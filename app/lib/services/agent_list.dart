/// The agent list's own local tree state, its two-axis grouping, and its per-Host persistence
/// (Phase 18, `WP-18-b`, `docs/90-implementation-plan.md` §5.2). `agent_list_screen.dart` reads
/// [AgentListService.view] to draw `/hosts/:hostId/agents` (`docs/31-mockups/06-agent-list.md`,
/// `docs/30-ux-spec.md` R-30-406 to R-30-414, R-30-500 to R-30-513).
///
/// This file keeps its own `tree_snapshot`/`tree_update` state (R-11-043 to R-11-047) rather than
/// reading `WP-18-c`'s `tree.dart`: this package's `Needs.` line names only `WP-18-a` and
/// `WP-19-a`'s declarations (`docs/90` §5.2), so it cannot depend on a sibling wave-9 package's
/// own tree consumer. Its tree state is its own, not a shared cache to invalidate.
///
/// **The `Workspace` axis is the Herdr desktop sidebar's hierarchy** (decided 2026-09-04 by the
/// product owner, R-31-06-27): `Space > Worktree > Tab > Pane`, over the whole tree. With the
/// pane tree screen gone, this axis is the only browser for every pane, so it lists a pane with
/// no agent too, as a [ShellRow] (R-31-06-14); `Priority` stays agents-only. A space is one
/// top-level entry of the desktop sidebar (Herdr `src/ui/sidebar.rs` at `b1ff4582e968`,
/// `workspace_list_entries`), which the Host reports as `WorkspaceSummary.spaceId` (R-11-044,
/// decided 2026-09-08 by the product owner): the workspaces that share a `spaceId` form one
/// space, keyed and named by the parent workspace that `spaceId` names, and a workspace with
/// `spaceId == null` is its own space, keyed by its id and named by its label. Nothing here
/// groups by `repo_name`, and nothing sorts: spaces stand where their first member stands in
/// Herdr's own order, the parent stands first inside its space, and the other members keep
/// Herdr's order. A worktree is the Herdr workspace itself. The parent's tabs sit directly
/// under the space header, because a worktree row for it would only repeat the header's own
/// name ([SpaceGroup.showsWorktreeRow]); so do a lone workspace's. The axis also carries the
/// pane search the tree screen used to hold (R-31-06-30, decided 2026-09-08):
/// [AgentListService.setSearch] narrows the built hierarchy by name, and
/// [AgentListView.workspaceCount] keeps the `Empty` state honest while a search matches nothing.
///
/// R-31-06-35: the tree supplies every row and its current state. Tree panes
/// with `blocked` or `done` status belong in `NEEDS YOU`, including read rows.
/// Attention supplies unread marks and ordering only for those panes.
///
/// R-30-405: age comes from `agents[].status_at` or a live attention event's `at`.
/// A status change in `tree_update` clears the snapshot age because it has no
/// timestamp. A later snapshot can restore it.
library;

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/result/result.dart' show Err, Ok, Result;
import '../models/message.dart';
import '../models/messages/agent_status_kind.dart';
import '../models/messages/pane_summary.dart';
import '../models/messages/tab_summary.dart';
import '../models/messages/tree_event.dart';
import '../models/messages/tree_request.dart';
import '../models/messages/tree_snapshot.dart';
import '../models/messages/tree_update.dart';
import '../models/messages/workspace_summary.dart';
import 'agent_status.dart' show AttentionItem;
import 'relay.dart' show RelayConnected, RelayConnectionState;

/// Sends one application [Message], optionally correlated by [corr]. Matches
/// `RelayConnection.send`'s exact signature (`relay.dart`, `WP-14-a`), the same seam
/// `terminal.dart`'s `TerminalMessageSender` and `device_list.dart`'s `SendFrame` already use, so
/// a caller passes `connection.send` directly.
typedef AgentListMessageSender = void Function(Message message, {String? corr});

/// The two grouping axes of R-30-406, in the fixed order the segmented control shows them.
enum AgentListAxis { priority, workspace }

/// One pane row. `Priority` grouping lists [AgentRow]s only; `Workspace` grouping lists every
/// pane of the tree (decided 2026-09-04 by the product owner, R-31-06-14), so it also lists a
/// [ShellRow] for a pane that holds no agent.
sealed class PaneRow {
  const PaneRow({
    required this.paneId,
    required this.workspaceId,
    required this.tabId,
    required this.paneDisplayName,
    required this.title,
  });

  final String paneId;
  final String workspaceId;
  final String tabId;

  /// The pane's display name (callout 7 of `docs/31-mockups/06-agent-list.md`): `label` when
  /// non-empty, else `pane <suffix>` derived from [paneId], per R-31-07-08.
  final String paneDisplayName;

  /// The pane's `title`, the command Herdr reports for it; may be empty. A [ShellRow] draws it;
  /// an [AgentRow] never does, but the search of R-31-06-30 matches it on both.
  final String title;
}

/// One agent row, axis-independent. `agent_list_screen.dart` builds the breadcrumb text itself,
/// because R-31-06-18 draws a different breadcrumb per axis from the same fields. The raw
/// `title`/command field is never displayed for an agent pane.
final class AgentRow extends PaneRow {
  const AgentRow({
    required super.paneId,
    required super.workspaceId,
    required this.workspaceName,
    required super.tabId,
    required this.tabTitle,
    required super.paneDisplayName,
    required super.title,
    required this.agentKind,
    required this.status,
    required this.at,
    required this.needsAttention,
  });

  final String workspaceName;
  final String tabTitle;

  /// For example `claude` or `codex`.
  final String agentKind;

  final AgentStatusKind status;

  /// RFC 3339 UTC, or `null` when no permitted source (see this file's own header doc) has one.
  final String? at;

  /// The unread mark from attention, only while the tree reports blocked or done
  /// (R-30-500, R-30-501, R-31-06-35). Section membership does not require this mark.
  final bool needsAttention;
}

/// One pane with no agent, `Workspace` grouping only (R-31-06-14): a shell. It draws its
/// display name and its [title], carries no status and never needs attention.
final class ShellRow extends PaneRow {
  const ShellRow({
    required super.paneId,
    required super.workspaceId,
    required super.tabId,
    required super.paneDisplayName,
    required super.title,
  });
}

/// One `Priority`-grouping section: `NEEDS YOU`, `WORKING`, `IDLE` or `UNKNOWN`. Already sorted
/// per R-31-06-02/R-31-06-25. [AgentListService] omits an empty section, per R-90-010's "hiding
/// an empty section with its header".
final class PrioritySection {
  const PrioritySection({required this.title, required this.rows});
  final String title;
  final List<AgentRow> rows;
}

/// Tier 3 of `Workspace` grouping (R-31-06-27): one tab under a worktree, with every pane it
/// holds (R-31-06-14), so it may hold no agent at all. Every tier carries the three counts of
/// R-31-06-28: panes, agents among them, and agents that need attention among those.
final class TabGroup {
  TabGroup({required this.tabId, required this.title, required this.rows})
    : agentCount = rows.whereType<AgentRow>().length,
      attentionCount = rows
          .whereType<AgentRow>()
          .where((AgentRow row) => row.needsAttention)
          .length;
  final String tabId;
  final String title;

  /// Attention first (R-30-409, R-31-06-15), then Herdr's own pane order.
  final List<PaneRow> rows;
  int get paneCount => rows.length;
  final int agentCount;
  final int attentionCount;
}

/// Tier 2 of `Workspace` grouping (R-31-06-27): one Herdr workspace, drawn under its space as a
/// worktree. It may hold no tab yet (R-31-06-14).
final class WorktreeGroup {
  WorktreeGroup({
    required this.workspaceId,
    required this.name,
    required this.tabs,
  }) : paneCount = tabs.fold(0, (int n, TabGroup tab) => n + tab.paneCount),
       agentCount = tabs.fold(0, (int n, TabGroup tab) => n + tab.agentCount),
       attentionCount = tabs.fold(
         0,
         (int n, TabGroup tab) => n + tab.attentionCount,
       );
  final String workspaceId;

  /// The workspace's own `label`.
  final String name;

  /// Herdr's own tab order.
  final List<TabGroup> tabs;
  final int paneCount;
  final int agentCount;
  final int attentionCount;
}

/// Tier 1 of `Workspace` grouping (R-31-06-27): one top-level entry of the desktop sidebar, a
/// group of workspaces that share a `spaceId` or a lone workspace. [attentionCount] drives the
/// collapsed-header badge of R-31-06-16.
final class SpaceGroup {
  SpaceGroup({required this.key, required this.name, required this.worktrees})
    : paneCount = worktrees.fold(
        0,
        (int n, WorktreeGroup worktree) => n + worktree.paneCount,
      ),
      agentCount = worktrees.fold(
        0,
        (int n, WorktreeGroup worktree) => n + worktree.agentCount,
      ),
      attentionCount = worktrees.fold(
        0,
        (int n, WorktreeGroup worktree) => n + worktree.attentionCount,
      );

  /// The `spaceId` its members share, which is the parent workspace's id, or the workspace id of
  /// a lone workspace. The collapse state of R-31-06-12 persists under this key. Opaque: when
  /// the desktop dissolves or re-parents a group, the key changes with it.
  final String key;

  /// The parent workspace's own `label`, or the lone workspace's.
  final String name;

  /// The parent first, then the other members in Herdr's own order (R-31-06-15). Never empty: a
  /// space exists only because a workspace names it.
  final List<WorktreeGroup> worktrees;
  final int paneCount;
  final int agentCount;
  final int attentionCount;

  /// R-31-06-27: the parent's tabs (and a lone workspace's) sit directly under the space header;
  /// only another member draws its own worktree row.
  bool showsWorktreeRow(WorktreeGroup worktree) => worktree.workspaceId != key;
}

/// One published snapshot of the whole screen's data (R-31-06-12: axis and collapse state
/// persist per Host, so a fresh [AgentListService] instance re-reads them before the first
/// [AgentListService.currentView] a caller may read).
final class AgentListView {
  const AgentListView({
    required this.axis,
    required this.prioritySections,
    required this.spaces,
    required this.search,
    required this.workspaceCount,
    required this.attentionCount,
    required this.collapsed,
  });

  final AgentListAxis axis;
  final List<PrioritySection> prioritySections;

  /// `Workspace` grouping, in the desktop sidebar's own order (R-31-06-15) and narrowed to
  /// [search] (R-31-06-30). Every workspace of the tree is here while [search] is empty.
  final List<SpaceGroup> spaces;

  /// The `Workspace` axis search text, trimmed; `''` when none (R-31-06-30). Session-scoped:
  /// never persisted.
  final String search;

  /// How many workspaces the tree holds before [search] narrows it: the `Workspace` axis is
  /// empty only when this is zero, never because a search matched nothing.
  final int workspaceCount;

  /// R-30-501 / R-30-508: the exact, uncapped `blocked` + `done` count for the connected
  /// computer. The `Notifications` destination badge shows it; this screen's app bar no longer
  /// does (decided 2026-09-04 by the product owner).
  final int attentionCount;

  /// Which [SpaceGroup.key]s are collapsed right now (`Workspace` grouping only).
  final Set<String> collapsed;

  /// True once a `tree_snapshot` has arrived and it named zero agents and zero workspaces
  /// (R-90-011's `Empty` state), whatever [search] holds. Distinguishing "no agents yet" from
  /// "not loaded yet" is [AgentListService.hasLoaded]'s job, not this type's: a view is a data
  /// snapshot, not a phase.
  bool get isEmpty => prioritySections.isEmpty && workspaceCount == 0;
}

/// The Device's local agent-list state for one connected computer: independent tree tracking
/// from `tree_snapshot`/`tree_update`, the two-axis grouping of `docs/30-ux-spec.md` R-30-406,
/// and the per-Host persistence of R-30-407/R-31-06-12. See this file's own header doc for the
/// full contract. One instance per connected computer — `agent_list_screen.dart` constructs and
/// disposes one per mount, per R-31-06-26 ("on a switch the list MUST rebuild... MUST NOT carry
/// a row, count or marker across").
class AgentListService {
  AgentListService({
    required Stream<Message> messages,
    required Stream<RelayConnectionState> connectionState,
    required AgentListMessageSender send,
    required Stream<List<AttentionItem>> unseenAttention,
    required List<AttentionItem> currentAttention,
    required String hostId,
    SharedPreferencesAsync? preferences,
    // `this._send`/`this._hostId` would make the external parameter names private and
    // unusable from `agent_list_test.dart`, a different library (Dart's named-parameter
    // privacy rule) — the same reasoning `agent_status.dart`'s own constructor documents.
    // ignore: prefer_initializing_formals
  }) : _send = send,
       _attention = List<AttentionItem>.of(currentAttention),
       // ignore: prefer_initializing_formals
       _hostId = hostId,
       _preferences = preferences ?? SharedPreferencesAsync() {
    _messagesSub = messages.listen(_onMessage);
    _connectionSub = connectionState.listen(_onConnectionState);
    _attentionSub = unseenAttention.listen((List<AttentionItem> items) {
      _attention = items;
      _emit();
    });
    unawaited(_loadPersisted());
  }

  final AgentListMessageSender _send;
  List<AttentionItem> _attention;
  final String _hostId;
  final SharedPreferencesAsync _preferences;

  late final StreamSubscription<Message> _messagesSub;
  late final StreamSubscription<RelayConnectionState> _connectionSub;
  late final StreamSubscription<List<AttentionItem>> _attentionSub;

  final Map<String, WorkspaceSummary> _workspaces =
      <String, WorkspaceSummary>{};
  final Map<String, TabSummary> _tabs = <String, TabSummary>{};
  final Map<String, List<String>> _tabOrder = <String, List<String>>{};

  /// Insertion order is Herdr's own pane order (the snapshot's, then each `pane_created`).
  final Map<String, PaneSummary> _panes = <String, PaneSummary>{};

  /// `agents[].status_at` from the last `tree_snapshot` only; see this file's own header doc.
  final Map<String, String?> _statusAt = <String, String?>{};

  AgentListAxis _axis = AgentListAxis.priority;

  /// Collapsed [SpaceGroup.key]s.
  final Set<String> _collapsed = <String>{};

  /// The `Workspace` axis search text, trimmed (R-31-06-30). Session-scoped on purpose: a
  /// search names what the person is looking for right now, so it is never persisted.
  String _search = '';

  /// Whether at least one `tree_snapshot` has ever been applied. `agent_list_screen.dart` reads
  /// this to tell `Loading` from a genuinely agent-less `Empty` computer.
  bool hasLoaded = false;

  final StreamController<AgentListView> _viewController =
      StreamController<AgentListView>.broadcast();

  Completer<Result<void>>? _refreshCompleter;
  int _corrSeq = 0;

  /// Published on every `tree_snapshot`, `tree_update`, attention change, axis change or
  /// collapse toggle.
  Stream<AgentListView> get view => _viewController.stream;

  /// The current value of [view], for a caller that has not subscribed yet (a screen's first
  /// `build`).
  AgentListView get currentView => _build();

  String get _axisStorageKey => 'agent_list_axis_$_hostId';
  String get _collapsedStorageKey => 'agent_list_collapsed_$_hostId';

  Future<void> _loadPersisted() async {
    final String? axisValue = await _preferences.getString(_axisStorageKey);
    if (axisValue == 'workspace') _axis = AgentListAxis.workspace;
    if (axisValue == 'priority' || axisValue == 'urgency') {
      _axis = AgentListAxis.priority; // pre-R-03-114 value
    }
    final String? collapsedJson = await _preferences.getString(
      _collapsedStorageKey,
    );
    if (collapsedJson != null) {
      final List<dynamic> ids = jsonDecode(collapsedJson) as List<dynamic>;
      _collapsed
        ..clear()
        ..addAll(ids.cast<String>());
    }
    _emit();
  }

  /// R-31-06-12: defaults to [AgentListAxis.priority], per R-30-406.
  AgentListAxis get axis => _axis;

  /// Sets the grouping axis and persists it per Host (R-30-406, R-31-06-12).
  Future<void> setAxis(AgentListAxis axis) async {
    if (_axis == axis) return;
    _axis = axis;
    _emit();
    await _preferences.setString(
      _axisStorageKey,
      axis == AgentListAxis.workspace ? 'workspace' : 'priority',
    );
  }

  /// The current `Workspace` axis search text, trimmed; `''` when none.
  String get search => _search;

  /// Narrows the `Workspace` axis to [text] (R-31-06-30). Whitespace around it is ignored, the
  /// match is case-insensitive, and `''` shows the whole tree again.
  void setSearch(String text) {
    final String trimmed = text.trim();
    if (trimmed == _search) return;
    _search = trimmed;
    _emit();
  }

  bool isCollapsed(String spaceKey) => _collapsed.contains(spaceKey);

  /// Toggles one space header's collapse state and persists it per Host (R-30-407,
  /// R-31-06-12), keyed by [SpaceGroup.key].
  Future<void> toggleCollapsed(String spaceKey) async {
    if (!_collapsed.add(spaceKey)) _collapsed.remove(spaceKey);
    _emit();
    await _preferences.setString(
      _collapsedStorageKey,
      jsonEncode(_collapsed.toList()),
    );
  }

  /// Sends one `tree_request` (R-11-043) and resolves once the resulting `tree_snapshot` has
  /// been applied, or with `Err` on an `error` reply or a dropped link before one arrives. The
  /// screen's pull-to-refresh gesture, and its own initial load, both await this.
  Future<Result<void>> refresh() {
    final Completer<Result<void>> completer = Completer<Result<void>>();
    _refreshCompleter = completer;
    _send(
      const Message.treeRequest(TreeRequest()),
      corr: 'agent-list-${_corrSeq++}',
    );
    return completer.future;
  }

  void _onConnectionState(RelayConnectionState state) {
    if (state is! RelayConnected) {
      final Completer<Result<void>>? pending = _refreshCompleter;
      if (pending != null && !pending.isCompleted) {
        _refreshCompleter = null;
        pending.complete(
          const Err('read the agent list: the connection dropped'),
        );
      }
    }
  }

  void _onMessage(Message message) {
    switch (message) {
      case MessageTreeSnapshot(:final payload):
        _applySnapshot(payload);
        hasLoaded = true;
        _emit();
        final Completer<Result<void>>? pending = _refreshCompleter;
        if (pending != null && !pending.isCompleted) {
          _refreshCompleter = null;
          pending.complete(const Ok<void>(null));
        }
      case MessageTreeUpdate(:final payload):
        _applyUpdate(payload);
        _emit();
      case MessageError(:final payload):
        final Completer<Result<void>>? pending = _refreshCompleter;
        if (pending != null && !pending.isCompleted) {
          _refreshCompleter = null;
          pending.complete(Err(payload.message));
        }
      default:
        break;
    }
  }

  void _applySnapshot(TreeSnapshot snapshot) {
    _workspaces.clear();
    _tabs.clear();
    _tabOrder.clear();
    _panes.clear();
    for (final WorkspaceSummary workspace in snapshot.workspaces) {
      _workspaces[workspace.workspaceId] = workspace;
    }
    for (final TabSummary tab in snapshot.tabs) {
      _tabs[tab.tabId] = tab;
      _tabOrder.putIfAbsent(tab.workspaceId, () => <String>[]).add(tab.tabId);
    }
    for (final PaneSummary pane in snapshot.panes) {
      _panes[pane.paneId] = pane;
    }
    _statusAt
      ..clear()
      ..addEntries(
        snapshot.agents.map((agent) => MapEntry(agent.paneId, agent.statusAt)),
      );
  }

  void _applyUpdate(TreeUpdate update) {
    switch (update.event) {
      case TreeEvent.workspaceCreated:
      case TreeEvent.workspaceUpdated:
      case TreeEvent.workspaceRenamed:
        final WorkspaceSummary? workspace = update.workspace;
        if (workspace == null) return;
        _workspaces[workspace.workspaceId] = workspace;
      case TreeEvent.workspaceClosed:
        final WorkspaceSummary? workspace = update.workspace;
        if (workspace == null) return;
        _workspaces.remove(workspace.workspaceId);
        final List<String> tabIds =
            _tabOrder.remove(workspace.workspaceId) ?? const <String>[];
        for (final String tabId in tabIds) {
          _tabs.remove(tabId);
        }
        _panes.removeWhere(
          (_, PaneSummary pane) => pane.workspaceId == workspace.workspaceId,
        );
      case TreeEvent.tabCreated:
      case TreeEvent.tabRenamed:
      case TreeEvent.tabFocused:
        final TabSummary? tab = update.tab;
        if (tab == null) return;
        if (!_tabs.containsKey(tab.tabId)) {
          _tabOrder
              .putIfAbsent(tab.workspaceId, () => <String>[])
              .add(tab.tabId);
        }
        _tabs[tab.tabId] = tab;
      case TreeEvent.tabClosed:
        final TabSummary? tab = update.tab;
        if (tab == null) return;
        _tabs.remove(tab.tabId);
        _tabOrder[tab.workspaceId]?.remove(tab.tabId);
        _panes.removeWhere((_, PaneSummary pane) => pane.tabId == tab.tabId);
      case TreeEvent.paneCreated:
      case TreeEvent.paneUpdated:
      case TreeEvent.paneFocused:
      case TreeEvent.paneAgentStatusChanged:
        final PaneSummary? pane = update.pane;
        if (pane == null) return;
        final PaneSummary? previous = _panes[pane.paneId];
        if (previous == null || previous.agentStatus != pane.agentStatus) {
          // R-30-405: a `tree_update` carries no timestamp for the change it reports.
          _statusAt[pane.paneId] = null;
        }
        _panes[pane.paneId] = pane;
      case TreeEvent.paneClosed:
        final PaneSummary? pane = update.pane;
        if (pane == null) return;
        _panes.remove(pane.paneId);
        _statusAt.remove(pane.paneId);
      case TreeEvent.layoutUpdated:
        break; // No pane/workspace/tab identity change; R-11-046's own field list carries none.
    }
  }

  void _emit() => _viewController.add(_build());

  AgentListView _build() {
    final Map<String, AttentionItem> attentionByPane = <String, AttentionItem>{
      for (final AttentionItem item in _attention) item.paneId: item,
    };

    // R-31-06-35: only the tree supplies rows and their current state.
    final List<AgentRow> attentionRows = <AgentRow>[];
    final List<AgentRow> liveRows = <AgentRow>[];
    final List<ShellRow> shellRows = <ShellRow>[];
    for (final PaneSummary pane in _panes.values) {
      if (pane.agent == null) {
        shellRows.add(
          ShellRow(
            paneId: pane.paneId,
            workspaceId: pane.workspaceId,
            tabId: pane.tabId,
            paneDisplayName: _paneDisplayName(pane.paneId, pane.label),
            title: pane.title,
          ),
        );
        continue;
      }
      final AgentRow? row = _rowFromPane(pane, attentionByPane[pane.paneId]);
      if (row == null) continue;
      if (row.status == AgentStatusKind.blocked ||
          row.status == AgentStatusKind.done) {
        attentionRows.add(row);
      } else {
        liveRows.add(row);
      }
    }

    return AgentListView(
      axis: _axis,
      prioritySections: _buildPrioritySections(attentionRows, liveRows),
      spaces: _narrow(
        _buildSpaces(<PaneRow>[...attentionRows, ...liveRows, ...shellRows]),
        _search,
      ),
      search: _search,
      workspaceCount: _workspaces.length,
      attentionCount: attentionRows.where((row) => row.needsAttention).length,
      collapsed: Set<String>.unmodifiable(_collapsed),
    );
  }

  AgentRow? _rowFromPane(PaneSummary pane, AttentionItem? attention) {
    final TabSummary? tab = _tabs[pane.tabId];
    final WorkspaceSummary? workspace = _workspaces[pane.workspaceId];
    if (tab == null || workspace == null) return null;
    final AgentStatusKind status = _statusKindOf(pane.agentStatus);
    // R-31-06-35: stale attention cannot mark or reorder a live row.
    if (status != AgentStatusKind.blocked && status != AgentStatusKind.done) {
      attention = null;
    }
    return AgentRow(
      paneId: pane.paneId,
      workspaceId: pane.workspaceId,
      workspaceName: workspace.name,
      tabId: pane.tabId,
      tabTitle: tab.title,
      paneDisplayName: _paneDisplayName(pane.paneId, pane.label),
      title: pane.title,
      agentKind: pane.agent!,
      status: status,
      at: attention?.at ?? _statusAt[pane.paneId],
      needsAttention: attention != null,
    );
  }

  /// R-31-07-08: `label` when non-empty; else the word `pane` and the pane's own suffix from
  /// [paneId] (`w3:p11` draws as `pane 11`, `w3:pS` draws as `pane S`).
  static String _paneDisplayName(String paneId, String? label) {
    if (label != null && label.isNotEmpty) return label;
    final String afterColon = paneId.contains(':')
        ? paneId.split(':').last
        : paneId;
    final String suffix = afterColon.startsWith('p')
        ? afterColon.substring(1)
        : afterColon;
    return 'pane $suffix';
  }

  /// R-30-404: an unrecognised status string MUST render as `unknown`, never `idle`.
  static AgentStatusKind _statusKindOf(String raw) => switch (raw) {
    'idle' => AgentStatusKind.idle,
    'working' => AgentStatusKind.working,
    'blocked' => AgentStatusKind.blocked,
    'done' => AgentStatusKind.done,
    _ => AgentStatusKind.unknown,
  };

  List<PrioritySection> _buildPrioritySections(
    List<AgentRow> attention,
    List<AgentRow> live,
  ) {
    final List<AgentRow> needsYou = List<AgentRow>.of(attention)
      ..sort(_needsYouCompare);
    final List<AgentRow> working = _bucket(live, AgentStatusKind.working);
    final List<AgentRow> idle = _bucket(live, AgentStatusKind.idle);
    final List<AgentRow> unknown = _bucket(live, AgentStatusKind.unknown);

    return <PrioritySection>[
      if (needsYou.isNotEmpty)
        PrioritySection(title: 'NEEDS YOU', rows: needsYou),
      if (working.isNotEmpty) PrioritySection(title: 'WORKING', rows: working),
      if (idle.isNotEmpty) PrioritySection(title: 'IDLE', rows: idle),
      if (unknown.isNotEmpty) PrioritySection(title: 'UNKNOWN', rows: unknown),
    ];
  }

  static List<AgentRow> _bucket(List<AgentRow> rows, AgentStatusKind status) =>
      rows.where((AgentRow row) => row.status == status).toList()
        ..sort(_ageCompare);

  /// R-31-06-02: `blocked` before `done`, oldest state change first inside each.
  static int _needsYouCompare(AgentRow a, AgentRow b) {
    final int rankA = a.status == AgentStatusKind.blocked ? 0 : 1;
    final int rankB = b.status == AgentStatusKind.blocked ? 0 : 1;
    if (rankA != rankB) return rankA - rankB;
    return _ageCompare(a, b);
  }

  /// Oldest first, `null` age last, per R-31-06-02/R-31-06-25.
  static int _ageCompare(AgentRow a, AgentRow b) {
    if (a.at == null && b.at == null) return 0;
    if (a.at == null) return 1;
    if (b.at == null) return -1;
    return a.at!.compareTo(b.at!);
  }

  /// R-31-06-27: `Space > Worktree > Tab > Pane`, over the whole tree: every workspace, every
  /// tab and every pane, agent or not (R-31-06-14). R-31-06-15 fixes the order to the desktop
  /// sidebar's own: a space stands where its first member stands in Herdr's workspace order,
  /// the parent stands first inside it and the other members keep Herdr's order, tabs keep
  /// Herdr's order, and inside a tab attention comes first then Herdr's pane order.
  List<SpaceGroup> _buildSpaces(List<PaneRow> all) {
    final Map<String, Map<String, List<PaneRow>>> byWorkspace =
        <String, Map<String, List<PaneRow>>>{};
    for (final PaneRow row in all) {
      byWorkspace
          .putIfAbsent(row.workspaceId, () => <String, List<PaneRow>>{})
          .putIfAbsent(row.tabId, () => <PaneRow>[])
          .add(row);
    }
    final Map<String, int> paneOrder = <String, int>{
      for (final (int index, String paneId) in _panes.keys.indexed)
        paneId: index,
    };
    int rowCompare(PaneRow a, PaneRow b) {
      final bool attentionA = a is AgentRow && a.needsAttention;
      final bool attentionB = b is AgentRow && b.needsAttention;
      if (attentionA != attentionB) {
        return attentionA ? -1 : 1; // R-30-409, R-31-06-15.
      }
      final int orderA = paneOrder[a.paneId] ?? paneOrder.length;
      final int orderB = paneOrder[b.paneId] ?? paneOrder.length;
      if (orderA != orderB) return orderA - orderB;
      return a.paneId.compareTo(b.paneId);
    }

    // Insertion order is first-member order: the desktop places a group where its first member
    // stands, whether that member is the parent or not.
    final Map<String, List<WorktreeGroup>> worktreesBySpace =
        <String, List<WorktreeGroup>>{};
    for (final WorkspaceSummary workspace in _workspaces.values) {
      final Map<String, List<PaneRow>> rowsByTab =
          byWorkspace[workspace.workspaceId] ?? const <String, List<PaneRow>>{};
      // R-31-06-35: attention cannot preserve a tab absent from the tree.
      final List<String> tabIds =
          _tabOrder[workspace.workspaceId] ?? const <String>[];
      final List<TabGroup> tabs = <TabGroup>[
        for (final String tabId in tabIds)
          TabGroup(
            tabId: tabId,
            title: _tabs[tabId]!.title,
            rows: List<PaneRow>.of(rowsByTab[tabId] ?? const <PaneRow>[])
              ..sort(rowCompare),
          ),
      ];
      worktreesBySpace
          .putIfAbsent(
            workspace.spaceId ?? workspace.workspaceId,
            () => <WorktreeGroup>[],
          )
          .add(
            WorktreeGroup(
              workspaceId: workspace.workspaceId,
              name: workspace.name,
              tabs: tabs,
            ),
          );
    }

    return <SpaceGroup>[
      for (final MapEntry<String, List<WorktreeGroup>> entry
          in worktreesBySpace.entries)
        SpaceGroup(
          key: entry.key,
          // The parent names the space; it is in the same snapshot (R-11-044). The first member
          // stands in only between a `workspace_closed` of the parent and the snapshot that
          // follows it, so the header is never blank.
          name: _workspaces[entry.key]?.name ?? entry.value.first.name,
          worktrees: _parentFirst(entry.key, entry.value),
        ),
    ];
  }

  /// The parent, the member whose id is [key], first; the others keep Herdr's order.
  static List<WorktreeGroup> _parentFirst(
    String key,
    List<WorktreeGroup> members,
  ) {
    final int parent = members.indexWhere(
      (WorktreeGroup worktree) => worktree.workspaceId == key,
    );
    if (parent > 0) members.insert(0, members.removeAt(parent));
    return members;
  }

  /// R-31-06-30: narrows the built hierarchy to [query], case-insensitive, by substring. A tier
  /// whose own name matches keeps its whole subtree; otherwise it stays only for the descendants
  /// that match, so a match is always shown with its ancestors. Counts and badges are rebuilt
  /// from what stays. An empty [query] returns [spaces] untouched.
  static List<SpaceGroup> _narrow(List<SpaceGroup> spaces, String query) {
    if (query.isEmpty) return spaces;
    final String needle = query.toLowerCase();
    bool hit(String text) => text.toLowerCase().contains(needle);
    return <SpaceGroup>[
      for (final SpaceGroup space in spaces)
        if (_narrowSpace(space, hit) case final SpaceGroup kept) kept,
    ];
  }

  static SpaceGroup? _narrowSpace(SpaceGroup space, bool Function(String) hit) {
    if (hit(space.name)) return space;
    final List<WorktreeGroup> worktrees = <WorktreeGroup>[
      for (final WorktreeGroup worktree in space.worktrees)
        if (_narrowWorktree(worktree, hit) case final WorktreeGroup kept) kept,
    ];
    if (worktrees.isEmpty) return null;
    return SpaceGroup(key: space.key, name: space.name, worktrees: worktrees);
  }

  static WorktreeGroup? _narrowWorktree(
    WorktreeGroup worktree,
    bool Function(String) hit,
  ) {
    if (hit(worktree.name)) return worktree;
    final List<TabGroup> tabs = <TabGroup>[
      for (final TabGroup tab in worktree.tabs)
        if (_narrowTab(tab, hit) case final TabGroup kept) kept,
    ];
    if (tabs.isEmpty) return null;
    return WorktreeGroup(
      workspaceId: worktree.workspaceId,
      name: worktree.name,
      tabs: tabs,
    );
  }

  /// A pane matches on its display name, its `title` (the command), and its agent kind.
  static TabGroup? _narrowTab(TabGroup tab, bool Function(String) hit) {
    if (hit(tab.title)) return tab;
    final List<PaneRow> rows = <PaneRow>[
      for (final PaneRow row in tab.rows)
        if (hit(row.paneDisplayName) ||
            hit(row.title) ||
            (row is AgentRow && hit(row.agentKind)))
          row,
    ];
    if (rows.isEmpty) return null;
    return TabGroup(tabId: tab.tabId, title: tab.title, rows: rows);
  }

  void dispose() {
    unawaited(_messagesSub.cancel());
    unawaited(_connectionSub.cancel());
    unawaited(_attentionSub.cancel());
    unawaited(_viewController.close());
  }
}
