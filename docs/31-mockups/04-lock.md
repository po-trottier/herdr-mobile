# 04 - Biometric lock screen

| Field | Value |
| --- | --- |
| Route | `/lock` |
| Surface | Device, Android and iOS |
| Spec | `docs/30-ux-spec.md` |

## Variants

One screen, three appearances. The glyph and the primary label come from the biometric type the
operating system reports at run time, never from the platform, per `R-32-407`. An iPhone SE reports
a fingerprint and an Android phone with face unlock reports a face, so a platform-keyed screen is
wrong on both.

| Reported type | Glyph | iOS label | Android label |
| --- | --- | --- | --- |
| `face` | `face` | `Unlock with Face ID` | `Unlock with face unlock` |
| `fingerprint` | `fingerprint` | `Unlock with Touch ID` | `Unlock with your fingerprint` |
| `iris` | `visibility` | not reachable | `Unlock with iris` |
| `strong` or `weak` only | `lock` | `Unlock with biometrics` | `Unlock with biometrics` |

## Wireframe A, a reported face

iOS with Face ID. The system runs the check as an overlay, so our screen stays visible behind it.

```text
+--------------------------------------+
| [GROUND GRID]                  [RAM] |
|--------------------------------------|
| -- LOCKED                            |
|             Herdr Remote             |
|                                      |
|            +-----------+             |
|            |  (o)      |             |
|            |   face    |             |
|            +-----------+             |
|                                      |
|          Unlock to continue          |
|                                      |
| Your keys stay in this phone's       |
| keystore, behind this check.         |
|                                      |
|                                      |
| +----------------------------------+ |
| |       Unlock with Face ID        | |
| +----------------------------------+ |
|                                      |
|         Use device passcode          |
|                                      |
+--------------------------------------+
```

## Wireframe B, a reported fingerprint

Android with a fingerprint sensor. `BiometricPrompt` is a **system-drawn sheet** that rises over our
screen and owns the whole interaction. The dashed block below is the operating system's, not ours: we
choose none of its type, colour, shape or copy, and we MUST NOT imitate it elsewhere. The same
wireframe serves an iPhone with Touch ID, with the label from the table above.

```text
+--------------------------------------+
| [GROUND GRID]                  [RAM] |
|--------------------------------------|
| -- LOCKED         Herdr Remote       |
|            +-----------+             |
|            |    (@)    |             |
|            | fingerprnt|             |
|            +-----------+             |
|                                      |
|          Unlock to continue          |
|                                      |
| Your keys stay in this phone's       |
| keystore, behind this check.         |
|                                      |
|+ - - - - - - - - - - - - - - - - - -+|
|' system sheet, drawn by Android     '|
|'                                    '|
|'          Herdr Remote              '|
|'      Unlock to continue            '|
|'                                    '|
|'             (@)                    '|
|'      Touch the sensor              '|
|'                                    '|
|'                 Use passcode       '|
|+ - - - - - - - - - - - - - - - - - -+|
+--------------------------------------+
```

## Callouts

1. The ground grid uses `R-32-332`. The `BrandMark` uses `color.fg.disabled` and a 96 px height.
   Its right edge is flush with the screen edge. Its bottom crop touches the top boundary rule.
   See `R-32-580`.
2. The `LOCKED` eyebrow uses `R-32-590`. The centred product name uses `type.title`.
3. The biometric glyph uses `size.icon.hero` and `color.accent.primary`. Its icon comes from the
   reported biometric type, per `R-32-401` and `R-32-407`.
4. The prompt uses `type.body` and `color.fg.primary`. An error prompt takes `treat.error` and,
   when it wraps, centres its lines: `/lock` is the one screen `R-30-293` lets centre (amended
   2026-09-08 by the product owner: a wrapped error prompt sat start-aligned under a centred
   glyph).
5. The reassurance uses `type.caption` and `color.fg.secondary`. It keeps the exact storage claim.
6. The shared primary and text buttons are the platform's own label style of `R-32-212`, as
   written (amended 2026-09-09 by the product owner, per `R-03-104`: until then `type.mono.button`
   with widget-applied upper case). Their labels still come from the reported biometric type. The
   body sits at the screen edge inset of `R-30-230` on every side, and the two actions sit
   `space.2` apart, the gap every filled-then-text stack in the app uses (amended 2026-09-08 by
   the product owner: this screen alone used `space.6` at the sides and `space.8` at the foot).
7. The `Use device passcode` action stays present. A biometric enrolment can fail or be absent.
8. Android draws the system sheet in wireframe B. The app supplies only its title and subtitle.
   Nothing behind the sheet is interactive while the sheet is open.

## States

| State | Trigger | Screen shows |
| --- | --- | --- |
| Default | App Lock is enabled, and the app resumes after the lock timeout, cold starts with one or more saved Hosts, per `R-03-043`, or a notification tap arrives. | The wireframe above, with the platform biometric sheet already raised. |
| Loading | The platform sheet is open. | The primary action is disabled. No spinner, because the platform sheet owns the feedback. |
| Empty | Not applicable. | - |
| Error, rejected | The biometric check failed. | The prompt takes `treat.error` and reads `Not recognised. Try again.` Haptic `haptic.error`. The primary action returns. |
| Error, locked out | The platform locked biometrics after repeated failures, on the counts `R-22-014` records. | The primary action is hidden. `Use device passcode` becomes primary, which is the fallback `R-22-014` requires. The prompt reads `Biometrics are locked. Use your passcode.` |
| Error, no enrolment | The phone has no biometric enrolled, which `R-22-014` treats the same way as a lockout. | The primary action is hidden and `Use device passcode` is primary. The prompt reads `No biometrics on this phone. Use your passcode.` |
| Offline | The phone has no network. | No change, because the unlock is local. A strip at the foot reads `No network. The app connects after you unlock.` in `color.fg.secondary`. |

## Navigation

- In: app resume after the lock timeout, cold start with one or more saved Hosts, per `R-03-043`,
  or a local notification tap, per `R-31-04-04` — and, in every case, only while App Lock is
  enabled, per `docs/03-product-decisions.md` R-03-090. The test is saved, never connected: a
  cold start with three saved computers and none connected still comes here first, if App Lock is
  on. When App Lock is off, none of these triggers route here; each goes straight to its target,
  per R-31-04-12.
- Out, success: the route that was open when the app locked, or the held notification route. If
  neither, `/hosts`, mockup `05-host-list.md`, which owns what a cold start connects. This screen
  MUST NOT choose a per-Host route of its own, because `R-30-946` permits one only for the connected
  computer and a cold start has connected nothing.
- Out, refusal: the screen stays. There is no way past it and no back target.

## Rules

- **R-31-04-01** The app MUST lock on the triggers `R-22-017` fixes, and MUST lock at once when the
  process is killed. `docs/22-platform-integration.md` owns the background timeout, and this screen
  MUST NOT restate the number.
- **R-31-04-02** The app MUST NOT paint pane content, an agent name, or a Host name behind this
  screen, and MUST set `FLAG_SECURE` on Android while locked, so the task switcher snapshot stays
  blank.
- **R-31-04-03** The passcode fallback MUST stay reachable, which is the fallback `R-22-014`
  requires. The app MUST NOT gate access on biometrics alone.
- **R-31-04-04** A local notification tap MUST route through `/lock` and MUST keep the target route,
  so the unlock lands on the pane the notification named. This is the `app is locked` degenerate
  case of `R-30-511`.
- **R-31-04-05** This screen MUST NOT show the relay address, a routing handle, a pairing phrase, or
  a key fingerprint. A locked phone shows nothing that identifies what it can reach.
- **R-31-04-06** The glyph is `lock` in every state, per `R-32-407` (amended 2026-09-16). The
  primary label MUST come from the biometric type that `getAvailableBiometrics()` reports, and
  MUST NOT be selected by `Platform.isIOS` or `Platform.isAndroid`. A platform-keyed label says
  `Face ID` to an iPhone SE user, who has Touch ID, and `fingerprint` to an Android user whose
  phone unlocks by face.
  The reported type alone selects the row: the glyph, and which pair of pre-written label strings
  applies. The platform then selects only which of that row's iOS or Android column to show — never
  a different row.
- **R-31-04-07** When the platform reports only the `strong` or `weak` classification and no specific
  type, the screen MUST use the `lock` glyph and the label `Unlock with biometrics`. The app MUST NOT
  guess a sensor from the manufacturer, the model or the API level.
- **R-31-04-08** No copy on this screen may state **where** a sensor is. `local_auth` reports the
  biometric type and not the sensor position, so `Touch the sensor on the back` is a guess that is
  wrong on any phone with an under-display or side-mounted reader. The system sheet says whatever the
  operating system decides, and that is the only place a sensor is described.
- **R-31-04-09** On Android the check runs inside the system `BiometricPrompt` sheet. The app MUST
  supply only the title and the subtitle it displays, MUST NOT draw a look-alike sheet, and MUST NOT
  place any interactive control where the sheet appears. On iOS with Face ID the check is a system
  overlay with no sheet, which is why the two wireframes differ.
- **R-31-04-10** The unlock MUST NOT change which computer is connected. This screen MUST NOT
  connect, disconnect or switch anything while it is presented, and MUST hand the held route back
  unchanged when the check passes. `R-30-511` then owns the case where the held route names a
  computer that is not the connected one, and `R-30-946` forbids drawing a per-Host screen for a
  computer that is not connected. That case is narrow: `R-03-045` means an alert can only come from
  the connected computer, so it needs the connection to have dropped between the event and the tap,
  or a cold start that has connected nothing yet.
- **R-31-04-11** `/lock` has exactly the entry conditions in `## Navigation` and no others. The
  re-authentication that `R-22-017` requires before a destructive action MUST raise the platform
  sheet in place, on the screen that holds the action, and MUST NOT present `/lock`. Presenting
  `/lock` would throw away the route the person is working in, to confirm one action inside it.
- **R-31-04-12** `/lock` and every wireframe on this screen are reachable only while App Lock is
  enabled, per `docs/03-product-decisions.md` R-03-090 and
  `docs/decisions/ADR-009-optional-app-lock.md`. When App Lock is off, cold start, foreground
  resume and a notification tap all route straight to their target with no biometric or passcode
  challenge, per `R-30-030` and `R-30-511`, and this screen never appears. Turning App Lock on or
  off does not change the Device key, the pinned Host keys or any pairing, per
  `docs/13-security-pairing.md` R-13-073; it changes only whether this screen ever stands between
  a cold start and the agent list.
- **R-31-04-13** On a phone, the unlock screen MUST request upright portrait orientation before
  it starts authentication and retain that restriction while it is present. Leaving the screen
  MUST restore the operating system's default orientations, so pairing and terminal screens
  can rotate (decided 2026-09-17 by the product owner). During rotation, and on displays where
  the operating system does not honour the request, the lock content MUST scroll when needed
  to keep the prompt and passcode action reachable. A rotation MUST NOT start another check.
  On iPhone-sized iOS displays (shorter physical edge below 600 logical pixels), authentication
  MUST wait for a portrait layout and its rendered frame. iPad and Android multi-window mode
  MUST remain usable when the platform ignores orientation locking.

## Accessibility

- Touch target: both actions are full width and meet the minimum target of `R-30-290` and
  `R-30-740`.
- Contrast: `color.fg.primary` and `color.fg.secondary` on `color.bg.base` are passing rows in
  `R-32-150`, per `R-30-720`. The biometric glyph is a non text indicator in `color.accent.primary`,
  whose row on `color.bg.base` clears the 3.0 to 1 floor.
- Screen reader: the glyph MUST carry the label `Locked`, per `R-30-717`. The prompt line MUST be a
  semantic node that the screen reader reads when this screen takes the focus. The app MUST NOT
  announce it: `R-30-742` prefers a changed node, permits a one-shot announcement in four cases
  only, and an unlock prompt is not one of them. The app MUST NOT make the prompt a live region
  either, because the platform sheet already speaks. The label MUST name the reported biometric
  type, so a screen-reader user hears `Unlock with your fingerprint` and not a platform guess.
- Focus order: per `R-30-719`, product name, prompt, reassurance line, primary action, then `Use
  device passcode`. The platform biometric sheet traps the focus while it is open, and the focus
  returns to the primary action when it closes.

## Open questions

None.

## Sources

- Flutter `SystemChrome.setPreferredOrientations`: an empty list restores the system default;
  iPad multitasking can prevent orientation locking.
  <https://api.flutter.dev/flutter/services/SystemChrome/setPreferredOrientations.html>
- Android multi-window mode ignores orientation requests; authentication must remain available.
  <https://developer.android.com/develop/ui/views/layout/support-multi-window-mode#disabled_features_in_multi-window_mode>
- `docs/32-design-language.md` - the type tokens `R-32-202`, the product name rule `R-32-205`, the
  hero icon size `R-32-402`, the icon map `R-32-401`, the type-driven glyph rule `R-32-407`, and the
  contrast table `R-32-150`.
- `docs/30-ux-spec.md` - the centring exception `R-30-293`, the notification tap route `R-30-511`,
  and the per-Host route rule `R-30-946`.
- `docs/22-platform-integration.md` - the keystore, the keychain, the biometric prompt, the
  biometric type detection in `R-22-069` and `R-22-070`, the passcode fallback `R-22-014`, and the
  re-authentication triggers and background lock timeout in `R-22-017`.
- `docs/03-product-decisions.md` - the saved-computer policy `R-03-043`, the connected-computer
  alert limit `R-03-045`, and the optional App Lock policy `R-03-090`.
- `docs/13-security-pairing.md` - what the Device key is and how the operating system protects
  it.
- `docs/decisions/ADR-009-optional-app-lock.md` - why App Lock, and so this screen, is optional.
- `local_auth` `BiometricType`, which states that some platforms report a specific biometric type
  while others report only the `strong` or `weak` classification:
  `https://pub.dev/documentation/local_auth/latest/local_auth/BiometricType.html`.
