/// Golden tests for `CreateSheet` (`app/lib/screens/create_sheet.dart`, `WP-18-d`), the
/// `Default` row of `docs/31-mockups/17-create.md`'s `## States` table (R-90-011): a pane is
/// open on the connected computer, so the third wireframe's every row is enabled and named,
/// rendered in both Selenized dark and light (R-32-012).
///
/// `CreateSheet` is stateful and talks to `pane_actions.dart` through the `messages`,
/// `connectionState` and `send` constructor arguments, so this file reuses
/// `create_sheet_test.dart`'s own `_Harness` (fake broadcast streams, no real relay) and its
/// `showCreateSheet`-through-a-button opening pattern, rather than building a second fake
/// service scaffold.
///
/// Fonts, the app theme and the 375 x 667 reference size come from `golden_support.dart`
/// (`loadAppFonts`, `goldenApp`, `goldenReferenceSize`); see its doc comment for why.
/// `goldenApp`'s `MediaQuery` sits above the `MaterialApp`, so the sheet `showModalBottomSheet`
/// pushes above `home` reads the same brightness and size. `devicePixelRatio` stays fixed at
/// 1.0.
library;

import 'dart:async';

import 'package:flutter/widgets.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/models/message.dart';
import 'package:herdr_mobile/models/messages/pane_scroll_state.dart';
import 'package:herdr_mobile/models/messages/pane_summary.dart';
import 'package:herdr_mobile/models/messages/tab_summary.dart';
import 'package:herdr_mobile/models/messages/tree_snapshot.dart';
import 'package:herdr_mobile/models/messages/workspace_summary.dart';
import 'package:herdr_mobile/screens/create_sheet.dart';
import 'package:herdr_mobile/services/relay.dart';
import 'package:material_ui/material_ui.dart'
    show Builder, ElevatedButton, Scaffold, Text;

import 'golden_support.dart';

/// Mirrors `create_sheet_test.dart`'s own `_Harness`: fake broadcast streams for `messages` and
/// `connectionState`, and a `send` that only records what left the phone. No `host_action_ack`
/// is ever delivered in this file — the `Default` state is what draws before any reply arrives.
class _Harness {
  _Harness()
    : messages = StreamController<Message>.broadcast(),
      connectionState = StreamController<RelayConnectionState>.broadcast();

  final StreamController<Message> messages;
  final StreamController<RelayConnectionState> connectionState;

  void send(Message message, {String? corr}) {}

  Future<void> dispose() async {
    await messages.close();
    await connectionState.close();
  }
}

/// One pane, open in one workspace, so every row of the `Default` state's third wireframe is
/// enabled and named: `New space`, `New tab in herdr-relay`, `Split pane claude right` and
/// `Split pane claude down`.
const _snapshot = TreeSnapshot(
  workspaces: [
    WorkspaceSummary(workspaceId: 'ws-1', name: 'herdr-relay', focused: true),
  ],
  tabs: <TabSummary>[],
  panes: [
    PaneSummary(
      paneId: 'pane-1',
      workspaceId: 'ws-1',
      tabId: 'tab-1',
      terminalId: 'term-1',
      label: '',
      title: 'claude',
      cwd: '/home/patrick/herdr-relay',
      focused: true,
      agentStatus: 'idle',
      revision: 1,
      scroll: PaneScrollState(
        offsetFromBottom: 0,
        maxOffsetFromBottom: 0,
        viewportRows: 24,
      ),
    ),
  ],
  agents: [],
);

const _themes = <(String, Brightness)>[
  ('dark', Brightness.dark),
  ('light', Brightness.light),
];

void main() {
  setUpAll(loadAppFonts);

  for (final (themeName, brightness) in _themes) {
    testWidgets('default ($themeName) matches docs/31-mockups/17-create.md', (
      tester,
    ) async {
      tester.view.physicalSize = goldenReferenceSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final harness = _Harness();
      addTearDown(harness.dispose);

      await tester.pumpWidget(
        goldenApp(
          brightness: brightness,
          child: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showCreateSheet(
                  context,
                  hostName: 'patrick-desk',
                  snapshot: _snapshot,
                  currentPaneId: 'pane-1',
                  messages: harness.messages.stream,
                  connectionState: harness.connectionState.stream,
                  send: harness.send,
                  onCreated: (_) {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Structural proof alongside the visual one: every callout the mockup's third wireframe
      // draws is really present in the tree, not just painted to look right by coincidence.
      expect(find.text('Create on patrick-desk'), findsOneWidget);
      expect(find.text('New space'), findsOneWidget);
      expect(find.text('New tab in herdr-relay'), findsOneWidget);
      expect(find.text('Split pane claude right'), findsOneWidget);
      expect(find.text('Split pane claude down'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      await expectLater(
        find.byType(CreateSheet),
        matchesGoldenFile('goldens/create_sheet_default_$themeName.png'),
      );
    });
  }
}
