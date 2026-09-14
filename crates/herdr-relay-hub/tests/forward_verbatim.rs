//! Asserts a binary frame sent by the Host client arrives at the Device client byte
//! for byte identical (`docs/90-implementation-plan.md` §Phase 3, R-40-032, R-12-003).

mod support;

use support::{HANDLE_A, Relay};
use tokio_tungstenite::tungstenite::Message as WsMessage;

#[tokio::test]
async fn binary_frame_forwards_byte_identical() {
    let relay = Relay::start().await;
    let mut host = relay.connect("host", HANDLE_A).await;
    let mut device = relay.connect("device", HANDLE_A).await;

    let payload = b"opaque-noise-ciphertext-not-a-real-frame".to_vec();
    host.send_binary(payload.clone()).await;

    let received = device
        .recv()
        .await
        .expect("the device must receive the forwarded frame");
    assert_eq!(received, WsMessage::Binary(payload.into()));
}
