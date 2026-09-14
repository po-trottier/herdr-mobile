/// Smoke-tests `HostListScreen` (`WP-18-a`) against `docs/31-mockups/05-host-list.md`: row
/// sort and content, the reveal-then-tap `Forget` action with its confirmation and its named
/// custom semantics action (R-31-05-02, R-31-05-03, R-32-580, R-30-298), the non-drag-
/// dismissible destructive pane (R-30-297, R-31-05-07), one open pane at a time across rows
/// (R-31-05-08, R-30-299), a saved-row tap starting a switch with no confirmation (R-30-948),
/// the `Switch failed` state (R-30-947), no relay address on any row (R-31-05-05), the
/// `host_in_use` row offering only `Try again` (R-31-05-06), the trailing slot's mutual
/// exclusivity (R-31-05-15), a tap on the already-connected row navigating without a second
/// switch attempt (R-31-05-10), and a mid-switch dispose not calling `setState` after unmount
/// (R-41-101).
library;

import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoButton, CupertinoNavigationBar;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart' show AppBar;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/widgets.dart'
    show
        CustomScrollView,
        Offset,
        SizedBox,
        SliverList,
        Text,
        TextStyle,
        Widget;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart' show Ok, Result;
import 'package:herdr_mobile/models/message.dart';
import 'package:herdr_mobile/screens/host_list_screen.dart';
import 'package:herdr_mobile/services/agent_status.dart' show AttentionItem;
import 'package:herdr_mobile/services/host_list.dart';
import 'package:herdr_mobile/services/plain_store.dart' show PairedHostRecord;
import 'package:herdr_mobile/services/relay.dart';
import 'package:herdr_mobile/widgets/app_ground.dart' show EmptyMark;
import 'package:herdr_mobile/widgets/brand_mark.dart' show BrandMark;
import 'package:herdr_mobile/widgets/ground_grid.dart' show GroundGrid;
import 'package:herdr_mobile/widgets/theme/app_color.dart' show AppColor;
import 'package:herdr_mobile/widgets/theme/app_space.dart' show AppSpace;
import 'package:herdr_mobile/widgets/theme/app_type.dart' show AppType;
import 'package:herdr_mobile/widgets/theme/chrome_icon_action.dart';
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart'
    show CircularProgressIndicator, MaterialApp;

PairedHostRecord _record({
  required String hostId,
  required String hostName,
  DateTime? lastSeen,
}) => PairedHostRecord(hostId: hostId, hostName: hostName, lastSeen: lastSeen);

class _Harness {
  _Harness({
    List<PairedHostRecord> hosts = const <PairedHostRecord>[],
    this.switchOutcome,
    this.pendingSwitch,
    this.connectedHostId,
    this.initialConnectionState,
    this.attemptOnLoad = false,
  }) : records = List<PairedHostRecord>.of(hosts),
       messages = StreamController<Message>.broadcast(),
       connectionState = StreamController<RelayConnectionState>.broadcast(),
       attentionController = StreamController<List<AttentionItem>>.broadcast();

  List<PairedHostRecord> records;
  final StreamController<Message> messages;
  final StreamController<RelayConnectionState> connectionState;
  final StreamController<List<AttentionItem>> attentionController;
  SwitchOutcome? switchOutcome;

  /// Set to make [onSwitch] hang until the test completes it, to exercise a switch still in
  /// flight (a `switching` row, or a widget disposed mid-await for R-41-101).
  final Completer<SwitchOutcome>? pendingSwitch;

  final String? connectedHostId;
  final RelayConnectionState? initialConnectionState;
  final bool attemptOnLoad;

  final List<PairedHostRecord> switchedTo = <PairedHostRecord>[];
  final List<PairedHostRecord> forgotten = <PairedHostRecord>[];
  String? switchedHostId;

  Future<Result<List<PairedHostRecord>>> pairedHosts() async =>
      Ok(List<PairedHostRecord>.of(records));

  Future<SwitchOutcome> onSwitch(PairedHostRecord target) async {
    switchedTo.add(target);
    final pending = pendingSwitch;
    if (pending != null) return pending.future;
    return switchOutcome ??
        SwitchSucceeded(hostId: target.hostId, hostName: target.hostName);
  }

  Future<Result<void>> onForget(PairedHostRecord target) async {
    forgotten.add(target);
    records = records.where((r) => r.hostId != target.hostId).toList();
    return const Ok<void>(null);
  }

  Future<String> thisDeviceName() async => 'pixel-9';

  Future<bool> hasNetwork() async => true;

  Widget build() => MaterialApp(
    home: HostListScreen(
      pairedHosts: pairedHosts,
      messages: messages.stream,
      connectionState: connectionState.stream,
      initialConnectionState: initialConnectionState,
      connectedHostId: connectedHostId,
      unseenAttention: attentionController.stream,
      currentAttention: const <AttentionItem>[],
      thisDeviceName: thisDeviceName,
      onSwitch: onSwitch,
      onForget: onForget,
      hasNetwork: hasNetwork,
      onSwitched: (id) => switchedHostId = id,
      attemptOnLoad: attemptOnLoad,
    ),
  );

  Future<void> dispose() async {
    await messages.close();
    await connectionState.close();
    await attentionController.close();
  }
}

void main() {
  testWidgets('iOS: renders CupertinoNavigationBar with the pair button trailing, not a Material '
      'AppBar', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final harness = _Harness();
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.build());
    await tester.pump();

    expect(find.byType(CupertinoNavigationBar), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    final navBar = tester.widget<CupertinoNavigationBar>(
      find.byType(CupertinoNavigationBar),
    );
    // The one app bar action primitive (R-33-033 `App bar action` row): a `CupertinoButton`
    // inside on iOS.
    expect(navBar.trailing, isA<ChromeIconAction>());
    expect(
      find.descendant(
        of: find.byType(ChromeIconAction),
        matching: find.byType(CupertinoButton),
      ),
      findsOneWidget,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'draws every saved row with its last-seen detail line, sorted by name',
    (tester) async {
      final harness = _Harness(
        hosts: <PairedHostRecord>[
          _record(hostId: 'b', hostName: 'zeta-box'),
          _record(hostId: 'a', hostName: 'alpha-box'),
        ],
      );
      addTearDown(harness.dispose);

      await tester.pumpWidget(harness.build());
      await tester.pumpAndSettle();

      expect(find.text('alpha-box'), findsOneWidget);
      expect(find.text('zeta-box'), findsOneWidget);
      expect(find.text('NOT CONNECTED YET'), findsNWidgets(2));

      final alphaTop = tester.getTopLeft(find.text('alpha-box')).dy;
      final zetaTop = tester.getTopLeft(find.text('zeta-box')).dy;
      expect(alphaTop, lessThan(zetaTop));
    },
  );

  testWidgets(
    'a list with rows paints no ground grid and ends with its hint; the empty state is '
    'the grid with the one mark, left aligned, its title in the display face in accent ink and '
    'its sentence in body secondary (R-03-107, amended 2026-09-09)',
    (tester) async {
      final harness = _Harness(
        hosts: <PairedHostRecord>[_record(hostId: 'a', hostName: 'alpha-box')],
      );
      addTearDown(harness.dispose);

      await tester.pumpWidget(harness.build());
      await tester.pumpAndSettle();

      expect(find.byType(GroundGrid), findsNothing);
      expect(find.byType(EmptyMark), findsNothing);
      expect(find.text('alpha-box'), findsOneWidget);
      expect(find.text('Swipe a row left, then tap Forget.'), findsOneWidget);
      // The rows and the hint are the one sliver, and nothing follows it: no remainder and no
      // clearance for a create control (R-03-109).
      final CustomScrollView list = tester.widget<CustomScrollView>(
        find.byType(CustomScrollView),
      );
      expect(list.slivers, hasLength(1));
      expect(list.slivers.single, isA<SliverList>());

      final empty = _Harness();
      addTearDown(empty.dispose);
      // A fresh screen: the same widget type in the same slot would keep the first screen's
      // state and its list from the first harness.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(empty.build());
      await tester.pumpAndSettle();

      final Finder title = find.text('No computer yet.');
      expect(
        find.descendant(
          of: find.descendant(
            of: find.byType(GroundGrid),
            matching: find.byType(EmptyMark),
          ),
          matching: title,
        ),
        findsOneWidget,
      );
      // One silhouette on the screen: the mark's own, in place of the 96 px one the block drew.
      expect(find.byType(BrandMark), findsOneWidget);
      final AppColor color = AppColor.of(tester.element(title));
      final TextStyle titleStyle = tester.widget<Text>(title).style!;
      expect(titleStyle.fontFamily, AppType.title.fontFamily);
      expect(titleStyle.fontSize, AppType.title.fontSize);
      expect(titleStyle.color, color.accentText);
      final TextStyle sentenceStyle = tester
          .widget<Text>(
            find.text(
              'Scan a QR code or enter a phrase to pair your first computer.',
            ),
          )
          .style!;
      expect(sentenceStyle.fontSize, AppType.body.fontSize);
      expect(sentenceStyle.color, color.fgSecondary);
      // Left aligned at `space.4` (R-32-553), not centred.
      expect(tester.getTopLeft(find.text('COMPUTERS')).dx, AppSpace.space4);
      expect(tester.getTopLeft(title).dx, AppSpace.space4);
    },
  );

  testWidgets(
    'the bottom hint strip sits above the system navigation bar inset',
    (tester) async {
      // The Android gesture bar: a bottom padding the view reports, which
      // MaterialApp turns into MediaQuery.padding.bottom.
      const double navBarInset = 48;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: navBarInset);
      tester.view.viewPadding = const FakeViewPadding(bottom: navBarInset);
      addTearDown(tester.view.reset);

      final harness = _Harness(
        hosts: <PairedHostRecord>[_record(hostId: 'a', hostName: 'alpha-box')],
      );
      addTearDown(harness.dispose);

      await tester.pumpWidget(harness.build());
      await tester.pumpAndSettle();

      final hint = find.text('Swipe a row left, then tap Forget.');
      expect(hint, findsOneWidget);
      final screenBottom = tester.view.physicalSize.height;
      expect(
        tester.getBottomLeft(hint).dy,
        lessThanOrEqualTo(screenBottom - navBarInset),
        reason: 'the hint must not be drawn under the navigation bar',
      );
    },
  );

  testWidgets('a swipe reveals Forget; confirming calls onForget with the R-31-05-03 sentence and '
      'removes the row', (tester) async {
    final harness = _Harness(
      hosts: <PairedHostRecord>[_record(hostId: 'a', hostName: 'alpha-box')],
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    await tester.drag(find.text('alpha-box'), const Offset(-300, 0));
    await tester.pumpAndSettle();

    expect(find.text('Forget'), findsOneWidget);
    await tester.tap(find.text('Forget'));
    await tester.pumpAndSettle();

    // The body is a `Text.rich` with the `d` key cap as a `WidgetSpan` (R-03-103), which
    // `find.text` cannot match.
    expect(
      find.textContaining('In the Relay pane, select pixel-9 and press'),
      findsOneWidget,
    );
    await tester.tap(find.text('Forget').last);
    await tester.pumpAndSettle();

    expect(harness.forgotten.single.hostId, 'a');
    expect(find.text('alpha-box'), findsNothing);
  });

  testWidgets(
    'the revealed Forget action is also a named custom semantics action (R-32-580, R-30-298)',
    (tester) async {
      final harness = _Harness(
        hosts: <PairedHostRecord>[_record(hostId: 'a', hostName: 'alpha-box')],
      );
      addTearDown(harness.dispose);
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(harness.build());
      await tester.pumpAndSettle();

      final node = tester.getSemantics(find.text('alpha-box'));
      final ids =
          node.getSemanticsData().customSemanticsActionIds ?? const <int>[];
      final labels = ids
          .map((int id) => CustomSemanticsAction.getAction(id)?.label)
          .toList();
      expect(labels, contains('Forget this computer'));

      handle.dispose();
    },
  );

  testWidgets(
    'opening one row\'s pane closes another open pane (R-31-05-08, R-30-299)',
    (tester) async {
      final harness = _Harness(
        hosts: <PairedHostRecord>[
          _record(hostId: 'a', hostName: 'alpha-box'),
          _record(hostId: 'b', hostName: 'beta-box'),
        ],
      );
      addTearDown(harness.dispose);

      await tester.pumpWidget(harness.build());
      await tester.pumpAndSettle();

      await tester.drag(find.text('alpha-box'), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.text('Forget'), findsOneWidget);

      // `SlidableAutoCloseBehavior`'s barrier absorbs the first tap elsewhere and uses it only
      // to close the open pane — it does not fall through and start a switch on row b.
      await tester.tap(find.text('beta-box'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Forget'), findsNothing);
      expect(harness.switchedTo, isEmpty);

      // A second, separate interaction can now open row b's own pane.
      await tester.drag(find.text('beta-box'), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.text('Forget'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping a saved row switches with no confirmation and routes on success (R-30-948)',
    (tester) async {
      final harness = _Harness(
        hosts: <PairedHostRecord>[_record(hostId: 'a', hostName: 'alpha-box')],
      );
      addTearDown(harness.dispose);

      await tester.pumpWidget(harness.build());
      await tester.pumpAndSettle();

      await tester.tap(find.text('alpha-box'));
      await tester.pumpAndSettle();

      expect(harness.switchedTo.single.hostId, 'a');
      expect(harness.switchedHostId, 'a');
      // No dialog was raised for a non-destructive switch.
      expect(find.text('Cancel'), findsNothing);
    },
  );

  testWidgets(
    'a cold start makes exactly one attempt, to the newest last-seen computer (R-31-05-16)',
    (tester) async {
      final harness = _Harness(
        attemptOnLoad: true,
        hosts: <PairedHostRecord>[
          _record(
            hostId: 'old',
            hostName: 'old-box',
            lastSeen: DateTime(2024, 1, 1),
          ),
          _record(
            hostId: 'new',
            hostName: 'new-box',
            lastSeen: DateTime(2024, 6, 1),
          ),
          _record(hostId: 'never', hostName: 'never-box'),
        ],
      );
      addTearDown(harness.dispose);

      await tester.pumpWidget(harness.build());
      await tester.pumpAndSettle();

      expect(harness.switchedTo.map((r) => r.hostId), <String>['new']);
      expect(harness.switchedHostId, 'new');
    },
  );

  testWidgets('a cold start with no last-seen time makes no attempt, and a later visit never attempts '
      '(R-31-05-16, R-31-13-14)', (tester) async {
    final noHistory = _Harness(
      attemptOnLoad: true,
      hosts: <PairedHostRecord>[_record(hostId: 'a', hostName: 'alpha-box')],
    );
    addTearDown(noHistory.dispose);
    await tester.pumpWidget(noHistory.build());
    await tester.pumpAndSettle();
    expect(noHistory.switchedTo, isEmpty);

    final laterVisit = _Harness(
      hosts: <PairedHostRecord>[
        _record(hostId: 'a', hostName: 'alpha-box', lastSeen: DateTime(2024)),
      ],
    );
    addTearDown(laterVisit.dispose);
    await tester.pumpWidget(laterVisit.build());
    await tester.pumpAndSettle();
    expect(laterVisit.switchedTo, isEmpty);
  });

  testWidgets('tapping the already-connected row navigates without a second switch attempt '
      '(R-31-05-10)', (tester) async {
    final harness = _Harness(
      hosts: <PairedHostRecord>[_record(hostId: 'a', hostName: 'alpha-box')],
      connectedHostId: 'a',
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    harness.connectionState.add(const RelayConnected());
    await tester.pump();

    // `HostRowState.connected` draws a `working` `StatusBar`, which pulses on
    // `motion.pulse` and never settles; `pump`, not `pumpAndSettle`, drives the tap.
    await tester.tap(find.text('alpha-box'));
    await tester.pump();

    expect(harness.switchedTo, isEmpty);
    expect(harness.switchedHostId, 'a');
  });

  testWidgets(
    'a failed switch shows Switch failed and the no-computer-connected strip (R-30-947)',
    (tester) async {
      final harness = _Harness(
        hosts: <PairedHostRecord>[_record(hostId: 'a', hostName: 'alpha-box')],
        switchOutcome: const SwitchFailed(
          hostId: 'a',
          reason: SwitchFailureReason.other,
          detail: 'boom',
        ),
      );
      addTearDown(harness.dispose);

      await tester.pumpWidget(harness.build());
      await tester.pumpAndSettle();

      await tester.tap(find.text('alpha-box'));
      await tester.pumpAndSettle();

      expect(find.text('TRY AGAIN'), findsOneWidget);
      expect(
        find.text('No computer is connected. Choose one, or see why.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'no row shows the relay address; it belongs on /settings only (R-31-05-05)',
    (tester) async {
      final harness = _Harness(
        hosts: <PairedHostRecord>[
          _record(hostId: 'a', hostName: 'alpha-box', lastSeen: DateTime(2024)),
        ],
      );
      addTearDown(harness.dispose);

      await tester.pumpWidget(harness.build());
      await tester.pumpAndSettle();

      // The relay address is a URI with a scheme (`ws://`/`wss://`); no row text ever contains
      // one, because `PairedHostRecord` carries no such field for this screen to render.
      expect(find.textContaining('://'), findsNothing);
    },
  );

  testWidgets('the host_in_use row offers only Try again, never an action naming or disconnecting '
      'the other phone (R-31-05-06)', (tester) async {
    final harness = _Harness(
      hosts: <PairedHostRecord>[_record(hostId: 'a', hostName: 'alpha-box')],
      switchOutcome: const SwitchFailed(
        hostId: 'a',
        reason: SwitchFailureReason.hostInUse,
        detail: 'in use',
      ),
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    await tester.tap(find.text('alpha-box'));
    await tester.pumpAndSettle();

    expect(find.text('IN USE ON ANOTHER PHONE'), findsOneWidget);
    expect(find.text('TRY AGAIN'), findsOneWidget);
    expect(find.textContaining('isconnect'), findsNothing);
  });

  testWidgets('the trailing slot holds exactly one control at a time: chevron, spinner, Try again, or '
      'Pair again (R-31-05-15)', (tester) async {
    int controlCount() =>
        find.byIcon(Symbols.chevron_right_rounded).evaluate().length +
        find.byType(CircularProgressIndicator).evaluate().length +
        find.text('TRY AGAIN').evaluate().length +
        find.text('PAIR AGAIN').evaluate().length;

    // saved: the chevron alone.
    final saved = _Harness(
      hosts: <PairedHostRecord>[_record(hostId: 'a', hostName: 'alpha-box')],
    );
    addTearDown(saved.dispose);
    await tester.pumpWidget(saved.build());
    await tester.pumpAndSettle();
    expect(find.byIcon(Symbols.chevron_right_rounded), findsOneWidget);
    expect(controlCount(), 1);

    // switching: the spinner alone, while the attempt is still in flight. `pump`, not
    // `pumpAndSettle` — the indeterminate spinner never settles.
    final pendingSwitch = Completer<SwitchOutcome>();
    final switching = _Harness(
      hosts: <PairedHostRecord>[_record(hostId: 'a', hostName: 'alpha-box')],
      pendingSwitch: pendingSwitch,
    );
    addTearDown(switching.dispose);
    await tester.pumpWidget(switching.build());
    await tester.pumpAndSettle();
    await tester.tap(find.text('alpha-box'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(controlCount(), 1);
    pendingSwitch.complete(
      const SwitchSucceeded(hostId: 'a', hostName: 'alpha-box'),
    );
    await tester.pumpAndSettle();

    // switchFailed: Try again alone.
    final failed = _Harness(
      hosts: <PairedHostRecord>[_record(hostId: 'a', hostName: 'alpha-box')],
      switchOutcome: const SwitchFailed(
        hostId: 'a',
        reason: SwitchFailureReason.other,
        detail: 'boom',
      ),
    );
    addTearDown(failed.dispose);
    await tester.pumpWidget(failed.build());
    await tester.pumpAndSettle();
    await tester.tap(find.text('alpha-box'));
    await tester.pumpAndSettle();
    expect(find.text('TRY AGAIN'), findsOneWidget);
    expect(controlCount(), 1);

    // rejected: Pair again alone.
    final rejected = _Harness(
      hosts: <PairedHostRecord>[_record(hostId: 'a', hostName: 'alpha-box')],
      switchOutcome: const SwitchFailed(
        hostId: 'a',
        reason: SwitchFailureReason.rejected,
        detail: 'revoked',
      ),
    );
    addTearDown(rejected.dispose);
    await tester.pumpWidget(rejected.build());
    await tester.pumpAndSettle();
    await tester.tap(find.text('alpha-box'));
    await tester.pumpAndSettle();
    expect(find.text('PAIR AGAIN'), findsOneWidget);
    expect(controlCount(), 1);
  });

  testWidgets(
    'disposing the screen mid-switch does not call setState after unmount (R-41-101)',
    (tester) async {
      final pendingSwitch = Completer<SwitchOutcome>();
      final harness = _Harness(
        hosts: <PairedHostRecord>[_record(hostId: 'a', hostName: 'alpha-box')],
        pendingSwitch: pendingSwitch,
      );
      addTearDown(harness.dispose);

      await tester.pumpWidget(harness.build());
      await tester.pumpAndSettle();

      await tester.tap(find.text('alpha-box'));
      await tester.pump();
      expect(harness.switchedTo.single.hostId, 'a');

      // Unmount `HostListScreen` while `widget.onSwitch` is still awaiting.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      // The pending switch resolves after the widget is gone; `_handleRowTap`'s
      // `if (!mounted) return;` guard MUST stop it from calling `setState` on a disposed
      // `State`, which would otherwise throw and fail this test.
      pendingSwitch.complete(
        const SwitchSucceeded(hostId: 'a', hostName: 'alpha-box'),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'pushed while connected: the connected row draws as connected at build, before any '
    'stream emission (R-31-05-10, R-31-05-19; measured live 2026-09-03)',
    (tester) async {
      final harness = _Harness(
        hosts: <PairedHostRecord>[
          PairedHostRecord(
            hostId: 'h1',
            hostName: 'patrick-desk',
            lastSeen: DateTime.now(),
          ),
        ],
        connectedHostId: 'h1',
        initialConnectionState: const RelayConnected(),
      );
      addTearDown(harness.dispose);

      await tester.pumpWidget(harness.build());
      await tester.pump();

      expect(find.textContaining('LAST SEEN'), findsNothing);
      expect(find.text('IDLE'), findsNothing);
    },
  );
}
