//! `docs/90-implementation-plan.md` Phase 6: "asserting a repeated revision produces
//! no `pane.read` against a stub `herdr`" (R-10-032, R-40-029, R-02-011, R-41-167, R-41-172). No
//! test framework, no
//! real Herdr server — a hand-written stub counts calls, matching the
//! `herdr-scheduled` pattern R-40-029 sets for a shim test.

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::mpsc;
use std::time::{Duration, Instant};

use herdr_relay::config::RelayConfig;
use herdr_relay::ipc::IpcError;
use herdr_relay::watch::{Bridge, HerdrCalls, HostIdentity, LatestSlot};
use herdr_relay_proto::messages::{
    Message, PaneFrame, TreeEvent, TreeSnapshot, TreeUpdate, WatchPane,
};
use serde_json::{Value, json};

/// A stub Herdr that always reports pane `w1:p1`, and counts every `pane.read` it
/// receives. `revision` is fixed at construction: `watch_pane`'s own initial read
/// (§5.1 steps 1-7) reads it once regardless, so the test tracks reads from that
/// baseline rather than needing a mutable stub revision. Its workspaces are the
/// state right after `workspace_created_line()`'s event: the new linked worktree
/// `w2` listed first, its non-linked parent `w1` second, a plain directory `w3`
/// last — so the follow-up `tree_snapshot` (R-11-046) has a real group to map.
struct StubHerdr {
    revision: u64,
    read_calls: Arc<AtomicU32>,
}

impl HerdrCalls for StubHerdr {
    fn session_snapshot(&self) -> Result<Value, IpcError> {
        Ok(json!({
            "workspaces": [
                {
                    "workspace_id": "w2", "label": "docs", "focused": false,
                    "worktree": {
                        "repo_name": "kit", "is_linked_worktree": true,
                        "checkout_path": "D:\\private\\kit-docs", "repo_root": "D:\\private\\kit",
                        "repo_key": "repo-key-secret",
                    },
                },
                {
                    "workspace_id": "w1", "label": "kit", "focused": true,
                    "worktree": {
                        "repo_name": "kit", "is_linked_worktree": false,
                        "checkout_path": "D:\\private\\kit", "repo_root": "D:\\private\\kit",
                        "repo_key": "repo-key-secret",
                    },
                },
                { "workspace_id": "w3", "label": "scratch", "focused": false },
            ],
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
                "revision": self.revision,
                "scroll": {"offset_from_bottom": 0, "max_offset_from_bottom": 0, "viewport_rows": 50},
            }],
            "agents": [],
        }))
    }

    fn pane_layout(&self, _pane_id: &str) -> Result<Value, IpcError> {
        Ok(json!({ "panes": [{"pane_id": "w1:p1", "rect": {"width": 120}}] }))
    }

    fn pane_read_visible(&self, _pane_id: &str) -> Result<Value, IpcError> {
        self.read_calls.fetch_add(1, Ordering::SeqCst);
        // R-11-045: a bogus `revision` field on the read response itself, distinct
        // from every real revision these tests use (1, 2, 500), so a caller that
        // wrongly adopted it would be caught immediately.
        Ok(json!({ "text": "hello", "truncated": false, "revision": 999_999 }))
    }

    fn pane_read_recent(&self, _pane_id: &str, _lines: u32) -> Result<Value, IpcError> {
        self.read_calls.fetch_add(1, Ordering::SeqCst);
        Ok(json!({ "text": "hello", "truncated": false, "revision": 999_999 }))
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

/// This file proves the revision-triggered path in isolation, so its run-loop
/// tests pin the R-10-070 poll timer to "effectively never" and keep their exact
/// read-count assertions. The poll path itself is `tests/poll_timer.rs`'s job.
fn revision_only_config() -> RelayConfig {
    RelayConfig {
        poll_ms: 60_000,
        ..RelayConfig::default()
    }
}

#[test]
fn a_repeated_revision_produces_no_pane_read() {
    let read_calls = Arc::new(AtomicU32::new(0));
    let herdr = StubHerdr {
        revision: 1,
        read_calls: read_calls.clone(),
    };
    let identity = HostIdentity {
        host_id: "host-1".to_string(),
        host_name: "test-host".to_string(),
    };
    let mut bridge = Bridge::new(herdr, identity, revision_only_config());

    // watch_pane issues exactly one pane.read (the initial frame, §5.1 step 5).
    bridge
        .watch_pane(WatchPane {
            pane_id: "w1:p1".to_string(),
        })
        .expect("watch_pane succeeds against the stub");
    assert_eq!(
        read_calls.load(Ordering::SeqCst),
        1,
        "watch_pane reads exactly once"
    );

    // The same revision arriving again on the subscription MUST NOT read again
    // (R-10-032): the event carries revision 1, identical to what watch_pane just
    // observed. A tree_update is still forwarded for the raw event (R-11-046).
    let (messages, _) = bridge
        .handle_subscription_line(&pane_updated_line(1))
        .expect("handling a duplicate-revision event succeeds");
    assert!(
        messages.iter().any(|m| matches!(m, Message::TreeUpdate(_))),
        "a tree_update is still forwarded for the raw pane.updated event"
    );
    assert_eq!(
        read_calls.load(Ordering::SeqCst),
        1,
        "a repeated revision produced no pane.read (R-10-032)"
    );

    // A changed revision reads before the 120 ms window closes.
    let (tx, rx) = mpsc::channel::<std::io::Result<String>>();
    tx.send(Ok(pane_updated_line(2))).expect("queue event");

    let frame_slot: LatestSlot<PaneFrame> = LatestSlot::new();
    let started = Instant::now();
    bridge
        .run_until(
            &rx,
            started + Duration::from_millis(40),
            &frame_slot,
            |_| {},
            || {},
        )
        .expect("the run loop completes at deadline with no error");
    assert_eq!(
        read_calls.load(Ordering::SeqCst),
        2,
        "the changed revision reads without waiting for the window to close"
    );
    let frame = frame_slot
        .try_take()
        .expect("the changed revision produced a pane_frame");
    assert_eq!(frame.revision, 2);

    // Repeated events inside the window do not schedule a trailing read.
    tx.send(Ok(pane_updated_line(2)))
        .expect("queue repeated revision inside the window");
    bridge
        .run_until(
            &rx,
            started + Duration::from_millis(160),
            &frame_slot,
            |_| {},
            || {},
        )
        .expect("the run loop passes the window close with no error");
    assert_eq!(
        read_calls.load(Ordering::SeqCst),
        2,
        "the window closes without another read for the same revision"
    );
    assert!(frame_slot.try_take().is_none());

    // The same revision also stays suppressed after the window closes.
    tx.send(Ok(pane_updated_line(2)))
        .expect("queue repeated revision after the window");
    bridge
        .run_until(
            &rx,
            Instant::now() + Duration::from_millis(160),
            &frame_slot,
            |_| {},
            || {},
        )
        .expect("the run loop handles the repeated revision with no error");
    drop(tx);
    assert_eq!(
        read_calls.load(Ordering::SeqCst),
        2,
        "repeated events produce no additional pane.read (R-10-032)"
    );
    assert!(frame_slot.try_take().is_none());
}

/// R-11-045: `pane.read`'s `revision` field (here a bogus `999_999`,
/// `StubHerdr::pane_read_visible` above) MUST NOT become the tracked revision;
/// that only ever comes from the snapshot/event (R-11-045). Proof: if it had
/// been adopted, the *real* revision (1) arriving on a later event would look
/// new (since the tracked value would be 999_999, not 1) and trigger a second
/// read. It does not.
#[test]
fn pane_read_revision_field_is_never_adopted() {
    let read_calls = Arc::new(AtomicU32::new(0));
    let herdr = StubHerdr {
        revision: 1,
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
        .expect("watch_pane succeeds against the stub");
    assert_eq!(
        read_calls.load(Ordering::SeqCst),
        1,
        "watch_pane reads exactly once"
    );

    let (_messages, _) = bridge
        .handle_subscription_line(&pane_updated_line(1))
        .expect("handling the event succeeds");
    assert_eq!(
        read_calls.load(Ordering::SeqCst),
        1,
        "the real revision (1) is still treated as already-seen: pane.read's \
         bogus revision field (999_999) was never adopted as last_revision (R-11-045)"
    );
}

/// A stub Herdr whose `session.snapshot` reports pane `w1:p1` until the test
/// flips `pane_present` to `false`, simulating the pane having closed between
/// the initial watch and a later resync (R-11-071).
struct StubHerdrClosablePane {
    pane_present: Arc<AtomicBool>,
}

impl HerdrCalls for StubHerdrClosablePane {
    fn session_snapshot(&self) -> Result<Value, IpcError> {
        let panes = if self.pane_present.load(Ordering::SeqCst) {
            json!([{
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
                "revision": 1,
                "scroll": {"offset_from_bottom": 0, "max_offset_from_bottom": 0, "viewport_rows": 50},
            }])
        } else {
            json!([])
        };
        Ok(json!({ "workspaces": [], "tabs": [], "panes": panes, "agents": [] }))
    }

    fn pane_layout(&self, _pane_id: &str) -> Result<Value, IpcError> {
        Ok(json!({ "panes": [{"pane_id": "w1:p1", "rect": {"width": 120}}] }))
    }

    fn pane_read_visible(&self, _pane_id: &str) -> Result<Value, IpcError> {
        Ok(json!({ "text": "hello", "truncated": false }))
    }

    fn pane_read_recent(&self, _pane_id: &str, _lines: u32) -> Result<Value, IpcError> {
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

/// R-11-071: `resynchronize` MUST report the pane closed, and stop watching,
/// when a fresh `session.snapshot` no longer contains it (§5.5 steps 3-6).
#[test]
fn resynchronize_reports_pane_closed_when_snapshot_omits_it() {
    let pane_present = Arc::new(AtomicBool::new(true));
    let herdr = StubHerdrClosablePane {
        pane_present: pane_present.clone(),
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
        .expect("watch_pane succeeds while the pane is present");

    // The pane vanishes from Herdr's session (closed, or the workspace/tab it
    // lived in was torn down) before the next resync.
    pane_present.store(false, Ordering::SeqCst);

    let messages = bridge
        .resynchronize()
        .expect("resynchronize succeeds even when the watched pane is gone");
    assert_eq!(
        messages.len(),
        1,
        "exactly one tree_update reports the pane closed"
    );
    assert!(
        matches!(
            &messages[0],
            Message::TreeUpdate(boxed)
                if matches!(
                    boxed.as_ref(),
                    TreeUpdate {
                        event: TreeEvent::PaneClosed,
                        pane: None,
                        ..
                    }
                )
        ),
        "resynchronize reports PaneClosed when the snapshot no longer has the \
         watched pane (R-11-071)"
    );

    // Watching stopped: a further resync is a no-op, not a second PaneClosed.
    let again = bridge
        .resynchronize()
        .expect("resynchronize with nothing watched is a no-op");
    assert!(
        again.is_empty(),
        "resynchronize does nothing once the pane has already been reported closed"
    );
}

/// R-11-073: no code buffers or replays intermediate revisions — a jump from one
/// revision straight to a much later one still produces exactly one `pane.read`
/// and one `pane_frame`, reporting the destination revision directly.
#[test]
fn a_large_revision_jump_produces_exactly_one_frame() {
    let read_calls = Arc::new(AtomicU32::new(0));
    let herdr = StubHerdr {
        revision: 1,
        read_calls: read_calls.clone(),
    };
    let identity = HostIdentity {
        host_id: "host-1".to_string(),
        host_name: "test-host".to_string(),
    };
    let mut bridge = Bridge::new(herdr, identity, revision_only_config());

    bridge
        .watch_pane(WatchPane {
            pane_id: "w1:p1".to_string(),
        })
        .expect("watch_pane succeeds against the stub");
    assert_eq!(
        read_calls.load(Ordering::SeqCst),
        1,
        "watch_pane reads exactly once"
    );

    let (tx, rx) = mpsc::channel::<std::io::Result<String>>();
    tx.send(Ok(pane_updated_line(500)))
        .expect("queue the far-jumped event");

    let frame_slot: LatestSlot<PaneFrame> = LatestSlot::new();
    let deadline = Instant::now() + Duration::from_millis(500);
    bridge
        .run_until(&rx, deadline, &frame_slot, |_| {}, || {})
        .expect("the run loop completes at the deadline with no error");
    drop(tx);

    assert_eq!(
        read_calls.load(Ordering::SeqCst),
        2,
        "a jump from revision 1 to 500 issues exactly one more pane.read, not \
         one per intermediate revision (R-11-073)"
    );
    let frame = frame_slot
        .try_take()
        .expect("the jump produced exactly one pane_frame");
    assert_eq!(
        frame.revision, 500,
        "the single frame reports the destination revision directly, with no \
         intermediate frames replayed"
    );
}

fn workspace_created_line() -> String {
    json!({
        "event": "workspace.created",
        "data": {
            "workspace": {
                "workspace_id": "w2",
                "label": "docs",
                "focused": false,
            }
        }
    })
    .to_string()
}

/// INT-25-host (R-10-011, R-10-055): the host bridge opens its one long-lived
/// events subscription at session start, so a topology event Herdr pushes
/// before any `watch_pane` still reaches the Device as a `tree_update`, followed
/// by the full `tree_snapshot` that carries the regrouped `space_id`s (R-11-046),
/// and the session-start entries already carry every known pane's
/// `pane.agent_status_changed` filter (R-02-013a). A later watch subscribes to
/// nothing new: the entries are unchanged, and its only read is the §5.1
/// initial frame.
#[test]
fn a_topology_event_before_any_watch_yields_a_tree_update() {
    let read_calls = Arc::new(AtomicU32::new(0));
    let herdr = StubHerdr {
        revision: 1,
        read_calls: read_calls.clone(),
    };
    let identity = HostIdentity {
        host_id: "host-1".to_string(),
        host_name: "test-host".to_string(),
    };
    let mut bridge = Bridge::new(herdr, identity, revision_only_config());

    // What `bridge_thread` subscribes at session start, with no watch yet:
    // the unfiltered tree events plus one agent-status filter per known pane.
    let entries = bridge.current_subscription_entries();
    assert!(
        entries.iter().any(|e| e["type"] == "workspace.created"),
        "the session-start subscription carries the tree events"
    );
    let agent_filters: Vec<_> = entries
        .iter()
        .filter(|e| e["type"] == "pane.agent_status_changed")
        .collect();
    assert_eq!(
        agent_filters.len(),
        1,
        "one agent-status filter per known pane"
    );
    assert_eq!(agent_filters[0]["pane_id"], "w1:p1");

    // A topology event pushed before any `watch_pane` still forwards: first the
    // incremental `tree_update` mapped from the event's own payload, then the
    // full `tree_snapshot` that resynchronises group membership (R-11-046).
    let (messages, _) = bridge
        .handle_subscription_line(&workspace_created_line())
        .expect("handling a topology event succeeds");
    assert_eq!(
        messages.len(),
        2,
        "a workspace event forwards the tree_update plus one full tree_snapshot"
    );
    assert!(
        matches!(
            &messages[0],
            Message::TreeUpdate(boxed)
                if matches!(
                    boxed.as_ref(),
                    TreeUpdate {
                        event: TreeEvent::WorkspaceCreated,
                        workspace: Some(workspace),
                        ..
                    } if workspace.workspace_id == "w2"
                        && workspace.name == "docs"
                        && workspace.space_id.is_none()
                )
        ),
        "the first message is the workspace_created tree_update, mapped from the \
         event's own payload, with no group id (only a snapshot is authoritative)"
    );
    let Message::TreeSnapshot(TreeSnapshot { workspaces, .. }) = &messages[1] else {
        panic!(
            "the second message is the follow-up tree_snapshot: {:?}",
            messages[1]
        );
    };
    let rows: Vec<(&str, &str, Option<&str>)> = workspaces
        .iter()
        .map(|w| {
            (
                w.workspace_id.as_str(),
                w.name.as_str(),
                w.space_id.as_deref(),
            )
        })
        .collect();
    assert_eq!(
        rows,
        [
            ("w2", "docs", Some("w1")),
            ("w1", "kit", Some("w1")),
            ("w3", "scratch", None),
        ],
        "Herdr's own order is kept; the linked `w2` and its parent `w1` share the \
         parent's id even though the linked member comes first; the plain `w3` \
         stays ungrouped; names are the snapshot labels verbatim"
    );
    let wire = serde_json::to_string(&messages[1]).expect("tree_snapshot serializes");
    for leaked in [
        "repo_key",
        "repo-key-secret",
        "checkout_path",
        "repo_root",
        "D:\\private",
    ] {
        assert!(
            !wire.contains(leaked),
            "{leaked} must not cross the wire: {wire}"
        );
    }

    // The later watch issues exactly its §5.1 initial read and needs no new
    // subscription: the session-start entries already cover every pane, so
    // there is no second subscriber to open.
    bridge
        .watch_pane(WatchPane {
            pane_id: "w1:p1".to_string(),
        })
        .expect("watch_pane succeeds against the stub");
    assert_eq!(
        read_calls.load(Ordering::SeqCst),
        1,
        "watch_pane issues exactly one pane.read (the initial frame, §5.1 step 5)"
    );
    assert_eq!(
        bridge.current_subscription_entries(),
        entries,
        "the watch changed no subscription entries: one subscription still covers every pane"
    );
}

/// R-11-046 as amended 2026-09-11: Herdr pushes `tab_closed`, `pane_closed` and
/// `pane_agent_status_changed` with a flat payload, measured live as
/// `{"tab_id","workspace_id"}` for `tab_closed`, so the mapped `tree_update`
/// carries no object and the Device cannot apply it. Each of the three MUST be
/// followed by one full `tree_snapshot`, which is what removes a closed tab's
/// panes (Herdr sends no `pane_closed` for them) and moves `done` back to
/// `working`. A `working` status forwards no `agent_status` (R-11-057) but
/// still gets the snapshot.
#[test]
fn flat_close_and_status_events_are_followed_by_a_snapshot() {
    let herdr = StubHerdr {
        revision: 1,
        read_calls: Arc::new(AtomicU32::new(0)),
    };
    let mut bridge = Bridge::new(
        herdr,
        HostIdentity {
            host_id: "host-1".to_string(),
            host_name: "test-host".to_string(),
        },
        revision_only_config(),
    );
    for (line, event) in [
        // R-11-046 second amendment, R-02-031: seen changes have no status event.
        (
            json!({"event":"pane.focused","data":{"type":"pane_focused","pane_id":"w1:p1","workspace_id":"w1"}}),
            TreeEvent::PaneFocused,
        ),
        (
            json!({"event": "tab.closed", "data": {"type": "tab_closed", "tab_id": "t9", "workspace_id": "w1"}}),
            TreeEvent::TabClosed,
        ),
        (
            json!({"event": "pane.closed", "data": {"type": "pane_closed", "pane_id": "w1:p9", "workspace_id": "w1"}}),
            TreeEvent::PaneClosed,
        ),
        (
            json!({"event": "pane.agent_status_changed", "data": {"type": "pane_agent_status_changed", "pane_id": "w1:p1", "workspace_id": "w1", "agent_status": "working"}}),
            TreeEvent::PaneAgentStatusChanged,
        ),
    ] {
        let (messages, _) = bridge
            .handle_subscription_line(&line.to_string())
            .expect("a flat event is handled");
        assert_eq!(
            messages.len(),
            2,
            "{event:?}: the objectless tree_update plus one full tree_snapshot, no agent_status"
        );
        assert!(
            matches!(
                &messages[0],
                Message::TreeUpdate(boxed)
                    if boxed.event == event
                        && boxed.pane.is_none()
                        && boxed.tab.is_none()
                        && boxed.workspace.is_none()
            ),
            "{event:?}: the flat payload maps to a tree_update with no object"
        );
        assert!(
            matches!(&messages[1], Message::TreeSnapshot(_)),
            "{event:?}: the follow-up is the full tree_snapshot the Device adopts wholesale"
        );
    }
}
