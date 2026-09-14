//! Shared wire protocol for the Host plugin (`herdr-relay`) and the relay service
//! (`herdr-relay-hub`).
//!
//! This crate is the only place that defines a wire type, a close-code enum, an error
//! code, a routing-handle codec or a pairing-phrase codec (`docs/41-code-standards.md`
//! R-41-122). The compiler enforces agreement between the two consumers.
//!
//! Module ownership follows `docs/40-repo-tooling.md` §3.2.1 and
//! `docs/90-implementation-plan.md` §5.2:
//!
//! - `frame` — the envelope that wraps every message (`WP-0-a`, filled in by `WP-5-b`
//!   for the pairing URI builder).
//! - `messages` — the application message union (`WP-5-a`).
//! - `codes` — the relay close-code enum and the phrase error codes (`WP-5-a`).
//! - `handle` — the routing-handle codec (`WP-5-b`).
//! - `phrase` — the pairing-phrase codec (`WP-5-b`).
//! - `test_vectors` — the vectors the Rust and Dart test suites both read (`WP-5-c`).

pub mod codes;
pub mod frame;
pub mod handle;
pub mod messages;
pub mod phrase;
pub mod test_vectors;
