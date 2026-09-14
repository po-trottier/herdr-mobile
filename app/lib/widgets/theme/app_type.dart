/// Type-scale tokens from `docs/32-design-language.md` section 4. R-32-202
/// fixes the fifteen tokens as the complete set. `docs/30-ux-spec.md`
/// R-30-101 fixes the Dart naming: `type.body.strong` becomes
/// `AppType.bodyStrong`. No colour is set on any style here, per R-32-005:
/// a caller applies ink from `AppColor` separately.
library;

import 'package:flutter/widgets.dart' show FontWeight, TextStyle;

/// The type scale. Every size, line height, weight and letter spacing is
/// transcribed verbatim from `docs/32-design-language.md` section 4.
class AppType {
  const AppType._();

  /// IBM Plex Sans, per R-32-200. The family for every token below except
  /// the `mono*` group.
  static const String interfaceFontFamily = 'IBM Plex Sans';

  /// `Archivo`, per `docs/32-design-language.md` section 5. Weights 700
  /// (Bold) and 900 (Black) bundled. SIL OFL 1.1.
  static const String displayFontFamily = 'Archivo';

  /// `JetBrainsMono Nerd Font Mono`, per `docs/21-terminal-rendering.md`
  /// R-21-011. That document owns the font; this file only references its
  /// name to build the `mono*` tokens, per R-32-003.
  static const String monoFontFamily = 'JetBrainsMono Nerd Font Mono';

  /// The terminal line-height ratio, per `docs/21-terminal-rendering.md`
  /// R-21-010. Owned there; `docs/32-design-language.md` R-32-209 forbids
  /// restating it, so this constant exists only to compute [monoTerminal]
  /// and MUST NOT be read as this file claiming ownership of the ratio.
  static const double _monoTerminalLineHeightRatio = 1.3;

  /// The only permitted `type.mono.terminal` sizes, per R-32-208.
  static const List<int> monoTerminalSizes = <int>[10, 11, 12, 13, 14, 16, 18];

  /// The default `type.mono.terminal` size, per R-32-208.
  static const int monoTerminalDefaultSize = 13;

  /// The product name on `/welcome`, and nowhere else, per R-32-205.
  /// Archivo, 42/40, w900, ls -2.4 (amended 2026-09-08: at 44 the headline
  /// `From anywhere.` measured 345 px against the 343 px column of the
  /// 375 reference device and wrapped to a third line; at 42 it is 328).
  static const TextStyle display = TextStyle(
    fontFamily: displayFontFamily,
    fontSize: 42,
    height: 40 / 42,
    fontWeight: FontWeight.w900,
    letterSpacing: -2.4,
  );

  /// A screen title with no back chevron, and the product name on `/lock`.
  /// Archivo, 28/30, w900, ls -1.1.
  static const TextStyle title = TextStyle(
    fontFamily: displayFontFamily,
    fontSize: 28,
    height: 30 / 28,
    fontWeight: FontWeight.w900,
    letterSpacing: -1.1,
  );

  /// An app bar title, a host chip, a sheet heading.
  /// Archivo, 18/24, w700, ls -0.36.
  static const TextStyle heading = TextStyle(
    fontFamily: displayFontFamily,
    fontSize: 18,
    height: 24 / 18,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.36,
  );

  /// Every row label, every sentence.
  static const TextStyle body = TextStyle(
    fontFamily: interfaceFontFamily,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
  );

  /// A primary row label, a button label.
  static const TextStyle bodyStrong = TextStyle(
    fontFamily: interfaceFontFamily,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w600,
  );

  /// A status word, a text button, a right-aligned value.
  static const TextStyle label = TextStyle(
    fontFamily: interfaceFontFamily,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w500,
  );

  /// A secondary line, a hint, a counter.
  static const TextStyle caption = TextStyle(
    fontFamily: interfaceFontFamily,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w400,
  );

  /// An upper-case section header. JetBrains Mono, 11/14, w700, ls 1.76, UPPER.
  static const TextStyle micro = TextStyle(
    fontFamily: monoFontFamily,
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.76,
  );

  /// A count beside an attention icon. JetBrains Mono, 11/14, w700, ls 0, as written.
  static const TextStyle microStrong = TextStyle(
    fontFamily: monoFontFamily,
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w700,
  );

  /// A step number in the welcome steps card. JetBrains Mono, 13/16, w700, ls 1.04. Until
  /// 2026-09-09 every button label took it; a button label is the platform's own style now,
  /// per `docs/03-product-decisions.md` R-03-104.
  static const TextStyle monoButton = TextStyle(
    fontFamily: monoFontFamily,
    fontSize: 13,
    height: 16 / 13,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.04,
  );

  /// A raw error, an id, a path, a relay origin.
  static const TextStyle monoCode = TextStyle(
    fontFamily: monoFontFamily,
    fontSize: 13,
    height: 20 / 13,
    fontWeight: FontWeight.w400,
  );

  /// A key cap label.
  static const TextStyle monoKey = TextStyle(
    fontFamily: monoFontFamily,
    fontSize: 13,
    height: 16 / 13,
    fontWeight: FontWeight.w500,
  );

  /// The prompt composer text area.
  static const TextStyle monoCompose = TextStyle(
    fontFamily: monoFontFamily,
    fontSize: 15,
    height: 22 / 15,
    fontWeight: FontWeight.w400,
  );

  /// One pairing word in one word field. MUST NOT be tracked out, per
  /// R-32-204.
  static const TextStyle monoPhrase = TextStyle(
    fontFamily: monoFontFamily,
    fontSize: 18,
    height: 24 / 18,
    fontWeight: FontWeight.w500,
  );

  /// Terminal content. `size` MUST be one of [monoTerminalSizes], per
  /// R-32-208. The line height is `size` times the ratio
  /// `docs/21-terminal-rendering.md` R-21-010 fixes, which is a fixed
  /// 1.3 multiplier of the size for every permitted size, per R-32-209.
  /// This token MUST NOT scale with the system text-size setting, per
  /// R-32-210; the caller applies `TextScaler.noScaling`.
  static TextStyle monoTerminal({int size = monoTerminalDefaultSize}) {
    assert(
      monoTerminalSizes.contains(size),
      'type.mono.terminal size must be one of $monoTerminalSizes, per R-32-208',
    );
    return TextStyle(
      fontFamily: monoFontFamily,
      fontSize: size.toDouble(),
      height: _monoTerminalLineHeightRatio,
      fontWeight: FontWeight.w400,
    );
  }
}
