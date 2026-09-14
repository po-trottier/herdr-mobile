//! Asserts each of the four `docs/12-relay-hosting.md` rate/size limits (R-12-031
//! connection rate, R-12-032 frame rate, R-12-033 handle-registration rate,
//! R-12-034 total-handle cap) closes the offending connection with `rate_limited`
//! (`4008`) (`docs/90-implementation-plan.md` §Phase 8, WP-8 `Owns.`).
//!
//! Self-contained: builds its own minimal WebSocket harness with `tokio-tungstenite`
//! rather than `tests/support/mod.rs` (owned by `WP-3`/Phase 3, whose four tests
//! never need to open a connection that a rate limit rejects mid-handshake).
//!
//! All four scenarios run inside one `#[tokio::test]` sequentially, each setting
//! only the one `HERDR_RELAY_*` variable it needs to a small, fast-to-exercise
//! value: `Config::from_env()` (`crates/herdr-relay-hub/src/routes/config.rs`) is
//! re-read fresh on every `router()` call rather than cached in a process-wide
//! static, so this is race-free as long as no other test function in this same
//! binary also touches the environment (none does).

use std::net::SocketAddr;

use futures_util::{SinkExt, StreamExt};
use tokio::net::TcpListener;
use tokio_tungstenite::tungstenite::Message as WsMessage;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::{MaybeTlsStream, WebSocketStream};

type Stream = WebSocketStream<MaybeTlsStream<tokio::net::TcpStream>>;

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

/// Just the WebSocket upgrade — fast regardless of what the relay does next, since
/// axum answers the HTTP upgrade before the connection handler even runs.
async fn raw_upgrade(addr: SocketAddr, role: &str, handle: &str) -> Stream {
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
    let (stream, _response) = tokio_tungstenite::connect_async(request)
        .await
        .expect("the relay must accept the WebSocket upgrade even when it will reject next");
    stream
}

/// Full registration handshake (R-11-113/114/115), keeping the stream open so a
/// caller can drive more frames on it (the frame-rate scenario needs this; the
/// others just inspect the reply and let the stream drop).
async fn connect_and_register(addr: SocketAddr, role: &str, handle: &str) -> (Stream, WsMessage) {
    let mut stream = raw_upgrade(addr, role, handle).await;
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
        .expect("a reply must arrive")
        .expect("no transport error");
    (stream, reply)
}

fn assert_rate_limited(reply: &WsMessage, scenario: &str) {
    match reply {
        WsMessage::Close(Some(frame)) => {
            assert_eq!(
                u16::from(frame.code),
                4008,
                "{scenario}: expected rate_limited (4008), got close code {}",
                frame.code
            );
        }
        WsMessage::Text(text) => {
            assert!(
                text.contains("rate_limited"),
                "{scenario}: expected a rate_limited error frame, got {text}"
            );
        }
        other => panic!("{scenario}: expected a rate_limited close or error frame, got {other:?}"),
    }
}

fn assert_session_joined(reply: &WsMessage, scenario: &str) {
    assert!(
        matches!(reply, WsMessage::Text(t) if t.contains("session_joined")),
        "{scenario}: expected session_joined, got {reply:?}"
    );
}

/// A 22-character base64url fixture handle, distinct per `n`. Varies the *first*
/// character, not the last: the final two characters of a 22-character handle
/// form a partial base64 group whose trailing bits must decode to zero, which
/// only a handful of characters satisfy (`A`, `Q`, `g`, `w`) — the first
/// character sits in a full four-character group with no such constraint.
fn fixture_handle(n: u8) -> String {
    format!("{n}AAAAAAAAAAAAAAAAAAAAA")
}

#[tokio::test]
async fn all_four_limits_return_rate_limited() {
    // Scenario 1: connection rate (R-12-031) — the limiter rejects before the
    // relay ever reads a registration frame. Open all three raw upgrades back to
    // back before reading anything: the first two never send a registration
    // frame, so *reading* from them would block for the full 10-second
    // registration timeout and push the third connection outside the one-second
    // rate window, defeating the scenario.
    unsafe {
        std::env::set_var("HERDR_RELAY_CONNECTION_RATE", "2");
    }
    let (addr, server) = start_relay().await;
    let _first = raw_upgrade(addr, "host", &fixture_handle(1)).await;
    let _second = raw_upgrade(addr, "host", &fixture_handle(2)).await;
    let mut third = raw_upgrade(addr, "host", &fixture_handle(3)).await;
    let reply = third
        .next()
        .await
        .expect("a message must arrive")
        .expect("no transport error");
    assert_rate_limited(&reply, "connection rate");
    server.abort();
    unsafe {
        std::env::remove_var("HERDR_RELAY_CONNECTION_RATE");
    }

    // Scenario 2: frame rate (R-12-032) — one joined Host exceeds its own
    // per-connection budget and is closed on its own socket. Send the whole
    // burst before reading anything back, for the same reason as scenario 1:
    // forwarded frames get no reply, so reading after each send would burn a
    // wait per frame and could push the burst outside the one-second window.
    unsafe {
        std::env::set_var("HERDR_RELAY_FRAME_RATE", "5");
    }
    let (addr, server) = start_relay().await;
    let handle = fixture_handle(4);
    let (mut host, joined) = connect_and_register(addr, "host", &handle).await;
    assert_session_joined(&joined, "frame rate setup");
    for _ in 0..20 {
        if host
            .send(WsMessage::Binary(b"x".to_vec().into()))
            .await
            .is_err()
        {
            break;
        }
    }
    let reply = tokio::time::timeout(std::time::Duration::from_secs(2), host.next())
        .await
        .expect("the Host must be closed for exceeding the frame rate")
        .expect("a message must arrive")
        .expect("no transport error");
    assert_rate_limited(&reply, "frame rate");
    server.abort();
    unsafe {
        std::env::remove_var("HERDR_RELAY_FRAME_RATE");
    }

    // Scenario 3: handle-registration rate (R-12-033) — new handles from one IP.
    // Each `connect_and_register` call gets a fast reply either way (no
    // 10-second wait involved), so three sequential calls comfortably fit
    // inside the one-second window.
    unsafe {
        std::env::set_var("HERDR_RELAY_HANDLE_RATE", "2");
    }
    let (addr, server) = start_relay().await;
    connect_and_register(addr, "host", &fixture_handle(5)).await;
    connect_and_register(addr, "host", &fixture_handle(6)).await;
    let (_stream, third) = connect_and_register(addr, "host", &fixture_handle(7)).await;
    assert_rate_limited(&third, "handle-registration rate");
    server.abort();
    unsafe {
        std::env::remove_var("HERDR_RELAY_HANDLE_RATE");
    }

    // Scenario 4: total-handle cap (R-12-034). No rate window involved at all —
    // the cap only checks the live handle count. The two setup streams must stay
    // open until the probe runs: a dropped socket ends its room at once
    // (R-11-125), so dropped setup connections would free the cap again.
    unsafe {
        std::env::set_var("HERDR_RELAY_MAX_HANDLES", "2");
    }
    let (addr, server) = start_relay().await;
    let (_first, _) = connect_and_register(addr, "host", &fixture_handle(8)).await;
    let (_second, _) = connect_and_register(addr, "host", &fixture_handle(9)).await;
    let (_stream, third) = connect_and_register(addr, "host", &fixture_handle(0)).await;
    assert_rate_limited(&third, "max handles");
    server.abort();
    unsafe {
        std::env::remove_var("HERDR_RELAY_MAX_HANDLES");
    }
}
