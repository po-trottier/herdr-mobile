//! The Noise session: `Noise_XXpsk0_25519_ChaChaPoly_BLAKE2s` for first pairing
//! and `Noise_KK_25519_ChaChaPoly_BLAKE2s` for reconnect (`docs/13-security-pairing.md`
//! R-13-013, R-13-014, R-13-015), built on `snow` 0.10.0.
//!
//! `docs/90-implementation-plan.md` Phase 4 (`WP-4`) owns this file. Phase 4's own
//! `Done when` line needs a deployed public relay reached over real WSS from a phone
//! on cellular data, which this workstation does not have. This module is scoped to
//! what `WP-14-a`/`WP-14-b`'s narrower `Needs.` lines actually read from `WP-4`: a
//! local, byte-verified proof that this crate's `snow` handshake interoperates with
//! the Device's from-primitives `cryptography` 2.9.0 implementation
//! (`docs/13-security-pairing.md` "### Libraries"). See
//! `crates/herdr-relay/src/bin/spike-noise-host.rs` and
//! `app/test/spike/noise_client_test.dart` for the two live ends of that proof, and
//! `crates/herdr-relay-hub/tests/ciphertext_only.rs` for the relay-opacity half
//! (R-11-001, R-11-027).
//! The PSK derivation and the initiator/responder assignment were both settled by the
//! project owner during this session, in `docs/13-security-pairing.md` R-13-024 and
//! the new R-13-071, after this module's first draft flagged both as open. This module
//! matches them exactly:
//!
//! - R-13-024: the `Noise_XXpsk0` PSK is `BLAKE2s-256(canonical_phrase_utf8)` — the
//!   full 32-byte digest, no truncation ([`psk_from_phrase`]). `snow` 0.10.0's PSK
//!   slot (`Builder::psk`) requires exactly 32 bytes; the raw phrase (for example
//!   `remedy-tapestry-hubcap-oversleep-jailbird-kinetic`, 50 UTF-8 bytes) does not fit
//!   it directly, so R-13-024 states the transform rather than the raw bytes.
//! - R-13-071: the Device is the Noise initiator and the Host is the Noise responder,
//!   for both `Noise_XXpsk0` (R-13-035 step 6) and `Noise_KK` (R-13-037 step 2). The
//!   Host registers on `/host/<handle>` and waits; the Device connects afterward and
//!   sends the first Noise handshake message.

use blake2::{Blake2s256, Digest};
use snow::{Builder, HandshakeState, TransportState};

/// R-13-013, R-13-014: first pairing.
const XXPSK0_PARAMS: &str = "Noise_XXpsk0_25519_ChaChaPoly_BLAKE2s";
/// R-13-013, R-13-015: reconnect.
const KK_PARAMS: &str = "Noise_KK_25519_ChaChaPoly_BLAKE2s";

/// `snow`'s own maximum single Noise message size: the spec's 16-bit length-prefix
/// convention (65535 bytes). Every handshake and transport buffer in this module is
/// sized to it.
pub const MAX_MESSAGE_LEN: usize = 65535;

/// Which end of the handshake a caller is building. R-13-071: the Device is always
/// [`Role::Initiator`]; the Host is always [`Role::Responder`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Role {
    Initiator,
    Responder,
}

/// An error setting up or driving a Noise handshake or transport session.
#[derive(Debug, thiserror::Error)]
pub enum NoiseError {
    #[error("noise handshake setup or execution failed: {0}")]
    Snow(#[from] snow::Error),
}

fn params(text: &str) -> snow::params::NoiseParams {
    text.parse()
        .expect("the handshake name constants in this module always parse")
}

/// Derives the 32-byte `Noise_XXpsk0` pre-shared key from the canonical hyphenated
/// pairing phrase's UTF-8 bytes, as `BLAKE2s-256(phrase)`, the full digest with no
/// truncation (R-13-024).
#[must_use]
pub fn psk_from_phrase(phrase_utf8: &[u8]) -> [u8; 32] {
    Blake2s256::digest(phrase_utf8).into()
}

/// Builds the `Noise_XXpsk0_25519_ChaChaPoly_BLAKE2s` handshake state for first
/// pairing (R-13-014). `psk` is [`psk_from_phrase`]'s output; `local_private_key` is
/// this peer's own static Curve25519 private key.
pub fn pairing_handshake(
    role: Role,
    local_private_key: &[u8; 32],
    psk: &[u8; 32],
) -> Result<HandshakeState, NoiseError> {
    let builder = Builder::new(params(XXPSK0_PARAMS))
        .local_private_key(local_private_key)?
        .psk(0, psk)?;
    Ok(match role {
        Role::Initiator => builder.build_initiator()?,
        Role::Responder => builder.build_responder()?,
    })
}

/// Builds the `Noise_KK_25519_ChaChaPoly_BLAKE2s` handshake state for reconnect
/// (R-13-015). Both peers already hold each other's static public key from the first
/// pairing (R-13-038, R-13-048).
pub fn reconnect_handshake(
    role: Role,
    local_private_key: &[u8; 32],
    remote_static_public_key: &[u8; 32],
) -> Result<HandshakeState, NoiseError> {
    let builder = Builder::new(params(KK_PARAMS))
        .local_private_key(local_private_key)?
        .remote_public_key(remote_static_public_key)?;
    Ok(match role {
        Role::Initiator => builder.build_initiator()?,
        Role::Responder => builder.build_responder()?,
    })
}

/// Writes the next handshake message (pending tokens plus `payload`) as the wire bytes
/// to send in one opaque binary WebSocket frame (R-11-026). Every caller in this
/// crate's spike harness passes an empty payload: the frame envelope (R-11-031) has no
/// home during the handshake itself.
pub fn write_handshake_message(
    state: &mut HandshakeState,
    payload: &[u8],
) -> Result<Vec<u8>, NoiseError> {
    let mut buf = vec![0_u8; MAX_MESSAGE_LEN];
    let len = state.write_message(payload, &mut buf)?;
    buf.truncate(len);
    Ok(buf)
}

/// Reads a handshake message received as one opaque binary WebSocket frame, returning
/// its payload (always empty, in this crate's spike harness).
pub fn read_handshake_message(
    state: &mut HandshakeState,
    message: &[u8],
) -> Result<Vec<u8>, NoiseError> {
    let mut buf = vec![0_u8; MAX_MESSAGE_LEN];
    let len = state.read_message(message, &mut buf)?;
    buf.truncate(len);
    Ok(buf)
}

/// The post-handshake transport session (R-11-003): encrypts and decrypts the JSON
/// frame envelope (`docs/11-relay-protocol.md` §3) as opaque binary WebSocket frames.
/// Wraps `snow::TransportState`, which manages its own per-direction nonce; this
/// struct adds no nonce bookkeeping of its own.
pub struct Transport {
    state: TransportState,
}

impl Transport {
    /// Encrypts one application frame for the wire.
    pub fn encrypt(&mut self, plaintext: &[u8]) -> Result<Vec<u8>, NoiseError> {
        let mut buf = vec![0_u8; MAX_MESSAGE_LEN];
        let len = self.state.write_message(plaintext, &mut buf)?;
        buf.truncate(len);
        Ok(buf)
    }

    /// Decrypts one binary WebSocket frame received from the peer.
    pub fn decrypt(&mut self, ciphertext: &[u8]) -> Result<Vec<u8>, NoiseError> {
        let mut buf = vec![0_u8; MAX_MESSAGE_LEN];
        let len = self.state.read_message(ciphertext, &mut buf)?;
        buf.truncate(len);
        Ok(buf)
    }
}

/// Finishes a completed handshake (`state.is_handshake_finished()` MUST already be
/// `true`): captures the peer's static public key for pinning/fingerprinting
/// (R-13-040, R-13-048) before consuming the [`HandshakeState`], then converts it into
/// a [`Transport`]. Both `Noise_XXpsk0` and `Noise_KK` yield the peer's static key by
/// handshake end (`Noise_XXpsk0` learns it during the handshake; `Noise_KK` already
/// knew it going in) — either way this is the only correct place to read it, since
/// `into_transport_mode` consumes `self`.
pub fn finish_handshake(state: HandshakeState) -> Result<(Transport, [u8; 32]), NoiseError> {
    let mut remote_static = [0_u8; 32];
    remote_static.copy_from_slice(
        state
            .get_remote_static()
            .expect("both Noise_XXpsk0 and Noise_KK yield a remote static key by handshake end"),
    );
    let transport = state.into_transport_mode()?;
    Ok((Transport { state: transport }, remote_static))
}

/// Generates a fresh Curve25519 static keypair using `snow`'s own DH resolver, in the
/// same raw 32/32-byte format `keys.rs`'s `HostKeypair` uses — but with no keyring
/// persistence. Spike callers (`spike-noise-host.rs`, this module's own tests) own
/// their own key lifetime; production Host identity remains `keys.rs`'s job.
pub fn generate_keypair() -> Result<([u8; 32], [u8; 32]), NoiseError> {
    let kp = Builder::new(params(XXPSK0_PARAMS)).generate_keypair()?;
    let mut private = [0_u8; 32];
    let mut public = [0_u8; 32];
    private.copy_from_slice(&kp.private);
    public.copy_from_slice(&kp.public);
    Ok((private, public))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn keypair() -> ([u8; 32], [u8; 32]) {
        generate_keypair().unwrap()
    }

    /// R-13-014: a matching phrase-derived PSK on both sides completes the `XXpsk0`
    /// handshake, each side learns the other's real static public key, and the
    /// resulting transport keys decrypt each other's frames.
    #[test]
    fn xxpsk0_round_trips_with_matching_psk() {
        let (device_sk, device_pk) = keypair();
        let (host_sk, host_pk) = keypair();
        let psk = psk_from_phrase(b"remedy-tapestry-hubcap-oversleep-jailbird-kinetic");
        let mut initiator = pairing_handshake(Role::Initiator, &device_sk, &psk).unwrap();
        let mut responder = pairing_handshake(Role::Responder, &host_sk, &psk).unwrap();

        let msg1 = write_handshake_message(&mut initiator, &[]).unwrap();
        read_handshake_message(&mut responder, &msg1).unwrap();
        let msg2 = write_handshake_message(&mut responder, &[]).unwrap();
        read_handshake_message(&mut initiator, &msg2).unwrap();
        let msg3 = write_handshake_message(&mut initiator, &[]).unwrap();
        read_handshake_message(&mut responder, &msg3).unwrap();

        assert!(initiator.is_handshake_finished());
        assert!(responder.is_handshake_finished());
        let (mut initiator_transport, initiator_remote) = finish_handshake(initiator).unwrap();
        let (mut responder_transport, responder_remote) = finish_handshake(responder).unwrap();
        assert_eq!(initiator_remote, host_pk);
        assert_eq!(responder_remote, device_pk);

        let ct = initiator_transport.encrypt(b"hello host").unwrap();
        let pt = responder_transport.decrypt(&ct).unwrap();
        assert_eq!(pt, b"hello host");

        let reply = responder_transport.encrypt(b"hello device").unwrap();
        let reply_pt = initiator_transport.decrypt(&reply).unwrap();
        assert_eq!(reply_pt, b"hello device");
    }

    /// R-13-014: a mismatched phrase MUST fail the handshake at the first transport
    /// message, never silently succeed with a different session key.
    #[test]
    fn xxpsk0_fails_with_mismatched_psk() {
        let (device_sk, _) = keypair();
        let (host_sk, _) = keypair();
        let mut initiator = pairing_handshake(
            Role::Initiator,
            &device_sk,
            &psk_from_phrase(b"remedy-tapestry-hubcap-oversleep-jailbird-kinetic"),
        )
        .unwrap();
        let mut responder = pairing_handshake(
            Role::Responder,
            &host_sk,
            &psk_from_phrase(b"wrong-words-do-not-match-here-at-all"),
        )
        .unwrap();

        let msg1 = write_handshake_message(&mut initiator, &[]).unwrap();
        // R-13-014: the `psk0` modifier mixes the PSK into the key before this same
        // message's own (empty) payload is authenticated, so a wrong phrase is
        // detected here, at message 1 — never a fresh key that quietly diverges later.
        assert!(read_handshake_message(&mut responder, &msg1).is_err());
    }

    /// R-13-015: `Noise_KK` reconnect with pinned static keys round-trips too, with no
    /// PSK involved.
    #[test]
    fn kk_round_trips_with_pinned_static_keys() {
        let (device_sk, device_pk) = keypair();
        let (host_sk, host_pk) = keypair();
        let mut initiator = reconnect_handshake(Role::Initiator, &device_sk, &host_pk).unwrap();
        let mut responder = reconnect_handshake(Role::Responder, &host_sk, &device_pk).unwrap();

        let msg1 = write_handshake_message(&mut initiator, &[]).unwrap();
        read_handshake_message(&mut responder, &msg1).unwrap();
        let msg2 = write_handshake_message(&mut responder, &[]).unwrap();
        read_handshake_message(&mut initiator, &msg2).unwrap();

        assert!(initiator.is_handshake_finished());
        assert!(responder.is_handshake_finished());
        let (mut initiator_transport, _) = finish_handshake(initiator).unwrap();
        let (mut responder_transport, _) = finish_handshake(responder).unwrap();
        let ct = responder_transport.encrypt(b"welcome back").unwrap();
        let pt = initiator_transport.decrypt(&ct).unwrap();
        assert_eq!(pt, b"welcome back");
    }
}
