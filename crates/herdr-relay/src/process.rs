//! One shared rule for every child process `herdr-relay` spawns: on Windows the
//! plugin runs from a console-less scheduled task (`windows/ensure-service.ps1`),
//! and a console-subsystem child spawned from a console-less parent allocates a
//! new, visible, focus-stealing console window as a side effect of its own
//! subsystem type. `AGENTS.md`'s "Never spawn a console-visible child process"
//! names the fix: pass Win32's `CREATE_NO_WINDOW` creation flag to the direct
//! child. That is complete for a simple, non-forking child such as `herdr`,
//! `curl` or `wget`. `pairing::wordlist` first carried this helper for its
//! fetch shell-out and documents the manual verification; `keybind` needed the
//! same flag for its `herdr` calls, so the helper lives here, owned by neither.

use std::io::Write;
use std::process::{Command, Stdio};

/// Win32's `CREATE_NO_WINDOW` process-creation flag (`winbase.h`).
#[cfg(windows)]
const CREATE_NO_WINDOW: u32 = 0x0800_0000;

/// Applies [`CREATE_NO_WINDOW`] on Windows so a console-subsystem child
/// spawned from a console-less parent allocates no visible console window.
/// A no-op on POSIX, where every process inherits or lacks a terminal by the
/// ordinary shell rules and this concern does not exist.
#[cfg(windows)]
pub fn suppress_console_window(cmd: &mut Command) {
    use std::os::windows::process::CommandExt;
    cmd.creation_flags(CREATE_NO_WINDOW);
}

/// See the Windows variant. Nothing to suppress on POSIX.
#[cfg(not(windows))]
pub fn suppress_console_window(_cmd: &mut Command) {}

/// A Herdr CLI invocation with the console window suppressed. Uses the absolute
/// binary Herdr injects as `HERDR_BIN_PATH` into plugin hooks and actions
/// (`docs/10-herdr-integration.md` §7.1), because the scheduled-task and
/// service environments that supervise this plugin do not always carry `herdr`
/// on `PATH`; falls back to `herdr` when the variable is absent, which is the
/// developer-shell case. `config::resolve_config_dir`, `ipc::discover` and
/// `keybind` all build their `herdr` commands here, so the flag and the binary
/// choice can never drift between call sites. The `bin/spike-*` probes are
/// throwaway developer tools and keep their own direct calls.
pub fn herdr_command(args: &[&str]) -> Command {
    let program = std::env::var_os("HERDR_BIN_PATH")
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "herdr".into());
    let mut cmd = Command::new(program);
    cmd.args(args);
    suppress_console_window(&mut cmd);
    cmd
}

// ---------------------------------------------------------------------------
// Clipboard (the popup's `c` key)
// ---------------------------------------------------------------------------

/// The Windows clipboard program name, exposed so the unit tests can assert it
/// without spawning anything.
#[cfg(windows)]
pub const CLIPBOARD_PROGRAM: &str = "clip";
#[cfg(target_os = "macos")]
pub const CLIPBOARD_PROGRAM: &str = "pbcopy";

/// The one fixed, path-free failure message for every clipboard copy: no tool
/// found, a spawn failure, or a non-zero exit. It names no program path and
/// never contains any part of the copied text.
pub const CLIPBOARD_COPY_FAILED: &str = "no clipboard tool found";

/// Why one candidate tool did not copy. `SpawnFailed` means the program was
/// not found, so the next candidate is worth trying; `ToolFailed` means a
/// program ran and still did not succeed.
enum CopyError {
    SpawnFailed,
    ToolFailed,
}

/// Pipes `text` to the platform clipboard tool over stdin: `clip` on Windows,
/// `pbcopy` on macOS, and on Linux the first found of `wl-copy`,
/// `xclip -selection clipboard` and `xsel --clipboard --input`. Every
/// `Command` goes through [`suppress_console_window`], like every other
/// child this crate spawns. On failure returns [`CLIPBOARD_COPY_FAILED`],
/// which is fixed and path-free, so no part of `text` can leak into it.
///
/// `clip.exe` reads raw bytes from a piped stdin, not console UTF-16: it
/// decodes them with the machine's console code page, so non-ASCII UTF-8 may
/// mangle (not measured here, because the one text this crate copies is
/// ASCII). The pairing URI is ASCII, so the one caller is unaffected.
pub fn copy_to_clipboard(text: &str) -> Result<(), String> {
    copy_first_success(clipboard_candidates(), text)
}

/// The platform's candidate tools, most preferred first.
fn clipboard_candidates() -> &'static [(&'static str, &'static [&'static str])] {
    #[cfg(windows)]
    {
        const CANDIDATES: [(&str, &[&str]); 1] = [(CLIPBOARD_PROGRAM, &[])];
        &CANDIDATES
    }
    #[cfg(all(not(windows), target_os = "macos"))]
    {
        const CANDIDATES: [(&str, &[&str]); 1] = [(CLIPBOARD_PROGRAM, &[])];
        &CANDIDATES
    }
    #[cfg(all(not(windows), not(target_os = "macos")))]
    {
        const CANDIDATES: [(&str, &[&str]); 3] = [
            ("wl-copy", &[]),
            ("xclip", &["-selection", "clipboard"]),
            ("xsel", &["--clipboard", "--input"]),
        ];
        &CANDIDATES
    }
}

/// Runs the candidates in order. The first one that exists owns the copy: a
/// tool that runs and fails is not retried on the next candidate. `pub` is not
/// needed; this stays private and is exercised by the tests through a
/// missing-program candidate, so no test touches the real clipboard.
fn copy_first_success(
    candidates: &[(&'static str, &'static [&'static str])],
    text: &str,
) -> Result<(), String> {
    for (program, args) in candidates {
        match copy_with(program, args, text) {
            Ok(()) => return Ok(()),
            Err(CopyError::ToolFailed) => return Err(CLIPBOARD_COPY_FAILED.to_string()),
            Err(CopyError::SpawnFailed) => continue,
        }
    }
    Err(CLIPBOARD_COPY_FAILED.to_string())
}

/// Pipes `text` to one tool over stdin. Dropping the taken stdin closes the
/// pipe, which is how every one of these tools knows the input is done. A
/// write error is ignored, because a tool that exits before reading all of
/// stdin still gets its real exit status reported by `wait`.
fn copy_with(program: &str, args: &[&str], text: &str) -> Result<(), CopyError> {
    let mut cmd = Command::new(program);
    cmd.args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    suppress_console_window(&mut cmd);
    let mut child = cmd.spawn().map_err(|_| CopyError::SpawnFailed)?;
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(text.as_bytes());
    }
    match child.wait() {
        Ok(status) if status.success() => Ok(()),
        _ => Err(CopyError::ToolFailed),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    #[cfg(windows)]
    fn the_windows_program_name_is_clip() {
        assert_eq!(CLIPBOARD_PROGRAM, "clip");
        assert!(clipboard_candidates().iter().any(|(p, _)| *p == "clip"));
    }

    #[test]
    fn the_error_message_contains_no_part_of_the_input_text() {
        let secret = "herdr-remote://pair?v=1&r=http%3A%2F%2Flocalhost%3A8080&h=abc&phrase=x-y-z";
        // A program that cannot exist fails the spawn, so this exercises the
        // real failure mapping and never touches the real clipboard.
        let err = copy_first_success(&[("herdr-no-such-clipboard-bin", &[])], secret)
            .expect_err("a missing program must fail");
        assert_eq!(err, CLIPBOARD_COPY_FAILED);
        for part in ["herdr-remote", "pair", "localhost", "abc", "x-y-z"] {
            assert!(!err.contains(part), "the error must not leak {part}");
        }
    }
}
