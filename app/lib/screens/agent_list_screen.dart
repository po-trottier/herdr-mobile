/// The agent list, the app's landing screen for a paired computer (Phase 18, `WP-18-b`), drawn
/// from `docs/31-mockups/06-agent-list.md` at route `/hosts/:hostId/agents`
/// (`docs/30-ux-spec.md` row 06, R-31-06-01). "Which agent needs me" is the one question this
/// screen answers, with two grouping axes over one list (`docs/30-ux-spec.md` R-30-406).
///
/// This file owns no route: `app/lib/routing.dart` (`WP-12-b`, not this package's `Paths.`
/// line) wires `/hosts/:hostId/agents` to this widget on request, and supplies this screen's
/// constructor arguments from whatever provider owns the live `RelayConnection` and the
/// app-session `AgentStatusService` — mirroring `device_list_screen.dart`'s own "a caller
/// adapts its own outcome" idiom (R-90-016, R-90-024).
///
/// **Header block, not a native app bar.** R-32-510 defines the app bar purely by token
/// (`color.bg.base`, a `color.border.strong` bottom edge), not by a native component mandate —
/// the same custom-widget pattern `app_strip.dart`/`app_list_row.dart`/`app_section_header.dart`
/// already use. This file builds its own header Row plus [_GroupingStrip] rather than a native
/// `AppBar`/`CupertinoNavigationBar`, so the single hairline of R-32-582 can move between the
/// header row and the strip as the strip appears and disappears, without juggling two different
/// native "bottom widget" APIs across platforms.
///
/// **The `Workspace` axis is a list of space blocks** (decided 2026-09-04 by the product owner,
/// R-31-06-27 to R-31-06-31): one raised card per space (`color.bg.raised`, a
/// `color.border.subtle` hairline, `radius.md`, inset `space.4` from the screen edge, `space.6`
/// apart), holding three tiers that read apart at a glance (R-03-057, 2026-09-09, after two
/// rounds that changed spacing alone): the space header as a `color.bg.high` band
/// ([ChromeListRow.expand]), a glyph-led tab header with its pane rows hung off a guide rule
/// ([_TabGroup]), and the pane rows themselves, with the worktree row ([_WorktreeRow]) between
/// the first two where a linked worktree needs naming; every text edge one `space.4` step in
/// from the tier above ([_spaceNameEdge]). No header pins on this axis: Flutter stacks pinned
/// persistent headers under each other, so a long list piled every scrolled-past workspace
/// header at the top; the block surface carries the membership while the list scrolls instead.
/// The `Priority` axis keeps its pinned upper-case headers (R-32-569) and scopes each pin to its
/// own section with a `SliverMainAxisGroup`, so those headers never stack either
/// ([_PriorityList]). Every pane of the tree is listed, agent or not (R-31-06-14): a shell pane
/// draws as [_ShellRowContent]. The axis opens with the pane search of R-31-06-30
/// ([_SearchField], the platform's own search component, decided 2026-09-08): the tree screen's
/// search moved here with the rest of the browser, and `AgentListService.setSearch` does the
/// narrowing.
///
/// **Live ages, one mark per fact.** Every age ticks once a second through [_AgeClock] while the
/// screen is shown (R-03-056, R-31-06-32), and only the rows that show one redraw. An agent row
/// carries the status as the leading state bar in the status hue beside the status word
/// (R-03-100), and the unread state as weight and wash: `type.body.strong` on the agent kind
/// and the `color.accent.soft` fill (R-03-058, R-31-06-33). No second bar, no dot.
///
/// **Reveal-then-tap.** The `Mark as seen` action (R-30-504, R-31-06-20) follows the pattern
/// `WP-18-a` (`host_list_screen.dart`) settled for `Forget`: one `SlidableAutoCloseBehavior`
/// ancestor, `Slidable.groupTag` shared by every row, `dragDismissible: false`, and an outer
/// `Semantics.customSemanticsActions` entry naming the action (R-32-580, R-30-298). It differs
/// from `Forget` in one way this file's own [_PaneRowTile] reflects: it is not destructive, so
/// the action panel carries the reveal only on a row that already needs attention — a row with no
/// marker to clear gets no dead affordance, per this screen's own reading of R-31-06-20 alongside
/// `agent_status.dart`'s documented no-op `markSeen` on an unmarked pane.
///
/// **Known gaps, disclosed.** Two mockup states are not built here because neither is named by
/// this package's sixteen checkboxes (`docs/90-implementation-plan.md` §5.2 `WP-18-b`): the
/// `Host in use` banner (it freezes every row's age at a Host-reported capture time and routes a
/// tap to "the last painted grid", both of which need a terminal cache this package does not
/// own) and the `Stale` progress line (R-32-511's live-dot threshold has no owning constant on
/// this package's `Needs.` line). Both remain open for a later package.
library;

import 'dart:async' show StreamSubscription, Timer, unawaited;
import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart'
    show
        BuildContext,
        CupertinoPageScaffold,
        CupertinoSearchTextField,
        CupertinoSlidingSegmentedControl,
        Widget;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/widgets.dart'
    show
        Align,
        Alignment,
        AlwaysScrollableScrollPhysics,
        AsyncSnapshot,
        Border,
        BorderRadius,
        BorderSide,
        BoxConstraints,
        BoxDecoration,
        Center,
        ClipRRect,
        Color,
        ColoredBox,
        Column,
        ConstrainedBox,
        Container,
        CrossAxisAlignment,
        CustomScrollView,
        DecoratedBox,
        DefaultTextStyle,
        Directionality,
        EdgeInsets,
        EdgeInsetsDirectional,
        Expanded,
        Icon,
        IgnorePointer,
        InheritedNotifier,
        Key,
        LayoutBuilder,
        Listener,
        MainAxisAlignment,
        MainAxisSize,
        MediaQuery,
        Opacity,
        Padding,
        PlaceholderAlignment,
        PointerDownEvent,
        PointerEvent,
        Positioned,
        PositionedDirectional,
        Row,
        SafeArea,
        Semantics,
        SizedBox,
        SliverChildBuilderDelegate,
        SliverFillRemaining,
        SliverList,
        SliverMainAxisGroup,
        SliverPadding,
        SliverPersistentHeader,
        SliverPersistentHeaderDelegate,
        SliverToBoxAdapter,
        Stack,
        State,
        StatefulWidget,
        StatelessWidget,
        StreamBuilder,
        Text,
        TextBaseline,
        TextDirection,
        TextOverflow,
        TextPainter,
        TextScaler,
        TextSpan,
        TextStyle,
        TickerMode,
        TickerProviderStateMixin,
        ValueChanged,
        ValueKey,
        ValueNotifier,
        VoidCallback,
        Widget,
        WidgetSpan;
import 'package:flutter_slidable/flutter_slidable.dart'
    show
        ActionPane,
        CustomSlidableAction,
        ScrollMotion,
        Slidable,
        SlidableAutoCloseBehavior;
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart'
    show
        FloatingActionButton,
        RefreshIndicator,
        Scaffold,
        SearchAnchor,
        SearchController,
        Tab,
        TabBar,
        TabBarView,
        TabController,
        kTabScrollDuration;

import '../core/result/result.dart' show Err, Ok, Result;
import '../models/message.dart';
import '../models/messages/agent_status_kind.dart';
import '../services/agent_list.dart';
import '../services/agent_status.dart' show AttentionItem;
import '../services/notifications.dart' show ageTickPeriod;
import '../services/relay.dart'
    show RelayConnected, RelayConnectionState, RelayNotConnectedException;
import '../widgets/app_ground.dart' show EmptyMark;
import '../widgets/app_list_row.dart';
import '../widgets/app_section_header.dart';
import '../widgets/app_strip.dart';
import '../widgets/app_text_button.dart';
import '../widgets/eyebrow.dart';
import '../widgets/ground_grid.dart' show GroundGrid;
import '../widgets/status_bar.dart' show BarState, StatusBar;
import '../widgets/theme/app_color.dart';
import '../widgets/theme/app_radius.dart';
import '../widgets/theme/app_size.dart';
import '../widgets/theme/app_space.dart';
import '../widgets/theme/app_type.dart';
import '../widgets/theme/chrome_icon_action.dart';
import '../widgets/theme/chrome_list_row.dart';
import '../widgets/theme/chrome_loading_delay.dart';
import '../widgets/theme/chrome_tonal_button.dart';
import '../widgets/treatments.dart';

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

/// The one revealed action's label (callout 17), `type.caption` under its icon (R-32-576).
const String _markSeenLabel = 'Mark as seen';

/// The breadcrumb separator, `›` (U+203A) with a hair space (U+200A) on each side, in one text
/// run, per R-32-572.
const String _breadcrumbSeparator = '\u2009\u203A\u2009';

/// `Slidable.groupTag` shared by every row on this screen, so opening one closes any other
/// (R-30-299, R-31-06-05's pending-reorder companion).
const String _slidableGroupTag = 'agent_list';

/// `opacity.disabled` (R-32-502): the create control while the link is down, the ink unchanged
/// (R-32-331). The one control this screen dims itself; a `ChromeIconAction` dims its own.
const double _opacityDisabled = 0.38;

/// The end padding of both axes (R-03-109, corrected 2026-09-10 by the product owner): the
/// create button's box plus `space.4`, so an overflowing list scrolls its last row clear of the
/// button. It is the scroll view's own end padding, never a reserved band: a list that fits the
/// screen ends at its last row, because the padding sits in the viewport's remainder on the
/// same plain `color.bg.base` and paints nothing, and it comes into view only once the list has
/// scrolled that far. The band the owner rejected on 2026-09-09 was this padding on the ground
/// grid, which R-03-107 took off a screen with content the same day.
const double _createClearance = AppSize.buttonCreate + AppSpace.space4;

/// A pane row's vertical inset: `space.3` above and below its text lines, with
/// `size.target.min` as the floor, so one line lands on 48 and two lines on 64. Since
/// 2026-09-10, per R-03-115, every pane row in a Workspace block uses one line, agent and shell
/// alike. Priority agent rows and the skeleton rows of [_SkeletonList] keep two lines.
const double _rowVerticalInset = AppSpace.space3;

class AgentListScreen extends StatefulWidget {
  const AgentListScreen({
    super.key,
    required this.hostId,
    required this.hostName,
    required this.messages,
    required this.connectionState,
    required this.initialConnectionState,
    required this.send,
    required this.unseenAttention,
    required this.currentAttention,
    required this.onMarkSeen,
    required this.onNotePaneOpened,
    this.alertsOff = false,
    this.onOpenPane,
    this.onHostChip,
    this.onOpenAlertsSettings,
    this.onOpenDiagnostics,
    this.onCreate,
    this.onOpenStatusColours,
    this.now = DateTime.now,
  });

  /// This computer's `host_id` (R-11-130), used to scope [AgentListService]'s per-Host
  /// persistence (R-31-06-12).
  final String hostId;

  /// `host_name` from `host_info` (R-11-130), the host chip's text (callout 1).
  final String hostName;

  final Stream<Message> messages;
  final Stream<RelayConnectionState> connectionState;

  /// The link state at the moment this screen was built, because [connectionState] has no
  /// replay: without it the first frame would draw the create control enabled on a dead link
  /// until the stream's next event. Mirrors `terminal_screen.dart`'s own parameter.
  final RelayConnectionState initialConnectionState;

  final AgentListMessageSender send;

  /// `WP-19-a`'s app-session unseen-attention stream (`agent_status.dart`); this screen's
  /// `Needs.` line names only its declarations. Mirrors `host_list_screen.dart`'s (`WP-18-a`)
  /// own `unseenAttention`/`currentAttention` parameters — the seam is testable against a bare
  /// `StreamController`, with no `AgentStatusService` to construct.
  final Stream<List<AttentionItem>> unseenAttention;

  /// The value of `AgentStatusService.currentAttention` at the moment this screen was built —
  /// the first paint, before [unseenAttention] emits again.
  final List<AttentionItem> currentAttention;

  /// `Mark as seen` (R-30-504, R-31-06-20): the caller's `AgentStatusService.markSeen`.
  final void Function(String paneId) onMarkSeen;

  /// Row tap (R-30-503, R-31-06-06): the caller's `AgentStatusService.notePaneOpened`. This
  /// widget always calls it first, regardless of whether [onOpenPane] is also supplied.
  final void Function(String paneId) onNotePaneOpened;

  /// True only while the operating system reports the notification permission as denied
  /// (R-31-06-21). This screen does not own `notifications.dart`, so a caller supplies the
  /// current value; it MUST NOT ask for the permission itself.
  final bool alertsOff;

  /// Row tap (R-30-503, R-31-06-06): the caller routes to `/hosts/:hostId/panes/:paneId`. This
  /// widget always calls [onNotePaneOpened] first, regardless of whether a caller is supplied.
  final void Function(String paneId)? onOpenPane;

  /// Host chip tap: routes to `/hosts` (callout 1). `null` is a deliberate no-op (R-90-016).
  final VoidCallback? onHostChip;

  /// Alerts-off marker tap: routes to `/settings/notifications` (callout 12).
  final VoidCallback? onOpenAlertsSettings;

  /// Offline strip tap: routes to `/hosts/:hostId/diagnostics` (R-30-806).
  final VoidCallback? onOpenDiagnostics;

  /// The create control (R-03-109, corrected 2026-09-10; R-31-06-22): Material's
  /// `FloatingActionButton` on both platforms, `space.4` from the trailing edge and the bottom
  /// of the body, the `add` glyph spoken `New`; `routing.dart`'s `_openCreateSheet` supplies the
  /// menu of `docs/31-mockups/17-create.md`. `null` draws no button at all (R-90-016); a
  /// non-null callback still draws it, disabled, while the link is down (R-30-807, amended
  /// 2026-09-08). The `New` app bar action of 2026-09-09 left with the correction.
  final VoidCallback? onCreate;

  /// The `Status colours` action (R-03-112, R-31-06-34): the `info` glyph in the app bar, first
  /// of its actions; the caller pushes the legend of `docs/31-mockups/20-status-legend.md`.
  /// `null` draws no action (R-90-016).
  final VoidCallback? onOpenStatusColours;

  /// The clock every age of callout 8 is measured against, read once per [ageTickPeriod] tick
  /// (R-03-056); a test pins it. Mirrors `notifications_screen.dart`'s own parameter.
  final DateTime Function() now;

  /// The pane search (R-31-06-30, R-03-102), for an end-to-end test: on iOS the
  /// `CupertinoSearchTextField` under the app bar; on Android the search action in the app bar
  /// that opens the Material search view, because `SearchAnchor` builds the view's own field
  /// and takes no key for it (type into `SearchBar` once the view is open).
  static const Key searchFieldKey = ValueKey<String>('agent_list_search');

  @override
  State<AgentListScreen> createState() => _AgentListScreenState();
}

enum _LiveConnection { connected, offline }

class _AgentListScreenState extends State<AgentListScreen>
    with TickerProviderStateMixin {
  late final AgentListService _service;
  StreamSubscription<AgentListView>? _viewSub;
  StreamSubscription<RelayConnectionState>? _connectionSub;
  AgentListView? _view;

  /// The pane search text (R-31-06-30). Owned here, not by the field, so the text survives an
  /// axis switch and a rebuild; cleared with the screen, never persisted. A `SearchController`
  /// on both platforms: on Android it opens and closes the Material search view of R-03-102,
  /// on iOS it is the plain `TextEditingController` the Cupertino field takes.
  final SearchController _searchController = SearchController();

  /// R-31-06-05: while a finger is down anywhere in the list, an emitted [AgentListView] is
  /// held in [_pendingView] rather than applied, so a row already visible never reorders under
  /// a touch that has not yet lifted. Flushed on pointer up/cancel.
  bool _holdUpdates = false;
  AgentListView? _pendingView;
  late _LiveConnection _connection;
  bool _showSkeleton = false;
  Timer? _skeletonTimer;
  String? _loadError;

  /// R-03-056 (2026-09-09): every age on screen ticks. One [ageTickPeriod] timer, the cadence
  /// the notifications list runs too (`notifications.dart`), moves [_clock] once a second; each
  /// agent row that shows an age depends on it through [_AgeClock] and redraws alone, so a tick
  /// never rebuilds the list, a header or a row with no time. Cancelled with the screen.
  late final ValueNotifier<DateTime> _clock = ValueNotifier<DateTime>(
    widget.now(),
  );
  Timer? _ageTimer;

  /// `TickerMode.of(context)` at the last build: `false` while this screen is the shell's
  /// offstage tab (go_router wraps an inactive branch in `TickerMode(enabled: false)`), so the
  /// tick moves nothing there. The mode change itself rebuilds the screen when the tab returns.
  bool _onScreen = true;

  /// R-03-108 (2026-09-09): on Android one controller drives both the `TabBar` of
  /// [_GroupingStrip] and the `TabBarView` body, so the `Priority` / `Workspace` switch tracks
  /// the finger and hands its velocity to the page physics. Its index is the axis on screen: a
  /// tab tap or a settled page moves it and [_onTabsChanged] tells the service; [_showView]
  /// moves it when the service's axis changes on its own (the persisted axis of R-31-06-12
  /// arriving), under [_syncingTabs] so that move never feeds back into the service. Built in
  /// [didChangeDependencies], because its one animation duration follows
  /// `MediaQuery.disableAnimationsOf` (R-32-606) and a rebuilt controller keeps the index; the
  /// mixin is the multi-ticker one for that reason. iOS never reads it: the segmented control
  /// switches with the platform's own transition.
  TabController? _tabs;
  bool _syncingTabs = false;

  @override
  void initState() {
    super.initState();
    _service = AgentListService(
      messages: widget.messages,
      connectionState: widget.connectionState,
      send: widget.send,
      unseenAttention: widget.unseenAttention,
      currentAttention: widget.currentAttention,
      hostId: widget.hostId,
    );
    _view = _service.currentView;
    // The search follows the controller, not the field's `onChanged`: the Material search
    // view's own clear button (`SearchAnchor`'s `_ViewContent`, `_controller.clear()`) sets
    // the text without firing `viewOnChanged`, so a person who tapped × kept seeing
    // `No pane matches "<old text>"` (2026-09-11). One listener covers typing, the clear
    // button and every programmatic clear; `setSearch` drops an unchanged value itself.
    _searchController.addListener(_onSearchTextChanged);
    _connection = widget.initialConnectionState is RelayConnected
        ? _LiveConnection.connected
        : _LiveConnection.offline;
    _viewSub = _service.view.listen((AgentListView view) {
      if (!mounted) return;
      if (_holdUpdates) {
        _pendingView = view;
      } else {
        _showView(view);
      }
    });
    _connectionSub = widget.connectionState.listen(_onConnectionState);
    _skeletonTimer = Timer(ChromeLoadingDelay.skeleton, () {
      if (mounted && !_service.hasLoaded) {
        setState(() => _showSkeleton = true);
      }
    });
    _ageTimer = Timer.periodic(ageTickPeriod, (_) {
      if (mounted && _onScreen) _clock.value = widget.now();
    });
    unawaited(_initialLoad());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final Duration duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : kTabScrollDuration;
    final TabController? previous = _tabs;
    if (previous?.animationDuration == duration) return;
    _tabs = TabController(
      length: AgentListAxis.values.length,
      initialIndex: previous?.index ?? _service.axis.index,
      animationDuration: duration,
      vsync: this,
    )..addListener(_onTabsChanged);
    // The `TabBar` and the `TabBarView` let go of the old controller in their own
    // `didUpdateWidget`, which tolerates a disposed one, the way `DefaultTabController` swaps
    // its controller on the same change.
    previous?.dispose();
  }

  /// A tab tap or a settled page: the controller's index is the axis the person chose.
  void _onTabsChanged() {
    if (_syncingTabs) return;
    unawaited(_service.setAxis(AgentListAxis.values[_tabs!.index]));
  }

  /// Applies an emitted view, and moves the controller when the service's axis changed on its
  /// own. A change under way from a tap is left alone: the view that tap caused is on its way.
  void _showView(AgentListView view) {
    setState(() => _view = view);
    final TabController? tabs = _tabs;
    if (tabs == null || tabs.index == view.axis.index || tabs.indexIsChanging) {
      return;
    }
    _syncingTabs = true;
    tabs.index = view.axis.index;
    _syncingTabs = false;
  }

  Future<void> _initialLoad() async {
    final Result<void> result = await _refresh();
    if (!mounted) return;
    if (result is Err<void> && !_service.hasLoaded) {
      setState(() => _loadError = result.message);
    } else {
      setState(() => _loadError = null);
    }
  }

  /// `relay.dart`'s `send` throws [RelayNotConnectedException] on a dead link — "an expected
  /// operational condition a caller can catch", its own doc comment; this screen is that
  /// caller. The throw resolves as the service's own dropped-link `Err` wording
  /// (`agent_list.dart`'s connection-drop completion, duplicated per R-41-042 rung 1): the
  /// offline strip already reports the link (R-30-805), and the `Error` block's `Try again`
  /// stays the recovery path when nothing has loaded yet.
  Future<Result<void>> _refresh() async {
    try {
      return await _service.refresh();
    } on RelayNotConnectedException {
      return const Err('read the agent list: the connection dropped');
    }
  }

  Future<void> _retry() => _initialLoad();

  /// The `RefreshIndicator`/`CupertinoSliverRefreshControl` gesture. A failure here is silent
  /// when content already loaded (R-30-003: a spinner MUST NOT cover a screen with real data);
  /// the offline strip already reports a dropped link.
  Future<void> _pullToRefresh() async {
    final Result<void> result = await _refresh();
    if (!mounted) return;
    if (result is Err<void> && !_service.hasLoaded) {
      setState(() => _loadError = result.message);
    } else if (result is Ok<void>) {
      setState(() => _loadError = null);
    }
  }

  @override
  void dispose() {
    unawaited(_viewSub?.cancel());
    unawaited(_connectionSub?.cancel());
    _skeletonTimer?.cancel();
    _ageTimer?.cancel();
    _clock.dispose();
    _searchController
      ..removeListener(_onSearchTextChanged)
      ..dispose();
    _tabs?.dispose();
    _service.dispose();
    super.dispose();
  }

  void _onConnectionState(RelayConnectionState state) {
    final _LiveConnection next = state is RelayConnected
        ? _LiveConnection.connected
        : _LiveConnection.offline;
    if (mounted) setState(() => _connection = next);
  }

  void _openPane(String paneId) {
    widget.onNotePaneOpened(paneId); // R-30-503, R-31-06-06.
    widget.onOpenPane?.call(paneId);
  }

  void _markSeen(String paneId) => widget.onMarkSeen(paneId); // R-30-504.

  void _onPointerDown(PointerDownEvent event) => _holdUpdates = true;

  void _onPointerUp(PointerEvent event) {
    _holdUpdates = false;
    final AgentListView? pending = _pendingView;
    if (pending != null) {
      _pendingView = null;
      if (mounted) _showView(pending);
    }
  }

  /// The iOS segmented control chose an axis; on Android the controller carries the choice
  /// ([_onTabsChanged]).
  void _onAxisChanged(AgentListAxis axis) => unawaited(_service.setAxis(axis));

  /// The Android search view closed (R-03-102): its results lived inside the view, so the list
  /// behind it shows the whole tree again, and the next open starts blank.
  void _onSearchViewClosed() => _searchController.clear();

  void _onSearchTextChanged() => _service.setSearch(_searchController.text);

  /// A row tapped inside the Android search view: the view closes first, so the pane opens
  /// over the list and not over the view.
  void _openPaneFromSearch(String paneId) {
    _searchController.closeView(null);
    _openPane(paneId);
  }

  void _onToggleSpace(String spaceKey) =>
      unawaited(_service.toggleCollapsed(spaceKey));

  @override
  Widget build(BuildContext context) {
    _onScreen = TickerMode.valuesOf(context).enabled;
    final AppColor color = AppColor.of(context);
    final AgentListView? view = _view;
    final bool showStrip = _service.hasLoaded && view != null && !view.isEmpty;

    final Widget headerRow = DecoratedBox(
      decoration: BoxDecoration(
        color: color.bgBase,
        border: showStrip
            ? null
            : Border(
                bottom: BorderSide(
                  color: color.borderStrong,
                  width: AppBorder.hairline,
                ),
              ),
      ),
      child: SizedBox(
        height: AppSize.appBar,
        child: Padding(
          // The host chip carries `space.2` of its own inside its pressed fill, so the row
          // inset is `space.2` at the leading edge and the name still starts at `space.4`.
          padding: const EdgeInsets.only(
            left: AppSpace.space2,
            right: AppSpace.space4,
          ),
          child: Row(
            children: <Widget>[
              _HostChip(hostName: widget.hostName, onTap: widget.onHostChip),
              const Expanded(child: SizedBox.shrink()),
              ..._trailingControls(searchable: showStrip),
            ],
          ),
        ),
      ),
    );

    final Widget content = Column(
      children: <Widget>[
        headerRow,
        // R-03-102 (2026-09-09): on iOS the pane search sits in the navigation bar area, under
        // the bar at the platform's own inset, while the `Workspace` axis is shown; on Android
        // it is the search action of [_trailingControls].
        if (_isIos && showStrip && view.axis == AgentListAxis.workspace)
          ColoredBox(
            color: color.bgBase,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(
                start: AppSpace.space4,
                end: AppSpace.space4,
                top: AppSpace.space2,
                bottom: AppSpace.space2,
              ),
              child: CupertinoSearchTextField(
                key: AgentListScreen.searchFieldKey,
                controller: _searchController,
                placeholder: _searchPlaceholder,
              ),
            ),
          ),
        if (showStrip)
          // R-32-582 as R-03-059 leaves it (2026-09-09): the block's one hairline closes the
          // strip, drawn by [_GroupingStrip]; the header row above draws none.
          ColoredBox(
            color: color.bgBase,
            child: _GroupingStrip(
              axis: view.axis,
              onChanged: _onAxisChanged,
              tabs: _tabs!,
            ),
          ),
        if (_connection == _LiveConnection.offline)
          AppStrip(
            onTapDestination: widget.onOpenDiagnostics,
            child: const Treatment.warning(
              label: 'Offline. Showing what we last saw.',
            ),
          ),
        Expanded(
          child: Listener(
            onPointerDown: _onPointerDown,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerUp,
            child: _buildBody(color, view),
          ),
        ),
      ],
    );

    // R-03-107 (amended 2026-09-09): a screen with content paints plain `color.bg.base`, so the
    // body lays no grid and no paper; only an empty state takes the grid ([_emptyBody]).
    // [_AgeClock] stays the body's clock, above every row (R-03-056).
    final Widget safeContent = SafeArea(
      bottom: false,
      child: _AgeClock(notifier: _clock, child: content),
    );

    final Widget? createButton = _createButton();
    if (_isIos) {
      // R-03-109 (corrected 2026-09-10): the same floating button on iOS. The Cupertino
      // scaffold has no slot for it, so it floats over the body at Material's own place,
      // `space.4` from the trailing edge and from the bottom, above the connection strip and
      // the tab bar the shell lays under this screen, plus the bottom safe area when this
      // screen stands alone (R-33-039).
      return CupertinoPageScaffold(
        backgroundColor: color.bgBase,
        child: createButton == null
            ? safeContent
            : Stack(
                children: <Widget>[
                  Positioned.fill(child: safeContent),
                  PositionedDirectional(
                    end: AppSpace.space4,
                    bottom:
                        AppSpace.space4 + MediaQuery.paddingOf(context).bottom,
                    child: createButton,
                  ),
                ],
              ),
      );
    }
    return Scaffold(
      backgroundColor: color.bgBase,
      body: safeContent,
      floatingActionButton: createButton,
    );
  }

  /// The create control (R-31-06-22; R-03-109 corrected 2026-09-10 by the product owner):
  /// Material's `FloatingActionButton` on both platforms, the `add` glyph spoken `New`. Fill,
  /// ink, glyph size and the component's own shape come from `floatingActionButtonTheme` in
  /// `app.dart` (R-32-588). `null` [AgentListScreen.onCreate] draws none (R-90-016). While the
  /// link is down the button stays, disabled and dimmed to `opacity.disabled` (R-30-807,
  /// R-32-502); this wrapper carries the `enabled` state and the `New` label of R-30-717, and
  /// the offline strip carries the reason.
  Widget? _createButton() {
    if (widget.onCreate == null) return null;
    final bool connected = _connection == _LiveConnection.connected;
    return Semantics(
      button: true,
      enabled: connected,
      label: 'New',
      excludeSemantics: true,
      child: Opacity(
        opacity: connected ? 1 : _opacityDisabled,
        child: FloatingActionButton(
          onPressed: connected ? widget.onCreate : null,
          tooltip: 'New',
          child: const Icon(
            Symbols.add_rounded,
            fill: 0,
            weight: 400,
            grade: 0,
          ),
        ),
      ),
    );
  }

  /// The app bar actions of R-31-06-24 (amended 2026-09-09 per R-03-112, corrected 2026-09-10
  /// per R-03-109), in this order on both platforms: `Status colours` (the `info` glyph, which
  /// pushes the legend), the Android search action of R-03-102 while [searchable], then the
  /// alerts-off marker of callout 12. The create control is not here: it is the floating
  /// action button of [_createButton] on both platforms; the `New` action that stood in this
  /// bar for one day left with the correction. The search action is the M3 pattern: it opens
  /// `SearchAnchor`'s full-screen search view, whose field narrows the tree as the person
  /// types and whose body is [_SearchResults]. The attention badge left this bar on
  /// 2026-09-04: the `Notifications` destination badge carries that count now. The `Computer
  /// actions` control left it on 2026-09-09 (R-03-055): a plugin acts on a pane, so the pane
  /// action sheet of the terminal carries plugin actions, and this bar carries no plugin
  /// control. Every control is the [ChromeIconAction] of R-33-033's `App bar action` row
  /// (decided 2026-09-08), and two sit `space.1` apart, per R-32-510.
  List<Widget> _trailingControls({required bool searchable}) {
    final List<Widget> controls = <Widget>[
      if (widget.onOpenStatusColours != null)
        ChromeIconAction(
          icon: Symbols.info_rounded,
          label: 'Status colours',
          onPressed: widget.onOpenStatusColours,
        ),
      if (!_isIos && searchable)
        // The view's fill, edge and type come from `searchViewTheme` in `app.dart`; this
        // screen sets the placeholder and what the view holds, per R-32-598. The body is
        // [_SearchResults], which follows the service; the anchor's own suggestion list stays
        // empty, because a keystroke narrows the tree instead of listing suggestions.
        SearchAnchor(
          searchController: _searchController,
          viewHintText: _searchPlaceholder,
          viewOnClose: _onSearchViewClosed,
          // The view is a route above the screen (2026-09-09), so the screen's [_AgeClock]
          // does not reach it: the same clock wraps the view's rows, and their ages tick with
          // the axis's (R-03-056).
          viewBuilder: (Iterable<Widget> suggestions) => _AgeClock(
            notifier: _clock,
            child: _SearchResults(
              views: _service.view,
              initial: _view,
              onOpenPane: _openPaneFromSearch,
              onMarkSeen: _markSeen,
              onToggleSpace: _onToggleSpace,
            ),
          ),
          suggestionsBuilder: (
            BuildContext context,
            SearchController controller,
          ) => const <Widget>[],
          builder: (BuildContext context, SearchController controller) =>
              ChromeIconAction(
                key: AgentListScreen.searchFieldKey,
                icon: Symbols.search_rounded,
                label: _searchPlaceholder,
                onPressed: controller.openView,
              ),
        ),
      if (widget.alertsOff)
        ChromeIconAction(
          icon: Symbols.notifications_off_rounded,
          label: 'Alerts are off',
          onPressed: widget.onOpenAlertsSettings,
        ),
    ];
    return <Widget>[
      for (final (int index, Widget control) in controls.indexed) ...<Widget>[
        if (index > 0) const SizedBox(width: AppSpace.space1),
        control,
      ],
    ];
  }

  Widget _buildBody(AppColor color, AgentListView? view) {
    if (!_service.hasLoaded) {
      if (_loadError != null) {
        return _ErrorBlock(
          hostName: widget.hostName,
          text: _loadError!,
          onRetry: () => unawaited(_retry()),
        );
      }
      return _showSkeleton ? const _SkeletonList() : const SizedBox.shrink();
    }
    // R-31-06-14: `Priority` lists agents only, `Workspace` lists every pane, so each axis has
    // its own empty case; the strip stays whenever either axis has something to show. A tree
    // with nothing at all shows one empty block and no strip, on either platform.
    if (view == null || view.isEmpty) {
      return _refreshWrapper(child: _emptyBody(noun: 'agents'));
    }
    if (_isIos) {
      // The segmented control switches with the platform's own transition (R-03-108): one
      // axis body at a time, chosen by the service's axis.
      return switch (view.axis) {
        AgentListAxis.priority => _priorityBody(color, view),
        AgentListAxis.workspace => _workspaceBody(color, view),
      };
    }
    // R-03-108: on Android the two axes are the two pages of a `TabBarView` on the strip's own
    // controller, so a horizontal swipe tracks the finger and hands its velocity to the page
    // physics; the settled page becomes the service's axis through [_onTabsChanged]. A row's
    // own reveal (`Mark as seen`) wins a horizontal drag that starts on it, as inside any
    // Material tab page.
    return TabBarView(
      controller: _tabs,
      children: <Widget>[
        _priorityBody(color, view),
        _workspaceBody(color, view),
      ],
    );
  }

  Widget _priorityBody(AppColor color, AgentListView view) => _refreshWrapper(
    child: view.prioritySections.isEmpty
        ? _emptyBody(noun: 'agents')
        : _PriorityList(
            sections: view.prioritySections,
            color: color,
            onOpenPane: _openPane,
            onMarkSeen: _markSeen,
          ),
  );

  /// R-31-06-30: a search that matches nothing is not an empty computer; the list stays and
  /// says so inline. Only a tree with no workspace reaches the empty block.
  Widget _workspaceBody(AppColor color, AgentListView view) => _refreshWrapper(
    child: view.workspaceCount == 0
        ? _emptyBody(noun: 'panes')
        : _SpaceList(
            spaces: view.spaces,
            search: view.search,
            collapsed: view.collapsed,
            color: color,
            onOpenPane: _openPane,
            onMarkSeen: _markSeen,
            onToggleSpace: _onToggleSpace,
          ),
  );

  /// The empty block on the ground grid of R-03-107 with the mark behind it, the one place on
  /// this screen that paints the grid: `GroundGrid` fills the rest of the viewport, so its
  /// lines align to the body's top-left, and `EmptyMark` anchors the silhouette bottom-right.
  /// Inside a scroll view that always scrolls, so the pull-to-refresh gesture around it still
  /// works there. The sliver keeps the default `hasScrollBody`, which sizes the child to exactly
  /// the rest of the viewport without asking its intrinsic height: `EmptyMark` measures itself
  /// with a `LayoutBuilder`, which has none, and the block is three lines, so it never needs
  /// more.
  Widget _emptyBody({required String noun}) => CustomScrollView(
    physics: const AlwaysScrollableScrollPhysics(),
    slivers: <Widget>[
      SliverFillRemaining(
        child: GroundGrid(
          child: EmptyMark(
            child: _EmptyBlock(hostName: widget.hostName, noun: noun),
          ),
        ),
      ),
    ],
  );

  Widget _refreshWrapper({required Widget child}) =>
      RefreshIndicator(onRefresh: _pullToRefresh, child: child);
}

/// The screen's age clock (R-03-056), an [InheritedNotifier] so that only the widgets that read
/// [of] rebuild when the clock moves: an agent row with an age depends on it, and nothing else
/// on the screen does.
class _AgeClock extends InheritedNotifier<ValueNotifier<DateTime>> {
  const _AgeClock({
    required ValueNotifier<DateTime> super.notifier,
    required super.child,
  });

  static DateTime of(BuildContext context) {
    final _AgeClock? clock = context
        .dependOnInheritedWidgetOfExactType<_AgeClock>();
    assert(
      clock != null,
      'No _AgeClock above this row. Every tree that draws an agent row needs '
      'one: the screen body has it, and the Android search view of R-03-102 '
      'is a route above the screen, so its viewBuilder wraps its own.',
    );
    return clock!.notifier!.value;
  }
}

/// The native host control opens the computer list.
class _HostChip extends StatelessWidget {
  const _HostChip({required this.hostName, this.onTap});

  final String hostName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    return Semantics(
      button: onTap != null,
      label: '$hostName, choose computer',
      excludeSemantics: true,
      child: ChromeTonalButton(
        onPressed: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              hostName,
              style: AppType.heading.copyWith(color: color.fgPrimary),
            ),
            const SizedBox(width: AppSpace.space2),
            Icon(
              Symbols.expand_more_rounded,
              size: AppSize.iconMd,
              color: color.fgSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// The attention badge `(!) 1` on a space header (callout 14, R-32-518): never a filled pill, the
/// icon carries the hue, the count carries `color.fg.primary`, exact and uncapped (R-30-508).
class _AttentionBadge extends StatelessWidget {
  const _AttentionBadge({required this.count, required this.ink});

  final int count;

  /// The count's ink: `color.fg.primary`, or `color.fg.on_accent` while the header band the
  /// badge sits on is pressed to `color.accent.primary` (R-32-501's first case). The icon keeps
  /// its hue either way: the hue is the badge's meaning (R-32-518).
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    return Semantics(
      label: '$count needing attention',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.space2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Symbols.notifications_active_rounded,
              size: AppSize.iconSm,
              color: color.statusBlocked,
            ),
            const SizedBox(width: AppSpace.space1),
            Text('$count', style: AppType.microStrong.copyWith(color: ink)),
          ],
        ),
      ),
    );
  }
}

/// The grouping strip (section 7.26, callout 13): the platform's own view switcher (R-03-102,
/// decided 2026-09-09 by the product owner), `Priority` then `Workspace`. On Android a Material
/// `TabBar` of two primary tabs, full width under the app bar, its indicator, ink, type and
/// bottom divider from `tabBarTheme` in `app.dart`; its own divider is the header block's one
/// edge, so no hairline is drawn here (R-32-582). Its controller is the screen's [tabs], the one
/// the `TabBarView` body shares (R-03-108): a tap moves the controller, and the screen reads
/// the axis off it, so this strip reports nothing itself there. On iOS a
/// `CupertinoSlidingSegmentedControl` keeps the component's own height, thumb and track,
/// because `cupertino_ui` 1.0.1 has no theme slot for it, inset `space.4` from each edge with
/// `space.3` above and below, and the header block's one `border.hairline` in
/// `color.border.strong` closes the strip; it shows [axis] and reports a choice through
/// [onChanged]. Both fill the width, so the two views share it equally, and each marks the
/// selected view its own way with the semantics state `selected` (R-32-520). The app bar
/// draws no edge while the strip is present ([_AgentListScreenState.build]): one edge for the
/// block, the same edge the notifications strip takes.
class _GroupingStrip extends StatelessWidget {
  const _GroupingStrip({
    required this.axis,
    required this.onChanged,
    required this.tabs,
  });

  final AgentListAxis axis;
  final ValueChanged<AgentListAxis> onChanged;
  final TabController tabs;

  /// The two axis names of R-30-406, in the control's own type.
  static const Map<AgentListAxis, String> _labels = <AgentListAxis, String>{
    AgentListAxis.priority: 'Priority',
    AgentListAxis.workspace: 'Workspace',
  };

  @override
  Widget build(BuildContext context) {
    if (!_isIos) {
      return TabBar(
        controller: tabs,
        tabs: <Widget>[
          for (final String label in _labels.values) Tab(text: label),
        ],
      );
    }
    final AppColor color = AppColor.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: color.borderStrong,
            width: AppBorder.hairline,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.space4,
          vertical: AppSpace.space3,
        ),
        child: SizedBox(
          width: double.infinity,
          child: CupertinoSlidingSegmentedControl<AgentListAxis>(
            groupValue: axis,
            onValueChanged: (AgentListAxis? value) {
              if (value != null) onChanged(value);
            },
            children: <AgentListAxis, Widget>{
              for (final MapEntry<AgentListAxis, String> entry
                  in _labels.entries)
                entry.key: Text(entry.value),
            },
          ),
        ),
      ),
    );
  }
}

/// R-32-560/R-90-011: three skeleton rows, never animated, at the two-line agent row height:
/// two bars of `size.skeleton` at `radius.sm`, 140 and 90 wide, plus `space.1` each way stand
/// for the two text lines (40), inside the row's own [_rowVerticalInset], so the skeleton is
/// 64 high like the row it stands for, on the screen's plain `color.bg.base`.
class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  static const double _firstBarWidth = 140;
  static const double _secondBarWidth = 90;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    Widget bar(double width) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.space4,
        vertical: AppSpace.space1,
      ),
      child: SizedBox(
        height: AppSize.skeleton,
        width: width,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color.bgRaised,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        ),
      ),
    );
    Widget row() => Padding(
      padding: const EdgeInsets.symmetric(vertical: _rowVerticalInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[bar(_firstBarWidth), bar(_secondBarWidth)],
      ),
    );
    return Align(
      alignment: Alignment.topCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[row(), row(), row()],
      ),
    );
  }
}

/// The `Error` state (section 7.20, R-32-555): `Could not read <hostName>.`, the raw text,
/// selectable, and exactly one `Try again`, on the screen's plain `color.bg.base`.
class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({
    required this.hostName,
    required this.text,
    required this.onRetry,
  });

  final String hostName;
  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Treatment.error(label: 'Could not read $hostName.'),
              const SizedBox(height: AppSpace.space3),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: color.bgRaised,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.fromBorderSide(
                    BorderSide(color: color.borderStrong),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.space3),
                  child: Text(
                    text,
                    style: AppType.monoCode.copyWith(color: color.fgPrimary),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.space4),
              AppTextButton(label: 'Try again', onPressed: onRetry),
            ],
          ),
        ),
      ),
    );
  }
}

/// The `Empty` state (R-32-553, R-03-107 amended 2026-09-09): left aligned at `space.4`, no
/// illustration, no action button (the create control never starts an agent, R-30-023). The
/// `Eyebrow('AGENTS')` first, then the title in `type.title`, the display face of the screen
/// titles, in `color.accent.text`, then the sentence in `type.body` `color.fg.secondary`
/// (`docs/32-design-language.md` section 7.19). [noun] is `agents` for the `Priority` axis and
/// `panes` for the `Workspace` axis (R-31-06-14).
class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock({required this.hostName, required this.noun});

  final String hostName;
  final String noun;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpace.space4,
        right: AppSpace.space4,
        top: AppSpace.space8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Eyebrow(text: 'AGENTS'),
          const SizedBox(height: AppSpace.space3),
          Text(
            'No $noun on $hostName.',
            style: AppType.title.copyWith(color: color.accentText),
          ),
          const SizedBox(height: AppSpace.space2),
          Text(
            noun == 'agents'
                ? 'Start one in Herdr on your computer, then pull down to refresh.'
                : 'Open one in Herdr on your computer, then pull down to refresh.',
            style: AppType.body.copyWith(color: color.fgSecondary),
          ),
        ],
      ),
    );
  }
}

/// The `Priority` axis: the four sections of callout 3, each a pinned `type.micro` header
/// (R-30-412, R-32-569) over its rows. Each section is one `SliverMainAxisGroup`, so its header
/// pins only while the section is on screen and scrolls away with the section's last row; the
/// next header then takes the top. Without the group, Flutter stacks every pinned header under
/// the one before it (amended 2026-09-08, R-32-569). The sections sit one R-30-231 group gap
/// (`space.6`) apart on the screen's plain `color.bg.base` (R-03-107, amended 2026-09-09), and
/// the pinned header paints that same ground so the rows that scroll under it never show
/// through. The list ends with its last row; the [_createClearance] after it is the scroll
/// view's own end padding for the floating create button (R-03-109, corrected 2026-09-10).
class _PriorityList extends StatelessWidget {
  const _PriorityList({
    required this.sections,
    required this.color,
    required this.onOpenPane,
    required this.onMarkSeen,
  });

  final List<PrioritySection> sections;
  final AppColor color;
  final void Function(String paneId) onOpenPane;
  final void Function(String paneId) onMarkSeen;

  @override
  Widget build(BuildContext context) => SlidableAutoCloseBehavior(
    child: CustomScrollView(
      slivers: <Widget>[
        for (final (int index, PrioritySection section) in sections.indexed)
          SliverPadding(
            padding: EdgeInsets.only(top: index == 0 ? 0 : AppSpace.space6),
            sliver: SliverMainAxisGroup(
              slivers: <Widget>[
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _PinnedHeaderDelegate(
                    height: AppSize.header,
                    child: ColoredBox(
                      color: color.bgBase,
                      child: AppSectionHeader.upperCase(label: section.title),
                    ),
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int index) => _PaneRowTile(
                      row: section.rows[index],
                      axis: AgentListAxis.priority,
                      color: color,
                      // The last row of a section carries no divider.
                      // decided 2026-09-03 by the product owner.
                      showDivider: index < section.rows.length - 1,
                      onOpenPane: onOpenPane,
                      onMarkSeen: onMarkSeen,
                    ),
                    childCount: section.rows.length,
                  ),
                ),
              ],
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: _createClearance)),
      ],
    ),
  );
}

/// The `Workspace` axis (R-31-06-27 to R-31-06-31): one [_SpaceBlock] per space, inset
/// `space.4` from the screen edge and `space.6` apart, on the screen's plain `color.bg.base`
/// (R-03-107, amended 2026-09-09). Nothing pins here; see this file's header doc for why. The
/// pane search left this list on 2026-09-09 (R-03-102): it is the platform's own search pattern
/// in the header block now, and the same list body is what the Android search view shows
/// ([_SearchResults]). The list ends with its last card; the [_createClearance] after it is the
/// scroll view's own end padding for the floating create button (R-03-109, corrected
/// 2026-09-10).
class _SpaceList extends StatelessWidget {
  const _SpaceList({
    required this.spaces,
    required this.search,
    required this.collapsed,
    required this.color,
    required this.onOpenPane,
    required this.onMarkSeen,
    required this.onToggleSpace,
  });

  final List<SpaceGroup> spaces;

  /// The trimmed search text the [spaces] are already narrowed to; `''` when none.
  final String search;
  final Set<String> collapsed;
  final AppColor color;
  final void Function(String paneId) onOpenPane;
  final void Function(String paneId) onMarkSeen;
  final void Function(String spaceKey) onToggleSpace;

  @override
  Widget build(BuildContext context) => SlidableAutoCloseBehavior(
    child: CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.only(
            left: AppSpace.space4,
            right: AppSpace.space4,
            top: AppSpace.space3,
          ),
          sliver: spaces.isEmpty
              // R-31-06-30: reached only while a search matches nothing (the empty tree never
              // builds this list), so the line names the search, not the computer.
              ? SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpace.space3,
                    ),
                    child: Text(
                      'No pane matches \u201C$search\u201D.',
                      style: AppType.body.copyWith(color: color.fgSecondary),
                    ),
                  ),
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate((
                    BuildContext context,
                    int index,
                  ) {
                    final SpaceGroup space = spaces[index];
                    return Padding(
                      // Blocks sit one group gap apart, `space.6` (R-32-595, amended
                      // 2026-09-08 by the product owner: `space.3` read tighter than the 24
                      // between two rows inside a block).
                      padding: const EdgeInsets.only(bottom: AppSpace.space6),
                      child: _SpaceBlock(
                        space: space,
                        expanded: !collapsed.contains(space.key),
                        color: color,
                        onOpenPane: onOpenPane,
                        onMarkSeen: onMarkSeen,
                        onToggle: () => onToggleSpace(space.key),
                      ),
                    );
                  }, childCount: spaces.length),
                ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: _createClearance)),
      ],
    ),
  );
}

/// The pane search placeholder of R-31-06-30 and R-32-598, on both platforms, and the Android
/// search action's label (R-30-717).
const String _searchPlaceholder = 'Search panes';

/// The body of the Android search view (R-03-102): the `Workspace` tree narrowed to the typed
/// text, the same [_SpaceList] the axis draws, or the `No pane matches` line of R-32-598. It
/// follows [views] because `SearchAnchor` rebuilds its suggestions on a keystroke, and the
/// narrowed tree arrives on the service's stream a moment later.
class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.views,
    required this.initial,
    required this.onOpenPane,
    required this.onMarkSeen,
    required this.onToggleSpace,
  });

  final Stream<AgentListView> views;
  final AgentListView? initial;
  final void Function(String paneId) onOpenPane;
  final void Function(String paneId) onMarkSeen;
  final void Function(String spaceKey) onToggleSpace;

  @override
  Widget build(BuildContext context) => StreamBuilder<AgentListView>(
    stream: views,
    initialData: initial,
    builder: (BuildContext context, AsyncSnapshot<AgentListView> snapshot) {
      final AgentListView? view = snapshot.data;
      if (view == null) return const SizedBox.shrink();
      return _SpaceList(
        spaces: view.spaces,
        search: view.search,
        collapsed: view.collapsed,
        color: AppColor.of(context),
        onOpenPane: onOpenPane,
        onMarkSeen: onMarkSeen,
        onToggleSpace: onToggleSpace,
      );
    },
  );
}

/// The `Workspace` axis ladder of text edges inside a space block (R-32-570; amended
/// 2026-09-09 per R-03-057, after two rounds that changed spacing alone left the tiers reading
/// as one weight): the space name at `space.4`, the worktree label at `space.8`, the tab title
/// at `space.12` and the pane text at `space.16`, four even `space.4` steps, so a person reads
/// the parent of a row off its text edge. Every glyph sits `size.icon.sm` plus one `space.2`
/// before its text, so the glyph insets below are the ladder's code-side values: the worktree
/// glyph at `space.2` puts its label at `space.8`, the tab glyph at `space.6` puts its title at
/// `space.12`, and the pane row's leading slot at `space.10` puts the pane text at `space.16`.
/// `agent_list_screen_test.dart` measures the four edges.
const double _spaceNameEdge = AppSpace.space4;
const double _worktreeGlyphInset = AppSpace.space2;
const double _tabGlyphInset = AppSpace.space6;
const double _paneSlotInset = AppSpace.space10;

/// The gap that closes a tab group and precedes a hairline inside the block (R-31-06-29,
/// amended 2026-09-09 per R-03-057): rows under one tab touch, so the `space.3` that a row
/// keeps around its lines is the rhythm inside a group, and one more `space.3` plus the hairline
/// is what separates two groups.
const double _groupGap = AppSpace.space3;

/// One space, drawn as the card of `docs/32-design-language.md` section 7.32 (R-32-595):
/// `color.bg.raised`, a `color.border.subtle` hairline, `radius.md`. Inside it the three tiers
/// of R-03-057 (amended 2026-09-09 by the product owner), each on its own step of the
/// [_spaceNameEdge] ladder and each different from the tier above it in background, in type or
/// glyph, and in text edge:
///
/// - Tier 1, the space: [ChromeListRow.expand], a `color.bg.high` band across the card's top.
/// - Tier 1.5, the worktree: [_WorktreeRow], the worktree glyph and its label, omitted for the
///   parent and for a lone workspace per [SpaceGroup.showsWorktreeRow], so the header's own
///   name is never repeated under it; a full-width hairline precedes it.
/// - Tier 2, the tab: [_TabGroup], the tab glyph, its title and its pane rows hung off a guide
///   rule; consecutive tabs are separated by [_groupGap] and a hairline from the tab glyph.
/// - Tier 3, the panes: [_PaneRowTile] rows on the card's `color.bg.raised`, agent rows with
///   their dot and shell rows with the pane glyph in one leading slot.
///
/// The header band is the block's own edge, so no hairline runs under it (R-32-596, amended
/// 2026-09-09); pane rows inside a tab draw no divider (R-31-06-29).
class _SpaceBlock extends StatelessWidget {
  const _SpaceBlock({
    required this.space,
    required this.expanded,
    required this.color,
    required this.onOpenPane,
    required this.onMarkSeen,
    required this.onToggle,
  });

  final SpaceGroup space;
  final bool expanded;
  final AppColor color;
  final void Function(String paneId) onOpenPane;
  final void Function(String paneId) onMarkSeen;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(AppRadius.md),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color.bgRaised,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: color.borderSubtle,
          width: AppBorder.hairline,
        ),
      ),
      child: ChromeListRow.expand(
        title: space.name,
        initiallyExpanded: expanded,
        onExpansionChanged: (_) => onToggle(),
        backgroundColor: color.bgHigh,
        padding: const EdgeInsets.symmetric(horizontal: _spaceNameEdge),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '${space.paneCount} pane${space.paneCount == 1 ? '' : 's'}',
              style: AppType.caption.copyWith(color: color.fgSecondary),
            ),
            if (space.attentionCount > 0) ...<Widget>[
              const SizedBox(width: AppSpace.space2),
              _AttentionBadge(
                count: space.attentionCount,
                ink: color.fgPrimary,
              ),
            ],
          ],
        ),
        child: ColoredBox(
          color: color.bgRaised,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final (int worktreeIndex, WorktreeGroup worktree)
                  in space.worktrees.indexed) ...<Widget>[
                if (space.showsWorktreeRow(worktree)) ...<Widget>[
                  // The parent is always first (R-31-06-15) and draws no row, so every drawn
                  // worktree row follows a tab group and its hairline spans the block.
                  if (worktreeIndex > 0) _Hairline(color: color),
                  _WorktreeRow(name: worktree.name, color: color),
                ],
                for (final (int tabIndex, TabGroup tab)
                    in worktree.tabs.indexed) ...<Widget>[
                  if (tabIndex > 0)
                    _Hairline(color: color, inset: _tabGlyphInset),
                  _TabGroup(
                    tab: tab,
                    color: color,
                    onOpenPane: onOpenPane,
                    onMarkSeen: onMarkSeen,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

/// Tier 1.5, the worktree row (callout 19, amended 2026-09-09 per R-03-057): the `A worktree`
/// glyph of R-32-401 at `size.icon.sm` in `color.fg.secondary` at [_worktreeGlyphInset], a
/// `space.2` gap, the workspace label in `type.body.strong` `color.fg.primary` at `space.8`;
/// its line plus `space.3` above and below (48). Not a target and never
/// collapses (R-32-565).
class _WorktreeRow extends StatelessWidget {
  const _WorktreeRow({required this.name, required this.color});

  final String name;
  final AppColor color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      left: _worktreeGlyphInset,
      top: AppSpace.space3,
      right: AppSpace.space4,
      bottom: AppSpace.space3,
    ),
    child: Row(
      children: <Widget>[
        Icon(
          Symbols.fork_right_rounded,
          size: AppSize.iconSm,
          color: color.fgSecondary,
        ),
        const SizedBox(width: AppSpace.space2),
        Expanded(
          child: Text(
            name,
            style: AppType.bodyStrong.copyWith(color: color.fgPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

/// Where the guide rule of [_TabGroup] stands: the tab glyph's centre, `space.8`. The rule's
/// trailing side, one `border.hairline` later, is the leading edge of every row hung off it, and
/// so where an agent row's state bar starts ([_agentBarInset]).
const double _guideRuleInset = _tabGlyphInset + AppSize.iconSm / 2;

/// Where an agent row's state bar starts inside a space block (owner finding, 2026-09-09, per
/// R-03-100): beside the guide rule, at the row's own leading edge, not the card's. In
/// `Priority` grouping the row is not indented, so the bar sits at 0.
const double _agentBarInset = _guideRuleInset + AppBorder.hairline;

/// Tier 2, one tab and its panes (callouts 15 and 23, amended 2026-09-09 per R-03-057). The
/// header: the `A tab` glyph of R-32-401 at `size.icon.sm` in `color.fg.secondary` at
/// [_tabGlyphInset], a `space.2` gap, the title in `type.body.strong` `color.fg.primary` at
/// `space.12`; its line plus `space.3` above and below (48); not a target (R-31-06-19).
/// Under it the pane rows, and a guide rule of `border.hairline` in `color.border.subtle` that
/// drops from the tab glyph's centre, `space.8`, through the rows' full height, so every row
/// hangs off its tab the way a tree draws its branch; the rule never takes a touch. The group
/// closes with [_groupGap], which is what separates it from the next hairline and tab, or from
/// the card's bottom edge.
class _TabGroup extends StatelessWidget {
  const _TabGroup({
    required this.tab,
    required this.color,
    required this.onOpenPane,
    required this.onMarkSeen,
  });

  final TabGroup tab;
  final AppColor color;
  final void Function(String paneId) onOpenPane;
  final void Function(String paneId) onMarkSeen;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Padding(
        padding: const EdgeInsets.only(
          left: _tabGlyphInset,
          top: AppSpace.space3,
          right: AppSpace.space4,
          bottom: AppSpace.space3,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              Symbols.tab_rounded,
              size: AppSize.iconSm,
              color: color.fgSecondary,
            ),
            const SizedBox(width: AppSpace.space2),
            Expanded(
              child: Text(
                tab.title,
                style: AppType.bodyStrong.copyWith(color: color.fgPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      Stack(
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final PaneRow row in tab.rows)
                _PaneRowTile(
                  row: row,
                  axis: AgentListAxis.workspace,
                  color: color,
                  showDivider: false,
                  leadingInset: _paneSlotInset,
                  slotWidth: AppSize.iconSm,
                  onOpenPane: onOpenPane,
                  onMarkSeen: onMarkSeen,
                ),
            ],
          ),
          Positioned(
            left: _guideRuleInset,
            top: 0,
            bottom: 0,
            width: AppBorder.hairline,
            child: IgnorePointer(child: ColoredBox(color: color.borderSubtle)),
          ),
        ],
      ),
      const SizedBox(height: _groupGap),
    ],
  );
}

/// A `border.hairline` in `color.border.subtle`, from [inset] to the trailing edge (R-32-596).
class _Hairline extends StatelessWidget {
  const _Hairline({required this.color, this.inset = 0});

  final AppColor color;
  final double inset;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(left: inset),
    child: SizedBox(
      height: AppBorder.hairline,
      child: ColoredBox(color: color.borderSubtle),
    ),
  );
}

/// A fixed-height pinned sliver header, per R-32-564/R-32-565/R-32-569's fixed header heights.
class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _PinnedHeaderDelegate({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => child;

  @override
  bool shouldRebuild(covariant _PinnedHeaderDelegate oldDelegate) =>
      oldDelegate.height != height || oldDelegate.child != child;
}

/// One pane row. An [AgentRow] draws as [_AgentRowContent] plus, only when it needs attention,
/// the `Mark as seen` reveal (R-31-06-20): a row with no marker to clear gets no dead
/// affordance. A [ShellRow] draws as [_ShellRowContent]: no status, no marker, no reveal.
class _PaneRowTile extends StatelessWidget {
  const _PaneRowTile({
    required this.row,
    required this.axis,
    required this.color,
    required this.showDivider,
    required this.onOpenPane,
    required this.onMarkSeen,
    this.leadingInset = AppSpace.space4,
    this.slotWidth = _prioritySlotWidth,
  });

  final PaneRow row;
  final AgentListAxis axis;
  final AppColor color;

  /// Whether the row draws its bottom divider. The last row of a section
  /// does not (owner decision, 2026-09-03), and no row inside a space block
  /// does (R-31-06-29).
  final bool showDivider;

  /// Where the row's leading slot starts: `space.4` in `Priority` grouping, [_paneSlotInset]
  /// inside a space block.
  final double leadingInset;

  /// The leading slot's width: [_prioritySlotWidth] in `Priority` grouping, where every row is an
  /// agent, and `size.icon.sm` inside a space block, where a shell row puts the pane glyph in
  /// the slot (R-32-597, amended 2026-09-09 per R-03-057). An agent row leaves the slot empty
  /// since R-03-100 moved its state to the leading bar; the slot plus [_slotGap] still sets the
  /// text edge, so the ladder of R-32-570 did not move.
  final double slotWidth;
  final void Function(String paneId) onOpenPane;
  final void Function(String paneId) onMarkSeen;

  @override
  Widget build(BuildContext context) {
    final PaneRow row = this.row;
    switch (row) {
      case ShellRow():
        return _ShellRowContent(
          row: row,
          color: color,
          leadingInset: leadingInset,
          slotWidth: slotWidth,
          onTap: () => onOpenPane(row.paneId),
        );
      case AgentRow():
        final Widget content = _AgentRowContent(
          row: row,
          axis: axis,
          color: color,
          showDivider: showDivider,
          leadingInset: leadingInset,
          slotWidth: slotWidth,
          onTap: () => onOpenPane(row.paneId),
        );
        if (!row.needsAttention) return content;

        // The revealed pane takes the anatomy of R-32-576: as wide as its one action, the
        // label at `type.caption` plus `space.3` each side, floored at `size.target.min` and
        // never past half the row ([_actionExtentRatio]); `done_all` at `size.icon.md` above
        // the words, gap `space.1`, both in `color.fg.primary` on `color.bg.raised`; and a
        // `border.hairline` in `color.border.strong` at the pane's leading edge. Corrected
        // 2026-09-08: the pane was a fixed 0.32 of the row and the package's own `SlidableAction`
        // drew a 24 icon and a `labelLarge` label with no leading edge.
        return Semantics(
          customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
            const CustomSemanticsAction(label: _markSeenLabel): () =>
                onMarkSeen(row.paneId),
          },
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) =>
                Slidable(
                  key: ValueKey<String>(row.paneId),
                  groupTag: _slidableGroupTag,
                  endActionPane: ActionPane(
                    motion: const ScrollMotion(),
                    dragDismissible: false,
                    extentRatio: _actionExtentRatio(
                      context,
                      _markSeenLabel,
                      constraints.maxWidth,
                    ),
                    children: <Widget>[
                      CustomSlidableAction(
                        onPressed: (_) => onMarkSeen(row.paneId),
                        backgroundColor: color.bgRaised,
                        foregroundColor: color.fgPrimary,
                        child: SizedBox.expand(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              SizedBox(
                                width: AppBorder.hairline,
                                child: ColoredBox(color: color.borderStrong),
                              ),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: <Widget>[
                                    Icon(
                                      Symbols.done_all_rounded,
                                      size: AppSize.iconMd,
                                      color: color.fgPrimary,
                                    ),
                                    const SizedBox(height: AppSpace.space1),
                                    DefaultTextStyle(
                                      style: AppType.caption.copyWith(
                                        color: color.fgPrimary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      child: const Text(_markSeenLabel),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  child: content,
                ),
          ),
        );
    }
  }
}

/// The leading slot's width in `Priority` grouping, where every row is an agent row. The slot is
/// empty (R-03-100: the state is the bar at the row's edge) and keeps the text at `space.8`:
/// `space.4` of inset, this slot and [_slotGap] (2026-09-09, the edge the status dot set).
const double _prioritySlotWidth = AppSpace.space2;

/// The gap after the leading slot. In `Priority` grouping the slot plus the gap is one `space.4`,
/// which puts the text at `space.8`. Inside a space block the slot is `size.icon.sm` wide at
/// [_paneSlotInset], so the same gap puts the pane text at `space.16`, one `space.4` step past
/// the tab title (R-32-570, amended 2026-09-09 per R-03-057).
const double _slotGap = AppSpace.space2;

/// A pane row's box: [_rowVerticalInset] above and below [child], [leadingInset] before it,
/// `space.4` after it, and never lower than `size.target.min` (R-32-360, R-32-363). The row is
/// as tall as its lines, so a one-line row is 48 and a two-line row 64 at the default text
/// scale, and both grow with the text instead of clipping it.
class _RowBox extends StatelessWidget {
  const _RowBox({required this.leadingInset, required this.child});

  final double leadingInset;
  final Widget child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: AppSize.targetMin),
    child: Padding(
      padding: EdgeInsets.only(
        left: leadingInset,
        right: AppSpace.space4,
        top: _rowVerticalInset,
        bottom: _rowVerticalInset,
      ),
      child: child,
    ),
  );
}

/// One text line shares an alphabetic baseline and a trailing edge.
/// Priority puts the status beside the tab title and the age beside the breadcrumb.
/// Workspace puts the kind, pane, status, and age on one line.
class _RowLine extends StatelessWidget {
  const _RowLine({required this.leading, this.trailing});

  final Widget leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: <Widget>[
      Expanded(child: leading),
      if (trailing != null) ...<Widget>[
        const SizedBox(width: AppSpace.space3),
        trailing!,
      ],
    ],
  );
}

/// A pane with no agent (R-31-06-14), per R-32-597 and R-03-115 (amended 2026-09-10): the
/// `A pane` glyph in the leading slot, then the display name in `type.body`
/// `color.fg.secondary` and its optional `title` in `type.caption` after `space.2`, all on
/// one baseline. The title ellipses with the line. The row has no status word or state bar and
/// The native list row handles taps.
class _ShellRowContent extends StatelessWidget {
  const _ShellRowContent({
    required this.row,
    required this.color,
    required this.leadingInset,
    required this.slotWidth,
    required this.onTap,
  });

  final ShellRow row;
  final AppColor color;
  final double leadingInset;
  final double slotWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppListRow(
    primary: <String>[
      row.paneDisplayName,
      if (row.title.isNotEmpty) row.title,
    ].join(', '),
    onTap: onTap,
    showDivider: false,
    contentPadding: EdgeInsets.zero,
    primaryWidget: _RowBox(
      leadingInset: leadingInset,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: slotWidth,
            child: Center(
              child: Icon(
                Symbols.splitscreen_rounded,
                size: AppSize.iconSm,
                color: color.fgSecondary,
              ),
            ),
          ),
          const SizedBox(width: _slotGap),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: row.paneDisplayName,
                style: AppType.body.copyWith(color: color.fgSecondary),
                children: [
                  if (row.title.isNotEmpty)
                    const WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: SizedBox(width: AppSpace.space2),
                    ),
                  if (row.title.isNotEmpty)
                    TextSpan(
                      text: row.title,
                      style: AppType.caption.copyWith(color: color.fgSecondary),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    ),
  );
}

/// The row follows the selected axis (R-03-115, R-03-124).
/// Workspace puts the kind, pane, state, and age on one alphabetic baseline.
/// Priority puts the tab title beside the state, then workspace, pane, and kind beside the age.
/// The unread mark gives the primary text strong weight and adds an accent wash.
/// The status bar spans the row height. The last Priority row has no divider.
/// [_RowBox] sets the height. [AppListRow] sets the pressed fill (R-32-501, R-32-609).
class _AgentRowContent extends StatelessWidget {
  const _AgentRowContent({
    required this.row,
    required this.axis,
    required this.color,
    required this.showDivider,
    required this.leadingInset,
    required this.slotWidth,
    this.onTap,
  });

  final AgentRow row;
  final AgentListAxis axis;
  final AppColor color;

  /// Whether the row draws its bottom divider, inset [leadingInset] from the
  /// leading edge per `docs/32-design-language.md` section 7.4.
  final bool showDivider;
  final double leadingInset;

  /// The leading slot's width; an agent row leaves it empty ([_PaneRowTile.slotWidth]).
  final double slotWidth;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final String statusLabel = _statusLabel(row.status);
    // R-03-056: a row with a time depends on the screen's clock and redraws on every tick; a
    // row the Host gave no time never does.
    final String? at = row.at;
    final String? age = at == null
        ? null
        : _formatAge(at, _AgeClock.of(context));
    // R-03-100 (2026-09-09): the bar is the status in the status hue, the word beside it names
    // the status, and the unread fact is weight and wash; two bars on one edge would say two
    // facts in one shape. `docs/32-design-language.md` section 7.4 owns the values.
    final bool unread = row.needsAttention;
    final String title = row.tabTitle.isEmpty
        ? row.paneDisplayName
        : row.tabTitle;
    // Priority names the task first. Workspace already has a tab header.
    final List<String> segments = axis == AgentListAxis.priority
        ? <String>[row.workspaceName, row.paneDisplayName]
        : <String>[row.paneDisplayName];

    // R-32-574: one semantics node, with each separator replaced by a comma.
    final String semanticsLabel = <String>[
      axis == AgentListAxis.priority ? title : row.agentKind,
      statusLabel,
      segments.join(', '),
      if (axis == AgentListAxis.priority) row.agentKind,
      ?age,
    ].join(', ');
    final Widget lines = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _RowBox(
          leadingInset: leadingInset,
          child: Row(
            children: <Widget>[
              SizedBox(width: slotWidth),
              const SizedBox(width: _slotGap),
              Expanded(
                child: axis == AgentListAxis.workspace
                    ? _RowLine(
                        leading: Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: <Widget>[
                            Text(
                              row.agentKind,
                              style:
                                  (unread ? AppType.bodyStrong : AppType.body)
                                      .copyWith(color: color.fgPrimary),
                            ),
                            const SizedBox(width: AppSpace.space2),
                            Expanded(
                              child: Text(
                                row.paneDisplayName,
                                style: AppType.caption.copyWith(
                                  color: color.fgSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        trailing: Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: <Widget>[
                            Text(
                              statusLabel,
                              style: AppType.body.copyWith(
                                color: color.fgPrimary,
                              ),
                            ),
                            if (age != null) ...<Widget>[
                              const SizedBox(width: AppSpace.space2),
                              Text(
                                age,
                                style: AppType.caption.copyWith(
                                  color: color.fgSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          _RowLine(
                            leading: Text(
                              title,
                              style:
                                  (unread ? AppType.bodyStrong : AppType.body)
                                      .copyWith(color: color.fgPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text(
                              statusLabel,
                              style: AppType.label.copyWith(
                                color: color.fgPrimary,
                              ),
                            ),
                          ),
                          _RowLine(
                            leading: _Breadcrumb(
                              segments: segments,
                              kind: row.agentKind,
                              color: color.fgSecondary,
                            ),
                            trailing: age == null
                                ? null
                                : Text(
                                    age,
                                    style: AppType.caption.copyWith(
                                      color: color.fgSecondary,
                                    ),
                                  ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Padding(
            padding: EdgeInsets.only(left: leadingInset),
            child: Container(
              height: AppBorder.hairline,
              color: color.borderSubtle,
            ),
          ),
      ],
    );

    return AppListRow(
      primary: semanticsLabel,
      onTap: onTap,
      selected: unread,
      showDivider: false,
      contentPadding: EdgeInsets.zero,
      primaryWidget: Stack(
        children: <Widget>[
          lines,
          PositionedDirectional(
            start: axis == AgentListAxis.workspace ? _agentBarInset : 0,
            top: 0,
            bottom: 0,
            child: StatusBar(state: _barStateFor(row.status)),
          ),
        ],
      ),
    );
  }
}

/// R-32-576: the revealed pane is exactly as wide as its one action, which is [label] at
/// `type.caption` plus `space.3` on each side, floored at `size.target.min` and capped at half
/// of [rowWidth]. Measured at the current text scale, so a large scale widens the action
/// instead of shrinking its label (R-32-363). `flutter_slidable` takes the pane as a ratio of
/// the row, so the width is converted here and is never a fixed fraction. Mirrors
/// `host_list_screen.dart`'s own private copy.
double _actionExtentRatio(BuildContext context, String label, double rowWidth) {
  final TextPainter painter = TextPainter(
    text: TextSpan(text: label, style: AppType.caption),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final double width = math.max(
    painter.width + AppSpace.space3 * 2,
    AppSize.targetMin,
  );
  painter.dispose();
  return math.min(width / rowWidth, 0.5);
}

/// The breadcrumb of section 7.24: one line, front-elided, the last segment always whole
/// (R-32-573, R-31-06-17), falling back to the last segment's own tail-ellipsis when even that
/// alone overflows.
class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.segments, required this.color, this.kind});

  final List<String> segments;
  final Color color;
  final String? kind;

  @override
  Widget build(BuildContext context) {
    final TextStyle style = AppType.caption.copyWith(color: color);
    final String suffix = kind == null ? '' : ' · $kind';
    if (segments.length == 1 && kind == null) {
      return Text(
        segments.first,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final TextScaler scaler = MediaQuery.textScalerOf(context);
        bool fits(String text) =>
            _fits(text, style, scaler, constraints.maxWidth);
        final String full = '${segments.join(_breadcrumbSeparator)}$suffix';
        if (fits(full)) {
          return Text(
            full,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.clip,
          );
        }
        for (int drop = 1; drop < segments.length; drop++) {
          final String candidate =
              '\u2026$_breadcrumbSeparator${segments.sublist(drop).join(_breadcrumbSeparator)}$suffix';
          if (fits(candidate)) {
            return Text(
              candidate,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.clip,
            );
          }
        }
        return Text(
          '${segments.last}$suffix',
          style: style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }

  /// Whether [text] fits on one line inside [maxWidth] at [scaler]. `TextPainter.width` is
  /// clamped to the layout width, so it said every breadcrumb fit and the front elision never
  /// ran (fixed 2026-09-08); the unclamped `maxIntrinsicWidth` is the measure.
  static bool _fits(
    String text,
    TextStyle style,
    TextScaler scaler,
    double maxWidth,
  ) {
    final TextPainter painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout(maxWidth: maxWidth);
    final bool fits = painter.maxIntrinsicWidth <= maxWidth;
    painter.dispose();
    return fits;
  }
}

/// The state bar's state for an agent status (callout 4, R-03-100): one hue per state, the
/// five states of R-30-401.
BarState _barStateFor(AgentStatusKind status) => switch (status) {
  AgentStatusKind.working => BarState.working,
  AgentStatusKind.idle => BarState.idle,
  AgentStatusKind.blocked => BarState.blocked,
  AgentStatusKind.done => BarState.done,
  AgentStatusKind.unknown => BarState.unknown,
};

String _statusLabel(AgentStatusKind status) => switch (status) {
  AgentStatusKind.idle => 'Idle',
  AgentStatusKind.working => 'Working',
  AgentStatusKind.blocked => 'Blocked',
  AgentStatusKind.done => 'Done',
  AgentStatusKind.unknown => 'Unknown',
};

/// The relative age of R-30-405's format, `null` when [at] is not a parsable time.
String? _formatAge(String at, DateTime now) {
  final DateTime? parsed = DateTime.tryParse(at);
  if (parsed == null) return null;
  final int totalSeconds = now
      .toUtc()
      .difference(parsed.toUtc())
      .inSeconds
      .clamp(0, 1 << 31);
  if (totalSeconds < 60) return '${totalSeconds}s';
  final int totalMinutes = totalSeconds ~/ 60;
  if (totalMinutes < 60) {
    final int seconds = totalSeconds % 60;
    return '${totalMinutes}m ${seconds.toString().padLeft(2, '0')}s';
  }
  final int totalHours = totalMinutes ~/ 60;
  if (totalHours < 24) {
    final int minutes = totalMinutes % 60;
    return '${totalHours}h ${minutes.toString().padLeft(2, '0')}m';
  }
  final int days = totalHours ~/ 24;
  return '${days}d';
}
