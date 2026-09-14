/// A pane's scrollback state inside `PaneSummary.scroll`
/// (`docs/11-relay-protocol.md` §4.4). Mirrors `PaneScrollState` in
/// `crates/herdr-relay-proto/src/messages/tree.rs:57-62`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'pane_scroll_state.freezed.dart';
part 'pane_scroll_state.g.dart';

@freezed
abstract class PaneScrollState with _$PaneScrollState {
  const factory PaneScrollState({
    @JsonKey(name: 'offset_from_bottom') required int offsetFromBottom,
    @JsonKey(name: 'max_offset_from_bottom') required int maxOffsetFromBottom,
    @JsonKey(name: 'viewport_rows') required int viewportRows,
  }) = _PaneScrollState;

  factory PaneScrollState.fromJson(Map<String, dynamic> json) =>
      _$PaneScrollStateFromJson(json);
}
