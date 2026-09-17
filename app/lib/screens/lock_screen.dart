/// The biometric lock screen, per `docs/90-implementation-plan.md` `WP-13-b` and
/// `docs/31-mockups/04-lock.md` (R-90-010, R-90-011). One screen, three appearances: the glyph
/// and the primary label come from the biometric type `BiometricGate.availableBiometrics()`
/// reports at run time, never from the platform (R-31-04-06, R-32-407).
///
/// [LockScreenBody] is the pure, stateless presentation of one named state
/// ([LockScreenPhase] plus [LockScreenBody.offline]); it takes every value it paints as a
/// constructor argument and calls nothing. [LockScreen] is the stateful orchestrator: it owns a
/// [BiometricGate], calls `unlock()` on mount, classifies a failure into the state
/// [LockScreenBody] understands, and rebuilds. The split exists so a golden test can render
/// every named state deterministically, with no platform channel, by constructing
/// [LockScreenBody] directly (`app/test/screens/lock_screen_golden_test.dart`).
///
/// The native page scaffold keeps the lock surface opaque (R-33-015).
///
/// This file does not decide the route this screen lives on, and does not keep the target
/// route across an unlock (R-31-04-04, R-30-030): that is `app/lib/routing.dart`'s file, which
/// is not in this work package's `Owns.` line.
library;

import 'dart:async' show Completer, unawaited;

import 'package:connectivity_plus/connectivity_plus.dart'
    show Connectivity, ConnectivityResult;
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoPageScaffold;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:flutter/widgets.dart'
    show
        BuildContext,
        AppLifecycleState,
        Center,
        ColoredBox,
        Column,
        CrossAxisAlignment,
        EdgeInsets,
        Expanded,
        Icon,
        IconData,
        MainAxisAlignment,
        Padding,
        Row,
        SafeArea,
        SizedBox,
        State,
        StatefulWidget,
        StatelessWidget,
        Text,
        TextAlign,
        VoidCallback,
        Widget,
        WidgetsBinding,
        WidgetsBindingObserver;
import 'package:local_auth/local_auth.dart' show BiometricType;
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart' show Scaffold;

import '../core/result/result.dart' show Err, Ok;
import '../services/biometric_gate.dart';
import '../services/frame_presentation.dart';
import '../services/keystore.dart'
    show BiometricAuthenticationException, BiometricFailureReason;
import '../widgets/app_filled_button.dart';
import '../widgets/app_text_button.dart';
import '../widgets/brand_mark.dart';
import '../widgets/eyebrow.dart';
import '../widgets/ground_grid.dart';
import '../widgets/theme/app_color.dart';
import '../widgets/theme/app_haptic.dart';
import '../widgets/theme/app_radius.dart';
import '../widgets/theme/app_size.dart';
import '../widgets/theme/app_space.dart';
import '../widgets/theme/app_type.dart';
import '../widgets/treatments.dart';

/// Mockup 04 callout 1: the brand mark's height, and so the height of the band it sits in,
/// whose bottom rule its bottom crop touches (R-32-580). Not `size.icon.hero`, which is the
/// biometric glyph's size and happens to share the number.
const double _markHeight = 96;

/// The screen's named states, one per non-empty row of `docs/31-mockups/04-lock.md`'s
/// `## States` table (R-90-011). `Default` and `Loading` share [checking]: both show the same
/// wireframe with the platform sheet already raised and the primary action disabled, per the
/// mockup's own two rows, so there is nothing left to distinguish in this widget tree.
enum LockScreenPhase { checking, rejected, lockedOut, noEnrolment }

/// One biometric type's glyph and primary-action label, resolved once from
/// `BiometricGate.availableBiometrics()` and the platform, per the variant table in
/// `docs/31-mockups/04-lock.md`.
class BiometricPresentation {
  const BiometricPresentation({required this.glyph, required this.label});

  final IconData glyph;
  final String label;
}

/// Maps `local_auth`'s reported [types] to the one row of `docs/31-mockups/04-lock.md`'s
/// variant table that applies (R-31-04-06, R-32-407, amended 2026-09-16): the glyph is the lock
/// in every row, the type decides which label to use, and [isIOS] only picks that label's
/// platform wording, never a type of its own. Checked in the table's own row order; a device is
/// not expected to report more than one specific type, but `face` is checked first because it
/// is the first row.
BiometricPresentation biometricPresentation(
  List<BiometricType> types, {
  required bool isIOS,
}) {
  final String label;
  if (types.contains(BiometricType.face)) {
    label = isIOS ? 'Unlock with Face ID' : 'Unlock with face unlock';
  } else if (types.contains(BiometricType.fingerprint)) {
    label = isIOS ? 'Unlock with Touch ID' : 'Unlock with your fingerprint';
  } else if (types.contains(BiometricType.iris)) {
    // iOS has no iris sensor; the mockup's variant table marks this cell "not reachable" and
    // names no iOS wording for it, per R-22-070.
    label = 'Unlock with iris';
  } else {
    // R-22-070: the platform reported only `strong` or `weak`, or nothing at all. The app MUST
    // NOT guess a sensor from the manufacturer, the model or the API level.
    label = 'Unlock with biometrics';
  }
  return BiometricPresentation(glyph: Symbols.lock_rounded, label: label);
}

/// The reassurance line, callout 4. `docs/13-security-pairing.md` owns the exact storage
/// claim; this MUST NOT make a stronger one (`04-lock.md` callout 4).
const String _reassuranceLine =
    "Your keys stay in this phone's keystore, behind this check.";

const String _offlineStrip = 'No network. The app connects after you unlock.';

String _promptFor(LockScreenPhase phase) => switch (phase) {
  LockScreenPhase.checking => 'Unlock to continue.',
  LockScreenPhase.rejected => 'Not recognised. Try again.',
  LockScreenPhase.lockedOut => 'Biometrics are locked. Use your passcode.',
  LockScreenPhase.noEnrolment =>
    'No biometrics on this phone. Use your passcode.',
};

/// The pure presentation of one lock-screen state. See this file's top doc comment for why
/// this is split from [LockScreen].
class LockScreenBody extends StatelessWidget {
  const LockScreenBody({
    super.key,
    required this.phase,
    required this.biometric,
    this.offline = false,
    this.onPrimaryPressed,
    this.onFallbackPressed,
  });

  /// Which of the mockup's states to draw.
  final LockScreenPhase phase;

  /// The glyph and label this device's biometric type resolves to (R-31-04-06).
  final BiometricPresentation biometric;

  /// R-90-011's `Offline` row: a foot strip, with no other change, because the unlock is
  /// local.
  final bool offline;

  /// Callout 5: retries the biometric-or-passcode challenge. `null` while [phase] is
  /// [LockScreenPhase.checking], matching the mockup's `Loading` row ("the primary action is
  /// disabled").
  final VoidCallback? onPrimaryPressed;

  /// Callout 6: `Use device passcode`. The fallback MUST stay reachable in every state
  /// (R-31-04-03); it retries the same gate, whose keystore-triggered system prompt already
  /// allows `DEVICE_CREDENTIAL` / `LAPolicy.deviceOwnerAuthentication`, so this and the
  /// primary action drive the one system sheet, never a second one this widget draws
  /// (R-31-04-09, `biometric_gate.dart`'s top doc comment).
  final VoidCallback? onFallbackPressed;

  /// R-31-04-01 group: the primary biometric action is hidden, and `Use device passcode`
  /// becomes primary, once biometrics are locked out or unenrolled.
  bool get _biometricActionAvailable =>
      phase != LockScreenPhase.lockedOut &&
      phase != LockScreenPhase.noEnrolment;

  bool get _promptIsError =>
      phase == LockScreenPhase.rejected ||
      phase == LockScreenPhase.lockedOut ||
      phase == LockScreenPhase.noEnrolment;

  @override
  Widget build(BuildContext context) {
    final color = AppColor.of(context);
    final prompt = _promptFor(phase);

    final Widget body = GroundGrid(
      child: SafeArea(
        child: Column(
          children: <Widget>[
            SizedBox(
              height: _markHeight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  BrandMark(height: _markHeight, color: color.fgDisabled),
                ],
              ),
            ),
            SizedBox(
              height: AppBorder.hairline,
              child: ColoredBox(color: color.borderSubtle),
            ),
            Expanded(
              child: Padding(
                // R-30-230: the one screen edge inset, `space.4`, on every side; this
                // screen's actions then land where every other screen's do.
                padding: const EdgeInsets.all(AppSpace.space4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Eyebrow(text: 'Locked'),
                    const SizedBox(height: AppSpace.space2),
                    Text(
                      'Herdr Remote',
                      textAlign: TextAlign.center,
                      style: AppType.title.copyWith(color: color.fgPrimary),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Center(
                            child: Icon(
                              biometric.glyph,
                              size: AppSize.iconHero,
                              color: color.accentPrimary,
                              fill: 0,
                              weight: 400,
                              grade: 0,
                              semanticLabel: 'Locked',
                            ),
                          ),
                          const SizedBox(height: AppSpace.space6),
                          if (_promptIsError)
                            // R-30-293: `/lock` is the one screen that centres, so the
                            // wrapped prompt centres its lines too, not only its block.
                            Center(
                              child: Treatment.error(
                                label: prompt,
                                textAlign: TextAlign.center,
                              ),
                            )
                          else
                            Text(
                              prompt,
                              textAlign: TextAlign.center,
                              style: AppType.body.copyWith(
                                color: color.fgPrimary,
                              ),
                            ),
                          const SizedBox(height: AppSpace.space3),
                          Text(
                            _reassuranceLine,
                            textAlign: TextAlign.center,
                            style: AppType.caption.copyWith(
                              color: color.fgSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (offline) ...<Widget>[
                      Text(
                        _offlineStrip,
                        textAlign: TextAlign.center,
                        style: AppType.caption.copyWith(
                          color: color.fgSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpace.space6),
                    ],
                    if (_biometricActionAvailable) ...<Widget>[
                      AppFilledButton(
                        label: biometric.label,
                        onPressed: onPrimaryPressed,
                      ),
                      const SizedBox(height: AppSpace.space2),
                      AppTextButton(
                        label: 'Use device passcode',
                        onPressed: onFallbackPressed,
                      ),
                    ] else
                      AppFilledButton(
                        label: 'Use device passcode',
                        onPressed: onFallbackPressed,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return CupertinoPageScaffold(backgroundColor: color.bgBase, child: body);
    }
    return Scaffold(backgroundColor: color.bgBase, body: body);
  }
}

/// The stateful orchestrator: owns a [BiometricGate], drives it on mount, and renders
/// [LockScreenBody] for whatever it reports. [onUnlocked] is the caller's hook for what
/// happens next; per R-31-04-10 this widget never decides that itself, and per this work
/// package's scope it does not touch `app/lib/routing.dart`.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, BiometricGate? gate, this.onUnlocked})
    : _providedGate = gate;

  final BiometricGate? _providedGate;

  /// Called once the OS-enforced gate (R-22-013) succeeds. The caller decides where to go
  /// next: the held route, or `/hosts`, per R-31-04-04 and this mockup's `## Navigation`
  /// section.
  final VoidCallback? onUnlocked;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with WidgetsBindingObserver {
  late final BiometricGate _gate =
      widget._providedGate ?? BiometricGate(appLockEnabled: true);

  LockScreenPhase _phase = LockScreenPhase.checking;
  BiometricPresentation _biometric = const BiometricPresentation(
    glyph: Symbols.lock_rounded,
    label: 'Unlock with biometrics',
  );
  bool _offline = false;
  bool _unlockAttempted = false;
  bool _unlockInFlight = false;
  RasterizedFrame? _frame;
  late final Future<bool> _presented;
  Completer<void>? _resumed;

  static const _nativeLock = MethodChannel(
    'dev.herdr.herdr_mobile/biometric_lock',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _presented = _preparePresentation();
    unawaited(_startUnlockAfterPresentation());
    unawaited(_checkOffline());
  }

  Future<bool> _preparePresentation() async {
    try {
      await _loadBiometricPresentation();
    } on PlatformException {
      // Capability detection only chooses the glyph. The Keychain remains the real gate.
    }
    if (!mounted) return false;
    _frame = RasterizedFrame();
    if (!await _frame!.ready || !mounted) return false;
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // Raster completion and the native launch-screen transition are separate events.
        await _nativeLock.invokeMethod<void>('waitUntilDisplayed');
      }
    } on PlatformException {
      if (mounted) setState(() => _phase = LockScreenPhase.rejected);
      return false;
    }
    return mounted;
  }

  Future<void> _startUnlockAfterPresentation() async {
    if (await _presented && mounted && !_unlockAttempted) {
      await _attemptUnlock();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resumed?.complete();
    _resumed = null;
    _frame?.cancel();
    super.dispose();
  }

  bool get _active =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumed?.complete();
      _resumed = null;
    }
  }

  Future<bool> _revealWhenActive() async {
    while (mounted) {
      if (!_active) {
        _resumed ??= Completer<void>();
        await _resumed!.future;
        continue;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android) {
        // An inactive scene retains its native cover. Wait for resume before removing it,
        // then recheck lifecycle after the channel call, immediately before authentication.
        await _nativeLock.invokeMethod<void>('frameReady');
      }
      if (_active) return mounted;
    }
    return false;
  }

  Future<void> _loadBiometricPresentation() async {
    final types = await _gate.availableBiometrics();
    if (!mounted) {
      return;
    }
    setState(() {
      _biometric = biometricPresentation(
        types,
        isIOS: defaultTargetPlatform == TargetPlatform.iOS,
      );
    });
  }

  Future<void> _checkOffline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (!mounted) {
        return;
      }
      setState(() {
        _offline = results.contains(ConnectivityResult.none);
      });
    } on Exception {
      // The unlock itself is local (R-90 states table's `Offline` row); a connectivity
      // read failing costs this screen nothing beyond not showing the foot strip.
    }
  }

  Future<void> _attemptUnlock() async {
    if (_unlockInFlight) return;
    _unlockInFlight = true;
    _unlockAttempted = true;
    if (!await _presented || !mounted) {
      _unlockInFlight = false;
      return;
    }
    try {
      if (!await _revealWhenActive()) {
        _unlockInFlight = false;
        return;
      }
    } on PlatformException {
      _unlockInFlight = false;
      if (mounted) setState(() => _phase = LockScreenPhase.rejected);
      return;
    }
    setState(() => _phase = LockScreenPhase.checking);
    final result = await _gate.unlock();
    _unlockInFlight = false;
    if (!mounted) {
      return;
    }
    switch (result) {
      case Ok<void>():
        widget.onUnlocked?.call();
      case Err<void>(:final cause):
        final phase = _phaseFor(cause);
        setState(() => _phase = phase);
        if (phase == LockScreenPhase.rejected) {
          unawaited(AppHaptic.error());
        }
    }
  }

  LockScreenPhase _phaseFor(Object? cause) {
    if (cause is BiometricAuthenticationException) {
      return switch (cause.reason) {
        BiometricFailureReason.lockedOutTemporarily ||
        BiometricFailureReason.lockedOutPermanently =>
          LockScreenPhase.lockedOut,
        BiometricFailureReason.notEnrolled => LockScreenPhase.noEnrolment,
        BiometricFailureReason.rejected => LockScreenPhase.rejected,
      };
    }
    // A `KeyInvalidatedException` (R-22-010), or any other unclassified `Err.cause`, names
    // no state of its own in `docs/31-mockups/04-lock.md`: a real re-pair prompt needs the
    // pairing screens of a later phase. This folds to the closest existing state rather than
    // inventing a state the mockup does not specify. Gap tracked at
    // `docs/90-implementation-plan.md` `## 8. Blocked work` item B30.
    return LockScreenPhase.rejected;
  }

  @override
  Widget build(BuildContext context) => LockScreenBody(
    phase: _phase,
    biometric: _biometric,
    offline: _offline,
    onPrimaryPressed: _phase == LockScreenPhase.checking
        ? null
        : _attemptUnlock,
    onFallbackPressed: _attemptUnlock,
  );
}
