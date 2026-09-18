//! Phase 7: `send_input`, `agent_prompt`, and `host_action`'s create and pane
//! operations (`docs/10-herdr-integration.md` §6, `docs/11-relay-protocol.md`
//! §4.12 through §4.17). `plugin.invoke` and `action_list_request` live in
//! `plugin_actions.rs`, and the shared error mapper lives in `error_map.rs`
//! (R-11-091) — both split out once this file crossed the R-41-010 400-line cap,
//! per `docs/90-implementation-plan.md` Phase 7's own guidance. Added onto
//! [`super::Bridge`] alongside `requests.rs`'s Phase 6 handlers (module
//! doc-comment in `watch.rs`).

use std::time::Instant;

use serde_json::{Value, json};
use unicode_segmentation::UnicodeSegmentation;

use herdr_relay_proto::messages::{
    AgentPrompt, AgentPromptAck, HostAction, HostActionAck, HostActionKind, Message, SendInput,
    SendInputAck,
};

use super::bridge::{Bridge, WatchError, lock_observed};
use super::herdr_calls::HerdrCalls;
use super::key_map::validate_key;

impl<H: HerdrCalls> Bridge<H> {
    /// `send_input` -> `send_input_ack` (R-11-054, R-11-055, R-11-056, R-11-227).
    /// R-01-006/R-01-007: refuses a `pane_id` that is not the one this Device is
    /// currently watching, before anything reaches Herdr. That check also keeps
    /// the R-10-071 reads below off an unwatched pane: there is no scheduler for
    /// one, and this returns before any arming.
    pub fn send_input(&mut self, request: SendInput) -> Result<Message, WatchError> {
        self.require_watched(&request.pane_id)?;
        validate_send_input(&request)?;
        if request.keys.as_ref().is_some_and(|keys| {
            keys.iter()
                .any(|key| key.eq_ignore_ascii_case("Enter") || key.eq_ignore_ascii_case("ctrl+c"))
        }) {
            self.cancel_pending_inputs();
        }
        // ponytail: one global input lock. Use per-pane locks if concurrent Devices need them.
        let mut lines = lock_observed(&self.input_lines);
        let old = lines.entry(request.pane_id.clone()).or_default();
        let old_len = old.len();
        let accepted = if let Some(line) = &request.line {
            self.reconcile_line(&request.pane_id, old, line).is_ok()
        } else {
            self.forward_input(&request, old).is_ok()
        };
        if accepted && let Some(line) = request.line {
            *old = line;
        }
        let changed = old.len() != old_len;
        drop(lines);
        // R-10-071: restart the read schedule after a successful write.
        if (accepted || changed)
            && let Some(scheduler) = &mut self.scheduler
        {
            scheduler.on_input_sent(Instant::now());
        }
        Ok(Message::SendInputAck(SendInputAck {
            pane_id: request.pane_id,
            accepted,
            queued: false,
        }))
    }

    fn send_typed_text(&self, pane_id: &str, text: &str) -> Result<(), WatchError> {
        if text.contains('\n') {
            self.herdr.pane_send_input(pane_id, Some(text), None)?;
        } else {
            self.herdr.pane_send_text(pane_id, text)?;
        }
        Ok(())
    }

    fn forward_input(&self, request: &SendInput, shadow: &mut String) -> Result<(), WatchError> {
        if let Some(text) = &request.text {
            self.send_typed_text(&request.pane_id, text)?;
            shadow.push_str(text);
        }
        if let Some(keys) = &request.keys {
            self.herdr
                .pane_send_input(&request.pane_id, None, Some(keys))?;
            if keys.iter().any(|key| {
                key.eq_ignore_ascii_case("Enter")
                    || key.eq_ignore_ascii_case("Return")
                    || key.eq_ignore_ascii_case("ctrl+c")
            }) {
                shadow.clear();
            } else {
                for key in keys {
                    if key.eq_ignore_ascii_case("Backspace") {
                        shadow.truncate(
                            shadow
                                .grapheme_indices(true)
                                .next_back()
                                .map_or(0, |(i, _)| i),
                        );
                    }
                }
            }
        }
        Ok(())
    }

    fn reconcile_line(
        &self,
        pane_id: &str,
        old: &mut String,
        line: &str,
    ) -> Result<(), WatchError> {
        let prefix_bytes: usize = old
            .graphemes(true)
            .zip(line.graphemes(true))
            .take_while(|(a, b)| a == b)
            .map(|(a, _)| a.len())
            .sum();
        let remove = old[prefix_bytes..].graphemes(true).count();
        if remove != 0 {
            let keys = vec!["Backspace".to_owned(); remove.min(64)];
            let mut remaining = remove;
            while remaining != 0 {
                let count = remaining.min(keys.len());
                self.herdr
                    .pane_send_input(pane_id, None, Some(&keys[..count]))?;
                let keep = old.len()
                    - old
                        .graphemes(true)
                        .rev()
                        .take(count)
                        .map(str::len)
                        .sum::<usize>();
                old.truncate(keep);
                remaining -= count;
            }
        }
        let tail = &line[prefix_bytes..];
        if !tail.is_empty() {
            self.send_typed_text(pane_id, tail)?;
        }
        Ok(())
    }

    /// `agent_prompt` -> `agent_prompt_ack` (R-11-060, R-10-040, R-10-043): maps
    /// straight to `agent.prompt` with no `wait`, distinct from `send_input`'s
    /// (`pane.send_input`) path (R-11-056).
    pub fn agent_prompt(&self, request: AgentPrompt) -> Result<Message, WatchError> {
        self.herdr.agent_prompt(&request.target, &request.text)?;
        Ok(Message::AgentPromptAck(AgentPromptAck {
            target: request.target,
            accepted: true,
        }))
    }

    /// `host_action` -> `host_action_ack` (R-11-201, R-11-202). `plugin.invoke`
    /// (`plugin_actions.rs`) replies directly (its own `error`-frame path on
    /// failure, R-11-217); every other action shares one `HostActionAck` builder.
    /// `HostActionKind` has no variant for `server.stop`, `workspace.close` or
    /// `tab.close` (R-11-204), so those are unreachable by construction, not by a
    /// runtime check.
    pub fn host_action(&self, request: HostAction) -> Result<Message, WatchError> {
        if matches!(request.action, HostActionKind::PluginInvoke) {
            return self.action_plugin_invoke(&request);
        }
        let (success, pane_id, result_id) = match request.action {
            HostActionKind::WorkspaceCreate => self.action_workspace_create(&request)?,
            HostActionKind::TabCreate => self.action_tab_create(&request)?,
            HostActionKind::PaneSplit => self.action_pane_split_create(&request)?,
            HostActionKind::Split => self.action_pane_split_existing(&request)?,
            HostActionKind::Zoom => self.action_pane_zoom(&request)?,
            HostActionKind::Close => self.action_pane_close(&request)?,
            HostActionKind::Rename => self.action_pane_rename(&request)?,
            HostActionKind::Resize => self.action_pane_resize(&request)?,
            HostActionKind::PluginInvoke => unreachable!("handled above"),
        };
        Ok(Message::HostActionAck(HostActionAck {
            action: request.action,
            success,
            pane_id,
            result_id,
        }))
    }

    pub(super) fn require_watched(&self, pane_id: &str) -> Result<(), WatchError> {
        match &self.watched {
            Some(watched) if watched.pane_id == pane_id => Ok(()),
            _ => Err(WatchError::NotWatching(pane_id.to_string())),
        }
    }

    fn action_workspace_create(
        &self,
        request: &HostAction,
    ) -> Result<(bool, Option<String>, Option<String>), WatchError> {
        let mut params = base_create_params(&request.params);
        if let Some(label) = param_str(&request.params, "label") {
            params["label"] = json!(label);
        }
        let workspace_id = self.herdr.workspace_create(params)?;
        Ok((true, None, Some(workspace_id)))
    }

    fn action_tab_create(
        &self,
        request: &HostAction,
    ) -> Result<(bool, Option<String>, Option<String>), WatchError> {
        let mut params = base_create_params(&request.params);
        if let Some(label) = param_str(&request.params, "label") {
            params["label"] = json!(label);
        }
        if let Some(workspace_id) = &request.workspace_id {
            params["workspace_id"] = json!(workspace_id);
        }
        let tab_id = self.herdr.tab_create(params)?;
        Ok((true, None, Some(tab_id)))
    }

    /// `pane.split` as a create action (R-11-202): `direction` is the only
    /// required field (R-02-020); `pane.split` carries no `label`
    /// (`PaneSplitParams` has none — R-02-020).
    fn action_pane_split_create(
        &self,
        request: &HostAction,
    ) -> Result<(bool, Option<String>, Option<String>), WatchError> {
        let direction = require_param_str(&request.params, "direction")?.to_string();
        let mut params = base_create_params(&request.params);
        params["direction"] = json!(direction);
        if let Some(ratio) = param_f64(&request.params, "ratio") {
            params["ratio"] = json!(ratio);
        }
        if let Some(workspace_id) = &request.workspace_id {
            params["workspace_id"] = json!(workspace_id);
        }
        let target_pane_id = request
            .pane_id
            .clone()
            .or_else(|| param_str(&request.params, "target_pane_id").map(str::to_owned));
        if let Some(target) = &target_pane_id {
            params["target_pane_id"] = json!(target);
        }
        let new_pane_id = self.herdr.pane_split(params)?;
        Ok((true, target_pane_id, Some(new_pane_id)))
    }

    /// `split`: splits an existing pane (R-11-202 maps this to the same Herdr
    /// `pane.split` method as the create action, with a smaller params shape:
    /// `{"direction":..,"focus":false}`).
    fn action_pane_split_existing(
        &self,
        request: &HostAction,
    ) -> Result<(bool, Option<String>, Option<String>), WatchError> {
        let pane_id = require_pane_id(request)?;
        let direction = require_param_str(&request.params, "direction")?;
        let params = json!({ "target_pane_id": pane_id, "direction": direction, "focus": false });
        let new_pane_id = self.herdr.pane_split(params)?;
        Ok((true, Some(pane_id), Some(new_pane_id)))
    }

    fn action_pane_zoom(
        &self,
        request: &HostAction,
    ) -> Result<(bool, Option<String>, Option<String>), WatchError> {
        let pane_id = require_pane_id(request)?;
        let mode = param_str(&request.params, "mode").unwrap_or("toggle"); // R-02-023
        self.herdr.pane_zoom(&pane_id, mode)?;
        Ok((true, Some(pane_id), None))
    }

    fn action_pane_close(
        &self,
        request: &HostAction,
    ) -> Result<(bool, Option<String>, Option<String>), WatchError> {
        let pane_id = require_pane_id(request)?;
        self.herdr.pane_close(&pane_id)?;
        Ok((true, Some(pane_id), None))
    }

    fn action_pane_rename(
        &self,
        request: &HostAction,
    ) -> Result<(bool, Option<String>, Option<String>), WatchError> {
        let pane_id = require_pane_id(request)?;
        let label = param_str(&request.params, "label"); // R-02-022: absent/null clears it
        self.herdr.pane_rename(&pane_id, label)?;
        Ok((true, Some(pane_id), None))
    }

    fn action_pane_resize(
        &self,
        request: &HostAction,
    ) -> Result<(bool, Option<String>, Option<String>), WatchError> {
        let pane_id = require_pane_id(request)?;
        let direction = require_param_str(&request.params, "direction")?;
        let amount = param_f64(&request.params, "amount");
        self.herdr.pane_resize(&pane_id, direction, amount)?;
        Ok((true, Some(pane_id), None))
    }
}

/// R-11-054 steps 1-3: validates `send_input`'s `text`/`keys` before it reaches
/// Herdr. `text` passes through unchanged — the Device resolves a printable
/// character (step 1) and each of the six unnamed keys (step 2, R-10-036) to
/// bytes itself before sending, so the bridge's job is only to confirm they made
/// it here unmangled. Every `keys` entry (step 3) is validated against the
/// accepted vocabulary (`key_map::validate_key`, R-10-036 through R-10-039); a
/// `keys` entry naming one of the six unnamed keys by its table name (`"Home"`,
/// not its raw sequence) is rejected here, matching §6.3's own "no logical name
/// exists" row, rather than silently reinterpreted. Step 4 (a committed
/// multi-character string on an agent pane) is not this function's concern: the
/// Device sends that as its own `agent_prompt` message (section 4.14), never as
/// `send_input`.
pub(super) fn validate_send_input(request: &SendInput) -> Result<(), WatchError> {
    if request.defer.is_some() {
        return Err(WatchError::InvalidInput(
            "deferred input requires the deferred handler".to_owned(),
        ));
    }
    if request.line.is_some() {
        return if request.text.is_some() || request.keys.is_some() {
            Err(WatchError::InvalidInput(
                "line cannot include text or keys".to_owned(),
            ))
        } else {
            Ok(())
        };
    }
    if request.text.is_none() && request.keys.as_ref().is_none_or(|k| k.is_empty()) {
        return Err(WatchError::InvalidInput(
            "send_input carried neither text nor keys".to_string(),
        ));
    }
    for key in request.keys.iter().flatten() {
        validate_key(key).map_err(|e| WatchError::InvalidInput(e.to_string()))?;
    }
    Ok(())
}

fn require_pane_id(request: &HostAction) -> Result<String, WatchError> {
    request.pane_id.clone().ok_or_else(|| {
        WatchError::InvalidInput(format!("host_action {:?} requires pane_id", request.action))
    })
}

fn require_param_str<'a>(params: &'a Option<Value>, key: &str) -> Result<&'a str, WatchError> {
    param_str(params, key).ok_or_else(|| {
        WatchError::InvalidInput(format!("host_action params missing required field {key:?}"))
    })
}

fn param_str<'a>(params: &'a Option<Value>, key: &str) -> Option<&'a str> {
    params.as_ref()?.get(key)?.as_str()
}

fn param_f64(params: &Option<Value>, key: &str) -> Option<f64> {
    params.as_ref()?.get(key)?.as_f64()
}

/// R-11-203: `focus: false` on every create action, unconditionally — the Device
/// MUST send it as `false`, so this never reads a Device-supplied `focus` value.
/// `cwd` and `env` are the two optional fields every create action shares
/// (`docs/10-herdr-integration.md` §3.8's table); `label` is added by the two
/// callers that have one (`pane.split` has none — R-02-020).
fn base_create_params(params: &Option<Value>) -> Value {
    let mut out = json!({ "focus": false });
    if let Some(cwd) = param_str(params, "cwd") {
        out["cwd"] = json!(cwd);
    }
    if let Some(env) = params.as_ref().and_then(|p| p.get("env")) {
        out["env"] = env.clone();
    }
    out
}

#[cfg(test)]
mod tests {
    use std::sync::Mutex;

    use super::super::bridge::HostIdentity;
    use super::*;
    use crate::config::RelayConfig;
    use crate::ipc::IpcError;

    /// R-10-072, R-11-240: focus has no reads or retries, including a rejected call.
    #[test]
    fn mark_seen_calls_focus_once_without_reads_or_retries() {
        use herdr_relay_proto::codes::ErrorCode;
        use herdr_relay_proto::messages::MarkSeen;
        for reject_focus in [false, true] {
            let bridge = Bridge::new(
                StubCalls {
                    reject_focus,
                    ..Default::default()
                },
                HostIdentity {
                    host_id: "host".to_owned(),
                    host_name: "test".to_owned(),
                },
                RelayConfig::default(),
            );
            let result = bridge.mark_seen(MarkSeen {
                pane_id: "w28:p1R".to_owned(),
            });
            assert_eq!(*bridge.herdr.focus_calls.lock().unwrap(), ["w28:p1R"]);
            if reject_focus {
                let mapped = super::super::map_watch_error(&result.unwrap_err());
                assert_eq!(mapped.code, ErrorCode::PaneNotFound);
                assert!(!mapped.fatal);
            } else {
                result.unwrap();
            }
        }
    }

    /// Captures the arguments the four pane actions under test forward to
    /// Herdr; every other `HerdrCalls` method is unreachable from these tests.
    #[derive(Default)]
    struct StubCalls {
        pane_split_params: Mutex<Vec<Value>>,
        pane_resize_calls: Mutex<Vec<(String, String, Option<f64>)>>,
        pane_rename_calls: Mutex<Vec<(String, Option<String>)>>,
        pane_zoom_calls: Mutex<Vec<(String, String)>>,
        focus_calls: Mutex<Vec<String>>,
        reject_focus: bool,
        working: bool,
        input_keys: Mutex<Vec<Vec<String>>>,
    }

    impl HerdrCalls for StubCalls {
        fn pane_send_text(&self, _pane_id: &str, _text: &str) -> Result<(), IpcError> {
            unimplemented!("not exercised by this test")
        }
        fn session_snapshot(&self) -> Result<Value, IpcError> {
            Ok(
                json!({"agents": [{"pane_id": "p", "agent": "test", "agent_status": if self.working { "working" } else { "idle" }}]}),
            )
        }
        fn pane_layout(&self, _pane_id: &str) -> Result<Value, IpcError> {
            unimplemented!("not exercised by this test")
        }
        fn pane_read_visible(&self, _pane_id: &str) -> Result<Value, IpcError> {
            unimplemented!("not exercised by this test")
        }
        fn pane_read_recent(&self, _pane_id: &str, _lines: u32) -> Result<Value, IpcError> {
            unimplemented!("not exercised by this test")
        }
        fn pane_send_input(
            &self,
            _pane_id: &str,
            _text: Option<&str>,
            _keys: Option<&[String]>,
        ) -> Result<(), IpcError> {
            self.input_keys
                .lock()
                .unwrap()
                .push(_keys.unwrap_or_default().to_vec());
            Ok(())
        }
        fn agent_focus(&self, target: &str) -> Result<(), IpcError> {
            self.focus_calls.lock().unwrap().push(target.to_owned());
            if self.reject_focus {
                return Err(IpcError::Rejected {
                    method: "agent.focus".to_owned(),
                    code: "agent_not_found".to_owned(),
                    message: "agent not found".to_owned(),
                });
            }
            Ok(())
        }
        fn agent_prompt(&self, _target: &str, _text: &str) -> Result<(), IpcError> {
            unimplemented!("not exercised by this test")
        }
        fn workspace_create(&self, _params: Value) -> Result<String, IpcError> {
            unimplemented!("not exercised by this test")
        }
        fn tab_create(&self, _params: Value) -> Result<String, IpcError> {
            unimplemented!("not exercised by this test")
        }
        fn pane_split(&self, params: Value) -> Result<String, IpcError> {
            self.pane_split_params
                .lock()
                .expect("stub mutex is never poisoned")
                .push(params);
            Ok("w1:new".to_string())
        }
        fn pane_zoom(&self, pane_id: &str, mode: &str) -> Result<(), IpcError> {
            self.pane_zoom_calls
                .lock()
                .expect("stub mutex is never poisoned")
                .push((pane_id.to_string(), mode.to_string()));
            Ok(())
        }
        fn pane_close(&self, _pane_id: &str) -> Result<(), IpcError> {
            unimplemented!("not exercised by this test")
        }
        fn pane_rename(&self, pane_id: &str, label: Option<&str>) -> Result<(), IpcError> {
            self.pane_rename_calls
                .lock()
                .expect("stub mutex is never poisoned")
                .push((pane_id.to_string(), label.map(str::to_owned)));
            Ok(())
        }
        fn pane_resize(
            &self,
            pane_id: &str,
            direction: &str,
            amount: Option<f64>,
        ) -> Result<(), IpcError> {
            self.pane_resize_calls
                .lock()
                .expect("stub mutex is never poisoned")
                .push((pane_id.to_string(), direction.to_string(), amount));
            Ok(())
        }
        fn plugin_action_list(&self) -> Result<Value, IpcError> {
            unimplemented!("not exercised by this test")
        }
        fn plugin_action_invoke(&self, _params: Value) -> Result<Value, IpcError> {
            unimplemented!("not exercised by this test")
        }
    }

    fn bridge() -> Bridge<StubCalls> {
        let identity = HostIdentity {
            host_id: "host-1".to_string(),
            host_name: "test-host".to_string(),
        };
        Bridge::new(StubCalls::default(), identity, RelayConfig::default())
    }

    /// R-02-020: `pane.split`'s create action never carries a `label` key, even
    /// when the Device's `host_action.params` supplies one — unlike
    /// `workspace.create`/`tab.create`, which do forward it.
    #[test]
    fn pane_split_create_never_forwards_a_label() {
        let bridge = bridge();
        bridge
            .host_action(HostAction {
                action: HostActionKind::PaneSplit,
                pane_id: Some("w1:p1".to_string()),
                workspace_id: None,
                tab_id: None,
                plugin_id: None,
                action_id: None,
                params: Some(json!({ "direction": "right", "label": "should be dropped" })),
            })
            .expect("pane.split create succeeds against the stub");
        let sent = bridge.herdr.pane_split_params.lock().unwrap();
        assert_eq!(sent.len(), 1);
        assert_eq!(sent[0]["direction"], json!("right"));
        assert!(
            sent[0].get("label").is_none(),
            "pane.split create params carried a label key: {:?}",
            sent[0]
        );
    }

    /// R-02-021: `resize` forwards only `direction`/`amount` to
    /// `HerdrCalls::pane_resize`'s typed parameters — extra `width`/`height`/
    /// `column`/`row` fields on the Device's `params` never reach Herdr.
    #[test]
    fn pane_resize_forwards_only_direction_and_amount() {
        let bridge = bridge();
        bridge
            .host_action(HostAction {
                action: HostActionKind::Resize,
                pane_id: Some("w1:p1".to_string()),
                workspace_id: None,
                tab_id: None,
                plugin_id: None,
                action_id: None,
                params: Some(json!({
                    "direction": "right",
                    "amount": 12.5,
                    "width": 999,
                    "height": 999,
                    "column": 1,
                    "row": 1,
                })),
            })
            .expect("resize succeeds against the stub");
        let calls = bridge.herdr.pane_resize_calls.lock().unwrap();
        assert_eq!(
            calls[0],
            ("w1:p1".to_string(), "right".to_string(), Some(12.5))
        );
    }

    /// R-02-022: an absent or `null` `label` forwards `label: None`, clearing
    /// the label rather than erroring or leaving it unchanged.
    #[test]
    fn pane_rename_forwards_none_for_absent_or_null_label() {
        let bridge = bridge();
        bridge
            .host_action(HostAction {
                action: HostActionKind::Rename,
                pane_id: Some("w1:p1".to_string()),
                workspace_id: None,
                tab_id: None,
                plugin_id: None,
                action_id: None,
                params: Some(json!({ "label": null })),
            })
            .expect("rename with a null label succeeds against the stub");
        bridge
            .host_action(HostAction {
                action: HostActionKind::Rename,
                pane_id: Some("w1:p1".to_string()),
                workspace_id: None,
                tab_id: None,
                plugin_id: None,
                action_id: None,
                params: None,
            })
            .expect("rename with no params succeeds against the stub");
        let calls = bridge.herdr.pane_rename_calls.lock().unwrap();
        assert_eq!(calls[0], ("w1:p1".to_string(), None));
        assert_eq!(calls[1], ("w1:p1".to_string(), None));
    }

    /// R-02-023: `zoom` defaults `mode` to `"toggle"` when the Device omits it,
    /// and otherwise forwards the Device-supplied mode unchanged.
    #[test]
    fn pane_zoom_defaults_mode_to_toggle_and_otherwise_forwards_it() {
        let bridge = bridge();
        bridge
            .host_action(HostAction {
                action: HostActionKind::Zoom,
                pane_id: Some("w1:p1".to_string()),
                workspace_id: None,
                tab_id: None,
                plugin_id: None,
                action_id: None,
                params: None,
            })
            .expect("zoom with no params succeeds against the stub");
        bridge
            .host_action(HostAction {
                action: HostActionKind::Zoom,
                pane_id: Some("w1:p1".to_string()),
                workspace_id: None,
                tab_id: None,
                plugin_id: None,
                action_id: None,
                params: Some(json!({ "mode": "off" })),
            })
            .expect("zoom with an explicit mode succeeds against the stub");
        let calls = bridge.herdr.pane_zoom_calls.lock().unwrap();
        assert_eq!(calls[0], ("w1:p1".to_string(), "toggle".to_string()));
        assert_eq!(calls[1], ("w1:p1".to_string(), "off".to_string()));
    }
    #[test]
    fn held_submit_lifecycle() {
        use super::super::bridge::WatchedPane;
        use herdr_relay_proto::messages::{Defer, UnwatchPane};

        let mut bridge = Bridge::new(
            StubCalls {
                working: true,
                ..Default::default()
            },
            HostIdentity {
                host_id: "h".into(),
                host_name: "h".into(),
            },
            RelayConfig::default(),
        );
        bridge.watched = Some(WatchedPane {
            pane_id: "p".into(),
            last_revision: 0,
            viewport_rows: 24,
            width: 80,
            last_frame_hash: 0,
        });
        let request = || SendInput {
            pane_id: "p".into(),
            line: None,
            text: None,
            keys: Some(vec!["Enter".into()]),
            defer: Some(Defer::UntilIdle),
        };
        let ack = |corr: &str, accepted, queued| {
            (
                Message::SendInputAck(SendInputAck {
                    pane_id: "p".into(),
                    accepted,
                    queued,
                }),
                Some(corr.to_owned()),
            )
        };
        assert_eq!(
            bridge.handle_deferred_input(request(), Some("a".into())),
            vec![ack("a", true, true)]
        );
        assert!(bridge.herdr.input_keys.lock().unwrap().is_empty());
        assert_eq!(
            bridge.handle_deferred_input(request(), Some("b".into())),
            vec![ack("a", false, false), ack("b", true, true)]
        );
        lock_observed(&bridge.input_lines).insert("p".into(), "draft".into());
        bridge.handle_subscription_line(r#"{"event":"pane_agent_status_changed","data":{"pane_id":"p","agent_status":"idle"}}"#).unwrap();
        assert_eq!(bridge.take_input_replies(), vec![ack("b", true, false)]);
        assert!(bridge.take_input_replies().is_empty());
        assert_eq!(
            *bridge.herdr.input_keys.lock().unwrap(),
            vec![vec!["Enter".to_owned()]]
        );
        assert_eq!(lock_observed(&bridge.input_lines).get("p").unwrap(), "");
        bridge.handle_deferred_input(request(), Some("c".into()));
        let cancel = || SendInput {
            pane_id: "p".into(),
            line: None,
            text: None,
            keys: None,
            defer: Some(Defer::Cancel),
        };
        assert_eq!(
            bridge.handle_deferred_input(cancel(), Some("cancel".into())),
            vec![ack("c", false, false), ack("cancel", true, false)]
        );
        bridge.herdr.working = false;
        assert_eq!(
            bridge.handle_deferred_input(request(), Some("d".into())),
            vec![ack("d", true, false)]
        );
        assert_eq!(bridge.herdr.input_keys.lock().unwrap().len(), 2);
        bridge.herdr.working = true;
        let mut invalid = request();
        invalid.text = Some("bad".into());
        assert_eq!(
            bridge.handle_deferred_input(invalid, Some("invalid".into())),
            vec![ack("invalid", false, false)]
        );
        assert_eq!(bridge.herdr.input_keys.lock().unwrap().len(), 2);
        for key in ["Enter", "ctrl+c"] {
            bridge.handle_deferred_input(request(), Some(key.into()));
            let mut interrupt = request();
            interrupt.defer = None;
            interrupt.keys = Some(vec![key.into()]);
            assert_eq!(
                bridge.send_input(interrupt).unwrap(),
                ack("unused", true, false).0
            );
            assert_eq!(bridge.take_input_replies(), vec![ack(key, false, false)]);
        }
        assert_eq!(
            *bridge.herdr.input_keys.lock().unwrap(),
            vec![
                vec!["Enter".to_owned()],
                vec!["Enter".to_owned()],
                vec!["Enter".to_owned()],
                vec!["ctrl+c".to_owned()]
            ]
        );
        bridge.handle_deferred_input(request(), Some("session-end".into()));
        bridge.session_active = Some(std::sync::Arc::new(std::sync::atomic::AtomicBool::new(
            false,
        )));
        bridge.handle_subscription_line(r#"{"event":"pane_agent_status_changed","data":{"pane_id":"p","agent_status":"idle"}}"#).unwrap();
        assert_eq!(
            bridge.take_input_replies(),
            vec![ack("session-end", false, false)]
        );
        assert_eq!(bridge.herdr.input_keys.lock().unwrap().len(), 4);
        bridge.session_active = None;
        bridge.handle_deferred_input(request(), Some("e".into()));
        bridge.unwatch_pane(UnwatchPane {
            pane_id: "other".into(),
        });
        assert!(bridge.take_input_replies().is_empty());
        bridge.unwatch_pane(UnwatchPane {
            pane_id: "p".into(),
        });
        assert_eq!(bridge.take_input_replies(), vec![ack("e", false, false)]);
        assert_eq!(
            bridge.handle_deferred_input(cancel(), Some("cancel".into())),
            vec![ack("cancel", true, false)]
        );
        assert_eq!(bridge.herdr.input_keys.lock().unwrap().len(), 4);
    }
}
