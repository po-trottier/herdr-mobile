//! `docs/90-implementation-plan.md` Phase 23: "Capture every byte on both relay legs
//! during a full session and confirm no plaintext terminal content appears, recording
//! the capture in `docs/security/review-pack/`" (R-13-002, R-12-003).
//!
//! Extends the same real-TCP harness `ciphertext_only.rs` uses (`mod support`,
//! `Relay::start()`/`relay.connect()`: a real loopback `TcpListener` serving the
//! crate's own `axum` router, and a real `ws://` client connecting to it over that
//! socket — not an in-process function call). Where `ciphertext_only.rs` only
//! *asserts* the relay forwarded no plaintext, this test additionally *records* the
//! exact bytes it observed on each of the two WebSocket connections ("legs") to disk,
//! so the review pack holds a reproducible artifact.
//!
//! A "leg" is one of the relay's two WebSocket connections for this session: the
//! Host's (`/host/<handle>`) or the Device's (`/device/<handle>`). Every frame the
//! relay forwards crosses both legs once (it arrives on one, leaves on the other), so
//! capturing each leg's traffic independently — rather than one merged stream —
//! proves neither socket individually ever carried plaintext.

mod support;

use std::path::Path;

use herdr_relay::noise::{self, Role};
use support::{HANDLE_A, Relay};
use tokio_tungstenite::tungstenite::Message as WsMessage;

/// This crate's own manifest directory is `crates/herdr-relay-hub`; the repo root
/// (where `docs/` lives) is two levels up. `env!` reads this at compile time, so the
/// resulting path is correct regardless of the test binary's runtime working
/// directory (Cargo runs it with the package directory as `cwd`, not the repo root).
const REPO_ROOT: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");

/// The docs' own worked pairing phrase (`docs/11-relay-protocol.md` §8.1).
const PHRASE: &str = "remedy-tapestry-hubcap-oversleep-jailbird-kinetic";

/// The plaintext this test proves never reaches the wire in the clear: a realistic
/// terminal pane dump, sent as one of the Host's encrypted application frames
/// (R-13-002's own "terminal content" wording).
const TERMINAL_MARKER: &[u8] = b"$ ls -la\nfile1.txt\nfile2.txt\n";

/// Four realistic-looking Host application frames — a terminal session's own output —
/// one of which is [`TERMINAL_MARKER`]. Combined with the one `Noise_XXpsk0`
/// handshake message the Host (responder) sends, the Host sends five ciphertext
/// frames in total, meeting this checkbox's ">= 5 frames" bar.
const HOST_MESSAGES: [&[u8]; 4] = [
    b"connected to pane 1\n",
    TERMINAL_MARKER,
    b"$ echo hello\nhello\n",
    b"$ pwd\n/home/user\n",
];

/// A single keystroke event, the smallest realistic Device-to-Host frame
/// (R-11-026's per-keystroke framing) — long enough that it cannot appear in random
/// ciphertext by chance, so [`assert_no_substring`] on it is a meaningful check.
const DEVICE_KEYSTROKE: &[u8] = b"key:l\n";

#[tokio::test]
async fn relay_legs_carry_only_ciphertext_across_a_full_session() {
    let relay = Relay::start().await;
    let mut host = relay.connect("host", HANDLE_A).await;
    let mut device = relay.connect("device", HANDLE_A).await;

    let (host_private, _host_public) = noise::generate_keypair().unwrap();
    let (device_private, _device_public) = noise::generate_keypair().unwrap();
    let psk = noise::psk_from_phrase(PHRASE.as_bytes());

    // R-13-071: Device is the Noise initiator, Host is the responder.
    let mut initiator = noise::pairing_handshake(Role::Initiator, &device_private, &psk).unwrap();
    let mut responder = noise::pairing_handshake(Role::Responder, &host_private, &psk).unwrap();

    // Every raw frame captured on each leg, in wire order, captured at the same
    // `send_binary`/`recv` call sites the test itself drives — so these are the
    // actual bytes that crossed each real TCP connection, not a reconstruction.
    let mut host_leg: Vec<Vec<u8>> = Vec::new();
    let mut device_leg: Vec<Vec<u8>> = Vec::new();

    let msg1 = noise::write_handshake_message(&mut initiator, &[]).unwrap();
    device_leg.push(msg1.clone());
    device.send_binary(msg1.clone()).await;
    let received1 = host.recv().await.expect("the Host must receive message 1");
    host_leg.push(binary_payload(received1));
    noise::read_handshake_message(&mut responder, &msg1).unwrap();

    let msg2 = noise::write_handshake_message(&mut responder, &[]).unwrap();
    host_leg.push(msg2.clone());
    host.send_binary(msg2.clone()).await;
    let received2 = device
        .recv()
        .await
        .expect("the Device must receive message 2");
    device_leg.push(binary_payload(received2));
    noise::read_handshake_message(&mut initiator, &msg2).unwrap();

    let msg3 = noise::write_handshake_message(&mut initiator, &[]).unwrap();
    device_leg.push(msg3.clone());
    device.send_binary(msg3.clone()).await;
    let received3 = host.recv().await.expect("the Host must receive message 3");
    host_leg.push(binary_payload(received3));
    noise::read_handshake_message(&mut responder, &msg3).unwrap();

    assert!(initiator.is_handshake_finished());
    assert!(responder.is_handshake_finished());
    let (mut initiator_transport, _host_public_seen) = noise::finish_handshake(initiator).unwrap();
    let (mut responder_transport, _device_public_seen) =
        noise::finish_handshake(responder).unwrap();

    // The Host's side of a full session: four ciphertext application frames, one
    // carrying the terminal-content marker.
    for plaintext in HOST_MESSAGES {
        let ciphertext = responder_transport.encrypt(plaintext).unwrap();
        host_leg.push(ciphertext.clone());
        host.send_binary(ciphertext.clone()).await;
        let received = device
            .recv()
            .await
            .expect("the Device must receive the Host's application frame");
        device_leg.push(binary_payload(received));
        let decrypted = initiator_transport.decrypt(&ciphertext).unwrap();
        assert_eq!(decrypted, plaintext);
    }

    // The Device's reply: one keystroke-sized ciphertext frame.
    let keystroke_ct = initiator_transport.encrypt(DEVICE_KEYSTROKE).unwrap();
    device_leg.push(keystroke_ct.clone());
    device.send_binary(keystroke_ct.clone()).await;
    let received_keystroke = host
        .recv()
        .await
        .expect("the Host must receive the Device's keystroke frame");
    host_leg.push(binary_payload(received_keystroke));
    let decrypted_keystroke = responder_transport.decrypt(&keystroke_ct).unwrap();
    assert_eq!(decrypted_keystroke, DEVICE_KEYSTROKE);

    // R-13-002, R-12-003: neither leg may ever carry the plaintext marker, the
    // pairing phrase, or the derived PSK — checked against each leg's own capture
    // independently, not just their union.
    for (leg_name, leg_bytes) in [("Host", host_leg.concat()), ("Device", device_leg.concat())] {
        assert_no_substring(
            &leg_bytes,
            TERMINAL_MARKER,
            &format!("the terminal-content plaintext marker on the {leg_name} leg"),
        );
        assert_no_substring(
            &leg_bytes,
            PHRASE.as_bytes(),
            &format!("the pairing phrase on the {leg_name} leg"),
        );
        assert_no_substring(
            &leg_bytes,
            &psk,
            &format!("the derived PSK on the {leg_name} leg"),
        );
        for plaintext in HOST_MESSAGES {
            assert_no_substring(
                &leg_bytes,
                plaintext,
                &format!("a Host plaintext application message on the {leg_name} leg"),
            );
        }
        assert_no_substring(
            &leg_bytes,
            DEVICE_KEYSTROKE,
            &format!("the Device's plaintext keystroke on the {leg_name} leg"),
        );
    }

    write_capture(
        &format!("{REPO_ROOT}/docs/security/review-pack/host-leg-capture.hex"),
        &host_leg,
    );
    write_capture(
        &format!("{REPO_ROOT}/docs/security/review-pack/device-leg-capture.hex"),
        &device_leg,
    );
}

/// Unwraps a relay-forwarded WebSocket message into its raw bytes. Every frame this
/// test exchanges is binary (R-11-026); anything else is a harness bug, not a case to
/// handle silently.
fn binary_payload(message: WsMessage) -> Vec<u8> {
    match message {
        WsMessage::Binary(bytes) => bytes.to_vec(),
        other => panic!("expected a binary frame from the relay, got {other:?}"),
    }
}

/// Writes one leg's captured frames to `path`, hex-encoded, one frame per line, so
/// the review pack holds a human-readable artifact rather than a raw binary blob.
fn write_capture(path: &str, frames: &[Vec<u8>]) {
    let path = Path::new(path);
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).expect("the review-pack directory must be creatable");
    }
    let mut body = String::new();
    for frame in frames {
        for byte in frame {
            body.push_str(&format!("{byte:02x}"));
        }
        body.push('\n');
    }
    std::fs::write(path, body).expect("writing the capture file must succeed");
}

/// Same helper `ciphertext_only.rs` uses (`R-13-002`, `R-12-003` proofs share this
/// shape); kept as a small local copy rather than exported from that test binary,
/// since Cargo integration-test files are separate crates and cannot import each
/// other's private items.
fn assert_no_substring(haystack: &[u8], needle: &[u8], description: &str) {
    assert!(
        !contains_subslice(haystack, needle),
        "the relay forwarded {description} in the clear"
    );
}

fn contains_subslice(haystack: &[u8], needle: &[u8]) -> bool {
    if needle.is_empty() || needle.len() > haystack.len() {
        return needle.is_empty();
    }
    haystack
        .windows(needle.len())
        .any(|window| window == needle)
}
