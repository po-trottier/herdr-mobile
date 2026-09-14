/// The frame envelope that wraps every application message inside the Noise
/// session (`docs/11-relay-protocol.md` §3, R-11-030, R-20-010). Mirrors
/// `Frame` in `crates/herdr-relay-proto/src/frame.rs:21-37`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`). The relay never sees
/// this envelope.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'frame.freezed.dart';
part 'frame.g.dart';

/// The current relay protocol version (R-11-032). Mirrors
/// `PROTOCOL_VERSION` in `crates/herdr-relay-proto/src/frame.rs:15`.
const int frameProtocolVersion = 1;

/// The JSON envelope every frame carries inside the Noise session
/// (R-11-031). Mirrors `Frame` in
/// `crates/herdr-relay-proto/src/frame.rs:21-37`.
@freezed
abstract class Frame with _$Frame {
  const factory Frame({
    /// Protocol version. MUST be `1` (R-11-032).
    required int v,

    /// Message type discriminator. See `docs/11-relay-protocol.md` §4.
    required String type,

    /// Monotonic sequence number per sender, starting at `1` (R-11-033,
    /// R-11-080).
    required int seq,

    /// Correlation id for request-reply pairs. The requester generates it;
    /// the replier echoes it. Absent on unsolicited messages (R-11-034).
    @JsonKey(includeIfNull: false) String? corr,

    /// Message-specific fields. May be `{}` when the message carries no
    /// data.
    required Map<String, dynamic> payload,
  }) = _Frame;

  factory Frame.fromJson(Map<String, dynamic> json) => _$FrameFromJson(json);
}
