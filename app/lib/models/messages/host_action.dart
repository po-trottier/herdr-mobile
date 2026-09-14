/// `host_action` (`docs/11-relay-protocol.md` §4.16). Sender: Device.
/// Reply: `host_action_ack`. Correlation: yes. Mirrors `HostAction` in
/// `crates/herdr-relay-proto/src/messages/action.rs:12-27`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
///
/// `params` is action-specific (R-11-201's field table); the bridge
/// validates its shape per action before forwarding to Herdr. The Device
/// MUST send `focus: false` in every create action inside `params`
/// (R-11-203).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import 'host_action_kind.dart';

part 'host_action.freezed.dart';
part 'host_action.g.dart';

@freezed
abstract class HostAction with _$HostAction {
  const factory HostAction({
    required HostActionKind action,
    @JsonKey(name: 'pane_id', includeIfNull: false) String? paneId,
    @JsonKey(name: 'workspace_id', includeIfNull: false) String? workspaceId,
    @JsonKey(name: 'tab_id', includeIfNull: false) String? tabId,
    @JsonKey(name: 'plugin_id', includeIfNull: false) String? pluginId,
    @JsonKey(name: 'action_id', includeIfNull: false) String? actionId,
    @JsonKey(includeIfNull: false) Map<String, dynamic>? params,
  }) = _HostAction;

  factory HostAction.fromJson(Map<String, dynamic> json) =>
      _$HostActionFromJson(json);
}
