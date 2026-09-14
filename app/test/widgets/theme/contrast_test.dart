/// Independently recomputes the WCAG 2.2 relative-luminance contrast ratio
/// for every fixed pair `docs/32-design-language.md` section 3.6
/// (`R-32-150`) and section 3.5 (`R-32-140`, the 16 ANSI slots against
/// `color.term.bg`) states a ratio for, and asserts the computed ratio
/// matches the documented value to within rounding, per R-32-153. This is
/// the proof that `AppColor`'s hex values are byte-for-byte the documented
/// ones, not merely close.
/// This also proves `R-33-042`: the computed ratios keep `docs/32-design-language.md`'s
/// measured table intact, byte-for-byte, not merely approximated.
///
/// The formula is transcribed from `docs/32-design-language.md` section
/// 3.6: `L = 0.2126 R + 0.7152 G + 0.0722 B`, each channel linearised as
/// `c/12.92` when `c <= 0.04045` and `((c + 0.055)/1.055) ^ 2.4`
/// otherwise, and the ratio is `(L_lighter + 0.05) / (L_darker + 0.05)`.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/widgets/theme/app_color.dart';

double _linearize(double channel) => channel <= 0.04045
    ? channel / 12.92
    : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();

double _relativeLuminance(Color c) =>
    0.2126 * _linearize(c.r) +
    0.7152 * _linearize(c.g) +
    0.0722 * _linearize(c.b);

double _contrastRatio(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

/// One documented pair: its two colours in a given theme, and the ratio
/// `docs/32-design-language.md` states for that theme.
class _Pair {
  const _Pair(this.name, this.a, this.b, this.documentedRatio);

  final String name;
  final Color a;
  final Color b;
  final double documentedRatio;
}

List<_Pair> _pairs(AppColor c) => <_Pair>[
  // --- 3.2 Surfaces and borders (R-32-150) ---
  _Pair(
    'border.strong on bg.base',
    c.borderStrong,
    c.bgBase,
    c == AppColor.dark ? 5.58 : 4.53,
  ),
  _Pair(
    'border.strong on bg.raised',
    c.borderStrong,
    c.bgRaised,
    c == AppColor.dark ? 5.19 : 4.17,
  ),
  _Pair(
    'border.strong on bg.high',
    c.borderStrong,
    c.bgHigh,
    c == AppColor.dark ? 4.70 : 3.75,
  ),
  _Pair(
    'border.subtle on bg.base',
    c.borderSubtle,
    c.bgBase,
    c == AppColor.dark ? 1.47 : 1.46,
  ),
  _Pair(
    'bg.raised on bg.base',
    c.bgRaised,
    c.bgBase,
    c == AppColor.dark ? 1.08 : 1.09,
  ),
  _Pair(
    'bg.high on bg.base',
    c.bgHigh,
    c.bgBase,
    c == AppColor.dark ? 1.19 : 1.21,
  ),

  // --- 3.3 Text and accent (R-32-150) ---
  _Pair(
    'fg.primary on bg.base',
    c.fgPrimary,
    c.bgBase,
    c == AppColor.dark ? 14.72 : 15.63,
  ),
  _Pair(
    'fg.primary on bg.raised',
    c.fgPrimary,
    c.bgRaised,
    c == AppColor.dark ? 13.67 : 14.40,
  ),
  _Pair(
    'fg.primary on bg.high',
    c.fgPrimary,
    c.bgHigh,
    c == AppColor.dark ? 12.39 : 12.97,
  ),
  _Pair(
    'fg.secondary on bg.base',
    c.fgSecondary,
    c.bgBase,
    c == AppColor.dark ? 8.22 : 6.54,
  ),
  _Pair(
    'fg.secondary on bg.raised',
    c.fgSecondary,
    c.bgRaised,
    c == AppColor.dark ? 7.64 : 6.02,
  ),
  _Pair(
    'fg.secondary on bg.high',
    c.fgSecondary,
    c.bgHigh,
    c == AppColor.dark ? 6.92 : 5.42,
  ),
  _Pair(
    'fg.disabled on bg.base',
    c.fgDisabled,
    c.bgBase,
    c == AppColor.dark ? 5.58 : 2.80,
  ),
  _Pair(
    'fg.disabled on bg.raised',
    c.fgDisabled,
    c.bgRaised,
    c == AppColor.dark ? 5.19 : 2.58,
  ),
  _Pair(
    'fg.disabled on bg.high',
    c.fgDisabled,
    c.bgHigh,
    c == AppColor.dark ? 4.70 : 2.32,
  ),
  _Pair(
    'accent.text on bg.base',
    c.accentText,
    c.bgBase,
    c == AppColor.dark ? 8.81 : 5.96,
  ),
  _Pair(
    'accent.text on bg.raised',
    c.accentText,
    c.bgRaised,
    c == AppColor.dark ? 8.18 : 5.50,
  ),
  _Pair(
    'accent.text on bg.high',
    c.accentText,
    c.bgHigh,
    c == AppColor.dark ? 7.41 : 4.95,
  ),
  _Pair(
    'fg.on_accent on accent.primary',
    c.fgOnAccent,
    c.accentPrimary,
    c == AppColor.dark ? 8.81 : 5.41,
  ),
  // The pressed primary fill of R-32-501: accent.primary under fg.primary at
  // opacity.press (0.12), the pair AppFilledButton paints while pressed.
  _Pair(
    'fg.on_accent on the pressed primary fill',
    c.fgOnAccent,
    Color.alphaBlend(c.fgPrimary.withValues(alpha: 0.12), c.accentPrimary),
    c == AppColor.dark ? 9.40 : 6.39,
  ),
  _Pair(
    'fg.on_accent on status.error',
    c.fgOnAccent,
    c.statusError,
    c == AppColor.dark ? 4.92 : 5.02,
  ),
  _Pair(
    'accent.primary on bg.base',
    c.accentPrimary,
    c.bgBase,
    c == AppColor.dark ? 8.81 : 4.59,
  ),
  _Pair(
    'accent.primary on bg.raised',
    c.accentPrimary,
    c.bgRaised,
    c == AppColor.dark ? 8.18 : 4.23,
  ),

  // --- 3.4 Semantic state colours (R-32-150) ---
  _Pair(
    'status.error on bg.base',
    c.statusError,
    c.bgBase,
    c == AppColor.dark ? 4.92 : 4.25,
  ),
  _Pair(
    'status.error on bg.raised',
    c.statusError,
    c.bgRaised,
    c == AppColor.dark ? 4.57 : 3.92,
  ),
  _Pair(
    'status.warning on bg.base',
    c.statusWarning,
    c.bgBase,
    c == AppColor.dark ? 9.64 : 3.83,
  ),
  _Pair(
    'status.warning on bg.raised',
    c.statusWarning,
    c.bgRaised,
    c == AppColor.dark ? 8.96 : 3.53,
  ),
  _Pair(
    'status.ok on bg.base',
    c.statusOk,
    c.bgBase,
    c == AppColor.dark ? 8.51 : 3.70,
  ),
  _Pair(
    'status.ok on bg.raised',
    c.statusOk,
    c.bgRaised,
    c == AppColor.dark ? 7.91 : 3.41,
  ),
  _Pair(
    'status.working on bg.base',
    c.statusWorking,
    c.bgBase,
    c == AppColor.dark ? 9.64 : 3.83,
  ),
  _Pair(
    'status.working on bg.raised',
    c.statusWorking,
    c.bgRaised,
    c == AppColor.dark ? 8.96 : 3.53,
  ),
  _Pair(
    'status.blocked on bg.base',
    c.statusBlocked,
    c.bgBase,
    c == AppColor.dark ? 4.92 : 4.25,
  ),
  _Pair(
    'status.blocked on bg.raised',
    c.statusBlocked,
    c.bgRaised,
    c == AppColor.dark ? 4.57 : 3.92,
  ),
  _Pair(
    'status.done on bg.base',
    c.statusDone,
    c.bgBase,
    c == AppColor.dark ? 12.01 : 4.03,
  ),
  _Pair(
    'status.done on bg.raised',
    c.statusDone,
    c.bgRaised,
    c == AppColor.dark ? 11.15 : 3.71,
  ),
  _Pair(
    'status.idle on bg.base',
    c.statusIdle,
    c.bgBase,
    c == AppColor.dark ? 8.51 : 3.70,
  ),
  _Pair(
    'status.idle on bg.raised',
    c.statusIdle,
    c.bgRaised,
    c == AppColor.dark ? 7.91 : 3.41,
  ),
  _Pair(
    'status.unknown on bg.base',
    c.statusUnknown,
    c.bgBase,
    c == AppColor.dark ? 5.58 : 4.53,
  ),
  _Pair(
    'status.unknown on bg.raised',
    c.statusUnknown,
    c.bgRaised,
    c == AppColor.dark ? 5.19 : 4.17,
  ),

  // --- 3.5 / 3.6 Terminal palette (R-32-140, R-32-150) ---
  // term.fg, term.fg_bold and term.cursor additionally prove R-30-151 and
  // R-32-143.
  _Pair(
    'term.fg on term.bg',
    c.termFg,
    c.termBg,
    c == AppColor.dark ? 6.07 : 5.37,
  ),
  _Pair(
    'term.fg_bold on term.bg',
    c.termFgBold,
    c.termBg,
    c == AppColor.dark ? 8.14 : 8.01,
  ),
  _Pair(
    'term.cursor on term.bg',
    c.termCursor,
    c.termBg,
    c == AppColor.dark ? 8.14 : 8.01,
  ),
  _Pair(
    'term.fg_dim on term.bg',
    c.termFgDim,
    c.termBg,
    c == AppColor.dark ? 3.23 : 2.64,
  ),
  _Pair(
    'term.fg on term.selection',
    c.termFg,
    c.termSelection,
    c == AppColor.dark ? 3.80 : 3.75,
  ),
  _Pair(
    'term.fg_bold on term.selection',
    c.termFgBold,
    c.termSelection,
    c == AppColor.dark ? 5.10 : 5.59,
  ),
  _Pair(
    'term.ansi_0 on term.bg',
    c.termAnsi0,
    c.termBg,
    c == AppColor.dark ? 1.21 : 1.15,
  ),
  _Pair(
    'term.ansi_1 on term.bg',
    c.termAnsi1,
    c.termBg,
    c == AppColor.dark ? 3.71 : 4.74,
  ),
  _Pair(
    'term.ansi_2 on term.bg',
    c.termAnsi2,
    c.termBg,
    c == AppColor.dark ? 4.97 : 3.56,
  ),
  // term.ansi_3's light-theme ratio additionally proves R-32-142.
  _Pair(
    'term.ansi_3 on term.bg',
    c.termAnsi3,
    c.termBg,
    c == AppColor.dark ? 5.96 : 2.98,
  ),
  _Pair(
    'term.ansi_4 on term.bg',
    c.termAnsi4,
    c.termBg,
    c == AppColor.dark ? 3.92 : 4.35,
  ),
  _Pair(
    'term.ansi_5 on term.bg',
    c.termAnsi5,
    c.termBg,
    c == AppColor.dark ? 4.58 : 3.87,
  ),
  _Pair(
    'term.ansi_6 on term.bg',
    c.termAnsi6,
    c.termBg,
    c == AppColor.dark ? 5.73 : 3.08,
  ),
  _Pair(
    'term.ansi_7 on term.bg',
    c.termAnsi7,
    c.termBg,
    c == AppColor.dark ? 6.07 : 5.37,
  ),
  _Pair(
    'term.ansi_8 on term.bg',
    c.termAnsi8,
    c.termBg,
    c == AppColor.dark ? 1.60 : 1.43,
  ),
  _Pair(
    'term.ansi_9 on term.bg',
    c.termAnsi9,
    c.termBg,
    c == AppColor.dark ? 4.15 : 5.09,
  ),
  _Pair(
    'term.ansi_10 on term.bg',
    c.termAnsi10,
    c.termBg,
    c == AppColor.dark ? 5.81 : 3.85,
  ),
  _Pair(
    'term.ansi_11 on term.bg',
    c.termAnsi11,
    c.termBg,
    c == AppColor.dark ? 6.94 : 3.22,
  ),
  _Pair(
    'term.ansi_12 on term.bg',
    c.termAnsi12,
    c.termBg,
    c == AppColor.dark ? 4.60 : 4.64,
  ),
  _Pair(
    'term.ansi_13 on term.bg',
    c.termAnsi13,
    c.termBg,
    c == AppColor.dark ? 5.35 : 4.15,
  ),
  _Pair(
    'term.ansi_14 on term.bg',
    c.termAnsi14,
    c.termBg,
    c == AppColor.dark ? 6.70 : 3.27,
  ),
  _Pair(
    'term.ansi_15 on term.bg',
    c.termAnsi15,
    c.termBg,
    c == AppColor.dark ? 8.14 : 8.01,
  ),
];

void main() {
  for (final theme in AppColor.values) {
    group('Contrast ratios for ${theme.name} (R-32-150, R-32-140)', () {
      for (final pair in _pairs(theme)) {
        test(pair.name, () {
          final computed = _contrastRatio(pair.a, pair.b);
          expect(
            computed,
            closeTo(pair.documentedRatio, 0.01),
            reason:
                '$pair.name: computed ${computed.toStringAsFixed(2)} != '
                'documented ${pair.documentedRatio.toStringAsFixed(2)}',
          );
        });
      }
    });
  }
}
