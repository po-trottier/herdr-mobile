/// Real-Host end-to-end UI test (`WP-25`): the production bootstrap
/// `app/lib/main.dart` against the emulator's preserved pairing, the real
/// Hub and the real Host, per the batch contract. Nothing is faked: no
/// `ProviderScope` override, no canned snapshot, no stub Host, no injected
/// agent event. Every assertion reads the real widget tree, real widget
/// geometry, or the real semantics tree (enabled through
/// `tester.ensureSemantics()`).
///
/// Runtime inputs (all non-secret, per the batch constraint — never a
/// pairing URI, phrase, handle or key, through `--dart-define`, source or
/// logs):
///
/// - `HERDR_E2E_REAL_WORKSPACE_ID` — the temporary workspace id.
/// - `HERDR_E2E_REAL_WORKSPACE_NAME` — its space-block name (`repo_name`,
///   else the workspace label).
/// - `HERDR_E2E_REAL_TAB_NAME` — the known tab title inside that space.
/// - `HERDR_E2E_REAL_SHELL_PANE_ID` — the agent-less shell pane id inside
///   that tab.
/// - `HERDR_E2E_REAL_SHELL_PANE_LABEL` — its display name.
/// - `HERDR_E2E_REAL_AGENT_PANE_ID` — the dedicated agent's pane id; the
///   notification rows key on it.
/// - `HERDR_E2E_REAL_HOST_NAME` — the computer's display name.
/// - `HERDR_E2E_REAL_SHELL_PANE_COLS` — the Host column count of the shell
///   pane (an `int`). Its 13 px grid must exceed both portrait and landscape
///   widths so both readable viewports can pan.
/// - `HERDR_E2E_REAL_SHELL_MARKER` — the non-secret ASCII text present in
///   the shell pane. Its first word must fit the initial readable window.
/// - `HERDR_E2E_REAL_NOTIFY_WAIT_SECONDS` — optional poll window (default
///   300) for a real `agent_status` transition of the dedicated agent.
/// - `HERDR_E2E_REAL_PAIR_WAIT_SECONDS` — optional window (default 900)
///   the test waits on `/welcome` for a real UI-driven pairing to
///   complete.
///
/// Exact command, from `app/`:
///
/// ```text
/// flutter test integration_test/real_host_ui_test.dart -d emulator-5554 \
///   --no-uninstall \
///   --dart-define=HERDR_E2E_REAL_WORKSPACE_ID=<id> \
///   --dart-define=HERDR_E2E_REAL_WORKSPACE_NAME=<name> \
///   --dart-define=HERDR_E2E_REAL_TAB_NAME=<tab> \
///   --dart-define=HERDR_E2E_REAL_SHELL_PANE_ID=<pane> \
///   --dart-define=HERDR_E2E_REAL_SHELL_PANE_LABEL=<label> \
///   --dart-define=HERDR_E2E_REAL_AGENT_PANE_ID=<pane> \
///   --dart-define=HERDR_E2E_REAL_HOST_NAME=<host> \
///   --dart-define=HERDR_E2E_REAL_SHELL_PANE_COLS=<cols> \
///   --dart-define=HERDR_E2E_REAL_SHELL_MARKER=<marker>
/// ```
///
/// Runtime prerequisites, each reported as a hard failure with its own
/// message, never masked as a skipped pass:
///
/// 1. A completed pairing with the Host in the device's platform
///    keystore, from an earlier run or done live. Run with
///    `--no-uninstall` (the tool's default uninstalls the app after an
///    integration test, which destroys that state): the paired install
///    then survives every rerun, and the harness may relaunch the same
///    binary without pairing again. When the keystore is empty anyway —
///    a cold start that lands
///    on `/welcome` prints one no-secret marker (`Awaiting manual pairing
///    through app UI`) and waits up to `HERDR_E2E_REAL_PAIR_WAIT_SECONDS`
///    (default 900) for the harness to pair through the real UI — either
///    by hand, or by opening the Host's real `herdr-remote://pair` deep
///    link, in which case the production router prefills the real
///    `ManualPairingScreen` and this test taps its enabled `Pair` button
///    once (the URI never passes through this file). A landing on
///    `/lock`, or no pairing inside that window, fails the test. This
///    file never accepts pairing secrets and never fakes persistence.
/// 2. The temporary workspace, tab, shell pane and dedicated agent exist
///    on the Host (the setup step creates them).
/// 3. The dedicated agent reaches a real `blocked`/`done` transition
///    inside each notification wait window (the setup step drives it), or
///    such an entry already sits in the session log when the test starts.
///    A second pane must also have a real notification before the first
///    mark-read action, so Remove all has a row after the single removal.
/// 4. Network: the device reaches the Hub the pairing record names.
/// 5. The terminal text size setting is 13 px. The device accepts real
///    portrait and landscape rotations. This test never changes settings.
/// 6. The shell pane contains the supplied marker. This run uses
///    `Terminal text is readable at normal size`.
///
/// What each phase proves, with the production source it reads:
///
/// - *Hierarchy* (`agent_list_screen.dart`, `Workspace` axis): the space
///   block `Semantics` label `<name>, N panes`, the tab sub-header
///   `Text(tab.title)` and the shell-pane row `Semantics` label
///   `<paneDisplayName>[, <title>]`, in that vertical order.
/// - *Create* (`create_sheet.dart` through the real `FloatingActionButton`
///   on the `Agents` screen): the menu opens with `New space`,
///   `New tab...` or `New tab in <name>`, `Split a pane` and `Cancel`
///   under the header `Create on <host>`; a real `New tab` create runs
///   (`host_action` `create_tab` over the live link) and the space's pane
///   count moves N to N+1 through the real `tree_update`.
/// - *Terminal modes* (`terminal_view_widget.dart`, keys `terminalGridArea`
///   and `terminalGridCells`): readable text starts at 13 px and permits
///   horizontal pan. The native `terminalOverviewToggle` button selects
///   Overview, which fits every column. Overview survives real platform
///   rotation through `SystemChrome.setPreferredOrientations`. Readable
///   restores the exact cell metrics. Host columns and rows never change,
///   `autoResize` stays false, and the grid width equals the painted cell
///   width times the Host column count. No view-size override exists.
/// - *Typed control chord* (`key_row.dart`, R-03-116): `ctrl` latched in the
///   key row, then `a` typed, with no palette, no popup and no route. The
///   chord reaches the real shell and moves its real cursor: a prefix typed
///   afterwards lands at the START of the line the phone typed before it, and
///   the line never runs.
/// - *Notifications* (`notifications_screen.dart`, R-31-07-03/04): the
///   dedicated agent's row arrives through a real `agent_status` event;
///   `Mark as read`, `Mark all as read`, `Remove` and `Remove all` act
///   through the revealed UI, and the read/removed states survive a real
///   `tree_request`/`tree_snapshot` round trip (the terminal screen's own
///   tree fetch, driven by real navigation) because the acks persist in
///   `PlainStore`. The OS-restart leg of persistence runs outside this
///   file, in the harness's relaunch step.
library;

import 'package:flutter/services.dart'
    show
        DeviceOrientation,
        SystemChannels,
        SystemChrome,
        TextEditingValue,
        TextSelection;
import 'package:flutter/widgets.dart'
    show
        ClipRect,
        EdgeInsetsGeometry,
        MediaQuery,
        Offset,
        Padding,
        Rect,
        Scrollable,
        Size,
        Text,
        TextDirection,
        ValueKey;
import 'package:flutter_slidable/flutter_slidable.dart' show Slidable;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/main.dart' as app;
import 'package:herdr_mobile/screens/agent_list_screen.dart'
    show AgentListScreen;
import 'package:herdr_mobile/screens/create_sheet.dart' show CreateSheet;
import 'package:herdr_mobile/screens/lock_screen.dart' show LockScreen;
import 'package:herdr_mobile/screens/manual_pairing_screen.dart'
    show ManualPairingScreen;
import 'package:herdr_mobile/screens/notifications_screen.dart'
    show NotificationsScreen;
import 'package:herdr_mobile/screens/welcome_screen.dart' show WelcomeScreen;
import 'package:herdr_mobile/widgets/app_filled_button.dart'
    show AppFilledButton;
import 'package:herdr_mobile/widgets/terminal_view_widget.dart'
    show TerminalViewWidget;
import 'package:integration_test/integration_test.dart';
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart'
    show AlertDialog, FloatingActionButton, NavigationBar;
import 'package:xterm2/xterm.dart'
    show TerminalSearch, TerminalView, TerminalViewState;

const String _workspaceId = String.fromEnvironment(
  'HERDR_E2E_REAL_WORKSPACE_ID',
);
const String _workspaceName = String.fromEnvironment(
  'HERDR_E2E_REAL_WORKSPACE_NAME',
);
const String _tabName = String.fromEnvironment('HERDR_E2E_REAL_TAB_NAME');
const String _shellPaneId = String.fromEnvironment(
  'HERDR_E2E_REAL_SHELL_PANE_ID',
);
const String _shellPaneLabel = String.fromEnvironment(
  'HERDR_E2E_REAL_SHELL_PANE_LABEL',
);
const String _agentPaneId = String.fromEnvironment(
  'HERDR_E2E_REAL_AGENT_PANE_ID',
);
const String _hostName = String.fromEnvironment('HERDR_E2E_REAL_HOST_NAME');
const int _shellPaneCols = int.fromEnvironment(
  'HERDR_E2E_REAL_SHELL_PANE_COLS',
);
const String _shellMarker = String.fromEnvironment(
  'HERDR_E2E_REAL_SHELL_MARKER',
);
const int _notifyWaitSeconds = int.fromEnvironment(
  'HERDR_E2E_REAL_NOTIFY_WAIT_SECONDS',
  defaultValue: 300,
);
const int _pairWaitSeconds = int.fromEnvironment(
  'HERDR_E2E_REAL_PAIR_WAIT_SECONDS',
  defaultValue: 900,
);

/// One poll step for every wait below. `pumpAndSettle` is never used: the
/// live app holds open streams and can animate, so every wait is bounded
/// and explicit.
const Duration _step = Duration(milliseconds: 250);

bool _found(Finder finder) => finder.evaluate().isNotEmpty;

/// One progress marker per phase boundary, so the harness knows when to
/// drive the dedicated agent's transitions. Markers carry phase words and
/// counts only — never an id, a name, or any content (AGENTS.md "Never
/// log").
void _phase(String name) {
  // ignore: avoid_print
  print('real_host_ui_test: $name');
}

/// Pumps in [_step] increments until [condition] holds. On timeout the
/// test fails with [description] — never a silent skip.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String description,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out after ${timeout.inSeconds}s waiting for: $description');
    }
    await tester.pump(_step);
  }
  await tester.pump();
}

/// A fixed wall-clock settle: [seconds] in 100 ms frames, so one real
/// network round trip and its animations can complete.
Future<void> _settle(WidgetTester tester, [int seconds = 2]) async {
  for (var i = 0; i < seconds * 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The space header's `Semantics` node label shape:
/// `<name>, N panes[, N needing attention]`.
final RegExp _spaceLabelPattern = RegExp(
  '^${RegExp.escape(_workspaceName)}, (\\d+) panes?',
);

Finder _spaceHeader() => find.bySemanticsLabel(_spaceLabelPattern);

/// The pane count of the temporary workspace, parsed from the real
/// semantics node of its space header.
int _spacePaneCount(WidgetTester tester) {
  final String label =
      tester.element(_spaceHeader()).renderObject?.debugSemantics?.label ?? '';
  final RegExpMatch? match = _spaceLabelPattern.firstMatch(label);
  if (match == null) {
    fail(
      'The space header semantics label "$label" does not match the '
      'expected "<name>, N panes" shape.',
    );
  }
  return int.parse(match.group(1)!);
}

/// The shell pane's row on the `Workspace` axis: one `Semantics` node
/// labelled `<paneDisplayName>` or `<paneDisplayName>, <title>`.
Finder _shellRow() => find.bySemanticsLabel(
  RegExp('^${RegExp.escape(_shellPaneLabel)}(, .*)?\$'),
);

/// A bottom-bar destination by label, scoped to the real `NavigationBar`
/// so an empty-state `Eyebrow` of the same word (`NOTIFICATIONS`,
/// `AGENTS`) cannot collide with the tap target.
Finder _destination(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

/// Makes [finder] genuinely tappable inside the screen of type [host]:
/// scrolls the host's lazy list until the row is built, `ensureVisible`s
/// it fully inside the scrollable's viewport (never half-hidden under the
/// bottom bar), settles, and fails unless it hit-tests. A finder that
/// merely evaluates is not enough — a row can be built but sit offscreen.
Future<Finder> _visible(
  WidgetTester tester,
  Finder finder, {
  required Type host,
}) async {
  if (!_found(finder.hitTestable())) {
    await tester.scrollUntilVisible(
      finder,
      120,
      scrollable: find
          .descendant(of: find.byType(host), matching: find.byType(Scrollable))
          .first,
      maxScrolls: 30,
    );
    await tester.ensureVisible(finder);
    await _settle(tester, 1);
  }
  if (!_found(finder.hitTestable())) {
    fail('A row stayed untappable after scrolling it into view.');
  }
  return finder;
}

/// Reveals a `Slidable` notification row's actions with the real gesture
/// (R-30-297): a horizontal drag on the row, then time for the reveal.
Future<void> _reveal(WidgetTester tester, Finder row) async {
  await _visible(tester, row, host: NotificationsScreen);
  await tester.drag(row, const Offset(-260, 0));
  await _settle(tester, 1);
}

/// Closes a revealed row without acting on it.
Future<void> _conceal(WidgetTester tester, Finder row) async {
  await tester.drag(row, const Offset(260, 0));
  await _settle(tester, 1);
}

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // fullyLive plus device-pointer propagation: real taps and keys from
  // the OS (the harness driving the pairing UI over adb) reach the app
  // itself instead of being intercepted by the binding's finder debug
  // path, and frames keep drawing while a wait loop pumps. Nothing about
  // this fakes input — the test's own gestures go through the same real
  // pipeline either way. Set before the test body so the binding's
  // post-test invariant sees it as the baseline.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  binding.shouldPropagateDevicePointerEvents = true;

  testWidgets(
    'real Host UI: hierarchy, + create, readable terminal, Overview, notifications',
    (WidgetTester tester) async {
      _requireInputs();
      // `testWidgets` enables semantics by default (its
      // `semanticsEnabled` parameter), which `find.bySemanticsLabel`
      // requires.
      _phase('launch/pair: start');
      await _launchToAgents(tester);
      _phase('launch/pair: done');
      _phase('hierarchy: start');
      final int panesBefore = await _hierarchyPhase(tester);
      _phase('hierarchy: done');
      _phase('create: start');
      await _createPhase(tester, panesBefore);
      _phase('create: done');
      _phase('terminal: start');
      await _terminalModesPhase(tester);
      _phase('terminal: done');
      _phase('notifications: start');
      await _notificationsPhase(tester);
      _phase('notifications: done');
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}

/// Every runtime input is present and self-consistent, or the test fails
/// here with the exact names to supply. Nothing defaults to a placeholder
/// Host object.
void _requireInputs() {
  final List<String> missing = <String>[
    if (_workspaceId.isEmpty) 'HERDR_E2E_REAL_WORKSPACE_ID',
    if (_workspaceName.isEmpty) 'HERDR_E2E_REAL_WORKSPACE_NAME',
    if (_tabName.isEmpty) 'HERDR_E2E_REAL_TAB_NAME',
    if (_shellPaneId.isEmpty) 'HERDR_E2E_REAL_SHELL_PANE_ID',
    if (_shellPaneLabel.isEmpty) 'HERDR_E2E_REAL_SHELL_PANE_LABEL',
    if (_agentPaneId.isEmpty) 'HERDR_E2E_REAL_AGENT_PANE_ID',
    if (_hostName.isEmpty) 'HERDR_E2E_REAL_HOST_NAME',
    if (_shellPaneCols <= 0) 'HERDR_E2E_REAL_SHELL_PANE_COLS',
    if (_shellMarker.trim().isEmpty) 'HERDR_E2E_REAL_SHELL_MARKER',
  ];
  if (missing.isNotEmpty) {
    fail(
      'Missing runtime inputs: ${missing.join(', ')}. Supply every one as '
      'a --dart-define (this file\'s header gives the exact command). The '
      'values come from the temporary real Host objects the setup step '
      'creates; none is secret.',
    );
  }
  if (!_shellPaneId.startsWith('$_workspaceId:')) {
    fail(
      'HERDR_E2E_REAL_SHELL_PANE_ID does not start with "$_workspaceId:" '
      '— the shell pane must live in the temporary workspace.',
    );
  }
}

/// Launches the production bootstrap and resolves the cold start: the
/// preserved pairing in the device keystore drives the real reconnect
/// (R-31-05-16) onto the `Agents` list. A landing on `Welcome` means no
/// paired computer exists on this device; a landing on `Lock` means App
/// Lock is on. Both are setup failures, reported as such.
Future<void> _launchToAgents(WidgetTester tester) async {
  app.main();
  await tester.pump(const Duration(seconds: 1));

  String? landing;
  await _pumpUntil(
    tester,
    () {
      if (_found(find.byType(AgentListScreen))) {
        landing = 'agents';
        return true;
      }
      if (_found(find.byType(WelcomeScreen))) {
        landing = 'welcome';
        return true;
      }
      if (_found(find.byType(LockScreen))) {
        landing = 'lock';
        return true;
      }
      return false;
    },
    description:
        'the cold start to reach the Agents list, the Welcome '
        'screen or the Lock screen',
    timeout: const Duration(seconds: 120),
  );

  switch (landing) {
    case 'welcome':
      // An install can replace the keystore state even without a data
      // clear. The harness pairs the installed app through the real UI
      // while this test waits: it opens the Host's real
      // `herdr-remote://pair` deep link, the production router prefills
      // the real ManualPairingScreen from it (R-22-034), and this loop
      // taps the screen's own enabled `Pair` button once. The URI never
      // passes through this test — no secret define, no constructed
      // PairingInput, no fake persistence.
      // ignore: avoid_print
      print(
        'real_host_ui_test: Awaiting manual pairing through app UI '
        '($_pairWaitSeconds-second window)',
      );
      String? resolved;
      bool pairTapped = false;
      final DateTime deadline = DateTime.now().add(
        const Duration(seconds: _pairWaitSeconds),
      );
      while (true) {
        if (_found(find.byType(AgentListScreen))) {
          resolved = 'agents';
          break;
        }
        if (_found(find.byType(LockScreen))) {
          resolved = 'lock';
          break;
        }
        final Finder pairButton = find.widgetWithText(AppFilledButton, 'PAIR');
        if (!pairTapped &&
            _found(find.byType(ManualPairingScreen)) &&
            _found(pairButton) &&
            tester.widget<AppFilledButton>(pairButton).onPressed != null) {
          // The deep link prefilled every field, so the button is
          // enabled. Hide the soft keyboard through the real platform
          // text-input channel, scroll the button into view, and tap it
          // once. The handshake then runs over the live link; a failure
          // surfaces on screen and the window below reports it.
          pairTapped = true;
          await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
          await tester.ensureVisible(pairButton);
          await tester.pump(_step);
          await tester.tap(pairButton);
        }
        if (DateTime.now().isAfter(deadline)) {
          fail(
            'No pairing completed within the $_pairWaitSeconds-second '
            'window: the harness must open the real pairing deep link on '
            'the device and let this test tap the enabled Pair button.',
          );
        }
        await tester.pump(_step);
      }
      if (resolved == 'lock') {
        fail(
          'Prerequisite missing: App Lock is enabled on this device, so '
          'the paired cold start landed on the Lock screen. Run the setup '
          'step with App Lock off.',
        );
      }
    case 'lock':
      fail(
        'Prerequisite missing: App Lock is enabled on this device, so the '
        'cold start landed on the Lock screen. Run the setup step with '
        'App Lock off.',
      );
  }

  // The one-time App Lock offer (R-03-091/R-30-521) can sit over the
  // Agents list on the first arrival. Decline it when present; the flag
  // persists, so later runs never see it.
  await _settle(tester, 3);
  // AppTextButton uppercases its label (mono.button, R-32).
  if (_found(find.text('NOT NOW'))) {
    await tester.tap(find.text('NOT NOW'));
    await _settle(tester);
  }

  await _pumpUntil(
    tester,
    () => _found(find.textContaining('Connected to $_hostName')),
    description: 'the connection strip "Connected to $_hostName."',
    timeout: const Duration(seconds: 60),
  );
}

/// The `Workspace` axis of the `Agents` list shows every pane, agent or
/// not (R-31-06-14): the temporary space block, its tab sub-header and
/// the agent-less shell pane row, in that vertical order. Returns the
/// space's pane count for the create phase.
Future<int> _hierarchyPhase(WidgetTester tester) async {
  await _pumpUntil(
    tester,
    () => _found(find.text('Workspace')),
    description: 'the Priority/Workspace grouping strip',
  );
  await tester.tap(find.text('Workspace'));
  await _settle(tester);

  // A session with many workspaces puts the temporary space below the
  // fold of a lazy list: narrow with the real pane search (R-31-06-30),
  // the production `SearchBar`, instead of polling rows that are not
  // built yet. A space whose own name matches keeps its whole subtree
  // (agent_list.dart's _narrow), so the tab and the shell pane stay.
  await _pumpUntil(
    tester,
    () => _found(find.byKey(AgentListScreen.searchFieldKey)),
    description: 'the Workspace axis search field',
  );
  await tester.enterText(
    find.byKey(AgentListScreen.searchFieldKey),
    _workspaceName,
  );
  // Hide the soft keyboard through the real platform text-input channel,
  // so its overlay cannot cover later tap targets.
  await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  await _settle(tester, 2);

  await _pumpUntil(
    tester,
    () => _found(_spaceHeader()),
    description:
        'the space block semantics label "$_workspaceName, N '
        'panes" on the Workspace axis',
  );
  final int paneCount = _spacePaneCount(tester);

  final Finder tabHeader = find.text(_tabName);
  final Finder shellRow = _shellRow();
  // Positions compare only inside one viewport: scroll the block into
  // view, then require all three rows onstage at once.
  await _visible(tester, shellRow, host: AgentListScreen);
  if (!_found(_spaceHeader()) || !_found(tabHeader)) {
    await _visible(tester, _spaceHeader(), host: AgentListScreen);
    if (!_found(tabHeader) || !_found(shellRow)) {
      fail(
        'The temporary workspace is taller than one viewport, so the '
        'space/tab/shell ordering cannot be asserted in one frame. '
        'Provision it smaller (one tab, few panes).',
      );
    }
  }

  // The hierarchy is real, not text-adjacent: the space header sits above
  // the tab sub-header, which sits above the shell pane row (R-31-06-29's
  // indent ladder in one card).
  final double spaceTop = tester.getTopLeft(_spaceHeader()).dy;
  final double tabTop = tester.getTopLeft(tabHeader).dy;
  final double shellTop = tester.getTopLeft(shellRow).dy;
  expect(
    spaceTop < tabTop && tabTop < shellTop,
    isTrue,
    reason:
        'Expected space header (y=$spaceTop) above tab header '
        '(y=$tabTop) above shell pane row (y=$shellTop).',
  );
  return paneCount;
}

/// The `+` create control (R-31-17-01, R-33-034) opens the real create
/// menu, and `New tab` runs a real create against the Host: the
/// acknowledgement pops the sheet and the live `tree_update` moves the
/// space's pane count from [panesBefore] to `panesBefore + 1`.
Future<void> _createPhase(WidgetTester tester, int panesBefore) async {
  await tester.tap(find.byType(FloatingActionButton));
  await _pumpUntil(
    tester,
    () => _found(find.text('Create on $_hostName')),
    description: 'the create sheet header "Create on $_hostName"',
    timeout: const Duration(seconds: 30),
  );
  expect(find.text('New space'), findsOneWidget);
  // AppTextButton uppercases its label (mono.button, R-32).
  expect(find.text('CANCEL'), findsOneWidget);
  expect(find.text('Split a pane'), findsOneWidget);

  final Finder pickerEntry = find.text('New tab...');
  if (_found(pickerEntry)) {
    await tester.tap(pickerEntry);
    await _pumpUntil(
      tester,
      () => _found(find.text('New tab in which space?')),
      description: 'the create sheet workspace picker',
    );
    // The picker row sits inside the sheet; the space header of the same
    // name stays in the tree behind the modal, so scope the finder. The
    // sheet's list scrolls (a Host with more workspaces than fit on one
    // screen puts the target below the fold), so route it through the
    // shared hit-testable helper before the tap.
    final Finder targetRow = find.descendant(
      of: find.byType(CreateSheet),
      matching: find.text(_workspaceName),
    );
    await _visible(tester, targetRow, host: CreateSheet);
    await tester.tap(targetRow);
  } else {
    // A single workspace on the Host preselects the row
    // `New tab in <name>` (create_sheet.dart's _workspaceContext rule).
    expect(
      find.text('New tab in $_workspaceName'),
      findsOneWidget,
      reason:
          'Expected either a "New tab..." picker entry or a '
          'preselected "New tab in $_workspaceName" row.',
    );
    await tester.tap(find.text('New tab in $_workspaceName'));
  }

  // A refusal stays on screen (the mockup's Error state); fail with it
  // rather than time out on a count that never moves.
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 90));
  while (true) {
    if (_found(find.text('Could not create that.'))) {
      fail(
        'The Host refused the real create; the refusal text is on screen '
        'in the create sheet.',
      );
    }
    if (!_found(find.byType(CreateSheet)) &&
        _found(_spaceHeader()) &&
        _spacePaneCount(tester) == panesBefore + 1) {
      break;
    }
    if (DateTime.now().isAfter(deadline)) {
      fail(
        'Timed out waiting for the real create to land: the sheet to '
        'close and the space pane count to move $panesBefore to '
        '${panesBefore + 1} through the live tree update.',
      );
    }
    await tester.pump(_step);
  }
}

/// Readable text starts at 13 px and pans. The native button selects
/// Overview. Real rotation preserves the mode and the Host dimensions.
Future<void> _terminalModesPhase(WidgetTester tester) async {
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
  await _pumpUntil(
    tester,
    () => tester.view.physicalSize.height > tester.view.physicalSize.width,
    description: 'the real portrait metrics before opening the terminal',
    timeout: const Duration(seconds: 30),
  );
  final Finder shellRow = await _visible(
    tester,
    _shellRow(),
    host: AgentListScreen,
  );
  await tester.tap(shellRow);
  await _waitForLiveGrid(tester);
  // Real frames let the grid adopt the painted cell metrics.
  await _settle(tester, 1);

  final terminal = tester
      .widget<TerminalView>(find.byType(TerminalView))
      .terminal;
  final int rows = terminal.viewHeight;
  expect(rows, greaterThan(0));
  final Size readableCellSize = _assertReadableGrid(
    tester,
    rows: rows,
    viewport: 'the initial portrait viewport',
  );
  _assertMarkerPaints(tester, viewport: 'the initial portrait viewport');
  await _panReadableGrid(tester);
  _assertGridGeometry(tester, rows: rows, viewport: 'the first readable pan');

  await tester.tap(_terminalModeControl(tester, 'Overview'));
  await _settle(tester, 1);
  _assertGridFits(tester, rows: rows, viewport: 'the portrait Overview');

  // The platform rotates the activity and reports real physical metrics.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  try {
    await _pumpUntil(
      tester,
      () => tester.view.physicalSize.width > tester.view.physicalSize.height,
      description: 'the real landscape metrics after the orientation change',
      timeout: const Duration(seconds: 30),
    );
    await _settle(tester, 3);
    expect(
      tester.widget<TerminalView>(find.byType(TerminalView)).terminal,
      same(terminal),
      reason: 'Rotation must keep the same live terminal.',
    );
    _assertGridFits(tester, rows: rows, viewport: 'the landscape Overview');

    await tester.tap(_terminalModeControl(tester, 'Readable'));
    await _settle(tester, 1);
    expect(
      _assertReadableGrid(
        tester,
        rows: rows,
        viewport: 'the restored landscape readable viewport',
      ),
      readableCellSize,
      reason: 'Readable must restore the exact 13 px cell metrics.',
    );
    _assertMarkerPaints(tester, viewport: 'the restored landscape viewport');
    await _panReadableGrid(tester);
    _assertGridGeometry(
      tester,
      rows: rows,
      viewport: 'the restored readable pan',
    );
  } finally {
    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
  }
  await _pumpUntil(
    tester,
    () => tester.view.physicalSize.height > tester.view.physicalSize.width,
    description: 'the real portrait metrics after restoring the orientation',
    timeout: const Duration(seconds: 30),
  );
  await _settle(tester, 3);
  expect(
    tester.widget<TerminalView>(find.byType(TerminalView)).terminal,
    same(terminal),
    reason: 'The return to portrait must keep the same live terminal.',
  );
  expect(
    _assertReadableGrid(
      tester,
      rows: rows,
      viewport: 'the restored portrait readable viewport',
    ),
    readableCellSize,
    reason: 'Portrait must keep the exact 13 px cell metrics.',
  );

  await _chordPhase(tester);

  await tester.tap(find.bySemanticsLabel('Back'));
  await _pumpUntil(
    tester,
    () => _found(find.byType(AgentListScreen)),
    description: 'the Agents list after leaving the terminal',
    timeout: const Duration(seconds: 30),
  );

  // Clear the search the hierarchy phase set: it lives as long as the
  // screen, and later phases deserve the full tree.
  if (_found(find.byKey(AgentListScreen.searchFieldKey))) {
    await tester.enterText(find.byKey(AgentListScreen.searchFieldKey), '');
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await _settle(tester);
  }
}

/// One committed keystroke burst into the key row's hidden text input client (R-03-054), the
/// way a keyboard commits it: one editing update that appends [text] to the client's last value.
Future<void> _typeLive(WidgetTester tester, String text) async {
  final String next =
      (tester.testTextInput.editingState!['text'] as String) + text;
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    ),
  );
  await tester.pump();
}

/// The typed control chord of R-03-116 (`key_row.dart`): a real typed line, then `ctrl`
/// latched and `a` typed, then a real typed prefix. The Host's own line must end up
/// reordered — the prefix in FRONT of the first text — which only a real cursor move on the
/// real shell can produce, and the line must never run. Nothing here leaves the terminal: no
/// palette, no popup, no route, no plugin action. Typing is live (R-03-054): a grid tap
/// raises the keyboard and every committed character goes to the pane at once, with no send
/// control.
Future<void> _chordPhase(WidgetTester tester) async {
  const String typed = 'echo herdr-chord-proof';
  const String prefix = ': ';
  final terminal = tester
      .widget<TerminalView>(find.byType(TerminalView))
      .terminal;
  String bufferText() => terminal.buffer.getText();
  int marks() => bufferText().split('herdr-chord-proof').length - 1;

  _phase('chord: typing the line the Host must hold unexecuted');
  await tester.tap(find.byType(TerminalViewWidget));
  await _settle(tester, 1);
  expect(tester.testTextInput.hasAnyClients, isTrue);
  await _typeLive(tester, typed);
  await _pumpUntil(
    tester,
    () => bufferText().contains(typed),
    description: 'the typed line "$typed" to echo back from the real shell',
    timeout: const Duration(seconds: 30),
  );
  expect(
    marks(),
    1,
    reason: 'a text send carries no Enter: the line waits on the prompt.',
  );

  _phase('chord: latching ctrl in the key row');
  await tester.tap(find.byKey(const ValueKey('keyRowCtrl')));
  await _settle(tester, 1);
  // The latch is local to the key row: the terminal is still mounted, nothing
  // was pushed over it, and the latch itself sent nothing.
  expect(_found(find.byType(TerminalViewWidget)), isTrue);
  expect(_found(find.text('CTRL')), isTrue);
  expect(marks(), 1, reason: 'latching ctrl must send nothing to the Host.');

  _phase('chord: ctrl then a, then a typed prefix');
  await _typeLive(tester, 'a');
  await _settle(tester, 2);
  expect(
    _found(find.text('CTRL')),
    isFalse,
    reason: 'the one-shot latch clears after its one key (R-31-09-08).',
  );
  expect(
    bufferText().contains(typed),
    isTrue,
    reason: 'ctrl+a moves the cursor; it must not run or clear the line.',
  );

  await _typeLive(tester, prefix);
  await _pumpUntil(
    tester,
    () => bufferText().contains('$prefix$typed'),
    description:
        'the Host line to read "$prefix$typed": the latched ctrl+a moved the '
        'real shell cursor to the line start',
    timeout: const Duration(seconds: 30),
  );
  expect(
    marks(),
    1,
    reason:
        'the line still waits on the prompt: an executed `echo` would print '
        'its argument a second time.',
  );
}

/// Waits for the terminal route's grid to reach the live phase with a
/// real `Terminal` behind it.
Future<void> _waitForLiveGrid(WidgetTester tester) async {
  await _pumpUntil(
    tester,
    () {
      final Finder finder = find.byType(TerminalViewWidget);
      if (!_found(finder)) return false;
      final TerminalViewWidget grid = tester.widget<TerminalViewWidget>(finder);
      return grid.phase.name == 'live' && grid.terminal != null;
    },
    description: 'the terminal grid of $_shellPaneId to go live',
    timeout: const Duration(seconds: 90),
  );
}

/// The width the cells must fit into: the full grid area minus the real
/// cutout inset the production widget reserves (R-21-039), read off the
/// actual `Padding` between `terminalGridArea` and `terminalGridCells` —
/// never an assumed percentage of the screen.
double _cellViewportWidth(WidgetTester tester, Finder area, Finder cells) {
  final Finder pad = find.descendant(
    of: area,
    matching: find.ancestor(of: cells, matching: find.byType(Padding)),
  );
  final double areaWidth = tester.getRect(area).width;
  if (!_found(pad)) return areaWidth;
  final EdgeInsetsGeometry inset = tester.widget<Padding>(pad.first).padding;
  return areaWidth - inset.resolve(TextDirection.ltr).horizontal;
}

Finder _columnWindow() => find.textContaining(RegExp(r'\bc\d+-\d+$'));

/// Returns the visible native button, not a callback or a replacement widget.
Finder _terminalModeControl(WidgetTester tester, String label) {
  final Finder control = find.byKey(const ValueKey('terminalOverviewToggle'));
  expect(control.hitTestable(), findsOneWidget);
  expect(
    find.descendant(of: control, matching: find.text(label)).hitTestable(),
    findsOneWidget,
  );
  final Size size = tester.getSize(control);
  expect(size.width, greaterThanOrEqualTo(48));
  expect(size.height, greaterThanOrEqualTo(48));
  return control;
}

/// Checks Host dimensions and the exact width of the painted grid.
Size _assertGridGeometry(
  WidgetTester tester, {
  required int rows,
  required String viewport,
}) {
  final TerminalView view = tester.widget<TerminalView>(
    find.byType(TerminalView),
  );
  expect(view.autoResize, isFalse, reason: '$viewport: no Device resize.');
  expect(
    view.terminal.viewWidth,
    _shellPaneCols,
    reason: '$viewport: Host columns.',
  );
  expect(view.terminal.viewHeight, rows, reason: '$viewport: Host rows.');
  final Size cell = tester
      .state<TerminalViewState>(find.byType(TerminalView))
      .renderTerminal
      .cellSize;
  expect(cell.width, greaterThan(0));
  expect(cell.height, greaterThan(0));
  expect(
    tester.getSize(find.byKey(const ValueKey('terminalGridCells'))).width,
    moreOrLessEquals(_shellPaneCols * cell.width, epsilon: 0.0001),
    reason:
        '$viewport: grid width must equal Host columns times painted cell width.',
  );
  return cell;
}

/// Checks the actual readable font and the visible clipping window.
Size _assertReadableGrid(
  WidgetTester tester, {
  required int rows,
  required String viewport,
}) {
  final TerminalViewWidget grid = tester.widget<TerminalViewWidget>(
    find.byType(TerminalViewWidget),
  );
  expect(grid.overview, isFalse, reason: '$viewport: Readable must be active.');
  expect(
    grid.textSize,
    13,
    reason: '$viewport: the readable rung must remain 13.',
  );
  expect(
    tester.widget<TerminalView>(find.byType(TerminalView)).textStyle.fontSize,
    13.0,
    reason: '$viewport: the painted font must be 13 px.',
  );
  final Size cell = _assertGridGeometry(tester, rows: rows, viewport: viewport);
  final Finder area = find.byKey(const ValueKey('terminalGridArea'));
  final Finder cells = find.byKey(const ValueKey('terminalGridCells'));
  expect(
    tester.getSize(cells).width,
    greaterThan(_cellViewportWidth(tester, area, cells)),
    reason:
        'Precondition: provision a Host pane wider than both 13 px viewports.',
  );
  expect(_columnWindow().hitTestable(), findsOneWidget);
  _terminalModeControl(tester, 'Overview');
  return cell;
}

/// The marker's first word must occupy the actual paint viewport.
/// The rest of the marker can extend beyond the horizontal clip.
void _assertMarkerPaints(WidgetTester tester, {required String viewport}) {
  final String marker = _shellMarker.trim();
  final String prefix = marker.split(RegExp(r'\s+')).first;
  final Finder finder = find.byType(TerminalView);
  final terminal = tester.widget<TerminalView>(finder).terminal;
  final render = tester.state<TerminalViewState>(finder).renderTerminal;
  // xterm reads this real padding inside its Scrollable viewport builder.
  final padding = MediaQuery.paddingOf(tester.element(finder));
  final Rect paintViewport =
      Rect.fromPoints(
        render.localToGlobal(Offset(padding.left, padding.top)),
        render.localToGlobal(
          Offset(
            render.size.width - padding.right,
            render.size.height - padding.bottom,
          ),
        ),
      ).intersect(
        tester.getRect(
          find
              .ancestor(
                of: find.byKey(const ValueKey('terminalGridCells')),
                matching: find.byType(ClipRect),
              )
              .first,
        ),
      );
  final (firstLine, lastLine) = render.debugVisibleLineRange();
  final matches = terminal.search(marker, caseSensitive: true);
  expect(
    matches,
    isNotEmpty,
    reason: '$viewport: the real shell marker is absent.',
  );
  final bool paints = matches.any((match) {
    final start = match.range.begin;
    if (start.y < firstLine || start.y > lastLine) return false;
    if (start.x + prefix.length > terminal.viewWidth) return false;
    // getOffset includes the real scroll offset. xterm truncates the row Y
    // coordinate during paint. localToGlobal includes the horizontal pan.
    final Offset cellOffset = render.getOffset(start);
    final Offset topLeft = Offset(
      cellOffset.dx,
      cellOffset.dy.truncateToDouble(),
    );
    final Rect glyphs = Rect.fromPoints(
      render.localToGlobal(topLeft),
      render.localToGlobal(
        topLeft +
            Offset(
              prefix.length * render.cellSize.width,
              render.cellSize.height,
            ),
      ),
    );
    return glyphs.left >= paintViewport.left &&
        glyphs.right <= paintViewport.right &&
        glyphs.top >= paintViewport.top &&
        glyphs.bottom <= paintViewport.bottom;
  });
  expect(
    paints,
    isTrue,
    reason:
        '$viewport: the marker glyphs must paint inside the real clipped viewport.',
  );
}

/// A real drag must move both the column window and the painted cells.
Future<void> _panReadableGrid(WidgetTester tester) async {
  final Finder cells = find.byKey(const ValueKey('terminalGridCells'));
  final String before = tester.widget<Text>(_columnWindow()).data!;
  final RegExp range = RegExp(r'c(\d+)-(\d+)$');
  final int firstBefore = int.parse(range.firstMatch(before)!.group(1)!);
  final Rect cellsBefore = tester.getRect(cells);
  final double widthBefore = tester.getSize(cells).width;
  final Rect area = tester.getRect(
    find.byKey(const ValueKey('terminalGridArea')),
  );
  await tester.dragFrom(area.center, Offset(-area.width / 3, 0));
  await _pumpUntil(
    tester,
    () =>
        _found(_columnWindow()) &&
        tester.widget<Text>(_columnWindow()).data != before,
    description: 'the readable column window to move after a horizontal pan',
    timeout: const Duration(seconds: 10),
  );
  final match = range.firstMatch(tester.widget<Text>(_columnWindow()).data!);
  expect(int.parse(match!.group(1)!), greaterThan(firstBefore));
  expect(int.parse(match.group(2)!), lessThanOrEqualTo(_shellPaneCols));
  expect(tester.getRect(cells).left, lessThan(cellsBefore.left));
  expect(tester.getSize(cells).width, widthBefore);
}

/// The fit assertion, valid at any viewport: every Host column is painted
/// inside the clip area, and the cells box width is exactly
/// `viewWidth x painted cell width`.
void _assertGridFits(
  WidgetTester tester, {
  required int rows,
  required String viewport,
}) {
  final Finder area = find.byKey(const ValueKey('terminalGridArea'));
  final Finder cells = find.byKey(const ValueKey('terminalGridCells'));
  final Rect areaRect = tester.getRect(area);
  final Rect cellsRect = tester.getRect(cells);
  final Size cellsSize = tester.getSize(cells);
  final double cellViewportWidth = _cellViewportWidth(tester, area, cells);
  final TerminalViewWidget grid = tester.widget<TerminalViewWidget>(
    find.byType(TerminalViewWidget),
  );
  expect(
    grid.overview,
    isTrue,
    reason: '$viewport: Overview must remain active.',
  );
  expect(
    grid.textSize,
    13,
    reason: '$viewport: Overview must not change the rung.',
  );
  expect(
    tester.widget<TerminalView>(find.byType(TerminalView)).textStyle.fontSize,
    lessThan(13.0),
    reason: '$viewport: Overview reduces the font of this wide Host grid.',
  );
  _assertGridGeometry(tester, rows: rows, viewport: viewport);
  expect(_columnWindow(), findsNothing);
  _terminalModeControl(tester, 'Readable');
  expect(
    cellsRect.left,
    greaterThanOrEqualTo(areaRect.left - 1),
    reason: '$viewport: the first Host column must be visible.',
  );
  expect(
    cellsRect.right,
    lessThanOrEqualTo(areaRect.right + 1),
    reason: '$viewport: the last Host column must be visible.',
  );
  // The fit contract is "every column visible", not a stretched-to-edge
  // font: the painted cell metric is quantized, so the box can sit a
  // fraction of a percent under the cell viewport width (measured: 0.4%
  // slack at 282 columns on the real device). Require at least 99% fill
  // of the unobscured cell viewport (the area minus the real cutout
  // inset) and never an overflow.
  expect(
    cellsSize.width,
    greaterThanOrEqualTo(cellViewportWidth * 0.99),
    reason:
        '$viewport: the cells box width ${cellsSize.width} must fill '
        'at least 99% of the unobscured cell viewport width '
        '$cellViewportWidth (Overview scales this wide grid to fit).',
  );
  expect(
    cellsSize.width,
    lessThanOrEqualTo(cellViewportWidth + 1),
    reason:
        '$viewport: the cells box must never overflow the unobscured '
        'cell viewport.',
  );
}

/// The Notifications lifecycle against real transport events only
/// (R-31-07-03, R-31-07-04). The dedicated agent's row arrives through a
/// real `agent_status`; the single and bulk actions run through the
/// revealed UI; the read/removed states survive a real
/// `tree_request`/`tree_snapshot` round trip (driven by real navigation,
/// never an injected event); and a second real transition of the same
/// agent re-adds the row after `Remove all`.
Future<void> _notificationsPhase(WidgetTester tester) async {
  await tester.tap(_destination('NOTIFICATIONS'));
  await _pumpUntil(
    tester,
    () => _found(find.byType(NotificationsScreen)),
    description: 'the Notifications screen',
    timeout: const Duration(seconds: 30),
  );
  // The create control belongs to the Agents destination alone
  // (R-31-17-01).
  expect(find.byType(FloatingActionButton), findsNothing);

  // Keep a second real row for Remove all after the single removal.
  final Finder notificationRows = find.descendant(
    of: find.byType(NotificationsScreen),
    matching: find.byType(Slidable),
  );
  _phase('awaiting bulk notification prerequisite');
  await _pumpUntil(
    tester,
    () {
      final paneIds = tester
          .widgetList<Slidable>(notificationRows)
          .map((Slidable item) => item.key)
          .whereType<ValueKey<String>>()
          .map((ValueKey<String> key) => key.value)
          .toSet();
      return paneIds.length >= 2;
    },
    description:
        'at least two real notification rows from distinct panes; '
        'drive a second real agent transition',
    timeout: const Duration(seconds: _notifyWaitSeconds),
  );

  // The first wait and the first mark-read are one real interaction: the
  // row's own overflow sheet carries `Mark as read` only while the row
  // is unread (R-31-07-09), so the real sheet is the unread detector —
  // never a semantics gate that could land on a merged ancestor. A row
  // left read from an earlier run gets its sheet opened and closed with
  // its real `Cancel`, and the wait continues. No fake event, no fake
  // unread signal.
  final Finder row = find.byKey(const ValueKey<String>(_agentPaneId));
  _phase('notifications: awaiting unread first transition');
  final Finder overflow = find.descendant(
    of: row,
    matching: find.byIcon(Symbols.more_vert_rounded),
  );
  final DateTime deadline = DateTime.now().add(
    const Duration(seconds: _notifyWaitSeconds),
  );
  while (true) {
    if (DateTime.now().isAfter(deadline)) {
      fail(
        'No UNREAD notification row appeared for pane $_agentPaneId '
        'within the $_notifyWaitSeconds-second window: the row stayed '
        'absent, or stayed read, the whole time. The dedicated agent '
        'must reach a fresh blocked/done transition during this window.',
      );
    }
    if (_found(row)) {
      await _visible(tester, row, host: NotificationsScreen);
      // The row's Semantics merges the overflow control's label into the
      // whole-row node: assert the label exists (production surface),
      // but tap the real glyph inside the row.
      expect(
        find.descendant(
          of: row,
          matching: find.bySemanticsLabel('Notification actions'),
        ),
        findsOneWidget,
      );
      await tester.tap(overflow);
      await _pumpUntil(
        tester,
        () => _found(find.text('Cancel')),
        description: 'the row actions sheet',
        timeout: const Duration(seconds: 15),
      );
      if (_found(find.text('Mark as read'))) {
        await tester.tap(find.text('Mark as read'));
        await _settle(tester);
        break;
      }
      // Read leftover: close through the sheet's own real Cancel and
      // keep waiting for a genuinely fresh transition.
      await tester.tap(find.text('Cancel'));
      await _settle(tester, 1);
    }
    await tester.pump(_step);
  }
  _phase('notifications: first transition seen');
  await _reveal(tester, row);
  expect(
    find.text('Mark as read'),
    findsNothing,
    reason: 'A read row offers no Mark as read action (R-31-07-09).',
  );
  expect(find.text('Remove'), findsOneWidget);
  await _conceal(tester, row);
  _phase('notifications: single mark-read done');

  // The read state survives a real tree_snapshot rehydration: opening a
  // terminal sends the screen's own tree_request (terminal_screen.dart's
  // tree fetch), and AgentStatusService rebuilds the log from the reply
  // with the PlainStore acks.
  await _treeRoundTrip(tester);
  await _reveal(tester, row);
  expect(
    find.text('Mark as read'),
    findsNothing,
    reason:
        'The read state must survive a real tree_snapshot '
        'rehydration (R-31-07-03, the ack persisted in PlainStore).',
  );
  expect(find.text('Remove'), findsOneWidget);
  await _conceal(tester, row);
  _phase('notifications: read persisted across refresh');

  // Mark all as read through the app-bar control (R-31-07-03).
  await tester.tap(find.bySemanticsLabel('Mark all as read'));
  await _settle(tester);
  final bool? markAllEnabled = tester
      .element(find.bySemanticsLabel('Mark all as read'))
      .renderObject
      ?.debugSemantics
      ?.flagsCollection
      .isEnabled
      .toBoolOrNull();
  expect(
    markAllEnabled,
    isFalse,
    reason:
        'With no unread row left, the Mark all as read control must '
        'be disabled (R-32-502).',
  );
  _phase('notifications: mark-all done');

  // Remove the dedicated agent's row through the revealed action
  // (R-31-07-04). It must stay removed across a second real rehydration.
  await _reveal(tester, row);
  await tester.tap(find.text('Remove'));
  await _pumpUntil(
    tester,
    () => !_found(row),
    description: 'the dedicated agent row to leave the list after Remove',
    timeout: const Duration(seconds: 30),
  );
  await _treeRoundTrip(tester);
  await _settle(tester);
  expect(
    row,
    findsNothing,
    reason:
        'A removed row stays removed across a real tree_snapshot '
        'rehydration (R-31-07-04).',
  );
  _phase('notifications: removal persisted across refresh');

  // Remove all, with the real confirmation dialog (section 7.17).
  await tester.tap(find.bySemanticsLabel('Remove all'));
  await _pumpUntil(
    tester,
    () => _found(find.text('Remove all notifications?')),
    description: 'the Remove all confirmation dialog',
    timeout: const Duration(seconds: 30),
  );
  // The toolbar control carries its name as a Semantics label only; the
  // plain `Text` match is the dialog's destructive button (the R-33-074
  // dialog renders the label un-uppercased in a TextButton). Scope to the
  // real dialog and require a native hit test — never a blind tap.
  final Finder confirm = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.text('Remove all'),
  );
  await _pumpUntil(
    tester,
    () => _found(confirm.hitTestable()),
    description: 'the Remove all confirmation button, hit-testable',
    timeout: const Duration(seconds: 30),
  );
  await tester.tap(confirm);
  await _pumpUntil(
    tester,
    () => _found(find.text('No notifications.')),
    description: 'the empty Notifications state after Remove all',
    timeout: const Duration(seconds: 30),
  );
  _phase('notifications: remove-all done');

  // The second real transition: the dedicated agent reaches blocked/done
  // again, a new (paneId, status, at) identity, so the row comes back as
  // unread even though the earlier identity was removed (R-31-07-04's ack
  // keys on the change identity).
  _phase('notifications: awaiting second transition');
  await _pumpUntil(
    tester,
    () => _found(row),
    description:
        'a second real notification row for pane $_agentPaneId '
        'after Remove all — the dedicated agent must transition again '
        'during this window',
    timeout: const Duration(seconds: _notifyWaitSeconds),
  );
  _phase('notifications: second transition seen');
  await _reveal(tester, row);
  expect(
    find.text('Mark as read'),
    findsOneWidget,
    reason:
        'A row that arrives through a live transition is unread, so '
        'it offers Mark as read.',
  );
  expect(find.text('Remove'), findsOneWidget);
  await _conceal(tester, row);
}

/// Opens the shell pane's terminal and returns to the Notifications
/// screen: real navigation that drives one real `tree_request`/
/// `tree_snapshot` round trip through the production services.
Future<void> _treeRoundTrip(WidgetTester tester) async {
  await tester.tap(_destination('AGENTS'));
  await _pumpUntil(
    tester,
    () => _found(find.byType(AgentListScreen)),
    description: 'the Agents tab',
    timeout: const Duration(seconds: 30),
  );
  final Finder shellRow = await _visible(
    tester,
    _shellRow(),
    host: AgentListScreen,
  );
  await tester.tap(shellRow);
  await _waitForLiveGrid(tester);
  // The tree reply rides the same broadcast message stream
  // AgentStatusService listens to; give its async rehydration real time.
  await _settle(tester, 3);
  await tester.tap(find.bySemanticsLabel('Back'));
  await _pumpUntil(
    tester,
    () => _found(find.byType(AgentListScreen)),
    description: 'the Agents list after the terminal round trip',
    timeout: const Duration(seconds: 30),
  );
  await tester.tap(_destination('NOTIFICATIONS'));
  await _pumpUntil(
    tester,
    () => _found(find.byType(NotificationsScreen)),
    description: 'the Notifications screen after the round trip',
    timeout: const Duration(seconds: 30),
  );
}
