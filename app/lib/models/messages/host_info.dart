/// `host_info` (`docs/11-relay-protocol.md` §4.1). Sender: Host. Reply:
/// `device_info`. Correlation: no. Mirrors `HostInfo` in
/// `crates/herdr-relay-proto/src/messages/session.rs:6-24`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
///
/// The Host MUST send this as the first application frame after the Noise
/// transport reaches transport mode (R-11-130).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import 'theme_palette.dart';
part 'host_info.freezed.dart';
part 'host_info.g.dart';

@freezed
abstract class HostInfo with _$HostInfo {
  const factory HostInfo({
    /// Relay protocol version. `1`.
    required int protocol,

    /// UUIDv4, stable for the life of the Host install.
    @JsonKey(name: 'host_id') required String hostId,

    /// Host machine name for display. At most 64 UTF-8 bytes.
    @JsonKey(name: 'host_name') required String hostName,

    /// Herdr server version from `ping`.
    @JsonKey(name: 'herdr_version') required String herdrVersion,

    /// Herdr socket protocol integer from `ping`. MUST be `22` (R-10-012).
    @JsonKey(name: 'herdr_protocol') required int herdrProtocol,

    /// `true` when this Device static key was already paired before this
    /// session.
    required bool paired,

    /// R-03-131: absent when the Host has no resolved theme.
    @JsonKey(includeIfNull: false) ThemePalette? theme,
  }) = _HostInfo;

  factory HostInfo.fromJson(Map<String, dynamic> json) =>
      _$HostInfoFromJson(json);
}
