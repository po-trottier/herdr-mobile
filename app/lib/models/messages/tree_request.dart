/// `tree_request` (`docs/11-relay-protocol.md` §4.3). Sender: Device. Reply:
/// `tree_snapshot`. Correlation: yes. The payload is `{}`. Mirrors
/// `TreeRequest` in `crates/herdr-relay-proto/src/messages/tree.rs:8-9`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'tree_request.freezed.dart';
part 'tree_request.g.dart';

@freezed
abstract class TreeRequest with _$TreeRequest {
  const factory TreeRequest() = _TreeRequest;

  factory TreeRequest.fromJson(Map<String, dynamic> json) =>
      _$TreeRequestFromJson(json);
}
