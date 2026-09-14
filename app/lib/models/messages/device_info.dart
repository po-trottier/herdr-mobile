/// `device_info` (`docs/11-relay-protocol.md` §4.2). Sender: Device. Reply:
/// no. Correlation: no. Mirrors `DeviceInfo` in
/// `crates/herdr-relay-proto/src/messages/session.rs:26-43`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
///
/// The Device MUST send this immediately on receiving `host_info`
/// (R-11-131).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import 'platform.dart';

part 'device_info.freezed.dart';
part 'device_info.g.dart';

@freezed
abstract class DeviceInfo with _$DeviceInfo {
  const factory DeviceInfo({
    /// Relay protocol version. `1`.
    required int protocol,

    /// UUIDv4 generated on first launch, stable across reconnects.
    @JsonKey(name: 'device_id') required String deviceId,

    /// Human-readable name. MUST NOT exceed 32 UTF-8 bytes (R-11-226).
    @JsonKey(name: 'device_name') required String deviceName,

    required Platform platform,

    /// Operating-system version string.
    @JsonKey(name: 'os_version') required String osVersion,

    /// Semantic version of the app build.
    @JsonKey(name: 'app_version') required String appVersion,
  }) = _DeviceInfo;

  factory DeviceInfo.fromJson(Map<String, dynamic> json) =>
      _$DeviceInfoFromJson(json);
}
