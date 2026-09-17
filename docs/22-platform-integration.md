# 22 — Platform Integration

**Targets:** Android (API 33+) and iOS (15.0+). No web, no desktop. Flutter 3.47.0 / Dart 3.13.0.

This document specifies every place the app touches the operating system. Each topic is organised by
capability first, then by framework. The master table in section 8 collects every package. Every
package version in this document MUST match the dependency table in `docs/20-mobile-framework.md`
section 6, which is the repository-wide dependency-version owner.

---

## 1. Secret Storage

### 1.1 Native Primitives

#### iOS Keychain

**R-22-001** The app MUST store the Device Curve25519 private key as keychain **data** with the
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` accessibility flag. This flag prevents the key from
appearing in iCloud backups and from migrating to a new device during a direct device-to-device
transfer. The key is stored as application data, not as a Secure Enclave key, because the iOS Secure
Enclave does not support Curve25519. See R-22-003.

**R-22-002** A key that MUST survive device migration (for example an identity key re-used after a
phone upgrade) MUST use `kSecAttrAccessibleAfterFirstUnlock` without `ThisDeviceOnly`. The
implementer MUST document the trade-off: the key travels with an encrypted Finder or iTunes backup
and with a direct device-to-device migration, but does NOT sync through iCloud Keychain unless
`kSecAttrSynchronizable` is also set.

**R-22-003** The iOS Secure Enclave does NOT hold the Device private key. The Secure Enclave
supports exactly one curve: `secp256r1` (NIST P-256). It does not support Curve25519. No document may
claim that the Device Curve25519 key stays inside the Secure Enclave. The key is stored as keychain
data protected by operating-system biometric access control, per
`docs/13-security-pairing.md` R-13-043, R-13-044 and R-13-063. A future hardware-backed P-256
upgrade is recorded in R-13-045, not as an open implementation choice.

**R-22-004** The pairing design in `docs/13-security-pairing.md` MUST account for the Curve25519
constraint: the key is stored as keychain data and is exportable to app code for the Noise DH
operation. Biometric access control gates the read, not the key generation.

**R-22-005** Keychain items with `ThisDeviceOnly` are invalidated when the device passcode is removed
and re-added, or when the user erases all content and settings. They survive iOS upgrades and ordinary
restarts.

#### Android Keystore

**R-22-006** The app MUST store the Device Curve25519 private key as Android Keystore data. The
Android Keystore supports `KeyProperties.KEY_ALGORITHM_EC` with curve `secp256r1` (NIST P-256) for
hardware-backed keys. KeyMint v2 adds Curve25519 for signing and key agreement, and the
`minSdk 33` floor guarantees KeyMint v2 on every device, but Curve25519 Keystore support is not
present on all devices because Secure Elements do not currently implement curve 25519. The app
MUST generate the Curve25519 keypair in software using `X25519()` from the `cryptography` package,
then store the private key bytes in the Android Keystore as encrypted data. The app MUST request
StrongBox backing when available by checking `FEATURE_STRONGBOX_KEYSTORE` at run time. StrongBox
requires API 28, which the `minSdk 33` floor satisfies, but StrongBox availability is
device-dependent: not every device has a Secure Element. The app MUST fall back to TEE-backed
Keystore when StrongBox is absent. This rule fixes the storage backend only, unconditionally;
whether the generated key also carries `setUserAuthenticationRequired(true)` depends on the App
Lock setting, per R-22-007 and R-22-082.
Source: `https://developer.android.com/privacy-and-security/keystore` and
`https://source.android.com/docs/security/features/keystore`.

**R-22-007** When App Lock is enabled (`docs/03-product-decisions.md` R-03-090), a key used for
the App Lock gate MUST be generated with `setUserAuthenticationRequired(true)`. The pinned
Android wrapper (R-22-012) generates this key with a zero-second authentication validity window,
so the Keystore or StrongBox hardware authorises exactly one read per unlock, not a 120-second
window; R-22-017 states where the 120-second re-authentication cadence is actually enforced.
When App Lock is disabled, the key carries no such flag, per R-22-082.

**R-22-008** Hardware-backed keys in Android Keystore are non-exportable. A Curve25519 key generated
in software and stored as Keystore data is protected by Keystore encryption but is readable by app
code after biometric authentication. Public keys are always exportable.

### 1.2 Known Failure Modes

**R-22-009** Android auto-backup (`android:allowBackup="true"`, the default) backs up app data to
Google Drive but does NOT include Keystore key material. On restore to a new device, the Keystore
keys are absent and any stored ciphertext encrypted with those keys is unrecoverable. The app MUST
set `android:allowBackup="false"` in the manifest, AND MUST handle the case where a previously paired
key is missing after restore by requiring re-pairing.

**R-22-010** On both platforms, adding a new biometric enrolment (fingerprint, face) invalidates keys
that were created with `setUserAuthenticationRequired(true)` (Android) or
`kSecAccessControlBiometryCurrentSet` (iOS). The app MUST detect
`KeyPermanentlyInvalidatedException` (Android) or `errSecAuthFailed` (iOS) and prompt the user to
re-enrol and re-pair.

**R-22-011** iOS keychain items with `ThisDeviceOnly` are NOT preserved during a direct
device-to-device migration (Quick Start). The safer rule is R-22-001: assume `ThisDeviceOnly` keys
are lost on device change, and require re-pairing.

### 1.3 Wrapper Packages

| Framework | Package | Version | Licence | Source |
|-----------|---------|---------|---------|--------|
| Flutter | `flutter_secure_storage` | 10.3.1 | BSD-3-Clause | https://pub.dev/packages/flutter_secure_storage |

**R-22-012** `flutter_secure_storage` uses `kSecAttrAccessibleWhenUnlocked` by default on iOS
(migratable). The app MUST configure it to use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` via the
`IOSOptions` parameter. On Android, the pinned 10.3.1 wrapper already satisfies R-22-006's and
R-22-013's biometric-gating requirement natively: `AndroidOptions.biometric(enforceBiometrics: true)`
generates a hardware-backed AES key with `setUserAuthenticationRequired(true)`, checks
`FEATURE_STRONGBOX_KEYSTORE` and requests StrongBox when available, falls back to TEE-backed
Keystore when it is absent or when StrongBox key generation fails, and throws if the device has no
PIN, pattern, password or biometric enrolled. This was confirmed against the pinned source
(`android_options.dart`, `KeyCipherImplementationAES23.java`). The app MUST use
`AndroidOptions.biometric()`; a hand-written platform channel to the native Keystore API is needed
only if a future version pin regresses this behaviour.

---

## 2. Biometric Unlock

### 2.1 The Rule: OS-Enforced Key Gating

**R-22-013** When App Lock is enabled (`docs/03-product-decisions.md` R-03-090), the app MUST
gate access on the operating system's biometric check, not on an app-level boolean. The correct
pattern: store the Curve25519 private key as Keystore or Keychain data with
`setUserAuthenticationRequired(true)` (Android) or a `SecAccessControl` combining
`.biometryCurrentSet` and `.devicePasscode` with `.or`, never `.and` (iOS). `.biometryCurrentSet`
alone would deny the Keychain read to a passcode-only device even after R-22-014's passcode
fallback succeeds at the app level, so both routes must succeed at the Keychain layer too. When
the app needs the key, it asks the Keystore or Keychain to read the data. The OS presents the
biometric prompt and, on success, allows the read. The app never sees a "yes/no" boolean it can
bypass. On iOS, the Device MUST reuse the device-key read's `LAContext` for later Host-record
reads in that unlocked session, including records protected by older builds. Those reads MUST
set `interactionNotAllowed` so they cannot open additional authentication sheets. Locking MUST
invalidate the context; a new unlock or destructive-action authentication uses a fresh one.

The app root MUST hide protected routes, modal contents and accessibility content while locked.
Navigation MUST NOT bypass this gate. Locking MUST close active and pending relay connections and
reject their delayed work. The Device MUST NOT generate a replacement identity to satisfy an
unlock when its existing key is missing. iOS MUST cover sensitive content before UIKit captures
an inactive scene and retain that cover until Flutter submits a safe foreground frame.
Concurrent unlock requests MUST share the same pending device-key read. A result received after
locking MUST NOT unlock the app. When App Lock is disabled, the app reads the same Keystore or
Keychain data with no authentication challenge at all, per R-22-082; the trade-off that mode accepts
is recorded in
`docs/decisions/ADR-009-optional-app-lock.md`.

**Reason this rule holds while App Lock is on:** An app-level boolean (`if
(biometricPrompt.show() == OK) { unlock() }`) is bypassable with a debugger, a tweak, or a
repackaged binary. The OS-enforced key gate means the private key is cryptographically
unavailable without a real biometric match. This is the same pattern used by banking apps and
password managers.

### 2.2 Native APIs

- **iOS:** `LocalAuthentication` framework (`LAContext`) with `SecAccessControl` flags on Keychain
  items. `LAPolicy.deviceOwnerAuthenticationWithBiometrics` for biometrics-only;
  `deviceOwnerAuthentication` for biometrics-or-passcode fallback.
- **Android:** `BiometricPrompt` (AndroidX `androidx.biometric:biometric:1.2.0-alpha05`) with
  `setAllowedAuthenticators(BIOMETRIC_STRONG | DEVICE_CREDENTIAL)`.

### 2.3 Fallback When Biometrics Are Absent

**R-22-014** While App Lock is enabled, when biometrics are not enrolled, not available, or
locked out (5 failed attempts on Android StrongBox triggers a 30-second lockout; 3 failed Face ID
attempts fall back to device passcode), the app MUST fall back to the device passcode or password
via `DEVICE_CREDENTIAL` (Android) or `LAPolicy.deviceOwnerAuthentication` (iOS). The app MUST NOT
offer a weaker fallback such as a 4-digit PIN inside the app. This rule has no effect while App
Lock is off, because no biometric or passcode check runs at all in that mode.

### 2.4 Required Manifest and Plist Entries

**R-22-015** iOS `Info.plist` MUST include:

```xml
<key>NSFaceIDUsageDescription</key>
<string>Unlock Herdr Remote with Face ID to view your terminal sessions.</string>
```

Touch ID does not require a usage description key; Face ID does. Provide both for safety.

**R-22-016** Android `AndroidManifest.xml` MUST include:

```xml
<uses-permission android:name="android.permission.USE_BIOMETRIC" />
```

This is a `normal` permission, granted at install time. No runtime request is needed.

### 2.5 Re-Authentication Policy

**R-22-017** While App Lock is enabled, the app MUST re-authenticate:

- On cold start (process not running).
- On return to foreground after **120 seconds** in background.
- Before every destructive action (revoke pairing, clear terminal history). Disconnecting is not
  destructive, per `docs/30-ux-spec.md` R-30-960, and a switch of connected computer is an ordinary
  disconnect, per `docs/03-product-decisions.md` R-03-044, so neither re-authenticates.

While App Lock is disabled, none of these three triggers raise a challenge, and the app opens
directly every time, per `docs/31-mockups/04-lock.md` R-31-04-12.

The 120-second foreground timeout is an app-level session timer, tracked entirely in
`app/lib/services/biometric_gate.dart`: it records the backgrounded timestamp and compares it
against the resume timestamp. It is not enforced by any OS Keystore or Keychain caching. Neither
pinned wrapper package exposes that caching for this key: the Android path generates the native
key with a zero-second authentication validity window (R-22-007), and the iOS `LAContext`-reuse
mechanism the package offers applies only to a Secure Enclave key, which R-13-044 forbids for this
Curve25519 key. Each of the three re-authentication triggers therefore performs a fresh Keystore
or Keychain read, and so a fresh OS prompt, every time App Lock is on.

This is the single biometric background lock timeout for the whole repository, and it applies
only while App Lock is enabled.

### 2.6 Wrapper Packages

| Framework | Package | Version | Licence | Source |
|-----------|---------|---------|---------|--------|
| Flutter | `local_auth` | 3.0.2 | BSD-3-Clause | https://pub.dev/packages/local_auth |

**R-22-018** While App Lock is enabled, the Keystore or Keychain key read (R-22-013) IS the
single OS-triggered authentication gate, used alone. The app MUST NOT call `local_auth`'s
`authenticate()` before or alongside that read: on Android, its `BiometricPrompt` call carries no
`CryptoObject`, so it has zero cryptographic effect on the Keystore key and only raises a second,
independent OS prompt; on iOS it evaluates a private `LAContext` the Keystore read never shares.
`local_auth` is used only for `getAvailableBiometrics()`, which raises no prompt: R-22-069 and
R-22-070 own its use to build `/lock`'s glyph and label, and R-31-15-18 owns its use to decide
whether the `App Lock` switch on `docs/31-mockups/15-appearance.md` can be turned on.

**R-22-069** Before it paints `/lock`, the app MUST call `getAvailableBiometrics()` and MUST choose
the glyph and the primary label from the returned `BiometricType` values, not from
`Platform.isIOS` or `Platform.isAndroid`. iOS reports `fingerprint` on a Touch ID device and `face`
on a Face ID device; Android reports `fingerprint`, `face` or `iris` on some devices and only the
`strong` or `weak` classification on others. `docs/32-design-language.md` `R-32-407` owns the glyph
map and `docs/31-mockups/04-lock.md` owns the labels and the two wireframes.

**R-22-070** When the returned list carries only `strong` or `weak`, the app MUST fall back to the
generic glyph and label. It MUST NOT infer a sensor type or a sensor position from the manufacturer,
the model or the API level. `local_auth` reports no sensor position, so no copy may state where a
sensor is.

Source: `local_auth` `BiometricType` API documentation, which states that some platforms report a
specific biometric type while others report only the `strong` or `weak` classification:
`https://pub.dev/documentation/local_auth/latest/local_auth/BiometricType.html`.

### 2.7 App Lock Off: Storage With No Authentication Challenge

**R-22-082** When App Lock is off (`docs/03-product-decisions.md` R-03-090), the app MUST store
the Device Curve25519 private key with no operating-system authentication requirement: on
Android, `AndroidOptions()` with no `biometric` parameter, so `setUserAuthenticationRequired` is
never set on the generated key; on iOS, a `SecAccessControl` built from
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` alone, with `.biometryCurrentSet` and
`.devicePasscode` both omitted. The key stays app-sandboxed, non-exportable to another app, and
outside iCloud and Android auto-backup exactly as R-22-001 and R-22-006 already require; only the
extra authentication challenge is absent. When App Lock is on, the app MUST use
`AndroidOptions.biometric(enforceBiometrics: true)` (R-22-012) and the `SecAccessControl` of
R-22-013.

**R-22-083** Toggling App Lock MUST read the stored value under the current protection level,
delete the old entry, then write the value back under the new one, using `flutter_secure_storage`'s
existing read, delete and write calls with the changed `AndroidOptions` or `IOSOptions` (R-22-012).
The delete MUST come before the write. `flutter_secure_storage`'s Android implementation keeps
every value in one shared file, keyed by the same string regardless of `AndroidOptions`, so a write
followed by a delete on that key would destroy the value the write just stored. This MUST NOT call
key generation again and MUST NOT change the Curve25519 keypair, the pinned Host keys, the routing
handles or the relay origin, per `docs/13-security-pairing.md` R-13-073. A read or write that fails
MUST attempt to restore the previous protection level and switch state, and MUST show the error
state of `docs/31-mockups/15-appearance.md`. The Device MUST persist the off policy before weakening
the private key's protection, and MUST protect that key before persisting an on policy. If the OS
also rejects recovery, the Device MUST NOT report App Lock as enabled over an unprotected key.
An authenticated disable may leave the switch off with an error in this case. Unlock MUST fail
closed if recovery leaves the existing identity unavailable.

---

## 3. Local Notifications and Push Wake

### 3.1 Model: Local Detail and Content-Free Push

**R-22-019** Detailed notifications MUST remain local and use encrypted `agent_status` events.
The app MUST support the content-free push exception in `docs/03-product-decisions.md` R-03-136.
Push delivery does not guarantee that the app runs in the background. On launch or reconnect,
the app MUST show unseen attention state without stale local notifications (R-22-024).
Public wording MUST follow R-03-063.

### 3.2 Notification Channel and Category Configuration

**R-22-020** The app MUST configure one notification channel on Android and one notification category
on iOS:

- **Android:** A channel with id `herdr_agent_status`, name `Agent status`, importance `IMPORTANCE_DEFAULT`,
  and no vibration override. The channel is created on first launch before any notification is posted.
- **iOS:** No category registration is needed for a simple alert notification. The app requests
  authorization for alerts, sounds and badges. The app icon badge MUST show the count of unread
  rows across every Host's notification log, the same count the in-app `Notifications`
  destination shows for one Host, and MUST fall to zero when the last row is read or removed
  (amended 2026-09-16 by the product owner, who expected `(1)` on the home screen; until then the
  rule read "not badges, because the attention marker lives in-app"). The app sets the badge
  itself through `UNUserNotificationCenter.setBadgeCount` on every change of that count, never by
  letting posted notifications accumulate one.

### 3.3 Permission Request Timing

**R-22-021** The app MUST request the notification permission once, at the moment `R-30-509`
names — the first arrival at the agent list after the first pair, never on `/welcome`. The app
MUST NOT request the
permission a second time. `POST_NOTIFICATIONS` is a runtime permission;
the app requests it with `ActivityResultContracts.RequestPermission()` targeting
`Manifest.permission.POST_NOTIFICATIONS`. The minimum SDK is 33, so the
runtime request is unconditional. On iOS, the app calls
`UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])`.
After the permission is granted, the app always posts an alert for an event that earns one.
Source: `https://developer.android.com/develop/ui/compose/notifications/notification-permission`
and `https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications`.

### 3.4 Notification Content from `agent_status`

**R-22-022** The local notification content MUST use the `agent_status` payload fields.
`docs/11-relay-protocol.md` owns these fields:

| Notification field | Payload field | Example |
|---|---|---|
| Title | `agent_kind` + `status` | `claude is done` |
| Body | `tab_title` + `pane_title` | `main.py in workspace-alpha` |
| Data: host_id | `host_id` | Routes the tap |
| Data: pane_id | `pane_id` | Routes the tap |
| Data: workspace_id | `workspace_id` | For deep navigation |
| Data: tab_id | `tab_id` | For deep navigation |

The notification MUST NOT carry pane text, terminal content, or any data beyond the fields above.

### 3.5 Notification Tap Route

**R-22-023** A local notification tap MUST route to `/hosts/:hostId/panes/:paneId`, where `hostId`
is the `host_id` and `paneId` is the `pane_id` from the `agent_status` payload. `go_router`
resolves this route to the terminal view. The degenerate cases are owned by `docs/30-ux-spec.md`:

- Host disconnected: route to the Host screen, show the disconnected state, offer reconnect.
- Pane closed: route to the Host tree, show `That pane has closed`.
- App locked: hold the route, present the biometric lock, then continue to the held route.
- Host unknown or unpaired: route to the Host list and show the pairing entry point.

### 3.6 Behaviour on Relaunch

**R-22-024** When the app relaunches after suspension or termination, it MUST reconnect to the relay,
request current state via `tree_request` (R-11-043), and show unseen attention state in-app. The app
MUST
NOT synthesise a system notification for a stale event. Unseen attention is shown as badges and
markers in the agent list, per `docs/30` R-30-501.

### 3.7 First-Run Permission and Recovery

**R-22-071** The app MUST request the notification permission once, at the moment `R-30-509`
names, and MUST NOT
request it a second time. The minimum SDK is 33, so the app requests
`android.permission.POST_NOTIFICATIONS` at runtime with
`ActivityResultContracts.RequestPermission()`. On iOS the app calls
`UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])`. A second
call on iOS does nothing: the system records the first response and never prompts again. The app
MUST NOT show its own dialog that imitates the platform permission sheet.
Source: `https://developer.android.com/develop/ui/compose/notifications/notification-permission`
and `https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications`.

**R-22-072** The app MUST read the current notification authorisation state on every resume. A
person can revoke the permission in the operating system settings at any time. On Android the app
checks `NotificationManagerCompat.areNotificationsEnabled()`. On iOS the app calls
`UNUserNotificationCenter.current().getNotificationSettings()` and reads
`settings.authorizationStatus`. The agent-list attention marker MUST follow the current state, so
a revoked permission shows the alerts-off marker of `docs/31-mockups/06-agent-list.md`.
Source: `https://developer.android.com/reference/androidx/core/app/NotificationManagerCompat#areNotificationsEnabled()`
and `https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/getnotificationsettings(completionhandler:)`.

**R-22-073** The app MUST be able to open the operating system notification settings for this app.
This is the only recovery from a refusal. On Android the app launches an intent with
`Settings.ACTION_APP_NOTIFICATION_SETTINGS` and extra `EXTRA_APP_PACKAGE` set to the app package
name. On iOS the app opens `UIApplication.openSettingsURLString` with
`UIApplication.shared.open(url)`. The app MUST NOT offer an app-level toggle that pretends to
re-enable alerts.
Source: `https://developer.android.com/reference/android/provider/Settings#ACTION_APP_NOTIFICATION_SETTINGS`
and `https://developer.apple.com/documentation/uikit/uiapplication/opensettingsurlstring`.

**R-22-074** The app MUST NOT request the notification permission a second time and MUST NOT show
its own dialog that imitates the platform sheet. On iOS a second request is impossible: the system
never prompts after the first response. On Android a second `RequestPermission` launch re-shows
the system dialog only if the user has not selected `Don't allow` and then checked
`Don't ask again`. The app MUST NOT rely on that path. The only recovery is R-22-073.
Source: `https://developer.android.com/develop/ui/compose/notifications/notification-permission`
and `https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications`.

### 3.8 Client-Side Package

| Framework | Package | Version | Licence | Source |
|-----------|---------|---------|---------|--------|
| Flutter | `flutter_local_notifications` | 22.3.0 | BSD-3-Clause | https://pub.dev/packages/flutter_local_notifications |

### 3.9 Content-Free Push Setup

**R-22-089** iOS MUST use native APNs registration, not Firebase.
`app/ios/Runner/Runner.entitlements` MUST declare `aps-environment`.
The Xcode project MUST reference this file through `CODE_SIGN_ENTITLEMENTS`.
The signed entitlement and provisioning profile MUST match the APNs environment.
The operator MUST enable Push Notifications for the app identifier.
Local installs signed by Xcode's free Personal Team MAY set
`CODE_SIGN_ENTITLEMENTS=Runner/Personal.entitlements` to select the empty entitlement file.
This development-only build omits APNs because that team cannot provision Push Notifications.
It MUST retain the local notification and foreground relay paths. Distribution builds MUST retain
the APNs entitlement. `docs/40-repo-tooling.md` section 7.2.3 gives the local build command.
After notification permission is granted under R-22-021, the app MUST call
`UIApplication.registerForRemoteNotifications()`.
Source: <https://developer.apple.com/documentation/bundleresources/entitlements/aps-environment>.

**R-22-090** The iOS bridge MUST use the channel `dev.herdr.herdr_mobile/push`.
It MUST deliver the APNs device token as a hexadecimal string through `token`.
It MUST report registration failure through `failed`, without token data.

**R-22-091** Android MUST use `firebase_messaging` for the FCM token.
`docs/20-mobile-framework.md` section 6 owns the dependency pins.
The operator MUST supply `app/android/app/google-services.json` for the app's Android identifier.
This file MUST remain gitignored. Gradle MUST apply `com.google.gms.google-services` only when
this file exists. A clone without this file MUST build and silently skip FCM registration.
FCM token registration MUST NOT cause another notification permission request.
Source: <https://firebase.google.com/docs/cloud-messaging/flutter/get-started>.

**R-22-092** The app MUST register a known push token after `session_joined` on each connection.
It MUST register replacement tokens while connected. The relay frames are owned by
`docs/11-relay-protocol.md`. The app and relay MUST NOT log push tokens or token-bearing frames.
Registration errors MUST NOT prevent normal relay connections or local notifications.

**R-22-093** A content-free push tap MUST open the app through its normal launch or resume flow.
The app MUST reconnect and show the real notification log. It MUST NOT derive a Host or pane
route from the push, or interpret the fixed text as an `agent_status` event.

---

## 4. Background and Reconnect Behaviour

### 4.1 Connection Lifecycle

**R-22-025** The app MUST maintain exactly one WebSocket connection to the relay. That one socket
belongs to the active computer. The app MUST connect to at most one computer at a time, per
`docs/03-product-decisions.md` R-03-043. When the app enters the background:

- **iOS:** The WebSocket is torn down by the OS within seconds. The app MUST close the connection
  cleanly in `applicationDidEnterBackground` and request `beginBackgroundTask` for a grace period to
  send a disconnect frame.
- **Android:** The app MAY keep the WebSocket alive via a foreground service with type `dataSync`.
  The app MUST show a persistent notification ("Connected to Herdr Remote") while the service runs.
  The foreground service is optional in version 1 because local notifications require the app process
  to be alive.

**R-22-026** When the app returns to the foreground, it MUST reconnect the WebSocket and call
`tree_request` (R-11-043) to resynchronise state. The Host responds with `tree_snapshot`. The Device
MUST NOT call a Herdr method directly; only the Host plugin talks to Herdr (R-01-006). See
`docs/11-relay-protocol.md`
for the resynchronisation rule.

### 4.2 Network Transitions

**R-22-027** The app MUST subscribe to connectivity changes. On a network loss (WiFi to cellular,
cellular to WiFi, or complete loss), the app MUST:

1. Detect the change via the connectivity package.
2. Wait for the new network to stabilise (1-second debounce).
3. Attempt reconnection with the backoff schedule in R-22-028.

### 4.3 Reconnect Backoff

**R-22-028** The reconnect backoff schedule recovers the current connection to the active computer.
It MUST NOT be used to reach a different computer, which is a new connection and not a retry, per
`docs/03-product-decisions.md` R-03-044. The schedule:

| Attempt | Delay | Notes |
|---------|-------|-------|
| 1 | 0.5 s | Immediate retry for transient blips |
| 2 | 1 s | |
| 3 | 2 s | |
| 4 | 5 s | |
| 5 | 10 s | |
| 6+ | 30 s | Cap at 30 seconds, repeat indefinitely |

The backoff resets to attempt 1 after any successful connection that lasts at least 30 seconds. A
reconnect never needs a fresh pairing (R-13-037, R-13-038). When the relay discarded the room — a
peer loss (R-11-125) or a relay restart (R-12-039) — the Host re-registers on its own ladder, and a
Device that arrives first receives `handle_unknown` (R-11-117) and retries on this schedule.

This is the single reconnect backoff schedule for the whole repository. No other document
restates it.

### 4.4 Connectivity Packages

| Framework | Package | Version | Licence | Source |
|-----------|---------|---------|---------|--------|
| Flutter | `connectivity_plus` | 7.3.1 | BSD-3-Clause | https://pub.dev/packages/connectivity_plus |

---

## 5. QR Code Scanning for Pairing

### 5.1 Camera Packages

**R-22-029** The app MUST use the device camera to scan a QR code during pairing. The QR code encodes
the pairing URI defined in `docs/11-relay-protocol.md` R-11-140. The scanner MUST support QR code format
only (not all barcode formats) to reduce false positives.

| Framework | Package | Version | Licence | Source |
|-----------|---------|---------|---------|--------|
| Flutter | `mobile_scanner` | 7.4.0 | BSD-3-Clause | https://pub.dev/packages/mobile_scanner |

### 5.2 Permission Strings

**R-22-030** iOS `Info.plist` MUST include:

```xml
<key>NSCameraUsageDescription</key>
<string>Scan the pairing QR code shown in the Herdr Remote plugin to connect to your terminal sessions.</string>
```

**R-22-031** Android `AndroidManifest.xml` MUST include:

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

`CAMERA` is a dangerous permission. The app MUST request it at runtime with a rationale dialog before
showing the scanner. On Android 14+, the `CAMERA` permission is subject to while-in-use restrictions;
the app MUST release the camera when the scanner view is dismissed.

### 5.3 Manual Pairing Phrase Entry Fallback

**R-22-032** The app MUST provide a manual entry screen as a fallback when the camera is unavailable,
not granted, or the QR code cannot be scanned. The manual entry screen MUST accept the relay origin
and the six EFF Diceware words, per `docs/13-security-pairing.md`
R-13-017 and R-13-018. The user types the origin as an
HTTPS URL and the six words in order. The app MUST normalise the words before validation: trim,
lowercase, collapse a run of spaces or hyphens to one separator. The app MUST reject a word that is
not in the EFF long list, a phrase that does not hold exactly six words, and an origin that uses
`http://` for a host outside the section 6 allow list. Manual entry and QR entry MUST converge on one
identical pairing input record.

The entry is six words, never a numeric digit code. An earlier numeric pairing-code format was
retired in favor of the six-word phrase; see `docs/decisions/ADR-004-pairing-phrase-and-routing.md`.

### 5.4 Camera Zoom Bridge

**R-22-088** The app MUST use `dev.herdr.herdr_mobile/camera_zoom` for device zoom capabilities.
`getRange` MUST return raw `minZoom`, `maxZoom`, `wideZoom`, and `switchOverFactors`.
The Dart service MUST divide raw factors by `wideZoom` to obtain the display range.
The UI contract belongs to `R-31-02-13`; this rule owns only the native bridge and conversion.

On iOS, the bridge MUST observe `AVCaptureSession.didStartRunningNotification` and read the running
session's video input device. This is the actual device that the scanner selected, not a second
camera chosen by the app. The pinned plugin normally selects a virtual triple camera, dual camera,
or wide camera, in that order. The bridge MUST read that device's available zoom bounds and
virtual-device switch-over factors. `wideZoom` MUST identify the wide-camera factor, with `1` for a
device without a wider constituent camera. `setZoom` MUST accept `{zoom: rawFactor, animated: bool}`
and set that device's exact raw factor within its available bounds. This path MUST bypass the
plugin's raw-factor cap of `5`; that cap does not mean display magnification of `5x`. Preset taps
MAY ramp to the target. Pinch updates and reduced motion MUST set the factor without a ramp.

On Android, the bridge MUST use the `ProcessCameraProvider` singleton and
`CameraSelector.DEFAULT_BACK_CAMERA`, as the plugin does. It MUST read
`getCameraInfo(selector).zoomState.value` for the selected camera's minimum and maximum ratios. It
MUST NOT infer this range from the first Camera2 device ID. Android returns `wideZoom: 1` and an
empty `switchOverFactors` list. The Dart service MUST apply the requested ratio through the plugin's
`setZoomScale`, which uses CameraX `setLinearZoom`. For factor `f`, minimum `m`, and maximum `M`,
use `(1 / m - 1 / f) / (1 / m - 1 / M)`. Clamp the factor to the range and the normalized result to
`0..1`. Handle a fixed range without division by zero.

If the running device or valid range is unavailable, report no range. Never substitute a fabricated
maximum. The app MUST leave scanning available without zoom controls, per `R-31-02-13`.

API evidence, not additional product rules:

- [Pinned Dart controller][camera-controller-740] clamps `setZoomScale` to `0..1`.
- [Pinned iOS implementation][camera-ios-740] applies the raw-factor cap and establishes the
  wide-camera reference factor.
- [Pinned iOS selector][camera-selector-740] defines the default triple/dual/wide discovery order.
- [Pinned Android implementation][camera-android-740] uses the default back-camera selector and
  calls `setLinearZoom`.
- [CameraX zoom documentation][camera-zoom] defines linear zoom as linear field-of-view control,
  not linear magnification.
- [CameraX ZoomState][camera-state] defines the selected camera's minimum and maximum zoom ratios.
- [ProcessCameraProvider][camera-provider] defines the process singleton and selector-based camera
  information API.

[camera-controller-740]: https://github.com/juliansteenbakker/mobile_scanner/blob/v7.4.0/lib/src/mobile_scanner_controller.dart
[camera-ios-740]: https://github.com/juliansteenbakker/mobile_scanner/blob/v7.4.0/darwin/mobile_scanner/Sources/mobile_scanner/MobileScannerPlugin.swift
[camera-selector-740]: https://github.com/juliansteenbakker/mobile_scanner/blob/v7.4.0/darwin/mobile_scanner/Sources/mobile_scanner/MobileScannerCameraSelector.swift
[camera-android-740]: https://github.com/juliansteenbakker/mobile_scanner/blob/v7.4.0/android/src/main/kotlin/dev/steenbakker/mobile_scanner/MobileScanner.kt
[camera-zoom]: https://developer.android.com/media/camera/camerax/configuration#camera-control
[camera-state]: https://developer.android.com/reference/androidx/camera/core/ZoomState
[camera-provider]: https://developer.android.com/reference/androidx/camera/lifecycle/ProcessCameraProvider

---

## 6. Deep Link Handling for `herdr-remote://pair`

### 6.1 iOS URL Scheme Registration

**R-22-033** iOS `Info.plist` MUST register the `herdr-remote` custom URL scheme using
`CFBundleURLTypes`:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>dev.herdr.remote</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>herdr-remote</string>
        </array>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
    </dict>
</array>
```

- `CFBundleURLName` is the abstract identifier for this URL type. It uses the reverse-DNS bundle
  identifier `dev.herdr.remote` to distinguish this app from others that declare the same scheme.
- `CFBundleURLSchemes` is an array of strings. The single entry is `herdr-remote`, the scheme without
  a trailing colon.
- `CFBundleTypeRole` is `Editor` because this app defines the scheme. A `Viewer` role is for schemes
  the app adopts but does not define.

Source: Apple Developer Documentation, `CFBundleURLTypes`:
`https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleurltypes`
and "Defining a custom URL scheme for your app":
`https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app`.

### 6.2 iOS URL Handling at Runtime

**R-22-034** The app MUST adopt the `UIScene` lifecycle, per `docs/20` R-20-028. The system delivers
the pairing URL in two ways:

1. **Cold launch:** The system delivers the URL to
   `scene(_:willConnectTo:options:)`. The app reads `connectionOptions.urlContexts.first?.url` and
   parses it.
2. **Warm launch:** The system delivers the URL to `scene(_:openURLContexts:)`. The app reads
   `URLContexts.first?.url` and parses it.

The app MUST parse the URL with `Uri.parse` in Dart, validate it against the pairing URI rules in
`docs/11-relay-protocol.md` R-11-140, and open `/pair/manual` with the relay origin, the computer
code and the six words filled from the link, per `R-03-073`. It MUST NOT start the handshake on
the link alone; `R-30-958` owns what happens at the press of `Pair`. Both the cold and the warm
delivery MUST reach the same screen with the same fields, and a warm delivery while `/pair/manual`
is already open MUST refill that screen instead of stacking a second one. The app MUST discard a
malformed URL without showing an error to the user.

Source: Apple Developer Documentation, "Defining a custom URL scheme for your app":
`https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app`.

### 6.3 Android Intent Filter

**R-22-035** Android `AndroidManifest.xml` MUST register an `intent-filter` for the `herdr-remote`
scheme inside the launcher activity:

```xml
<activity
    android:name=".MainActivity"
    android:launchMode="singleTask">
    <intent-filter>
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="herdr-remote" android:host="pair" />
    </intent-filter>
</activity>
```

- `android.intent.action.VIEW` is the action for viewing data.
- `android.intent.category.DEFAULT` allows the app to respond to implicit intents.
- `android.intent.category.BROWSABLE` allows the intent filter to be reached from a browser.
- `android:scheme` is `herdr-remote`, specified in lowercase because Android scheme matching is
  case-sensitive.
- `android:host` is `pair`, matching the path component of the pairing URI.
- `android:launchMode` is `singleTask`. If the activity is already running, the system brings it to
  the foreground and delivers the new intent via `onNewIntent()`. The app MUST handle the intent in
  `onNewIntent()` by extracting the URI data and forwarding it to the Flutter engine.

**R-22-036** The `autoVerify` attribute does NOT apply to a custom URL scheme. `autoVerify` is for
Android App Links, which use `http` or `https` schemes and require a verified website association.
The `herdr-remote` scheme is a custom deep link, not an App Link. The app MUST NOT set
`android:autoVerify="true"` on this intent filter.

Source: Android Developer Documentation, "Create deep links":
`https://developer.android.com/training/app-links/deep-linking` and `<data>` element:
`https://developer.android.com/guide/topics/manifest/data-element`.

---

## 6A. App Icon and Brand Mark Resources

`docs/32-design-language.md` owns the masters, the placement constants and the export rules, in
`R-32-410` through `R-32-418`. This section owns only where the generated files are copied and how
each platform is told about them. It restates no image value.

The generated files are committed at `assets/icon/export/`. The implementation copies them; it does
not regenerate them by hand.

### 6A.1 Android launcher icon

**R-22-060**: The three adaptive layers (background, foreground, monochrome) MUST be copied
from `assets/icon/export/android/mipmap-*/` to `android/app/src/main/res/mipmap-*/`, preserving
the density directory names. The adaptive declarations in
`assets/icon/export/android/mipmap-anydpi-v26/` MUST be copied to the matching resource
directory. No legacy raster is required, because `<adaptive-icon>` needs API 26 and the
`minSdk 33` floor is above it.

**R-22-061**: The adaptive icon is declared as:

```xml
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
```

The `<monochrome>` layer supplies the Android 13 themed-icon treatment. Omitting it makes the
launcher fall back to a shrunken full-colour icon inside a tinted circle.

**R-22-062**: The manifest MUST reference the adaptive icon. Both `android:icon` and
`android:roundIcon` resolve to the adaptive declarations in `mipmap-anydpi-v26/`:

```xml
<application
    android:icon="@mipmap/ic_launcher"
    android:roundIcon="@mipmap/ic_launcher_round"
    android:label="Herdr Remote">
```

No legacy raster is required, because `<adaptive-icon>` needs API 26 and the `minSdk 33` floor
is above it.
Source: Android Developer Documentation, "Adaptive icons":
`https://developer.android.com/develop/ui/views/launch/icon_design_adaptive`.

### 6A.2 Android notification icon

**R-22-063**: `ic_stat_agent.png` MUST be copied from
`assets/icon/export/android/drawable-*/` to `android/app/src/main/res/drawable-*/`.

**R-22-064**: The local notification MUST set `ic_stat_agent` as its small icon and MUST NOT set the
launcher icon. Android draws a small icon from its alpha channel alone and applies its own tint, per
`R-32-418`, so a full-colour launcher icon renders as a solid block.

**R-22-065**: The notification accent colour MUST be set explicitly rather than left to the platform
default, so the tint is predictable. The value comes from `docs/32-design-language.md`; this document
states no colour.

Source: Android Developer Documentation, "Notifications overview":
`https://developer.android.com/develop/ui/views/notifications`.

### 6A.3 iOS app icon

**R-22-066**: `assets/icon/export/ios/AppIcon.appiconset/` MUST be copied whole, both
`Icon-1024.png` and `Contents.json`, to `ios/Runner/Assets.xcassets/AppIcon.appiconset/`. The
catalog declares one `universal` `ios-marketing` entry at 1024 x 1024 and Xcode derives every smaller
size from it.

**R-22-067**: The build MUST fail if that file carries an alpha channel or is not 1024 x 1024, per
`R-32-417`. App Store Connect rejects an icon with an alpha channel at upload, which is late and
expensive feedback.

**R-22-068**: iOS MUST NOT declare a separate notification icon, per `R-32-418`.

Source: Apple Developer Documentation, "App icons":
`https://developer.apple.com/design/human-interface-guidelines/app-icons`.

### 6A.4 Brand mark asset copy

- **R-22-086**: `assets/icon/export/brand/ram.png` (1024 wide white silhouette with alpha) MUST be
  copied to `app/assets/brand/ram.png`. The app uses this asset via `widgets/brand_mark.dart` for the
  welcome hero and empty state.

### 6A.5 Launch surface

**R-22-087** The launch surface MUST be `color.bg.base` of the theme the operating-system
appearance selects, and the ground grid of `docs/32-design-language.md` `R-32-332` MUST appear
wherever the platform's launch surface can draw one. The values live in
`docs/32-design-language.md` section 3.2 and MUST NOT be restated here; the native resources map
them.

Amended twice on 2026-09-11. First by the product owner, who saw the grid only inside the splash
icon's circle and wanted it "throughout, not just in the circle". Then by measurement (the launch
capture in `## Sources`), which showed that Android permits no grid anywhere before the first
Flutter frame, so the first amendment's Android half was unimplementable and its resources drew
nothing. The
platforms differ, and the rule states the whole of it:

- **Android (Android 12 and later, so every device at `minSdk 33`).** The launch surface is one
  flat colour and carries **no grid**. `android:windowSplashScreenBackground` MUST be
  `@color/launch_background` (`color.bg.base`): the platform draws it as "a single opaque color"
  and permits no drawable. `LaunchTheme` and `NormalTheme` `android:windowBackground` MUST be the
  same `@color/launch_background`, not a drawable: measured live, the system splash window holds
  until the app draws its first frame, so no window background is ever visible on its own and a
  tiled drawable there is dead weight. The splash icon MUST be the mark alone,
  `@mipmap/ic_launcher_foreground`, never the adaptive `@mipmap/ic_launcher`: the adaptive icon's
  background layer carries the grid and the system masks it to a circle, which is the
  grid-in-a-circle the owner rejected. On Android the grid therefore begins at the first Flutter
  frame, which is where `R-32-332` already puts it.
- **iOS.** `LaunchScreen.storyboard` MUST fill the view with an image view of a `LaunchGrid` image
  set in `Assets.xcassets`, one 40 pt tile at 1x, 2x and 3x with the asset catalog's tile
  slicing, with light and dark appearances in the two `color.bg.grid` values, over the existing
  `LaunchBackground` colour set. A launch storyboard renders a real view hierarchy, so unlike
  Android it does carry the grid. The storyboard MUST NOT draw a mark: iOS shows the icon on the
  way in.

A native launch surface cannot read the app's persisted `Light` or `Dark` override of
`R-30-112`, so when that override differs from the operating-system appearance the first Flutter
frame repaints to the app's ground; that one transition is accepted and MUST NOT be papered over
with a native preference-sync mechanism. On iOS the launch grid aligns to the window's top-left
corner and the first hero screen aligns its grid to the safe area (`R-32-332`); that one shift is
accepted for the same reason. The launch surface MUST NOT draw a second mark, a wordmark, text or
motion. Source: Android "Splash screens",
`https://developer.android.com/develop/ui/views/launch/splash-screen`, read 2026-09-11: "The
window background consists of a single opaque color"; "The app icon ... The launcher icon is the
default"; "one-third of the foreground is masked".

---

## 7. Relay Origin Storage

### 7.1 Canonical Form

**R-22-037** The app MUST store the relay origin in canonical form: scheme, host, and optional
port. No path, no query, no fragment, no trailing slash. Example: `https://relay.example.com`,
`https://relay.example.com:8443`.

### 7.2 HTTPS to WSS Mapping

**R-22-038** The app MUST convert `https://` to `wss://` when constructing a relay protocol path. The
app MUST convert `http://` to `ws://` only for the local-development allow list in R-22-039.

### 7.3 Local-Development Allow List

**R-22-039** The app MUST permit `http://` only for `localhost`, any address in `127.0.0.0/8`, `::1`,
and the RFC 1918 ranges `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`. Such an origin becomes
`ws://` and raises a persistent, non-dismissible insecure-development warning in the app. Every other
cleartext origin MUST be rejected with `relay_origin_insecure`.

**R-22-084** Android's declarative `<domain-config>` element matches an exact hostname or IP
literal only; it has no CIDR/subnet syntax, so R-22-039's IP-range allow list cannot be expressed
as a set of `<domain>` entries. The app MUST ship
`app/android/app/src/main/res/xml/network_security_config.xml` with a `base-config` that sets
`cleartextTrafficPermitted="true"`, wired through `android:networkSecurityConfig` on the
`<application>` element. This grants the OS-level permission the connection needs; R-22-039's
Dart-level allow list stays the real security gate, since it rejects every origin outside the
allow list before a socket ever opens.
Source: Android Developer Documentation, "Network security configuration":
`https://developer.android.com/privacy-and-security/security-config`.

**R-22-085** The app MUST declare `NSAppTransportSecurity` in `Info.plist` with
`NSAllowsLocalNetworking` set to `true` and an `NSExceptionDomains` entry, each with
`NSExceptionAllowsInsecureHTTPLoads` set to `true`, for every member of R-22-039's allow list:
`localhost`, `127.0.0.0/8`, `::1`, `10.0.0.0/8`, `172.16.0.0/12`, and `192.168.0.0/16`. From iOS
17, ATS no longer allows a connection to an IP address by default and requires each address or
CIDR range listed individually. The app MUST NOT set `NSAllowsArbitraryLoads`: it disables ATS for
every domain, which is broader than this local-only need.
Source: Apple Developer Documentation, "NSAllowsLocalNetworking" and "NSExceptionDomains":
`https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking`
and
`https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsexceptiondomains`.

### 7.4 No Compiled Default

**R-22-040** The app MUST NOT ship a compiled default relay origin. First run has no relay. Pairing
supplies the first origin. There is no `relay.herdr.nvidia.com` default and no built-in relay of any
kind.

### 7.5 Destructive Confirmation

**R-22-041** Settings MAY replace the relay origin only after an explicit destructive confirmation.
Replacing the origin closes the current connection, clears every stored routing handle and every
pinned Host key, and requires pairing against the new relay. The app MUST show a confirmation dialog
that states these consequences before applying the change.

**R-22-042** The relay origin settings screen MUST be reachable from `/settings`. The screen MUST
display the current origin, an edit action with the destructive confirmation in R-22-041, and the
persistent insecure-development warning if the origin is on the local-development allow list.

---

## 8. Store and Privacy Compliance

### 8.1 iOS Privacy Manifest

**R-22-043** The app MUST include a `PrivacyInfo.xcprivacy` file with:

- `NSPrivacyTracking`: `false` (the app does not track users).
- `NSPrivacyTrackingDomains`: empty array.
- `NSPrivacyCollectedDataTypes`: declare `NSCameraUsageDescription` (for QR scanning). No other data
  types are collected by the app.
- Required reason API declarations: none of the required-reason APIs (file timestamps, system boot
  time, disk space, UserDefaults, active keyboard) are used by this app. If a dependency uses one, its
  privacy manifest covers it.

### 8.2 Android Data Safety Form

**R-22-044** The Google Play Data Safety form MUST disclose the push-token use.
Amended 2026-09-16 under R-03-136: the app shares its push token with the relay operator and
Apple or Google for fixed-text wake alerts, without agent or terminal content.

- **Data collected and shared:** The push token for wake delivery. The pairing key stays in
  Keystore. The relay cannot read terminal content.
- **Encryption in transit:** Yes. The relay connection uses TLS, and Noise encrypts terminal
  content end to end.
- **Data retention:** The relay holds the token in memory until unregister, eviction, or restart.

### 8.3 Encryption Export Compliance

**R-22-045** Both the App Store and Google Play Store require an encryption export declaration because
the app uses cryptography (TLS, ECDH for pairing, Keystore operations).

- **App Store:** Answer "Yes" to the export compliance question. Select the exemption: the app uses
  encryption provided by the operating system (iOS Security framework, CryptoKit) and is not designed
  for military or government end-users. Provide the standard self-classification report if requested.
- **Google Play:** Answer "Yes" to the export compliance question. Select the exemption for apps that
  use standard OS-provided cryptography for authentication and secure communication.

### 8.4 Complete Permission List

| Platform | Permission | Justification |
|----------|-----------|---------------|
| iOS | `NSFaceIDUsageDescription` | Biometric unlock to access terminal sessions |
| iOS | `NSCameraUsageDescription` | Scan pairing QR code |
| Android | `android.permission.USE_BIOMETRIC` | Biometric unlock (normal permission) |
| Android | `android.permission.CAMERA` | Scan pairing QR code (dangerous, runtime) |
| Android | `android.permission.INTERNET` | WebSocket to relay (normal) |
| Android | `android.permission.ACCESS_NETWORK_STATE` | Detect connectivity changes (normal) |
| Android | `android.permission.POST_NOTIFICATIONS` | Show agent-status local notifications (dangerous, runtime) |
| Android | `android.permission.FOREGROUND_SERVICE` | Optional: hold WebSocket in background (normal) |
| Android | `android.permission.FOREGROUND_SERVICE_DATA_SYNC` | Foreground service type declaration (Android 14+) |

---

## 9. Master Package Table

| Capability | iOS Native API | Android Native API | Flutter |
|-----------|---------------|-------------------|---------|
| Secret storage | Keychain (`SecItemAdd`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, `SecAccessControl` with `.biometryCurrentSet`) | Keystore (`KeyGenParameterSpec`, `setUserAuthenticationRequired`) | `flutter_secure_storage` 10.3.1 (BSD-3-Clause) |
| Biometric unlock | `LocalAuthentication` + `SecAccessControl` | `BiometricPrompt` (AndroidX biometric 1.2.0-alpha05) | `local_auth` 3.0.2 (BSD-3-Clause) |
| Local notifications | `UserNotifications` | `NotificationManager` | `flutter_local_notifications` 22.3.0 (BSD-3-Clause) |
| Connectivity | `NWPathMonitor` (Network framework) | `ConnectivityManager` | `connectivity_plus` 7.3.1 (BSD-3-Clause) |
| QR scanning | `AVFoundation` + Vision | CameraX + ML Kit | `mobile_scanner` 7.4.0 (BSD-3-Clause) |
| Noise crypto | CryptoKit (via `cryptography_flutter`) | `javax.crypto` (via `cryptography_flutter`) | `cryptography` 2.9.0 (Apache-2.0) + `cryptography_flutter` 2.3.4 (Apache-2.0) |

---

## 10. Implementation TODO

### Secret Storage

- [ ] Implement iOS Keychain wrapper with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and
  `SecAccessControl` with `.biometryCurrentSet`
- [ ] Implement Android Keystore wrapper with `setUserAuthenticationRequired(true)` and 120-second validity
- [ ] Generate Curve25519 key pair on first launch using `X25519()` from the `cryptography` package
  (both platforms)
- [ ] Handle `KeyPermanentlyInvalidatedException` (Android) and `errSecAuthFailed` (iOS) with
  re-pair prompt
- [ ] Set `android:allowBackup="false"` in the manifest
- [ ] Test key survival across app uninstall and reinstall (expected: keys lost, re-pair required)

### Biometric Unlock

- [ ] Generate biometric-gated Keystore or Keychain key (not app-level boolean)
- [ ] Add `NSFaceIDUsageDescription` to `Info.plist`
- [ ] Add `USE_BIOMETRIC` permission to `AndroidManifest.xml`
- [ ] Implement re-auth on cold start
- [ ] Implement re-auth after 120-second background timeout
- [ ] Implement re-auth before destructive actions
- [ ] Implement passcode fallback when biometrics unavailable

### Local Notifications

- [ ] Create Android notification channel `herdr_agent_status` on first launch
- [ ] Request `POST_NOTIFICATIONS` at the `R-30-509` moment (R-22-021, R-22-071, R-30-509)
- [ ] Request iOS notification authorization at the `R-30-509` moment (R-22-021, R-22-071, R-30-509)
- [ ] Read notification authorisation state on every resume (R-22-072)
- [ ] Open OS notification settings from `/settings/notifications` (R-22-073)
- [ ] Post local notification from `agent_status` payload fields
- [ ] Route notification tap to `/hosts/:hostId/panes/:paneId`
- [ ] On relaunch: reconnect, send `tree_request` (R-11-043), show unseen attention in-app

### Deep Links

- [ ] Add `CFBundleURLTypes` with `herdr-remote` scheme to `Info.plist`
- [ ] Handle pairing URL in `scene(_:willConnectTo:options:)` and `scene(_:openURLContexts:)`
- [ ] Add `intent-filter` with `herdr-remote` scheme to the launcher activity in `AndroidManifest.xml`
- [ ] Set `android:launchMode="singleTask"` and handle `onNewIntent()`
- [ ] Parse and validate the pairing URI against `docs/11-relay-protocol.md` R-11-140

### Relay Origin Storage

- [ ] Store origin in canonical form: scheme, host, optional port
- [ ] Convert `https://` to `wss://` and `http://` to `ws://` for the local allow list
- [ ] Reject cleartext origins outside the local-development allow list with `relay_origin_insecure`
- [ ] Show persistent insecure-development warning for local `http://` origins
- [ ] Implement destructive confirmation dialog for origin change

### Background and Reconnect

- [ ] Implement WebSocket lifecycle: clean close on background, reconnect on foreground
- [ ] Implement connectivity monitoring with 1-second debounce
- [ ] Implement reconnect backoff (0.5 s, 1 s, 2 s, 5 s, 10 s, 30 s cap)
- [ ] Resynchronise state on reconnect (send `tree_request`, R-11-043)
- [ ] Test network transition: WiFi to cellular to WiFi

### QR Code Scanning

- [ ] Add `NSCameraUsageDescription` to `Info.plist`
- [ ] Add `CAMERA` permission to `AndroidManifest.xml` with runtime request
- [ ] Implement QR scanner view (camera and detection overlay)
- [ ] Implement manual six-word phrase entry fallback with relay origin field
- [ ] Release camera when scanner dismissed (Android 14+ while-in-use)

### Store and Privacy Compliance

- [ ] Create `PrivacyInfo.xcprivacy` with `NSPrivacyTracking: false`
- [ ] Complete Google Play Data Safety form (no data collected)
- [ ] Complete App Store encryption export declaration
- [ ] Complete Google Play encryption export declaration
- [ ] Add all permissions from section 8.4 with justification strings

## 11. Operating-System Theming

### 11.1 Platform signal

**R-22-050**: The app MUST read the operating-system brightness through
`MediaQuery.platformBrightnessOf(context)`. This function returns the `Brightness` from the nearest
`MediaQuery` ancestor and causes the given `context` to rebuild only when
`MediaQueryData.platformBrightness` changes, not when any other `MediaQuery` attribute changes.
Source: https://api.flutter.dev/flutter/widgets/MediaQuery/platformBrightnessOf.html

**R-22-051**: The root `MaterialApp` MUST use `themeMode: ThemeMode.system` as the default. This
selects `theme` for light and `darkTheme` for dark based on the operating-system setting. When the
person selects `Light` or `Dark` in settings, the app switches to `ThemeMode.light` or
`ThemeMode.dark`. Source: https://api.flutter.dev/flutter/material/ThemeMode.html

### 11.2 Persisted preference

**R-22-052**: The persisted preference MUST store the **mode** (`System`, `Light`, `Dark`), never a
resolved brightness value. The package that stores it is `shared_preferences` 2.5.5, per
`docs/20-mobile-framework.md` table in section 6. The key MUST be `theme_mode`. The default value
when no persisted preference exists is `System`.

### 11.3 Must-not consequences

**R-22-053**: A theme change MUST NOT drop the relay connection. It MUST NOT re-fetch a pane frame
except as required by `docs/21-terminal-rendering.md` for the terminal palette switch. It MUST NOT
clear the biometric unlock state. The app listens for platform-brightness changes through
`MediaQuery.platformBrightnessOf(context)` and updates the `MaterialApp` `themeMode` and the terminal
palette without restarting the widget tree.

### 11.4 Status bar and navigation bar

**R-22-054**: The status-bar and navigation-bar appearance MUST follow the resolved theme. The app
MUST use `SystemUiOverlayStyle`:

- On a light resolved theme: light background with dark status-bar icons
  (`SystemUiOverlayStyle.light`).
- On a dark resolved theme: dark background with light status-bar icons
  (`SystemUiOverlayStyle.dark`).
The app MUST update the overlay style on every theme change without restarting the widget tree.
Source: https://api.flutter.dev/flutter/services/SystemUiOverlayStyle-class.html

### 11.5 Platform behaviour

**R-22-055**: On iOS, the operating system delivers a `traitCollectionDidChange` callback when the
user toggles Light or Dark in Control Center or when the scheduled Night Shift transition fires.
Flutter propagates this through `MediaQueryData.platformBrightness`. No `Info.plist` key is required
for dark-mode support because `UIUserInterfaceStyle` is automatic since iOS 13.
Source: https://developer.apple.com/documentation/uikit/uitraitcollection

**R-22-056**: On Android, the operating system delivers a `Configuration.uiMode` change through the
`onConfigurationChanged` callback when the user toggles Dark theme in Settings or when Battery Saver
activates. Flutter propagates this through `MediaQueryData.platformBrightness`. The app MUST NOT set
`android:configChanges="uiMode"` in its activity declaration, because that would tell Android the app
handles the change itself and would prevent Flutter from receiving the update
[unverified — confirm first with
https://developer.android.com/guide/topics/resources/runtime-changes#HandlingTheChange].
Source: https://developer.android.com/guide/topics/ui/look-and-feel/darktheme

---

## 12. Platform Chrome Detection and Insets

This section owns the run-time detection rules for platform-native chrome:
dynamic colour on Android, flat Cupertino chrome on iOS, edge-to-edge insets,
and accessibility transparency and contrast settings. `docs/33-platform-chrome.md`
owns the component shapes; this section owns the platform calls.

### 12.1 Android fixed Herdr palette

**R-22-075** The app MUST use the fixed Herdr chrome palette on Android via
`ChromeScheme.fixed(Brightness)`. The `dynamic_color` package is removed; there is no
wallpaper-derived scheme. `DynamicColorBuilder`, `DynamicColorPlugin`, the degenerate
scheme, `proveAndroidChromeScheme`, and `ChromeSchemeSource.wallpaper`/`degenerate` are
deleted. The Android dynamic-colour gate is retired; the fixed palette is the only source.

### 12.2 iOS chrome is flat Cupertino

**R-22-076** *(Retired. The app ships no glass on iOS in version 1. iOS chrome is the plain
`cupertino_ui` appearance, owned by `docs/33-platform-chrome.md` R-33-012. No version check,
capability check, or string parse is needed. The migration to official Liquid Glass is tracked
by `docs/33-platform-chrome.md` R-33-069, which cites Flutter issue 170310 and states no date.)*
Source: `https://github.com/flutter/flutter/issues/170310`.

### 12.3 Edge-to-edge and window insets

**R-22-077** The repository pins `targetSdk 36` per `docs/20` R-20-026, so edge-to-edge is enforced.
The app MUST handle edge-to-edge on every device it supports. A floating bottom control MUST NOT sit
under the system navigation bar. The app MUST read the bottom inset through
`MediaQuery.viewPaddingOf(context)` or `MediaQuery.paddingOf(context)` and apply it as bottom margin
or padding to any floating control. `SafeArea` applies these insets automatically.
The edge-to-edge bottom inset for a floating control is owned by
`docs/33-platform-chrome.md` R-33-029; this rule owns the platform version
facts and the inset API.
Source:
`https://developer.android.com/develop/ui/views/layout/edge-to-edge`
and
`https://developer.android.com/about/versions/16/behavior-changes-16#edge-to-edge`.

### 12.4 Reduce Transparency and Increase Contrast

**R-22-078** The app MUST honour the iOS Reduce Transparency setting for any
translucent surface. iOS exposes it through
`UIAccessibility.isReduceTransparencyEnabled`, a `@MainActor` static property
available on iOS 8.0 and above. Flutter does NOT expose this flag in
`MediaQueryData` or `AccessibilityFeatures`; there is no MediaQuery read for it.
The app MUST read it through a platform channel that calls the native
`UIAccessibility.isReduceTransparencyEnabled` getter and MUST fall back to an
opaque surface when it is true. The design rule for honouring Reduce
Transparency is owned by `docs/33-platform-chrome.md` R-33-051; this rule owns
the platform call.

**R-22-079** The app MUST honour the iOS Increase Contrast setting. iOS exposes
it through `UIAccessibility.isDarkerSystemColorsEnabled`, a `@MainActor`
static property available on iOS 8.0 and above. Flutter maps this to
`MediaQueryData.highContrast`, which the app MUST read through
`MediaQuery.highContrastOf(context)`. The Flutter docs confirm that
`highContrast` corresponds to the iOS "Increase Contrast" setting and is
updated on iOS 13 and above. When it is true, the app MUST use the
high-contrast theme variants owned by `docs/32-design-language.md`. The design
rule for honouring Increase Contrast is owned by `docs/33-platform-chrome.md`
R-33-052; this rule owns the platform call and the Flutter MediaQuery read.

**R-22-080** On Android, `MediaQueryData.highContrast` maps to the
"High contrast text" accessibility setting. The Flutter docs confirm it is
updated on Android API 34 and above. The `minSdk 33` floor is below 34, so on
API 33 devices `highContrast` reads false, which is a graceful default
costing no code. The app MUST honour it the same way as iOS.
Android has no equivalent of Reduce Transparency. There is no Android setting
that reduces or disables translucent surfaces, so R-22-078 applies to iOS only.
Do not invent symmetry where none exists.
Source:
`https://developer.apple.com/documentation/uikit/uiaccessibility/isreducetransparencyenabled`,
`https://developer.apple.com/documentation/uikit/uiaccessibility/isdarkersystemcolorsenabled`,
and
`https://api.flutter.dev/flutter/widgets/MediaQueryData/highContrast.html`.

### 12.5 The platform view boundary

**R-22-081** *(Retired. The app ships no platform view on iOS in version 1.
iOS chrome is the plain `cupertino_ui` appearance drawn by Flutter, per
`docs/33-platform-chrome.md` R-33-012. There is no hybrid composition, no
gesture arbitration cost, no screenshot boundary, and no split accessibility
tree. The four tested costs below no longer apply. If a future version adopts
official Liquid Glass through a platform view, the costs return and this rule
is revived.)*

---

## Retired rules

| Rule | Status | Replaced by |
|---|---|---|
| R-22-076 | Retired. The app ships no glass on iOS in version 1. No version detection is needed. | `docs/33-platform-chrome.md` R-33-012 (flat Cupertino chrome), R-33-069 (migration trigger) |
| R-22-081 | Retired. The app ships no platform view on iOS in version 1. The four tested costs no longer apply. | `docs/33-platform-chrome.md` R-33-012 (flat Cupertino chrome drawn by Flutter) |

---

## Sources

- Apple supported iOS capabilities —
  <https://developer.apple.com/help/account/reference/supported-capabilities-ios> —
  Push Notifications requires Apple Developer Program or Enterprise Program membership.
- Apple task-switcher privacy guidance —
  <https://developer.apple.com/library/archive/qa/qa1838/_index.html> —
  UIKit captures the window at backgrounding; sensitive views must be covered without animation.
- Apple `kSecUseAuthenticationContext` —
  <https://developer.apple.com/documentation/security/ksecuseauthenticationcontext> —
  an authenticated context can serve subsequent Keychain operations without another prompt.
- Apple `LAContext.invalidate()` —
  <https://developer.apple.com/documentation/localauthentication/lacontext/invalidate()> —
  invalidation cancels pending authentication and prevents context reuse.
- Apple `LAContext.interactionNotAllowed` —
  <https://developer.apple.com/documentation/localauthentication/lacontext/interactionnotallowed> —
  subsequent reads can prohibit authentication UI.

- Apple Developer — `CFBundleURLTypes`: https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleurltypes
- Apple Developer — `CFBundleURLSchemes`: https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleurltypes/cfbundleurlschemes
- Apple Developer — `CFBundleTypeRole`: https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleurltypes/cfbundletyperole
- Apple Developer — Defining a custom URL scheme for your app: https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app
- Apple Developer — Keychain Services: https://developer.apple.com/documentation/security/keychain_services
- Apple Developer — `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`: https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly
- Apple Developer — `biometryCurrentSet`: https://developer.apple.com/documentation/security/secaccesscontrolcreateflags/biometrycurrentset
- Apple Developer — Accessing keychain items with Face ID or Touch ID: https://developer.apple.com/documentation/LocalAuthentication/accessing-keychain-items-with-face-id-or-touch-id
- Apple Developer — Restricting keychain item accessibility: https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility
- Apple Developer — LocalAuthentication: https://developer.apple.com/documentation/localauthentication
- Apple Developer — Background Execution: https://developer.apple.com/documentation/uikit/about-the-background-execution-sequence
- Apple Developer — Privacy Manifest: https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
- Apple Developer — Encryption Export: https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations
- Android Developers — Create deep links: https://developer.android.com/training/app-links/deep-linking
- Android Developers — `<data>` element: https://developer.android.com/guide/topics/manifest/data-element
- Android Developers — Keystore: https://developer.android.com/privacy-and-security/keystore
- Android Developers — `KeyGenParameterSpec`: https://developer.android.com/reference/android/security/keystore/KeyGenParameterSpec
- Android Developers — BiometricPrompt: https://developer.android.com/identity/sign-in/biometric-auth
- Android Developers — Permissions: https://developer.android.com/guide/topics/permissions/overview
- Android Developers — Backup Best Practices: https://developer.android.com/privacy-and-security/risks/backup-best-practices
- Google Play — Data Safety: https://support.google.com/googleplay/android-developer/answer/10787469
- Google Play — Export Compliance: https://support.google.com/googleplay/android-developer/answer/113770
- pub.dev — `flutter_secure_storage`: https://pub.dev/packages/flutter_secure_storage
- pub.dev — `local_auth`: https://pub.dev/packages/local_auth
- pub.dev — `flutter_local_notifications`: https://pub.dev/packages/flutter_local_notifications
- pub.dev — `connectivity_plus`: https://pub.dev/packages/connectivity_plus
- pub.dev — `mobile_scanner`: https://pub.dev/packages/mobile_scanner
- pub.dev — `cryptography`: https://pub.dev/packages/cryptography
- pub.dev — `cryptography_flutter`: https://pub.dev/packages/cryptography_flutter
- Flutter — `MediaQuery.platformBrightnessOf`: https://api.flutter.dev/flutter/widgets/MediaQuery/platformBrightnessOf.html
- Flutter — `ThemeMode`: https://api.flutter.dev/flutter/material/ThemeMode.html
- Flutter — `SystemUiOverlayStyle`: https://api.flutter.dev/flutter/services/SystemUiOverlayStyle-class.html
- Apple Developer — `UITraitCollection`: https://developer.apple.com/documentation/uikit/uitraitcollection
- Android Developers — Dark theme: https://developer.android.com/guide/topics/ui/look-and-feel/darktheme
- Android Developers — Notification runtime permission: https://developer.android.com/develop/ui/compose/notifications/notification-permission
- Android Developers — `POST_NOTIFICATIONS` permission: https://developer.android.com/reference/android/Manifest.permission#POST_NOTIFICATIONS
- Android Developers — `ACTION_APP_NOTIFICATION_SETTINGS`: https://developer.android.com/reference/android/provider/Settings#ACTION_APP_NOTIFICATION_SETTINGS
- Android Developers — `NotificationManagerCompat.areNotificationsEnabled()`: https://developer.android.com/reference/androidx/core/app/NotificationManagerCompat#areNotificationsEnabled()
- Apple Developer — Asking permission to use notifications: https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications
- Apple Developer — `UNUserNotificationCenter.getNotificationSettings`: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/getnotificationsettings(completionhandler:)
- Apple Developer — `UIApplication.openSettingsURLString`: https://developer.apple.com/documentation/uikit/uiapplication/opensettingsurlstring
- `docs/11-relay-protocol.md` — R-11-043 (`tree_request` and `tree_snapshot`), R-11-130 (`host_info`
  exchange).
- `docs/21-terminal-rendering.md` — terminal palette response to a theme change.
- `docs/32-design-language.md` — colour value owner for both themes.
- `dynamic_color` `DynamicColorBuilder` API: https://pub.dev/documentation/dynamic_color/latest/dynamic_color/DynamicColorBuilder-class.html
- Android edge-to-edge in views: https://developer.android.com/develop/ui/views/layout/edge-to-edge
- Android 16 behavior changes, edge-to-edge opt-out: https://developer.android.com/about/versions/16/behavior-changes-16#edge-to-edge
- Apple `UIAccessibility.isReduceTransparencyEnabled`: https://developer.apple.com/documentation/uikit/uiaccessibility/isreducetransparencyenabled
- Apple `UIAccessibility.isDarkerSystemColorsEnabled`: https://developer.apple.com/documentation/uikit/uiaccessibility/isdarkersystemcolorsenabled
- Flutter `MediaQueryData.highContrast`: https://api.flutter.dev/flutter/widgets/MediaQueryData/highContrast.html
- Flutter `SafeArea`: https://api.flutter.dev/flutter/widgets/SafeArea-class.html
- Launch-surface capture, 2026-09-11, Android 16 emulator (`sdk gphone64 x86 64`), debug build of
  this app, cold start from the launcher. Screenshots every 90 ms and every 160 ms across two runs,
  measured for pixels within 6 of `color.bg.grid` (`#202024`) and of `color.bg.base` (`#17171a`).
  The system splash frames read 94.7% `bg.base` and 0.05% grid ink; the frames after it read the
  same flat colour; grid ink first appeared at about 2 s, in Flutter's own first frame, at 4.0%.
  It proved that no Android launch surface before the first Flutter frame can carry the grid, and
  that `android:windowBackground` is never displayed on its own, which set the Android half of
  `R-22-087`. The same capture proved the splash icon draws with no circle once it is
  `@mipmap/ic_launcher_foreground`.

---

## Open Questions

1. **iOS Keychain `ThisDeviceOnly` migration behaviour.** Apple Developer Forums thread 802526
   reports that `ThisDeviceOnly` keys were preserved during direct device-to-device migration (Quick
   Start) but not during iCloud restore. This contradicts the documented behaviour. **Recommended
   default:** Assume `ThisDeviceOnly` keys are lost on any device change and require re-pairing
   (R-22-011). If testing shows they survive Quick Start, relax the rule.

2. **Android Keystore Curve25519 support.** KeyMint v2 adds Curve25519, and the
   `minSdk 33` floor guarantees KeyMint v2 on every device, but device coverage is
   not universal because Secure Elements do not currently implement curve 25519.
   **Recommended default, and the rule in force:** generate the Curve25519
   keypair in software using `X25519()` from the `cryptography` package and
   store the private key bytes as Keystore data with biometric gating. A future
   hardware-backed Curve25519 upgrade is a future ADR task, not an open choice.

3. **Android biometric key validity window under the pinned wrapper.** The pinned
   `flutter_secure_storage` 10.3.1 wrapper sets the Android biometric key's authentication validity
   to 0 seconds (`setUserAuthenticationParameters(0, ...)` in `KeyCipherImplementationAES23.java`),
   not R-22-007's and R-22-017's 120-second value, and exposes no option to change it.
   **Recommended default, and the rule in force:** R-22-007 and R-22-017 keep the 120-second target
   unchanged; the gate stays app-level re-authentication timing until proven otherwise. If the
   wrapper's zero-second window proves unworkable, `WP-13-b` MAY set
   `setUserAuthenticationParameters` on the key directly, through a platform channel from
   `app/android/app/src/main/kotlin/.../MainActivity.kt`, which it owns.
