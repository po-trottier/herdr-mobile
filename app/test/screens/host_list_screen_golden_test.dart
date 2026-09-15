/// Golden tests for `HostListScreen` (`app/lib/screens/host_list_screen.dart`, `WP-18-a`),
/// one per named row of `docs/31-mockups/05-host-list.md`'s `## States` table this file
/// covers (`Default`, `Switch failed`, `Host in use`, `Empty`), each rendered in both
/// Selenized dark and light (R-32-012).
///
/// Renders the stateful `HostListScreen` itself, not a presentational split: this screen owns
/// no such split (unlike `lock_screen.dart`'s `LockScreenBody`), so this file reuses the
/// `_Harness` fake-service pattern `host_list_screen_test.dart` already built for its own
/// widget tests, copied rather than imported because Dart's leading-underscore privacy keeps
/// a `_Harness` class file-local.
///
/// `Default` covers a connected row (`3 agents`, two badges) and four saved rows carrying the
/// three last-seen forms of callout 5 (`today`, `yesterday`, and a date) plus `not connected
/// yet`, so every branch of `formatLastSeenLong` paints at least once. `Empty` renders zero
/// records: unreachable as this screen's start state (`R-31-01-01` sends a cold start with no
/// paired computer to `/welcome` instead), but reachable mid-session on this exact screen by
/// forgetting the last saved computer without leaving `/hosts` — `_confirmForget` never
/// navigates away, so the screen keeps rendering with `_records` empty.
///
/// The `today`/`yesterday` records fix their hour and minute directly rather than deriving
/// them from the render-time clock, so the drawn `HH:mm` text stays the same on every re-run;
/// only their calendar day is taken from `DateTime.now()`, which is what keeps them classified
/// as `today`/`yesterday` by `formatLastSeenLong`'s own day-difference check. The long-ago
/// record is a fixed calendar date, because `formatLastSeenLong` draws `day Mon` for it and a
/// date derived from the clock would change the drawn text every day.
///
/// Fonts, the app theme and the 375 x 667 reference size come from `golden_support.dart`
/// (`loadAppFonts`, `goldenApp`, `goldenReferenceSize`); see its doc comment for why.
/// `devicePixelRatio` stays fixed at 1.0.
library;

import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart' show Brightness, Widget;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart' show Ok, Result;
import 'package:herdr_mobile/models/message.dart';
import 'package:herdr_mobile/models/messages/agent_status_kind.dart';
import 'package:herdr_mobile/models/messages/agent_summary.dart';
import 'package:herdr_mobile/models/messages/pane_summary.dart';
import 'package:herdr_mobile/models/messages/tab_summary.dart';
import 'package:herdr_mobile/models/messages/tree_snapshot.dart';
import 'package:herdr_mobile/models/messages/workspace_summary.dart';
import 'package:herdr_mobile/screens/host_list_screen.dart';
import 'package:herdr_mobile/services/agent_status.dart' show AttentionItem;
import 'package:herdr_mobile/services/host_list.dart';
import 'package:herdr_mobile/services/plain_store.dart' show PairedHostRecord;
import 'package:herdr_mobile/services/relay.dart';
import 'package:herdr_mobile/widgets/app_ground.dart' show EmptyMark;
import 'package:herdr_mobile/widgets/ground_grid.dart' show GroundGrid;

import 'golden_support.dart';

/// A trimmed copy of `host_list_screen_test.dart`'s own `_Harness`: same fake-service shape,
/// down to the field and method names, minus the parts this file's four states never drive
/// (`pendingSwitch`, `hasNetwork`, `onForget`'s bookkeeping). [screen] returns the bare
/// `HostListScreen`, so `goldenApp` owns the one `MaterialApp`/`MediaQuery` this file needs
/// instead of nesting a second one.
class _Harness {
  _Harness({
    List<PairedHostRecord> hosts = const <PairedHostRecord>[],
    this.switchOutcome,
    this.connectedHostId,
  }) : records = List<PairedHostRecord>.of(hosts),
       messages = StreamController<Message>.broadcast(),
       connectionState = StreamController<RelayConnectionState>.broadcast(),
       attentionController = StreamController<List<AttentionItem>>.broadcast();

  final List<PairedHostRecord> records;
  final StreamController<Message> messages;
  final StreamController<RelayConnectionState> connectionState;
  final StreamController<List<AttentionItem>> attentionController;
  final SwitchOutcome? switchOutcome;
  final String? connectedHostId;

  Future<Result<List<PairedHostRecord>>> pairedHosts() async =>
      Ok(List<PairedHostRecord>.of(records));

  Future<SwitchOutcome> onSwitch(PairedHostRecord target) async =>
      switchOutcome ??
      SwitchSucceeded(hostId: target.hostId, hostName: target.hostName);

  Future<Result<void>> onForget(PairedHostRecord target) async =>
      const Ok<void>(null);

  Future<String> thisDeviceName() async => 'pixel-9';

  Future<bool> hasNetwork() async => true;

  Widget screen() => HostListScreen(
    pairedHosts: pairedHosts,
    messages: messages.stream,
    connectionState: connectionState.stream,
    connectedHostId: connectedHostId,
    unseenAttention: attentionController.stream,
    currentAttention: const <AttentionItem>[],
    thisDeviceName: thisDeviceName,
    onSwitch: onSwitch,
    onForget: onForget,
    hasNetwork: hasNetwork,
    onPairAnother: () {},
  );

  Future<void> dispose() async {
    await messages.close();
    await connectionState.close();
    await attentionController.close();
  }
}

AttentionItem _attention({
  required String hostId,
  required String paneId,
  required AgentStatusKind status,
}) => AttentionItem(
  hostId: hostId,
  paneId: paneId,
  workspaceId: 'w1',
  tabId: 't1',
  agentKind: 'claude',
  tabTitle: 'main',
  paneTitle: 'build',
  status: status,
  at: null,
);

/// Builds the `Default` state's five rows: one connected, four saved across every last-seen
/// form callout 5 names, per this file's own top doc comment.
_Harness _defaultHarness() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  DateTime todayAt(int hour, int minute) =>
      DateTime(today.year, today.month, today.day, hour, minute);
  final yesterday = todayAt(14, 2).subtract(const Duration(days: 1));
  // Drawn as `12 Feb`; formatLastSeenLong prints no year for an old date.
  final longAgo = DateTime(2026, 2, 12);

  return _Harness(
    hosts: <PairedHostRecord>[
      const PairedHostRecord(hostId: 'patrick', hostName: 'patrick-desk'),
      PairedHostRecord(
        hostId: 'build-box',
        hostName: 'build-box',
        lastSeen: todayAt(9, 14),
      ),
      PairedHostRecord(
        hostId: 'office-tower',
        hostName: 'office-tower',
        lastSeen: yesterday,
      ),
      PairedHostRecord(
        hostId: 'macbook-pat',
        hostName: 'macbook-pat',
        lastSeen: longAgo,
      ),
      const PairedHostRecord(hostId: 'old-laptop', hostName: 'old-laptop'),
    ],
    connectedHostId: 'patrick',
  );
}

/// Feeds the connected row's live state: pushed only after `HostListScreen`'s `initState` has
/// subscribed, because [_Harness]'s streams are broadcast streams, which drop an event added
/// before a listener exists.
void _pushDefaultLiveState(_Harness harness) {
  harness.connectionState.add(const RelayConnected());
  harness.messages.add(
    const Message.treeSnapshot(
      TreeSnapshot(
        workspaces: <WorkspaceSummary>[],
        tabs: <TabSummary>[],
        panes: <PaneSummary>[],
        agents: <AgentSummary>[
          AgentSummary(agentKind: 'claude', paneId: 'p1', status: 'working'),
          AgentSummary(agentKind: 'claude', paneId: 'p2', status: 'blocked'),
          AgentSummary(agentKind: 'codex', paneId: 'p3', status: 'idle'),
        ],
      ),
    ),
  );
  harness.attentionController.add(<AttentionItem>[
    _attention(
      hostId: 'patrick',
      paneId: 'p1',
      status: AgentStatusKind.blocked,
    ),
    _attention(hostId: 'patrick', paneId: 'p2', status: AgentStatusKind.done),
    _attention(
      hostId: 'build-box',
      paneId: 'p3',
      status: AgentStatusKind.blocked,
    ),
  ]);
}

void main() {
  setUpAll(loadAppFonts);

  const themes = <(String, Brightness)>[
    ('dark', Brightness.dark),
    ('light', Brightness.light),
    ('ios_dark', Brightness.dark),
    ('ios_light', Brightness.light),
  ];

  Future<void> renderAndSettle(
    WidgetTester tester,
    _Harness harness,
    Brightness brightness, {
    void Function(_Harness harness)? afterMount,
  }) async {
    tester.view.physicalSize = goldenReferenceSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      goldenApp(
        brightness: brightness,
        adjust: (ambient) => ambient.copyWith(disableAnimations: true),
        child: harness.screen(),
      ),
    );
    await tester.pump();
    afterMount?.call(harness);
    await tester.pumpAndSettle();
  }

  for (final (themeName, brightness) in themes) {
    group(themeName, () {
      setUp(() {
        debugDefaultTargetPlatformOverride = themeName.startsWith('ios_')
            ? TargetPlatform.iOS
            : TargetPlatform.android;
      });
      tearDown(() => debugDefaultTargetPlatformOverride = null);
      testWidgets(
        'default ($themeName) matches docs/31-mockups/05-host-list.md',
        (tester) async {
          final harness = _defaultHarness();
          await renderAndSettle(
            tester,
            harness,
            brightness,
            afterMount: _pushDefaultLiveState,
          );

          expect(find.text('Computers'), findsOneWidget);
          expect(find.text('patrick-desk'), findsOneWidget);
          expect(find.text('3 AGENTS'), findsOneWidget);
          expect(find.text('LAST SEEN 09:14'), findsOneWidget);
          expect(find.textContaining('LAST SEEN YESTERDAY'), findsOneWidget);
          expect(find.text('NOT CONNECTED YET'), findsOneWidget);
          expect(find.text('2'), findsOneWidget); // patrick-desk's badge count.
          expect(find.text('1'), findsOneWidget); // build-box's badge count.
          expect(
            find.text('Swipe a row left, then tap Forget.'),
            findsOneWidget,
          );
          // R-03-107 (amended 2026-09-09): a list with rows paints plain `color.bg.base`, no
          // grid.
          expect(find.byType(GroundGrid), findsNothing);

          await expectLater(
            find.byType(HostListScreen),
            matchesGoldenFile('goldens/host_list_default_$themeName.png'),
          );
          debugDefaultTargetPlatformOverride = null;
        },
      );

      testWidgets(
        'switch_failed ($themeName) matches docs/31-mockups/05-host-list.md',
        (tester) async {
          final harness = _Harness(
            hosts: <PairedHostRecord>[
              const PairedHostRecord(hostId: 'a', hostName: 'alpha-box'),
              const PairedHostRecord(hostId: 'b', hostName: 'beta-box'),
            ],
            switchOutcome: const SwitchFailed(
              hostId: 'a',
              reason: SwitchFailureReason.other,
              detail: 'boom',
            ),
          );
          await renderAndSettle(tester, harness, brightness);

          await tester.tap(find.text('alpha-box'));
          await tester.pumpAndSettle();

          expect(
            find.text('No computer is connected. Choose one, or see why.'),
            findsOneWidget,
          );
          expect(find.text('TRY AGAIN'), findsOneWidget);
          expect(find.text('Could not reach this computer.'), findsOneWidget);

          await expectLater(
            find.byType(HostListScreen),
            matchesGoldenFile('goldens/host_list_switch_failed_$themeName.png'),
          );
          debugDefaultTargetPlatformOverride = null;
        },
      );

      testWidgets(
        'host_in_use ($themeName) matches docs/31-mockups/05-host-list.md',
        (tester) async {
          final harness = _Harness(
            hosts: <PairedHostRecord>[
              const PairedHostRecord(hostId: 'a', hostName: 'alpha-box'),
              const PairedHostRecord(hostId: 'b', hostName: 'beta-box'),
            ],
            switchOutcome: const SwitchFailed(
              hostId: 'a',
              reason: SwitchFailureReason.hostInUse,
              detail: 'in use',
            ),
          );
          await renderAndSettle(tester, harness, brightness);

          await tester.tap(find.text('alpha-box'));
          await tester.pumpAndSettle();

          expect(find.text('IN USE ON ANOTHER PHONE'), findsOneWidget);
          expect(find.text('TRY AGAIN'), findsOneWidget);
          expect(find.textContaining('isconnect'), findsNothing);

          await expectLater(
            find.byType(HostListScreen),
            matchesGoldenFile('goldens/host_list_host_in_use_$themeName.png'),
          );
          debugDefaultTargetPlatformOverride = null;
        },
      );

      testWidgets(
        'empty ($themeName) matches docs/31-mockups/05-host-list.md',
        (tester) async {
          final harness = _Harness();
          await renderAndSettle(tester, harness, brightness);
          await precacheBrandMark(tester, find.byType(HostListScreen));
          await tester.pumpAndSettle();

          expect(find.text('Computers'), findsOneWidget);
          // No row, and no hint pointing at a swipe gesture with nothing to swipe.
          expect(find.text('Swipe a row left, then tap Forget.'), findsNothing);
          // R-03-107 (amended 2026-09-09): the empty block sits on the ground grid inside the mark.
          expect(
            find.descendant(
              of: find.descendant(
                of: find.byType(GroundGrid),
                matching: find.byType(EmptyMark),
              ),
              matching: find.text('No computer yet.'),
            ),
            findsOneWidget,
          );

          await expectLater(
            find.byType(HostListScreen),
            matchesGoldenFile('goldens/host_list_empty_$themeName.png'),
          );
          debugDefaultTargetPlatformOverride = null;
        },
      );
    });
  }
}
