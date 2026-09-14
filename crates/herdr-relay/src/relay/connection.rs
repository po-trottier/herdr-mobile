//! Opening the Host's real outbound connection to the relay
//! (`wss://<origin>/host/<handle>`, R-12-002, R-12-020) and the post-handshake
//! send/receive path over it. `docs/90-implementation-plan.md`'s Phase 4
//! checklist named this file, but its own dependency wave (`crates/herdr-relay
//! /src/noise.rs`, `frame_codec.rs`, and the `tokio`/`tokio-tungstenite`
//! dependency) lands after Phase 6 opens, so `relay.rs`'s own header comment
//! disclosed the gap; this closes it, citing `relay.rs` per that checklist
//! item's own instruction.

use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use tokio::net::TcpStream;
use tokio_tungstenite::tungstenite::Message as WsMessage;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::{MaybeTlsStream, WebSocketStream};

use herdr_relay_proto::frame::FrameError;
use herdr_relay_proto::handle::Handle;

use crate::frame_codec::{self, FrameCodecError, Reassembler};
use crate::noise::{self, NoiseError, Role, Transport};

/// The relay subprotocol every connection MUST offer (R-11-013, R-12-020).
pub(super) const SUBPROTOCOL: &str = "herdr-relay.v1";

/// R-41-131: every connection attempt and handshake step carries a timeout.
/// The pairing phrase itself stays valid for 600 s (R-13-022); this bounds
/// one connect-plus-handshake attempt well inside that window, so a stuck
/// peer fails fast instead of silently consuming the whole phrase lifetime.
const CONNECT_TIMEOUT: Duration = Duration::from_secs(30);

pub type WsStream = WebSocketStream<MaybeTlsStream<TcpStream>>;

/// What the Noise responder handshake needs: a fresh pairing (`Noise_XXpsk0`)
/// or a returning Device's reconnect (`Noise_KK`). R-13-071: the Host is
/// always the responder; the Device always sends the first handshake message.
pub enum HandshakeSetup {
    Pairing {
        local_private_key: [u8; 32],
        psk: [u8; 32],
    },
    Reconnect {
        local_private_key: [u8; 32],
        remote_static_public_key: [u8; 32],
    },
}

/// An error connecting outbound or completing registration/handshake.
#[derive(Debug, thiserror::Error)]
pub enum ConnectError {
    #[error("connect to the relay failed: {0}")]
    Connect(#[source] tokio_tungstenite::tungstenite::Error),
    #[error("relay websocket I/O failed: {0}")]
    Io(#[source] tokio_tungstenite::tungstenite::Error),
    #[error("timed out connecting to the relay or completing the handshake")]
    Timeout,
    #[error("expected a text session_joined frame, got: {0}")]
    UnexpectedRegistrationReply(String),
    #[error(transparent)]
    Noise(#[from] NoiseError),
}

/// An error sending or receiving an application frame over an established
/// session (post-handshake).
#[derive(Debug, thiserror::Error)]
pub enum SessionError {
    #[error("relay websocket I/O failed: {0}")]
    Io(#[source] tokio_tungstenite::tungstenite::Error),
    #[error("the relay closed the connection")]
    Closed,
    #[error(transparent)]
    Codec(#[from] FrameCodecError),
    #[error(transparent)]
    Noise(#[from] NoiseError),
    #[error(transparent)]
    Frame(#[from] FrameError),
}

/// Connects outbound to `wss://<origin>/host/<handle>` (R-12-002: outbound
/// only, no inbound port ever opens) with the `herdr-relay.v1` subprotocol
/// (R-12-020), sends the `host_register` registration frame (R-11-113),
/// awaits `session_joined`, then drives the Noise responder handshake
/// `setup` describes (`noise.rs`, R-13-071) to transport mode. `origin` is
/// the full scheme-plus-host prefix, for example `wss://relay.example.com`
/// or, for local development or this crate's own tests, `ws://127.0.0.1:PORT`
/// — this function performs no `https`-to-`wss` scheme mapping of its own
/// (R-11-111 assigns that to the Device/app side); the caller passes the
/// literal WebSocket URL prefix. Returns the live WebSocket, the resulting
/// `Transport`, and the peer's static public key (for pinning/fingerprinting,
/// R-13-040, R-13-048).
pub async fn connect_host(
    origin: &str,
    handle: Handle,
    setup: HandshakeSetup,
) -> Result<(WsStream, Transport, [u8; 32]), ConnectError> {
    tokio::time::timeout(
        CONNECT_TIMEOUT,
        connect_host_inner(origin, handle, setup, None),
    )
    .await
    .map_err(|_| ConnectError::Timeout)?
}

/// Test-only seam, identical to [`connect_host`] but with the TLS connector
/// overridable: lets `#[cfg(test)]` code prove the real `wss://` path
/// against a self-signed certificate (`tests` module below), without
/// [`connect_host`] itself carrying any TLS-configuration surface — it
/// always passes `None`, which keeps this crate's own
/// `rustls-tls-native-roots` default (R-12-020).
#[cfg(test)]
async fn connect_host_with_connector(
    origin: &str,
    handle: Handle,
    setup: HandshakeSetup,
    connector: tokio_tungstenite::Connector,
) -> Result<(WsStream, Transport, [u8; 32]), ConnectError> {
    tokio::time::timeout(
        CONNECT_TIMEOUT,
        connect_host_inner(origin, handle, setup, Some(connector)),
    )
    .await
    .map_err(|_| ConnectError::Timeout)?
}

async fn connect_host_inner(
    origin: &str,
    handle: Handle,
    setup: HandshakeSetup,
    connector: Option<tokio_tungstenite::Connector>,
) -> Result<(WsStream, Transport, [u8; 32]), ConnectError> {
    let socket = register_host_inner(origin, handle, connector, false).await?;
    handshake_on(socket, setup).await
}

/// Step one of [`connect_host`] on its own: opens the WebSocket to
/// `<origin>/host/<handle>`, sends `host_register` (R-11-113) and returns once
/// the relay answered `session_joined`. From that moment a Device that arrives
/// on the handle is routed to this socket, which is what `docs/10-herdr-
/// integration.md` R-10-064 reports as `registered`. Bounded by
/// [`CONNECT_TIMEOUT`]; the wait for a Device is the caller's, through
/// [`handshake_on`].
pub async fn register_host(origin: &str, handle: Handle) -> Result<WsStream, ConnectError> {
    tokio::time::timeout(
        CONNECT_TIMEOUT,
        register_host_inner(origin, handle, None, false),
    )
    .await
    .map_err(|_| ConnectError::Timeout)?
}

/// [`register_host`] for a first-pairing registration: the same two steps,
/// but the `host_register` frame carries `"pairing": true` (R-11-113), so the
/// relay applies the R-11-120 pairing window to this handle. A paired
/// (`Noise_KK`) registration keeps the plain frame.
pub async fn register_host_pairing(origin: &str, handle: Handle) -> Result<WsStream, ConnectError> {
    tokio::time::timeout(
        CONNECT_TIMEOUT,
        register_host_inner(origin, handle, None, true),
    )
    .await
    .map_err(|_| ConnectError::Timeout)?
}

async fn register_host_inner(
    origin: &str,
    handle: Handle,
    connector: Option<tokio_tungstenite::Connector>,
    pairing: bool,
) -> Result<WsStream, ConnectError> {
    let url = format!("{origin}/host/{handle}");
    let mut request = url.into_client_request().map_err(ConnectError::Connect)?;
    request.headers_mut().insert(
        "sec-websocket-protocol",
        SUBPROTOCOL
            .parse()
            .expect("the subprotocol constant is a valid header value"),
    );
    let (mut socket, _response) =
        tokio_tungstenite::connect_async_tls_with_config(request, None, false, connector)
            .await
            .map_err(ConnectError::Connect)?;

    // R-11-113: the Host registration frame. `"pairing": true` marks a
    // first-pairing registration, so the relay applies the R-11-120 pairing
    // window; a paired (`Noise_KK`) registration omits it.
    let frame = if pairing {
        r#"{"type":"host_register","protocol":1,"pairing":true}"#
    } else {
        r#"{"type":"host_register","protocol":1}"#
    };
    socket
        .send(WsMessage::Text(frame.into()))
        .await
        .map_err(ConnectError::Io)?;
    match next_text(&mut socket).await? {
        text if text.contains("session_joined") => {}
        text => return Err(ConnectError::UnexpectedRegistrationReply(text)),
    }
    Ok(socket)
}

/// Step two of [`connect_host`] on its own: drives the Host (responder) side
/// of the Noise handshake `setup` names over a socket [`register_host`]
/// returned, and returns the transport plus the Device's static public key.
/// Unbounded on purpose: a registered Host waits for a Device for as long as
/// the caller allows (the R-13-022 window for a pairing, indefinitely for a
/// `Noise_KK` registration), so the caller applies its own timeout.
pub async fn handshake_on(
    mut socket: WsStream,
    setup: HandshakeSetup,
) -> Result<(WsStream, Transport, [u8; 32]), ConnectError> {
    let mut handshake = match setup {
        HandshakeSetup::Pairing {
            local_private_key,
            psk,
        } => noise::pairing_handshake(Role::Responder, &local_private_key, &psk)?,
        HandshakeSetup::Reconnect {
            local_private_key,
            remote_static_public_key,
        } => noise::reconnect_handshake(
            Role::Responder,
            &local_private_key,
            &remote_static_public_key,
        )?,
    };

    // R-13-071: the Device (initiator) sends the first handshake message.
    let msg1 = next_binary(&mut socket).await?;
    noise::read_handshake_message(&mut handshake, &msg1)?;

    let msg2 = noise::write_handshake_message(&mut handshake, &[])?;
    socket
        .send(WsMessage::Binary(msg2.into()))
        .await
        .map_err(ConnectError::Io)?;

    // Noise_KK (reconnect) finishes in 2 messages; Noise_XXpsk0 (pairing) needs a
    // third, inbound message. `is_handshake_finished` distinguishes them so this
    // one function drives either pattern correctly.
    if !handshake.is_handshake_finished() {
        let msg3 = next_binary(&mut socket).await?;
        noise::read_handshake_message(&mut handshake, &msg3)?;
    }

    let (transport, remote_static) = noise::finish_handshake(handshake)?;
    Ok((socket, transport, remote_static))
}

async fn next_text(socket: &mut WsStream) -> Result<String, ConnectError> {
    match next_message(socket).await? {
        WsMessage::Text(text) => Ok(text.to_string()),
        other => Err(ConnectError::UnexpectedRegistrationReply(format!(
            "{other:?}"
        ))),
    }
}

async fn next_binary(socket: &mut WsStream) -> Result<Vec<u8>, ConnectError> {
    match next_message(socket).await? {
        WsMessage::Binary(bytes) => Ok(bytes.to_vec()),
        other => Err(ConnectError::UnexpectedRegistrationReply(format!(
            "{other:?}"
        ))),
    }
}

/// The next data message. A registered Host can sit idle for hours before a
/// phone arrives, and the relay's WebSocket heartbeat (`Ping`, answered by
/// tokio-tungstenite itself) and any `Pong` arrive on this socket meanwhile,
/// so they are skipped here exactly as `receive_frame` skips them. `Close`
/// and end-of-stream are the closed connection.
async fn next_message(socket: &mut WsStream) -> Result<WsMessage, ConnectError> {
    loop {
        let message = socket
            .next()
            .await
            .ok_or_else(closed_by_relay)?
            .map_err(ConnectError::Io)?;
        match message {
            WsMessage::Ping(_) | WsMessage::Pong(_) | WsMessage::Frame(_) => continue,
            WsMessage::Close(_) => return Err(closed_by_relay()),
            other => return Ok(other),
        }
    }
}

fn closed_by_relay() -> ConnectError {
    ConnectError::UnexpectedRegistrationReply("the relay closed the connection".to_owned())
}

/// Sends one application frame envelope over `socket`, compressed and
/// fragmented per `frame_codec::encode_frame`, as one physical binary
/// WebSocket message per resulting ciphertext, in order (R-11-229 step 5).
pub async fn send_frame(
    socket: &mut WsStream,
    transport: &mut Transport,
    envelope_bytes: &[u8],
) -> Result<(), SessionError> {
    let fragments = frame_codec::encode_frame(transport, envelope_bytes)?;
    for fragment in fragments {
        socket
            .send(WsMessage::Binary(fragment.into()))
            .await
            .map_err(SessionError::Io)?;
    }
    Ok(())
}

/// Reads physical binary WebSocket messages from `socket`, feeding each into
/// `reassembler`/`transport` via `frame_codec::decode_fragment`, until one
/// full frame envelope is reassembled. Returns `Err(SessionError::Closed)` if
/// the connection ends first.
pub async fn receive_frame(
    socket: &mut WsStream,
    transport: &mut Transport,
    reassembler: &mut Reassembler,
) -> Result<Vec<u8>, SessionError> {
    loop {
        let message = socket
            .next()
            .await
            .ok_or(SessionError::Closed)?
            .map_err(SessionError::Io)?;
        let bytes = match message {
            WsMessage::Binary(bytes) => bytes,
            WsMessage::Close(_) => return Err(SessionError::Closed),
            // tokio-tungstenite auto-answers Ping; Text/Pong/Frame carry no
            // application data on this wire (R-11-026: opaque binary only,
            // after registration).
            _ => continue,
        };
        let now = std::time::Instant::now();
        if let Some(envelope) = frame_codec::decode_fragment(reassembler, transport, &bytes, now)? {
            return Ok(envelope);
        }
    }
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use futures_util::StreamExt as _;
    use rcgen::{CertifiedKey, generate_simple_self_signed};
    use rustls::{ClientConfig, RootCertStore, ServerConfig};
    use rustls_pki_types::{PrivateKeyDer, PrivatePkcs8KeyDer};
    use tokio::net::TcpListener;
    use tokio_rustls::TlsAcceptor;
    use tokio_tungstenite::Connector;
    use tokio_tungstenite::tungstenite::Message as WsMessage;

    use super::{ConnectError, HandshakeSetup, connect_host_with_connector};
    use crate::noise;
    use herdr_relay_proto::handle::Handle;

    /// Echoes the client's requested subprotocol back in the handshake
    /// response, matching what a real relay negotiates (R-11-013,
    /// R-12-020); `accept_async`'s default callback does not do this.
    #[allow(clippy::result_large_err)] // the Err type is tungstenite's own Response; not this test's to box
    fn echo_subprotocol(
        request: &tokio_tungstenite::tungstenite::handshake::server::Request,
        mut response: tokio_tungstenite::tungstenite::handshake::server::Response,
    ) -> Result<
        tokio_tungstenite::tungstenite::handshake::server::Response,
        tokio_tungstenite::tungstenite::handshake::server::ErrorResponse,
    > {
        if let Some(protocol) = request.headers().get("sec-websocket-protocol") {
            response
                .headers_mut()
                .insert("sec-websocket-protocol", protocol.clone());
        }
        Ok(response)
    }

    /// Proves `connect_host` actually completes a real TLS handshake
    /// (R-12-002, R-12-020), not just the plaintext `ws://` this file's
    /// other coverage exercises: a self-signed certificate for `127.0.0.1`,
    /// a real `tokio_rustls` server-side TLS accept, and a real
    /// `rustls::ClientConfig` that trusts exactly that certificate as a
    /// root — not a disabled-verification bypass. Stops once the WebSocket
    /// handshake completes and one real message crosses the tunnel: the
    /// Noise handshake and application framing over the connection are
    /// transport-agnostic and already fully covered, over plaintext, by
    /// `tests/relay_connection.rs`.
    #[tokio::test]
    async fn connect_host_completes_a_real_tls_handshake() {
        let CertifiedKey { cert, signing_key } =
            generate_simple_self_signed(vec!["127.0.0.1".to_owned(), "localhost".to_owned()])
                .expect("generate a self-signed certificate");
        let certificate = cert.der().clone();
        let private_key =
            PrivateKeyDer::Pkcs8(PrivatePkcs8KeyDer::from(signing_key.serialize_der()));

        let server_config = ServerConfig::builder()
            .with_no_client_auth()
            .with_single_cert(vec![certificate.clone()], private_key)
            .expect("build a server TLS config from the self-signed certificate");
        let acceptor = TlsAcceptor::from(Arc::new(server_config));

        let mut roots = RootCertStore::empty();
        roots
            .add(certificate)
            .expect("trust the self-signed certificate as a root");
        let client_config = ClientConfig::builder()
            .with_root_certificates(roots)
            .with_no_client_auth();

        let listener = TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind a local test port");
        let addr = listener.local_addr().expect("read the bound address");
        let handle = Handle::generate().expect("generate a routing handle");
        let (host_private, _host_public) =
            noise::generate_keypair().expect("generate a host keypair");

        let server_task = tokio::spawn(async move {
            let (stream, _addr) = listener
                .accept()
                .await
                .expect("accept the client's TCP connection");
            let tls_stream = acceptor
                .accept(stream)
                .await
                .expect("complete the server side of the TLS handshake");
            let mut socket = tokio_tungstenite::accept_hdr_async(tls_stream, echo_subprotocol)
                .await
                .expect("complete the websocket upgrade over TLS");
            // Prove the tunnel carries real application data, not just a
            // completed handshake.
            let register = socket
                .next()
                .await
                .expect("a message arrives over the tls tunnel")
                .expect("no websocket I/O error");
            assert!(
                matches!(&register, WsMessage::Text(text) if text.contains("host_register")),
                "expected host_register over the tls tunnel, got {register:?}"
            );
        });

        let origin = format!("wss://127.0.0.1:{}", addr.port());
        let result = connect_host_with_connector(
            &origin,
            handle,
            HandshakeSetup::Pairing {
                local_private_key: host_private,
                psk: [1_u8; 32],
            },
            Connector::Rustls(Arc::new(client_config)),
        )
        .await;

        // The fake server never drives the Noise handshake (it only proves
        // TLS + WS + one real message), so `connect_host` legitimately
        // fails past that point once the server task drops the socket. Any
        // error other than a TLS/websocket connect failure proves the TLS
        // tunnel itself was established and carried real traffic.
        match result {
            Ok(_) => panic!("the fake server never completes the noise handshake"),
            Err(ConnectError::Connect(err)) => {
                panic!("the tls/websocket connect itself failed: {err}")
            }
            Err(_) => {} // any later-stage error is expected past a real TLS connect
        }

        server_task
            .await
            .expect("the fake tls server task did not panic");
    }
}
