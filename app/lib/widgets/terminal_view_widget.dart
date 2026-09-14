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
/// [TerminalViewWidget.textSize], including the default 13 logical pixels. Only explicit
/// [TerminalViewWidget.overview] shrinks cells until every Host column fits (R-21-008, latest correction 2026-09-08).
/// Both modes adopt the render object's exact cell metrics. A wide readable grid supports pan.
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
/// draws, not this file) — this file tracks them as its own scroll and selection state and layers
/// the jump-to-bottom pill (R-31-08-06, `R-90-010`) and the selection toolbar (R-21-042) over
/// whatever phase is showing. `landscape` is not a phase either: the grid never changes its column
/// count for orientation (R-21-036), so this file's only landscape-specific duty is to keep every
/// offset stable across the rotation (R-31-08-10), which the same state fields that survive an app
/// background and resume already provide.
library;

import 'dart:async' show Timer;
import 'dart:ui'
    show DisplayFeatureType, ParagraphBuilder, ParagraphConstraints;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart'
    show
        HorizontalDragGestureRecognizer,
        LongPressGestureRecognizer,
        LongPressMoveUpdateDetails,
        LongPressStartDetails;
import 'package:flutter/material.dart'
    show
        AdaptiveTextSelectionToolbar,
        ContextMenuButtonItem,
        ContextMenuButtonType;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';

import 'package:material_symbols_icons/symbols.dart';
import 'package:xterm2/xterm.dart'
    show
        CellOffset,
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
import 'theme/app_pressable.dart';
import 'theme/app_radius.dart';
import 'theme/app_size.dart';
import 'theme/app_space.dart';
import 'theme/app_type.dart';
import 'theme/chrome_gesture_timing.dart';
import 'theme/chrome_loading_delay.dart';
import 'treatments.dart';

/// `opacity.dim`, per `docs/32-design-language.md` section 5.4's opacity
/// table: "the last painted grid in every non-live state". Every opacity
/// value outside `elev.*` stays a local constant beside its one caller, per
/// the precedent `app/lib/widgets/app_filled_button.dart` (`WP-12-a`) set
/// for `opacity.disabled`.
const double _opacityDim = 0.60;

/// R-30-302's pinch thresholds: the terminal text size steps up the
/// R-21-010 ladder when the gesture's scale passes 1.15, and down when it
/// passes 0.87. The gesture never lands between ladder sizes.
const double _pinchUpThreshold = 1.15;
const double _pinchDownThreshold = 0.87;

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
/// measurement. The first layout of a fit or a size step sizes the grid
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
    this.revision,
    this.hostName,
    this.captureTime,
    this.reconnectAttempt,
    this.errorText,
    this.truncatedAtTop = false,
    this.maxScrollOffsetFromBottom = 0,
    this.onGridTap,
    this.onDismissTruncated,
    this.onDiagnostics,
    this.onRevoked,
    this.onSelectionLiveChanged,
    this.onScrollOffsetChanged,
    this.onVisibleColumnsChanged,
    this.onPinchSizeStep,
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

  /// Fires when a two-finger pinch crosses one of R-30-302's thresholds:
  /// `true` for one step up the R-21-010 ladder, `false` for one step
  /// down. This file owns no ladder: the caller holds the current size,
  /// steps it, fires `haptic.select`, and rebuilds this widget with the
  /// new [textSize] — a pinch moves the text size, never the column
  /// count (R-21-008).
  final ValueChanged<bool>? onPinchSizeStep;

  /// Fires on the force-read gesture of `docs/30-ux-spec.md`'s gesture
  /// table: a pull down that starts at the top of the grid while the
  /// Device's own scroll offset is at the live bottom. A caller wires
  /// this to `TerminalService.requestScrollback` (R-11-053). This widget
  /// sends nothing itself (R-30-300).
  final VoidCallback? onForceRead;

  @override
  State<TerminalViewWidget> createState() => _TerminalViewWidgetState();
}

class _TerminalViewWidgetState extends State<TerminalViewWidget> {
  // Keep the reader's horizontal position and vertical intent across rebuilds and rotation.
  double _horizontalOffsetColumns = 0;
  double _verticalOffsetFromBottom = 0;
  double _viewportTopRows = 0;
  int _liveContentRows = 1;
  bool _terminalContentDirty = true;
  bool _adjustingViewport = false;

  late final ScrollController _verticalScroll;
  late final TerminalController _controller;
  bool _ownsController = false;

  bool _showFirstPaintLine = false;
  Timer? _firstPaintTimer;

  HorizontalDragGestureRecognizer? _panRecognizer;
  double _viewportColumns = 0;

  /// The readable [TerminalViewWidget.textSize], or the corrected fit size in overview.
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
  (double, int, int, bool)? _fitKey;
  double _lastAvailableWidth = 0;
  int _fitCorrections = 0;
  bool _metricsAdoptionScheduled = false;

  // The pinch's two tracked pointers, read straight off the `Listener`:
  // a `ScaleGestureRecognizer` shares the gesture arena with `xterm2`'s
  // own tap, long-press and scroll recognizers plus this file's pan
  // recognizer, and in that arena it never reaches its scale slop, so
  // the pinch is tracked here without entering the arena at all — the
  // same pattern the force-read pull uses below. R-30-303: a third
  // pointer keeps the gesture unbound.
  final Map<int, Offset> _pinchPointers = <int, Offset>{};
  double? _pinchStartSpan;

  /// The scale value at which the last pinch step fired, so one gesture
  /// can step the R-21-010 ladder more than once (R-30-302). Reset to 1
  /// when the second pointer lands.
  double _pinchReferenceScale = 1;

  // The force-read pull's one tracked pointer: a second finger never
  // joins this gesture (R-30-303 leaves multi-finger unbound beyond the
  // pinch).
  int? _forceReadPointer;
  double _forceReadStartDy = 0;
  bool _forceReadFired = false;

  ({int first, int last})? _reportedWindow;
  bool _windowReportScheduled = false;

  // R-30-301: xterm2's own internal long-press recognizer for
  // select-a-word uses the Flutter SDK default (500 ms), which this rule
  // forbids. This ancestor recognizer wins the gesture arena first, at
  // the correct 400 ms, so xterm2's own (slower) internal one never
  // fires — then drives xterm2's own public `RenderTerminal.selectWord`
  // through `_terminalViewKey`, reusing its real word-boundary and
  // selection logic rather than reimplementing it.
  final GlobalKey<TerminalViewState> _terminalViewKey =
      GlobalKey<TerminalViewState>();
  LongPressGestureRecognizer? _longPressRecognizer;
  Offset? _lastLongPressStart;

  @override
  void initState() {
    super.initState();
    _verticalScroll = ScrollController()..addListener(_onVerticalScroll);
    _controller = widget.controller ?? TerminalController();
    _ownsController = widget.controller == null;
    _controller.addListener(_onControllerChanged);
    widget.terminal?.addListener(_onTerminalContentChanged);
    _scheduleFirstPaintLine();
    _maybeFireRevoked();
  }

  @override
  void didUpdateWidget(TerminalViewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.terminal != widget.terminal) {
      oldWidget.terminal?.removeListener(_onTerminalContentChanged);
      widget.terminal?.addListener(_onTerminalContentChanged);
      _onTerminalContentChanged();
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerChanged);
      if (_ownsController) _controller.dispose();
      _controller = widget.controller ?? TerminalController();
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
    widget.terminal?.removeListener(_onTerminalContentChanged);
    _verticalScroll
      ..removeListener(_onVerticalScroll)
      ..dispose();
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) _controller.dispose();
    _panRecognizer?.dispose();
    _longPressRecognizer?.dispose();
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
    final double offset = (_liveBottom - position.pixels).clamp(
      0.0,
      double.infinity,
    );
    if (offset == _verticalOffsetFromBottom) return;
    setState(() => _verticalOffsetFromBottom = offset);
    widget.onScrollOffsetChanged?.call((offset / _cellHeight).round());
  }

  void _onTerminalContentChanged() {
    _terminalContentDirty = true;
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
    final position = _verticalScroll.position;
    if (!position.hasContentDimensions) return;
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
  }

  void _onControllerChanged() {
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
    final dx = event.localPosition.dx;
    if (dx < insets.left || dx > width - insets.right) return;
    (_panRecognizer ??= HorizontalDragGestureRecognizer(debugOwner: this))
      ..onUpdate = _onPanUpdate
      ..addPointer(event);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _horizontalOffsetColumns -= details.delta.dx / _cellWidth;
      _clampHorizontalOffset();
    });
  }

  /// R-30-302: one step per threshold crossing, re-baselined at each
  /// crossing so a long pinch walks the ladder; the size itself is the
  /// caller's state (this widget never holds it past [textSize]). The
  /// span is the distance between the two tracked pointers.
  void _onPinchMove() {
    final callback = widget.onPinchSizeStep;
    final start = _pinchStartSpan;
    if (callback == null || start == null || _pinchPointers.length != 2) {
      return;
    }
    final points = _pinchPointers.values.toList();
    final double span = (points[0] - points[1]).distance;
    if (span <= 0) return;
    final double scale = span / start;
    if (scale > _pinchReferenceScale * _pinchUpThreshold) {
      _pinchReferenceScale = scale;
      callback(true);
    } else if (scale < _pinchReferenceScale * _pinchDownThreshold) {
      _pinchReferenceScale = scale;
      callback(false);
    }
  }

  void _onPinchPointerDown(PointerDownEvent event) {
    if (widget.onPinchSizeStep == null) return;
    _pinchPointers[event.pointer] = event.localPosition;
    if (_pinchPointers.length == 2) {
      final points = _pinchPointers.values.toList();
      _pinchStartSpan = (points[0] - points[1]).distance;
      _pinchReferenceScale = 1;
    }
  }

  void _onPinchPointerMove(PointerMoveEvent event) {
    if (!_pinchPointers.containsKey(event.pointer)) return;
    _pinchPointers[event.pointer] = event.localPosition;
    _onPinchMove();
  }

  void _onPinchPointerEnd(int pointer) {
    if (_pinchPointers.remove(pointer) != null && _pinchPointers.length < 2) {
      _pinchStartSpan = null;
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

  /// R-30-301: the long press that starts a free selection MUST be
  /// 400 ms. `xterm2`'s own internal `LongPressGestureRecognizer` (its
  /// selection gesture) uses the Flutter SDK default (`kLongPressTimeout`,
  /// 500 ms) with no public override point, so this ancestor recognizer
  /// wins the gesture arena first, at the correct duration — Flutter
  /// resolves a `LongPressGestureRecognizer` arena in favour of whichever
  /// competing recognizer's timer fires first, so `xterm2`'s slower one
  /// is rejected before it ever calls its own selection code.
  void _maybeStartLongPress(PointerDownEvent event) {
    (_longPressRecognizer ??= LongPressGestureRecognizer(
        debugOwner: this,
        duration: ChromeGestureTiming.longPress,
      ))
      ..onLongPressStart = _onLongPressStart
      ..onLongPressMoveUpdate = _onLongPressMoveUpdate
      ..addPointer(event);
  }

  /// Selects the word under the long press through `xterm2`'s own public
  /// `RenderTerminal.selectWord` (reached via [_terminalViewKey]) — this
  /// file never reimplements word-boundary detection.
  void _onLongPressStart(LongPressStartDetails details) {
    _lastLongPressStart = details.localPosition;
    _terminalViewKey.currentState?.renderTerminal.selectWord(
      details.localPosition,
    );
  }

  /// Extends the same selection as the press moves, matching `xterm2`'s
  /// own long-press-then-drag behaviour (`docs/30-ux-spec.md`'s gesture
  /// table, "Start a free selection").
  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    final start = _lastLongPressStart;
    if (start == null) return;
    _terminalViewKey.currentState?.renderTerminal.selectWord(
      start,
      details.localPosition,
    );
  }

  /// R-30-730: under reduced motion every `motion.duration.*` becomes 0 ms
  /// and every `motion.curve.*` becomes linear — an instant swap, not a
  /// perceptible scroll.
  void _jumpToBottom() {
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

  Future<void> _copySelection() async {
    final terminal = widget.terminal;
    final range = _controller.selectionFor(terminal!.buffer);
    if (range == null) return;
    final text = terminal.buffer.getText(range);
    await Clipboard.setData(ClipboardData(text: text));
    _controller.clearSelection();
  }

  void _selectVisibleScreen() {
    final terminal = widget.terminal;
    if (terminal == null) return;
    final double pixels = _verticalScroll.hasClients
        ? _verticalScroll.position.pixels
        : 0.0;
    final top = (pixels / _cellHeight).round();
    final base = terminal.buffer.createAnchorFromOffset(CellOffset(0, top));
    final extent = terminal.buffer.createAnchorFromOffset(
      CellOffset(terminal.viewWidth - 1, top + terminal.viewHeight - 1),
    );
    _controller.setSelection(base, extent);
  }

  /// The grid's one semantics node, per R-30-710 and R-30-711: the visible
  /// screen as plain text, trailing spaces stripped per line, empty lines
  /// collapsed to one. Built at the terminal's own full width, never
  /// clipped to the columns the pan window currently shows, because a
  /// screen reader cannot pan (R-21-037 point 4).
  String _semanticsLabel(Terminal terminal) {
    final rawLines = terminal.buffer.getText().split('\n');
    final trimmed = rawLines.map((line) => line.replaceAll(RegExp(r' +$'), ''));
    final collapsed = <String>[];
    for (final line in trimmed) {
      if (line.isEmpty && collapsed.isNotEmpty && collapsed.last.isEmpty) {
        continue;
      }
      collapsed.add(line);
    }
    return collapsed.join('\n');
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
        // Recompute the candidate only when an input moved; the adopted
        // painted cell and any taken correction survive untouched
        // rebuilds, so the metrics never oscillate under setState.
        final fitKey = (
          availableWidth,
          _gridColumns,
          widget.textSize,
          widget.overview,
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
                if (_hasSelection && widget.terminal != null)
                  _buildSelectionToolbar(context, color),
                if (widget.truncatedAtTop) _buildTruncatedStrip(color),
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
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.bgRaised,
          border: Border.symmetric(
            horizontal: BorderSide(color: color.borderSubtle),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpace.space3,
            horizontal: AppSpace.space4,
          ),
          child: child,
        ),
      ),
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

    final theme = terminalThemeFrom(color, widget.hostTheme?.value);
    final cutoutInset = _cutoutSafeInset(context);
    final label = _semanticsLabel(terminal);

    final grid = Padding(
      padding: cutoutInset,
      child: ClipRect(
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
              child: TerminalView(
                terminal,
                key: _terminalViewKey,
                controller: interactive ? _controller : null,
                theme: theme,
                // The readable size or the explicit overview fit reaches the painter.
                // Glyphs, pan offsets, and pointer-to-cell mappings share the measured cell size.
                // The line height stays fixed at the R-21-010 token.
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
                // widget could otherwise forward.
                readOnly: true,
                onTapUp: interactive
                    ? (_, _) => widget.onGridTap?.call()
                    : null,
              ),
            ),
          ),
        ),
      ),
    );

    return Listener(
      // R-21-039: the cutout-inset band above the first cell row is grid
      // background, and the grid's gestures accept it — `deferToChild`
      // would leave the band dead, because no child paints there.
      behavior: HitTestBehavior.opaque,
      onPointerDown: interactive
          ? (event) {
              _maybeStartPan(event, context);
              _maybeStartLongPress(event);
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
            }
          : null,
      onPointerCancel: interactive
          ? (event) {
              _onPinchPointerEnd(event.pointer);
              _onForceReadPointerEnd(event.pointer);
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
      child: _JumpToBottomPill(color: color, onTap: _jumpToBottom),
    );
  }

  Widget _buildTruncatedStrip(AppColor color) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: _buildStrip(
        color,
        onTap: widget.onDismissTruncated,
        child: const Treatment.warning(
          label:
              'This is the most recent output. '
              'Older lines stay on the computer.',
        ),
      ),
    );
  }

  /// R-21-042: the platform's own selection surface, built from
  /// `AdaptiveTextSelectionToolbar.buttonItems` with exactly `Copy` and
  /// `Select visible screen` — no second bar, bottom bar or app-bar action
  /// repeats either command.
  Widget _buildSelectionToolbar(BuildContext context, AppColor color) {
    final anchor = _selectionAnchor(context);
    return Positioned.fill(
      child: AdaptiveTextSelectionToolbar.buttonItems(
        anchors: TextSelectionToolbarAnchors(primaryAnchor: anchor),
        buttonItems: <ContextMenuButtonItem>[
          ContextMenuButtonItem(
            onPressed: () => unawaited(_copySelection()),
            type: ContextMenuButtonType.copy,
            label: 'Copy',
          ),
          ContextMenuButtonItem(
            onPressed: _selectVisibleScreen,
            label: 'Select visible screen',
          ),
        ],
      ),
    );
  }

  /// The selection's top-left cell, in pixels, above the grid's own
  /// transform. ponytail: a single fixed anchor above the selection start,
  /// not a full above-or-below-keyboard placement search; upgrade if a
  /// selection near the top edge is found to clip off screen.
  Offset _selectionAnchor(BuildContext context) {
    final terminal = widget.terminal;
    final range = terminal == null
        ? null
        : _controller.selectionFor(terminal.buffer);
    final row = range?.begin.y ?? 0;
    final col = range?.begin.x ?? 0;
    return Offset(
      (col - _horizontalOffsetColumns) * _cellWidth,
      row * _cellHeight,
    );
  }

  String _formatCaptureTime(DateTime time) {
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

void unawaited(Future<void> future) {}

/// The jump-to-bottom pill of R-32-540's anatomy: `size.pill` high inside a
/// `size.target.min` target, `color.bg.high` under a `color.border.strong`
/// hairline at `radius.full`, the `vertical_align_bottom` glyph and
/// `type.label`, `space.3` horizontal padding. The target stands above the
/// pill, so the pill itself stays `space.4` above the strip. It composes
/// `AppPressable` like every other button: pressed, per R-32-501's first
/// case, `color.accent.primary` with the glyph and the label in
/// `color.fg.on_accent`, on the press scale of R-32-609.
class _JumpToBottomPill extends StatelessWidget {
  const _JumpToBottomPill({required this.color, required this.onTap});

  final AppColor color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: onTap,
      radius: AppRadius.full,
      builder: (BuildContext context, bool pressed) {
        final Color ink = pressed ? color.fgOnAccent : color.fgPrimary;
        return SizedBox(
          height: AppSize.targetMin,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedContainer(
              duration: AppPressable.fillDuration(context, pressed),
              curve: AppPressable.fillCurve(context),
              height: AppSize.pill,
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.space3),
              decoration: BoxDecoration(
                color: pressed ? color.accentPrimary : color.bgHigh,
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(
                  color: pressed ? color.accentPrimary : color.borderStrong,
                  width: AppBorder.hairline,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    // R-32-540: `vertical_align_bottom`, "to the end",
                    // never a bare downward arrow.
                    Symbols.vertical_align_bottom_rounded,
                    size: AppSize.iconMd,
                    color: ink,
                    fill: 0,
                    weight: 400,
                    grade: 0,
                  ),
                  const SizedBox(width: AppSpace.space1),
                  Text('to bottom', style: AppType.label.copyWith(color: ink)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
