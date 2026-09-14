/// The Host sends this palette when its Herdr theme changes (R-03-131).
/// The message has no reply and no correlation identifier.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import 'theme_palette.dart';

part 'host_theme.freezed.dart';
part 'host_theme.g.dart';

@freezed
abstract class HostTheme with _$HostTheme {
  const factory HostTheme({required ThemePalette theme}) = _HostTheme;

  factory HostTheme.fromJson(Map<String, dynamic> json) =>
      _$HostThemeFromJson(json);
}
