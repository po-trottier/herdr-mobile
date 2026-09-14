/// The Device's Noise session: `Noise_XXpsk0_25519_ChaChaPoly_BLAKE2s` for first pairing and
/// `Noise_KK_25519_ChaChaPoly_BLAKE2s` for reconnect (`docs/13-security-pairing.md`
/// R-13-013, R-13-014, R-13-015), built from `cryptography` 2.9.0 primitives: `X25519` for
/// the Diffie-Hellman, `Chacha20.poly1305Aead` for the AEAD, and `Blake2s` for hashing and
/// the display fingerprint. No ready-made Dart Noise package offers these two patterns
/// (R-20-032), so this file implements the handshake state machine itself.
///
/// The Device is always the Noise **initiator**; the Host is always the responder
/// (R-13-071). This file therefore implements only the initiator side of both patterns —
/// there is no responder class here, and none is needed: the Rust Host plugin
/// (`crates/herdr-relay/src/noise.rs`) is the only responder in this system.
///
/// Every `HKDF`, `MixKey` and `MixKeyAndHash` call below routes through
/// `hmac_blake2s.dart`'s `hmacBlake2s`, never through `cryptography`'s `Hmac.blake2s()`
/// (R-13-072). The state machine mirrors `snow` 0.10.0's own source
/// (`handshakestate.rs`, `symmetricstate.rs`, `cipherstate.rs`,
/// `resolvers/default.rs`) exactly, including the ChaCha20-Poly1305 nonce layout (4 zero
/// bytes then the little-endian 64-bit counter) and the psk0-modified pattern's extra
/// `MixKey(e.public_key)` call on every `e` token. This file's `Noise_XXpsk0` half was
/// carried over, byte for byte, from the local interop proof
/// `app/test/spike/noise_client_test.dart` already ran against the real Rust Host
/// (`crates/herdr-relay/src/noise.rs`) this session (`docs/90-implementation-plan.md`
/// Phase 4, `WP-4`); `Noise_KK`'s message pattern (`-> e, es, ss` / `<- e, ee, se`, with
/// the initiator's static key pre-hashed before the responder's) is the Noise Protocol
/// Framework specification's own `KK` pattern, verified against
/// `noiseprotocol.org/noise.html` and matching `crates/herdr-relay/src/noise.rs`'s
/// `reconnect_handshake`.
///
/// Every Noise session MUST be established behind a passed biometric gate (R-13-064):
/// [NoiseXxPsk0Initiator.init] and [NoiseKkInitiator.init] both throw
/// [NoiseSessionLockedException] when the passed [BiometricGate.isLocked] is `true`. This
/// file never itself triggers the platform biometric prompt — that is
/// `BiometricGate.unlock()`'s job, called by a caller (the app root or router redirect,
/// per `biometric_gate.dart`'s own doc comment) before it ever reaches this file.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'biometric_gate.dart';
import 'hmac_blake2s.dart';

/// R-13-013, R-13-014: first pairing.
const String _xxPsk0ProtocolName = 'Noise_XXpsk0_25519_ChaChaPoly_BLAKE2s';

/// R-13-013, R-13-015: reconnect.
const String _kkProtocolName = 'Noise_KK_25519_ChaChaPoly_BLAKE2s';

/// The BLAKE2s digest length in bytes, also this cipher suite's Noise hash length.
const int _hashLen = 32;

/// The Curve25519 public-key and DH-output length in bytes.
const int _dhLen = 32;

/// The ChaCha20-Poly1305 authentication tag length in bytes.
const int _tagLen = 16;

/// Thrown by [NoiseXxPsk0Initiator.init] or [NoiseKkInitiator.init] when the passed
/// [BiometricGate] is locked (R-13-064). The caller must call
/// `BiometricGate.unlock()` and succeed before attempting the handshake again; this
/// exception is a defence-in-depth guard inside the Noise layer, not itself a way to raise
/// the platform prompt.
final class NoiseSessionLockedException implements Exception {
  const NoiseSessionLockedException();

  @override
  String toString() =>
      'a Noise session was attempted while the app is biometrically locked (R-13-064)';
}

/// One direction of the post-handshake transport cipher (`docs/13-security-pairing.md`
/// "### Chosen protocol"). Mirrors `crates/herdr-relay/src/noise.rs`'s `Transport`, which
/// wraps `snow::TransportState`'s per-direction `CipherState`: its own 32-byte key and its
/// own nonce counter starting at 0. A new Noise session produces new keys (R-11-033's
/// framing, though R-11-033 itself is about the separate application-layer `seq` field, not
/// this transport nonce).
final class NoiseCipher {
  NoiseCipher._(this._key);

  /// Builds a cipher directly from a 32-byte key, bypassing the handshake entirely. Not
  /// used by [NoiseXxPsk0Initiator]/[NoiseKkInitiator] themselves (both go through the
  /// private [NoiseCipher._] constructor via `_SymmetricState.split`); this exists so
  /// `relay.dart`'s own tests can build a [NoiseSession] with a fixed, pre-agreed key on
  /// both a fake test server and the [RelayConnection] under test, exercising the real
  /// AEAD frame encryption while stubbing only the handshake negotiation — which this
  /// file's own interop check already proves separately, byte for byte, against the real
  /// Rust responder.
  NoiseCipher.withKey(Uint8List key) : _key = key;

  final Uint8List _key;
  int _nonce = 0;

  /// Encrypts [plaintext] with this direction's key and the next nonce, returning
  /// ciphertext with the 16-byte Poly1305 tag appended.
  Future<Uint8List> encrypt(List<int> plaintext) async {
    final ciphertext = await _aeadEncrypt(_key, _nonce, const [], plaintext);
    _nonce++;
    return ciphertext;
  }

  /// Decrypts [ciphertextWithTag] (as produced by [encrypt] on the peer's matching
  /// direction) with the next nonce.
  Future<Uint8List> decrypt(List<int> ciphertextWithTag) async {
    final plaintext = await _aeadDecrypt(
      _key,
      _nonce,
      const [],
      ciphertextWithTag,
    );
    _nonce++;
    return plaintext;
  }
}

/// The outcome of a completed Noise handshake: the two independent transport ciphers and
/// the peer's pinned static public key, from which [hostFingerprint] derives the display
/// string R-13-040/R-13-041 specify. `relay.dart` (`WP-14-a`) owns turning the application
/// frame envelope's JSON bytes into and out of [send]/[receive] ciphertext; this file does
/// not know about the frame envelope at all.
final class NoiseSession {
  const NoiseSession({
    required this.send,
    required this.receive,
    required this.remoteStaticPublicKey,
  });

  final NoiseCipher send;
  final NoiseCipher receive;

  /// The peer's static Curve25519 public key, learned during the handshake
  /// (`Noise_XXpsk0`) or already known and just confirmed (`Noise_KK`). The caller MUST
  /// pin this for reconnect (R-13-038, R-13-048) and MAY derive [hostFingerprint] from it
  /// for display.
  final Uint8List remoteStaticPublicKey;
}

/// The Device (initiator, R-13-071) side of `Noise_XXpsk0_25519_ChaChaPoly_BLAKE2s`
/// (R-13-013, R-13-014), used for first pairing. Call [init], then [writeMessage1],
/// [readMessage2], [writeMessage3], and finally [finish] to obtain the transport
/// [NoiseSession] — one call each, in that exact order, matching the three-message `XX`
/// pattern.
final class NoiseXxPsk0Initiator {
  final _SymmetricState _state = _SymmetricState(_xxPsk0ProtocolName);
  late final SimpleKeyPair _localStatic;
  late SimpleKeyPair _localEphemeral;
  Uint8List? _remoteEphemeral;
  Uint8List? _remoteStatic;

  /// Initializes the handshake state. MUST be called before [writeMessage1]. Throws
  /// [NoiseSessionLockedException] when [gate] is locked (R-13-064).
  Future<void> init({
    required BiometricGate gate,
    required SimpleKeyPair localStatic,
  }) async {
    _requireUnlocked(gate);
    _localStatic = localStatic;
    await _state.initialize(prologue: const []);
  }

  /// Message 1: `psk, e` (R-13-014's `psk0` modifier inserts `psk` before the first `e`).
  /// [psk] is [pskFromPhrase]'s 32-byte output.
  Future<Uint8List> writeMessage1(Uint8List psk) async {
    await _state.mixKeyAndHash(psk);
    _localEphemeral = await X25519().newKeyPair();
    final ePub = await _publicKeyBytes(_localEphemeral);
    await _state.mixHash(ePub);
    // Every `e` token in a psk-modified pattern also calls MixKey (Noise spec §5: "If
    // part of a psk handshake, calls MixKey(e.public_key)"), not only the message that
    // carries the `psk` token itself.
    await _state.mixKey(ePub);
    final tag = await _state.encryptAndHash(const []);
    return Uint8List.fromList([...ePub, ...tag]);
  }

  /// Message 2: `e, ee, s, es`, received from the Host.
  Future<void> readMessage2(Uint8List message) async {
    var offset = 0;
    final re = message.sublist(offset, offset + _dhLen);
    offset += _dhLen;
    _remoteEphemeral = re;
    await _state.mixHash(re);
    await _state.mixKey(re);

    final eeShared = await _dh(_localEphemeral, re);
    await _state.mixKey(eeShared);

    final sLen = _state.hasKey ? _dhLen + _tagLen : _dhLen;
    final sCiphertext = message.sublist(offset, offset + sLen);
    offset += sLen;
    final rs = await _state.decryptAndHash(sCiphertext);
    _remoteStatic = rs;

    // R-13-071 (Device = initiator): `es` = DH(initiator ephemeral, responder static).
    final esShared = await _dh(_localEphemeral, rs);
    await _state.mixKey(esShared);

    final remainder = message.sublist(offset);
    await _state.decryptAndHash(
      remainder,
    ); // the (always-empty) handshake payload
  }

  /// Message 3: `s, se`, sent by the Device.
  Future<Uint8List> writeMessage3() async {
    final sPub = await _publicKeyBytes(_localStatic);
    final sCiphertext = await _state.encryptAndHash(sPub);
    // R-13-071 (Device = initiator): `se` = DH(initiator static, responder ephemeral).
    final seShared = await _dh(_localStatic, _remoteEphemeral!);
    await _state.mixKey(seShared);
    final tag = await _state.encryptAndHash(const []);
    return Uint8List.fromList([...sCiphertext, ...tag]);
  }

  /// Splits into the transport [NoiseSession]. MUST be called only after [writeMessage3].
  Future<NoiseSession> finish() async {
    final (send, receive) = await _state.split();
    return NoiseSession(
      send: send,
      receive: receive,
      remoteStaticPublicKey: _remoteStatic!,
    );
  }
}

/// The Device (initiator, R-13-071) side of `Noise_KK_25519_ChaChaPoly_BLAKE2s`
/// (R-13-013, R-13-015), used for reconnect: both peers already know each other's static
/// public key from the first pairing (R-13-038, R-13-048), so no phrase and no PSK is
/// needed. Call [init], then [writeMessage1] and [readMessage2], and finally [finish] to
/// obtain the transport [NoiseSession] — matching the two-message `KK` pattern
/// (`-> e, es, ss` / `<- e, ee, se`).
final class NoiseKkInitiator {
  final _SymmetricState _state = _SymmetricState(_kkProtocolName);
  late final SimpleKeyPair _localStatic;
  late final Uint8List _remoteStatic;
  late SimpleKeyPair _localEphemeral;

  /// Initializes the handshake state, including the `KK` pre-message hashing: the Noise
  /// specification's `Initialize` step MixHashes the initiator's static key first, then
  /// the responder's (in that order regardless of which side is computing it), because
  /// `Noise_KK`'s two pre-message lines are `-> s` then `<- s`. MUST be called before
  /// [writeMessage1]. Throws [NoiseSessionLockedException] when [gate] is locked
  /// (R-13-064).
  Future<void> init({
    required BiometricGate gate,
    required SimpleKeyPair localStatic,
    required Uint8List remoteStaticPublicKey,
  }) async {
    _requireUnlocked(gate);
    _localStatic = localStatic;
    _remoteStatic = remoteStaticPublicKey;
    await _state.initialize(prologue: const []);
    final localStaticPub = await _publicKeyBytes(localStatic);
    await _state.mixHash(localStaticPub);
    await _state.mixHash(_remoteStatic);
  }

  /// Message 1: `e, es, ss`, sent by the Device.
  Future<Uint8List> writeMessage1() async {
    _localEphemeral = await X25519().newKeyPair();
    final ePub = await _publicKeyBytes(_localEphemeral);
    await _state.mixHash(ePub);

    final esShared = await _dh(_localEphemeral, _remoteStatic);
    await _state.mixKey(esShared);
    final ssShared = await _dh(_localStatic, _remoteStatic);
    await _state.mixKey(ssShared);

    final tag = await _state.encryptAndHash(const []);
    return Uint8List.fromList([...ePub, ...tag]);
  }

  /// Message 2: `e, ee, se`, received from the Host.
  Future<void> readMessage2(Uint8List message) async {
    final re = message.sublist(0, _dhLen);
    await _state.mixHash(re);

    final eeShared = await _dh(_localEphemeral, re);
    await _state.mixKey(eeShared);
    // `se` = DH(initiator static, responder ephemeral) — the same naming convention
    // `writeMessage3` in [NoiseXxPsk0Initiator] uses for the same token.
    final seShared = await _dh(_localStatic, re);
    await _state.mixKey(seShared);

    final remainder = message.sublist(_dhLen);
    await _state.decryptAndHash(
      remainder,
    ); // the (always-empty) handshake payload
  }

  /// Splits into the transport [NoiseSession]. MUST be called only after [readMessage2].
  Future<NoiseSession> finish() async {
    final (send, receive) = await _state.split();
    return NoiseSession(
      send: send,
      receive: receive,
      remoteStaticPublicKey: _remoteStatic,
    );
  }
}

/// The Noise `SymmetricState`: `h`, `ck`, and the current cipher key, shared by
/// [NoiseXxPsk0Initiator] and [NoiseKkInitiator] so the `MixHash`/`MixKey`/
/// `MixKeyAndHash`/`EncryptAndHash`/`DecryptAndHash` operations exist in exactly one
/// place. Mirrors `snow::SymmetricState` exactly, including that `MixKeyAndHash` does NOT
/// itself set `hasKey` — in `Noise_XXpsk0` the `e` token that always immediately follows
/// `psk` sets it via [mixKey] instead, matching a finding this session's Phase 4 spike
/// (`app/test/spike/noise_client_test.dart`) already verified against `snow`'s own source.
final class _SymmetricState {
  _SymmetricState(this._protocolName);

  final String _protocolName;

  late Uint8List _h;
  late Uint8List _ck;
  bool hasKey = false;
  Uint8List? _cipherKey;
  int _nonce = 0;

  Future<void> initialize({required List<int> prologue}) async {
    final nameBytes = utf8.encode(_protocolName);
    if (nameBytes.length <= _hashLen) {
      _h = Uint8List(_hashLen)..setRange(0, nameBytes.length, nameBytes);
    } else {
      _h = Uint8List.fromList((await Blake2s().hash(nameBytes)).bytes);
    }
    _ck = Uint8List.fromList(_h);
    // The Noise spec's Initialize() always calls MixHash(prologue), even when the
    // prologue is empty (as it is here: this codebase never sets one).
    await mixHash(prologue);
  }

  Future<void> mixHash(List<int> data) async {
    _h = Uint8List.fromList((await Blake2s().hash([..._h, ...data])).bytes);
  }

  Future<void> mixKey(List<int> data) async {
    final outputs = await _hkdf(_ck, data, 2);
    _ck = outputs[0];
    _cipherKey = outputs[1];
    _nonce = 0;
    hasKey = true;
  }

  Future<void> mixKeyAndHash(List<int> data) async {
    final outputs = await _hkdf(_ck, data, 3);
    _ck = outputs[0];
    await mixHash(outputs[1]);
    _cipherKey = outputs[2];
    _nonce = 0;
  }

  Future<Uint8List> encryptAndHash(List<int> plaintext) async {
    Uint8List ciphertext;
    if (hasKey) {
      ciphertext = await _aeadEncrypt(_cipherKey!, _nonce, _h, plaintext);
      _nonce++;
    } else {
      ciphertext = Uint8List.fromList(plaintext);
    }
    await mixHash(ciphertext);
    return ciphertext;
  }

  Future<Uint8List> decryptAndHash(List<int> data) async {
    Uint8List plaintext;
    if (hasKey) {
      plaintext = await _aeadDecrypt(_cipherKey!, _nonce, _h, data);
      _nonce++;
    } else {
      plaintext = Uint8List.fromList(data);
    }
    await mixHash(data);
    return plaintext;
  }

  /// Splits into the two transport ciphers. The Device is always the Noise initiator
  /// (R-13-071), so the assignment is unambiguous with no responder-side call site
  /// anywhere in this file: the first HKDF output is the send key, the second is the
  /// receive key (mirroring `snow::TransportState::write_message`/`read_message`).
  Future<(NoiseCipher, NoiseCipher)> split() async {
    final outputs = await _hkdf(_ck, const [], 2);
    return (NoiseCipher._(outputs[0]), NoiseCipher._(outputs[1]));
  }
}

/// Derives the 32-byte `Noise_XXpsk0` pre-shared key from the canonical hyphenated pairing
/// phrase, as `BLAKE2s-256(canonical_phrase_utf8)` — the full digest, no truncation
/// (R-13-024). Mirrors `crates/herdr-relay/src/noise.rs`'s `psk_from_phrase` exactly.
Future<Uint8List> pskFromPhrase(String canonicalPhrase) async {
  final digest = await Blake2s().hash(utf8.encode(canonicalPhrase));
  return Uint8List.fromList(digest.bytes);
}

/// The display fingerprint of a static public key (R-13-040, R-13-041):
/// `BLAKE2s-256(staticPublicKey)`, first 8 bytes, lowercase hex, in four hyphen-separated
/// groups of four hex digits — for example `3f9a-1c04-be77-20d5`. Used for both the Host
/// fingerprint the Device displays and the Device fingerprint the Host displays (this file
/// only needs the former; the latter is the Host's own, symmetric computation).
Future<String> hostFingerprint(Uint8List staticPublicKey) async {
  final digest = await Blake2s().hash(staticPublicKey);
  final firstEightBytes = digest.bytes.sublist(0, 8);
  final hex = firstEightBytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 4)}-${hex.substring(4, 8)}-'
      '${hex.substring(8, 12)}-${hex.substring(12, 16)}';
}

void _requireUnlocked(BiometricGate gate) {
  if (gate.isLocked) {
    throw const NoiseSessionLockedException();
  }
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
/// little-endian 64-bit counter (matches `snow`'s
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
  final tagStart = ciphertextWithTag.length - _tagLen;
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

/// The Noise spec's HKDF (§4.3): `HMAC-BLAKE2s`-based (R-13-072, `hmac_blake2s.dart`),
/// `numOutputs` in `{2, 3}`. Mirrors `snow::types::Hash::hkdf`'s default trait
/// implementation.
Future<List<Uint8List>> _hkdf(
  Uint8List chainingKey,
  List<int> ikm,
  int numOutputs,
) async {
  final tempKey = await hmacBlake2s(chainingKey, ikm);
  final out1 = await hmacBlake2s(tempKey, const [1]);
  if (numOutputs == 1) {
    return [Uint8List.fromList(out1)];
  }
  final out2 = await hmacBlake2s(tempKey, [...out1, 2]);
  if (numOutputs == 2) {
    return [Uint8List.fromList(out1), Uint8List.fromList(out2)];
  }
  final out3 = await hmacBlake2s(tempKey, [...out2, 3]);
  return [
    Uint8List.fromList(out1),
    Uint8List.fromList(out2),
    Uint8List.fromList(out3),
  ];
}
