/// Widget tests for `AppSectionHeader`, per `docs/32-design-language.md`
/// section 7.23 (R-32-563 to R-32-570).
library;

import 'package:flutter/widgets.dart'
    show
        BoxConstraints,
        ColoredBox,
        DecoratedBox,
        Icon,
        MainAxisSize,
        RenderBox,
        Row,
        SizedBox,
        Text,
        TextBaseline,
        Widget;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/widgets/app_section_header.dart';
import 'package:herdr_mobile/widgets/theme/app_color.dart';
import 'package:herdr_mobile/widgets/theme/app_size.dart';
import 'package:herdr_mobile/widgets/theme/app_space.dart';
import 'package:herdr_mobile/widgets/theme/app_type.dart';
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart' show MaterialApp, Scaffold;

import '../screens/golden_support.dart';

/// The alphabetic baseline of the text [finder] finds, in the global frame.
double _baselineOf(WidgetTester tester, Finder finder) {
  final RenderBox box = tester.renderObject(finder);
  final double? distance = box.getDryBaseline(
    BoxConstraints.tight(box.size),
    TextBaseline.alphabetic,
  );
  expect(
    distance,
    isNotNull,
    reason: '${finder.describeMatch(Plurality.one)} has a baseline',
  );
  return tester.getTopLeft(finder).dy + distance!;
}

/// The badge of R-32-518 as `agent_list_screen.dart` composes it: the
/// attention glyph at `size.icon.sm`, a `space.1` gap, the count in
/// `type.micro.strong`.
Widget _badge(String count) => Row(
  mainAxisSize: MainAxisSize.min,
  children: <Widget>[
    Icon(
      Symbols.notifications_active_rounded,
      size: AppSize.iconSm,
      color: AppColor.light.statusBlocked,
    ),
    const SizedBox(width: AppSpace.space1),
    Text(
      count,
      style: AppType.microStrong.copyWith(color: AppColor.light.fgPrimary),
    ),
  ],
);

void main() {
  setUpAll(loadAppFonts);

  testWidgets(
    'the upper-case tier is the label alone: no tape rule, no border, height 32',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AppSectionHeader.upperCase(label: 'NEEDS YOU')),
        ),
      );

      final Finder header = find.byType(AppSectionHeader);
      expect(find.text('NEEDS YOU'), findsOneWidget);
      // R-32-563's table: `Divider | none`. The header draws no trailing tape
      // rule (decided 2026-09-03 by the product owner).
      expect(
        find.descendant(of: header, matching: find.byType(ColoredBox)),
        findsNothing,
      );
      expect(
        find.descendant(of: header, matching: find.byType(DecoratedBox)),
        findsNothing,
      );
      expect(tester.getSize(header).height, AppSize.header);
    },
  );

  testWidgets(
    'tier 1 puts the label, the count and the badge count on one alphabetic baseline, '
    'and keeps the label centred in the 52 row (R-32-563, amended 2026-09-08)',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppSectionHeader.tier1(
              label: 'herdr-mobile',
              expanded: true,
              count: '3 panes',
              trailingBadge: _badge('1'),
            ),
          ),
        ),
      );

      final double label = _baselineOf(tester, find.text('herdr-mobile'));
      final double count = _baselineOf(tester, find.text('3 panes'));
      final double badge = _baselineOf(tester, find.text('1'));
      expect(count, closeTo(label, 0.5), reason: 'count on the label baseline');
      expect(
        badge,
        closeTo(label, 0.5),
        reason: 'badge count on the label baseline',
      );

      // The baseline row is the label's own 24 line, so the label sits where
      // it sits without a count or a badge: centred in `size.row.one_line`.
      final Finder header = find.byType(AppSectionHeader);
      final double rowCentre = tester.getCenter(header).dy;
      expect(
        tester.getCenter(find.text('herdr-mobile')).dy,
        closeTo(rowCentre, 0.5),
      );
      expect(tester.getSize(header).height, AppSize.rowOneLine);
    },
  );
}
