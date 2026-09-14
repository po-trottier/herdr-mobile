/// One pane in `tree_snapshot.panes` (`docs/11-relay-protocol.md` §4.4) or
/// `tree_update.pane` (§4.5). Mirrors `PaneSummary` in
/// `crates/herdr-relay-proto/src/messages/tree.rs:41-55`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
///
/// `revision` MUST come from the snapshot, never from a `pane.read` result,
/// which is always `0` (R-11-045). `title` is Herdr's own `PaneInfo.title`;
/// a raw terminal OSC title MUST NOT cross the wire (R-11-225).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import 'pane_scroll_state.dart';

part 'pane_summary.freezed.dart';
part 'pane_summary.g.dart';

@freezed
abstract class PaneSummary with _$PaneSummary {
  const factory PaneSummary({
    @JsonKey(name: 'pane_id') required String paneId,
    @JsonKey(name: 'workspace_id') required String workspaceId,
    @JsonKey(name: 'tab_id') required String tabId,
    @JsonKey(name: 'terminal_id') required String terminalId,
    required String label,
    required String title,
    required String cwd,
    required bool focused,
    String? agent,
    @JsonKey(name: 'agent_status') required String agentStatus,
    required int revision,
    required PaneScrollState scroll,
  }) = _PaneSummary;

  factory PaneSummary.fromJson(Map<String, dynamic> json) =>
      _$PaneSummaryFromJson(json);
}
