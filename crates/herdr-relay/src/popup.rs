//! The Host popup pane: the pairing QR code, the six-word phrase, and the
//! paired-device list (`docs/31-mockups/16-host-popup.md`, `WP-10-c`).
//!
//! This is the only UI surface a Herdr plugin can open (`R-01-005`,
//! `R-90-010`). Every behavioural rule this module implements is cited by its
//! `R-31-16-NN` id inline, next to the code that implements it; read the
//! mockup document itself for the prose these ids point at.
//!
//! # The pane is a control client (R-10-066)
//!
//! The long-lived bridge (`crate::bridge`) holds every relay connection, the
//! paired-device store and the open pairing. This pane is a loopback client
//! of the bridge's R-10-062 control transport: it renders the `status`
//! answer and maps its keys to commands (`p` -> `open_pairing`, `d` ->
//! `revoke`, `r` -> `revoke_all`, `s` -> `stop`, `f` -> `status`; `q` sends
//! `close_pairing` when a pairing is open, then quits). It MUST NOT mint a
//! handle, a phrase or a QR of its own: the QR is encoded from the `uri`
//! field of the status answer (R-31-16-01), and while `pairing.registered`
//! is false the pane shows `registering...` and no credential (R-10-064).
//! When the bridge is not running (R-10-062) the pane shows the exact
//! `control::not_running_notice()` and no pairing surface.
//!
//! # Verification
//!
//! This workstation has no way to visually confirm real terminal rendering
//! (no interactive pty this session can drive end to end). Verification here
//! is structural: [`App::handle_key`]'s state machine is exercised directly
//! (bypassing `crossterm::event`), and [`render_to_buffer`] is asserted
//! cell-by-cell against an in-memory `ratatui` `TestBackend` — the same
//! mechanism `--once` (R-31-16-06) uses, which exists precisely so a test can
//! assert this pane's output "without a terminal". Tests inject the status
//! source and the command sink ([`App::with_sources`]), so they need no
//! bridge, no disk and no clipboard.

use std::io::Write;
use std::time::{Duration, Instant};

use crossterm::event::{self, Event, KeyCode, KeyEventKind};
use crossterm::terminal::{
    EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode, enable_raw_mode,
};
use ratatui::Frame;
use ratatui::Terminal;
use ratatui::backend::{CrosstermBackend, TestBackend};
use ratatui::buffer::Buffer;
use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Paragraph, Wrap};
use time::OffsetDateTime;
use time::format_description::well_known::Rfc3339;
use unicode_width::{UnicodeWidthChar, UnicodeWidthStr};

use herdr_relay_proto::messages::Platform;

use crate::config::{ConfigError, ConfigPaths};
use crate::control::{self, ClientError, Command, LinkState};
use crate::pairing::{QrGrid, qr_from_uri};
use crate::process;

// ---------------------------------------------------------------------------
// Layout constants
// ---------------------------------------------------------------------------

/// The QR quiet zone, in modules on every side (R-31-16-02).
const QUIET_ZONE: usize = 4;
/// R-31-16-26: the floor below which the pane shows "terminal too small" and
/// nothing else, in both floor cases.
const FLOOR_COLS: u16 = 28;
/// R-31-16-26: the floor while a pairing session is open. 12, not 11, since
/// the copy hint line (R-31-16-34) joined the never-dropped credential
/// block.
const PAIRING_FLOOR_ROWS: u16 = 12;
/// R-31-16-26: the floor otherwise.
const IDLE_FLOOR_ROWS: u16 = 6;

/// R-31-16-37: the notice the bridge prints and exits with when
/// `relay_origin` is not an absolute `http://`/`https://` origin (R-10-061).
/// The exact contract message, shared verbatim with `bridge.rs` through
/// `herdr_relay::popup::INVALID_ORIGIN_NOTICE`, so the string lives in
/// exactly one place. The pane itself never validates the origin: the bridge
/// refuses to start on an invalid one, so the pane sees only the
/// bridge-not-running surface of R-10-066.
pub const INVALID_ORIGIN_NOTICE: &str = "relay_origin must be an http:// or https:// origin, \
for example http://192.168.1.20:8080 - set it in config.toml";

fn meta_style() -> Style {
    Style::default().fg(Color::DarkGray)
}

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

/// A failure from the popup's own real-I/O paths (resolving the config
/// directory, or the interactive terminal).
#[derive(Debug, thiserror::Error)]
pub enum PopupError {
    #[error(transparent)]
    Config(#[from] ConfigError),
    #[error(transparent)]
    Io(#[from] std::io::Error),
}

// ---------------------------------------------------------------------------
// Per-row state (R-31-16-15, R-31-16-16, R-31-16-19)
// ---------------------------------------------------------------------------

/// A phone row's state — exactly one of three words, never a fourth
/// (R-31-16-19).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum RowState {
    Connected,
    Idle,
    Unknown,
}

impl RowState {
    /// R-31-16-19: `connected` only where the bridge's status row says so
    /// (R-10-064's `devices[].connected`); `unknown` while the link is
    /// `offline` or `stopped`; `idle` otherwise.
    fn compute(link: &control::LinkStatus, connected: bool) -> Self {
        if connected {
            return RowState::Connected;
        }
        match link.state {
            LinkState::Offline | LinkState::Stopped => RowState::Unknown,
            LinkState::Connected | LinkState::Idle => RowState::Idle,
        }
    }

    fn word(self) -> &'static str {
        match self {
            RowState::Connected => "connected",
            RowState::Idle => "idle",
            RowState::Unknown => "unknown",
        }
    }

    /// R-31-16-08 in the reference table: `connected` green, `idle`
    /// uncoloured, `unknown` yellow (R-31-16-11: eight basic colours only).
    fn style(self) -> Style {
        match self {
            RowState::Connected => Style::default().fg(Color::Green),
            RowState::Idle => Style::default(),
            RowState::Unknown => Style::default().fg(Color::Yellow),
        }
    }
}

fn platform_label(platform: Platform) -> &'static str {
    match platform {
        Platform::Ios => "ios",
        Platform::Android => "android",
    }
}

// ---------------------------------------------------------------------------
// Confirmations (R-31-16-09, R-31-16-32, R-13-057)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
enum PendingAction {
    RemoveOne {
        device_id: String,
        device_name: String,
    },
    RemoveAll {
        count: usize,
    },
    Stop,
}

impl PendingAction {
    /// The exact-count `y/n` question (R-31-16-09).
    fn question(&self) -> String {
        match self {
            PendingAction::RemoveOne { device_name, .. } => {
                format!("remove {device_name}? 1 phone loses access. y/n")
            }
            PendingAction::RemoveAll { count } => {
                let noun = if *count == 1 { "phone" } else { "phones" };
                let verb = if *count == 1 { "loses" } else { "lose" };
                format!("remove every phone? {count} {noun} {verb} access at once. y/n")
            }
            PendingAction::Stop => {
                "stop the relay? this phone list is kept, and no phone can connect. y/n".to_string()
            }
        }
    }
}

// ---------------------------------------------------------------------------
// The per-redraw view of the bridge's open pairing (R-10-064)
// ---------------------------------------------------------------------------

/// The credential half of an open pairing, present only once the bridge
/// reports `registered: true` (R-10-064 keeps `uri`/`phrase`/`handle` null
/// until then, and the pane shows `registering...` instead — R-31-16-38).
struct PairingView {
    remaining: Duration,
    credential: Option<PairingCredential>,
}

struct PairingCredential {
    uri: String,
    handle: String,
    words: String,
    /// `None` when `qr_from_uri` rejected the URI (in practice an origin so
    /// long the URI exceeds R-11-141's 512 bytes): the words stay on screen,
    /// because they are the credential (the mockup's URI-too-long state).
    qr: Option<QrGrid>,
}

impl App {
    /// The pairing to draw this frame, or `None` when none is open or its
    /// countdown already reached zero (R-13-022). The countdown ticks
    /// locally: `expires_in_s` is read once per status answer and counted
    /// down from `status_fetched_at`, so no per-second reload is needed.
    fn pairing_view(&self, now: Instant) -> Option<PairingView> {
        let pairing = self.status.as_ref()?.pairing.as_ref()?;
        let remaining = Duration::from_secs(pairing.expires_in_s)
            .checked_sub(now.saturating_duration_since(self.status_fetched_at))?;
        let credential = if !pairing.registered {
            None
        } else {
            match (&pairing.uri, &pairing.handle, &pairing.phrase) {
                (Some(uri), Some(handle), Some(words)) => Some(PairingCredential {
                    qr: qr_from_uri(uri).ok(),
                    uri: uri.clone(),
                    handle: handle.clone(),
                    words: words.clone(),
                }),
                // R-10-064: registered implies the three fields are set; a
                // violation is treated as still registering, never drawn.
                _ => None,
            }
        };
        Some(PairingView {
            remaining,
            credential,
        })
    }

    /// Whether a pairing session is open on the bridge (registered or not).
    fn pairing_open(&self) -> bool {
        self.status.as_ref().is_some_and(|s| s.pairing.is_some())
    }
}

// ---------------------------------------------------------------------------
// App: the pane's own state (R-31-16-07: a snapshot, reloaded after a write
// or `f`, plus the poll cadence the countdown and the link state need)
// ---------------------------------------------------------------------------

/// The pane's full state between redraws: the bridge's last `status` answer
/// and pure UI state. Reloading re-asks the bridge (R-31-16-07); moving the
/// selection costs no I/O.
pub struct App {
    status: Option<control::Status>,
    /// R-10-066/R-31-16-06: the status source is injectable, so `--once` and
    /// every test render through a fixture with no bridge. Production is
    /// `control::status` against the R-10-062 endpoint.
    status_source: Box<dyn FnMut() -> Result<control::Status, ClientError>>,
    /// The command half of the same transport, injectable for the same
    /// reason. Production is `control::request`.
    #[allow(clippy::type_complexity)]
    command_sink: Box<dyn FnMut(&Command) -> Result<serde_json::Value, ClientError>>,
    /// Copies the full pairing URI to the clipboard for `c` (R-31-16-34). A
    /// function pointer so this module's own tests never touch the real
    /// clipboard: the default points at [`process::copy_to_clipboard`],
    /// which is the only real implementation (and the only one allowed,
    /// R-31-16-35).
    copy_pairing_uri: fn(&str) -> Result<(), String>,
    /// `true` when the last status or command call reported the bridge as
    /// not running (R-10-062): the pane shows the R-10-066 notice and no
    /// pairing surface.
    bridge_down: bool,
    /// When `status` was last fetched; the pairing countdown ticks down from
    /// here against `expires_in_s`.
    status_fetched_at: Instant,
    /// Set once a locally counted-down pairing hit zero, so the expired
    /// notice prints exactly once per pairing (R-31-16-05).
    expiry_noticed: bool,
    selected: usize,
    confirm: Option<PendingAction>,
    notice: Option<String>,
    /// R-30-600: "a yellow notice line that clears on the next redraw."
    /// `true` once `notice` has been shown for one [`draw`] call; the next
    /// call clears it before building that frame's content, unless a fresh
    /// notice was set in between (`set_notice` always resets this to
    /// `false`, so a freshly set notice always gets its own one-redraw
    /// showing first).
    notice_shown: bool,
    loading: bool,
    /// Set after every [`draw`] call so the next key event knows whether a
    /// phone row was actually on screen (R-31-16-29: no selection may exist
    /// that was not drawn).
    table_visible: bool,
}

/// What a key press did, for the interactive loop.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum KeyOutcome {
    Continue,
    Quit,
}

impl App {
    /// The production pane: status and commands go to the running bridge
    /// over the R-10-062 transport under `paths`.
    pub fn new(paths: ConfigPaths) -> Self {
        let status_paths = paths.clone();
        let command_paths = paths;
        Self::with_sources(
            Box::new(move || control::status(&status_paths)),
            Box::new(move |command| control::request(&command_paths, command)),
        )
    }

    /// The test seam (R-10-066, R-31-16-06): a caller-supplied status source
    /// and command sink, so a test needs no bridge.
    #[allow(clippy::type_complexity)]
    pub fn with_sources(
        status_source: Box<dyn FnMut() -> Result<control::Status, ClientError>>,
        command_sink: Box<dyn FnMut(&Command) -> Result<serde_json::Value, ClientError>>,
    ) -> Self {
        Self {
            status: None,
            status_source,
            command_sink,
            copy_pairing_uri: process::copy_to_clipboard,
            bridge_down: false,
            status_fetched_at: Instant::now(),
            expiry_noticed: false,
            selected: 0,
            confirm: None,
            notice: None,
            notice_shown: false,
            loading: false,
            table_visible: false,
        }
    }

    /// Real-I/O constructor for the standalone CLI binary. The first status
    /// fetch happens here; a bridge that is not running lands the pane on
    /// the R-10-066 notice surface, not on an error exit.
    pub fn load_live() -> Result<Self, PopupError> {
        let paths = crate::bridge::control_paths()?;
        let mut app = Self::new(paths);
        app.refresh();
        Ok(app)
    }

    fn devices(&self) -> &[control::DeviceRow] {
        self.status
            .as_ref()
            .map(|status| status.devices.as_slice())
            .unwrap_or(&[])
    }

    fn stopped(&self) -> bool {
        self.status
            .as_ref()
            .is_some_and(|status| status.link.state == LinkState::Stopped)
    }

    /// Sets `notice`, always displayed for exactly one redraw before
    /// [`draw`] clears it (R-30-600). Every notice-setting call site in
    /// this module MUST go through this rather than assigning `self.notice`
    /// directly, so a freshly set notice always gets its own showing even
    /// if it overwrites one that had already been shown once.
    fn set_notice(&mut self, text: impl Into<String>) {
        self.notice = Some(text.into());
        self.notice_shown = false;
    }

    fn selected_device(&self) -> Option<&control::DeviceRow> {
        self.devices().get(self.selected)
    }

    /// Re-asks the bridge for its status (`f`, and after every write, per
    /// R-31-16-07). A bridge that does not answer per R-10-062 is "not
    /// running": the pane drops to the notice-only surface (R-10-066).
    pub fn refresh(&mut self) {
        self.refresh_at(Instant::now());
    }

    fn refresh_at(&mut self, now: Instant) {
        match (self.status_source)() {
            Ok(status) => {
                // R-13-023: the bridge destroys a spent pairing without
                // minting a replacement, so an answer can drop `pairing`
                // while the local countdown still had time on it. A
                // successful pair also drops `pairing`, but grows the
                // device list, and `revoke_all` empties it; only a spent
                // phrase leaves the list unchanged.
                let spent = self.status.as_ref().is_some_and(|old| {
                    old.pairing.is_some()
                        && self.pairing_view(now).is_some()
                        && status.pairing.is_none()
                        && status.devices.len() == old.devices.len()
                });
                self.status_fetched_at = now;
                self.status = Some(status);
                self.bridge_down = false;
                self.clamp_selection();
                if spent {
                    self.set_notice("phrase spent - press p for a new one");
                }
            }
            Err(ClientError::NotRunning) => {
                self.status = None;
                self.bridge_down = true;
            }
            // The R-10-064 client error strings are all fixed text that
            // names no path, token or secret (R-10-065).
            Err(err) => self.set_notice(format!("{err}")),
        }
    }

    /// Sends one R-10-064 command. Returns `false` when the bridge did not
    /// accept it; a dead bridge flips the pane to the notice surface.
    fn send_command(&mut self, command: Command) -> bool {
        match (self.command_sink)(&command) {
            Ok(_) => true,
            Err(ClientError::NotRunning) => {
                self.status = None;
                self.bridge_down = true;
                false
            }
            Err(err) => {
                self.set_notice(format!("{err}"));
                false
            }
        }
    }

    /// `p` (R-10-066): asks the bridge to open a pairing, then reloads. The
    /// bridge mints the phrase, the handle and the registration; this pane
    /// never does (R-31-16-38).
    pub fn open_pairing(&mut self) {
        // The bridge preserves an open pairing and leaves the stopped state.
        self.send_command(Command::OpenPairing);
        self.refresh();
    }

    /// `c` (R-31-16-34). Copies the exact pairing URI the QR encodes — the
    /// `uri` field of the status answer, never a URI rebuilt from parts —
    /// through the platform clipboard tool. With no session open, one still
    /// registering (R-10-064 withholds the credential), or one whose phrase
    /// expired, there is nothing to copy: `press p first`.
    fn copy_pairing(&mut self, now: Instant) {
        let uri = self
            .pairing_view(now)
            .and_then(|view| view.credential.map(|credential| credential.uri));
        let Some(uri) = uri else {
            self.set_notice("press p first - there is nothing to copy yet");
            return;
        };
        match (self.copy_pairing_uri)(&uri) {
            Ok(()) => {
                self.set_notice("copied - paste it into the phone app with Paste from clipboard")
            }
            // R-31-16-36: the URI never prints in a failure message. The
            // error is the fixed, path-free `CLIPBOARD_COPY_FAILED`.
            Err(message) => self.set_notice(format!("copy failed: {message}")),
        }
    }

    /// The live pairing URI, or `None` once no session is open, it is still
    /// registering, or it has expired. `pub` so an external caller
    /// (`tests/popup_once.rs`) can compare the URI a captured QR block
    /// decodes to against the exact value this pane encoded (R-31-16-02).
    pub fn pairing_uri(&self) -> Option<String> {
        let now = Instant::now();
        self.pairing_view(now)
            .and_then(|view| view.credential.map(|credential| credential.uri))
    }

    /// The live QR grid's own module width, or `None` once no session is
    /// open, it is still registering, it expired, or its URI was too long to
    /// encode. `pub` so an external caller (`tests/popup_once.rs`) can
    /// reconstruct the exact module grid from the pane's own rendered
    /// half-block characters without re-deriving the encoder's chosen QR
    /// version from the rendered text (R-31-16-02: the region size always
    /// comes from the encoder's own output).
    pub fn qr_width(&self) -> Option<usize> {
        let now = Instant::now();
        self.pairing_view(now)
            .and_then(|view| view.credential)
            .and_then(|credential| credential.qr)
            .map(|qr| qr.width)
    }

    fn clamp_selection(&mut self) {
        let len = self.devices().len();
        if len == 0 {
            self.selected = 0;
        } else if self.selected >= len {
            self.selected = len - 1;
        }
    }

    /// Dispatches one key press. `now` drives the pairing countdown/expiry
    /// checks the same way every other time-dependent call in this pane
    /// does.
    fn handle_key(&mut self, key: KeyCode, now: Instant) -> Result<KeyOutcome, PopupError> {
        if let Some(pending) = self.confirm.take() {
            // R-31-16-32: `y` confirms, every other key (`n`, `esc`, `q`,
            // anything else) cancels. `q`/`esc` MUST NOT quit the pane here.
            if matches!(key, KeyCode::Char('y')) {
                self.confirm_action(pending);
            }
            return Ok(KeyOutcome::Continue);
        }
        match key {
            KeyCode::Up | KeyCode::Char('k') => self.move_selection(-1),
            KeyCode::Down | KeyCode::Char('j') => self.move_selection(1),
            KeyCode::Char('p') => self.open_pairing(),
            // R-31-16-34: copy the full pairing URI to the clipboard while
            // a session is open, never a rebuilt-from-parts copy.
            KeyCode::Char('c') => self.copy_pairing(now),
            KeyCode::Char('d') => {
                if self.table_visible
                    && let Some(device) = self.selected_device()
                {
                    self.confirm = Some(PendingAction::RemoveOne {
                        device_id: device.device_id.clone(),
                        device_name: device.device_name.clone(),
                    });
                }
            }
            KeyCode::Char('r') => {
                let count = self.devices().len();
                if count > 0 {
                    self.confirm = Some(PendingAction::RemoveAll { count });
                }
            }
            KeyCode::Char('s') => {
                if !self.stopped() {
                    self.confirm = Some(PendingAction::Stop);
                }
            }
            KeyCode::Char('f') => {
                self.loading = true;
                self.refresh();
                self.loading = false;
            }
            KeyCode::Char('q') | KeyCode::Esc => {
                // R-31-16-05: `q` ends any open pairing session instantly, in
                // the same key press that quits the pane. R-10-066: the pane
                // tells the bridge (`close_pairing`), then hides the
                // credential locally without waiting for the next poll.
                if self.pairing_open() {
                    self.send_command(Command::ClosePairing);
                    if let Some(status) = self.status.as_mut() {
                        status.pairing = None;
                    }
                }
                return Ok(KeyOutcome::Quit);
            }
            _ => {}
        }
        Ok(KeyOutcome::Continue)
    }

    fn move_selection(&mut self, delta: i32) {
        if !self.table_visible || self.devices().is_empty() {
            return;
        }
        let len = self.devices().len() as i32;
        let next = (self.selected as i32 + delta).clamp(0, len - 1);
        self.selected = next as usize;
    }

    /// The confirmed half of a `y/n` question (R-31-16-09): send the command
    /// (R-10-066's key map), reload, then set the action's own notice so it
    /// wins over any reload notice.
    fn confirm_action(&mut self, pending: PendingAction) {
        match pending {
            PendingAction::RemoveOne {
                device_id,
                device_name,
            } => {
                if self.send_command(Command::Revoke { device_id }) {
                    self.refresh();
                    self.set_notice(format!("{device_name} lost access"));
                }
            }
            PendingAction::RemoveAll { .. } => {
                if self.send_command(Command::RevokeAll) {
                    self.refresh();
                    self.set_notice("every phone lost access");
                }
            }
            PendingAction::Stop => {
                // R-31-16-24: `s` MUST NOT clear a pairing. The bridge's
                // `stop` does not either (R-10-064).
                self.send_command(Command::Stop);
                self.refresh();
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Text measurement helpers (R-31-16-28: display cells, not characters)
// ---------------------------------------------------------------------------

fn cell_width(text: &str) -> usize {
    UnicodeWidthStr::width(text)
}

/// Pads `text` to `width` display cells with trailing spaces. Never
/// truncates — callers that need elision call [`elide`] first.
fn pad(text: &str, width: usize) -> String {
    let current = cell_width(text);
    if current >= width {
        text.to_string()
    } else {
        format!("{text}{}", " ".repeat(width - current))
    }
}

/// Elides `text` to `width` display cells, tail-truncated with one `…`,
/// measured with the same width function as the budget itself (R-31-16-28).
fn elide(text: &str, width: usize) -> String {
    if cell_width(text) <= width {
        return text.to_string();
    }
    if width == 0 {
        return String::new();
    }
    let mut out = String::new();
    let mut used = 0usize;
    for ch in text.chars() {
        let w = UnicodeWidthChar::width(ch).unwrap_or(0);
        if used + w > width.saturating_sub(1) {
            break;
        }
        out.push(ch);
        used += w;
    }
    out.push('…');
    out
}

// ---------------------------------------------------------------------------
// Credential block (R-31-16-04, R-31-16-13, R-31-16-27)
// ---------------------------------------------------------------------------

const CRED_INDENT: usize = 4;
const CRED_LABEL_FIELD: usize = 10;
const CRED_CONT_INDENT: usize = 6;

/// One label/value credential line, wrapped per R-31-16-27 when it does not
/// fit inline: the value moves to its own row at column 7, and — if it still
/// does not fit — wraps at a space without ever breaking the 22-character
/// handle or a phrase word. R-31-16-13: no numeric code is ever the value
/// here; every caller passes the relay origin, the handle text, or the
/// phrase text.
fn credential_lines(label: &str, value: &str, width: u16) -> Vec<Line<'static>> {
    let width = width as usize;
    let prefix = format!(
        "{}{}",
        " ".repeat(CRED_INDENT),
        pad(&format!("{label}:"), CRED_LABEL_FIELD)
    );
    let inline = format!("{prefix}{value}");
    if cell_width(&inline) <= width {
        return vec![Line::styled(inline, Style::default())];
    }
    let mut lines = vec![Line::styled(
        prefix.trim_end().to_string(),
        Style::default(),
    )];
    let indent = " ".repeat(CRED_CONT_INDENT);
    let avail = width.saturating_sub(CRED_CONT_INDENT).max(1);
    for row in wrap_at_spaces(value, avail) {
        lines.push(Line::styled(format!("{indent}{row}"), Style::default()));
    }
    lines
}

/// Greedy word wrap that never breaks a single "word" (a phrase word or the
/// handle, both of which R-31-16-27 forbids breaking).
fn wrap_at_spaces(text: &str, width: usize) -> Vec<String> {
    let mut lines = Vec::new();
    let mut current = String::new();
    for word in text.split(' ') {
        let candidate_width = if current.is_empty() {
            cell_width(word)
        } else {
            cell_width(&current) + 1 + cell_width(word)
        };
        if !current.is_empty() && candidate_width > width {
            lines.push(std::mem::take(&mut current));
        }
        if !current.is_empty() {
            current.push(' ');
        }
        current.push_str(word);
    }
    if !current.is_empty() || lines.is_empty() {
        lines.push(current);
    }
    lines
}

// ---------------------------------------------------------------------------
// QR rendering (R-31-16-02, R-31-16-03)
// ---------------------------------------------------------------------------

/// `(columns, printed rows)` for `qr`'s region, quiet zone and 2-column
/// indent included, computed from the encoder's own output width — never a
/// fixed constant (R-31-16-02).
fn qr_region_size(qr_width_modules: usize) -> (u16, u16) {
    let padded = qr_width_modules + 2 * QUIET_ZONE;
    let rows = padded.div_ceil(2);
    let cols = padded + 2;
    (cols as u16, rows as u16)
}

fn qr_module_dark(qr: &QrGrid, padded_x: usize, padded_y: usize) -> bool {
    if padded_x < QUIET_ZONE || padded_y < QUIET_ZONE {
        return false;
    }
    let x = padded_x - QUIET_ZONE;
    let y = padded_y - QUIET_ZONE;
    if x >= qr.width || y >= qr.width {
        return false;
    }
    qr.is_dark(x, y)
}

/// Half-block glyphs, two module rows per printed row (R-31-16-02), indented
/// two columns, default foreground on default background so the symbol
/// inverts correctly under any terminal theme (R-31-16-11).
fn qr_lines(qr: &QrGrid) -> Vec<Line<'static>> {
    let padded = qr.width + 2 * QUIET_ZONE;
    let printed_rows = padded.div_ceil(2);
    let mut lines = Vec::with_capacity(printed_rows);
    for row in 0..printed_rows {
        let top_y = row * 2;
        let bottom_y = row * 2 + 1;
        let mut glyphs = String::with_capacity(padded + 2);
        glyphs.push_str("  ");
        for x in 0..padded {
            let top = qr_module_dark(qr, x, top_y);
            let bottom = bottom_y < padded && qr_module_dark(qr, x, bottom_y);
            glyphs.push(match (top, bottom) {
                (true, true) => '█',
                (true, false) => '▀',
                (false, true) => '▄',
                (false, false) => ' ',
            });
        }
        lines.push(Line::styled(glyphs, Style::default()));
    }
    lines
}

// ---------------------------------------------------------------------------
// Timestamps (R-13-049's stored RFC 3339 strings, rendered two ways)
// ---------------------------------------------------------------------------

const MONTH_ABBR: [&str; 12] = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
];

/// The table's `Paired` column: `MM-DD HH:MM`.
fn format_paired_column(timestamp: &str) -> String {
    match OffsetDateTime::parse(timestamp, &Rfc3339) {
        Ok(dt) => format!(
            "{:02}-{:02} {:02}:{:02}",
            u8::from(dt.month()),
            dt.day(),
            dt.hour(),
            dt.minute()
        ),
        Err(_) => "unknown".to_string(),
    }
}

/// The detail block's `paired` value: `D Mon HH:MM`.
fn format_paired_detail(timestamp: &str) -> String {
    match OffsetDateTime::parse(timestamp, &Rfc3339) {
        Ok(dt) => format!(
            "{} {} {:02}:{:02}",
            dt.day(),
            MONTH_ABBR[usize::from(u8::from(dt.month())) - 1],
            dt.hour(),
            dt.minute()
        ),
        Err(_) => "unknown".to_string(),
    }
}

/// `now`/`3m ago`/`2h ago`/`5d ago`, relative to `wall_now`.
fn format_relative(timestamp: &str, wall_now: OffsetDateTime) -> String {
    let Ok(parsed) = OffsetDateTime::parse(timestamp, &Rfc3339) else {
        return "unknown".to_string();
    };
    let delta = wall_now - parsed;
    if delta.whole_seconds() < 60 {
        "now".to_string()
    } else if delta.whole_minutes() < 60 {
        format!("{}m ago", delta.whole_minutes())
    } else if delta.whole_hours() < 24 {
        format!("{}h ago", delta.whole_hours())
    } else {
        format!("{}d ago", delta.whole_days())
    }
}

// ---------------------------------------------------------------------------
// Table columns (R-31-16-28)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy)]
struct TableColumns {
    platform: bool,
    paired: bool,
    last_seen: bool,
}

/// The five-column budget is 70 cells, four (drop `Last seen`) is 57, three
/// (drop `Paired` too) is 39, two (drop `Platform` too) is 26 — the exact
/// numbers R-31-16-28's own arithmetic paragraph gives. `Phone` and `State`
/// are never dropped.
fn table_columns(width: u16) -> TableColumns {
    if width >= 70 {
        TableColumns {
            platform: true,
            paired: true,
            last_seen: true,
        }
    } else if width >= 57 {
        TableColumns {
            platform: true,
            paired: true,
            last_seen: false,
        }
    } else if width >= 39 {
        TableColumns {
            platform: true,
            paired: false,
            last_seen: false,
        }
    } else {
        TableColumns {
            platform: false,
            paired: false,
            last_seen: false,
        }
    }
}

fn table_header_line(width: u16) -> Line<'static> {
    let cols = table_columns(width);
    let mut text = pad("Phone", 16);
    text.push_str("  ");
    if cols.platform {
        text.push_str(&pad("Platform", 12));
        text.push_str("  ");
    }
    if cols.paired {
        text.push_str(&pad("Paired", 17));
        text.push_str("  ");
    }
    if cols.last_seen {
        text.push_str(&pad("Last seen", 12));
        text.push_str("  ");
    }
    text.push_str("State");
    Line::styled(text, meta_style())
}

fn row_line(
    device: &control::DeviceRow,
    row_state: RowState,
    selected: bool,
    width: u16,
    wall_now: OffsetDateTime,
) -> Line<'static> {
    let cols = table_columns(width);
    let base = if selected {
        Style::default().add_modifier(Modifier::REVERSED)
    } else {
        Style::default()
    };
    let state_style = if selected {
        row_state.style().add_modifier(Modifier::REVERSED)
    } else {
        row_state.style()
    };
    let mut spans = vec![Span::styled(
        format!("{}  ", pad(&elide(&device.device_name, 16), 16)),
        base,
    )];
    if cols.platform {
        let platform = format!("{} {}", platform_label(device.platform), device.os_version);
        spans.push(Span::styled(
            format!("{}  ", pad(&elide(&platform, 12), 12)),
            base,
        ));
    }
    if cols.paired {
        spans.push(Span::styled(
            format!("{}  ", pad(&format_paired_column(&device.paired_at), 17)),
            base,
        ));
    }
    if cols.last_seen {
        spans.push(Span::styled(
            format!(
                "{}  ",
                pad(&format_relative(&device.last_seen, wall_now), 12)
            ),
            base,
        ));
    }
    spans.push(Span::styled(row_state.word().to_string(), state_style));
    Line::from(spans)
}

/// Keeps the selected row inside the visible window (R-31-16-29).
fn visible_window(total: usize, visible: usize, selected: usize) -> std::ops::Range<usize> {
    if total == 0 || visible == 0 {
        return 0..0;
    }
    let visible = visible.min(total);
    let start = selected.saturating_sub(visible - 1).min(total - visible);
    start..(start + visible)
}

// ---------------------------------------------------------------------------
// Detail slot: selected phone, offline error, or stopped (R-31-16-18 to -24)
// ---------------------------------------------------------------------------

enum DetailKind<'a> {
    Selected(&'a control::DeviceRow),
    Offline { error: &'a str, attempt: u32 },
    Stopped,
}

fn detail_lines(kind: &DetailKind<'_>, wall_now: OffsetDateTime) -> Vec<Line<'static>> {
    match kind {
        DetailKind::Selected(device) => vec![
            Line::styled(
                format!(
                    "paired {}  -  last seen {}  -  {} {}",
                    format_paired_detail(&device.paired_at),
                    format_relative(&device.last_seen, wall_now),
                    platform_label(device.platform),
                    device.os_version
                ),
                Style::default(),
            ),
            // R-13-070: the fingerprint, never the raw key. The bridge
            // computes it (R-10-064's `devices[].fingerprint`); the pane
            // never sees the key itself.
            Line::styled(format!("key {}", device.fingerprint), Style::default()),
        ],
        DetailKind::Offline { error, attempt } => vec![
            Line::styled(
                format!("relay unreachable - connect: {error}"),
                Style::default().fg(Color::Red),
            ),
            Line::styled(format!("retrying, attempt {attempt}"), Style::default()),
        ],
        DetailKind::Stopped => vec![
            Line::styled("relay stopped", Style::default()),
            Line::styled("press p to start it again", Style::default()),
        ],
    }
}

// ---------------------------------------------------------------------------
// Footer (R-31-16-30)
// ---------------------------------------------------------------------------

struct FooterAvailability {
    scroll: bool,
    /// `c copy` is listed only while a pairing session is open
    /// (R-31-16-34): with no session the key acts, but on a notice, so
    /// listing it would suggest something to copy.
    copy: bool,
    remove_one: bool,
    remove_all: bool,
}

fn footer_line(availability: &FooterAvailability, width: u16) -> Line<'static> {
    let mut labelled_parts = Vec::new();
    let mut short_parts = Vec::new();
    let mut keys_only = Vec::new();
    if availability.scroll {
        labelled_parts.push("up/down select");
        // R-31-16-30: the short and keys-only forms already omit "up/down
        // select" at their own widths (72 -> 49 -> 11); a inert binding
        // never appears in any form (R-31-16-29).
    }
    labelled_parts.push("p pair");
    short_parts.push("p pair");
    keys_only.push("p");
    if availability.copy {
        labelled_parts.push("c copy");
        short_parts.push("c copy");
        keys_only.push("c");
    }
    if availability.remove_one {
        labelled_parts.push("d remove");
        short_parts.push("d remove");
        keys_only.push("d");
    }
    if availability.remove_all {
        labelled_parts.push("r remove all");
        short_parts.push("r all");
        keys_only.push("r");
    }
    labelled_parts.push("s stop");
    short_parts.push("s stop");
    keys_only.push("s");
    labelled_parts.push("f reload");
    short_parts.push("f reload");
    keys_only.push("f");
    labelled_parts.push("q quit");
    short_parts.push("q quit");
    keys_only.push("q");

    let labelled = labelled_parts.join("  ");
    let short = short_parts.join("  ");
    let compact = keys_only.join(" ");

    let text = if cell_width(&labelled) <= width as usize {
        labelled
    } else if cell_width(&short) <= width as usize {
        short
    } else {
        compact
    };
    Line::styled(text, meta_style())
}

// ---------------------------------------------------------------------------
// Title, relay line, pair header (R-31-16-04, R-31-16-20, R-31-16-21)
// ---------------------------------------------------------------------------

fn title_lines(app: &App) -> Vec<Line<'static>> {
    let count = app.devices().len();
    let title = Line::styled(
        format!(
            "herdr relay ({count} phone{})",
            if count == 1 { "" } else { "s" }
        ),
        Style::default().fg(Color::Cyan),
    );
    // The origin and the link state both come from the bridge's status
    // answer (R-10-066). The link object carries no round trip (R-10-064),
    // and the pane holds no relay connection to measure one with, so the
    // state word prints alone (R-31-16-21).
    let origin = app
        .status
        .as_ref()
        .map(|status| status.relay_origin.clone())
        .filter(|origin| !origin.trim().is_empty())
        .unwrap_or_else(|| "(not configured)".to_string());
    let (state, color) = match app
        .status
        .as_ref()
        .map(|status| status.link.state)
        .unwrap_or(LinkState::Offline)
    {
        LinkState::Connected => ("connected", Color::DarkGray),
        LinkState::Idle => ("idle", Color::DarkGray),
        LinkState::Offline => ("offline", Color::Red),
        LinkState::Stopped => ("stopped", Color::DarkGray),
    };
    let relay = Line::styled(
        format!("relay: {origin}   {state}"),
        Style::default().fg(color),
    );
    vec![title, relay]
}

fn pair_header_line(remaining: Duration, width: u16) -> Line<'static> {
    let secs = remaining.as_secs();
    let countdown = format!("expires in {}:{:02}", secs / 60, secs % 60);
    // The mockup's callout 3: bright black until 60 seconds remain, then
    // ANSI yellow.
    let color = if secs <= 60 {
        Color::Yellow
    } else {
        Color::DarkGray
    };
    let left = "pair a phone";
    let pad_len = (width as usize)
        .saturating_sub(cell_width(left))
        .saturating_sub(cell_width(&countdown))
        .max(1);
    Line::from(vec![
        Span::raw(left),
        Span::raw(" ".repeat(pad_len)),
        Span::styled(countdown, Style::default().fg(color)),
    ])
}

// ---------------------------------------------------------------------------
// Rendering: terminal-too-small and confirmation screens
// ---------------------------------------------------------------------------

fn draw_too_small(frame: &mut Frame, area: Rect) {
    // R-31-16-26/27: three lines, print as many as fit, from the top, and no
    // part of any credential or phone row.
    let lines = ["pane too small", "enlarge the terminal", "q quit"];
    let take = (area.height as usize).min(lines.len());
    let text: Vec<Line<'static>> = lines[..take]
        .iter()
        .map(|line| Line::styled((*line).to_string(), Style::default()))
        .collect();
    frame.render_widget(Paragraph::new(text), area);
}

fn draw_confirm(frame: &mut Frame, area: Rect, question: &str) {
    // R-31-16-32: a cleared screen with one question that wraps rather than
    // clips, so the affected-phone count always reads.
    let paragraph = Paragraph::new(Line::styled(question.to_string(), Style::default()))
        .wrap(Wrap { trim: false });
    frame.render_widget(paragraph, area);
}

// ---------------------------------------------------------------------------
// Rendering: the normal screen (R-31-16-25, R-31-16-26)
// ---------------------------------------------------------------------------

fn floor_rows(pairing_open: bool) -> u16 {
    if pairing_open {
        PAIRING_FLOOR_ROWS
    } else {
        IDLE_FLOOR_ROWS
    }
}

/// Draws one frame from `app`'s current state at `now` (the pairing
/// countdown's monotonic clock) and `wall_now` (real time, for the stored
/// RFC 3339 timestamps). Also updates `app.table_visible` for the next key
/// event (R-31-16-29).
fn draw(frame: &mut Frame, app: &mut App, now: Instant, wall_now: OffsetDateTime) {
    let area = frame.area();

    // R-30-600: "a yellow notice line that clears on the next redraw."
    // Clear a notice that was already shown on a prior draw call, before
    // this frame decides what (if anything) to show.
    if app.notice_shown {
        app.notice = None;
        app.notice_shown = false;
    }

    let pairing_open_before = app.pairing_open();
    if area.width < FLOOR_COLS || area.height < floor_rows(pairing_open_before) {
        draw_too_small(frame, area);
        app.table_visible = false;
        mark_notice_shown(app);
        return;
    }

    if let Some(pending) = app.confirm.clone() {
        draw_confirm(frame, area, &pending.question());
        mark_notice_shown(app);
        return;
    }

    // R-10-066: when the bridge is not running the pane shows the exact
    // notice and no pairing surface. (A never-refreshed pane is the same
    // surface: there is no status to draw.)
    if app.bridge_down || app.status.is_none() {
        let top = vec![
            Line::styled("herdr relay".to_string(), Style::default().fg(Color::Cyan)),
            Line::default(),
            Line::styled(
                control::not_running_notice().to_string(),
                Style::default().fg(Color::Yellow),
            ),
        ];
        let bottom = vec![
            Line::default(),
            Line::styled("q quit".to_string(), meta_style()),
        ];
        // The notice is 79 cells, wider than a 72-column pane: it wraps
        // (R-31-16-32's wrap-not-clip rule applies to a state line too).
        let notice_rows = wrap_at_spaces(control::not_running_notice(), area.width as usize)
            .len()
            .max(1) as u16;
        let chunks = Layout::vertical([
            Constraint::Length(2 + notice_rows),
            Constraint::Min(0),
            Constraint::Length(bottom.len() as u16),
        ])
        .split(area);
        frame.render_widget(Paragraph::new(top).wrap(Wrap { trim: false }), chunks[0]);
        frame.render_widget(Paragraph::new(bottom), chunks[2]);
        app.table_visible = false;
        mark_notice_shown(app);
        return;
    }

    let pairing_view = app.pairing_view(now);
    // R-31-16-05: the credential hides the instant the countdown reaches
    // zero; the bridge destroys the pairing on its own clock (R-13-022) and
    // the next poll confirms it, so this is a local hide plus one notice.
    if app.pairing_open() && pairing_view.is_none() && !app.expiry_noticed {
        app.expiry_noticed = true;
        app.set_notice("phrase expired - press p for a new one");
    }
    let pairing_open = pairing_view.is_some();
    let has_credential = pairing_view
        .as_ref()
        .is_some_and(|view| view.credential.is_some());

    let devices: Vec<control::DeviceRow> = app.devices().to_vec();
    let link = &app
        .status
        .as_ref()
        .expect("the bridge-down surface returned already")
        .link;
    let stopped = link.state == LinkState::Stopped;
    let use_empty_message =
        devices.is_empty() && !pairing_open && !stopped && link.state == LinkState::Idle;

    let detail_kind: Option<DetailKind<'_>> = if stopped {
        Some(DetailKind::Stopped)
    } else if link.state == LinkState::Offline {
        Some(DetailKind::Offline {
            error: link.error.as_deref().unwrap_or("connect failed"),
            attempt: link.attempt,
        })
    } else if !use_empty_message {
        app.selected_device().map(DetailKind::Selected)
    } else {
        None
    };

    let idle_hint = !pairing_open
        && !stopped
        && !use_empty_message
        && !devices.is_empty()
        && app
            .status
            .as_ref()
            .is_some_and(|status| status.link.state == LinkState::Idle);

    // --- Decide which droppable regions fit (R-31-16-25, R-31-16-26) -----
    let title_h: u16 = 2;
    let pair_header_h: u16 = if pairing_open { 2 } else { 0 };
    let footer_h: u16 = 2;
    let notice_h: u16 = if app.notice.is_some() || idle_hint {
        1
    } else {
        0
    };
    let empty_message_h: u16 = if use_empty_message { 2 } else { 0 };

    let qr_dims = pairing_view
        .as_ref()
        .and_then(|view| view.credential.as_ref())
        .and_then(|credential| credential.qr.as_ref())
        .map(|qr| qr_region_size(qr.width));
    let qr_cols_fit = qr_dims.is_some_and(|(cols, _)| cols <= area.width);

    let mut include_qr = pairing_open && qr_cols_fit;
    let mut include_detail = detail_kind.is_some();
    let mut include_table = !devices.is_empty() && !use_empty_message;

    let total_height = |include_qr: bool, include_detail: bool, include_table: bool| -> u16 {
        let qr_h = if include_qr {
            qr_dims.map(|(_, rows)| rows).unwrap_or(0)
        } else {
            0
        };
        let credential_h: u16 = if pairing_open {
            if has_credential {
                // hint + relay + computer + phrase + the copy hint line
                // (R-31-16-34), +1 more when the QR is absent (its blank
                // stand-in).
                5 + if include_qr { 0 } else { 1 }
            } else {
                // The `registering...` line alone (R-31-16-38): no QR, no
                // credential, until the bridge reports the registration.
                1
            }
        } else {
            0
        };
        let table_header_h: u16 = if include_table { 2 } else { 0 };
        let detail_h: u16 = if include_detail { 3 } else { 0 };
        title_h
            + pair_header_h
            + qr_h
            + credential_h
            + empty_message_h
            + table_header_h
            + detail_h
            + footer_h
            + notice_h
    };

    loop {
        if total_height(include_qr, include_detail, include_table) <= area.height {
            break;
        }
        if include_qr {
            include_qr = false;
        } else if include_detail {
            include_detail = false;
        } else if include_table {
            include_table = false;
        } else {
            break;
        }
    }

    // --- Build content ------------------------------------------------
    let mut top: Vec<Line<'static>> = title_lines(app);
    if pairing_open {
        let view = pairing_view
            .as_ref()
            .expect("pairing_open implies pairing_view is Some");
        top.push(Line::default());
        top.push(pair_header_line(view.remaining, area.width));
        match &view.credential {
            None => {
                // R-10-064/R-31-16-38: the credential fields stay null until
                // the relay accepted the registration, so the pane shows
                // `registering...` and nothing else.
                top.push(Line::styled("  registering...".to_string(), meta_style()));
            }
            Some(credential) => {
                if include_qr && let Some(qr) = &credential.qr {
                    top.extend(qr_lines(qr));
                } else {
                    top.push(Line::default());
                }
                let hint = if include_qr {
                    "or type these in on the phone:"
                } else if credential.qr.is_none() {
                    // The mockup's URI-too-long state: no QR, but the words
                    // are the credential and still print.
                    "no qr for this address - type the words in instead"
                } else {
                    "no room for the qr code. type these in on the phone:"
                };
                top.push(Line::styled(format!("  {hint}"), Style::default()));
                let origin = app
                    .status
                    .as_ref()
                    .map(|status| status.relay_origin.clone())
                    .filter(|origin| !origin.trim().is_empty())
                    .unwrap_or_else(|| "(not configured)".to_string());
                top.extend(credential_lines("relay", &origin, area.width));
                top.extend(credential_lines("computer", &credential.handle, area.width));
                top.extend(credential_lines("phrase", &credential.words, area.width));
                // R-31-16-34: the copy hint prints under the credential block
                // in every pairing layout, so `c` is discoverable exactly
                // where the wrapped credential block makes drag-select
                // useless.
                top.push(Line::styled(
                    "press c to copy the pairing link".to_string(),
                    meta_style(),
                ));
            }
        }
    }
    if use_empty_message {
        top.push(Line::default());
        top.push(Line::styled(
            "no phones yet - press p to pair one.".to_string(),
            Style::default(),
        ));
    }
    if include_table {
        top.push(Line::default());
        top.push(table_header_line(area.width));
    }

    let mut bottom: Vec<Line<'static>> = Vec::new();
    if include_detail && let Some(kind) = &detail_kind {
        bottom.push(Line::default());
        bottom.extend(detail_lines(kind, wall_now));
    }
    bottom.push(Line::default());
    let availability = FooterAvailability {
        scroll: include_table && devices.len() > 1,
        // R-31-16-34 lists `c copy` while a session is open; while the
        // pairing is still registering there is no URI to copy (R-10-064),
        // so the binding waits for the credential like the block does.
        copy: has_credential,
        remove_one: include_table && !devices.is_empty(),
        remove_all: !devices.is_empty(),
    };
    bottom.push(footer_line(&availability, area.width));
    if let Some(notice) = &app.notice {
        bottom.push(Line::styled(
            notice.clone(),
            Style::default().fg(Color::Yellow),
        ));
    } else if idle_hint {
        bottom.push(Line::styled(
            "press p to pair another phone".to_string(),
            Style::default(),
        ));
    }

    let top_h = top.len() as u16;
    let bottom_h = bottom.len() as u16;
    let chunks = Layout::vertical([
        Constraint::Length(top_h),
        Constraint::Min(0),
        Constraint::Length(bottom_h),
    ])
    .split(area);

    frame.render_widget(Paragraph::new(top), chunks[0]);

    app.table_visible = include_table;
    if include_table {
        let table_rect = chunks[1];
        let visible = table_rect.height as usize;
        let window = visible_window(devices.len(), visible, app.selected);
        let rows: Vec<Line<'static>> = devices[window.clone()]
            .iter()
            .enumerate()
            .map(|(offset, device)| {
                let index = window.start + offset;
                let row_state = RowState::compute(
                    &app.status
                        .as_ref()
                        .expect("the bridge-down surface returned already")
                        .link,
                    device.connected,
                );
                row_line(
                    device,
                    row_state,
                    index == app.selected,
                    area.width,
                    wall_now,
                )
            })
            .collect();
        frame.render_widget(Paragraph::new(rows), table_rect);
    }

    if app.loading {
        frame.render_widget(
            Paragraph::new(Line::styled("loading...".to_string(), meta_style())),
            chunks[0],
        );
    }

    frame.render_widget(Paragraph::new(bottom).wrap(Wrap { trim: false }), chunks[2]);
    mark_notice_shown(app);
}

/// Marks `app.notice` as having been shown on this redraw, if it is
/// present, so `draw`'s own next call clears it (R-30-600).
fn mark_notice_shown(app: &mut App) {
    if app.notice.is_some() {
        app.notice_shown = true;
    }
}

// ---------------------------------------------------------------------------
// Rendering entry points (R-31-16-06: `--once` renders one pass, no terminal
// needed — this is also this pane's own test seam)
// ---------------------------------------------------------------------------

/// Renders one frame into an in-memory buffer. No real terminal is touched;
/// this is the function both `--once` and this module's own tests use.
pub fn render_to_buffer(
    app: &mut App,
    area: Rect,
    now: Instant,
    wall_now: OffsetDateTime,
) -> Buffer {
    let backend = TestBackend::new(area.width, area.height);
    let mut terminal = Terminal::new(backend).expect("TestBackend sizing never fails");
    terminal
        .draw(|frame| draw(frame, app, now, wall_now))
        .expect("drawing into an in-memory TestBackend cannot fail");
    terminal.backend().buffer().clone()
}

/// One printed line per buffer row, trailing spaces trimmed.
pub fn buffer_lines(buffer: &Buffer) -> Vec<String> {
    let area = buffer.area();
    (0..area.height)
        .map(|y| {
            let mut line = String::new();
            for x in 0..area.width {
                line.push_str(buffer[(area.x + x, area.y + y)].symbol());
            }
            line.trim_end().to_string()
        })
        .collect()
}

/// R-31-16-06's default `--once` size: 72 columns (this document's own
/// worked width) by 47 rows (its own worked full-pairing-layout height, one
/// row more since the copy hint line of R-31-16-34 joined the credential
/// block), so the default invocation demonstrates the full layout, not the
/// compact one.
pub const DEFAULT_ONCE_WIDTH: u16 = 72;
pub const DEFAULT_ONCE_HEIGHT: u16 = 47;

/// `--once`: renders the bridge's current status exactly once and prints it
/// (R-31-16-06: "how a test asserts the output without a terminal" — this
/// never touches `crossterm`'s real terminal APIs at all). It opens no
/// pairing and writes nothing: a read-only snapshot. The test half of this
/// flag is `tests/popup_once.rs`, which renders the same [`App`] through an
/// injected status source (R-10-066) and decodes the QR against the
/// fixture's `uri`.
pub fn run_once(width: u16, height: u16) -> Result<(), PopupError> {
    let mut app = App::load_live()?;
    let buffer = render_to_buffer(
        &mut app,
        Rect::new(0, 0, width, height),
        Instant::now(),
        OffsetDateTime::now_utc(),
    );
    let mut stdout = std::io::stdout();
    for line in buffer_lines(&buffer) {
        writeln!(stdout, "{line}")?;
    }
    stdout.flush()?;
    Ok(())
}

/// The interactive pane. Enters the alternate screen and raw mode, redraws
/// on every key press and on resize (R-31-16-31: resize redraws from the
/// held snapshot, never reloads), and restores the terminal on exit.
///
/// This workstation has no way to drive a real interactive pty end to end
/// this session (see the module doc comment); this function is verified
/// structurally only — [`App::handle_key`] is exercised directly by this
/// module's own tests, decoupled from `crossterm::event`.
pub fn run() -> Result<(), PopupError> {
    let mut app = App::load_live()?;
    enable_raw_mode()?;
    let mut stdout = std::io::stdout();
    crossterm::execute!(stdout, EnterAlternateScreen)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let result = run_loop(&mut terminal, &mut app);

    disable_raw_mode()?;
    crossterm::execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    result
}

fn run_loop(
    terminal: &mut Terminal<CrosstermBackend<std::io::Stdout>>,
    app: &mut App,
) -> Result<(), PopupError> {
    // R-31-16-07 lets the pane reload after a write or `f`; the pairing
    // countdown and the link state still need a tick, so the pane also polls
    // the bridge every 500 ms while a pairing is open and every 2 s
    // otherwise (the mockup's cadence note). The countdown itself counts
    // down locally from `expires_in_s` between polls, so a poll never moves
    // it backwards.
    let mut last_refresh = Instant::now();
    loop {
        let now = Instant::now();
        let wall_now = OffsetDateTime::now_utc();
        terminal.draw(|frame| draw(frame, app, now, wall_now))?;
        let cadence = if app.pairing_open() {
            Duration::from_millis(500)
        } else {
            Duration::from_secs(2)
        };
        if last_refresh.elapsed() >= cadence {
            app.refresh();
            last_refresh = Instant::now();
        }
        if !event::poll(Duration::from_millis(200))? {
            continue;
        }
        if let Event::Key(key_event) = event::read()?
            && key_event.kind == KeyEventKind::Press
            && app.handle_key(key_event.code, Instant::now())? == KeyOutcome::Quit
        {
            return Ok(());
        }
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Mutex};

    /// The mockup's worked-example origin, reused as the fixture origin.
    const ORIGIN: &str = "https://relay.example.com";
    /// The fixture handle: the mockup's own 22-character worked example.
    const HANDLE: &str = "n6Loxf94CfyIO6hOxlaHvA";
    /// The fixture phrase (display form): six fixed words, matching the
    /// synthetic-wordlist convention `pairing.rs`'s own tests use (R-13-025
    /// forbids the real EFF list even in a fixture).
    const PHRASE: &str = "remedy tapestry hubcap oversleep jailbird kinetic";

    /// The fixture pairing URI, built with the one shared builder so the QR
    /// the pane encodes decodes to exactly this string.
    fn pairing_uri_fixture() -> String {
        herdr_relay_proto::handle::PairingUri {
            relay_origin: ORIGIN.to_string(),
            handle: HANDLE.parse().expect("the fixture handle parses"),
            phrase: PHRASE.replace(' ', "-"),
        }
        .build()
    }

    fn link(state: LinkState) -> control::LinkStatus {
        control::LinkStatus {
            state,
            attempt: 0,
            error: None,
        }
    }

    fn offline_link(error: &str, attempt: u32) -> control::LinkStatus {
        control::LinkStatus {
            state: LinkState::Offline,
            attempt,
            error: Some(error.to_string()),
        }
    }

    /// A registered pairing fixture (R-10-064: the credential fields are
    /// present only once `registered` is true).
    fn registered_pairing(expires_in_s: u64) -> control::PairingStatus {
        control::PairingStatus {
            registered: true,
            uri: Some(pairing_uri_fixture()),
            phrase: Some(PHRASE.to_string()),
            handle: Some(HANDLE.to_string()),
            expires_in_s,
        }
    }

    fn device_row(
        device_id: &str,
        name: &str,
        platform: Platform,
        os_version: &str,
        connected: bool,
    ) -> control::DeviceRow {
        control::DeviceRow {
            device_id: device_id.to_string(),
            device_name: name.to_string(),
            platform,
            os_version: os_version.to_string(),
            fingerprint: "3f9a-1c04-be77-20d5".to_string(),
            paired_at: "2026-08-22T17:02:00Z".to_string(),
            last_seen: "2026-08-24T09:14:00Z".to_string(),
            connected,
        }
    }

    fn pixel(connected: bool) -> control::DeviceRow {
        device_row(
            "device-1",
            "pixel-8-pat",
            Platform::Android,
            "15",
            connected,
        )
    }

    fn iphone(connected: bool) -> control::DeviceRow {
        device_row(
            "device-2",
            "iphone-15-pat",
            Platform::Ios,
            "18.5",
            connected,
        )
    }

    fn thinkpad(connected: bool) -> control::DeviceRow {
        device_row(
            "device-3",
            "thinkpad-x1",
            Platform::Android,
            "15",
            connected,
        )
    }

    fn base_status(devices: Vec<control::DeviceRow>, link: control::LinkStatus) -> control::Status {
        control::Status {
            relay_origin: ORIGIN.to_string(),
            link,
            pairing: None,
            devices,
        }
    }

    /// A fake bridge behind the two injected seams: the status source clones
    /// a shared status; the command sink records every command and applies
    /// it to that shared status the way the real bridge would (R-10-064), so
    /// the refresh that follows a write observes its effect.
    struct Fixture {
        status: Arc<Mutex<control::Status>>,
        commands: Arc<Mutex<Vec<Command>>>,
    }

    impl Fixture {
        fn new(status: control::Status) -> Self {
            Self {
                status: Arc::new(Mutex::new(status)),
                commands: Arc::new(Mutex::new(Vec::new())),
            }
        }

        fn app(&self) -> App {
            let source_status = Arc::clone(&self.status);
            let sink_status = Arc::clone(&self.status);
            let commands = Arc::clone(&self.commands);
            let mut app = App::with_sources(
                Box::new(move || Ok(source_status.lock().expect("fixture lock").clone())),
                Box::new(move |command: &Command| {
                    commands
                        .lock()
                        .expect("commands lock")
                        .push(command.clone());
                    let mut status = sink_status.lock().expect("fixture lock");
                    match command {
                        Command::Revoke { device_id } => {
                            status.devices.retain(|row| row.device_id != *device_id);
                        }
                        Command::RevokeAll => status.devices.clear(),
                        Command::Stop => status.link.state = LinkState::Stopped,
                        Command::ClosePairing => status.pairing = None,
                        Command::OpenPairing => {
                            status
                                .pairing
                                .get_or_insert_with(|| registered_pairing(600));
                            if status.link.state == LinkState::Stopped {
                                status.link.state = LinkState::Idle;
                            }
                        }
                        Command::Status => {}
                    }
                    Ok(serde_json::json!({}))
                }),
            );
            app.refresh();
            app
        }

        fn commands(&self) -> Vec<Command> {
            self.commands.lock().expect("commands lock").clone()
        }

        fn mutate(&self, f: impl FnOnce(&mut control::Status)) {
            f(&mut self.status.lock().expect("fixture lock"));
        }
    }

    fn fixture_app(status: control::Status) -> (Fixture, App) {
        let fixture = Fixture::new(status);
        let app = fixture.app();
        (fixture, app)
    }

    fn render(app: &mut App, width: u16, height: u16, now: Instant) -> Vec<String> {
        let buffer = render_to_buffer(
            app,
            Rect::new(0, 0, width, height),
            now,
            OffsetDateTime::now_utc(),
        );
        buffer_lines(&buffer)
    }

    // -- R-31-16-06: --once-equivalent rendering --------------------------

    #[test]
    fn empty_state_shows_the_hint_and_no_table() {
        let (_fixture, mut app) = fixture_app(base_status(vec![], link(LinkState::Idle)));
        let lines = render(&mut app, 72, 46, Instant::now());
        assert!(lines[0].starts_with("herdr relay (0 phones)"));
        assert!(
            lines
                .iter()
                .any(|l| l.contains("no phones yet - press p to pair one."))
        );
        assert!(!lines.iter().any(|l| l.contains("Phone")));
    }

    #[test]
    fn idle_state_lists_devices_with_a_fingerprint_and_a_hint() {
        let (_fixture, mut app) =
            fixture_app(base_status(vec![pixel(false)], link(LinkState::Idle)));
        let lines = render(&mut app, 72, 46, Instant::now());
        assert!(lines[0].starts_with("herdr relay (1 phone)"));
        assert!(lines.iter().any(|l| l.contains("pixel-8-pat")));
        assert!(lines.iter().any(|l| l.trim_start().starts_with("key ")));
        assert!(
            lines
                .iter()
                .any(|l| l.contains("press p to pair another phone"))
        );
    }

    #[test]
    fn opening_a_pairing_session_shows_qr_words_origin_and_handle_full_layout() {
        let mut status = base_status(vec![pixel(false)], link(LinkState::Idle));
        status.pairing = Some(registered_pairing(600));
        let (_fixture, mut app) = fixture_app(status);
        let now = Instant::now();
        app.refresh_at(now);
        let lines = render(&mut app, DEFAULT_ONCE_WIDTH, DEFAULT_ONCE_HEIGHT, now);
        let text = lines.join("\n");
        assert!(text.contains("pair a phone"));
        assert!(
            text.contains("expires in 10:00"),
            "the countdown starts at the full 600s lifetime"
        );
        assert!(text.contains("relay:"));
        assert!(text.contains(ORIGIN));
        assert!(text.contains("computer:"));
        assert!(text.contains(HANDLE), "the 22-character handle prints");
        assert!(text.contains("phrase:"));
        for word in PHRASE.split(' ') {
            assert!(text.contains(word), "the phrase word {word} prints");
        }
        // R-31-16-02: a QR glyph row is present (half-block characters).
        assert!(
            lines
                .iter()
                .any(|l| l.contains('█') || l.contains('▀') || l.contains('▄'))
        );
        // R-31-16-13: never a bare numeric pairing code.
        assert!(!text.contains("code: "));
    }

    #[test]
    fn compact_layout_drops_the_qr_but_keeps_the_credential_as_text() {
        let mut status = base_status(vec![], link(LinkState::Idle));
        status.pairing = Some(registered_pairing(600));
        let (_fixture, mut app) = fixture_app(status);
        let now = Instant::now();
        let lines = render(&mut app, 72, PAIRING_FLOOR_ROWS, now);
        let text = lines.join("\n");
        assert!(text.contains("no room for the qr code"));
        assert!(text.contains(ORIGIN));
        assert!(text.contains("computer:"));
        assert!(text.contains("phrase:"));
        assert!(
            !lines.iter().any(|l| l.contains('█')),
            "the QR region must be dropped whole"
        );
    }

    #[test]
    fn terminal_below_the_floor_shows_only_the_too_small_state() {
        let (_fixture, mut app) = fixture_app(base_status(vec![], link(LinkState::Idle)));
        let lines = render(&mut app, 20, 4, Instant::now());
        let text = lines.join("\n");
        assert!(text.contains("pane too small"));
        assert!(
            !text.contains("herdr relay"),
            "no credential or content prints below the floor"
        );
    }

    // -- R-10-064/R-31-16-38: no credential before `registered` -----------

    #[test]
    fn a_registering_pairing_shows_no_credential_no_qr_and_no_copy_key() {
        let mut status = base_status(vec![pixel(false)], link(LinkState::Idle));
        status.pairing = Some(control::PairingStatus {
            registered: false,
            uri: None,
            phrase: None,
            handle: None,
            expires_in_s: 600,
        });
        let (_fixture, mut app) = fixture_app(status);
        let lines = render(
            &mut app,
            DEFAULT_ONCE_WIDTH,
            DEFAULT_ONCE_HEIGHT,
            Instant::now(),
        );
        let text = lines.join("\n");
        assert!(text.contains("pair a phone"), "the section header prints");
        assert!(text.contains("registering..."));
        assert!(!text.contains("phrase:"), "no credential yet (R-10-064)");
        assert!(!text.contains(HANDLE));
        assert!(
            !lines.iter().any(|l| l.contains('█') || l.contains('▀')),
            "no QR before the relay accepted the registration"
        );
        let footer = lines
            .iter()
            .find(|l| l.contains("q quit"))
            .expect("a footer");
        assert!(
            !footer.contains("c copy"),
            "no URI to copy while registering"
        );
    }

    // -- R-10-066: the bridge-not-running surface -------------------------

    #[test]
    fn a_bridge_that_is_not_running_shows_the_exact_notice_and_no_pairing_surface() {
        let mut app = App::with_sources(
            Box::new(|| Err(ClientError::NotRunning)),
            Box::new(|_| Err(ClientError::NotRunning)),
        );
        app.refresh();
        let lines = render(&mut app, 72, 46, Instant::now());
        let text = lines.join("\n");
        // The notice is 79 cells, so at 72 columns it wraps: compare with
        // the whitespace normalised (R-31-16-32's wrap-not-clip rule).
        let flat = text.split_whitespace().collect::<Vec<_>>().join(" ");
        assert!(flat.contains(control::not_running_notice()));
        assert!(!text.contains("pair a phone"), "no pairing surface");
        assert!(!text.contains("p pair"), "no pairing key either");
        assert!(text.contains("q quit"));
        // `p` against a dead bridge must not panic and must not draw one.
        app.handle_key(KeyCode::Char('p'), Instant::now())
            .expect("handle p");
        let lines = render(&mut app, 72, 46, Instant::now());
        let flat = lines
            .join("\n")
            .split_whitespace()
            .collect::<Vec<_>>()
            .join(" ");
        assert!(flat.contains(control::not_running_notice()));
    }

    // -- R-31-16-05: hide credentials the instant pairing ends -----------

    #[test]
    fn q_ends_an_open_pairing_session_instantly() {
        let mut status = base_status(vec![], link(LinkState::Idle));
        status.pairing = Some(registered_pairing(600));
        let (fixture, mut app) = fixture_app(status);
        assert!(app.pairing_open());
        let outcome = app
            .handle_key(KeyCode::Char('q'), Instant::now())
            .expect("handle q");
        assert_eq!(outcome, KeyOutcome::Quit);
        assert_eq!(
            fixture.commands(),
            vec![Command::ClosePairing],
            "R-10-066: q sends close_pairing, then quits"
        );
        assert!(
            !app.pairing_open(),
            "R-31-16-05: q ends the pairing session instantly"
        );
    }

    #[test]
    fn a_phrase_past_its_lifetime_is_cleared_on_the_next_draw() {
        let mut status = base_status(vec![], link(LinkState::Idle));
        status.pairing = Some(registered_pairing(600));
        let (_fixture, mut app) = fixture_app(status);
        let start = Instant::now();
        app.refresh_at(start);
        let too_late = start + Duration::from_secs(601);
        let lines = render(&mut app, 72, 46, too_late);
        let text = lines.join("\n");
        assert!(
            !text.contains("phrase:"),
            "R-31-16-05: expiry hides the session too"
        );
        assert!(!text.contains(HANDLE));
        assert_eq!(
            app.notice.as_deref(),
            Some("phrase expired - press p for a new one")
        );
    }

    #[test]
    fn a_spent_phrase_shows_the_spent_notice_on_the_next_poll() {
        // R-13-023: the third failed attempt destroys the phrase and the
        // handle with no replacement, so the next poll answer drops
        // `pairing` while the local countdown still had time on it.
        let mut status = base_status(vec![], link(LinkState::Idle));
        status.pairing = Some(registered_pairing(600));
        let (fixture, mut app) = fixture_app(status);
        let now = Instant::now();
        app.refresh_at(now);

        fixture.mutate(|status| status.pairing = None);
        app.refresh_at(now + Duration::from_secs(5));

        assert!(!app.pairing_open());
        assert_eq!(
            app.notice.as_deref(),
            Some("phrase spent - press p for a new one")
        );
    }

    #[test]
    fn a_successful_pair_shows_no_spent_notice() {
        // The device list grew: the pairing ended by enrolment, not by the
        // three-attempt limit, so no spent notice may print.
        let mut status = base_status(vec![], link(LinkState::Idle));
        status.pairing = Some(registered_pairing(600));
        let (fixture, mut app) = fixture_app(status);
        let now = Instant::now();
        app.refresh_at(now);

        fixture.mutate(|status| {
            status.pairing = None;
            status.devices.push(pixel(true));
        });
        app.refresh_at(now + Duration::from_secs(5));

        assert_eq!(app.notice, None);
    }

    #[test]
    fn the_countdown_turns_yellow_at_sixty_seconds_remaining() {
        // The mockup's callout 3: bright black until 60 seconds remain,
        // then ANSI yellow.
        let countdown_span = |remaining: u64| {
            pair_header_line(Duration::from_secs(remaining), 72)
                .spans
                .last()
                .expect("the countdown span")
                .clone()
        };
        assert_eq!(
            countdown_span(600).content,
            "expires in 10:00",
            "the countdown starts at the full 600s lifetime"
        );
        assert_eq!(countdown_span(61).style.fg, Some(Color::DarkGray));
        assert_eq!(countdown_span(60).style.fg, Some(Color::Yellow));
    }

    // -- R-30-600: the notice line clears on the next redraw --------------

    #[test]
    fn a_notice_shows_for_exactly_one_redraw_then_clears() {
        let (_fixture, mut app) =
            fixture_app(base_status(vec![pixel(false)], link(LinkState::Idle)));
        let _ = render(&mut app, 72, 46, Instant::now());
        app.handle_key(KeyCode::Char('d'), Instant::now())
            .expect("handle d");
        app.handle_key(KeyCode::Char('y'), Instant::now())
            .expect("confirm y");
        assert_eq!(app.notice.as_deref(), Some("pixel-8-pat lost access"));

        // The redraw right after the action still shows it (R-30-600: a
        // notice prints "after an action").
        let first = render(&mut app, 72, 46, Instant::now());
        assert!(
            first.iter().any(|l| l.contains("pixel-8-pat lost access")),
            "the notice shows on the redraw right after the action"
        );
        assert_eq!(app.notice.as_deref(), Some("pixel-8-pat lost access"));

        // The *next* redraw, with no intervening action, clears it.
        let second = render(&mut app, 72, 46, Instant::now());
        assert!(
            !second.iter().any(|l| l.contains("lost access")),
            "R-30-600: the notice MUST clear on the next redraw"
        );
        assert_eq!(app.notice, None);

        // It stays clear on every redraw after that too, not just the one
        // right after.
        let third = render(&mut app, 72, 46, Instant::now());
        assert!(!third.iter().any(|l| l.contains("lost access")));
    }

    #[test]
    fn a_fresh_notice_set_after_the_first_clears_gets_its_own_one_redraw_showing() {
        let (_fixture, mut app) = fixture_app(base_status(
            vec![pixel(false), iphone(false)],
            link(LinkState::Idle),
        ));
        let _ = render(&mut app, 72, 46, Instant::now());

        app.handle_key(KeyCode::Char('d'), Instant::now())
            .expect("handle d");
        app.handle_key(KeyCode::Char('y'), Instant::now())
            .expect("confirm y");
        let _ = render(&mut app, 72, 46, Instant::now()); // shows notice 1
        let _ = render(&mut app, 72, 46, Instant::now()); // clears it
        assert_eq!(app.notice, None);

        // A second, later action's notice still gets its own full showing —
        // the earlier clear must not have left it permanently disabled.
        app.handle_key(KeyCode::Char('d'), Instant::now())
            .expect("handle d");
        app.handle_key(KeyCode::Char('y'), Instant::now())
            .expect("confirm y");
        let showing = render(&mut app, 72, 46, Instant::now());
        assert!(
            showing
                .iter()
                .any(|l| l.contains("iphone-15-pat lost access")),
            "a later notice still shows on its own next redraw"
        );
    }

    // -- R-31-16-29: no selection may exist that was not drawn ------------

    #[test]
    fn up_down_and_d_do_nothing_when_no_row_is_drawn() {
        let (_fixture, mut app) = fixture_app(base_status(vec![], link(LinkState::Idle)));
        // table_visible defaults false until a draw happens.
        let outcome = app
            .handle_key(KeyCode::Char('d'), Instant::now())
            .expect("handle d");
        assert_eq!(outcome, KeyOutcome::Continue);
        assert!(app.confirm.is_none(), "d must do nothing with no drawn row");
    }

    #[test]
    fn r_does_nothing_when_the_stored_list_is_empty() {
        let (_fixture, mut app) = fixture_app(base_status(vec![], link(LinkState::Idle)));
        app.handle_key(KeyCode::Char('r'), Instant::now())
            .expect("handle r");
        assert!(app.confirm.is_none());
    }

    // -- R-31-16-09, R-31-16-32: confirmations ----------------------------

    #[test]
    fn d_asks_a_yn_question_with_the_exact_device_name_and_y_sends_revoke() {
        let (fixture, mut app) =
            fixture_app(base_status(vec![pixel(false)], link(LinkState::Idle)));
        let _ = render(&mut app, 72, 46, Instant::now());
        assert!(app.table_visible);
        app.handle_key(KeyCode::Char('d'), Instant::now())
            .expect("handle d");
        let question = app
            .confirm
            .as_ref()
            .expect("d opens a confirmation")
            .question();
        assert_eq!(question, "remove pixel-8-pat? 1 phone loses access. y/n");
        app.handle_key(KeyCode::Char('y'), Instant::now())
            .expect("confirm y");
        assert_eq!(
            fixture.commands(),
            vec![Command::Revoke {
                device_id: "device-1".to_string()
            }],
            "R-10-066: d maps to `revoke` with the exact device id"
        );
        assert!(app.devices().is_empty());
        assert_eq!(app.notice.as_deref(), Some("pixel-8-pat lost access"));
    }

    #[test]
    fn any_other_key_cancels_a_confirmation_including_q_and_esc() {
        let (_fixture, mut app) =
            fixture_app(base_status(vec![pixel(false)], link(LinkState::Idle)));
        let _ = render(&mut app, 72, 46, Instant::now());
        app.handle_key(KeyCode::Char('d'), Instant::now())
            .expect("handle d");
        assert!(app.confirm.is_some());
        let outcome = app
            .handle_key(KeyCode::Esc, Instant::now())
            .expect("esc cancels");
        assert_eq!(
            outcome,
            KeyOutcome::Continue,
            "esc cancels the question, it does not quit"
        );
        assert!(app.confirm.is_none());
        assert_eq!(app.devices().len(), 1, "the device was not removed");
    }

    #[test]
    fn r_reports_the_exact_count_and_sends_revoke_all() {
        let (fixture, mut app) = fixture_app(base_status(
            vec![pixel(false), iphone(false)],
            link(LinkState::Idle),
        ));
        app.handle_key(KeyCode::Char('r'), Instant::now())
            .expect("handle r");
        let question = app
            .confirm
            .as_ref()
            .expect("r opens a confirmation")
            .question();
        assert_eq!(
            question,
            "remove every phone? 2 phones lose access at once. y/n"
        );
        app.handle_key(KeyCode::Char('y'), Instant::now())
            .expect("confirm y");
        assert_eq!(
            fixture.commands(),
            vec![Command::RevokeAll],
            "R-10-066: r maps to `revoke_all`"
        );
        assert!(app.devices().is_empty());
        assert_eq!(app.notice.as_deref(), Some("every phone lost access"));
        // R-10-064's `revoke_all` mints nothing (the bridge rotates the
        // keypair, R-13-056 step 4); a new pairing is the pane's `p`.
        assert!(!app.pairing_open());
    }

    #[test]
    fn s_stops_the_bridge_without_clearing_an_open_pairing() {
        let mut status = base_status(vec![], link(LinkState::Idle));
        status.pairing = Some(registered_pairing(600));
        let (fixture, mut app) = fixture_app(status);
        let now = Instant::now();
        app.handle_key(KeyCode::Char('s'), now).expect("handle s");
        let question = app
            .confirm
            .as_ref()
            .expect("s opens a confirmation")
            .question();
        assert_eq!(
            question,
            "stop the relay? this phone list is kept, and no phone can connect. y/n"
        );
        app.handle_key(KeyCode::Char('y'), now).expect("confirm y");
        assert_eq!(fixture.commands(), vec![Command::Stop]);
        assert!(app.stopped(), "the refreshed status reads stopped");
        assert!(
            app.pairing_open(),
            "R-31-16-24/R-10-064: s MUST NOT clear a pairing"
        );
    }

    // -- R-31-16-15: at most one connected row ----------------------------

    #[test]
    fn at_most_one_row_reads_connected() {
        let (_fixture, mut app) = fixture_app(base_status(
            vec![pixel(true), iphone(false)],
            link(LinkState::Connected),
        ));
        // Width 80: the five-column row is 74 cells, so `connected` (the
        // word this test counts) is only whole past the 72-column mockup
        // width.
        let lines = render(&mut app, 80, 46, Instant::now());
        let connected_rows = lines
            .iter()
            .filter(|l| {
                (l.contains("pixel-8-pat") || l.contains("iphone-15-pat"))
                    && l.trim_end().ends_with("connected")
            })
            .count();
        assert_eq!(connected_rows, 1);
    }

    #[test]
    fn the_connected_word_comes_from_the_bridge_row_not_the_pane() {
        // R-10-064's `devices[].connected` is the only source: a row whose
        // flag is false reads idle even when the link itself is connected.
        let (_fixture, mut app) = fixture_app(base_status(
            vec![pixel(false), iphone(true)],
            link(LinkState::Connected),
        ));
        let lines = render(&mut app, 80, 46, Instant::now());
        let pixel_row = lines
            .iter()
            .find(|l| l.contains("pixel-8-pat"))
            .expect("the pixel row");
        assert!(pixel_row.trim_end().ends_with("idle"));
        let iphone_row = lines
            .iter()
            .find(|l| l.contains("iphone-15-pat"))
            .expect("the iphone row");
        assert!(iphone_row.trim_end().ends_with("connected"));
    }

    // -- R-31-16-16, R-32-704: no delay, cap or total ever prints; colour never the only carrier --

    #[test]
    fn offline_prints_the_attempt_number_only() {
        let (_fixture, mut app) = fixture_app(base_status(
            vec![pixel(false)],
            offline_link("i/o timeout", 4),
        ));
        let lines = render(&mut app, 72, 46, Instant::now());
        let text = lines.join("\n");
        assert!(text.contains("retrying, attempt 4"));
        assert!(
            text.contains("unknown"),
            "R-31-16-19: offline rows read unknown"
        );
        assert!(!text.to_lowercase().contains("delay"));
        assert!(!text.to_lowercase().contains("cap"));
    }

    // -- R-31-16-28: column elision at a fixed budget ----------------------

    #[test]
    fn a_long_device_name_elides_with_one_ellipsis_at_the_column_budget() {
        assert_eq!(
            elide("a very very long device name indeed", 16),
            "a very very lon…"
        );
        assert_eq!(
            cell_width(&elide("a very very long device name indeed", 16)),
            16
        );
        assert_eq!(elide("short", 16), "short");
    }

    // -- R-31-16-27: credential wrapping never breaks a word ----------------

    #[test]
    fn a_handle_that_does_not_fit_inline_moves_to_its_own_row_unbroken() {
        let lines = credential_lines("computer", "n6Loxf94CfyIO6hOxlaHvA", FLOOR_COLS);
        assert_eq!(lines.len(), 2, "label row, then the unbroken value row");
    }

    #[test]
    fn a_long_phrase_wraps_at_spaces_without_breaking_a_word() {
        let phrase = "remedy tapestry hubcap oversleep jailbird kinetics";
        let lines = credential_lines("phrase", phrase, 72);
        for line in &lines {
            let text: String = line.spans.iter().map(|s| s.content.as_ref()).collect();
            for word in phrase.split(' ') {
                assert!(
                    !text.contains(&format!("{word}-")) && !text.ends_with('-'),
                    "must not insert a hyphen at a wrap break"
                );
            }
        }
    }

    // -- R-03-084, R-30-604, R-32-701: no literal RGB colour, brightness
    // detection, or external-process QR encoding in this pane's own
    // production source ----------------------------------------------------

    #[test]
    fn source_has_no_rgb_literal_brightness_detection_or_external_qr_process() {
        // Mirrors `app/test/widgets/theme/no_literals_test.dart`'s static
        // scan pattern rather than adding an analyser dependency
        // (`docs/41-code-standards.md` R-41-042). Scans only the production
        // code above `mod tests`, so this test's own source (which
        // necessarily names the forbidden patterns as strings) can never
        // match itself.
        let source = include_str!("popup.rs");
        let production_source = source
            .split_once("#[cfg(test)]\nmod tests {")
            .expect("this file has a #[cfg(test)] test module")
            .0;
        assert!(
            !production_source.contains("Color::Rgb("),
            "R-32-701/R-03-084: no 24-bit colour literal outside the test module"
        );
        assert!(
            !production_source.contains("Color::Indexed("),
            "R-32-701: no 256-colour literal outside the test module"
        );
        assert!(
            !production_source.to_lowercase().contains("brightness"),
            "R-03-084: no OS-brightness-detection call outside the test module"
        );
        assert!(
            !production_source.contains("Command::new")
                && !production_source.contains("process::Command"),
            "R-30-604: the QR code is encoded in-process, never by spawning an external encoder"
        );
    }

    // -- R-30-601, R-32-700: only the eight basic ANSI colours plus bright
    // black ever reach the rendered buffer, across every state that assigns
    // a colour ---------------------------------------------------------------

    fn assert_colours_are_basic_ansi_or_reset(buffer: &Buffer, context: &str) {
        for cell in &buffer.content {
            for colour in [cell.fg, cell.bg] {
                let allowed = matches!(
                    colour,
                    Color::Reset
                        | Color::Black
                        | Color::Red
                        | Color::Green
                        | Color::Yellow
                        | Color::Blue
                        | Color::Magenta
                        | Color::Cyan
                        | Color::Gray
                        | Color::DarkGray
                );
                assert!(
                    allowed,
                    "R-30-601/R-32-700: {context} used non-basic-ANSI colour {colour:?}"
                );
            }
        }
    }

    #[test]
    fn every_rendered_colour_across_pane_states_is_a_basic_ansi_or_bright_black_variant() {
        let now = Instant::now();

        let (_f1, mut empty) = fixture_app(base_status(vec![], link(LinkState::Idle)));
        let buffer = render_to_buffer(
            &mut empty,
            Rect::new(0, 0, 72, 46),
            now,
            OffsetDateTime::now_utc(),
        );
        assert_colours_are_basic_ansi_or_reset(&buffer, "empty state");

        let (_f2, mut idle) =
            fixture_app(base_status(vec![pixel(true)], link(LinkState::Connected)));
        let buffer = render_to_buffer(
            &mut idle,
            Rect::new(0, 0, 72, 46),
            now,
            OffsetDateTime::now_utc(),
        );
        assert_colours_are_basic_ansi_or_reset(&buffer, "a connected row");

        let (_f3, mut offline) = fixture_app(base_status(
            vec![pixel(false)],
            offline_link("i/o timeout", 1),
        ));
        let buffer = render_to_buffer(
            &mut offline,
            Rect::new(0, 0, 72, 46),
            now,
            OffsetDateTime::now_utc(),
        );
        assert_colours_are_basic_ansi_or_reset(&buffer, "the offline state");

        let mut pairing_status = base_status(vec![], link(LinkState::Idle));
        pairing_status.pairing = Some(registered_pairing(600));
        let (_f4, mut pairing) = fixture_app(pairing_status);
        let buffer = render_to_buffer(
            &mut pairing,
            Rect::new(0, 0, DEFAULT_ONCE_WIDTH, DEFAULT_ONCE_HEIGHT),
            now,
            OffsetDateTime::now_utc(),
        );
        assert_colours_are_basic_ansi_or_reset(&buffer, "an open pairing session");

        let mut registering_status = base_status(vec![], link(LinkState::Idle));
        registering_status.pairing = Some(control::PairingStatus {
            registered: false,
            uri: None,
            phrase: None,
            handle: None,
            expires_in_s: 600,
        });
        let (_f5, mut registering) = fixture_app(registering_status);
        let buffer = render_to_buffer(
            &mut registering,
            Rect::new(0, 0, DEFAULT_ONCE_WIDTH, DEFAULT_ONCE_HEIGHT),
            now,
            OffsetDateTime::now_utc(),
        );
        assert_colours_are_basic_ansi_or_reset(&buffer, "the registering state");
    }

    // -- R-30-600: the reference layout's cyan title, bright black context/
    // header/footer lines, and reverse-video selected row -------------------

    #[test]
    fn title_header_footer_and_selected_row_use_the_reference_layout_colours() {
        let (_fixture, mut app) = fixture_app(base_status(
            vec![pixel(false), iphone(false)],
            link(LinkState::Idle),
        ));
        let now = Instant::now();
        let buffer = render_to_buffer(
            &mut app,
            Rect::new(0, 0, 72, 46),
            now,
            OffsetDateTime::now_utc(),
        );
        let lines = buffer_lines(&buffer);

        assert_eq!(buffer[(0, 0)].fg, Color::Cyan, "the title line is cyan");
        assert!(lines[0].starts_with("herdr relay (2 phones)"));

        assert_eq!(
            buffer[(0, 1)].fg,
            Color::DarkGray,
            "the second context line is bright black"
        );

        let header_row = lines
            .iter()
            .position(|l| l.starts_with("Phone"))
            .expect("a column header row");
        assert_eq!(
            buffer[(0, header_row as u16)].fg,
            Color::DarkGray,
            "the column header is bright black"
        );

        let selected_row = lines
            .iter()
            .position(|l| l.contains("pixel-8-pat"))
            .expect("the selected device's row");
        assert!(
            buffer[(0, selected_row as u16)]
                .modifier
                .contains(Modifier::REVERSED),
            "the selected row prints in reverse video"
        );
        let unselected_row = lines
            .iter()
            .position(|l| l.contains("iphone-15-pat"))
            .expect("the unselected device's row");
        assert!(
            !buffer[(0, unselected_row as u16)]
                .modifier
                .contains(Modifier::REVERSED),
            "an unselected row must not be reversed"
        );

        let footer_row = lines
            .iter()
            .position(|l| l.contains("q quit"))
            .expect("the footer row");
        assert_eq!(
            buffer[(0, footer_row as u16)].fg,
            Color::DarkGray,
            "the one-line footer is bright black"
        );
    }

    // -- R-30-602: up/k, down/j move the selection; esc quits like q --------

    #[test]
    fn up_k_down_j_move_the_selection_within_bounds_and_esc_quits_like_q() {
        let (_fixture, mut app) = fixture_app(base_status(
            vec![pixel(false), iphone(false), thinkpad(false)],
            link(LinkState::Idle),
        ));
        let now = Instant::now();
        let _ = render(&mut app, 72, 46, now);
        assert_eq!(app.selected, 0);

        app.handle_key(KeyCode::Down, now).expect("down");
        assert_eq!(app.selected, 1);
        app.handle_key(KeyCode::Char('j'), now).expect("j");
        assert_eq!(app.selected, 2);
        app.handle_key(KeyCode::Char('j'), now)
            .expect("j at the bottom");
        assert_eq!(
            app.selected, 2,
            "R-31-16-29: selection never runs past the last row"
        );

        app.handle_key(KeyCode::Up, now).expect("up");
        assert_eq!(app.selected, 1);
        app.handle_key(KeyCode::Char('k'), now).expect("k");
        assert_eq!(app.selected, 0);
        app.handle_key(KeyCode::Char('k'), now)
            .expect("k at the top");
        assert_eq!(app.selected, 0, "selection never runs before the first row");

        let outcome = app.handle_key(KeyCode::Esc, now).expect("esc quits");
        assert_eq!(
            outcome,
            KeyOutcome::Quit,
            "R-30-602: esc quits the pane exactly like q, with no confirmation pending"
        );
    }

    // -- R-30-603, R-30-607: r asks before a destructive remove-all, f
    // silently reloads, and moving the selection never re-polls -------------

    #[test]
    fn r_asks_before_removing_everything_while_f_reloads_silently_and_movement_reads_nothing() {
        let (fixture, mut app) = fixture_app(base_status(
            vec![pixel(false), iphone(false)],
            link(LinkState::Idle),
        ));
        app.handle_key(KeyCode::Char('r'), Instant::now())
            .expect("handle r");
        assert!(
            app.confirm.is_some(),
            "R-30-603: r is the destructive 'remove all' action and MUST ask first"
        );
        app.handle_key(KeyCode::Char('n'), Instant::now())
            .expect("cancel");
        assert_eq!(
            app.devices().len(),
            2,
            "cancelling r must not remove anything"
        );
        assert!(
            fixture.commands().is_empty(),
            "a cancelled question sends no command"
        );

        let _ = render(&mut app, 72, 46, Instant::now());

        // A write lands on the bridge behind the pane's back, exactly the
        // way a concurrent pairing accept would.
        fixture.mutate(|status| status.devices.push(thinkpad(false)));

        // R-30-607: moving the selection costs no I/O — the third device
        // stays invisible.
        app.handle_key(KeyCode::Down, Instant::now())
            .expect("move down");
        assert_eq!(app.devices().len(), 2);

        // R-30-603/R-30-607: `f` keeps the reference meaning of redraw — it
        // re-asks the bridge without ever asking a y/n question.
        app.handle_key(KeyCode::Char('f'), Instant::now())
            .expect("handle f");
        assert!(
            app.confirm.is_none(),
            "R-30-603: f MUST NOT read as a second destructive refresh"
        );
        assert_eq!(
            app.devices().len(),
            3,
            "R-30-607: f is the one key that reloads the status"
        );
    }

    // -- R-30-605: hide the QR code and the six words the instant pairing
    // ends ---------------------------------------------------------------

    #[test]
    fn q_removes_the_qr_and_phrase_text_from_the_very_next_render() {
        let mut status = base_status(vec![], link(LinkState::Idle));
        status.pairing = Some(registered_pairing(600));
        let (_fixture, mut app) = fixture_app(status);
        let now = Instant::now();
        let before = render(&mut app, DEFAULT_ONCE_WIDTH, DEFAULT_ONCE_HEIGHT, now);
        let before_text = before.join("\n");
        assert!(before_text.contains("phrase:"));
        assert!(
            before
                .iter()
                .any(|l| l.contains('█') || l.contains('▀') || l.contains('▄')),
            "the QR block is on screen while pairing is open"
        );

        app.handle_key(KeyCode::Char('q'), now).expect("handle q");

        let after = render(&mut app, DEFAULT_ONCE_WIDTH, DEFAULT_ONCE_HEIGHT, now);
        let after_text = after.join("\n");
        assert!(
            !after_text.contains("phrase:"),
            "R-30-605: the phrase disappears the instant q ends pairing"
        );
        assert!(
            !after
                .iter()
                .any(|l| l.contains('█') || l.contains('▀') || l.contains('▄')),
            "R-30-605: the QR block disappears the instant q ends pairing"
        );
        for word in PHRASE.split(' ') {
            assert!(
                !after_text.contains(word),
                "R-30-605: no phrase word survives on screen after q"
            );
        }
    }

    // -- R-30-606: `--once` renders exactly one pass with no terminal, so a
    // test can assert its output deterministically --------------------------

    #[test]
    fn render_to_buffer_at_the_once_default_size_is_deterministic_with_no_terminal() {
        let (_fixture, mut app) =
            fixture_app(base_status(vec![pixel(false)], link(LinkState::Idle)));
        let now = Instant::now();
        let wall_now = OffsetDateTime::now_utc();
        let area = Rect::new(0, 0, DEFAULT_ONCE_WIDTH, DEFAULT_ONCE_HEIGHT);

        let first = buffer_lines(&render_to_buffer(&mut app, area, now, wall_now));
        let second = buffer_lines(&render_to_buffer(&mut app, area, now, wall_now));

        assert_eq!(
            first, second,
            "R-30-606: the same state and instant render one identical pass, with no terminal touched"
        );
    }

    // -- R-31-16-34 to -36: the copy key, its hint, and its failure text ----

    #[test]
    fn c_with_no_session_sets_the_nothing_to_copy_notice() {
        let (_fixture, mut app) = fixture_app(base_status(vec![], link(LinkState::Idle)));
        app.copy_pairing_uri = |text| {
            panic!("no session is open, so the copy fn must never run: {text}");
        };
        app.handle_key(KeyCode::Char('c'), Instant::now())
            .expect("handle c");
        assert_eq!(
            app.notice.as_deref(),
            Some("press p first - there is nothing to copy yet")
        );
    }

    #[test]
    fn c_while_registering_sets_the_nothing_to_copy_notice() {
        // R-10-064: the URI stays null until the registration is accepted,
        // so `c` has nothing to copy yet (R-31-16-38).
        let mut status = base_status(vec![], link(LinkState::Idle));
        status.pairing = Some(control::PairingStatus {
            registered: false,
            uri: None,
            phrase: None,
            handle: None,
            expires_in_s: 600,
        });
        let (_fixture, mut app) = fixture_app(status);
        app.copy_pairing_uri = |text| {
            panic!("a still-registering session holds no URI to copy: {text}");
        };
        app.handle_key(KeyCode::Char('c'), Instant::now())
            .expect("handle c");
        assert_eq!(
            app.notice.as_deref(),
            Some("press p first - there is nothing to copy yet")
        );
    }

    #[test]
    fn c_with_an_open_session_copies_the_exact_uri_the_qr_encodes() {
        use std::sync::Mutex;

        static COPIED: Mutex<Vec<String>> = Mutex::new(Vec::new());
        fn record_copy(text: &str) -> Result<(), String> {
            COPIED
                .lock()
                .expect("copy record lock")
                .push(text.to_owned());
            Ok(())
        }

        let mut status = base_status(vec![], link(LinkState::Idle));
        status.pairing = Some(registered_pairing(600));
        let (_fixture, mut app) = fixture_app(status);
        let expected_uri = app.pairing_uri().expect("a live pairing URI");
        assert_eq!(expected_uri, pairing_uri_fixture());

        COPIED.lock().expect("copy record lock").clear();
        app.copy_pairing_uri = record_copy;
        app.handle_key(KeyCode::Char('c'), Instant::now())
            .expect("handle c");

        assert_eq!(
            COPIED.lock().expect("copy record lock").clone(),
            vec![expected_uri],
            "R-31-16-34: c copies the exact URI the QR encodes, whole"
        );
        assert_eq!(
            app.notice.as_deref(),
            Some("copied - paste it into the phone app with Paste from clipboard")
        );
    }

    #[test]
    fn c_with_a_failed_copy_reports_the_fixed_failure_message() {
        let mut status = base_status(vec![], link(LinkState::Idle));
        status.pairing = Some(registered_pairing(600));
        let (_fixture, mut app) = fixture_app(status);
        app.copy_pairing_uri = |_| Err("no clipboard tool found".to_string());
        app.handle_key(KeyCode::Char('c'), Instant::now())
            .expect("handle c");
        assert_eq!(
            app.notice.as_deref(),
            Some("copy failed: no clipboard tool found")
        );
    }

    #[test]
    fn c_after_expiry_sets_the_nothing_to_copy_notice_without_calling_copy() {
        let mut status = base_status(vec![], link(LinkState::Idle));
        status.pairing = Some(registered_pairing(600));
        let (_fixture, mut app) = fixture_app(status);
        let start = Instant::now();
        app.refresh_at(start);
        app.copy_pairing_uri = |text| {
            panic!("an expired phrase must not be copied: {text}");
        };
        let too_late = start + Duration::from_secs(601);
        app.handle_key(KeyCode::Char('c'), too_late)
            .expect("handle c");
        assert_eq!(
            app.notice.as_deref(),
            Some("press p first - there is nothing to copy yet")
        );
    }

    #[test]
    fn the_copy_hint_line_prints_only_while_a_session_is_open() {
        let mut status = base_status(vec![pixel(false)], link(LinkState::Idle));
        let (_fixture, mut app) = fixture_app(status.clone());
        let now = Instant::now();

        let idle = render(&mut app, 72, 46, now);
        assert!(
            !idle.iter().any(|l| l.contains("press c to copy")),
            "no hint and no c binding with no session open"
        );
        assert!(!idle.iter().any(|l| l.contains("c copy")));

        status.pairing = Some(registered_pairing(600));
        let (_fixture2, mut app) = fixture_app(status);
        let open = render(&mut app, DEFAULT_ONCE_WIDTH, DEFAULT_ONCE_HEIGHT, now);
        assert!(
            open.iter()
                .any(|l| l.contains("press c to copy the pairing link")),
            "the copy hint prints under the credential block"
        );
        let footer = open
            .iter()
            .find(|l| l.contains("q quit"))
            .expect("a footer line");
        assert!(
            footer.contains("c copy"),
            "the footer lists c copy while a session is open"
        );
    }

    #[test]
    fn the_footer_keeps_the_c_key_in_every_form_while_a_session_is_open() {
        // R-31-16-30's own three widths, with `c` in each form while a
        // session is open. `footer_line` is the pure function the draw
        // path calls, so no render floor interferes with the width
        // arithmetic under test. `c copy` makes the labelled form 80
        // cells, so a 72 column pane shows the short form — the widest
        // form that fits, never a shortened key.
        let availability = FooterAvailability {
            scroll: true,
            copy: true,
            remove_one: true,
            remove_all: true,
        };
        let text =
            |line: Line<'_>| -> String { line.spans.iter().map(|s| s.content.as_ref()).collect() };
        assert_eq!(
            text(footer_line(&availability, 80)),
            "up/down select  p pair  c copy  d remove  r remove all  s stop  f reload  q quit"
        );
        assert_eq!(
            text(footer_line(&availability, 72)),
            "p pair  c copy  d remove  r all  s stop  f reload  q quit"
        );
        assert_eq!(text(footer_line(&availability, 13)), "p c d r s f q");
    }

    // -- R-10-066: `p` asks the bridge; the pane mints nothing -------------

    #[test]
    fn p_sends_open_pairing_and_the_refreshed_status_shows_the_session() {
        let (fixture, mut app) = fixture_app(base_status(vec![], link(LinkState::Idle)));
        app.handle_key(KeyCode::Char('p'), Instant::now())
            .expect("handle p");
        assert_eq!(
            fixture.commands(),
            vec![Command::OpenPairing],
            "R-10-066: p maps to `open_pairing`; the pane mints nothing itself"
        );
        let lines = render(
            &mut app,
            DEFAULT_ONCE_WIDTH,
            DEFAULT_ONCE_HEIGHT,
            Instant::now(),
        );
        let text = lines.join("\n");
        assert!(
            text.contains("pair a phone"),
            "the refreshed status renders"
        );
        assert!(text.contains("phrase:"));
    }

    #[test]
    fn p_restarts_a_stopped_relay_without_replacing_its_pairing() {
        let mut status = base_status(vec![], link(LinkState::Stopped));
        status.pairing = Some(registered_pairing(87));
        let (_fixture, mut app) = fixture_app(status);
        let uri = app.pairing_uri();
        app.handle_key(KeyCode::Char('p'), Instant::now())
            .expect("handle p");
        assert!(!app.stopped());
        assert_eq!(app.pairing_uri(), uri);
        assert_eq!(
            app.status
                .as_ref()
                .unwrap()
                .pairing
                .as_ref()
                .unwrap()
                .expires_in_s,
            87
        );
    }
}
