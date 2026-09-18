//! The bridge's per-Device state (R-11-224), and the low-level Herdr-call plus
//! raw-to-wire mapping glue every other `impl Bridge` block in this module
//! shares. Other files in this module (`requests.rs`, `incoming.rs`,
//! `run_loop.rs`) add further `impl<H: HerdrCalls> Bridge<H>` blocks for the same
//! type — a single struct definition, split responsibilities (R-41-011).

use std::collections::HashMap;
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};
use std::time::{Duration, Instant};

use herdr_relay_proto::messages::{AgentSummary, HostInfo, TreeSnapshot};

use crate::config::RelayConfig;
use crate::ipc::IpcError;

use super::herdr_calls::HerdrCalls;
use super::raw::{RawSnapshot, map_pane, map_tab, map_workspaces};
use super::scheduler::PaneScheduler;

/// An error from the watch loop: either Herdr rejected or failed a call, or a
/// Herdr response did not carry a field the loop needed.
#[derive(Debug, thiserror::Error)]
pub enum WatchError {
    #[error("herdr call failed: {0}")]
    Herdr(#[from] IpcError),
    #[error("herdr session.snapshot did not include pane {0}")]
    PaneNotInSnapshot(String),
    #[error("herdr response for {method} carried no usable {field}")]
    MissingField {
        method: &'static str,
        field: &'static str,
    },
    #[error("herdr response for {method} did not parse: {source}")]
    Malformed {
        method: &'static str,
        #[source]
        source: serde_json::Error,
    },
    #[error("the herdr subscription connection closed")]
    SubscriptionClosed,
    /// R-01-006: the Device named a pane that is not the one it is watching. Only
    /// `send_input` enforces this (R-01-007 restricts input to the single watched
    /// pane); `host_action`'s pane-scoped operations act on any pane the tree
    /// already named to the Device, and let Herdr's own `pane_not_found` surface
    /// through [`WatchError::Herdr`] instead.
    #[error("pane {0} is not the watched pane")]
    NotWatching(String),
    /// R-11-055, R-10-013: a `send_input` or `host_action` failed local validation
    /// before it ever reached Herdr (an unsupported key name, a missing required
    /// field, or an empty `send_input`).
    #[error("{0}")]
    InvalidInput(String),
    /// R-11-063: `revoke_device` failed local validation or store/key I/O,
    /// surfaced by `watch/devices.rs`'s own typed `DeviceError` (R-41-125/026:
    /// an error crossing that module boundary stays typed, never restringified).
    #[error("device management failed: {0}")]
    Device(#[from] super::devices::DeviceError),
}

/// This build's identity, sent once as `host_info` (R-11-130). `host_id` and
/// `host_name` are Phase 10's (`keys.rs`/pairing) concern to source; the watch loop
/// only formats them onto the wire.
#[derive(Debug, Clone)]
pub struct HostIdentity {
    pub host_id: String,
    pub host_name: String,
}

/// The pane a Device is currently watching (R-10-033: at most one).
#[derive(Debug, Clone)]
pub(super) struct WatchedPane {
    pub(super) pane_id: String,
    /// The dedup/resync baseline (R-10-032, R-10-035): updated the moment a
    /// genuinely new revision is observed, independent of whether the resulting
    /// read later succeeds (`docs/10-herdr-integration.md` §5.2 steps 3-4 update
    /// this before the read is even attempted; R-10-034's "keep it unchanged on a
    /// failed read" already holds because nothing here rolls it back).
    pub(super) last_revision: u64,
    pub(super) viewport_rows: u32,
    /// Refreshed only when `viewport_rows` changes (R-10-025), never per frame.
    pub(super) width: u32,
    /// R-10-070: hash of the last frame actually sent (ANSI text plus geometry).
    /// A poll read whose hash matches is not sent, so an unchanged pane costs no
    /// wire bytes. Updated by every frame this bridge sends, from any trigger.
    pub(super) last_frame_hash: u64,
}

/// R-10-070: the dedupe token for a frame — the ANSI text plus the geometry the
/// Device renders at, so a resize with identical text still sends. Stdlib
/// `DefaultHasher` only; the value never leaves this process.
pub(super) fn frame_hash(text: &str, viewport_rows: u32, width: u32) -> u64 {
    use std::hash::{Hash, Hasher};
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    text.hash(&mut hasher);
    viewport_rows.hash(&mut hasher);
    width.hash(&mut hasher);
    hasher.finish()
}

/// The bridge's per-Device state: the watched pane, its scheduler, the agent
/// status timestamps observed since attach, and the `agent_status` settle
/// baseline per pane (R-11-224). Generic over [`HerdrCalls`] so a test drives
/// it against a stub with no live Herdr server (R-40-029 style).
pub struct Bridge<H: HerdrCalls> {
    pub(super) herdr: H,
    pub(super) config: RelayConfig,
    identity: HostIdentity,
    pub(super) watched: Option<WatchedPane>,
    pub(super) scheduler: Option<PaneScheduler>,
    /// pane_id -> RFC 3339 timestamp of the last observed `pane.agent_status_changed`
    /// (R-11-224: the Host MUST NOT invent or backfill this from the snapshot time).
    /// `pub(crate)` so `crate::bridge`'s session thread can swap in the
    /// process-lifetime map `HostState` owns: a Device reconnect then
    /// rehydrates `status_at` from what this bridge process really observed,
    /// while a bridge restart still clears it — R-11-224's own "predates the
    /// bridge start" case.
    pub(crate) agent_status_observed: Arc<Mutex<HashMap<String, String>>>,
    /// R-10-075: shared across Device sessions and watch changes.
    pub(crate) input_lines: Arc<Mutex<HashMap<String, String>>>,
    /// pane_id -> `Instant` of the last `agent_status` message actually sent for
    /// that pane's agent (R-11-059: the 30-second settle window). Separate from
    /// `agent_status_observed` above, which records every observed change
    /// (`idle`/`working` included) for `TreeSnapshot.agents[].status_at`; this
    /// tracks only sends, gating whether the next `blocked`/`done` event fires
    /// one.
    pub(super) agent_status_settled: HashMap<String, Instant>,
    pub(super) pending_input: Option<super::held_input::PendingInput>,
    /// R-10-078: the transport clears this flag before the session thread ends.
    pub(crate) session_active: Option<Arc<std::sync::atomic::AtomicBool>>,
    pub(super) input_replies: Vec<(herdr_relay_proto::messages::Message, Option<String>)>,
}

/// Locks a shared pane map and recovers a poisoned lock.
/// This follows the policy of `crate::bridge::lock`.
pub(super) fn lock_observed(
    map: &Arc<Mutex<HashMap<String, String>>>,
) -> MutexGuard<'_, HashMap<String, String>> {
    map.lock().unwrap_or_else(PoisonError::into_inner)
}

/// R-11-059: the 30-second settle window per agent, collapsing a flapping
/// status (`blocked` -> `working` -> `blocked` within the window) into one
/// `agent_status` send. Not a `RelayConfig` tunable: like
/// `crate::relay::StaleDeviceDetector`'s pong timeout and hold-open window,
/// this is a fixed relay-protocol constant (`docs/11-relay-protocol.md`), not
/// a Host knob.
const AGENT_STATUS_SETTLE: Duration = Duration::from_secs(30);

impl<H: HerdrCalls> Bridge<H> {
    pub fn new(herdr: H, identity: HostIdentity, config: RelayConfig) -> Self {
        Self {
            herdr,
            config,
            identity,
            watched: None,
            scheduler: None,
            agent_status_observed: Arc::new(Mutex::new(HashMap::new())),
            input_lines: Arc::new(Mutex::new(HashMap::new())),
            agent_status_settled: HashMap::new(),
            pending_input: None,
            session_active: None,
            input_replies: Vec::new(),
        }
    }

    /// This build's `host_id` (R-11-057's `agent_status.host_id`, R-11-130's
    /// `host_info.host_id`): the same identity, read without re-formatting a
    /// whole `HostInfo`.
    pub(super) fn host_id(&self) -> &str {
        &self.identity.host_id
    }

    /// `host_info` (§4.1). MUST be the first frame after the Noise transport
    /// reaches transport mode (R-11-130); the caller (`relay.rs`'s session
    /// handler) sends it at that moment using this builder.
    pub fn host_info(&self, herdr_version: String, herdr_protocol: u32, paired: bool) -> HostInfo {
        HostInfo {
            protocol: 1,
            host_id: self.identity.host_id.clone(),
            host_name: self.identity.host_name.clone(),
            herdr_version,
            herdr_protocol,
            paired,
            theme: None,
        }
    }

    /// The current watched pane, if any.
    pub fn watched_pane_id(&self) -> Option<&str> {
        self.watched.as_ref().map(|w| w.pane_id.as_str())
    }

    /// R-11-059: `true`, and records `now` as the new baseline, only when at
    /// least [`AGENT_STATUS_SETTLE`] has elapsed since the last `agent_status`
    /// this pane's agent sent, or none was ever sent. `false` means suppress:
    /// the caller MUST NOT send `agent_status` this time.
    pub(super) fn settle_agent_status(&mut self, pane_id: &str, now: Instant) -> bool {
        let due = self
            .agent_status_settled
            .get(pane_id)
            .is_none_or(|&last| now.saturating_duration_since(last) >= AGENT_STATUS_SETTLE);
        if due {
            self.agent_status_settled.insert(pane_id.to_owned(), now);
        }
        due
    }

    pub(super) fn fetch_snapshot(&self) -> Result<RawSnapshot, WatchError> {
        let raw = self.herdr.session_snapshot()?;
        serde_json::from_value(raw).map_err(|source| WatchError::Malformed {
            method: "session.snapshot",
            source,
        })
    }

    pub(super) fn map_snapshot(&self, raw: RawSnapshot) -> TreeSnapshot {
        let observed = lock_observed(&self.agent_status_observed);
        let agents = raw
            .agents
            .into_iter()
            .map(|a| AgentSummary {
                agent_kind: a.agent,
                pane_id: a.pane_id.clone(),
                status: a.agent_status,
                status_at: observed.get(&a.pane_id).cloned(),
                session: a.agent_session.and_then(|s| s.value),
            })
            .collect();
        TreeSnapshot {
            workspaces: map_workspaces(raw.workspaces),
            tabs: raw.tabs.into_iter().map(map_tab).collect(),
            panes: raw.panes.into_iter().map(map_pane).collect(),
            agents,
        }
    }

    pub(super) fn fetch_width(&self, pane_id: &str) -> Result<u32, WatchError> {
        let layout = self.herdr.pane_layout(pane_id)?;
        layout
            .get("panes")
            .and_then(serde_json::Value::as_array)
            .and_then(|panes| {
                panes
                    .iter()
                    .find(|p| p.get("pane_id").and_then(serde_json::Value::as_str) == Some(pane_id))
            })
            .and_then(|p| p.get("rect"))
            .and_then(|r| r.get("width"))
            .and_then(serde_json::Value::as_u64)
            .map(|w| w as u32)
            .ok_or(WatchError::MissingField {
                method: "pane.layout",
                field: "rect.width",
            })
    }

    pub(super) fn fetch_visible_text(&self, pane_id: &str) -> Result<String, WatchError> {
        let read = self.herdr.pane_read_visible(pane_id)?;
        read.get("text")
            .and_then(serde_json::Value::as_str)
            .map(str::to_owned)
            .ok_or(WatchError::MissingField {
                method: "pane.read",
                field: "text",
            })
    }
}
