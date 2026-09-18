//! R-10-070, R-02-026: an agent pane can repaint without its `revision` ever
//! moving, so a watched pane is also read on a poll timer. R-10-071, R-02-029: a
//! typed character moves no `revision` at all, so a forwarded `send_input` also
//! arms its own reads at 60 ms, 130 ms and 250 ms after the write. These tests
//! drive the real `Bridge::run_until` loop against a stub Herdr whose `revision`
//! is frozen, with no `pane.updated` events at all — the exact live defect
//! measured in `docs/02-herdr-probe-results.md` R-02-026 and R-02-029.

use std::sync::{Arc, Mutex, mpsc};
use std::time::{Duration, Instant};

use herdr_relay::config::RelayConfig;
use herdr_relay::ipc::IpcError;
use herdr_relay::watch::{Bridge, HerdrCalls, HostIdentity, LatestSlot};
use herdr_relay_proto::messages::{PaneFrame, SendInput, WatchPane};
use serde_json::{Value, json};

/// A stub Herdr that reports pane `w1:p1` with a permanently frozen `revision`
/// of 7 and never emits an event. Its visible text is mutable, so the test
/// decides when the pane's content changes. Every `pane.read` instant is logged.
struct StubHerdr {
    text: Arc<Mutex<String>>,
    read_at: Arc<Mutex<Vec<Instant>>>,
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
                "label": "omp",
                "title": "omp",
                "cwd": "/home",
                "focused": true,
                "agent": "omp",
                "agent_status": "working",
                "revision": 7,
                "scroll": {"offset_from_bottom": 0, "max_offset_from_bottom": 0, "viewport_rows": 50},
            }],
            "agents": [],
        }))
    }

    fn pane_layout(&self, _pane_id: &str) -> Result<Value, IpcError> {
        Ok(json!({ "panes": [{"pane_id": "w1:p1", "rect": {"width": 120}}] }))
    }

    fn pane_read_visible(&self, _pane_id: &str) -> Result<Value, IpcError> {
        self.read_at.lock().expect("read log").push(Instant::now());
        let text = self.text.lock().expect("text").clone();
        Ok(json!({ "text": text, "truncated": false }))
    }

    fn pane_read_recent(&self, _pane_id: &str, _lines: u32) -> Result<Value, IpcError> {
        self.read_at.lock().expect("read log").push(Instant::now());
        let text = self.text.lock().expect("text").clone();
        Ok(json!({ "text": text, "truncated": false }))
    }

    fn pane_send_text(&self, _pane_id: &str, _text: &str) -> Result<(), IpcError> {
        Ok(())
    }

    fn pane_send_input(
        &self,
        _pane_id: &str,
        _text: Option<&str>,
        _keys: Option<&[String]>,
    ) -> Result<(), IpcError> {
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

struct Fixture {
    bridge: Bridge<StubHerdr>,
    text: Arc<Mutex<String>>,
    read_at: Arc<Mutex<Vec<Instant>>>,
}

fn test_bridge(initial_text: &str) -> Fixture {
    test_bridge_with(initial_text, RelayConfig::default())
}

/// The R-10-071 tests below prove the input path in isolation, so they pin the
/// R-10-070 poll to "effectively never", as `tests/debounce.rs` pins it for the
/// event path. Every read they count is then an input-triggered read.
fn input_only_config() -> RelayConfig {
    RelayConfig {
        poll_ms: 60_000,
        ..RelayConfig::default()
    }
}

fn test_bridge_with(initial_text: &str, config: RelayConfig) -> Fixture {
    let text = Arc::new(Mutex::new(initial_text.to_string()));
    let read_at = Arc::new(Mutex::new(Vec::new()));
    let herdr = StubHerdr {
        text: text.clone(),
        read_at: read_at.clone(),
    };
    let identity = HostIdentity {
        host_id: "host-1".to_string(),
        host_name: "test-host".to_string(),
    };
    Fixture {
        bridge: Bridge::new(herdr, identity, config),
        text,
        read_at,
    }
}

#[test]
fn text_change_without_revision_move_yields_a_frame_within_two_poll_periods() {
    let Fixture {
        mut bridge, text, ..
    } = test_bridge("frame-v1");
    let (_ack, first_frame) = bridge
        .watch_pane(WatchPane {
            pane_id: "w1:p1".to_string(),
        })
        .expect("watch_pane succeeds against the stub");
    assert_eq!(first_frame.text, "frame-v1");
    assert_eq!(first_frame.revision, 7);

    // The pane repaints, but its revision stays at 7 and no event ever arrives.
    *text.lock().expect("text") = "frame-v2".to_string();

    // No subscription lines at all: the channel stays open but silent, so only
    // the poll timer can produce a frame.
    let (tx, rx) = mpsc::channel::<std::io::Result<String>>();
    let frame_slot: LatestSlot<PaneFrame> = LatestSlot::new();
    // Two full poll periods (2 x 250 ms) plus margin.
    let deadline = Instant::now() + Duration::from_millis(700);
    bridge
        .run_until(&rx, deadline, &frame_slot, |_| {}, || {})
        .expect("the run loop completes at the deadline with no error");
    drop(tx);

    let frame = frame_slot
        .try_take()
        .expect("a changed pane with a frozen revision still yields a frame (R-10-070)");
    assert_eq!(frame.text, "frame-v2");
    assert_eq!(
        frame.revision, 7,
        "the frame keeps the Host revision, which never moved (R-10-070)"
    );
}

#[test]
fn unchanged_text_yields_poll_reads_but_no_frame() {
    let Fixture {
        mut bridge,
        read_at,
        ..
    } = test_bridge("hello");
    bridge
        .watch_pane(WatchPane {
            pane_id: "w1:p1".to_string(),
        })
        .expect("watch_pane succeeds against the stub");
    read_at.lock().expect("read log").clear(); // count only the polled reads

    let (tx, rx) = mpsc::channel::<std::io::Result<String>>();
    let frame_slot: LatestSlot<PaneFrame> = LatestSlot::new();
    let deadline = Instant::now() + Duration::from_millis(600);
    bridge
        .run_until(&rx, deadline, &frame_slot, |_| {}, || {})
        .expect("the run loop completes at the deadline with no error");
    drop(tx);

    let polls = read_at.lock().expect("read log").len();
    assert!(
        polls >= 2,
        "two poll periods elapsed, so at least two poll reads happened, got {polls}"
    );
    assert!(
        frame_slot.try_take().is_none(),
        "an unchanged pane sends no frame: the poll read costs no wire bytes (R-10-070)"
    );
}

/// R-10-071: a forwarded `send_input` arms reads at 60 ms, 130 ms and 250 ms
/// after the write, so a keystroke echo reaches the Device even though it moved
/// no `revision` and produced no event (R-02-029). The poll is pinned far away,
/// so every read counted here is input-triggered.
#[test]
fn send_input_arms_reads_that_carry_the_echo_of_a_keystroke() {
    let Fixture {
        mut bridge,
        text,
        read_at,
    } = test_bridge_with("prompt> ", input_only_config());
    bridge
        .watch_pane(WatchPane {
            pane_id: "w1:p1".to_string(),
        })
        .expect("watch_pane succeeds against the stub");
    read_at.lock().expect("read log").clear(); // count only the input-triggered reads

    let written_at = Instant::now();
    bridge
        .send_input(SendInput {
            defer: None,
            line: None,
            pane_id: "w1:p1".to_string(),
            text: Some("a".to_string()),
            keys: None,
        })
        .expect("the watched pane accepts input");
    // The shell echoes the character: text changes, revision stays 7, no event.
    *text.lock().expect("text") = "prompt> a".to_string();

    let (tx, rx) = mpsc::channel::<std::io::Result<String>>();
    let frame_slot: LatestSlot<PaneFrame> = LatestSlot::new();
    // The last R-10-071 read arms at 250 ms; the margin absorbs a slow CI runner and the
    // 60 s poll pin keeps the count exact.
    let deadline = Instant::now() + Duration::from_millis(1500);
    bridge
        .run_until(&rx, deadline, &frame_slot, |_| {}, || {})
        .expect("the run loop completes at the deadline with no error");
    drop(tx);

    let reads = read_at.lock().expect("read log");
    // One read serves every deadline that is due when it fires, so a slow read
    // can merge the 60 ms and 130 ms offsets: two or three reads, never more, and
    // the last one lands at or after the 250 ms offset.
    assert!(
        (2..=3).contains(&reads.len()),
        "one write arms the three R-10-071 reads, merged at most once, got {}",
        reads.len()
    );
    assert!(
        *reads.last().expect("a read") >= written_at + Duration::from_millis(250),
        "the last input read serves the 250 ms offset"
    );
    drop(reads);
    let frame = frame_slot
        .try_take()
        .expect("the echoed character reaches the Device (R-10-071)");
    assert_eq!(frame.text, "prompt> a");
    assert_eq!(
        frame.revision, 7,
        "the frame keeps the Host revision, which a keystroke never moves (R-02-029)"
    );
}

/// R-10-071 with R-10-070's hash compare: input that changes nothing on screen
/// still reads, but sends no frame, so a password prompt or an ignored key costs
/// no wire bytes.
#[test]
fn input_with_unchanged_text_reads_but_sends_no_frame() {
    let Fixture {
        mut bridge,
        read_at,
        ..
    } = test_bridge_with("prompt> ", input_only_config());
    bridge
        .watch_pane(WatchPane {
            pane_id: "w1:p1".to_string(),
        })
        .expect("watch_pane succeeds against the stub");
    read_at.lock().expect("read log").clear();

    bridge
        .send_input(SendInput {
            defer: None,
            line: None,
            pane_id: "w1:p1".to_string(),
            keys: Some(vec!["ctrl+c".to_string()]),
            text: None,
        })
        .expect("the watched pane accepts input");

    let (tx, rx) = mpsc::channel::<std::io::Result<String>>();
    let frame_slot: LatestSlot<PaneFrame> = LatestSlot::new();
    let deadline = Instant::now() + Duration::from_millis(1500);
    bridge
        .run_until(&rx, deadline, &frame_slot, |_| {}, || {})
        .expect("the run loop completes at the deadline with no error");
    drop(tx);

    let reads = read_at.lock().expect("read log").len();
    assert!(
        (2..=3).contains(&reads),
        "input arms reads, merged at most once on a slow read, got {reads}"
    );
    assert!(
        frame_slot.try_take().is_none(),
        "an unchanged pane sends no frame after input either (R-10-070 hash compare)"
    );
}

/// R-01-006, R-01-007: a `send_input` naming a pane this Device is not watching
/// is refused, so it can never arm an R-10-071 read either. A rejected write
/// costs no Herdr reads at all.
#[test]
fn refused_input_arms_no_reads() {
    let Fixture {
        mut bridge,
        read_at,
        ..
    } = test_bridge_with("prompt> ", input_only_config());
    bridge
        .watch_pane(WatchPane {
            pane_id: "w1:p1".to_string(),
        })
        .expect("watch_pane succeeds against the stub");
    read_at.lock().expect("read log").clear();

    let refused = bridge.send_input(SendInput {
        defer: None,
        line: None,
        pane_id: "w1:p2".to_string(), // not the watched pane
        text: Some("a".to_string()),
        keys: None,
    });
    assert!(refused.is_err(), "an unwatched pane_id must be refused");

    let (tx, rx) = mpsc::channel::<std::io::Result<String>>();
    let frame_slot: LatestSlot<PaneFrame> = LatestSlot::new();
    let deadline = Instant::now() + Duration::from_millis(1500);
    bridge
        .run_until(&rx, deadline, &frame_slot, |_| {}, || {})
        .expect("the run loop completes at the deadline with no error");
    drop(tx);

    assert_eq!(
        read_at.lock().expect("read log").len(),
        0,
        "a refused send_input must arm no read (R-01-006)"
    );
    assert!(frame_slot.try_take().is_none());
}
