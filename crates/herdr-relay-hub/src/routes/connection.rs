//! Drives one accepted WebSocket connection from its first byte to the byte pump:
//! the connection-rate, subprotocol, handle and registration-frame checks
//! (R-12-020, R-12-021, R-12-031, R-11-113 to R-11-120), then registration itself
//! and the R-11-115/R-11-116 replies. Split out of `routes.rs` along this
//! responsibility boundary — connection lifecycle versus router/state
//! construction — to keep both files under the 400-line cap (R-41-010, R-41-011).

use axum::extract::ws::{CloseFrame, Message, Utf8Bytes, WebSocket};
use herdr_relay_proto::codes::CloseCode;
use herdr_relay_proto::handle::{Handle, HandleError};
use tokio::sync::mpsc;

use super::metrics::RejectReason;
use super::{AppState, handle_first_6, logging, registration};
use crate::relay;
use crate::session::{OutboundTx, RegisterError, Role};

/// Rejects a bad connection-rate, subprotocol, handle or registration frame
/// (R-12-020, R-12-021, R-12-031, R-11-113 to R-11-120), then registers the
/// connection and, once joined, runs the byte pump (R-11-026). Each rejection
/// path is its own named helper below, so this function stays a short, readable
/// sequence of early returns (R-41-012).
pub(super) async fn drive_connection(
    mut socket: WebSocket,
    state: AppState,
    ip: std::net::IpAddr,
    protocol_ok: bool,
    handle: Result<Handle, HandleError>,
    role: Role,
) {
    if reject_if_rate_limited(&mut socket, &state, ip).await {
        return;
    }
    if reject_if_bad_protocol(&mut socket, &state, protocol_ok).await {
        return;
    }
    let Some(handle) = accept_handle(&mut socket, &state, handle).await else {
        return;
    };
    let Some(pairing) = registration::wait_for_registration(&mut socket, role).await else {
        close_with_error(
            &mut socket,
            &state,
            CloseCode::ProtocolError,
            "protocol_error",
            "missing or malformed registration frame",
        )
        .await;
        return;
    };
    let Some((my_tx, inbound, is_new)) =
        register_or_reject(&mut socket, &state, handle, role, ip, pairing).await
    else {
        return;
    };
    if is_new {
        state.metrics.record_handle_created();
    }
    announce_and_log_joined(&mut socket, &state, handle, role).await;
    relay::run_peer(socket, state, handle, role, my_tx, inbound).await;
}

/// R-12-031: `true` when this connection was rejected for exceeding the per-IP
/// connection rate.
async fn reject_if_rate_limited(
    socket: &mut WebSocket,
    state: &AppState,
    ip: std::net::IpAddr,
) -> bool {
    if state.limits.connections.allow(ip) {
        return false;
    }
    close_with_error(
        socket,
        state,
        CloseCode::RateLimited,
        "rate_limited",
        "connection rate limit exceeded",
    )
    .await;
    state.metrics.record_rejected(RejectReason::RateLimited);
    true
}

/// R-12-020: `true` when this connection was rejected for a missing or
/// unsupported subprotocol.
async fn reject_if_bad_protocol(
    socket: &mut WebSocket,
    state: &AppState,
    protocol_ok: bool,
) -> bool {
    if protocol_ok {
        return false;
    }
    close_with_error(
        socket,
        state,
        CloseCode::ProtocolError,
        "protocol_error",
        "missing or unsupported subprotocol",
    )
    .await;
    true
}

/// R-12-021: `Some(handle)` when `raw_handle` parsed; rejects and returns `None`
/// otherwise.
async fn accept_handle(
    socket: &mut WebSocket,
    state: &AppState,
    handle: Result<Handle, HandleError>,
) -> Option<Handle> {
    match handle {
        Ok(handle) => Some(handle),
        Err(_) => {
            close_with_error(
                socket,
                state,
                CloseCode::ProtocolError,
                "protocol_error",
                "malformed routing handle",
            )
            .await;
            state.metrics.record_rejected(RejectReason::HandleMalformed);
            None
        }
    }
}

/// Registers the connection, or rejects it with the close/error frame and metric
/// R-11-117 to R-11-120 and R-12-033/R-12-034 name (`session::RegisterError`'s own
/// doc comment lists exactly which rule maps to which variant).
async fn register_or_reject(
    socket: &mut WebSocket,
    state: &AppState,
    handle: Handle,
    role: Role,
    ip: std::net::IpAddr,
    pairing: bool,
) -> Option<(OutboundTx, mpsc::Receiver<Message>, bool)> {
    let outcome = state.sessions.register(
        handle,
        role,
        ip,
        &state.limits.handles,
        state.config.max_handles,
        pairing,
    );
    let error = match outcome {
        Ok(registered) => return Some(registered),
        Err(error) => error,
    };
    let (code, name, message, reject_reason) = describe_register_error(error);
    close_with_error(socket, state, code, name, message).await;
    if let Some(reason) = reject_reason {
        state.metrics.record_rejected(reason);
    }
    if error == RegisterError::PairingExpired {
        logging::handle_expired(
            &handle_first_6(handle),
            state.sessions.active_handles() as u64,
        );
    }
    None
}

/// Maps a [`RegisterError`] to its close code (R-11-121), its R-11-116 `code`
/// name and message, and the `connections_rejected_total` reason it counts
/// against, if any (only the four reasons R-12-050 names are counted).
fn describe_register_error(
    error: RegisterError,
) -> (CloseCode, &'static str, &'static str, Option<RejectReason>) {
    match error {
        RegisterError::HandleTaken => (
            CloseCode::HandleTaken,
            "handle_taken",
            "A Host is already registered under this handle",
            Some(RejectReason::HandleTaken),
        ),
        RegisterError::HostInUse => (
            CloseCode::HostInUse,
            "host_in_use",
            "A Device is already active on this Host",
            Some(RejectReason::HostInUse),
        ),
        RegisterError::HandleUnknown => (
            CloseCode::HandleUnknown,
            "handle_unknown",
            "No Host is registered under this handle",
            None,
        ),
        RegisterError::PairingExpired => (
            CloseCode::PairingExpired,
            "pairing_expired",
            "The pairing window has expired",
            None,
        ),
        RegisterError::HandleRateLimited | RegisterError::TooManyHandles => (
            CloseCode::RateLimited,
            "rate_limited",
            "handle registration rate limit exceeded",
            Some(RejectReason::RateLimited),
        ),
    }
}

/// Sends `session_joined` (R-11-115) and the matching R-12-041 connect log line.
async fn announce_and_log_joined(
    socket: &mut WebSocket,
    state: &AppState,
    handle: Handle,
    role: Role,
) {
    let _ = socket
        .send(Message::Text(Utf8Bytes::from(
            registration::session_joined_frame(role),
        )))
        .await;
    let h6 = handle_first_6(handle);
    let active = state.sessions.active_handles() as u64;
    match role {
        Role::Host => logging::host_connected(&h6, active),
        Role::Device => logging::device_connected(&h6, active),
    }
}

/// Sends the R-11-116 plaintext JSON error frame, then the close frame (R-11-121),
/// and records the error metric (R-12-050 `herdr_relay_errors_total`).
async fn close_with_error(
    socket: &mut WebSocket,
    state: &AppState,
    code: CloseCode,
    error_code: &str,
    message: &str,
) {
    let _ = socket
        .send(Message::Text(Utf8Bytes::from(registration::error_frame(
            error_code, message,
        ))))
        .await;
    close(socket, code, message.to_owned()).await;
    state.metrics.record_error(code);
    logging::error(state.sessions.active_handles() as u64, error_code, message);
}

/// Sends one close frame with `code` and `reason` (R-11-121, R-12-020, R-12-021).
// ponytail: the send result is discarded — the peer may already be gone, and there is
// nothing left to do about a failed close on a socket that is closing anyway.
async fn close(socket: &mut WebSocket, code: CloseCode, reason: String) {
    let _ = socket
        .send(Message::Close(Some(CloseFrame {
            code: code.code(),
            reason: Utf8Bytes::from(reason),
        })))
        .await;
}
