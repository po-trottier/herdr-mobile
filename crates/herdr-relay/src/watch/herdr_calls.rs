//! What the bridge calls on Herdr, already unwrapped through `result.<payload_key>`
//! (R-41-163).

use serde_json::{Value, json};

use crate::ipc::{HerdrClient, IpcError};

/// What the bridge calls on Herdr, already unwrapped through `result.<payload_key>`
/// (R-41-163). `ipc::HerdrClient` is the real implementation; a test substitutes a
/// stub with no test framework and no real Herdr server, matching the
/// `herdr-scheduled` pattern R-40-029 sets for a shim test.
pub trait HerdrCalls: Send {
    fn session_snapshot(&self) -> Result<Value, IpcError>;
    fn pane_layout(&self, pane_id: &str) -> Result<Value, IpcError>;
    /// R-02-014, R-10-021, R-41-169: `source:"visible"`, `format:"ansi"`,
    /// `strip_ansi:false`.
    fn pane_read_visible(&self, pane_id: &str) -> Result<Value, IpcError>;
    /// R-11-053, R-10-027: `source:"recent"`, `format:"ansi"`, `strip_ansi:false`.
    fn pane_read_recent(&self, pane_id: &str, lines: u32) -> Result<Value, IpcError>;

    /// R-11-056, R-10-041, R-10-042: delivers `send_input`'s `text` and/or `keys`
    /// to the pane. Herdr's own result for `pane.send_input` carries nothing the
    /// bridge needs (`send_input_ack.accepted` is the bridge's own confirmation
    /// that the call succeeded, not a Herdr field), so this returns `()`.
    fn pane_send_input(
        &self,
        pane_id: &str,
        text: Option<&str>,
        keys: Option<&[String]>,
    ) -> Result<(), IpcError>;

    /// R-11-060, R-10-040: submits a prompt to a registered agent, without `wait`
    /// (R-10-043).
    fn agent_prompt(&self, target: &str, text: &str) -> Result<(), IpcError>;
    /// R-10-072: focuses the agent to mark it as seen.
    fn agent_focus(&self, target: &str) -> Result<(), IpcError>;

    /// R-10-054: creates a workspace. Returns the new `workspace_id`, read from
    /// `result.workspace.workspace_id`. Measured live 2026-08-27 against Herdr
    /// `0.8.2-preview.2026-08-19-b5c4a0176e91`: `workspace.create` wraps the whole
    /// created-entity triple — `workspace`, `tab`, `root_pane` — as result
    /// siblings under `type: "workspace_created"`, not one payload key (R-10-007
    /// still holds; the "key" here is the dotted path into that triple).
    fn workspace_create(&self, params: Value) -> Result<String, IpcError>;

    /// R-10-054: creates a tab. Returns the new `tab_id`, read from
    /// `result.tab.tab_id`. Measured live: `type: "tab_created"`, fields `tab` and
    /// `root_pane`.
    fn tab_create(&self, params: Value) -> Result<String, IpcError>;

    /// R-11-202 `pane.split` (create) and `split` (existing-pane split) both call
    /// this: same Herdr method, same result shape, different `params` built by the
    /// caller (R-11-201's field table). Returns the new `pane_id`, read from
    /// `result.pane.pane_id`. Measured live: `type: "pane_info"` — the same shape a
    /// plain pane lookup carries. `herdr api schema --json`'s `ResponseResult`
    /// union has no distinct `pane_split` result variant, so this was measured, not
    /// assumed.
    fn pane_split(&self, params: Value) -> Result<String, IpcError>;

    /// R-11-202 `zoom` -> `pane.zoom`.
    fn pane_zoom(&self, pane_id: &str, mode: &str) -> Result<(), IpcError>;

    /// R-11-202 `close` -> `pane.close`. Herdr takes `pane_id` at the top level of
    /// `params`, with no nested params struct (R-02-020).
    fn pane_close(&self, pane_id: &str) -> Result<(), IpcError>;

    /// R-11-202 `rename` -> `pane.rename`. `label: None` clears the label
    /// (R-02-022).
    fn pane_rename(&self, pane_id: &str, label: Option<&str>) -> Result<(), IpcError>;

    /// R-11-202 `resize` -> `pane.resize`. `amount: None` omits the field; Herdr
    /// requires only `direction` (R-02-020's Required column).
    fn pane_resize(
        &self,
        pane_id: &str,
        direction: &str,
        amount: Option<f64>,
    ) -> Result<(), IpcError>;

    /// R-10-056: enumerates every plugin action, unfiltered and unprojected. The
    /// bridge projects and filters before it reaches the Device (R-10-057,
    /// R-11-209, R-11-210).
    fn plugin_action_list(&self) -> Result<Value, IpcError>;

    /// R-10-058: invokes one plugin action. Returns the raw `result.invoke` value;
    /// the bridge does not need any field from it beyond "the call succeeded"
    /// today, but keeps the value in case a future action surfaces one.
    fn plugin_action_invoke(&self, params: Value) -> Result<Value, IpcError>;
}

impl HerdrCalls for HerdrClient {
    fn session_snapshot(&self) -> Result<Value, IpcError> {
        self.call_result("session.snapshot", json!({}), "snapshot")
    }

    fn pane_layout(&self, pane_id: &str) -> Result<Value, IpcError> {
        self.call_result("pane.layout", json!({ "pane_id": pane_id }), "layout")
    }

    fn pane_read_visible(&self, pane_id: &str) -> Result<Value, IpcError> {
        self.call_result(
            "pane.read",
            json!({
                "pane_id": pane_id,
                "source": "visible",
                "format": "ansi",
                "strip_ansi": false,
            }),
            "read",
        )
    }

    fn pane_read_recent(&self, pane_id: &str, lines: u32) -> Result<Value, IpcError> {
        self.call_result(
            "pane.read",
            json!({
                "pane_id": pane_id,
                "source": "recent",
                "format": "ansi",
                "strip_ansi": false,
                "lines": lines,
            }),
            "read",
        )
    }

    fn pane_send_input(
        &self,
        pane_id: &str,
        text: Option<&str>,
        keys: Option<&[String]>,
    ) -> Result<(), IpcError> {
        let mut params = json!({ "pane_id": pane_id });
        if let Some(text) = text {
            params["text"] = json!(text);
        }
        if let Some(keys) = keys {
            params["keys"] = json!(keys);
        }
        self.call("pane.send_input", params)?;
        Ok(())
    }

    fn agent_prompt(&self, target: &str, text: &str) -> Result<(), IpcError> {
        self.call("agent.prompt", json!({ "target": target, "text": text }))?;
        Ok(())
    }
    fn agent_focus(&self, target: &str) -> Result<(), IpcError> {
        self.call("agent.focus", json!({"target": target}))?;
        Ok(())
    }

    fn workspace_create(&self, params: Value) -> Result<String, IpcError> {
        let envelope = self.call("workspace.create", params)?;
        nested_id(
            &envelope,
            "workspace.create",
            &["workspace", "workspace_id"],
        )
    }

    fn tab_create(&self, params: Value) -> Result<String, IpcError> {
        let envelope = self.call("tab.create", params)?;
        nested_id(&envelope, "tab.create", &["tab", "tab_id"])
    }

    fn pane_split(&self, params: Value) -> Result<String, IpcError> {
        let envelope = self.call("pane.split", params)?;
        nested_id(&envelope, "pane.split", &["pane", "pane_id"])
    }

    fn pane_zoom(&self, pane_id: &str, mode: &str) -> Result<(), IpcError> {
        self.call("pane.zoom", json!({ "pane_id": pane_id, "mode": mode }))?;
        Ok(())
    }

    fn pane_close(&self, pane_id: &str) -> Result<(), IpcError> {
        self.call("pane.close", json!({ "pane_id": pane_id }))?;
        Ok(())
    }

    fn pane_rename(&self, pane_id: &str, label: Option<&str>) -> Result<(), IpcError> {
        self.call("pane.rename", json!({ "pane_id": pane_id, "label": label }))?;
        Ok(())
    }

    fn pane_resize(
        &self,
        pane_id: &str,
        direction: &str,
        amount: Option<f64>,
    ) -> Result<(), IpcError> {
        let mut params = json!({ "pane_id": pane_id, "direction": direction });
        if let Some(amount) = amount {
            params["amount"] = json!(amount);
        }
        self.call("pane.resize", params)?;
        Ok(())
    }

    fn plugin_action_list(&self) -> Result<Value, IpcError> {
        self.call_result("plugin.action.list", json!({}), "actions")
    }

    fn plugin_action_invoke(&self, params: Value) -> Result<Value, IpcError> {
        // R-10-058 and `docs/11-relay-protocol.md` §2.2 claim the payload key is
        // `invoke`, but `herdr api schema --json`'s `ResponseResult` union carries
        // no `invoke` field for this method (measured live 2026-08-27): the result
        // type is `plugin_action_invoked`, with sibling fields `action`, `context`
        // and `log` directly under `result` — the same "flat siblings, no wrapper
        // key" shape `workspace_created` uses, not `pane.read`'s single-key wrap.
        // Read `result` whole rather than through a payload key this build does
        // not have.
        let envelope = self.call("plugin.action.invoke", params)?;
        envelope
            .get("result")
            .cloned()
            .ok_or_else(|| IpcError::MissingPayload {
                method: "plugin.action.invoke".to_string(),
                key: "result".to_string(),
            })
    }
}

/// Reads a nested id field out of a raw call envelope's `result`, for a create
/// call whose new-entity id sits under more than one key (measured live:
/// `workspace.create`, `tab.create` and `pane.split` all do this — see the trait
/// doc-comments above for the exact shape of each).
fn nested_id(envelope: &Value, method: &'static str, path: &[&str]) -> Result<String, IpcError> {
    let mut current = envelope
        .get("result")
        .ok_or_else(|| IpcError::MissingPayload {
            method: method.to_string(),
            key: "result".to_string(),
        })?;
    for segment in path {
        current = current
            .get(segment)
            .ok_or_else(|| IpcError::MissingPayload {
                method: method.to_string(),
                key: path.join("."),
            })?;
    }
    current
        .as_str()
        .map(str::to_owned)
        .ok_or_else(|| IpcError::MissingPayload {
            method: method.to_string(),
            key: path.join("."),
        })
}
