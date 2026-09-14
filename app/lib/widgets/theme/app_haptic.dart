/// Haptic tokens from `docs/30-ux-spec.md`'s Haptics table (`R-30-280`,
/// `R-30-285`). `docs/30-ux-spec.md` R-30-101 fixes the Dart naming:
/// `haptic.select` becomes `AppHaptic.select`.
///
/// `successNotification`, `warningNotification` and `errorNotification`
/// are real `HapticFeedback` methods on the Flutter `stable` branch, per
/// R-30-280; this file calls them directly rather than reimplementing
/// notification-style haptics, per `docs/41-code-standards.md` R-41-042
/// rung 2.
///
/// R-30-281 and R-30-282: silencing every token under a "Haptics off"
/// setting, and never firing one in place of a visible change, are a
/// caller's responsibility. This file exposes the five raw calls only,
/// the same division `app_motion.dart`'s `AppMotion` draws for
/// `disableAnimationsOf` substitution.
library;

import 'package:flutter/services.dart' show HapticFeedback;

/// The five haptic tokens.
class AppHaptic {
  const AppHaptic._();

  /// `haptic.select`. A key row press, a list selection change, a
  /// stepper step.
  static Future<void> select() => HapticFeedback.selectionClick();

  /// `haptic.confirm`. Input accepted, a toggle flipped, a copy done.
  static Future<void> confirm() => HapticFeedback.lightImpact();

  /// `haptic.commit`. A pairing succeeded, a pane action applied, a
  /// prompt sent. MUST use `successNotification`, per R-30-280.
  static Future<void> commit() => HapticFeedback.successNotification();

  /// `haptic.alert`. An agent reached `blocked` while the app is open.
  /// MUST stay `heavyImpact` and MUST NOT become `warningNotification`,
  /// per R-30-285: it is the one haptic that fires for an event the
  /// person did not cause, per R-30-283, so it MUST feel unlike the two
  /// notification haptics that answer a press.
  static Future<void> alert() => HapticFeedback.heavyImpact();

  /// `haptic.error`. A wrong word, a failed send, a rejected biometric.
  /// MUST use `errorNotification`, per R-30-280.
  static Future<void> error() => HapticFeedback.errorNotification();
}
