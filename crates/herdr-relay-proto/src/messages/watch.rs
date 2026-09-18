//! The pane-watch and render-loop messages (`docs/11-relay-protocol.md` §4.6 through
//! §4.11): watching one pane, its ANSI frames, and scrollback.

use serde::{Deserialize, Serialize};

/// `watch_pane` (§4.6). Sender: Device. Reply: `watch_ack`. Correlation: yes. The
/// Device watches at most one pane at a time; a second `watch_pane` replaces the first
/// (R-11-048).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WatchPane {
    pub pane_id: String,
}

/// `watch_ack` (§4.7). Sender: Host. Reply: no (reply to `watch_pane`). Correlation:
/// yes.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WatchAck {
    pub pane_id: String,
    /// Current revision from `session.snapshot` (R-10-020).
    pub revision: u64,
    /// From `scroll.viewport_rows` (R-10-024).
    pub viewport_rows: u32,
    /// From `pane.layout` `rect.width`, in character cells (R-10-024).
    pub width: u32,
    pub scroll: ScrollOffsets,
    /// The Host's shadow of the console line for this pane: everything the Device
    /// typed since the last submit (R-11-249). Empty when nothing is pending. The
    /// Device seeds its composer from it when the terminal opens.
    #[serde(default)]
    pub line: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct ScrollOffsets {
    pub offset_from_bottom: u64,
    pub max_offset_from_bottom: u64,
}

/// `unwatch_pane` (§4.8). Sender: Device. Reply: no. Correlation: no.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct UnwatchPane {
    pub pane_id: String,
}

/// `pane_frame` (§4.9). Sender: Host. Reply: no. Correlation: no. The payload the
/// terminal emulator renders.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PaneFrame {
    pub pane_id: String,
    /// From the `pane.updated` event that triggered this read, never from `pane.read`,
    /// which is always `0` (R-11-052).
    pub revision: u64,
    pub viewport_rows: u32,
    pub width: u32,
    /// Full ANSI text of the visible viewport, never a delta (R-11-051).
    pub text: String,
}

/// `scroll_request` (§4.10). Sender: Device. Reply: `scroll_response`. Correlation:
/// yes.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ScrollRequest {
    pub pane_id: String,
    /// MUST NOT exceed 1000 (R-10-019).
    pub lines: u32,
}

/// `scroll_response` (§4.11). Sender: Host. Reply: no (reply to `scroll_request`).
/// Correlation: yes.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ScrollResponse {
    pub pane_id: String,
    pub text: String,
    pub lines: u32,
    /// `true` when the returned window does not cover the full scrollback.
    pub truncated: bool,
}
