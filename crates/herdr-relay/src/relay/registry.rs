//! Tracking the Host's live relay session(s) by routing handle, so a
//! revocation can find and close the right one (R-13-053 steps 2-3, R-13-056
//! steps 2-3).

use std::collections::HashMap;
use std::sync::{Mutex, PoisonError};

use tokio::sync::oneshot;

use herdr_relay_proto::handle::Handle;
use herdr_relay_proto::messages::RevokeResult;

/// Why a live session is being closed.
#[derive(Debug, Clone, Copy)]
pub enum CloseReason {
    /// R-13-053, R-13-056: the Device (or every Device) was revoked.
    Revoked,
}

struct RegisteredSession {
    device_id: Option<String>,
    close: oneshot::Sender<CloseReason>,
}

/// The Host's live outbound relay session(s), keyed by routing handle.
/// R-03-040/R-11-123: at most one Device is ever connected to this Host at a
/// time, so in practice this holds at most one entry — it is still keyed by
/// [`Handle`] rather than being a single `Option`, per the actual ask, so a
/// session mid-teardown never silently masks a session that has just
/// replaced it under a new handle.
#[derive(Default)]
pub struct SessionRegistry {
    sessions: Mutex<HashMap<Handle, RegisteredSession>>,
}

impl SessionRegistry {
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// Registers a live session under `handle`, returning the receiver its
    /// connection-driving task selects on to learn when to close
    /// (`super::session::run_host_session`).
    pub fn register(
        &self,
        handle: Handle,
        device_id: Option<String>,
    ) -> oneshot::Receiver<CloseReason> {
        let (tx, rx) = oneshot::channel();
        let mut sessions = self.sessions.lock().unwrap_or_else(PoisonError::into_inner);
        sessions.insert(
            handle,
            RegisteredSession {
                device_id,
                close: tx,
            },
        );
        rx
    }

    /// Records `device_id` once it becomes known (after `device_info`
    /// arrives), so a later revocation by device id can find this session.
    pub fn set_device_id(&self, handle: Handle, device_id: String) {
        let mut sessions = self.sessions.lock().unwrap_or_else(PoisonError::into_inner);
        if let Some(session) = sessions.get_mut(&handle) {
            session.device_id = Some(device_id);
        }
    }

    /// Removes `handle`'s entry with no close signal: the connection already
    /// ended on its own (network drop, not a revocation). Called by
    /// `super::session::run_host_session` on every exit path, so a stale
    /// entry never survives the task.
    pub fn unregister(&self, handle: Handle) {
        let mut sessions = self.sessions.lock().unwrap_or_else(PoisonError::into_inner);
        sessions.remove(&handle);
    }

    /// R-13-053 steps 2-3 / R-13-056 steps 2-3: closes every live session
    /// whose `device_id` is named in `result.revoked` (or every session, if
    /// `result.all`), and removes it from this registry — this Host's own
    /// "destroy the handle" bookkeeping. The relay's own routing-table entry
    /// for the handle ends the moment the Host's own connection does
    /// (R-11-125: only the Device side of a handle carries a hold-open; "The
    /// Host registration lives as long as the Host connection lives"), so
    /// closing the socket here is both steps at once. A device that is not
    /// currently connected has nothing live to close here, matching
    /// R-13-053's own "If the Device has an active Noise session" condition.
    /// Returns the count actually closed, which may legitimately be zero.
    pub fn close_for_revocation(&self, result: &RevokeResult) -> usize {
        let mut sessions = self.sessions.lock().unwrap_or_else(PoisonError::into_inner);
        let to_close: Vec<Handle> = sessions
            .iter()
            .filter(|(_, session)| {
                result.all
                    || session
                        .device_id
                        .as_deref()
                        .is_some_and(|id| result.revoked.iter().any(|revoked| revoked == id))
            })
            .map(|(handle, _)| *handle)
            .collect();
        let mut closed = 0;
        for handle in to_close {
            if let Some(session) = sessions.remove(&handle)
                && session.close.send(CloseReason::Revoked).is_ok()
            {
                closed += 1;
            }
        }
        closed
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn close_for_revocation_closes_only_the_named_device() {
        let registry = SessionRegistry::new();
        let handle_a = Handle::generate().expect("generate handle a");
        let handle_b = Handle::generate().expect("generate handle b");
        let mut rx_a = registry.register(handle_a, Some("device-a".to_string()));
        let mut rx_b = registry.register(handle_b, Some("device-b".to_string()));

        let result = RevokeResult {
            revoked: vec!["device-a".to_string()],
            all: false,
        };
        let closed = registry.close_for_revocation(&result);

        assert_eq!(closed, 1);
        assert!(matches!(rx_a.try_recv(), Ok(CloseReason::Revoked)));
        assert!(
            rx_b.try_recv().is_err(),
            "device-b's session was not closed"
        );
    }

    #[test]
    fn close_for_revocation_all_closes_every_session() {
        let registry = SessionRegistry::new();
        let handle_a = Handle::generate().expect("generate handle a");
        let handle_b = Handle::generate().expect("generate handle b");
        let mut rx_a = registry.register(handle_a, Some("device-a".to_string()));
        let mut rx_b = registry.register(handle_b, Some("device-b".to_string()));

        let result = RevokeResult {
            revoked: vec!["device-a".to_string(), "device-b".to_string()],
            all: true,
        };
        let closed = registry.close_for_revocation(&result);

        assert_eq!(closed, 2);
        assert!(matches!(rx_a.try_recv(), Ok(CloseReason::Revoked)));
        assert!(matches!(rx_b.try_recv(), Ok(CloseReason::Revoked)));
    }

    #[test]
    fn close_for_revocation_returns_zero_for_a_device_not_connected() {
        let registry = SessionRegistry::new();
        let result = RevokeResult {
            revoked: vec!["device-not-connected".to_string()],
            all: false,
        };
        assert_eq!(registry.close_for_revocation(&result), 0);
    }

    #[test]
    fn set_device_id_lets_a_later_revoke_find_the_session() {
        let registry = SessionRegistry::new();
        let handle = Handle::generate().expect("generate a handle");
        let mut rx = registry.register(handle, None); // device_info not yet received
        registry.set_device_id(handle, "device-a".to_string());

        let result = RevokeResult {
            revoked: vec!["device-a".to_string()],
            all: false,
        };
        assert_eq!(registry.close_for_revocation(&result), 1);
        assert!(matches!(rx.try_recv(), Ok(CloseReason::Revoked)));
    }

    #[test]
    fn unregister_removes_with_no_close_signal() {
        let registry = SessionRegistry::new();
        let handle = Handle::generate().expect("generate a handle");
        let rx = registry.register(handle, Some("device-a".to_string()));
        registry.unregister(handle);

        let result = RevokeResult {
            revoked: vec!["device-a".to_string()],
            all: false,
        };
        assert_eq!(
            registry.close_for_revocation(&result),
            0,
            "an unregistered session is not found"
        );
        drop(rx); // never received a close signal, and never will
    }
}
