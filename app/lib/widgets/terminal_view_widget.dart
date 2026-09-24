/// The terminal grid widget, per `docs/90-implementation-plan.md` `WP-16-b` and
/// `docs/31-mockups/08-terminal.md`. It renders one Herdr pane at 1-to-1 fidelity: a persistent
/// `xterm2` `Terminal` fed by `app/lib/services/terminal.dart` (`WP-16-a`), painted through
/// `xterm2`'s `TerminalView`.
///
/// **The grid contract this file publishes to `INT-16-terminal`** (`docs/90-implementation-plan.md`
/// §5.2): [TerminalViewWidget] takes its palette as an explicit [AppColor] constructor argument,
/// never a `Theme.of(context)` lookup (R-33-055, R-33-056), imports no `terminal.dart` symbol, and
/// never reflows the grid to fit the screen (R-31-08-07, R-21-009) — the grid stays exactly
/// [Terminal.viewWidth] columns wide, set from the outside by whoever owns the [Terminal] instance,
/// and this file only ever *reads* that size, through `autoResize: false` and
/// `textScaler: TextScaler.noScaling` (R-21-038). The readable view uses
/// [TerminalViewWidget.textSize], including the default 13 logical pixels.
/// [TerminalViewWidget.overview] fits every Host column; [TerminalViewWidget.customTextSize]
/// retains a continuous pinch zoom between or beyond the presets (R-21-008).
/// Every zoom adopts the render object's exact cell metrics. A wide grid supports pan.
/// The pannable grid rectangle carries the `terminalGridCells` key, the viewport Stack carries
/// `terminalGridArea`. A caller — `terminal.dart`, or the screen that
/// composes it with this widget — owns calling `Terminal.write` and `Terminal.resize`; this file
/// never calls `pane.resize` or `pane.split`, directly or indirectly, per R-21-036.
///
/// The ten named states of `docs/31-mockups/08-terminal.md`'s wireframes and `## States` table
/// this file renders (R-90-011): [TerminalGridPhase.live] (plus its `scrolled` and `selection`
/// modifiers, and the orientation-driven `landscape` layout, none of which are separate phases —
/// see below), [TerminalGridPhase.loadingFirstPaint], [TerminalGridPhase.loadingReconnecting],
/// [TerminalGridPhase.paneGone], [TerminalGridPhase.readFailed],
/// [TerminalGridPhase.protocolMismatch], [TerminalGridPhase.hostInUse],
/// [TerminalGridPhase.offline], and the `truncated` top-of-scrollback banner ([truncatedAtTop]).
/// `paneGone`, `readFailed` and `protocolMismatch` only dim the last painted grid here: each ends
/// the person's work in the pane, so the platform's own alert dialog carries the message and the
/// way out, and the screen that composes this widget raises it (R-03-119, 2026-09-10; until then
/// this file drew a centred block over the grid).
/// `scrolled` and `selection` are not distinct phases: the mockup's own wireframes show them as
/// modifiers over `live` (the connection word turns `paused`, which `app/lib/widgets/status_strip.dart`
/// draws, not this file) — this file tracks them as its own scroll state, layers
/// the jump-to-bottom pill (R-31-08-06, `R-90-010`) over whatever phase is showing, and hands
/// selection (R-21-042) to the platform: the live grid sits inside the SDK's `SelectionArea`,
/// whose handles, magnifier and adaptive toolbar are drawn by the platform, while the
/// [_TerminalSelectionAdapter] render object bridges the cell grid to it and the highlight keeps
/// painting in the theme's `termSelection` colour through `TerminalController.setSelection`.
/// `landscape` is not a phase either: the grid never changes its column
/// count for orientation (R-21-036), so this file's only landscape-specific duty is to keep every
/// offset stable across the rotation (R-31-08-10), which the same state fields that survive an app
/// background and resume already provide.
library;

import 'dart:async' show Timer;
import 'dart:ui'
    show DisplayFeatureType, ParagraphBuilder, ParagraphConstraints;

import 'package:flutter/foundation.dart' show ObserverList, ValueListenable;
import 'package:flutter/gestures.dart'
    show
        Drag,
        GestureDisposition,
        HorizontalDragGestureRecognizer,
        OneSequenceGestureRecognizer,
        VerticalDragGestureRecognizer,
        kTouchSlop;
import 'package:flutter/material.dart' show SelectionArea;
import 'package:flutter/rendering.dart'
    show
        ClearSelectionEvent,
        DirectionallyExtendSelectionEvent,
        GranularlyExtendSelectionEvent,
        LeaderLayer,
        PipelineOwner,
        SelectAllSelectionEvent,
        SelectParagraphSelectionEvent,
        SelectWordSelectionEvent,
        Selectable,
        SelectedContent,
        SelectedContentRange,
        SelectionEdgeUpdateEvent,
        SelectionEvent,
        SelectionEventType,
        SelectionGeometry,
        SelectionPoint,
        SelectionRegistrar,
        SelectionRegistrant,
        SelectionResult,
        SelectionStatus,
        TextGranularity;
import 'package:flutter/widgets.dart';

import 'package:material_symbols_icons/symbols.dart';
import 'package:xterm2/xterm.dart'
    show
        Buffer,
        CellAnchor,
        CellOffset,
        SelectionMode,
        Terminal,
        TerminalController,
        TerminalCursorType,
        TerminalStyle,
        TerminalTheme,
        TerminalView,
        TerminalViewState;

import '../models/messages/theme_palette.dart';
import 'theme/app_color.dart';
import 'theme/app_motion.dart';
import 'theme/app_size.dart';
import 'theme/app_space.dart';
import 'theme/app_type.dart';
import 'theme/chrome_gesture_timing.dart';
import 'theme/chrome_loading_delay.dart';
import 'theme/chrome_strip_action.dart';
import 'theme/chrome_tonal_button.dart';
import 'treatments.dart';

/// `opacity.dim`, per `docs/32-design-language.md` section 5.4's opacity
/// table: "the last painted grid in every non-live state". Every opacity
/// value outside `elev.*` stays a local constant beside its one caller, per
/// the precedent `app/lib/widgets/app_filled_button.dart` (`WP-12-a`) set
/// for `opacity.disabled`.
const double _opacityDim = 0.60;

/// R-32-208: temporary pinch zoom is continuous; Settings still uses its presets.
const double _minimumZoomTextSize = 1;
const double _maximumZoomTextSize = 36;

/// The measured cell metrics of the bundled terminal font, per logical
/// pixel of font size: the maximum printable-ASCII advance and line height
/// through the same `TerminalStyle`-to-paragraph pipeline the `xterm2`
/// 5.2.0 painter measures with (`TerminalPainter._measureCharSize`), taken
/// at a reference size and divided back out — paragraph metrics scale
/// linearly with font size. This is the estimate the first layout fits and
/// pans with; after the frame, `_scheduleMetricsAdoption` re-anchors to the
/// render object's own `cellSize`, so the grid ends exact even where a
/// paragraph engine rounds differently.
final Size _cellMetricsPerPt = _measureCellMetricsPerPt();

/// The estimate of one cell at [fontSize], linear from the reference
/// measurement. The first layout of a fit or a size change sizes the grid
/// box with this; the post-frame adoption replaces it with the painted
/// cell, which hint quantization can shift off the linear value at a
/// fractional point size.
Size _estimateCellSize(double fontSize) => Size(
  fontSize * _cellMetricsPerPt.width,
  fontSize * _cellMetricsPerPt.height,
);

Size _measureCellMetricsPerPt() {
  const double referenceSize = 100;
  final textStyle = TerminalStyle(
    fontSize: referenceSize,
    height: AppType.monoTerminal().height!,
    fontFamily: AppType.monoFontFamily,
    fontFamilyFallback: _fallbackFontFamilies,
  ).toTextStyle();
  final paragraphStyle = textStyle.getParagraphStyle();
  final runStyle = textStyle.getTextStyle(textScaler: TextScaler.noScaling);
  double width = 0;
  double height = 0;
  for (int codePoint = 0x21; codePoint <= 0x7e; codePoint++) {
    final builder = ParagraphBuilder(paragraphStyle);
    builder.pushStyle(runStyle);
    builder.addText(String.fromCharCode(codePoint));
    final paragraph = builder.build();
    paragraph.layout(const ParagraphConstraints(width: double.infinity));
    if (paragraph.maxIntrinsicWidth > width) {
      width = paragraph.maxIntrinsicWidth;
    }
    if (paragraph.height > height) height = paragraph.height;
    paragraph.dispose();
  }
  return Size(width / referenceSize, height / referenceSize);
}

/// The force-read pull of `docs/30-ux-spec.md`'s gesture table ("Force a
/// read: pull down from the top of the grid while already at the bottom"):
/// the drag must begin within this distance of the grid's top edge and
/// travel this far down before it fires. One minimum touch target
/// (R-30-290) keeps both halves deliberate without inventing a new number.
const double _forceReadSlop = AppSize.targetMin;

/// The `TerminalStyle` per-glyph fallback chain, per R-21-014, verbatim: the
/// bundled `JetBrainsMono Nerd Font Mono` (R-21-011) contains no CJK glyphs
/// and no emoji glyphs, so both depend on a system font, searched in this
/// order "when a glyph cannot be found in a higher priority font family"
/// (Flutter's own `TextStyle.fontFamilyFallback` documentation). Order
/// matters: Android system fonts first, then iOS, then the two platforms'
/// emoji fonts, then a generic symbols font, then `monospace` as the last
/// resort — a codepoint neither the bundled font nor any of these resolves
/// renders as a tofu box rather than shifting the grid, per R-21-014's own
/// closing line.
const List<String> _fallbackFontFamilies = <String>[
  // CJK — Android system fonts
  'Noto Sans Mono CJK SC',
  'Noto Sans Mono CJK TC',
  'Noto Sans Mono CJK KR',
  'Noto Sans Mono CJK JP',
  // CJK — iOS system fonts
  'PingFang SC',
  'PingFang TC',
  'PingFang HK',
  'Hiragino Sans',
  'Apple SD Gothic Neo',
  // Emoji — platform system fonts
  'Apple Color Emoji', // iOS
  'Noto Color Emoji', // Android
  // Symbols
  'Noto Sans Symbols',
  'monospace',
];

/// Maps the 20-value terminal palette `docs/32-design-language.md` R-32-140
/// fixes (the 16 ANSI slots plus foreground, background, cursor and
/// selection) onto `xterm2`'s [TerminalTheme], per R-30-150: the emulator
/// MUST be configured with exactly these values and MUST NOT fall back to a
/// package default. This is the one place this file reads [AppColor]; every
/// other cell colour in the widget below comes from the [TerminalTheme]
/// this function returns, never from [AppColor] again, so the grid rectangle
/// itself never depends on anything but this explicit argument (R-33-055,
/// R-33-056).
///
/// `xterm2`'s [TerminalTheme] carries no separate "bold foreground" or "dim
/// foreground" slot: bold text is the terminal's own bright-colour
/// substitution and faint text is the terminal's own opacity reduction,
/// neither of which is one of the 20 values this checklist item names, so
/// neither `AppColor.termFgBold` nor `AppColor.termFgDim` has a slot to fill
/// here. `xterm2`'s three `searchHit*` fields have no Selenized token at
/// all — this app never surfaces `xterm2`'s built-in text search — so they
/// take the selection background, which is the closest existing token for
/// "a highlighted range of cells" and keeps every field on this call an
/// [AppColor] value rather than an invented literal.
/// R-21-044: only the default grid colours follow the Host.
TerminalTheme terminalThemeFrom(AppColor palette, [ThemePalette? hostTheme]) =>
    TerminalTheme(
      cursor: palette.termCursor,
      selection: palette.termSelection,
      foreground: _hostColor(hostTheme?.text, palette.fgPrimary),
      background: _hostColor(hostTheme?.surfaceDim, palette.bgBase),
      black: palette.termAnsi0,
      red: palette.termAnsi1,
      green: palette.termAnsi2,
      yellow: palette.termAnsi3,
      blue: palette.termAnsi4,
      magenta: palette.termAnsi5,
      cyan: palette.termAnsi6,
      white: palette.termAnsi7,
      brightBlack: palette.termAnsi8,
      brightRed: palette.termAnsi9,
      brightGreen: palette.termAnsi10,
      brightYellow: palette.termAnsi11,
      brightBlue: palette.termAnsi12,
      brightMagenta: palette.termAnsi13,
      brightCyan: palette.termAnsi14,
      brightWhite: palette.termAnsi15,
      searchHitBackground: palette.termSelection,
      searchHitBackgroundCurrent: palette.termSelection,
      searchHitForeground: palette.termFg,
    );

Color _hostColor(String? value, Color fallback) {
  if (value == null || value == 'reset') return fallback;
  if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
    throw const FormatException('Invalid Host theme colour');
  }
  return Color(0xff000000 | int.parse(value.substring(1), radix: 16));
}

/// The named, non-modifier states of `docs/31-mockups/08-terminal.md`'s
/// `## States` table this widget renders, per R-90-011. `Empty` is not a
/// member: the mockup's own row says the pane's real single-cursor content
/// "is correct and needs no empty state text", so it is simply [live] with
/// nothing painted, not a special case. `scrolled`, `selection` and
/// `landscape` are not members either — see this file's top doc comment for
/// why they are modifiers, not phases.
enum TerminalGridPhase {
  /// The subscription is up and the revision moves. The default phase.
  live,

  /// The route opened and the first frame has not arrived yet.
  loadingFirstPaint,

  /// The relay link dropped and the app is retrying.
  loadingReconnecting,

  /// The pane closed while the screen was open.
  paneGone,

  /// The Host answered `error` for `watch_pane` or `scroll_request`.
  readFailed,

  /// `herdr_protocol` in `host_info` is not the version this app expects.
  protocolMismatch,

  /// The relay answered `host_in_use` with close code `4006`.
  hostInUse,

  /// The phone has no network, the relay is unreachable, or the computer is
  /// not connected to the relay.
  offline,

  /// This Device was revoked while its session was live: the relay or Host
  /// closed with code `4004` (R-13-054). The session cannot resume; the
  /// only way out is back to the pairing screen (R-13-055).
  revoked,
}

/// The terminal grid, its loading/error/disconnected states, its horizontal
/// pan window, its scrollback affordance and its selection toolbar. See this
/// file's top doc comment for the grid contract and the state list.
class TerminalViewWidget extends StatefulWidget {
  const TerminalViewWidget({
    super.key,
    required this.palette,
    this.hostTheme,
    required this.phase,
    this.terminal,
    this.controller,
    this.textSize = AppType.monoTerminalDefaultSize,
    this.overview = false,
    this.customTextSize,
    this.revision,
    this.hostName,
    this.captureTime,
    this.reconnectAttempt,
    this.errorText,
    this.truncatedAtTop = false,
    this.historyVisible = false,
    this.historyTruncated = false,
    this.historyCanLoadMore = false,
    this.historyGeneration = 0,
    this.onRequestScrollback,
    this.maxScrollOffsetFromBottom = 0,
    this.onGridTap,
    this.onDismissTruncated,
    this.onDiagnostics,
    this.onRevoked,
    this.onSelectionLiveChanged,
    this.onScrollOffsetChanged,
    this.onVisibleColumnsChanged,
    this.onPinchTextSize,
    this.onForceRead,
  }) : assert(
         phase == TerminalGridPhase.loadingFirstPaint || terminal != null,
         'terminal is required for every phase except loadingFirstPaint, '
         'per docs/31-mockups/08-terminal.md: every other state keeps the '
         'last painted grid on screen.',
       );

  /// The explicit palette argument, per R-33-055 and R-33-056. Never a
  /// `Theme.of(context)` lookup.
  final AppColor palette;

  /// R-21-044: palette updates change paint, never terminal contents.
  final ValueListenable<ThemePalette?>? hostTheme;

  /// Which named state, of the list this file's top doc comment gives, to
  /// render.
  final TerminalGridPhase phase;

  /// The persistent `xterm2` emulator instance. Owned and fed by whoever
  /// composes this widget (`app/lib/services/terminal.dart`, `WP-16-a`, per
  /// R-21-001); this file never calls [Terminal.write] or [Terminal.resize].
  /// Required for every [phase] except [TerminalGridPhase.loadingFirstPaint].
  final Terminal? terminal;

  /// The selection controller. This widget creates and owns its own when
  /// omitted, so a caller that does not need to observe the selection from
  /// outside may leave this unset.
  final TerminalController? controller;

  /// The readable font size in logical pixels, from [AppType.monoTerminalSizes].
  /// Every size, including the default 13, paints at its own value unless [overview] is true.
  final int textSize;

  /// Fits every Host column into the viewport without changing the readable [textSize].
  /// The screen owns this temporary mode. It starts false on each pane visit.
  final bool overview;

  /// A route-local pinch size. Overrides either preset without changing [textSize].
  final double? customTextSize;

  /// `pane.revision`, shown by `app/lib/widgets/status_strip.dart`
  /// (`WP-16-c`), not this file; kept here only so a caller has one place to
  /// pass every frame-identifying value down.
  final int? revision;

  /// The paired computer's display name, for the offline message.
  final String? hostName;

  /// When the last painted grid was captured, for the offline message's
  /// "as it was at" sentence (R-30-805).
  final DateTime? captureTime;

  /// The reconnect attempt number, for [TerminalGridPhase.loadingReconnecting].
  final int? reconnectAttempt;

  /// The offline strip's failure-kind sentence for [TerminalGridPhase.offline].
  final String? errorText;

  /// `true` when the person reached the top of the fetched scrollback and
  /// `scroll_response` reported `truncated: true` (R-31-08-19).
  final bool truncatedAtTop;

  /// The grid currently holds an independent fetched history window.
  final bool historyVisible;
  final bool historyTruncated;
  final bool historyCanLoadMore;

  /// Changes only when a history reply replaces the grid. The terminal itself is
  /// mutable, so comparing its old and new row counts in didUpdateWidget is too late.
  final int historyGeneration;

  /// Load older output when a drag approaches the first currently available row.
  final VoidCallback? onRequestScrollback;

  /// Host-reported `scroll.max_offset_from_bottom` from `watch_ack`
  /// (`TerminalService.state.scroll`, `WP-16-a`). Gates the scrollback
  /// affordance: only above zero is there anything to scroll back into
  /// (R-10-026), so this widget only attaches its vertical scroll gesture
  /// when this is positive.
  final int maxScrollOffsetFromBottom;

  /// Fired on a single tap on the grid. Per R-31-08-08 this widget sends
  /// nothing to the pane itself on any gesture (`TerminalView` is
  /// constructed `readOnly: true`); a caller wires this to raise the
  /// keyboard (R-03-054), and the tap itself sends nothing.
  final VoidCallback? onGridTap;

  /// Dismisses the truncated-scrollback strip.
  final VoidCallback? onDismissTruncated;

  /// A tap on the offline strip, routing to `/hosts/:hostId/diagnostics`
  /// per R-30-806.
  final VoidCallback? onDiagnostics;

  /// Fired once, automatically, the moment [phase] becomes
  /// [TerminalGridPhase.revoked] — no tap required, per R-13-055's "return
  /// to the pairing screen": a caller wires this to clear the computer's
  /// stored record (R-13-054) and navigate away. This file only paints the
  /// required message and raises this signal; it owns no router.
  final VoidCallback? onRevoked;

  /// Fires whenever this widget's own selection goes live or clears, in
  /// row units matching `TerminalService.setSelectionLive` (`WP-16-a`).
  /// This file never imports `terminal.dart`; a caller wires this straight
  /// to that service's setter so it can derive the R-21-041 freeze.
  final ValueChanged<bool>? onSelectionLiveChanged;

  /// Fires whenever this widget's own scroll offset changes, in whole
  /// rows above the live bottom (0 at the bottom), matching
  /// `TerminalService.setScrollOffset` and `watch_ack`'s
  /// `scroll.offset_from_bottom` convention.
  final ValueChanged<int>? onScrollOffsetChanged;

  /// Fires whenever the column window of R-21-037 changes, with the
  /// 1-based first and last Host column the screen currently holds, or
  /// `null` when the grid fits the screen and there is no window to
  /// report (R-21-037 point 2). A caller feeds this straight into
  /// `StatusStrip.firstVisibleColumn`/`lastVisibleColumn`.
  final ValueChanged<({int first, int last})?>? onVisibleColumnsChanged;

  /// R-30-302: reports the gesture-start painted size times the cumulative scale.
  /// The caller retains it in [customTextSize]; null restores the starting preset
  /// when the gesture becomes a two-finger scroll. Host geometry never changes.
  final ValueChanged<double?>? onPinchTextSize;

  /// Fires on the force-read gesture of `docs/30-ux-spec.md`'s gesture
  /// table: a pull down that starts at the top of the grid while the
  /// Device's own scroll offset is at the live bottom. A caller wires
  /// this to `TerminalService.requestScrollback` (R-11-053). This widget
  /// sends nothing itself (R-30-300).
  final VoidCallback? onForceRead;

  @override
  State<TerminalViewWidget> createState() => _TerminalViewWidgetState();
}

/// Claims a two-pointer gesture before tap/long-press deadlines, including tiny
/// pinches below Flutter's scale slop. The Listener still supplies exact spans.
/// Single-pointer gestures remain available to the terminal's native recognizers.
class _PinchGestureRecognizer extends OneSequenceGestureRecognizer {
  void claim() => resolve(GestureDisposition.accepted);

  @override
  void handleEvent(PointerEvent event) =>
      stopTrackingIfPointerNoLongerDown(event);

  @override
  void didStopTrackingLastPointer(int pointer) =>
      resolve(GestureDisposition.rejected);

  @override
  String get debugDescription => 'terminal pinch';
}

class _TerminalViewWidgetState extends State<TerminalViewWidget> {
  // Keep the reader's horizontal position and vertical intent across rebuilds and rotation.
  double _horizontalOffsetColumns = 0;
  double _verticalOffsetFromBottom = 0;
  double _viewportTopRows = 0;
  int _liveContentRows = 1;
  bool _terminalContentDirty = true;
  bool _adjustingViewport = false;
  bool _historyViewportPending = false;
  bool _historyRequested = false;
  bool _userScrollInProgress = false;
  bool _truncatedDismissed = false;
  ScrollPhysics? _nativeScrollPhysics;
  ScrollPhysics? _historyScrollPhysics;
  (AppColor, String?, String?)? _themeKey;
  TerminalTheme? _cachedTheme;
  (int, int)? _semanticsRows;
  String? _cachedSemantics;

  late final ScrollController _verticalScroll;
  late final TerminalController _controller;
  bool _ownsController = false;

  bool _showFirstPaintLine = false;
  Timer? _firstPaintTimer;

  HorizontalDragGestureRecognizer? _panRecognizer;
  double _viewportColumns = 0;
  double _viewportHeight = 0;

  /// The current custom size, readable preset, or corrected Overview fit.
  /// A width, column count, readable size, or mode change recomputes this value.
  double _fontSize = AppType.monoTerminalDefaultSize.toDouble();

  /// The cell size every offset, window and selection computation in this
  /// file shares with the grid box's width: the [_estimateCellSize] value
  /// before the first frame, the render object's own measured `cellSize`
  /// after it — the value every pointer-to-cell mapping inside `xterm2`
  /// resolves with, so the box and the paint never disagree. The
  /// 2026-09-08 real-device run caught a 1.65 px divergence over 282
  /// columns from font hint quantization at a fractional point size, which
  /// a re-multiplied estimate ratio cannot absorb; the adopted cell can.
  Size _cellSize = _estimateCellSize(
    AppType.monoTerminalDefaultSize.toDouble(),
  );

  /// The current fit inputs and the width the last correction targeted.
  /// At most two corrections use the painted cell ratio to prevent oscillation.
  (double, int, int, bool, double?)? _fitKey;
  double _lastAvailableWidth = 0;
  int _fitCorrections = 0;
  bool _metricsAdoptionScheduled = false;

  // Raw positions retain sub-slop precision. The recognizer claims two fingers
  // immediately to suppress taps and selection. Coordinated vertical movement
  // still drives the platform's scroll activity. A third finger stays unbound.
  final Map<int, Offset> _pinchPointers = <int, Offset>{};
  final _pinchRecognizer = _PinchGestureRecognizer();
  double? _pinchStartSpan;
  List<Offset> _pinchStartPoints = const [];
  Offset _twoFingerScrollCenter = Offset.zero;
  Drag? _twoFingerScroll;
  bool _twoFingerScrolling = false;
  double _pinchStartTextSize = 0;
  double? _pinchStartCustomTextSize;

  // The force-read pull's one tracked pointer: a second finger never
  // joins this gesture (R-30-303 leaves multi-finger unbound beyond the
  // pinch).
  int? _forceReadPointer;
  double _forceReadStartDy = 0;
  bool _forceReadFired = false;

  ({int first, int last})? _reportedWindow;
  bool _windowReportScheduled = false;

  // The platform `SelectionArea` owns the selection gestures; the adapter
  // render object under it maps them onto cells. This file keeps only the
  // edge autoscroll: the SDK's `EdgeDraggingAutoScroller` binds the nearest
  // *ancestor* `Scrollable`, and the grid's lives inside `TerminalView`,
  // below the area, so a drag past the grid edge is stepped from here.
  final GlobalKey<TerminalViewState> _terminalViewKey =
      GlobalKey<TerminalViewState>();
  final GlobalKey _selectionAdapterKey = GlobalKey();
  final FocusNode _selectionFocusNode = FocusNode(canRequestFocus: false);
  Offset? _selectionPointer;
  Timer? _selectionScrollTimer;
  int _edgeDragIdleTicks = 0;
  bool _edgeDragContinuous = false;
  int _selectionBufferRows = 0;

  @override
  void initState() {
    super.initState();
    _verticalScroll = ScrollController()..addListener(_onVerticalScroll);
    _controller = widget.controller ?? _GridSelectionController();
    _ownsController = widget.controller == null;
    _controller.addListener(_onControllerChanged);
    widget.terminal?.addListener(_onTerminalContentChanged);
    _scheduleFirstPaintLine();
    _maybeFireRevoked();
  }

  @override
  void didUpdateWidget(TerminalViewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.historyVisible != widget.historyVisible ||
        oldWidget.historyGeneration != widget.historyGeneration) {
      _truncatedDismissed = false;
      _historyViewportPending = widget.historyVisible;
      if (_hasSelection && widget.historyVisible) {
        _historyViewportPending = false;
        final rows = widget.terminal!.buffer.lines.length;
        _viewportTopRows += rows - _selectionBufferRows;
        _selectionBufferRows = rows;
        _historyRequested = false;
      }
      if (widget.historyVisible) {
        _verticalOffsetFromBottom = _max(
          _verticalOffsetFromBottom,
          _cellHeight,
        );
      } else {
        _verticalOffsetFromBottom = 0;
        _viewportTopRows = 0;
        _historyRequested = false;
      }
    }
    if (oldWidget.terminal != widget.terminal) {
      oldWidget.terminal?.removeListener(_onTerminalContentChanged);
      widget.terminal?.addListener(_onTerminalContentChanged);
      _onTerminalContentChanged();
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerChanged);
      if (_ownsController) _controller.dispose();
      _controller = widget.controller ?? _GridSelectionController();
      _ownsController = widget.controller == null;
      _controller.addListener(_onControllerChanged);
    }
    if (widget.phase != TerminalGridPhase.loadingFirstPaint) {
      _firstPaintTimer?.cancel();
    } else if (oldWidget.phase != TerminalGridPhase.loadingFirstPaint) {
      _showFirstPaintLine = false;
      _scheduleFirstPaintLine();
    }
    if (widget.phase == TerminalGridPhase.revoked &&
        oldWidget.phase != TerminalGridPhase.revoked) {
      _maybeFireRevoked();
    }
  }

  @override
  void dispose() {
    _firstPaintTimer?.cancel();
    _stopSelectionAutoscroll();
    _selectionFocusNode.dispose();
    widget.terminal?.removeListener(_onTerminalContentChanged);
    _twoFingerScroll?.cancel();
    _verticalScroll
      ..removeListener(_onVerticalScroll)
      ..dispose();
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) _controller.dispose();
    _panRecognizer?.dispose();
    _pinchRecognizer.dispose();
    super.dispose();
  }

  void _scheduleFirstPaintLine() {
    if (widget.phase != TerminalGridPhase.loadingFirstPaint) return;
    // R-30-004: a skeleton/spinner-equivalent line appears only after this
    // grace period, so a fast response never flashes it.
    _firstPaintTimer = Timer(ChromeLoadingDelay.skeleton, () {
      if (!mounted) return;
      setState(() => _showFirstPaintLine = true);
    });
  }

  /// R-13-055: fires [TerminalViewWidget.onRevoked] once, after the current
  /// frame, the moment [phase] is or becomes [TerminalGridPhase.revoked] —
  /// deferred past the build phase, per the standard Flutter idiom, since
  /// the caller's response is a navigation, not safe to run mid-build.
  void _maybeFireRevoked() {
    if (widget.phase != TerminalGridPhase.revoked) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onRevoked?.call();
    });
  }

  void _onVerticalScroll() {
    if (_adjustingViewport ||
        _terminalContentDirty ||
        !_verticalScroll.hasClients) {
      return;
    }
    final position = _verticalScroll.position;
    if (!position.hasContentDimensions) return;
    _viewportTopRows = position.pixels / _cellHeight;
    double offset = (_liveBottom - position.pixels).clamp(0.0, double.infinity);
    // A native spring-back is not a request to leave history. Retain a row of
    // scroll intent while this two-finger gesture waits for its first reply.
    // A new gesture or the explicit bottom action clears the latch.
    if (_twoFingerScrolling && _historyRequested && !widget.historyVisible) {
      offset = _max(offset, _cellHeight);
    }
    if (offset == _verticalOffsetFromBottom) return;
    setState(() => _verticalOffsetFromBottom = offset);
    widget.onScrollOffsetChanged?.call((offset / _cellHeight).round());
  }

  void _onTerminalContentChanged() {
    _terminalContentDirty = true;
    _cachedSemantics = null;
    _scheduleMetricsAdoption();
  }

  /// Snapshot padding can leave the emulator cursor on a blank final Host row.
  /// Scan only after terminal updates, once per frame, without allocating row strings.
  void _updateLiveContentRows() {
    if (!_terminalContentDirty) return;
    _terminalContentDirty = false;
    final lines = widget.terminal!.buffer.lines;
    for (int row = lines.length - 1; row >= 0; row--) {
      final line = lines[row];
      for (int column = line.length - 1; column >= 0; column--) {
        if (line.getCodePoint(column) > 0x20) {
          _liveContentRows = row + 1;
          return;
        }
      }
    }
    _liveContentRows = 1;
  }

  /// The follow anchor. A Host `pane_frame` is a fixed-height snapshot of the
  /// pane's own viewport, and an agent TUI moves its last non-blank row between
  /// consecutive frames — measured live 2026-09-08 on an 85-row `omp` pane: the
  /// frame's last non-blank row alternates between 83 and 85 while the pane
  /// redraws. Following that row moved the whole window by the difference on
  /// every frame, which is the flicker R-21-021's amendment records. So the
  /// anchor holds still while the last ink row stays inside the window, and
  /// moves only to bring that row back into view: down when new output runs
  /// past the window bottom, up when a clear leaves the window blank. A sparse
  /// pane whose ink fits the first screenful therefore anchors at the top
  /// (R-31-08-16), and a 27-row shell inside an 87-row buffer never lands on
  /// the 60 blank rows below its prompt when the keyboard shrinks the viewport
  /// (measured live 2026-09-11).
  double get _liveBottom {
    final position = _verticalScroll.position;
    if (widget.historyVisible) return position.maxScrollExtent;
    final double viewport = position.viewportDimension;
    final double inkBottom = _liveContentRows * _cellHeight;
    final double current = position.pixels;
    final bool inkVisible =
        inkBottom > current && inkBottom <= current + viewport;
    final double target = inkVisible ? current : inkBottom - viewport;
    return target.clamp(0.0, position.maxScrollExtent);
  }

  /// xterm follows the full Host row count after a clear-and-home snapshot.
  /// Restore the content viewport after layout without reporting a user scroll.
  void _syncVerticalViewport() {
    if (!_verticalScroll.hasClients) return;
    // Let a two-finger drag and its native bounce finish without snapping an
    // overscroll back to zero, cancelling the drag and its pending history read.
    // A new history window still restores its row anchor immediately.
    if (_twoFingerScrolling &&
        _userScrollInProgress &&
        !_historyViewportPending) {
      return;
    }
    final position = _verticalScroll.position;
    if (!position.hasContentDimensions) return;
    if (_historyViewportPending) {
      _historyViewportPending = false;
      _viewportTopRows =
          (position.maxScrollExtent - _verticalOffsetFromBottom).clamp(
            0.0,
            position.maxScrollExtent,
          ) /
          _cellHeight;
    }
    final bool follow = !_isScrolledBack && !_hasSelection;
    final double target = follow
        ? _liveBottom
        : (_viewportTopRows * _cellHeight).clamp(0.0, position.maxScrollExtent);
    if (follow) _viewportTopRows = target / _cellHeight;
    if ((position.pixels - target).abs() < 0.01) return;
    _adjustingViewport = true;
    try {
      _verticalScroll.jumpTo(target);
    } finally {
      _adjustingViewport = false;
    }
    // The jump happens after layout and suppresses the user-scroll listener.
    // Rebuild the semantics for the restored window as well as moving its paint.
    setState(() {});
  }

  void _onControllerChanged() {
    _selectionBufferRows = widget.terminal?.buffer.lines.length ?? 0;
    if (!_hasSelection) _stopSelectionAutoscroll();
    setState(() {});
    widget.onSelectionLiveChanged?.call(_hasSelection);
  }

  bool get _isScrolledBack => _verticalOffsetFromBottom > 0;
  bool get _hasSelection => _controller.selection != null;

  double get _cellWidth => _cellSize.width;
  double get _cellHeight => _cellSize.height;

  int get _gridColumns => widget.terminal?.viewWidth ?? 0;

  /// True when the whole Host grid fits the viewport: no window, no pan,
  /// and R-21-037's range report stays hidden. The epsilon absorbs float
  /// noise from the fit division, which computes the two sides of this
  /// comparison from each other.
  bool get _gridFits => _gridColumns <= _viewportColumns + 0.01;

  /// Readable mode keeps the selected font size. Overview fits every Host column
  /// into the unobscured width and never enlarges the selected size (R-21-008).
  /// The painted cell replaces this estimate after layout. Host geometry never changes.
  double _candidateFontSize(double availableWidth) {
    final custom = widget.customTextSize;
    if (custom != null) return custom;
    final int textSize = widget.textSize;
    if (!widget.overview) {
      return textSize.toDouble();
    }
    final int columns = _gridColumns;
    if (columns <= 0 || availableWidth <= 0 || _cellMetricsPerPt.width <= 0) {
      return textSize.toDouble();
    }
    final double fit = availableWidth / (columns * _cellMetricsPerPt.width);
    return fit < textSize ? fit : textSize.toDouble();
  }

  /// Adopts `RenderTerminal.cellSize` for every grid size and pointer-to-cell calculation.
  /// Only overview can shrink an overshoot, at most twice for each set of fit inputs.
  void _scheduleMetricsAdoption() {
    if (_metricsAdoptionScheduled || widget.terminal == null) return;
    _metricsAdoptionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _metricsAdoptionScheduled = false;
      if (!mounted || _fontSize <= 0) return;
      final state = _terminalViewKey.currentState;
      if (state == null) return;
      final Size cell = state.renderTerminal.cellSize;
      if (cell.width <= 0 || cell.height <= 0) return;
      double? corrected;
      final int columns = _gridColumns;
      if (widget.overview &&
          widget.customTextSize == null &&
          _fitCorrections < 2 &&
          columns > 0 &&
          columns * cell.width > _lastAvailableWidth + 0.5) {
        final double step =
            _fontSize * ((_lastAvailableWidth - 0.5) / (columns * cell.width));
        if (step > 0 && step < _fontSize) corrected = step;
      }
      final bool changed =
          (cell.width - _cellSize.width).abs() > 0.0001 ||
          (cell.height - _cellSize.height).abs() > 0.0001;
      if (changed || corrected != null) {
        setState(() {
          _cellSize = cell;
          if (corrected != null) {
            _fitCorrections++;
            _fontSize = corrected;
          }
        });
      }
      _updateLiveContentRows();
      _syncVerticalViewport();
    });
  }

  double get _maxHorizontalOffsetColumns {
    final max = _gridColumns - _viewportColumns;
    return max > 0.01 ? max : 0;
  }

  void _clampHorizontalOffset() {
    final max = _maxHorizontalOffsetColumns;
    if (_horizontalOffsetColumns > max) _horizontalOffsetColumns = max;
    if (_horizontalOffsetColumns < 0) _horizontalOffsetColumns = 0;
  }

  /// R-21-040: the horizontal pan MUST begin only from a touch outside
  /// `MediaQueryData.systemGestureInsets`, and this file MUST set no
  /// gesture exclusion anywhere. A touch inside the inset is never claimed
  /// here at all, so the system's own edge gesture keeps priority — the
  /// correct mechanism is to not compete for the pointer, never to exclude
  /// it after the fact.
  void _maybeStartPan(PointerDownEvent event, BuildContext context) {
    if (_gridFits) return;
    final insets = MediaQuery.systemGestureInsetsOf(context);
    final width = MediaQuery.sizeOf(context).width;
    // Global, not local: the recognizer now listens below the pan transform,
    // whose local x shifts with the pan offset while the system gesture
    // insets stay screen-relative.
    final dx = event.position.dx;
    if (dx < insets.left || dx > width - insets.right) return;
    (_panRecognizer ??= HorizontalDragGestureRecognizer(debugOwner: this))
      ..onUpdate = _onPanUpdate
      ..addPointer(event);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_pinchPointers.length >= 2) return;
    setState(() {
      _horizontalOffsetColumns -= details.delta.dx / _cellWidth;
      _clampHorizontalOffset();
    });
  }

  /// Scale from the actual painted size, including Overview's fractional fit.
  /// Repeated updates use the same baseline, so they never compound or snap.
  void _onPinchMove() {
    final callback = widget.onPinchTextSize;
    final start = _pinchStartSpan;
    if (callback == null ||
        start == null ||
        start <= 0 ||
        _pinchPointers.length != 2) {
      return;
    }
    final points = _pinchPointers.values.toList();
    final double span = (points[0] - points[1]).distance;
    if (span <= 0) return;
    final center = (points[0] + points[1]) / 2;
    if (!_twoFingerScrolling && _verticalScroll.hasClients) {
      final first = points[0].dy - _pinchStartPoints[0].dy;
      final second = points[1].dy - _pinchStartPoints[1].dy;
      // Both fingers must travel together; moving only one finger remains a
      // pinch even when its midpoint moves. Use Flutter's drag slop only for
      // scrolling, never as a threshold for fine zoom adjustments.
      if (first * second > 0 &&
          first.abs() > kTouchSlop &&
          second.abs() > kTouchSlop &&
          (span - start).abs() < kTouchSlop) {
        _twoFingerScrolling = true;
        callback(_pinchStartCustomTextSize);
      }
    }
    if (_twoFingerScrolling && _verticalScroll.hasClients) {
      _twoFingerScroll ??= _verticalScroll.position.drag(
        DragStartDetails(globalPosition: center),
        () => _twoFingerScroll = null,
      );
    }
    final scroll = _twoFingerScroll;
    if (scroll != null) {
      final delta = center.dy - _twoFingerScrollCenter.dy;
      _twoFingerScrollCenter = center;
      scroll.update(
        DragUpdateDetails(
          delta: Offset(0, delta),
          primaryDelta: delta,
          globalPosition: center,
        ),
      );
      return;
    }
    // A very wide Overview may already fit below the normal minimum. Do not
    // jump on the first movement in that case; it remains the gesture's floor.
    final minimum = _pinchStartTextSize < _minimumZoomTextSize
        ? _pinchStartTextSize
        : _minimumZoomTextSize;
    final size = (_pinchStartTextSize * span / start).clamp(
      minimum,
      _maximumZoomTextSize,
    );
    if (size != widget.customTextSize) callback(size);
  }

  void _onPinchPointerDown(PointerDownEvent event) {
    if (widget.onPinchTextSize == null) return;
    if (_pinchPointers.isEmpty) _twoFingerScrolling = false;
    _pinchRecognizer.addPointer(event);
    _pinchPointers[event.pointer] = event.position;
    if (_pinchPointers.length >= 2) _pinchRecognizer.claim();
    if (_pinchPointers.length == 2) {
      _stopSelectionAutoscroll();
      final points = _pinchPointers.values.toList();
      _pinchStartPoints = points;
      _twoFingerScrollCenter = (points[0] + points[1]) / 2;
      _pinchStartSpan = (points[0] - points[1]).distance;
      _pinchStartTextSize = _fontSize;
      _pinchStartCustomTextSize = widget.customTextSize;
      _forceReadPointer = null;
    } else if (_pinchPointers.length > 2) {
      _pinchStartSpan = null;
      _twoFingerScroll?.cancel();
    }
  }

  void _onPinchPointerMove(PointerMoveEvent event) {
    if (!_pinchPointers.containsKey(event.pointer)) return;
    _pinchPointers[event.pointer] = event.position;
    _onPinchMove();
  }

  void _onPinchPointerEnd(int pointer) {
    if (_pinchPointers.remove(pointer) != null && _pinchPointers.length < 2) {
      _pinchStartSpan = null;
      _twoFingerScroll?.end(DragEndDetails(primaryVelocity: 0));
    }
  }

  /// The force-read pull (see [onForceRead]): one pointer, starting
  /// within [_forceReadSlop] of the first cell row — R-21-039's cutout
  /// inset sits between this Listener's top edge and that row, and the
  /// band counts as the grid's top for the pull — while the Device's own
  /// offset is at the live bottom, fired once per gesture after
  /// [_forceReadSlop] of downward travel. A bare `Listener` sees the
  /// drag without entering the gesture arena, so the scrollback drag of
  /// R-30-306 keeps working beside it.
  void _onForceReadPointerDown(PointerDownEvent event, double topInset) {
    if (_pinchPointers.length >= 2) return;
    if (widget.onForceRead == null || _forceReadPointer != null) return;
    if (_verticalOffsetFromBottom > 0) return; // not at the live bottom
    if (event.localPosition.dy > _forceReadSlop + topInset) return;
    _forceReadPointer = event.pointer;
    _forceReadStartDy = event.localPosition.dy;
    _forceReadFired = false;
  }

  void _onForceReadPointerMove(PointerMoveEvent event) {
    if (event.pointer != _forceReadPointer || _forceReadFired) return;
    if (event.localPosition.dy - _forceReadStartDy >= _forceReadSlop) {
      _forceReadFired = true;
      widget.onForceRead?.call();
    }
  }

  void _onForceReadPointerEnd(int pointer) {
    if (pointer == _forceReadPointer) _forceReadPointer = null;
  }

  /// The column window of R-21-037, 1-based and inclusive, or `null`
  /// when the grid fits the window and there is no range to report.
  ({int first, int last})? _visibleColumnWindow() {
    final int columns = _gridColumns;
    if (columns <= 0 || _viewportColumns <= 0 || _gridFits) return null;
    final int first = _horizontalOffsetColumns.floor() + 1;
    final int unclamped = (_horizontalOffsetColumns + _viewportColumns).floor();
    final int last = unclamped > columns
        ? columns
        : (unclamped < first ? first : unclamped);
    return (first: first, last: last);
  }

  /// Reports the window after the frame, so a caller may `setState` in
  /// response even when this runs mid-build (the `LayoutBuilder` below
  /// is where both the pan offset and the viewport size land).
  void _reportVisibleColumns() {
    if (_windowReportScheduled) return;
    if (_visibleColumnWindow() == _reportedWindow) return;
    _windowReportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _windowReportScheduled = false;
      if (!mounted) return;
      final window = _visibleColumnWindow();
      if (window == _reportedWindow) return;
      _reportedWindow = window;
      widget.onVisibleColumnsChanged?.call(window);
    });
  }

  /// The adapter render object reports every selection-edge drag position
  /// here. A position near the grid's top or bottom edge autoscrolls one row
  /// per [ChromeGestureTiming.selectionAutoscrollStep]. For a handle drag the
  /// adapter answers the SDK with `SelectionResult.pending`, so the platform
  /// re-sends the edge event every frame; those events are the liveness
  /// signal, and the selection extension itself rides on them. For a
  /// long-press drag (word granularity, sent once per move) the timer
  /// re-applies the last edge after each scroll step, and the gesture's end
  /// arrives as the pointer-up on this widget's own Listener.
  void _onSelectionEdgeDrag(
    Offset globalPosition, {
    required bool continuous,
  }) {
    _selectionPointer = globalPosition;
    _edgeDragIdleTicks = 0;
    _edgeDragContinuous = continuous;
    if (_selectionDragDirection(globalPosition) == 0) {
      _stopSelectionAutoscroll();
      return;
    }
    _selectionScrollTimer ??= Timer.periodic(
      ChromeGestureTiming.selectionAutoscrollStep,
      (_) {
        // Two steps without a fresh edge event can only mean a handle drag
        // ended inside the platform's overlay, which this widget never sees.
        if (_edgeDragContinuous && ++_edgeDragIdleTicks > 2) {
          _stopSelectionAutoscroll();
          return;
        }
        _scrollSelectionStep();
        if (!_edgeDragContinuous) _adapterRenderObject?.reapplyEdgeDrag();
      },
    );
  }

  void _stopSelectionAutoscroll() {
    _selectionScrollTimer?.cancel();
    _selectionScrollTimer = null;
    _selectionPointer = null;
    _edgeDragIdleTicks = 0;
  }

  // The one-finger vertical drag on the grid, forwarded by the selection
  // adapter (which absorbs the pointer so the platform selection gestures own
  // the arena) into the grid's own scroll position — the same
  // `position.drag` path the two-finger scroll uses, so every scroll
  // notification, the keyboard dismissal and the history request behave as
  // they did with the scrollable's own drag.
  Drag? _gridDrag;

  void _onGridDragStart(DragStartDetails details) {
    _gridDrag?.cancel();
    if (!_verticalScroll.hasClients) return;
    _gridDrag = _verticalScroll.position.drag(
      details,
      () => _gridDrag = null,
    );
  }

  void _onGridDragUpdate(DragUpdateDetails details) {
    _gridDrag?.update(details);
  }

  void _onGridDragEnd(DragEndDetails details) {
    _gridDrag?.end(details);
  }

  void _onGridDragCancel() {
    _gridDrag?.cancel();
  }

  _RenderTerminalSelection? get _adapterRenderObject =>
      _selectionAdapterKey.currentContext?.findRenderObject()
          as _RenderTerminalSelection?;

  /// -1 when [globalPosition] is within one minimum touch target of the
  /// grid's top edge, 1 near the bottom edge, 0 anywhere else.
  int _selectionDragDirection(Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return 0;
    final local = box.globalToLocal(globalPosition);
    final inset = _cutoutSafeInset(context);
    if (local.dy < inset.top + AppSize.targetMin) return -1;
    if (local.dy > box.size.height - inset.bottom - AppSize.targetMin) {
      return 1;
    }
    return 0;
  }

  void _scrollSelectionStep() {
    final pointer = _selectionPointer;
    if (pointer == null ||
        !_verticalScroll.hasClients ||
        _terminalContentDirty) {
      return;
    }
    final direction = _selectionDragDirection(pointer);
    if (direction == 0) return;
    final position = _verticalScroll.position;
    final target = (position.pixels + direction * _cellHeight).clamp(
      0.0,
      position.maxScrollExtent,
    );
    if (target != position.pixels) _verticalScroll.jumpTo(target);
    // Reaching the top of the fetched rows asks the Host for older history,
    // the same request the scroll notification path makes.
    if (direction < 0 &&
        target <= position.viewportDimension &&
        widget.maxScrollOffsetFromBottom > 0 &&
        (!widget.historyVisible || widget.historyCanLoadMore) &&
        !_historyRequested) {
      _historyRequested = true;
      widget.onRequestScrollback?.call();
    }
  }

  /// R-30-730: under reduced motion every `motion.duration.*` becomes 0 ms
  /// and every `motion.curve.*` becomes linear — an instant swap, not a
  /// perceptible scroll.
  void _jumpToBottom() {
    _userScrollInProgress = false;
    _twoFingerScrolling = false;
    if (!_verticalScroll.hasClients) return;
    final double bottom = _liveBottom;
    if (MediaQuery.disableAnimationsOf(context)) {
      _verticalScroll.jumpTo(bottom);
      _onVerticalScroll();
      return;
    }
    unawaited(
      _verticalScroll
          .animateTo(
            bottom,
            duration: AppMotion.durationBase,
            curve: AppMotion.curveMove,
          )
          .then((_) {
            if (mounted) _onVerticalScroll();
          }),
    );
  }

  /// The grid's one semantics node, per R-30-710 and R-30-711: the visible
  /// screen as plain text, trailing spaces stripped per line, empty lines
  /// collapsed to one. Built at the terminal's own full width, never
  /// clipped to the columns the pan window currently shows, because a
  /// screen reader cannot pan (R-21-037 point 4).
  String _semanticsLabel(Terminal terminal) {
    final lines = terminal.buffer.lines;
    if (lines.length == 0) return '';
    final position = _verticalScroll.hasClients
        ? _verticalScroll.position
        : null;
    final top = position?.hasContentDimensions == true ? position!.pixels : 0.0;
    final height = _viewportHeight;
    final first = (top / _cellHeight).floor().clamp(0, lines.length - 1);
    final end = ((top + height) / _cellHeight).ceil().clamp(
      first + 1,
      lines.length,
    );
    final rows = (first, end);
    if (_cachedSemantics != null && _semanticsRows == rows) {
      return _cachedSemantics!;
    }
    _semanticsRows = rows;
    final collapsed = <String>[];
    for (var row = first; row < end; row++) {
      final line = lines[row].getText().trimRight();
      if (line.isEmpty && collapsed.isNotEmpty && collapsed.last.isEmpty) {
        continue;
      }
      collapsed.add(line);
    }
    return _cachedSemantics = collapsed.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final hostTheme = widget.hostTheme;
    if (hostTheme == null) return _build(context);
    return ValueListenableBuilder<ThemePalette?>(
      valueListenable: hostTheme,
      builder: (context, _, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final color = widget.palette;
    return LayoutBuilder(
      builder: (context, constraints) {
        // The fit and the window both measure against the unobscured cell
        // rectangle (R-21-039), never the full-width background, and the
        // fit recomputes whenever an input moves, so an orientation
        // change, a viewport change or a Host column change lands here.
        final double availableWidth =
            constraints.maxWidth - _cutoutSafeInset(context).horizontal;
        _viewportHeight =
            constraints.maxHeight - _cutoutSafeInset(context).vertical;
        // Recompute the candidate only when an input moved; the adopted
        // painted cell and any taken correction survive untouched
        // rebuilds, so the metrics never oscillate under setState.
        final fitKey = (
          availableWidth,
          _gridColumns,
          widget.textSize,
          widget.overview,
          widget.customTextSize,
        );
        if (fitKey != _fitKey) {
          _fitKey = fitKey;
          _lastAvailableWidth = availableWidth;
          _fontSize = _candidateFontSize(availableWidth);
          _cellSize = _estimateCellSize(_fontSize);
          _fitCorrections = 0;
        }
        _viewportColumns = _cellWidth > 0 && availableWidth > 0
            ? availableWidth / _cellWidth
            : 0;
        _clampHorizontalOffset();
        _reportVisibleColumns();
        _scheduleMetricsAdoption();
        return ColoredBox(
          // The grid background runs edge to edge and under a display
          // cutout; only the cell rectangle inside it is inset, per
          // R-21-039.
          color: _hostColor(widget.hostTheme?.value?.surfaceDim, color.bgBase),
          child: Padding(
            padding:
                EdgeInsets.zero, // space.0 on the screen edge, per R-30-230.
            child: Stack(
              key: const ValueKey('terminalGridArea'),
              children: [
                Positioned.fill(child: _buildGridArea(context, color)),
                if (widget.phase == TerminalGridPhase.live && _isScrolledBack)
                  _buildJumpToBottomPill(color),
                if (widget.truncatedAtTop ||
                    (widget.historyVisible &&
                        widget.historyTruncated &&
                        _viewportTopRows <= 0.01 &&
                        !_truncatedDismissed))
                  _buildTruncatedStrip(color),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGridArea(BuildContext context, AppColor color) {
    switch (widget.phase) {
      case TerminalGridPhase.loadingFirstPaint:
        return _buildFirstPaintLoading(color);
      case TerminalGridPhase.loadingReconnecting:
        return _buildDimmedGrid(
          context,
          color,
          overlay: Treatment.warning(
            label: 'Reconnecting... try ${widget.reconnectAttempt ?? 1}',
          ),
        );
      // R-03-119: the three states that end the work only dim the grid here;
      // the screen raises the platform's own alert over it.
      case TerminalGridPhase.paneGone:
      case TerminalGridPhase.readFailed:
      case TerminalGridPhase.protocolMismatch:
        return _buildDimmedGrid(context, color);
      case TerminalGridPhase.hostInUse:
        return _buildDimmedGrid(
          context,
          color,
          overlay: const Treatment.warning(
            label: 'Another phone is using this pane.',
          ),
        );
      case TerminalGridPhase.offline:
        return _buildDimmedGrid(
          context,
          color,
          overlay: Treatment.warning(label: widget.errorText ?? 'No network.'),
          overlayDetail: widget.hostName != null && widget.captureTime != null
              ? 'This is ${widget.hostName} as it was at '
                    '${_formatCaptureTime(widget.captureTime!)}.'
              : null,
          onOverlayTap: widget.onDiagnostics,
        );
      case TerminalGridPhase.revoked:
        return _buildDimmedGrid(
          context,
          color,
          // R-13-055's one required message, centred on `color.bg.raised`
          // across the grid; `onRevoked` carries the way out, so no action.
          block: Center(
            child: ColoredBox(
              color: color.bgRaised,
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.space6),
                child: SizedBox(
                  width: double.infinity,
                  child: Text(
                    'Connection lost — this device has been revoked',
                    style: AppType.body.copyWith(color: color.fgPrimary),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        );
      case TerminalGridPhase.live:
        return _buildLiveGrid(context, color);
    }
  }

  Widget _buildFirstPaintLoading(AppColor color) {
    return Center(
      child: _showFirstPaintLine
          ? Text(
              'Reading pane...',
              // `color.fg.secondary`, per the mockup's own row. `termBg`
              // equals `bgBase` by value (R-32-100) and nothing has
              // painted yet, so the already-measured `fg.secondary` on
              // `bg.base` row of R-32-150 (6.07 dark, 5.37 light) covers
              // this pair without a new measurement.
              style: AppType.monoTerminal(size: widget.textSize)
                  .copyWith(color: color.fgSecondary),
              // No spinner and no skeleton grid: a fake grid of grey bars
              // looks like real output, per the mockup's own row.
            )
          : const SizedBox.shrink(),
    );
  }

  /// Every non-live state keeps the last painted grid visible, dimmed to
  /// `opacity.dim`, per R-31-08-05: the last known screen is the most
  /// useful thing on the phone. The grid MUST NOT be cleared.
  Widget _buildDimmedGrid(
    BuildContext context,
    AppColor color, {
    Widget? block,
    Widget? overlay,
    String? overlayDetail,
    VoidCallback? onOverlayTap,
  }) {
    return Stack(
      children: [
        Positioned.fill(
          child: Opacity(
            opacity: _opacityDim,
            child: _buildLiveGrid(context, color, interactive: false),
          ),
        ),
        if (overlay != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildStrip(
              color,
              onTap: onOverlayTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  overlay,
                  if (overlayDetail != null)
                    Padding(
                      // The detail hangs under the label, not under the glyph: its
                      // leading edge is the treatment's `size.icon.sm` glyph plus the
                      // `space.2` gap before the label (R-32-506's anatomy), so the
                      // two lines read as one title and its description.
                      padding: const EdgeInsets.only(
                        top: AppSpace.space1,
                        left: AppSize.iconSm + AppSpace.space2,
                      ),
                      child: Text(
                        overlayDetail,
                        style: AppType.caption.copyWith(
                          color: color.fgSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (block != null) Positioned.fill(child: block),
      ],
    );
  }

  /// The `Strip` component of `docs/32-design-language.md` section 7.22
  /// (R-32-561): full width, opaque `color.bg.raised`, `border.hairline`
  /// in `color.border.subtle` above and below, padding `space.3` vertical
  /// by `space.4` horizontal. Shared by the reconnecting / host-in-use /
  /// offline banner and the truncated-scrollback strip: both are chrome
  /// drawn over the grid rect, and R-31-08-16 requires every one of them
  /// to be opaque, with a boundary a person can actually read against the
  /// terminal pixels behind it.
  Widget _buildStrip(
    AppColor color, {
    required Widget child,
    VoidCallback? onTap,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.bgRaised,
        border: Border.symmetric(
          horizontal: BorderSide(color: color.borderSubtle),
        ),
      ),
      child: onTap == null
          ? Padding(
              padding: const EdgeInsets.symmetric(
                vertical: AppSpace.space3,
                horizontal: AppSpace.space4,
              ),
              child: child,
            )
          : ChromeStripAction(onTap: onTap, child: child),
    );
  }

  /// The readable grid supports horizontal pan (R-21-037). Explicit overview fits its width.
  /// The background covers the display cutout, but cells use the unobscured viewport (R-21-039).
  /// One accessibility node contains every Host column (R-30-710).
  Widget _buildLiveGrid(
    BuildContext context,
    AppColor color, {
    bool interactive = true,
  }) {
    final terminal = widget.terminal;
    if (terminal == null) {
      return ColoredBox(
        color: _hostColor(widget.hostTheme?.value?.surfaceDim, color.bgBase),
      );
    }

    final behavior = ScrollConfiguration.of(context);
    final nativePhysics = behavior.getScrollPhysics(context);
    if (_nativeScrollPhysics != nativePhysics) {
      _nativeScrollPhysics = nativePhysics;
      _historyScrollPhysics = AlwaysScrollableScrollPhysics(
        parent: nativePhysics,
      );
    }
    // xterm's TerminalTheme has identity equality. Recreating it on each scroll
    // clears the glyph paragraph cache even when every colour is unchanged.
    final hostTheme = widget.hostTheme?.value;
    final themeKey = (color, hostTheme?.text, hostTheme?.surfaceDim);
    if (_themeKey != themeKey) {
      _themeKey = themeKey;
      _cachedTheme = terminalThemeFrom(color, hostTheme);
    }
    final theme = _cachedTheme!;
    final cutoutInset = _cutoutSafeInset(context);
    final label = _semanticsLabel(terminal);

    final terminalView = TerminalView(
      terminal,
      key: _terminalViewKey,
      controller: interactive ? _controller : null,
      theme: theme,
      // The readable size or the explicit overview fit reaches the painter.
      // Glyphs, pan offsets, and pointer-to-cell mappings share the measured
      // cell size. The line height stays fixed at the R-21-010 token.
      textStyle: TerminalStyle(
        fontSize: _fontSize,
        height: AppType.monoTerminal().height!,
        fontFamily: AppType.monoFontFamily,
        fontFamilyFallback: _fallbackFontFamilies,
      ),
      // R-21-038: both differ from the xterm2 default. autoResize
      // false keeps the emulator at rect.width, set from the
      // outside, never from this widget's own measured size.
      // textScaler noScaling keeps the cell advance off the system
      // text-scale setting.
      autoResize: false,
      textScaler: TextScaler.noScaling,
      padding: EdgeInsets.zero,
      scrollController: _verticalScroll,
      cursorType: TerminalCursorType.block,
      // R-31-08-08: a single tap on the grid MUST NOT send
      // anything to the pane. readOnly stops every keystroke this
      // widget could otherwise forward. The tap itself never reaches
      // `xterm2`: the selection adapter above it absorbs the pointer and its
      // tap reports through `_TerminalSelectionAdapter.onTap`.
      readOnly: true,
    );

    // The grid below the pan transform: the clipped, translated, overflowing
    // cell rectangle.
    final gridContent = ClipRect(
      child: Transform.translate(
        offset: Offset(-_horizontalOffsetColumns * _cellWidth, 0),
        // The grid box MUST be allowed to exceed the viewport: without
        // the OverflowBox the tight `Positioned.fill` constraint clamps
        // the child to the viewport width, and a panned window would
        // move the readout while the paint stayed clipped to the first
        // columns (observed 2026-09-08: the box measured 390 px for a
        // 144-column pane at an explicit size).
        child: OverflowBox(
          alignment: Alignment.topLeft,
          // Both bounds: `maxWidth` alone leaves the tight parent's
          // minimum in force, and a grid narrower than the viewport (a
          // small pane at an explicit size) would stretch to it instead
          // of measuring its real column count (observed 2026-09-08).
          minWidth: 0,
          maxWidth: double.infinity,
          child: SizedBox(
            // The pannable grid rectangle: exactly [Terminal.viewWidth]
            // cells of the painted width, so a test (and the e2e of
            // WP-25) can prove the first and the last Host column sit
            // inside the `terminalGridArea` viewport.
            key: const ValueKey('terminalGridCells'),
            width: _gridColumns * _cellWidth,
            // A finger drag on the grid dismisses the software keyboard, the
            // platform's own scroll-to-dismiss (iOS `keyboardDismissMode = .onDrag`,
            // Flutter's `ScrollViewKeyboardDismissBehavior.onDrag`). Only a drag with
            // pointer details counts: the widget's own `jumpTo`/`animateTo` and a
            // Host-driven resync raise no `dragDetails` and leave focus alone.
            child: NotificationListener<ScrollNotification>(
              onNotification: (ScrollNotification notification) {
                if (notification is ScrollStartNotification) {
                  _userScrollInProgress = notification.dragDetails != null;
                } else if (notification is ScrollEndNotification) {
                  _userScrollInProgress = false;
                }
                if (notification is ScrollStartNotification &&
                    notification.dragDetails != null) {
                  FocusManager.instance.primaryFocus?.unfocus();
                  _historyRequested = false;
                }
                final movingUp = switch (notification) {
                  ScrollUpdateNotification(:final scrollDelta) =>
                    (scrollDelta ?? 0) < 0,
                  OverscrollNotification(:final overscroll) => overscroll < 0,
                  _ => false,
                };
                if (movingUp &&
                    (_pinchPointers.length < 2 || _twoFingerScroll != null) &&
                    _userScrollInProgress &&
                    !_adjustingViewport &&
                    interactive &&
                    widget.phase == TerminalGridPhase.live &&
                    widget.maxScrollOffsetFromBottom > 0 &&
                    (!widget.historyVisible || widget.historyCanLoadMore) &&
                    !_historyRequested &&
                    notification.metrics.pixels <=
                        notification.metrics.viewportDimension) {
                  _historyRequested = true;
                  widget.onRequestScrollback?.call();
                }
                return false;
              },
              child: ScrollConfiguration(
                behavior: behavior.copyWith(
                  physics: widget.maxScrollOffsetFromBottom > 0
                      ? _historyScrollPhysics
                      : nativePhysics,
                ),
                child: terminalView,
              ),
            ),
          ),
        ),
      ),
    );

    // R-21-042: the live grid's selection is the platform's own. The SDK
    // `SelectionArea` draws the handles, magnifier and adaptive toolbar and
    // owns the long-press / handle-drag gestures; `_TerminalSelectionAdapter`
    // lies over the grid as the area's one leaf `Selectable`, absorbing the
    // pointer so `xterm2`'s own recognizers never join the arena, mapping the
    // events onto cells, and leaving the highlight to the painter. The area's
    // focus node never takes focus, so a long press never drops the
    // composer's keyboard. Both sit *above* the pan transform: the
    // `OverflowBox` hit-test rejects any touch whose translated position
    // lands outside its own bounds, so anything below the transform stops
    // seeing pointers once the pan passes one viewport.
    // The tree shape never changes with `interactive`: the `TerminalView`
    // keeps its slot under the area, so a phase flip never reparents its
    // GlobalKey; the adapter alone turns off. The area and the adapter wrap
    // the cutout padding itself: R-21-039's inset band above the first cell
    // row is grid background whose gestures (pan, force-read, tap) must work,
    // so the adapter covers it.
    final grid = SelectionArea(
      focusNode: _selectionFocusNode,
      child: Stack(
        children: [
          Padding(padding: cutoutInset, child: gridContent),
          Positioned.fill(
            child: _TerminalSelectionAdapter(
              leafKey: _selectionAdapterKey,
              enabled: interactive,
              terminal: terminal,
              controller: _controller,
              viewKey: _terminalViewKey,
              scroll: _verticalScroll,
              onEdgeDrag: _onSelectionEdgeDrag,
              onTap: () => widget.onGridTap?.call(),
              onMaybePan: (event) => _maybeStartPan(event, context),
              onVerticalDragStart: _onGridDragStart,
              onVerticalDragUpdate: _onGridDragUpdate,
              onVerticalDragEnd: _onGridDragEnd,
              onVerticalDragCancel: _onGridDragCancel,
            ),
          ),
        ],
      ),
    );

    return Listener(
      // R-21-039: the cutout-inset band above the first cell row is grid
      // background, and the grid's gestures accept it — `deferToChild`
      // would leave the band dead, because no child paints there.
      behavior: HitTestBehavior.opaque,
      onPointerDown: interactive
          ? (event) {
              _onPinchPointerDown(event);
              _onForceReadPointerDown(event, cutoutInset.top);
            }
          : null,
      onPointerMove: interactive
          ? (event) {
              _onPinchPointerMove(event);
              _onForceReadPointerMove(event);
            }
          : null,
      onPointerUp: interactive
          ? (event) {
              _onPinchPointerEnd(event.pointer);
              _onForceReadPointerEnd(event.pointer);
              _stopSelectionAutoscroll();
            }
          : null,
      onPointerCancel: interactive
          ? (event) {
              _onPinchPointerEnd(event.pointer);
              _onForceReadPointerEnd(event.pointer);
              _stopSelectionAutoscroll();
            }
          : null,
      child: Semantics(
        key: const ValueKey('terminalGridSemantics'),
        label: label,
        readOnly: true,
        multiline: true,
        container: true,
        explicitChildNodes: false,
        child: ExcludeSemantics(child: grid),
      ),
    );
  }

  /// R-21-039: the cell rectangle comes from `MediaQuery.paddingOf`, with
  /// every cutout `DisplayFeature` also accounted for — `paddingOf` alone
  /// is not guaranteed to already include every cutout's exact bounds on
  /// every platform build, so this file measures them independently and
  /// takes the larger of the two per edge. The grid *background* stays
  /// edge to edge; only this inset — applied to the cell rectangle above,
  /// never to the `ColoredBox` behind it — respects the cutout.
  EdgeInsets _cutoutSafeInset(BuildContext context) {
    var inset = MediaQuery.paddingOf(context);
    final size = MediaQuery.sizeOf(context);
    for (final feature in MediaQuery.displayFeaturesOf(context)) {
      if (feature.type != DisplayFeatureType.cutout) continue;
      final bounds = feature.bounds;
      inset = EdgeInsets.fromLTRB(
        bounds.left <= 0 ? _max(inset.left, bounds.right) : inset.left,
        bounds.top <= 0 ? _max(inset.top, bounds.bottom) : inset.top,
        bounds.right >= size.width
            ? _max(inset.right, size.width - bounds.left)
            : inset.right,
        bounds.bottom >= size.height
            ? _max(inset.bottom, size.height - bounds.top)
            : inset.bottom,
      );
    }
    return inset;
  }

  static double _max(double a, double b) => a > b ? a : b;

  /// R-31-08-06 and R-10-026: the pill appears only while the Device's own
  /// scroll offset is greater than zero, and a tap resumes the live
  /// follow.
  Widget _buildJumpToBottomPill(AppColor color) {
    return Positioned(
      bottom: AppSpace.space4,
      right: AppSpace.space4,
      child: _JumpToBottomPill(onTap: _jumpToBottom),
    );
  }

  Widget _buildTruncatedStrip(AppColor color) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: _buildStrip(
        color,
        onTap: () {
          setState(() => _truncatedDismissed = true);
          widget.onDismissTruncated?.call();
        },
        child: const Treatment.warning(
          label:
              'This is the most recent output. '
              'Older lines stay on the computer.',
        ),
      ),
    );
  }

  String _formatCaptureTime(DateTime time) {
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

void unawaited(Future<void> future) {}

/// The platform's tonal action returns the terminal to its live end.
class _JumpToBottomPill extends StatelessWidget {
  const _JumpToBottomPill({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChromeTonalButton(
    onPressed: onTap,
    icon: Symbols.vertical_align_bottom_rounded,
    child: const Text('to bottom'),
  );
}

/// The controller this widget creates when a caller passes none. `xterm2`'s
/// own gesture layer (its long-press, double/triple tap and mouse-drag
/// recognizers inside `TerminalGestureHandler`) writes straight to the
/// controller; the platform `SelectionArea` owns the selection now, so those
/// writes are dropped and only the adapter's writes land. `clearSelection`
/// stays open to everyone: `TerminalView` uses it for tap-to-clear, which is
/// exactly the platform's tap-clears-selection behaviour.
class _GridSelectionController extends TerminalController {
  bool _adapterWrite = false;

  @override
  void setSelection(CellAnchor base, CellAnchor extent, {SelectionMode? mode}) {
    if (!_adapterWrite) {
      // setSelection takes ownership of the anchors; a dropped write must
      // dispose them itself.
      base.dispose();
      extent.dispose();
      return;
    }
    super.setSelection(base, extent, mode: mode);
  }

  void setSelectionFromAdapter(CellAnchor base, CellAnchor extent) {
    _adapterWrite = true;
    try {
      super.setSelection(base, extent);
    } finally {
      _adapterWrite = false;
    }
  }
}

/// The adapter that bridges the live grid to the SDK `SelectionArea` wrapped
/// around it. It hit-tests *opaque* over the grid, so `xterm2`'s own gesture
/// recognizers (its long-press, double tap, tap) never join the gesture
/// arena: the arena closes when the pointer-down dispatch finishes, and
/// `xterm2`'s recognizers — added from the deeper `TerminalView` — would win
/// every long-press tie against the area's own, starving the platform
/// selection gestures. With the adapter absorbing the pointer, the area's
/// recognizers own the arena. The gestures the grid still needs are forwarded
/// here instead: the vertical drag drives the grid's own [ScrollController]
/// (the same `position.drag` path the two-finger scroll uses, so scroll
/// notifications, keyboard-on-drag dismissal and the history request all keep
/// working), the horizontal pan keeps its system-inset gate (R-21-040), and
/// the platform's tap collapse reports through [onTap] for R-31-08-08.
class _TerminalSelectionAdapter extends StatelessWidget {
  const _TerminalSelectionAdapter({
    required this.leafKey,
    required this.enabled,
    required this.terminal,
    required this.controller,
    required this.viewKey,
    required this.scroll,
    required this.onEdgeDrag,
    required this.onTap,
    required this.onMaybePan,
    required this.onVerticalDragStart,
    required this.onVerticalDragUpdate,
    required this.onVerticalDragEnd,
    required this.onVerticalDragCancel,
  });

  /// Reaches the leaf's render object (`_RenderTerminalSelection`) so the
  /// edge-autoscroll timer can re-apply the drag after each scroll step.
  final GlobalKey leafKey;

  /// False on the dimmed, non-live phases: no selection, no pan, no grid tap.
  /// The vertical scroll keeps working either way.
  final bool enabled;

  final Terminal terminal;
  final TerminalController controller;
  final GlobalKey<TerminalViewState> viewKey;
  final ScrollController scroll;

  /// Every selection-edge drag position, with `continuous` true for the SDK's
  /// per-frame handle-drag stream and false for one-shot long-press moves.
  final void Function(Offset globalPosition, {required bool continuous})
  onEdgeDrag;

  /// A tap on the grid collapsed or cleared the selection (R-31-08-08).
  final VoidCallback onTap;

  /// Starts the horizontal pan recognizer when the touch is outside the
  /// system gesture insets.
  final ValueChanged<PointerDownEvent> onMaybePan;

  final GestureDragStartCallback onVerticalDragStart;
  final GestureDragUpdateCallback onVerticalDragUpdate;
  final GestureDragEndCallback onVerticalDragEnd;
  final GestureDragCancelCallback onVerticalDragCancel;

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      gestures: <Type, GestureRecognizerFactory>{
        VerticalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<VerticalDragGestureRecognizer>(
              () => VerticalDragGestureRecognizer(debugOwner: this),
              (instance) {
                instance
                  ..onStart = onVerticalDragStart
                  ..onUpdate = onVerticalDragUpdate
                  ..onEnd = onVerticalDragEnd
                  ..onCancel = onVerticalDragCancel;
              },
            ),
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: enabled ? onMaybePan : null,
        child: _TerminalSelectionLeaf(
          key: leafKey,
          enabled: enabled,
          terminal: terminal,
          controller: controller,
          viewKey: viewKey,
          scroll: scroll,
          onEdgeDrag: onEdgeDrag,
          onTap: onTap,
        ),
      ),
    );
  }
}

/// The leaf whose render object is the area's one registered [Selectable].
/// It paints nothing itself — the selection highlight keeps painting through
/// the `TerminalController`, in the theme's `termSelection` colour.
class _TerminalSelectionLeaf extends LeafRenderObjectWidget {
  const _TerminalSelectionLeaf({
    super.key,
    required this.enabled,
    required this.terminal,
    required this.controller,
    required this.viewKey,
    required this.scroll,
    required this.onEdgeDrag,
    required this.onTap,
  });

  final bool enabled;
  final Terminal terminal;
  final TerminalController controller;
  final GlobalKey<TerminalViewState> viewKey;
  final ScrollController scroll;
  final void Function(Offset globalPosition, {required bool continuous})
  onEdgeDrag;
  final VoidCallback onTap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTerminalSelection(
        enabled: enabled,
        terminal: terminal,
        controller: controller,
        viewKey: viewKey,
        scroll: scroll,
        onEdgeDrag: onEdgeDrag,
        onTap: onTap,
        registrar: SelectionContainer.maybeOf(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderTerminalSelection renderObject,
  ) {
    renderObject
      ..enabled = enabled
      ..terminal = terminal
      ..controller = controller
      ..viewKey = viewKey
      ..scroll = scroll
      ..onEdgeDrag = onEdgeDrag
      ..onTap = onTap
      ..registrar = SelectionContainer.maybeOf(context);
  }
}

/// The one [Selectable] under the grid's `SelectionArea`. The controller's
/// selection is the single source of truth: events write it, geometry reads
/// it, so a selection set from anywhere (a drag, `Select all`, a test
/// seeding the controller directly) reports the same.
class _RenderTerminalSelection extends RenderBox
    with Selectable, SelectionRegistrant {
  _RenderTerminalSelection({
    required this._enabled,
    required this._terminal,
    required this._controller,
    required this._viewKey,
    required this._scroll,
    required this.onEdgeDrag,
    required this.onTap,
    required SelectionRegistrar? registrar,
  }) {
    this.registrar = registrar;
  }

  /// False on the dimmed, non-live phases: the selectable unregisters, so no
  /// selection event ever reaches it.
  bool get enabled => _enabled;
  bool _enabled;
  set enabled(bool value) {
    if (value == _enabled) return;
    _enabled = value;
    _onSourceChanged();
  }

  void Function(Offset globalPosition, {required bool continuous})? onEdgeDrag;

  /// A tap on the grid collapsed or cleared the selection (R-31-08-08).
  VoidCallback? onTap;

  Terminal get terminal => _terminal;
  Terminal _terminal;
  set terminal(Terminal value) {
    if (identical(value, _terminal)) return;
    if (attached) _terminal.removeListener(_onSourceChanged);
    _terminal = value;
    if (attached) _terminal.addListener(_onSourceChanged);
    _onSourceChanged();
  }

  TerminalController get controller => _controller;
  TerminalController _controller;
  set controller(TerminalController value) {
    if (identical(value, _controller)) return;
    if (attached) _controller.removeListener(_onSourceChanged);
    _controller = value;
    if (attached) _controller.addListener(_onSourceChanged);
    _onSourceChanged();
  }

  GlobalKey<TerminalViewState> get viewKey => _viewKey;
  GlobalKey<TerminalViewState> _viewKey;
  set viewKey(GlobalKey<TerminalViewState> value) {
    if (identical(value, _viewKey)) return;
    _viewKey = value;
    _onSourceChanged();
  }

  ScrollController get scroll => _scroll;
  ScrollController _scroll;
  set scroll(ScrollController value) {
    if (identical(value, _scroll)) return;
    if (attached) _scroll.removeListener(_onSourceChanged);
    _scroll = value;
    if (attached) _scroll.addListener(_onSourceChanged);
    _onSourceChanged();
  }

  // `RenderTerminal` is not exported by `xterm2`, so it is only ever a
  // local, inferred from `_viewKey.currentState!.renderTerminal`.

  // The word the last long press landed on; word-granularity edge drags keep
  // it fully selected, the native extend-by-word behaviour.
  CellOffset? _originStart;
  CellOffset? _originEnd;

  // The last edge event, re-applied by the widget's edge-autoscroll timer
  // after each scroll step (the long-press path, which the SDK sends once
  // per move rather than per frame).
  SelectionEdgeUpdateEvent? _lastEdgeEvent;

  // A start edge that arrived with no selection (a desktop mouse down): held
  // until the matching end edge moves it or collapses it away.
  CellOffset? _pendingStart;

  // The cell the immediately preceding start-edge update landed on. A tap
  // arrives as a start+end pair at one cell (the SDK's collapse); the end
  // half of the pair clears the selection and reports the tap.
  CellOffset? _collapseCandidate;

  final ObserverList<VoidCallback> _listeners = ObserverList<VoidCallback>();

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void _notifyListeners() {
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addListener(_onSourceChanged);
    _terminal.addListener(_onSourceChanged);
    _scroll.addListener(_onSourceChanged);
    // The registrant subscribes this selectable only while the geometry
    // reports hasContent, so the initial (selectionless) geometry must be
    // computed as soon as the sources are known.
    _updateGeometry();
  }

  @override
  void detach() {
    _controller.removeListener(_onSourceChanged);
    _terminal.removeListener(_onSourceChanged);
    _scroll.removeListener(_onSourceChanged);
    super.detach();
  }

  /// The selection, the scroll offset and the content all move the handles:
  /// every one of them funnels here.
  void _onSourceChanged() => _updateGeometry();

  @override
  void performLayout() {
    size = constraints.biggest;
  }

  // --- SelectionHandler -------------------------------------------------

  SelectionGeometry _geometry = const SelectionGeometry(
    status: SelectionStatus.none,
    hasContent: false,
  );

  @override
  SelectionGeometry get value => _geometry;

  @override
  int get contentLength => terminal.buffer.lines.length * (terminal.viewWidth + 1);

  @override
  List<Rect> get boundingBoxes => [paintBounds];

  @override
  SelectedContent? getSelectedContent() {
    final range = _controller.selectionFor(terminal.buffer);
    if (range == null || range.isCollapsed) return null;
    return SelectedContent(plainText: terminal.buffer.getText(range));
  }

  @override
  SelectedContentRange? getSelection() {
    final range = _controller.selectionFor(terminal.buffer);
    if (range == null || range.isCollapsed) return null;
    final line = terminal.viewWidth + 1;
    final normalized = range.normalized;
    return SelectedContentRange(
      startOffset: normalized.begin.y * line + normalized.begin.x,
      endOffset: normalized.end.y * line + normalized.end.x,
    );
  }

  void _updateGeometry() {
    if (!attached) return;
    final next = _computeGeometry();
    if (next == _geometry) return;
    _geometry = next;
    _notifyListeners();
    // The handle LeaderLayers bake the point offsets in at paint time.
    markNeedsPaint();
  }

  SelectionGeometry _computeGeometry() {
    const none = SelectionGeometry(
      status: SelectionStatus.none,
      hasContent: true,
    );
    if (!_enabled) {
      // Unregistered either way; hasContent false keeps the registrant from
      // subscribing this selectable at all.
      return const SelectionGeometry(
        status: SelectionStatus.none,
        hasContent: false,
      );
    }
    final render = _viewKey.currentState?.renderTerminal;
    if (render == null || !attached) return none;
    // A cell's caret point in this render object's local coordinates: the
    // render terminal's own mapping (scroll-compensated), re-expressed here.
    Offset toLocal(CellOffset cell) =>
        globalToLocal(render.localToGlobal(render.getOffset(cell)));
    final buffer = terminal.buffer;
    final range = _controller.selectionFor(buffer);
    // A collapsed selection is a tap's caret in editable text; the terminal
    // shows nothing for it.
    if (range == null || range.isCollapsed) return none;

    final cellSize = render.cellSize;
    final begin = range.begin;
    final end = range.end;
    final reversed = end.isBefore(begin);
    final first = reversed ? end : begin;
    final last = reversed ? begin : end;
    final width = terminal.viewWidth;
    final rects = <Rect>[];
    for (var row = first.y; row <= last.y; row++) {
      final leftCol = row == first.y ? first.x : 0;
      final rightCol = row == last.y ? last.x : width;
      if (rightCol <= leftCol) continue;
      final topLeft = toLocal(CellOffset(leftCol, row));
      rects.add(
        Rect.fromLTWH(
          topLeft.dx,
          topLeft.dy,
          (rightCol - leftCol) * cellSize.width,
          cellSize.height,
        ),
      );
    }
    // The SelectionPoint convention, from the SDK's RenderParagraph: the
    // point is the bottom-left of the caret at the edge.
    final startPoint = toLocal(begin) + Offset(0, cellSize.height);
    final endPoint = toLocal(end) + Offset(0, cellSize.height);
    final (startHandle, endHandle) = reversed
        ? (TextSelectionHandleType.right, TextSelectionHandleType.left)
        : (TextSelectionHandleType.left, TextSelectionHandleType.right);
    return SelectionGeometry(
      startSelectionPoint: SelectionPoint(
        localPosition: startPoint,
        lineHeight: cellSize.height,
        handleType: startHandle,
      ),
      endSelectionPoint: SelectionPoint(
        localPosition: endPoint,
        lineHeight: cellSize.height,
        handleType: endHandle,
      ),
      selectionRects: rects,
      status: SelectionStatus.uncollapsed,
      hasContent: true,
    );
  }

  // --- Selection events ---------------------------------------------------

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    switch (event) {
      case final SelectionEdgeUpdateEvent edge:
        return _handleEdgeUpdate(edge);
      case final SelectWordSelectionEvent selectWord:
        return _handleSelectWord(selectWord.globalPosition);
      case final SelectParagraphSelectionEvent selectParagraph:
        return _handleSelectParagraph(selectParagraph.globalPosition);
      case SelectAllSelectionEvent():
        _clearDragState();
        _writeSelection(
          const CellOffset(0, 0),
          CellOffset(terminal.viewWidth, terminal.buffer.lines.length - 1),
        );
        return SelectionResult.none;
      case ClearSelectionEvent():
        _clearDragState();
        _controller.clearSelection();
        return SelectionResult.none;
      case final GranularlyExtendSelectionEvent extend:
        return _handleGranularlyExtend(extend);
      case DirectionallyExtendSelectionEvent():
        // Keyboard line/caret movement: not meaningful on a cell grid.
        return SelectionResult.end;
    }
    return SelectionResult.none;
  }

  void _clearDragState() {
    _originStart = null;
    _originEnd = null;
    _lastEdgeEvent = null;
    _pendingStart = null;
    _collapseCandidate = null;
  }

  /// Re-applies the last edge event after an autoscroll step: the scroll
  /// moved the grid, so the same pointer position is a new cell now.
  void reapplyEdgeDrag() {
    final event = _lastEdgeEvent;
    if (event == null || !attached) return;
    dispatchSelectionEvent(event);
  }

  SelectionResult _handleSelectWord(Offset globalPosition) {
    final render = _viewKey.currentState?.renderTerminal;
    if (render == null) return SelectionResult.end;
    final cell = render.getCellOffset(render.globalToLocal(globalPosition));
    final word = terminal.buffer.getWordBoundary(cell);
    // A long press on blank padding selects nothing, matching the old
    // recognizer and `xterm2`'s own selectWord.
    if (word == null) return SelectionResult.end;
    _lastEdgeEvent = null;
    _originStart = word.begin;
    _originEnd = word.end;
    _writeSelection(word.begin, word.end);
    return SelectionResult.end;
  }

  SelectionResult _handleSelectParagraph(Offset globalPosition) {
    final render = _viewKey.currentState?.renderTerminal;
    if (render == null) return SelectionResult.end;
    final cell = render.getCellOffset(render.globalToLocal(globalPosition));
    final line = terminal.buffer.getLineBoundary(cell);
    if (line == null) return SelectionResult.end;
    _clearDragState();
    _writeSelection(line.begin, line.end);
    return SelectionResult.end;
  }

  SelectionResult _handleEdgeUpdate(SelectionEdgeUpdateEvent event) {
    final render = _viewKey.currentState?.renderTerminal;
    if (render == null) return SelectionResult.end;
    final isEnd = event.type == SelectionEventType.endEdgeUpdate;
    final granularity = event.granularity;
    final local = render.globalToLocal(event.globalPosition);
    final cell = render.getCellOffset(local);
    final buffer = terminal.buffer;
    final current = _controller.selectionFor(buffer);
    if (granularity != TextGranularity.word) _clearGranularOriginOnly();
    _lastEdgeEvent = event;

    switch (granularity) {
      case TextGranularity.word:
        // The long-press drag. The word the press landed on stays fully
        // selected; the dragged edge snaps to the word under the pointer.
        if (current == null) return SelectionResult.end;
        final word = buffer.getWordBoundary(cell);
        final wordStart = word?.begin ?? cell;
        final wordEnd = word?.end ?? CellOffset(cell.x + 1, cell.y);
        final originStart = _originStart ?? current.normalized.begin;
        final originEnd = _originEnd ?? current.normalized.end;
        if (isEnd) {
          if (cell.isBefore(originStart)) {
            _writeSelection(originEnd, wordStart);
          } else {
            _writeSelection(originStart, wordEnd);
          }
        } else {
          if (cell.isAfter(originEnd)) {
            _writeSelection(wordEnd, originStart);
          } else {
            _writeSelection(wordStart, originEnd);
          }
        }
      default:
        // The cell under the handle is inside the selection: the end edge is
        // exclusive, so it sits one cell past it.
        if (isEnd) {
          final candidate = _collapseCandidate;
          _collapseCandidate = null;
          if (current == null) {
            final pending = _pendingStart;
            if (pending == null) return SelectionResult.end;
            _pendingStart = null;
            if (pending == cell) {
              // The second half of a tap's collapse pair.
              _controller.clearSelection();
              onTap?.call();
              return SelectionResult.end;
            }
            _writeSelection(pending, CellOffset(cell.x + 1, cell.y));
          } else if (candidate != null && candidate == cell) {
            // A tap with a selection live: the collapse pair clears it, and
            // the tap itself still counts as the grid tap (R-31-08-08).
            _controller.clearSelection();
            onTap?.call();
          } else {
            _writeSelection(current.begin, CellOffset(cell.x + 1, cell.y));
          }
        } else {
          if (current == null) {
            // A mouse down ahead of its drag: hold the edge until the end
            // edge arrives.
            _pendingStart = cell;
          } else {
            _writeSelection(cell, current.end);
          }
          _collapseCandidate = cell;
        }
    }

    onEdgeDrag?.call(
      event.globalPosition,
      continuous: granularity != TextGranularity.word,
    );
    // The continuous handle-drag stream re-sends the event every frame while
    // the result is pending, which is what drives the edge autoscroll.
    final beyond =
        local.dy < AppSize.targetMin ||
        local.dy > render.size.height - AppSize.targetMin;
    if (beyond && granularity != TextGranularity.word) {
      return SelectionResult.pending;
    }
    return SelectionResult.end;
  }

  void _clearGranularOriginOnly() {
    _originStart = null;
    _originEnd = null;
  }

  SelectionResult _handleGranularlyExtend(GranularlyExtendSelectionEvent event) {
    final buffer = terminal.buffer;
    final current = _controller.selectionFor(buffer);
    if (current == null) return SelectionResult.end;
    final width = terminal.viewWidth;
    final lastRow = buffer.lines.length - 1;
    final edge = event.isEnd ? current.end : current.begin;
    final CellOffset target = switch (event.granularity) {
      TextGranularity.character => _stepCell(edge, event.forward, width, lastRow),
      TextGranularity.word => _stepWord(buffer, edge, event.forward, width, lastRow),
      TextGranularity.line ||
      TextGranularity.paragraph => event.forward
          ? CellOffset(width, edge.y)
          : CellOffset(0, edge.y),
      TextGranularity.document => event.forward
          ? CellOffset(width, lastRow)
          : const CellOffset(0, 0),
    };
    if (event.isEnd) {
      _writeSelection(current.begin, target);
    } else {
      _writeSelection(target, current.end);
    }
    return SelectionResult.end;
  }

  CellOffset _stepCell(CellOffset cell, bool forward, int width, int lastRow) {
    if (forward) {
      if (cell.x >= width) {
        return cell.y >= lastRow ? CellOffset(width, lastRow) : CellOffset(0, cell.y + 1);
      }
      return CellOffset(cell.x + 1, cell.y);
    }
    if (cell.x <= 0) {
      return cell.y <= 0 ? const CellOffset(0, 0) : CellOffset(width, cell.y - 1);
    }
    return CellOffset(cell.x - 1, cell.y);
  }

  CellOffset _stepWord(
    Buffer buffer,
    CellOffset edge,
    bool forward,
    int width,
    int lastRow,
  ) {
    final probe = forward
        ? _stepCell(edge, true, width, lastRow)
        : _stepCell(edge, false, width, lastRow);
    final word = buffer.getWordBoundary(probe);
    if (word == null) return probe;
    return forward ? word.end : word.begin;
  }

  void _writeSelection(CellOffset begin, CellOffset end) {
    final buffer = terminal.buffer;
    final current = _controller.selectionFor(buffer);
    if (current != null &&
        current.begin.isEqual(begin) &&
        current.end.isEqual(end)) {
      return;
    }
    final controller = _controller;
    if (controller is _GridSelectionController) {
      controller.setSelectionFromAdapter(
        buffer.createAnchorFromOffset(begin),
        buffer.createAnchorFromOffset(end),
      );
    } else {
      controller.setSelection(
        buffer.createAnchorFromOffset(begin),
        buffer.createAnchorFromOffset(end),
      );
    }
  }

  // --- Handle layers --------------------------------------------------------

  LayerLink? _startHandleLayerLink;
  LayerLink? _endHandleLayerLink;

  @override
  void pushHandleLayers(LayerLink? startHandle, LayerLink? endHandle) {
    if (identical(startHandle, _startHandleLayerLink) &&
        identical(endHandle, _endHandleLayerLink)) {
      return;
    }
    _startHandleLayerLink = startHandle;
    _endHandleLayerLink = endHandle;
    // The registrar withdraws the layers while the tree is being torn down.
    if (attached) markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final startLink = _startHandleLayerLink;
    final startPoint = _geometry.startSelectionPoint;
    if (startLink != null && startPoint != null) {
      context.pushLayer(
        LeaderLayer(link: startLink, offset: offset + startPoint.localPosition),
        (context, offset) {},
        Offset.zero,
      );
    }
    final endLink = _endHandleLayerLink;
    final endPoint = _geometry.endSelectionPoint;
    if (endLink != null && endPoint != null) {
      context.pushLayer(
        LeaderLayer(link: endLink, offset: offset + endPoint.localPosition),
        (context, offset) {},
        Offset.zero,
      );
    }
  }
}
