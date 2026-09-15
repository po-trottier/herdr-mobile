import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoListTile, CupertinoExpansionTile, CupertinoSwitch;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/widgets/theme/app_color.dart';
import 'package:herdr_mobile/widgets/theme/chrome_activity_indicator.dart';
import 'package:herdr_mobile/widgets/theme/chrome_list_row.dart';
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart';

Future<void> _pump(WidgetTester tester, Widget row) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: row)));
  await tester.pump();
}

void main() {
  for (final TargetPlatform platform in <TargetPlatform>[
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    final bool ios = platform == TargetPlatform.iOS;
    final TargetPlatformVariant variant = TargetPlatformVariant.only(platform);
    testWidgets('$platform disabled sheet has no tap action', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, const ChromeListRow.sheet(title: 'Unavailable'));
      expect(
        tester.getSemantics(find.text('Unavailable')),
        matchesSemantics(
          label: 'Unavailable',
          hasSelectedState: true,
          hasEnabledState: true,
          isEnabled: false,
          hasTapAction: false,
        ),
      );
      handle.dispose();
    }, variant: variant);
    testWidgets('$platform sheet selects and taps a native row', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await _pump(
        tester,
        ChromeListRow.sheet(
          title: 'Session',
          subtitle: 'Available',
          selected: true,
          navigation: true,
          onTap: () => taps++,
        ),
      );
      expect(find.byType(ios ? CupertinoListTile : ListTile), findsOneWidget);
      expect(
        find.byIcon(Symbols.chevron_right_rounded),
        ios ? findsOneWidget : findsNothing,
      );
      expect(
        tester.getSemantics(find.text('Session')),
        matchesSemantics(
          label: 'Session\nAvailable',
          isSelected: true,
          hasSelectedState: true,
          isButton: !ios,
          hasTapAction: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: !ios,
          hasFocusAction: !ios,
        ),
      );
      await tester.tap(find.text('Session'));
      expect(taps, 1);
      handle.dispose();
    }, variant: variant);

    testWidgets('$platform loading blocks taps and keeps trailing content', (
      tester,
    ) async {
      var taps = 0;
      await _pump(
        tester,
        ChromeListRow.sheet(
          title: 'Connect',
          loading: true,
          trailing: const Text('Host'),
          onTap: () => taps++,
        ),
      );
      expect(find.byType(ChromeActivityIndicator), findsOneWidget);
      expect(find.text('Host'), findsOneWidget);
      await tester.tap(find.text('Connect'));
      expect(taps, 0);
    }, variant: variant);

    testWidgets('$platform destructive hue stays on the leading icon', (
      tester,
    ) async {
      await _pump(
        tester,
        ChromeListRow.sheet(
          title: 'Remove',
          destructive: true,
          leading: const Icon(Symbols.delete_outline_rounded),
          onTap: () {},
        ),
      );
      final BuildContext iconContext = tester.element(
        find.byIcon(Symbols.delete_outline_rounded),
      );
      final AppColor color = AppColor.of(iconContext);
      expect(IconTheme.of(iconContext).color, color.statusError);
      final BuildContext titleContext = tester.element(find.text('Remove'));
      expect(
        DefaultTextStyle.of(titleContext).style.color,
        isNot(color.statusError),
      );
    }, variant: variant);

    testWidgets('$platform expansion reports collapse and reopen', (
      tester,
    ) async {
      final List<bool> changes = <bool>[];
      await _pump(
        tester,
        ChromeListRow.expand(
          title: 'Workspace',
          initiallyExpanded: true,
          onExpansionChanged: changes.add,
          trailing: const Text('2 panes'),
          child: const Text('Pane content'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byType(ios ? CupertinoExpansionTile : ExpansionTile),
        findsOneWidget,
      );
      expect(find.text('Pane content').hitTestable(), findsOneWidget);
      expect(find.text('2 panes'), findsOneWidget);
      await tester.tap(find.text('Workspace'));
      await tester.pumpAndSettle();
      expect(changes, <bool>[false]);
      expect(find.text('Pane content').hitTestable(), findsNothing);
      await tester.tap(find.text('Workspace'));
      await tester.pumpAndSettle();
      expect(changes, <bool>[false, true]);
      expect(find.text('Pane content').hitTestable(), findsOneWidget);
    }, variant: variant);

    testWidgets('$platform switch changes once and disables correctly', (
      tester,
    ) async {
      var changes = 0;
      await _pump(
        tester,
        ChromeListRow.toggle(
          title: 'Haptics',
          value: false,
          onChanged: (value) {
            expect(value, isTrue);
            changes++;
          },
        ),
      );
      await tester.tap(
        ios ? find.byType(CupertinoSwitch) : find.text('Haptics'),
      );
      expect(changes, 1);
      await _pump(
        tester,
        const ChromeListRow.toggle(
          title: 'Haptics',
          value: false,
          onChanged: null,
        ),
      );
      await tester.tap(find.text('Haptics'));
      expect(changes, 1);
    }, variant: variant);

    testWidgets('$platform sheet description wraps without truncation', (
      tester,
    ) async {
      const String description =
          'A long description that explains the action in full and continues across several lines without truncation.';
      await _pump(
        tester,
        SizedBox(
          width: 240,
          child: ChromeListRow.sheet(
            title: 'Action',
            subtitle: description,
            onTap: () {},
          ),
        ),
      );
      final TextStyle style = DefaultTextStyle.of(
        tester.element(find.text(description)),
      ).style;
      final TextPainter painter = TextPainter(
        text: TextSpan(text: description, style: style),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 208);
      expect(
        tester.getSize(find.text(description)).height,
        greaterThan(painter.preferredLineHeight * 2),
      );
      painter.dispose();
      expect(tester.takeException(), isNull);
    }, variant: variant);
  }
}
