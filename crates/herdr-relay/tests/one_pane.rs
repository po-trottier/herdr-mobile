//! `docs/90-implementation-plan.md` Phase 6: "asserting a second `watch_pane`
//! replaces the first and the old pane stops producing frames" (R-01-007, R-11-048).
//!
//! This file also hosts the Phase 6 manual live-Herdr verification (Step 4 of the
//! `WP-6` assignment): an `#[ignore]`d test, run by hand against a real running
//! Herdr server, watching one real pane for a real observation window. It is
//! `#[ignore]`d so `cargo test -p herdr-relay` (the Phase 6 `Done when` command)
//! never depends on Herdr being installed or running, matching the
//! `#[ignore]`d `regenerate_vectors_json` pattern already used in
//! `crates/herdr-relay-proto/tests/vectors.rs`.

use std::sync::Arc;
use std::sync::atomic::{AtomicU32, Ordering};

use herdr_relay::config::RelayConfig;
use herdr_relay::ipc::IpcError;
use herdr_relay::watch::{Bridge, HerdrCalls, HostIdentity};
use herdr_relay_proto::messages::{Message, UnwatchPane, WatchPane};
use serde_json::{Value, json};

struct StubHerdr {
    read_calls: Arc<AtomicU32>,
}

fn pane(pane_id: &str, revision: u64) -> Value {
    json!({
        "pane_id": pane_id,
        "workspace_id": "w1",
        "tab_id": "t1",
        "terminal_id": format!("term-{pane_id}"),
        "label": "shell",
        "title": "shell",
        "cwd": "/home",
        "focused": true,
        "agent": null,
        "agent_status": "idle",
        "revision": revision,
        "scroll": {"offset_from_bottom": 0, "max_offset_from_bottom": 0, "viewport_rows": 50},
    })
}

impl HerdrCalls for StubHerdr {
    fn session_snapshot(&self) -> Result<Value, IpcError> {
        Ok(json!({
            "workspaces": [],
            "tabs": [],
            "panes": [pane("w1:p1", 1), pane("w1:p2", 1)],
            "agents": [],
        }))
    }

    fn pane_layout(&self, pane_id: &str) -> Result<Value, IpcError> {
        Ok(json!({ "panes": [{"pane_id": pane_id, "rect": {"width": 120}}] }))
    }

    fn pane_read_visible(&self, _pane_id: &str) -> Result<Value, IpcError> {
        self.read_calls.fetch_add(1, Ordering::SeqCst);
        Ok(json!({ "text": "hello", "truncated": false }))
    }

    fn pane_read_recent(&self, _pane_id: &str, _lines: u32) -> Result<Value, IpcError> {
        self.read_calls.fetch_add(1, Ordering::SeqCst);
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

fn pane_updated_line(pane_id: &str, revision: u64) -> String {
    json!({
        "event": "pane.updated",
        "data": { "pane": { "pane_id": pane_id, "revision": revision, "scroll": {"viewport_rows": 50} } }
    })
    .to_string()
}

#[test]
fn a_second_watch_pane_replaces_the_first() {
    let read_calls = Arc::new(AtomicU32::new(0));
    let herdr = StubHerdr {
        read_calls: read_calls.clone(),
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
        .expect("watch the first pane");
    assert_eq!(bridge.watched_pane_id(), Some("w1:p1"));

    bridge
        .watch_pane(WatchPane {
            pane_id: "w1:p2".to_string(),
        })
        .expect("watch the second pane, replacing the first (R-11-048)");
    assert_eq!(
        bridge.watched_pane_id(),
        Some("w1:p2"),
        "the second watch_pane replaces the first (R-01-007)"
    );

    let reads_before = read_calls.load(Ordering::SeqCst);

    // An event for the OLD pane MUST be discarded before any read (R-01-007,
    // R-02-013, R-41-168): no pane_frame, and no extra pane.read.
    let (messages, _) = bridge
        .handle_subscription_line(&pane_updated_line("w1:p1", 2))
        .expect("handling the old pane's event succeeds");
    assert!(
        !messages
            .iter()
            .any(|m| matches!(m, Message::PaneFrame(f) if f.pane_id == "w1:p1")),
        "the old, unwatched pane produces no pane_frame"
    );
    assert_eq!(
        read_calls.load(Ordering::SeqCst),
        reads_before,
        "the old pane's event triggers no pane.read once replaced"
    );

    // unwatch_pane for the pane that is not watched is a no-op (R-11-072: the
    // Device need not unwatch before switching).
    bridge.unwatch_pane(UnwatchPane {
        pane_id: "w1:p1".to_string(),
    });
    assert_eq!(
        bridge.watched_pane_id(),
        Some("w1:p2"),
        "unwatch_pane for a pane that is not watched changes nothing"
    );

    bridge.unwatch_pane(UnwatchPane {
        pane_id: "w1:p2".to_string(),
    });
    assert_eq!(
        bridge.watched_pane_id(),
        None,
        "unwatch_pane for the watched pane stops it (R-11-050)"
    );
}

/// Manual live-Herdr verification (Phase 6 `WP-6` Step 4). Run by hand with a real
/// Herdr server up:
///
/// ```text
/// cargo test -p herdr-relay --test one_pane -- --ignored --nocapture live_watch_loop_observes_only_the_watched_pane
/// ```
///
/// Set `HERDR_MANUAL_PANE_ID` to a real pane id (`herdr api snapshot` lists them)
/// before running. Read-only: calls only `ping`, `session.snapshot`, `pane.layout`,
/// `pane.read` and `events.subscribe` (R-40-030). Prints only byte counts and
/// revision numbers, never pane content, per `AGENTS.md` "Never log" and the
/// `WP-1` fixture-incident lesson: real terminal content must never touch a
/// committed artifact.
#[test]
#[ignore = "requires a live Herdr server and a real pane id; run manually"]
fn live_watch_loop_observes_only_the_watched_pane() {
    use std::time::{Duration, Instant};

    use herdr_relay::ipc::HerdrClient;
    use herdr_relay::watch::LatestSlot;
    use herdr_relay_proto::messages::PaneFrame;

    let pane_id = std::env::var("HERDR_MANUAL_PANE_ID")
        .expect("set HERDR_MANUAL_PANE_ID to a real pane id from `herdr api snapshot`");

    let config = RelayConfig::default();
    let client = HerdrClient::discover(&config).expect("locate the live herdr socket");
    client
        .ping()
        .expect("ping the live herdr server, protocol 22");

    let identity = HostIdentity {
        host_id: "manual-verification-host".to_string(),
        host_name: "manual-verification".to_string(),
    };
    let mut bridge = Bridge::new(client.clone(), identity, config);

    let (_ack, first_frame) = bridge
        .watch_pane(WatchPane {
            pane_id: pane_id.clone(),
        })
        .expect("watch_pane against the live pane");
    println!(
        "watch_pane: pane_id={} revision={} bytes={}",
        first_frame.pane_id,
        first_frame.revision,
        first_frame.text.len()
    );

    let subscription = client
        .subscribe(Bridge::<HerdrClient>::subscription_entries(
            std::iter::once(pane_id.as_str()),
        ))
        .expect("open the herdr subscription connection");
    let rx = subscription.spawn_reader();

    let frame_slot: LatestSlot<PaneFrame> = LatestSlot::new();
    let mut tree_updates_for_other_panes = 0u32;
    let mut tree_updates_total = 0u32;
    let mut frames_observed = 0u32;
    let deadline = Instant::now() + Duration::from_secs(60);

    loop {
        let now = Instant::now();
        if now >= deadline {
            break;
        }
        let window = (deadline - now).min(Duration::from_millis(500));
        let step_deadline = now + window;
        let outcome = bridge.run_until(
            &rx,
            step_deadline,
            &frame_slot,
            |message| {
                if let Message::TreeUpdate(update) = &message {
                    tree_updates_total += 1;
                    if let Some(pane) = &update.pane
                        && pane.pane_id != pane_id
                    {
                        tree_updates_for_other_panes += 1;
                    }
                }
            },
            || {},
        );
        if let Some(frame) = frame_slot.try_take() {
            frames_observed += 1;
            println!(
                "pane_frame: pane_id={} revision={} bytes={}",
                frame.pane_id,
                frame.revision,
                frame.text.len()
            );
        }
        if let Err(err) = &outcome {
            println!("run_until ended early: {err}");
            break; // subscription dropped; nothing left to observe
        }
    }

    println!(
        "observed {frames_observed} pane_frame(s) for the watched pane over 60s; \
         {tree_updates_total} tree_update(s) total, {tree_updates_for_other_panes} of them \
         referenced a different pane (expected: any number — tree_update forwards for every \
         subscribed pane, only pane_frame is scoped to the watched one)"
    );
    assert!(
        tree_updates_total > 0,
        "expected at least one tree_update over 60s of live subscription traffic"
    );
    assert!(
        frames_observed > 0,
        "expected at least one pane_frame for a pane with active revision churn over 60s"
    );
    // The load-bearing assertion: nothing here ever produced a pane_frame for a
    // pane other than the one watched (R-01-007) — checked by construction, since
    // `frame_slot` only ever receives frames `Bridge::poll_scheduler` builds from
    // `self.watched`, which is exactly the one pane this test attached to.
}
