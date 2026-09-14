/// The app bar live bar of `docs/32-design-language.md` section 7.3
/// (R-32-510's anatomy table): `color.status.ok` when live,
/// `color.status.warning` when the last event is older than 60 seconds,
/// `color.status.error` when the relay is lost. The live dot it replaced
/// was retired on 2026-09-09, per R-03-100: the indicator is the state bar.
library;

/// The one age the table fixes. A screen reads it here, never as a literal
/// (`test/widgets/theme/no_literals_test.dart`).
class AppLiveBar {
  const AppLiveBar._();

  /// Older than this since the last frame or event, the bar turns
  /// `color.status.warning`.
  static const Duration warningAge = Duration(seconds: 60);
}
