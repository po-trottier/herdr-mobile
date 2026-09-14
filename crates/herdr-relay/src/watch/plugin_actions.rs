//! Phase 7: `action_list_request` -> `action_list`, and `host_action`'s
//! `plugin.invoke` (`docs/10-herdr-integration.md` §3.9, `docs/11-relay-protocol.md`
//! §4.16 `plugin.invoke`, §4.24, §4.25). Split out of `input.rs` once that file
//! crossed the R-41-010 400-line cap, per `docs/90-implementation-plan.md` Phase
//! 7's own guidance.

use std::collections::HashSet;
use std::thread;
use std::time::Duration;

use serde_json::{Value, json};

use herdr_relay_proto::messages::{
    ActionList, ActionListEntry, ActionListRequest, HostAction, HostActionAck, HostActionKind,
    MarkSeen, Message,
};

use super::bridge::{Bridge, WatchError};
use super::error_map::map_watch_error;
use super::herdr_calls::HerdrCalls;

impl<H: HerdrCalls> Bridge<H> {
    /// R-10-072, R-11-240, R-02-031: marks seen with one focus call and no read.
    pub fn mark_seen(&self, request: MarkSeen) -> Result<(), WatchError> {
        self.herdr.agent_focus(&request.pane_id)?;
        Ok(())
    }
    /// `action_list_request` -> `action_list` (R-10-056, R-10-057, R-11-209,
    /// R-11-210, R-11-211).
    pub fn action_list_request(&self, _request: ActionListRequest) -> Result<Message, WatchError> {
        let raw = self.herdr.plugin_action_list()?;
        let host_platform = std::env::consts::OS; // "windows" | "linux" | "macos" (R-11-210)
        let actions = raw
            .as_array()
            .cloned()
            .unwrap_or_default()
            .into_iter()
            .filter(|action| platform_matches(action, host_platform))
            .map(project_action)
            .collect();
        Ok(Message::ActionList(ActionList { actions }))
    }

    /// `plugin.invoke` (R-11-215 through R-11-219, R-10-058, R-10-059). Replies
    /// with `host_action_ack` on success and an `error` frame — never a fatal one
    /// — on failure (R-11-217, R-11-091), because a `plugin_disabled` or
    /// `action_unknown` Herdr rejection MUST NOT close the Noise session. Called
    /// from `input.rs`'s `host_action` dispatcher.
    pub(super) fn action_plugin_invoke(&self, request: &HostAction) -> Result<Message, WatchError> {
        let plugin_id = request.plugin_id.clone().ok_or_else(|| {
            WatchError::InvalidInput("host_action plugin.invoke requires plugin_id".to_string())
        })?;
        let action_id = request.action_id.clone().ok_or_else(|| {
            WatchError::InvalidInput("host_action plugin.invoke requires action_id".to_string())
        })?;
        let context = self.build_invocation_context(request)?;
        let params = json!({ "plugin_id": plugin_id, "action_id": action_id, "context": context });

        let before = self.snapshot_pane_ids()?;
        if let Err(err) = self.herdr.plugin_action_invoke(params) {
            return Ok(Message::Error(map_watch_error(&WatchError::from(err))));
        }

        thread::sleep(Duration::from_millis(200)); // R-11-217a settle window
        let after = self.snapshot_pane_ids()?;
        let mut new_panes = after.difference(&before);
        // R-11-217a: attribute only when EXACTLY one new pane appeared.
        let only_new = new_panes.next().filter(|_| new_panes.next().is_none());
        let (pane_id, result_id) = match only_new {
            Some(id) => (Some(id.clone()), Some(id.clone())),
            None => (None, None), // R-11-217b: zero, or more than one — attribute nothing
        };

        Ok(Message::HostActionAck(HostActionAck {
            action: HostActionKind::PluginInvoke,
            success: true,
            pane_id,
            result_id,
        }))
    }

    /// R-11-215, R-11-216, R-10-059: builds `PluginInvocationContext` from a fresh
    /// `session.snapshot`, overridden by at most one Device-supplied surface id.
    /// The five Device-hostile fields (`selected_text`, `focused_pane_cwd`,
    /// `workspace_cwd`, `clicked_url`, `link_handler_id`) are never read from
    /// `request` — they are hardcoded `null` below, which is what "the bridge MUST
    /// ignore any such field the Device sends" means in code: there is no code
    /// path that could read them even if the Device sent them.
    fn build_invocation_context(&self, request: &HostAction) -> Result<Value, WatchError> {
        let tree = self.map_snapshot(self.fetch_snapshot()?);
        let mut focused_workspace_id = tree
            .workspaces
            .iter()
            .find(|w| w.focused)
            .map(|w| w.workspace_id.clone());
        let mut focused_tab_id = tree
            .tabs
            .iter()
            .find(|t| t.focused)
            .map(|t| t.tab_id.clone());
        let mut focused_pane_id = tree
            .panes
            .iter()
            .find(|p| p.focused)
            .map(|p| p.pane_id.clone());
        if let Some(workspace_id) = &request.workspace_id {
            focused_workspace_id = Some(workspace_id.clone());
        }
        if let Some(tab_id) = &request.tab_id {
            focused_tab_id = Some(tab_id.clone());
        }
        if let Some(pane_id) = &request.pane_id {
            focused_pane_id = Some(pane_id.clone());
        }
        Ok(json!({
            "focused_workspace_id": focused_workspace_id,
            "focused_tab_id": focused_tab_id,
            "focused_pane_id": focused_pane_id,
            "selected_text": Value::Null,
            "focused_pane_cwd": Value::Null,
            "workspace_cwd": Value::Null,
            "clicked_url": Value::Null,
            "link_handler_id": Value::Null,
            "invocation_source": "herdr-remote",
        }))
    }

    fn snapshot_pane_ids(&self) -> Result<HashSet<String>, WatchError> {
        Ok(self
            .fetch_snapshot()?
            .panes
            .into_iter()
            .map(|p| p.pane_id)
            .collect())
    }
}

/// R-11-210: excludes an action whose `platforms` does not include the Host's
/// current OS. Herdr's schema declares `platforms` as `array | null`; `null`
/// (or an absent key) is unrestricted, distinct from an empty array.
fn platform_matches(action: &Value, host_platform: &str) -> bool {
    match action.get("platforms").and_then(Value::as_array) {
        None => true,
        Some(list) => list.iter().any(|p| p.as_str() == Some(host_platform)),
    }
}

/// R-10-057, R-11-209, R-11-211: projects one raw `plugin.action.list` entry to
/// the five permitted fields, dropping `command`, `manifest_path`, `plugin_root`
/// and every host path by construction — this function never reads them.
fn project_action(raw: Value) -> ActionListEntry {
    let contexts = raw
        .get("contexts")
        .and_then(Value::as_array)
        .map(|arr| {
            arr.iter()
                .filter_map(|c| c.as_str().map(str::to_owned))
                .collect::<Vec<_>>()
        })
        .filter(|c| !c.is_empty());
    ActionListEntry {
        plugin_id: raw
            .get("plugin_id")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string(),
        action_id: raw
            .get("action_id")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string(),
        title: raw
            .get("title")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string(),
        description: raw
            .get("description")
            .and_then(Value::as_str)
            .map(str::to_owned),
        contexts: Some(contexts.unwrap_or_else(|| vec!["global".to_string()])), // R-11-211
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// R-02-025, R-11-210: excludes an action whose `platforms` does not
    /// include the Host's current OS; null/absent `platforms` is unrestricted.
    #[test]
    fn platform_matches_treats_null_platforms_as_unrestricted() {
        assert!(platform_matches(&json!({}), "windows"));
        assert!(platform_matches(
            &json!({ "platforms": ["windows", "linux"] }),
            "windows"
        ));
        assert!(!platform_matches(
            &json!({ "platforms": ["linux"] }),
            "windows"
        ));
    }

    #[test]
    fn project_action_defaults_absent_contexts_to_global_and_drops_host_paths() {
        let raw = json!({
            "plugin_id": "herdr-sidebar",
            "action_id": "pair",
            "title": "Pair",
            "description": null,
            "command": ["/usr/bin/herdr-sidebar", "pair"],
            "manifest_path": "/home/user/.herdr/plugins/herdr-sidebar/herdr-plugin.toml",
            "plugin_root": "/home/user/.herdr/plugins/herdr-sidebar",
        });
        let entry = project_action(raw);
        assert_eq!(entry.plugin_id, "herdr-sidebar");
        assert_eq!(entry.action_id, "pair");
        assert_eq!(entry.contexts, Some(vec!["global".to_string()])); // R-11-211
    }
}
