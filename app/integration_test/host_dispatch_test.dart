/// Phase 25 live-review defect: the Host bridge dropped every Device request except
/// `tree_request`, `watch_pane` and `send_input`, so the Devices screen, the scrollback,
/// the pane-actions sheet and the plugin-action list all waited forever. The fix is
/// `crates/herdr-relay/src/bridge.rs`'s `dispatch_incoming`/`bridge_thread` arms for
/// `device_list_request`, `scroll_request`, `unwatch_pane`, `action_list_request`,
/// `host_action` and `revoke_device`. This file is that defect's end-to-end case
/// (`docs/40-repo-tooling.md` §5.4, R-40-037): the real app stack on the device
/// (`RelayConnection`, real `Noise_XXpsk0`, real frame codec) against the real Host
/// code in `crates/herdr-relay/src/bin/e2e-stub-host.rs` (a real
/// `herdr_relay::watch::Bridge` over a stub Herdr), through a real relay.
///
/// The emulator cannot spawn `cargo`, so, unlike `app/test/e2e/full_stack_test.dart`,
/// the operator starts the two Rust processes on the workstation first and this test
/// reaches them through the emulator's host alias (`10.0.2.2`):
///
/// ```text
/// cd crates
/// HERDR_RELAY_LISTEN=127.0.0.1:18922 HERDR_RELAY_METRICS_LISTEN=127.0.0.1:19292 \
///   cargo run -p herdr-relay-hub
/// RELAY_ADDR=127.0.0.1:18922 HANDLE=AQIDBAUGBwgJCgsMDQ4PEQ \
///   PHRASE=remedy-tapestry-hubcap-oversleep-jailbird-kinetic \
///   cargo run -p herdr-relay --bin e2e-stub-host
/// cd ../app
/// flutter test integration_test/host_dispatch_test.dart -d emulator-5554
/// ```
///
/// Override the defaults with `--dart-define=HERDR_E2E_RELAY_ORIGIN=...`,
/// `HERDR_E2E_HANDLE=...`, `HERDR_E2E_PHRASE=...`. The stub Host serves one session and
/// exits, so restart it before a second run.
///
/// Each request below is sent with a `corr` and its typed reply awaited; the reply's
/// echoed `corr` is observed through the production seam `RelayConnection.lastRoundTrip`,
/// which only ever becomes non-null when an incoming frame echoes an outstanding `corr`
/// (R-11-031). The last case revokes the Device itself and asserts the wire order
/// R-11-064/R-11-065 fix: `revoke_result` first, then the fatal `revoked` error, then the
/// 4004 close surfaces as [RelayRevoked].
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart' show Ok;
import 'package:herdr_mobile/models/frame.dart';
import 'package:herdr_mobile/models/message.dart';
import 'package:herdr_mobile/models/messages/action_list_request.dart';
import 'package:herdr_mobile/models/messages/device_info.dart';
import 'package:herdr_mobile/models/messages/device_list_request.dart';
import 'package:herdr_mobile/models/messages/host_action.dart';
import 'package:herdr_mobile/models/messages/host_action_kind.dart';
import 'package:herdr_mobile/models/messages/platform.dart' as wire;
import 'package:herdr_mobile/models/messages/revoke_device.dart';
import 'package:herdr_mobile/models/messages/scroll_request.dart';
import 'package:herdr_mobile/services/biometric_gate.dart';
import 'package:herdr_mobile/services/connectivity.dart';
import 'package:herdr_mobile/services/keystore.dart' as keystore_service;
import 'package:herdr_mobile/services/noise.dart';
import 'package:herdr_mobile/services/origin.dart';
import 'package:herdr_mobile/services/relay.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mocktail/mocktail.dart';

/// `10.0.2.2` is the Android emulator's alias for the workstation's loopback
/// interface, inside R-22-039's `10.0.0.0/8` local-development allow list.
const _relayOrigin = String.fromEnvironment(
  'HERDR_E2E_RELAY_ORIGIN',
  defaultValue: 'http://10.0.2.2:18922',
);

/// A fresh 22-char base64url handle (R-11-112), distinct from
/// `app/test/e2e/full_stack_test.dart`'s so the two never collide on one relay.
const _handle = String.fromEnvironment(
  'HERDR_E2E_HANDLE',
  defaultValue: 'AQIDBAUGBwgJCgsMDQ4PEQ',
);

/// `docs/11-relay-protocol.md` §8.1's worked pairing phrase: a documented fixture,
/// not a secret.
const _phrase = String.fromEnvironment(
  'HERDR_E2E_PHRASE',
  defaultValue: 'remedy-tapestry-hubcap-oversleep-jailbird-kinetic',
);

/// MUST match `PANE_ID` and `CANNED_SCROLLBACK`'s first line in
/// `crates/herdr-relay/src/bin/e2e-stub-host.rs` exactly.
const _paneId = 'w1:p1';
const _cannedScrollbackHead = 'HERDR-E2E-STUB-SCROLLBACK-2b8e44';

/// MUST match `CANNED_ACTION_ID` in `e2e-stub-host.rs`.
const _cannedActionId = 'e2e-ping';

const _deviceId = 'e2e-dispatch-device';

const _replyTimeout = Duration(seconds: 10);

class _MockLocalAuthentication extends Mock implements LocalAuthentication {}

class _MockKeystoreService extends Mock
    implements keystore_service.KeystoreService {}

class _MockConnectivity extends Mock implements Connectivity {}

ConnectivityWatcher _noOpConnectivityWatcher() {
  final connectivity = _MockConnectivity();
  when(() => connectivity.onConnectivityChanged)
      .thenAnswer((_) => const Stream<List<ConnectivityResult>>.empty());
  return ConnectivityWatcher(connectivity: connectivity);
}

/// Mirrors `full_stack_test.dart`'s `_unlockedGate`: a real gate over a fresh
/// Curve25519 keypair, `local_auth` and the keystore mocked.
Future<BiometricGate> _unlockedGate() async {
  final localAuth = _MockLocalAuthentication();
  final mockKeystore = _MockKeystoreService();
  final keyPair = await X25519().newKeyPair();
  when(
    () =>
        localAuth.authenticate(localizedReason: any(named: 'localizedReason')),
  ).thenAnswer((_) async => true);
  when(() => mockKeystore.existingDeviceKeyPair())
      .thenAnswer((_) async => Ok(keyPair));
  final gate = BiometricGate(
    appLockEnabled: true,
    localAuth: localAuth,
    keystore: mockKeystore,
    setNativeLocked: (_) {},
  );
  final result = await gate.unlock();
  expect(result, isA<Ok<void>>());
  return gate;
}

/// Sends [request] with [corr] and returns the first reply of type [T]. The
/// subscription is armed before the send, so a fast reply is never missed.
Future<T> _request<T extends Message>(
  RelayConnection connection,
  Message request,
  String corr,
) async {
  final reply = connection.messages
      .where((m) => m is T)
      .cast<T>()
      .first
      .timeout(
        _replyTimeout,
        onTimeout: () => throw TimeoutException(
          'no ${T.toString()} reply to ${request.typeName} ($corr) within '
          '$_replyTimeout: the Host dropped the request',
        ),
      );
  connection.send(request, corr: corr);
  return reply;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late RelayConnection connection;
  final states = <RelayConnectionState>[];
  late StreamSubscription<RelayConnectionState> stateSubscription;

  setUpAll(() async {
    connection = RelayConnection(
      connectivityWatcher: _noOpConnectivityWatcher(),
    );
    stateSubscription = connection.connectionState.listen(states.add);
    final gate = await _unlockedGate();
    final origin = (parseRelayOrigin(_relayOrigin) as Ok<RelayOrigin>).value;
    final psk = await pskFromPhrase(_phrase);
    const deviceInfo = DeviceInfo(
      protocol: frameProtocolVersion,
      deviceId: _deviceId,
      deviceName: 'E2E Dispatch Harness',
      platform: wire.Platform.android,
      osVersion: '14',
      appVersion: '0.1.0',
    );
    final connectResult = await connection.connect(
      origin: origin,
      handle: _handle,
      mode: PairingMode(psk: psk),
      gate: gate,
      deviceInfo: deviceInfo,
    );
    expect(
      connectResult,
      isA<Ok<void>>(),
      reason:
          'the real Noise_XXpsk0 handshake against the stub Host must '
          'succeed (is e2e-stub-host running on $_relayOrigin?): $connectResult',
    );
    expect(connection.isConnected, isTrue);
  });

  tearDownAll(() async {
    await stateSubscription.cancel();
    await connection.dispose();
  });

  test(
    'device_list_request is answered with a correlated device_list',
    () async {
      expect(connection.lastRoundTrip, isNull);
      final reply = await _request<MessageDeviceList>(
        connection,
        const Message.deviceListRequest(DeviceListRequest()),
        'c-device-list',
      );
      final entry = reply.payload.devices.singleWhere((d) => d.id == _deviceId);
      expect(entry.name, 'E2E Dispatch Harness');
      expect(entry.platform, wire.Platform.android);
      expect(
        entry.connected,
        isTrue,
        reason: 'R-11-062: this session is connected',
      );
      expect(
        entry.fingerprint,
        matches(RegExp(r'^[0-9a-f]{4}(-[0-9a-f]{4}){3}$')),
        reason: 'R-13-040 fingerprint shape, never the raw key',
      );
      expect(
        connection.lastRoundTrip,
        isNotNull,
        reason: 'the reply echoed the corr (R-11-031)',
      );
    },
  );

  test('scroll_request is answered with the canned scroll_response', () async {
    final reply = await _request<MessageScrollResponse>(
      connection,
      const Message.scrollRequest(ScrollRequest(paneId: _paneId, lines: 200)),
      'c-scroll',
    );
    expect(reply.payload.paneId, _paneId);
    expect(reply.payload.text, startsWith(_cannedScrollbackHead));
    expect(reply.payload.lines, 3);
    expect(reply.payload.truncated, isTrue);
  });

  test('action_list_request is answered with the canned action_list', () async {
    final reply = await _request<MessageActionList>(
      connection,
      const Message.actionListRequest(ActionListRequest()),
      'c-actions',
    );
    expect(
      reply.payload.actions.map((a) => a.actionId),
      contains(_cannedActionId),
    );
  });

  test('host_action zoom is answered with host_action_ack', () async {
    final reply = await _request<MessageHostActionAck>(
      connection,
      const Message.hostAction(
        HostAction(action: HostActionKind.zoom, paneId: _paneId),
      ),
      'c-zoom',
    );
    expect(reply.payload.action, HostActionKind.zoom);
    expect(reply.payload.success, isTrue);
    expect(reply.payload.paneId, _paneId);
  });

  test('unwatch_pane has no reply and the session keeps serving', () async {
    var frames = 0;
    final counting = connection.messages.listen((_) => frames++);
    connection.unwatchPane(_paneId);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await counting.cancel();
    expect(frames, 0, reason: 'R-11-050: unwatch_pane has no reply');
    final reply = await _request<MessageDeviceList>(
      connection,
      const Message.deviceListRequest(DeviceListRequest()),
      'c-after-unwatch',
    );
    expect(reply.payload.devices, isNotEmpty);
  });

  test('revoke_device of this Device replies, then the fatal revoked error closes with 4004', () async {
    final revokedState = connection.connectionState
        .firstWhere((state) => state is RelayRevoked)
        .timeout(_replyTimeout);
    final fatalError = connection.messages
        .where((m) => m is MessageError)
        .cast<MessageError>()
        .firstWhere((m) => m.payload.fatal)
        .timeout(_replyTimeout);
    final reply = await _request<MessageRevokeResult>(
      connection,
      const Message.revokeDevice(RevokeDevice(deviceId: _deviceId)),
      'c-revoke',
    );
    expect(reply.payload.revoked, [_deviceId]);
    expect(reply.payload.all, isFalse);
    final error = await fatalError;
    expect(error.payload.fatal, isTrue, reason: 'R-11-065: fatal, last frame');
    await revokedState;
    expect(states.whereType<RelayRevoked>(), isNotEmpty);
    expect(connection.isConnected, isFalse);
  });
}
