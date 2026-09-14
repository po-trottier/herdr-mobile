/// `action_list_request` (`docs/11-relay-protocol.md` §4.24). Sender:
/// Device. Reply: `action_list`. Correlation: yes. The payload is `{}`.
/// Mirrors `ActionListRequest` in
/// `crates/herdr-relay-proto/src/messages/action.rs:72-75`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'action_list_request.freezed.dart';
part 'action_list_request.g.dart';

@freezed
abstract class ActionListRequest with _$ActionListRequest {
  const factory ActionListRequest() = _ActionListRequest;

  factory ActionListRequest.fromJson(Map<String, dynamic> json) =>
      _$ActionListRequestFromJson(json);
}
