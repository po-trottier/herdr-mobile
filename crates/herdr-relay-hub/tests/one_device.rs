//! Asserts a second Device on an already-joined handle receives `host_in_use` and the
//! first Device is left undisturbed (`docs/90-implementation-plan.md` §Phase 3,
//! R-12-035, R-03-040).

mod support;

use support::{HANDLE_A, Relay};
use tokio_tungstenite::tungstenite::Message as WsMessage;
use tokio_tungstenite::tungstenite::protocol::frame::coding::CloseCode;

#[tokio::test]
async fn second_device_is_refused_and_first_is_undisturbed() {
    let relay = Relay::start().await;
    let mut host = relay.connect("host", HANDLE_A).await;
    let mut first_device = relay.connect("device", HANDLE_A).await;
    let mut second_device = relay.connect("device", HANDLE_A).await;

    // The second Device's registration was refused: an `error` frame (R-11-116)
    // precedes the close. `Relay::connect` could not treat it as `session_joined`,
    // so it buffered it instead of discarding it (see tests/support/mod.rs); consume
    // that buffered frame before the close.
    second_device
        .recv()
        .await
        .expect("the second Device must receive an error frame before the close");

    let close = second_device
        .recv()
        .await
        .expect("the second Device must receive a close frame");
    match close {
        WsMessage::Close(Some(frame)) => assert_eq!(frame.code, CloseCode::from(4006)),
        other => panic!("expected a Close(4006 host_in_use) frame, got {other:?}"),
    }

    // The first Device stays live: a frame the Host sends still reaches it.
    let payload = b"the-first-device-is-still-here".to_vec();
    host.send_binary(payload.clone()).await;
    let received = first_device
        .recv()
        .await
        .expect("the first Device must still receive frames");
    assert_eq!(received, WsMessage::Binary(payload.into()));
}
