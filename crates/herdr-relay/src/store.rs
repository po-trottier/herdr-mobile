//! The paired-device list (`docs/13-security-pairing.md` R-13-049), persisted
//! as `paired-devices.json` (R-13-060) under the Host's config directory.
//!
//! This module owns the record shape and its on-disk persistence only. It does
//! not destroy a routing handle or close a relay WebSocket session: those are
//! `INT-6-bridge`/`WP-6` concerns that consume the entry [`DeviceStore::revoke`]
//! and [`DeviceStore::clear_all`] return, once `watch.rs` exists.

use std::path::PathBuf;

use herdr_relay_proto::messages::Platform;
use serde::{Deserialize, Serialize};
use thiserror::Error;
use time::OffsetDateTime;
use time::format_description::well_known::Rfc3339;

use crate::config::{self, ConfigError, ConfigPaths};

/// One paired-device entry. Every field from R-13-049's table; no
/// `reconnect_token` field exists (R-13-050).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PairedDevice {
    /// Host pairing identifier from `host_info` (R-13-049).
    pub host_id: String,
    /// The routing handle of this pairing: 22 unpadded base64url characters
    /// (R-11-112). The Host registers on `/host/<handle>` for `Noise_KK`
    /// reconnect (R-13-037) and destroys the handle on revocation (R-13-053).
    /// `#[serde(default)]` keeps a pre-Phase-25 file loadable; an entry with
    /// an empty handle is unservable and the bridge skips it.
    #[serde(default)]
    pub handle: String,
    /// Device pairing identifier from `device_info` (R-13-049).
    pub device_id: String,
    /// Human-readable device name, at most 32 bytes (R-11-226).
    pub device_name: String,
    /// `ios` or `android`, from `device_info` (R-11-131).
    pub platform: Platform,
    /// Device operating-system version, read live from `device_info` at
    /// enrolment and stored, never re-read (R-13-049).
    pub os_version: String,
    /// Device Curve25519 static public key. The fingerprint shown to the user
    /// (R-13-041) is computed from this; the raw key itself never crosses the
    /// wire again (R-13-070).
    #[serde(with = "public_key_base64")]
    pub static_public_key: [u8; 32],
    /// RFC 3339 UTC timestamp of first pairing.
    pub paired_at: String,
    /// RFC 3339 UTC timestamp of the last successful Noise handshake or
    /// transport message.
    pub last_seen: String,
}

impl PairedDevice {
    /// The display fingerprint shown to the user (R-13-040): BLAKE2s-256 of
    /// the static public key, first 8 bytes, lowercase hex in four
    /// hyphen-separated groups of four. Reuses [`crate::keys::fingerprint_of`].
    pub fn fingerprint(&self) -> String {
        crate::keys::fingerprint_of(&self.static_public_key)
    }
}

mod public_key_base64 {
    use base64::Engine as _;
    use base64::engine::general_purpose::STANDARD as BASE64;
    use serde::{Deserialize, Deserializer, Serializer};

    pub fn serialize<S: Serializer>(key: &[u8; 32], serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(&BASE64.encode(key))
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(deserializer: D) -> Result<[u8; 32], D::Error> {
        let text = String::deserialize(deserializer)?;
        let bytes = BASE64.decode(text).map_err(serde::de::Error::custom)?;
        bytes
            .try_into()
            .map_err(|_| serde::de::Error::custom("static_public_key must be 32 bytes"))
    }
}

#[derive(Debug, Error)]
pub enum StoreError {
    #[error("read the paired-device list at {path} failed: {source}")]
    Read {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("parse the paired-device list at {path} failed: {source}")]
    Parse {
        path: PathBuf,
        #[source]
        source: serde_json::Error,
    },
    #[error("serialise the paired-device list failed: {0}")]
    Serialize(#[source] serde_json::Error),
    #[error("write the paired-device list failed: {0}")]
    Write(#[source] ConfigError),
}

/// The current UTC time as RFC 3339, matching the timestamp convention every
/// other wire timestamp in `herdr-relay-proto` already uses (`AgentStatus::at`,
/// `DeviceListEntry::paired_at`/`last_seen`).
fn now_iso8601() -> String {
    OffsetDateTime::now_utc()
        .format(&Rfc3339)
        .expect("Rfc3339 formatting of the current time never fails")
}

/// The paired-device list, loaded from and persisted to `paired-devices.json`
/// (R-13-051, R-13-060).
pub struct DeviceStore {
    paths: ConfigPaths,
    devices: Vec<PairedDevice>,
}

impl DeviceStore {
    /// Loads the list from disk. A missing file is an empty list, not an error
    /// — a fresh Host install has paired no device yet.
    pub fn load(paths: ConfigPaths) -> Result<Self, StoreError> {
        let path = paths.paired_devices_file();
        let devices = match config::read_to_string_bounded(&path, config::FILE_READ_TIMEOUT) {
            Ok(text) => serde_json::from_str(&text).map_err(|source| StoreError::Parse {
                path: path.clone(),
                source,
            })?,
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => Vec::new(),
            Err(source) => return Err(StoreError::Read { path, source }),
        };
        Ok(Self { paths, devices })
    }

    fn save(&self, devices: &[&PairedDevice]) -> Result<(), StoreError> {
        let json = serde_json::to_vec_pretty(devices).map_err(StoreError::Serialize)?;
        let path = self.paths.paired_devices_file();
        let temporary = path.with_extension("json.herdr-relay-tmp");
        // R-13-060: restrict the staged file before it replaces the saved list.
        let result = config::write_restricted_file(&temporary, &json).and_then(|()| {
            std::fs::rename(&temporary, &path).map_err(|source| ConfigError::Write { path, source })
        });
        if result.is_err() {
            std::fs::remove_file(&temporary).ok();
        }
        result.map_err(StoreError::Write)
    }

    /// Every paired device, in enrolment order.
    pub fn devices(&self) -> &[PairedDevice] {
        &self.devices
    }

    /// Looks up one paired device by its `device_id`.
    pub fn find(&self, device_id: &str) -> Option<&PairedDevice> {
        self.devices
            .iter()
            .find(|device| device.device_id == device_id)
    }

    /// Enrols a device (R-13-048). `handle` is the routing handle of this
    /// pairing (R-13-049). `paired_at` and `last_seen` are stamped
    /// with the current time. Re-enrolling an already-known `device_id`
    /// replaces its entry rather than appending a duplicate row.
    // The parameter list is the R-13-049 enrolment record; the control-plane
    // contract fixes this shape.
    #[allow(clippy::too_many_arguments)]
    pub fn add(
        &mut self,
        host_id: String,
        handle: String,
        device_id: String,
        device_name: String,
        platform: Platform,
        os_version: String,
        static_public_key: [u8; 32],
    ) -> Result<(), StoreError> {
        let now = now_iso8601();
        let entry = PairedDevice {
            host_id,
            handle,
            device_id: device_id.clone(),
            device_name,
            platform,
            os_version,
            static_public_key,
            paired_at: now.clone(),
            last_seen: now,
        };
        let mut devices: Vec<_> = self
            .devices
            .iter()
            .filter(|device| device.device_id != device_id)
            .collect();
        devices.push(&entry);
        // R-13-049: commit the enrolment record only after the save succeeds.
        self.save(&devices)?;
        self.devices.retain(|device| device.device_id != device_id);
        self.devices.push(entry);
        Ok(())
    }

    /// Revokes one Device (R-13-053 step 1): removes its entry and persists
    /// the list. Returns the removed entry so the caller can destroy its
    /// routing handle and close its relay session (R-13-053 steps 2–3), which
    /// this module does not own.
    pub fn revoke(&mut self, device_id: &str) -> Result<Option<PairedDevice>, StoreError> {
        let Some(index) = self
            .devices
            .iter()
            .position(|device| device.device_id == device_id)
        else {
            return Ok(None);
        };
        let devices: Vec<_> = self
            .devices
            .iter()
            .enumerate()
            .filter_map(|(i, device)| (i != index).then_some(device))
            .collect();
        // R-13-053: retain the entry on failure so the caller can retry revocation.
        self.save(&devices)?;
        Ok(Some(self.devices.remove(index)))
    }

    /// "Refresh" (R-13-056 step 1): clears every paired device and persists
    /// the empty list. Returns the cleared entries so the caller can destroy
    /// every routing handle and close every session (R-13-056 steps 2–3).
    pub fn clear_all(&mut self) -> Result<Vec<PairedDevice>, StoreError> {
        self.save(&[])?;
        Ok(std::mem::take(&mut self.devices))
    }

    /// Updates `last_seen` to the current time for one device, on every
    /// successful Noise handshake or transport message. Returns `false` when
    /// no entry matches `device_id` — a stale handle from a session that
    /// outlived its revocation, not an error.
    pub fn touch_last_seen(&mut self, device_id: &str) -> Result<bool, StoreError> {
        let Some(index) = self
            .devices
            .iter()
            .position(|device| device.device_id == device_id)
        else {
            return Ok(false);
        };
        let mut updated = self.devices[index].clone();
        updated.last_seen = now_iso8601();
        let mut devices: Vec<_> = self.devices.iter().collect();
        devices[index] = &updated;
        self.save(&devices)?;
        self.devices[index].last_seen = updated.last_seen;
        Ok(true)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_paths(label: &str) -> ConfigPaths {
        let dir = std::env::temp_dir().join(format!(
            "herdr-relay-store-test-{label}-{}",
            std::process::id()
        ));
        std::fs::remove_dir_all(&dir).ok();
        ConfigPaths::new(dir)
    }

    /// A fake 22-character routing handle (R-11-112 shape) for tests.
    const TEST_HANDLE: &str = "AAAAAAAAAAAAAAAAAAAAAA";

    fn add_sample(store: &mut DeviceStore, device_id: &str, name: &str) {
        let mut key = [0u8; 32];
        key[0] = device_id.len() as u8;
        store
            .add(
                "host-1".to_string(),
                TEST_HANDLE.to_string(),
                device_id.to_string(),
                name.to_string(),
                Platform::Android,
                "15".to_string(),
                key,
            )
            .expect("add a paired device");
    }

    fn assert_failed_save_preserves_devices(
        label: &str,
        update: impl FnOnce(&mut DeviceStore) -> Result<(), StoreError>,
    ) {
        let paths = temp_paths(label);
        let mut store = DeviceStore::load(paths.clone()).expect("load empty store");
        add_sample(&mut store, "device-1", "Pixel 9 Pro");
        add_sample(&mut store, "device-2", "iPhone SE");
        store.devices[0].last_seen = "2000-01-01T00:00:00Z".to_string();
        let original = store.devices().to_vec();
        let original_json =
            serde_json::to_vec_pretty(&original).expect("serialize original devices");
        let path = paths.paired_devices_file();
        std::fs::write(&path, &original_json).expect("persist original devices");
        // R-13-049, R-13-053, R-13-060: a failed save must preserve both copies.
        let blocked_path = path.with_extension("json.herdr-relay-tmp");
        std::fs::create_dir(&blocked_path).expect("block the staged file");

        assert!(matches!(update(&mut store), Err(StoreError::Write(_))));
        assert_eq!(store.devices(), original);
        assert_eq!(
            std::fs::read(&path).expect("read original file"),
            original_json
        );
        assert_eq!(
            DeviceStore::load(paths.clone())
                .expect("reload original devices")
                .devices(),
            original
        );

        std::fs::remove_dir(&blocked_path).expect("unblock the staged file");
        assert_eq!(
            store.revoke("device-1").expect("retry revocation"),
            Some(original[0].clone())
        );
        assert_eq!(
            DeviceStore::load(paths.clone())
                .expect("reload revoked devices")
                .devices(),
            &original[1..]
        );
        std::fs::remove_dir_all(paths.dir()).expect("remove isolated store");
    }

    #[test]
    fn add_save_failure_preserves_memory_and_disk() {
        assert_failed_save_preserves_devices("add-save-failure", |store| {
            store.add(
                "host-1".to_string(),
                TEST_HANDLE.to_string(),
                "device-3".to_string(),
                "New device".to_string(),
                Platform::Android,
                "15".to_string(),
                [3; 32],
            )
        });
    }

    #[test]
    fn replace_save_failure_preserves_memory_and_disk() {
        assert_failed_save_preserves_devices("replace-save-failure", |store| {
            store.add(
                "host-1".to_string(),
                TEST_HANDLE.to_string(),
                "device-1".to_string(),
                "Replacement device".to_string(),
                Platform::Android,
                "15".to_string(),
                [3; 32],
            )
        });
    }

    #[test]
    fn revoke_save_failure_preserves_memory_and_disk() {
        assert_failed_save_preserves_devices("revoke-save-failure", |store| {
            store.revoke("device-1").map(|_| ())
        });
    }

    #[test]
    fn clear_all_save_failure_preserves_memory_and_disk() {
        assert_failed_save_preserves_devices("clear-all-save-failure", |store| {
            store.clear_all().map(|_| ())
        });
    }

    #[test]
    fn touch_last_seen_save_failure_preserves_memory_and_disk() {
        assert_failed_save_preserves_devices("touch-save-failure", |store| {
            store.touch_last_seen("device-1").map(|_| ())
        });
    }

    #[test]
    fn add_then_list_returns_the_device() {
        let paths = temp_paths("add-list");
        let mut store = DeviceStore::load(paths.clone()).expect("load an empty store");
        add_sample(&mut store, "device-1", "Pixel 9 Pro");
        assert_eq!(store.devices().len(), 1);
        assert_eq!(store.devices()[0].device_id, "device-1");
        std::fs::remove_dir_all(paths.dir()).ok();
    }

    /// The device list persists as `paired-devices.json` on disk and survives
    /// a restart: a fresh `DeviceStore` loaded from the same path still sees
    /// the device (R-13-051).
    #[test]
    fn reload_from_disk_survives_a_restart() {
        let paths = temp_paths("reload");
        let mut store = DeviceStore::load(paths.clone()).expect("load an empty store");
        add_sample(&mut store, "device-1", "Pixel 9 Pro");
        drop(store);
        let reloaded = DeviceStore::load(paths.clone()).expect("reload the persisted store");
        assert_eq!(reloaded.devices().len(), 1);
        assert_eq!(reloaded.devices()[0].device_id, "device-1");
        std::fs::remove_dir_all(paths.dir()).ok();
    }

    #[test]
    fn revoke_removes_only_the_named_device() {
        let paths = temp_paths("revoke");
        let mut store = DeviceStore::load(paths.clone()).expect("load an empty store");
        add_sample(&mut store, "device-1", "Pixel 9 Pro");
        add_sample(&mut store, "device-2", "iPhone SE");
        let removed = store
            .revoke("device-1")
            .expect("revoke device-1")
            .expect("device-1 existed");
        assert_eq!(removed.device_id, "device-1");
        assert_eq!(store.devices().len(), 1);
        assert_eq!(store.devices()[0].device_id, "device-2");
        std::fs::remove_dir_all(paths.dir()).ok();
    }

    #[test]
    fn revoke_unknown_device_returns_none() {
        let paths = temp_paths("revoke-unknown");
        let mut store = DeviceStore::load(paths.clone()).expect("load an empty store");
        add_sample(&mut store, "device-1", "Pixel 9 Pro");
        let removed = store
            .revoke("device-9")
            .expect("revoke does not fail on an unknown id");
        assert!(removed.is_none());
        assert_eq!(store.devices().len(), 1);
        std::fs::remove_dir_all(paths.dir()).ok();
    }

    #[test]
    fn clear_all_empties_the_list_and_persists() {
        let paths = temp_paths("clear-all");
        let mut store = DeviceStore::load(paths.clone()).expect("load an empty store");
        add_sample(&mut store, "device-1", "Pixel 9 Pro");
        add_sample(&mut store, "device-2", "iPhone SE");
        let cleared = store.clear_all().expect("clear the list");
        assert_eq!(cleared.len(), 2);
        assert!(store.devices().is_empty());
        let reloaded = DeviceStore::load(paths.clone()).expect("reload after clear_all");
        assert!(reloaded.devices().is_empty());
        std::fs::remove_dir_all(paths.dir()).ok();
    }

    #[test]
    fn touch_last_seen_updates_only_the_named_device() {
        let paths = temp_paths("touch");
        let mut store = DeviceStore::load(paths.clone()).expect("load an empty store");
        add_sample(&mut store, "device-1", "Pixel 9 Pro");
        let before = store.devices()[0].last_seen.clone();
        std::thread::sleep(std::time::Duration::from_millis(10));
        let found = store.touch_last_seen("device-1").expect("touch device-1");
        assert!(found);
        assert_ne!(store.devices()[0].last_seen, before);
        std::fs::remove_dir_all(paths.dir()).ok();
    }

    #[test]
    fn touch_last_seen_unknown_device_returns_false() {
        let paths = temp_paths("touch-unknown");
        let mut store = DeviceStore::load(paths.clone()).expect("load an empty store");
        let found = store
            .touch_last_seen("device-9")
            .expect("touch does not fail on unknown id");
        assert!(!found);
        std::fs::remove_dir_all(paths.dir()).ok();
    }

    /// The `handle` field serialises into `paired-devices.json` and survives a
    /// reload (R-13-049).
    #[test]
    fn handle_round_trips_through_the_json_file() {
        let paths = temp_paths("handle-round-trip");
        let mut store = DeviceStore::load(paths.clone()).expect("load an empty store");
        add_sample(&mut store, "device-1", "Pixel 9 Pro");
        let raw = std::fs::read_to_string(paths.paired_devices_file()).expect("read the list file");
        assert!(raw.contains(TEST_HANDLE));
        let reloaded = DeviceStore::load(paths.clone()).expect("reload the persisted store");
        assert_eq!(reloaded.devices()[0].handle, TEST_HANDLE);
        std::fs::remove_dir_all(paths.dir()).ok();
    }

    /// A list written before Phase 25 has no `handle` field. It loads with an
    /// empty handle; the bridge treats such an entry as unservable.
    #[test]
    fn a_file_without_handle_loads_with_an_empty_handle() {
        let paths = temp_paths("no-handle");
        std::fs::create_dir_all(paths.dir()).expect("create the config dir");
        let json = r#"[
            {
                "host_id": "host-1",
                "device_id": "device-1",
                "device_name": "Pixel 9 Pro",
                "platform": "android",
                "os_version": "15",
                "static_public_key": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
                "paired_at": "2026-01-01T00:00:00Z",
                "last_seen": "2026-01-01T00:00:00Z"
            }
        ]"#;
        std::fs::write(paths.paired_devices_file(), json).expect("write a pre-Phase-25 list");
        let store = DeviceStore::load(paths.clone()).expect("load the pre-Phase-25 store");
        assert_eq!(store.devices().len(), 1);
        assert!(store.devices()[0].handle.is_empty());
        std::fs::remove_dir_all(paths.dir()).ok();
    }

    #[test]
    fn find_hits_and_misses() {
        let paths = temp_paths("find");
        let mut store = DeviceStore::load(paths.clone()).expect("load an empty store");
        add_sample(&mut store, "device-1", "Pixel 9 Pro");
        let found = store.find("device-1").expect("device-1 is paired");
        assert_eq!(found.device_name, "Pixel 9 Pro");
        assert_eq!(found.handle, TEST_HANDLE);
        assert!(store.find("device-9").is_none());
        std::fs::remove_dir_all(paths.dir()).ok();
    }

    /// R-13-040: `^[0-9a-f]{4}(-[0-9a-f]{4}){3}$`, and stable for a fixed key.
    #[test]
    fn fingerprint_matches_the_r_13_040_shape_and_is_stable() {
        let paths = temp_paths("fingerprint");
        let mut store = DeviceStore::load(paths.clone()).expect("load an empty store");
        add_sample(&mut store, "device-1", "Pixel 9 Pro");
        let device = &store.devices()[0];
        let fingerprint = device.fingerprint();
        let groups: Vec<&str> = fingerprint.split('-').collect();
        assert_eq!(groups.len(), 4);
        for group in groups {
            assert_eq!(group.len(), 4);
            assert!(
                group
                    .chars()
                    .all(|c| c.is_ascii_digit() || ('a'..='f').contains(&c))
            );
        }
        assert_eq!(device.fingerprint(), fingerprint, "stable for a fixed key");
        std::fs::remove_dir_all(paths.dir()).ok();
    }
}
