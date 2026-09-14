//! `herdr-relay`'s library target: exposes the Host plugin's modules to its own
//! integration tests under `tests/` (for example `tests/revoke.rs`), which cannot
//! reach a binary-only crate's modules.
//!
//! Owning paths per `docs/90-implementation-plan.md` §5.2: `config`, `keys` and
//! `store` are `WP-10-a`'s; `ipc`, `relay` and `watch` are `WP-6`'s, added once
//! through `INT-6-bridge` (§5.3) — Phase 7, Phase 10 and Phase 19 extend `watch`
//! afterward without adding a new top-level module here; `noise` and `frame_codec`
//! are `WP-4`'s, both named explicitly on Phase 4's own `Owns.` line; `pairing`
//! (with its `pairing::wordlist` submodule) is `WP-10-b`'s, named explicitly on
//! Phase 10's own `Owns.` line. `popup` (with its `tests/popup_once.rs`) is
//! `WP-10-c`'s, also named on Phase 10's own `Owns.` line.
// ponytail: crate-root file, added on request from WP-10-a; grows as later phases add
// their own owned modules to crates/herdr-relay/src/

pub mod bridge;
pub mod config;
pub mod control;
pub mod frame_codec;
pub mod ipc;
pub mod keybind;
pub mod keys;
pub mod noise;
pub mod pairing;
pub mod popup;
pub mod process;
pub mod relay;
pub mod store;
pub mod theme;
pub mod watch;
