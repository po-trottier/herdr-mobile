//! The frame envelope that wraps every application message inside the Noise session.
//!
//! Owning rules: `docs/11-relay-protocol.md` R-11-030 (JSON/UTF-8 encoding), R-11-031
//! (the `v`/`type`/`seq`/`corr`/`payload` field set), R-11-032 (`v` MUST be `1`),
//! R-11-033/R-11-080 (`seq` monotonic per sender, starting at `1`, resetting on a new
//! Noise session), R-11-034 (`corr` presence rule), R-11-035/R-11-036/R-12-030 (the
//! 1 MiB maximum frame size and the `frame_too_large` rejection), and R-11-085 (no
//! frame is buffered for replay).

use serde::{Deserialize, Serialize};

use crate::messages::Message;

/// The current relay protocol version (R-11-032).
pub const PROTOCOL_VERSION: u32 = 1;

/// The single frame-size limit for the whole repository: 1 MiB, uncompressed JSON
/// (R-11-035, R-12-030, R-41-039).
pub const MAX_FRAME_SIZE: usize = 1_048_576;

/// The JSON envelope every frame carries inside the Noise session (R-11-031).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Frame {
    /// Protocol version. MUST be `1` (R-11-032).
    pub v: u32,
    /// Message type discriminator.
    #[serde(rename = "type")]
    pub message_type: String,
    /// Monotonic sequence number per sender, starting at `1` (R-11-033, R-11-080).
    pub seq: u64,
    /// Correlation id for request-reply pairs. Present on every request and reply,
    /// absent on unsolicited messages (R-11-034).
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub corr: Option<String>,
    /// Message-specific fields. May be `{}` when the message carries no data.
    pub payload: serde_json::Value,
}

/// An error building, reading or bounding a [`Frame`].
#[derive(Debug, thiserror::Error)]
pub enum FrameError {
    /// The frame's encoded size exceeds [`MAX_FRAME_SIZE`] (R-11-035, R-11-036).
    #[error("frame of {0} bytes exceeds the 1 MiB maximum (R-11-035)")]
    TooLarge(usize),
    /// The envelope is not valid JSON, or a `Message` did not serialize to the
    /// `{"type", "payload"}` shape this module expects.
    #[error("frame envelope is malformed: {0}")]
    Malformed(#[source] serde_json::Error),
}

impl From<serde_json::Error> for FrameError {
    fn from(error: serde_json::Error) -> Self {
        Self::Malformed(error)
    }
}

impl Frame {
    /// Builds a frame envelope around one application `message`.
    ///
    /// # Errors
    ///
    /// Returns [`FrameError::Malformed`] only if `message` cannot serialize to JSON,
    /// which does not happen for any variant of [`Message`] in practice.
    pub fn wrap(seq: u64, corr: Option<String>, message: &Message) -> Result<Self, FrameError> {
        let value = serde_json::to_value(message)?;
        let serde_json::Value::Object(mut fields) = value else {
            return Err(FrameError::Malformed(serde::de::Error::custom(
                "Message did not serialize to a JSON object",
            )));
        };
        let payload = fields
            .remove("payload")
            .unwrap_or_else(|| serde_json::Value::Object(serde_json::Map::new()));
        Ok(Self {
            v: PROTOCOL_VERSION,
            message_type: message.type_name().to_owned(),
            seq,
            corr,
            payload,
        })
    }

    /// Recovers the typed [`Message`] this frame's `type` and `payload` describe.
    ///
    /// # Errors
    ///
    /// Returns [`FrameError::Malformed`] when `message_type` is unknown or `payload`
    /// does not match that message's documented shape.
    pub fn message(&self) -> Result<Message, FrameError> {
        let value = serde_json::json!({ "type": self.message_type, "payload": self.payload });
        Ok(serde_json::from_value(value)?)
    }

    /// Serializes this frame to JSON bytes, rejecting an oversized result before it is
    /// sent (R-11-035, R-11-036).
    ///
    /// # Errors
    ///
    /// Returns [`FrameError::TooLarge`] when the encoded frame exceeds
    /// [`MAX_FRAME_SIZE`], or [`FrameError::Malformed`] if serialization fails.
    pub fn to_json_bytes(&self) -> Result<Vec<u8>, FrameError> {
        let bytes = serde_json::to_vec(self)?;
        if bytes.len() > MAX_FRAME_SIZE {
            return Err(FrameError::TooLarge(bytes.len()));
        }
        Ok(bytes)
    }

    /// Parses a frame from JSON bytes, checking the size bound before allocating a
    /// parse tree (R-41-039).
    ///
    /// # Errors
    ///
    /// Returns [`FrameError::TooLarge`] when `bytes` exceeds [`MAX_FRAME_SIZE`], or
    /// [`FrameError::Malformed`] if the bytes are not a valid `Frame`.
    pub fn from_json_bytes(bytes: &[u8]) -> Result<Self, FrameError> {
        if bytes.len() > MAX_FRAME_SIZE {
            return Err(FrameError::TooLarge(bytes.len()));
        }
        Ok(serde_json::from_slice(bytes)?)
    }
}

/// A monotonic per-sender sequence counter. Starts at `1` and never buffers a frame for
/// replay (R-11-080, R-11-085). Create a new counter on every fresh Noise session
/// (R-11-033).
#[derive(Debug, Default)]
pub struct SequenceCounter(u64);

impl SequenceCounter {
    /// Creates a counter whose first [`advance`](Self::advance) call returns `1`.
    #[must_use]
    pub const fn new() -> Self {
        Self(0)
    }

    /// Advances the counter and returns the next sequence number.
    pub fn advance(&mut self) -> u64 {
        self.0 += 1;
        self.0
    }
}

#[cfg(test)]
mod tests {
    use super::{Frame, MAX_FRAME_SIZE, PROTOCOL_VERSION, SequenceCounter};
    use crate::messages::{Message, TreeRequest};

    // R-11-031, R-11-032: Frame::wrap builds the JSON envelope shape (`v`,
    // `type`, `seq`, `corr`, `payload`) and stamps `v` with PROTOCOL_VERSION.
    #[test]
    fn wrap_and_message_round_trip() {
        let message = Message::TreeRequest(TreeRequest {});
        let frame = Frame::wrap(1, Some("corr-1".to_owned()), &message).expect("wraps cleanly");
        assert_eq!(frame.v, PROTOCOL_VERSION);
        assert_eq!(frame.message_type, "tree_request");
        assert_eq!(frame.corr.as_deref(), Some("corr-1"));
        assert_eq!(frame.message().expect("valid message"), message);
    }

    // R-11-030: a Frame round-trips through JSON/UTF-8 bytes unchanged.
    #[test]
    fn to_json_bytes_and_from_json_bytes_round_trip() {
        let message = Message::TreeRequest(TreeRequest {});
        let frame = Frame::wrap(1, None, &message).expect("wraps cleanly");
        let bytes = frame.to_json_bytes().expect("small frame serializes");
        let parsed = Frame::from_json_bytes(&bytes).expect("valid frame bytes");
        assert_eq!(parsed, frame);
    }

    #[test]
    fn from_json_bytes_rejects_a_frame_over_the_max_size() {
        let oversized = vec![b'a'; MAX_FRAME_SIZE + 1];
        let error = Frame::from_json_bytes(&oversized).expect_err("must reject oversized input");
        assert!(matches!(error, super::FrameError::TooLarge(n) if n == MAX_FRAME_SIZE + 1));
    }

    // R-11-081: a fresh counter (as created for a new Noise session) starts at 1.
    #[test]
    fn sequence_counter_starts_at_one_and_is_monotonic() {
        let mut counter = SequenceCounter::new();
        assert_eq!(counter.advance(), 1);
        assert_eq!(counter.advance(), 2);
        assert_eq!(counter.advance(), 3);
    }
}
