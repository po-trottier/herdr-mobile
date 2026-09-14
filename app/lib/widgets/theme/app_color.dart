/// Colour tokens from `docs/32-design-language.md` section 3. Two sources,
/// per R-32-100/R-32-103: the app-chrome surfaces, borders, text and accent
/// (R-32-110, R-32-120) come from the Herdr brand grounds (Ink/Paper), and
/// the semantic state colours (R-32-130) and the terminal-slot palette
/// (R-32-140) come from Selenized, unchanged, and are unaffected by the
/// chrome source. `docs/30-ux-spec.md` R-30-101 fixes the Dart naming:
/// `color.bg.base` becomes `AppColor.bgBase`.
library;

import 'package:flutter/widgets.dart'
    show Brightness, BuildContext, Color, MediaQuery;

/// One instance per [Brightness]. Both themes are first class per
/// R-32-012: neither is derived from the other at run time.
enum AppColor {
  /// The dark theme: Herdr Ink chrome, Selenized terminal and semantic state.
  dark(Brightness.dark),

  /// The light theme: Herdr Paper chrome, Selenized terminal and semantic state.
  light(Brightness.light);

  const AppColor(this.brightness);

  /// Resolves the token set for the given platform brightness.
  static AppColor resolve(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// Resolves the token set from the ambient platform brightness, per
  /// R-32-013.
  static AppColor of(BuildContext context) =>
      resolve(MediaQuery.platformBrightnessOf(context));

  /// The brightness this instance resolves tokens for.
  final Brightness brightness;

  bool get _isDark => brightness == Brightness.dark;

  // --- 3.2 App chrome: surfaces and borders (R-32-110), Herdr brand grounds ---

  /// The page background. The terminal keeps its own `termBg`, per
  /// R-32-104: the two no longer share a value in either theme.
  /// Herdr Ink (dark): `--bg` #17171a; Herdr Paper (light): `--bg` #efece5.
  Color get bgBase =>
      _isDark ? const Color(0xFF17171A) : const Color(0xFFEFECE5);

  /// A strip, a banner, a sheet, a dialog, a key row, a snackbar.
  /// Herdr Ink (dark): `--panel` #1e1e22; Herdr Paper (light): `--panel` #e7e3da.
  Color get bgRaised =>
      _isDark ? const Color(0xFF1E1E22) : const Color(0xFFE7E3DA);

  /// Fill only: a key cap, a text field, the jump pill, a switch track that
  /// is off. MUST carry a `borderStrong` boundary, per R-32-112.
  /// Herdr Ink (dark): `--mass` #26262b; Herdr Paper (light): `--mass` #ddd8cc.
  Color get bgHigh =>
      _isDark ? const Color(0xFF26262B) : const Color(0xFFDDD8CC);

  /// The ground grid lines. Herdr Ink (dark): `--grid` #202024; Herdr Paper (light): `--grid` #e4e0d6.
  /// Decorative, contrast-exempt.
  Color get bgGrid =>
      _isDark ? const Color(0xFF202024) : const Color(0xFFE4E0D6);

  /// The boundary of any control whose shape is its only identifier.
  /// Clears the 3.0 floor on all three surfaces, per R-32-113.
  /// Herdr Ink (dark): derived from `--faint2`/`--dim` scale #908f96; Herdr Paper (light): #6f6b5c.
  Color get borderStrong =>
      _isDark ? const Color(0xFF908F96) : const Color(0xFF6F6B5C);

  /// A decorative divider only, per R-32-114.
  /// Herdr Ink (dark): `--line2` #35353d; Herdr Paper (light): #cbc5b6.
  Color get borderSubtle =>
      _isDark ? const Color(0xFF35353D) : const Color(0xFFCBC5B6);

  /// The shadow colour of `elev.2` and `elev.3`. Selenized black `bg_0`,
  /// one of the two values R-32-101 keeps unchanged: it still clears 4.5
  /// against the new `accentPrimary` fill. Fixed in both themes and never
  /// used as a contrast pair, per R-32-321.
  Color get shadow => const Color(0xFF181818);

  // --- 3.3 App chrome: text and accent (R-32-120), Herdr brand spot ---

  /// The primary ink, permitted on all three surfaces.
  /// Herdr Ink (dark): `--ink` #eae8ee; Herdr Paper (light): #15140f.
  Color get fgPrimary =>
      _isDark ? const Color(0xFFEAE8EE) : const Color(0xFF15140F);

  /// The secondary ink, permitted on all three surfaces, per R-32-122:
  /// clears `bgHigh` too.
  /// Herdr Ink (dark): `--faint`/`--dim` #b0afb6; Herdr Paper (light): #55534a.
  Color get fgSecondary =>
      _isDark ? const Color(0xFFB0AFB6) : const Color(0xFF55534A);

  /// A disabled control and a placeholder only, per R-32-123.
  /// Herdr Ink (dark): `--faint2` #908f96; Herdr Paper (light): #928e79.
  Color get fgDisabled =>
      _isDark ? const Color(0xFF908F96) : const Color(0xFF928E79);

  /// Accent ink; clears 4.5 on all three surfaces in both themes, per R-32-124.
  /// Herdr Ink (dark): `--spot` #cba6f7; Herdr Paper (light): darkened `--spot` #7028d8.
  /// Paper darkens because #8839ef measures ~4.2 on `bg.raised` and ~3.8 on `bg.high`.
  Color get accentText =>
      _isDark ? const Color(0xFFCBA6F7) : const Color(0xFF7028D8);

  /// A fill, never an ink, per R-32-125. Chrome's one accent: the Herdr `--spot`.
  /// Herdr Ink (dark): #cba6f7; Herdr Paper (light): #8839ef.
  Color get accentPrimary =>
      _isDark ? const Color(0xFFCBA6F7) : const Color(0xFF8839EF);

  /// Accent at 10% alpha for selected-row wash, pressed ghost fill, chip fill.
  /// Decorative, contrast-exempt.
  Color get accentSoft => accentPrimary.withValues(alpha: 0.10);

  /// The label on `accentPrimary` only. Herdr Ink (dark): `--spot-ink` #17171a; Herdr Paper (light): #ffffff.
  Color get fgOnAccent =>
      _isDark ? const Color(0xFF17171A) : const Color(0xFFFFFFFF);

  // --- 3.4 Semantic state colours (R-32-130) ---
  //
  // A status hue MUST NOT carry text, per R-32-131; use `treatments.dart`.

  /// The `idle` state and a success. Herdr brand green.
  /// Ink: #52c97a; Paper: darkened #268a46.
  Color get statusIdle =>
      _isDark ? const Color(0xFF52C97A) : const Color(0xFF268A46);

  /// The `working` state and a neutral note. Herdr brand yellow.
  /// Ink: #e6b84a; Paper: darkened #9a6f08 (clears 3.0 on all three surfaces).
  Color get statusWorking =>
      _isDark ? const Color(0xFFE6B84A) : const Color(0xFF9A6F08);

  /// The `blocked` state and a failure. Herdr brand red.
  /// Ink: #e05a5a; Paper: #c73e3e.
  Color get statusBlocked =>
      _isDark ? const Color(0xFFE05A5A) : const Color(0xFFC73E3E);

  /// The `done` state. Herdr brand teal.
  /// Ink: #94e2d5; Paper: darkened #1f8078.
  Color get statusDone =>
      _isDark ? const Color(0xFF94E2D5) : const Color(0xFF1F8078);

  /// The `unknown` agent state. Neutral.
  /// Ink: #908f96; Paper: #6f6b5c.
  Color get statusUnknown =>
      _isDark ? const Color(0xFF908F96) : const Color(0xFF6F6B5C);

  /// A failure. Shares blocked's hue on purpose, per R-32-130.
  Color get statusError =>
      _isDark ? const Color(0xFFE05A5A) : const Color(0xFFC73E3E);

  /// A warning. Shares working's hue on purpose, per R-32-130.
  Color get statusWarning =>
      _isDark ? const Color(0xFFE6B84A) : const Color(0xFF9A6F08);

  /// A success. Shares idle's hue on purpose, per R-32-130.
  Color get statusOk =>
      _isDark ? const Color(0xFF52C97A) : const Color(0xFF268A46);

  /// A neutral note. The spot; a note, never text.
  /// Ink: #cba6f7; Paper: #8839ef.
  Color get statusInfo =>
      _isDark ? const Color(0xFFCBA6F7) : const Color(0xFF8839EF);

  // --- 3.5 The terminal palette (R-32-140) ---
  //
  // These 22 values MUST be reached only through `color.term.*`, never
  // through the chrome tokens above, even where the hex values agree
  // today, per R-32-584.

  /// The terminal background.
  Color get termBg =>
      _isDark ? const Color(0xFF103C48) : const Color(0xFFFBF3DB);

  /// The default terminal foreground.
  Color get termFg =>
      _isDark ? const Color(0xFFADBCBC) : const Color(0xFF53676D);

  /// The bold terminal foreground.
  Color get termFgBold =>
      _isDark ? const Color(0xFFCAD8D9) : const Color(0xFF3A4D53);

  /// `SGR 2` dim output. Exempt from the 3.0 indicator floor, per R-32-145.
  Color get termFgDim =>
      _isDark ? const Color(0xFF72898F) : const Color(0xFF909995);

  /// The terminal cursor.
  Color get termCursor =>
      _isDark ? const Color(0xFFCAD8D9) : const Color(0xFF3A4D53);

  /// The selection background. A background, not an ink.
  Color get termSelection =>
      _isDark ? const Color(0xFF2D5B69) : const Color(0xFFD5CDB6);

  /// ANSI slot 0, black. A background slot, exempt from the indicator
  /// floor per R-32-140.
  Color get termAnsi0 =>
      _isDark ? const Color(0xFF184956) : const Color(0xFFECE3CC);

  /// ANSI slot 1, red.
  Color get termAnsi1 =>
      _isDark ? const Color(0xFFFA5750) : const Color(0xFFD2212D);

  /// ANSI slot 2, green.
  Color get termAnsi2 =>
      _isDark ? const Color(0xFF75B938) : const Color(0xFF489100);

  /// ANSI slot 3, yellow. Misses the indicator floor by 0.02 in light, per
  /// R-32-142; the app MUST accept it and MUST NOT correct it.
  Color get termAnsi3 =>
      _isDark ? const Color(0xFFDBB32D) : const Color(0xFFAD8900);

  /// ANSI slot 4, blue.
  Color get termAnsi4 =>
      _isDark ? const Color(0xFF4695F7) : const Color(0xFF0072D4);

  /// ANSI slot 5, magenta.
  Color get termAnsi5 =>
      _isDark ? const Color(0xFFF275BE) : const Color(0xFFCA4898);

  /// ANSI slot 6, cyan.
  Color get termAnsi6 =>
      _isDark ? const Color(0xFF41C7B9) : const Color(0xFF009C8F);

  /// ANSI slot 7, white. Deviates from the published Selenized mapping:
  /// `fg_0`, not `dim_0`, per R-32-141.
  Color get termAnsi7 =>
      _isDark ? const Color(0xFFADBCBC) : const Color(0xFF53676D);

  /// ANSI slot 8, bright black. A background slot, exempt.
  Color get termAnsi8 =>
      _isDark ? const Color(0xFF2D5B69) : const Color(0xFFD5CDB6);

  /// ANSI slot 9, bright red.
  Color get termAnsi9 =>
      _isDark ? const Color(0xFFFF665C) : const Color(0xFFCC1729);

  /// ANSI slot 10, bright green.
  Color get termAnsi10 =>
      _isDark ? const Color(0xFF84C747) : const Color(0xFF428B00);

  /// ANSI slot 11, bright yellow.
  Color get termAnsi11 =>
      _isDark ? const Color(0xFFEBC13D) : const Color(0xFFA78300);

  /// ANSI slot 12, bright blue.
  Color get termAnsi12 =>
      _isDark ? const Color(0xFF58A3FF) : const Color(0xFF006DCE);

  /// ANSI slot 13, bright magenta.
  Color get termAnsi13 =>
      _isDark ? const Color(0xFFFF84CD) : const Color(0xFFC44392);

  /// ANSI slot 14, bright cyan.
  Color get termAnsi14 =>
      _isDark ? const Color(0xFF53D6C7) : const Color(0xFF00978A);

  /// ANSI slot 15, bright white.
  Color get termAnsi15 =>
      _isDark ? const Color(0xFFCAD8D9) : const Color(0xFF3A4D53);
}
