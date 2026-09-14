/// Proves `xterm2`'s SGR parser renders every SGR attribute the Host emits
/// (R-10-017) into the cell grid it reads back, per
/// `docs/21-terminal-rendering.md` R-21-007a, which names the nine codes
/// this file asserts: `0`, `1`, `2`, `3`, `4`, `38;2`, `48;2`, `38;5` and
/// `48;5`. This is `docs/90-implementation-plan.md` Phase 2 (`WP-2`), the
/// R-20-008 terminal-widget fidelity gate.
/// The `38;2` and `48;2` cases below also prove `docs/30-ux-spec.md`
/// R-30-153: the app renders 24-bit truecolour SGR exactly as received,
/// with the exact RGB bytes surviving the read-back.
///
/// `app/lib/services/terminal.dart` is `WP-16-a`'s path
/// (`docs/90-implementation-plan.md` §5.3 `INT-16-terminal`), so this file
/// builds its own `xterm2` `Terminal` directly rather than writing to a
/// path this package does not own (R-90-016).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/xterm.dart';

void main() {
  group('SGR fidelity (R-21-007a)', () {
    late Terminal terminal;

    setUp(() {
      // `maxLines: 0` matches the R-21-002 no-scrollback contract; the grid
      // size only needs to hold the short strings this file writes.
      terminal = Terminal(maxLines: 0);
      terminal.resize(40, 5);
    });

    /// Row 0 of the active buffer, per `docs/21-terminal-rendering.md`
    /// §2.2.1's read-back contract (`lib/src/core/buffer/line.dart`
    /// `getForeground` / `getBackground` / `getAttributes`).
    BufferLine firstRow() => terminal.buffer.lines[0];

    test('SGR 0 resets every attribute and colour to default', () {
      terminal.write('\x1b[1;3;4;38;2;10;20;30mX\x1b[0mY');
      final line = firstRow();
      // Column 0 ('X') carries the styling written before the reset.
      expect(line.getAttributes(0) & CellAttr.bold, isNot(0));
      // Column 1 ('Y') was written after `\x1b[0m` and MUST carry none of
      // it: no visual attribute bit, and both colours back to default.
      expect(line.getAttributes(1) & CellAttr.visualMask, 0);
      expect(line.getForeground(1) & CellColor.typeMask, CellColor.normal);
      expect(line.getBackground(1) & CellColor.typeMask, CellColor.normal);
    });

    test('SGR 1 sets bold', () {
      terminal.write('\x1b[1mX');
      expect(firstRow().getAttributes(0) & CellAttr.bold, isNot(0));
    });

    test('SGR 2 sets faint', () {
      terminal.write('\x1b[2mX');
      expect(firstRow().getAttributes(0) & CellAttr.faint, isNot(0));
    });

    test('SGR 3 sets italic', () {
      terminal.write('\x1b[3mX');
      expect(firstRow().getAttributes(0) & CellAttr.italic, isNot(0));
    });

    test('SGR 4 sets underline', () {
      terminal.write('\x1b[4mX');
      expect(firstRow().getAttributes(0) & CellAttr.underline, isNot(0));
    });

    test('SGR 38;2 sets a 24-bit truecolour foreground', () {
      terminal.write('\x1b[38;2;12;34;56mX');
      final fg = firstRow().getForeground(0);
      expect(fg & CellColor.typeMask, CellColor.rgb);
      final rgb = fg & CellColor.valueMask;
      expect((rgb >> 16) & 0xff, 12);
      expect((rgb >> 8) & 0xff, 34);
      expect(rgb & 0xff, 56);
    });

    test('SGR 48;2 sets a 24-bit truecolour background', () {
      terminal.write('\x1b[48;2;78;90;123mX');
      final bg = firstRow().getBackground(0);
      expect(bg & CellColor.typeMask, CellColor.rgb);
      final rgb = bg & CellColor.valueMask;
      expect((rgb >> 16) & 0xff, 78);
      expect((rgb >> 8) & 0xff, 90);
      expect(rgb & 0xff, 123);
    });

    test('SGR 38;5 sets an indexed (256-colour palette) foreground', () {
      terminal.write('\x1b[38;5;202mX');
      final fg = firstRow().getForeground(0);
      expect(fg & CellColor.typeMask, CellColor.palette);
      expect(fg & CellColor.valueMask, 202);
    });

    test('SGR 48;5 sets an indexed (256-colour palette) background', () {
      terminal.write('\x1b[48;5;93mX');
      final bg = firstRow().getBackground(0);
      expect(bg & CellColor.typeMask, CellColor.palette);
      expect(bg & CellColor.valueMask, 93);
    });

    test('cell content survives alongside the styling', () {
      terminal.write('\x1b[1;38;2;255;0;0mHi');
      final line = firstRow();
      expect(String.fromCharCode(line.getCodePoint(0)), 'H');
      expect(String.fromCharCode(line.getCodePoint(1)), 'i');
    });
  });
}
