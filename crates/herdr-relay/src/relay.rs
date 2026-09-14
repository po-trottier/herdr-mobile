//! The relay-facing connection logic (`WP-6`, `INT-6-bridge`): opening the
//! Host's real outbound WebSocket connection, driving the Noise handshake and
//! a live session, the reconnect backoff ladder, stale-Device detection, and
//! the session registry a revocation closes through.
//!
//! Split by responsibility (R-41-011), each file under the R-41-010 400-line
//! cap:
//! - [`connection`] — opening the outbound connection (R-12-002, R-12-020),
//!   the `host_register`/`session_joined` handshake, driving the Noise
//!   handshake to transport mode, and the post-handshake send/receive path.
//! - [`registry`] — the live-session-by-handle map a revocation closes
//!   through (`store.rs`'s own doc comment names this as `WP-6`/`watch.rs`'s
//!   job).
//! - [`session`] — the per-connection loop: registers with `registry`, reads
//!   frames, and closes with `4004 revoked` on a revocation signal.
//! - [`backoff`] — [`ReconnectBackoff`], R-10-014's exponential ladder with
//!   jitter, reused by `watch.rs`'s Herdr subscription reconnect too.
//! - [`stale`] — [`StaleDeviceDetector`], R-11-086/R-12-009's missed-pong and
//!   30 s hold-open decision.

mod backoff;
mod connection;
mod registry;
mod session;
mod stale;

pub use backoff::ReconnectBackoff;
pub use connection::{
    ConnectError, HandshakeSetup, SessionError, WsStream, connect_host, handshake_on,
    receive_frame, register_host, register_host_pairing, send_frame,
};
pub use registry::{CloseReason, SessionRegistry};
pub use session::run_host_session;
pub use stale::StaleDeviceDetector;
