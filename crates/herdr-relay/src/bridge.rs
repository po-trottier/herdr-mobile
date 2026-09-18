//! The long-lived Host bridge process (R-10-062 through R-10-069).
//!
//! One process holds every relay connection, the paired-device store and the
//! open pairing (R-10-068): one `/host/<handle>` registration per
//! paired-device entry as the `Noise_KK` responder (R-13-037), plus one
//! registration for the open pairing as the `Noise_XXpsk0` responder
//! (R-13-035) while one is open, all under one active-session guard
//! (R-10-069). The popup pane and `herdr-relay ctl` are loopback clients of
//! the control transport (`crate::control`, R-10-062 to R-10-065); they never
//! mint a credential and never open a relay connection of their own.
//!
//! # Diagnostics discipline (R-10-065, `AGENTS.md`)
//!
//! Every log line this file emits is fixed text plus counts and states. No
//! line ever carries a phrase, a pairing URI, a handle, a key, a token, a
//! device id or a user path, and no error's `Display` is ever logged (a
//! connect error's text can embed the URL, which embeds the handle).
//!
//! # Environment
//!
//! - `HERDR_RELAY_HOST_CONNECT_ORIGIN`: overrides the origin this process
//!   dials, for local no-TLS dev testing only (see `run_inner`).
//! - `HERDR_RELAY_CONFIG_DIR`: overrides the plugin config directory that
//!   `config::resolve_config_dir` would otherwise shell out to `herdr` for
//!   (R-10-045). Honoured only when set and non-empty; exists so the phase
//!   gate's live proof and integration tests run a bridge against a
//!   throwaway state directory without touching the live plugin state.
//!   `config.rs` itself needs no change: this is the one caller that wants
//!   the override, so the read lives here.

use std::collections::HashMap;
use std::io::Write as _;
use std::path::PathBuf;
use std::sync::mpsc as std_mpsc;
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};
use std::time::{Duration, Instant};

use futures_util::{SinkExt as _, StreamExt as _};
use tokio_tungstenite::tungstenite::Message as WsMessage;
use tokio_tungstenite::tungstenite::protocol::CloseFrame;
use tokio_tungstenite::tungstenite::protocol::frame::coding::CloseCode as WsCloseCode;

use herdr_relay_proto::codes::{CloseCode, ErrorCode as WireErrorCode};
use herdr_relay_proto::frame::{Frame, SequenceCounter};
use herdr_relay_proto::handle::{Handle, is_absolute_http_origin};
use herdr_relay_proto::messages::MarkSeen;
use herdr_relay_proto::messages::{
    ActionListRequest, DeviceListRequest, ErrorMessage, HostAction, HostInfo, Message, PaneFrame,
    RevokeDevice, RevokeResult, ScrollRequest, SendInput, UnwatchPane, WatchPane,
};

use crate::config::{self, ConfigError, ConfigPaths, RelayConfig};
use crate::control::{self, Command};
use crate::frame_codec::Reassembler;
use crate::ipc::HerdrClient;
use crate::keys::{self, HostKeypair};
use crate::noise::Transport;
use crate::pairing::{PHRASE_LIFETIME, PairingSession, wordlist};
use crate::popup::INVALID_ORIGIN_NOTICE;
use crate::relay::{
    self, CloseReason, ConnectError, HandshakeSetup, ReconnectBackoff, SessionRegistry, WsStream,
};
use crate::store::{DeviceStore, StoreError};
use crate::watch::{Bridge, HostIdentity, LatestSlot};

/// One diagnostics line sink (R-10-051's `relay.log`). Every line is fixed
/// text plus counts and states only (R-10-065); the type itself is the
/// reason no call site can accidentally format a secret into one.
pub type Log = Arc<dyn Fn(&str) + Send + Sync>;

/// Everything [`start`] needs, already loaded and validated. `run` builds
/// this from real I/O; `tests/host_pairing.rs` builds it with a stub Herdr
/// socket path and a throwaway state directory.
pub struct HostConfig {
    /// The plugin state directory (R-10-051).
    pub paths: ConfigPaths,
    /// Every tunable from `config.toml` (R-10-051); `relay_origin` is the
    /// operator-facing origin embedded in pairing URIs.
    pub relay_config: RelayConfig,
    /// The literal `ws(s)://` origin this process dials (usually
    /// `relay_origin` mapped by [`to_ws_origin`]; the dev override differs).
    pub ws_origin: String,
    /// The Host's Curve25519 static keypair (R-13-058).
    pub keypair: HostKeypair,
    /// The pairing word list, loaded once (R-13-017).
    pub words: Vec<String>,
    /// The Herdr socket client. Never constructed by `start` itself, so a
    /// test passes `HerdrClient::with_path` at a stub path.
    pub client: HerdrClient,
    /// `ping`'s version, reported in `host_info` (R-11-130).
    pub herdr_version: String,
    /// `ping`'s protocol integer (R-10-012).
    pub herdr_protocol: u32,
    /// The machine hostname for `host_info.host_name` (R-10-068).
    pub host_name: String,
    /// The diagnostics sink.
    pub log: Log,
}

/// A startup failure of [`start`]. Every `Display` is fixed text plus the
/// wrapped error's own fixed text (R-10-065).
#[derive(Debug, thiserror::Error)]
pub enum BridgeError {
    #[error("load the paired-device list failed: {0}")]
    Store(#[from] StoreError),
    #[error("bind the loopback control listener failed: {0}")]
    Bind(#[source] std::io::Error),
    #[error("publish the control endpoint failed: {0}")]
    Endpoint(#[from] control::ControlError),
}

/// The running bridge: the control-plane handler plus the task set. Dropped
/// only through [`HostHandle::shutdown`], which removes the `control` key
/// from `state.json` (R-10-062's clean-exit rule).
pub struct HostHandle {
    state: Arc<Mutex<HostState>>,
    handler: Arc<dyn control::Handler>,
    serve_task: tokio::task::JoinHandle<()>,
    paths: ConfigPaths,
}

impl HostHandle {
    /// The control handler, for a same-process caller (the integration
    /// test). Production callers go through the R-10-062 socket.
    pub fn handler(&self) -> Arc<dyn control::Handler> {
        Arc::clone(&self.handler)
    }

    /// The state directory this bridge publishes its endpoint in.
    pub fn paths(&self) -> &ConfigPaths {
        &self.paths
    }

    /// Stops every task and removes the `control` key (R-10-062). Aborting
    /// the registration and pairing tasks drops their sockets, which ends
    /// every relay registration they held (R-11-125).
    pub async fn shutdown(self) {
        self.serve_task.abort();
        let (pairing, registrations) = {
            let mut state = lock(&self.state);
            (
                state.open_pairing.take().map(|open| open.task),
                std::mem::take(&mut state.registrations),
            )
        };
        if let Some(task) = pairing {
            task.abort();
        }
        for (_device_id, task) in registrations {
            task.abort();
        }
        if let Err(_err) = control::clear_endpoint(&self.paths) {
            (lock(&self.state).log)("herdr-relay: clearing the control endpoint failed");
        }
    }
}

// ---------------------------------------------------------------------------
// The shared Host state (R-10-063: every control answer comes from here)
// ---------------------------------------------------------------------------

/// One open pairing (R-13-035): the minted session, whether the relay has
/// accepted its registration (R-10-064's `registered`), and the task driving
/// that registration and the Device handshake wait.
struct OpenPairing {
    session: PairingSession,
    minted_at: tokio::time::Instant,
    registered: bool,
    task: tokio::task::JoinHandle<()>,
}

/// The one live Device session (R-10-069's guard). `device_id` is `None`
/// between a pairing handshake's completion and that session's `device_info`
/// (R-11-131).
struct ActiveSession {
    device_id: Option<String>,
    handle: Handle,
}

// R-10-069: task cancellation must release only its own session claim.
struct ActiveClaim {
    state: Arc<Mutex<HostState>>,
    handle: Handle,
}

impl Drop for ActiveClaim {
    fn drop(&mut self) {
        release_active(&self.state, self.handle);
    }
}
struct HostState {
    paths: ConfigPaths,
    store: DeviceStore,
    open_pairing: Option<OpenPairing>,
    /// The one Host-wide active-session guard (R-10-069).
    active: Option<ActiveSession>,
    link: control::LinkStatus,
    stopped: bool,
    relay_origin: String,
    ws_origin: String,
    keypair: HostKeypair,
    herdr_version: String,
    herdr_protocol: u32,
    host_name: String,
    client: HerdrClient,
    relay_config: RelayConfig,
    registry: SessionRegistry,
    words: Vec<String>,
    /// Live `Noise_KK` registration loops, by device id, so `revoke` and
    /// `revoke_all` can drop them (R-13-053 step 2, R-13-056 step 3).
    registrations: HashMap<String, tokio::task::JoinHandle<()>>,
    /// pane_id -> RFC 3339 of the last `pane.agent_status_changed` this
    /// process observed (R-11-224). One map per bridge process, handed to
    /// every session's `watch::Bridge`, so a Device reconnect rehydrates
    /// `status_at` from real observations; a bridge restart clears it, which
    /// R-11-224's own "predates the bridge start" case already allows.
    agent_status_observed: Arc<Mutex<HashMap<String, String>>>,
    input_lines: Arc<Mutex<HashMap<String, String>>>,
    /// `true` while stopped (R-10-064's `stop`): registration loops park on
    /// this channel and serving loops close their sockets when it fires.
    stop_tx: tokio::sync::watch::Sender<bool>,
    log: Log,
}

fn lock(state: &Arc<Mutex<HostState>>) -> MutexGuard<'_, HostState> {
    state.lock().unwrap_or_else(PoisonError::into_inner)
}

fn link_idle() -> control::LinkStatus {
    control::LinkStatus {
        state: control::LinkState::Idle,
        attempt: 0,
        error: None,
    }
}

fn link_connected() -> control::LinkStatus {
    control::LinkStatus {
        state: control::LinkState::Connected,
        attempt: 0,
        error: None,
    }
}

// ---------------------------------------------------------------------------
// Startup
// ---------------------------------------------------------------------------

/// Starts the bridge: binds the R-10-062 control listener, publishes the
/// endpoint, spawns `control::serve`, and starts one `Noise_KK` registration
/// loop per stored entry that has a usable handle (R-10-068). Must be called
/// inside a tokio runtime (every task it spawns is a tokio task).
pub async fn start(config: HostConfig) -> Result<HostHandle, BridgeError> {
    let store = DeviceStore::load(config.paths.clone())?;
    let (listener, port) = control::bind().await.map_err(BridgeError::Bind)?;
    let token = control::new_token();
    control::write_endpoint(
        &config.paths,
        &control::ControlEndpoint {
            pid: std::process::id(),
            port,
            token: token.clone(),
        },
    )?;

    let (stop_tx, _) = tokio::sync::watch::channel(false);
    let state = Arc::new(Mutex::new(HostState {
        paths: config.paths.clone(),
        store,
        open_pairing: None,
        active: None,
        link: link_idle(),
        stopped: false,
        relay_origin: config.relay_config.relay_origin.clone(),
        ws_origin: config.ws_origin,
        keypair: config.keypair,
        herdr_version: config.herdr_version,
        herdr_protocol: config.herdr_protocol,
        host_name: config.host_name,
        client: config.client,
        relay_config: config.relay_config,
        registry: SessionRegistry::new(),
        words: config.words,
        registrations: HashMap::new(),
        agent_status_observed: Arc::new(Mutex::new(HashMap::new())),
        input_lines: Arc::new(Mutex::new(HashMap::new())),
        stop_tx,
        log: config.log,
    }));

    // R-10-068: one registration per stored entry. Pre-25 entries can carry
    // an empty handle (`#[serde(default)]` keeps them loadable); they are
    // unservable and skipped, one count line and never an id (R-10-065).
    let device_ids: Vec<String> = {
        lock(&state)
            .store
            .devices()
            .iter()
            .map(|device| device.device_id.clone())
            .collect()
    };
    let mut started = 0usize;
    let mut skipped = 0usize;
    for device_id in &device_ids {
        if spawn_registration(&state, device_id) {
            started += 1;
        } else {
            skipped += 1;
        }
    }
    if started > 0 {
        (lock(&state).log)(&format!(
            "herdr-relay: {started} paired device registration(s) started"
        ));
    }
    if skipped > 0 {
        (lock(&state).log)(&format!(
            "herdr-relay: {skipped} paired device(s) skipped: no routing handle"
        ));
    }

    let handler: Arc<dyn control::Handler> = Arc::new(HostCore {
        state: Arc::clone(&state),
    });
    let serve_task = tokio::spawn(control::serve(listener, token, Arc::clone(&handler)));
    (lock(&state).log)("herdr-relay: bridge started");
    Ok(HostHandle {
        state,
        handler,
        serve_task,
        paths: config.paths,
    })
}

/// The config directory both the bridge and the `ctl`/popup clients resolve,
/// honouring `HERDR_RELAY_CONFIG_DIR` when set (see the module doc comment),
/// otherwise `herdr plugin config-dir herdr-relay` (R-10-045). Only the
/// resolved live directory opts into the platform credential store
/// (`ConfigPaths::with_os_keyring`); an override is a throwaway state
/// directory and keeps its Host keypair in its own fallback file, so a
/// proof run or a test can never rotate the live Host key.
pub fn control_paths() -> Result<ConfigPaths, ConfigError> {
    match std::env::var_os("HERDR_RELAY_CONFIG_DIR") {
        Some(dir) if !dir.is_empty() => Ok(ConfigPaths::new(PathBuf::from(dir))),
        _ => config::resolve_config_dir().map(ConfigPaths::with_os_keyring),
    }
}

/// Entry point for `main.rs`'s no-argument path. Never returns on success; a
/// setup failure (no Herdr server, no relay origin configured, no word list)
/// prints one line and exits non-zero, matching `main.rs`'s existing `popup`
/// error convention.
pub fn run() {
    if let Err(err) = run_inner() {
        eprintln!("herdr-relay: {err}");
        std::process::exit(1);
    }
}

// R-10-065: startup diagnostics cannot contain dynamic error text or private paths.
fn run_inner() -> Result<(), &'static str> {
    let paths = control_paths().map_err(|_| "resolve config directory failed")?;
    paths
        .ensure_dir()
        .map_err(|_| "create config directory failed")?;
    let relay_config = config::load(&paths).map_err(|_| "load config.toml failed")?;
    if relay_config.relay_origin.trim().is_empty() {
        return Err("relay origin not configured - set relay_origin in config.toml");
    }
    if !is_absolute_http_origin(relay_config.relay_origin.trim()) {
        // R-10-061: a `ws://`/`wss://` value here would flow into the pairing
        // URI and every Device would reject it. Same message the pairing pane
        // shows (R-31-16-06), one string, one home.
        return Err(INVALID_ORIGIN_NOTICE);
    }

    let keypair = keys::load_or_generate(&paths).map_err(|_| "load host keypair failed")?;

    let words = wordlist::load(&paths.wordlist_cache_file())
        .map_err(|_| "load pairing word list failed")?;

    let client = HerdrClient::discover(&relay_config).map_err(|_| "locate herdr socket failed")?;
    let ping = client.ping().map_err(|_| "ping herdr failed")?;
    let herdr_version = ping
        .get("result")
        .and_then(|r| r.get("version"))
        .and_then(|v| v.as_str())
        .unwrap_or("unknown")
        .to_owned();
    let herdr_protocol = ping
        .get("result")
        .and_then(|r| r.get("protocol"))
        .and_then(serde_json::Value::as_u64)
        .unwrap_or(0) as u32;

    // The address this process (the Host) dials can differ from the address in
    // the credentials the phone is shown (R-10-061): the Android emulator's
    // `10.0.2.2` alias is reachable only from inside the emulator, and a
    // mirrored-mode WSL relay cannot be reached from the Windows host through
    // the host's own LAN address. Precedence: the environment override (tests
    // and one-off runs), then the `host_connect_origin` key of `config.toml`
    // (the supervised bridge, which has no environment of its own), then
    // `relay_origin` itself, which is every real deployment (R-01-013).
    let host_connect_origin = std::env::var("HERDR_RELAY_HOST_CONNECT_ORIGIN")
        .ok()
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| {
            if relay_config.host_connect_origin.trim().is_empty() {
                relay_config.relay_origin.clone()
            } else {
                relay_config.host_connect_origin.clone()
            }
        });
    if !is_absolute_http_origin(host_connect_origin.trim()) {
        // R-10-061: the override passes through `to_ws_origin` too, so it
        // holds to the same shape as `relay_origin` itself.
        return Err(INVALID_ORIGIN_NOTICE);
    }
    let ws_origin = to_ws_origin(&host_connect_origin);

    // R-10-051: diagnostics go to `relay.log` in the plugin state directory
    // and to stdout for a foreground run. Every line is fixed text plus
    // counts and states (R-10-065), enforced by `Log` taking a `&str` the
    // call sites build only from literals and numbers.
    let log_file = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(paths.log_file())
        .map_err(|_| "open relay.log failed")?;
    let log_file = Mutex::new(log_file);
    let log: Log = Arc::new(move |line: &str| {
        println!("{line}");
        if let Ok(mut file) = log_file.lock() {
            let _ = writeln!(file, "{line}");
        }
    });

    let host_config = HostConfig {
        paths,
        relay_config,
        ws_origin,
        keypair,
        words,
        client,
        herdr_version,
        herdr_protocol,
        host_name: host_name(),
        log,
    };

    let probe = host_config.client.clone();
    let runtime = tokio::runtime::Runtime::new().map_err(|_| "start the async runtime failed")?;
    runtime.block_on(async move {
        let host = start(host_config)
            .await
            .map_err(|_| "start the host bridge failed")?;
        // R-10-062: a clean exit removes the `control` key.
        tokio::select! {
            _ = tokio::signal::ctrl_c() => {}
            _ = herdr_gone(probe) => {}
        }
        host.shutdown().await;
        Ok(())
    })
}

/// R-10-049: the bridge lives as long as the Herdr server does. Resolves once
/// `ping` has failed for `HERDR_GONE_AFTER` straight, so a quit Herdr leaves
/// no orphan bridge and the supervisor's next start (Herdr's startup hook
/// reconciles it) begins from a clean registration. A restart shorter than the
/// window is invisible: the socket returns and the counter resets.
const HERDR_GONE_AFTER: Duration = Duration::from_secs(5 * 60);
const HERDR_PROBE_EVERY: Duration = Duration::from_secs(30);

async fn herdr_gone(client: HerdrClient) {
    let mut failures = 0u32;
    loop {
        tokio::time::sleep(HERDR_PROBE_EVERY).await;
        let probe = client.clone();
        let ok = tokio::task::spawn_blocking(move || probe.ping().is_ok())
            .await
            .unwrap_or(false);
        failures = if ok { 0 } else { failures + 1 };
        if u64::from(failures) * HERDR_PROBE_EVERY.as_secs() >= HERDR_GONE_AFTER.as_secs() {
            return;
        }
    }
}

/// R-10-068: the machine hostname as `host_info.host_name` (at most 64 UTF-8
/// bytes, R-11-130's field comment). No new dependency: `COMPUTERNAME`
/// (Windows) then `HOSTNAME` (POSIX), `unknown` when neither is set.
fn host_name() -> String {
    let name = std::env::var("COMPUTERNAME")
        .or_else(|_| std::env::var("HOSTNAME"))
        .unwrap_or_default()
        .trim()
        .to_owned();
    let name = if name.is_empty() {
        "unknown".to_owned()
    } else {
        name
    };
    bounded_host_name(name)
}

// R-11-130: the hostname limit counts UTF-8 bytes, not characters.
fn bounded_host_name(mut name: String) -> String {
    let mut end = name.len().min(64);
    while !name.is_char_boundary(end) {
        end -= 1;
    }
    name.truncate(end);
    name
}

/// `https://` -> `wss://`, `http://` -> `ws://` (R-11-111 assigns this mapping
/// to the Device/app side; `relay::connect_host` performs none of its own, so
/// the Host side does it here, the same transform `app/lib/services/origin.dart`'s
/// `RelayOrigin.webSocketUri` applies). Total: every caller validates with
/// [`is_absolute_http_origin`] first (R-10-061), so a non-`http(s)` input is
/// a caller bug, not a value to pass through unchanged.
fn to_ws_origin(origin: &str) -> String {
    if let Some(rest) = origin.strip_prefix("https://") {
        format!("wss://{rest}")
    } else if let Some(rest) = origin.strip_prefix("http://") {
        format!("ws://{rest}")
    } else {
        unreachable!("origin validated by herdr_relay_proto::handle::is_absolute_http_origin")
    }
}

/// The fixed R-10-064 link `error` class text for a failed connect: a class,
/// never the raw error, whose text can embed the dialed URL (and with it the
/// routing handle, R-10-065).
fn link_error_class(error: &ConnectError) -> &'static str {
    match error {
        ConnectError::Timeout => "i/o timeout",
        ConnectError::Connect(_) | ConnectError::Io(_) => "connect failed",
        ConnectError::UnexpectedRegistrationReply(_) => "registration rejected",
        ConnectError::Noise(_) => "handshake failed",
    }
}

/// `ReconnectBackoff::next_wait`'s jitter source, `[-1.0, 1.0]`.
fn jitter_unit() -> f64 {
    rand::random::<f64>() * 2.0 - 1.0
}

// ---------------------------------------------------------------------------
// The control handler (R-10-063, R-10-064)
// ---------------------------------------------------------------------------

/// The control-plane handler: answers every R-10-064 command from
/// `HostState` only, with no relay round trip inside a request (R-10-063).
struct HostCore {
    state: Arc<Mutex<HostState>>,
}

impl control::Handler for HostCore {
    fn handle(&self, command: Command) -> Result<serde_json::Value, control::ErrorCode> {
        match command {
            Command::Status => Ok(status_value(&mut lock(&self.state))),
            Command::OpenPairing => {
                open_pairing(&self.state)?;
                Ok(status_value(&mut lock(&self.state)))
            }
            Command::ClosePairing => {
                let mut state = lock(&self.state);
                if let Some(open) = state.open_pairing.take() {
                    // R-13-022/R-13-029: the phrase, the handle and the
                    // registration die together. Aborting the task drops the
                    // socket, which ends the relay-side registration.
                    open.task.abort();
                    (state.log)("herdr-relay: pairing closed");
                }
                Ok(serde_json::json!({}))
            }
            Command::Revoke { device_id } => revoke_one(&self.state, &device_id),
            Command::RevokeAll => revoke_all(&self.state),
            Command::Stop => {
                let mut state = lock(&self.state);
                // R-10-064: `stop` MUST NOT clear a pairing and MUST NOT exit
                // the process; `stopped` is a state (R-31-16-24).
                state.stopped = true;
                state.link = control::LinkStatus {
                    state: control::LinkState::Stopped,
                    attempt: 0,
                    error: None,
                };
                // Serving loops select on this channel and close their
                // sockets; registration loops park until `open_pairing`
                // clears it.
                let _ = state.stop_tx.send(true);
                (state.log)("herdr-relay: stopped");
                Ok(serde_json::json!({}))
            }
        }
    }
}

fn status_value(state: &mut HostState) -> serde_json::Value {
    serde_json::to_value(build_status(state)).expect("control::Status always serializes")
}

/// The R-10-064 status object. `pairing` is destroyed the moment the phrase
/// lifetime has elapsed (R-13-022) or the third failed attempt has spent the
/// phrase (R-13-023), and its credential fields stay `null` until the relay
/// accepted the registration (R-13-035 step 3).
fn build_status(state: &mut HostState) -> control::Status {
    let now = Instant::now();
    if state
        .open_pairing
        .as_mut()
        .is_some_and(|open| !open.session.is_live(now))
        && let Some(open) = state.open_pairing.take()
    {
        open.task.abort();
    }
    let pairing = state.open_pairing.as_mut().map(|open| {
        let registered = open.registered;
        control::PairingStatus {
            registered,
            uri: if registered {
                open.session.pairing_uri(now).map(str::to_owned)
            } else {
                None
            },
            phrase: if registered {
                open.session.phrase_display(now)
            } else {
                None
            },
            handle: if registered {
                open.session.handle(now).map(|handle| handle.encode())
            } else {
                None
            },
            expires_in_s: PHRASE_LIFETIME.as_secs().saturating_sub(
                tokio::time::Instant::now()
                    .saturating_duration_since(open.minted_at)
                    .as_secs(),
            ),
        }
    });
    let connected_id = state
        .active
        .as_ref()
        .and_then(|active| active.device_id.as_deref());
    let devices = state
        .store
        .devices()
        .iter()
        .map(|device| control::DeviceRow {
            device_id: device.device_id.clone(),
            device_name: device.device_name.clone(),
            platform: device.platform,
            os_version: device.os_version.clone(),
            fingerprint: device.fingerprint(),
            paired_at: device.paired_at.clone(),
            last_seen: device.last_seen.clone(),
            connected: connected_id == Some(device.device_id.as_str()),
        })
        .collect();
    control::Status {
        relay_origin: state.relay_origin.clone(),
        link: state.link.clone(),
        pairing,
        devices,
    }
}

/// `open_pairing` (R-10-064): idempotent while a pairing is open; mints a
/// `PairingSession`, leaves the `stopped` state, and spawns the background
/// task that runs the `/host/<handle>` registration on the R-10-014 ladder
/// and waits out the R-13-022 window for the Device's handshake.
fn open_pairing(shared: &Arc<Mutex<HostState>>) -> Result<(), control::ErrorCode> {
    let mut state = lock(shared);
    let now = Instant::now();
    if state
        .open_pairing
        .as_mut()
        .is_some_and(|open| open.session.is_live(now))
    {
        return Ok(());
    }
    // An expired pairing is replaced, not revived (R-13-022).
    if let Some(open) = state.open_pairing.take() {
        open.task.abort();
    }
    let words = wordlist::word_refs(&state.words);
    let session = match PairingSession::new(state.relay_origin.clone(), &words, now) {
        Ok(session) => session,
        Err(_err) => {
            // The word list was validated at startup, so this is the random
            // source or an over-long configured origin (R-11-141). R-10-064
            // defines no internal-error code; `bad_request` is the closest.
            (state.log)("herdr-relay: minting a pairing failed");
            return Err(control::ErrorCode::BadRequest);
        }
    };
    if state.stopped {
        // R-10-064: `open_pairing` leaves the stopped state.
        state.stopped = false;
        state.link = link_idle();
        let _ = state.stop_tx.send(false);
    }
    let task = tokio::spawn(pairing_loop(Arc::clone(shared)));
    state.open_pairing = Some(OpenPairing {
        session,
        minted_at: tokio::time::Instant::now(),
        registered: false,
        task,
    });
    (state.log)("herdr-relay: pairing open");
    Ok(())
}

/// `revoke <device_id>` (R-13-053 steps 1-3): remove the entry, drop its
/// registration, close its live session. `not_found` for an unknown id
/// (R-10-064).
fn revoke_one(
    shared: &Arc<Mutex<HostState>>,
    device_id: &str,
) -> Result<serde_json::Value, control::ErrorCode> {
    let mut state = lock(shared);
    let removed = match state.store.revoke(device_id) {
        Ok(removed) => removed,
        Err(_err) => {
            (state.log)("herdr-relay: updating the paired-device list failed");
            return Err(control::ErrorCode::BadRequest);
        }
    };
    if removed.is_none() {
        return Err(control::ErrorCode::NotFound);
    }
    // R-13-053 steps 2-3. The order matters: the registration task owns the
    // session's socket, so aborting it first would drop the socket before
    // the `revoked` error and the 4004 close could be sent. A live session
    // is closed through the registry and its loop then ends itself (the
    // store check at the top of every iteration); only a parked loop (mid
    // backoff, or waiting on a handshake) is aborted outright.
    let session_live = state
        .active
        .as_ref()
        .is_some_and(|active| active.device_id.as_deref() == Some(device_id));
    state.registry.close_for_revocation(&RevokeResult {
        revoked: vec![device_id.to_owned()],
        all: false,
    });
    if session_live {
        state.active = None;
        if !state.stopped {
            state.link = link_idle();
        }
    } else if let Some(task) = state.registrations.remove(device_id) {
        task.abort();
    }
    (state.log)("herdr-relay: a paired device was revoked");
    Ok(serde_json::json!({}))
}

/// `revoke_all` (R-13-056): clear the list, close every session, destroy
/// every handle, rotate the Host keypair. The open pairing goes with them:
/// its in-flight handshake would pin the pre-rotation key, so no credential
/// minted under the old identity survives.
fn revoke_all(shared: &Arc<Mutex<HostState>>) -> Result<serde_json::Value, control::ErrorCode> {
    let mut state = lock(shared);
    let cleared = match state.store.clear_all() {
        Ok(cleared) => cleared,
        Err(_err) => {
            (state.log)("herdr-relay: clearing the paired-device list failed");
            return Err(control::ErrorCode::BadRequest);
        }
    };
    state.registry.close_for_revocation(&RevokeResult {
        revoked: cleared
            .iter()
            .map(|device| device.device_id.clone())
            .collect(),
        all: true,
    });
    // Same ordering as `revoke_one`: the active session's own loop is left
    // to deliver the `revoked` error and end itself on the cleared store;
    // every parked loop is aborted now (R-13-056 steps 2-3).
    let active_id = state
        .active
        .as_ref()
        .and_then(|active| active.device_id.clone());
    for (device_id, task) in state.registrations.drain() {
        if Some(&device_id) != active_id.as_ref() {
            task.abort();
        }
    }
    if let Some(open) = state.open_pairing.take() {
        open.task.abort();
    }
    state.active = None;
    if !state.stopped {
        state.link = link_idle();
    }
    match keys::rotate(&state.paths) {
        Ok(keypair) => {
            state.keypair = keypair;
            (state.log)("herdr-relay: the host keypair rotated");
        }
        Err(_err) => {
            // The list is already gone, so no live pairing depends on the old
            // key; the next start regenerates instead. Not worth failing the
            // command over.
            (state.log)("herdr-relay: rotating the host keypair failed");
        }
    }
    (state.log)("herdr-relay: every paired device was revoked");
    Ok(serde_json::json!({}))
}

/// The `HostState` half of a Device-sent `revoke_device` (R-11-063,
/// R-11-064), after `Bridge::revoke_device_request` updated the store,
/// rotated the on-disk keypair for `all: true`, and signalled the registry.
/// Same ordering as `revoke_one`/`revoke_all`: the active session's own
/// loop delivers the `revoked` error, the 4004 close and `release_active`,
/// then ends itself on the cleared store; every parked loop for a revoked
/// entry is aborted now (R-13-053 step 2, R-13-056 step 3), so a revoked
/// Device cannot rejoin through a still-registered handle. For `all: true`
/// the open pairing goes too (its handshake would pin the pre-rotation key)
/// and the in-memory keypair is reloaded to match the rotated one on disk.
fn finish_wire_revoke(state: &mut HostState, result: &RevokeResult) {
    let active_id = state
        .active
        .as_ref()
        .and_then(|active| active.device_id.clone());
    if result.all {
        for (device_id, task) in state.registrations.drain() {
            if Some(&device_id) != active_id.as_ref() {
                task.abort();
            }
        }
        if let Some(open) = state.open_pairing.take() {
            open.task.abort();
        }
        match keys::load_or_generate(&state.paths) {
            Ok(keypair) => state.keypair = keypair,
            Err(_err) => (state.log)("herdr-relay: reloading the host keypair failed"),
        }
        (state.log)("herdr-relay: every paired device was revoked");
    } else {
        for device_id in &result.revoked {
            if Some(device_id) != active_id.as_ref()
                && let Some(task) = state.registrations.remove(device_id)
            {
                task.abort();
            }
        }
        (state.log)("herdr-relay: a paired device was revoked");
    }
}

// ---------------------------------------------------------------------------
// Registration loops (R-10-068)
// ---------------------------------------------------------------------------

/// Starts the `Noise_KK` registration loop for one stored entry and records
/// its task for `revoke`/`revoke_all`. Returns `false` for an entry with an
/// empty or malformed handle (unservable, R-10-068's skip rule).
fn spawn_registration(shared: &Arc<Mutex<HostState>>, device_id: &str) -> bool {
    let usable = {
        lock(shared)
            .store
            .find(device_id)
            .is_some_and(|entry| entry.handle.parse::<Handle>().is_ok())
    };
    if !usable {
        return false;
    }
    let task = {
        let state = Arc::clone(shared);
        let device_id = device_id.to_owned();
        tokio::spawn(async move { registration_loop(state, device_id).await })
    };
    lock(shared)
        .registrations
        .insert(device_id.to_owned(), task);
    true
}

/// Observes agent status while a registered socket waits for a Device.
async fn idle_handshake(
    mut socket: WsStream,
    state: &Arc<Mutex<HostState>>,
    host_id: &str,
    setup: HandshakeSetup,
) -> Result<(WsStream, Transport, [u8; 32]), ConnectError> {
    let (wake_tx, mut wake_rx) = tokio::sync::mpsc::unbounded_channel();
    let (client, config, identity, observed, log) = {
        let host = lock(state);
        (
            host.client.clone(),
            host.relay_config.clone(),
            HostIdentity {
                host_id: host_id.to_owned(),
                host_name: host.host_name.clone(),
            },
            host.agent_status_observed.clone(),
            host.log.clone(),
        )
    };
    let observer = tokio::task::spawn_blocking(move || {
        let mut bridge = Bridge::new(client.clone(), identity, config);
        bridge.agent_status_observed = observed;
        let mut subscription = open_subscription(&client, &bridge);
        while !wake_tx.is_closed() {
            let mut resubscribe = false;
            if let Some((rx, slot)) = &subscription {
                let result = bridge.run_until(
                    rx,
                    Instant::now() + Duration::from_millis(50),
                    slot,
                    |message| {
                        if needs_push_wake(&message) {
                            let _ = wake_tx.send(());
                        }
                    },
                    || resubscribe = true,
                );
                if result.is_err() || resubscribe {
                    subscription = None;
                }
            } else {
                std::thread::sleep(Duration::from_millis(200));
                if !wake_tx.is_closed() {
                    subscription = open_subscription(&client, &bridge);
                }
            }
        }
        // ponytail: the old IPC reader exits on its next event. Hand over the
        // subscription if idle/session transitions leave too many idle readers.
    });
    let first = loop {
        tokio::select! {
            frame = socket.next() => {
                match frame {
                    Some(Ok(WsMessage::Binary(bytes))) => break Ok(bytes),
                    Some(Ok(WsMessage::Ping(_))) => {
                        if let Err(error) = socket.flush().await {
                            break Err(ConnectError::Io(error));
                        }
                    }
                    Some(Ok(WsMessage::Close(_))) | None => break Err(ConnectError::Io(
                        tokio_tungstenite::tungstenite::Error::ConnectionClosed,
                    )),
                    Some(Err(error)) => break Err(ConnectError::Io(error)),
                    // Push errors are fire-and-forget. No text enters Noise.
                    Some(Ok(_)) => {}
                }
            }
            Some(()) = wake_rx.recv() => send_push_wake(&mut socket, &log).await,
        }
    };
    drop(wake_rx);
    let _ = observer.await;
    relay::handshake_after_first(socket, setup, &first?).await
}

fn needs_push_wake(message: &Message) -> bool {
    matches!(message, Message::AgentStatus(status) if matches!(
        status.status,
        herdr_relay_proto::messages::AgentStatusKind::Blocked
            | herdr_relay_proto::messages::AgentStatusKind::Done
    ))
}

async fn send_push_wake(socket: &mut WsStream, log: &Log) {
    if socket
        .send(WsMessage::Text(r#"{"type":"push_wake"}"#.into()))
        .await
        .is_err()
    {
        log("herdr-relay: push wake send failed");
    }
}

/// One entry's `Noise_KK` registration loop (R-10-068): register on
/// `/host/<handle>` with the entry's pinned key (R-13-037), serve the session
/// when a Device completes the handshake, and reconnect on the R-10-014
/// ladder. Ends when the entry leaves the store (revoke) or the task is
/// aborted (shutdown).
async fn registration_loop(state: Arc<Mutex<HostState>>, device_id: String) {
    let (ws_origin, relay_config, private_key, handle, remote_key, host_id) = {
        let host = lock(&state);
        let Some(entry) = host.store.find(&device_id) else {
            return;
        };
        let Ok(handle) = entry.handle.parse::<Handle>() else {
            (host.log)("herdr-relay: a stored entry has an unusable routing handle; skipped");
            return;
        };
        (
            host.ws_origin.clone(),
            host.relay_config.clone(),
            host.keypair.private,
            handle,
            entry.static_public_key,
            entry.host_id.clone(),
        )
    };
    let mut backoff = ReconnectBackoff::new(&relay_config);
    let mut stop_rx = lock(&state).stop_tx.subscribe();
    loop {
        // A revoked entry's loop dies here even if the abort has not landed.
        if lock(&state).store.find(&device_id).is_none() {
            return;
        }
        // R-10-064: `stopped` suspends every registration loop.
        if !wait_until_running(&mut stop_rx).await {
            return;
        }
        // Two steps on purpose (R-10-068): `register_host` is bounded by the
        // connect timeout, `handshake_on` is not, so a registered handle is
        // held for as long as no phone arrives; only `stop`, a revocation or a
        // socket error ends the wait. `connect_host` would fold the idle wait
        // into its 30 s timeout and drop the registration every 30 s.
        let registered = tokio::select! {
            _ = stop_rx.changed() => continue,
            result = relay::register_host(&ws_origin, handle) => result,
        };
        let socket = match registered {
            Ok(socket) => {
                set_idle(&state);
                socket
            }
            Err(err) => {
                set_offline(&state, backoff.attempt_number(), link_error_class(&err));
                let wait = backoff.next_wait(jitter_unit());
                tokio::select! {
                    _ = stop_rx.changed() => {}
                    _ = tokio::time::sleep(wait) => {}
                }
                continue;
            }
        };
        let connected = tokio::select! {
            _ = stop_rx.changed() => continue,
            result = idle_handshake(
                socket,
                &state,
                &host_id,
                HandshakeSetup::Reconnect {
                    local_private_key: private_key,
                    remote_static_public_key: remote_key,
                },
            ) => result,
        };
        let (mut socket, mut transport, _device_static) = match connected {
            Ok(ok) => ok,
            Err(err) => {
                // The relay dropped a registered socket, or a phone failed its
                // handshake: re-register on the ladder.
                set_offline(&state, backoff.attempt_number(), link_error_class(&err));
                let wait = backoff.next_wait(jitter_unit());
                tokio::select! {
                    _ = stop_rx.changed() => {}
                    _ = tokio::time::sleep(wait) => {}
                }
                continue;
            }
        };
        // R-10-069: one active Device per Host, across every registration.
        let Some(_claim) = claim_active(&state, Some(device_id.clone()), handle) else {
            let _ = close_socket(&mut socket, CloseCode::HostInUse).await;
            let wait = backoff.next_wait(jitter_unit());
            tokio::select! {
                _ = stop_rx.changed() => {}
                _ = tokio::time::sleep(wait) => {}
            }
            continue;
        };
        backoff.record_connected(Instant::now());
        {
            let mut host = lock(&state);
            if host.store.touch_last_seen(&device_id).is_err() {
                (host.log)("herdr-relay: updating last_seen failed");
            }
        }
        (lock(&state).log)("herdr-relay: a device connected");
        // R-11-130: `host_info` is the first application frame, `paired:
        // true` for a returning Device (R-10-068).
        let mut seq = SequenceCounter::new();
        let (herdr_version, herdr_protocol, host_name) = {
            let host = lock(&state);
            (
                host.herdr_version.clone(),
                host.herdr_protocol,
                host.host_name.clone(),
            )
        };
        let theme = crate::theme::Watcher::new();
        let hello = Message::HostInfo(HostInfo {
            protocol: 1,
            host_id: host_id.clone(),
            host_name: host_name.clone(),
            herdr_version,
            herdr_protocol,
            paired: true,
            theme: theme.current.clone(),
        });
        if send_message(&mut socket, &mut transport, &mut seq, &hello, None)
            .await
            .is_err()
        {
            backoff.record_disconnected(Instant::now());
            continue;
        }
        // R-13-049: host_info is outbound traffic after the handshake timestamp.
        {
            let mut host = lock(&state);
            if host.store.touch_last_seen(&device_id).is_err() {
                (host.log)("herdr-relay: updating last_seen failed");
            }
        }
        let identity = HostIdentity {
            host_id: host_id.clone(),
            host_name: host_name.clone(),
        };
        serve_session(
            &state,
            identity,
            socket,
            transport,
            seq,
            handle,
            device_id.clone(),
            Reassembler::new(),
            theme,
        )
        .await;
        backoff.record_disconnected(Instant::now());
    }
}

/// The open pairing's registration loop (R-10-068): register on
/// `/host/<handle>` until the relay accepts (R-10-064's `registered`), then
/// wait out the phrase's R-13-022 window for the Device's `Noise_XXpsk0`
/// handshake (R-13-035). On success the session is served in place; the
/// entry's `Noise_KK` loop starts when that session ends. On expiry
/// (R-13-022) or on the third failed handshake attempt (R-13-023) the
/// phrase, the handle and the registration are destroyed, and no
/// replacement is minted: the pane waits for `p`.
async fn pairing_loop(state: Arc<Mutex<HostState>>) {
    let (ws_origin, relay_config, private_key) = {
        let host = lock(&state);
        (
            host.ws_origin.clone(),
            host.relay_config.clone(),
            host.keypair.private,
        )
    };
    let mut backoff = ReconnectBackoff::new(&relay_config);
    let mut stop_rx = lock(&state).stop_tx.subscribe();
    loop {
        let now = Instant::now();
        let (handle, psk, minted_at) = {
            let mut host = lock(&state);
            let Some(open) = host.open_pairing.as_mut() else {
                return; // close_pairing or a successful enrolment ended it
            };
            match (open.session.handle(now), open.session.psk_for(now)) {
                (Some(handle), Some(psk)) => (handle, psk, open.minted_at),
                // R-13-022/R-13-023: the phrase lifetime elapsed, or the
                // third failed attempt spent the phrase. Destroy the
                // pairing; no replacement is minted (the pane waits for
                // `p`).
                _ => {
                    let spent = host
                        .open_pairing
                        .as_ref()
                        .is_some_and(|open| open.session.is_spent());
                    if let Some(open) = host.open_pairing.take() {
                        open.task.abort();
                    }
                    (host.log)(if spent {
                        "herdr-relay: pairing spent after three failed attempts"
                    } else {
                        "herdr-relay: pairing expired"
                    });
                    return;
                }
            }
        };
        if !wait_until_running(&mut stop_rx).await {
            return;
        }
        // R-11-113/R-11-120: a first-pairing registration carries
        // `"pairing": true`, so the relay applies the pairing window to
        // this handle. The `Noise_KK` loop keeps the plain frame.
        let registered = tokio::select! {
            _ = stop_rx.changed() => continue,
            result = relay::register_host_pairing(&ws_origin, handle) => result,
        };
        let socket = match registered {
            Ok(socket) => {
                let mut host = lock(&state);
                if let Some(open) = host.open_pairing.as_mut()
                    && open.session.handle(now) == Some(handle)
                {
                    open.registered = true;
                    (host.log)("herdr-relay: pairing registered with the relay");
                }
                socket
            }
            Err(err) => {
                // R-10-064: the registration runs on the R-10-014 ladder
                // until it succeeds or the pairing expires.
                set_offline(&state, backoff.attempt_number(), link_error_class(&err));
                let wait = backoff.next_wait(jitter_unit());
                tokio::select! {
                    _ = stop_rx.changed() => {}
                    _ = tokio::time::sleep(wait) => {}
                }
                continue;
            }
        };
        backoff.record_connected(Instant::now());

        // R-13-022: the Device's handshake must complete inside the phrase's
        // remaining lifetime.
        let deadline = minted_at + PHRASE_LIFETIME;
        let handshake = tokio::select! {
            _ = stop_rx.changed() => continue,
            result = tokio::time::timeout_at(
                deadline,
                relay::handshake_on(socket, HandshakeSetup::Pairing { local_private_key: private_key, psk }),
            ) => result,
        };
        let (mut socket, transport, device_static) = match handshake {
            Ok(Ok(done)) => done,
            Ok(Err(_err)) => {
                // R-13-023: one failed attempt against the live phrase; the
                // handshake's own socket went down with it. The third
                // failure spends the phrase and the handle with no
                // replacement, and the next pass of this loop destroys the
                // pairing.
                let mut host = lock(&state);
                if let Some(open) = host.open_pairing.as_mut()
                    && open.session.handle(now) == Some(handle)
                {
                    open.session.record_failed_attempt(now);
                }
                continue;
            }
            Err(_elapsed) => {
                // The window elapsed with no completed handshake (R-13-022).
                let mut host = lock(&state);
                if host
                    .open_pairing
                    .as_mut()
                    .is_some_and(|open| open.session.handle(now) == Some(handle))
                {
                    host.open_pairing = None;
                    (host.log)("herdr-relay: pairing expired");
                }
                return;
            }
        };

        // R-10-069: one active Device per Host. The phrase is not consumed by
        // a refused Device, so the loop keeps serving it.
        let Some(_claim) = claim_active(&state, None, handle) else {
            let _ = close_socket(&mut socket, CloseCode::HostInUse).await;
            continue;
        };
        match serve_new_pairing(&state, socket, transport, handle, device_static, deadline).await {
            Some(device_id) => {
                // R-13-035 step 9: the entry's `Noise_KK` registration starts
                // once the pairing session's own socket is closed, so the
                // handle is free for it (R-11-123).
                spawn_registration(&state, &device_id);
                return;
            }
            None => continue,
        }
    }
}

/// Parks while the bridge is stopped (R-10-064's `stop`). Returns `false`
/// when the bridge is shutting down (the watch sender dropped).
async fn wait_until_running(stop_rx: &mut tokio::sync::watch::Receiver<bool>) -> bool {
    while *stop_rx.borrow() {
        if stop_rx.changed().await.is_err() {
            return false;
        }
    }
    true
}

/// Sets the link's offline state, unless a session is live (a serving
/// session outranks another registration's failure) or the bridge stopped.
fn set_offline(state: &Arc<Mutex<HostState>>, attempt: u32, class: &'static str) {
    let mut host = lock(state);
    if host.active.is_none() && !host.stopped {
        host.link = control::LinkStatus {
            state: control::LinkState::Offline,
            attempt,
            error: Some(class.to_owned()),
        };
    }
}

/// The R-10-069 guard: claims the one active session, marking the link
/// connected. `device_id` is `None` for a pairing handshake until
/// `device_info` arrives (R-11-131).
fn claim_active(
    state: &Arc<Mutex<HostState>>,
    device_id: Option<String>,
    handle: Handle,
) -> Option<ActiveClaim> {
    let mut host = lock(state);
    if host.active.is_some() || host.stopped {
        return None;
    }
    host.active = Some(ActiveSession { device_id, handle });
    host.link = link_connected();
    Some(ActiveClaim {
        state: Arc::clone(state),
        handle,
    })
}

fn release_active(state: &Arc<Mutex<HostState>>, handle: Handle) {
    let mut host = lock(state);
    host.registry.unregister(handle);
    if !host
        .active
        .as_ref()
        .is_some_and(|active| active.handle == handle)
    {
        return;
    }
    host.active = None;
    host.link = if host.stopped {
        control::LinkStatus {
            state: control::LinkState::Stopped,
            attempt: 0,
            error: None,
        }
    } else {
        link_idle()
    };
}

/// A registration was accepted and waits for a phone: `idle`, unless a live
/// session (`connected` outranks it) or `stop` says otherwise.
fn set_idle(state: &Arc<Mutex<HostState>>) {
    let mut host = lock(state);
    if host.active.is_none() && !host.stopped {
        host.link = link_idle();
    }
}

// ---------------------------------------------------------------------------
// Serving one established session
// ---------------------------------------------------------------------------

/// Serves one completed pairing handshake (R-13-035 steps 7-10): `host_info`
/// first with a fresh UUIDv4 `host_id` (R-13-049) and `paired: false`, then
/// the mandatory `device_info` first frame (R-11-131/R-11-132), enrolment,
/// and the dispatch loop. Returns the new entry's device id only when the
/// Device enrolled; every earlier failure leaves the pairing open.
async fn serve_new_pairing(
    state: &Arc<Mutex<HostState>>,
    mut socket: WsStream,
    mut transport: Transport,
    handle: Handle,
    device_static: [u8; 32],
    deadline: tokio::time::Instant,
) -> Option<String> {
    // R-13-049: each entry carries its own host_id, minted at pairing time.
    let host_id = uuid::Uuid::new_v4().to_string();
    let (herdr_version, herdr_protocol, host_name) = {
        let host = lock(state);
        (
            host.herdr_version.clone(),
            host.herdr_protocol,
            host.host_name.clone(),
        )
    };
    let mut seq = SequenceCounter::new();
    let theme = crate::theme::Watcher::new();
    let hello = Message::HostInfo(HostInfo {
        protocol: 1,
        host_id: host_id.clone(),
        host_name: host_name.clone(),
        herdr_version,
        herdr_protocol,
        paired: false,
        theme: theme.current.clone(),
    });
    // R-11-131/R-11-132: the Device's first application frame MUST be
    // `device_info`; anything else is a fatal protocol mismatch.
    let mut reassembler = Reassembler::new();
    let mut stop_rx = lock(state).stop_tx.subscribe();
    if *stop_rx.borrow() {
        return None;
    }
    // R-13-022/R-10-064: enrollment shares the phrase deadline and stop signal.
    let first_frame = tokio::select! {
        biased;
        _ = stop_rx.changed() => return None,
        _ = tokio::time::sleep_until(deadline) => {
            let mut host = lock(state);
            if host.open_pairing.as_ref().is_some_and(|open| {
                open.minted_at + PHRASE_LIFETIME == deadline
            }) {
                host.open_pairing = None;
            }
            return None;
        }
        frame = async {
            if send_message(&mut socket, &mut transport, &mut seq, &hello, None).await.is_err() {
                return None;
            }
            Some(relay::receive_frame(&mut socket, &mut transport, &mut reassembler).await)
        } => frame?,
    };
    let info = match first_frame {
        Ok(bytes) => match decode_message(&bytes) {
            Ok(Message::DeviceInfo(info)) => info,
            _ => {
                let message = Message::Error(ErrorMessage {
                    code: WireErrorCode::ProtocolMismatch,
                    message: "expected device_info".to_owned(),
                    fatal: true,
                });
                let _ = send_message(&mut socket, &mut transport, &mut seq, &message, None).await;
                let _ = close_socket(&mut socket, CloseCode::ProtocolError).await;
                return None;
            }
        },
        Err(_err) => {
            return None;
        }
    };

    let device_id = info.device_id.clone();
    let enrolled = {
        let mut host = lock(state);
        // R-13-022/R-13-035: reject closed, expired, or replaced pairings before persistence.
        if host.stopped
            || tokio::time::Instant::now() >= deadline
            || !host
                .open_pairing
                .as_mut()
                .is_some_and(|open| open.session.handle(Instant::now()) == Some(handle))
        {
            return None;
        }
        // R-13-053: stop the obsolete registration before replacing its pinned key.
        if let Some(task) = host.registrations.remove(&device_id) {
            task.abort();
        }
        let added = host.store.add(
            host_id.clone(),
            handle.encode(),
            info.device_id,
            info.device_name,
            info.platform,
            info.os_version,
            device_static,
        );
        match added {
            Ok(()) => {
                // R-13-035 step 10, R-13-029: a successful enrolment destroys
                // the phrase. Take the pairing only if it is still the one
                // this handshake came from.
                if host
                    .open_pairing
                    .as_mut()
                    .is_some_and(|open| open.session.handle(Instant::now()) == Some(handle))
                {
                    host.open_pairing = None;
                }
                if let Some(active) = host.active.as_mut()
                    && active.handle == handle
                {
                    active.device_id = Some(device_id.clone());
                }
                (host.log)("herdr-relay: a phone paired");
                true
            }
            Err(_err) => {
                (host.log)("herdr-relay: storing a paired device failed");
                false
            }
        }
    };
    if !enrolled {
        // R-13-053: a failed save retains the old entry and its registration.
        spawn_registration(state, &device_id);
        return None;
    }
    let identity = HostIdentity { host_id, host_name };
    serve_session(
        state,
        identity,
        socket,
        transport,
        seq,
        handle,
        device_id.clone(),
        reassembler,
        theme,
    )
    .await;
    Some(device_id)
}

// R-13-053/R-13-037: validate identity and register atomically before dispatch.
fn register_session(
    state: &Arc<Mutex<HostState>>,
    identity: &HostIdentity,
    handle: Handle,
    device_id: &str,
) -> Option<tokio::sync::oneshot::Receiver<CloseReason>> {
    let host = lock(state);
    if host.stopped
        || !host.store.find(device_id).is_some_and(|entry| {
            entry.host_id == identity.host_id && entry.handle.parse::<Handle>().ok() == Some(handle)
        })
    {
        return None;
    }
    Some(host.registry.register(handle, Some(device_id.to_owned())))
}

/// The dispatch loop every established session runs (pairing or reconnect):
/// inbound frames go to the blocking `watch::Bridge` thread, outbound replies
/// and live `pane_frame`s come back over `out_rx`. Ends on a drop, a
/// `disconnect`, a revocation close (R-13-053 step 3, R-11-065), or `stop`
/// (R-10-064). Unregisters and releases the guard on every exit path.
#[allow(clippy::too_many_arguments)]
async fn serve_session(
    state: &Arc<Mutex<HostState>>,
    identity: HostIdentity,
    mut socket: WsStream,
    mut transport: Transport,
    mut seq: SequenceCounter,
    handle: Handle,
    device_id: String,
    mut reassembler: Reassembler,
    theme: crate::theme::Watcher,
) {
    let Some(mut close_rx) = register_session(state, &identity, handle, &device_id) else {
        return;
    };
    let mut stop_rx = lock(state).stop_tx.subscribe();
    let (client, relay_config) = {
        let host = lock(state);
        (host.client.clone(), host.relay_config.clone())
    };
    let (req_tx, req_rx) = std_mpsc::channel::<BridgeRequest>();
    let (out_tx, mut out_rx) = tokio::sync::mpsc::unbounded_channel::<(Message, Option<String>)>();
    let session_active = Arc::new(std::sync::atomic::AtomicBool::new(true));
    let thread = {
        let state = Arc::clone(state);
        let device_id = device_id.clone();
        let session_active = Arc::clone(&session_active);
        std::thread::spawn(move || {
            bridge_thread(
                client,
                identity,
                relay_config,
                req_rx,
                out_tx,
                state,
                device_id,
                theme,
                session_active,
            );
        })
    };

    loop {
        tokio::select! {
            incoming = relay::receive_frame(&mut socket, &mut transport, &mut reassembler) => {
                match incoming {
                    Ok(bytes) => {
                        // R-13-049: every transport message moves last_seen
                        // (no throttling, by the rule's own text).
                        {
                            let mut host = lock(state);
                            if host.store.touch_last_seen(&device_id).is_err() {
                                (host.log)("herdr-relay: updating last_seen failed");
                            }
                        }
                        match dispatch_incoming(&bytes, &req_tx) {
                            DispatchOutcome::Pong(corr) => {
                                let pong = Message::Pong(herdr_relay_proto::messages::Pong {});
                                if send_message(&mut socket, &mut transport, &mut seq, &pong, corr).await.is_err() {
                                    break;
                                }
                            }
                            // A second `device_info` mid-session is ignored:
                            // R-11-131 names only the first frame.
                            DispatchOutcome::Continue | DispatchOutcome::DeviceInfo => {}
                            DispatchOutcome::Disconnect => {
                                cancel_held_before_close(&req_tx).await;
                                if let Ok(first) = out_rx.try_recv() {
                                    for (message, corr) in drain_outgoing(first, &mut out_rx) {
                                        if send_message(&mut socket, &mut transport, &mut seq, &message, corr).await.is_err() {
                                            break;
                                        }
                                    }
                                }
                                break;
                            }
                            DispatchOutcome::Error(_message) => {
                                (lock(state).log)(
                                    "herdr-relay: a malformed frame ended a device session",
                                );
                                break;
                            }
                        }
                    }
                    Err(_err) => break,
                }
            }
            outgoing = out_rx.recv() => {
                let Some(first) = outgoing else { break };
                let mut failed = false;
                for (message, corr) in drain_outgoing(first, &mut out_rx) {
                    if send_message(&mut socket, &mut transport, &mut seq, &message, corr).await.is_err() {
                        failed = true;
                        break;
                    }
                    if needs_push_wake(&message) {
                        let log = lock(state).log.clone();
                        send_push_wake(&mut socket, &log).await;
                    }
                }
                if failed { break; }
                let mut host = lock(state);
                if host.store.touch_last_seen(&device_id).is_err() {
                    (host.log)("herdr-relay: updating last_seen failed");
                }
            }
            reason = &mut close_rx => {
                // R-13-053 step 3, R-11-065: tell the Device why, then close
                // with 4004 (R-11-121). One SequenceCounter serves the whole
                // session (R-11-033). A reply the bridge thread queued before
                // the close signal (a self-revoke's own `revoke_result`) goes
                // out first: the fatal error MUST be the last frame (R-11-065),
                // and `select!` gives the close branch no ordering over `out_rx`.
                cancel_held_before_close(&req_tx).await;
                let batch = out_rx.try_recv().ok()
                    .map(|first| drain_outgoing(first, &mut out_rx))
                    .unwrap_or_default();
                for (message, corr) in batch {
                    if send_message(&mut socket, &mut transport, &mut seq, &message, corr)
                        .await
                        .is_err()
                    {
                        break;
                    }
                    if needs_push_wake(&message) {
                        let log = lock(state).log.clone();
                        send_push_wake(&mut socket, &log).await;
                    }
                }
                if matches!(reason, Ok(CloseReason::Revoked)) {
                    let message = Message::Error(ErrorMessage {
                        code: WireErrorCode::Revoked,
                        message: "This device has been revoked.".to_owned(),
                        fatal: true,
                    });
                    let _ = send_message(&mut socket, &mut transport, &mut seq, &message, None)
                        .await;
                }
                let _ = close_socket(&mut socket, CloseCode::Revoked).await;
                break;
            }
            _ = stop_rx.changed() => {
                // R-10-064's `stop`: every relay connection closes.
                cancel_held_before_close(&req_tx).await;
                if let Ok(first) = out_rx.try_recv() {
                    for (message, corr) in drain_outgoing(first, &mut out_rx) {
                        if send_message(&mut socket, &mut transport, &mut seq, &message, corr).await.is_err() {
                            break;
                        }
                    }
                }
                let _ = close_socket(&mut socket, CloseCode::Normal).await;
                break;
            }
        }
    }

    session_active.store(false, std::sync::atomic::Ordering::Release);
    drop(req_tx);
    let _ = thread.join();
    (lock(state).log)("herdr-relay: a device session ended");
}

async fn cancel_held_before_close(req_tx: &std_mpsc::Sender<BridgeRequest>) {
    let (done_tx, done_rx) = tokio::sync::oneshot::channel();
    if req_tx.send(BridgeRequest::CancelPending(done_tx)).is_ok() {
        // A closed receiver means the bridge thread already ended.
        let _ = done_rx.await;
    }
}

/// Closes the WebSocket with one of R-11-121's application close codes
/// (`4006` host_in_use, `4004` revoked, `4003` protocol_error).
async fn close_socket(socket: &mut WsStream, code: CloseCode) -> Result<(), ()> {
    socket
        .send(WsMessage::Close(Some(CloseFrame {
            code: WsCloseCode::from(code.code()),
            reason: String::new().into(),
        })))
        .await
        .map_err(|_| ())
}

// ---------------------------------------------------------------------------
// Frame dispatch (the watch::Bridge plumbing): every Device request the
// bridge answers, plus the `device_info` arm (R-11-131/R-11-132)
// ---------------------------------------------------------------------------

enum DispatchOutcome {
    Continue,
    Pong(Option<String>),
    Disconnect,
    /// R-11-131: a `device_info` frame was parsed. The pairing path reads
    /// the first one's payload through [`decode_message`] directly; a
    /// mid-session one is ignored, so this variant carries nothing.
    DeviceInfo,
    Error(String),
}

/// Parses one reassembled frame envelope into its application message.
fn decode_message(bytes: &[u8]) -> Result<Message, String> {
    let frame =
        Frame::from_json_bytes(bytes).map_err(|err| format!("parsing a frame failed: {err}"))?;
    frame
        .message()
        .map_err(|err| format!("decoding a message failed: {err}"))
}

fn dispatch_incoming(bytes: &[u8], req_tx: &std_mpsc::Sender<BridgeRequest>) -> DispatchOutcome {
    let frame = match Frame::from_json_bytes(bytes) {
        Ok(frame) => frame,
        Err(err) => return DispatchOutcome::Error(format!("parsing a frame failed: {err}")),
    };
    let corr = frame.corr.clone();
    let message = match frame.message() {
        Ok(message) => message,
        Err(err) => return DispatchOutcome::Error(format!("decoding a message failed: {err}")),
    };
    match message {
        Message::Ping(_) => return DispatchOutcome::Pong(corr),
        Message::TreeRequest(_) => {
            let _ = req_tx.send(BridgeRequest::TreeRequest(corr));
        }
        Message::WatchPane(request) => {
            let _ = req_tx.send(BridgeRequest::WatchPane(request, corr));
        }
        Message::SendInput(request) => {
            let _ = req_tx.send(BridgeRequest::SendInput(request, corr));
        }
        Message::ScrollRequest(request) => {
            let _ = req_tx.send(BridgeRequest::ScrollRequest(request, corr));
        }
        // R-11-050: `unwatch_pane` has no reply and no correlation.
        Message::UnwatchPane(request) => {
            let _ = req_tx.send(BridgeRequest::UnwatchPane(request));
        }
        Message::ActionListRequest(request) => {
            let _ = req_tx.send(BridgeRequest::ActionListRequest(request, corr));
        }
        Message::MarkSeen(request) => {
            let _ = req_tx.send(BridgeRequest::MarkSeen(request));
        }
        Message::HostAction(request) => {
            let _ = req_tx.send(BridgeRequest::HostAction(request, corr));
        }
        Message::DeviceListRequest(request) => {
            let _ = req_tx.send(BridgeRequest::DeviceListRequest(request, corr));
        }
        Message::RevokeDevice(request) => {
            let _ = req_tx.send(BridgeRequest::RevokeDevice(request, corr));
        }
        Message::DeviceInfo(_) => return DispatchOutcome::DeviceInfo,
        Message::Disconnect(_) => return DispatchOutcome::Disconnect,
        _ => {}
    }
    DispatchOutcome::Continue
}

async fn send_message(
    socket: &mut WsStream,
    transport: &mut Transport,
    seq: &mut SequenceCounter,
    message: &Message,
    corr: Option<String>,
) -> Result<(), String> {
    let frame = Frame::wrap(seq.advance(), corr, message)
        .map_err(|err| format!("building a {} frame failed: {err}", message.type_name()))?;
    let bytes = frame
        .to_json_bytes()
        .map_err(|err| format!("serializing a {} frame failed: {err}", message.type_name()))?;
    relay::send_frame(socket, transport, &bytes)
        .await
        .map_err(|err| format!("sending a {} frame failed: {err}", message.type_name()))
}

/// One inbound Device request, handed from the async WebSocket task to the
/// thread that owns the blocking `watch::Bridge`. Each carries the frame's
/// `corr` to echo on the reply, except `unwatch_pane`, which has no reply.
enum BridgeRequest {
    TreeRequest(Option<String>),
    WatchPane(WatchPane, Option<String>),
    SendInput(SendInput, Option<String>),
    ScrollRequest(ScrollRequest, Option<String>),
    UnwatchPane(UnwatchPane),
    MarkSeen(MarkSeen),
    ActionListRequest(ActionListRequest, Option<String>),
    HostAction(HostAction, Option<String>),
    DeviceListRequest(DeviceListRequest, Option<String>),
    RevokeDevice(RevokeDevice, Option<String>),
    CancelPending(tokio::sync::oneshot::Sender<()>),
}
fn coalesce_input(
    mut request: SendInput,
    corr: Option<String>,
    rx: &std_mpsc::Receiver<BridgeRequest>,
    pending: &mut Option<BridgeRequest>,
) -> (SendInput, Vec<Option<String>>) {
    let mut corrs = vec![corr];
    if request.line.is_some()
        && request.text.is_none()
        && request.keys.is_none()
        && request.defer.is_none()
    {
        while let Ok(next) = rx.try_recv() {
            match next {
                BridgeRequest::SendInput(newer, corr)
                    if newer.line.is_some()
                        && newer.text.is_none()
                        && newer.keys.is_none()
                        && newer.defer.is_none()
                        && newer.pane_id == request.pane_id =>
                {
                    request = newer;
                    corrs.push(corr);
                }
                other => {
                    *pending = Some(other);
                    break;
                }
            }
        }
    }
    (request, corrs)
}

fn reply_to_inputs(
    tx: &tokio::sync::mpsc::UnboundedSender<(Message, Option<String>)>,
    reply: Message,
    mut corrs: Vec<Option<String>>,
) {
    let last = corrs.pop();
    for corr in corrs {
        let _ = tx.send((reply.clone(), corr));
    }
    if let Some(corr) = last {
        let _ = tx.send((reply, corr));
    }
}

fn drain_outgoing(
    first: (Message, Option<String>),
    rx: &mut tokio::sync::mpsc::UnboundedReceiver<(Message, Option<String>)>,
) -> Vec<(Message, Option<String>)> {
    let mut batch = vec![first];
    while let Ok(message) = rx.try_recv() {
        batch.push(message);
    }
    let mut panes = std::collections::HashSet::new();
    batch.reverse();
    batch.retain(|(message, _)| match message {
        Message::PaneFrame(frame) => panes.insert(frame.pane_id.clone()),
        _ => true,
    });
    batch.reverse();
    batch
}

/// Opens the session's one long-lived events subscription (R-10-011) with
/// [`Bridge::current_subscription_entries`] and starts its reader thread.
/// `None` when the connect or the `events.subscribe` handshake failed; what
/// that failure means for the Device is the caller's decision (session start
/// logs and carries on, the `watch_pane` retry sends the non-fatal error).
fn open_subscription(
    client: &HerdrClient,
    bridge: &Bridge<HerdrClient>,
) -> Option<(
    std_mpsc::Receiver<std::io::Result<String>>,
    LatestSlot<PaneFrame>,
)> {
    client
        .subscribe(bridge.current_subscription_entries())
        .ok()
        .map(|sub| (sub.spawn_reader(), LatestSlot::new()))
}

/// Owns the blocking `watch::Bridge` for this session's whole lifetime. Two
/// jobs, interleaved every tick: (1) drain at most one pending Device request
/// and answer it directly (the Herdr-backed requests are real synchronous
/// Herdr calls; `device_list_request` and `revoke_device` read and write the
/// shared `HostState` store instead, the same `Arc<Mutex<HostState>>` the
/// control commands `revoke_one`/`revoke_all` use); (2) drive
/// `Bridge::run_until` for a short window over the session's one long-lived
/// events subscription (R-10-011), opened at session start — not on the first
/// `watch_pane` — so `tree_update` and `agent_status` reach the Device from
/// the start (R-10-055, R-11-047) and the watched pane's `pane.updated`
/// events keep producing live `pane_frame` updates, exactly like
/// `tests/one_pane.rs`'s manual live-Herdr loop. `device_id` is this
/// session's connected Device (R-11-131), the one `device_list` reports
/// `connected: true` for.
#[allow(clippy::too_many_arguments)]
fn bridge_thread(
    client: HerdrClient,
    identity: HostIdentity,
    relay_config: RelayConfig,
    req_rx: std_mpsc::Receiver<BridgeRequest>,
    out_tx: tokio::sync::mpsc::UnboundedSender<(Message, Option<String>)>,
    state: Arc<Mutex<HostState>>,
    device_id: String,
    mut theme: crate::theme::Watcher,
    session_active: Arc<std::sync::atomic::AtomicBool>,
) {
    let mut bridge = Bridge::new(client.clone(), identity, relay_config);
    // Share the bridge process's one observed-stamp map (see `HostState`)
    // into this session's Bridge in place of its fresh per-session one.
    bridge.agent_status_observed = lock(&state).agent_status_observed.clone();
    bridge.input_lines = lock(&state).input_lines.clone();
    bridge.session_active = Some(session_active);
    // R-10-011/R-10-055: the one long-lived events subscription opens at
    // session start, so tree updates and agent statuses flow before the first
    // `watch_pane`. A failed open is retried by the `watch_pane` arm below
    // (the historical open point), so a transient failure costs the live tree
    // only until the first watch.
    let mut subscription = open_subscription(&client, &bridge);
    if subscription.is_none() {
        (lock(&state).log)("herdr-relay: opening the herdr events subscription failed");
    }

    loop {
        let wait = if subscription.is_some() {
            Duration::from_millis(20)
        } else {
            Duration::from_millis(200)
        };
        // Every queued request is served before the subscription tick below, which
        // blocks up to 50 ms. Serving one request per tick capped the Device at
        // roughly 15 requests per second, so fast typing (one `send_input` per
        // keystroke) queued for seconds and the phone's acknowledgement deadline
        // passed (measured 2026-09-16: 12 frames per second reached Herdr while the
        // phone typed 28).
        let mut next = req_rx.recv_timeout(wait);
        let mut pending = None;
        loop {
            match next {
                Ok(BridgeRequest::TreeRequest(corr)) => match bridge.tree_snapshot() {
                    Ok(snapshot) => {
                        let _ = out_tx.send((Message::TreeSnapshot(snapshot), corr));
                    }
                    Err(err) => {
                        let mapped = crate::watch::map_watch_error(&err);
                        let _ = out_tx.send((Message::Error(mapped), corr));
                    }
                },
                Ok(BridgeRequest::WatchPane(request, corr)) => {
                    match bridge.watch_pane(request) {
                        Ok((ack, frame)) => {
                            let _ = out_tx.send((Message::WatchAck(ack), corr));
                            let _ = out_tx.send((Message::PaneFrame(frame), None));
                            // The subscription opened at session start stays the
                            // one long-lived connection (R-10-011): a watch or a
                            // watch switch opens no second one and re-reads
                            // nothing beyond `watch_pane`'s own §5.1 calls. Only a
                            // failed startup open is retried here, the historical
                            // open point.
                            if subscription.is_none() {
                                subscription = open_subscription(&client, &bridge);
                                if subscription.is_none() {
                                    // Fixed text only: the Herdr error text names
                                    // a socket path, which stays out of every log
                                    // and wire line this crate emits (AGENTS.md).
                                    let _ = out_tx.send((
                                        Message::Error(ErrorMessage {
                                            code: WireErrorCode::InternalError,
                                            message: "subscribing to pane updates failed"
                                                .to_owned(),
                                            fatal: false,
                                        }),
                                        None,
                                    ));
                                }
                            }
                        }
                        Err(err) => {
                            let mapped = crate::watch::map_watch_error(&err);
                            let _ = out_tx.send((Message::Error(mapped), corr));
                        }
                    }
                }
                Ok(BridgeRequest::SendInput(request, corr)) => {
                    if request.defer.is_some() {
                        for reply in bridge.handle_deferred_input(request, corr) {
                            let _ = out_tx.send(reply);
                        }
                    } else {
                        let (request, corrs) = coalesce_input(request, corr, &req_rx, &mut pending);
                        let pane_id = request.pane_id.clone();
                        let reply = bridge.send_input(request).unwrap_or(Message::SendInputAck(
                            herdr_relay_proto::messages::SendInputAck {
                                pane_id,
                                accepted: false,
                                queued: false,
                            },
                        ));
                        reply_to_inputs(&out_tx, reply, corrs);
                    }
                }
                Ok(BridgeRequest::CancelPending(done)) => {
                    bridge.cancel_pending_inputs();
                    for reply in bridge.take_input_replies() {
                        let _ = out_tx.send(reply);
                    }
                    let _ = done.send(());
                }
                Ok(BridgeRequest::ScrollRequest(request, corr)) => {
                    match bridge.scroll_request(request) {
                        Ok(response) => {
                            let _ = out_tx.send((Message::ScrollResponse(response), corr));
                        }
                        Err(err) => {
                            let mapped = crate::watch::map_watch_error(&err);
                            let _ = out_tx.send((Message::Error(mapped), corr));
                        }
                    }
                }
                Ok(BridgeRequest::UnwatchPane(request)) => {
                    // R-11-050: no reply. A stale `unwatch_pane` for another pane
                    // is a no-op. The subscription stays up either way: it carries
                    // the session-long `tree_update`/`agent_status` flow
                    // (R-10-011), not just the watched pane's frames — those stop
                    // because the subscription-line handler ignores every pane
                    // that is not the watched one (R-01-007, R-02-013).
                    bridge.unwatch_pane(request);
                }
                Ok(BridgeRequest::MarkSeen(request)) => {
                    // R-10-072: log only the call count, never the target.
                    (lock(&state).log)("herdr-relay: mark_seen calls=1");
                    if let Err(err) = bridge.mark_seen(request) {
                        let mapped = crate::watch::map_watch_error(&err);
                        let _ = out_tx.send((Message::Error(mapped), None));
                    }
                }
                Ok(BridgeRequest::ActionListRequest(request, corr)) => {
                    match bridge.action_list_request(request) {
                        Ok(reply) => {
                            let _ = out_tx.send((reply, corr));
                        }
                        Err(err) => {
                            let mapped = crate::watch::map_watch_error(&err);
                            let _ = out_tx.send((Message::Error(mapped), corr));
                        }
                    }
                }
                Ok(BridgeRequest::HostAction(request, corr)) => match bridge.host_action(request) {
                    Ok(reply) => {
                        let _ = out_tx.send((reply, corr));
                    }
                    Err(err) => {
                        let mapped = crate::watch::map_watch_error(&err);
                        let _ = out_tx.send((Message::Error(mapped), corr));
                    }
                },
                Ok(BridgeRequest::DeviceListRequest(request, corr)) => {
                    let reply = {
                        let host = lock(&state);
                        Bridge::<HerdrClient>::device_list_request(
                            &host.store,
                            Some(device_id.as_str()),
                            request,
                        )
                    };
                    let _ = out_tx.send((reply, corr));
                }
                Ok(BridgeRequest::RevokeDevice(request, corr)) => {
                    let mut guard = lock(&state);
                    let host: &mut HostState = &mut guard;
                    // R-11-065: the reply is queued BEFORE the registry fires the close
                    // signal. `serve_session` drains `out_rx` when the signal lands, so a
                    // close fired first can find the queue still empty and send the fatal
                    // `revoked` error ahead of `revoke_result`.
                    let outcome = Bridge::<HerdrClient>::revoke_device_request(
                        &mut host.store,
                        &host.paths,
                        request,
                        None,
                    );
                    match outcome {
                        Ok(reply) => {
                            let result = match &reply {
                                Message::RevokeResult(result) => Some(result.clone()),
                                _ => None,
                            };
                            let _ = out_tx.send((reply, corr));
                            if let Some(result) = result {
                                host.registry.close_for_revocation(&result);
                                finish_wire_revoke(host, &result);
                            }
                        }
                        Err(err) => {
                            let mapped = crate::watch::map_watch_error(&err);
                            let _ = out_tx.send((Message::Error(mapped), corr));
                        }
                    }
                }
                Err(std_mpsc::RecvTimeoutError::Disconnected) => return,
                Err(std_mpsc::RecvTimeoutError::Timeout) => break,
            }
            for reply in bridge.take_input_replies() {
                let _ = out_tx.send(reply);
            }
            next = match pending.take().map_or_else(|| req_rx.try_recv(), Ok) {
                Ok(request) => Ok(request),
                Err(std_mpsc::TryRecvError::Empty) => break,
                Err(std_mpsc::TryRecvError::Disconnected) => return,
            };
        }

        // R-10-073/R-11-242: use the unsolicited snapshot outbound path.
        if let Some(theme) = theme.poll(Instant::now()) {
            let _ = out_tx.send((
                Message::HostTheme(herdr_relay_proto::messages::HostTheme { theme }),
                None,
            ));
        }

        let mut clear_subscription = false;
        let mut resubscribe = false;
        if let Some((rx, frame_slot)) = &subscription {
            let tick_deadline = Instant::now() + Duration::from_millis(50);
            let outcome = bridge.run_until(
                rx,
                tick_deadline,
                frame_slot,
                |message| {
                    let _ = out_tx.send((message, None));
                },
                || resubscribe = true,
            );
            if outcome.is_err() {
                clear_subscription = true;
            }
            if let Some(frame) = frame_slot.try_take() {
                let _ = out_tx.send((Message::PaneFrame(frame), None));
            }
            for reply in bridge.take_input_replies() {
                let _ = out_tx.send(reply);
            }
        }
        if clear_subscription {
            subscription = None;
        } else if resubscribe {
            // R-02-013a: a created pane's `pane.agent_status_changed` coverage
            // exists only after a fresh `events.subscribe` carrying every
            // known pane; Herdr has no incremental add (see
            // `subscription_entries`' own doc comment).
            subscription = open_subscription(&client, &bridge);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{bounded_host_name, to_ws_origin};
    #[test]
    fn input_coalesces_only_consecutive_lines_and_replies_to_every_corr() {
        use super::*;
        use herdr_relay_proto::messages::SendInputAck;

        let line = |pane: &str, text: &str| SendInput {
            pane_id: pane.to_owned(),
            defer: None,
            line: Some(text.to_owned()),
            text: None,
            keys: None,
        };
        let barriers = [
            BridgeRequest::TreeRequest(Some("tree".to_owned())),
            BridgeRequest::SendInput(line("other", "other"), None),
            BridgeRequest::SendInput(
                SendInput {
                    defer: Some(herdr_relay_proto::messages::Defer::UntilIdle),
                    ..line("pane", "deferred")
                },
                Some("held".to_owned()),
            ),
            BridgeRequest::SendInput(
                SendInput {
                    text: Some("invalid".to_owned()),
                    ..line("pane", "malformed")
                },
                None,
            ),
            BridgeRequest::SendInput(
                SendInput {
                    pane_id: "pane".to_owned(),
                    defer: None,
                    line: None,
                    text: None,
                    keys: Some(vec!["Enter".to_owned()]),
                },
                None,
            ),
        ];
        for barrier in barriers {
            let (tx, rx) = std_mpsc::channel();
            assert!(
                tx.send(BridgeRequest::SendInput(
                    line("pane", "newest"),
                    Some("second".to_owned())
                ))
                .is_ok()
            );
            assert!(tx.send(barrier).is_ok());
            assert!(
                tx.send(BridgeRequest::SendInput(
                    line("pane", "after"),
                    Some("after".to_owned())
                ))
                .is_ok()
            );
            let mut pending = None;
            let (request, corrs) = coalesce_input(
                line("pane", "old"),
                Some("first".to_owned()),
                &rx,
                &mut pending,
            );
            assert_eq!(request.line.as_deref(), Some("newest"));
            assert!(matches!(
                pending,
                Some(BridgeRequest::TreeRequest(_)) | Some(BridgeRequest::SendInput(_, _))
            ));
            assert!(
                matches!(rx.try_recv(), Ok(BridgeRequest::SendInput(request, _)) if request.line.as_deref() == Some("after"))
            );
            for reply in [
                Message::SendInputAck(SendInputAck {
                    pane_id: "pane".to_owned(),
                    accepted: true,
                    queued: false,
                }),
                Message::SendInputAck(SendInputAck {
                    pane_id: "pane".to_owned(),
                    accepted: false,
                    queued: false,
                }),
                Message::Error(ErrorMessage {
                    code: WireErrorCode::InternalError,
                    message: "failed".to_owned(),
                    fatal: false,
                }),
            ] {
                let (out_tx, mut out_rx) = tokio::sync::mpsc::unbounded_channel();
                reply_to_inputs(&out_tx, reply.clone(), corrs.clone());
                assert_eq!(
                    out_rx.try_recv().unwrap(),
                    (reply.clone(), Some("first".to_owned()))
                );
                assert_eq!(
                    out_rx.try_recv().unwrap(),
                    (reply, Some("second".to_owned()))
                );
                assert!(out_rx.try_recv().is_err());
            }
        }
    }

    #[test]
    fn outbound_keeps_latest_frame_per_pane_and_other_messages_in_order() {
        use super::*;
        let frame = |pane: &str, revision| {
            (
                Message::PaneFrame(PaneFrame {
                    pane_id: pane.to_owned(),
                    revision,
                    viewport_rows: 24,
                    width: 80,
                    text: revision.to_string(),
                }),
                None,
            )
        };
        let pong = (
            Message::Pong(herdr_relay_proto::messages::Pong {}),
            Some("ping".to_owned()),
        );
        let error = (
            Message::Error(ErrorMessage {
                code: WireErrorCode::InternalError,
                message: "failed".to_owned(),
                fatal: false,
            }),
            None,
        );
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
        for message in [
            pong.clone(),
            frame("b", 1),
            frame("a", 2),
            error.clone(),
            frame("b", 2),
        ] {
            tx.send(message).unwrap();
        }
        assert_eq!(
            drain_outgoing(frame("a", 1), &mut rx),
            vec![pong, frame("a", 2), error, frame("b", 2)]
        );
        assert!(rx.try_recv().is_err());
    }

    #[test]
    fn ping_echoes_corr_without_a_bridge_request() {
        use super::*;
        let (tx, rx) = std_mpsc::channel();
        let frame = Frame::wrap(
            1,
            Some("probe".to_owned()),
            &Message::Ping(herdr_relay_proto::messages::Ping {}),
        )
        .unwrap();
        let result = dispatch_incoming(&frame.to_json_bytes().unwrap(), &tx);
        assert!(matches!(result, DispatchOutcome::Pong(corr) if corr.as_deref() == Some("probe")));
        assert!(rx.try_recv().is_err());
    }

    #[test]
    fn hostname_respects_utf8_byte_limit() {
        assert_eq!(bounded_host_name("a".repeat(65)), "a".repeat(64));
        assert_eq!(bounded_host_name("é".repeat(33)), "é".repeat(32));
        assert_eq!(
            bounded_host_name(format!("{}é", "a".repeat(63))),
            "a".repeat(63)
        );
        assert_eq!(bounded_host_name("host".to_owned()), "host");
    }
    use crate::popup::INVALID_ORIGIN_NOTICE;
    use herdr_relay_proto::handle::is_absolute_http_origin;

    #[test]
    fn to_ws_origin_maps_http_and_https() {
        assert_eq!(
            to_ws_origin("http://192.168.1.20:8080"),
            "ws://192.168.1.20:8080"
        );
        assert_eq!(
            to_ws_origin("https://relay.example.com"),
            "wss://relay.example.com"
        );
    }

    #[test]
    fn the_start_paths_origin_check_matches_the_panes() {
        // The start path's origin check: a `ws://` value must fail the one
        // shared validator, and the refusal message must be the exact one
        // the pairing pane also shows (R-10-061).
        assert!(!is_absolute_http_origin("ws://localhost:8080"));
        assert_eq!(
            INVALID_ORIGIN_NOTICE,
            "relay_origin must be an http:// or https:// origin, for example http://192.168.1.20:8080 - set it in config.toml"
        );
    }
}

#[cfg(test)]
mod lifetime_tests {
    use super::*;
    use herdr_relay_proto::messages::Platform;

    // R-13-053/R-13-037: revoke or replacement between claim and dispatch rejects the old identity.
    #[tokio::test]
    async fn revoked_or_replaced_identity_cannot_register_for_dispatch() {
        let paths = ConfigPaths::new(
            std::env::temp_dir().join(format!("herdr-bridge-lifetime-{}", uuid::Uuid::new_v4(),)),
        );
        let relay_config = RelayConfig::default();
        let (private, public) = crate::noise::generate_keypair().expect("generate host key");
        let host = start(HostConfig {
            paths: paths.clone(),
            client: HerdrClient::with_path(PathBuf::from("unused-test-socket"), &relay_config),
            relay_config,
            ws_origin: "ws://127.0.0.1:1".to_owned(),
            keypair: HostKeypair { private, public },
            herdr_version: "test".to_owned(),
            herdr_protocol: 1,
            host_name: "test".to_owned(),
            words: Vec::new(),
            log: Arc::new(|_| {}),
        })
        .await
        .expect("start bridge");
        let handle = Handle::generate().expect("generate handle");
        let identity = HostIdentity {
            host_id: uuid::Uuid::new_v4().to_string(),
            host_name: "test".to_owned(),
        };
        lock(&host.state)
            .store
            .add(
                identity.host_id.clone(),
                handle.encode(),
                "device".to_owned(),
                "phone".to_owned(),
                Platform::Android,
                "15".to_owned(),
                public,
            )
            .expect("store device");
        let claim =
            claim_active(&host.state, Some("device".to_owned()), handle).expect("claim session");
        revoke_one(&host.state, "device").expect("revoke before registry insertion");
        assert!(register_session(&host.state, &identity, handle, "device").is_none());
        let replacement_handle = Handle::generate().expect("generate replacement handle");
        let replacement = HostIdentity {
            host_id: uuid::Uuid::new_v4().to_string(),
            host_name: "test".to_owned(),
        };
        lock(&host.state)
            .store
            .add(
                replacement.host_id.clone(),
                replacement_handle.encode(),
                "device".to_owned(),
                "phone".to_owned(),
                Platform::Android,
                "15".to_owned(),
                public,
            )
            .expect("store replacement");
        assert!(register_session(&host.state, &identity, handle, "device").is_none());
        let replacement_claim =
            claim_active(&host.state, Some("device".to_owned()), replacement_handle)
                .expect("claim replacement");
        drop(claim);
        assert!(
            lock(&host.state)
                .active
                .as_ref()
                .is_some_and(|active| active.handle == replacement_handle)
        );
        assert!(matches!(
            lock(&host.state).link.state,
            control::LinkState::Connected
        ));
        let close_rx = register_session(&host.state, &replacement, replacement_handle, "device")
            .expect("register current identity");
        revoke_one(&host.state, "device").expect("revoke current identity");
        assert!(matches!(close_rx.await, Ok(CloseReason::Revoked)));
        drop(replacement_claim);
        host.shutdown().await;
        std::fs::remove_dir_all(paths.dir()).ok();
    }
}
