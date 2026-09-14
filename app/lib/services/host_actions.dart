/// The Host plugin actions service (`WP-18-f`, wave 9 of `docs/90-implementation-plan.md`),
/// driven from `docs/31-mockups/18-actions.md` and `docs/11-relay-protocol.md` §4.16, §4.17,
/// §4.24, §4.25: `action_list_request`/`action_list` (R-11-208 to R-11-211) to read the Host's
/// projected plugin action list, and `host_action`'s `plugin.invoke` kind (R-11-215 to
/// R-11-220) to run one.
///
/// Every function here takes a `Stream<Message>`, a `Stream<RelayConnectionState>` and a
/// [SendFrame] rather than a whole `RelayConnection`, mirroring `device_list.dart`'s own
/// established seam (see that file's header comment for why: `RelayConnection` opens a real
/// WebSocket internally with no injectable fake short of the full local-server harness).
/// `actions_screen.dart` is the one caller, and passes `connection.messages`,
/// `connection.connectionState` and `connection.send` straight through.
///
/// This file holds an [ActionListEntry] exactly as `action_list.dart`'s wire model already
/// projects it — `plugin_id`, `action_id`, `title`, `description`, `contexts` and nothing else
/// (R-30-964, R-11-209) — rather than inventing a second domain type: the freezed class has no
/// field for `command`, `manifest_path` or `plugin_root`, so a row built from it cannot leak
/// one even if a malformed `action_list` tried to carry it.
///
/// This file owns no screen: `actions_screen.dart` paints every state this file raises
/// (R-90-024).
library;

import 'dart:async';

import '../core/result/result.dart' show Err, Ok, Result;
import '../models/codes.dart';
import '../models/message.dart';
import '../models/messages/action_list_entry.dart';
import '../models/messages/action_list_request.dart';
import '../models/messages/host_action.dart';
import '../models/messages/host_action_kind.dart';
import 'relay.dart' show RelayConnected, RelayConnectionState;

/// The function shape `RelayConnection.send` already has; accepted here instead of the whole
/// connection object (see this file's own header comment).
typedef SendFrame = void Function(Message message, {String? corr});

/// What this phone is viewing when it opens `/hosts/:hostId/panes/:paneId/actions`: at most one
/// workspace, tab or pane, each with its display name for the scope sentence and breadcrumb of
/// R-31-18-05. Since 2026-09-09 (R-03-055) the pane action sheet's `Plugin actions` row is the
/// one entry, so `routing.dart` supplies the pane on screen, sourced from the tree snapshot per
/// R-31-18-05's own text. The default (every field `null`) is "the computer alone in scope",
/// the caller's fallback for a tree it could not read.
///
/// [surfaceId] is R-11-215's "at most one surface id" the Device sends with `plugin.invoke`:
/// the most specific of [paneId], [tabId] or [workspaceId].
class ActionScope {
  const ActionScope({
    this.workspaceId,
    this.workspaceName,
    this.tabId,
    this.tabName,
    this.paneId,
    this.paneName,
  });

  final String? workspaceId;
  final String? workspaceName;
  final String? tabId;
  final String? tabName;
  final String? paneId;
  final String? paneName;

  /// The context word set the current scope satisfies, per the context-gating table of
  /// `docs/31-mockups/18-actions.md`: `global` and `workspace` are always satisfied — "a
  /// paired phone is always on one computer" — `tab` needs a tab or a pane in view, `pane`
  /// needs a pane, and `selection` is never satisfied in version one (R-31-18-07).
  Set<String> get _satisfiedContexts => <String>{
    'global',
    'workspace',
    if (tabId != null || paneId != null) 'tab',
    if (paneId != null) 'pane',
  };

  /// R-11-215's one surface id: the most specific of [paneId], [tabId], [workspaceId].
  ({String? paneId, String? tabId, String? workspaceId}) get surfaceId =>
      paneId != null
      ? (paneId: paneId, tabId: null, workspaceId: null)
      : tabId != null
      ? (paneId: null, tabId: tabId, workspaceId: null)
      : (paneId: null, tabId: null, workspaceId: workspaceId);
}

/// The result of [gateActions]: [visible] is what R-31-18-04 groups and draws, already stripped
/// of the whole `herdr-relay` plugin (R-31-18-16) and of every row R-30-966 hides for the
/// current [ActionScope]; [hiddenByScopeCount] is the exact count the hidden-row line of
/// R-31-18-06 reports — it excludes the `herdr-relay` removal, which R-31-18-16 says MUST NOT
/// be counted there.
class GatedActions {
  const GatedActions({required this.visible, required this.hiddenByScopeCount});
  final List<ActionListEntry> visible;
  final int hiddenByScopeCount;
}

/// Filters and gates [entries] for [scope], per R-30-966, R-11-211 and R-31-18-16. An absent
/// `contexts` is treated as `['global']` (R-11-211), defensively, even though the Host already
/// normalizes it before the wire (R-10-057).
GatedActions gateActions(List<ActionListEntry> entries, ActionScope scope) {
  final List<ActionListEntry> nonRelay = entries
      .where((ActionListEntry e) => e.pluginId != 'herdr-relay')
      .toList();
  final Set<String> satisfied = scope._satisfiedContexts;
  final List<ActionListEntry> visible = nonRelay.where((ActionListEntry e) {
    final List<String> contexts = e.contexts ?? const <String>['global'];
    return contexts.any(satisfied.contains);
  }).toList();
  return GatedActions(
    visible: visible,
    hiddenByScopeCount: nonRelay.length - visible.length,
  );
}

int _corrSeq = 0;

/// A correlation id for one outgoing request (R-11-034), matching `device_list.dart`'s own
/// per-file counter: this client cannot read `corr` back off an incoming reply, so every
/// function below matches a reply by its message type instead.
String _nextCorr() => 'host-actions-${_corrSeq++}';

/// Races [messages] for the first message [onMessage] accepts against [connectionState] for a
/// transition off [RelayConnected] — mirrors `device_list.dart`'s own `_awaitReply` exactly,
/// including its documented reason for a fire-and-forget cancel (see that file for the full
/// explanation). Returns `null` on a drop.
Future<T?> _awaitReply<T>({
  required Stream<Message> messages,
  required Stream<RelayConnectionState> connectionState,
  required T? Function(Message) onMessage,
}) async {
  final Completer<T?> completer = Completer<T?>();
  void finish(T? value) {
    if (!completer.isCompleted) completer.complete(value);
  }

  final StreamSubscription<Message> messageSub = messages.listen((
    Message message,
  ) {
    final T? result = onMessage(message);
    if (result != null) finish(result);
  });
  final StreamSubscription<RelayConnectionState> stateSub = connectionState
      .listen((RelayConnectionState state) {
        if (state is! RelayConnected) finish(null);
      });
  try {
    return await completer.future;
  } finally {
    unawaited(messageSub.cancel());
    unawaited(stateSub.cancel());
  }
}

/// Requests the Host's plugin action list (`action_list_request`, R-11-208) and awaits
/// `action_list`. `Err` covers both an `error` reply and a dropped link.
Future<Result<List<ActionListEntry>>> fetchActionList({
  required Stream<Message> messages,
  required Stream<RelayConnectionState> connectionState,
  required SendFrame send,
}) async {
  send(const Message.actionListRequest(ActionListRequest()), corr: _nextCorr());
  final Result<List<ActionListEntry>>? reply =
      await _awaitReply<Result<List<ActionListEntry>>>(
        messages: messages,
        connectionState: connectionState,
        onMessage: (Message message) => switch (message) {
          MessageActionList(:final payload) => Ok(payload.actions),
          MessageError(:final payload) => Err(payload.message),
          _ => null,
        },
      );
  return reply ??
      const Err('read the plugin action list: the connection dropped');
}

/// Session-scoped cache of the plugin action list (R-11-208): the one caller
/// (`actions_screen.dart`) calls [refresh] once to populate it, then this class re-requests
/// automatically on every reconnect and whenever the caller reports a stale plugin through
/// [notePluginDisabled]. The reconnect listener never duplicates that first call: entering this
/// screen's route requires an already-live connection (R-30-946), so the first
/// [RelayConnected] this class ever observes after construction is a real reconnect, never the
/// initial connect.
class ActionListCache {
  ActionListCache({
    required this._messages,
    required this._connectionState,
    required this._send,
  }) {
    _connectionSub = _connectionState.listen((RelayConnectionState state) {
      if (state is RelayConnected) unawaited(refresh());
    });
  }

  final Stream<Message> _messages;
  final Stream<RelayConnectionState> _connectionState;
  final SendFrame _send;
  late final StreamSubscription<RelayConnectionState> _connectionSub;
  final StreamController<Result<List<ActionListEntry>>> _controller =
      StreamController<Result<List<ActionListEntry>>>.broadcast();

  /// Every [fetchActionList] outcome this cache has produced, including the ones [refresh]
  /// itself triggered from a reconnect.
  Stream<Result<List<ActionListEntry>>> get results => _controller.stream;

  /// Re-requests `action_list_request` and publishes the outcome on [results]. Also the one
  /// `Refresh actions` control's job (R-31-18-09, R-31-18-15): re-reading the list is the whole
  /// of this file's own reconciliation; the tree-snapshot half those two rules also name is
  /// `tree.dart`'s live subscription staying current on its own (R-11-043), not a second read
  /// this file needs to trigger.
  Future<Result<List<ActionListEntry>>> refresh() async {
    final Result<List<ActionListEntry>> result = await fetchActionList(
      messages: _messages,
      connectionState: _connectionState,
      send: _send,
    );
    _controller.add(result);
    return result;
  }

  /// R-11-208's error-driven refresh: call after an invocation returns `plugin_disabled`.
  void notePluginDisabled() => unawaited(refresh());

  void dispose() {
    unawaited(_connectionSub.cancel());
    unawaited(_controller.close());
  }
}

/// One outcome of a `plugin.invoke` `host_action` (R-30-518): the Host applied it, the Host
/// refused it, or the acknowledgement never arrived.
sealed class InvokeOutcome {
  const InvokeOutcome();
}

/// The Host applied the invocation (R-11-217). [paneId] is present only when the Host could
/// attribute a resulting pane with confidence (R-11-217a); absent covers both "no pane
/// appeared" and "the toggle closed one" (R-11-217b) — the caller MUST NOT read absence as
/// failure.
final class InvokeSucceeded extends InvokeOutcome {
  const InvokeSucceeded({this.paneId});
  final String? paneId;
}

/// The Host refused the invocation. [code] and [message] are the raw `error` frame
/// (R-30-803): [code] is `plugin_disabled` (R-11-218) or `action_unknown` (R-11-219) in the
/// documented cases, and any other code the Herdr call itself might surface.
final class InvokeRefused extends InvokeOutcome {
  const InvokeRefused(this.code, this.message);
  final ErrorCode code;
  final String message;
}

/// The link dropped before `host_action_ack` arrived (R-30-518, R-31-18-15). The caller MUST
/// NOT re-send the invocation; `ActionListCache.refresh` is the only reconciliation.
final class InvokeOutcomeUnknown extends InvokeOutcome {
  const InvokeOutcomeUnknown();
}

/// Invokes one plugin action (`plugin.invoke` via `host_action`, R-11-215 to R-11-220). Sends
/// at most one surface id from [scope] (R-11-215); the Host builds the rest of
/// `PluginInvocationContext` itself and the Device MUST NOT try to set any of it (R-11-216),
/// which is exactly why this function's own signature carries only [pluginId], [actionId] and
/// [scope] and nothing resembling `selectedText` or a Herdr path.
Future<InvokeOutcome> invokeAction({
  required Stream<Message> messages,
  required Stream<RelayConnectionState> connectionState,
  required SendFrame send,
  required String pluginId,
  required String actionId,
  required ActionScope scope,
}) async {
  final surface = scope.surfaceId;
  send(
    Message.hostAction(
      HostAction(
        action: HostActionKind.pluginInvoke,
        pluginId: pluginId,
        actionId: actionId,
        workspaceId: surface.workspaceId,
        tabId: surface.tabId,
        paneId: surface.paneId,
      ),
    ),
    corr: _nextCorr(),
  );
  final InvokeOutcome? outcome = await _awaitReply<InvokeOutcome>(
    messages: messages,
    connectionState: connectionState,
    onMessage: (Message message) => switch (message) {
      MessageHostActionAck(:final payload)
          when payload.action == HostActionKind.pluginInvoke &&
              payload.success =>
        InvokeSucceeded(paneId: payload.paneId),
      MessageError(:final payload) => InvokeRefused(
        payload.code,
        payload.message,
      ),
      _ => null,
    },
  );
  return outcome ?? const InvokeOutcomeUnknown();
}
