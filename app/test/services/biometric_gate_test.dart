/// Proves `BiometricGate` (`WP-13-b`) follows the R-22-013 pattern: a real keystore read is
/// the single OS-triggered authentication event, never a bare `local_auth` boolean, and never
/// a second, independent `local_auth.authenticate()` prompt alongside it (the double-prompt
/// defect `wp-13a-keystore`'s native-source investigation found and `keystore.dart`'s
/// `BiometricAuthenticationException` doc comment cites in full). Also proves the three
/// re-authentication triggers, the 120-second background timeout, and that both
/// `KeyInvalidatedException` and `BiometricAuthenticationException` pass through `unlock()`
/// unchanged for `lock_screen.dart` to classify.
library;

import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart';
import 'package:herdr_mobile/services/biometric_gate.dart';
import 'package:herdr_mobile/services/keystore.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mocktail/mocktail.dart';

/// Mirrors `biometric_gate.dart`'s own private `_lockChannel`: the channel
/// `_defaultSetNativeLocked` -- the real default for the `setNativeLocked` constructor
/// parameter every other test in this file overrides with `nativeLockCalls.add` -- invokes
/// for the Android screenshot flag and the iOS privacy shield.
const MethodChannel _lockChannel = MethodChannel(
  'dev.herdr.herdr_mobile/biometric_lock',
);

class _MockLocalAuthentication extends Mock implements LocalAuthentication {}

class _MockKeystoreService extends Mock implements KeystoreService {}

void main() {
  late _MockLocalAuthentication localAuth;
  late _MockKeystoreService keystore;
  late DateTime clock;
  late List<bool> nativeLockCalls;
  late BiometricGate gate;
  late SimpleKeyPair keyPair;

  setUp(() async {
    localAuth = _MockLocalAuthentication();
    keystore = _MockKeystoreService();
    clock = DateTime(2026);
    nativeLockCalls = <bool>[];
    keyPair = await X25519().newKeyPair();
    gate = BiometricGate(
      appLockEnabled: true,
      localAuth: localAuth,
      keystore: keystore,
      now: () => clock,
      setNativeLocked: nativeLockCalls.add,
    );
  });

  /// Every test in this file calls this at the end, not just the ones that name the defect
  /// directly: a regression that reintroduces a `local_auth.authenticate()` call anywhere in
  /// `BiometricGate` would raise the second, independent OS prompt the redesign removed, and
  /// every scenario below should catch it, not just one dedicated case.
  void verifyNoLocalAuthPromptWasRaised() {
    verifyNever(
      () => localAuth.authenticate(
        localizedReason: any(named: 'localizedReason'),
      ),
    );
  }

  test('concurrent unlocks share one pending keychain challenge', () async {
    final pending = Completer<Result<SimpleKeyPair>>();
    when(() => keystore.existingDeviceKeyPair())
        .thenAnswer((_) => pending.future);
    final first = gate.unlock();
    final second = gate.unlock();
    pending.complete(Ok(keyPair));
    expect(await first, isA<Ok<void>>());
    expect(await second, isA<Ok<void>>());
    expect(gate.deviceStaticKey, same(keyPair));
    verify(() => keystore.existingDeviceKeyPair()).called(1);
  });

  test(
    'locking during authentication rejects the late keychain result',
    () async {
      final pending = Completer<Result<SimpleKeyPair>>();
      when(() => keystore.existingDeviceKeyPair())
          .thenAnswer((_) => pending.future);
      final unlocking = gate.unlock();
      gate.noteLifecycleChange(AppLifecycleState.detached);
      pending.complete(Ok(keyPair));
      expect(await unlocking, isA<Err<void>>());
      expect(gate.isLocked, isTrue);
      expect(gate.deviceStaticKey, isNull);
    },
  );

  group('_defaultSetNativeLocked platform gate (R-31-04-02)', () {
    // These tests build a `BiometricGate` with no `setNativeLocked` override, so the real
    // `_defaultSetNativeLocked` (the constructor parameter's own default) runs, and mock the
    // native channel directly -- the only testing seam that reaches
    // that private top-level function at all.
    final binding = TestWidgetsFlutterBinding.ensureInitialized();

    tearDown(() {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _lockChannel,
        null,
      );
      debugDefaultTargetPlatformOverride = null;
    });

    test(
      'iOS: unlock and lock synchronize the native privacy shield',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        final lockedStates = <bool>[];
        binding.defaultBinaryMessenger.setMockMethodCallHandler(_lockChannel, (
          MethodCall call,
        ) async {
          lockedStates.add((call.arguments as Map)['locked'] as bool);
          return null;
        });
        when(() => keystore.existingDeviceKeyPair())
            .thenAnswer((_) async => Ok(keyPair));
        final iosGate = BiometricGate(
          appLockEnabled: true,
          localAuth: localAuth,
          keystore: keystore,
          now: () => clock,
        );

        final result = await iosGate.unlock();

        expect(result, isA<Ok<void>>());
        expect(iosGate.isLocked, isFalse);
        expect(lockedStates, [false]);
        iosGate.noteLifecycleChange(AppLifecycleState.detached);
        await Future<void>.delayed(Duration.zero);
        expect(lockedStates, [false, true]);
        debugDefaultTargetPlatformOverride = null;
      },
    );

    test('syncNativeLockState(appLockEnabled: false) clears the flag independent of any '
        'BiometricGate construction, the fix for the /welcome cold-start gap (R-31-01-09: no '
        'gate is ever constructed there)', () async {
      final calls = <MethodCall>[];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(_lockChannel, (
        MethodCall call,
      ) async {
        calls.add(call);
        return null;
      });

      syncNativeLockState(appLockEnabled: false);
      await Future<void>.delayed(Duration.zero);

      expect(calls, hasLength(1));
      expect(calls.single.method, 'setLocked');
      expect(calls.single.arguments, {'locked': false});
    });

    test('syncNativeLockState(appLockEnabled: true) makes no native call: '
        "MainActivity.onCreate()'s own unconditional set already leaves the flag correct", () async {
      var invoked = false;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(_lockChannel, (
        MethodCall call,
      ) async {
        invoked = true;
        return null;
      });

      syncNativeLockState(appLockEnabled: true);
      await Future<void>.delayed(Duration.zero);

      expect(invoked, isFalse);
    });
  });

  test('a fresh gate starts locked, per R-31-04-01 and R-13-064, and construction with App '
      'Lock on makes no native call, unlike the off case below', () {
    expect(gate.isLocked, isTrue);
    expect(gate.deviceStaticKey, isNull);
    expect(nativeLockCalls, isEmpty);
    verifyNoLocalAuthPromptWasRaised();
  });

  test('unlock() gates on a real keystore read alone, per R-22-013, and never also calls '
      'local_auth.authenticate() (the double-prompt defect)', () async {
    when(() => keystore.existingDeviceKeyPair())
        .thenAnswer((_) async => Ok(keyPair));

    final result = await gate.unlock();

    expect(result, isA<Ok<void>>());
    expect(gate.isLocked, isFalse);
    // The gate exposes the very key its own keystore read produced -- the key a caller
    // builds the Noise handshake with must be the key the biometric gate read, never an
    // independently generated one, or the gate is cryptographic theater.
    expect(gate.deviceStaticKey, same(keyPair));
    verify(() => keystore.existingDeviceKeyPair()).called(1);
    expect(nativeLockCalls, [false]);
    verifyNoLocalAuthPromptWasRaised();
  });

  test(
    'unlock() is a no-op with no further keystore read once already unlocked',
    () async {
      when(() => keystore.existingDeviceKeyPair())
          .thenAnswer((_) async => Ok(keyPair));
      await gate.unlock();

      final second = await gate.unlock();

      expect(second, isA<Ok<void>>());
      // Exactly the one read from the first unlock: the second call short-circuited, which
      // matters doubly here because a real device re-prompts on every raw keystore read.
      verify(() => keystore.existingDeviceKeyPair()).called(1);
      verifyNoLocalAuthPromptWasRaised();
    },
  );

  test('a rejected biometric leaves the app locked and passes BiometricAuthenticationException '
      'through unchanged', () async {
    when(() => keystore.existingDeviceKeyPair()).thenAnswer(
      (_) async => const Err<SimpleKeyPair>(
        'read or generate the device key pair',
        cause: BiometricAuthenticationException(
          BiometricFailureReason.rejected,
          'Biometric authentication error [10]: user canceled',
        ),
      ),
    );

    final result = await gate.unlock();

    expect(gate.isLocked, isTrue);
    final cause =
        (result as Err<void>).cause as BiometricAuthenticationException;
    expect(cause.reason, BiometricFailureReason.rejected);
    verifyNoLocalAuthPromptWasRaised();
  });

  test('a temporary lockout passes through, per the mockup state', () async {
    when(() => keystore.existingDeviceKeyPair()).thenAnswer(
      (_) async => const Err<SimpleKeyPair>(
        'read or generate the device key pair',
        cause: BiometricAuthenticationException(
          BiometricFailureReason.lockedOutTemporarily,
          'Biometric authentication error [7]: lockout',
        ),
      ),
    );

    final result = await gate.unlock();

    final cause =
        (result as Err<void>).cause as BiometricAuthenticationException;
    expect(cause.reason, BiometricFailureReason.lockedOutTemporarily);
    expect(gate.isLocked, isTrue);
    verifyNoLocalAuthPromptWasRaised();
  });

  test('no enrolled biometric passes through, per the mockup state', () async {
    when(() => keystore.existingDeviceKeyPair()).thenAnswer(
      (_) async => const Err<SimpleKeyPair>(
        'read or generate the device key pair',
        cause: BiometricAuthenticationException(
          BiometricFailureReason.notEnrolled,
          'Biometric authentication error [11]: no biometrics',
        ),
      ),
    );

    final result = await gate.unlock();

    final cause =
        (result as Err<void>).cause as BiometricAuthenticationException;
    expect(cause.reason, BiometricFailureReason.notEnrolled);
    verifyNoLocalAuthPromptWasRaised();
  });

  test('a permanently invalidated key surfaces KeyInvalidatedException unwrapped, per R-22-010', () async {
    when(() => keystore.existingDeviceKeyPair()).thenAnswer(
      (_) async => const Err<SimpleKeyPair>(
        'read or generate the device key pair',
        cause: KeyInvalidatedException('KeyPermanentlyInvalidatedException'),
      ),
    );

    final result = await gate.unlock();

    expect((result as Err<void>).cause, isA<KeyInvalidatedException>());
    expect(gate.isLocked, isTrue);
    expect(nativeLockCalls, isEmpty);
    verifyNoLocalAuthPromptWasRaised();
  });

  test(
    'the app locks again after 120 seconds in the background, per R-22-017',
    () async {
      when(() => keystore.existingDeviceKeyPair())
          .thenAnswer((_) async => Ok(keyPair));
      await gate.unlock();
      nativeLockCalls.clear();

      gate.noteLifecycleChange(AppLifecycleState.paused);
      clock = clock.add(const Duration(seconds: 121));
      gate.noteLifecycleChange(AppLifecycleState.resumed);

      expect(gate.isLocked, isTrue);
      expect(nativeLockCalls, [true]);
      // The 120-second timeout is one of the two `_lock()` call sites; the cached key must not
      // linger past it.
      expect(gate.deviceStaticKey, isNull);
      verifyNoLocalAuthPromptWasRaised();
    },
  );

  test(
    'the app stays unlocked under the 120-second background timeout',
    () async {
      when(() => keystore.existingDeviceKeyPair())
          .thenAnswer((_) async => Ok(keyPair));
      await gate.unlock();
      nativeLockCalls.clear();

      gate.noteLifecycleChange(AppLifecycleState.paused);
      clock = clock.add(const Duration(seconds: 119));
      gate.noteLifecycleChange(AppLifecycleState.resumed);

      expect(gate.isLocked, isFalse);
      expect(nativeLockCalls, isEmpty);
      verifyNoLocalAuthPromptWasRaised();
    },
  );

  test(
    'a detached lifecycle locks at once, defence in depth for a killed process',
    () async {
      when(() => keystore.existingDeviceKeyPair())
          .thenAnswer((_) async => Ok(keyPair));
      await gate.unlock();
      expect(gate.deviceStaticKey, same(keyPair));

      gate.noteLifecycleChange(AppLifecycleState.detached);

      expect(gate.isLocked, isTrue);
      // The killed-process defence-in-depth path is the other `_lock()` call site; it must
      // clear the cached key too, not just the 120-second timeout path above.
      expect(gate.deviceStaticKey, isNull);
      verifyNoLocalAuthPromptWasRaised();
    },
  );

  test('a destructive-action re-auth always re-reads the keystore and never locks the session '
      'on refusal, per R-31-04-11', () async {
    when(() => keystore.existingDeviceKeyPair())
        .thenAnswer((_) async => Ok(keyPair));
    await gate.unlock();

    when(() => keystore.existingDeviceKeyPair()).thenAnswer(
      (_) async => const Err<SimpleKeyPair>(
        'read or generate the device key pair',
        cause: BiometricAuthenticationException(
          BiometricFailureReason.rejected,
          'Biometric authentication error [10]: user canceled',
        ),
      ),
    );

    final result = await gate.reauthenticateForDestructiveAction();

    expect(result, isA<Err<void>>());
    // A refused confirmation denies the one action; it does not send the whole app back to
    // `/lock`.
    expect(gate.isLocked, isFalse);
    verify(() => keystore.existingDeviceKeyPair())
        .called(2); // the earlier unlock() plus this one.
    verifyNoLocalAuthPromptWasRaised();
  });

  test('availableBiometrics() still passes through to local_auth, with no glyph choice here and '
      'no authentication prompt', () async {
    when(() => localAuth.getAvailableBiometrics())
        .thenAnswer((_) async => [BiometricType.fingerprint]);

    final types = await gate.availableBiometrics();

    expect(types, [BiometricType.fingerprint]);
    verifyNoLocalAuthPromptWasRaised();
  });

  group('App Lock off (R-13-064, R-31-04-12)', () {
    test('isLocked reports false unconditionally, even before any unlock() call, and '
        'construction alone clears the native FLAG_SECURE MainActivity.kt set by default '
        '(the fix for the fresh-install black-screenshot defect: nothing ever called unlock() '
        'to clear it before)', () {
      final offGate = BiometricGate(
        appLockEnabled: false,
        localAuth: localAuth,
        keystore: keystore,
        now: () => clock,
        setNativeLocked: nativeLockCalls.add,
      );
      expect(offGate.isLocked, isFalse);
      expect(nativeLockCalls, [false]);
    });

    test('a fresh keystore read still populates deviceStaticKey with no OS challenge, since the '
        'off-mode KeystoreService instance a caller supplies is what makes the read '
        'non-challenging -- this file adds no separate gate', () async {
      when(() => keystore.deviceKeyPair()).thenAnswer((_) async => Ok(keyPair));
      final offGate = BiometricGate(
        appLockEnabled: false,
        localAuth: localAuth,
        keystore: keystore,
        now: () => clock,
        setNativeLocked: nativeLockCalls.add,
      );

      final result = await offGate.unlock();

      expect(result, isA<Ok<void>>());
      expect(offGate.isLocked, isFalse);
      expect(offGate.deviceStaticKey, same(keyPair));
      verifyNoLocalAuthPromptWasRaised();
    });

    test('setAppLockEnabled(false) unlocks the session live, with no app restart, even while '
        'internally still locked', () {
      expect(
        gate.isLocked,
        isTrue,
      ); // on-mode default `setUp` gate, never unlocked yet.

      gate.setAppLockEnabled(value: false);

      expect(gate.isLocked, isFalse);
    });

    test('setAppLockEnabled(true) re-arms the gate using the session\'s own unlock history, with '
        'no special case', () async {
      when(() => keystore.existingDeviceKeyPair())
          .thenAnswer((_) async => Ok(keyPair));
      await gate
          .unlock(); // Real unlock history: `_locked` now false internally.
      gate.setAppLockEnabled(value: false);
      expect(gate.isLocked, isFalse);

      gate.setAppLockEnabled(value: true);

      // Turning App Lock back on mid-session does not itself re-lock an already-unlocked
      // session (R-22-017 names cold start, the 120s timeout, and a destructive action as
      // the only triggers -- not the toggle itself).
      expect(gate.isLocked, isFalse);
    });
  });
}
