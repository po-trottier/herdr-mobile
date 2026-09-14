/// The Host's Herdr palette (R-03-131).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'theme_palette.freezed.dart';
part 'theme_palette.g.dart';

@freezed
abstract class ThemePalette with _$ThemePalette {
  const factory ThemePalette({
    required String name,
    required String accent,
    @JsonKey(name: 'panel_bg') required String panelBg,
    required String surface0,
    required String surface1,
    @JsonKey(name: 'surface_dim') required String surfaceDim,
    required String overlay0,
    required String overlay1,
    required String text,
    required String subtext0,
    required String mauve,
    required String green,
    required String yellow,
    required String red,
    required String blue,
    required String teal,
    required String peach,
  }) = _ThemePalette;

  factory ThemePalette.fromJson(Map<String, dynamic> json) =>
      _$ThemePaletteFromJson(json);
}
