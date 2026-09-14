//! The loopback control transport between the bridge and its local clients
//! (`docs/10-herdr-integration.md` §7, R-10-062 to R-10-067).
//!
//! The bridge is the server: it binds `127.0.0.1` on an ephemeral port, writes
//! the endpoint (pid, port, token) into `state.json` under `control`, serves
//! one JSON request per connection and removes the key on a clean exit
//! (R-10-062). The popup and `herdr-relay ctl` are the clients; both are
//! synchronous callers, so the client half uses `std::net` only.
//!
//! One connection carries one request: one JSON object and `\n`, at most
//! [`REQUEST_MAX_BYTES`] bytes, answered within [`IO_TIMEOUT`] by one JSON
//! object and `\n`, at most [`REPLY_MAX_BYTES`] bytes (R-10-063). The token
//! gates every request; `state.json` carries the paired-device list's
//! permissions through [`write_restricted_file`] (R-13-060), and no error or
//! log line ever carries the token, a reply body or a path (R-10-065).

use std::sync::Arc;
use std::time::Duration;

use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use rand::TryRng;
use rand::rngs::SysRng;
use serde::{Deserialize, Serialize};
use thiserror::Error;
use tokio::io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader};
use tokio::net::{TcpListener, TcpStream};

use crate::config::{
    ConfigError, ConfigPaths, FILE_READ_TIMEOUT, read_to_string_bounded, write_restricted_file,
};

/// The request line's maximum size in bytes, without the `\n` (R-10-063).
pub const REQUEST_MAX_BYTES: usize = 4096;
/// The reply line's maximum size in bytes, without the `\n` (R-10-063).
pub const REPLY_MAX_BYTES: usize = 65536;
/// The read/write bound on both halves of the transport (R-10-063).
pub const IO_TIMEOUT: Duration = Duration::from_secs(2);

/// The endpoint the bridge publishes in `state.json` (R-10-062). No `Debug`
/// derive: the token must never appear in a log line (R-10-065).
#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ControlEndpoint {
    pub pid: u32,
    pub port: u16,
    pub token: String,
}

/// Redacts the token (R-10-065).
impl std::fmt::Debug for ControlEndpoint {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ControlEndpoint")
            .field("pid", &self.pid)
            .field("port", &self.port)
            .field("token", &"<redacted>")
            .finish()
    }
}

/// Endpoint-file failures. Every `Display` string is fixed text.
#[derive(Debug, Error)]
pub enum ControlError {
    #[error("reading the pairing state file failed")]
    Read(#[source] std::io::Error),
    #[error("the pairing state file is not valid JSON")]
    Parse(#[source] serde_json::Error),
    #[error("the pairing state file is not a JSON object")]
    NotAnObject,
    #[error("writing the pairing state file failed")]
    Write(#[source] ConfigError),
}

/// The endpoint token: 32 random bytes from the R-11-112 source, unpadded
/// base64url (43 characters, R-10-062). New on every bridge start.
pub fn new_token() -> String {
    let mut bytes = [0u8; 32];
    SysRng
        .try_fill_bytes(&mut bytes)
        .expect("the system random source is available (R-11-112)");
    URL_SAFE_NO_PAD.encode(bytes)
}

/// Reads `state.json`. `Ok(None)` is a missing file (R-10-062); any existing
/// content must be one JSON object.
fn read_state(
    paths: &ConfigPaths,
) -> Result<Option<serde_json::Map<String, serde_json::Value>>, ControlError> {
    let text = match read_to_string_bounded(&paths.state_file(), FILE_READ_TIMEOUT) {
        Ok(text) => text,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(ControlError::Read(error)),
    };
    match serde_json::from_str(&text).map_err(ControlError::Parse)? {
        serde_json::Value::Object(map) => Ok(Some(map)),
        _ => Err(ControlError::NotAnObject),
    }
}

/// Writes `state.json` through the restricted writer, so the token carries
/// the paired-device list's permissions (R-13-060).
fn write_state(
    paths: &ConfigPaths,
    state: serde_json::Map<String, serde_json::Value>,
) -> Result<(), ControlError> {
    let body = serde_json::to_string(&serde_json::Value::Object(state))
        .expect("a serde_json::Value always serializes");
    write_restricted_file(&paths.state_file(), body.as_bytes()).map_err(ControlError::Write)
}

/// Writes the `control` key of R-10-062, preserving every other top-level
/// key; a missing file starts as an empty object.
pub fn write_endpoint(paths: &ConfigPaths, endpoint: &ControlEndpoint) -> Result<(), ControlError> {
    let mut state = read_state(paths)?.unwrap_or_default();
    let value = serde_json::to_value(endpoint).expect("a derived struct always serializes");
    state.insert("control".to_owned(), value);
    write_state(paths, state)
}

/// Removes the `control` key on a clean exit (R-10-062), preserving every
/// other top-level key. A missing file is already clear.
pub fn clear_endpoint(paths: &ConfigPaths) -> Result<(), ControlError> {
    let Some(mut state) = read_state(paths)? else {
        return Ok(());
    };
    state.remove("control");
    write_state(paths, state)
}

/// The endpoint a client dials. `Ok(None)` when `state.json` or its `control`
/// key is missing — R-10-062's "the bridge is not running".
pub fn read_endpoint(paths: &ConfigPaths) -> Result<Option<ControlEndpoint>, ControlError> {
    let Some(mut state) = read_state(paths)? else {
        return Ok(None);
    };
    state
        .remove("control")
        .map(|value| serde_json::from_value(value).map_err(ControlError::Parse))
        .transpose()
}

/// The commands of R-10-064.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "command", rename_all = "snake_case")]
pub enum Command {
    Status,
    OpenPairing,
    ClosePairing,
    Revoke { device_id: String },
    RevokeAll,
    Stop,
}

/// One request: the token plus the flattened command (R-10-064). No `Debug`
/// derive: the token must never appear in a log line (R-10-065).
#[derive(Serialize, Deserialize)]
pub struct Request {
    pub token: String,
    #[serde(flatten)]
    pub command: Command,
}

/// The reply error codes of R-10-064.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ErrorCode {
    Unauthorized,
    BadRequest,
    UnknownCommand,
    NotFound,
}

/// The bridge's status object (R-10-064).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Status {
    pub relay_origin: String,
    pub link: LinkStatus,
    pub pairing: Option<PairingStatus>,
    pub devices: Vec<DeviceRow>,
}

/// The relay link summary (R-10-064).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LinkStatus {
    pub state: LinkState,
    pub attempt: u32,
    pub error: Option<String>,
}

/// The link states of R-10-064.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LinkState {
    Connected,
    Idle,
    Offline,
    Stopped,
}

/// The open pairing, or `null` in the `pairing` field when none is open
/// (R-10-064). While `registered` is false, `uri`, `phrase` and `handle` are
/// `null` and the pane shows no credential.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PairingStatus {
    pub registered: bool,
    pub uri: Option<String>,
    pub phrase: Option<String>,
    pub handle: Option<String>,
    pub expires_in_s: u64,
}

/// One paired device in the status object. Carries the R-13-040 fingerprint,
/// never the raw key (R-13-070) and never the handle (R-10-064).
/// `os_version` rides along for the pane's Platform column (R-31-16-18 reads
/// `platform` and `os_version` from the stored record).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DeviceRow {
    pub device_id: String,
    pub device_name: String,
    pub platform: herdr_relay_proto::messages::Platform,
    pub os_version: String,
    pub fingerprint: String,
    pub paired_at: String,
    pub last_seen: String,
    pub connected: bool,
}

/// The bridge's command sink. Every command MUST answer from the bridge's own
/// in-memory state, with no relay round trip inside the request, so every
/// reply fits the R-10-063 window.
pub trait Handler: Send + Sync + 'static {
    fn handle(&self, command: Command) -> Result<serde_json::Value, ErrorCode>;
}

/// Binds the loopback control listener on an ephemeral port (R-10-062).
pub async fn bind() -> std::io::Result<(TcpListener, u16)> {
    let listener = TcpListener::bind((std::net::Ipv4Addr::LOCALHOST, 0)).await?;
    let port = listener.local_addr()?.port();
    Ok((listener, port))
}

/// Serves control requests until the listener drops. Every connection is
/// handled on its own task; the bridge stops the control plane by dropping
/// the task this future runs on.
pub async fn serve(listener: TcpListener, token: String, handler: Arc<dyn Handler>) {
    loop {
        let Ok((stream, _peer)) = listener.accept().await else {
            return;
        };
        let token = token.clone();
        let handler = Arc::clone(&handler);
        tokio::spawn(async move {
            handle_connection(stream, &token, handler).await;
        });
    }
}

/// One connection: one bounded line in, one bounded reply out, then close
/// (R-10-063).
async fn handle_connection(stream: TcpStream, token: &str, handler: Arc<dyn Handler>) {
    let (read_half, mut write_half) = stream.into_split();
    let mut line = String::new();
    // The cap reads one byte past the limit: a line that long without a `\n`
    // is over 4096 bytes and closes without a reply (R-10-063).
    let read = tokio::time::timeout(
        IO_TIMEOUT,
        BufReader::new(read_half)
            .take(REQUEST_MAX_BYTES as u64 + 1)
            .read_line(&mut line),
    )
    .await;
    let Ok(Ok(_)) = read else {
        return; // a timeout or an I/O error: close without a reply
    };
    if !line.ends_with('\n') {
        return; // oversize, truncated or empty: close without a reply
    }
    let Ok(value) = serde_json::from_str::<serde_json::Value>(&line) else {
        return; // not one JSON object: close without a reply
    };
    if !value.is_object() {
        return;
    }
    let reply = match classify(value, token) {
        Ok(command) => match handler.handle(command) {
            Ok(result) => serde_json::json!({ "ok": true, "result": result }),
            Err(code) => serde_json::json!({ "ok": false, "error": code }),
        },
        Err(code) => serde_json::json!({ "ok": false, "error": code }),
    };
    let mut body = serde_json::to_string(&reply).expect("a serde_json::Value always serializes");
    if body.len() > REPLY_MAX_BYTES {
        // A reply over the cap is an internal bug. The line is fixed text; it
        // carries none of the reply's content (R-10-065).
        eprintln!("herdr-relay: a control reply exceeded the reply cap; closing without a reply");
        return;
    }
    body.push('\n');
    let _ = tokio::time::timeout(IO_TIMEOUT, write_half.write_all(body.as_bytes())).await;
}

/// The `command` values R-10-064 defines; any other string is
/// `unknown_command`.
const KNOWN_COMMANDS: [&str; 6] = [
    "status",
    "open_pairing",
    "close_pairing",
    "revoke",
    "revoke_all",
    "stop",
];

/// Classifies one parsed request object into a command or an R-10-064 error
/// code: `unauthorized` for a bad or missing token, `unknown_command` for a
/// command string outside [`KNOWN_COMMANDS`], `bad_request` for every other
/// missing or malformed field.
fn classify(value: serde_json::Value, token: &str) -> Result<Command, ErrorCode> {
    if value.get("token").and_then(serde_json::Value::as_str) != Some(token) {
        return Err(ErrorCode::Unauthorized);
    }
    match value.get("command").cloned() {
        Some(serde_json::Value::String(name)) if KNOWN_COMMANDS.contains(&name.as_str()) => {
            serde_json::from_value::<Request>(value)
                .map(|request| request.command)
                .map_err(|_| ErrorCode::BadRequest)
        }
        Some(serde_json::Value::String(_)) => Err(ErrorCode::UnknownCommand),
        _ => Err(ErrorCode::BadRequest),
    }
}

/// A client-side failure. Every `Display` string is fixed text; no token,
/// reply body or path ever appears (R-10-065).
#[derive(Debug, Error)]
pub enum ClientError {
    /// R-10-062's "the bridge is not running": no endpoint, a refused
    /// connection or an `unauthorized` reply.
    #[error("the bridge is not running")]
    NotRunning,
    #[error("the control connection failed")]
    Io(#[source] std::io::Error),
    /// The reply failed the R-10-063 shape. The message is a fixed string and
    /// never carries the reply body.
    #[error("the bridge reply failed the protocol: {0}")]
    Protocol(String),
    #[error("the bridge rejected the command ({0:?})")]
    Rejected(ErrorCode),
}

/// Sends one command to the running bridge and returns its `result`
/// (R-10-063, R-10-064). Blocking by design: the popup and `ctl` are
/// synchronous callers, and the loopback round trip is bounded by
/// [`IO_TIMEOUT`].
///
/// `pid` is informational only (R-10-062): a client never tests it, because a
/// reused pid proves nothing. A dead bridge's port refuses the connection, and
/// a foreign listener on a reused port fails the token check; both map to
/// [`ClientError::NotRunning`], as does a malformed `control` value.
pub fn request(paths: &ConfigPaths, command: &Command) -> Result<serde_json::Value, ClientError> {
    use std::io::Write as _;

    // A corrupt state file yields no usable endpoint: not running.
    let endpoint = read_endpoint(paths)
        .map_err(|_| ClientError::NotRunning)?
        .ok_or(ClientError::NotRunning)?;
    let mut stream =
        match std::net::TcpStream::connect((std::net::Ipv4Addr::LOCALHOST, endpoint.port)) {
            Ok(stream) => stream,
            Err(error) if error.kind() == std::io::ErrorKind::ConnectionRefused => {
                return Err(ClientError::NotRunning);
            }
            Err(error) => return Err(ClientError::Io(error)),
        };
    stream
        .set_read_timeout(Some(IO_TIMEOUT))
        .map_err(ClientError::Io)?;
    stream
        .set_write_timeout(Some(IO_TIMEOUT))
        .map_err(ClientError::Io)?;
    let request = Request {
        token: endpoint.token,
        command: command.clone(),
    };
    let mut body = serde_json::to_string(&request)
        .map_err(|_| ClientError::Protocol("serializing a control request failed".to_owned()))?;
    body.push('\n');
    stream.write_all(body.as_bytes()).map_err(ClientError::Io)?;
    read_reply(&stream)
}

/// Reads the one reply line, bounded to [`REPLY_MAX_BYTES`] (R-10-063), and
/// decodes the R-10-064 envelope.
fn read_reply(stream: &std::net::TcpStream) -> Result<serde_json::Value, ClientError> {
    use std::io::BufRead as _;

    let deadline = std::time::Instant::now() + IO_TIMEOUT;
    let mut reader = std::io::BufReader::new(stream);
    let mut line = Vec::new();
    while line.len() <= REPLY_MAX_BYTES && !line.ends_with(b"\n") {
        let remaining = deadline
            .checked_duration_since(std::time::Instant::now())
            .filter(|remaining| !remaining.is_zero())
            .ok_or_else(|| ClientError::Io(std::io::ErrorKind::TimedOut.into()))?;
        stream
            .set_read_timeout(Some(remaining))
            .map_err(ClientError::Io)?;
        let available = reader.fill_buf().map_err(ClientError::Io)?;
        if available.is_empty() {
            break;
        }
        let count = available.len().min(REPLY_MAX_BYTES + 1 - line.len());
        let count = available[..count]
            .iter()
            .position(|byte| *byte == b'\n')
            .map_or(count, |index| index + 1);
        line.extend_from_slice(&available[..count]);
        reader.consume(count);
    }
    if line.is_empty() {
        return Err(ClientError::Protocol(
            "the bridge closed without a reply".to_owned(),
        ));
    }
    if !line.ends_with(b"\n") {
        return Err(ClientError::Protocol(
            "the reply was truncated or over the size cap".to_owned(),
        ));
    }
    let reply: serde_json::Value = serde_json::from_slice(&line)
        .map_err(|_| ClientError::Protocol("the reply was not one JSON object".to_owned()))?;
    match reply.get("ok").and_then(serde_json::Value::as_bool) {
        Some(true) => reply
            .get("result")
            .cloned()
            .ok_or_else(|| ClientError::Protocol("an ok reply without a result".to_owned())),
        Some(false) => match reply.get("error").and_then(serde_json::Value::as_str) {
            // R-10-062: an `unauthorized` reply means "the bridge is not running".
            Some("unauthorized") => Err(ClientError::NotRunning),
            Some(code) => {
                match serde_json::from_value::<ErrorCode>(serde_json::Value::String(
                    code.to_owned(),
                )) {
                    Ok(code) => Err(ClientError::Rejected(code)),
                    Err(_) => Err(ClientError::Protocol("an unknown error code".to_owned())),
                }
            }
            None => Err(ClientError::Protocol(
                "an error reply without a code".to_owned(),
            )),
        },
        None => Err(ClientError::Protocol(
            "a reply without an ok flag".to_owned(),
        )),
    }
}

/// The bridge's status object (R-10-064), for the popup and `ctl status`.
pub fn status(paths: &ConfigPaths) -> Result<Status, ClientError> {
    let value = request(paths, &Command::Status)?;
    serde_json::from_value(value)
        .map_err(|_| ClientError::Protocol("the status object was malformed".to_owned()))
}

/// The exact notice the popup shows when the bridge is not running
/// (R-10-066).
pub fn not_running_notice() -> &'static str {
    "bridge not running - start herdr-relay first (the service starts it at login)"
}

#[cfg(test)]
mod tests {
    use std::io::Write as _;

    use herdr_relay_proto::messages::Platform;

    use super::*;

    fn temp_paths(tag: &str) -> ConfigPaths {
        ConfigPaths::new(std::env::temp_dir().join(format!(
            "herdr-relay-control-test-{tag}-{}",
            std::process::id()
        )))
    }

    /// The `registering...` state (R-10-064): no credential appears in a test
    /// fixture, so a failed `assert_eq!` can never print one.
    fn fixture_status() -> Status {
        Status {
            relay_origin: "https://relay.example.com".to_owned(),
            link: LinkStatus {
                state: LinkState::Connected,
                attempt: 0,
                error: None,
            },
            pairing: Some(PairingStatus {
                registered: false,
                uri: None,
                phrase: None,
                handle: None,
                expires_in_s: 87,
            }),
            devices: vec![DeviceRow {
                device_id: "device-1".to_owned(),
                device_name: "Pixel".to_owned(),
                platform: Platform::Android,
                os_version: "15".to_owned(),
                fingerprint: "xxxx-xxxx-xxxx-xxxx".to_owned(),
                paired_at: "2026-01-01T00:00:00Z".to_owned(),
                last_seen: "2026-01-02T00:00:00Z".to_owned(),
                connected: true,
            }],
        }
    }

    struct Stub;

    impl Handler for Stub {
        fn handle(&self, command: Command) -> Result<serde_json::Value, ErrorCode> {
            match command {
                Command::Status => Ok(serde_json::to_value(fixture_status())
                    .expect("a derived struct always serializes")),
                Command::Revoke { .. } => Err(ErrorCode::NotFound),
                _ => Ok(serde_json::json!({})),
            }
        }
    }

    /// Binds, serves and publishes the endpoint; returns the server's token.
    async fn start_stub_server(paths: &ConfigPaths) -> String {
        let (listener, port) = bind().await.expect("bind a loopback listener");
        let token = new_token();
        write_endpoint(
            paths,
            &ControlEndpoint {
                pid: std::process::id(),
                port,
                token: token.clone(),
            },
        )
        .expect("write the endpoint");
        tokio::spawn(serve(listener, token.clone(), Arc::new(Stub)));
        token
    }

    /// Sends one raw request body and reads the raw reply to the server's
    /// close; `None` means the server closed without a reply.
    fn raw_round_trip(port: u16, body: &str) -> Option<String> {
        use std::io::Read as _;

        let mut stream = std::net::TcpStream::connect((std::net::Ipv4Addr::LOCALHOST, port))
            .expect("connect to the stub server");
        stream
            .set_read_timeout(Some(IO_TIMEOUT))
            .expect("set the read timeout");
        stream.write_all(body.as_bytes()).expect("send the request");
        let mut reply = Vec::new();
        // A closed-with-unread-data socket can report a reset instead of EOF;
        // both prove the server sent no reply.
        match stream.read_to_end(&mut reply) {
            Ok(_) if reply.is_empty() => None,
            Ok(_) => Some(String::from_utf8(reply).expect("the reply is UTF-8")),
            Err(_) => None,
        }
    }

    #[tokio::test]
    async fn status_round_trips_and_revoke_is_rejected() {
        let paths = temp_paths("roundtrip");
        start_stub_server(&paths).await;

        let client_paths = paths.clone();
        let status = tokio::task::spawn_blocking(move || status(&client_paths))
            .await
            .expect("join the client call")
            .expect("status succeeds");
        assert_eq!(status, fixture_status());

        let client_paths = paths.clone();
        let error = tokio::task::spawn_blocking(move || {
            request(
                &client_paths,
                &Command::Revoke {
                    device_id: "no-such-device".to_owned(),
                },
            )
        })
        .await
        .expect("join the client call")
        .expect_err("an unknown device_id is rejected");
        assert!(
            matches!(error, ClientError::Rejected(ErrorCode::NotFound)),
            "revoke of an unknown device_id is not_found"
        );

        std::fs::remove_dir_all(paths.dir()).ok();
    }

    #[tokio::test]
    async fn a_wrong_token_is_unauthorized_and_reports_not_running() {
        let paths = temp_paths("token");
        let server_token = start_stub_server(&paths).await;
        // Overwrite the endpoint with a token the server does not hold.
        let port = read_endpoint(&paths)
            .expect("read the endpoint back")
            .expect("the endpoint exists")
            .port;
        write_endpoint(
            &paths,
            &ControlEndpoint {
                pid: std::process::id(),
                port,
                token: new_token(),
            },
        )
        .expect("write a stale endpoint");

        let client_paths = paths.clone();
        let error = tokio::task::spawn_blocking(move || request(&client_paths, &Command::Status))
            .await
            .expect("join the client call")
            .expect_err("a wrong token is rejected");
        assert!(
            matches!(error, ClientError::NotRunning),
            "R-10-062: an unauthorized reply is 'the bridge is not running'"
        );

        // The server answered `unauthorized`, not a silent close.
        let body = format!("{{\"token\":\"{server_token}\",\"command\":\"status\"}}\n")
            .replace(&server_token, "wrong-token");
        let reply = tokio::task::spawn_blocking(move || raw_round_trip(port, &body))
            .await
            .expect("join the raw call")
            .expect("the server replies to a wrong token");
        let reply: serde_json::Value =
            serde_json::from_str(&reply).expect("the reply is one JSON object");
        assert_eq!(
            reply,
            serde_json::json!({"ok": false, "error": "unauthorized"})
        );

        std::fs::remove_dir_all(paths.dir()).ok();
    }

    #[tokio::test]
    async fn an_oversize_request_is_closed_without_a_reply() {
        let paths = temp_paths("oversize");
        let token = start_stub_server(&paths).await;
        let port = read_endpoint(&paths)
            .expect("read the endpoint back")
            .expect("the endpoint exists")
            .port;

        let body = format!(
            "{{\"token\":\"{token}\",\"command\":\"status\",\"pad\":\"{}\"}}\n",
            "x".repeat(5000)
        );
        let reply = tokio::task::spawn_blocking(move || raw_round_trip(port, &body))
            .await
            .expect("join the raw call");
        assert!(
            reply.is_none(),
            "R-10-063: a request over 4096 bytes closes without a reply"
        );

        std::fs::remove_dir_all(paths.dir()).ok();
    }

    #[tokio::test]
    async fn unknown_command_and_malformed_revoke_are_rejected() {
        let paths = temp_paths("classify");
        let token = start_stub_server(&paths).await;
        let port = read_endpoint(&paths)
            .expect("read the endpoint back")
            .expect("the endpoint exists")
            .port;

        let body = format!("{{\"token\":\"{token}\",\"command\":\"frobnicate\"}}\n");
        let reply = tokio::task::spawn_blocking(move || raw_round_trip(port, &body))
            .await
            .expect("join the raw call")
            .expect("the server replies to an unknown command");
        let reply: serde_json::Value =
            serde_json::from_str(&reply).expect("the reply is one JSON object");
        assert_eq!(
            reply,
            serde_json::json!({"ok": false, "error": "unknown_command"})
        );

        let body = format!("{{\"token\":\"{token}\",\"command\":\"revoke\"}}\n");
        let reply = tokio::task::spawn_blocking(move || raw_round_trip(port, &body))
            .await
            .expect("join the raw call")
            .expect("the server replies to a malformed revoke");
        let reply: serde_json::Value =
            serde_json::from_str(&reply).expect("the reply is one JSON object");
        assert_eq!(
            reply,
            serde_json::json!({"ok": false, "error": "bad_request"}),
            "a revoke without device_id is bad_request (R-10-064)"
        );

        std::fs::remove_dir_all(paths.dir()).ok();
    }

    #[test]
    fn a_missing_state_file_reports_not_running() {
        let paths = temp_paths("missing");
        let error = request(&paths, &Command::Status)
            .expect_err("a missing state.json means the bridge is not running");
        assert!(matches!(error, ClientError::NotRunning));
    }

    #[test]
    fn write_and_clear_endpoint_preserve_other_top_level_keys() {
        let paths = temp_paths("preserve");
        write_restricted_file(
            &paths.state_file(),
            b"{\"pairing\":{\"open\":true}}".as_slice(),
        )
        .expect("seed state.json with another key");
        let endpoint = ControlEndpoint {
            pid: 12345,
            port: 49321,
            token: "test-token".to_owned(),
        };
        write_endpoint(&paths, &endpoint).expect("write the endpoint");
        let read = read_endpoint(&paths)
            .expect("read the endpoint back")
            .expect("the endpoint exists");
        assert_eq!(read, endpoint);

        clear_endpoint(&paths).expect("clear the endpoint");
        assert_eq!(
            read_endpoint(&paths).expect("read the cleared state file"),
            None
        );
        let state: serde_json::Value = serde_json::from_str(
            &std::fs::read_to_string(paths.state_file()).expect("read state.json"),
        )
        .expect("state.json is valid JSON");
        assert_eq!(
            state,
            serde_json::json!({"pairing": {"open": true}}),
            "clear removes only the control key"
        );
        std::fs::remove_dir_all(paths.dir()).ok();
    }

    #[test]
    fn new_token_is_43_unpadded_base64url_characters() {
        let token = new_token();
        assert_eq!(token.len(), 43, "32 bytes, unpadded base64url");
        assert!(
            token
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_'),
            "the base64url alphabet only"
        );
        assert_ne!(new_token(), token, "new on every bridge start");
    }

    #[test]
    fn request_serializes_with_a_snake_case_command_tag() {
        let request = Request {
            token: "t".to_owned(),
            command: Command::Revoke {
                device_id: "d".to_owned(),
            },
        };
        assert_eq!(
            serde_json::to_value(&request).expect("serialize the request"),
            serde_json::json!({"token": "t", "command": "revoke", "device_id": "d"})
        );
        let parsed: Request =
            serde_json::from_value(serde_json::json!({"token": "t", "command": "stop"}))
                .expect("parse a unit command");
        assert_eq!(parsed.command, Command::Stop);
    }

    #[test]
    fn not_running_notice_is_the_exact_r_10_066_text() {
        assert_eq!(
            not_running_notice(),
            "bridge not running - start herdr-relay first (the service starts it at login)"
        );
    }

    #[test]
    fn a_partial_reply_does_not_extend_the_reply_deadline() {
        use std::io::Write as _;

        let listener = std::net::TcpListener::bind((std::net::Ipv4Addr::LOCALHOST, 0))
            .expect("bind loopback listener");
        let address = listener.local_addr().expect("listener address");
        let server = std::thread::spawn(move || {
            let (mut stream, _) = listener.accept().expect("accept client");
            for _ in 0..5 {
                if stream.write_all(b" ").is_err() {
                    return;
                }
                std::thread::sleep(Duration::from_millis(600));
            }
            let _ = stream.write_all(b"{\"ok\":true,\"result\":{}}\n");
        });
        let client = std::net::TcpStream::connect(address).expect("connect client");
        client
            .set_read_timeout(Some(IO_TIMEOUT))
            .expect("set read timeout");
        let result = read_reply(&client);
        drop(client);
        server.join().expect("join reply server");
        assert!(matches!(
            result,
            Err(ClientError::Io(error))
                if matches!(
                    error.kind(),
                    std::io::ErrorKind::TimedOut | std::io::ErrorKind::WouldBlock
                )
        ));
    }
}
