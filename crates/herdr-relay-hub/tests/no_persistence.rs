//! Phase 23 item 3 (`docs/90-implementation-plan.md`): confirms the relay holds zero
//! persistent state and nothing survives a restart (R-12-013). A code-review grep of
//! `crates/herdr-relay-hub/src/` for `std::fs`, `File::`, `OpenOptions` or `tokio::fs`
//! finds nothing (recorded in `docs/security/review-pack/`); this test proves the
//! runtime half: a fresh `router()` call, the only way a real process restart can
//! rebuild the relay, starts with an empty handle map, not the one a prior instance
//! built. `tests/support/mod.rs`'s `Relay::start()` calls `router()` itself, so two
//! `Relay::start()` calls in one process are the same "is there hidden global state"
//! question a real process restart answers by construction — if this failed, the
//! relay would need a `static`/`OnceLock` registry, which `crates/herdr-relay-hub/src/`
//! does not have.

mod support;

use support::{HANDLE_A, Relay};
use tokio_tungstenite::tungstenite::Message as WsMessage;

#[tokio::test]
async fn a_second_relay_instance_has_no_memory_of_the_first() {
    let first = Relay::start().await;
    let _host = first.connect("host", HANDLE_A).await;
    drop(first); // simulates the process restart R-12-013 requires losing all state.

    let second = Relay::start().await;
    let mut device = second.connect("device", HANDLE_A).await;

    // The Host registered on `first` is gone: `second` has never heard of `HANDLE_A`,
    // so the Device's join is refused with `handle_unknown` (R-11-117), not silently
    // paired with a Host from a prior instance.
    let reply = device
        .recv()
        .await
        .expect("an unknown handle must get an error frame before the close");
    match reply {
        WsMessage::Text(text) => assert!(
            text.contains("handle_unknown"),
            "expected a handle_unknown error frame proving no state survived the restart, got: {text}"
        ),
        other => panic!("expected a Text error frame, got {other:?}"),
    }
}
