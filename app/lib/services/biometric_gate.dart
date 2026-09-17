// The Device's session-level biometric gate, per `docs/22-platform-integration.md`
// section 2 and `docs/13-security-pairing.md` R-13-064.
//
// R-22-013 fixes the pattern this file MUST follow: the app gates access on the operating
// system's biometric check, never on an app-level boolean. `unlock()` follows it literally,
// with exactly one step: a real read of `KeystoreService.deviceKeyPair()`. That key was
// written with `setUserAuthenticationRequired(true)` (Android) or a `SecAccessControl` with
// `.biometryCurrentSet` plus `.devicePasscode` (iOS), so the read only succeeds if the OS
// itself unlocked the key -- and it is the OS, not this file, that raises the prompt. This is
// the single "app asks the Keystore/Keychain to read the data; the OS presents the prompt"
// event R-22-013 describes.
//
// `LocalAuthentication.authenticate()` is deliberately NOT part of that gate.
// `wp-13a-keystore`'s native-source investigation (`keystore.dart`'s
// `BiometricAuthenticationException` doc comment carries the full citation trail) found that
// calling it first would raise a SECOND, independent OS prompt on both platforms, and that the
// `local_auth` one carries zero cryptographic weight on Android: its `BiometricPrompt` call
// has no `CryptoObject`, so it cannot satisfy this service's own Keystore key requirement, and
// `flutter_secure_storage` always raises its own separate, key-bound prompt regardless. On
// iOS, `local_auth` evaluates a private `LAContext` `flutter_secure_storage` never sees. The
// mockup's own R-31-04-09 requires exactly one system-drawn sheet; two prompts would violate
// it. `LocalAuthentication` stays in this file for exactly one job that raises no prompt at
// all: `availableBiometrics()`, `local_auth`'s `getAvailableBiometrics()` passthrough, which
// `docs/31-mockups/04-lock.md`'s screen needs for its glyph and label lookup (R-22-069,
// R-22-070).
//
// This file holds session state only: whether the app is currently locked, and since when it
// has been backgrounded. It persists nothing (R-13-066 lists what plain storage may never
// hold, and session-lock state is not even listed there because it must not survive a process
// restart at all): a fresh instance starts locked, which is what makes "lock at once when the
// process is killed" (R-31-04-01) true with no extra code -- there is no way for a new process
// to inherit an unlocked one.
//
// This file has no widget tree and paints nothing. `docs/31-mockups/04-lock.md`'s wireframes,
// its rejected/locked-out/no-enrolment states and its biometric-label lookup belong to
// `app/lib/screens/lock_screen.dart`, a later work package's file, not this one. That screen
// classifies a failed `unlock()` by pattern-matching `Err.cause`, which this file passes
// through unchanged: `KeyInvalidatedException` for a permanently invalidated key (R-22-010),
// or `BiometricAuthenticationException` with its `BiometricFailureReason` for a recoverable
// rejection, lockout or missing enrolment -- both types owned by `keystore.dart`.
//
// `unlock()`'s keystore read produces real key material, not just a boolean. This file caches
// that `SimpleKeyPair` and exposes it through [BiometricGate.deviceStaticKey] for exactly as
// long as the app stays unlocked, so a caller building the Noise handshake (a later work
// package's `RelayConnection.connect()`) uses the very key the biometric gate just read,
// never an independently generated one. [BiometricGate._lock] clears the cached key the
// instant the app locks -- on the 120-second background timeout and on the killed-process
// defence-in-depth path alike -- so no key material lingers in memory past a lock.
library;

import 'dart:async';

import 'package:cryptography/cryptography.dart' show SimpleKeyPair;
import 'package:flutter/foundation.dart'
    show TargetPlatform, ValueChanged, defaultTargetPlatform;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:local_auth/local_auth.dart'
    show BiometricType, LocalAuthentication;

import '../core/result/result.dart' show Err, Ok, Result;
import 'keystore.dart' show KeystoreService;

/// The method channel `app/android/app/src/main/kotlin/.../MainActivity.kt` listens on to set
/// or clear `FLAG_SECURE` while the app is locked (R-31-04-02). iOS has no matching native
/// file in this work package's `Owns.` line, so [_defaultSetNativeLocked] is a no-op there;
/// `MainActivity.kt`'s own doc comment records that FLAG_SECURE is also set synchronously in
/// `onCreate`, before this channel exists, so a cold start is covered with no race.
const MethodChannel _lockChannel = MethodChannel(
  'dev.herdr.herdr_mobile/biometric_lock',
);

void _defaultSetNativeLocked(bool locked) {
  if (defaultTargetPlatform != TargetPlatform.android) {
    return;
  }
  unawaited(
    _lockChannel.invokeMethod<void>('setLocked', <String, Object?>{
      'locked': locked,
    }),
  );
}

/// Syncs `MainActivity.kt`'s native `FLAG_SECURE` to [appLockEnabled], independent of whether
/// or when any [BiometricGate] gets constructed. `MainActivity.onCreate()` sets the flag
/// unconditionally before any Dart code runs (the correct locked-by-default posture,
/// matching [BiometricGate]'s own `_locked` starting `true`), so a session whose landing
/// screen never constructs a gate at all -- `/welcome`, by `docs/31-mockups/01-welcome.md`
/// R-31-01-09's deliberate design: zero paired computers means there is nothing yet to
/// protect -- would otherwise carry a blanked window (`adb screencap`, the task switcher
/// snapshot, any screen recording) for its whole session, with no code path ever reaching the
/// constructor-time sync below.
///
/// Call once, at the one point every session already passes through before any route builds:
/// `routing.dart`'s `_resolveStartupRedirect`, which already loads the same
/// `AppSettingsService.current.appLockEnabled` this function needs. This is deliberately not a
/// replacement for [BiometricGate]'s own constructor-time sync (this file's top doc comment on
/// that constructor) -- that one still runs for the moment a real gate later gets constructed
/// with its own, possibly different, `appLockEnabled` value (`qr_scan_screen.dart`'s
/// pairing-scoped gate is deliberately always `false`, regardless of the session setting). The
/// two are complementary: this one fixes the *starting* state for every screen, gate-free or
/// not; that one keeps a later-constructed gate's own state in sync with the flag as before.
///
/// Mirrors [BiometricGate]'s constructor: only acts when [appLockEnabled] is `false`. When
/// it is `true`, `onCreate`'s own unconditional set already leaves the flag in the correct,
/// safe, locked state, so there is nothing to do -- the existing App-Lock-on behaviour is
/// untouched by this function.
void syncNativeLockState({required bool appLockEnabled}) {
  if (!appLockEnabled) {
    _defaultSetNativeLocked(false);
  }
}

/// The Device's session-level biometric gate. One instance covers the whole app session; a
/// caller (a later work package's router redirect or app root) reads [isLocked] to decide
/// whether to show `/lock`, and calls [unlock] there.
class BiometricGate {
  /// [appLockEnabled] is required, with no default, mirroring `keystore.dart`'s own
  /// constructor: every caller states the current App Lock setting
  /// (`docs/03-product-decisions.md` R-03-090) explicitly, so a silent fallback to "always
  /// gated" or "never gated" can never hide a real regression.
  BiometricGate({
    required bool appLockEnabled,
    LocalAuthentication? localAuth,
    KeystoreService? keystore,
    DateTime Function() now = DateTime.now,
    ValueChanged<bool>? setNativeLocked,
  }) : _appLockEnabled = appLockEnabled,
       _localAuth = localAuth ?? LocalAuthentication(),
       _keystore = keystore ?? KeystoreService(appLockEnabled: appLockEnabled),
       // `this._now` would make the external parameter name `_now`, which is unusable
       // from `biometric_gate_test.dart`, a different library, per Dart's
       // named-parameter privacy rule.
       // ignore: prefer_initializing_formals
       _now = now,
       _setNativeLocked = setNativeLocked ?? _defaultSetNativeLocked {
    // `MainActivity.kt`'s `onCreate` sets `FLAG_SECURE` unconditionally, before any Dart
    // code runs, matching `_locked`'s own "locked by default" (R-31-04-01). [unlock] is the
    // only other place that clears it, and nothing calls [unlock] proactively: it fires
    // only from a pairing or host-switch flow (`qr_scan_screen.dart`, `host_list.dart`). A
    // person who starts with App Lock off (`docs/03-product-decisions.md` R-03-090, the
    // default) and only browses `/welcome` or `/settings` would otherwise carry a
    // `FLAG_SECURE` window — blank in every screenshot, screen recording and cast — for the
    // whole session, with nothing actually locked to justify it. [isLocked] already reports
    // `false` from this first instant per its own doc comment; this makes the native flag
    // agree with it immediately, the same one-line call [_markUnlocked] and [_lock] already
    // use.
    if (!appLockEnabled) {
      _setNativeLocked(false);
    }
  }

  bool _appLockEnabled;
  final LocalAuthentication _localAuth;
  final KeystoreService _keystore;
  final DateTime Function() _now;
  final ValueChanged<bool> _setNativeLocked;

  /// The Device's Curve25519 static key pair, cached from the last successful keystore read
  /// `unlock()` or `reauthenticateForDestructiveAction()` performed. `null` whenever
  /// [isLocked] is true, including before the first successful `unlock()`: this is the only
  /// way a caller reaches the actual key material the biometric-gated read produced, so it
  /// can never be read while the app is locked, and it never lingers in memory past a lock
  /// (see [_lock]).
  SimpleKeyPair? _deviceStaticKey;

  /// The single background-lock timeout for the whole repository (R-22-017). No other file
  /// may restate this number, per `docs/31-mockups/04-lock.md` R-31-04-01. Applies only while
  /// App Lock is on; see [isLocked].
  static const backgroundLockTimeout = Duration(seconds: 120);

  /// Locked by default: a cold start (R-03-043 group, R-13-064) and a killed-and-relaunched
  /// process both start here, which is what makes R-31-04-01's "at once when the process is
  /// killed" true with no further code. [isLocked] still reports `false` from the first
  /// instant while App Lock is off, per that getter's own doc comment; this internal flag
  /// keeps tracking real unlock history underneath either way, so a later toggle to App Lock
  /// on picks up exactly where the session's own unlock history left off, with no special
  /// case.
  bool _locked = true;

  DateTime? _backgroundedAt;

  /// Whether the session-level gate applies at all (`docs/03-product-decisions.md`
  /// R-03-090). Mutable: `settings_screen.dart`'s App Lock toggle calls
  /// [setAppLockEnabled] on this same session-shared instance (`routing.dart`'s
  /// `biometricGateProvider`) so the very next R-22-017 trigger picks up the new setting,
  /// with no app restart.
  bool get appLockEnabled => _appLockEnabled;

  /// See [appLockEnabled]'s doc comment. Called only after
  /// `KeystoreService.retoggleProtection` has already migrated the storage this gate reads,
  /// so the two never disagree about which mode is actually in effect.
  void setAppLockEnabled({required bool value}) => _appLockEnabled = value;

  /// Whether the app currently withholds pane content, agent names and Host names (R-31-04-02
  /// belongs to `lock_screen.dart` and `MainActivity.kt`; this flag is the signal both would
  /// read). Unconditionally `false` while App Lock is off (R-13-064, R-31-04-12): there is no
  /// gate to pass, so nothing this app builds may show `/lock` or otherwise treat the phone
  /// as locked, regardless of whether a real `unlock()` has ever run this session.
  bool get isLocked => _appLockEnabled && _locked;

  /// The cached key [_deviceStaticKey] backs; see that field's doc comment.
  SimpleKeyPair? get deviceStaticKey => _locked ? null : _deviceStaticKey;

  /// The biometric types `local_auth` reports as currently usable, for a caller's glyph and
  /// label lookup (R-22-069, R-22-070, `docs/32-design-language.md` R-32-407). This raises no
  /// system prompt: `getAvailableBiometrics()` is capability detection, not authentication.
  Future<List<BiometricType>> availableBiometrics() =>
      _localAuth.getAvailableBiometrics();

  /// Re-authenticates on cold start and after the 120-second background timeout (R-22-017,
  /// R-13-064). A no-op, with no platform prompt, when the app is already unlocked. On
  /// success, marks the app unlocked and clears `MainActivity.kt`'s `FLAG_SECURE`
  /// (R-31-04-02).
  Future<Result<void>>? _pendingUnlock;
  int _authenticationGeneration = 0;

  Future<Result<void>> unlock() {
    if (!_locked) return Future.value(const Ok(null));
    return _pendingUnlock ??= _authenticate(force: false).whenComplete(() {
      _pendingUnlock = null;
    });
  }

  /// Re-authenticates unconditionally, for the third R-22-017 trigger: before a destructive
  /// action (revoke pairing, clear terminal history), regardless of the current lock state or
  /// how recently the person last unlocked. Per R-31-04-11 this MUST raise the platform sheet
  /// in place on the screen that holds the action, never present `/lock`; this method does
  /// exactly that and, win or lose, leaves [isLocked] exactly as it was before the call —
  /// a failed confirmation denies one action, it does not lock the whole session.
  Future<Result<void>> reauthenticateForDestructiveAction() =>
      _authenticate(force: true);

  /// Called from a `WidgetsBindingObserver.didChangeAppLifecycleState`. This file owns only
  /// the lock policy, not the observer's registration: a later work package's app root wires
  /// that, per this work package's `Publishes.` line in `docs/90-implementation-plan.md`
  /// §5.2.
  void noteLifecycleChange(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgroundedAt ??= _now();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      final backgroundedAt = _backgroundedAt;
      _backgroundedAt = null;
      if (backgroundedAt != null &&
          _now().difference(backgroundedAt) >= backgroundLockTimeout) {
        _lock(); // R-22-017's 120-second trigger.
      }
      return;
    }
    if (state == AppLifecycleState.detached) {
      // Defence in depth for R-31-04-01's "at once when the process is killed": most
      // platforms never deliver a further frame after this state, so `_locked` staying
      // true costs nothing, and it closes the gap on the platforms where the engine can
      // detach without a full process kill.
      _lock();
    }
    // `AppLifecycleState.inactive` is a brief transitional state (an incoming call, the
    // notification shade) that R-22-017 does not name as a trigger; it is intentionally
    // ignored here.
  }

  Future<Result<void>> _authenticate({required bool force}) async {
    if (!force && !_locked) {
      return const Ok(null);
    }

    // R-22-013: this read is the single OS-triggered authentication event, per this file's
    // top doc comment. `keystore.dart` classifies a failure as `KeyInvalidatedException` or
    // `BiometricAuthenticationException`; both pass through unchanged for
    // `lock_screen.dart` to pattern-match on.
    final generation = _authenticationGeneration;
    final keyResult = await _keystore.deviceKeyPair();
    if (generation != _authenticationGeneration) {
      return const Err('authentication ended because the app locked');
    }
    return switch (keyResult) {
      Ok(:final value) => _markUnlocked(value),
      Err(:final message, :final cause) => Err(
        'read the biometric-gated device key: $message',
        cause: cause,
      ),
    };
  }

  Result<void> _markUnlocked(SimpleKeyPair key) {
    _deviceStaticKey = key;
    if (_locked) {
      _locked = false;
      _setNativeLocked(false);
    }
    _backgroundedAt = null;
    return const Ok(null);
  }

  void _lock() {
    _authenticationGeneration++;
    _keystore.endAuthenticationSession();
    _deviceStaticKey = null;
    if (!_locked) {
      _locked = true;
      _setNativeLocked(true);
    }
  }
}
