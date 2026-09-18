//! `docs/90-implementation-plan.md` Phase 23: the Host half of the cross-component
//! end-to-end test `docs/40-repo-tooling.md` §5.4 (R-40-037) describes, delivered at
//! `tests/e2e/` (`tests/e2e/README.md` names the exact command sequence).
//!
//! Connects to a real, locally-run `herdr-relay-hub` instance (started separately, by
//! the caller, on `127.0.0.1` — never a public deployment) as the Host, registers on
//! `/host/<handle>`, and runs a real Noise responder handshake
//! (`crates/herdr-relay/src/noise.rs`, R-13-014, R-13-071) — reusing the production
//! `crate::relay::connect_host` path, not a hand-rolled one. Once the Noise transport
//! is up, this binary drives a real [`herdr_relay::watch::Bridge`] against a stub
//! [`HerdrCalls`] that returns a canned pane snapshot (§5.4 step 2), so every message
//! this process sends over the wire — `host_info`, `tree_snapshot`, `watch_ack`,
//! `pane_frame`, `scroll_response`, `send_input_ack`, `host_action_ack`,
//! `action_list`, `device_list`, `revoke_result` — is built by the same production
//! code the real Host plugin uses, not a throwaway reimplementation. The two
//! device-management replies read a throwaway file-only `DeviceStore` under a temp
//! directory (`ConfigPaths::new`), fed from the `device_info` this session received.
//!
//! `E2E_STUB_IGNORE` (optional): a comma-separated list of wire `type` names, for
//! example `device_list_request`. A request named there is not answered, only logged
//! as `request_ignored`, so a Device harness can prove its own no-reply timeout end
//! to end. Unset, every request is answered.
//!
//! `tests/e2e/full_stack_test.dart` spawns this binary as a subprocess (the same
//! pattern `app/test/spike/noise_client_test.dart` already established for
//! `src/bin/spike-noise-host.rs`) and drives the Device (initiator) side through the
//! app's own real `RelayConnection`/`TerminalService` stack, never a hand-rolled Dart
//! Noise client. See that file's own header comment for the full message sequence.
//!
//! Every event this binary observes is printed to stdout as one JSON line, flushed at
//! once, so the Dart harness (or a human) can follow progress and assert on specific
//! events — `send_input_received` in particular is the process-side proof that the
//! Host observed the Device's exact keystroke bytes (§5.4 step 5). A failure prints one
//! JSON line to stderr and exits non-zero.
//!
//! Not part of any other work package's owned-paths list (R-90-016): a throwaway
//! integration-proof binary, the same category as this crate's existing
//! `src/bin/spike-*.rs` files.

use std::collections::HashSet;
use std::env;
use std::io::Write;
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use herdr_relay::config::{ConfigPaths, RelayConfig};
use herdr_relay::frame_codec::Reassembler;
use herdr_relay::ipc::IpcError;
use herdr_relay::noise::{self, Role, Transport};
use herdr_relay::relay::{self, CloseReason, SessionRegistry, WsStream};
use herdr_relay::store::DeviceStore;
use herdr_relay::watch::{Bridge, HerdrCalls, HostIdentity, WatchError, map_watch_error};
use herdr_relay_proto::codes::{CloseCode, ErrorCode};
use herdr_relay_proto::frame::{Frame, SequenceCounter};
use herdr_relay_proto::handle::Handle;
use herdr_relay_proto::messages::{ErrorMessage, Message, SendInput, WatchPane};
use serde_json::{Value, json};
use tokio_tungstenite::tungstenite::Message as WsMessage;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::protocol::CloseFrame;
use tokio_tungstenite::tungstenite::protocol::frame::coding::CloseCode as WsCloseCode;

/// The relay subprotocol every connection MUST offer (R-11-013, R-12-020).
const SUBPROTOCOL: &str = "herdr-relay.v1";

/// R-41-131: bounds the connect-plus-registration attempt.
const CONNECT_TIMEOUT: Duration = Duration::from_secs(30);

/// The first canned pane (matches `tests/e2e/full_stack_test.dart`'s own constant):
/// tab `t1` "main", label "shell", 80x24, no agent, no scrollback above.
const PANE_ID: &str = "w1:p1";
/// The second canned pane, for `app/integration_test/*` cases that need a pane taller
/// than the phone viewport with an agent working in it: tab `t2` "plugin", label
/// "main", 144x50, 240 rows of scrollback above, agent `claude` `working`.
const TALL_PANE_ID: &str = "w1:p2";
/// The known content `full_stack_test.dart` asserts the Device's terminal buffer ends
/// up containing (§5.4 step 4). Every visible frame starts with this row.
const CANNED_TEXT: &str = "HERDR-E2E-STUB-SNAPSHOT-7f3a1c";
/// The exact keystroke texts the two Device tests send (`tests/e2e/full_stack_test.dart`
/// `_keystrokeText`, `integration_test/terminal_test.dart` `_sentText`). The stub compares
/// in place and reports only a boolean: terminal content never reaches stdout (`AGENTS.md`
/// "Never log"), and a digest of a short keystroke is still that content.
const EXPECTED_SEND_INPUT_TEXTS: [&str; 2] = ["E2E-KEYSTROKE-4d9b21", "herdr-e2e-terminal-case-4"];
/// The known `scroll_response` text (`pane.read` with `source:"recent"`), asserted by
/// `app/integration_test/host_dispatch_test.dart`.
const CANNED_SCROLLBACK: &str = "HERDR-E2E-STUB-SCROLLBACK-2b8e44\nline-2\nline-3";
/// The one canned plugin action `action_list` carries.
const CANNED_ACTION_ID: &str = "e2e-ping";
const WIDTH: u32 = 80;
const VIEWPORT_ROWS: u32 = 24;
const TALL_WIDTH: u32 = 144;
const TALL_VIEWPORT_ROWS: u32 = 50;
const TALL_SCROLLBACK_ROWS: u32 = 240;

/// A stub `herdr` (§5.4 step 2): returns the canned snapshot above (workspace `w1`
/// as the main checkout of repo `e2e-repo`, `w2` as a linked worktree of the same repo,
/// `w3` with no worktree; tabs `t1`/`t2` and panes `w1:p1`/`w1:p2` in `w1`), canned
/// scrollback and one canned plugin action, and records every write call by printing
/// it to stdout, with no real Herdr socket anywhere. Create actions answer fixed new
/// ids.
struct StubHerdr;

impl HerdrCalls for StubHerdr {
    fn session_snapshot(&self) -> Result<Value, IpcError> {
        Ok(json!({
            "workspaces": [
                {
                    "workspace_id": "w1", "label": "e2e", "focused": true,
                    "worktree": {
                        "repo_name": "e2e-repo", "is_linked_worktree": false,
                        "checkout_path": "/home/e2e", "repo_root": "/home/e2e",
                        "repo_key": "e2e-key",
                    },
                },
                {
                    "workspace_id": "w2", "label": "feature/e2e", "focused": false,
                    "worktree": {
                        "repo_name": "e2e-repo", "is_linked_worktree": true,
                        "checkout_path": "/home/e2e-wt", "repo_root": "/home/e2e",
                        "repo_key": "e2e-key",
                    },
                },
                { "workspace_id": "w3", "label": "scratch", "focused": false },
            ],
            "tabs": [
                { "tab_id": "t1", "workspace_id": "w1", "label": "main", "focused": true },
                { "tab_id": "t2", "workspace_id": "w1", "label": "plugin", "focused": false },
            ],
            "panes": [
                {
                    "pane_id": PANE_ID,
                    "workspace_id": "w1",
                    "tab_id": "t1",
                    "terminal_id": "term-p1",
                    "label": "shell",
                    "title": "shell",
                    "cwd": "/home",
                    "focused": true,
                    "agent": null,
                    "agent_status": "idle",
                    "revision": 1,
                    "scroll": {
                        "offset_from_bottom": 0,
                        "max_offset_from_bottom": 0,
                        "viewport_rows": VIEWPORT_ROWS,
                    },
                },
                {
                    "pane_id": TALL_PANE_ID,
                    "workspace_id": "w1",
                    "tab_id": "t2",
                    "terminal_id": "term-p2",
                    "label": "main",
                    "title": "main",
                    "cwd": "/home/plugin",
                    "focused": false,
                    "agent": "claude",
                    "agent_status": "working",
                    "revision": 1,
                    "scroll": {
                        "offset_from_bottom": 0,
                        "max_offset_from_bottom": TALL_SCROLLBACK_ROWS,
                        "viewport_rows": TALL_VIEWPORT_ROWS,
                    },
                },
            ],
            "agents": [{
                "agent": "claude",
                "pane_id": TALL_PANE_ID,
                "agent_status": "working",
                "agent_session": { "value": "e2e-session" },
            }],
        }))
    }

    fn pane_layout(&self, pane_id: &str) -> Result<Value, IpcError> {
        let width = if pane_id == TALL_PANE_ID {
            TALL_WIDTH
        } else {
            WIDTH
        };
        Ok(json!({ "panes": [{"pane_id": pane_id, "rect": {"width": width}}] }))
    }

    /// Row 1 is [`CANNED_TEXT`]; the tall pane fills its whole 50-row viewport with
    /// ANSI-coloured rows, so the Device's grid is taller than a phone screen.
    fn pane_read_visible(&self, pane_id: &str) -> Result<Value, IpcError> {
        let rows = if pane_id == TALL_PANE_ID {
            TALL_VIEWPORT_ROWS
        } else {
            1
        };
        let text = (1..=rows)
            .map(|row| {
                if row == 1 {
                    CANNED_TEXT.to_owned()
                } else {
                    format!("\x1b[3{}mrow-{row:02}\x1b[0m", row % 7 + 1)
                }
            })
            .collect::<Vec<_>>()
            .join("\n");
        Ok(json!({ "text": text, "truncated": false }))
    }

    /// `truncated: true` always: the canned scrollback stands in for a longer real one.
    fn pane_read_recent(&self, pane_id: &str, lines: u32) -> Result<Value, IpcError> {
        emit_stdout(&json!({ "event": "scroll_read", "pane_id": pane_id, "lines": lines }));
        Ok(json!({ "text": CANNED_SCROLLBACK, "truncated": true }))
    }

    fn pane_send_text(&self, pane_id: &str, text: &str) -> Result<(), IpcError> {
        emit_stdout(&json!({
            "event": "send_input_received",
            "pane_id": pane_id,
            "text_len": text.len(),
            "text_matches_expected": EXPECTED_SEND_INPUT_TEXTS.contains(&text),
            "keys_len": 0,
        }));
        Ok(())
    }

    fn pane_send_input(
        &self,
        pane_id: &str,
        text: Option<&str>,
        keys: Option<&[String]>,
    ) -> Result<(), IpcError> {
        // The process-side proof for §5.4 step 5: `tests/e2e/full_stack_test.dart`
        // asserts one of this process's stdout lines carries this event with
        // `text_matches_expected: true`. Key names are input too, so only their count goes out.
        emit_stdout(&json!({
            "event": "send_input_received",
            "pane_id": pane_id,
            "text_len": text.map_or(0, str::len),
            "text_matches_expected": text.is_some_and(|t| EXPECTED_SEND_INPUT_TEXTS.contains(&t)),
            "keys_len": keys.map_or(0, <[String]>::len),
        }));
        Ok(())
    }

    fn agent_prompt(&self, target: &str, _text: &str) -> Result<(), IpcError> {
        emit_stdout(&json!({ "event": "agent_prompt_received", "target": target }));
        Ok(())
    }

    fn agent_focus(&self, target: &str) -> Result<(), IpcError> {
        emit_stdout(&json!({"event": "mark_seen_received", "target": target}));
        Ok(())
    }

    fn workspace_create(&self, _params: Value) -> Result<String, IpcError> {
        host_call("workspace.create", PANE_ID);
        Ok("w2".to_owned())
    }

    fn tab_create(&self, _params: Value) -> Result<String, IpcError> {
        host_call("tab.create", PANE_ID);
        Ok("t2".to_owned())
    }

    fn pane_split(&self, _params: Value) -> Result<String, IpcError> {
        host_call("pane.split", PANE_ID);
        Ok("w1:p3".to_owned())
    }

    fn pane_zoom(&self, pane_id: &str, _mode: &str) -> Result<(), IpcError> {
        host_call("pane.zoom", pane_id);
        Ok(())
    }

    fn pane_close(&self, pane_id: &str) -> Result<(), IpcError> {
        host_call("pane.close", pane_id);
        Ok(())
    }

    fn pane_rename(&self, pane_id: &str, _label: Option<&str>) -> Result<(), IpcError> {
        host_call("pane.rename", pane_id);
        Ok(())
    }

    fn pane_resize(
        &self,
        pane_id: &str,
        _direction: &str,
        _amount: Option<f64>,
    ) -> Result<(), IpcError> {
        host_call("pane.resize", pane_id);
        Ok(())
    }

    fn plugin_action_list(&self) -> Result<Value, IpcError> {
        Ok(json!([{
            "plugin_id": "e2e-stub-plugin",
            "action_id": CANNED_ACTION_ID,
            "title": "E2E ping",
            "description": "canned action for the end-to-end test",
            "contexts": ["global"],
            "platforms": null,
        }]))
    }

    fn plugin_action_invoke(&self, params: Value) -> Result<Value, IpcError> {
        emit_stdout(&json!({
            "event": "plugin_invoke_received",
            "action_id": params.get("action_id"),
        }));
        Ok(json!({}))
    }
}

/// The process-side proof that a `host_action` reached the Herdr call the
/// production `Bridge` maps it to.
fn host_call(method: &str, pane_id: &str) {
    emit_stdout(&json!({ "event": "host_call", "method": method, "pane_id": pane_id }));
}

#[tokio::main]
async fn main() {
    if let Err(message) = run().await {
        emit_stderr(&message);
        std::process::exit(1);
    }
}

async fn run() -> Result<(), String> {
    let relay_addr = require_env("RELAY_ADDR")?;
    let handle_str = require_env("HANDLE")?;
    let phrase = require_env("PHRASE")?;

    let handle: Handle = handle_str
        .parse()
        .map_err(|error| format!("invalid HANDLE: {error}"))?;

    let (host_private, _host_public) =
        noise::generate_keypair().map_err(|error| format!("keypair generation failed: {error}"))?;
    // R-13-024: the PSK is derived from the phrase, never the raw phrase bytes.
    let psk = noise::psk_from_phrase(phrase.as_bytes());

    // Registers on the relay first, in its own step, and reports
    // `host_registered` before starting the Noise handshake.
    // `relay::connect_host` does registration and the full handshake as one
    // blocking call with no hook in between, which would leave
    // `tests/e2e/full_stack_test.dart` unable to tell "the Host has
    // registered, the Device may now connect" from "the Host is still
    // waiting for the Device's first handshake message" apart — and the
    // relay itself refuses a Device connection with `handle_unknown` until
    // the Host has registered
    // (`crates/herdr-relay-hub/src/routes/connection.rs`), so that ordering
    // matters here. This mirrors `src/bin/spike-noise-host.rs`'s own manual
    // connect-then-handshake steps, for exactly that reason.
    let url = format!("ws://{relay_addr}/host/{handle}");
    let mut request = url
        .into_client_request()
        .map_err(|error| format!("building the Host WebSocket request failed: {error}"))?;
    request.headers_mut().insert(
        "sec-websocket-protocol",
        SUBPROTOCOL
            .parse()
            .expect("the subprotocol constant is a valid header value"),
    );
    let (mut socket, _response) =
        tokio::time::timeout(CONNECT_TIMEOUT, tokio_tungstenite::connect_async(request))
            .await
            .map_err(|_| "timed out connecting to the relay".to_owned())?
            .map_err(|error| format!("connecting to the relay failed: {error}"))?;

    // R-11-113: the Host registration frame.
    socket
        .send(WsMessage::Text(
            r#"{"type":"host_register","protocol":1}"#.into(),
        ))
        .await
        .map_err(|error| format!("sending host_register failed: {error}"))?;
    let joined = next_text(&mut socket).await?;
    if !joined.contains("session_joined") {
        return Err(format!("expected session_joined, got: {joined}"));
    }
    emit_stdout(&json!({"event": "host_registered"}));

    // R-13-071: the Host is the Noise responder.
    let mut handshake = noise::pairing_handshake(Role::Responder, &host_private, &psk)
        .map_err(|error| format!("building the responder handshake failed: {error}"))?;

    let msg1 = next_binary(&mut socket).await?;
    noise::read_handshake_message(&mut handshake, &msg1)
        .map_err(|error| format!("reading handshake message 1 failed: {error}"))?;

    let msg2 = noise::write_handshake_message(&mut handshake, &[])
        .map_err(|error| format!("writing handshake message 2 failed: {error}"))?;
    socket
        .send(WsMessage::Binary(msg2.into()))
        .await
        .map_err(|error| format!("sending handshake message 2 failed: {error}"))?;

    let msg3 = next_binary(&mut socket).await?;
    noise::read_handshake_message(&mut handshake, &msg3)
        .map_err(|error| format!("reading handshake message 3 failed: {error}"))?;

    let (mut transport, device_static_public) = noise::finish_handshake(handshake)
        .map_err(|error| format!("finishing the handshake failed: {error}"))?;

    // Key material never reaches stdout (AGENTS.md "Never log"): the event alone is the proof.
    emit_stdout(&json!({ "event": "handshake_complete" }));

    let identity = HostIdentity {
        host_id: "e2e-stub-host".to_owned(),
        host_name: "e2e-stub-host".to_owned(),
    };
    let mut bridge = Bridge::new(StubHerdr, identity, RelayConfig::default());
    let mut seq = SequenceCounter::new();

    // R-11-130: host_info MUST be the first application frame after transport mode.
    let mut host_info = bridge.host_info("0.0.0-e2e-stub".to_owned(), 20, false);
    host_info.theme = Some(
        herdr_relay::theme::resolve("[theme]\nname = \"vesper\"", false).expect("known palette"),
    );
    send_message(
        &mut socket,
        &mut transport,
        &mut seq,
        &Message::HostInfo(host_info),
        None,
    )
    .await?;
    emit_stdout(&json!({"event": "host_info_sent"}));

    let mut reassembler = Reassembler::default();

    // The device-management replies read a throwaway, file-only store (never the
    // machine's credential store: `ConfigPaths::new`), fed from this session's
    // `device_info`. The registry is how a self-`revoke_device` closes this
    // session with the fatal `revoked` error and 4004, exactly as the production
    // bridge does (R-11-064, R-11-065).
    let paths = ConfigPaths::new(env::temp_dir().join(format!(
        "herdr-e2e-stub-host-{}-{}",
        std::process::id(),
        handle.encode()
    )));
    paths
        .ensure_dir()
        .map_err(|error| format!("creating the stub state directory failed: {error}"))?;
    let mut store = DeviceStore::load(paths.clone())
        .map_err(|error| format!("loading the stub device store failed: {error}"))?;
    let registry = SessionRegistry::new();
    let mut close_rx = registry.register(handle, None);
    let mut connected_device_id: Option<String> = None;
    let ignored: HashSet<String> = env::var("E2E_STUB_IGNORE")
        .unwrap_or_default()
        .split(',')
        .map(str::trim)
        .filter(|name| !name.is_empty())
        .map(str::to_owned)
        .collect();

    loop {
        let bytes = match relay::receive_frame(&mut socket, &mut transport, &mut reassembler).await
        {
            Ok(bytes) => bytes,
            Err(error) => {
                emit_stdout(
                    &json!({"event": "device_connection_ended", "reason": error.to_string()}),
                );
                break;
            }
        };
        let frame = Frame::from_json_bytes(&bytes)
            .map_err(|error| format!("parsing a frame failed: {error}"))?;
        let corr = frame.corr.clone();
        let message = frame
            .message()
            .map_err(|error| format!("decoding a message failed: {error}"))?;

        if ignored.contains(message.type_name()) {
            emit_stdout(&json!({"event": "request_ignored", "type": message.type_name()}));
            continue;
        }

        match message {
            Message::DeviceInfo(info) => {
                // A device id is never logged (AGENTS.md "Never log").
                emit_stdout(&json!({"event": "device_info_received"}));
                store
                    .add(
                        "e2e-stub-host".to_owned(),
                        handle.encode(),
                        info.device_id.clone(),
                        info.device_name,
                        info.platform,
                        info.os_version,
                        device_static_public,
                    )
                    .map_err(|error| format!("storing the device entry failed: {error}"))?;
                registry.set_device_id(handle, info.device_id.clone());
                connected_device_id = Some(info.device_id);
            }
            Message::TreeRequest(_) => {
                let reply = bridge.tree_snapshot().map(Message::TreeSnapshot);
                reply_with(&mut socket, &mut transport, &mut seq, reply, corr).await?;
                emit_stdout(&json!({"event": "tree_snapshot_sent"}));
            }
            Message::WatchPane(request) => {
                handle_watch_pane(
                    &mut bridge,
                    &mut socket,
                    &mut transport,
                    &mut seq,
                    request,
                    corr,
                )
                .await?
            }
            // R-11-050: no reply.
            Message::UnwatchPane(request) => {
                let pane_id = request.pane_id.clone();
                bridge.unwatch_pane(request);
                emit_stdout(&json!({"event": "unwatch_pane_received", "pane_id": pane_id}));
            }
            Message::ScrollRequest(request) => {
                let reply = bridge.scroll_request(request).map(Message::ScrollResponse);
                reply_with(&mut socket, &mut transport, &mut seq, reply, corr).await?;
                emit_stdout(&json!({"event": "scroll_response_sent"}));
            }
            Message::SendInput(request) => {
                handle_send_input(
                    &mut bridge,
                    &mut socket,
                    &mut transport,
                    &mut seq,
                    request,
                    corr,
                )
                .await?
            }
            Message::AgentPrompt(request) => {
                let reply = bridge.agent_prompt(request);
                reply_with(&mut socket, &mut transport, &mut seq, reply, corr).await?;
            }
            Message::MarkSeen(request) => {
                if let Err(err) = bridge.mark_seen(request) {
                    reply_with(&mut socket, &mut transport, &mut seq, Err(err), None).await?;
                }
            }
            Message::HostAction(request) => {
                let action = request.action;
                let reply = bridge.host_action(request);
                reply_with(&mut socket, &mut transport, &mut seq, reply, corr).await?;
                emit_stdout(&json!({"event": "host_action_answered", "action": action}));
            }
            Message::ActionListRequest(request) => {
                let reply = bridge.action_list_request(request);
                reply_with(&mut socket, &mut transport, &mut seq, reply, corr).await?;
                emit_stdout(&json!({"event": "action_list_sent"}));
            }
            Message::DeviceListRequest(request) => {
                let reply = Bridge::<StubHerdr>::device_list_request(
                    &store,
                    connected_device_id.as_deref(),
                    request,
                );
                let count = match &reply {
                    Message::DeviceList(list) => list.devices.len(),
                    _ => 0,
                };
                send_message(&mut socket, &mut transport, &mut seq, &reply, corr).await?;
                emit_stdout(&json!({"event": "device_list_sent", "count": count}));
            }
            Message::RevokeDevice(request) => {
                let reply = Bridge::<StubHerdr>::revoke_device_request(
                    &mut store,
                    &paths,
                    request,
                    Some(&registry),
                );
                reply_with(&mut socket, &mut transport, &mut seq, reply, corr).await?;
                emit_stdout(&json!({"event": "revoke_result_sent"}));
                // R-11-065: the fatal error is the last frame, then 4004.
                if matches!(close_rx.try_recv(), Ok(CloseReason::Revoked)) {
                    let fatal = Message::Error(ErrorMessage {
                        code: ErrorCode::Revoked,
                        message: "This device has been revoked.".to_owned(),
                        fatal: true,
                    });
                    send_message(&mut socket, &mut transport, &mut seq, &fatal, None).await?;
                    socket
                        .send(WsMessage::Close(Some(CloseFrame {
                            code: WsCloseCode::from(CloseCode::Revoked.code()),
                            reason: String::new().into(),
                        })))
                        .await
                        .map_err(|error| format!("sending the 4004 close failed: {error}"))?;
                    emit_stdout(&json!({"event": "session_closed_revoked"}));
                    break;
                }
            }
            Message::Disconnect(_) => {
                emit_stdout(&json!({"event": "device_disconnect_frame_received"}));
                break;
            }
            other => {
                emit_stdout(
                    &json!({"event": "unexpected_message_ignored", "type": other.type_name()}),
                );
            }
        }
    }

    std::fs::remove_dir_all(paths.dir()).ok();
    emit_stdout(&json!({"event": "teardown_complete"}));
    Ok(())
}

/// Sends a handler's reply with the request's `corr`, or the `error` frame
/// R-11-091 maps a handler failure to — the same two arms the production
/// `bridge_thread` runs.
async fn reply_with(
    socket: &mut WsStream,
    transport: &mut Transport,
    seq: &mut SequenceCounter,
    reply: Result<Message, WatchError>,
    corr: Option<String>,
) -> Result<(), String> {
    let message = match reply {
        Ok(message) => message,
        Err(error) => Message::Error(map_watch_error(&error)),
    };
    send_message(socket, transport, seq, &message, corr).await
}

async fn handle_watch_pane(
    bridge: &mut Bridge<StubHerdr>,
    socket: &mut WsStream,
    transport: &mut Transport,
    seq: &mut SequenceCounter,
    request: WatchPane,
    corr: Option<String>,
) -> Result<(), String> {
    let pane_id = request.pane_id.clone();
    let (ack, first_frame) = bridge
        .watch_pane(request)
        .map_err(|error| format!("watch_pane failed: {error}"))?;
    emit_stdout(
        &json!({"event": "watch_pane_acked", "pane_id": pane_id, "revision": ack.revision}),
    );
    send_message(socket, transport, seq, &Message::WatchAck(ack), corr).await?;
    send_message(
        socket,
        transport,
        seq,
        &Message::PaneFrame(first_frame.clone()),
        None,
    )
    .await?;
    // `app/lib/services/terminal.dart`'s own revision gate (R-31-08-03, R-02-012)
    // rejects a `pane_frame` whose revision does not exceed the revision `watch_ack`
    // already published, and that comparison races a live socket for real: whichever
    // of `watch_ack`/this first `pane_frame` the Device's stream listener happens to
    // apply first decides whether the first frame survives. Real production Herdr
    // only ever sends a second frame after a genuine `pane.updated` event pushed
    // through the Herdr subscription; this stub has no live subscription to wait for
    // one, so it sends a synthetic follow-up frame, identical content, with a
    // strictly higher revision than `first_frame`'s — the Device is guaranteed to
    // accept it regardless of how the race above resolved.
    let mut bumped_frame = first_frame;
    bumped_frame.revision += 1;
    send_message(
        socket,
        transport,
        seq,
        &Message::PaneFrame(bumped_frame),
        None,
    )
    .await
}

async fn handle_send_input(
    bridge: &mut Bridge<StubHerdr>,
    socket: &mut WsStream,
    transport: &mut Transport,
    seq: &mut SequenceCounter,
    request: SendInput,
    corr: Option<String>,
) -> Result<(), String> {
    let pane_id = request.pane_id.clone();
    let reply = bridge
        .send_input(request)
        .map_err(|error| format!("send_input failed: {error}"))?;
    emit_stdout(&json!({"event": "send_input_acked", "pane_id": pane_id}));
    send_message(socket, transport, seq, &reply, corr).await
}

async fn send_message(
    socket: &mut WsStream,
    transport: &mut Transport,
    seq: &mut SequenceCounter,
    message: &Message,
    corr: Option<String>,
) -> Result<(), String> {
    let frame = Frame::wrap(seq.advance(), corr, message)
        .map_err(|error| format!("building a {} frame failed: {error}", message.type_name()))?;
    let bytes = frame.to_json_bytes().map_err(|error| {
        format!(
            "serializing a {} frame failed: {error}",
            message.type_name()
        )
    })?;
    relay::send_frame(socket, transport, &bytes)
        .await
        .map_err(|error| format!("sending a {} frame failed: {error}", message.type_name()))
}

fn require_env(name: &str) -> Result<String, String> {
    env::var(name).map_err(|_| format!("missing required environment variable {name}"))
}

fn emit_stdout(value: &Value) {
    println!("{value}");
    let _ = std::io::stdout().flush();
}

fn emit_stderr(message: &str) {
    let value = json!({ "error": message });
    eprintln!("{value}");
    let _ = std::io::stderr().flush();
}

async fn next_text(socket: &mut WsStream) -> Result<String, String> {
    match next_message(socket).await? {
        WsMessage::Text(text) => Ok(text.to_string()),
        other => Err(format!("expected a text frame, got: {other:?}")),
    }
}

async fn next_binary(socket: &mut WsStream) -> Result<Vec<u8>, String> {
    match next_message(socket).await? {
        WsMessage::Binary(bytes) => Ok(bytes.to_vec()),
        other => Err(format!("expected a binary frame, got: {other:?}")),
    }
}

async fn next_message(socket: &mut WsStream) -> Result<WsMessage, String> {
    tokio::time::timeout(CONNECT_TIMEOUT, socket.next())
        .await
        .map_err(|_| "timed out waiting for the next relay frame".to_owned())?
        .ok_or_else(|| "the relay closed the connection".to_owned())?
        .map_err(|error| format!("reading from the relay failed: {error}"))
}
