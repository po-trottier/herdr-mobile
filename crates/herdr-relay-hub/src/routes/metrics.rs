//! The seven Prometheus metrics `/metrics` exposes (`docs/12-relay-hosting.md`
//! R-12-050). Every counter and gauge is a plain atomic; the label sets are the
//! small, fixed ones the doc names, so a match on a known enum replaces a
//! `HashMap<String, _>` and needs no lock, and no attacker-controlled string ever
//! becomes a label (R-12-041's "never log a handle, an IP or payload content"
//! applies to metric labels too, per R-12-024).

use std::fmt::Write as _;
use std::sync::atomic::{AtomicU64, Ordering};

use herdr_relay_proto::codes::CloseCode;

use crate::session::Role;

/// R-12-050's histogram bucket boundaries, in seconds, cumulative (`_bucket{le=...}`).
const DURATION_BUCKETS_SECS: [u64; 10] = [1, 5, 15, 30, 60, 120, 300, 600, 1800, 3600];

/// The nine [`CloseCode`] variants that carry a relay-defined name, in the fixed
/// order `errors_total` renders them (R-12-050 `code` label).
const NAMED_CLOSE_CODES: [CloseCode; 9] = [
    CloseCode::PairingExpired,
    CloseCode::HandleUnknown,
    CloseCode::HandleTaken,
    CloseCode::ProtocolError,
    CloseCode::Revoked,
    CloseCode::HandshakeFailed,
    CloseCode::HostInUse,
    CloseCode::FrameTooLarge,
    CloseCode::RateLimited,
];

/// `connections_rejected_total`'s four named reasons (R-12-050 `reason` label).
#[derive(Debug, Clone, Copy)]
pub(crate) enum RejectReason {
    RateLimited,
    HandleMalformed,
    HandleTaken,
    HostInUse,
}

const REJECT_REASONS: [RejectReason; 4] = [
    RejectReason::RateLimited,
    RejectReason::HandleMalformed,
    RejectReason::HandleTaken,
    RejectReason::HostInUse,
];

impl RejectReason {
    const fn label(self) -> &'static str {
        match self {
            Self::RateLimited => "rate_limited",
            Self::HandleMalformed => "handle_malformed",
            Self::HandleTaken => "handle_taken",
            Self::HostInUse => "host_in_use",
        }
    }

    const fn index(self) -> usize {
        match self {
            Self::RateLimited => 0,
            Self::HandleMalformed => 1,
            Self::HandleTaken => 2,
            Self::HostInUse => 3,
        }
    }
}

fn close_code_index(code: CloseCode) -> Option<usize> {
    Some(match code {
        CloseCode::PairingExpired => 0,
        CloseCode::HandleUnknown => 1,
        CloseCode::HandleTaken => 2,
        CloseCode::ProtocolError => 3,
        CloseCode::Revoked => 4,
        CloseCode::HandshakeFailed => 5,
        CloseCode::HostInUse => 6,
        CloseCode::FrameTooLarge => 7,
        CloseCode::RateLimited => 8,
        CloseCode::Normal
        | CloseCode::GoingAway
        | CloseCode::Abnormal
        | CloseCode::InternalError => {
            return None;
        }
    })
}

fn direction_index(sender: Role) -> usize {
    match sender {
        Role::Host => 0,
        Role::Device => 1,
    }
}

fn direction_label(index: usize) -> &'static str {
    match index {
        0 => "host_to_device",
        _ => "device_to_host",
    }
}

/// The relay's whole metric state (`docs/12-relay-hosting.md` R-12-050).
/// `handles_active` is not stored here: it is read straight from [`super::session::SessionMap`]
/// at scrape time, so there is exactly one place that counts active handles.
pub(crate) struct Metrics {
    handles_total: AtomicU64,
    frames_forwarded: [AtomicU64; 2],
    bytes_forwarded: [AtomicU64; 2],
    duration_buckets: [AtomicU64; 10],
    duration_sum_ms: AtomicU64,
    duration_count: AtomicU64,
    errors_total: [AtomicU64; 9],
    connections_rejected_total: [AtomicU64; 4],
}

impl Metrics {
    pub(crate) fn new() -> Self {
        Self {
            handles_total: AtomicU64::new(0),
            frames_forwarded: Default::default(),
            bytes_forwarded: Default::default(),
            duration_buckets: Default::default(),
            duration_sum_ms: AtomicU64::new(0),
            duration_count: AtomicU64::new(0),
            errors_total: Default::default(),
            connections_rejected_total: Default::default(),
        }
    }

    pub(crate) fn record_handle_created(&self) {
        self.handles_total.fetch_add(1, Ordering::Relaxed);
    }

    pub(crate) fn record_forward(&self, sender: Role, bytes: usize) {
        let i = direction_index(sender);
        self.frames_forwarded[i].fetch_add(1, Ordering::Relaxed);
        self.bytes_forwarded[i].fetch_add(bytes as u64, Ordering::Relaxed);
    }

    pub(crate) fn record_session_duration(&self, duration_ms: u64) {
        let secs = duration_ms / 1000;
        for (bucket, &boundary) in self.duration_buckets.iter().zip(&DURATION_BUCKETS_SECS) {
            if secs <= boundary {
                bucket.fetch_add(1, Ordering::Relaxed);
            }
        }
        self.duration_sum_ms
            .fetch_add(duration_ms, Ordering::Relaxed);
        self.duration_count.fetch_add(1, Ordering::Relaxed);
    }

    pub(crate) fn record_error(&self, code: CloseCode) {
        if let Some(i) = close_code_index(code) {
            self.errors_total[i].fetch_add(1, Ordering::Relaxed);
        }
    }

    pub(crate) fn record_rejected(&self, reason: RejectReason) {
        self.connections_rejected_total[reason.index()].fetch_add(1, Ordering::Relaxed);
    }

    /// Renders the full Prometheus text exposition body (R-12-050, R-12-011).
    pub(crate) fn render(&self, active_handles: usize) -> String {
        let mut out = String::new();
        push_gauge(
            &mut out,
            "herdr_relay_handles_active",
            "Current active handle registrations",
            active_handles as u64,
        );
        push_counter(
            &mut out,
            "herdr_relay_handles_total",
            "Total handle registrations since start",
            self.handles_total.load(Ordering::Relaxed),
        );
        push_labeled_counter(
            &mut out,
            "herdr_relay_frames_forwarded_total",
            "Total frames relayed",
            "direction",
            (0..2).map(|i| {
                (
                    direction_label(i),
                    self.frames_forwarded[i].load(Ordering::Relaxed),
                )
            }),
        );
        push_labeled_counter(
            &mut out,
            "herdr_relay_bytes_forwarded_total",
            "Total bytes relayed",
            "direction",
            (0..2).map(|i| {
                (
                    direction_label(i),
                    self.bytes_forwarded[i].load(Ordering::Relaxed),
                )
            }),
        );
        push_histogram(&mut out, self);
        push_labeled_counter(
            &mut out,
            "herdr_relay_errors_total",
            "Error count by type",
            "code",
            NAMED_CLOSE_CODES.iter().enumerate().map(|(i, code)| {
                (
                    code.name().unwrap_or(""),
                    self.errors_total[i].load(Ordering::Relaxed),
                )
            }),
        );
        push_labeled_counter(
            &mut out,
            "herdr_relay_connections_rejected_total",
            "Rejected connection count",
            "reason",
            REJECT_REASONS.iter().map(|&reason| {
                (
                    reason.label(),
                    self.connections_rejected_total[reason.index()].load(Ordering::Relaxed),
                )
            }),
        );
        out
    }
}

fn push_gauge(out: &mut String, name: &str, help: &str, value: u64) {
    let _ = writeln!(out, "# HELP {name} {help}");
    let _ = writeln!(out, "# TYPE {name} gauge");
    let _ = writeln!(out, "{name} {value}");
}

fn push_counter(out: &mut String, name: &str, help: &str, value: u64) {
    let _ = writeln!(out, "# HELP {name} {help}");
    let _ = writeln!(out, "# TYPE {name} counter");
    let _ = writeln!(out, "{name} {value}");
}

fn push_labeled_counter<'a>(
    out: &mut String,
    name: &str,
    help: &str,
    label: &str,
    values: impl Iterator<Item = (&'a str, u64)>,
) {
    let _ = writeln!(out, "# HELP {name} {help}");
    let _ = writeln!(out, "# TYPE {name} counter");
    for (value_label, count) in values {
        let _ = writeln!(out, "{name}{{{label}=\"{value_label}\"}} {count}");
    }
}

fn push_histogram(out: &mut String, metrics: &Metrics) {
    const NAME: &str = "herdr_relay_session_duration_seconds";
    let _ = writeln!(out, "# HELP {NAME} Session lifetime");
    let _ = writeln!(out, "# TYPE {NAME} histogram");
    let mut cumulative = 0u64;
    for (&boundary, bucket) in DURATION_BUCKETS_SECS.iter().zip(&metrics.duration_buckets) {
        cumulative += bucket.load(Ordering::Relaxed);
        let _ = writeln!(out, "{NAME}_bucket{{le=\"{boundary}\"}} {cumulative}");
    }
    let count = metrics.duration_count.load(Ordering::Relaxed);
    let _ = writeln!(out, "{NAME}_bucket{{le=\"+Inf\"}} {count}");
    let sum_secs = metrics.duration_sum_ms.load(Ordering::Relaxed) as f64 / 1000.0;
    let _ = writeln!(out, "{NAME}_sum {sum_secs}");
    let _ = writeln!(out, "{NAME}_count {count}");
}

#[cfg(test)]
mod tests {
    use herdr_relay_proto::codes::CloseCode;

    use super::{Metrics, RejectReason};
    use crate::session::Role;

    /// The Prometheus text exposition format and every metric name `/metrics`
    /// MUST expose (R-12-011, R-12-015, R-12-050).
    #[test]
    fn render_includes_every_r_12_050_metric_name() {
        let metrics = Metrics::new();
        metrics.record_handle_created();
        metrics.record_forward(Role::Host, 10);
        metrics.record_session_duration(2_500);
        metrics.record_error(CloseCode::RateLimited);
        metrics.record_rejected(RejectReason::RateLimited);
        let body = metrics.render(1);
        for name in [
            "herdr_relay_handles_active",
            "herdr_relay_handles_total",
            "herdr_relay_frames_forwarded_total",
            "herdr_relay_bytes_forwarded_total",
            "herdr_relay_session_duration_seconds",
            "herdr_relay_errors_total",
            "herdr_relay_connections_rejected_total",
        ] {
            assert!(body.contains(name), "missing metric {name} in:\n{body}");
        }
        assert!(body.contains("herdr_relay_handles_active 1"));
        assert!(body.contains(r#"direction="host_to_device"#));
        assert!(body.contains(r#"code="rate_limited"#));
        assert!(body.contains(r#"reason="rate_limited"#));
    }
}
