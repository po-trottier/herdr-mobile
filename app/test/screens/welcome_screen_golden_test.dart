/// Golden tests for `WelcomeScreenBody` (`app/lib/screens/welcome_screen.dart`, `WP-15-b`), one
/// per non-empty row of `docs/31-mockups/01-welcome.md`'s `## States` table (R-90-011), each
/// rendered in both Selenized dark and light (R-32-012).
///
/// Renders `WelcomeScreenBody` directly, not the stateful `WelcomeScreen`, for the same reason
/// `lock_screen_golden_test.dart` renders `LockScreenBody`: the presentational split needs no
/// `KeystoreService` and no `connectivity_plus` platform channel, so every state is one fixed
/// constructor call.
///
/// `Image.asset` decodes off the test's fake async zone, so the first golden in a file used to
/// paint no brand mark while every later one, served from the image cache, did.
/// `precacheBrandMark` waits for the decode under `tester.runAsync` before the frame is compared.
///
/// Fonts, the app theme, the 375 x 667 reference size and that precache come from
/// `golden_support.dart`.
library;

import 'package:flutter/widgets.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/screens/welcome_screen.dart';

import 'golden_support.dart';

class _Case {
  const _Case(this.name, {this.isError = false, this.isOffline = false});
  final String name;
  final bool isError;
  final bool isOffline;
}

/// One entry per named row of the mockup's `## States` table. `Loading` is "not applicable" and
/// `Empty` is "same as default", so neither gets a golden of its own.
const _cases = <_Case>[
  _Case('default'),
  _Case('error', isError: true),
  _Case('offline', isOffline: true),
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
        '${testCase.name} ($themeName) matches docs/31-mockups/01-welcome.md',
        (tester) async {
          tester.view.physicalSize = goldenReferenceSize;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            goldenApp(
              brightness: brightness,
              child: WelcomeScreenBody(
                isError: testCase.isError,
                isOffline: testCase.isOffline,
                onScanPressed: () {},
                onManualPressed: () {},
              ),
            ),
          );
          await precacheBrandMark(tester, find.byType(WelcomeScreenBody));
          await tester.pumpAndSettle();

          expect(find.text('Watch the herd.\nFrom anywhere.'), findsOneWidget);
          expect(find.text('Scan QR code'), findsOneWidget);
          expect(find.text('Enter the phrase instead'), findsOneWidget);
          for (final step in pairingSetupSteps) {
            expect(find.text(step), findsNWidgets(testCase.isError ? 0 : 1));
          }

          await expectLater(
            find.byType(WelcomeScreenBody),
            matchesGoldenFile(
              'goldens/welcome_screen_${testCase.name}_$themeName.png',
            ),
          );
        },
      );
    }
  }
}
