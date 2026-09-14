//! The production Herdr socket client (`WP-6`, `INT-6-bridge`, folding in the Phase 1
//! findings proven live in `src/bin/spike-read.rs` and `src/bin/spike-subscribe.rs`).
//!
//! Split by responsibility (R-41-011, each file under the R-41-010 400-line cap):
//! [`client`] is the request/response Herdr socket client; [`subscription`] is the
//! one long-lived event-subscription connection; `transport` is the shared
//! platform-specific open/read/write plumbing neither protocol layer duplicates;
//! `discover` locates the socket path. Every rule here restates
//! `docs/41-code-standards.md` §7 (R-41-153 through R-41-172), which restates
//! `docs/02-herdr-probe-results.md`, the measured ground truth. One connection
//! answers one request, then half-closes (R-10-009); the one long-lived
//! subscription connection answers no request at all after `events.subscribe`
//! (R-10-011); `params` is always sent, even as `{}` (R-02-007); a result is read
//! through its wrapped `result.<payload_key>` (R-10-007); `ping.result.protocol`
//! MUST equal `21` (R-10-012, R-41-164).

mod client;
mod discover;
mod subscription;
mod transport;

pub use client::{EXPECTED_PROTOCOL, HerdrClient, IpcError};
pub use subscription::SubscriptionConnection;
