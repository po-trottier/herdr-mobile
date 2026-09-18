/// Application RTT reply. The envelope echoes the probe correlation ID.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'pong.freezed.dart';
part 'pong.g.dart';

@freezed
abstract class Pong with _$Pong {
  const factory Pong() = _Pong;

  factory Pong.fromJson(Map<String, dynamic> json) => _$PongFromJson(json);
}
