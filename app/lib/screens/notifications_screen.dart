/// The `Notifications` destination, drawn from `docs/31-mockups/07-notifications.md` at route
/// `/hosts/:hostId/notifications` (`docs/30-ux-spec.md` row 07, decided 2026-09-04 by the
/// product owner): the session log of agent status changes, one row per pane (R-31-07-01),
/// newest first (R-31-07-02), in two groups, `NEW` then `EARLIER` (R-31-07-11), under a strip of
/// two worded bulk controls, `Mark all read` and `Remove all` (R-31-07-03, R-31-07-04). A tap
/// opens the pane (R-31-07-05).
///
/// This file owns no route and no data: `app/lib/routing.dart` wires the route and hands this
/// widget `AgentStatusService`'s [notifications]/[currentNotifications] plus one callback per
/// action, mirroring `agent_list_screen.dart`'s `unseenAttention`/`onMarkSeen` seam, so a test
/// drives it with a bare `StreamController`. The log lives in memory for the session
/// (R-31-07-06), so there is no loading state: the first paint draws [currentNotifications].
///
/// **Live (R-03-056, R-31-07-12).** Every emission of [notifications] redraws the list, so a new
/// `agent_status` lands at the top of `NEW` while the person looks at it. One periodic timer on
/// `ageTickPeriod` redraws the ages while the screen is on screen, and stops while this branch is
/// the shell's offstage tab (`TickerMode`), so an invisible tab costs nothing per second.
///
/// **One mark per fact (R-03-058).** A row's status is the word in its phrase, `omp is done`;
/// no dot repeats it. A row's unread state is one composed signal: the leading `border.attention`
/// bar in `color.accent.primary`, `type.body.strong` and the `color.accent.soft` wash. A read row
/// carries none of the three. The two group headers say the same thing for the group.
///
/// **Reveal-then-tap.** Each row is a `Slidable` (R-20-040, R-30-297 to R-30-299): one
/// `SlidableAutoCloseBehavior` ancestor, a shared `groupTag`, `dragDismissible: false`, and
/// `customSemanticsActions` naming every revealed action (R-30-298, R-32-580). A swipe toward
/// the trailing edge reveals `Remove`; a swipe toward the leading edge reveals `Mark as read` on
/// an unread row (R-31-07-09). `Remove` acts at once, because a row is a phone-local record and
/// nothing on the computer changes (R-31-07-04); `Remove all` confirms first through
/// `chrome_confirmation_dialog.dart`, per `docs/32-design-language.md` section 7.17.
///
/// The row's small helpers (`_formatAge`, the breadcrumb separator, the pinned header delegate)
/// duplicate `agent_list_screen.dart`'s private ones per R-41-042 rung 1 and R-90-018: that file
/// belongs to another work package, and neither helper sits on a shared `Paths.` line yet.
library;

import 'dart:async' show StreamSubscription, Timer, unawaited;
import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart'
    show
        CupertinoButton,
        CupertinoTheme,
        CupertinoNavigationBar,
        CupertinoPageScaffold,
        kMinInteractiveDimensionCupertino;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/widgets.dart'
    show
        AnimationStyle,
        Border,
        BorderRadius,
        BorderSide,
        BoxConstraints,
        BoxDecoration,
        BuildContext,
        Center,
        ColoredBox,
        Column,
        Container,
        CrossAxisAlignment,
        Curve,
        Curves,
        CustomScrollView,
        DecoratedBox,
        EdgeInsets,
        ExcludeSemantics,
        Expanded,
        Icon,
        IconData,
        LayoutBuilder,
        MainAxisSize,
        MediaQuery,
        Navigator,
        Padding,
        Radius,
        Row,
        SafeArea,
        SingleTickerProviderStateMixin,
        SizedBox,
        SliverChildBuilderDelegate,
        SliverList,
        SliverMainAxisGroup,
        SliverPadding,
        SliverPersistentHeader,
        SliverPersistentHeaderDelegate,
        SliverToBoxAdapter,
        State,
        StatefulWidget,
        StatelessWidget,
        Text,
        TextBaseline,
        TextDirection,
        TextOverflow,
        TextPainter,
        TextSpan,
        TickerMode,
        ValueKey,
        VoidCallback,
        Widget;
import 'package:flutter_slidable/flutter_slidable.dart'
    show
        ActionPane,
        ScrollMotion,
        Slidable,
        SlidableAutoCloseBehavior,
        SlidableController;
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart'
    show
        AppBar,
        IconButton,
        RoundedRectangleBorder,
        Scaffold,
        TextButton,
        Theme,
        showModalBottomSheet;

import '../core/result/result.dart' show Err, Result;
import '../models/messages/agent_status_kind.dart';
import '../services/agent_status.dart' show NotificationItem;
import '../services/notifications.dart' show ageTickPeriod;
import '../widgets/app_ground.dart' show EmptyMark;
import '../widgets/app_list_row.dart';
import '../widgets/app_section_header.dart';
import '../widgets/app_strip.dart';
import '../widgets/app_text_button.dart';
import '../widgets/ground_grid.dart' show GroundGrid;
import '../widgets/status_bar.dart' show BarState;
import '../widgets/theme/app_color.dart';
import '../widgets/theme/app_motion.dart' show AppMotion;
import '../widgets/theme/app_radius.dart';
import '../widgets/theme/app_size.dart';
import '../widgets/theme/app_space.dart';
import '../widgets/theme/app_type.dart';
import '../widgets/theme/chrome_confirmation_dialog.dart';
import '../widgets/theme/chrome_confirmation_outcome.dart';
import '../widgets/theme/chrome_list_row.dart';
import '../widgets/treatments.dart';

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

/// The breadcrumb separator, `›` (U+203A) with a hair space on each side, per R-32-572.
const String _breadcrumbSeparator = '\u2009\u203A\u2009';

/// The blank each side of a `size.icon.md` glyph inside the platform button's own box: the
/// `size.target.min` box of `IconButton` on Android and the `kMinInteractiveDimensionCupertino`
/// box of `CupertinoButton` on iOS (R-03-059: the button keeps its own size, no box around it).
/// Subtracted from the row's trailing inset so the glyph, not the box, ends on `space.4`
/// (callout 11).
double get _menuGlyphInset =>
    ((_isIos ? kMinInteractiveDimensionCupertino : AppSize.targetMin) -
        AppSize.iconMd) /
    2;

/// `Slidable.groupTag` shared by every row on this screen, so opening one closes any other
/// (R-30-299).
const String _slidableGroupTag = 'notifications';

/// R-30-511's `pane closed` copy, drawn as the inline strip of R-31-07-07.
const String paneClosedSentence = 'That pane has closed.';

/// The two group headers of callout 4 (R-31-07-11): our own words, so upper case in
/// `type.micro`, per R-32-567.
const String newHeaderLabel = 'NEW';
const String earlierHeaderLabel = 'EARLIER';

/// Callout 12's line under an empty `NEW` group (R-30-801, R-30-802): the absent thing and the
/// next step, in one sentence pair.
const String noNewSentence =
    'No new notifications. You have read everything below.';

/// Section 7.16's sheet motion: `motion.duration.base` both ways, `motion.curve.enter` in and
/// `motion.curve.exit` out; under reduce motion no animation at all (R-32-606). `curveExit` is
/// defined in Flutter's reverse space (R-32-609), so a `reverseCurve` takes it unchanged.
/// Duplicated from `pane_actions_sheet.dart` per this file's header note.
AnimationStyle _sheetAnimationStyle(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? AnimationStyle.noAnimation
    : const AnimationStyle(
        duration: AppMotion.durationBase,
        reverseDuration: AppMotion.durationBase,
        curve: AppMotion.curveEnter,
        reverseCurve: AppMotion.curveExit,
      );

/// The swipe reveal's settle (R-32-600, R-32-609). `flutter_slidable` tracks the finger 1:1
/// while it drags, then settles a released row with its own `Curves.ease` over 200 ms, a weak
/// ease-in-out that ignores the motion tokens. Its `ActionPane` settles through these two
/// methods, so this controller substitutes the tokens there: `motion.curve.enter` for the
/// reveal, `motion.curve.exit` for the close, `motion.duration.base` for both, and instant
/// under reduce motion (R-32-606). `animateBack` runs the close in forward time, so the exit
/// curve, defined in reverse space, is `flipped` here, as R-32-609 says a forward-running
/// animation of a leaving element takes it.
class _SnapController extends SlidableController {
  _SnapController(super.vsync);

  /// `MediaQuery.disableAnimationsOf`, read at build by the row that owns this controller.
  bool reduceMotion = false;

  Duration get _duration =>
      reduceMotion ? AppMotion.durationInstant : AppMotion.durationBase;

  Curve _curve(Curve curve) => reduceMotion ? Curves.linear : curve;

  @override
  Future<void> openCurrentActionPane({Duration? duration, Curve? curve}) =>
      super.openCurrentActionPane(
        duration: _duration,
        curve: _curve(AppMotion.curveEnter),
      );

  @override
  Future<void> close({Duration? duration, Curve? curve}) => super.close(
    duration: _duration,
    curve: _curve(AppMotion.curveExit.flipped),
  );
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.hostName,
    required this.notifications,
    required this.currentNotifications,
    required this.onMarkSeen,
    required this.onMarkAllSeen,
    required this.onRemove,
    required this.onRemoveAll,
    required this.onOpenPane,
    this.closedPaneId,
    this.now = DateTime.now,
  });

  /// The connected computer's display name, for the empty state and the `Remove all` dialog.
  final String hostName;

  /// `AgentStatusService.notifications`: the session log, newest first (R-31-07-02). Every
  /// emission redraws the list (R-31-07-12).
  final Stream<List<NotificationItem>> notifications;

  /// `AgentStatusService.currentNotifications` at build, for the first paint and for any later
  /// rebuild the route makes while the stream is quiet.
  final List<NotificationItem> currentNotifications;

  /// `Mark as read` on one row (R-31-07-03): `AgentStatusService.markSeen`. Resolves once the
  /// acknowledgement is stored; an `Err` is shown inline and the row stays unread.
  final Future<Result<void>> Function(String paneId) onMarkSeen;

  /// `Mark all read` (R-31-07-03): `AgentStatusService.markAllSeen`.
  final Future<Result<void>> Function() onMarkAllSeen;

  /// `Remove` on one row (R-31-07-04): `AgentStatusService.remove`.
  final Future<Result<void>> Function(String paneId) onRemove;

  /// `Remove all`, after this screen's own confirmation (R-31-07-04):
  /// `AgentStatusService.removeAll`.
  final Future<Result<void>> Function() onRemoveAll;

  /// A row tap (R-31-07-05). The caller marks the pane opened
  /// (`AgentStatusService.notePaneOpened`) and pushes `/hosts/:hostId/panes/:paneId`.
  final void Function(String paneId) onOpenPane;

  /// R-30-511, R-31-07-07: the pane a notification tap named that the tree no longer holds.
  /// Non-`null` draws the `That pane has closed.` strip above the list.
  final String? closedPaneId;

  /// The clock the age of callout 7 is measured against; a test pins it.
  final DateTime Function() now;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late List<NotificationItem> _items = widget.currentNotifications;
  StreamSubscription<List<NotificationItem>>? _sub;
  Timer? _ageTick;

  /// `TickerMode.of(context)` at the last build: `false` while this screen is the shell's
  /// offstage tab (go_router wraps an inactive branch in `TickerMode(enabled: false)`), so the
  /// age tick rebuilds nothing there. The mode change itself rebuilds the screen when the tab
  /// returns, so the ages are fresh on the first visible frame.
  bool _onScreen = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sub = widget.notifications.listen((List<NotificationItem> items) {
      if (mounted) setState(() => _items = items);
    });
    // R-03-056, R-31-07-12: the ages count while the screen is on screen. One timer for the
    // whole list, cancelled in [dispose]; a list with no aged row has nothing to redraw.
    _ageTick = Timer.periodic(ageTickPeriod, (_) {
      if (mounted && _onScreen && _hasAge) setState(() {});
    });
  }

  @override
  void didUpdateWidget(NotificationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The route hands a fresh log on every rebuild. Adopting it means a rebuild can never leave
    // the first paint's list on screen while the stream is quiet, so the rows and the shell's
    // badge, which reads the same log, cannot disagree (R-31-07-05).
    if (!identical(
      oldWidget.currentNotifications,
      widget.currentNotifications,
    )) {
      _items = widget.currentNotifications;
    }
  }

  @override
  void dispose() {
    _ageTick?.cancel();
    unawaited(_sub?.cancel());
    super.dispose();
  }

  bool get _hasAge =>
      _items.any((NotificationItem entry) => entry.item.at != null);

  /// Callout 11: the row's actions behind a visible control, on the menu surface of R-33-033 (a
  /// bottom sheet on both platforms), so a person who never swipes still finds `Mark as read`
  /// and `Remove`. Same callbacks as the swipe. The sheet takes section 7.16's anatomy: grab
  /// handle, header (the row's phrase over its breadcrumb), a group divider,
  /// `size.row.one_line` rows in `type.body`, then `Cancel`.
  Future<void> _showRowActions(NotificationItem entry) {
    final AppColor color = AppColor.of(context);
    final String paneId = entry.item.paneId;
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: color.bgRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      sheetAnimationStyle: _sheetAnimationStyle(context),
      builder: (BuildContext sheetContext) {
        final Widget divider = Container(
          height: AppBorder.hairline,
          color: color.borderSubtle,
        );
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.space2),
                child: Center(
                  child: ExcludeSemantics(
                    child: Container(
                      width: AppSize.grabWidth,
                      height: AppSize.grabHeight,
                      decoration: BoxDecoration(
                        color: color.fgDisabled,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.space4,
                  AppSpace.space4,
                  AppSpace.space4,
                  AppSpace.space3,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      _phraseFor(entry),
                      style: AppType.bodyStrong.copyWith(
                        color: color.fgPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpace.space1),
                    Text(
                      _segmentsFor(entry).join(_breadcrumbSeparator),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.caption.copyWith(color: color.fgSecondary),
                    ),
                  ],
                ),
              ),
              divider,
              if (!entry.seen)
                _SheetActionRow(
                  // `Mark as seen` in the R-32-401 map.
                  icon: Symbols.done_all_rounded,
                  label: 'Mark as read',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(_run(widget.onMarkSeen(paneId)));
                  },
                ),
              _SheetActionRow(
                // `Remove one notification, destructive` in the R-32-401 map (2026-09-08).
                icon: Symbols.delete_outline_rounded,
                label: 'Remove',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_run(widget.onRemove(paneId)));
                },
              ),
              divider,
              // R-03-059 (2026-09-09): the platform button keeps its own height; no box
              // around it.
              AppTextButton(
                label: 'Cancel',
                onPressed: () => Navigator.of(sheetContext).pop(),
                subdued: true,
              ),
            ],
          ),
        );
      },
    );
  }

  /// R-31-07-04: `Remove all` is the one destructive action here and confirms first, per
  /// `docs/32-design-language.md` section 7.17 and R-33-074.
  Future<void> _confirmRemoveAll() async {
    final ChromeConfirmationOutcome? outcome =
        await showChromeConfirmationDialog(
          context: context,
          title: 'Remove all notifications?',
          body:
              'This clears the list on this phone. '
              'Nothing changes on ${widget.hostName}.',
          destructiveLabel: 'Remove all',
        );
    if (outcome != ChromeConfirmationOutcome.destructive || !mounted) return;
    await _run(widget.onRemoveAll());
  }

  /// Every action reports its stored outcome (R-31-07-01): an `Err` stays on screen as the
  /// error strip, in the failed write's own words (R-30-803), until the next action succeeds.
  /// The rows themselves only change through the stream, once the service stored the change.
  Future<void> _run(Future<Result<void>> action) async {
    final Result<void> result = await action;
    if (!mounted) return;
    setState(() => _error = result is Err<void> ? result.message : null);
  }

  @override
  Widget build(BuildContext context) {
    _onScreen = TickerMode.valuesOf(context).enabled;
    final AppColor color = AppColor.of(context);
    // One list, one predicate, in this order: the `NEW` group is exactly the unread rows the
    // shell's badge counts from the same log (R-31-07-05), so the two cannot disagree.
    final List<NotificationItem> unread = <NotificationItem>[
      for (final NotificationItem entry in _items)
        if (!entry.seen) entry,
    ];
    final List<NotificationItem> read = <NotificationItem>[
      for (final NotificationItem entry in _items)
        if (entry.seen) entry,
    ];
    // `type.title`, not `type.heading`: this is a bottom destination with no back chevron,
    // matching `settings_screen.dart`'s own precedent.
    final Widget title = Text(
      'Notifications',
      style: AppType.title.copyWith(color: color.fgPrimary),
    );
    final Widget body = Column(
      children: <Widget>[
        // Callouts 2 and 3: the two bulk controls, worded, under the title. R-32-582: the bar
        // and this strip are one header block, so the block's one hairline sits under the strip
        // and the bar above draws none.
        _BulkActions(
          onMarkAllRead: unread.isEmpty
              ? null
              : () => unawaited(_run(widget.onMarkAllSeen())),
          onRemoveAll: _items.isEmpty
              ? null
              : () => unawaited(_confirmRemoveAll()),
        ),
        if (widget.closedPaneId != null)
          const AppStrip(child: Treatment.warning(label: paneClosedSentence)),
        if (_error != null)
          AppStrip(child: Treatment.error(label: _error!, inStrip: true)),
        Expanded(
          // R-03-107 (amended 2026-09-09): the empty state is the one place this screen paints
          // the ground grid, with the mark behind its block; the list sits on the screen's
          // plain `color.bg.base` (see [_NotificationList]).
          child: _items.isEmpty
              ? GroundGrid(
                  child: EmptyMark(
                    child: _EmptyBlock(hostName: widget.hostName),
                  ),
                )
              : _NotificationList(
                  unread: unread,
                  read: read,
                  color: color,
                  onOpenPane: widget.onOpenPane,
                  onMarkSeen: (String id) => _run(widget.onMarkSeen(id)),
                  onRemove: (String id) => _run(widget.onRemove(id)),
                  onOpenActions: _showRowActions,
                  now: widget.now,
                ),
        ),
      ],
    );
    // R-32-115, R-32-510: `color.bg.base` on both platforms. No edge under the bar: the strip
    // below carries the header block's one hairline (R-32-582).
    if (_isIos) {
      return CupertinoPageScaffold(
        backgroundColor: color.bgBase,
        navigationBar: CupertinoNavigationBar(
          backgroundColor: color.bgBase,
          border: null,
          middle: title,
        ),
        child: body,
      );
    }
    return Scaffold(
      backgroundColor: color.bgBase,
      appBar: AppBar(
        backgroundColor: color.bgBase,
        elevation: 0,
        // The list scrolls under the strip, never under the bar, and the block keeps one
        // surface: no Material scroll-under tint.
        scrolledUnderElevation: 0,
        title: title,
      ),
      body: body,
    );
  }
}

/// Callouts 2 and 3: the strip of two bulk controls under the title, on `color.bg.base`, closed
/// by the header block's one `border.hairline` in `color.border.strong` (R-32-582). Each control
/// is the one text button of `app_text_button.dart`, the platform's own (R-03-059, 2026-09-09),
/// with its R-32-401 glyph before the label. On Android the button carries the `space.3` inset
/// of R-32-526 from `textButtonTheme`, so the strip insets `space.1` and the first glyph and the
/// last label edge land on the `space.4` column every row's text and menu glyph share (R-30-230,
/// R-32-510). On iOS the Cupertino button's own inset already exceeds `space.4`, so the strip
/// adds none. `Remove all` is destructive and takes `treat.destructive`'s ink through the
/// button's own `destructive` form (R-32-506, R-32-527).
class _BulkActions extends StatelessWidget {
  const _BulkActions({required this.onMarkAllRead, required this.onRemoveAll});

  /// `null` while no row is unread (R-32-502); the empty `NEW` line says why.
  final VoidCallback? onMarkAllRead;

  /// `null` while the list is empty (R-32-502); the empty state says why.
  final VoidCallback? onRemoveAll;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.bgBase,
        border: Border(
          bottom: BorderSide(
            color: color.borderStrong,
            width: AppBorder.hairline,
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: _isIos
              ? AppSpace.space0
              : AppSpace.space4 - AppSpace.space3,
        ),
        child: Row(
          children: <Widget>[
            AppTextButton(
              // `Mark as seen` in the R-32-401 map.
              icon: Symbols.done_all_rounded,
              label: 'Mark all read',
              onPressed: onMarkAllRead,
            ),
            const Expanded(child: SizedBox.shrink()),
            AppTextButton(
              // `Remove all notifications, destructive` in the R-32-401 map (2026-09-08).
              icon: Symbols.delete_sweep_rounded,
              label: 'Remove all',
              destructive: true,
              onPressed: onRemoveAll,
            ),
          ],
        ),
      ),
    );
  }
}

/// Callout 11's in-row actions control, the platform's own icon button (R-03-059, 2026-09-09):
/// a plain `IconButton` on Android, whose `size.target.min` box, `radius.sm` and
/// `color.fg.primary` ink come from `iconButtonTheme` in `app.dart`; a plain `CupertinoButton`
/// on iOS in the component's own `kMinInteractiveDimensionCupertino` box, inked in
/// `CupertinoThemeData.primaryColor`. Neither sits in a box of this screen's making (the
/// R-03-059 addendum, 2026-09-09). The glyph is `size.icon.md`, and [label] is the spoken
/// action name (R-32-505), on Android also the tooltip.
class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Widget glyph = Icon(icon, size: AppSize.iconMd, semanticLabel: label);
    if (_isIos) {
      return CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onTap,
        child: glyph,
      );
    }
    return IconButton(icon: glyph, tooltip: label, onPressed: onTap);
  }
}

/// The `Empty` state (callout 13, R-31-07-10, amended 2026-09-09 per R-03-107): left aligned at
/// `space.4` on the ground grid, the title `No notifications.` in `type.title`, the display face
/// of the screen titles, in `color.accent.text`, and the hint under it in `type.body`
/// `color.fg.secondary` (`docs/32-design-language.md` section 7.19). No eyebrow and no rule:
/// the product owner removed both on 2026-09-08.
class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock({required this.hostName});

  final String hostName;

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
          Text(
            'No notifications.',
            style: AppType.title.copyWith(color: color.accentText),
          ),
          const SizedBox(height: AppSpace.space2),
          Text(
            'Agent status changes on $hostName appear here.',
            style: AppType.body.copyWith(color: color.fgSecondary),
          ),
        ],
      ),
    );
  }
}

/// A fixed-height pinned sliver header, per R-32-569's fixed header height. The shape of
/// `agent_list_screen.dart`'s own delegate, duplicated per this file's header note.
class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _PinnedHeaderDelegate({required this.child});

  final Widget child;

  @override
  double get minExtent => AppSize.header;

  @override
  double get maxExtent => AppSize.header;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => child;

  @override
  bool shouldRebuild(covariant _PinnedHeaderDelegate oldDelegate) =>
      oldDelegate.child != child;
}

/// The two groups of callout 4 (R-31-07-11): `NEW` over the unread rows, `EARLIER` over the read
/// rows, each an upper-case tier header of R-32-563 that pins only while its own group is on
/// screen (R-32-569, one `SliverMainAxisGroup` per group, the agent list's own construction) on
/// the `color.bg.base` surface the header table gives it. `NEW` is always drawn: with nothing
/// unread it carries the one line of callout 12, so the absence is as visible as a row would be.
/// `EARLIER` is drawn only while a read row exists. The first header follows the strip by the
/// `space.6` group gap of R-32-582, and the two groups sit one R-30-231 group gap (`space.6`)
/// apart on the screen's plain `color.bg.base` (R-03-107, amended 2026-09-09). The list ends
/// with its last row (R-03-109).
class _NotificationList extends StatelessWidget {
  const _NotificationList({
    required this.unread,
    required this.read,
    required this.color,
    required this.onOpenPane,
    required this.onMarkSeen,
    required this.onRemove,
    required this.onOpenActions,
    required this.now,
  });

  final List<NotificationItem> unread;
  final List<NotificationItem> read;
  final AppColor color;
  final void Function(String paneId) onOpenPane;
  final void Function(String paneId) onMarkSeen;
  final void Function(String paneId) onRemove;
  final void Function(NotificationItem entry) onOpenActions;
  final DateTime Function() now;

  Widget _header(String label) => SliverPersistentHeader(
    pinned: true,
    delegate: _PinnedHeaderDelegate(
      child: ColoredBox(
        color: color.bgBase,
        child: AppSectionHeader.upperCase(label: label),
      ),
    ),
  );

  Widget _rows(List<NotificationItem> entries) => SliverList(
    delegate: SliverChildBuilderDelegate(
      (BuildContext context, int index) => _NotificationRow(
        // R-30-299: the row's identity is its pane, never its index, so its reveal state
        // follows it across a re-sort or a move between the two groups.
        key: ValueKey<String>(entries[index].item.paneId),
        entry: entries[index],
        color: color,
        // The last row of a group carries no divider (owner decision, 2026-09-03).
        showDivider: index < entries.length - 1,
        onOpenPane: onOpenPane,
        onMarkSeen: onMarkSeen,
        onRemove: onRemove,
        onOpenActions: onOpenActions,
        now: now,
      ),
      childCount: entries.length,
    ),
  );

  @override
  Widget build(BuildContext context) => SlidableAutoCloseBehavior(
    child: CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.only(top: AppSpace.space6),
          sliver: SliverMainAxisGroup(
            slivers: <Widget>[
              _header(newHeaderLabel),
              if (unread.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.space4,
                      vertical: AppSpace.space3,
                    ),
                    child: Text(
                      noNewSentence,
                      style: AppType.body.copyWith(color: color.fgSecondary),
                    ),
                  ),
                )
              else
                _rows(unread),
            ],
          ),
        ),
        if (read.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.only(top: AppSpace.space6),
            sliver: SliverMainAxisGroup(
              slivers: <Widget>[_header(earlierHeaderLabel), _rows(read)],
            ),
          ),
      ],
    ),
  );
}

/// One row plus its two reveals (R-31-07-09): a swipe toward the trailing edge reveals `Remove`
/// on every row; a swipe toward the leading edge reveals `Mark as read` on an unread row only (a
/// read row gets no dead affordance). Stateful for one reason: it owns the [_SnapController]
/// that settles both reveals on the motion tokens.
class _NotificationRow extends StatefulWidget {
  const _NotificationRow({
    super.key,
    required this.entry,
    required this.color,
    required this.showDivider,
    required this.onOpenPane,
    required this.onMarkSeen,
    required this.onRemove,
    required this.onOpenActions,
    required this.now,
  });

  final NotificationItem entry;
  final AppColor color;
  final bool showDivider;
  final void Function(String paneId) onOpenPane;
  final void Function(String paneId) onMarkSeen;
  final void Function(String paneId) onRemove;
  final void Function(NotificationItem entry) onOpenActions;
  final DateTime Function() now;

  @override
  State<_NotificationRow> createState() => _NotificationRowState();
}

class _NotificationRowState extends State<_NotificationRow>
    with SingleTickerProviderStateMixin {
  late final _SnapController _controller = _SnapController(this);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Measure the platform label and reserve the native button padding and glyph.
  double _actionWidth(BuildContext context, String label) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: label,
        style: _isIos
            ? CupertinoTheme.of(context).textTheme.actionTextStyle
            : Theme.of(context).textTheme.labelLarge,
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final double width =
        painter.width +
        (_isIos ? AppSpace.space5 : AppSpace.space4) * 2 +
        AppSize.iconMd +
        AppSpace.space2;
    painter.dispose();
    return math.max(AppSize.targetMin, width);
  }

  ActionPane _pane(
    BoxConstraints constraints, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool leading,
  }) {
    final double width = _actionWidth(context, label);
    return ActionPane(
      motion: const ScrollMotion(),
      dragDismissible: false,
      // R-32-576: the pane extent is its action's width, never a fixed fraction.
      extentRatio: math.min(1, width / constraints.maxWidth),
      children: <Widget>[
        _SwipeAction(icon: icon, label: label, leading: leading, onTap: onTap),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final NotificationItem entry = widget.entry;
    final String paneId = entry.item.paneId;
    _controller.reduceMotion = MediaQuery.disableAnimationsOf(context);
    void markRead() => widget.onMarkSeen(paneId);
    void remove() => widget.onRemove(paneId);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) => Slidable(
        controller: _controller,
        groupTag: _slidableGroupTag,
        startActionPane: entry.seen
            ? null
            : _pane(
                constraints,
                // `Mark as seen` in the R-32-401 map.
                icon: Symbols.done_all_rounded,
                label: 'Mark as read',
                onTap: markRead,
                leading: true,
              ),
        endActionPane: _pane(
          constraints,
          // `Remove one notification, destructive` in the R-32-401 map (2026-09-08).
          icon: Symbols.delete_outline_rounded,
          label: 'Remove',
          onTap: remove,
          leading: false,
        ),
        child: _RowContent(
          entry: entry,
          color: widget.color,
          showDivider: widget.showDivider,
          onTap: () => widget.onOpenPane(paneId),
          onActions: () => widget.onOpenActions(entry),
          now: widget.now,
          customActions: <CustomSemanticsAction, VoidCallback>{
            if (!entry.seen)
              const CustomSemanticsAction(label: 'Mark as read'): markRead,
            const CustomSemanticsAction(label: 'Remove'): remove,
          },
        ),
      ),
    );
  }
}

/// A platform action inside the existing swipe reveal.
class _SwipeAction extends StatelessWidget {
  const _SwipeAction({
    required this.icon,
    required this.label,
    required this.leading,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool leading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    void act() {
      onTap();
      unawaited(Slidable.of(context)?.close());
    }

    final Widget glyph = Icon(
      icon,
      size: AppSize.iconMd,
      color: leading ? null : color.statusError,
    );
    return Expanded(
      child: ColoredBox(
        color: color.bgRaised,
        child: Center(
          child: _isIos
              ? CupertinoButton(
                  onPressed: act,
                  foregroundColor: color.accentText,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      glyph,
                      const SizedBox(width: AppSpace.space2),
                      Text(label),
                    ],
                  ),
                )
              : TextButton.icon(
                  onPressed: act,
                  icon: glyph,
                  label: Text(label),
                ),
        ),
      ),
    );
  }
}

/// A native action row in the notification sheet.
class _SheetActionRow extends StatelessWidget {
  const _SheetActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChromeListRow.sheet(
    title: label,
    leading: Icon(icon, size: AppSize.iconMd),
    destructive: icon == Symbols.delete_outline_rounded,
    onTap: onTap,
  );
}

/// A native notification row with its status, age, and action menu.
class _RowContent extends StatelessWidget {
  const _RowContent({
    required this.entry,
    required this.color,
    required this.showDivider,
    required this.onTap,
    required this.onActions,
    required this.now,
    required this.customActions,
  });
  final NotificationItem entry;
  final AppColor color;
  final bool showDivider;
  final VoidCallback onTap;
  final VoidCallback onActions;
  final DateTime Function() now;
  final Map<CustomSemanticsAction, VoidCallback> customActions;

  @override
  Widget build(BuildContext context) {
    final String phrase = _phraseFor(entry);
    final String? age = _formatAge(entry.item.at, now: now);
    final List<String> segments = _segmentsFor(entry);
    final String semanticsLabel = <String>[
      segments.join(', '),
      ?age,
      if (!entry.seen) 'unread',
    ].join(', ');
    return AppListRow(
      semanticsValue: semanticsLabel,
      customSemanticsActions: customActions,
      preserveTrailingSemantics: true,
      primary: phrase,
      primaryWidget: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Expanded(
              child: Text(
                phrase,
                style: (entry.seen ? AppType.body : AppType.bodyStrong)
                    .copyWith(color: color.fgPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (age != null) ...<Widget>[
              const SizedBox(width: AppSpace.space3),
              Text(
                age,
                style: AppType.caption.copyWith(color: color.fgSecondary),
              ),
            ],
          ],
        ),
      ),
      secondary: segments.join(_breadcrumbSeparator),
      selected: !entry.seen,
      state: _barStateFor(entry.item.status),
      showDivider: showDivider,
      contentPadding: EdgeInsets.only(
        left: AppSpace.space4,
        right: AppSpace.space4 - _menuGlyphInset,
      ),
      trailing: _IconAction(
        icon: Symbols.more_vert_rounded,
        label: 'Notification actions',
        onTap: onActions,
      ),
      onTap: onTap,
    );
  }
}

/// Callout 5: the agent kind and the status word as one phrase, `omp is done`, the same phrase
/// the system notification's title carries (R-31-12-01), so the row reads as the alert it logs.
String _phraseFor(NotificationItem entry) =>
    '${entry.item.agentKind} is ${_statusWord(entry.item.status)}';

/// R-30-510: the segments are `agent_status`'s own `tab_title`/`pane_title`, plus the space name
/// the service joined from the tree; an empty segment is skipped, never drawn blank (callout 6).
List<String> _segmentsFor(NotificationItem entry) => <String>[
  entry.item.spaceName,
  entry.item.tabTitle,
  entry.item.paneTitle,
].where((String s) => s.isNotEmpty).toList();

String _statusWord(AgentStatusKind status) => switch (status) {
  AgentStatusKind.idle => 'idle',
  AgentStatusKind.working => 'working',
  AgentStatusKind.blocked => 'blocked',
  AgentStatusKind.done => 'done',
  AgentStatusKind.unknown => 'unknown',
};

/// The state bar's state for the status the phrase names (callout 8, R-03-100).
BarState _barStateFor(AgentStatusKind status) => switch (status) {
  AgentStatusKind.idle => BarState.idle,
  AgentStatusKind.working => BarState.working,
  AgentStatusKind.blocked => BarState.blocked,
  AgentStatusKind.done => BarState.done,
  AgentStatusKind.unknown => BarState.unknown,
};

/// The relative age of R-30-405's format, `null` when the Host reported no time (R-11-224).
String? _formatAge(String? at, {DateTime Function() now = DateTime.now}) {
  if (at == null) return null;
  final DateTime? parsed = DateTime.tryParse(at);
  if (parsed == null) return null;
  final int totalSeconds = now()
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
