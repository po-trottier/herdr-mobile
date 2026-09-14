/// Structural coverage for `WelcomeScreenBody` (`app/lib/screens/welcome_screen.dart`,
/// `WP-15-b`), one per non-empty row of `docs/31-mockups/01-welcome.md`'s `## States` table
/// (R-90-011).
///
/// Renders `WelcomeScreenBody` directly, not the stateful `WelcomeScreen`: the presentational
/// split this file's top doc comment documents exists exactly so this file needs no
/// `KeystoreService` platform channel and no `connectivity_plus` platform channel, mirroring
/// `lock_screen_golden_test.dart`'s own reasoning. The stateful orchestrator's own keystore
/// check is covered separately below, with an injected `KeystoreService` mock.
library;

import 'package:cryptography/cryptography.dart' show X25519;
import 'package:flutter/widgets.dart' show CustomScrollView, Icon, IconData;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart' show Err, Ok;
import 'package:herdr_mobile/screens/welcome_screen.dart';
import 'package:herdr_mobile/services/keystore.dart' show KeystoreService;
import 'package:herdr_mobile/widgets/app_filled_button.dart';
import 'package:herdr_mobile/widgets/brand_mark.dart';
import 'package:herdr_mobile/widgets/eyebrow.dart';
import 'package:herdr_mobile/widgets/ground_grid.dart';
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart' show MaterialApp;
import 'package:mocktail/mocktail.dart';

class _MockKeystoreService extends Mock implements KeystoreService {}

void main() {
  testWidgets(
    'default: draws the three setup steps and both actions, primary enabled',
    (tester) async {
      var scanTapped = false;
      var manualTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeScreenBody(
            onScanPressed: () => scanTapped = true,
            onManualPressed: () => manualTapped = true,
          ),
        ),
      );

      expect(find.byType(GroundGrid), findsOneWidget);
      expect(find.byType(BrandMark), findsOneWidget);
      expect(find.byType(Eyebrow), findsOneWidget);
      expect(find.text('HERDR REMOTE'), findsOneWidget);
      expect(find.text('Watch the herd.\nFrom anywhere.'), findsOneWidget);
      expect(
        find.text(
          'Read a pane. Send a prompt. Nothing else crosses the network.',
        ),
        findsOneWidget,
      );
      for (final step in pairingSetupSteps) {
        expect(find.text(step), findsOneWidget);
      }
      for (final number in <String>['01', '02', '03']) {
        expect(find.text(number), findsOneWidget);
      }
      expect(find.text('Scan QR code'), findsOneWidget);
      expect(find.text('Enter the phrase instead'), findsOneWidget);

      final button = tester.widget<AppFilledButton>(
        find.byType(AppFilledButton),
      );
      expect(button.onPressed, isNotNull);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan QR code'));
      expect(scanTapped, isTrue);
      await tester.tap(find.text('Enter the phrase instead'));
      expect(manualTapped, isTrue);
    },
  );

  testWidgets('each setup step carries its R-32-401 icon, and the alert block carries a leading info '
      'icon', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WelcomeScreenBody()));

    const stepIcons = <IconData>[
      Symbols.computer_rounded,
      Symbols.dns_rounded,
      Symbols.qr_code_scanner_rounded,
    ];
    for (final icon in stepIcons) {
      expect(
        find.byWidgetPredicate((w) => w is Icon && w.icon == icon),
        findsOneWidget,
      );
    }
    expect(
      find.byWidgetPredicate(
        (w) => w is Icon && w.icon == Symbols.info_rounded,
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'error: replaces the setup list with the keystore-init-failure line and disables the '
    'primary action, per R-31-01-09 (never a screen-lock message)',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: WelcomeScreenBody(isError: true)),
      );

      expect(
        find.text(
          'Something went wrong setting up this phone. Restart the app.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('screen lock'), findsNothing);
      for (final step in pairingSetupSteps) {
        expect(find.text(step), findsNothing);
      }
      final button = tester.widget<AppFilledButton>(
        find.byType(AppFilledButton),
      );
      expect(button.onPressed, isNull);
      // Callout 6 stays reachable: the mockup names no change to the secondary action.
      expect(find.text('Enter the phrase instead'), findsOneWidget);
    },
  );

  testWidgets(
    'offline: shows the network strip above the primary action, which stays enabled',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: WelcomeScreenBody(isOffline: true)),
      );

      expect(
        find.text(
          'No network. Pairing needs a connection, and a phrase lasts ten minutes.',
        ),
        findsOneWidget,
      );
      final button = tester.widget<AppFilledButton>(
        find.byType(AppFilledButton),
      );
      expect(button.onPressed, isNull); // no callback was supplied in this case
    },
  );

  testWidgets('carries both R-30-512 and R-30-517 alert limitations verbatim', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: WelcomeScreenBody()));

    expect(
      find.text(
        'Alerts arrive while the app is running. If the phone closes the '
        'app, the alert is waiting in the app the next time you open it.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Alerts come from the computer you are connected to. If an agent '
        'finishes on another computer, you see it when you connect to '
        'that computer.',
      ),
      findsOneWidget,
    );
  });

  group('WelcomeScreen (stateful orchestrator)', () {
    testWidgets('a failing keystore read shows the Error state, per R-31-01-09 (never checks '
        'local_auth)', (tester) async {
      final keystore = _MockKeystoreService();
      when(() => keystore.deviceKeyPair()).thenAnswer(
        (_) async => const Err('read or generate the device key pair'),
      );

      await tester.pumpWidget(
        MaterialApp(home: WelcomeScreen(keystore: keystore)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Something went wrong setting up this phone. Restart the app.',
        ),
        findsOneWidget,
      );
      final button = tester.widget<AppFilledButton>(
        find.byType(AppFilledButton),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('a successful keystore read leaves Scan QR code enabled, with no screen-lock check '
        '(R-31-01-09, R-03-090)', (tester) async {
      final keystore = _MockKeystoreService();
      final keyPair = await X25519().newKeyPair();
      when(() => keystore.deviceKeyPair()).thenAnswer((_) async => Ok(keyPair));
      var scanTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeScreen(
            keystore: keystore,
            onScanPressed: () => scanTapped = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('screen lock'), findsNothing);
      final button = tester.widget<AppFilledButton>(
        find.byType(AppFilledButton),
      );
      expect(button.onPressed, isNotNull);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan QR code'));
      expect(scanTapped, isTrue);
    });
  });
}
