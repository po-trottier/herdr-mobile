# 01 - First run and welcome

| Field | Value |
| --- | --- |
| Route | `/welcome` |
| Surface | Device, Android and iOS |
| Spec | `docs/30-ux-spec.md` |

## Wireframe

```text
--------------------------------------+
|                                      |
| ┌──────────────────────────────────┐ |
| │          HERO BLOCK              │ |
| │  ┌────────────────────────────┐  │ |
| │  │     PLAIN, NO GRID         │  │ |
| │  │                            │  │ |
| │  │                     [RAM]  │  │ |
| │  │                            │  │ |
| │  ├────────────────────────────┤  │ |
| │  │  HERDR REMOTE         [▼]  │  │ |
| │  └────────────────────────────┘  │ |
| └──────────────────────────────────┘ |
|                                      |
|  Watch the herd.                     |
|  From anywhere.                      |
|                                      |
|  Read a pane. Send a prompt.         |
|  Nothing else crosses the network.   |
|                                      |
| ┌──────────────────────────────────┐ |
| │ 01  Open Herdr on your computer. │ |
| │ 02  Open the Relay pane.         │ |
| │ 03  Scan the QR code it shows.   │ |
| └──────────────────────────────────┘ |
|                                      |
| (i) Alerts arrive while the app is   |
|     running. If the phone closes the |
|     app, you see the alert the next  |
|     time you open it.                |
|                                      |
|     Alerts come from the computer    |
|     you are connected to. If an      |
|     agent finishes on another        |
|     computer, you see it when you    |
|     connect to that computer.        |
|                                      |
| +----------------------------------+ |
| |           Scan QR code           | |
| +----------------------------------+ |
|                                      |
|      Enter the phrase instead        |
|                                      |
--------------------------------------+
```

The hero stays pinned to the top safe-area edge. Both actions sit in a footer that is always on
screen. Only the content between them scrolls, and only when it cannot fit, per `R-31-01-08`.

## Callouts

1. The hero starts at the top safe-area edge and takes every pixel the content below it does not
   need, so its height follows the viewport: tall on a large phone, short on a small one, and zero
   on a viewport the fixed content fills by itself. The hero is the one band painted plain
   `color.bg.base`, with no ground grid; the grid starts below its bottom edge, which has a 1 px
   `color.border.subtle` rule. See `R-32-332` and `R-32-594`.
2. The brand mark uses `color.fg.primary` and 64% of the hero height, at most 320 logical pixels,
   and shrinks with the hero. Its right crop is flush with the screen edge. Its bottom crop touches
   the hero rule. See `R-32-594`.
3. The `HERDR REMOTE` eyebrow sits at the bottom-left of the hero. It stays `space.4` above the
   rule. See `R-32-590` and `R-32-594`.
4. The headline starts `space.6` below the rule. It uses `type.display` and
   `color.fg.primary`. It reads `Watch the herd.` and `From anywhere.` on two lines. The body uses
   `type.body` and `color.fg.secondary`. It reads `Read a pane. Send a prompt. Nothing else
   crosses the network.`
5. The featured steps card uses `color.bg.raised`, a 1 px `color.border.subtle` border, and
   `radius.md`. See `R-32-593`. Its 2 px top edge uses `color.accent.primary`. See `R-32-333`.
   Step numbers use `type.mono.button`, `color.accent.text`, and `01`, `02`, and `03`, the card's
   one mono size (amended 2026-09-09 by the product owner, per `R-03-104`: the two actions below
   the card are the platform's own sans label now, so the step number no longer shares a size with
   them).
6. The alert note keeps both existing sentences. It uses `type.caption`, `color.fg.secondary`,
   and the `info` icon at `size.icon.sm`, aligned to the first line. See `R-30-512` and
   `R-30-517`, and the `Alert note` row of the welcome hero table in `docs/32-design-language.md`
   (amended 2026-09-08 by the product owner: with both sentences in `type.body` the column
   outgrew the 375 point reference viewport, `R-31-01-08` gave the hero zero height, and the
   first screen showed no mark and no eyebrow).
7. The shared primary and text buttons show `Scan QR code` and `Enter the phrase instead`, as the
   wireframe writes them. Their labels are the platform's own label style of `R-32-212`, as
   written (amended 2026-09-09 by the product owner, per `R-03-104`: until then `type.mono.button`
   with widget-applied upper case). The two actions sit `space.2` apart, the gap every
   filled-then-text stack in the app uses (amended 2026-09-08 by the product owner: this screen
   alone used `space.1`).

## States

| State | Trigger | Screen shows |
| --- | --- | --- |
| Default | No Host is saved. | The wireframe above. |
| Loading | None. The screen reads local storage only. | Not applicable. This screen never waits. |
| Empty | Same as default. No saved Host is the normal first run case. | The wireframe above. |
| Error | The device's secure key storage fails to initialise (a rare operating-system or hardware fault, unrelated to a screen lock). | The setup list gives way to one line, `Something went wrong setting up this phone. Restart the app.`, with `treat.error`. The primary action is disabled. |
| Offline | The phone has no network. | The primary action stays enabled, because the camera works offline. A strip above it reads `No network. Pairing needs a connection, and a phrase lasts ten minutes.` with `treat.warning`, the same strip `/pair/manual` shows (amended 2026-09-08 by the product owner: one sentence, one rendering, on every pairing screen; the lifetime is the 600 seconds of `R-13-022`). |

## Navigation

- In: cold start when the saved Host count is zero, per `R-03-043`. A saved Host that is not
  connected keeps this screen away.
- Out, primary: `/pair/scan`, mockup `02-pair-scan.md`.
- Out, secondary: `/pair/manual`, mockup `03-pair-code.md`.
- The system back gesture leaves the app. This screen has no back target.

## Rules

- **R-31-01-01** The app MUST show `/welcome` when the saved Host count is zero, and MUST NOT show
  it when the count is one or more. The test is saved, never connected. `R-03-043` saves every
  paired computer and connects at most one, so a cold start with three saved computers and none
  connected MUST route to `/hosts` and MUST NOT come here.
- **R-31-01-02** This screen MUST NOT ask for the camera permission. `/pair/scan` asks at the moment
  it needs the camera.
- **R-31-01-03** This screen MUST NOT hold a carousel, a page indicator, or a second primary action.
- **R-31-01-04** This screen MUST carry both alert limitations, the `R-30-512` sentence and the
  `R-30-517` sentence, each in its exact wording, and MUST NOT request the platform alert
  permission. `R-30-509` owns that request and puts it on the first agent list after the first
  pair. Those two sentences are the whole explanation, so this screen MUST NOT add a second in-app
  explainer, a `Turn on` action, or an app-level alert switch.
- **R-31-01-05** This screen MUST NOT name a relay address, offer one, or imply that the app already
  knows one. The app ships with none, per `R-30-920`.
- **R-31-01-07** The three setup steps are written on this screen and nowhere else: `Open Herdr on
  your computer.`, `Open the Relay pane.`, `Scan the QR code it shows.` The help sheet on
  `/pair/scan` repeats these three words for word, per `R-31-02-09`, and MUST NOT reword them.
- **R-31-01-08** Both actions MUST sit in a footer that is on screen at every viewport size and
  text scale, without a scroll. Above the footer the screen is one vertical column: hero, headline,
  steps card and both limitation sentences. That column scrolls only when it cannot fit, and the
  hero gives up its height first, so a scroll is the last resort and never hides an action. Both
  limitation sentences MUST sit above both actions in reading order. The person reads them before
  the first tap starts pairing, which is the only moment this screen can promise, because the
  request itself arrives two screens later, per `R-30-509`. `R-31-01-03` already forbids a carousel.
  While the column is scrolled under the footer, the footer MUST draw a 1 px `color.border.subtle`
  rule on its top edge, and MUST draw none once the column fits or is scrolled to its end, so a cut
  sentence reads as scrolled under, not as the end of the text (amended 2026-09-08 by the product
  owner: on the reference viewport the last sentence was cut mid-line with no edge).
- **R-31-01-09** This screen MUST NOT require, check for, or mention a device screen lock, a
  passcode or biometric enrolment, and MUST NOT disable `Scan QR code` for that reason. Pairing
  and every other app action work fully with no screen lock present.
  `docs/03-product-decisions.md` R-03-090 and `docs/decisions/ADR-009-optional-app-lock.md`
  record this reversal of the former precondition. A person who wants App Lock is offered it
  once, after the first successful pair, per `docs/30-ux-spec.md` R-30-521, never here.

## Retired rules

This table carries two retired rule ids. Each id stays reserved, so an old citation still
resolves.

| Rule | Disposition |
| --- | --- |
| `R-31-01-06` | Retired. It required the app to continue to the pairing route whatever the person answered to the alert permission request, and to ask no second time. `R-30-509` has moved that request off this screen to the first agent list after the first pair, so this screen raises no request and has no answer to continue from. `R-30-509` now carries all three outcomes, including the dismissal that answers nothing. |
| `R-31-01-10` | Retired. It required a floating brand mark between the alert note and the primary action. The anchored mark now belongs to the welcome hero, per `R-32-594`. The old floating placement stays prohibited. |

## Accessibility

- Touch target: both actions meet the minimum target of `R-30-290` and `R-30-740`, whose value and
  sources are in `R-32-360`. The secondary action is text only, so its row is larger than its
  glyphs, which `R-30-291` permits.
- Contrast: `color.fg.primary` and `color.fg.secondary` on `color.bg.base`, and `color.fg.on_accent`
  on `color.accent.primary`, each have a passing row in the contrast table of `R-32-150`, per
  `R-30-720`. The step numbers use `color.accent.text` on `color.bg.base`, which is a passing row
  there too, and `R-32-124` permits accent ink on that surface only.
- Screen reader: the numbered list MUST be read as three separate items, `Step 1 of 3` and so on,
  not as one paragraph. The two limitation sentences MUST be read as two separate items, not run
  together. The step icons and the alert block's `info` icon are decorative, redundant with text
  already on screen, and MUST NOT be announced separately. The primary action MUST carry the
  label `Scan QR code`, per `R-30-717`, which covers every control that carries no text of its
  own.
- Focus order: per `R-30-719`, the product name, the value sentence, the three steps, the
  `R-30-512` limitation, the `R-30-517` limitation, the primary action, then the secondary action.
  There is no app bar on this screen, and no system sheet opens over it.

## Open questions

None.

## Sources

- `docs/32-design-language.md` - the type scale `R-32-202`, the display token rule `R-32-205`, the
  accent permission rule `R-32-124`, the filled button `R-32-525`, the text action `R-32-526`, the
  touch target `R-32-360`, the contrast table `R-32-150`, the icon map `R-32-401` and the icon
  size and alignment rule `R-32-402`.
- `docs/30-ux-spec.md` - gesture model, status model, the two alert limitations `R-30-512` and
  `R-30-517`, the first-run permission moment `R-30-509`, the App Lock prompt moment `R-30-521`,
  and the no default relay rule `R-30-920`.
- `docs/03-product-decisions.md` - the saved-computer policy `R-03-043`, the connected-computer
  alert limit `R-03-045`, and the optional App Lock policy `R-03-090`.
- `docs/decisions/ADR-009-optional-app-lock.md` - the decision to make App Lock optional.
