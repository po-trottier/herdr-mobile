/// One agent in `tree_snapshot.agents` (`docs/11-relay-protocol.md` §4.4).
/// `statusAt` is present only when the Host observed the change through a
/// `pane.agent_status_changed` event; the Host MUST NOT invent a timestamp
/// (R-11-224). Mirrors `AgentSummary` in
/// `crates/herdr-relay-proto/src/messages/tree.rs:64-74`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'agent_summary.freezed.dart';
part 'agent_summary.g.dart';

@freezed
abstract class AgentSummary with _$AgentSummary {
  const factory AgentSummary({
    @JsonKey(name: 'agent_kind') required String agentKind,
    @JsonKey(name: 'pane_id') required String paneId,
    required String status,
    @JsonKey(name: 'status_at', includeIfNull: false) String? statusAt,
    String? session,
  }) = _AgentSummary;

  factory AgentSummary.fromJson(Map<String, dynamic> json) =>
      _$AgentSummaryFromJson(json);
}
