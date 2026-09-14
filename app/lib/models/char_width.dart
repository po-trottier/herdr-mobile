/// A Unicode East Asian Width table for terminal-cell measurement, per
/// `docs/10-herdr-integration.md` R-10-023: the Device MUST measure
/// character width with a Unicode East Asian Width table and MUST render a
/// double-width code point across two cells. Getting this wrong shifts
/// every following character on the row, because the Host has already
/// padded rows assuming its own width model.
///
/// This file is self-contained: no dependency on `xterm2` or on
/// `app/lib/services/terminal.dart`, per `docs/90-implementation-plan.md`
/// `WP-16-b`. It classifies a Unicode scalar value (a full code point, not
/// a UTF-16 code unit) as occupying 0, 1 or 2 terminal cells, following the
/// Unicode Standard Annex #11 East Asian Width property: a code point
/// whose property is `W` (Wide) or `F` (Fullwidth) occupies two cells;
/// every other code point occupies one, except a combining mark, which
/// occupies none because it draws onto the cell before it.
///
/// Ranges below are condensed from the published Unicode `EastAsianWidth.txt`
/// `W`/`F` categories (the CJK, Hangul and fullwidth-form blocks, and the
/// pictographic ranges the emoji data file also marks wide) plus the
/// `Mn`/`Me` combining-mark ranges most likely to appear in terminal output
/// (accents, Hangul jungseong/jongseong fillers, and variation selectors).
/// A code point absent from every range below defaults to width 1, which is
/// the correct default for the overwhelming majority of Unicode.
library;

/// Returns the terminal cell width of the single Unicode scalar value
/// [codePoint]: `0` for a combining mark, which draws onto the previous
/// cell rather than claiming one of its own; `2` for an East Asian Wide or
/// Fullwidth code point; `1` for everything else.
int charWidth(int codePoint) {
  if (codePoint == 0) return 0;
  if (_inRanges(codePoint, _combining)) return 0;
  if (_inRanges(codePoint, _wide)) return 2;
  return 1;
}

/// Returns the total terminal cell width of [text]: the sum of [charWidth]
/// over its Unicode scalar values (`text.runes`, not UTF-16 code units, so
/// a surrogate pair counts once for its true code point).
int textCellWidth(String text) {
  var width = 0;
  for (final codePoint in text.runes) {
    width += charWidth(codePoint);
  }
  return width;
}

/// `true` when [codePoint] falls inside any `[start, end]` pair of
/// [ranges]. `ranges` MUST be sorted by `start` with no overlap, so a
/// binary search finds the containing range in `O(log n)`.
///
/// ponytail: binary search over a flat sorted array, not an interval tree —
/// this table has a few hundred ranges and is queried once per code point
/// per rendered frame; upgrade only if profiling shows this on a hot path.
bool _inRanges(int codePoint, List<List<int>> ranges) {
  var low = 0;
  var high = ranges.length - 1;
  while (low <= high) {
    final mid = (low + high) >> 1;
    final range = ranges[mid];
    if (codePoint < range[0]) {
      high = mid - 1;
    } else if (codePoint > range[1]) {
      low = mid + 1;
    } else {
      return true;
    }
  }
  return false;
}

/// East Asian Wide (`W`) and Fullwidth (`F`) ranges, sorted by start.
const List<List<int>> _wide = <List<int>>[
  [0x1100, 0x115F], // Hangul Jamo (Wide)
  [0x231A, 0x231B], // Watch, hourglass
  [0x2329, 0x232A], // Angle brackets
  [0x23E9, 0x23EC], // Media control symbols
  [0x23F0, 0x23F0], // Alarm clock
  [0x23F3, 0x23F3], // Hourglass with flowing sand
  [0x25FD, 0x25FE], // Small squares
  [0x2614, 0x2615], // Umbrella, hot beverage
  [0x2648, 0x2653], // Zodiac symbols
  [0x267F, 0x267F], // Wheelchair symbol
  [0x2693, 0x2693], // Anchor
  [0x26A1, 0x26A1], // High voltage
  [0x26AA, 0x26AB], // Circles
  [0x26BD, 0x26BE], // Soccer ball, baseball
  [0x26C4, 0x26C5], // Snowman, sun behind cloud
  [0x26CE, 0x26CE], // Ophiuchus
  [0x26D4, 0x26D4], // No entry
  [0x26EA, 0x26EA], // Church
  [0x26F2, 0x26F3], // Fountain, flag in hole
  [0x26F5, 0x26F5], // Sailboat
  [0x26FA, 0x26FA], // Tent
  [0x26FD, 0x26FD], // Fuel pump
  [0x2705, 0x2705], // Check mark button
  [0x270A, 0x270B], // Fist, raised hand
  [0x2728, 0x2728], // Sparkles
  [0x274C, 0x274C], // Cross mark
  [0x274E, 0x274E], // Cross mark button
  [0x2753, 0x2755], // Question/exclamation marks
  [0x2757, 0x2757], // Exclamation mark
  [0x2795, 0x2797], // Plus/minus/divide signs
  [0x27B0, 0x27B0], // Curly loop
  [0x27BF, 0x27BF], // Double curly loop
  [0x2B1B, 0x2B1C], // Large squares
  [0x2B50, 0x2B50], // Star
  [0x2B55, 0x2B55], // Heavy large circle
  [0x2E80, 0x303E], // CJK radicals, symbols and punctuation
  [0x3041, 0x33FF], // Hiragana, Katakana, CJK compatibility
  [0x3400, 0x4DBF], // CJK Unified Ideographs Extension A
  [0x4E00, 0x9FFF], // CJK Unified Ideographs
  [0xA000, 0xA4CF], // Yi Syllables and Radicals
  [0xAC00, 0xD7A3], // Hangul Syllables
  [0xF900, 0xFAFF], // CJK Compatibility Ideographs
  [0xFE30, 0xFE4F], // CJK Compatibility Forms
  [0xFF00, 0xFF60], // Fullwidth ASCII variants and punctuation
  [0xFFE0, 0xFFE6], // Fullwidth signs
  [0x16FE0, 0x16FE3], // Tangut/Nushu iteration marks
  [0x17000, 0x18CD5], // Tangut
  [0x18D00, 0x18D08], // Tangut Supplement
  [0x1AFF0, 0x1B16F], // Kana extended and supplement
  [0x1B170, 0x1B2FB], // Nushu
  [0x1F004, 0x1F004], // Mahjong red dragon
  [0x1F0CF, 0x1F0CF], // Playing card black joker
  [0x1F18E, 0x1F18E], // Negative squared AB
  [0x1F191, 0x1F19A], // Squared CL/COOL/FREE/... symbols
  [0x1F200, 0x1F320], // Squared Katakana and enclosed ideographs
  [0x1F32D, 0x1F335], // Food and plant emoji
  [0x1F337, 0x1F37C], // Plant and food emoji
  [0x1F37E, 0x1F393], // Drink, celebration and school emoji
  [0x1F3A0, 0x1F3CA], // Activity emoji
  [0x1F3CF, 0x1F3D3], // Sport emoji
  [0x1F3E0, 0x1F3F0], // Building and place emoji
  [0x1F3F4, 0x1F3F4], // Waving black flag
  [0x1F3F8, 0x1F43E], // Animal and object emoji
  [0x1F440, 0x1F440], // Eyes
  [0x1F442, 0x1F4FC], // Body, clothing and object emoji
  [0x1F4FF, 0x1F53D], // Object and arrow emoji
  [0x1F54B, 0x1F54E], // Religious symbol emoji
  [0x1F550, 0x1F567], // Clock face emoji
  [0x1F57A, 0x1F57A], // Man dancing
  [0x1F595, 0x1F596], // Hand gesture emoji
  [0x1F5A4, 0x1F5A4], // Black heart
  [0x1F5FB, 0x1F64F], // Landmark, face and gesture emoji
  [0x1F680, 0x1F6C5], // Transport emoji
  [0x1F6CC, 0x1F6CC], // Person in bed
  [0x1F6D0, 0x1F6D2], // Place of worship, shopping trolley/bags
  [0x1F6D5, 0x1F6D7], // Place of worship, sled, ski
  [0x1F6DC, 0x1F6DF], // Wireless, ring buoy, playground slide
  [0x1F6EB, 0x1F6EC], // Aeroplane departure/arrival
  [0x1F6F4, 0x1F6FC], // Vehicle emoji
  [0x1F7E0, 0x1F7EB], // Coloured circles and squares
  [0x1F7F0, 0x1F7F0], // Heavy equals sign
  [0x1F90C, 0x1F93A], // Hand and person emoji
  [0x1F93C, 0x1F945], // Sport emoji
  [0x1F947, 0x1F9FF], // Medal, face and object emoji
  [0x1FA70, 0x1FAFF], // Extended-A object and face emoji
  [0x20000, 0x3FFFD], // CJK Unified Ideographs Extension B and beyond
];

/// Combining-mark ranges most likely inside terminal output: spacing and
/// non-spacing accents, Hangul jungseong/jongseong filler and variation
/// selectors. Not exhaustive of Unicode's full `Mn`/`Me` general category,
/// which spans thousands of code points across dozens of scripts a
/// terminal payload has never carried in this app's measurements
/// (`docs/21-terminal-rendering.md` R-10-016).
///
/// ponytail: covers the scripts observed or plausible in a developer's
/// terminal (Latin/Greek/Cyrillic combining diacritics, ZWJ, variation
/// selectors); extend with the Unicode data file's full `Mn`/`Me` list if
/// a fidelity test surfaces a script outside it.
const List<List<int>> _combining = <List<int>>[
  [0x0300, 0x036F], // Combining diacritical marks
  [0x0483, 0x0489], // Cyrillic combining marks
  [0x0591, 0x05BD], // Hebrew points
  [0x05BF, 0x05BF],
  [0x05C1, 0x05C2],
  [0x05C4, 0x05C5],
  [0x05C7, 0x05C7],
  [0x0610, 0x061A], // Arabic combining marks
  [0x064B, 0x065F],
  [0x0670, 0x0670],
  [0x06D6, 0x06DC],
  [0x06DF, 0x06E4],
  [0x0900, 0x0903], // Devanagari combining marks
  [0x093A, 0x094F],
  [0x0951, 0x0957],
  [0x200B, 0x200F], // Zero-width space, ZWJ/ZWNJ, direction marks
  [0x20D0, 0x20FF], // Combining marks for symbols
  [0xFE00, 0xFE0F], // Variation selectors 1-16
  [0xFE20, 0xFE2F], // Combining half marks
];
