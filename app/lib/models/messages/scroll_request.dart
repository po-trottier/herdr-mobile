/// `scroll_request` (`docs/11-relay-protocol.md` §4.10). Sender: Device.
/// Reply: `scroll_response`. Correlation: yes. Mirrors `ScrollRequest` in
/// `crates/herdr-relay-proto/src/messages/watch.rs:54-61`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'scroll_request.freezed.dart';
part 'scroll_request.g.dart';

@freezed
abstract class ScrollRequest with _$ScrollRequest {
  const factory ScrollRequest({
    @JsonKey(name: 'pane_id') required String paneId,

    /// MUST NOT exceed 1000 (R-10-019).
    required int lines,
  }) = _ScrollRequest;

  factory ScrollRequest.fromJson(Map<String, dynamic> json) =>
      _$ScrollRequestFromJson(json);
}
