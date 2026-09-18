/// Screen-level tests for `TerminalScreen` (`docs/31-mockups/08-terminal.md`): the app bar
/// composition (back, pane title, live dot, `Pane actions` overflow — no keyboard control
/// since R-03-116, 2026-09-10), the live typing path of R-03-054 and its per-pane ACK filter,
/// the grid tap that raises the keyboard and never sends (R-31-08-08), readable text, the
/// column window (R-21-037), and the explicit Overview control.
/// Other cases cover continuous pinch zoom (R-30-302), the force-read pull (R-11-053), the live link word
/// on a pane taller than the viewport (the 2026-09-03 live-review defect), the live dot's
/// re-arm on a frame whose revision did not move (Herdr freezes `revision` on agent panes,
/// 2026-09-03), the R-03-119 alerts of the pane-gone (`tree_update`, R-11-046) and read-failed
/// states, the landscape
/// composition (mockup 08's landscape wireframe), and the two R-03-113 imports of 2026-09-09:
/// the title that opens the pane switcher sheet and hands the chosen pane to `onSwitchPane`
/// (item 1, R-31-08-25), and the `N waiting   N done` attention summary (item 4, R-31-08-26).
///
/// The harness serves real `watch_ack`/`pane_frame`/`tree_snapshot` messages through one
/// broadcast stream, so `TerminalService`, the screen's shared listener and the tree read
/// all see the same frames, exactly as `RelayConnection.messages` publishes them.
library;

import 'dart:async' show StreamController;

import 'package:cupertino_ui/cupertino_ui.dart'
    show
        CupertinoAlertDialog,
        CupertinoButton,
        CupertinoDialogAction,
        CupertinoNavigationBar,
        CupertinoNavigationBarBackButton,
        CupertinoPageRoute,
        CupertinoTextField;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/widgets.dart'
    show
        Brightness,
        EditableText,
        Offset,
        Rect,
        Semantics,
        Size,
        SizedBox,
        Text,
        ValueKey,
        Widget;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/app.dart' show ResolvedChrome, appThemeFrom;
import 'package:herdr_mobile/models/codes.dart' show ErrorCode;
import 'package:herdr_mobile/models/message.dart'
    show Message, MessageHostAction, MessageScrollRequest, MessageSendInput;
import 'package:herdr_mobile/models/messages/agent_summary.dart'
    show AgentSummary;
import 'package:herdr_mobile/models/messages/error_message.dart'
    show ErrorMessage;
import 'package:herdr_mobile/models/messages/host_action_kind.dart'
    show HostActionKind;
import 'package:herdr_mobile/models/messages/pane_frame.dart' show PaneFrame;
import 'package:herdr_mobile/models/messages/pane_scroll_state.dart'
    show PaneScrollState;
import 'package:herdr_mobile/models/messages/pane_summary.dart'
    show PaneSummary;
import 'package:herdr_mobile/models/messages/scroll_offsets.dart'
    show ScrollOffsets;
import 'package:herdr_mobile/models/messages/scroll_request.dart'
    show ScrollRequest;
import 'package:herdr_mobile/models/messages/scroll_response.dart'
    show ScrollResponse;
import 'package:herdr_mobile/models/messages/send_input.dart' show SendInput;
import 'package:herdr_mobile/models/messages/send_input_ack.dart'
    show SendInputAck;
import 'package:herdr_mobile/models/messages/tab_summary.dart' show TabSummary;
import 'package:herdr_mobile/models/messages/tree_event.dart' show TreeEvent;
import 'package:herdr_mobile/models/messages/tree_snapshot.dart'
    show TreeSnapshot;
import 'package:herdr_mobile/models/messages/tree_update.dart' show TreeUpdate;
import 'package:herdr_mobile/models/messages/watch_ack.dart' show WatchAck;
import 'package:herdr_mobile/models/messages/workspace_summary.dart'
    show WorkspaceSummary;
import 'package:herdr_mobile/screens/pane_actions_sheet.dart'
    show PaneActionsSheet;
import 'package:herdr_mobile/screens/pane_switcher_sheet.dart'
    show PaneSwitcherSheet;
import 'package:herdr_mobile/screens/terminal_screen.dart';
import 'package:herdr_mobile/services/relay.dart'
    show RelayConnected, RelayConnectionState, RelayDisconnected;
import 'package:herdr_mobile/widgets/key_row.dart' show KeyRow;
import 'package:herdr_mobile/widgets/status_bar.dart' show BarState, StatusBar;
import 'package:herdr_mobile/widgets/status_strip.dart' show StatusStrip;
import 'package:herdr_mobile/widgets/terminal_view_widget.dart'
    show TerminalGridPhase, TerminalViewWidget;
import 'package:herdr_mobile/widgets/theme/app_type.dart' show AppType;
import 'package:herdr_mobile/widgets/theme/chrome_icon_action.dart'
    show ChromeIconAction;
import 'package:herdr_mobile/widgets/theme/chrome_scheme.dart'
    show ChromeScheme;
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart'
    show AlertDialog, AppBar, BackButton, MaterialApp, TextButton;
import 'package:xterm2/xterm.dart'
    show Terminal, TerminalView, TerminalViewState;

import 'golden_support.dart' show loadAppFonts;

const String _paneId = 'w3:p1';
const ValueKey<String> _gridKey = ValueKey<String>('terminalGridArea');
const ValueKey<String> _cellsKey = ValueKey<String>('terminalGridCells');
const ValueKey<String> _overviewKey = ValueKey<String>(
  'terminalOverviewToggle',
);

/// The fixed clock every case here runs against, so the sheet header's
/// agent age and the live dot's 60 s warning stay deterministic.
final DateTime _fixedNow = DateTime.utc(2026, 9, 3, 10, 0, 33);

const PaneSummary _pane = PaneSummary(
  paneId: _paneId,
  workspaceId: 'w3',
  tabId: 'w3:t1',
  terminalId: 'term-1',
  label: 'main',
  title: 'claude',
  cwd: '/work',
  focused: true,
  agentStatus: 'working',
  revision: 1,
  scroll: PaneScrollState(
    offsetFromBottom: 0,
    maxOffsetFromBottom: 240,
    viewportRows: 50,
  ),
);

const TreeSnapshot _snapshot = TreeSnapshot(
  workspaces: [
    WorkspaceSummary(workspaceId: 'w3', name: 'plugin', focused: true),
  ],
  tabs: [
    TabSummary(
      tabId: 'w3:t1',
      workspaceId: 'w3',
      title: 'plugin',
      focused: true,
    ),
  ],
  panes: [_pane],
  agents: [
    AgentSummary(
      agentKind: 'claude',
      paneId: _paneId,
      status: 'working',
      statusAt: '2026-09-03T10:00:00Z',
    ),
  ],
);

/// The R-31-08-25 switcher fixture: two workspaces, three tabs, four panes. Two agent panes
/// are `blocked` and one is `done`, so the R-31-08-26 summary reads `2 waiting   1 done`;
/// the fourth pane is a shell. Every agent pane carries `agent` and `agent_status` on the
/// pane itself, the fields `tree_update` keeps current and the screen counts from.
const PaneSummary _switcherPane2 = PaneSummary(
  paneId: 'w3:p2',
  workspaceId: 'w3',
  tabId: 'w3:t2',
  terminalId: 'term-2',
  label: '',
  title: 'codex',
  cwd: '/work',
  focused: false,
  agent: 'codex',
  agentStatus: 'done',
  revision: 1,
  scroll: PaneScrollState(
    offsetFromBottom: 0,
    maxOffsetFromBottom: 0,
    viewportRows: 50,
  ),
);

const TreeSnapshot _switcherSnapshot = TreeSnapshot(
  workspaces: [
    WorkspaceSummary(workspaceId: 'w3', name: 'plugin', focused: true),
    WorkspaceSummary(workspaceId: 'w4', name: 'docs', focused: false),
  ],
  tabs: [
    TabSummary(
      tabId: 'w3:t1',
      workspaceId: 'w3',
      title: 'plugin',
      focused: true,
    ),
    TabSummary(
      tabId: 'w3:t2',
      workspaceId: 'w3',
      title: 'tests',
      focused: false,
    ),
    TabSummary(
      tabId: 'w4:t1',
      workspaceId: 'w4',
      title: 'notes',
      focused: true,
    ),
  ],
  panes: [
    PaneSummary(
      paneId: _paneId,
      workspaceId: 'w3',
      tabId: 'w3:t1',
      terminalId: 'term-1',
      label: 'main',
      title: 'claude',
      cwd: '/work',
      focused: true,
      agent: 'claude',
      agentStatus: 'blocked',
      revision: 1,
      scroll: PaneScrollState(
        offsetFromBottom: 0,
        maxOffsetFromBottom: 240,
        viewportRows: 50,
      ),
    ),
    PaneSummary(
      paneId: 'w3:p3',
      workspaceId: 'w3',
      tabId: 'w3:t1',
      terminalId: 'term-3',
      label: '',
      title: 'zsh',
      cwd: '/work',
      focused: false,
      agentStatus: 'unknown',
      revision: 1,
      scroll: PaneScrollState(
        offsetFromBottom: 0,
        maxOffsetFromBottom: 0,
        viewportRows: 50,
      ),
    ),
    _switcherPane2,
    PaneSummary(
      paneId: 'w4:p1',
      workspaceId: 'w4',
      tabId: 'w4:t1',
      terminalId: 'term-4',
      label: 'review',
      title: 'claude',
      cwd: '/docs',
      focused: true,
      agent: 'claude',
      agentStatus: 'blocked',
      revision: 1,
      scroll: PaneScrollState(
        offsetFromBottom: 0,
        maxOffsetFromBottom: 0,
        viewportRows: 50,
      ),
    ),
  ],
  agents: [
    AgentSummary(
      agentKind: 'claude',
      paneId: _paneId,
      status: 'blocked',
      statusAt: '2026-09-03T10:00:00Z',
    ),
  ],
);

/// One pumped screen plus what it sent. `send`, `watchPane` and
/// `unwatchPane` only record; the test drives every reply by hand through
/// [emit].
class _Harness {
  _Harness({
    this.initialState = const RelayConnected(),
    this.initialTextSize = 13,
    DateTime Function()? now,
  }) : now = now ?? (() => _fixedNow);

  final RelayConnectionState initialState;
  final int initialTextSize;

  /// The clock the screen reads; `_fixedNow` unless a test supplies its own.
  final DateTime Function() now;
  final StreamController<Message> messages =
      StreamController<Message>.broadcast();
  final List<Message> sent = <Message>[];

  bool backTapped = false;
  bool diagnosticsTapped = false;

  /// The pane id the switcher sheet handed to `onSwitchPane`, or `null`.
  String? switchedTo;
  String? splitTo;

  void emit(Message message) => messages.add(message);

  List<SendInput> get sendInputs => sent
      .whereType<MessageSendInput>()
      .map((MessageSendInput m) => m.payload)
      .toList();

  List<ScrollRequest> get scrollRequests => sent
      .whereType<MessageScrollRequest>()
      .map((MessageScrollRequest m) => m.payload)
      .toList();

  Widget build({bool themed = false}) => MaterialApp(
    theme: themed ? appThemeFrom(ChromeScheme.fixed(Brightness.dark)) : null,
    builder: themed ? (context, child) => ResolvedChrome(child: child!) : null,
    onGenerateInitialRoutes:
        debugDefaultTargetPlatformOverride == TargetPlatform.iOS
        ? (_) => [
            CupertinoPageRoute<void>(
              title: 'Workspace',
              builder: (_) => const SizedBox(),
            ),
            CupertinoPageRoute<void>(
              title: 'Terminal',
              builder: (_) => screen(),
            ),
          ]
        : null,
    routes: {'/': (_) => screen()},
  );

  Widget screen() => TerminalScreen(
    hostId: 'host-1',
    paneId: _paneId,
    hostName: 'patrick-desk',
    initialTextSize: initialTextSize,
    messages: messages.stream,
    connectionState: const Stream<RelayConnectionState>.empty(),
    initialConnectionState: initialState,
    send: (Message message, {String? corr}) => sent.add(message),
    watchPane: (String paneId, {String? corr}) {},
    unwatchPane: (String paneId, {String? corr}) {},
    onBack: () => backTapped = true,
    onDiagnostics: () => diagnosticsTapped = true,
    onSwitchPane: (String paneId) => switchedTo = paneId,
    onSplit: (String paneId) => splitTo = paneId,
    now: now,
  );
}

/// The phone-size portrait viewport every portrait case here runs at (the
/// default 800x600 test surface reads as landscape). [size] overrides it
/// for a case whose content the wider-than-Roboto flutter_test font
/// overflows at 390 logical pixels though a real phone fits it.
Future<void> _pumpScreen(
  WidgetTester tester,
  _Harness harness, {
  bool landscape = false,
  bool themed = false,
  Size? size,
}) async {
  tester.view.physicalSize =
      size ?? (landscape ? const Size(844, 390) : const Size(390, 844));
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(harness.build(themed: themed));
  await tester.pump();
}

/// Attaches a pane and applies a frame after the 120 ms coalescing window.
Future<void> _attachLive(
  WidgetTester tester,
  _Harness harness, {
  int columns = 144,
  int rows = 50,
}) async {
  harness.emit(
    Message.watchAck(
      WatchAck(
        paneId: _paneId,
        revision: 1,
        viewportRows: rows,
        width: columns,
        scroll: const ScrollOffsets(
          offsetFromBottom: 0,
          maxOffsetFromBottom: 240,
        ),
      ),
    ),
  );
  await tester.pump();
  harness.emit(
    Message.paneFrame(
      PaneFrame(
        paneId: _paneId,
        revision: 2,
        viewportRows: rows,
        width: columns,
        text: 'build ok\r\n> ',
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 200));
  // Apply the column report and the measured cell size after layout.
  await tester.pump();
}

/// The live dot's 60 s warning timer (`docs/32-design-language.md` section
/// 7.3) outlives every case here; flush it so no test ends on a pending
/// timer.
Future<void> _flushDotTimer(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 61));

/// `pane.closed` for this pane (R-11-046): the tree drops it and the screen
/// reaches `paneGone`.
const Message _paneClosedUpdate = Message.treeUpdate(
  TreeUpdate(event: TreeEvent.paneClosed, pane: _pane),
);

/// The Host's `error` reply to `watch_pane`, so the attach in flight fails
/// and the screen reaches `readFailed` with the raw text (R-11-092).
const Message _attachError = Message.error(
  ErrorMessage(
    code: ErrorCode.paneNotFound,
    message: 'no such pane',
    fatal: false,
  ),
);

/// Long enough for the alert's entrance or exit on either platform: the
/// Material dialog route's 150 ms, the Cupertino dialog's 250 ms route plus
/// its own scale and inset animation, which the test clock lands under
/// 500 ms.
const Duration _alertExit = Duration(milliseconds: 600);

/// Lands the R-03-119 alert after a phase change: one frame for the change
/// itself, whose post-frame check pushes the dialog; one frame that builds
/// it; then its entrance, or its exit, animation.
Future<void> _pumpAlert(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(_alertExit);
}

/// The Material alert's action labels in the order the component lays them
/// out: the default action last (R-33-074.4). The bar's title is a
/// `TextButton` too on Android, hence the descendant scope.
List<String> _alertActionLabels(WidgetTester tester) => tester
    .widgetList<TextButton>(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextButton),
      ),
    )
    .map((TextButton button) => (button.child! as Text).data!)
    .toList();

/// One app bar action, the shared `ChromeIconAction`, by the name it carries
/// (R-30-717). Never by glyph: the key row draws `arrow_back_rounded` too,
/// for its `Left` arrow segment, so a glyph finder is ambiguous.
Finder _barAction(String label) => find.byWidgetPredicate(
  (widget) => widget is ChromeIconAction && widget.label == label,
);

/// The `Pane actions` overflow.
Finder _overflow() => _barAction('Pane actions');

/// The back control: the platform's own glyph (R-33-070), one name.
Finder _backControl() =>
    debugDefaultTargetPlatformOverride == TargetPlatform.iOS
    ? find.byType(CupertinoNavigationBarBackButton)
    : find.byType(BackButton);

/// One cap of the key row, by the widget key `key_row.dart` gives it.
Finder _keyCap(String key) => find.byKey(ValueKey<String>(key));

/// The live bar's semantics node (R-32-511, R-03-100).
Finder _liveDot() => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == 'live',
);

/// The title control of R-31-08-25: the one semantics node that reads
/// `<title>, switch pane`, present only once the tree has landed.
Finder _titleControl() => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      (widget.properties.label ?? '').endsWith(', switch pane'),
);

/// One pane row in the switcher, by its unchanged combined semantics label.
Finder _paneRow(String label) => find.byWidgetPredicate(
  (Widget widget) => widget is Semantics && widget.properties.label == label,
);

/// The live bar's current state.
BarState _liveState(WidgetTester tester) => tester
    .widget<StatusBar>(
      find.descendant(of: _liveDot(), matching: find.byType(StatusBar)),
    )
    .state;

/// R-03-130: append one native composer edit.
Future<void> _type(WidgetTester tester, String text) async {
  final field = tester.widget<EditableText>(find.byType(EditableText));
  await tester.enterText(
    find.byType(EditableText),
    field.controller.text + text,
  );
  await tester.pump();
}

/// The glyph the emulator holds at [row], [col], or `''` for a cell nothing wrote. Reads the
/// live `xterm2` buffer, which is the grid a person sees.
String _gridCell(Terminal terminal, int row, int col) {
  final int codePoint = terminal.buffer.lines[row].getCodePoint(col);
  return codePoint == 0 ? '' : String.fromCharCode(codePoint);
}

/// The status strip is one `Text.rich` (its runs share a baseline), so a
/// readout is found by `textContaining`, and its text read through the
/// span; the landscape bar keeps the range in a plain `Text`.
({int first, int last}) _columnWindow(WidgetTester tester) {
  final text = tester.widget<Text>(find.textContaining(RegExp(r'c\d+-\d+')));
  final plain = text.data ?? text.textSpan!.toPlainText();
  final match = RegExp(r'c(\d+)-(\d+)').firstMatch(plain)!;
  return (first: int.parse(match.group(1)!), last: int.parse(match.group(2)!));
}

double _paintedTextSize(WidgetTester tester) =>
    tester.widget<TerminalView>(find.byType(TerminalView)).textStyle.fontSize;

Future<void> _pinchBy(WidgetTester tester, double scale) async {
  final center = tester.getCenter(find.byKey(_gridKey));
  final a = await tester.startGesture(center - const Offset(50, 0));
  final b = await tester.startGesture(center + const Offset(50, 0));
  final movement = 50 * (scale - 1);
  await a.moveBy(Offset(-movement, 0));
  await b.moveBy(Offset(movement, 0));
  await tester.pump();
  await tester.pump();
  await a.up();
  await b.up();
  await tester.pump();
}

Future<void> _toggleOverview(WidgetTester tester) async {
  await tester.tap(find.byKey(_overviewKey));
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

void main() {
  for (final (waitFrames, returnLive) in [
    (1, false),
    (60, false),
    (60, true),
  ]) {
    testWidgets(
      'a two-finger scroll awaits history through bounce ($waitFrames frames, return live: $returnLive)',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final harness = _Harness(initialTextSize: 16);
        await _pumpScreen(tester, harness);
        await _attachLive(tester, harness);
        final center = tester.getCenter(find.byKey(_gridKey));
        final a = await tester.startGesture(center - const Offset(50, 0));
        final b = await tester.startGesture(center + const Offset(50, 0));
        for (var i = 0; i < 5; i++) {
          await a.moveBy(const Offset(0, 20));
          await b.moveBy(const Offset(0, 20));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await a.up();
        await b.up();
        for (var frame = 0; frame < waitFrames; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(harness.scrollRequests, hasLength(1));
        if (returnLive) {
          await tester.tap(find.text('to bottom'));
          await tester.pump(const Duration(milliseconds: 600));
          await tester.pump();
        }
        harness.emit(
          Message.scrollResponse(
            ScrollResponse(
              paneId: _paneId,
              lines: 150,
              truncated: true,
              text: List.generate(150, (i) => 'history row $i').join('\r\n'),
            ),
          ),
        );
        for (var frame = 0; frame < 5; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          tester
              .widget<TerminalView>(find.byType(TerminalView))
              .terminal
              .buffer
              .lines
              .length,
          returnLive ? 50 : 150,
        );
        expect(
          tester
              .widget<TerminalViewWidget>(find.byType(TerminalViewWidget))
              .customTextSize,
          isNull,
        );
        expect(_paintedTextSize(tester), 16);
        expect(harness.sendInputs, isEmpty);
        await _flushDotTimer(tester);
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      'short live grid still loads history on an ordinary drag on ${platform.name}',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final harness = _Harness();
        await _pumpScreen(tester, harness);
        await _attachLive(tester, harness, rows: 10);
        await tester.dragFrom(
          tester.getCenter(find.byKey(_gridKey)),
          const Offset(0, 120),
        );
        await tester.pump();
        expect(harness.scrollRequests, hasLength(1));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets('returning live before a history timeout keeps the pane usable', (
    tester,
  ) async {
    final harness = _Harness();
    await _pumpScreen(tester, harness);
    await _attachLive(tester, harness, rows: 50);
    harness.emit(
      Message.paneFrame(
        PaneFrame(
          paneId: _paneId,
          revision: 3,
          viewportRows: 50,
          width: 144,
          text: List.generate(50, (i) => 'live row $i').join('\r\n'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.dragFrom(
      tester.getCenter(find.byKey(_gridKey)),
      const Offset(0, 650),
    );
    await tester.pumpAndSettle();
    expect(harness.scrollRequests, hasLength(1));
    await tester.tap(find.text('to bottom'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    expect(find.text('Could not read this pane.'), findsNothing);
    expect(
      tester.widget<TerminalViewWidget>(find.byType(TerminalViewWidget)).phase,
      TerminalGridPhase.live,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'ordinary upward scrolling grows history only near the top and preserves the reader',
    (tester) async {
      final harness = _Harness();
      await _pumpScreen(tester, harness);
      await _attachLive(tester, harness, columns: 80, rows: 50);
      harness.emit(
        Message.paneFrame(
          PaneFrame(
            paneId: _paneId,
            revision: 3,
            viewportRows: 50,
            width: 80,
            text: List.generate(50, (i) => 'live row $i').join('\r\n'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      // Start well away from the special pull-to-read region at the top.
      await tester.dragFrom(
        tester.getCenter(find.byKey(_gridKey)),
        const Offset(0, 650),
      );
      await tester.pumpAndSettle();
      expect(harness.scrollRequests, hasLength(1));
      expect(harness.scrollRequests.single.lines, 150);
      harness.emit(
        Message.scrollResponse(
          ScrollResponse(
            paneId: _paneId,
            text: List.generate(
              150,
              (i) => 'history row ${850 + i}',
            ).join('\r\n'),
            lines: 150,
            truncated: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final view = tester.widget<TerminalView>(find.byType(TerminalView));
      expect(view.terminal.buffer.getText(), contains('history row 850'));
      expect(view.terminal.buffer.lines.length, 150);
      final scroll = view.scrollController!;
      final cell = tester
          .state<TerminalViewState>(find.byType(TerminalView))
          .renderTerminal
          .cellSize;
      // Waiting and scrolling within the loaded window must not fetch more.
      await tester.pump(const Duration(seconds: 1));
      await tester.dragFrom(
        tester.getCenter(find.byKey(_gridKey)),
        const Offset(0, 80),
      );
      await tester.pumpAndSettle();
      expect(harness.scrollRequests, hasLength(1));
      scroll.jumpTo(10 * cell.height);
      await tester.pumpAndSettle();
      expect(harness.scrollRequests, hasLength(1));
      await tester.dragFrom(
        tester.getCenter(find.byKey(_gridKey)),
        const Offset(0, 45),
      );
      await tester.pumpAndSettle();
      expect(harness.scrollRequests.map((r) => r.lines), [150, 250]);
      final offsetBefore = scroll.offset;
      final topBefore = (offsetBefore / cell.height).floor();
      final lineBefore = view.terminal.buffer.lines[topBefore].getText();
      harness.emit(
        Message.scrollResponse(
          ScrollResponse(
            paneId: _paneId,
            text: List.generate(
              250,
              (i) => 'history row ${750 + i}',
            ).join('\r\n'),
            lines: 250,
            truncated: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(offsetBefore + 100 * cell.height, 0.1));
      expect(
        view.terminal.buffer.lines[(scroll.offset / cell.height).floor()]
            .getText(),
        lineBefore,
      );
      expect(
        tester
            .widget<Semantics>(
              find.byKey(const ValueKey('terminalGridSemantics')),
            )
            .properties
            .label,
        startsWith(lineBefore.trimRight()),
      );
      expect(harness.scrollRequests, hasLength(2));
      view.scrollController!.jumpTo(0);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'This is the most recent output. Older lines stay on the computer.',
        ),
        findsNothing,
      );
      expect(harness.scrollRequests, hasLength(2));
      await tester.tap(find.text('to bottom'));
      // The native terminal cursor keeps animating after the button receives focus.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      final live = tester.widget<TerminalView>(find.byType(TerminalView));
      expect(live.terminal.buffer.getText(), contains('live row 49'));
      expect(live.terminal.buffer.getText(), isNot(contains('history row')));
      expect(harness.sendInputs, isEmpty);
      expect(harness.sent.whereType<MessageHostAction>(), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final availableRows in [175, 1000]) {
    testWidgets(
      'progressive history stops at $availableRows rows and resets on return to live',
      (tester) async {
        Future<void> settleGrid() async {
          for (var frame = 0; frame < 5; frame++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
        }

        final harness = _Harness();
        await _pumpScreen(tester, harness);
        await _attachLive(tester, harness, columns: 80, rows: 50);
        final view = tester.widget<TerminalView>(find.byType(TerminalView));
        for (
          var requested = 150;
          ;
          requested = (requested + 100).clamp(1, 1000)
        ) {
          view.scrollController!.jumpTo(0);
          await settleGrid();
          final previousRequests = harness.scrollRequests.length;
          await tester.dragFrom(
            tester.getCenter(find.byKey(_gridKey)),
            const Offset(0, 70),
          );
          await settleGrid();
          expect(harness.scrollRequests.length, previousRequests + 1);
          expect(harness.scrollRequests.last.lines, requested);
          // A second gesture while the reply is pending shares the same request.
          await tester.dragFrom(
            tester.getCenter(find.byKey(_gridKey)),
            const Offset(0, 70),
          );
          await settleGrid();
          expect(harness.scrollRequests.length, previousRequests + 1);
          final returned = requested.clamp(1, availableRows);
          harness.emit(
            Message.scrollResponse(
              ScrollResponse(
                paneId: _paneId,
                text: List.generate(
                  returned,
                  (i) => 'history row $i',
                ).join('\r\n'),
                lines: returned,
                // Some Hosts flag truncation even when returning fewer rows than requested.
                truncated: true,
              ),
            ),
          );
          await settleGrid();
          expect(view.terminal.buffer.lines.length, returned);
          if (returned == availableRows) break;
        }
        final count = harness.scrollRequests.length;
        view.scrollController!.jumpTo(0);
        await settleGrid();
        await tester.dragFrom(
          tester.getCenter(find.byKey(_gridKey)),
          const Offset(0, 70),
        );
        await settleGrid();
        expect(harness.scrollRequests, hasLength(count));
        expect(
          find.text(
            'This is the most recent output. Older lines stay on the computer.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('to bottom'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        await tester.dragFrom(
          tester.getCenter(find.byKey(_gridKey)),
          const Offset(0, 250),
        );
        await tester.pump();
        expect(harness.scrollRequests, hasLength(count + 1));
        expect(harness.scrollRequests.last.lines, 150);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  setUpAll(loadAppFonts);

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final landscape in [false, true]) {
      final orientation = landscape ? '_landscape' : '';
      testWidgets('native terminal back golden ${platform.name}$orientation', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final harness = _Harness();
        await _pumpScreen(tester, harness, themed: true, landscape: landscape);
        await _attachLive(tester, harness);
        await tester.pump(const Duration(seconds: 1));
        await expectLater(
          find.byType(TerminalScreen),
          matchesGoldenFile(
            'goldens/terminal_screen_native_back_${platform.name}${orientation}_dark.png',
          ),
        );
        await _flushDotTimer(tester);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }

  testWidgets(
    'Android: AppBar with back, the pane title, the live dot and the Pane actions overflow',
    (tester) async {
      final harness = _Harness();
      await _pumpScreen(tester, harness);

      expect(find.byType(CupertinoNavigationBar), findsNothing);
      // Before the first tree_snapshot, the title is R-31-07-10's
      // unnamed-pane fallback from the pane id alone.
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('pane 1')),
        findsOneWidget,
      );
      // The host name no longer titles this screen (R-31-08-20).
      expect(find.text('patrick-desk'), findsNothing);

      await tester.tap(_backControl());
      await tester.pump();
      expect(harness.backTapped, isTrue);

      expect(_overflow(), findsOneWidget);
      // R-32-511: the live dot carries the connection word.
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.label == 'live',
        ),
        findsOneWidget,
      );
      await _flushDotTimer(tester);
    },
  );

  testWidgets(
    'iOS: CupertinoNavigationBar with the same back, title, dot and overflow',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final harness = _Harness();
      await _pumpScreen(tester, harness);

      expect(find.byType(AppBar), findsNothing);
      expect(
        find.descendant(
          of: find.byType(CupertinoNavigationBar),
          matching: find.text('pane 1'),
        ),
        findsOneWidget,
      );
      await tester.tap(_backControl());
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(TerminalScreen), findsNothing);
      expect(harness.backTapped, isFalse);
      await _flushDotTimer(tester);
      // The framework's own invariant check runs before tearDowns, so the
      // platform override resets here, inside the body.
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('the app bar carries no keyboard control: the overflow is the one trailing control, and '
      'the live bar sits before the title on the leading side, with the summary on the title '
      'text edge (R-03-116, R-03-121, R-31-08-26)', (tester) async {
    final harness = _Harness();
    await _pumpScreen(tester, harness);
    await _attachLive(tester, harness);

    expect(find.byTooltip('Shortcuts'), findsNothing);
    expect(_barAction('Shortcuts'), findsNothing);
    expect(find.byIcon(Symbols.keyboard_rounded), findsNothing);
    // The bar's controls, leading to trailing: back, the live bar, the
    // title control, the overflow. `Overview` sits on the status strip
    // in portrait.
    expect(_backControl(), findsOneWidget);
    expect(_overflow(), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AppBar), matching: _liveDot()),
      findsOneWidget,
    );
    final double bar = tester.getCenter(_liveDot()).dx;
    expect(bar, greaterThan(tester.getCenter(_backControl()).dx));
    expect(bar, lessThan(tester.getTopLeft(find.text('pane 1')).dx));
    expect(bar, lessThan(tester.getCenter(_overflow()).dx));

    // R-31-08-26: the summary starts on the title's text edge, past the
    // bar and its gap.
    harness.emit(const Message.treeSnapshot(_switcherSnapshot));
    await tester.pump();
    await tester.pump();
    expect(
      tester.getTopLeft(find.textContaining('waiting')).dx,
      closeTo(tester.getTopLeft(find.text('plugin')).dx, 0.5),
    );
    await _flushDotTimer(tester);
  });

  testWidgets('iOS: the same bar carries no keyboard control either, and the live bar leads the '
      'title (R-03-121)', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final harness = _Harness();
    await _pumpScreen(tester, harness);
    await _attachLive(tester, harness);

    expect(find.byIcon(Symbols.keyboard_rounded), findsNothing);
    expect(_overflow(), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(CupertinoNavigationBar),
        matching: _liveDot(),
      ),
      findsOneWidget,
    );
    final double bar = tester.getCenter(_liveDot()).dx;
    expect(bar, greaterThan(tester.getCenter(_backControl()).dx));
    expect(bar, lessThan(tester.getTopLeft(find.text('pane 1')).dx));
    await _flushDotTimer(tester);
    // The framework's own invariant check runs before tearDowns, so the
    // platform override resets here, inside the body.
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('More keys preserves the keyboard; the grid closes all 14 keys', (
    tester,
  ) async {
    final harness = _Harness();
    await _pumpScreen(tester, harness);
    await _attachLive(tester, harness);
    const keys = <String>[
      'keyRowEsc',
      'keyRowTab',
      'keyRowCtrl',
      'keyRowAlt',
      'keyRowArrow^',
      'keyRowNavins',
      'keyRowNavhome',
      'keyRowNavpgup',
      'keyRowArrow<',
      'keyRowArrowv',
      'keyRowArrow>',
      'keyRowNavdel',
      'keyRowNavend',
      'keyRowNavpgdn',
    ];
    for (final key in keys) {
      expect(_keyCap(key), findsNothing);
    }
    await tester.tap(find.byType(EditableText));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.byKey(const ValueKey<String>('composerMore')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.testTextInput.isVisible, isTrue);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
    for (final key in keys) {
      expect(_keyCap(key).hitTestable(), findsOneWidget);
    }
    await tester.tap(find.byType(EditableText));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.testTextInput.isVisible, isTrue);
    for (final key in keys) {
      expect(_keyCap(key).hitTestable(), findsOneWidget);
    }
    await tester.tap(find.byKey(_gridKey));
    await tester.pump(const Duration(milliseconds: 600));
    for (final key in keys) {
      expect(_keyCap(key), findsNothing);
    }
    expect(harness.sendInputs, isEmpty);
    await _flushDotTimer(tester);
  });

  testWidgets(
    'a control chord is typed, not picked: the ctrl latch then one key is '
    'exactly one send_input for this pane (R-03-116)',
    (tester) async {
      final harness = _Harness();
      await _pumpScreen(tester, harness);
      await _attachLive(tester, harness);

      await tester.tap(find.byKey(const ValueKey<String>('composerMore')));
      await tester.pump();
      // The latch alone sends nothing and raises the keyboard (R-31-09-19).
      await tester.tap(_keyCap('keyRowCtrl'));
      await tester.pump();
      expect(harness.sendInputs, isEmpty);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(_keyCap('keyRowCtrl').hitTestable(), findsOneWidget);

      await _type(tester, 'c');
      expect(harness.sendInputs, hasLength(1));
      expect(harness.sendInputs.single.paneId, _paneId);
      expect(harness.sendInputs.single.keys, <String>['ctrl+c']);
      expect(harness.sendInputs.single.text, isNull);
      expect(harness.sent.whereType<MessageHostAction>(), isEmpty);
      await _flushDotTimer(tester);
    },
  );

  testWidgets(
    'offline: the ctrl cap latches nothing and the key row dispatches nothing '
    '(R-30-808)',
    (tester) async {
      final harness = _Harness(initialState: const RelayDisconnected());
      await _pumpScreen(tester, harness);

      await tester.tap(find.byKey(const ValueKey<String>('composerMore')));
      await tester.pump();
      await tester.tap(_keyCap('keyRowCtrl'));
      await tester.pump();
      expect(find.bySemanticsLabel('Control'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Control (held|locked)')),
        findsNothing,
      );
      expect(harness.sendInputs, isEmpty);
      expect(harness.sent.whereType<MessageHostAction>(), isEmpty);
      await _flushDotTimer(tester);
    },
  );

  testWidgets(
    'a second frame with the SAME revision re-arms the live bar: Herdr freezes '
    'revision on agent panes, so the 60 s warning age runs from the last frame, '
    'not the last revision change (2026-09-03)',
    (tester) async {
      DateTime clock = _fixedNow;
      final harness = _Harness(now: () => clock);
      await _pumpScreen(tester, harness);
      await _attachLive(tester, harness); // the first frame, revision 2, at T

      expect(_liveState(tester), BarState.ok);

      // 59 s later a frame arrives with the same revision and new text.
      clock = clock.add(const Duration(seconds: 59));
      harness.emit(
        const Message.paneFrame(
          PaneFrame(
            paneId: _paneId,
            revision: 2,
            viewportRows: 50,
            width: 144,
            text: 'build ok\r\n> still running',
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();

      // 61 s past the first frame now: the first frame's 60 s timer has
      // expired, but the bar re-armed on the second frame, so it still
      // holds `ok`. Run the clock past both timers to prove it.
      clock = clock.add(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 61));
      expect(_liveState(tester), BarState.ok);
    },
  );

  testWidgets(
    'the app bar title and the sheet header follow the tree: tab title, pane label, agent line',
    (tester) async {
      final harness = _Harness();
      await _pumpScreen(tester, harness);
      await _attachLive(tester, harness);
      harness.emit(const Message.treeSnapshot(_snapshot));
      await tester.pump();

      expect(find.text('plugin'), findsOneWidget);
      expect(find.text('main'), findsNothing);

      await tester.tap(_overflow());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.descendant(
          of: find.byType(PaneActionsSheet),
          matching: find.text('plugin'),
        ),
        findsOneWidget,
      );
      // Mockup 10 callout 4: agent kind, status word, age from status_at
      // (33 s at the fixed clock).
      expect(find.text('claude  -  working 33s'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await _flushDotTimer(tester);
    },
  );

  testWidgets('a live pane taller than the viewport reads LIVE, never PAUSED, and shows no pill '
      '(the 2026-09-03 defect, R-21-041)', (tester) async {
    final harness = _Harness();
    await _pumpScreen(tester, harness);
    await _attachLive(tester, harness);

    expect(find.byType(KeyRow), findsOneWidget);
    expect(find.byType(StatusStrip), findsOneWidget);
    expect(find.byType(CupertinoTextField), findsNothing);
    expect(find.textContaining('LIVE'), findsOneWidget);
    expect(find.textContaining('PAUSED'), findsNothing);
    expect(find.text('to bottom'), findsNothing);
    // The `space.3` gap between two readouts is a `WidgetSpan`, U+FFFC in
    // the plain text.
    expect(find.textContaining(RegExp('144x50\uFFFCc1-\\d+')), findsOneWidget);
    expect(_columnWindow(tester).first, 1);
    expect(_columnWindow(tester).last, lessThan(144));
    expect(find.text('Overview').hitTestable(), findsOneWidget);
    await _flushDotTimer(tester);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final textSize in [13, 18]) {
      testWidgets(
        '${platform.name}: the native mode control restores ${textSize}px and horizontal pan',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          final harness = _Harness(initialTextSize: textSize);
          await _pumpScreen(tester, harness);
          await _attachLive(tester, harness, columns: 282);

          final toggle = find.byKey(_overviewKey);
          expect(toggle.hitTestable(), findsOneWidget);
          if (platform == TargetPlatform.android) {
            expect(tester.widget(toggle), isA<TextButton>());
          } else {
            expect(tester.widget(toggle), isA<CupertinoButton>());
          }
          expect(find.text('Overview').hitTestable(), findsOneWidget);
          expect(find.text('Readable'), findsNothing);
          expect(tester.getSize(toggle).width, greaterThanOrEqualTo(48));
          expect(tester.getSize(toggle).height, greaterThanOrEqualTo(48));

          final gridState = tester.state(find.byType(TerminalViewWidget));
          final view = tester.widget<TerminalView>(find.byType(TerminalView));
          final terminal = view.terminal;
          final readableCell = tester
              .state<TerminalViewState>(find.byType(TerminalView))
              .renderTerminal
              .cellSize;
          final area = tester.getRect(find.byKey(_gridKey));
          final readableCells = tester.getRect(find.byKey(_cellsKey));
          expect(view.textStyle.fontSize, textSize.toDouble());
          expect(view.autoResize, isFalse);
          expect(readableCells.width, greaterThan(area.width));
          expect(
            readableCells.width,
            moreOrLessEquals(282 * readableCell.width, epsilon: 0.01),
          );
          expect(_columnWindow(tester).first, 1);
          expect(_columnWindow(tester).last, lessThan(282));
          expect(terminal.viewWidth, 282);
          expect(terminal.viewHeight, 50);
          final sentBefore = List<Message>.of(harness.sent);

          await _toggleOverview(tester);
          expect(
            tester.state(find.byType(TerminalViewWidget)),
            same(gridState),
          );
          expect(find.text('Readable').hitTestable(), findsOneWidget);
          expect(find.text('Overview'), findsNothing);
          expect(tester.getSize(toggle).width, greaterThanOrEqualTo(48));
          expect(tester.getSize(toggle).height, greaterThanOrEqualTo(48));
          expect(find.textContaining('282x50'), findsOneWidget);
          expect(find.textContaining(RegExp(r'c\d+-\d+')), findsNothing);
          final overviewView = tester.widget<TerminalView>(
            find.byType(TerminalView),
          );
          final overviewCells = tester.getRect(find.byKey(_cellsKey));
          final overviewCell = tester
              .state<TerminalViewState>(find.byType(TerminalView))
              .renderTerminal
              .cellSize;
          expect(
            overviewView.textStyle.fontSize,
            lessThan(textSize.toDouble()),
          );
          expect(overviewView.autoResize, isFalse);
          expect(overviewView.terminal, same(terminal));
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
          expect(terminal.viewWidth, 282);
          expect(terminal.viewHeight, 50);

          await _toggleOverview(tester);
          expect(find.text('Overview').hitTestable(), findsOneWidget);
          expect(find.text('Readable'), findsNothing);
          final restoredView = tester.widget<TerminalView>(
            find.byType(TerminalView),
          );
          final restoredCell = tester
              .state<TerminalViewState>(find.byType(TerminalView))
              .renderTerminal
              .cellSize;
          expect(restoredView.textStyle.fontSize, textSize.toDouble());
          expect(restoredView.autoResize, isFalse);
          expect(restoredCell, readableCell);
          expect(
            tester.getRect(find.byKey(_cellsKey)).width,
            readableCells.width,
          );
          expect(_columnWindow(tester).first, 1);

          await tester.drag(find.byKey(_gridKey), const Offset(-120, 0));
          await tester.pump();
          await tester.pump();
          expect(_columnWindow(tester).first, greaterThan(1));
          expect(
            tester.getRect(find.byKey(_cellsKey)).left,
            lessThan(area.left),
          );
          await tester.drag(find.byKey(_gridKey), const Offset(-10000, 0));
          await tester.pump();
          await tester.pump();
          expect(_columnWindow(tester).last, 282);
          expect(
            tester.getRect(find.byKey(_cellsKey)).right,
            moreOrLessEquals(area.right, epsilon: 0.01),
          );
          expect(terminal.viewWidth, 282);
          expect(terminal.viewHeight, 50);
          expect(harness.sent, sentBefore);
          expect(
            tester
                .widget<TerminalScreen>(find.byType(TerminalScreen))
                .initialTextSize,
            textSize,
          );
          await _flushDotTimer(tester);
          // The binding checks this value before registered teardown callbacks run.
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }
  }

  testWidgets('the portrait mode control remains visible at 200% text scale', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final harness = _Harness();
    await _pumpScreen(tester, harness);
    await _attachLive(tester, harness, columns: 282);

    expect(tester.takeException(), isNull);
    final toggle = find.byKey(_overviewKey);
    expect(toggle.hitTestable(), findsOneWidget);
    expect(find.text('Overview').hitTestable(), findsOneWidget);
    expect(tester.getSize(toggle).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(toggle).height, greaterThanOrEqualTo(48));
    expect(
      tester.getSize(find.byType(StatusStrip)).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.widget<TerminalView>(find.byType(TerminalView)).textStyle.fontSize,
      13.0,
    );
    expect(_columnWindow(tester).first, 1);
    await _toggleOverview(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Readable').hitTestable(), findsOneWidget);
    await _toggleOverview(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Overview').hitTestable(), findsOneWidget);
    expect(
      tester.widget<TerminalView>(find.byType(TerminalView)).textStyle.fontSize,
      13.0,
    );
    await _flushDotTimer(tester);
  });

  testWidgets(
    'a tap on the grid raises the keyboard and sends nothing (R-31-08-08, R-03-054)',
    (tester) async {
      final harness = _Harness();
      await _pumpScreen(tester, harness);
      await _attachLive(tester, harness);
      expect(tester.testTextInput.hasAnyClients, isFalse);

      await tester.tap(find.byKey(_gridKey));
      await tester.pump();

      expect(tester.testTextInput.hasAnyClients, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(harness.sendInputs, isEmpty);
      await _flushDotTimer(tester);
    },
  );

  testWidgets(
    "typing goes to this pane as typed, and only this pane's ack settles it "
    '(R-03-054, R-11-227)',
    (tester) async {
      final harness = _Harness();
      await _pumpScreen(tester, harness);
      await _attachLive(tester, harness);
      await tester.tap(find.byKey(_gridKey));
      await tester.pump();

      await _type(tester, 'l');
      expect(harness.sendInputs, hasLength(1));
      expect(harness.sendInputs.single.paneId, _paneId);
      expect(harness.sendInputs.single.text, 'l');
      expect(harness.sendInputs.single.keys, isNull);

      // Another pane's refusal MUST NOT settle this pane's send.
      harness.emit(
        const Message.sendInputAck(
          SendInputAck(paneId: 'w3:p9', accepted: false),
        ),
      );
      await tester.pump();
      expect(find.text('Not sent: typing'), findsNothing);

      harness.emit(
        const Message.sendInputAck(
          SendInputAck(paneId: _paneId, accepted: false),
        ),
      );
      await tester.pump();
      expect(find.text('Not sent: typing'), findsOneWidget);
      // Nothing re-sends (R-11-228).
      expect(harness.sendInputs, hasLength(1));
      await _flushDotTimer(tester);
    },
  );

  testWidgets(
    'typing stays in the native composer until the Host echoes it (R-03-130)',
    (tester) async {
      final harness = _Harness();
      await _pumpScreen(tester, harness);
      await _attachLive(tester, harness);
      await tester.tap(find.byKey(_gridKey));
      await tester.pump();
      final terminal = tester
          .widget<TerminalView>(find.byType(TerminalView))
          .terminal;
      var paints = 0;
      terminal.addListener(() => paints++);

      await _type(tester, 'l');
      await _type(tester, 's');
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'ls',
      );
      expect(_gridCell(terminal, 1, 2), '');
      expect(paints, 0);
      harness.emit(
        const Message.paneFrame(
          PaneFrame(
            paneId: _paneId,
            revision: 3,
            viewportRows: 50,
            width: 144,
            text: 'build ok\r\n> ls',
          ),
        ),
      );
      await tester.pump();
      expect(_gridCell(terminal, 1, 2), 'l');
      expect(_gridCell(terminal, 1, 3), 's');
      expect(paints, 1);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'ls',
      );
      await _flushDotTimer(tester);
    },
  );

  testWidgets(
    'pinch chooses fractional sizes continuously and keeps the Settings default',
    (tester) async {
      final harness = _Harness();
      await _pumpScreen(tester, harness);
      await _attachLive(tester, harness);
      final initialWindow = _columnWindow(tester);
      await _pinchBy(tester, 1.1);
      expect(_paintedTextSize(tester), closeTo(14.3, 0.001));
      expect(find.textContaining('14.3px'), findsOneWidget);
      expect(_columnWindow(tester).last, lessThan(initialWindow.last));
      await _pinchBy(tester, 0.65);
      expect(_paintedTextSize(tester), closeTo(9.295, 0.001));
      expect(_columnWindow(tester).last, greaterThan(initialWindow.last));
      expect(
        tester
            .widget<TerminalViewWidget>(find.byType(TerminalViewWidget))
            .textSize,
        13,
      );
      await _toggleOverview(tester);
      await _toggleOverview(tester);
      expect(_paintedTextSize(tester), 13);
      await _flushDotTimer(tester);
    },
  );

  testWidgets(
    'a fine pinch does not open the keyboard but the next tap still does',
    (tester) async {
      final harness = _Harness();
      await _pumpScreen(tester, harness);
      await _attachLive(tester, harness);
      expect(tester.testTextInput.isVisible, isFalse);
      await _pinchBy(tester, 1.02);
      expect(_paintedTextSize(tester), closeTo(13.26, 0.001));
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.byKey(_gridKey));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
      expect(harness.sendInputs, isEmpty);
      await _flushDotTimer(tester);
    },
  );

  testWidgets(
    'continuous pinch updates use the gesture baseline and ignore a third finger',
    (tester) async {
      final harness = _Harness();
      await _pumpScreen(tester, harness);
      await _attachLive(tester, harness);
      final center = tester.getCenter(find.byKey(_gridKey));
      final a = await tester.startGesture(center - const Offset(50, 0));
      final b = await tester.startGesture(center + const Offset(50, 0));
      await a.moveBy(const Offset(-10, 0));
      await tester.pump();
      await tester.pump();
      expect(_paintedTextSize(tester), closeTo(14.3, 0.001));
      await b.moveBy(const Offset(20, 0));
      await tester.pump();
      await tester.pump();
      expect(_paintedTextSize(tester), closeTo(16.9, 0.001));
      final c = await tester.startGesture(center + const Offset(0, 50));
      await a.moveBy(const Offset(-30, 0));
      await tester.pump();
      expect(_paintedTextSize(tester), closeTo(16.9, 0.001));
      await c.up();
      await b.moveBy(const Offset(20, 0));
      await tester.pump();
      expect(_paintedTextSize(tester), closeTo(16.9, 0.001));
      await a.up();
      await b.up();
      await _flushDotTimer(tester);
    },
  );

  for (final textSize in [13, 18]) {
    testWidgets(
      'Overview pinch keeps intermediate zoom and Readable restores Settings $textSize',
      (tester) async {
        final harness = _Harness(initialTextSize: textSize);
        await _pumpScreen(tester, harness);
        await _attachLive(tester, harness, columns: 282);
        final terminal = tester
            .widget<TerminalView>(find.byType(TerminalView))
            .terminal;
        final sentBefore = List<Message>.of(harness.sent);
        await _toggleOverview(tester);
        final fittedSize = _paintedTextSize(tester);
        expect(fittedSize, lessThan(10));
        await _pinchBy(tester, 1.25);
        expect(_paintedTextSize(tester), closeTo(fittedSize * 1.25, 0.001));
        expect(_paintedTextSize(tester), lessThan(textSize));
        expect(find.text('Readable').hitTestable(), findsOneWidget);
        final custom = _paintedTextSize(tester);
        await tester.pump(const Duration(seconds: 1));
        expect(_paintedTextSize(tester), custom);
        await _pinchBy(tester, 1.2);
        expect(_paintedTextSize(tester), closeTo(custom * 1.2, 0.001));
        await _toggleOverview(tester);
        expect(_paintedTextSize(tester), textSize.toDouble());
        await _toggleOverview(tester);
        expect(_paintedTextSize(tester), closeTo(fittedSize, 0.001));
        expect(terminal.viewWidth, 282);
        expect(terminal.viewHeight, 50);
        expect(
          tester.widget<TerminalView>(find.byType(TerminalView)).terminal,
          same(terminal),
        );
        expect(harness.sent, sentBefore);
        await _flushDotTimer(tester);
      },
    );
  }

  testWidgets(
    'custom zoom survives rotation without changing Host geometry or Settings',
    (tester) async {
      final harness = _Harness(initialTextSize: 16);
      await _pumpScreen(tester, harness);
      await _attachLive(tester, harness, columns: 282);
      await _toggleOverview(tester);
      await _pinchBy(tester, 1.6);
      final custom = _paintedTextSize(tester);
      final sentBefore = List<Message>.of(harness.sent);
      tester.view.physicalSize = const Size(844, 390);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(_paintedTextSize(tester), custom);
      expect(find.text('Readable').hitTestable(), findsOneWidget);
      await _toggleOverview(tester);
      expect(_paintedTextSize(tester), 16);
      expect(harness.sent, sentBefore);
      await _flushDotTimer(tester);
    },
  );

  testWidgets('a pull down from the top of the grid while at the bottom sends one scroll_request '
      '(force a read, R-11-053)', (tester) async {
    final harness = _Harness();
    await _pumpScreen(tester, harness);
    await _attachLive(tester, harness);

    final topLeft = tester.getTopLeft(find.byKey(_gridKey));
    final pull = await tester.startGesture(topLeft + const Offset(150, 10));
    await pull.moveBy(const Offset(0, 60));
    await tester.pump();
    await pull.up();

    expect(harness.scrollRequests, hasLength(1));
    expect(harness.scrollRequests.single.paneId, _paneId);
    expect(harness.scrollRequests.single.lines, 150);

    // A pull that starts below the top edge is a scrollback drag, not a
    // force read.
    final mid = await tester.startGesture(topLeft + const Offset(150, 200));
    await mid.moveBy(const Offset(0, 60));
    await tester.pump();
    await mid.up();
    expect(harness.scrollRequests, hasLength(1));

    // Flush the 5 s reply timeout the unanswered request runs out.
    await tester.pump(const Duration(seconds: 6));
    await _flushDotTimer(tester);
  });

  testWidgets(
    'the overflow opens pane actions with split actions, and '
    'a confirmed Close pane sends one host_action close (R-03-101, R-31-10-01, R-11-202)',
    (tester) async {
      final harness = _Harness();
      await _pumpScreen(tester, harness);
      await _attachLive(tester, harness);
      harness.emit(const Message.treeSnapshot(_snapshot));
      await tester.pump();

      await tester.tap(_overflow());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Plugin actions'), findsOneWidget);
      expect(find.text('Close pane'), findsOneWidget);
      expect(find.text('Split right'), findsOneWidget);
      expect(find.text('Split down'), findsOneWidget);
      for (final String removed in <String>[
        'Send a prompt to claude',
        'Zoom this pane',
        'Rename pane',
        'Copy the whole screen',
      ]) {
        expect(
          find.text(removed),
          findsNothing,
          reason: '$removed left the sheet',
        );
      }

      await tester.tap(find.text('Close pane'));
      // The live indicator keeps a timer armed, so `pumpAndSettle` never
      // settles here: pump the sheet's exit and the dialog's entry by hand.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      // R-31-10-01: the sheet is gone and the dialog names the pane label.
      expect(find.text('Plugin actions'), findsNothing);
      expect(find.text('Close main?'), findsOneWidget);
      expect(harness.sent.whereType<MessageHostAction>(), isEmpty);

      await tester.tap(find.text('Close pane'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final hostActions = harness.sent.whereType<MessageHostAction>().toList();
      expect(hostActions, hasLength(1));
      expect(hostActions.single.payload.action, HostActionKind.close);
      expect(hostActions.single.payload.paneId, _paneId);
      expect(hostActions.single.payload.params, isNull);
      await _flushDotTimer(tester);
    },
  );

  testWidgets(
    'a refused split shows the Host error and keeps the current pane',
    (tester) async {
      final harness = _Harness();
      await _pumpScreen(tester, harness);
      await _attachLive(tester, harness);
      await tester.tap(_overflow());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Split down'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final hostActions = harness.sent.whereType<MessageHostAction>().toList();
      expect(hostActions, hasLength(1));
      expect(hostActions.single.payload.action, HostActionKind.paneSplit);
      expect(hostActions.single.payload.paneId, _paneId);
      expect(hostActions.single.payload.params, {
        'focus': false,
        'direction': 'down',
      });
      expect(harness.splitTo, isNull);
      harness.emit(
        const Message.error(
          ErrorMessage(
            code: ErrorCode.internalError,
            fatal: false,
            message: 'Pane cannot split.',
          ),
        ),
      );
      await _pumpAlert(tester);

      expect(find.byType(PaneActionsSheet), findsNothing);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Could not split pane.'), findsOneWidget);
      expect(find.text('Pane cannot split.'), findsOneWidget);
      expect(harness.splitTo, isNull);
      expect(harness.sent.whereType<MessageHostAction>(), hasLength(1));
    },
  );
  testWidgets('a pane.closed tree_update raises the R-03-119 alert once, the Material AlertDialog over the '
      'dimmed grid: `This pane closed.`, one action `Back to agents` that leaves through onBack; '
      'neither the barrier nor the back gesture closes it', (tester) async {
    final harness = _Harness();
    await _pumpScreen(tester, harness);
    await _attachLive(tester, harness);
    harness.emit(const Message.treeSnapshot(_snapshot));
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);

    harness.emit(_paneClosedUpdate);
    await _pumpAlert(tester);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(CupertinoAlertDialog), findsNothing);
    expect(find.text('This pane closed.'), findsOneWidget);
    expect(_alertActionLabels(tester), <String>['Back to agents']);
    // The last painted grid stays under the alert (R-31-08-05).
    expect(find.byType(TerminalView), findsOneWidget);

    // One alert per phase entry: a later tree change in the same phase raises no second one.
    harness.emit(const Message.treeSnapshot(_switcherSnapshot));
    await _pumpAlert(tester);
    expect(find.byType(AlertDialog), findsOneWidget);

    // A barrier tap and the system back gesture leave it in place: its actions are the only
    // way out.
    await tester.tapAt(const Offset(4, 4));
    await tester.pump(_alertExit);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump(_alertExit);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(harness.backTapped, isFalse);

    await tester.tap(find.text('Back to agents'));
    await tester.pump();
    await tester.pump(_alertExit);
    expect(harness.backTapped, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
    await _flushDotTimer(tester);
  });

  testWidgets(
    'the alert closes when the phase leaves and returns on the next entry: a frame proves the '
    'pane alive, then a second pane.closed raises it again (R-03-119)',
    (tester) async {
      final harness = _Harness();
      await _pumpScreen(tester, harness);
      await _attachLive(tester, harness);
      harness.emit(const Message.treeSnapshot(_snapshot));
      await tester.pump();
      harness.emit(_paneClosedUpdate);
      await _pumpAlert(tester);
      expect(find.byType(AlertDialog), findsOneWidget);

      harness.emit(
        const Message.paneFrame(
          PaneFrame(
            paneId: _paneId,
            revision: 3,
            viewportRows: 50,
            width: 144,
            text: 'still here\r\n> ',
          ),
        ),
      );
      // The 120 ms coalescing window, then the phase change and the alert's exit.
      await tester.pump(const Duration(milliseconds: 200));
      await _pumpAlert(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(harness.backTapped, isFalse);

      harness.emit(const Message.treeSnapshot(_snapshot));
      await tester.pump();
      harness.emit(_paneClosedUpdate);
      await _pumpAlert(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      await _flushDotTimer(tester);
    },
  );

  testWidgets('an error reply to watch_pane raises the read-failed alert: `Could not read this pane.`, the '
      'raw text in type.mono.code, `Back` then `Try again` as the default; `Try again` attaches '
      'again (R-03-119)', (tester) async {
    final harness = _Harness();
    await _pumpScreen(tester, harness);
    harness.emit(_attachError);
    await _pumpAlert(tester);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Could not read this pane.'), findsOneWidget);
    final Text raw = tester.widget(
      find.text('attach to pane $_paneId: no such pane'),
    );
    expect(raw.style!.fontFamily, AppType.monoCode.fontFamily);
    expect(_alertActionLabels(tester), <String>['Back', 'Try again']);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump(_alertExit);
    expect(find.byType(AlertDialog), findsNothing);
    // One more attach is in flight: the first-paint line shows after its 150 ms grace.
    expect(find.text('Reading pane...'), findsOneWidget);

    await _attachLive(tester, harness);
    expect(find.text('Reading pane...'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    await _flushDotTimer(tester);
  });

  testWidgets(
    'on iOS the alert is a CupertinoAlertDialog whose CupertinoDialogAction marks `Try again` '
    'as the default after `Back`, and `Back` leaves through onBack (R-03-119, R-33-074.2)',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final harness = _Harness();
      await _pumpScreen(tester, harness);
      harness.emit(_attachError);
      await _pumpAlert(tester);

      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Could not read this pane.'), findsOneWidget);
      final List<CupertinoDialogAction> actions = tester
          .widgetList<CupertinoDialogAction>(find.byType(CupertinoDialogAction))
          .toList();
      expect(
        actions
            .map((CupertinoDialogAction a) => (a.child as Text).data)
            .toList(),
        <String>['Back', 'Try again'],
      );
      expect(actions[0].isDefaultAction, isFalse);
      expect(actions[1].isDefaultAction, isTrue);
      expect(
        actions.any((CupertinoDialogAction a) => a.isDestructiveAction),
        isFalse,
      );

      await tester.tap(
        find.descendant(
          of: find.byType(CupertinoAlertDialog),
          matching: find.text('Back'),
        ),
      );
      await tester.pump();
      await tester.pump(_alertExit);
      expect(harness.backTapped, isTrue);
      expect(find.byType(CupertinoAlertDialog), findsNothing);
      await _flushDotTimer(tester);
      // The binding checks this value before registered teardown callbacks run.
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'an offline link disables the key row sends and names the failure (R-30-808)',
    (tester) async {
      final harness = _Harness(initialState: const RelayDisconnected());
      await _pumpScreen(tester, harness);

      expect(find.textContaining('OFFLINE'), findsOneWidget);
      expect(find.text('Not connected to patrick-desk.'), findsWidgets);

      // A sendable key is disabled at the link level: a tap sends nothing
      // (mockup 09's Offline row).
      await tester.tap(find.byKey(const ValueKey<String>('composerMore')));
      await tester.pump();
      await tester.tap(_keyCap('keyRowEsc'));
      await tester.pump();
      expect(harness.sendInputs, isEmpty);
      await _flushDotTimer(tester);
    },
  );

  testWidgets('landscape shows the default column window and the mode control in the merged bar; '
      'the key panel opens from the composer', (tester) async {
    final harness = _Harness();
    await _pumpScreen(tester, harness, landscape: true);
    await _attachLive(tester, harness);

    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(StatusStrip), findsNothing);
    expect(find.text('rev 2'), findsOneWidget);
    final initialWindow = _columnWindow(tester);
    final readableCell = tester
        .state<TerminalViewState>(find.byType(TerminalView))
        .renderTerminal
        .cellSize;
    expect(initialWindow.first, 1);
    expect(initialWindow.last, lessThan(144));
    expect(find.text('Overview').hitTestable(), findsOneWidget);
    final toggle = find.byKey(_overviewKey);
    expect(tester.getSize(toggle).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(toggle).height, greaterThanOrEqualTo(48));
    expect(
      tester.widget<TerminalView>(find.byType(TerminalView)).textStyle.fontSize,
      13.0,
    );
    expect(_overflow(), findsOneWidget);
    expect(_keyCap('keyRowAlt'), findsNothing);
    expect(_keyCap('keyRowNavins'), findsNothing);
    await tester.tap(find.byKey(const ValueKey<String>('composerMore')));
    await tester.pumpAndSettle();
    expect(_keyCap('keyRowAlt').hitTestable(), findsOneWidget);
    expect(_keyCap('keyRowNavins').hitTestable(), findsOneWidget);
    expect(_keyCap('keyRowArrowv').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(harness.sendInputs, isEmpty);
    await tester.tap(find.byKey(const ValueKey<String>('composerMore')));
    await tester.pumpAndSettle();
    expect(_keyCap('keyRowNavins'), findsNothing);

    await _toggleOverview(tester);
    expect(find.text('Readable').hitTestable(), findsOneWidget);
    expect(find.textContaining(RegExp(r'^c\d+-\d+$')), findsNothing);
    await _toggleOverview(tester);
    expect(find.text('Overview').hitTestable(), findsOneWidget);
    expect(_columnWindow(tester), initialWindow);
    expect(
      tester
          .state<TerminalViewState>(find.byType(TerminalView))
          .renderTerminal
          .cellSize,
      readableCell,
    );

    // No field in landscape either: the grid tap raises the keyboard and
    // sends nothing (R-03-054).
    expect(find.byType(CupertinoTextField), findsNothing);
    expect(tester.testTextInput.hasAnyClients, isFalse);
    await tester.tap(find.byKey(_gridKey));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    expect(harness.sendInputs, isEmpty);

    // The pinch reduces the column window and scales the grid by 50%.
    final a = await tester.startGesture(const Offset(345, 150));
    final b = await tester.startGesture(const Offset(445, 150));
    await tester.pump();
    await a.moveBy(const Offset(-50, 0));
    await tester.pump();
    await a.up();
    await b.up();
    await tester.pump();
    await tester.pump();
    final cellWidth = tester
        .state<TerminalViewState>(find.byType(TerminalView))
        .renderTerminal
        .cellSize
        .width;
    final visible = (tester.getSize(find.byKey(_gridKey)).width / cellWidth)
        .floor();
    final window = _columnWindow(tester);
    expect(
      window.last - window.first + 1,
      inInclusiveRange(visible, visible + 1),
    );
    expect(visible, lessThan(initialWindow.last));
    expect(
      tester.widget<TerminalView>(find.byType(TerminalView)).textStyle.fontSize,
      19.5,
    );
    await _flushDotTimer(tester);
  });

  testWidgets(
    'rotation preserves the pan window and overview state while the ACK stream remains active',
    (tester) async {
      final harness = _Harness();
      await _pumpScreen(tester, harness);
      await _attachLive(tester, harness, columns: 282);
      final gridState = tester.state(find.byType(TerminalViewWidget));
      final readableCell = tester
          .state<TerminalViewState>(find.byType(TerminalView))
          .renderTerminal
          .cellSize;
      await tester.drag(find.byKey(_gridKey), const Offset(-120, 0));
      await tester.pump();
      await tester.pump();
      final portraitWindow = _columnWindow(tester);
      expect(portraitWindow.first, greaterThan(1));

      // KeyRow subscribes again after rotation. The grid keeps its state.
      tester.view.physicalSize = const Size(844, 390);
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(KeyRow), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(tester.state(find.byType(TerminalViewWidget)), same(gridState));
      expect(_columnWindow(tester).first, portraitWindow.first);
      expect(_columnWindow(tester).last, greaterThan(portraitWindow.last));
      expect(find.text('Overview').hitTestable(), findsOneWidget);

      await _toggleOverview(tester);
      expect(find.text('Readable').hitTestable(), findsOneWidget);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(StatusStrip), findsOneWidget);
      expect(find.text('Readable').hitTestable(), findsOneWidget);
      expect(find.textContaining(RegExp(r'c\d+-\d+')), findsNothing);
      expect(
        tester.getSize(find.byKey(_cellsKey)).width,
        moreOrLessEquals(
          tester.getSize(find.byKey(_gridKey)).width,
          epsilon: 1.0,
        ),
      );

      tester.view.physicalSize = const Size(844, 390);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Readable').hitTestable(), findsOneWidget);
      await _toggleOverview(tester);
      expect(find.text('Overview').hitTestable(), findsOneWidget);
      expect(
        tester
            .state<TerminalViewState>(find.byType(TerminalView))
            .renderTerminal
            .cellSize,
        readableCell,
      );
      final view = tester.widget<TerminalView>(find.byType(TerminalView));
      expect(view.textStyle.fontSize, 13.0);
      expect(view.autoResize, isFalse);
      expect(view.terminal.viewWidth, 282);
      expect(view.terminal.viewHeight, 50);

      // The remounted key row still types to this pane, and still settles a
      // send only on this pane's ack (the rotation remount of 2026-09-08).
      await tester.tap(find.byKey(_gridKey));
      await tester.pump();
      await _type(tester, 'l');
      expect(harness.sendInputs, hasLength(1));
      expect(harness.sendInputs.single.paneId, _paneId);
      expect(harness.sendInputs.single.text, 'l');
      harness.emit(
        const Message.sendInputAck(
          SendInputAck(paneId: 'w3:p9', accepted: false),
        ),
      );
      await tester.pump();
      expect(find.text('Not sent: typing'), findsNothing);
      harness.emit(
        const Message.sendInputAck(
          SendInputAck(paneId: _paneId, accepted: false),
        ),
      );
      await tester.pump();
      expect(find.text('Not sent: typing'), findsOneWidget);
      await _flushDotTimer(tester);
    },
  );

  for (final TargetPlatform platform in <TargetPlatform>[
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    testWidgets(
      '${platform.name}: the title is a plain heading until the tree lands, then the '
      "platform's own button that opens the pane switcher; a tap on another pane closes the "
      'sheet and hands its id to onSwitchPane (R-03-113 item 1, R-31-08-25)',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final harness = _Harness();
        await _pumpScreen(tester, harness);

        // No tree yet: nothing to list, so the title is not a control.
        expect(_titleControl(), findsNothing);
        await tester.tap(find.text('pane 1'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(PaneSwitcherSheet), findsNothing);

        harness.emit(const Message.treeSnapshot(_switcherSnapshot));
        await tester.pump();
        expect(_titleControl(), findsOneWidget);
        expect(
          find.byType(
            platform == TargetPlatform.iOS ? CupertinoButton : TextButton,
          ),
          findsWidgets,
        );
        // The switcher affordance: the `expand_more` glyph beside the title.
        expect(
          find.descendant(
            of: _titleControl(),
            matching: find.byIcon(Symbols.expand_more_rounded),
          ),
          findsOneWidget,
        );

        await tester.tap(_titleControl());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(PaneSwitcherSheet), findsOneWidget);
        expect(
          tester
              .widget<Semantics>(_paneRow('claude, Blocked, main'))
              .properties
              .selected,
          isTrue,
        );
        expect(
          tester
              .widget<Semantics>(_paneRow('codex, Done, pane 2'))
              .properties
              .selected,
          isFalse,
        );
        // R-03-101: no layout task rides along.
        for (final String absent in <String>[
          'Split right',
          'Split down',
          'Zoom this pane',
          'Rename pane',
        ]) {
          expect(find.text(absent), findsNothing, reason: absent);
        }

        await tester.tap(find.text('pane 2'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(harness.switchedTo, 'w3:p2');
        expect(find.byType(PaneSwitcherSheet), findsNothing);
        // The switch is the caller's route replacement: this screen sent
        // nothing and still shows its own pane.
        expect(harness.sent.whereType<MessageHostAction>(), isEmpty);
        expect(find.text('plugin'), findsOneWidget);
        await _flushDotTimer(tester);
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      '${platform.name}: one agent tab uses its tab title alone (R-03-129)',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final harness = _Harness();
        await _pumpScreen(tester, harness);
        harness.emit(const Message.treeSnapshot(_snapshot));
        await tester.pump();
        expect(find.text('plugin'), findsOneWidget);
        expect(find.text(' / '), findsNothing);
        await _flushDotTimer(tester);
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      '${platform.name}: the title uses free width and truncates the tab first '
      '(R-31-08-25, mockup 08 callout 2)',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final harness = _Harness();
        await _pumpScreen(tester, harness);

        Future<void> showTitle(String tab, String paneName) async {
          harness.emit(
            Message.treeSnapshot(
              TreeSnapshot(
                workspaces: _snapshot.workspaces,
                tabs: [
                  TabSummary(
                    tabId: 'w3:t1',
                    workspaceId: 'w3',
                    title: tab,
                    focused: true,
                  ),
                ],
                panes: [
                  _pane.copyWith(label: paneName, agent: 'claude'),
                  _pane.copyWith(
                    paneId: 'w3:p2',
                    label: 'second',
                    agent: 'codex',
                    agentStatus: 'working',
                    focused: false,
                  ),
                ],
                agents: [
                  ..._snapshot.agents,
                  _snapshot.agents.first.copyWith(
                    paneId: 'w3:p2',
                    agentKind: 'codex',
                  ),
                ],
              ),
            ),
          );
          await tester.pump();
          await tester.pump();
        }

        const String longName =
            'Release review notes from all working branches';
        await showTitle(longName, 'main');
        expect(
          tester
              .renderObject<RenderParagraph>(find.text(longName))
              .didExceedMaxLines,
          isTrue,
        );
        // The separator is its own text, so the ellipsis on the tab never eats it.
        expect(find.text(' / '), findsOneWidget);
        expect(
          tester
              .renderObject<RenderParagraph>(find.text('main'))
              .didExceedMaxLines,
          isFalse,
        );

        await showTitle('git', longName);
        expect(
          tester
              .renderObject<RenderParagraph>(find.text(longName))
              .didExceedMaxLines,
          isTrue,
        );
        expect(tester.takeException(), isNull);
        await _flushDotTimer(tester);
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      '${platform.name}: the attention summary follows the live tree and hides at zero '
      '(R-03-113 item 4, R-31-08-26)',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final harness = _Harness();
        await _pumpScreen(tester, harness);
        expect(find.textContaining('waiting'), findsNothing);
        final int barsBefore = find.byType(StatusBar).evaluate().length;
        final Rect backBefore = tester.getRect(_backControl());

        harness.emit(const Message.treeSnapshot(_switcherSnapshot));
        await tester.pump();
        await tester.pump();
        expect(
          find.textContaining(RegExp(r'2 waiting.*1 done')),
          findsOneWidget,
        );
        // R-03-058/R-03-100: the words add no state mark or separator glyph.
        expect(find.byType(StatusBar), findsNWidgets(barsBefore));
        final Finder summary = find.textContaining('waiting');
        final Text text = tester.widget<Text>(summary);
        expect(
          text.textSpan!.toPlainText(includePlaceholders: false),
          matches(r'^2 waiting\s*1 done$'),
        );
        expect(text.semanticsLabel, '2 waiting, 1 done');
        if (platform == TargetPlatform.iOS) {
          // R-31-08-26/R-33-076: the subtitle sits inside `middle`, so the
          // native 44 row does not grow.
          expect(tester.getRect(_backControl()), backBefore);
          expect(
            tester.getSize(find.byType(CupertinoNavigationBar)).height,
            44,
          );
        }

        // R-31-08-26: a tree_update changes the done count.
        harness.emit(
          Message.treeUpdate(
            TreeUpdate(
              event: TreeEvent.paneAgentStatusChanged,
              pane: _switcherPane2.copyWith(agentStatus: 'working'),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(
          find.textContaining(RegExp(r'2 waiting.*0 done')),
          findsOneWidget,
        );

        // R-31-08-26: the line disappears when both counts reach zero.
        harness.emit(const Message.treeSnapshot(_snapshot));
        await tester.pump();
        await tester.pump();
        expect(find.textContaining('waiting'), findsNothing);
        await _flushDotTimer(tester);
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets(
    'landscape: the title control and the summary share the merged bar',
    (tester) async {
      final harness = _Harness();
      await _pumpScreen(tester, harness, landscape: true);
      harness.emit(const Message.treeSnapshot(_switcherSnapshot));
      // Nothing animates in the merged bar, so no frame is pending and the
      // stream event lands after the first pump; the second draws it.
      await tester.pump();
      await tester.pump();
      expect(find.byType(AppBar), findsNothing);
      expect(_titleControl(), findsOneWidget);
      expect(find.textContaining(RegExp(r'2 waiting.*1 done')), findsOneWidget);
      await tester.tap(_titleControl());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(PaneSwitcherSheet), findsOneWidget);
      await _flushDotTimer(tester);
    },
  );
}
