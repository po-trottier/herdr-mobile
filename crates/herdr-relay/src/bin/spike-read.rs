//! Phase 1 SPIKE A: prove the Herdr socket transport by reading one real pane.
//!
//! `docs/90-implementation-plan.md` Phase 1 owns this file. It proves, against a live Herdr
//! server, that a Rust client can discover the socket, connect on the current platform, call
//! `ping`, `session.snapshot`, `pane.layout` and `pane.read`, and get back genuine ANSI content.
//! `docs/01-architecture.md` §7 names this the first risk-spike assumption.
//!
//! Read-only. This binary MUST NOT close a pane, stop the server, or mutate layout it did not
//! create (R-40-030). It calls only `ping`, `session.snapshot`, `pane.layout` and `pane.read`.
//!
//! `crates/herdr-relay/src/ipc.rs` and `src/watch.rs` are owned by `WP-6` through the
//! `INT-6-bridge` integration step (`docs/90-implementation-plan.md` §5.3), not by this phase, so
//! the socket-client logic below is self-contained in this bin target rather than split into a
//! shared module. WP-6 folds these findings in when it builds the production client.

use std::env;
use std::io::{self, BufRead, BufReader, Read, Write};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::Duration;

use serde_json::{Value, json};

/// Matches `IPC_TIMEOUT` in the reference client, `ipc.rs:22` (R-10-004, R-10-034).
const IPC_TIMEOUT: Duration = Duration::from_secs(5);

/// Matches `MAX_RESPONSE_BYTES` in the reference client, `ipc.rs:26` (R-10-004).
const MAX_RESPONSE_BYTES: u64 = 4 * 1024 * 1024;

/// This build's protocol floor (R-10-012, R-41-164). `docs/02-herdr-probe-results.md` and
/// `docs/10-herdr-integration.md` were re-measured 2026-09-02 against Herdr
/// `0.8.2-preview.2026-08-31-b1ff4582e968`, superseding the 2026-08-27 probe that pinned `20`
/// and the original 2026-08-04 probe that pinned `19`.
const EXPECTED_PROTOCOL: u64 = 21;

fn main() {
    let pane_id = match env::args().nth(1) {
        Some(id) => id,
        None => {
            eprintln!("usage: spike-read <pane_id>");
            std::process::exit(2);
        }
    };

    if let Err(err) = run(&pane_id) {
        eprintln!("herdr-relay: {err}");
        std::process::exit(1);
    }
}

fn run(pane_id: &str) -> io::Result<()> {
    let path = socket_path()?;
    let mut counter: u64 = 0;

    let ping = call(&path, "ping", json!({}), next(&mut counter))?;
    let protocol = ping["result"]["protocol"].as_u64().unwrap_or(0);
    if protocol != EXPECTED_PROTOCOL {
        return Err(io::Error::other(format!(
            "protocol {protocol}, expected {EXPECTED_PROTOCOL}"
        )));
    }

    let snapshot = call(&path, "session.snapshot", json!({}), next(&mut counter))?;
    let viewport_rows = snapshot["result"]["snapshot"]["panes"]
        .as_array()
        .and_then(|panes| panes.iter().find(|p| p["pane_id"] == pane_id))
        .and_then(|p| p["scroll"]["viewport_rows"].as_u64())
        .ok_or_else(|| io::Error::other(format!("pane {pane_id} not found in session.snapshot")))?;

    let layout = call(
        &path,
        "pane.layout",
        json!({ "pane_id": pane_id }),
        next(&mut counter),
    )?;
    let width = layout["result"]["layout"]["panes"]
        .as_array()
        .and_then(|panes| panes.iter().find(|p| p["pane_id"] == pane_id))
        .and_then(|p| p["rect"]["width"].as_u64())
        .ok_or_else(|| io::Error::other(format!("pane {pane_id} not found in pane.layout")))?;

    let read = call(
        &path,
        "pane.read",
        json!({
            "pane_id": pane_id,
            "source": "visible",
            "format": "ansi",
            "strip_ansi": false,
        }),
        next(&mut counter),
    )?;
    let text = read["result"]["read"]["text"]
        .as_str()
        .ok_or_else(|| io::Error::other(format!("pane.read returned no text for {pane_id}")))?;

    // The pane text is a real user pane and is never printed (AGENTS.md "Never log");
    // the probe reports geometry and sizes only.
    println!("pane {pane_id}: columns={width} rows={viewport_rows}");
    println!(
        "read: rows={} bytes={} escape_sequences={}",
        text.lines().count(),
        text.len(),
        text.matches('\u{1b}').count()
    );

    Ok(())
}

fn next(counter: &mut u64) -> u64 {
    let value = *counter;
    *counter += 1;
    value
}

/// R-10-003: read `HERDR_SOCKET_PATH` first. When absent, parse the `socket:` line of
/// `herdr status`. Linux and macOS MUST NOT guess further; Windows falls back to `%APPDATA%`
/// per the reference client (`ipc.rs:30-43`, `docs/10-herdr-integration.md` §1.5).
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

/// One request, one response, one connection (R-10-009, R-02-004). Sends `params` always
/// (R-02-007), formats `id` as `herdr-relay:<method>:<counter>` (R-10-008), and returns the whole
/// envelope so the caller reads `result.<payload_key>` (R-10-007).
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

// Every `call` opens a fresh connection and this process never writes to a connection after
// reading its response, so the EPIPE-on-a-spent-connection case in R-10-010 cannot arise here;
// there is nothing to special-case.

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

/// POSIX only: the stream already carries its own read/write timeout (R-10-004).
#[cfg(unix)]
fn exchange<S: Read + Write>(mut stream: S, request: &str) -> io::Result<String> {
    stream.write_all(request.as_bytes())?;
    stream.write_all(b"\n")?;
    stream.flush()?;
    let mut line = String::new();
    BufReader::new(stream.take(MAX_RESPONSE_BYTES)).read_line(&mut line)?;
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
    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        let mut line = String::new();
        let result = BufReader::new(stream.take(MAX_RESPONSE_BYTES))
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
