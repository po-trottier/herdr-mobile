/// End-to-end cases for the five Device-side defects the product owner found in the live
/// review of 2026-09-03 (`docs/90-implementation-plan.md` Phase 25, "Live review on
/// 2026-09-03, Device side"), each driven against the real stub Host
/// `crates/herdr-relay/src/bin/e2e-stub-host.rs` through a real, locally run
/// `herdr-relay-hub`, per `docs/40-repo-tooling.md` §5.4 (R-40-037). The Device side is the
/// app's own `RelayConnection` (real `Noise_XXpsk0`, real frame codec, real WebSocket) and the
/// real screens, pumped under the app's one real theme.
///
/// This file runs on the Android emulator, so it cannot spawn the two Rust processes itself
/// (`full_stack_test.dart` does that on the workstation). Start them first, on the workstation,
/// then run this file against them. The emulator reaches the workstation's loopback as
/// `10.0.2.2` (R-22-039 permits the `http://` origin: `10.0.0.0/8`). Exact commands, from
/// `crates/`:
///
/// ```text
/// HERDR_RELAY_LISTEN=127.0.0.1:18922 HERDR_RELAY_METRICS_LISTEN=127.0.0.1:19292 \
///   cargo run -p herdr-relay-hub
/// RELAY_ADDR=127.0.0.1:18922 HANDLE=AQIDBAUGBwgJCgsMDQ4PEA \
///   PHRASE=remedy-tapestry-hubcap-oversleep-jailbird-kinetic \
///   cargo run -p herdr-relay --bin e2e-stub-host
/// RELAY_ADDR=127.0.0.1:18922 HANDLE=EA8ODQwLCgkIBwYFBAMCAQ \
///   PHRASE=remedy-tapestry-hubcap-oversleep-jailbird-kinetic \
///   E2E_STUB_IGNORE=device_list_request \
///   cargo run -p herdr-relay --bin e2e-stub-host
/// ```
///
/// then, from `app/`: `flutter test integration_test/live_review_fixes_test.dart -d
/// emulator-5554`. The three `--dart-define`s `E2E_RELAY_ORIGIN`, `E2E_HANDLE` and
/// `E2E_SILENT_HANDLE` override the defaults above. The second stub instance answers nothing
/// to `device_list_request`, which is the live defect the timeout case proves against.
///
/// The stub Host exits after one deliberate Device disconnect, so each stub instance serves
/// exactly one test below.
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/widgets.dart'
    show Brightness, ListView, Offset, Scrollable, Widget;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/app.dart'
    show appThemeFrom, sdkMaterialLocalizations;
import 'package:herdr_mobile/core/result/result.dart' show Ok;
import 'package:herdr_mobile/models/frame.dart';
import 'package:herdr_mobile/models/messages/device_info.dart';
import 'package:herdr_mobile/models/messages/platform.dart' as wire;
import 'package:herdr_mobile/screens/about_screen.dart';
import 'package:herdr_mobile/screens/connection_screen.dart';
import 'package:herdr_mobile/screens/device_list_screen.dart';
import 'package:herdr_mobile/screens/notifications_screen.dart';
import 'package:herdr_mobile/screens/settings_screen.dart';
import 'package:herdr_mobile/services/agent_status.dart' show NotificationItem;
import 'package:herdr_mobile/services/app_settings.dart';
import 'package:herdr_mobile/services/biometric_gate.dart';
import 'package:herdr_mobile/services/connectivity.dart';
import 'package:herdr_mobile/services/device_list.dart'
    show deviceListNoReplyText, deviceListReplyTimeout;
import 'package:herdr_mobile/services/keystore.dart';
import 'package:herdr_mobile/services/noise.dart';
import 'package:herdr_mobile/services/origin.dart';
import 'package:herdr_mobile/services/plain_store.dart';
import 'package:herdr_mobile/services/relay.dart';
import 'package:herdr_mobile/widgets/brand_mark.dart';
import 'package:herdr_mobile/widgets/eyebrow.dart';
import 'package:herdr_mobile/widgets/ground_grid.dart';
import 'package:herdr_mobile/widgets/theme/chrome_scheme.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:material_ui/material_ui.dart' show MaterialApp;
import 'package:mocktail/mocktail.dart';

/// The workstation's relay as the emulator sees it; the same port `full_stack_test.dart` uses.
const String _relayOrigin = String.fromEnvironment(
  'E2E_RELAY_ORIGIN',
  defaultValue: 'http://10.0.2.2:18922',
);

/// `full_stack_test.dart`'s own handle fixture: the stub instance that answers everything.
const String _handle = String.fromEnvironment(
  'E2E_HANDLE',
  defaultValue: 'AQIDBAUGBwgJCgsMDQ4PEA',
);

/// A second 22-character base64url handle (R-11-112): the stub instance started with
/// `E2E_STUB_IGNORE=device_list_request`.
const String _silentHandle = String.fromEnvironment(
  'E2E_SILENT_HANDLE',
  defaultValue: 'EA8ODQwLCgkIBwYFBAMCAQ',
);

/// `docs/11-relay-protocol.md` §8.1's worked pairing phrase, a documented fixture and not a
/// secret, shared with `full_stack_test.dart` and the stub's own tests.
const String _phrase = 'remedy-tapestry-hubcap-oversleep-jailbird-kinetic';

const String _deviceId = 'e2e-device-1';
const String _deviceName = 'E2E Harness';

class _MockLocalAuthentication extends Mock implements LocalAuthentication {}

class _MockKeystoreService extends Mock implements KeystoreService {}

class _MockConnectivity extends Mock implements Connectivity {}

ConnectivityWatcher _noOpConnectivityWatcher() {
  final connectivity = _MockConnectivity();
  when(() => connectivity.onConnectivityChanged)
      .thenAnswer((_) => const Stream<List<ConnectivityResult>>.empty());
  return ConnectivityWatcher(connectivity: connectivity);
}

/// Mirrors `full_stack_test.dart`'s `_unlockedGate`: a real gate over a fresh Curve25519 key,
/// with `local_auth` and the platform keystore mocked so no prompt appears on the emulator.
Future<BiometricGate> _unlockedGate() async {
  final localAuth = _MockLocalAuthentication();
  final mockKeystore = _MockKeystoreService();
  final keyPair = await X25519().newKeyPair();
  when(
    () =>
        localAuth.authenticate(localizedReason: any(named: 'localizedReason')),
  ).thenAnswer((_) async => true);
  when(() => mockKeystore.deviceKeyPair()).thenAnswer((_) async => Ok(keyPair));
  final gate = BiometricGate(
    appLockEnabled: true,
    localAuth: localAuth,
    keystore: mockKeystore,
    setNativeLocked: (_) {},
  );
  expect(await gate.unlock(), isA<Ok<void>>());
  return gate;
}

/// Connects the app's real relay stack to the stub instance registered on [handle].
Future<RelayConnection> _connect(String handle) async {
  final connection = RelayConnection(
    connectivityWatcher: _noOpConnectivityWatcher(),
  );
  final origin = (parseRelayOrigin(_relayOrigin) as Ok<RelayOrigin>).value;
  final result = await connection.connect(
    origin: origin,
    handle: handle,
    mode: PairingMode(psk: await pskFromPhrase(_phrase)),
    gate: await _unlockedGate(),
    deviceInfo: const DeviceInfo(
      protocol: frameProtocolVersion,
      deviceId: _deviceId,
      deviceName: _deviceName,
      platform: wire.Platform.android,
      osVersion: '16',
      appVersion: '0.1.0',
    ),
  );
  expect(result, isA<Ok<void>>(), reason: 'connect to $handle: $result');
  expect(connection.isConnected, isTrue);
  return connection;
}

/// The real app root's theme and localisations, as `golden_support.dart` builds them.
Future<void> _pumpScreen(WidgetTester tester, Widget child) =>
    tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: sdkMaterialLocalizations,
        theme: appThemeFrom(ChromeScheme.fixed(Brightness.light)),
        home: child,
      ),
    );

/// Pumps real frames until [finder] matches, or fails after [timeout]. The live binding runs
/// on the real clock, so a 5 s reply timeout takes 5 real seconds here.
Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('$finder never appeared within $timeout');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'against the answering stub Host: the four redesigned screens and the loaded devices list',
    (WidgetTester tester) async {
      final connection = await _connect(_handle);
      addTearDown(connection.dispose);
      final String hostName = connection.lastHostInfo!.hostName;

      // 1. Connection (R-31-13-23): the distinction table is four two-line rows with a tag.
      await _pumpScreen(
        tester,
        ConnectionScreen(
          hostId: connection.lastHostInfo!.hostId,
          hostName: hostName,
          connectionState: connection.connectionState,
          initialConnectionState: const RelayConnected(),
          relayOrigin: _relayOrigin,
          alertsDeliveryWord: 'ready',
          onReconnect: () async => const Ok<void>(null),
          onDisconnect: () async {},
        ),
      );
      await tester.pump();
      expect(find.text('CONNECTED'), findsNWidgets(2));
      await tester.scrollUntilVisible(
        find.text('Remove'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(
        find.textContaining('Alerts come from the computer'),
        findsOneWidget,
      );
      expect(find.text('Disconnect'), findsOneWidget);
      expect(find.text('Switching computer'), findsOneWidget);
      expect(find.text('Forget'), findsOneWidget);
      expect(find.text('NOT DESTRUCTIVE'), findsNWidgets(2));
      expect(find.text('DESTRUCTIVE'), findsNWidgets(2));

      // 2. Settings (R-31-15-19): no `MORE` header; `Alerts` and `About` are plain rows.
      final keystore = KeystoreService(
        appLockEnabled: false,
        storage: const FlutterSecureStorage(),
      );
      final appSettings = AppSettingsService();
      addTearDown(appSettings.dispose);
      await _pumpScreen(
        tester,
        SettingsScreen(
          appSettings: appSettings,
          keystore: keystore,
          gate: BiometricGate(
            appLockEnabled: false,
            keystore: keystore,
            setNativeLocked: (_) {},
          ),
          plainStore: PlainStore(),
          connection: connection,
          onOpenAlerts: () {},
          onOpenAbout: () {},
        ),
      );
      await _pumpUntil(tester, find.text('APPEARANCE'));
      await tester.dragUntilVisible(
        find.text('About'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pump();
      expect(find.text('MORE'), findsNothing);
      expect(find.text('SECURITY'), findsOneWidget);
      expect(find.text('Alerts'), findsOneWidget);
      expect(find.text('About'), findsOneWidget);

      // 3. Notifications (R-31-07-01, decided 2026-09-04): the destination that replaced the
      // panes tree, drawn empty over a fresh session log.
      await _pumpScreen(
        tester,
        NotificationsScreen(
          hostName: hostName,
          notifications: const Stream<List<NotificationItem>>.empty(),
          currentNotifications: const <NotificationItem>[],
          onMarkSeen: (_) async => const Ok(null),
          onMarkAllSeen: () async => const Ok(null),
          onRemove: (_) async => const Ok(null),
          onRemoveAll: () async => const Ok(null),
          onOpenPane: (_) {},
        ),
      );
      await _pumpUntil(tester, find.text('No notifications.'));
      expect(
        find.text('Agent status changes on $hostName appear here.'),
        findsOneWidget,
      );

      // 4. Licences (R-31-19-16): a plain list, no hero chrome, from the real registry.
      await _pumpScreen(tester, LicenceIndexScreen(onOpenPackage: (_) {}));
      await _pumpUntil(tester, find.text('Herdr Remote'));
      expect(find.byType(GroundGrid), findsNothing);
      expect(find.byType(BrandMark), findsNothing);
      expect(find.byType(Eyebrow), findsNothing);

      // 5. Devices (R-31-14-14, loaded path): the stub answers `device_list_request`, so the
      // skeleton gives way to this phone's own row.
      await _pumpScreen(
        tester,
        DeviceListScreen(
          hostName: hostName,
          localDeviceId: _deviceId,
          messages: connection.messages,
          connectionState: connection.connectionState,
          send: connection.send,
        ),
      );
      await _pumpUntil(tester, find.text('THIS PHONE'));
      expect(find.textContaining(_deviceName), findsWidgets);
      expect(find.text('Could not read the phone list.'), findsNothing);

      await connection.disconnect();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'against the silent stub Host: the devices list leaves the skeleton for the no-reply '
    'error after deviceListReplyTimeout (R-31-14-14)',
    (WidgetTester tester) async {
      final connection = await _connect(_silentHandle);
      addTearDown(connection.dispose);

      await _pumpScreen(
        tester,
        DeviceListScreen(
          hostName: connection.lastHostInfo!.hostName,
          localDeviceId: _deviceId,
          messages: connection.messages,
          connectionState: connection.connectionState,
          send: connection.send,
        ),
      );
      await _pumpUntil(
        tester,
        find.text('Could not read the phone list.'),
        timeout: deviceListReplyTimeout + const Duration(seconds: 5),
      );
      expect(find.text(deviceListNoReplyText), findsOneWidget);
      expect(find.text('TRY AGAIN'), findsOneWidget);

      // A real interaction: `Try again` sends a fresh request, which the silent Host also
      // ignores, so the same block returns after one more timeout.
      await tester.tap(find.text('TRY AGAIN'));
      await tester.pump();
      expect(find.text('Could not read the phone list.'), findsNothing);
      await _pumpUntil(
        tester,
        find.text('Could not read the phone list.'),
        timeout: deviceListReplyTimeout + const Duration(seconds: 5),
      );

      await connection.disconnect();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
