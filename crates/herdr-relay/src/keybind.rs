//! The plugin's default key binding for the pairing pane (`docs/10-herdr-integration.md`
//! R-10-060). A Herdr manifest carries no key: the live action schema holds only
//! `command`, `description`, `id`, `platforms` and `title`. So the startup hook installs
//! one `[[keys.command]]` block into the Herdr `config.toml` itself, through the
//! `herdr-relay install-keybind --action <id>` subcommand this module backs.
//!
//! The decision logic ([`plan`]) is pure and unit-tested against TOML text; the file and
//! process work ([`install`]) wraps it. Every `herdr` child goes through
//! [`crate::process::herdr_command`], so the console-less Windows scheduled-task parent
//! never pops a console window.

use std::fs;
use std::path::{Path, PathBuf};

use thiserror::Error;

/// The chord. Free in `herdr --default-config` (`prefix+p` is `previous_tab`,
/// `prefix+shift+p` is `rename_pane`) and in every reference plugin's documented binding.
pub const DEFAULT_KEY: &str = "prefix+shift+m";

/// Marker file in the plugin state directory. Its presence means the installer has run to
/// a decision once; the startup hook then never re-adds a binding the user deleted or
/// removed with `herdr config reset-keys`.
pub const MARKER_FILE: &str = "keybind.installed";

const MARKER_COMMENT: &str = "# herdr-relay: default pairing binding. Change the key here; the plugin never rewrites this block.";

/// What [`plan`] decided for a given `config.toml` text.
#[derive(Debug, PartialEq, Eq)]
pub enum Plan {
    /// A `pair`/`pair-windows` binding already exists under any key: the user customised it.
    AlreadyBound { key: String },
    /// [`DEFAULT_KEY`] is taken by another command: never overwrite.
    KeyOccupied { command: String },
    /// Append this exact text to the end of the file.
    Append(String),
}

/// What [`install`] did.
#[derive(Debug, PartialEq, Eq)]
pub enum Outcome {
    /// The marker exists; nothing was inspected or written.
    SkippedMarker,
    /// `herdr --help` printed no `Config:` line; nothing written.
    PathUnresolved,
    AlreadyBound {
        key: String,
    },
    KeyOccupied {
        command: String,
    },
    /// The file did not exist; created with only the block.
    Created(PathBuf),
    /// The block was appended.
    Appended(PathBuf),
}

impl Outcome {
    /// A fixed, path-free name: the marker file's whole payload (R-10-060).
    pub fn kind_name(&self) -> &'static str {
        match self {
            Outcome::SkippedMarker => "skipped",
            Outcome::PathUnresolved => "path-unresolved",
            Outcome::AlreadyBound { .. } => "already-bound",
            Outcome::KeyOccupied { .. } => "key-occupied",
            Outcome::Created(_) => "created",
            Outcome::Appended(_) => "appended",
        }
    }
}

#[derive(Debug, Error)]
pub enum KeybindError {
    #[error("action id must be `pair` or `pair-windows`, got `{0}`")]
    UnknownAction(String),
    #[error("run herdr {args} failed: {source}")]
    Spawn {
        args: String,
        #[source]
        source: std::io::Error,
    },
    #[error("{path} is not valid TOML: {message}")]
    Parse { path: PathBuf, message: String },
    #[error("{op} {path} failed: {source}")]
    Io {
        op: &'static str,
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("herdr config check rejected the new {path}; original restored")]
    CheckFailed { path: PathBuf },
}

impl KeybindError {
    /// A fixed, path-free name for logs (`AGENTS.md`: never log a user path).
    pub fn kind_name(&self) -> &'static str {
        match self {
            KeybindError::UnknownAction(_) => "unknown action id",
            KeybindError::Spawn { .. } => "could not run herdr",
            KeybindError::Parse { .. } => "config.toml is not valid TOML",
            KeybindError::Io { op, .. } => op,
            KeybindError::CheckFailed { .. } => {
                "herdr config check rejected the write; original restored"
            }
        }
    }
}

/// A fixed, path-free description of an [`Outcome`] for logs. The occupying command is
/// never echoed: a `popup` command can itself be a user path.
pub fn describe(outcome: &Outcome) -> String {
    match outcome {
        Outcome::SkippedMarker => "already decided on an earlier run; nothing written".into(),
        Outcome::PathUnresolved => "config path not resolved; nothing written".into(),
        Outcome::AlreadyBound { key } => {
            format!("already bound by the user to {key}; nothing written")
        }
        Outcome::KeyOccupied { .. } => {
            format!("{DEFAULT_KEY} is taken by another command; nothing written")
        }
        Outcome::Created(_) => format!("created config.toml with {DEFAULT_KEY}"),
        Outcome::Appended(_) => format!("appended {DEFAULT_KEY} to config.toml"),
    }
}

/// The block for one action id, exactly as it is appended.
pub fn block(action_id: &str) -> Result<String, KeybindError> {
    if action_id != "pair" && action_id != "pair-windows" {
        return Err(KeybindError::UnknownAction(action_id.to_string()));
    }
    Ok(format!(
        "{MARKER_COMMENT}\n[[keys.command]]\nkey = \"{DEFAULT_KEY}\"\ntype = \"plugin_action\"\ncommand = \"herdr-relay.{action_id}\"\ndescription = \"pair a phone\"\n"
    ))
}

/// Decides against the current `config.toml` text. `None` means the file does not exist.
pub fn plan(existing: Option<&str>, action_id: &str) -> Result<Plan, KeybindError> {
    let block = block(action_id)?;
    let Some(text) = existing else {
        return Ok(Plan::Append(block));
    };
    let doc: toml::Value = toml::from_str(text).map_err(|err| KeybindError::Parse {
        path: PathBuf::from("config.toml"),
        message: err.to_string(),
    })?;
    let commands = doc
        .get("keys")
        .and_then(|keys| keys.get("command"))
        .and_then(toml::Value::as_array)
        .cloned()
        .unwrap_or_default();
    for entry in &commands {
        let command = entry
            .get("command")
            .and_then(toml::Value::as_str)
            .unwrap_or("");
        let key = entry.get("key").and_then(toml::Value::as_str).unwrap_or("");
        if command == "herdr-relay.pair" || command == "herdr-relay.pair-windows" {
            return Ok(Plan::AlreadyBound {
                key: key.to_string(),
            });
        }
    }
    for entry in &commands {
        let key = entry.get("key").and_then(toml::Value::as_str).unwrap_or("");
        if key == DEFAULT_KEY {
            let command = entry
                .get("command")
                .and_then(toml::Value::as_str)
                .unwrap_or("");
            return Ok(Plan::KeyOccupied {
                command: command.to_string(),
            });
        }
    }
    let separator = if text.is_empty() || text.ends_with('\n') {
        "\n"
    } else {
        "\n\n"
    };
    Ok(Plan::Append(format!("{separator}{block}")))
}

/// Parses the `Config:` line of `herdr --help`.
pub fn parse_config_line(help: &str) -> Option<PathBuf> {
    help.lines()
        .map(str::trim)
        .find_map(|line| line.strip_prefix("Config:"))
        .map(str::trim)
        .filter(|path| !path.is_empty())
        .map(PathBuf::from)
}

fn run_herdr(args: &[&str]) -> Result<std::process::Output, KeybindError> {
    crate::process::herdr_command(args)
        .output()
        .map_err(|source| KeybindError::Spawn {
            args: args.join(" "),
            source,
        })
}

fn io_err<'a>(
    op: &'static str,
    path: &'a Path,
) -> impl FnOnce(std::io::Error) -> KeybindError + 'a {
    move |source| KeybindError::Io {
        op,
        path: path.to_path_buf(),
        source,
    }
}

/// Writes `candidate` to `path` and validates it with `check`. On a failed check the
/// original bytes are restored, or the file is deleted when it did not exist before.
/// `check` runs against the swapped-in file, because `herdr config check` reads only the
/// live path.
pub fn write_checked(
    path: &Path,
    original: Option<&[u8]>,
    candidate: &str,
    check: impl FnOnce() -> bool,
) -> Result<(), KeybindError> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(io_err("create directory", parent))?;
    }
    let temp = path.with_extension("toml.herdr-relay-tmp");
    fs::write(&temp, candidate).map_err(io_err("write", &temp))?;
    fs::rename(&temp, path).map_err(io_err("rename", &temp))?;
    if check() {
        return Ok(());
    }
    match original {
        Some(bytes) => fs::write(path, bytes).map_err(io_err("restore", path))?,
        None => fs::remove_file(path).map_err(io_err("remove", path))?,
    }
    Err(KeybindError::CheckFailed {
        path: path.to_path_buf(),
    })
}

/// Runs the whole installer once. `state_dir` holds [`MARKER_FILE`]; pass the plugin's
/// `herdr plugin config-dir herdr-relay` directory. `log` receives one line per
/// non-writing outcome so `relay.log` can carry it.
pub fn install(
    action_id: &str,
    state_dir: &Path,
    log: &mut dyn FnMut(&str),
) -> Result<Outcome, KeybindError> {
    let block = block(action_id)?;
    let marker = state_dir.join(MARKER_FILE);
    if marker.exists() {
        return Ok(Outcome::SkippedMarker);
    }
    let help = run_herdr(&["--help"])?;
    let Some(path) = parse_config_line(&String::from_utf8_lossy(&help.stdout)) else {
        log(&format!(
            "herdr-relay: could not resolve the Herdr config path; add this to config.toml:\n{block}"
        ));
        // Not a decision, so no marker (R-10-060 case 1): the next Herdr start retries,
        // when an upgraded `herdr` may print the line.
        return Ok(Outcome::PathUnresolved);
    };
    let original = match fs::read(&path) {
        Ok(bytes) => Some(bytes),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => None,
        Err(source) => return Err(io_err("read", &path)(source)),
    };
    let existing = original.as_deref().map(String::from_utf8_lossy);
    let decision = plan(existing.as_deref(), action_id).map_err(|err| match err {
        KeybindError::Parse { message, .. } => KeybindError::Parse {
            path: path.clone(),
            message,
        },
        other => other,
    })?;
    let outcome = match decision {
        Plan::AlreadyBound { key } => Outcome::AlreadyBound { key },
        Plan::KeyOccupied { command } => {
            log(&format!(
                "herdr-relay: {DEFAULT_KEY} is taken by another command; add this to config.toml with another key:\n{block}"
            ));
            Outcome::KeyOccupied { command }
        }
        Plan::Append(text) => {
            let mut candidate = existing.as_deref().map(str::to_owned).unwrap_or_default();
            candidate.push_str(&text);
            write_checked(&path, original.as_deref(), &candidate, || {
                run_herdr(&["config", "check"])
                    .map(|out| out.status.success())
                    .unwrap_or(false)
            })?;
            let reload = run_herdr(&["server", "reload-config"])?;
            if !reload.status.success() {
                log(
                    "herdr-relay: config written; herdr server reload-config failed, the binding applies on the next reload",
                );
            }
            if original.is_some() {
                Outcome::Appended(path)
            } else {
                Outcome::Created(path)
            }
        }
    };
    // The marker records only which case decided (R-10-060: no line written anywhere names
    // a user path); `Created`/`Appended` carry the resolved config path, so never `{:?}`.
    fs::create_dir_all(state_dir).map_err(io_err("create directory", state_dir))?;
    fs::write(&marker, format!("{}\n", outcome.kind_name())).map_err(io_err("write", &marker))?;
    Ok(outcome)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn block_carries_marker_key_command_and_description() {
        let text = block("pair-windows").unwrap();
        assert!(text.starts_with(MARKER_COMMENT));
        assert!(text.contains("key = \"prefix+shift+m\""));
        assert!(text.contains("command = \"herdr-relay.pair-windows\""));
        assert!(text.contains("description = \"pair a phone\""));
        assert!(block("clients").is_err());
    }

    #[test]
    fn marker_payload_never_names_the_resolved_path() {
        let path = PathBuf::from("C:/Users/someone/AppData/Roaming/herdr/config.toml");
        for outcome in [
            Outcome::Created(path.clone()),
            Outcome::Appended(path.clone()),
            Outcome::AlreadyBound {
                key: "prefix+alt+m".into(),
            },
            Outcome::KeyOccupied {
                command: "C:/Users/someone/tool.exe".into(),
            },
            Outcome::PathUnresolved,
            Outcome::SkippedMarker,
        ] {
            let payload = outcome.kind_name();
            assert!(
                !payload.contains("someone") && !payload.contains('/') && !payload.contains('\\')
            );
            assert!(!payload.contains("config.toml"));
        }
    }

    #[test]
    fn missing_file_appends_bare_block() {
        assert_eq!(
            plan(None, "pair").unwrap(),
            Plan::Append(block("pair").unwrap())
        );
    }

    #[test]
    fn existing_pair_binding_under_another_key_wins() {
        let text = "[[keys.command]]\nkey = \"prefix+alt+m\"\ntype = \"plugin_action\"\ncommand = \"herdr-relay.pair-windows\"\n";
        assert_eq!(
            plan(Some(text), "pair").unwrap(),
            Plan::AlreadyBound {
                key: "prefix+alt+m".into()
            }
        );
    }

    #[test]
    fn other_relay_action_bound_does_not_count_as_pair() {
        let text = "[[keys.command]]\nkey = \"prefix+alt+c\"\ntype = \"plugin_action\"\ncommand = \"herdr-relay.clients\"\n";
        assert!(matches!(plan(Some(text), "pair").unwrap(), Plan::Append(_)));
    }

    #[test]
    fn occupied_default_key_is_never_overwritten() {
        let text =
            "[[keys.command]]\nkey = \"prefix+shift+m\"\ntype = \"popup\"\ncommand = \"lazygit\"\n";
        assert_eq!(
            plan(Some(text), "pair").unwrap(),
            Plan::KeyOccupied {
                command: "lazygit".into()
            }
        );
    }

    #[test]
    fn append_preserves_every_existing_line_and_comment() {
        let text = "# my note\nonboarding = false\n[[keys.command]]\nkey = \"prefix+f\"\ntype = \"plugin_action\"\ncommand = \"herdr-sidebar.open-sidebar-windows\"";
        let Plan::Append(tail) = plan(Some(text), "pair-windows").unwrap() else {
            panic!("expected append");
        };
        let result = format!("{text}{tail}");
        assert!(result.starts_with(text), "existing bytes must be a prefix");
        assert!(
            tail.starts_with("\n\n"),
            "a file without a final newline gets one blank line"
        );
        let doc: toml::Value = toml::from_str(&result).unwrap();
        assert_eq!(doc["keys"]["command"].as_array().unwrap().len(), 2);
    }

    #[test]
    fn passing_check_keeps_candidate() {
        let dir =
            std::env::temp_dir().join(format!("herdr-relay-keybind-ok-{}", std::process::id()));
        let path = dir.join("config.toml");
        write_checked(&path, None, "onboarding = false\n", || true).unwrap();
        assert_eq!(fs::read_to_string(&path).unwrap(), "onboarding = false\n");
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn passing_check_replaces_an_existing_file_in_place() {
        let dir = std::env::temp_dir().join(format!(
            "herdr-relay-keybind-replace-{}",
            std::process::id()
        ));
        let path = dir.join("config.toml");
        fs::create_dir_all(&dir).unwrap();
        fs::write(&path, b"onboarding = false\n").unwrap();
        write_checked(
            &path,
            Some(b"onboarding = false\n"),
            "onboarding = false\nx = 1\n",
            || true,
        )
        .unwrap();
        assert_eq!(
            fs::read_to_string(&path).unwrap(),
            "onboarding = false\nx = 1\n"
        );
        assert!(!path.with_extension("toml.herdr-relay-tmp").exists());
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn failed_check_restores_original_bytes() {
        let dir = std::env::temp_dir().join(format!("herdr-relay-keybind-{}", std::process::id()));
        let path = dir.join("config.toml");
        fs::create_dir_all(&dir).unwrap();
        fs::write(&path, b"onboarding = false\n").unwrap();
        let err = write_checked(&path, Some(b"onboarding = false\n"), "broken = [", || false);
        assert!(matches!(err, Err(KeybindError::CheckFailed { .. })));
        assert_eq!(fs::read(&path).unwrap(), b"onboarding = false\n");
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn failed_check_deletes_a_created_file() {
        let dir =
            std::env::temp_dir().join(format!("herdr-relay-keybind-new-{}", std::process::id()));
        let path = dir.join("config.toml");
        let err = write_checked(&path, None, "broken = [", || false);
        assert!(matches!(err, Err(KeybindError::CheckFailed { .. })));
        assert!(!path.exists());
        fs::remove_dir_all(&dir).unwrap();
    }
}
