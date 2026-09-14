//! The plaintext JSON registration handshake that opens every connection, before
//! the Noise tunnel starts (`docs/11-relay-protocol.md` §2.3, §2.4: R-11-113 to
//! R-11-116). Split out of `routes.rs` along this responsibility boundary — wire
//! framing versus connection/rate-limit orchestration — to keep both files under
//! the 400-line cap (R-41-010, R-41-011).

use axum::extract::ws::{Message, WebSocket};
use futures_util::StreamExt;
use herdr_relay_proto::handle::Handle;
use serde::{Deserialize, Serialize};
use tokio::time::timeout;

use super::{MAX_FRAME_BYTES, REGISTER_TIMEOUT};
use crate::session::Role;

/// The registration frame R-11-113/R-11-114 requires as the first message on every
/// connection: `{"type":"host_register","protocol":1}` or
/// `{"type":"device_register","protocol":1}`. A first-pairing `host_register`
/// carries `"pairing": true` (R-11-113); every other registration omits it.
#[derive(Deserialize)]
struct RegisterFrame {
    #[serde(rename = "type")]
    kind: String,
    protocol: u32,
    #[serde(default)]
    pairing: bool,
}

/// Waits for and validates the registration frame (R-11-113, R-11-114). `None`
/// covers every failure mode alike (timeout, transport error, non-text message,
/// oversized text, malformed JSON, wrong `type`, wrong `protocol`): the caller
/// closes with the same `protocol_error` either way. On success returns the
/// frame's `pairing` flag — meaningful only for a Host registration (R-11-113);
/// a Device registration ignores it.
pub(super) async fn wait_for_registration(socket: &mut WebSocket, role: Role) -> Option<bool> {
    let expected_type = match role {
        Role::Host => "host_register",
        Role::Device => "device_register",
    };
    let Ok(Some(Ok(message))) = timeout(REGISTER_TIMEOUT, socket.next()).await else {
        return None;
    };
    let Message::Text(text) = message else {
        return None;
    };
    if text.len() > MAX_FRAME_BYTES {
        return None;
    }
    let Ok(frame) = serde_json::from_str::<RegisterFrame>(&text) else {
        return None;
    };
    (frame.kind == expected_type && frame.protocol == 1).then_some(frame.pairing)
}

/// `{"type":"session_joined","role":"host"|"device"}` (R-11-115).
pub(super) fn session_joined_frame(role: Role) -> String {
    #[derive(Serialize)]
    struct SessionJoined {
        #[serde(rename = "type")]
        kind: &'static str,
        role: &'static str,
    }
    let role = match role {
        Role::Host => "host",
        Role::Device => "device",
    };
    serde_json::to_string(&SessionJoined {
        kind: "session_joined",
        role,
    })
    .unwrap_or_default()
}

/// `{"type":"error","code":"...","message":"..."}` (R-11-116).
pub(super) fn error_frame(code: &str, message: &str) -> String {
    #[derive(Serialize)]
    struct ErrorFrame<'a> {
        #[serde(rename = "type")]
        kind: &'static str,
        code: &'a str,
        message: &'a str,
    }
    serde_json::to_string(&ErrorFrame {
        kind: "error",
        code,
        message,
    })
    .unwrap_or_default()
}

/// The first 6 characters of the handle's base64url text, for log correlation only
/// (R-12-041 `handle_first_6`) — the full handle is never logged (R-41-031).
pub(crate) fn handle_first_6(handle: Handle) -> String {
    handle.to_string().chars().take(6).collect()
}

#[cfg(test)]
mod tests {
    use std::str::FromStr;

    use herdr_relay_proto::handle::Handle;

    use super::{error_frame, handle_first_6, session_joined_frame};
    use crate::session::Role;

    #[test]
    fn session_joined_frame_matches_r_11_115() {
        assert_eq!(
            session_joined_frame(Role::Host),
            r#"{"type":"session_joined","role":"host"}"#
        );
        assert_eq!(
            session_joined_frame(Role::Device),
            r#"{"type":"session_joined","role":"device"}"#
        );
    }

    #[test]
    fn error_frame_matches_r_11_116() {
        assert_eq!(
            error_frame("handle_unknown", "No Host is registered under this handle"),
            r#"{"type":"error","code":"handle_unknown","message":"No Host is registered under this handle"}"#
        );
    }

    #[test]
    fn handle_first_6_never_returns_the_full_handle() {
        let handle = Handle::from_str("n6Loxf94CfyIO6hOxlaHvA").expect("the doc's own example");
        let prefix = handle_first_6(handle);
        assert_eq!(prefix, "n6Loxf");
        assert_ne!(prefix, handle.to_string());
    }
}
