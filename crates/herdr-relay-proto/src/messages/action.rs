//! The Host-action and plugin-action-list messages (`docs/11-relay-protocol.md` §4.16,
//! §4.17, §4.24, §4.25). A paired phone has full control; there is no read-only mode
//! (R-03-050).

use serde::{Deserialize, Serialize};

/// `host_action` (§4.16). Sender: Device. Reply: `host_action_ack`. Correlation: yes.
///
/// `params` is action-specific (R-11-201's field table); the bridge validates its
/// shape per action before forwarding to Herdr. The Device MUST send `focus: false` in
/// every create action inside `params` (R-11-203).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct HostAction {
    pub action: HostActionKind,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub pane_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub workspace_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub tab_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub plugin_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub action_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub params: Option<serde_json::Value>,
}

/// The nine action kinds `host_action.action` accepts (R-11-202's mapping table).
/// `server.stop`, `workspace.close`, `tab.close` and the plugin lifecycle actions MUST
/// NOT be reachable here (R-11-204); they are not variants of this enum.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum HostActionKind {
    #[serde(rename = "workspace.create")]
    WorkspaceCreate,
    #[serde(rename = "tab.create")]
    TabCreate,
    /// Create a pane by split. Maps to Herdr's `pane.split`.
    #[serde(rename = "pane.split")]
    PaneSplit,
    /// Split an existing pane. Also maps to Herdr's `pane.split`.
    #[serde(rename = "split")]
    Split,
    #[serde(rename = "zoom")]
    Zoom,
    #[serde(rename = "close")]
    Close,
    #[serde(rename = "rename")]
    Rename,
    #[serde(rename = "resize")]
    Resize,
    #[serde(rename = "plugin.invoke")]
    PluginInvoke,
}

/// `host_action_ack` (§4.17). Sender: Host. Reply: no (reply to `host_action`).
/// Correlation: yes.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct HostActionAck {
    pub action: HostActionKind,
    pub success: bool,
    /// The pane acted on, for pane-scoped actions; for `pane.split`, the target
    /// (original) pane (R-11-205's sibling rule).
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub pane_id: Option<String>,
    /// The id of the newly created entity, present on a successful create action
    /// (R-11-205).
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub result_id: Option<String>,
}

/// `action_list_request` (§4.24). Sender: Device. Reply: `action_list`. Correlation:
/// yes. The payload is `{}`.
#[derive(Debug, Clone, PartialEq, Eq, Default, Serialize, Deserialize)]
pub struct ActionListRequest {}

/// `action_list` (§4.25). Sender: Host. Reply: no (reply to `action_list_request`).
/// Correlation: yes.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ActionList {
    pub actions: Vec<ActionListEntry>,
}

/// One projected plugin action. MUST NOT carry `command`, `manifest_path`,
/// `plugin_root`, a `*_cwd` field, or any host path (R-11-209).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ActionListEntry {
    pub plugin_id: String,
    pub action_id: String,
    pub title: String,
    pub description: Option<String>,
    pub contexts: Option<Vec<String>>,
}
