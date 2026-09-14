/// R-11-240, R-11-241: Device marks an agent pane seen without a reply.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'mark_seen.freezed.dart';
part 'mark_seen.g.dart';

@freezed
abstract class MarkSeen with _$MarkSeen {
  const factory MarkSeen({@JsonKey(name: 'pane_id') required String paneId}) =
      _MarkSeen;

  factory MarkSeen.fromJson(Map<String, dynamic> json) =>
      _$MarkSeenFromJson(json);
}
