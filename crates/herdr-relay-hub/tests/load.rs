//! Holds 500 concurrent Host and Device pairs on one relay instance and confirms
//! every pair still forwards a frame correctly (`docs/12-relay-hosting.md`
//! R-12-007, `docs/90-implementation-plan.md` §Phase 8, WP-8 `Owns.`).
//!
//! Self-contained: see `tests/limits.rs`'s module doc for why this does not use
//! `tests/support/mod.rs` (owned by `WP-3`/Phase 3). Raises the connection- and
//! handle-registration-rate limits for this run only: R-12-007 is about concurrent
//! *steady-state* capacity, not about also passing R-12-031/R-12-033's rate limits
//! within the same one-second window — a real deployment's 500 pairs arrive over
//! minutes, not one second, so the default rates would only be testing the rate
//! limiter a second time, which `tests/limits.rs` already covers.

use std::net::SocketAddr;
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use tokio::net::TcpListener;
use tokio_tungstenite::tungstenite::Message as WsMessage;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::{MaybeTlsStream, WebSocketStream};

type Stream = WebSocketStream<MaybeTlsStream<tokio::net::TcpStream>>;

const PAIRS: usize = 500;

async fn start_relay() -> (SocketAddr, SocketAddr, tokio::task::JoinHandle<((), ())>) {
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("binding a loopback ephemeral port must succeed in a test");
    let addr = listener
        .local_addr()
        .expect("a bound socket has a local address");
    let metrics_listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("binding a loopback ephemeral port must succeed in a test");
    let metrics_addr = metrics_listener
        .local_addr()
        .expect("a bound socket has a local address");
    let (app, metrics_app) = herdr_relay_hub::routes::build();
    let server = tokio::spawn(async move {
        let main_server = axum::serve(
            listener,
            app.into_make_service_with_connect_info::<SocketAddr>(),
        );
        let metrics_server = axum::serve(metrics_listener, metrics_app);
        tokio::try_join!(main_server, metrics_server)
            .expect("the test relay must not fail to serve")
    });
    (addr, metrics_addr, server)
}

/// A minimal raw-TCP `GET /metrics` — no HTTP client crate is a workspace
/// dependency for this crate (`docs/12-relay-hosting.md` "## Language and
/// Crates" pins none; `AGENTS.md` "Never build ... an HTTP client" is about the
/// relay's own production code, not a five-line test-only request over a
/// request/response protocol this simple).
async fn fetch_metrics_body(addr: SocketAddr) -> String {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    let mut stream = tokio::net::TcpStream::connect(addr)
        .await
        .expect("connecting to the metrics listener must succeed");
    stream
        .write_all(b"GET /metrics HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        .await
        .expect("writing the request must succeed");
    let mut raw = Vec::new();
    stream
        .read_to_end(&mut raw)
        .await
        .expect("reading the response must succeed");
    let text = String::from_utf8(raw).expect("the metrics body is ASCII Prometheus text");
    text.split_once("\r\n\r\n")
        .map(|(_, body)| body.to_owned())
        .unwrap_or(text)
}

async fn connect_and_register(addr: SocketAddr, role: &str, handle: &str) -> Stream {
    let url = format!("ws://{addr}/{role}/{handle}");
    let mut request = url
        .into_client_request()
        .expect("a loopback ws URL always builds a valid request");
    request.headers_mut().insert(
        "sec-websocket-protocol",
        "herdr-relay.v1"
            .parse()
            .expect("a static header value always parses"),
    );
    let (mut stream, _response) = tokio_tungstenite::connect_async(request)
        .await
        .expect("the relay must accept the WebSocket upgrade");
    let frame = if role == "host" {
        r#"{"type":"host_register","protocol":1}"#
    } else {
        r#"{"type":"device_register","protocol":1}"#
    };
    stream
        .send(WsMessage::Text(frame.into()))
        .await
        .expect("send must succeed on a fresh socket");
    let reply = stream
        .next()
        .await
        .expect("session_joined must arrive")
        .expect("no transport error");
    assert!(
        matches!(&reply, WsMessage::Text(t) if t.contains("session_joined")),
        "expected session_joined, got {reply:?}"
    );
    stream
}

/// Sends `handle` as an opaque payload from the joined Host to the joined Device
/// and confirms it arrives byte-identical. MUST run only after both sides have
/// joined: a frame sent before the peer slot fills is dropped silently by design
/// (R-12-036), which is exactly the bug this split from `connect_and_register`
/// exists to avoid — the Host used to send immediately after its own
/// `session_joined`, before the Device had even connected.
async fn exchange_one_frame(host: &mut Stream, device: &mut Stream, handle: &str) {
    let payload = handle.as_bytes().to_vec();
    host.send(WsMessage::Binary(payload.clone().into()))
        .await
        .expect("send must succeed on a joined socket");
    let received = tokio::time::timeout(Duration::from_secs(10), device.next())
        .await
        .expect("the Host's frame must arrive within 10 seconds under load")
        .expect("a message must arrive")
        .expect("no transport error");
    match received {
        WsMessage::Binary(bytes) => {
            assert_eq!(
                bytes.as_ref(),
                handle.as_bytes(),
                "frame must forward byte-identical"
            );
        }
        other => panic!("expected the forwarded binary frame, got {other:?}"),
    }
}

/// A 22-character base64url fixture handle unique to pair `n` (`n` < 500 fits in
/// three base64url characters at the front of an otherwise-zero handle, so no two
/// pairs in this test ever collide).
fn fixture_handle(n: usize) -> String {
    const ALPHABET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    let a = ALPHABET[n / (ALPHABET.len() * ALPHABET.len()) % ALPHABET.len()] as char;
    let b = ALPHABET[n / ALPHABET.len() % ALPHABET.len()] as char;
    let c = ALPHABET[n % ALPHABET.len()] as char;
    format!("{a}{b}{c}AAAAAAAAAAAAAAAAAAA")
}

#[tokio::test(flavor = "multi_thread", worker_threads = 16)]
async fn five_hundred_concurrent_pairs_all_forward_correctly() {
    unsafe {
        std::env::set_var("HERDR_RELAY_CONNECTION_RATE", "10000");
        std::env::set_var("HERDR_RELAY_HANDLE_RATE", "10000");
    }
    let (addr, metrics_addr, server) = start_relay().await;

    let mut pairs = tokio::task::JoinSet::new();
    for n in 0..PAIRS {
        let handle = fixture_handle(n);
        // Sequenced within one task, not two independent spawns: a Device only
        // ever connects after scanning a QR code the Host has already rendered
        // (`docs/13-security-pairing.md`), so the Host's `session_joined` reply —
        // proof the relay finished registering it — must arrive before the
        // Device's own connection starts, or it can race the registration and
        // see `handle_unknown`. Across the 500 pairs, this task itself is still
        // fully concurrent.
        pairs.spawn(async move {
            let mut host = connect_and_register(addr, "host", &handle).await;
            let mut device = connect_and_register(addr, "device", &handle).await;
            exchange_one_frame(&mut host, &mut device, &handle).await;
            (host, device)
        });
    }

    // Every task returns its still-open pair of streams: hold all 500 pairs
    // alive so the `/metrics` snapshot below observes the relay while every
    // pair is truly up, not after they have already started disconnecting.
    let mut streams = Vec::with_capacity(PAIRS);
    while let Some(result) = pairs.join_next().await {
        streams.push(result.expect("no connection task may panic"));
    }
    assert_eq!(streams.len(), PAIRS, "every Host/Device pair must complete");

    let metrics_body = fetch_metrics_body(metrics_addr).await;
    assert!(
        metrics_body.contains(&format!("herdr_relay_handles_active {PAIRS}")),
        "expected herdr_relay_handles_active {PAIRS} while every pair is still connected, got:\n{metrics_body}"
    );

    drop(streams);
    server.abort();
    unsafe {
        std::env::remove_var("HERDR_RELAY_CONNECTION_RATE");
        std::env::remove_var("HERDR_RELAY_HANDLE_RATE");
    }
}
