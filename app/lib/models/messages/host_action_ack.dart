/// `host_action_ack` (`docs/11-relay-protocol.md` §4.17). Sender: Host.
/// Reply: no (reply to `host_action`). Correlation: yes. Mirrors
/// `HostActionAck` in
/// `crates/herdr-relay-proto/src/messages/action.rs:56-70`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import 'host_action_kind.dart';

part 'host_action_ack.freezed.dart';
part 'host_action_ack.g.dart';

@freezed
abstract class HostActionAck with _$HostActionAck {
  const factory HostActionAck({
    required HostActionKind action,
    required bool success,

    /// The pane acted on, for pane-scoped actions; for `pane.split`, the
    /// target (original) pane (R-11-205's sibling rule).
    @JsonKey(name: 'pane_id', includeIfNull: false) String? paneId,

    /// The id of the newly created entity, present on a successful create
    /// action (R-11-205).
    @JsonKey(name: 'result_id', includeIfNull: false) String? resultId,
  }) = _HostActionAck;

  factory HostActionAck.fromJson(Map<String, dynamic> json) =>
      _$HostActionAckFromJson(json);
}
