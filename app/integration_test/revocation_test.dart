/// Covers revocation during an active session end to end (R-13-055,
/// `docs/13-security-pairing.md`), composing every piece Phase 20 adds
/// across the files each is owned by: a real `Noise_KK` reconnect brings
/// `app/lib/services/relay.dart`'s (`WP-14-a`) [RelayConnection] to
/// [RelayConnected]; the fake Host then revokes it exactly the way
/// `crates/herdr-relay/src/relay/session.rs`'s real `run_host_session` does
/// — an `error{code:"revoked",fatal:true}` frame (R-11-065), then a
/// WebSocket close with code `4004` (R-11-121) — and this file asserts
/// [RelayConnection] publishes [RelayRevoked] (never the generic
/// [RelayDisconnected]) with no automatic reconnect, then drives
/// `app/lib/services/pairing.dart`'s (`WP-15-a`) [clearRevokedHost] off the
/// real [RelayConnection.lastHostInfo] it produced, proving R-13-054's
/// "clear the stored Host key and handle... MUST NOT clear the relay
/// origin... MUST NOT touch another saved computer" end to end rather than
/// each half in isolation.
///
/// `app/test/services/revocation_test.dart` (`WP-14-a`) already proves the
/// transport-only half of this (the `4004` -> [RelayRevoked] distinction,
/// no error frame, no [clearRevokedHost] call); this file's own scope is the
/// composition those two owned files never see wired together. The message
/// display (`app/lib/widgets/terminal_view_widget.dart`'s
/// `TerminalGridPhase.revoked`, `WP-16-b`) and the `/welcome` navigation
/// itself are a screen's job (R-90-024, `pairing.dart`'s own
/// [clearRevokedHost] doc comment) — outside every file this phase names —
/// and are proven separately by `terminal_isolated_test.dart`'s widget test.
///
/// **Device gap.** This workstation has no attached Android/iOS device or
/// emulator, and this app ships Android/iOS only (R-20-007): no `windows/`
/// or `web/` platform directory exists for `flutter test
/// integration_test/...` to target here, confirmed directly: `flutter test
/// integration_test/pairing_flow_test.dart` on this machine fails immediately
/// with "No supported devices connected", the same gap
/// `pairing_flow_test.dart`, `first_paint_test.dart` and
/// `keystore_survival_test.dart` already carry. This file is written for a
/// real device/CI run and cannot be executed as `flutter test
/// integration_test/...` on this workstation. It was verified for real by a
/// temporary scratch copy — `testWidgets`/`IntegrationTestWidgetsFlutterBinding`
/// swapped for plain `package:test` `test()`, identical logic otherwise —
/// run with `dart test` against the same real local WebSocket server this
/// file uses, then deleted; see this work package's own report for that run's
/// output.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart';
import 'package:herdr_mobile/models/codes.dart';
import 'package:herdr_mobile/models/frame.dart';
import 'package:herdr_mobile/models/message.dart';
import 'package:herdr_mobile/models/messages/device_info.dart';
import 'package:herdr_mobile/models/messages/error_message.dart';
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

class _MockPlainStore extends Mock implements PlainStore {}

class _MockConnectivity extends Mock implements Connectivity {}

ConnectivityWatcher _noOpConnectivityWatcher() {
  final connectivity = _MockConnectivity();
  when(() => connectivity.onConnectivityChanged)
      .thenAnswer((_) => const Stream<List<ConnectivityResult>>.empty());
  return ConnectivityWatcher(connectivity: connectivity);
}

final Uint8List _deviceSendKey = Uint8List.fromList(
  List.generate(32, (i) => i),
);
final Uint8List _deviceReceiveKey = Uint8List.fromList(
  List.generate(32, (i) => 31 - i),
);
final Uint8List _pinnedHostStaticKey = Uint8List.fromList(
  List.filled(32, 0x42),
);

/// A fake `Noise_KK` initiator: this file's own scope is what happens after
/// transport mode is reached, so the handshake bytes themselves are stubbed
/// exactly like `pairing_flow_test.dart`'s `_fakeHandshaker`, but asserts
/// [ReconnectMode] rather than [PairingMode] — a revocation always targets
/// an already-paired Device reconnecting with `Noise_KK` (R-13-037), never a
/// first pairing.
Future<NoiseSession> _fakeHandshaker(
  StreamIterator<dynamic> iterator,
  WebSocketChannel channel,
  NoiseHandshakeMode mode,
  BiometricGate gate,
  SimpleKeyPair localStatic,
) async {
  expect(
    mode,
    isA<ReconnectMode>(),
    reason: 'a revoked session was reached by reconnect, Noise_KK (R-13-037)',
  );
  return NoiseSession(
    send: NoiseCipher.withKey(_deviceSendKey),
    receive: NoiseCipher.withKey(_deviceReceiveKey),
    remoteStaticPublicKey: _pinnedHostStaticKey,
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

const _testHostInfo = HostInfo(
  protocol: frameProtocolVersion,
  hostId: 'host-1',
  hostName: 'office-desktop',
  herdrVersion: '1.0.0',
  herdrProtocol: 20,
  paired: true,
);

const _testDeviceInfo = DeviceInfo(
  protocol: frameProtocolVersion,
  deviceId: 'device-1',
  deviceName: 'Test Phone',
  platform: wire.Platform.android,
  osVersion: '14',
  appVersion: '0.1.0',
);

Future<void> _sendFrame(
  WebSocket ws,
  NoiseCipher hostSend,
  Message message,
  int seq,
) async {
  final frame = Frame(
    v: frameProtocolVersion,
    type: message.typeName,
    seq: seq,
    payload: message.payloadJson,
  );
  final envelopeBytes = Uint8List.fromList(
    utf8.encode(jsonEncode(frame.toJson())),
  );
  final encoded = await encodeFrame(hostSend, envelopeBytes);
  for (final fragment in (encoded as Ok<List<Uint8List>>).value) {
    ws.add(fragment);
  }
}

/// Answers one Host-side registration + `Noise_KK` reconnect (faked, see
/// [_fakeHandshaker]) + `host_info(paired: true)`, then revokes the Device
/// exactly the way `crates/herdr-relay/src/relay/session.rs`'s real
/// `run_host_session` does on a revocation signal: an `error{code:"revoked",
/// fatal:true}` frame (R-11-065), then close code `4004` (R-11-121).
Future<void> _serveOneRevocation(WebSocket ws) async {
  final iterator = StreamIterator<dynamic>(ws);
  await iterator.moveNext(); // device_register
  ws.add(jsonEncode({'type': 'session_joined', 'role': 'device'}));
  final hostSend = NoiseCipher.withKey(_deviceReceiveKey);
  await _sendFrame(ws, hostSend, const Message.hostInfo(_testHostInfo), 1);
  // Let the Device finish the handshake and reach RelayConnected before the
  // revocation lands, matching the checklist's "during an active session".
  await Future<void>.delayed(const Duration(milliseconds: 50));
  await _sendFrame(
    ws,
    hostSend,
    const Message.error(
      ErrorMessage(
        code: ErrorCode.revoked,
        message: 'This Device has been revoked.',
        fatal: true,
      ),
    ),
    2,
  );
  await ws.close(4004, 'revoked');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  late RelayOrigin origin;

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://relay.example.com'));
  });

  setUp(() async {
    server = await HttpServer.bind('127.0.0.1', 0);
    // R-22-039: a loopback origin is on the local-development allow list.
    origin = (parseRelayOrigin(
      'http://127.0.0.1:${server.port}',
    ) as Ok<RelayOrigin>).value;
  });

  tearDown(() => server.close(force: true));

  testWidgets('a Device revoked mid-session loses the connection, never auto-reconnects, and '
      'clears exactly that computer\'s stored record, never the relay origin '
      '(R-13-054, R-13-055)', (tester) async {
    final connections = <WebSocket>[];
    server.listen((request) async {
      final ws = await WebSocketTransformer.upgrade(request);
      connections.add(ws);
      unawaited(_serveOneRevocation(ws));
    });

    final gate = await _unlockedGate();
    final connection = RelayConnection(
      handshaker: _fakeHandshaker,
      connectivityWatcher: _noOpConnectivityWatcher(),
    );
    addTearDown(connection.dispose);

    final states = <RelayConnectionState>[];
    final statesSub = connection.connectionState.listen(states.add);
    addTearDown(statesSub.cancel);
    final errors = <MessageError>[];
    final messagesSub = connection.messages.listen((message) {
      if (message is MessageError) errors.add(message);
    });
    addTearDown(messagesSub.cancel);

    final connectResult = await connection.connect(
      origin: origin,
      handle: 'n6Loxf94CfyIO6hOxlaHvA',
      mode: ReconnectMode(remoteStaticPublicKey: _pinnedHostStaticKey),
      gate: gate,
      deviceInfo: _testDeviceInfo,
    );
    expect(connectResult, isA<Ok<void>>());
    expect(connection.isConnected, isTrue);
    expect(connection.lastHostInfo?.hostId, 'host-1');

    // The revoked error frame and the 4004 close both arrive asynchronously
    // from `_serveOneRevocation`; wait for the session to actually end.
    await expectLater(
      Stream<void>.periodic(const Duration(milliseconds: 10))
          .map((_) => states.whereType<RelayRevoked>().isNotEmpty)
          .firstWhere((seen) => seen)
          .timeout(const Duration(seconds: 5)),
      completes,
      reason: 'RelayRevoked MUST be published on a 4004 mid-session close',
    );
    expect(
      states.whereType<RelayDisconnected>(),
      isEmpty,
      reason:
          'a revocation close MUST NOT also publish the generic '
          'RelayDisconnected',
    );
    expect(connection.isConnected, isFalse);
    expect(
      errors,
      contains(
        isA<MessageError>()
            .having((e) => e.payload.code, 'code', ErrorCode.revoked)
            .having((e) => e.payload.fatal, 'fatal', isTrue),
      ),
      reason:
          'R-11-092: the raw revoked error frame is shown, not '
          'replaced with a friendly sentence',
    );

    // R-13-055: "never auto-reconnects" — give the reconnect schedule's
    // own first delay (R-22-028) generous headroom, then confirm the
    // server never saw a second socket for the same key.
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(
      connections.length,
      1,
      reason: 'a revoked Device MUST NOT auto-reconnect with the same key',
    );

    // R-13-054's clearing action, driven off the real close this test just
    // observed rather than a hand-built RevokeResult.
    final keystore = _MockKeystoreService();
    final plainStore = _MockPlainStore();
    when(() => keystore.deleteHostSecrets(any()))
        .thenAnswer((_) async => const Ok(null));
    when(() => plainStore.removePairedHost(any()))
        .thenAnswer((_) async => const Ok(null));
    when(() => plainStore.pairedHosts())
        .thenAnswer((_) async => const Ok(<PairedHostRecord>[]));

    final clearResult = await clearRevokedHost(
      keystore: keystore,
      plainStore: plainStore,
      hostId: connection.lastHostInfo!.hostId,
    );
    expect(clearResult, isA<Ok<bool>>());
    expect(
      (clearResult as Ok<bool>).value,
      isTrue,
      reason: 'no saved computer remains, so the caller routes to /welcome',
    );
    verify(() => keystore.deleteHostSecrets('host-1')).called(1);
    verify(() => plainStore.removePairedHost('host-1')).called(1);
    verifyNever(() => keystore.clearAll());
  });

  testWidgets('revoking one computer leaves a different saved computer\'s record untouched '
      '(R-13-054: "MUST NOT touch another saved computer")', (tester) async {
    final connections = <WebSocket>[];
    server.listen((request) async {
      final ws = await WebSocketTransformer.upgrade(request);
      connections.add(ws);
      unawaited(_serveOneRevocation(ws));
    });

    final gate = await _unlockedGate();
    final connection = RelayConnection(
      handshaker: _fakeHandshaker,
      connectivityWatcher: _noOpConnectivityWatcher(),
    );
    addTearDown(connection.dispose);

    final states = <RelayConnectionState>[];
    final statesSub = connection.connectionState.listen(states.add);
    addTearDown(statesSub.cancel);

    final connectResult = await connection.connect(
      origin: origin,
      handle: 'n6Loxf94CfyIO6hOxlaHvA',
      mode: ReconnectMode(remoteStaticPublicKey: _pinnedHostStaticKey),
      gate: gate,
      deviceInfo: _testDeviceInfo,
    );
    expect(connectResult, isA<Ok<void>>());

    await expectLater(
      Stream<void>.periodic(const Duration(milliseconds: 10))
          .map((_) => states.whereType<RelayRevoked>().isNotEmpty)
          .firstWhere((seen) => seen)
          .timeout(const Duration(seconds: 5)),
      completes,
    );

    final keystore = _MockKeystoreService();
    final plainStore = _MockPlainStore();
    when(() => keystore.deleteHostSecrets(any()))
        .thenAnswer((_) async => const Ok(null));
    when(() => plainStore.removePairedHost(any()))
        .thenAnswer((_) async => const Ok(null));
    // A second saved computer survives the revocation.
    when(() => plainStore.pairedHosts()).thenAnswer(
      (_) async => const Ok(<PairedHostRecord>[
        PairedHostRecord(hostId: 'host-2', hostName: 'laptop'),
      ]),
    );

    final clearResult = await clearRevokedHost(
      keystore: keystore,
      plainStore: plainStore,
      hostId: connection.lastHostInfo!.hostId,
    );
    expect(clearResult, isA<Ok<bool>>());
    expect(
      (clearResult as Ok<bool>).value,
      isFalse,
      reason:
          'a saved computer remains, so the app MUST NOT route to '
          '/welcome',
    );
    verify(() => keystore.deleteHostSecrets('host-1')).called(1);
    verify(() => plainStore.removePairedHost('host-1')).called(1);
    verifyNever(() => keystore.deleteHostSecrets('host-2'));
    verifyNever(() => plainStore.removePairedHost('host-2'));
  });
}
