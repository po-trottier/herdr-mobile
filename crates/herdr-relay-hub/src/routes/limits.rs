//! Per-source-IP and per-connection rate limiting (`docs/12-relay-hosting.md`
//! R-12-031, R-12-032, R-12-033).

use std::collections::{HashMap, VecDeque};
use std::net::IpAddr;
use std::sync::{Mutex, PoisonError};
use std::time::{Duration, Instant};

const WINDOW: Duration = Duration::from_secs(1);

/// A sliding one-second window of allowed events per source IP address: the
/// connection-rate (R-12-031) and handle-registration-rate (R-12-033) limits share
/// this same shape, just with different `max_per_window` values and call sites.
///
/// ponytail: an IP that stops connecting keeps its (empty, near-zero-cost)
/// `VecDeque` entry forever — unbounded growth only if the relay sees unboundedly
/// many distinct source IPs over its lifetime. Add periodic pruning if that is ever
/// measured to matter; a public relay behind one reverse proxy sees a bounded set of
/// recent client IPs in practice.
pub(crate) struct IpRateLimiter {
    max_per_window: usize,
    seen: Mutex<HashMap<IpAddr, VecDeque<Instant>>>,
}

impl IpRateLimiter {
    pub(crate) fn new(max_per_window: usize) -> Self {
        Self {
            max_per_window,
            seen: Mutex::new(HashMap::new()),
        }
    }

    /// `true` when this call is inside the allowance for `ip`; also records the
    /// attempt so it counts against the next call's window.
    pub(crate) fn allow(&self, ip: IpAddr) -> bool {
        let now = Instant::now();
        let mut seen = self.seen.lock().unwrap_or_else(PoisonError::into_inner);
        let events = seen.entry(ip).or_default();
        while events
            .front()
            .is_some_and(|&t| now.duration_since(t) >= WINDOW)
        {
            events.pop_front();
        }
        if events.len() >= self.max_per_window {
            return false;
        }
        events.push_back(now);
        true
    }
}

/// One connection's rolling one-second inbound-frame counter (R-12-032). Lives on
/// the connection's own task; unlike [`IpRateLimiter`], it needs no lock.
pub(crate) struct FrameRateLimiter {
    max_per_window: usize,
    window_start: Instant,
    count: usize,
}

impl FrameRateLimiter {
    pub(crate) fn new(max_per_window: usize) -> Self {
        Self {
            max_per_window,
            window_start: Instant::now(),
            count: 0,
        }
    }

    /// `true` when this frame is inside the allowance; also counts it.
    pub(crate) fn allow(&mut self) -> bool {
        let now = Instant::now();
        if now.duration_since(self.window_start) >= WINDOW {
            self.window_start = now;
            self.count = 0;
        }
        self.count += 1;
        self.count <= self.max_per_window
    }
}

#[cfg(test)]
mod tests {
    use std::net::{IpAddr, Ipv4Addr};

    use super::{FrameRateLimiter, IpRateLimiter};

    const IP: IpAddr = IpAddr::V4(Ipv4Addr::LOCALHOST);

    #[test]
    fn ip_limiter_allows_up_to_the_limit_then_rejects() {
        let limiter = IpRateLimiter::new(3);
        assert!(limiter.allow(IP));
        assert!(limiter.allow(IP));
        assert!(limiter.allow(IP));
        assert!(!limiter.allow(IP));
    }

    #[test]
    fn ip_limiter_tracks_ips_independently() {
        let limiter = IpRateLimiter::new(1);
        assert!(limiter.allow(IP));
        assert!(!limiter.allow(IP));
        assert!(limiter.allow(IpAddr::V4(Ipv4Addr::new(10, 0, 0, 1))));
    }

    #[test]
    fn frame_limiter_allows_up_to_the_limit_then_rejects() {
        let mut limiter = FrameRateLimiter::new(2);
        assert!(limiter.allow());
        assert!(limiter.allow());
        assert!(!limiter.allow());
        assert!(!limiter.allow());
    }
}
