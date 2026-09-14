//! Exponential backoff with jitter for a long-lived connection (R-10-014).

use std::time::{Duration, Instant};

use crate::config::RelayConfig;

/// R-10-014: exponential backoff with jitter for a long-lived connection (the
/// Herdr subscription today; the relay WebSocket now `connection.rs` opens
/// one). Pure and synchronous: the caller supplies `Instant::now()` and a
/// jitter source, so this is deterministically testable with no real
/// sleeping.
#[derive(Debug, Clone)]
pub struct ReconnectBackoff {
    initial: Duration,
    max: Duration,
    /// A fraction, `0.20` for ±20% (R-10-014 step 4).
    jitter: f64,
    reset_after: Duration,
    attempt: u32,
    connected_at: Option<Instant>,
}

impl ReconnectBackoff {
    pub fn new(config: &RelayConfig) -> Self {
        Self {
            initial: Duration::from_millis(config.reconnect_initial_ms),
            max: Duration::from_millis(config.reconnect_max_ms),
            jitter: config.reconnect_jitter,
            reset_after: Duration::from_secs(config.reconnect_reset_after_s),
            attempt: 0,
            connected_at: None,
        }
    }

    /// R-10-014 step 5: call when the connection is established, so a later drop
    /// knows whether it survived long enough to reset the ladder.
    pub fn record_connected(&mut self, now: Instant) {
        self.connected_at = Some(now);
    }

    /// Call when the connection drops. Resets the ladder to attempt 1 if the prior
    /// connection survived at least `reconnect_reset_after_s` (R-10-014 step 5);
    /// otherwise keeps climbing.
    pub fn record_disconnected(&mut self, now: Instant) {
        let survived_long_enough = self
            .connected_at
            .is_some_and(|since| now.saturating_duration_since(since) >= self.reset_after);
        if survived_long_enough {
            self.attempt = 0;
        }
        self.connected_at = None;
    }

    /// The wait before the next reconnect attempt (R-10-014 steps 1-4), applying
    /// ±`jitter` from `jitter_unit` (expected in `[-1.0, 1.0]`; a caller passes a
    /// value from its own random source — this struct adds no `rand` dependency of
    /// its own beyond what the caller already has). Advances the attempt counter.
    pub fn next_wait(&mut self, jitter_unit: f64) -> Duration {
        let exponent = self.attempt.min(u32::BITS - 1);
        self.attempt = self.attempt.saturating_add(1);
        let base = self
            .initial
            .saturating_mul(1u32.checked_shl(exponent).unwrap_or(u32::MAX))
            .min(self.max);
        let jitter_unit = jitter_unit.clamp(-1.0, 1.0);
        let factor = 1.0 + jitter_unit * self.jitter;
        let millis = (base.as_millis() as f64 * factor).max(0.0);
        Duration::from_millis(millis as u64)
    }

    /// The attempt number `next_wait` will use next (1-based), for logging.
    pub fn attempt_number(&self) -> u32 {
        self.attempt + 1
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn config() -> RelayConfig {
        RelayConfig::default()
    }

    #[test]
    fn backoff_doubles_from_the_configured_initial_up_to_the_cap() {
        let mut backoff = ReconnectBackoff::new(&config());
        let waits: Vec<u64> = (0..8)
            .map(|_| backoff.next_wait(0.0).as_millis() as u64)
            .collect();
        assert_eq!(waits, vec![250, 500, 1000, 2000, 4000, 8000, 8000, 8000]);
    }

    #[test]
    fn backoff_applies_plus_or_minus_20_percent_jitter() {
        let mut low = ReconnectBackoff::new(&config());
        let mut high = ReconnectBackoff::new(&config());
        let low_wait = low.next_wait(-1.0).as_millis();
        let high_wait = high.next_wait(1.0).as_millis();
        assert_eq!(low_wait, 200); // 250 * 0.8
        assert_eq!(high_wait, 300); // 250 * 1.2
    }

    #[test]
    fn backoff_resets_after_surviving_30_seconds() {
        let mut backoff = ReconnectBackoff::new(&config());
        let t0 = Instant::now();
        backoff.next_wait(0.0);
        backoff.next_wait(0.0);
        assert_eq!(backoff.attempt_number(), 3);

        backoff.record_connected(t0);
        backoff.record_disconnected(t0 + Duration::from_secs(31));
        assert_eq!(
            backoff.attempt_number(),
            1,
            "surviving 30s+ resets the ladder (R-10-014 step 5)"
        );
    }

    #[test]
    fn backoff_does_not_reset_after_a_short_connection() {
        let mut backoff = ReconnectBackoff::new(&config());
        backoff.next_wait(0.0);
        let t0 = Instant::now();
        backoff.record_connected(t0);
        backoff.record_disconnected(t0 + Duration::from_secs(5));
        assert_eq!(
            backoff.attempt_number(),
            2,
            "a short-lived connection keeps climbing"
        );
    }
}
