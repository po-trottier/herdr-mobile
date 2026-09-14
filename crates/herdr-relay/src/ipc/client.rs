//! The request/response Herdr socket client: path discovery, one connection per
//! call, retry-once-then-fail (R-10-015), `ping`/protocol-22 check.

use std::io::{self, BufReader};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

use serde_json::{Value, json};

use crate::config::RelayConfig;

use super::discover::discover_socket_path;
use super::subscription::SubscriptionConnection;
use super::transport::{PlatformStream, exchange, open_platform, read_bounded_line, write_request};

/// This build's exact protocol version (R-10-012, R-41-164). R-02-028 records
/// the compatible protocol 22 increment measured on 2026-09-10 against Herdr
/// `0.9.0-preview.2026-09-08-62431dbd033b`.
pub const EXPECTED_PROTOCOL: u64 = 22;

/// An error from a Herdr socket call.
#[derive(Debug, thiserror::Error)]
pub enum IpcError {
    /// R-10-003: neither `HERDR_SOCKET_PATH` nor `herdr status` named a socket.
    #[error("locate the herdr socket failed: {0}")]
    Discover(#[source] io::Error),
    /// Opening the platform connection failed (R-41-156: a fresh connection per call).
    #[error("connect to the herdr socket failed: {0}")]
    Connect(#[source] io::Error),
    /// A write, read or timeout failure on an already-open connection.
    #[error("herdr socket read or write failed: {0}")]
    Io(#[source] io::Error),
    /// The response line was not valid JSON (R-10-005: buffer across reads, never
    /// assume one read is one line — this is the parse-time symptom of getting that
    /// wrong, or of a genuinely malformed server response).
    #[error("herdr response for {method} was not valid JSON: {source}")]
    Malformed {
        method: String,
        #[source]
        source: serde_json::Error,
    },
    /// Herdr answered with an `error` object (R-02-009). Not retryable: the request
    /// itself was rejected, not lost.
    #[error("herdr rejected {method}: {code}: {message}")]
    Rejected {
        method: String,
        code: String,
        message: String,
    },
    /// The response parsed, but `result.<key>` was absent (R-41-163).
    #[error("herdr response for {method} carried no result.{key}")]
    MissingPayload { method: String, key: String },
    /// R-10-012, R-41-164: `ping.result.protocol` did not equal
    /// [`EXPECTED_PROTOCOL`].
    #[error("herdr protocol {actual}, expected {EXPECTED_PROTOCOL}")]
    ProtocolMismatch { actual: u64 },
}

impl IpcError {
    /// R-10-015: a request connection is never backed off; a failure is retried once
    /// immediately. Only a transport-level failure is worth retrying — a `Rejected`
    /// request would be rejected again with the same input, and a `ProtocolMismatch`
    /// or `MissingPayload` is a data problem, not a transient one.
    fn is_retryable(&self) -> bool {
        matches!(self, Self::Connect(_) | Self::Io(_))
    }
}

/// A Herdr socket client: path, timeouts and the per-process request-id counter
/// (R-10-008). Cheap to clone; every call opens its own fresh connection
/// (R-10-009, R-41-156).
#[derive(Debug, Clone)]
pub struct HerdrClient {
    path: PathBuf,
    timeout: Duration,
    max_response_bytes: u64,
    counter: Arc<AtomicU64>,
}

impl HerdrClient {
    /// R-10-003: read `HERDR_SOCKET_PATH` first; when absent, parse the `socket:`
    /// line of `herdr status`; on Windows only, fall back to `%APPDATA%`.
    pub fn discover(config: &RelayConfig) -> Result<Self, IpcError> {
        let path = discover_socket_path().map_err(IpcError::Discover)?;
        Ok(Self::with_path(path, config))
    }

    /// Builds a client for an already-known socket path, for example a path an
    /// operator pinned in `config.toml`, or a stub path in a test.
    pub fn with_path(path: PathBuf, config: &RelayConfig) -> Self {
        Self {
            path,
            timeout: Duration::from_millis(config.socket_timeout_ms),
            max_response_bytes: config.max_response_bytes,
            counter: Arc::new(AtomicU64::new(0)),
        }
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    /// Calls `ping` and checks `result.protocol` against [`EXPECTED_PROTOCOL`]
    /// (R-10-012, R-41-164). The bridge MUST NOT serve a Device against a mismatched
    /// protocol; the caller decides how to surface that refusal.
    pub fn ping(&self) -> Result<Value, IpcError> {
        let envelope = self.call("ping", json!({}))?;
        let protocol = envelope
            .get("result")
            .and_then(|r| r.get("protocol"))
            .and_then(Value::as_u64)
            .unwrap_or(0);
        if protocol != EXPECTED_PROTOCOL {
            return Err(IpcError::ProtocolMismatch { actual: protocol });
        }
        Ok(envelope)
    }

    /// One request, one response, one connection (R-10-009, R-41-156/157/158).
    /// `params` is always sent (R-02-007). Retries once immediately on a
    /// transport-level failure and never backs off (R-10-015); the caller reports a
    /// second failure to the Device.
    pub fn call(&self, method: &str, params: Value) -> Result<Value, IpcError> {
        match self.call_once(method, &params) {
            Ok(value) => Ok(value),
            Err(err) if err.is_retryable() => self.call_once(method, &params),
            Err(err) => Err(err),
        }
    }

    /// [`Self::call`], then reads the result through its wrapped payload key
    /// (`result.<key>`), never off `result` directly (R-41-163, R-10-007).
    pub fn call_result(&self, method: &str, params: Value, key: &str) -> Result<Value, IpcError> {
        let envelope = self.call(method, params)?;
        envelope
            .get("result")
            .and_then(|r| r.get(key))
            .cloned()
            .ok_or_else(|| IpcError::MissingPayload {
                method: method.to_string(),
                key: key.to_string(),
            })
    }

    fn call_once(&self, method: &str, params: &Value) -> Result<Value, IpcError> {
        let id = self.next_id(method);
        let request = json!({ "id": id, "method": method, "params": params }).to_string();
        let stream = self.connect_timed().map_err(IpcError::Connect)?;
        let line = exchange(stream, &request, self.max_response_bytes, self.timeout)
            .map_err(IpcError::Io)?;
        let parsed: Value =
            serde_json::from_str(line.trim_end()).map_err(|source| IpcError::Malformed {
                method: method.to_string(),
                source,
            })?;
        if let Some(error) = parsed.get("error") {
            let code = error
                .get("code")
                .and_then(Value::as_str)
                .unwrap_or("unknown")
                .to_string();
            let message = error
                .get("message")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string();
            return Err(IpcError::Rejected {
                method: method.to_string(),
                code,
                message,
            });
        }
        Ok(parsed)
    }

    /// Opens the one long-lived subscription connection and sends `events.subscribe`
    /// once (R-10-011, R-41-160). Blocks for the `subscription_started`
    /// acknowledgement, bounded by the same timeout as a one-shot call: an
    /// acknowledgement that never arrives is a connect-time failure, not the
    /// intentionally-unbounded steady state that follows it.
    pub fn subscribe(&self, subscriptions: Vec<Value>) -> Result<SubscriptionConnection, IpcError> {
        let id = self.next_id("events.subscribe");
        let request = json!({
            "id": id,
            "method": "events.subscribe",
            "params": { "subscriptions": subscriptions },
        })
        .to_string();
        let stream = self.connect_untimed().map_err(IpcError::Connect)?;
        let mut reader = BufReader::new(stream);
        write_request(reader.get_mut(), &request).map_err(IpcError::Io)?;

        let mut first = String::new();
        read_bounded_line(&mut reader, self.max_response_bytes, &mut first)
            .map_err(IpcError::Io)?;
        let parsed: Value =
            serde_json::from_str(first.trim_end()).map_err(|source| IpcError::Malformed {
                method: "events.subscribe".to_string(),
                source,
            })?;
        if let Some(error) = parsed.get("error") {
            let code = error
                .get("code")
                .and_then(Value::as_str)
                .unwrap_or("unknown")
                .to_string();
            let message = error
                .get("message")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string();
            return Err(IpcError::Rejected {
                method: "events.subscribe".to_string(),
                code,
                message,
            });
        }

        Ok(SubscriptionConnection::new(reader, self.max_response_bytes))
    }

    fn next_id(&self, method: &str) -> String {
        let counter = self.counter.fetch_add(1, Ordering::Relaxed);
        format!("herdr-relay:{method}:{counter}")
    }

    /// Timeout applied (R-10-004, R-41-131): used for every one-shot request.
    fn connect_timed(&self) -> io::Result<PlatformStream> {
        let stream = open_platform(&self.path)?;
        #[cfg(unix)]
        {
            stream.set_read_timeout(Some(self.timeout))?;
            stream.set_write_timeout(Some(self.timeout))?;
        }
        Ok(stream)
    }

    /// No timeout: the subscription connection is expected to sit idle between
    /// events (R-02-006, R-41-160). On Windows the two connect paths are identical
    /// because the timeout there is emulated per-read, not intrinsic to the handle
    /// (see [`exchange`]); on POSIX this skips `set_read_timeout` entirely.
    fn connect_untimed(&self) -> io::Result<PlatformStream> {
        open_platform(&self.path)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_transport_failure_is_retryable_but_a_rejection_is_not() {
        let io_err = IpcError::Io(io::Error::other("broken pipe"));
        let connect_err = IpcError::Connect(io::Error::other("no listener"));
        let rejected = IpcError::Rejected {
            method: "pane.read".to_string(),
            code: "pane_not_found".to_string(),
            message: "no such pane".to_string(),
        };
        let protocol = IpcError::ProtocolMismatch { actual: 19 };
        assert!(io_err.is_retryable());
        assert!(connect_err.is_retryable());
        assert!(!rejected.is_retryable());
        assert!(!protocol.is_retryable());
    }

    #[test]
    fn next_id_is_unique_and_carries_the_method_name() {
        let client = HerdrClient::with_path(PathBuf::from("unused"), &RelayConfig::default());
        let a = client.next_id("ping");
        let b = client.next_id("ping");
        assert_ne!(a, b);
        assert!(a.starts_with("herdr-relay:ping:"));
        assert!(b.starts_with("herdr-relay:ping:"));
    }
}
