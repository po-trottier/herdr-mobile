/// The chrome `ColorScheme` builder. `docs/33-platform-chrome.md`
/// R-33-008 owns how a token resolves on a platform; this file owns only
/// the role-to-token map of `docs/32-design-language.md` section 6.
/// Both platforms use the same fixed `ColorScheme`.
library;

import 'package:flutter/widgets.dart' show Brightness, Color;
import 'package:material_ui/material_ui.dart' show ColorScheme;

import 'app_color.dart';
import 'chrome_scheme_source.dart';

/// Builds the one chrome [ColorScheme] the application root uses, per
/// `docs/32-design-language.md` section 6. `app/lib/app.dart` is the only
/// caller and the only place in the app that builds one.
class ChromeScheme {
  const ChromeScheme._();

  /// The fixed Herdr chrome scheme, mapped from [AppColor] tokens only.
  /// This file introduces no hex value. Both platforms use this scheme.
  static ColorScheme fixed(Brightness brightness) {
    final AppColor c = AppColor.resolve(brightness);
    return ColorScheme(
      brightness: brightness,
      surface: c.bgBase,
      surfaceContainerLowest: c.bgBase,
      surfaceContainerLow: c.bgRaised,
      surfaceContainer: c.bgRaised,
      surfaceContainerHigh: c.bgHigh,
      surfaceContainerHighest: c.bgHigh,
      onSurface: c.fgPrimary,
      onSurfaceVariant: c.fgSecondary,
      primary: c.accentPrimary,
      secondary: c.accentPrimary,
      tertiary: c.accentPrimary,
      onPrimary: c.fgOnAccent,
      onSecondary: c.fgOnAccent,
      onTertiary: c.fgOnAccent,
      primaryContainer: c.bgHigh,
      secondaryContainer: c.bgHigh,
      tertiaryContainer: c.bgHigh,
      onPrimaryContainer: c.fgPrimary,
      onSecondaryContainer: c.fgPrimary,
      onTertiaryContainer: c.fgPrimary,
      outline: c.borderStrong,
      outlineVariant: c.borderSubtle,
      error: c.statusError,
      onError: c.fgOnAccent,
      errorContainer: c.bgHigh,
      onErrorContainer: c.statusError,
      shadow: c.shadow,
      scrim: c.shadow,
      inverseSurface: c.fgPrimary,
      onInverseSurface: c.bgBase,
      inversePrimary: c.accentText,
      surfaceTint: const Color(
        0x00000000,
      ), // Colors.transparent - no tint overlay anywhere
    );
  }

  /// Resolves the chrome scheme for the given brightness. Both platforms
  /// use the fixed Herdr palette.
  static ({ColorScheme colorScheme, ChromeSchemeSource source}) resolve(
    Brightness brightness,
  ) => (colorScheme: fixed(brightness), source: ChromeSchemeSource.fixed);
}
