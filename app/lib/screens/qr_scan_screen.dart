/// The QR pairing scanner, per `docs/90-implementation-plan.md` `WP-15-b` and
/// `docs/31-mockups/02-pair-scan.md` (R-90-010, R-90-011).
///
/// [QrScanScreenBody] is the pure, stateless presentation of one named state, mirroring
/// `lock_screen.dart`'s split: it takes every value it paints as a constructor argument and
/// calls nothing. [QrScanScreen] is the stateful orchestrator: it owns a [PairingScanner]
/// (`WP-15-a`), the EFF word list, connectivity, and the pairing handshake itself
/// (`attemptPairing`/`persistPairing`), and renders [QrScanScreenBody] for whatever it finds.
///
/// This file requests the camera permission implicitly, by calling
/// `PairingScanner.controller.start()` only once this route is mounted and never earlier
/// (R-31-02-01): `mobile_scanner`'s own `start()` is what raises the platform permission
/// prompt (`mobile_scanner_controller.dart`'s own doc comment: "Upon calling this method, the
/// necessary camera permission will be requested"), so no separate rationale dialog sits in
/// front of it — `docs/31-mockups/02-pair-scan.md`'s own states table draws none, and
/// `R-31-02-01` names no such step; `docs/22-platform-integration.md` §5.2's general
/// "with a rationale dialog" phrasing is platform-integration boilerplate, not a screen-level
/// requirement this mockup repeats.
///
/// A successful handshake shows the Host fingerprint in place, satisfying R-13-041's "the
/// Device displays the Host fingerprint on the pairing confirmation screen" the way WP-15-b's
/// own one-line description names it ("the welcome screen, the QR scanner and the
/// confirmation") — this file's only owned surface that could be "the confirmation". See
/// `## 8. Blocked work` item B17 for the part of R-13-041 this file cannot close alone (a
/// real per-Host route to land on next does not exist before `docs/90` Phase 18).
library;

import 'dart:async' show StreamSubscription, unawaited;
import 'dart:ui'
    show
        Canvas,
        ClipOp,
        Color,
        Offset,
        Paint,
        PaintingStyle,
        Path,
        Rect,
        Size,
        StrokeCap,
        StrokeJoin;

import 'package:connectivity_plus/connectivity_plus.dart'
    show Connectivity, ConnectivityResult;
import 'package:cupertino_ui/cupertino_ui.dart'
    show Border, BorderSide, CupertinoNavigationBar, CupertinoPageScaffold;
import 'package:device_info_plus/device_info_plus.dart' show DeviceInfoPlugin;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:flutter/widgets.dart'
    show
        AnimatedBuilder,
        AnimationController,
        AppLifecycleState,
        BorderRadius,
        BoxDecoration,
        BuildContext,
        Center,
        Column,
        Container,
        CrossAxisAlignment,
        CustomPaint,
        HitTestBehavior,
        IgnorePointer,
        CustomPainter,
        EdgeInsets,
        ExcludeSemantics,
        GestureDetector,
        Expanded,
        LayoutBuilder,
        MainAxisSize,
        MediaQuery,
        Navigator,
        Padding,
        PositionedDirectional,
        Radius,
        Row,
        SafeArea,
        Semantics,
        SingleTickerProviderStateMixin,
        SizedBox,
        Stack,
        StackFit,
        State,
        StatefulWidget,
        StatelessWidget,
        Text,
        VoidCallback,
        Widget,
        WidgetsBinding,
        WidgetsBindingObserver;
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart'
    show
        AppBar,
        Colors,
        Material,
        PreferredSize,
        RoundedRectangleBorder,
        Scaffold,
        showModalBottomSheet;
import 'package:mobile_scanner/mobile_scanner.dart'
    show
        BarcodeFormat,
        MobileScanner,
        MobileScannerController,
        MobileScannerErrorCode,
        MobileScannerException,
        TorchState;
import 'package:package_info_plus/package_info_plus.dart' show PackageInfo;

import '../core/result/result.dart' show Err, Ok, Result;
import '../models/frame.dart' show frameProtocolVersion;
import '../models/messages/device_info.dart' as messages show DeviceInfo;
import '../models/messages/platform.dart' as messages show Platform;
import '../services/biometric_gate.dart';
import '../services/camera_zoom.dart';
import '../services/keystore.dart' show KeystoreService;
import '../services/origin.dart'
    show RelayOriginErrorCode, RelayOriginException;
import '../services/pairing.dart';
import '../services/pairing_failure.dart';
import '../services/plain_store.dart' show PlainStore;
import '../services/relay.dart';
import '../widgets/app_filled_button.dart';
import '../widgets/app_text_button.dart';
import '../widgets/eyebrow.dart';
import '../widgets/ground_grid.dart';
import '../widgets/key_label.dart';
import '../widgets/pairing_connecting_panel.dart';
import '../widgets/theme/app_color.dart';
import '../widgets/theme/app_haptic.dart';
import '../widgets/theme/app_motion.dart';
import '../widgets/theme/app_radius.dart';
import '../widgets/theme/app_size.dart';
import '../widgets/theme/app_space.dart';
import '../widgets/theme/app_type.dart';
import '../widgets/theme/chrome_icon_action.dart';
import '../widgets/theme/chrome_tonal_button.dart';
import '../widgets/treatments.dart';

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

/// The channel `MainActivity.kt`/`AppDelegate.swift` (`WP-13-b`, `WP-0-b`, on request) listen
/// on to open the platform's app-details settings page, for the `Permission denied` row's
/// `Open Settings` action.
const MethodChannel _appSettingsChannel = MethodChannel(
  'dev.herdr.herdr_mobile/app_settings',
);

/// `border.frame`, per the width table beside `docs/32-design-language.md` R-32-330: 3 px,
/// the QR viewfinder corner marks. Every border width outside `border.hairline` and
/// `border.accent` stays a local constant beside its one caller, per `app_elev.dart`
/// (`WP-12-a`).
const double _borderFrameWidth = 3;

/// `opacity.dim`, per the same sibling opacity table: the scrim outside the viewfinder frame.
const double _opacityDim = 0.60;

/// R-31-01-07: written on `welcome_screen.dart` and repeated word for word by the help
/// sheet's `R-31-02-09`.
const List<String> _setupSteps = <String>[
  'Open Herdr on your computer.',
  'Open the Relay pane.',
  'Scan the QR code it shows.',
];

/// The screen's named phases, one per non-empty `Default`/`Loading`/`Error`/`Permission
/// denied` row of `docs/31-mockups/02-pair-scan.md`'s states table (R-90-011). `unreadable`,
/// `malformed` and the sheet-based failures are transient overlays on [ready], not separate
/// phases, since the scanner keeps running through every one of them.
enum QrScanPhase {
  cameraStarting,
  ready,
  pairing,
  cameraUnavailable,
  permissionDenied,
}

/// One inline hint issue: the scanner keeps running and the hint takes `treat.error`.
final class QrHintIssue {
  const QrHintIssue(this.text, {this.isError = true});
  final String text;
  final bool isError;
}

/// One single-action informational bottom sheet (`relay_origin_insecure`,
/// `phrase_expired`, `phrase_attempts`, relay-side
/// `pairing_expired`/`handle_unknown` failures) — R-32-545's "non-destructive" sheet, never
/// the destructive dialog of R-33-074, per R-30-005: none of these destroys anything.
final class _InfoSheet {
  const _InfoSheet({
    required this.title,
    required this.body,
    required this.actionLabel,
  });
  final String title;
  final String body;
  final String actionLabel;
}

/// The pairing error text table, `docs/30-ux-spec.md`'s pairing error text table
/// (R-31-03-07). Every code [parsePairingUri] and [attemptPairing] can raise on this screen.
const Map<String, String> _pairingErrorText = <String, String>{
  'pair_uri_scheme': 'That is not a Herdr pairing code.',
  'pair_uri_path': 'That is not a Herdr pairing code.',
  'pair_uri_version': 'That code came from a newer version. Update this app.',
  'pair_uri_field_missing': 'That pairing code is incomplete. Read it again.',
  'pair_uri_field_repeated': 'That pairing code is malformed. Read it again.',
  'pair_uri_too_long': 'That pairing code is too long to be one of ours.',
  'relay_origin_invalid':
      'That is not a relay address. Use the form https://relay.example.com.',
  'relay_origin_insecure':
      'A relay address must start with https, unless the computer is on '
      'your own network.',
  'handle_malformed':
      'That computer address is malformed. Read the code again.',
  'phrase_expired':
      'That phrase expired. Press {p} in the Relay pane for a new one.',
  'phrase_attempts':
      'Three tries used. The computer made a new phrase. Read it again.',
};

/// The pure presentation of one screen state. See this file's top doc comment for why this is
/// split from [QrScanScreen].
class QrScanScreenBody extends StatelessWidget {
  const QrScanScreenBody({
    super.key,
    required this.phase,
    this.controller,
    this.hasConnectedHost = false,
    this.torchOn = false,
    this.hint,
    this.offline = false,
    this.fingerprintText,
    this.onFlashToggle,
    this.onManualEntry,
    this.onHelp,
    this.onOpenSettings,
    this.connectingHost = '',
    this.onCancel,
  });

  final QrScanPhase phase;

  /// The live camera controller, for `MobileScanner(controller: ...)`. `null` in
  /// [QrScanPhase.cameraUnavailable] and [QrScanPhase.permissionDenied].
  final MobileScannerController? controller;

  /// R-30-945: the switch caption appears only once a computer is connected. First run
  /// (`/welcome`'s only route here) never carries one.
  final bool hasConnectedHost;

  final bool torchOn;

  /// An `unreadable`/`malformed` inline issue (R-31-02-02), replacing the default hint with
  /// `treat.error`. The scanner keeps running.
  final QrHintIssue? hint;

  final bool offline;

  /// A successful handshake's confirmation content (R-13-041), shown in place of the
  /// viewfinder for the moment before this route leaves, per R-31-02-04.
  final String? fingerprintText;

  final VoidCallback? onFlashToggle;
  final VoidCallback? onManualEntry;
  final VoidCallback? onHelp;
  final VoidCallback? onOpenSettings;
  final String connectingHost;
  final VoidCallback? onCancel;

  static const String _defaultHint =
      'Point the camera at the QR code in the Relay pane on your computer.';
  static const String _startingHint = 'Starting camera...';
  static const String _pairingHint = 'Connecting...';
  static const String _cameraUnavailableLine =
      'The camera is not available. Type the phrase instead.';
  static const String _permissionDeniedLine =
      'The app needs the camera to scan. Open Settings to allow it.';
  static const String _switchCaption =
      'Pairing disconnects the computer you are using now.';

  /// R-13-022: a phrase lives 600 seconds. The same sentence as `/welcome` and `/pair/manual`.
  static const String _offlineStrip =
      'No network. Pairing needs a connection, and a phrase lasts ten minutes.';

  /// `null` while the preview area itself carries the one line the state names (the camera
  /// did not start, or the permission is denied): the bar MUST NOT also say "Point the
  /// camera", a second instruction that contradicts the first.
  String? get _hintText {
    if (fingerprintText != null) {
      return 'Paired. Fingerprint $fingerprintText';
    }
    if (hint != null) {
      return hint!.text;
    }
    return switch (phase) {
      QrScanPhase.cameraStarting => _startingHint,
      QrScanPhase.pairing => _pairingHint,
      QrScanPhase.cameraUnavailable || QrScanPhase.permissionDenied => null,
      QrScanPhase.ready => _defaultHint,
    };
  }

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final Widget preview = switch (phase) {
      QrScanPhase.cameraUnavailable => const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpace.space6),
          child: Treatment.error(label: _cameraUnavailableLine),
        ),
      ),
      QrScanPhase.permissionDenied => const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpace.space6),
          child: Treatment.error(label: _permissionDeniedLine),
        ),
      ),
      _ => _Viewfinder(
        controller: controller,
        pairing: phase == QrScanPhase.pairing,
        zoomEnabled: phase == QrScanPhase.ready,
      ),
    };

    final Widget body = Column(
      children: <Widget>[
        Expanded(child: preview),
        if (phase == QrScanPhase.pairing && fingerprintText == null)
          PairingConnectingPanel(
            host: connectingHost,
            onCancel: onCancel ?? () {},
          )
        else
          _BottomBar(
            color: color,
            hintText: _hintText,
            hintIsError: hint?.isError ?? false,
            hintIsOk: hint != null && !hint!.isError,
            hasConnectedHost: hasConnectedHost,
            switchCaption: _switchCaption,
            offline: offline,
            offlineStrip: _offlineStrip,
            phase: phase,
            onManualEntry: phase == QrScanPhase.pairing ? null : onManualEntry,
            onOpenSettings: phase == QrScanPhase.permissionDenied
                ? onOpenSettings
                : null,
          ),
      ],
    );

    final Widget title = Text(
      'Pair a computer',
      style: AppType.heading.copyWith(color: color.fgPrimary),
    );
    // Callout 8: the off glyph in `color.fg.primary`, the on glyph in `color.accent.text`.
    // Both are the one app bar icon action of R-33-033's `App bar action` row.
    final Widget flashButton = ChromeIconAction(
      icon: torchOn ? Symbols.flash_on_rounded : Symbols.flash_off_rounded,
      label: torchOn ? 'Turn flash off' : 'Turn flash on',
      color: torchOn ? color.accentText : null,
      onPressed: phase == QrScanPhase.ready ? onFlashToggle : null,
    );
    final Widget helpButton = ChromeIconAction(
      icon: Symbols.info_rounded,
      label: 'How to pair a computer',
      onPressed: onHelp,
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
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[flashButton, helpButton],
          ),
        ),
        child: GroundGrid(child: body),
      );
    }
    return Scaffold(
      backgroundColor: color.bgBase,
      appBar: AppBar(
        backgroundColor: color.bgBase,
        elevation: 0,
        title: title,
        actions: <Widget>[flashButton, helpButton],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(AppBorder.hairline),
          child: Container(
            color: color.borderStrong,
            height: AppBorder.hairline,
          ),
        ),
      ),
      body: GroundGrid(child: body),
    );
  }
}

/// The camera preview plus the QR viewport of `docs/32-design-language.md` section 7.21:
/// a square frame at `min(screen width - 2 * space.6, 280)`, four `border.frame` corner marks
/// in `color.accent.primary`, and a `color.bg.base` scrim at `opacity.dim` outside the frame.
///
/// The mockup's `Loading, pairing` row: while [pairing] holds, the corner marks fade between
/// `color.accent.primary` and `color.fg.secondary` over `motion.duration.slow`, on
/// `motion.curve.move` (a colour that moves back and forth on screen, not an entrance). Under
/// reduced motion (R-32-606, R-30-730) nothing runs: the marks hold `color.fg.secondary`, the
/// fade's far end, so the state still reads without motion.
class _Viewfinder extends StatefulWidget {
  const _Viewfinder({
    required this.controller,
    required this.pairing,
    required this.zoomEnabled,
  });

  final MobileScannerController? controller;
  final bool pairing;
  final bool zoomEnabled;

  @override
  State<_Viewfinder> createState() => _ViewfinderState();
}

class _ViewfinderState extends State<_Viewfinder>
    with SingleTickerProviderStateMixin {
  CameraZoomRange? _zoomRange;
  double _zoom = 1;
  double _pinchStart = 1;
  double _pinchTarget = 1;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_syncZoom);
    if (widget.zoomEnabled) unawaited(_loadZoomRange());
  }

  Future<void> _loadZoomRange() async {
    final controller = widget.controller;
    if (controller == null) return;
    final range = await CameraZoomRange.load();
    if (!mounted || controller != widget.controller) return;
    setState(() {
      _zoomRange = range;
      if (range != null) {
        _zoom = range.factorFromScale(controller.value.zoomScale);
      }
    });
  }

  void _syncZoom() {
    final range = _zoomRange;
    final controller = widget.controller;
    if (range == null || controller == null) return;
    final factor = range.factorFromScale(controller.value.zoomScale);
    if (_zoom != factor) setState(() => _zoom = factor);
  }

  Future<void> _setZoom(double factor, {bool animated = false}) async {
    final range = _zoomRange;
    final controller = widget.controller;
    if (range == null || controller == null) return;
    final target = factor.clamp(range.min, range.max);
    setState(() => _zoom = target);
    try {
      await range.setFactor(controller, target, animated: animated);
    } on PlatformException {
      if (mounted) setState(() => _zoomRange = null);
    } on MobileScannerException {
      if (mounted) setState(() => _zoomRange = null);
    }
  }

  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: AppMotion.durationSlow,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncFade();
  }

  @override
  void didUpdateWidget(_Viewfinder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_syncZoom);
      widget.controller?.addListener(_syncZoom);
      _zoomRange = null;
    }
    if (widget.zoomEnabled &&
        (!oldWidget.zoomEnabled || oldWidget.controller != widget.controller)) {
      unawaited(_loadZoomRange());
    }
    if (oldWidget.pairing != widget.pairing) _syncFade();
  }

  void _syncFade() {
    final bool run = widget.pairing && !MediaQuery.disableAnimationsOf(context);
    if (run) {
      if (!_fade.isAnimating) _fade.repeat(reverse: true);
    } else {
      _fade
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_syncZoom);
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    final range = _zoomRange;
    final canZoom = widget.zoomEnabled && range != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onScaleStart: canZoom
          ? (_) {
              _pinchStart = _zoom;
              _pinchTarget = _zoom;
            }
          : null,
      onScaleUpdate: canZoom
          ? (details) {
              if (details.pointerCount < 2) return;
              _pinchTarget = (_pinchStart * details.scale).clamp(
                range.min,
                range.max,
              );
              unawaited(_setZoom(_pinchTarget, animated: !reduceMotion));
            }
          : null,
      onScaleEnd: canZoom ? (_) => unawaited(_setZoom(_pinchTarget)) : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double side = constraints.maxWidth > 0
              ? (constraints.maxWidth - 2 * AppSpace.space6).clamp(0, 280)
              : 280;
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (widget.controller != null)
                IgnorePointer(
                  child: ExcludeSemantics(
                    child: MobileScanner(controller: widget.controller),
                  ),
                ),
              IgnorePointer(
                child: ExcludeSemantics(
                  child: AnimatedBuilder(
                    animation: _fade,
                    builder: (context, _) {
                      final Color frameColor = widget.pairing && reduceMotion
                          ? color.fgSecondary
                          : Color.lerp(
                              color.accentPrimary,
                              color.fgSecondary,
                              AppMotion.curveMove.transform(_fade.value),
                            )!;
                      return CustomPaint(
                        size: Size(constraints.maxWidth, constraints.maxHeight),
                        painter: _ViewfinderPainter(
                          scrimColor: color.bgBase.withValues(
                            alpha: _opacityDim,
                          ),
                          frameColor: frameColor,
                          frameSide: side,
                        ),
                      );
                    },
                  ),
                ),
              ),
              if (range != null)
                // Below the frame, on the scrim: the target area stays clear
                // (R-31-02-13).
                PositionedDirectional(
                  start: AppSpace.space4,
                  end: AppSpace.space4,
                  top: (constraints.maxHeight + side) / 2 + AppSpace.space4,
                  child: Center(
                    child: Material(
                      color: color.bgBase,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          for (final factor in range.presets)
                            _zoomButton(factor, canZoom),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _zoomButton(double factor, bool enabled) {
    final label =
        '${factor == factor.roundToDouble() ? factor.toInt() : factor}x';
    final selected = (_zoom - factor).abs() < 0.01;
    final VoidCallback? onPressed = enabled
        ? () => unawaited(_setZoom(factor))
        : null;
    return Semantics(
      label: 'Zoom $label',
      button: true,
      selected: selected,
      enabled: enabled,
      onTap: onPressed,
      excludeSemantics: true,
      child: SizedBox(
        height: AppSize.targetMin,
        child: selected
            ? ChromeTonalButton(onPressed: onPressed, child: Text(label))
            : AppTextButton(label: label, onPressed: onPressed),
      ),
    );
  }
}

/// Paints the scrim (everything outside the centred frame) and the frame's four corner marks.
class _ViewfinderPainter extends CustomPainter {
  const _ViewfinderPainter({
    required this.scrimColor,
    required this.frameColor,
    required this.frameSide,
  });

  final Color scrimColor;
  final Color frameColor;
  final double frameSide;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect frame = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: frameSide,
      height: frameSide,
    );

    // The scrim: the full canvas minus the frame square, at `opacity.dim`. The preview behind
    // the frame stays clear (callout 5: "the outer frame area keeps its scrim").
    canvas.save();
    canvas.clipRect(frame, clipOp: ClipOp.difference);
    canvas.drawRect(Offset.zero & size, Paint()..color = scrimColor);
    canvas.restore();

    // Each mark is one L-shaped path, so the outer corner is a joined stroke, not two butt
    // caps that leave a notch. The round join gives that corner half the stroke width of
    // radius, the closest a stroke comes to the table's `radius.sm`.
    final Paint framePaint = Paint()
      ..color = frameColor
      ..strokeWidth = _borderFrameWidth
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.butt;
    const double corner = AppSize.viewfinderCorner;
    void mark(Offset origin, Offset toX, Offset toY) {
      final Path path = Path()
        ..moveTo(origin.dx + toY.dx, origin.dy + toY.dy)
        ..lineTo(origin.dx, origin.dy)
        ..lineTo(origin.dx + toX.dx, origin.dy + toX.dy);
      canvas.drawPath(path, framePaint);
    }

    mark(frame.topLeft, const Offset(corner, 0), const Offset(0, corner));
    mark(frame.topRight, const Offset(-corner, 0), const Offset(0, corner));
    mark(frame.bottomLeft, const Offset(corner, 0), const Offset(0, -corner));
    mark(frame.bottomRight, const Offset(-corner, 0), const Offset(0, -corner));
  }

  @override
  bool shouldRepaint(covariant _ViewfinderPainter oldDelegate) =>
      oldDelegate.scrimColor != scrimColor ||
      oldDelegate.frameColor != frameColor ||
      oldDelegate.frameSide != frameSide;
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.color,
    required this.hintText,
    required this.hintIsError,
    required this.hintIsOk,
    required this.hasConnectedHost,
    required this.switchCaption,
    required this.offline,
    required this.offlineStrip,
    required this.phase,
    this.onManualEntry,
    this.onOpenSettings,
  });

  final AppColor color;

  /// `null` draws no hint line: the preview area already carries the state's one line.
  final String? hintText;
  final bool hintIsError;
  final bool hintIsOk;
  final bool hasConnectedHost;
  final String switchCaption;
  final bool offline;
  final String offlineStrip;
  final QrScanPhase phase;
  final VoidCallback? onManualEntry;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: color.bgRaised,
      border: Border.symmetric(
        horizontal: BorderSide(
          color: color.borderSubtle,
          width: AppBorder.hairline,
        ),
      ),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.space4,
          vertical: AppSpace.space4,
        ),
        // Stretched: every action is a full-width text button with a centred label, the one
        // centring R-30-293 permits, as the wireframe draws `TYPE IT IN`.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Eyebrow(text: 'PAIRING'),
            if (hintText != null) ...<Widget>[
              const SizedBox(height: AppSpace.space3),
              if (hintIsError)
                Treatment.error(label: hintText!)
              else if (hintIsOk)
                Treatment.ok(label: hintText!)
              else
                Text(
                  hintText!,
                  style: AppType.body.copyWith(color: color.fgSecondary),
                ),
            ],
            if (hasConnectedHost) ...<Widget>[
              const SizedBox(height: AppSpace.space2),
              Text(
                switchCaption,
                style: AppType.caption.copyWith(color: color.fgSecondary),
              ),
            ],
            if (offline) ...<Widget>[
              const SizedBox(height: AppSpace.space2),
              Treatment.warning(label: offlineStrip),
            ],
            const SizedBox(height: AppSpace.space3),
            if (phase == QrScanPhase.permissionDenied) ...<Widget>[
              AppTextButton(label: 'Open Settings', onPressed: onOpenSettings),
              const SizedBox(height: AppSpace.space2),
            ],
            AppTextButton(label: 'Type it in', onPressed: onManualEntry),
          ],
        ),
      ),
    ),
  );
}

/// The bottom sheet grab handle of `docs/32-design-language.md` section 7.16: `size.grab` at
/// `radius.full` in `color.fg.disabled`, centred, `space.2` from the top, excluded from the
/// semantics tree (R-32-546). The same anatomy `pane_actions_sheet.dart` draws.
class _GrabHandle extends StatelessWidget {
  const _GrabHandle();

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.space2),
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
    );
  }
}

/// The surface every sheet on this screen is presented on: `color.bg.raised` with `radius.lg`
/// top corners (section 7.16), supplied to `showModalBottomSheet` the way
/// `device_list_screen.dart` does, so the content draws no surface of its own.
const RoundedRectangleBorder _sheetShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
);

/// The help sheet's content: the three setup steps of `_setupSteps`, word for word, plus one
/// `Close` row (R-31-02-09). Anatomy per section 7.16 and `pane_actions_sheet.dart`: grab
/// handle, `type.heading` title, `space.4` side inset, `space.6` under the last action.
class HelpSheetContent extends StatelessWidget {
  const HelpSheetContent({super.key, this.onClose});

  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.space4,
        AppSpace.space2,
        AppSpace.space4,
        AppSpace.space6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _GrabHandle(),
          Text(
            'How to pair a computer',
            style: AppType.heading.copyWith(color: color.fgPrimary),
          ),
          const SizedBox(height: AppSpace.space4),
          for (var i = 0; i < _setupSteps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.space2),
              child: Text(
                '${i + 1}  ${_setupSteps[i]}',
                style: AppType.body.copyWith(color: color.fgPrimary),
              ),
            ),
          const SizedBox(height: AppSpace.space2),
          AppTextButton(label: 'Close', onPressed: onClose),
        ],
      ),
    );
  }
}

/// One [_InfoSheet]'s content. No grab handle: `_showSheet` presents it with the drag and the
/// tap-outside dismissal off, so a handle would promise a gesture the sheet refuses. Otherwise
/// the same anatomy as [HelpSheetContent].
class _InfoSheetContent extends StatelessWidget {
  const _InfoSheetContent({required this.sheet, this.onAction});

  final _InfoSheet sheet;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.space4,
        AppSpace.space6,
        AppSpace.space4,
        AppSpace.space6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            sheet.title,
            style: AppType.heading.copyWith(color: color.fgPrimary),
          ),
          const SizedBox(height: AppSpace.space3),
          keyedText(
            sheet.body,
            style: AppType.body.copyWith(color: color.fgPrimary),
            color: color,
          ),
          const SizedBox(height: AppSpace.space6),
          AppFilledButton(label: sheet.actionLabel, onPressed: onAction),
        ],
      ),
    );
  }
}

/// The stateful orchestrator. Constructor parameters exist to inject fakes under test,
/// mirroring `LockScreen`'s own `gate`/`onUnlocked` injection seam.
///
/// [onManualEntry] routes to `/pair/manual`. [onPaired] is the caller's hook for what happens
/// once a handshake completes and is persisted — a later phase's router, per `R-90-024` and
/// this work package's `Publishes.` line ("Nothing"): this file decides no destination route
/// itself, the same "the caller decides where to go" pattern `lock_screen.dart`'s
/// `onUnlocked` already set. [hasConnectedHost] drives the switch caption (R-30-945); real
/// host-connection state is a later phase's concern (`docs/90` Phase 18), so it defaults to
/// `false`, first-run's only true value.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({
    super.key,
    PairingScanner? scanner,
    RelayConnection? connection,
    BiometricGate? gate,
    KeystoreService? keystore,
    PlainStore? plainStore,
    List<String>? effWords,
    this.hasConnectedHost = false,
    this.onManualEntry,
    this.onPaired,
    this.onCancelledSwitch,
    this.onFailedSwitch,
  }) : _providedScanner = scanner,
       _providedConnection = connection,
       _providedGate = gate,
       _providedKeystore = keystore,
       _providedPlainStore = plainStore,
       _providedEffWords = effWords;

  final PairingScanner? _providedScanner;
  final RelayConnection? _providedConnection;
  final BiometricGate? _providedGate;
  final KeystoreService? _providedKeystore;
  final PlainStore? _providedPlainStore;
  final List<String>? _providedEffWords;

  final bool hasConnectedHost;
  final VoidCallback? onManualEntry;
  final void Function(PairingOutcome outcome, PairingInput input)? onPaired;
  final VoidCallback? onCancelledSwitch;
  final void Function(String sentence)? onFailedSwitch;

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen>
    with WidgetsBindingObserver {
  late final PairingScanner _scanner =
      widget._providedScanner ??
      PairingScanner(
        controller: MobileScannerController(
          autoStart: false,
          formats: const [BarcodeFormat.qrCode],
        ),
      );
  late final RelayConnection _connection =
      widget._providedConnection ?? RelayConnection();
  late final BiometricGate _gate =
      widget._providedGate ?? BiometricGate(appLockEnabled: false);
  late final KeystoreService _keystore =
      widget._providedKeystore ?? KeystoreService(appLockEnabled: false);
  late final PlainStore _plainStore =
      widget._providedPlainStore ?? PlainStore();
  final PairingAttemptTracker _tracker = PairingAttemptTracker();

  QrScanPhase _phase = QrScanPhase.cameraStarting;
  bool _torchOn = false;
  bool _offline = false;
  QrHintIssue? _hint;
  String? _fingerprintText;
  List<String>? _effWords;

  StreamSubscription<String?>? _barcodeSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _busy = false;
  PairingCancellation? _cancellation;
  PairingInput? _input;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_init());
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (!mounted) {
        return;
      }
      setState(() => _offline = results.contains(ConnectivityResult.none));
    });
  }

  Future<void> _init() async {
    final effResult = widget._providedEffWords != null
        ? Ok<List<String>>(widget._providedEffWords!)
        : await loadEffWordlist();
    if (!mounted) {
      return;
    }
    if (effResult is Ok<List<String>>) {
      _effWords = effResult.value;
    }
    // R-31-02-01: the camera permission is requested here, by `start()` itself, the moment
    // this route mounts and never earlier.
    await _startCamera();
    if (mounted) {
      _barcodeSub = _scanner.scannedValues.listen(_onBarcode);
    }
  }

  Future<void> _startCamera() async {
    setState(() => _phase = QrScanPhase.cameraStarting);
    try {
      await _scanner.controller.start();
      // The plugin stores native start failures instead of throwing them.
      final error = _scanner.controller.value.error;
      if (error != null) {
        throw error;
      }
      if (!mounted) {
        return;
      }
      setState(() => _phase = QrScanPhase.ready);
    } on MobileScannerException catch (e) {
      if (!mounted) {
        return;
      }
      setState(
        () => _phase = e.errorCode == MobileScannerErrorCode.permissionDenied
            ? QrScanPhase.permissionDenied
            : QrScanPhase.cameraUnavailable,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // R-31-02-03, R-22-031: stop the camera on focus loss so the indicator never stays lit.
    if (state != AppLifecycleState.resumed) {
      unawaited(_scanner.pause());
    } else if (_phase == QrScanPhase.ready) {
      unawaited(_startCamera());
    }
  }

  @override
  void dispose() {
    _cancellation?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_barcodeSub?.cancel());
    unawaited(_connectivitySub?.cancel());
    unawaited(_scanner.dispose());
    super.dispose();
  }

  Future<void> _toggleFlash() async {
    await _scanner.controller.toggleTorch();
    if (!mounted) {
      return;
    }
    setState(
      () => _torchOn = _scanner.controller.value.torchState == TorchState.on,
    );
  }

  void _openHelp() {
    unawaited(_scanner.pause());
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        backgroundColor: Colors.transparent,
        shape: _sheetShape,
        builder: (context) => Material(
          color: AppColor.of(context).bgRaised,
          shape: _sheetShape,
          child: HelpSheetContent(onClose: () => Navigator.of(context).pop()),
        ),
      ).whenComplete(() {
        if (mounted && _phase == QrScanPhase.ready) {
          unawaited(_startCamera());
        }
      }),
    );
  }

  Future<void> _openAppSettings() async {
    await _appSettingsChannel.invokeMethod<bool>('open');
  }

  void _onBarcode(String? raw) {
    if (_busy || _phase != QrScanPhase.ready || raw == null || _offline) {
      // R-30-947: offline, the scan is read but the app MUST NOT start the switch at all.
      return;
    }
    if (!isPairingPayload(raw)) {
      unawaited(AppHaptic.error());
      setState(
        () => _hint = const QrHintIssue('That is not a Herdr pairing code.'),
      );
      return;
    }
    final effWords = _effWords;
    if (effWords == null) {
      return;
    }
    final parsed = parsePairingUri(raw, effWords);
    switch (parsed) {
      case Err<PairingInput>(:final cause):
        _handleParseFailure(cause);
      case Ok<PairingInput>(:final value):
        unawaited(_handleParsed(value));
    }
  }

  void _handleParseFailure(Object? cause) {
    unawaited(AppHaptic.error());
    final code = switch (cause) {
      PairingUriException(:final code) => code.wireValue,
      RelayOriginException(:final code) => code.wireValue,
      PhraseException(:final code) => code.wireValue,
      _ => null,
    };
    final text = code != null ? _pairingErrorText[code] : null;
    if (text == null) {
      setState(
        () => _hint = const QrHintIssue(
          'That pairing code is malformed. Read it again.',
        ),
      );
      return;
    }
    if (cause is RelayOriginException &&
        cause.code == RelayOriginErrorCode.relayOriginInsecure) {
      _showSheet(
        _InfoSheet(
          title: 'That relay is not encrypted',
          body: text,
          actionLabel: 'Close',
        ),
      );
      return;
    }
    setState(() => _hint = QrHintIssue(text));
  }

  void _cancelPairing() {
    final cancellation = _cancellation;
    if (!_busy || cancellation == null || cancellation.isCancelled) return;
    cancellation.cancel();
    unawaited(AppHaptic.select());
    setState(() {
      _busy = false;
      _phase = QrScanPhase.ready;
      _hint = const QrHintIssue('Pairing cancelled.', isError: false);
    });
    if (cancellation.disconnectedHost) widget.onCancelledSwitch?.call();
  }

  Future<void> _handleParsed(PairingInput input) async {
    final cancellation = PairingCancellation();
    _cancellation = cancellation;
    _input = input;

    setState(() {
      _busy = true;
      _hint = null;
      _phase = QrScanPhase.pairing;
    });
    final deviceInfoResult = await _buildDeviceInfo();
    if (!mounted || cancellation.isCancelled) {
      return;
    }
    if (deviceInfoResult is Err<messages.DeviceInfo>) {
      _failPairing('Could not read this phone\'s device information.');
      return;
    }
    final unlockResult = await _gate.unlock();
    if (!mounted || cancellation.isCancelled) {
      return;
    }
    if (unlockResult is Err<void>) {
      _failPairing('Could not unlock this phone.');
      return;
    }

    final outcome = await attemptPairing(
      cancellation: cancellation,
      connection: _connection,
      input: input,
      gate: _gate,
      deviceInfo: (deviceInfoResult as Ok<messages.DeviceInfo>).value,
      tracker: _tracker,
    );
    if (!mounted || cancellation.isCancelled) {
      return;
    }
    switch (outcome) {
      case Ok<PairingOutcome>(:final value):
        await _finishPairing(input, value, cancellation);
      case Err<PairingOutcome>(:final cause):
        _handleHandshakeFailure(cause);
    }
  }

  Future<void> _finishPairing(
    PairingInput input,
    PairingOutcome outcome,
    PairingCancellation cancellation,
  ) async {
    await persistPairing(
      keystore: _keystore,
      plainStore: _plainStore,
      input: input,
      outcome: outcome,
    );
    if (!mounted || cancellation.isCancelled) {
      return;
    }
    unawaited(AppHaptic.commit());
    setState(() {
      _fingerprintText = outcome.hostFingerprintText;
    });
    // R-31-02-04: leave this route inside `motion.duration.base`. R-32-606: under reduced
    // motion every `motion.duration.*` becomes 0 ms, so this wait collapses too.
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (!reduceMotion) {
      await Future<void>.delayed(AppMotion.durationBase);
    }
    if (!mounted || cancellation.isCancelled) {
      return;
    }
    cancellation.complete();
    widget.onPaired?.call(outcome, input);
  }

  void _handleHandshakeFailure(Object? cause) {
    setState(() {
      _busy = false;
      _phase = QrScanPhase.ready;
    });
    unawaited(AppHaptic.error());
    if (_cancellation?.disconnectedHost ?? false) {
      final input = _input!;
      final sentence = switch (cause) {
        PhraseException(:final code, :final message) =>
          _pairingErrorText[code.wireValue] ?? message,
        _ => pairingFailureSentence(
          cause,
          input.relayOrigin.webSocketUri('/').authority,
          secrets: [input.handle, input.phrase],
        ),
      };
      widget.onFailedSwitch?.call(sentence);
      return;
    }
    if (cause is PhraseException) {
      final text = _pairingErrorText[cause.code.wireValue] ?? cause.message;
      _showSheet(
        _InfoSheet(
          title: cause.code == PhraseErrorCode.phraseExpired
              ? 'Phrase expired'
              : 'Try again',
          body: text,
          actionLabel: 'Try again',
        ),
      );
      return;
    }
    if (cause is RelayRegistrationException) {
      switch (cause.code) {
        case RelayRegistrationErrorCode.handleUnknown:
          _showSheet(
            const _InfoSheet(
              title: 'The Relay pane is not open',
              body:
                  'Open the Relay pane on your computer, then read the '
                  'code again.',
              actionLabel: 'Try again',
            ),
          );
        case RelayRegistrationErrorCode.hostInUse:
          setState(
            () => _hint = const QrHintIssue(
              'Another phone is connected to that computer. Disconnect '
              'there, or remove that phone in the Relay pane, then try '
              'again.',
            ),
          );
        default:
          final input = _input!;
          setState(
            () => _hint = QrHintIssue(
              pairingFailureSentence(
                cause,
                input.relayOrigin.webSocketUri('/').authority,
                secrets: [input.handle, input.phrase],
              ),
            ),
          );
      }
      return;
    }
    final input = _input!;
    setState(
      () => _hint = QrHintIssue(
        pairingFailureSentence(
          cause,
          input.relayOrigin.webSocketUri('/').authority,
          secrets: [input.handle, input.phrase],
        ),
      ),
    );
  }

  void _failPairing(String message) {
    setState(() {
      _busy = false;
      _phase = QrScanPhase.ready;
      _hint = QrHintIssue(message);
    });
    unawaited(AppHaptic.error());
  }

  void _showSheet(_InfoSheet sheet) {
    unawaited(_scanner.pause());
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: Colors.transparent,
        shape: _sheetShape,
        builder: (context) => Material(
          color: AppColor.of(context).bgRaised,
          shape: _sheetShape,
          child: _InfoSheetContent(
            sheet: sheet,
            onAction: () => Navigator.of(context).pop(),
          ),
        ),
      ).whenComplete(() {
        if (mounted && _phase == QrScanPhase.ready) {
          unawaited(_startCamera());
        }
      }),
    );
  }

  /// Builds the `device_info` payload (`docs/11-relay-protocol.md` §4.2) for
  /// `RelayConnection.connect`. R-11-226 caps `deviceName` at 32 UTF-8 bytes; the device
  /// model names this reads are ASCII in practice, so truncating by character count is a safe
  /// approximation.
  Future<Result<messages.DeviceInfo>> _buildDeviceInfo() async {
    try {
      final idResult = await _plainStore.deviceId();
      if (idResult is Err<String>) {
        return Err(idResult.message, cause: idResult.cause);
      }
      final deviceId = (idResult as Ok<String>).value;
      final nameResult = await _plainStore.deviceName();
      final storedName = nameResult is Ok<String?> ? nameResult.value : null;

      String modelName;
      String osVersion;
      if (_isIos) {
        final info = await DeviceInfoPlugin().iosInfo;
        modelName = info.modelName;
        osVersion = info.systemVersion;
      } else {
        final info = await DeviceInfoPlugin().androidInfo;
        modelName = info.model;
        osVersion = info.version.release;
      }
      final packageInfo = await PackageInfo.fromPlatform();
      final name = storedName ?? modelName;
      return Ok(
        messages.DeviceInfo(
          protocol: frameProtocolVersion,
          deviceId: deviceId,
          deviceName: name.length > 32 ? name.substring(0, 32) : name,
          platform: _isIos ? messages.Platform.ios : messages.Platform.android,
          osVersion: osVersion,
          appVersion: packageInfo.version,
        ),
      );
    } on Exception catch (e) {
      return Err('build device info', cause: e);
    }
  }

  @override
  Widget build(BuildContext context) => QrScanScreenBody(
    phase: _phase,
    controller: _scanner.controller,
    hasConnectedHost: widget.hasConnectedHost,
    torchOn: _torchOn,
    hint: _hint,
    offline: _offline,
    fingerprintText: _fingerprintText,
    connectingHost: _input?.relayOrigin.webSocketUri('/').authority ?? '',
    onCancel: _cancelPairing,
    onFlashToggle: () => unawaited(_toggleFlash()),
    onManualEntry: widget.onManualEntry,
    onHelp: _openHelp,
    onOpenSettings: () => unawaited(_openAppSettings()),
  );
}
