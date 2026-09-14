//! Locating the Herdr socket path (R-10-003).

use std::env;
use std::io;
use std::path::PathBuf;
use std::process::Command;

/// R-10-003: read `HERDR_SOCKET_PATH` first. When absent, parse the `socket:` line
/// of `herdr status`. Windows falls back to `%APPDATA%`; POSIX MUST NOT guess
/// further (`docs/10-herdr-integration.md` §1.5).
pub(super) fn discover_socket_path() -> io::Result<PathBuf> {
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_the_socket_line_from_herdr_status() {
        let status = "server:\n  status: running\n  socket: /tmp/herdr/herdr.sock\n";
        assert_eq!(
            parse_socket_line(status),
            Some("/tmp/herdr/herdr.sock".to_string())
        );
    }

    #[test]
    fn returns_none_when_status_has_no_socket_line() {
        assert_eq!(parse_socket_line("server:\n  status: running\n"), None);
    }
}
