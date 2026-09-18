/// Application RTT probe. The envelope carries its correlation ID.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'ping.freezed.dart';
part 'ping.g.dart';

@freezed
abstract class Ping with _$Ping {
  const factory Ping() = _Ping;

  factory Ping.fromJson(Map<String, dynamic> json) => _$PingFromJson(json);
}
