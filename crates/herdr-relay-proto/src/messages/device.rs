//! The paired-device-management messages (`docs/11-relay-protocol.md` §4.18 through
//! §4.21): the device list and revocation.

use serde::{Deserialize, Serialize};

use super::session::Platform;

/// `device_list_request` (§4.18). Sender: Device. Reply: `device_list`. Correlation:
/// yes. The payload is `{}`.
#[derive(Debug, Clone, PartialEq, Eq, Default, Serialize, Deserialize)]
pub struct DeviceListRequest {}

/// `device_list` (§4.19). Sender: Host. Reply: no (reply to `device_list_request`).
/// Correlation: yes.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DeviceList {
    pub devices: Vec<DeviceListEntry>,
}

/// One paired-device entry. `fingerprint` is computed from the stored
/// `static_public_key`; the raw key MUST NOT appear in any message (R-11-062).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DeviceListEntry {
    pub id: String,
    pub name: String,
    pub paired_at: String,
    pub last_seen: String,
    pub connected: bool,
    pub platform: Platform,
    pub fingerprint: String,
}

/// `revoke_device` (§4.20). Sender: Device. Reply: `revoke_result`. Correlation: yes.
/// Exactly one of `device_id` or `all` MUST be present (R-11-063).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RevokeDevice {
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub device_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub all: Option<bool>,
}

/// `revoke_result` (§4.21). Sender: Host. Reply: no (reply to `revoke_device`).
/// Correlation: yes. When `all` is `true`, the Host also generates a new Host static
/// keypair (R-11-064).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RevokeResult {
    pub revoked: Vec<String>,
    pub all: bool,
}
