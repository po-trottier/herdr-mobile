//! Low-level platform transport: opening the named pipe (Windows) or the
//! `AF_UNIX` socket (POSIX), and a bounded write-then-read round trip. No
//! request/response or subscription protocol semantics live here — `client.rs`
//! and `subscription.rs` both build on this.

use std::io::{self, BufRead, BufReader, Read, Write};
use std::path::Path;
#[cfg(windows)]
use std::sync::mpsc;
use std::time::Duration;

#[cfg(windows)]
pub(super) type PlatformStream = std::fs::File;
#[cfg(unix)]
pub(super) type PlatformStream = std::os::unix::net::UnixStream;

/// The whole path, drive letter and backslashes included, becomes the named-pipe
/// name (R-41-153); on POSIX it is used as an `AF_UNIX` address unchanged.
#[cfg(windows)]
pub(super) fn open_platform(path: &Path) -> io::Result<PlatformStream> {
    let pipe = format!(r"\\.\pipe\{}", path.display());
    std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .open(pipe)
}

#[cfg(unix)]
pub(super) fn open_platform(path: &Path) -> io::Result<PlatformStream> {
    std::os::unix::net::UnixStream::connect(path)
}

pub(super) fn write_request(stream: &mut PlatformStream, request: &str) -> io::Result<()> {
    stream.write_all(request.as_bytes())?;
    stream.write_all(b"\n")?;
    stream.flush()
}

/// Reads one line into `line`, bounding the accepted response to `max_bytes`
/// (R-10-004). Buffers across reads, never assuming one read is one whole line
/// (R-10-005).
pub(super) fn read_bounded_line(
    reader: &mut BufReader<PlatformStream>,
    max_bytes: u64,
    line: &mut String,
) -> io::Result<usize> {
    let mut limited = reader.by_ref().take(max_bytes);
    limited.read_line(line)
}

/// One write-then-read round trip on a fresh connection (R-10-009). POSIX already
/// carries its timeout on the stream (set by the caller before this runs);
/// Windows has no `set_read_timeout` on a named-pipe `File` through the standard
/// library, so the read is bounded with a background thread and `recv_timeout`
/// instead (R-10-004, R-01-005) — this crate has no async runtime, so a
/// dedicated thread is the established pattern (`config.rs`'s `call_bounded` uses
/// the same technique).
pub(super) fn exchange(
    mut stream: PlatformStream,
    request: &str,
    max_bytes: u64,
    timeout: Duration,
) -> io::Result<String> {
    stream.write_all(request.as_bytes())?;
    stream.write_all(b"\n")?;
    stream.flush()?;

    #[cfg(unix)]
    {
        let _ = timeout; // already applied to the stream by the caller
        let mut line = String::new();
        BufReader::new(stream.take(max_bytes)).read_line(&mut line)?;
        Ok(line)
    }

    #[cfg(windows)]
    {
        let (tx, rx) = mpsc::channel();
        std::thread::spawn(move || {
            let mut line = String::new();
            let result = BufReader::new(stream.take(max_bytes))
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
}
