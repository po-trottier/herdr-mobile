/// `tree_snapshot` (`docs/11-relay-protocol.md` §4.4). Sender: Host. Reply:
/// no (reply to `tree_request`). Correlation: yes. Flat, joined by id, not
/// nested (R-11-044). Mirrors `TreeSnapshot` in
/// `crates/herdr-relay-proto/src/messages/tree.rs:13-19`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import 'agent_summary.dart';
import 'pane_summary.dart';
import 'tab_summary.dart';
import 'workspace_summary.dart';

part 'tree_snapshot.freezed.dart';
part 'tree_snapshot.g.dart';

@freezed
abstract class TreeSnapshot with _$TreeSnapshot {
  const factory TreeSnapshot({
    required List<WorkspaceSummary> workspaces,
    required List<TabSummary> tabs,
    required List<PaneSummary> panes,
    required List<AgentSummary> agents,
  }) = _TreeSnapshot;

  factory TreeSnapshot.fromJson(Map<String, dynamic> json) =>
      _$TreeSnapshotFromJson(json);
}
