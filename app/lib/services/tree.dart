/// The Device's tree service (Phase 18, `WP-18-c`): the `tree_request`/`tree_snapshot` read
/// and the `tree_update` follow (R-11-043, R-11-044, R-11-046, R-31-07-04), the flat-to-joined
/// view model `tree_screen.dart` draws from, the pane display-name rule (R-31-07-10, and the
/// checklist's own "draw `title` as the pane display name" line, R-11-046/R-31-07-01), the
/// nullable `status_at` reader that never invents a value (R-11-224), and the per-Host expander
/// persistence (R-31-07-02).
///
/// Mirrors `device_list.dart`'s own shape: every function takes a `Stream<Message>` (and, for
/// the one request/reply read, a `Stream<RelayConnectionState>`) and a [TreeMessageSender]
/// rather than a whole `RelayConnection`, for the same reason that file's header comment
/// gives — `RelayConnection` opens a real socket with no injectable fake short of the full
/// local-server harness, and this file's own logic has nothing to do with that transport.
/// `tree_screen.dart` is the one caller and passes `connection.messages`,
/// `connection.connectionState` and `connection.send` straight through.
///
/// **Why [watchTreeUpdates] also adopts a `tree_snapshot`, not only a `tree_update`.**
/// `relay.dart`'s own `_resume()` already sends a fresh `tree_request` on every reconnect
/// (R-11-084, R-11-200) — the *send* half of R-11-043 is that file's job, not this one's. This
/// file supplies the *receive* half: a `tree_snapshot` that arrives without this file having
/// asked for it (because `relay.dart` asked instead, after a dropped and restored link) is
/// still adopted as the new base, so the screen recovers with no person action, matching
/// R-31-07-04's "never poll" — this file never re-sends `tree_request` itself once
/// [fetchTreeSnapshot] returns.
///
/// This file owns no widget and paints nothing (R-90-024): `tree_screen.dart` reads every type
/// and function below.
library;

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/result/result.dart' show Err, Ok, Result;
import '../models/message.dart';
import '../models/messages/agent_summary.dart';
import '../models/messages/pane_summary.dart';
import '../models/messages/tab_summary.dart';
import '../models/messages/tree_event.dart';
import '../models/messages/tree_request.dart';
import '../models/messages/tree_snapshot.dart';
import '../models/messages/tree_update.dart';
import '../models/messages/workspace_summary.dart';
import 'relay.dart' show RelayConnectionState, RelayConnected;

/// The function shape `RelayConnection.send` already has; accepted here instead of the whole
/// connection object (see this file's own header comment). Matches `device_list.dart`'s
/// `SendFrame` and `terminal.dart`'s `TerminalMessageSender` exactly, each file's own private
/// copy of the same seam.
typedef TreeMessageSender = void Function(Message message, {String? corr});

int _corrSeq = 0;

/// A correlation id for one outgoing `tree_request` (R-11-034). Every function below matches a
/// reply by its message type instead of reading `corr` back — `relay.dart`'s `messages` stream
/// publishes the decoded `Message` only, stripping the frame envelope, the same limitation
/// `device_list.dart`'s own header comment documents.
String _nextCorr() => 'tree-${_corrSeq++}';

/// Races [messages] for the first message [onMessage] accepts against [connectionState] for a
/// transition off [RelayConnected]. Returns `null` on a drop. A private copy of
/// `device_list.dart`'s own helper of the same shape; see that file's header comment for why
/// awaiting either cancellation is not needed.
Future<T?> _awaitReply<T>({
  required Stream<Message> messages,
  required Stream<RelayConnectionState> connectionState,
  required T? Function(Message) onMessage,
}) async {
  final Completer<T?> completer = Completer<T?>();
  void finish(T? value) {
    if (!completer.isCompleted) completer.complete(value);
  }

  final StreamSubscription<Message> messageSub = messages.listen((message) {
    final T? result = onMessage(message);
    if (result != null) finish(result);
  });
  final StreamSubscription<RelayConnectionState> stateSub = connectionState
      .listen((state) {
        if (state is! RelayConnected) finish(null);
      });
  try {
    return await completer.future;
  } finally {
    unawaited(messageSub.cancel());
    unawaited(stateSub.cancel());
  }
}

/// Requests the full tree (`tree_request`, R-11-043) and awaits `tree_snapshot`. `Err` covers
/// both an `error` reply and a dropped link. Used for the first read on mount and for the
/// person's own `Try again` press; this function itself never retries and never polls
/// (R-31-07-04).
Future<Result<TreeSnapshot>> fetchTreeSnapshot({
  required Stream<Message> messages,
  required Stream<RelayConnectionState> connectionState,
  required TreeMessageSender send,
}) async {
  send(const Message.treeRequest(TreeRequest()), corr: _nextCorr());
  final Result<TreeSnapshot>? reply = await _awaitReply<Result<TreeSnapshot>>(
    messages: messages,
    connectionState: connectionState,
    onMessage: (message) => switch (message) {
      MessageTreeSnapshot(:final payload) => Ok(payload),
      MessageError(:final payload) => Err(payload.message),
      _ => null,
    },
  );
  return reply ?? const Err('read the tree: the connection dropped');
}

/// Follows `tree_update` from [initial] onward (R-11-046), and adopts any later
/// `tree_snapshot` wholesale — see this file's own header comment for why. Sends nothing:
/// purely reactive, so this stream never needs a [RelayConnectionState] to race (unlike
/// [fetchTreeSnapshot], a one-shot request whose single reply could otherwise wait forever on
/// a dropped link, this is a long-lived subscription that simply stays quiet until the next
/// message).
Stream<TreeSnapshot> watchTreeUpdates(
  Stream<Message> messages,
  TreeSnapshot initial,
) {
  TreeSnapshot current = initial;
  TreeSnapshot? handle(Message message) {
    switch (message) {
      case MessageTreeSnapshot(:final payload):
        return current = payload;
      case MessageTreeUpdate(:final payload):
        final TreeSnapshot next = applyTreeUpdate(current, payload);
        if (identical(next, current)) return null;
        return current = next;
      default:
        return null;
    }
  }

  return messages
      .map(handle)
      .where((snapshot) => snapshot != null)
      .cast<TreeSnapshot>();
}

/// Replaces or removes one entry of [items], matched by [idOf], keeping every other entry's
/// position — an update never reshuffles the list, only a genuinely new entry is appended.
List<T> _upsert<T>(List<T> items, T value, String Function(T) idOf) {
  final String id = idOf(value);
  final int index = items.indexWhere((item) => idOf(item) == id);
  if (index == -1) return <T>[...items, value];
  final List<T> next = List<T>.of(items);
  next[index] = value;
  return next;
}

/// Applies one `tree_update` onto [snapshot] (R-11-046). `layout.updated` is a deliberate
/// no-op: R-31-07-01 forbids the split geometry that event carries from ever reshaping this
/// three-level tree, and the pane's own fields arrive through a separate `pane.updated`
/// instead. An update whose declared object is absent (a malformed frame) is also a no-op —
/// this file MUST NOT guess a missing id.
TreeSnapshot applyTreeUpdate(TreeSnapshot snapshot, TreeUpdate update) {
  switch (update.event) {
    case TreeEvent.workspaceCreated:
    case TreeEvent.workspaceUpdated:
    case TreeEvent.workspaceRenamed:
      final WorkspaceSummary? workspace = update.workspace;
      if (workspace == null) return snapshot;
      return snapshot.copyWith(
        workspaces: _upsert(
          snapshot.workspaces,
          workspace,
          (w) => w.workspaceId,
        ),
      );
    case TreeEvent.workspaceClosed:
      final WorkspaceSummary? workspace = update.workspace;
      if (workspace == null) return snapshot;
      // A closed workspace takes its tabs and panes with it (R-11-044's join):
      // Herdr sends no `tab.closed` or `pane.closed` for them, measured
      // 2026-09-11 (R-11-046 as amended), so a row would otherwise outlive
      // its workspace. `agent_list.dart`'s reducer already cascades the same way.
      return snapshot.copyWith(
        workspaces: snapshot.workspaces
            .where((w) => w.workspaceId != workspace.workspaceId)
            .toList(),
        tabs: snapshot.tabs
            .where((t) => t.workspaceId != workspace.workspaceId)
            .toList(),
        panes: snapshot.panes
            .where((p) => p.workspaceId != workspace.workspaceId)
            .toList(),
      );
    case TreeEvent.tabCreated:
    case TreeEvent.tabRenamed:
    case TreeEvent.tabFocused:
      final TabSummary? tab = update.tab;
      if (tab == null) return snapshot;
      return snapshot.copyWith(
        tabs: _upsert(snapshot.tabs, tab, (t) => t.tabId),
      );
    case TreeEvent.tabClosed:
      final TabSummary? tab = update.tab;
      if (tab == null) return snapshot;
      // Same cascade: a closed tab's panes get no `pane.closed` of their own.
      return snapshot.copyWith(
        tabs: snapshot.tabs.where((t) => t.tabId != tab.tabId).toList(),
        panes: snapshot.panes.where((p) => p.tabId != tab.tabId).toList(),
      );
    case TreeEvent.paneCreated:
    case TreeEvent.paneUpdated:
    case TreeEvent.paneFocused:
    case TreeEvent.paneAgentStatusChanged:
      final PaneSummary? pane = update.pane;
      if (pane == null) return snapshot;
      return snapshot.copyWith(
        panes: _upsert(snapshot.panes, pane, (p) => p.paneId),
      );
    case TreeEvent.paneClosed:
      final PaneSummary? pane = update.pane;
      if (pane == null) return snapshot;
      return snapshot.copyWith(
        panes: snapshot.panes.where((p) => p.paneId != pane.paneId).toList(),
      );
    case TreeEvent.layoutUpdated:
      return snapshot;
  }
}

/// One tab, with its panes already joined by `tab_id` (R-11-044).
final class TabNode {
  const TabNode({required this.tab, required this.panes});

  final TabSummary tab;
  final List<PaneSummary> panes;
}

/// One workspace, with its tabs already joined by `workspace_id` (R-11-044).
final class WorkspaceNode {
  const WorkspaceNode({required this.workspace, required this.tabs});

  final WorkspaceSummary workspace;
  final List<TabNode> tabs;

  /// Every pane this workspace holds, across every tab.
  int get paneCount =>
      tabs.fold(0, (int sum, TabNode tab) => sum + tab.panes.length);
}

/// Joins the flat `tree_snapshot` (R-10-018, R-11-044) into the three-level shape R-31-07-01
/// fixes: workspace, then tab, then pane. Preserves the Host's own list order. A tab or a pane
/// whose parent id is missing from the snapshot (a transient ordering gap between two
/// `tree_update`s) is silently dropped from the joined tree rather than guessed into a wrong
/// parent; the next update corrects it.
List<WorkspaceNode> buildTree(TreeSnapshot snapshot) {
  final Map<String, List<PaneSummary>> panesByTab =
      <String, List<PaneSummary>>{};
  for (final PaneSummary pane in snapshot.panes) {
    panesByTab.putIfAbsent(pane.tabId, () => <PaneSummary>[]).add(pane);
  }
  final Map<String, List<TabSummary>> tabsByWorkspace =
      <String, List<TabSummary>>{};
  for (final TabSummary tab in snapshot.tabs) {
    tabsByWorkspace.putIfAbsent(tab.workspaceId, () => <TabSummary>[]).add(tab);
  }
  return <WorkspaceNode>[
    for (final WorkspaceSummary workspace in snapshot.workspaces)
      WorkspaceNode(
        workspace: workspace,
        tabs: <TabNode>[
          for (final TabSummary tab
              in tabsByWorkspace[workspace.workspaceId] ?? const <TabSummary>[])
            TabNode(
              tab: tab,
              panes: panesByTab[tab.tabId] ?? const <PaneSummary>[],
            ),
        ],
      ),
  ];
}

/// R-31-07-10: a pane row's display name. `label` when the pane was named, else the word
/// `pane` plus the pane's own suffix from `pane_id`: `w3:p11` draws as `pane 11`, and `w3:pS`
/// draws as `pane S`. A pane created from the phone is unnamed (R-30-954), so `label` is
/// empty for it — this is the checklist's own "draw `title` as the pane display name" line;
/// the *command* beside the name is `title` verbatim (R-11-225 already keeps a raw
/// terminal-set title off the wire, so no further filtering is needed here).
String paneDisplayName(PaneSummary pane) {
  if (pane.label.isNotEmpty) return pane.label;
  final int lastColon = pane.paneId.lastIndexOf(':');
  final String suffix = lastColon < 0
      ? pane.paneId
      : pane.paneId.substring(lastColon + 1);
  final String number = suffix.startsWith('p') ? suffix.substring(1) : suffix;
  return 'pane $number';
}

/// R-11-224: the agent's `status_at` for [paneId], parsed to local time, or `null` when the
/// Host never observed the change through a `pane.agent_status_changed` event. The Host MUST
/// NOT invent a timestamp, and neither does this function — `null` means "draw no age", never
/// "draw an age of zero".
DateTime? agentStatusAt(TreeSnapshot snapshot, String paneId) {
  for (final AgentSummary agent in snapshot.agents) {
    if (agent.paneId == paneId) {
      final String? statusAt = agent.statusAt;
      return statusAt == null ? null : DateTime.parse(statusAt).toLocal();
    }
  }
  return null;
}

/// R-31-07-02's default before any override: every workspace starts expanded.
const bool defaultWorkspaceExpanded = true;

/// R-31-07-02's default before any override: a tab starts expanded only when its workspace
/// holds three tabs or fewer (07-tree.md's own `Default` states-table row).
bool defaultTabExpanded(int tabCountInWorkspace) => tabCountInWorkspace <= 3;

/// Per-Host expander overrides (R-31-07-02): survives a route change and an app restart. Its
/// own `SharedPreferencesAsync` instance, independent of `plain_store.dart` (a distinct owned
/// path, R-90-016) — the same pattern `notifications.dart` already uses for its own settings.
///
/// Stores only the ids a person has explicitly toggled away from [defaultWorkspaceExpanded] /
/// [defaultTabExpanded]; an id absent from [loadOverrides]'s result still follows that
/// default. A brand-new tab a person has never touched therefore keeps following the
/// tab-count default even after other tabs in the same workspace have stored overrides.
class TreeExpansionStore {
  TreeExpansionStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  static String _expandedKey(String hostId) => 'tree_expanded_$hostId';
  static String _collapsedKey(String hostId) => 'tree_collapsed_$hostId';

  /// Loads [hostId]'s persisted overrides: a workspace or tab id mapped to the forced state a
  /// person last set for it.
  Future<Map<String, bool>> loadOverrides(String hostId) async {
    final List<String>? expanded = await _preferences.getStringList(
      _expandedKey(hostId),
    );
    final List<String>? collapsed = await _preferences.getStringList(
      _collapsedKey(hostId),
    );
    return <String, bool>{
      for (final String id in expanded ?? const <String>[]) id: true,
      for (final String id in collapsed ?? const <String>[]) id: false,
    };
  }

  /// Saves [overrides] for [hostId], replacing whatever was stored before.
  Future<void> saveOverrides(String hostId, Map<String, bool> overrides) async {
    final List<String> expanded = <String>[
      for (final MapEntry<String, bool> entry in overrides.entries)
        if (entry.value) entry.key,
    ];
    final List<String> collapsed = <String>[
      for (final MapEntry<String, bool> entry in overrides.entries)
        if (!entry.value) entry.key,
    ];
    await _preferences.setStringList(_expandedKey(hostId), expanded);
    await _preferences.setStringList(_collapsedKey(hostId), collapsed);
  }
}
