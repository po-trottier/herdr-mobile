/// Non-golden structural/unit coverage for `app/lib/screens/lock_screen.dart` (`WP-13-b`).
///
/// `biometricPresentation()` is a pure function, so a plain `test()` on its return value is
/// the direct proof, per `docs/31-mockups/04-lock.md`'s variant table (R-31-04-06, R-32-407):
/// the reported [BiometricType] picks the glyph and which label applies, and the platform
/// picks only that label's wording. `lock_screen_golden_test.dart` renders every screen
/// *state* with one fixed biometric presentation; it does not exercise this function's own
/// type-and-platform branching, which is this file's job.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter/scheduler.dart' show SchedulerPhase;
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:flutter/widgets.dart' show AppLifecycleState, SizedBox, Text;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart';
import 'package:herdr_mobile/screens/lock_screen.dart';
import 'package:herdr_mobile/services/biometric_gate.dart';
import 'package:herdr_mobile/widgets/brand_mark.dart';
import 'package:herdr_mobile/widgets/eyebrow.dart';
import 'package:herdr_mobile/widgets/ground_grid.dart';
import 'package:local_auth/local_auth.dart' show BiometricType;
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart' show MaterialApp;
import 'package:mocktail/mocktail.dart';

import '../frame_presentation_support.dart';

class _MockBiometricGate extends Mock implements BiometricGate {}

void main() {
  group('authentication starts after the lock page is drawn', () {
    const connectivity = MethodChannel(
      'dev.fluttercommunity.plus/connectivity',
    );
    const presentation = MethodChannel('dev.herdr.herdr_mobile/biometric_lock');
    late _MockBiometricGate gate;
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized()
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      gate = _MockBiometricGate();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(presentation, (_) async => null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(connectivity, (_) async => ['wifi']);
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(presentation, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(connectivity, null);
    });
    testWidgets('Face ID begins with the lock icon and unlock text visible', (
      tester,
    ) async {
      when(() => gate.availableBiometrics())
          .thenAnswer((_) async => [BiometricType.face]);
      final visibleAtUnlock = <bool>[];
      when(() => gate.unlock()).thenAnswer((_) async {
        visibleAtUnlock.add(
          find.byIcon(Symbols.lock_rounded).evaluate().isNotEmpty &&
              find.text('Unlock to continue.').evaluate().isNotEmpty &&
              tester.binding.schedulerPhase !=
                  SchedulerPhase.persistentCallbacks,
        );
        return const Ok<void>(null);
      });
      await tester.pumpWidget(MaterialApp(home: LockScreen(gate: gate)));
      await tester.pump();
      // A built widget tree is not proof that the engine displayed its pixels.
      expect(visibleAtUnlock, isEmpty);
      reportRaster(tester, frameNumber: -2); // An older, blank bootstrap frame.
      await tester.pump();
      expect(visibleAtUnlock, isEmpty);
      reportRaster(tester);
      await tester.pump();
      expect(visibleAtUnlock, [true]);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
    testWidgets('Face ID waits for the native launch screen to disappear', (
      tester,
    ) async {
      final displayed = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(presentation, (call) async {
            if (call.method == 'waitUntilDisplayed') await displayed.future;
            return null;
          });
      when(() => gate.availableBiometrics())
          .thenAnswer((_) async => [BiometricType.face]);
      when(() => gate.unlock()).thenAnswer((_) async => const Ok<void>(null));
      await tester.pumpWidget(MaterialApp(home: LockScreen(gate: gate)));
      await tester.pump();
      reportRaster(tester);
      await tester.pump();
      verifyNever(() => gate.unlock());
      displayed.complete();
      await tester.pump();
      verify(() => gate.unlock()).called(1);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('pending display acknowledgment waits until the app resumes', (
      tester,
    ) async {
      final displayed = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(presentation, (call) async {
            if (call.method == 'waitUntilDisplayed') await displayed.future;
            return null;
          });
      when(() => gate.availableBiometrics())
          .thenAnswer((_) async => [BiometricType.face]);
      when(() => gate.unlock()).thenAnswer((_) async => const Ok<void>(null));
      await tester.pumpWidget(MaterialApp(home: LockScreen(gate: gate)));
      await tester.pump();
      reportRaster(tester);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      displayed.complete();
      await tester.pump();
      verifyNever(() => gate.unlock());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      verify(() => gate.unlock()).called(1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      verifyNever(() => gate.unlock());
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('disposing while a raster is pending cancels authentication', (
      tester,
    ) async {
      when(() => gate.availableBiometrics())
          .thenAnswer((_) async => [BiometricType.face]);
      when(() => gate.unlock()).thenAnswer((_) async => const Ok<void>(null));
      await tester.pumpWidget(MaterialApp(home: LockScreen(gate: gate)));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      reportRaster(tester);
      await tester.pump();
      verifyNever(() => gate.unlock());
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('leaving before the page is ready does not raise Face ID', (
      tester,
    ) async {
      final types = Completer<List<BiometricType>>();
      when(() => gate.availableBiometrics()).thenAnswer((_) => types.future);
      when(() => gate.unlock()).thenAnswer((_) async => const Ok<void>(null));
      await tester.pumpWidget(MaterialApp(home: LockScreen(gate: gate)));
      await tester.pumpWidget(const SizedBox());
      types.complete([BiometricType.face]);
      await tester.pump();
      verifyNever(() => gate.unlock());
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
    testWidgets(
      'capability lookup failure still permits the real keychain unlock',
      (tester) async {
        when(() => gate.availableBiometrics())
            .thenThrow(PlatformException(code: 'unavailable'));
        when(() => gate.unlock()).thenAnswer((_) async => const Ok<void>(null));
        await tester.pumpWidget(MaterialApp(home: LockScreen(gate: gate)));
        await tester.pump();
        reportRaster(tester);
        await tester.pump();
        verify(() => gate.unlock()).called(1);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
    testWidgets(
      'a manual attempt while capabilities load is not followed by another prompt',
      (tester) async {
        final types = Completer<List<BiometricType>>();
        when(() => gate.availableBiometrics()).thenAnswer((_) => types.future);
        when(
          () => gate.unlock(),
        ).thenAnswer((_) async => const Err<void>('Authentication cancelled'));
        await tester.pumpWidget(MaterialApp(home: LockScreen(gate: gate)));
        await tester.tap(find.text('Use device passcode'));
        await tester.pump();
        verifyNever(() => gate.unlock());

        types.complete([BiometricType.face]);
        await tester.pumpAndSettle();
        verifyNever(() => gate.unlock());
        reportRaster(tester);
        await tester.pumpAndSettle();
        verify(() => gate.unlock()).called(1);
        expect(find.text('Not recognised. Try again.'), findsOneWidget);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  });

  group('biometricPresentation', () {
    test('face on iOS reads the iOS wording, per the variant table', () {
      final result = biometricPresentation([BiometricType.face], isIOS: true);
      expect(result.glyph, Symbols.lock_rounded);
      expect(result.label, 'Unlock with Face ID');
    });

    test(
      'face on Android reads the Android wording, per the variant table',
      () {
        final result = biometricPresentation([
          BiometricType.face,
        ], isIOS: false);
        expect(result.glyph, Symbols.lock_rounded);
        expect(result.label, 'Unlock with face unlock');
      },
    );

    test('fingerprint on iOS reads the iOS wording, per the variant table', () {
      final result = biometricPresentation([
        BiometricType.fingerprint,
      ], isIOS: true);
      expect(result.glyph, Symbols.lock_rounded);
      expect(result.label, 'Unlock with Touch ID');
    });

    test(
      'fingerprint on Android reads the Android wording, per the variant table',
      () {
        final result = biometricPresentation([
          BiometricType.fingerprint,
        ], isIOS: false);
        expect(result.glyph, Symbols.lock_rounded);
        expect(result.label, 'Unlock with your fingerprint');
      },
    );

    test('iris reads the one wording the table gives, per R-22-070', () {
      final result = biometricPresentation([BiometricType.iris], isIOS: false);
      expect(result.glyph, Symbols.lock_rounded);
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
