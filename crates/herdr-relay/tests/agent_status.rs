//! `docs/11-relay-protocol.md` §4.13: `agent_status` fires only for `blocked`/
//! `done` (R-11-057), never for `idle`/`working`/`unknown`, and applies a
//! 30-second settle window per agent so a flapping status notifies at most
//! once (R-11-059). Routed to `WP-6` via §5.3 on `WP-19-a`'s request.

use herdr_relay::config::RelayConfig;
use herdr_relay::ipc::IpcError;
use herdr_relay::watch::{Bridge, HerdrCalls, HostIdentity};
use herdr_relay_proto::messages::{AgentStatusKind, Message};
use serde_json::{Value, json};

struct StubHerdr;

impl HerdrCalls for StubHerdr {
    fn session_snapshot(&self) -> Result<Value, IpcError> {
        // The flat `session.snapshot` shape (`docs/10-herdr-integration.md`
        // §3.4): the agent-status arm reads it for the pane's tab routing,
        // because the real push carries no pane object.
        let panes: Vec<Value> = ["w1:p1", "w1:p2", "w1:p3", "w1:p4", "w1:p5", "w1:p6"]
            .iter()
            .map(|id| {
                json!({
                    "pane_id": id,
                    "workspace_id": "w1",
                    "tab_id": "t1",
                    "terminal_id": "term-1",
                    "label": "",
                    "cwd": "/",
                    "focused": true,
                    "agent": "claude",
                    "agent_status": "working",
                    "revision": 1,
                    "scroll": {"offset_from_bottom": 0, "max_offset_from_bottom": 0, "viewport_rows": 50}
                })
            })
            .collect();
        Ok(json!({
            "workspaces": [{"workspace_id": "w1", "label": "ws", "focused": true}],
            "tabs": [{"tab_id": "t1", "workspace_id": "w1", "label": "My Tab", "focused": true}],
            "panes": panes,
            "agents": []
        }))
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

    fn pane_send_text(&self, _pane_id: &str, _text: &str) -> Result<(), IpcError> {
        unimplemented!("not exercised by this test")
    }

    fn pane_send_input(
        &self,
        _pane_id: &str,
        _text: Option<&str>,
        _keys: Option<&[String]>,
    ) -> Result<(), IpcError> {
        unimplemented!("not exercised by this test")
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

fn bridge() -> Bridge<StubHerdr> {
    let identity = HostIdentity {
        host_id: "host-1".to_string(),
        host_name: "test-host".to_string(),
    };
    Bridge::new(StubHerdr, identity, RelayConfig::default())
}

fn agent_status_changed_line(pane_id: &str, status: &str) -> String {
    // The real push shape (`herdr api schema`, protocol 21, EventData variant
    // `pane_agent_status_changed`): flat fields, no `pane`/`tab` object.
    json!({
        "event": "pane_agent_status_changed",
        "data": {
            "type": "pane_agent_status_changed",
            "pane_id": pane_id,
            "workspace_id": "w1",
            "agent_status": status,
            "agent": "claude",
            "display_agent": "Claude",
            "title": null,
            "state_labels": {}
        }
    })
    .to_string()
}

fn only_agent_status(messages: Vec<Message>) -> Option<Message> {
    let mut agent_status = messages
        .into_iter()
        .filter(|m| matches!(m, Message::AgentStatus(_)));
    let first = agent_status.next();
    assert!(
        agent_status.next().is_none(),
        "expected at most one agent_status message"
    );
    first
}

#[test]
fn blocked_sends_one_agent_status_with_the_expected_fields() {
    let mut bridge = bridge();
    let (messages, _) = bridge
        .handle_subscription_line(&agent_status_changed_line("w1:p1", "blocked"))
        .expect("a well-formed push parses");

    let Some(Message::AgentStatus(status)) = only_agent_status(messages) else {
        panic!("expected an agent_status message for a blocked agent");
    };
    assert_eq!(status.host_id, "host-1");
    assert_eq!(status.pane_id, "w1:p1");
    assert_eq!(status.workspace_id, "w1");
    assert_eq!(status.tab_id, "t1");
    assert_eq!(status.tab_title, "My Tab");
    assert_eq!(status.agent_kind, "claude");
    assert_eq!(status.status, AgentStatusKind::Blocked);
    assert!(!status.at.is_empty());
}

#[test]
fn done_sends_one_agent_status() {
    let mut bridge = bridge();
    let (messages, _) = bridge
        .handle_subscription_line(&agent_status_changed_line("w1:p2", "done"))
        .expect("a well-formed push parses");

    let Some(Message::AgentStatus(status)) = only_agent_status(messages) else {
        panic!("expected an agent_status message for a done agent");
    };
    assert_eq!(status.status, AgentStatusKind::Done);
}

#[test]
fn idle_working_and_unknown_never_send_agent_status() {
    let mut bridge = bridge();
    for status in ["idle", "working", "unknown"] {
        let (messages, _) = bridge
            .handle_subscription_line(&agent_status_changed_line("w1:p3", status))
            .expect("a well-formed push parses");
        assert!(
            only_agent_status(messages).is_none(),
            "status {status} MUST NOT send agent_status (R-11-057)"
        );
    }
}

#[test]
fn a_second_blocked_event_inside_the_settle_window_sends_nothing() {
    let mut bridge = bridge();
    let (first, _) = bridge
        .handle_subscription_line(&agent_status_changed_line("w1:p4", "blocked"))
        .expect("a well-formed push parses");
    assert!(only_agent_status(first).is_some(), "the first send fires");

    // Flap: blocked -> working -> blocked again, all well inside 30 s.
    let (second, _) = bridge
        .handle_subscription_line(&agent_status_changed_line("w1:p4", "working"))
        .expect("a well-formed push parses");
    assert!(only_agent_status(second).is_none(), "working never sends");

    let (third, _) = bridge
        .handle_subscription_line(&agent_status_changed_line("w1:p4", "blocked"))
        .expect("a well-formed push parses");
    assert!(
        only_agent_status(third).is_none(),
        "R-11-059: the second blocked inside the settle window sends nothing"
    );
}

#[test]
fn two_different_panes_each_get_their_own_settle_window() {
    let mut bridge = bridge();
    let (a, _) = bridge
        .handle_subscription_line(&agent_status_changed_line("w1:p5", "blocked"))
        .expect("a well-formed push parses");
    assert!(only_agent_status(a).is_some());

    let (b, _) = bridge
        .handle_subscription_line(&agent_status_changed_line("w1:p6", "blocked"))
        .expect("a well-formed push parses");
    assert!(
        only_agent_status(b).is_some(),
        "a different pane's agent has its own settle baseline"
    );
}

#[test]
fn a_status_for_a_pane_missing_from_the_snapshot_sends_nothing() {
    let mut bridge = bridge();
    let (messages, _) = bridge
        .handle_subscription_line(&agent_status_changed_line("w1:pGone", "blocked"))
        .expect("a well-formed push parses");
    assert!(
        only_agent_status(messages).is_none(),
        "a pane the fresh snapshot no longer holds is gone: no notification"
    );
}
