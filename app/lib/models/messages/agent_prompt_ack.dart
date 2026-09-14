/// `agent_prompt_ack` (`docs/11-relay-protocol.md` §4.15). Sender: Host.
/// Reply: no (reply to `agent_prompt`). Correlation: yes. Mirrors
/// `AgentPromptAck` in
/// `crates/herdr-relay-proto/src/messages/input.rs:39-45`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'agent_prompt_ack.freezed.dart';
part 'agent_prompt_ack.g.dart';

@freezed
abstract class AgentPromptAck with _$AgentPromptAck {
  const factory AgentPromptAck({
    required String target,
    required bool accepted,
  }) = _AgentPromptAck;

  factory AgentPromptAck.fromJson(Map<String, dynamic> json) =>
      _$AgentPromptAckFromJson(json);
}
