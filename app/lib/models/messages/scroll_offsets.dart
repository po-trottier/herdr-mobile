/// A pane's live scroll offsets inside `WatchAck.scroll`
/// (`docs/11-relay-protocol.md` §4.7). Mirrors `ScrollOffsets` in
/// `crates/herdr-relay-proto/src/messages/watch.rs:28-32`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'scroll_offsets.freezed.dart';
part 'scroll_offsets.g.dart';

@freezed
abstract class ScrollOffsets with _$ScrollOffsets {
  const factory ScrollOffsets({
    @JsonKey(name: 'offset_from_bottom') required int offsetFromBottom,
    @JsonKey(name: 'max_offset_from_bottom') required int maxOffsetFromBottom,
  }) = _ScrollOffsets;

  factory ScrollOffsets.fromJson(Map<String, dynamic> json) =>
      _$ScrollOffsetsFromJson(json);
}
