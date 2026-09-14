/// Proves `agent_status.dart`'s session notification log (`docs/31-mockups/07-notifications.md`,
/// decided 2026-09-04): one entry per pane where the latest status wins (R-31-07-01), newest
/// first with a `null` time last (R-31-07-02), `markSeen`/`markAllSeen` flag an entry read and
/// keep it (R-31-07-03). Remove actions delete entries (R-31-07-04).
/// Tree state filters attention without deleting history (R-31-06-35).
/// Snapshots preserve read acknowledgements (R-30-513) and supply space names.
/// notification and announcement contracts; this file covers the log and its per-Host
/// switching isolation (R-03-046, R-30-946).
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart' show Ok;
import 'package:herdr_mobile/models/message.dart';
import 'package:herdr_mobile/models/messages/agent_status.dart';
import 'package:herdr_mobile/models/messages/agent_status_kind.dart';
import 'package:herdr_mobile/models/messages/agent_summary.dart';
import 'package:herdr_mobile/models/messages/mark_seen.dart';
import 'package:herdr_mobile/models/messages/pane_scroll_state.dart';
import 'package:herdr_mobile/models/messages/pane_summary.dart';
import 'package:herdr_mobile/models/messages/tab_summary.dart';
import 'package:herdr_mobile/models/messages/tree_event.dart';
import 'package:herdr_mobile/models/messages/tree_snapshot.dart';
import 'package:herdr_mobile/models/messages/tree_update.dart';
import 'package:herdr_mobile/models/messages/workspace_summary.dart';
import 'package:herdr_mobile/services/agent_status.dart';
import 'package:herdr_mobile/services/notifications.dart';
import 'package:herdr_mobile/services/plain_store.dart';
import 'package:herdr_mobile/services/relay.dart'
    show RelayConnected, RelayConnectionState;
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _MockNotificationsService extends Mock implements NotificationsService {}

AgentStatus _live({
  required String paneId,
  AgentStatusKind status = AgentStatusKind.done,
  String at = '2026-09-04T10:00:00Z',
  String workspaceId = 'w3',
  String hostId = 'host-1',
}) => AgentStatus(
  hostId: hostId,
  paneId: paneId,
  workspaceId: workspaceId,
  tabId: '$workspaceId:t1',
  tabTitle: 'impl',
  paneTitle: 'main.py',
  agentKind: 'claude',
  status: status,
  at: at,
);

TreeSnapshot _snapshot({
  required String paneId,
  required String status,
  String? statusAt,
  String? repoName,
  String workspaceName = 'feature/db-interface',
  String? spaceId,
  String? parentName,
}) => TreeSnapshot(
  workspaces: [
    if (parentName != null)
      WorkspaceSummary(
        workspaceId: spaceId ?? 'w1',
        name: parentName,
        focused: false,
      ),
    WorkspaceSummary(
      workspaceId: 'w3',
      name: workspaceName,
      focused: true,
      repoName: repoName,
      isLinkedWorktree: repoName != null || spaceId != null,
      spaceId: spaceId,
    ),
  ],
  tabs: const [
    TabSummary(tabId: 'w3:t1', workspaceId: 'w3', title: 'impl', focused: true),
  ],
  panes: [
    PaneSummary(
      paneId: paneId,
      workspaceId: 'w3',
      tabId: 'w3:t1',
      terminalId: 'term-1',
      label: '',
      title: 'main.py',
      cwd: '/repo',
      focused: true,
      agent: 'claude',
      agentStatus: status,
      revision: 1,
      scroll: const PaneScrollState(
        offsetFromBottom: 0,
        maxOffsetFromBottom: 0,
        viewportRows: 50,
      ),
    ),
  ],
  agents: [
    AgentSummary(
      agentKind: 'claude',
      paneId: paneId,
      status: status,
      statusAt: statusAt,
    ),
  ],
);

void main() {
  late StreamController<Message> messages;
  late _MockNotificationsService notifications;
  late PlainStore store;
  late AgentStatusService service;

  setUpAll(() => registerFallbackValue(_live(paneId: 'x')));

  AgentStatusService newService({void Function(Message)? send}) =>
      AgentStatusService(
        messages: messages.stream,
        notifications: notifications,
        plainStore: store,
        currentHostId: () => 'host-1',
        send: send,
      );

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    store = PlainStore();
    messages = StreamController<Message>.broadcast();
    notifications = _MockNotificationsService();
    when(() => notifications.postAgentStatusNotification(any()))
        .thenAnswer((_) async => const Ok(null));
    when(
      () => notifications.cancelAgentStatusNotification(
        hostId: any(named: 'hostId'),
        paneId: any(named: 'paneId'),
      ),
    ).thenAnswer((_) async => const Ok(null));
    service = newService();
  });

  tearDown(() async {
    service.dispose();
    await messages.close();
  });

  Future<void> send(AgentStatus status) async {
    messages.add(Message.agentStatus(status));
    await pumpEventQueue();
  }

  Future<void> snapshot(
    String paneId, {
    required String status,
    String? statusAt,
  }) async {
    messages.add(
      Message.treeSnapshot(
        _snapshot(paneId: paneId, status: status, statusAt: statusAt),
      ),
    );
    await pumpEventQueue();
  }

  test(
    'notePaneOpened clears locally before one mark_seen send (R-11-241)',
    () async {
      service.dispose();
      final sent = <Message>[];
      service = newService(
        send: (message) {
          expect(service.currentAttention, isEmpty);
          sent.add(message);
        },
      );
      await send(_live(paneId: 'pane'));
      expect(service.currentAttention, isNotEmpty);
      await service.notePaneOpened('pane');
      expect(sent, [const Message.markSeen(MarkSeen(paneId: 'pane'))]);
    },
  );

  test(
    'notePaneOpened sends for working and unknown panes (R-11-240)',
    () async {
      service.dispose();
      final sent = <Message>[];
      service = newService(send: sent.add);
      await snapshot('working', status: 'working');
      await service.notePaneOpened('working');
      await service.notePaneOpened('unknown');
      expect(sent, [
        const Message.markSeen(MarkSeen(paneId: 'working')),
        const Message.markSeen(MarkSeen(paneId: 'unknown')),
      ]);
    },
  );

  test(
    'markSeen sends once for done, working and unknown panes (R-11-240)',
    () async {
      service.dispose();
      final sent = <Message>[];
      service = newService(
        send: (message) {
          expect(service.currentAttention, isEmpty);
          sent.add(message);
        },
      );
      await snapshot('done', status: 'done');
      await service.markSeen('done');
      await snapshot('working', status: 'working');
      await service.markSeen('working');
      await service.markSeen('unknown');
      expect(sent, [
        const Message.markSeen(MarkSeen(paneId: 'done')),
        const Message.markSeen(MarkSeen(paneId: 'working')),
        const Message.markSeen(MarkSeen(paneId: 'unknown')),
      ]);
    },
  );

  test(
    'setOpenPane does not resend for the same open pane (R-11-241)',
    () async {
      service.dispose();
      final sent = <Message>[];
      service = newService(send: sent.add);
      service.setOpenPane('pane');
      service.setOpenPane('pane');
      expect(sent, [const Message.markSeen(MarkSeen(paneId: 'pane'))]);
      await pumpEventQueue();
    },
  );

  test('a null send hook still clears local attention (R-30-503)', () async {
    await send(_live(paneId: 'pane'));
    final result = service.notePaneOpened('pane');
    expect(service.currentAttention, isEmpty);
    expect(await result, isA<Ok<void>>());
  });

  test(
    'R-31-06-35: snapshots prune attention but preserve notification history',
    () async {
      await send(_live(paneId: 'w3:p1'));
      await send(_live(paneId: 'w3:p2'));
      final history = service.currentNotifications;
      final emissions = <List<AttentionItem>>[];
      final subscription = service.unseenAttention.listen(emissions.add);
      addTearDown(subscription.cancel);

      await snapshot('w3:p1', status: 'done');
      expect(service.currentAttention.map((item) => item.paneId), ['w3:p1']);
      await snapshot('w3:p1', status: 'working');
      expect(service.currentAttention, isEmpty);
      expect(emissions.last, isEmpty);
      expect(service.currentNotifications, history);
      verify(() => notifications.postAgentStatusNotification(any())).called(2);
    },
  );

  test(
    'R-31-06-35: tree updates prune attention without deleting history',
    () async {
      final tree = _snapshot(paneId: 'w3:p1', status: 'done');
      await send(_live(paneId: 'w3:p1'));
      final history = service.currentNotifications;
      for (final status in ['working', 'idle', 'unknown']) {
        messages.add(Message.treeSnapshot(tree));
        await pumpEventQueue();
        expect(service.currentAttention.single.paneId, 'w3:p1');
        messages.add(
          Message.treeUpdate(
            TreeUpdate(
              event: TreeEvent.paneAgentStatusChanged,
              pane: tree.panes.single.copyWith(agentStatus: status),
            ),
          ),
        );
        await pumpEventQueue();
        expect(service.currentAttention, isEmpty);
        expect(service.currentNotifications, history);
      }
      for (final update in [
        TreeUpdate(event: TreeEvent.paneClosed, pane: tree.panes.single),
        TreeUpdate(event: TreeEvent.tabClosed, tab: tree.tabs.single),
        TreeUpdate(
          event: TreeEvent.workspaceClosed,
          workspace: tree.workspaces.single,
        ),
      ]) {
        messages.add(Message.treeSnapshot(tree));
        await pumpEventQueue();
        messages.add(Message.treeUpdate(update));
        await pumpEventQueue();
        expect(service.currentAttention, isEmpty);
        expect(service.currentNotifications, history);
      }
      verify(() => notifications.postAgentStatusNotification(any())).called(1);
    },
  );

  test('an empty service has an empty log and emits nothing', () {
    expect(service.currentNotifications, isEmpty);
    expect(service.currentAttention, isEmpty);
  });

  test('one entry per pane; a later agent_status replaces it and the latest status wins '
      '(R-31-07-01)', () async {
    await send(_live(paneId: 'w3:p1', status: AgentStatusKind.blocked));
    await send(
      _live(
        paneId: 'w3:p1',
        status: AgentStatusKind.done,
        at: '2026-09-04T10:05:00Z',
      ),
    );

    expect(service.currentNotifications, hasLength(1));
    expect(
      service.currentNotifications.single.item.status,
      AgentStatusKind.done,
    );
    expect(service.currentNotifications.single.item.at, '2026-09-04T10:05:00Z');
    expect(service.currentNotifications.single.seen, isFalse);
  });

  test('the log orders newest first by `at`, and an entry with no time last '
      '(R-31-07-02)', () async {
    await send(_live(paneId: 'w3:p1', at: '2026-09-04T10:00:00Z'));
    messages.add(
      Message.treeSnapshot(
        _snapshot(paneId: 'w3:p9', status: 'blocked', statusAt: null),
      ),
    );
    await pumpEventQueue();
    await send(_live(paneId: 'w3:p2', at: '2026-09-04T11:00:00Z'));

    expect(
      service.currentNotifications.map((e) => e.item.paneId).toList(),
      <String>['w3:p2', 'w3:p1', 'w3:p9'],
    );
  });

  test('markSeen flags the entry read and keeps it in the log; unseenAttention drops it '
      '(R-31-07-03, R-30-503)', () async {
    final emitted = <List<NotificationItem>>[];
    final sub = service.notifications.listen(emitted.add);
    await send(_live(paneId: 'w3:p1'));
    await service.markSeen('w3:p1');
    await pumpEventQueue();
    await service.markSeen('w3:p1');

    expect(service.currentNotifications, hasLength(1));
    expect(service.currentNotifications.single.seen, isTrue);
    expect(service.currentAttention, isEmpty);
    expect(emitted, hasLength(2));
    await sub.cancel();
  });

  test('markSeen on a seen or unknown pane emits nothing', () async {
    await send(_live(paneId: 'w3:p1'));
    await service.markSeen('w3:p1');
    final emitted = <List<NotificationItem>>[];
    final sub = service.notifications.listen(emitted.add);

    await service.markSeen('w3:p1');
    await service.markSeen('nope');
    await pumpEventQueue();

    expect(emitted, isEmpty);
    await sub.cancel();
  });

  test('a new agent_status for a seen pane replaces the entry and makes it unseen again '
      '(R-31-07-01)', () async {
    await send(_live(paneId: 'w3:p1', status: AgentStatusKind.blocked));
    await service.markSeen('w3:p1');
    expect(service.currentAttention, isEmpty);

    await send(
      _live(
        paneId: 'w3:p1',
        status: AgentStatusKind.done,
        at: '2026-09-04T10:05:00Z',
      ),
    );

    expect(service.currentNotifications, hasLength(1));
    expect(service.currentNotifications.single.seen, isFalse);
    expect(service.currentAttention, hasLength(1));
    expect(service.currentAttention.single.status, AgentStatusKind.done);
  });

  test('a tree_snapshot never resurrects a seen entry (R-30-513)', () async {
    await send(_live(paneId: 'w3:p1', status: AgentStatusKind.blocked));
    await service.markSeen('w3:p1');

    messages.add(
      Message.treeSnapshot(
        _snapshot(
          paneId: 'w3:p1',
          status: 'blocked',
          statusAt: '2026-09-04T10:00:00Z',
        ),
      ),
    );
    await pumpEventQueue();

    expect(service.currentNotifications.single.seen, isTrue);
    expect(service.currentAttention, isEmpty);
  });

  test('markAllSeen flags every unseen entry, each once stored, and a second call emits '
      'nothing (R-31-07-03)', () async {
    await send(_live(paneId: 'w3:p1'));
    await send(_live(paneId: 'w3:p2', at: '2026-09-04T10:01:00Z'));
    final emitted = <List<NotificationItem>>[];
    final sub = service.notifications.listen(emitted.add);

    await service.markAllSeen();
    await pumpEventQueue();
    // Store-first: each row turns read as its own write lands, so the count of emissions is
    // incidental; the last emission and the current state are the contract.
    final int afterFirst = emitted.length;
    expect(afterFirst, greaterThanOrEqualTo(1));
    expect(emitted.last.every((e) => e.seen), isTrue);
    expect(service.currentNotifications.every((e) => e.seen), isTrue);
    expect(service.currentNotifications, hasLength(2));
    expect(service.currentAttention, isEmpty);

    await service.markAllSeen();
    await pumpEventQueue();
    expect(emitted, hasLength(afterFirst), reason: 'nothing left to mark');
    await sub.cancel();
  });

  test('remove drops one entry, seen or unseen, and is a no-op for an unknown pane '
      '(R-31-07-04)', () async {
    await send(_live(paneId: 'w3:p1'));
    await send(_live(paneId: 'w3:p2', at: '2026-09-04T10:01:00Z'));
    await service.markSeen('w3:p2');
    final emitted = <List<NotificationItem>>[];
    final sub = service.notifications.listen(emitted.add);

    await service.remove('w3:p2');
    await service.remove('w3:p1');
    await service.remove('nope');
    await pumpEventQueue();

    expect(emitted, hasLength(2));
    expect(service.currentNotifications, isEmpty);
    expect(service.currentAttention, isEmpty);
    await sub.cancel();
  });

  test('removeAll empties the log and the attention list, each row once stored, and a second '
      'call emits nothing (R-31-07-04)', () async {
    await send(_live(paneId: 'w3:p1'));
    await send(_live(paneId: 'w3:p2', at: '2026-09-04T10:01:00Z'));
    final emitted = <List<NotificationItem>>[];
    final sub = service.notifications.listen(emitted.add);

    await service.removeAll();
    await pumpEventQueue();
    final int afterFirst = emitted.length;
    expect(afterFirst, greaterThanOrEqualTo(1));
    expect(emitted.last, isEmpty);
    expect(service.currentNotifications, isEmpty);
    expect(service.currentAttention, isEmpty);

    await service.removeAll();
    await pumpEventQueue();
    expect(emitted, hasLength(afterFirst), reason: 'nothing left to remove');
    await sub.cancel();
  });

  test(
    'a removed pane earns a fresh unseen entry on its next live transition',
    () async {
      await send(_live(paneId: 'w3:p1'));
      await service.remove('w3:p1');

      await send(_live(paneId: 'w3:p1', at: '2026-09-04T10:09:00Z'));

      expect(service.currentNotifications, hasLength(1));
      expect(service.currentNotifications.single.seen, isFalse);
    },
  );

  test('notePaneOpened flags the entry seen and records the open', () async {
    await send(_live(paneId: 'w3:p1'));

    await service.notePaneOpened('w3:p1');

    expect(service.currentNotifications.single.seen, isTrue);
    verify(() => notifications.notePaneOpened('w3:p1')).called(1);
  });

  group('spaceName joins from the last tree_snapshot', () {
    test('a grouped workspace names its space by its parent workspace\'s name, never '
        'repo_name', () async {
      messages.add(
        Message.treeSnapshot(
          _snapshot(
            paneId: 'w3:p1',
            status: 'working',
            spaceId: 'w1',
            parentName: 'lightspeed-kit',
            // Deliberately stale: proves the parent name wins over `repo_name`.
            repoName: 'stale-repo-name',
          ),
        ),
      );
      await pumpEventQueue();

      await send(_live(paneId: 'w3:p1'));

      expect(
        service.currentNotifications.single.item.spaceName,
        'lightspeed-kit',
      );
    });

    test(
      'a workspace with no worktree is its own space, named by its label',
      () async {
        messages.add(
          Message.treeSnapshot(_snapshot(paneId: 'w3:p1', status: 'blocked')),
        );
        await pumpEventQueue();

        expect(
          service.currentNotifications.single.item.spaceName,
          'feature/db-interface',
        );
      },
    );

    test(
      'before any snapshot the space name is empty, never invented',
      () async {
        await send(_live(paneId: 'w3:p1'));

        expect(service.currentNotifications.single.item.spaceName, isEmpty);
      },
    );
  });

  test(
    'a snapshot carrying a newer transition for a tracked pane replaces the row unread '
    '(R-31-12-09: the snapshot is the only source while disconnected)',
    () async {
      await send(_live(paneId: 'w3:p1', status: AgentStatusKind.blocked));
      await service.markSeen('w3:p1');

      await snapshot('w3:p1', status: 'done', statusAt: '2026-09-04T10:05:00Z');

      expect(
        service.currentNotifications.single.item.status,
        AgentStatusKind.done,
      );
      expect(service.currentNotifications.single.seen, isFalse);
      verify(() => notifications.postAgentStatusNotification(any())).called(1);
    },
  );

  test('a repeat agent_status with an acknowledged identity posts no native alert, and remove '
      'cancels the alert (R-30-506, R-31-07-04)', () async {
    await send(_live(paneId: 'w3:p1'));
    await service.remove('w3:p1');
    await pumpEventQueue();

    await send(_live(paneId: 'w3:p1'));

    verify(() => notifications.postAgentStatusNotification(any())).called(1);
    verify(
      () => notifications.cancelAgentStatusNotification(
        hostId: 'host-1',
        paneId: 'w3:p1',
      ),
    ).called(1);
  });

  group('acknowledged identities (R-31-07-01, R-31-07-03, R-31-07-04)', () {
    test(
      'a tree_snapshot refresh after remove keeps the pane removed',
      () async {
        await send(_live(paneId: 'w3:p1', status: AgentStatusKind.blocked));
        await service.remove('w3:p1');

        await snapshot(
          'w3:p1',
          status: 'blocked',
          statusAt: '2026-09-04T10:00:00Z',
        );

        expect(service.currentNotifications, isEmpty);
        expect(service.currentAttention, isEmpty);
      },
    );

    test('a newer transition re-adds a removed pane unread, from a snapshot or live', () async {
      await send(_live(paneId: 'w3:p1', status: AgentStatusKind.blocked));
      await service.remove('w3:p1');

      await snapshot('w3:p1', status: 'done', statusAt: '2026-09-04T10:00:00Z');
      expect(service.currentNotifications.single.seen, isFalse);
      expect(
        service.currentNotifications.single.item.status,
        AgentStatusKind.done,
      );

      await service.remove('w3:p1');
      await send(
        _live(
          paneId: 'w3:p1',
          status: AgentStatusKind.done,
          at: '2026-09-04T10:07:00Z',
        ),
      );
      expect(service.currentNotifications.single.seen, isFalse);
      expect(
        service.currentNotifications.single.item.at,
        '2026-09-04T10:07:00Z',
      );
    });

    test(
      'a repeat agent_status with the acknowledged identity stays removed',
      () async {
        await send(_live(paneId: 'w3:p1'));
        await service.remove('w3:p1');

        await send(_live(paneId: 'w3:p1'));

        expect(service.currentNotifications, isEmpty);
      },
    );

    test('a reconnect snapshot after mark-all keeps every row read', () async {
      await send(_live(paneId: 'w3:p1', status: AgentStatusKind.blocked));
      await service.markAllSeen();
      // A reconnect rebuilds from the snapshot alone: a fresh service over the same store.
      service.dispose();
      service = newService();

      await snapshot(
        'w3:p1',
        status: 'blocked',
        statusAt: '2026-09-04T10:00:00Z',
      );

      expect(service.currentNotifications.single.seen, isTrue);
      expect(service.currentAttention, isEmpty);
    });

    test(
      'a fresh service over the same store starts with the removed state',
      () async {
        await send(_live(paneId: 'w3:p1'));
        await send(_live(paneId: 'w3:p2', at: '2026-09-04T10:01:00Z'));
        await service.remove('w3:p1');
        await service.markSeen('w3:p2');
        await pumpEventQueue();
        service.dispose();
        service = newService();

        await snapshot(
          'w3:p1',
          status: 'done',
          statusAt: '2026-09-04T10:00:00Z',
        );
        expect(service.currentNotifications, isEmpty);

        await send(_live(paneId: 'w3:p2', at: '2026-09-04T10:01:00Z'));
        expect(service.currentNotifications.single.seen, isTrue);
      },
    );

    test('forgetting the Host clears its acknowledgements', () async {
      await send(_live(paneId: 'w3:p1'));
      await service.remove('w3:p1');
      await pumpEventQueue();

      await store.removePairedHost('host-1');
      service.dispose();
      service = newService();
      await snapshot('w3:p1', status: 'done', statusAt: '2026-09-04T10:00:00Z');

      expect(service.currentNotifications.single.seen, isFalse);
    });

    test('acknowledgements are per Host', () async {
      await send(_live(paneId: 'w3:p1'));
      await service.remove('w3:p1');
      await pumpEventQueue();

      final acks = await store.notificationAcks('other-host');
      expect((acks as Ok<List<NotificationAck>>).value, isEmpty);
      final own = await store.notificationAcks('host-1');
      expect((own as Ok<List<NotificationAck>>).value.single.removed, isTrue);
    });
  });

  group('Host switching (per-Host log, R-03-046, R-30-946)', () {
    late String connectedHostId;
    late StreamController<RelayConnectionState> states;

    setUp(() {
      connectedHostId = 'host-1';
      states = StreamController<RelayConnectionState>.broadcast();
      // Replace the outer fixed-Host service with one whose connected Host can switch,
      // mirroring `routing.dart`'s `currentHostId` closure over `lastHostInfo`.
      service.dispose();
      service = AgentStatusService(
        messages: messages.stream,
        notifications: notifications,
        plainStore: store,
        currentHostId: () => connectedHostId,
        connectionState: states.stream,
      );
    });

    tearDown(() async {
      await states.close();
    });

    test('a snapshot queued across a Host switch keeps the Host it arrived on', () async {
      // A synchronous controller runs `_onMessage` inside `add`: the snapshot's turn is
      // queued while host-1 is connected, and the switch lands before that turn runs.
      final syncMessages = StreamController<Message>.broadcast(sync: true);
      final local = AgentStatusService(
        messages: syncMessages.stream,
        notifications: notifications,
        plainStore: store,
        currentHostId: () => connectedHostId,
      );
      syncMessages.add(
        Message.treeSnapshot(
          _snapshot(
            paneId: 'w3:p2',
            status: 'blocked',
            statusAt: '2026-09-04T10:00:00Z',
          ),
        ),
      );
      connectedHostId = 'host-2';
      await pumpEventQueue();

      expect(local.currentNotifications, isEmpty); // host-2 has no rows.
      connectedHostId = 'host-1';
      expect(local.currentNotifications.single.item.paneId, 'w3:p2');
      // The pane-closed cache is host-1's; host-2 has no snapshot state at all.
      expect(
        local.paneClosedSinceSnapshot(hostId: 'host-1', paneId: 'w3:zz'),
        isTrue,
      );
      expect(
        local.paneClosedSinceSnapshot(hostId: 'host-2', paneId: 'w3:p2'),
        isFalse,
      );
      local.dispose();
      await syncMessages.close();
    });

    test('identical pane ids on two Hosts stay independent; both Hosts\' rows survive '
        '(R-03-046)', () async {
      await send(_live(paneId: 'w3:p2', status: AgentStatusKind.blocked));
      await service.markSeen('w3:p2'); // acknowledged under host-1

      connectedHostId = 'host-2';
      expect(service.currentNotifications, isEmpty); // re-scoped at once

      // The same pane id with the same identity on host-2 has no acknowledgement there.
      await snapshot(
        'w3:p2',
        status: 'blocked',
        statusAt: '2026-09-04T10:00:00Z',
      );
      expect(service.currentNotifications.single.item.hostId, 'host-2');
      expect(service.currentNotifications.single.seen, isFalse);
      // host-1's read row is retained, not discarded; only host-2's is unseen.
      expect(service.currentAttention.single.hostId, 'host-2');

      connectedHostId = 'host-1';
      expect(service.currentNotifications.single.item.hostId, 'host-1');
      expect(service.currentNotifications.single.seen, isTrue);
    });

    test('a removal survives that Host\'s reconnect snapshot and never touches the other '
        'Host\'s identical pane; a newer event re-adds', () async {
      await send(_live(paneId: 'w3:p2')); // done @ 10:00 on host-1
      await service.remove('w3:p2');
      expect(service.currentNotifications, isEmpty);

      // host-1 reconnect: the same settled state arrives again — removed stays removed.
      await snapshot('w3:p2', status: 'done', statusAt: '2026-09-04T10:00:00Z');
      expect(service.currentNotifications, isEmpty);

      // host-2's identical pane id and identity is a different change entirely.
      await send(_live(hostId: 'host-2', paneId: 'w3:p2'));
      connectedHostId = 'host-2';
      expect(service.currentNotifications.single.item.hostId, 'host-2');
      expect(service.currentNotifications.single.seen, isFalse);

      // A genuinely newer transition on host-1 re-adds host-1's pane unread.
      connectedHostId = 'host-1';
      await send(_live(paneId: 'w3:p2', at: '2026-09-04T10:09:00Z'));
      expect(
        service.currentNotifications.single.item.at,
        '2026-09-04T10:09:00Z',
      );
      expect(service.currentNotifications.single.seen, isFalse);
    });

    test('one flush with two Hosts\' queued messages applies each Host\'s own stored '
        'acknowledgements', () async {
      // Pre-seed the store before the first message: host-1 removed this identity,
      // host-2 read it. The first queued turn per Host pays a real asynchronous store
      // read, serialised behind one another by the service's queue.
      await store.saveNotificationAck(
        const NotificationAck(
          hostId: 'host-1',
          paneId: 'w3:p2',
          status: 'done',
          at: '2026-09-04T10:00:00Z',
          removed: true,
        ),
      );
      await store.saveNotificationAck(
        const NotificationAck(
          hostId: 'host-2',
          paneId: 'w3:p2',
          status: 'blocked',
          at: '2026-09-04T10:00:00Z',
          removed: false,
        ),
      );

      // One flush, no pump in between: host-1's live event, then the switch, then
      // host-2's snapshot.
      messages.add(Message.agentStatus(_live(paneId: 'w3:p2')));
      connectedHostId = 'host-2';
      messages.add(
        Message.treeSnapshot(
          _snapshot(
            paneId: 'w3:p2',
            status: 'blocked',
            statusAt: '2026-09-04T10:00:00Z',
          ),
        ),
      );
      await pumpEventQueue();

      // host-1's removed identity stays absent; host-2's read identity comes back read.
      expect(service.currentNotifications.single.item.hostId, 'host-2');
      expect(service.currentNotifications.single.seen, isTrue);
      connectedHostId = 'host-1';
      expect(service.currentNotifications, isEmpty);
    });

    test('a Host switch emits the newly connected Host\'s log at connect, its empty state '
        'included; a same-Host reconnect emits nothing', () async {
      await send(_live(paneId: 'w3:p2', status: AgentStatusKind.blocked));
      final emitted = <List<NotificationItem>>[];
      final sub = service.notifications.listen(emitted.add);

      connectedHostId = 'host-2';
      states.add(const RelayConnected());
      await pumpEventQueue();
      // host-2's empty state reaches a listener mounted since before the switch, before
      // any host-2 message arrives.
      expect(emitted, hasLength(1));
      expect(emitted.single, isEmpty);

      // host-2's first snapshot changes no row and must not emit a second time…
      await snapshot('w3:p9', status: 'working');
      expect(emitted, hasLength(1));

      // …and a reconnect to the SAME Host emits nothing either.
      states.add(const RelayConnected());
      await pumpEventQueue();
      expect(emitted, hasLength(1));
      await sub.cancel();
    });

    test('space names join per Host: one workspace id on two computers keeps both names', () async {
      messages.add(
        Message.treeSnapshot(
          _snapshot(paneId: 'w3:p9', status: 'working', workspaceName: 'alpha'),
        ),
      );
      await pumpEventQueue();

      connectedHostId = 'host-2';
      messages.add(
        Message.treeSnapshot(
          _snapshot(paneId: 'w3:p9', status: 'working', workspaceName: 'beta'),
        ),
      );
      await pumpEventQueue();

      connectedHostId = 'host-1';
      await send(_live(paneId: 'w3:p1'));
      expect(service.currentNotifications.single.item.spaceName, 'alpha');

      connectedHostId = 'host-2';
      await send(_live(hostId: 'host-2', paneId: 'w3:p1'));
      expect(service.currentNotifications.single.item.spaceName, 'beta');
    });

    test('an announcement fires only for a transition on the open pane\'s own Host', () async {
      connectedHostId = 'host-2';
      service.setOpenPane('w3:p2');
      final events = <String>[];
      final sub = service.announcements.listen(events.add);

      // A late live event from the computer switched away from shares the pane id.
      await send(_live(paneId: 'w3:p2', status: AgentStatusKind.blocked));
      expect(events, isEmpty);

      await send(
        _live(
          hostId: 'host-2',
          paneId: 'w3:p2',
          status: AgentStatusKind.blocked,
        ),
      );
      expect(events, <String>['claude is blocked and waiting for you']);
      await sub.cancel();
    });
  });
}
