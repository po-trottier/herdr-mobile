//! The relay WebSocket close-code enum, the application-layer error taxonomy, and the
//! six pairing-phrase validation error codes.
//!
//! Owning rules: `docs/11-relay-protocol.md` R-11-121 (the close-code table, `1000`
//! through `4008`), §7.1 "Error taxonomy" (the `error` message `code` field values),
//! and `docs/13-security-pairing.md` R-13-027 (the six `phrase_*` validation codes,
//! restated as `docs/11-relay-protocol.md` §9.5).

use serde::{Deserialize, Serialize};

/// A relay-to-peer WebSocket close code (`docs/11-relay-protocol.md` R-11-121).
///
/// This table covers relay-to-peer close events only. Peer-to-peer errors inside the
/// Noise session use [`ErrorCode`] instead.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum CloseCode {
    /// `1000`: clean shutdown or deliberate disconnect after a `disconnect` frame.
    Normal,
    /// `1001`: ping timeout or relay shutdown. Reconnect with backoff.
    GoingAway,
    /// `1006`: network drop, no close frame. Reconnect with backoff.
    Abnormal,
    /// `1011`: relay fault. Reconnect with backoff.
    InternalError,
    /// `4000` `pairing_expired`: the phrase lifetime (R-13-022, 600 s) elapsed before the Device joined.
    PairingExpired,
    /// `4001` `handle_unknown`: no Host is registered under this handle.
    HandleUnknown,
    /// `4002` `handle_taken`: a Host is already registered under this handle.
    HandleTaken,
    /// `4003` `protocol_error`: bad subprotocol, bad path, bad handle syntax, or bad first frame.
    ProtocolError,
    /// `4004` `revoked`: the Host revoked this Device.
    Revoked,
    /// `4005` `handshake_failed`: the Noise handshake failed.
    HandshakeFailed,
    /// `4006` `host_in_use`: a Device is already active on this Host handle.
    HostInUse,
    /// `4007` `frame_too_large`: a frame exceeded the size limit.
    FrameTooLarge,
    /// `4008` `rate_limited`: a connection-rate or frame-rate limit was exceeded.
    RateLimited,
}

impl CloseCode {
    /// The numeric WebSocket close code.
    #[must_use]
    pub const fn code(self) -> u16 {
        match self {
            Self::Normal => 1000,
            Self::GoingAway => 1001,
            Self::Abnormal => 1006,
            Self::InternalError => 1011,
            Self::PairingExpired => 4000,
            Self::HandleUnknown => 4001,
            Self::HandleTaken => 4002,
            Self::ProtocolError => 4003,
            Self::Revoked => 4004,
            Self::HandshakeFailed => 4005,
            Self::HostInUse => 4006,
            Self::FrameTooLarge => 4007,
            Self::RateLimited => 4008,
        }
    }

    /// The lower-`snake_case` name used in the relay's plaintext error frame `code`
    /// field (`docs/11-relay-protocol.md` §2.4). The two standard WebSocket codes
    /// (`1000`, `1001`, `1006`, `1011`) carry no relay-defined name.
    #[must_use]
    pub const fn name(self) -> Option<&'static str> {
        match self {
            Self::Normal | Self::GoingAway | Self::Abnormal | Self::InternalError => None,
            Self::PairingExpired => Some("pairing_expired"),
            Self::HandleUnknown => Some("handle_unknown"),
            Self::HandleTaken => Some("handle_taken"),
            Self::ProtocolError => Some("protocol_error"),
            Self::Revoked => Some("revoked"),
            Self::HandshakeFailed => Some("handshake_failed"),
            Self::HostInUse => Some("host_in_use"),
            Self::FrameTooLarge => Some("frame_too_large"),
            Self::RateLimited => Some("rate_limited"),
        }
    }

    /// Recovers a [`CloseCode`] from a numeric WebSocket close code, when it is one the
    /// relay defines.
    #[must_use]
    pub const fn from_code(code: u16) -> Option<Self> {
        match code {
            1000 => Some(Self::Normal),
            1001 => Some(Self::GoingAway),
            1006 => Some(Self::Abnormal),
            1011 => Some(Self::InternalError),
            4000 => Some(Self::PairingExpired),
            4001 => Some(Self::HandleUnknown),
            4002 => Some(Self::HandleTaken),
            4003 => Some(Self::ProtocolError),
            4004 => Some(Self::Revoked),
            4005 => Some(Self::HandshakeFailed),
            4006 => Some(Self::HostInUse),
            4007 => Some(Self::FrameTooLarge),
            4008 => Some(Self::RateLimited),
            _ => None,
        }
    }
}

/// The `error` application message's `code` field (`docs/11-relay-protocol.md` §7.1).
/// Distinct from [`CloseCode`]: this taxonomy covers peer-to-peer errors carried inside
/// the Noise session, not relay-to-peer WebSocket closes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ErrorCode {
    /// Relay protocol version mismatch. Raised by both peers. Fatal.
    ProtocolMismatch,
    /// Herdr socket protocol is not `21`. Raised by the Host. Fatal.
    HerdrProtocolMismatch,
    /// Unknown message `type`. Raised by both peers. Not fatal.
    UnknownMessage,
    /// Frame exceeds 1 MiB. Raised by both peers. Not fatal.
    FrameTooLarge,
    /// Pane does not exist. Raised by the Host. Not fatal.
    PaneNotFound,
    /// Agent does not exist. Raised by the Host. Not fatal.
    AgentNotFound,
    /// Malformed request rejected by Herdr (R-02-009). Raised by the Host. Not fatal.
    InvalidRequest,
    /// Unsupported key name. Raised by the Host. Not fatal.
    InvalidKey,
    /// Herdr request timed out. Raised by the Host. Not fatal.
    Timeout,
    /// Agent did not respond within 5000 ms. Raised by the Host. Not fatal.
    AgentPromptStalled,
    /// Pane is not being watched. Raised by the Host. Not fatal.
    NotWatching,
    /// Device has been revoked. Raised by the Host. Fatal.
    Revoked,
    /// No Host registered under this handle. Raised by the relay. Fatal.
    HandleUnknown,
    /// A Device is already active on this Host. Raised by the relay. Fatal.
    HostInUse,
    /// The phrase lifetime (R-13-022, 600 s) elapsed. Raised by the relay. Fatal.
    PairingExpired,
    /// Connection-rate or frame-rate limit exceeded. Raised by the relay. Fatal.
    RateLimited,
    /// Noise handshake failed. Raised by both peers. Fatal.
    HandshakeFailed,
    /// Named plugin has been disabled since the action list was fetched. Raised by the
    /// Host. Not fatal.
    PluginDisabled,
    /// Action id is unknown to the named plugin. Raised by the Host. Not fatal.
    ActionUnknown,
    /// Unexpected error. Raised by both peers. Not fatal.
    InternalError,
}

/// A pairing-phrase validation failure code (`docs/13-security-pairing.md` R-13-027,
/// `docs/11-relay-protocol.md` §9.5).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PhraseErrorCode {
    /// The phrase does not hold exactly six words.
    PhraseWordCount,
    /// A word is not in the EFF long list.
    PhraseWordUnknown,
    /// An empty word, a repeated hyphen, a leading or trailing hyphen, or whitespace
    /// inside the phrase.
    PhraseSeparator,
    /// A character is not lowercase ASCII after normalisation.
    PhraseCase,
    /// More than 120 seconds elapsed since the Host generated the phrase.
    PhraseExpired,
    /// More than three failed handshake attempts used this phrase.
    PhraseAttempts,
}

#[cfg(test)]
mod tests {
    use super::{CloseCode, ErrorCode, PhraseErrorCode};

    #[test]
    fn close_code_round_trips_through_its_numeric_value() {
        for close_code in [
            CloseCode::Normal,
            CloseCode::GoingAway,
            CloseCode::Abnormal,
            CloseCode::InternalError,
            CloseCode::PairingExpired,
            CloseCode::HandleUnknown,
            CloseCode::HandleTaken,
            CloseCode::ProtocolError,
            CloseCode::Revoked,
            CloseCode::HandshakeFailed,
            CloseCode::HostInUse,
            CloseCode::FrameTooLarge,
            CloseCode::RateLimited,
        ] {
            assert_eq!(CloseCode::from_code(close_code.code()), Some(close_code));
        }
    }

    #[test]
    fn close_code_matches_the_r_11_121_table() {
        assert_eq!(CloseCode::PairingExpired.code(), 4000);
        assert_eq!(CloseCode::HandleUnknown.code(), 4001);
        assert_eq!(CloseCode::HandleTaken.code(), 4002);
        assert_eq!(CloseCode::ProtocolError.code(), 4003);
        assert_eq!(CloseCode::Revoked.code(), 4004);
        assert_eq!(CloseCode::HandshakeFailed.code(), 4005);
        assert_eq!(CloseCode::HostInUse.code(), 4006);
        assert_eq!(CloseCode::FrameTooLarge.code(), 4007);
        assert_eq!(CloseCode::RateLimited.code(), 4008);
        assert_eq!(CloseCode::HandleTaken.name(), Some("handle_taken"));
        assert_eq!(CloseCode::Normal.name(), None);
    }

    /// Wire enum values MUST be snake_case (`docs/41-code-standards.md` R-41-166).
    #[test]
    fn error_code_serializes_to_the_documented_snake_case_string() {
        let json = serde_json::to_string(&ErrorCode::HerdrProtocolMismatch)
            .expect("ErrorCode always serializes");
        assert_eq!(json, "\"herdr_protocol_mismatch\"");
        let json =
            serde_json::to_string(&ErrorCode::HostInUse).expect("ErrorCode always serializes");
        assert_eq!(json, "\"host_in_use\"");
    }

    /// Wire enum values MUST be snake_case (`docs/41-code-standards.md` R-41-166).
    #[test]
    fn phrase_error_code_serializes_to_the_documented_snake_case_string() {
        for (code, expected) in [
            (PhraseErrorCode::PhraseWordCount, "\"phrase_word_count\""),
            (
                PhraseErrorCode::PhraseWordUnknown,
                "\"phrase_word_unknown\"",
            ),
            (PhraseErrorCode::PhraseSeparator, "\"phrase_separator\""),
            (PhraseErrorCode::PhraseCase, "\"phrase_case\""),
            (PhraseErrorCode::PhraseExpired, "\"phrase_expired\""),
            (PhraseErrorCode::PhraseAttempts, "\"phrase_attempts\""),
        ] {
            assert_eq!(
                serde_json::to_string(&code).expect("PhraseErrorCode always serializes"),
                expected
            );
        }
    }
}
