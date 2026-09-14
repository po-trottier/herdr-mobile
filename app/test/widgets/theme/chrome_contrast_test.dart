/// Proves `lib/services/contrast_assert.dart`'s static WCAG 2.2 contrast
/// assertion, per `docs/90-implementation-plan.md`'s `WP-12-c` checklist:
/// the assertion runs against the fixed Herdr scheme in both brightnesses
/// with zero failures, proving the fixed scheme is always legible.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/services/contrast_assert.dart';
import 'package:herdr_mobile/widgets/theme/chrome_scheme.dart';
import 'package:material_ui/material_ui.dart'
    show Brightness, Color, ColorScheme;

void main() {
  test('checkChromeContrast catches a synthetic failing pair', () {
    // Every ink equals every surface: the worst possible scheme, and a
    // ratio of 1.0 fails every one of the 33 pairs' floors.
    const Color flat = Color(0xFF808080);
    const ColorScheme failing = ColorScheme(
      brightness: Brightness.light,
      primary: flat,
      onPrimary: flat,
      secondary: flat,
      onSecondary: flat,
      error: flat,
      onError: flat,
      surface: flat,
      onSurface: flat,
    );

    final failures = checkChromeContrast(
      scheme: failing,
      brightness: Brightness.light,
    );

    expect(failures, isNotEmpty);
    expect(
      failures.length,
      33,
      reason: 'a flat scheme fails every one of the 33 pairs (R-33-045)',
    );
    expect(failures.map((f) => f.pairName), contains('onSurface/surface'));
  });

  test(
    'checkChromeContrast passes on the fixed Herdr scheme with headroom',
    () {
      for (final brightness in Brightness.values) {
        final ColorScheme scheme = ChromeScheme.fixed(brightness);
        final failures = checkChromeContrast(
          scheme: scheme,
          brightness: brightness,
        );
        expect(
          failures,
          isEmpty,
          reason: 'the fixed Herdr scheme in $brightness clears all 33 pairs',
        );
      }
    },
  );

  for (final brightness in Brightness.values) {
    test(
      'the fixed Herdr scheme has zero contrast failures in $brightness, proving it is always legible',
      () {
        final ColorScheme scheme = ChromeScheme.fixed(brightness);
        final failures = checkChromeContrast(
          scheme: scheme,
          brightness: brightness,
        );
        expect(
          failures,
          isEmpty,
          reason: 'the fixed Herdr scheme in $brightness clears all 33 pairs',
        );
      },
    );
  }
}
