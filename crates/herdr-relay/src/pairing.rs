//! The Host's live pairing session: the 600-second phrase lifetime (R-13-022),
//! the three-attempt limit (R-13-023), the `herdr-remote://pair` URI builder
//! (R-03-013, R-11-140, R-11-141) and the local QR encoder (R-13-030,
//! R-12-005, R-31-16-01). [`wordlist`] owns the underlying EFF word-list data;
//! see that module's doc comment for the word-list-sourcing story and a real
//! codec-interaction defect it works around.
//!
//! This module owns no I/O of its own: every time-dependent method takes an
//! explicit `now: Instant` (the same convention `crate::frame_codec`'s
//! `Reassembler` already uses), so the 600-second expiry and the three-attempt
//! limit are deterministically testable with no real sleeping. It also
//! never resolves a cache path or talks to the network itself — the caller
//! loads the word list once (`wordlist::load`) and passes `&[&str]` in,
//! keeping this file's only declared dependency `WP-5-b`
//! (`herdr-relay-proto`), per `docs/90-implementation-plan.md`'s `WP-10-b`
//! entry.
//!
//! **Expiry and the three-attempt limit end a session the same way, and both
//! are implemented literally, not by analogy:** R-13-022 says expiry MUST
//! "destroy the phrase, destroy the handle, and stop accepting handshakes
//! with that PSK" and MUST NOT generate a replacement on its own. R-13-023
//! says the third failed attempt MUST "destroy the phrase and destroy the
//! handle, and MUST NOT mint a replacement itself; the pairing pane shows
//! that the phrase is spent and waits for `p`". [`PairingSession`]'s state
//! machine keeps the two ends apart — [`SessionState::Expired`] and
//! [`SessionState::Spent`] — and both are terminal until an explicit
//! [`PairingSession::regenerate`] call (the popup's `p` key, out of this
//! package's scope).

use std::time::{Duration, Instant};

use herdr_relay_proto::handle::{Handle, HandleError, PAIRING_URI_MAX_LEN, PairingUri};
use qrcode::bits::Bits;
use qrcode::types::QrError;
use qrcode::{Color, EcLevel, QrCode, Version};
use thiserror::Error;

use crate::noise;

pub mod wordlist;

use wordlist::{Phrase, WordlistError};

/// The phrase lifetime (R-13-022).
pub const PHRASE_LIFETIME: Duration = Duration::from_secs(600);
/// The number of failed handshake attempts permitted against one phrase
/// before the Host destroys it and the handle (R-13-023). No replacement is
/// minted: the pane's `p` key is the only re-arm path.
pub const MAX_ATTEMPTS: u8 = 3;

/// A failure building or encoding a live pairing session.
#[derive(Debug, Error)]
pub enum PairingError {
    /// The word list, or the phrase generated from it, was rejected.
    #[error(transparent)]
    Wordlist(#[from] WordlistError),
    /// The system random source failed while generating a routing handle.
    #[error(transparent)]
    Handle(#[from] HandleError),
    /// The built pairing URI exceeds R-11-141's 512-byte limit.
    #[error("pairing URI is {0} bytes, exceeding the {PAIRING_URI_MAX_LEN}-byte limit (R-11-141)")]
    UriTooLong(usize),
    /// The QR encoder rejected the URI (in practice, only reachable if a
    /// pathologically long relay origin also survives the 512-byte check
    /// above and still cannot fit QR version 40).
    #[error("QR encoding failed: {0}")]
    Qr(#[from] QrError),
}

/// The QR code's raw module grid: `width` × `width` booleans, row-major,
/// `true` meaning a dark module. Carries no quiet zone padding — R-11-142's
/// 4-module quiet zone is a rendering-time border, added by whichever module
/// paints this grid into the terminal (`crates/herdr-relay/src/popup.rs`,
/// `WP-10-c`, per its own checklist: "compute the QR region from the encoder
/// output, never from a fixed constant"), not encoded into the grid itself.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct QrGrid {
    pub width: usize,
    pub modules: Vec<bool>,
}

impl QrGrid {
    /// Whether the module at `(x, y)` is dark. `x` and `y` are in `0..width`.
    #[must_use]
    pub fn is_dark(&self, x: usize, y: usize) -> bool {
        self.modules[y * self.width + x]
    }
}

/// Encodes `uri` as a QR code in pure byte mode at error-correction level `M`,
/// choosing the smallest version that fits (R-11-142).
///
/// `qrcode` 0.14.1's own `QrCode::new`/`with_error_correction_level` run an
/// *optimal mixed-mode* segmenter (`bits::encode_auto`, source-verified
/// against <https://github.com/kennytm/qrcode-rust/blob/v0.14.1/src/bits.rs>):
/// it can carve out an Alphanumeric-mode sub-segment for a run of uppercase
/// hex digits (this URI's percent-encoding, e.g. `%3A`) even while the
/// surrounding text is Byte mode. R-11-142 requires byte mode for the whole
/// payload, so this function drives the lower-level `Bits` API directly —
/// `push_byte_data` plus a linear version search — instead of the crate's
/// auto-segmenting entry points.
fn encode_qr(uri: &str) -> Result<QrGrid, QrError> {
    let payload = uri.as_bytes();
    for version_number in 1..=40_i16 {
        let mut bits = Bits::new(Version::Normal(version_number));
        if bits.push_byte_data(payload).is_err() {
            continue;
        }
        if bits.push_terminator(EcLevel::M).is_err() {
            continue;
        }
        let code = QrCode::with_bits(bits, EcLevel::M)?;
        let width = code.width();
        let modules = code
            .to_colors()
            .into_iter()
            .map(|c| c != Color::Light)
            .collect();
        return Ok(QrGrid { width, modules });
    }
    Err(QrError::DataTooLong)
}

/// Encodes a pairing URI that came from outside this module — the bridge's
/// copy, handed back over the control socket — into a [`QrGrid`] identical
/// to the one the live session itself publishes. Applies the same 512-byte
/// limit (R-11-141) and the same byte-mode rules (R-11-142) as the session's
/// own encode path, so the popup and the bridge always render the same code.
///
/// # Errors
///
/// See [`PairingError`].
pub fn qr_from_uri(uri: &str) -> Result<QrGrid, PairingError> {
    if uri.len() > PAIRING_URI_MAX_LEN {
        return Err(PairingError::UriTooLong(uri.len()));
    }
    Ok(encode_qr(uri)?)
}

/// One live phrase/handle pair: generated, displayable, and destroyed as a
/// unit (R-13-029).
struct LivePhrase {
    handle: Handle,
    phrase: Phrase,
    generated_at: Instant,
    failed_attempts: u8,
    uri: String,
    qr: QrGrid,
}

impl LivePhrase {
    fn generate(relay_origin: &str, words: &[&str], now: Instant) -> Result<Self, PairingError> {
        let handle = Handle::generate()?;
        let phrase = wordlist::generate_phrase(words)?;
        let uri = PairingUri {
            relay_origin: relay_origin.to_owned(),
            handle,
            phrase: phrase.canonical().to_owned(),
        }
        .build();
        if uri.len() > PAIRING_URI_MAX_LEN {
            return Err(PairingError::UriTooLong(uri.len()));
        }
        let qr = encode_qr(&uri)?;
        Ok(Self {
            handle,
            phrase,
            generated_at: now,
            failed_attempts: 0,
            uri,
            qr,
        })
    }
}

/// [`PairingSession`]'s four mutually exclusive states. R-13-029 groups
/// "successful enrolment", "expiry" and "three failed attempts" together as
/// causes of destruction; expiry and the third failed attempt are both
/// terminal without an explicit [`PairingSession::regenerate`] call — see
/// this module's doc comment.
enum SessionState {
    /// A phrase/handle pair is live: displayable, and accepting handshake
    /// attempts.
    Live(Box<LivePhrase>),
    /// The phrase expired (R-13-022). No phrase, no handle, no QR remain
    /// reachable.
    Expired,
    /// The third failed handshake attempt destroyed the phrase and the
    /// handle (R-13-023). No replacement is minted.
    Spent,
    /// A Device successfully enrolled using this session's phrase (R-13-029).
    Enrolled,
}

/// One Host pairing session for one relay origin. Owns at most one live
/// phrase/handle/QR triple at a time.
pub struct PairingSession {
    relay_origin: String,
    state: SessionState,
}

impl PairingSession {
    /// Starts a new session: generates the first phrase, handle and QR
    /// immediately.
    ///
    /// # Errors
    ///
    /// See [`PairingError`].
    pub fn new(relay_origin: String, words: &[&str], now: Instant) -> Result<Self, PairingError> {
        let live = Box::new(LivePhrase::generate(&relay_origin, words, now)?);
        Ok(Self {
            relay_origin,
            state: SessionState::Live(live),
        })
    }

    /// Transitions `Live` to `Expired` the instant more than
    /// [`PHRASE_LIFETIME`] has elapsed since generation (R-13-022). Matches
    /// `crate::frame_codec::Reassembler`'s own boundary convention: exactly
    /// `PHRASE_LIFETIME` elapsed is still live; any amount past it is not.
    fn apply_expiry(&mut self, now: Instant) {
        if let SessionState::Live(live) = &self.state
            && now.saturating_duration_since(live.generated_at) > PHRASE_LIFETIME
        {
            self.state = SessionState::Expired;
        }
    }

    fn live(&self) -> Option<&LivePhrase> {
        match &self.state {
            SessionState::Live(live) => Some(live.as_ref()),
            SessionState::Expired | SessionState::Spent | SessionState::Enrolled => None,
        }
    }

    /// Whether a phrase is currently live and displayable.
    #[must_use]
    pub fn is_live(&mut self, now: Instant) -> bool {
        self.apply_expiry(now);
        self.live().is_some()
    }

    /// Whether the third failed handshake attempt destroyed the phrase and
    /// the handle (R-13-023's terminal `Spent` state, distinct from expiry
    /// so the bridge and the pane can say *spent*, not *expired*).
    #[must_use]
    pub fn is_spent(&self) -> bool {
        matches!(self.state, SessionState::Spent)
    }

    /// The live routing handle, or `None` once expired, spent or enrolled.
    #[must_use]
    pub fn handle(&mut self, now: Instant) -> Option<Handle> {
        self.apply_expiry(now);
        self.live().map(|live| live.handle)
    }

    /// The live phrase's display form (space-separated, R-13-020), or `None`
    /// once expired, spent or enrolled.
    #[must_use]
    pub fn phrase_display(&mut self, now: Instant) -> Option<String> {
        self.apply_expiry(now);
        self.live().map(|live| live.phrase.display_form())
    }

    /// The live phrase's canonical hyphenated form (R-13-019), or `None`
    /// once expired, spent or enrolled.
    #[must_use]
    pub fn phrase_canonical(&mut self, now: Instant) -> Option<String> {
        self.apply_expiry(now);
        self.live().map(|live| live.phrase.canonical().to_owned())
    }

    /// The live `herdr-remote://pair` URI, or `None` once expired or
    /// enrolled.
    #[must_use]
    pub fn pairing_uri(&mut self, now: Instant) -> Option<&str> {
        self.apply_expiry(now);
        self.live().map(|live| live.uri.as_str())
    }

    /// The live QR module grid, or `None` once expired, spent or enrolled — the
    /// "destroy the QR buffer" half of R-13-022/R-13-029.
    #[must_use]
    pub fn qr(&mut self, now: Instant) -> Option<&QrGrid> {
        self.apply_expiry(now);
        self.live().map(|live| &live.qr)
    }

    /// The 32-byte `Noise_XXpsk0` pre-shared key derived from the live
    /// canonical phrase (R-13-024), or `None` once expired, spent or enrolled — the
    /// "stop accepting handshakes with that PSK" half of R-13-022, enforced
    /// by making the PSK unreachable after expiry.
    #[must_use]
    pub fn psk_for(&mut self, now: Instant) -> Option<[u8; 32]> {
        self.apply_expiry(now);
        self.live()
            .map(|live| noise::psk_from_phrase(live.phrase.canonical().as_bytes()))
    }

    /// Records one failed Noise handshake attempt against the live phrase
    /// (R-13-023). A no-op if the phrase already expired or is already spent
    /// (a late failure against a dead PSK must not resurrect it). On the
    /// third failure, destroys the phrase and the handle and mints no
    /// replacement: [`SessionState::Spent`] is terminal until an explicit
    /// [`PairingSession::regenerate`] call.
    pub fn record_failed_attempt(&mut self, now: Instant) {
        self.apply_expiry(now);
        let SessionState::Live(live) = &mut self.state else {
            return;
        };
        live.failed_attempts += 1;
        if live.failed_attempts >= MAX_ATTEMPTS {
            self.state = SessionState::Spent;
        }
    }

    /// Records a successful enrolment (R-13-035 step 10): destroys the
    /// phrase, the QR buffer and the handle so the same URI cannot enrol a
    /// second Device (R-13-029).
    pub fn record_enrolled(&mut self) {
        self.state = SessionState::Enrolled;
    }

    /// Mints a fresh phrase, handle and QR, replacing whatever state this
    /// session was in — the operator-triggered refresh path (the popup's `p`
    /// key, `WP-10-c`) for re-arming after expiry or a spent phrase, or for
    /// an explicit operator-requested rotation.
    ///
    /// # Errors
    ///
    /// See [`PairingError`].
    pub fn regenerate(&mut self, words: &[&str], now: Instant) -> Result<(), PairingError> {
        self.state = SessionState::Live(Box::new(LivePhrase::generate(
            &self.relay_origin,
            words,
            now,
        )?));
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const RELAY_ORIGIN: &str = "https://relay.example.com";

    /// A synthetic 7776-entry fixture (R-13-025 forbids committing the real
    /// EFF list); only the count and per-word ASCII-lowercase shape matter to
    /// the codec, matching `herdr_relay_proto::phrase`'s own test fixture.
    fn word_list() -> Vec<&'static str> {
        const POOL: [&str; 6] = [
            "remedy",
            "tapestry",
            "hubcap",
            "oversleep",
            "jailbird",
            "kinetic",
        ];
        (0..wordlist::EFF_WORDLIST_ENTRY_COUNT)
            .map(|i| POOL[i % POOL.len()])
            .collect()
    }

    #[test]
    fn a_fresh_session_is_live_and_publishes_a_uri_and_a_qr() {
        let words = word_list();
        let now = Instant::now();
        let mut session = PairingSession::new(RELAY_ORIGIN.to_owned(), &words, now).unwrap();
        assert!(session.is_live(now));
        let uri = session.pairing_uri(now).unwrap();
        assert!(uri.starts_with("herdr-remote://pair?v=1&r="));
        assert!(session.qr(now).unwrap().width > 0);
        assert!(session.handle(now).is_some());
        assert!(session.phrase_display(now).unwrap().split(' ').count() == wordlist::WORD_COUNT);
    }

    #[test]
    fn a_phrase_is_still_live_at_exactly_the_600_second_boundary() {
        let words = word_list();
        let start = Instant::now();
        let mut session = PairingSession::new(RELAY_ORIGIN.to_owned(), &words, start).unwrap();
        assert!(session.is_live(start + PHRASE_LIFETIME));
    }

    #[test]
    fn a_phrase_is_refused_one_second_past_the_600_second_boundary() {
        let words = word_list();
        let start = Instant::now();
        let mut session = PairingSession::new(RELAY_ORIGIN.to_owned(), &words, start).unwrap();
        let too_late = start + PHRASE_LIFETIME + Duration::from_secs(1);

        assert!(!session.is_live(too_late));
        assert!(session.pairing_uri(too_late).is_none());
        assert!(session.handle(too_late).is_none());
        assert!(session.qr(too_late).is_none());
        assert!(session.phrase_display(too_late).is_none());
    }

    #[test]
    fn expiry_does_not_auto_regenerate() {
        // R-13-022 says only "stop accepting handshakes with that PSK" and
        // MUST NOT generate a replacement; like the three-attempt case
        // (R-13-023), expiry never itself mints a replacement.
        let words = word_list();
        let start = Instant::now();
        let mut session = PairingSession::new(RELAY_ORIGIN.to_owned(), &words, start).unwrap();
        let too_late = start + PHRASE_LIFETIME + Duration::from_secs(1);
        assert!(!session.is_live(too_late));

        let much_later = too_late + Duration::from_secs(300);
        assert!(
            !session.is_live(much_later),
            "expiry is terminal without an explicit regenerate() call"
        );
    }

    #[test]
    fn two_failed_attempts_keep_the_same_phrase_and_handle() {
        let words = word_list();
        let now = Instant::now();
        let mut session = PairingSession::new(RELAY_ORIGIN.to_owned(), &words, now).unwrap();
        let original_handle = session.handle(now).unwrap();

        for _ in 0..(MAX_ATTEMPTS - 1) {
            session.record_failed_attempt(now);
        }

        assert!(session.is_live(now));
        assert_eq!(
            session.handle(now),
            Some(original_handle),
            "R-13-023 permits two failures without destroying the phrase"
        );
    }

    #[test]
    fn a_third_failed_attempt_spends_the_phrase_and_handle_without_a_replacement() {
        let words = word_list();
        let now = Instant::now();
        let mut session = PairingSession::new(RELAY_ORIGIN.to_owned(), &words, now).unwrap();

        for _ in 0..MAX_ATTEMPTS {
            session.record_failed_attempt(now);
        }

        assert!(
            !session.is_live(now),
            "R-13-023: the third failure destroys the phrase and mints no replacement"
        );
        assert!(session.is_spent(), "the spent state is not expiry");
        assert!(session.handle(now).is_none());
        assert!(session.pairing_uri(now).is_none());
        assert!(session.psk_for(now).is_none());
    }

    #[test]
    fn a_spent_phrase_stays_dead_until_an_explicit_regenerate() {
        let words = word_list();
        let now = Instant::now();
        let mut session = PairingSession::new(RELAY_ORIGIN.to_owned(), &words, now).unwrap();
        let original_handle = session.handle(now).unwrap();
        for _ in 0..MAX_ATTEMPTS {
            session.record_failed_attempt(now);
        }

        // A late failure against the spent phrase changes nothing, and no
        // amount of waiting revives it.
        session.record_failed_attempt(now);
        assert!(session.is_spent());
        let much_later = now + PHRASE_LIFETIME + Duration::from_secs(300);
        assert!(
            !session.is_live(much_later) && session.is_spent(),
            "spent is terminal without an explicit regenerate() call"
        );

        session.regenerate(&words, much_later).unwrap();

        assert!(session.is_live(much_later));
        assert!(!session.is_spent());
        assert_ne!(
            session.handle(much_later),
            Some(original_handle),
            "regenerate mints a fresh handle (the popup's `p` path)"
        );
    }

    #[test]
    fn a_failed_attempt_against_an_already_expired_phrase_is_a_no_op() {
        let words = word_list();
        let start = Instant::now();
        let mut session = PairingSession::new(RELAY_ORIGIN.to_owned(), &words, start).unwrap();
        let too_late = start + PHRASE_LIFETIME + Duration::from_secs(1);

        session.record_failed_attempt(too_late);

        assert!(
            !session.is_live(too_late) && !session.is_spent(),
            "a stale attempt must not resurrect an expired phrase, nor mark it spent"
        );
    }

    #[test]
    fn enrolment_destroys_the_phrase_the_qr_buffer_and_the_handle() {
        let words = word_list();
        let now = Instant::now();
        let mut session = PairingSession::new(RELAY_ORIGIN.to_owned(), &words, now).unwrap();

        session.record_enrolled();

        assert!(!session.is_live(now));
        assert!(session.pairing_uri(now).is_none());
        assert!(session.handle(now).is_none());
        assert!(session.qr(now).is_none());
    }

    #[test]
    fn regenerate_re_arms_an_expired_session_with_a_new_handle() {
        let words = word_list();
        let start = Instant::now();
        let mut session = PairingSession::new(RELAY_ORIGIN.to_owned(), &words, start).unwrap();
        let original_handle = session.handle(start).unwrap();
        let too_late = start + PHRASE_LIFETIME + Duration::from_secs(1);
        assert!(!session.is_live(too_late));

        session.regenerate(&words, too_late).unwrap();

        assert!(session.is_live(too_late));
        assert_ne!(session.handle(too_late), Some(original_handle));
    }

    #[test]
    fn the_pairing_uri_carries_the_relay_origin_the_handle_and_the_phrase_and_round_trips() {
        let words = word_list();
        let now = Instant::now();
        let mut session = PairingSession::new(RELAY_ORIGIN.to_owned(), &words, now).unwrap();
        let uri = session.pairing_uri(now).unwrap().to_owned();
        let handle = session.handle(now).unwrap();
        let phrase = session.phrase_display(now).unwrap().replace(' ', "-");

        let parsed = PairingUri::parse(&uri).expect("a built URI must parse back");
        assert_eq!(parsed.relay_origin, RELAY_ORIGIN);
        assert_eq!(parsed.handle, handle);
        assert_eq!(parsed.phrase, phrase);
        assert!(uri.len() <= PAIRING_URI_MAX_LEN);
    }

    #[test]
    fn qr_from_uri_reproduces_the_sessions_own_qr_module_for_module() {
        let words = word_list();
        let now = Instant::now();
        let mut session = PairingSession::new(RELAY_ORIGIN.to_owned(), &words, now).unwrap();
        let uri = session.pairing_uri(now).unwrap().to_owned();

        let grid = qr_from_uri(&uri).unwrap();

        assert_eq!(&grid, session.qr(now).unwrap());
    }

    #[test]
    fn qr_from_uri_refuses_an_overlong_uri() {
        let uri = "x".repeat(PAIRING_URI_MAX_LEN + 1);
        assert!(matches!(
            qr_from_uri(&uri),
            Err(PairingError::UriTooLong(n)) if n == PAIRING_URI_MAX_LEN + 1
        ));
    }

    #[test]
    fn psk_for_matches_psk_from_phrase_of_the_live_canonical_phrase() {
        let words = word_list();
        let now = Instant::now();
        let mut session = PairingSession::new(RELAY_ORIGIN.to_owned(), &words, now).unwrap();

        let canonical = session.phrase_canonical(now).unwrap();
        let expected = noise::psk_from_phrase(canonical.as_bytes());

        // `assert!` over `assert_eq!`: a failed run must not print key bytes.
        assert!(
            session.psk_for(now) == Some(expected),
            "psk_for must derive from the live canonical phrase (R-13-024)"
        );
    }

    #[test]
    fn psk_for_and_phrase_canonical_are_none_once_the_phrase_expires() {
        let words = word_list();
        let start = Instant::now();
        let mut session = PairingSession::new(RELAY_ORIGIN.to_owned(), &words, start).unwrap();
        let too_late = start + PHRASE_LIFETIME + Duration::from_secs(1);

        assert!(session.psk_for(too_late).is_none());
        assert!(session.phrase_canonical(too_late).is_none());
    }
}
