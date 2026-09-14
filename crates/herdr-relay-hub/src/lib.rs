//! `herdr-relay-hub`: the relay service library surface.
//!
//! Exposes [`routes::router`] so both the `main.rs` binary entry point and the
//! integration tests under `tests/` build the exact same `axum` router
//! (`docs/90-implementation-plan.md` §5.2 `WP-3`, added to the tree by R-90-018
//! because Phase 3 is the first and only phase this path touches). `session`,
//! `relay` and `heartbeat` stay crate-private: they are implementation detail behind
//! the one public entry point.

mod heartbeat;
mod relay;
pub mod routes;
mod session;
