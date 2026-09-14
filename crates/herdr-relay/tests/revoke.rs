//! Add two Devices, revoke one, confirm only the revoked one is removed
//! (`docs/13-security-pairing.md` R-13-053 step 1, `DeviceStore`-level only).
//!
//! `revoking_a_connected_device_...` below closes the gap this file's own
//! previous doc comment disclosed: a mid-session single-Device revoke, over a
//! REAL Noise_KK reconnect handshake (R-13-071), composed with the real
//! `Bridge::revoke_device` (`watch/devices.rs`) and `relay::SessionRegistry`
//! (`relay/registry.rs`) — the same fake-in-process-WS-server pattern
//! `tests/relay_connection.rs` already proved for `Noise_XXpsk0` pairing plus
//! a hand-built `RevokeResult`, and the same store/registry composition
//! `tests/revoke_all.rs` already proved for the `all: true` case with no real
//! socket. This is the first test combining all four: real KK handshake,
//! real `DeviceStore`, real `Bridge::revoke_device`, real registry close.
//!
//! Also asserts the wire-level form of "the handle is destroyed": a second
//! connect attempt on the same handle, after the Host's own connection for
//! it has ended, gets `handle_unknown` and a real `ConnectError` — the exact
//! behaviour R-11-125 describes ("The Host registration lives as long as the
//! Host connection lives") and the only layer this crate (not the separate
//! `herdr-relay-hub` relay service) can prove.

use std::net::SocketAddr;
use std::time::{Duration, Instant};

use futures_util::{SinkExt, StreamExt};
use tokio::net::{TcpListener, TcpStream};
use tokio_tungstenite::WebSocketStream;
use tokio_tungstenite::tungstenite::Message as WsMessage;

use herdr_relay::config::ConfigPaths;
use herdr_relay::frame_codec::{self, Reassembler};
use herdr_relay::ipc::HerdrClient;
use herdr_relay::noise::{self, Role};
use herdr_relay::relay::{self, HandshakeSetup, SessionRegistry};
use herdr_relay::store::DeviceStore;
use herdr_relay::watch::Bridge;
use herdr_relay_proto::codes::ErrorCode;
use herdr_relay_proto::frame::Frame;
use herdr_relay_proto::handle::Handle;
use herdr_relay_proto::messages::{Message, Platform, RevokeDevice};

fn temp_paths(tag: &str) -> ConfigPaths {
    let dir = std::env::temp_dir().join(format!(
        "herdr-relay-revoke-test-{tag}-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("the system clock is after the Unix epoch")
            .as_nanos()
    ));
    std::fs::remove_dir_all(&dir).ok();
    ConfigPaths::new(dir)
}

fn public_key(seed: u8) -> [u8; 32] {
    let mut key = [0u8; 32];
    key[0] = seed;
    key
}

#[test]
fn revoking_one_device_leaves_the_other_paired() {
    let paths = temp_paths("store");
    let mut store = DeviceStore::load(paths.clone()).expect("load a fresh device store");

    store
        .add(
            "host-1".to_string(),
            "AAAAAAAAAAAAAAAAAAAAAA".to_string(),
            "device-a".to_string(),
            "Pixel 9 Pro".to_string(),
            Platform::Android,
            "15".to_string(),
            public_key(1),
        )
        .expect("add device-a");
    store
        .add(
            "host-1".to_string(),
            "AAAAAAAAAAAAAAAAAAAAAA".to_string(),
            "device-b".to_string(),
            "iPhone SE".to_string(),
            Platform::Ios,
            "18.0".to_string(),
            public_key(2),
        )
        .expect("add device-b");
    assert_eq!(
        store.devices().len(),
        2,
        "both devices are paired before revocation"
    );

    let removed = store
        .revoke("device-a")
        .expect("revoke device-a")
        .expect("device-a was paired");
    assert_eq!(removed.device_id, "device-a");

    let remaining = store.devices();
    assert_eq!(remaining.len(), 1, "exactly one device survives revocation");
    assert_eq!(
        remaining[0].device_id, "device-b",
        "the un-revoked device survives"
    );
    assert!(
        remaining
            .iter()
            .all(|device| device.device_id != "device-a"),
        "the revoked device is gone, not marked revoked (R-13-053: no revoked row state)"
    );

    // Revocation persists: a reload from disk sees the same single survivor.
    let reloaded = DeviceStore::load(paths.clone()).expect("reload the persisted store");
    assert_eq!(reloaded.devices().len(), 1);
    assert_eq!(reloaded.devices()[0].device_id, "device-b");

    std::fs::remove_dir_all(paths.dir()).ok();
}

/// Matches `tests/relay_connection.rs`'s own identical helper: reads one
/// binary WebSocket message, panicking on anything else (a Noise handshake
/// message is always binary).
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

/// Matches `tests/relay_connection.rs`'s own identical helper: echoes the
/// requested subprotocol so `tokio_tungstenite::connect_async`'s client-side
/// subprotocol check accepts this fake server (R-11-013, R-12-020).
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

/// Accepts one connection and reads its `host_register` frame (R-11-113),
/// leaving the reply (`session_joined` or a refusal) to the caller, unlike
/// `tests/relay_connection.rs`'s `accept_and_register`, which always sends
/// `session_joined` — this file's second phase needs to refuse instead.
async fn accept_and_read_register(listener: &TcpListener) -> WebSocketStream<TcpStream> {
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
}

/// R-13-034, R-13-054: revoking a connected Device (a) closes its real,
/// already-established `Noise_KK` session with the fatal `revoked` error and
/// close code `4004`, through the real `DeviceStore` + `Bridge::revoke_device`
/// + `SessionRegistry` composition (b) removes it from the store so a second
/// close for the same result finds nothing left, and (c) a fresh reconnect
/// attempt on that now-dead handle is refused with `handle_unknown`.
#[tokio::test]
async fn revoking_a_connected_device_closes_its_kk_session_and_the_handle_refuses_reconnect() {
    let paths = temp_paths("kk-session");
    let mut store = DeviceStore::load(paths.clone()).expect("load a fresh device store");

    let (host_private, host_public) = noise::generate_keypair().expect("generate a host keypair");
    let (device_private, device_public) =
        noise::generate_keypair().expect("generate a device keypair");

    store
        .add(
            "host-1".to_string(),
            "AAAAAAAAAAAAAAAAAAAAAA".to_string(),
            "device-a".to_string(),
            "Pixel 9 Pro".to_string(),
            Platform::Android,
            "15".to_string(),
            device_public,
        )
        .expect("add device-a");
    store
        .add(
            "host-1".to_string(),
            "AAAAAAAAAAAAAAAAAAAAAA".to_string(),
            "device-b".to_string(),
            "iPhone SE".to_string(),
            Platform::Ios,
            "18.0".to_string(),
            public_key(2),
        )
        .expect("add device-b");

    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind a local test port");
    let addr: SocketAddr = listener.local_addr().expect("read the bound address");
    let handle = Handle::generate().expect("generate a routing handle");
    let origin = format!("ws://{addr}");

    // Phase 1: a real Noise_KK reconnect handshake, Host as responder
    // (R-13-071), exactly the setup a returning already-paired Device uses.
    let origin_for_host = origin.clone();
    let host_task = tokio::spawn(async move {
        relay::connect_host(
            &origin_for_host,
            handle,
            HandshakeSetup::Reconnect {
                local_private_key: host_private,
                remote_static_public_key: device_public,
            },
        )
        .await
        .expect("the host completes connect, register and the noise_kk handshake")
    });

    let mut device_socket = accept_and_read_register(&listener).await;
    device_socket
        .send(WsMessage::Text(r#"{"type":"session_joined"}"#.into()))
        .await
        .expect("send session_joined");

    let mut handshake = noise::reconnect_handshake(Role::Initiator, &device_private, &host_public)
        .expect("build the device's kk initiator handshake state");
    let msg1 = noise::write_handshake_message(&mut handshake, &[]).expect("write kk msg1");
    device_socket
        .send(WsMessage::Binary(msg1.into()))
        .await
        .expect("send kk msg1");

    let msg2 = next_binary(&mut device_socket).await;
    noise::read_handshake_message(&mut handshake, &msg2).expect("read kk msg2");
    assert!(
        handshake.is_handshake_finished(),
        "Noise_KK finishes in exactly two messages"
    );
    let (mut device_transport, _host_static_key) =
        noise::finish_handshake(handshake).expect("finish the device's kk handshake");

    let (host_socket, host_transport, _device_static_key) =
        host_task.await.expect("the host task did not panic");

    // Phase 2: revoke device-a mid-session, through the real production
    // composition (`watch/requests.rs`'s `revoke_device_request` calls this
    // same pair in the same order).
    let registry = SessionRegistry::new();
    let session_fut = relay::run_host_session(
        host_socket,
        host_transport,
        handle,
        Some("device-a".to_owned()),
        &registry,
    );

    let verify_fut = async {
        tokio::time::sleep(Duration::from_millis(50)).await;

        let result = Bridge::<HerdrClient>::revoke_device(
            &mut store,
            &paths,
            RevokeDevice {
                device_id: Some("device-a".to_string()),
                all: None,
            },
        )
        .expect("revoke device-a");
        assert_eq!(result.revoked, vec!["device-a".to_string()]);
        assert!(!result.all);
        assert!(
            store
                .devices()
                .iter()
                .all(|device| device.device_id != "device-a"),
            "R-13-053 step 1: the revoked device is gone from the store"
        );
        assert!(
            store.devices().iter().any(|d| d.device_id == "device-b"),
            "the un-revoked device survives"
        );

        assert_eq!(
            registry.close_for_revocation(&result),
            1,
            "the registered kk session under device-a is found and closed"
        );

        // The Device side MUST observe the fatal `revoked` error (R-11-065)
        // over the real frame_codec wire format, established by the real
        // Noise_KK transport above.
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

        match device_socket
            .next()
            .await
            .expect("a close frame arrives")
            .expect("no websocket I/O error")
        {
            WsMessage::Close(Some(close_frame)) => {
                assert_eq!(u16::from(close_frame.code), 4004, "R-11-121");
            }
            other => panic!("expected a close frame with code 4004, got {other:?}"),
        }

        // R-13-034/R-13-054 "the handle is destroyed": a second close for
        // the same result finds nothing left — the registry entry, not just
        // the live socket, is gone.
        assert_eq!(
            registry.close_for_revocation(&result),
            0,
            "the handle was destroyed: nothing survives a second close"
        );
    };

    let (session_result, ()) = tokio::join!(session_fut, verify_fut);
    session_result.expect("the session loop exits cleanly after closing on revocation");

    // Phase 3: a fresh reconnect attempt on the same, now-dead handle is
    // refused. R-11-125: the Host's own registration for a handle lives only
    // as long as its connection does, so once that connection closed above,
    // the relay's own routing entry for `handle` is gone too — simulated
    // here exactly as R-11-117 specifies: `error{code:"handle_unknown"}`,
    // then a close, with no `session_joined` ever sent.
    let origin_for_retry = origin.clone();
    let retry_task = tokio::spawn(async move {
        relay::connect_host(
            &origin_for_retry,
            handle,
            HandshakeSetup::Reconnect {
                local_private_key: host_private,
                remote_static_public_key: device_public,
            },
        )
        .await
    });

    let (stream, _addr) = listener
        .accept()
        .await
        .expect("accept the reconnect attempt");
    let mut refusing_socket = tokio_tungstenite::accept_hdr_async(stream, echo_subprotocol)
        .await
        .expect("complete the websocket upgrade for the refusal");
    let register = refusing_socket
        .next()
        .await
        .expect("a registration message arrives")
        .expect("no websocket I/O error");
    assert!(matches!(&register, WsMessage::Text(text) if text.contains("host_register")));
    refusing_socket
        .send(WsMessage::Text(
            r#"{"type":"error","code":"handle_unknown","message":"No Host is registered under this handle"}"#
                .into(),
        ))
        .await
        .expect("send handle_unknown");
    refusing_socket
        .close(None)
        .await
        .expect("close after the refusal");

    let retry_result = retry_task.await.expect("the retry task did not panic");
    let message = match retry_result {
        Ok(_) => panic!("a reconnect on a destroyed handle must be refused, got Ok"),
        Err(err) => err.to_string(),
    };
    assert!(
        message.contains("handle_unknown"),
        "expected the refusal to surface handle_unknown, got: {message}"
    );

    std::fs::remove_dir_all(paths.dir()).ok();
}
