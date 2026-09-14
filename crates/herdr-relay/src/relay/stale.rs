//! Stale-Device detection and the 30-second handle hold-open window
//! (R-11-086, R-12-009).

use std::time::{Duration, Instant};

/// R-11-086, R-12-009: the relay pings a peer every 30 s with a 10 s pong timeout
/// (R-11-022, R-11-023) and closes the WebSocket on a missed pong; the Host then
/// waits for the Device to reconnect inside the relay's 30 s handle hold-open
/// (R-11-125). This tracker holds only the "has it gone stale, and is the
/// hold-open window still open" decision — the actual ping/pong observation comes
/// from whichever module drives the WebSocket.
#[derive(Debug, Clone)]
pub struct StaleDeviceDetector {
    pong_timeout: Duration,
    hold_open: Duration,
    last_pong_at: Option<Instant>,
    disconnected_at: Option<Instant>,
}

impl StaleDeviceDetector {
    /// `pong_timeout` is R-11-023's 10 s; `hold_open` is R-11-125's 30 s. Both are
    /// relay-owned constants (`docs/11-relay-protocol.md`), not Host tunables, so
    /// they are passed explicitly rather than read from `RelayConfig`.
    pub fn new(pong_timeout: Duration, hold_open: Duration) -> Self {
        Self {
            pong_timeout,
            hold_open,
            last_pong_at: None,
            disconnected_at: None,
        }
    }

    /// Call whenever a pong (or any traffic proving liveness) arrives from the
    /// Device.
    pub fn record_pong(&mut self, now: Instant) {
        self.last_pong_at = Some(now);
        self.disconnected_at = None;
    }

    /// Call when the Device's WebSocket closes, so the hold-open window starts.
    pub fn record_disconnected(&mut self, now: Instant) {
        self.disconnected_at = Some(now);
    }

    /// `true` once `now` is `pong_timeout` past the last observed pong with no
    /// newer one (R-11-023).
    pub fn is_stale(&self, now: Instant, last_ping_at: Instant) -> bool {
        let last_seen = self.last_pong_at.unwrap_or(last_ping_at);
        now.saturating_duration_since(last_seen) >= self.pong_timeout
    }

    /// `true` while the Host should keep waiting for the Device to reconnect on
    /// the same handle, rather than treating the slot as gone (R-11-125,
    /// R-12-009).
    pub fn within_hold_open(&self, now: Instant) -> bool {
        match self.disconnected_at {
            None => true, // never disconnected: nothing to hold open for
            Some(since) => now.saturating_duration_since(since) < self.hold_open,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// R-11-086: `is_stale` flips to `true` only once the pong timeout has
    /// elapsed with no fresher pong recorded — the stale-Device detection
    /// this module's own doc comment describes.
    #[test]
    fn stale_device_detector_flags_a_missed_pong() {
        let mut detector =
            StaleDeviceDetector::new(Duration::from_secs(10), Duration::from_secs(30));
        let ping_at = Instant::now();
        detector.record_pong(ping_at);
        assert!(!detector.is_stale(ping_at + Duration::from_secs(5), ping_at));
        assert!(detector.is_stale(ping_at + Duration::from_secs(11), ping_at));
    }

    #[test]
    fn stale_device_detector_holds_the_slot_open_for_30_seconds() {
        let mut detector =
            StaleDeviceDetector::new(Duration::from_secs(10), Duration::from_secs(30));
        let t0 = Instant::now();
        detector.record_disconnected(t0);
        assert!(detector.within_hold_open(t0 + Duration::from_secs(29)));
        assert!(!detector.within_hold_open(t0 + Duration::from_secs(31)));
    }

    #[test]
    fn stale_device_detector_holds_open_before_any_disconnect() {
        let detector = StaleDeviceDetector::new(Duration::from_secs(10), Duration::from_secs(30));
        assert!(detector.within_hold_open(Instant::now()));
    }
}
