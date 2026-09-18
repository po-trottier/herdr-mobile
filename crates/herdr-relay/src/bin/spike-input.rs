//! Phase 7 spike: two live-Herdr measurements neither the closed-source server nor
//! the committed schema settles on paper.
//!
//! 1. The `result.<payload_key>` shape of `workspace.create`, `tab.create` and
//!    `pane.split` (`docs/10-herdr-integration.md` R-10-054, R-10-007). The
//!    `herdr api schema --json` `ResponseResult` union carries no `pane_split`
//!    variant, so the create-action bridge code in `watch/input.rs` is grounded in
//!    this measurement, not a guess.
//! 2. The DECCKM named-arrow-key question `docs/10-herdr-integration.md` R-10-037
//!    marks `[UNVERIFIED]`: whether Herdr's `pane.send_input {keys:["Up"]}` resolves
//!    the pane's actual DECCKM (application cursor key) mode. Feeds
//!    `docs/decisions/ADR-008-named-arrow-keys.md`.
//!
//! Every entity this binary creates is created by this binary and torn down before
//! exit (`workspace.close` on the scratch workspace), per the "never touch a
//! pre-existing pane/tab/workspace" rule this session was given. Read-only on
//! everything else: no call here names a pane, tab or workspace id this process did
//! not itself just receive back from Herdr.
//!
//! `crates/herdr-relay/src/watch/` is `WP-6`/`WP-7`'s production module; this binary
//! reuses it directly (`ipc::HerdrClient`) rather than re-implementing the socket
//! client a third time, unlike Phase 1's `spike-read.rs`, which predates `ipc.rs`.

use std::thread;
use std::time::Duration;

use serde_json::{Value, json};

use herdr_relay::config::RelayConfig;
use herdr_relay::ipc::HerdrClient;
use herdr_relay::watch::{Bridge, HostIdentity};
use herdr_relay_proto::messages::{SendInput, WatchPane};

fn main() {
    let config = RelayConfig::default();
    let client = match HerdrClient::discover(&config) {
        Ok(c) => c,
        Err(err) => {
            eprintln!("spike-input: discover failed: {err}");
            std::process::exit(2);
        }
    };
    if let Err(err) = client.ping() {
        eprintln!("spike-input: ping failed: {err}");
        std::process::exit(2);
    }

    let workspace_id = probe_create_shapes(&client);
    decckm_spike(&client, &workspace_id);
    ctrl_c_manual_test(&client, &workspace_id);

    // Teardown: this binary's own scratch workspace only.
    match client.call("workspace.close", json!({ "workspace_id": workspace_id })) {
        Ok(_) => println!("spike-input: torn down scratch workspace {workspace_id}"),
        Err(err) => eprintln!("spike-input: teardown failed (manual cleanup needed): {err}"),
    }
}

/// Measurement 1: print the real `result` envelope for each create call, so
/// `watch/input.rs` reads the true payload key instead of a guess.
fn probe_create_shapes(client: &HerdrClient) -> String {
    let ws = client
        .call("workspace.create", json!({ "focus": false }))
        .expect("workspace.create");
    println!("workspace.create result: {ws}");
    let workspace_id = ws["result"]["workspace"]["workspace_id"]
        .as_str()
        .expect("workspace_id in workspace.create result")
        .to_string();

    let tab = client
        .call(
            "tab.create",
            json!({ "workspace_id": workspace_id, "focus": false }),
        )
        .expect("tab.create");
    println!("tab.create result: {tab}");
    let tab_id = tab["result"]["tab"]["tab_id"]
        .as_str()
        .expect("tab_id in tab.create result")
        .to_string();
    let first_pane_id = tab["result"]["root_pane"]["pane_id"]
        .as_str()
        .expect("root_pane.pane_id in tab.create result")
        .to_string();

    let split = client
        .call(
            "pane.split",
            json!({ "tab_id": tab_id, "target_pane_id": first_pane_id, "direction": "right", "focus": false }),
        )
        .expect("pane.split");
    println!("pane.split result: {split}");

    workspace_id
}

/// Measurement 2: the DECCKM behavioural spike. Launches real `vim` (Git for
/// Windows' `vim.exe`, verified on `PATH`), types three distinguishable lines, then
/// sends the named `Up` key through the exact path `watch/input.rs` uses
/// (`pane.send_input {keys:["Up"]}`) followed by `x` (delete-under-cursor). Which
/// line loses a character reveals, unambiguously, whether Herdr moved the cursor
/// to the line above — i.e. whether it resolved vim's DECCKM (application cursor
/// key) mode for the named key, the question `docs/10-herdr-integration.md`
/// R-10-037 marks `[UNVERIFIED]`. `\r`, not `\n`, is Enter on this Windows pane's
/// console (measured: an earlier `\n`-terminated command never ran).
fn decckm_spike(client: &HerdrClient, workspace_id: &str) {
    let tab = client
        .call(
            "tab.create",
            json!({ "workspace_id": workspace_id, "focus": false }),
        )
        .expect("tab.create for decckm spike");
    let pane_id = tab["result"]["root_pane"]["pane_id"]
        .as_str()
        .expect("root_pane.pane_id")
        .to_string();

    send_text(
        client,
        &pane_id,
        "& 'C:\\Program Files\\Git\\usr\\bin\\vim.exe'\r",
    );
    thread::sleep(Duration::from_millis(1200));
    println!(
        "decckm spike: after vim launch: {}",
        summarize(&read_pane(client, &pane_id))
    );

    // Enter insert mode, type three lines, then restore normal mode.
    // Text uses the raw method unless it contains a newline.
    // Named keys use pane.send_input.
    send_text(client, &pane_id, "i");
    thread::sleep(Duration::from_millis(150));
    send_text(client, &pane_id, "AAAA\rBBBB\rCCCC");
    thread::sleep(Duration::from_millis(250));
    send_keys(client, &pane_id, &["Esc"]);
    thread::sleep(Duration::from_millis(250));
    println!(
        "decckm spike: after typing three lines: {}",
        summarize(&read_pane(client, &pane_id))
    );

    // The measurement. If Herdr resolved DECCKM correctly, Up moves to "BBBB" and
    // "x" removes a "B", leaving "BBB". If Herdr sent the wrong escape form for
    // vim's current mode, the cursor stays on "CCCC" (or the raw bytes leak some
    // other way) and "x" removes a "C" instead, or literal escape/bracket text
    // appears.
    send_keys(client, &pane_id, &["Up"]);
    thread::sleep(Duration::from_millis(250));
    send_text(client, &pane_id, "x");
    thread::sleep(Duration::from_millis(250));
    let after = read_pane(client, &pane_id);
    println!("decckm spike: after Up + x: {}", summarize(&after));

    // Quit vim without saving so the pane returns to a plain shell before this
    // binary's own teardown closes the scratch workspace.
    send_keys(client, &pane_id, &["Esc"]);
    thread::sleep(Duration::from_millis(150));
    send_text(client, &pane_id, ":q!");
    thread::sleep(Duration::from_millis(150));
    send_keys(client, &pane_id, &["Enter"]);
    thread::sleep(Duration::from_millis(300));
}

fn send_text(client: &HerdrClient, pane_id: &str, text: &str) {
    let method = if text.contains('\n') {
        "pane.send_input"
    } else {
        "pane.send_text"
    };
    client
        .call(method, json!({ "pane_id": pane_id, "text": text }))
        .expect("send text");
}

fn send_keys(client: &HerdrClient, pane_id: &str, keys: &[&str]) {
    client
        .call(
            "pane.send_input",
            json!({ "pane_id": pane_id, "keys": keys }),
        )
        .expect("pane.send_input keys");
}

/// A pane read reduced to what the spike measures. The text itself is never printed
/// (AGENTS.md "Never log"), even for the scratch pane this binary owns.
fn summarize(text: &str) -> String {
    format!(
        "lines={} has_BBBB={} has_BBB={} has_CCCC={} has_escape_literal={}",
        text.lines().count(),
        text.contains("BBBB"),
        text.contains("BBB"),
        text.contains("CCCC"),
        text.contains("^[") || text.contains("[200~")
    )
}

fn read_pane(client: &HerdrClient, pane_id: &str) -> String {
    let read: Value = client
        .call_result(
            "pane.read",
            json!({ "pane_id": pane_id, "source": "visible", "format": "ansi", "strip_ansi": false }),
            "read",
        )
        .expect("pane.read");
    read["text"].as_str().unwrap_or_default().to_string()
}

/// Measurement 3: the Phase 7 `Done when` manual test. Runs `sleep 60` in a fresh
/// pane, then sends `ctrl+c` through the real production path — `Bridge::watch_pane`
/// then `Bridge::send_input`, exactly what `watch/input.rs` runs for a Device —
/// and confirms the pane returns to its shell prompt instead of finishing the
/// full 60-second sleep.
fn ctrl_c_manual_test(client: &HerdrClient, workspace_id: &str) {
    let tab = client
        .call(
            "tab.create",
            json!({ "workspace_id": workspace_id, "focus": false }),
        )
        .expect("tab.create for ctrl+c test");
    let pane_id = tab["result"]["root_pane"]["pane_id"]
        .as_str()
        .expect("root_pane.pane_id")
        .to_string();

    send_text(client, &pane_id, "sleep 60\r");
    thread::sleep(Duration::from_millis(500));
    println!(
        "ctrl+c test: pane during sleep: {}",
        summarize(&read_pane(client, &pane_id))
    );

    let identity = HostIdentity {
        host_id: "spike-input".to_string(),
        host_name: "spike-input".to_string(),
    };
    let mut bridge = Bridge::new(client.clone(), identity, RelayConfig::default());
    bridge
        .watch_pane(WatchPane {
            pane_id: pane_id.clone(),
        })
        .expect("watch_pane for ctrl+c test");
    let ack = bridge
        .send_input(SendInput {
            defer: None,
            line: None,
            pane_id: pane_id.clone(),
            text: None,
            keys: Some(vec!["ctrl+c".to_string()]),
        })
        .expect("Bridge::send_input(ctrl+c)");
    println!("ctrl+c test: send_input_ack: {ack:?}");

    thread::sleep(Duration::from_millis(500));
    println!(
        "ctrl+c test: pane after ctrl+c: {}",
        summarize(&read_pane(client, &pane_id))
    );
}
