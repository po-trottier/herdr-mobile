/// `agent_status` (`docs/11-relay-protocol.md` §4.13), the trigger for a
/// local notification (R-30-502, `docs/22-platform-integration.md`
/// R-22-022). Mirrors `AgentStatus` in
/// `crates/herdr-relay-proto/src/messages/status.rs:10-24`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
///
/// The Host MUST NOT send pane text here (R-11-058). The Host MUST apply a
/// 30-second settle window per agent before re-notifying (R-11-059).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import 'agent_status_kind.dart';

part 'agent_status.freezed.dart';
part 'agent_status.g.dart';

@freezed
abstract class AgentStatus with _$AgentStatus {
  const factory AgentStatus({
    /// The `host_id` from `host_info`. Routes the notification tap.
    @JsonKey(name: 'host_id') required String hostId,
    @JsonKey(name: 'pane_id') required String paneId,
    @JsonKey(name: 'workspace_id') required String workspaceId,
    @JsonKey(name: 'tab_id') required String tabId,
    @JsonKey(name: 'tab_title') required String tabTitle,
    @JsonKey(name: 'pane_title') required String paneTitle,

    /// For example `claude` or `codex`.
    @JsonKey(name: 'agent_kind') required String agentKind,
    required AgentStatusKind status,

    /// RFC 3339 UTC timestamp of the status change.
    required String at,
  }) = _AgentStatus;

  factory AgentStatus.fromJson(Map<String, dynamic> json) =>
      _$AgentStatusFromJson(json);
}
