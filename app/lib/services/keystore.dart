// The Device's secret state -- App Lock (`docs/03-product-decisions.md` R-03-090) decides
// whether reading it also demands an operating-system biometric or passcode challenge.
//
// This file owns every value `docs/13-security-pairing.md` R-13-063 requires the platform
// keychain or keystore to hold, regardless of the App Lock setting:
//   - The Curve25519 Noise static private key. One key for the whole Device (R-13-063).
// - Each paired computer's pinned public key, routing handle, and relay origin
//   (R-03-126, R-13-038, R-13-048).
//
// `plain_store.dart` owns the rest of the Device's persisted state: `device_id`,
// `device_name`, and, per paired computer, `host_id`, `host_name` and the last-seen time
// (R-13-065). Those values carry no confidentiality requirement, so they need no biometric
// gate. A `PairedHostRecord` in `plain_store.dart` and a `HostSecrets` record here share the
// same `hostId` key; neither file reads the other's storage.
//
// The Device Curve25519 private key is generated in software by [X25519] from the
// `cryptography` package and stored as keychain or keystore **data**. It is never a Secure
// Enclave key and never a StrongBox-native key. The iOS Secure Enclave supports only the
// secp256r1 curve, not Curve25519 (R-13-044, R-22-003), so nothing in this file may claim
// the private key lives inside it. R-22-006's StrongBox preference is Android's own default
// behaviour for a biometric-gated Keystore key; see the note on `_androidOptions` below for
// how the pinned wrapper package supplies it without a platform channel.
//
// Every public method returns `Result<T>` per R-41-103 (`core/result/result.dart`). Nothing
// here throws across the service boundary, and nothing here logs, prints, or plainly stores
// the private key, derived session key material, the pairing phrase, or a routing handle
// (R-13-066).

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/result/result.dart';

/// Set as a [Err.cause] when the platform keychain or keystore reports that the biometric
/// gated key was permanently invalidated: `KeyPermanentlyInvalidatedException` on Android,
/// `errSecAuthFailed` (`OSStatus` -25293) on iOS (R-22-010). A caller MUST show a re-pair
/// prompt rather than retry the read.
final class KeyInvalidatedException implements Exception {
  const KeyInvalidatedException(this.platformDetail);

  /// The raw platform error text this was detected from. Diagnostic only; it names no key
  /// material, so it is safe to log (R-13-066).
  final String platformDetail;

  @override
  String toString() => 'KeyInvalidatedException: $platformDetail';
}

/// Why a biometric-gated keystore read failed, classified from the raw platform error text
/// so `biometric_gate.dart` (WP-13-b) can drive its rejected / locked-out / not-enrolled UI
/// states directly off a keystore read -- the single OS-triggered authentication event
/// R-22-013 describes -- with no separate `local_auth.authenticate()` call needed as the
/// actual gate. Real double-prompt problem this replaces: `local_auth`'s Android path calls
/// plain `BiometricPrompt.authenticate(promptInfo)` with no `CryptoObject`
/// (`local_auth_android-2.0.9/.../AuthenticationHelper.java`), so it has zero cryptographic
/// binding to this service's Keystore key and cannot satisfy the key's own
/// `setUserAuthenticationRequired(true)` gate; `flutter_secure_storage`'s Android plugin
/// always shows its own separate, `CryptoObject`-bound `BiometricPrompt` regardless
/// (`FlutterSecureStorage.java` `authenticateUser`). On iOS, `local_auth_darwin` evaluates a
/// private `LAContext` it never exposes (`LocalAuthPlugin.swift`), and `flutter_secure_storage`
/// only reuses a caller-supplied `LAContext` when `useSecureEnclave: true`
/// (`FlutterSecureStorageDarwinPlugin.swift` `parseCall`) -- unusable here, since R-13-044
/// forbids storing this Curve25519 key as a Secure Enclave key at all. So today, calling
/// `local_auth.authenticate()` before a keystore read produces two independent OS prompts on
/// both platforms, and the `local_auth` one is pure UI theatre on Android.
enum BiometricFailureReason {
  /// The user dismissed the prompt or tapped cancel. Android
  /// `BiometricPrompt.ERROR_USER_CANCELED` = 10; iOS `errSecUserCanceled` = -128.
  rejected,

  /// Too many failed attempts; temporarily locked out, about 30 seconds. Android
  /// `BiometricPrompt.ERROR_LOCKOUT` = 7.
  lockedOutTemporarily,

  /// Locked out until the user unlocks with the device passcode. Android
  /// `BiometricPrompt.ERROR_LOCKOUT_PERMANENT` = 9.
  lockedOutPermanently,

  /// No biometric is enrolled. Android `BiometricPrompt.ERROR_NO_BIOMETRICS` = 11.
  notEnrolled,
}

/// Set as a [Err.cause] when a biometric-gated read failed for one of the reasons
/// [BiometricFailureReason] names, distinct from [KeyInvalidatedException]'s permanent,
/// re-pair-requiring failure.
final class BiometricAuthenticationException implements Exception {
  const BiometricAuthenticationException(this.reason, this.platformDetail);

  final BiometricFailureReason reason;

  /// The raw platform error text this was classified from. Diagnostic only; it names no key
  /// material, so it is safe to log (R-13-066).
  final String platformDetail;

  @override
  String toString() =>
      'BiometricAuthenticationException($reason): $platformDetail';
}

/// The secret half of one paired computer's record (R-13-038, R-13-048, R-13-063). The
/// non-secret half — `hostId`, `hostName`, last-seen time — is `PairedHostRecord` in
/// `plain_store.dart`, keyed by the same [hostId].
final class HostSecrets {
  const HostSecrets({
    required this.hostStaticPublicKey,
    required this.routingHandle,
    this.relayOrigin,
  });

  /// The Host's pinned Noise static public key, obtained from the Noise handshake at
  /// enrolment (R-13-048) and never re-read from the wire afterward (R-13-070).
  final List<int> hostStaticPublicKey;

  /// The routing handle that reaches this Host through the relay (R-13-038).
  final String routingHandle;

  /// This computer's relay origin (R-03-126, R-13-048).
  final Uri? relayOrigin;
}

/// The platform keychain or keystore, wrapped for the Device's secret state.
///
/// `flutter_secure_storage` 10.3.1 is pinned (`docs/20-mobile-framework.md` section 6; not
/// 11.0.0, which raises the plugin's own Android `compileSdk` past the newest stable
/// platform). Every read and write goes through one `FlutterSecureStorage` instance
/// configured once, in the constructor, so every caller gets the same access control with no
/// chance of an unprotected call slipping in.
class KeystoreService {
  /// [appLockEnabled] is required, with no default, so every call site states the current
  /// App Lock setting (`docs/03-product-decisions.md` R-03-090) explicitly — a silent
  /// fallback to the old mandatory-biometric behaviour, or a silent fallback to no
  /// protection at all, would both be a real regression a default could hide.
  KeystoreService({required bool appLockEnabled, FlutterSecureStorage? storage})
    : _appLockEnabled = appLockEnabled,
      _storageOverride = storage,
      _storage =
          storage ??
          FlutterSecureStorage(
            iOptions: appLockEnabled
                ? _iosOptionsAppLockOn
                : _iosOptionsAppLockOff,
            aOptions: appLockEnabled
                ? _androidOptionsAppLockOn
                : _androidOptionsAppLockOff,
          );

  bool _appLockEnabled;
  FlutterSecureStorage _storage;

  /// The constructor's own `storage` override, if a caller supplied one -- kept so
  /// [retoggleProtection] can reuse the identical test double as its own "new" storage rather
  /// than always constructing a real `FlutterSecureStorage`, which would hit a real platform
  /// channel in a widget test. A production caller never supplies this, so production
  /// toggling always builds a real, distinctly-optioned instance, exactly as the constructor
  /// does above.
  final FlutterSecureStorage? _storageOverride;

  /// The protection level this instance currently reads and writes under. Mutated only by
  /// [retoggleProtection], once the migration it describes has actually succeeded.
  bool get appLockEnabled => _appLockEnabled;

  // R-22-001 names `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` exactly, which is
  // `KeychainAccessibility.unlocked_this_device` in the pinned 10.3.1 enum (verified against
  // `flutter_secure_storage-10.3.1/lib/options/apple_options.dart`): access only while the
  // device is unlocked, and the item never migrates to a new device. This is a stricter,
  // "while unlocked" read than `first_unlock_this_device`, which would allow a read any time
  // after one unlock since boot. This accessibility class is unrelated to, and unweakened
  // by, the access-control flags below; it is the disk-encryption-class gate, not the
  // biometric gate. It applies whether App Lock is on or off (R-22-082): only the extra
  // authentication challenge below is conditional.
  //
  // App Lock on: the access-control flags combine `biometryCurrentSet` with `devicePasscode`
  // via `or`, never `and`. `biometryCurrentSet` alone is biometry-only: a device with no
  // biometric enrolled, or a user who falls back to the passcode prompt `biometric_gate.dart`
  // offers per R-22-014, would pass that app-level prompt and then still fail this Keychain
  // read, because the item itself would refuse a passcode-based unlock. `or` makes either
  // route succeed at the Keychain layer too, so R-22-014's passcode fallback actually works
  // end to end, not just at the `local_auth` prompt. `biometryCurrentSet` (not `biometryAny`)
  // is kept for the `or` combination's biometric side so a newly enrolled fingerprint or face
  // still invalidates the key (R-22-010) exactly as R-22-013 specifies. Verified against
  // `flutter_secure_storage_darwin-0.3.2/darwin/.../FlutterSecureStorage.swift`
  // `parseAccessControlFlags`, which inserts each named flag straight into Apple's real
  // `SecAccessControlCreateFlags` and passes the set to `SecAccessControlCreateWithFlags`; the
  // three flags used here are handled by name in that switch, and Apple's own
  // `SecAccessControlCreateFlags` documents `.biometryCurrentSet`, `.devicePasscode` and `.or`
  // as a real, supported combination, not an invented member.
  static const _iosOptionsAppLockOn = IOSOptions(
    accessibility: KeychainAccessibility.unlocked_this_device,
    accessControlFlags: [
      AccessControlFlag.biometryCurrentSet,
      AccessControlFlag.devicePasscode,
      AccessControlFlag.or,
    ],
  );

  /// App Lock off, per R-22-082: the same `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
  /// accessibility class, but no `accessControlFlags` at all -- `.biometryCurrentSet` and
  /// `.devicePasscode` are both omitted, not merely left unused, so the Keychain read raises
  /// no operating-system challenge.
  static const _iosOptionsAppLockOff = IOSOptions(
    accessibility: KeychainAccessibility.unlocked_this_device,
  );

  /// Exposed for `test/services/keystore_test.dart` only, to prove the access-control flags
  /// above are what the constructor actually uses in each mode.
  @visibleForTesting
  static const IOSOptions iosOptionsAppLockOnForTesting = _iosOptionsAppLockOn;
  @visibleForTesting
  static const IOSOptions iosOptionsAppLockOffForTesting =
      _iosOptionsAppLockOff;

  // `AndroidOptions.biometric(enforceBiometrics: true)` generates a hardware-backed AES key
  // with `setUserAuthenticationRequired(true)` and throws if the device has no PIN, pattern,
  // password or biometric enrolled (verified against
  // `flutter_secure_storage-10.3.1/android/.../KeyCipherImplementationAES23.java`, which also
  // checks `FEATURE_STRONGBOX_KEYSTORE` and falls back to the TEE when StrongBox is
  // unavailable or key generation with it fails). This satisfies R-22-006, R-22-007 and
  // R-22-013's Android half with no platform channel, while App Lock is on. R-22-012's text
  // ("the app MUST call the native Android Keystore API directly through a platform channel")
  // predates this capability in the pinned 10.3.1 release; this comment records the
  // correction rather than silently diverging from the cited rule, per `AGENTS.md`.
  //
  // One known gap: the native key is generated with a zero-second authentication validity
  // window (`setUserAuthenticationParameters(0, ...)`), so every read re-prompts, not the
  // 120-second validity R-22-007 allows. The 120-second background-lock cadence in R-22-017
  // and R-13-064 is session-level and belongs to `biometric_gate.dart` (WP-13-b); it is
  // unaffected by this key-level gap.
  //
  // `biometricPromptTitle`/`biometricPromptSubtitle` supply the system `BiometricPrompt`
  // sheet's copy (R-22-012's `biometricPromptTitle` group). Left unset, `flutter_secure_storage`
  // shows its own package defaults ("Authenticate to access" / "Use biometrics or device
  // credentials"), not the product's copy. `docs/31-mockups/04-lock.md` R-31-04-09 requires the
  // app to supply this sheet's title and subtitle; the values here MUST stay identical to
  // `lock_screen.dart`'s painted title ("Herdr Remote") and its `checking`-phase prompt
  // ("Unlock to continue") so the sheet reads as a continuation of the screen behind it, not a
  // second, differently worded prompt.
  static const _androidOptionsAppLockOn = AndroidOptions.biometric(
    enforceBiometrics: true,
    biometricPromptTitle: 'Herdr Remote',
    biometricPromptSubtitle: 'Unlock to continue',
  );

  /// App Lock off, per R-22-082: plain `AndroidOptions()` with no `biometric` parameter at
  /// all, so `setUserAuthenticationRequired` is never set on the generated key.
  static const _androidOptionsAppLockOff = AndroidOptions();

  /// Exposed for `test/services/keystore_test.dart` only, to prove the prompt copy above is
  /// what the constructor actually uses when App Lock is on.
  @visibleForTesting
  static const AndroidOptions androidOptionsAppLockOnForTesting =
      _androidOptionsAppLockOn;
  @visibleForTesting
  static const AndroidOptions androidOptionsAppLockOffForTesting =
      _androidOptionsAppLockOff;

  static const _privateKeyStorageKey = 'device_x25519_private_key';

  static String _hostPublicKeyStorageKey(String hostId) =>
      'host_static_public_key_$hostId';

  static String _hostRoutingHandleStorageKey(String hostId) =>
      'host_routing_handle_$hostId';

  static String _hostRelayOriginStorageKey(String hostId) =>
      'host_relay_origin_$hostId';

  /// Returns the Device's Curve25519 static keypair, generating and storing it on the first
  /// call if none exists yet (R-13-043, R-20-035) -- whether or not App Lock is on, and
  /// whether or not the phone has a screen lock at all. Every later call returns the same
  /// keypair; this method never rotates an existing key (R-13-046).
  Future<Result<SimpleKeyPair>> deviceKeyPair() async {
    try {
      final storedSeed = await _storage.read(key: _privateKeyStorageKey);
      if (storedSeed != null) {
        return Ok(await X25519().newKeyPairFromSeed(base64Decode(storedSeed)));
      }
      final keyPair = await X25519().newKeyPair();
      final seed = await keyPair.extractPrivateKeyBytes();
      await _storage.write(
        key: _privateKeyStorageKey,
        value: base64Encode(seed),
      );
      return Ok(keyPair);
    } on PlatformException catch (e) {
      return Err('read or generate the device key pair', cause: _classify(e));
    } on FormatException catch (e) {
      return Err('decode the stored device private key', cause: e);
    }
  }

  /// Stores this paired computer's pinned public key and routing handle (R-13-038, R-13-048,
  /// R-13-063). [hostId] is the identifier `plain_store.dart` uses for the matching
  /// non-secret record; this service keeps no list of paired computers of its own.
  Future<Result<void>> storeHostSecrets(
    String hostId,
    HostSecrets secrets,
  ) async {
    try {
      await _storage.write(
        key: _hostPublicKeyStorageKey(hostId),
        value: base64Encode(secrets.hostStaticPublicKey),
      );
      await _storage.write(
        key: _hostRoutingHandleStorageKey(hostId),
        value: secrets.routingHandle,
      );
      if (secrets.relayOrigin != null) {
        await _storage.write(
          key: _hostRelayOriginStorageKey(hostId),
          value: secrets.relayOrigin.toString(),
        );
      }
      return const Ok(null);
    } on PlatformException catch (e) {
      return Err('store host secrets for $hostId', cause: _classify(e));
    }
  }

  /// Reads the secrets stored for [hostId], or `Ok(null)` when none are stored.
  Future<Result<HostSecrets?>> hostSecrets(String hostId) async {
    try {
      final publicKeyBase64 = await _storage.read(
        key: _hostPublicKeyStorageKey(hostId),
      );
      final routingHandle = await _storage.read(
        key: _hostRoutingHandleStorageKey(hostId),
      );
      if (publicKeyBase64 == null || routingHandle == null) {
        return const Ok(null);
      }
      final origin = await _storage.read(
        key: _hostRelayOriginStorageKey(hostId),
      );
      return Ok(
        HostSecrets(
          hostStaticPublicKey: base64Decode(publicKeyBase64),
          routingHandle: routingHandle,
          relayOrigin: origin == null ? null : Uri.parse(origin),
        ),
      );
    } on PlatformException catch (e) {
      return Err('read host secrets for $hostId', cause: _classify(e));
    } on FormatException catch (e) {
      return Err('decode host secrets for $hostId', cause: e);
    }
  }

  /// Removes one paired computer's secret record: on revoke, on unpair, or as part of the
  /// destructive relay-origin change R-03-032 requires. The caller MUST also remove the
  /// matching `PairedHostRecord` from `plain_store.dart`.
  Future<Result<void>> deleteHostSecrets(String hostId) async {
    try {
      await _storage.delete(key: _hostPublicKeyStorageKey(hostId));
      await _storage.delete(key: _hostRoutingHandleStorageKey(hostId));
      await _storage.delete(key: _hostRelayOriginStorageKey(hostId));
      return const Ok(null);
    } on PlatformException catch (e) {
      return Err('delete host secrets for $hostId', cause: _classify(e));
    }
  }

  /// Stores one computer's origin. The caller validates it (R-03-033, R-03-126).
  Future<Result<void>> storeHostRelayOrigin(String hostId, Uri origin) async {
    try {
      await _storage.write(
        key: _hostRelayOriginStorageKey(hostId),
        value: origin.toString(),
      );
      return const Ok(null);
    } on PlatformException catch (e) {
      return Err('store relay origin for $hostId', cause: _classify(e));
    }
  }

  /// Reads one computer's stored origin alone, or `Ok(null)` when it has none.
  ///
  /// [hostSecrets] answers the same question, but it also reads that computer's pinned Host key
  /// and its routing handle. A caller that only needs an address MUST use this instead: the
  /// pairing form's prefill (`R-03-126`) is such a caller, and reading a pinned handle to fill a
  /// text field is a use of key material that no rule asks for.
  Future<Result<Uri?>> hostRelayOrigin(String hostId) async {
    try {
      final stored = await _storage.read(
        key: _hostRelayOriginStorageKey(hostId),
      );
      if (stored == null) return const Ok(null);
      final parsed = Uri.tryParse(stored);
      return Ok(parsed);
    } on PlatformException catch (e) {
      return Err('read relay origin for $hostId', cause: _classify(e));
    }
  }

  /// Deletes every secret this service holds: the Device keypair, relay origins, and
  /// every paired computer's pinned key and routing handle. Used for a full unpair and as
  /// part of the account-reset flow; a relay-origin change (R-03-032) should instead call
  /// `deleteHostSecrets` per affected computer and leave the Device keypair untouched.
  Future<Result<void>> clearAll() async {
    try {
      await _storage.deleteAll();
      return const Ok(null);
    } on PlatformException catch (e) {
      return Err('clear the keystore', cause: _classify(e));
    }
  }

  /// `R-22-083`/`R-13-073`: toggling App Lock re-stores every secret this service owns --
  /// the device keypair and [hostIds]' pinned public keys, routing handles, and relay
  /// origins (R-13-063) -- under the new protection level. This
  /// method never calls key generation and never touches a paired computer's non-secret
  /// `PairedHostRecord`; it MUST NOT be used for anything but a protection-level change.
  ///
  /// **Read-delete-write per key, not R-22-083's literal read-write-delete order.** The pinned
  /// `flutter_secure_storage` 10.3.1 Android implementation
  /// (`FlutterSecureStorage.java` `writeUnsafe`/`delete`) keeps every value in one
  /// `SharedPreferences` file, addressed by the same string `key` regardless of
  /// `AndroidOptions`; there is no separate "old" and "new" entry to distinguish once both
  /// options write to the identical `key`. Writing the new value first and deleting second, as
  /// R-22-083's prose literally reads, would delete the just-written new value, because
  /// `delete` removes whatever currently sits at that key with no memory of which write put it
  /// there. Deleting first instead (with the value already held in memory from the read) is
  /// the only order that ends with exactly the migrated value present under the new options,
  /// and it also avoids iOS's `errSecDuplicateItem` a `SecItemAdd` under new access-control
  /// flags would otherwise hit against an item that already exists at the same account. This
  /// comment records the correction rather than silently diverging from R-22-083's prose, per
  /// `AGENTS.md`.
  ///
  /// On success this instance itself starts reading and writing under [appLockEnabled] from
  /// then on (see [KeystoreService.appLockEnabled]), so a caller holding onto the same
  /// instance -- `biometric_gate.dart`'s session-shared gate, in particular -- picks up the
  /// new mode with no separate wiring. A failure leaves this instance, and every entry it has
  /// not yet migrated, exactly as they were (R-22-083's "leave the previous protection level
  /// ... in place").
  ///
  /// ponytail: per-key migration, not one atomic transaction. The narrow window between a
  /// successful delete and a failed write for the same key can lose that one value on a real
  /// device fault; a caller that observes an `Err` here MUST NOT flip the App Lock switch (see
  /// `settings_screen.dart`), which bounds the damage to "re-pair that one computer", never a
  /// silently wrong reported setting. Upgrade path if this ever matters in practice: back up
  /// the value to plain memory before the delete and re-attempt the write once more before
  /// giving up.
  Future<Result<void>> retoggleProtection({
    required bool appLockEnabled,
    required List<String> hostIds,
  }) async {
    if (appLockEnabled == _appLockEnabled) {
      return const Ok(null);
    }
    final newStorage =
        _storageOverride ??
        FlutterSecureStorage(
          iOptions: appLockEnabled
              ? _iosOptionsAppLockOn
              : _iosOptionsAppLockOff,
          aOptions: appLockEnabled
              ? _androidOptionsAppLockOn
              : _androidOptionsAppLockOff,
        );
    try {
      final keys = <String>[
        _privateKeyStorageKey,
        for (final hostId in hostIds) _hostPublicKeyStorageKey(hostId),
        for (final hostId in hostIds) _hostRoutingHandleStorageKey(hostId),
        for (final hostId in hostIds) _hostRelayOriginStorageKey(hostId),
      ];
      for (final key in keys) {
        final value = await _storage.read(key: key);
        if (value == null) {
          continue; // Nothing stored under this key yet; nothing to migrate.
        }
        await _storage.delete(key: key);
        await newStorage.write(key: key, value: value);
      }
      _storage = newStorage;
      _appLockEnabled = appLockEnabled;
      return const Ok(null);
    } on PlatformException catch (e) {
      return Err('retoggle App Lock protection', cause: _classify(e));
    }
  }

  /// Recognises a permanently invalidated key from the platform's raw error text and wraps
  /// it as [KeyInvalidatedException] (R-22-010), or a recoverable biometric failure as
  /// [BiometricAuthenticationException]. `flutter_secure_storage`'s Android channel reports
  /// every native exception with the fixed code `"Exception encountered"`
  /// (`FlutterSecureStoragePlugin.java`), and its own `authenticateUser` embeds the numeric
  /// `BiometricPrompt` error code as literal text, `"Biometric authentication error [N]: ..."`
  /// -- so classification here is by parsing that text, not by a stable error code on either
  /// platform. iOS formats a failed `SecItemCopyMatching` as `"Code: N, Message: ..."` where
  /// N is the raw OSStatus (`FlutterSecureStorageDarwinPlugin.swift` `handleResponse`). Every
  /// `PlatformException` passes through unchanged.
  Object _classify(PlatformException e) {
    final text = '${e.code} ${e.message ?? ''} ${e.details ?? ''}';
    final isInvalidated =
        text.contains('KeyPermanentlyInvalidatedException') ||
        text.contains('errSecAuthFailed') ||
        text.contains('Code: -25293');
    if (isInvalidated) {
      return KeyInvalidatedException(text);
    }
    final reason = _biometricFailureReason(text);
    return reason == null ? e : BiometricAuthenticationException(reason, text);
  }

  static final _androidBiometricErrorCode = RegExp(
    r'Biometric authentication error \[(\d+)\]',
  );

  BiometricFailureReason? _biometricFailureReason(String text) {
    final androidMatch = _androidBiometricErrorCode.firstMatch(text);
    if (androidMatch != null) {
      return switch (int.parse(androidMatch.group(1)!)) {
        7 => BiometricFailureReason.lockedOutTemporarily,
        9 => BiometricFailureReason.lockedOutPermanently,
        10 => BiometricFailureReason.rejected,
        11 => BiometricFailureReason.notEnrolled,
        _ => null,
      };
    }
    if (text.contains('Code: -128')) {
      return BiometricFailureReason.rejected;
    }
    return null;
  }
}
