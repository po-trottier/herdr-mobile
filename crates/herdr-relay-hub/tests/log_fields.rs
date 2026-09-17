//! Asserts every log line the relay emits is a single valid JSON object
//! (`docs/12-relay-hosting.md` R-12-040) and carries no field outside the
//! R-12-041 allow list: `ts`, `event`, `handle_first_6`,
//! `peer`, `active_handles`, `frames_forwarded`, `bytes_forwarded`, `duration_ms`,
//! `error_code`, `error_message` — nothing else may ever appear in a log line
//! (`docs/90-implementation-plan.md` §Phase 8, WP-8 `Owns.`).
//!
//! Spawns the real compiled `herdr-relay-hub` binary as a subprocess and reads its
//! actual stdout, rather than calling the crate in-process: the JSON subscriber
//! `crates/herdr-relay-hub/src/routes/logging.rs` installs is crate-private
//! (`pub(crate) mod logging`, nested under `routes` — see that module's own doc
//! comment for why), so an external test crate has no other way to observe what a
//! real deployment's stdout actually contains. This also proves the end-to-end
//! wiring `main.rs` does (env vars, `routes::build()`, the subscriber install),
//! not just the formatting function in isolation.

use std::io::{BufRead, BufReader};
use std::net::SocketAddr;
use std::process::{Child, Command, Stdio};
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use serde_json::Value;
use tokio_tungstenite::tungstenite::Message as WsMessage;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::protocol::frame::coding::CloseCode as WsCloseCode;
use tokio_tungstenite::{MaybeTlsStream, WebSocketStream};

/// The exact, closed R-12-041 field allow list.
const ALLOWED_FIELDS: &[&str] = &[
    "ts",
    "event",
    "handle_first_6",
    "peer",
    "active_handles",
    "frames_forwarded",
    "bytes_forwarded",
    "duration_ms",
    "error_code",
    "error_message",
];

/// The exact, closed R-12-041 `event` value list.
const ALLOWED_EVENTS: &[&str] = &[
    "host_connected",
    "host_disconnected",
    "device_connected",
    "device_disconnected",
    "relay_started",
    "push_disabled",
    "handle_expired",
    "error",
];

/// Binds an ephemeral loopback port, reads the address, then frees it again — the
/// child process binds it for real a moment later. A small TOCTOU window exists,
/// same as `tests/support/mod.rs`'s pattern of binding `127.0.0.1:0`, just with an
/// extra step because a subprocess (not this process) does the real bind.
async fn free_loopback_port() -> u16 {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .expect("binding a loopback ephemeral port must succeed in a test");
    listener
        .local_addr()
        .expect("a bound socket has a local address")
        .port()
}

struct RelayProcess {
    child: Child,
    addr: SocketAddr,
}

impl Drop for RelayProcess {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

async fn spawn_relay() -> (RelayProcess, std::sync::mpsc::Receiver<String>) {
    let port = free_loopback_port().await;
    let metrics_port = free_loopback_port().await;
    let addr: SocketAddr = format!("127.0.0.1:{port}")
        .parse()
        .expect("a valid loopback address");

    let mut child = Command::new(env!("CARGO_BIN_EXE_herdr-relay-hub"))
        .env("HERDR_RELAY_LISTEN", format!("127.0.0.1:{port}"))
        .env(
            "HERDR_RELAY_METRICS_LISTEN",
            format!("127.0.0.1:{metrics_port}"),
        )
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
        .expect("the compiled herdr-relay-hub binary must launch");
    let stdout = child.stdout.take().expect("stdout was piped");

    // A plain background thread, not a tokio task: `std::process::Child`'s stdout
    // is a blocking `std::fs::File`-backed pipe, and this only needs to forward
    // lines to the async test as they arrive.
    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        for line in BufReader::new(stdout).lines() {
            let Ok(line) = line else { break };
            if tx.send(line).is_err() {
                break;
            }
        }
    });

    // Poll until the acceptor is actually listening, rather than a fixed sleep.
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    loop {
        if tokio::net::TcpStream::connect(addr).await.is_ok() {
            break;
        }
        assert!(
            tokio::time::Instant::now() < deadline,
            "the relay did not start listening in time"
        );
        tokio::time::sleep(Duration::from_millis(20)).await;
    }

    (RelayProcess { child, addr }, rx)
}

async fn connect_and_register(
    addr: SocketAddr,
    role: &str,
    handle: &str,
) -> WebSocketStream<MaybeTlsStream<tokio::net::TcpStream>> {
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

/// Connects a Host and a Device on one handle, then closes both, Device first.
/// The Host's socket stays open across the Device's join: under R-11-125 the
/// room dies with either peer, so a Device that joined after the Host left would
/// be refused with `handle_unknown` (R-11-117) instead of `session_joined`.
async fn connect_pair_and_disconnect(addr: SocketAddr, handle: &str) {
    let mut host = connect_and_register(addr, "host", handle).await;
    let mut device = connect_and_register(addr, "device", handle).await;
    device
        .close(None)
        .await
        .expect("a clean close must succeed");
    // R-11-125, R-12-038: the Device's close ends the room, so the relay closes
    // the Host's socket at once with `1001` and a reason that names the Device.
    let close = host
        .next()
        .await
        .expect("the relay's close of the Host must arrive")
        .expect("no transport error");
    match close {
        WsMessage::Close(Some(frame)) => {
            assert_eq!(frame.code, WsCloseCode::from(1001), "going_away (R-12-038)");
            assert_eq!(frame.reason.as_str(), "the Device is gone");
        }
        other => panic!("expected a Close(1001) message, got {other:?}"),
    }
    // Dropping the socket ends the Host's connection task: reading the relay's
    // close already queued this side's own close reply, so a second explicit
    // close would fail with `SendAfterClosing`.
    drop(host);
}

/// Connects two Hosts on the same handle: the second gets `handle_taken`
/// (R-11-118), which fires `close_with_error` -> `logging::error` with
/// `error_code="handle_taken"`, the scenario this test needs to prove the
/// R-12-041 `error_code` field is wired end to end.
async fn trigger_handle_taken_error(addr: SocketAddr, handle: &str) {
    let url = format!("ws://{addr}/host/{handle}");
    let mut request = url
        .into_client_request()
        .expect("a loopback ws URL always builds a valid request");
    request.headers_mut().insert(
        "sec-websocket-protocol",
        "herdr-relay.v1"
            .parse()
            .expect("a static header value always parses"),
    );
    let (mut first, _) = tokio_tungstenite::connect_async(request)
        .await
        .expect("the relay must accept the first upgrade");
    first
        .send(WsMessage::Text(
            r#"{"type":"host_register","protocol":1}"#.into(),
        ))
        .await
        .expect("send must succeed on a fresh socket");
    first
        .next()
        .await
        .expect("session_joined must arrive")
        .expect("no transport error");

    let mut request2 = format!("ws://{addr}/host/{handle}")
        .into_client_request()
        .expect("a loopback ws URL always builds a valid request");
    request2.headers_mut().insert(
        "sec-websocket-protocol",
        "herdr-relay.v1"
            .parse()
            .expect("a static header value always parses"),
    );
    let (mut second, _) = tokio_tungstenite::connect_async(request2)
        .await
        .expect("the relay must accept the second upgrade");
    second
        .send(WsMessage::Text(
            r#"{"type":"host_register","protocol":1}"#.into(),
        ))
        .await
        .expect("send must succeed on a fresh socket");
    let reply = second
        .next()
        .await
        .expect("an error frame must arrive")
        .expect("no transport error");
    assert!(
        matches!(&reply, WsMessage::Text(t) if t.contains("handle_taken")),
        "expected a handle_taken error frame, got {reply:?}"
    );
    drop(second);
    drop(first);
}

#[tokio::test]
async fn no_log_line_carries_a_field_outside_the_r_12_041_allow_list() {
    let (relay, lines) = spawn_relay().await;
    let handle = "n6Loxf94CfyIO6hOxlaHvA";
    connect_pair_and_disconnect(relay.addr, handle).await;
    trigger_handle_taken_error(relay.addr, "AAAAAAAAAAAAAAAAAAAAAA").await;

    // Give the server-side disconnect handling a moment to log, then stop it —
    // its own shutdown produces no further log lines to wait for.
    tokio::time::sleep(Duration::from_millis(200)).await;
    drop(relay);

    let mut seen_events = std::collections::HashSet::new();
    let mut line_count = 0;
    while let Ok(line) = lines.recv_timeout(Duration::from_millis(200)) {
        line_count += 1;
        let parsed: Value = serde_json::from_str(&line).unwrap_or_else(|error| {
            panic!("line {line_count} is not valid JSON ({error}): {line}")
        });
        let object = parsed
            .as_object()
            .unwrap_or_else(|| panic!("line {line_count} is not a JSON object: {line}"));

        for key in object.keys() {
            assert!(
                ALLOWED_FIELDS.contains(&key.as_str()),
                "line {line_count} has a field '{key}' outside the R-12-041 allow list: {line}"
            );
        }
        assert!(
            object.contains_key("ts"),
            "line {line_count} is missing 'ts': {line}"
        );
        assert!(
            object.contains_key("event"),
            "line {line_count} is missing 'event': {line}"
        );

        let ts = object["ts"].as_str().expect("ts is a string");
        assert!(
            is_iso8601_with_millis(ts),
            "line {line_count}'s ts '{ts}' is not ISO 8601 with millisecond precision: {line}"
        );

        let event = object["event"].as_str().expect("event is a string");
        assert!(
            ALLOWED_EVENTS.contains(&event),
            "line {line_count}'s event '{event}' is outside the R-12-041 event list: {line}"
        );
        seen_events.insert(event.to_owned());

        if let Some(h6) = object.get("handle_first_6").and_then(Value::as_str) {
            assert_eq!(
                h6.len(),
                6,
                "line {line_count}'s handle_first_6 must be exactly 6 characters, never the full handle: {line}"
            );
            assert_ne!(
                h6, handle,
                "line {line_count} must never log the full handle: {line}"
            );
        }

        if event == "error" {
            let error_code = object
                .get("error_code")
                .and_then(Value::as_str)
                .unwrap_or_else(|| {
                    panic!("line {line_count} is an error event missing error_code: {line}")
                });
            assert!(
                !error_code.is_empty(),
                "line {line_count}'s error_code must be non-empty: {line}"
            );
            assert!(
                object.contains_key("error_message"),
                "line {line_count} is an error event missing error_message: {line}"
            );
        }
    }

    assert!(
        line_count >= 5,
        "expected at least relay_started, two connects, two disconnects, plus one error, got {line_count} lines"
    );
    assert!(seen_events.contains("relay_started"));
    assert!(seen_events.contains("host_connected"));
    assert!(seen_events.contains("device_connected"));
    assert!(
        seen_events.contains("error"),
        "expected an error event from the handle_taken rejection"
    );
}

/// `YYYY-MM-DDTHH:MM:SS.mmmZ`, matched by hand rather than adding a regex
/// dependency for one fixed-width check.
fn is_iso8601_with_millis(ts: &str) -> bool {
    let bytes = ts.as_bytes();
    bytes.len() == 24
        && bytes[4] == b'-'
        && bytes[7] == b'-'
        && bytes[10] == b'T'
        && bytes[13] == b':'
        && bytes[16] == b':'
        && bytes[19] == b'.'
        && bytes[23] == b'Z'
        && ts[0..4].bytes().all(|b| b.is_ascii_digit())
        && ts[5..7].bytes().all(|b| b.is_ascii_digit())
        && ts[8..10].bytes().all(|b| b.is_ascii_digit())
        && ts[11..13].bytes().all(|b| b.is_ascii_digit())
        && ts[14..16].bytes().all(|b| b.is_ascii_digit())
        && ts[17..19].bytes().all(|b| b.is_ascii_digit())
        && ts[20..23].bytes().all(|b| b.is_ascii_digit())
}
