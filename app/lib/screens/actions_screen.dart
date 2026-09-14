/// The Host plugin actions screen (`WP-18-f`, wave 9 of `docs/90-implementation-plan.md`),
/// drawn from `docs/31-mockups/18-actions.md` at route `/hosts/:hostId/panes/:paneId/actions`
/// (`docs/30-ux-spec.md` row 18). Lists a Herdr plugin's published actions as rows, grouped by
/// `plugin_id`, and invokes one by `action_id` through `host_actions.dart`'s `invokeAction`.
///
/// This file owns no route: `app/lib/routing.dart` (`WP-12-b`, on request per `docs/90` §5.3)
/// wires the route to this widget, and supplies [messages], [connectionState] and [send] from
/// the live `RelayConnection` it already holds — the same three-argument shape
/// `device_list_screen.dart` uses, passed through rather than the whole connection object, for
/// that file's own documented reason. [onOpenPane] is this screen's whole navigation contract,
/// mirroring `DeviceListScreen.onRemovedThisPhone`'s "a caller adapts its own outcome" idiom: a
/// `null` value is a deliberate no-op (R-90-016).
///
/// [scope] carries what this phone is viewing, per `host_actions.dart`'s own `ActionScope` doc
/// comment. Since 2026-09-09 (R-03-055, R-31-18-01) the one entry point is the `Plugin actions`
/// row of the pane action sheet, so the caller supplies the pane on screen: `routing.dart`
/// resolves the workspace `name`, the tab `title` and the pane display name from the tree
/// snapshot, per R-31-18-05's "sourced by whichever caller supplies them", and this file never
/// reads the tree itself. The default "computer alone" scope stays as the caller's fallback for
/// a tree it could not read, and every gating and sentence path here holds for either
/// (R-31-18-05). History: the `Agents` app bar carried a computer-scoped entry from 2026-09-04
/// to 2026-09-09, and the terminal app bar a pane-scoped one from 2026-09-03 to 2026-09-08.
///
/// `ponytail`: the pane-offer strip of R-31-18-13 draws only the action title and "opened a
/// pane", never the second-line breadcrumb the rule also names, because resolving a bare
/// `pane_id` into workspace/tab/pane names needs the live tree snapshot, which is `tree.dart`'s
/// (`WP-18-c`) undeclared dependency from this package's `Needs.` line. Upgrade path: once a
/// shared "current tree" read exists for a screen that does not own `tree.dart`, resolve
/// `_PaneOffer.paneId` through it and restore the breadcrumb line.
library;

import 'dart:async' show StreamSubscription, Timer, unawaited;

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoNavigationBar, CupertinoPageScaffold;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart'
    show
        Align,
        Alignment,
        AnimatedContainer,
        Border,
        BorderRadius,
        BorderSide,
        BoxConstraints,
        BoxDecoration,
        BuildContext,
        Column,
        ConstrainedBox,
        CrossAxisAlignment,
        CustomScrollView,
        DecoratedBox,
        EdgeInsets,
        Expanded,
        MainAxisAlignment,
        MainAxisSize,
        MediaQuery,
        Opacity,
        Padding,
        SafeArea,
        Row,
        Semantics,
        SizedBox,
        SliverList,
        State,
        StatefulWidget,
        StatelessWidget,
        Text,
        TextOverflow,
        TextStyle,
        VoidCallback,
        Widget;
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart'
    show
        AppBar,
        CircularProgressIndicator,
        Colors,
        Container,
        Icon,
        PreferredSize,
        Scaffold,
        ScaffoldMessenger,
        SelectionArea,
        Size,
        SnackBar;

import '../core/result/result.dart' show Err, Ok, Result;
import '../models/codes.dart' show ErrorCode;
import '../models/message.dart';
import '../models/messages/action_list_entry.dart';
import '../services/host_actions.dart';
import '../services/relay.dart'
    show
        RelayConnected,
        RelayConnectionState,
        RelayRegistrationError,
        RelayRegistrationErrorCode;
import '../widgets/app_ground.dart' show EmptyMark;
import '../widgets/app_section_header.dart';
import '../widgets/app_strip.dart';
import '../widgets/app_text_button.dart';
import '../widgets/ground_grid.dart' show GroundGrid;
import '../widgets/theme/app_color.dart';
import '../widgets/theme/app_haptic.dart';
import '../widgets/theme/app_pressable.dart' show AppPressable;
import '../widgets/theme/app_radius.dart';
import '../widgets/theme/app_size.dart';
import '../widgets/theme/app_space.dart';
import '../widgets/theme/app_type.dart';
import '../widgets/theme/chrome_loading_delay.dart';
import '../widgets/treatments.dart';

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

/// `opacity.disabled`, per `docs/32-design-language.md`'s opacity table beside R-32-330. See
/// `app_text_button.dart`'s sibling constant for why this is a local constant rather than a
/// token import.
const double _opacityDisabled = 0.38;

/// `border.hairline`, per `docs/32-design-language.md` R-32-330. See `about_screen.dart`'s
/// sibling constant for why this is a local constant rather than a token import.
const double _hairlineWidth = 1;

/// The breadcrumb separator, `›` (U+203A) with a hair space on each side, per R-32-572,
/// matching `notifications_screen.dart`'s own constant.
const String _breadcrumbSeparator = '\u2009\u203A\u2009';

/// The skeleton bar widths of section 7.22's anatomy table (`first bar 140 wide and second 90
/// wide`), the same two `agent_list_screen.dart`'s skeleton draws.
const double _skeletonFirstBarWidth = 140;
const double _skeletonSecondBarWidth = 90;

enum _Phase { loading, loaded, listError, outcomeUnknown }

/// R-30-940 (`host_in_use`) and the generic offline case both dim the list and disable every
/// row, per R-30-807; only the header strip's sentence differs.
enum _LiveConnection { connected, hostInUse, offline }

/// The pending pane-offer strip of R-31-18-13.
class _PaneOffer {
  const _PaneOffer({required this.title, required this.paneId});
  final String title;
  final String paneId;
}

class ActionsScreen extends StatefulWidget {
  const ActionsScreen({
    super.key,
    required this.hostId,
    required this.hostName,
    required this.messages,
    required this.connectionState,
    required this.send,
    this.scope = const ActionScope(),
    this.onOpenPane,
  });

  /// The connected computer's `host_id`, carried in the route (R-31-18-01) and passed straight
  /// through to [onOpenPane].
  final String hostId;

  /// The connected computer's display name, for the app bar title and every sentence that
  /// names it (callout 4).
  final String hostName;

  final Stream<Message> messages;
  final Stream<RelayConnectionState> connectionState;
  final SendFrame send;

  /// What this phone is viewing (see this file's own header comment and `host_actions.dart`'s
  /// `ActionScope`). Defaults to "the computer alone in scope".
  final ActionScope scope;

  /// Fired when an acknowledgement names a pane and the person takes the offered route
  /// (R-30-520, R-31-18-13). `null` is a deliberate no-op (R-90-016): this screen offers the
  /// route but MUST NOT navigate on its own.
  final void Function(String hostId, String paneId)? onOpenPane;

  @override
  State<ActionsScreen> createState() => _ActionsScreenState();
}

class _ActionsScreenState extends State<ActionsScreen> {
  _Phase _phase = _Phase.loading;
  List<ActionListEntry>? _rawEntries;
  String? _errorText;
  DateTime? _lastReadAt;
  _LiveConnection _connection = _LiveConnection.connected;
  bool _showSkeleton = false;
  final Set<String> _collapsedPluginIds = <String>{};
  String? _invokingKey;
  String? _lastInvokedTitle;
  String? _invokeStaleText;
  String? _invokeStaleCode;
  _PaneOffer? _paneOffer;

  late final ActionListCache _cache;
  StreamSubscription<Result<List<ActionListEntry>>>? _resultsSub;
  StreamSubscription<RelayConnectionState>? _connectionSub;
  Timer? _skeletonTimer;

  @override
  void initState() {
    super.initState();
    _cache = ActionListCache(
      messages: widget.messages,
      connectionState: widget.connectionState,
      send: widget.send,
    );
    _resultsSub = _cache.results.listen(_onResult);
    _connectionSub = widget.connectionState.listen(_onConnectionState);
    _skeletonTimer = Timer(ChromeLoadingDelay.skeleton, () {
      if (mounted && _phase == _Phase.loading) {
        setState(() => _showSkeleton = true);
      }
    });
    unawaited(_cache.refresh());
  }

  @override
  void dispose() {
    unawaited(_resultsSub?.cancel());
    unawaited(_connectionSub?.cancel());
    _skeletonTimer?.cancel();
    _cache.dispose();
    super.dispose();
  }

  void _onConnectionState(RelayConnectionState state) {
    final _LiveConnection next = switch (state) {
      RelayConnected() => _LiveConnection.connected,
      RelayRegistrationError(:final code)
          when code == RelayRegistrationErrorCode.hostInUse =>
        _LiveConnection.hostInUse,
      _ => _LiveConnection.offline,
    };
    if (mounted) setState(() => _connection = next);
  }

  void _onResult(Result<List<ActionListEntry>> result) {
    if (!mounted) return;
    switch (result) {
      case Ok<List<ActionListEntry>>(:final value):
        setState(() {
          // R-31-18-16: the whole `herdr-relay` group is removed before anything else draws,
          // and before it can be counted in the hidden-row line.
          _rawEntries = value
              .where((ActionListEntry e) => e.pluginId != 'herdr-relay')
              .toList();
          _phase = _Phase.loaded;
          _lastReadAt = DateTime.now();
          _invokeStaleText = null;
          _invokeStaleCode = null;
        });
      case Err<List<ActionListEntry>>(:final message):
        if (_rawEntries == null) {
          setState(() {
            _phase = _Phase.listError;
            _errorText = message;
          });
        }
      // else: a background refresh failed (a reconnect race, or a "Refresh actions" that lost
      // the link again). The last-known list stays on screen per R-30-805; `_connection`
      // already reflects offline/host-in-use separately.
    }
  }

  bool get _rowsDisabled =>
      _invokingKey != null ||
      _connection != _LiveConnection.connected ||
      _phase == _Phase.outcomeUnknown;

  Future<void> _invoke(ActionListEntry entry) async {
    if (_rowsDisabled) return;
    final String key = '${entry.pluginId}::${entry.actionId}';
    setState(() {
      _invokingKey = key;
      _lastInvokedTitle = entry.title;
      _invokeStaleText = null;
      _invokeStaleCode = null;
      _paneOffer = null;
    });
    final InvokeOutcome outcome = await invokeAction(
      messages: widget.messages,
      connectionState: widget.connectionState,
      send: widget.send,
      pluginId: entry.pluginId,
      actionId: entry.actionId,
      scope: widget.scope,
    );
    if (!mounted) return;
    switch (outcome) {
      case InvokeSucceeded(:final paneId):
        unawaited(AppHaptic.commit());
        setState(() {
          _invokingKey = null;
          _phase = _Phase.loaded;
          _paneOffer = paneId == null
              ? null
              : _PaneOffer(title: entry.title, paneId: paneId);
        });
        if (paneId == null) {
          _showSnackbar('Sent ${entry.title}. Agents shows what exists now.');
        }
      case InvokeRefused(:final code):
        unawaited(AppHaptic.error());
        setState(() {
          _invokingKey = null;
          _invokeStaleCode = code.wireValue;
          _invokeStaleText = code == ErrorCode.pluginDisabled
              ? '${entry.pluginId} is switched off on ${widget.hostName}.'
              : 'Could not run that action on ${widget.hostName}.';
        });
        if (code == ErrorCode.pluginDisabled) _cache.notePluginDisabled();
      case InvokeOutcomeUnknown():
        setState(() {
          _invokingKey = null;
          _phase = _Phase.outcomeUnknown;
        });
    }
  }

  void _showSnackbar(String message) {
    final AppColor color = AppColor.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color.bgRaised,
        content: Text(
          message,
          style: AppType.body.copyWith(color: color.fgPrimary),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    // `type.heading` in `color.fg.primary`, matching `about_screen.dart` and
    // `settings_screen.dart`'s own app-bar titles (R-32-150: `color.fg.primary` on
    // `color.bg.base`, 8.14 dark / 8.01 light, floor 4.5, pass AAA). Plain `Text(title)`
    // left this title in the platform's own default typeface, off `type.heading` and off
    // `IBM Plex Sans` alike, which mismatched every other line of text on this screen.
    final Widget titleText = Text(
      'Actions on ${widget.hostName}',
      style: AppType.heading.copyWith(color: color.fgPrimary),
    );
    // Under the Agents branch the bottom bar already absorbs the system inset, so this
    // `SafeArea` measures 0 there (measured 2026-09-03); it is kept because the screen also
    // has to hold up on a viewport whose bar is gone. R-03-107 (amended 2026-09-09): a screen
    // with content paints plain `color.bg.base`, so the list, the skeleton and the error block
    // sit on the bare surface; only the empty state takes the ground grid ([_buildLoaded]).
    final Widget body = SafeArea(top: false, child: _buildBody(context));
    // `color.bg.base` with a `border.hairline`-wide `color.border.strong` bottom edge, per
    // R-32-115 and R-32-510, on both platforms (the edge drew `color.border.subtle` until
    // 2026-09-08; Main confirmed one strong edge on every screen). A bare
    // `Scaffold`/`AppBar`/`CupertinoPageScaffold` left this screen on the platform's own
    // default surface colour instead, which drifted from the chrome palette on iOS and from
    // every sibling screen on Android; `elevation: 0` on the Android `AppBar` turns off
    // Material's own shadow-based edge so this explicit one is the only one drawn.
    if (_isIos) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          backgroundColor: color.bgBase,
          border: Border(
            bottom: BorderSide(
              color: color.borderStrong,
              width: _hairlineWidth,
            ),
          ),
          middle: titleText,
        ),
        child: body,
      );
    }
    return Scaffold(
      backgroundColor: color.bgBase,
      appBar: AppBar(
        backgroundColor: color.bgBase,
        elevation: 0,
        title: titleText,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(_hairlineWidth),
          child: Container(color: color.borderStrong, height: _hairlineWidth),
        ),
      ),
      body: body,
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_phase) {
      case _Phase.loading:
        return _showSkeleton ? const _SkeletonList() : const SizedBox.shrink();
      case _Phase.listError:
        return _ErrorBlock(
          hostName: widget.hostName,
          text: _errorText ?? '',
          onRetry: () => unawaited(_cache.refresh()),
        );
      case _Phase.loaded:
      case _Phase.outcomeUnknown:
        return _buildLoaded(context);
    }
  }

  Widget _buildLoaded(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final List<ActionListEntry> raw = _rawEntries!;
    final String timeLabel = _lastReadAt == null
        ? ''
        : _formatTime(_lastReadAt!.toLocal());

    final List<Widget> banners = <Widget>[
      if (_connection == _LiveConnection.hostInUse)
        AppStrip(
          child: Treatment.warning(
            label:
                'Another phone is using this computer. This list is from $timeLabel.',
          ),
        ),
      if (_connection == _LiveConnection.offline)
        // `treat.error` in a strip carries its own `border.attention` bar (R-32-506), so the
        // strip itself draws none: two bars at one edge read as a box.
        AppStrip(
          child: Treatment.error(
            label: 'Offline. This list is from $timeLabel.',
            inStrip: true,
          ),
        ),
    ];

    if (raw.isEmpty) {
      // R-03-107: the empty state is the one place this screen paints the ground grid, with
      // the mark behind its block.
      return Column(
        children: <Widget>[
          ...banners,
          Expanded(
            child: GroundGrid(
              child: EmptyMark(
                child: _NoPluginEmptyState(hostName: widget.hostName),
              ),
            ),
          ),
        ],
      );
    }

    final GatedActions gated = gateActions(raw, widget.scope);
    final Map<String, List<ActionListEntry>> groups =
        <String, List<ActionListEntry>>{};
    for (final ActionListEntry entry in gated.visible) {
      groups.putIfAbsent(entry.pluginId, () => <ActionListEntry>[]).add(entry);
    }

    return Column(
      children: <Widget>[
        ...banners,
        if (_paneOffer != null) _paneOfferStrip(color),
        if (_phase == _Phase.outcomeUnknown) _outcomeUnknownStrip(color),
        if (_invokeStaleText != null) _staleErrorStrip(color),
        Expanded(
          // The list ends with its last strip or row (R-03-109): no clearance below it.
          child: CustomScrollView(
            slivers: <Widget>[
              SliverList.list(
                children: <Widget>[
                  _scopeStrip(color),
                  for (final String pluginId in groups.keys) ...<Widget>[
                    AppSectionHeader.tier1(
                      label: pluginId,
                      expanded: !_collapsedPluginIds.contains(pluginId),
                      count:
                          '${groups[pluginId]!.length} action${groups[pluginId]!.length == 1 ? '' : 's'}',
                      onToggle: () => setState(() {
                        if (_collapsedPluginIds.contains(pluginId)) {
                          _collapsedPluginIds.remove(pluginId);
                        } else {
                          _collapsedPluginIds.add(pluginId);
                        }
                      }),
                    ),
                    if (!_collapsedPluginIds.contains(pluginId))
                      for (final (int i, ActionListEntry entry)
                          in groups[pluginId]!.indexed)
                        _actionRow(
                          context,
                          entry,
                          // 7.4: the last row of a section carries no divider (owner
                          // decision, 2026-09-03); the next section header separates it.
                          showDivider: i < groups[pluginId]!.length - 1,
                        ),
                  ],
                  if (gated.hiddenByScopeCount > 0)
                    _hiddenRowStrip(color, gated.hiddenByScopeCount),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _scopeStrip(AppColor color) {
    final ActionScope scope = widget.scope;
    final String label =
        scope.paneName ??
        scope.tabName ??
        scope.workspaceName ??
        widget.hostName;
    final String breadcrumb = <String?>[
      scope.workspaceName,
      scope.tabName,
      scope.paneName,
    ].whereType<String>().join(_breadcrumbSeparator);
    return AppStrip(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'A tap sends $label as the context.',
            style: AppType.caption.copyWith(color: color.fgSecondary),
          ),
          if (scope.paneId != null && breadcrumb.isNotEmpty)
            Text(
              breadcrumb,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.caption.copyWith(color: color.fgSecondary),
            ),
        ],
      ),
    );
  }

  Widget _hiddenRowStrip(AppColor color, int count) {
    final String verb = count == 1 ? 'needs' : 'need';
    final String noun = count == 1 ? 'action' : 'actions';
    return AppStrip(
      child: Text(
        '$count $noun $verb a tab or a pane.',
        style: AppType.caption.copyWith(color: color.fgSecondary),
      ),
    );
  }

  Widget _paneOfferStrip(AppColor color) {
    final _PaneOffer offer = _paneOffer!;
    return AppStrip(
      onTapDestination: () =>
          widget.onOpenPane?.call(widget.hostId, offer.paneId),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '${offer.title} opened a pane.',
              style: AppType.body.copyWith(color: color.fgPrimary),
            ),
          ),
          Icon(
            Symbols.chevron_right_rounded,
            size: AppSize.iconMd,
            color: color.fgSecondary,
          ),
        ],
      ),
    );
  }

  /// R-31-18-15, R-30-518: not an error, so no treatment and no bar; one sentence pair and the
  /// one control, `Refresh actions`, at the strip's leading edge under it.
  Widget _outcomeUnknownStrip(AppColor color) => AppStrip(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          '${_lastInvokedTitle ?? 'That action'} may have run on ${widget.hostName}. '
          'The link dropped before the answer came back.',
          style: AppType.body.copyWith(color: color.fgPrimary),
        ),
        const SizedBox(height: AppSpace.space3),
        _refreshAction(),
      ],
    ),
  );

  /// Callout 16, R-31-18-09: the sentence with `treat.error`, the raw code in `type.mono.code`
  /// `space.3` under it (section 7.20's gap), then `Refresh actions`.
  Widget _staleErrorStrip(AppColor color) => AppStrip(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Treatment.error(label: _invokeStaleText!, inStrip: true),
        const SizedBox(height: AppSpace.space3),
        Text(
          _invokeStaleCode!,
          style: AppType.monoCode.copyWith(color: color.fgPrimary),
        ),
        const SizedBox(height: AppSpace.space3),
        _refreshAction(),
      ],
    ),
  );

  /// A `Row` gives the text action tight constraints, so it sits at the strip's leading edge
  /// under the sentence instead of stretching across the strip and centring its label.
  Widget _refreshAction() => Row(
    children: <Widget>[
      AppTextButton(
        label: 'Refresh actions',
        onPressed: () => unawaited(_cache.refresh()),
      ),
    ],
  );

  Widget _actionRow(
    BuildContext context,
    ActionListEntry entry, {
    required bool showDivider,
  }) {
    final String key = '${entry.pluginId}::${entry.actionId}';
    return _ActionRow(
      pluginId: entry.pluginId,
      title: entry.title,
      description: entry.description,
      showDivider: showDivider,
      invoking: _invokingKey == key,
      onTap: _rowsDisabled ? null : () => unawaited(_invoke(entry)),
    );
  }
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

/// `14:02`, the last-read time this screen's offline/host-in-use banners cite (R-30-805).
String _formatTime(DateTime local) =>
    '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';

/// One action row, per R-31-18-03 and section 7.4: the `title` in `type.body.strong` over the
/// whole `description` in `type.caption`, wrapped and never clamped, both at the `space.4`
/// list inset with no leading icon, no chevron and no state word. The row is at least
/// `size.row.two_line` high (`size.row.one_line` with no description) and grows with the
/// description: the text lines plus `space.4` above and below. Divider: `border.hairline` in
/// `color.border.subtle`, inset `space.4`, none on the last row of a group. Pressed:
/// `color.bg.high` and the R-32-609 scale through [AppPressable]. Disabled: `opacity.disabled`
/// (R-32-502, R-31-18-17). [invoking]: the in-place spinner holds the title line's height so
/// the description does not jump (R-31-18-08), and the row is not dimmed.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.pluginId,
    required this.title,
    required this.description,
    required this.showDivider,
    required this.invoking,
    required this.onTap,
  });

  final String pluginId;
  final String title;
  final String? description;
  final bool showDivider;
  final bool invoking;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final bool active = onTap != null && !invoking;
    final TextStyle titleStyle = AppType.bodyStrong.copyWith(
      color: color.fgPrimary,
    );
    // `type.body.strong`'s own line height, so the spinner keeps the title line's box.
    final double titleLineHeight =
        titleStyle.fontSize! *
        titleStyle.height! *
        MediaQuery.textScalerOf(context).scale(1);
    final Widget titleLine = invoking
        ? SizedBox(
            height: titleLineHeight,
            child: const Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: AppSize.spinner,
                height: AppSize.spinner,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        : Text(title, style: titleStyle);
    final Widget row = AppPressable(
      onTap: active ? onTap : null,
      builder: (BuildContext context, bool pressed) => AnimatedContainer(
        duration: AppPressable.fillDuration(context, pressed),
        curve: AppPressable.fillCurve(context),
        color: pressed ? color.bgHigh : Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: description == null
                    ? AppSize.rowOneLine
                    : AppSize.rowTwoLine,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.space4,
                  vertical: AppSpace.space4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    titleLine,
                    if (description case final String text)
                      Text(
                        text,
                        style: AppType.caption.copyWith(
                          color: color.fgSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (showDivider)
              Padding(
                padding: const EdgeInsets.only(left: AppSpace.space4),
                child: Container(
                  height: _hairlineWidth,
                  color: color.borderSubtle,
                ),
              ),
          ],
        ),
      ),
    );
    // R-31-18-17: the button role, the whole label (plugin id, title, description) and the
    // enabled state; pending is a separate value, never spliced into the label.
    return Semantics(
      button: true,
      enabled: active,
      label: <String>[pluginId, title, ?description].join(', '),
      value: invoking ? 'pending' : null,
      onTap: active ? onTap : null,
      excludeSemantics: true,
      child: active || invoking
          ? row
          : Opacity(opacity: _opacityDisabled, child: row),
    );
  }
}

/// The two skeleton rows of the `Loading` state (R-32-560, section 7.22), shown only after a
/// 150 ms grace period: two bars per row, 140 and 90 wide, `size.skeleton` high, at
/// `radius.sm` in `color.bg.raised`, inside the row's own `space.4` inset, so each skeleton
/// row is `size.row.two_line` high like the row it stands for, on the screen's plain
/// `color.bg.base`. Never animated.
class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    Widget bar(double width) => Container(
      height: AppSize.skeleton,
      width: width,
      margin: const EdgeInsets.symmetric(vertical: AppSpace.space1),
      decoration: BoxDecoration(
        color: color.bgRaised,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
    );
    Widget row() => SizedBox(
      height: AppSize.rowTwoLine,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.space4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            bar(_skeletonFirstBarWidth),
            bar(_skeletonSecondBarWidth),
          ],
        ),
      ),
    );
    return Align(
      alignment: Alignment.topCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[row(), row()],
      ),
    );
  }
}

/// The `Error, list` state, per section 7.20 (R-32-555): `Could not read the actions on
/// patrick-desk.` with `treat.error`, the raw text in a selectable `type.mono.code` block on
/// `color.bg.raised` at `radius.md` behind a `color.border.strong` hairline, `space.3` under
/// the sentence, and exactly one `Try again` (R-30-803, R-30-804). Left aligned at `space.4`,
/// the shape of `agent_list_screen.dart`'s own block, on the screen's plain `color.bg.base`.
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
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Treatment.error(label: 'Could not read the actions on $hostName.'),
            const SizedBox(height: AppSpace.space3),
            DecoratedBox(
              decoration: BoxDecoration(
                color: color.bgRaised,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.fromBorderSide(
                  BorderSide(color: color.borderStrong, width: _hairlineWidth),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.space3),
                child: SelectionArea(
                  child: Text(
                    text,
                    style: AppType.monoCode.copyWith(color: color.fgPrimary),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.space3),
            Row(
              children: <Widget>[
                AppTextButton(label: 'Try again', onPressed: onRetry),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The no-plugin empty state (R-30-964's own carve-out, R-32-553; R-03-107, amended
/// 2026-09-09): left aligned at `space.4` on the ground grid, no illustration, naming the absent
/// thing in `type.title`, the display face of the screen titles, in `color.accent.text`, and
/// the next step under it in `type.body` `color.fg.secondary` (R-30-802;
/// `docs/32-design-language.md` section 7.19). No eyebrow: the app bar already names the
/// screen, the reason the notifications list lost its own on 2026-09-08.
class _NoPluginEmptyState extends StatelessWidget {
  const _NoPluginEmptyState({required this.hostName});
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
            'No plugin on $hostName offers an action.',
            style: AppType.title.copyWith(color: color.accentText),
          ),
          const SizedBox(height: AppSpace.space2),
          Text(
            'Install a Herdr plugin on the computer, then come back.',
            style: AppType.body.copyWith(color: color.fgSecondary),
          ),
        ],
      ),
    );
  }
}
