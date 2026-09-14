/// The static WCAG 2.2 contrast proof for the fixed Herdr chrome
/// `ColorScheme`, per `docs/32-design-language.md` section 6. The fixed
/// scheme is built directly from `AppColor` tokens (which are byte-for-byte
/// the Herdr brand values), so this file verifies that the role-to-token
/// mapping in `chrome_scheme.dart` produces a `ColorScheme` that clears
/// every documented floor. `test/widgets/theme/contrast_test.dart` proves
/// the token values themselves; this file proves the Material role mapping.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart' show Brightness, Color;
import 'package:material_ui/material_ui.dart' show ColorScheme;

import '../widgets/theme/app_color.dart';

double _linearize(double channel) => channel <= 0.04045
    ? channel / 12.92
    : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();

double _relativeLuminance(Color c) =>
    0.2126 * _linearize(c.r) +
    0.7152 * _linearize(c.g) +
    0.0722 * _linearize(c.b);

/// The real WCAG 2.2 contrast ratio between two colours, from sRGB
/// relative luminance.
double contrastRatio(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

/// One failing pair from [checkChromeContrast].
class ContrastFailure {
  const ContrastFailure({
    required this.pairName,
    required this.ratio,
    required this.floor,
  });

  final String pairName;
  final double ratio;
  final double floor;

  @override
  String toString() =>
      '$pairName: ratio ${ratio.toStringAsFixed(2)} < floor $floor';
}

/// Runs the contrast pairs against [scheme] in one [brightness].
/// These are the pairs from `docs/32-design-language.md` section 6
/// (the Material role mapping table) at their documented floors:
/// 4.5 for text-on-surface pairs, 3.0 for non-text (outline, state on surface).
List<ContrastFailure> checkChromeContrast({
  required ColorScheme scheme,
  required Brightness brightness,
}) {
  final AppColor tokens = AppColor.resolve(brightness);
  final List<ContrastFailure> failures = <ContrastFailure>[];

  void check(String name, Color a, Color b, double floor) {
    final ratio = contrastRatio(a, b);
    if (ratio < floor) {
      failures.add(ContrastFailure(pairName: name, ratio: ratio, floor: floor));
    }
  }

  // Class A: text on surface (4.5 floor), last three at 3.0
  check('onSurface/surface', scheme.onSurface, scheme.surface, 4.5);
  check(
    'onSurface/surfaceContainerLowest',
    scheme.onSurface,
    scheme.surfaceContainerLowest,
    4.5,
  );
  check(
    'onSurface/surfaceContainerLow',
    scheme.onSurface,
    scheme.surfaceContainerLow,
    4.5,
  );
  check(
    'onSurface/surfaceContainer',
    scheme.onSurface,
    scheme.surfaceContainer,
    4.5,
  );
  check(
    'onSurface/surfaceContainerHigh',
    scheme.onSurface,
    scheme.surfaceContainerHigh,
    4.5,
  );
  check(
    'onSurface/surfaceContainerHighest',
    scheme.onSurface,
    scheme.surfaceContainerHighest,
    4.5,
  );
  check('onPrimary/primary', scheme.onPrimary, scheme.primary, 4.5);
  check('onSecondary/secondary', scheme.onSecondary, scheme.secondary, 4.5);
  check('onTertiary/tertiary', scheme.onTertiary, scheme.tertiary, 4.5);
  check(
    'onPrimaryContainer/primaryContainer',
    scheme.onPrimaryContainer,
    scheme.primaryContainer,
    3.0,
  );
  check(
    'onSecondaryContainer/secondaryContainer',
    scheme.onSecondaryContainer,
    scheme.secondaryContainer,
    3.0,
  );
  check(
    'onTertiaryContainer/tertiaryContainer',
    scheme.onTertiaryContainer,
    scheme.tertiaryContainer,
    3.0,
  );

  // Class B: semantic state tokens on surface and surfaceContainer (3.0 floor)
  check('statusWorking/surface', tokens.statusWorking, scheme.surface, 3.0);
  check(
    'statusWorking/surfaceContainer',
    tokens.statusWorking,
    scheme.surfaceContainer,
    3.0,
  );
  check('statusBlocked/surface', tokens.statusBlocked, scheme.surface, 3.0);
  check(
    'statusBlocked/surfaceContainer',
    tokens.statusBlocked,
    scheme.surfaceContainer,
    3.0,
  );
  check('statusIdle/surface', tokens.statusIdle, scheme.surface, 3.0);
  check(
    'statusIdle/surfaceContainer',
    tokens.statusIdle,
    scheme.surfaceContainer,
    3.0,
  );
  check('statusDone/surface', tokens.statusDone, scheme.surface, 3.0);
  check(
    'statusDone/surfaceContainer',
    tokens.statusDone,
    scheme.surfaceContainer,
    3.0,
  );
  check('statusUnknown/surface', tokens.statusUnknown, scheme.surface, 3.0);
  check(
    'statusUnknown/surfaceContainer',
    tokens.statusUnknown,
    scheme.surfaceContainer,
    3.0,
  );
  check('statusError/surface', tokens.statusError, scheme.surface, 3.0);
  check(
    'statusError/surfaceContainer',
    tokens.statusError,
    scheme.surfaceContainer,
    3.0,
  );
  check('statusWarning/surface', tokens.statusWarning, scheme.surface, 3.0);
  check(
    'statusWarning/surfaceContainer',
    tokens.statusWarning,
    scheme.surfaceContainer,
    3.0,
  );
  check('statusOk/surface', tokens.statusOk, scheme.surface, 3.0);
  check(
    'statusOk/surfaceContainer',
    tokens.statusOk,
    scheme.surfaceContainer,
    3.0,
  );
  check('statusInfo/surface', tokens.statusInfo, scheme.surface, 3.0);
  check(
    'statusInfo/surfaceContainer',
    tokens.statusInfo,
    scheme.surfaceContainer,
    3.0,
  );

  // Outline on surface (3.0 floor). `outlineVariant` (`border.subtle`) is
  // contrast-exempt, per docs/32-design-language.md R-32-114 and the
  // section 3.6 table ("exempt, decorative"), so it has no check here.
  check('outline/surface', scheme.outline, scheme.surface, 3.0);
  check('error/surface', scheme.error, scheme.surface, 3.0);
  check('onError/error', scheme.onError, scheme.error, 4.5);

  return failures;
}
