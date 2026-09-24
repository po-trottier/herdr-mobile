/// Proves R-31-08-08 and R-30-300's whole-app gesture rule on the one screen that draws a
/// live terminal grid: a single tap on `terminal_view_widget.dart`'s grid (`WP-16-b`) MUST
/// send nothing to the pane, and MUST only fire `onGridTap`, which `terminal_screen.dart`
/// turns into a focus request on the native composer field of R-03-130.
///
/// This file builds `TerminalViewWidget` directly with a bare `xterm2` `Terminal` and a
/// fixture `FocusNode` standing in for the composer's own focus node
/// (`composer.dart`, outside this package's `Needs.` line, per R-90-024) — the same
/// seam `WP-16-b` named for this test: `onGridTap` fires exactly what a real caller would wire
/// to a focus request, and nothing else. "Sends nothing" is read straight off
/// `Terminal.onOutput`, the one sink every keystroke, mouse report and paste passes through;
/// `TerminalViewWidget`'s `readOnly: true` wrapping of `xterm2`'s `TerminalView` is what
/// keeps that sink silent on a tap, per `xterm2`'s own `readOnly` gate on keyboard input and
/// mouse-event forwarding.
library;

import 'package:flutter/widgets.dart'
    show Column, Expanded, Focus, FocusNode, SizedBox, ValueKey, Widget;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/app.dart' show sdkMaterialLocalizations;
import 'package:herdr_mobile/widgets/terminal_view_widget.dart';
import 'package:herdr_mobile/widgets/theme/app_color.dart';
import 'package:material_ui/material_ui.dart' show MaterialApp, Scaffold;
import 'package:xterm2/xterm.dart' show Terminal;

void main() {
  testWidgets('a single tap on the grid sends nothing and only fires the keyboard request '
      '(R-31-08-08, R-30-300, R-03-054)', (WidgetTester tester) async {
    final List<String> sentToPane = <String>[];
    final Terminal terminal = Terminal(maxLines: 0, onOutput: sentToPane.add);
    final FocusNode inputFocusNode = FocusNode();
    addTearDown(inputFocusNode.dispose);
    var gridTapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: sdkMaterialLocalizations,
        home: Scaffold(
          body: Column(
            children: <Widget>[
              Expanded(
                child: TerminalViewWidget(
                  palette: AppColor.dark,
                  phase: TerminalGridPhase.live,
                  terminal: terminal,
                  onGridTap: () {
                    gridTapCount++;
                    inputFocusNode.requestFocus();
                  },
                ),
              ),
              // A fixture standing in for the key row's hidden text input client (Phase
              // 17): only its `FocusNode` matters to this test, per the seam `WP-16-b` named.
              Focus(focusNode: inputFocusNode, child: const SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );

    expect(inputFocusNode.hasFocus, isFalse);
    expect(gridTapCount, 0);

    await tester.tap(find.byKey(const ValueKey('terminalGridArea')));
    await tester.pump();

    expect(
      sentToPane,
      isEmpty,
      reason: 'a grid tap MUST send nothing to the pane',
    );
    expect(
      gridTapCount,
      1,
      reason: 'the tap MUST reach onGridTap exactly once',
    );
    expect(
      inputFocusNode.hasFocus,
      isTrue,
      reason: 'the tap MUST reach the focus request the caller wired',
    );
  });
}
