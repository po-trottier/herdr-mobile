/// Spacing-scale tokens from `docs/32-design-language.md` section 5.1.
/// R-32-300 fixes the eleven-step scale as the complete set: a value
/// outside it, and a value reached by adding two steps together, are both
/// forbidden, per R-32-302. `docs/30-ux-spec.md` R-30-101 fixes the Dart
/// naming.
library;

/// The 4-unit spacing scale, 8 as the working rhythm.
class AppSpace {
  const AppSpace._();

  /// `space.0`.
  static const double space0 = 0;

  /// `space.1`. The minimum gap between two adjacent touch targets, per
  /// R-32-362.
  static const double space1 = 4;

  /// `space.2`.
  static const double space2 = 8;

  /// `space.3`. Horizontal padding inside a bezelled control.
  static const double space3 = 12;

  /// `space.4`. The screen edge inset, per R-30-230.
  static const double space4 = 16;

  /// `space.5`.
  static const double space5 = 20;

  /// `space.6`. The gap between two row groups, per R-30-231.
  static const double space6 = 24;

  /// `space.8`.
  static const double space8 = 32;

  /// `space.10`.
  static const double space10 = 40;

  /// `space.12`.
  static const double space12 = 48;

  /// `space.16`.
  static const double space16 = 64;
}
