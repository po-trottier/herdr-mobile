/// `scroll_response` (`docs/11-relay-protocol.md` §4.11). Sender: Host.
/// Reply: no (reply to `scroll_request`). Correlation: yes. Mirrors
/// `ScrollResponse` in
/// `crates/herdr-relay-proto/src/messages/watch.rs:63-72`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'scroll_response.freezed.dart';
part 'scroll_response.g.dart';

@freezed
abstract class ScrollResponse with _$ScrollResponse {
  const factory ScrollResponse({
    @JsonKey(name: 'pane_id') required String paneId,
    required String text,
    required int lines,

    /// `true` when the returned window does not cover the full scrollback.
    required bool truncated,
  }) = _ScrollResponse;

  factory ScrollResponse.fromJson(Map<String, dynamic> json) =>
      _$ScrollResponseFromJson(json);
}
