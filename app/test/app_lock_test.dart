/// Session lock security regressions; app composition is owned by WP-12-b.
library;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/app.dart';
import 'package:herdr_mobile/core/result/result.dart';
import 'package:herdr_mobile/routing.dart';
import 'package:herdr_mobile/services/app_settings.dart';
import 'package:herdr_mobile/services/biometric_gate.dart';
import 'package:herdr_mobile/services/connectivity.dart';
import 'package:herdr_mobile/services/keystore.dart';
import 'package:herdr_mobile/services/notifications.dart';
import 'package:herdr_mobile/services/plain_store.dart';
import 'package:herdr_mobile/services/relay.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'frame_presentation_support.dart';

class _Keystore extends Mock implements KeystoreService {}

class _LocalAuth extends Mock implements LocalAuthentication {}

class _Connectivity extends Mock implements Connectivity {}

class _Notifications extends Mock implements NotificationsService {
  @override
  void Function(String, String)? onNotificationTapped;
}

class _Settings extends Mock implements AppSettingsService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime clock;
  late BiometricGate gate;
  late _Keystore keystore;
  late AppSettingsService settings;
  late RelayConnection relay;
  late _Notifications notifications;
  late SimpleKeyPair key;
  const channel = MethodChannel('dev.fluttercommunity.plus/connectivity');
  const lockChannel = MethodChannel('dev.herdr.herdr_mobile/biometric_lock');

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    settings = AppSettingsService();
    await settings.setAppLockEnabled(value: true);
    await PlainStore().savePairedHost(
      const PairedHostRecord(hostId: 'h1', hostName: 'Private fixture desktop'),
    );
    clock = DateTime(2026);
    key = await X25519().newKeyPairFromSeed(List<int>.filled(32, 7));
    keystore = _Keystore();
    when(keystore.existingDeviceKeyPair)
        .thenAnswer((_) async => const Err('denied'));
    final auth = _LocalAuth();
    when(auth.getAvailableBiometrics)
        .thenAnswer((_) async => [BiometricType.face]);
    gate = BiometricGate(
      appLockEnabled: true,
      keystore: keystore,
      localAuth: auth,
      now: () => clock,
      setNativeLocked: (_) {},
    );
    final network = _Connectivity();
    when(() => network.onConnectivityChanged)
        .thenAnswer((_) => const Stream<List<ConnectivityResult>>.empty());
    relay = RelayConnection(
      connectivityWatcher: ConnectivityWatcher(connectivity: network),
    );
    notifications = _Notifications();
    when(notifications.initialize).thenAnswer((_) async => const Ok(null));
    when(() => notifications.setBadgeCount(any())).thenAnswer((_) async {});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => ['none']);
    messenger.setMockMethodCallHandler(lockChannel, (_) async => null);
  });
  tearDown(() async {
    await relay.dispose();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(lockChannel, null);
  });

  Future<void> pumpApp(WidgetTester tester) async {
    appRouter.go('/hosts');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsServiceProvider.overrideWithValue(settings),
          biometricGateProvider.overrideWithValue(gate),
          keystoreServiceProvider.overrideWithValue(keystore),
          relayConnectionProvider.overrideWithValue(relay),
          notificationsServiceProvider.overrideWithValue(notifications),
        ],
        child: const HerdrRemoteApp(),
      ),
    );
    await pumpRasterized(tester);
  }

  Future<void> unlock() async {
    when(keystore.existingDeviceKeyPair).thenAnswer((_) async => Ok(key));
    await gate.unlock();
    when(keystore.existingDeviceKeyPair)
        .thenAnswer((_) async => const Err('denied'));
  }

  testWidgets(
    'a direct protected route cannot reveal saved Host names while locked',
    (tester) async {
      await pumpApp(tester);
      expect(find.text('Private fixture desktop'), findsNothing);
      expect(find.text('Not recognised. Try again.'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await pumpRasterized(tester);
      expect(find.text('Private fixture desktop'), findsNothing);
      expect(gate.isLocked, isTrue);
      verify(keystore.existingDeviceKeyPair).called(1);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'background timeout hides the previous Host list until authentication',
    (tester) async {
      await unlock();
      await pumpApp(tester);
      expect(find.text('Private fixture desktop'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      clock = clock.add(const Duration(seconds: 121));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumpRasterized(tester);
      expect(gate.isLocked, isTrue);
      expect(find.text('Private fixture desktop'), findsNothing);
      expect(find.text('Not recognised. Try again.'), findsOneWidget);

      when(keystore.existingDeviceKeyPair).thenAnswer((_) async => Ok(key));
      await tester.tap(
        find.text(
          defaultTargetPlatform == TargetPlatform.iOS
              ? 'Unlock with Face ID'
              : 'Unlock with face unlock',
        ),
      );
      await pumpRasterized(tester);
      expect(find.text('Private fixture desktop'), findsOneWidget);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets('inactive app excludes sensitive content from its visible tree', (
    tester,
  ) async {
    await unlock();
    await pumpApp(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('Private fixture desktop'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await pumpRasterized(tester);
    expect(gate.isLocked, isFalse);
    expect(find.text('Private fixture desktop'), findsOneWidget);
  });
  testWidgets('an unreadable lock policy fails closed before routes build', (
    tester,
  ) async {
    final unreadable = _Settings();
    when(() => unreadable.current).thenReturn(const AppSettings());
    when(() => unreadable.changes)
        .thenAnswer((_) => const Stream<AppSettings>.empty());
    when(unreadable.load)
        .thenAnswer((_) async => const Err('fixture read failed'));
    settings = unreadable;
    await pumpApp(tester);
    expect(find.text('Private fixture desktop'), findsNothing);
    expect(
      find.text('Unable to load App Lock settings. Reopen the app.'),
      findsOneWidget,
    );
    verifyNever(keystore.existingDeviceKeyPair);
  });

  testWidgets(
    'locked root hides Navigator dialogs and their accessibility contents',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await unlock();
      await pumpApp(tester);
      final modal = rootNavigatorKey.currentState!.push<void>(
        PageRouteBuilder(
          pageBuilder: (_, _, _) =>
              const Center(child: Text('Private fixture modal')),
        ),
      );
      await pumpRasterized(tester);
      expect(find.text('Private fixture modal'), findsOneWidget);
      gate.noteLifecycleChange(AppLifecycleState.detached);
      await pumpRasterized(tester);
      expect(find.text('Private fixture modal'), findsNothing);
      expect(find.bySemanticsLabel('Private fixture modal'), findsNothing);
      expect(find.text('Private fixture desktop'), findsNothing);
      // Cleanup only the synthetic route this test created.
      rootNavigatorKey.currentState!.pop();
      await pumpRasterized(tester);
      await modal;
      semantics.dispose();
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'changing to Settings while locked neither exposes controls nor retries Face ID',
    (tester) async {
      await pumpApp(tester);
      appRouter.go('/settings');
      await pumpRasterized(tester);
      expect(find.text('App Lock'), findsNothing);
      expect(find.text('Not recognised. Try again.'), findsOneWidget);
      verify(keystore.existingDeviceKeyPair).called(1);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );
  testWidgets(
    'a cold notification is held until the protected Navigator exists',
    (tester) async {
      when(notifications.initialize).thenAnswer((_) async {
        notifications.onNotificationTapped!('h1', 'p1');
        return const Ok(null);
      });
      await pumpApp(tester);
      expect(tester.takeException(), isNull);
      expect(gate.isLocked, isTrue);
      expect(appRouter.state.uri.path, '/lock');
      expect(appRouter.state.uri.queryParameters['from'], '/hosts/h1/panes/p1');
      expect(find.text('Private fixture desktop'), findsNothing);
    },
  );
}
