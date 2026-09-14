/// `host_action`/`host_action_ack` request-reply plumbing (`docs/11-relay-protocol.md`
/// §4.16-4.17, `docs/90-implementation-plan.md` `WP-18-d`), shared by the create menu
/// (`create_sheet.dart`, this package's own path) and the terminal screen's `Close pane`
/// (`terminal_screen.dart` sends [closePane] after `pane_actions_sheet.dart`'s confirmation).
/// Every function here takes a `Stream<Message>`, a `Stream<RelayConnectionState>` and a
/// `SendFrame` rather than a whole `RelayConnection`, mirroring `device_list.dart`'s own
/// reasoning: no fake short of the full local-server transport harness exists for
/// `RelayConnection` itself, and this file's own logic — matching a reply by type, racing it
/// against a connection drop, never resending a non-idempotent action — has nothing to do with
/// that transport.
///
/// This file owns no screen (R-90-024). Callers show action outcomes and choose navigation.
library;

import 'dart:async';

import '../core/result/result.dart' show Err, Ok, Result;
import '../models/message.dart';
import '../models/messages/host_action.dart';
import '../models/messages/host_action_ack.dart';
import '../models/messages/host_action_kind.dart';
import '../models/messages/tree_request.dart';
import '../models/messages/tree_snapshot.dart';
import 'device_list.dart' show SendFrame;
import 'relay.dart'
    show RelayConnected, RelayConnectionState, RelayNotConnectedException;

/// The one text every send-on-a-dead-link path reports (R-30-807's offline wording family).
const String notConnectedMessage =
    'Not connected to this computer. Reconnect, then try again.';

/// One outcome of a `host_action` request (`docs/30-ux-spec.md` R-30-518): the Host applied
/// it, the Host refused it, or the acknowledgement never arrived. Mirrors `device_list.dart`'s
/// `RevokeOutcome` three-variant shape for the same reason: `Result<T>`'s plain Ok/Err cannot
/// express the third case.
sealed class HostActionOutcome {
  const HostActionOutcome();
}

/// The Host applied the action. [ack] carries `result_id` on a create action (R-11-205) and
/// `pane_id` on a pane-scoped action, per §4.17's own field table.
final class HostActionApplied extends HostActionOutcome {
  const HostActionApplied(this.ack);
  final HostActionAck ack;
}

/// The Host refused the action. [message] is its raw `error` text (R-30-803). Nothing
/// changed, so the outcome is known and a further attempt is safe at once.
final class HostActionRefused extends HostActionOutcome {
  const HostActionRefused(this.message);
  final String message;
}

/// The link dropped before `host_action_ack` arrived (R-30-518). Every action this file sends
/// is non-idempotent (R-31-10-11, R-31-17-07): a repeat can split a second pane, rename over a
/// second edit, or create a second workspace. The caller MUST NOT resend the action and MUST
/// reconcile with [reconcileTree] instead.
final class HostActionOutcomeUnknown extends HostActionOutcome {
  const HostActionOutcomeUnknown();
}

int _corrSeq = 0;

/// A correlation id for one outgoing request (R-11-034). Mirrors `device_list.dart`'s own
/// per-file counter: this client cannot read `corr` back off an incoming reply (`relay.dart`'s
/// `messages` stream strips the frame envelope), so every function below matches a reply by
/// its message type instead.
String _nextCorr() => 'pane-actions-${_corrSeq++}';

/// Races [messages] for the first message [onMessage] accepts against [connectionState] for a
/// transition off [RelayConnected]. Returns `null` on a drop. Duplicated from
/// `device_list.dart`'s own private helper of the same shape rather than shared, since that
/// one is private to its file; see its doc comment for the full reasoning, including why a
/// fire-and-forget `cancel()` is correct here.
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

/// Sends [action] and awaits its `host_action_ack` (§4.16-4.17). Every function below is a
/// thin, named wrapper over this one, per action kind.
Future<HostActionOutcome> sendHostAction({
  required Stream<Message> messages,
  required Stream<RelayConnectionState> connectionState,
  required SendFrame send,
  required HostAction action,
}) async {
  // A tap can land while the link is down (`Offline. Showing what we last saw.`), and
  // `RelayConnection.send` throws a `RelayNotConnectedException` then. Nothing left the phone,
  // so the outcome is known: refused, and the person can retry once reconnected (measured
  // 2026-09-04: the create control looked inert because this throw escaped the tap handler).
  try {
    send(Message.hostAction(action), corr: _nextCorr());
  } on RelayNotConnectedException {
    return const HostActionRefused(notConnectedMessage);
  }
  final HostActionOutcome? outcome = await _awaitReply<HostActionOutcome>(
    messages: messages,
    connectionState: connectionState,
    onMessage: (message) => switch (message) {
      MessageHostActionAck(:final payload) => HostActionApplied(payload),
      MessageError(:final payload) => HostActionRefused(payload.message),
      _ => null,
    },
  );
  return outcome ?? const HostActionOutcomeUnknown();
}

/// `workspace.create` (R-11-202). `focus` is always sent `false` (R-11-203, R-30-952): a
/// phone MUST NOT steal focus on the workstation.
Future<HostActionOutcome> createWorkspace({
  required Stream<Message> messages,
  required Stream<RelayConnectionState> connectionState,
  required SendFrame send,
}) => sendHostAction(
  messages: messages,
  connectionState: connectionState,
  send: send,
  action: const HostAction(
    action: HostActionKind.workspaceCreate,
    params: <String, dynamic>{'focus': false},
  ),
);

/// `tab.create` in [workspaceId] (R-11-202, R-31-17-02). `focus` is always sent `false`.
/// [workspaceId] is optional per §4.16's own field table: absent, the Host resolves its own
/// default, which the create menu never relies on (R-31-17-02 always resolves one first).
Future<HostActionOutcome> createTab({
  required Stream<Message> messages,
  required Stream<RelayConnectionState> connectionState,
  required SendFrame send,
  String? workspaceId,
}) => sendHostAction(
  messages: messages,
  connectionState: connectionState,
  send: send,
  action: HostAction(
    action: HostActionKind.tabCreate,
    workspaceId: workspaceId,
    params: const <String, dynamic>{'focus': false},
  ),
);

/// Splits [targetPaneId] toward [direction] (`right` or `down`, R-03-134).
/// The terminal action sheet offers this action. `focus` stays `false` on the Host.
Future<HostActionOutcome> createPaneSplit({
  required Stream<Message> messages,
  required Stream<RelayConnectionState> connectionState,
  required SendFrame send,
  required String targetPaneId,
  required String direction,
}) => sendHostAction(
  messages: messages,
  connectionState: connectionState,
  send: send,
  action: HostAction(
    action: HostActionKind.paneSplit,
    paneId: targetPaneId,
    params: <String, dynamic>{'focus': false, 'direction': direction},
  ),
);

/// Closes pane [paneId] (`close`, R-11-202). The confirmation this action needs
/// (`docs/31-mockups/10-pane-actions.md` R-31-10-01) is `pane_actions_sheet.dart`'s own
/// responsibility (R-90-024): this function sends the request only, once the caller has
/// already confirmed.
Future<HostActionOutcome> closePane({
  required Stream<Message> messages,
  required Stream<RelayConnectionState> connectionState,
  required SendFrame send,
  required String paneId,
}) => sendHostAction(
  messages: messages,
  connectionState: connectionState,
  send: send,
  action: HostAction(action: HostActionKind.close, paneId: paneId),
);

/// Reconciles an unknown outcome by reading a fresh `tree_snapshot` (R-30-518, R-31-17-07,
/// R-31-10-11): "For anything the tree holds, that read is `tree_request`... which exist for
/// exactly this purpose." Never resends the original action. `Err` covers both an `error`
/// reply and a second dropped link; R-30-518 exempts a read from the no-retry rule, but only a
/// person's own `Check now` press triggers the next one — this function itself does not loop.
Future<Result<TreeSnapshot>> reconcileTree({
  required Stream<Message> messages,
  required Stream<RelayConnectionState> connectionState,
  required SendFrame send,
}) async {
  try {
    send(const Message.treeRequest(TreeRequest()), corr: _nextCorr());
  } on RelayNotConnectedException {
    return const Err(notConnectedMessage);
  }
  final Result<TreeSnapshot>? reply = await _awaitReply<Result<TreeSnapshot>>(
    messages: messages,
    connectionState: connectionState,
    onMessage: (message) => switch (message) {
      MessageTreeSnapshot(:final payload) => Ok(payload),
      MessageError(:final payload) => Err(payload.message),
      _ => null,
    },
  );
  return reply ?? const Err('read the current tree: the connection dropped');
}
