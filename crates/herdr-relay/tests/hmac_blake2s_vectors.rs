//! `docs/13-security-pairing.md` R-13-072: asserts the committed
//! `tests/hmac_blake2s_vectors.json` — the one shared artifact this file and the future
//! `app/test/services/hmac_blake2s_vectors_test.dart` (`WP-14-b`) both read directly —
//! against a hand-rolled RFC 2104 HMAC over `blake2` 0.10.6's `Blake2s256`.
//!
//! This is not the Noise state machine's own HMAC-BLAKE2s: `crates/herdr-relay/src/noise.rs`
//! never needs one, because `snow` 0.10.0 already implements the Noise-spec HKDF
//! internally and correctly. This file exists because the *Dart* side has no such luxury
//! (`docs/13-security-pairing.md` R-13-072): `cryptography` 2.9.0's `Blake2s.blockLengthInBytes`
//! returns 32, not RFC 7693's 64, so its own `Hmac.blake2s()` pads to the wrong width and
//! computes a `snow`-incompatible MAC. The construction below is the reference both language
//! implementations must reproduce byte for byte, built independently of `snow`'s own
//! crate-internal (unexported) `HashBLAKE2s::hmac()` so this file is a real cross-check, not
//! a re-export of the thing it verifies.
//!
//! `docs/90-implementation-plan.md` Phase 4 (`WP-4`) owns this file and
//! `tests/hmac_blake2s_vectors.json`; `app/lib/services/hmac_blake2s.dart` and
//! `app/test/services/hmac_blake2s_vectors_test.dart` are `WP-14-b`'s, not built here.

use std::fs;

use blake2::{Blake2s256, Digest};
use serde::Deserialize;

/// RFC 2104 HMAC over BLAKE2s-256, with the block length R-13-072 fixes at 64 bytes
/// (RFC 7693; matches `snow` 0.10.0's own `HashBLAKE2s::block_len()`). Every caller in
/// this crate's Noise usage passes a `key` of at most 32 bytes (Noise's `chaining_key`
/// length), so the RFC 2104 over-length-key branch (hashing a key longer than the block
/// length before use) is intentionally not implemented — R-13-072 states the same
/// simplification for the Dart side.
fn hmac_blake2s(key: &[u8], data: &[u8]) -> [u8; 32] {
    assert!(
        key.len() <= 64,
        "this reference implementation only covers keys up to the block length, per R-13-072"
    );
    let mut ipad = [0x36_u8; 64];
    let mut opad = [0x5c_u8; 64];
    for (i, byte) in key.iter().enumerate() {
        ipad[i] ^= byte;
        opad[i] ^= byte;
    }

    let mut inner_hasher = Blake2s256::new();
    inner_hasher.update(ipad);
    inner_hasher.update(data);
    let inner: [u8; 32] = inner_hasher.finalize().into();

    let mut outer_hasher = Blake2s256::new();
    outer_hasher.update(opad);
    outer_hasher.update(inner);
    outer_hasher.finalize().into()
}

#[derive(Deserialize)]
struct VectorsDocument {
    vectors: Vec<Vector>,
}

#[derive(Deserialize)]
struct Vector {
    name: String,
    key_hex: String,
    data_hex: String,
    expected_mac_hex: String,
}

fn decode_hex(s: &str) -> Vec<u8> {
    assert!(s.len().is_multiple_of(2), "odd-length hex string: {s}");
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).expect("valid hex digit pair"))
        .collect()
}

fn encode_hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn load_vectors() -> VectorsDocument {
    let path = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/tests/hmac_blake2s_vectors.json"
    );
    let content = fs::read_to_string(path).expect("hmac_blake2s_vectors.json must be readable");
    serde_json::from_str(&content).expect("hmac_blake2s_vectors.json must be valid JSON")
}

/// Every vector's `expected_mac_hex` MUST equal what this reference construction
/// computes from `key_hex`/`data_hex`, byte for byte. A drift here means the committed
/// file no longer matches the RFC 2104 construction R-13-072 specifies — the same defect
/// class R-13-072 exists to catch (`Hmac.blake2s()` silently computing the wrong thing).
#[test]
fn every_vector_matches_the_reference_construction() {
    let document = load_vectors();
    assert!(
        !document.vectors.is_empty(),
        "the vector file must not be empty"
    );
    for vector in &document.vectors {
        let key = decode_hex(&vector.key_hex);
        let data = decode_hex(&vector.data_hex);
        let mac = hmac_blake2s(&key, &data);
        assert_eq!(
            encode_hex(&mac),
            vector.expected_mac_hex,
            "vector {:?} did not reproduce its committed expected_mac_hex",
            vector.name
        );
    }
}

/// R-13-072's own boundary statement: a key exactly 64 bytes long is still valid input
/// (`assert!` inside [`hmac_blake2s`] must not panic on it). Distinct from the substantive
/// MAC-value assertion above: this only proves the boundary itself does not reject.
#[test]
fn a_sixty_four_byte_key_is_accepted() {
    let key = [0_u8; 64];
    let _ = hmac_blake2s(&key, b"boundary check");
}

/// Every vector name in the committed file MUST be unique, so a future addition cannot
/// silently shadow an existing one in test output or in the Dart side's own lookup.
#[test]
fn vector_names_are_unique() {
    let document = load_vectors();
    let mut names: Vec<&str> = document
        .vectors
        .iter()
        .map(|vector| vector.name.as_str())
        .collect();
    let original_len = names.len();
    names.sort_unstable();
    names.dedup();
    assert_eq!(
        names.len(),
        original_len,
        "duplicate vector name in hmac_blake2s_vectors.json"
    );
}
