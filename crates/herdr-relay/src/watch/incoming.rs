//! Interpreting one raw line from the Herdr subscription connection: the
//! `subscription_started` acknowledgement, or an event push that may produce a
//! `tree_update` and may feed the debounce scheduler for the watched pane.

use std::time::Instant;

use serde_json::{Value, json};

use herdr_relay_proto::messages::{AgentStatus, AgentStatusKind, Message, TreeUpdate};

use super::bridge::{Bridge, WatchError, lock_observed};
use super::events::{
    SubscriptionAction, agent_status_kind_of, now_rfc3339, pane_id_of, tree_event_for,
};
use super::herdr_calls::HerdrCalls;
use super::raw::{RawPane, RawTab, RawWorkspace, map_pane, map_tab, map_workspace};

impl<H: HerdrCalls> Bridge<H> {
    /// Handles one raw line from the Herdr subscription connection: the
    /// `subscription_started` acknowledgement (ignored) or an event push. Returns
    /// the messages to forward to the Device (zero or more `tree_update`s) and
    /// whether the caller should resubscribe (a new pane needs
    /// `pane.agent_status_changed` coverage — R-02-013a).
    pub fn handle_subscription_line(
        &mut self,
        line: &str,
    ) -> Result<(Vec<Message>, SubscriptionAction), WatchError> {
        let parsed: Value =
            serde_json::from_str(line.trim_end()).map_err(|source| WatchError::Malformed {
                method: "events.subscribe",
                source,
            })?;

        if parsed.get("result").and_then(|r| r.get("type")) == Some(&json!("subscription_started"))
        {
            return Ok((Vec::new(), SubscriptionAction::None));
        }

        let Some(raw_event_name) = parsed.get("event").and_then(Value::as_str) else {
            return Ok((Vec::new(), SubscriptionAction::None)); // unrecognised push: ignore, don't fail the loop
        };
        // Measured live 2026-08-27 against Herdr `0.8.2-preview.2026-08-19-b5c4a0176e91`:
        // a push's `event` field is underscore-separated (`pane_updated`), not the
        // dotted form `events.subscribe`'s `type` parameter and
        // `docs/11-relay-protocol.md` R-11-047 both use (`pane.updated`). Confirmed
        // independently by `src/bin/spike-subscribe.rs`'s own live output. Normalize
        // once here so every comparison below uses one form.
        let event_name = raw_event_name.replace('.', "_");
        let event_name = event_name.as_str();
        let data = parsed.get("data");
        let mut out = Vec::new();
        let mut action = SubscriptionAction::None;

        if event_name == "pane_agent_status_changed"
            && let Some(pane_id) = pane_id_of(data)
        {
            lock_observed(&self.agent_status_observed).insert(pane_id.to_string(), now_rfc3339());

            // R-11-057: send only for `blocked`/`done`; R-11-059: at most once
            // per 30 s per agent. The push's `data` is the flat
            // `pane_agent_status_changed` EventData variant (`herdr api schema`,
            // protocol 21): `pane_id`, `workspace_id`, `agent_status`, optional
            // `agent`/`display_agent`/`title`/`state_labels` — it carries no
            // `pane` or `tab` object, so the routing and title fields come from
            // one fresh snapshot (the settle window bounds this to at most one
            // fetch per 30 s per pane). A pane missing from that snapshot is
            // gone: skip rather than notify with invented fields.
            let status = data
                .and_then(|d| d.get("agent_status"))
                .and_then(Value::as_str)
                .and_then(agent_status_kind_of);
            if let Some(status) = status
                && matches!(status, AgentStatusKind::Blocked | AgentStatusKind::Done)
                && self.settle_agent_status(pane_id, Instant::now())
                && let Ok(snapshot) = self.fetch_snapshot().map(|raw| self.map_snapshot(raw))
                && let Some(pane) = snapshot.panes.iter().find(|p| p.pane_id == pane_id)
            {
                let tab_title = snapshot
                    .tabs
                    .iter()
                    .find(|t| t.tab_id == pane.tab_id)
                    .map(|t| t.title.clone())
                    .unwrap_or_default();
                let agent_kind = data
                    .and_then(|d| d.get("agent"))
                    .and_then(Value::as_str)
                    .map(str::to_owned)
                    .or_else(|| pane.agent.clone())
                    .unwrap_or_default();
                out.push(Message::AgentStatus(AgentStatus {
                    host_id: self.host_id().to_owned(),
                    pane_id: pane.pane_id.clone(),
                    workspace_id: pane.workspace_id.clone(),
                    tab_id: pane.tab_id.clone(),
                    tab_title,
                    pane_title: pane.title.clone(),
                    agent_kind,
                    status,
                    at: now_rfc3339(),
                }));
            }
        }

        if let Some(tree_event) = tree_event_for(event_name) {
            let pane = data
                .and_then(|d| d.get("pane"))
                .and_then(|p| serde_json::from_value::<RawPane>(p.clone()).ok())
                .map(map_pane);
            let workspace = data
                .and_then(|d| d.get("workspace"))
                .and_then(|w| serde_json::from_value::<RawWorkspace>(w.clone()).ok())
                .map(map_workspace);
            let tab = data
                .and_then(|d| d.get("tab"))
                .and_then(|t| serde_json::from_value::<RawTab>(t.clone()).ok())
                .map(map_tab);
            out.push(Message::TreeUpdate(Box::new(TreeUpdate {
                event: tree_event,
                pane,
                workspace,
                tab,
            })));
        }

        // R-11-046: grouping (`WorkspaceSummary.space_id`) is whole-list state the
        // single `tree_update.workspace` above cannot carry — any workspace event can
        // create or dissolve a worktree group or move its parent, and the Device
        // adopts any `tree_snapshot` as its new base wholesale. Follow every
        // workspace event with a fresh full snapshot so no Device keeps a stale
        // group id. The same rule (amended 2026-09-11) covers the three events Herdr
        // pushes with a flat payload, measured live: `tab_closed` is
        // `{"tab_id","workspace_id"}`, `pane_agent_status_changed` is the flat
        // variant of R-11-057, and a closed tab's panes get no `pane_closed` at all.
        // The `tree_update` built above therefore carries no object for them, so the
        // snapshot is what removes the pane and what moves `done` back to `working`.
        // A failed refresh is not fatal: the next event or a reconnect
        // resynchronises, the same convention as `handle_pane_updated`.
        // R-11-046 second amendment, R-02-031: focus changes seen without a status event.
        if matches!(
            event_name,
            "workspace_created"
                | "workspace_updated"
                | "workspace_renamed"
                | "workspace_closed"
                | "tab_closed"
                | "pane_closed"
                | "pane_agent_status_changed"
                | "pane_focused"
        ) && let Ok(raw) = self.fetch_snapshot()
        {
            out.push(Message::TreeSnapshot(self.map_snapshot(raw)));
        }

        if event_name == "pane_created" {
            action = SubscriptionAction::Resubscribe;
        }

        if event_name == "pane_updated" {
            self.handle_pane_updated(data);
        }

        if event_name == "pane_closed"
            && let Some(pane_id) = pane_id_of(data)
            && self.watched.as_ref().is_some_and(|w| w.pane_id == pane_id)
        {
            self.watched = None;
            self.scheduler = None;
        }

        Ok((out, action))
    }

    fn handle_pane_updated(&mut self, data: Option<&Value>) {
        let Some(pane_id) = pane_id_of(data) else {
            return;
        };
        let Some(revision) = data
            .and_then(|d| d.get("pane"))
            .and_then(|p| p.get("revision"))
            .and_then(Value::as_u64)
        else {
            return;
        };
        let new_rows = data
            .and_then(|d| d.get("pane"))
            .and_then(|p| p.get("scroll"))
            .and_then(|s| s.get("viewport_rows"))
            .and_then(Value::as_u64)
            .map(|v| v as u32);

        let is_watched = self.watched.as_ref().is_some_and(|w| w.pane_id == pane_id);
        if !is_watched {
            return; // R-01-007, R-02-013: discard before any read
        }
        let rows_changed = new_rows.is_some_and(|rows| {
            self.watched
                .as_ref()
                .is_some_and(|w| w.viewport_rows != rows)
        });
        let already_seen = self
            .watched
            .as_ref()
            .is_some_and(|w| w.last_revision == revision);
        if already_seen && !rows_changed {
            return; // R-10-032
        }
        // A changed `viewport_rows` with an unmoved revision is still a change the
        // bridge consumes (R-10-025, R-10-070): fall through, refresh the
        // geometry, and schedule one read so the frame carries the new grid.

        if let Some(watched) = &mut self.watched {
            watched.last_revision = revision;
            if let Some(rows) = new_rows {
                watched.viewport_rows = rows;
            }
        }

        if rows_changed {
            // R-10-025: pane.layout only on attach or a changed viewport_rows.
            if let Ok(width) = self.fetch_width(pane_id)
                && let Some(watched) = &mut self.watched
            {
                watched.width = width;
            }
        }

        if let Some(scheduler) = &mut self.scheduler {
            scheduler.on_revision_changed(Instant::now());
        }
    }
}
