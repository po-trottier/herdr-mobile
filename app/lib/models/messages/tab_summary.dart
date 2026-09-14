/// One tab in `tree_snapshot.tabs` (`docs/11-relay-protocol.md` §4.4).
/// Mirrors `TabSummary` in
/// `crates/herdr-relay-proto/src/messages/tree.rs:28-34`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'tab_summary.freezed.dart';
part 'tab_summary.g.dart';

@freezed
abstract class TabSummary with _$TabSummary {
  const factory TabSummary({
    @JsonKey(name: 'tab_id') required String tabId,
    @JsonKey(name: 'workspace_id') required String workspaceId,
    required String title,
    required bool focused,
  }) = _TabSummary;

  factory TabSummary.fromJson(Map<String, dynamic> json) =>
      _$TabSummaryFromJson(json);
}
