/// Smoke-tests `AgentListScreen` (`WP-18-b`) against `docs/31-mockups/06-agent-list.md`: the
/// default `Priority` grouping with its `NEEDS YOU` section (R-31-06-02), the `Empty` state, the
/// grouping-strip axis switch to `Workspace` with its `Space > Worktree > Tab > Pane` blocks
/// (R-31-06-27 to R-31-06-29, decided 2026-09-04 by the product owner), the shell rows of
/// R-31-06-14, the app bar with no plugin control (callout 2, R-03-055) and no attention badge,
/// the long-press `Mark as seen` action with its named custom semantics action (R-30-504,
/// R-32-580, R-30-298), and clearing the marker on a row tap (R-30-503, R-31-06-06).
///
/// Also covers: the five status icon/label pairs and their five distinct icon shapes
/// (R-30-400, R-30-401), the grouping strip staying shown for a single workspace (R-30-411,
/// R-31-06-13), the collapse of a space block (R-31-06-16), a regression guard against an
/// expander on a tab row (R-31-06-19), and the `Priority` headers replacing each other instead of
/// stacking while the list scrolls (R-32-569, amended 2026-09-08). The create-control
/// connection gate (R-31-06-22, amended 2026-09-08) has its own group.
library;

import 'dart:async';
import 'dart:ui' show SemanticsAction, TextBaseline, Tristate;

import 'package:cupertino_ui/cupertino_ui.dart'
    show
        CupertinoButton,
        CupertinoContextMenuAction,
        CupertinoListTile,
        CupertinoPageScaffold,
        CupertinoSearchTextField,
        CupertinoSlidingSegmentedControl;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/rendering.dart'
    show BoxConstraints, RenderBox;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/widgets.dart'
    show
        BoxDecoration,
        BoxShape,
        ColoredBox,
        Container,
        CustomScrollView,
        DecoratedBox,
        Element,
        Expansible,
        GestureDetector,
        Icon,
        IconData,
        IgnorePointer,
        MediaQuery,
        MediaQueryData,
        Offset,
        Opacity,
        Rect,
        Scrollable,
        Semantics,
        Size,
        SizedBox,
        SliverPadding,
        SliverToBoxAdapter,
        Text,
        TextDirection,
        TextSpan,
        TextStyle,
        TickerMode,
        ValueKey,
        Widget;
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
import 'package:herdr_mobile/services/agent_list.dart'
    show AgentListAxis, AgentListService;
import 'package:herdr_mobile/services/agent_status.dart' show AttentionItem;
import 'package:herdr_mobile/services/relay.dart'
    show RelayConnected, RelayConnectionState, RelayDisconnected;
import 'package:herdr_mobile/widgets/app_ground.dart' show EmptyMark;
import 'package:herdr_mobile/widgets/app_section_header.dart'
    show AppSectionHeader;
import 'package:herdr_mobile/widgets/ground_grid.dart' show GroundGrid;
import 'package:herdr_mobile/widgets/status_bar.dart' show BarState, StatusBar;
import 'package:herdr_mobile/widgets/theme/app_color.dart';
import 'package:herdr_mobile/widgets/theme/app_radius.dart' show AppBorder;
import 'package:herdr_mobile/widgets/theme/app_size.dart';
import 'package:herdr_mobile/widgets/theme/app_space.dart';
import 'package:herdr_mobile/widgets/theme/app_type.dart' show AppType;
import 'package:herdr_mobile/widgets/theme/chrome_icon_action.dart'
    show ChromeIconAction;
import 'package:herdr_mobile/widgets/theme/chrome_list_row.dart';
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart'
    show
        ExpansionTile,
        FilledButton,
        ListTile,
        FloatingActionButton,
        IconButton,
        Icons,
        MaterialApp,
        MenuItemButton,
        Scaffold,
        SearchBar,
        TabBar,
        TabBarView;
import 'package:shared_preferences/shared_preferences.dart'
    show SharedPreferencesAsync;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'row_actions_support.dart';

AttentionItem _attention({
  String paneId = 'w1:p9',
  String workspaceId = 'w1',
  String tabId = 'w1:t2',
  String agentKind = 'codex',
  AgentStatusKind status = AgentStatusKind.blocked,
  String? at = '2026-01-01T00:00:00Z',
}) => AttentionItem(
  hostId: 'host-1',
  paneId: paneId,
  workspaceId: workspaceId,
  tabId: tabId,
  agentKind: agentKind,
  tabTitle: 'impl',
  paneTitle: 'codex',
  status: status,
  at: at,
);

const _scroll = PaneScrollState(
  offsetFromBottom: 0,
  maxOffsetFromBottom: 0,
  viewportRows: 50,
);

PaneSummary _pane({
  required String paneId,
  String workspaceId = 'w1',
  String tabId = 'w1:t1',
  String label = '',
  String title = 'claude command',
  String? agent = 'claude',
  String agentStatus = 'idle',
}) => PaneSummary(
  paneId: paneId,
  workspaceId: workspaceId,
  tabId: tabId,
  terminalId: 'term_$paneId',
  label: label,
  title: title,
  cwd: '/home/user',
  focused: false,
  agent: agent,
  agentStatus: agentStatus,
  revision: 1,
  scroll: _scroll,
);

/// One workspace, one tab, one pane per [AgentStatusKind] value, so a single snapshot
/// exercises every status this screen draws (R-30-400, R-30-401).
Message _fiveStatusSnapshot() {
  const statuses = <String>['idle', 'working', 'blocked', 'done', 'unknown'];
  return Message.treeSnapshot(
    TreeSnapshot(
      workspaces: const [
        WorkspaceSummary(workspaceId: 'w1', name: 'ws', focused: true),
      ],
      tabs: const [
        TabSummary(
          tabId: 'w1:t1',
          workspaceId: 'w1',
          title: 'impl',
          focused: true,
        ),
      ],
      panes: [
        for (final status in statuses)
          _pane(
            paneId: 'w1:p-$status',
            label: 'row-$status',
            title: 'row-$status',
            agent: 'agent-$status',
            agentStatus: status,
          ),
      ],
      agents: [
        for (final status in statuses)
          AgentSummary(
            agentKind: 'agent-$status',
            paneId: 'w1:p-$status',
            status: status,
          ),
      ],
    ),
  );
}

/// One standalone workspace with one agent pane: the smallest `Workspace`-axis tree.
Message _oneAgentSnapshot() => Message.treeSnapshot(
  TreeSnapshot(
    workspaces: const [
      WorkspaceSummary(workspaceId: 'w1', name: 'herdr-relay', focused: true),
    ],
    tabs: const [
      TabSummary(
        tabId: 'w1:t2',
        workspaceId: 'w1',
        title: 'impl',
        focused: true,
      ),
    ],
    panes: [_pane(paneId: 'w1:p2', tabId: 'w1:t2', label: 'my-agent')],
    agents: const [
      AgentSummary(agentKind: 'claude', paneId: 'w1:p2', status: 'idle'),
    ],
  ),
);

/// The hierarchy of R-31-06-27: `lightspeed-kit` holds a main checkout (`impl`: one agent, one
/// shell pane with a command and one labelled shell pane `Explorer` with no `title`, so the row
/// has one line) and a linked worktree with no agent (`shell`: one shell pane), grouped by the
/// shared `spaceId`; the parent's tabs sit directly under the space header, with no worktree row
/// for the parent. `scratch` has no `worktree`, so it is its own space with no worktree row.
Message _hierarchySnapshot() => Message.treeSnapshot(
  TreeSnapshot(
    workspaces: const [
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
      WorkspaceSummary(workspaceId: 'w3', name: 'scratch', focused: false),
    ],
    tabs: const [
      TabSummary(
        tabId: 'w1:t1',
        workspaceId: 'w1',
        title: 'impl',
        focused: true,
      ),
      TabSummary(
        tabId: 'w2:t1',
        workspaceId: 'w2',
        title: 'shell',
        focused: false,
      ),
      TabSummary(
        tabId: 'w3:t1',
        workspaceId: 'w3',
        title: 'notes',
        focused: false,
      ),
    ],
    panes: [
      _pane(paneId: 'w1:p1', label: 'builder', agentStatus: 'working'),
      _pane(paneId: 'w1:p2', title: 'zsh', agent: null, agentStatus: 'unknown'),
      _pane(
        paneId: 'w1:p5',
        label: 'Explorer',
        title: '',
        agent: null,
        agentStatus: 'unknown',
      ),
      _pane(
        paneId: 'w2:p3',
        workspaceId: 'w2',
        tabId: 'w2:t1',
        title: 'npm run dev',
        agent: null,
        agentStatus: 'unknown',
      ),
      _pane(
        paneId: 'w3:p4',
        workspaceId: 'w3',
        tabId: 'w3:t1',
        agent: 'gemini',
        agentStatus: 'blocked',
      ),
    ],
    agents: const [],
  ),
);

Message _attentionSnapshot(List<AttentionItem> items) => Message.treeSnapshot(
  TreeSnapshot(
    workspaces: const [
      WorkspaceSummary(workspaceId: 'w1', name: 'ws', focused: true),
    ],
    tabs: const [
      TabSummary(
        tabId: 'w1:t2',
        workspaceId: 'w1',
        title: 'impl',
        focused: true,
      ),
    ],
    panes: [
      for (final item in items)
        _pane(
          paneId: item.paneId,
          tabId: item.tabId,
          agent: item.agentKind,
          agentStatus: item.status.name,
        ),
    ],
    agents: [
      for (final item in items)
        AgentSummary(
          agentKind: item.agentKind,
          paneId: item.paneId,
          status: item.status.name,
          statusAt: item.at,
        ),
    ],
  ),
);

class _Harness {
  _Harness({this.currentAttention = const <AttentionItem>[]})
    : messages = StreamController<Message>.broadcast(),
      connectionState = StreamController<RelayConnectionState>.broadcast(),
      attention = StreamController<List<AttentionItem>>.broadcast();

  final List<AttentionItem> currentAttention;
  final StreamController<Message> messages;
  final StreamController<RelayConnectionState> connectionState;
  final StreamController<List<AttentionItem>> attention;

  final List<String> markedSeen = <String>[];
  final List<String> notedOpened = <String>[];
  final List<String> openedPanes = <String>[];

  AgentListScreen build({
    void Function()? onCreate,
    void Function()? onOpenStatusColours,
    RelayConnectionState initialConnectionState = const RelayConnected(),
    DateTime Function() now = DateTime.now,
  }) => AgentListScreen(
    hostId: 'host-1',
    hostName: 'patrick-desk',
    messages: messages.stream,
    connectionState: connectionState.stream,
    initialConnectionState: initialConnectionState,
    send: (Message message, {String? corr}) {},
    unseenAttention: attention.stream,
    currentAttention: currentAttention,
    onMarkSeen: markedSeen.add,
    onNotePaneOpened: notedOpened.add,
    onOpenPane: openedPanes.add,
    onCreate: onCreate,
    onOpenStatusColours: onOpenStatusColours,
    now: now,
  );

  Future<void> dispose() async {
    await messages.close();
    await connectionState.close();
    await attention.close();
  }
}

/// Pumps the screen with animations off (a `working` dot pulses forever otherwise, and
/// `pumpAndSettle` never settles) and feeds it [snapshot]. The axis stays `Priority`.
Future<void> _pumpLoaded(
  WidgetTester tester,
  _Harness harness,
  Message snapshot,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: harness.build(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  harness.messages.add(snapshot);
  await tester.pumpAndSettle();
}

/// [_pumpLoaded], then switches to the `Workspace` axis.
Future<void> _pumpWorkspaceAxis(
  WidgetTester tester,
  _Harness harness,
  Message snapshot,
) async {
  await _pumpLoaded(tester, harness, snapshot);
  await tester.tap(find.text('Workspace'));
  await tester.pumpAndSettle();
}

/// Turns animations off for every route, not only for the screen under [_pumpLoaded]'s own
/// `MediaQuery`: the Android search view of R-03-102 is a route above the screen, and a
/// `working` bar inside it would pulse forever, so `pumpAndSettle` would never settle.
void _disableAnimationsEverywhere(WidgetTester tester) {
  tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(
    tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
  );
}

/// Drags the one list on screen until [finder] is built and visible. The list is lazy, so a
/// block below the fold of the 600 px test surface does not exist until the real list scrolls.
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.dragUntilVisible(
    finder,
    find.byType(CustomScrollView),
    const Offset(0, -200),
  );
  await tester.pumpAndSettle();
}

/// The row divider: a 1 px `color.border.subtle` box, drawn by the row itself (section 7.4's
/// `Divider` row).
Finder _rowDividers(AppColor color) => find.byWidgetPredicate(
  (Widget widget) =>
      widget is Container &&
      widget.constraints != null &&
      widget.constraints!.minHeight == 1 &&
      widget.constraints!.maxHeight == 1 &&
      widget.color == color.borderSubtle,
);

Finder _semanticsRow(String label) => find.byWidgetPredicate(
  (Widget widget) =>
      (widget is Semantics && widget.properties.label == label) ||
      (widget is ChromeListRow &&
          label.startsWith('${widget.title}, ') &&
          label.contains(' pane')),
);

bool _textHasRun(Text widget, String value) {
  bool spanHasRun(TextSpan span) =>
      span.text == value ||
      (span.children?.whereType<TextSpan>().any(
            (TextSpan child) => spanHasRun(child),
          ) ??
          false);
  return widget.data == value ||
      (widget.textSpan is TextSpan && spanHasRun(widget.textSpan! as TextSpan));
}

Finder _textRun(String value) => find.byWidgetPredicate(
  (Widget widget) => widget is Text && _textHasRun(widget, value),
);

/// A `Text` reading [text] inside the Android search view of R-03-102: the view is a route
/// above the screen, so nothing under [AgentListScreen] counts, and the list beneath the view
/// never inflates a match.
Finder _inSearchView(String text) => find.byElementPredicate(
  (Element element) =>
      element.widget is Text &&
      _textHasRun(element.widget as Text, text) &&
      element.findAncestorWidgetOfExactType<AgentListScreen>() == null,
);

/// The create control of R-03-109 (corrected 2026-09-10): the one `FloatingActionButton` under
/// its `New` semantics node, on both platforms.
Finder _createButton() => find.descendant(
  of: find.bySemanticsLabel('New'),
  matching: find.byType(FloatingActionButton),
);

/// Every `ChromeIconAction` in the app bar, in order: no `New` action stands among them.
Iterable<String> _actionLabels(WidgetTester tester) => tester
    .widgetList<ChromeIconAction>(find.byType(ChromeIconAction))
    .map((ChromeIconAction action) => action.label);

/// The `Status colours` action of R-03-112, on both platforms.
Finder _statusColoursAction() => find.byWidgetPredicate(
  (Widget widget) =>
      widget is ChromeIconAction && widget.label == 'Status colours',
);

/// The end padding of both axes (R-03-109, corrected 2026-09-10): `size.button.create` plus
/// `space.4`, the scroll view's own, never a fixed band.
const double _createClearance = AppSize.buttonCreate + AppSpace.space4;

/// The height of a list's end padding sliver, a `SliverToBoxAdapter` over one `SizedBox`.
double _endPadding(Widget sliver) =>
    ((sliver as SliverToBoxAdapter).child! as SizedBox).height!;

/// The one end padding box on screen; its top edge is the last row's bottom edge.
Finder _endPaddingBox() => find.descendant(
  of: find.byType(SliverToBoxAdapter),
  matching: find.byType(SizedBox),
);

Future<void> _performPinAction(
  WidgetTester tester,
  String paneLabel,
  String action,
) async {
  final node = tester.getSemantics(find.bySemanticsLabel(RegExp(paneLabel)));
  final ids = node.getSemanticsData().customSemanticsActionIds!;
  final id = ids.singleWhere(
    (id) => CustomSemanticsAction.getAction(id)?.label == action,
  );
  node.owner!.performAction(node.id, SemanticsAction.customAction, id);
  await tester.pumpAndSettle();
}

void main() {
  for (final platform in <TargetPlatform>[
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    testWidgets(
      '$platform: a long press opens Pin, then Unpin and Mark as seen, as platform menu '
      'items with their glyphs (R-32-708, R-33-077)',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        tester.view.physicalSize = const Size(375, 667);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final harness = _Harness(currentAttention: [_attention()]);
        addTearDown(harness.dispose);
        await _pumpLoaded(
          tester,
          harness,
          _attentionSnapshot(harness.currentAttention),
        );
        final Type item = platform == TargetPlatform.iOS
            ? CupertinoContextMenuAction
            : MenuItemButton;
        await openRowActions(tester, find.text('impl'));
        expect(find.widgetWithText(item, 'Pin'), findsOneWidget);
        await tester.tap(find.widgetWithText(item, 'Pin'));
        await tester.pumpAndSettle();
        expect(find.byType(item), findsNothing);
        await openRowActions(tester, find.text('impl'));
        for (final (label, icon) in <(String, IconData)>[
          ('Unpin', Symbols.keep_off_rounded),
          ('Mark as seen', Symbols.done_all_rounded),
        ]) {
          expect(find.widgetWithText(item, label), findsOneWidget);
          expect(
            find.descendant(
              of: find.widgetWithText(item, label),
              matching: find.byIcon(icon),
            ),
            findsOneWidget,
            reason: label,
          );
        }
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
  testWidgets('semantics pins and unpins a normal agent in both views', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final semantics = tester.ensureSemantics();
    await _pumpLoaded(tester, harness, _fiveStatusSnapshot());
    expect(find.text('PINNED'), findsNothing);
    await _performPinAction(tester, 'row-idle', 'Pin');
    expect(find.text('PINNED'), findsOneWidget);
    expect(find.text('IDLE'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('row-idle')), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('PINNED')).dy,
      lessThan(tester.getTopLeft(find.text('WORKING')).dy),
    );
    await tester.tap(find.text('Workspace'));
    await tester.pumpAndSettle();
    expect(find.text('PINNED'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('row-idle')), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('PINNED')).dy,
      lessThan(tester.getTopLeft(_semanticsRow('ws, 4 panes')).dy),
    );
    expect(
      tester.getTopLeft(find.text('agent-idle')).dx,
      moreOrLessEquals(
        tester.getTopLeft(find.text('PINNED')).dx,
        epsilon: 0.01,
      ),
    );
    await _performPinAction(tester, 'row-idle', 'Unpin');
    expect(find.text('PINNED'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('row-idle')), findsOneWidget);
    await tester.tap(find.text('Priority'));
    await tester.pumpAndSettle();
    expect(find.text('PINNED'), findsNothing);
    expect(find.text('IDLE'), findsOneWidget);
    expect(harness.openedPanes, isEmpty);
    expect(harness.markedSeen, isEmpty);
    semantics.dispose();
  });

  testWidgets('a long press pins and unpins a shell without Mark as seen', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await _pumpWorkspaceAxis(tester, harness, _hierarchySnapshot());
    expect(find.text('PINNED'), findsNothing);
    await openRowActions(tester, find.text('Explorer'));
    expect(find.text('Mark as seen'), findsNothing);
    await tester.tap(find.text('Pin'));
    await tester.pumpAndSettle();
    expect(find.text('PINNED'), findsOneWidget);
    expect(find.text('Explorer'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('PINNED')).dy,
      lessThan(tester.getTopLeft(_semanticsRow('lightspeed-kit, 3 panes')).dy),
    );
    await tester.tap(find.text('Priority'));
    await tester.pumpAndSettle();
    expect(find.text('PINNED'), findsNothing);
    expect(find.text('Explorer'), findsNothing);
    await tester.tap(find.text('Workspace'));
    await tester.pumpAndSettle();
    await openRowActions(tester, find.text('Explorer'));
    expect(find.text('Mark as seen'), findsNothing);
    await tester.tap(find.text('Unpin'));
    await tester.pumpAndSettle();
    expect(find.text('PINNED'), findsNothing);
    expect(find.text('Explorer'), findsOneWidget);
    expect(harness.openedPanes, isEmpty);
  });

  testWidgets(
    'pins survive service replacement and prune only after a snapshot',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      AgentListService service(String hostId) => AgentListService(
        messages: harness.messages.stream,
        connectionState: harness.connectionState.stream,
        send: (Message message, {String? corr}) {},
        unseenAttention: harness.attention.stream,
        currentAttention: const <AttentionItem>[],
        hostId: hostId,
      );
      final first = service('host-1');
      harness.messages.add(_fiveStatusSnapshot());
      await tester.pumpAndSettle();
      await first.togglePinned('w1:p-idle');
      await first.togglePinned('w1:p-working');
      expect(first.currentView.prioritySections.first.title, 'PINNED');
      expect(
        first.currentView.prioritySections.first.rows.map((row) => row.paneId),
        <String>['w1:p-idle', 'w1:p-working'],
      );
      expect(first.currentView.pinnedRows.map((row) => row.paneId), <String>[
        'w1:p-idle',
        'w1:p-working',
      ]);
      await first.togglePinned('w1:p-idle');
      await first.togglePinned('w1:p-idle');
      expect(first.currentView.pinnedRows.map((row) => row.paneId), <String>[
        'w1:p-working',
        'w1:p-idle',
      ]);
      first.dispose();
      final restored = service('host-1');
      addTearDown(restored.dispose);
      final otherHost = service('host-2');
      addTearDown(otherHost.dispose);
      await tester.pumpAndSettle();
      expect(restored.isPinned('w1:p-idle'), isTrue);
      expect(restored.isPinned('w1:p-working'), isTrue);
      expect(otherHost.isPinned('w1:p-idle'), isFalse);
      expect(
        await SharedPreferencesAsync().getString('agent_list_pinned_host-1'),
        '["w1:p-working","w1:p-idle"]',
      );
      harness.messages.add(_oneAgentSnapshot());
      await tester.pumpAndSettle();
      expect(restored.isPinned('w1:p-idle'), isFalse);
      expect(restored.isPinned('w1:p-working'), isFalse);
      expect(
        await SharedPreferencesAsync().getString('agent_list_pinned_host-1'),
        '[]',
      );
    },
  );
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('iOS: uses CupertinoPageScaffold, not Scaffold', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final harness = _Harness();
    addTearDown(harness.dispose);

    await tester.pumpWidget(MaterialApp(home: harness.build(onCreate: () {})));
    await tester.pump();

    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(find.byType(Scaffold), findsNothing);
    // R-32-350 `size.appbar`, iOS value: the app-built header row matches the 44 of
    // `CupertinoNavigationBar` on every other iOS screen (R-33-076).
    expect(
      tester
          .getSize(
            find
                .ancestor(
                  of: find.text('patrick-desk'),
                  matching: find.byType(SizedBox),
                )
                .first,
          )
          .height,
      AppSize.appBarIos,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  group('the create control (R-03-109 corrected 2026-09-10; R-03-112; R-31-06-24)', () {
    for (final TargetPlatform platform in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.iOS,
    ]) {
      testWidgets(
        '$platform: a floating action button spoken New, bottom trailing above the body\'s '
        'end; the app bar holds Status colours and the Android search only; each control '
        'appears only with its callback',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          var created = 0;
          var legends = 0;
          final harness = _Harness();
          addTearDown(harness.dispose);

          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: const MediaQueryData(disableAnimations: true),
                child: harness.build(
                  onCreate: () => created++,
                  onOpenStatusColours: () => legends++,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          harness.messages.add(_oneAgentSnapshot());
          await tester.pumpAndSettle();

          expect(_createButton(), findsOneWidget);
          expect(
            tester.getSemantics(find.bySemanticsLabel('New')).label,
            'New',
          );
          expect(find.bySemanticsLabel('Create'), findsNothing);
          // R-32-588: the component's own 56 box, `space.4` from the trailing edge and from
          // the bottom of the screen, on both platforms.
          final Rect fab = tester.getRect(_createButton());
          final Size screen = tester.getSize(find.byType(AgentListScreen));
          expect(
            fab.size,
            const Size(AppSize.buttonCreate, AppSize.buttonCreate),
          );
          expect(fab.right, screen.width - AppSpace.space4);
          expect(fab.bottom, screen.height - AppSpace.space4);
          // No `New` in the bar: `Status colours`, then the search action on Android alone.
          expect(
            _actionLabels(tester),
            platform == TargetPlatform.android
                ? <String>['Status colours', 'Search panes']
                : <String>['Status colours'],
          );
          expect(_statusColoursAction(), findsOneWidget);

          await tester.tap(_statusColoursAction());
          expect(legends, 1);
          await tester.tap(_createButton());
          expect(created, 1);

          final none = _Harness();
          addTearDown(none.dispose);
          await tester.pumpWidget(MaterialApp(home: none.build()));
          await tester.pump();
          expect(find.byType(FloatingActionButton), findsNothing);
          expect(_statusColoursAction(), findsNothing);
          // The binding checks the variable before the tear-downs run, so the body resets it.
          debugDefaultTargetPlatformOverride = null;
        },
      );

      testWidgets(
        '$platform: New gates on the live connection (R-31-06-22, amended 2026-09-08): seeded '
        'disconnected it stays on screen, disabled, announced disabled and dimmed; a drop after '
        'connect disables it and a reconnect re-enables it',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          var created = 0;
          final harness = _Harness();
          addTearDown(harness.dispose);

          await tester.pumpWidget(
            MaterialApp(
              home: harness.build(
                onCreate: () => created++,
                initialConnectionState: const RelayDisconnected(),
              ),
            ),
          );
          await tester.pump();

          expect(_createButton(), findsOneWidget);
          expect(
            tester.widget<FloatingActionButton>(_createButton()).onPressed,
            isNull,
          );
          expect(
            tester
                .getSemantics(find.bySemanticsLabel('New'))
                .flagsCollection
                .isEnabled,
            Tristate.isFalse,
          );
          // Dimmed to `opacity.disabled` (R-32-502) with its colours unchanged...
          expect(
            tester
                .widget<Opacity>(
                  find.ancestor(
                    of: _createButton(),
                    matching: find.byType(Opacity),
                  ),
                )
                .opacity,
            0.38,
          );
          // ...and the offline strip carries the reason.
          expect(
            find.text('Offline. Showing what we last saw.'),
            findsOneWidget,
          );
          await tester.tap(_createButton());
          await tester.pump();
          expect(created, 0);

          // One pump delivers the stream event; the rebuild it schedules lands on the next.
          harness.connectionState.add(const RelayConnected());
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<Opacity>(
                  find.ancestor(
                    of: _createButton(),
                    matching: find.byType(Opacity),
                  ),
                )
                .opacity,
            1,
          );
          await tester.tap(_createButton());
          expect(created, 1);

          harness.connectionState.add(const RelayDisconnected());
          await tester.pumpAndSettle();
          expect(
            tester.widget<FloatingActionButton>(_createButton()).onPressed,
            isNull,
          );
          await tester.tap(_createButton());
          await tester.pump();
          expect(created, 1);
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }

    testWidgets(
      'a null onCreate draws no create button even while offline (R-90-016 unchanged)',
      (tester) async {
        final harness = _Harness();
        addTearDown(harness.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: harness.build(
              initialConnectionState: const RelayDisconnected(),
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(FloatingActionButton), findsNothing);
        expect(find.bySemanticsLabel('New'), findsNothing);
      },
    );
  });

  testWidgets(
    'the app bar carries no plugin control and no attention badge (callout 2, R-03-055)',
    (tester) async {
      final harness = _Harness(currentAttention: [_attention()]);
      addTearDown(harness.dispose);

      await tester.pumpWidget(MaterialApp(home: harness.build()));
      harness.messages.add(
        const Message.treeSnapshot(
          TreeSnapshot(workspaces: [], tabs: [], panes: [], agents: []),
        ),
      );
      await tester.pumpAndSettle();

      // The count lives on the Notifications destination now: no bell, no `1` in the bar.
      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is Icon &&
              widget.icon == Symbols.notifications_active_rounded,
        ),
        findsNothing,
      );
      // R-03-055 (2026-09-09): a plugin acts on a pane, so the pane action sheet carries plugin
      // actions and this bar carries none.
      expect(find.bySemanticsLabel('Computer actions'), findsNothing);
    },
  );

  testWidgets('draws the NEEDS YOU section from the live tree snapshot', (
    tester,
  ) async {
    final harness = _Harness(currentAttention: [_attention()]);
    addTearDown(harness.dispose);

    await tester.pumpWidget(MaterialApp(home: harness.build()));
    harness.messages.add(_attentionSnapshot(harness.currentAttention));
    await tester.pumpAndSettle();

    expect(find.text('NEEDS YOU'), findsOneWidget);
    expect(find.text('impl'), findsOneWidget);
    expect(find.text('Blocked'), findsOneWidget);
  });

  testWidgets(
    'the Empty state names the computer and offers no grouping strip',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);

      await tester.pumpWidget(MaterialApp(home: harness.build()));
      await tester.pumpAndSettle();
      harness.messages.add(
        const Message.treeSnapshot(
          TreeSnapshot(workspaces: [], tabs: [], panes: [], agents: []),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No agents on patrick-desk.'), findsOneWidget);
      expect(find.text('Priority'), findsNothing);
    },
  );

  testWidgets(
    'a body with content paints no ground grid and no paper, and ends its slivers with the '
    'scroll view\'s own end padding for the create button, on either axis; the empty state is '
    'the grid with the mark, its title in the display face in accent ink and its sentence in '
    'body secondary (R-03-107, R-03-109 corrected 2026-09-10)',
    (tester) async {
      final harness = _Harness(currentAttention: [_attention()]);
      addTearDown(harness.dispose);

      await _pumpLoaded(tester, harness, _fiveStatusSnapshot());

      expect(find.byType(GroundGrid), findsNothing);
      final Finder headers = find.byType(AppSectionHeader);
      expect(headers, findsAtLeast(2));
      // One padded section group per header, then the one end padding of `size.button.create`
      // plus `space.4` (R-03-109, corrected 2026-09-10): no remainder sliver.
      final List<Widget> prioritySlivers = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .slivers;
      final int sectionCount = headers.evaluate().length;
      expect(prioritySlivers, hasLength(sectionCount + 1));
      expect(
        prioritySlivers.take(sectionCount),
        everyElement(isA<SliverPadding>()),
      );
      expect(
        (prioritySlivers[sectionCount - 1] as SliverPadding).padding
            .resolve(TextDirection.ltr)
            .bottom,
        0,
      );
      expect(_endPadding(prioritySlivers.last), _createClearance);

      await tester.tap(find.text('Workspace'));
      await tester.pumpAndSettle();
      expect(find.text('ws'), findsOneWidget); // The space card.
      expect(find.byType(GroundGrid), findsNothing);
      final List<Widget> workspaceSlivers = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .slivers;
      expect(workspaceSlivers, hasLength(2));
      expect(
        (workspaceSlivers.first as SliverPadding).padding
            .resolve(TextDirection.ltr)
            .bottom,
        0,
      );
      expect(_endPadding(workspaceSlivers.last), _createClearance);

      // The tree loses its workspaces while the Workspace page is shown; the unseen attention
      // row keeps the strip (R-31-06-14), so the page shows its own empty block on the grid.
      harness.messages.add(
        const Message.treeSnapshot(
          TreeSnapshot(workspaces: [], tabs: [], panes: [], agents: []),
        ),
      );
      await tester.pumpAndSettle();
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
      final AppColor color = AppColor.of(tester.element(title));
      final TextStyle titleStyle = tester.widget<Text>(title).style!;
      expect(titleStyle.fontFamily, AppType.title.fontFamily);
      expect(titleStyle.fontSize, AppType.title.fontSize);
      expect(titleStyle.color, color.accentText);
      final TextStyle sentenceStyle = tester
          .widget<Text>(
            find.text(
              'Start one in Herdr on your computer, then pull down to refresh.',
            ),
          )
          .style!;
      expect(sentenceStyle.fontSize, AppType.body.fontSize);
      expect(sentenceStyle.color, color.fgSecondary);
    },
  );

  for (final TargetPlatform platform in <TargetPlatform>[
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    testWidgets(
      '$platform: a list that fits the screen ends at its last row above the create button '
      'with nothing to scroll, and a list that overflows scrolls its last row exactly clear '
      'of the button (R-03-109, corrected 2026-09-10)',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final harness = _Harness();
        addTearDown(harness.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: harness.build(onCreate: () {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
        harness.messages.add(_oneAgentSnapshot());
        await tester.pumpAndSettle();

        // Short list, one row: the end padding starts where that row ends, above the button,
        // and the list has no scroll extent, so no band can come into view.
        final Rect fab = tester.getRect(_createButton());
        final Finder endPadding = _endPaddingBox();
        expect(endPadding, findsOneWidget);
        expect(tester.getRect(endPadding).top, lessThan(fab.top));
        expect(
          Scrollable.of(tester.element(endPadding)).position.maxScrollExtent,
          0,
        );

        // Long list: twenty working rows overflow the 600 px surface. Scrolled to the end, the
        // last row's bottom edge is the button's top edge: clear of it, with no band below.
        harness.messages.add(
          Message.treeSnapshot(
            TreeSnapshot(
              workspaces: const [
                WorkspaceSummary(workspaceId: 'w1', name: 'ws', focused: true),
              ],
              tabs: const [
                TabSummary(
                  tabId: 'w1:t1',
                  workspaceId: 'w1',
                  title: 'impl',
                  focused: true,
                ),
              ],
              panes: [
                for (int i = 0; i < 20; i++)
                  _pane(paneId: 'w1:pw$i', agentStatus: 'working'),
              ],
              agents: const [],
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.drag(
          find.byType(CustomScrollView),
          const Offset(0, -5000),
        );
        await tester.pumpAndSettle();

        expect(
          Scrollable.of(tester.element(_endPaddingBox())).position.pixels,
          greaterThan(0),
        );
        final Rect end = tester.getRect(_endPaddingBox());
        expect(end.top, moreOrLessEquals(fab.top, epsilon: 0.5));
        expect(
          end.bottom,
          moreOrLessEquals(fab.bottom + AppSpace.space4, epsilon: 0.5),
        );
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets('Android: the two axes are the pages of a TabBarView on the strip\'s controller; a drag of '
      'the page settles on Workspace and the service follows, and under reduced motion a tab tap '
      'switches in one frame (R-03-108, R-32-606)', (tester) async {
    // The reference phone width, so a 300 px drag is most of a page and the page physics
    // settle on the next page; on the default 800 px test surface it would spring back.
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = _Harness();
    addTearDown(harness.dispose);

    await _pumpLoaded(tester, harness, _oneAgentSnapshot());

    final Finder pages = find.byType(TabBarView);
    expect(pages, findsOneWidget);
    expect(
      tester.widget<TabBarView>(pages).controller,
      same(tester.widget<TabBar>(find.byType(TabBar)).controller),
    );
    expect(find.text('NEEDS YOU'), findsNothing);
    expect(find.text('IDLE'), findsOneWidget);
    expect(find.text('herdr-relay'), findsNothing);

    // From the bare ground under the one row, so no row reveal takes the drag.
    await tester.dragFrom(
      tester.getBottomLeft(pages) + const Offset(180, -60),
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('herdr-relay'), findsOneWidget); // The space card.
    expect(find.text('IDLE'), findsNothing);
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);
    // The service took the settled page as the axis and persisted it (R-31-06-12).
    expect(
      await SharedPreferencesAsync().getString('agent_list_axis_host-1'),
      'workspace',
    );

    // `_pumpLoaded` turns animations off: the tab tap jumps, no 300 ms page slide.
    await tester.tap(find.text('Priority'));
    await tester.pump();
    expect(find.text('IDLE'), findsOneWidget);
    expect(find.text('herdr-relay'), findsNothing);
    expect(
      await SharedPreferencesAsync().getString('agent_list_axis_host-1'),
      'priority',
    );
  });

  testWidgets(
    'panes without agents keep the strip: Priority is empty, Workspace lists them (R-31-06-14)',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);

      await tester.pumpWidget(MaterialApp(home: harness.build()));
      await tester.pumpAndSettle();
      harness.messages.add(
        Message.treeSnapshot(
          TreeSnapshot(
            workspaces: const [
              WorkspaceSummary(
                workspaceId: 'w1',
                name: 'scratch',
                focused: true,
              ),
            ],
            tabs: const [
              TabSummary(
                tabId: 'w1:t1',
                workspaceId: 'w1',
                title: 'notes',
                focused: true,
              ),
            ],
            panes: [
              _pane(
                paneId: 'w1:p1',
                title: 'zsh',
                agent: null,
                agentStatus: 'unknown',
              ),
            ],
            agents: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No agents on patrick-desk.'), findsOneWidget);
      expect(find.text('Priority'), findsOneWidget);

      await tester.tap(find.text('Workspace'));
      await tester.pumpAndSettle();
      expect(find.text('No agents on patrick-desk.'), findsNothing);
      expect(find.text('scratch'), findsOneWidget);
      expect(_textRun('pane 1'), findsOneWidget);
      expect(_textRun('zsh'), findsOneWidget);
    },
  );

  for (final platform in <TargetPlatform>[
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    testWidgets(
      '$platform: native host button, pane row and workspace expansion',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final harness = _Harness();
        addTearDown(harness.dispose);
        await _pumpWorkspaceAxis(tester, harness, _oneAgentSnapshot());
        expect(
          find.byType(
            platform == TargetPlatform.iOS ? Expansible : ExpansionTile,
          ),
          findsOneWidget,
        );
        expect(
          find.byType(
            platform == TargetPlatform.iOS ? CupertinoListTile : ListTile,
          ),
          findsWidgets,
        );
        expect(
          find.ancestor(
            of: find.text('patrick-desk'),
            matching: find.byType(
              platform == TargetPlatform.iOS ? CupertinoButton : FilledButton,
            ),
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('herdr-relay'));
        await tester.pumpAndSettle();
        expect(find.text('my-agent'), findsNothing);
        await tester.tap(find.text('herdr-relay'));
        await tester.pumpAndSettle();
        expect(find.text('my-agent'), findsOneWidget);
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets('switching to Workspace draws the space header, tab sub-header and one-line pane '
      'label (R-31-06-18, R-03-115)', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);

    await _pumpWorkspaceAxis(tester, harness, _oneAgentSnapshot());

    expect(find.text('herdr-relay'), findsOneWidget); // The space header.
    expect(find.text('impl'), findsOneWidget); // The tab sub-header.
    expect(
      find.text('my-agent'),
      findsOneWidget,
    ); // The agent row has the pane name, not the header breadcrumb.
    expect(find.text('herdr-relay›impl›my-agent'), findsNothing);
    expect(find.text('1 pane'), findsOneWidget);
  });

  testWidgets('the Workspace axis draws Space > Worktree > Tab > Pane, and lists shell panes '
      '(R-31-06-27, R-31-06-14)', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);

    await _pumpWorkspaceAxis(tester, harness, _hierarchySnapshot());

    // The space header alone: the parent draws no worktree row.
    expect(find.text('lightspeed-kit'), findsOneWidget);
    expect(
      find.text('asset_library'),
      findsOneWidget,
    ); // The linked worktree row.
    expect(find.text('impl'), findsOneWidget);
    expect(find.text('shell'), findsOneWidget);
    expect(
      find.text('builder'),
      findsOneWidget,
    ); // The agent pane name follows its kind.
    expect(find.text('claude'), findsOneWidget);
    // Shell panes: display name and optional command share one baseline, with no status word.
    expect(_textRun('pane 2'), findsOneWidget);
    expect(_textRun('zsh'), findsOneWidget);
    expect(_textRun('Explorer'), findsOneWidget);
    expect(_textRun('pane 3'), findsOneWidget);
    expect(_textRun('npm run dev'), findsOneWidget);
    expect(find.text('Unknown'), findsNothing);
    // Counts: `N panes` on every space header (R-31-06-28).
    expect(find.text('4 panes'), findsOneWidget);

    // The ladder of R-32-570 (amended 2026-09-09, R-03-057): four text edges one `space.4`
    // apart inside the block, the space name, the worktree label, the tab title and the pane
    // text, so the parent of a row reads off its edge; every glyph sits `space.2` before its
    // text. The agent row's state bar (R-03-100) sits at the row's own leading edge, beside the
    // guide rule, and leaves the ladder where it was (owner finding, 2026-09-09).
    double leftOf(Finder finder) => tester.getTopLeft(finder.first).dx;
    Finder icon(IconData data) => find.byWidgetPredicate(
      (Widget widget) => widget is Icon && widget.icon == data,
    );
    // The block is inset `space.4` from the screen edge; its hairline border paints over the
    // block's own edge and moves nothing.
    const double blockEdge = AppSpace.space4;
    final double spaceLabelLeft = leftOf(find.text('lightspeed-kit'));
    final double worktreeGlyphLeft = leftOf(icon(Symbols.fork_right_rounded));
    final double worktreeLabelLeft = leftOf(find.text('asset_library'));
    final double tabGlyphLeft = leftOf(icon(Symbols.tab_rounded));
    final double tabLeft = leftOf(find.text('impl'));
    final Finder agentBar = find.descendant(
      of: _semanticsRow('claude, Working, builder'),
      matching: find.byType(StatusBar),
    );
    final double paneGlyphLeft = leftOf(icon(Symbols.splitscreen_rounded));
    final double paneTextLeft = leftOf(find.text('claude'));
    expect(spaceLabelLeft, blockEdge + AppSpace.space4);
    expect(worktreeLabelLeft - spaceLabelLeft, AppSpace.space4);
    expect(tabLeft - worktreeLabelLeft, AppSpace.space4);
    expect(paneTextLeft - tabLeft, AppSpace.space4);
    expect(
      worktreeLabelLeft - worktreeGlyphLeft,
      AppSize.iconSm + AppSpace.space2,
    );
    expect(tabLeft - tabGlyphLeft, AppSize.iconSm + AppSpace.space2);
    expect(paneTextLeft - paneGlyphLeft, AppSize.iconSm + AppSpace.space2);
    // The state bar starts where the guide rule ends: at `space.8` plus the rule's own hairline
    // inside the block, not at the block's edge, so the bar marks its row and not the card; as
    // wide as `border.attention`; the empty slot keeps the pane text on the ladder.
    final Finder guideRule = find.byWidgetPredicate(
      (Widget widget) => widget is IgnorePointer && widget.child is ColoredBox,
    );
    expect(agentBar, findsOneWidget);
    expect(leftOf(agentBar), tester.getTopRight(guideRule.first).dx);
    expect(leftOf(agentBar), blockEdge + AppSpace.space8 + AppBorder.hairline);
    expect(tester.getSize(agentBar).width, AppBorder.attention);
    // A shell row keeps its text in the agent rows' column (R-32-597).
    expect(leftOf(_textRun('pane 2')), paneTextLeft);
    expect(leftOf(_textRun('Explorer')), paneTextLeft);

    // A shell row is tappable like any pane row.
    await tester.ensureVisible(_textRun('npm run dev'));
    await tester.pumpAndSettle();
    await tester.tap(_textRun('npm run dev'));
    expect(harness.notedOpened, ['w2:p3']);
    expect(harness.openedPanes, ['w2:p3']);

    // `scratch` has no worktree: its own space, no worktree row, tabs right under it. Its block
    // sits below the fold of the 600 px test surface, so the lazy list builds it only once the
    // real list is scrolled to it.
    await _scrollTo(tester, find.text('scratch'));
    expect(find.text('scratch'), findsOneWidget);
    expect(find.text('notes'), findsOneWidget);
    expect(find.text('gemini'), findsOneWidget);
    expect(find.text('1 pane'), findsOneWidget);
  });

  testWidgets(
    'a collapsed space keeps its count and badge and hides its rows (R-31-06-16)',
    (tester) async {
      final harness = _Harness(
        currentAttention: [
          _attention(
            paneId: 'w3:p4',
            workspaceId: 'w3',
            tabId: 'w3:t1',
            agentKind: 'gemini',
          ),
        ],
      );
      addTearDown(harness.dispose);

      final Finder badgeIcon = find.byWidgetPredicate(
        (Widget widget) =>
            widget is Icon &&
            widget.icon == Symbols.notifications_active_rounded,
      );
      final Finder scratchHeader = _semanticsRow(
        'scratch, 1 pane, 1 needing attention',
      );

      await _pumpWorkspaceAxis(tester, harness, _hierarchySnapshot());
      await _scrollTo(
        tester,
        find.text('scratch'),
      ); // Below the fold until scrolled.
      expect(find.text('gemini'), findsOneWidget);
      expect(badgeIcon, findsOneWidget); // Only `scratch` holds attention.
      expect(scratchHeader, findsOneWidget);

      await tester.tap(find.text('scratch'));
      await tester.pumpAndSettle();

      expect(find.text('gemini'), findsNothing);
      expect(find.text('notes'), findsNothing);
      expect(find.text('1 pane'), findsOneWidget);
      expect(badgeIcon, findsOneWidget);
      expect(scratchHeader, findsOneWidget);
    },
  );

  testWidgets(
    'Android: the pane search is a search action in the app bar that opens the Material '
    'search view, on both axes, and no field sits in the body (R-03-102, R-33-033)',
    (tester) async {
      _disableAnimationsEverywhere(tester);
      final harness = _Harness();
      addTearDown(harness.dispose);

      await _pumpLoaded(tester, harness, _hierarchySnapshot());
      final Finder action = find.byKey(AgentListScreen.searchFieldKey);
      expect(
        action,
        findsOneWidget,
      ); // On `Priority` too: the view searches every pane.
      expect(
        find.byType(SearchBar),
        findsNothing,
      ); // No loose pill in the body.
      expect(find.byType(CupertinoSearchTextField), findsNothing);
      // In the app bar, on the host chip's row, above the tab bar.
      expect(
        tester.getBottomLeft(action).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.text('Workspace')).dy),
      );

      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.byType(SearchBar), findsOneWidget); // The view's own field.
      expect(find.text('Search panes'), findsOneWidget);

      // The view's own back control closes it; the Workspace axis has no field in its body
      // either, only the same action in the bar.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(SearchBar), findsNothing);
      await tester.tap(find.text('Workspace'));
      await tester.pumpAndSettle();
      expect(find.byType(SearchBar), findsNothing);
      expect(find.byType(CupertinoSearchTextField), findsNothing);
      expect(action, findsOneWidget);
    },
  );

  testWidgets(
    'iOS: switching axes keeps the switcher fixed and search starts the Workspace content',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);

      await _pumpLoaded(tester, harness, _oneAgentSnapshot());
      expect(find.byType(CupertinoSearchTextField), findsNothing);
      final switcher = find.byType(
        CupertinoSlidingSegmentedControl<AgentListAxis>,
      );
      final priorityPosition = tester.getRect(switcher);
      final titlePosition = tester.getRect(find.text('patrick-desk'));
      expect(find.byType(TabBar), findsNothing);
      expect(find.byType(TabBarView), findsNothing);

      await tester.tap(find.text('Workspace'));
      await tester.pumpAndSettle();
      expect(tester.getRect(switcher), priorityPosition);
      expect(tester.getRect(find.text('patrick-desk')), titlePosition);
      final field = find.byKey(AgentListScreen.searchFieldKey);
      expect(find.byType(CupertinoSearchTextField), findsOneWidget);
      expect(find.byType(SearchBar), findsNothing);
      expect(
        tester.getTopLeft(field).dy,
        greaterThan(tester.getBottomLeft(switcher).dy),
      );
      expect(
        tester.getBottomLeft(field).dy,
        lessThan(tester.getTopLeft(find.text('herdr-relay')).dy),
      );
      expect(
        find.ancestor(of: field, matching: find.byType(CustomScrollView)),
        findsOneWidget,
      );
      expect(tester.getTopLeft(field).dx, AppSpace.space4);

      await tester.tap(find.text('Priority'));
      await tester.pumpAndSettle();
      expect(tester.getRect(switcher), priorityPosition);
      expect(find.byType(CupertinoSearchTextField), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'Android: typing in the search view narrows the tree to the match and its ancestors; no '
    'match keeps the view and says so; closing the view shows everything (R-31-06-30)',
    (tester) async {
      _disableAnimationsEverywhere(tester);
      final harness = _Harness();
      addTearDown(harness.dispose);

      await _pumpLoaded(tester, harness, _hierarchySnapshot());
      await tester.tap(find.byKey(AgentListScreen.searchFieldKey));
      await tester.pumpAndSettle();
      final Finder field = find.byType(SearchBar);

      await tester.enterText(field, 'npm');
      await tester.pumpAndSettle();
      // The shell pane `npm run dev` with its tab, worktree and space; nothing else.
      expect(_inSearchView('npm run dev'), findsOneWidget);
      expect(_inSearchView('shell'), findsOneWidget);
      expect(_inSearchView('asset_library'), findsOneWidget);
      expect(
        _inSearchView('lightspeed-kit'),
        findsOneWidget,
      ); // The header alone.
      expect(_inSearchView('1 pane'), findsOneWidget);
      expect(_inSearchView('impl'), findsNothing);
      expect(_inSearchView('builder'), findsNothing);
      expect(_inSearchView('scratch'), findsNothing);

      await tester.enterText(field, 'Gemini');
      await tester.pumpAndSettle();
      // Case-insensitive, agent kind.
      expect(_inSearchView('gemini'), findsOneWidget);
      expect(_inSearchView('scratch'), findsOneWidget);
      expect(_inSearchView('lightspeed-kit'), findsNothing);

      await tester.enterText(field, 'zzz');
      await tester.pumpAndSettle();
      expect(_inSearchView('No pane matches \u201Czzz\u201D.'), findsOneWidget);
      expect(field, findsOneWidget);
      expect(find.text('No panes on patrick-desk.'), findsNothing);
      expect(find.text('No agents on patrick-desk.'), findsNothing);

      // Clear with the view's own × control, not `enterText('')`: `SearchAnchor` clears the
      // controller without firing `viewOnChanged`, and until 2026-09-11 the results kept
      // naming the old text. The screen now follows the controller itself.
      await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
      await tester.pumpAndSettle();
      expect(_inSearchView('lightspeed-kit'), findsOneWidget);
      expect(_inSearchView('4 panes'), findsOneWidget);
      expect(find.textContaining('No pane matches'), findsNothing);

      // A result tap closes the view and opens the pane.
      await tester.enterText(field, 'npm');
      await tester.pumpAndSettle();
      await tester.tap(_inSearchView('npm run dev'));
      await tester.pumpAndSettle();
      expect(find.byType(SearchBar), findsNothing);
      expect(harness.openedPanes, isNotEmpty);

      // Closing the view cleared the search: the Workspace axis shows the whole tree.
      await tester.tap(find.text('Workspace'));
      await tester.pumpAndSettle();
      expect(find.text('4 panes'), findsOneWidget);
      expect(find.textContaining('No pane matches'), findsNothing);
    },
  );

  testWidgets(
    'Android: an agent row with a time renders inside the search view, with its age ticking off '
    'the screen clock, and throws nothing (R-03-056, R-03-102)',
    (tester) async {
      _disableAnimationsEverywhere(tester);
      final harness = _Harness();
      addTearDown(harness.dispose);

      // The search view is a route above the screen, so the view's rows need their own
      // `_AgeClock`; with none, every row that has a time throws on `_AgeClock.of`.
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: harness.build(now: () => DateTime.utc(2026, 1, 1, 0, 0, 42)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      harness.messages.add(
        Message.treeSnapshot(
          TreeSnapshot(
            workspaces: const [
              WorkspaceSummary(
                workspaceId: 'w1',
                name: 'herdr-relay',
                focused: true,
              ),
            ],
            tabs: const [
              TabSummary(
                tabId: 'w1:t2',
                workspaceId: 'w1',
                title: 'impl',
                focused: true,
              ),
            ],
            panes: [_pane(paneId: 'w1:p2', tabId: 'w1:t2', label: 'my-agent')],
            agents: const [
              AgentSummary(
                agentKind: 'claude',
                paneId: 'w1:p2',
                status: 'idle',
                statusAt: '2026-01-01T00:00:00Z',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(AgentListScreen.searchFieldKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(SearchBar), 'my-ag');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(_inSearchView('my-agent'), findsOneWidget);
      expect(_inSearchView('claude'), findsOneWidget);
      expect(_inSearchView('42s'), findsOneWidget);
    },
  );

  testWidgets('iOS: typing in the field narrows the tree in place and clearing restores everything '
      '(R-31-06-30)', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final harness = _Harness();
    addTearDown(harness.dispose);

    await _pumpWorkspaceAxis(tester, harness, _hierarchySnapshot());
    final Finder field = find.byKey(AgentListScreen.searchFieldKey);

    await tester.enterText(field, 'npm');
    await tester.pumpAndSettle();
    expect(_textRun('npm run dev'), findsOneWidget);
    expect(find.text('1 pane'), findsOneWidget);
    expect(find.text('impl'), findsNothing);

    await tester.enterText(field, 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No pane matches \u201Czzz\u201D.'), findsOneWidget);
    expect(field, findsOneWidget);
    expect(find.text('Workspace'), findsOneWidget); // The strip stays.
    expect(find.text('No panes on patrick-desk.'), findsNothing);

    await tester.enterText(field, '');
    await tester.pumpAndSettle();
    expect(find.text('4 panes'), findsOneWidget);
    expect(find.textContaining('No pane matches'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'a long press on a NEEDS YOU row opens Mark as seen; tapping it calls onMarkSeen',
    (tester) async {
      final harness = _Harness(currentAttention: [_attention()]);
      addTearDown(harness.dispose);

      await tester.pumpWidget(MaterialApp(home: harness.build()));
      harness.messages.add(_attentionSnapshot(harness.currentAttention));
      await tester.pumpAndSettle();

      await openRowActions(tester, find.text('impl'));

      expect(find.text('Mark as seen'), findsOneWidget);
      await tester.tap(find.text('Mark as seen'));
      await tester.pumpAndSettle();

      expect(harness.markedSeen, ['w1:p9']);
    },
  );

  testWidgets(
    'Mark as seen is also a named custom semantics action (R-32-580, R-30-298)',
    (tester) async {
      final harness = _Harness(currentAttention: [_attention()]);
      addTearDown(harness.dispose);
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(MaterialApp(home: harness.build()));
      harness.messages.add(_attentionSnapshot(harness.currentAttention));
      await tester.pumpAndSettle();

      final node = tester.getSemantics(find.text('impl'));
      final ids =
          node.getSemanticsData().customSemanticsActionIds ?? const <int>[];
      final labels = ids
          .map((int id) => CustomSemanticsAction.getAction(id)?.label)
          .toList();
      expect(labels, contains('Mark as seen'));

      handle.dispose();
    },
  );

  testWidgets(
    'a row tap clears the marker and routes to the pane (R-30-503, R-31-06-06)',
    (tester) async {
      final harness = _Harness(currentAttention: [_attention()]);
      addTearDown(harness.dispose);

      await tester.pumpWidget(MaterialApp(home: harness.build()));
      harness.messages.add(_attentionSnapshot(harness.currentAttention));
      await tester.pumpAndSettle();

      await tester.tap(find.text('impl'));
      await tester.pumpAndSettle();

      expect(harness.notedOpened, ['w1:p9']);
      expect(harness.openedPanes, ['w1:p9']);
    },
  );

  testWidgets('a live attention update is held while a finger is down, and applied on lift '
      '(R-31-06-05)', (tester) async {
    final older = _attention(paneId: 'w1:p1', at: '2026-01-01T00:00:00Z');
    final harness = _Harness(currentAttention: [older]);
    addTearDown(harness.dispose);

    await tester.pumpWidget(MaterialApp(home: harness.build()));
    harness.messages.add(_attentionSnapshot(harness.currentAttention));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('w1:p2')), findsNothing);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('impl')),
    );
    final evenOlder = _attention(paneId: 'w1:p2', at: '2025-01-01T00:00:00Z');
    harness.messages.add(_attentionSnapshot([evenOlder, older]));
    harness.attention.add([evenOlder, older]);
    await tester.pump();

    // Held: the newly-attention pane does not appear while the finger is still down.
    expect(find.byKey(const ValueKey<String>('w1:p2')), findsNothing);

    await gesture.up();
    await tester.pumpAndSettle();

    // Applied on lift.
    expect(find.byKey(const ValueKey<String>('w1:p2')), findsOneWidget);
  });

  testWidgets(
    'all five agent-status states render a state bar and a text label (R-30-400, R-03-100)',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: harness.build(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      harness.messages.add(_fiveStatusSnapshot());
      await tester.pumpAndSettle();

      for (final label in ['Idle', 'Working', 'Blocked', 'Done', 'Unknown']) {
        expect(find.text(label), findsOneWidget);
      }
      // One bar per row and no dot anywhere: the bar is the one state mark (R-03-100).
      expect(find.byType(StatusBar), findsNWidgets(5));
      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is DecoratedBox &&
              (widget.decoration as BoxDecoration?)?.shape == BoxShape.circle,
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'the five state bars are five distinct BarStates, not only colours (R-30-401)',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: harness.build(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      harness.messages.add(_fiveStatusSnapshot());
      await tester.pumpAndSettle();

      final bars = tester.widgetList<StatusBar>(find.byType(StatusBar));
      final states = bars.map((bar) => bar.state).toSet();
      expect(states, {
        BarState.idle,
        BarState.working,
        BarState.blocked,
        BarState.done,
        BarState.unknown,
      });
    },
  );

  testWidgets(
    'an agent-less workspace and tab are listed on the Workspace axis (R-31-06-14, 2026-09-04)',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);

      await _pumpWorkspaceAxis(
        tester,
        harness,
        Message.treeSnapshot(
          TreeSnapshot(
            workspaces: const [
              WorkspaceSummary(
                workspaceId: 'w1',
                name: 'herdr-relay',
                focused: true,
              ),
              WorkspaceSummary(
                workspaceId: 'w-empty',
                name: 'Empty Workspace',
                focused: false,
              ),
            ],
            tabs: const [
              TabSummary(
                tabId: 'w1:t1',
                workspaceId: 'w1',
                title: 'impl',
                focused: true,
              ),
              TabSummary(
                tabId: 'w1:t-empty',
                workspaceId: 'w1',
                title: 'Empty Tab',
                focused: false,
              ),
            ],
            panes: [_pane(paneId: 'w1:p1', label: 'my-agent')],
            agents: const [
              AgentSummary(
                agentKind: 'claude',
                paneId: 'w1:p1',
                status: 'idle',
              ),
            ],
          ),
        ),
      );

      expect(find.text('herdr-relay'), findsOneWidget);
      expect(find.text('impl'), findsOneWidget);
      expect(find.text('Empty Workspace'), findsOneWidget);
      expect(find.text('Empty Tab'), findsOneWidget);
      expect(find.text('0 panes'), findsOneWidget);
    },
  );

  testWidgets(
    'the grouping strip stays shown for a single workspace with one agent, as the platform '
    'view switcher: a TabBar on Android (R-30-411, R-31-06-13, R-03-102)',
    (tester) async {
      final harness = _Harness(currentAttention: [_attention()]);
      addTearDown(harness.dispose);

      await tester.pumpWidget(MaterialApp(home: harness.build()));
      harness.messages.add(_attentionSnapshot(harness.currentAttention));
      await tester.pumpAndSettle();

      expect(find.text('Priority'), findsOneWidget);
      expect(find.text('Workspace'), findsOneWidget);
      expect(find.byType(TabBar), findsOneWidget);
      expect(
        find.byType(CupertinoSlidingSegmentedControl<AgentListAxis>),
        findsNothing,
      );
    },
  );

  testWidgets(
    'Priority headers replace each other while scrolling and never stack (R-32-569, 2026-09-08)',
    (tester) async {
      // Twelve NEEDS YOU rows and eight WORKING rows: each section is taller than the 600 px
      // test surface, so scrolling past NEEDS YOU must hand the top of the list to WORKING.
      final harness = _Harness(
        currentAttention: [
          for (int i = 0; i < 12; i++)
            _attention(
              paneId: 'w1:pa$i',
              at: '2026-01-01T00:00:${i.toString().padLeft(2, '0')}Z',
            ),
        ],
      );
      addTearDown(harness.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: harness.build(),
          ),
        ),
      );
      harness.messages.add(
        Message.treeSnapshot(
          TreeSnapshot(
            workspaces: const [
              WorkspaceSummary(workspaceId: 'w1', name: 'ws', focused: true),
            ],
            tabs: const [
              TabSummary(
                tabId: 'w1:t1',
                workspaceId: 'w1',
                title: 'impl',
                focused: true,
              ),
            ],
            panes: [
              for (final item in harness.currentAttention)
                _pane(
                  paneId: item.paneId,
                  agent: item.agentKind,
                  agentStatus: 'blocked',
                ),
              for (int i = 0; i < 8; i++)
                _pane(paneId: 'w1:pw$i', agentStatus: 'working'),
            ],
            agents: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final double listTop = tester.getTopLeft(find.text('NEEDS YOU')).dy;
      // Before the scroll WORKING is not at the top: twelve 64 px rows push it below the fold,
      // where the lazy list may not even have built it yet, and if it is built it lies under
      // every NEEDS YOU row.
      final Finder working = find.text('WORKING');
      expect(
        working.evaluate().isEmpty ||
            tester.getTopLeft(working).dy > listTop + 12 * 64,
        isTrue,
        reason: 'WORKING must sit below the NEEDS YOU rows before the scroll',
      );

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -1000));
      await tester.pumpAndSettle();

      // WORKING pins where NEEDS YOU pinned, not one header height below it: the first
      // section's header left with its last row instead of stacking above the next header.
      expect(find.text('WORKING'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('WORKING')).dy,
        moreOrLessEquals(listTop, epsilon: 0.5),
      );
    },
  );

  testWidgets(
    'a standalone space draws no worktree row, and a tab row is never a target (R-31-06-19)',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);

      await _pumpWorkspaceAxis(tester, harness, _oneAgentSnapshot());

      // Two tiers only: the space header and one tab header; the worktree row is omitted for a
      // space that holds one non-linked workspace (R-31-06-27), so no worktree glyph is drawn.
      expect(_semanticsRow('herdr-relay, 1 pane'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is Icon && widget.icon == Symbols.tab_rounded,
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is Icon && widget.icon == Symbols.fork_right_rounded,
        ),
        findsNothing,
      );
      // The tab sub-header is never interactive: no GestureDetector wraps it, unlike the
      // collapsible space header.
      expect(
        find.ancestor(
          of: find.text('impl'),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'Priority: the last row of a section draws no divider; every other divider is inset space.4; '
    'Workspace: no pane row draws one (section 7.4, R-31-06-29)',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);

      final snapshot = Message.treeSnapshot(
        TreeSnapshot(
          workspaces: const [
            WorkspaceSummary(workspaceId: 'w1', name: 'ws', focused: true),
          ],
          tabs: const [
            TabSummary(
              tabId: 'w1:t1',
              workspaceId: 'w1',
              title: 'impl',
              focused: true,
            ),
          ],
          panes: [
            _pane(
              paneId: 'w1:p1',
              label: 'first-pane',
              title: 'first-pane command',
            ),
            _pane(
              paneId: 'w1:p2',
              label: 'last-pane',
              title: 'last-pane command',
              agent: 'codex',
            ),
          ],
          agents: const [
            AgentSummary(agentKind: 'claude', paneId: 'w1:p1', status: 'idle'),
            AgentSummary(agentKind: 'codex', paneId: 'w1:p2', status: 'idle'),
          ],
        ),
      );

      await tester.pumpWidget(MaterialApp(home: harness.build()));
      await tester.pumpAndSettle();
      harness.messages.add(snapshot);
      await tester.pumpAndSettle();

      final AppColor color = AppColor.of(
        tester.element(find.text('impl').first),
      );
      final Finder firstRow = _semanticsRow(
        'impl, Idle, ws, first-pane, claude',
      );
      final Finder lastRow = _semanticsRow('impl, Idle, ws, last-pane, codex');
      expect(firstRow, findsOneWidget);
      expect(lastRow, findsOneWidget);

      final Finder firstDivider = find.descendant(
        of: firstRow,
        matching: _rowDividers(color),
      );
      expect(firstDivider, findsOneWidget);
      expect(
        tester.getTopLeft(firstDivider).dx - tester.getTopLeft(firstRow).dx,
        AppSpace.space4,
      );
      expect(
        find.descendant(of: lastRow, matching: _rowDividers(color)),
        findsNothing,
      );
      // In `Priority` grouping the row is not indented, so its state bar sits at the row's own
      // leading edge, which is the list's edge (R-03-100; the Workspace-axis bar is measured in
      // the ladder test above).
      expect(
        tester
            .getTopLeft(
              find.descendant(of: firstRow, matching: find.byType(StatusBar)),
            )
            .dx,
        tester.getTopLeft(firstRow).dx,
      );

      await tester.tap(find.text('Workspace'));
      await tester.pumpAndSettle();
      expect(_rowDividers(color), findsNothing);
    },
  );

  testWidgets(
    'Priority names the task, preserves unread weight, and speaks full identity (R-03-124)',
    (tester) async {
      final workspace = 'very-long-workspace-name-' * 12;
      final harness = _Harness(
        currentAttention: [
          _attention(
            paneId: 'w1:p1',
            tabId: 'w1:t1',
            agentKind: 'omp',
            at: null,
          ),
        ],
      );
      addTearDown(harness.dispose);
      final semantics = tester.ensureSemantics();
      await _pumpLoaded(
        tester,
        harness,
        Message.treeSnapshot(
          TreeSnapshot(
            workspaces: [
              WorkspaceSummary(
                workspaceId: 'w1',
                name: workspace,
                focused: true,
              ),
            ],
            tabs: const [
              TabSummary(
                tabId: 'w1:t1',
                workspaceId: 'w1',
                title: 'Asset Pipeline Parity',
                focused: true,
              ),
              TabSummary(
                tabId: 'w1:t2',
                workspaceId: 'w1',
                title: '',
                focused: false,
              ),
            ],
            panes: [
              _pane(
                paneId: 'w1:p1',
                label: 'pane W',
                agent: 'omp',
                agentStatus: 'blocked',
              ),
              _pane(
                paneId: 'w1:p2',
                tabId: 'w1:t2',
                label: 'fallback pane',
                agent: 'omp',
                agentStatus: 'done',
              ),
            ],
            agents: const [],
          ),
        ),
      );
      final title = find.text('Asset Pipeline Parity');
      expect(
        tester.widget<Text>(title).style!.fontWeight,
        AppType.bodyStrong.fontWeight,
      );
      expect(
        tester.widget<Text>(find.text('fallback pane')).style!.fontWeight,
        AppType.body.fontWeight,
      );
      expect(find.text('…\u2009›\u2009pane W · omp'), findsOneWidget);
      expect(find.text('…\u2009›\u2009fallback pane · omp'), findsOneWidget);
      expect(find.text('omp'), findsNothing);
      expect(
        find.bySemanticsLabel(
          'Asset Pipeline Parity, Blocked, $workspace, pane W, omp',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'fallback pane, Done, $workspace, fallback pane, omp',
        ),
        findsOneWidget,
      );
      harness.attention.add([]);
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(title).style!.fontWeight,
        AppType.body.fontWeight,
      );
      expect(find.text('Blocked'), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets('Priority keeps two lines while Workspace puts kind, pane, state, and age on one baseline '
      '(R-03-115, 2026-09-10)', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);

    await _pumpLoaded(
      tester,
      harness,
      Message.treeSnapshot(
        TreeSnapshot(
          workspaces: const [
            WorkspaceSummary(workspaceId: 'w1', name: 'ws', focused: true),
          ],
          tabs: const [
            TabSummary(
              tabId: 'w1:t1',
              workspaceId: 'w1',
              title: 'impl',
              focused: true,
            ),
          ],
          panes: [
            _pane(paneId: 'w1:p1', label: 'aged', agentStatus: 'working'),
            _pane(
              paneId: 'w1:p2',
              label: 'ageless',
              agent: 'codex',
              agentStatus: 'working',
            ),
          ],
          agents: const [
            // Days old, so the age reads `Nd` for the whole test day.
            AgentSummary(
              agentKind: 'claude',
              paneId: 'w1:p1',
              status: 'working',
              statusAt: '2026-01-01T00:00:00Z',
            ),
          ],
        ),
      ),
    );

    // `getDistanceToBaseline` is a layout-phase API; the dry baseline at the box's own laid-out
    // size is the same number and may be read from a test.
    double baselineOf(Finder finder) {
      final RenderBox box = tester.renderObject(finder);
      return tester.getTopLeft(finder).dy +
          box.getDryBaseline(
            BoxConstraints.tight(box.size),
            TextBaseline.alphabetic,
          )!;
    }

    const String sep = '\u2009\u203A\u2009';
    final Finder aged = find.byWidgetPredicate(
      (Widget widget) =>
          widget is Semantics &&
          (widget.properties.label ?? '').startsWith(
            'impl, Working, ws, aged, claude, ',
          ),
    );
    final Finder ageless = _semanticsRow('impl, Working, ws, ageless, codex');
    expect(aged, findsOneWidget);
    expect(ageless, findsOneWidget);

    final Finder status = find.descendant(
      of: aged,
      matching: find.text('Working'),
    );
    final Finder age = find.descendant(
      of: aged,
      matching: find.textContaining(RegExp(r'^\d+d$')),
    );
    final Finder kind = find.descendant(of: aged, matching: find.text('impl'));
    final Finder crumb = find.descendant(
      of: aged,
      matching: find.text('ws${sep}aged · claude'),
    );
    expect(age, findsOneWidget);

    // One right edge for the word and the age, at the row's `space.4` trailing inset.
    expect(
      tester.getTopRight(age).dx,
      moreOrLessEquals(tester.getTopRight(status).dx, epsilon: 0.01),
    );
    expect(
      tester.getTopRight(aged).dx - tester.getTopRight(status).dx,
      AppSpace.space4,
    );
    // The state shares the task title baseline. The age shares the breadcrumb baseline.
    expect(
      baselineOf(status),
      moreOrLessEquals(baselineOf(kind), epsilon: 0.01),
    );
    expect(baselineOf(age), moreOrLessEquals(baselineOf(crumb), epsilon: 0.01));
    // The age is not part of the breadcrumb run: the breadcrumb ends `space.3` before it.
    expect(
      tester.getTopLeft(age).dx - tester.getTopRight(crumb).dx,
      moreOrLessEquals(AppSpace.space3, epsilon: 0.01),
    );

    // No age: the word stays on line one, in the same column.
    final Finder agelessStatus = find.descendant(
      of: ageless,
      matching: find.text('Working'),
    );
    final Finder agelessKind = find.descendant(
      of: ageless,
      matching: find.text('impl'),
    );
    expect(
      baselineOf(agelessStatus),
      moreOrLessEquals(baselineOf(agelessKind), epsilon: 0.01),
    );
    expect(
      tester.getTopRight(agelessStatus).dx,
      moreOrLessEquals(tester.getTopRight(status).dx, epsilon: 0.01),
    );
    await tester.tap(find.text('Workspace'));
    await tester.pumpAndSettle();

    final Finder workspaceAged = find.byWidgetPredicate(
      (Widget widget) =>
          widget is Semantics &&
          (widget.properties.label ?? '').startsWith('claude, Working, aged, '),
    );
    final Finder workspaceKind = find.descendant(
      of: workspaceAged,
      matching: find.text('claude'),
    );
    final Finder workspacePane = find.descendant(
      of: workspaceAged,
      matching: find.text('aged'),
    );
    final Finder workspaceStatus = find.descendant(
      of: workspaceAged,
      matching: find.text('Working'),
    );
    final Finder workspaceAge = find.descendant(
      of: workspaceAged,
      matching: find.textContaining(RegExp(r'^[0-9]+d$')),
    );
    expect(tester.getSize(workspaceAged).height, AppSize.targetMin);
    for (final Finder text in <Finder>[
      workspacePane,
      workspaceStatus,
      workspaceAge,
    ]) {
      expect(
        baselineOf(text),
        moreOrLessEquals(baselineOf(workspaceKind), epsilon: 0.5),
      );
    }
    expect(
      tester.getTopLeft(workspacePane).dx -
          tester.getTopRight(workspaceKind).dx,
      moreOrLessEquals(AppSpace.space2, epsilon: 0.01),
    );
    expect(
      tester.getTopLeft(workspaceAge).dx -
          tester.getTopRight(workspaceStatus).dx,
      moreOrLessEquals(AppSpace.space2, epsilon: 0.01),
    );
    expect(
      tester
          .getSize(
            find.descendant(
              of: workspaceAged,
              matching: find.byType(StatusBar),
            ),
          )
          .height,
      tester.getSize(workspaceAged).height,
    );
  });

  testWidgets(
    'every Workspace pane row is 48 high, agent and shell alike (R-03-115, 2026-09-10)',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);

      await _pumpWorkspaceAxis(tester, harness, _hierarchySnapshot());

      final Finder agentRow = _semanticsRow('claude, Working, builder');
      final Finder titledShell = _semanticsRow('pane 2, zsh');
      final Finder labelledShell = _semanticsRow('Explorer');
      for (final Finder row in <Finder>[agentRow, titledShell, labelledShell]) {
        expect(tester.getSize(row).height, AppSize.targetMin);
      }
      // Rows under one tab touch (R-31-06-29), with no hidden gap from the old second line.
      expect(
        tester.getBottomLeft(agentRow).dy,
        tester.getTopLeft(titledShell).dy,
      );
      expect(
        tester.getBottomLeft(titledShell).dy,
        tester.getTopLeft(labelledShell).dy,
      );
      final Finder bar = find.descendant(
        of: agentRow,
        matching: find.byType(StatusBar),
      );
      expect(tester.getSize(bar).height, tester.getSize(agentRow).height);
    },
  );

  testWidgets(
    'two tabs of one worktree are separated by the group gap and a hairline from the '
    'tab glyph, and the second tab\'s pane rows hang off their own guide rule (R-03-057)',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);

      await _pumpWorkspaceAxis(
        tester,
        harness,
        Message.treeSnapshot(
          TreeSnapshot(
            workspaces: const [
              WorkspaceSummary(workspaceId: 'w1', name: 'ws', focused: true),
            ],
            tabs: const [
              TabSummary(
                tabId: 'w1:t1',
                workspaceId: 'w1',
                title: 'impl',
                focused: true,
              ),
              TabSummary(
                tabId: 'w1:t2',
                workspaceId: 'w1',
                title: 'bench',
                focused: false,
              ),
            ],
            panes: [
              _pane(paneId: 'w1:p1', label: 'builder'),
              _pane(
                paneId: 'w1:p2',
                tabId: 'w1:t2',
                title: 'cargo bench',
                agent: null,
                agentStatus: 'unknown',
              ),
            ],
            agents: const [],
          ),
        ),
      );

      final Finder lastRowOfImpl = _semanticsRow('claude, Idle, builder');
      final Finder benchTitle = find.text('bench');
      final Finder benchGlyph = find.byWidgetPredicate(
        (Widget widget) => widget is Icon && widget.icon == Symbols.tab_rounded,
      );
      // Between the last row of `impl` and the `bench` title: the group gap, the hairline and the
      // tab header's own top inset, so two groups sit further apart than two rows (2 x space.3).
      expect(
        tester.getTopLeft(benchTitle).dy -
            tester.getBottomLeft(lastRowOfImpl).dy,
        AppSpace.space3 + 1 + AppSpace.space3,
      );
      // The hairline starts at the tab glyph's leading edge and reaches the block's trailing
      // edge; the guide rule under each tab is the only other line and no row draws a divider.
      final Finder hairline = find.byWidgetPredicate(
        (Widget widget) => widget is SizedBox && widget.height == 1,
      );
      expect(hairline, findsOneWidget);
      expect(
        tester.getTopLeft(hairline).dx,
        tester.getTopLeft(benchGlyph.last).dx,
      );
      expect(
        tester.getTopRight(hairline).dx,
        tester.getTopRight(_semanticsRow('ws, 2 panes')).dx,
      );
      expect(
        _rowDividers(AppColor.of(tester.element(benchTitle))),
        findsNothing,
      );
    },
  );

  testWidgets(
    'every age on screen ticks once a second while the list is shown (R-03-056)',
    (tester) async {
      DateTime now = DateTime.utc(2026, 9, 9, 12, 0, 12);
      final harness = _Harness();
      addTearDown(harness.dispose);

      // The same tree shape as the hidden-tab step below, so the flip updates one element.
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: TickerMode(
              enabled: true,
              child: harness.build(now: () => now),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      harness.messages.add(
        Message.treeSnapshot(
          TreeSnapshot(
            workspaces: const [
              WorkspaceSummary(workspaceId: 'w1', name: 'ws', focused: true),
            ],
            tabs: const [
              TabSummary(
                tabId: 'w1:t1',
                workspaceId: 'w1',
                title: 'impl',
                focused: true,
              ),
            ],
            panes: [
              _pane(paneId: 'w1:p1', label: 'aged', agentStatus: 'working'),
              _pane(paneId: 'w1:p2', label: 'ageless'),
            ],
            agents: const [
              AgentSummary(
                agentKind: 'claude',
                paneId: 'w1:p1',
                status: 'working',
                statusAt: '2026-09-09T12:00:00Z',
              ),
              AgentSummary(
                agentKind: 'claude',
                paneId: 'w1:p2',
                status: 'idle',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('12s'), findsOneWidget);

      // One tick of the screen's clock: the aged row redraws with the new age and the row with
      // no time still draws none.
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('13s'), findsOneWidget);
      expect(
        _semanticsRow('impl, Working, ws, aged, claude, 13s'),
        findsOneWidget,
      );
      expect(
        _semanticsRow('impl, Working, ws, aged, claude, 13s'),
        findsOneWidget,
      );
      expect(find.text('12s'), findsNothing);
      expect(_semanticsRow('impl, Idle, ws, ageless, claude'), findsOneWidget);

      // A hidden tab (the shell's inactive branch) ticks nothing.
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: TickerMode(
              enabled: false,
              child: harness.build(now: () => now),
            ),
          ),
        ),
      );
      await tester.pump();
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('13s'), findsOneWidget);
      expect(find.text('14s'), findsNothing);
    },
  );
}
