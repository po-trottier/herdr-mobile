/// One paired-device entry inside `device_list.devices`
/// (`docs/11-relay-protocol.md` §4.19). `fingerprint` is computed from the
/// stored `static_public_key`; the raw key MUST NOT appear in any message
/// (R-11-062). Mirrors `DeviceListEntry` in
/// `crates/herdr-relay-proto/src/messages/device.rs:20-31`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import 'platform.dart';

part 'device_list_entry.freezed.dart';
part 'device_list_entry.g.dart';

@freezed
abstract class DeviceListEntry with _$DeviceListEntry {
  const factory DeviceListEntry({
    required String id,
    required String name,
    @JsonKey(name: 'paired_at') required String pairedAt,
    @JsonKey(name: 'last_seen') required String lastSeen,
    required bool connected,
    required Platform platform,
    required String fingerprint,
  }) = _DeviceListEntry;

  factory DeviceListEntry.fromJson(Map<String, dynamic> json) =>
      _$DeviceListEntryFromJson(json);
}
