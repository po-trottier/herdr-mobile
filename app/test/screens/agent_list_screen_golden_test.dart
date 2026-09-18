/// Golden tests for `AgentListScreen` (`app/lib/screens/agent_list_screen.dart`, `WP-18-b`),
/// one per state this package's checklist reaches from `docs/31-mockups/06-agent-list.md`'s
/// `## States` table (R-90-011): the default `Priority` grouping with its `NEEDS YOU` section,
/// the `Workspace` grouping with its `Space > Worktree > Tab > Pane` blocks (R-31-06-27,
/// decided 2026-09-04 by the product owner), and `Empty, no agents`. Since 2026-09-10, the
/// Workspace goldens also prove R-03-115: all pane rows are one line, while Priority stays two.
/// Each state renders in both Selenized dark and light (R-32-012); `Priority` renders on iOS too.
///
/// Reuses this package's own `_Harness` fake-service idiom from `agent_list_screen_test.dart` —
/// a `StreamController`-backed `AgentListScreen`, no live relay or Docker test infra needed —
/// copied here because Dart's `_`-prefixed privacy keeps that class file-local; a second file
/// cannot import it. [_AgentListFixture] carries the mockup's own names (`claude`, `codex`,
/// `gemini`, `lightspeed-kit`, `asset_library`, `feature/db-interface`, `scratch`), so the
/// rendered goldens can be read straight against `06-agent-list.md`'s wireframes.
///
/// Fonts, the app theme and the 375 x 667 reference size come from `golden_support.dart`
/// (`loadAppFonts`, `goldenApp`, `goldenReferenceSize`); see its doc comment for why.
/// `devicePixelRatio` stays fixed at 1.0.
library;

import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoSlidingSegmentedControl;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart' show Brightness, Text, TextStyle, Widget;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/models/message.dart';
import 'package:herdr_mobile/models/messages/agent_status_kind.dart';
import 'package:herdr_mobile/models/messages/agent_summary.dart';
import 'package:herdr_mobile/models/messages/pane_scroll_state.dart';
import 'package:herdr_mobile/models/messages/pane_summary.dart';
import 'package:herdr_mobile/models/messages/tab_summary.dart';
import 'package:herdr_mobile/models/messages/tree_snapshot.dart';
import 'package:herdr_mobile/models/messages/workspace_summary.dart';
import 'package:herdr_mobile/screens/agent_list_screen.dart';
import 'package:herdr_mobile/services/agent_list.dart' show AgentListAxis;
import 'package:herdr_mobile/services/agent_status.dart' show AttentionItem;
import 'package:herdr_mobile/services/relay.dart';
import 'package:herdr_mobile/widgets/app_ground.dart' show EmptyMark;
import 'package:herdr_mobile/widgets/ground_grid.dart' show GroundGrid;
import 'package:herdr_mobile/widgets/theme/app_color.dart' show AppColor;
import 'package:herdr_mobile/widgets/theme/app_type.dart' show AppType;
import 'package:herdr_mobile/widgets/theme/chrome_icon_action.dart'
    show ChromeIconAction;
import 'package:material_ui/material_ui.dart'
    show FloatingActionButton, SearchBar, TabBar;
import 'package:shared_preferences/shared_preferences.dart'
    show SharedPreferencesAsync;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'golden_support.dart';

const _scroll = PaneScrollState(
  offsetFromBottom: 0,
  maxOffsetFromBottom: 0,
  viewportRows: 50,
);

/// The measured Herdr shape of 2026-09-04, transcribed into
/// `docs/31-mockups/06-agent-list.md`'s wireframes: the repo `lightspeed-kit` holds its main
/// checkout (`impl`: a `working` `claude`, a shell pane `pane 2` with its command, a labelled
/// shell pane `Explorer` with no command, and an `idle` `codex` the Host gave no `status_at`,
/// so its row shows no age; then a second tab `bench` with one shell pane, added 2026-09-09 so
/// the golden shows two tab groups separated, per R-03-057), the linked worktree
/// `asset_library` with no agent at all (`shell`: one shell pane), and the linked worktree
/// `feature/db-interface` (`api-server`: a `blocked` `codex`), all three grouped by the Host
/// under the parent's `spaceId` (`w1`), so the parent's tabs sit directly under the space
/// header and only the two linked worktrees draw a worktree row; `scratch` has no `worktree`
/// (`notes`: a `done` `gemini`). Every age is relative to when this fixture is built, so the
/// on-screen text (`12s`, `1m 12s`, `4m 02s`) matches the wireframes on every run. Since
/// 2026-09-10, R-03-115 puts every Workspace pane, agent and shell alike, on one baseline.
class _AgentListFixture {
  _AgentListFixture() : _now = DateTime.now().toUtc();

  final DateTime _now;

  String _ago(Duration age) => _now.subtract(age).toIso8601String();

  Message get snapshot => Message.treeSnapshot(
    TreeSnapshot(
      workspaces: const <WorkspaceSummary>[
        WorkspaceSummary(
          workspaceId: 'w1',
          name: 'lightspeed-kit',
          focused: true,
          spaceId: 'w1',
          repoName: 'lightspeed-kit',
        ),
        WorkspaceSummary(
          workspaceId: 'w2',
          name: 'asset_library',
          focused: false,
          spaceId: 'w1',
          repoName: 'lightspeed-kit',
          isLinkedWorktree: true,
        ),
        WorkspaceSummary(
          workspaceId: 'w3',
          name: 'feature/db-interface',
          focused: false,
          spaceId: 'w1',
          repoName: 'lightspeed-kit',
          isLinkedWorktree: true,
        ),
        WorkspaceSummary(workspaceId: 'w4', name: 'scratch', focused: false),
      ],
      tabs: const <TabSummary>[
        TabSummary(
          tabId: 'w1:t1',
          workspaceId: 'w1',
          title: 'impl',
          focused: true,
        ),
        // A second tab in the main checkout (added 2026-09-09, R-03-057), so the golden shows
        // two tab groups of one worktree and the gap and hairline that separate them.
        TabSummary(
          tabId: 'w1:t5',
          workspaceId: 'w1',
          title: 'bench',
          focused: false,
        ),
        TabSummary(
          tabId: 'w2:t2',
          workspaceId: 'w2',
          title: 'shell',
          focused: false,
        ),
        TabSummary(
          tabId: 'w3:t3',
          workspaceId: 'w3',
          title: 'api-server',
          focused: false,
        ),
        TabSummary(
          tabId: 'w4:t4',
          workspaceId: 'w4',
          title: 'notes',
          focused: false,
        ),
      ],
      panes: const <PaneSummary>[
        PaneSummary(
          paneId: 'w1:p1',
          workspaceId: 'w1',
          tabId: 'w1:t1',
          terminalId: 'term_w1p1',
          label: '',
          title: 'claude',
          cwd: '/home/user/lightspeed-kit',
          focused: true,
          agent: 'claude',
          agentStatus: 'working',
          revision: 4,
          scroll: _scroll,
        ),
        PaneSummary(
          paneId: 'w1:p2',
          workspaceId: 'w1',
          tabId: 'w1:t1',
          terminalId: 'term_w1p2',
          label: '',
          title: 'zsh',
          cwd: '/home/user/lightspeed-kit',
          focused: false,
          agent: null,
          agentStatus: 'unknown',
          revision: 9,
          scroll: _scroll,
        ),
        PaneSummary(
          paneId: 'w1:p3',
          workspaceId: 'w1',
          tabId: 'w1:t1',
          terminalId: 'term_w1p3',
          label: 'Explorer',
          title: '',
          cwd: '/home/user/lightspeed-kit',
          focused: false,
          agent: null,
          agentStatus: 'unknown',
          revision: 1,
          scroll: _scroll,
        ),
        PaneSummary(
          paneId: 'w1:p4',
          workspaceId: 'w1',
          tabId: 'w1:t1',
          terminalId: 'term_w1p4',
          label: '',
          title: 'codex',
          cwd: '/home/user/lightspeed-kit',
          focused: false,
          agent: 'codex',
          agentStatus: 'idle',
          revision: 1,
          scroll: _scroll,
        ),
        PaneSummary(
          paneId: 'w1:p6',
          workspaceId: 'w1',
          tabId: 'w1:t5',
          terminalId: 'term_w1p6',
          label: '',
          title: 'cargo bench',
          cwd: '/home/user/lightspeed-kit',
          focused: false,
          agent: null,
          agentStatus: 'unknown',
          revision: 3,
          scroll: _scroll,
        ),
        PaneSummary(
          paneId: 'w2:p5',
          workspaceId: 'w2',
          tabId: 'w2:t2',
          terminalId: 'term_w2p5',
          label: '',
          title: 'npm run dev',
          cwd: '/home/user/lightspeed-kit-asset_library',
          focused: false,
          agent: null,
          agentStatus: 'unknown',
          revision: 2,
          scroll: _scroll,
        ),
        PaneSummary(
          paneId: 'w3:p11',
          workspaceId: 'w3',
          tabId: 'w3:t3',
          terminalId: 'term_w3p11',
          label: '',
          title: 'codex',
          cwd: '/home/user/lightspeed-kit-db-interface',
          focused: false,
          agent: 'codex',
          agentStatus: 'blocked',
          revision: 1,
          scroll: _scroll,
        ),
        PaneSummary(
          paneId: 'w4:p3',
          workspaceId: 'w4',
          tabId: 'w4:t4',
          terminalId: 'term_w4p3',
          label: '',
          title: 'gemini',
          cwd: '/home/user/scratch',
          focused: false,
          agent: 'gemini',
          agentStatus: 'done',
          revision: 1,
          scroll: _scroll,
        ),
      ],
      agents: <AgentSummary>[
        AgentSummary(
          agentKind: 'claude',
          paneId: 'w1:p1',
          status: 'working',
          statusAt: _ago(const Duration(seconds: 12)),
        ),
        // No `status_at`: the row draws its status word and no age (R-30-405).
        AgentSummary(
          agentKind: 'codex',
          paneId: 'w3:p11',
          status: 'blocked',
          statusAt: _ago(const Duration(minutes: 1, seconds: 12)),
        ),
        AgentSummary(
          agentKind: 'gemini',
          paneId: 'w4:p3',
          status: 'done',
          statusAt: _ago(const Duration(minutes: 4, seconds: 2)),
        ),
        const AgentSummary(agentKind: 'codex', paneId: 'w1:p4', status: 'idle'),
      ],
    ),
  );

  /// R-31-06-02: `blocked` MUST sort before `done` in `NEEDS YOU`; [AgentListService] applies
  /// that sort itself, so list order here does not matter.
  List<AttentionItem> get attention => <AttentionItem>[
    AttentionItem(
      hostId: 'host-1',
      paneId: 'w3:p11',
      workspaceId: 'w3',
      tabId: 'w3:t3',
      agentKind: 'codex',
      tabTitle: 'api-server',
      paneTitle: 'codex',
      status: AgentStatusKind.blocked,
      at: _ago(const Duration(minutes: 1, seconds: 12)),
    ),
    AttentionItem(
      hostId: 'host-1',
      paneId: 'w4:p3',
      workspaceId: 'w4',
      tabId: 'w4:t4',
      agentKind: 'gemini',
      tabTitle: 'notes',
      paneTitle: 'gemini',
      status: AgentStatusKind.done,
      at: _ago(const Duration(minutes: 4, seconds: 2)),
    ),
  ];
}

class _Harness {
  _Harness({this.currentAttention = const <AttentionItem>[]})
    : messages = StreamController<Message>.broadcast(),
      connectionState = StreamController<RelayConnectionState>.broadcast(),
      attention = StreamController<List<AttentionItem>>.broadcast();

  final List<AttentionItem> currentAttention;
  final StreamController<Message> messages;
  final StreamController<RelayConnectionState> connectionState;
  final StreamController<List<AttentionItem>> attention;

  AgentListScreen build() => AgentListScreen(
    hostId: 'host-1',
    hostName: 'patrick-desk',
    messages: messages.stream,
    connectionState: connectionState.stream,
    // Connected: every mockup wireframe draws the enabled create button.
    initialConnectionState: const RelayConnected(),
    send: (Message message, {String? corr}) {},
    unseenAttention: attention.stream,
    currentAttention: currentAttention,
    onMarkSeen: (String paneId) {},
    onNotePaneOpened: (String paneId) {},
    onOpenPane: (String paneId) {},
    // Every mockup wireframe draws the create button of R-03-109 and the `Status colours`
    // action of R-03-112 (callouts 18 and 26); a fixture with neither callback would silently
    // hide them.
    onCreate: () {},
    onOpenStatusColours: () {},
  );

  Future<void> dispose() async {
    await messages.close();
    await connectionState.close();
    await attention.close();
  }
}

Future<void> _pumpScreen(
  WidgetTester tester,
  Brightness brightness,
  Widget child,
) async {
  tester.view.physicalSize = goldenReferenceSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    goldenApp(
      brightness: brightness,
      adjust: (ambient) => ambient.copyWith(disableAnimations: true),
      child: child,
    ),
  );
}

const _themes = <(String, Brightness)>[
  ('dark', Brightness.dark),
  ('light', Brightness.light),
];

/// One app bar action of R-31-06-24 by its spoken name, on both platforms.
Finder _action(String label) => find.byWidgetPredicate(
  (Widget widget) => widget is ChromeIconAction && widget.label == label,
);

void main() {
  setUpAll(loadAppFonts);
  for (final platform in <TargetPlatform>[
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    for (final (themeName, brightness) in _themes) {
      for (final axis in <String>['priority', 'workspace']) {
        final platformName = platform == TargetPlatform.iOS ? 'ios' : 'android';
        testWidgets('$axis pinned ($platformName $themeName)', (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          await SharedPreferencesAsync().setString(
            'agent_list_pinned_host-1',
            axis == 'priority' ? '["w1:p4","w3:p11"]' : '["w1:p4","w1:p2"]',
          );
          final fixture = _AgentListFixture();
          final harness = _Harness(currentAttention: fixture.attention);
          addTearDown(harness.dispose);
          await _pumpScreen(tester, brightness, harness.build());
          await tester.pumpAndSettle();
          harness.messages.add(fixture.snapshot);
          await tester.pumpAndSettle();
          if (axis == 'workspace') {
            await tester.tap(find.text('Workspace'));
            await tester.pumpAndSettle();
          }
          expect(find.text('PINNED'), findsOneWidget);
          await expectLater(
            find.byType(AgentListScreen),
            matchesGoldenFile(
              'goldens/agent_list_${axis}_pinned_${platformName}_$themeName.png',
            ),
          );
          debugDefaultTargetPlatformOverride = null;
        });
      }
    }
  }

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  for (final (themeName, brightness) in _themes) {
    testWidgets(
      'priority grouping, NEEDS YOU ($themeName) matches docs/31-mockups/06-agent-list.md',
      (tester) async {
        final fixture = _AgentListFixture();
        final harness = _Harness(currentAttention: fixture.attention);
        addTearDown(harness.dispose);

        await _pumpScreen(tester, brightness, harness.build());
        harness.messages.add(fixture.snapshot);
        await tester.pumpAndSettle();

        // Structural proof alongside the visual one, per this package's own convention.
        expect(find.text('NEEDS YOU'), findsOneWidget);
        expect(find.text('WORKING'), findsOneWidget);
        expect(find.text('IDLE'), findsOneWidget);
        expect(find.text('UNKNOWN'), findsNothing);
        expect(find.text('Idle'), findsOneWidget);
        // Priority lists agents only: no shell pane, no bell and no plugin control in the app
        // bar (R-03-055, 2026-09-09).
        expect(find.text('zsh'), findsNothing);
        expect(find.text('Explorer'), findsNothing);
        expect(find.bySemanticsLabel('Computer actions'), findsNothing);
        // R-03-109 (corrected 2026-09-10), R-03-112: `Status colours` in the bar, no `New`
        // there; the create control is the floating action button.
        expect(_action('Status colours'), findsOneWidget);
        expect(_action('New'), findsNothing);
        expect(find.byType(FloatingActionButton), findsOneWidget);
        // R-03-107 (amended 2026-09-09): a body with content paints plain `color.bg.base`, no
        // grid.
        expect(find.byType(GroundGrid), findsNothing);

        await expectLater(
          find.byType(AgentListScreen),
          matchesGoldenFile('goldens/agent_list_priority_$themeName.png'),
        );
      },
    );

    testWidgets(
      'workspace grouping ($themeName) matches docs/31-mockups/06-agent-list.md',
      (tester) async {
        final fixture = _AgentListFixture();
        final harness = _Harness(currentAttention: fixture.attention);
        addTearDown(harness.dispose);

        await _pumpScreen(tester, brightness, harness.build());
        harness.messages.add(fixture.snapshot);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Workspace'));
        await tester.pumpAndSettle();

        // The search action of R-03-102 sits in the app bar and no field sits in the list;
        // then the first block: the space header alone names `lightspeed-kit`, because the
        // parent draws no worktree row; its `impl` tab sits directly under it, and its second
        // tab `bench` follows after the group gap and the hairline of R-03-057. The
        // `asset_library` worktree and the `scratch` block sit below the 667 px frame, so the
        // lazy list has not built them.
        expect(find.byKey(AgentListScreen.searchFieldKey), findsOneWidget);
        expect(find.byType(SearchBar), findsNothing);
        expect(find.text('lightspeed-kit'), findsOneWidget);
        expect(find.text('impl'), findsOneWidget);
        expect(find.text('bench'), findsOneWidget);
        expect(find.text('7 panes'), findsOneWidget);
        // Shell panes: display name and optional command share one baseline; no status word.
        expect(find.bySemanticsLabel('pane 2, zsh'), findsOneWidget);
        expect(find.bySemanticsLabel('Explorer'), findsOneWidget);
        expect(find.bySemanticsLabel('pane 6, cargo bench'), findsOneWidget);
        expect(find.text('Unknown'), findsNothing);
        // The idle `codex` row draws its word and no age.
        expect(find.text('Idle'), findsOneWidget);
        // R-03-107 (amended 2026-09-09): plain `color.bg.base` behind the cards, no grid.
        expect(find.byType(GroundGrid), findsNothing);
        expect(find.byType(FloatingActionButton), findsOneWidget);

        await expectLater(
          find.byType(AgentListScreen),
          matchesGoldenFile('goldens/agent_list_workspace_$themeName.png'),
        );
      },
    );

    testWidgets('workspace grouping iOS ($themeName)', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final fixture = _AgentListFixture();
      final harness = _Harness(currentAttention: fixture.attention);
      addTearDown(harness.dispose);
      await _pumpScreen(tester, brightness, harness.build());
      harness.messages.add(fixture.snapshot);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Workspace'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(AgentListScreen),
        matchesGoldenFile('goldens/agent_list_workspace_ios_$themeName.png'),
      );
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
      'empty state ($themeName) matches docs/31-mockups/06-agent-list.md',
      (tester) async {
        final harness = _Harness();
        addTearDown(harness.dispose);

        await _pumpScreen(tester, brightness, harness.build());
        harness.messages.add(
          const Message.treeSnapshot(
            TreeSnapshot(workspaces: [], tabs: [], panes: [], agents: []),
          ),
        );
        await tester.pumpAndSettle();
        await precacheBrandMark(tester, find.byType(AgentListScreen));
        await tester.pumpAndSettle();

        expect(find.text('No agents on patrick-desk.'), findsOneWidget);
        expect(
          find.text(
            'Start one in Herdr on your computer, then pull down to refresh.',
          ),
          findsOneWidget,
        );
        expect(find.text('Priority'), findsNothing);
        // R-03-107 (amended 2026-09-09): the empty block sits on the ground grid inside the
        // mark, its title in the display face in accent ink.
        final Finder title = find.text('No agents on patrick-desk.');
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
        final TextStyle titleStyle = tester.widget<Text>(title).style!;
        expect(titleStyle.fontFamily, AppType.title.fontFamily);
        expect(titleStyle.color, AppColor.of(tester.element(title)).accentText);

        await expectLater(
          find.byType(AgentListScreen),
          matchesGoldenFile('goldens/agent_list_empty_$themeName.png'),
        );
      },
    );
  }

  // The `Priority` grouping on iOS (added 2026-09-09, R-03-059, R-03-102): the axis chooser is a
  // `CupertinoSlidingSegmentedControl` there, so the platform form gets its own golden.
  for (final (themeName, brightness) in _themes) {
    testWidgets(
      'priority grouping (ios_$themeName) matches docs/31-mockups/06-agent-list.md',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        // A failed expect below must not leak the override into the next test; the binding
        // checks the variable before the tear-downs run, so the body resets it too.
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final fixture = _AgentListFixture();
        final harness = _Harness(currentAttention: fixture.attention);
        addTearDown(harness.dispose);

        await _pumpScreen(tester, brightness, harness.build());
        harness.messages.add(fixture.snapshot);
        await tester.pumpAndSettle();

        expect(find.text('NEEDS YOU'), findsOneWidget);
        expect(
          find.byType(CupertinoSlidingSegmentedControl<AgentListAxis>),
          findsOneWidget,
        );
        expect(find.byType(TabBar), findsNothing);
        expect(_action('New'), findsNothing);
        expect(find.byType(FloatingActionButton), findsOneWidget);

        await expectLater(
          find.byType(AgentListScreen),
          matchesGoldenFile('goldens/agent_list_priority_ios_$themeName.png'),
        );
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
}
