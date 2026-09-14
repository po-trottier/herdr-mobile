/// `tree_update` (`docs/11-relay-protocol.md` §4.5). Sender: Host. Reply:
/// no. Correlation: no. Sent for every subscribed Herdr event that changes
/// the tree (R-11-046, R-11-047). Mirrors `TreeUpdate` in
/// `crates/herdr-relay-proto/src/messages/tree.rs:78-84`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import 'pane_summary.dart';
import 'tab_summary.dart';
import 'tree_event.dart';
import 'workspace_summary.dart';

part 'tree_update.freezed.dart';
part 'tree_update.g.dart';

@freezed
abstract class TreeUpdate with _$TreeUpdate {
  const factory TreeUpdate({
    required TreeEvent event,
    @JsonKey(includeIfNull: false) PaneSummary? pane,
    @JsonKey(includeIfNull: false) WorkspaceSummary? workspace,
    @JsonKey(includeIfNull: false) TabSummary? tab,
  }) = _TreeUpdate;

  factory TreeUpdate.fromJson(Map<String, dynamic> json) =>
      _$TreeUpdateFromJson(json);
}
