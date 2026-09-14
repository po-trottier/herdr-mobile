//! The handshake-opening messages (`docs/11-relay-protocol.md` §4.1, §4.2) and the
//! `platform` value they share with the device list (§4.19).

use serde::{Deserialize, Serialize};

/// `host_info` (§4.1). Sender: Host. Reply: `device_info`. Correlation: no.
///
/// The Host MUST send this as the first application frame after the Noise transport
/// reaches transport mode (R-11-130).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct HostInfo {
    /// Relay protocol version. `1`.
    pub protocol: u32,
    /// UUIDv4, stable for the life of the Host install.
    pub host_id: String,
    /// Host machine name for display. At most 64 UTF-8 bytes.
    pub host_name: String,
    /// Herdr server version from `ping`.
    pub herdr_version: String,
    /// Herdr socket protocol integer from `ping`. MUST be `21` (R-10-012).
    pub herdr_protocol: u32,
    /// `true` when this Device static key was already paired before this session.
    pub paired: bool,
    /// The current Herdr palette, if the Host can resolve it.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub theme: Option<ThemePalette>,
}
/// The resolved Herdr palette. Colors are strings such as `#101010` or `reset`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ThemePalette {
    pub name: String,
    pub accent: String,
    pub panel_bg: String,
    pub surface0: String,
    pub surface1: String,
    pub surface_dim: String,
    pub overlay0: String,
    pub overlay1: String,
    pub text: String,
    pub subtext0: String,
    pub mauve: String,
    pub green: String,
    pub yellow: String,
    pub red: String,
    pub blue: String,
    pub teal: String,
    pub peach: String,
}

/// A Host palette update after `host_info`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct HostTheme {
    pub theme: ThemePalette,
}

/// `device_info` (§4.2). Sender: Device. Reply: no. Correlation: no.
///
/// The Device MUST send this immediately on receiving `host_info` (R-11-131).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DeviceInfo {
    /// Relay protocol version. `1`.
    pub protocol: u32,
    /// UUIDv4 generated on first launch, stable across reconnects.
    pub device_id: String,
    /// Human-readable name. MUST NOT exceed 32 UTF-8 bytes (R-11-226).
    pub device_name: String,
    /// `ios` or `android`.
    pub platform: Platform,
    /// Operating-system version string.
    pub os_version: String,
    /// Semantic version of the app build.
    pub app_version: String,
}

/// A Device operating-system platform (§4.2, §4.19).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Platform {
    Ios,
    Android,
}
