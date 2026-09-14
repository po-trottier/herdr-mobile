/// Golden tests for `LockScreenBody` (`app/lib/screens/lock_screen.dart`, `WP-13-b`), one per
/// named row of `docs/31-mockups/04-lock.md`'s `## States` table (R-90-011), each rendered in
/// both Selenized dark and light (R-32-012).
///
/// Renders `LockScreenBody` directly, not the stateful `LockScreen`: the presentational split
/// documented at the top of `lock_screen.dart` exists exactly so this file needs no
/// `BiometricGate`, no `local_auth` platform channel and no `connectivity_plus` platform
/// channel, and so every state is reachable with a fixed, deterministic constructor call
/// instead of driving async, possibly-flaky state transitions.
///
/// Fonts, the app theme, the 375 x 667 reference size and the brand-mark precache come from
/// `golden_support.dart` (`loadAppFonts`, `goldenApp`, `goldenReferenceSize`,
/// `precacheBrandMark`); see its doc comment for why. `devicePixelRatio` stays fixed at 1.0, so
/// each PNG's pixel dimensions equal the logical size.
///
/// What this file proves and what it does not: matching goldens prove Flutter's own widget
/// rendering — layout, colour, spacing, text, icons — reproduces `04-lock.md` pixel for pixel.
/// It does NOT exercise the real native `BiometricPrompt` / `LocalAuthentication` system
/// dialog, which `local_auth` raises through a platform channel and Flutter never paints; that
/// native-dialog appearance needs a real device or emulator, a separate gap from this screen's
/// own layout.
library;

import 'package:flutter/widgets.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/screens/lock_screen.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'golden_support.dart';

/// One fixed biometric presentation, held constant across every golden: these tests vary
/// [LockScreenPhase] and `offline`, not the reported biometric type or the platform.
/// `biometricPresentation()`'s own branching — which type picks which glyph, and which
/// platform picks which label wording — is `lock_screen_test.dart`'s job, a plain `test()`
/// on the function's return value, since it is pure and needs no widget tree.
const _biometric = BiometricPresentation(
  glyph: Symbols.fingerprint_rounded,
  label: 'Unlock with your fingerprint',
);

class _Case {
  const _Case(this.name, this.phase, {this.offline = false});
  final String name;
  final LockScreenPhase phase;
  final bool offline;
}

/// One entry per named row of the mockup's `## States` table. `default` and `loading` render
/// the same `LockScreenPhase.checking` body — `lock_screen.dart`'s top doc comment records why
/// the mockup gives them nothing to distinguish in this widget tree — so their two goldens are
/// deliberately byte-identical, not a defect.
const _cases = <_Case>[
  _Case('default', LockScreenPhase.checking),
  _Case('loading', LockScreenPhase.checking),
  _Case('rejected', LockScreenPhase.rejected),
  _Case('locked_out', LockScreenPhase.lockedOut),
  _Case('no_enrolment', LockScreenPhase.noEnrolment),
  _Case('offline', LockScreenPhase.checking, offline: true),
];

const _themes = <(String, Brightness)>[
  ('dark', Brightness.dark),
  ('light', Brightness.light),
];

void main() {
  setUpAll(loadAppFonts);

  for (final testCase in _cases) {
    for (final (themeName, brightness) in _themes) {
      testWidgets(
        '${testCase.name} ($themeName) matches docs/31-mockups/04-lock.md',
        (tester) async {
          tester.view.physicalSize = goldenReferenceSize;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            goldenApp(
              brightness: brightness,
              child: LockScreenBody(
                phase: testCase.phase,
                biometric: _biometric,
                offline: testCase.offline,
                onPrimaryPressed: testCase.phase == LockScreenPhase.checking
                    ? null
                    : () {},
                onFallbackPressed: () {},
              ),
            ),
          );
          await precacheBrandMark(tester, find.byType(LockScreenBody));
          await tester.pumpAndSettle();

          // Structural proof alongside the visual one: every callout the mockup names is
          // really present in the tree, not just painted to look right by coincidence.
          expect(find.text('Herdr Remote'), findsOneWidget);
          expect(
            find.text(
              "Your keys stay in this phone's keystore, behind this check.",
            ),
            findsOneWidget,
          );
          if (testCase.phase == LockScreenPhase.lockedOut ||
              testCase.phase == LockScreenPhase.noEnrolment) {
            expect(find.text(_biometric.label), findsNothing);
          } else {
            expect(find.text(_biometric.label), findsOneWidget);
          }
          expect(find.text('Use device passcode'), findsOneWidget);
          expect(
            find.text('No network. The app connects after you unlock.'),
            findsNWidgets(testCase.offline ? 1 : 0),
          );

          await expectLater(
            find.byType(LockScreenBody),
            matchesGoldenFile(
              'goldens/lock_screen_${testCase.name}_$themeName.png',
            ),
          );
        },
      );
    }
  }
}
