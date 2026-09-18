/// `send_input_ack` (`docs/11-relay-protocol.md` §4.12a). Sender: Host.
/// Reply: no (reply to `send_input`). Correlation: yes. Carries no pane
/// content (R-11-227). Mirrors `SendInputAck` in
/// `crates/herdr-relay-proto/src/messages/input.rs:21-27`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'send_input_ack.freezed.dart';
part 'send_input_ack.g.dart';

@freezed
abstract class SendInputAck with _$SendInputAck {
  const factory SendInputAck({
    @JsonKey(name: 'pane_id') required String paneId,
    required bool accepted,

    /// True on the first of the two acks of a held submit (R-11-253). Absent
    /// otherwise, like the Rust `skip_serializing_if` default.
    @JsonKey(includeIfNull: false) bool? queued,
  }) = _SendInputAck;

  factory SendInputAck.fromJson(Map<String, dynamic> json) =>
      _$SendInputAckFromJson(json);
}
