/// `agent_prompt` (`docs/11-relay-protocol.md` §4.14). Sender: Device.
/// Reply: `agent_prompt_ack`. Correlation: yes. Maps to Herdr's
/// `agent.prompt` without `wait` (R-11-060). Mirrors `AgentPrompt` in
/// `crates/herdr-relay-proto/src/messages/input.rs:29-37`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'agent_prompt.freezed.dart';
part 'agent_prompt.g.dart';

@freezed
abstract class AgentPrompt with _$AgentPrompt {
  const factory AgentPrompt({
    /// A pane id or agent identifier.
    required String target,

    /// Prompt text; multi-line is permitted.
    required String text,
  }) = _AgentPrompt;

  factory AgentPrompt.fromJson(Map<String, dynamic> json) =>
      _$AgentPromptFromJson(json);
}
