/// Tests `agent_list.dart` (`WP-18-b`): the `tree_request`/`tree_snapshot` read matched by
/// type and raced against a connection drop (mirroring `tree_test.dart`'s own harness), the
/// two-axis grouping (`docs/30-ux-spec.md` R-30-406 to R-30-414), the `NEEDS YOU` ordering
/// (R-31-06-02, R-31-06-25), the `Space > Worktree > Tab > Pane` hierarchy of the `Workspace`
/// axis with every pane listed (R-31-06-27, R-31-06-14, decided 2026-09-04 by the product
/// owner), its `space_id` grouping in the desktop's own order and per-tier counts (R-31-06-15,
/// R-31-06-28), the attention-first
/// sort inside a tab (R-30-409), the pane display-name rule (R-31-07-08), the age source rule
/// (R-30-405) and the per-Host axis/collapse persistence (R-31-06-12).
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart';
import 'package:herdr_mobile/models/codes.dart';
import 'package:herdr_mobile/models/message.dart';
import 'package:herdr_mobile/models/messages/agent_status_kind.dart';
import 'package:herdr_mobile/models/messages/agent_summary.dart';
import 'package:herdr_mobile/models/messages/error_message.dart';
import 'package:herdr_mobile/models/messages/pane_scroll_state.dart';
import 'package:herdr_mobile/models/messages/pane_summary.dart';
import 'package:herdr_mobile/models/messages/tab_summary.dart';
import 'package:herdr_mobile/models/messages/tree_event.dart';
import 'package:herdr_mobile/models/messages/tree_snapshot.dart';
import 'package:herdr_mobile/models/messages/tree_update.dart';
import 'package:herdr_mobile/models/messages/workspace_summary.dart';
import 'package:herdr_mobile/services/agent_list.dart';
import 'package:herdr_mobile/services/agent_status.dart' show AttentionItem;
import 'package:herdr_mobile/services/relay.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

const _scroll = PaneScrollState(
  offsetFromBottom: 0,
  maxOffsetFromBottom: 0,
  viewportRows: 50,
);

PaneSummary _pane({
  String paneId = 'w1:p2',
  String workspaceId = 'w1',
  String tabId = 'w1:t2',
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

TreeSnapshot _snapshotWith({
  List<WorkspaceSummary> workspaces = const [
    WorkspaceSummary(workspaceId: 'w1', name: 'herdr-relay', focused: true),
  ],
  List<TabSummary> tabs = const [
    TabSummary(tabId: 'w1:t2', workspaceId: 'w1', title: 'impl', focused: true),
  ],
  List<PaneSummary>? panes,
  List<AgentSummary>? agents,
}) => TreeSnapshot(
  workspaces: workspaces,
  tabs: tabs,
  panes: panes ?? [_pane()],
  agents:
      agents ??
      const [
        AgentSummary(agentKind: 'claude', paneId: 'w1:p2', status: 'working'),
      ],
);

AttentionItem _attention({
  String paneId = 'w1:p9',
  String workspaceId = 'w1',
  String tabId = 'w1:t2',
  String agentKind = 'codex',
  AgentStatusKind status = AgentStatusKind.blocked,
  String? at,
}) => AttentionItem(
  hostId: 'host-1',
  paneId: paneId,
  workspaceId: workspaceId,
  tabId: tabId,
  agentKind: agentKind,
  tabTitle: 'impl',
  paneTitle: 'codex terminal',
  status: status,
  at: at,
);

class _Harness {
  _Harness()
    : messages = StreamController<Message>.broadcast(),
      connectionState = StreamController<RelayConnectionState>.broadcast(),
      attention = StreamController<List<AttentionItem>>.broadcast(),
      sent = <Message>[];

  final StreamController<Message> messages;
  final StreamController<RelayConnectionState> connectionState;
  final StreamController<List<AttentionItem>> attention;
  final List<Message> sent;

  AgentListService build({
    List<AttentionItem> currentAttention = const <AttentionItem>[],
    String hostId = 'host-1',
  }) => AgentListService(
    messages: messages.stream,
    connectionState: connectionState.stream,
    send: (Message message, {String? corr}) => sent.add(message),
    unseenAttention: attention.stream,
    currentAttention: currentAttention,
    hostId: hostId,
    preferences: SharedPreferencesAsync(),
  );

  Future<void> dispose() async {
    await messages.close();
    await connectionState.close();
    await attention.close();
  }
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('refresh', () {
    test('sends tree_request and resolves Ok on tree_snapshot', () async {
      final harness = _Harness();
      final service = harness.build();
      addTearDown(() async {
        service.dispose();
        await harness.dispose();
      });

      final future = service.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(harness.sent, hasLength(1));
      expect(harness.sent.single, isA<MessageTreeRequest>());

      harness.messages.add(Message.treeSnapshot(_snapshotWith()));
      final result = await future;
      expect(result, isA<Ok<void>>());
      expect(service.hasLoaded, isTrue);
    });

    test('resolves Err on an error reply', () async {
      final harness = _Harness();
      final service = harness.build();
      addTearDown(() async {
        service.dispose();
        await harness.dispose();
      });

      final future = service.refresh();
      harness.messages.add(
        const Message.error(
          ErrorMessage(
            code: ErrorCode.internalError,
            message: 'boom',
            fatal: false,
          ),
        ),
      );
      final result = await future;
      expect(result, isA<Err<void>>());
      expect((result as Err<void>).message, 'boom');
      expect(service.hasLoaded, isFalse);
    });

    test(
      'resolves Err when the connection drops before a reply arrives',
      () async {
        final harness = _Harness();
        final service = harness.build();
        addTearDown(() async {
          service.dispose();
          await harness.dispose();
        });

        final future = service.refresh();
        harness.connectionState.add(const RelayDisconnected());
        final result = await future;
        expect(result, isA<Err<void>>());
      },
    );
  });

  group('Priority grouping', () {
    test(
      'NEEDS YOU orders blocked before done, oldest first, null-at last',
      () async {
        final harness = _Harness();
        final blockedOld = _attention(
          paneId: 'p-blocked-old',
          status: AgentStatusKind.blocked,
          at: '2026-01-01T00:00:00Z',
        );
        final blockedNew = _attention(
          paneId: 'p-blocked-new',
          status: AgentStatusKind.blocked,
          at: '2026-01-02T00:00:00Z',
        );
        final doneWithTime = _attention(
          paneId: 'p-done',
          status: AgentStatusKind.done,
          at: '2026-01-01T00:00:00Z',
        );
        final doneNoTime = _attention(
          paneId: 'p-done-no-time',
          status: AgentStatusKind.done,
        );
        final service = harness.build(
          currentAttention: [doneNoTime, doneWithTime, blockedNew, blockedOld],
        );
        addTearDown(() async {
          service.dispose();
          await harness.dispose();
        });
        // R-31-06-35: attention orders tree rows; it cannot create them.
        harness.messages.add(
          Message.treeSnapshot(
            _snapshotWith(
              panes: [
                _pane(paneId: blockedOld.paneId, agentStatus: 'blocked'),
                _pane(paneId: blockedNew.paneId, agentStatus: 'blocked'),
                _pane(paneId: doneWithTime.paneId, agentStatus: 'done'),
                _pane(paneId: doneNoTime.paneId, agentStatus: 'done'),
              ],
              agents: const [],
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final needsYou = service.currentView.prioritySections.firstWhere(
          (s) => s.title == 'NEEDS YOU',
        );
        expect(needsYou.rows.map((r) => r.paneId).toList(), [
          'p-blocked-old',
          'p-blocked-new',
          'p-done',
          'p-done-no-time',
        ]);
      },
    );

    test('WORKING/IDLE/UNKNOWN ignore stale attention', () async {
      final harness = _Harness();
      final service = harness.build(
        currentAttention: [
          _attention(paneId: 'p-work', status: AgentStatusKind.done),
          _attention(paneId: 'p-idle'),
          _attention(paneId: 'p-weird'),
        ],
      );
      addTearDown(() async {
        service.dispose();
        await harness.dispose();
      });

      harness.messages.add(
        Message.treeSnapshot(
          _snapshotWith(
            panes: [
              _pane(paneId: 'p-work', agentStatus: 'working'),
              _pane(paneId: 'p-idle', agentStatus: 'idle'),
              _pane(paneId: 'p-weird', agentStatus: 'something-new'),
            ],
            agents: const [],
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final view = service.currentView;
      final titles = view.prioritySections.map((s) => s.title).toSet();
      expect(titles, {'WORKING', 'IDLE', 'UNKNOWN'});
      expect(view.attentionCount, 0);
      expect(
        view.prioritySections
            .expand((section) => section.rows)
            .map((row) => row.needsAttention),
        everyElement(isFalse),
      );
      expect(
        view.prioritySections
            .firstWhere((s) => s.title == 'UNKNOWN')
            .rows
            .single
            .status,
        AgentStatusKind
            .unknown, // R-30-404: an unrecognised string is never `idle`.
      );
    });

    test('a live blocked pane not yet in the attention set still lands in NEEDS YOU', () async {
      final harness = _Harness();
      final service = harness.build();
      addTearDown(() async {
        service.dispose();
        await harness.dispose();
      });

      harness.messages.add(
        Message.treeSnapshot(
          _snapshotWith(
            panes: [_pane(paneId: 'p-blocked', agentStatus: 'blocked')],
            agents: const [
              AgentSummary(
                agentKind: 'claude',
                paneId: 'p-blocked',
                status: 'blocked',
              ),
            ],
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final needsYou = service.currentView.prioritySections.firstWhere(
        (s) => s.title == 'NEEDS YOU',
      );
      expect(needsYou.rows.single.paneId, 'p-blocked');
      expect(needsYou.rows.single.needsAttention, isFalse);
      expect(service.currentView.attentionCount, 0);
    });
  });

  group('tree authority (R-31-06-35)', () {
    test(
      'attention for a pane absent from the snapshot creates no row',
      () async {
        final harness = _Harness();
        final service = harness.build(currentAttention: [_attention()]);
        addTearDown(() async {
          service.dispose();
          await harness.dispose();
        });
        harness.messages.add(
          Message.treeSnapshot(_snapshotWith(panes: [], agents: const [])),
        );
        await Future<void>.delayed(Duration.zero);
        expect(service.currentView.prioritySections, isEmpty);
        expect(
          service.currentView.spaces.single.worktrees.single.tabs.single.rows,
          isEmpty,
        );
        expect(service.currentView.attentionCount, 0);
      },
    );

    test(
      'tree working replaces stale done and a snapshot removes the row',
      () async {
        final harness = _Harness();
        final service = harness.build(
          currentAttention: [
            _attention(paneId: 'w1:p2', status: AgentStatusKind.done),
          ],
        );
        addTearDown(() async {
          service.dispose();
          await harness.dispose();
        });
        harness.messages.add(
          Message.treeSnapshot(
            _snapshotWith(panes: [_pane(agentStatus: 'done')]),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(service.currentView.prioritySections.single.title, 'NEEDS YOU');
        harness.messages.add(
          Message.treeUpdate(
            TreeUpdate(
              event: TreeEvent.paneAgentStatusChanged,
              pane: _pane(agentStatus: 'working'),
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        final working = service.currentView.prioritySections.single;
        expect(working.title, 'WORKING');
        expect(working.rows.single.status, AgentStatusKind.working);
        expect(working.rows.single.needsAttention, isFalse);
        expect(service.currentView.attentionCount, 0);
        harness.messages.add(
          Message.treeSnapshot(_snapshotWith(panes: [], agents: const [])),
        );
        await Future<void>.delayed(Duration.zero);
        expect(service.currentView.prioritySections, isEmpty);
        expect(
          service.currentView.spaces.single.worktrees.single.tabs.single.rows,
          isEmpty,
        );
      },
    );

    test(
      'tree blocked keeps its state and names with the attention unread mark',
      () async {
        final harness = _Harness();
        final service = harness.build(
          currentAttention: [
            _attention(
              paneId: 'w1:p2',
              workspaceId: 'old-workspace',
              tabId: 'old-tab',
              agentKind: 'old-agent',
              status: AgentStatusKind.done,
            ),
          ],
        );
        addTearDown(() async {
          service.dispose();
          await harness.dispose();
        });
        harness.messages.add(
          Message.treeSnapshot(
            _snapshotWith(
              panes: [_pane(agentStatus: 'blocked', label: 'review')],
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        final section = service.currentView.prioritySections.single;
        final row = section.rows.single;
        expect(section.title, 'NEEDS YOU');
        expect(row.status, AgentStatusKind.blocked);
        expect(row.needsAttention, isTrue);
        expect(row.workspaceName, 'herdr-relay');
        expect(row.tabTitle, 'impl');
        expect(row.paneDisplayName, 'review');
        expect(row.agentKind, 'claude');
        expect(service.currentView.attentionCount, 1);
      },
    );
  });

  group('Workspace grouping', () {
    /// The measured Herdr shape of 2026-09-04 in the desktop sidebar's own terms (Herdr
    /// `src/ui/sidebar.rs` at `b1ff4582e968`): one repo with a main checkout and two linked
    /// worktrees, grouped by the Host under the parent's `space_id`, plus one workspace with no
    /// `worktree`. Herdr's own order is deliberately not alphabetical, and the group's first
    /// member comes before its parent, so any sorting would be observable.
    TreeSnapshot hierarchySnapshot() => TreeSnapshot(
      workspaces: const [
        WorkspaceSummary(workspaceId: 'w4', name: 'z-scratch', focused: false),
        WorkspaceSummary(
          workspaceId: 'w2',
          name: 'feature/db-interface',
          focused: false,
          spaceId: 'w1',
          repoName: 'lightspeed-kit',
          isLinkedWorktree: true,
        ),
        WorkspaceSummary(
          workspaceId: 'w1',
          name: 'lightspeed-kit',
          focused: true,
          spaceId: 'w1',
          repoName: 'lightspeed-kit',
        ),
        WorkspaceSummary(
          workspaceId: 'w3',
          name: 'asset_library',
          focused: false,
          spaceId: 'w1',
          repoName: 'lightspeed-kit',
          isLinkedWorktree: true,
        ),
      ],
      tabs: const [
        TabSummary(
          tabId: 'w1:t1',
          workspaceId: 'w1',
          title: 'impl',
          focused: true,
        ),
        TabSummary(
          tabId: 'w1:t2',
          workspaceId: 'w1',
          title: 'tests',
          focused: false,
        ),
        TabSummary(
          tabId: 'w2:t1',
          workspaceId: 'w2',
          title: 'api-server',
          focused: false,
        ),
        TabSummary(
          tabId: 'w3:t1',
          workspaceId: 'w3',
          title: 'shell',
          focused: false,
        ),
        TabSummary(
          tabId: 'w4:t1',
          workspaceId: 'w4',
          title: 'notes',
          focused: false,
        ),
      ],
      panes: [
        // Herdr order inside `impl`: the shell first, then the agent.
        _pane(
          paneId: 'w1:p1',
          tabId: 'w1:t1',
          agent: null,
          agentStatus: 'unknown',
          title: 'zsh',
        ),
        _pane(paneId: 'w1:p2', tabId: 'w1:t1', label: 'builder'),
        _pane(paneId: 'w1:p3', tabId: 'w1:t2', agentStatus: 'idle'),
        _pane(
          paneId: 'w2:p4',
          workspaceId: 'w2',
          tabId: 'w2:t1',
          agent: 'codex',
          agentStatus: 'blocked',
        ),
        // `asset_library` holds no agent at all.
        _pane(
          paneId: 'w3:p5',
          workspaceId: 'w3',
          tabId: 'w3:t1',
          agent: null,
          agentStatus: 'unknown',
          title: 'npm run dev',
        ),
        _pane(
          paneId: 'w4:p6',
          workspaceId: 'w4',
          tabId: 'w4:t1',
          agent: 'gemini',
          agentStatus: 'done',
        ),
      ],
      agents: const [],
    );

    Future<AgentListService> loaded(_Harness harness) async {
      final service = harness.build(
        currentAttention: [
          _attention(paneId: 'w2:p4', workspaceId: 'w2', tabId: 'w2:t1'),
          _attention(
            paneId: 'w4:p6',
            workspaceId: 'w4',
            tabId: 'w4:t1',
            status: AgentStatusKind.done,
          ),
        ],
      );
      addTearDown(() async {
        service.dispose();
        await harness.dispose();
      });
      harness.messages.add(Message.treeSnapshot(hierarchySnapshot()));
      await Future<void>.delayed(Duration.zero);
      return service;
    }

    test('groups by space_id where the first member stands, parent first, then Herdr order (R-31-06-27, R-31-06-15)', () async {
      final service = await loaded(_Harness());

      final spaces = service.currentView.spaces;
      // Herdr's order, not alphabetical: `z-scratch` stays first.
      expect(spaces.map((s) => s.name).toList(), [
        'z-scratch',
        'lightspeed-kit',
      ]);
      final group = spaces.last;
      expect(group.key, 'w1'); // The parent's own id, opaque.
      // The parent first, then the other members in Herdr's order (`w2` before `w3`, which
      // is not alphabetical either).
      expect(group.worktrees.map((w) => w.workspaceId).toList(), [
        'w1',
        'w2',
        'w3',
      ]);
      expect(group.worktrees.map((w) => w.name).toList(), [
        'lightspeed-kit',
        'feature/db-interface',
        'asset_library',
      ]);
    });

    test('the parent draws no worktree row under the header it names; the other members do', () async {
      final service = await loaded(_Harness());

      final group = service.currentView.spaces.last;
      expect(group.name, group.worktrees.first.name);
      expect(group.showsWorktreeRow(group.worktrees[0]), isFalse);
      expect(group.showsWorktreeRow(group.worktrees[1]), isTrue);
      expect(group.showsWorktreeRow(group.worktrees[2]), isTrue);
    });

    test('a workspace with no worktree is its own space, keyed by id, with no worktree row', () async {
      final service = await loaded(_Harness());

      final scratch = service.currentView.spaces.first;
      expect(scratch.key, 'w4');
      expect(scratch.name, 'z-scratch');
      expect(scratch.worktrees.single.workspaceId, 'w4');
      expect(scratch.showsWorktreeRow(scratch.worktrees.single), isFalse);
    });

    test('a lone linked worktree (space_id null) is its own space, named by its label, no worktree row', () async {
      final harness = _Harness();
      final service = harness.build();
      addTearDown(() async {
        service.dispose();
        await harness.dispose();
      });
      harness.messages.add(
        Message.treeSnapshot(
          _snapshotWith(
            workspaces: const [
              WorkspaceSummary(
                workspaceId: 'w1',
                name: 'feature/x',
                focused: true,
                repoName: 'herdr-relay',
                isLinkedWorktree: true,
              ),
            ],
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final space = service.currentView.spaces.single;
      expect(space.key, 'w1');
      expect(space.name, 'feature/x'); // Never `repo_name`.
      expect(space.showsWorktreeRow(space.worktrees.single), isFalse);
    });

    test('same-named repos never merge: repo_name groups nothing, only space_id does', () async {
      final harness = _Harness();
      final service = harness.build();
      addTearDown(() async {
        service.dispose();
        await harness.dispose();
      });
      harness.messages.add(
        Message.treeSnapshot(
          _snapshotWith(
            workspaces: const [
              // Two clones of one repo, each alone: the desktop lists both at the top level.
              WorkspaceSummary(
                workspaceId: 'w1',
                name: 'herdr',
                focused: true,
                repoName: 'herdr',
              ),
              WorkspaceSummary(
                workspaceId: 'w2',
                name: 'herdr (fork)',
                focused: false,
                repoName: 'herdr',
              ),
              // A linked-only repo: no non-linked parent, so the Host sends no `space_id`
              // and each worktree stands alone.
              WorkspaceSummary(
                workspaceId: 'w3',
                name: 'feature/a',
                focused: false,
                repoName: 'kit',
                isLinkedWorktree: true,
              ),
              WorkspaceSummary(
                workspaceId: 'w4',
                name: 'feature/b',
                focused: false,
                repoName: 'kit',
                isLinkedWorktree: true,
              ),
              // A second group of a same-named repo: its own parent, its own space.
              WorkspaceSummary(
                workspaceId: 'w5',
                name: 'herdr-main',
                focused: false,
                spaceId: 'w5',
                repoName: 'herdr',
              ),
              WorkspaceSummary(
                workspaceId: 'w6',
                name: 'feature/c',
                focused: false,
                spaceId: 'w5',
                repoName: 'herdr',
                isLinkedWorktree: true,
              ),
            ],
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final spaces = service.currentView.spaces;
      expect(spaces.map((s) => s.key).toList(), ['w1', 'w2', 'w3', 'w4', 'w5']);
      expect(spaces.map((s) => s.name).toList(), [
        'herdr',
        'herdr (fork)',
        'feature/a',
        'feature/b',
        'herdr-main',
      ]);
      for (final space in spaces.take(4)) {
        expect(space.showsWorktreeRow(space.worktrees.single), isFalse);
      }
      expect(spaces.last.worktrees.map((w) => w.name).toList(), [
        'herdr-main',
        'feature/c',
      ]);
    });

    test('lists every pane: a shell pane beside an agent pane, in Herdr order (R-31-06-14)', () async {
      final service = await loaded(_Harness());

      final impl = service.currentView.spaces.last.worktrees.first.tabs.first;
      expect(impl.title, 'impl');
      expect(impl.rows, hasLength(2));
      final shell = impl.rows.first as ShellRow;
      expect(shell.paneId, 'w1:p1');
      expect(shell.paneDisplayName, 'pane 1');
      expect(shell.title, 'zsh');
      final agent = impl.rows.last as AgentRow;
      expect(agent.paneDisplayName, 'builder');
      expect(agent.agentKind, 'claude');
    });

    test('a worktree with no agent at all stays on the Workspace axis and off Priority', () async {
      final service = await loaded(_Harness());
      final view = service.currentView;

      final assetLibrary = view.spaces.last.worktrees.last;
      expect(assetLibrary.name, 'asset_library');
      expect(assetLibrary.agentCount, 0);
      expect(assetLibrary.paneCount, 1);
      expect(assetLibrary.tabs.single.rows.single, isA<ShellRow>());
      // Priority lists agents only: the shell pane names no section.
      final priorityPaneIds = view.prioritySections
          .expand((s) => s.rows)
          .map((r) => r.paneId);
      expect(priorityPaneIds, isNot(contains('w3:p5')));
      expect(priorityPaneIds, isNot(contains('w1:p1')));
    });

    test(
      'counts roll up per tier: panes, agents, attention (R-31-06-28)',
      () async {
        final service = await loaded(_Harness());

        final space = service.currentView.spaces.last;
        expect(space.paneCount, 5);
        expect(space.agentCount, 3);
        expect(space.attentionCount, 1); // the live blocked `codex`, R-30-500.
        final main = space.worktrees.first;
        expect(
          (main.paneCount, main.agentCount, main.attentionCount),
          (3, 2, 0),
        );
        final tabTests = main.tabs.last;
        expect((tabTests.paneCount, tabTests.agentCount), (1, 1));
        final dbInterface = space.worktrees[1];
        expect((dbInterface.paneCount, dbInterface.attentionCount), (1, 1));
      },
    );

    test('a tab-less worktree is still listed (R-31-06-14)', () async {
      final harness = _Harness();
      final service = harness.build();
      addTearDown(() async {
        service.dispose();
        await harness.dispose();
      });
      harness.messages.add(
        Message.treeSnapshot(
          _snapshotWith(
            workspaces: const [
              WorkspaceSummary(
                workspaceId: 'w1',
                name: 'herdr-relay',
                focused: true,
                spaceId: 'w1',
                repoName: 'herdr-relay',
              ),
              WorkspaceSummary(
                workspaceId: 'w9',
                name: 'feature/empty',
                focused: false,
                spaceId: 'w1',
                repoName: 'herdr-relay',
                isLinkedWorktree: true,
              ),
            ],
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final space = service.currentView.spaces.single;
      expect(space.worktrees.map((w) => w.name).toList(), [
        'herdr-relay',
        'feature/empty',
      ]);
      expect(space.worktrees.last.tabs, isEmpty);
      expect(space.worktrees.last.paneCount, 0);
    });

    test('sorts an agent needing attention before one that does not, inside a tab (R-30-409)', () async {
      final harness = _Harness();
      final blocked = _attention(
        paneId: 'p-blocked',
        tabId: 'w1:t2',
        at: '2026-01-01T00:00:00Z',
      );
      final service = harness.build(currentAttention: [blocked]);
      addTearDown(() async {
        service.dispose();
        await harness.dispose();
      });

      harness.messages.add(
        Message.treeSnapshot(
          _snapshotWith(
            panes: [
              _pane(paneId: 'p-idle', tabId: 'w1:t2', agentStatus: 'idle'),
              _pane(
                paneId: 'p-blocked',
                tabId: 'w1:t2',
                agentStatus: 'blocked',
              ),
            ],
            agents: const [],
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final tab =
          service.currentView.spaces.single.worktrees.single.tabs.single;
      expect(tab.rows.map((r) => r.paneId).toList(), ['p-blocked', 'p-idle']);
    });

    group('search (R-31-06-30)', () {
      test('a pane match keeps its ancestors and drops its siblings', () async {
        final service = await loaded(_Harness());
        service.setSearch('  ZSH ');

        final view = service.currentView;
        expect(view.search, 'ZSH'); // Trimmed, case kept for the no-match line.
        final space = view.spaces.single;
        expect(space.name, 'lightspeed-kit');
        final worktree = space.worktrees.single;
        expect(worktree.name, 'lightspeed-kit');
        final tab = worktree.tabs.single;
        expect(tab.title, 'impl');
        expect(
          tab.rows.single.paneId,
          'w1:p1',
        ); // The shell whose title is `zsh`.
        // Counts follow what stays.
        expect((space.paneCount, space.agentCount), (1, 0));
      });

      test('matches the agent kind and the pane label', () async {
        final service = await loaded(_Harness());

        service.setSearch('codex');
        expect(
          service.currentView.spaces.single.worktrees.single.name,
          'feature/db-interface',
        );

        service.setSearch('build');
        final tab =
            service.currentView.spaces.single.worktrees.single.tabs.single;
        expect(tab.rows.single.paneDisplayName, 'builder');
      });

      test('a tab match keeps every pane of the tab', () async {
        final service = await loaded(_Harness());
        service.setSearch('impl');

        final tab =
            service.currentView.spaces.single.worktrees.single.tabs.single;
        expect(tab.rows, hasLength(2));
      });

      test(
        'a worktree match keeps its whole subtree; the space stays',
        () async {
          final service = await loaded(_Harness());
          service.setSearch('asset');

          final space = service.currentView.spaces.single;
          expect(space.name, 'lightspeed-kit');
          expect(space.worktrees.single.name, 'asset_library');
          expect(space.worktrees.single.tabs.single.rows, hasLength(1));
          // Narrowed to one non-parent member, the space still draws that member's worktree row.
          expect(space.showsWorktreeRow(space.worktrees.single), isTrue);
        },
      );

      test(
        'a space match keeps every worktree, tab and pane under it',
        () async {
          final service = await loaded(_Harness());
          service.setSearch('lightspeed');

          final spaces = service.currentView.spaces;
          expect(spaces.map((s) => s.name).toList(), ['lightspeed-kit']);
          expect(spaces.single.worktrees, hasLength(3));
          expect(spaces.single.paneCount, 5);
        },
      );

      test('a workspace with no worktree is found by its label', () async {
        final service = await loaded(_Harness());
        service.setSearch('scratch');

        expect(service.currentView.spaces.single.name, 'z-scratch');
      });

      test(
        'no match empties the spaces but never the view (no false empty state)',
        () async {
          final service = await loaded(_Harness());
          service.setSearch('nothing-here');

          final view = service.currentView;
          expect(view.spaces, isEmpty);
          expect(view.workspaceCount, 4);
          expect(view.isEmpty, isFalse);
          expect(
            view.prioritySections,
            isNotEmpty,
          ); // Priority is never narrowed.
        },
      );

      test('clearing the search shows the whole tree again, and it is not persisted', () async {
        final harness = _Harness();
        final service = await loaded(harness);
        service.setSearch('zsh');
        expect(service.currentView.spaces.single.paneCount, 1);

        service.setSearch('');
        expect(service.search, '');
        expect(service.currentView.spaces, hasLength(2));
        expect(service.currentView.spaces.last.paneCount, 5);

        service.setSearch('zsh');
        final harnessB = _Harness();
        final serviceB = await loaded(harnessB);
        expect(
          serviceB.search,
          '',
        ); // Session-scoped: a fresh instance starts clean.
      });
    });

    test(
      'a fresh tree_snapshot after a create adds the new tab and pane with search and collapse '
      'state untouched (no tree_update reached the phone, 2026-09-08)',
      () async {
        final harness = _Harness();
        final service = await loaded(harness);
        await service.toggleCollapsed('w4'); // `z-scratch` closed.
        service.setSearch('lightspeed');
        expect(service.currentView.spaces.single.paneCount, 5);

        // The create acknowledgement arrived and routing re-read the tree; the Host sent no
        // `tree_update` (its event subscription opens only once a pane is watched).
        final TreeSnapshot before = hierarchySnapshot();
        harness.messages.add(
          Message.treeSnapshot(
            TreeSnapshot(
              workspaces: before.workspaces,
              tabs: [
                ...before.tabs,
                const TabSummary(
                  tabId: 'w1:t9',
                  workspaceId: 'w1',
                  title: 'new-tab',
                  focused: true,
                ),
              ],
              panes: [
                ...before.panes,
                _pane(
                  paneId: 'w1:p9',
                  tabId: 'w1:t9',
                  agent: null,
                  agentStatus: 'unknown',
                  title: 'zsh',
                ),
              ],
              agents: before.agents,
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final view = service.currentView;
        expect(view.search, 'lightspeed');
        expect(view.collapsed, contains('w4'));
        final space = view.spaces.single;
        expect(space.paneCount, 6);
        final main = space.worktrees.first;
        expect(main.tabs.map((t) => t.title).toList(), [
          'impl',
          'tests',
          'new-tab',
        ]);
        expect(main.tabs.last.rows.single.paneId, 'w1:p9');
      },
    );
  });

  group('pane display name (R-31-07-08)', () {
    test('uses label when non-empty', () async {
      final harness = _Harness();
      final service = harness.build();
      addTearDown(() async {
        service.dispose();
        await harness.dispose();
      });
      harness.messages.add(
        Message.treeSnapshot(_snapshotWith(panes: [_pane(label: 'my-pane')])),
      );
      await Future<void>.delayed(Duration.zero);
      final row = service.currentView.prioritySections.single.rows.single;
      expect(row.paneDisplayName, 'my-pane');
    });

    test('falls back to pane plus the numeric suffix', () async {
      final harness = _Harness();
      final service = harness.build();
      addTearDown(() async {
        service.dispose();
        await harness.dispose();
      });
      harness.messages.add(
        Message.treeSnapshot(_snapshotWith(panes: [_pane(paneId: 'w1:p11')])),
      );
      await Future<void>.delayed(Duration.zero);
      final row = service.currentView.prioritySections.single.rows.single;
      expect(row.paneDisplayName, 'pane 11');
    });
  });

  group('age (R-30-405)', () {
    test('a status_at from the snapshot is used as the age source', () async {
      final harness = _Harness();
      final service = harness.build();
      addTearDown(() async {
        service.dispose();
        await harness.dispose();
      });
      harness.messages.add(
        Message.treeSnapshot(
          _snapshotWith(
            agents: const [
              AgentSummary(
                agentKind: 'claude',
                paneId: 'w1:p2',
                status: 'working',
                statusAt: '2026-01-01T00:00:00Z',
              ),
            ],
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final row = service.currentView.prioritySections.single.rows.single;
      expect(row.at, '2026-01-01T00:00:00Z');
    });

    test('a tree_update status change clears the age: no permitted timestamp source', () async {
      final harness = _Harness();
      final service = harness.build();
      addTearDown(() async {
        service.dispose();
        await harness.dispose();
      });
      harness.messages.add(
        Message.treeSnapshot(
          _snapshotWith(
            agents: const [
              AgentSummary(
                agentKind: 'claude',
                paneId: 'w1:p2',
                status: 'working',
                statusAt: '2026-01-01T00:00:00Z',
              ),
            ],
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      harness.messages.add(
        Message.treeUpdate(
          TreeUpdate(
            event: TreeEvent.paneAgentStatusChanged,
            pane: _pane(agentStatus: 'idle'),
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final row = service.currentView.prioritySections.single.rows.single;
      expect(row.status, AgentStatusKind.idle);
      expect(row.at, isNull); // R-30-405: never invented, never substituted.
    });
  });

  group('per-Host persistence (R-31-06-12)', () {
    test('round-trips the axis and the collapse state per Host', () async {
      final harnessA = _Harness();
      final serviceA = harnessA.build(hostId: 'host-a');
      await Future<void>.delayed(Duration.zero);
      await serviceA.setAxis(AgentListAxis.workspace);
      await serviceA.toggleCollapsed('w1');
      serviceA.dispose();
      await harnessA.dispose();

      final harnessB = _Harness();
      final serviceB = harnessB.build(hostId: 'host-a');
      addTearDown(() async {
        serviceB.dispose();
        await harnessB.dispose();
      });
      await Future<void>.delayed(Duration.zero);

      expect(serviceB.axis, AgentListAxis.workspace);
      expect(serviceB.isCollapsed('w1'), isTrue);
    });

    test(
      'a different Host starts with the default axis and no collapse state',
      () async {
        final harnessA = _Harness();
        final serviceA = harnessA.build(hostId: 'host-a');
        await Future<void>.delayed(Duration.zero);
        await serviceA.setAxis(AgentListAxis.workspace);
        serviceA.dispose();
        await harnessA.dispose();

        final harnessC = _Harness();
        final serviceC = harnessC.build(hostId: 'host-c');
        addTearDown(() async {
          serviceC.dispose();
          await harnessC.dispose();
        });
        await Future<void>.delayed(Duration.zero);

        expect(serviceC.axis, AgentListAxis.priority);
        expect(serviceC.isCollapsed('w1'), isFalse);
      },
    );
  });
}
