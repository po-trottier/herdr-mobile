/// Size tokens from `docs/32-design-language.md` section 5.5. R-32-350
/// fixes the table as the complete size set: a screen MUST NOT invent a
/// height, a width or an icon size. `docs/30-ux-spec.md` R-30-101 fixes
/// the Dart naming: `size.icon.sm` becomes `AppSize.iconSm`.
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;

/// The complete size set: every touch target, row height, icon size and
/// control dimension the app uses.
class AppSize {
  const AppSize._();

  /// `size.target.min`. Every interactive element, per R-32-360.
  static const double targetMin = 48;

  /// `size.appbar`: Android 56; iOS 44, the height `CupertinoNavigationBar`
  /// draws itself (R-33-076). Before the top safe-area inset a caller adds.
  /// An app-built bar row on iOS takes the same 44, so it matches the native
  /// bar on every other screen.
  static double get appBar =>
      defaultTargetPlatform == TargetPlatform.iOS ? appBarIos : appBarAndroid;

  /// The Android value of `size.appbar`.
  static const double appBarAndroid = 56;

  /// The iOS value of `size.appbar`.
  static const double appBarIos = 44;

  /// `size.bar.merged`. The terminal's landscape bar, where the app bar
  /// row and the status strip merge into one, on both platforms: the mode
  /// control of R-32-543 is a `size.target.min` row and the row range and
  /// the revision sit beside it, so the bar is 56 high on iOS as well as
  /// Android, never the 44 iOS `size.appbar` (added 2026-09-08).
  static const double barMerged = 56;

  /// `size.bottomnav`. The three bottom destinations, before the bottom
  /// safe-area inset a caller adds.
  static const double bottomNav = 56;

  /// `size.statusstrip`. Minimum height for terminal metadata and its view control.
  static const double statusStrip = targetMin;

  /// `size.keyrow`. One row of key caps, before the `space.2` the toolbar
  /// adds above, below and between rows (R-31-09-21).
  static const double keyRow = 48;

  /// `size.header`. An upper-case group header row.
  static const double header = 32;

  /// `size.row.one_line`. A settings row, a sheet action row, a toggle
  /// row, a tree row.
  static const double rowOneLine = 52;

  /// `size.row.two_line`. A host row, an agent row, a paired-phone row,
  /// a settings row with a value line.
  static const double rowTwoLine = 72;

  // `size.button.primary` and `size.button.text` have no constant: the
  // platform button keeps its own height, radius and inset, per the
  // R-03-059 addendum (2026-09-09); docs/32 section 5.5 records them as
  // `platform`.

  /// `size.button.create`. The create control of the `Agents` screen, the
  /// Material floating action button on both platforms: 56 by 56, the
  /// component's own box (R-32-588, restored 2026-09-10 per the corrected
  /// R-03-109). An overflowing list adds this plus `space.4` at its end, so
  /// its last row scrolls clear of the button.
  static const double buttonCreate = 56;

  /// `size.field`. A text field, a word field, the composer input row.
  static const double field = 48;

  /// `size.input.ios`. The single-line Messages field height.
  static const double inputIos = 36;

  /// `size.keycap` width. One key cap, one arrow segment, one symbol key,
  /// one navigation key. A minimum: `key_row.dart` widens every cap to its
  /// column module, per R-31-09-21.
  static const double keycapWidth = 48;

  /// `size.keycap` height. The cap is its own touch target, so it is
  /// `size.target.min` high (decided 2026-09-03 by the product owner).
  static const double keycapHeight = 48;

  /// `size.pill`. The jump-to-bottom pill.
  static const double pill = 36;

  /// `size.grab` width. The bottom sheet grab handle.
  static const double grabWidth = 36;

  /// `size.grab` height.
  static const double grabHeight = 4;

  /// `size.icon.sm`. A status icon, a treatment icon, an inline icon, a
  /// badge icon.
  static const double iconSm = 16;

  /// `size.icon.md`. A control icon, a chevron, an expander, a
  /// destructive treatment icon.
  static const double iconMd = 20;

  /// `size.icon.lg`. An app bar icon, a bottom-navigation icon.
  static const double iconLg = 24;

  /// `size.icon.hero`. The biometric glyph on `/lock`, the only hero
  /// icon in the app.
  static const double iconHero = 96;

  /// `size.spinner`. The in-place spinner that replaces a label while an
  /// action is in flight.
  static const double spinner = 20;

  /// `size.skeleton`. One skeleton bar height, at `radius.sm` in
  /// `color.bg.raised`.
  static const double skeleton = 12;

  /// `size.viewfinder.corner`. The length of one QR viewfinder corner
  /// mark.
  static const double viewfinderCorner = 24;
}
