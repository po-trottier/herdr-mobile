/// Golden tests for `PaneSwitcherSheet` (`app/lib/screens/pane_switcher_sheet.dart`), the
/// switcher wireframe of `docs/31-mockups/08-terminal.md` (R-31-08-25), rendered on both
/// platforms in both Selenized themes (R-32-012). Since 2026-09-10, the frame also proves the
/// one-line agent and shell pane rows of R-03-115. The sheet is the same Material bottom sheet
/// on both (R-33-037), so platform goldens differ only where native type or physics differ.
///
/// Opens the sheet through the real `showPaneSwitcherSheet`, the way
/// `pane_actions_sheet_golden_test.dart` does, so the `Material` ancestor, the `radius.lg`
/// corners and `color.bg.raised` are the ones a person sees. `disableAnimations` holds the
/// `working` row's pulsing state bar at full opacity (R-32-606), the same way the agent list
/// goldens do, so the frame is deterministic. Fonts, the app theme and the 375 x 667 reference
/// size come from `golden_support.dart`.
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart' show Brightness, MediaQueryData;
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
import 'package:material_ui/material_ui.dart'
    show Builder, ElevatedButton, Scaffold, Text;

import 'golden_support.dart';

const PaneScrollState _scroll = PaneScrollState(
  offsetFromBottom: 0,
  maxOffsetFromBottom: 0,
  viewportRows: 50,
);

/// The switcher wireframe's tree: two workspaces, three tabs, four panes, every agent state
/// hue the wireframe shows (`blocked` on the current pane, `done`, `working`) plus one shell.
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

const _platforms = <(String, TargetPlatform)>[
  ('android', TargetPlatform.android),
  ('ios', TargetPlatform.iOS),
];

const _themes = <(String, Brightness)>[
  ('dark', Brightness.dark),
  ('light', Brightness.light),
];

void main() {
  setUpAll(loadAppFonts);

  for (final (platformName, platform) in _platforms) {
    for (final (themeName, brightness) in _themes) {
      testWidgets(
        '$platformName $themeName matches the switcher wireframe of docs/31-mockups/08-terminal.md',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          tester.view.physicalSize = goldenReferenceSize;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            goldenApp(
              brightness: brightness,
              adjust: (MediaQueryData ambient) =>
                  ambient.copyWith(disableAnimations: true),
              child: Builder(
                builder: (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () => showPaneSwitcherSheet(
                      context,
                      tree: _tree,
                      currentPaneId: 'w3:p1',
                      onSwitchPane: (_) {},
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();

          // Structural proof beside the visual one: every tier is present and
          // the current pane is the selected row.
          expect(find.text('Switch pane'), findsOneWidget);
          expect(find.text('docs'), findsOneWidget);
          expect(find.text('tests'), findsOneWidget);
          expect(find.text('Blocked'), findsOneWidget);
          expect(find.text('Done'), findsOneWidget);
          expect(find.text('Working'), findsOneWidget);
          expect(find.bySemanticsLabel('pane 3, zsh'), findsOneWidget);

          await expectLater(
            find.byType(PaneSwitcherSheet),
            matchesGoldenFile(
              'goldens/pane_switcher_sheet_${platformName}_$themeName.png',
            ),
          );
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }
  }
}
