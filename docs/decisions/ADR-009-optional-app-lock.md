# ADR-009: App Lock is an optional setting, not a precondition for pairing

## Status

Accepted

## Context

`docs/13-security-pairing.md` R-13-043 required the Device to store its Curve25519 identity
private key behind an operating-system biometric or passcode challenge from the moment of key
generation: Android Keystore `setUserAuthenticationRequired(true)` or an iOS `SecAccessControl`
with `.biometryCurrentSet`, per `docs/22-platform-integration.md` R-22-013.
`app/lib/screens/welcome_screen.dart` enforced the same precondition at the door: it called
`local_auth.isDeviceSupported()` before pairing could start, and disabled the whole `Scan QR
code` action, with an error message, on any phone that reported no PIN, pattern, password or
biometric enrolled. A phone with no screen lock could not pair at all.

`docs/22-platform-integration.md` R-22-013 gives the reason the biometric-gated Keystore or
Keychain read exists in the first place: an app-level boolean (`if (biometricPrompt.show() ==
OK) { unlock() }`) is bypassable with a debugger, a tweak or a repackaged binary, so the private
key must be cryptographically unavailable without a real biometric or passcode match, the same
pattern banking apps and password managers use. That reasoning stands. It is not the part this
ADR reverses.

The product owner reversed a different decision: whether that gate, and the screen-lock
precondition it forced onto pairing, should be mandatory at all. A person who has never set a
screen lock on their phone, and does not want one, should still be able to pair and use this
product. A locked-behind-a-passcode terminal is a feature some people want and others find in
their way. It should not be the price of entry.

## Decision

App Lock becomes a named, optional, off-by-default setting, never a pairing precondition.

- Pairing, first launch and every other app action work fully with App Lock off, on a phone with
  no screen lock of any kind. `docs/13-security-pairing.md` R-13-043 no longer ties Curve25519
  key generation to a screen-lock check, and `docs/31-mockups/01-welcome.md` no longer disables
  `Scan QR code` for one.
- The Device's identity key, the pinned per-computer Host secrets, and the relay origin keep
  living in the platform Keystore or Keychain either way, still sandboxed app storage, still
  never plaintext, still never `plain_store.dart`. The App Lock setting changes only whether that
  storage additionally demands a fresh operating-system biometric or passcode challenge to read
  it, per `docs/13-security-pairing.md` R-13-073.
- **App Lock on** keeps today's exact mechanism. `docs/22-platform-integration.md` R-22-013
  still gates the read on the operating system, never an app-level boolean, for the reason given
  in `## Context` above. `/lock` (`docs/31-mockups/04-lock.md`) and the 120-second background
  timeout of R-22-017 still apply, unchanged, whenever App Lock is on.
- **App Lock off** stores the identical values with no authentication requirement:
  `AndroidOptions()` with no biometric parameter, or an iOS `SecAccessControl` that keeps only
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and omits `.biometryCurrentSet` and
  `.devicePasscode`, per `docs/22-platform-integration.md` R-22-082. `/lock` never appears.
- The app offers to turn App Lock on exactly once, as a bottom sheet on the first arrival at
  `/hosts/:hostId/agents` after the first successful pair, alongside the existing notification
  permission ask of R-30-509 and just as non-gating, per `docs/30-ux-spec.md` R-30-521 and
  R-30-522. A person can turn it on or off at any later time from Settings, per
  `docs/31-mockups/15-appearance.md` R-31-15-18. Toggling it re-stores the same secrets under the
  new protection level; it never generates a new key and never forces re-pairing.

## Consequences

- A phone with App Lock off, if lost or stolen while unlocked, exposes the app to anyone holding
  it: the terminal sessions, the paired-computer list and every action a paired phone can take,
  with no second challenge beyond whatever the phone's own lock screen already asked at wake.
  This is a real, deliberate trade-off. The product owner chose it explicitly: a person who
  declines a screen lock, or declines App Lock, accepts that their unlocked phone is the whole
  boundary. Revoking the Device from the Host, per `docs/13-security-pairing.md` R-13-053,
  remains the recovery for a stolen phone, on or off.
- A phone with App Lock on keeps every property it had before this decision: the private key is
  cryptographically unavailable without a real biometric or passcode match, exactly as
  `docs/22-platform-integration.md` R-22-013 requires. Nothing about the on-state's rigor
  changes.
- `docs/13-security-pairing.md`, `docs/22-platform-integration.md`,
  `docs/03-product-decisions.md`, `docs/30-ux-spec.md`, `docs/31-mockups/01-welcome.md`,
  `docs/31-mockups/04-lock.md` and `docs/31-mockups/15-appearance.md` all gain or change rules to
  state this precisely; each is updated in the same change as this ADR.
- A later implementation phase must build the App Lock switch, the one-time prompt, and the
  conditional storage-mode toggle described above. None of it exists in code yet.
