//! Throwaway probe shim: reads `{"method":..,"params":..}` lines on stdin, issues
//! each through the bridge's real `HerdrClient`, prints the reply envelope per line.
use std::io::{BufRead, Write};

use herdr_relay::config::RelayConfig;
use herdr_relay::ipc::HerdrClient;

fn main() {
    let client = HerdrClient::discover(&RelayConfig::default()).expect("herdr socket");
    let stdin = std::io::stdin();
    let mut out = std::io::stdout();
    for line in stdin.lock().lines() {
        let line = line.expect("stdin");
        let req: serde_json::Value = serde_json::from_str(&line).expect("json");
        let method = req["method"].as_str().expect("method");
        let reply = match client.call(method, req["params"].clone()) {
            Ok(v) => v,
            Err(e) => serde_json::json!({"error": {"code": format!("{e:?}")}}),
        };
        writeln!(out, "{reply}").unwrap();
        out.flush().unwrap();
    }
}
