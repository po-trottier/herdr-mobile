//! Compress-then-fragment on send, defragment-then-decompress on receive, between the
//! frame envelope (`docs/11-relay-protocol.md` §3.2) and `crate::noise::Transport`
//! (`docs/11-relay-protocol.md` §3.4, §3.5, R-11-229 through R-11-239).
//!
//! **Correction against this module's own task brief:** the brief that requested this
//! file described `uncompressed_len` as little-endian. `docs/11-relay-protocol.md`
//! R-11-231, read in full before writing anything here, states big-endian explicitly:
//! `` `[codec: u8][uncompressed_len: u32, big-endian][body: bytes]` ``. This module
//! follows the document, not the paraphrase; [`build_record`]'s doc comment repeats the
//! correction at the point of encoding so a future reader does not "fix" it to
//! little-endian.
//!
//! This module owns no networking and no WebSocket close-code logic: it is pure,
//! synchronous codec/protocol logic over byte slices and `crate::noise::Transport`
//! (Noise-only, itself no socket). [`FrameCodecError::ProtocolError`] is this module's
//! signal for every R-11-237/R-11-238 violation; the future caller that owns the actual
//! WebSocket connection (`watch.rs`/`relay.rs`, later phases, not this one) maps it to
//! closing with code `4003` (R-11-121).
//!
//! Ownership boundary: `docs/90-implementation-plan.md` Phase 4 (`WP-4`) owns this file
//! (added to Phase 4's `Owns.` line this session). Wiring it into a live watch loop or
//! relay connection is a later phase's job.

use std::io::{Read, Write};
use std::time::{Duration, Instant};

use flate2::Compression;
use flate2::read::ZlibDecoder;
use flate2::write::ZlibEncoder;

use crate::noise::Transport;

/// R-11-035, R-11-233: the frame envelope's raw byte length cap, and the cap on
/// `uncompressed_len` and on decompression output.
pub const MAX_UNCOMPRESSED_LEN: usize = 1_048_576;

/// R-11-231: `codec` (1 byte) + `uncompressed_len` (4 bytes).
const RECORD_HEADER_LEN: usize = 5;

/// R-11-236: the largest a legal compression record can be — 1 MiB raw (codec `0`), or
/// zlib's worst-case expansion on already-compact data plus this record's own header:
/// `1_048_576 + 1_048_576 / 1000 + 12 + 5`.
pub const MAX_COMPRESSED_RECORD_LEN: usize = 1_049_641;

/// R-11-235: `snow`'s 65535-byte Noise message ceiling
/// (`crate::noise::MAX_MESSAGE_LEN`) less the 16-byte ChaChaPoly AEAD tag every
/// `Transport::encrypt` call appends.
const NOISE_PLAINTEXT_CEILING: usize = crate::noise::MAX_MESSAGE_LEN - 16;

/// R-11-235: `[frag_index: u8][frag_count: u8]`.
const FRAGMENT_HEADER_LEN: usize = 2;

/// R-11-235: usable `chunk` bytes per physical Noise transport message.
pub const MAX_CHUNK_LEN: usize = NOISE_PLAINTEXT_CEILING - FRAGMENT_HEADER_LEN;

/// R-11-236: a receiver MUST reject a `frag_count` above this, on the first fragment,
/// before allocating a reassembly buffer.
pub const MAX_FRAG_COUNT: u8 = 40;

/// R-11-238: matches R-11-023's existing pong-response bound; no new timing constant.
const INTER_FRAGMENT_TIMEOUT: Duration = Duration::from_secs(10);

/// A codec, fragmentation, or reassembly-timing violation. Every variant here maps to
/// R-11-121's `protocol_error` / WebSocket close code `4003` at the caller's transport
/// layer; this module itself closes nothing.
#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum FrameCodecError {
    /// R-11-035, R-11-233: the envelope's raw bytes exceed 1 MiB before this record is
    /// even built. Distinct from `ProtocolError` because R-11-036 already gives it a
    /// separate wire error code (`frame_too_large`), never `protocol_error`.
    #[error("the envelope exceeds the 1 MiB frame-size cap (R-11-035, R-11-233)")]
    EnvelopeTooLarge,
    /// Every R-11-231, R-11-234, R-11-236, R-11-237 or R-11-238 violation.
    #[error("protocol_error: {0}")]
    ProtocolError(&'static str),
}

impl From<crate::noise::NoiseError> for FrameCodecError {
    fn from(_: crate::noise::NoiseError) -> Self {
        // A Noise decrypt/encrypt failure on a fragment is itself a wire-level
        // integrity failure with no more specific R-11 code than protocol_error.
        FrameCodecError::ProtocolError(
            "Noise transport error while encoding or decoding a fragment",
        )
    }
}

/// Compresses `data` with zlib (RFC 1950), for [`build_record`]'s R-11-232 codec
/// decision. Never fails: `flate2`'s in-memory `Vec` sink cannot produce an I/O error.
fn zlib_compress(data: &[u8]) -> Vec<u8> {
    let mut encoder = ZlibEncoder::new(Vec::new(), Compression::default());
    encoder
        .write_all(data)
        .expect("writing to an in-memory Vec sink never fails");
    encoder
        .finish()
        .expect("finishing an in-memory Vec sink never fails")
}

/// R-11-234: decompresses `body` with a bounded, streaming reader that aborts the
/// instant its *actual* output exceeds [`MAX_UNCOMPRESSED_LEN`] — the declared
/// `uncompressed_len` in [`build_record`]'s record is never trusted as the sole bound,
/// so a sender that lies about it while shipping an oversized compressed payload (a
/// decompression bomb) is stopped here, not by the declared field.
fn bounded_zlib_decompress(body: &[u8]) -> Result<Vec<u8>, FrameCodecError> {
    let mut decoder = ZlibDecoder::new(body);
    let mut out = Vec::new();
    let mut buf = [0_u8; 8192];
    loop {
        let read = decoder
            .read(&mut buf)
            .map_err(|_| FrameCodecError::ProtocolError("zlib decompression failed (R-11-234)"))?;
        if read == 0 {
            break;
        }
        out.extend_from_slice(&buf[..read]);
        if out.len() > MAX_UNCOMPRESSED_LEN {
            return Err(FrameCodecError::ProtocolError(
                "decompressed output exceeds the 1 MiB cap (R-11-234, decompression-bomb defence)",
            ));
        }
    }
    Ok(out)
}

/// R-11-229 step 2, R-11-231, R-11-232, R-11-233: builds one compression record from a
/// frame envelope's serialized UTF-8 bytes.
///
/// `uncompressed_len` is written **big-endian** (R-11-231's exact text), not
/// little-endian.
fn build_record(envelope_bytes: &[u8]) -> Result<Vec<u8>, FrameCodecError> {
    // R-11-233: check the raw cap before this record is built, exactly as R-11-036
    // already does at the envelope level.
    if envelope_bytes.len() > MAX_UNCOMPRESSED_LEN {
        return Err(FrameCodecError::EnvelopeTooLarge);
    }

    let compressed = zlib_compress(envelope_bytes);
    // R-11-232: codec 1 only when it actually shrinks the payload; codec 0 otherwise.
    let (codec, body): (u8, &[u8]) = if compressed.len() < envelope_bytes.len() {
        (1, &compressed)
    } else {
        (0, envelope_bytes)
    };

    let mut record = Vec::with_capacity(RECORD_HEADER_LEN + body.len());
    record.push(codec);
    record.extend_from_slice(&(envelope_bytes.len() as u32).to_be_bytes());
    record.extend_from_slice(body);
    Ok(record)
}

/// R-11-231, R-11-234: parses and decompresses one reassembled compression record back
/// into the frame envelope's serialized UTF-8 bytes.
fn decode_record(record: &[u8]) -> Result<Vec<u8>, FrameCodecError> {
    if record.len() < RECORD_HEADER_LEN {
        return Err(FrameCodecError::ProtocolError(
            "compression record shorter than its 5-byte header (R-11-231)",
        ));
    }
    let codec = record[0];
    let uncompressed_len =
        u32::from_be_bytes([record[1], record[2], record[3], record[4]]) as usize;
    let body = &record[RECORD_HEADER_LEN..];

    // R-11-234: reject a declared uncompressed_len already over the cap, before
    // attempting decompression at all.
    if uncompressed_len > MAX_UNCOMPRESSED_LEN {
        return Err(FrameCodecError::ProtocolError(
            "declared uncompressed_len exceeds the 1 MiB cap (R-11-234)",
        ));
    }

    match codec {
        0 => {
            // R-11-231: uncompressed_len MUST equal body's length for codec 0.
            if body.len() != uncompressed_len {
                return Err(FrameCodecError::ProtocolError(
                    "codec 0's uncompressed_len does not match its body length (R-11-231)",
                ));
            }
            Ok(body.to_vec())
        }
        1 => bounded_zlib_decompress(body),
        _ => Err(FrameCodecError::ProtocolError(
            "unrecognised codec byte (R-11-231)",
        )),
    }
}

/// R-11-229 step 3, R-11-235: splits one compression record into fragment plaintexts,
/// each prefixed with `[frag_index: u8][frag_count: u8]`. `record` is never empty
/// ([`build_record`] always emits at least its 5-byte header), so this always returns
/// at least one fragment.
fn split_into_fragments(record: &[u8]) -> Vec<Vec<u8>> {
    let chunks: Vec<&[u8]> = record.chunks(MAX_CHUNK_LEN).collect();
    debug_assert!(
        chunks.len() <= usize::from(MAX_FRAG_COUNT),
        "build_record's own MAX_UNCOMPRESSED_LEN cap keeps every record this crate \
         produces well under MAX_FRAG_COUNT fragments"
    );
    let frag_count = chunks.len() as u8;
    chunks
        .into_iter()
        .enumerate()
        .map(|(index, chunk)| {
            let mut fragment = Vec::with_capacity(FRAGMENT_HEADER_LEN + chunk.len());
            fragment.push(index as u8);
            fragment.push(frag_count);
            fragment.extend_from_slice(chunk);
            fragment
        })
        .collect()
}

/// R-11-229 steps 1 through 4: builds the compression record from `envelope_bytes`,
/// splits it into fragments, and Noise-encrypts each one — one `Transport::encrypt`
/// call per fragment, exactly as R-11-229 specifies. The caller sends each returned
/// ciphertext as its own physical WebSocket binary frame, in order (step 5, not this
/// module's job).
pub fn encode_frame(
    transport: &mut Transport,
    envelope_bytes: &[u8],
) -> Result<Vec<Vec<u8>>, FrameCodecError> {
    let record = build_record(envelope_bytes)?;
    split_into_fragments(&record)
        .iter()
        .map(|fragment| transport.encrypt(fragment).map_err(FrameCodecError::from))
        .collect()
}

/// Receive-side reassembly state for one Noise session (R-11-237, R-11-238, R-11-239).
/// One instance tracks at most one in-progress record at a time; a fresh
/// `Noise_KK` session (reconnect) needs a fresh `Reassembler`, since R-11-238 already
/// notes a lost connection discards any partial buffer.
#[derive(Debug, Default)]
pub struct Reassembler {
    partial: Option<PartialRecord>,
}

#[derive(Debug)]
struct PartialRecord {
    frag_count: u8,
    next_index: u8,
    buffer: Vec<u8>,
    last_fragment_at: Instant,
}

impl Reassembler {
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// Feeds one already-Noise-decrypted fragment plaintext (`Transport::decrypt`'s
    /// output). Returns `Ok(Some(envelope_bytes))` once a complete record has been
    /// reassembled and decompressed, `Ok(None)` while a record is still in progress,
    /// or `Err` on any R-11-236/R-11-237/R-11-238 violation — which always discards
    /// this reassembler's partial buffer (R-11-237), leaving it ready for a fresh
    /// record on the next call, on the assumption the caller closes the connection.
    ///
    /// `now` is caller-supplied (R-41-131's convention throughout this crate) so
    /// R-11-238's 10-second inter-fragment timeout is deterministically testable with
    /// no real sleeping.
    pub fn accept_fragment(
        &mut self,
        plaintext: &[u8],
        now: Instant,
    ) -> Result<Option<Vec<u8>>, FrameCodecError> {
        if let Some(partial) = &self.partial
            && now.saturating_duration_since(partial.last_fragment_at) > INTER_FRAGMENT_TIMEOUT
        {
            self.partial = None;
            return Err(FrameCodecError::ProtocolError(
                "no fragment arrived within 10 seconds of the previous one (R-11-238)",
            ));
        }

        if plaintext.len() < FRAGMENT_HEADER_LEN {
            self.partial = None;
            return Err(FrameCodecError::ProtocolError(
                "fragment shorter than its 2-byte header (R-11-235)",
            ));
        }
        let frag_index = plaintext[0];
        let frag_count = plaintext[1];
        let chunk = &plaintext[FRAGMENT_HEADER_LEN..];

        let is_first_fragment_of_a_new_record = self.partial.is_none();
        if is_first_fragment_of_a_new_record {
            if frag_index != 0 {
                return Err(FrameCodecError::ProtocolError(
                    "the first fragment of a record must be frag_index 0 (R-11-237)",
                ));
            }
            // R-11-236: reject an out-of-bounds frag_count before allocating any
            // reassembly buffer or accepting any chunk bytes.
            if frag_count == 0 || frag_count > MAX_FRAG_COUNT {
                return Err(FrameCodecError::ProtocolError(
                    "frag_count is zero or exceeds the maximum of 40 (R-11-236)",
                ));
            }
            if chunk.len() > MAX_COMPRESSED_RECORD_LEN {
                return Err(FrameCodecError::ProtocolError(
                    "running fragment byte total exceeds the compression-record cap (R-11-236)",
                ));
            }
            if frag_count == 1 {
                return Ok(Some(decode_record(chunk)?));
            }
            self.partial = Some(PartialRecord {
                frag_count,
                next_index: 1,
                buffer: chunk.to_vec(),
                last_fragment_at: now,
            });
            return Ok(None);
        }

        let partial = self.partial.as_mut().expect("checked Some above");
        if frag_count != partial.frag_count {
            self.partial = None;
            return Err(FrameCodecError::ProtocolError(
                "frag_count changed within one record (R-11-237)",
            ));
        }
        if frag_index != partial.next_index {
            self.partial = None;
            return Err(FrameCodecError::ProtocolError(
                "out-of-order, repeated, or skipped frag_index (R-11-237)",
            ));
        }
        partial.buffer.extend_from_slice(chunk);
        partial.last_fragment_at = now;
        // R-11-236: independent of frag_count, reject the moment the running total
        // exceeds the cap, checked after every fragment, not only once reassembly
        // finishes.
        if partial.buffer.len() > MAX_COMPRESSED_RECORD_LEN {
            self.partial = None;
            return Err(FrameCodecError::ProtocolError(
                "running fragment byte total exceeds the compression-record cap (R-11-236)",
            ));
        }

        if frag_index == frag_count - 1 {
            let PartialRecord { buffer, .. } = self.partial.take().expect("checked Some above");
            return Ok(Some(decode_record(&buffer)?));
        }
        partial.next_index += 1;
        Ok(None)
    }
}

/// Convenience symmetric to [`encode_frame`]: Noise-decrypts one physical WebSocket
/// binary frame's ciphertext, then feeds the plaintext into `reassembler`. See
/// [`Reassembler::accept_fragment`] for the return-value contract.
pub fn decode_fragment(
    reassembler: &mut Reassembler,
    transport: &mut Transport,
    ciphertext: &[u8],
    now: Instant,
) -> Result<Option<Vec<u8>>, FrameCodecError> {
    let plaintext = transport.decrypt(ciphertext)?;
    reassembler.accept_fragment(&plaintext, now)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::noise::{self, Role};
    use blake2::Digest;

    /// A live, matched pair of `Transport`s from a real `Noise_XXpsk0` handshake — the
    /// same construction `noise.rs`'s own tests already prove correct — so the
    /// round-trip tests below exercise this module through real Noise encryption, not
    /// a shortcut.
    fn transport_pair() -> (Transport, Transport) {
        let (device_sk, _device_pk) = noise::generate_keypair().unwrap();
        let (host_sk, _host_pk) = noise::generate_keypair().unwrap();
        let psk = noise::psk_from_phrase(b"remedy-tapestry-hubcap-oversleep-jailbird-kinetic");
        let mut initiator = noise::pairing_handshake(Role::Initiator, &device_sk, &psk).unwrap();
        let mut responder = noise::pairing_handshake(Role::Responder, &host_sk, &psk).unwrap();

        let msg1 = noise::write_handshake_message(&mut initiator, &[]).unwrap();
        noise::read_handshake_message(&mut responder, &msg1).unwrap();
        let msg2 = noise::write_handshake_message(&mut responder, &[]).unwrap();
        noise::read_handshake_message(&mut initiator, &msg2).unwrap();
        let msg3 = noise::write_handshake_message(&mut initiator, &[]).unwrap();
        noise::read_handshake_message(&mut responder, &msg3).unwrap();

        let (initiator_transport, _) = noise::finish_handshake(initiator).unwrap();
        let (responder_transport, _) = noise::finish_handshake(responder).unwrap();
        (initiator_transport, responder_transport)
    }

    /// Sends `envelope_bytes` from `sender` to `receiver` through the full
    /// `encode_frame`/`decode_fragment` pipeline and returns the reassembled envelope
    /// bytes, asserting every fragment arrives (nothing is dropped) and the record
    /// completes on the last one.
    fn round_trip(
        sender: &mut Transport,
        receiver: &mut Transport,
        envelope_bytes: &[u8],
    ) -> Vec<u8> {
        let fragments = encode_frame(sender, envelope_bytes).unwrap();
        let mut reassembler = Reassembler::new();
        let now = Instant::now();
        let mut result = None;
        for (index, ciphertext) in fragments.iter().enumerate() {
            let outcome = decode_fragment(&mut reassembler, receiver, ciphertext, now).unwrap();
            if index == fragments.len() - 1 {
                assert!(
                    outcome.is_some(),
                    "the last fragment must complete the record"
                );
                result = outcome;
            } else {
                assert!(
                    outcome.is_none(),
                    "an earlier fragment must not complete the record"
                );
            }
        }
        result.unwrap()
    }

    #[test]
    fn small_payload_round_trips_with_the_raw_fallback() {
        let (mut sender, mut receiver) = transport_pair();
        let envelope = br#"{"v":1,"type":"ping","seq":1,"payload":{}}"#;
        // codec 0: a short JSON envelope's zlib overhead does not beat its raw size.
        assert_eq!(build_record(envelope).unwrap()[0], 0);

        let decoded = round_trip(&mut sender, &mut receiver, envelope);
        assert_eq!(decoded, envelope);
    }

    #[test]
    fn large_compressible_payload_round_trips_across_multiple_fragments_with_zlib() {
        let (mut sender, mut receiver) = transport_pair();
        // Semi-varied repeated JSON-ish text: compressible, but not so uniform that
        // the compressed record shrinks back under one fragment.
        let mut envelope = String::new();
        for i in 0..14_500 {
            envelope.push_str(&format!(
                "{{\"index\":{i},\"note\":\"herdr-relay frame codec fixture line {i}\"}},"
            ));
        }
        let envelope = envelope.into_bytes();
        assert!(
            envelope.len() < MAX_UNCOMPRESSED_LEN,
            "fixture must respect the 1 MiB cap"
        );

        let record = build_record(&envelope).unwrap();
        assert_eq!(record[0], 1, "fixture must actually choose zlib (codec 1)");
        assert!(
            record.len() - RECORD_HEADER_LEN > MAX_CHUNK_LEN,
            "fixture must force multi-fragment splitting even after compression"
        );

        let decoded = round_trip(&mut sender, &mut receiver, &envelope);
        assert_eq!(decoded, envelope);
    }

    #[test]
    fn incompressible_near_one_mib_payload_round_trips_with_the_raw_fallback() {
        let (mut sender, mut receiver) = transport_pair();
        // High-entropy bytes via repeated BLAKE2s digests of a counter: deterministic
        // (a stable, reproducible test fixture), but not zlib-compressible.
        let mut envelope = Vec::with_capacity(1_000_000);
        let mut counter: u64 = 0;
        while envelope.len() < 1_000_000 {
            envelope.extend_from_slice(&blake2::Blake2s256::digest(counter.to_le_bytes()));
            counter += 1;
        }
        envelope.truncate(1_000_000);
        assert!(
            envelope.len() < MAX_UNCOMPRESSED_LEN,
            "fixture must respect the 1 MiB cap"
        );

        let record = build_record(&envelope).unwrap();
        assert_eq!(
            record[0], 0,
            "high-entropy bytes must fall back to codec 0 (raw)"
        );
        assert!(
            record.len() - RECORD_HEADER_LEN > MAX_CHUNK_LEN,
            "fixture must force multi-fragment splitting"
        );

        let decoded = round_trip(&mut sender, &mut receiver, &envelope);
        assert_eq!(decoded, envelope);
    }

    #[test]
    fn a_frag_count_of_forty_one_is_rejected_before_any_allocation() {
        let mut reassembler = Reassembler::new();
        let first_fragment = vec![0_u8, 41, 1, 2, 3];
        let error = reassembler
            .accept_fragment(&first_fragment, Instant::now())
            .unwrap_err();
        assert_eq!(
            error,
            FrameCodecError::ProtocolError(
                "frag_count is zero or exceeds the maximum of 40 (R-11-236)"
            )
        );
    }

    #[test]
    fn a_frag_count_of_forty_is_accepted() {
        let mut reassembler = Reassembler::new();
        let first_fragment = vec![0_u8, 40, 9, 9, 9];
        let outcome = reassembler
            .accept_fragment(&first_fragment, Instant::now())
            .unwrap();
        assert_eq!(
            outcome, None,
            "frag_count 40 with more fragments still owed must not complete yet"
        );
    }

    #[test]
    fn a_lying_uncompressed_len_is_rejected_by_the_bounded_decompressor() {
        // A genuine decompression bomb: 2 MiB of zeros compresses tiny, but the
        // declared uncompressed_len lies and claims only 10 bytes.
        let real_payload = vec![0_u8; 2 * 1_048_576];
        let compressed = zlib_compress(&real_payload);
        let mut record = Vec::new();
        record.push(1_u8); // codec 1 (zlib)
        record.extend_from_slice(&10_u32.to_be_bytes()); // lying uncompressed_len
        record.extend_from_slice(&compressed);

        let error = decode_record(&record).unwrap_err();
        assert_eq!(
            error,
            FrameCodecError::ProtocolError(
                "decompressed output exceeds the 1 MiB cap (R-11-234, decompression-bomb defence)"
            )
        );
    }

    #[test]
    fn an_out_of_order_fragment_is_rejected() {
        let mut reassembler = Reassembler::new();
        // frag_count 3, but frag_index jumps straight from 0 to 2.
        let first = vec![0_u8, 3, 1, 2, 3];
        assert_eq!(
            reassembler.accept_fragment(&first, Instant::now()).unwrap(),
            None
        );
        let out_of_order = vec![2_u8, 3, 7, 8, 9];
        let error = reassembler
            .accept_fragment(&out_of_order, Instant::now())
            .unwrap_err();
        assert_eq!(
            error,
            FrameCodecError::ProtocolError(
                "out-of-order, repeated, or skipped frag_index (R-11-237)"
            )
        );
    }

    #[test]
    fn a_new_records_frag_index_zero_before_the_previous_records_last_fragment_is_rejected() {
        let mut reassembler = Reassembler::new();
        let first = vec![0_u8, 2, 1, 2, 3];
        assert_eq!(
            reassembler.accept_fragment(&first, Instant::now()).unwrap(),
            None
        );
        // A new record's frag_index 0 arrives before the first record's last fragment
        // (frag_index 1 of 2) — R-11-237's explicit interleaving prohibition. Same
        // frag_count (2) as the in-progress record, so this exercises the frag_index
        // ordering check specifically, not the separate frag_count-consistency check.
        let interleaved_new_record = vec![0_u8, 2, 9, 9];
        let error = reassembler
            .accept_fragment(&interleaved_new_record, Instant::now())
            .unwrap_err();
        assert_eq!(
            error,
            FrameCodecError::ProtocolError(
                "out-of-order, repeated, or skipped frag_index (R-11-237)"
            )
        );
    }

    #[test]
    fn a_stale_partial_record_times_out_after_ten_seconds() {
        let mut reassembler = Reassembler::new();
        let first = vec![0_u8, 2, 1, 2, 3];
        let start = Instant::now();
        assert_eq!(reassembler.accept_fragment(&first, start).unwrap(), None);

        let too_late = start + Duration::from_secs(11);
        let second = vec![1_u8, 2, 4, 5, 6];
        let error = reassembler.accept_fragment(&second, too_late).unwrap_err();
        assert_eq!(
            error,
            FrameCodecError::ProtocolError(
                "no fragment arrived within 10 seconds of the previous one (R-11-238)"
            )
        );
    }

    #[test]
    fn an_envelope_over_one_mib_is_rejected_before_compression() {
        let oversized = vec![0_u8; MAX_UNCOMPRESSED_LEN + 1];
        assert_eq!(
            build_record(&oversized).unwrap_err(),
            FrameCodecError::EnvelopeTooLarge
        );
    }

    #[test]
    fn an_unrecognised_codec_byte_is_rejected() {
        let mut record = vec![2_u8]; // no codec 2 is defined
        record.extend_from_slice(&0_u32.to_be_bytes());
        assert_eq!(
            decode_record(&record).unwrap_err(),
            FrameCodecError::ProtocolError("unrecognised codec byte (R-11-231)")
        );
    }
}
