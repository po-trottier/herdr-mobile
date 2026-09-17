/// Real iOS renderer and native launch-screen barrier, with a held Keychain fixture.
/// WP-13-b. No real key, Host, network session or biometric prompt is used.
library;

import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/app.dart'
    show ResolvedChrome, appThemeFrom, sdkMaterialLocalizations;
import 'package:herdr_mobile/core/result/result.dart';
import 'package:herdr_mobile/screens/lock_screen.dart';
import 'package:herdr_mobile/services/biometric_gate.dart';
import 'package:herdr_mobile/services/keystore.dart';
import 'package:herdr_mobile/widgets/theme/chrome_scheme.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart' show MaterialApp;
import 'package:mocktail/mocktail.dart';

class _Keystore extends Mock implements KeystoreService {}

class _LocalAuth extends Mock implements LocalAuthentication {}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('landscape entry becomes portrait before the first key read', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
    ]);
    for (
      var attempt = 0;
      attempt < 50 &&
          tester.view.physicalSize.width <= tester.view.physicalSize.height;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      tester.view.physicalSize.width,
      greaterThan(tester.view.physicalSize.height),
    );
    final store = _Keystore();
    final auth = _LocalAuth();
    final challenge = Completer<Result<SimpleKeyPair>>();
    final captured = Completer<void>();
    var reads = 0;
    late Size pageSizeAtRead;
    var promptVisibleAtRead = false;
    when(auth.getAvailableBiometrics)
        .thenAnswer((_) async => [BiometricType.face]);
    when(store.existingDeviceKeyPair).thenAnswer((_) async {
      reads++;
      promptVisibleAtRead =
          find.byIcon(Symbols.lock_rounded).evaluate().isNotEmpty &&
          find.text('Unlock to continue.').evaluate().isNotEmpty;
      // This callback can run during pump; read layout directly instead of calling
      // guarded WidgetTester APIs from another asynchronous test scope.
      pageSizeAtRead =
          (find.byType(LockScreenBody).evaluate().single.findRenderObject()!
                  as RenderBox)
              .size;
      // The native plugin captures the UIWindow, including any launch/privacy cover.
      await binding.takeScreenshot('lock-before-authentication');
      captured.complete();
      return challenge.future;
    });
    final gate = BiometricGate(
      appLockEnabled: true,
      keystore: store,
      localAuth: auth,
    );
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: appThemeFrom(ChromeScheme.fixed(Brightness.dark)),
        localizationsDelegates: sdkMaterialLocalizations,
        builder: (_, child) => ResolvedChrome(child: child!),
        home: LockScreen(gate: gate),
      ),
    );
    await tester.pumpAndSettle();
    for (var attempt = 0; attempt < 100 && !captured.isCompleted; attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await captured.future.timeout(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(promptVisibleAtRead, isTrue);
    expect(pageSizeAtRead.height, greaterThan(pageSizeAtRead.width));
    await tester.tap(find.text('Use device passcode'));
    await tester.tap(find.text('Use device passcode'));
    await tester.pumpAndSettle();
    expect(reads, 1);
    challenge.complete(const Err('Fixture cancellation'));
    await tester.pumpAndSettle();
    expect(find.text('Not recognised. Try again.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    gate.dispose();
  });
}
