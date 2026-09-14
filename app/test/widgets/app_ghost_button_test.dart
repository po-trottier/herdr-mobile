/// `AppGhostButton` (`app/lib/widgets/app_ghost_button.dart`), the ghost
/// button of `docs/32-design-language.md` section 7.28 (R-32-591) as the
/// platform's own secondary button per `docs/03-product-decisions.md`
/// R-03-059: an `OutlinedButton` on Android, a `CupertinoButton` on iOS,
/// with every value from the theme `app.dart` builds and none in the widget.
library;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoButton;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart'
    show
        BorderSide,
        Brightness,
        BuildContext,
        Center,
        DefaultTextStyle,
        Opacity,
        Text,
        TextStyle,
        WidgetState;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/app.dart' show appThemeFrom;
import 'package:herdr_mobile/widgets/app_ghost_button.dart';
import 'package:herdr_mobile/widgets/theme/app_color.dart';
import 'package:herdr_mobile/widgets/theme/app_size.dart';
import 'package:herdr_mobile/widgets/theme/app_type.dart';
import 'package:herdr_mobile/widgets/theme/chrome_scheme.dart';
import 'package:material_ui/material_ui.dart'
    show
        ButtonStyle,
        CircularProgressIndicator,
        MaterialApp,
        OutlinedButton,
        Scaffold,
        Widget;

Widget _app(Widget child) => MaterialApp(
  theme: appThemeFrom(ChromeScheme.fixed(Brightness.light)),
  home: Scaffold(body: child),
);

const Set<WidgetState> _enabled = <WidgetState>{};
const Set<WidgetState> _pressed = <WidgetState>{WidgetState.pressed};
const Set<WidgetState> _disabled = <WidgetState>{WidgetState.disabled};

void main() {
  testWidgets('Android: an OutlinedButton, no fill, border.strong hairline, fg.primary label in the '
      'component\'s own type, no style of its own, at the component\'s own height and shape '
      '(section 7.28, R-03-104)', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(AppGhostButton(label: 'Cancel', onPressed: () {})),
    );

    final Finder button = find.byType(OutlinedButton);
    expect(button, findsOneWidget);
    expect(find.byType(CupertinoButton), findsNothing);
    // The R-03-059 addendum: the theme sets no geometry.
    final ButtonStyle themeStyle = tester
        .widget<OutlinedButton>(button)
        .themeStyleOf(tester.element(button))!;
    expect(themeStyle.shape, isNull);
    expect(themeStyle.minimumSize, isNull);
    expect(themeStyle.padding, isNull);
    expect(
      tester.getSize(button).width,
      tester.getSize(find.byType(Scaffold)).width,
      reason: 'fullWidth is the default',
    );
    expect(tester.widget<OutlinedButton>(button).style, isNull);

    final BuildContext context = tester.element(button);
    final AppColor color = AppColor.of(context);
    final ButtonStyle style = tester
        .widget<OutlinedButton>(button)
        .themeStyleOf(context)!;
    expect(style.backgroundColor, isNull, reason: 'no fill');
    final BorderSide side = style.side!.resolve(_enabled)!;
    expect(side.color, color.borderStrong);
    expect(side.width, 1);
    expect(style.foregroundColor!.resolve(_enabled), color.fgPrimary);
    // R-03-104: no label type in the theme; the component's own, as written.
    expect(style.textStyle, isNull);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('CANCEL'), findsNothing);
    expect(tester.widget<Text>(find.text('Cancel')).style, isNull);
  });

  testWidgets('Android: pressed is the accent.soft wash under an accent.primary side, the '
      'platform\'s own overlay (R-32-591)', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(AppGhostButton(label: 'Cancel', onPressed: () {})),
    );
    final Finder button = find.byType(OutlinedButton);
    final BuildContext context = tester.element(button);
    final AppColor color = AppColor.of(context);
    final ButtonStyle style = tester
        .widget<OutlinedButton>(button)
        .themeStyleOf(context)!;
    expect(style.overlayColor!.resolve(_pressed), color.accentSoft);
    expect(style.side!.resolve(_pressed)!.color, color.accentPrimary);
  });

  testWidgets('Android: disabled dims the side and the label to opacity.disabled with no second '
      'colour (R-32-502)', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(const AppGhostButton(label: 'Cancel', onPressed: null)),
    );
    final Finder button = find.byType(OutlinedButton);
    final BuildContext context = tester.element(button);
    final AppColor color = AppColor.of(context);
    final ButtonStyle style = tester
        .widget<OutlinedButton>(button)
        .themeStyleOf(context)!;
    expect(
      style.side!.resolve(_disabled)!.color,
      color.borderStrong.withValues(alpha: 0.38),
    );
    expect(
      style.foregroundColor!.resolve(_disabled),
      color.fgPrimary.withValues(alpha: 0.38),
    );
    expect(tester.widget<OutlinedButton>(button).enabled, isFalse);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets(
    'fullWidth false hugs the label so the button sits beside another control',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(
          Center(
            child: AppGhostButton(
              label: 'Pair a computer',
              onPressed: () {},
              fullWidth: false,
            ),
          ),
        ),
      );
      final Finder button = find.byType(OutlinedButton);
      expect(
        tester.getSize(button).width,
        lessThan(tester.getSize(find.byType(Scaffold)).width),
      );
    },
  );

  testWidgets(
    'loading swaps the label for a size.spinner spinner and takes the tap off',
    (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(
        _app(
          AppGhostButton(
            label: 'Cancel',
            onPressed: () => taps++,
            isLoading: true,
          ),
        ),
      );
      expect(find.text('Cancel'), findsNothing);
      final Finder spinner = find.byType(CircularProgressIndicator);
      expect(tester.getSize(spinner).height, AppSize.spinner);
      await tester.tap(find.byType(OutlinedButton));
      await tester.pump();
      expect(taps, 0);
    },
  );

  testWidgets(
    'iOS: a tinted CupertinoButton inked in color.accent.text, not the 3.6 primary '
    'tint (R-32-124), dimmed whole when disabled',
    (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        int taps = 0;
        await tester.pumpWidget(
          _app(AppGhostButton(label: 'Cancel', onPressed: () => taps++)),
        );
        expect(find.byType(OutlinedButton), findsNothing);
        final Finder button = find.byType(CupertinoButton);
        expect(button, findsOneWidget);
        final AppColor color = AppColor.of(tester.element(button));
        final TextStyle labelStyle = DefaultTextStyle.of(
          tester.element(find.text('Cancel')),
        ).style;
        expect(labelStyle.color, color.accentText);
        expect(labelStyle.color, isNot(color.accentPrimary));
        expect(labelStyle.fontFamily, AppType.interfaceFontFamily);
        final Finder dim = find.descendant(
          of: find.byType(AppGhostButton),
          matching: find.byType(Opacity),
        );
        expect(tester.widget<Opacity>(dim).opacity, 1);
        await tester.tap(button);
        await tester.pump();
        expect(taps, 1);

        await tester.pumpWidget(
          _app(const AppGhostButton(label: 'Cancel', onPressed: null)),
        );
        expect(tester.widget<CupertinoButton>(button).enabled, isFalse);
        expect(tester.widget<Opacity>(dim).opacity, 0.38);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
