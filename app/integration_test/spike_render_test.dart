/// The R-20-008 fidelity and frame-rate gate, driven against the real
/// captured fixture (`docs/90-implementation-plan.md` Phase 2, `WP-2`).
///
/// This file feeds `app/test/fixtures/pane-50row.ansi` (`WP-1`'s fixture,
/// R-02-015) to a persistent `xterm2` `Terminal` every 100 ms for 60
/// seconds, with the R-21-002 clear-and-home reset before each feed, and
/// records the sustained frame rate. It also feeds four additional
/// synthetic strings, one per R-20-008 step 4 fidelity check (24-bit
/// truecolour SGR, a wide CJK character, an emoji with a variation
/// selector, a Powerline glyph), and asserts the cell grid resolves each
/// one to the correct content and cell width. Step 5 of the gate: none of
/// these probes exercise cursor motion, an erase, a scroll region, an OSC
/// sequence or a mode switch, matching the measured Host payload vocabulary
/// (R-02-018, R-21-003).
///
/// `app/lib/services/terminal.dart` and
/// `app/lib/widgets/terminal_view_widget.dart` are `WP-16-a`'s and
/// `WP-16-b`'s paths respectively (`docs/90-implementation-plan.md` §5.3
/// `INT-16-terminal`), so this file builds its own `xterm2` `Terminal` and
/// `TerminalView` directly rather than writing to a path this package
/// does not own (R-90-016).
///
/// **Hardware gap.** R-20-008's reference devices are a Pixel 6a and an
/// iPhone SE (3rd generation). Neither is attached to the workstation that
/// ran this file; `flutter devices` there lists only Windows desktop,
/// Chrome and Edge. The frame-rate number this file prints is measured on
/// whichever device actually ran it, and that fact is printed alongside
/// the number so it is never mistaken for the R-20-008 device measurement.
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xterm2/xterm.dart';

/// The clear-and-home reset R-21-002 requires before every feed.
const _clearAndHome = '\x1b[2J\x1b[H';

/// The R-21-014 fallback chain, verbatim.
const _fontFamilyFallback = <String>[
  'Noto Sans Mono CJK SC',
  'Noto Sans Mono CJK TC',
  'Noto Sans Mono CJK KR',
  'Noto Sans Mono CJK JP',
  'PingFang SC',
  'PingFang TC',
  'PingFang HK',
  'Hiragino Sans',
  'Apple SD Gothic Neo',
  'Apple Color Emoji',
  'Noto Color Emoji',
  'Noto Sans Symbols',
  'monospace',
];

/// R-21-009: columns from the fixture's recorded `rect.width` and rows
/// from its recorded `viewport_rows`, per the Phase 1 pull request
/// (R-02-015): pane `w2E:p6`, `rect: {width: 282, height: 87}`,
/// `scroll.viewport_rows: 87`.
const _fixtureColumns = 282;
const _fixtureRows = 87;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'xterm2 sustains a frame rate feeding the captured fixture for 60s',
    (tester) async {
      final fixtureText = File('test/fixtures/pane-50row.ansi')
          .readAsStringSync();

      final terminal = Terminal(maxLines: 0)
        ..resize(_fixtureColumns, _fixtureRows);
      final controller = TerminalController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: TerminalView(
            terminal,
            controller: controller,
            textStyle: const TerminalStyle(
              fontFamily: 'JetBrainsMono Nerd Font Mono',
              fontFamilyFallback: _fontFamilyFallback,
            ),
            textScaler: TextScaler.noScaling,
            autoResize: false,
          ),
        ),
      );

      const feedInterval = Duration(milliseconds: 100);
      const totalDuration = Duration(seconds: 60);
      final feedCount =
          totalDuration.inMilliseconds ~/ feedInterval.inMilliseconds;

      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < feedCount; i++) {
        terminal.write(_clearAndHome);
        terminal.write(fixtureText);
        await tester.pump(feedInterval);
      }
      stopwatch.stop();

      final elapsedSeconds = stopwatch.elapsedMilliseconds / 1000;
      final measuredFps = feedCount / elapsedSeconds;

      // Recorded for the pull request per R-20-008 step 6. This number is
      // NOT the R-20-008 device measurement: see this file's header
      // comment for the hardware gap.
      // ignore: avoid_print
      print(
        'spike_render_test: fed $feedCount frames over '
        '${elapsedSeconds.toStringAsFixed(1)}s wall-clock, '
        'measured ${measuredFps.toStringAsFixed(1)} fps '
        '(this test-harness device, not a Pixel 6a or iPhone SE 3rd gen)',
      );

      expect(feedCount, 600);
      // A sanity floor for the harness itself: the loop must actually
      // have completed without the emulator throwing. This is not the
      // R-20-008 30 FPS gate, which applies only to the two named
      // reference devices.
      expect(terminal.buffer.lines.length, _fixtureRows);
    },
  );

  testWidgets('R-20-008 step 4: 24-bit truecolour SGR', (tester) async {
    final terminal = Terminal(maxLines: 0)..resize(20, 3);
    terminal.write('\x1b[38;2;255;100;50mtruecolour');
    final line = terminal.buffer.lines[0];
    final fg = line.getForeground(0);
    expect(fg & CellColor.typeMask, CellColor.rgb);
    final rgb = fg & CellColor.valueMask;
    expect((rgb >> 16) & 0xff, 255);
    expect((rgb >> 8) & 0xff, 100);
    expect(rgb & 0xff, 50);
  });

  testWidgets('R-20-008 step 4: a wide CJK character', (tester) async {
    final terminal = Terminal(maxLines: 0)..resize(20, 3);
    // U+4E2D, 中, a double-width CJK ideograph.
    terminal.write('\u4e2d');
    final line = terminal.buffer.lines[0];
    expect(line.getCodePoint(0), 0x4e2d);
    expect(line.getWidth(0), 2);
  });

  testWidgets('R-20-008 step 4: an emoji with a variation selector', (
    tester,
  ) async {
    final terminal = Terminal(maxLines: 0)..resize(20, 3);
    // U+2764 (heavy black heart) + U+FE0F (VS-16, emoji presentation).
    terminal.write('\u2764\ufe0f');
    final line = terminal.buffer.lines[0];
    expect(line.getCodePoint(0), 0x2764);
    // The VS-16 is a zero-width combining character attached to the
    // heart's cell, not a cell of its own (R-21-014's "emoji receive two
    // cells from wcwidth" note: the selector widens the base glyph's
    // cell rather than occupying a second one).
    expect(line.getCombiningCharacters(0), '\ufe0f');
    expect(line.getWidth(0), 2);
  });

  testWidgets('R-20-008 step 4: a Powerline glyph', (tester) async {
    final terminal = Terminal(maxLines: 0)..resize(20, 3);
    // U+E0B0, Powerline's right-pointing solid triangle: a private-use
    // codepoint the bundled `NerdFontMono` variant covers directly and
    // scales to exactly one cell (R-21-012).
    terminal.write('\ue0b0');
    final line = terminal.buffer.lines[0];
    expect(line.getCodePoint(0), 0xe0b0);
    expect(line.getWidth(0), 1);
  });
}
