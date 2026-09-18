//! Handling one direct Device request: `tree_request`, `watch_pane`,
//! `unwatch_pane`, `scroll_request`, `device_list_request`, `revoke_device`.
//! Each of these calls Herdr (or, for the two device-management requests,
//! `crate::store`/`crate::keys` via `watch/devices.rs`) and builds exactly one
//! wire reply, with no dependency on the subscription connection's state
//! beyond the currently-watched pane.

use std::time::{Duration, Instant};

use serde_json::Value;

use herdr_relay_proto::messages::{
    DeviceListRequest, Message, PaneFrame, RevokeDevice, ScrollOffsets, ScrollRequest,
    ScrollResponse, TreeSnapshot, UnwatchPane, WatchAck, WatchPane,
};

use crate::config::ConfigPaths;
use crate::relay::SessionRegistry;
use crate::store::DeviceStore;

use super::bridge::{Bridge, WatchError, WatchedPane, frame_hash, lock_observed};
use super::events::UNFILTERED_TREE_EVENTS;
use super::herdr_calls::HerdrCalls;
use super::scheduler::PaneScheduler;

impl<H: HerdrCalls> Bridge<H> {
    /// `tree_request` -> `tree_snapshot` (R-11-043, R-11-044).
    pub fn tree_snapshot(&self) -> Result<TreeSnapshot, WatchError> {
        let raw = self.fetch_snapshot()?;
        Ok(self.map_snapshot(raw))
    }

    /// `watch_pane` -> `watch_ack` plus the first `pane_frame` (§5.1 steps 1-7,
    /// R-11-048, R-11-049). Replaces whatever pane was watched before (R-01-007):
    /// the old scheduler is simply dropped, and the subscription-line handler
    /// already discards events for any pane that is not `self.watched` (R-02-013,
    /// R-01-007), so the old pane naturally stops producing frames.
    pub fn watch_pane(&mut self, request: WatchPane) -> Result<(WatchAck, PaneFrame), WatchError> {
        let pane_id = request.pane_id;
        let raw = self.fetch_snapshot()?;
        let pane = raw
            .panes
            .iter()
            .find(|p| p.pane_id == pane_id)
            .cloned()
            .ok_or_else(|| WatchError::PaneNotInSnapshot(pane_id.clone()))?;

        let width = self.fetch_width(&pane_id)?;
        let text = self.fetch_visible_text(&pane_id)?;

        if self.watched.as_ref().is_some_and(|w| w.pane_id != pane_id) {
            self.cancel_pending_inputs();
        }
        self.watched = Some(WatchedPane {
            pane_id: pane_id.clone(),
            last_revision: pane.revision,
            viewport_rows: pane.scroll.viewport_rows,
            width,
            last_frame_hash: frame_hash(&text, pane.scroll.viewport_rows, width),
        });
        self.scheduler = Some(PaneScheduler::new(
            Duration::from_millis(self.config.debounce_ms),
            Duration::from_millis(self.config.poll_ms),
            self.config
                .input_read_ms
                .iter()
                .map(|ms| Duration::from_millis(*ms))
                .collect(),
            self.config.max_reads_per_second,
            Instant::now(),
        ));

        let ack = WatchAck {
            pane_id: pane_id.clone(),
            line: lock_observed(&self.input_lines)
                .get(&pane_id)
                .cloned()
                .unwrap_or_default(),
            revision: pane.revision,
            viewport_rows: pane.scroll.viewport_rows,
            width,
            scroll: ScrollOffsets {
                offset_from_bottom: pane.scroll.offset_from_bottom,
                max_offset_from_bottom: pane.scroll.max_offset_from_bottom,
            },
        };
        let frame = PaneFrame {
            pane_id,
            revision: pane.revision,
            viewport_rows: pane.scroll.viewport_rows,
            width,
            text,
        };
        Ok((ack, frame))
    }

    /// `unwatch_pane` (R-11-050): stops the filter and the frames for the named
    /// pane. A stale `unwatch_pane` for a pane that is not (or is no longer) the
    /// watched one is a no-op, matching R-11-072's "the Device does not need to
    /// send `unwatch_pane` first" — the bridge tolerates either order.
    pub fn unwatch_pane(&mut self, request: UnwatchPane) {
        if self
            .watched
            .as_ref()
            .is_some_and(|w| w.pane_id == request.pane_id)
        {
            self.cancel_pending_inputs();
            self.watched = None;
            self.scheduler = None;
        }
    }

    /// `scroll_request` -> `scroll_response` (R-11-053, R-10-019, R-10-027):
    /// `source:"recent"`, `lines` capped at `RelayConfig::max_scrollback_lines`
    /// (1000 by default).
    pub fn scroll_request(&self, request: ScrollRequest) -> Result<ScrollResponse, WatchError> {
        let lines = request.lines.min(self.config.max_scrollback_lines);
        let raw = self.herdr.pane_read_recent(&request.pane_id, lines)?;
        let text = raw
            .get("text")
            .and_then(Value::as_str)
            .ok_or(WatchError::MissingField {
                method: "pane.read",
                field: "text",
            })?
            .to_string();
        let truncated = raw
            .get("truncated")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        Ok(ScrollResponse {
            pane_id: request.pane_id,
            lines: text.lines().count() as u32,
            text,
            truncated,
        })
    }

    /// `device_list_request` -> `device_list` (R-11-062). No Herdr call
    /// (`watch/devices.rs`'s own header comment): reads `store` and this
    /// bridge's connected Device only. Associated, not `&self`, matching
    /// `Bridge::device_list`'s own shape.
    pub fn device_list_request(
        store: &DeviceStore,
        connected_device_id: Option<&str>,
        _request: DeviceListRequest,
    ) -> Message {
        Message::DeviceList(Self::device_list(store, connected_device_id))
    }

    /// `revoke_device` -> `revoke_result` (R-11-063, R-11-064, R-13-053,
    /// R-13-056). Wraps `watch/devices.rs`'s `Bridge::revoke_device` into the
    /// `Message` reply shape every other handler in this file returns, then
    /// composes `relay::SessionRegistry::close_for_revocation` on the result
    /// (R-11-064: "the current Device's session is closed"), matching the
    /// exact composition `tests/revoke_all.rs` proves correct. `registry` is
    /// `Option`, not required: no production process holds a live
    /// `SessionRegistry` yet to pass one (`main.rs`'s no-argument run path is
    /// still `WP-0-a`'s unwired stub; `popup.rs`'s own `App::session_registry`
    /// field carries the identical disclosure) — a `None` here still returns
    /// the correct wire reply, it just closes nothing, same as
    /// `popup.rs::confirm_action` when no registry is wired in. Named
    /// `revoke_device_request`, not `revoke_device`: that name is already
    /// `watch/devices.rs`'s associated function this one calls, and Rust
    /// merges every `impl<H: HerdrCalls> Bridge<H>` block into one method
    /// namespace, so the two cannot share a name.
    pub fn revoke_device_request(
        store: &mut DeviceStore,
        key_paths: &ConfigPaths,
        request: RevokeDevice,
        registry: Option<&SessionRegistry>,
    ) -> Result<Message, WatchError> {
        let result = Self::revoke_device(store, key_paths, request)?;
        if let Some(registry) = registry {
            registry.close_for_revocation(&result);
        }
        Ok(Message::RevokeResult(result))
    }

    /// The `events.subscribe` params the Host bridge opens its one long-lived
    /// subscription connection with when a Device session starts (R-10-011,
    /// R-10-055): [`Self::subscription_entries`] over every pane in a fresh
    /// snapshot, so `pane.agent_status_changed` carries its R-02-013a filter
    /// per known pane and `tree_update`/`agent_status` flow before the first
    /// `watch_pane`. A snapshot failure degrades to the unfiltered tree
    /// events alone: `tree_update` still flows, and the next `pane.created`
    /// resubscribe retries the full list.
    pub fn current_subscription_entries(&self) -> Vec<Value> {
        let pane_ids: Vec<String> = self
            .fetch_snapshot()
            .map(|raw| raw.panes.into_iter().map(|p| p.pane_id).collect())
            .unwrap_or_default();
        Self::subscription_entries(pane_ids.iter().map(String::as_str))
    }

    /// The `events.subscribe` params for this session (R-11-047): the 13
    /// unfiltered tree events, plus one `pane.agent_status_changed` entry per
    /// currently-known `pane_id` (R-02-013a — that event's subscription entry MUST
    /// carry its own `pane_id`, unlike every other entry here). A newly created
    /// pane gains `pane.agent_status_changed` coverage only on the next
    /// resubscribe, which [`super::incoming`]'s `pane.created` handling triggers
    /// by returning [`super::events::SubscriptionAction::Resubscribe`] — reusing
    /// the reconnect path rather than inventing an incremental-subscribe protocol
    /// Herdr does not offer.
    /// ponytail: resubscribe-on-pane-created (not an incremental add) — upgrade
    /// only if Herdr ever offers a way to extend a live subscription.
    pub fn subscription_entries<'a>(pane_ids: impl IntoIterator<Item = &'a str>) -> Vec<Value> {
        let mut entries: Vec<Value> = UNFILTERED_TREE_EVENTS
            .iter()
            .map(|t| serde_json::json!({ "type": t }))
            .collect();
        for pane_id in pane_ids {
            entries.push(
                serde_json::json!({ "type": "pane.agent_status_changed", "pane_id": pane_id }),
            );
        }
        entries
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ipc::HerdrClient;

    #[test]
    fn subscription_entries_add_a_filter_per_pane_for_agent_status_only() {
        let entries = Bridge::<HerdrClient>::subscription_entries(["w1:p1", "w1:p2"]);
        assert_eq!(entries.len(), UNFILTERED_TREE_EVENTS.len() + 2);
        let agent_status: Vec<_> = entries
            .iter()
            .filter(|e| e["type"] == "pane.agent_status_changed")
            .collect();
        assert_eq!(agent_status.len(), 2);
        assert!(agent_status.iter().all(|e| e["pane_id"].is_string()));
        let unfiltered: Vec<_> = entries
            .iter()
            .filter(|e| e["type"] == "pane.updated")
            .collect();
        assert_eq!(unfiltered.len(), 1);
        assert!(unfiltered[0].get("pane_id").is_none());
    }

    fn temp_paths(tag: &str) -> ConfigPaths {
        let dir = std::env::temp_dir().join(format!(
            "herdr-relay-requests-test-{tag}-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .expect("the system clock is after the Unix epoch")
                .as_nanos()
        ));
        std::fs::remove_dir_all(&dir).ok();
        ConfigPaths::new(dir)
    }

    #[test]
    fn device_list_request_wraps_bridge_device_list() {
        let paths = temp_paths("list");
        let mut store = DeviceStore::load(paths.clone()).expect("load a fresh device store");
        store
            .add(
                "host-1".to_string(),
                "AAAAAAAAAAAAAAAAAAAAAA".to_string(),
                "device-a".to_string(),
                "Pixel 9 Pro".to_string(),
                herdr_relay_proto::messages::Platform::Android,
                "15".to_string(),
                [7u8; 32],
            )
            .expect("add device-a");

        let message = Bridge::<HerdrClient>::device_list_request(
            &store,
            None,
            herdr_relay_proto::messages::DeviceListRequest {},
        );
        match message {
            Message::DeviceList(list) => {
                assert_eq!(list.devices.len(), 1);
                assert_eq!(list.devices[0].id, "device-a");
            }
            other => panic!("expected Message::DeviceList, got {other:?}"),
        }
        std::fs::remove_dir_all(paths.dir()).ok();
    }

    #[test]
    fn revoke_device_request_wraps_bridge_revoke_device() {
        let paths = temp_paths("revoke");
        let mut store = DeviceStore::load(paths.clone()).expect("load a fresh device store");
        store
            .add(
                "host-1".to_string(),
                "AAAAAAAAAAAAAAAAAAAAAA".to_string(),
                "device-a".to_string(),
                "Pixel 9 Pro".to_string(),
                herdr_relay_proto::messages::Platform::Android,
                "15".to_string(),
                [7u8; 32],
            )
            .expect("add device-a");

        let message = Bridge::<HerdrClient>::revoke_device_request(
            &mut store,
            &paths,
            RevokeDevice {
                device_id: Some("device-a".to_string()),
                all: None,
            },
            None,
        )
        .expect("revoke device-a");
        match message {
            Message::RevokeResult(result) => {
                assert_eq!(result.revoked, vec!["device-a".to_string()]);
                assert!(!result.all);
            }
            other => panic!("expected Message::RevokeResult, got {other:?}"),
        }
        assert!(store.devices().is_empty(), "revoke removes the entry");
        std::fs::remove_dir_all(paths.dir()).ok();
    }

    #[test]
    fn revoke_device_request_rejects_neither_field_present() {
        let paths = temp_paths("invalid");
        let mut store = DeviceStore::load(paths.clone()).expect("load a fresh device store");
        let result = Bridge::<HerdrClient>::revoke_device_request(
            &mut store,
            &paths,
            RevokeDevice {
                device_id: None,
                all: None,
            },
            None,
        );
        assert!(
            matches!(result, Err(WatchError::Device(_))),
            "an ambiguous revoke_device must be refused, not silently repaired (R-41-037)"
        );
        std::fs::remove_dir_all(paths.dir()).ok();
    }

    /// R-11-064: "the current Device's session is closed". Proves
    /// `revoke_device_request` actually composes `SessionRegistry` when one is
    /// wired in, not just `Bridge::revoke_device`'s store/key half.
    #[test]
    fn revoke_device_request_closes_the_live_session_when_a_registry_is_wired_in() {
        let paths = temp_paths("registry");
        let mut store = DeviceStore::load(paths.clone()).expect("load a fresh device store");
        store
            .add(
                "host-1".to_string(),
                "AAAAAAAAAAAAAAAAAAAAAA".to_string(),
                "device-a".to_string(),
                "Pixel 9 Pro".to_string(),
                herdr_relay_proto::messages::Platform::Android,
                "15".to_string(),
                [7u8; 32],
            )
            .expect("add device-a");

        let registry = SessionRegistry::new();
        let handle = herdr_relay_proto::handle::Handle::generate().expect("generate a handle");
        let mut close_rx = registry.register(handle, Some("device-a".to_string()));

        let _ = Bridge::<HerdrClient>::revoke_device_request(
            &mut store,
            &paths,
            RevokeDevice {
                device_id: Some("device-a".to_string()),
                all: None,
            },
            Some(&registry),
        )
        .expect("revoke device-a");

        assert!(
            matches!(close_rx.try_recv(), Ok(crate::relay::CloseReason::Revoked)),
            "device-a's live session must receive the revoked close signal"
        );
        std::fs::remove_dir_all(paths.dir()).ok();
    }
}
