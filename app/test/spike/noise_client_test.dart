/// `docs/90-implementation-plan.md` Phase 4 (`WP-4`): the Device half of the local
/// `Noise_XXpsk0_25519_ChaChaPoly_BLAKE2s` interop proof `WP-14-a`/`WP-14-b`'s `Needs.`
/// lines read from `WP-4` — never Phase 4's own package, and never its `Done when`
/// line, which needs a deployed public relay reached over real WSS from a phone on
/// cellular data (infrastructure this workstation does not have).
///
/// This file starts two real, locally-run subprocesses on `127.0.0.1` (never a public
/// deployment):
///   1. `cargo run -p herdr-relay-hub` — the real relay router, listening on
///      `127.0.0.1:$_relayPort`.
///   2. `cargo run -p herdr-relay --bin spike-noise-host` — the Host (Noise responder)
///      side of the handshake (`crates/herdr-relay/src/noise.rs`,
///      `crates/herdr-relay/src/bin/spike-noise-host.rs`), which registers on
///      `/host/$_handle` and waits.
///
/// Then this test itself connects to `/device/$_handle` with `web_socket_channel` and
/// runs the Device (Noise initiator, R-13-071) side of `Noise_XXpsk0` from `cryptography`
/// 2.9.0 primitives only (`X25519`, `Chacha20.poly1305Aead`, `Blake2s`, `Hmac(Blake2s())`
/// for the Noise-spec HKDF) — no ready-made Noise package, per R-20-032 and
/// `docs/13-security-pairing.md` "### Libraries". The hand-rolled state machine below
/// mirrors `snow` 0.10.0's own source exactly (`handshakestate.rs`, `symmetricstate.rs`,
/// `cipherstate.rs`, `resolvers/default.rs`, read directly from the vendored crate to
/// confirm every step, token order, and the ChaCha20-Poly1305 nonce layout: 4 zero bytes
/// then the little-endian 64-bit counter).
///
/// This file is not on any other work package's owned-paths list (R-90-016): it is a
/// throwaway spike proof, the Dart-side analogue of this crate's own
/// `src/bin/spike-*.rs` convention, not Phase 14's production
/// `app/lib/services/noise.dart` (`WP-14-b`, not yet built).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/io.dart';

/// The docs' own worked pairing phrase (`docs/11-relay-protocol.md` §8.1), also used by
/// `crates/herdr-relay/src/noise.rs`'s and `crates/herdr-relay-hub/tests/ciphertext_only.rs`'s
/// tests, so a human comparing the three files sees one shared fixture.
const _phrase = 'remedy-tapestry-hubcap-oversleep-jailbird-kinetic';
const _handle = 'n6Loxf94CfyIO6hOxlaHvA';
const _relayPort = 18743;
const _metricsPort = 19091;
const _subprotocol = 'herdr-relay.v1';

/// MUST match `HOST_GREETING` in `crates/herdr-relay/src/bin/spike-noise-host.rs`
/// exactly: this test asserts its decrypted `pane_frame`-stand-in equals this literal.
const _expectedHostGreeting =
    'herdr-relay-noise-interop: hello from the Rust Host';
const _deviceReply = 'herdr-relay-noise-interop: hello from the Dart Device';

void main() {
  final cratesDir = Directory(
    '${Directory.current.path}${Platform.pathSeparator}..${Platform.pathSeparator}crates',
  );

  group('Noise_XXpsk0 local interop verdict (WP-14-a/WP-14-b Needs. -> WP-4)', () {
    late Process hubProcess;
    late Process hostProcess;
    final hostStdoutLines = <String>[];

    setUpAll(() async {
      expect(
        cratesDir.existsSync(),
        isTrue,
        reason: 'expected the Rust workspace at ${cratesDir.path}',
      );

      hubProcess = await Process.start(
        'cargo',
        ['run', '-p', 'herdr-relay-hub'],
        workingDirectory: cratesDir.path,
        environment: {
          'HERDR_RELAY_LISTEN': '127.0.0.1:$_relayPort',
          'HERDR_RELAY_METRICS_LISTEN': '127.0.0.1:$_metricsPort',
        },
      );
      hubProcess.stdout
          .transform(utf8.decoder)
          .listen((line) => stdout.write('[hub] $line'));
      hubProcess.stderr
          .transform(utf8.decoder)
          .listen((line) => stdout.write('[hub:err] $line'));
      await _waitForHealthz();

      hostProcess = await Process.start(
        'cargo',
        ['run', '-p', 'herdr-relay', '--bin', 'spike-noise-host'],
        workingDirectory: cratesDir.path,
        environment: {
          'RELAY_ADDR': '127.0.0.1:$_relayPort',
          'HANDLE': _handle,
          'PHRASE': _phrase,
        },
      );
      hostProcess.stderr
          .transform(utf8.decoder)
          .listen((line) => stdout.write('[host:err] $line'));
      final hostStdoutDone = Completer<void>();
      hostProcess.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            // Not echoed: the Host reports booleans, never plaintext or keys.
            hostStdoutLines.add(line);
          }, onDone: hostStdoutDone.complete);
      await _waitForHostEvent(
        hostStdoutLines,
        'host_registered',
        const Duration(seconds: 60),
      );
      addTearDown(() async {
        hubProcess.kill();
        hostProcess.kill();
        await hostStdoutDone.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () {},
        );
      });
    });

    test('Device (initiator) completes Noise_XXpsk0 against the Rust Host and decrypts its greeting', () async {
      final channel = IOWebSocketChannel.connect(
        'ws://127.0.0.1:$_relayPort/device/$_handle',
        protocols: [_subprotocol],
      );
      final messages = StreamIterator(channel.stream);
      addTearDown(() => channel.sink.close());

      // R-11-114: the Device registration frame.
      channel.sink.add(jsonEncode({'type': 'device_register', 'protocol': 1}));
      await messages.moveNext();
      final joined = messages.current as String;
      expect(joined, contains('session_joined'));

      // R-13-024: the PSK is derived from the phrase, never the raw phrase bytes.
      final psk = Uint8List.fromList(
        (await Blake2s().hash(utf8.encode(_phrase))).bytes,
      );
      expect(psk, hasLength(32));

      final deviceStatic = await X25519().newKeyPair();
      final handshake = _NoiseXxPsk0Initiator();
      await handshake.init(deviceStatic);

      final msg1 = await handshake.writeMessage1(psk);
      channel.sink.add(msg1);

      await messages.moveNext();
      final msg2 = Uint8List.fromList(messages.current as List<int>);
      await handshake.readMessage2(msg2);

      final msg3 = await handshake.writeMessage3();
      channel.sink.add(msg3);

      final split = await handshake.split();
      final sendCipher = split.$1;
      final recvCipher = split.$2;
      final hostStaticKey = split.$3;
      expect(hostStaticKey, hasLength(32));

      await messages.moveNext();
      final greetingCiphertext = Uint8List.fromList(
        messages.current as List<int>,
      );
      // The cipher suite is AEAD (R-13-013): ciphertext must never equal plaintext.
      expect(
        greetingCiphertext,
        isNot(equals(utf8.encode(_expectedHostGreeting))),
      );
      final greetingPlaintext = await recvCipher.decrypt(greetingCiphertext);
      final decryptedText = utf8.decode(greetingPlaintext);

      // The `expect` below is the proof the handshake round-tripped between `snow`
      // and `cryptography`; the plaintext is never printed (never-log rule).
      expect(decryptedText, _expectedHostGreeting);

      final replyCiphertext = await sendCipher.encrypt(
        utf8.encode(_deviceReply),
      );
      channel.sink.add(replyCiphertext);

      // Let the Host process decrypt the reply and exit, then fold its own stdout
      // into this test's evidence (the Rust-side half of the bidirectional proof).
      final exitCode = await hostProcess.exitCode.timeout(
        const Duration(seconds: 30),
      );
      expect(
        exitCode,
        0,
        reason:
            'the Rust Host process must exit cleanly: ${hostStdoutLines.join('\n')}',
      );
      final replyDecryptedLine = hostStdoutLines.firstWhere(
        (line) => line.contains('reply_decrypted'),
        orElse: () => '',
      );
      expect(
        replyDecryptedLine,
        isNot(isEmpty),
        reason: 'the Host must report decrypting the reply',
      );
      final replyDecrypted =
          jsonDecode(replyDecryptedLine) as Map<String, dynamic>;
      expect(
        replyDecrypted['reply_matches_expected'],
        isTrue,
        reason: 'the Rust Host compares the decrypted reply to the literal in place',
      );

      await messages.cancel();
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}

Future<void> _waitForHealthz() async {
  final client = HttpClient();
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    try {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:$_relayPort/healthz'),
      );
      final response = await request.close();
      if (response.statusCode == 200) {
        await response.drain<void>();
        client.close();
        return;
      }
      await response.drain<void>();
    } on Exception {
      // The relay has not started listening yet; retry.
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  client.close();
  fail(
    'the local herdr-relay-hub instance never became healthy on 127.0.0.1:$_relayPort',
  );
}

Future<void> _waitForHostEvent(
  List<String> lines,
  String event,
  Duration timeout,
) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (lines.any((line) => line.contains(event))) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail(
    'the Rust Host process never reported "$event" within $timeout: ${lines.join('\n')}',
  );
}

/// The Device (initiator) side of `Noise_XXpsk0_25519_ChaChaPoly_BLAKE2s`
/// (`docs/13-security-pairing.md` R-13-013, R-13-014, R-13-071), built from
/// `cryptography` 2.9.0 primitives only. Every step below is verified against
/// `snow` 0.10.0's own source (see this file's doc comment) so the two
/// implementations agree byte-for-byte.
class _NoiseXxPsk0Initiator {
  static const _protocolName = 'Noise_XXpsk0_25519_ChaChaPoly_BLAKE2s';
  static const _hashLen = 32;
  static const _tagLen = 16;

  late Uint8List _h;
  late Uint8List _ck;
  bool _hasKey = false;
  Uint8List? _cipherKey;
  int _nonce = 0;

  late SimpleKeyPair _localStatic;
  late SimpleKeyPair _localEphemeral;
  Uint8List? _remoteEphemeral;
  Uint8List? _remoteStatic;

  Future<void> init(SimpleKeyPair localStatic) async {
    _localStatic = localStatic;
    final nameBytes = utf8.encode(_protocolName);
    if (nameBytes.length <= _hashLen) {
      _h = Uint8List(_hashLen)..setRange(0, nameBytes.length, nameBytes);
    } else {
      _h = Uint8List.fromList((await Blake2s().hash(nameBytes)).bytes);
    }
    _ck = Uint8List.fromList(_h);
    // The Noise spec's Initialize() always calls MixHash(prologue), even when the
    // prologue is empty (as it is here: `snow::Builder` defaults `prologue` to `&[]`).
    await _mixHash(const []);
  }

  /// Message 1: `psk, e` (R-13-014's `psk0` modifier inserts `psk` at position 0).
  Future<Uint8List> writeMessage1(Uint8List psk) async {
    await _mixKeyAndHash(psk);
    _localEphemeral = await X25519().newKeyPair();
    final ePub = await _publicKeyBytes(_localEphemeral);
    await _mixHash(ePub);
    // Every `e` token in a PSK-modified pattern also calls MixKey (Noise spec §5,
    // "If this is a PSK handshake, MixKey(e.public_key) is also called"), for every
    // message in the pattern, not only the one carrying the `psk` token.
    await _mixKey(ePub);
    final tag = await _encryptAndHash(const []);
    return Uint8List.fromList([...ePub, ...tag]);
  }

  /// Message 2: `e, ee, s, es`.
  Future<void> readMessage2(Uint8List message) async {
    var offset = 0;
    final re = message.sublist(offset, offset + 32);
    offset += 32;
    _remoteEphemeral = re;
    await _mixHash(re);
    await _mixKey(re);

    final eeShared = await _dh(_localEphemeral, re);
    await _mixKey(eeShared);

    final sLen = _hasKey ? 32 + _tagLen : 32;
    final sCiphertext = message.sublist(offset, offset + sLen);
    offset += sLen;
    final rs = await _decryptAndHash(sCiphertext);
    _remoteStatic = rs;

    // R-13-071 (Device = initiator): `es` = DH(initiator ephemeral, responder static).
    final esShared = await _dh(_localEphemeral, rs);
    await _mixKey(esShared);

    final remainder = message.sublist(offset);
    await _decryptAndHash(
      remainder,
    ); // discards the (always-empty) handshake payload
  }

  /// Message 3: `s, se`.
  Future<Uint8List> writeMessage3() async {
    final sPub = await _publicKeyBytes(_localStatic);
    final sCiphertext = await _encryptAndHash(sPub);
    // R-13-071 (Device = initiator): `se` = DH(initiator static, responder ephemeral).
    final seShared = await _dh(_localStatic, _remoteEphemeral!);
    await _mixKey(seShared);
    final tag = await _encryptAndHash(const []);
    return Uint8List.fromList([...sCiphertext, ...tag]);
  }

  /// Splits into the two transport ciphers. The initiator sends with the first HKDF
  /// output and receives with the second (`snow::TransportState::write_message`/
  /// `read_message`); returns `(send, recv, hostStaticPublicKey)`.
  Future<(_TransportCipher, _TransportCipher, Uint8List)> split() async {
    final outputs = await _hkdf(_ck, const [], 2);
    return (
      _TransportCipher(outputs[0]),
      _TransportCipher(outputs[1]),
      _remoteStatic!,
    );
  }

  Future<void> _mixHash(List<int> data) async {
    final hash = await Blake2s().hash([..._h, ...data]);
    _h = Uint8List.fromList(hash.bytes);
  }

  Future<void> _mixKey(List<int> data) async {
    final outputs = await _hkdf(_ck, data, 2);
    _ck = outputs[0];
    _cipherKey = outputs[1];
    _nonce = 0;
    _hasKey = true;
  }

  Future<void> _mixKeyAndHash(List<int> data) async {
    final outputs = await _hkdf(_ck, data, 3);
    _ck = outputs[0];
    await _mixHash(outputs[1]);
    _cipherKey = outputs[2];
    _nonce = 0;
    // Matches `snow::SymmetricState::mix_key_and_hash` exactly: `hasKey` is NOT set
    // here. In `Noise_XXpsk0`, the `e` token that always immediately follows `psk`
    // sets it via `_mixKey` instead.
  }

  Future<Uint8List> _encryptAndHash(List<int> plaintext) async {
    Uint8List ciphertext;
    if (_hasKey) {
      ciphertext = await _aeadEncrypt(_cipherKey!, _nonce, _h, plaintext);
      _nonce++;
    } else {
      ciphertext = Uint8List.fromList(plaintext);
    }
    await _mixHash(ciphertext);
    return ciphertext;
  }

  Future<Uint8List> _decryptAndHash(List<int> data) async {
    Uint8List plaintext;
    if (_hasKey) {
      plaintext = await _aeadDecrypt(_cipherKey!, _nonce, _h, data);
      _nonce++;
    } else {
      plaintext = Uint8List.fromList(data);
    }
    await _mixHash(data);
    return plaintext;
  }
}

/// One direction of the post-handshake transport cipher: its own 32-byte key and its
/// own nonce counter starting at 0 (`snow::CipherStates` — `split()` produces two
/// independent `CipherState`s, matching `docs/11-relay-protocol.md` R-11-033's "a new
/// Noise session has new keys" framing for the concept, though R-11-033 itself is about
/// the separate application-layer `seq` field, not this transport nonce).
class _TransportCipher {
  _TransportCipher(this._key);

  final Uint8List _key;
  int _nonce = 0;

  Future<Uint8List> encrypt(List<int> plaintext) async {
    final ciphertext = await _aeadEncrypt(_key, _nonce, const [], plaintext);
    _nonce++;
    return ciphertext;
  }

  Future<Uint8List> decrypt(List<int> ciphertext) async {
    final plaintext = await _aeadDecrypt(_key, _nonce, const [], ciphertext);
    _nonce++;
    return plaintext;
  }
}

/// The Noise spec's HKDF (§4.3): `HMAC-BLAKE2s`-based, `numOutputs` in `{2, 3}`,
/// verified against `snow::types::Hash::hkdf`'s default trait implementation.
Future<List<Uint8List>> _hkdf(
  Uint8List chainingKey,
  List<int> ikm,
  int numOutputs,
) async {
  final tempKey = await _hmacBlake2s(chainingKey, ikm);
  final out1 = await _hmacBlake2s(tempKey, const [1]);
  if (numOutputs == 1) return [out1];
  final out2 = await _hmacBlake2s(tempKey, [...out1, 2]);
  if (numOutputs == 2) return [out1, out2];
  final out3 = await _hmacBlake2s(tempKey, [...out2, 3]);
  return [out1, out2, out3];
}

/// **Finding:** `cryptography` 2.9.0's `Blake2s.blockLengthInBytes` (in
/// `lib/src/cryptography/algorithms.dart`) returns `32`, but RFC 7693's BLAKE2s
/// block length is `64` (same as `snow`'s `HashBLAKE2s::block_len()`, verified
/// against `snow-0.10.0/src/resolvers/default.rs`). Because HMAC's inner/outer
/// padding length is exactly the block length, the package's own `Hmac(Blake2s())`
/// pads to the wrong width and computes a non-standard, `snow`-incompatible MAC —
/// confirmed by cross-checking three independent implementations (`snow`, a `pyca
/// cryptography` Python reference, and this function) against the same fixed
/// input: only a 64-byte block length reproduces `snow`'s output. This hand-rolled
/// HMAC (RFC 2104, `cryptography`'s own `Blake2s().hash()` for the underlying
/// digest) works around the bug; `docs/13-security-pairing.md`'s owner should
/// weigh this before Phase 14 depends on `Hmac(Blake2s())` for anything.
Future<Uint8List> _hmacBlake2s(List<int> key, List<int> data) async {
  const blockLen = 64;
  var paddedKey = Uint8List.fromList(key);
  if (paddedKey.length > blockLen) {
    paddedKey = Uint8List.fromList((await Blake2s().hash(paddedKey)).bytes);
  }
  if (paddedKey.length < blockLen) {
    paddedKey = Uint8List(blockLen)..setRange(0, paddedKey.length, paddedKey);
  }
  final innerPad = Uint8List(blockLen);
  final outerPad = Uint8List(blockLen);
  for (var i = 0; i < blockLen; i++) {
    innerPad[i] = paddedKey[i] ^ 0x36;
    outerPad[i] = paddedKey[i] ^ 0x5c;
  }
  final inner = (await Blake2s().hash([...innerPad, ...data])).bytes;
  final outer = await Blake2s().hash([...outerPad, ...inner]);
  return Uint8List.fromList(outer.bytes);
}

Future<Uint8List> _publicKeyBytes(SimpleKeyPair keyPair) async {
  final public = await keyPair.extractPublicKey();
  return Uint8List.fromList(public.bytes);
}

Future<Uint8List> _dh(
  SimpleKeyPair local,
  Uint8List remotePublicKeyBytes,
) async {
  final shared = await X25519().sharedSecretKey(
    keyPair: local,
    remotePublicKey: SimplePublicKey(
      remotePublicKeyBytes,
      type: KeyPairType.x25519,
    ),
  );
  return Uint8List.fromList(await shared.extractBytes());
}

/// ChaCha20-Poly1305 with the Noise spec's nonce layout: 4 zero bytes then the
/// little-endian 64-bit counter (verified against `snow`'s
/// `resolvers/default.rs::CipherChaChaPoly::encrypt`/`decrypt`).
Uint8List _nonceBytes(int counter) {
  final nonce = Uint8List(12);
  ByteData.sublistView(nonce).setUint64(4, counter, Endian.little);
  return nonce;
}

Future<Uint8List> _aeadEncrypt(
  Uint8List key,
  int nonceCounter,
  List<int> associatedData,
  List<int> plaintext,
) async {
  final secretBox = await Chacha20.poly1305Aead().encrypt(
    plaintext,
    secretKey: SecretKey(key),
    nonce: _nonceBytes(nonceCounter),
    aad: associatedData,
  );
  return Uint8List.fromList([...secretBox.cipherText, ...secretBox.mac.bytes]);
}

Future<Uint8List> _aeadDecrypt(
  Uint8List key,
  int nonceCounter,
  List<int> associatedData,
  List<int> ciphertextWithTag,
) async {
  final tagStart = ciphertextWithTag.length - 16;
  final secretBox = SecretBox(
    ciphertextWithTag.sublist(0, tagStart),
    nonce: _nonceBytes(nonceCounter),
    mac: Mac(ciphertextWithTag.sublist(tagStart)),
  );
  final plaintext = await Chacha20.poly1305Aead().decrypt(
    secretBox,
    secretKey: SecretKey(key),
    aad: associatedData,
  );
  return Uint8List.fromList(plaintext);
}
