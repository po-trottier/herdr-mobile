/// Tests `StatusLegendScreen` (`app/lib/screens/status_legend_screen.dart`), the `Status
/// colours` legend of `docs/31-mockups/20-status-legend.md` (R-03-106): every `BarState` is
/// listed exactly once beside its word (R-31-20-01), every row is one platform static tile with a
/// one-sentence meaning (R-31-20-02) and one semantics node reading `<word>, <meaning>`
/// (R-31-20-06), the states that share a hue sit in one group and the sharing is said in words
/// (R-31-20-03, R-31-20-04), and the page renders with no service and no connectivity wiring at
/// all (R-31-20-07).
library;

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoListSection, CupertinoListTile, CupertinoNavigationBar;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart' show ColoredBox, Size, Text;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/screens/status_legend_screen.dart';
import 'package:herdr_mobile/widgets/app_list_row.dart' show AppListRow;
import 'package:herdr_mobile/widgets/ground_grid.dart' show GroundGrid;
import 'package:herdr_mobile/widgets/status_bar.dart' show BarState, StatusBar;
import 'package:herdr_mobile/widgets/theme/app_color.dart' show AppColor;
import 'package:herdr_mobile/widgets/theme/chrome_list_row.dart'
    show ChromeListRow;
import 'package:herdr_mobile/widgets/theme/chrome_settings_section.dart'
    show ChromeSettingsSection;
import 'package:material_ui/material_ui.dart' show AppBar, MaterialApp;

/// The word the app writes beside each bar (`docs/30-ux-spec.md` R-30-400 for the five agent
/// states; `Ok`, `Warning` and `Error` for a connection leg and the live bar), the contract the
/// legend's titles pin.
const Map<BarState, String> _words = <BarState, String>{
  BarState.working: 'Working',
  BarState.warning: 'Warning',
  BarState.blocked: 'Blocked',
  BarState.error: 'Error',
  BarState.idle: 'Idle',
  BarState.ok: 'Ok',
  BarState.done: 'Done',
  BarState.unknown: 'Unknown',
};

/// The five hue groups of R-31-20-03 in drawing order, each pair that shares a hue together.
const List<(String, List<BarState>)> _groups = <(String, List<BarState>)>[
  ('AMBER', <BarState>[BarState.working, BarState.warning]),
  ('RED', <BarState>[BarState.blocked, BarState.error]),
  ('GREEN', <BarState>[BarState.idle, BarState.ok]),
  ('TEAL', <BarState>[BarState.done]),
  ('GREY', <BarState>[BarState.unknown]),
];

/// A surface tall enough for the whole list, so the lazy scroll view builds every row and no
/// scroll is needed, mirroring `settings_screen_test.dart`'s own `useTallSurface`.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpScreen(WidgetTester tester) async {
  _useTallSurface(tester);
  await tester.pumpWidget(const MaterialApp(home: StatusLegendScreen()));
  await tester.pump();
}

void main() {
  testWidgets(
    'lists every BarState exactly once, each bar beside its own word (R-31-20-01)',
    (tester) async {
      await _pumpScreen(tester);

      final List<BarState> drawn = tester
          .widgetList<StatusBar>(find.byType(StatusBar))
          .map((StatusBar bar) => bar.state)
          .toList();
      expect(drawn, hasLength(BarState.values.length));
      expect(drawn.toSet(), BarState.values.toSet());

      final List<String> titles = tester
          .widgetList<ChromeListRow>(find.byType(ChromeListRow))
          .map((ChromeListRow row) => row.title)
          .toList();
      expect(titles, hasLength(BarState.values.length));
      for (final BarState state in BarState.values) {
        expect(find.text(_words[state]!), findsOneWidget);
      }
      // The bars and the words share one order: the i-th bar is the i-th row's state.
      expect(drawn.map((BarState s) => _words[s]).toList(), titles);
    },
  );

  testWidgets('the states that share a hue sit together under that colour, in the fixed order, and the '
      'sharing is said in words once (R-31-20-03, R-31-20-04)', (tester) async {
    await _pumpScreen(tester);

    final List<BarState> drawn = tester
        .widgetList<StatusBar>(find.byType(StatusBar))
        .map((StatusBar bar) => bar.state)
        .toList();
    final List<BarState> expected = <BarState>[
      for (final (_, List<BarState> states) in _groups) ...states,
    ];
    expect(drawn, expected);

    // One group header per hue, above its rows in the same top-to-bottom order.
    double previousTop = 0;
    for (final (String header, List<BarState> states) in _groups) {
      expect(find.text(header), findsOneWidget);
      final double headerTop = tester.getTopLeft(find.text(header)).dy;
      expect(headerTop, greaterThan(previousTop));
      for (final BarState state in states) {
        final double rowTop = tester.getTopLeft(find.text(_words[state]!)).dy;
        expect(rowTop, greaterThan(headerTop));
        previousTop = rowTop;
      }
    }

    // The lead line names all three shared hues; the `GREEN` caption names the saved
    // computer, the one bar a person sees most whose row is not an agent's.
    final Text lead = tester.widget<Text>(find.text(statusLegendLead));
    expect(lead.data, contains('Working and Warning share one amber'));
    expect(lead.data, contains('Blocked and Error share one red'));
    expect(lead.data, contains('Idle and Ok share one green'));
    expect(lead.data, contains('The word beside the bar tells them apart.'));
    expect(
      find.text(
        'A paired computer or phone that is not connected shows Idle too.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('every row carries one plain sentence as its meaning and is one semantics node reading '
      '`word, meaning` (R-31-20-02, R-31-20-06)', (tester) async {
    // Disposed at the end of the body: the tester checks for a live handle before teardowns run.
    final SemanticsHandle semantics = tester.ensureSemantics();
    await _pumpScreen(tester);

    final Iterable<ChromeListRow> rows = tester.widgetList<ChromeListRow>(
      find.byType(ChromeListRow),
    );
    for (final ChromeListRow row in rows) {
      final String meaning = row.subtitle!;
      expect(meaning, isNotEmpty);
      expect(meaning, endsWith('.'));
      expect(
        meaning.substring(0, meaning.length - 1),
        isNot(contains('.')),
        reason: '${row.title} carries more than one sentence',
      );
      expect(
        find.bySemanticsLabel('${row.title}, $meaning'),
        findsOneWidget,
        reason: '${row.title} is not one node reading word, meaning',
      );
      // Neither half is a node of its own: the row speaks once.
      expect(find.bySemanticsLabel(row.title), findsNothing);
      expect(find.bySemanticsLabel(meaning), findsNothing);
    }
    semantics.dispose();
  });

  testWidgets(
    'Android: an AppBar, every row the section 7.4 row, no CupertinoListTile (R-33-073)',
    (tester) async {
      await _pumpScreen(tester);

      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(CupertinoNavigationBar), findsNothing);
      expect(find.text('Status colours'), findsOneWidget);
      expect(find.byType(AppListRow), findsNWidgets(BarState.values.length));
      expect(find.byType(CupertinoListTile), findsNothing);
    },
  );

  testWidgets('iOS: a CupertinoNavigationBar, every row a CupertinoListTile inside a CupertinoListSection, '
      'never an AppListRow (R-33-073)', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    // A failed expect below must not leak the override into the next test; the binding's own
    // invariant check runs before the teardowns, so the body resets it too.
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await _pumpScreen(tester);

    expect(find.byType(CupertinoNavigationBar), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Status colours'), findsOneWidget);
    expect(find.byType(CupertinoListSection), findsNWidgets(_groups.length));
    expect(
      find.byType(CupertinoListTile),
      findsNWidgets(BarState.values.length),
    );
    expect(find.byType(AppListRow), findsNothing);
    for (final String word in _words.values) {
      expect(
        find.ancestor(
          of: find.text(word),
          matching: find.byType(CupertinoListTile),
        ),
        findsOneWidget,
        reason: '$word is not a CupertinoListTile',
      );
    }
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('the body is plain color.bg.base with no ground grid, one section per hue group '
      '(R-03-107, amended 2026-09-09)', (tester) async {
    await _pumpScreen(tester);

    expect(find.byType(GroundGrid), findsNothing);
    // The bars are `ColoredBox`es in their hue; nothing paints `color.bg.base` as paper.
    final AppColor color = AppColor.of(
      tester.element(find.byType(StatusLegendScreen)),
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is ColoredBox && widget.color == color.bgBase,
      ),
      findsNothing,
    );
    expect(find.byType(ChromeSettingsSection), findsNWidgets(_groups.length));
  });
}
