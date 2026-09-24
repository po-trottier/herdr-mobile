//! The protocol test vectors shared by the Rust integration tests
//! (`crates/herdr-relay-proto/tests/vectors.rs`) and the Dart mirror tests under
//! `app/test/models/`.
//!
//! Owning rule: `docs/40-repo-tooling.md` R-40-031, which requires unit tests for the
//! frame envelope, the close-code enum, the error taxonomy, the handle codec and the
//! phrase codec, so a bug in this shared crate breaks every consumer at once.
//!
//! [`message_vectors`] holds one canonical example frame for every application message
//! in `docs/11-relay-protocol.md` §4 (`docs/90-implementation-plan.md` §5.2, `WP-5-c`).
//! The `host_info`, `device_info`, `tree_request`, `tree_snapshot`, `watch_pane`,
//! `watch_ack`, `pane_frame`, `send_input`, `agent_status`, `unwatch_pane` and
//! `disconnect` vectors reproduce §8's worked example verbatim; the rest use the same
//! sample ids for consistency.
//!
//! Each vector is a real, typed [`Message`] instance, not a hand-shaped JSON literal:
//! `crates/herdr-relay-proto/tests/vectors.rs` passes it through [`Frame::wrap`], which
//! calls this crate's own `#[derive(Serialize)]` implementation. That is what lets the
//! committed `tests/vectors.json` prove the crate's real field-presence behaviour (for
//! example, an absent `Option` field serializing as an explicit `null` versus an
//! omitted key) instead of merely reproducing whatever shape a literal happened to be
//! typed with.

use serde_json::json;

use crate::codes::ErrorCode;
use crate::messages::{
    ActionList, ActionListEntry, ActionListRequest, AgentPrompt, AgentPromptAck, AgentStatus,
    AgentStatusKind, AgentSummary, Defer, DeviceInfo, DeviceList, DeviceListEntry,
    DeviceListRequest, Disconnect, ErrorMessage, HostAction, HostActionAck, HostActionKind,
    HostInfo, Message, PaneFrame, PaneScrollState, PaneSummary, Ping, Platform, Pong, RevokeDevice,
    RevokeResult, ScrollOffsets, ScrollRequest, ScrollResponse, SendInput, SendInputAck,
    TabSummary, TreeEvent, TreeRequest, TreeSnapshot, TreeUpdate, UnwatchPane, WatchAck, WatchPane,
    WorkspaceSummary,
};

/// The routing handle from the worked example (`docs/11-relay-protocol.md` §8).
pub const EXAMPLE_HANDLE: &str = "n6Loxf94CfyIO6hOxlaHvA";

/// The pairing phrase from the worked example (§8).
pub const EXAMPLE_PHRASE: &str = "remedy-tapestry-hubcap-oversleep-jailbird-kinetic";

/// The pairing URI from the worked example (§8.1, R-11-140).
pub const EXAMPLE_PAIRING_URI: &str = "herdr-remote://pair?v=1&r=https%3A%2F%2Frelay.example.com&h=n6Loxf94CfyIO6hOxlaHvA&p=remedy-tapestry-hubcap-oversleep-jailbird-kinetic";

/// One canonical example frame — wire `type`, `seq`, `corr` and a real typed
/// [`Message`] — for every application message in `docs/11-relay-protocol.md` §4.
#[must_use]
pub fn message_vectors() -> Vec<(&'static str, u64, Option<String>, Message)> {
    let pane = PaneSummary {
        pane_id: "w3:p2".to_owned(),
        workspace_id: "w3".to_owned(),
        tab_id: "w3:t2".to_owned(),
        terminal_id: "term_abc123".to_owned(),
        label: "claude".to_owned(),
        title: "claude".to_owned(),
        cwd: "D:\\Repositories\\herdr-mobile".to_owned(),
        focused: true,
        agent: Some("claude".to_owned()),
        agent_status: "working".to_owned(),
        revision: 82195,
        scroll: PaneScrollState {
            offset_from_bottom: 0,
            max_offset_from_bottom: 0,
            viewport_rows: 50,
        },
    };
    let updated_pane = PaneSummary {
        revision: 82196,
        ..pane.clone()
    };

    vec![
        (
            "host_info",
            1,
            None,
            Message::HostInfo(HostInfo {
                protocol: 1,
                host_id: "a1b2c3d4-e5f6-7890-abcd-ef1234567890".to_owned(),
                host_name: "patrick-desk".to_owned(),
                herdr_version: "0.8.2-preview.2026-08-31-b1ff4582e968".to_owned(),
                herdr_protocol: 21,
                paired: false,
                theme: None,
            }),
        ),
        (
            "device_info",
            1,
            None,
            Message::DeviceInfo(DeviceInfo {
                protocol: 1,
                device_id: "f9e8d7c6-b5a4-3210-fedc-ba9876543210".to_owned(),
                device_name: "Pixel 9 Pro".to_owned(),
                platform: Platform::Android,
                os_version: "15".to_owned(),
                app_version: "1.0.0".to_owned(),
            }),
        ),
        (
            "tree_request",
            2,
            Some("req-001".to_owned()),
            Message::TreeRequest(TreeRequest {}),
        ),
        (
            "tree_snapshot",
            2,
            Some("req-001".to_owned()),
            Message::TreeSnapshot(TreeSnapshot {
                workspaces: vec![WorkspaceSummary {
                    workspace_id: "w3".to_owned(),
                    name: "herdr-relay".to_owned(),
                    focused: true,
                    repo_name: Some("herdr-relay".to_owned()),
                    is_linked_worktree: false,
                    // A lone workspace belongs to no worktree group (R-11-044).
                    space_id: None,
                }],
                tabs: vec![TabSummary {
                    tab_id: "w3:t2".to_owned(),
                    workspace_id: "w3".to_owned(),
                    title: "impl".to_owned(),
                    focused: true,
                }],
                panes: vec![pane.clone()],
                agents: vec![AgentSummary {
                    agent_kind: "claude".to_owned(),
                    pane_id: "w3:p2".to_owned(),
                    status: "working".to_owned(),
                    // Absent: the Host did not observe this status through a
                    // `pane.agent_status_changed` event (R-11-224).
                    status_at: None,
                    session: Some("sess_001".to_owned()),
                }],
            }),
        ),
        (
            "tree_update",
            3,
            None,
            Message::TreeUpdate(Box::new(TreeUpdate {
                event: TreeEvent::PaneUpdated,
                pane: Some(updated_pane.clone()),
                workspace: None,
                tab: None,
            })),
        ),
        (
            "watch_pane",
            3,
            Some("req-002".to_owned()),
            Message::WatchPane(WatchPane {
                pane_id: "w3:p2".to_owned(),
            }),
        ),
        (
            "watch_ack",
            3,
            Some("req-002".to_owned()),
            Message::WatchAck(WatchAck {
                pane_id: "w3:p2".to_owned(),
                revision: 82195,
                viewport_rows: 50,
                width: 122,
                scroll: ScrollOffsets {
                    offset_from_bottom: 0,
                    max_offset_from_bottom: 0,
                },
                line: String::new(),
            }),
        ),
        (
            "unwatch_pane",
            5,
            None,
            Message::UnwatchPane(UnwatchPane {
                pane_id: "w3:p2".to_owned(),
            }),
        ),
        (
            "pane_frame",
            4,
            None,
            Message::PaneFrame(PaneFrame {
                pane_id: "w3:p2".to_owned(),
                revision: 82196,
                viewport_rows: 50,
                width: 122,
                text: "line one\nline two".to_owned(),
            }),
        ),
        (
            "scroll_request",
            6,
            Some("req-003".to_owned()),
            Message::ScrollRequest(ScrollRequest {
                pane_id: "w3:p2".to_owned(),
                lines: 200,
            }),
        ),
        (
            "scroll_response",
            6,
            Some("req-003".to_owned()),
            Message::ScrollResponse(ScrollResponse {
                pane_id: "w3:p2".to_owned(),
                text: "older line one\nolder line two".to_owned(),
                lines: 2,
                truncated: true,
            }),
        ),
        (
            "send_input",
            4,
            None,
            Message::SendInput(SendInput {
                pane_id: "w3:p2".to_owned(),
                line: None,
                text: None,
                keys: Some(vec!["ctrl+c".to_owned()]),
                defer: None,
                bypass_line: None,
            }),
        ),
        (
            "send_input",
            4,
            Some("req-005".to_owned()),
            Message::SendInput(SendInput {
                pane_id: "w3:p2".to_owned(),
                line: Some("hello, world".to_owned()),
                text: None,
                keys: None,
                defer: None,
                bypass_line: None,
            }),
        ),
        (
            "send_input",
            7,
            Some("req-007".to_owned()),
            Message::SendInput(SendInput {
                pane_id: "w3:p2".to_owned(),
                line: None,
                text: None,
                keys: Some(vec!["Enter".to_owned()]),
                defer: Some(Defer::UntilIdle),
                bypass_line: None,
            }),
        ),
        (
            "send_input",
            8,
            Some("req-answer".to_owned()),
            Message::SendInput(SendInput {
                pane_id: "w3:p2".to_owned(),
                line: None,
                text: Some("other answer".to_owned()),
                keys: Some(vec!["Enter".to_owned()]),
                defer: None,
                bypass_line: Some(true),
            }),
        ),
        (
            "send_input_ack",
            7,
            Some("req-007".to_owned()),
            Message::SendInputAck(SendInputAck {
                pane_id: "w3:p2".to_owned(),
                accepted: true,
                queued: true,
            }),
        ),
        (
            "ping",
            6,
            Some("req-006".to_owned()),
            Message::Ping(Ping {}),
        ),
        (
            "pong",
            6,
            Some("req-006".to_owned()),
            Message::Pong(Pong {}),
        ),
        (
            "send_input_ack",
            4,
            Some("req-004".to_owned()),
            Message::SendInputAck(SendInputAck {
                pane_id: "w3:p2".to_owned(),
                accepted: true,
                queued: false,
            }),
        ),
        (
            "agent_status",
            5,
            None,
            Message::AgentStatus(AgentStatus {
                host_id: "a1b2c3d4-e5f6-7890-abcd-ef1234567890".to_owned(),
                pane_id: "w3:p2".to_owned(),
                workspace_id: "w3".to_owned(),
                tab_id: "w3:t2".to_owned(),
                tab_title: "impl".to_owned(),
                pane_title: "claude".to_owned(),
                agent_kind: "claude".to_owned(),
                status: AgentStatusKind::Done,
                at: "2026-08-24T14:32:05Z".to_owned(),
            }),
        ),
        (
            "agent_prompt",
            7,
            Some("req-005".to_owned()),
            Message::AgentPrompt(AgentPrompt {
                target: "w3:p2".to_owned(),
                text: "run the tests".to_owned(),
            }),
        ),
        (
            "agent_prompt_ack",
            7,
            Some("req-005".to_owned()),
            Message::AgentPromptAck(AgentPromptAck {
                target: "w3:p2".to_owned(),
                accepted: true,
            }),
        ),
        (
            "host_action",
            8,
            Some("req-006".to_owned()),
            Message::HostAction(HostAction {
                action: HostActionKind::PaneSplit,
                pane_id: Some("w3:p2".to_owned()),
                workspace_id: None,
                tab_id: None,
                plugin_id: None,
                action_id: None,
                params: Some(json!({"direction": "right", "focus": false})),
            }),
        ),
        (
            "host_action_ack",
            8,
            Some("req-006".to_owned()),
            Message::HostActionAck(HostActionAck {
                action: HostActionKind::PaneSplit,
                success: true,
                pane_id: Some("w3:p2".to_owned()),
                result_id: Some("w3:p4".to_owned()),
            }),
        ),
        (
            "device_list_request",
            9,
            Some("req-007".to_owned()),
            Message::DeviceListRequest(DeviceListRequest {}),
        ),
        (
            "device_list",
            9,
            Some("req-007".to_owned()),
            Message::DeviceList(DeviceList {
                devices: vec![DeviceListEntry {
                    id: "f9e8d7c6-b5a4-3210-fedc-ba9876543210".to_owned(),
                    name: "Pixel 9 Pro".to_owned(),
                    paired_at: "2026-08-20T09:00:00Z".to_owned(),
                    last_seen: "2026-08-24T14:30:00Z".to_owned(),
                    connected: true,
                    platform: Platform::Android,
                    fingerprint: "3f9a-1c04-be77-20d5".to_owned(),
                }],
            }),
        ),
        (
            "revoke_device",
            10,
            Some("req-008".to_owned()),
            Message::RevokeDevice(RevokeDevice {
                device_id: Some("f9e8d7c6-b5a4-3210-fedc-ba9876543210".to_owned()),
                all: None,
            }),
        ),
        (
            "revoke_result",
            10,
            Some("req-008".to_owned()),
            Message::RevokeResult(RevokeResult {
                revoked: vec!["f9e8d7c6-b5a4-3210-fedc-ba9876543210".to_owned()],
                all: false,
            }),
        ),
        (
            "error",
            11,
            Some("req-009".to_owned()),
            Message::Error(ErrorMessage {
                code: ErrorCode::PaneNotFound,
                message: "pane w3:p9 does not exist".to_owned(),
                fatal: false,
            }),
        ),
        ("disconnect", 5, None, Message::Disconnect(Disconnect {})),
        (
            "action_list_request",
            12,
            Some("req-010".to_owned()),
            Message::ActionListRequest(ActionListRequest {}),
        ),
        (
            "action_list",
            12,
            Some("req-010".to_owned()),
            Message::ActionList(ActionList {
                actions: vec![ActionListEntry {
                    plugin_id: "herdr-sidebar".to_owned(),
                    action_id: "open-git".to_owned(),
                    title: "Open Git".to_owned(),
                    description: Some("Opens a git status pane".to_owned()),
                    contexts: Some(vec!["global".to_owned()]),
                }],
            }),
        ),
    ]
}
