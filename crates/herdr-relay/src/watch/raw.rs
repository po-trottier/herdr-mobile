//! Raw shapes read directly off Herdr's own `session.snapshot`/`pane.updated`
//! JSON, distinct from the relay-wire `herdr_relay_proto::messages` types they
//! feed. This crate MUST NOT assume the wire shape's field names apply verbatim
//! to Herdr's own JSON: measured live 2026-08-27 against Herdr
//! `0.8.2-preview.2026-08-19-b5c4a0176e91` (`herdr api snapshot`), a raw
//! workspace and a raw tab each carry `label`, never `name`/`title`; a raw pane
//! carries `label` only when set and no `title` field at all; and a raw agent
//! entry names its kind `agent`, its status `agent_status`, and its session
//! `agent_session` (an object, not a string). `docs/10-herdr-integration.md` §3.4
//! does not enumerate these exact names, so the live capture is the ground truth
//! (`AGENTS.md` "Never diverge silently" — recorded here, not silently patched).

use serde::Deserialize;

use herdr_relay_proto::messages::{PaneScrollState, PaneSummary, TabSummary, WorkspaceSummary};

#[derive(Debug, Deserialize)]
pub(super) struct RawSnapshot {
    #[serde(default)]
    pub(super) workspaces: Vec<RawWorkspace>,
    #[serde(default)]
    pub(super) tabs: Vec<RawTab>,
    #[serde(default)]
    pub(super) panes: Vec<RawPane>,
    #[serde(default)]
    pub(super) agents: Vec<RawAgent>,
}

#[derive(Debug, Deserialize)]
pub(super) struct RawWorkspace {
    pub(super) workspace_id: String,
    #[serde(default)]
    label: String,
    pub(super) focused: bool,
    /// Measured live 2026-09-04 (`herdr api snapshot`): present only for a workspace
    /// that is a git checkout. Absent for a plain-directory workspace.
    #[serde(default)]
    worktree: Option<RawWorktree>,
}

/// Herdr's raw `worktree` object. Only `repo_name` and `is_linked_worktree` cross the
/// wire. `repo_key` is read strictly in-process to derive `WorkspaceSummary.space_id`
/// (it is the desktop's group key, `WorktreeSpaceMembership.key`); like
/// `checkout_path` and `repo_root` it is a user-local value that MUST NOT cross the
/// wire (`AGENTS.md` "Never log") — this struct is `Deserialize`-only, so the key
/// cannot serialize out by accident, and the two paths are not even deserialized.
#[derive(Debug, Deserialize)]
pub(super) struct RawWorktree {
    repo_name: String,
    #[serde(default)]
    is_linked_worktree: bool,
    /// Present on every `worktree` object the pinned Herdr emits
    /// (`src/app/creation.rs` `workspace_info`, commit b1ff4582e968). `None` only if a
    /// future build drops it; the workspace then never groups, never false-groups.
    #[serde(default)]
    repo_key: Option<String>,
}

#[derive(Debug, Deserialize)]
pub(super) struct RawTab {
    pub(super) tab_id: String,
    pub(super) workspace_id: String,
    #[serde(default)]
    label: String,
    pub(super) focused: bool,
}

/// A raw pane. `revision` and `scroll` are read directly (matching field names,
/// including `scroll.viewport_rows`); `label`, `title` and `agent` MUST go
/// through [`map_pane`], never a direct field-for-field reuse of
/// [`PaneSummary`] — see this module's struct-level doc for why.
#[derive(Debug, Clone, Deserialize)]
pub(super) struct RawPane {
    pub(super) pane_id: String,
    workspace_id: String,
    tab_id: String,
    terminal_id: String,
    #[serde(default)]
    label: String,
    cwd: String,
    focused: bool,
    #[serde(default)]
    agent: Option<String>,
    agent_status: String,
    pub(super) revision: u64,
    pub(super) scroll: PaneScrollState,
}

/// Herdr's raw `agents[]` entry. Measured live 2026-08-27 against Herdr
/// `0.8.2-preview.2026-08-19-b5c4a0176e91` (`herdr api snapshot`): the kind is
/// named `agent`, not `agent_kind`; the status is `agent_status`, not `status`;
/// and `agent_session` is an object (`{agent, kind, source, value}`), not the
/// plain string `AgentSummary.session` expects. `docs/10-herdr-integration.md`
/// §3.4 does not enumerate these field names, and the wire shape's own names
/// (`docs/11-relay-protocol.md` R-11-044) do not apply verbatim to Herdr's raw
/// JSON here — this struct corrects that assumption against the live capture.
#[derive(Debug, Deserialize)]
pub(super) struct RawAgent {
    pub(super) agent: String,
    pub(super) pane_id: String,
    pub(super) agent_status: String,
    #[serde(default)]
    pub(super) agent_session: Option<RawAgentSession>,
}

#[derive(Debug, Deserialize)]
pub(super) struct RawAgentSession {
    #[serde(default)]
    pub(super) value: Option<String>,
}

/// Maps one workspace for the incremental `tree_update` path. `space_id` stays
/// `None` here: grouping is whole-list state, authoritative only in a full
/// `tree_snapshot` ([`map_workspaces`]), and a fresh snapshot follows every
/// workspace event (R-11-046), so no Device keeps a stale group id.
pub(super) fn map_workspace(w: RawWorkspace) -> WorkspaceSummary {
    let (repo_name, is_linked_worktree) = match w.worktree {
        Some(t) => (Some(t.repo_name), t.is_linked_worktree),
        None => (None, false),
    };
    WorkspaceSummary {
        workspace_id: w.workspace_id,
        name: w.label,
        focused: w.focused,
        repo_name,
        is_linked_worktree,
        space_id: None,
    }
}

/// The desktop worktree grouping, transliterated from Herdr's
/// `workspace_list_entries_inner` (`src/ui/sidebar.rs:344-441`, commit b1ff4582e968):
/// members share one private `worktree.repo_key`; a group is eligible with two or
/// more members and at least one non-linked member; the wire group id is the first
/// non-linked member's `workspace_id` (the desktop's parent entry), set on every
/// member, the parent included. Returned per workspace, in input order; `None` for a
/// lone workspace, a linked-only group, a plain directory, or a worktree whose key a
/// future Herdr stopped sending. `repo_name` is never consulted: two repos can share
/// one name and MUST stay separate groups.
pub(super) fn space_ids(workspaces: &[RawWorkspace]) -> Vec<Option<String>> {
    let mut members_by_key = std::collections::HashMap::<&str, Vec<usize>>::new();
    for (idx, workspace) in workspaces.iter().enumerate() {
        if let Some(key) = workspace
            .worktree
            .as_ref()
            .and_then(|worktree| worktree.repo_key.as_deref())
        {
            members_by_key.entry(key).or_default().push(idx);
        }
    }
    let mut out = vec![None; workspaces.len()];
    for members in members_by_key.values() {
        if members.len() < 2 {
            continue;
        }
        let Some(&parent) = members.iter().find(|&&idx| {
            workspaces[idx]
                .worktree
                .as_ref()
                .is_some_and(|worktree| !worktree.is_linked_worktree)
        }) else {
            continue; // a linked-only group: the desktop draws no group either
        };
        for &idx in members {
            out[idx] = Some(workspaces[parent].workspace_id.clone());
        }
    }
    out
}

/// Maps every raw workspace in Herdr's own order, attaching each one's group id from
/// [`space_ids`]. The full `tree_snapshot` is the only place `space_id` is set.
pub(super) fn map_workspaces(workspaces: Vec<RawWorkspace>) -> Vec<WorkspaceSummary> {
    let ids = space_ids(&workspaces);
    workspaces
        .into_iter()
        .zip(ids)
        .map(|(workspace, space_id)| {
            let mut summary = map_workspace(workspace);
            summary.space_id = space_id;
            summary
        })
        .collect()
}

pub(super) fn map_tab(t: RawTab) -> TabSummary {
    TabSummary {
        tab_id: t.tab_id,
        workspace_id: t.workspace_id,
        title: t.label,
        focused: t.focused,
    }
}

/// `title` is deliberately always empty: the live capture shows Herdr's raw pane
/// carries no field distinct from `label` for it on this build, and R-11-225
/// forbids substituting `terminal_title` (attacker-controllable OSC content).
/// `[UNVERIFIED]`: whether a future Herdr build adds a real `title` field;
/// revisit this mapping against a fresh `herdr api snapshot` capture if so.
pub(super) fn map_pane(p: RawPane) -> PaneSummary {
    PaneSummary {
        pane_id: p.pane_id,
        workspace_id: p.workspace_id,
        tab_id: p.tab_id,
        terminal_id: p.terminal_id,
        label: p.label,
        title: String::new(),
        cwd: p.cwd,
        focused: p.focused,
        agent: p.agent,
        agent_status: p.agent_status,
        revision: p.revision,
        scroll: p.scroll,
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::{RawWorkspace, map_workspace, map_workspaces};

    fn map(raw: serde_json::Value) -> serde_json::Value {
        let raw: RawWorkspace = serde_json::from_value(raw).expect("raw workspace parses");
        serde_json::to_value(map_workspace(raw)).expect("summary serializes")
    }

    fn map_all(raw: serde_json::Value) -> Vec<serde_json::Value> {
        let raw: Vec<RawWorkspace> = serde_json::from_value(raw).expect("raw workspaces parse");
        map_workspaces(raw)
            .into_iter()
            .map(|w| serde_json::to_value(w).expect("summary serializes"))
            .collect()
    }

    /// One raw workspace carrying a full `worktree` object, user paths included, so
    /// every leak assertion exercises the complete live shape.
    fn worktree(
        workspace_id: &str,
        label: &str,
        repo_name: &str,
        repo_key: &str,
        linked: bool,
    ) -> serde_json::Value {
        json!({
            "workspace_id": workspace_id,
            "label": label,
            "focused": false,
            "worktree": {
                "repo_name": repo_name,
                "is_linked_worktree": linked,
                "checkout_path": "D:\\private\\checkout",
                "repo_root": "D:\\private\\repo",
                "repo_key": repo_key
            }
        })
    }

    /// Live shape 2026-09-04: a linked worktree carries the full `worktree` object.
    /// Only `repo_name` and `is_linked_worktree` cross the wire; the paths never do.
    #[test]
    fn worktree_object_forwards_name_and_flag_but_no_paths() {
        let out = map(json!({
            "workspace_id": "w2",
            "label": "feature/db-interface",
            "focused": false,
            "worktree": {
                "repo_name": "lightspeed-kit",
                "is_linked_worktree": true,
                "checkout_path": "D:\\Repositories\\lightspeed-kit-wt\\feature-db-interface",
                "repo_root": "D:\\Repositories\\lightspeed-kit",
                "repo_key": "abc123"
            }
        }));
        assert_eq!(
            out,
            json!({
                "workspace_id": "w2",
                "name": "feature/db-interface",
                "focused": false,
                "repo_name": "lightspeed-kit",
                "is_linked_worktree": true,
                "space_id": null
            })
        );
        let text = out.to_string();
        for leaked in ["checkout_path", "repo_root", "repo_key", "Repositories"] {
            assert!(
                !text.contains(leaked),
                "{leaked} must not cross the wire: {text}"
            );
        }
    }

    /// A plain-directory workspace has no `worktree`: `repo_name` is an explicit
    /// `null` and `is_linked_worktree` is `false`.
    #[test]
    fn missing_worktree_maps_to_null_and_false() {
        let out = map(json!({ "workspace_id": "w5", "label": "scratch", "focused": true }));
        assert_eq!(
            out,
            json!({
                "workspace_id": "w5",
                "name": "scratch",
                "focused": true,
                "repo_name": null,
                "is_linked_worktree": false,
                "space_id": null
            })
        );
    }

    /// R-11-044: grouping keys on the private `repo_key`, never on `repo_name` — two
    /// repos that share one name stay two groups, each under its own parent.
    #[test]
    fn same_repo_name_with_two_keys_stays_two_groups() {
        let out = map_all(json!([
            worktree("w1", "alpha", "kit", "key-a", false),
            worktree("w2", "alpha/b1", "kit", "key-a", true),
            worktree("w3", "beta", "kit", "key-b", false),
            worktree("w4", "beta/b2", "kit", "key-b", true),
        ]));
        assert_eq!(out[0]["space_id"], json!("w1"));
        assert_eq!(out[1]["space_id"], json!("w1"));
        assert_eq!(out[2]["space_id"], json!("w3"));
        assert_eq!(out[3]["space_id"], json!("w3"));
    }

    /// R-11-044: a linked-only group has no non-linked parent and a lone worktree has
    /// no second member; the desktop draws no group for either, so both stay `null`.
    #[test]
    fn linked_only_group_and_lone_worktree_stay_ungrouped() {
        let out = map_all(json!([
            worktree("w1", "kit/one", "kit", "key-a", true),
            worktree("w2", "kit/two", "kit", "key-a", true),
            worktree("w3", "lone", "solo", "key-b", false),
            { "workspace_id": "w4", "label": "scratch", "focused": false },
        ]));
        for w in &out {
            assert_eq!(
                w["space_id"],
                serde_json::Value::Null,
                "{} must stay ungrouped",
                w["workspace_id"]
            );
        }
    }

    /// R-11-044: the parent is the first non-linked member in Herdr's own order, even
    /// when a linked member comes first in the raw list; the snapshot order itself
    /// passes through untouched.
    #[test]
    fn parent_is_first_non_linked_and_order_is_herdrs() {
        let out = map_all(json!([
            worktree("w9", "kit/linked-a", "kit", "key-a", true),
            worktree("w2", "kit", "kit", "key-a", false),
            worktree("w7", "kit/linked-b", "kit", "key-a", true),
        ]));
        let order: Vec<&str> = out
            .iter()
            .map(|w| {
                w["workspace_id"]
                    .as_str()
                    .expect("workspace_id is a string")
            })
            .collect();
        assert_eq!(order, ["w9", "w2", "w7"], "snapshot keeps Herdr's order");
        for w in &out {
            assert_eq!(
                w["space_id"],
                json!("w2"),
                "every member points at the parent, the parent included"
            );
        }
    }

    /// The private key drives grouping but never appears on the wire: only the
    /// parent's public `workspace_id` does.
    #[test]
    fn space_id_never_leaks_the_private_repo_key() {
        let out = map_all(json!([
            worktree("w1", "kit", "kit", "secret-key-abc123", false),
            worktree("w2", "kit/b1", "kit", "secret-key-abc123", true),
        ]));
        let text = serde_json::to_string(&out).expect("summaries serialize");
        for leaked in [
            "secret-key-abc123",
            "repo_key",
            "checkout_path",
            "repo_root",
            "D:\\private",
        ] {
            assert!(
                !text.contains(leaked),
                "{leaked} must not cross the wire: {text}"
            );
        }
        assert!(
            text.contains("\"space_id\":\"w1\""),
            "the opaque parent id is the only group handle: {text}"
        );
    }
}
