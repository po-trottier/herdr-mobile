//! `docs/90-implementation-plan.md` Phase 4 (`WP-4`): the Host half of the local Noise
//! interop proof `WP-14-a`/`WP-14-b`'s `Needs.` lines read from `WP-4`. Connects to a
//! real, locally-run `crates/herdr-relay-hub` instance (started separately, by the
//! caller, on `127.0.0.1` — never a public deployment) as the Host, registers on
//! `/host/<handle>`, then runs the Host (responder) side of `Noise_XXpsk0`
//! (`crates/herdr-relay/src/noise.rs`, R-13-014, R-13-071) against a Device (initiator)
//! that connects on `/device/<handle>`. `app/test/spike/noise_client_test.dart` drives
//! that Device side from `cryptography` 2.9.0 primitives and spawns this binary as a
//! subprocess; see its doc comment for the coordination protocol.
//!
//! Follows this crate's existing `src/bin/spike-*.rs` convention (`spike-read.rs`,
//! `spike-subscribe.rs`, `spike-input.rs`): a throwaway, standalone binary, not part of
//! the production Host plugin (R-90-016 — this file is not on any other work
//! package's owned-paths list).
//!
//! Every event this binary observes is printed to stdout as one JSON line, flushed
//! immediately, so the Dart test (or a human) can follow progress without parsing
//! `snow`/`tokio-tungstenite` internals. A failure prints one JSON line to stderr and
//! exits non-zero.

use std::env;
use std::io::Write;
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use herdr_relay::noise::{self, Role};
use serde_json::json;
use tokio_tungstenite::tungstenite::Message as WsMessage;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;

/// The relay subprotocol every connection MUST offer (R-11-013, R-12-020).
const SUBPROTOCOL: &str = "herdr-relay.v1";

/// Bounds every wait on the Device (R-41-131's blocking-I/O convention); the pairing
/// phrase itself is valid for 600 s (R-13-022), so 60 s leaves the Dart side plenty of
/// room to start its own runtime and still fail fast if something hangs.
const WAIT_TIMEOUT: Duration = Duration::from_secs(60);

/// The known plaintext the Host sends once transport mode is reached, and the
/// benchmark the Dart test asserts its decrypted `pane_frame`-stand-in against. Not a
/// real `docs/11-relay-protocol.md` frame envelope: Phase 14 owns that format. This
/// spike proves only that ciphertext round-trips between `snow` and `cryptography`.
const HOST_GREETING: &str = "herdr-relay-noise-interop: hello from the Rust Host";
/// The exact reply `app/test/spike/noise_client_test.dart` sends back (`_deviceReply`).
const DEVICE_REPLY: &str = "herdr-relay-noise-interop: hello from the Dart Device";

#[tokio::main]
async fn main() {
    if let Err(message) = run().await {
        emit_stderr(&message);
        std::process::exit(1);
    }
}

async fn run() -> Result<(), String> {
    let relay_addr = require_env("RELAY_ADDR")?;
    let handle = require_env("HANDLE")?;
    let phrase = require_env("PHRASE")?;

    let (host_private, _host_public) =
        noise::generate_keypair().map_err(|error| format!("keypair generation failed: {error}"))?;

    let url = format!("ws://{relay_addr}/host/{handle}");
    let mut request = url
        .into_client_request()
        .map_err(|error| format!("building the Host WebSocket request failed: {error}"))?;
    request.headers_mut().insert(
        "sec-websocket-protocol",
        SUBPROTOCOL
            .parse()
            .expect("the subprotocol constant is a valid header value"),
    );
    let (mut socket, _response) =
        tokio::time::timeout(WAIT_TIMEOUT, tokio_tungstenite::connect_async(request))
            .await
            .map_err(|_| "timed out connecting to the relay".to_owned())?
            .map_err(|error| format!("connecting to the relay failed: {error}"))?;

    // R-11-113: the Host registration frame.
    socket
        .send(WsMessage::Text(
            r#"{"type":"host_register","protocol":1}"#.into(),
        ))
        .await
        .map_err(|error| format!("sending host_register failed: {error}"))?;
    let joined = next_text(&mut socket).await?;
    if !joined.contains("session_joined") {
        return Err(format!("expected session_joined, got: {joined}"));
    }

    emit_stdout(&json!({ "event": "host_registered" }));

    // R-13-024: the PSK is derived from the phrase, never the raw phrase bytes.
    let psk = noise::psk_from_phrase(phrase.as_bytes());
    // R-13-071: the Host is the Noise responder.
    let mut handshake = noise::pairing_handshake(Role::Responder, &host_private, &psk)
        .map_err(|error| format!("building the responder handshake failed: {error}"))?;

    let msg1 = next_binary(&mut socket).await?;
    noise::read_handshake_message(&mut handshake, &msg1)
        .map_err(|error| format!("reading handshake message 1 failed: {error}"))?;

    let msg2 = noise::write_handshake_message(&mut handshake, &[])
        .map_err(|error| format!("writing handshake message 2 failed: {error}"))?;
    socket
        .send(WsMessage::Binary(msg2.into()))
        .await
        .map_err(|error| format!("sending handshake message 2 failed: {error}"))?;

    let msg3 = next_binary(&mut socket).await?;
    noise::read_handshake_message(&mut handshake, &msg3)
        .map_err(|error| format!("reading handshake message 3 failed: {error}"))?;

    let (mut transport, _device_public) = noise::finish_handshake(handshake)
        .map_err(|error| format!("finishing the handshake failed: {error}"))?;

    emit_stdout(&json!({ "event": "handshake_complete" }));

    let greeting_ct = transport
        .encrypt(HOST_GREETING.as_bytes())
        .map_err(|error| format!("encrypting the greeting failed: {error}"))?;
    socket
        .send(WsMessage::Binary(greeting_ct.into()))
        .await
        .map_err(|error| format!("sending the greeting failed: {error}"))?;

    let reply_ct = next_binary(&mut socket).await?;
    let reply_pt = transport
        .decrypt(&reply_ct)
        .map_err(|error| format!("decrypting the Device's reply failed: {error}"))?;
    let reply_text = String::from_utf8(reply_pt)
        .map_err(|error| format!("the Device's reply was not UTF-8: {error}"))?;

    // The plaintext never reaches stdout (AGENTS.md "Never log"); the Device test asserts
    // this boolean, computed here against the literal it sends.
    emit_stdout(&json!({
        "event": "reply_decrypted",
        "reply_matches_expected": reply_text == DEVICE_REPLY,
    }));

    Ok(())
}

fn require_env(name: &str) -> Result<String, String> {
    env::var(name).map_err(|_| format!("missing required environment variable {name}"))
}

fn emit_stdout(value: &serde_json::Value) {
    let mut out = std::io::stdout();
    let _ = writeln!(out, "{value}");
    let _ = out.flush();
}

fn emit_stderr(message: &str) {
    let mut err = std::io::stderr();
    let line = json!({"event": "error", "message": message});
    let _ = writeln!(err, "{line}");
    let _ = err.flush();
}

type Socket =
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

async fn next_text(socket: &mut Socket) -> Result<String, String> {
    match next_message(socket).await? {
        WsMessage::Text(text) => Ok(text.to_string()),
        other => Err(format!("expected a text frame, got: {other:?}")),
    }
}

async fn next_binary(socket: &mut Socket) -> Result<Vec<u8>, String> {
    match next_message(socket).await? {
        WsMessage::Binary(bytes) => Ok(bytes.to_vec()),
        other => Err(format!("expected a binary frame, got: {other:?}")),
    }
}

async fn next_message(socket: &mut Socket) -> Result<WsMessage, String> {
    tokio::time::timeout(WAIT_TIMEOUT, socket.next())
        .await
        .map_err(|_| "timed out waiting for the next frame".to_owned())?
        .ok_or_else(|| "the relay closed the connection".to_owned())?
        .map_err(|error| format!("reading from the relay failed: {error}"))
}
