//! The byte pump: verbatim binary-frame forwarding between a joined Host and Device,
//! with no inspection, decryption, modification or persistence (R-12-003, R-01-012,
//! R-11-026, R-11-027), plus the relay-owned ping/pong heartbeat (R-12-022), the
//! per-frame size limit (R-12-030), the per-connection frame-rate limit (R-12-032)
//! and the R-12-041 connect/disconnect log lines.

use std::time::Duration;

use axum::body::Bytes;
use axum::extract::ws::{CloseFrame, Message, Utf8Bytes, WebSocket};
use futures_util::stream::SplitSink;
use futures_util::{SinkExt, StreamExt};
use herdr_relay_proto::codes::CloseCode;
use herdr_relay_proto::handle::Handle;
use tokio::sync::mpsc;
use tokio::time::{Instant, timeout};

use crate::heartbeat::{Heartbeat, HeartbeatEvent};
use crate::routes::AppState;
use crate::routes::limits::FrameRateLimiter;
use crate::routes::logging;
use crate::routes::{MAX_FRAME_BYTES, handle_first_6};
use crate::session::{OutboundTx, Role};

/// A send MUST NOT block the connection's task forever when a peer stalls (R-41-131).
/// A stalled recv is already bounded by the pong deadline, so only sends need their
/// own timeout here.
const SEND_TIMEOUT: Duration = Duration::from_secs(10);

/// The write half of a joined connection's socket.
type PeerSink = SplitSink<WebSocket, Message>;

/// Drives one joined peer connection until it closes: forwards its binary frames to
/// the other side's outbound queue, drains its own outbound queue to the socket, and
/// answers the relay's own heartbeat. On exit it tears the room down by socket
/// identity (R-12-037): the other peer is closed with `going_away` and the room is
/// discarded at once (R-11-125, R-12-038).
pub async fn run_peer(
    socket: WebSocket,
    state: AppState,
    handle: Handle,
    role: Role,
    my_tx: OutboundTx,
    mut inbound: mpsc::Receiver<Message>,
) {
    let (mut sink, mut stream) = socket.split();
    let mut heartbeat = Heartbeat::new();
    let mut frame_limiter = FrameRateLimiter::new(state.config.frame_rate_per_sec);
    let mut frames_forwarded: u64 = 0;
    let mut bytes_forwarded: u64 = 0;
    let started = Instant::now();
    loop {
        tokio::select! {
            // Cancel-safe: SplitStream::next() drops cleanly with no partial-read state.
            frame = stream.next() => match frame {
                Some(Ok(Message::Binary(bytes))) => {
                    if bytes.len() > MAX_FRAME_BYTES {
                        send_close(&mut sink, CloseCode::FrameTooLarge, "frame exceeds the 1 MiB limit").await;
                        state.metrics.record_error(CloseCode::FrameTooLarge);
                        logging::error(
                            state.sessions.active_handles() as u64,
                            CloseCode::FrameTooLarge.name().unwrap_or(""),
                            "frame exceeds the 1 MiB limit",
                        );
                        break;
                    }
                    if !frame_limiter.allow() {
                        send_close(&mut sink, CloseCode::RateLimited, "frame rate limit exceeded").await;
                        state.metrics.record_error(CloseCode::RateLimited);
                        logging::error(
                            state.sessions.active_handles() as u64,
                            CloseCode::RateLimited.name().unwrap_or(""),
                            "frame rate limit exceeded",
                        );
                        break;
                    }
                    frames_forwarded += 1;
                    bytes_forwarded += bytes.len() as u64;
                    state.metrics.record_forward(role, bytes.len());
                    forward(&state, handle, role, bytes).await;
                }
                Some(Ok(Message::Pong(_))) => heartbeat.note_pong(),
                Some(Ok(Message::Text(_) | Message::Ping(_))) => {}
                Some(Ok(Message::Close(_))) | None | Some(Err(_)) => break,
            },
            // Cancel-safe: tokio::sync::mpsc::Receiver::recv() drops cleanly.
            Some(outgoing) = inbound.recv() => {
                if send(&mut sink, outgoing).await.is_err() {
                    break;
                }
            }
            // Cancel-safe: Heartbeat::wait() drops cleanly and recomputes its state
            // from `heartbeat` on every call (see heartbeat.rs).
            event = heartbeat.wait() => match event {
                HeartbeatEvent::PingDue => {
                    if send(&mut sink, Message::Ping(Bytes::new())).await.is_err() {
                        break;
                    }
                    heartbeat.note_ping_sent();
                }
                HeartbeatEvent::PongOverdue => break,
            },
        }
    }
    // The receiver MUST already be gone before `disconnect` runs below: a
    // concurrent `SessionMap::register` detects this connection's loss through
    // `my_tx.is_closed()`, which only becomes true once `inbound` drops.
    drop(inbound);
    let duration_ms = started.elapsed().as_millis() as u64;
    state.metrics.record_session_duration(duration_ms);
    let h6 = handle_first_6(handle);
    let active = state.sessions.active_handles() as u64;
    match role {
        Role::Host => {
            logging::host_disconnected(&h6, active, frames_forwarded, bytes_forwarded, duration_ms)
        }
        Role::Device => logging::device_disconnected(
            &h6,
            active,
            frames_forwarded,
            bytes_forwarded,
            duration_ms,
        ),
    }
    state.sessions.disconnect(handle, role, my_tx);
}

/// Looks up the other side's outbound queue and enqueues the frame, or drops it
/// silently when no peer has joined yet (R-12-036).
async fn forward(state: &AppState, handle: Handle, role: Role, bytes: Bytes) {
    let Some(peer_tx) = state.sessions.peer_of(handle, role) else {
        return;
    };
    // ponytail: the peer's own connection task may have already exited between the
    // lookup above and this send; nobody is left to observe that failure, which is
    // the same silent drop R-12-036 already requires for an empty peer slot.
    let _ = peer_tx.send(Message::Binary(bytes)).await;
}

/// Sends one message with the bounded timeout every I/O path needs (R-41-131).
async fn send(sink: &mut PeerSink, msg: Message) -> Result<(), ()> {
    match timeout(SEND_TIMEOUT, sink.send(msg)).await {
        Ok(Ok(())) => Ok(()),
        Ok(Err(_)) | Err(_) => Err(()),
    }
}

/// Sends one close frame with `code` and `reason` (R-12-030, R-12-032).
// ponytail: the send result is discarded — the peer may already be gone, and there
// is nothing left to do about a failed close on a socket that is closing anyway.
async fn send_close(sink: &mut PeerSink, code: CloseCode, reason: &'static str) {
    let _ = sink
        .send(Message::Close(Some(CloseFrame {
            code: code.code(),
            reason: Utf8Bytes::from_static(reason),
        })))
        .await;
}
