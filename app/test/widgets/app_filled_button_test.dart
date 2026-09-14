/// `AppFilledButton` (`app/lib/widgets/app_filled_button.dart`), the one
/// filled control of R-30-121 and `docs/32-design-language.md` section 7.8,
/// as the platform's own button per `docs/03-product-decisions.md` R-03-059:
///
/// - a source scan keeps `FilledButton(`/`ElevatedButton(` out of every other
///   widget under `lib/screens` and `lib/widgets`, the same idiom
///   `test/a11y/reduce_motion_test.dart` uses for a per-widget policy;
/// - on Android the widget is a `FilledButton`, on iOS a `CupertinoButton`,
///   and nothing of its own draws a fill or a border;
/// - the theme `app.dart` builds gives it the `color.accent.primary` fill
///   and the `color.fg.on_accent` label (R-32-525) with no style in the
///   widget, and leaves the component's own height, radius, inset and label
///   type alone (the R-03-059 addendum and R-03-104, 2026-09-09);
/// - disabled is the same colours at `opacity.disabled` (R-32-502), and
///   loading swaps the label for a spinner in place (R-32-331).
library;

import 'dart:io';

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoButton, CupertinoTextThemeData;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart'
    show
        Brightness,
        BuildContext,
        DefaultTextStyle,
        Opacity,
        Text,
        TextStyle,
        WidgetState;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/app.dart' show appThemeFrom;
import 'package:herdr_mobile/widgets/app_filled_button.dart';
import 'package:herdr_mobile/widgets/theme/app_color.dart';
import 'package:herdr_mobile/widgets/theme/app_size.dart';
import 'package:herdr_mobile/widgets/theme/app_type.dart';
import 'package:herdr_mobile/widgets/theme/chrome_scheme.dart';
import 'package:material_ui/material_ui.dart'
    show
        ButtonStyle,
        CircularProgressIndicator,
        FilledButton,
        Material,
        MaterialApp,
        Scaffold,
        Theme,
        Widget;

Widget _app(Widget child) => MaterialApp(
  theme: appThemeFrom(ChromeScheme.fixed(Brightness.light)),
  home: Scaffold(body: child),
);

const Set<WidgetState> _enabled = <WidgetState>{};
const Set<WidgetState> _disabled = <WidgetState>{WidgetState.disabled};

void main() {
  test('no other widget under lib/screens or lib/widgets builds a raw FilledButton( or '
      'ElevatedButton(: AppFilledButton is the one filled control type (R-30-121), and '
      'the latched key cap of R-03-118 is the one other builder (R-32-525)', () {
    final RegExp rawFilledOrElevatedButton = RegExp(
      r'\bFilledButton\(|\bElevatedButton\(',
    );
    final violations = <String>[];
    for (final rootPath in <String>['lib/screens', 'lib/widgets']) {
      final root = Directory(rootPath);
      if (!root.existsSync()) continue;
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll(r'\', '/');
        // The two files R-32-525 lets build the platform's filled button: the
        // app's filled control, and the latched modifier cap of R-03-118.
        if (path.endsWith('lib/widgets/app_filled_button.dart') ||
            path.endsWith('lib/widgets/key_row.dart')) {
          continue;
        }
        if (rawFilledOrElevatedButton.hasMatch(entity.readAsStringSync())) {
          violations.add(path);
        }
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          'these files build a raw filled control instead of AppFilledButton: '
          '$violations',
    );
  });

  testWidgets(
    'Android: a FilledButton, full width, with the theme\'s accent fill and on_accent label, '
    'in the component\'s own type, height and shape (R-32-525, R-03-059, R-03-104)',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(AppFilledButton(label: 'Save', onPressed: () {})),
      );

      final Finder button = find.byType(FilledButton);
      expect(button, findsOneWidget);
      expect(find.byType(CupertinoButton), findsNothing);
      expect(
        tester.getSize(button).width,
        tester.getSize(find.byType(Scaffold)).width,
      );

      // No style on the widget: every value is the theme's.
      expect(tester.widget<FilledButton>(button).style, isNull);
      final BuildContext context = tester.element(button);
      final AppColor color = AppColor.of(context);
      final ButtonStyle style = tester
          .widget<FilledButton>(button)
          .themeStyleOf(context)!;
      expect(style.backgroundColor!.resolve(_enabled), color.accentPrimary);
      expect(style.foregroundColor!.resolve(_enabled), color.fgOnAccent);
      // R-03-104: the theme sets no label type, so the label is the
      // component's own `labelLarge` in the interface family.
      expect(style.textStyle, isNull);
      // The R-03-059 addendum: the theme sets no geometry, so the pill is
      // the platform's own.
      expect(style.shape, isNull);
      expect(style.minimumSize, isNull);
      expect(style.padding, isNull);

      // The painted surface is the resolved fill; the label is the theme's
      // ink in `labelLarge`, drawn as written.
      final Material material = tester.widget<Material>(
        find.descendant(of: button, matching: find.byType(Material)),
      );
      expect(material.color, color.accentPrimary);
      expect(material.textStyle!.color, color.fgOnAccent);
      expect(material.textStyle!.fontFamily, AppType.interfaceFontFamily);
      expect(
        material.textStyle!.fontSize,
        Theme.of(context).textTheme.labelLarge!.fontSize,
      );
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('SAVE'), findsNothing);
    },
  );

  testWidgets('Android: disabled is the same colours at opacity.disabled, no second colour '
      '(R-32-502, R-32-331)', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(const AppFilledButton(label: 'Save', onPressed: null)),
    );
    final Finder button = find.byType(FilledButton);
    final BuildContext context = tester.element(button);
    final AppColor color = AppColor.of(context);
    final ButtonStyle style = tester
        .widget<FilledButton>(button)
        .themeStyleOf(context)!;
    expect(
      style.backgroundColor!.resolve(_disabled),
      color.accentPrimary.withValues(alpha: 0.38),
    );
    expect(
      style.foregroundColor!.resolve(_disabled),
      color.fgOnAccent.withValues(alpha: 0.38),
    );
    expect(tester.widget<FilledButton>(button).enabled, isFalse);
  });

  testWidgets('loading swaps the label for a size.spinner spinner in place and takes the tap off '
      '(R-32-331)', (WidgetTester tester) async {
    int taps = 0;
    await tester.pumpWidget(
      _app(
        AppFilledButton(
          label: 'Save',
          onPressed: () => taps++,
          isLoading: true,
        ),
      ),
    );
    expect(find.text('SAVE'), findsNothing);
    final Finder spinner = find.byType(CircularProgressIndicator);
    expect(spinner, findsOneWidget);
    expect(tester.getSize(spinner).height, AppSize.spinner);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isFalse,
    );
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(taps, 0);
  });

  testWidgets(
    'the label is drawn and spoken as written, with no style of the widget\'s own (R-03-104)',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(AppFilledButton(label: 'Reconnect now', onPressed: () {})),
      );
      final Text text = tester.widget<Text>(find.text('Reconnect now'));
      expect(
        text.style,
        isNull,
        reason: 'the type is the theme\'s, not the widget\'s',
      );
      expect(find.bySemanticsLabel('Reconnect now'), findsOneWidget);
    },
  );

  testWidgets('iOS: a filled CupertinoButton with the theme\'s primary fill and contrasting '
      'label, dimmed whole when disabled', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      int taps = 0;
      await tester.pumpWidget(
        _app(AppFilledButton(label: 'Save', onPressed: () => taps++)),
      );
      expect(find.byType(FilledButton), findsNothing);
      final Finder button = find.byType(CupertinoButton);
      expect(button, findsOneWidget);
      expect(
        tester.getRect(button).width,
        tester.getSize(find.byType(Scaffold)).width,
      );
      final AppColor color = AppColor.of(tester.element(button));
      // The button paints the theme's `primaryContrastingColor` on its label
      // through the `DefaultTextStyle` it sets, in the component's own
      // action style in the interface family (R-03-104).
      final TextStyle labelStyle = DefaultTextStyle.of(
        tester.element(find.text('Save')),
      ).style;
      expect(labelStyle.color, color.fgOnAccent);
      expect(labelStyle.fontFamily, AppType.interfaceFontFamily);
      expect(
        labelStyle.fontSize,
        const CupertinoTextThemeData().actionTextStyle.fontSize,
      );
      final Finder dim = find.descendant(
        of: find.byType(AppFilledButton),
        matching: find.byType(Opacity),
      );
      expect(tester.widget<Opacity>(dim).opacity, 1);
      await tester.tap(button);
      await tester.pump();
      expect(taps, 1);

      await tester.pumpWidget(
        _app(const AppFilledButton(label: 'Save', onPressed: null)),
      );
      final CupertinoButton disabled = tester.widget<CupertinoButton>(button);
      expect(disabled.enabled, isFalse);
      expect(disabled.disabledColor, color.accentPrimary);
      expect(tester.widget<Opacity>(dim).opacity, 0.38);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
