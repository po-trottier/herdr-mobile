//! The EFF long Diceware word list (R-13-017): the actual 7776-entry data that
//! `herdr_relay_proto::phrase` deliberately does not hold. That crate's own doc
//! comment names this file as the one R-13-025 makes responsible for the
//! build-time download, checksum verification, and on-disk cache of the list,
//! and explicitly declines to duplicate that logic itself. This module honours
//! that split: it owns the word *data* (fetch, verify, cache, normalise), and
//! re-uses `herdr_relay_proto::phrase`'s codec (`Phrase`, `normalize`, …)
//! unchanged, so word selection and phrase validation are implemented exactly
//! once (R-40-031).
//!
//! `docs/decisions/ADR-004-pairing-phrase-and-routing.md` settles the fetch
//! timing: "A local copy is not bundled; the Host fetches it once and caches
//! it" — a runtime, not build-time, fetch. [`load`] implements exactly that:
//! read the cache file; on a miss, fetch, verify, write the cache, then
//! return. `AGENTS.md`'s "Never build" rule forbids an HTTP client crate
//! outright (an unconditional prohibition, not a "no client is pinned yet"
//! gap), so [`default_fetch`] shells out to `curl` (falling back to `wget`)
//! rather than adding one — the fetch mechanism stays swappable
//! ([`load_with_fetch`]) regardless.
//!
//! **That shell-out itself hit `AGENTS.md`'s "Never spawn a console-visible
//! child process" rule**, which names this exact function: `curl.exe`/
//! `wget.exe` are console-subsystem binaries, and `herdr-relay` runs as a
//! console-less Windows Scheduled Task
//! (`crates/herdr-relay/windows/ensure-service.ps1`), so the naive spawn pops
//! a new, visible, focus-stealing console window. The fix, applied by
//! [`suppress_console_window`]: pass Win32's `CREATE_NO_WINDOW` creation flag
//! (`0x0800_0000`) via `std::os::windows::process::CommandExt::creation_flags`
//! — no new dependency, `#[cfg(windows)]`-gated, a no-op on POSIX where this
//! concern does not exist. Unlike the rule's first named instance
//! (`chrome-headless-shell.exe`, which forks its own internal GPU/network/
//! renderer child processes that never inherit a flag set on the direct
//! child, so the only fix there was eliminating the subprocess entirely),
//! `curl`/`wget` are simple, single-process CLI tools with no internal
//! re-forking, so the flag on the direct child is the complete fix here.
//! Microsoft's own `CREATE_NO_WINDOW` documentation states this precisely:
//! "the console handle for the application is not set" — the process still
//! gets a console object for its own stdio, it is simply never shown as a
//! window. This was confirmed once, manually, during this session, using a
//! temporary standalone harness outside this crate (compiled, run, and
//! deleted; never checked in) that measured the real Win32 state
//! (`AttachConsole`/`GetConsoleWindow`/`IsWindowVisible`) of a `curl.exe`
//! child spawned from a genuinely console-less `DETACHED_PROCESS` parent.
//! This doc comment is the durable record of that result; it is not re-run
//! automatically, and this module intentionally holds no test that spawns
//! `curl.exe`/`wget.exe` without `CREATE_NO_WINDOW` — even a temporary,
//! deliberately-unflagged spawn is itself the exact hazard this section
//! describes, so it is not something this module's own test suite
//! reproduces, on demand or otherwise.
//!
//! **A real defect found while sourcing the list — fixed in
//! `herdr_relay_proto::phrase`, not here:** the canonical EFF file (fetched
//! and hashed for this module's own recorded checksum below) holds four
//! entries with an internal hyphen: `drop-down`, `felt-tip`, `t-shirt`,
//! `yo-yo` (source line numbers 2009, 2528, 6640 and 7748 of 7776). A naive
//! split of the canonical six-word text on every `-` over-counts words when
//! one of these four is chosen, so `Phrase::generate`'s original test suite
//! never caught it (it fixtured a synthetic, hyphen-free pool).
//! `herdr_relay_proto::phrase::Phrase::parse_canonical` now resolves this
//! correctly itself, via a `segment_words` step that recognises the four
//! hyphenated entries before splitting; see that module's own doc comment for
//! the fix. [`generate_phrase`] below needs no workaround as a result — it is
//! a direct, single-attempt call, exactly as `Phrase::generate` on its own.
//! This module's `generate_phrase_always_returns_a_phrase_that_round_trips`
//! test still exercises this exact word through this module's public API, so
//! a regression in the shared codec is still caught here too. This does not
//! fix the same ambiguity for a Device's *manual* phrase entry (an EFF word
//! containing a hyphen can still only be typed correctly if the Device's own
//! parser applies the same segmentation); that is `app/`-side, Device-only
//! scope, outside this package, and is flagged in this session's report for
//! the Device pairing-entry work package.

use std::path::Path;
use std::process::Command;

use blake2::{Blake2s256, Digest};
use thiserror::Error;

pub use herdr_relay_proto::phrase::{
    EFF_WORDLIST_ENTRY_COUNT, EFF_WORDLIST_URL, Phrase, PhraseError, WORD_COUNT, normalize,
};

/// `BLAKE2s-256` of the raw bytes downloaded from [`EFF_WORDLIST_URL`] (the
/// `<dice-roll>\t<word>` source file, 108800 bytes, 7776 lines), verified by
/// downloading the canonical URL and hashing it with the same construction
/// `blake2` 0.10.6 uses elsewhere in this crate (`keys.rs`'s fingerprint,
/// `noise.rs`'s PSK derivation) — no new hash primitive is added (R-13-025:
/// "The checksum value is recorded by the implementer ... after verification
/// and is never invented in advance"). `blake2`, not `sha2`, because it is
/// already a pinned Host dependency and R-13-025 does not name an algorithm.
const RAW_SOURCE_CHECKSUM_BLAKE2S256_HEX: &str =
    "e246c56edf8a06d87d89fd37966576ee70302c19ce128dac5004a87a7990d060";

/// A fetch, checksum, parsing or cache failure for the EFF word list.
#[derive(Debug, Error)]
pub enum WordlistError {
    /// Neither `curl` nor `wget` is installed, or both failed
    /// ([`default_fetch`]). [`load_with_fetch`] lets a caller substitute a
    /// different fetcher.
    #[error("fetching the EFF wordlist from {0} failed: {1}")]
    Fetch(String, String),
    /// No fetch command was found at all.
    #[error("no fetch command is available to download the EFF wordlist (tried curl, then wget)")]
    NoFetcherAvailable,
    /// The downloaded or cached bytes are not valid UTF-8.
    #[error("the EFF wordlist source is not valid UTF-8")]
    NotUtf8,
    /// The downloaded bytes did not match [`RAW_SOURCE_CHECKSUM_BLAKE2S256_HEX`]
    /// (R-13-025).
    #[error("the downloaded EFF wordlist failed checksum verification (R-13-025)")]
    ChecksumMismatch,
    /// The source did not hold exactly [`EFF_WORDLIST_ENTRY_COUNT`] entries
    /// after parsing.
    #[error("EFF wordlist does not hold exactly {EFF_WORDLIST_ENTRY_COUNT} entries, found {0}")]
    WrongEntryCount(usize),
    /// Reading or writing the on-disk cache file failed.
    #[error("reading or writing the EFF wordlist cache file failed: {0}")]
    Cache(#[source] std::io::Error),
    /// The underlying phrase codec rejected the request (for example, a word
    /// list of the wrong size).
    #[error(transparent)]
    Phrase(#[from] PhraseError),
}

/// Generates a pairing phrase from `words` (delegates to
/// [`Phrase::generate`]; converts [`PhraseError`] into [`WordlistError`] so
/// callers only need one error type at this module's boundary). A single
/// attempt: `herdr_relay_proto::phrase::Phrase::parse_canonical` now segments
/// the real EFF list's four internal-hyphen words correctly (see this
/// module's own doc comment), so every generated phrase round-trips on the
/// first try — no retry is needed.
///
/// # Errors
///
/// Returns [`PhraseError`] (via [`WordlistError::Phrase`]) if `words` is not
/// exactly [`EFF_WORDLIST_ENTRY_COUNT`] entries or the system random source
/// fails.
pub fn generate_phrase(words: &[&str]) -> Result<Phrase, WordlistError> {
    Ok(Phrase::generate(words)?)
}

/// Converts a loaded word list into the `&[&str]` slice
/// [`generate_phrase`]/[`Phrase::parse_canonical`] take.
#[must_use]
pub fn word_refs(words: &[String]) -> Vec<&str> {
    words.iter().map(String::as_str).collect()
}

/// Loads the EFF word list, using `curl`/`wget` as the fetcher
/// ([`default_fetch`]) and `cache_path` as the on-disk cache. The caller
/// supplies `cache_path` (never a hardcoded per-OS path, matching R-10-045's
/// convention elsewhere in this crate) — typically a file under the Host's
/// config directory (`crate::config::ConfigPaths`), assembled by whichever
/// module wires the live Host together.
///
/// # Errors
///
/// See [`WordlistError`].
pub fn load(cache_path: &Path) -> Result<Vec<String>, WordlistError> {
    load_with_fetch(cache_path, default_fetch)
}

/// [`load`], with the network fetch replaced by `fetch` — the seam this
/// module's own tests use to avoid a real network call.
///
/// # Errors
///
/// See [`WordlistError`].
pub fn load_with_fetch(
    cache_path: &Path,
    fetch: impl FnOnce(&str) -> Result<Vec<u8>, WordlistError>,
) -> Result<Vec<String>, WordlistError> {
    load_verified(cache_path, fetch, RAW_SOURCE_CHECKSUM_BLAKE2S256_HEX)
}

/// [`load_with_fetch`]'s full implementation, with the expected checksum also
/// injected so this module's tests can exercise the whole cache-miss /
/// verify / cache-write / cache-hit pipeline against a synthetic fixture
/// without ever holding the real EFF list in memory or on disk during a test
/// run (R-13-025 forbids committing that list, tests included).
fn load_verified(
    cache_path: &Path,
    fetch: impl FnOnce(&str) -> Result<Vec<u8>, WordlistError>,
    expected_checksum_hex: &str,
) -> Result<Vec<String>, WordlistError> {
    let raw = match std::fs::read(cache_path) {
        Ok(bytes) => bytes,
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => {
            let bytes = fetch(EFF_WORDLIST_URL)?;
            write_cache(cache_path, &bytes)?;
            bytes
        }
        Err(err) => return Err(WordlistError::Cache(err)),
    };
    verify_checksum(&raw, expected_checksum_hex)?;
    extract_words(&raw)
}

fn write_cache(path: &Path, bytes: &[u8]) -> Result<(), WordlistError> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(WordlistError::Cache)?;
    }
    std::fs::write(path, bytes).map_err(WordlistError::Cache)
}

fn hex_digest(bytes: &[u8]) -> String {
    use std::fmt::Write as _;
    Blake2s256::digest(bytes)
        .iter()
        .fold(String::with_capacity(64), |mut hex, byte| {
            let _ = write!(hex, "{byte:02x}");
            hex
        })
}

fn verify_checksum(raw: &[u8], expected_hex: &str) -> Result<(), WordlistError> {
    if hex_digest(raw) == expected_hex {
        Ok(())
    } else {
        Err(WordlistError::ChecksumMismatch)
    }
}

/// Parses the `<dice-roll>\t<word>` source format (R-13-025's normalisation:
/// lowercase ASCII, one word per line, no blank lines, no leading or trailing
/// whitespace), taking the last tab-separated field of each non-blank line so
/// a bare word-only line (a pre-normalised source) also parses.
fn extract_words(raw: &[u8]) -> Result<Vec<String>, WordlistError> {
    let text = std::str::from_utf8(raw).map_err(|_| WordlistError::NotUtf8)?;
    let words: Vec<String> = text
        .lines()
        .filter_map(|line| {
            let word = line.rsplit('\t').next()?.trim();
            (!word.is_empty()).then(|| word.to_ascii_lowercase())
        })
        .collect();
    if words.len() == EFF_WORDLIST_ENTRY_COUNT {
        Ok(words)
    } else {
        Err(WordlistError::WrongEntryCount(words.len()))
    }
}

/// Runs one fetch command, returning `None` if the binary itself was not
/// found (so [`default_fetch`] can fall through to the next candidate) and
/// `Some(Err(_))` for every other failure (found the binary, it failed).
fn run_fetch_command(mut cmd: Command) -> Option<Result<Vec<u8>, WordlistError>> {
    match cmd.output() {
        Ok(output) if output.status.success() => Some(Ok(output.stdout)),
        Ok(output) => Some(Err(WordlistError::Fetch(
            format!("{:?}", cmd.get_program()),
            format!(
                "exit status {status}: {stderr}",
                status = output.status,
                stderr = String::from_utf8_lossy(&output.stderr).trim()
            ),
        ))),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => None,
        Err(err) => Some(Err(WordlistError::Fetch(
            format!("{:?}", cmd.get_program()),
            err.to_string(),
        ))),
    }
}

use crate::process::suppress_console_window;

/// Fetches `url` by shelling out to `curl`, falling back to `wget` when
/// `curl` is not installed (this module's own doc comment explains why no
/// HTTP client crate is used, and why the shell-out needs
/// [`suppress_console_window`]).
///
/// # Errors
///
/// Returns [`WordlistError::NoFetcherAvailable`] if neither binary is found,
/// or [`WordlistError::Fetch`] if a found binary exits non-zero.
pub fn default_fetch(url: &str) -> Result<Vec<u8>, WordlistError> {
    let mut curl = Command::new("curl");
    curl.args([
        "--fail",
        "--silent",
        "--show-error",
        "--location",
        "--max-time",
        "30",
        url,
    ]);
    suppress_console_window(&mut curl);
    if let Some(result) = run_fetch_command(curl) {
        return result;
    }

    let mut wget = Command::new("wget");
    wget.args(["--quiet", "-O", "-", "--timeout=30", url]);
    suppress_console_window(&mut wget);
    if let Some(result) = run_fetch_command(wget) {
        return result;
    }

    Err(WordlistError::NoFetcherAvailable)
}

#[cfg(test)]
mod tests {
    use std::cell::Cell;
    use std::process::Command;
    use std::time::{SystemTime, UNIX_EPOCH};

    use super::{
        EFF_WORDLIST_ENTRY_COUNT, RAW_SOURCE_CHECKSUM_BLAKE2S256_HEX, WordlistError, extract_words,
        generate_phrase, hex_digest, load_verified, run_fetch_command, verify_checksum, word_refs,
        write_cache,
    };
    use crate::pairing::wordlist::Phrase;

    /// A tiny, deterministic stand-in for the real `<dice-roll>\t<word>`
    /// source format: real word content is irrelevant to parsing, checksum
    /// or cache-mechanics correctness (R-13-025 forbids committing the real
    /// list, tests included), only the shape and the exact entry count
    /// matter.
    fn raw_source_fixture() -> Vec<u8> {
        let mut raw = String::new();
        for i in 0..EFF_WORDLIST_ENTRY_COUNT {
            raw.push_str(&format!("11{i:04}\tword{i}\n"));
        }
        raw.into_bytes()
    }

    /// A synthetic 7776-entry pool with one hyphenated entry mixed in, so
    /// `generate_phrase`'s round-trip through `Phrase::parse_canonical`'s
    /// hyphen segmentation is realistically exercised, not just the
    /// hyphen-free default fixture other tests use.
    fn word_list_with_a_hyphenated_entry() -> Vec<&'static str> {
        const POOL: [&str; 7] = [
            "remedy",
            "tapestry",
            "hubcap",
            "oversleep",
            "jailbird",
            "kinetic",
            "t-shirt",
        ];
        (0..EFF_WORDLIST_ENTRY_COUNT)
            .map(|i| POOL[i % POOL.len()])
            .collect()
    }

    fn temp_cache_path(name: &str) -> std::path::PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let mut path = std::env::temp_dir();
        path.push(format!(
            "herdr-relay-wordlist-test-{}-{}-{name}",
            std::process::id(),
            nanos
        ));
        path
    }

    #[test]
    fn recorded_checksum_is_a_well_formed_64_character_lowercase_hex_string() {
        assert_eq!(RAW_SOURCE_CHECKSUM_BLAKE2S256_HEX.len(), 64);
        assert!(
            RAW_SOURCE_CHECKSUM_BLAKE2S256_HEX
                .bytes()
                .all(|b| b.is_ascii_digit() || b.is_ascii_lowercase())
        );
    }

    #[test]
    fn extract_words_parses_the_dice_roll_source_format() {
        let raw = raw_source_fixture();
        let words = extract_words(&raw).unwrap();
        assert_eq!(words.len(), EFF_WORDLIST_ENTRY_COUNT);
        assert_eq!(words[0], "word0");
        assert_eq!(
            words[EFF_WORDLIST_ENTRY_COUNT - 1],
            format!("word{}", EFF_WORDLIST_ENTRY_COUNT - 1)
        );
    }

    #[test]
    fn extract_words_rejects_the_wrong_entry_count() {
        let raw = b"11111\tabacus\n11112\tabdomen\n".to_vec();
        let error = extract_words(&raw).unwrap_err();
        assert!(matches!(error, WordlistError::WrongEntryCount(2)));
    }

    #[test]
    fn extract_words_skips_blank_lines() {
        let raw = "11111\tabacus\n\n11112\tabdomen\n".as_bytes().to_vec();
        let error = extract_words(&raw).unwrap_err();
        // Only asserting the shape here (2 real entries after the blank line
        // is skipped): the count is deliberately wrong for this tiny fixture.
        assert!(matches!(error, WordlistError::WrongEntryCount(2)));
    }

    #[test]
    fn extract_words_lowercases_every_word() {
        let mut raw = raw_source_fixture();
        // `raw_source_fixture` already lowercases; uppercase the whole buffer
        // in place so this test actually exercises the lowercasing step.
        for byte in &mut raw {
            *byte = byte.to_ascii_uppercase();
        }
        let words = extract_words(&raw).unwrap();
        assert!(words.iter().all(|w| {
            w.bytes()
                .all(|b| !b.is_ascii_alphabetic() || b.is_ascii_lowercase())
        }));
        assert_eq!(words[0], "word0");
    }

    #[test]
    fn verify_checksum_accepts_a_matching_digest_and_rejects_a_tampered_one() {
        let raw = raw_source_fixture();
        let checksum = hex_digest(&raw);
        assert!(verify_checksum(&raw, &checksum).is_ok());

        let mut tampered = raw.clone();
        tampered.push(b'\n');
        assert!(matches!(
            verify_checksum(&tampered, &checksum),
            Err(WordlistError::ChecksumMismatch)
        ));
    }

    #[test]
    fn write_cache_creates_the_parent_directory_and_round_trips_bytes() {
        let path = temp_cache_path("write-cache");
        let parent = path.parent().unwrap().join("nested");
        let path = parent.join("wordlist.txt");
        write_cache(&path, b"hello").unwrap();
        assert_eq!(std::fs::read(&path).unwrap(), b"hello");
        std::fs::remove_dir_all(parent.parent().unwrap()).ok();
    }

    #[test]
    fn load_verified_fetches_verifies_caches_and_reuses_the_cache_on_a_second_call() {
        let raw = raw_source_fixture();
        let checksum = hex_digest(&raw);
        let path = temp_cache_path("load-verified");
        let fetch_calls = Cell::new(0);

        let words = load_verified(
            &path,
            |_url| {
                fetch_calls.set(fetch_calls.get() + 1);
                Ok(raw.clone())
            },
            &checksum,
        )
        .unwrap();
        assert_eq!(words.len(), EFF_WORDLIST_ENTRY_COUNT);
        assert_eq!(fetch_calls.get(), 1);

        let words_again = load_verified(
            &path,
            |_url| {
                fetch_calls.set(fetch_calls.get() + 1);
                Ok(raw.clone())
            },
            &checksum,
        )
        .unwrap();
        assert_eq!(words_again, words);
        assert_eq!(
            fetch_calls.get(),
            1,
            "a cache hit must not call the fetcher again"
        );

        std::fs::remove_file(&path).ok();
    }

    #[test]
    fn load_verified_rejects_a_cached_file_that_fails_checksum_verification() {
        let raw = raw_source_fixture();
        let checksum = hex_digest(&raw);
        let path = temp_cache_path("load-verified-tampered-cache");
        write_cache(&path, b"not the real list").unwrap();

        let error =
            load_verified(&path, |_url| unreachable!("cache is present"), &checksum).unwrap_err();
        assert!(matches!(error, WordlistError::ChecksumMismatch));

        std::fs::remove_file(&path).ok();
    }

    #[test]
    fn generate_phrase_always_returns_a_phrase_that_round_trips() {
        let words = word_list_with_a_hyphenated_entry();
        for _ in 0..50 {
            let phrase = generate_phrase(&words).unwrap();
            Phrase::parse_canonical(phrase.canonical(), &words)
                .expect("generate_phrase's own contract: the result always round-trips");
        }
    }

    #[test]
    fn word_refs_borrows_every_owned_word() {
        let owned = vec!["alpha".to_owned(), "beta".to_owned()];
        assert_eq!(word_refs(&owned), vec!["alpha", "beta"]);
    }

    #[test]
    fn run_fetch_command_returns_stdout_on_success() {
        let cmd = if cfg!(windows) {
            let mut cmd = Command::new("cmd");
            cmd.args(["/C", "echo hello"]);
            cmd
        } else {
            let mut cmd = Command::new("echo");
            cmd.arg("hello");
            cmd
        };
        let result = run_fetch_command(cmd)
            .expect("this binary is present on every supported dev/CI platform")
            .unwrap();
        assert_eq!(String::from_utf8(result).unwrap().trim(), "hello");
    }

    #[test]
    fn run_fetch_command_returns_none_when_the_binary_is_missing() {
        let cmd = Command::new("herdr-relay-definitely-not-a-real-binary-xyz");
        assert!(run_fetch_command(cmd).is_none());
    }
}
