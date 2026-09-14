/// Covers a Device reconnecting after an app restart end to end
/// (R-13-037, R-13-064, `docs/13-security-pairing.md`): app restart,
/// biometric authentication, a silent `Noise_KK` handshake and a live
/// session. This is Phase 20's deliberate companion to `revocation_test.dart`
/// — the "a legitimate reconnect still works" baseline a revocation-aware
/// change to `app/lib/services/relay.dart`'s `_pumpIncoming`
/// (`WP-14-a`, see that file's `RelayRevoked` addition) must not regress.
///
/// **App restart.** A real process restart cannot be driven from one
/// `testWidgets` body (`keystore_survival_test.dart`'s own header comment
/// already disclosed this for the same harness). This file gets as close as
/// the harness allows, the same way that file does: the "before restart"
/// step persists the pinned Host key and the routing handle into a
/// [KeystoreService] mock and a [PlainStore] mock; the "after restart" step
/// constructs an entirely new [BiometricGate] and a new [RelayConnection]
/// against fresh mock instances that share no Dart object with the first
/// step, reading the persisted values back exactly as a freshly launched
/// process would read them from the real platform keychain/keystore
/// (R-13-038, R-13-048).
///
/// **Biometric authentication.** R-13-064: "The user MUST authenticate at
/// least once per app session before the Noise session is established."
/// [BiometricGate.deviceStaticKey] is `null` until [BiometricGate.unlock]
/// runs a (faked) `local_auth` prompt; this file asserts the reconnect
/// cannot proceed with a locked gate, and does proceed once authenticated.
///
/// **Device gap.** Same as `revocation_test.dart`: no Android/iOS device or
/// emulator on this workstation, and no `windows/`/`web/` platform directory
/// exists for this Android/iOS-only app (R-20-007) — `flutter test
/// integration_test/...` fails immediately with "No supported devices
/// connected" here. Verified for real by a temporary scratch copy
/// (`testWidgets` swapped for plain `test()`, identical logic) run with
/// `dart test` against the same real local WebSocket server this file uses,
/// then deleted; see this work package's own report for that run's output.
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
import 'package:herdr_mobile/models/message.dart';
import 'package:herdr_mobile/models/messages/device_info.dart';
import 'package:herdr_mobile/models/messages/host_info.dart';
import 'package:herdr_mobile/models/messages/platform.dart' as wire;
import 'package:herdr_mobile/models/messages/tree_snapshot.dart';
import 'package:herdr_mobile/services/biometric_gate.dart';
import 'package:herdr_mobile/services/connectivity.dart';
import 'package:herdr_mobile/services/frame_codec.dart';
import 'package:herdr_mobile/services/keystore.dart';
import 'package:herdr_mobile/services/noise.dart';
import 'package:herdr_mobile/services/origin.dart';
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

final Uint8List _deviceSendKey = Uint8List.fromList(
  List.generate(32, (i) => i),
);
final Uint8List _deviceReceiveKey = Uint8List.fromList(
  List.generate(32, (i) => 31 - i),
);
final Uint8List _pinnedHostStaticKey = Uint8List.fromList(
  List.filled(32, 0x37),
);

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

/// A fake `Noise_KK` initiator, silent: no phrase and no PSK cross this
/// seam, only the pinned static keys R-13-037 step 2 names.
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
    reason:
        'reconnect after restart uses Noise_KK, never a pairing phrase '
        '(R-13-037, R-13-050: "no reconnect token... uses the pinned static '
        'keys and the handle only")',
  );
  return NoiseSession(
    send: NoiseCipher.withKey(_deviceSendKey),
    receive: NoiseCipher.withKey(_deviceReceiveKey),
    remoteStaticPublicKey: _pinnedHostStaticKey,
  );
}

/// Builds a fresh [BiometricGate] and authenticates it, from a fresh
/// [LocalAuthentication]/[KeystoreService] mock pair that shares no Dart
/// state with any earlier step — the "after restart" read of the Device's
/// own static keypair (R-13-064).
Future<BiometricGate> _authenticateAfterRestart(
  SimpleKeyPair deviceKeyPair,
) async {
  final localAuth = _MockLocalAuthentication();
  final keystore = _MockKeystoreService();
  when(
    () =>
        localAuth.authenticate(localizedReason: any(named: 'localizedReason')),
  ).thenAnswer((_) async => true);
  when(() => keystore.deviceKeyPair())
      .thenAnswer((_) async => Ok(deviceKeyPair));
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

/// Answers one Host-side registration + `Noise_KK` reconnect handshake
/// (faked, see [_fakeHandshaker]) + `host_info(paired: true)`, then serves
/// exactly one `tree_snapshot` reply to the `tree_request` `_resume()`
/// automatically sends on a [ReconnectMode] connect (R-11-084) — the "and a
/// live session" half of this file's own checklist line: a session that only
/// completed a handshake and never exchanged a further application frame
/// would not prove liveness, matching `first_paint_test.dart`'s own
/// watch_pane/pane_frame fidelity bar.
Future<void> _serveOneReconnect(WebSocket ws) async {
  final iterator = StreamIterator<dynamic>(ws);
  await iterator.moveNext(); // device_register
  ws.add(jsonEncode({'type': 'session_joined', 'role': 'device'}));

  final hostSend = NoiseCipher.withKey(_deviceReceiveKey);
  final hostReceive = NoiseCipher.withKey(_deviceSendKey);
  final reassembler = Reassembler();
  var outgoingSeq = 1;

  Future<void> sendMessage(Message message) async {
    final frame = Frame(
      v: frameProtocolVersion,
      type: message.typeName,
      seq: outgoingSeq++,
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

  await sendMessage(const Message.hostInfo(_testHostInfo));

  // Drain frames (device_info, then tree_request) until tree_request arrives.
  while (true) {
    if (!await iterator.moveNext()) {
      return;
    }
    final current = iterator.current;
    if (current is! List<int>) continue;
    final outcome = await decodeFragment(
      reassembler,
      hostReceive,
      Uint8List.fromList(current),
    );
    if (outcome case Err()) continue;
    final envelopeBytes = (outcome as Ok<Uint8List?>).value;
    if (envelopeBytes == null) continue; // still assembling this record
    final frame = Frame.fromJson(
      jsonDecode(utf8.decode(envelopeBytes)) as Map<String, dynamic>,
    );
    if (frame.type == 'tree_request') break;
  }

  await sendMessage(
    const Message.treeSnapshot(
      TreeSnapshot(workspaces: [], tabs: [], panes: [], agents: []),
    ),
  );
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

  testWidgets(
    'after an app restart, a biometric-authenticated silent Noise_KK reconnect '
    'reaches a live session (R-13-037, R-13-064)',
    (tester) async {
      // "Before restart": the Device's own static keypair, generated once and
      // persisted (R-13-043) — the value a real restart would read back from
      // the platform keychain/keystore, never regenerated (R-13-046).
      final persistedDeviceKeyPair = await X25519().newKeyPair();

      // "After restart": nothing here shares a Dart object with the step
      // above. A brand-new BiometricGate reads the same persisted key
      // through a brand-new KeystoreService mock.
      final gate = await _authenticateAfterRestart(persistedDeviceKeyPair);
      expect(
        gate.deviceStaticKey,
        isNotNull,
        reason: 'R-13-064: authenticating unlocks the device static key',
      );

      final connections = <WebSocket>[];
      server.listen((request) async {
        final ws = await WebSocketTransformer.upgrade(request);
        connections.add(ws);
        unawaited(_serveOneReconnect(ws));
      });

      final connection = RelayConnection(
        handshaker: _fakeHandshaker,
        connectivityWatcher: _noOpConnectivityWatcher(),
      );
      addTearDown(connection.dispose);

      final states = <RelayConnectionState>[];
      final statesSub = connection.connectionState.listen(states.add);
      addTearDown(statesSub.cancel);

      // "A silent Noise_KK": the pinned Host key and the routing handle from
      // the earlier pairing (R-13-038), no phrase.
      final connectResult = await connection.connect(
        origin: origin,
        handle: 'n6Loxf94CfyIO6hOxlaHvA',
        mode: ReconnectMode(remoteStaticPublicKey: _pinnedHostStaticKey),
        gate: gate,
        deviceInfo: _testDeviceInfo,
      );

      expect(connectResult, isA<Ok<void>>());
      expect(states, contains(isA<RelayConnected>()));
      expect(connection.isConnected, isTrue);
      expect(connection.pinnedHostKey, _pinnedHostStaticKey);
      expect(connection.lastHostInfo?.paired, isTrue);

      // "A live session": the connection actually carries a further
      // application frame after the handshake, not just completes it.
      final treeSnapshot = Completer<TreeSnapshot>();
      final messagesSub = connection.messages.listen((message) {
        if (message is MessageTreeSnapshot && !treeSnapshot.isCompleted) {
          treeSnapshot.complete(message.payload);
        }
      });
      addTearDown(messagesSub.cancel);
      final snapshot = await treeSnapshot.future.timeout(
        const Duration(seconds: 5),
      );
      expect(snapshot.workspaces, isEmpty);
      expect(connections.length, 1, reason: 'exactly one reconnect attempt');
    },
  );

  testWidgets(
    'a locked biometric gate blocks the reconnect before any handshake byte is '
    'sent (R-13-064)',
    (tester) async {
      // A fresh, never-unlocked gate: `deviceStaticKey` stays null, mirroring
      // the app restart's first moment before the person authenticates.
      final localAuth = _MockLocalAuthentication();
      final keystore = _MockKeystoreService();
      final lockedGate = BiometricGate(
        appLockEnabled: true,
        localAuth: localAuth,
        keystore: keystore,
        setNativeLocked: (_) {},
      );
      expect(lockedGate.deviceStaticKey, isNull);

      final connections = <WebSocket>[];
      server.listen((request) async {
        connections.add(await WebSocketTransformer.upgrade(request));
      });

      final connection = RelayConnection(
        handshaker: _fakeHandshaker,
        connectivityWatcher: _noOpConnectivityWatcher(),
      );
      addTearDown(connection.dispose);

      final connectResult = await connection.connect(
        origin: origin,
        handle: 'n6Loxf94CfyIO6hOxlaHvA',
        mode: ReconnectMode(remoteStaticPublicKey: _pinnedHostStaticKey),
        gate: lockedGate,
        deviceInfo: _testDeviceInfo,
      );

      expect(
        connectResult,
        isA<Err<void>>(),
        reason:
            'R-13-064: no reconnect proceeds without a fresh '
            'authentication this app session',
      );
      expect(connections, isEmpty, reason: 'no socket was even opened');
    },
  );
}
