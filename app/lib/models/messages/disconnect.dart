/// `disconnect` (`docs/11-relay-protocol.md` §4.23). Sender: Device. Reply:
/// no. Correlation: no. Sent as the last application frame before a
/// deliberate close with code `1000` (R-11-206). The payload is `{}`.
/// Mirrors `Disconnect` in
/// `crates/herdr-relay-proto/src/messages/control.rs:18-22`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'disconnect.freezed.dart';
part 'disconnect.g.dart';

@freezed
abstract class Disconnect with _$Disconnect {
  const factory Disconnect() = _Disconnect;

  factory Disconnect.fromJson(Map<String, dynamic> json) =>
      _$DisconnectFromJson(json);
}
