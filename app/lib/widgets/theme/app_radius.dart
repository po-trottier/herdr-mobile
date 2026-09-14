/// Corner-radius tokens from `docs/32-design-language.md` section 5.2.
/// R-32-310 fixes `radius.none` as the terminal grid's only radius.
/// `docs/30-ux-spec.md` R-30-101 fixes the Dart naming: `radius.sm`
/// becomes `AppRadius.sm`.
library;

/// The five corner radii. The set is closed: a widget MUST NOT invent a
/// sixth, per `docs/32-design-language.md` R-32-350's sibling rule for
/// size.
class AppRadius {
  const AppRadius._();

  /// `radius.none`. The terminal grid, a divider, a strip, a banner. A
  /// rounded terminal clips a real cell, per R-32-310.
  static const double none = 0;

  /// `radius.sm`. A button, key cap, chip, segment, focus ring, text field.
  static const double sm = 2;

  /// `radius.md`. A card, dialog, raw-error block, sheet body.
  static const double md = 4;

  /// `radius.lg`. The top two corners of a bottom sheet.
  static const double lg = 6;

  /// `radius.full`. A dot, a pill, a grab handle, a switch track, a badge count.
  static const double full = 999;
}

/// Border-width tokens from `docs/32-design-language.md` section 5.4.
class AppBorder {
  const AppBorder._();

  /// `border.hairline`. 1 px, unchanged.
  static const double hairline = 1;

  /// `border.accent`. 2 px in `color.accent.primary`: the top edge of a
  /// featured card (welcome steps card, empty-state card) and the selected
  /// segment underline.
  static const double accent = 2;

  /// `border.attention`. 3 px in the row's `color.status.*`: the leading
  /// bar of a row that needs attention, of `treat.error` in a strip and of
  /// `treat.destructive`, and, since 2026-09-09 (R-03-100), the state bar
  /// of `status_bar.dart`. Three callers earn the token its own name here.
  static const double attention = 3;
}
