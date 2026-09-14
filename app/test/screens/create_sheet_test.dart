/// Tests workspace and tab creation, acknowledgements, refusal, and connection loss.
/// The create menu does not offer pane actions.
library;

import 'dart:async';

import 'package:flutter/material.dart' show MaterialApp, Offset;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/models/codes.dart';
import 'package:herdr_mobile/models/message.dart';
import 'package:herdr_mobile/models/messages/agent_summary.dart';
import 'package:herdr_mobile/models/messages/error_message.dart';
import 'package:herdr_mobile/models/messages/host_action_ack.dart';
import 'package:herdr_mobile/models/messages/host_action_kind.dart';
import 'package:herdr_mobile/models/messages/pane_scroll_state.dart';
import 'package:herdr_mobile/models/messages/pane_summary.dart';
import 'package:herdr_mobile/models/messages/tab_summary.dart';
import 'package:herdr_mobile/models/messages/tree_snapshot.dart';
import 'package:herdr_mobile/models/messages/workspace_summary.dart';
import 'package:herdr_mobile/screens/create_sheet.dart';
import 'package:herdr_mobile/services/relay.dart';
import 'package:herdr_mobile/widgets/app_list_row.dart';
import 'package:material_ui/material_ui.dart'
    show AlertDialog, Builder, ElevatedButton, Scaffold, Text;

WorkspaceSummary _workspace({
  String id = 'ws-1',
  String name = 'herdr-relay',
}) => WorkspaceSummary(workspaceId: id, name: name, focused: true);

PaneSummary _pane({
  String id = 'pane-1',
  String workspaceId = 'ws-1',
  String label = '',
  String title = 'claude',
}) => PaneSummary(
  paneId: id,
  workspaceId: workspaceId,
  tabId: 'tab-1',
  terminalId: 'term-1',
  label: label,
  title: title,
  cwd: '/home',
  focused: true,
  agentStatus: 'idle',
  revision: 1,
  scroll: const PaneScrollState(
    offsetFromBottom: 0,
    maxOffsetFromBottom: 0,
    viewportRows: 24,
  ),
);

TreeSnapshot _snapshot({
  List<WorkspaceSummary> workspaces = const <WorkspaceSummary>[],
  List<PaneSummary> panes = const <PaneSummary>[],
}) => TreeSnapshot(
  workspaces: workspaces,
  tabs: const <TabSummary>[],
  panes: panes,
  agents: const <AgentSummary>[],
);

class _Harness {
  _Harness()
    : messages = StreamController<Message>.broadcast(),
      connectionState = StreamController<RelayConnectionState>.broadcast();

  final StreamController<Message> messages;
  final StreamController<RelayConnectionState> connectionState;
  final List<Message> sent = <Message>[];

  void send(Message message, {String? corr}) => sent.add(message);

  /// Delivers [message] on the fake wire, then pumps to render the resulting `setState`.
  Future<void> deliver(WidgetTester tester, Message message) async {
    messages.add(message);
    await tester.pump();
    await tester.pump();
  }

  Future<void> dispose() async {
    await messages.close();
    await connectionState.close();
  }
}

/// Opens the sheet from a plain button, so `Navigator.of(context).pop()` pops the sheet's own
/// route rather than the app's only route.
Future<void> _openSheet(
  WidgetTester tester,
  _Harness harness, {
  required TreeSnapshot snapshot,
  required void Function(CreateResult) onCreated,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showCreateSheet(
              context,
              hostName: 'patrick-desk',
              snapshot: snapshot,
              messages: harness.messages.stream,
              connectionState: harness.connectionState.stream,
              send: harness.send,
              onCreated: onCreated,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'New space sends workspace.create and, on a host_action_ack with result_id, calls '
    'onCreated with CreatedWorkspace and closes the sheet',
    (WidgetTester tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      CreateResult? result;

      await _openSheet(
        tester,
        harness,
        snapshot: _snapshot(workspaces: [_workspace()]),
        onCreated: (value) => result = value,
      );

      await tester.tap(find.text('New space'));
      await tester.pump();

      final request = harness.sent.whereType<MessageHostAction>().single;
      expect(request.payload.action, HostActionKind.workspaceCreate);
      expect(request.payload.params, <String, dynamic>{'focus': false});

      await harness.deliver(
        tester,
        const Message.hostActionAck(
          HostActionAck(
            action: HostActionKind.workspaceCreate,
            success: true,
            resultId: 'ws-99',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(result, isA<CreatedWorkspace>());
      expect((result! as CreatedWorkspace).workspaceId, 'ws-99');
      expect(find.text('New space'), findsNothing, reason: 'the sheet closed');
    },
  );

  testWidgets('an error reply shows the refusal text under Could not create that. and re-enables every '
      'row, with no navigation', (WidgetTester tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    CreateResult? result;

    await _openSheet(
      tester,
      harness,
      snapshot: _snapshot(workspaces: [_workspace()]),
      onCreated: (value) => result = value,
    );

    await tester.tap(find.text('New space'));
    await tester.pump();

    await harness.deliver(
      tester,
      const Message.error(
        ErrorMessage(
          code: ErrorCode.internalError,
          message: 'workstation refused: quota exceeded',
          fatal: false,
        ),
      ),
    );

    expect(find.text('Could not create that.'), findsOneWidget);
    expect(find.text('workstation refused: quota exceeded'), findsOneWidget);
    expect(result, isNull, reason: 'the menu stayed open, nothing was created');

    // Rows re-enabled: New space is tappable again.
    await tester.tap(find.text('New space'));
    await tester.pump();
    final requests = harness.sent.whereType<MessageHostAction>();
    expect(
      requests.length,
      2,
      reason: 'Try again is not required; a fresh tap works too',
    );
  });

  testWidgets(
    'a connection drop before any reply shows the outcome-unknown state with no error styling, '
    'and Check now returns to the menu once a fresh tree_snapshot arrives',
    (WidgetTester tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      CreateResult? result;

      await _openSheet(
        tester,
        harness,
        snapshot: _snapshot(workspaces: [_workspace()], panes: [_pane()]),
        onCreated: (value) => result = value,
      );

      await tester.tap(find.text('New space'));
      await tester.pump();

      harness.connectionState.add(const RelayDisconnected());
      await tester.pump();
      await tester.pump();

      expect(find.text('This phone did not get an answer.'), findsOneWidget);
      expect(find.text('The change may already be done.'), findsOneWidget);
      expect(find.text('Could not create that.'), findsNothing);
      expect(find.text('Check now'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);

      harness.connectionState.add(const RelayConnected());
      await tester.pump();

      await tester.tap(find.text('Check now'));
      await tester.pump();

      await harness.deliver(
        tester,
        Message.treeSnapshot(
          _snapshot(workspaces: [_workspace()], panes: [_pane()]),
        ),
      );

      expect(find.text('This phone did not get an answer.'), findsNothing);
      expect(find.text('New space'), findsOneWidget);
      expect(result, isNull);
    },
  );

  testWidgets('the create menu offers only space and tab actions', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await _openSheet(
      tester,
      harness,
      snapshot: _snapshot(workspaces: [_workspace()], panes: [_pane()]),
      onCreated: (_) {},
    );
    expect(find.text('New space'), findsOneWidget);
    expect(find.text('New tab in herdr-relay'), findsOneWidget);
    expect(find.byType(AppListRow), findsNWidgets(2));
    expect(find.textContaining('Split'), findsNothing);
  });

  testWidgets(
    'tapping New space raises no confirmation dialog - creating is not destructive (R-30-953)',
    (WidgetTester tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);

      await _openSheet(
        tester,
        harness,
        snapshot: _snapshot(workspaces: [_workspace()]),
        onCreated: (_) {},
      );

      await tester.tap(find.text('New space'));
      await tester.pump();

      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.text('Cancel'),
        findsOneWidget,
        reason: 'the sheet itself stayed open; no dialog intercepted the tap',
      );
    },
  );

  testWidgets('no phase of the create sheet offers to close a workspace, close a tab, or stop the server '
      '(R-30-955)', (WidgetTester tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);

    await _openSheet(
      tester,
      harness,
      snapshot: _snapshot(
        workspaces: [
          _workspace(),
          _workspace(id: 'ws-2', name: 'other-space'),
        ],
      ),
      onCreated: (_) {},
    );

    const forbidden = <String>[
      'Close workspace',
      'Close tab',
      'Stop server',
      'Close',
      'Stop',
    ];
    for (final phrase in forbidden) {
      expect(find.textContaining(phrase), findsNothing);
    }

    // The workspace-picker phase (callout 16) is a second, otherwise-untested screen this
    // sheet can show; it must not offer the forbidden actions either.
    await tester.tap(find.text('New tab...'));
    await tester.pump();

    for (final phrase in forbidden) {
      expect(find.textContaining(phrase), findsNothing);
    }
  });

  testWidgets('onCreated fires from the ack alone: no tree_request is sent, so navigation never waits on '
      'a full snapshot (R-30-956)', (WidgetTester tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    CreateResult? result;

    await _openSheet(
      tester,
      harness,
      snapshot: _snapshot(workspaces: [_workspace()]),
      onCreated: (value) => result = value,
    );

    await tester.tap(find.text('New space'));
    await tester.pump();

    await harness.deliver(
      tester,
      const Message.hostActionAck(
        HostActionAck(
          action: HostActionKind.workspaceCreate,
          success: true,
          resultId: 'ws-42',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect((result! as CreatedWorkspace).workspaceId, 'ws-42');
    expect(
      harness.sent.whereType<MessageTreeRequest>(),
      isEmpty,
      reason:
          'the ack carries the new id; a tree_request would mean the sheet waited on a '
          'full snapshot instead',
    );
  });

  testWidgets(
    'the create menu offers no zoom, rename, resize, copy or close-pane rows (R-31-17-06)',
    (WidgetTester tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);

      await _openSheet(
        tester,
        harness,
        snapshot: _snapshot(workspaces: [_workspace()], panes: [_pane()]),
        onCreated: (_) {},
      );

      for (final phrase in <String>[
        'Zoom',
        'Rename',
        'Resize',
        'Copy',
        'Close',
      ]) {
        expect(find.textContaining(phrase), findsNothing);
      }
    },
  );

  testWidgets('a scrim tap dismisses the idle sheet (R-31-17-07, callout 4)', (
    WidgetTester tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);

    await _openSheet(
      tester,
      harness,
      snapshot: _snapshot(workspaces: [_workspace()]),
      onCreated: (_) {},
    );

    // The point sits above the sheet, on the scrim.
    await tester.tapAt(const Offset(400, 20));
    await tester.pumpAndSettle();

    expect(find.text('Cancel'), findsNothing, reason: 'the sheet closed');
  });

  testWidgets(
    'a scrim tap does nothing while a create is in flight (R-31-17-07)',
    (WidgetTester tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      CreateResult? result;

      await _openSheet(
        tester,
        harness,
        snapshot: _snapshot(workspaces: [_workspace()]),
        onCreated: (value) => result = value,
      );

      await tester.tap(find.text('New space'));
      await tester.pump();

      // The point sits above the sheet, on the scrim. No pumpAndSettle: the row spinner
      // animates forever while the create is in flight.
      await tester.tapAt(const Offset(400, 20));
      await tester.pump();
      await tester.pump();

      expect(
        find.text('Cancel'),
        findsOneWidget,
        reason: 'the sheet stayed open',
      );
      expect(result, isNull, reason: 'nothing was created');
    },
  );
}
