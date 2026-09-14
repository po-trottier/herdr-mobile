/// Motion tokens from `docs/32-design-language.md` section 8. R-32-600
/// fixes the four durations and the four curves as the complete motion
/// set. `docs/30-ux-spec.md` R-30-101 fixes the Dart naming:
/// `motion.duration.fast` becomes `AppMotion.durationFast`.
///
/// R-32-605 forbids `Curves.bounceOut`, `Curves.elasticOut`,
/// `Curves.elasticIn`, `Curves.elasticInOut`, `Curves.easeOutBack` and
/// every other overshoot curve; this file declares none of them.
library;

import 'package:flutter/widgets.dart' show Curve, Curves, FlippedCurve;

/// The four durations, the four easing curves and the press scale.
/// R-32-606: under `MediaQuery.disableAnimationsOf(context)` a caller
/// substitutes every duration with zero, every curve with `Curves.linear`
/// and the press scale with 1.0; that substitution is the caller's
/// responsibility, not a member of this token set.
class AppMotion {
  const AppMotion._();

  /// `motion.duration.instant`. The absence of animation: a status badge
  /// change, a terminal grid repaint.
  static const Duration durationInstant = Duration.zero;

  /// `motion.duration.fast`. Press feedback: the pressed fill and the
  /// press scale, on the way in only. Release is `durationInstant`, per
  /// R-32-609.
  static const Duration durationFast = Duration(milliseconds: 120);

  /// `motion.duration.base`. A screen transition, a bottom sheet, a
  /// dialog.
  static const Duration durationBase = Duration(milliseconds: 200);

  /// `motion.duration.slow`. A hold, not a transition: how long a
  /// transient readout stays on screen (`docs/30-ux-spec.md` R-30-302)
  /// and the period of the pairing frame fade. R-32-604 (amended
  /// 2026-09-08) forbids it as the duration of a UI transition, because
  /// a transition MUST finish under 300 ms.
  static const Duration durationSlow = Duration(milliseconds: 320);

  /// `motion.scale.press`. Every pressable control scales to this on
  /// pointer-down, over [durationFast] with [curveEnter], and snaps back
  /// to 1.0 at [durationInstant] on release, per R-32-609. A transform
  /// only: it never moves layout.
  static const double scalePress = 0.97;

  /// `motion.curve.enter`.
  static const Curve curveEnter = Curves.easeOutExpo;

  /// `motion.curve.exit`: `Curves.easeOutQuart` in Flutter's **reverse
  /// space**, per R-32-609 (amended 2026-09-08). Hand it to a
  /// `reverseCurve` (a route, a sheet, a dialog) as it is. Flutter
  /// evaluates a reverse curve on the parent's `t` while `t` runs 1 to 0,
  /// so on screen the exit starts fast and settles: an ease-out, with a
  /// shorter tail than [curveEnter], so a leaving surface does not linger
  /// almost gone. Numerically this equals `Curves.easeInQuart`, which is
  /// what an ease-out looks like read backwards. A forward-running
  /// animation of a leaving element, one that drives `t` 0 to 1 while the
  /// element goes, takes `AppMotion.curveExit.flipped` instead.
  static const Curve curveExit = FlippedCurve(Curves.easeOutQuart);

  /// `motion.curve.move`.
  static const Curve curveMove = Curves.easeInOutQuart;

  /// `motion.curve.emphasis`.
  static const Curve curveEmphasis = Curves.easeInOutCubicEmphasized;

  /// `motion.pulse`, per R-32-608: opacity [pulseOpacityFloor] to 1.0 and
  /// back over [pulseDuration] on [pulseCurve], repeating. The `working`
  /// status dot and the live connection dot use it. Under reduce motion
  /// the dot is static at opacity 1.0.
  static const Duration pulseDuration = Duration(milliseconds: 2200);
  static const Curve pulseCurve = Curves.easeInOut;
  static const double pulseOpacityFloor = 0.25;
}
