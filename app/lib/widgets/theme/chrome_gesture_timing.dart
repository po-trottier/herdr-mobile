/// Gesture-recognition timings this app sets beside the Flutter SDK defaults.
///
/// The 400 ms long-press override R-30-301 once required is gone: the grid's
/// selection is the platform's own now (`SelectionArea` in
/// `app/lib/widgets/terminal_view_widget.dart`), so the SDK default
/// (`kLongPressTimeout`, 500 ms) applies, and this catalogue keeps only the
/// timing that is still the app's own. R-30-301's 300 ms double-tap and
/// triple-tap windows always matched Flutter's `kDoubleTapTimeout` and never
/// needed an entry here.
library;

/// The grid's selection edge-autoscroll cadence.
class ChromeGestureTiming {
  const ChromeGestureTiming._();

  /// The step period of the edge autoscroll while a selection drag holds near
  /// the grid edge: one row per step.
  static const Duration selectionAutoscrollStep = Duration(milliseconds: 50);
}
