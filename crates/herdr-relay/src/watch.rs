//! The bridge watch loop (`WP-6`, `INT-6-bridge`): turns a Herdr pane change into an
//! encrypted `pane_frame` at the relay. `docs/90-implementation-plan.md` Phase 6
//! `**Owns.**` this module; Phase 7 (input path), Phase 10 (four device-management
//! handlers) and Phase 19 (the `agent_status` emitter) add to it afterward through
//! the same integration step, per `docs/90-implementation-plan.md` §5.3.
//!
//! Split by responsibility (R-41-011, each file under the R-41-010 400-line cap):
//! `bridge` is the core per-Device state (`Bridge`, `HostIdentity`, `WatchError`)
//! plus the Herdr-call/raw-mapping glue every other file shares; `requests`
//! handles one direct Device request (`tree_request`, `watch_pane`,
//! `unwatch_pane`, `scroll_request`); `input` (added by `WP-7`) handles
//! `send_input`, `agent_prompt` and `host_action`'s create/pane operations;
//! `plugin_actions` handles `host_action`'s `plugin.invoke` and
//! `action_list_request`, split out of `input` once it crossed the R-41-010
//! cap; `error_map` is the shared Herdr-error-to-`error`-frame mapper
//! (R-11-091) both of those use; `key_map` is `input`'s pure `keys`-vocabulary
//! validation (R-10-036 through R-10-039), split out so `tests/input_map.rs`
//! exercises it with no stub server; `devices` (added by `WP-10-a`) handles the
//! four device-management requests (`device_list_request`, `revoke_device`);
//! `incoming` interprets one Herdr subscription push; `run_loop` resynchronises
//! after a drop and drives the main loop; `scheduler` is the pure
//! debounce/rate-cap decision logic; `latest_slot` is the backpressure
//! primitive; `raw` adapts Herdr's actual JSON schema (which measurement proved
//! differs from the wire schema) to the wire types; `herdr_calls` is the trait
//! `ipc::HerdrClient` implements and tests stub; `events` maps a raw push event
//! name to our domain concepts.
//!
//! One watched pane per Device (R-01-007, R-10-033): [`Bridge`] holds at most one
//! watched pane. A second `watch_pane` replaces the first (R-11-048). Reads have
//! two triggers: a moved `revision`, taken only from an event or
//! `session.snapshot`, never from a `pane.read` result, which is always `0`
//! (R-10-020, R-02-012a, R-41-172); and the R-10-070 poll timer, because an agent
//! pane can repaint without its `revision` ever moving (R-02-026). A poll frame
//! goes on the wire only when the text or geometry differs from the last frame
//! sent.

mod bridge;
mod devices;
mod error_map;
mod events;
mod herdr_calls;
mod incoming;
mod input;
mod key_map;
mod latest_slot;
mod plugin_actions;
mod raw;
mod requests;
mod run_loop;
mod scheduler;

pub use bridge::{Bridge, HostIdentity, WatchError};
pub use error_map::map_watch_error;
pub use events::SubscriptionAction;
pub use herdr_calls::HerdrCalls;
pub use latest_slot::LatestSlot;
