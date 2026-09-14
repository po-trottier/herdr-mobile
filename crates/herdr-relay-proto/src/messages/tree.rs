//! The tree-browsing messages (`docs/11-relay-protocol.md` §4.3 through §4.5): the full
//! workspace/tab/pane/agent tree and its incremental updates.

use serde::{Deserialize, Serialize};

/// `tree_request` (§4.3). Sender: Device. Reply: `tree_snapshot`. Correlation: yes.
/// The payload is `{}`.
#[derive(Debug, Clone, PartialEq, Eq, Default, Serialize, Deserialize)]
pub struct TreeRequest {}

/// `tree_snapshot` (§4.4). Sender: Host. Reply: no (reply to `tree_request`).
/// Correlation: yes. Flat, joined by id, not nested (R-11-044).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TreeSnapshot {
    pub workspaces: Vec<WorkspaceSummary>,
    pub tabs: Vec<TabSummary>,
    pub panes: Vec<PaneSummary>,
    pub agents: Vec<AgentSummary>,
}

/// One workspace in `tree_snapshot.workspaces` (§4.4) or `tree_update.workspace` (§4.5).
///
/// `repo_name` and `is_linked_worktree` come from Herdr's `worktree` object (2026-09-04:
/// the Device draws Space > Worktree > Tab > Pane from them, R-11-044). The optional
/// fields default so an older peer's payload still parses (R-11-102). `repo_name` and
/// `space_id` serialize as an explicit `null` when absent, like `PaneSummary::agent`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WorkspaceSummary {
    pub workspace_id: String,
    pub name: String,
    pub focused: bool,
    /// The repository name of the workspace's worktree; `null` when Herdr reports no
    /// `worktree` object for the workspace. Metadata only: it MUST NOT group
    /// workspaces (two repos can share one name); `space_id` is the group handle.
    #[serde(default)]
    pub repo_name: Option<String>,
    /// `true` when the workspace is a linked worktree of `repo_name`, `false` for the
    /// main checkout or when there is no worktree.
    #[serde(default)]
    pub is_linked_worktree: bool,
    /// The opaque worktree-group id (R-11-044): the `workspace_id` of the group's
    /// parent — the first non-linked member, in Herdr's own workspace order — set on
    /// every member of an eligible group, the parent included. Eligibility mirrors
    /// the desktop sidebar (`workspace_list_entries_inner`, Herdr `src/ui/sidebar.rs`
    /// at commit b1ff4582e968): two or more workspaces share one private
    /// `worktree.repo_key` and at least one is not a linked worktree. `null` for a
    /// lone workspace, a linked-only group, or a plain directory. The key itself
    /// never crosses the wire; this id is the only group handle a Device sees.
    /// Authoritative in `tree_snapshot` only: a `tree_update.workspace` carries
    /// `null`, and a full `tree_snapshot` follows every workspace event so no Device
    /// keeps a stale id (R-11-046).
    #[serde(default)]
    pub space_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TabSummary {
    pub tab_id: String,
    pub workspace_id: String,
    pub title: String,
    pub focused: bool,
}

/// One pane in `tree_snapshot.panes` (§4.4) or `tree_update.pane` (§4.5).
///
/// `revision` MUST come from the snapshot, never from a `pane.read` result, which is
/// always `0` (R-11-045). `title` is Herdr's own `PaneInfo.title`; a raw terminal OSC
/// title MUST NOT cross the wire (R-11-225).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PaneSummary {
    pub pane_id: String,
    pub workspace_id: String,
    pub tab_id: String,
    pub terminal_id: String,
    pub label: String,
    pub title: String,
    pub cwd: String,
    pub focused: bool,
    /// `agent` (string or null, §4.4 field table): no matching Herdr agent serializes
    /// as an explicit `null`, not an omitted key (worked example, §8).
    pub agent: Option<String>,
    pub agent_status: String,
    pub revision: u64,
    pub scroll: PaneScrollState,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct PaneScrollState {
    pub offset_from_bottom: u64,
    pub max_offset_from_bottom: u64,
    pub viewport_rows: u32,
}

/// One agent in `tree_snapshot.agents` (§4.4). `status_at` is present only when the Host
/// observed the change through a `pane.agent_status_changed` event; the Host MUST NOT
/// invent a timestamp (R-11-224).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AgentSummary {
    pub agent_kind: String,
    pub pane_id: String,
    pub status: String,
    /// Present only when the Host observed the change through a
    /// `pane.agent_status_changed` event; omitted from the wire otherwise (R-11-224).
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub status_at: Option<String>,
    /// `session` (string or null, §4.4 field table), unlike `status_at`: no override
    /// rule narrows this to "absent", so it serializes as an explicit `null`.
    pub session: Option<String>,
}

/// `tree_update` (§4.5). Sender: Host. Reply: no. Correlation: no. Sent for every
/// subscribed Herdr event that changes the tree (R-11-046, R-11-047).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TreeUpdate {
    pub event: TreeEvent,
    /// Present when the event carries a pane object; omitted otherwise (§4.5 field
    /// table, `Required: No`).
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub pane: Option<PaneSummary>,
    /// Present only for workspace events; omitted otherwise (§4.5 field table).
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub workspace: Option<WorkspaceSummary>,
    /// Present only for tab events; omitted otherwise (§4.5 field table).
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub tab: Option<TabSummary>,
}

/// The Herdr event that triggered a `tree_update` (R-11-047's exact subscription set).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum TreeEvent {
    #[serde(rename = "workspace.created")]
    WorkspaceCreated,
    #[serde(rename = "workspace.updated")]
    WorkspaceUpdated,
    #[serde(rename = "workspace.renamed")]
    WorkspaceRenamed,
    #[serde(rename = "workspace.closed")]
    WorkspaceClosed,
    #[serde(rename = "tab.created")]
    TabCreated,
    #[serde(rename = "tab.closed")]
    TabClosed,
    #[serde(rename = "tab.renamed")]
    TabRenamed,
    #[serde(rename = "tab.focused")]
    TabFocused,
    #[serde(rename = "pane.created")]
    PaneCreated,
    #[serde(rename = "pane.closed")]
    PaneClosed,
    #[serde(rename = "pane.updated")]
    PaneUpdated,
    #[serde(rename = "pane.focused")]
    PaneFocused,
    #[serde(rename = "pane.agent_status_changed")]
    PaneAgentStatusChanged,
    #[serde(rename = "layout.updated")]
    LayoutUpdated,
}

#[cfg(test)]
mod tests {
    use super::{AgentSummary, WorkspaceSummary};

    /// R-11-102: a newer peer MUST treat an absent field as its default value.
    #[test]
    fn missing_optional_field_deserializes_to_none() {
        let json = r#"{"agent_kind":"claude","pane_id":"w3:p2","status":"working"}"#;
        let parsed: AgentSummary =
            serde_json::from_str(json).expect("must parse without status_at/session keys");
        assert!(parsed.status_at.is_none());
        assert!(parsed.session.is_none());
    }

    /// R-11-102: a pre-2026-09-04 Host omits the worktree fields; they MUST default.
    #[test]
    fn workspace_without_worktree_fields_defaults() {
        let json = r#"{"workspace_id":"w3","name":"herdr-relay","focused":true}"#;
        let parsed: WorkspaceSummary =
            serde_json::from_str(json).expect("must parse without worktree fields");
        assert_eq!(parsed.repo_name, None);
        assert!(!parsed.is_linked_worktree);
        assert_eq!(parsed.space_id, None);
        let out = serde_json::to_value(&parsed).expect("serialize");
        assert!(
            out["repo_name"].is_null(),
            "absent repo_name is an explicit null"
        );
        assert_eq!(out["is_linked_worktree"], false);
        assert!(
            out["space_id"].is_null(),
            "absent space_id is an explicit null"
        );
    }
}
