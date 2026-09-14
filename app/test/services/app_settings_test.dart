/// Tests `app_settings.dart`: the `AppThemeMode` enum is exactly the three modes
/// `docs/32-design-language.md`:48-49 permits, in that fixed order, and `AppSettings`
/// defaults to `system` (R-30-112, R-32-010).
///
/// Also proves R-32-013 (`docs/32-design-language.md`:57-59): `AppColor.of(context)`
/// (`app/lib/widgets/theme/app_color.dart`) resolves from the ambient platform brightness
/// and switches when that brightness changes, with no widget rebuild/restart.
library;

import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter/widgets.dart'
    show AnnotatedRegion, Builder, BuildContext, SizedBox, Widget;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/app.dart' show ResolvedChrome, themeModeOf;
import 'package:herdr_mobile/core/result/result.dart' show Ok;
import 'package:herdr_mobile/services/app_settings.dart';
import 'package:herdr_mobile/widgets/theme/app_color.dart';
import 'package:material_ui/material_ui.dart'
    show Brightness, MaterialApp, ThemeData, ThemeMode;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  group('AppThemeMode (R-30-112, R-32-010)', () {
    test(
      'has exactly the three modes docs/32-design-language.md fixes, in order',
      () {
        expect(AppThemeMode.values, [
          AppThemeMode.system,
          AppThemeMode.light,
          AppThemeMode.dark,
        ]);
      },
    );

    test('AppSettings defaults themeMode to system', () {
      expect(const AppSettings().themeMode, AppThemeMode.system);
    });

    test('AppSettings defaults App Lock off and its offer unshown (R-03-090, R-03-091)', () {
      const settings = AppSettings();
      expect(settings.appLockEnabled, isFalse);
      expect(settings.appLockOfferShown, isFalse);
    });
  });

  group('AppSettingsService App Lock persistence (R-03-090, R-03-091)', () {
    late AppSettingsService service;

    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      service = AppSettingsService();
    });

    tearDown(() => service.dispose());

    test('current starts at the documented defaults before any load()', () {
      expect(service.current.appLockEnabled, isFalse);
      expect(service.current.appLockOfferShown, isFalse);
    });

    test('setAppLockEnabled persists and updates current', () async {
      final result = await service.setAppLockEnabled(value: true);

      expect(result, isA<Ok<void>>());
      expect(service.current.appLockEnabled, isTrue);
      final reloaded = await service.load();
      expect((reloaded as Ok<AppSettings>).value.appLockEnabled, isTrue);
    });

    test(
      'setAppLockOfferShown persists independently of appLockEnabled',
      () async {
        await service.setAppLockOfferShown(value: true);

        expect(service.current.appLockOfferShown, isTrue);
        expect(service.current.appLockEnabled, isFalse);
      },
    );

    test(
      'load publishes on changes, so the root sees the persisted mode',
      () async {
        final Future<AppSettings> first = service.changes.first;
        await service.setThemeMode(AppThemeMode.dark);
        expect((await first).themeMode, AppThemeMode.dark);
        final Future<AppSettings> reloaded = service.changes.first;
        expect(await service.load(), isA<Ok<AppSettings>>());
        expect((await reloaded).themeMode, AppThemeMode.dark);
      },
    );
  });

  group('AppColor.of (R-32-013)', () {
    testWidgets('resolves the ambient platform brightness with no restart', (
      WidgetTester tester,
    ) async {
      AppColor? resolved;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              resolved = AppColor.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pump();
      expect(resolved, AppColor.light);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pump();
      expect(resolved, AppColor.dark);
    });
  });

  group('ResolvedChrome (R-22-051, R-22-054)', () {
    test('themeModeOf maps the three modes one to one', () {
      expect(themeModeOf(AppThemeMode.system), ThemeMode.system);
      expect(themeModeOf(AppThemeMode.light), ThemeMode.light);
      expect(themeModeOf(AppThemeMode.dark), ThemeMode.dark);
    });

    Future<AppColor?> pumpForced(
      WidgetTester tester, {
      required ThemeMode mode,
      required Brightness platform,
    }) async {
      AppColor? resolved;
      tester.platformDispatcher.platformBrightnessTestValue = platform;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(
        MaterialApp(
          themeMode: mode,
          theme: ThemeData(brightness: Brightness.light),
          darkTheme: ThemeData(brightness: Brightness.dark),
          builder: (BuildContext context, Widget? child) =>
              ResolvedChrome(child: child!),
          home: Builder(
            builder: (BuildContext context) {
              resolved = AppColor.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return resolved;
    }

    SystemUiOverlayStyle barsOf(WidgetTester tester) => tester
        .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
          find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
        )
        .value;

    testWidgets('forced Light on a dark OS resolves light tokens and bars', (
      WidgetTester tester,
    ) async {
      final AppColor? resolved = await pumpForced(
        tester,
        mode: ThemeMode.light,
        platform: Brightness.dark,
      );
      expect(resolved, AppColor.light);
      final SystemUiOverlayStyle bars = barsOf(tester);
      expect(bars.statusBarIconBrightness, Brightness.dark);
      expect(bars.systemNavigationBarColor, AppColor.light.bgBase);
    });

    testWidgets('forced Dark on a light OS resolves dark tokens and bars', (
      WidgetTester tester,
    ) async {
      final AppColor? resolved = await pumpForced(
        tester,
        mode: ThemeMode.dark,
        platform: Brightness.light,
      );
      expect(resolved, AppColor.dark);
      final SystemUiOverlayStyle bars = barsOf(tester);
      expect(bars.statusBarIconBrightness, Brightness.light);
      expect(bars.systemNavigationBarColor, AppColor.dark.bgBase);
    });

    testWidgets('System mode follows a live OS change through the wrapper', (
      WidgetTester tester,
    ) async {
      final AppColor? resolved = await pumpForced(
        tester,
        mode: ThemeMode.system,
        platform: Brightness.dark,
      );
      expect(resolved, AppColor.dark);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
              find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
            )
            .value
            .systemNavigationBarColor,
        AppColor.light.bgBase,
      );
    });
  });
}
