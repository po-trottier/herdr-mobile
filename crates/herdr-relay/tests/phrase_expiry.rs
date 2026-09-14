//! `docs/90-implementation-plan.md` `WP-10-b`: asserts a phrase is refused
//! after 600 seconds (R-13-022) and after three failed attempts (R-13-023),
//! driven through caller-supplied `Instant`s so the test needs no real
//! sleeping — matches `crate::frame_codec`'s own `Reassembler` tests.
//! `crates/herdr-relay/src/pairing.rs`'s own `#[cfg(test)]` module covers the
//! finer-grained state-machine edge cases (the exact 600-second boundary,
//! expiry not auto-regenerating, a stale attempt against an already-expired
//! phrase, a spent phrase staying dead until `regenerate`, enrolment, and
//! the built URI's field content); this file is the black-box confirmation
//! of the two headline guarantees through `herdr_relay`'s public API alone.

use std::time::{Duration, Instant};

use herdr_relay::pairing::wordlist;
use herdr_relay::pairing::{MAX_ATTEMPTS, PHRASE_LIFETIME, PairingSession};

const RELAY_ORIGIN: &str = "https://relay.example.com";

/// A synthetic 7776-entry fixture (R-13-025 forbids committing the real EFF
/// list); only the count and per-word ASCII-lowercase shape matter to the
/// codec.
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
fn a_phrase_is_refused_after_600_seconds() {
    let words = word_list();
    let start = Instant::now();
    let mut session = PairingSession::new(RELAY_ORIGIN.to_owned(), &words, start).unwrap();
    assert!(session.is_live(start), "a fresh phrase must be live");

    let after_expiry = start + PHRASE_LIFETIME + Duration::from_secs(1);
    assert!(
        !session.is_live(after_expiry),
        "a phrase more than 600 seconds old must be refused (R-13-022)"
    );
    assert!(
        session.pairing_uri(after_expiry).is_none(),
        "the pairing URI must be destroyed on expiry"
    );
    assert!(
        session.handle(after_expiry).is_none(),
        "the routing handle must be destroyed on expiry"
    );
    assert!(
        session.qr(after_expiry).is_none(),
        "the QR buffer must be destroyed on expiry"
    );
}

#[test]
fn a_phrase_is_refused_after_three_failed_attempts() {
    let words = word_list();
    let now = Instant::now();
    let mut session = PairingSession::new(RELAY_ORIGIN.to_owned(), &words, now).unwrap();

    for _ in 0..MAX_ATTEMPTS {
        session.record_failed_attempt(now);
    }

    // R-13-023: the third failure destroys the phrase and the handle used
    // for the first three attempts and mints no replacement — the session
    // is spent, and the pairing pane waits for `p`.
    assert!(
        !session.is_live(now),
        "the third failure ends the session; it does not replace the phrase"
    );
    assert!(
        session.is_spent(),
        "the third failure is the spent state, not expiry (R-13-023)"
    );
    assert!(
        session.handle(now).is_none(),
        "the handle used for the three failed attempts must be destroyed (R-13-023)"
    );
}
