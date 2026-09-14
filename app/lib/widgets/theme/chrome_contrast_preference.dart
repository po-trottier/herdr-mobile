/// The Increase Contrast starting level, per `docs/33-platform-chrome.md`
/// R-33-052.
library;

import 'package:cupertino_ui/cupertino_ui.dart' show BuildContext, MediaQuery;

/// R-33-052: the starting `contrastLevel` a generated Android scheme
/// hands to `lib/services/contrast_assert.dart`'s escalation. 1.0 under
/// Increase Contrast, per R-33-052; 0.0 otherwise.
class ChromeContrastPreference {
  const ChromeContrastPreference._();

  static double startingLevel({required bool increaseContrast}) =>
      increaseContrast ? 1.0 : 0.0;

  /// Reads Increase Contrast from `MediaQuery.highContrastOf`.
  static double of(BuildContext context) =>
      startingLevel(increaseContrast: MediaQuery.highContrastOf(context));
}
