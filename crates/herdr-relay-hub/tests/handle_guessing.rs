//! Phase 23 security review (`docs/90-implementation-plan.md` §Phase 23, item 6): attempts to
//! guess a routing handle against a real, running relay and records the refusal behaviour
//! (R-13-033, R-12-031). Results are written up in
//! `docs/security/review-pack/handle-guessing.md`.
//!
//! Self-contained, like `tests/limits.rs`: this file deliberately exercises the *default*
//! `HERDR_RELAY_CONNECTION_RATE` (10/sec/IP, R-12-031) rather than raising or lowering it, and a
//! guessing connection must never complete the shared `tests/support/mod.rs` `Relay::connect`
//! round trip (it always sends a registration frame and unconditionally awaits a reply — the
//! wrong shape once a guess gets rejected before ever reading that frame), so this builds its
//! own minimal harness the same way `tests/limits.rs` already does.

use std::net::SocketAddr;
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use tokio::net::TcpListener;
use tokio_tungstenite::tungstenite::Message as WsMessage;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::{MaybeTlsStream, WebSocketStream};

type Stream = WebSocketStream<MaybeTlsStream<tokio::net::TcpStream>>;

/// How long one probe waits for a reply before it counts as a hang.
const RECV_TIMEOUT: Duration = Duration::from_millis(500);

/// The real, registered handle an attacker is trying to reach without knowing it — the doc's own
/// worked example (`docs/11-relay-protocol.md` §2.1), same as `tests/support/mod.rs::HANDLE_A`.
const REAL_HANDLE: &str = "n6Loxf94CfyIO6hOxlaHvA";

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

async fn raw_upgrade(addr: SocketAddr, role: &str, handle: &str) -> Stream {
    let url = format!("ws://{addr}/{role}/{handle}");
    let mut request = url
        .into_client_request()
        .expect("a loopback ws URL always builds a valid request");
    request.headers_mut().insert(
        "sec-websocket-protocol",
        "herdr-relay.v1"
            .parse()
            .expect("static header value always parses"),
    );
    let (stream, _response) = tokio_tungstenite::connect_async(request)
        .await
        .expect("the relay must accept the WebSocket upgrade even when it will reject next");
    stream
}

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

/// 100 syntactically-valid-but-wrong 22-character base64url handles, all distinct from
/// [`REAL_HANDLE`] by construction: each ends in the same `..AA` two-character tail
/// `tests/limits.rs`'s own `fixture_handle` uses (the last base64 group's trailing bits must
/// decode to zero; `A` is one of the few characters that satisfies this), so every generated
/// string is itself a valid `Handle` — a real attacker's best-case guess, not noise a `protocol_error`
/// would catch for free.
fn guess_handles() -> Vec<String> {
    let alphabet = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    (0..100)
        .map(|i: usize| {
            let c1 = alphabet[i % alphabet.len()] as char;
            let c2 = alphabet[(i / alphabet.len()) % alphabet.len()] as char;
            format!("{c1}{c2}AAAAAAAAAAAAAAAAAAAA")
        })
        .collect()
}

/// One guess attempt: upgrades, sends a Device registration frame (harmless if the connection is
/// rejected before reading it — R-12-031's rejection never depends on client input), then reads
/// the R-11-116 error frame and the close frame that follows it. Every relay rejection path
/// (`close_with_error`, `crates/herdr-relay-hub/src/routes/connection.rs`) sends exactly this
/// two-message shape, whichever reason fired.
async fn attempt_guess(addr: SocketAddr, handle: &str) -> String {
    let mut stream = raw_upgrade(addr, "device", handle).await;
    let _ = stream
        .send(WsMessage::Text(
            r#"{"type":"device_register","protocol":1}"#.into(),
        ))
        .await;
    let first = match tokio::time::timeout(RECV_TIMEOUT, stream.next()).await {
        Err(_) => return "hang".to_owned(),
        Ok(None) => return "eof_before_reply".to_owned(),
        Ok(Some(Err(e))) => return format!("transport_error:{e}"),
        Ok(Some(Ok(message))) => message,
    };
    let code = match &first {
        WsMessage::Text(t) if t.contains("handle_unknown") => "handle_unknown",
        WsMessage::Text(t) if t.contains("rate_limited") => "rate_limited",
        other => return format!("unexpected_first_message:{other:?}"),
    };
    match tokio::time::timeout(RECV_TIMEOUT, stream.next()).await {
        Ok(Some(Ok(WsMessage::Close(Some(frame))))) => format!("{code}_{}", u16::from(frame.code)),
        other => format!("{code}_but_no_clean_close:{other:?}"),
    }
}

#[tokio::test]
async fn guessing_a_handle_never_reaches_the_real_session_and_trips_the_rate_limit() {
    let (addr, server) = start_relay().await;

    // A real Host and a real Device join the one handle an attacker does not know — something
    // worth protecting, and a live session whose isolation the guessing barrage below must not
    // disturb.
    let (mut host, host_joined) = connect_and_register(addr, "host", REAL_HANDLE).await;
    assert!(
        matches!(&host_joined, WsMessage::Text(t) if t.contains("session_joined")),
        "expected the real Host to join cleanly, got {host_joined:?}"
    );
    let (mut device, device_joined) = connect_and_register(addr, "device", REAL_HANDLE).await;
    assert!(
        matches!(&device_joined, WsMessage::Text(t) if t.contains("session_joined")),
        "expected the real Device to join cleanly, got {device_joined:?}"
    );

    // The guessing barrage: 100 syntactically valid, wrong handles, back to back, fast enough
    // (this crate's own `IpRateLimiter` is a real one-second sliding window,
    // `crates/herdr-relay-hub/src/routes/limits.rs`) to exceed R-12-031's default 10
    // connections/second/IP partway through.
    let handles = guess_handles();
    let mut outcomes: std::collections::BTreeMap<String, usize> = std::collections::BTreeMap::new();
    for handle in &handles {
        let outcome = attempt_guess(addr, handle).await;
        *outcomes.entry(outcome).or_insert(0) += 1;
    }
    println!("handle_guessing: {} guesses against {addr}", handles.len());
    for (outcome, count) in &outcomes {
        println!("  {outcome}: {count}");
    }

    // Every guess was refused with one of exactly two documented codes: `handle_unknown` (4001,
    // R-13-033 — the relay does not recognize the handle) once inside the connection-rate
    // budget, or `rate_limited` (4008, R-12-031) once the guessing itself tripped the limiter.
    // No guess ever received `session_joined`, a forwarded frame, or anything else.
    for (outcome, count) in &outcomes {
        assert!(
            outcome == "handle_unknown_4001" || outcome == "rate_limited_4008",
            "unexpected refusal outcome {outcome} ({count} occurrences) for a handle guess"
        );
    }
    assert!(
        outcomes.contains_key("handle_unknown_4001"),
        "expected at least some guesses to be refused with handle_unknown before the rate limit tripped"
    );
    assert!(
        outcomes.contains_key("rate_limited_4008"),
        "expected the guessing burst to exceed R-12-031's default 10 connections/sec/IP and trip \
         rate_limited; if this ever fails, the burst above is no longer fast enough on this \
         machine to exceed the limit within one second"
    );

    // The real session survived the entire barrage undisturbed: the Host's traffic still reaches
    // only the real Device, and nothing else received it (every guessing connection's own
    // `attempt_guess` above already asserted it saw exactly its own refusal and nothing more).
    let payload = b"the-real-session-is-still-here-after-100-guesses".to_vec();
    host.send(WsMessage::Binary(payload.clone().into()))
        .await
        .expect("send must succeed on the still-live real Host connection");
    let received = tokio::time::timeout(RECV_TIMEOUT, device.next())
        .await
        .expect("the real Device must still receive the Host's frame, not hang")
        .expect("a message must arrive")
        .expect("no transport error");
    assert_eq!(
        received,
        WsMessage::Binary(payload.into()),
        "the real Device must receive exactly what the real Host sent, unaffected by the guessing barrage"
    );

    server.abort();
}
