/// One workspace in `tree_snapshot.workspaces`
/// (`docs/11-relay-protocol.md` §4.4). Mirrors `WorkspaceSummary` in
/// `crates/herdr-relay-proto/src/messages/tree.rs`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`). [spaceId] is the Host's
/// desktop-sidebar grouping (decided 2026-09-08 by the product owner): the
/// agent list draws one top-level entry per desktop entry from it
/// (`docs/31-mockups/06-agent-list.md` R-31-06-27). [repoName] and
/// [isLinkedWorktree] carry the Herdr `worktree` object's `repo_name` and
/// `is_linked_worktree` as metadata; neither groups anything.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'workspace_summary.freezed.dart';
part 'workspace_summary.g.dart';

@freezed
abstract class WorkspaceSummary with _$WorkspaceSummary {
  const factory WorkspaceSummary({
    @JsonKey(name: 'workspace_id') required String workspaceId,
    required String name,
    required bool focused,

    /// The `workspace_id` of the group's parent, the first workspace of the
    /// snapshot that shares this workspace's repo and is not a linked worktree
    /// (Herdr `src/ui/sidebar.rs` at `b1ff4582e968`, `workspace_list_entries`).
    /// The Host sets it on every member of a group of two or more workspaces
    /// with such a parent, the parent included, so the parent's own [spaceId]
    /// is its [workspaceId]. `null` when the workspace stands alone on the
    /// desktop: no `worktree`, the only workspace of its repo, or a repo with
    /// linked worktrees only. The Host always writes the key, as an explicit
    /// `null` in that case, like [repoName]. The parent is always present in
    /// the same snapshot.
    @JsonKey(name: 'space_id') String? spaceId,

    /// `worktree.repo_name`; `null` when the workspace has no `worktree`.
    /// The Host always writes the key, as an explicit `null` in that case,
    /// so this side writes it the same way and the wire vectors round-trip.
    @JsonKey(name: 'repo_name') String? repoName,

    /// `worktree.is_linked_worktree`; `false` when the workspace has no
    /// `worktree`.
    @JsonKey(name: 'is_linked_worktree', defaultValue: false)
    @Default(false)
    bool isLinkedWorktree,
  }) = _WorkspaceSummary;

  factory WorkspaceSummary.fromJson(Map<String, dynamic> json) =>
      _$WorkspaceSummaryFromJson(json);
}
