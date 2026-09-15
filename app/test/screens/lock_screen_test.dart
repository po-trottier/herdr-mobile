/// Non-golden structural/unit coverage for `app/lib/screens/lock_screen.dart` (`WP-13-b`).
///
/// `biometricPresentation()` is a pure function, so a plain `test()` on its return value is
/// the direct proof, per `docs/31-mockups/04-lock.md`'s variant table (R-31-04-06, R-32-407):
/// the reported [BiometricType] picks the glyph and which label applies, and the platform
/// picks only that label's wording. `lock_screen_golden_test.dart` renders every screen
/// *state* with one fixed biometric presentation; it does not exercise this function's own
/// type-and-platform branching, which is this file's job.
library;

import 'package:flutter/widgets.dart' show Text;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/screens/lock_screen.dart';
import 'package:herdr_mobile/widgets/brand_mark.dart';
import 'package:herdr_mobile/widgets/eyebrow.dart';
import 'package:herdr_mobile/widgets/ground_grid.dart';
import 'package:local_auth/local_auth.dart' show BiometricType;
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart' show MaterialApp;

void main() {
  group('biometricPresentation', () {
    test('face on iOS reads the iOS wording, per the variant table', () {
      final result = biometricPresentation([BiometricType.face], isIOS: true);
      expect(result.glyph, Symbols.face_rounded);
      expect(result.label, 'Unlock with Face ID');
    });

    test(
      'face on Android reads the Android wording, per the variant table',
      () {
        final result = biometricPresentation([
          BiometricType.face,
        ], isIOS: false);
        expect(result.glyph, Symbols.face_rounded);
        expect(result.label, 'Unlock with face unlock');
      },
    );

    test('fingerprint on iOS reads the iOS wording, per the variant table', () {
      final result = biometricPresentation([
        BiometricType.fingerprint,
      ], isIOS: true);
      expect(result.glyph, Symbols.fingerprint_rounded);
      expect(result.label, 'Unlock with Touch ID');
    });

    test(
      'fingerprint on Android reads the Android wording, per the variant table',
      () {
        final result = biometricPresentation([
          BiometricType.fingerprint,
        ], isIOS: false);
        expect(result.glyph, Symbols.fingerprint_rounded);
        expect(result.label, 'Unlock with your fingerprint');
      },
    );

    test('iris reads the one wording the table gives, per R-22-070', () {
      final result = biometricPresentation([BiometricType.iris], isIOS: false);
      expect(result.glyph, Symbols.visibility_rounded);
      expect(result.label, 'Unlock with iris');
    });

    test('strong or weak only, on either platform, falls back to the generic glyph and label '
        '(R-22-070, R-31-04-07)', () {
      for (final type in [BiometricType.strong, BiometricType.weak]) {
        for (final isIOS in [true, false]) {
          final result = biometricPresentation([type], isIOS: isIOS);
          expect(result.glyph, Symbols.lock_rounded);
          expect(result.label, 'Unlock with biometrics');
        }
      }
    });

    test('an empty report, on either platform, also falls back to generic', () {
      for (final isIOS in [true, false]) {
        final result = biometricPresentation([], isIOS: isIOS);
        expect(result.glyph, Symbols.lock_rounded);
        expect(result.label, 'Unlock with biometrics');
      }
    });

    test('face is preferred over fingerprint when a device reports both', () {
      final result = biometricPresentation([
        BiometricType.fingerprint,
        BiometricType.face,
      ], isIOS: true);
      expect(result.label, 'Unlock with Face ID');
    });
  });

  testWidgets('draws the branded blocking-state anatomy', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LockScreenBody(
          phase: LockScreenPhase.rejected,
          biometric: BiometricPresentation(
            glyph: Symbols.fingerprint_rounded,
            label: 'Unlock with your fingerprint',
          ),
        ),
      ),
    );

    expect(find.byType(GroundGrid), findsOneWidget);
    expect(find.byType(BrandMark), findsOneWidget);
    expect(find.byType(Eyebrow), findsOneWidget);
    expect(find.text('LOCKED'), findsOneWidget);
    expect(find.text('Herdr Remote'), findsOneWidget);
    expect(find.text('Unlock with your fingerprint'), findsOneWidget);
    expect(find.text('Use device passcode'), findsOneWidget);
  });
  group('no secret identifiers on screen (R-31-04-05)', () {
    testWidgets('no phase, offline or not, ever renders a relay address, a routing handle, a pairing '
        'phrase or a key fingerprint', (tester) async {
      const biometric = BiometricPresentation(
        glyph: Symbols.fingerprint_rounded,
        label: 'Unlock with your fingerprint',
      );
      const forbidden = ['relay', 'pairing', 'routing', 'key fingerprint'];

      for (final phase in LockScreenPhase.values) {
        for (final offline in [false, true]) {
          await tester.pumpWidget(
            MaterialApp(
              home: LockScreenBody(
                phase: phase,
                biometric: biometric,
                offline: offline,
              ),
            ),
          );

          final rendered = tester
              .widgetList<Text>(find.byType(Text))
              .map((text) => text.data ?? '')
              .join('\n')
              .toLowerCase();

          for (final term in forbidden) {
            expect(
              rendered.contains(term),
              isFalse,
              reason: '"$term" found in $phase (offline: $offline): $rendered',
            );
          }
        }
      }
    });
  });
}
