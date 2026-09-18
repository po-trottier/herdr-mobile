//! The input-delivery messages (`docs/11-relay-protocol.md` §4.12 through §4.15): key
//! and text input to a pane, and prompts to an agent.

use serde::{Deserialize, Serialize};

/// `send_input` (§4.12). Sender: Device. Reply: `send_input_ack`. Correlation: yes.
/// Exactly one of two shapes (R-11-248):
///
/// - `line`: the full current text of the Device composer for `pane_id`. The Host
///   owns a per-pane shadow of the console line and reconciles it to `line`
///   (Backspace for the differing tail, then raw text). Idempotent, so it may be
///   resent, and a newer `line` for the same pane supersedes an unapplied older one.
/// - `text` and/or `keys`: literal text and named keys from the key row. The bridge
///   resolves the four-step key order of R-11-054 and maps to the correct Herdr
///   method (R-11-056).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SendInput {
    pub pane_id: String,
    /// Full composer text (R-11-248). Mutually exclusive with `text`/`keys`.
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub line: Option<String>,
    /// Literal text: printable characters and the six unnamed keys as raw sequences
    /// (R-10-036).
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub text: Option<String>,
    /// Named keys, for example `["Enter"]` or `["ctrl+c"]` (R-10-036 to R-10-039).
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub keys: Option<Vec<String>>,
    /// Queue or cancel a submit (R-11-253). `until_idle` with `keys: ["Enter"]`:
    /// the Host holds the `Enter` until the pane's agent status is not `working`,
    /// then forwards it. `cancel` alone: drop a held submit for this pane.
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub defer: Option<Defer>,
}

/// `send_input.defer` values (R-11-253).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Defer {
    UntilIdle,
    Cancel,
}

/// `send_input_ack` (§4.12a). Sender: Host. Reply: no (reply to `send_input`).
/// Correlation: yes. Carries no pane content (R-11-227). For a `defer: until_idle`
/// submit the Host sends two acks with the same `corr`: `queued: true` when it
/// holds the `Enter`, then the final ack when it forwarded it (R-11-253).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SendInputAck {
    pub pane_id: String,
    pub accepted: bool,
    /// True on the first of the two acks of a held submit (R-11-253).
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub queued: bool,
}

/// `agent_prompt` (§4.14). Sender: Device. Reply: `agent_prompt_ack`. Correlation:
/// yes. Maps to Herdr's `agent.prompt` without `wait` (R-11-060).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AgentPrompt {
    /// A pane id or agent identifier.
    pub target: String,
    /// Prompt text; multi-line is permitted.
    pub text: String,
}

/// `agent_prompt_ack` (§4.15). Sender: Host. Reply: no (reply to `agent_prompt`).
/// Correlation: yes.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AgentPromptAck {
    pub target: String,
    pub accepted: bool,
}
/// R-11-240: marks an agent pane as seen through Herdr.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MarkSeen {
    pub pane_id: String,
}

/// `ping` (§4.26). Sender: Device. Reply: `pong`. Correlation: yes. End-to-end
/// round-trip probe through the Noise session (R-11-250); at most one every 10 s
/// and only while a terminal is visible.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Ping {}

/// `pong` (§4.27). Sender: Host. Reply: no (reply to `ping`). Correlation: yes.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Pong {}
