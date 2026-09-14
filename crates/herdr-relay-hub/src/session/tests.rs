//! `session.rs`'s unit tests, split into their own file (via `#[path]` in
//! `session.rs`) so `session.rs` itself stays under the 400-line cap (R-41-010,
//! R-41-011): a test module has a different reason to change (new scenario
//! coverage) than the routing/peer-loss logic it exercises.

use std::net::{IpAddr, Ipv4Addr};
use std::str::FromStr;

use herdr_relay_proto::handle::Handle;

use super::{RegisterError, Role, SessionMap};
use crate::routes::limits::IpRateLimiter;

const IP: IpAddr = IpAddr::V4(Ipv4Addr::LOCALHOST);
const UNLIMITED: usize = usize::MAX;

fn handle() -> Handle {
    Handle::from_str("n6Loxf94CfyIO6hOxlaHvA").expect("the doc's own worked example parses")
}

fn other_handle() -> Handle {
    Handle::from_str("AAAAAAAAAAAAAAAAAAAAAA").expect("a valid fixture handle")
}

fn unlimited() -> IpRateLimiter {
    IpRateLimiter::new(UNLIMITED)
}

/// R-11-118: a Host already registered under this handle refuses a second
/// Host registration. R-12-037: the rejection must not trigger cleanup of
/// the first (still live) Host connection.
#[test]
fn second_host_is_refused_and_first_untouched() {
    let sessions = SessionMap::new();
    let limiter = unlimited();
    let (first_tx, _first_rx, _) = sessions
        .register(handle(), Role::Host, IP, &limiter, UNLIMITED, false)
        .expect("first Host registers");
    let second = sessions.register(handle(), Role::Host, IP, &limiter, UNLIMITED, false);
    assert_eq!(second.unwrap_err(), RegisterError::HandleTaken);
    assert!(
        !first_tx.is_closed(),
        "the first Host's channel must survive the rejection"
    );
}

#[test]
fn device_on_unknown_handle_is_refused() {
    let sessions = SessionMap::new();
    let limiter = unlimited();
    let result = sessions.register(handle(), Role::Device, IP, &limiter, UNLIMITED, false);
    assert_eq!(result.unwrap_err(), RegisterError::HandleUnknown);
}

/// R-12-037: a rejected second Device registration must not trigger cleanup
/// of the first (still live) Device connection.
#[test]
fn second_device_is_refused_and_first_untouched() {
    let sessions = SessionMap::new();
    let limiter = unlimited();
    let (_host_tx, _host_rx, _) = sessions
        .register(handle(), Role::Host, IP, &limiter, UNLIMITED, false)
        .expect("Host registers");
    let (first_tx, _first_rx, _) = sessions
        .register(handle(), Role::Device, IP, &limiter, UNLIMITED, false)
        .expect("first Device registers");
    let second = sessions.register(handle(), Role::Device, IP, &limiter, UNLIMITED, false);
    assert_eq!(second.unwrap_err(), RegisterError::HostInUse);
    assert!(!first_tx.is_closed());
}

#[test]
fn first_registration_of_a_handle_is_new_the_second_is_not() {
    let sessions = SessionMap::new();
    let limiter = unlimited();
    let (_host_tx, _host_rx, host_is_new) = sessions
        .register(handle(), Role::Host, IP, &limiter, UNLIMITED, false)
        .expect("Host registers");
    assert!(host_is_new);
    let (.., device_is_new) = sessions
        .register(handle(), Role::Device, IP, &limiter, UNLIMITED, false)
        .expect("Device registers");
    assert!(!device_is_new);
}

#[test]
fn handle_rate_limit_refuses_a_new_handle_but_not_a_reconnect() {
    let sessions = SessionMap::new();
    let limiter = IpRateLimiter::new(1);
    sessions
        .register(handle(), Role::Host, IP, &limiter, UNLIMITED, false)
        .expect("first new handle is inside the allowance");
    let second_new_handle =
        sessions.register(other_handle(), Role::Host, IP, &limiter, UNLIMITED, false);
    assert_eq!(
        second_new_handle.unwrap_err(),
        RegisterError::HandleRateLimited
    );
}

#[test]
fn max_handles_cap_refuses_a_new_handle_but_not_a_reconnect() {
    let sessions = SessionMap::new();
    let limiter = unlimited();
    sessions
        .register(handle(), Role::Host, IP, &limiter, 1, false)
        .expect("first handle is inside the cap");
    let second_new_handle = sessions.register(other_handle(), Role::Host, IP, &limiter, 1, false);
    assert_eq!(
        second_new_handle.unwrap_err(),
        RegisterError::TooManyHandles
    );
}

#[test]
fn peer_of_is_none_until_the_device_joins() {
    let sessions = SessionMap::new();
    let limiter = unlimited();
    let (_host_tx, _host_rx, _) = sessions
        .register(handle(), Role::Host, IP, &limiter, UNLIMITED, false)
        .expect("Host registers");
    assert!(sessions.peer_of(handle(), Role::Host).is_none());
    sessions
        .register(handle(), Role::Device, IP, &limiter, UNLIMITED, false)
        .expect("Device registers");
    assert!(sessions.peer_of(handle(), Role::Host).is_some());
}

/// R-11-125: the loss discarded the room, so the Host's reconnect under the
/// same handle registers fresh — there is no slot to reclaim.
#[test]
fn a_host_reconnect_after_a_loss_registers_fresh() {
    let sessions = SessionMap::new();
    let limiter = unlimited();
    let (first_tx, first_rx, _) = sessions
        .register(handle(), Role::Host, IP, &limiter, UNLIMITED, false)
        .expect("Host registers");
    drop(first_rx); // simulates the connection task exiting, as relay.rs does
    sessions.disconnect(handle(), Role::Host, first_tx);

    let (.., is_new) = sessions
        .register(handle(), Role::Host, IP, &limiter, UNLIMITED, false)
        .expect("a reconnect after the loss must succeed");
    assert!(is_new, "the room was discarded, so this is a new handle");
}

/// R-11-125, R-12-008, R-12-038: Host loss is immediate. The Device receives a
/// `going_away` close that names the Host, the whole room is discarded, and a
/// Device that joins afterwards finds the handle unknown (R-11-117).
#[test]
fn host_loss_closes_the_device_at_once_and_discards_the_room() {
    let sessions = SessionMap::new();
    let limiter = unlimited();
    let (host_tx, host_rx, _) = sessions
        .register(handle(), Role::Host, IP, &limiter, UNLIMITED, false)
        .expect("Host registers");
    let (_device_tx, mut device_rx, _) = sessions
        .register(handle(), Role::Device, IP, &limiter, UNLIMITED, false)
        .expect("Device registers");

    drop(host_rx); // simulates the connection task exiting, as relay.rs does
    sessions.disconnect(handle(), Role::Host, host_tx);

    let close = device_rx
        .try_recv()
        .expect("the Device must receive a going_away close (R-12-038)");
    match close {
        axum::extract::ws::Message::Close(Some(frame)) => {
            assert_eq!(frame.code, 1001, "going_away, not normal (R-12-038)");
            assert_eq!(
                frame.reason.as_str(),
                "the Host is gone",
                "the reason names the gone peer (R-12-038)"
            );
        }
        other => panic!("expected a Close(1001) message, got {other:?}"),
    }
    assert_eq!(
        sessions.active_handles(),
        0,
        "the whole room must be discarded"
    );
    let join = sessions.register(handle(), Role::Device, IP, &limiter, UNLIMITED, false);
    assert_eq!(
        join.unwrap_err(),
        RegisterError::HandleUnknown,
        "a Device join after the loss finds no room (R-11-117)"
    );
}

/// R-11-125, R-12-009, R-12-038: Device loss is symmetric. The Host receives a
/// `going_away` close that names the Device and the whole room is discarded.
#[test]
fn device_loss_closes_the_host_at_once_and_discards_the_room() {
    let sessions = SessionMap::new();
    let limiter = unlimited();
    let (_host_tx, mut host_rx, _) = sessions
        .register(handle(), Role::Host, IP, &limiter, UNLIMITED, false)
        .expect("Host registers");
    let (device_tx, device_rx, _) = sessions
        .register(handle(), Role::Device, IP, &limiter, UNLIMITED, false)
        .expect("Device registers");

    drop(device_rx); // simulates the connection task exiting, as relay.rs does
    sessions.disconnect(handle(), Role::Device, device_tx);

    let close = host_rx
        .try_recv()
        .expect("the Host must receive a going_away close (R-12-038)");
    match close {
        axum::extract::ws::Message::Close(Some(frame)) => {
            assert_eq!(frame.code, 1001, "going_away, not normal (R-12-038)");
            assert_eq!(
                frame.reason.as_str(),
                "the Device is gone",
                "the reason names the gone peer (R-12-038)"
            );
        }
        other => panic!("expected a Close(1001) message, got {other:?}"),
    }
    assert_eq!(
        sessions.active_handles(),
        0,
        "the whole room must be discarded"
    );
}

/// R-12-037: the first Host's socket died and a fresh Host registration has
/// already replaced the room by the time the first connection's teardown calls
/// `disconnect`. The stale call must leave the new room untouched.
#[test]
fn a_stale_disconnect_from_a_reclaimed_slot_is_ignored() {
    let sessions = SessionMap::new();
    let limiter = unlimited();
    let (first_tx, first_rx, _) = sessions
        .register(handle(), Role::Host, IP, &limiter, UNLIMITED, false)
        .expect("first Host registers");
    let (_device_tx, mut device_rx, _) = sessions
        .register(handle(), Role::Device, IP, &limiter, UNLIMITED, false)
        .expect("Device registers");

    drop(first_rx); // the first Host's socket died; its task has not called disconnect yet
    let (second_tx, _second_rx, is_new) = sessions
        .register(handle(), Role::Host, IP, &limiter, UNLIMITED, false)
        .expect("a fresh Host registration after the loss");
    assert!(
        is_new,
        "the lost room was discarded, so this is a new handle"
    );

    // The registration finished the lost room's teardown at once (R-11-125).
    let close = device_rx
        .try_recv()
        .expect("the lost room's Device must be closed (R-11-125)");
    match close {
        axum::extract::ws::Message::Close(Some(frame)) => {
            assert_eq!(frame.code, 1001);
            assert_eq!(frame.reason.as_str(), "the Host is gone");
        }
        other => panic!("expected a Close(1001) message, got {other:?}"),
    }

    // Only now does the first connection's teardown arrive.
    sessions.disconnect(handle(), Role::Host, first_tx);
    assert!(
        !second_tx.is_closed(),
        "the stale disconnect must not touch the new room (R-12-037)"
    );
    assert_eq!(sessions.active_handles(), 1, "the new room survives");
}

#[test]
fn pairing_window_allows_an_immediate_join() {
    let sessions = SessionMap::new();
    let limiter = unlimited();
    let (_host_tx, _host_rx, _) = sessions
        .register(handle(), Role::Host, IP, &limiter, UNLIMITED, true)
        .expect("Host registers");
    let ok = sessions.register(handle(), Role::Device, IP, &limiter, UNLIMITED, false);
    assert!(ok.is_ok(), "joining immediately must still succeed");
}

/// R-11-120: a Device that never joins within the `PAIRING_WINDOW` after the
/// Host registered with `"pairing": true` (R-11-113) is refused with
/// `PairingExpired`.
#[tokio::test(start_paused = true)]
async fn pairing_window_refuses_a_late_first_join() {
    let sessions = SessionMap::new();
    let limiter = unlimited();
    let (_host_tx, _host_rx, _) = sessions
        .register(handle(), Role::Host, IP, &limiter, UNLIMITED, true)
        .expect("Host registers");

    tokio::time::advance(super::PAIRING_WINDOW + std::time::Duration::from_secs(1)).await;

    let late = sessions.register(handle(), Role::Device, IP, &limiter, UNLIMITED, false);
    assert_eq!(late.unwrap_err(), RegisterError::PairingExpired);
}

/// R-11-120: the pairing window does not apply to a registration that did
/// not declare `"pairing": true` — a paired Host's `Noise_KK` registration
/// holds the handle for as long as the Host holds the socket, so a Device's
/// late first join is accepted.
#[tokio::test(start_paused = true)]
async fn pairing_window_does_not_apply_to_a_non_pairing_registration() {
    let sessions = SessionMap::new();
    let limiter = unlimited();
    let (_host_tx, _host_rx, _) = sessions
        .register(handle(), Role::Host, IP, &limiter, UNLIMITED, false)
        .expect("Host registers");

    tokio::time::advance(super::PAIRING_WINDOW + std::time::Duration::from_secs(1)).await;

    let late = sessions.register(handle(), Role::Device, IP, &limiter, UNLIMITED, false);
    assert!(
        late.is_ok(),
        "a late first join on a non-pairing registration must be accepted"
    );
}

/// R-11-120: a fresh Host registration starts a fresh pairing window. The room
/// the first registration created was discarded when its connection ended
/// (R-11-125), and nothing carries the first window's start time over.
#[tokio::test(start_paused = true)]
async fn pairing_window_restarts_on_a_fresh_host_registration() {
    let sessions = SessionMap::new();
    let limiter = unlimited();
    let (host_tx, host_rx, _) = sessions
        .register(handle(), Role::Host, IP, &limiter, UNLIMITED, true)
        .expect("Host registers");
    tokio::time::advance(super::PAIRING_WINDOW - std::time::Duration::from_secs(1)).await;
    drop(host_rx);
    sessions.disconnect(handle(), Role::Host, host_tx);
    let (_second_tx, _second_rx, _) = sessions
        .register(handle(), Role::Host, IP, &limiter, UNLIMITED, true)
        .expect("Host re-registers after the loss");

    // One second past the first registration's window, but well inside the
    // fresh registration's window.
    tokio::time::advance(std::time::Duration::from_secs(2)).await;
    let join = sessions.register(handle(), Role::Device, IP, &limiter, UNLIMITED, false);
    assert!(
        join.is_ok(),
        "the fresh registration restarted the pairing window"
    );
}
