/// Composes `services/terminal.dart`'s [TerminalService] with
/// `widgets/terminal_view_widget.dart`'s [TerminalViewWidget],
/// `widgets/status_strip.dart`'s [StatusStrip] and `widgets/key_row.dart`'s
/// [KeyRow] into the real terminal route, `/hosts/:hostId/panes/:paneId`
/// (`docs/30-ux-spec.md` row 08, `docs/31-mockups/08-terminal.md`).
///
/// This file owns the pane lifecycle: it builds one [TerminalService] per mount, attaches
/// [paneId] once on mount, detaches on dispose, and derives [TerminalGridPhase] and
/// [StatusStripLinkWord] from [TerminalService.frameState] and [connectionState] — the same
/// [RelayConnected]/[RelayRegistrationError] classification `device_list_screen.dart`'s
/// `_LiveConnection` already established, so a third reader agrees with the first two rather
/// than inventing a fourth reading of [RelayConnectionState] (R-90-018).
///
/// The pane title, the pane's agent status line and the pane-gone state come from the same
/// `tree_snapshot` the agent list reads (R-11-044, R-31-06): this screen sends
/// one `tree_request` on mount — the first-read pattern `agent_list.dart` and
/// `create_sheet.dart` already establish, never a poll (R-31-06-04) — and then follows
/// `tree_snapshot`/`tree_update` on the one shared [messages] subscription, so a rename or a
/// `pane.closed` event reaches this screen live. The same tree feeds the two R-03-113 imports
/// of 2026-09-09: the title is the platform's own button that opens
/// `pane_switcher_sheet.dart`'s hierarchy switcher (item 1, R-31-08-25), and the bar carries
/// the `N waiting   N done` attention summary under it (item 4, R-31-08-26). The connection
/// state bar sits before the title, on the bar's leading side, like every list row's bar
/// (R-03-121, 2026-09-10).
///
/// The three grid phases that end the person's work in the pane, `paneGone`, `readFailed` and
/// `protocolMismatch`, are the platform's own alert dialog (R-03-119): this screen raises it once
/// per phase entry, after the frame, and closes it when the phase leaves; the grid widget only
/// dims under it. `Back` and `Back to agents` are [TerminalScreen.onBack], `Try again` is one
/// more [_TerminalScreenState._attach].
///
/// ponytail: `TerminalGridPhase.protocolMismatch` is never raised — detecting it needs
/// `HostInfo.herdrProtocol` threaded through, which `RelayConnection` does not yet expose to
/// a caller. Every other attach failure surfaces as [TerminalGridPhase.readFailed] instead,
/// with the raw error text and a working `Try again`, which is honest even where it is not
/// the exact named phase. `paneGone` is raised from the tree (see above), closing the other
/// half of the gap this paragraph used to disclose.
library;

import 'dart:async' show StreamController, StreamSubscription, Timer, unawaited;

import 'package:cupertino_ui/cupertino_ui.dart'
    show
        BuildContext,
        CupertinoButton,
        CupertinoNavigationBar,
        CupertinoPageScaffold,
        Text,
        Widget;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart' show TextInputFormatter;
import 'package:flutter/widgets.dart'
    show
        AlignmentDirectional,
        Border,
        BorderSide,
        BoxDecoration,
        BoxConstraints,
        BuildContext,
        Column,
        ConstrainedBox,
        CrossAxisAlignment,
        Container,
        EdgeInsets,
        Expanded,
        Flexible,
        FocusNode,
        GlobalKey,
        Icon,
        IconData,
        InlineSpan,
        LayoutBuilder,
        MainAxisSize,
        MediaQuery,
        Orientation,
        PreferredSize,
        Row,
        SafeArea,
        Semantics,
        Size,
        SizedBox,
        State,
        StatefulWidget,
        StatelessWidget,
        Text,
        TextOverflow,
        TextSpan,
        TextStyle,
        ValueChanged,
        VoidCallback,
        Widget,
        WidgetSpan,
        WidgetsBinding;
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart'
    show AppBar, BackButton, Scaffold, TextButton;

import '../core/result/result.dart' show Err, Ok;
import '../models/message.dart'
    show
        Message,
        MessageSendInput,
        MessageSendInputAck,
        MessageTreeSnapshot,
        MessageTreeUpdate;
import '../models/messages/agent_summary.dart' show AgentSummary;
import '../models/messages/pane_summary.dart' show PaneSummary;
import '../models/messages/send_input_ack.dart' show SendInputAck;
import '../models/messages/theme_palette.dart' show ThemePalette;
import '../models/messages/tree_snapshot.dart' show TreeSnapshot;
import '../services/pane_actions.dart'
    show
        closePane,
        createPaneSplit,
        HostActionOutcome,
        HostActionApplied,
        HostActionRefused,
        HostActionOutcomeUnknown;
import '../services/relay.dart'
    show
        RelayConnected,
        RelayConnectionState,
        RelayReconnecting,
        RelayRegistrationError,
        RelayRegistrationErrorCode,
        RelayRevoked;
import '../services/terminal.dart'
    show
        TerminalAttachException,
        TerminalFrameState,
        TerminalMessageSender,
        TerminalPaneStatus,
        TerminalPaneWatcher,
        TerminalService;
import '../services/tree.dart'
    show applyTreeUpdate, fetchTreeSnapshot, paneDisplayName;
import '../widgets/composer.dart' show Composer;
import '../widgets/key_row.dart' show KeyRow, KeyRowLinkState, KeyRowState;
import '../widgets/status_bar.dart' show BarState, StatusBar;
import '../widgets/status_strip.dart'
    show StatusStrip, StatusStripLinkWord, TerminalOverviewControl;
import '../widgets/terminal_view_widget.dart'
    show TerminalGridPhase, TerminalViewWidget;
import '../widgets/theme/app_color.dart';
import '../widgets/theme/app_haptic.dart' show AppHaptic;
import '../widgets/theme/app_live_bar.dart' show AppLiveBar;
import '../widgets/theme/app_motion.dart' show AppMotion;
import '../widgets/theme/app_size.dart' show AppSize;
import '../widgets/theme/app_space.dart' show AppSpace;
import '../widgets/theme/app_type.dart' show AppType;
import '../widgets/theme/chrome_confirmation_dialog.dart'
    show ChromeAlertAction, ChromeDialogHandle, showChromeAlertDialog;
import '../widgets/theme/chrome_icon_action.dart' show ChromeIconAction;
import 'pane_actions_sheet.dart'
    show PaneActionsLinkState, showPaneActionsSheet;
import 'pane_switcher_sheet.dart' show showPaneSwitcherSheet;

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({
    super.key,
    required this.hostId,
    required this.paneId,
    required this.hostName,
    required this.messages,
    required this.connectionState,
    required this.initialConnectionState,
    required this.send,
    required this.watchPane,
    required this.unwatchPane,
    this.initialTextSize = AppType.monoTerminalDefaultSize,
    this.initialHostTheme,
    this.onBack,
    this.onDiagnostics,
    this.onOpenPluginActions,
    this.onSwitchPane,
    this.onSplit,
    this.onRevoked,
    this.onFrameState,
    this.now = DateTime.now,
  });

  final String hostId;
  final String paneId;
  final String hostName;
  final Stream<Message> messages;
  final Stream<RelayConnectionState> connectionState;

  /// The link state when this screen opens. [connectionState] is a broadcast stream with no
  /// replay, and a pane is opened on a link that is already connected, so without this the
  /// grid read `offline` and the strip `OFFLINE` while frames kept painting (measured live,
  /// 2026-09-03).
  final RelayConnectionState initialConnectionState;
  final TerminalMessageSender send;
  final TerminalPaneWatcher watchPane;
  final TerminalPaneWatcher unwatchPane;

  /// The terminal text size the person chose in Settings (R-21-010's
  /// ladder, R-30-210); a pinch steps it for this screen only.
  final int initialTextSize;

  /// R-03-131: host_info arrives before this screen opens.
  final ThemePalette? initialHostTheme;

  /// R-30-031: back MUST return to the route that opened this one, never a fixed route. A
  /// caller wires this to `context.pop()`.
  final VoidCallback? onBack;

  /// A tap on the offline strip, per R-30-806.
  final VoidCallback? onDiagnostics;

  /// Opens the plugin actions screen scoped to this pane (R-03-055): the caller pushes
  /// `/hosts/:hostId/panes/:paneId/actions`. The pane action sheet's `Plugin actions` row
  /// (mockup 10 callout 5) fires it.
  final VoidCallback? onOpenPluginActions;

  /// The hierarchy switcher of R-03-113 item 1 (mockup 08 callout 10, R-31-08-25): fires with
  /// the pane a person chose in the switcher sheet, never this screen's own [paneId]. A caller
  /// replaces this route with that pane's terminal (`context.pushReplacement` of
  /// `/hosts/:hostId/panes/:paneId`), so the new screen attaches, watches and unwatches on its
  /// own lifecycle and the nested `/actions` route keeps the right pane. `null` leaves the
  /// title a plain heading.
  final ValueChanged<String>? onSwitchPane;

  /// Opens the new pane after the Host acknowledges a split.
  final ValueChanged<String>? onSplit;

  /// Fires once, automatically, when this Device is revoked mid-session (R-13-054,
  /// R-13-055). A caller clears this computer's stored record and navigates to the pairing
  /// screen; this file only raises the signal.
  final VoidCallback? onRevoked;

  /// Every [TerminalFrameState] this pane publishes. A caller keeps the last one for the
  /// session, so `/hosts/:hostId/diagnostics` can show the grid, the longest line and the
  /// unknown SGR count after this pane closes (R-31-13-07 to R-31-13-10). `null` drops them.
  final ValueChanged<TerminalFrameState>? onFrameState;

  /// The clock, injectable for tests. Backs the live dot's 60-second
  /// warning colour of `docs/32-design-language.md` section 7.3 and the
  /// agent status line's age.
  final DateTime Function() now;

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  late final TerminalService _service = TerminalService(
    messages: widget.messages,
    send: (message, {corr}) {
      if (message case MessageSendInput(:final payload)) {
        // R-31-09-13: composer edits share the key row's acknowledgement path.
        _keyRowKey.currentState?.sendInput(
          payload,
          label: payload.keys?.first.toLowerCase() ?? 'typing',
        );
      } else {
        widget.send(message, corr: corr);
      }
    },
    watchPane: widget.watchPane,
    unwatchPane: widget.unwatchPane,
    initialHostTheme: widget.initialHostTheme,
  );
  late final StreamSubscription<RelayConnectionState> _connectionSub;
  late final StreamSubscription<TerminalFrameState> _frameSub;

  /// The one shared listener on [TerminalScreen.messages]: it filters this
  /// pane's `send_input_ack` frames for the key row and feeds
  /// `tree_snapshot`/`tree_update` to [_applyTree]. `TerminalService`
  /// keeps its own subscription; no other feature adds a third.
  late final StreamSubscription<Message> _messageSub;

  /// Broadcast, not single-subscription: the portrait and landscape
  /// branches mount [KeyRow] under different subtrees, so a rotation
  /// remounts it and the fresh state listens again while this controller,
  /// owned by the surviving screen state, lives on (the 2026-09-08
  /// real-device rotation crash).
  final StreamController<SendInputAck> _ackController =
      StreamController<SendInputAck>.broadcast();

  /// R-03-130: grid taps focus the native composer without sending input.
  final FocusNode _composerFocus = FocusNode(debugLabel: 'Terminal composer');
  bool _keyPanelOpen = false;

  void _toggleKeyPanel() {
    setState(() => _keyPanelOpen = !_keyPanelOpen);
  }

  final GlobalKey<KeyRowState> _keyRowKey = GlobalKey<KeyRowState>();
  final GlobalKey _composerKey = GlobalKey();
  final GlobalKey _gridKey = GlobalKey();

  late RelayConnectionState _connectionState = widget.initialConnectionState;
  TerminalFrameState get _frame => _service.state;
  bool _attaching = true;
  String? _attachError;

  /// R-22-028's attempt counter for the reconnecting strip: each
  /// [RelayReconnecting] event is one backoff wait after one failed
  /// attempt.
  int _reconnectAttempt = 0;

  TreeSnapshot? _tree;
  bool _paneSeenInTree = false;
  bool _paneClosed = false;

  /// The R-03-119 alert while one of the three phases that end the work
  /// shows, with the phase it was raised for; `null` otherwise.
  _StateDialog? _stateDialog;
  bool _stateDialogSyncScheduled = false;

  late int _textSize = widget.initialTextSize;
  bool _overview = false;
  int? _sizeFlash;
  Timer? _sizeFlashTimer;
  ({int first, int last})? _visibleWindow;

  /// The Device's own scroll offset above the live bottom, in rows, as
  /// `TerminalViewWidget.onScrollOffsetChanged` reports it. Feeds the
  /// status strip's scroll readout — R-31-08-18 forbids the pane object's
  /// own `offset_from_bottom` here.
  int _deviceScrollOffset = 0;

  DateTime? _lastFrameAt;
  Timer? _dotTimer;

  @override
  void initState() {
    super.initState();
    _connectionSub = widget.connectionState.listen(
      (RelayConnectionState state) => setState(() {
        _connectionState = state;
        if (state is RelayConnected) {
          _reconnectAttempt = 0;
        } else if (state is RelayReconnecting) {
          _reconnectAttempt++;
        }
      }),
    );
    _frameSub = _service.frameState.listen((TerminalFrameState state) {
      widget.onFrameState?.call(state);
      // Herdr freezes `revision` on an agent pane, and the Host polls and
      // dedupes by text, so a fresh frame can carry a revision that did
      // not move (2026-09-03). Every emission of this stream is already a
      // changed frame — `terminal.dart`'s `_onPaneFrame` gate sees to
      // that — so the live dot re-arms on every emission, never on a
      // revision change.
      _lastFrameAt = widget.now();
      _armDotTimer();
      if (_paneClosed) _paneClosed = false; // a fresh frame proves life
      setState(() {});
    });
    _messageSub = widget.messages.listen(_onSharedMessage);
    unawaited(_attach());
    unawaited(_loadTree());
  }

  @override
  void dispose() {
    // An alert over a route that leaves closes after this frame, once the
    // tree is unlocked; a dialog the navigator already removed with this
    // route is inactive by then, and the handle does nothing.
    final ChromeDialogHandle<_StateAction>? dialog = _stateDialog?.dialog;
    if (dialog != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => dialog.dismiss());
    }
    _dotTimer?.cancel();
    _sizeFlashTimer?.cancel();
    unawaited(_connectionSub.cancel());
    unawaited(_frameSub.cancel());
    unawaited(_messageSub.cancel());
    _composerFocus.dispose();
    unawaited(_ackController.close());
    _service.detach();
    unawaited(_service.dispose());
    super.dispose();
  }

  Future<void> _attach() async {
    setState(() {
      _attaching = true;
      _attachError = null;
    });
    final result = await _service.attach(widget.paneId);
    if (!mounted) return;
    setState(() {
      _attaching = false;
      // R-30-803: the raw reason, so a timeout and a Host refusal read differently.
      _attachError = switch (result) {
        Err(:final message, cause: final TerminalAttachException cause) =>
          '$message: ${cause.message}',
        Err(:final message) => message,
        Ok() => null,
      };
    });
  }

  /// Sends the one `tree_request` of this screen's header comment. A
  /// failure leaves the pane-name fallback in the app bar; the grid works
  /// without tree data.
  Future<void> _loadTree() async {
    final result = await fetchTreeSnapshot(
      messages: widget.messages,
      connectionState: widget.connectionState,
      send: widget.send,
    );
    if (!mounted) return;
    if (result case Ok(:final value)) _applyTree(value);
  }

  void _onSharedMessage(Message message) {
    switch (message) {
      case MessageSendInputAck(:final payload):
        // The key row's ACK stream is this pane's `send_input_ack` frames
        // only (R-11-227, R-11-055).
        if (payload.paneId == widget.paneId && !_ackController.isClosed) {
          _ackController.add(payload);
        }
      case MessageTreeSnapshot(:final payload):
        _applyTree(payload);
      case MessageTreeUpdate(:final payload):
        final TreeSnapshot? current = _tree;
        if (current != null) {
          final TreeSnapshot next = applyTreeUpdate(current, payload);
          if (!identical(next, current)) _applyTree(next);
        }
      default:
        break;
    }
  }

  void _applyTree(TreeSnapshot next) {
    final bool present = next.panes.any(
      (PaneSummary pane) => pane.paneId == widget.paneId,
    );
    setState(() {
      _tree = next;
      if (present) {
        _paneSeenInTree = true;
      } else if (_paneSeenInTree || (!_attaching && _attachError == null)) {
        // `pane.closed` while this screen is open (mockup 08, States,
        // "Empty, pane gone", R-11-046).
        _paneClosed = true;
      }
    });
  }

  /// R-32-510's live bar refreshes itself once, at the moment the last
  /// event crosses the 60-second warning age.
  void _armDotTimer() {
    _dotTimer?.cancel();
    _dotTimer = Timer(AppLiveBar.warningAge, () {
      if (mounted) setState(() {});
    });
  }

  TerminalGridPhase get _phase {
    if (_connectionState is RelayRevoked) {
      return TerminalGridPhase.revoked;
    }
    if (_connectionState case RelayRegistrationError(:final code)
        when code == RelayRegistrationErrorCode.hostInUse) {
      return TerminalGridPhase.hostInUse;
    }
    if (_connectionState is RelayReconnecting) {
      return TerminalGridPhase.loadingReconnecting;
    }
    if (_connectionState is! RelayConnected) {
      return TerminalGridPhase.offline;
    }
    if (_paneClosed) {
      return TerminalGridPhase.paneGone;
    }
    if (_attaching) {
      return TerminalGridPhase.loadingFirstPaint;
    }
    if (_attachError != null) {
      return TerminalGridPhase.readFailed;
    }
    return TerminalGridPhase.live;
  }

  /// R-03-119: `paneGone`, `readFailed` and `protocolMismatch` end the work
  /// in this pane, so the platform's own alert offers the way out and the
  /// grid only dims. The check runs after the frame: the phase is derived
  /// state that any listener can move, and a route push is not safe
  /// mid-build (the grid widget's `_maybeFireRevoked` idiom). One alert per
  /// phase entry: it shows once, and a phase change closes it — a `Try
  /// again` that succeeds, a link that drops, a frame that proves the pane
  /// alive — after which the new phase raises its own if it needs one.
  void _scheduleStateDialogSync() {
    if (_stateDialogSyncScheduled) return;
    _stateDialogSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _stateDialogSyncScheduled = false;
      if (mounted) _syncStateDialog();
    });
  }

  void _syncStateDialog() {
    final TerminalGridPhase phase = _phase;
    final _StateDialog? showing = _stateDialog;
    if (showing != null) {
      if (showing.phase != phase) showing.dialog.dismiss();
      return;
    }
    final ChromeDialogHandle<_StateAction>? dialog = _stateDialogFor(phase);
    if (dialog != null) unawaited(_awaitStateDialog(phase, dialog));
  }

  /// Raises the alert of [phase] with the title, the body and the actions
  /// R-03-119 and mockup 08's States table fix, or returns `null` for a
  /// phase that ends no work. `Back`, in every wording, is the screen's own
  /// back navigation, so the dialog leaves exactly where the bar's back
  /// control would (R-30-031).
  ChromeDialogHandle<_StateAction>? _stateDialogFor(TerminalGridPhase phase) {
    const ChromeAlertAction<_StateAction> back = (
      label: 'Back',
      result: _StateAction.back,
    );
    return switch (phase) {
      TerminalGridPhase.paneGone => showChromeAlertDialog(
        context: context,
        title: 'This pane closed.',
        defaultAction: (label: 'Back to agents', result: _StateAction.back),
      ),
      TerminalGridPhase.readFailed => showChromeAlertDialog(
        context: context,
        title: 'Could not read this pane.',
        detail: _attachError,
        defaultAction: (label: 'Try again', result: _StateAction.tryAgain),
        otherAction: back,
      ),
      TerminalGridPhase.protocolMismatch => showChromeAlertDialog(
        context: context,
        title: 'This computer runs a different Herdr version.',
        body: 'Update Herdr on ${widget.hostName}, or update this app.',
        defaultAction: back,
      ),
      _ => null,
    };
  }

  Future<void> _awaitStateDialog(
    TerminalGridPhase phase,
    ChromeDialogHandle<_StateAction> dialog,
  ) async {
    _stateDialog = (phase: phase, dialog: dialog);
    final _StateAction? action = await dialog.result;
    _stateDialog = null;
    if (!mounted) return;
    switch (action) {
      case _StateAction.back:
        widget.onBack?.call();
      case _StateAction.tryAgain:
        unawaited(_attach());
      case null:
        // Closed by a phase change: the new phase may need its own alert.
        _syncStateDialog();
    }
  }

  StatusStripLinkWord get _linkWord {
    if (_frame.status == TerminalPaneStatus.paused) {
      return StatusStripLinkWord.paused;
    }
    if (_connectionState is RelayConnected) {
      return StatusStripLinkWord.live;
    }
    if (_connectionState case RelayRegistrationError(:final code)
        when code == RelayRegistrationErrorCode.hostInUse) {
      return StatusStripLinkWord.hostInUse;
    }
    return StatusStripLinkWord.offline;
  }

  KeyRowLinkState get _keyRowLinkState {
    if (_connectionState is RelayConnected) return KeyRowLinkState.live;
    if (_connectionState case RelayRegistrationError(:final code)
        when code == RelayRegistrationErrorCode.hostInUse) {
      return KeyRowLinkState.hostInUse;
    }
    return KeyRowLinkState.offline;
  }

  /// R-30-808's failure sentence, in the words `app_shell.dart`'s
  /// connection strip already uses. This stream does not tell "no network"
  /// from "relay unreachable" (see that file's own note), so both read as
  /// the not-connected sentence.
  String? get _offlineReason => switch (_connectionState) {
    RelayConnected() => null,
    RelayRegistrationError(code: RelayRegistrationErrorCode.handleUnknown) =>
      'The computer is not connected to the relay. Open its Relay pane.',
    _ => 'Not connected to ${widget.hostName}.',
  };

  /// This pane's `panes[]` entry, or `null` before the first
  /// `tree_snapshot` lands or after the pane leaves the tree.
  PaneSummary? get _treePane {
    final TreeSnapshot? tree = _tree;
    if (tree == null) return null;
    for (final PaneSummary pane in tree.panes) {
      if (pane.paneId == widget.paneId) return pane;
    }
    return null;
  }

  /// The pane display name of R-31-07-10, from the tree when it has
  /// answered, else the rule's own unnamed-pane fallback, computable from
  /// the id alone (`w3:p11` draws as `pane 11`).
  String get _paneName {
    final PaneSummary? pane = _treePane;
    if (pane != null) return paneDisplayName(pane);
    final int lastColon = widget.paneId.lastIndexOf(':');
    final String suffix = lastColon < 0
        ? widget.paneId
        : widget.paneId.substring(lastColon + 1);
    final String number = suffix.startsWith('p') ? suffix.substring(1) : suffix;
    return 'pane $number';
  }

  /// The tab `title` of mockup 08's callout 2, or `null` until the first
  /// `tree_snapshot` lands.
  String? get _tabTitle {
    final TreeSnapshot? tree = _tree;
    final PaneSummary? pane = _treePane;
    if (tree == null || pane == null) return null;
    for (final tab in tree.tabs) {
      if (tab.tabId == pane.tabId) return tab.title;
    }
    return null;
  }

  /// Whether the pane name belongs in the title (R-03-129): only when this pane's tab holds two
  /// or more agent panes, so the name is what tells them apart. A sidebar beside one agent pane
  /// is not a second agent pane, and on the measured Host that was every agent tab.
  bool get _tabHasSiblingAgents {
    final TreeSnapshot? tree = _tree;
    final PaneSummary? pane = _treePane;
    if (tree == null || pane == null) return false;
    // An `agents[]` entry names its pane, and the pane names its tab (R-11-044).
    final Set<String> agentPanes = <String>{
      for (final agent in tree.agents) agent.paneId,
    };
    var agents = 0;
    for (final PaneSummary candidate in tree.panes) {
      if (candidate.tabId == pane.tabId &&
          agentPanes.contains(candidate.paneId) &&
          ++agents > 1) {
        return true;
      }
    }
    return false;
  }

  /// The title text of mockup 08 callout 2 as R-03-129 leaves it: the tab title alone; the pane
  /// name after ` / ` only with sibling agent panes; the pane name alone when the tab has no
  /// title. One place, so the app bar and the actions sheet never disagree.
  String get _titleText {
    final String? tab = _tabTitle;
    if (tab == null || tab.isEmpty) return _paneName;
    return _tabHasSiblingAgents ? '$tab / $_paneName' : tab;
  }

  /// The pane name the title control draws, or `null` when R-03-129 leaves it out.
  String? get _titlePaneName => _tabHasSiblingAgents ? _paneName : null;

  /// This pane's `agents[]` entry, or `null` when the pane holds no
  /// agent.
  AgentSummary? get _treeAgent {
    final TreeSnapshot? tree = _tree;
    if (tree == null) return null;
    for (final AgentSummary agent in tree.agents) {
      if (agent.paneId == widget.paneId) return agent;
    }
    return null;
  }

  /// Mockup 10's callout 4: the header's second line, `agent_kind`, then
  /// the `status` word with the age from `status_at` when the Host
  /// observed one (R-11-224). `null` when the pane holds no agent.
  ({String kind, String line})? get _agentLine {
    final AgentSummary? agent = _treeAgent;
    if (agent == null) return null;
    final String? age = _formatAge(agent.statusAt, now: widget.now);
    final String status = age == null ? agent.status : '${agent.status} $age';
    return (kind: agent.agentKind, line: '${agent.agentKind}  -  $status');
  }

  /// The same age shape `agent_list_screen.dart`'s `_formatAge` draws
  /// (`12s`, `3m 04s`, `2h 05m`, `1d`). A local copy rather than a shared
  /// import: that one is private to its screen, and R-90-018 assigns a
  /// shared factoring only once a second caller needs one — this is the
  /// second caller, but across a package boundary this file cannot cross
  /// without owning a new shared file.
  static String? _formatAge(String? at, {required DateTime Function() now}) {
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
      return '${totalMinutes}m '
          '${(totalSeconds % 60).toString().padLeft(2, '0')}s';
    }
    final int totalHours = totalMinutes ~/ 60;
    if (totalHours < 24) {
      return '${totalHours}h ${(totalMinutes % 60).toString().padLeft(2, '0')}m';
    }
    return '${totalHours ~/ 24}d';
  }

  /// The live bar's state (R-32-511): `error` while the link is down,
  /// `warning` once the last frame is older than `AppLiveBar.warningAge`,
  /// `ok` otherwise. A stale link is not work, so it never takes `working`.
  BarState get _liveState {
    if (_connectionState is! RelayConnected) return BarState.error;
    final DateTime? at = _lastFrameAt;
    if (at != null && widget.now().difference(at) >= AppLiveBar.warningAge) {
      return BarState.warning;
    }
    return BarState.ok;
  }

  void _onGridTap() {
    if (_keyPanelOpen) setState(() => _keyPanelOpen = false);
    _composerFocus.requestFocus();
  }

  void _onScrollOffsetRows(int rows) {
    _service.setScrollOffset(rows);
    if (rows != _deviceScrollOffset) {
      setState(() => _deviceScrollOffset = rows);
    }
  }

  void _onVisibleColumnsChanged(({int first, int last})? window) {
    if (window == _visibleWindow) return;
    setState(() => _visibleWindow = window);
  }

  void _toggleOverview() {
    _sizeFlashTimer?.cancel();
    setState(() {
      _overview = !_overview;
      _sizeFlash = null;
    });
  }

  /// R-30-302: one step along the R-21-010 ladder per threshold crossing,
  /// `haptic.select` on each step, and the new size in the status strip
  /// for `motion.duration.slow`. Under `disableAnimationsOf` (R-30-730) the
  /// readout does not time out: it stays until the next step, so no
  /// information is lost (R-30-732).
  /// The first threshold in overview restores the current readable size without a step.
  void _onPinchSizeStep(bool up) {
    const List<int> sizes = AppType.monoTerminalSizes;
    final int index = sizes.indexOf(_textSize);
    final int next = _overview ? index : (up ? index + 1 : index - 1);
    if (index < 0 || next < 0 || next >= sizes.length) return;
    unawaited(AppHaptic.select());
    setState(() {
      _overview = false;
      _textSize = sizes[next];
      _sizeFlash = sizes[next];
    });
    _sizeFlashTimer?.cancel();
    if (MediaQuery.disableAnimationsOf(context)) return;
    _sizeFlashTimer = Timer(AppMotion.durationSlow, () {
      if (mounted) setState(() => _sizeFlash = null);
    });
  }

  /// The force-read gesture of `docs/30-ux-spec.md`'s gesture table: ask
  /// the Host for the pane's scrollback (R-11-053). A dropped reply
  /// leaves the live grid untouched, so the outcome is not surfaced.
  void _onForceRead() {
    unawaited(
      _service.requestScrollback(lines: _frame.scroll.maxOffsetFromBottom),
    );
  }

  /// One SGR/CSI escape sequence — `pane_actions_sheet.dart`'s own
  /// `_ansiEscape` pattern, kept local for the same reason
  /// `terminal.dart` keeps its SGR regex local.
  static final RegExp _ansiEscape = RegExp('\x1B\\[[0-9;]*[A-Za-z]');
  static final RegExp _trailingSpaces = RegExp(' +\$');

  /// The visible screen as plain text for the sheet's `Read the last 20
  /// lines` row: escape sequences removed and each line's trailing spaces
  /// stripped (R-30-305). With the emulator's `maxLines: 0`, the buffer IS
  /// the visible screen.
  String _visibleScreenText() => _service.xterm.buffer
      .getText()
      .split('\n')
      .map(
        (String line) =>
            line.replaceAll(_ansiEscape, '').replaceAll(_trailingSpaces, ''),
      )
      .join('\n');

  /// The overflow's pane action sheet (mockup 08 callout 5, mockup 10). Its
  /// `Plugin actions` row routes to this pane's plugin actions (R-03-055);
  /// `Close pane` sends `close` after the R-31-10-01 confirmation. Nothing
  /// else requires a confirmation. Split actions report the new pane after acknowledgement.
  void _openPaneActions() {
    final ({String kind, String line})? agent = _agentLine;
    final String? label = _treePane?.label;
    final PaneActionsLinkState linkState = switch (_keyRowLinkState) {
      KeyRowLinkState.live => PaneActionsLinkState.normal,
      KeyRowLinkState.hostInUse => PaneActionsLinkState.hostInUse,
      KeyRowLinkState.offline => PaneActionsLinkState.offline,
    };
    unawaited(
      showPaneActionsSheet(
        context,
        paneTitle: _titleText,
        currentLabel: label ?? '',
        agentKind: agent?.kind,
        agentStatusLine: agent?.line,
        visibleScreenText: _visibleScreenText(),
        linkState: linkState,
        linkStateDetail: switch (linkState) {
          PaneActionsLinkState.normal => null,
          PaneActionsLinkState.hostInUse => 'Another phone is using this pane.',
          PaneActionsLinkState.offline => _offlineReason,
        },
        onTapDiagnostics: widget.onDiagnostics,
        onOpenPluginActions: widget.onOpenPluginActions,
        onSplit: widget.onSplit == null
            ? null
            : (String direction) => unawaited(_splitPane(direction)),
        onClosePane: () => unawaited(
          closePane(
            messages: widget.messages,
            connectionState: widget.connectionState,
            send: widget.send,
            paneId: widget.paneId,
          ),
        ),
      ),
    );
  }

  Future<void> _splitPane(String direction) async {
    final HostActionOutcome outcome = await createPaneSplit(
      messages: widget.messages,
      connectionState: widget.connectionState,
      send: widget.send,
      targetPaneId: widget.paneId,
      direction: direction,
    );
    if (!mounted) return;
    switch (outcome) {
      case HostActionApplied(:final ack) when ack.resultId != null:
        unawaited(AppHaptic.commit());
        widget.onSplit?.call(ack.resultId!);
      case HostActionApplied():
        showChromeAlertDialog<void>(
          context: context,
          title: 'Could not split pane.',
          detail: 'The computer did not return the new id.',
          defaultAction: (label: 'OK', result: null),
        );
      case HostActionRefused(:final message):
        unawaited(AppHaptic.error());
        showChromeAlertDialog<void>(
          context: context,
          title: 'Could not split pane.',
          detail: message,
          defaultAction: (label: 'OK', result: null),
        );
      case HostActionOutcomeUnknown():
        showChromeAlertDialog<void>(
          context: context,
          title: 'Outcome unknown',
          body: 'The connection dropped before the computer confirmed the split. Check the pane list before you split again.',
          defaultAction: (label: 'OK', result: null),
        );
    }
  }

  /// The hierarchy switcher of R-03-113 item 1 (mockup 08 callout 10,
  /// R-31-08-25): the sheet lists the tree this screen already follows, and
  /// a chosen pane closes it and reaches [TerminalScreen.onSwitchPane],
  /// which replaces this route. `null` before the first `tree_snapshot`
  /// lands (nothing to list) and where no caller wired the switch, so the
  /// title is then a plain heading.
  VoidCallback? get _openPaneSwitcher {
    final TreeSnapshot? tree = _tree;
    final ValueChanged<String>? onSwitch = widget.onSwitchPane;
    if (tree == null || onSwitch == null) return null;
    return () => unawaited(
      showPaneSwitcherSheet(
        context,
        tree: tree,
        currentPaneId: widget.paneId,
        onSwitchPane: onSwitch,
      ),
    );
  }

  /// The attention summary of R-03-113 item 4 (R-31-08-26) counts the
  /// `blocked` and `done` agent panes of the live tree. They are counted
  /// the way `agent_list.dart` counts them: a pane whose `agent` is set, by
  /// the pane's own `agent_status`, which `tree_update` keeps current where
  /// `agents[]` refreshes only with a full snapshot. `null` before the tree
  /// lands and while both counts are zero. Words only: no bar, no dot
  /// (R-03-058, R-03-100).
  ({int waiting, int done})? get _attentionSummary {
    final TreeSnapshot? tree = _tree;
    if (tree == null) return null;
    int waiting = 0;
    int done = 0;
    for (final PaneSummary pane in tree.panes) {
      if (pane.agent == null) continue;
      switch (pane.agentStatus) {
        case 'blocked':
          waiting++;
        case 'done':
          done++;
      }
    }
    if (waiting == 0 && done == 0) return null;
    return (waiting: waiting, done: done);
  }

  /// The bar's title, callout 2 of mockup 08 as R-31-08-25 leaves it: the
  /// platform's own button around [_PaneTitle], which opens the switcher,
  /// with the R-31-08-26 attention summary as its subtitle.
  Widget _titleControl() => _TitleControl(
    summary: _attentionSummary,
    // R-03-129: the tab title is the heading; the pane name only beside sibling agent panes;
    // with no tab title the pane name is the whole heading.
    title: _tabTitle == null || _tabTitle!.isEmpty ? _paneName : _tabTitle!,
    paneName: _tabTitle == null || _tabTitle!.isEmpty ? null : _titlePaneName,
    onPressed: _openPaneSwitcher,
  );

  /// R-32-510/R-32-511 as R-03-100 leaves them: the live indicator is the
  /// state bar, `size.icon.md` high like the control glyphs, with the
  /// connection word as its semantics label.
  Widget _liveDot() => Semantics(
    label: _linkWord.label,
    child: StatusBar(state: _liveState, height: AppSize.iconMd),
  );

  /// R-03-121: the state bar sits before the title, on its leading side,
  /// `space.2` apart, the way every list row puts its bar in the leading
  /// slot before its name (R-32-592, R-32-597; the `Live bar` row of
  /// `docs/32` section 7.3); never among the trailing actions. One group on
  /// the portrait bars of both platforms and on the landscape bar. The bar
  /// keeps its own semantics node, so the traversal reads the connection
  /// word, then the title (R-30-719).
  Widget _barAndTitle() => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      _liveDot(),
      const SizedBox(width: AppSpace.space2),
      Flexible(child: _titleControl()),
    ],
  );

  /// One icon control of R-32-510's app bar: the shared `ChromeIconAction`
  /// (R-33-033's `App bar action` row, R-33-076), so it presses the way every
  /// other bar action does and keeps keyboard focus and activation
  /// (R-30-718). `size.icon.lg` in `color.fg.primary`, [label] as its
  /// semantics label on both platforms and its tooltip on Android
  /// (R-30-717). A `null` [onPressed] disables it.
  Widget _barControl(
    AppColor color,
    IconData icon, {
    required String label,
    required VoidCallback? onPressed,
  }) => ChromeIconAction(
    icon: icon,
    label: label,
    onPressed: onPressed,
    color: color.fgPrimary,
  );

  /// The overflow of mockup 08's callout 5: the `more_vert` icon R-32-401
  /// names for `Pane actions`, with that name as its label (R-30-717).
  Widget _overflowControl(AppColor color) => _barControl(
    color,
    Symbols.more_vert_rounded,
    label: 'Pane actions',
    onPressed: _openPaneActions,
  );

  /// Landscape keeps the status readouts and view control inside the app bar.
  /// The range sits above the revision to leave room for the pane title; the
  /// attention summary of R-31-08-26 sits under the title, and the bar grows
  /// past `size.bar.merged` to hold it.
  Widget _landscapeBar(AppColor color, TerminalFrameState frame) {
    final ({int first, int last})? window = _visibleWindow;
    final String trailing = _deviceScrollOffset > 0
        ? '-$_deviceScrollOffset / ${frame.scroll.maxOffsetFromBottom}'
        : 'rev ${frame.revision}';
    final Widget content = Row(
      children: <Widget>[
        const SizedBox(width: AppSpace.space2),

        Expanded(child: _barAndTitle()),
        const SizedBox(width: AppSpace.space3),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            if (window != null)
              Text(
                'c${window.first}-${window.last}',
                style: AppType.caption.copyWith(color: color.fgSecondary),
              ),
            Text(
              trailing,
              style: AppType.caption.copyWith(color: color.fgSecondary),
            ),
          ],
        ),
        const SizedBox(width: AppSpace.space2),
        TerminalOverviewControl(
          overview: _overview,
          onPressed: _toggleOverview,
        ),
        // R-32-510's anatomy: `space.1` between two trailing controls.
        const SizedBox(width: AppSpace.space1),
        _overflowControl(color),
        const SizedBox(width: AppSpace.space2),
      ],
    );
    return Container(
      decoration: BoxDecoration(
        color: color.bgBase,
        border: Border(bottom: BorderSide(color: color.borderStrong)),
      ),
      // CupertinoNavigationBar supplies its own top inset.
      padding: _isIos
          ? EdgeInsets.zero
          : EdgeInsets.only(top: MediaQuery.viewPaddingOf(context).top),
      child: ConstrainedBox(
        // `size.bar.merged`: at least 56 on both platforms (R-32-543); the
        // iOS `size.appbar` of 44 belongs to `CupertinoNavigationBar` alone.
        constraints: const BoxConstraints(minHeight: AppSize.barMerged),
        child: _isIos
            ? CupertinoNavigationBar(
                backgroundColor: color.bgBase,
                border: null,
                leading: null,
                automaticallyImplyLeading: true,
                middle: content,
              )
            : Row(
                children: <Widget>[
                  BackButton(onPressed: widget.onBack),
                  Expanded(child: content),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final TerminalFrameState frame = _frame;
    final bool landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    _scheduleStateDialogSync();

    final Widget grid = TerminalViewWidget(
      key: _gridKey,
      palette: color,
      phase: _phase,
      terminal: _service.xterm,
      hostTheme: _service.hostTheme,
      textSize: _textSize,
      overview: _overview,
      revision: frame.revision,
      hostName: widget.hostName,
      captureTime: _lastFrameAt,
      reconnectAttempt: _reconnectAttempt,
      errorText: _offlineReason,
      maxScrollOffsetFromBottom: frame.scroll.maxOffsetFromBottom,
      onDiagnostics: widget.onDiagnostics,
      onRevoked: widget.onRevoked,
      onGridTap: _onGridTap,
      onSelectionLiveChanged: (bool live) =>
          _service.setSelectionLive(live: live),
      onScrollOffsetChanged: _onScrollOffsetRows,
      onVisibleColumnsChanged: _onVisibleColumnsChanged,
      onPinchSizeStep: _onPinchSizeStep,
      onForceRead: _onForceRead,
    );

    final Widget composer = Composer(
      key: _composerKey,
      focusNode: _composerFocus,
      panelOpen: _keyPanelOpen,
      onTogglePanel: _toggleKeyPanel,
      enabled: _phase == TerminalGridPhase.live,
      onText: _service.sendComposerText,
      onDelete: _service.sendComposerDeletions,
      onSubmit: _service.sendComposerSubmit,
      inputFormatters: [
        TextInputFormatter.withFunction(
          (before, after) =>
              _keyRowKey.currentState?.formatComposerEdit(before, after) ??
              after,
        ),
      ],
    );
    final Widget strip = StatusStrip(
      columns: frame.columns,
      rows: frame.rows,
      linkWord: _linkWord,
      overview: _overview,
      onToggleOverview: _toggleOverview,
      revision: frame.revision,
      scrollOffsetFromBottom: _deviceScrollOffset,
      scrollMaxOffsetFromBottom: frame.scroll.maxOffsetFromBottom,
      firstVisibleColumn: _visibleWindow?.first,
      lastVisibleColumn: _visibleWindow?.last,
      textSizeFlash: _sizeFlash,
    );
    final Widget keyRow = KeyRow(
      grid: landscape
          ? grid
          : Column(
              children: <Widget>[
                Expanded(child: grid),
                strip,
              ],
            ),
      key: _keyRowKey,
      focusNode: _composerFocus,
      panelOpen: _keyPanelOpen,
      composer: composer,
      paneId: widget.paneId,
      send: widget.send,
      sendInputAcks: _ackController.stream,
      linkState: _keyRowLinkState,
      offlineReason: _offlineReason,
      onDiagnostics: widget.onDiagnostics,
      reconciliationSignal: frame.revision,
      landscape: landscape,
    );

    if (landscape) {
      // The status strip disappears; its readouts move into the merged
      // bar and the key row. The grid background keeps running edge to
      // edge and under a side cutout (R-21-039), so no SafeArea wraps
      // the grid here; the key row alone stays inside the system inset.
      final Widget body = Column(
        children: <Widget>[
          _landscapeBar(color, frame),
          Expanded(child: keyRow),
        ],
      );
      if (_isIos) {
        return CupertinoPageScaffold(child: body);
      }
      return Scaffold(body: body);
    }

    // The key row is the last thing above the system navigation bar;
    // nothing may sit under it.
    final Widget body = SafeArea(top: false, child: keyRow);
    if (_isIos) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          backgroundColor: color.bgBase,
          border: Border(
            bottom: BorderSide(color: color.borderStrong, width: 1),
          ),
          leading: null,
          automaticallyImplyLeading: true,
          middle: _barAndTitle(),
          trailing: _overflowControl(color),
          // R-31-08-26 (amended 2026-09-11): the attention summary is the
          // title's subtitle, inside `middle`; the 44 row never grows
          // (R-33-076) because the two lines fit its height.
        ),
        child: body,
      );
    }
    return Scaffold(
      appBar: AppBar(
        backgroundColor: color.bgBase,
        elevation: 0,
        leading: BackButton(onPressed: widget.onBack),
        title: _barAndTitle(),
        actions: <Widget>[
          _overflowControl(color),
          const SizedBox(width: AppSpace.space2),
        ],
        // R-31-08-26 (amended 2026-09-11): the attention summary is the
        // title's subtitle, inside `title`; the `bottom` slot holds only the
        // bar's one edge.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: color.borderStrong),
        ),
      ),
      body: body,
    );
  }
}

/// The ways out of the R-03-119 alert: [back] is [TerminalScreen.onBack],
/// for `Back` and `Back to agents` alike; [tryAgain] is one more
/// `watch_pane` attach.
enum _StateAction { back, tryAgain }

/// The alert on screen and the phase it was raised for.
typedef _StateDialog = ({
  TerminalGridPhase phase,
  ChromeDialogHandle<_StateAction> dialog,
});

/// The bar's title as R-31-08-25 leaves it (R-03-113 item 1): the platform's
/// own button (R-03-059) around [_PaneTitle] and the `expand_more` glyph of
/// R-32-401's `Expand, collapse` row at `size.icon.md` in `color.fg.secondary`,
/// the same pair the `Agents` host chip draws for a title that opens a
/// chooser. Android: a `TextButton` in the heading's own `color.fg.primary`
/// ink over the theme's `color.accent.soft` press wash; iOS: a plain
/// `CupertinoButton` with the platform's press fade. One semantics node,
/// `<title>, switch pane`, a button (R-32-505); a `null` [onPressed] leaves
/// the same heading with no button and no glyph.
class _TitleControl extends StatelessWidget {
  const _TitleControl({
    required this.title,
    required this.onPressed,
    this.paneName,
    this.summary,
  });

  /// The heading: the tab title, or the pane name when the tab has none (R-03-129).
  final String title;

  /// The pane name drawn after ` / `, only when the tab holds sibling agent panes
  /// (R-03-129); `null` otherwise.
  final String? paneName;
  final VoidCallback? onPressed;

  /// R-31-08-26 (amended 2026-09-11): the attention summary is the title's
  /// own subtitle, one caption line under the name on the same text edge, so
  /// the bar reads as one two-line heading and not a title with a stray line
  /// under it. `null` while both counts are zero.
  final ({int waiting, int done})? summary;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final Widget heading = _PaneTitle(title: title, paneName: paneName);
    final ({int waiting, int done})? counts = summary;
    Widget withSubtitle(Widget line) => counts == null
        ? line
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[line, _SummaryText(counts)],
          );
    if (onPressed == null) return withSubtitle(heading);
    // The chevron sits on the heading line, never centred on the two-line
    // block, so the subtitle hangs under both the name and the glyph.
    final Widget label = withSubtitle(
      Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Flexible(child: heading),
          const SizedBox(width: AppSpace.space1),
          Icon(
            Symbols.expand_more_rounded,
            size: AppSize.iconMd,
            color: color.fgSecondary,
          ),
        ],
      ),
    );
    final String name = paneName == null ? title : '$title / $paneName';
    final String spoken = counts == null
        ? name
        : '$name, ${counts.waiting} waiting, ${counts.done} done';
    final Widget button = _isIos
        ? CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.space2),
            onPressed: onPressed,
            child: label,
          )
        : TextButton(
            style: TextButton.styleFrom(
              foregroundColor: color.fgPrimary,
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.space2),
              alignment: AlignmentDirectional.centerStart,
            ),
            onPressed: onPressed,
            child: label,
          );
    return Semantics(
      label: '$spoken, switch pane',
      button: true,
      onTap: onPressed,
      excludeSemantics: true,
      child: button,
    );
  }
}

/// The R-31-08-26 summary uses caption text and one secondary ink.
/// Numbers take the existing body-strong weight; space.3 separates the pairs.
class _SummaryText extends StatelessWidget {
  const _SummaryText(this.counts);

  final ({int waiting, int done}) counts;

  @override
  Widget build(BuildContext context) {
    final TextStyle number = TextStyle(
      fontWeight: AppType.bodyStrong.fontWeight,
    );
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          TextSpan(text: '${counts.waiting}', style: number),
          const TextSpan(text: ' waiting'),
          const WidgetSpan(child: SizedBox(width: AppSpace.space3)),
          TextSpan(text: '${counts.done}', style: number),
          const TextSpan(text: ' done'),
        ],
      ),
      style: AppType.caption.copyWith(color: AppColor.of(context).fgSecondary),
      semanticsLabel: '${counts.waiting} waiting, ${counts.done} done',
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// The title of R-31-08-25 keeps the pane name readable, per mockup 08
/// callout 2. The pane takes its natural width, capped at the available
/// title width. The tab uses the rest and truncates first on overflow.
class _PaneTitle extends StatelessWidget {
  const _PaneTitle({required this.title, this.paneName});

  final String title;
  final String? paneName;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final style = AppType.heading.copyWith(color: color.fgPrimary);
    final String? pane = paneName;
    if (pane == null) {
      return Text(
        title,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    // The separator and the pane name share one box capped at the row width, so the pane
    // takes its natural width, a too-long pane truncates without overflowing, and the
    // separator is never eaten by an ellipsis. The tab is the one flexible child: it takes
    // every pixel the pane does not need and gives characters up first when the pair does
    // not fit, so the pane name stays readable (mockup 08 callout 2).
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Flexible(
            child: Text(
              title,
              style: style,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(' / ', style: style, maxLines: 1, softWrap: false),
                Flexible(
                  child: Text(
                    pane,
                    style: style,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
