/// Proves the clear-and-home reset (`\x1b[2J\x1b[H`, R-21-002) keeps a
/// persistent `xterm2` `Terminal` scrollback-free and free of stale
/// content across repeated full-viewport feeds, which is what makes
/// R-21-001's strategy B (a persistent emulator, not a fresh one per
/// frame) safe: each `pane.read` resends the whole visible viewport
/// (`docs/21-terminal-rendering.md` §1.2a), so a persistent instance that
/// skipped the reset would accumulate scrollback and stale rows.
///
/// `app/lib/services/terminal.dart` is `WP-16-a`'s path
/// (`docs/90-implementation-plan.md` §5.3 `INT-16-terminal`), so this file
/// builds its own `xterm2` `Terminal` directly rather than writing to a
/// path this package does not own (R-90-016).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/xterm.dart';

/// The clear-and-home reset R-21-002 requires before every feed.
const _clearAndHome = '\x1b[2J\x1b[H';

/// Every row's text, joined, so a substring search covers the whole grid.
String _visibleText(Terminal terminal) {
  final rows = terminal.buffer.lines.length;
  return List<String>.generate(
    rows,
    (row) => terminal.buffer.lines[row].getText(),
  ).join('\n');
}

void main() {
  test('the clear-and-home reset stops scrollback growth across 10 feeds', () {
    // `maxLines: 0` matches the production R-21-002 contract.
    final terminal = Terminal(maxLines: 0);
    terminal.resize(20, 5);

    for (var frame = 0; frame < 10; frame++) {
      terminal.write(_clearAndHome);
      terminal.write('frame-marker-$frame');

      // With `maxLines: 0` the active buffer can never hold more than
      // one viewport's worth of rows, so scrollback stays flat.
      expect(terminal.buffer.lines.length, terminal.viewHeight);
      expect(terminal.buffer.scrollBack, 0);

      // The reset wipes every prior frame: only the marker just
      // written may appear anywhere in the grid.
      final visibleText = _visibleText(terminal);
      expect(visibleText, contains('frame-marker-$frame'));
      for (var earlier = 0; earlier < frame; earlier++) {
        expect(visibleText, isNot(contains('frame-marker-$earlier')));
      }
    }
  });

  test('omitting the reset accumulates content, the risk R-21-002 removes', () {
    final terminal = Terminal(maxLines: 0);
    terminal.resize(20, 5);

    // No clear-and-home reset between feeds: each write continues from
    // wherever the cursor stopped, exactly the "Duplicated content" and
    // "Scrollback growth" risk `docs/21-terminal-rendering.md` §1.2a
    // describes for a persistent emulator fed repeated full-viewport
    // snapshots.
    terminal.write('frame-marker-0\r\n');
    terminal.write('frame-marker-1\r\n');

    final visibleText = _visibleText(terminal);

    // Both markers survive simultaneously: without the reset, the
    // second feed does not erase the first, unlike the positive-path
    // test above.
    expect(visibleText, contains('frame-marker-0'));
    expect(visibleText, contains('frame-marker-1'));
  });
}
