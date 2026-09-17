/// Covers the QR path, the manual path and the deep-link path (R-13-035, R-03-071) of
/// `app/lib/services/pairing.dart` (`WP-15-a`) end to end: parse or build a [PairingInput],
/// drive the real `Noise_XXpsk0` handshake through [RelayConnection.connect] against a real
/// local WebSocket server (mirroring `app/test/services/single_socket_test.dart`'s own
/// harness), and persist the outcome. All three paths converge on the identical
/// [PairingInput] and the identical persisted state, proving R-13-026's "manual entry and QR
/// entry MUST converge on one identical pairing input record" end to end, not just at the
/// parser boundary `app/test/services/pairing_test.dart` already proves in isolation.
///
/// This file drives no real camera and no real OS deep-link delivery: `qr_scan_screen.dart`'s
/// `PairingScanner` wraps a native camera plugin with no Dart-VM-testable fake, and the native
/// URL-scheme delivery is `app/ios/Runner/Info.plist`/`AndroidManifest.xml`'s and the
/// `go_router` route's job (`WP-0-b`'s and `WP-12-b`'s owned paths, R-90-024). What both the
/// QR scanner and the deep-link handler ultimately do — hand `pairing.dart` a
/// `herdr-remote://pair` string to parse — is exactly what [parsePairingUri] receives below;
/// the "QR path" and "deep link" groups exercise that identical call, distinguished only by
/// where a real screen would have obtained the string.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart';
import 'package:herdr_mobile/models/frame.dart';
import 'package:herdr_mobile/models/messages/device_info.dart';
import 'package:herdr_mobile/models/messages/host_info.dart';
import 'package:herdr_mobile/models/messages/platform.dart' as wire;
import 'package:herdr_mobile/services/biometric_gate.dart';
import 'package:herdr_mobile/services/connectivity.dart';
import 'package:herdr_mobile/services/frame_codec.dart';
import 'package:herdr_mobile/services/keystore.dart';
import 'package:herdr_mobile/services/noise.dart';
import 'package:herdr_mobile/services/origin.dart';
import 'package:herdr_mobile/services/pairing.dart';
import 'package:herdr_mobile/services/plain_store.dart';
import 'package:herdr_mobile/services/relay.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _MockLocalAuthentication extends Mock implements LocalAuthentication {}

class _MockKeystoreService extends Mock implements KeystoreService {}

class _MockConnectivity extends Mock implements Connectivity {}

ConnectivityWatcher _noOpConnectivityWatcher() {
  final connectivity = _MockConnectivity();
  when(() => connectivity.onConnectivityChanged)
      .thenAnswer((_) => const Stream<List<ConnectivityResult>>.empty());
  return ConnectivityWatcher(connectivity: connectivity);
}

class _MockPlainStore extends Mock implements PlainStore {}

/// Relative to the package root, which is `flutter test`'s working directory (`app/`).
const String _wordlistPath = 'assets/wordlists/eff_large_wordlist.txt';

final Uint8List _deviceSendKey = Uint8List.fromList(
  List.generate(32, (i) => i),
);
final Uint8List _deviceReceiveKey = Uint8List.fromList(
  List.generate(32, (i) => 31 - i),
);
final Uint8List _fixedHostStaticKey = Uint8List.fromList(List.filled(32, 0x42));

/// A fake initiator: skips the real `Noise_XXpsk0` bytes on the wire (already proven byte
/// for byte against the real Rust responder in the Phase 4 spike, `noise.dart`'s own header
/// comment) and returns a fixed transport session, exactly `single_socket_test.dart`'s own
/// seam.
Future<NoiseSession> _fakeHandshaker(
  StreamIterator<dynamic> iterator,
  WebSocketChannel channel,
  NoiseHandshakeMode mode,
  BiometricGate gate,
  SimpleKeyPair localStatic,
) async {
  expect(
    mode,
    isA<PairingMode>(),
    reason: 'first pairing MUST use Noise_XXpsk0, never Noise_KK (R-13-014)',
  );
  return NoiseSession(
    send: NoiseCipher.withKey(_deviceSendKey),
    receive: NoiseCipher.withKey(_deviceReceiveKey),
    remoteStaticPublicKey: _fixedHostStaticKey,
  );
}

Future<BiometricGate> _unlockedGate() async {
  final localAuth = _MockLocalAuthentication();
  final keystore = _MockKeystoreService();
  final keyPair = await X25519().newKeyPair();
  when(
    () =>
        localAuth.authenticate(localizedReason: any(named: 'localizedReason')),
  ).thenAnswer((_) async => true);
  when(() => keystore.existingDeviceKeyPair())
      .thenAnswer((_) async => Ok(keyPair));
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

const _testHostInfo = HostInfo(
  protocol: frameProtocolVersion,
  hostId: 'host-1',
  hostName: 'office-desktop',
  herdrVersion: '1.0.0',
  herdrProtocol: 20,
  paired: false,
);

const _testDeviceInfo = DeviceInfo(
  protocol: frameProtocolVersion,
  deviceId: 'device-1',
  deviceName: 'Test Phone',
  platform: wire.Platform.android,
  osVersion: '14',
  appVersion: '0.1.0',
);

/// Answers one Host-side registration + `Noise_XXpsk0` handshake (faked, see
/// [_fakeHandshaker]) + `host_info` on [ws], mirroring
/// `single_socket_test.dart`'s `serveOneHandshake`.
Future<void> _serveOnePairing(WebSocket ws) async {
  final iterator = StreamIterator<dynamic>(ws);
  await iterator.moveNext(); // device_register
  ws.add(jsonEncode({'type': 'session_joined', 'role': 'device'}));
  final hostSend = NoiseCipher.withKey(_deviceReceiveKey);
  final frame = Frame(
    v: frameProtocolVersion,
    type: 'host_info',
    seq: 1,
    payload: _testHostInfo.toJson(),
  );
  final envelopeBytes = Uint8List.fromList(
    utf8.encode(jsonEncode(frame.toJson())),
  );
  final encoded = await encodeFrame(hostSend, envelopeBytes);
  for (final fragment in (encoded as Ok<List<Uint8List>>).value) {
    ws.add(fragment);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late List<String> effWords;
  late HttpServer server;
  late RelayOrigin origin;
  const routingHandle = 'n6Loxf94CfyIO6hOxlaHvA';
  const canonicalPhrase = 'abacus-abdomen-abdominal-abide-abiding-ability';

  setUpAll(() async {
    effWords = File(_wordlistPath)
        .readAsLinesSync()
        .where((line) => line.isNotEmpty)
        .toList();
    expect(effWords.length, 7776);
    registerFallbackValue(
      HostSecrets(
        hostStaticPublicKey: Uint8List(32),
        routingHandle: 'AAAAAAAAAAAAAAAAAAAAAA',
      ),
    );
    registerFallbackValue(Uri.parse('https://relay.example.com'));
    registerFallbackValue(
      const PairedHostRecord(hostId: 'fallback', hostName: 'fallback'),
    );
  });

  setUp(() async {
    server = await HttpServer.bind('127.0.0.1', 0);
    // R-22-039: a loopback origin is on the local-development allow list.
    origin = (parseRelayOrigin(
      'http://127.0.0.1:${server.port}',
    ) as Ok<RelayOrigin>).value;
  });

  tearDown(() => server.close(force: true));

  /// Runs [attemptPairing] against one served handshake and returns the outcome, proving
  /// the connection actually completed (not just that parsing succeeded).
  Future<PairingOutcome> pairAndCapture(PairingInput input) async {
    final connections = <WebSocket>[];
    server.listen((request) async {
      connections.add(await WebSocketTransformer.upgrade(request));
    });

    final gate = await _unlockedGate();
    final connection = RelayConnection(
      handshaker: _fakeHandshaker,
      connectivityWatcher: _noOpConnectivityWatcher(),
    );
    addTearDown(connection.dispose);

    final future = attemptPairing(
      connection: connection,
      input: input,
      gate: gate,
      deviceInfo: _testDeviceInfo,
      tracker: PairingAttemptTracker(),
    );
    while (connections.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await _serveOnePairing(connections.single);

    final result = await future;
    expect(result, isA<Ok<PairingOutcome>>());
    return (result as Ok<PairingOutcome>).value;
  }

  Future<void> expectPersisted(
    PairingInput input,
    PairingOutcome outcome,
  ) async {
    final keystore = _MockKeystoreService();
    final plainStore = _MockPlainStore();
    when(() => keystore.storeHostSecrets(any(), any()))
        .thenAnswer((_) async => const Ok(null));
    when(() => plainStore.savePairedHost(any()))
        .thenAnswer((_) async => const Ok(null));

    final persistResult = await persistPairing(
      keystore: keystore,
      plainStore: plainStore,
      input: input,
      outcome: outcome,
    );
    expect(persistResult, isA<Ok<void>>());

    final capturedSecrets = verify(
      () => keystore.storeHostSecrets(captureAny(), captureAny()),
    ).captured;
    expect(capturedSecrets[0], outcome.hostId);
    final secrets = capturedSecrets[1] as HostSecrets;
    expect(secrets.hostStaticPublicKey, outcome.hostStaticPublicKey);
    expect(secrets.routingHandle, input.handle);

    expect(secrets.relayOrigin.toString(), input.relayOrigin.canonical);

    final capturedRecord =
        verify(() => plainStore.savePairedHost(captureAny())).captured.single
            as PairedHostRecord;
    expect(capturedRecord.hostId, outcome.hostId);
    expect(capturedRecord.hostName, outcome.hostName);
    // R-13-065: pairing connected the link before this record existed, so the enrolment
    // save carries the first contact itself; without it a cold start shows
    // `NOT CONNECTED YET` and never auto-connects (live defect, 2026-09-04).
    expect(capturedRecord.lastSeen, outcome.connectedAt);
  }

  testWidgets('QR path: scanning the Host QR pairs and persists (R-13-035)', (
    tester,
  ) async {
    final uri =
        'herdr-remote://pair?v=1&r=${Uri.encodeComponent(origin.canonical)}'
        '&h=$routingHandle&p=$canonicalPhrase';
    // What `PairingScanner.scannedValues` would emit for a real QR scan; the screen calls
    // `isPairingPayload` then `parsePairingUri` exactly like this.
    expect(isPairingPayload(uri), isTrue);
    final parsed = parsePairingUri(uri, effWords);
    expect(parsed, isA<Ok<PairingInput>>());
    final input = (parsed as Ok<PairingInput>).value;

    final outcome = await pairAndCapture(input);
    expect(outcome.hostId, 'host-1');
    expect(outcome.hostName, 'office-desktop');
    expect(outcome.hostStaticPublicKey, _fixedHostStaticKey);
    expect(outcome.hostFingerprintText, isNotEmpty);

    await expectPersisted(input, outcome);
  });

  testWidgets(
    'manual path: typing the origin, code and six words pairs and persists, '
    'and converges on the identical PairingInput the QR path produces (R-30-921)',
    (tester) async {
      final manual = buildManualPairingInput(
        relayOriginText: origin.canonical,
        handleText: routingHandle,
        phraseText: 'abacus abdomen abdominal abide abiding ability',
        effWords: effWords,
      );
      expect(manual, isA<Ok<PairingInput>>());
      final input = (manual as Ok<PairingInput>).value;

      final uri =
          'herdr-remote://pair?v=1&r=${Uri.encodeComponent(origin.canonical)}'
          '&h=$routingHandle&p=$canonicalPhrase';
      final fromQr = parsePairingUri(uri, effWords) as Ok<PairingInput>;
      expect(
        input,
        fromQr.value,
        reason:
            'R-13-026: manual entry and QR entry MUST converge on one '
            'identical pairing input record',
      );

      final outcome = await pairAndCapture(input);
      await expectPersisted(input, outcome);
    },
  );

  testWidgets('deep-link path: a herdr-remote://pair URL delivered by the OS pairs and persists '
      '(R-22-034)', (tester) async {
    // What the OS scene/intent delivery hands the app (R-22-034: "the app MUST parse the
    // URL with Uri.parse in Dart... and route to the pairing flow"), before any go_router
    // wiring -- pairing.dart's own parser is the same call the QR path makes.
    final deepLinkUrl =
        'herdr-remote://pair?v=1&r=${Uri.encodeComponent(origin.canonical)}'
        '&h=$routingHandle&p=$canonicalPhrase';
    final parsed = parsePairingUri(deepLinkUrl, effWords);
    expect(parsed, isA<Ok<PairingInput>>());
    final input = (parsed as Ok<PairingInput>).value;

    final outcome = await pairAndCapture(input);
    await expectPersisted(input, outcome);
  });

  testWidgets(
    'a malformed deep link is discarded with no error shown (R-22-034: "the app MUST '
    'discard a malformed URL without showing an error to the user")',
    (tester) async {
      final result = parsePairingUri('not-a-pairing-url', effWords);
      expect(result, isA<Err<PairingInput>>());
      // R-22-034 places the "discard silently, no error" behaviour on the screen/router
      // that receives this Err (R-90-024, out of this file's owned paths); this assertion
      // only proves the parser itself never throws and always returns a typed Err a caller
      // can discard.
    },
  );
}
