/// The `working` status icon's rotation period, per `docs/32-design-language.md` R-32-601:
/// "The only continuous animation in the app is the `working` icon, which rotates once every
/// 1200 ms with `Curves.linear`, per `R-30-403`." This is not one of `app_motion.dart`'s
/// `AppMotion` four durations — R-32-600 fixes that catalogue at exactly four values for
/// perceived-motion transitions, and a continuous rotation period is a different kind of value,
/// for a different reason — owned here instead, mirroring `chrome_loading_delay.dart`'s own
/// sibling token, so no screen redeclares the literal (`docs/41-code-standards.md` R-41-111,
/// `docs/30-ux-spec.md` R-30-102).
library;

/// R-32-601's fixed 1200 ms rotation period.
class ChromeWorkingIconMotion {
  const ChromeWorkingIconMotion._();

  /// One full rotation of the `working` status icon.
  static const Duration rotationPeriod = Duration(milliseconds: 1200);
}
