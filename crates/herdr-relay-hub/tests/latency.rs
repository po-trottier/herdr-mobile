//! Asserts added ingress-to-egress latency (frame arrival at the relay to frame
//! departure) stays under 5 ms at p50 and under 20 ms at p99 under normal load
//! (`docs/12-relay-hosting.md` R-12-006, `docs/90-implementation-plan.md` §Phase 8,
//! WP-8 `Owns.`).
//!
//! Self-contained: see `tests/limits.rs`'s module doc for why this does not use
//! `tests/support/mod.rs` (owned by `WP-3`/Phase 3).
//!
//! Measures the relay's own added latency, not the network's: both client sockets
//! are loopback TCP, so the measured round trip time is almost entirely the
//! relay's own scheduling and forwarding cost — exactly what R-12-006 bounds.
//! `HERDR_RELAY_FRAME_RATE` is raised for this run only: the default 100 frames/s
//! would itself become the bottleneck under measurement, hiding the relay's true
//! forwarding latency behind R-12-032's throttle rather than measuring it.

use std::net::SocketAddr;
use std::time::{Duration, Instant};

use futures_util::{SinkExt, StreamExt};
use tokio::net::TcpListener;
use tokio_tungstenite::tungstenite::Message as WsMessage;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::{MaybeTlsStream, WebSocketStream};

type Stream = WebSocketStream<MaybeTlsStream<tokio::net::TcpStream>>;

const HANDLE: &str = "n6Loxf94CfyIO6hOxlaHvA";
const SAMPLES: usize = 500;

async fn start_relay() -> (SocketAddr, tokio::task::JoinHandle<()>) {
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("binding a loopback ephemeral port must succeed in a test");
    let addr = listener
        .local_addr()
        .expect("a bound socket has a local address");
    let app = herdr_relay_hub::routes::router();
    let server = tokio::spawn(async move {
        axum::serve(
            listener,
            app.into_make_service_with_connect_info::<SocketAddr>(),
        )
        .await
        .expect("the test relay must not fail to serve");
    });
    (addr, server)
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

#[tokio::test]
async fn added_latency_stays_under_the_r_12_006_bounds() {
    // See the module doc: this raises the frame-rate ceiling only so the limiter
    // itself does not become the measured bottleneck.
    unsafe {
        std::env::set_var("HERDR_RELAY_FRAME_RATE", "100000");
    }
    let (addr, server) = start_relay().await;
    let mut host = connect_and_register(addr, "host", HANDLE).await;
    let mut device = connect_and_register(addr, "device", HANDLE).await;

    let mut samples = Vec::with_capacity(SAMPLES);
    for i in 0..SAMPLES {
        let payload = (i as u64).to_le_bytes().to_vec();
        let sent_at = Instant::now();
        host.send(WsMessage::Binary(payload.clone().into()))
            .await
            .expect("send must succeed on a live socket");
        let received = tokio::time::timeout(Duration::from_secs(1), device.next())
            .await
            .expect("a forwarded frame must arrive within one second")
            .expect("a message must arrive")
            .expect("no transport error");
        let elapsed = sent_at.elapsed();
        match received {
            WsMessage::Binary(bytes) => assert_eq!(bytes.as_ref(), payload.as_slice()),
            other => panic!("expected the forwarded binary frame, got {other:?}"),
        }
        samples.push(elapsed);
    }
    server.abort();
    unsafe {
        std::env::remove_var("HERDR_RELAY_FRAME_RATE");
    }

    samples.sort_unstable();
    let p50 = samples[samples.len() / 2];
    let p99 = samples[samples.len() * 99 / 100];
    println!("p50={p50:?} p99={p99:?} (n={SAMPLES})");
    // R-12-006 bounds *added* relay latency (ingress to egress); the relay MUST
    // NOT inspect a frame to timestamp it (R-12-003), so a client-observed round
    // trip — two loopback TCP hops plus the relay's own forwarding — is the
    // closest external proxy available. Measured on this loopback harness: p50
    // around 30-70 microseconds, p99 around 50-90 microseconds, two orders of
    // magnitude under the bound, so asserting the doc's exact numbers directly
    // still leaves ample headroom for a slower CI container.
    assert!(p50 < Duration::from_millis(5), "p50 too high: {p50:?}");
    assert!(p99 < Duration::from_millis(20), "p99 too high: {p99:?}");
}
