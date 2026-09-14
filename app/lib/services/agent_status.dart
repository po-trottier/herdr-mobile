/// The Device's `agent_status` consumer and unseen-attention list (Phase 19, `WP-19-a`), per
/// `docs/30-ux-spec.md` R-30-500 to R-30-513. This file is the one place that turns a live
/// `agent_status` message, or a `tree_snapshot`'s `agents[]`, into the attention state
/// `agent_list_screen.dart` (`WP-18-a`, Phase 18) and `docs/22-platform-integration.md` R-22-053's
/// group (Phase 22 accessibility) both read (`docs/90-implementation-plan.md` §5.2's `WP-19-a`
/// `Publishes.` line).
///
/// Two, and only two, sources feed [unseenAttention]:
///
/// - A live `agent_status` message on [RelayConnection.messages] (R-30-500): earns a badge AND a
///   native local notification through [NotificationsService.postAgentStatusNotification].
/// - A `tree_snapshot`, received after `RelayConnection`'s own reconnect resume (R-22-026,
///   R-11-084) or a caller's own `tree_request`: earns a badge only, from `agents[]`'s already-
///   settled state (R-22-024, R-30-513). This is the only path a relaunch or a reconnect can take,
///   and it MUST NOT post a notification: "the app MUST NOT synthesise a system notification for
/// an event arrived while its process was stopped" (R-30-513, R-03-062).
///
/// R-31-06-35: snapshots and tree updates remove attention for absent panes and
/// panes whose current state is not `blocked` or `done`. They preserve the shared
/// notification log. Read and remove actions still update persisted acknowledgements.
///
/// Since the 2026-09-04 decision that made `Notifications` a bottom destination, this file keeps
/// a per-pane notification log ([notifications], R-31-07-01): one entry per pane, latest status
/// wins, each flagged `seen` or not. [unseenAttention] is the unseen subset of that log, so every
/// badge and the `NEEDS YOU` section keep their meaning. [remove]/[removeAll] drop entries from
/// the log (R-31-07-04). The log itself is rebuilt from `tree_snapshot` after a relaunch
/// (R-30-513); what persists is the *acknowledgement*: [markSeen]/[remove] record the identity
/// `(paneId, status, at)` of the change a person read or removed, per Host, in
/// [PlainStore.saveNotificationAck] (metadata only, never pane content, R-30-510). A later
/// `tree_snapshot` or a repeat `agent_status` with that same identity therefore comes back read,
/// or not at all; only a genuinely newer change (a different status, or a later `at`) re-adds
/// the pane unread. Forgetting a computer clears its acknowledgements with its record
/// (`PlainStore.removePairedHost`).
///
/// Every log key, acknowledgement, space name and pane-closed snapshot carries its Host id:
/// pane and workspace ids are one computer's names (R-11-044), so two paired computers may
/// share one and neither may see the other's rows. [notifications] and every action cover the
/// connected computer alone (R-30-946); [unseenAttention] spans every computer so
/// `host_list_screen.dart` can badge a disconnected one's remembered attention (R-03-046). A
/// `tree_snapshot` carries no Host id, so this file captures the connected computer's identity
/// when the snapshot ARRIVES — the queue behind it may outlive a Host switch — and a
/// `RelayConnected` for a different computer emits that computer's log, its empty state
/// included, so a listener mounted since before the switch converges.
///
/// This file also publishes [announcements] (Phase 22, `docs/30-ux-spec.md` R-30-714, R-30-742):
/// exactly one spoken sentence when a live transition lands on the pane [setOpenPane] names as
/// currently open, and never for a `tree_snapshot`-rehydrated one (the same R-30-513 reasoning
/// that already excludes it from a notification excludes it from an announcement).
library;

import 'dart:async';

import '../core/result/result.dart' show Err, Ok, Result;
import '../models/message.dart';
import '../models/messages/agent_status.dart';
import '../models/messages/agent_status_kind.dart';
import '../models/messages/mark_seen.dart';
import '../models/messages/pane_summary.dart';
import '../models/messages/tree_event.dart';
import '../models/messages/tree_snapshot.dart';
import '../models/messages/tree_update.dart';
import 'notifications.dart';
import 'plain_store.dart';
import 'relay.dart';

/// One agent needing attention (R-30-500): `blocked` or `done`. Every human-readable field
/// mirrors [AgentStatus]/`AgentSummary` exactly — no other source, per R-01-011 — except
/// [spaceName], which this service joins from the last `tree_snapshot` it saw.
final class AttentionItem {
  const AttentionItem({
    required this.hostId,
    required this.paneId,
    required this.workspaceId,
    required this.tabId,
    this.spaceName = '',
    required this.agentKind,
    required this.tabTitle,
    required this.paneTitle,
    required this.status,
    required this.at,
  });

  final String hostId;
  final String paneId;
  final String workspaceId;
  final String tabId;

  /// The Herdr space that holds the pane (`docs/31-mockups/06-agent-list.md`, decided
  /// 2026-09-04): the workspace's `repo_name` from the last `tree_snapshot`, or its `name` when
  /// it has no worktree. Empty when no snapshot has named this workspace yet — `agent_status`
  /// carries no workspace name of its own.
  final String spaceName;
  final String agentKind;
  final String tabTitle;
  final String paneTitle;

  /// Always [AgentStatusKind.blocked] or [AgentStatusKind.done] (R-30-500).
  final AgentStatusKind status;

  /// RFC 3339 UTC, or `null` when the Host never observed the change (R-11-224: "the Host MUST
  /// NOT invent a timestamp"). [AgentStatusService.unseenAttention] sorts a `null` entry last —
  /// an unknown age is the least useful ordering key, not the most recent one.
  final String? at;
}

/// One row of the Notifications screen (`docs/31-mockups/07-notifications.md`, R-31-07-01): the
/// latest `blocked`/`done` transition of one pane, and whether a person has seen it.
final class NotificationItem {
  const NotificationItem({required this.item, required this.seen});

  final AttentionItem item;

  /// `true` once [AgentStatusService.markSeen] (or `markAllSeen`) flagged it. A later live
  /// `agent_status` for the same pane replaces the entry and resets this to `false`.
  final bool seen;
}

/// The Device's live `agent_status` consumer and unseen-attention list. One instance covers the
/// whole app session; construct it once a [RelayConnection] and a [NotificationsService] exist.
///
/// Takes [messages], [connectionState] and [currentHostId] rather than a whole
/// `RelayConnection`: `RelayConnection` is declared `final class` (R-20-009, R-22-025's
/// single-socket invariant lives there), so a test in a different library cannot
/// `implements`/mock it. This service only ever reads its message stream, its connection
/// lifecycle and its last-known Host id, so those seams are also the honest minimum
/// dependency, not a speculative interface.
class AgentStatusService {
  AgentStatusService({
    required Stream<Message> messages,
    required NotificationsService notifications,
    required PlainStore plainStore,
    this.send,
    String? Function() currentHostId = _noHostId,
    Stream<RelayConnectionState> connectionState =
        const Stream<RelayConnectionState>.empty(),
    // `this._notifications`/`this._currentHostId` would make the external parameter names
    // private, unusable from `agent_status_test.dart`, a different library (Dart's
    // named-parameter privacy rule) — the same reasoning `biometric_gate.dart`'s `_now` param
    // documents.
    // ignore: prefer_initializing_formals
  }) : _notifications = notifications,
       // ignore: prefer_initializing_formals
       _plainStore = plainStore,
       // ignore: prefer_initializing_formals
       _currentHostId = currentHostId {
    _subscription = messages.listen(_onMessage);
    _stateSubscription = connectionState.listen(_onConnectionState);
  }

  final NotificationsService _notifications;
  final void Function(Message message)? send;
  final PlainStore _plainStore;
  final String? Function() _currentHostId;
  late final StreamSubscription<Message> _subscription;
  late final StreamSubscription<RelayConnectionState> _stateSubscription;

  /// The acknowledged identities of the Host [_acksHostId], keyed by pane id, loaded once per
  /// Host from [PlainStore.notificationAcks] before the first message of that Host is applied.
  final Map<String, NotificationAck> _acks = <String, NotificationAck>{};
  String? _acksHostId;

  /// Messages apply one after another, in arrival order, because loading the acknowledgements
  /// is asynchronous and a `tree_snapshot` must not overtake the `agent_status` before it.
  Future<void> _queue = Future<void>.value();

  /// Notification history, keyed by Host and pane (R-31-07-01).
  /// Unread entries feed attention only when the known tree state permits it.
  final Map<String, NotificationItem> _log = <String, NotificationItem>{};
  // R-31-06-35: tree state filters attention, not notification history.
  final Map<String, Map<String, PaneSummary>> _panesByHost = {};

  /// Host id + `workspace_id` -> space name, from that Host's last `tree_snapshot` (see
  /// [AttentionItem.spaceName]). Host-scoped like [_log]: a workspace id is one computer's
  /// name (R-11-044), so a second computer's snapshot must not rename the first one's rows.
  final Map<String, String> _spaceNames = <String, String>{};
  final StreamController<List<AttentionItem>> _attentionController =
      StreamController<List<AttentionItem>>.broadcast();
  final StreamController<List<NotificationItem>> _notificationsController =
      StreamController<List<NotificationItem>>.broadcast();
  final StreamController<String> _announcementController =
      StreamController<String>.broadcast();

  /// The Host the last [_emit] filtered [notifications] for, or `null` before the first one.
  /// A `tree_snapshot` or `RelayConnected` naming a different Host forces one emission even
  /// when it changes no row, so a listener mounted since before the switch receives the newly
  /// connected computer's log — its empty state included.
  String? _emittedHostId;

  /// The pane the terminal screen currently shows, or `null` when it is not the visible
  /// screen. Drives the [announcements] gate of R-30-714: only a live transition on *this*
  /// pane earns a spoken announcement. The Host is captured with the pane: two computers may
  /// share one pane id (R-11-044), so a late live event from the computer being switched away
  /// from must not announce over the newly connected one's open pane.
  String? _openPaneId;
  String? _openPaneHostId;

  /// Unread attention permitted by the known tree state (R-31-06-35).
  /// Entries span Hosts, newest first, with null timestamps last.
  Stream<List<AttentionItem>> get unseenAttention =>
      _attentionController.stream;

  /// The current value of [unseenAttention], for a caller that has not subscribed yet (a screen's
  /// first `build`).
  List<AttentionItem> get currentAttention => _unseen();

  /// The current Host's log, seen and unseen, ordered per R-31-07-02.
  /// `notifications_screen.dart` and the `app_shell.dart` badge share this log.
  /// [unseenAttention] spans Hosts for chooser badges and Host-filtered agent lists.
  Stream<List<NotificationItem>> get notifications =>
      _notificationsController.stream;

  /// The current value of [notifications].
  List<NotificationItem> get currentNotifications => _sortedLog();

  /// Every pane id each Host's last `tree_snapshot` held, keyed by Host id. Read by
  /// [paneClosedSinceSnapshot] alone. Host-scoped like [_log]: a snapshot of the computer
  /// being switched away from — queued behind a slow acknowledgement load — must not clobber
  /// the newly connected one's pane set.
  final Map<String, Set<String>> _snapshotPaneIdsByHost =
      <String, Set<String>>{};

  /// R-30-511's `pane closed` test for a notification tap: `true` when a `tree_snapshot` has
  /// arrived and does not hold [paneId]. `false` before any snapshot, so a tap still opens the
  /// pane and lets the terminal's own `Empty, pane gone` state answer. A `pane.closed`
  /// `tree_update` between two snapshots is not seen here (this file reacts to a full snapshot
  /// only, see the header); the terminal covers that gap the same way.
  bool paneClosedSinceSnapshot({
    required String hostId,
    required String paneId,
  }) {
    final ids = _snapshotPaneIdsByHost[hostId];
    return ids != null && !ids.contains(paneId);
  }

  void _onMessage(Message message) {
    switch (message) {
      case MessageAgentStatus(:final payload):
        _queue = _queue.then((_) => _onLiveAgentStatus(payload));
      case MessageTreeSnapshot(:final payload):
        // A `tree_snapshot` carries no Host id, so capture the connected Host at ARRIVAL. The
        // queue in front of this turn (a slow acknowledgement load) may outlive a Host
        // switch; reading `_currentHostId` only when the turn runs would attribute this
        // snapshot to the computer being switched TO.
        final hostId = _currentHostId() ?? '';
        _queue = _queue.then((_) => _onTreeSnapshot(payload, hostId));
      case MessageTreeUpdate(:final payload):
        final hostId = _currentHostId() ?? '';
        _queue = _queue.then((_) => _onTreeUpdate(payload, hostId));
      default:
        break;
    }
  }

  /// Loads [hostId]'s acknowledgements once. A read failure leaves the map empty: the log then
  /// behaves as a fresh session, which loses nothing but a read mark.
  Future<void> _loadAcks(String hostId) async {
    if (_acksHostId == hostId) return;
    _acks.clear();
    _acksHostId = hostId;
    final result = await _plainStore.notificationAcks(hostId);
    if (result is Ok<List<NotificationAck>> && _acksHostId == hostId) {
      for (final ack in result.value) {
        _acks[ack.paneId] = ack;
      }
    }
  }

  /// How an acknowledgement resolves a change with this identity: `null` when it is a genuinely
  /// newer change (no acknowledgement, a different status, or a later `at`) and the entry is
  /// unread; otherwise the acknowledged state, read or removed.
  NotificationAck? _ackFor(String paneId, AgentStatusKind status, String? at) {
    final ack = _acks[paneId];
    if (ack == null) return null;
    if (ack.status != status.name) return null;
    if (_compareAt(at, ack.at) > 0) return null;
    return ack;
  }

  /// Orders two RFC 3339 `at` values as instants, so mixed fractional precision from one Host
  /// (R-11-224 permits it) never misorders; falls back to a string compare when one does not
  /// parse. `null` sorts oldest.
  static int _compareAt(String? a, String? b) {
    final pa = a == null ? null : DateTime.tryParse(a);
    final pb = b == null ? null : DateTime.tryParse(b);
    if (pa != null && pb != null) return pa.compareTo(pb);
    return (a ?? '').compareTo(b ?? '');
  }

  /// Records the acknowledgement of [entry] for its Host in [PlainStore] first, and in memory
  /// only once that write succeeded, so this file never claims a persisted state it does not
  /// have. On success a removal also withdraws the native alert (R-31-07-04); the OS answer to
  /// that cancel is not part of the result, because the row's state does not depend on it.
  Future<Result<void>> _acknowledge(
    NotificationItem entry, {
    required bool removed,
  }) async {
    final ack = NotificationAck(
      hostId: entry.item.hostId,
      paneId: entry.item.paneId,
      status: entry.item.status.name,
      at: entry.item.at,
      removed: removed,
    );
    final result = await _plainStore.saveNotificationAck(ack);
    if (result is Err<void>) return result;
    if (ack.hostId == _acksHostId) _acks[ack.paneId] = ack;
    if (removed) {
      unawaited(
        _notifications.cancelAgentStatusNotification(
          hostId: ack.hostId,
          paneId: ack.paneId,
        ),
      );
    }
    return const Ok(null);
  }

  /// Applies one acknowledged transition to the log: [removed] drops the entry, otherwise it
  /// becomes read. Skipped when the entry changed underneath (a newer live event replaced it).
  Future<Result<void>> _transition(
    String key,
    NotificationItem entry, {
    required bool removed,
  }) async {
    final result = await _acknowledge(entry, removed: removed);
    if (result is Err<void>) return result;
    if (identical(_log[key], entry)) {
      if (removed) {
        _log.remove(key);
      } else {
        _log[key] = NotificationItem(item: entry.item, seen: true);
      }
      _emit();
    }
    return const Ok(null);
  }

  /// One-shot accessibility announcements (R-30-714, R-30-742): exactly one sentence when an
  /// agent on the currently open pane ([setOpenPane]) reaches `blocked` or `done`, and no other
  /// state change. This file holds no `SemanticsService`/`BuildContext`/`View` import, mirroring
  /// its own "no `BuildContext`" boundary (see this file's header): a widget that has a
  /// `BuildContext` (the terminal screen) subscribes to this stream and performs the real
  /// `SemanticsService.sendAnnouncement(View.of(context), sentence, TextDirection.ltr)` call
  /// after its own `MediaQuery.supportsAnnounceOf(context)` check — the exact pattern
  /// `pane_actions_sheet.dart`'s `_readLast20Lines` already uses for R-30-713.
  Stream<String> get announcements => _announcementController.stream;

  /// Sets which pane the terminal screen currently displays. `null` when the terminal screen is
  /// not the visible route. Viewing a pane counts as opening it, so a non-`null` [paneId] also
  /// runs [notePaneOpened]'s effects (R-30-503's marker clear, R-31-12-12's audience tracking) —
  /// a caller therefore makes exactly one call, not two, when a person opens a pane.
  void setOpenPane(String? paneId) {
    final hostId = paneId == null ? null : _currentHostId() ?? '';
    if (_openPaneId == paneId && _openPaneHostId == hostId) return;
    _openPaneId = paneId;
    _openPaneHostId = hostId;
    if (paneId != null) unawaited(notePaneOpened(paneId));
  }

  Future<void> _onLiveAgentStatus(AgentStatus status) async {
    if (status.status != AgentStatusKind.blocked &&
        status.status != AgentStatusKind.done) {
      return; // R-30-500: defence in depth; the Host already filters.
    }
    await _loadAcks(status.hostId);
    final ack = _ackFor(status.paneId, status.status, status.at);
    // Captured before the map below is written: R-30-714 announces once per genuinely new
    // transition, never a repeat `agent_status` for a pane this service already tracks unseen
    // (mirrors R-30-506/R-30-507's "collapse repeats" reasoning for the notification itself). A
    // pane whose earlier entry was already seen has genuinely changed again, so it announces.
    final key = _key(status.hostId, status.paneId);
    final isNewAttention = ack == null && _log[key]?.seen != false;
    final item = AttentionItem(
      hostId: status.hostId,
      paneId: status.paneId,
      workspaceId: status.workspaceId,
      tabId: status.tabId,
      spaceName: _spaceNames[_key(status.hostId, status.workspaceId)] ?? '',
      agentKind: status.agentKind,
      tabTitle: status.tabTitle,
      paneTitle: status.paneTitle,
      status: status.status,
      at: status.at,
    );
    if (ack == null) {
      _log[key] = NotificationItem(item: item, seen: false);
    } else if (ack.removed) {
      _log.remove(key);
    } else {
      _log[key] = NotificationItem(item: item, seen: true);
    }
    _emit();
    // Fire-and-forget: a live event posts a real OS notification. `NotificationsService` itself
    // classifies and swallows platform failures into a `Result`; this is a live stream handler
    // with no caller to report an `Err` to, so a failure here degrades to "no alert fired", never
    // to "no attention marker" (`_emit()` above already ran regardless).
    // R-30-506/R-30-507: an acknowledged identity is a repeat the person already answered, so
    // it earns no second native alert; only a genuinely newer change posts one.
    if (ack == null) {
      unawaited(_notifications.postAgentStatusNotification(status));
    }
    if (isNewAttention &&
        status.paneId == _openPaneId &&
        status.hostId == _openPaneHostId) {
      final sentence = status.status == AgentStatusKind.blocked
          ? '${status.agentKind} is blocked and waiting for you' // R-30-714's own example.
          : '${status.agentKind} is done';
      _announcementController.add(sentence);
    }
  }

  Future<void> _onTreeSnapshot(TreeSnapshot snapshot, String hostId) async {
    await _loadAcks(hostId);
    final panesById = {for (final pane in snapshot.panes) pane.paneId: pane};
    _panesByHost[hostId] = panesById;
    _snapshotPaneIdsByHost[hostId] = panesById.keys.toSet();
    final tabsById = {for (final tab in snapshot.tabs) tab.tabId: tab};
    final workspacesById = {
      for (final workspace in snapshot.workspaces)
        workspace.workspaceId: workspace,
    };
    for (final workspace in snapshot.workspaces) {
      // A workspace grouped under a parent takes the PARENT's name — the desktop sidebar's
      // own Space label; `space_id` names the parent, always present in the same snapshot.
      // Never `repo_name`: a custom-renamed workspace leaves it stale.
      final parent = workspace.spaceId == null
          ? null
          : workspacesById[workspace.spaceId];
      _spaceNames[_key(hostId, workspace.workspaceId)] =
          (parent ?? workspace).name;
    }
    var changed = false;
    for (final agent in snapshot.agents) {
      final kind = switch (agent.status) {
        'blocked' => AgentStatusKind.blocked,
        'done' => AgentStatusKind.done,
        _ => null,
      };
      if (kind == null) continue;
      final existing = _log[_key(hostId, agent.paneId)];
      if (existing != null &&
          existing.item.status == kind &&
          _compareAt(agent.statusAt, existing.item.at) <= 0) {
        // Keep the acknowledgement for the same or an older identity (R-30-513).
        // A newer identity falls through: a transition that happened while the app was
        // disconnected reaches it through this snapshot alone (R-31-12-09), so it re-adds unread.
        continue;
      }
      final ack = _ackFor(agent.paneId, kind, agent.statusAt);
      if (ack != null && ack.removed) {
        continue; // R-31-07-04: removed stays removed.
      }
      final pane = panesById[agent.paneId];
      final tab = pane == null ? null : tabsById[pane.tabId];
      _log[_key(hostId, agent.paneId)] = NotificationItem(
        item: AttentionItem(
          hostId: hostId,
          paneId: agent.paneId,
          workspaceId: pane?.workspaceId ?? '',
          tabId: pane?.tabId ?? '',
          spaceName: pane == null
              ? ''
              : _spaceNames[_key(hostId, pane.workspaceId)] ?? '',
          agentKind: agent.agentKind,
          tabTitle: tab?.title ?? '',
          paneTitle: pane?.title ?? '',
          status: kind,
          at: agent.statusAt,
        ),
        seen:
            ack !=
            null, // An acknowledged identity comes back read (R-31-07-03).
      );
      changed = true;
    }
    // R-30-513, R-22-024: this path never calls `postAgentStatusNotification`. A relaunch or a
    // reconnect resynchronises with `tree_request`/`tree_snapshot` alone; no system notification
    // is ever synthesised from it.
    // A snapshot of a DIFFERENT Host than the last emission filtered for also emits, changed
    // rows or not: the connected computer's log — its empty state included — must reach a
    // listener mounted since before the switch (R-30-946).
    if (changed || hostId != _emittedHostId) {
      _emit();
    } else {
      _attentionController.add(_unseen());
    }
  }

  void _onTreeUpdate(TreeUpdate update, String hostId) {
    switch (update.event) {
      case TreeEvent.paneCreated:
      case TreeEvent.paneUpdated:
      case TreeEvent.paneFocused:
      case TreeEvent.paneAgentStatusChanged:
        final pane = update.pane;
        if (pane == null) return;
        (_panesByHost[hostId] ??= {})[pane.paneId] = pane;
      case TreeEvent.paneClosed:
        final pane = update.pane;
        if (pane == null) return;
        (_panesByHost[hostId] ??= {}).remove(pane.paneId);
      case TreeEvent.tabClosed:
        final tab = update.tab;
        if (tab == null) return;
        (_panesByHost[hostId] ??= {}).removeWhere(
          (_, pane) => pane.tabId == tab.tabId,
        );
      case TreeEvent.workspaceClosed:
        final workspace = update.workspace;
        if (workspace == null) return;
        (_panesByHost[hostId] ??= {}).removeWhere(
          (_, pane) => pane.workspaceId == workspace.workspaceId,
        );
      default:
        return;
    }
    _attentionController.add(_unseen());
  }

  /// A successful (re)connect is the one explicit Host-identity moment this app has
  /// (`RelayConnection.lastHostInfo` is already set when `RelayConnected` fires). A connect
  /// to a DIFFERENT computer — `host_list.dart`'s `switchToHost` — re-emits at once: the log
  /// stream then carries the newly connected computer's rows, its empty state included,
  /// instead of leaving a pre-switch listener on the previous computer's list. A reconnect
  /// to the same computer changes nothing and emits nothing.
  void _onConnectionState(RelayConnectionState state) {
    if (state is RelayConnected && (_currentHostId() ?? '') != _emittedHostId) {
      _emit();
    }
  }

  /// Flags [paneId]'s entry seen (R-30-503, R-30-504, R-31-07-03): a screen calls this when a
  /// person opens that agent's pane, or taps `Mark as seen`/`Mark as read` on a swipe action.
  /// The entry stays in [notifications] as a read row, and its identity is acknowledged so a
  /// later `tree_snapshot` keeps it read. R-11-241: clear locally before the send.
  /// The result reports a local storage failure, not a Host reply.
  Future<Result<void>> markSeen(String paneId) {
    final key = _key(_currentHostId() ?? '', paneId);
    final entry = _log[key];
    if (entry != null && !entry.seen) {
      _log[key] = NotificationItem(item: entry.item, seen: true);
      _emit();
    }
    // R-11-240: send once, regardless of the pane's current status.
    send?.call(Message.markSeen(MarkSeen(paneId: paneId)));
    return entry == null || entry.seen
        ? Future.value(const Ok(null))
        : _acknowledge(entry, removed: false);
  }

  /// `Mark all as read` (R-31-07-03): flags every unread entry of the connected Host seen, each
  /// once its acknowledgement is stored. Returns the first failure, after every other row that
  /// could be stored has turned read.
  Future<Result<void>> markAllSeen() => _transitionAll(removed: false);

  /// `Remove` (R-31-07-04): drops [paneId]'s entry from the log, seen or not, once its identity
  /// is stored as removed so a later `tree_snapshot` does not bring it back. `Ok` and a no-op
  /// when the pane carries none.
  Future<Result<void>> remove(String paneId) {
    final key = _key(_currentHostId() ?? '', paneId);
    final entry = _log[key];
    if (entry == null) return Future.value(const Ok(null));
    return _transition(key, entry, removed: true);
  }

  /// `Remove all` (R-31-07-04): empties the connected Host's log, each entry once its removal is
  /// stored. Returns the first failure, after every other row that could be stored is gone.
  Future<Result<void>> removeAll() => _transitionAll(removed: true);

  Future<Result<void>> _transitionAll({required bool removed}) async {
    final own = _log.entries
        .where((e) => _isCurrentHost(e.value) && (removed || !e.value.seen))
        .toList();
    final results = await Future.wait(<Future<Result<void>>>[
      for (final e in own) _transition(e.key, e.value, removed: removed),
    ]);
    for (final r in results) {
      if (r is Err<void>) return r;
    }
    return const Ok(null);
  }

  /// [markSeen], plus records that this Device has opened [paneId] at least once, for
  /// [NotificationsService]'s `Only agents I have opened` audience filter (R-31-12-12). The
  /// terminal-open point calls this instead of [markSeen] directly when the clearing reason is
  /// genuinely "the pane was opened", not a bare swipe.
  Future<Result<void>> notePaneOpened(String paneId) {
    _notifications.notePaneOpened(paneId);
    return markSeen(paneId);
  }

  void _emit() {
    _emittedHostId = _currentHostId() ?? '';
    _attentionController.add(_unseen());
    _notificationsController.add(_sortedLog());
  }

  /// Spans every Host (R-03-046: `host_list_screen.dart` shows a disconnected computer's
  /// remembered attention on its own row), unlike [_sortedLog].
  List<AttentionItem> _unseen() => List.unmodifiable(<AttentionItem>[
    for (final entry in _sorted(_log.values))
      if (!entry.seen && _needsAttention(entry.item)) entry.item,
  ]);
  bool _needsAttention(AttentionItem item) {
    final panes = _panesByHost[item.hostId];
    if (panes == null) return true;
    final status = panes[item.paneId]?.agentStatus;
    return status == 'blocked' || status == 'done';
  }

  /// Most recent first, `null` `at` last (R-30-513's order, R-31-07-02).
  /// Every entry is keyed by Host and pane: a pane id such as `w3:p2` is one computer's name
  /// (R-11-044), so two computers may share one. [unseenAttention] spans every Host, because
  /// `host_list_screen.dart` shows the remembered attention of a disconnected computer on its own
  /// row (R-03-046); [notifications] and every action here cover the connected Host alone.
  static String _key(String hostId, String paneId) => '$hostId\u0000$paneId';

  bool _isCurrentHost(NotificationItem entry) =>
      entry.item.hostId == (_currentHostId() ?? '');

  List<NotificationItem> _sortedLog() =>
      _sorted(_log.values.where(_isCurrentHost));

  List<NotificationItem> _sorted(Iterable<NotificationItem> entries) {
    final items = entries.toList();
    items.sort((a, b) {
      final aAt = a.item.at;
      final bAt = b.item.at;
      if (aAt == null && bAt == null) return 0;
      if (aAt == null) return 1;
      if (bAt == null) return -1;
      return _compareAt(bAt, aAt); // Most recent first.
    });
    return List.unmodifiable(items);
  }

  void dispose() {
    unawaited(_subscription.cancel());
    unawaited(_stateSubscription.cancel());
    unawaited(_attentionController.close());
    unawaited(_notificationsController.close());
    unawaited(_announcementController.close());
  }
}

String? _noHostId() => null;
