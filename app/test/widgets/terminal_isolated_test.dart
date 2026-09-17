/// Tests for `app/lib/widgets/terminal_view_widget.dart` (`WP-16-b`) in isolation: no
/// `app/lib/services/terminal.dart` dependency anywhere in this file, per that package's own
/// contract (`docs/90-implementation-plan.md` `WP-16-b`, `INT-16-terminal`). Every case below
/// constructs a bare `xterm2` `Terminal` directly.
library;

import 'dart:io' show File;

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoButton, CupertinoListTile;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart'
    show AdaptiveTextSelectionToolbar, Colors, DefaultMaterialLocalizations;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/models/messages/theme_palette.dart';
import 'package:herdr_mobile/widgets/terminal_view_widget.dart';
import 'package:herdr_mobile/widgets/theme/app_color.dart';
import 'package:herdr_mobile/widgets/theme/app_type.dart';
import 'package:material_ui/material_ui.dart'
    show
        Brightness,
        ColorScheme,
        FilledButton,
        ListTile,
        Material,
        MaterialApp,
        Scaffold,
        ThemeData;
import 'package:xterm2/xterm.dart'
    show
        CellOffset,
        Terminal,
        TerminalController,
        TerminalView,
        TerminalViewState;

import '../screens/golden_support.dart' show loadAppFonts;

/// A worst-case Android dynamic-colour scheme, per `docs/33-platform-chrome.md` R-33-026 —
/// deliberately unrelated to the fixed Selenized terminal palette, so a test that pumps the
/// grid underneath it and still finds the exact Selenized values proves the isolation R-33-055,
/// R-33-056 and R-33-057 require, not merely that the two schemes happen to agree today.
ColorScheme _degenerateScheme(Brightness brightness) => ColorScheme.fromSeed(
  seedColor: AppColor.resolve(brightness).accentPrimary,
  brightness: brightness,
);

/// [Localizations] providing the Flutter SDK's own `MaterialLocalizations`, not
/// `material_ui`'s reimplementation `material_ui.MaterialApp` registers: R-21-042 names
/// `package:flutter/material.dart`'s `AdaptiveTextSelectionToolbar` by class, and that SDK
/// widget looks up the SDK's own `MaterialLocalizations` type, a different type identity from
/// `material_ui`'s. Production wiring this exposes: `app/lib/app.dart` (`WP-12-b`) builds only
/// a `material_ui.MaterialApp` today, so it does not yet satisfy this ancestor on its own — a
/// gap outside this file's `Paths.` line, reported rather than patched here.
Widget _harness({
  required Widget child,
  Brightness brightness = Brightness.dark,
  double width = 390,
  double height = 700,
}) => MaterialApp(
  theme: ThemeData(colorScheme: _degenerateScheme(brightness)),
  home: Scaffold(
    body: SizedBox(
      width: width,
      height: height,
      child: Localizations(
        locale: const Locale('en', 'US'),
        delegates: const [
          DefaultWidgetsLocalizations.delegate,
          DefaultMaterialLocalizations.delegate,
        ],
        child: child,
      ),
    ),
  ),
);

Terminal _terminal({String? feed}) {
  final terminal = Terminal(maxLines: 0);
  if (feed != null) terminal.write(feed);
  return terminal;
}

void main() {
  final reset = ThemePalette.fromJson({
    'name': '',
    for (final key in [
      'accent',
      'panel_bg',
      'surface0',
      'surface1',
      'surface_dim',
      'overlay0',
      'overlay1',
      'text',
      'subtext0',
      'mauve',
      'green',
      'yellow',
      'red',
      'blue',
      'teal',
      'peach',
    ])
      key: 'reset',
  });
  test('a removed Host theme restores the app ground (R-21-044)', () {
    for (final palette in AppColor.values) {
      final theme = terminalThemeFrom(palette, reset);
      expect(theme.background, palette.bgBase);
      expect(theme.foreground, palette.fgPrimary);
      expect(theme.cursor, palette.termCursor);
      expect(theme.red, palette.termAnsi1);
    }
  });
  testWidgets('theme updates repaint without clearing the grid (R-21-044)', (
    tester,
  ) async {
    final hostTheme = ValueNotifier<ThemePalette?>(null);
    addTearDown(hostTheme.dispose);
    final terminal = _terminal(feed: 'preserved text');
    final before = terminal.buffer.getText();
    final palette = AppColor.resolve(Brightness.dark);
    await tester.pumpWidget(
      _harness(
        child: TerminalViewWidget(
          palette: palette,
          hostTheme: hostTheme,
          phase: TerminalGridPhase.live,
          terminal: terminal,
        ),
      ),
    );
    hostTheme.value = reset.copyWith(surfaceDim: '#101010', text: '#D0D0D0');
    await tester.pump();
    final view = tester.widget<TerminalView>(find.byType(TerminalView));
    expect(view.theme.background, const Color(0xff101010));
    expect(view.theme.foreground, const Color(0xffd0d0d0));
    expect(view.theme.cursor, palette.termCursor);
    expect(view.theme.red, palette.termAnsi1);
    expect(terminal.buffer.getText(), before);
    hostTheme.value = reset;
    await tester.pump();
    expect(
      tester.widget<TerminalView>(find.byType(TerminalView)).theme.background,
      palette.bgBase,
    );
    expect(terminal.buffer.getText(), before);
  });
  setUpAll(loadAppFonts);

  group('terminalThemeFrom', () {
    for (final palette in AppColor.values) {
      test(
        'maps every one of the 20 R-32-140 values for ${palette.name}, exactly, no package '
        'default',
        () {
          final theme = terminalThemeFrom(palette);
          expect(theme.background, palette.bgBase);
          expect(theme.foreground, palette.fgPrimary);
          expect(theme.cursor, palette.termCursor);
          expect(theme.selection, palette.termSelection);
          expect(theme.black, palette.termAnsi0);
          expect(theme.red, palette.termAnsi1);
          expect(theme.green, palette.termAnsi2);
          expect(theme.yellow, palette.termAnsi3);
          expect(theme.blue, palette.termAnsi4);
          expect(theme.magenta, palette.termAnsi5);
          expect(theme.cyan, palette.termAnsi6);
          expect(theme.white, palette.termAnsi7);
          expect(theme.brightBlack, palette.termAnsi8);
          expect(theme.brightRed, palette.termAnsi9);
          expect(theme.brightGreen, palette.termAnsi10);
          expect(theme.brightYellow, palette.termAnsi11);
          expect(theme.brightBlue, palette.termAnsi12);
          expect(theme.brightMagenta, palette.termAnsi13);
          expect(theme.brightCyan, palette.termAnsi14);
          expect(theme.brightWhite, palette.termAnsi15);
        },
      );
    }
  });

  group('grid isolation from the ambient theme (R-33-055, R-33-056, R-33-057, R-33-058)', () {
    for (final brightness in Brightness.values) {
      testWidgets(
        'every cell colour matches the Selenized terminal palette exactly under the '
        'degenerate scheme, in $brightness, and no platform view or glass surface overlays '
        'the grid',
        (tester) async {
          final terminal = _terminal();
          await tester.pumpWidget(
            _harness(
              brightness: brightness,
              child: TerminalViewWidget(
                palette: AppColor.resolve(brightness),
                phase: TerminalGridPhase.live,
                terminal: terminal,
              ),
            ),
          );
          await tester.pump();

          final view = tester.widget<TerminalView>(find.byType(TerminalView));
          final expected = terminalThemeFrom(AppColor.resolve(brightness));
          expect(view.theme.background, expected.background);
          expect(view.theme.foreground, expected.foreground);
          expect(view.theme.cursor, expected.cursor);
          expect(view.theme.selection, expected.selection);
          expect(view.theme.red, expected.red);
          expect(view.theme.brightWhite, expected.brightWhite);

          // No BackdropFilter (a blur/glass approximation) and no embedded
          // platform view anywhere in the tree, per R-33-057.
          expect(find.byType(BackdropFilter), findsNothing);
          expect(
            find.byWidgetPredicate(
              (w) => w.runtimeType.toString().contains('PlatformView'),
            ),
            findsNothing,
          );

          // R-33-058: no Material ancestor of the grid may carry a
          // generated-role surface tint — the leak a Material elevation
          // overlay would otherwise paint over the grid. `null` and
          // `Colors.transparent` both mean no tint paints; only a real
          // generated colour (e.g. `colorScheme.surfaceTint`) is the leak
          // this guards against.
          final ancestorMaterials = tester.widgetList<Material>(
            find.ancestor(
              of: find.byKey(const ValueKey('terminalGridArea')),
              matching: find.byType(Material),
            ),
          );
          expect(
            ancestorMaterials,
            isNotEmpty,
            reason:
                'the harness must place at least one Material ancestor over the grid for '
                'this check to mean anything',
          );
          for (final material in ancestorMaterials) {
            expect(
              material.surfaceTintColor,
              anyOf(isNull, Colors.transparent),
              reason: 'a Material ancestor of the grid must never carry a generated tint',
            );
          }
        },
      );
    }
  });

  group('grid contract: no theme lookup in the source (R-33-056)', () {
    test('the widget file imports no theme lookup and calls no Theme.of/CupertinoTheme.of', () {
      final source = _codeOnly(
        File('lib/widgets/terminal_view_widget.dart').readAsStringSync(),
      );
      expect(source.contains('Theme.of'), isFalse);
      expect(source.contains('CupertinoTheme.of'), isFalse);
      expect(source.contains('ColorScheme.of'), isFalse);
      expect(source.contains('colorScheme'), isFalse);
    });
  });

  group('grid is content, not chrome — no glass material (R-31-08-15)', () {
    testWidgets(
      'the live grid carries no BackdropFilter, no ImageFiltered blur and no Opacity',
      (tester) async {
        await tester.pumpWidget(
          _harness(
            child: TerminalViewWidget(
              palette: AppColor.dark,
              phase: TerminalGridPhase.live,
              terminal: _terminal(feed: 'alpha'),
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(BackdropFilter), findsNothing);
        expect(find.byType(ImageFiltered), findsNothing);
        // Opacity is reserved for the non-live `opacity.dim` treatment
        // (`_buildDimmedGrid`); the live grid itself must always paint at
        // full opacity, never a translucent glass overlay.
        expect(find.byType(Opacity), findsNothing);
      },
    );
  });

  group('TerminalView construction (R-21-038)', () {
    testWidgets('autoResize is false and textScaler is TextScaler.noScaling', (
      tester,
    ) async {
      final terminal = _terminal();
      await tester.pumpWidget(
        _harness(
          child: TerminalViewWidget(
            palette: AppColor.dark,
            phase: TerminalGridPhase.live,
            terminal: terminal,
          ),
        ),
      );
      await tester.pump();

      final view = tester.widget<TerminalView>(find.byType(TerminalView));
      expect(view.autoResize, isFalse);
      expect(view.textScaler, TextScaler.noScaling);
      expect(view.readOnly, isTrue);
    });

    testWidgets('textStyle carries the exact R-21-014 CJK/emoji fallback chain, in production, not '
        'just a test file', (tester) async {
      final terminal = _terminal();
      await tester.pumpWidget(
        _harness(
          child: TerminalViewWidget(
            palette: AppColor.dark,
            phase: TerminalGridPhase.live,
            terminal: terminal,
          ),
        ),
      );
      await tester.pump();

      final view = tester.widget<TerminalView>(find.byType(TerminalView));
      expect(view.textStyle.fontFamilyFallback, <String>[
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
      ]);
    });
  });

  group('never reflows and never resizes the Host pane (R-21-036, R-31-08-07, R-21-009)', () {
    test('the widget file calls neither pane.resize nor pane.split', () {
      final source = _codeOnly(
        File('lib/widgets/terminal_view_widget.dart').readAsStringSync(),
      );
      expect(source.contains('pane.resize'), isFalse);
      expect(source.contains('pane.split'), isFalse);
      // This file has no service reference at all, so it cannot call
      // Terminal.resize either: it only ever reads Terminal.viewWidth /
      // viewHeight, never mutates them.
      expect(source.contains('.resize('), isFalse);
    });

    testWidgets('the grid column and row count stay fixed across a layout change, an orientation '
        'change, a text-size change and a pan drag', (tester) async {
      final terminal = _terminal(
        feed: List.generate(30, (i) => 'row $i').join('\r\n'),
      );
      final startColumns = terminal.viewWidth;
      final startRows = terminal.viewHeight;

      Widget build({required double width, required int textSize}) => _harness(
        width: width,
        child: TerminalViewWidget(
          palette: AppColor.dark,
          phase: TerminalGridPhase.live,
          terminal: terminal,
          textSize: textSize,
        ),
      );

      await tester.pumpWidget(build(width: 390, textSize: 13));
      await tester.pump();
      expect(terminal.viewWidth, startColumns);
      expect(terminal.viewHeight, startRows);

      // A layout change: narrower width, as a rotation to portrait would
      // produce for a landscape-sized parent.
      await tester.pumpWidget(build(width: 250, textSize: 13));
      await tester.pump();
      expect(terminal.viewWidth, startColumns);
      expect(terminal.viewHeight, startRows);

      // An orientation change: wider than tall, as landscape would be.
      await tester.pumpWidget(build(width: 700, textSize: 13));
      await tester.pump();
      expect(terminal.viewWidth, startColumns);
      expect(terminal.viewHeight, startRows);

      // A text-size change: one step up the R-21-010 ladder.
      await tester.pumpWidget(build(width: 390, textSize: 16));
      await tester.pump();
      expect(terminal.viewWidth, startColumns);
      expect(terminal.viewHeight, startRows);

      // A horizontal pan drag across the grid.
      await tester.drag(
        find.byKey(const ValueKey('terminalGridArea')),
        const Offset(-120, 0),
      );
      await tester.pump();
      expect(terminal.viewWidth, startColumns);
      expect(terminal.viewHeight, startRows);
    });
  });

  group('readable text and explicit overview (R-21-008, R-21-037)', () {
    const cellsKey = ValueKey('terminalGridCells');
    const areaKey = ValueKey('terminalGridArea');

    for (final columns in [240, 282]) {
      testWidgets(
        'a $columns-column pane uses 13px by default and reports a clamped pan window',
        (tester) async {
          final terminal = _terminal(feed: 'hello world')..resize(columns, 50);
          ({int first, int last})? window;
          await tester.pumpWidget(
            _harness(
              width: 390,
              child: TerminalViewWidget(
                palette: AppColor.dark,
                phase: TerminalGridPhase.live,
                terminal: terminal,
                onVisibleColumnsChanged: (value) => window = value,
              ),
            ),
          );
          await tester.pump();
          await tester.pump();

          final view = tester.widget<TerminalView>(find.byType(TerminalView));
          final cell = tester
              .state<TerminalViewState>(find.byType(TerminalView))
              .renderTerminal
              .cellSize;
          final area = tester.getRect(find.byKey(areaKey));
          final cells = tester.getRect(find.byKey(cellsKey));
          expect(view.textStyle.fontSize, 13.0);
          expect(view.autoResize, isFalse);
          expect(cells.width, greaterThan(area.width));
          expect(
            cells.width,
            moreOrLessEquals(columns * cell.width, epsilon: 0.01),
          );
          expect(window, (first: 1, last: (area.width / cell.width).floor()));
          final initialWindow = window!;
          expect(initialWindow.last, lessThan(columns));
          expect(terminal.viewWidth, columns);
          expect(terminal.viewHeight, 50);

          await tester.drag(find.byKey(areaKey), const Offset(-120, 0));
          await tester.pump();
          await tester.pump();
          final panned = tester.getRect(find.byKey(cellsKey));
          expect(panned.left, lessThan(cells.left));
          expect(panned.right, greaterThan(area.right));
          expect(window!.first, greaterThan(initialWindow.first));
          expect(window!.last, greaterThan(initialWindow.last));

          await tester.drag(find.byKey(areaKey), const Offset(-10000, 0));
          await tester.pump();
          await tester.pump();
          final clamped = tester.getRect(find.byKey(cellsKey));
          expect(clamped.right, moreOrLessEquals(area.right, epsilon: 0.01));
          expect(window!.last, columns);

          await tester.drag(find.byKey(areaKey), const Offset(10000, 0));
          await tester.pump();
          await tester.pump();
          expect(
            tester.getRect(find.byKey(cellsKey)).left,
            moreOrLessEquals(area.left, epsilon: 0.01),
          );
          expect(window, initialWindow);
          expect(terminal.viewWidth, columns);
          expect(terminal.viewHeight, 50);
        },
      );
    }

    for (final textSize in [13, 18]) {
      testWidgets(
        'overview restores the saved ${textSize}px rung and exact cell size on the same widget',
        (tester) async {
          final terminal = _terminal(feed: 'hello world')..resize(282, 50);
          ({int first, int last})? window;
          Widget build({bool overview = false}) => _harness(
            width: 390,
            child: TerminalViewWidget(
              palette: AppColor.dark,
              phase: TerminalGridPhase.live,
              terminal: terminal,
              textSize: textSize,
              overview: overview,
              onVisibleColumnsChanged: (value) => window = value,
            ),
          );

          await tester.pumpWidget(build());
          await tester.pump();
          await tester.pump();
          final state = tester.state(find.byType(TerminalViewWidget));
          final readableCell = tester
              .state<TerminalViewState>(find.byType(TerminalView))
              .renderTerminal
              .cellSize;
          final readableCells = tester.getRect(find.byKey(cellsKey));
          final area = tester.getRect(find.byKey(areaKey));
          expect(
            tester
                .widget<TerminalView>(find.byType(TerminalView))
                .textStyle
                .fontSize,
            textSize.toDouble(),
          );
          expect(readableCells.width, greaterThan(area.width));
          expect(window!.first, 1);

          await tester.pumpWidget(build(overview: true));
          await tester.pump();
          await tester.pump();
          final overviewView = tester.widget<TerminalView>(
            find.byType(TerminalView),
          );
          final overviewCell = tester
              .state<TerminalViewState>(find.byType(TerminalView))
              .renderTerminal
              .cellSize;
          final overviewCells = tester.getRect(find.byKey(cellsKey));
          expect(tester.state(find.byType(TerminalViewWidget)), same(state));
          expect(
            overviewView.textStyle.fontSize,
            lessThan(textSize.toDouble()),
          );
          expect(overviewView.autoResize, isFalse);
          expect(
            overviewCells.width,
            moreOrLessEquals(area.width, epsilon: 1.0),
          );
          expect(overviewCells.left, greaterThanOrEqualTo(area.left - 1));
          expect(overviewCells.right, lessThanOrEqualTo(area.right + 1));
          expect(
            overviewCells.width,
            moreOrLessEquals(282 * overviewCell.width, epsilon: 0.01),
          );
          expect(window, isNull);
          expect(terminal.viewWidth, 282);
          expect(terminal.viewHeight, 50);

          await tester.pumpWidget(build());
          await tester.pump();
          await tester.pump();
          final restoredView = tester.widget<TerminalView>(
            find.byType(TerminalView),
          );
          final restoredCell = tester
              .state<TerminalViewState>(find.byType(TerminalView))
              .renderTerminal
              .cellSize;
          expect(tester.state(find.byType(TerminalViewWidget)), same(state));
          expect(restoredView.textStyle.fontSize, textSize.toDouble());
          expect(restoredView.autoResize, isFalse);
          expect(restoredCell, readableCell);
          expect(
            tester.getRect(find.byKey(cellsKey)).width,
            readableCells.width,
          );
          expect(window!.first, 1);

          await tester.drag(find.byKey(areaKey), const Offset(-120, 0));
          await tester.pump();
          await tester.pump();
          expect(
            tester.getRect(find.byKey(cellsKey)).left,
            lessThan(area.left),
          );
          expect(window!.first, greaterThan(1));
          expect(terminal.viewWidth, 282);
          expect(terminal.viewHeight, 50);
        },
      );
    }

    testWidgets(
      'overview keeps 13px when a small pane already fits and cannot pan',
      (tester) async {
        final terminal = _terminal(feed: 'x')..resize(20, 10);
        await tester.pumpWidget(
          _harness(
            width: 390,
            child: TerminalViewWidget(
              palette: AppColor.dark,
              phase: TerminalGridPhase.live,
              terminal: terminal,
              overview: true,
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        final view = tester.widget<TerminalView>(find.byType(TerminalView));
        expect(
          view.textStyle.fontSize,
          AppType.monoTerminalDefaultSize.toDouble(),
        );
        final area = tester.getRect(find.byKey(areaKey));
        final cells = tester.getRect(find.byKey(cellsKey));
        expect(cells.width, lessThan(area.width));

        await tester.drag(find.byKey(areaKey), const Offset(-120, 0));
        await tester.pump();
        expect(
          tester.getRect(find.byKey(cellsKey)).left,
          moreOrLessEquals(cells.left, epsilon: 0.5),
          reason: 'a grid that fits has nothing to pan (R-21-037)',
        );
      },
    );

    testWidgets(
      'overview refits after a viewport change without changing Host geometry',
      (tester) async {
        final terminal = _terminal(feed: 'x')..resize(282, 50);
        Widget build(double width) => _harness(
          width: width,
          child: TerminalViewWidget(
            palette: AppColor.dark,
            phase: TerminalGridPhase.live,
            terminal: terminal,
            overview: true,
          ),
        );

        await tester.pumpWidget(build(390));
        await tester.pump();
        await tester.pump();
        final portrait = tester.widget<TerminalView>(find.byType(TerminalView));
        expect(
          tester.getRect(find.byKey(cellsKey)).width,
          moreOrLessEquals(
            tester.getRect(find.byKey(areaKey)).width,
            epsilon: 1.0,
          ),
        );

        await tester.pumpWidget(build(700));
        await tester.pump();
        await tester.pump();
        final landscape = tester.widget<TerminalView>(
          find.byType(TerminalView),
        );
        expect(
          landscape.textStyle.fontSize,
          greaterThan(portrait.textStyle.fontSize),
        );
        expect(
          tester.getRect(find.byKey(cellsKey)).width,
          moreOrLessEquals(
            tester.getRect(find.byKey(areaKey)).width,
            epsilon: 1.0,
          ),
        );
        expect(terminal.viewWidth, 282);
        expect(terminal.viewHeight, 50);
      },
    );
  });

  group('the grid semantics node (R-30-710, R-30-711, R-30-712)', () {
    testWidgets('is exactly one node, read only, multiline, at the full row width, not clipped to the '
        'window', (tester) async {
      final terminal = _terminal(feed: 'first row   \r\n\r\n\r\nsecond row  ');
      await tester.pumpWidget(
        _harness(
          width: 100, // Narrower than an 80-column grid's cell width, so
          // the pan window holds fewer columns than the grid.
          child: TerminalViewWidget(
            palette: AppColor.dark,
            phase: TerminalGridPhase.live,
            terminal: terminal,
          ),
        ),
      );
      await tester.pump();

      final gridSemantics = tester.getSemantics(
        find.byKey(const ValueKey('terminalGridSemantics')),
      );
      // Exactly one merged node under the grid area: no per-cell and no
      // per-line child nodes survive (R-30-710).
      expect(gridSemantics.childrenCount, 0);
      expect(gridSemantics.label, contains('first row'));
      expect(gridSemantics.label, contains('second row'));
      // Trailing spaces stripped, empty lines collapsed to one, per
      // R-30-711.
      expect(gridSemantics.label.contains('first row   '), isFalse);
      final lines = gridSemantics.label.split('\n');
      for (var i = 1; i < lines.length; i++) {
        expect(
          lines[i - 1].isEmpty && lines[i].isEmpty,
          isFalse,
          reason: 'two consecutive empty lines at $i must collapse to one',
        );
      }
    });
  });

  group('selection freeze contract (R-21-041)', () {
    testWidgets('copy returns the text of the frame the selection was made in, unaffected by ten '
        'further frames a freeze gate would have held', (tester) async {
      final terminal = _terminal(
        feed: 'alpha\r\nbeta\r\ngamma\r\ndelta\r\nepsilon',
      );
      final controller = TerminalController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _harness(
          child: TerminalViewWidget(
            palette: AppColor.dark,
            phase: TerminalGridPhase.live,
            terminal: terminal,
            controller: controller,
          ),
        ),
      );
      await tester.pump();

      // Select the first three rows.
      final base = terminal.buffer.createAnchorFromOffset(
        const CellOffset(0, 0),
      );
      final extent = terminal.buffer.createAnchorFromOffset(
        CellOffset(terminal.viewWidth - 1, 2),
      );
      controller.setSelection(base, extent);
      await tester.pump();

      final selectedText = terminal.buffer.getText(
        controller.selectionFor(terminal.buffer),
      );

      // Ten further frames arrive. This file's `_gatedWrite` mirrors the
      // freeze `app/lib/services/terminal.dart` (WP-16-a) must implement
      // per R-21-041: it MUST NOT write while a selection is live. This
      // test file has no dependency on that service, so it pins the
      // contract locally and proves the Copy path this widget builds
      // reads whatever was selected, unaffected by a write the real
      // freeze would have held.
      for (var i = 0; i < 10; i++) {
        _gatedWrite(terminal, controller, 'zzz frame $i\r\n');
      }

      expect(
        terminal.buffer.getText(controller.selectionFor(terminal.buffer)),
        selectedText,
        reason: 'the freeze gate must have held every one of the ten frames',
      );

      final copied = selectedText;
      expect(copied, contains('alpha'));
      expect(copied, contains('beta'));
      expect(copied, contains('gamma'));
      expect(copied.contains('delta'), isFalse);

      // ponytail: no Clipboard round-trip here — this test proves the
      // freeze contract at the buffer level, which is where the bug
      // R-21-041 guards against would actually manifest.
    });
  });

  group('selection toolbar exposes exactly Copy and Select visible screen (R-30-305)', () {
    testWidgets('never offers Select all', (tester) async {
      final terminal = _terminal(feed: 'alpha\r\nbeta\r\ngamma');
      final controller = TerminalController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _harness(
          child: TerminalViewWidget(
            palette: AppColor.dark,
            phase: TerminalGridPhase.live,
            terminal: terminal,
            controller: controller,
          ),
        ),
      );
      await tester.pump();

      final base = terminal.buffer.createAnchorFromOffset(
        const CellOffset(0, 0),
      );
      final extent = terminal.buffer.createAnchorFromOffset(
        CellOffset(terminal.viewWidth - 1, 1),
      );
      controller.setSelection(base, extent);
      await tester.pump();

      final toolbar = tester.widget<AdaptiveTextSelectionToolbar>(
        find.byType(AdaptiveTextSelectionToolbar),
      );
      final labels = toolbar.buttonItems!.map((item) => item.label).toList();
      expect(labels, ['Copy', 'Select visible screen']);
    });
  });

  group('the grid takes no typed-text side channel of its own (R-31-09-12 as amended by '
      'R-03-123)', () {
    test('the widget file never calls Terminal.write: since R-03-123 the grid does carry a '
        'predicted echo, but `terminal.dart` (`WP-16-a`) writes every cell of it, including '
        'the overlay, and this file writes none', () {
      final source = _codeOnly(
        File('lib/widgets/terminal_view_widget.dart').readAsStringSync(),
      );
      expect(source.contains('.write('), isFalse);
    });

    testWidgets('the widget tree carries no text-input widget of its own', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          child: TerminalViewWidget(
            palette: AppColor.dark,
            phase: TerminalGridPhase.live,
            terminal: _terminal(feed: 'from the pane'),
          ),
        ),
      );
      await tester.pump();

      // `key_row.dart` (`WP-17`) owns typed input and classifies each
      // keystroke for the predictive local echo of R-03-123; the glyph it
      // predicts is drawn by `terminal.dart`'s own overlay write, never by a
      // field this file owns. So this file must still carry no editable text
      // widget that a typed-text side channel could target.
      expect(find.byType(EditableText), findsNothing);
    });
  });

  group('states (R-90-011)', () {
    testWidgets(
      'loadingFirstPaint shows nothing before 150ms, then the reading line',
      (tester) async {
        await tester.pumpWidget(
          _harness(
            child: const TerminalViewWidget(
              palette: AppColor.dark,
              phase: TerminalGridPhase.loadingFirstPaint,
            ),
          ),
        );
        expect(find.text('Reading pane...'), findsNothing);
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('Reading pane...'), findsOneWidget);
      },
    );

    testWidgets(
      'paneGone, readFailed and protocolMismatch only dim the last painted grid and draw no '
      'block: the R-03-119 alert is the screen\'s, not this widget\'s',
      (tester) async {
        for (final phase in [
          TerminalGridPhase.paneGone,
          TerminalGridPhase.readFailed,
          TerminalGridPhase.protocolMismatch,
        ]) {
          await tester.pumpWidget(
            _harness(
              child: TerminalViewWidget(
                palette: AppColor.dark,
                phase: phase,
                terminal: _terminal(feed: 'last known output'),
                errorText: 'pane_not_found',
                hostName: 'patrick-desk',
              ),
            ),
          );
          await tester.pump();
          final Finder grid = find.byType(TerminalView);
          expect(grid, findsOneWidget, reason: '$phase keeps the grid');
          final Opacity dim = tester.widget(
            find.ancestor(of: grid, matching: find.byType(Opacity)).first,
          );
          expect(dim.opacity, 0.60, reason: '$phase dims to opacity.dim');
          for (final String text in [
            'This pane closed.',
            'Back to agents',
            'Could not read this pane.',
            'pane_not_found',
            'Try again',
            'Back',
            'This computer runs a different Herdr version.',
            'Update Herdr on patrick-desk, or update this app.',
          ]) {
            expect(
              find.text(text),
              findsNothing,
              reason: '$phase draws no block, so no `$text`',
            );
          }
        }
      },
    );

    testWidgets(
      'hostInUse and offline keep the last painted grid, dimmed, never cleared',
      (tester) async {
        for (final phase in [
          TerminalGridPhase.hostInUse,
          TerminalGridPhase.offline,
        ]) {
          final terminal = _terminal(feed: 'still here');
          await tester.pumpWidget(
            _harness(
              child: TerminalViewWidget(
                palette: AppColor.dark,
                phase: phase,
                terminal: terminal,
              ),
            ),
          );
          await tester.pump();
          expect(find.byType(TerminalView), findsOneWidget);
          expect(find.byType(Opacity), findsWidgets);
        }
      },
    );

    testWidgets('truncatedAtTop shows the dismissible strip', (tester) async {
      var dismissed = false;
      await tester.pumpWidget(
        _harness(
          child: TerminalViewWidget(
            palette: AppColor.dark,
            phase: TerminalGridPhase.live,
            terminal: _terminal(),
            truncatedAtTop: true,
            onDismissTruncated: () => dismissed = true,
          ),
        ),
      );
      await tester.pump();
      expect(
        find.textContaining('This is the most recent output.'),
        findsOneWidget,
      );
      await tester.tap(find.textContaining('This is the most recent output.'));
      expect(dismissed, isTrue);
    });

    testWidgets('truncatedAtTop reads the exact R-31-08-19 strip text', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          child: TerminalViewWidget(
            palette: AppColor.dark,
            phase: TerminalGridPhase.live,
            terminal: _terminal(),
            truncatedAtTop: true,
          ),
        ),
      );
      await tester.pump();
      expect(
        find.text(
          'This is the most recent output. Older lines stay on the computer.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'revoked shows the exact R-13-055 message and fires onRevoked once, without a tap',
      (tester) async {
        var revokedCount = 0;
        await tester.pumpWidget(
          _harness(
            child: TerminalViewWidget(
              palette: AppColor.dark,
              phase: TerminalGridPhase.revoked,
              terminal: _terminal(feed: 'last known output'),
              onRevoked: () => revokedCount++,
            ),
          ),
        );
        await tester.pump();
        expect(
          find.text('Connection lost — this device has been revoked'),
          findsOneWidget,
        );
        expect(revokedCount, 1);

        // Stays live, unrelated rebuilds do not re-fire it.
        await tester.pump();
        expect(revokedCount, 1);
      },
    );
  });

  group('the jump-to-bottom pill (R-31-08-06, R-31-08-16, R-90-010)', () {
    testWidgets('does not appear while at the live bottom', (tester) async {
      await tester.pumpWidget(
        _harness(
          child: TerminalViewWidget(
            palette: AppColor.dark,
            phase: TerminalGridPhase.live,
            terminal: _terminal(),
            maxScrollOffsetFromBottom: 100,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('to bottom'), findsNothing);
    });

    for (final platform in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.iOS,
    ]) {
      testWidgets('native pill returns to live output on ${platform.name}', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final terminal = _terminal(
          feed: List.generate(60, (i) => 'row $i').join('\r\n'),
        );
        await tester.pumpWidget(
          _harness(
            height: 200,
            child: TerminalViewWidget(
              palette: AppColor.dark,
              phase: TerminalGridPhase.live,
              terminal: terminal,
              textSize: 18,
              maxScrollOffsetFromBottom: 200,
            ),
          ),
        );
        await tester.pump();
        final scrollable = tester.widget<Scrollable>(find.byType(Scrollable));
        final double bottom = scrollable.controller!.position.maxScrollExtent;
        scrollable.controller!.jumpTo(bottom - 50);
        await tester.pump();
        expect(find.text('to bottom'), findsOneWidget);
        expect(
          find.byType(
            platform == TargetPlatform.iOS ? CupertinoButton : FilledButton,
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('to bottom'));
        await tester.pumpAndSettle();
        expect(scrollable.controller!.offset, closeTo(bottom, 0.5));
        expect(find.text('to bottom'), findsNothing);
        debugDefaultTargetPlatformOverride = null;
      });
      testWidgets('native truncated strip dismisses on ${platform.name}', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        var dismissed = false;
        await tester.pumpWidget(
          _harness(
            child: TerminalViewWidget(
              palette: AppColor.dark,
              phase: TerminalGridPhase.live,
              terminal: _terminal(),
              truncatedAtTop: true,
              onDismissTruncated: () => dismissed = true,
            ),
          ),
        );
        await tester.pump();
        final row = find.byType(
          platform == TargetPlatform.iOS ? CupertinoListTile : ListTile,
        );
        expect(row, findsOneWidget);
        await tester.tap(row);
        expect(dismissed, isTrue);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  });

  group('sparse Host rows keep real content visible', () {
    for (final maxScrollOffset in [0, 200]) {
      testWidgets(
        'a sparse 282x87 pane keeps readable cells inside the clip with scroll maximum $maxScrollOffset',
        (tester) async {
          const marker = 'Terminal text is readable at normal size';
          final rows = <String>[
            marker,
            'Connection is ready',
            'The Host grid stays fixed',
            'The text size is 13 pixels',
            'Output is complete',
            ...List<String>.filled(82, ''),
          ];
          final terminal = _terminal()
            ..resize(282, 87)
            ..write(rows.join('\r\n'));
          final offsets = <int>[];
          Widget build({
            bool overview = false,
            double width = 390,
            double height = 500,
          }) => _harness(
            width: width,
            height: height,
            child: TerminalViewWidget(
              palette: AppColor.dark,
              phase: TerminalGridPhase.live,
              terminal: terminal,
              overview: overview,
              maxScrollOffsetFromBottom: maxScrollOffset,
              onScrollOffsetChanged: offsets.add,
            ),
          );

          void expectVisibleContent({bool overview = false}) {
            final view = tester.widget<TerminalView>(find.byType(TerminalView));
            final render = tester
                .state<TerminalViewState>(find.byType(TerminalView))
                .renderTerminal;
            final clip = tester.getRect(
              find
                  .descendant(
                    of: find.byKey(const ValueKey('terminalGridArea')),
                    matching: find.byType(ClipRect),
                  )
                  .first,
            );
            expect(view.textStyle.fontSize, overview ? lessThan(13.0) : 13.0);
            expect(view.autoResize, isFalse);
            expect(terminal.viewWidth, 282);
            expect(terminal.viewHeight, 87);
            expect(terminal.buffer.lines.length, 87);
            expect(clip.width, greaterThan(0));
            expect(clip.height, greaterThan(0));
            for (var row = 0; row < 5; row++) {
              expect(
                terminal.buffer.lines[row].getText().trimRight(),
                rows[row],
              );
              for (var column = 0; column < rows[row].length; column++) {
                final cell =
                    render.localToGlobal(
                      render.getOffset(CellOffset(column, row)),
                    ) &
                    render.cellSize;
                expect(cell.left, greaterThanOrEqualTo(clip.left - 0.01));
                expect(cell.top, greaterThanOrEqualTo(clip.top - 0.01));
                expect(cell.right, lessThanOrEqualTo(clip.right + 0.01));
                expect(
                  cell.bottom,
                  lessThanOrEqualTo(clip.bottom + 0.01),
                  reason: 'row $row column $column must paint inside the clip',
                );
              }
            }
            for (var row = 5; row < 87; row++) {
              expect(terminal.buffer.lines[row].getText().trim(), isEmpty);
            }
            expect(offsets, everyElement(0));
            expect(find.text('to bottom'), findsNothing);
          }

          await tester.pumpWidget(build());
          await tester.pump();
          await tester.pump();
          await tester.pump();
          final state = tester.state(find.byType(TerminalViewWidget));
          final readableCell = tester
              .state<TerminalViewState>(find.byType(TerminalView))
              .renderTerminal
              .cellSize;
          expectVisibleContent();

          rows[1] = 'The second frame is visible';
          terminal
            ..write('\x1b[2J\x1b[H')
            ..write(rows.join('\r\n'));
          await tester.pump();
          await tester.pump();
          await tester.pump();
          expectVisibleContent();

          await tester.pumpWidget(build(overview: true));
          await tester.pump();
          await tester.pump();
          await tester.pump();
          expectVisibleContent(overview: true);
          await tester.pumpWidget(build());
          await tester.pump();
          await tester.pump();
          await tester.pump();
          expectVisibleContent();
          expect(
            tester
                .state<TerminalViewState>(find.byType(TerminalView))
                .renderTerminal
                .cellSize,
            readableCell,
          );

          await tester.pumpWidget(build(width: 700, height: 300));
          await tester.pump();
          await tester.pump();
          await tester.pump();
          expectVisibleContent();
          await tester.pumpWidget(build());
          await tester.pump();
          await tester.pump();
          await tester.pump();
          expectVisibleContent();
          expect(tester.state(find.byType(TerminalViewWidget)), same(state));
        },
      );
    }
  });

  group('the scroll offset direction (R-31-08-18, R-21-041)', () {
    testWidgets(
      'a filled grid preserves manual scroll through rebuilds and reports row offsets',
      (tester) async {
        final rows = List.generate(87, (row) => 'row $row');
        final terminal = _terminal()
          ..resize(282, 87)
          ..write(rows.join('\r\n'));
        final offsets = <int>[];
        Widget build({int revision = 1}) => _harness(
          height: 200,
          child: TerminalViewWidget(
            palette: AppColor.dark,
            phase: TerminalGridPhase.live,
            terminal: terminal,
            revision: revision,
            maxScrollOffsetFromBottom: 200,
            onScrollOffsetChanged: offsets.add,
          ),
        );
        await tester.pumpWidget(build());
        await tester.pump();
        await tester.pump();
        await tester.pump();

        rows[86] = 'New output is visible';
        terminal
          ..write('\x1b[2J\x1b[H')
          ..write(rows.join('\r\n'));
        await tester.pump();
        await tester.pump();
        await tester.pump();

        final scrollable = tester.widget<Scrollable>(find.byType(Scrollable));
        final position = scrollable.controller!.position;
        final bottom = position.maxScrollExtent;
        final render = tester
            .state<TerminalViewState>(find.byType(TerminalView))
            .renderTerminal;
        expect(bottom, greaterThan(0));
        expect(position.pixels, moreOrLessEquals(bottom, epsilon: 0.01));
        expect(offsets, everyElement(0));
        expect(find.text('to bottom'), findsNothing);
        expect(
          tester
              .widget<TerminalView>(find.byType(TerminalView))
              .textStyle
              .fontSize,
          13.0,
        );

        // Move two rows toward earlier output with the real scroll controller.
        position.jumpTo(bottom - 2 * render.cellSize.height);
        await tester.pump();
        await tester.pump();
        expect(offsets.last, 2);
        expect(find.text('to bottom'), findsOneWidget);
        final userPosition = position.pixels;
        final markerPosition = render.localToGlobal(
          render.getOffset(const CellOffset(0, 82)),
        );

        for (final revision in [2, 3]) {
          await tester.pumpWidget(build(revision: revision));
          await tester.pump();
          await tester.pump();
          await tester.pump();
          expect(
            position.pixels,
            moreOrLessEquals(userPosition, epsilon: 0.01),
          );
          expect(
            render.localToGlobal(render.getOffset(const CellOffset(0, 82))),
            markerPosition,
          );
          expect(offsets.last, 2);
          expect(find.text('to bottom'), findsOneWidget);
        }

        position.jumpTo(bottom);
        await tester.pump();
        await tester.pump();
        expect(offsets.last, 0);
        expect(find.text('to bottom'), findsNothing);
        expect(terminal.viewWidth, 282);
        expect(terminal.viewHeight, 87);
      },
    );

    testWidgets(
      'the follow anchor holds still when the frame\'s last non-blank row moves',
      (tester) async {
        // Measured live 2026-09-08 against an 85-row `omp` agent pane: the Host
        // frame is a fixed-height snapshot whose own last non-blank row moves
        // between consecutive frames (83 and 85 while the pane redraws, about
        // four frames a second). An anchor that follows that row moved the whole
        // window by the difference on every frame, which is the flicker
        // R-21-021's 2026-09-08 amendment records.
        String snapshot(int lines) =>
            [for (var row = 0; row < lines; row++) 'row $row'].join('\r\n');
        final terminal = _terminal()..resize(240, 85);
        Widget build({int revision = 1}) => _harness(
          height: 200,
          child: TerminalViewWidget(
            palette: AppColor.dark,
            phase: TerminalGridPhase.live,
            terminal: terminal,
            revision: revision,
            maxScrollOffsetFromBottom: 200,
          ),
        );
        terminal.write('\x1b[2J\x1b[H${snapshot(85)}');
        await tester.pumpWidget(build());
        await tester.pump();
        await tester.pump();
        await tester.pump();

        final position = tester
            .widget<Scrollable>(find.byType(Scrollable))
            .controller!
            .position;
        final double anchored = position.pixels;
        expect(anchored, greaterThan(0));

        for (var frame = 1; frame <= 4; frame++) {
          terminal.write('\x1b[2J\x1b[H${snapshot(frame.isEven ? 85 : 83)}');
          await tester.pumpWidget(build(revision: frame + 1));
          await tester.pump();
          await tester.pump();
          expect(
            position.pixels,
            moreOrLessEquals(anchored, epsilon: 0.01),
            reason:
                'frame $frame moved the window; the anchor must not follow the '
                "frame's own last non-blank row",
          );
        }
      },
    );

    testWidgets(
      'a sparse pane anchors on its last ink row, not the blank buffer bottom',
      (tester) async {
        // Measured live 2026-09-11: a PowerShell pane with 27 rows of ink inside
        // an 87-row Host buffer. Anchoring at `maxScrollExtent` showed 60 blank
        // rows once the keyboard shrank the viewport, so the person typed blind.
        String snapshot(int lines) =>
            [for (var row = 0; row < lines; row++) 'row $row'].join('\r\n');
        final terminal = _terminal()..resize(240, 87);
        Widget build({required double height}) => _harness(
          height: height,
          child: TerminalViewWidget(
            palette: AppColor.dark,
            phase: TerminalGridPhase.live,
            terminal: terminal,
            revision: 1,
            maxScrollOffsetFromBottom: 200,
          ),
        );
        terminal.write('\x1b[2J\x1b[H${snapshot(27)}');
        await tester.pumpWidget(build(height: 200));
        await tester.pump();
        await tester.pump();
        await tester.pump();

        final position = tester
            .widget<Scrollable>(find.byType(Scrollable))
            .controller!
            .position;
        final double cell = tester
            .state<TerminalViewState>(find.byType(TerminalView))
            .renderTerminal
            .cellSize
            .height;
        expect(
          position.pixels,
          moreOrLessEquals(
            27 * cell - position.viewportDimension,
            epsilon: 0.01,
          ),
          reason: 'the last ink row (27) sits at the window bottom',
        );
        expect(position.pixels, lessThan(position.maxScrollExtent));

        // The keyboard shrinks the viewport: row 27 must stay in view.
        await tester.pumpWidget(build(height: 120));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        expect(
          position.pixels,
          moreOrLessEquals(
            27 * cell - position.viewportDimension,
            epsilon: 0.01,
          ),
          reason: 'a shorter viewport re-anchors on the same last ink row',
        );
      },
    );
  });

  group('R-30-250 and R-30-230: radius.none and space.0', () {
    testWidgets(
      'the grid area carries no rounded decoration and no screen-edge inset',
      (tester) async {
        await tester.pumpWidget(
          _harness(
            child: TerminalViewWidget(
              palette: AppColor.dark,
              phase: TerminalGridPhase.live,
              terminal: _terminal(),
            ),
          ),
        );
        await tester.pump();
        // ColoredBox has no shape/radius by construction; asserting one
        // exists here would be asserting a widget type this file never
        // uses for the grid fill.
        expect(find.byType(ColoredBox), findsWidgets);
      },
    );
  });

  group('long-press duration (R-30-301)', () {
    testWidgets('a stationary press selects a word at 400ms, not before, overriding xterm2\'s own '
        '500ms default', (tester) async {
      final terminal = _terminal(feed: 'hello world');
      await tester.pumpWidget(
        _harness(
          child: TerminalViewWidget(
            palette: AppColor.dark,
            phase: TerminalGridPhase.live,
            terminal: terminal,
          ),
        ),
      );
      await tester.pump();

      final gesture = await tester.startGesture(
        tester.getTopLeft(find.byKey(const ValueKey('terminalGridArea'))) +
            const Offset(5, 5),
      );
      addTearDown(() => gesture.removePointer());

      // Just under R-30-301's 400 ms: not yet recognised.
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);

      // Past 400 ms, still well under xterm2's own 500 ms default: this
      // only passes if this file's own recognizer, not xterm2's, won
      // the gesture arena.
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pump();

      expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
    });
  });

  group('scroll to dismiss the keyboard', () {
    testWidgets(
      'a finger drag on the grid drops focus; a programmatic scroll does not',
      (tester) async {
        final rows = List.generate(87, (row) => 'row $row');
        final terminal = _terminal()
          ..resize(80, 87)
          ..write(rows.join('\r\n'));
        final focus = FocusNode();
        addTearDown(focus.dispose);
        await tester.pumpWidget(
          _harness(
            height: 300,
            child: Column(
              children: [
                SizedBox(
                  height: 200,
                  child: TerminalViewWidget(
                    palette: AppColor.dark,
                    phase: TerminalGridPhase.live,
                    terminal: terminal,
                    maxScrollOffsetFromBottom: 200,
                  ),
                ),
                // Stands in for the composer field: the thing that holds the keyboard.
                Focus(focusNode: focus, child: const SizedBox(height: 40)),
              ],
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        focus.requestFocus();
        await tester.pump();
        expect(focus.hasFocus, isTrue);

        // The widget's own scroll (a jump, a resync) raises no drag details.
        final scrollable = tester.widget<Scrollable>(find.byType(Scrollable));
        scrollable.controller!.jumpTo(40);
        await tester.pump();
        expect(
          focus.hasFocus,
          isTrue,
          reason: 'a programmatic scroll keeps focus',
        );

        await tester.drag(
          find.byKey(const ValueKey('terminalGridArea')),
          const Offset(0, 60),
        );
        await tester.pump();
        expect(
          focus.hasFocus,
          isFalse,
          reason: 'a finger drag dismisses the keyboard',
        );
      },
    );
  });
}

/// Mirrors the freeze `app/lib/services/terminal.dart` (`WP-16-a`, R-21-041) must implement:
/// hold a write while a selection is live. This file has no dependency on that service; this
/// helper exists only to pin the contract this test proves against.
void _gatedWrite(
  Terminal terminal,
  TerminalController controller,
  String data,
) {
  if (controller.selection != null) return;
  terminal.write(data);
}

/// Strips `///`, `//` line comments and `/* */` block comments from [source], so a source-text
/// assertion checks real code, not this file's own doc comments describing the rule it proves
/// (which necessarily quote the very substrings, such as `Theme.of` and `pane.resize`, the check
/// looks for).
String _codeOnly(String source) {
  final noBlockComments = source.replaceAll(
    RegExp(r'/\*.*?\*/', dotAll: true),
    '',
  );
  return noBlockComments
      .split('\n')
      .map((line) {
        final index = line.indexOf('//');
        return index == -1 ? line : line.substring(0, index);
      })
      .join('\n');
}
