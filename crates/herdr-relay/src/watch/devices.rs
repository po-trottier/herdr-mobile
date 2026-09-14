//! The four paired-device-management wire messages
//! (`docs/11-relay-protocol.md` §4.18 through §4.21): `device_list_request` ->
//! `device_list`, and `revoke_device` -> `revoke_result`. Two request/reply
//! pairs, so two methods, matching the one-request-in/one-reply-out shape
//! `watch/requests.rs` already uses for `tree_request`/`scroll_request`.
//!
//! Neither handler calls Herdr: both read and write `crate::store`'s
//! `DeviceStore` (`WP-10-a`'s R-13-049 record) and, for a full revoke,
//! `crate::keys`' Host keypair (`WP-10-a`'s R-13-058 identity). Both are
//! associated functions on `Bridge<H>` rather than `&self` methods, matching
//! `requests.rs`'s `subscription_entries` precedent: nothing here reads
//! `Bridge`'s own state, so there is nothing for `&self` to borrow.

use herdr_relay_proto::messages::{DeviceList, DeviceListEntry, RevokeDevice, RevokeResult};

use crate::config::ConfigPaths;
use crate::keys::{self, KeysError};
use crate::store::{DeviceStore, StoreError};

use super::bridge::Bridge;
use super::herdr_calls::HerdrCalls;

/// An error from a device-management handler. Distinct from `WatchError`
/// (`bridge.rs`) because these handlers never call Herdr — every failure here
/// is local store or key-storage I/O, or a malformed `revoke_device` (R-41-125:
/// an error crossing a module boundary is `thiserror`-derived).
#[derive(Debug, thiserror::Error)]
pub enum DeviceError {
    #[error("revoke_device must carry exactly one of device_id or all: true (R-11-063)")]
    InvalidRevokeRequest,
    #[error("update the paired-device list failed: {0}")]
    Store(#[from] StoreError),
    #[error("rotate the Host keypair failed: {0}")]
    Keys(#[from] KeysError),
}

impl<H: HerdrCalls> Bridge<H> {
    /// `device_list_request` -> `device_list` (R-11-062). Sends the
    /// fingerprint `keys::fingerprint_of` computes from each stored
    /// `static_public_key`, never the raw key itself (R-13-070) — the wire
    /// type `DeviceListEntry` has no field for it, so this is a compile-time
    /// guarantee, not just a convention followed by hand.
    ///
    /// `connected_device_id` names the Device holding this bridge's own live
    /// session, if any. It is the only entry that can ever read
    /// `connected: true`: one active Device is a relay-enforced connection
    /// limit, not an enrolment limit (R-13-052), and `Bridge` itself is
    /// already scoped to one Device's session (R-11-224), so no other
    /// connection is visible from here to report as connected.
    pub fn device_list(store: &DeviceStore, connected_device_id: Option<&str>) -> DeviceList {
        let devices = store
            .devices()
            .iter()
            .map(|device| DeviceListEntry {
                id: device.device_id.clone(),
                name: device.device_name.clone(),
                paired_at: device.paired_at.clone(),
                last_seen: device.last_seen.clone(),
                connected: connected_device_id == Some(device.device_id.as_str()),
                platform: device.platform,
                fingerprint: keys::fingerprint_of(&device.static_public_key),
            })
            .collect();
        DeviceList { devices }
    }

    /// `revoke_device` -> `revoke_result` (R-11-063, R-11-064, R-13-053,
    /// R-13-056). Exactly one of `request.device_id` or `request.all: true`
    /// MUST be present (R-11-063); any other combination is rejected, not
    /// repaired (R-41-037).
    ///
    /// `all: true` clears every paired device and rotates the Host's own
    /// static keypair (R-11-064, R-13-056 step 4): the new key alone
    /// invalidates every existing pairing, independent of whatever the
    /// relay/session layer later does with the now-orphaned handles and live
    /// connections (R-13-053 steps 2-3, R-13-056 steps 2-3), which this
    /// module does not own — it returns the revoked id(s) so that layer
    /// (`crate::bridge`'s `finish_wire_revoke` and `SessionRegistry`) can
    /// finish the job.
    pub fn revoke_device(
        store: &mut DeviceStore,
        key_paths: &ConfigPaths,
        request: RevokeDevice,
    ) -> Result<RevokeResult, DeviceError> {
        match (request.device_id, request.all == Some(true)) {
            (None, true) => {
                let cleared = store.clear_all()?;
                keys::rotate(key_paths)?;
                Ok(RevokeResult {
                    revoked: cleared.into_iter().map(|device| device.device_id).collect(),
                    all: true,
                })
            }
            (Some(device_id), false) => {
                let revoked = store
                    .revoke(&device_id)?
                    .into_iter()
                    .map(|device| device.device_id)
                    .collect();
                Ok(RevokeResult {
                    revoked,
                    all: false,
                })
            }
            _ => Err(DeviceError::InvalidRevokeRequest),
        }
    }
}

#[cfg(test)]
mod tests {
    use herdr_relay_proto::messages::Platform;

    use super::*;
    use crate::ipc::HerdrClient;

    fn temp_paths(label: &str) -> ConfigPaths {
        let dir = std::env::temp_dir().join(format!(
            "herdr-relay-devices-test-{label}-{}",
            std::process::id()
        ));
        std::fs::remove_dir_all(&dir).ok();
        ConfigPaths::new(dir)
    }

    fn add_sample(store: &mut DeviceStore, device_id: &str, name: &str) {
        let mut key = [0u8; 32];
        key[0] = device_id.len() as u8;
        store
            .add(
                "host-1".to_string(),
                "AAAAAAAAAAAAAAAAAAAAAA".to_string(),
                device_id.to_string(),
                name.to_string(),
                Platform::Android,
                "15".to_string(),
                key,
            )
            .expect("add a paired device");
    }

    #[test]
    fn device_list_marks_only_the_connected_device() {
        let paths = temp_paths("device-list");
        let mut store = DeviceStore::load(paths.clone()).expect("load an empty store");
        add_sample(&mut store, "device-a", "Pixel 9 Pro");
        add_sample(&mut store, "device-b", "iPhone SE");

        let list = Bridge::<HerdrClient>::device_list(&store, Some("device-a"));

        assert_eq!(list.devices.len(), 2);
        let a = list
            .devices
            .iter()
            .find(|d| d.id == "device-a")
            .expect("device-a listed");
        let b = list
            .devices
            .iter()
            .find(|d| d.id == "device-b")
            .expect("device-b listed");
        assert!(a.connected, "the session's own device is connected");
        assert!(
            !b.connected,
            "no other paired device can be connected (R-13-052)"
        );
        assert_eq!(a.platform, Platform::Android);
        assert!(!a.fingerprint.is_empty());
        assert_eq!(
            a.fingerprint.split('-').count(),
            4,
            "R-13-040 fingerprint shape"
        );

        std::fs::remove_dir_all(paths.dir()).ok();
    }

    #[test]
    fn device_list_with_no_live_session_marks_nothing_connected() {
        let paths = temp_paths("device-list-none");
        let mut store = DeviceStore::load(paths.clone()).expect("load an empty store");
        add_sample(&mut store, "device-a", "Pixel 9 Pro");

        let list = Bridge::<HerdrClient>::device_list(&store, None);

        assert!(!list.devices[0].connected);
        std::fs::remove_dir_all(paths.dir()).ok();
    }

    #[test]
    fn revoke_device_single_removes_only_the_named_device() {
        let paths = temp_paths("revoke-single");
        let mut store = DeviceStore::load(paths.clone()).expect("load an empty store");
        add_sample(&mut store, "device-a", "Pixel 9 Pro");
        add_sample(&mut store, "device-b", "iPhone SE");

        let request = RevokeDevice {
            device_id: Some("device-a".to_string()),
            all: None,
        };
        let result = Bridge::<HerdrClient>::revoke_device(&mut store, &paths, request)
            .expect("revoke a known device");

        assert_eq!(result.revoked, vec!["device-a".to_string()]);
        assert!(!result.all);
        assert_eq!(store.devices().len(), 1);
        assert_eq!(store.devices()[0].device_id, "device-b");
        std::fs::remove_dir_all(paths.dir()).ok();
    }

    #[test]
    fn revoke_device_unknown_id_reports_nothing_revoked() {
        let paths = temp_paths("revoke-unknown");
        let mut store = DeviceStore::load(paths.clone()).expect("load an empty store");
        add_sample(&mut store, "device-a", "Pixel 9 Pro");

        let request = RevokeDevice {
            device_id: Some("device-9".to_string()),
            all: None,
        };
        let result = Bridge::<HerdrClient>::revoke_device(&mut store, &paths, request)
            .expect("revoke does not fail on an unknown id");

        assert!(result.revoked.is_empty());
        assert_eq!(store.devices().len(), 1);
        std::fs::remove_dir_all(paths.dir()).ok();
    }

    #[test]
    fn revoke_device_all_clears_the_list_and_rotates_the_host_keypair() {
        let paths = temp_paths("revoke-all");
        let mut store = DeviceStore::load(paths.clone()).expect("load an empty store");
        add_sample(&mut store, "device-a", "Pixel 9 Pro");
        add_sample(&mut store, "device-b", "iPhone SE");
        let keypair_before = keys::load_or_generate(&paths).expect("generate the initial keypair");

        let request = RevokeDevice {
            device_id: None,
            all: Some(true),
        };
        let result = Bridge::<HerdrClient>::revoke_device(&mut store, &paths, request)
            .expect("revoke all devices");

        assert!(result.all);
        let mut revoked = result.revoked;
        revoked.sort();
        assert_eq!(
            revoked,
            vec!["device-a".to_string(), "device-b".to_string()]
        );
        assert!(store.devices().is_empty());

        let keypair_after =
            keys::load_or_generate(&paths).expect("load the rotated keypair back from storage");
        assert_ne!(
            keypair_before.public, keypair_after.public,
            "R-11-064: all: true rotates the Host's own keypair"
        );
        std::fs::remove_dir_all(paths.dir()).ok();
    }

    #[test]
    fn revoke_device_rejects_neither_field_present() {
        let paths = temp_paths("revoke-neither");
        let mut store = DeviceStore::load(paths.clone()).expect("load an empty store");
        let request = RevokeDevice {
            device_id: None,
            all: None,
        };
        let error = Bridge::<HerdrClient>::revoke_device(&mut store, &paths, request)
            .expect_err("neither device_id nor all is a malformed request (R-11-063)");
        assert!(
            matches!(error, DeviceError::InvalidRevokeRequest),
            "a malformed revoke_device request produces a typed DeviceError, not a bare string (R-41-125)"
        );
        std::fs::remove_dir_all(paths.dir()).ok();
    }

    #[test]
    fn revoke_device_rejects_both_fields_present() {
        let paths = temp_paths("revoke-both");
        let mut store = DeviceStore::load(paths.clone()).expect("load an empty store");
        let request = RevokeDevice {
            device_id: Some("device-a".to_string()),
            all: Some(true),
        };
        let error = Bridge::<HerdrClient>::revoke_device(&mut store, &paths, request)
            .expect_err("both device_id and all is ambiguous, not a union (R-11-063)");
        assert!(
            matches!(error, DeviceError::InvalidRevokeRequest),
            "a malformed revoke_device request produces a typed DeviceError, not a bare string (R-41-125)"
        );
        std::fs::remove_dir_all(paths.dir()).ok();
    }
}
