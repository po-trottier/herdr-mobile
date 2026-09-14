/// `watch_pane` (`docs/11-relay-protocol.md` §4.6). Sender: Device. Reply:
/// `watch_ack`. Correlation: yes. The Device watches at most one pane at a
/// time; a second `watch_pane` replaces the first (R-11-048). Mirrors
/// `WatchPane` in `crates/herdr-relay-proto/src/messages/watch.rs:9-12`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'watch_pane.freezed.dart';
part 'watch_pane.g.dart';

@freezed
abstract class WatchPane with _$WatchPane {
  const factory WatchPane({@JsonKey(name: 'pane_id') required String paneId}) =
      _WatchPane;

  factory WatchPane.fromJson(Map<String, dynamic> json) =>
      _$WatchPaneFromJson(json);
}
