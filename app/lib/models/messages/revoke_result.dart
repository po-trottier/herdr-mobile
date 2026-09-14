/// `revoke_result` (`docs/11-relay-protocol.md` §4.21). Sender: Host.
/// Reply: no (reply to `revoke_device`). Correlation: yes. When `all` is
/// `true`, the Host also generates a new Host static keypair (R-11-064).
/// Mirrors `RevokeResult` in
/// `crates/herdr-relay-proto/src/messages/device.rs:43-50`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'revoke_result.freezed.dart';
part 'revoke_result.g.dart';

@freezed
abstract class RevokeResult with _$RevokeResult {
  const factory RevokeResult({
    required List<String> revoked,
    required bool all,
  }) = _RevokeResult;

  factory RevokeResult.fromJson(Map<String, dynamic> json) =>
      _$RevokeResultFromJson(json);
}
