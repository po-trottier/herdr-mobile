/// Golden tests for `QrScanScreenBody` (`app/lib/screens/qr_scan_screen.dart`, `WP-15-b`), one
/// per row of `docs/31-mockups/02-pair-scan.md`'s `## States` table that the pure body can reach
/// with no `mobile_scanner` platform channel (R-90-011), each in both Selenized dark and light
/// (R-32-012). The sheet-based failures open a modal route from the stateful orchestrator, so
/// they are not bodies this file can construct.
///
/// Every case passes `controller: null`, so `_Viewfinder` paints the scrim and the corner marks
/// over the ground grid and no camera preview. That makes the scrim measurable: the grid lines
/// inside the frame stay at full contrast and the lines outside sit under `opacity.dim`.
///
/// The `pairing` case runs the corner-mark fade of the mockup's `Loading, pairing` row, a
/// repeating animation `pumpAndSettle` would never settle, so that case pumps exactly one
/// `motion.duration.slow` and captures the far end of the fade, `color.fg.secondary`.
///
/// Fonts, the app theme and the 375 x 667 reference size come from `golden_support.dart`.
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/screens/qr_scan_screen.dart';
import 'package:herdr_mobile/widgets/theme/app_motion.dart' show AppMotion;

import 'golden_support.dart';

class _Case {
  const _Case(
    this.name,
    this.phase, {
    this.hasConnectedHost = false,
    this.torchOn = false,
    this.hint,
    this.offline = false,
    this.fingerprintText,
    this.ios = false,
  });
  final String name;
  final QrScanPhase phase;
  final bool hasConnectedHost;
  final bool torchOn;
  final QrHintIssue? hint;
  final bool offline;
  final String? fingerprintText;
  final bool ios;
}

const _cases = <_Case>[
  _Case('default', QrScanPhase.ready),
  _Case('default_ios', QrScanPhase.ready, ios: true),
  _Case('connected', QrScanPhase.ready, hasConnectedHost: true),
  _Case('torch_on', QrScanPhase.ready, torchOn: true),
  _Case('camera_starting', QrScanPhase.cameraStarting),
  _Case('pairing', QrScanPhase.pairing),
  _Case('camera_unavailable', QrScanPhase.cameraUnavailable),
  _Case('permission_denied', QrScanPhase.permissionDenied),
  _Case(
    'not_ours',
    QrScanPhase.ready,
    hint: QrHintIssue('That is not a Herdr pairing code.'),
  ),
  _Case('offline', QrScanPhase.ready, offline: true),
  _Case(
    'paired',
    QrScanPhase.ready,
    fingerprintText: 'ab12 cd34 ef56 7890 ab12 cd34 ef56 7890',
  ),
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
        '${testCase.name} ($themeName) matches docs/31-mockups/02-pair-scan.md',
        (tester) async {
          tester.view.physicalSize = goldenReferenceSize;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          // Reset inside the body: the binding checks foundation debug variables before
          // `addTearDown` callbacks run.
          if (testCase.ios) {
            debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
          }

          await tester.pumpWidget(
            goldenApp(
              brightness: brightness,
              child: QrScanScreenBody(
                phase: testCase.phase,
                hasConnectedHost: testCase.hasConnectedHost,
                torchOn: testCase.torchOn,
                hint: testCase.hint,
                offline: testCase.offline,
                fingerprintText: testCase.fingerprintText,
                onFlashToggle: () {},
                onManualEntry: () {},
                onHelp: () {},
                onOpenSettings: () {},
              ),
            ),
          );
          if (testCase.phase == QrScanPhase.pairing) {
            await tester.pump();
            await tester.pump(AppMotion.durationSlow);
          } else {
            await tester.pumpAndSettle();
          }

          expect(find.text('Pair a computer'), findsOneWidget);
          expect(find.text('Type it in'), findsOneWidget);
          expect(
            find.text('Pairing disconnects the computer you are using now.'),
            findsNWidgets(testCase.hasConnectedHost ? 1 : 0),
          );
          expect(
            find.text('Open Settings'),
            findsNWidgets(
              testCase.phase == QrScanPhase.permissionDenied ? 1 : 0,
            ),
          );

          await expectLater(
            find.byType(QrScanScreenBody),
            matchesGoldenFile(
              'goldens/qr_scan_screen_${testCase.name}_$themeName.png',
            ),
          );
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }
  }
}
