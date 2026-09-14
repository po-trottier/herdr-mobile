/// End-to-end cases for the terminal screen of `docs/31-mockups/08-terminal.md` and
/// `09-key-row.md`, driven against the real stub Host
/// `crates/herdr-relay/src/bin/e2e-stub-host.rs` through a real, locally run
/// `herdr-relay-hub`, per `docs/40-repo-tooling.md` §5.4 (R-40-037). The Device side is
/// the app's own `RelayConnection` (real `Noise_XXpsk0`, real frame codec, real
/// WebSocket), the real `AgentListScreen`/`TerminalScreen` and their real
/// `TerminalService`/`KeyRow` composition — the same harness shape
/// `host_dispatch_test.dart` and `live_review_fixes_test.dart` established.
///
/// This file runs on the Android emulator, so it cannot spawn the two Rust processes
/// itself. Start them first, on the workstation, then run this file against them. The
/// emulator reaches the workstation's loopback as `10.0.2.2` (R-22-039 permits the
/// `http://` origin: `10.0.0.0/8`). Exact commands, from `crates/`:
///
/// ```text
/// HERDR_RELAY_LISTEN=127.0.0.1:18922 HERDR_RELAY_METRICS_LISTEN=127.0.0.1:19292 \
///   cargo run -p herdr-relay-hub
/// RELAY_ADDR=127.0.0.1:18922 HANDLE=AQIDBAUGBwgJCgsMDQ4PEQ \
///   PHRASE=remedy-tapestry-hubcap-oversleep-jailbird-kinetic \
///   cargo run -p herdr-relay --bin e2e-stub-host
/// ```
///
/// then, from `app/`: `flutter test integration_test/terminal_test.dart -d
/// emulator-5554`. The three `--dart-define`s `HERDR_E2E_RELAY_ORIGIN`,
/// `HERDR_E2E_HANDLE` and `HERDR_E2E_PHRASE` override the defaults above.
/// The phone must accept real portrait and landscape rotations. The mode cases
/// use its physical metrics, the bundled font, and the native Overview button.
///
/// The stub exits after one Device session, so every case below shares the one
/// connection `setUpAll` opens (the same pattern `host_dispatch_test.dart` uses). The
/// stub also dies on its own after roughly CONNECT_TIMEOUT while it waits for a
/// Device that never comes, and the local process supervisor restarts it; the connect
/// below therefore retries until a freshly registered stub answers.
///
/// What each case asserts on the Device side, the stub's own stdout trail proves on
/// the Host side: one `send_input_received` line per `send_input` it observed, one
/// `scroll_read` per `scroll_request`. The run's report checks those lines by hand; the
/// cases themselves read the wire the way `host_dispatch_test.dart` does — typed replies
/// and ack frames on `RelayConnection.messages`.
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart'
    show DeviceOrientation, SystemChrome, TextEditingValue, TextSelection;
import 'package:flutter/widgets.dart'
    show
        Brightness,
        ClipRect,
        GlobalKey,
        NavigatorState,
        Offset,
        Rect,
        Semantics,
        Size,
        SizedBox,
        Text,
        ValueKey,
        Widget;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/app.dart'
    show appThemeFrom, sdkMaterialLocalizations;
import 'package:herdr_mobile/core/result/result.dart' show Ok, Result;
import 'package:herdr_mobile/models/frame.dart';
import 'package:herdr_mobile/models/message.dart';
import 'package:herdr_mobile/models/messages/device_info.dart';
import 'package:herdr_mobile/models/messages/platform.dart' as wire;
import 'package:herdr_mobile/models/messages/scroll_response.dart';
import 'package:herdr_mobile/models/messages/send_input_ack.dart';
import 'package:herdr_mobile/screens/agent_list_screen.dart';
import 'package:herdr_mobile/screens/terminal_screen.dart';
import 'package:herdr_mobile/services/agent_status.dart' show AttentionItem;
import 'package:herdr_mobile/services/biometric_gate.dart';
import 'package:herdr_mobile/services/connectivity.dart';
import 'package:herdr_mobile/services/keystore.dart';
import 'package:herdr_mobile/services/noise.dart';
import 'package:herdr_mobile/services/origin.dart';
import 'package:herdr_mobile/services/relay.dart';
import 'package:herdr_mobile/widgets/status_strip.dart';
import 'package:herdr_mobile/widgets/terminal_view_widget.dart';
import 'package:herdr_mobile/widgets/theme/chrome_scheme.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:material_ui/material_ui.dart'
    show AppBar, MaterialApp, MaterialPageRoute;
import 'package:mocktail/mocktail.dart';
import 'package:xterm2/xterm.dart' show TerminalView, TerminalViewState;

/// The workstation's relay as the emulator sees it; the same port
/// `host_dispatch_test.dart` uses.
const String _relayOrigin = String.fromEnvironment(
  'HERDR_E2E_RELAY_ORIGIN',
  defaultValue: 'http://10.0.2.2:18922',
);

/// The handle the running `e2e-stub-host` registered with — the same stub instance
/// `host_dispatch_test.dart` drives.
const String _handle = String.fromEnvironment(
  'HERDR_E2E_HANDLE',
  defaultValue: 'AQIDBAUGBwgJCgsMDQ4PEQ',
);

/// `docs/11-relay-protocol.md` §8.1's worked pairing phrase, a documented fixture and
/// not a secret, shared with `host_dispatch_test.dart` and the stub's own tests.
const String _phrase = String.fromEnvironment(
  'HERDR_E2E_PHRASE',
  defaultValue: 'remedy-tapestry-hubcap-oversleep-jailbird-kinetic',
);

/// MUST match `TALL_PANE_ID` in `e2e-stub-host.rs`: tab `t2` "plugin", label "main",
/// 144x50, 240 rows of scrollback, agent `claude` `working`.
const String _tallPaneId = 'w1:p2';

/// MUST match `PANE_ID` in `e2e-stub-host.rs`: tab `t1` "main", label "shell",
/// 80x24, no agent.
const String _shellPaneId = 'w1:p1';

/// MUST match `CANNED_SCROLLBACK`'s first line in `e2e-stub-host.rs`.
const String _cannedScrollbackHead = 'HERDR-E2E-STUB-SCROLLBACK-2b8e44';

/// The text case 4 sends, unique in the stub's stdout trail
/// (`send_input_received` carries it verbatim).
const String _sentText = 'herdr-e2e-terminal-case-4';

const String _deviceId = 'e2e-terminal-device';
const String _deviceName = 'E2E Terminal Harness';

const Duration _replyTimeout = Duration(seconds: 10);

class _MockLocalAuthentication extends Mock implements LocalAuthentication {}

class _MockKeystoreService extends Mock implements KeystoreService {}

class _MockConnectivity extends Mock implements Connectivity {}

ConnectivityWatcher _noOpConnectivityWatcher() {
  final connectivity = _MockConnectivity();
  when(() => connectivity.onConnectivityChanged)
      .thenAnswer((_) => const Stream<List<ConnectivityResult>>.empty());
  return ConnectivityWatcher(connectivity: connectivity);
}

/// Mirrors `host_dispatch_test.dart`'s `_unlockedGate`: a real gate over a fresh
/// Curve25519 key, with `local_auth` and the platform keystore mocked so no prompt
/// appears on the emulator.
Future<BiometricGate> _unlockedGate() async {
  final localAuth = _MockLocalAuthentication();
  final mockKeystore = _MockKeystoreService();
  final keyPair = await X25519().newKeyPair();
  when(
    () =>
        localAuth.authenticate(localizedReason: any(named: 'localizedReason')),
  ).thenAnswer((_) async => true);
  when(() => mockKeystore.deviceKeyPair()).thenAnswer((_) async => Ok(keyPair));
  final gate = BiometricGate(
    appLockEnabled: true,
    localAuth: localAuth,
    keystore: mockKeystore,
    setNativeLocked: (_) {},
  );
  expect(await gate.unlock(), isA<Ok<void>>());
  return gate;
}

/// Connects the app's real relay stack to the stub Host, retrying until a freshly
/// restarted stub has registered its handle again (the stub exits when its 30-second
/// wait for a Device elapses, and the supervisor restarts it).
Future<RelayConnection> _connect() async {
  final origin = (parseRelayOrigin(_relayOrigin) as Ok<RelayOrigin>).value;
  final psk = await pskFromPhrase(_phrase);
  Object? lastFailure;
  for (var attempt = 0; attempt < 30; attempt++) {
    final connection = RelayConnection(
      connectivityWatcher: _noOpConnectivityWatcher(),
    );
    final Result<void> result;
    try {
      result = await connection.connect(
        origin: origin,
        handle: _handle,
        mode: PairingMode(psk: psk),
        gate: await _unlockedGate(),
        deviceInfo: const DeviceInfo(
          protocol: frameProtocolVersion,
          deviceId: _deviceId,
          deviceName: _deviceName,
          platform: wire.Platform.android,
          osVersion: '16',
          appVersion: '0.1.0',
        ),
      );
    } on Object catch (error) {
      await connection.dispose();
      lastFailure = error;
      await Future<void>.delayed(const Duration(seconds: 2));
      continue;
    }
    if (result is Ok<void>) {
      expect(connection.isConnected, isTrue);
      return connection;
    }
    await connection.dispose();
    lastFailure = result;
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  fail(
    'no connection to the stub Host on $_relayOrigin within ~60 s (is '
    'e2e-stub-host running with HANDLE=$_handle?): $lastFailure',
  );
}

/// The real app root's theme and localisations, as
/// `live_review_fixes_test.dart` builds them.
Future<void> _pumpApp(WidgetTester tester, Widget home) => tester.pumpWidget(
  MaterialApp(
    debugShowCheckedModeBanner: false,
    localizationsDelegates: sdkMaterialLocalizations,
    theme: appThemeFrom(ChromeScheme.fixed(Brightness.light)),
    home: home,
  ),
);

/// Pumps real frames until [condition] holds, or fails after [timeout]. The live
/// binding runs on the real clock, so wire round trips take real time here.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 15),
  required String reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (condition()) return;
  }
  fail('$reason (not true within $timeout)');
}

bool _visible(Finder finder) => finder.evaluate().isNotEmpty;

/// Real frames let the grid adopt the painted cell metrics after layout.
Future<void> _settle(WidgetTester tester, [int seconds = 1]) async {
  for (var i = 0; i < seconds * 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder _columnWindow() => find.textContaining(RegExp(r'\bc\d+-\d+$'));

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

/// Checks the mode, Host dimensions, and actual painted cell geometry.
Size _assertGridGeometry(
  WidgetTester tester, {
  required int columns,
  required int rows,
  bool overview = false,
}) {
  final TerminalViewWidget grid = tester.widget<TerminalViewWidget>(
    find.byType(TerminalViewWidget),
  );
  final TerminalView view = tester.widget<TerminalView>(
    find.byType(TerminalView),
  );
  expect(grid.overview, overview);
  expect(grid.textSize, 13, reason: 'The readable rung must remain 13.');
  expect(view.textStyle.fontSize, overview ? lessThanOrEqualTo(13.0) : 13.0);
  expect(view.autoResize, isFalse);
  expect(view.terminal.viewWidth, columns);
  expect(view.terminal.viewHeight, rows);
  final Size cell = tester
      .state<TerminalViewState>(find.byType(TerminalView))
      .renderTerminal
      .cellSize;
  expect(cell.width, greaterThan(0));
  expect(cell.height, greaterThan(0));
  final Finder cells = find.byKey(const ValueKey('terminalGridCells'));
  expect(
    tester.getSize(cells).width,
    moreOrLessEquals(columns * cell.width, epsilon: 0.0001),
    reason: 'Grid width must equal Host columns times painted cell width.',
  );
  if (overview) {
    // The actual clip includes the production cutout padding.
    final Rect clip = tester.getRect(
      find.ancestor(of: cells, matching: find.byType(ClipRect)).first,
    );
    final Rect painted = tester.getRect(cells);
    expect(painted.left, greaterThanOrEqualTo(clip.left - 1));
    expect(painted.right, lessThanOrEqualTo(clip.right + 1));
    expect(_columnWindow(), findsNothing);
  }
  _terminalModeControl(tester, overview ? 'Readable' : 'Overview');
  return cell;
}

/// A real drag must move both the column window and the painted cells.
Future<void> _panReadableGrid(WidgetTester tester) async {
  expect(_columnWindow().hitTestable(), findsOneWidget);
  final Finder cells = find.byKey(const ValueKey('terminalGridCells'));
  final String before = tester.widget<Text>(_columnWindow()).data!;
  final RegExp range = RegExp(r'c(\d+)-(\d+)$');
  final int firstBefore = int.parse(range.firstMatch(before)!.group(1)!);
  final Rect cellsBefore = tester.getRect(cells);
  final double widthBefore = tester.getSize(cells).width;
  final Rect area = tester.getRect(
    find.byKey(const ValueKey('terminalGridArea')),
  );
  expect(widthBefore, greaterThan(area.width));
  await tester.dragFrom(area.center, Offset(-area.width / 3, 0));
  await _pumpUntil(
    tester,
    () =>
        _visible(_columnWindow()) &&
        tester.widget<Text>(_columnWindow()).data != before,
    reason: 'the readable column window never moved after a horizontal pan',
  );
  final match = range.firstMatch(tester.widget<Text>(_columnWindow()).data!);
  expect(int.parse(match!.group(1)!), greaterThan(firstBefore));
  expect(tester.getRect(cells).left, lessThan(cellsBefore.left));
  expect(tester.getSize(cells).width, widthBefore);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late RelayConnection connection;

  /// The terminal screen for [paneId], composed exactly the way
  /// `routing.dart`'s `/hosts/:hostId/panes/:paneId` route composes it.
  Widget terminalScreen(String paneId) => TerminalScreen(
    hostId: connection.lastHostInfo!.hostId,
    paneId: paneId,
    hostName: connection.lastHostInfo!.hostName,
    messages: connection.messages,
    connectionState: connection.connectionState,
    initialConnectionState: const RelayConnected(),
    send: connection.send,
    watchPane: connection.watchPane,
    unwatchPane: connection.unwatchPane,
  );

  /// Opens [paneId] in portrait with the real platform metrics.
  Future<void> pumpTerminal(WidgetTester tester, String paneId) async {
    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
    await _pumpApp(tester, terminalScreen(paneId));
    await _pumpUntil(
      tester,
      () => tester.view.physicalSize.height > tester.view.physicalSize.width,
      timeout: const Duration(seconds: 30),
      reason: 'the real portrait metrics never arrived',
    );
  }

  /// Waits until the pane's frames have landed: the strip's `<cols>x<rows>`
  /// readout is the proof `watch_ack` arrived and the grid resized.
  Future<void> awaitLive(WidgetTester tester, String sizeReadout) => _pumpUntil(
    tester,
    () => _visible(find.textContaining(sizeReadout)),
    reason: 'the $sizeReadout readout never appeared',
  );

  /// Unmounts the case's screen so its `detach` sends `unwatch_pane` before the
  /// next case attaches, and lets the frame reach the wire.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 300));
  }

  setUpAll(() async {
    connection = await _connect();
  });

  tearDownAll(() async {
    await connection.dispose();
  });

  testWidgets(
    'opening the tall pane shows readable 13 px text, the title, the live dot and '
    'a LIVE strip, never PAUSED while frames arrive (R-21-041)',
    (WidgetTester tester) async {
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.portraitUp,
      ]);
      final navigatorKey = GlobalKey<NavigatorState>();
      String? openedPaneId;
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
          localizationsDelegates: sdkMaterialLocalizations,
          theme: appThemeFrom(ChromeScheme.fixed(Brightness.light)),
          home: AgentListScreen(
            hostId: connection.lastHostInfo!.hostId,
            hostName: connection.lastHostInfo!.hostName,
            messages: connection.messages,
            connectionState: connection.connectionState,
            initialConnectionState: const RelayConnected(),
            send: connection.send,
            unseenAttention: const Stream<List<AttentionItem>>.empty(),
            currentAttention: const <AttentionItem>[],
            onMarkSeen: (_) {},
            onNotePaneOpened: (_) {},
            onOpenPane: (String paneId) {
              openedPaneId = paneId;
              navigatorKey.currentState!.push(
                MaterialPageRoute<void>(builder: (_) => terminalScreen(paneId)),
              );
            },
          ),
        ),
      );
      await _pumpUntil(
        tester,
        () => tester.view.physicalSize.height > tester.view.physicalSize.width,
        timeout: const Duration(seconds: 30),
        reason: 'the real portrait metrics never arrived',
      );

      // The agent list loads the stub's canned tree: one row, the working
      // `claude` agent of pane w1:p2.
      await _pumpUntil(
        tester,
        () => _visible(find.text('claude')),
        reason: 'the claude row never appeared on the agent list',
      );
      await tester.tap(find.text('claude'));
      expect(openedPaneId, _tallPaneId);

      // The pushed terminal screen attaches, reads the tree, and paints. The
      // tree reply races the watch_ack, so the title gets its own wait.
      await awaitLive(tester, '144x50');
      await _pumpUntil(
        tester,
        () => _visible(find.text('plugin / ')),
        reason: 'the tree never answered the open',
      );
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('plugin / '),
        ),
        findsOneWidget,
        reason: 'the app bar carries the tab title from the tree',
      );
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('main')),
        findsOneWidget,
        reason: 'the app bar carries the pane display name from the tree',
      );
      // The dot is a `Semantics` widget labelled with the connection word;
      // read the widget tree, not the platform semantics tree.
      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is Semantics && widget.properties.label == 'live',
        ),
        findsOneWidget,
        reason: 'the app bar live dot announces the connection word',
      );
      expect(find.text('LIVE'), findsOneWidget);
      // Readable is the default. All 144 Host columns retain 13 px text.
      await _pumpUntil(
        tester,
        () => _visible(find.textContaining(RegExp(r'^144x50  c1-\d+$'))),
        reason: 'the default readable column window never appeared',
      );
      await _settle(tester);
      _assertGridGeometry(tester, columns: 144, rows: 50);
      expect(_columnWindow().hitTestable(), findsOneWidget);

      // R-21-041: a pane taller than the viewport, parked at the live bottom,
      // reads LIVE while frames arrive — never PAUSED.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('PAUSED'), findsNothing);
        expect(find.text('LIVE'), findsOneWidget);
      }

      await unmount(tester);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets('default readable text pans, Overview fits, and Readable restores 13 px and '
      'pan (R-21-037, R-21-008)', (WidgetTester tester) async {
    await pumpTerminal(tester, _tallPaneId);
    await awaitLive(tester, '144x50');
    await _pumpUntil(
      tester,
      () => _visible(find.textContaining(RegExp(r'^144x50  c1-\d+$'))),
      reason: 'the default readable column window never appeared',
    );
    await _settle(tester);
    final Size readableCellSize = _assertGridGeometry(
      tester,
      columns: 144,
      rows: 50,
    );
    await _panReadableGrid(tester);
    _assertGridGeometry(tester, columns: 144, rows: 50);

    await tester.tap(_terminalModeControl(tester, 'Overview'));
    await _settle(tester);
    _assertGridGeometry(tester, columns: 144, rows: 50, overview: true);
    expect(find.text('144x50'), findsOneWidget);

    await tester.tap(_terminalModeControl(tester, 'Readable'));
    await _settle(tester);
    expect(
      _assertGridGeometry(tester, columns: 144, rows: 50),
      readableCellSize,
      reason: 'Readable must restore the exact 13 px cell metrics.',
    );
    await _panReadableGrid(tester);
    _assertGridGeometry(tester, columns: 144, rows: 50);

    await unmount(tester);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets(
    'a grid tap focuses the input field and sends nothing (R-31-08-08)',
    (WidgetTester tester) async {
      var ackCount = 0;
      final ackSub = connection.messages
          .where((message) => message is MessageSendInputAck)
          .listen((_) => ackCount++);
      addTearDown(ackSub.cancel);

      await pumpTerminal(tester, _tallPaneId);
      await awaitLive(tester, '144x50');

      await tester.tap(find.byType(TerminalViewWidget));
      await tester.pump();
      expect(
        tester.testTextInput.hasAnyClients,
        isTrue,
        reason: 'the grid tap attached the key row\'s hidden text input client (R-03-054)',
      );

      // Any send_input would be acked by the stub; two seconds of silence is the
      // Device-side proof the tap sent nothing. The stub's stdout trail (zero
      // `send_input_received` lines for w1:p2 across this run) proves the same on
      // the Host side.
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(ackCount, 0, reason: 'R-30-300: a grid tap never sends');

      await unmount(tester);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets('typed text goes to the pane as typed: one committed burst is one send_input and '
      'its ack settles it (R-03-054, R-11-227)', (WidgetTester tester) async {
    final acks = <SendInputAck>[];
    final ackSub = connection.messages
        .where((message) => message is MessageSendInputAck)
        .cast<MessageSendInputAck>()
        .map((message) => message.payload)
        .listen(acks.add);
    addTearDown(ackSub.cancel);

    await pumpTerminal(tester, _shellPaneId);
    await awaitLive(tester, '80x24');

    // A grid tap raises the keyboard and sends nothing; the keyboard's commit
    // is the send (no field, no send control).
    await tester.tap(find.byType(TerminalViewWidget));
    await tester.pump();
    expect(tester.testTextInput.hasAnyClients, isTrue);
    expect(acks, isEmpty, reason: 'R-30-300: a grid tap never sends');
    final String next =
        (tester.testTextInput.editingState!['text'] as String) + _sentText;
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      ),
    );
    await tester.pump();

    await _pumpUntil(
      tester,
      () => acks.isNotEmpty,
      timeout: _replyTimeout,
      reason: 'no send_input_ack arrived',
    );
    expect(acks, hasLength(1), reason: 'exactly one send_input went out');
    expect(acks.single.paneId, _shellPaneId);
    expect(
      find.text('We do not know whether this reached the pane.'),
      findsNothing,
    );

    await unmount(tester);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets(
    'the key row sends the documented keys payloads (docs/10 §6.2/6.3, R-10-044)',
    (WidgetTester tester) async {
      final acks = <SendInputAck>[];
      final ackSub = connection.messages
          .where((message) => message is MessageSendInputAck)
          .cast<MessageSendInputAck>()
          .map((message) => message.payload)
          .listen(acks.add);
      addTearDown(ackSub.cancel);

      await pumpTerminal(tester, _shellPaneId);
      await awaitLive(tester, '80x24');

      // Esc, Tab and the up arrow are one tap each; `ctrl+c` is typed the way a
      // keyboard types it — `ctrl` latched, then the key — because the row has
      // no chord list any more (R-03-116).
      await tester.tap(find.byKey(const ValueKey<String>('keyRowEsc')));
      await _pumpUntil(
        tester,
        () => acks.isNotEmpty,
        timeout: _replyTimeout,
        reason: 'esc was never acked',
      );
      await tester.tap(find.byKey(const ValueKey<String>('keyRowTab')));
      await _pumpUntil(
        tester,
        () => acks.length >= 2,
        timeout: _replyTimeout,
        reason: 'tab was never acked',
      );
      await tester.tap(find.byKey(const ValueKey<String>('keyRowArrow^')));
      await _pumpUntil(
        tester,
        () => acks.length >= 3,
        timeout: _replyTimeout,
        reason: 'the arrow was never acked',
      );
      // The latch raises the keyboard and sends nothing of its own; the next
      // committed character is the chord (R-31-09-08, R-31-09-19).
      await tester.tap(find.byKey(const ValueKey<String>('keyRowCtrl')));
      await _pumpUntil(
        tester,
        () => _visible(find.text('CTRL')),
        reason: 'the ctrl latch never engaged',
      );
      expect(acks, hasLength(3), reason: 'a latch sends nothing on its own');
      final String next = '${tester.testTextInput.editingState!['text']}c';
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        ),
      );
      await tester.pump();
      await _pumpUntil(
        tester,
        () => acks.length >= 4,
        timeout: _replyTimeout,
        reason: 'ctrl+c was never acked',
      );

      // Each press is one send_input, each send_input one ack — four in total,
      // and the stub's trail carries the payloads verbatim:
      // ["Esc"], ["Tab"], ["Up"], ["ctrl+c"].
      expect(acks, hasLength(4));
      expect(acks.map((ack) => ack.paneId).toSet(), <String>{_shellPaneId});

      await unmount(tester);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'real landscape rotation preserves Overview in the merged bar and Readable '
    'restores 13 px before the return to portrait (mockup 08 landscape)',
    (WidgetTester tester) async {
      await pumpTerminal(tester, _shellPaneId);
      await awaitLive(tester, '80x24');
      await _pumpUntil(
        tester,
        () => _visible(find.text('main / ')),
        reason: 'the tree never answered the open',
      );
      await _settle(tester);
      final terminal = tester
          .widget<TerminalView>(find.byType(TerminalView))
          .terminal;
      final Size readableCellSize = _assertGridGeometry(
        tester,
        columns: 80,
        rows: 24,
      );
      expect(find.byType(StatusStrip), findsOneWidget);
      await tester.tap(_terminalModeControl(tester, 'Overview'));
      await _settle(tester);
      _assertGridGeometry(tester, columns: 80, rows: 24, overview: true);

      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      try {
        await _pumpUntil(
          tester,
          () =>
              tester.view.physicalSize.width > tester.view.physicalSize.height,
          timeout: const Duration(seconds: 30),
          reason: 'the real landscape metrics never arrived',
        );
        await _settle(tester, 3);
        expect(
          tester.widget<TerminalView>(find.byType(TerminalView)).terminal,
          same(terminal),
          reason: 'Rotation must keep the same live terminal.',
        );
        _assertGridGeometry(tester, columns: 80, rows: 24, overview: true);
        expect(find.byType(StatusStrip), findsNothing);
        expect(
          find.text('main / '),
          findsOneWidget,
          reason: 'The merged bar keeps the pane title.',
        );
        expect(
          find.text('80x24'),
          findsOneWidget,
          reason: 'The key row keeps the grid size.',
        );
        expect(
          find.textContaining(RegExp(r'^rev \d+$')),
          findsOneWidget,
          reason: 'The merged bar keeps the revision.',
        );

        await tester.tap(_terminalModeControl(tester, 'Readable'));
        await _settle(tester);
        expect(
          _assertGridGeometry(tester, columns: 80, rows: 24),
          readableCellSize,
          reason: 'Readable must restore the exact 13 px cell metrics.',
        );
      } finally {
        await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
          DeviceOrientation.portraitUp,
        ]);
      }
      await _pumpUntil(
        tester,
        () => tester.view.physicalSize.height > tester.view.physicalSize.width,
        timeout: const Duration(seconds: 30),
        reason: 'the real portrait metrics never returned',
      );
      await _settle(tester, 3);
      expect(find.byType(StatusStrip), findsOneWidget);
      expect(
        tester.widget<TerminalView>(find.byType(TerminalView)).terminal,
        same(terminal),
      );
      expect(
        _assertGridGeometry(tester, columns: 80, rows: 24),
        readableCellSize,
        reason: 'Portrait must keep the exact 13 px cell metrics.',
      );
      await _panReadableGrid(tester);

      await unmount(tester);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'a pull from the grid top at the live bottom sends one scroll_request '
    '(force-read)',
    (WidgetTester tester) async {
      await pumpTerminal(tester, _tallPaneId);
      await awaitLive(tester, '144x50');
      // The pull arms only while the Device's own offset sits at the live
      // bottom. The strip's trailing slot reads the revision there and the
      // '-N / 240' scroll readout anywhere else (R-31-08-18), so wait for the
      // revision before pulling.
      await _pumpUntil(
        tester,
        () => _visible(find.textContaining(RegExp(r'^rev \d+$'))),
        reason: 'the pane never settled at the live bottom',
      );

      ScrollResponse? payload;
      final responseSub = connection.messages
          .where((message) => message is MessageScrollResponse)
          .cast<MessageScrollResponse>()
          .map((message) => message.payload)
          .listen((ScrollResponse candidate) {
            if (candidate.paneId == _tallPaneId) payload = candidate;
          });
      addTearDown(responseSub.cancel);

      final grid = tester.getRect(find.byType(TerminalViewWidget));
      await tester.dragFrom(
        Offset(grid.center.dx, grid.top + 20),
        const Offset(0, 120),
      );

      await _pumpUntil(
        tester,
        () => payload != null,
        timeout: _replyTimeout,
        reason: 'no scroll_response arrived after the force-read pull',
      );
      expect(payload!.text, startsWith(_cannedScrollbackHead));
      expect(payload!.truncated, isTrue);

      await unmount(tester);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
