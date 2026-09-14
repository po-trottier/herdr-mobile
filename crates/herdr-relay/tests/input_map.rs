//! `docs/90-implementation-plan.md` Phase 7: "one case per row of the R-10-036
//! table and one case per rejected name in `docs/10-herdr-integration.md` §6.3"
//! (R-10-036, R-10-044). Drives `Bridge::send_input` end to end against a stub
//! Herdr, matching the `herdr-scheduled` shim-test pattern R-40-029 sets: no test
//! framework, no real Herdr server.

use std::sync::{Arc, Mutex};

use herdr_relay::config::RelayConfig;
use herdr_relay::ipc::IpcError;
use herdr_relay::watch::{Bridge, HerdrCalls, HostIdentity};
use herdr_relay_proto::messages::{Message, SendInput, WatchPane};
use serde_json::{Value, json};

/// One captured `pane.send_input` call: the `text` and `keys` the bridge actually
/// forwarded to Herdr.
type SentCall = (Option<String>, Option<Vec<String>>);

struct StubHerdr {
    sent: Arc<Mutex<Vec<SentCall>>>,
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

    fn pane_send_input(
        &self,
        _pane_id: &str,
        text: Option<&str>,
        keys: Option<&[String]>,
    ) -> Result<(), IpcError> {
        self.sent
            .lock()
            .expect("stub mutex is never poisoned")
            .push((text.map(str::to_owned), keys.map(<[String]>::to_vec)));
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

/// A `Bridge` already watching `w1:p1`, with a fresh call-capture slot.
fn watching_bridge() -> (Bridge<StubHerdr>, Arc<Mutex<Vec<SentCall>>>) {
    let sent = Arc::new(Mutex::new(Vec::new()));
    let herdr = StubHerdr { sent: sent.clone() };
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
    (bridge, sent)
}

fn send(
    bridge: &mut Bridge<StubHerdr>,
    text: Option<&str>,
    keys: Option<&[&str]>,
) -> Result<Message, herdr_relay::watch::WatchError> {
    bridge.send_input(SendInput {
        pane_id: "w1:p1".to_string(),
        text: text.map(str::to_owned),
        keys: keys.map(|k| k.iter().map(|s| (*s).to_string()).collect()),
    })
}

/// R-10-036: the six unnamed keys, sent by a compliant Device as their raw CSI
/// sequence in `text` (R-11-054 step 2), MUST reach `pane.send_input` unchanged.
#[test]
fn every_row_of_the_r_10_036_table_reaches_herdr_as_the_exact_raw_sequence() {
    let rows: &[(&str, &str)] = &[
        ("Home", "\u{1b}[H"),
        ("End", "\u{1b}[F"),
        ("PageUp", "\u{1b}[5~"),
        ("PageDown", "\u{1b}[6~"),
        ("Delete", "\u{1b}[3~"),
        ("Insert", "\u{1b}[2~"),
    ];
    for (name, sequence) in rows {
        let (mut bridge, sent) = watching_bridge();
        let result = send(&mut bridge, Some(sequence), None);
        assert!(result.is_ok(), "{name} ({sequence:?}) should be accepted");
        let calls = sent.lock().expect("stub mutex is never poisoned");
        assert_eq!(calls.len(), 1, "{name} sends exactly one pane.send_input");
        assert_eq!(
            calls[0].0.as_deref(),
            Some(*sequence),
            "{name} must reach Herdr as the unmodified raw sequence"
        );
    }
}

/// Printable characters and named keys (R-10-036 §6.2) are accepted the ordinary
/// way: `text` for a single character, `keys` for a name.
#[test]
fn printable_text_and_named_keys_are_accepted() {
    let (mut bridge, sent) = watching_bridge();
    assert!(send(&mut bridge, Some("a"), None).is_ok());
    assert!(send(&mut bridge, None, Some(&["ctrl+c"])).is_ok());
    assert!(send(&mut bridge, None, Some(&["Enter"])).is_ok());
    let calls = sent.lock().expect("stub mutex is never poisoned");
    assert_eq!(calls.len(), 3);
    assert_eq!(calls[0].0.as_deref(), Some("a"));
    assert_eq!(calls[1].1.as_deref(), Some(&["ctrl+c".to_string()][..]));
    assert_eq!(calls[2].1.as_deref(), Some(&["Enter".to_string()][..]));
}

/// `docs/10-herdr-integration.md` §6.3: every rejected name, sent as a `keys`
/// entry, MUST be refused before it ever reaches Herdr (R-11-055).
#[test]
fn every_row_of_section_6_3_is_rejected() {
    let rejected = [
        "Home", "End", "PageUp", "PageDown", "Delete", "Insert", // no logical name (§6.3)
        "Del", "Ins", "Newline", "BackTab", "ShiftTab", // not aliases
        "M-x", "A-x", "S-Tab",  // emacs style
        "ctrl-c", // hyphen separator
        "^C",     // caret notation
        "win+a",  // `win` is not a modifier
        "super+a", "cmd+a",
        "meta+a", // R-10-039: accepted by Herdr, forbidden from the Device
    ];
    for name in rejected {
        let (mut bridge, sent) = watching_bridge();
        let result = send(&mut bridge, None, Some(&[name]));
        assert!(result.is_err(), "{name} must be rejected");
        assert!(
            sent.lock()
                .expect("stub mutex is never poisoned")
                .is_empty(),
            "{name} must never reach Herdr"
        );
    }
}

/// R-11-055: a `send_input` with neither `text` nor `keys` is rejected before it
/// reaches Herdr.
#[test]
fn an_empty_send_input_is_rejected() {
    let (mut bridge, sent) = watching_bridge();
    let result = send(&mut bridge, None, None);
    assert!(result.is_err(), "empty send_input must be rejected");
    assert!(
        sent.lock()
            .expect("stub mutex is never poisoned")
            .is_empty()
    );
}
