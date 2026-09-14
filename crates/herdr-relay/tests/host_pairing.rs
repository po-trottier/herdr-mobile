//! The Phase 25 proof (`docs/90-implementation-plan.md`): the real bridge
//! (`herdr_relay::bridge`) against a fake in-process relay, driving the
//! Device half of the wire protocol by hand — the same fake-server pattern
//! `tests/relay_connection.rs` and `tests/revoke.rs` use (a sibling crate's
//! binary would couple this crate to another package's build).
//!
//! Covered, end to end through the library API (`bridge::start` plus the
//! control handler):
//!
//! a. `open_pairing`, then a Device `Noise_XXpsk0` handshake plus
//!    `device_info`, writes a store entry with a 22-character handle and a
//!    UUIDv4 `host_id`, and `status` shows the device `connected`
//!    (R-13-035, R-13-049, R-10-064);
//! b. after that session ends, a `Noise_KK` initiator on the same handle
//!    with the pinned keys gets `host_info.paired == true` (R-13-037);
//! c. a second Device completing a handshake while one session is live is
//!    closed with `4006` and the first session is untouched (R-10-069);
//! d. `revoke` removes the entry, closes the live session with the `revoked`
//!    error and `4004` (R-13-053), and the handle is never registered again;
//! e. control `status` round-trips with and without an open pairing, with
//!    `registered` flipping true only after `session_joined` (R-10-064);
//! f. no captured log line contains the phrase, the handle or a device id
//!    (R-10-065);
//! g. a `Noise_KK` registration stays held with no Device for more than
//!    `CONNECT_TIMEOUT` (a relay heartbeat `Ping` in that period included),
//!    and the handshake after it still completes with `paired == true`
//!    (R-11-120: the pairing window applies only to a first pairing);
//! h. a pairing no Device joined after 600 s is destroyed — `status`
//!    reads `pairing: null` and nothing re-registers (R-13-022);
//! i. three failed handshakes spend the phrase and the handle with no
//!    replacement: the same handle is re-registered between attempts, then
//!    nothing, until a fresh `open_pairing` (R-13-023);
//! j. every Device request the bridge dispatches is answered on the same
//!    session with the request's `corr` echoed: `device_list_request`,
//!    `scroll_request`, `action_list_request`, `host_action` and
//!    `revoke_device` (the Herdr-backed ones answer with the `error` frame
//!    the absent stub Herdr produces, exactly like (c)'s probe); a
//!    `revoke_device` naming the connected Device itself gets its
//!    `revoke_result` before the fatal `revoked` error and the 4004 close
//!    (R-11-063, R-11-064, R-11-065); `unwatch_pane` gets no reply and
//!    leaves the session serving (R-11-050).

use std::collections::HashSet;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use futures_util::{FutureExt, SinkExt, StreamExt};
use tokio::net::{TcpListener, TcpStream};
use tokio_tungstenite::WebSocketStream;
use tokio_tungstenite::tungstenite::Message as WsMessage;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::protocol::CloseFrame;

use herdr_relay::bridge::{self, HostConfig, HostHandle};
use herdr_relay::config::{ConfigPaths, RelayConfig};
use herdr_relay::control::{self, Command};
use herdr_relay::frame_codec::{self, Reassembler};
use herdr_relay::ipc::{EXPECTED_PROTOCOL, HerdrClient};
use herdr_relay::keys::HostKeypair;
use herdr_relay::noise::{self, Role, Transport};
use herdr_relay::store::DeviceStore;
use herdr_relay_proto::codes::CloseCode;
use herdr_relay_proto::frame::{Frame, SequenceCounter};
use herdr_relay_proto::handle::Handle;
use herdr_relay_proto::messages::{
    ActionListRequest, DeviceInfo, DeviceListRequest, Disconnect, HostAction, HostActionKind,
    HostInfo, Message, Platform, RevokeDevice, ScrollRequest, UnwatchPane,
};

/// The relay subprotocol every connection MUST offer (R-11-013, R-12-020).
const SUBPROTOCOL: &str = "herdr-relay.v1";

fn temp_paths(tag: &str) -> ConfigPaths {
    let dir = std::env::temp_dir().join(format!(
        "herdr-relay-host-pairing-{tag}-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("the system clock is after the Unix epoch")
            .as_nanos()
    ));
    std::fs::remove_dir_all(&dir).ok();
    ConfigPaths::new(dir)
}

/// A synthetic 7776-entry fixture, matching `pairing.rs`'s own test
/// convention (R-13-025 forbids committing the real EFF list).
fn word_list() -> Vec<String> {
    const POOL: [&str; 6] = [
        "remedy",
        "tapestry",
        "hubcap",
        "oversleep",
        "jailbird",
        "kinetic",
    ];
    (0..7776)
        .map(|i| POOL[i % POOL.len()].to_string())
        .collect()
}

// ---------------------------------------------------------------------------
// The fake relay
// ---------------------------------------------------------------------------

/// One accepted Host registration: the handle from the URL path and the
/// still-open WebSocket, for the test to drive the Device's half over.
struct IncomingHost {
    handle: String,
    socket: WebSocketStream<TcpStream>,
}

/// A fake relay: accepts every `/host/<handle>` registration, answers
/// `session_joined` (R-11-113/R-11-115), and hands the socket to the test.
/// A `/device/<handle>` connection with no live Host registration is refused
/// with `handle_unknown` and close code `4001` (R-11-117) — the refusal a
/// revoked Device meets once the bridge holds no registration (R-11-125: the
/// registration lives exactly as long as the Host's connection, which the
/// test models explicitly through [`FakeRelay::host_closed`]).
struct FakeRelay {
    origin: String,
    incoming: tokio::sync::mpsc::UnboundedReceiver<IncomingHost>,
    registrations: Arc<Mutex<Vec<String>>>,
    live: Arc<Mutex<HashSet<String>>>,
    task: tokio::task::JoinHandle<()>,
}

impl FakeRelay {
    async fn start() -> Self {
        let listener = TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind a local test port");
        let addr: SocketAddr = listener.local_addr().expect("read the bound address");
        let (tx, incoming) = tokio::sync::mpsc::unbounded_channel();
        let registrations = Arc::new(Mutex::new(Vec::new()));
        let live = Arc::new(Mutex::new(HashSet::new()));
        let task = tokio::spawn(accept_loop(
            listener,
            tx,
            Arc::clone(&registrations),
            Arc::clone(&live),
        ));
        Self {
            origin: format!("ws://{addr}"),
            incoming,
            registrations,
            live,
            task,
        }
    }

    async fn accept_host(&mut self) -> IncomingHost {
        tokio::time::timeout(Duration::from_secs(5), self.incoming.recv())
            .await
            .expect("a host registration arrives within 5 s")
            .expect("the accept loop lives")
    }

    /// Every registration ever accepted for `handle` (the bridge's reconnect
    /// ladder shows up here as repeat entries).
    fn registration_count(&self, handle: &str) -> usize {
        self.registrations
            .lock()
            .expect("registrations lock")
            .iter()
            .filter(|registered| *registered == handle)
            .count()
    }

    /// The bridge's connection for `handle` ended, so the relay-side
    /// registration is gone (R-11-125).
    fn host_closed(&self, handle: &str) {
        self.live.lock().expect("live lock").remove(handle);
    }
}

impl Drop for FakeRelay {
    fn drop(&mut self) {
        self.task.abort();
    }
}

/// The upgrade callback's concrete types, aliased so the closure below can
/// name them (tungstenite's `accept_hdr_async` needs the fully annotated
/// closure form once it captures state).
type UpgradeRequest = tokio_tungstenite::tungstenite::handshake::server::Request;
type UpgradeResponse = tokio_tungstenite::tungstenite::handshake::server::Response;
type UpgradeReply =
    Result<UpgradeResponse, tokio_tungstenite::tungstenite::handshake::server::ErrorResponse>;

// The upgrade callback's Err is tungstenite's own Response; not this test's
// type to box.
#[allow(clippy::result_large_err)]
async fn accept_loop(
    listener: TcpListener,
    tx: tokio::sync::mpsc::UnboundedSender<IncomingHost>,
    registrations: Arc<Mutex<Vec<String>>>,
    live: Arc<Mutex<HashSet<String>>>,
) {
    loop {
        let Ok((stream, _addr)) = listener.accept().await else {
            return;
        };
        let tx = tx.clone();
        let registrations = Arc::clone(&registrations);
        let live = Arc::clone(&live);
        tokio::spawn(async move {
            let path = Arc::new(Mutex::new(None));
            let seen = Arc::clone(&path);
            // Echoes the requested subprotocol so the client-side check
            // accepts this fake server (R-11-013), and records the URL path
            // for the /host vs /device split below.
            let mut socket = tokio_tungstenite::accept_hdr_async(
                stream,
                move |request: &UpgradeRequest, mut response: UpgradeResponse| -> UpgradeReply {
                    *seen.lock().expect("path lock") = Some(request.uri().path().to_owned());
                    if let Some(protocol) = request.headers().get("sec-websocket-protocol") {
                        response
                            .headers_mut()
                            .insert("sec-websocket-protocol", protocol.clone());
                    }
                    Ok(response)
                },
            )
            .await
            .expect("complete the websocket upgrade");
            let path = path.lock().expect("path lock").clone().expect("a URL path");
            if let Some(handle) = path.strip_prefix("/host/") {
                let register = socket
                    .next()
                    .await
                    .expect("a registration message arrives")
                    .expect("no websocket I/O error");
                assert!(
                    matches!(&register, WsMessage::Text(text) if text.contains("host_register")),
                    "expected host_register"
                );
                registrations
                    .lock()
                    .expect("registrations lock")
                    .push(handle.to_owned());
                live.lock().expect("live lock").insert(handle.to_owned());
                socket
                    .send(WsMessage::Text(r#"{"type":"session_joined"}"#.into()))
                    .await
                    .expect("send session_joined");
                let _ = tx.send(IncomingHost {
                    handle: handle.to_owned(),
                    socket,
                });
            } else if let Some(handle) = path.strip_prefix("/device/") {
                // Only the refusal path is within this test's scope: a Device
                // never reaches a live Host through the fake (the test drives
                // the Device's half on the Host's own socket instead).
                if !live.lock().expect("live lock").contains(handle) {
                    socket
                        .send(WsMessage::Text(
                            r#"{"type":"error","code":"handle_unknown","message":"No Host is registered under this handle."}"#.into(),
                        ))
                        .await
                        .expect("send handle_unknown");
                    let _ = socket
                        .send(WsMessage::Close(Some(CloseFrame {
                            code: CloseCode::HandleUnknown.code().into(),
                            reason: String::new().into(),
                        })))
                        .await;
                }
            }
        });
    }
}

// ---------------------------------------------------------------------------
// The Device's half of the wire protocol, driven by hand
// ---------------------------------------------------------------------------

async fn next_binary(socket: &mut WebSocketStream<TcpStream>, label: &str) -> Vec<u8> {
    match socket
        .next()
        .await
        .unwrap_or_else(|| panic!("{label}: the fake relay socket closed early"))
        .unwrap_or_else(|err| panic!("{label}: websocket error: {err}"))
    {
        WsMessage::Binary(bytes) => bytes.to_vec(),
        other => panic!("expected a binary message, got {other:?}"),
    }
}

/// The Device's `Noise_XXpsk0` initiator half (R-13-071: the Device sends
/// first), returning the transport and the Host's static public key (pinned
/// for later `Noise_KK` reconnects, R-13-048).
async fn device_pairing_handshake(
    socket: &mut WebSocketStream<TcpStream>,
    device_private: &[u8; 32],
    psk: &[u8; 32],
) -> (Transport, [u8; 32]) {
    let mut handshake = noise::pairing_handshake(Role::Initiator, device_private, psk)
        .expect("build the device's initiator handshake state");
    let msg1 = noise::write_handshake_message(&mut handshake, &[]).expect("write msg1");
    socket
        .send(WsMessage::Binary(msg1.into()))
        .await
        .expect("send msg1");
    let msg2 = next_binary(socket, "device handshake msg2").await;
    noise::read_handshake_message(&mut handshake, &msg2).expect("read msg2");
    let msg3 = noise::write_handshake_message(&mut handshake, &[]).expect("write msg3");
    socket
        .send(WsMessage::Binary(msg3.into()))
        .await
        .expect("send msg3");
    noise::finish_handshake(handshake).expect("finish the pairing handshake")
}

/// The Device's `Noise_KK` initiator half on a handle it paired before
/// (R-13-037), with the Host's pinned static key.
async fn device_reconnect_handshake(
    socket: &mut WebSocketStream<TcpStream>,
    device_private: &[u8; 32],
    host_public: &[u8; 32],
) -> Transport {
    let mut handshake = noise::reconnect_handshake(Role::Initiator, device_private, host_public)
        .expect("build the device's reconnect handshake state");
    let msg1 = noise::write_handshake_message(&mut handshake, &[]).expect("write msg1");
    socket
        .send(WsMessage::Binary(msg1.into()))
        .await
        .expect("send msg1");
    let msg2 = next_binary(socket, "device handshake msg2").await;
    noise::read_handshake_message(&mut handshake, &msg2).expect("read msg2");
    let (transport, _host_static) =
        noise::finish_handshake(handshake).expect("finish the reconnect handshake");
    transport
}

/// One failed pairing attempt, driven by hand on the Host's registered
/// socket: a `Noise_XXpsk0` initiator built with the wrong PSK sends its
/// `msg1`, whose payload tag the Host cannot verify — the `psk0` modifier
/// mixes the PSK in before `msg1`, so the mismatch fails at `msg1` already
/// (see `noise.rs`'s own `xxpsk0_fails_with_mismatched_psk`). R-13-023
/// counts one failed attempt and the Host drops its end of the socket,
/// which this helper waits for, so the attempt is complete before the
/// caller looks for the next registration.
async fn failed_pairing_attempt(socket: &mut WebSocketStream<TcpStream>) {
    let (device_private, _device_public) =
        noise::generate_keypair().expect("generate the device keypair");
    let wrong_psk = [0xAA; 32];
    let mut handshake = noise::pairing_handshake(Role::Initiator, &device_private, &wrong_psk)
        .expect("build the wrong-psk handshake state");
    let msg1 = noise::write_handshake_message(&mut handshake, &[]).expect("write msg1");
    socket
        .send(WsMessage::Binary(msg1.into()))
        .await
        .expect("send msg1");
    let closed = tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            match socket.next().await {
                Some(Ok(WsMessage::Close(_))) | None | Some(Err(_)) => break,
                Some(Ok(_)) => {}
            }
        }
    })
    .await;
    assert!(
        closed.is_ok(),
        "the Host closes its end after a failed msg1 (R-41-131)"
    );
}

/// Reads physical binary messages until one full frame envelope reassembles
/// (the `frame_codec` fragmentation path, R-11-229), then parses it.
async fn read_app_frame(
    socket: &mut WebSocketStream<TcpStream>,
    transport: &mut Transport,
    reassembler: &mut Reassembler,
) -> Message {
    read_app_frame_with_corr(socket, transport, reassembler)
        .await
        .0
}

/// [`read_app_frame`] plus the envelope's `corr`, for the reply-correlation
/// assertions in (j).
async fn read_app_frame_with_corr(
    socket: &mut WebSocketStream<TcpStream>,
    transport: &mut Transport,
    reassembler: &mut Reassembler,
) -> (Message, Option<String>) {
    loop {
        let ciphertext = next_binary(socket, "read_app_frame").await;
        if let Some(bytes) =
            frame_codec::decode_fragment(reassembler, transport, &ciphertext, Instant::now())
                .expect("decode a fragment")
        {
            let frame = Frame::from_json_bytes(&bytes).expect("parse the frame envelope");
            let message = frame.message().expect("decode the message");
            return (message, frame.corr);
        }
    }
}

async fn send_app_frame(
    socket: &mut WebSocketStream<TcpStream>,
    transport: &mut Transport,
    seq: &mut SequenceCounter,
    message: &Message,
    corr: Option<String>,
) {
    let frame = Frame::wrap(seq.advance(), corr, message).expect("wrap the frame");
    let bytes = frame.to_json_bytes().expect("serialize the frame");
    for fragment in frame_codec::encode_frame(transport, &bytes).expect("encode the frame") {
        socket
            .send(WsMessage::Binary(fragment.into()))
            .await
            .expect("send the frame");
    }
}

/// Sends the mandatory first frame (R-11-131).
async fn send_device_info(
    socket: &mut WebSocketStream<TcpStream>,
    transport: &mut Transport,
    seq: &mut SequenceCounter,
    device_id: &str,
    device_name: &str,
) {
    send_app_frame(
        socket,
        transport,
        seq,
        &Message::DeviceInfo(DeviceInfo {
            protocol: 1,
            device_id: device_id.to_owned(),
            device_name: device_name.to_owned(),
            platform: Platform::Android,
            os_version: "15".to_owned(),
            app_version: "0.1.0".to_owned(),
        }),
        None,
    )
    .await;
}

// ---------------------------------------------------------------------------
// The Host under test
// ---------------------------------------------------------------------------

fn test_config(paths: ConfigPaths, origin: String, log: bridge::Log) -> HostConfig {
    let (private, public) = noise::generate_keypair().expect("generate the host keypair");
    let relay_config = RelayConfig {
        relay_origin: origin.clone(),
        ..RelayConfig::default()
    };
    HostConfig {
        paths,
        client: HerdrClient::with_path(
            PathBuf::from("herdr-stub-socket-not-present"),
            &relay_config,
        ),
        herdr_version: "test-herdr".to_owned(),
        herdr_protocol: EXPECTED_PROTOCOL as u32,
        host_name: "test-host".to_owned(),
        keypair: HostKeypair { private, public },
        words: word_list(),
        relay_config,
        ws_origin: origin,
        log,
    }
}

fn status(host: &HostHandle) -> control::Status {
    let value = host
        .handler()
        .handle(Command::Status)
        .expect("status answers ok");
    serde_json::from_value(value).expect("the status object decodes")
}

/// Polls `check` until it holds: the bridge's registration and session tasks
/// run concurrently with the test, so every observation of their effect is a
/// poll, never a sleep-then-assume.
async fn wait_for(what: &str, mut check: impl FnMut() -> bool) {
    for _ in 0..500 {
        if check() {
            return;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    panic!("timed out waiting for {what}");
}

/// One full pairing, from `open_pairing` to an enrolled, connected Device,
/// returning the pairing's handle and the Device's key material plus the
/// live session socket. Asserts (a) and (e) on the way.
async fn begin_pairing(
    relay: &mut FakeRelay,
    host: &HostHandle,
) -> (
    String,
    [u8; 32],
    [u8; 32],
    WebSocketStream<TcpStream>,
    Transport,
) {
    // (e) `open_pairing` answers with the status object, and the credential
    // fields stay null until the relay accepted the registration (R-10-064).
    let value = host
        .handler()
        .handle(Command::OpenPairing)
        .expect("open_pairing answers ok");
    let opened: control::Status = serde_json::from_value(value).expect("the status decodes");
    let pairing = opened.pairing.expect("a pairing is open");
    assert!(!pairing.registered, "not registered before session_joined");
    assert!(pairing.uri.is_none() && pairing.phrase.is_none() && pairing.handle.is_none());
    assert!(pairing.expires_in_s > 500, "a fresh phrase lives ~600 s");

    // The registration lands on the fake relay; `session_joined` flips
    // `registered` (R-10-064).
    let incoming = relay.accept_host().await;
    wait_for("pairing.registered", || {
        status(host)
            .pairing
            .as_ref()
            .is_some_and(|pairing| pairing.registered)
    })
    .await;
    let pairing = status(host).pairing.expect("the pairing is still open");
    let handle = pairing.handle.expect("registered: the handle is set");
    assert_eq!(handle.len(), 22, "R-11-112: 22 base64url characters");
    assert!(
        handle.parse::<Handle>().is_ok(),
        "the handle parses back (R-11-112)"
    );
    assert!(
        incoming.handle == handle,
        "the registered handle is the minted one"
    );
    let phrase = pairing.phrase.expect("registered: the phrase is set");
    assert!(
        pairing
            .uri
            .expect("registered: the uri is set")
            .starts_with("herdr-remote://pair?")
    );

    // The Device's half: psk from the canonical (hyphenated) phrase
    // (R-13-024), then the XXpsk0 handshake on the registered socket.
    let psk = noise::psk_from_phrase(phrase.replace(' ', "-").as_bytes());
    let (device_private, _device_public) =
        noise::generate_keypair().expect("generate the device keypair");
    let mut device_socket = incoming.socket;
    let (mut device_transport, host_static) =
        device_pairing_handshake(&mut device_socket, &device_private, &psk).await;

    // `host_info` first (R-11-130), `paired: false` for a first pairing.
    let mut reassembler = Reassembler::new();
    let hello = read_app_frame(&mut device_socket, &mut device_transport, &mut reassembler).await;
    let Message::HostInfo(HostInfo {
        protocol,
        host_id,
        host_name,
        herdr_version,
        herdr_protocol,
        paired,
        theme: _,
    }) = hello
    else {
        panic!("expected host_info, got {hello:?}");
    };
    assert_eq!(protocol, 1);
    assert!(!paired, "a first pairing reports paired: false");
    let parsed_id = uuid::Uuid::parse_str(&host_id).expect("host_id is a UUID");
    assert_eq!(
        parsed_id.get_version_num(),
        4,
        "host_id is UUIDv4 (R-13-049)"
    );
    assert_eq!(host_name, "test-host");
    assert_eq!(herdr_version, "test-herdr");
    assert_eq!(herdr_protocol, EXPECTED_PROTOCOL as u32);

    (
        handle,
        device_private,
        host_static,
        device_socket,
        device_transport,
    )
}

async fn pair_a_device(
    relay: &mut FakeRelay,
    host: &HostHandle,
    device_id: &str,
    device_name: &str,
) -> (
    String,
    [u8; 32],
    [u8; 32],
    WebSocketStream<TcpStream>,
    Transport,
) {
    let (handle, device_private, host_static, mut device_socket, mut device_transport) =
        begin_pairing(relay, host).await;
    let mut seq = SequenceCounter::new();
    send_device_info(
        &mut device_socket,
        &mut device_transport,
        &mut seq,
        device_id,
        device_name,
    )
    .await;

    // (a) the store entry exists and `status` shows the device connected.
    wait_for("the enrolled device to read connected", || {
        let status = status(host);
        status
            .devices
            .iter()
            .any(|row| row.device_id == device_id && row.connected)
    })
    .await;
    assert!(
        status(host).pairing.is_none(),
        "a successful enrolment destroyed the phrase (R-13-035 step 10)"
    );
    (
        handle,
        device_private,
        host_static,
        device_socket,
        device_transport,
    )
}

/// (g): a `Noise_KK` registration is held with no Device for more than
/// `CONNECT_TIMEOUT` (30 s) — the relay's own heartbeat `Ping` in that
/// period answered by tokio-tungstenite itself — and a `Noise_KK` handshake
/// after that still completes with `host_info.paired == true` (R-11-120: no
/// pairing window applies to a paired registration). The clock is paused
/// only after the real-I/O setup completes: a paused runtime advances to
/// the next pending timer on any idle turn, which real round trips cannot
/// survive, so every exchange here runs with no timer pending.
#[tokio::test]
async fn a_kk_registration_held_past_the_connect_timeout_still_completes() {
    let mut relay = FakeRelay::start().await;
    let paths = temp_paths("kk-held");
    let log: bridge::Log = Arc::new(|_line| {});
    let host = bridge::start(test_config(paths.clone(), relay.origin.clone(), log))
        .await
        .expect("the bridge starts");

    let (handle, device_private, host_static, mut device_socket, mut device_transport) =
        pair_a_device(&mut relay, &host, "device-a", "pixel-8-pat").await;

    // End the pairing session the deliberate way (R-11-206); the bridge
    // starts the entry's `Noise_KK` registration (R-13-035 step 9).
    send_app_frame(
        &mut device_socket,
        &mut device_transport,
        &mut SequenceCounter::new(),
        &Message::Disconnect(Disconnect {}),
        None,
    )
    .await;
    let kk_registration = loop {
        let incoming = relay.accept_host().await;
        if incoming.handle == handle {
            break incoming;
        }
    };

    // 31 s pass with no Device; the relay's heartbeat Ping lands inside
    // that period and is answered at the WebSocket layer. The KK wait in
    // `handshake_on` carries no timer, so no pending timer exists to fire
    // while the clock is paused.
    let mut kk_socket = kk_registration.socket;
    tokio::time::pause();
    tokio::time::advance(Duration::from_secs(31)).await;
    kk_socket
        .send(WsMessage::Ping(Vec::new().into()))
        .await
        .expect("send the heartbeat ping");
    // No tokio timer while the clock is paused (an idle turn would fire it
    // before real I/O lands): poll the socket directly, yielding between
    // attempts, against a real-clock budget (R-41-131).
    let pong_deadline = std::time::Instant::now() + Duration::from_secs(5);
    loop {
        match kk_socket.next().now_or_never() {
            Some(Some(Ok(WsMessage::Pong(_)))) => break,
            Some(Some(Ok(_))) | None => {}
            other => panic!("expected the pong on the held registration, got {other:?}"),
        }
        assert!(
            std::time::Instant::now() < pong_deadline,
            "no pong on the held registration within 5 real seconds"
        );
        tokio::task::yield_now().await;
    }

    // The handshake after the held window still completes, paired: true.
    let mut kk_transport =
        device_reconnect_handshake(&mut kk_socket, &device_private, &host_static).await;
    let mut reassembler = Reassembler::new();
    let hello = read_app_frame(&mut kk_socket, &mut kk_transport, &mut reassembler).await;
    let Message::HostInfo(hello) = hello else {
        panic!("expected host_info, got {hello:?}");
    };
    assert!(
        hello.paired,
        "a Noise_KK session after the held window reports paired: true"
    );
    wait_for("the reconnected device to read connected", || {
        status(&host)
            .devices
            .iter()
            .any(|row| row.device_id == "device-a" && row.connected)
    })
    .await;

    host.shutdown().await;
    std::fs::remove_dir_all(paths.dir()).ok();
}

/// (h): 600 s with no Device destroys the pairing (R-13-022) — `status`
/// reads `pairing: null`, the registration socket closes, and nothing
/// re-registers. The clock is paused only after the real-I/O registration
/// completes (see the `held_past_the_connect_timeout` test for why), then
/// advanced past the phrase lifetime, which fires the bridge's pairing
/// window without a real 600 s wait.
#[tokio::test]
async fn a_pairing_with_no_device_is_destroyed_after_600_seconds() {
    let mut relay = FakeRelay::start().await;
    let paths = temp_paths("expiry");
    let log: bridge::Log = Arc::new(|_line| {});
    let host = bridge::start(test_config(paths.clone(), relay.origin.clone(), log))
        .await
        .expect("the bridge starts");

    host.handler()
        .handle(Command::OpenPairing)
        .expect("open_pairing answers ok");
    let incoming = relay.accept_host().await;
    wait_for("pairing.registered", || {
        status(&host)
            .pairing
            .as_ref()
            .is_some_and(|pairing| pairing.registered)
    })
    .await;
    assert!(status(&host).pairing.is_some());
    assert_eq!(relay.registration_count(&incoming.handle), 1);

    // The R-13-022 window elapses with no Device.
    tokio::time::pause();
    tokio::time::advance(Duration::from_secs(601)).await;

    wait_for("the expired pairing to be destroyed", || {
        status(&host).pairing.is_none()
    })
    .await;
    drop(incoming);
    assert!(
        tokio::time::timeout(Duration::from_millis(500), relay.incoming.recv())
            .await
            .is_err(),
        "a destroyed pairing is not re-registered"
    );

    host.shutdown().await;
    std::fs::remove_dir_all(paths.dir()).ok();
}

/// (i): three failed handshakes spend the phrase and the handle (R-13-023):
/// the bridge re-registers the SAME handle between attempts (no rotation),
/// the third failure destroys the pairing (`status` reads `pairing: null`)
/// with no re-registration, and a fresh `open_pairing` mints a NEW handle.
/// Real time: every wait here is bounded by I/O, not by the phrase clock.
#[tokio::test]
async fn three_failed_handshakes_spend_the_phrase_with_no_replacement() {
    let mut relay = FakeRelay::start().await;
    let paths = temp_paths("spent");
    let log: bridge::Log = Arc::new(|_line| {});
    let host = bridge::start(test_config(paths.clone(), relay.origin.clone(), log))
        .await
        .expect("the bridge starts");

    host.handler()
        .handle(Command::OpenPairing)
        .expect("open_pairing answers ok");
    let first = relay.accept_host().await;
    wait_for("pairing.registered", || {
        status(&host)
            .pairing
            .as_ref()
            .is_some_and(|pairing| pairing.registered)
    })
    .await;
    let spent_handle = first.handle.clone();

    // Three attempts, each on a fresh registration of the same handle.
    let mut incoming = Some(first);
    for attempt in 1..=3u8 {
        let IncomingHost { handle, mut socket } =
            incoming.take().expect("one registration per attempt");
        assert_eq!(
            handle, spent_handle,
            "attempt {attempt}: no rotation — the handle stays until the third failure"
        );
        failed_pairing_attempt(&mut socket).await;
        if attempt < 3 {
            incoming = Some(relay.accept_host().await);
        }
    }

    // The third failure destroys the pairing; nothing re-registers.
    wait_for("the spent pairing to be destroyed", || {
        status(&host).pairing.is_none()
    })
    .await;
    assert_eq!(
        relay.registration_count(&spent_handle),
        3,
        "one registration per attempt, and no replacement minted"
    );
    assert!(
        tokio::time::timeout(Duration::from_millis(500), relay.incoming.recv())
            .await
            .is_err(),
        "a spent pairing is not re-registered"
    );

    // A fresh `open_pairing` (the pane's `p`) mints a new handle.
    host.handler()
        .handle(Command::OpenPairing)
        .expect("open_pairing answers ok");
    let reopened = relay.accept_host().await;
    assert_ne!(
        reopened.handle, spent_handle,
        "a new open_pairing mints a new handle"
    );
    wait_for("the reopened pairing to register", || {
        status(&host)
            .pairing
            .as_ref()
            .is_some_and(|pairing| pairing.registered)
    })
    .await;

    host.shutdown().await;
    std::fs::remove_dir_all(paths.dir()).ok();
}

/// (a) + (b) + (e) + (f): pair, reconnect with `Noise_KK`, and never log a
/// secret.
#[tokio::test]
async fn pairing_then_kk_reconnect_round_trip() {
    let mut relay = FakeRelay::start().await;
    let paths = temp_paths("round-trip");
    let log_lines: Arc<Mutex<Vec<String>>> = Arc::new(Mutex::new(Vec::new()));
    let log: bridge::Log = {
        let log_lines = Arc::clone(&log_lines);
        Arc::new(move |line: &str| {
            log_lines.lock().expect("log lock").push(line.to_owned());
        })
    };
    let host = bridge::start(test_config(paths.clone(), relay.origin.clone(), log))
        .await
        .expect("the bridge starts");

    // (e) with no open pairing.
    let before = status(&host);
    assert_eq!(before.relay_origin, relay.origin);
    assert!(before.pairing.is_none());
    assert!(before.devices.is_empty());
    assert_eq!(before.link.state, control::LinkState::Idle);

    let (handle, device_private, host_static, mut device_socket, mut device_transport) =
        pair_a_device(&mut relay, &host, "device-a", "pixel-8-pat").await;

    // The stored entry: the same 22-character handle and the UUIDv4 host_id
    // the Device saw in `host_info` (R-13-049).
    let store = DeviceStore::load(paths.clone()).expect("reload the store");
    let entry = store.find("device-a").expect("the entry was written");
    assert_eq!(entry.handle, handle);
    assert_eq!(entry.device_name, "pixel-8-pat");
    assert_eq!(entry.platform, Platform::Android);
    assert_eq!(entry.os_version, "15");
    let _ = uuid::Uuid::parse_str(&entry.host_id).expect("the stored host_id is a UUID");

    // End the pairing session the deliberate way (R-11-206): disconnect,
    // then close. The bridge starts the entry's `Noise_KK` registration
    // (R-13-035 step 9).
    let mut seq = SequenceCounter::new();
    send_app_frame(
        &mut device_socket,
        &mut device_transport,
        &mut seq,
        &Message::Disconnect(Disconnect {}),
        None,
    )
    .await;
    let mut kk_registration = None;
    for _ in 0..500 {
        match tokio::time::timeout(Duration::from_millis(10), relay.incoming.recv()).await {
            Ok(Some(incoming)) if incoming.handle == handle => {
                kk_registration = Some(incoming);
                break;
            }
            Ok(Some(_other)) => {}
            Ok(None) => panic!("the accept loop lives"),
            Err(_) => {}
        }
    }
    let kk_registration = kk_registration.expect("the Noise_KK registration arrives");

    // (b) the Device reconnects on the same handle (R-13-034) with the
    // pinned keys, and `host_info.paired` is true.
    let mut kk_socket = kk_registration.socket;
    let mut kk_transport =
        device_reconnect_handshake(&mut kk_socket, &device_private, &host_static).await;
    let mut reassembler = Reassembler::new();
    let hello = read_app_frame(&mut kk_socket, &mut kk_transport, &mut reassembler).await;
    let Message::HostInfo(hello) = hello else {
        panic!("expected host_info, got {hello:?}");
    };
    assert!(hello.paired, "a Noise_KK session reports paired: true");
    assert_eq!(hello.host_id, entry.host_id, "the entry's own host_id");
    wait_for("the reconnected device to read connected", || {
        status(&host)
            .devices
            .iter()
            .any(|row| row.device_id == "device-a" && row.connected)
    })
    .await;

    // End the KK session too, then shut the bridge down: the control
    // endpoint leaves `state.json` (R-10-062).
    send_app_frame(
        &mut kk_socket,
        &mut kk_transport,
        &mut seq,
        &Message::Disconnect(Disconnect {}),
        None,
    )
    .await;
    tokio::time::sleep(Duration::from_millis(100)).await;
    host.shutdown().await;
    let state: serde_json::Value = serde_json::from_str(
        &std::fs::read_to_string(paths.state_file()).expect("state.json exists"),
    )
    .expect("state.json parses");
    assert!(
        state.get("control").is_none(),
        "R-10-062: a clean exit removes the control key"
    );

    // (f) no captured log line carries a secret. The pairing's phrase is
    // gone from the status by now, so assert against the store record and
    // the values this test itself observed: the handle and the device id.
    let lines = log_lines.lock().expect("log lock").clone();
    assert!(!lines.is_empty(), "the bridge logged its state changes");
    for line in &lines {
        assert!(!line.contains(&handle), "no handle in a log line: {line}");
        assert!(
            !line.contains("device-a"),
            "no device id in a log line: {line}"
        );
        assert!(
            !line.contains("herdr-remote://"),
            "no pairing URI in a log line: {line}"
        );
    }

    std::fs::remove_dir_all(paths.dir()).ok();
}

/// (c) + (d): the one-active-session guard closes the second Device with
/// `4006` and leaves the first alone; `revoke` ends the first with `4004`
/// and kills the registration for good.
#[tokio::test]
async fn second_device_gets_4006_and_revoke_ends_the_first() {
    let mut relay = FakeRelay::start().await;
    let paths = temp_paths("guard");
    let log: bridge::Log = Arc::new(|_line| {});
    let host = bridge::start(test_config(paths.clone(), relay.origin.clone(), log))
        .await
        .expect("the bridge starts");

    // Pair two devices in turn; each pairing session is ended before the
    // next opens, so both entries get their own handles and their own
    // `Noise_KK` loops.
    let (handle_a, device_a_private, host_static_a, mut socket_a, mut transport_a) =
        pair_a_device(&mut relay, &host, "device-a", "pixel-8-pat").await;
    send_app_frame(
        &mut socket_a,
        &mut transport_a,
        &mut SequenceCounter::new(),
        &Message::Disconnect(Disconnect {}),
        None,
    )
    .await;
    let registration_a = loop {
        let incoming = relay.accept_host().await;
        if incoming.handle == handle_a {
            break incoming;
        }
    };

    let (handle_b, device_b_private, _host_static_b, mut socket_b, mut transport_b) =
        pair_a_device(&mut relay, &host, "device-b", "iphone-15-pat").await;
    send_app_frame(
        &mut socket_b,
        &mut transport_b,
        &mut SequenceCounter::new(),
        &Message::Disconnect(Disconnect {}),
        None,
    )
    .await;
    let registration_b = loop {
        let incoming = relay.accept_host().await;
        if incoming.handle == handle_b {
            break incoming;
        }
    };
    assert_ne!(handle_a, handle_b, "each pairing mints its own handle");

    // Device A reconnects and holds the one live session.
    let mut live_a_socket = registration_a.socket;
    let mut live_a_transport =
        device_reconnect_handshake(&mut live_a_socket, &device_a_private, &host_static_a).await;
    let mut reassembler_a = Reassembler::new();
    let hello = read_app_frame(
        &mut live_a_socket,
        &mut live_a_transport,
        &mut reassembler_a,
    )
    .await;
    assert!(matches!(hello, Message::HostInfo(_)));
    wait_for("device-a to read connected", || {
        status(&host)
            .devices
            .iter()
            .any(|row| row.device_id == "device-a" && row.connected)
    })
    .await;

    // (c) Device B completes its `Noise_KK` handshake while A's session is
    // live: the guard closes B's WebSocket with 4006 (R-10-069)…
    let mut denied_b_socket = registration_b.socket;
    let _denied_b_transport =
        device_reconnect_handshake(&mut denied_b_socket, &device_b_private, &host_static_a).await;
    let close = loop {
        match denied_b_socket.next().await {
            Some(Ok(WsMessage::Close(Some(frame)))) => break frame,
            Some(Ok(_)) => {}
            other => panic!("expected a close frame for the second device, got {other:?}"),
        }
    };
    assert_eq!(
        u16::from(close.code),
        CloseCode::HostInUse.code(),
        "4006 host_in_use"
    );

    // …and A's session is untouched: it still answers a request (the stub
    // Herdr fails the call, and that failure arrives as an `error` frame —
    // proof the session's dispatch loop is alive).
    let probe_seq = &mut SequenceCounter::new();
    send_app_frame(
        &mut live_a_socket,
        &mut live_a_transport,
        probe_seq,
        &Message::TreeRequest(herdr_relay_proto::messages::TreeRequest {}),
        Some("probe-1".to_owned()),
    )
    .await;
    let reply = read_app_frame(
        &mut live_a_socket,
        &mut live_a_transport,
        &mut reassembler_a,
    )
    .await;
    assert!(
        matches!(reply, Message::Error(_)),
        "the first session still serves: {reply:?}"
    );
    assert!(
        status(&host)
            .devices
            .iter()
            .any(|row| row.device_id == "device-a" && row.connected),
        "device-a is still the connected one"
    );

    // (d) revoke A: the live session gets the fatal `revoked` error and a
    // 4004 close (R-13-053 step 3, R-11-065)…
    host.handler()
        .handle(Command::Revoke {
            device_id: "device-a".to_owned(),
        })
        .expect("revoke answers ok");
    let revoked = read_app_frame(
        &mut live_a_socket,
        &mut live_a_transport,
        &mut reassembler_a,
    )
    .await;
    let Message::Error(error) = revoked else {
        panic!("expected the revoked error, got {revoked:?}");
    };
    assert!(error.fatal);
    let close = loop {
        match live_a_socket.next().await {
            Some(Ok(WsMessage::Close(Some(frame)))) => break frame,
            Some(Ok(_)) => {}
            other => panic!("expected the 4004 close, got {other:?}"),
        }
    };
    assert_eq!(
        u16::from(close.code),
        CloseCode::Revoked.code(),
        "4004 revoked"
    );

    // …the entry is gone from the store and from `status`…
    assert!(
        status(&host)
            .devices
            .iter()
            .all(|row| row.device_id != "device-a")
    );
    let store = DeviceStore::load(paths.clone()).expect("reload the store");
    assert!(store.find("device-a").is_none());
    assert_eq!(
        host.handler().handle(Command::Revoke {
            device_id: "device-a".to_owned(),
        }),
        Err(control::ErrorCode::NotFound),
        "an unknown device_id is not_found (R-10-064)"
    );

    // …and the handle is never registered again (R-13-053 step 2). The
    // bridge's connection ended, so the relay-side registration is gone
    // (R-11-125), and a Device that tries the dead handle meets 4001.
    relay.host_closed(&handle_a);
    let registrations_before = relay.registration_count(&handle_a);
    tokio::time::sleep(Duration::from_millis(400)).await;
    assert_eq!(
        relay.registration_count(&handle_a),
        registrations_before,
        "no re-registration after revoke"
    );

    let url = format!("{}/device/{}", relay.origin, handle_a);
    let mut request = url.into_client_request().expect("a valid URL");
    request.headers_mut().insert(
        "sec-websocket-protocol",
        SUBPROTOCOL
            .parse()
            .expect("the subprotocol constant parses"),
    );
    let (mut device_attempt, _response) = tokio_tungstenite::connect_async(request)
        .await
        .expect("the relay answers the upgrade");
    let refusal = device_attempt
        .next()
        .await
        .expect("a refusal frame arrives")
        .expect("no websocket I/O error");
    assert!(
        matches!(&refusal, WsMessage::Text(text) if text.contains("handle_unknown")),
        "R-11-117: handle_unknown, got {refusal:?}"
    );
    let close = loop {
        match device_attempt.next().await {
            Some(Ok(WsMessage::Close(Some(frame)))) => break frame,
            Some(Ok(_)) => {}
            other => panic!("expected the 4001 close, got {other:?}"),
        }
    };
    assert_eq!(
        u16::from(close.code),
        CloseCode::HandleUnknown.code(),
        "4001 handle_unknown"
    );

    host.shutdown().await;
    std::fs::remove_dir_all(paths.dir()).ok();
}

// ---------------------------------------------------------------------------
// (j) Request dispatch: one test per `BridgeRequest` arm added in Phase 25
// ---------------------------------------------------------------------------

/// One paired, connected Device session against a running bridge, with the
/// Device-side frame state the (j) tests drive requests through.
struct LiveSession {
    relay: FakeRelay,
    host: HostHandle,
    paths: ConfigPaths,
    socket: WebSocketStream<TcpStream>,
    transport: Transport,
    reassembler: Reassembler,
    seq: SequenceCounter,
}

impl LiveSession {
    async fn start(tag: &str) -> Self {
        let mut relay = FakeRelay::start().await;
        let paths = temp_paths(tag);
        let log: bridge::Log = Arc::new(|_line| {});
        let host = bridge::start(test_config(paths.clone(), relay.origin.clone(), log))
            .await
            .expect("the bridge starts");
        let (_handle, _device_private, _host_static, socket, transport) =
            pair_a_device(&mut relay, &host, "device-a", "pixel-8-pat").await;
        Self {
            relay,
            host,
            paths,
            socket,
            transport,
            reassembler: Reassembler::new(),
            seq: SequenceCounter::new(),
        }
    }

    async fn send(&mut self, message: &Message, corr: Option<&str>) {
        send_app_frame(
            &mut self.socket,
            &mut self.transport,
            &mut self.seq,
            message,
            corr.map(str::to_owned),
        )
        .await;
    }

    async fn read(&mut self) -> (Message, Option<String>) {
        read_app_frame_with_corr(&mut self.socket, &mut self.transport, &mut self.reassembler).await
    }

    /// Sends `message` with `corr` and returns the one reply frame.
    async fn request(&mut self, message: Message, corr: &str) -> (Message, Option<String>) {
        self.send(&message, Some(corr)).await;
        self.read().await
    }

    async fn finish(self) {
        drop(self.relay);
        self.host.shutdown().await;
        std::fs::remove_dir_all(self.paths.dir()).ok();
    }
}

/// The Herdr-backed requests reach the bridge thread and come back as a
/// non-fatal `error` frame with the request's `corr`: the stub Herdr socket
/// does not exist, so the handler's Herdr call fails and R-11-091 maps that
/// failure onto the reply (the same proof (c)'s `tree_request` probe uses).
fn assert_herdr_error_reply(reply: &Message, corr: Option<&str>, expected_corr: &str) {
    assert_eq!(corr, Some(expected_corr), "the reply echoes the corr");
    let Message::Error(error) = reply else {
        panic!("expected the stub Herdr failure as an error frame, got {reply:?}");
    };
    assert!(
        !error.fatal,
        "a Herdr call failure never closes the session"
    );
}

#[tokio::test]
async fn device_list_request_is_answered_with_a_correlated_device_list() {
    let mut session = LiveSession::start("dispatch-device-list").await;
    let (reply, corr) = session
        .request(Message::DeviceListRequest(DeviceListRequest {}), "c-list")
        .await;
    assert_eq!(corr.as_deref(), Some("c-list"));
    let Message::DeviceList(list) = reply else {
        panic!("expected device_list, got {reply:?}");
    };
    assert_eq!(list.devices.len(), 1, "the one paired device");
    assert_eq!(list.devices[0].id, "device-a");
    assert!(
        list.devices[0].connected,
        "R-11-062: the session's own Device reads connected"
    );
    session.finish().await;
}

#[tokio::test]
async fn scroll_request_is_answered_on_the_same_corr() {
    let mut session = LiveSession::start("dispatch-scroll").await;
    let (reply, corr) = session
        .request(
            Message::ScrollRequest(ScrollRequest {
                pane_id: "w1:p1".to_owned(),
                lines: 200,
            }),
            "c-scroll",
        )
        .await;
    assert_herdr_error_reply(&reply, corr.as_deref(), "c-scroll");
    session.finish().await;
}

#[tokio::test]
async fn action_list_request_is_answered_on_the_same_corr() {
    let mut session = LiveSession::start("dispatch-action-list").await;
    let (reply, corr) = session
        .request(
            Message::ActionListRequest(ActionListRequest {}),
            "c-actions",
        )
        .await;
    assert_herdr_error_reply(&reply, corr.as_deref(), "c-actions");
    session.finish().await;
}

#[tokio::test]
async fn host_action_is_answered_on_the_same_corr() {
    let mut session = LiveSession::start("dispatch-host-action").await;
    let (reply, corr) = session
        .request(
            Message::HostAction(HostAction {
                action: HostActionKind::WorkspaceCreate,
                pane_id: None,
                workspace_id: None,
                tab_id: None,
                plugin_id: None,
                action_id: None,
                params: Some(serde_json::json!({ "focus": false })),
            }),
            "c-action",
        )
        .await;
    assert_herdr_error_reply(&reply, corr.as_deref(), "c-action");
    session.finish().await;
}

#[tokio::test]
async fn unwatch_pane_has_no_reply_and_leaves_the_session_serving() {
    let mut session = LiveSession::start("dispatch-unwatch").await;
    session
        .send(
            &Message::UnwatchPane(UnwatchPane {
                pane_id: "w1:p1".to_owned(),
            }),
            None,
        )
        .await;
    // R-11-050: no reply frame at all, not even an error.
    let silent = tokio::time::timeout(Duration::from_millis(300), session.read()).await;
    assert!(silent.is_err(), "unwatch_pane produced a frame: {silent:?}");
    // The dispatch loop is still alive and still correlates.
    let (reply, corr) = session
        .request(Message::DeviceListRequest(DeviceListRequest {}), "c-after")
        .await;
    assert_eq!(corr.as_deref(), Some("c-after"));
    assert!(matches!(reply, Message::DeviceList(_)), "got {reply:?}");
    session.finish().await;
}

/// R-11-063/R-11-064/R-11-065 over the wire: the Device revokes itself. The
/// `revoke_result` reply carries the corr and arrives BEFORE the fatal
/// `revoked` error, which is the last frame before the 4004 close; the
/// entry is gone from the store and from `status`.
#[tokio::test]
async fn revoke_device_of_the_connected_device_replies_then_closes_with_4004() {
    let mut session = LiveSession::start("dispatch-revoke").await;
    let (reply, corr) = session
        .request(
            Message::RevokeDevice(RevokeDevice {
                device_id: Some("device-a".to_owned()),
                all: None,
            }),
            "c-revoke",
        )
        .await;
    assert_eq!(corr.as_deref(), Some("c-revoke"));
    let Message::RevokeResult(result) = reply else {
        panic!(
            "expected revoke_result first (R-11-065 orders the fatal error last), got {reply:?}"
        );
    };
    assert_eq!(result.revoked, vec!["device-a".to_owned()]);
    assert!(!result.all);

    let (revoked, corr) = session.read().await;
    let Message::Error(error) = revoked else {
        panic!("expected the fatal revoked error, got {revoked:?}");
    };
    assert!(error.fatal, "R-11-065: the revoked error is fatal");
    assert_eq!(corr, None, "the fatal error is not a reply");
    let close = loop {
        match session.socket.next().await {
            Some(Ok(WsMessage::Close(Some(frame)))) => break frame,
            Some(Ok(_)) => {}
            other => panic!("expected the 4004 close, got {other:?}"),
        }
    };
    assert_eq!(
        u16::from(close.code),
        CloseCode::Revoked.code(),
        "4004 revoked"
    );

    wait_for("device-a to leave status", || {
        status(&session.host)
            .devices
            .iter()
            .all(|row| row.device_id != "device-a")
    })
    .await;
    let store = DeviceStore::load(session.paths.clone()).expect("reload the store");
    assert!(store.find("device-a").is_none(), "R-13-053 step 1");
    session.finish().await;
}

// R-10-069/R-13-022: cancellation after XX must not retain the active claim.
#[tokio::test]
async fn closing_pairing_before_device_info_releases_the_host() {
    let mut relay = FakeRelay::start().await;
    let paths = temp_paths("close-before-info");
    let lines = Arc::new(Mutex::new(Vec::<String>::new()));
    let captured = Arc::clone(&lines);
    let log: bridge::Log =
        Arc::new(move |line| captured.lock().expect("log lock").push(line.to_owned()));
    let host = bridge::start(test_config(paths.clone(), relay.origin.clone(), log))
        .await
        .expect("the bridge starts");
    let (_, _, _, mut old_socket, _) = begin_pairing(&mut relay, &host).await;
    let phrase = status(&host)
        .pairing
        .expect("pairing open")
        .phrase
        .expect("registered phrase");
    host.handler()
        .handle(Command::ClosePairing)
        .expect("close pairing");
    assert!(status(&host).pairing.is_none());
    let ended = tokio::time::timeout(Duration::from_secs(5), old_socket.next())
        .await
        .expect("the canceled socket closes");
    assert!(matches!(
        ended,
        None | Some(Err(_)) | Some(Ok(WsMessage::Close(_)))
    ));
    let (_, _, _, _, _) = pair_a_device(&mut relay, &host, "replacement", "replacement").await;
    assert!(
        status(&host)
            .devices
            .iter()
            .any(|row| row.device_id == "replacement" && row.connected)
    );
    host.shutdown().await;
    // R-10-065: diagnostic output must not contain the generated phrase.
    assert!(
        lines
            .lock()
            .expect("log lock")
            .iter()
            .all(|line| !line.contains(&phrase))
    );
    std::fs::remove_dir_all(paths.dir()).ok();
}

// R-13-022: late device_info cannot persist after the shared phrase deadline.
#[tokio::test]
async fn pairing_expiry_before_device_info_rejects_late_enrollment() {
    let mut relay = FakeRelay::start().await;
    let paths = temp_paths("expiry-before-info");
    let host = bridge::start(test_config(
        paths.clone(),
        relay.origin.clone(),
        Arc::new(|_| {}),
    ))
    .await
    .expect("the bridge starts");
    let (_, _, _, mut socket, mut transport) = begin_pairing(&mut relay, &host).await;
    tokio::time::pause();
    tokio::time::advance(herdr_relay::pairing::PHRASE_LIFETIME + Duration::from_secs(1)).await;
    // Queue late bytes without polling status, which itself can cancel expired pairings.
    let frame = Frame::wrap(
        1,
        None,
        &Message::DeviceInfo(DeviceInfo {
            protocol: 1,
            app_version: "0.1.0".to_owned(),
            device_id: "late-device".to_owned(),
            device_name: "late-device".to_owned(),
            platform: Platform::Android,
            os_version: "15".to_owned(),
        }),
    )
    .expect("wrap late device_info");
    let bytes = frame.to_json_bytes().expect("encode late device_info");
    for message in
        frame_codec::encode_frame(&mut transport, &bytes).expect("encrypt late device_info")
    {
        let _ = socket.send(WsMessage::Binary(message.into())).await;
    }
    tokio::time::resume();
    let ended = tokio::time::timeout(Duration::from_secs(5), socket.next())
        .await
        .expect("the expired socket closes");
    assert!(matches!(
        ended,
        None | Some(Err(_)) | Some(Ok(WsMessage::Close(_)))
    ));
    assert!(status(&host).pairing.is_none());
    assert!(
        DeviceStore::load(paths.clone())
            .expect("reload store")
            .devices()
            .is_empty()
    );
    let (_, _, _, _, _) = pair_a_device(&mut relay, &host, "after-expiry", "replacement").await;
    assert!(
        status(&host)
            .devices
            .iter()
            .any(|row| row.device_id == "after-expiry" && row.connected)
    );
    host.shutdown().await;
    std::fs::remove_dir_all(paths.dir()).ok();
}

// R-13-049: the reply snapshot precedes its own outbound timestamp update.
#[tokio::test]
async fn outgoing_reply_updates_last_seen_without_another_device_frame() {
    let mut session = LiveSession::start("outgoing-last-seen").await;
    let (reply, _) = session
        .request(
            Message::DeviceListRequest(DeviceListRequest {}),
            "last-seen",
        )
        .await;
    let Message::DeviceList(list) = reply else {
        panic!("expected device_list");
    };
    let before = &list.devices[0].last_seen;
    wait_for("outbound last_seen update", || {
        status(&session.host).devices[0].last_seen > *before
    })
    .await;
    assert!(
        DeviceStore::load(session.paths.clone())
            .expect("reload store")
            .devices()[0]
            .last_seen
            > *before
    );
    session.finish().await;
}

// R-13-053/R-13-037: a replacement must retire the old handle and pinned key.
#[tokio::test]
async fn pairing_the_same_device_again_closes_its_old_registration() {
    let mut relay = FakeRelay::start().await;
    let paths = temp_paths("replace-device");
    let host = bridge::start(test_config(
        paths.clone(),
        relay.origin.clone(),
        Arc::new(|_| {}),
    ))
    .await
    .expect("the bridge starts");
    let (old_handle, _, _, mut socket, mut transport) =
        pair_a_device(&mut relay, &host, "same-device", "first").await;
    send_app_frame(
        &mut socket,
        &mut transport,
        &mut SequenceCounter::new(),
        &Message::Disconnect(Disconnect {}),
        None,
    )
    .await;
    let mut old_registration = relay.accept_host().await;
    assert!(old_registration.handle == old_handle);
    let (new_handle, device_key, host_key, mut socket, mut transport) =
        pair_a_device(&mut relay, &host, "same-device", "second").await;
    assert!(new_handle != old_handle);
    let ended = tokio::time::timeout(Duration::from_secs(5), old_registration.socket.next())
        .await
        .expect("the obsolete registration closes");
    assert!(matches!(
        ended,
        None | Some(Err(_)) | Some(Ok(WsMessage::Close(_)))
    ));
    let store = DeviceStore::load(paths.clone()).expect("reload store");
    assert!(store.devices().len() == 1);
    assert!(store.devices()[0].handle == new_handle);
    send_app_frame(
        &mut socket,
        &mut transport,
        &mut SequenceCounter::new(),
        &Message::Disconnect(Disconnect {}),
        None,
    )
    .await;
    let mut new_registration = relay.accept_host().await;
    assert!(new_registration.handle == new_handle);
    let mut transport =
        device_reconnect_handshake(&mut new_registration.socket, &device_key, &host_key).await;
    let hello = read_app_frame(
        &mut new_registration.socket,
        &mut transport,
        &mut Reassembler::new(),
    )
    .await;
    assert!(matches!(
        hello,
        Message::HostInfo(HostInfo { paired: true, .. })
    ));
    host.shutdown().await;
    std::fs::remove_dir_all(paths.dir()).ok();
}

// R-10-064/R-10-069: stop ends the device_info wait and releases its claim.
#[tokio::test]
async fn stop_before_device_info_releases_the_host() {
    let mut relay = FakeRelay::start().await;
    let paths = temp_paths("stop-before-info");
    let host = bridge::start(test_config(
        paths.clone(),
        relay.origin.clone(),
        Arc::new(|_| {}),
    ))
    .await
    .expect("the bridge starts");
    let (_, _, _, mut socket, _) = begin_pairing(&mut relay, &host).await;
    host.handler().handle(Command::Stop).expect("stop bridge");
    let ended = tokio::time::timeout(Duration::from_secs(5), socket.next())
        .await
        .expect("stop closes the socket");
    assert!(matches!(
        ended,
        None | Some(Err(_)) | Some(Ok(WsMessage::Close(_)))
    ));
    assert!(status(&host).pairing.is_some(), "stop retains the pairing");
    host.handler()
        .handle(Command::ClosePairing)
        .expect("close retained pairing");
    let (_, _, _, _, _) = pair_a_device(&mut relay, &host, "after-stop", "replacement").await;
    assert!(
        status(&host)
            .devices
            .iter()
            .any(|row| row.device_id == "after-stop" && row.connected)
    );
    host.shutdown().await;
    std::fs::remove_dir_all(paths.dir()).ok();
}
