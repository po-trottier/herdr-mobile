/// `action_list` (`docs/11-relay-protocol.md` §4.25). Sender: Host. Reply:
/// no (reply to `action_list_request`). Correlation: yes. Mirrors
/// `ActionList` in `crates/herdr-relay-proto/src/messages/action.rs:77-82`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import 'action_list_entry.dart';

part 'action_list.freezed.dart';
part 'action_list.g.dart';

@freezed
abstract class ActionList with _$ActionList {
  const factory ActionList({required List<ActionListEntry> actions}) =
      _ActionList;

  factory ActionList.fromJson(Map<String, dynamic> json) =>
      _$ActionListFromJson(json);
}
