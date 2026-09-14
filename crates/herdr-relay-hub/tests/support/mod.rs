//! Shared test harness: starts the relay's real router on an ephemeral loopback port
//! and gives each test a plain `ws://` client connection with the required
//! subprotocol already offered (`docs/90-implementation-plan.md` §Phase 3 test boxes).
//!
//! Lives under `tests/support/mod.rs`, not `tests/support.rs`, so Cargo does not treat
//! it as its own integration-test binary; it is a module the four Phase 3 test files
//! include with `mod support;`.
//!
//! ponytail: each of the four test binaries below recompiles this module and only
//! some use every helper (e.g. only `handle_isolation.rs` needs `HANDLE_B` and
//! `expect_silence`), which `rustc` flags as dead code per compilation unit. A
//! shared, over-provisioned test helper module is the standard shape for this; allow
//! it here rather than duplicating helpers per test file to silence the lint.
#![allow(
    dead_code,
    reason = "shared test harness: some binaries use only a subset of these helpers, and rustc flags the rest as dead code per compilation unit (R-41-116)"
)]

use std::net::SocketAddr;
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use tokio::net::{TcpListener, TcpStream};
use tokio_tungstenite::tungstenite::Message as WsMessage;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::{MaybeTlsStream, WebSocketStream};

/// The doc's own worked-example handle (`docs/11-relay-protocol.md` §2.1).
pub const HANDLE_A: &str = "n6Loxf94CfyIO6hOxlaHvA";
/// A second, distinct 22-character handle, valid base64url decoding to 16 zero bytes.
/// A fixture, never a real routing handle.
pub const HANDLE_B: &str = "AAAAAAAAAAAAAAAAAAAAAA";

/// How long a test waits for a message before concluding one will never arrive.
const RECV_TIMEOUT: Duration = Duration::from_millis(500);

/// A running relay instance for one test. Dropping it stops the server task.
pub struct Relay {
    addr: SocketAddr,
    server: tokio::task::JoinHandle<()>,
}

impl Relay {
    /// Starts the relay's real router on an OS-assigned loopback port.
    pub async fn start() -> Self {
        let listener = TcpListener::bind("127.0.0.1:0")
            .await
            .expect("binding a loopback ephemeral port must succeed in a test");
        let addr = listener
            .local_addr()
            .expect("a bound socket has a local address");
        let app = herdr_relay_hub::routes::router();
        let server = tokio::spawn(async move {
            // R-12-031's connection-rate limiter keys off ConnectInfo (WP-8).
            axum::serve(
                listener,
                app.into_make_service_with_connect_info::<SocketAddr>(),
            )
            .await
            .expect("the test relay must not fail to serve");
        });
        Self { addr, server }
    }

    /// Connects a client to `/host/<handle>` or `/device/<handle>` with the relay
    /// subprotocol already offered (R-12-020), then sends the R-11-113/R-11-114
    /// registration frame `role` requires and consumes a `session_joined` reply
    /// (R-11-115). A refused registration's `error` frame (R-11-116) is not
    /// `session_joined`, so it is kept for the caller's own `recv()` instead of
    /// being discarded here.
    pub async fn connect(&self, role: &str, handle: &str) -> WsClient {
        let url = format!("ws://{}/{role}/{handle}", self.addr);
        let mut request = url
            .into_client_request()
            .expect("a loopback ws URL always builds a valid request");
        request.headers_mut().insert(
            "sec-websocket-protocol",
            "herdr-relay.v1"
                .parse()
                .expect("a static header value always parses"),
        );
        let (stream, _response) = tokio_tungstenite::connect_async(request)
            .await
            .expect("the relay must accept the WebSocket upgrade");
        let mut client = WsClient {
            stream,
            pending: None,
        };
        client.register(role).await;
        client
    }
}

impl Drop for Relay {
    fn drop(&mut self) {
        self.server.abort();
    }
}

/// A thin client wrapper so test bodies read as plain send/receive, with the timeout
/// every assertion needs to fail instead of hanging (R-41-131).
pub struct WsClient {
    stream: WebSocketStream<MaybeTlsStream<TcpStream>>,
    /// A message [`Self::register`] already read off the wire but could not treat as
    /// `session_joined`, returned by the next [`Self::recv`] instead of being lost.
    pending: Option<WsMessage>,
}

impl WsClient {
    /// Sends the `host_register`/`device_register` frame R-11-113/R-11-114 requires
    /// for `role`, then consumes the relay's reply. A `session_joined` reply
    /// (R-11-115) is discarded here; anything else (an `error` frame ahead of a
    /// refusal's close, R-11-116) is buffered for the caller's own `recv()`.
    async fn register(&mut self, role: &str) {
        let frame = format!(r#"{{"type":"{role}_register","protocol":1}}"#);
        self.stream
            .send(WsMessage::Text(frame.into()))
            .await
            .expect("send must succeed on a live socket");
        let reply = self
            .recv()
            .await
            .expect("the relay must reply to registration before forwarding (R-11-115)");
        if !is_session_joined(&reply) {
            self.pending = Some(reply);
        }
    }

    /// Sends one opaque binary frame, standing in for Noise ciphertext (R-12-003).
    pub async fn send_binary(&mut self, bytes: Vec<u8>) {
        self.stream
            .send(WsMessage::Binary(bytes.into()))
            .await
            .expect("send must succeed on a live socket");
    }

    /// Waits up to [`RECV_TIMEOUT`] for the next message, returning a buffered
    /// [`Self::register`] reply first if one is pending.
    pub async fn recv(&mut self) -> Option<WsMessage> {
        if let Some(message) = self.pending.take() {
            return Some(message);
        }
        tokio::time::timeout(RECV_TIMEOUT, self.stream.next())
            .await
            .ok()?
            .map(|result| {
                result.expect("a WebSocket transport error is a test infrastructure failure")
            })
    }

    /// Confirms no message arrives within [`RECV_TIMEOUT`] (proves isolation/silence).
    pub async fn expect_silence(&mut self) {
        assert!(
            self.recv().await.is_none(),
            "expected no message to arrive, but one did"
        );
    }
}

/// `true` for the relay's `{"type":"session_joined",...}` reply (R-11-115). A
/// substring check is enough here: this is a test fixture, not a wire parser.
fn is_session_joined(message: &WsMessage) -> bool {
    matches!(message, WsMessage::Text(text) if text.as_str().contains("session_joined"))
}
