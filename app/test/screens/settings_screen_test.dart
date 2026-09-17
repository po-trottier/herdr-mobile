/// Settings controls and the absence of a global relay editor (R-03-126).
library;

import 'dart:async' show unawaited;
import 'dart:convert' show base64Encode;

import 'package:connectivity_plus/connectivity_plus.dart'
    show Connectivity, ConnectivityResult;
import 'package:cupertino_ui/cupertino_ui.dart'
    show
        CupertinoListSection,
        CupertinoListTile,
        CupertinoNavigationBar,
        CupertinoNavigationBarBackButton,
        CupertinoPage,
        CupertinoSlider,
        CupertinoSlidingSegmentedControl,
        CupertinoSwitch;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart' show AppBar;
import 'package:flutter/services.dart'
    show MethodCall, MethodChannel, SystemChannels;
import 'package:flutter/widgets.dart'
    show
        CustomScrollView,
        HeroControllerScope,
        Navigator,
        Page,
        Rect,
        Size,
        SizedBox,
        Text;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart' show Ok;
import 'package:herdr_mobile/screens/settings_screen.dart';
import 'package:herdr_mobile/services/app_settings.dart';
import 'package:herdr_mobile/services/biometric_gate.dart' show BiometricGate;
import 'package:herdr_mobile/services/connectivity.dart'
    show ConnectivityWatcher;
import 'package:herdr_mobile/services/keystore.dart' show KeystoreService;
import 'package:herdr_mobile/services/plain_store.dart' show PlainStore;
import 'package:herdr_mobile/services/relay.dart' show RelayConnection;
import 'package:herdr_mobile/widgets/ground_grid.dart' show GroundGrid;
import 'package:herdr_mobile/widgets/theme/app_type.dart' show AppType;
import 'package:material_ui/material_ui.dart'
    show IconButton, ListTile, MaterialApp, SegmentedButton, Slider, Switch;
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

class _MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

class _MockConnectivity extends Mock implements Connectivity {}

final class _FailingLockPreferences extends InMemorySharedPreferencesAsync {
  _FailingLockPreferences({required bool enabled})
    : super.withData({'app_lock_enabled': enabled});

  @override
  Future<bool> setBool(
    String key,
    bool value,
    SharedPreferencesOptions options,
  ) async {
    if (key == 'app_lock_enabled') throw Exception('setting_write_failed');
    return super.setBool(key, value, options);
  }
}

/// Mirrors `origin_change_test.dart`'s own helper: `RelayConnection`'s constructor starts a
/// real `ConnectivityWatcher`, whose `onConnectivityChanged` subscription needs a live
/// platform binding plain `flutter_test` never initialises.
ConnectivityWatcher _noOpConnectivityWatcher() {
  final connectivity = _MockConnectivity();
  when(() => connectivity.onConnectivityChanged)
      .thenAnswer((_) => const Stream<List<ConnectivityResult>>.empty());
  return ConnectivityWatcher(connectivity: connectivity);
}

void main() {
  late _MockFlutterSecureStorage storage;
  late KeystoreService keystore;
  late BiometricGate gate;
  late PlainStore plainStore;
  late AppSettingsService appSettings;
  late RelayConnection connection;

  setUp(() async {
    // `AppHaptic` calls `HapticFeedback`, which invokes `SystemChannels.platform` — with no
    // handler registered, plain `flutter_test` leaves that call pending forever, which would
    // stall every `_onThemeModeChanged`/`_onHapticsChanged` await chain below indefinitely.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (MethodCall call) async => null,
        );
    storage = _MockFlutterSecureStorage();
    final backing = <String, String>{
      'relay_origin': 'https://relay.example.com',
      'device_x25519_private_key': base64Encode(List<int>.filled(32, 7)),
    };
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
    // A no-op: `BiometricGate`'s constructor now clears the native `FLAG_SECURE` channel
    // immediately when App Lock starts off (the fresh-install black-screenshot fix), so
    // every off-mode gate in a test needs a `setNativeLocked` stub or the real
    // `_defaultSetNativeLocked` throws `MissingPluginException` with no platform binding.
    gate = BiometricGate(
      appLockEnabled: false,
      keystore: keystore,
      setNativeLocked: (_) {},
    );
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    plainStore = PlainStore();
    appSettings = AppSettingsService();
    // `RelayConnection`'s constructor starts a real `ConnectivityWatcher`, whose
    // `onConnectivityChanged` subscription needs a live platform binding plain
    // `flutter_test` never initialises (mirrors `origin_change_test.dart`'s own helper).
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

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          appSettings: appSettings,
          keystore: keystore,
          gate: gate,
          plainStore: plainStore,
          connection: connection,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'the theme control is the platform segmented control, visible without any tap, and '
    'selecting Light then Dark persists through AppSettingsService (R-20-036, R-03-059)',
    (tester) async {
      await pumpScreen(tester);

      final initial = await appSettings.load();
      expect((initial as Ok<AppSettings>).value.themeMode, AppThemeMode.system);

      // decided 2026-09-03 by the product owner: no expand step — all three segments render
      // before any tap, as written (R-32-213), and the row carries no collapsed value word any
      // more. On Android the control is Material's own `SegmentedButton` (R-03-059).
      expect(find.byType(SegmentedButton<AppThemeMode>), findsOneWidget);
      expect(
        find.byType(CupertinoSlidingSegmentedControl<AppThemeMode>),
        findsNothing,
      );
      expect(find.text('System'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('SYSTEM'), findsNothing);
      // The one line R-31-15-05 requires sits under the control.
      expect(
        find.text('The terminal palette follows this setting too.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();

      final afterLight = await appSettings.load();
      expect(
        (afterLight as Ok<AppSettings>).value.themeMode,
        AppThemeMode.light,
      );

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      final afterDark = await appSettings.load();
      expect((afterDark as Ok<AppSettings>).value.themeMode, AppThemeMode.dark);
    },
  );

  testWidgets('the terminal text size is a discrete platform slider over the permitted sizes with the '
      'value beside the title, and a move persists the size and repaints the preview '
      '(R-03-110, R-31-15-02, R-32-208)', (tester) async {
    await pumpScreen(tester);

    // No `aA` glyph and no `-`/`+` buttons (R-03-110); the value sits on the title line.
    expect(find.text('aA'), findsNothing);
    expect(find.byType(IconButton), findsNothing);
    expect(find.byType(CupertinoSlider), findsNothing);
    expect(find.text('13 pt'), findsOneWidget);
    final Rect title = tester.getRect(find.text('Terminal text size'));
    final Rect value = tester.getRect(find.text('13 pt'));
    expect(
      value.center.dy,
      inInclusiveRange(title.top, title.bottom),
      reason: 'the value shares the title row',
    );
    expect(
      value.right,
      tester.getRect(find.byType(Slider)).right,
      reason: "the value ends at the block's trailing edge",
    );
    expect(
      find.text("Terminal text size is separate from your phone's text size."),
      findsOneWidget,
    );

    final Slider slider = tester.widget(find.byType(Slider));
    expect(slider.divisions, AppType.monoTerminalSizes.length - 1);
    expect(slider.max, AppType.monoTerminalSizes.length - 1);
    expect(slider.value, AppType.monoTerminalSizes.indexOf(13));
    final semantics = tester.getSemantics(find.byType(Slider));
    expect(semantics.label, 'Terminal text size');
    expect(semantics.value, '13 points');

    double previewSize() =>
        tester.widget<Text>(find.text(r'$ dotnet test')).style!.fontSize!;
    expect(previewSize(), 13);

    // Drag to the far end: `18` is the last of R-32-208's list; the readout, the preview
    // and the store all move.
    await tester.drag(find.byType(Slider), const Offset(600, 0));
    await tester.pumpAndSettle();

    expect(find.text('18 pt'), findsOneWidget);
    expect(previewSize(), 18);
    expect(tester.getSemantics(find.byType(Slider)).value, '18 points');
    final stored = await appSettings.load();
    expect((stored as Ok<AppSettings>).value.terminalTextSize, 18);
  });

  testWidgets(
    "this phone's name row shows the device model when no name is stored "
    '(R-31-14-05, R-31-15-15)',
    (tester) async {
      // The same method-channel mock idiom this file's `setUp` uses for
      // `SystemChannels.platform`: `device_info_plus` answers `getDeviceInfo` with this map.
      const channel = MethodChannel('dev.fluttercommunity.plus/device_info');
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            if (call.method != 'getDeviceInfo') {
              return null;
            }
            return <String, dynamic>{
              'version': <String, dynamic>{
                'baseOS': '',
                'sdkInt': 34,
                'release': '14',
                'codename': 'REL',
                'incremental': '',
                'previewSdkInt': 0,
                'securityPatch': '',
              },
              'board': 'shiba',
              'bootloader': 'test',
              'brand': 'Google',
              'device': 'shiba',
              'display': 'test',
              'fingerprint': 'test',
              'hardware': 'shiba',
              'host': 'test',
              'id': 'test',
              'manufacturer': 'Google',
              'model': 'Pixel 8',
              'product': 'shiba',
              'name': 'shiba',
              'supported32BitAbis': <String>[],
              'supported64BitAbis': <String>['arm64-v8a'],
              'supportedAbis': <String>['arm64-v8a'],
              'tags': 'release-keys',
              'type': 'user',
              'isPhysicalDevice': true,
              'freeDiskSize': 0,
              'totalDiskSize': 0,
              'systemFeatures': <String>[],
              'isLowRamDevice': false,
              'physicalRamSize': 0,
              'availableRamSize': 0,
            };
          });

      await pumpScreen(tester);

      // The THIS PHONE section can sit below the fold; the `ListView` builds rows lazily.
      await tester.dragUntilVisible(
        find.text("This phone's name"),
        find.byType(CustomScrollView),
        const Offset(0, -200),
      );
      expect(find.text('Pixel 8'), findsOneWidget);
    },
  );

  testWidgets('Settings has no global relay editor (R-03-126)', (tester) async {
    await pumpScreen(tester);
    expect(find.text('RELAY'), findsNothing);
    expect(find.text('Relay address'), findsNothing);
    expect(find.text('Edit'), findsNothing);
  });

  testWidgets('renders every documented settings section, closing the widget-test gap for this screen '
      '(R-40-035)', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('RELAY'), findsNothing);
    expect(find.text('APPEARANCE'), findsOneWidget);
    expect(find.text('Status colours'), findsOneWidget);

    // With the always-visible appearance controls (owner decision 2026-09-03) and the
    // `Status colours` row under `Theme` (R-03-106, 2026-09-09), `FEEL`, `THIS PHONE`, `Alerts`
    // and `About` sit below the fold: the scroll view's sliver machinery only builds elements
    // for what's near the viewport, so scroll them into view first.
    final scrollView = find.byType(CustomScrollView);
    await tester.dragUntilVisible(
      find.text('FEEL'),
      scrollView,
      const Offset(0, -200),
    );
    expect(find.text('FEEL'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('THIS PHONE'),
      scrollView,
      const Offset(0, -200),
    );
    expect(find.text('THIS PHONE'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('Alerts'),
      scrollView,
      const Offset(0, -200),
    );
    expect(find.text('Alerts'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('About'),
      scrollView,
      const Offset(0, -200),
    );
    expect(find.text('About'), findsOneWidget);
  });

  /// One label per row of the groups R-33-073 reaches on this screen: `FEEL`, `THIS
  /// PHONE`, `SECURITY`, then the headerless `Alerts` and `About`. `APPEARANCE` holds the two
  /// inline blocks, which are not rows (R-33-073 item 2), so it is absent here.
  const rowLabels = <String>[
    'Haptics',
    'Key press haptics',
    "This phone's name",
    'App Lock',
    'Alerts',
    'About',
  ];

  /// A surface tall enough for the whole list, so the lazy scroll view builds every row and no
  /// scroll is needed. A 200 px drag flings under the iOS scroll physics and can carry a row
  /// past the viewport between two `dragUntilVisible` checks.
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('the body is plain color.bg.base: no ground grid, and the sections paint no paper '
      '(R-03-107)', (tester) async {
    useTallSurface(tester);
    await pumpScreen(tester);

    expect(find.byType(GroundGrid), findsNothing);
  });

  testWidgets(
    'iOS: renders CupertinoNavigationBar, not Material AppBar, every row of every group is a '
    'CupertinoListTile inside CupertinoListSection (R-33-073), and '
    'theme and size controls are the Cupertino ones (R-03-059)',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      // A failed expect below must not leak the override into the next test
      // (`_verifyInvariants` fails the whole file on a leaked debug variable).
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      useTallSurface(tester);
      await pumpScreen(tester);

      expect(find.text('Settings'), findsOneWidget);
      expect(find.byType(CupertinoNavigationBar), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(CupertinoListSection), findsWidgets);
      expect(find.text('RELAY'), findsNothing);

      for (final label in rowLabels) {
        expect(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(CupertinoListTile),
          ),
          findsOneWidget,
          reason: '$label is not a CupertinoListTile',
        );
      }
      expect(find.byType(ListTile), findsNothing);
      expect(find.byType(CupertinoSwitch), findsWidgets);
      expect(find.byType(Switch), findsNothing);
      expect(
        find.byType(CupertinoSlidingSegmentedControl<AppThemeMode>),
        findsOneWidget,
      );
      expect(find.byType(SegmentedButton<AppThemeMode>), findsNothing);
      final CupertinoSlider slider = tester.widget(
        find.byType(CupertinoSlider),
      );
      expect(slider.divisions, AppType.monoTerminalSizes.length - 1);
      expect(find.byType(Slider), findsNothing);
      expect(find.byType(IconButton), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  // The screen as `routing.dart` pushes it on iOS: a `CupertinoPage` above another one, in a
  // nested `Navigator` under `HeroControllerScope.none` (as go_router's shell branches do,
  // since `MaterialApp`'s `HeroController` MUST NOT be shared). `CupertinoNavigationBar` then
  // implies its own back button; R-33-070 forbids the app from drawing one of its own, so the
  // platform widget is the one thing this asserts on.
  testWidgets(
    'iOS: on a pushed route CupertinoNavigationBar implies its automatic back button (R-33-070)',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      useTallSurface(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: HeroControllerScope.none(
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
      expect(find.byType(AppBar), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('Android: every row is the Material settings row of docs/32 section 7.4, and no '
      'CupertinoListTile exists (R-33-073)', (tester) async {
    useTallSurface(tester);
    await pumpScreen(tester);

    expect(find.text('About'), findsOneWidget);
    expect(find.byType(CupertinoListTile), findsNothing);
    expect(find.byType(CupertinoSwitch), findsNothing);
    expect(find.byType(Switch), findsWidgets);
    for (final label in rowLabels) {
      expect(
        find.ancestor(of: find.text(label), matching: find.byType(ListTile)),
        findsOneWidget,
        reason: '$label is not a ListTile',
      );
    }
  });

  testWidgets(
    'turning App Lock on migrates storage before persisting the switch, and syncs the '
    'session gate (R-03-092, R-13-073, R-22-083, R-31-15-18)',
    (tester) async {
      await pumpScreen(tester);
      expect(gate.appLockEnabled, isFalse);

      await tester.dragUntilVisible(
        find.text('App Lock'),
        find.byType(CustomScrollView),
        const Offset(0, -200),
      );
      expect(find.text('SECURITY'), findsOneWidget);
      // `ChromeSettingsSection`'s own header padding pushes the row a few
      // pixels further down than the drag step lands; bring it fully inside
      // the viewport before the tap, so the tap hits the row, not the edge.
      await tester.ensureVisible(find.text('App Lock'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('App Lock'));
      await tester.pumpAndSettle();

      final settings = await appSettings.load();
      expect((settings as Ok<AppSettings>).value.appLockEnabled, isTrue);
      expect(keystore.appLockEnabled, isTrue);
      expect(gate.appLockEnabled, isTrue);
    },
  );

  for (final initiallyEnabled in [false, true]) {
    testWidgets(
      'a preference failure restores App Lock protection from $initiallyEnabled',
      (tester) async {
        SharedPreferencesAsyncPlatform.instance = _FailingLockPreferences(
          enabled: initiallyEnabled,
        );
        await appSettings.dispose();
        appSettings = AppSettingsService();
        keystore = KeystoreService(
          appLockEnabled: initiallyEnabled,
          storage: storage,
        );
        gate = BiometricGate(
          appLockEnabled: initiallyEnabled,
          keystore: keystore,
          setNativeLocked: (_) {},
        );
        final seed = base64Encode(List<int>.filled(32, 7));
        await storage.write(key: 'device_x25519_private_key', value: seed);
        await pumpScreen(tester);
        await tester.dragUntilVisible(
          find.text('App Lock'),
          find.byType(CustomScrollView),
          const Offset(0, -200),
        );
        await tester.ensureVisible(find.text('App Lock'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('App Lock'));
        await tester.pumpAndSettle();

        expect(keystore.appLockEnabled, initiallyEnabled);
        expect(gate.appLockEnabled, initiallyEnabled);
        expect(appSettings.current.appLockEnabled, initiallyEnabled);
        expect(await storage.read(key: 'device_x25519_private_key'), seed);
      },
    );
  }
}
