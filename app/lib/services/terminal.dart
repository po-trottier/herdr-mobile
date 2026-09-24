/// The Device's terminal-pane service (Phase 16, `WP-16-a`): the `watch_pane`/`unwatch_pane`
/// lifecycle (R-11-048, R-11-050), the persistent `xterm2` `Terminal` instance strategy B
/// commits to (`docs/21-terminal-rendering.md` R-21-001), the clear-and-home reset before
/// every feed (R-21-002), the revision gate (R-21-004, R-11-052), the pane filter (R-21-004a),
/// frames fed on arrival (R-21-021), the R-21-041 selection/scroll freeze,
/// `scroll_request`/`scroll_response` (R-11-053), the local `terminal.resize()` call from
/// `watch_ack`/`pane_frame` geometry (R-21-009, R-10-025), and the `render_ms` measurement
/// with its 240 ms fallback (R-21-022).
///
/// R-03-130: only Host frames write to the grid. Native composer edits send input
/// without a local grid echo.
///
/// R-21-036: this service never sends `host_action` or changes Host pane geometry.
/// Its watch, scroll and input requests carry no pane dimensions. The local
/// [xterm] resize only applies geometry that the Host already reported.
///
/// R-21-021: the bridge applies the normal 120 ms debounce before it sends a frame.
/// The Device feeds an unfrozen frame on arrival, without a second coalescing window.
/// R-21-022: only five consecutive `render_ms` samples over 200 ms enable the Device's
/// 240 ms fallback throttle. The protocol has no bridge-throttle request, so this local
/// fallback protects a slow Device without pretending to change the bridge's timer.
/// R-21-004, R-21-041: keep one pending frame during a feed or freeze. A newer frame
/// replaces it; resume after the current feed yields, or as soon as the freeze clears.
///
/// This file owns no widget and paints nothing (R-90-024). `terminal_view_widget.dart`
/// (`WP-16-b`) binds [xterm] straight into `xterm2`'s `TerminalView` and reads
/// [TerminalService.frameState] for layout/backoff diagnostics; `status_strip.dart` and
/// `pane_actions_sheet.dart` (`WP-16-c`) read [TerminalService.frameState] for the grid size,
/// the revision, the Host-reported scroll state and the `paused` status word.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:logging/logging.dart' show Logger;
import 'package:xterm2/xterm.dart' show Terminal;

import '../core/result/result.dart' show Err, Ok, Result;
import '../models/codes.dart' show ErrorCode;
import '../models/message.dart';
import '../models/messages/pane_frame.dart';
import '../models/messages/ping.dart';
import '../models/messages/scroll_offsets.dart';
import '../models/messages/scroll_request.dart';
import '../models/messages/scroll_response.dart';
import '../models/messages/send_input.dart';
import '../models/messages/theme_palette.dart';
import '../models/messages/watch_ack.dart';
import '../models/sgr_counter.dart' show SgrCounter;

/// R-21-021, R-10-029: the bridge's normal debounce window, reported for diagnostics.
/// The Device does not apply this delay.
const Duration terminalDefaultCoalesceWindow = Duration(milliseconds: 120);

/// R-21-022: the Device throttle enabled only after consecutive slow frames trip the fallback.
const Duration terminalFallbackCoalesceWindow = Duration(milliseconds: 240);

/// R-21-022: a `render_ms` above this, for [terminalRenderSlowTripCount] consecutive applied
/// frames, trips the fallback.
const int terminalRenderSlowThresholdMs = 200;

/// R-21-022: consecutive slow frames required to trip the fallback.
const int terminalRenderSlowTripCount = 5;

/// R-21-022: how many recent `render_ms` samples [TerminalFrameState.lastRenderMs] keeps for
/// the diagnostics screen.
const int terminalRenderMsHistoryLength = 5;

/// Bounds how long [TerminalService.attach] and [TerminalService.requestScrollback] wait for
/// their reply before giving up, matching `docs/10-herdr-integration.md` R-10-004's 5000 ms
/// shape one layer up the stack.
const Duration terminalReplyTimeout = Duration(seconds: 5);

/// Sends one application [Message], optionally correlated by [corr]. Matches
/// `RelayConnection.send`'s exact signature (`relay.dart`, `WP-14-a`), so a caller passes
/// `connection.send` directly. [RelayConnection] is a `final class`: Dart forbids
/// `implements`/`extends` on it from outside `relay.dart`'s own library, so it cannot be
/// `mocktail`-mocked from a test file. `relay.dart` itself already established this same
/// function-typedef seam pattern (`ChannelFactory`, `NoiseHandshaker`) for the identical
/// reason; this file follows it instead of depending on the concrete class.
typedef TerminalMessageSender = void Function(Message message, {String? corr});

/// Watches or unwatches one pane, matching `RelayConnection.watchPane` /
/// `RelayConnection.unwatchPane`'s exact signature. [TerminalService] calls these, never a
/// raw [TerminalMessageSender], so `RelayConnection`'s own watched-pane bookkeeping stays
/// correct and an automatic reconnect still resumes the right pane (R-11-084, R-11-200).
typedef TerminalPaneWatcher = void Function(String paneId, {String? corr});

/// `WP-16-b`/`WP-16-c` read this word. The grid MUST NOT dim while [paused]: dimming means a
/// lost or blocked link, and a freeze is neither (R-21-041, R-31-08-05). The freeze, and any
/// selection live when it started, survive a lost link untouched — this file never clears
/// [paused] on a connection-state change, only on [TerminalService.setSelectionLive] and
/// [TerminalService.setScrollOffset] both reporting clear.
enum TerminalPaneStatus {
  /// Every applied `pane_frame` feeds [TerminalService.xterm] and repaints at once.
  live,

  /// A selection is live or the Device's own scroll offset is above zero (R-21-041,
  /// R-31-08-18). At most one newer frame is held; a newer arrival replaces it rather than
  /// queuing, and it is fed through the normal clear-and-feed cycle the instant both
  /// conditions clear.
  paused,
}

/// A snapshot of [TerminalService]'s pipeline, published on [TerminalService.frameState]
/// after every applied frame, attach, detach, resize or freeze transition.
final class TerminalFrameState {
  const TerminalFrameState({
    required this.paneId,
    required this.revision,
    required this.columns,
    required this.rows,
    required this.scroll,
    required this.status,
    required this.debounceWindow,
    required this.lastRenderMs,
    required this.renderSlowTripCount,
    required this.longestLineDrawn,
    required this.unknownSgrCount,
  });

  /// `null` before the first successful [TerminalService.attach], and again after
  /// [TerminalService.detach].
  final String? paneId;

  /// From the `watch_ack`/`pane_frame` relay message, never from a `pane.read` result, which
  /// is always `0` (R-21-004, R-11-052).
  final int revision;

  /// From `watch_ack`/`pane_frame`'s `width`, i.e. the Host's `rect.width` (R-21-009).
  final int columns;

  /// From `watch_ack`/`pane_frame`'s `viewport_rows` (R-21-009).
  final int rows;

  /// The Host-reported scroll state from the last `watch_ack` (R-11-049): whether a
  /// scrollback affordance has anything to show (R-10-026). Distinct from the Device's own
  /// pan/scroll position, which [TerminalService.setScrollOffset] feeds into the R-21-041
  /// freeze and which `terminal_view_widget.dart` (`WP-16-b`) owns the display of.
  final ScrollOffsets scroll;

  final TerminalPaneStatus status;

  /// R-21-021, R-21-022: the reported bridge window during normal operation.
  /// After a slow-render trip, the Device applies [terminalFallbackCoalesceWindow] locally.
  final Duration debounceWindow;

  /// The most recent applied frames' `render_ms`, oldest first, capped at
  /// [terminalRenderMsHistoryLength] (R-21-022).
  final List<int> lastRenderMs;

  /// How many times the R-21-022 fallback has tripped this session.
  final int renderSlowTripCount;

  /// The longest applied frame's `text`, ANSI-stripped, in cells — `0` before the first
  /// applied frame or right after [TerminalService.attach]/[TerminalService.detach]
  /// (R-31-13-09, R-31-13-10). `docs/31-mockups/13-connection.md`'s diagnostics screen
  /// (`WP-18-d`) shows this against `columns` and warns once the gap passes 8 cells.
  final int longestLineDrawn;

  /// [SgrCounter.unknownCount] since the last [TerminalService.attach], scanning every
  /// applied frame's raw `text` (R-01-008, R-31-08-12, R-31-13-08). `0` is the expected
  /// steady state; `docs/31-mockups/13-connection.md`'s diagnostics screen (`WP-18-d`) MUST
  /// show this row even at `0`, never hide it.
  final int unknownSgrCount;

  /// Copies every field except [paneId], which only [TerminalService.attach] and
  /// [TerminalService.detach] change — both build a fresh [TerminalFrameState] directly
  /// instead, since a nullable field has no unambiguous "leave unset" sentinel through
  /// `copyWith`.
  TerminalFrameState copyWith({
    int? revision,
    int? columns,
    int? rows,
    ScrollOffsets? scroll,
    TerminalPaneStatus? status,
    Duration? debounceWindow,
    List<int>? lastRenderMs,
    int? renderSlowTripCount,
    int? longestLineDrawn,
    int? unknownSgrCount,
  }) => TerminalFrameState(
    paneId: paneId,
    revision: revision ?? this.revision,
    columns: columns ?? this.columns,
    rows: rows ?? this.rows,
    scroll: scroll ?? this.scroll,
    status: status ?? this.status,
    debounceWindow: debounceWindow ?? this.debounceWindow,
    lastRenderMs: lastRenderMs ?? this.lastRenderMs,
    renderSlowTripCount: renderSlowTripCount ?? this.renderSlowTripCount,
    longestLineDrawn: longestLineDrawn ?? this.longestLineDrawn,
    unknownSgrCount: unknownSgrCount ?? this.unknownSgrCount,
  );
}

/// Set as an [Err.cause] when [TerminalService.attach] fails: the Host answered `error`
/// instead of `watch_ack` (most commonly `pane_not_found`), or no reply arrived within
/// [terminalReplyTimeout].
final class TerminalAttachException implements Exception {
  const TerminalAttachException(this.message, {this.errorCode});
  final String message;
  final ErrorCode? errorCode;

  @override
  String toString() => 'TerminalAttachException: $message';
}

/// Set as an [Err.cause] when [TerminalService.requestScrollback] fails.
final class TerminalScrollbackException implements Exception {
  const TerminalScrollbackException(
    this.message, {
    this.errorCode,
    this.cancelled = false,
  });
  final String message;
  final ErrorCode? errorCode;
  final bool cancelled;

  @override
  String toString() => 'TerminalScrollbackException: $message';
}

/// The Device's terminal-pane pipeline for one watched pane at a time (R-10-033). See this
/// file's own header comment for the full contract.
final class TerminalService {
  TerminalService({
    required Stream<Message> messages,
    required this._send,
    required TerminalPaneWatcher watchPane,
    required TerminalPaneWatcher unwatchPane,
    Terminal? terminal,
    ThemePalette? initialHostTheme,
    Duration coalesceWindow = terminalDefaultCoalesceWindow,
    Duration fallbackCoalesceWindow = terminalFallbackCoalesceWindow,
    int renderSlowThresholdMs = terminalRenderSlowThresholdMs,
    int renderSlowTripCount = terminalRenderSlowTripCount,
    Duration replyTimeout = terminalReplyTimeout,
    Logger? logger,
    DateTime Function() now = DateTime.now,
  }) : // ignore: prefer_initializing_formals
       _watchPaneFn = watchPane,
       _unwatchPaneFn = unwatchPane,
       hostTheme = ValueNotifier(initialHostTheme),
       // R-21-001, R-21-005, R-21-002: `maxLines: 0` disables scrollback entirely, so the
       // clear-and-home reset before every feed is a trivial grid reset, never a growing
       // buffer (WP-2's `reset_no_scrollback_test.dart` proves this at the xterm2 layer).
       xterm = terminal ?? Terminal(maxLines: 0),
       // ignore: prefer_initializing_formals
       _fallbackCoalesceWindow = fallbackCoalesceWindow,
       // ignore: prefer_initializing_formals
       _renderSlowThresholdMs = renderSlowThresholdMs,
       // ignore: prefer_initializing_formals
       _renderSlowTripCount = renderSlowTripCount,
       // ignore: prefer_initializing_formals
       _replyTimeout = replyTimeout,
       _log = logger ?? Logger('TerminalService'),
       // ignore: prefer_initializing_formals
       _now = now,
       _state = TerminalFrameState(
         paneId: null,
         revision: 0,
         columns: 0,
         rows: 0,
         scroll: const ScrollOffsets(
           offsetFromBottom: 0,
           maxOffsetFromBottom: 0,
         ),
         status: TerminalPaneStatus.live,
         debounceWindow: coalesceWindow,
         lastRenderMs: const [],
         renderSlowTripCount: 0,
         longestLineDrawn: 0,
         unknownSgrCount: 0,
       ) {
    _subscription = messages.listen(_onMessage);
  }

  /// The persistent `xterm2` instance (R-21-001, R-21-005). `terminal_view_widget.dart`
  /// (`WP-16-b`) binds this straight into `TerminalView(terminal: xterm, autoResize: false,
  /// textScaler: TextScaler.noScaling, ...)` (R-21-038); this file owns every [Terminal.write]
  /// and [Terminal.resize] call on it, and `WP-16-b` MUST NOT call either itself.
  final Terminal xterm;

  final TerminalMessageSender _send;
  final TerminalPaneWatcher _watchPaneFn;
  final TerminalPaneWatcher _unwatchPaneFn;
  final Duration _fallbackCoalesceWindow;
  final int _renderSlowThresholdMs;
  final int _renderSlowTripCount;
  final Duration _replyTimeout;
  final Logger _log;
  final DateTime Function() _now;
  // R-01-008, R-31-08-12, R-31-13-08: scans every applied frame's raw text for SGR
  // parameters outside the measured vocabulary. Reset on every [attach]/[detach] so the
  // count never aggregates across panes (R-31-13-09).
  final SgrCounter _sgrCounter = SgrCounter();

  /// R-03-131: the latest Host palette, including updates after this pane opens.
  final ValueNotifier<ThemePalette?> hostTheme;
  final ValueNotifier<Duration?> latestRtt = ValueNotifier(null);
  final _pendingReplies =
      <String, ({DateTime? sentAt, String? paneId, Timer timer})>{};
  final _submits = <String, Completer<bool>>{};
  Timer? _rttProbeTimer;
  bool _disposed = false;
  int _connectionGeneration = 0;
  late final StreamSubscription<Message> _subscription;

  TerminalFrameState _state;
  final StreamController<TerminalFrameState> _stateController =
      StreamController<TerminalFrameState>.broadcast();

  // R-21-041, R-21-021 step 3: at most one unapplied frame is ever held; a newer arrival
  // always replaces it rather than queuing (R-10-018 — every frame is a full repaint, so
  // only the newest is ever worth painting).
  PaneFrame? _pendingFrame;
  PaneFrame? _lastLiveFrame;
  bool _readingScrollback = false;
  bool _showingScrollback = false;
  bool _scrollbackTruncated = false;
  int _scrollbackRequestedLines = 0;
  int _scrollbackRows = 0;
  int _scrollbackGeneration = 0;
  int _scrollEpoch = 0;
  Future<Result<ScrollResponse>>? _scrollFuture;

  /// A fetched window replaces the live grid in memory until the reader returns.
  bool get showingScrollback => _showingScrollback;
  bool get scrollbackTruncated => _scrollbackTruncated;
  int get scrollbackGeneration => _scrollbackGeneration;

  /// The Host exposes recent windows, not offsets. Expand by 100 rows per gesture
  /// without fetching the wire maximum on the first read (R-21-045).
  int get nextScrollbackLines =>
      ((_showingScrollback ? _scrollbackRequestedLines : _state.rows) + 100)
          .clamp(1, 1000);
  bool get canLoadMoreScrollback =>
      !_showingScrollback ||
      (_scrollbackTruncated &&
          _scrollbackRequestedLines < 1000 &&
          _scrollbackRows >= _scrollbackRequestedLines);
  DateTime? _pendingFrameReceivedAt;
  Timer? _coalesceTimer;
  bool _flushingFrame = false;
  bool _selectionLive = false;
  int _scrollOffset = 0;
  int _consecutiveSlowFrames = 0;
  // R-21-004, R-02-012: the revision of the last frame actually WRITTEN to [xterm] —
  // distinct from `_state.revision`, which [_applyWatchAck] sets from `watch_ack` before
  // any frame has ever been painted. `null` means "nothing painted for this pane yet",
  // which is the fix for a real production bug (see `_onPaneFrame`'s own comment): the
  // production `Bridge::watch_pane` (`crates/herdr-relay/src/watch/requests.rs`) always
  // builds `watch_ack` and the pane's first `pane_frame` from the very same snapshot read,
  // so that first frame's `revision` always equals `watch_ack.revision`. Gating "paint" on
  // `_state.revision` (already seeded from that same `watch_ack`) silently discarded that
  // first frame every time, leaving the grid permanently blank until an unrelated later
  // revision change happened to arrive. `docs/21-terminal-rendering.md` R-21-004/R-02-012's
  // "skip when the revision does not move" is a rule about skipping a re-read against a
  // revision *already painted*, never against a revision merely reported by `watch_ack`.
  int? _lastAppliedRevision;

  Completer<Result<WatchAck>>? _attachCompleter;
  String? _attachingPaneId;
  Completer<Result<ScrollResponse>>? _scrollCompleter;

  /// Published after every applied frame, attach, detach, resize or freeze transition.
  Stream<TerminalFrameState> get frameState => _stateController.stream;

  /// The latest value [frameState] published; same object [frameState]'s last event carried.
  TerminalFrameState get state => _state;

  /// Sends `watch_pane` for [paneId] (R-11-048) and awaits the matching `watch_ack`
  /// (R-11-049), resizing [xterm] from its `width`/`viewport_rows` at once (R-21-009,
  /// R-10-025). Resets every per-pane pipeline field (revision, pending frame, freeze) for
  /// the new pane. A caller does not need to [detach] first when switching panes: the bridge
  /// unwatches the previous pane automatically (R-11-072, R-11-048).
  ///
  /// ponytail: a second `attach()` call before the first resolves abandons the first
  /// completer's `Future` unresolved rather than cancelling it; add explicit cancellation if
  /// a caller ever needs to attach twice in flight.
  Future<Result<void>> attach(String paneId) async {
    _coalesceTimer?.cancel();
    _coalesceTimer = null;
    _pendingFrame = null;
    _pendingFrameReceivedAt = null;
    _consecutiveSlowFrames = 0;
    _lastAppliedRevision = null;
    _lastLiveFrame = null;
    _cancelScrollback();
    _scrollOffset = 0;
    _selectionLive = false;
    _sgrCounter.reset();
    _attachingPaneId = paneId;
    final completer = Completer<Result<WatchAck>>();
    _attachCompleter = completer;
    _watchPaneFn(paneId);

    final Result<WatchAck> result = await completer.future.timeout(
      _replyTimeout,
      onTimeout: () => Err(
        'attach to pane $paneId',
        cause: const TerminalAttachException('no watch_ack arrived in time'),
      ),
    );
    if (identical(_attachCompleter, completer)) {
      _attachCompleter = null;
      _attachingPaneId = null;
    }
    if (result case Err(:final message, :final cause)) {
      return Err(message, cause: cause);
    }
    _applyWatchAck((result as Ok<WatchAck>).value);
    return const Ok(null);
  }

  void _applyWatchAck(WatchAck ack) {
    xterm.resize(ack.width, ack.viewportRows);
    _publish(
      TerminalFrameState(
        paneId: ack.paneId,
        revision: ack.revision,
        columns: ack.width,
        rows: ack.viewportRows,
        scroll: ack.scroll,
        status: TerminalPaneStatus.live,
        debounceWindow: _state.debounceWindow,
        lastRenderMs: const [],
        renderSlowTripCount: _state.renderSlowTripCount,
        longestLineDrawn: 0,
        unknownSgrCount: 0,
      ),
    );
  }

  /// Sends `unwatch_pane` (R-11-050) for the currently attached pane, if any, and drops
  /// every per-pane pipeline field.
  void detach() {
    final paneId = _state.paneId;
    _coalesceTimer?.cancel();
    _coalesceTimer = null;
    _pendingFrame = null;
    _pendingFrameReceivedAt = null;
    _consecutiveSlowFrames = 0;
    _lastAppliedRevision = null;
    _lastLiveFrame = null;
    _cancelScrollback();
    _scrollOffset = 0;
    _selectionLive = false;
    _sgrCounter.reset();
    if (paneId != null) {
      _unwatchPaneFn(paneId);
    }
    _publish(
      TerminalFrameState(
        paneId: null,
        revision: 0,
        columns: 0,
        rows: 0,
        scroll: const ScrollOffsets(
          offsetFromBottom: 0,
          maxOffsetFromBottom: 0,
        ),
        status: TerminalPaneStatus.live,
        debounceWindow: _state.debounceWindow,
        lastRenderMs: const [],
        renderSlowTripCount: _state.renderSlowTripCount,
        longestLineDrawn: 0,
        unknownSgrCount: 0,
      ),
    );
  }

  /// `terminal_view_widget.dart` (`WP-16-b`) calls this whenever its own text-selection
  /// state changes, feeding the first half of the R-21-041 freeze condition.
  void setSelectionLive({required bool live}) {
    if (_selectionLive == live) return;
    _selectionLive = live;
    _onFreezeConditionChanged();
  }

  /// `terminal_view_widget.dart` (`WP-16-b`) calls this whenever the Device's own scroll
  /// offset changes, feeding the second half of the R-21-041 freeze condition
  /// (`offsetAboveBottom` rows above the live bottom; `0` means at the live bottom,
  /// R-31-08-18).
  void setScrollOffset(int offsetAboveBottom) {
    final wasLive = _scrollOffset <= 0;
    final isLive = offsetAboveBottom <= 0;
    _scrollOffset = offsetAboveBottom;
    if (isLive && _readingScrollback) {
      _readingScrollback = false;
      _scrollEpoch++;
      _onFreezeConditionChanged();
      return;
    }
    if (wasLive == isLive) return;
    _onFreezeConditionChanged();
  }

  bool get _frozen => _selectionLive || _scrollOffset > 0 || _readingScrollback;

  void _onFreezeConditionChanged() {
    if (_frozen) {
      if (_state.status != TerminalPaneStatus.paused) {
        _publish(_state.copyWith(status: TerminalPaneStatus.paused));
      }
      return;
    }
    // R-21-041: both conditions just cleared. Feed any held frame at once, through the
    // normal clear-and-feed cycle — never queued, and never waiting for a fresh timer tick.
    _coalesceTimer?.cancel();
    _coalesceTimer = null;
    if (_showingScrollback) {
      _showingScrollback = false;
      _scrollbackTruncated = false;
      // The Host may have sent no newer frame while history was open.
      _pendingFrame ??= _lastLiveFrame;
      _pendingFrameReceivedAt ??= _now();
    }
    if (_pendingFrame != null) {
      _flushPendingFrame();
    } else {
      _publish(_state.copyWith(status: TerminalPaneStatus.live));
    }
  }

  /// Requests scrollback above the visible viewport (R-11-053, `docs/31-mockups/08-terminal.md`
  /// callout 10), capping [lines] to the wire's 1-1000 range (R-10-019).
  Future<Result<ScrollResponse>> requestScrollback({required int lines}) {
    return _scrollFuture ??= _fetchScrollback(lines: lines).whenComplete(() {
      _scrollFuture = null;
    });
  }

  Future<Result<ScrollResponse>> _fetchScrollback({required int lines}) async {
    final paneId = _state.paneId;
    if (paneId == null) {
      return const Err(
        'request scrollback',
        cause: TerminalScrollbackException('no pane is attached'),
      );
    }
    final cappedLines = lines.clamp(1, 1000);
    final epoch = ++_scrollEpoch;
    _readingScrollback = true;
    _onFreezeConditionChanged();
    final completer = Completer<Result<ScrollResponse>>();
    _scrollCompleter = completer;
    _send(
      Message.scrollRequest(ScrollRequest(paneId: paneId, lines: cappedLines)),
    );
    final result = await completer.future.timeout(
      _replyTimeout,
      onTimeout: () => Err(
        'request scrollback for $paneId',
        cause: const TerminalScrollbackException(
          'no scroll_response arrived in time',
        ),
      ),
    );
    if (identical(_scrollCompleter, completer)) {
      _scrollCompleter = null;
    }
    if (epoch != _scrollEpoch || paneId != _state.paneId) {
      return const Err(
        'scrollback request cancelled',
        cause: TerminalScrollbackException(
          'reader left history',
          cancelled: true,
        ),
      );
    }
    if (result case Ok(:final value)) {
      final rows = value.text.split('\n').length.clamp(1, 1001);
      if (_selectionLive) {
        if (!_prependSelectedHistory(value.text, rows)) {
          _showingScrollback = true;
          _scrollbackTruncated = true;
          _scrollbackRequestedLines = 1000;
          _scrollbackGeneration++;
          _publish(_state.copyWith(status: TerminalPaneStatus.paused));
          return result;
        }
      } else {
        // An unselected reply replaces the temporary grid, without local scrollback.
        xterm.resize(_state.columns, rows);
        xterm.write('\x1b[2J\x1b[H${value.text}');
      }
      _showingScrollback = true;
      _scrollbackTruncated = value.truncated;
      _scrollbackRequestedLines = cappedLines;
      _scrollbackRows = rows;
      _scrollbackGeneration++;
      _publish(_state.copyWith(status: TerminalPaneStatus.paused));
    } else {
      _readingScrollback = false;
      _onFreezeConditionChanged();
    }
    return result;
  }

  /// Keep selected lines and their anchors. Only add proven older rows.
  bool _prependSelectedHistory(String text, int rows) {
    final history = Terminal(maxLines: 0)..resize(_state.columns, rows);
    try {
      history.write(text);
      final current = xterm.buffer.lines;
      var count = current.length;
      while (count > 0 && current[count - 1].getText().trimRight().isEmpty) {
        count--;
      }
      if (count == 0) return false;
      final oldRows = List.generate(count, (i) => current[i].getText());
      final fetched = history.buffer.lines;
      for (var start = fetched.length - count; start >= 0; start--) {
        var matched = 0;
        while (matched < count &&
            fetched[start + matched].getText() == oldRows[matched]) {
          matched++;
        }
        if (matched != count) continue;
        if (start == 0) return true;
        xterm.resize(_state.columns, xterm.viewHeight + start);
        // Insert lines through xterm so its existing cell anchors move with the text.
        xterm.write('\x1b[H\x1b[${start}L');
        for (var row = 0; row < start; row++) {
          current[row].copyFrom(fetched[row], 0, 0, _state.columns);
          current[row].isWrapped = fetched[row].isWrapped;
        }
        xterm.write('');
        return true;
      }
      // The wire supplies recent windows, not absolute row offsets (R-10-027).
      return false;
    } finally {
      history.dispose();
    }
  }

  void _cancelScrollback() {
    _scrollEpoch++;
    _readingScrollback = false;
    _showingScrollback = false;
    _scrollbackTruncated = false;
    final pending = _scrollCompleter;
    _scrollCompleter = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete(const Err('scrollback request cancelled'));
    }
  }

  void _onMessage(Message message) {
    switch (message) {
      case MessageHostInfo(:final payload):
        hostTheme.value = payload.theme;
      case MessageHostTheme(:final payload):
        hostTheme.value = payload.theme;
      case MessageWatchAck(:final payload):
        final completer = _attachCompleter;
        if (completer != null &&
            !completer.isCompleted &&
            payload.paneId == _attachingPaneId) {
          completer.complete(Ok(payload));
        }
      case MessagePaneFrame(:final payload):
        _onPaneFrame(payload);
      case MessageScrollResponse(:final payload):
        final completer = _scrollCompleter;
        if (completer != null &&
            !completer.isCompleted &&
            payload.paneId == _state.paneId) {
          completer.complete(Ok(payload));
        }
      case MessageSendInputAck(:final payload, :final corr):
        if (corr != null && _pendingReplies[corr]?.paneId == payload.paneId) {
          if (payload.accepted && (payload.queued ?? false)) {
            final pending = _pendingReplies[corr]!;
            if (pending.sentAt != null) {
              latestRtt.value = _now().difference(pending.sentAt!);
            }
            if (_submits.containsKey(corr)) {
              pending.timer.cancel();
              _pendingReplies[corr] = (
                sentAt: null,
                paneId: pending.paneId,
                timer: pending.timer,
              );
              _queuedCorr = corr;
              composerQueued.value = true;
            }
          } else {
            _finishReply(corr, payload.accepted, measure: true);
          }
        }
      case MessagePong(:final corr):
        if (corr != null &&
            _pendingReplies.containsKey(corr) &&
            _pendingReplies[corr]!.paneId == null) {
          _finishReply(corr, true, measure: true);
        }
      case MessageError(:final payload, :final corr):
        if (corr != null && _pendingReplies.containsKey(corr)) {
          _finishReply(corr, false);
          return;
        }
        final attachCompleter = _attachCompleter;
        if (attachCompleter != null && !attachCompleter.isCompleted) {
          attachCompleter.complete(
            Err(
              'attach to pane $_attachingPaneId',
              cause: TerminalAttachException(
                payload.message,
                errorCode: payload.code,
              ),
            ),
          );
        }
        final scrollCompleter = _scrollCompleter;
        if (scrollCompleter != null && !scrollCompleter.isCompleted) {
          scrollCompleter.complete(
            Err(
              'request scrollback',
              cause: TerminalScrollbackException(
                payload.message,
                errorCode: payload.code,
              ),
            ),
          );
        }
      default:
        break;
    }
  }

  void _onPaneFrame(PaneFrame frame) {
    // R-21-004a, R-01-007: filter to the pane being viewed. A race right after switching
    // panes could still deliver one stale frame before the bridge's own R-02-013 filter
    // catches up; this is the Device-side backstop.
    if (frame.paneId != _state.paneId) return;
    // R-31-08-03, R-02-012: never paint a frame *older* than the last painted frame or any
    // not-yet-applied held frame. A frame with the *same* revision is painted: Herdr freezes
    // `revision` on an agent pane (`screen_detection_skipped`, R-02 measurement of
    // 2026-09-03), so the Host polls and sends a frame only when the text changed (R-10-070);
    // every such frame carries the frozen revision and new text. `_lastAppliedRevision` — not
    // `_state.revision` — is the bootstrap: see that field's own doc comment for the real
    // production bug this distinction fixes (the pane's first frame always shares its
    // revision with `watch_ack`, and MUST still be painted).
    final currentBest = _pendingFrame?.revision ?? _lastAppliedRevision;
    if (currentBest != null && frame.revision < currentBest) return;

    // R-21-004, R-21-021 step 3: a newer revision supersedes and cancels any pending frame;
    // frames are never queued, only the newest is ever worth painting (R-10-018).
    _pendingFrame = frame;
    _pendingFrameReceivedAt = _now();

    if (_frozen) {
      // R-21-041: hold one frame without feeding the emulator.
      // `_onFreezeConditionChanged` flushes it when both conditions clear.
      if (_state.status != TerminalPaneStatus.paused) {
        _publish(_state.copyWith(status: TerminalPaneStatus.paused));
      }
      return;
    }

    // R-21-021: feed on arrival, unless a feed or fallback throttle already holds a frame.
    if (_flushingFrame || _coalesceTimer != null) return;
    if (_state.renderSlowTripCount > 0) {
      // R-21-022: only a measured slow-render trip enables the Device's 240 ms throttle.
      _coalesceTimer = Timer(_state.debounceWindow, _flushPendingFrame);
    } else {
      _flushPendingFrame();
    }
  }

  void _flushPendingFrame() {
    _coalesceTimer = null;
    final frame = _pendingFrame;
    final receivedAt = _pendingFrameReceivedAt;
    if (frame == null || receivedAt == null) return;
    // R-21-004, R-21-041: never interrupt a feed or write while a freeze holds.
    if (_flushingFrame || _frozen) return;
    _flushingFrame = true;
    try {
      _pendingFrame = null;
      _pendingFrameReceivedAt = null;
      _lastAppliedRevision = frame.revision;
      _lastLiveFrame = frame;

      if (frame.width != xterm.viewWidth ||
          frame.viewportRows != xterm.viewHeight) {
        // R-21-009, R-10-025: resize on every Host-reported layout change, never on the
        // widget's own measured size.
        xterm.resize(frame.width, frame.viewportRows);
        // Shrinking a fetched history grid moves rows into xterm's buffer.
        // They are not live scrollback and must not survive the restoration.
        xterm.buffer.clearScrollback();
      }
      // R-21-001, R-21-002: clear and home before every feed, then replace the whole grid —
      // never append, never patch (R-10-018, R-31-08-11). One `write`, one parse, one listener
      // notification per frame; the 2026-09-08 flicker was the widget's follow anchor, not
      // this feed (R-21-021).
      xterm.write('\x1b[2J\x1b[H${frame.text}');
      xterm.buffer.clearScrollback();
      // R-01-008, R-31-08-12, R-31-13-08/09/10: scan and measure this applied frame's raw
      // text, once, alongside the feed above — never in place of it (`sgr_counter.dart`'s own
      // header comment).
      _sgrCounter.scan(frame.text);
      final longestLine = _longestLineLength(frame.text);
      final renderMs = _now().difference(receivedAt).inMilliseconds;
      final history = [..._state.lastRenderMs, renderMs];
      if (history.length > terminalRenderMsHistoryLength) {
        history.removeAt(0);
      }
      var debounceWindow = _state.debounceWindow;
      var tripCount = _state.renderSlowTripCount;
      if (renderMs > _renderSlowThresholdMs) {
        _consecutiveSlowFrames++;
        if (_consecutiveSlowFrames >= _renderSlowTripCount &&
            debounceWindow != _fallbackCoalesceWindow) {
          // R-21-022: raise the debounce window, log the warning, and count the trip for the
          // diagnostics screen.
          debounceWindow = _fallbackCoalesceWindow;
          tripCount++;
          _consecutiveSlowFrames = 0;
          _log.warning(
            'render_ms exceeded ${_renderSlowThresholdMs}ms for $_renderSlowTripCount '
            'consecutive frames; raising the coalescing window to '
            '${debounceWindow.inMilliseconds}ms (R-21-022)',
          );
        }
      } else {
        _consecutiveSlowFrames = 0;
      }

      _publish(
        _state.copyWith(
          revision: frame.revision,
          columns: frame.width,
          rows: frame.viewportRows,
          status: TerminalPaneStatus.live,
          debounceWindow: debounceWindow,
          lastRenderMs: history,
          renderSlowTripCount: tripCount,
          longestLineDrawn: longestLine,
          unknownSgrCount: _sgrCounter.unknownCount,
        ),
      );
    } finally {
      _flushingFrame = false;
      if (_pendingFrame != null && !_frozen) {
        // R-21-021, R-21-022: yield after one feed; apply only the newest pending frame.
        // A zero-delay event prevents recursion without a normal coalescing window.
        _coalesceTimer ??= Timer(
          _state.renderSlowTripCount > 0
              ? _state.debounceWindow
              : Duration.zero,
          _flushPendingFrame,
        );
      }
    }
  }

  /// Sends a correlated input or probe and measures its reply time.
  void send(Message message, {String? corr}) {
    if (_disposed) return;
    if (message is! MessageSendInput && message is! MessagePing) {
      _send(message, corr: corr);
      return;
    }
    corr ??= _freshCorr();
    final id = corr;
    final paneId = message is MessageSendInput ? message.payload.paneId : null;
    final timer = Timer(_replyTimeout, () => _finishReply(id, false));
    _pendingReplies[id] = (sentAt: _now(), paneId: paneId, timer: timer);
    try {
      _send(message, corr: id);
    } on Object {
      _finishReply(id, false);
      rethrow;
    }
  }

  static int _corrSequence = 0;
  String _freshCorr() =>
      'terminal-${_now().microsecondsSinceEpoch}-${_corrSequence++}';

  void _finishReply(String corr, bool accepted, {bool measure = false}) {
    final pending = _pendingReplies.remove(corr);
    if (pending == null) return;
    pending.timer.cancel();
    if (_queuedCorr == corr) {
      _queuedCorr = null;
      composerQueued.value = false;
    }
    if (measure && pending.sentAt != null) {
      latestRtt.value = _now().difference(pending.sentAt!);
    }
    _submits.remove(corr)?.complete(accepted);
  }

  /// Replaces the Host composer text, including an empty line.
  void sendComposerLine(String paneId, String line) {
    send(Message.sendInput(SendInput(paneId: paneId, line: line)));
  }

  /// Sends Enter only after the Host accepts the complete line.
  Future<bool> sendComposerSubmit(
    String paneId,
    String line, {
    bool whenIdle = false,
  }) async {
    final generation = _connectionGeneration;
    if (line.isNotEmpty &&
        !await _sendAndWait(SendInput(paneId: paneId, line: line))) {
      return false;
    }
    if (generation != _connectionGeneration) return false;
    return _sendAndWait(
      SendInput(
        paneId: paneId,
        keys: const ['Enter'],
        defer: whenIdle ? 'until_idle' : null,
      ),
    );
  }

  /// Sends an answer to an agent's question as one frame past the line
  /// shadow (R-11-254, R-31-09-41): the text, when non-empty, and `Enter`
  /// together with `bypass_line`, so the Host's held composer line is
  /// untouched. Resolves with the Host's ack.
  Future<bool> sendAnswerSubmit(String paneId, String text) => _sendAndWait(
    SendInput(
      paneId: paneId,
      text: text.isEmpty ? null : text,
      keys: const ['Enter'],
      bypassLine: true,
    ),
  );

  final ValueNotifier<bool> composerQueued = ValueNotifier(false);
  String? _queuedCorr;

  /// Sends the held Enter now without replacing the line again.
  void sendQueuedComposerNow(String paneId) {
    final previous = _queuedCorr;
    final pending = _pendingReplies[previous];
    if (_disposed || previous == null || pending?.paneId != paneId) return;
    final completer = _submits.remove(previous);
    if (completer == null) return;
    _queuedCorr = null;
    composerQueued.value = false;
    _pendingReplies[previous] = (
      sentAt: pending!.sentAt,
      paneId: paneId,
      timer: Timer(_replyTimeout, () => _finishReply(previous, false)),
    );
    final corr = _freshCorr();
    _submits[corr] = completer;
    try {
      send(
        Message.sendInput(SendInput(paneId: paneId, keys: const ['Enter'])),
        corr: corr,
      );
    } on Object {
      // send already completed the transferred request with false.
    }
  }

  /// Cancels the Host-held Enter with a separate correlation ID.
  Future<bool> cancelComposerSubmit(String paneId) =>
      _sendAndWait(SendInput(paneId: paneId, defer: 'cancel'));

  /// Releases requests whose replies cannot arrive after a disconnect.
  void disconnect() {
    _connectionGeneration++;
    for (final corr in _pendingReplies.keys.toList()) {
      _finishReply(corr, false);
    }
  }

  Future<bool> _sendAndWait(SendInput input) {
    if (_disposed) return Future.value(false);
    final corr = _freshCorr();
    final completer = Completer<bool>();
    _submits[corr] = completer;
    try {
      send(Message.sendInput(input), corr: corr);
    } on Object {
      return Future.value(false);
    }
    return completer.future;
  }

  /// Probes only while the terminal screen is visible and the link is live.
  void setRttProbeEnabled({required bool enabled}) {
    if (enabled && _rttProbeTimer != null) return;
    _rttProbeTimer?.cancel();
    _rttProbeTimer = null;
    if (!enabled || _disposed) return;
    _rttProbeTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      try {
        send(const Message.ping(Ping()));
      } on Object catch (error) {
        _log.fine('RTT probe failed: $error');
      }
    });
  }

  /// One `CSI ... m` SGR sequence — the only escape sequence the Host payload ever contains
  /// (R-10-016), matching `sgr_counter.dart`'s own `_sgrSequence` pattern. Kept local rather
  /// than shared: this file owns no path in `app/lib/models/`, and this is a one-line regex,
  /// not a dependency worth crossing package ownership for.
  static final RegExp _sgrSequence = RegExp('\x1B\\[([0-9;]*)m');

  /// The longest line in [text], SGR-stripped, in cells (R-31-13-09, R-31-13-10).
  int _longestLineLength(String text) {
    var longest = 0;
    for (final line in text.split('\n')) {
      final visible = line.replaceAll(_sgrSequence, '');
      if (visible.length > longest) longest = visible.length;
    }
    return longest;
  }

  void _publish(TerminalFrameState next) {
    _state = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  /// Releases every resource this service holds (R-41-100). Does not send `unwatch_pane`; a
  /// caller navigating away calls [detach] first if it wants that sent.
  Future<void> dispose() async {
    _cancelScrollback();
    _lastLiveFrame = null;
    _pendingFrame = null;
    _disposed = true;
    setRttProbeEnabled(enabled: false);
    disconnect();
    composerQueued.dispose();
    latestRtt.dispose();
    _coalesceTimer?.cancel();
    await _subscription.cancel();
    await _stateController.close();
    hostTheme.dispose();
    xterm.dispose();
  }
}
