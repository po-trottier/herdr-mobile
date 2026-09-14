//! Full integration smoke test: starts the relay, joins a Host and a Device over real
//! WebSockets, and confirms frames flow unmodified in both directions
//! (`docs/90-implementation-plan.md` §Phase 3, R-40-033).

mod support;

use support::{HANDLE_A, Relay};
use tokio_tungstenite::tungstenite::Message as WsMessage;

#[tokio::test]
async fn frames_flow_unmodified_both_directions() {
    let relay = Relay::start().await;
    let mut host = relay.connect("host", HANDLE_A).await;
    let mut device = relay.connect("device", HANDLE_A).await;

    host.send_binary(b"host-to-device".to_vec()).await;
    let at_device = device
        .recv()
        .await
        .expect("the device must receive the host's frame");
    assert_eq!(
        at_device,
        WsMessage::Binary(b"host-to-device".to_vec().into())
    );

    device.send_binary(b"device-to-host".to_vec()).await;
    let at_host = host
        .recv()
        .await
        .expect("the host must receive the device's frame");
    assert_eq!(
        at_host,
        WsMessage::Binary(b"device-to-host".to_vec().into())
    );
}
