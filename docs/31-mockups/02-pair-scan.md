# 02 - Pair a Host by QR scan

| Field | Value |
| --- | --- |
| Route | `/pair/scan` |
| Surface | Device, Android and iOS |
| Spec | `docs/30-ux-spec.md` |

## Wireframe

```text
+--------------------------------------+
| <  Pair a computer     [flash off] (i)|
+--------------------------------------+
|                                      |
|   +--+                      +--+     |
|   |                            |     |
|                                      |
|                                      |
|          [ camera preview ]          |
|                                      |
|                                      |
|   |                            |     |
|   +--+                      +--+     |
|                              [ 1x ]  |
+--------------------------------------+
| -- PAIRING                           |
| Point the camera at the QR code in   |
| the Relay pane on your computer.     |
|              Type it in              |
+--------------------------------------+
```

## Wireframe, the bottom bar while a computer is connected

```text
+--------------------------------------+
| -- PAIRING                           |
| Point the camera at the QR code in   |
| the Relay pane on your computer.     |
| Pairing disconnects the computer you |
| are using now.                       |
|              Type it in              |
+--------------------------------------+
```

## Wireframe, Connecting

```text
+--------------------------------------+
|        [ camera preview ]            |
|                              [ 1x ]  |
+--------------------------------------+
| -- CONNECTING                        |
| Connecting to 172.16.188.73:8080...    |
| [ platform activity indicator ]      |
|               Cancel                 |
+--------------------------------------+
```

## Wireframe, the help sheet

```text
+--------------------------------------+
|             ------                   |
| How to pair a computer               |
|                                      |
| 1  Open Herdr on your computer.      |
| 2  Open the Relay pane.              |
| 3  Scan the QR code it shows.        |
|                                      |
|                Close                 |
+--------------------------------------+
```

## Callouts

1. The back chevron uses the app bar leading control of `R-32-510`.
2. The title `Pair a computer` uses `type.heading`.
3. The app bar has two trailing icon actions: the flash toggle and the help action.
4. The viewfinder uses four square corner marks in `color.accent.primary`, each one joined
   stroke at `border.frame`, so the outer corner is closed, not two caps with a notch. The
   ground grid from `R-32-332` stays behind the non-terminal screen body (amended 2026-09-08 by
   the product owner: the marks were drawn at 2 px, as two lines, against the 3 px of the width
   table beside `R-32-330`).
5. The camera preview fills the area behind the frame and carries no scrim. The outer frame
   area keeps its scrim (amended 2026-09-08 by the product owner: the scrim covered the frame
   interior too and dimmed the code the person was framing).
6. The hint strip uses `color.bg.raised` and 1 px `color.border.subtle` top and bottom borders.
   The `PAIRING` eyebrow uses `R-32-590` above the hint. While the camera did not start or the
   permission is denied, the strip carries no hint line: the preview area holds the state's one
   line, and `Point the camera...` under it would be a second instruction that contradicts the
   first (amended 2026-09-08 by the product owner).
7. The switch caption keeps the exact sentence from `R-30-945`. It appears only while a
   computer is connected.
8. The flash toggle uses the `flash_off_rounded` icon when off and `flash_on_rounded` when on.
   The off icon uses `color.fg.primary`. The on icon uses `color.accent.text`. Both use
   `size.icon.lg`. Their exact semantics labels are `Turn flash on` and `Turn flash off`. The
   toggle and the help action are the platform's own bar controls, per `R-33-033` and the bar
   rule of `docs/33-platform-chrome.md`, so each gives the platform's own press feedback
   (amended 2026-09-08 by the product owner: both were one platform's control on both platforms).
9. The shared text button shows `Type it in`, full width with its label centred, the one
   centring `R-30-293` permits. Its label is the platform's own label style of `R-32-212`, as
   written (amended 2026-09-09 by the product owner, per `R-03-104`: until then `TYPE IT IN` in
   `type.mono.button` with widget-applied upper case). In the `Permission denied` state,
   `Open Settings` sits above it, `space.2` apart, the same full width (amended 2026-09-08 by the
   product owner: both actions were right-aligned in one row).
10. The help sheet uses the bottom sheet anatomy of `docs/32-design-language.md` section 7.16:
    `color.bg.raised`, `radius.lg` top corners, the grab handle, a `type.heading` title. It keeps
    the three steps from `R-31-01-07` and one shared text button labelled `CLOSE`. The
    single-action sheets of the states table share that anatomy without the grab handle, because
    they refuse the drag and the tap outside (amended 2026-09-08 by the product owner: the two
    sheets on this screen had two paddings, two title sizes and two corner treatments).
11. In landscape, the preview and the hint/actions panel sit beside each other inside the safe
    area. The panel has an inset frame on all four sides and scrolls when its text and actions
    need more height. The square frame fits the preview's available width and height, with room
    for zoom controls below it. Portrait keeps the
    bottom bar. `docs/32-design-language.md` section 7.21 owns the dimensions.

## What the QR carries

The QR holds one pairing URI. `docs/11-relay-protocol.md` owns its exact form and
`R-30-900` fixes the one worked example this repository uses:

```text
herdr-remote://pair?v=1&r=https%3A%2F%2Frelay.example.com&h=n6Loxf94CfyIO6hOxlaHvA&p=remedy-tapestry-hubcap-oversleep-jailbird-kinetic
```

The four values the app takes from it:

| Field | Value in the example | What the app does with it |
| --- | --- | --- |
| `v` | `1` | Checks it. A higher number means this app is too old. |
| `r` | `https://relay.example.com` after decoding | Stores it as the relay origin when the app holds none. When the app already holds a different origin the app MUST refuse it, per `R-31-02-11`. |
| `h` | `n6Loxf94CfyIO6hOxlaHvA` | Uses it as the path segment for `/device/<handle>`. |
| `p` | `remedy-tapestry-hubcap-oversleep-jailbird-kinetic` | Uses it as the Noise pre-shared key. It never appears on this screen. |

## States

| State | Trigger | Screen shows |
| --- | --- | --- |
| Default, first pairing | The camera permission is granted and no computer is connected. | The first wireframe. No switch caption, per `R-30-945`. |
| Default, a computer is connected | The camera permission is granted and one computer is connected. | The second wireframe, with the switch caption of `R-30-945`. |
| Loading, the camera is starting | The route opened with the permission granted and the preview has not yet delivered a frame. | The viewfinder frame is drawn with nothing behind it. The hint reads `Starting camera...`. The flash toggle is disabled, because there is no camera to light. `type it in` stays enabled, per `R-31-02-12`. |
| Loading, pairing | A scan was committed. | The connecting panel of `R-31-02-14` replaces the bottom bar immediately. It names the relay host, shows the platform activity indicator, and enables `Cancel`. `Type it in` stays disabled. |
| Cancelled, no previous connection | The person pressed `Cancel` without a previous connection. | The scanner is ready. The hint reads `Pairing cancelled.` with `treat.ok`, per `R-31-02-14`. |
| Cancelled switch | The scan disconnected a computer before the person pressed `Cancel`. | Route to `/hosts`, per `R-30-947`. |
| Error, transport | The relay connection failed. | Show `Could not reach <host>: <reason>.`, per `R-31-02-15`. `R-31-02-08` decides where the person lands. |
| Error, protocol | The relay or handshake reported a protocol failure. | Keep the existing protocol sentence, per `R-31-02-15`. `R-31-02-08` decides where the person lands. |
| Error, the camera did not start | The platform reports no usable camera, so the preview cannot start. | The preview area gives way to one line, `The camera is not available. Type the phrase instead.`, with `treat.error`. `type it in` is the only enabled action. The screen MUST NOT wait on `Starting camera...` for a camera that will not arrive, per `R-31-02-12`. |
| Empty | Not applicable. A camera view has no empty state. | - |
| Permission denied | The user refused the camera. | The preview gives way to one line, `The app needs the camera to scan. Open Settings to allow it.`, plus one action `Open Settings` that calls the platform settings intent. The `type it in` action stays enabled. |
| Error, not one of ours | The frame holds a QR code that is not a pairing URI. Codes `pair_uri_scheme` and `pair_uri_path`. | The hint takes `treat.error` and reads `That is not a Herdr pairing code.` The scanner keeps running. Haptic `haptic.error`. |
| Error, malformed | The URI parsed but a field failed. Codes `pair_uri_version`, `pair_uri_field_missing`, `pair_uri_field_repeated`, `pair_uri_too_long`, `handle_malformed`. | The hint takes `treat.error` and reads the one matching sentence from the pairing error text table in `docs/30-ux-spec.md`. The scanner keeps running. |
| Error, insecure relay | `r` is a cleartext origin outside the permitted list. Code `relay_origin_insecure`. | A sheet titled `That relay is not encrypted` reads `A relay address must start with https, unless the computer is on your own network.` One action, `Close`. The app MUST NOT store the origin. |
| Error, relay address differs | `r` is a valid `https` origin, but the app already holds a different one. Code `relay_origin_conflict`. | A sheet titled `Different relay address` reads the one matching sentence from the pairing error text table in `docs/30-ux-spec.md`. One action, `Close`. Nothing is stored and nothing is paired, per `R-31-02-11`. |
| Error, expired | The phrase lifetime elapsed. Code `phrase_expired`, close code `4000`. | A sheet titled `Phrase expired` reads the one matching sentence from the pairing error text table in `docs/30-ux-spec.md`. One action, `Try again`, dismisses it and restarts the scanner. This arrives after the disconnect, so `R-31-02-08` decides where the person lands. |
| Error, computer not there | The relay knows no Host under that handle. Close code `4001`. | A sheet titled `The Relay pane is not open` says `Open the Relay pane on your computer, then read the code again.` One action, `Try again`. This arrives after the disconnect, so `R-31-02-08` decides where the person lands. |
| Error, host in use | Another phone already holds that computer. Error `host_in_use`, close code `4006`. | `R-31-02-08` decides. When this screen keeps it, the name-free banner replaces the hint with `Try again` as its one action, and the scanner stops, because a second read changes nothing. |
| Offline | The phone has no route to the relay. | The scan is read, but the app MUST NOT claim it paired, MUST NOT disconnect the connected computer, and MUST NOT start the switch at all, per `R-30-947`. A strip reads `No network. Pairing needs a connection, and a phrase lasts ten minutes.` with `treat.warning`. Both actions stay enabled. |

## Navigation

- In: `/welcome` primary action, or the `+` action on `/hosts`.
- Out, success: `/hosts/:hostId/agents` for the computer just paired, mockup `06-agent-list.md`.
  That computer is the connected one, per `R-30-945`, which is what makes a per-Host route legal
  under `R-30-946`.
- Out, fallback: `/pair/manual`, mockup `03-pair-code.md`.
- Out, help: the help sheet drawn above, in place. It closes back to this screen.
- Out, failure after the disconnect: `/hosts`, mockup `05-host-list.md`, when a computer was
  connected. `R-30-947` owns that landing state. When nothing was connected the screen stays, per
  `R-31-02-08`.
- Out, back: the previous route.

## Rules

- **R-31-02-01** The app MUST request the camera permission when this route opens, and never
  earlier.
- **R-31-02-02** The scanner MUST accept only the pairing URI form that `docs/11-relay-protocol.md`
  defines, and MUST reject every other QR code with the `not one of ours` error state.
- **R-31-02-03** The scanner MUST stop the camera when this route loses focus, so the camera
  indicator never stays lit.
- **R-31-02-04** A successful pair MUST fire `haptic.commit` and MUST leave this route inside
  `motion.duration.base`.
- **R-31-02-05** This screen MUST NOT display or log the phrase, handle, or full scanned URI.
  The connecting panel MAY display only the relay host and port, per `R-31-02-14`.
- **R-31-02-06** The app MUST NOT queue a pairing for later. A phrase lives 600 seconds
  (`R-13-022`), so a queued pairing would still expire. The offline state says so instead.
- **R-31-02-07** The app MUST store the relay origin from the QR only after the handshake succeeds.
  A failed pairing MUST leave the stored origin unchanged.
- **R-31-02-08** A failure that arrives after the disconnect of `R-31-02-10` leaves the phone
  connected to nothing. What the person sees depends on whether a computer was connected when the
  scan was committed.
  - A computer was connected. This is the failed switch of `R-30-947`, which owns the landing state
    for every relay-side failure. This screen MUST NOT raise a banner of its own, and MUST NOT dial
    the computer the person left.
  - Nothing was connected. No connection was given up and no saved row exists for the computer that
    refused, so this screen MUST stay and MUST show the failure in place, with the sentence its
    state row names.
  For `host_in_use` the in-place case needs its own wording, because the error arrives before any
  Host name does: `R-11-119` sends it in plaintext before the Noise tunnel opens, so the app holds a
  handle and no name. This screen MUST then show a name-free variant of the `R-30-940` banner: the
  same first line, `Computer in use on another phone`, and one name-free line under it, `Another
  phone is connected to that computer. Disconnect there, or remove that phone in the Relay pane,
  then try again.` It MUST carry `Try again` only. The `Connection details` action of `R-30-941`
  MUST NOT appear, because no `:hostId` exists to route it to. `/pair/manual` MUST use this same
  variant.
- **R-31-02-09** The `(i)` sheet MUST repeat the three setup steps of `R-31-01-07` word for word and
  MUST hold no other action. The sheet MUST pause the preview while it is open, and the scanner MUST
  resume when it closes, so the camera indicator never stays lit behind a sheet that covers the
  viewfinder.
- **R-31-02-10** A successful scan MUST disconnect the connected computer **before** the pairing
  handshake starts, never after it succeeds. The handshake runs on the new handle and the app holds
  exactly one socket, per `R-20-009`, so there is no order in which both computers are connected.
  That disconnect is the switch of `R-03-044`, so it keeps every pairing and every Device key and
  MUST NOT raise a confirmation. `R-30-945` owns that ordering for both pairing screens and
  `R-30-947` owns the landing state after a failed switch, including the prohibition on dialling the
  computer the person left.
- **R-31-02-11** The app MUST NOT store the origin from a QR when it already holds a different one.
  `R-30-927` forbids the app changing the origin on its own, and `R-30-924` makes a change
  destructive and owned by `/settings`. A refused origin MUST NOT pair the computer, MUST NOT save
  it, and MUST NOT change the stored origin.
- **R-31-02-12** The two waits MUST remain distinct. While the camera starts, show
  `Starting camera...` and keep `Type it in` enabled. Disable the flash and zoom controls.
  During pairing, disable `Type it in` and keep `Cancel` enabled in the panel of `R-31-02-14`.
  The screen MUST NOT show a connection state before pairing starts.
  Replace the camera start hint when the platform reports no usable camera.
- **R-31-02-13** The viewfinder MUST support two-finger pinch and device-range presets.
 The camera bridge in `R-22-088` owns range discovery and factor conversion.
 Show `0.5x`, `1x`, `2x`, and `5x` only when the device range permits each value.
 If the maximum is below `5x`, include that maximum without a duplicate preset.
 Labels MUST represent actual magnification relative to the wide camera, not a normalized plugin scale.
 Use `CupertinoButton` on iOS. Use `TextButton` and selected `FilledButton.tonal` on Android.
 Each preset MUST expose toggled selection semantics and its ratio, for example `Zoom 5x`.
 Keep the native selected appearance and the minimum target in `R-30-290`.
 The preset row sits on the scrim directly below the frame, `space.4` under its bottom edge,
 centred; it MUST NOT overlap the frame, so the target area stays clear (amended 2026-09-16 by
 the product owner: the first build placed the row inside the frame's bottom edge).
 At gesture start, save the current factor. Multiply that factor by each pinch update's cumulative scale.
 Clamp the result to the device range. Do not multiply the previous update by the cumulative scale.
 Do not replace preset labels with a synthetic zoom label during pinch.
 Decorative overlays MUST ignore pointer events so transparent areas do not block the viewfinder gesture.
 Preset buttons MUST remain interactive above those overlays.
 Disable zoom while the camera starts or is unavailable. Hide the controls when no valid range is available.
 Never invent a fallback range. Reduced motion MUST disable the iOS zoom ramp.
- **R-31-02-14** A committed scan MUST immediately replace the bottom bar with a connecting panel.
  Show the `CONNECTING` eyebrow, `Connecting to <host>...` in `type.body`, and a `ChromeActivityIndicator`.
  `<host>` MUST contain only the relay host and optional port, such as `172.16.188.73:8080`.
  The panel MUST have one enabled action: `Cancel`, an `AppTextButton` with the platform text-button
  appearance.
  Cancel MUST abort the handshake and close the relay connection that this screen opened.
  Cancel MUST fire `haptic.select`. If no computer was disconnected, restore the scanner with
  `Pairing cancelled.` in `treat.ok`.
  Otherwise, call `onCancelledSwitch` and route to `/hosts`, per `R-30-947`.
  A cancelled attempt MUST NOT later save a pairing or navigate to the computer.
- **R-31-02-15** Transport failures MUST read `Could not reach <host>: <reason>.`
  The shared sentence builder MUST serve QR and manual pairing.
  Map `SocketException`, `WebSocketException`, `TimeoutException`, and `HandshakeException`,
  including OS error codes, to these reasons:
  `connection refused`, `timed out after <n> s`, `no route to the network`,
  `the relay closed the connection`, or `TLS failed`.
  Use the exception message when no reason matches. Remove secrets prohibited by `R-31-02-05` before
  display.
  Relay and protocol failures MUST keep their existing sentences from the pairing error text table
  in `docs/30-ux-spec.md`.
- **R-31-02-16** This screen MUST support landscape. The preview and the hint/actions panel MUST
  share the available width equally and remain inside the side and bottom safe areas. The panel
  MUST scroll when needed, including while pairing and at accessibility text sizes. Camera failure
  and permission messages MUST also scroll when needed. The frame and every zoom target MUST fit
  inside the preview without overlap. Rotating MUST keep the scanner mounted and preserve the
  current camera state. The landscape panel MUST have a complete frame with side margins,
  using the frame and inset of `docs/32-design-language.md` section 7.21. This also applies
  to its connecting state. Portrait MUST keep the preview above the bottom bar.

## Accessibility

- Touch target: the back chevron, `(i)`, the flash toggle and `type it in` each meet the minimum
  target of `R-30-290` and `R-30-740`.
- Contrast: the hint sits in `color.fg.secondary` on `color.bg.raised`, a passing row in `R-32-150`,
  per `R-30-720`. The viewfinder corner marks are a framing aid, not a state indicator, per
  `R-32-558`, and the hint text carries every word the person needs.
- Screen reader: `(i)` MUST carry the label `How to pair a computer`, the title of the sheet it
  opens, and the back chevron the label `Back`, per `R-30-717`. The camera preview MUST be
  excluded from the semantics tree, because a live image has no useful label. An error the hint
  carries MUST be announced once, per `R-30-742` and `R-30-912`, because the hint sits away from the
  focus and the scanner keeps running. An error that opens a sheet MUST NOT be announced: the sheet
  takes the focus, which is the changed node `R-30-742` prefers.
- Focus order: per `R-30-719`, back chevron, title, `(i)`, then the hint, then the switch caption
  when it is present, then the flash toggle, then `type it in`. The preview is skipped. A sheet
  traps the focus until it closes.

## Open questions

None.

## Sources

- [CameraX ZoomMath.getLinearZoomFromZoomRatio][camerax-zoommath] - reciprocal ratio conversion
  used by the bridge in `R-22-088`.
- [Apple Support: Zoom in or out in Camera on iPhone][apple-camera] — camera pinch and zoom
  controls.
- [MobileScannerController.setZoomScale][scanner-zoom] — camera zoom API.

- `docs/32-design-language.md` - the app bar `R-32-510`, the QR viewport `R-32-558` and `R-32-559`,
  the text action `R-32-526`, the opacity tokens `R-32-331`, and the contrast table `R-32-150`.
- `docs/30-ux-spec.md` - the pairing error text table, `R-30-900`, `R-30-921`, `R-30-927`,
  `R-30-940`, `R-30-941`, the pairing switch `R-30-945`, the per-Host route rule `R-30-946`, the
  failed switch `R-30-947`, and the announcement rule `R-30-742`.
- `docs/11-relay-protocol.md` - the pairing URI form, the parsing error codes, the plaintext
  `host_in_use` error `R-11-119`, and the close codes `4000`, `4001` and `4006`.
- `docs/13-security-pairing.md` - the phrase, its 600 second lifetime, and the Noise handshake that
  uses it.
- `docs/03-product-decisions.md` - the saved-computer policy `R-03-043` and the switch rule
  `R-03-044`.
- `docs/20-mobile-framework.md` - the one socket rule `R-20-009`.

[apple-camera]: https://support.apple.com/guide/iphone/camera-basics-iph263472f78/ios
[scanner-zoom]: https://pub.dev/documentation/mobile_scanner/7.4.0/mobile_scanner/MobileScannerController/setZoomScale.html
[camerax-zoommath]: https://github.com/androidx/androidx/blob/androidx-main/camera/camera-camera2/src/main/java/androidx/camera/camera2/internal/ZoomMath.kt
