/// `revoke_device` (`docs/11-relay-protocol.md` §4.20). Sender: Device.
/// Reply: `revoke_result`. Correlation: yes. Exactly one of `deviceId` or
/// `all` MUST be present (R-11-063). Mirrors `RevokeDevice` in
/// `crates/herdr-relay-proto/src/messages/device.rs:33-41`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'revoke_device.freezed.dart';
part 'revoke_device.g.dart';

@freezed
abstract class RevokeDevice with _$RevokeDevice {
  const factory RevokeDevice({
    @JsonKey(name: 'device_id', includeIfNull: false) String? deviceId,
    @JsonKey(includeIfNull: false) bool? all,
  }) = _RevokeDevice;

  factory RevokeDevice.fromJson(Map<String, dynamic> json) =>
      _$RevokeDeviceFromJson(json);
}
