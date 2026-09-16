/// Proves `app/lib/services/pairing.dart` (`WP-15-a`): each of the six phrase error codes
/// (R-13-027) is raised by the matching malformed input, the pairing URI codec accepts and
/// rejects exactly what `docs/11-relay-protocol.md` §9.5's table names, manual entry and QR
/// entry converge on one identical [PairingInput] record (R-13-026, R-11-140, R-03-071), the
/// four real EFF long-list entries with an internal hyphen (`drop-down`, `felt-tip`,
/// `t-shirt`, `yo-yo`) segment correctly, and [PairingAttemptTracker] fires
/// `phrase_attempts` only on the third consecutive failure against the same phrase
/// (R-13-023).
///
/// Reads the real, build-time-bundled EFF word list from disk
/// (`assets/wordlists/eff_large_wordlist.txt`, relative to `app/`, `flutter test`'s working
/// directory — the same precedent `app/test/models/vectors_test.dart` already uses for a
/// repo-relative fixture) rather than a synthetic fixture, so every word-membership assertion
/// below exercises the real 7776-entry list, not a hand-picked stand-in.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart' show Err, Ok;
import 'package:herdr_mobile/models/frame.dart' show frameProtocolVersion;
import 'package:herdr_mobile/models/messages/device_info.dart' show DeviceInfo;
import 'package:herdr_mobile/models/messages/platform.dart'
    as wire
    show Platform;
import 'package:herdr_mobile/services/biometric_gate.dart' show BiometricGate;
import 'package:herdr_mobile/services/connectivity.dart'
    show ConnectivityWatcher;
import 'package:herdr_mobile/services/keystore.dart'
    show HostSecrets, KeystoreService;
import 'package:herdr_mobile/services/noise.dart'
    show NoiseSession, NoiseCipher;
import 'package:herdr_mobile/services/origin.dart';
import 'package:herdr_mobile/services/pairing.dart';
import 'package:herdr_mobile/services/plain_store.dart';
import 'package:herdr_mobile/services/relay.dart'
    show
        NoiseHandshakeMode,
        RelayConnectException,
        RelayConnectFailure,
        RelayConnection,
        RelayConnected;
import 'package:local_auth/local_auth.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Relative to the package root, which is `flutter test`'s working directory (`app/`).
const String _wordlistPath = 'assets/wordlists/eff_large_wordlist.txt';

List<String> _loadRealWords() =>
    File(_wordlistPath)
        .readAsLinesSync()
        .where((line) => line.isNotEmpty)
        .toList();

class _MockKeystoreService extends Mock implements KeystoreService {}

class _MockPlainStore extends Mock implements PlainStore {}

class _MockLocalAuthentication extends Mock implements LocalAuthentication {}

class _MockConnectivity extends Mock implements Connectivity {}

// The harness mirrors `relay_test.dart`'s own seams: a biometric gate unlocked with a
// mock keystore read, a no-op connectivity watcher, and a local WebSocket server standing
// in for the relay.

ConnectivityWatcher _noOpConnectivityWatcher() {
  final connectivity = _MockConnectivity();
  when(() => connectivity.onConnectivityChanged)
      .thenAnswer((_) => const Stream<List<ConnectivityResult>>.empty());
  return ConnectivityWatcher(connectivity: connectivity);
}

Future<BiometricGate> _unlockedGate() async {
  final localAuth = _MockLocalAuthentication();
  final keystore = _MockKeystoreService();
  final keyPair = await X25519().newKeyPair();
  when(
    () =>
        localAuth.authenticate(localizedReason: any(named: 'localizedReason')),
  ).thenAnswer((_) async => true);
  when(() => keystore.deviceKeyPair()).thenAnswer((_) async => Ok(keyPair));
  final gate = BiometricGate(
    appLockEnabled: true,
    localAuth: localAuth,
    keystore: keystore,
    setNativeLocked: (_) {},
  );
  final result = await gate.unlock();
  expect(result, isA<Ok<void>>());
  return gate;
}

const _testDeviceInfo = DeviceInfo(
  protocol: frameProtocolVersion,
  deviceId: 'device-1',
  deviceName: 'Test Phone',
  platform: wire.Platform.android,
  osVersion: '14',
  appVersion: '0.1.0',
);

/// The way a wrong phrase makes the Noise handshake fail (`relay.dart`'s own
/// `_defaultHandshaker` wraps a decryption failure into this exact exception).
Future<NoiseSession> _failingHandshaker(
  StreamIterator<dynamic> iterator,
  WebSocketChannel channel,
  NoiseHandshakeMode mode,
  BiometricGate gate,
  SimpleKeyPair localStatic,
) => throw const RelayConnectException(
  RelayConnectFailure.handshakeFailed,
  'the Noise handshake failed: StateError',
);

/// Runs one [attemptPairing] against a local relay that answers registration and then
/// fails the handshake, and returns the attempt's `Err.cause`.
Future<Object?> _failHandshakeOnce(
  BiometricGate gate,
  PairingAttemptTracker tracker,
) async {
  final connections = <WebSocket>[];
  final server = await HttpServer.bind('127.0.0.1', 0);
  server.listen((request) async {
    connections.add(await WebSocketTransformer.upgrade(request));
  });
  final origin = (parseRelayOrigin(
    'http://127.0.0.1:${server.port}',
  ) as Ok<RelayOrigin>).value;
  final relay = RelayConnection(
    handshaker: _failingHandshaker,
    connectivityWatcher: _noOpConnectivityWatcher(),
  );
  final resultFuture = attemptPairing(
    connection: relay,
    input: PairingInput(
      relayOrigin: origin,
      handle: 'h1',
      phrase: 'remedy-tapestry-hubcap-oversleep-jailbird-kinetic',
    ),
    gate: gate,
    deviceInfo: _testDeviceInfo,
    tracker: tracker,
  );
  while (connections.isEmpty) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  final ws = connections[0];
  final iterator = StreamIterator<dynamic>(ws);
  await iterator.moveNext(); // device_register
  ws.add(jsonEncode({'type': 'session_joined', 'role': 'device'}));
  final result = await resultFuture;
  await relay.dispose();
  await ws.close();
  await server.close(force: true);
  return (result as Err<PairingOutcome>).cause;
}

void main() {
  final words = _loadRealWords();

  test(
    'cancelling during Noise closes the socket and rejects late completion',
    () async {
      final gate = await _unlockedGate();
      final accepted = Completer<WebSocket>();
      final entered = Completer<void>();
      final release = Completer<NoiseSession>();
      final server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((request) async {
        accepted.complete(await WebSocketTransformer.upgrade(request));
      });
      final relay = RelayConnection(
        connectivityWatcher: _noOpConnectivityWatcher(),
        handshaker: (iterator, channel, mode, gate, localStatic) {
          entered.complete();
          return release.future;
        },
      );
      final cancellation = PairingCancellation();
      final states = <Object>[];
      final subscription = relay.connectionState.listen(states.add);
      final pending = attemptPairing(
        connection: relay,
        input: PairingInput(
          relayOrigin: (parseRelayOrigin(
            'http://127.0.0.1:${server.port}',
          ) as Ok<RelayOrigin>).value,
          handle: 'h1',
          phrase: 'remedy-tapestry-hubcap-oversleep-jailbird-kinetic',
        ),
        gate: gate,
        deviceInfo: _testDeviceInfo,
        tracker: PairingAttemptTracker(),
        cancellation: cancellation,
      );
      final socket = await accepted.future;
      addTearDown(socket.close);
      final closed = Completer<void>();
      socket.listen((_) {
        socket.add(jsonEncode({'type': 'session_joined', 'role': 'device'}));
      }, onDone: closed.complete);
      await entered.future;
      cancellation.cancel();
      cancellation.cancel();
      final result = await pending.timeout(const Duration(seconds: 1));
      expect(result, isA<Err<PairingOutcome>>());
      expect(
        (result as Err<PairingOutcome>).cause,
        isA<PairingCancelledException>(),
      );
      await closed.future.timeout(const Duration(seconds: 1));
      release.complete(
        NoiseSession(
          send: NoiseCipher.withKey(Uint8List(32)),
          receive: NoiseCipher.withKey(Uint8List(32)),
          remoteStaticPublicKey: Uint8List(32),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(relay.isConnected, isFalse);
      expect(states.whereType<RelayConnected>(), isEmpty);
      await subscription.cancel();
      await relay.dispose();
      await server.close(force: true);
    },
  );

  setUpAll(() {
    expect(
      words.length,
      7776,
      reason:
          'run `dart run tool/fetch_eff_wordlist.dart` from app/ before '
          'this test suite (R-13-025)',
    );
    registerFallbackValue(Uri.parse('https://relay.example.com'));
  });

  group('normalizePhraseInput (R-13-026)', () {
    test('trims, lowercases, and collapses a run of spaces to one hyphen', () {
      expect(normalizePhraseInput('  Abacus   Abdomen  '), 'abacus-abdomen');
    });

    test('collapses a run of hyphens to one hyphen', () {
      expect(normalizePhraseInput('abacus---abdomen'), 'abacus-abdomen');
    });

    test('collapses a mixed run of spaces and hyphens to one hyphen', () {
      expect(normalizePhraseInput('abacus - abdomen'), 'abacus-abdomen');
    });

    test('a leading hyphen survives as a length-one run', () {
      expect(normalizePhraseInput('-abacus'), '-abacus');
    });

    test('a trailing hyphen survives as a length-one run', () {
      expect(normalizePhraseInput('abacus-'), 'abacus-');
    });
  });

  group('validatePhrase (R-13-027)', () {
    test('accepts a valid canonical six-word phrase', () {
      final result = validatePhrase(
        'abacus-abdomen-abdominal-abide-abiding-ability',
        words,
      );
      expect(result, isA<Ok<String>>());
      expect(
        (result as Ok<String>).value,
        'abacus-abdomen-abdominal-abide-abiding-ability',
      );
    });

    test(
      'accepts the space-separated display form and returns the canonical form',
      () {
        final result = validatePhrase(
          'abacus abdomen abdominal abide abiding ability',
          words,
        );
        expect(result, isA<Ok<String>>());
        expect(
          (result as Ok<String>).value,
          'abacus-abdomen-abdominal-abide-abiding-ability',
        );
      },
    );

    for (final hyphenated in ['drop-down', 'felt-tip', 't-shirt', 'yo-yo']) {
      test(
        'segments the internal-hyphen entry "$hyphenated" as one word, not two',
        () {
          expect(words, contains(hyphenated));
          final candidate =
              '$hyphenated-abdomen-abdominal-abide-abiding-ability';
          final result = validatePhrase(candidate, words);
          expect(result, isA<Ok<String>>());
          expect((result as Ok<String>).value, candidate);
        },
      );
    }

    test('phrase_word_count: five words is rejected', () {
      final result = validatePhrase(
        'abacus-abdomen-abdominal-abide-abiding',
        words,
      );
      expect(result, isA<Err<String>>());
      final cause = (result as Err<String>).cause! as PhraseException;
      expect(cause.code, PhraseErrorCode.phraseWordCount);
      expect(cause.code.wireValue, 'phrase_word_count');
    });

    test('phrase_word_count: seven words is rejected', () {
      final result = validatePhrase(
        'abacus-abdomen-abdominal-abide-abiding-ability-ablaze',
        words,
      );
      expect(result, isA<Err<String>>());
      expect(
        ((result as Err<String>).cause! as PhraseException).code,
        PhraseErrorCode.phraseWordCount,
      );
    });

    test(
      'phrase_word_unknown: a word not in the EFF long list is rejected',
      () {
        final result = validatePhrase(
          'abacus-abdomen-abdominal-abide-abiding-zzznotarealword',
          words,
        );
        expect(result, isA<Err<String>>());
        final cause = (result as Err<String>).cause! as PhraseException;
        expect(cause.code, PhraseErrorCode.phraseWordUnknown);
        expect(cause.code.wireValue, 'phrase_word_unknown');
      },
    );

    test(
      'phrase_separator: an empty word from a leading hyphen is rejected',
      () {
        final result = validatePhrase(
          '-abacus-abdomen-abdominal-abide-abiding-ability',
          words,
        );
        expect(result, isA<Err<String>>());
        final cause = (result as Err<String>).cause! as PhraseException;
        expect(cause.code, PhraseErrorCode.phraseSeparator);
        expect(cause.code.wireValue, 'phrase_separator');
      },
    );

    test(
      'phrase_separator: an empty word from a trailing hyphen is rejected',
      () {
        final result = validatePhrase(
          'abacus-abdomen-abdominal-abide-abiding-ability-',
          words,
        );
        expect(result, isA<Err<String>>());
        expect(
          ((result as Err<String>).cause! as PhraseException).code,
          PhraseErrorCode.phraseSeparator,
        );
      },
    );

    test('phrase_case: a digit surviving normalisation is rejected', () {
      final result = validatePhrase(
        'abacus1-abdomen-abdominal-abide-abiding-ability',
        words,
      );
      expect(result, isA<Err<String>>());
      final cause = (result as Err<String>).cause! as PhraseException;
      expect(cause.code, PhraseErrorCode.phraseCase);
      expect(cause.code.wireValue, 'phrase_case');
    });

    test('phrase_expired and phrase_attempts wire values (raised only by attemptPairing)', () {
      expect(PhraseErrorCode.phraseExpired.wireValue, 'phrase_expired');
      expect(PhraseErrorCode.phraseAttempts.wireValue, 'phrase_attempts');
    });
  });

  group('splitPastedPhrase (R-30-907)', () {
    test('splits a space-separated paste into six fields', () {
      expect(
        splitPastedPhrase(
          'abacus abdomen abdominal abide abiding ability',
          words,
        ),
        ['abacus', 'abdomen', 'abdominal', 'abide', 'abiding', 'ability'],
      );
    });

    test('splits a hyphenated paste into six fields', () {
      expect(
        splitPastedPhrase(
          'abacus-abdomen-abdominal-abide-abiding-ability',
          words,
        ),
        ['abacus', 'abdomen', 'abdominal', 'abide', 'abiding', 'ability'],
      );
    });

    test('keeps a pasted internal-hyphen word ("t-shirt") as one field', () {
      expect(
        splitPastedPhrase(
          't-shirt abdomen abdominal abide abiding ability',
          words,
        ),
        ['t-shirt', 'abdomen', 'abdominal', 'abide', 'abiding', 'ability'],
      );
    });

    test(
      'a wrong word count still fills as far as the paste reached (R-30-907)',
      () {
        expect(splitPastedPhrase('abacus abdomen abdominal', words), [
          'abacus',
          'abdomen',
          'abdominal',
        ]);
      },
    );

    for (final hyphenated in ['drop-down', 'felt-tip', 't-shirt', 'yo-yo']) {
      test(
        'every keystroke of "$hyphenated" stays one word being typed, never a paste',
        () {
          // Regression: `yo-y` split into two tokens no entry joins, the paste
          // path fired, cleared every field and reported word 1 as unknown.
          for (var n = 1; n <= hyphenated.length; n++) {
            final typed = hyphenated.substring(0, n);
            expect(splitPastedPhrase(typed, words), [
              typed,
            ], reason: 'after typing "$typed"');
          }
        },
      );
    }

    test('a hyphen-joined value that prefixes no entry is still a paste', () {
      expect(splitPastedPhrase('abacus-abdomen', words), ['abacus', 'abdomen']);
    });
  });

  group('autocompleteWords (R-30-904)', () {
    test('proposes no suggestion before the second character', () {
      expect(autocompleteWords('a', words), isEmpty);
    });

    test(
      'proposes only an exact prefix match, at most six, after two characters',
      () {
        final suggestions = autocompleteWords('ab', words);
        expect(suggestions.length, lessThanOrEqualTo(6));
        expect(suggestions, everyElement(startsWith('ab')));
      },
    );

    test('is case-insensitive on the typed prefix', () {
      expect(autocompleteWords('AB', words), autocompleteWords('ab', words));
    });
  });

  group('isPairingPayload (R-31-02-02, R-03-013)', () {
    test('accepts the herdr-remote scheme', () {
      expect(isPairingPayload('herdr-remote://pair?v=1&r=x&h=y&p=z'), isTrue);
    });

    test('rejects every other payload, including a look-alike scheme', () {
      expect(isPairingPayload('https://example.com'), isFalse);
      expect(isPairingPayload('herdr-remotex://pair'), isFalse);
      expect(isPairingPayload('not a uri at all'), isFalse);
    });
  });

  group('parsePairingUri (R-11-140, §9.5)', () {
    const phrase = 'abacus-abdomen-abdominal-abide-abiding-ability';
    const handle = 'n6Loxf94CfyIO6hOxlaHvA';

    String uriWith({
      String v = '1',
      String r = 'https%3A%2F%2Frelay.example.com',
      String h = handle,
      String p = phrase,
    }) => 'herdr-remote://pair?v=$v&r=$r&h=$h&p=$p';

    test(
      'accepts a well-formed URI and produces the expected PairingInput',
      () {
        final result = parsePairingUri(uriWith(), words);
        expect(result, isA<Ok<PairingInput>>());
        final input = (result as Ok<PairingInput>).value;
        expect(input.relayOrigin.canonical, 'https://relay.example.com');
        expect(input.handle, handle);
        expect(input.phrase, phrase);
      },
    );

    test('accepts fields in any order (R-11-140: "a parser MUST accept any order")', () {
      const reordered =
          'herdr-remote://pair?p=$phrase&h=$handle&v=1&r=https%3A%2F%2Frelay.example.com';
      final result = parsePairingUri(reordered, words);
      expect(result, isA<Ok<PairingInput>>());
      expect(
        (result as Ok<PairingInput>).value.relayOrigin.canonical,
        'https://relay.example.com',
      );
    });

    test('pair_uri_scheme: wrong scheme is rejected', () {
      final result = parsePairingUri(
        'https://pair?v=1&r=https%3A%2F%2Frelay.example.com&h=$handle&p=$phrase',
        words,
      );
      expect(result, isA<Err<PairingInput>>());
      final cause = (result as Err<PairingInput>).cause! as PairingUriException;
      expect(cause.code, PairingUriErrorCode.scheme);
      expect(cause.code.wireValue, 'pair_uri_scheme');
    });

    test('pair_uri_path: wrong path is rejected', () {
      final result = parsePairingUri(
        'herdr-remote://notpair?v=1&r=https%3A%2F%2Frelay.example.com&h=$handle&p=$phrase',
        words,
      );
      expect(result, isA<Err<PairingInput>>());
      expect(
        ((result as Err<PairingInput>).cause! as PairingUriException).code,
        PairingUriErrorCode.path,
      );
    });

    test('pair_uri_version: absent v is rejected', () {
      final result = parsePairingUri(
        'herdr-remote://pair?r=https%3A%2F%2Frelay.example.com&h=$handle&p=$phrase',
        words,
      );
      expect(result, isA<Err<PairingInput>>());
      expect(
        ((result as Err<PairingInput>).cause! as PairingUriException).code,
        PairingUriErrorCode.version,
      );
    });

    test('pair_uri_version: v=2 is rejected', () {
      final result = parsePairingUri(uriWith(v: '2'), words);
      expect(result, isA<Err<PairingInput>>());
      expect(
        ((result as Err<PairingInput>).cause! as PairingUriException).code,
        PairingUriErrorCode.version,
      );
    });

    test('pair_uri_field_missing: absent p is rejected', () {
      final result = parsePairingUri(
        'herdr-remote://pair?v=1&r=https%3A%2F%2Frelay.example.com&h=$handle',
        words,
      );
      expect(result, isA<Err<PairingInput>>());
      expect(
        ((result as Err<PairingInput>).cause! as PairingUriException).code,
        PairingUriErrorCode.fieldMissing,
      );
    });

    test('pair_uri_field_repeated: a duplicated field is rejected', () {
      final result = parsePairingUri(
        'herdr-remote://pair?v=1&v=1&r=https%3A%2F%2Frelay.example.com&h=$handle&p=$phrase',
        words,
      );
      expect(result, isA<Err<PairingInput>>());
      expect(
        ((result as Err<PairingInput>).cause! as PairingUriException).code,
        PairingUriErrorCode.fieldRepeated,
      );
    });

    test('pair_uri_too_long: a URI over 512 bytes is rejected', () {
      final longOrigin = 'https%3A%2F%2F${'a' * 600}.example.com';
      final result = parsePairingUri(uriWith(r: longOrigin), words);
      expect(result, isA<Err<PairingInput>>());
      expect(
        ((result as Err<PairingInput>).cause! as PairingUriException).code,
        PairingUriErrorCode.tooLong,
      );
    });

    test('handle_malformed: a 21-character handle is rejected', () {
      final result = parsePairingUri(
        uriWith(h: handle.substring(0, 21)),
        words,
      );
      expect(result, isA<Err<PairingInput>>());
      expect(
        ((result as Err<PairingInput>).cause! as PairingUriException).code,
        PairingUriErrorCode.handleMalformed,
      );
    });

    test('handle_malformed: invalid base64url characters are rejected', () {
      final result = parsePairingUri(
        uriWith(h: 'n6Loxf94CfyIO6hOxlaH!!'),
        words,
      );
      expect(result, isA<Err<PairingInput>>());
      expect(
        ((result as Err<PairingInput>).cause! as PairingUriException).code,
        PairingUriErrorCode.handleMalformed,
      );
    });

    test(
      'relay_origin_invalid passes through origin.dart\'s own error unchanged',
      () {
        final result = parsePairingUri(
          uriWith(r: Uri.encodeComponent('not a uri')),
          words,
        );
        expect(result, isA<Err<PairingInput>>());
        final cause =
            (result as Err<PairingInput>).cause! as RelayOriginException;
        expect(cause.code, RelayOriginErrorCode.relayOriginInvalid);
      },
    );

    test('a malformed phrase field surfaces the matching phrase_* code', () {
      final result = parsePairingUri(
        uriWith(p: 'abacus-abdomen-abdominal-abide-abiding'),
        words,
      );
      expect(result, isA<Err<PairingInput>>());
      expect(
        ((result as Err<PairingInput>).cause! as PhraseException).code,
        PhraseErrorCode.phraseWordCount,
      );
    });

    test('percent-decodes the r field correctly', () {
      final result = parsePairingUri(
        uriWith(r: 'https%3A%2F%2Frelay.example.com%3A8443'),
        words,
      );
      expect(result, isA<Ok<PairingInput>>());
      expect(
        (result as Ok<PairingInput>).value.relayOrigin.canonical,
        'https://relay.example.com:8443',
      );
    });
  });

  group('manual entry and QR entry converge on one identical PairingInput '
      '(R-13-026, R-11-140, R-03-071)', () {
    test('buildManualPairingInput and parsePairingUri agree exactly', () {
      const phrase = 'abacus-abdomen-abdominal-abide-abiding-ability';
      const handle = 'n6Loxf94CfyIO6hOxlaHvA';
      const originText = 'https://relay.example.com';

      final fromQr = parsePairingUri(
        'herdr-remote://pair?v=1&r=https%3A%2F%2Frelay.example.com&h=$handle&p=$phrase',
        words,
      );
      final fromManual = buildManualPairingInput(
        relayOriginText: originText,
        handleText: handle,
        // R-30-907: the manual screen joins its six word fields with spaces before
        // this call; the display form and the canonical form MUST produce the same
        // record.
        phraseText: 'abacus abdomen abdominal abide abiding ability',
        effWords: words,
      );

      expect(fromQr, isA<Ok<PairingInput>>());
      expect(fromManual, isA<Ok<PairingInput>>());
      expect(
        (fromManual as Ok<PairingInput>).value,
        (fromQr as Ok<PairingInput>).value,
      );
    });

    test('an identical failure code is raised on both paths for the same bad phrase', () {
      const badPhrase = 'abacus-abdomen-abdominal-abide-abiding';
      const handle = 'n6Loxf94CfyIO6hOxlaHvA';
      const originText = 'https://relay.example.com';

      final fromQr = parsePairingUri(
        'herdr-remote://pair?v=1&r=https%3A%2F%2Frelay.example.com&h=$handle&p=$badPhrase',
        words,
      );
      final fromManual = buildManualPairingInput(
        relayOriginText: originText,
        handleText: handle,
        phraseText: badPhrase,
        effWords: words,
      );

      expect(
        ((fromQr as Err<PairingInput>).cause! as PhraseException).code,
        ((fromManual as Err<PairingInput>).cause! as PhraseException).code,
      );
    });
  });

  group('PairingAttemptTracker (R-13-023)', () {
    test(
      'fires only on the third consecutive failure against the same phrase',
      () {
        final tracker = PairingAttemptTracker();
        expect(tracker.recordFailure('phrase-a'), isFalse);
        expect(tracker.recordFailure('phrase-a'), isFalse);
        expect(tracker.recordFailure('phrase-a'), isTrue);
      },
    );

    test('a phrase change resets the counter (R-13-023)', () {
      final tracker = PairingAttemptTracker();
      expect(tracker.recordFailure('phrase-a'), isFalse);
      expect(tracker.recordFailure('phrase-a'), isFalse);
      // The Host destroyed and replaced the phrase after the second failure;
      // a retry against the new phrase starts a fresh count.
      expect(tracker.recordFailure('phrase-b'), isFalse);
      expect(tracker.recordFailure('phrase-b'), isFalse);
      expect(tracker.recordFailure('phrase-b'), isTrue);
    });

    test('reset() clears the counter for a successful pairing', () {
      final tracker = PairingAttemptTracker();
      expect(tracker.recordFailure('phrase-a'), isFalse);
      expect(tracker.recordFailure('phrase-a'), isFalse);
      tracker.reset();
      expect(tracker.recordFailure('phrase-a'), isFalse);
      expect(tracker.recordFailure('phrase-a'), isFalse);
    });
  });

  group('attemptPairing failure classification (R-31-03-13)', () {
    test(
      'a link failure passes through unclassified and never ticks the attempt '
      'tracker (the 2026-09-03 live defect: an unreachable relay must not '
      'surface as phrase_attempts)',
      () async {
        final tracker = PairingAttemptTracker();
        final gate = await _unlockedGate();
        final origin = (parseRelayOrigin(
          'https://relay.example.com',
        ) as Ok<RelayOrigin>).value;
        final relay = RelayConnection(
          channelFactory: (uri, protocols) =>
              throw const SocketException('connection refused'),
          connectivityWatcher: _noOpConnectivityWatcher(),
        );
        addTearDown(relay.dispose);

        final result = await attemptPairing(
          connection: relay,
          input: PairingInput(
            relayOrigin: origin,
            handle: 'h1',
            phrase: 'remedy-tapestry-hubcap-oversleep-jailbird-kinetic',
          ),
          gate: gate,
          deviceInfo: _testDeviceInfo,
          tracker: tracker,
        );

        final cause = (result as Err<PairingOutcome>).cause;
        // The transport error travels inside the wrapper, never bare: its own text
        // carries the connection URL and the handle (R-13-066).
        expect(cause, isA<RelayConnectException>());
        expect(
          (cause as RelayConnectException).failure,
          RelayConnectFailure.webSocketFailed,
        );
        expect(cause.inner, isA<SocketException>());

        // Had the link failure ticked the tracker, the SECOND handshake failure
        // below would already fire `phrase_attempts`. Both must pass through as
        // plain handshake failures instead.
        for (var i = 1; i <= 2; i++) {
          final handshakeCause = await _failHandshakeOnce(gate, tracker);
          expect(handshakeCause, isA<RelayConnectException>());
          expect(
            (handshakeCause as RelayConnectException).failure,
            RelayConnectFailure.handshakeFailed,
          );
        }
      },
    );

    test(
      'three handshake failures against one phrase still classify the third as '
      'phrase_attempts (R-13-023, unchanged)',
      () async {
        final tracker = PairingAttemptTracker();
        final gate = await _unlockedGate();
        for (var i = 1; i <= 2; i++) {
          final cause = await _failHandshakeOnce(gate, tracker);
          expect(cause, isA<RelayConnectException>());
          expect(
            (cause as RelayConnectException).failure,
            RelayConnectFailure.handshakeFailed,
          );
        }
        final third = await _failHandshakeOnce(gate, tracker);
        expect(third, isA<PhraseException>());
        expect((third as PhraseException).code, PhraseErrorCode.phraseAttempts);
      },
    );
  });

  group('loadEffWordlist (R-13-025)', () {
    test('reads the real bundled asset', () async {
      final bytes = await File(_wordlistPath).readAsBytes();
      final result = await loadEffWordlist(assetLoader: () async => bytes);
      expect(result, isA<Ok<List<String>>>());
      expect((result as Ok<List<String>>).value.length, 7776);
    });

    test('rejects an asset that does not hold exactly 7776 entries', () async {
      final result = await loadEffWordlist(
        assetLoader: () async =>
            Uint8List.fromList(utf8.encode('abacus\nabdomen\n')),
      );
      expect(result, isA<Err<List<String>>>());
      expect((result as Err<List<String>>).cause, isA<WordlistException>());
    });

    test('propagates an asset-loader failure as an Err', () async {
      final result = await loadEffWordlist(
        assetLoader: () async => throw const FormatException('no asset'),
      );
      expect(result, isA<Err<List<String>>>());
    });
  });

  group('persistPairing (R-13-048, R-13-065)', () {
    test(
      'the enrolment record carries the first contact time, because the '
      'link opened before the record existed (cold-start defect, 2026-09-04)',
      () async {
        final keystore = _MockKeystoreService();
        final plainStore = _MockPlainStore();
        registerFallbackValue(
          HostSecrets(hostStaticPublicKey: Uint8List(32), routingHandle: 'h'),
        );
        registerFallbackValue(
          const PairedHostRecord(hostId: 'fallback', hostName: 'fallback'),
        );
        when(() => keystore.storeHostSecrets(any(), any()))
            .thenAnswer((_) async => const Ok(null));
        when(() => plainStore.savePairedHost(any()))
            .thenAnswer((_) async => const Ok(null));
        final origin = (parseRelayOrigin(
          'https://relay.example',
        ) as Ok<RelayOrigin>).value;
        final DateTime connectedAt = DateTime.utc(2026, 9, 4, 10, 58);

        final result = await persistPairing(
          keystore: keystore,
          plainStore: plainStore,
          input: PairingInput(
            relayOrigin: origin,
            handle: 'h1',
            phrase: 'remedy-tapestry-hubcap-oversleep-jailbird-kinetic',
          ),
          outcome: PairingOutcome(
            hostId: 'host-1',
            hostName: 'patrick-desk',
            hostStaticPublicKey: Uint8List(32),
            hostFingerprintText: 'fp',
            connectedAt: connectedAt,
          ),
        );

        expect(result, isA<Ok<void>>());
        final writes = verifyInOrder([
          () => keystore.storeHostSecrets('host-1', captureAny()),
          () => plainStore.savePairedHost(captureAny()),
        ]);
        final secrets = writes[0].captured.single as HostSecrets;
        expect(secrets.relayOrigin, Uri.parse(origin.canonical));
        final saved = writes[1].captured.single as PairedHostRecord;
        verifyNoMoreInteractions(keystore);
        verifyNoMoreInteractions(plainStore);
        expect(saved.hostId, 'host-1');
        expect(saved.hostName, 'patrick-desk');
        expect(
          saved.lastSeen,
          connectedAt,
          reason:
              'the link-open time, not the time the confirmation was accepted',
        );
      },
    );
    test(
      'pairing saves its relay origin without changing another host',
      () async {
        FlutterSecureStorage.setMockInitialValues({});
        addTearDown(() => FlutterSecureStorage.setMockInitialValues({}));
        registerFallbackValue(
          const PairedHostRecord(hostId: 'fallback', hostName: 'fallback'),
        );
        final keystore = KeystoreService(appLockEnabled: false);
        final plainStore = _MockPlainStore();
        when(() => plainStore.savePairedHost(any()))
            .thenAnswer((_) async => const Ok(null));
        final other = HostSecrets(
          hostStaticPublicKey: Uint8List.fromList(List.filled(32, 7)),
          routingHandle: 'other-handle',
          relayOrigin: Uri.parse('https://other-relay.example'),
        );
        expect(
          await keystore.storeHostSecrets('other-host', other),
          isA<Ok<void>>(),
        );
        final origin = (parseRelayOrigin(
          'https://new-relay.example',
        ) as Ok<RelayOrigin>).value;

        final result = await persistPairing(
          keystore: keystore,
          plainStore: plainStore,
          input: PairingInput(
            relayOrigin: origin,
            handle: 'new-handle',
            phrase: 'remedy-tapestry-hubcap-oversleep-jailbird-kinetic',
          ),
          outcome: PairingOutcome(
            hostId: 'new-host',
            hostName: 'New host',
            hostStaticPublicKey: Uint8List(32),
            hostFingerprintText: 'fp',
            connectedAt: DateTime.utc(2026, 9, 11),
          ),
        );

        expect(result, isA<Ok<void>>());
        final saved =
            (await keystore.hostSecrets('new-host') as Ok<HostSecrets?>).value!;
        expect(saved.relayOrigin, Uri.parse(origin.canonical));
        expect(saved.routingHandle, 'new-handle');
        final unchanged = (await keystore.hostSecrets(
          'other-host',
        ) as Ok<HostSecrets?>).value!;
        expect(unchanged.relayOrigin, other.relayOrigin);
        expect(unchanged.routingHandle, other.routingHandle);
        expect(unchanged.hostStaticPublicKey, other.hostStaticPublicKey);
      },
    );
  });

  group('loadPairingOriginDefault (R-03-126)', () {
    late _MockKeystoreService keystore;
    late _MockPlainStore plainStore;

    setUp(() {
      keystore = _MockKeystoreService();
      plainStore = _MockPlainStore();
    });

    test('uses the latest contact time instead of list order', () async {
      when(() => plainStore.pairedHosts()).thenAnswer(
        (_) async => Ok([
          PairedHostRecord(
            hostId: 'older',
            hostName: 'Older',
            lastSeen: DateTime.utc(2026, 9, 9),
          ),
          PairedHostRecord(
            hostId: 'latest',
            hostName: 'Latest',
            lastSeen: DateTime.utc(2026, 9, 11),
          ),
          const PairedHostRecord(hostId: 'unseen', hostName: 'Unseen'),
          PairedHostRecord(
            hostId: 'oldest',
            hostName: 'Oldest',
            lastSeen: DateTime.utc(2026, 9, 8),
          ),
        ]),
      );
      when(() => keystore.hostRelayOrigin(any())).thenAnswer(
        (invocation) async => Ok(
          Uri.parse('https://${invocation.positionalArguments.single}.example'),
        ),
      );

      final origin = await loadPairingOriginDefault(
        keystore: keystore,
        plainStore: plainStore,
      );
      expect(origin?.canonical, 'https://latest.example');
    });

    test('returns no default when no hosts exist', () async {
      when(() => plainStore.pairedHosts())
          .thenAnswer((_) async => const Ok(<PairedHostRecord>[]));
      expect(
        await loadPairingOriginDefault(
          keystore: keystore,
          plainStore: plainStore,
        ),
        isNull,
      );
    });

    test('returns no default before any host has connected', () async {
      when(() => plainStore.pairedHosts()).thenAnswer(
        (_) async =>
            const Ok([PairedHostRecord(hostId: 'unseen', hostName: 'Unseen')]),
      );
      expect(
        await loadPairingOriginDefault(
          keystore: keystore,
          plainStore: plainStore,
        ),
        isNull,
      );
    });

    test('returns no default when the latest host has no origin', () async {
      when(() => plainStore.pairedHosts()).thenAnswer(
        (_) async => Ok([
          PairedHostRecord(
            hostId: 'latest',
            hostName: 'Latest',
            lastSeen: DateTime.utc(2026, 9, 11),
          ),
        ]),
      );
      when(() => keystore.hostRelayOrigin('latest'))
          .thenAnswer((_) async => const Ok(null));
      expect(
        await loadPairingOriginDefault(
          keystore: keystore,
          plainStore: plainStore,
        ),
        isNull,
      );
    });
  });

  group('clearRevokedHost (R-13-054)', () {
    test('clears this computer\'s secrets and record, never the relay origin, '
        'never another computer', () async {
      final keystore = _MockKeystoreService();
      final plainStore = _MockPlainStore();
      when(() => keystore.deleteHostSecrets(any()))
          .thenAnswer((_) async => const Ok(null));
      when(() => plainStore.removePairedHost(any()))
          .thenAnswer((_) async => const Ok(null));
      when(() => plainStore.pairedHosts()).thenAnswer(
        (_) async => const Ok([
          PairedHostRecord(hostId: 'other-host', hostName: 'other'),
        ]),
      );

      final result = await clearRevokedHost(
        keystore: keystore,
        plainStore: plainStore,
        hostId: 'revoked-host',
      );

      expect(result, isA<Ok<bool>>());
      expect(
        (result as Ok<bool>).value,
        isFalse,
        reason: 'another saved computer remains',
      );
      verify(() => keystore.deleteHostSecrets('revoked-host')).called(1);
      verify(() => plainStore.removePairedHost('revoked-host')).called(1);
      verifyNever(() => keystore.deleteHostSecrets('other-host'));
      verifyNever(() => plainStore.removePairedHost('other-host'));
    });

    test(
      'reports true once no saved computer remains, for /welcome routing',
      () async {
        final keystore = _MockKeystoreService();
        final plainStore = _MockPlainStore();
        when(() => keystore.deleteHostSecrets(any()))
            .thenAnswer((_) async => const Ok(null));
        when(() => plainStore.removePairedHost(any()))
            .thenAnswer((_) async => const Ok(null));
        when(() => plainStore.pairedHosts())
            .thenAnswer((_) async => const Ok([]));

        final result = await clearRevokedHost(
          keystore: keystore,
          plainStore: plainStore,
          hostId: 'revoked-host',
        );

        expect(result, isA<Ok<bool>>());
        expect((result as Ok<bool>).value, isTrue);
      },
    );

    test(
      'propagates a keystore failure as an Err without touching plainStore',
      () async {
        final keystore = _MockKeystoreService();
        final plainStore = _MockPlainStore();
        when(() => keystore.deleteHostSecrets(any())).thenAnswer(
          (_) async =>
              const Err('delete host secrets for revoked-host', cause: null),
        );

        final result = await clearRevokedHost(
          keystore: keystore,
          plainStore: plainStore,
          hostId: 'revoked-host',
        );

        expect(result, isA<Err<bool>>());
        verifyNever(() => plainStore.removePairedHost(any()));
      },
    );
  });
}
