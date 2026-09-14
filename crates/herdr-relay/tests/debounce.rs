//! `docs/90-implementation-plan.md` Phase 6: "asserting 40 events in one second
//! produce at most 16 reads" (R-10-030, cap amended from 8 to 16 on 2026-09-11 to
//! leave room for the R-10-071 input-triggered reads). Drives the real
//! `Bridge::run_until` loop — not the internal scheduler directly — so this proves
//! the production entry point, not just the pure decision struct
//! `crates/herdr-relay/src/watch.rs`'s own unit tests already cover. The R-10-070
//! poll timer runs alongside the event burst, so this also proves the cap is
//! shared by both triggers: at most 16 reads in any one-second window, however the
//! reads were triggered.

use std::sync::{Arc, Mutex, mpsc};
use std::time::{Duration, Instant};

use herdr_relay::config::RelayConfig;
use herdr_relay::ipc::IpcError;
use herdr_relay::watch::{Bridge, HerdrCalls, HostIdentity, LatestSlot};
use herdr_relay_proto::messages::{PaneFrame, WatchPane};
use serde_json::{Value, json};

struct StubHerdr {
    read_at: Arc<Mutex<Vec<Instant>>>,
    read_gate: Option<(mpsc::Sender<()>, mpsc::Receiver<()>)>,
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
        let count = {
            let mut reads = self.read_at.lock().expect("read log");
            reads.push(Instant::now());
            reads.len()
        };
        if count == 2
            && let Some((started, release)) = &self.read_gate
        {
            started.send(()).expect("read started");
            release
                .recv_timeout(Duration::from_secs(2))
                .expect("release blocked read");
        }
        Ok(json!({ "text": "hello", "truncated": false }))
    }

    fn pane_read_recent(&self, _pane_id: &str, _lines: u32) -> Result<Value, IpcError> {
        self.read_at.lock().expect("read log").push(Instant::now());
        Ok(json!({ "text": "hello", "truncated": false }))
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

fn pane_updated_line(revision: u64) -> String {
    json!({
        "event": "pane.updated",
        "data": {
            "pane": {
                "pane_id": "w1:p1",
                "revision": revision,
                "scroll": {"viewport_rows": 50},
            }
        }
    })
    .to_string()
}

/// The three exact-read-count tests below prove the R-10-029 event path in
/// isolation, so they pin the R-10-070 poll to "effectively never", as
/// `tests/revision_gate.rs` does. The poll path is `tests/poll_timer.rs`'s job;
/// the forty-event test above keeps the default so the shared cap is real.
fn event_only_config() -> RelayConfig {
    RelayConfig {
        poll_ms: 60_000,
        ..RelayConfig::default()
    }
}

#[test]
fn forty_events_in_one_second_produce_at_most_sixteen_reads() {
    let read_at = Arc::new(Mutex::new(Vec::new()));
    let herdr = StubHerdr {
        read_at: read_at.clone(),
        read_gate: None,
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
    read_at.lock().expect("read log").clear(); // count only the 40-event burst below

    let (tx, rx) = mpsc::channel::<std::io::Result<String>>();
    // 40 events, every one a genuinely new revision, delivered over ~1 real second
    // — the same shape `docs/10-herdr-integration.md` §5.1 measured live (99
    // events/10s from one background pane).
    std::thread::spawn(move || {
        for revision in 1..=40u64 {
            let _ = tx.send(Ok(pane_updated_line(revision)));
            std::thread::sleep(Duration::from_millis(25));
        }
        // tx drops here once every event is sent; the run loop below has its own
        // deadline and does not depend on the channel staying open past that.
    });

    let frame_slot: LatestSlot<PaneFrame> = LatestSlot::new();
    let deadline = Instant::now() + Duration::from_millis(1300);
    // A `SubscriptionClosed` error once the feeder thread's `tx` drops, after the
    // deadline has already been reached, is an acceptable end to this test run;
    // only a `Timeout`-driven early exit would be a bug.
    let _ = bridge.run_until(&rx, deadline, &frame_slot, |_| {}, || {});

    // R-10-030 is a per-second ceiling shared by the revision trigger, the
    // R-10-070 poll trigger and the R-10-071 input trigger, so assert it as a
    // sliding window over the recorded instants rather than as a grand total: the
    // burst runs ~1 s and the loop runs 1.3 s, in which up to 16 + poll reads are
    // legal overall.
    let reads = read_at.lock().expect("read log");
    assert!(
        !reads.is_empty(),
        "expected at least one read to have happened"
    );
    let worst_window = reads
        .iter()
        .enumerate()
        .map(|(i, start)| {
            reads[i..]
                .iter()
                .take_while(|t| **t - *start < Duration::from_secs(1))
                .count()
        })
        .max()
        .unwrap_or(0);
    assert!(
        worst_window <= 16,
        "expected at most 16 reads in any one-second window, got {worst_window} (instants: {:?})",
        reads
            .iter()
            .map(|t| t.duration_since(reads[0]).as_millis())
            .collect::<Vec<_>>()
    );
}

#[test]
fn single_event_reads_before_window_close_without_trailing_read() {
    let read_at = Arc::new(Mutex::new(Vec::new()));
    let herdr = StubHerdr {
        read_at: read_at.clone(),
        read_gate: None,
    };
    let mut bridge = Bridge::new(
        herdr,
        HostIdentity {
            host_id: "host-1".to_string(),
            host_name: "test-host".to_string(),
        },
        event_only_config(),
    );
    bridge
        .watch_pane(WatchPane {
            pane_id: "w1:p1".to_string(),
        })
        .expect("watch pane");
    let (tx, rx) = mpsc::channel();
    let frames = LatestSlot::new();
    let start = Instant::now();
    tx.send(Ok(pane_updated_line(1))).expect("first event");
    bridge
        .run_until(
            &rx,
            start + Duration::from_millis(60),
            &frames,
            |_| {},
            || {},
        )
        .expect("leading interval");
    assert_eq!(frames.try_take().expect("leading frame").revision, 1);
    assert_eq!(read_at.lock().expect("read log").len(), 2);
    bridge
        .run_until(
            &rx,
            start + Duration::from_millis(180),
            &frames,
            |_| {},
            || {},
        )
        .expect("window close");
    assert!(
        frames.try_take().is_none(),
        "no newer revision needs a trailing frame"
    );
    assert_eq!(read_at.lock().expect("read log").len(), 2);
}

#[test]
fn events_forty_ms_apart_read_leading_and_keep_last_at_window_close() {
    let read_at = Arc::new(Mutex::new(Vec::new()));
    let herdr = StubHerdr {
        read_at: read_at.clone(),
        read_gate: None,
    };
    let mut bridge = Bridge::new(
        herdr,
        HostIdentity {
            host_id: "host-1".to_string(),
            host_name: "test-host".to_string(),
        },
        event_only_config(),
    );
    bridge
        .watch_pane(WatchPane {
            pane_id: "w1:p1".to_string(),
        })
        .expect("watch pane");
    let (tx, rx) = mpsc::channel();
    let frames = LatestSlot::new();
    let start = Instant::now();
    tx.send(Ok(pane_updated_line(1))).expect("first event");
    bridge
        .run_until(
            &rx,
            start + Duration::from_millis(40),
            &frames,
            |_| {},
            || {},
        )
        .expect("first interval");
    assert_eq!(
        frames
            .try_take()
            .expect("frame before second event")
            .revision,
        1
    );
    tx.send(Ok(pane_updated_line(2))).expect("second event");
    bridge
        .run_until(
            &rx,
            start + Duration::from_millis(80),
            &frames,
            |_| {},
            || {},
        )
        .expect("second interval");
    assert!(frames.try_take().is_none());
    tx.send(Ok(pane_updated_line(3))).expect("third event");
    bridge
        .run_until(
            &rx,
            start + Duration::from_millis(150),
            &frames,
            |_| {},
            || {},
        )
        .expect("fixed window close");
    assert_eq!(
        frames.try_take().expect("newest trailing frame").revision,
        3
    );
    assert_eq!(read_at.lock().expect("read log").len(), 3);
    bridge
        .run_until(
            &rx,
            start + Duration::from_millis(220),
            &frames,
            |_| {},
            || {},
        )
        .expect("no second trailing read");
    assert!(frames.try_take().is_none());
    assert_eq!(read_at.lock().expect("read log").len(), 3);
}

#[test]
fn event_during_read_waits_for_completion_then_reads_trailing() {
    let (started_tx, started_rx) = mpsc::channel();
    let (release_tx, release_rx) = mpsc::channel();
    let read_at = Arc::new(Mutex::new(Vec::new()));
    let herdr = StubHerdr {
        read_at: read_at.clone(),
        read_gate: Some((started_tx, release_rx)),
    };
    let mut bridge = Bridge::new(
        herdr,
        HostIdentity {
            host_id: "host-1".to_string(),
            host_name: "test-host".to_string(),
        },
        event_only_config(),
    );
    bridge
        .watch_pane(WatchPane {
            pane_id: "w1:p1".to_string(),
        })
        .expect("watch pane");
    let (tx, rx) = mpsc::channel();
    let frames = LatestSlot::new();
    let start = Instant::now();
    tx.send(Ok(pane_updated_line(1))).expect("first event");
    let reads = read_at.clone();
    let sender = std::thread::spawn(move || {
        started_rx
            .recv_timeout(Duration::from_secs(2))
            .expect("leading read starts");
        tx.send(Ok(pane_updated_line(2)))
            .expect("event during read");
        std::thread::sleep(Duration::from_millis(140));
        assert_eq!(
            reads.lock().expect("read log").len(),
            2,
            "no concurrent read"
        );
        let released_at = Instant::now();
        release_tx.send(()).expect("finish leading read");
        // Keep the subscription open until the loop reaches its deadline.
        std::thread::sleep(Duration::from_millis(150));
        released_at
    });
    bridge
        .run_until(
            &rx,
            start + Duration::from_millis(220),
            &frames,
            |_| {},
            || {},
        )
        .expect("read and trailing interval");
    let released_at = sender.join().expect("event sender");
    let reads = read_at.lock().expect("read log");
    assert_eq!(reads.len(), 3, "initial, leading, and one trailing read");
    assert!(
        reads[2] >= released_at,
        "trailing read starts after release"
    );
    assert_eq!(frames.try_take().expect("trailing frame").revision, 2);
}
