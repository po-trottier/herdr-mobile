//! Structured JSON logging to stdout, restricted to exactly the field allow list in
//! `docs/12-relay-hosting.md` R-12-041 (`docs/41-code-standards.md` R-41-030 to
//! R-41-035 — the highest-stakes section in this crate).
//!
//! A generic `tracing-subscriber` JSON formatter would also print `target`, `level`,
//! `span` and a `message` field, none of which R-12-041 allows, and
//! `tracing-subscriber` is not a workspace-pinned dependency. Rather than add it and
//! then fight its defaults, this module installs a small hand-rolled
//! [`tracing::Subscriber`] whose [`RelaySubscriber::event`] serializes only the eight
//! named optional fields into [`LogLine`], so the schema is enforced by the compiler
//! (the struct has no field for anything else) rather than by a runtime filter.

use std::sync::Once;
use std::sync::atomic::{AtomicBool, Ordering};

use serde::Serialize;
use tracing::field::{Field, Visit};
use tracing::{Event, Metadata, Subscriber, span};

static LOG_ENABLED: AtomicBool = AtomicBool::new(true);
static INIT: Once = Once::new();

/// Installs the process-wide subscriber the first time it is called; every later
/// call only updates whether logging is enabled. `enabled` is
/// `HERDR_RELAY_LOG_JSON` (R-14-014); the wire format is always JSON when enabled
/// (R-12-040) — there is no alternate plaintext mode to configure.
pub(crate) fn init(enabled: bool) {
    LOG_ENABLED.store(enabled, Ordering::Relaxed);
    INIT.call_once(|| {
        // A second `set_global_default` call from another test binary in the same
        // process would error; every other caller only wants `LOG_ENABLED` updated,
        // which the store above already did, so a failed install here is fine.
        let _ = tracing::subscriber::set_global_default(RelaySubscriber);
    });
}

/// One `docs/12-relay-hosting.md` R-12-041 log line. Every field but `ts` and
/// `event` is optional and omitted when absent, so the JSON object never carries a
/// field the event kind does not define.
#[derive(Debug, Serialize)]
struct LogLine {
    ts: String,
    event: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    handle_first_6: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    peer: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    active_handles: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    frames_forwarded: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    bytes_forwarded: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    duration_ms: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error_code: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error_message: Option<String>,
}

#[derive(Default)]
struct FieldCollector {
    event: Option<String>,
    handle_first_6: Option<String>,
    peer: Option<String>,
    active_handles: Option<u64>,
    frames_forwarded: Option<u64>,
    bytes_forwarded: Option<u64>,
    duration_ms: Option<u64>,
    error_code: Option<String>,
    error_message: Option<String>,
}

impl Visit for FieldCollector {
    fn record_u64(&mut self, field: &Field, value: u64) {
        match field.name() {
            "active_handles" => self.active_handles = Some(value),
            "frames_forwarded" => self.frames_forwarded = Some(value),
            "bytes_forwarded" => self.bytes_forwarded = Some(value),
            "duration_ms" => self.duration_ms = Some(value),
            _ => {}
        }
    }

    fn record_i64(&mut self, field: &Field, value: i64) {
        if let Ok(value) = u64::try_from(value) {
            self.record_u64(field, value);
        }
    }

    fn record_str(&mut self, field: &Field, value: &str) {
        match field.name() {
            "event" => self.event = Some(value.to_owned()),
            "handle_first_6" => self.handle_first_6 = Some(value.to_owned()),
            "peer" => self.peer = Some(value.to_owned()),
            "error_code" => self.error_code = Some(value.to_owned()),
            "error_message" => self.error_message = Some(truncate(value, 256)),
            _ => {}
        }
    }

    fn record_debug(&mut self, field: &Field, value: &dyn std::fmt::Debug) {
        // Every call site in this crate passes a typed value that routes through one
        // of the methods above; this only guards a future call site that forgets to.
        self.record_str(field, &format!("{value:?}"));
    }
}

/// Truncates to at most `max_bytes` bytes on a UTF-8 boundary (R-12-041
/// `error_message`: "at most 256 characters").
fn truncate(s: &str, max_bytes: usize) -> String {
    if s.len() <= max_bytes {
        return s.to_owned();
    }
    let mut end = max_bytes;
    while !s.is_char_boundary(end) {
        end -= 1;
    }
    s[..end].to_owned()
}

struct RelaySubscriber;

impl Subscriber for RelaySubscriber {
    fn enabled(&self, _metadata: &Metadata<'_>) -> bool {
        LOG_ENABLED.load(Ordering::Relaxed)
    }

    fn new_span(&self, _span: &span::Attributes<'_>) -> span::Id {
        // This crate never opens a span, only events, so any span id is fine.
        span::Id::from_u64(1)
    }

    fn record(&self, _span: &span::Id, _values: &span::Record<'_>) {}
    fn record_follows_from(&self, _span: &span::Id, _follows: &span::Id) {}
    fn enter(&self, _span: &span::Id) {}
    fn exit(&self, _span: &span::Id) {}

    fn event(&self, event: &Event<'_>) {
        if !LOG_ENABLED.load(Ordering::Relaxed) {
            return;
        }
        let mut fields = FieldCollector::default();
        event.record(&mut fields);
        let Some(kind) = fields.event else { return };
        let line = LogLine {
            ts: iso8601_now(),
            event: kind,
            handle_first_6: fields.handle_first_6,
            peer: fields.peer,
            active_handles: fields.active_handles,
            frames_forwarded: fields.frames_forwarded,
            bytes_forwarded: fields.bytes_forwarded,
            duration_ms: fields.duration_ms,
            error_code: fields.error_code,
            error_message: fields.error_message,
        };
        if let Ok(json) = serde_json::to_string(&line) {
            println!("{json}");
        }
    }
}

/// ISO 8601 UTC timestamp with millisecond precision (R-12-041 `ts`). Hand-rolled on
/// `SystemTime` rather than pulling the workspace-pinned `time` crate's `macros` or
/// `parsing` features (not part of this crate's feature pin) or adding `chrono` (not
/// pinned anywhere in the repo): Howard Hinnant's `civil_from_days` is the standard,
/// well-tested algorithm for the one conversion this needs.
fn iso8601_now() -> String {
    let since_epoch = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default();
    format_iso8601(since_epoch.as_millis())
}

fn format_iso8601(millis_since_epoch: u128) -> String {
    let millis = millis_since_epoch as i64;
    let secs = millis.div_euclid(1000);
    let ms = millis.rem_euclid(1000);
    let days = secs.div_euclid(86_400);
    let secs_of_day = secs.rem_euclid(86_400);
    let (y, m, d) = civil_from_days(days);
    format!(
        "{y:04}-{m:02}-{d:02}T{:02}:{:02}:{:02}.{ms:03}Z",
        secs_of_day / 3600,
        (secs_of_day / 60) % 60,
        secs_of_day % 60,
    )
}

/// Howard Hinnant's `civil_from_days`: days since 1970-01-01 to a proleptic
/// Gregorian `(year, month, day)`. <https://howardhinnant.github.io/date_algorithms.html>
fn civil_from_days(z: i64) -> (i64, u32, u32) {
    let z = z + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097) as u64;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe as i64 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    (if m <= 2 { y + 1 } else { y }, m, d)
}

/// `relay_started` (R-12-041): the process came up and the acceptor is about to
/// listen.
pub(crate) fn relay_started() {
    tracing::info!(event = "relay_started", active_handles = 0u64);
}

pub(crate) fn host_connected(handle_first_6: &str, active_handles: u64) {
    tracing::info!(
        event = "host_connected",
        handle_first_6,
        peer = "host",
        active_handles
    );
}

pub(crate) fn device_connected(handle_first_6: &str, active_handles: u64) {
    tracing::info!(
        event = "device_connected",
        handle_first_6,
        peer = "device",
        active_handles
    );
}

pub(crate) fn host_disconnected(
    handle_first_6: &str,
    active_handles: u64,
    frames_forwarded: u64,
    bytes_forwarded: u64,
    duration_ms: u64,
) {
    tracing::info!(
        event = "host_disconnected",
        handle_first_6,
        peer = "host",
        active_handles,
        frames_forwarded,
        bytes_forwarded,
        duration_ms,
    );
}

pub(crate) fn device_disconnected(
    handle_first_6: &str,
    active_handles: u64,
    frames_forwarded: u64,
    bytes_forwarded: u64,
    duration_ms: u64,
) {
    tracing::info!(
        event = "device_disconnected",
        handle_first_6,
        peer = "device",
        active_handles,
        frames_forwarded,
        bytes_forwarded,
        duration_ms,
    );
}

/// `handle_expired` (R-12-041): a room was discarded — either peer's connection
/// ended (R-11-125, R-12-008, R-12-009) — or a Device's pairing window (R-13-022,
/// 600 s) lapsed (R-11-120) before it joined.
pub(crate) fn handle_expired(handle_first_6: &str, active_handles: u64) {
    tracing::info!(event = "handle_expired", handle_first_6, active_handles);
}

/// `error` (R-12-041): the relay sent an R-11-116 error frame or a mid-session
/// close for a size/rate violation. `error_code` is one of the close-code names
/// from `docs/11-relay-protocol.md` (`herdr_relay_proto::codes::CloseCode::name`).
pub(crate) fn error(active_handles: u64, error_code: &str, error_message: &str) {
    tracing::error!(event = "error", active_handles, error_code, error_message);
}

#[cfg(test)]
mod tests {
    use super::format_iso8601;

    #[test]
    fn format_iso8601_matches_a_known_instant() {
        // 2024-01-02T03:04:05.678Z, computed independently via `date -u -d ... +%s`.
        assert_eq!(
            format_iso8601(1_704_164_645_678),
            "2024-01-02T03:04:05.678Z"
        );
    }

    #[test]
    fn format_iso8601_matches_the_epoch() {
        assert_eq!(format_iso8601(0), "1970-01-01T00:00:00.000Z");
    }

    #[test]
    fn error_event_is_reachable_and_does_not_panic() {
        super::error(
            3,
            "rate_limited",
            "an internal condition a person must act on",
        );
    }
}
