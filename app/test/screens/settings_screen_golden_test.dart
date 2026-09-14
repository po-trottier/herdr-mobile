/// Golden tests for `SettingsScreen` (`app/lib/screens/settings_screen.dart`, `WP-21-b`), one
/// per named row of `docs/31-mockups/15-appearance.md`'s `## States` table (R-90-011), each
/// rendered in both Selenized dark and light (R-32-012).
///
/// `SettingsScreen` owns no presentational split (its own top doc comment explains why): every
/// live value comes straight from real services on mount, so this file reuses
/// `settings_screen_test.dart`'s own fake-service harness -- a seeded `FlutterSecureStorage`
/// mock, an in-memory `SharedPreferencesAsync`, and a `RelayConnection` built on a no-op
/// `ConnectivityWatcher` -- rather than building a second one. The connected-computer group
/// never renders here: nothing in this harness opens a real relay socket, which is the same
/// "nothing paired, nothing connected" state `settings_screen_test.dart` itself exercises, and
/// a normal, documented state per the mockup's own `Nothing connected` row.
///
/// Fonts, the app theme and the 375 x 667 reference size come from `golden_support.dart`
/// (`loadAppFonts`, `goldenApp`, `goldenReferenceSize`); see its doc comment for why.
/// `devicePixelRatio` stays fixed at 1.0, so each PNG's pixel dimensions equal the logical size.
library;

import 'dart:async' show unawaited;

import 'package:connectivity_plus/connectivity_plus.dart'
    show Connectivity, ConnectivityResult;
import 'package:cupertino_ui/cupertino_ui.dart'
    show
        CupertinoListSection,
        CupertinoListTile,
        CupertinoNavigationBar,
        CupertinoNavigationBarBackButton,
        CupertinoPage,
        CupertinoSwitch;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart' show MethodCall, SystemChannels;
import 'package:flutter/widgets.dart'
    show
        Brightness,
        CustomScrollView,
        HeroControllerScope,
        Navigator,
        Page,
        SizedBox;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/screens/settings_screen.dart';
import 'package:herdr_mobile/services/app_settings.dart';
import 'package:herdr_mobile/services/biometric_gate.dart' show BiometricGate;
import 'package:herdr_mobile/services/connectivity.dart'
    show ConnectivityWatcher;
import 'package:herdr_mobile/services/keystore.dart' show KeystoreService;
import 'package:herdr_mobile/services/plain_store.dart' show PlainStore;
import 'package:herdr_mobile/services/relay.dart' show RelayConnection;
import 'package:herdr_mobile/widgets/app_list_row.dart' show AppListRow;
import 'package:local_auth/local_auth.dart' show LocalAuthentication;
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'golden_support.dart';

/// The mockup supplies the phone name for these snapshots.
const String _phoneName = 'Pixel 8';

class _MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

class _MockConnectivity extends Mock implements Connectivity {}

class _MockLocalAuthentication extends Mock implements LocalAuthentication {}

/// Mirrors `settings_screen_test.dart`'s own helper: `RelayConnection`'s constructor starts a
/// real `ConnectivityWatcher`, whose `onConnectivityChanged` subscription needs a live platform
/// binding plain `flutter_test` never initialises.
ConnectivityWatcher _noOpConnectivityWatcher() {
  final connectivity = _MockConnectivity();
  when(() => connectivity.onConnectivityChanged)
      .thenAnswer((_) => const Stream<List<ConnectivityResult>>.empty());
  return ConnectivityWatcher(connectivity: connectivity);
}

const _themes = <(String, Brightness)>[
  ('dark', Brightness.dark),
  ('light', Brightness.light),
];

void main() {
  setUpAll(loadAppFonts);

  late _MockFlutterSecureStorage storage;
  late KeystoreService keystore;
  late BiometricGate gate;
  late PlainStore plainStore;
  late AppSettingsService appSettings;
  late RelayConnection connection;

  setUp(() async {
    // `AppHaptic` calls `HapticFeedback`, which invokes `SystemChannels.platform` -- with no
    // handler registered, plain `flutter_test` leaves that call pending forever. This screen's
    // build itself fires no haptic, but `pumpAndSettle` still needs the channel answered in
    // case a pending future from a previous frame resolves during settling.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (MethodCall call) async => null,
        );
    storage = _MockFlutterSecureStorage();
    final backing = <String, String>{};
    when(() => storage.read(key: any(named: 'key')))
        .thenAnswer((invocation) async {
          final key = invocation.namedArguments[#key] as String;
          return backing[key];
        });
    when(
      () => storage.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
      ),
    ).thenAnswer((invocation) async {
      final key = invocation.namedArguments[#key] as String;
      final value = invocation.namedArguments[#value] as String?;
      if (value == null) {
        backing.remove(key);
      } else {
        backing[key] = value;
      }
    });
    when(() => storage.delete(key: any(named: 'key')))
        .thenAnswer((invocation) async {
          backing.remove(invocation.namedArguments[#key] as String);
        });
    keystore = KeystoreService(appLockEnabled: false, storage: storage);
    // A no-op: `BiometricGate`'s constructor clears the native `FLAG_SECURE` channel
    // immediately when App Lock starts off, and needs a stub or the real
    // `_defaultSetNativeLocked` throws `MissingPluginException` with no platform binding.
    gate = BiometricGate(
      appLockEnabled: false,
      keystore: keystore,
      setNativeLocked: (_) {},
    );
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    plainStore = PlainStore();
    // Seeded before the screen mounts, so `_loadAll`'s first read already sees the name.
    await plainStore.setDeviceName(_phoneName);
    appSettings = AppSettingsService();
    connection = RelayConnection(
      connectivityWatcher: _noOpConnectivityWatcher(),
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    await appSettings.dispose();
    unawaited(connection.dispose());
  });

  for (final (themeName, brightness) in _themes) {
    testWidgets(
      'default ($themeName) matches docs/31-mockups/15-appearance.md',
      (tester) async {
        tester.view.physicalSize = goldenReferenceSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          goldenApp(
            brightness: brightness,
            child: SettingsScreen(
              appSettings: appSettings,
              keystore: keystore,
              gate: gate,
              plainStore: plainStore,
              connection: connection,
              // The `Status colours` row is in frame: wired, as `routing.dart` wires it, so
              // the golden shows the live row and not the `null`-callback dim (R-32-502).
              onOpenStatusColours: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Structural proof alongside the visual one: every documented default-state value is
        // really in the tree, not just painted to look right by coincidence. Only the top of
        // the list is asserted unscrolled: the iPhone SE reference viewport is short enough
        // that `FEEL` and everything below it needs a real scroll to reach, which the
        // `no_screen_lock` case below proves instead.
        expect(find.text('Settings'), findsOneWidget);
        expect(find.text('RELAY'), findsNothing);
        expect(find.text('APPEARANCE'), findsOneWidget);
        expect(find.text('Theme'), findsOneWidget);
        // `System` is `AppSettings()`'s own default themeMode (R-30-112), the selected segment
        // of the always-visible control per the mockup's callout 8.
        expect(find.text('System'), findsOneWidget);
        expect(find.text('Terminal text size'), findsOneWidget);
        // `13` is `defaultTerminalTextSize` (R-32-208), written `13 pt` as callout 10 does.
        expect(find.text('13 pt'), findsOneWidget);

        await expectLater(
          find.byType(SettingsScreen),
          matchesGoldenFile('goldens/settings_screen_default_$themeName.png'),
        );
      },
    );

    testWidgets(
      'no_screen_lock ($themeName) matches docs/31-mockups/15-appearance.md',
      (tester) async {
        tester.view.physicalSize = goldenReferenceSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final localAuth = _MockLocalAuthentication();
        when(() => localAuth.isDeviceSupported())
            .thenAnswer((_) async => false);

        await tester.pumpWidget(
          goldenApp(
            brightness: brightness,
            child: SettingsScreen(
              appSettings: appSettings,
              keystore: keystore,
              gate: gate,
              plainStore: plainStore,
              connection: connection,
              localAuth: localAuth,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // `SECURITY` sits below the fold on the iPhone SE reference viewport: scroll it into
        // view first, mirroring `settings_screen_test.dart`'s own `dragUntilVisible` use. The
        // golden below then captures this state's one distinguishing row, scrolled into frame.
        await tester.dragUntilVisible(
          find.text('App Lock'),
          find.byType(CustomScrollView),
          const Offset(0, -200),
        );
        await tester.pumpAndSettle();
        expect(find.text('SECURITY'), findsOneWidget);
        expect(find.text('App Lock'), findsOneWidget);
        expect(
          find.text(
            "This phone has no screen lock. Add a passcode or fingerprint "
            "in your phone's settings, then come back.",
          ),
          findsOneWidget,
        );

        await expectLater(
          find.byType(SettingsScreen),
          matchesGoldenFile(
            'goldens/settings_screen_no_screen_lock_$themeName.png',
          ),
        );
      },
    );

    // The end of the list: `SECURITY`, then `Alerts` and `About` as plain rows with no group
    // header over them (decided 2026-09-03 by the product owner: the old `MORE` header read as
    // an action and did nothing). The two navigation rows are wired, so they render at full
    // ink, as they do in the app.
    testWidgets(
      'list_end ($themeName) matches docs/31-mockups/15-appearance.md',
      (tester) async {
        tester.view.physicalSize = goldenReferenceSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          goldenApp(
            brightness: brightness,
            child: SettingsScreen(
              appSettings: appSettings,
              keystore: keystore,
              gate: gate,
              plainStore: plainStore,
              connection: connection,
              onOpenAlerts: () {},
              onOpenAbout: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.dragUntilVisible(
          find.text('About'),
          find.byType(CustomScrollView),
          const Offset(0, -200),
        );
        await tester.pumpAndSettle();
        expect(find.text('SECURITY'), findsOneWidget);
        expect(find.text('Alerts'), findsOneWidget);
        expect(find.text('About'), findsOneWidget);
        expect(find.text('MORE'), findsNothing);

        await expectLater(
          find.byType(SettingsScreen),
          matchesGoldenFile('goldens/settings_screen_list_end_$themeName.png'),
        );
      },
    );
  }

  // The iOS branch: `CupertinoPageScaffold` over `ChromeSettingsSection`'s inset-grouped
  // `CupertinoListSection`, every row a `CupertinoListTile` through `ChromeListRow` (R-33-073,
  // amended 2026-09-08). The frames prove three things at once. No `Text` falls back to
  // `MaterialApp`'s yellow double underline (R-41-020); the section's own separators are the
  // only dividers, because no `AppListRow` renders on iOS, so no row hairline stacks on the
  // section's into a 2 px line (R-32-515); and the toggle rows trail a `CupertinoSwitch`.
  for (final (themeName, brightness) in _themes) {
    testWidgets(
      'default_ios ($themeName) matches docs/31-mockups/15-appearance.md',
      (tester) async {
        tester.view.physicalSize = goldenReferenceSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        // Reset inside the body: the binding checks foundation debug variables before
        // `addTearDown` callbacks run.
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

        await tester.pumpWidget(
          goldenApp(
            brightness: brightness,
            child: SettingsScreen(
              appSettings: appSettings,
              keystore: keystore,
              gate: gate,
              plainStore: plainStore,
              connection: connection,
              onOpenStatusColours: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(CupertinoNavigationBar), findsOneWidget);
        expect(find.byType(CupertinoListSection), findsWidgets);
        expect(find.text('RELAY'), findsNothing);
        expect(find.text('APPEARANCE'), findsOneWidget);

        await expectLater(
          find.byType(SettingsScreen),
          matchesGoldenFile(
            'goldens/settings_screen_default_ios_$themeName.png',
          ),
        );
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      'list_end_ios ($themeName) matches docs/31-mockups/15-appearance.md',
      (tester) async {
        tester.view.physicalSize = goldenReferenceSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

        await tester.pumpWidget(
          goldenApp(
            brightness: brightness,
            child: SettingsScreen(
              appSettings: appSettings,
              keystore: keystore,
              gate: gate,
              plainStore: plainStore,
              connection: connection,
              onOpenAlerts: () {},
              onOpenAbout: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.dragUntilVisible(
          find.text('About'),
          find.byType(CustomScrollView),
          const Offset(0, -200),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AppListRow), findsNothing);
        expect(find.byType(CupertinoSwitch), findsWidgets);
        for (final label in <String>['App Lock', 'Alerts', 'About']) {
          expect(
            find.ancestor(
              of: find.text(label),
              matching: find.byType(CupertinoListTile),
            ),
            findsOneWidget,
          );
        }

        await expectLater(
          find.byType(SettingsScreen),
          matchesGoldenFile(
            'goldens/settings_screen_list_end_ios_$themeName.png',
          ),
        );
        debugDefaultTargetPlatformOverride = null;
      },
    );

    // A genuinely pushed route: the harness `Navigator` holds a placeholder page under the
    // settings page, both `CupertinoPage`s as `routing.dart`'s `_platformPage` builds them, so
    // `CupertinoNavigationBar` implies its own back button. Its chevron is `CupertinoIcons.back`
    // from the `cupertino_icons` font (`app/pubspec.yaml`, added 2026-09-08). The frame proves
    // the glyph renders as a chevron, not a tofu box; R-33-070 forbids the app from drawing a
    // back glyph of its own, so no `lib/` fallback can hide a missing font. The nested
    // `Navigator` sits in `HeroControllerScope.none`, as go_router's own shell branches do,
    // because `MaterialApp`'s `HeroController` MUST NOT be shared by two navigators.
    testWidgets(
      'pushed_ios ($themeName) shows the automatic back button (R-33-070)',
      (tester) async {
        tester.view.physicalSize = goldenReferenceSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

        await tester.pumpWidget(
          goldenApp(
            brightness: brightness,
            child: HeroControllerScope.none(
              child: Navigator(
                onDidRemovePage: (_) {},
                pages: <Page<void>>[
                  const CupertinoPage<void>(child: SizedBox.shrink()),
                  CupertinoPage<void>(
                    child: SettingsScreen(
                      appSettings: appSettings,
                      keystore: keystore,
                      gate: gate,
                      plainStore: plainStore,
                      connection: connection,
                      onOpenStatusColours: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(CupertinoNavigationBar), findsOneWidget);
        expect(find.byType(CupertinoNavigationBarBackButton), findsOneWidget);
        expect(find.text('Settings'), findsOneWidget);
        expect(find.text('RELAY'), findsNothing);

        await expectLater(
          find.byType(SettingsScreen),
          matchesGoldenFile(
            'goldens/settings_screen_pushed_ios_$themeName.png',
          ),
        );
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
}
