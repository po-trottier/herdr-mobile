/// Golden tests cover the terminal grid, status strip, composer, and key panel.
/// The key panel overlays the grid above the composer, as in TerminalScreen.
/// Screen tests cover the platform app bar and merged landscape bar.
/// Cases cover dark and light themes, panel-open state, and three text lines.
/// The portrait reference size is 375 x 667 logical pixels at scale 1.0.
/// Landscape cases swap these dimensions.
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart' show AdaptiveTextSelectionToolbar;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/models/messages/send_input_ack.dart'
    show SendInputAck;
import 'package:herdr_mobile/models/messages/theme_palette.dart';
import 'package:herdr_mobile/widgets/composer.dart';
import 'package:herdr_mobile/widgets/key_row.dart' show KeyRow;
import 'package:herdr_mobile/widgets/status_strip.dart';
import 'package:herdr_mobile/widgets/terminal_view_widget.dart';
import 'package:herdr_mobile/widgets/theme/app_color.dart';
import 'package:material_ui/material_ui.dart' show AppBar, Material;
import 'package:xterm2/xterm.dart'
    show CellOffset, Terminal, TerminalController;

import '../screens/golden_support.dart' show goldenApp, loadAppFonts;

const double _referenceWidth = 375;
const double _referenceHeight = 667;

/// A realistic agent-session transcript matching `08-terminal.md`'s own
/// portrait wireframe, through real ANSI SGR (bold agent name, a cyan
/// tool call, a green diff count) so the terminal palette paints
/// non-default ink, not just `color.term.fg`.
const _sampleFeed =
    '\x1b[37;1H'
    '  Passed!  Failed: 0, Passed: 412\r\n'
    '\r\n'
    '\x1b[1m* claude\x1b[0m\r\n'
    '| I will add the missing test for\r\n'
    '| the socket reconnect path.\r\n'
    '|\r\n'
    '| \x1b[36m> Read\x1b[0m  socket_test.dart\r\n'
    '|   \x1b[32m+ 34 lines\x1b[0m\r\n'
    '|\r\n'
    '| Waiting for your approval:\r\n'
    '| Allow write to socket_test.dart?\r\n'
    '|   1. Yes  2. Always  3. No\r\n'
    '\r\n'
    '> ';

/// A 240-row build log gives the scrolled case a real vertical extent.
String _scrollableFeed() => List.generate(
  240,
  (i) => 'socket_test.dart:${i + 1}: connection retry attempt ${i % 5}',
).join('\r\n');

Terminal _terminal({String feed = _sampleFeed}) {
  final terminal = Terminal(maxLines: 1000)..resize(144, 50);
  terminal.write(feed);
  return terminal;
}

Widget _harness({
  required Widget child,
  required Brightness brightness,
  required double width,
  required double height,
}) => goldenApp(
  brightness: brightness,
  child: Material(
    child: SizedBox(width: width, height: height, child: child),
  ),
);

const _bodyKey = ValueKey('terminalGoldenBody');

/// The key row as `terminal_screen.dart` composes it, with a dead sender:
/// the golden proves the visual unit, never a send.
Widget _keyRow({
  required FocusNode focus,
  required bool enabled,
  required bool panelOpen,
  required Widget grid,
  required VoidCallback onTogglePanel,
  bool landscape = false,
}) => KeyRow(
  panelOpen: panelOpen,
  grid: grid,
  focusNode: focus,
  composer: Composer(
    focusNode: focus,
    enabled: enabled,
    panelOpen: panelOpen,
    onTogglePanel: onTogglePanel,
    onText: (_) {},
    onDelete: (_) {},
    onSubmit: () {},
  ),
  paneId: 'w3:p1',
  send: (message, {corr}) {},
  sendInputAcks: const Stream<SendInputAck>.empty(),
  landscape: landscape,
);

/// The grid, the strip and the key row, exactly as `terminal_screen.dart`
/// composes them below its app bar in portrait. In landscape (the strip
/// gone, the key row promoted) this builds the screen's own landscape
/// branch: grid over the landscape key row, no strip.
Widget _body({
  required AppColor color,
  required TerminalGridPhase phase,
  ValueNotifier<ThemePalette?>? hostTheme,
  Terminal? terminal,
  TerminalController? controller,
  String? errorText,
  String? hostName,
  DateTime? captureTime,
  int? reconnectAttempt,
  bool truncatedAtTop = false,
  int maxScrollOffsetFromBottom = 0,
  StatusStripLinkWord linkWord = StatusStripLinkWord.live,
  int columns = 144,
  int rows = 50,
  int revision = 41822,
  int scrollOffsetFromBottom = 0,
  bool landscape = false,
}) {
  final header = AppBar(
    backgroundColor: color.bgBase,
    elevation: 0,
    title: const Text('Agent session'),
  );
  var overview = false;
  var panelOpen = false;
  final FocusNode focus = FocusNode();
  addTearDown(focus.dispose);
  ({int first, int last})? window;
  return StatefulBuilder(
    builder: (context, setState) => Column(
      key: _bodyKey,
      children: [
        if (hostTheme != null)
          SizedBox.fromSize(size: header.preferredSize, child: header),
        Expanded(
          child: _keyRow(
            focus: focus,
            enabled: phase == TerminalGridPhase.live,
            panelOpen: panelOpen,
            onTogglePanel: () => setState(() => panelOpen = !panelOpen),
            landscape: landscape,
            grid: Column(
              children: [
                Expanded(
                  child: TerminalViewWidget(
                    palette: color,
                    hostTheme: hostTheme,
                    phase: phase,
                    terminal: terminal,
                    controller: controller,
                    errorText: errorText,
                    hostName: hostName,
                    captureTime: captureTime,
                    reconnectAttempt: reconnectAttempt,
                    truncatedAtTop: truncatedAtTop,
                    onDismissTruncated: () {},
                    maxScrollOffsetFromBottom: maxScrollOffsetFromBottom,
                    overview: overview,
                    onVisibleColumnsChanged: (value) =>
                        setState(() => window = value),
                  ),
                ),
                if (!landscape)
                  StatusStrip(
                    columns: columns,
                    rows: rows,
                    linkWord: linkWord,
                    revision: revision,
                    scrollOffsetFromBottom: scrollOffsetFromBottom,
                    scrollMaxOffsetFromBottom: maxScrollOffsetFromBottom,
                    firstVisibleColumn: window?.first,
                    lastVisibleColumn: window?.last,
                    overview: overview,
                    onToggleOverview: () =>
                        setState(() => overview = !overview),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

const _themes = <(String, Brightness)>[
  ('dark', Brightness.dark),
  ('light', Brightness.light),
];

Future<void> _goldenCase(
  WidgetTester tester, {
  required String name,
  required Brightness brightness,
  required Widget body,
  double width = _referenceWidth,
  double height = _referenceHeight,
  Future<void> Function(WidgetTester)? settle,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    _harness(brightness: brightness, width: width, height: height, child: body),
  );
  if (settle != null) {
    await settle(tester);
  } else {
    await tester.pump();
  }
  await tester.pump();

  await expectLater(
    find.byKey(_bodyKey),
    matchesGoldenFile('goldens/terminal_view_${name}_${brightness.name}.png'),
  );
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('native iOS pill ${brightness.name}', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await loadAppFonts();
      await _goldenCase(
        tester,
        name: 'scrolled_ios',
        brightness: brightness,
        body: _body(
          color: AppColor.resolve(brightness),
          phase: TerminalGridPhase.live,
          terminal: _terminal(feed: _scrollableFeed())..resize(144, 240),
          maxScrollOffsetFromBottom: 240,
          linkWord: StatusStripLinkWord.paused,
          scrollOffsetFromBottom: 120,
        ),
        settle: (t) async {
          await t.pump();
          final scrollable = t.widget<Scrollable>(
            find.descendant(
              of: find.byKey(const ValueKey('terminalGridArea')),
              matching: find.byType(Scrollable),
            ),
          );
          scrollable.controller!.jumpTo(
            scrollable.controller!.position.maxScrollExtent - 50,
          );
          await t.pump();
          expect(find.text('to bottom'), findsOneWidget);
        },
      );
      debugDefaultTargetPlatformOverride = null;
    });
    testWidgets('native iOS truncated strip ${brightness.name}', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await loadAppFonts();
      await _goldenCase(
        tester,
        name: 'truncated_ios',
        brightness: brightness,
        body: _body(
          color: AppColor.resolve(brightness),
          phase: TerminalGridPhase.live,
          terminal: _terminal(),
          truncatedAtTop: true,
        ),
      );
      debugDefaultTargetPlatformOverride = null;
    });
  }
  testWidgets(
    'themed_vesper follows the Host without changing chrome (R-21-044)',
    (tester) async {
      final theme = ValueNotifier<ThemePalette?>(
        const ThemePalette(
          name: 'vesper',
          accent: '#8A9A7B',
          panelBg: '#101010',
          surface0: '#1C1C1C',
          surface1: '#282828',
          surfaceDim: '#101010',
          overlay0: '#505050',
          overlay1: '#606060',
          text: '#D0D0D0',
          subtext0: '#909090',
          mauve: '#8A9A7B',
          green: '#8A9A7B',
          yellow: '#D0A050',
          red: '#C05050',
          blue: '#6080A0',
          teal: '#70A0A0',
          peach: '#D08050',
        ),
      );
      addTearDown(theme.dispose);
      await _goldenCase(
        tester,
        name: 'themed_vesper',
        brightness: Brightness.dark,
        body: _body(
          color: AppColor.resolve(Brightness.dark),
          phase: TerminalGridPhase.live,
          terminal: _terminal(),
          hostTheme: theme,
        ),
      );
    },
  );
  setUpAll(loadAppFonts);

  for (final (themeName, brightness) in _themes) {
    final color = AppColor.resolve(brightness);

    for (final variant in <String>['panel_open', 'three_line']) {
      testWidgets('$variant ($themeName) matches the composer layout', (
        tester,
      ) async {
        await _goldenCase(
          tester,
          name: variant,
          brightness: brightness,
          body: _body(
            color: color,
            phase: TerminalGridPhase.live,
            terminal: _terminal(),
          ),
          settle: (t) async {
            if (variant == 'panel_open') {
              await t.tap(find.byKey(const ValueKey<String>('composerMore')));
            } else {
              await t.enterText(
                find.byType(EditableText),
                'First line\nSecond line\nThird line',
              );
              t
                  .widget<EditableText>(find.byType(EditableText))
                  .focusNode
                  .unfocus();
            }
            await t.pump(const Duration(milliseconds: 600));
          },
        );
      });
    }

    testWidgets('live ($themeName) matches docs/31-mockups/08-terminal.md', (
      tester,
    ) async {
      await _goldenCase(
        tester,
        name: 'live',
        brightness: brightness,
        body: _body(
          color: color,
          phase: TerminalGridPhase.live,
          terminal: _terminal(),
        ),
      );
      expect(find.text('Overview').hitTestable(), findsOneWidget);
      // The strip is one `Text.rich`; the `space.3` gap between two readouts
      // is a `WidgetSpan`, U+FFFC in the plain text.
      expect(
        find.textContaining(RegExp('144x50\uFFFCc1-\\d+')),
        findsOneWidget,
      );
    });

    testWidgets(
      'overview ($themeName) shows the full grid and the Readable control',
      (tester) async {
        await _goldenCase(
          tester,
          name: 'overview',
          brightness: brightness,
          body: _body(
            color: color,
            phase: TerminalGridPhase.live,
            terminal: _terminal(),
          ),
          settle: (t) async {
            await t.pump();
            await t.tap(find.byKey(const ValueKey('terminalOverviewToggle')));
            await t.pump();
            await t.pump();
            await t.pump(const Duration(milliseconds: 400));
          },
        );
        expect(find.text('Readable').hitTestable(), findsOneWidget);
        expect(find.textContaining('144x50'), findsOneWidget);
        expect(find.textContaining(RegExp(r'c\d+-\d+')), findsNothing);
      },
    );

    testWidgets(
      'loadingFirstPaint ($themeName) matches docs/31-mockups/08-terminal.md',
      (tester) async {
        await _goldenCase(
          tester,
          name: 'loading_first_paint',
          brightness: brightness,
          body: _body(
            color: color,
            phase: TerminalGridPhase.loadingFirstPaint,
            linkWord: StatusStripLinkWord.offline,
            columns: 0,
            rows: 0,
            revision: 0,
          ),
          settle: (t) => t.pump(const Duration(milliseconds: 200)),
        );
        expect(find.text('Reading pane...'), findsOneWidget);
      },
    );

    testWidgets(
      'loadingReconnecting ($themeName) matches docs/31-mockups/08-terminal.md',
      (tester) async {
        await _goldenCase(
          tester,
          name: 'loading_reconnecting',
          brightness: brightness,
          body: _body(
            color: color,
            phase: TerminalGridPhase.loadingReconnecting,
            terminal: _terminal(),
            reconnectAttempt: 3,
            linkWord: StatusStripLinkWord.offline,
          ),
        );
        expect(find.text('Reconnecting... try 3'), findsOneWidget);
      },
    );

    testWidgets(
      'paneGone ($themeName) matches docs/31-mockups/08-terminal.md',
      (tester) async {
        await _goldenCase(
          tester,
          name: 'pane_gone',
          brightness: brightness,
          body: _body(
            color: color,
            phase: TerminalGridPhase.paneGone,
            terminal: _terminal(),
            linkWord: StatusStripLinkWord.offline,
          ),
        );
        // R-03-119: the widget's part of this state is the dim alone; the
        // alert is the screen's (`terminal_screen_test.dart`).
        expect(find.text('This pane closed.'), findsNothing);
      },
    );

    testWidgets(
      'readFailed ($themeName) matches docs/31-mockups/08-terminal.md',
      (tester) async {
        await _goldenCase(
          tester,
          name: 'read_failed',
          brightness: brightness,
          body: _body(
            color: color,
            phase: TerminalGridPhase.readFailed,
            terminal: _terminal(),
            errorText: 'pane_not_found: w3:p1 no longer exists',
            linkWord: StatusStripLinkWord.offline,
          ),
        );
        expect(find.text('Could not read this pane.'), findsNothing);
        expect(
          find.text('pane_not_found: w3:p1 no longer exists'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'protocolMismatch ($themeName) matches docs/31-mockups/08-terminal.md',
      (tester) async {
        await _goldenCase(
          tester,
          name: 'protocol_mismatch',
          brightness: brightness,
          body: _body(
            color: color,
            phase: TerminalGridPhase.protocolMismatch,
            terminal: _terminal(),
            hostName: 'patrick-desk',
            linkWord: StatusStripLinkWord.offline,
          ),
        );
        expect(
          find.text('Update Herdr on patrick-desk, or update this app.'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'hostInUse ($themeName) matches docs/31-mockups/08-terminal.md',
      (tester) async {
        await _goldenCase(
          tester,
          name: 'host_in_use',
          brightness: brightness,
          body: _body(
            color: color,
            phase: TerminalGridPhase.hostInUse,
            terminal: _terminal(),
            linkWord: StatusStripLinkWord.hostInUse,
          ),
        );
        expect(find.text('Another phone is using this pane.'), findsOneWidget);
      },
    );

    testWidgets('offline ($themeName) matches docs/31-mockups/08-terminal.md', (
      tester,
    ) async {
      await _goldenCase(
        tester,
        name: 'offline',
        brightness: brightness,
        body: _body(
          color: color,
          phase: TerminalGridPhase.offline,
          terminal: _terminal(),
          errorText: 'No network.',
          hostName: 'patrick-desk',
          captureTime: DateTime(2026, 8, 31, 14, 2),
          linkWord: StatusStripLinkWord.offline,
        ),
      );
      expect(find.text('No network.'), findsOneWidget);
      expect(
        find.text('This is patrick-desk as it was at 14:02.'),
        findsOneWidget,
      );
    });

    testWidgets('revoked ($themeName) matches docs/31-mockups/08-terminal.md', (
      tester,
    ) async {
      await _goldenCase(
        tester,
        name: 'revoked',
        brightness: brightness,
        body: _body(
          color: color,
          phase: TerminalGridPhase.revoked,
          terminal: _terminal(),
          linkWord: StatusStripLinkWord.offline,
        ),
      );
      expect(
        find.text('Connection lost — this device has been revoked'),
        findsOneWidget,
      );
    });

    testWidgets(
      'scrolled ($themeName) matches docs/31-mockups/08-terminal.md',
      (tester) async {
        // The scrollback buffer remains taller than the grid at readable size.
        final terminal = _terminal(feed: _scrollableFeed())..resize(144, 240);
        await _goldenCase(
          tester,
          name: 'scrolled',
          brightness: brightness,
          body: _body(
            color: color,
            phase: TerminalGridPhase.live,
            terminal: terminal,
            maxScrollOffsetFromBottom: 240,
            linkWord: StatusStripLinkWord.paused,
            scrollOffsetFromBottom: 120,
          ),
          settle: (t) async {
            await t.pump();
            // Same technique as `terminal_isolated_test.dart`'s own
            // scrolled-pill case: drive the grid's own `Scrollable`
            // directly, deterministically, rather than a drag gesture.
            // The key row holds its own horizontal Scrollables; take the
            // grid's.
            final scrollable = t.widget<Scrollable>(
              find.descendant(
                of: find.byKey(const ValueKey('terminalGridArea')),
                matching: find.byType(Scrollable),
              ),
            );
            final bottom = scrollable.controller!.position.maxScrollExtent;
            scrollable.controller!.jumpTo(bottom - 50);
            await t.pump();
          },
        );
        expect(find.text('to bottom'), findsOneWidget);
      },
    );

    testWidgets(
      'selection ($themeName) matches docs/31-mockups/08-terminal.md',
      (tester) async {
        final terminal = _terminal();
        final controller = TerminalController();
        addTearDown(controller.dispose);
        await _goldenCase(
          tester,
          name: 'selection',
          brightness: brightness,
          body: _body(
            color: color,
            phase: TerminalGridPhase.live,
            terminal: terminal,
            controller: controller,
            linkWord: StatusStripLinkWord.paused,
          ),
          settle: (t) async {
            await t.pump();
            final base = terminal.buffer.createAnchorFromOffset(
              CellOffset(2, terminal.viewHeight - 5),
            );
            final extent = terminal.buffer.createAnchorFromOffset(
              CellOffset(terminal.viewWidth - 1, terminal.viewHeight - 4),
            );
            controller.setSelection(base, extent);
            await t.pump();
          },
        );
        expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
      },
    );

    testWidgets(
      'truncated ($themeName) matches docs/31-mockups/08-terminal.md',
      (tester) async {
        await _goldenCase(
          tester,
          name: 'truncated',
          brightness: brightness,
          body: _body(
            color: color,
            phase: TerminalGridPhase.live,
            terminal: _terminal(),
            truncatedAtTop: true,
          ),
        );
        expect(
          find.textContaining('This is the most recent output.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'landscape ($themeName) matches docs/31-mockups/08-terminal.md',
      (tester) async {
        await _goldenCase(
          tester,
          name: 'landscape',
          brightness: brightness,
          width: _referenceHeight,
          height: _referenceWidth,
          // The mockup's landscape branch: no strip, the key row promoted
          // (the merged app bar and its window readout are screen chrome,
          // covered in `terminal_screen_test.dart`).
          body: _body(
            color: color,
            phase: TerminalGridPhase.live,
            terminal: _terminal(),
            landscape: true,
          ),
        );
      },
    );
  }
}
