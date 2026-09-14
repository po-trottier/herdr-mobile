/// Reduce Transparency and the opaque-variant decision, per
/// `docs/33-platform-chrome.md` R-33-051, R-33-052 and R-33-068.
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart' show MethodChannel;

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

const MethodChannel _reduceTransparencyChannel = MethodChannel(
  'herdr_mobile/chrome_reduce_transparency',
);

/// Reduce Transparency (iOS only, R-33-051) and the opaque-variant
/// decision that follows from it and from Increase Contrast (R-33-068).
class ChromeTransparency {
  const ChromeTransparency._();

  /// `MediaQueryData` exposes no reduce-transparency field, so this reads
  /// `UIAccessibility.isReduceTransparencyEnabled` over a platform
  /// channel, per R-33-051. Android has no equivalent setting and needs
  /// none, because Android chrome is opaque, so this returns `false`
  /// there without a channel call. The native iOS handler for this
  /// channel is a `ios/Runner` file, which carries no owner on this
  /// package's `Paths.` line; a later platform-integration package
  /// registers it.
  static Future<bool> isReduceTransparencyEnabled() async {
    if (!_isIos) {
      return false;
    }
    final bool? enabled = await _reduceTransparencyChannel.invokeMethod<bool>(
      'isReduceTransparencyEnabled',
    );
    return enabled ?? false;
  }

  /// R-33-068: the opaque variant is reachable in exactly two cases, and
  /// neither is a fallback or a version tier: Reduce Transparency
  /// (R-33-051) or Increase Contrast (R-33-052).
  static bool shouldUseOpaqueVariant({
    required bool reduceTransparency,
    required bool increaseContrast,
  }) => reduceTransparency || increaseContrast;
}
