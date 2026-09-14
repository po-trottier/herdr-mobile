//! `docs/90-implementation-plan.md` Phase 4 (`WP-4`): drives a real
//! `Noise_XXpsk0_25519_ChaChaPoly_BLAKE2s` handshake (`crates/herdr-relay/src/noise.rs`,
//! R-13-014, R-13-071) between a Host (responder) and a Device (initiator) through this
//! crate's own real router (`herdr_relay_hub::routes::router()`, the same one
//! `tests/one_device.rs` and friends use), and asserts every byte the relay forwards is
//! opaque: no substring of the pairing phrase, the derived PSK, or either side's
//! plaintext application message ever appears on the wire (R-11-001, R-11-027,
//! R-13-002, R-13-012, R-01-012). This is the relay-opacity half of the local interop proof
//! `WP-14-a`/`WP-14-b`'s `Needs.` lines read from `WP-4`; the cross-language half lives
//! in `app/test/spike/noise_client_test.dart` and
//! `crates/herdr-relay/src/bin/spike-noise-host.rs`.
//!
//! Both peers here are `snow` (this crate does not implement Dart's `cryptography`
//! primitives), so this test does not by itself prove Rust-Dart interop — it proves the
//! independent property that the relay never sees plaintext, which the Dart-side test
//! cannot observe from its own vantage point (it only sees its own decrypted output,
//! never the wire bytes the relay actually forwarded).

mod support;

use herdr_relay::noise::{self, Role};
use support::{HANDLE_A, Relay};

/// The docs' own worked pairing phrase (`docs/11-relay-protocol.md` §8.1).
const PHRASE: &str = "remedy-tapestry-hubcap-oversleep-jailbird-kinetic";
const HOST_MESSAGE: &[u8] = b"host secret: the pane shows `rm -rf /tmp/build`";
const DEVICE_MESSAGE: &[u8] = b"device secret: acknowledging the host's pane";

#[tokio::test]
async fn relay_forwards_only_ciphertext_through_a_full_handshake() {
    let relay = Relay::start().await;
    let mut host = relay.connect("host", HANDLE_A).await;
    let mut device = relay.connect("device", HANDLE_A).await;

    let (host_private, _host_public) = noise::generate_keypair().unwrap();
    let (device_private, _device_public) = noise::generate_keypair().unwrap();
    let psk = noise::psk_from_phrase(PHRASE.as_bytes());

    // R-13-071: Device is the Noise initiator, Host is the responder.
    let mut initiator = noise::pairing_handshake(Role::Initiator, &device_private, &psk).unwrap();
    let mut responder = noise::pairing_handshake(Role::Responder, &host_private, &psk).unwrap();

    // Every raw byte the relay ever forwards on this handle, collected as it is sent,
    // so the plaintext-marker assertions below cover the real wire traffic rather than
    // an in-process shortcut.
    let mut forwarded: Vec<u8> = Vec::new();

    let msg1 = noise::write_handshake_message(&mut initiator, &[]).unwrap();
    forwarded.extend_from_slice(&msg1);
    device.send_binary(msg1.clone()).await;
    let received1 = host.recv().await.expect("the Host must receive message 1");
    assert_eq!(received1, tungstenite_binary(&msg1));
    noise::read_handshake_message(&mut responder, &msg1).unwrap();

    let msg2 = noise::write_handshake_message(&mut responder, &[]).unwrap();
    forwarded.extend_from_slice(&msg2);
    host.send_binary(msg2.clone()).await;
    let received2 = device
        .recv()
        .await
        .expect("the Device must receive message 2");
    assert_eq!(received2, tungstenite_binary(&msg2));
    noise::read_handshake_message(&mut initiator, &msg2).unwrap();

    let msg3 = noise::write_handshake_message(&mut initiator, &[]).unwrap();
    forwarded.extend_from_slice(&msg3);
    device.send_binary(msg3.clone()).await;
    let received3 = host.recv().await.expect("the Host must receive message 3");
    assert_eq!(received3, tungstenite_binary(&msg3));
    noise::read_handshake_message(&mut responder, &msg3).unwrap();

    assert!(initiator.is_handshake_finished());
    assert!(responder.is_handshake_finished());
    let (mut initiator_transport, responder_seen_by_initiator) =
        noise::finish_handshake(initiator).unwrap();
    let (mut responder_transport, initiator_seen_by_responder) =
        noise::finish_handshake(responder).unwrap();
    assert_eq!(responder_seen_by_initiator, _host_public);
    assert_eq!(initiator_seen_by_responder, _device_public);

    // One application frame each way, same as the Dart interop test's greeting
    // exchange, through the same real relay connection.
    let host_ct = responder_transport.encrypt(HOST_MESSAGE).unwrap();
    forwarded.extend_from_slice(&host_ct);
    host.send_binary(host_ct.clone()).await;
    let received_host_ct = device
        .recv()
        .await
        .expect("the Device must receive the Host's application frame");
    assert_eq!(received_host_ct, tungstenite_binary(&host_ct));
    let device_plaintext = initiator_transport.decrypt(&host_ct).unwrap();
    assert_eq!(device_plaintext, HOST_MESSAGE);

    let device_ct = initiator_transport.encrypt(DEVICE_MESSAGE).unwrap();
    forwarded.extend_from_slice(&device_ct);
    device.send_binary(device_ct.clone()).await;
    let received_device_ct = host
        .recv()
        .await
        .expect("the Host must receive the Device's application frame");
    assert_eq!(received_device_ct, tungstenite_binary(&device_ct));
    let host_plaintext = responder_transport.decrypt(&device_ct).unwrap();
    assert_eq!(host_plaintext, DEVICE_MESSAGE);

    // R-11-001, R-11-027, R-13-002, R-13-012, R-01-012: the relay is a wire, not a warehouse. No
    // plaintext marker may appear anywhere in what it forwarded.
    assert_no_substring(&forwarded, PHRASE.as_bytes(), "the pairing phrase");
    assert_no_substring(&forwarded, &psk, "the derived PSK");
    assert_no_substring(
        &forwarded,
        HOST_MESSAGE,
        "the Host's plaintext application message",
    );
    assert_no_substring(
        &forwarded,
        DEVICE_MESSAGE,
        "the Device's plaintext application message",
    );
    // Every real Noise message includes a 16-byte Poly1305 tag (R-13-013's cipher is
    // AEAD), so "the ciphertext never equals the plaintext" is also directly checked
    // for the two application frames, not just the substring search above.
    assert_ne!(host_ct, HOST_MESSAGE);
    assert_ne!(device_ct, DEVICE_MESSAGE);
}

fn tungstenite_binary(bytes: &[u8]) -> tokio_tungstenite::tungstenite::Message {
    tokio_tungstenite::tungstenite::Message::Binary(bytes.to_vec().into())
}

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
