//! The relay's one piece of routing state: the in-memory handle map
//! (`docs/12-relay-hosting.md` "## Handle Routing", R-12-004, R-12-013), the
//! symmetric peer-loss close and room discard (R-11-125, R-12-008, R-12-009,
//! R-12-038), the 600-second pairing window (R-11-120), the
//! handle-registration rate limit (R-12-033) and the total-handle cap
//! (R-12-034).

use std::collections::HashMap;
use std::net::IpAddr;
use std::sync::{Arc, Mutex, PoisonError};
use std::time::Duration;

use axum::extract::ws::{CloseFrame, Message, Utf8Bytes};
use herdr_relay_proto::codes::CloseCode;
use herdr_relay_proto::handle::Handle;
use tokio::sync::mpsc;
use tokio::time::Instant;

use crate::routes::limits::IpRateLimiter;

// ponytail: mpsc::channel(OUTBOUND_QUEUE_DEPTH) per peer — a slow peer's write loop
// applies backpressure to whoever forwards into it instead of growing without bound;
// raise this only if a legitimate burst measurably overflows it (R-41-130).
const OUTBOUND_QUEUE_DEPTH: usize = 32;

/// R-11-120: how long a Device has to join after the Host registers a pairing
/// before the relay refuses it with `pairing_expired`. Only checked on a handle
/// whose Host registered with `"pairing": true` (R-11-113): a paired
/// (`Noise_KK`) registration is never window-limited at all, and a fresh Host
/// registration starts a fresh window because a peer loss discards the room
/// (R-11-125).
const PAIRING_WINDOW: Duration = Duration::from_secs(600);

/// The channel a connection's own task drains to write frames to its socket. The
/// other side's forwarder holds a clone to enqueue frames onto it (R-12-003).
pub type OutboundTx = mpsc::Sender<Message>;

/// Which side of a room a connection registers as.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Role {
    Host,
    Device,
}

/// Why a registration attempt was refused. The existing occupant, and every other
/// handle's room, is left untouched either way (R-12-004, R-12-035, R-12-037).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RegisterError {
    /// R-11-118: a Host is already registered under this handle.
    HandleTaken,
    /// R-11-119: a Device is already active on this Host.
    HostInUse,
    /// R-11-117: a Device presented a handle no Host has registered.
    HandleUnknown,
    /// R-11-120: a Device joined more than [`PAIRING_WINDOW`] after the Host
    /// registered with `"pairing": true` (R-11-113).
    PairingExpired,
    /// R-12-033: this source IP has registered more than the configured number of
    /// new handles in the last second.
    HandleRateLimited,
    /// R-12-034: the relay already holds the configured maximum number of
    /// registered handles.
    TooManyHandles,
}

/// One handle's Host and Device slots (docs/12 "## Handle Routing"). A room lives
/// exactly as long as its connections: when either side's socket ends,
/// [`SessionMap::disconnect`] closes the other peer with `going_away` and removes
/// the room at once (R-11-125, R-12-038). A slot found holding a closed
/// [`OutboundTx`] belongs to a connection whose teardown is in flight — the room
/// is already lost, and [`SessionMap::register`] finishes that teardown before it
/// answers.
struct Room {
    host: Option<OutboundTx>,
    device: Option<OutboundTx>,
    host_registered_at: Instant,
    /// R-11-113/R-11-120: `true` when the Host's registration frame carried
    /// `"pairing": true` — only then does the [`PAIRING_WINDOW`] check apply
    /// to a Device join. A paired (`Noise_KK`) registration omits the field and
    /// is never window-limited.
    pairing: bool,
}

impl Room {
    fn new(host_tx: OutboundTx, pairing: bool) -> Self {
        Self {
            host: Some(host_tx),
            device: None,
            host_registered_at: Instant::now(),
            pairing,
        }
    }

    /// The role whose connection is gone (its [`OutboundTx`] is closed), if any.
    /// Such a room is doomed: its connection's [`SessionMap::disconnect`] is in
    /// flight and will discard the room (R-11-125).
    fn closed_role(&self) -> Option<Role> {
        if self.host.as_ref().is_some_and(|tx| tx.is_closed()) {
            Some(Role::Host)
        } else if self.device.as_ref().is_some_and(|tx| tx.is_closed()) {
            Some(Role::Device)
        } else {
            None
        }
    }
}

/// The shared, cloneable handle-routing map. Every clone shares the same state.
#[derive(Clone, Default)]
pub struct SessionMap(Arc<Mutex<HashMap<Handle, Room>>>);

impl SessionMap {
    /// Creates an empty routing map.
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// The current number of registered handles (R-12-050 `herdr_relay_handles_active`).
    #[must_use]
    pub fn active_handles(&self) -> usize {
        self.lock().len()
    }

    /// Registers `role` under `handle` from source `ip`. Returns this connection's
    /// own outbound sender (kept for the identity-checked [`Self::disconnect`]
    /// later), the receiver its write loop drains, and whether this call created a
    /// brand-new handle (for `herdr_relay_handles_total`, R-12-050). `pairing` is
    /// the registration frame's `"pairing": true` flag (R-11-113): it is read only
    /// for a Host registration, where it decides whether the [`PAIRING_WINDOW`]
    /// check (R-11-120) applies to this handle at all.
    ///
    /// A Host creates the room on its first registration; a Device may only join a
    /// room a Host already created. There is no grace window after a loss
    /// (R-11-125): a room with a closed slot is already lost — its connection's
    /// [`Self::disconnect`] is in flight but has not run yet — so registration
    /// finishes that teardown first (closes the surviving peer, discards the
    /// room), and a fresh registration after a loss creates a fresh room. The
    /// stale disconnect that lands later finds a slot it does not own and does
    /// nothing (R-12-037).
    ///
    /// # Errors
    ///
    /// See [`RegisterError`] for every rejection this can return.
    pub fn register(
        &self,
        handle: Handle,
        role: Role,
        ip: IpAddr,
        handle_limiter: &IpRateLimiter,
        max_handles: usize,
        pairing: bool,
    ) -> Result<(OutboundTx, mpsc::Receiver<Message>, bool), RegisterError> {
        let (tx, rx) = mpsc::channel(OUTBOUND_QUEUE_DEPTH);
        let mut rooms = self.lock();
        let doomed = rooms.get(&handle).and_then(Room::closed_role);
        if let Some(gone) = doomed {
            let peer_to_close = rooms.remove(&handle).and_then(|mut room| match gone {
                Role::Host => room.device.take(),
                Role::Device => room.host.take(),
            });
            // `try_send` does not block, so this is safe under the lock.
            if let Some(peer_tx) = peer_to_close {
                close_peer(peer_tx, gone);
            }
        }
        let is_new = match role {
            Role::Host => match rooms.get_mut(&handle) {
                Some(_) => return Err(RegisterError::HandleTaken),
                None => {
                    if !handle_limiter.allow(ip) {
                        return Err(RegisterError::HandleRateLimited);
                    }
                    if rooms.len() >= max_handles {
                        return Err(RegisterError::TooManyHandles);
                    }
                    rooms.insert(handle, Room::new(tx.clone(), pairing));
                    true
                }
            },
            Role::Device => {
                let Some(room) = rooms.get_mut(&handle) else {
                    return Err(RegisterError::HandleUnknown);
                };
                if room.pairing && room.host_registered_at.elapsed() > PAIRING_WINDOW {
                    return Err(RegisterError::PairingExpired);
                }
                if room.device.is_some() {
                    return Err(RegisterError::HostInUse);
                }
                room.device = Some(tx.clone());
                false
            }
        };
        Ok((tx, rx, is_new))
    }

    /// Returns the other side's outbound sender, if it has joined. The caller MUST
    /// drop the frame silently when this is `None` (R-12-036).
    #[must_use]
    pub fn peer_of(&self, handle: Handle, role: Role) -> Option<OutboundTx> {
        let rooms = self.lock();
        let room = rooms.get(&handle)?;
        match role {
            Role::Host => room.device.clone(),
            Role::Device => room.host.clone(),
        }
    }

    /// Called when a connection's read/write loop exits. Peer loss is symmetric
    /// and immediate (R-11-125, R-12-008, R-12-009): the other peer's outbound
    /// queue receives a `going_away` close that names the side that is gone
    /// (R-12-038), and the whole room is discarded at once. There is no grace
    /// window — a Noise transport state lives in the peer process, so no
    /// relay-side window can resume a session across a peer restart.
    ///
    /// The close and the discard happen only when the slot still holds `mine`:
    /// a stale disconnect from a connection whose room was already discarded —
    /// by the peer's own loss, or by a fresh registration that reclaimed the
    /// handle — is a no-op (R-12-037).
    ///
    /// The caller MUST have already dropped its own `mpsc::Receiver` before
    /// calling this, so `mine.is_closed()` is already `true` and a concurrent
    /// [`Self::register`] can tell this connection is gone.
    ///
    /// `peer_close` is the close frame the leaving peer sent, if any. When it
    /// carries an application code (R-12-038 amended 2026-09-18) the survivor
    /// receives that frame verbatim: a Host that refuses a Device with `4006`
    /// after the Noise handshake (one active Device per Host, R-10-069) speaks
    /// for itself, and the Device must hear that code, not `1001`. Every other
    /// close becomes `going_away`.
    pub fn disconnect(
        &self,
        handle: Handle,
        role: Role,
        mine: OutboundTx,
        peer_close: Option<CloseFrame>,
    ) {
        let peer_to_close = {
            let mut rooms = self.lock();
            let owns_slot = rooms.get(&handle).is_some_and(|room| {
                let slot = match role {
                    Role::Host => &room.host,
                    Role::Device => &room.device,
                };
                slot.as_ref().is_some_and(|tx| tx.same_channel(&mine))
            });
            if !owns_slot {
                return;
            }
            // The identity check just proved this room exists and holds `mine`.
            if let Some(mut room) = rooms.remove(&handle) {
                match role {
                    Role::Host => room.device.take(),
                    Role::Device => room.host.take(),
                }
            } else {
                None
            }
        };
        if let Some(peer_tx) = peer_to_close {
            match peer_close.filter(|frame| (4000..=4999).contains(&frame.code)) {
                Some(frame) => {
                    let _ = peer_tx.try_send(Message::Close(Some(frame)));
                }
                None => close_peer(peer_tx, role),
            }
        }
        // R-12-041: the handle registration is gone, in either direction.
        crate::routes::logging::handle_expired(
            &handle.to_string()[..6],
            self.active_handles() as u64,
        );
    }

    /// Locks the map. Never poisons in practice: no critical section below panics.
    /// Recovering the guard on a poison anyway avoids `unwrap` (R-41-126).
    fn lock(&self) -> std::sync::MutexGuard<'_, HashMap<Handle, Room>> {
        self.0.lock().unwrap_or_else(PoisonError::into_inner)
    }
}

/// R-12-038: closes the surviving peer's outbound queue with `going_away`
/// (`1001`), never `normal` — that peer did not initiate the shutdown. The reason
/// names the side that is gone (R-11-125). `try_send` because the peer's own
/// connection task may already be exiting: a close that nobody drains has nothing
/// left to do.
fn close_peer(peer_tx: OutboundTx, gone: Role) {
    let reason = match gone {
        Role::Host => "the Host is gone",
        Role::Device => "the Device is gone",
    };
    let _ = peer_tx.try_send(Message::Close(Some(CloseFrame {
        code: CloseCode::GoingAway.code(),
        reason: Utf8Bytes::from_static(reason),
    })));
}

#[cfg(test)]
#[path = "session/tests.rs"]
mod tests;
