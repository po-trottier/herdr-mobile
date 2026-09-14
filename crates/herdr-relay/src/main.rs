//! `herdr-relay`: the Herdr Host plugin.
//!
//! With no arguments, runs the long-lived bridge (`bridge::run`): one relay
//! registration per paired device and one for an open pairing, behind the
//! R-10-062 loopback control transport. `posix/run.sh` and `windows/run.ps1`
//! invoke exactly this path with no arguments, matching their own doc
//! comments ("with no arguments it runs the long-lived bridge").
//!
//! The `popup` subcommand, which `posix/ui.sh`/`windows/ui.ps1` already invoke
//! ( `exec "$HERDR_RELAY_BIN" popup` ), dispatches to `herdr_relay::popup::run`
//! (interactive) or `run_once` (`--once`, R-31-16-06).
//!
//! The `ctl` subcommand (R-10-067), which `posix/relayctl.sh` and
//! `windows/relayctl.ps1` forward to, is the command-line client of the same
//! control transport: `ctl <status|clients|refresh|stop|revoke <device_id>>`.

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.first().map(String::as_str) == Some("popup") {
        let once = args.iter().any(|arg| arg == "--once");
        let result = if once {
            herdr_relay::popup::run_once(
                herdr_relay::popup::DEFAULT_ONCE_WIDTH,
                herdr_relay::popup::DEFAULT_ONCE_HEIGHT,
            )
        } else {
            herdr_relay::popup::run()
        };
        if let Err(err) = result {
            eprintln!("herdr-relay: {err}");
            std::process::exit(1);
        }
        return;
    }
    if args.first().map(String::as_str) == Some("install-keybind") {
        // R-10-060: `--action pair|pair-windows`; the ensure-service shims pass their
        // platform's id. Exit 1 on an error, 0 on every decided outcome.
        let action = args
            .iter()
            .position(|arg| arg == "--action")
            .and_then(|i| args.get(i + 1))
            .map(String::as_str)
            .unwrap_or(if cfg!(windows) {
                "pair-windows"
            } else {
                "pair"
            });
        let state_dir = match herdr_relay::config::resolve_config_dir() {
            Ok(dir) => dir,
            Err(err) => {
                eprintln!("herdr-relay: {err}");
                std::process::exit(1);
            }
        };
        // R-10-060: diagnostics go to `relay.log` in the plugin state directory
        // (R-10-051), never to a user path in stdout/stderr (AGENTS.md). The
        // directory and the append handle exist before the first decision, and a
        // log write that fails is a real failure, not a swallowed one.
        use std::io::Write;
        let mut log_file = std::fs::create_dir_all(&state_dir)
            .and_then(|()| {
                std::fs::OpenOptions::new()
                    .create(true)
                    .append(true)
                    .open(state_dir.join("relay.log"))
            })
            .unwrap_or_else(|err| {
                eprintln!("herdr-relay: cannot open relay.log: {}", err.kind());
                std::process::exit(1);
            });
        let mut log_failed = false;
        let mut log = |line: &str| {
            if writeln!(log_file, "{line}").is_err() {
                log_failed = true;
            }
        };
        let result = herdr_relay::keybind::install(action, &state_dir, &mut log);
        let (line, ok) = match &result {
            Ok(outcome) => (
                format!(
                    "herdr-relay: keybind {}",
                    herdr_relay::keybind::describe(outcome)
                ),
                true,
            ),
            Err(err) => (
                format!("herdr-relay: keybind install failed: {}", err.kind_name()),
                false,
            ),
        };
        log(&line);
        if log_failed {
            eprintln!("herdr-relay: writing relay.log failed");
            std::process::exit(1);
        }
        if ok {
            println!("{line}");
        } else {
            eprintln!("{line}");
            std::process::exit(1);
        }
        return;
    }
    if args.first().map(String::as_str) == Some("ctl") {
        std::process::exit(ctl(&args[1..]));
    }
    if args.first().map(String::as_str) == Some("--version") {
        println!("{}", env!("CARGO_PKG_VERSION"));
        return;
    }
    herdr_relay::bridge::run();
}

/// `herdr-relay ctl <status|clients|refresh|stop|revoke <device_id>>`
/// (R-10-067): the command-line client of the R-10-062 control transport.
/// Exit 0 on `ok`, 1 on an error reply or a local failure, 2 when the bridge
/// is not running. `status` prints the origin, the link state, the device
/// count and only whether a pairing is open with the seconds left — never
/// the phrase, the URI or the handle (R-10-065).
fn ctl(args: &[String]) -> i32 {
    use herdr_relay::control::{self, ClientError, Command};

    let Some(verb) = args.first().map(String::as_str) else {
        eprintln!("usage: herdr-relay ctl <status|clients|refresh|stop|revoke <device_id>>");
        return 1;
    };
    let paths = match herdr_relay::bridge::control_paths() {
        Ok(paths) => paths,
        Err(err) => {
            eprintln!("herdr-relay: {err}");
            return 2;
        }
    };
    let outcome: Result<(), ClientError> = match verb {
        "status" => control::status(&paths).map(|status| {
            let link = match status.link.state {
                control::LinkState::Connected => "connected",
                control::LinkState::Idle => "idle",
                control::LinkState::Offline => "offline",
                control::LinkState::Stopped => "stopped",
            };
            println!("relay: {}", status.relay_origin);
            println!("link: {link}");
            println!("devices: {}", status.devices.len());
            match &status.pairing {
                Some(pairing) => println!("pairing: open, {} s left", pairing.expires_in_s),
                None => println!("pairing: none"),
            }
        }),
        "clients" => control::status(&paths).and_then(|status| {
            let mut stdout = std::io::stdout().lock();
            for row in &status.devices {
                write_client(
                    &mut stdout,
                    &row.device_name,
                    row.platform,
                    &row.fingerprint,
                )
                .map_err(ClientError::Io)?;
            }
            Ok(())
        }),
        "refresh" => control::request(&paths, &Command::RevokeAll).map(|_| ()),
        "stop" => control::request(&paths, &Command::Stop).map(|_| ()),
        "revoke" => match args.get(1) {
            Some(device_id) => control::request(
                &paths,
                &Command::Revoke {
                    device_id: device_id.clone(),
                },
            )
            .map(|_| ()),
            None => {
                eprintln!("usage: herdr-relay ctl revoke <device_id>");
                return 1;
            }
        },
        _ => {
            eprintln!("usage: herdr-relay ctl <status|clients|refresh|stop|revoke <device_id>>");
            return 1;
        }
    };
    match outcome {
        Ok(()) => 0,
        Err(ClientError::NotRunning) => {
            eprintln!("{}", control::not_running_notice());
            2
        }
        Err(ClientError::Rejected(code)) => {
            eprintln!("herdr-relay: the bridge rejected the command ({code:?})");
            1
        }
        Err(err) => {
            eprintln!("herdr-relay: {err}");
            1
        }
    }
}

fn write_client(
    output: &mut impl std::io::Write,
    name: &str,
    platform: herdr_relay_proto::messages::Platform,
    fingerprint: &str,
) -> std::io::Result<()> {
    let platform = match platform {
        herdr_relay_proto::messages::Platform::Ios => "ios",
        herdr_relay_proto::messages::Platform::Android => "android",
    };
    writeln!(output, "{} {platform} {fingerprint}", name.escape_debug())
}

#[cfg(test)]
mod tests {
    #[test]
    fn clients_escape_device_control_characters_on_one_line() {
        let mut output = Vec::new();
        super::write_client(
            &mut output,
            "phone\n\x1b[2J\t",
            herdr_relay_proto::messages::Platform::Android,
            "3f9a-1c04-be77-20d5",
        )
        .expect("write client row");
        let text = String::from_utf8(output).expect("UTF-8 output");
        assert_eq!(text.lines().count(), 1);
        assert!(!text.contains(['\x1b', '\t']));
        assert!(text.starts_with("phone\\n"));
        assert!(text.ends_with(" android 3f9a-1c04-be77-20d5\n"));
    }
}
