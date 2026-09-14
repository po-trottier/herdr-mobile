//! Mapping a raw Herdr subscription push to our domain concepts: which
//! `TreeEvent` it represents, extracting its `pane_id`, and what the run loop
//! should do about the subscription connection afterward.

use serde_json::Value;

use herdr_relay_proto::messages::{AgentStatusKind, TreeEvent};

/// The 13 Herdr events `tree_update` forwards unconditionally on the long-lived
/// subscription connection (R-11-047), every one of them accepted with no filter
/// field. `pane.agent_status_changed` is the 14th: it also drives `tree_update`
/// (via `TreeEvent::PaneAgentStatusChanged`) but, unlike these, its subscription
/// entry MUST additionally carry a `pane_id` (R-02-013a) — see
/// [`super::Bridge::subscription_entries`].
pub(super) const UNFILTERED_TREE_EVENTS: &[&str] = &[
    "workspace.created",
    "workspace.updated",
    "workspace.renamed",
    "workspace.closed",
    "tab.created",
    "tab.closed",
    "tab.renamed",
    "tab.focused",
    "pane.created",
    "pane.closed",
    "pane.updated",
    "pane.focused",
    "layout.updated",
];

/// What [`super::Bridge::handle_subscription_line`] wants the run loop to do about
/// the subscription connection.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SubscriptionAction {
    None,
    /// A pane was created: R-02-013a means its `pane.agent_status_changed`
    /// coverage can only be added by resubscribing with the full pane list.
    Resubscribe,
}

pub(super) fn pane_id_of(data: Option<&Value>) -> Option<&str> {
    data.and_then(|d| d.get("pane"))
        .and_then(|p| p.get("pane_id"))
        .and_then(Value::as_str)
        .or_else(|| data.and_then(|d| d.get("pane_id")).and_then(Value::as_str))
}

/// Matches against the underscore-separated push `event` name
/// [`super::Bridge::handle_subscription_line`] already normalized (see its own
/// comment for the live-measured dot-vs-underscore finding).
pub(super) fn tree_event_for(event_name: &str) -> Option<TreeEvent> {
    Some(match event_name {
        "workspace_created" => TreeEvent::WorkspaceCreated,
        "workspace_updated" => TreeEvent::WorkspaceUpdated,
        "workspace_renamed" => TreeEvent::WorkspaceRenamed,
        "workspace_closed" => TreeEvent::WorkspaceClosed,
        "tab_created" => TreeEvent::TabCreated,
        "tab_closed" => TreeEvent::TabClosed,
        "tab_renamed" => TreeEvent::TabRenamed,
        "tab_focused" => TreeEvent::TabFocused,
        "pane_created" => TreeEvent::PaneCreated,
        "pane_closed" => TreeEvent::PaneClosed,
        "pane_updated" => TreeEvent::PaneUpdated,
        "pane_focused" => TreeEvent::PaneFocused,
        "pane_agent_status_changed" => TreeEvent::PaneAgentStatusChanged,
        "layout_updated" => TreeEvent::LayoutUpdated,
        _ => return None,
    })
}

/// Parses Herdr's raw `agent_status` string (`PaneSummary.agent_status`, see
/// `super::raw`'s own doc comment for why this is a raw field name, not the
/// wire's) into the wire's [`AgentStatusKind`]. `None` for an unrecognized
/// value: matches this module's own defensive convention of ignoring what it
/// does not recognize rather than failing the subscription loop.
pub(super) fn agent_status_kind_of(raw: &str) -> Option<AgentStatusKind> {
    Some(match raw {
        "idle" => AgentStatusKind::Idle,
        "working" => AgentStatusKind::Working,
        "blocked" => AgentStatusKind::Blocked,
        "done" => AgentStatusKind::Done,
        "unknown" => AgentStatusKind::Unknown,
        _ => return None,
    })
}

/// RFC 3339 UTC "now", for `agent_status_observed` timestamps (R-11-224). Uses the
/// `time` crate already pinned for `store.rs`'s `paired_at`/`last_seen` — no new
/// dependency.
pub(super) fn now_rfc3339() -> String {
    time::OffsetDateTime::now_utc()
        .format(&time::format_description::well_known::Rfc3339)
        .unwrap_or_else(|_| String::new())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tree_event_for_maps_every_subscribed_event_name() {
        for name in UNFILTERED_TREE_EVENTS {
            let normalized = name.replace('.', "_");
            assert!(tree_event_for(&normalized).is_some(), "{name} should map");
        }
        assert!(tree_event_for("pane_agent_status_changed").is_some());
        assert!(tree_event_for("worktree_created").is_none());
    }
}
