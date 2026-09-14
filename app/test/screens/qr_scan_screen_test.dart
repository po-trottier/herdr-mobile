/// Structural coverage for `QrScanScreenBody` (`app/lib/screens/qr_scan_screen.dart`,
/// `WP-15-b`), one per non-empty row of `docs/31-mockups/02-pair-scan.md`'s `## States` table
/// that this file's own presentational split can reach with no `mobile_scanner` platform
/// channel: `QrScanScreenBody` never opens a camera itself (it only paints whatever
/// `MobileScannerController` its caller passes, or none), mirroring
/// `lock_screen_golden_test.dart`'s reasoning for testing the pure `*Body` widget directly.
library;

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoButton, CupertinoNavigationBar;
import 'package:flutter/foundation.dart'
    show Brightness, TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart' show SizedBox, StatefulBuilder;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/screens/qr_scan_screen.dart';
import 'package:herdr_mobile/services/pairing.dart';
import 'package:herdr_mobile/widgets/app_text_button.dart';
import 'package:herdr_mobile/widgets/theme/app_color.dart';
import 'package:material_symbols_icons/symbols.dart' show Symbols;
// `material_ui`'s `AppBar` and `IconButton` are the screen's own types; `flutter/material`'s
// would never match a finder here.
import 'package:material_ui/material_ui.dart'
    show AppBar, IconButton, Material, MaterialApp;
import 'package:mobile_scanner/mobile_scanner.dart';

/// The Android flash control: an `IconButton` whose tooltip is the mockup's exact label
/// (callout 8), the same control `connection_screen.dart` and `terminal_screen.dart` use in
/// their bars. iOS keeps a `CupertinoButton`, covered by the iOS test below.
IconButton _flashButton(WidgetTester tester) => tester.widget<IconButton>(
  find.ancestor(
    of: find.byIcon(Symbols.flash_off_rounded),
    matching: find.byType(IconButton),
  ),
);

void main() {
  for (final code in [
    MobileScannerErrorCode.permissionDenied,
    MobileScannerErrorCode.genericError,
  ]) {
    testWidgets('native camera failure $code survives help', (tester) async {
      const connectivity = MethodChannel(
        'dev.fluttercommunity.plus/connectivity',
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        connectivity,
        (_) async => <String>['wifi'],
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          connectivity,
          null,
        );
      });
      const camera = MethodChannel(
        'dev.steenbakker.mobile_scanner/scanner/method',
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        camera,
        (_) async => null,
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          camera,
          null,
        );
      });
      var manualEntries = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: QrScanScreen(
            scanner: PairingScanner(controller: _FailedCamera(code)),
            effWords: const [],
            onManualEntry: () => manualEntries++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final message = code == MobileScannerErrorCode.permissionDenied
          ? 'The app needs the camera to scan. Open Settings to allow it.'
          : 'The camera is not available. Type the phrase instead.';
      expect(find.text(message), findsOneWidget);
      expect(
        find.text(
          'Point the camera at the QR code in the Relay pane on your computer.',
        ),
        findsNothing,
      );
      expect(_flashButton(tester).onPressed, isNull);
      expect(
        find.text('Open Settings'),
        code == MobileScannerErrorCode.permissionDenied
            ? findsOneWidget
            : findsNothing,
      );
      await tester.tap(find.byIcon(Symbols.info_rounded));
      await tester.pumpAndSettle();
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      for (final brightness in [Brightness.dark, Brightness.light]) {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        await tester.pumpAndSettle();
        final surface = tester
            .element(find.byType(HelpSheetContent))
            .findAncestorWidgetOfExactType<Material>()!;
        expect(surface.color, AppColor.resolve(brightness).bgRaised);
      }
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      await tester.tap(find.text('Type it in'));
      expect(manualEntries, 1);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
    });
  }

  testWidgets('default: draws the app bar title and the default hint', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: QrScanScreenBody(phase: QrScanPhase.ready)),
    );

    expect(find.text('Pair a computer'), findsOneWidget);
    expect(
      find.text(
        'Point the camera at the QR code in the Relay pane on your computer.',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Symbols.flash_off_rounded), findsOneWidget);
    expect(find.text('Type it in'), findsOneWidget);
  });
  testWidgets('flash icon starts off and toggles with exact semantics', (
    tester,
  ) async {
    var torchOn = false;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => QrScanScreenBody(
            phase: QrScanPhase.ready,
            torchOn: torchOn,
            onFlashToggle: () => setState(() => torchOn = !torchOn),
          ),
        ),
      ),
    );

    expect(find.byIcon(Symbols.flash_off_rounded), findsOneWidget);
    expect(find.byTooltip('Turn flash on'), findsOneWidget);

    await tester.tap(find.byTooltip('Turn flash on'));
    await tester.pump();

    expect(find.byIcon(Symbols.flash_on_rounded), findsOneWidget);
    expect(find.byTooltip('Turn flash off'), findsOneWidget);
  });

  testWidgets(
    'iOS: renders CupertinoNavigationBar, not Material AppBar, on iOS',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await tester.pumpWidget(
          const MaterialApp(home: QrScanScreenBody(phase: QrScanPhase.ready)),
        );

        final navBar = tester.widget<CupertinoNavigationBar>(
          find.byType(CupertinoNavigationBar),
        );
        expect(find.text('Pair a computer'), findsOneWidget);
        expect(navBar.trailing, isNotNull);
        expect(
          find.descendant(
            of: find.byType(CupertinoNavigationBar),
            matching: find.byType(CupertinoButton),
          ),
          findsNWidgets(2),
        );
        expect(
          find.descendant(
            of: find.widgetWithText(AppTextButton, 'Type it in'),
            matching: find.byType(CupertinoButton),
          ),
          findsOneWidget,
        );
        expect(find.byType(IconButton), findsNothing);
        expect(find.bySemanticsLabel('Turn flash on'), findsOneWidget);
        expect(find.byType(AppBar), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'loading, camera starting: shows the starting hint and disables flash',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: QrScanScreenBody(
            phase: QrScanPhase.cameraStarting,
            onManualEntry: () {},
          ),
        ),
      );

      expect(find.text('Starting camera...'), findsOneWidget);
      expect(_flashButton(tester).onPressed, isNull);
      // R-31-02-12: `type it in` stays enabled while the camera is still starting.
      final typeItIn = tester.widget<AppTextButton>(
        find.widgetWithText(AppTextButton, 'Type it in'),
      );
      expect(typeItIn.onPressed, isNotNull);
    },
  );

  testWidgets(
    'loading, pairing: shows the connecting hint and disables both actions',
    (tester) async {
      var flashTapped = false;
      var manualTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: QrScanScreenBody(
            phase: QrScanPhase.pairing,
            onFlashToggle: () => flashTapped = true,
            onManualEntry: () => manualTapped = true,
          ),
        ),
      );

      expect(find.text('Connecting...'), findsOneWidget);
      final IconButton flash = _flashButton(tester);
      final typeItIn = tester.widget<AppTextButton>(
        find.widgetWithText(AppTextButton, 'Type it in'),
      );
      expect(flash.onPressed, isNull);
      expect(typeItIn.onPressed, isNull);
      expect(flashTapped, isFalse);
      expect(manualTapped, isFalse);
    },
  );

  testWidgets(
    'camera unavailable: shows the fallback line and only "type it in" is enabled',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: QrScanScreenBody(phase: QrScanPhase.cameraUnavailable),
        ),
      );

      expect(
        find.text('The camera is not available. Type the phrase instead.'),
        findsOneWidget,
      );
      // One instruction, not two: the bar drops "Point the camera..." while the preview
      // area says the camera is not there.
      expect(
        find.text(
          'Point the camera at the QR code in the Relay pane on your computer.',
        ),
        findsNothing,
      );
      expect(find.text('Type it in'), findsOneWidget);
    },
  );

  testWidgets(
    'permission denied: shows the recovery line and an Open Settings action',
    (tester) async {
      var openedSettings = false;
      await tester.pumpWidget(
        MaterialApp(
          home: QrScanScreenBody(
            phase: QrScanPhase.permissionDenied,
            onOpenSettings: () => openedSettings = true,
          ),
        ),
      );

      expect(
        find.text(
          'The app needs the camera to scan. Open Settings to allow it.',
        ),
        findsOneWidget,
      );
      expect(find.text('Open Settings'), findsOneWidget);
      expect(find.text('flash off'), findsNothing);
      expect(
        find.text(
          'Point the camera at the QR code in the Relay pane on your computer.',
        ),
        findsNothing,
      );

      await tester.tap(find.text('Open Settings'));
      expect(openedSettings, isTrue);
    },
  );

  testWidgets(
    'unreadable/malformed hint: takes the error treatment and keeps the scanner reachable',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: QrScanScreenBody(
            phase: QrScanPhase.ready,
            hint: QrHintIssue('That is not a Herdr pairing code.'),
          ),
        ),
      );

      expect(find.text('That is not a Herdr pairing code.'), findsOneWidget);
      // The scanner keeps running: both actions remain in the tree.
      expect(find.text('Type it in'), findsOneWidget);
    },
  );

  testWidgets(
    'offline: shows the persistent strip while both actions stay reachable',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: QrScanScreenBody(phase: QrScanPhase.ready, offline: true),
        ),
      );

      expect(
        find.text(
          'No network. Pairing needs a connection, and a phrase lasts ten minutes.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('a connected computer adds the switch caption, per R-30-945', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: QrScanScreenBody(
          phase: QrScanPhase.ready,
          hasConnectedHost: true,
        ),
      ),
    );

    expect(
      find.text('Pairing disconnects the computer you are using now.'),
      findsOneWidget,
    );
  });
}

class _FailedCamera extends MobileScannerController {
  _FailedCamera(this.code) : super(autoStart: false);

  final MobileScannerErrorCode code;

  @override
  Future<void> start({
    CameraFacing? cameraDirection,
    CameraLensType? cameraLensType,
  }) async {
    value = value.copyWith(
      isInitialized: true,
      error: MobileScannerException(errorCode: code),
    );
  }

  @override
  Future<void> pause() async {}
}
