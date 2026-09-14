/// The one grace period every skeleton or spinner waits out before it paints, per
/// `docs/30-ux-spec.md` R-30-004: "A skeleton or a spinner MUST appear only after 150 ms of
/// waiting, so a fast response never flashes." This is a UX-spec timing threshold, not one of
/// `app_motion.dart`'s `AppMotion` durations: R-32-600 fixes that catalogue at exactly four
/// values (`instant`/`fast`/`base`/`slow`, 0/120/200/320 ms) for perceived-motion easing, and
/// none of them is 150 ms or means "wait before showing a loading state" — a different rule,
/// for a different reason, owned here instead so no screen redeclares the literal.
library;

/// R-30-004's fixed 150 ms threshold.
class ChromeLoadingDelay {
  const ChromeLoadingDelay._();

  /// The delay before a `Loading` state's skeleton or spinner may paint.
  static const Duration skeleton = Duration(milliseconds: 150);
}
