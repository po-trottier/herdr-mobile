/// The `agent_status.status` values (`docs/11-relay-protocol.md` §4.13).
/// Mirrors `AgentStatusKind` in
/// `crates/herdr-relay-proto/src/messages/status.rs:26-34`
/// (`#[serde(rename_all = "snake_case")]`)
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

enum AgentStatusKind {
  @JsonValue('idle')
  idle,
  @JsonValue('working')
  working,
  @JsonValue('blocked')
  blocked,
  @JsonValue('done')
  done,
  @JsonValue('unknown')
  unknown,
}
