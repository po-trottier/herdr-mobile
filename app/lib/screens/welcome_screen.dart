/// The first-run welcome screen, per `docs/90-implementation-plan.md` `WP-15-b` and
/// `docs/31-mockups/01-welcome.md` (R-90-010, R-90-011).
///
/// Gated on a zero paired-Host count (R-31-01-01): a caller — a later phase's router
/// redirect, per `app/lib/routing.dart`'s own doc comment that a real host-scoped route needs
/// a paired computer this phase does not yet have — decides when to show this route. This
/// file does not touch `app/lib/routing.dart` (outside this work package's `Paths.` line).
///
/// [WelcomeScreenBody] is the pure, stateless presentation of one named state, mirroring
/// `lock_screen.dart`'s split: it takes every value it paints as a constructor argument and
/// calls nothing, so a state can be rendered deterministically with no platform channel.
/// [WelcomeScreen] is the stateful orchestrator: it checks connectivity (`connectivity_plus`,
/// mirroring `LockScreen`'s own one-shot `Connectivity()` check) once on mount.
///
/// [WelcomeScreenBody] wraps its content in a [Scaffold], not a bare `ColoredBox`, per
/// R-41-020: a `Text` with no `Material` ancestor silently falls back to `MaterialApp`'s own
/// deliberately-ugly `_errorTextStyle` (`package:flutter/src/material/app.dart`), which sets
/// a yellow, double `TextStyle.decoration`. No `AppType` token sets `decoration`, and
/// `Text.style` merges over `DefaultTextStyle` rather than replacing it, so that fallback
/// underline was reaching every piece of text on this screen while its `color` override hid
/// only the fallback's red text colour. `Scaffold` supplies the missing `Material` and a real
/// `DefaultTextStyle`. Do not revert this to a bare `ColoredBox` — that silently reintroduces
/// the yellow underline on every `Text` on this screen. `lock_screen.dart`'s `LockScreenBody`
/// and `app_shell.dart`'s iOS branch had this same bare-`ColoredBox` gap; both now wrap in a
/// `Scaffold`/`CupertinoPageScaffold` too, for the identical reason.
///
/// R-31-01-09: this screen MUST NOT require, check for, or mention a device screen lock, a
/// passcode or biometric enrolment, and MUST NOT disable `Scan QR code` for one — pairing and
/// every other app action work fully with App Lock off (`docs/03-product-decisions.md`
/// R-03-090), on a phone with no screen lock at all. It imports no `local_auth`. `docs/13
/// -security-pairing.md` R-13-043 still has the Device generate its Curve25519 keypair
/// unconditionally on first launch; this screen attempts that generation itself on mount, via
/// a plain `KeystoreService` read, so the `Error` state below reflects a genuine keystore
/// failure rather than a screen-lock precondition. See `docs/decisions/ADR-009-optional-app
/// -lock.md`.
///
/// R-31-01-02, R-31-01-03: this screen requests no permission of any kind and holds no
/// carousel, page indicator or second primary action — it imports no camera and no
/// notification API. `docs/30-ux-spec.md` R-30-509 and `docs/31-mockups/01-welcome.md`
/// R-31-01-04 place the platform notification-permission request on the first arrival at the
/// agent list after the first successful pair — a screen `docs/90`'s Phase 18 builds, not
/// this one; R-31-01-04 states plainly that this screen "MUST NOT request the platform alert
/// permission". `docs/22-platform-integration.md` R-22-021 and R-22-071 still read as though
/// that request belonged on `/welcome`; per R-90-008 the more specific, later-revised mockup
/// wins, and its own `## Retired rules` row retires the matching `R-31-01-06` in R-30-509's
/// favour, confirming the move was deliberate. See `## 8. Blocked work` item B16.
library;

import 'dart:async' show unawaited;

import 'package:connectivity_plus/connectivity_plus.dart'
    show Connectivity, ConnectivityResult;
import 'package:cryptography/cryptography.dart' show SimpleKeyPair;
import 'package:flutter/widgets.dart'
    show
        Align,
        Alignment,
        Border,
        BorderSide,
        BorderRadius,
        BoxDecoration,
        BoxFit,
        BuildContext,
        ClipRRect,
        ColoredBox,
        Column,
        CrossAxisAlignment,
        CustomScrollView,
        DecoratedBox,
        EdgeInsets,
        ExcludeSemantics,
        Expanded,
        FittedBox,
        FractionallySizedBox,
        Icon,
        IconData,
        MainAxisSize,
        NotificationListener,
        Padding,
        Positioned,
        Row,
        SafeArea,
        ScrollMetrics,
        ScrollMetricsNotification,
        ScrollNotification,
        Semantics,
        SizedBox,
        SliverFillRemaining,
        Stack,
        State,
        StatefulWidget,
        StatelessWidget,
        Text,
        VoidCallback,
        Widget;
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart' show Scaffold;

import '../core/result/result.dart' show Err;
import '../services/keystore.dart' show KeystoreService;
import '../widgets/app_filled_button.dart';
import '../widgets/app_strip.dart';
import '../widgets/app_text_button.dart';
import '../widgets/brand_mark.dart';
import '../widgets/eyebrow.dart';
import '../widgets/ground_grid.dart';
import '../widgets/theme/app_color.dart';
import '../widgets/theme/app_radius.dart';
import '../widgets/theme/app_size.dart';
import '../widgets/theme/app_space.dart';
import '../widgets/theme/app_type.dart';
import '../widgets/treatments.dart';

/// R-31-01-07: written on this screen and nowhere else; the help sheet on `/pair/scan`
/// repeats these three sentences word for word (`qr_scan_screen.dart`, R-31-02-09).
const List<String> pairingSetupSteps = <String>[
  'Open Herdr on your computer.',
  'Open the Relay pane.',
  'Scan the QR code it shows.',
];

/// One icon per row of [pairingSetupSteps], same order. `R-32-401`: `A computer`, `The relay`
/// and `Scan a QR code` map to `computer`, `dns` and `qr_code_scanner`.
const List<IconData> _stepIcons = <IconData>[
  Symbols.computer_rounded,
  Symbols.dns_rounded,
  Symbols.qr_code_scanner_rounded,
];

/// Mockup 01 callout 1: the hero takes whatever height is left after the fixed content below
/// it, so both actions are on screen without a scroll at every size (R-31-01-08). The mark is
/// this share of the hero's height and never larger than [_markMaxHeight].
const double _markFraction = 0.64;
const double _markMaxHeight = 320;

const String _valueSentence =
    'Read a pane. Send a prompt. Nothing else crosses the network.';

/// R-30-512's exact wording.
const String _alertRunningLimitation =
    'Alerts arrive while the app is running. If the phone closes the app, '
    'the alert is waiting in the app the next time you open it.';

/// R-30-517's exact wording.
const String _alertScopeLimitation =
    'Alerts come from the computer you are connected to. If an agent '
    'finishes on another computer, you see it when you connect to that '
    'computer.';
const String _keystoreInitError =
    'Something went wrong setting up this phone. Restart the app.';

/// R-13-022: a phrase lives 600 seconds. The same sentence, in the same `treat.warning`, on
/// `/pair/scan` and `/pair/manual`.
const String _offlineStrip =
    'No network. Pairing needs a connection, and a phrase lasts ten minutes.';

/// The pure presentation of one welcome-screen state. See this file's top doc comment for why
/// this is split from [WelcomeScreen].
class WelcomeScreenBody extends StatelessWidget {
  const WelcomeScreenBody({
    super.key,
    this.isError = false,
    this.isOffline = false,
    this.onScanPressed,
    this.onManualPressed,
  });

  /// The `Error` row, per `docs/31-mockups/01-welcome.md`'s `## States` table: the device's
  /// secure key storage failed to initialise -- a rare operating-system or hardware fault,
  /// unrelated to screen-lock status (R-31-01-09). Replaces the setup list with one error
  /// line and disables the primary action; the mockup names no change to the secondary
  /// action.
  final bool isError;

  /// The `Offline` row: a strip above the primary action. The primary action stays enabled,
  /// because the camera works offline.
  final bool isOffline;

  /// Callout 5: `Scan QR code`. `null` while [isError] holds.
  final VoidCallback? onScanPressed;

  /// Callout 6: `Enter the phrase instead`, routes to `/pair/manual`.
  final VoidCallback? onManualPressed;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    return Scaffold(
      backgroundColor: color.bgBase,
      // R-32-332: the grid aligns to the safe area's top-left, so it lives inside
      // it; the status-bar band above shows plain `color.bg.base`.
      body: SafeArea(
        child: GroundGrid(
          child: _ScrollEdgeFooter(
            scrollable: CustomScrollView(
              slivers: <Widget>[
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            // The hero is the one band without the ground grid:
                            // plain `color.bg.base` up to its bottom rule, so the
                            // mark and eyebrow sit on a quiet field (R-32-594).
                            color: color.bgBase,
                            border: Border(
                              bottom: BorderSide(
                                color: color.borderSubtle,
                                width: AppBorder.hairline,
                              ),
                            ),
                          ),
                          child: Stack(
                            children: <Widget>[
                              Positioned.fill(
                                child: Align(
                                  alignment: Alignment.bottomRight,
                                  child: FractionallySizedBox(
                                    heightFactor: _markFraction,
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.bottomRight,
                                      child: BrandMark(
                                        height: _markMaxHeight,
                                        color: color.fgPrimary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const Positioned(
                                left: AppSpace.space4,
                                bottom: AppSpace.space4,
                                child: Eyebrow(text: 'Herdr Remote'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpace.space4,
                          AppSpace.space6,
                          AppSpace.space4,
                          AppSpace.space6,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Watch the herd.\nFrom anywhere.',
                              style: AppType.display.copyWith(
                                color: color.fgPrimary,
                              ),
                            ),
                            const SizedBox(height: AppSpace.space3),
                            Text(
                              _valueSentence,
                              style: AppType.body.copyWith(
                                color: color.fgSecondary,
                              ),
                            ),
                            const SizedBox(height: AppSpace.space6),
                            if (isError)
                              const Treatment.error(label: _keystoreInitError)
                            else
                              ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.md,
                                ),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: color.bgRaised,
                                    border: Border.all(
                                      color: color.borderSubtle,
                                      width: AppBorder.hairline,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: <Widget>[
                                      // R-32-333: the featured card's `border.accent` top edge.
                                      SizedBox(
                                        height: AppBorder.accent,
                                        child: ColoredBox(
                                          color: color.accentPrimary,
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(
                                          AppSpace.space4,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: <Widget>[
                                            for (
                                              var i = 0;
                                              i < pairingSetupSteps.length;
                                              i++
                                            )
                                              Padding(
                                                padding: EdgeInsets.only(
                                                  bottom:
                                                      i ==
                                                          pairingSetupSteps
                                                                  .length -
                                                              1
                                                      ? 0
                                                      : AppSpace.space2,
                                                ),
                                                child: _StepRow(
                                                  number: i + 1,
                                                  total:
                                                      pairingSetupSteps.length,
                                                  text: pairingSetupSteps[i],
                                                  icon: _stepIcons[i],
                                                  color: color,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            const SizedBox(height: AppSpace.space6),
                            // The 7.31 `Alert note` row (amended 2026-09-08): `type.caption`
                            // in `color.fg.secondary`, the `info` icon at `size.icon.sm` on
                            // the first line. A 16 icon on a 16 line needs no offset.
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Icon(
                                  Symbols.info_rounded,
                                  size: AppSize.iconSm,
                                  color: color.fgSecondary,
                                ),
                                const SizedBox(width: AppSpace.space2),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        _alertRunningLimitation,
                                        style: AppType.caption.copyWith(
                                          color: color.fgSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: AppSpace.space2),
                                      Text(
                                        _alertScopeLimitation,
                                        style: AppType.caption.copyWith(
                                          color: color.fgSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // R-31-01-08: the limitation notes end the scrolling content and both actions
            // sit in this footer, outside the scroll, so they are on screen at every size.
            footer: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.space4,
                AppSpace.space3,
                AppSpace.space4,
                AppSpace.space4,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (isOffline) ...<Widget>[
                    const AppStrip(
                      child: Treatment.warning(label: _offlineStrip),
                    ),
                    const SizedBox(height: AppSpace.space3),
                  ],
                  AppFilledButton(
                    label: 'Scan QR code',
                    onPressed: isError ? null : onScanPressed,
                  ),
                  // `space.2`: the gap every filled-then-text stack in the app uses
                  // (`/lock`, `/pair/manual`, the connection screen, every sheet).
                  const SizedBox(height: AppSpace.space2),
                  AppTextButton(
                    label: 'Enter the phrase instead',
                    onPressed: onManualPressed,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The scrolling column above a fixed footer, with a `border.subtle` hairline on the footer's
/// top edge only while content is still under it (R-31-01-08: the column scrolls under the
/// footer as a last resort, so the cut sentence has to read as scrolled-under, not as the end).
/// A viewport that fits, or a column scrolled to its end, draws no rule: the note and the
/// actions then read as one column, as the mockup's wireframe draws them.
class _ScrollEdgeFooter extends StatefulWidget {
  const _ScrollEdgeFooter({required this.scrollable, required this.footer});

  final Widget scrollable;
  final Widget footer;

  @override
  State<_ScrollEdgeFooter> createState() => _ScrollEdgeFooterState();
}

class _ScrollEdgeFooterState extends State<_ScrollEdgeFooter> {
  bool _contentBelow = false;

  void _update(ScrollMetrics metrics) {
    final bool below = metrics.hasContentDimensions && metrics.extentAfter > 0;
    if (below != _contentBelow) {
      setState(() => _contentBelow = below);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    return Column(
      children: <Widget>[
        Expanded(
          // Metrics arrive once per layout (the initial fit, a rotation, a text-scale
          // change); scroll notifications arrive per drag. Both carry the same metrics.
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: (ScrollMetricsNotification n) {
              _update(n.metrics);
              return false;
            },
            child: NotificationListener<ScrollNotification>(
              onNotification: (ScrollNotification n) {
                _update(n.metrics);
                return false;
              },
              child: widget.scrollable,
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            border: _contentBelow
                ? Border(
                    top: BorderSide(
                      color: color.borderSubtle,
                      width: AppBorder.hairline,
                    ),
                  )
                : null,
          ),
          child: widget.footer,
        ),
      ],
    );
  }
}

/// One numbered setup-list row. Screen-reader accessibility: read as `Step <n> of <total>`,
/// one item, per the mockup's own Accessibility section — never as one run-together
/// paragraph.
class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.number,
    required this.total,
    required this.text,
    required this.icon,
    required this.color,
  });

  final int number;
  final int total;
  final String text;
  final IconData icon;
  final AppColor color;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Step $number of $total',
    child: ExcludeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
        children: <Widget>[
          Icon(icon, size: AppSize.iconSm, color: color.fgSecondary),
          const SizedBox(width: AppSpace.space2),
          Text(
            number.toString().padLeft(2, '0'),
            style: AppType.monoButton.copyWith(color: color.accentText),
          ),
          const SizedBox(width: AppSpace.space2),
          Expanded(
            child: Text(
              text,
              style: AppType.body.copyWith(color: color.fgPrimary),
            ),
          ),
        ],
      ),
    ),
  );
}

/// The stateful orchestrator. [onScanPressed] and [onManualPressed] are the caller's hooks
/// for `/pair/scan` and `/pair/manual`; per this work package's scope this widget does not
/// touch `app/lib/routing.dart`, mirroring `LockScreen.onUnlocked`'s "the caller decides
/// where to go" pattern.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({
    super.key,
    KeystoreService? keystore,
    this.onScanPressed,
    this.onManualPressed,
  }) : _providedKeystore = keystore;

  final KeystoreService? _providedKeystore;
  final VoidCallback? onScanPressed;
  final VoidCallback? onManualPressed;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  // R-03-090: App Lock defaults off, and nothing has paired yet at this screen, so there is
  // no App Lock setting to read here -- the off-mode options are always correct for this
  // first, unconditional key generation/read (R-13-043).
  late final KeystoreService _keystore =
      widget._providedKeystore ?? KeystoreService(appLockEnabled: false);

  bool _keystoreUnavailable = false;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    unawaited(_checkKeystoreAvailable());
    unawaited(_checkOffline());
  }

  /// R-31-01-09: this screen checks nothing about a screen lock. It instead attempts the
  /// real, unconditional key generation/read R-13-043 requires on first launch, and shows the
  /// `Error` state only if that plain keystore operation itself fails (a rare operating-system
  /// or hardware fault, per `docs/31-mockups/01-welcome.md`'s `## States` table) -- never for
  /// a missing screen lock. `KeystoreService.deviceKeyPair()` is idempotent: the later pairing
  /// handshake's own call to it returns this same key, so this early read never regenerates
  /// or discards anything.
  Future<void> _checkKeystoreAvailable() async {
    final result = await _keystore.deviceKeyPair();
    if (!mounted) {
      return;
    }
    setState(() => _keystoreUnavailable = result is Err<SimpleKeyPair>);
  }

  Future<void> _checkOffline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (!mounted) {
        return;
      }
      setState(() => _offline = results.contains(ConnectivityResult.none));
    } on Exception {
      // The primary action stays enabled either way; the strip is a courtesy, not a gate.
    }
  }

  @override
  Widget build(BuildContext context) => WelcomeScreenBody(
    isError: _keystoreUnavailable,
    isOffline: _offline,
    onScanPressed: widget.onScanPressed,
    onManualPressed: widget.onManualPressed,
  );
}
