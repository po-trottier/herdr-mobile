//! Integration tests for the pairing-phrase codec, asserting it rejects every
//! malformed input in the `docs/13-security-pairing.md` R-13-027 table that this
//! module actually owns (`docs/90-implementation-plan.md` §5.2, R-40-031).
//!
//! `phrase_expired` and `phrase_attempts` are **not** tested here. They are
//! stateful session properties (a generation timestamp, a per-phrase attempt
//! counter) that belong to the Host's pairing session, not this stateless codec —
//! see the scope note in `src/phrase.rs` citing R-90-008. This module tests the four
//! structural codes the codec does own: `phrase_word_count`, `phrase_word_unknown`,
//! `phrase_separator`, `phrase_case`.

use herdr_relay_proto::phrase::{Phrase, PhraseError};

const WORD_POOL: [&str; 6] = [
    "remedy",
    "tapestry",
    "hubcap",
    "oversleep",
    "jailbird",
    "kinetic",
];

/// A synthetic 7776-entry word list, not the real EFF list (R-13-025 forbids
/// committing that list). Codec correctness depends only on the count and the
/// per-word ASCII-lowercase shape, not real word content.
fn word_list() -> Vec<&'static str> {
    (0..herdr_relay_proto::phrase::EFF_WORDLIST_ENTRY_COUNT)
        .map(|i| WORD_POOL[i % WORD_POOL.len()])
        .collect()
}

const VALID_PHRASE: &str = "remedy-tapestry-hubcap-oversleep-jailbird-kinetic";

#[test]
fn valid_canonical_phrase_parses() {
    let words = word_list();
    let phrase =
        Phrase::parse_canonical(VALID_PHRASE, &words).expect("must accept the valid phrase");
    assert_eq!(phrase.canonical(), VALID_PHRASE);
}

#[test]
fn phrase_word_count_too_few_is_rejected() {
    let words = word_list();
    let error = Phrase::parse_canonical("remedy-tapestry-hubcap", &words)
        .expect_err("must reject three words");
    assert!(matches!(error, PhraseError::WordCount));
    assert_eq!(
        error.code(),
        Some(herdr_relay_proto::codes::PhraseErrorCode::PhraseWordCount)
    );
}

#[test]
fn phrase_word_count_too_many_is_rejected() {
    let words = word_list();
    let error = Phrase::parse_canonical(
        "remedy-tapestry-hubcap-oversleep-jailbird-kinetic-remedy",
        &words,
    )
    .expect_err("must reject seven words");
    assert!(matches!(error, PhraseError::WordCount));
}

#[test]
fn phrase_word_unknown_is_rejected() {
    let words = word_list();
    let error = Phrase::parse_canonical(
        "remedy-tapestry-hubcap-oversleep-jailbird-notarealword",
        &words,
    )
    .expect_err("must reject a word outside the list");
    assert!(matches!(error, PhraseError::WordUnknown));
    assert_eq!(
        error.code(),
        Some(herdr_relay_proto::codes::PhraseErrorCode::PhraseWordUnknown)
    );
}

#[test]
fn phrase_separator_leading_hyphen_is_rejected() {
    let words = word_list();
    let error = Phrase::parse_canonical(&format!("-{VALID_PHRASE}"), &words)
        .expect_err("must reject a leading hyphen");
    assert!(matches!(error, PhraseError::Separator));
    assert_eq!(
        error.code(),
        Some(herdr_relay_proto::codes::PhraseErrorCode::PhraseSeparator)
    );
}

#[test]
fn phrase_separator_trailing_hyphen_is_rejected() {
    let words = word_list();
    let error = Phrase::parse_canonical(&format!("{VALID_PHRASE}-"), &words)
        .expect_err("must reject a trailing hyphen");
    assert!(matches!(error, PhraseError::Separator));
}

#[test]
fn phrase_separator_empty_word_is_rejected() {
    let words = word_list();
    // A whitespace-only candidate normalises to the empty string, which splits to one
    // empty word.
    let error = Phrase::parse_canonical("   ", &words).expect_err("must reject an empty phrase");
    assert!(matches!(error, PhraseError::Separator));
}

#[test]
fn phrase_case_non_ascii_after_normalisation_is_rejected() {
    let words = word_list();
    // 'é' is not ASCII, so ASCII-only lowercasing during normalisation leaves it
    // untouched, and it must still fail the case check.
    let error = Phrase::parse_canonical(
        "r\u{e9}medy-tapestry-hubcap-oversleep-jailbird-kinetic",
        &words,
    )
    .expect_err("must reject a non-ASCII character");
    assert!(matches!(error, PhraseError::Case));
    assert_eq!(
        error.code(),
        Some(herdr_relay_proto::codes::PhraseErrorCode::PhraseCase)
    );
}

#[test]
fn manual_entry_normalisation_converges_with_the_canonical_form() {
    // R-13-026: manual entry normalises before validation, so upper case, extra
    // spaces, and repeated hyphens all converge on the same canonical phrase.
    let words = word_list();
    let manual = "  Remedy Tapestry--Hubcap   Oversleep-Jailbird Kinetic  ";
    let phrase = Phrase::parse_canonical(manual, &words).expect("must normalise and accept");
    assert_eq!(phrase.canonical(), VALID_PHRASE);
}

#[test]
fn word_list_of_the_wrong_size_is_rejected_before_structural_checks() {
    let short_list: Vec<&str> = WORD_POOL.to_vec();
    let error = Phrase::parse_canonical(VALID_PHRASE, &short_list)
        .expect_err("must reject a caller word list that is not exactly 7776 entries");
    assert!(matches!(error, PhraseError::WordListSize(6)));
}
