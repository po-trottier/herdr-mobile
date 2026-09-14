//! The agent-status message (`docs/11-relay-protocol.md` §4.13), the trigger for a
//! local notification (R-30-502, `docs/22-platform-integration.md` R-22-022).

use serde::{Deserialize, Serialize};

/// `agent_status` (§4.13). Sender: Host. Reply: no. Correlation: no.
///
/// The Host MUST NOT send pane text here (R-11-058). The Host MUST apply a 30-second
/// settle window per agent before re-notifying (R-11-059).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AgentStatus {
    /// The `host_id` from `host_info`. Routes the notification tap.
    pub host_id: String,
    pub pane_id: String,
    pub workspace_id: String,
    pub tab_id: String,
    pub tab_title: String,
    pub pane_title: String,
    /// For example `claude` or `codex`.
    pub agent_kind: String,
    pub status: AgentStatusKind,
    /// RFC 3339 UTC timestamp of the status change.
    pub at: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AgentStatusKind {
    Idle,
    Working,
    Blocked,
    Done,
    Unknown,
}
