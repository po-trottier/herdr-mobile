//! The session-control messages (`docs/11-relay-protocol.md` §4.22, §4.23): errors and
//! deliberate disconnect.

use serde::{Deserialize, Serialize};

use crate::codes::ErrorCode;

/// `error` (§4.22). Sender: either. Reply: no. Correlation: optional. `fatal: true`
/// MUST be the last frame before the Noise session closes (R-11-065).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ErrorMessage {
    pub code: ErrorCode,
    /// Shown raw in the app; never replaced with a friendly sentence (R-11-092).
    pub message: String,
    pub fatal: bool,
}

/// `disconnect` (§4.23). Sender: Device. Reply: no. Correlation: no. Sent as the last
/// application frame before a deliberate close with code `1000` (R-11-206). The
/// payload is `{}`.
#[derive(Debug, Clone, PartialEq, Eq, Default, Serialize, Deserialize)]
pub struct Disconnect {}
