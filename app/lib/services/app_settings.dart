/// Local, phone-only preferences the Settings screen's `APPEARANCE` and `FEEL` groups own:
/// theme mode, terminal text size and both haptic switches
/// (`docs/31-mockups/15-appearance.md`, R-31-15-01 through R-31-15-04, R-30-112,
/// R-32-010).
///
/// Self-declared under Phase 21's `Owns.` line (R-90-018): no earlier phase named this path in
/// `docs/90-implementation-plan.md` §5.2 or §5.3. `settings_screen.dart` (`WP-21-b`) is its
/// only writer. R-03-130 retires the Safe typing preference.
///
/// Backed by `shared_preferences`, mirroring `plain_store.dart`'s own `SharedPreferencesAsync`
/// pattern (R-20-038) rather than inventing a third preferences mechanism: every value here is
/// a plain local preference like a device name, not a secret `keystore.dart` protects, per
/// R-13-063's own scope.
///
/// This file persists a value and republishes the current settings on [changes]. `app.dart`
/// subscribes to apply the theme mode to `MaterialApp.themeMode` and overrides
/// `MediaQuery.platformBrightness` below the root with the resolved brightness, so every
/// `AppColor.of(context)` reader agrees with the chosen mode (R-22-051, R-32-013).
library;

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/result/result.dart' show Err, Ok, Result;

/// `R-30-112`, `R-32-010`: the three permitted theme modes, in the mockup's fixed order.
enum AppThemeMode { system, light, dark }

/// `R-32-208`'s default `type.mono.terminal` size.
const int defaultTerminalTextSize = 13;

/// One immutable snapshot of every preference this file owns.
final class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.terminalTextSize = defaultTerminalTextSize,
    this.hapticsEnabled = true,
    this.keyPressHapticsEnabled = true,
    this.appLockEnabled = false,
    this.appLockOfferShown = false,
  });

  /// `R-30-112`: `System` is the default.
  final AppThemeMode themeMode;

  /// `R-32-208`: one of the seven permitted sizes, default 13.
  final int terminalTextSize;

  /// `R-31-15-04`: off silences every haptic in the app, including the error haptic.
  final bool hapticsEnabled;

  /// Forced off (and disabled) whenever [hapticsEnabled] is off; see
  /// `docs/31-mockups/15-appearance.md` callout 13.
  final bool keyPressHapticsEnabled;

  /// `R-03-090`: optional, default off. Gates access behind the operating-system biometric
  /// or passcode challenge (`docs/13-security-pairing.md` R-13-064) when on; storage and
  /// pairing both work with this off, per the same rule.
  final bool appLockEnabled;

  /// `R-03-091`/`R-30-521`: whether the one-time App Lock offer has already fired, at the
  /// first arrival at `/hosts/:hostId/agents` after the first successful pair. Unlike the
  /// OS-level notification permission, nothing outside this app remembers that the offer was
  /// made, so this flag is the only thing standing between "exactly once" and asking forever.
  final bool appLockOfferShown;

  AppSettings copyWith({
    AppThemeMode? themeMode,
    int? terminalTextSize,
    bool? hapticsEnabled,
    bool? keyPressHapticsEnabled,
    bool? appLockEnabled,
    bool? appLockOfferShown,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    terminalTextSize: terminalTextSize ?? this.terminalTextSize,
    hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
    keyPressHapticsEnabled:
        keyPressHapticsEnabled ?? this.keyPressHapticsEnabled,
    appLockEnabled: appLockEnabled ?? this.appLockEnabled,
    appLockOfferShown: appLockOfferShown ?? this.appLockOfferShown,
  );
}

/// The one reader/writer of these preferences: `shared_preferences` 2.5.5, mirroring
/// `plain_store.dart`'s constructor and error-handling shape exactly.
class AppSettingsService {
  AppSettingsService({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  static const _themeModeKey = 'app_theme_mode';
  static const _terminalTextSizeKey = 'terminal_text_size';
  static const _hapticsEnabledKey = 'haptics_enabled';
  static const _keyPressHapticsEnabledKey = 'key_press_haptics_enabled';
  static const _appLockEnabledKey = 'app_lock_enabled';
  static const _appLockOfferShownKey = 'app_lock_offer_shown';

  final StreamController<AppSettings> _controller =
      StreamController<AppSettings>.broadcast();

  /// The most recently loaded or written snapshot. `routing.dart`'s route builders run
  /// synchronously (`go_router` calls them with no `await`) and cannot each perform their own
  /// `load()`, so they read this cache instead when they need the current App Lock setting to
  /// construct a `KeystoreService`/`BiometricGate`. Starts at the documented defaults, which
  /// is correct for a session that has not loaded yet: App Lock off is also the true default
  /// for a fresh install (R-03-090). `routing.dart`'s `_resolveStartupRedirect` awaits one
  /// real [load] before any other route builds, so every synchronous reader after cold start
  /// sees the persisted value, not just this placeholder.
  AppSettings _current = const AppSettings();

  /// See [_current]'s doc comment.
  AppSettings get current => _current;

  /// Republishes the current settings after every successful [load], which includes the one
  /// each successful write performs. `app.dart` subscribes to apply the theme mode (R-22-051).
  Stream<AppSettings> get changes => _controller.stream;

  /// Reads every preference, defaulting each one independently so a partially written store
  /// (or a fresh install) never fails the whole read.
  Future<Result<AppSettings>> load() async {
    try {
      final settings = AppSettings(
        themeMode: _parseThemeMode(await _preferences.getString(_themeModeKey)),
        terminalTextSize:
            await _preferences.getInt(_terminalTextSizeKey) ??
            defaultTerminalTextSize,
        hapticsEnabled: await _preferences.getBool(_hapticsEnabledKey) ?? true,
        keyPressHapticsEnabled:
            await _preferences.getBool(_keyPressHapticsEnabledKey) ?? true,
        appLockEnabled: await _preferences.getBool(_appLockEnabledKey) ?? false,
        appLockOfferShown:
            await _preferences.getBool(_appLockOfferShownKey) ?? false,
      );
      _current = settings;
      if (!_controller.isClosed) {
        _controller.add(settings);
      }
      return Ok(settings);
    } on Exception catch (e) {
      return Err('load app settings', cause: e);
    }
  }

  Future<Result<void>> setThemeMode(AppThemeMode mode) =>
      _write(() => _preferences.setString(_themeModeKey, mode.name));

  /// The caller MUST have already validated [size] against `AppType.monoTerminalSizes`
  /// (R-32-208); this method only persists it.
  Future<Result<void>> setTerminalTextSize(int size) =>
      _write(() => _preferences.setInt(_terminalTextSizeKey, size));

  Future<Result<void>> setHapticsEnabled({required bool value}) =>
      _write(() => _preferences.setBool(_hapticsEnabledKey, value));

  Future<Result<void>> setKeyPressHapticsEnabled({required bool value}) =>
      _write(() => _preferences.setBool(_keyPressHapticsEnabledKey, value));

  /// `R-03-092`/`R-31-15-18`: persists the switch alone. The storage-mode migration itself
  /// (R-13-073, R-22-083) is `KeystoreService.retoggleProtection`'s job; a caller MUST call
  /// that with this writer as its persistence callback. The transaction orders the policy
  /// and key writes so a stored `true` never precedes the required key protection.
  Future<Result<void>> setAppLockEnabled({required bool value}) =>
      _write(() => _preferences.setBool(_appLockEnabledKey, value));

  /// `R-03-091`/`R-30-521`: set once, right before or after the one-time offer is evaluated,
  /// regardless of whether the person saw a sheet or it was skipped silently (R-30-523) — the
  /// trigger moment itself only ever happens once.
  Future<Result<void>> setAppLockOfferShown({required bool value}) =>
      _write(() => _preferences.setBool(_appLockOfferShownKey, value));

  Future<Result<void>> _write(Future<void> Function() write) async {
    try {
      await write();
    } on Exception catch (e) {
      return Err('store an app setting', cause: e);
    }
    await load();
    return const Ok(null);
  }

  AppThemeMode _parseThemeMode(String? raw) => switch (raw) {
    'light' => AppThemeMode.light,
    'dark' => AppThemeMode.dark,
    _ => AppThemeMode.system,
  };

  Future<void> dispose() => _controller.close();
}
