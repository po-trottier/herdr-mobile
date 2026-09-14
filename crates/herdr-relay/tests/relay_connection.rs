//! Integration test for `relay::connection`, `relay::session` and
//! `relay::registry`: a full Host-side connect, Noise handshake, and
//! revocation-close round trip, against a self-contained fake relay server.
//!
//! This crate owns no relay-hub code, and `herdr-relay-hub` is a sibling
//! package's own concurrently-edited crate — coupling this test to a real
//! `herdr-relay-hub` binary would make it depend on another package's build
//! and behaviour. `docs/90-implementation-plan.md`'s own Phase 6 task brief
//! names "an in-process fake WebSocket server" as sufficient local proof
//! here, matching how `app/lib/services/relay.dart`'s own Dart tests work.
//! The fake server plays both the relay's registration handshake
//! (`host_register`/`session_joined`) and the Device's half of the real
//! `Noise_XXpsk0` handshake (`herdr-relay`'s own `noise.rs`), so this test
//! exercises the genuine wire format end to end: real Noise ciphertext, real
//! `frame_codec` compress/fragment framing, and a real close code.

use std::net::SocketAddr;
use std::time::{Duration, Instant};

use futures_util::{SinkExt, StreamExt};
use tokio::net::{TcpListener, TcpStream};
use tokio_tungstenite::WebSocketStream;
use tokio_tungstenite::tungstenite::Message as WsMessage;

use herdr_relay::frame_codec::{self, Reassembler};
use herdr_relay::noise::{self, Role};
use herdr_relay::relay::{self, HandshakeSetup, SessionRegistry};
use herdr_relay_proto::codes::ErrorCode;
use herdr_relay_proto::frame::Frame;
use herdr_relay_proto::handle::Handle;
use herdr_relay_proto::messages::{Message, RevokeResult};

/// A fixed pre-shared key both sides of this test's fake pairing use.
/// `noise.rs` owns the real `BLAKE2s-256(phrase)` transform (R-13-024); this
/// test drives both handshake ends itself, so any matching 32 bytes prove
/// the same wire behaviour.
fn psk() -> [u8; 32] {
    [7_u8; 32]
}

async fn next_binary(socket: &mut WebSocketStream<TcpStream>) -> Vec<u8> {
    match socket
        .next()
        .await
        .expect("the fake relay socket is still open")
        .expect("no websocket I/O error")
    {
        WsMessage::Binary(bytes) => bytes.to_vec(),
        other => panic!("expected a binary handshake message, got {other:?}"),
    }
}

/// Echoes the client's requested subprotocol back in the handshake
/// response, so `tokio_tungstenite::connect_async`'s own subprotocol check
/// on the client side accepts this fake server (R-11-013, R-12-020).
#[allow(clippy::result_large_err)] // the Err type is tungstenite's own Response; not this test's to box
fn echo_subprotocol(
    request: &tokio_tungstenite::tungstenite::handshake::server::Request,
    mut response: tokio_tungstenite::tungstenite::handshake::server::Response,
) -> Result<
    tokio_tungstenite::tungstenite::handshake::server::Response,
    tokio_tungstenite::tungstenite::handshake::server::ErrorResponse,
> {
    if let Some(protocol) = request.headers().get("sec-websocket-protocol") {
        response
            .headers_mut()
            .insert("sec-websocket-protocol", protocol.clone());
    }
    Ok(response)
}

/// Accepts one connection, completes the `host_register`/`session_joined`
/// exchange (R-11-113), and returns the still-open WebSocket for the caller
/// to drive the Device's own Noise handshake over.
async fn accept_and_register(listener: &TcpListener) -> WebSocketStream<TcpStream> {
    let (stream, _addr) = listener
        .accept()
        .await
        .expect("accept the host's connection");
    let mut socket = tokio_tungstenite::accept_hdr_async(stream, echo_subprotocol)
        .await
        .expect("complete the websocket upgrade");
    let register = socket
        .next()
        .await
        .expect("a registration message arrives")
        .expect("no websocket I/O error");
    assert!(
        matches!(&register, WsMessage::Text(text) if text.contains("host_register")),
        "expected host_register, got {register:?}"
    );
    socket
        .send(WsMessage::Text(r#"{"type":"session_joined"}"#.into()))
        .await
        .expect("send session_joined");
    socket
}

#[tokio::test]
async fn connect_run_session_and_close_on_revocation() {
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind a local test port");
    let addr: SocketAddr = listener.local_addr().expect("read the bound address");
    let handle = Handle::generate().expect("generate a routing handle");

    let (host_private, _host_public) = noise::generate_keypair().expect("generate a host keypair");
    let (device_private, _device_public) =
        noise::generate_keypair().expect("generate a device keypair");

    let origin = format!("ws://{addr}");
    let host_task = tokio::spawn(async move {
        relay::connect_host(
            &origin,
            handle,
            HandshakeSetup::Pairing {
                local_private_key: host_private,
                psk: psk(),
            },
        )
        .await
        .expect("the host completes connect, register and the noise handshake")
    });

    // Drive the fake relay's registration reply, then the Device's own
    // Noise_XXpsk0 initiator half (R-13-071: the Device sends first).
    let mut device_socket = accept_and_register(&listener).await;
    let mut handshake = noise::pairing_handshake(Role::Initiator, &device_private, &psk())
        .expect("build the device's initiator handshake state");
    let msg1 = noise::write_handshake_message(&mut handshake, &[]).expect("write handshake msg1");
    device_socket
        .send(WsMessage::Binary(msg1.into()))
        .await
        .expect("send handshake msg1");

    let msg2 = next_binary(&mut device_socket).await;
    noise::read_handshake_message(&mut handshake, &msg2).expect("read handshake msg2");

    let msg3 = noise::write_handshake_message(&mut handshake, &[]).expect("write handshake msg3");
    device_socket
        .send(WsMessage::Binary(msg3.into()))
        .await
        .expect("send handshake msg3");

    let (mut device_transport, _host_static_key) =
        noise::finish_handshake(handshake).expect("finish the device's handshake");

    let (host_socket, host_transport, _device_static_key) =
        host_task.await.expect("the host task did not panic");

    // Both sides now hold an established Noise transport. Run the real
    // session driver, and from the "outside" (as `store.rs`'s revocation
    // flow would), close it through the registry.
    let registry = SessionRegistry::new();
    let session_fut = relay::run_host_session(
        host_socket,
        host_transport,
        handle,
        Some("device-a".to_owned()),
        &registry,
    );

    let verify_fut = async {
        // Give `run_host_session` a moment to register itself before this
        // closes it, matching the real ordering: registration always
        // precedes any possible revocation.
        tokio::time::sleep(Duration::from_millis(50)).await;
        let result = RevokeResult {
            revoked: vec!["device-a".to_owned()],
            all: false,
        };
        assert_eq!(
            registry.close_for_revocation(&result),
            1,
            "the registered session under device-a is found and closed"
        );

        // The Device side MUST observe one application frame: the fatal
        // `revoked` error (R-11-065), over the real frame_codec wire format.
        let mut reassembler = Reassembler::new();
        let envelope_bytes = loop {
            match device_socket
                .next()
                .await
                .expect("the socket is still open for the error frame")
                .expect("no websocket I/O error")
            {
                WsMessage::Binary(bytes) => {
                    if let Some(envelope) = frame_codec::decode_fragment(
                        &mut reassembler,
                        &mut device_transport,
                        &bytes,
                        Instant::now(),
                    )
                    .expect("decode the revoked-error fragment")
                    {
                        break envelope;
                    }
                }
                other => panic!("expected a binary application frame, got {other:?}"),
            }
        };
        let frame = Frame::from_json_bytes(&envelope_bytes).expect("parse the frame envelope");
        match frame.message().expect("recover the typed message") {
            Message::Error(error) => {
                assert_eq!(error.code, ErrorCode::Revoked);
                assert!(error.fatal, "R-11-065: fatal MUST be true");
            }
            other => panic!("expected an Error message, got {other:?}"),
        }

        // Then the WebSocket MUST close with code 4004 (R-11-121).
        match device_socket
            .next()
            .await
            .expect("a close frame arrives")
            .expect("no websocket I/O error")
        {
            WsMessage::Close(Some(close_frame)) => {
                assert_eq!(u16::from(close_frame.code), 4004);
            }
            other => panic!("expected a close frame with code 4004, got {other:?}"),
        }
    };

    let (session_result, ()) = tokio::join!(session_fut, verify_fut);
    session_result.expect("the session loop exits cleanly after closing on revocation");
}
