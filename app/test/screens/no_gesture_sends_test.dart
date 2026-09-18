/// Proves R-30-300 ("No gesture on the grid MUST ever send a byte to the pane") across
/// every gesture shape the terminal screen's grid actually recognises, beyond the plain
/// single tap `single_tap_sends_nothing_test.dart` (`WP-16-b`) already covers: a long
/// press, a double tap, and a horizontal/vertical drag (the pan of R-21-037 and the
/// scrollback drag of `docs/31-mockups/08-terminal.md` callout 10). `docs/90-implementation-plan.md`
/// `WP-17` owns this file because R-30-300 is this package's own "every send is an explicit
/// press of a key, a chord, or the send control" boundary: the key row is the one thing on
/// this screen that is allowed to send, and every gesture below proves the grid beside it
/// still is not.
///
/// Same seam `single_tap_sends_nothing_test.dart` established: `TerminalViewWidget` is
/// built directly with a bare `xterm2` `Terminal`, and "sends nothing" is read straight off
/// `Terminal.onOutput`, the one sink every keystroke, mouse report and paste passes through.
/// `TerminalViewWidget`'s `readOnly: true` wrapping of `xterm2`'s `TerminalView` is what
/// keeps that sink silent on every gesture below, not just a tap.
library;

import 'package:flutter/widgets.dart'
    show
        Builder,
        EdgeInsets,
        MediaQuery,
        Offset,
        ValueChanged,
        ValueKey,
        VoidCallback,
        Widget;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/widgets/terminal_view_widget.dart';
import 'package:herdr_mobile/widgets/theme/app_color.dart';
import 'package:material_ui/material_ui.dart' show MaterialApp, Scaffold;
import 'package:xterm2/xterm.dart' show Terminal;

const ValueKey<String> _gridKey = ValueKey<String>('terminalGridArea');

Future<List<String>> _pumpGrid(
  WidgetTester tester, {
  VoidCallback? onForceRead,
  ValueChanged<double?>? onPinchTextSize,
  void Function(({int first, int last})?)? onVisibleColumnsChanged,
  EdgeInsets? viewPadding,
}) async {
  final List<String> sentToPane = <String>[];
  // A grid wider than the default test viewport (per R-21-038's `viewWidth` contract) at an
  // explicit ladder size, so a horizontal pan (R-21-037) has somewhere to go — the corrected
  // R-21-008 (2026-09-08) fits every column at the default size, which would leave the pan
  // unbound — and a positive scroll offset from `pane.layout` so the vertical scrollback
  // gesture attaches (`TerminalViewWidget`'s own `maxScrollOffsetFromBottom` gate).
  final Terminal terminal = Terminal(maxLines: 0, onOutput: sentToPane.add)
    ..resize(400, 24);

  Widget body = TerminalViewWidget(
    key: const ValueKey<String>('grid'),
    palette: AppColor.dark,
    phase: TerminalGridPhase.live,
    terminal: terminal,
    textSize: 18,
    maxScrollOffsetFromBottom: 50,
    onForceRead: onForceRead,
    onPinchTextSize: onPinchTextSize,
    onVisibleColumnsChanged: onVisibleColumnsChanged,
  );
  if (viewPadding != null) {
    final Widget inner = body;
    body = Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(padding: viewPadding, viewPadding: viewPadding),
        child: inner,
      ),
    );
  }
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
  return sentToPane;
}

void main() {
  testWidgets('a long press on the grid sends nothing (R-30-300)', (
    WidgetTester tester,
  ) async {
    final List<String> sentToPane = await _pumpGrid(tester);

    await tester.longPress(find.byKey(_gridKey));
    await tester.pumpAndSettle();

    expect(
      sentToPane,
      isEmpty,
      reason: 'a long press MUST NOT send a byte to the pane',
    );
  });

  testWidgets('a double tap on the grid sends nothing (R-30-300)', (
    WidgetTester tester,
  ) async {
    final List<String> sentToPane = await _pumpGrid(tester);

    await tester.tap(find.byKey(_gridKey));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(_gridKey));
    await tester.pumpAndSettle();

    expect(
      sentToPane,
      isEmpty,
      reason: 'a double tap MUST NOT send a byte to the pane',
    );
  });

  testWidgets(
    'a horizontal drag on the grid sends nothing (R-30-300, R-21-037)',
    (WidgetTester tester) async {
      final List<String> sentToPane = await _pumpGrid(tester);

      await tester.drag(find.byKey(_gridKey), const Offset(-120, 0));
      await tester.pumpAndSettle();

      expect(
        sentToPane,
        isEmpty,
        reason:
            'a horizontal pan drag MUST NOT send a byte to the pane, only move the '
            'window (R-21-037)',
      );
    },
  );

  testWidgets('a vertical drag on the grid sends nothing (R-30-300)', (
    WidgetTester tester,
  ) async {
    final List<String> sentToPane = await _pumpGrid(tester);

    await tester.drag(find.byKey(_gridKey), const Offset(0, 120));
    await tester.pumpAndSettle();

    expect(
      sentToPane,
      isEmpty,
      reason: 'a vertical scrollback drag MUST NOT send a byte to the pane',
    );
  });

  testWidgets('a force-read pull from the top fires the read callback and sends nothing to the pane '
      '(R-30-300)', (WidgetTester tester) async {
    var forceReads = 0;
    final List<String> sentToPane = await _pumpGrid(
      tester,
      onForceRead: () => forceReads++,
    );

    final topLeft = tester.getTopLeft(find.byKey(_gridKey));
    final pull = await tester.startGesture(topLeft + const Offset(150, 10));
    await pull.moveBy(const Offset(0, 60));
    await tester.pump();
    await pull.up();
    await tester.pump();

    expect(forceReads, 1, reason: 'the pull asks for one read');
    expect(
      sentToPane,
      isEmpty,
      reason: 'the force-read pull MUST NOT send a byte to the pane',
    );
  });

  testWidgets(
    'a pinch reports the exact scaled size and sends nothing to the pane (R-30-300, R-30-302)',
    (WidgetTester tester) async {
      final sizes = <double?>[];
      final List<String> sentToPane = await _pumpGrid(
        tester,
        onPinchTextSize: sizes.add,
      );

      // Two fingers down, one moves 50 px: the span grows 100 -> 150,
      // scale 1.5, applied to the painted 18px size.
      final a = await tester.startGesture(const Offset(350, 300));
      final b = await tester.startGesture(const Offset(450, 300));
      await tester.pump();
      await a.moveBy(const Offset(-50, 0));
      await tester.pump();
      await a.up();
      await b.up();
      await tester.pump();

      expect(sizes, [27.0]);
      expect(
        sentToPane,
        isEmpty,
        reason: 'a pinch MUST NOT send a byte to the pane',
      );
    },
  );

  testWidgets('a pointer down in the cutout-inset band reaches the force-read and the pan '
      '(R-21-039)', (WidgetTester tester) async {
    var forceReads = 0;
    ({int first, int last})? window;
    final List<String> sentToPane = await _pumpGrid(
      tester,
      // The 50 px top inset of R-21-039: no cell paints in the band, but the
      // band is grid background and the grid's gestures accept it (the
      // 2026-09-03 note beside R-21-040).
      viewPadding: const EdgeInsets.only(top: 50),
      onForceRead: () => forceReads++,
      onVisibleColumnsChanged: (value) => window = value,
    );

    final topLeft = tester.getTopLeft(find.byKey(_gridKey));
    // Ten pixels into the band: above the first cell row, inside the grid's
    // background.
    final pull = await tester.startGesture(topLeft + const Offset(150, 10));
    await pull.moveBy(const Offset(0, 60));
    await tester.pump();
    await pull.up();
    await tester.pump();

    expect(forceReads, 1, reason: 'the force-read pull may start in the band');

    await tester.dragFrom(
      topLeft + const Offset(150, 10),
      const Offset(-120, 0),
    );
    await tester.pump();
    expect(
      window?.first,
      greaterThan(1),
      reason: 'the horizontal pan may start in the band',
    );
    expect(sentToPane, isEmpty, reason: 'R-30-300: neither sent a byte');
  });
}
