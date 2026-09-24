/// The one gesture-recognition timing this app overrides from a Flutter SDK default, per
/// `docs/30-ux-spec.md` R-30-301: "A long press MUST be 400 ms." Flutter's own
/// `LongPressGestureRecognizer` defaults to `kLongPressTimeout` (500 ms); this is not one of
/// `app_motion.dart`'s `AppMotion` perceived-motion durations either — R-32-600 fixes that
/// catalogue at exactly four values for animation easing, and a gesture-recognition threshold is
/// a different rule, for a different reason, owned here instead so no screen redeclares the
/// literal.
///
/// R-30-301 also fixes a 300 ms double-tap window and a 300 ms triple-tap window, but Flutter's
/// own defaults (`kDoubleTapTimeout`) already equal 300 ms, so neither needs an override or a
/// token here.
library;

/// R-30-301's 400 ms long-press threshold.
class ChromeGestureTiming {
  const ChromeGestureTiming._();

  /// The duration a press MUST be held before it is recognised as a long press.
  static const Duration longPress = Duration(milliseconds: 400);

  /// The step period of the edge autoscroll while a selection drag holds near the grid edge:
  /// one row per step.
  static const Duration selectionAutoscrollStep = Duration(milliseconds: 50);
}
