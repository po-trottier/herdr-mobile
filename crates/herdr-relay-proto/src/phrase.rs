//! The pairing-phrase codec: the six-word Diceware phrase used as the `Noise_XXpsk0`
//! pre-shared key.
//!
//! Owning rules: `docs/13-security-pairing.md` R-13-017 (EFF long wordlist),
//! R-13-018 (uniform independent selection from a CSPRNG), R-13-019 (canonical
//! hyphenated form), R-13-020 (display form), R-13-021 (entropy), R-13-026
//! (normalisation before validation).
//!
//! **Scope boundary (R-90-008):** `docs/13-security-pairing.md` R-13-025 names
//! `crates/herdr-relay/src/pairing/wordlist.rs`, not this file, as the home for the
//! build-time download, checksum verification, and on-disk cache of the EFF word
//! list — that document is the owning source and it names a different path than the
//! Phase 5 checklist item that requested this download logic live here. This module
//! holds the pure, stateless codec: generation, canonical/display form, normalisation,
//! and structural validation, each taking the word list as a parameter. It never
//! downloads, caches, or embeds the list itself. `docs/13-security-pairing.md`
//! R-13-022 (600-second lifetime) and R-13-023 (three-attempt limit) are stateful
//! session properties that belong to the Host's pairing session (Phase 10,
//! `crates/herdr-relay/src/pairing.rs`), not this stateless crate; [`PhraseErrorCode`]
//! still names their wire codes for that future caller.

#[cfg(feature = "generate")]
use rand::rngs::{StdRng, SysRng};
#[cfg(feature = "generate")]
use rand::{RngExt, SeedableRng};

use crate::codes::PhraseErrorCode;

/// The number of words in a pairing phrase (R-13-017).
pub const WORD_COUNT: usize = 6;

/// The exact size of the EFF long wordlist (R-13-025).
pub const EFF_WORDLIST_ENTRY_COUNT: usize = 7776;

/// The canonical URL of the EFF long wordlist (R-13-017). The list itself is never
/// committed to this repository (R-13-025).
pub const EFF_WORDLIST_URL: &str = "https://www.eff.org/files/2016/07/18/eff_large_wordlist.txt";

/// A validated pairing phrase. Holds both the canonical hyphenated lowercase
/// form (R-13-019, the `Noise_XXpsk0` PSK input) and the six words it was built
/// from, resolved once at construction time by [`segment_words`]. The two are
/// kept side by side deliberately: [`Phrase::canonical`] must stay a zero-copy
/// `&str`, and the six words cannot be recovered from the flat canonical string
/// by a naive hyphen-to-space replacement, because the real EFF long list holds
/// four words with an internal hyphen (`drop-down`, `felt-tip`, `t-shirt`,
/// `yo-yo`) — that is exactly the bug [`Phrase::display_form`] avoids by reading
/// the stored words instead.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct Phrase {
    canonical: String,
    words: [String; WORD_COUNT],
}

/// An error generating or validating a [`Phrase`].
#[derive(Debug, thiserror::Error)]
pub enum PhraseError {
    /// The system random source failed while choosing words (R-13-018). Only
    /// compiled with the `generate` feature (R-41-133: `herdr-relay-hub` never
    /// enables it).
    #[cfg(feature = "generate")]
    #[error("phrase generation failed: {0}")]
    Generate(#[source] rand::rngs::SysError),
    /// The caller's word list does not hold exactly [`EFF_WORDLIST_ENTRY_COUNT`]
    /// entries.
    #[error("word list does not hold exactly {EFF_WORDLIST_ENTRY_COUNT} entries, found {0}")]
    WordListSize(usize),
    /// The phrase does not hold exactly six words.
    #[error("phrase does not hold exactly {WORD_COUNT} words")]
    WordCount,
    /// A word is not in the EFF long list.
    #[error("phrase contains a word that is not in the EFF long list")]
    WordUnknown,
    /// An empty word, a repeated hyphen, or a leading or trailing hyphen.
    #[error("phrase has an empty word, a repeated hyphen, or a leading or trailing hyphen")]
    Separator,
    /// A character is not lowercase ASCII after normalisation.
    #[error("phrase contains a character that is not lowercase ASCII after normalisation")]
    Case,
}

impl PhraseError {
    /// The wire validation code this error maps to (`docs/11-relay-protocol.md` §9.5),
    /// when it is a structural validation failure rather than a local RNG or
    /// caller-input fault.
    #[must_use]
    pub const fn code(&self) -> Option<PhraseErrorCode> {
        match self {
            Self::WordCount => Some(PhraseErrorCode::PhraseWordCount),
            Self::WordUnknown => Some(PhraseErrorCode::PhraseWordUnknown),
            Self::Separator => Some(PhraseErrorCode::PhraseSeparator),
            Self::Case => Some(PhraseErrorCode::PhraseCase),
            #[cfg(feature = "generate")]
            Self::Generate(_) => None,
            Self::WordListSize(_) => None,
        }
    }
}

impl Phrase {
    /// Chooses [`WORD_COUNT`] words uniformly, independently, from a cryptographic
    /// random source (R-13-018). `words` MUST hold exactly
    /// [`EFF_WORDLIST_ENTRY_COUNT`] entries. Only compiled with the `generate`
    /// feature.
    ///
    /// # Errors
    ///
    /// Returns [`PhraseError::WordListSize`] when `words` is the wrong size, or
    /// [`PhraseError::Generate`] if the system random source fails.
    #[cfg(feature = "generate")]
    pub fn generate(words: &[&str]) -> Result<Self, PhraseError> {
        if words.len() != EFF_WORDLIST_ENTRY_COUNT {
            return Err(PhraseError::WordListSize(words.len()));
        }
        let mut rng = StdRng::try_from_rng(&mut SysRng).map_err(PhraseError::Generate)?;
        let chosen: [String; WORD_COUNT] =
            std::array::from_fn(|_| words[rng.random_range(0..words.len())].to_owned());
        let canonical = chosen.join("-");
        Ok(Self {
            canonical,
            words: chosen,
        })
    }

    /// Parses and validates a candidate phrase, normalising it first (R-13-026).
    /// `words` MUST hold exactly [`EFF_WORDLIST_ENTRY_COUNT`] entries.
    ///
    /// The real EFF long list holds exactly four entries with an internal hyphen
    /// (`drop-down`, `felt-tip`, `t-shirt`, `yo-yo`), so a naive split of the
    /// candidate on every `-` can over-count words. [`segment_words`] resolves
    /// this before the word-count and word-membership checks run, and its result
    /// becomes [`Phrase::display_form`]'s word list; see its own doc comment for
    /// why the resolution is unambiguous against the real list.
    ///
    /// # Errors
    ///
    /// Returns the first structural failure the candidate exhibits, in the order
    /// separator, case, word count, then word membership.
    pub fn parse_canonical(candidate: &str, words: &[&str]) -> Result<Self, PhraseError> {
        if words.len() != EFF_WORDLIST_ENTRY_COUNT {
            return Err(PhraseError::WordListSize(words.len()));
        }
        let normalized = normalize(candidate);
        let parts: Vec<&str> = normalized.split('-').collect();
        if parts.iter().any(|word| word.is_empty()) {
            return Err(PhraseError::Separator);
        }
        if parts
            .iter()
            .any(|word| !word.bytes().all(|byte| byte.is_ascii_lowercase()))
        {
            return Err(PhraseError::Case);
        }
        let segmented = segment_words(&normalized, &parts, words);
        if segmented.len() != WORD_COUNT {
            return Err(PhraseError::WordCount);
        }
        if segmented.iter().any(|word| !words.contains(word)) {
            return Err(PhraseError::WordUnknown);
        }
        let words: [String; WORD_COUNT] = segmented
            .into_iter()
            .map(str::to_owned)
            .collect::<Vec<String>>()
            .try_into()
            .expect("segmented was just checked to hold exactly WORD_COUNT words");
        Ok(Self {
            canonical: normalized,
            words,
        })
    }

    /// The canonical hyphenated lowercase text: the UTF-8 bytes used as the
    /// `Noise_XXpsk0` pre-shared key (R-13-019, R-13-024).
    #[must_use]
    pub fn canonical(&self) -> &str {
        &self.canonical
    }

    /// The display form: the same six words separated by single spaces
    /// (R-13-020). Joins the six words resolved at construction time; never
    /// replaces hyphens in [`Phrase::canonical`]'s flat string directly, because
    /// that would incorrectly split any of the real EFF long list's four
    /// internal-hyphen words (`drop-down`, `felt-tip`, `t-shirt`, `yo-yo`) into
    /// two displayed fields.
    #[must_use]
    pub fn display_form(&self) -> String {
        self.words.join(" ")
    }
}

/// Greedily segments `parts` (the naive tokens of `normalized` split on every
/// `-`) into dictionary words, rejoining two adjacent tokens with a hyphen when
/// `words` holds that hyphenated form. Fixes the over-count a naive hyphen split
/// produces for the real EFF long list's four internal-hyphen entries
/// (`drop-down`, `felt-tip`, `t-shirt`, `yo-yo`; confirmed against the live list
/// at source line numbers 2009, 2528, 6640, 7748 of 7776, `docs/13-security-pairing.md`
/// R-13-025).
///
/// A single lookahead (join the current token with the next, check membership,
/// merge on a hit) is unambiguous against the real list, not just a convenient
/// simplification: every one of those four entries' left-hand half (`drop`,
/// `felt`, `t`, `yo`) is verified absent from the list as a standalone word, and
/// none of the four carries a second internal hyphen. So a naive token equal to
/// one of those four halves can only ever have been produced by splitting the
/// hyphenated word, never by a legitimately chosen standalone word of the same
/// spelling — there is no candidate segmentation this could pick over another.
fn segment_words<'a>(normalized: &'a str, parts: &[&'a str], words: &[&str]) -> Vec<&'a str> {
    let mut spans = Vec::with_capacity(parts.len());
    let mut offset = 0usize;
    for part in parts {
        let start = offset;
        let end = start + part.len();
        spans.push((start, end));
        offset = end + 1; // skip the hyphen separator normalize() guarantees here
    }
    let mut segmented = Vec::with_capacity(WORD_COUNT);
    let mut i = 0;
    while i < parts.len() {
        if i + 1 < parts.len() {
            let joined = &normalized[spans[i].0..spans[i + 1].1];
            if words.contains(&joined) {
                segmented.push(joined);
                i += 2;
                continue;
            }
        }
        segmented.push(parts[i]);
        i += 1;
    }
    segmented
}

/// Normalises manual entry before validation (R-13-026): trims outer whitespace,
/// lowercases ASCII letters, and collapses a run of spaces or hyphens to one hyphen.
/// A leading or trailing hyphen is a run of length one and survives unchanged, so
/// [`Phrase::parse_canonical`] can still reject it as [`PhraseError::Separator`].
#[must_use]
pub fn normalize(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    let mut last_was_separator = false;
    for ch in input.trim().chars() {
        if ch == '-' || ch.is_whitespace() {
            if !last_was_separator {
                out.push('-');
            }
            last_was_separator = true;
        } else {
            out.push(ch.to_ascii_lowercase());
            last_was_separator = false;
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::{Phrase, PhraseError, normalize};

    fn word_list() -> Vec<&'static str> {
        // ponytail: a synthetic 7776-entry test fixture, not the real EFF list
        // (R-13-025 forbids committing that list). Real word content is irrelevant to
        // codec correctness; only the count and per-word ASCII-lowercase shape matter.
        const WORD_POOL: [&str; 6] = [
            "remedy",
            "tapestry",
            "hubcap",
            "oversleep",
            "jailbird",
            "kinetic",
        ];
        (0..super::EFF_WORDLIST_ENTRY_COUNT)
            .map(|i| WORD_POOL[i % WORD_POOL.len()])
            .collect()
    }

    fn word_list_with_hyphenated_entries() -> Vec<&'static str> {
        // ponytail: same synthetic-fixture rationale as `word_list()`, extended with
        // the four internal-hyphen entries the real EFF long list holds (`drop-down`,
        // `felt-tip`, `t-shirt`, `yo-yo`, confirmed against the live list) plus two of
        // their component halves that are independently valid words in the real list
        // (`shirt`, `down`), so these tests exercise `parse_canonical`'s hyphen
        // segmentation against a fixture shaped like the real defect, not a
        // hyphen-free one.
        const WORD_POOL: [&str; 12] = [
            "remedy",
            "tapestry",
            "hubcap",
            "oversleep",
            "jailbird",
            "kinetic",
            "drop-down",
            "felt-tip",
            "t-shirt",
            "yo-yo",
            "shirt",
            "down",
        ];
        (0..super::EFF_WORDLIST_ENTRY_COUNT)
            .map(|i| WORD_POOL[i % WORD_POOL.len()])
            .collect()
    }

    #[cfg(feature = "generate")]
    #[test]
    fn generate_produces_a_valid_canonical_phrase() {
        let words = word_list();
        let phrase = Phrase::generate(&words).expect("generation succeeds with a full word list");
        assert_eq!(phrase.canonical().split('-').count(), super::WORD_COUNT);
        Phrase::parse_canonical(phrase.canonical(), &words)
            .expect("a generated phrase always validates");
    }

    #[test]
    fn display_form_uses_spaces() {
        let words = word_list();
        let phrase =
            Phrase::parse_canonical("remedy-tapestry-hubcap-oversleep-jailbird-kinetic", &words)
                .expect("all six words are in the fixture pool");
        assert_eq!(
            phrase.display_form(),
            "remedy tapestry hubcap oversleep jailbird kinetic"
        );
    }

    #[test]
    fn normalize_trims_lowercases_and_collapses_separators() {
        assert_eq!(
            normalize("  Remedy   Tapestry--Hubcap \n"),
            "remedy-tapestry-hubcap"
        );
    }

    #[test]
    fn parse_canonical_rejects_wrong_word_count() {
        let words = word_list();
        let error = Phrase::parse_canonical("remedy-tapestry-hubcap", &words)
            .expect_err("three words must be rejected");
        assert!(matches!(error, PhraseError::WordCount));
    }

    #[test]
    fn parse_canonical_rejects_a_leading_hyphen_as_a_separator_error() {
        let words = word_list();
        let error =
            Phrase::parse_canonical("-remedy-tapestry-hubcap-oversleep-jailbird-kinetic", &words)
                .expect_err("a leading hyphen must be rejected");
        assert!(matches!(error, PhraseError::Separator));
    }

    #[test]
    fn parse_canonical_rejects_an_unknown_word() {
        let words = word_list();
        let error = Phrase::parse_canonical(
            "remedy-tapestry-hubcap-oversleep-jailbird-zzzznotaword",
            &words,
        )
        .expect_err("a word outside the list must be rejected");
        assert!(matches!(error, PhraseError::WordUnknown));
    }

    #[cfg(feature = "generate")]
    #[test]
    fn generate_round_trips_even_when_the_word_list_contains_hyphenated_entries() {
        let words = word_list_with_hyphenated_entries();
        for _ in 0..64 {
            let phrase =
                Phrase::generate(&words).expect("generation succeeds with a full word list");
            Phrase::parse_canonical(phrase.canonical(), &words).expect(
                "a generated phrase always round-trips on the first try, even when it draws a \
                 hyphenated word",
            );
        }
    }

    #[test]
    fn parse_canonical_recovers_a_single_hyphenated_word() {
        let words = word_list_with_hyphenated_entries();
        let chosen = [
            "remedy",
            "tapestry",
            "t-shirt",
            "oversleep",
            "jailbird",
            "kinetic",
        ];
        let canonical = chosen.join("-");
        let parts: Vec<&str> = canonical.split('-').collect();
        assert_eq!(
            super::segment_words(&canonical, &parts, &words),
            chosen,
            "the recovered words must be byte-identical to the words used to build the phrase"
        );
        let phrase = Phrase::parse_canonical(&canonical, &words)
            .expect("a phrase containing one hyphenated dictionary word must parse");
        assert_eq!(phrase.canonical(), canonical);
    }

    #[test]
    fn parse_canonical_recovers_all_four_hyphenated_words_in_one_phrase() {
        let words = word_list_with_hyphenated_entries();
        let chosen = [
            "drop-down",
            "felt-tip",
            "t-shirt",
            "yo-yo",
            "remedy",
            "tapestry",
        ];
        let canonical = chosen.join("-");
        // Naively splitting on every '-' yields ten tokens, not six: this is the
        // exact over-count `segment_words` exists to resolve.
        assert_eq!(canonical.split('-').count(), 10);
        let parts: Vec<&str> = canonical.split('-').collect();
        assert_eq!(
            super::segment_words(&canonical, &parts, &words),
            chosen,
            "the recovered words must be byte-identical to the words used to build the phrase"
        );
        let phrase = Phrase::parse_canonical(&canonical, &words)
            .expect("a phrase built from all four hyphenated dictionary words must parse");
        assert_eq!(phrase.canonical(), canonical);
        let display_form = phrase.display_form();
        let display_fields: Vec<&str> = display_form.split(' ').collect();
        assert_eq!(
            display_fields.len(),
            super::WORD_COUNT,
            "display_form must report exactly six fields, not one per naive hyphen split"
        );
        assert_eq!(
            display_fields, chosen,
            "each displayed field must match one original word exactly, none split at its \
             internal hyphen"
        );
    }

    #[test]
    fn segment_words_does_not_merge_independently_valid_lookalike_neighbors() {
        let words = word_list_with_hyphenated_entries();
        // "shirt" and "down" are each independently valid words (the right-hand half
        // of `t-shirt` and `drop-down` respectively), but "shirt-down" is not a
        // dictionary entry, so they must never be merged into one word.
        let chosen = ["remedy", "shirt", "down", "tapestry", "hubcap", "kinetic"];
        let canonical = chosen.join("-");
        let parts: Vec<&str> = canonical.split('-').collect();
        assert_eq!(super::segment_words(&canonical, &parts, &words), chosen);
    }

    #[test]
    fn parse_canonical_rejects_a_lone_half_of_a_hyphenated_word() {
        let words = word_list_with_hyphenated_entries();
        // "t" alone (unpaired with a following "shirt") is not a dictionary word.
        let error = Phrase::parse_canonical("remedy-tapestry-hubcap-oversleep-jailbird-t", &words)
            .expect_err("a lone, unpaired half of a hyphenated word must be rejected");
        assert!(matches!(error, PhraseError::WordUnknown));
    }
}
