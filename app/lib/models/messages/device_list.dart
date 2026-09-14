/// `device_list` (`docs/11-relay-protocol.md` §4.19). Sender: Host. Reply:
/// no (reply to `device_list_request`). Correlation: yes. Mirrors
/// `DeviceList` in `crates/herdr-relay-proto/src/messages/device.rs:13-18`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import 'device_list_entry.dart';

part 'device_list.freezed.dart';
part 'device_list.g.dart';

@freezed
abstract class DeviceList with _$DeviceList {
  const factory DeviceList({required List<DeviceListEntry> devices}) =
      _DeviceList;

  factory DeviceList.fromJson(Map<String, dynamic> json) =>
      _$DeviceListFromJson(json);
}
