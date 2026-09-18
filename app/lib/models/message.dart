/// The application message union that travels inside the frame envelope's
/// `payload` (`docs/11-relay-protocol.md` §4, R-11-030, R-20-010). Mirrors
/// `Message` in `crates/herdr-relay-proto/src/messages.rs:39-108`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
///
/// Unlike a typical `freezed` union, this type is not itself
/// `fromJson`/`toJson`-serializable through the generator: the wire splits
/// the discriminator (`type`) and the data (`payload`) across two
/// [Frame] fields rather than folding them into one flat JSON object
/// (`freezed`'s default union codec expects a `runtimeType` key inside a
/// single object). [messageFromTypeAndPayload] and [MessageWire] hand-write
/// that split, mirroring `Frame::wrap`/`Frame::message` in
/// `crates/herdr-relay-proto/src/frame.rs:57-92` and `Message::type_name` in
/// `crates/herdr-relay-proto/src/messages.rs:74-108`.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import 'messages/action_list.dart';
import 'messages/action_list_request.dart';
import 'messages/agent_prompt.dart';
import 'messages/agent_prompt_ack.dart';
import 'messages/agent_status.dart';
import 'messages/device_info.dart';
import 'messages/device_list.dart';
import 'messages/device_list_request.dart';
import 'messages/disconnect.dart';
import 'messages/error_message.dart';
import 'messages/host_action.dart';
import 'messages/host_action_ack.dart';
import 'messages/host_info.dart';
import 'messages/host_theme.dart';
import 'messages/mark_seen.dart';
import 'messages/pane_frame.dart';
import 'messages/ping.dart';
import 'messages/pong.dart';
import 'messages/revoke_device.dart';
import 'messages/revoke_result.dart';
import 'messages/scroll_request.dart';
import 'messages/scroll_response.dart';
import 'messages/send_input.dart';
import 'messages/send_input_ack.dart';
import 'messages/tree_request.dart';
import 'messages/tree_snapshot.dart';
import 'messages/tree_update.dart';
import 'messages/unwatch_pane.dart';
import 'messages/watch_ack.dart';
import 'messages/watch_pane.dart';

part 'message.freezed.dart';

/// One application message, tagged by its wire `type` string. Mirrors the
/// 26-variant `Message` enum in
/// `crates/herdr-relay-proto/src/messages.rs:45-72`.
@freezed
sealed class Message with _$Message {
  const factory Message.hostInfo(HostInfo payload) = MessageHostInfo;
  const factory Message.hostTheme(HostTheme payload) = MessageHostTheme;
  const factory Message.deviceInfo(DeviceInfo payload) = MessageDeviceInfo;
  const factory Message.treeRequest(TreeRequest payload) = MessageTreeRequest;
  const factory Message.treeSnapshot(TreeSnapshot payload) =
      MessageTreeSnapshot;
  const factory Message.treeUpdate(TreeUpdate payload) = MessageTreeUpdate;
  const factory Message.watchPane(WatchPane payload) = MessageWatchPane;
  const factory Message.watchAck(WatchAck payload) = MessageWatchAck;
  const factory Message.unwatchPane(UnwatchPane payload) = MessageUnwatchPane;
  const factory Message.paneFrame(PaneFrame payload) = MessagePaneFrame;
  const factory Message.scrollRequest(ScrollRequest payload) =
      MessageScrollRequest;
  const factory Message.scrollResponse(ScrollResponse payload) =
      MessageScrollResponse;
  const factory Message.sendInput(SendInput payload) = MessageSendInput;
  const factory Message.sendInputAck(SendInputAck payload, {String? corr}) =
      MessageSendInputAck;
  const factory Message.agentStatus(AgentStatus payload) = MessageAgentStatus;
  const factory Message.markSeen(MarkSeen payload) = MessageMarkSeen;
  const factory Message.agentPrompt(AgentPrompt payload) = MessageAgentPrompt;
  const factory Message.agentPromptAck(AgentPromptAck payload) =
      MessageAgentPromptAck;
  const factory Message.hostAction(HostAction payload) = MessageHostAction;
  const factory Message.hostActionAck(HostActionAck payload) =
      MessageHostActionAck;
  const factory Message.deviceListRequest(DeviceListRequest payload) =
      MessageDeviceListRequest;
  const factory Message.deviceList(DeviceList payload) = MessageDeviceList;
  const factory Message.revokeDevice(RevokeDevice payload) =
      MessageRevokeDevice;
  const factory Message.revokeResult(RevokeResult payload) =
      MessageRevokeResult;
  const factory Message.error(ErrorMessage payload, {String? corr}) =
      MessageError;
  const factory Message.ping(Ping payload) = MessagePing;
  const factory Message.pong(Pong payload, {String? corr}) = MessagePong;
  const factory Message.disconnect(Disconnect payload) = MessageDisconnect;
  const factory Message.actionListRequest(ActionListRequest payload) =
      MessageActionListRequest;
  const factory Message.actionList(ActionList payload) = MessageActionList;
}

/// Recovers the typed [Message] a [Frame]'s `type` and `payload` describe.
/// Mirrors `Frame::message` in
/// `crates/herdr-relay-proto/src/frame.rs:83-92`.
///
/// Throws a [FormatException] for an unknown `type`, per R-41-037: a
/// validation failure MUST produce a typed error, never a silent default.
Message messageFromTypeAndPayload(
  String type,
  Map<String, dynamic> payload, {
  String? corr,
}) {
  return switch (type) {
    'host_info' => Message.hostInfo(HostInfo.fromJson(payload)),
    'host_theme' => Message.hostTheme(HostTheme.fromJson(payload)),
    'device_info' => Message.deviceInfo(DeviceInfo.fromJson(payload)),
    'tree_request' => Message.treeRequest(TreeRequest.fromJson(payload)),
    'tree_snapshot' => Message.treeSnapshot(TreeSnapshot.fromJson(payload)),
    'tree_update' => Message.treeUpdate(TreeUpdate.fromJson(payload)),
    'watch_pane' => Message.watchPane(WatchPane.fromJson(payload)),
    'watch_ack' => Message.watchAck(WatchAck.fromJson(payload)),
    'unwatch_pane' => Message.unwatchPane(UnwatchPane.fromJson(payload)),
    'pane_frame' => Message.paneFrame(PaneFrame.fromJson(payload)),
    'scroll_request' => Message.scrollRequest(ScrollRequest.fromJson(payload)),
    'scroll_response' => Message.scrollResponse(
      ScrollResponse.fromJson(payload),
    ),
    'send_input' => Message.sendInput(SendInput.fromJson(payload)),
    'send_input_ack' => Message.sendInputAck(
      SendInputAck.fromJson(payload),
      corr: corr,
    ),
    'ping' => Message.ping(Ping.fromJson(payload)),
    'pong' => Message.pong(Pong.fromJson(payload), corr: corr),
    'agent_status' => Message.agentStatus(AgentStatus.fromJson(payload)),
    'mark_seen' => Message.markSeen(MarkSeen.fromJson(payload)),
    'agent_prompt' => Message.agentPrompt(AgentPrompt.fromJson(payload)),
    'agent_prompt_ack' => Message.agentPromptAck(
      AgentPromptAck.fromJson(payload),
    ),
    'host_action' => Message.hostAction(HostAction.fromJson(payload)),
    'host_action_ack' => Message.hostActionAck(HostActionAck.fromJson(payload)),
    'device_list_request' => Message.deviceListRequest(
      DeviceListRequest.fromJson(payload),
    ),
    'device_list' => Message.deviceList(DeviceList.fromJson(payload)),
    'revoke_device' => Message.revokeDevice(RevokeDevice.fromJson(payload)),
    'revoke_result' => Message.revokeResult(RevokeResult.fromJson(payload)),
    'error' => Message.error(ErrorMessage.fromJson(payload), corr: corr),
    'disconnect' => Message.disconnect(Disconnect.fromJson(payload)),
    'action_list_request' => Message.actionListRequest(
      ActionListRequest.fromJson(payload),
    ),
    'action_list' => Message.actionList(ActionList.fromJson(payload)),
    _ => throw FormatException('unknown message type: $type'),
  };
}

/// The wire `type` string and JSON `payload` for a [Message]. Mirrors
/// `Message::type_name` in `crates/herdr-relay-proto/src/messages.rs:74-108`
/// and the payload half of `Frame::wrap` in
/// `crates/herdr-relay-proto/src/frame.rs:64-81`.
extension MessageWire on Message {
  /// The wire `type` string for this message, exactly as it appears in a
  /// frame envelope's `type` field.
  String get typeName => switch (this) {
    MessageHostInfo() => 'host_info',
    MessageHostTheme() => 'host_theme',
    MessageDeviceInfo() => 'device_info',
    MessageTreeRequest() => 'tree_request',
    MessageTreeSnapshot() => 'tree_snapshot',
    MessageTreeUpdate() => 'tree_update',
    MessageWatchPane() => 'watch_pane',
    MessageWatchAck() => 'watch_ack',
    MessageUnwatchPane() => 'unwatch_pane',
    MessagePaneFrame() => 'pane_frame',
    MessageScrollRequest() => 'scroll_request',
    MessageScrollResponse() => 'scroll_response',
    MessageSendInput() => 'send_input',
    MessageSendInputAck() => 'send_input_ack',
    MessagePing() => 'ping',
    MessagePong() => 'pong',
    MessageAgentStatus() => 'agent_status',
    MessageAgentPrompt() => 'agent_prompt',
    MessageMarkSeen() => 'mark_seen',
    MessageAgentPromptAck() => 'agent_prompt_ack',
    MessageHostAction() => 'host_action',
    MessageHostActionAck() => 'host_action_ack',
    MessageDeviceListRequest() => 'device_list_request',
    MessageDeviceList() => 'device_list',
    MessageRevokeDevice() => 'revoke_device',
    MessageRevokeResult() => 'revoke_result',
    MessageError() => 'error',
    MessageDisconnect() => 'disconnect',
    MessageActionListRequest() => 'action_list_request',
    MessageActionList() => 'action_list',
  };

  /// This message's payload, serialized to JSON. Matches the `payload`
  /// field `Frame::wrap` would produce for this message.
  Map<String, dynamic> get payloadJson => switch (this) {
    MessageHostInfo(:final payload) => payload.toJson(),
    MessageHostTheme(:final payload) => payload.toJson(),
    MessageDeviceInfo(:final payload) => payload.toJson(),
    MessageTreeRequest(:final payload) => payload.toJson(),
    MessageTreeSnapshot(:final payload) => payload.toJson(),
    MessageTreeUpdate(:final payload) => payload.toJson(),
    MessageWatchPane(:final payload) => payload.toJson(),
    MessageWatchAck(:final payload) => payload.toJson(),
    MessageUnwatchPane(:final payload) => payload.toJson(),
    MessagePaneFrame(:final payload) => payload.toJson(),
    MessageScrollRequest(:final payload) => payload.toJson(),
    MessageScrollResponse(:final payload) => payload.toJson(),
    MessageSendInput(:final payload) => payload.toJson(),
    MessageSendInputAck(:final payload) => payload.toJson(),
    MessagePing(:final payload) => payload.toJson(),
    MessagePong(:final payload) => payload.toJson(),
    MessageAgentStatus(:final payload) => payload.toJson(),
    MessageAgentPrompt(:final payload) => payload.toJson(),
    MessageMarkSeen(:final payload) => payload.toJson(),
    MessageAgentPromptAck(:final payload) => payload.toJson(),
    MessageHostAction(:final payload) => payload.toJson(),
    MessageHostActionAck(:final payload) => payload.toJson(),
    MessageDeviceListRequest(:final payload) => payload.toJson(),
    MessageDeviceList(:final payload) => payload.toJson(),
    MessageRevokeDevice(:final payload) => payload.toJson(),
    MessageRevokeResult(:final payload) => payload.toJson(),
    MessageError(:final payload) => payload.toJson(),
    MessageDisconnect(:final payload) => payload.toJson(),
    MessageActionListRequest(:final payload) => payload.toJson(),
    MessageActionList(:final payload) => payload.toJson(),
  };
}
