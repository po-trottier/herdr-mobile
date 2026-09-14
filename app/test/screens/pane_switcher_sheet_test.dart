/// Tests `pane_switcher_sheet.dart` against `docs/31-mockups/08-terminal.md`'s switcher
/// (R-03-113 item 1, R-31-08-25): the three tiers of a fixture tree, the state bar and word
/// on an agent row and the pane glyph on a shell row (R-03-100, R-32-597), the current pane's
/// selected state, the tap that closes the sheet and hands another pane's id to the caller
/// (never the current pane's), a workspace that collapses in place, the row set R-03-101
/// forbids staying absent, and the empty tree. Since 2026-09-10, R-03-115 also makes every pane
/// row one line high and puts each agent row's kind, pane, and state on one baseline.
library;

import 'dart:ui' show TextBaseline, Tristate;

import 'package:flutter/rendering.dart'
    show BoxConstraints, RenderBox, SemanticsNode;
import 'package:flutter/widgets.dart'
    show
        AnimatedContainer,
        BoxDecoration,
        Icon,
        Semantics,
        Size,
        ValueChanged,
        Widget;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/models/messages/pane_scroll_state.dart'
    show PaneScrollState;
import 'package:herdr_mobile/models/messages/pane_summary.dart'
    show PaneSummary;
import 'package:herdr_mobile/models/messages/tab_summary.dart' show TabSummary;
import 'package:herdr_mobile/models/messages/tree_snapshot.dart'
    show TreeSnapshot;
import 'package:herdr_mobile/models/messages/workspace_summary.dart'
    show WorkspaceSummary;
import 'package:herdr_mobile/screens/pane_switcher_sheet.dart';
import 'package:herdr_mobile/widgets/app_section_header.dart'
    show AppSectionHeader;
import 'package:herdr_mobile/widgets/status_bar.dart' show BarState, StatusBar;
import 'package:herdr_mobile/widgets/theme/app_color.dart' show AppColor;
import 'package:herdr_mobile/widgets/theme/app_size.dart' show AppSize;
import 'package:herdr_mobile/widgets/theme/app_space.dart' show AppSpace;
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart'
    show Builder, ElevatedButton, MaterialApp, Scaffold, Text;

const PaneScrollState _scroll = PaneScrollState(
  offsetFromBottom: 0,
  maxOffsetFromBottom: 0,
  viewportRows: 50,
);

/// Two workspaces, three tabs, four panes: a `blocked` agent (the current pane), a `done`
/// agent in a second tab, a shell beside the current pane, and an agent in the second
/// workspace.
const TreeSnapshot _tree = TreeSnapshot(
  workspaces: [
    WorkspaceSummary(workspaceId: 'w3', name: 'plugin', focused: true),
    WorkspaceSummary(workspaceId: 'w4', name: 'docs', focused: false),
  ],
  tabs: [
    TabSummary(
      tabId: 'w3:t1',
      workspaceId: 'w3',
      title: 'plugin',
      focused: true,
    ),
    TabSummary(
      tabId: 'w3:t2',
      workspaceId: 'w3',
      title: 'tests',
      focused: false,
    ),
    TabSummary(
      tabId: 'w4:t1',
      workspaceId: 'w4',
      title: 'notes',
      focused: true,
    ),
  ],
  panes: [
    PaneSummary(
      paneId: 'w3:p1',
      workspaceId: 'w3',
      tabId: 'w3:t1',
      terminalId: 'term-1',
      label: 'main',
      title: 'claude',
      cwd: '/work',
      focused: true,
      agent: 'claude',
      agentStatus: 'blocked',
      revision: 1,
      scroll: _scroll,
    ),
    PaneSummary(
      paneId: 'w3:p3',
      workspaceId: 'w3',
      tabId: 'w3:t1',
      terminalId: 'term-3',
      label: '',
      title: 'zsh',
      cwd: '/work',
      focused: false,
      agentStatus: 'unknown',
      revision: 1,
      scroll: _scroll,
    ),
    PaneSummary(
      paneId: 'w3:p2',
      workspaceId: 'w3',
      tabId: 'w3:t2',
      terminalId: 'term-2',
      label: '',
      title: 'codex',
      cwd: '/work',
      focused: false,
      agent: 'codex',
      agentStatus: 'done',
      revision: 1,
      scroll: _scroll,
    ),
    PaneSummary(
      paneId: 'w4:p1',
      workspaceId: 'w4',
      tabId: 'w4:t1',
      terminalId: 'term-4',
      label: 'review',
      title: 'claude',
      cwd: '/docs',
      focused: true,
      agent: 'claude',
      agentStatus: 'working',
      revision: 1,
      scroll: _scroll,
    ),
  ],
  agents: [],
);

/// Pumps the sheet's `motion.duration.base` transition by hand: the `working` agent's state
/// bar pulses for as long as the sheet is open, so `pumpAndSettle` never settles here.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Opens the sheet from a plain button, the way `pane_actions_sheet_test.dart` opens its own:
/// `showModalBottomSheet` pushes the sheet as a sibling route of `home`.
Future<void> _openSheet(
  WidgetTester tester, {
  TreeSnapshot tree = _tree,
  String currentPaneId = 'w3:p1',
  required ValueChanged<String> onSwitchPane,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showPaneSwitcherSheet(
              context,
              tree: tree,
              currentPaneId: currentPaneId,
              onSwitchPane: onSwitchPane,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await _settle(tester);
}

/// One pane row, by the single unchanged semantics label that describes its contents.
Finder _row(String label) => find.byWidgetPredicate(
  (Widget widget) => widget is Semantics && widget.properties.label == label,
);

Semantics _rowWidget(WidgetTester tester, String label) =>
    tester.widget<Semantics>(_row(label));

void main() {
  testWidgets(
    'lists every workspace, tab and pane of the tree in three tiers; an agent row carries its '
    'state bar and word, a shell row the pane glyph and neither (R-03-100, R-32-597)',
    (tester) async {
      await _openSheet(tester, onSwitchPane: (_) {});

      expect(find.byType(PaneSwitcherSheet), findsOneWidget);
      expect(find.text('Switch pane'), findsOneWidget);
      // Tier 1: one shared header per workspace, with its pane count.
      final headers = tester
          .widgetList<AppSectionHeader>(find.byType(AppSectionHeader))
          .toList();
      expect(headers.map((h) => h.label), ['plugin', 'docs']);
      expect(headers.map((h) => h.count), ['3 panes', '1 pane']);
      // Tier 2: the tab titles, each behind the `A tab` glyph.
      expect(find.text('tests'), findsOneWidget);
      expect(find.text('notes'), findsOneWidget);
      expect(find.byIcon(Symbols.tab_rounded), findsNWidgets(3));
      // Tier 3: every pane is one line. Agent rows carry the state bar and word; the shell row
      // carries the pane glyph and neither state cue.
      final Finder claude = _row('claude, Blocked, main');
      final StatusBar blocked = tester.widget<StatusBar>(
        find.descendant(of: claude, matching: find.byType(StatusBar)),
      );
      expect(blocked.state, BarState.blocked);
      final Finder codex = _row('codex, Done, pane 2');
      final StatusBar done = tester.widget<StatusBar>(
        find.descendant(of: codex, matching: find.byType(StatusBar)),
      );
      expect(done.state, BarState.done);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Blocked'), findsOneWidget);
      expect(find.text('Working'), findsOneWidget);
      final Finder shell = _row('pane 3, zsh');
      expect(
        find.descendant(of: shell, matching: find.byType(StatusBar)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: shell,
          matching: find.byWidgetPredicate(
            (Widget widget) =>
                widget is Icon && widget.icon == Symbols.splitscreen_rounded,
          ),
        ),
        findsOneWidget,
      );
      // R-03-101: no layout task rides along.
      for (final String absent in <String>[
        'Split right',
        'Split down',
        'Zoom this pane',
        'Rename pane',
        'Close pane',
      ]) {
        expect(find.text(absent), findsNothing, reason: absent);
      }
    },
  );

  testWidgets('agent and shell rows are 48 high; agent kind, pane, and state share one baseline '
      '(R-03-115, 2026-09-10)', (tester) async {
    await _openSheet(tester, onSwitchPane: (_) {});

    const List<String> labels = <String>[
      'claude, Blocked, main',
      'pane 3, zsh',
      'codex, Done, pane 2',
      'claude, Working, review',
    ];
    for (final String label in labels) {
      expect(tester.getSize(_row(label)).height, AppSize.targetMin);
    }

    final Finder agent = _row(labels.first);
    final Finder kind = find.descendant(
      of: agent,
      matching: find.text('claude'),
    );
    final Finder pane = find.descendant(of: agent, matching: find.text('main'));
    final Finder state = find.descendant(
      of: agent,
      matching: find.text('Blocked'),
    );
    double baselineOf(Finder finder) {
      final RenderBox box = tester.renderObject(finder);
      return tester.getTopLeft(finder).dy +
          box.getDryBaseline(
            BoxConstraints.tight(box.size),
            TextBaseline.alphabetic,
          )!;
    }

    expect(baselineOf(pane), moreOrLessEquals(baselineOf(kind), epsilon: 0.5));
    expect(baselineOf(state), moreOrLessEquals(baselineOf(kind), epsilon: 0.5));
    expect(
      tester.getTopLeft(pane).dx - tester.getTopRight(kind).dx,
      moreOrLessEquals(AppSpace.space2, epsilon: 0.01),
    );
    expect(
      tester
          .getSize(find.descendant(of: agent, matching: find.byType(StatusBar)))
          .height,
      tester.getSize(agent).height,
    );
  });

  testWidgets(
    'the current pane is the one selected row, in the wash and in the semantics state',
    (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await _openSheet(tester, onSwitchPane: (_) {});

      expect(
        _rowWidget(tester, 'claude, Blocked, main').properties.selected,
        isTrue,
      );
      expect(
        _rowWidget(tester, 'codex, Done, pane 2').properties.selected,
        isFalse,
      );
      expect(_rowWidget(tester, 'pane 3, zsh').properties.selected, isFalse);
      expect(
        _rowWidget(tester, 'claude, Working, review').properties.selected,
        isFalse,
      );

      final Finder selectedRow = _row('claude, Blocked, main');
      final SemanticsNode selected = tester.getSemantics(selectedRow);
      expect(selected.flagsCollection.isSelected, Tristate.isTrue);
      expect(selected.label, 'claude, Blocked, main');
      final SemanticsNode other = tester.getSemantics(
        _row('codex, Done, pane 2'),
      );
      expect(other.flagsCollection.isSelected, Tristate.isFalse);
      final AnimatedContainer wash = tester.widget<AnimatedContainer>(
        find.descendant(
          of: selectedRow,
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(
        (wash.decoration! as BoxDecoration).color,
        AppColor.of(tester.element(selectedRow)).accentSoft,
      );
      // The framework checks for a live handle before tearDowns run.
      handle.dispose();
    },
  );

  testWidgets('a tap on another pane closes the sheet and hands its id to onSwitchPane; a tap on the '
      'current pane only closes the sheet', (tester) async {
    final List<String> switched = <String>[];
    await _openSheet(tester, onSwitchPane: switched.add);

    await tester.tap(find.text('main'));
    await _settle(tester);
    expect(find.byType(PaneSwitcherSheet), findsNothing);
    expect(switched, isEmpty);

    await tester.tap(find.text('open'));
    await _settle(tester);
    await tester.tap(find.text('review'));
    await _settle(tester);
    expect(find.byType(PaneSwitcherSheet), findsNothing);
    expect(switched, ['w4:p1']);
  });

  testWidgets(
    'a workspace header collapses its tabs and panes in place and keeps its count (R-32-566)',
    (tester) async {
      await _openSheet(tester, onSwitchPane: (_) {});

      await tester.tap(find.text('plugin').first);
      await _settle(tester);
      expect(find.text('tests'), findsNothing);
      expect(_row('claude, Blocked, main'), findsNothing);
      expect(_row('pane 3, zsh'), findsNothing);
      expect(find.text('3 panes'), findsOneWidget);
      // The other workspace is untouched.
      expect(find.text('notes'), findsOneWidget);
      expect(_row('claude, Working, review'), findsOneWidget);

      await tester.tap(find.text('plugin').first);
      await _settle(tester);
      expect(find.text('tests'), findsOneWidget);
      expect(_row('claude, Blocked, main'), findsOneWidget);
    },
  );

  testWidgets('an empty tree says so instead of drawing nothing', (
    tester,
  ) async {
    await _openSheet(
      tester,
      tree: const TreeSnapshot(workspaces: [], tabs: [], panes: [], agents: []),
      currentPaneId: 'w3:p1',
      onSwitchPane: (_) {},
    );
    expect(find.text('No panes on this computer.'), findsOneWidget);
    expect(find.byType(StatusBar), findsNothing);
  });
}
