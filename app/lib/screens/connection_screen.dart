/// `docs/90-implementation-plan.md` §5.2 Phase 21, `WP-21-a`: the eleven diagnostics rows of
/// `docs/31-mockups/13-connection.md` (both legs, the round trip, `Herdr protocol`/`version`,
/// `RENDER`, `THIS SESSION, THIS COMPUTER`, `ALERTS`, `LAST ERROR`, `copy` and the
/// Disconnect/Forget/Remove/switch table — R-31-13-01 to 04, 06 to 10, 12, 13, 18, 19). `WP-18-d`
/// built the two structural checkboxes below it (`Reconnect now`, R-31-13-20; the `Disconnect`
/// text action, R-31-13-13/15/16/17) and this file's original app-bar/host-name/actions
/// skeleton.
///
/// **Documented ownership deviation.** `app/lib/screens/connection_screen.dart` is `WP-18-d`'s
/// owned path, routed to `WP-21-a` "on request" per `docs/90-implementation-plan.md` §5.3 — the
/// normal pattern has the owning session make a routed edit itself. `WP-18-d`'s own session had
/// already terminated by the time this request was made (confirmed unreachable), so `WP-21-a`
/// made this edit directly, with the requesting Main agent's explicit authorisation, rather than
/// leave the checkboxes undone. Every value below still arrives as a plain constructor argument
/// (see the next paragraph) — this file still imports no `RelayConnection`, `TerminalService` or
/// `NotificationsService` directly, so the deviation changes who wrote the code, not the file's
/// architecture.
///
/// Every value that depends on where the live connection comes from is a plain constructor
/// argument, the same idiom `pane_actions_sheet.dart` and `device_list_screen.dart` already set.
/// [ConnectionDiagnostics] bundles the session-scoped numbers that arrive at their own cadence
/// (`RelayConnection.framesIn`/`framesOut`/`bytesInOnWire`/`bytesInUnpacked`/`lastRoundTrip`,
/// `HostInfo.herdrProtocol`/`herdrVersion`, and `TerminalFrameState.columns`/`rows`/
/// `longestLineDrawn`/`unknownSgrCount`) so a caller (`app/lib/routing.dart`, `WP-12-b`) can
/// rebuild and emit one fresh snapshot on whatever cadence its own sources change, without this
/// file taking a dependency on any of those three services. [messages] supplies the raw
/// `LAST ERROR` text from an `error` frame (R-31-13-02, R-11-092); [connectionState]'s
/// `RelayDisconnected.closeCode` supplies the same row's other raw-text source, an abnormal
/// WebSocket close with no preceding `error` frame.
///
/// The `STAGES` group (added 2026-09-09, `docs/03-product-decisions.md` R-03-113 items 3 and
/// 7, R-31-13-24) reads the same [connectionState] stream: `RelayConnecting.stage` is the step
/// in flight, `RelayDisconnected.failedStage`/`failure` and `RelayRegistrationError.message`
/// are the step the attempt stopped at and its raw text, and `RelayReconnecting.delay` is the
/// wait before the next attempt. Every attempt this screen can observe reuses the cached handle
/// (`ConnectionStage.reusingHandle`), so the list always draws that stage first.
library;

import 'dart:async' show StreamSubscription, unawaited;

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoNavigationBar, CupertinoPageScaffold;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, visibleForTesting;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart'
    show
        Border,
        BorderSide,
        BuildContext,
        Column,
        CrossAxisAlignment,
        EdgeInsets,
        Expanded,
        Flexible,
        MainAxisAlignment,
        TextAlign,
        IntrinsicHeight,
        CustomScrollView,
        Padding,
        Row,
        SafeArea,
        SliverList,
        SliverPadding,
        Semantics,
        SizedBox,
        State,
        StatefulWidget,
        StatelessWidget,
        Text,
        TextBaseline,
        TextStyle,
        VoidCallback,
        Widget;
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart'
    show AppBar, Container, PreferredSize, Scaffold, Size;

import '../core/result/result.dart' show Result;
import '../models/message.dart' show Message, MessageError;
import '../services/relay.dart'
    show
        ConnectionStage,
        RelayConnected,
        RelayConnecting,
        RelayConnectionState,
        RelayDisconnected,
        RelayReconnecting,
        RelayRegistrationError,
        RelayRegistrationErrorCode,
        RelayRevoked;
import '../widgets/app_filled_button.dart';
import '../widgets/app_strip.dart';
import '../widgets/app_text_button.dart';
import '../widgets/status_bar.dart' show BarState, StatusBar;
import '../widgets/theme/app_color.dart';
import '../widgets/theme/app_space.dart';
import '../widgets/theme/app_type.dart';
import '../widgets/theme/chrome_icon_action.dart' show ChromeIconAction;
import '../widgets/treatments.dart';

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

/// `border.hairline`, per `docs/32-design-language.md` R-32-330. Every border width outside
/// `elev.1`'s stays a local constant beside its one caller, matching every other screen's own
/// `_hairlineWidth`.
const double _hairlineWidth = 1;

/// R-10-012: the Herdr socket protocol this app expects on `host_info.herdr_protocol`.
/// Re-measured 2026-09-02 against Herdr `0.8.2-preview.2026-08-31-b1ff4582e968`
/// (`docs/02-herdr-probe-results.md` R-02-028).
const int expectedHerdrProtocol = 22;

/// R-31-13-10: a longer gap than this between `Grid from the computer` and `Longest line drawn`
/// takes `treat.warning`. The Host's own row padding normally produces a 2-to-4-cell gap; this
/// is double the widest normal value.
const int longestLineWarningGapCells = 8;

/// One snapshot of every diagnostics value this screen draws that is not already covered by
/// [ConnectionScreen.connectionState] (the leg words) or [ConnectionScreen.messages] (the raw
/// `LAST ERROR` text). See this file's own header comment for the full contract and the exact
/// source of each field.
final class ConnectionDiagnostics {
  const ConnectionDiagnostics({
    this.herdrProtocol,
    this.herdrVersion,
    this.framesIn,
    this.framesOut,
    this.bytesInOnWire,
    this.bytesInUnpacked,
    this.roundTrip,
    this.gridColumns,
    this.gridRows,
    this.longestLineDrawn,
    this.unknownSgrCount,
  });

  /// `HostInfo.herdrProtocol`. `null` before the first `host_info` this session.
  final int? herdrProtocol;

  /// `HostInfo.herdrVersion`.
  final String? herdrVersion;

  /// `RelayConnection.framesIn` (R-31-13-06). `null` with no live session — read as `-`, never
  /// `0`.
  final int? framesIn;

  /// `RelayConnection.framesOut`.
  final int? framesOut;

  /// `RelayConnection.bytesInOnWire` — the compressed record bytes read off the wire.
  final int? bytesInOnWire;

  /// `RelayConnection.bytesInUnpacked` — the decompressed envelope bytes. The compression
  /// percentage this screen shows is derived as `bytesInOnWire / bytesInUnpacked * 100`
  /// (R-31-13-06); this class carries only the two counts.
  final int? bytesInUnpacked;

  /// `RelayConnection.lastRoundTrip` (R-31-13-19). `null` before the first correlated reply
  /// this session.
  final Duration? roundTrip;

  /// `TerminalFrameState.columns`, i.e. the Host's `rect.width` (R-31-13-07). `null` when no
  /// pane has been opened this session — the `RENDER` group then reads `-` with the
  /// `Open a pane to measure this.` hint, never `0`.
  final int? gridColumns;

  /// `TerminalFrameState.rows`, i.e. `scroll.viewport_rows`.
  final int? gridRows;

  /// `TerminalFrameState.longestLineDrawn` (R-31-13-09, R-31-13-10).
  final int? longestLineDrawn;

  /// `TerminalFrameState.unknownSgrCount` (R-31-13-08). Never hidden at `0` — `0` is the
  /// reassurance the row exists to give.
  final int? unknownSgrCount;
}

/// The connection status and diagnostics screen (`docs/31-mockups/13-connection.md`, route
/// `/hosts/:hostId/diagnostics`). See this file's own header comment for the split between
/// `WP-18-d`'s original two checkboxes and `WP-21-a`'s later eleven.
class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({
    super.key,
    required this.hostId,
    required this.hostName,
    this.connectionState,
    this.initialConnectionState,
    required this.onReconnect,
    this.onDisconnect,
    this.onDisconnected,
    this.relayOrigin,
    this.diagnostics,
    this.messages,
    this.alertsDeliveryWord,
    this.onOpenAlertsSettings,
    this.onCopied,
  });

  /// The computer this screen names. `Reconnect now` rebuilds exactly this connection and
  /// never another one, per R-31-13-20.
  final String hostId;

  /// The computer's display name.
  final String hostName;

  /// `null` is the `Saved, not connected` state's own exception, per R-30-946: no live link
  /// exists for [hostId] at all, so there is nothing to subscribe to.
  final Stream<RelayConnectionState>? connectionState;

  /// The link state at the moment this screen opens. [connectionState] is a broadcast stream
  /// with no replay, and a person opens diagnostics on a link that is already connected, so
  /// without this the legs read `checking` until the next state change. `null` keeps the
  /// `Loading` legs.
  final RelayConnectionState? initialConnectionState;

  /// Tears down and rebuilds the connection named by [hostId] (R-31-13-20). The caller closes
  /// over [hostId], so this widget structurally cannot reach a different computer.
  final Future<Result<void>> Function() onReconnect;

  /// Closes this phone's link to the relay. `null` exactly when [connectionState] is `null`
  /// (R-31-13-13: "MUST be absent when there is no link to close").
  final Future<void> Function()? onDisconnect;

  /// Fired after a successful disconnect. The caller routes to `/hosts` and shows its own
  /// snackbar (R-90-024, and the mockup's Navigation section: "Out, `Disconnect`: `/hosts`...
  /// A snackbar carries the result") — this file owns no route and shows no snackbar itself.
  final VoidCallback? onDisconnected;

  /// The relay origin exactly as stored (R-30-922), shown in full under leg one. `null` matches
  /// [connectionState] being `null`.
  final String? relayOrigin;

  /// The session-scoped numbers `RENDER`, `THIS SESSION, THIS COMPUTER` and the protocol row
  /// draw. See [ConnectionDiagnostics]'s own doc comment. `null` before the first snapshot
  /// arrives (the `Loading` state); every field inside may independently be `null`.
  final Stream<ConnectionDiagnostics>? diagnostics;

  /// Every decrypted application message this session receives (`RelayConnection.messages`),
  /// read only for `error` frames (R-31-13-02, R-11-092). `null` matches [connectionState]
  /// being `null`.
  final Stream<Message>? messages;

  /// The `ALERTS` header word: `ready`, `silenced` or `off` (R-31-13-22), from the same reading
  /// `NotificationsService.effectiveDeliveryState()` gives `/settings/notifications`. `null`
  /// before the first read.
  final String? alertsDeliveryWord;

  /// Routes to `/settings/notifications` from the `ALERTS` group's `Fix this in Alerts.` line,
  /// shown only when [alertsDeliveryWord] is `silenced` or `off`.
  final VoidCallback? onOpenAlertsSettings;

  /// Fired after `copy` writes the clipboard. The caller shows its own `Copied.` snackbar
  /// (R-90-024), matching [onDisconnected]'s split.
  final VoidCallback? onCopied;

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

/// R-31-13-01 leg words: `checking` (Loading), `connected` (`treat.ok`), `connecting`
/// (`treat.warning`), `offline`/`in use` (`treat.error`/`treat.warning`), `unknown` and
/// `not connected` (both plain, `color.fg.secondary`, no icon — `unknown` per callout 4's own
/// "That honesty matters more than a guess"). [working] is the stage list's running step
/// (R-31-13-24): the pulsing `working` bar, and a word with no treatment icon, because the bar
/// is the one mark.
enum _Treat { plain, ok, warning, error, working }

final class _Leg {
  const _Leg(
    this.word,
    this.treat, {
    this.subLine,
    this.extraLines = const <String>[],
    this.rawText,
  });
  final String word;
  final _Treat treat;
  final String? subLine;
  final List<String> extraLines;

  /// R-30-803, R-31-13-24: the raw error text of a failed stage, drawn in `type.mono.code`
  /// under the label, never rewritten.
  final String? rawText;
}

final class _Legs {
  const _Legs(this.legOne, this.legTwo);
  final _Leg legOne;
  final _Leg legTwo;
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  bool _reconnecting = false;
  bool _disconnecting = false;
  String? _disconnectError;

  /// The latest connection state. Drives both legs (R-31-13-01) and, via [_onConnectionState],
  /// the `RelayDisconnected.closeCode` half of `LAST ERROR` (R-31-13-02).
  late RelayConnectionState? _liveState = widget.initialConnectionState;

  @visibleForTesting
  RelayConnectionState? get debugLiveState => _liveState;

  /// The latest diagnostics snapshot (R-31-13-06, 07 to 10, 19, protocol row). `null` renders
  /// every dependent row as `-`.
  ConnectionDiagnostics? _diagnostics;

  @visibleForTesting
  ConnectionDiagnostics? get debugDiagnostics => _diagnostics;

  /// The raw `LAST ERROR` text and when it arrived (R-31-13-02, R-11-092). Two sources feed
  /// this: a `MessageError` on [ConnectionScreen.messages], and a `RelayDisconnected` with a
  /// non-null `closeCode` on [ConnectionScreen.connectionState]. Whichever lands most recently
  /// wins, per the mockup's own "shown as it arrived" (never merged, never a history).
  String? _lastErrorText;
  DateTime? _lastErrorAt;

  @visibleForTesting
  String? get debugLastErrorText => _lastErrorText;

  /// R-03-113 item 3, R-31-13-24: what the `STAGES` group draws. [_stageRunning] is the step
  /// of the attempt in flight; [_stageFailed] and [_stageError] are the step the last attempt
  /// stopped at and its raw text (R-30-803); [_retryIn] is the backoff wait in progress. A new
  /// attempt clears the failure, so a stale error never sits beside a working bar.
  ConnectionStage? _stageRunning;
  ConnectionStage? _stageFailed;
  String? _stageError;
  Duration? _retryIn;

  StreamSubscription<RelayConnectionState>? _connectionSub;
  StreamSubscription<ConnectionDiagnostics>? _diagnosticsSub;
  StreamSubscription<Message>? _messagesSub;

  @override
  void initState() {
    super.initState();
    _trackStages(widget.initialConnectionState);
    _connectionSub = widget.connectionState?.listen(_onConnectionState);
    _diagnosticsSub = widget.diagnostics?.listen(_onDiagnostics);
    _messagesSub = widget.messages?.listen(_onMessage);
  }

  @override
  void dispose() {
    unawaited(_connectionSub?.cancel());
    unawaited(_diagnosticsSub?.cancel());
    unawaited(_messagesSub?.cancel());
    super.dispose();
  }

  void _onConnectionState(RelayConnectionState state) {
    if (!mounted) return;
    setState(() {
      _liveState = state;
      _trackStages(state);
      // R-31-13-02: the raw WS close code is the LAST ERROR source when the link drops with
      // no preceding `error` frame. A deliberate close (Disconnect, background) never carries
      // a close code here — `relay.dart` sets both to `null` on that path.
      if (state is RelayDisconnected && state.closeCode != null) {
        _lastErrorText = 'websocket closed ${state.closeCode}';
        _lastErrorAt = DateTime.now();
      }
    });
  }

  /// Folds one state into the stage fields. `RelayReconnecting` keeps the failed stage and
  /// its raw text on screen through the wait, because that failure is why the app is waiting.
  void _trackStages(RelayConnectionState? state) {
    switch (state) {
      case RelayConnecting(:final stage):
        _stageRunning = stage;
        _stageFailed = null;
        _stageError = null;
        _retryIn = null;
      case RelayDisconnected(:final failedStage, :final failure):
        _stageRunning = null;
        _stageFailed = failedStage;
        _stageError = failure;
        _retryIn = null;
      case RelayRegistrationError(:final message):
        _stageRunning = null;
        _stageFailed = ConnectionStage.registeringHandle;
        _stageError = message;
        _retryIn = null;
      case RelayReconnecting(:final delay):
        _stageRunning = null;
        _retryIn = delay;
      case RelayConnected() || RelayRevoked():
        _stageRunning = null;
        _stageFailed = null;
        _stageError = null;
        _retryIn = null;
      case null:
        break;
    }
  }

  /// The `STAGES` group exists once there is an attempt to describe: one running, one that
  /// failed, one whose retry is being waited out, or the connected link every stage built.
  bool get _showStages =>
      widget.connectionState != null &&
      (_liveState is RelayConnected ||
          _stageRunning != null ||
          _stageFailed != null ||
          _retryIn != null);

  /// One stage row (R-31-13-24): `ok` before the running or failed step, `working` at the
  /// running step, `error` with the raw text at the failed step, `pending` after either.
  _Leg _stageLeg(ConnectionStage stage) {
    if (_liveState is RelayConnected) return const _Leg('ok', _Treat.ok);
    final ConnectionStage? running = _stageRunning;
    if (running != null) {
      if (stage.index < running.index) return const _Leg('ok', _Treat.ok);
      if (stage == running) return const _Leg('working', _Treat.working);
      return const _Leg('pending', _Treat.plain);
    }
    final ConnectionStage? failed = _stageFailed;
    if (failed != null) {
      if (stage.index < failed.index) return const _Leg('ok', _Treat.ok);
      if (stage == failed) {
        return _Leg('error', _Treat.error, rawText: _stageError);
      }
    }
    return const _Leg('pending', _Treat.plain);
  }

  void _onDiagnostics(ConnectionDiagnostics diagnostics) {
    if (mounted) setState(() => _diagnostics = diagnostics);
  }

  void _onMessage(Message message) {
    if (!mounted || message is! MessageError) return;
    setState(() {
      _lastErrorText = message.payload.message;
      _lastErrorAt = DateTime.now();
    });
  }

  /// R-31-13-20: rebuilds the connection [widget.onReconnect] closes over, regardless of
  /// `Ok`/`Err` — the resulting [RelayConnectionState] this screen already tracks is the
  /// existing, correct failure signal, so this method builds no second one.
  Future<void> _reconnect() async {
    if (_reconnecting) return;
    setState(() => _reconnecting = true);
    await widget.onReconnect();
    if (!mounted) return;
    setState(() => _reconnecting = false);
  }

  /// R-31-13-15: a thrown failure leaves the link open, keeps this route, and shows the
  /// `Error, disconnect failed` strip with a `Try again`. A success calls
  /// [ConnectionScreen.onDisconnected] and stops; the caller's own route change and snackbar
  /// follow from there.
  Future<void> _disconnect() async {
    if (_disconnecting || widget.onDisconnect == null) return;
    setState(() {
      _disconnecting = true;
      _disconnectError = null;
    });
    try {
      await widget.onDisconnect!();
      if (!mounted) return;
      widget.onDisconnected?.call();
    } on Exception catch (_) {
      if (!mounted) return;
      setState(() {
        _disconnecting = false;
        _disconnectError = 'Could not disconnect. The link is still open.';
      });
    }
  }

  /// R-31-13-01, and the `Loading`/`Error, leg one down`/`Error, leg two down`/
  /// `Error, host in use`/`Saved, not connected` state-table rows. Since 2026-09-09 the failed
  /// stage of R-31-13-24 says which half broke: an attempt that got past `Opening WebSocket`
  /// reached the relay, so leg one reads `connected` and leg two carries the failure. A relay
  /// that answers `handle_unknown` is the mockup's `Error, leg two down` row exactly: no Host
  /// is registered, so leg two reads `offline` with the `Relay pane` line. A handshake or
  /// `host_info` failure reads leg two as `unknown`, because the Host answered and the stage
  /// row already carries the raw text; a guess at a leg word would add nothing (callout 4's
  /// own "That honesty matters more than a guess"). A drop with no stage, and a failure to
  /// open the socket at all, read leg one as `offline` and leg two as `unknown`, as before.
  _Legs _legs() {
    if (widget.connectionState == null) {
      return const _Legs(
        _Leg('not connected', _Treat.plain),
        _Leg('not connected', _Treat.plain),
      );
    }
    final RelayConnectionState? state = _liveState;
    return switch (state) {
      null || RelayConnecting() => const _Legs(
        _Leg('checking', _Treat.plain),
        _Leg('checking', _Treat.plain),
      ),
      RelayConnected() => _Legs(
        _Leg('connected', _Treat.ok, subLine: widget.relayOrigin),
        _Leg('connected', _Treat.ok, subLine: widget.hostName),
      ),
      RelayReconnecting() => _Legs(
        _Leg('connecting', _Treat.warning, subLine: widget.relayOrigin),
        const _Leg('unknown', _Treat.plain),
      ),
      RelayRegistrationError(code: RelayRegistrationErrorCode.hostInUse) =>
        _Legs(
          _Leg('connected', _Treat.ok, subLine: widget.relayOrigin),
          _Leg(
            'in use',
            _Treat.warning,
            subLine: widget.hostName,
            extraLines: <String>[
              'Another phone is using ${widget.hostName}.',
              'One phone at a time. Disconnect there, or remove that phone in the Relay pane.',
            ],
          ),
        ),
      RelayRegistrationError(code: RelayRegistrationErrorCode.handleUnknown) =>
        _Legs(
          _Leg('connected', _Treat.ok, subLine: widget.relayOrigin),
          _Leg(
            'offline',
            _Treat.error,
            subLine: widget.hostName,
            extraLines: <String>[
              'The Relay pane may be closed on ${widget.hostName}.',
            ],
          ),
        ),
      RelayRegistrationError() ||
      RelayDisconnected(
        failedStage: ConnectionStage.handshake || ConnectionStage.hostInfo,
      ) => _Legs(
        _Leg('connected', _Treat.ok, subLine: widget.relayOrigin),
        const _Leg('unknown', _Treat.plain),
      ),
      RelayDisconnected() || RelayRevoked() => _Legs(
        _Leg('offline', _Treat.error, subLine: widget.relayOrigin),
        const _Leg('unknown', _Treat.plain),
      ),
    };
  }

  /// `Try again` replaces `Reconnect now` while the last attempt failed at a stage
  /// (R-31-13-24), making one attempt. `host_in_use` is one such failure (R-30-942), so this
  /// generalises that row of the states table; R-31-13-17 still holds: the control closes only
  /// this phone's own link. The screen draws no second retry control (R-30-804).
  bool get _attemptFailed => _stageFailed != null;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    // R-03-107 (amended 2026-09-09): a screen with content paints plain
    // `color.bg.base`, no ground grid and no paper block.
    final Widget body = _buildBody(context);
    final Widget title = Text(
      'Connection',
      style: AppType.heading.copyWith(color: color.fgPrimary),
    );
    // R-32-115, R-32-510: the app bar's bottom edge is `color.border.strong` on both platforms.
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
          middle: title,
          trailing: _copyButton(),
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
        actions: <Widget>[_copyButton()],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(_hairlineWidth),
          child: Container(color: color.borderStrong, height: _hairlineWidth),
        ),
      ),
      body: body,
    );
  }

  /// R-31-13-05: the app-bar `copy` action, the one app bar icon action of R-33-033.
  /// `Copy this page` is its screen-reader label (R-30-717).
  Widget _copyButton() => ChromeIconAction(
    icon: Symbols.content_copy_rounded,
    label: 'Copy this page',
    onPressed: _copy,
  );

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _copyText()));
    widget.onCopied?.call();
  }

  /// R-31-13-05: plain text, no colour codes, no emoji. MUST include the relay origin; MUST
  /// NOT include the routing handle, a phrase, a key or a key fingerprint — none of which this
  /// file ever receives as a constructor argument, so that half of the rule holds structurally.
  String _copyText() {
    final _Legs legs = _legs();
    final ConnectionDiagnostics? d = _diagnostics;
    final List<String> lines = <String>[
      'Connection',
      widget.hostName,
      'Phone to relay: ${legs.legOne.word}',
      if (widget.relayOrigin != null) '  ${widget.relayOrigin}',
      'Relay to computer: ${legs.legTwo.word}',
      if (_showStages) ...<String>[
        'STAGES',
        for (final ConnectionStage stage in ConnectionStage.values)
          '  ${stage.label}: ${_stageLeg(stage).word}',
        if (_stageError != null) '  $_stageError',
        if (_retryIn != null) '  Retrying in ${_secondsLabel(_retryIn!)}.',
      ],
      'Phone to computer, round trip: ${_msLabel(d?.roundTrip)}',
      'Herdr protocol: ${d?.herdrProtocol?.toString() ?? '-'}',
      'Herdr version: ${d?.herdrVersion ?? '-'}',
      'RENDER',
      '  Grid from the computer: ${_gridLabel(d)}',
      '  Longest line drawn: ${d?.longestLineDrawn?.toString() ?? '-'}',
      '  Unknown SGR codes: ${d?.unknownSgrCount?.toString() ?? '-'}',
      'THIS SESSION, THIS COMPUTER',
      '  Frames in: ${d?.framesIn?.toString() ?? '-'}',
      '  Frames out: ${d?.framesOut?.toString() ?? '-'}',
      '  Bytes in, on the wire: ${d?.bytesInOnWire?.toString() ?? '-'}',
      '  Bytes in, unpacked: ${d?.bytesInUnpacked?.toString() ?? '-'}',
      '  Compression: ${_compressionLabel(d)}',
      'ALERTS: ${widget.alertsDeliveryWord ?? '-'}',
      if (_lastErrorText != null) 'LAST ERROR: $_lastErrorText',
    ];
    return lines.join('\n');
  }

  Widget _buildBody(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final _Legs legs = _legs();
    final ConnectionDiagnostics? d = _diagnostics;
    final bool protocolMismatch =
        d?.herdrProtocol != null && d!.herdrProtocol != expectedHerdrProtocol;
    final bool sgrSeen = (d?.unknownSgrCount ?? 0) > 0;
    final bool longestLineGapWide =
        d?.gridColumns != null &&
        d?.longestLineDrawn != null &&
        d!.gridColumns! - d.longestLineDrawn! > longestLineWarningGapCells;

    // The computer's name heads the list and scrolls with it: pinned above the list it had no
    // edge of its own, so scrolled rows ran into it (amended 2026-09-08 by the product owner).
    return SafeArea(
      child: CustomScrollView(
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.all(AppSpace.space4),
            sliver: SliverList.list(
              children: <Widget>[
                Text(
                  widget.hostName,
                  style: AppType.bodyStrong.copyWith(color: color.fgPrimary),
                ),
                _legRow('Phone to relay', legs.legOne),
                _legRow('Relay to computer', legs.legTwo),
                if (_showStages) ...<Widget>[
                  const _GroupHeader('STAGES'),
                  for (final ConnectionStage stage in ConnectionStage.values)
                    _legRow(stage.label, _stageLeg(stage)),
                  if (_retryIn != null)
                    // The line closes the group: `space.3` under it, the row gap of the stage
                    // rows above, so the next value row does not run into it.
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.space3),
                      child: Text(
                        'Retrying in ${_secondsLabel(_retryIn!)}.',
                        style: AppType.caption.copyWith(
                          color: color.fgSecondary,
                        ),
                      ),
                    ),
                ],
                _ValueRow(
                  label: 'Phone to computer, round trip',
                  value: _msLabel(d?.roundTrip),
                ),
                _ValueRow(
                  label: 'Herdr protocol',
                  value: d?.herdrProtocol?.toString() ?? '-',
                  treat: protocolMismatch ? _Treat.error : _Treat.plain,
                  overrideText: protocolMismatch
                      ? '$expectedHerdrProtocol expected, ${d.herdrProtocol} found'
                      : null,
                  extraLine: protocolMismatch
                      ? 'Update Herdr on the computer, or update this app.'
                      : null,
                ),
                _ValueRow(
                  label: 'Herdr version',
                  value: d?.herdrVersion ?? '-',
                ),
                // R-33-045: the diagnostics screen MUST show that the fixed Herdr palette is
                // in use, observably, not silently. There is one palette on both platforms now
                // (`docs/33-platform-chrome.md` section 4), so this line is a constant fact,
                // never a live value.
                const _ValueRow(label: 'Chrome', value: 'fixed Herdr palette'),
                const _GroupHeader('RENDER'),
                if (d?.gridColumns == null || d?.gridRows == null) ...<Widget>[
                  const _ValueRow(label: 'Grid from the computer', value: '-'),
                  const _ValueRow(label: 'Longest line drawn', value: '-'),
                  const _ValueRow(label: 'Unknown SGR codes', value: '-'),
                  Text(
                    'Open a pane to measure this.',
                    style: AppType.caption.copyWith(color: color.fgSecondary),
                  ),
                ] else ...<Widget>[
                  _ValueRow(
                    label: 'Grid from the computer',
                    value: _gridLabel(d),
                  ),
                  _ValueRow(
                    label: 'Longest line drawn',
                    value: d?.longestLineDrawn?.toString() ?? '-',
                    treat: longestLineGapWide ? _Treat.warning : _Treat.plain,
                  ),
                  _ValueRow(
                    label: 'Unknown SGR codes',
                    value: d?.unknownSgrCount?.toString() ?? '-',
                    treat: sgrSeen ? _Treat.error : _Treat.plain,
                    extraLine: sgrSeen
                        ? 'Rendering may be wrong. Send this with Copy.'
                        : null,
                  ),
                ],
                const _GroupHeader('THIS SESSION, THIS COMPUTER'),
                _ValueRow(
                  label: 'Frames in',
                  value: d?.framesIn?.toString() ?? '-',
                ),
                _ValueRow(
                  label: 'Frames out',
                  value: d?.framesOut?.toString() ?? '-',
                ),
                _ValueRow(
                  label: 'Bytes in, on the wire',
                  value: d?.bytesInOnWire?.toString() ?? '-',
                ),
                _ValueRow(
                  label: 'Bytes in, unpacked',
                  value: d?.bytesInUnpacked?.toString() ?? '-',
                ),
                _ValueRow(label: 'Compression', value: _compressionLabel(d)),
                _AlertsGroup(
                  deliveryWord: widget.alertsDeliveryWord,
                  onOpenAlertsSettings: widget.onOpenAlertsSettings,
                ),
                if (_lastErrorText != null) ...<Widget>[
                  const _GroupHeader('LAST ERROR'),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          _lastErrorText!,
                          style: AppType.monoCode.copyWith(
                            color: color.fgPrimary,
                          ),
                        ),
                      ),
                      if (_lastErrorAt != null) ...<Widget>[
                        const SizedBox(width: AppSpace.space3),
                        Text(
                          _clockLabel(_lastErrorAt!),
                          style: AppType.caption.copyWith(
                            color: color.fgSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpace.space4),
                ],
                const _DistinctionTable(),
                // The wireframe of `13-connection.md` draws `Reconnect now` and `Disconnect` as
                // the last rows of the one list, never pinned over it (corrected 2026-09-03).
                if (_disconnectError != null) ...<Widget>[
                  const SizedBox(height: AppSpace.space4),
                  AppStrip(
                    trailing: AppTextButton(
                      label: 'Try again',
                      onPressed: _disconnecting
                          ? null
                          : () => unawaited(_disconnect()),
                    ),
                    child: Treatment.error(
                      label: _disconnectError!,
                      inStrip: true,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpace.space6),
                // R-31-13-16, R-31-13-17: enabled state keys off presence and in-flight status
                // only, never off `_liveState`'s offline or host-in-use case. The mockup's
                // `Disconnecting` state disables it while the link closes.
                AppFilledButton(
                  label: _attemptFailed ? 'Try again' : 'Reconnect now',
                  onPressed: _reconnecting || _disconnecting
                      ? null
                      : () => unawaited(_reconnect()),
                  isLoading: _reconnecting,
                ),
                if (widget.onDisconnect != null) ...<Widget>[
                  const SizedBox(height: AppSpace.space2),
                  // `Disconnecting`: the in-place spinner of R-32-350 takes the label's place
                  // and the tap is off, so nothing below it moves.
                  AppTextButton(
                    label: 'Disconnect',
                    isLoading: _disconnecting,
                    onPressed: _disconnecting
                        ? null
                        : () => unawaited(_disconnect()),
                  ),
                ],
                const SizedBox(height: AppSpace.space4),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One semantics node per row that reads the label, then the state word, then any raw text
  /// (the mockup's Accessibility section): the row's own texts are excluded, so a reader hears
  /// `Relay to computer, connected` once, not the label and the word as two nodes.
  Widget _legRow(String label, _Leg leg) => Semantics(
    excludeSemantics: true,
    label: leg.rawText == null
        ? '$label, ${leg.word}'
        : '$label, ${leg.word}, ${leg.rawText}',
    child: _LegGroup(
      label: label,
      word: leg.word,
      treat: leg.treat,
      subLine: leg.subLine,
      extraLines: leg.extraLines,
      rawText: leg.rawText,
    ),
  );
}

String _msLabel(Duration? d) => d == null ? '-' : '${d.inMilliseconds} ms';

/// `0.5 s`, `5 s`: the backoff wait in progress (R-31-13-11 permits a fact about now).
String _secondsLabel(Duration d) => d.inMilliseconds % 1000 == 0
    ? '${d.inSeconds} s'
    : '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s';

String _gridLabel(ConnectionDiagnostics? d) =>
    (d?.gridColumns == null || d?.gridRows == null)
    ? '-'
    : '${d!.gridColumns}x${d.gridRows}';

String _compressionLabel(ConnectionDiagnostics? d) {
  final int? onWire = d?.bytesInOnWire;
  final int? unpacked = d?.bytesInUnpacked;
  if (onWire == null || unpacked == null || unpacked == 0) return '-';
  return '${(onWire / unpacked * 100).round()}%';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

/// `14:02:11`, the `LAST ERROR` group's wall-clock time.
String _clockLabel(DateTime local) =>
    '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}:${_twoDigits(local.second)}';

/// One leg row (callouts 2 and 4, amended 2026-09-08 by the product owner, and 2026-09-09 per
/// R-03-100): the state bar in the state's hue at the leg's leading edge, as tall as the leg,
/// the label in `type.body`, the state word trailing it in `type.micro` UPPER
/// `color.fg.secondary` on the same baseline, and the sub-line (the relay origin or the host
/// name) and any explanatory lines in `type.caption` under the label, in the label's own
/// column, never under the bar (R-31-13-01). A stage row (R-31-13-24) is the same anatomy,
/// with [rawText] in `type.mono.code` under the label when the stage failed (R-30-803).
class _LegGroup extends StatelessWidget {
  const _LegGroup({
    required this.label,
    required this.word,
    required this.treat,
    this.subLine,
    this.extraLines = const <String>[],
    this.rawText,
  });

  final String label;
  final String word;
  final _Treat treat;
  final String? subLine;
  final List<String> extraLines;
  final String? rawText;

  // `ok`, not `done` (amended 2026-09-08, section 7.29 table): a connected leg is a healthy
  // link, not a finished task, and `color.status.ok` is the hue `Treatment.ok` beside it uses.
  // `warning`, not `working` (2026-09-09): a `connecting` or `in use` leg is a warning, and
  // only work pulses.
  static BarState _barStateFor(_Treat treat) => switch (treat) {
    _Treat.ok => BarState.ok,
    _Treat.warning => BarState.warning,
    _Treat.error => BarState.error,
    _Treat.working => BarState.working,
    _Treat.plain => BarState.unknown,
  };

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final TextStyle detail = AppType.caption.copyWith(color: color.fgSecondary);
    // `IntrinsicHeight` gives the stretched bar a bounded cross axis: the leg is as tall as its
    // lines, and the bar spans them.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.space3),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            StatusBar(state: _barStateFor(treat)),
            const SizedBox(width: AppSpace.space2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          label,
                          style: AppType.body.copyWith(color: color.fgPrimary),
                        ),
                      ),
                      const SizedBox(width: AppSpace.space3),
                      Text(
                        word.toUpperCase(),
                        style: AppType.micro.copyWith(color: color.fgSecondary),
                      ),
                    ],
                  ),
                  if (subLine != null) Text(subLine!, style: detail),
                  if (rawText != null) ...<Widget>[
                    const SizedBox(height: AppSpace.space1),
                    Text(
                      rawText!,
                      style: AppType.monoCode.copyWith(color: color.fgPrimary),
                    ),
                  ],
                  for (final String line in extraLines) ...<Widget>[
                    const SizedBox(height: AppSpace.space1),
                    Text(line, style: detail),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A state word: plain `color.fg.secondary` text for [_Treat.plain] (`checking`, `unknown`,
/// `not connected` — no icon, per the states table), one of the three [Treatment] widgets
/// otherwise.
class _StateWord extends StatelessWidget {
  const _StateWord(this.word, this.treat);
  final String word;
  final _Treat treat;

  @override
  Widget build(BuildContext context) => switch (treat) {
    _Treat.plain || _Treat.working => Text(
      word,
      style: AppType.label.copyWith(color: AppColor.of(context).fgSecondary),
    ),
    _Treat.ok => Treatment.ok(label: word),
    _Treat.warning => Treatment.warning(label: word),
    _Treat.error => Treatment.error(label: word),
  };
}

/// One label/value row shared by the protocol, `RENDER` and session-counter rows: the label in
/// `type.body` `color.fg.secondary`, the value in `type.mono.code` `color.fg.primary` on the
/// label's alphabetic baseline, so a 13 px mono value never floats above or below a 16 px label.
class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.label,
    required this.value,
    this.treat = _Treat.plain,
    this.overrideText,
    this.extraLine,
  });

  final String label;
  final String value;
  final _Treat treat;

  /// Replaces [value]'s displayed text without changing [Semantics] wording built from
  /// [value] — used only by the protocol-mismatch row, whose R-31-13-04 wording ("`20
  /// expected, 22 found`") differs from the bare number [value] otherwise shows.
  final String? overrideText;
  final String? extraLine;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final String shown = overrideText ?? value;
    return Semantics(
      label: '$label, $shown',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.space2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Flexible(
                  child: Text(
                    label,
                    style: AppType.body.copyWith(color: color.fgSecondary),
                  ),
                ),
                const SizedBox(width: AppSpace.space3),
                // A long value (a Herdr preview version is 40 characters) keeps the
                // label whole: the value wraps on its own lines, right-aligned.
                Flexible(
                  child: treat == _Treat.plain
                      ? Text(
                          shown,
                          textAlign: TextAlign.end,
                          style: AppType.monoCode.copyWith(
                            color: color.fgPrimary,
                          ),
                        )
                      : _StateWord(shown, treat),
                ),
              ],
            ),
            if (extraLine != null) ...<Widget>[
              const SizedBox(height: AppSpace.space1),
              Text(
                extraLine!,
                style: AppType.caption.copyWith(color: color.fgSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// An upper-case group header, `type.micro` (R-31-13-06's `THIS SESSION, THIS COMPUTER`,
/// callout 7's `RENDER`, callout 14's `LAST ERROR`).
class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      top: AppSpace.space6,
      bottom: AppSpace.space2,
    ),
    child: Text(
      title,
      style: AppType.micro.copyWith(color: AppColor.of(context).fgSecondary),
    ),
  );
}

/// R-31-13-12: the exact wording of R-30-512 and R-30-517, with the header word `ready`,
/// `silenced` or `off` (R-31-13-22) and, for the latter two, the `Fix this in Alerts.` line.
/// The two sentences are two paragraphs with `space.3` between them (R-31-13-23, decided
/// 2026-09-03 by the product owner: one dense block did not read).
class _AlertsGroup extends StatelessWidget {
  const _AlertsGroup({this.deliveryWord, this.onOpenAlertsSettings});

  final String? deliveryWord;
  final VoidCallback? onOpenAlertsSettings;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final bool needsFix = deliveryWord == 'silenced' || deliveryWord == 'off';
    final TextStyle paragraph = AppType.caption.copyWith(
      color: color.fgSecondary,
    );
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'ALERTS',
                  style: AppType.micro.copyWith(color: color.fgSecondary),
                ),
              ),
              Text(
                (deliveryWord ?? '-').toUpperCase(),
                style: AppType.micro.copyWith(color: color.fgSecondary),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.space2),
          Text(
            'Alerts arrive while the app is running. If the phone closes the app, the alert '
            'is waiting in the app the next time you open it.',
            style: paragraph,
          ),
          const SizedBox(height: AppSpace.space3),
          Text(
            'Alerts come from the computer you are connected to. If an agent finishes on '
            'another computer, you see it when you connect to that computer.',
            style: paragraph,
          ),
          if (needsFix) ...<Widget>[
            const SizedBox(height: AppSpace.space3),
            // R-32-561: a strip that names a destination is tappable across its whole width
            // and routes there; the hue lives in the treatment's icon, not in a bar.
            AppStrip(
              onTapDestination: onOpenAlertsSettings,
              child: Treatment.warning(
                label: 'Alerts are $deliveryWord. Fix this in Alerts.',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// R-31-13-18, R-30-962, R-03-044: the one place that holds the `Disconnect`/switch/`Forget`/
/// `Remove` distinction. Carries the mockup's own table as four two-line rows (R-31-13-23,
/// decided 2026-09-03 by the product owner): the action word alone on the title line in
/// `type.body`, the `DESTRUCTIVE`/`NOT DESTRUCTIVE` tag trailing it in `type.micro` and never
/// wrapping, then where the action lives and what it does in one `type.caption` line under it.
/// This codebase draws no `DataTable` anywhere else, so neither does this.
class _DistinctionTable extends StatelessWidget {
  const _DistinctionTable();

  static const List<(String, String, bool)> _rows = <(String, String, bool)>[
    (
      'Disconnect',
      'This screen. Closes this phone\u2019s link to the relay, and keeps the pairing and '
          'the Device key.',
      false,
    ),
    (
      'Switching computer',
      'The host list, a plain tap on a saved row. Disconnects the connected computer, then '
          'connects the tapped one, and keeps every pairing and every Device key.',
      false,
    ),
    (
      'Forget',
      'The host list, from a touch and hold on a row. Drops the paired computer on this phone, '
          'and destroys the Device key for it.',
      true,
    ),
    ('Remove', 'The devices screen. Revokes this phone on the computer.', true),
  ];

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpace.space6,
        bottom: AppSpace.space4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'DISCONNECT, FORGET, REMOVE AND THE SWITCH',
            style: AppType.micro.copyWith(color: color.fgSecondary),
          ),
          const SizedBox(height: AppSpace.space2),
          for (final (
                int index,
                (String action, String detail, bool destructive),
              )
              in _rows.indexed) ...<Widget>[
            if (index > 0) const SizedBox(height: AppSpace.space4),
            Semantics(
              label:
                  '$action, ${destructive ? 'destructive' : 'not destructive'}, $detail',
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          action,
                          style: AppType.body.copyWith(color: color.fgPrimary),
                        ),
                      ),
                      const SizedBox(width: AppSpace.space3),
                      Text(
                        destructive ? 'DESTRUCTIVE' : 'NOT DESTRUCTIVE',
                        maxLines: 1,
                        style: AppType.micro.copyWith(color: color.fgSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.space1),
                  Text(
                    detail,
                    style: AppType.caption.copyWith(color: color.fgSecondary),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
