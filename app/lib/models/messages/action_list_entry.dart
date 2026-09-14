/// One projected plugin action inside `action_list.actions`
/// (`docs/11-relay-protocol.md` §4.25). MUST NOT carry `command`,
/// `manifest_path`, `plugin_root`, a `*_cwd` field, or any host path
/// (R-11-209). Mirrors `ActionListEntry` in
/// `crates/herdr-relay-proto/src/messages/action.rs:86-93`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'action_list_entry.freezed.dart';
part 'action_list_entry.g.dart';

@freezed
abstract class ActionListEntry with _$ActionListEntry {
  const factory ActionListEntry({
    @JsonKey(name: 'plugin_id') required String pluginId,
    @JsonKey(name: 'action_id') required String actionId,
    required String title,
    String? description,
    List<String>? contexts,
  }) = _ActionListEntry;

  factory ActionListEntry.fromJson(Map<String, dynamic> json) =>
      _$ActionListEntryFromJson(json);
}
