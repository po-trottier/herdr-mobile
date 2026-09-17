/// Proves `KeystoreService`'s iOS access-control configuration (R-22-013, R-22-014,
/// R-22-010): biometry OR device passcode unlocks the Keychain item, never biometry alone
/// and never an AND of the two, and R-22-001's accessibility class is untouched by that
/// choice. Added after `WP-13-b` found that `biometryCurrentSet` alone denies a passcode-only
/// device the read `biometric_gate.dart`'s passcode fallback prompt was supposed to unlock.
///
/// Also proves `_classify`'s biometric-failure classification: it turns the raw
/// `PlatformException` text `flutter_secure_storage`'s Android and iOS channels emit into
/// [KeyInvalidatedException] or [BiometricAuthenticationException], so `biometric_gate.dart`
/// can drive its rejected / locked-out / not-enrolled states from a keystore read alone,
/// with no separate `local_auth.authenticate()` call as the actual gate (see `_classify`'s
/// doc comment in `keystore.dart` for why that call would otherwise produce a second,
/// cryptographically meaningless prompt).
library;

import 'dart:convert' show base64Encode;

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart';
import 'package:herdr_mobile/services/biometric_gate.dart';
import 'package:herdr_mobile/services/keystore.dart';
import 'package:mocktail/mocktail.dart';

class _MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  group('iOS session keychain reads', () {
    const channel = MethodChannel('dev.herdr.herdr_mobile/keychain_session');
    const storageChannel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    late List<MethodCall> calls;
    final seed = [0, ...List<int>.filled(30, 7), 71];
    final hostKey = List<int>.filled(32, 9);
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      calls = [];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'invalidate') return null;
        return switch ((call.arguments as Map)['key']) {
          'device_x25519_private_key' => base64Encode(seed),
          'host_static_public_key_host-1' => base64Encode(hostKey),
          'host_routing_handle_host-1' => 'test-handle',
          'host_relay_origin_host-1' => 'wss://relay.example',
          _ => null,
        };
      });
      binding.defaultBinaryMessenger.setMockMethodCallHandler(storageChannel, (
        call,
      ) async {
        throw PlatformException(code: 'unexpected_independent_keychain_read');
      });
    });
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        storageChannel,
        null,
      );
    });
    test(
      'unlock and legacy host records use the shared native context',
      () async {
        final service = KeystoreService(appLockEnabled: true);
        final gate = BiometricGate(appLockEnabled: true, keystore: service);
        expect(await gate.unlock(), isA<Ok<void>>());
        expect(await gate.deviceStaticKey!.extractPrivateKeyBytes(), seed);
        final result = await service.hostSecrets('host-1');
        final secrets = (result as Ok<HostSecrets?>).value!;
        expect(secrets.hostStaticPublicKey, hostKey);
        expect(secrets.routingHandle, 'test-handle');
        expect(secrets.relayOrigin, Uri.parse('wss://relay.example'));
        expect(
          (await service.hostRelayOrigin('host-1') as Ok<Uri?>).value,
          Uri.parse('wss://relay.example'),
        );
        await gate.unlock();
        expect(
          calls.where(
            (c) =>
                c.method == 'read' &&
                (c.arguments as Map)['key'] == 'device_x25519_private_key',
          ),
          hasLength(1),
        );
        gate.noteLifecycleChange(AppLifecycleState.detached);
        await Future<void>.delayed(Duration.zero);
        expect(calls.last.method, 'invalidate');
        expect(gate.deviceStaticKey, isNull);
      },
    );
  });

  const options = KeystoreService.iosOptionsAppLockOnForTesting;
  const offOptions = KeystoreService.iosOptionsAppLockOffForTesting;

  group('KeystoreService iOS access control, App Lock on', () {
    test(
      'combines biometryCurrentSet with devicePasscode via or, never and',
      () {
        expect(
          options.accessControlFlags,
          contains(AccessControlFlag.biometryCurrentSet),
        );
        expect(
          options.accessControlFlags,
          contains(AccessControlFlag.devicePasscode),
        );
        expect(options.accessControlFlags, contains(AccessControlFlag.or));
        expect(
          options.accessControlFlags,
          isNot(contains(AccessControlFlag.and)),
        );
      },
    );

    test('keeps biometryAny out, so a new enrolment still invalidates the key (R-22-010)', () {
      expect(
        options.accessControlFlags,
        isNot(contains(AccessControlFlag.biometryAny)),
      );
    });

    test('leaves the R-22-001 accessibility class untouched', () {
      expect(options.accessibility, KeychainAccessibility.unlocked_this_device);
    });
  });

  group('KeystoreService iOS access control, App Lock off (R-22-082)', () {
    test(
      'carries no access-control flags -- the pinned 10.3.1 plugin only serialises '
      '`accessControlFlags` to the native side when the list is non-empty '
      '(`apple_options.dart` `toMap`), so an empty list here really does omit '
      '`.biometryCurrentSet` and `.devicePasscode` entirely, not send them as a false pair',
      () {
        expect(offOptions.accessControlFlags, isEmpty);
      },
    );

    test('keeps the same R-22-001 accessibility class as App Lock on', () {
      expect(
        offOptions.accessibility,
        KeychainAccessibility.unlocked_this_device,
      );
    });
  });

  group('KeystoreService Android options (R-22-006, R-22-082)', () {
    const androidOptions = KeystoreService.androidOptionsAppLockOnForTesting;
    const androidOffOptions =
        KeystoreService.androidOptionsAppLockOffForTesting;

    test('App Lock on supplies the product prompt copy instead of the package defaults '
        '(R-31-04-09)', () {
      expect(androidOptions.biometricPromptTitle, 'Herdr Remote');
      expect(androidOptions.biometricPromptSubtitle, 'Unlock to continue');
    });

    test('App Lock off carries no biometric parameter at all', () {
      expect(androidOffOptions.biometricPromptTitle, isNull);
    });
  });

  group('KeystoreService biometric failure classification', () {
    late _MockFlutterSecureStorage storage;
    late KeystoreService keystore;

    setUp(() {
      storage = _MockFlutterSecureStorage();
      keystore = KeystoreService(appLockEnabled: true, storage: storage);
    });

    Future<Object?> causeFromRead(PlatformException thrown) async {
      when(() => storage.read(key: any(named: 'key'))).thenThrow(thrown);
      final result = await keystore.deviceKeyPair();
      expect(result, isA<Err<SimpleKeyPair>>());
      return (result as Err<SimpleKeyPair>).cause;
    }

    test('classifies a permanently invalidated Android key as KeyInvalidatedException (R-22-010)', () async {
      final cause = await causeFromRead(
        PlatformException(
          code: 'Exception encountered',
          message:
              'android.security.keystore.KeyPermanentlyInvalidatedException',
        ),
      );
      expect(cause, isA<KeyInvalidatedException>());
    });

    test(
      'classifies iOS errSecAuthFailed as KeyInvalidatedException (R-22-010)',
      () async {
        final cause = await causeFromRead(
          PlatformException(
            code: 'read',
            message: 'Code: -25293, Message: errSecAuthFailed',
          ),
        );
        expect(cause, isA<KeyInvalidatedException>());
      },
    );

    test(
      'classifies Android BiometricPrompt error 7 as lockedOutTemporarily',
      () async {
        final cause = await causeFromRead(
          PlatformException(
            code: 'Exception encountered',
            message: 'Biometric authentication error [7]: Too many attempts',
          ),
        );
        expect(
          (cause! as BiometricAuthenticationException).reason,
          BiometricFailureReason.lockedOutTemporarily,
        );
      },
    );

    test(
      'classifies Android BiometricPrompt error 9 as lockedOutPermanently',
      () async {
        final cause = await causeFromRead(
          PlatformException(
            code: 'Exception encountered',
            message: 'Biometric authentication error [9]: Locked out',
          ),
        );
        expect(
          (cause! as BiometricAuthenticationException).reason,
          BiometricFailureReason.lockedOutPermanently,
        );
      },
    );

    test('classifies Android BiometricPrompt error 10 as rejected', () async {
      final cause = await causeFromRead(
        PlatformException(
          code: 'Exception encountered',
          message: 'Biometric authentication error [10]: User canceled',
        ),
      );
      expect(
        (cause! as BiometricAuthenticationException).reason,
        BiometricFailureReason.rejected,
      );
    });

    test(
      'classifies Android BiometricPrompt error 11 as notEnrolled',
      () async {
        final cause = await causeFromRead(
          PlatformException(
            code: 'Exception encountered',
            message:
                'Biometric authentication error [11]: No biometrics enrolled',
          ),
        );
        expect(
          (cause! as BiometricAuthenticationException).reason,
          BiometricFailureReason.notEnrolled,
        );
      },
    );

    test('classifies iOS errSecUserCanceled (-128) as rejected', () async {
      final cause = await causeFromRead(
        PlatformException(
          code: 'read',
          message: 'Code: -128, Message: The user canceled the operation.',
        ),
      );
      expect(
        (cause! as BiometricAuthenticationException).reason,
        BiometricFailureReason.rejected,
      );
    });

    test('leaves an unrelated PlatformException unclassified', () async {
      final thrown = PlatformException(code: 'read', message: 'disk full');
      final cause = await causeFromRead(thrown);
      expect(cause, same(thrown));
    });
  });

  group('retoggleProtection (R-22-083, R-13-073)', () {
    late _MockFlutterSecureStorage storage;
    late Map<String, String> backing;
    late KeystoreService keystore;
    late String seedBase64;

    setUp(() async {
      final keyPair = await X25519().newKeyPair();
      seedBase64 = base64Encode(await keyPair.extractPrivateKeyBytes());
      backing = <String, String>{
        'device_x25519_private_key': seedBase64,
        'host_relay_origin_host-1': 'https://relay.example.com',
        'host_static_public_key_host-1': base64Encode(List<int>.filled(32, 7)),
        'host_routing_handle_host-1': 'handle',
      };
      storage = _MockFlutterSecureStorage();
      when(() => storage.read(key: any(named: 'key'))).thenAnswer(
        (invocation) async =>
            backing[invocation.namedArguments[#key] as String],
      );
      when(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((invocation) async {
        backing[invocation.namedArguments[#key] as String] =
            invocation.namedArguments[#value] as String;
      });
      when(() => storage.delete(key: any(named: 'key')))
          .thenAnswer((invocation) async {
            backing.remove(invocation.namedArguments[#key] as String);
          });
      keystore = KeystoreService(appLockEnabled: false, storage: storage);
    });

    test('migrates the device key, relay origin, and every host record, preserving every value', () async {
      final result = await keystore.retoggleProtection(
        appLockEnabled: true,
        hostIds: ['host-1'],
      );

      expect(result, isA<Ok<void>>());
      expect(keystore.appLockEnabled, isTrue);
      expect(backing['device_x25519_private_key'], seedBase64);
      expect(backing['host_relay_origin_host-1'], 'https://relay.example.com');
      expect(
        backing['host_static_public_key_host-1'],
        base64Encode(List<int>.filled(32, 7)),
      );
      expect(backing['host_routing_handle_host-1'], 'handle');
    });

    test(
      'keeps origins separate through updates and deletion (R-03-126)',
      () async {
        final firstOrigin = Uri.parse('https://first.example.com');
        final secondOrigin = Uri.parse('https://second.example.com:8443');
        for (final entry in {
          'host-1': firstOrigin,
          'host-2': secondOrigin,
        }.entries) {
          expect(
            await keystore.storeHostSecrets(
              entry.key,
              HostSecrets(
                hostStaticPublicKey: List<int>.filled(32, 7),
                routingHandle: entry.key,
                relayOrigin: entry.value,
              ),
            ),
            isA<Ok<void>>(),
          );
        }
        final reopened = KeystoreService(
          appLockEnabled: false,
          storage: storage,
        );
        final first =
            (await reopened.hostSecrets('host-1') as Ok<HostSecrets?>).value!;
        expect(first.hostStaticPublicKey, List<int>.filled(32, 7));
        expect(first.routingHandle, 'host-1');
        expect(first.relayOrigin, firstOrigin);
        expect(
          (await reopened.hostSecrets(
            'host-2',
          ) as Ok<HostSecrets?>).value!.relayOrigin,
          secondOrigin,
        );
        final updated = Uri.parse('https://updated.example.com');
        expect(
          await reopened.storeHostRelayOrigin('host-1', updated),
          isA<Ok<void>>(),
        );
        expect(
          (await reopened.hostSecrets(
            'host-1',
          ) as Ok<HostSecrets?>).value!.relayOrigin,
          updated,
        );
        expect(await reopened.deleteHostSecrets('host-1'), isA<Ok<void>>());
        expect(
          (await reopened.hostSecrets('host-1') as Ok<HostSecrets?>).value,
          isNull,
        );
        expect(backing.containsKey('host_relay_origin_host-1'), isFalse);
        expect(
          (await reopened.hostSecrets(
            'host-2',
          ) as Ok<HostSecrets?>).value!.relayOrigin,
          secondOrigin,
        );
      },
    );

    test('reads an existing host without an origin (R-13-048)', () async {
      backing.remove('host_relay_origin_host-1');
      final secrets =
          (await keystore.hostSecrets('host-1') as Ok<HostSecrets?>).value!;
      expect(secrets.relayOrigin, isNull);
      expect(secrets.routingHandle, 'handle');
    });

    test(
      'migrates each host origin in both protection modes (R-22-083)',
      () async {
        final secondOrigin = Uri.parse('https://second.example.com');
        expect(
          await keystore.storeHostSecrets(
            'host-2',
            HostSecrets(
              hostStaticPublicKey: List<int>.filled(32, 8),
              routingHandle: 'second-handle',
              relayOrigin: secondOrigin,
            ),
          ),
          isA<Ok<void>>(),
        );
        for (final enabled in [true, false]) {
          expect(
            await keystore.retoggleProtection(
              appLockEnabled: enabled,
              hostIds: ['host-1', 'host-2'],
            ),
            isA<Ok<void>>(),
          );
          expect(
            (await keystore.hostSecrets(
              'host-1',
            ) as Ok<HostSecrets?>).value!.relayOrigin,
            Uri.parse('https://relay.example.com'),
          );
          expect(
            (await keystore.hostSecrets(
              'host-2',
            ) as Ok<HostSecrets?>).value!.relayOrigin,
            secondOrigin,
          );
          verify(() => storage.delete(key: 'host_relay_origin_host-1'))
              .called(1);
          verify(() => storage.delete(key: 'host_relay_origin_host-2'))
              .called(1);
        }
      },
    );

    test('never regenerates the keypair: the same seed decodes to the same key after toggling', () async {
      final before = await keystore.deviceKeyPair();
      await keystore.retoggleProtection(
        appLockEnabled: true,
        hostIds: const <String>[],
      );
      final after = await keystore.deviceKeyPair();

      final beforeBytes = await (before as Ok<SimpleKeyPair>).value
          .extractPrivateKeyBytes();
      final afterBytes = await (after as Ok<SimpleKeyPair>).value
          .extractPrivateKeyBytes();
      expect(afterBytes, beforeBytes);
    });

    test('is a no-op when the requested mode already matches', () async {
      final onKeystore = KeystoreService(
        appLockEnabled: true,
        storage: storage,
      );
      final result = await onKeystore.retoggleProtection(
        appLockEnabled: true,
        hostIds: const <String>[],
      );
      expect(result, isA<Ok<void>>());
      verifyNever(() => storage.delete(key: any(named: 'key')));
    });

    test(
      'skips a key with nothing stored, rather than writing a null value',
      () async {
        backing.remove('host_relay_origin_host-1');
        final result = await keystore.retoggleProtection(
          appLockEnabled: true,
          hostIds: const <String>[],
        );
        expect(result, isA<Ok<void>>());
        expect(backing.containsKey('host_relay_origin_host-1'), isFalse);
      },
    );

    test(
      'a failing read leaves this instance reporting the old mode',
      () async {
        when(() => storage.read(key: any(named: 'key')))
            .thenThrow(PlatformException(code: 'read', message: 'disk full'));
        final result = await keystore.retoggleProtection(
          appLockEnabled: true,
          hostIds: const <String>[],
        );
        expect(result, isA<Err<void>>());
        expect(keystore.appLockEnabled, isFalse);
      },
    );
  });

  group('one OS challenge per session (R-13-064, 2026-09-16)', () {
    late _MockFlutterSecureStorage gated;
    late _MockFlutterSecureStorage plain;
    late Map<String, String> gatedBacking;
    late Map<String, String> plainBacking;

    void wire(_MockFlutterSecureStorage storage, Map<String, String> backing) {
      when(() => storage.read(key: any(named: 'key'))).thenAnswer(
        (invocation) async =>
            backing[invocation.namedArguments[#key] as String],
      );
      when(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((invocation) async {
        backing[invocation.namedArguments[#key] as String] =
            invocation.namedArguments[#value] as String;
      });
      when(() => storage.delete(key: any(named: 'key')))
          .thenAnswer((invocation) async {
            backing.remove(invocation.namedArguments[#key] as String);
          });
    }

    setUp(() {
      gated = _MockFlutterSecureStorage();
      plain = _MockFlutterSecureStorage();
      gatedBacking = <String, String>{};
      plainBacking = <String, String>{};
      wire(gated, gatedBacking);
      wire(plain, plainBacking);
    });

    test('only the device key lives behind the challenge; a Host record is read with none', () async {
      final keystore = KeystoreService(
        appLockEnabled: true,
        storage: gated,
        plainStorage: plain,
      );
      expect(await keystore.deviceKeyPair(), isA<Ok<SimpleKeyPair>>());
      expect(
        await keystore.storeHostSecrets(
          'host-1',
          HostSecrets(
            hostStaticPublicKey: List<int>.filled(32, 7),
            routingHandle: 'handle',
            relayOrigin: Uri.parse('https://relay.example.com'),
          ),
        ),
        isA<Ok<void>>(),
      );
      expect(await keystore.hostSecrets('host-1'), isA<Ok<HostSecrets?>>());
      expect(await keystore.hostRelayOrigin('host-1'), isA<Ok<Uri?>>());

      expect(gatedBacking.keys, ['device_x25519_private_key']);
      expect(plainBacking.keys, isNot(contains('device_x25519_private_key')));
      expect(plainBacking, hasLength(3));
      // The gated store answered exactly one read: the key. Every Host read went plain.
      verify(() => gated.read(key: 'device_x25519_private_key')).called(1);
      verifyNever(
        () => gated.read(
          key: any(named: 'key', that: startsWith('host_')),
        ),
      );
    });

    test('toggling App Lock moves a Host record an earlier build wrote gated into the plain store', () async {
      gatedBacking['device_x25519_private_key'] = 'seed';
      gatedBacking['host_routing_handle_host-1'] = 'handle';
      final keystore = KeystoreService(
        appLockEnabled: true,
        storage: gated,
        plainStorage: plain,
      );
      expect(
        await keystore.retoggleProtection(
          appLockEnabled: false,
          hostIds: ['host-1'],
        ),
        isA<Ok<void>>(),
      );
      expect(plainBacking['host_routing_handle_host-1'], 'handle');
      expect(gatedBacking.containsKey('host_routing_handle_host-1'), isFalse);
    });
  });
}
