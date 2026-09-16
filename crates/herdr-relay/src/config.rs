//! The Host's writable directory and every tunable named in
//! `docs/10-herdr-integration.md` (R-10-051).
//!
//! Every file the Host writes — `config.toml`, `state.json`, `relay.log`, the
//! keyring-fallback keypair file and the paired-device list — lives under one
//! directory: the output of `herdr plugin config-dir herdr-relay`. R-10-045
//! forbids hardcoding a per-OS path, so [`resolve_config_dir`] always shells out
//! to the Herdr CLI, which is the one place that already knows the per-platform
//! rule.
//!
//! `docs/13-security-pairing.md` R-13-059 and R-13-060 also print a per-OS path
//! table for the keypair fallback file and the paired-device list
//! (`%APPDATA%\herdr\herdr-relay\...`, `~/.local/share/herdr/herdr-relay/...`).
//! Those hardcoded examples conflict with R-10-045's "MUST NOT hardcode" rule.
//! This module resolves the conflict by keeping R-13's file *names*
//! (`host-keypair.json`, `paired-devices.json`) and permission requirements, but
//! rooting every path at the `config-dir` output instead of a hardcoded example.

use std::path::{Path, PathBuf};
#[cfg(windows)]
use std::process::Command;
use std::sync::mpsc;
use std::thread;
use std::time::Duration;

use serde::{Deserialize, Serialize};
use thiserror::Error;

/// Errors from config-directory resolution, directory creation or
/// `config.toml` loading.
#[derive(Debug, Error)]
pub enum ConfigError {
    #[error("run herdr plugin config-dir herdr-relay failed: {0}")]
    ConfigDirSpawn(#[source] std::io::Error),
    #[error("herdr plugin config-dir herdr-relay exited with a failure status")]
    ConfigDirStatus,
    #[error("herdr plugin config-dir herdr-relay printed an empty path")]
    ConfigDirEmpty,
    #[error("create the Host config directory {path} failed: {source}")]
    CreateDir {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("restrict permissions on {path} failed: {source}")]
    Restrict {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("read config.toml at {path} failed: {source}")]
    Read {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("parse config.toml at {path} failed: {source}")]
    Parse {
        path: PathBuf,
        #[source]
        source: Box<toml::de::Error>,
    },
    #[error("write {path} failed: {source}")]
    Write {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
}

/// Resolves `herdr plugin config-dir herdr-relay` (R-10-045). Never guesses a
/// per-OS path itself.
pub fn resolve_config_dir() -> Result<PathBuf, ConfigError> {
    let output = crate::process::herdr_command(&["plugin", "config-dir", "herdr-relay"])
        .output()
        .map_err(ConfigError::ConfigDirSpawn)?;
    if !output.status.success() {
        return Err(ConfigError::ConfigDirStatus);
    }
    let text = String::from_utf8_lossy(&output.stdout);
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return Err(ConfigError::ConfigDirEmpty);
    }
    Ok(PathBuf::from(trimmed))
}

/// The bound every production file read in this crate uses (R-41-131).
/// Matches the 5000 ms `IPC_TIMEOUT` convention `docs/10-herdr-integration.md`
/// R-10-004 already sets for the Herdr socket, so one number means "a blocking
/// I/O call" across the whole plugin.
pub const FILE_READ_TIMEOUT: Duration = Duration::from_millis(5000);

/// Bounds a blocking operation to `timeout` (R-41-131: "a file read... MUST
/// carry a timeout"). This crate has no `tokio` runtime wired in yet — every
/// caller here runs once at process start, before any async work exists — so
/// this bounds a synchronous call by running it on a dedicated thread and
/// waiting on it through an `mpsc::Receiver::recv_timeout`, rather than
/// pulling in an async runtime for one blocking call. On timeout the spawned
/// thread is left to finish in the background; its result is dropped when the
/// receiver goes out of scope.
fn call_bounded<T: Send + 'static>(
    timeout: Duration,
    operation: impl FnOnce() -> std::io::Result<T> + Send + 'static,
) -> std::io::Result<T> {
    let (tx, rx) = mpsc::channel();
    thread::Builder::new()
        .name("herdr-relay-bounded-io".to_string())
        .spawn(move || {
            // The receiver may already have timed out and been dropped; a failed
            // send just means nobody is waiting any more.
            let _ = tx.send(operation());
        })?;
    rx.recv_timeout(timeout).unwrap_or_else(|_| {
        Err(std::io::Error::new(
            std::io::ErrorKind::TimedOut,
            format!("operation exceeded {timeout:?} (R-41-131)"),
        ))
    })
}

/// `std::fs::read_to_string`, bounded to `timeout` (R-41-131). Preserves
/// `std::io::Error`, including `ErrorKind::NotFound`, so an existing caller
/// that matches on "file absent" keeps working unchanged.
pub fn read_to_string_bounded(path: &Path, timeout: Duration) -> std::io::Result<String> {
    let path = path.to_path_buf();
    call_bounded(timeout, move || std::fs::read_to_string(&path))
}

/// The file layout under the Host config directory (R-10-051, R-13-059,
/// R-13-060), plus where the Host keypair lives: the platform credential
/// store (R-13-058) for the live plugin directory only, or the fallback file
/// under `dir` for every other directory. The one OS credential-store entry
/// is shared by every process on the machine, so a test's or a throwaway
/// state directory's key rotation must never reach it (measured live:
/// a unit test's `keys::rotate` overwrote the live Host keypair).
#[derive(Debug, Clone)]
pub struct ConfigPaths {
    dir: PathBuf,
    os_keyring: bool,
}

impl ConfigPaths {
    /// File-only keypair storage under `dir` (R-13-059's fallback file,
    /// always). Every test `temp_paths()` and every `HERDR_RELAY_CONFIG_DIR`
    /// override uses this constructor.
    pub fn new(dir: PathBuf) -> Self {
        Self {
            dir,
            os_keyring: false,
        }
    }

    /// The live plugin config directory: the Host keypair lives in the
    /// platform credential store (R-13-058), with the file under `dir` only
    /// as R-13-059's fallback. Constructed once, by `bridge::control_paths`.
    pub fn with_os_keyring(dir: PathBuf) -> Self {
        Self {
            dir,
            os_keyring: true,
        }
    }

    /// Whether `keys` may read and write the platform credential store.
    pub fn uses_os_keyring(&self) -> bool {
        self.os_keyring
    }

    /// The config directory itself.
    pub fn dir(&self) -> &Path {
        &self.dir
    }

    /// Tunables (R-10-051).
    pub fn config_file(&self) -> PathBuf {
        self.dir.join("config.toml")
    }

    /// Pairing state (R-10-051).
    pub fn state_file(&self) -> PathBuf {
        self.dir.join("state.json")
    }

    /// Diagnostics (R-10-051).
    pub fn log_file(&self) -> PathBuf {
        self.dir.join("relay.log")
    }

    /// The Host keypair, used only when the platform credential store is
    /// unavailable (R-13-059).
    pub fn keypair_fallback_file(&self) -> PathBuf {
        self.dir.join("host-keypair.json")
    }

    /// The paired-device list (R-13-060).
    pub fn paired_devices_file(&self) -> PathBuf {
        self.dir.join("paired-devices.json")
    }

    /// The Host's runtime-fetched EFF word-list cache (R-13-025), keyed
    /// under this same config directory rather than a second hardcoded
    /// per-OS path. Requested by `WP-10-c` for
    /// `crates/herdr-relay/src/popup.rs`: `pairing::wordlist::load` takes a
    /// caller-supplied cache path (never resolving one itself), and the
    /// popup is that caller.
    pub fn wordlist_cache_file(&self) -> PathBuf {
        self.dir.join("wordlist-cache.txt")
    }

    /// Creates the config directory, if it does not already exist, with the
    /// most restrictive permissions the platform supports (R-13-061).
    pub fn ensure_dir(&self) -> Result<(), ConfigError> {
        create_restricted_dir(&self.dir)
    }
}

/// Every tunable `docs/10-herdr-integration.md` names, with the default value
/// measured in that document (R-10-051). Every field is keyed in `config.toml`
/// exactly as named here.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct RelayConfig {
    /// R-10-004, R-10-034: Herdr-socket read/write timeout, in milliseconds.
    pub socket_timeout_ms: u64,
    /// R-10-004: maximum accepted response-line size, in bytes.
    pub max_response_bytes: u64,
    /// R-10-029: pane-read debounce window, in milliseconds.
    pub debounce_ms: u64,
    /// R-10-070 (amended 2026-09-11): poll period for reading a watched pane whose
    /// `revision` does not move (R-02-026), in milliseconds. A typed character moves
    /// no revision at all, so this period is the keystroke echo's worst-case wait.
    pub poll_ms: u64,
    /// R-10-071: offsets after a forwarded `send_input`, in milliseconds, at
    /// which the bridge reads the watched pane. A keystroke moves no `revision`
    /// and emits no event (R-02-029), so only a timed read carries its echo.
    pub input_read_ms: Vec<u64>,
    /// R-10-030 (amended 2026-09-11): maximum `pane.read` calls per second, per
    /// attached pane. 16, to leave room for the R-10-071 input reads.
    pub max_reads_per_second: u32,
    /// R-10-033: panes one Device may attach to at once.
    pub attached_panes_per_device: u32,
    /// R-10-019, R-10-027: maximum `lines` requested from a scrollback read.
    pub max_scrollback_lines: u32,
    /// R-10-014 step 1: initial reconnect wait, in milliseconds.
    pub reconnect_initial_ms: u64,
    /// R-10-014 step 3: reconnect wait ceiling, in milliseconds.
    pub reconnect_max_ms: u64,
    /// R-10-014 step 4: jitter applied to every reconnect wait, as a fraction
    /// (`0.20` is ±20%).
    pub reconnect_jitter: f64,
    /// R-10-014 step 5: seconds a subscription must survive before the
    /// reconnect wait resets to `reconnect_initial_ms`.
    pub reconnect_reset_after_s: u64,
    /// The relay origin the operator configured (R-30-922, R-31-16-04). Not
    /// one of `docs/10-herdr-integration.md`'s own R-10-051 tunables — that
    /// document only names the ten socket/reconnect knobs above — but the
    /// pairing popup (`popup.rs`, `WP-10-c`) MUST always print an origin
    /// (R-31-16-04) and the mockup states plainly that "the origin comes
    /// from the plugin's own config.toml". Requested by `WP-10-c` as a
    /// minimal, additive `config.toml` key alongside the ten already here.
    /// Empty (the default) means "not yet configured"; `popup.rs` reports
    /// that state rather than guessing a value, per `R-03-030`'s sibling
    /// rule against a compiled-in default origin.
    pub relay_origin: String,
    /// R-10-061: the origin this Host process dials when it differs from the
    /// origin the phone is shown, for a relay that the Host reaches by another
    /// address (mirrored-mode WSL cannot reach the Windows host's own LAN
    /// address, and `localhost` first resolves to an unmirrored `::1`, which
    /// costs a 21 s connect timeout). Empty (the default) means "same as
    /// `relay_origin`". Validated with the same one validator.
    pub host_connect_origin: String,
}

impl Default for RelayConfig {
    fn default() -> Self {
        Self {
            socket_timeout_ms: 5000,
            max_response_bytes: 4 * 1024 * 1024,
            debounce_ms: 120,
            poll_ms: 125,
            input_read_ms: vec![60, 130, 250],
            max_reads_per_second: 16,
            attached_panes_per_device: 1,
            max_scrollback_lines: 1000,
            reconnect_initial_ms: 250,
            reconnect_max_ms: 8000,
            reconnect_jitter: 0.20,
            reconnect_reset_after_s: 30,
            relay_origin: String::new(),
            host_connect_origin: String::new(),
        }
    }
}

/// Loads `config.toml`, falling back to every documented default for a key
/// that is absent (R-10-051). Missing file is not an error: a fresh install
/// runs on defaults until the operator writes one.
pub fn load(paths: &ConfigPaths) -> Result<RelayConfig, ConfigError> {
    let path = paths.config_file();
    match read_to_string_bounded(&path, FILE_READ_TIMEOUT) {
        Ok(text) => toml::from_str(&text).map_err(|source| ConfigError::Parse {
            path: path.clone(),
            source: Box::new(source),
        }),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(RelayConfig::default()),
        Err(source) => Err(ConfigError::Read { path, source }),
    }
}

/// Writes `contents` to `path` with the most restrictive permissions the
/// platform supports, creating the parent directory first (R-13-059,
/// R-13-060, R-13-061).
pub fn write_restricted_file(path: &Path, contents: &[u8]) -> Result<(), ConfigError> {
    if let Some(parent) = path.parent() {
        create_restricted_dir(parent)?;
    }
    std::fs::write(path, contents).map_err(|source| ConfigError::Write {
        path: path.to_path_buf(),
        source,
    })?;
    restrict_file(path)
}

#[cfg(unix)]
fn create_restricted_dir(dir: &Path) -> Result<(), ConfigError> {
    use std::os::unix::fs::PermissionsExt;
    std::fs::create_dir_all(dir).map_err(|source| ConfigError::CreateDir {
        path: dir.to_path_buf(),
        source,
    })?;
    std::fs::set_permissions(dir, std::fs::Permissions::from_mode(0o700)).map_err(|source| {
        ConfigError::Restrict {
            path: dir.to_path_buf(),
            source,
        }
    })
}

#[cfg(unix)]
fn restrict_file(path: &Path) -> Result<(), ConfigError> {
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600)).map_err(|source| {
        ConfigError::Restrict {
            path: path.to_path_buf(),
            source,
        }
    })
}

#[cfg(windows)]
fn create_restricted_dir(dir: &Path) -> Result<(), ConfigError> {
    std::fs::create_dir_all(dir).map_err(|source| ConfigError::CreateDir {
        path: dir.to_path_buf(),
        source,
    })?;
    restrict_acl(dir, true)
}

#[cfg(windows)]
fn restrict_file(path: &Path) -> Result<(), ConfigError> {
    // ponytail: the directory ACL above already grants (OI)(CI) inheritance to
    // SYSTEM and the current user only, so a file created inside it inherits
    // the restriction. This second call is defense in depth for a file moved
    // or copied in from elsewhere.
    restrict_acl(path, false)
}

/// Restricts `path` to `SYSTEM` and the current user, full control
/// (R-13-059, R-13-060). Shells out to `icacls` rather than linking a Windows
/// ACL crate or calling `SetNamedSecurityInfo` through raw FFI.
/// ponytail: subprocess ceiling — upgrade to a programmatic ACL call only if
/// `icacls`'s ~10 ms spawn cost is ever measured to matter.
///
/// `(OI)(CI)` (object-inherit / container-inherit) are propagation flags:
/// valid on a directory, so a file created inside it inherits the same
/// restriction, but meaningless on a file. Applying them to a file does not
/// error; it silently produces an empty, unreadable ACL (verified against a
/// live `icacls` on this machine). `is_container` selects the correct form.
#[cfg(windows)]
fn restrict_acl(path: &Path, is_container: bool) -> Result<(), ConfigError> {
    let user = std::env::var("USERNAME").unwrap_or_else(|_| "%USERNAME%".to_string());
    let perm = if is_container { "(OI)(CI)F" } else { "F" };
    let grant_user = format!("{user}:{perm}");
    let grant_system = format!("SYSTEM:{perm}");
    let mut cmd = Command::new("icacls");
    cmd.arg(path).args([
        "/inheritance:r",
        "/grant:r",
        &grant_user,
        "/grant:r",
        &grant_system,
    ]);
    crate::process::suppress_console_window(&mut cmd);
    let output = cmd.output().map_err(|source| ConfigError::Restrict {
        path: path.to_path_buf(),
        source,
    })?;
    if !output.status.success() {
        let message = String::from_utf8_lossy(&output.stderr).into_owned();
        return Err(ConfigError::Restrict {
            path: path.to_path_buf(),
            source: std::io::Error::other(message),
        });
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_config_matches_documented_tunables() {
        let config = RelayConfig::default();
        assert_eq!(config.socket_timeout_ms, 5000);
        assert_eq!(config.max_response_bytes, 4 * 1024 * 1024);
        assert_eq!(config.debounce_ms, 120);
        assert_eq!(config.poll_ms, 125);
        assert_eq!(config.input_read_ms, vec![60, 130, 250]);
        assert_eq!(config.max_reads_per_second, 16);
        assert_eq!(config.attached_panes_per_device, 1);
        assert_eq!(config.max_scrollback_lines, 1000);
        assert_eq!(config.reconnect_initial_ms, 250);
        assert_eq!(config.reconnect_max_ms, 8000);
        assert_eq!(config.reconnect_reset_after_s, 30);
        assert_eq!(
            config.relay_origin, "",
            "not configured out of the box (R-03-030)"
        );
    }

    #[test]
    fn load_missing_file_returns_defaults() {
        let dir = std::env::temp_dir().join(format!("herdr-relay-cfg-test-{}", std::process::id()));
        let paths = ConfigPaths::new(dir);
        let config = load(&paths).expect("a missing config.toml is not an error");
        assert_eq!(config, RelayConfig::default());
    }

    #[test]
    fn load_reads_a_partial_override() {
        let dir = std::env::temp_dir().join(format!(
            "herdr-relay-cfg-test-partial-{}",
            std::process::id()
        ));
        let paths = ConfigPaths::new(dir);
        paths
            .ensure_dir()
            .expect("create the test config directory");
        std::fs::write(paths.config_file(), "debounce_ms = 250\n")
            .expect("write a partial config.toml");
        let config = load(&paths).expect("parse a partial config.toml");
        assert_eq!(config.debounce_ms, 250);
        assert_eq!(
            config.max_reads_per_second,
            RelayConfig::default().max_reads_per_second
        );
        std::fs::remove_dir_all(paths.dir()).ok();
    }

    #[test]
    fn write_restricted_file_creates_parent_and_readable_content() {
        let dir = std::env::temp_dir().join(format!(
            "herdr-relay-cfg-test-restrict-{}",
            std::process::id()
        ));
        let path = dir.join("child").join("secret.json");
        write_restricted_file(&path, b"{}").expect("write a restricted file");
        assert_eq!(
            std::fs::read(&path).expect("read back the restricted file"),
            b"{}"
        );
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn call_bounded_times_out_when_the_operation_is_slow() {
        let result: std::io::Result<()> = call_bounded(Duration::from_millis(50), || {
            std::thread::sleep(Duration::from_secs(2));
            Ok(())
        });
        let err = result.expect_err("a 2s operation must time out against a 50ms bound");
        assert_eq!(
            err.kind(),
            std::io::ErrorKind::TimedOut,
            "R-41-131: elapsed bound is reported"
        );
    }

    #[test]
    fn call_bounded_returns_promptly_when_the_operation_is_fast() {
        let result = call_bounded(Duration::from_secs(5), || Ok::<_, std::io::Error>(42));
        assert_eq!(
            result.expect("a fast operation completes within the bound"),
            42
        );
    }

    #[test]
    fn read_to_string_bounded_reads_a_real_file() {
        let path = std::env::temp_dir().join(format!(
            "herdr-relay-cfg-test-bounded-read-{}.txt",
            std::process::id()
        ));
        std::fs::write(&path, "hello").expect("write a test file");
        let text = read_to_string_bounded(&path, FILE_READ_TIMEOUT)
            .expect("read the test file within the bound");
        assert_eq!(text, "hello");
        std::fs::remove_file(&path).ok();
    }

    #[test]
    fn read_to_string_bounded_reports_not_found_like_std_fs() {
        let path = std::env::temp_dir().join(format!(
            "herdr-relay-cfg-test-bounded-missing-{}.txt",
            std::process::id()
        ));
        std::fs::remove_file(&path).ok();
        let err = read_to_string_bounded(&path, FILE_READ_TIMEOUT)
            .expect_err("a missing file is an error");
        assert_eq!(
            err.kind(),
            std::io::ErrorKind::NotFound,
            "existing NotFound callers keep working"
        );
    }
}
