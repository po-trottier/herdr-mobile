//! The input-delivery messages (`docs/11-relay-protocol.md` §4.12 through §4.15): key
//! and text input to a pane, and prompts to an agent.

use serde::{Deserialize, Serialize};

/// `send_input` (§4.12). Sender: Device. Reply: no. Correlation: no. The bridge
/// resolves the four-step key order of R-11-054 and maps to the correct Herdr method
/// (R-11-056).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SendInput {
    pub pane_id: String,
    /// Literal text: printable characters and the six unnamed keys as raw sequences
    /// (R-10-036).
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub text: Option<String>,
    /// Named keys, for example `["Enter"]` or `["ctrl+c"]` (R-10-036 to R-10-039).
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub keys: Option<Vec<String>>,
}

/// `send_input_ack` (§4.12a). Sender: Host. Reply: no (reply to `send_input`).
/// Correlation: yes. Carries no pane content (R-11-227).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SendInputAck {
    pub pane_id: String,
    pub accepted: bool,
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
