/// `AppListRow` (`app/lib/widgets/app_list_row.dart`) against the section 7.4
/// table of `docs/32-design-language.md`: `size.row.one_line` with one line
/// and `size.row.two_line` with two, the divider inset `space.4` from the
/// leading edge and absent when `showDivider` is false, the content inset
/// that never moves when a row is selected or carries a state bar, the
/// selected wash with no second bar (R-03-100), the pressed `color.bg.high`
/// fill of R-32-501 and R-32-609, and one semantics node (R-32-515).
library;

import 'package:flutter/widgets.dart'
    show AnimatedContainer, BoxDecoration, DecoratedBox, Rect, Widget;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/widgets/app_list_row.dart';
import 'package:herdr_mobile/widgets/status_bar.dart';
import 'package:herdr_mobile/widgets/theme/app_color.dart';
import 'package:herdr_mobile/widgets/theme/app_radius.dart';
import 'package:herdr_mobile/widgets/theme/app_size.dart';
import 'package:herdr_mobile/widgets/theme/app_space.dart';
import 'package:material_ui/material_ui.dart' show MaterialApp, Scaffold;

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

bool _isDivider(Widget w) =>
    w is DecoratedBox &&
    w.decoration is BoxDecoration &&
    (w.decoration as BoxDecoration).border?.bottom.width == AppBorder.hairline;

void main() {
  testWidgets('one line is size.row.one_line, two lines size.row.two_line', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(AppListRow(primary: 'Theme', onTap: () {})));
    expect(tester.getSize(find.byType(AppListRow)).height, AppSize.rowOneLine);

    await tester.pumpWidget(
      _app(
        AppListRow(
          primary: 'Relay address',
          secondary: 'Not set',
          onTap: () {},
        ),
      ),
    );
    expect(tester.getSize(find.byType(AppListRow)).height, AppSize.rowTwoLine);
  });

  testWidgets(
    'the divider starts space.4 from the leading edge, and showDivider false '
    'removes it',
    (WidgetTester tester) async {
      await tester.pumpWidget(_app(AppListRow(primary: 'Theme', onTap: () {})));
      final Finder divider = find.byWidgetPredicate(_isDivider);
      expect(divider, findsOneWidget);
      final Rect row = tester.getRect(find.byType(AppListRow));
      final Rect line = tester.getRect(divider);
      expect(line.left, row.left + AppSpace.space4);
      expect(line.right, row.right);
      expect(line.bottom, row.bottom);

      await tester.pumpWidget(
        _app(AppListRow(primary: 'Theme', onTap: () {}, showDivider: false)),
      );
      expect(find.byWidgetPredicate(_isDivider), findsNothing);
    },
  );

  testWidgets(
    'the text keeps its space.4 inset when the row is selected or carries a '
    'state, the selection is a wash alone, and the state bar sits flush to '
    'the edge at full row height (R-03-100)',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(AppListRow(primary: 'build-box', onTap: () {})),
      );
      final double plain = tester.getRect(find.text('build-box')).left;
      expect(plain, AppSpace.space4);
      expect(find.byType(StatusBar), findsNothing);

      await tester.pumpWidget(
        _app(AppListRow(primary: 'build-box', onTap: () {}, selected: true)),
      );
      expect(tester.getRect(find.text('build-box')).left, plain);
      final AnimatedContainer selected = tester.widget(
        find.byType(AnimatedContainer),
      );
      final AppColor color = AppColor.of(
        tester.element(find.text('build-box')),
      );
      expect((selected.decoration as BoxDecoration).color, color.accentSoft);
      expect(selected.foregroundDecoration, isNull);
      expect(find.byType(StatusBar), findsNothing);

      await tester.pumpWidget(
        _app(
          AppListRow(
            primary: 'build-box',
            secondary: 'Connected',
            onTap: () {},
            selected: true,
            state: BarState.working,
          ),
        ),
      );
      expect(tester.getRect(find.text('build-box')).left, plain);
      final Rect row = tester.getRect(find.byType(AppListRow));
      final Rect bar = tester.getRect(find.byType(StatusBar));
      expect(bar.left, row.left);
      expect(bar.width, AppBorder.attention);
      expect(bar.top, row.top);
      expect(bar.bottom, row.bottom);
      expect(
        tester.widget<StatusBar>(find.byType(StatusBar)).state,
        BarState.working,
      );
    },
  );

  testWidgets('pressed fills with color.bg.high and releases to none', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(AppListRow(primary: 'Theme', onTap: () {})));
    final AppColor color = AppColor.of(tester.element(find.text('Theme')));
    BoxDecoration fill() =>
        tester
                .widget<AnimatedContainer>(find.byType(AnimatedContainer))
                .decoration
            as BoxDecoration;
    expect(fill().color, isNull);

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.text('Theme')),
    );
    await tester.pump();
    expect(fill().color, color.bgHigh);

    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pump();
    expect(fill().color, isNull);
  });

  testWidgets('a static row keeps full ink and one semantics node', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        const AppListRow(
          primary: 'Herdr protocol targeted',
          secondary: '22',
          semanticsValue: '22',
          isStatic: true,
        ),
      ),
    );
    expect(
      find.bySemanticsLabel('Herdr protocol targeted, 22'),
      findsOneWidget,
    );
    handle.dispose();
  });
}
