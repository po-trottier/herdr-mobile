//! Phase 1 SPIKE A: prove the Herdr socket subscription channel is real and holds for real time.
//!
//! `docs/90-implementation-plan.md` Phase 1 owns this file. It holds one long-lived `pane.updated`
//! plus `pane.agent_status_changed` subscription for 60 seconds, prints `pane_id` and `revision`
//! from `data.pane` on every push, and measures the events-per-second rate. `docs/02-herdr-probe-
//! results.md` R-02-013 measured about 9.8 events/s on an idle machine with no server-side filter;
//! this binary re-measures that live rather than assuming it.
//!
//! Read-only. This binary MUST NOT close a pane, stop the server, or mutate layout it did not
//! create (R-40-030). It calls `ping` once, then `events.subscribe`, and sends no further request
//! on the subscription connection (R-02-006, R-10-011).
//!
//! `crates/herdr-relay/src/ipc.rs` and `src/watch.rs` are owned by `WP-6` through the
//! `INT-6-bridge` integration step (`docs/90-implementation-plan.md` §5.3), not by this phase, so
//! the socket-client logic below is self-contained in this bin target rather than split into a
//! shared module. WP-6 folds these findings in when it builds the production client.

use std::env;
use std::io::{self, BufRead, BufReader, Read, Write};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::mpsc;
use std::time::{Duration, Instant};

use serde_json::{Value, json};

/// Matches `IPC_TIMEOUT` in the reference client, `ipc.rs:22` (R-10-004). Applies only to the
/// one-shot `ping` connection; the subscription connection has no per-read timeout because it is
/// expected to sit idle between events (R-02-006).
const IPC_TIMEOUT: Duration = Duration::from_secs(5);

/// Matches `MAX_RESPONSE_BYTES` in the reference client, `ipc.rs:26` (R-10-004). Checked per line
/// on the subscription connection too, so a runaway push cannot grow this process without bound.
const MAX_RESPONSE_BYTES: usize = 4 * 1024 * 1024;

/// See the matching constant and comment in `spike-read.rs` (R-10-012, R-41-164): the docs were
/// re-measured 2026-09-02 against Herdr `0.8.2-preview.2026-08-31-b1ff4582e968`, superseding the
/// 2026-08-27 probe that pinned `20` and the original 2026-08-04 probe that pinned `19`.
const EXPECTED_PROTOCOL: u64 = 21;

const SUBSCRIBE_DURATION: Duration = Duration::from_secs(60);

fn main() {
    if let Err(err) = run() {
        eprintln!("herdr-relay: {err}");
        std::process::exit(1);
    }
}

fn run() -> io::Result<()> {
    let path = socket_path()?;
    let agent_status_pane_id = env::args().nth(1);

    // Ping on its own fresh connection first (R-10-011): the subscription connection below
    // answers no further request once it starts streaming (R-02-006).
    let ping = call(&path, "ping", json!({}), 0)?;
    let protocol = ping["result"]["protocol"].as_u64().unwrap_or(0);
    if protocol != EXPECTED_PROTOCOL {
        return Err(io::Error::other(format!(
            "protocol {protocol}, expected {EXPECTED_PROTOCOL}"
        )));
    }

    let (tx, rx) = mpsc::channel::<io::Result<String>>();
    let reader_path = path.clone();
    let reader_pane_id = agent_status_pane_id.clone();
    std::thread::spawn(move || subscribe_reader(&reader_path, reader_pane_id.as_deref(), tx));

    match &agent_status_pane_id {
        Some(pane_id) => println!(
            "subscribed for {}s to pane.updated (all panes) and pane.agent_status_changed ({pane_id})",
            SUBSCRIBE_DURATION.as_secs()
        ),
        None => println!(
            "subscribed for {}s to pane.updated (all panes); pass a pane_id argument to also watch pane.agent_status_changed",
            SUBSCRIBE_DURATION.as_secs()
        ),
    }

    let start = Instant::now();
    let mut total_events: u64 = 0;
    let mut disconnected_early: Option<String> = None;

    loop {
        let elapsed = start.elapsed();
        if elapsed >= SUBSCRIBE_DURATION {
            break;
        }
        let remaining = SUBSCRIBE_DURATION - elapsed;
        let poll = remaining.min(Duration::from_millis(500));
        match rx.recv_timeout(poll) {
            Ok(Ok(line)) => {
                if handle_line(&line) == Some(LineKind::Event) {
                    total_events += 1;
                }
            }
            Ok(Err(e)) => {
                disconnected_early = Some(e.to_string());
                break;
            }
            Err(mpsc::RecvTimeoutError::Timeout) => {}
            Err(mpsc::RecvTimeoutError::Disconnected) => {
                disconnected_early = Some("subscription connection closed with no error".into());
                break;
            }
        }
    }

    let elapsed_secs = start.elapsed().as_secs_f64();
    let rate = if elapsed_secs > 0.0 {
        total_events as f64 / elapsed_secs
    } else {
        0.0
    };

    match disconnected_early {
        Some(reason) => {
            eprintln!(
                "herdr-relay: subscription ended after {elapsed_secs:.1}s (before the {}s budget): {reason}",
                SUBSCRIBE_DURATION.as_secs()
            );
            eprintln!("events observed: {total_events} ({rate:.2}/s)");
            Err(io::Error::other("subscription connection dropped early"))
        }
        None => {
            println!(
                "ran the full {}s with no disconnect: {total_events} events ({rate:.2}/s)",
                SUBSCRIBE_DURATION.as_secs()
            );
            Ok(())
        }
    }
}

#[derive(PartialEq, Eq)]
enum LineKind {
    SubscriptionStarted,
    Event,
    Other,
}

/// Prints `pane_id` and `revision` from `data.pane` for a `pane.updated` or
/// `pane.agent_status_changed` push (R-02-011, R-10-020). Returns what kind of line this was, so
/// the caller counts only real events.
fn handle_line(line: &str) -> Option<LineKind> {
    let parsed: Value = match serde_json::from_str(line.trim_end()) {
        Ok(v) => v,
        Err(e) => {
            eprintln!("herdr-relay: malformed subscription line: {e}");
            return Some(LineKind::Other);
        }
    };

    if parsed["result"]["type"] == "subscription_started" {
        println!("subscription_started");
        return Some(LineKind::SubscriptionStarted);
    }

    if let Some(event) = parsed["event"].as_str() {
        let pane = &parsed["data"]["pane"];
        match (pane["pane_id"].as_str(), pane["revision"].as_u64()) {
            (Some(pane_id), Some(revision)) => {
                println!("event={event} pane_id={pane_id} revision={revision}");
            }
            _ => println!("event={event} (no data.pane on this push)"),
        }
        return Some(LineKind::Event);
    }

    eprintln!("herdr-relay: unrecognised subscription line: {line}");
    Some(LineKind::Other)
}

/// Opens the one long-lived subscription connection, writes `events.subscribe` once, and forwards
/// every subsequent line to `tx`. Never writes a second request on this connection (R-02-006,
/// R-41-161).
///
/// `pane.agent_status_changed` requires its own `pane_id` in the subscription entry (measured live
/// against protocol 21: an entry with only `{"type":"pane.agent_status_changed"}` returns
/// `invalid_request: missing field 'pane_id'`), unlike `pane.updated`, which has no filter at all
/// (R-02-013). So this subscribes to `pane.agent_status_changed` only when a target pane was given
/// on the command line.
fn subscribe_reader(
    path: &Path,
    agent_status_pane_id: Option<&str>,
    tx: mpsc::Sender<io::Result<String>>,
) {
    let result = (|| -> io::Result<()> {
        let mut subscriptions = vec![json!({ "type": "pane.updated" })];
        if let Some(pane_id) = agent_status_pane_id {
            subscriptions.push(json!({ "type": "pane.agent_status_changed", "pane_id": pane_id }));
        }
        let request = json!({
            "id": "herdr-relay:events.subscribe:0",
            "method": "events.subscribe",
            "params": { "subscriptions": subscriptions },
        })
        .to_string();

        let mut reader = BufReader::new(open_subscription(path)?);

        // The first write is the only write this connection ever makes.
        reader.get_mut().write_all(request.as_bytes())?;
        reader.get_mut().write_all(b"\n")?;
        reader.get_mut().flush()?;

        loop {
            let mut line = String::new();
            let read = reader.read_line(&mut line)?;
            if read == 0 {
                return Ok(()); // server half-closed the connection
            }
            if line.len() > MAX_RESPONSE_BYTES {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    "subscription line exceeded the 4 MiB cap",
                ));
            }
            if tx.send(Ok(line)).is_err() {
                return Ok(()); // main thread stopped listening
            }
        }
    })();
    if let Err(e) = result {
        let _ = tx.send(Err(e));
    }
}

#[cfg(windows)]
fn open_subscription(path: &Path) -> io::Result<std::fs::File> {
    let pipe = format!(r"\\.\pipe\{}", path.display());
    std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .open(pipe)
}

#[cfg(unix)]
fn open_subscription(path: &Path) -> io::Result<std::os::unix::net::UnixStream> {
    std::os::unix::net::UnixStream::connect(path)
}

/// R-10-003: read `HERDR_SOCKET_PATH` first. When absent, parse the `socket:` line of
/// `herdr status`. Windows falls back to `%APPDATA%`, matching the reference client
/// (`ipc.rs:30-43`) and `docs/10-herdr-integration.md` §1.5.
fn socket_path() -> io::Result<PathBuf> {
    if let Some(path) = env::var_os("HERDR_SOCKET_PATH") {
        return Ok(PathBuf::from(path));
    }

    let status = Command::new("herdr").arg("status").output()?;
    let stdout = String::from_utf8_lossy(&status.stdout);
    if let Some(reported) = parse_socket_line(&stdout) {
        return Ok(PathBuf::from(reported));
    }

    #[cfg(windows)]
    {
        if let Some(appdata) = env::var_os("APPDATA") {
            return Ok(PathBuf::from(appdata).join("herdr").join("herdr.sock"));
        }
    }

    Err(io::Error::new(
        io::ErrorKind::NotFound,
        "no herdr socket path: HERDR_SOCKET_PATH unset and `herdr status` reported none",
    ))
}

fn parse_socket_line(status_output: &str) -> Option<String> {
    status_output.lines().find_map(|line| {
        line.trim()
            .strip_prefix("socket:")
            .map(|v| v.trim().to_string())
    })
}

/// One request, one response, one connection (R-10-009, R-02-004), used only for the `ping`
/// preflight. Sends `params` always (R-02-007) and formats `id` as `herdr-relay:<method>:<counter>`
/// (R-10-008).
fn call(path: &Path, method: &str, params: Value, counter: u64) -> io::Result<Value> {
    let id = format!("herdr-relay:{method}:{counter}");
    let request = json!({ "id": id, "method": method, "params": params }).to_string();
    let line = roundtrip(path, &request)?;
    let parsed: Value = serde_json::from_str(line.trim_end()).map_err(|e| {
        io::Error::new(
            io::ErrorKind::InvalidData,
            format!("malformed response for {method}: {e}"),
        )
    })?;
    if let Some(error) = parsed.get("error") {
        return Err(io::Error::other(format!("{method} failed: {error}")));
    }
    Ok(parsed)
}

#[cfg(windows)]
fn roundtrip(path: &Path, request: &str) -> io::Result<String> {
    let pipe = format!(r"\\.\pipe\{}", path.display());
    let stream = std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .open(pipe)?;
    exchange_with_thread_timeout(stream, request, IPC_TIMEOUT)
}

#[cfg(unix)]
fn roundtrip(path: &Path, request: &str) -> io::Result<String> {
    let stream = std::os::unix::net::UnixStream::connect(path)?;
    stream.set_read_timeout(Some(IPC_TIMEOUT))?;
    stream.set_write_timeout(Some(IPC_TIMEOUT))?;
    exchange(stream, request)
}

#[cfg(unix)]
fn exchange<S: Read + Write>(mut stream: S, request: &str) -> io::Result<String> {
    stream.write_all(request.as_bytes())?;
    stream.write_all(b"\n")?;
    stream.flush()?;
    let mut line = String::new();
    BufReader::new(stream.take(MAX_RESPONSE_BYTES as u64)).read_line(&mut line)?;
    Ok(line)
}

/// Windows only: a named-pipe `File` has no `set_read_timeout` through the standard library, so
/// the read is bounded with a background thread and `recv_timeout` instead (R-10-004, R-01-005).
#[cfg(windows)]
fn exchange_with_thread_timeout<S: Read + Write + Send + 'static>(
    mut stream: S,
    request: &str,
    timeout: Duration,
) -> io::Result<String> {
    stream.write_all(request.as_bytes())?;
    stream.write_all(b"\n")?;
    stream.flush()?;
    let (tx, rx) = mpsc::channel();
    std::thread::spawn(move || {
        let mut line = String::new();
        let result = BufReader::new(stream.take(MAX_RESPONSE_BYTES as u64))
            .read_line(&mut line)
            .map(|_| line);
        let _ = tx.send(result);
    });
    rx.recv_timeout(timeout).unwrap_or_else(|_| {
        Err(io::Error::new(
            io::ErrorKind::TimedOut,
            "herdr socket response timed out",
        ))
    })
}
