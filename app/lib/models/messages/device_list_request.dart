/// `device_list_request` (`docs/11-relay-protocol.md` §4.18). Sender:
/// Device. Reply: `device_list`. Correlation: yes. The payload is `{}`.
/// Mirrors `DeviceListRequest` in
/// `crates/herdr-relay-proto/src/messages/device.rs:8-11`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'device_list_request.freezed.dart';
part 'device_list_request.g.dart';

@freezed
abstract class DeviceListRequest with _$DeviceListRequest {
  const factory DeviceListRequest() = _DeviceListRequest;

  factory DeviceListRequest.fromJson(Map<String, dynamic> json) =>
      _$DeviceListRequestFromJson(json);
}
