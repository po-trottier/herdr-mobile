/// `pane_frame` (`docs/11-relay-protocol.md` §4.9). Sender: Host. Reply:
/// no. Correlation: no. The payload the terminal emulator renders. Mirrors
/// `PaneFrame` in `crates/herdr-relay-proto/src/messages/watch.rs:40-52`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'pane_frame.freezed.dart';
part 'pane_frame.g.dart';

@freezed
abstract class PaneFrame with _$PaneFrame {
  const factory PaneFrame({
    @JsonKey(name: 'pane_id') required String paneId,

    /// From the `pane.updated` event that triggered this read, never from
    /// `pane.read`, which is always `0` (R-11-052).
    required int revision,
    @JsonKey(name: 'viewport_rows') required int viewportRows,
    required int width,

    /// Full ANSI text of the visible viewport, never a delta (R-11-051).
    required String text,
  }) = _PaneFrame;

  factory PaneFrame.fromJson(Map<String, dynamic> json) =>
      _$PaneFrameFromJson(json);
}
