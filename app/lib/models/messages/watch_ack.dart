/// `watch_ack` (`docs/11-relay-protocol.md` §4.7). Sender: Host. Reply: no
/// (reply to `watch_pane`). Correlation: yes. Mirrors `WatchAck` in
/// `crates/herdr-relay-proto/src/messages/watch.rs:14-26`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import 'scroll_offsets.dart';

part 'watch_ack.freezed.dart';
part 'watch_ack.g.dart';

@freezed
abstract class WatchAck with _$WatchAck {
  const factory WatchAck({
    @JsonKey(name: 'pane_id') required String paneId,

    /// Current revision from `session.snapshot` (R-10-020).
    required int revision,

    /// From `scroll.viewport_rows` (R-10-024).
    @JsonKey(name: 'viewport_rows') required int viewportRows,

    /// From `pane.layout` `rect.width`, in character cells (R-10-024).
    required int width,
    required ScrollOffsets scroll,
    @Default('') String line,
  }) = _WatchAck;

  factory WatchAck.fromJson(Map<String, dynamic> json) =>
      _$WatchAckFromJson(json);
}
