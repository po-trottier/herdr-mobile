/// Tests `tree.dart` (`WP-18-c`): the `tree_request`/`tree_snapshot` read matched by type and
/// raced against a connection drop (mirroring `device_list_test.dart`'s own harness), the
/// `tree_update` join-and-apply logic (R-11-046), the pane display-name rule (R-31-07-10) and
/// the nullable `status_at` reader (R-11-224).
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart';
import 'package:herdr_mobile/models/codes.dart';
import 'package:herdr_mobile/models/message.dart';
import 'package:herdr_mobile/models/messages/agent_summary.dart';
import 'package:herdr_mobile/models/messages/error_message.dart';
import 'package:herdr_mobile/models/messages/pane_scroll_state.dart';
import 'package:herdr_mobile/models/messages/pane_summary.dart';
import 'package:herdr_mobile/models/messages/tab_summary.dart';
import 'package:herdr_mobile/models/messages/tree_event.dart';
import 'package:herdr_mobile/models/messages/tree_snapshot.dart';
import 'package:herdr_mobile/models/messages/tree_update.dart';
import 'package:herdr_mobile/models/messages/workspace_summary.dart';
import 'package:herdr_mobile/services/relay.dart';
import 'package:herdr_mobile/services/tree.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

const _scroll = PaneScrollState(
  offsetFromBottom: 0,
  maxOffsetFromBottom: 0,
  viewportRows: 50,
);

PaneSummary _pane({
  String paneId = 'w3:p2',
  String workspaceId = 'w3',
  String tabId = 'w3:t2',
  String label = '',
  String title = 'claude',
  String? agent = 'claude',
  String agentStatus = 'working',
}) => PaneSummary(
  paneId: paneId,
  workspaceId: workspaceId,
  tabId: tabId,
  terminalId: 'term_$paneId',
  label: label,
  title: title,
  cwd: '/home/user',
  focused: false,
  agent: agent,
  agentStatus: agentStatus,
  revision: 1,
  scroll: _scroll,
);

TreeSnapshot _sampleSnapshot() => TreeSnapshot(
  workspaces: const [
    WorkspaceSummary(workspaceId: 'w3', name: 'herdr-relay', focused: true),
  ],
  tabs: const [
    TabSummary(tabId: 'w3:t2', workspaceId: 'w3', title: 'impl', focused: true),
  ],
  panes: [_pane()],
  agents: const [
    AgentSummary(agentKind: 'claude', paneId: 'w3:p2', status: 'working'),
  ],
);

void main() {
  group('fetchTreeSnapshot', () {
    test('sends tree_request and resolves Ok on tree_snapshot', () async {
      final messages = StreamController<Message>.broadcast();
      final connectionState =
          StreamController<RelayConnectionState>.broadcast();
      final sent = <Message>[];

      final future = fetchTreeSnapshot(
        messages: messages.stream,
        connectionState: connectionState.stream,
        send: (message, {corr}) => sent.add(message),
      );
      await Future<void>.delayed(Duration.zero);
      expect(sent, hasLength(1));
      expect(sent.single, isA<MessageTreeRequest>());

      final snapshot = _sampleSnapshot();
      messages.add(Message.treeSnapshot(snapshot));

      final result = await future;
      expect(result, isA<Ok<TreeSnapshot>>());
      expect((result as Ok<TreeSnapshot>).value, snapshot);

      await messages.close();
      await connectionState.close();
    });

    test('resolves Err on an error reply', () async {
      final messages = StreamController<Message>.broadcast();
      final connectionState =
          StreamController<RelayConnectionState>.broadcast();

      final future = fetchTreeSnapshot(
        messages: messages.stream,
        connectionState: connectionState.stream,
        send: (message, {corr}) {},
      );
      messages.add(
        const Message.error(
          ErrorMessage(
            code: ErrorCode.internalError,
            message: 'boom',
            fatal: false,
          ),
        ),
      );

      final result = await future;
      expect(result, isA<Err<TreeSnapshot>>());
      expect((result as Err<TreeSnapshot>).message, 'boom');

      await messages.close();
      await connectionState.close();
    });

    test(
      'resolves Err when the connection drops before a reply arrives',
      () async {
        final messages = StreamController<Message>.broadcast();
        final connectionState =
            StreamController<RelayConnectionState>.broadcast();

        final future = fetchTreeSnapshot(
          messages: messages.stream,
          connectionState: connectionState.stream,
          send: (message, {corr}) {},
        );
        connectionState.add(const RelayDisconnected());

        final result = await future;
        expect(result, isA<Err<TreeSnapshot>>());

        await messages.close();
        await connectionState.close();
      },
    );
  });

  group('watchTreeUpdates', () {
    test('applies pane.updated by upserting the pane in place', () async {
      final messages = StreamController<Message>.broadcast();
      final initial = _sampleSnapshot();
      final updates = watchTreeUpdates(messages.stream, initial);
      final emitted = <TreeSnapshot>[];
      final sub = updates.listen(emitted.add);

      final updatedPane = _pane(agentStatus: 'blocked');
      messages.add(
        Message.treeUpdate(
          TreeUpdate(event: TreeEvent.paneUpdated, pane: updatedPane),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(emitted, hasLength(1));
      expect(emitted.single.panes, hasLength(1));
      expect(emitted.single.panes.single.agentStatus, 'blocked');

      await sub.cancel();
      await messages.close();
    });

    test('applies pane.closed by removing the pane', () async {
      final messages = StreamController<Message>.broadcast();
      final initial = _sampleSnapshot();
      final updates = watchTreeUpdates(messages.stream, initial);
      final emitted = <TreeSnapshot>[];
      final sub = updates.listen(emitted.add);

      messages.add(
        Message.treeUpdate(
          TreeUpdate(event: TreeEvent.paneClosed, pane: _pane()),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(emitted.single.panes, isEmpty);

      await sub.cancel();
      await messages.close();
    });

    test('adopts a later tree_snapshot wholesale', () async {
      final messages = StreamController<Message>.broadcast();
      final initial = _sampleSnapshot();
      final updates = watchTreeUpdates(messages.stream, initial);
      final emitted = <TreeSnapshot>[];
      final sub = updates.listen(emitted.add);

      const resync = TreeSnapshot(
        workspaces: [],
        tabs: [],
        panes: [],
        agents: [],
      );
      messages.add(const Message.treeSnapshot(resync));
      await Future<void>.delayed(Duration.zero);

      expect(emitted.single.workspaces, isEmpty);

      await sub.cancel();
      await messages.close();
    });

    test('ignores layout.updated', () async {
      final messages = StreamController<Message>.broadcast();
      final initial = _sampleSnapshot();
      final updates = watchTreeUpdates(messages.stream, initial);
      final emitted = <TreeSnapshot>[];
      final sub = updates.listen(emitted.add);

      messages.add(
        const Message.treeUpdate(TreeUpdate(event: TreeEvent.layoutUpdated)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(emitted, isEmpty);

      await sub.cancel();
      await messages.close();
    });
  });

  group('buildTree', () {
    test('joins workspaces, tabs and panes by id, preserving order', () {
      final snapshot = _sampleSnapshot();
      final tree = buildTree(snapshot);
      expect(tree, hasLength(1));
      expect(tree.single.workspace.name, 'herdr-relay');
      expect(tree.single.tabs, hasLength(1));
      expect(tree.single.tabs.single.panes, hasLength(1));
      expect(tree.single.paneCount, 1);
    });

    test('drops a tab whose workspace_id is missing from the snapshot', () {
      const snapshot = TreeSnapshot(
        workspaces: [],
        tabs: [
          TabSummary(
            tabId: 't1',
            workspaceId: 'missing',
            title: 'x',
            focused: false,
          ),
        ],
        panes: [],
        agents: [],
      );
      expect(buildTree(snapshot), isEmpty);
    });
  });

  group('paneDisplayName', () {
    test('uses label when non-empty', () {
      expect(paneDisplayName(_pane(label: 'claude')), 'claude');
    });

    test('falls back to pane plus the numeric suffix', () {
      expect(paneDisplayName(_pane(paneId: 'w3:p11')), 'pane 11');
    });

    test('falls back to pane plus a non-numeric suffix', () {
      expect(paneDisplayName(_pane(paneId: 'w3:pS')), 'pane S');
    });
  });

  group('agentStatusAt', () {
    test('returns null when the Host never observed the change', () {
      final snapshot = _sampleSnapshot();
      expect(agentStatusAt(snapshot, 'w3:p2'), isNull);
    });

    test('parses the timestamp when present', () {
      const snapshot = TreeSnapshot(
        workspaces: [],
        tabs: [],
        panes: [],
        agents: [
          AgentSummary(
            agentKind: 'claude',
            paneId: 'w3:p2',
            status: 'blocked',
            statusAt: '2026-08-27T00:00:00Z',
          ),
        ],
      );
      expect(agentStatusAt(snapshot, 'w3:p2'), isNotNull);
    });

    test('returns null for a pane with no agent entry at all', () {
      expect(agentStatusAt(_sampleSnapshot(), 'no-such-pane'), isNull);
    });
  });

  group('defaultTabExpanded', () {
    test('expanded at three tabs or fewer', () {
      expect(defaultTabExpanded(0), isTrue);
      expect(defaultTabExpanded(3), isTrue);
    });

    test('collapsed above three tabs', () {
      expect(defaultTabExpanded(4), isFalse);
    });
  });

  group('TreeExpansionStore', () {
    test('round-trips overrides per Host', () async {
      final backend = InMemorySharedPreferencesAsync.empty();
      SharedPreferencesAsyncPlatform.instance = backend;
      final store = TreeExpansionStore();

      await store.saveOverrides('host-1', {'w3': true, 'w3:t2': false});
      final loaded = await store.loadOverrides('host-1');
      expect(loaded, {'w3': true, 'w3:t2': false});
    });

    test('keeps two Hosts independent', () async {
      final backend = InMemorySharedPreferencesAsync.empty();
      SharedPreferencesAsyncPlatform.instance = backend;
      final store = TreeExpansionStore();

      await store.saveOverrides('host-1', {'w3': false});
      await store.saveOverrides('host-2', {'w3': true});

      expect(await store.loadOverrides('host-1'), {'w3': false});
      expect(await store.loadOverrides('host-2'), {'w3': true});
    });

    test('an id never toggled is absent from the loaded overrides', () async {
      final backend = InMemorySharedPreferencesAsync.empty();
      SharedPreferencesAsyncPlatform.instance = backend;
      final store = TreeExpansionStore();

      expect(await store.loadOverrides('fresh-host'), isEmpty);
    });
  });
}
