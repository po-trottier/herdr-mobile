/// Smoke tests for the five shared primitives of
/// `docs/90-implementation-plan.md` Phase 12's shared-primitives
/// checklist item: each renders its tokens and fires its one callback.
/// `AppTextButton` also proves its platform form per
/// `docs/03-product-decisions.md` R-03-059 and R-03-104: a `TextButton` on
/// Android and a `CupertinoButton` on iOS, with `color.accent.text` from the
/// theme `app.dart` builds (R-32-526) and the component's own label type,
/// drawn as written, at the component's own height; the glyph form, the
/// `treat.destructive` form (R-32-527) and the quiet form.
library;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoButton;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart'
    show
        Brightness,
        BuildContext,
        DecoratedBox,
        DefaultTextStyle,
        Icon,
        Opacity,
        Row,
        Text,
        TextStyle,
        WidgetState;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/app.dart' show appThemeFrom;
import 'package:herdr_mobile/widgets/app_filled_button.dart';
import 'package:herdr_mobile/widgets/app_list_row.dart';
import 'package:herdr_mobile/widgets/app_section_header.dart';
import 'package:herdr_mobile/widgets/app_strip.dart';
import 'package:herdr_mobile/widgets/app_text_button.dart';
import 'package:herdr_mobile/widgets/theme/app_color.dart';
import 'package:herdr_mobile/widgets/theme/app_size.dart';
import 'package:herdr_mobile/widgets/theme/app_type.dart';
import 'package:herdr_mobile/widgets/theme/chrome_scheme.dart';
import 'package:herdr_mobile/widgets/treatments.dart';
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart'
    show ButtonStyle, MaterialApp, Scaffold, TextButton, Widget;

Widget _app(Widget child) => MaterialApp(
  theme: appThemeFrom(ChromeScheme.fixed(Brightness.light)),
  home: Scaffold(body: child),
);

const Set<WidgetState> _enabled = <WidgetState>{};
const Set<WidgetState> _pressed = <WidgetState>{WidgetState.pressed};
const Set<WidgetState> _disabled = <WidgetState>{WidgetState.disabled};

void main() {
  group('AppFilledButton', () {
    testWidgets('fires onPressed when enabled', (WidgetTester tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppFilledButton(
              label: 'Reconnect now',
              onPressed: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Reconnect now'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('does not fire onPressed when disabled', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppFilledButton(label: 'Reconnect now', onPressed: null),
          ),
        ),
      );
      await tester.tap(find.text('Reconnect now'));
      await tester.pump();
      // Nothing to assert beyond "no crash": `onPressed` is null, so
      // `GestureDetector.onTap` is also null and the tap is a no-op.
    });
  });

  group('AppTextButton', () {
    testWidgets('fires onPressed', (WidgetTester tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppTextButton(
              label: 'Cancel',
              onPressed: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('Android: a TextButton, accent.text label in the component\'s own type, accent.soft '
        'pressed wash, no style of its own, at the component\'s own height and shape '
        '(R-32-526, R-03-059, R-03-104)', (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(AppTextButton(label: 'Try again', onPressed: () {})),
      );
      final Finder button = find.byType(TextButton);
      expect(button, findsOneWidget);
      expect(find.byType(CupertinoButton), findsNothing);
      expect(tester.widget<TextButton>(button).enabled, isTrue);
      expect(tester.widget<TextButton>(button).style, isNull);
      final BuildContext context = tester.element(button);
      final AppColor color = AppColor.of(context);
      final ButtonStyle style = tester
          .widget<TextButton>(button)
          .themeStyleOf(context)!;
      expect(style.foregroundColor!.resolve(_enabled), color.accentText);
      expect(
        style.foregroundColor!.resolve(_disabled),
        color.accentText.withValues(alpha: 0.38),
      );
      expect(style.overlayColor!.resolve(_pressed), color.accentSoft);
      // R-03-104: no label type in the theme; the component's own.
      expect(style.textStyle, isNull);
      // The R-03-059 addendum: the theme sets no geometry.
      expect(style.shape, isNull);
      expect(style.minimumSize, isNull);
      expect(style.padding, isNull);
      final Text text = tester.widget<Text>(find.text('Try again'));
      expect(text.style, isNull);
      expect(find.text('TRY AGAIN'), findsNothing);
    });

    testWidgets('icon: the glyph at the theme\'s size.icon.md before the label, in the label\'s '
        'ink', (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(
          AppTextButton(
            label: 'Mark all read',
            icon: Symbols.done_all_rounded,
            onPressed: () {},
          ),
        ),
      );
      final Finder glyph = find.byType(Icon);
      expect(glyph, findsOneWidget);
      expect(tester.getSize(glyph).width, AppSize.iconMd);
      expect(
        tester.getRect(glyph).right,
        lessThan(tester.getRect(find.text('Mark all read')).left),
      );
      final AppColor color = AppColor.of(tester.element(glyph));
      final ButtonStyle style = tester
          .widget<TextButton>(find.byType(TextButton))
          .themeStyleOf(tester.element(find.byType(TextButton)))!;
      expect(style.iconSize!.resolve(_enabled), AppSize.iconMd);
      expect(tester.widget<Icon>(glyph).color, isNull);
      expect(style.foregroundColor!.resolve(_enabled), color.accentText);
    });

    testWidgets('destructive: a status.error glyph and the button\'s own label ink; no bar, no red '
        'text (R-32-527, R-03-104)', (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(
          AppTextButton(
            label: 'Remove all',
            icon: Symbols.delete_sweep_rounded,
            destructive: true,
            onPressed: () {},
          ),
        ),
      );
      final AppColor color = AppColor.of(tester.element(find.byType(Icon)));
      expect(tester.widget<Icon>(find.byType(Icon)).color, color.statusError);
      final Finder label = find.text('Remove all');
      expect(
        tester.widget<Text>(label).style,
        isNull,
        reason: 'the label is the theme\'s; only the glyph is the treatment\'s',
      );
      expect(
        DefaultTextStyle.of(tester.element(label)).style.color,
        color.accentText,
      );
      expect(
        find.descendant(
          of: find.byType(TextButton),
          matching: find.byType(DecoratedBox),
        ),
        findsNothing,
        reason:
            'the glyph is the one destructive mark; no border.attention bar',
      );
    });

    testWidgets(
      'two text buttons side by side share one label ink and type, as written, and '
      'only the destructive glyph differs (R-03-104)',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          _app(
            Row(
              children: <Widget>[
                AppTextButton(
                  label: 'Mark all read',
                  icon: Symbols.done_all_rounded,
                  onPressed: () {},
                ),
                AppTextButton(
                  label: 'Remove all',
                  icon: Symbols.delete_sweep_rounded,
                  destructive: true,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        );
        final Finder markAllRead = find.text('Mark all read');
        final Finder removeAll = find.text('Remove all');
        expect(markAllRead, findsOneWidget);
        expect(removeAll, findsOneWidget);
        expect(find.text('MARK ALL READ'), findsNothing);
        expect(find.text('REMOVE ALL'), findsNothing);
        final TextStyle first = DefaultTextStyle.of(tester.element(markAllRead))
            .style;
        final TextStyle second = DefaultTextStyle.of(tester.element(removeAll))
            .style;
        expect(second, first);
        expect(first.fontFamily, AppType.interfaceFontFamily);
        expect(first.fontFamily, isNot(AppType.monoFontFamily));
        final AppColor color = AppColor.of(tester.element(markAllRead));
        expect(first.color, color.accentText);
        final List<Icon> glyphs = tester
            .widgetList<Icon>(find.byType(Icon))
            .toList();
        expect(glyphs.first.color, isNull);
        expect(glyphs.last.color, color.statusError);
      },
    );

    testWidgets('destructive and subdued content dims with the disabled button, so the whole '
        'control dims as one (R-32-502)', (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(
          const AppTextButton(
            label: 'Remove all',
            icon: Symbols.delete_sweep_rounded,
            destructive: true,
            onPressed: null,
          ),
        ),
      );
      final AppColor color = AppColor.of(tester.element(find.byType(Icon)));
      expect(
        tester.widget<Icon>(find.byType(Icon)).color,
        color.statusError.withValues(alpha: 0.38),
      );
      // The label dims through the theme's disabled ink, per R-32-502.
      expect(
        DefaultTextStyle.of(tester.element(find.text('Remove all')))
            .style
            .color,
        color.accentText.withValues(alpha: 0.38),
      );

      await tester.pumpWidget(
        _app(
          const AppTextButton(label: 'Cancel', subdued: true, onPressed: null),
        ),
      );
      expect(
        tester.widget<Text>(find.text('Cancel')).style!.color,
        color.fgSecondary.withValues(alpha: 0.38),
      );
    });

    testWidgets(
      'subdued: type.body.strong in fg.secondary, the label\'s own case, with no '
      'tracking inherited from the button (R-32-526)',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          _app(AppTextButton(label: 'Cancel', subdued: true, onPressed: () {})),
        );
        final Finder label = find.text('Cancel');
        expect(label, findsOneWidget);
        final TextStyle style = tester.widget<Text>(label).style!;
        final AppColor color = AppColor.of(tester.element(label));
        expect(style.color, color.fgSecondary);
        expect(style.fontFamily, AppType.bodyStrong.fontFamily);
        expect(style.fontWeight, AppType.bodyStrong.fontWeight);
        expect(style.inherit, isFalse);
        expect(style.letterSpacing, isNull);
      },
    );

    testWidgets(
      'iOS: a plain CupertinoButton inked in accent.text, dimmed whole when disabled',
      (WidgetTester tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          int taps = 0;
          await tester.pumpWidget(
            _app(
              AppTextButton(
                label: 'Mark all read',
                icon: Symbols.done_all_rounded,
                onPressed: () => taps++,
              ),
            ),
          );
          expect(find.byType(TextButton), findsNothing);
          final Finder button = find.byType(CupertinoButton);
          expect(button, findsOneWidget);
          final AppColor color = AppColor.of(tester.element(button));
          final TextStyle labelStyle = DefaultTextStyle.of(
            tester.element(find.text('Mark all read')),
          ).style;
          expect(labelStyle.color, color.accentText);
          expect(labelStyle.fontFamily, AppType.interfaceFontFamily);
          expect(
            tester.getRect(find.byType(Icon)).right,
            lessThan(tester.getRect(find.text('Mark all read')).left),
          );
          final Finder dim = find.descendant(
            of: find.byType(AppTextButton),
            matching: find.byType(Opacity),
          );
          expect(tester.widget<Opacity>(dim).opacity, 1);
          await tester.tap(button);
          await tester.pump();
          expect(taps, 1);

          await tester.pumpWidget(
            _app(const AppTextButton(label: 'Mark all read', onPressed: null)),
          );
          expect(tester.widget<CupertinoButton>(button).enabled, isFalse);
          expect(tester.widget<Opacity>(dim).opacity, 0.38);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  });

  testWidgets('AppListRow renders both lines and fires onTap', (
    WidgetTester tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppListRow(
            primary: 'herdr-relay',
            secondary: 'Last seen 3 minutes ago',
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('herdr-relay'), findsOneWidget);
    expect(find.text('Last seen 3 minutes ago'), findsOneWidget);
    await tester.tap(find.text('herdr-relay'));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('AppSectionHeader.tier1 toggles and shows its count', (
    WidgetTester tester,
  ) async {
    var toggled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppSectionHeader.tier1(
            label: 'my-workspace',
            expanded: true,
            count: '3',
            onToggle: () => toggled = true,
          ),
        ),
      ),
    );

    expect(find.text('my-workspace'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.text('my-workspace'));
    await tester.pump();
    expect(toggled, isTrue);
  });

  testWidgets(
    'AppStrip taps its destination area but not its trailing control',
    (WidgetTester tester) async {
      var destinationTapped = false;
      var trailingTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppStrip(
              onTapDestination: () => destinationTapped = true,
              trailing: AppTextButton(
                label: 'Try again',
                onPressed: () => trailingTapped = true,
              ),
              child: const Treatment.warning(label: 'Relay unreachable'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(trailingTapped, isTrue);
      expect(destinationTapped, isFalse);

      await tester.tap(find.text('Relay unreachable'));
      await tester.pump();
      expect(destinationTapped, isTrue);
    },
  );
}
