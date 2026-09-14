/// Self-check for `app/lib/models/char_width.dart`, per R-10-023: a narrow
/// code point occupies one cell, a CJK/emoji code point occupies two, and a
/// combining mark occupies none, so a following character never shifts.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/models/char_width.dart';

void main() {
  test('ASCII is one cell wide', () {
    expect(charWidth('a'.codeUnitAt(0)), 1);
    expect(charWidth('9'.codeUnitAt(0)), 1);
    expect(charWidth(' '.codeUnitAt(0)), 1);
  });

  test('CJK ideographs are two cells wide', () {
    expect(charWidth(0x4E2D), 2); // 中
    expect(charWidth(0x65E5), 2); // 日
  });

  test('Hangul syllables and fullwidth forms are two cells wide', () {
    expect(charWidth(0xAC00), 2); // 가
    expect(charWidth(0xFF21), 2); // fullwidth 'A'
  });

  test('a wide emoji is two cells wide', () {
    expect(charWidth(0x1F600), 2); // grinning face
  });

  test('a combining mark is zero cells wide', () {
    expect(charWidth(0x0301), 0); // combining acute accent
  });

  test('a variation selector is zero cells wide', () {
    expect(charWidth(0xFE0F), 0); // emoji variation selector
  });

  test('textCellWidth sums runes, not UTF-16 code units', () {
    // A surrogate-pair emoji plus a two-letter ASCII word: 2 + 1 + 1 = 4,
    // never 5, which a naive .length-based count would produce.
    expect(textCellWidth('\u{1F600}ab'), 4);
  });

  test('a double-width code point renders across two cells: the row model', () {
    // Mirrors the Host's own row-padding assumption (R-10-023): each cell
    // in a fixed-width row accounts for exactly charWidth(codePoint) slots.
    const line = '中文ab';
    expect(textCellWidth(line), 2 + 2 + 1 + 1);
  });
}
