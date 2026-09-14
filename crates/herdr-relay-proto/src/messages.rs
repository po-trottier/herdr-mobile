//! The application message union that travels inside the frame envelope's `payload`.
//!
//! Owning rule: `docs/11-relay-protocol.md` §4 "Application messages", the 26-row
//! message table (including `send_input_ack` as `12a`) and its per-message sections
//! (4.1 through 4.25).
//!
//! Split by responsibility across `messages/*.rs`, re-exported here, following the
//! same `foo.rs` + `foo/*.rs` pattern the tree already uses for
//! `crates/herdr-relay/src/pairing.rs` + `pairing/wordlist.rs`
//! (`docs/40-repo-tooling.md` §3.2.1).

mod action;
mod control;
mod device;
mod input;
mod session;
mod status;
mod tree;
mod watch;

pub use action::{
    ActionList, ActionListEntry, ActionListRequest, HostAction, HostActionAck, HostActionKind,
};
pub use control::{Disconnect, ErrorMessage};
pub use device::{DeviceList, DeviceListEntry, DeviceListRequest, RevokeDevice, RevokeResult};
pub use input::{AgentPrompt, AgentPromptAck, MarkSeen, SendInput, SendInputAck};
pub use session::{DeviceInfo, HostInfo, HostTheme, Platform, ThemePalette};
pub use status::{AgentStatus, AgentStatusKind};
pub use tree::{
    AgentSummary, PaneScrollState, PaneSummary, TabSummary, TreeEvent, TreeRequest, TreeSnapshot,
    TreeUpdate, WorkspaceSummary,
};
pub use watch::{
    PaneFrame, ScrollOffsets, ScrollRequest, ScrollResponse, UnwatchPane, WatchAck, WatchPane,
};

use serde::{Deserialize, Serialize};

/// One application message, tagged by its wire `type` string. Serializing a `Message`
/// produces `{"type": "<type>", "payload": {...}}`, matching the frame envelope's
/// `type`/`payload` split (`docs/11-relay-protocol.md` R-11-031); [`crate::frame::Frame`]
/// builds and reads a `Message` through that shape.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", content = "payload", rename_all = "snake_case")]
pub enum Message {
    HostInfo(HostInfo),
    HostTheme(HostTheme),
    DeviceInfo(DeviceInfo),
    TreeRequest(TreeRequest),
    TreeSnapshot(TreeSnapshot),
    /// Boxed: `TreeUpdate` (three `PaneSummary`-sized `Option`s) is the largest
    /// payload at 424 bytes and boxes to 8; measured with `size_of`.
    TreeUpdate(Box<TreeUpdate>),
    WatchPane(WatchPane),
    WatchAck(WatchAck),
    UnwatchPane(UnwatchPane),
    PaneFrame(PaneFrame),
    ScrollRequest(ScrollRequest),
    ScrollResponse(ScrollResponse),
    SendInput(SendInput),
    SendInputAck(SendInputAck),
    AgentStatus(AgentStatus),
    AgentPrompt(AgentPrompt),
    MarkSeen(MarkSeen),
    AgentPromptAck(AgentPromptAck),
    HostAction(HostAction),
    HostActionAck(HostActionAck),
    DeviceListRequest(DeviceListRequest),
    DeviceList(DeviceList),
    RevokeDevice(RevokeDevice),
    RevokeResult(RevokeResult),
    Error(ErrorMessage),
    Disconnect(Disconnect),
    ActionListRequest(ActionListRequest),
    ActionList(ActionList),
}

impl Message {
    /// The wire `type` string for this message, exactly as it appears in a frame
    /// envelope's `type` field.
    #[must_use]
    pub fn type_name(&self) -> &'static str {
        match self {
            Self::HostInfo(_) => "host_info",
            Self::HostTheme(_) => "host_theme",
            Self::DeviceInfo(_) => "device_info",
            Self::TreeRequest(_) => "tree_request",
            Self::TreeSnapshot(_) => "tree_snapshot",
            Self::TreeUpdate(_) => "tree_update",
            Self::WatchPane(_) => "watch_pane",
            Self::WatchAck(_) => "watch_ack",
            Self::UnwatchPane(_) => "unwatch_pane",
            Self::PaneFrame(_) => "pane_frame",
            Self::ScrollRequest(_) => "scroll_request",
            Self::ScrollResponse(_) => "scroll_response",
            Self::SendInput(_) => "send_input",
            Self::SendInputAck(_) => "send_input_ack",
            Self::AgentStatus(_) => "agent_status",
            Self::AgentPrompt(_) => "agent_prompt",
            Self::MarkSeen(_) => "mark_seen",
            Self::AgentPromptAck(_) => "agent_prompt_ack",
            Self::HostAction(_) => "host_action",
            Self::HostActionAck(_) => "host_action_ack",
            Self::DeviceListRequest(_) => "device_list_request",
            Self::DeviceList(_) => "device_list",
            Self::RevokeDevice(_) => "revoke_device",
            Self::RevokeResult(_) => "revoke_result",
            Self::Error(_) => "error",
            Self::Disconnect(_) => "disconnect",
            Self::ActionListRequest(_) => "action_list_request",
            Self::ActionList(_) => "action_list",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{ErrorMessage, Message, TreeRequest};
    use crate::codes::ErrorCode;

    #[test]
    fn message_serializes_as_type_and_payload() {
        let message = Message::TreeRequest(TreeRequest {});
        let value = serde_json::to_value(&message).expect("Message always serializes");
        assert_eq!(value["type"], "tree_request");
        assert_eq!(value["payload"], serde_json::json!({}));
        assert_eq!(message.type_name(), "tree_request");
    }

    #[test]
    fn message_round_trips_through_json() {
        let message = Message::Error(ErrorMessage {
            code: ErrorCode::PaneNotFound,
            message: "pane w3:p2 does not exist".to_owned(),
            fatal: false,
        });
        let json = serde_json::to_string(&message).expect("Message always serializes");
        let round_tripped: Message = serde_json::from_str(&json).expect("valid Message JSON");
        assert_eq!(round_tripped, message);
    }
}
