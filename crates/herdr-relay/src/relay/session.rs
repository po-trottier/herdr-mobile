//! Driving one live Host-to-relay session from just after the Noise
//! handshake completes to close.

use futures_util::SinkExt;
use tokio_tungstenite::tungstenite::Message as WsMessage;
use tokio_tungstenite::tungstenite::protocol::CloseFrame;
use tokio_tungstenite::tungstenite::protocol::frame::coding::CloseCode as WsCloseCode;

use herdr_relay_proto::codes::{CloseCode, ErrorCode};
use herdr_relay_proto::frame::Frame;
use herdr_relay_proto::handle::Handle;
use herdr_relay_proto::messages::{ErrorMessage, Message};

use crate::frame_codec::Reassembler;
use crate::noise::Transport;

use super::connection::{self, SessionError, WsStream};
use super::registry::{CloseReason, SessionRegistry};

/// Drives one live Host-to-relay session, registering it in `registry` under
/// `handle` so a revocation can find and close it (R-13-053 step 3, R-13-056
/// step 2). Exits when either the connection drops on its own or `registry`
/// signals a close: on a close signal, sends the `error{code:"revoked",
/// fatal:true}` application frame over the still-open Noise transport
/// (R-11-065, the `revoked` row of the §7.1 error taxonomy), then closes the
/// WebSocket with close code `4004` (R-11-121, docs/11-relay-protocol.md
/// §3.1). Unregisters itself from `registry` on every exit path, so a stale
/// entry never survives the task.
///
/// This function drives no full application-message dispatch loop: no
/// orchestration layer to hand an inbound frame to exists yet
/// (`docs/90-implementation-plan.md`'s own Phase 6 disclosure). It proves
/// the connection stays open, reads frames without blocking a close signal,
/// and can be closed on command — the scope this task's checklist item
/// actually names.
pub async fn run_host_session(
    mut socket: WsStream,
    mut transport: Transport,
    handle: Handle,
    device_id: Option<String>,
    registry: &SessionRegistry,
) -> Result<(), SessionError> {
    let close_rx = registry.register(handle, device_id);
    let result = drive_session(&mut socket, &mut transport, close_rx).await;
    registry.unregister(handle);
    result
}

async fn drive_session(
    socket: &mut WsStream,
    transport: &mut Transport,
    mut close_rx: tokio::sync::oneshot::Receiver<CloseReason>,
) -> Result<(), SessionError> {
    let mut reassembler = Reassembler::new();
    loop {
        tokio::select! {
            reason = &mut close_rx => {
                if matches!(reason, Ok(CloseReason::Revoked)) {
                    send_revoked_error(socket, transport).await?;
                }
                return close_socket(socket, CloseCode::Revoked).await;
            }
            frame = connection::receive_frame(socket, transport, &mut reassembler) => {
                match frame {
                    Ok(_envelope_bytes) => {} // dispatch is a later phase's job; see doc comment above
                    Err(SessionError::Closed) => return Ok(()),
                    Err(err) => return Err(err),
                }
            }
        }
    }
}

/// R-11-065: sends the `revoked` error as the session's own first (and, given
/// no dispatch loop sends anything else yet, only) frame, seq `1`. A later
/// phase wiring real application-message dispatch on this loop MUST carry one
/// `SequenceCounter` for the whole session's lifetime instead (R-11-033: seq
/// MUST NOT reset within a session) rather than hardcoding `1` here.
async fn send_revoked_error(
    socket: &mut WsStream,
    transport: &mut Transport,
) -> Result<(), SessionError> {
    let message = Message::Error(ErrorMessage {
        code: ErrorCode::Revoked,
        message: "This device has been revoked.".to_owned(),
        fatal: true,
    });
    let frame = Frame::wrap(1, None, &message)?;
    let bytes = frame.to_json_bytes()?;
    connection::send_frame(socket, transport, &bytes).await
}

async fn close_socket(socket: &mut WsStream, code: CloseCode) -> Result<(), SessionError> {
    socket
        .send(WsMessage::Close(Some(CloseFrame {
            code: WsCloseCode::from(code.code()),
            reason: String::new().into(),
        })))
        .await
        .map_err(SessionError::Io)
}
