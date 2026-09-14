//! The relay-owned WebSocket ping/pong heartbeat: a ping every 30 seconds and a
//! 10-second pong deadline. A peer's own ping is answered automatically at the
//! WebSocket layer and never reaches this type (R-12-022, R-11-022, R-11-023,
//! R-11-024).

use std::time::Duration;

use tokio::time::{Instant, Interval, MissedTickBehavior, interval_at, sleep_until};

/// How often the relay pings each connected peer (R-12-022, R-11-022).
pub const PING_INTERVAL: Duration = Duration::from_secs(30);
/// How long a peer has to answer a ping with a pong before the relay drops it (R-11-023).
pub const PONG_TIMEOUT: Duration = Duration::from_secs(10);

/// What [`Heartbeat::wait`] resolved for.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HeartbeatEvent {
    /// A ping is due now. Send it, then call [`Heartbeat::note_ping_sent`].
    PingDue,
    /// No pong arrived within [`PONG_TIMEOUT`] of the last ping. Drop the connection.
    PongOverdue,
}

/// Tracks one connection's ping/pong cycle.
pub struct Heartbeat {
    ticker: Interval,
    awaiting_pong_since: Option<Instant>,
}

impl Heartbeat {
    /// Starts a fresh heartbeat; the first ping is due after one full
    /// [`PING_INTERVAL`].
    #[must_use]
    pub fn new() -> Self {
        // `tokio::time::interval` fires its first tick immediately; that would send
        // a ping the instant a peer connects instead of after PING_INTERVAL, so the
        // first tick is scheduled explicitly at `now + PING_INTERVAL` instead.
        let mut ticker = interval_at(Instant::now() + PING_INTERVAL, PING_INTERVAL);
        // A ping the relay was too busy to send on time is sent once, not replayed in
        // a burst, once the runtime catches up.
        ticker.set_missed_tick_behavior(MissedTickBehavior::Delay);
        Self {
            ticker,
            awaiting_pong_since: None,
        }
    }

    /// Resolves for the next ping or, while a pong is outstanding, for that pong's
    /// deadline — whichever comes first. Combined into one `&mut self` method,
    /// rather than two separate ones, so a caller's own `tokio::select!` needs only
    /// one borrow of this heartbeat (two live borrows in sibling branches would not
    /// borrow-check). Cancel-safe: both inner races recompute their state from
    /// `self` on every call, so dropping this future loses nothing.
    pub async fn wait(&mut self) -> HeartbeatEvent {
        match self.awaiting_pong_since {
            Some(since) => {
                tokio::select! {
                    () = sleep_until(since + PONG_TIMEOUT) => HeartbeatEvent::PongOverdue,
                    _ = self.ticker.tick() => HeartbeatEvent::PingDue,
                }
            }
            None => {
                self.ticker.tick().await;
                HeartbeatEvent::PingDue
            }
        }
    }

    /// Records that a ping was just sent, starting the pong deadline.
    pub fn note_ping_sent(&mut self) {
        self.awaiting_pong_since = Some(Instant::now());
    }

    /// Records that a pong arrived, clearing any pending deadline.
    pub fn note_pong(&mut self) {
        self.awaiting_pong_since = None;
    }
}

impl Default for Heartbeat {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use super::{Heartbeat, HeartbeatEvent};

    /// The first ping does not fire before one full `PING_INTERVAL` elapses
    /// (R-11-022).
    #[tokio::test(start_paused = true)]
    async fn first_wait_does_not_resolve_before_one_full_interval() {
        let mut heartbeat = Heartbeat::new();
        // Leave a clear 10ms margin before PING_INTERVAL's deadline: advancing to
        // within 1ms of it ties the ticker's due instant against the race's own
        // sleep at the same paused-clock tick, which `select!` resolves arbitrarily
        // and made this test flaky.
        tokio::time::advance(super::PING_INTERVAL - Duration::from_millis(10)).await;
        tokio::select! {
            _ = heartbeat.wait() => panic!("must not fire a ping before one full PING_INTERVAL"),
            () = tokio::time::sleep(Duration::from_millis(5)) => {}
        }
    }

    /// The first ping fires after exactly one `PING_INTERVAL`, matching the
    /// relay's 30-second ping cadence (R-11-022, R-12-022).
    #[tokio::test(start_paused = true)]
    async fn first_wait_resolves_ping_due_after_one_interval() {
        let mut heartbeat = Heartbeat::new();
        tokio::select! {
            event = heartbeat.wait() => assert_eq!(event, HeartbeatEvent::PingDue),
            () = tokio::time::sleep(super::PING_INTERVAL + Duration::from_secs(1)) => {
                panic!("the first wait must resolve within one PING_INTERVAL");
            }
        }
    }

    /// No pong within `PONG_TIMEOUT` resolves `PongOverdue`, matching the
    /// relay's 10-second pong deadline (R-12-022).
    #[tokio::test(start_paused = true)]
    async fn wait_resolves_pong_overdue_when_no_pong_arrives() {
        let mut heartbeat = Heartbeat::new();
        heartbeat.note_ping_sent();
        tokio::time::advance(super::PONG_TIMEOUT).await;
        let event = heartbeat.wait().await;
        assert_eq!(event, HeartbeatEvent::PongOverdue);
    }

    /// A received pong clears the deadline so `wait` falls back to the next
    /// ping (R-12-022).
    #[tokio::test(start_paused = true)]
    async fn a_pong_clears_the_deadline_so_wait_falls_back_to_the_next_ping() {
        let mut heartbeat = Heartbeat::new();
        heartbeat.note_ping_sent();
        heartbeat.note_pong();
        tokio::time::advance(super::PONG_TIMEOUT).await;
        tokio::select! {
            _ = heartbeat.wait() => panic!("a received pong must clear the deadline"),
            () = tokio::time::sleep(Duration::from_millis(1)) => {}
        }
    }
}
