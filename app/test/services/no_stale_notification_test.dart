/// Proves `agent_status.dart`'s `AgentStatusService` (`WP-19-a`) follows R-30-513 and R-03-062
/// exactly: a `tree_snapshot` — the only message a relaunch or a reconnect can produce
/// (R-22-024) — never posts a system notification for the `blocked`/`done` agents it reports,
/// even though it does raise the in-app unseen-attention marker for them. Only a live
/// `agent_status` message posts a real notification. Also proves R-30-503 (amended 2026-09-11): a
/// marker clears when [AgentStatusService.markSeen] is called, or when a later snapshot reports the
/// pane's state has moved on; it never clears for any other reason, and the retirement of a marker
/// posts nothing. The `announcements` group proves the R-30-714/R-30-742
/// accessibility announcement (Phase 22): fires exactly once for a genuinely new live transition
/// on the currently open pane, never for a `tree_snapshot`, never for a pane that is not open,
/// and never twice for a repeat.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart' show Ok;
import 'package:herdr_mobile/models/message.dart';
import 'package:herdr_mobile/models/messages/agent_status.dart';
import 'package:herdr_mobile/models/messages/agent_status_kind.dart';
import 'package:herdr_mobile/models/messages/agent_summary.dart';
import 'package:herdr_mobile/models/messages/pane_scroll_state.dart';
import 'package:herdr_mobile/models/messages/pane_summary.dart';
import 'package:herdr_mobile/models/messages/tab_summary.dart';
import 'package:herdr_mobile/models/messages/tree_snapshot.dart';
import 'package:herdr_mobile/models/messages/workspace_summary.dart';
import 'package:herdr_mobile/services/agent_status.dart';
import 'package:herdr_mobile/services/notifications.dart';
import 'package:herdr_mobile/services/plain_store.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _MockNotificationsService extends Mock implements NotificationsService {
  _MockNotificationsService() {
    // The app icon badge mirror (R-22-020) fires on every emission; stub it once here.
    when(() => setBadgeCount(any())).thenAnswer((_) async {});
  }
}

AgentStatus _liveStatus({
  String paneId = 'w3:p2',
  AgentStatusKind status = AgentStatusKind.done,
}) => AgentStatus(
  hostId: 'host-1',
  paneId: paneId,
  workspaceId: 'w3',
  tabId: 'w3:t2',
  tabTitle: 'impl',
  paneTitle: 'main.py',
  agentKind: 'claude',
  status: status,
  at: '2026-08-24T14:32:05Z',
);

TreeSnapshot _snapshotWith({
  required String paneId,
  required String status,
  String? statusAt,
}) => TreeSnapshot(
  workspaces: const [
    WorkspaceSummary(workspaceId: 'w3', name: 'alpha', focused: true),
  ],
  tabs: const [
    TabSummary(tabId: 'w3:t2', workspaceId: 'w3', title: 'impl', focused: true),
  ],
  panes: [
    PaneSummary(
      paneId: paneId,
      workspaceId: 'w3',
      tabId: 'w3:t2',
      terminalId: 'term-1',
      label: '1',
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
  late AgentStatusService service;

  setUpAll(() {
    registerFallbackValue(_liveStatus());
  });

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
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
    service = AgentStatusService(
      messages: messages.stream,
      notifications: notifications,
      plainStore: PlainStore(),
      currentHostId: () => 'host-1',
    );
  });

  tearDown(() async {
    service.dispose();
    await messages.close();
  });

  test('a tree_snapshot with a blocked/done agent raises the in-app attention marker but posts '
      'no notification (R-30-513, R-03-062, R-22-024)', () async {
    final attention = service.unseenAttention.first;
    messages.add(
      Message.treeSnapshot(
        _snapshotWith(paneId: 'w3:p2', status: 'blocked', statusAt: null),
      ),
    );

    final items = await attention;
    expect(items, hasLength(1));
    expect(items.single.paneId, 'w3:p2');
    expect(items.single.status, AgentStatusKind.blocked);
    verifyNever(() => notifications.postAgentStatusNotification(any()));
  });

  test('a tree_snapshot with an idle/working/unknown agent raises no attention marker at all', () async {
    for (final status in ['idle', 'working', 'unknown']) {
      messages.add(
        Message.treeSnapshot(_snapshotWith(paneId: 'w3:p2', status: status)),
      );
    }
    await pumpEventQueue();

    expect(service.currentAttention, isEmpty);
    verifyNever(() => notifications.postAgentStatusNotification(any()));
  });

  test('a live agent_status message raises the attention marker AND posts exactly one real '
      'notification (the only path that may)', () async {
    final attention = service.unseenAttention.first;
    final status = _liveStatus(status: AgentStatusKind.done);
    messages.add(Message.agentStatus(status));

    final items = await attention;
    expect(items, hasLength(1));
    expect(items.single.paneId, status.paneId);
    verify(() => notifications.postAgentStatusNotification(status)).called(1);
  });

  test(
    'markSeen clears a marker that a tree_snapshot raised '
    '(R-30-503: opening the pane is the proof that the work was seen)',
    () async {
      messages.add(
        Message.treeSnapshot(
          _snapshotWith(paneId: 'w3:p2', status: 'done', statusAt: null),
        ),
      );
      await pumpEventQueue();
      expect(service.currentAttention, hasLength(1));

      await service.markSeen('w3:p2');
      expect(service.currentAttention, isEmpty);
    },
  );

  test('a later snapshot reporting the same pane back to "working" retires the marker on its own '
      'and posts nothing (R-30-503 amended 2026-09-11: a state that is over has nothing to mark)', () async {
    messages.add(
      Message.treeSnapshot(
        _snapshotWith(paneId: 'w3:p2', status: 'blocked', statusAt: null),
      ),
    );
    await pumpEventQueue();
    expect(service.currentAttention, hasLength(1));

    messages.add(
      Message.treeSnapshot(_snapshotWith(paneId: 'w3:p2', status: 'working')),
    );
    await pumpEventQueue();

    expect(service.currentAttention, isEmpty);
    verifyNever(() => notifications.postAgentStatusNotification(any()));
  });

  test(
    'notePaneOpened clears the marker and records the pane as opened',
    () async {
      messages.add(
        Message.treeSnapshot(
          _snapshotWith(paneId: 'w3:p2', status: 'done', statusAt: null),
        ),
      );
      await pumpEventQueue();
      expect(service.currentAttention, hasLength(1));

      await service.notePaneOpened('w3:p2');

      expect(service.currentAttention, isEmpty);
      verify(() => notifications.notePaneOpened('w3:p2')).called(1);
    },
  );

  group('announcements (R-30-714, R-30-742)', () {
    test('a live blocked/done transition on the currently open pane emits exactly the R-30-714 '
        'example sentence', () async {
      service.setOpenPane('w3:p2');
      final announcement = service.announcements.first;

      messages.add(
        Message.agentStatus(_liveStatus(status: AgentStatusKind.blocked)),
      );

      expect(await announcement, 'claude is blocked and waiting for you');
    });

    test(
      'a done transition on the open pane reads "<agent> is done"',
      () async {
        service.setOpenPane('w3:p2');
        final announcement = service.announcements.first;

        messages.add(
          Message.agentStatus(_liveStatus(status: AgentStatusKind.done)),
        );

        expect(await announcement, 'claude is done');
      },
    );

    test(
      'a live transition on a pane that is NOT open announces nothing',
      () async {
        service.setOpenPane('some-other-pane');
        final events = <String>[];
        final sub = service.announcements.listen(events.add);

        messages.add(Message.agentStatus(_liveStatus(paneId: 'w3:p2')));
        await pumpEventQueue();

        expect(events, isEmpty);
        await sub.cancel();
      },
    );

    test(
      'a tree_snapshot never announces, even for an agent on the open pane — the same '
      'R-30-513 reasoning that already excludes it from a notification',
      () async {
        service.setOpenPane('w3:p2');
        final events = <String>[];
        final sub = service.announcements.listen(events.add);

        messages.add(
          Message.treeSnapshot(
            _snapshotWith(paneId: 'w3:p2', status: 'blocked', statusAt: null),
          ),
        );
        await pumpEventQueue();

        expect(events, isEmpty);
        await sub.cancel();
      },
    );

    test('a repeat agent_status for a pane this service already tracks does not announce a '
        'second time', () async {
      service.setOpenPane('w3:p2');
      final events = <String>[];
      final sub = service.announcements.listen(events.add);

      messages.add(
        Message.agentStatus(_liveStatus(status: AgentStatusKind.blocked)),
      );
      await pumpEventQueue();
      messages.add(
        Message.agentStatus(_liveStatus(status: AgentStatusKind.blocked)),
      );
      await pumpEventQueue();

      expect(events, hasLength(1));
      await sub.cancel();
    });

    test('setOpenPane also runs notePaneOpened\'s effects: opening a pane that already carries '
        'a marker clears it, so a later new transition on that same pane can announce again', () async {
      messages.add(
        Message.treeSnapshot(
          _snapshotWith(paneId: 'w3:p2', status: 'blocked', statusAt: null),
        ),
      );
      await pumpEventQueue();
      expect(service.currentAttention, hasLength(1));

      service.setOpenPane('w3:p2');
      await pumpEventQueue();
      expect(service.currentAttention, isEmpty); // markSeen ran.
      verify(() => notifications.notePaneOpened('w3:p2')).called(1);

      final announcement = service.announcements.first;
      messages.add(
        Message.agentStatus(_liveStatus(status: AgentStatusKind.done)),
      );
      expect(await announcement, 'claude is done');
    });
  });
}
