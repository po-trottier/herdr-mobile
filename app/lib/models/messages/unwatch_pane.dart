/// `unwatch_pane` (`docs/11-relay-protocol.md` §4.8). Sender: Device.
/// Reply: no. Correlation: no. Mirrors `UnwatchPane` in
/// `crates/herdr-relay-proto/src/messages/watch.rs:34-38`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'unwatch_pane.freezed.dart';
part 'unwatch_pane.g.dart';

@freezed
abstract class UnwatchPane with _$UnwatchPane {
  const factory UnwatchPane({
    @JsonKey(name: 'pane_id') required String paneId,
  }) = _UnwatchPane;

  factory UnwatchPane.fromJson(Map<String, dynamic> json) =>
      _$UnwatchPaneFromJson(json);
}
