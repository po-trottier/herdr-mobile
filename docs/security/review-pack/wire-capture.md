# Wire capture: relay legs carry only ciphertext

Phase 23 checkbox (`docs/90-implementation-plan.md`): "Capture every byte on both
relay legs during a full session and confirm no plaintext terminal content appears,
recording the capture in `docs/security/review-pack/`" (R-13-002, R-12-003).

## Methodology

The proof is `crates/herdr-relay-hub/tests/byte_capture.rs`. It extends the same
harness `crates/herdr-relay-hub/tests/support/mod.rs` already uses for the other
relay-hub integration tests:

- `support::Relay::start()` binds a real `TcpListener` on an OS-assigned loopback
  port and serves this crate's own real `axum` router
  (`herdr_relay_hub::routes::router()`) on it — the same router the production
  binary runs.
- `support::Relay::connect()` opens a real `ws://127.0.0.1:<port>/...` WebSocket
  connection over that TCP socket (`tokio_tungstenite::connect_async`), the same way
  the Host plugin and the Device app connect in production.

Two such connections are opened for one handle: `/host/<handle>` (the "Host leg")
and `/device/<handle>` (the "Device leg"). The test then drives one full simulated
pairing session across both real sockets:

1. A real `Noise_XXpsk0_25519_ChaChaPoly_BLAKE2s` handshake
   (`crates/herdr-relay/src/noise.rs`, R-13-014, R-13-071), Device as initiator, Host
   as responder — three handshake messages.
2. Four Host application frames, encrypted with the resulting transport session, one
   of which encrypts a realistic terminal pane dump before encryption (the "plaintext
   marker" below). Combined with the one handshake message the Host itself sends,
   the Host sends five ciphertext frames in total.
3. One Device application frame: a single encrypted keystroke event, the smallest
   realistic Device-to-Host frame.

Every frame is captured at the same `send_binary`/`recv` call sites the test itself
drives — the raw bytes observed crossing each real TCP connection, not a
reconstruction — and written to disk as one hex-encoded frame per line:

- `docs/security/review-pack/host-leg-capture.hex` — every frame observed on the
  Host's WebSocket connection (both what the Host sent and what the relay forwarded
  to it).
- `docs/security/review-pack/device-leg-capture.hex` — the same, for the Device's
  WebSocket connection.

Because the relay is a pure forwarder, every frame crosses both legs once (it
arrives on one connection, leaves on the other), so both files end up holding the
same eight ciphertext frames, captured independently at each socket. Proving each
capture is clean, on its own, is a stronger claim than proving only their union is
clean.

## Plaintext markers checked

The test asserts, separately against each leg's own capture (not just their
combined bytes), that none of the following ever appear as a substring:

- The terminal-content plaintext marker: `$ ls -la\nfile1.txt\nfile2.txt\n`.
- The pairing phrase: `remedy-tapestry-hubcap-oversleep-jailbird-kinetic`
  (`docs/11-relay-protocol.md` §8.1's own worked example).
- The derived Noise PSK (`BLAKE2s-256` of the pairing phrase, R-13-024).
- Each of the four Host plaintext application messages (including the marker above).
- The Device's plaintext keystroke event.

## Result

**No plaintext substring was found in either capture.** Both
`host-leg-capture.hex` and `device-leg-capture.hex` contain only Noise ciphertext:
eight hex-encoded frames each (three handshake messages, four Host application
frames, one Device keystroke frame), all opaque. The test's own in-process
assertions (`assert_no_substring`) additionally confirm this on every run, not just
the one recorded here.

## Reproduction

```sh
cd crates
cargo test -p herdr-relay-hub --test byte_capture -- --nocapture
```

Run from the repository root, `cd crates` first (the Cargo workspace lives at
`crates/Cargo.toml`, not the repo root). The command re-runs the full session
above, regenerates both `.hex` capture files in this directory, and re-asserts (via
Rust `assert!`) that neither leg's capture contains any of the plaintext markers
listed above. Observed output on this workstation:

```text
running 1 test
test relay_legs_carry_only_ciphertext_across_a_full_session ... ok

test result: ok. 1 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out
```
