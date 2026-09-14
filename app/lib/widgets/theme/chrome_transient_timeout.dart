/// A transient that must not time out for a screen reader, per
/// `docs/30-ux-spec.md` R-30-743.
library;

import 'package:cupertino_ui/cupertino_ui.dart' show BuildContext, MediaQuery;

/// R-30-743: a transient carrying information the person must read MUST
/// NOT time out while a screen reader is active, and keeps its normal
/// timing when it is off. `accessibleNavigation` is Flutter's own
/// screen-reader signal, true when TalkBack or VoiceOver is active.
class ChromeTransientTimeout {
  const ChromeTransientTimeout._();

  /// `null` means no timeout. Returns [normal] unless [accessibleNavigation]
  /// is true.
  static Duration? resolve({
    required bool accessibleNavigation,
    required Duration normal,
  }) => accessibleNavigation ? null : normal;

  /// Reads [accessibleNavigation] from the ambient [MediaQuery].
  static Duration? of(BuildContext context, Duration normal) => resolve(
    accessibleNavigation: MediaQuery.of(context).accessibleNavigation,
    normal: normal,
  );
}
