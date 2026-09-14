//! Asserts two connections registered under different routing handles are never
//! joined (`docs/90-implementation-plan.md` §Phase 3, R-40-032, R-12-004).

mod support;

use support::{HANDLE_A, HANDLE_B, Relay};

#[tokio::test]
async fn different_handles_never_join() {
    let relay = Relay::start().await;
    let mut host_a = relay.connect("host", HANDLE_A).await;
    // A Host must be registered under HANDLE_B too, or the Device's own join is
    // refused with `handle_unknown` (R-11-117) before it ever reaches a room to
    // leak into — that would make `expect_silence` below pass for the wrong reason.
    let _host_b = relay.connect("host", HANDLE_B).await;
    let mut device_b = relay.connect("device", HANDLE_B).await;

    host_a
        .send_binary(b"frame-for-handle-a-only".to_vec())
        .await;

    device_b.expect_silence().await;
}

#[tokio::test]
async fn a_device_on_the_same_handle_still_joins() {
    // Control case: confirms `expect_silence` above is a real assertion, not a
    // relay that silently drops every frame regardless of handle.
    let relay = Relay::start().await;
    let mut host_a = relay.connect("host", HANDLE_A).await;
    let mut device_a = relay.connect("device", HANDLE_A).await;

    host_a
        .send_binary(b"frame-on-the-shared-handle".to_vec())
        .await;

    device_a
        .recv()
        .await
        .expect("a Device on the same handle must receive the Host's frame");
}
