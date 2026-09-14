/// `error` (`docs/11-relay-protocol.md` §4.22). Sender: either. Reply: no.
/// Correlation: optional. `fatal: true` MUST be the last frame before the
/// Noise session closes (R-11-065). Mirrors `ErrorMessage` in
/// `crates/herdr-relay-proto/src/messages/control.rs:8-16`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../codes.dart';

part 'error_message.freezed.dart';
part 'error_message.g.dart';

@freezed
abstract class ErrorMessage with _$ErrorMessage {
  const factory ErrorMessage({
    @JsonKey(fromJson: errorCodeFromJson, toJson: errorCodeToJson)
    required ErrorCode code,

    /// Shown raw in the app; never replaced with a friendly sentence
    /// (R-11-092).
    required String message,
    required bool fatal,
  }) = _ErrorMessage;

  factory ErrorMessage.fromJson(Map<String, dynamic> json) =>
      _$ErrorMessageFromJson(json);
}
