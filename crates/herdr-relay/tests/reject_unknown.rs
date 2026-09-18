//! `docs/90-implementation-plan.md` Phase 7: "asserting a `send_input` naming an
//! unwatched `pane_id` is refused" (R-01-006). The Device MUST NOT be given a
//! `pane_id` it did not receive from the bridge, and the bridge enforces that for
//! `send_input` by restricting it to the one pane this Device is watching
//! (R-01-007, R-10-033) — never blindly trusting whatever `pane_id` the wire
//! message names.

use std::sync::Arc;
use std::sync::atomic::{AtomicU32, Ordering};

use herdr_relay::config::RelayConfig;
use herdr_relay::ipc::IpcError;
use herdr_relay::watch::{Bridge, HerdrCalls, HostIdentity, WatchError};
use herdr_relay_proto::messages::{SendInput, WatchPane};
use serde_json::{Value, json};

struct StubHerdr {
    send_input_calls: Arc<AtomicU32>,
}

impl HerdrCalls for StubHerdr {
    fn session_snapshot(&self) -> Result<Value, IpcError> {
        Ok(json!({
            "workspaces": [],
            "tabs": [],
            "panes": [{
                "pane_id": "w1:p1",
                "workspace_id": "w1",
                "tab_id": "t1",
                "terminal_id": "term1",
                "label": "shell",
                "title": "shell",
                "cwd": "/home",
                "focused": true,
                "agent": null,
                "agent_status": "idle",
                "revision": 0,
                "scroll": {"offset_from_bottom": 0, "max_offset_from_bottom": 0, "viewport_rows": 50},
            }],
            "agents": [],
        }))
    }

    fn pane_layout(&self, _pane_id: &str) -> Result<Value, IpcError> {
        Ok(json!({ "panes": [{"pane_id": "w1:p1", "rect": {"width": 120}}] }))
    }

    fn pane_read_visible(&self, _pane_id: &str) -> Result<Value, IpcError> {
        Ok(json!({ "text": "", "truncated": false }))
    }

    fn pane_read_recent(&self, _pane_id: &str, _lines: u32) -> Result<Value, IpcError> {
        Ok(json!({ "text": "", "truncated": false }))
    }

    fn pane_send_text(&self, _pane_id: &str, _text: &str) -> Result<(), IpcError> {
        self.send_input_calls.fetch_add(1, Ordering::SeqCst);
        Ok(())
    }

    fn pane_send_input(
        &self,
        _pane_id: &str,
        _text: Option<&str>,
        _keys: Option<&[String]>,
    ) -> Result<(), IpcError> {
        self.send_input_calls.fetch_add(1, Ordering::SeqCst);
        Ok(())
    }

    fn agent_focus(&self, _target: &str) -> Result<(), IpcError> {
        unimplemented!("not exercised by this test")
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

    fn pane_split(&self, _params: Value) -> Result<String, IpcError> {
        unimplemented!("not exercised by this test")
    }

    fn pane_zoom(&self, _pane_id: &str, _mode: &str) -> Result<(), IpcError> {
        unimplemented!("not exercised by this test")
    }

    fn pane_close(&self, _pane_id: &str) -> Result<(), IpcError> {
        unimplemented!("not exercised by this test")
    }

    fn pane_rename(&self, _pane_id: &str, _label: Option<&str>) -> Result<(), IpcError> {
        unimplemented!("not exercised by this test")
    }

    fn pane_resize(
        &self,
        _pane_id: &str,
        _direction: &str,
        _amount: Option<f64>,
    ) -> Result<(), IpcError> {
        unimplemented!("not exercised by this test")
    }

    fn plugin_action_list(&self) -> Result<Value, IpcError> {
        unimplemented!("not exercised by this test")
    }

    fn plugin_action_invoke(&self, _params: Value) -> Result<Value, IpcError> {
        unimplemented!("not exercised by this test")
    }
}

fn watching_bridge() -> (Bridge<StubHerdr>, Arc<AtomicU32>) {
    let send_input_calls = Arc::new(AtomicU32::new(0));
    let herdr = StubHerdr {
        send_input_calls: send_input_calls.clone(),
    };
    let identity = HostIdentity {
        host_id: "host-1".to_string(),
        host_name: "test-host".to_string(),
    };
    let mut bridge = Bridge::new(herdr, identity, RelayConfig::default());
    bridge
        .watch_pane(WatchPane {
            pane_id: "w1:p1".to_string(),
        })
        .expect("watch_pane succeeds against the stub");
    (bridge, send_input_calls)
}

#[test]
fn send_input_naming_an_unwatched_pane_is_refused() {
    let (mut bridge, send_input_calls) = watching_bridge();
    let result = bridge.send_input(SendInput {
        defer: None,
        line: None,
        pane_id: "w1:p2".to_string(), // not the watched pane
        text: Some("a".to_string()),
        keys: None,
    });
    assert!(
        matches!(&result, Err(WatchError::NotWatching(pane_id)) if pane_id == "w1:p2"),
        "a send_input naming an unwatched pane must be refused with NotWatching, got {result:?}"
    );
    assert_eq!(
        send_input_calls.load(Ordering::SeqCst),
        0,
        "a refused send_input must never reach Herdr"
    );
}

#[test]
fn send_input_with_no_pane_watched_at_all_is_refused() {
    let send_input_calls = Arc::new(AtomicU32::new(0));
    let herdr = StubHerdr {
        send_input_calls: send_input_calls.clone(),
    };
    let identity = HostIdentity {
        host_id: "host-1".to_string(),
        host_name: "test-host".to_string(),
    };
    let mut bridge = Bridge::new(herdr, identity, RelayConfig::default());
    let result = bridge.send_input(SendInput {
        defer: None,
        line: None,
        pane_id: "w1:p1".to_string(),
        text: Some("a".to_string()),
        keys: None,
    });
    assert!(
        matches!(result, Err(WatchError::NotWatching(_))),
        "send_input with nothing watched must be refused, got {result:?}"
    );
    assert_eq!(send_input_calls.load(Ordering::SeqCst), 0);
}

#[test]
fn send_input_to_the_actually_watched_pane_succeeds() {
    let (mut bridge, send_input_calls) = watching_bridge();
    let result = bridge.send_input(SendInput {
        defer: None,
        line: None,
        pane_id: "w1:p1".to_string(),
        text: Some("a".to_string()),
        keys: None,
    });
    assert!(result.is_ok(), "the watched pane's own id must be accepted");
    assert_eq!(send_input_calls.load(Ordering::SeqCst), 1);
}
