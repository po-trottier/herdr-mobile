//! `WP-20-b`: proves the "Refresh" mechanism end to end at the level it
//! actually exists in this codebase (R-13-056 steps 1, 2, 3 and 4 —
//! `docs/13-security-pairing.md`): clearing the paired-device list, closing
//! every live session, destroying every routing handle and rotating the
//! Host's own keypair. `tests/revoke.rs` (`WP-10-a`) already covers step 1
//! alone, at the `DeviceStore` level only; this file additionally composes
//! `relay::SessionRegistry` (`WP-14`'s `close_for_revocation`, R-13-053 steps
//! 2-3 / R-13-056 steps 2-3) and `keys::rotate` (R-13-056 step 4) around the
//! same `Bridge::revoke_device` wire-shaped call `watch/devices.rs` exposes.
//!
//! The production call sites now exist: `crates/herdr-relay/src/bridge.rs`
//! answers the control commands `revoke`/`revoke_all` (`revoke_one`,
//! `revoke_all`) and dispatches the Device-sent `revoke_device` and
//! `device_list_request` frames (`dispatch_incoming` ->
//! `BridgeRequest::RevokeDevice`/`DeviceListRequest`, answered in
//! `bridge_thread` against `HostState`'s store and `SessionRegistry`, with
//! `finish_wire_revoke` for the parked registrations and the keypair). The
//! popup's `RemoveAll` arm sends `Command::RevokeAll` to that bridge.
//! `tests/host_pairing.rs` proves the wire dispatch end to end over a fake
//! relay (`revoke_result` first, then the fatal `revoked` error and the 4004
//! close). This file keeps proving the pieces compose correctly at the
//! store/registry/keys level, which is exactly what "Refresh clears the
//! list, closes every session, destroys every handle and rotates the Host
//! keypair" (this file's own checklist line) asks for.
//!
//! Step 5 (show a new QR and phrase) is `popup.rs`'s own concern
//! (`r_reports_the_exact_count_and_rotates_keys_without_touching_the_real_keyring`
//! in `popup.rs` already covers it) and is out of scope here.

use herdr_relay::config::ConfigPaths;
use herdr_relay::ipc::HerdrClient;
use herdr_relay::keys;
use herdr_relay::relay::{CloseReason, SessionRegistry};
use herdr_relay::store::DeviceStore;
use herdr_relay::watch::Bridge;
use herdr_relay_proto::handle::Handle;
use herdr_relay_proto::messages::{Platform, RevokeDevice};

fn temp_paths() -> ConfigPaths {
    let dir = std::env::temp_dir().join(format!(
        "herdr-relay-revoke-all-test-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("the system clock is after the Unix epoch")
            .as_nanos()
    ));
    std::fs::remove_dir_all(&dir).ok();
    let paths = ConfigPaths::new(dir);
    // The bridge calls this before its first write (`run_inner`); a test that
    // writes the store first needs it too, or macOS reports NotFound.
    paths.ensure_dir().expect("create the temp config dir");
    paths
}

fn public_key(seed: u8) -> [u8; 32] {
    let mut key = [0u8; 32];
    key[0] = seed;
    key
}

#[test]
fn refresh_clears_the_list_closes_every_session_destroys_every_handle_and_rotates_the_keypair() {
    let paths = temp_paths();
    let mut store = DeviceStore::load(paths.clone()).expect("load a fresh device store");
    store
        .add(
            "host-1".to_string(),
            "AAAAAAAAAAAAAAAAAAAAAA".to_string(),
            "device-a".to_string(),
            "Pixel 9 Pro".to_string(),
            Platform::Android,
            "15".to_string(),
            public_key(1),
        )
        .expect("add device-a");
    store
        .add(
            "host-1".to_string(),
            "AAAAAAAAAAAAAAAAAAAAAA".to_string(),
            "device-b".to_string(),
            "iPhone SE".to_string(),
            Platform::Ios,
            "18.0".to_string(),
            public_key(2),
        )
        .expect("add device-b");
    assert_eq!(
        store.devices().len(),
        2,
        "both devices paired before Refresh"
    );

    let keypair_before = keys::load_or_generate(&paths).expect("generate the initial keypair");

    // Two live sessions, one per paired device, mirroring what
    // `relay::session::run_host_session` would have registered for each
    // Device's own connection (R-13-052 governs at most one being
    // simultaneously *connected* in real operation; this registry-level test
    // exercises "every session" independent of that runtime invariant, the
    // same way `relay/registry.rs`'s own
    // `close_for_revocation_all_closes_every_session` unit test does).
    let registry = SessionRegistry::new();
    let handle_a = Handle::generate().expect("generate handle a");
    let handle_b = Handle::generate().expect("generate handle b");
    let mut rx_a = registry.register(handle_a, Some("device-a".to_string()));
    let mut rx_b = registry.register(handle_b, Some("device-b".to_string()));

    // Step 1 (clear the list) and step 4 (rotate the keypair): the wire-shaped
    // `revoke_device` call `docs/11-relay-protocol.md` §4.21 names.
    let request = RevokeDevice {
        device_id: None,
        all: Some(true),
    };
    let result = Bridge::<HerdrClient>::revoke_device(&mut store, &paths, request)
        .expect("revoke every device");
    assert!(result.all, "R-11-064: the reply carries all: true");
    let mut revoked = result.revoked.clone();
    revoked.sort();
    assert_eq!(
        revoked,
        vec!["device-a".to_string(), "device-b".to_string()],
        "R-13-056 step 1: every paired device is named as revoked"
    );
    assert!(
        store.devices().is_empty(),
        "R-13-056 step 1: the paired-device list is cleared"
    );
    let reloaded = DeviceStore::load(paths.clone()).expect("reload the persisted store");
    assert!(
        reloaded.devices().is_empty(),
        "R-13-056 step 1 persists: a reload from disk also sees an empty list"
    );

    let keypair_after =
        keys::load_or_generate(&paths).expect("load the rotated keypair back from storage");
    assert_ne!(
        keypair_before.public, keypair_after.public,
        "R-13-056 step 4: Refresh rotates the Host's own keypair"
    );

    // Steps 2-3 (close every live session, destroy every handle): the
    // `RevokeResult` this call produced is exactly what
    // `SessionRegistry::close_for_revocation` consumes.
    let closed = registry.close_for_revocation(&result);
    assert_eq!(
        closed, 2,
        "R-13-056 step 2: every live session is closed, not just one"
    );
    assert!(
        matches!(rx_a.try_recv(), Ok(CloseReason::Revoked)),
        "device-a's session received the revoked close signal"
    );
    assert!(
        matches!(rx_b.try_recv(), Ok(CloseReason::Revoked)),
        "device-b's session received the revoked close signal"
    );

    // R-13-056 step 3 (destroy every handle): a second close for the same
    // result finds nothing left to close, proving the registry entries were
    // actually removed and not merely signalled.
    assert_eq!(
        registry.close_for_revocation(&result),
        0,
        "R-13-056 step 3: every handle was destroyed, none survives a second Refresh"
    );

    std::fs::remove_dir_all(paths.dir()).ok();
}

#[test]
fn refresh_with_no_live_session_still_clears_the_list_and_rotates_the_keypair() {
    // R-13-053's own "If the Device has an active Noise session" condition,
    // applied to "every Device" for Refresh: a paired-but-not-connected
    // Device has nothing live to close, and that MUST NOT stop the list
    // clear or the keypair rotation.
    let paths = temp_paths();
    let mut store = DeviceStore::load(paths.clone()).expect("load a fresh device store");
    store
        .add(
            "host-1".to_string(),
            "AAAAAAAAAAAAAAAAAAAAAA".to_string(),
            "device-a".to_string(),
            "Pixel 9 Pro".to_string(),
            Platform::Android,
            "15".to_string(),
            public_key(1),
        )
        .expect("add device-a");
    let keypair_before = keys::load_or_generate(&paths).expect("generate the initial keypair");

    let registry = SessionRegistry::new();
    let request = RevokeDevice {
        device_id: None,
        all: Some(true),
    };
    let result = Bridge::<HerdrClient>::revoke_device(&mut store, &paths, request)
        .expect("revoke every device");

    assert_eq!(
        registry.close_for_revocation(&result),
        0,
        "no live session existed to close"
    );
    assert!(store.devices().is_empty());
    let keypair_after =
        keys::load_or_generate(&paths).expect("load the rotated keypair back from storage");
    assert_ne!(keypair_before.public, keypair_after.public);

    std::fs::remove_dir_all(paths.dir()).ok();
}
