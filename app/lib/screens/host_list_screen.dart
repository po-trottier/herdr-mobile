/// The paired-computer list screen (Phase 18, `WP-18-a`, wave 9), drawn from
/// `docs/31-mockups/05-host-list.md` at route `/hosts` (`docs/30-ux-spec.md` row 05): the
/// rows, the connection glyph, the detail line, the attention badge, and the `Forget` action
/// every row carries behind a long press.
///
/// This file owns no route and no live `RelayConnection`: `app/lib/routing.dart` (`WP-12-b`,
/// on request) wires `/hosts` to this widget, and supplies [HostListScreen.onSwitch] and
/// [HostListScreen.onForget] as `host_list.dart`'s [switchToHost]/[forgetHost] bound to
/// whatever provider owns the app's one live connection — the same "take the pieces this
/// screen needs, not the whole object" idiom `device_list_screen.dart`'s own header comment
/// already establishes for `messages`/`connectionState`/`send` (R-90-024).
///
/// **The row-action pattern this file publishes for `WP-18-b`'s `agent_list_screen.dart`
/// to replicate** (R-30-296 to R-30-298, R-32-515, R-32-580): every row is one
/// `ChromeRowActions` keyed by its own stable row id, never a list index; its one item is
/// destructive and always raises `showChromeConfirmationDialog` first; and the row's own
/// `Semantics` widget adds `customSemanticsActions` around the tappable row content, which
/// merges into that content's own semantics node (neither sets `container: true`) rather than
/// adding a second node.
library;

import 'dart:async' show StreamSubscription, Timer, unawaited;

import 'package:connectivity_plus/connectivity_plus.dart'
    show Connectivity, ConnectivityResult;
import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoNavigationBar, CupertinoPageScaffold;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/widgets.dart'
    show
        Align,
        Alignment,
        Border,
        BorderRadius,
        BorderSide,
        BoxDecoration,
        BuildContext,
        Center,
        Column,
        CrossAxisAlignment,
        CustomScrollView,
        DecoratedBox,
        EdgeInsets,
        Expanded,
        Icon,
        MainAxisSize,
        Padding,
        Row,
        SafeArea,
        Semantics,
        SizedBox,
        SliverList,
        State,
        StatefulWidget,
        StatelessWidget,
        Text,
        ValueChanged,
        VoidCallback,
        Widget;
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart'
    show AppBar, Container, PreferredSize, Size, ValueKey;

import '../core/result/result.dart' show Result, Ok, Err;
import '../models/message.dart'
    show Message, MessageHostInfo, MessageTreeSnapshot;
import '../services/agent_status.dart' show AttentionItem;
import '../services/host_list.dart'
    show
        forgetStillListedSentence,
        formatLastSeenLong,
        sortHostRows,
        HostListRow,
        HostRowState,
        SwitchFailureReason,
        SwitchOutcome,
        SwitchSucceeded,
        SwitchFailed;
import '../services/plain_store.dart' show PairedHostRecord;
import '../services/relay.dart'
    show
        RelayConnectionState,
        RelayConnected,
        RelayDisconnected,
        RelayRegistrationError,
        RelayRegistrationErrorCode;
import '../widgets/app_ghost_button.dart';
import '../widgets/app_ground.dart' show EmptyMark;
import '../widgets/app_list_row.dart';
import '../widgets/app_strip.dart';
import '../widgets/app_text_button.dart';
import '../widgets/eyebrow.dart';
import '../widgets/ground_grid.dart' show GroundGrid;
import '../widgets/status_bar.dart' show BarState;
import '../widgets/theme/app_color.dart';
import '../widgets/theme/app_haptic.dart' show AppHaptic;
import '../widgets/theme/app_radius.dart';
import '../widgets/theme/app_size.dart';
import '../widgets/theme/app_space.dart' show AppSpace;
import '../widgets/theme/app_type.dart';
import '../widgets/theme/chrome_activity_indicator.dart';
import '../widgets/theme/chrome_confirmation_dialog.dart'
    show showChromeConfirmationDialog;
import '../widgets/theme/chrome_confirmation_outcome.dart'
    show ChromeConfirmationOutcome;
import '../widgets/theme/chrome_icon_action.dart';
import '../widgets/theme/chrome_loading_delay.dart';
import '../widgets/theme/chrome_menu.dart' show ChromeMenuItem;
import '../widgets/theme/chrome_row_actions.dart';
import '../widgets/theme/chrome_snackbar.dart';
import '../widgets/treatments.dart';

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

/// Callout 9: the hint under the last row names the gesture and the word, because a long
/// press is invisible (R-31-05-02).
const String _rowActionsHint = 'Touch and hold a row, then tap Forget.';

/// The text edge every host name starts on: the row inset of section 7.4. The connection state
/// is the leading bar of R-03-100 (2026-09-09), flush to the row's edge and outside the inset,
/// so the names start at `space.4` (2026-09-08: the names used to start on two different
/// edges, because the glyph carried a state word of varying width).
const double _textEdge = AppSpace.space4;

/// The one row action's label (callout 11).
const String _forgetLabel = 'Forget';

Future<bool> _defaultHasNetwork() async {
  final results = await Connectivity().checkConnectivity();
  return !results.contains(ConnectivityResult.none);
}

class HostListScreen extends StatefulWidget {
  const HostListScreen({
    super.key,
    required this.pairedHosts,
    required this.messages,
    required this.connectionState,
    this.initialConnectionState,
    required this.connectedHostId,
    required this.unseenAttention,
    required this.currentAttention,
    required this.thisDeviceName,
    required this.onSwitch,
    required this.onForget,
    this.hasNetwork = _defaultHasNetwork,
    this.onSwitched,
    this.onPairAnother,
    this.onOpenDiagnostics,
    this.attemptOnLoad = false,
  });

  /// Reads every saved computer's non-secret record (`PlainStore.pairedHosts`).
  final Future<Result<List<PairedHostRecord>>> Function() pairedHosts;

  /// The app's one live connection's frames, for the connected row's `tree_snapshot` agent
  /// count (R-11-044) and `host_info` display-name refresh (R-13-065).
  final Stream<Message> messages;

  final Stream<RelayConnectionState> connectionState;

  /// The link state when this screen opens. [connectionState] is a broadcast stream with no
  /// replay, so the pushed chooser (R-31-05-19) drew the connected computer as `saved` with
  /// a `LAST SEEN` line until the next emission (measured live, 2026-09-03). `null` reads as
  /// disconnected.
  final RelayConnectionState? initialConnectionState;

  /// Which paired computer [messages]/[connectionState] currently belong to, or `null`.
  final String? connectedHostId;

  final Stream<List<AttentionItem>> unseenAttention;
  final List<AttentionItem> currentAttention;

  /// This phone's own device name, for the `Forget` confirmation's R-31-05-03 sentence.
  final Future<String> Function() thisDeviceName;

  /// Performs one switch attempt (`host_list.dart`'s [switchToHost], bound to the app's live
  /// `RelayConnection` by whoever constructs this screen — R-90-024).
  final Future<SwitchOutcome> Function(PairedHostRecord target) onSwitch;

  /// Forgets a computer locally (`host_list.dart`'s [forgetHost], bound the same way).
  final Future<Result<void>> Function(PairedHostRecord target) onForget;

  /// Whether the phone currently has a network (R-30-947, R-30-806). Injectable for a test;
  /// defaults to a real `connectivity_plus` check.
  final Future<bool> Function() hasNetwork;

  /// A switch succeeded: the caller routes to `/hosts/:hostId/agents` with `context.go`,
  /// which clears every `:hostId` route from the stack on its own (R-30-948, R-30-949) — this
  /// screen owns no router.
  final ValueChanged<String>? onSwitched;

  /// `+` (callout 2) and `Pair again` on a rejected row: routes to `/pair/scan`.
  final VoidCallback? onPairAnother;

  /// The `Switch failed`/`Offline` strip and the `host_in_use` banner's `Why`: routes to
  /// `/hosts/:hostId/diagnostics` for the named computer (R-31-05-18).
  final ValueChanged<String>? onOpenDiagnostics;

  /// R-31-05-16: `true` for the one cold-start build of this screen, which then makes exactly
  /// one connection attempt to the newest last-seen computer once the records load.
  /// `routing.dart` hands out `true` once per app session and `false` for every later visit,
  /// so a return to this chooser (a deliberate `Disconnect`, R-31-13-14) never reconnects.
  final bool attemptOnLoad;

  @override
  State<HostListScreen> createState() => _HostListScreenState();
}

enum _Phase { loading, loaded, error }

/// One row's own failed-switch memory, scoped to that row until a new attempt starts or the
/// row is forgotten.
final class _Attempt {
  const _Attempt({
    required this.hostId,
    required this.reason,
    required this.detail,
  });
  final String hostId;
  final SwitchFailureReason reason;
  final String detail;
}

class _HostListScreenState extends State<HostListScreen> {
  _Phase _phase = _Phase.loading;
  List<PairedHostRecord> _records = const <PairedHostRecord>[];
  String? _errorText;
  bool _showSkeleton = false;
  Timer? _skeletonTimer;

  String? _connectedHostId;
  RelayConnectionState _liveState = const RelayDisconnected();
  int? _liveAgentCount;
  bool _hostInUseBanner = false;

  List<AttentionItem> _attention = const <AttentionItem>[];

  String? _pendingSwitchHostId;
  _Attempt? _lastAttempt;
  bool _coldStartAttempted = false;

  // ponytail: a one-shot `hasNetwork()` check, re-run before every switch attempt, rather
  // than a continuous OS connectivity stream. `connectivity_plus`'s `onConnectivityChanged`
  // is a platform EventChannel with no fake seam this screen can inject for a widget test;
  // add a live watcher once `WP-14-a`'s `ConnectivityWatcher` grows a public boolean stream a
  // screen can safely test against.
  bool _offline = false;

  StreamSubscription<Message>? _messagesSub;
  StreamSubscription<RelayConnectionState>? _connectionSub;
  StreamSubscription<List<AttentionItem>>? _attentionSub;

  @override
  void initState() {
    super.initState();
    _connectedHostId = widget.connectedHostId;
    _liveState = widget.initialConnectionState ?? const RelayDisconnected();
    _attention = widget.currentAttention;
    _messagesSub = widget.messages.listen(_onMessage);
    _connectionSub = widget.connectionState.listen(_onConnectionState);
    _attentionSub = widget.unseenAttention.listen((items) {
      if (mounted) setState(() => _attention = items);
    });
    _skeletonTimer = Timer(ChromeLoadingDelay.skeleton, () {
      if (mounted && _phase == _Phase.loading) {
        setState(() => _showSkeleton = true);
      }
    });
    unawaited(_recheckOffline());
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_messagesSub?.cancel());
    unawaited(_connectionSub?.cancel());
    unawaited(_attentionSub?.cancel());
    _skeletonTimer?.cancel();
    super.dispose();
  }

  Future<void> _recheckOffline() async {
    final has = await widget.hasNetwork();
    if (mounted) setState(() => _offline = !has);
  }

  Future<void> _load() async {
    if (_phase != _Phase.loading) setState(() => _phase = _Phase.loading);
    final result = await widget.pairedHosts();
    if (!mounted) return;
    switch (result) {
      case Ok<List<PairedHostRecord>>(:final value):
        setState(() {
          _records = value;
          _phase = _Phase.loaded;
        });
        _attemptColdStartOnce();
      case Err<List<PairedHostRecord>>(:final message):
        setState(() {
          _phase = _Phase.error;
          _errorText = message;
        });
    }
  }

  /// R-31-05-16: at a cold start, exactly one connection attempt, to the computer with
  /// the newest stored last-seen time; never a second one, and none when no computer
  /// carries a last-seen time or one is already connected. Runs the same single attempt
  /// a row tap runs, so the `Loading` state, R-31-05-17 and the failure strip of
  /// R-30-947 all come for free.
  void _attemptColdStartOnce() {
    if (!widget.attemptOnLoad || _coldStartAttempted) return;
    _coldStartAttempted = true;
    if (_liveState is RelayConnected || _pendingSwitchHostId != null) return;
    final id = _newestLastSeenHostId();
    if (id == null) return;
    for (final record in _records) {
      if (record.hostId == id) {
        unawaited(_handleRowTap(record));
        return;
      }
    }
  }

  void _onMessage(Message message) {
    if (!mounted) return;
    switch (message) {
      case MessageHostInfo(:final payload):
        setState(() => _connectedHostId = payload.hostId);
      case MessageTreeSnapshot(:final payload):
        setState(() => _liveAgentCount = payload.agents.length);
      default:
        break;
    }
  }

  void _onConnectionState(RelayConnectionState state) {
    if (!mounted) return;
    setState(() {
      _liveState = state;
      if (state is! RelayConnected) _liveAgentCount = null;
      // R-30-947: `host_in_use` on a background reconnect raises the R-30-940 banner only on
      // a screen already scoped to a computer (the pushed variant, `_connectedHostId` set);
      // a failed-switch `host_in_use` never reaches here as a [RelayRegistrationError] at
      // all — it is a [SwitchFailed] outcome from `widget.onSwitch`, handled in
      // [_handleRowTap], and the failed-switch strip is what R-30-947 wants for it instead.
      _hostInUseBanner =
          state is RelayRegistrationError &&
          state.code == RelayRegistrationErrorCode.hostInUse &&
          _connectedHostId != null;
    });
  }

  Future<void> _handleRowTap(PairedHostRecord record) async {
    if (_pendingSwitchHostId != null) {
      return; // R-31-05-17: one attempt at a time.
    }
    if (record.hostId == _connectedHostId && _liveState is RelayConnected) {
      widget.onSwitched?.call(
        record.hostId,
      ); // Already connected: the row just navigates.
      return;
    }
    final hasNetwork = await widget.hasNetwork();
    if (!mounted) return;
    if (!hasNetwork) {
      setState(() => _offline = true); // R-30-947: no attempt while offline.
      return;
    }
    setState(() {
      _offline = false;
      _pendingSwitchHostId = record.hostId;
      _lastAttempt = null;
    });
    final outcome = await widget.onSwitch(record);
    if (!mounted) return;
    switch (outcome) {
      case SwitchSucceeded(:final hostId):
        unawaited(AppHaptic.commit());
        setState(() {
          _pendingSwitchHostId = null;
          _connectedHostId = hostId;
          _liveAgentCount =
              null; // A fresh `tree_snapshot` refills this via `_onMessage`.
        });
        widget.onSwitched?.call(hostId);
      case SwitchFailed(:final hostId, :final reason, :final detail):
        unawaited(AppHaptic.error());
        setState(() {
          _pendingSwitchHostId = null;
          _lastAttempt = _Attempt(
            hostId: hostId,
            reason: reason,
            detail: detail,
          );
        });
    }
  }

  Future<void> _confirmForget(PairedHostRecord record) async {
    final thisDeviceName = await widget.thisDeviceName();
    if (!mounted) return;
    final outcome = await showChromeConfirmationDialog(
      context: context,
      title: 'Forget ${record.hostName}?',
      body: forgetStillListedSentence(thisDeviceName),
      destructiveLabel: 'Forget',
    );
    if (outcome != ChromeConfirmationOutcome.destructive || !mounted) return;
    final result = await widget.onForget(record);
    if (!mounted) return;
    switch (result) {
      case Ok<void>():
        unawaited(AppHaptic.commit());
        setState(() {
          _records = _records.where((r) => r.hostId != record.hostId).toList();
          if (_lastAttempt?.hostId == record.hostId) _lastAttempt = null;
        });
      case Err<void>(:final message):
        unawaited(AppHaptic.error());
        _showSnackbar(message);
    }
  }

  void _showSnackbar(String message) => showChromeSnackbar(context, message);

  List<HostListRow> get _rows {
    final rows = _records.map((record) {
      final attentionCount = _attention
          .where((item) => item.hostId == record.hostId)
          .length;
      final attempt = _lastAttempt?.hostId == record.hostId
          ? _lastAttempt
          : null;
      final HostRowState state;
      if (_pendingSwitchHostId == record.hostId) {
        state = HostRowState.switching;
      } else if (attempt != null) {
        state = switch (attempt.reason) {
          SwitchFailureReason.hostInUse => HostRowState.hostInUse,
          SwitchFailureReason.rejected => HostRowState.rejected,
          SwitchFailureReason.offline ||
          SwitchFailureReason.unknownHost ||
          SwitchFailureReason.other => HostRowState.switchFailed,
        };
      } else if (record.hostId == _connectedHostId &&
          _liveState is RelayConnected) {
        state = HostRowState.connected;
      } else {
        state = HostRowState.saved;
      }
      return HostListRow(
        record: record,
        state: state,
        liveAgentCount: state == HostRowState.connected
            ? _liveAgentCount
            : null,
        attentionCount: attentionCount,
      );
    }).toList();
    return sortHostRows(rows);
  }

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final title = Text(
      'Computers',
      style: AppType.heading.copyWith(color: color.fgPrimary),
    );
    // R-03-107 (amended 2026-09-09): a screen with content paints plain `color.bg.base`, so the
    // rows sit on the bare surface with no grid and no paper; only the empty state takes the
    // grid, with the mark behind it ([_buildLoaded]). The body stays inside the safe area, so
    // the hint under the last row clears the system navigation bar. Top is the app bar's job.
    // The bar's bottom edge is `color.border.strong`, per R-32-115 and R-32-510 (corrected
    // 2026-09-08 from `color.border.subtle`).
    final body = SafeArea(top: false, child: _buildBody(context));
    // The one app bar action of R-33-033's `App bar action` row (decided 2026-09-08): the
    // platform's own control, never a bare gesture box.
    final Widget pairButton = ChromeIconAction(
      icon: Symbols.add_rounded,
      label: 'Pair a computer',
      onPressed: widget.onPairAnother,
    );
    if (_isIos) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          backgroundColor: color.bgBase,
          border: Border(
            bottom: BorderSide(
              color: color.borderStrong,
              width: AppBorder.hairline,
            ),
          ),
          middle: title,
          trailing: pairButton,
        ),
        child: body,
      );
    }
    return Scaffold(
      backgroundColor: color.bgBase,
      appBar: AppBar(
        backgroundColor: color.bgBase,
        elevation: 0,
        title: title,
        actions: <Widget>[pairButton],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(AppBorder.hairline),
          child: Container(
            color: color.borderStrong,
            height: AppBorder.hairline,
          ),
        ),
      ),
      body: body,
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_phase) {
      case _Phase.loading:
        return _showSkeleton ? const _SkeletonList() : const SizedBox.shrink();
      case _Phase.error:
        return _ErrorBlock(
          text: _errorText ?? '',
          onRetry: () => unawaited(_load()),
        );
      case _Phase.loaded:
        return _buildLoaded(context);
    }
  }

  Widget _buildLoaded(BuildContext context) {
    final color = AppColor.of(context);
    final rows = _rows;
    if (rows.isEmpty) {
      // R-03-107: the empty state is the one place this screen paints the ground grid, with
      // the mark behind its block.
      return GroundGrid(
        child: EmptyMark(
          child: _EmptyBlock(onPairAnother: widget.onPairAnother),
        ),
      );
    }
    // The strips carry `treat.warning` (R-32-506): the hue lives in the icon, and only
    // `treat.error` in a strip and `treat.destructive` take the leading bar (corrected
    // 2026-09-08: a bare body sentence beside a warning bar was neither treatment).
    return Column(
      children: <Widget>[
        if (_hostInUseBanner) _hostInUseStrip(context),
        if (_offline)
          AppStrip(
            child: const Treatment.warning(label: 'No network.'),
            onTapDestination: () {
              final id =
                  _lastAttempt?.hostId ??
                  _connectedHostId ??
                  _newestLastSeenHostId();
              if (id != null) widget.onOpenDiagnostics?.call(id);
            },
          )
        else if (_lastAttempt case final attempt?
            when _liveState is! RelayConnected)
          AppStrip(
            // R-31-05-18 (amended 2026-09-16): name the computer; the row carries the
            // raw failure text (R-30-803).
            child: Treatment.warning(
              label:
                  'Could not connect to '
                  '${_findRecord(attempt.hostId)?.hostName ?? 'this computer'}. '
                  'Tap for details.',
            ),
            onTapDestination: () =>
                widget.onOpenDiagnostics?.call(attempt.hostId),
          ),
        Expanded(
          // The list ends with the hint under its last row (R-03-109): no clearance and no
          // ground below it.
          child: CustomScrollView(
            slivers: <Widget>[
              SliverList.list(
                children: <Widget>[
                  for (final row in rows) _buildRow(row),
                  // Callout 9: plain `type.caption` under the last row, on the names'
                  // text edge, `space.4` above and below, as the wireframe draws it
                  // (moved out of a footer strip 2026-09-08: the strip's own inset put
                  // the hint 20 px left of the names it explains).
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _textEdge,
                      AppSpace.space4,
                      AppSpace.space4,
                      AppSpace.space4,
                    ),
                    child: Text(
                      _rowActionsHint,
                      style: AppType.caption.copyWith(color: color.fgSecondary),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _hostInUseStrip(BuildContext context) => AppStrip(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Treatment.warning(label: 'Computer in use on another phone'),
        const SizedBox(height: AppSpace.space2),
        Row(
          children: <Widget>[
            AppTextButton(
              label: 'Try again',
              onPressed: () {
                final id = _connectedHostId;
                final record = id == null ? null : _findRecord(id);
                if (record != null) unawaited(_handleRowTap(record));
              },
            ),
            const SizedBox(width: AppSpace.space3),
            AppTextButton(
              label: 'Why',
              onPressed: () {
                final id = _connectedHostId;
                if (id != null) widget.onOpenDiagnostics?.call(id);
              },
            ),
          ],
        ),
      ],
    ),
  );

  PairedHostRecord? _findRecord(String hostId) {
    for (final record in _records) {
      if (record.hostId == hostId) return record;
    }
    return null;
  }

  String? _newestLastSeenHostId() {
    PairedHostRecord? newest;
    for (final record in _records) {
      final seen = record.lastSeen;
      if (seen == null) continue;
      final newestSeen = newest?.lastSeen;
      if (newest == null || (newestSeen != null && seen.isAfter(newestSeen))) {
        newest = record;
      }
    }
    return newest?.hostId;
  }

  /// The row's connection state for the bar of R-03-100, per R-32-705 and callout 3: `ok` for
  /// the one connected computer, `unknown` for every other row, which is a saved computer this
  /// phone knows nothing live about (R-03-046) whatever its detail line reports (a switch under
  /// way, a failed switch, `in use on another phone`, a revoke: the mockup's `States` draw each as
  /// an ordinary saved row, and the detail line of callout 5 carries the failure), and `unknown`
  /// while this phone has no network, where the strip and the detail line name `offline`. Amended
  /// 2026-09-10: `idle` shared the `ok` hue (R-32-130), so a disconnected row read as connected.
  BarState _barStateFor(HostListRow row) =>
      !_offline && row.state == HostRowState.connected
      ? BarState.ok
      : BarState.unknown;

  /// One row. A long press opens the row's actions (R-30-296): `Forget` alone, destructive,
  /// with `delete_outline` from the R-32-401 map. The tap on it always raises
  /// `showChromeConfirmationDialog` first (R-30-297).
  Widget _buildRow(HostListRow row) {
    final color = AppColor.of(context);
    final barState = _barStateFor(row);
    final isConnected = row.state == HostRowState.connected;

    return ChromeRowActions(
      key: ValueKey<String>(row.record.hostId),
      items: <ChromeMenuItem>[
        ChromeMenuItem(
          label: _forgetLabel,
          icon: Symbols.delete_outline_rounded,
          destructive: true,
          onSelected: () => unawaited(_confirmForget(row.record)),
        ),
      ],
      child: Semantics(
        customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
          const CustomSemanticsAction(label: 'Forget this computer'): () =>
              unawaited(_confirmForget(row.record)),
        },
        // Callout 3: the connection state is the leading bar alone, no state word. `WORKING`
        // and `IDLE` are agent words, which R-31-05-11 keeps off a computer's row, and their
        // differing widths started the names on two edges (2026-09-08). R-03-100
        // (2026-09-09): the bar is the one mark; the attention count of callout 8 is a badge
        // in the trailing slot, never a second bar.
        child: AppListRow(
          state: barState,
          primary: row.record.hostName,
          secondary: _detailFor(row),
          trailing: _trailingFor(row, color),
          onTap: () {
            if (row.state == HostRowState.rejected) {
              widget.onPairAnother?.call();
            } else {
              unawaited(_handleRowTap(row.record));
            }
          },
          selected: isConnected,
        ),
      ),
    );
  }

  /// Callout 5: one detail form per row, always present, so every row is the two-line row of
  /// R-32-515 and every name sits on line one (2026-09-08: a connected row with no count yet
  /// drew one line, and its name sat 8 px lower than its neighbours'). The state forms are
  /// upper case like the `LAST SEEN` form beside them; the two failure sentences stay
  /// sentences, per R-32-207.
  String _detailFor(HostListRow row) {
    switch (row.state) {
      case HostRowState.connected:
        final count = row.liveAgentCount;
        if (count == null) return 'CONNECTED';
        return '$count AGENT${count == 1 ? '' : 'S'}';
      case HostRowState.switching:
        return 'SWITCHING';
      case HostRowState.hostInUse:
        return 'IN USE ON ANOTHER PHONE';
      case HostRowState.rejected:
        return 'Removed by this computer. Pair again.';
      case HostRowState.switchFailed:
        // R-30-803: the raw reason, never a paraphrase.
        return _lastAttempt?.detail ?? 'Could not reach this computer.';
      case HostRowState.saved:
        final lastSeen = row.record.lastSeen;
        if (lastSeen == null) return 'NOT CONNECTED YET';
        return formatLastSeenLong(lastSeen.toLocal()).toUpperCase();
    }
  }

  Widget _trailingFor(HostListRow row, AppColor color) {
    final Widget control = switch (row.state) {
      HostRowState.switching => const ChromeActivityIndicator(),
      HostRowState.switchFailed || HostRowState.hostInUse => Text(
        'TRY AGAIN',
        style: AppType.monoButton.copyWith(color: color.accentText),
      ),
      HostRowState.rejected => Text(
        'PAIR AGAIN',
        style: AppType.monoButton.copyWith(color: color.accentText),
      ),
      HostRowState.connected || HostRowState.saved => Icon(
        Symbols.chevron_right_rounded,
        size: AppSize.iconMd,
        color: color.fgSecondary,
      ),
    };
    if (row.attentionCount <= 0) return control;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        control,
        const SizedBox(height: AppSpace.space1),
        _AttentionBadge(count: row.attentionCount),
      ],
    );
  }
}

/// The `Loading` state's skeleton (R-32-560, R-90-011), shown only after the 150 ms grace
/// period of `R-30-004`: three rows, each two bars of `size.skeleton` at `radius.sm` in
/// `color.bg.raised`, 140 and 90 wide, standing for the name and the detail line at the row's
/// own text edge, on the screen's plain `color.bg.base`. Never animated. Corrected 2026-09-08:
/// four full-width square bars stood for nothing on this screen.
class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  static const double _firstBarWidth = 140;
  static const double _secondBarWidth = 90;

  @override
  Widget build(BuildContext context) {
    final color = AppColor.of(context);
    Widget bar(double width) => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.space1),
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
      padding: const EdgeInsets.fromLTRB(
        _textEdge,
        AppSpace.space2,
        AppSpace.space4,
        AppSpace.space2,
      ),
      child: Column(
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

/// The `Error` state (R-30-803, R-30-804), on the screen's plain `color.bg.base`.
class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.text, required this.onRetry});
  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final color = AppColor.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.space4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Treatment.error(label: 'Could not read the computer list.'),
            const SizedBox(height: AppSpace.space2),
            Text(
              text,
              style: AppType.monoCode.copyWith(color: color.fgPrimary),
            ),
            const SizedBox(height: AppSpace.space4),
            AppTextButton(label: 'Try again', onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

/// The `Empty` state: no computer paired (R-32-553; R-03-107, amended 2026-09-09). Left aligned
/// at `space.4` on the ground grid inside `EmptyMark`, whose `color.bg.grid` silhouette
/// bottom-right replaced the 96 px `color.fg.disabled` mark this block drew above its eyebrow:
/// one silhouette per screen. The `Eyebrow('COMPUTERS')` first, then the title in `type.title`,
/// the display face of the screen titles, in `color.accent.text`, the sentence in `type.body`
/// `color.fg.secondary`, and the one ghost button `space.5` under it (`docs/32-design-language.md`
/// section 7.19). Centred until 2026-09-09, against R-32-553.
class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock({this.onPairAnother});
  final VoidCallback? onPairAnother;

  @override
  Widget build(BuildContext context) {
    final color = AppColor.of(context);
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
          const Eyebrow(text: 'COMPUTERS'),
          const SizedBox(height: AppSpace.space3),
          Text(
            'No computer yet.',
            style: AppType.title.copyWith(color: color.accentText),
          ),
          const SizedBox(height: AppSpace.space2),
          Text(
            'Scan a QR code or enter a phrase to pair your first computer.',
            style: AppType.body.copyWith(color: color.fgSecondary),
          ),
          const SizedBox(height: AppSpace.space5),
          AppGhostButton(label: 'Pair a computer', onPressed: onPairAnother),
        ],
      ),
    );
  }
}

/// `docs/32-design-language.md` R-32-518's badge: `notifications_active` at `size.icon.sm` in
/// `color.status.blocked`, the count in `type.micro.strong` in `color.fg.primary`, no fill.
class _AttentionBadge extends StatelessWidget {
  const _AttentionBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = AppColor.of(context);
    return Semantics(
      label: '$count needing attention',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Symbols.notifications_active_rounded,
            size: AppSize.iconSm,
            color: color.statusBlocked,
          ),
          const SizedBox(width: AppSpace.space1),
          Text(
            '$count',
            style: AppType.microStrong.copyWith(color: color.fgPrimary),
          ),
        ],
      ),
    );
  }
}
