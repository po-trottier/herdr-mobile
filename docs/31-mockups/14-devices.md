# 14 - Paired Device management

| Field | Value |
| --- | --- |
| Route | `/hosts/:hostId/devices` |
| Surface | Device, Android and iOS |
| Spec | `docs/30-ux-spec.md` |

The Host keeps the paired phone list, so this screen reads and writes on the Host. The relay holds
no grant and cannot revoke one, per `R-30-610`. This is a per-Host route, so it only ever opens for
the connected computer, per `R-30-946`. A computer serves one phone at a time, so at most one row
here is `connected`.

## Wireframe

```text
+--------------------------------------+
| <  Phones on patrick-desk        [x] |
+--------------------------------------+
| Pixel 8                 This phone > |
| paired 24 Aug 09:14 · seen now       |
+--------------------------------------+
| iPhone 15                          > |
| paired 22 Aug 17:02 · seen 3m ago    |
+--------------------------------------+
| old-pixel                          > |
| paired 02 Aug 11:30 · seen 21d ago   |
+--------------------------------------+
```

Redrawn 2026-09-09 by the product owner, per `R-03-105` and `R-03-111`. The list is the platform's
own: the three phone rows are one list section, per `R-33-073`, and the list ends with its last
phone, per `R-03-109`. The trailing `>` stands for the iOS push chevron of `R-33-072.2`; an Android
row carries none, per `R-33-072.3`, and this file names no glyph. The `[x]` in the app bar stands
for the `delete_outline` glyph of `treat.destructive`, which this scale cannot draw: it is the one
`Remove phones` action of `R-03-111` (callout 15), and it opens the two surfaces drawn next. No row
carries a state bar (callout 2), and nothing sits before a phone's name. Until 2026-09-09 the three
remove actions were rows in a second section under a footnote strip; both are retired.

## Wireframe, the remove menu on Android

```text
+--------------------------------------+
| <  Phones on patrick-desk        [x] |
+--------------------------------------+
| Pixel 8        +---------------------+
| paired 24 Aug  | [x] Remove this pho |
+--------------- | [x] Remove other ph |
| iPhone 15      | [x] Remove every ph |
| paired 22 Aug  +---------------------+
+--------------------------------------+
| old-pixel                          > |
| paired 02 Aug 11:30 · seen 21d ago   |
+--------------------------------------+
```

Added 2026-09-09 by the product owner, per `R-03-111`. The menu is the platform's own Material
menu, anchored under the action and drawn by the component: its surface, its corner, its shadow
and its item height are the component's, and this file names none of them. Each item is one
`MenuItemButton` whose label is `Remove this phone`, `Remove other phones` or `Remove every
phone`, in that order, with the `delete_outline` glyph of `treat.destructive` leading it. The
drawing cuts the labels only because of its width; the real menu shows each whole.

## Wireframe, the remove sheet on iOS

```text
+--------------------------------------+
| <  Phones on patrick-desk        [x] |
+--------------------------------------+
| Pixel 8                 This phone > |
| paired 24 Aug 09:14 · seen now       |
+--------------------------------------+
|                                      |
+--------------------------------------+
|          Remove this phone           |
+--------------------------------------+
|         Remove other phones          |
+--------------------------------------+
|          Remove every phone          |
+--------------------------------------+
|                                      |
+--------------------------------------+
|               Cancel                 |
+--------------------------------------+
```

Added 2026-09-09 by the product owner, per `R-03-111`. The sheet is the platform's own
`CupertinoActionSheet`: three `CupertinoActionSheetAction`s marked destructive, in the same order
as the menu, and the `Cancel` button the component groups apart under them. The component draws
the sheet, the dimmed list behind it and the destructive ink; this file names none of them. No
action carries a glyph, because the platform's action sheet carries none.

## Wireframe, the Device detail screen for this phone

```text
+--------------------------------------+
| <  Pixel 8                           |
+--------------------------------------+
| HEALTH                               |
+--------------------------------------+
| Last connected                   now |
+--------------------------------------+
| App Lock                          On |
+--------------------------------------+
| Pairing         Paired 24 Aug 2026.. |
+--------------------------------------+
| How to revoke: Remove phones on the  |
| phone list removes one phone or      |
| every phone. The r key in the Relay  |
| pane on your computer removes every  |
| phone.                               |
+--------------------------------------+
|                                      |
+--------------------------------------+
| Platform                     Android |
+--------------------------------------+
| Key fingerprint  3f9a-1c04-be77-20d5 |
+--------------------------------------+
| Rename this phone in Settings.       |
+--------------------------------------+
|                                      |
+--------------------------------------+
| [x] Remove                           |
+--------------------------------------+
```

The detail is a pushed screen since 2026-09-09, per `R-03-105` and `R-33-072.4` (until then a
bottom sheet, opened from a `Details` control on the row): a row that pushes carries the chevron,
so what it opens is the next level, and a sheet is not one. The `HEALTH` group is the health card
of `R-03-113` item 6 (added 2026-09-09, callout 16): it is present only on the `This phone` row's
detail, because only this phone knows its own lock state. The `Pairing` value reads
`Paired 24 Aug 2026 09:14` in full; the drawing cuts it for width. The two captions are present
only on this phone's detail too, because a phone cannot rename another phone. The back control is
the platform's own, per `R-33-070`, so the screen has no `Close`.

## Wireframe, the Device detail screen for another phone

```text
+--------------------------------------+
| <  iPhone 15                         |
+--------------------------------------+
| Paired             22 Aug 2026 17:02 |
+--------------------------------------+
| Last seen                     3m ago |
+--------------------------------------+
| Platform                         iOS |
+--------------------------------------+
| Key fingerprint  7b2e-90af-13c8-d4e1 |
+--------------------------------------+
|                                      |
+--------------------------------------+
| [x] Remove                           |
+--------------------------------------+
```

Another phone's detail has no health card and no caption: its four values sit in one group, then
`Remove`. The pair time and the last seen time are the same two facts the `HEALTH` group carries
on this phone's detail, shown once on each screen, per `R-03-058`.

## Wireframe, the confirmation for one phone

```text
+--------------------------------------+
|                                      |
|  Remove this phone from              |
|  patrick-desk?                       |
|                                      |
|  You will have to pair again to      |
|  reach this computer.                |
|                                      |
|  cancelling:   Cancel                |
|  destructive:  Remove                |
|                                      |
+--------------------------------------+
```

## Wireframe, the confirmation for the other phones

```text
+--------------------------------------+
|                                      |
| Remove 2 other phones from           |
| patrick-desk?                        |
|                                      |
| They pair again. This phone keeps    |
| access.                              |
|                                      |
| cancelling:   Cancel                 |
| destructive:  Remove other phones    |
|                                      |
+--------------------------------------+
```

Added 2026-09-09 by the product owner, per `R-03-105`. The count is exact and the noun follows it:
`Remove 1 other phone from patrick-desk?` when one other phone is paired.

## Wireframe, the confirmation for every phone

```text
+--------------------------------------+
|                                      |
|  Remove every phone from             |
|  patrick-desk?                       |
|                                      |
|  This phone and 2 other phones lose  |
|  access at once. Everyone pairs      |
|  again. Removing every phone is the  |
|  same as the r key in the Relay pane |
|  on your computer.                   |
|                                      |
|  cancelling:   Cancel                |
|  destructive:  Remove every phone    |
|                                      |
+--------------------------------------+
```

Amended 2026-09-09 by the product owner, per `R-03-111`: the sentence about the `r` key ends the
body, where the list's footnote strip used to carry it (callout 10). The `r` is the inline key of
`R-32-599`, drawn as a cap on the sentence's baseline.

All three frames name each action by its **role** and draw no order. `R-33-074` fixes the
component, the action titles, the placement and whether any action is preferred. This file MUST
NOT name a position, an action order or an initial focus target.

## Wireframe, a revoke that has not answered yet

```text
+--------------------------------------+
| <  Phones on patrick-desk        [x] |
+--------------------------------------+
| Pixel 8                 This phone > |
| paired 24 Aug 09:14 · seen now       |
+--------------------------------------+
| iPhone 15                          > |
| paired 22 Aug 17:02 · seen 3m ago    |
+--------------------------------------+
| old-pixel                      ... > |
| removing                             |
+--------------------------------------+
```

The `[x]` action is disabled here, at `opacity.disabled`, which this scale cannot draw (callout
11).

## Wireframe, a revoke whose outcome is unknown

```text
+--------------------------------------+
| <  Phones on patrick-desk        [x] |
+--------------------------------------+
| This phone did not get an answer.    |
| The change may already be done.      |
|                                      |
|             Check now                |
+--------------------------------------+
| Pixel 8                 This phone > |
| paired 24 Aug 09:14 · seen now       |
+--------------------------------------+
| iPhone 15                          > |
| paired 22 Aug 17:02 · seen 3m ago    |
+--------------------------------------+
| old-pixel                          > |
| paired 02 Aug 11:30 · seen 21d ago   |
+--------------------------------------+
```

The `[x]` action is disabled here too, until `Check now` resolves the state (callout 12).

## Callouts

1. The back control and the title `Phones on patrick-desk`, in the app bar of `R-32-510`, with the
   `Remove phones` action at the bar's trailing edge (callout 15). The list is per computer,
   because the computer owns the pairing. The drawn `<` is a placeholder: the back glyph, the back
   label and the back gesture belong to each platform's own navigation component, per `R-33-070`,
   and this file names none of them.
2. Connection state. The list carries **no state bar** (amended 2026-09-09 by the product owner,
   per `R-03-105`; until then the state bar of `R-32-592` sat on every row, `ok` for the connected
   phone and `idle` for a paired phone). Every paired phone rests in one state hue, per `R-32-130`,
   so a bar that cannot differ between rows says nothing, and one fact takes one mark, per
   `R-03-058`. The connected phone is marked instead by `This phone` (callout 6) and by `seen now`
   in its subtitle (callout 4), and the row's announcement carries `Connected` or `Not connected`
   in words. In every live state exactly one row is connected, and it is always the `This phone`
   row. A second phone cannot be connected, because the relay refuses it with `host_in_use`, per
   `R-03-040`. So a person who can read a live list is the person holding the computer, and the
   list says which row is theirs. It never says which computers are reachable. The one exception
   is a stale list. In the `Host in use` and `Offline` states the marks are the value of the last
   successful read, so `seen now` may sit on a row that is not connected now. The dimmed list and
   the timestamp in the header say so.
3. Device name, the row's title. Each phone row is the platform's own push row, `ChromeListRow.push`
   of `R-33-073` (amended 2026-09-09 by the product owner, per `R-03-105`; until then the two-line
   row of `R-32-515` with a drawn `THIS PHONE` chip or a `Details` control in its trailing slot):
   on iOS one `CupertinoListTile` inside the `CupertinoListSection`, which keeps the platform's own
   height, inset and type; on Android the list row of `docs/32-design-language.md` section 7.4,
   `type.body.strong` in `color.fg.primary`, whose `border.subtle` divider is inset `space.4` and
   absent on the last row. The row's whole surface is one tap and one semantics node.
4. The subtitle, one line: the pair time, then the last-seen age, `paired 24 Aug 09:14 · seen 3m
   ago`, in the row's own secondary line (`type.caption` in `color.fg.secondary` on Android, the
   tile's subtitle on iOS). The `·` is a middle dot between the two facts. `now` means inside the
   last 30 seconds, and a connected row reads `seen now` regardless of `last_seen`, because the
   Host stamps `last_seen` on every frame it serves (decided 2026-09-03). Amended 2026-09-09 by
   the product owner, per `R-03-105`: until then the age sat right aligned on its own line.
5. The row opens the Device detail screen drawn above, by pushing it as the next level in the
   hierarchy (amended 2026-09-09 by the product owner, per `R-03-105`; until then a `Details`
   control opened a bottom sheet). `R-33-072.4` names this exact row: a phone row either pushes a
   detail route and keeps its chevron, or keeps its sheet and drops it; the product owner asked for
   the platform row that pushes, so the row pushes and iOS keeps the chevron of `R-33-072.2`, while
   Android carries none, per `R-33-072.3`. The push is the platform's own page route on this
   screen's own navigator, not a named route: the detail carries the one `device_list` entry the
   row already holds, and `R-31-14-07` forbids the identity values a URL would need. The detail
   shows the name in its app bar, then the pair time, the last seen time, the platform and the key
   fingerprint as the platform's own information rows (`ChromeListRow.static` of `R-33-073`, the
   label as the title and the value at the trailing edge in `type.body` `color.fg.secondary`, the
   fingerprint in `type.mono.code`), and one `Remove` action, the destructive row of callout 7,
   alone in its own section. On this phone's detail the pair time and the last seen time are the
   `Pairing` and `Last connected` rows of the health card (callout 16), and the platform and the
   fingerprint follow in their own group. The screen shows the name and never edits it. A person
   sets this phone's own name in the row `This phone's name` on `/settings`, per `R-31-15-12` and
   `docs/31-mockups/15-appearance.md`, which is what the caption line under the values points at,
   in `type.caption` `color.fg.secondary` on the row text's edge. No grab handle and no `Close`:
   the back control of `R-33-070` returns to the list. Each row speaks as one `label, value` pair.
6. `This phone`, at the trailing edge of the current Device's row alone: the platform's secondary
   label, sentence case, `type.label` in `color.fg.secondary`; on iOS it takes the tile's own
   secondary slot before the chevron, where the platform puts a row's value. It is a word, not a
   chip (amended 2026-09-09 by the product owner, per `R-03-105`: the drawn `THIS PHONE` chip,
   `bg.high` fill, `border.strong`, `type.micro` UPPER, is retired). It marks which phone is the
   reader's own, and it does not remove the row's own tap target: this row pushes the same detail.
7. `Remove this phone`. It revokes only the current Device. Since 2026-09-09 it is the first item
   of the choice surface behind the `Remove phones` action (callout 15), per `R-03-111`: on
   Android a `MenuItemButton` whose label is the action name and whose leading glyph is the
   `delete_outline` of `treat.destructive`, `size.icon.md` in `color.status.error`, while the
   label keeps the component's own ink, per `R-32-527`; on iOS a `CupertinoActionSheetAction`
   marked destructive, whose red ink is the component's own. Until then it was a destructive row,
   `ChromeListRow.destructive` of `R-33-073` (2026-09-09, per `R-03-105`), before that the
   platform text button of `R-03-059`, and before that an app-drawn row; the row form survives on
   the detail screen as `Remove`, the destructive row of `docs/32-design-language.md` section 7.9,
   where the hue lives in the leading glyph alone and no bar is drawn, per `R-03-058`. A disabled
   item takes the component's own disabled state on Android and `opacity.disabled` on iOS, per
   `R-32-502`, and keeps its place. After it succeeds, the app returns to `/hosts` and that
   computer is gone from the list.
8. `Remove other phones` (added 2026-09-09 by the product owner, per `R-03-105`). It revokes every
   paired phone except the current Device, and it is the second item of the surface, drawn exactly
   like callout 7. The wire offers no "every phone but one" request, per `R-11-063`, so the app
   sends one `revoke_device` per other phone, in sequence, each awaited before the next is sent,
   which keeps `R-31-14-12.1`'s one revoke in flight. Every row the sequence covers reads
   `removing` from the start, and each confirmed phone leaves the list as its `revoke_result`
   arrives. A refusal or a silent revoke stops the sequence at that phone and reports it as a
   single revoke would, so the strip or the `Outcome unknown` block names one phone; the phones
   already removed stay gone and the rest keep their rows, because a second revoke aimed at a list
   the app can no longer trust is what `R-31-14-12.1` forbids. The item is disabled while no other
   phone exists, because there is nothing for it to do.
9. `Remove every phone`. This is the `remove all` action of the Host plugin, named in plain words,
   and the third item of the surface, drawn exactly like callout 7. It stays on the surface when
   only this phone is paired, and its confirmation then reads `This phone loses access. You pair
   again.` with no count of others, before the sentence of callout 10.
10. The sentence about the `r` key. It names the exact equivalence with the `r` key in the Relay
    pane, so a person never wonders whether the two differ. Since 2026-09-09 it is the last
    sentence of the `Remove every phone` confirmation body, per `R-03-111`; until then a footnote
    strip under the three remove rows, which is retired. The `r` is the inline key of section 7.33
    of `docs/32-design-language.md`, per `R-32-599`: a `type.mono.key` cap on its own small raised
    box, on the sentence's baseline, never the plain word (amended 2026-09-09 by the product owner,
    per `R-03-103`). The dialog body of `R-33-074` already draws a named key as a cap, so the
    sentence needs nothing of its own there. A screen reader gets the plain sentence.
11. The trailing `...` and the word `removing` on a row whose revoke is in flight. The in-place
    spinner `size.spinner` of `R-32-350` sits in the row's trailing slot, before the iOS chevron,
    and `removing` replaces the subtitle. Every revoke control on the screen is disabled while it
    shows, per `R-31-14-12`: the `Remove phones` action dims at `opacity.disabled`, and `Remove` on
    the detail screen dims with it.
12. The two sentences and `Check now`. This is the `Outcome unknown` state of `R-30-518`, and that
    rule fixes both the sentences and the control name. It is **not** an error state: no
    `treat.error`, no `error` icon, no raw error text and no `haptic.error`, because nothing failed
    and there is no error to report. The block takes the plain body tokens on `color.bg.raised`.
    `Check now` is not a retry. It reads a fresh `device_list` and never re-sends `revoke_device`.
    `R-31-14-12` holds what this screen reconciles against.
13. Primary navigation. This screen is pushed from the `Settings` destination, and the two platforms
    diverge on what the bottom control does then. The drawing is platform-neutral and omits it.
    `R-33-071` owns the divergence, and it also covers the detail screen, which is pushed on the
    same navigator (amended 2026-09-09, per `R-03-105`: the detail was a modal sheet).
14. Ground. Both screens paint plain `color.bg.base`, with no grid and no paper block, per
    `R-03-107` (amended 2026-09-09 by the product owner: the first draft of that rule put the
    ground grid of `R-32-332` under every screen, with each section on a paper block; the owner saw
    the grid around solid list blocks and rejected it). Each platform section of `R-33-073` sits on
    the ground with its `space.6` gap above it, the strips and the blocks of the live states sit on
    the same ground, and the list ends with its last row, with no empty band under it, per
    `R-03-109`. This screen has no empty state, because the `Empty` row of the states table still
    holds this phone, so it carries no brand silhouette. The skeleton and the error block sit on
    the same plain ground.
15. `Remove phones`, the one `delete` action of `R-03-111` in the app bar (added 2026-09-09 by the
    product owner, who called the three rows a terrible way of exposing the feature). It is the app
    bar action of `R-33-033`, `ChromeIconAction`: on Android a Material `IconButton` with its
    tooltip, on iOS a `CupertinoButton` at least `size.target.min` wide that fills the bar, per
    `R-33-076`. Its glyph is the `delete_outline` of the icon map of `R-32-401`, `size.icon.lg` in
    `color.fg.primary`; the hue of `treat.destructive` lives on the items it opens, not on the bar
    action, because the action itself removes nothing. It opens the platform's own choice surface:
    the Material menu on Android and the `CupertinoActionSheet` on iOS, drawn above, each with the
    three items of callouts 7 to 9 in that order; the sheet adds the `Cancel` button the platform
    groups apart, and the menu closes on an outside tap, as the component does. Picking an item
    closes the surface, then opens that item's confirmation of `R-33-074` over the list. The
    action is disabled at `opacity.disabled`, per `R-32-502`, whenever the list is not a live one
    the app can trust: while the list loads or failed to load, while offline or while another
    phone holds the computer (`R-31-14-04`), while a revoke is in flight and while an outcome is
    unknown (`R-31-14-12.1`). The bar never gains or loses the control, so nothing moves.
16. The health card, the `HEALTH` group on this phone's detail (added 2026-09-09 by the product
    owner, per `R-03-113` item 6, imported from `deex2/herdroid` inside the rules that already
    exist). It is one platform section of `R-33-073` with the upper-case header of `R-32-563`, and
    three information rows drawn exactly like the value rows of callout 5: `Last connected`, the
    age and the time of `last_seen`, `now` for the connected phone, else `3m ago · 22 Aug 17:02`;
    `App Lock`, `On` or `Off`, the App Lock setting of `R-03-090` this phone holds for itself;
    `Pairing`, `Paired 24 Aug 2026 09:14`, the pair time in the detail's full format. Under the
    group, the `How to revoke` caption in `type.caption` `color.fg.secondary` on the row text's
    edge names the revocation path: `Remove phones` on the phone list, and the `r` key in the Relay
    pane, as the inline key of `R-32-599`, which removes every phone. The card carries no key
    material and no second fingerprint, per `R-13-053` and `R-31-14-07`; the fingerprint keeps its
    one row below. The pair time and the last seen time live in the card and nowhere else on this
    screen, per `R-03-058`, so this phone's values group holds the platform and the fingerprint
    alone. Another phone's detail has no card: this phone knows only its own lock state, and the
    revocation path is the same for every phone.

## The key fingerprint in the detail screen

The detail screen shows the Device key fingerprint, so a person can match a row to a phone with
certainty. The Host computes it and sends it in the `device_list` entry, so this phone never holds a
key and never computes a digest. `docs/13-security-pairing.md` owns the format, in `R-13-040`. This
screen prints it as that document defines, in `type.mono.code`, and never prints a key.

The fingerprint carries a second job. It is what the app reconciles against after a revoke whose
outcome is unknown, because a name can be reused and a fingerprint cannot. `R-31-14-12` holds that.

## States

| State | Trigger | Screen shows |
| --- | --- | --- |
| Default | The computer is connected and reports two or more Devices. | The wireframe above, with the `Remove phones` action enabled. |
| Loading | The Device list has not returned. | Two skeleton rows after 150 ms. The `Remove phones` action is present and disabled while the list is unknown, because removing from an unknown list is a guess (amended 2026-09-09, per `R-03-111`: until then the remove rows were absent). |
| Empty | The computer reports only this Device. | One row, this phone, and the `Remove phones` action enabled. On its surface `Remove other phones` is disabled, because no other phone exists, and `Remove this phone` and `Remove every phone` stay enabled (amended 2026-09-09, per `R-03-105` and `R-03-111`: until then three rows, and before that `Remove every phone` was hidden here). |
| Error | The computer rejected the list request. | A block: `Could not read the phone list.` with `treat.error`, the raw error in `type.mono.code`, and `Try again`. The `Remove phones` action is disabled. |
| Error, no reply | The request was sent and neither `device_list` nor `error` arrived within 5 seconds. | The same block as `Error`: `Could not read the phone list.` with `treat.error`, the raw text `read the paired-device list: no device_list reply after 5 s` in `type.mono.code`, and `Try again`. The `Remove phones` action is disabled. Per `R-31-14-14`; decided 2026-09-03 by the product owner. |
| Host in use | The connection dropped while this screen was open, and the relay answered `host_in_use` on the retry, so this phone cannot reach the computer. | The last known list is shown, dimmed, with the header line `Another phone is using this computer. This list is from 14:02.` Every remove control is disabled, the `Remove phones` action and `Remove` on the detail screen alike, because a revoke must reach the computer to mean anything. |
| Offline | The connection dropped while this screen was open and there is no route to the relay. | The last known list is shown, dimmed, with the header line `Offline. This list is from 14:02.` Every remove control is disabled, the `Remove phones` action and `Remove` on the detail screen alike, because a revoke must reach the computer to mean anything. |
| Choosing | `Remove phones` was tapped. | The platform's choice surface of `R-03-111`, drawn above: the Material menu on Android, the `CupertinoActionSheet` on iOS, with `Remove this phone`, `Remove other phones` and `Remove every phone` in that order, the sheet with `Cancel` under them. `Remove other phones` is disabled when no other phone exists. An outside tap, or `Cancel`, closes the surface and changes nothing. Added 2026-09-09, per `R-03-111`. |
| Confirming, one | `Remove this phone` was picked on the surface, or `Remove` was tapped on the detail screen of the `This phone` row. | The confirmation of `R-30-005`: `Remove this phone from patrick-desk?` then `You will have to pair again to reach this computer.` The destructive verb is `Remove`, with `treat.destructive`. The other action cancels. `R-33-074` owns their titles, their order and their placement. |
| Confirming, another phone | `Remove` was tapped on the detail screen of a row that is not this phone. | The same dialog with that row's name: `Remove old-pixel from patrick-desk?` then `That phone will have to pair again to reach this computer.` The destructive verb is `Remove`. |
| Confirming, the others | `Remove other phones` was picked on the surface. | The confirmation of `R-30-005`: `Remove 2 other phones from patrick-desk?` then `They pair again. This phone keeps access.` The count is exact, and the noun follows it. The destructive verb is `Remove other phones`. Added 2026-09-09, per `R-03-105`. |
| Confirming, all | `Remove every phone` was picked on the surface. | The confirmation of `R-30-005`: `Remove every phone from patrick-desk?` then `This phone and 2 other phones lose access at once. Everyone pairs again. Removing every phone is the same as the r key in the Relay pane on your computer.` The count is exact, and the `r` is the inline key of `R-32-599`. When only this phone is paired the first sentence is `This phone loses access. You pair again.` (added 2026-09-09, per `R-03-105`), and the sentence about the key still ends the body (amended 2026-09-09, per `R-03-111`). The destructive verb is `Remove every phone`. |
| Removing | A revoke was confirmed and `revoke_result` has not arrived. | The wireframe `a revoke that has not answered yet`. The dialog closes at once, so nothing holds the person in a modal. The targeted row carries the spinner and `removing`; for the others case every row but this phone's does, and for the all case every row does. Every revoke control on the screen and on the detail screen is disabled, per `R-31-14-12`. |
| Removed, this phone | A revoke of this Device, or of every Device, was confirmed by `revoke_result`. | The app routes to `/hosts`, and that computer is gone with its pinned key, per `R-11-064`. A snackbar reads `Removed. Pair again from the Relay pane.` |
| Removed, another phone | A revoke of another Device was confirmed by `revoke_result`. | This screen stays. That row leaves the list, and a snackbar reads `Removed old-pixel.` No row reads `revoked`, because `R-13-053` deletes the entry. |
| Removed, the others | Every revoke of the `Remove other phones` sequence was confirmed by its own `revoke_result`. | This screen stays with this phone's row alone, `Remove other phones` disabled on the surface, and a snackbar reads `Removed 2 other phones.` Added 2026-09-09, per `R-03-105`. |
| Revoke refused | `revoke_result` arrived and reports a failure. | The row returns to its last read value. A block with `treat.error` names the failure and carries the raw text, per `R-30-803`. Nothing was removed, so the outcome is known and every revoke control re-enables at once. This is not the unknown-outcome state. In the others sequence the refused phone stops the sequence; the phones confirmed before it are gone and the rest keep their rows. |
| Outcome unknown | The link dropped, or the app was suspended, before `revoke_result` arrived. | The wireframe `a revoke whose outcome is unknown`, which is the `Outcome unknown` state of `R-30-518`. The list stays, dimmed. Every revoke control stays disabled. The only control is `Check now`. It is not an error state, so no `treat.error` and no raw text appear. In the others sequence the silent phone stops the sequence and is the phone `Check now` reconciles against. |
| Reconciling | `Check now` was tapped. | The block keeps its two sentences and shows the spinner `size.spinner` in place of the control. The screen resolves to `Removed, this phone`, `Removed, another phone`, or `Default` with a fresh list, and never to a queued second revoke. When the read cannot complete, `Outcome unknown` stays and the controls stay disabled, per `R-30-518`. |

## Navigation

- In: `Phones on this computer` on `15-appearance.md`.
- Out, a phone row: the Device detail screen, drawn in this file. It is pushed on this screen's
  own navigator, with no route change in the router (amended 2026-09-09, per `R-03-105`: until
  then a sheet that opened in place).
- Out, back from the detail screen: this screen.
- Out, a successful revoke of this Device or of every Device: `/hosts`, mockup `05-host-list.md`.
- Out, back: `/settings`.

## Rules

- **R-31-14-01** Every revoke this screen offers MUST ask for a confirmation first. That covers all
  four entry points: `Remove this phone`, `Remove other phones` and `Remove every phone` on the
  choice surface of `R-31-14-15`, and `Remove` on the detail screen (amended 2026-09-09, per
  `R-03-105`: the third action was added; and per `R-03-111`: the three actions moved from rows to
  the surface). The confirmation MUST be the destructive confirmation dialog of `R-32-547`, one of
  the two modal dialogs `R-30-005` permits (amended 2026-09-10 per `R-03-119`: the other is the
  terminal-state dialog of `docs/31-mockups/08-terminal.md` `R-31-08-27`; until then this sentence
  called the confirmation the one modal dialog the app is permitted).
  It MUST state the exact consequence and the exact count, and MUST name the phone whenever it
  removes one. This rule MUST NOT name an action order, a button position or an initial focus
  target: `R-33-074` owns the component, the action titles, the order and the focus, because the
  two platforms differ on all four.
- **R-31-14-02** The interface MUST call the destructive action `Remove every phone`, never
  `Refresh`. The word `refresh` means reload everywhere else in software, and here it destroys
  access. The body of the `Remove every phone` confirmation MUST end with the sentence that maps
  the action to the Host key, `Removing every phone is the same as the r key in the Relay pane on
  your computer.`, with the `r` as the inline key of `R-32-599`, and the list MUST NOT carry that
  sentence as a footnote (amended 2026-09-09, per `R-03-111`: until then a footnote strip under
  the remove rows).
- **R-31-14-03** A revoke MUST take effect on the computer, not only on the phone. The app MUST show
  the computer's confirmation before it reports success. The relay cannot perform a revoke, per
  `R-30-610`.
- **R-31-14-04** The app MUST NOT allow a revoke while offline or while another phone holds the
  computer.
- **R-31-14-05** The Device name MUST default to the device model, because `Pixel 8` beats a random
  identifier when a person decides what to remove. `docs/20-mobile-framework.md` owns the package
  that reads the model on both platforms. The default is not the current value: the current value is
  whatever this phone last sent in `device_info`, so `old-pixel` in the third row is a renamed phone
  and not a model. This screen MUST show that name and MUST NOT edit it, per `R-31-15-12`, which
  owns the one control that sets a name and the reason no phone renames another. That control is the
  row `This phone's name` on `/settings`, in `docs/31-mockups/15-appearance.md`.
- **R-31-14-06** This screen MUST NOT show a grant kind, an access level, or a read only marker.
  Every paired phone has full control, per `docs/03-product-decisions.md`. It shows a name, a
  platform, two times, a state and a fingerprint. Nothing else. Each of those six values comes from
  one field of the `device_list` entry, per `R-11-062`: `name`, `platform`, `paired_at`,
  `last_seen`, `connected` and `fingerprint`. A row draws the name and the two times, and it draws
  the state as `This phone` and `seen now` on the connected row, never as a bar (amended
  2026-09-09, per `R-03-105`). The row's semantics label adds the platform. The detail screen draws
  the platform and the fingerprint.
- **R-31-14-07** This screen MUST NOT print a routing handle, a pairing phrase or a key. The
  fingerprint is the only identity value it shows.
- **R-31-14-08** The detail screen MUST show exactly six values: the name, the pair time, the last
  seen time, the platform, the key fingerprint, and one `Remove` action. Each of those MUST come
  from the `device_list` entry for that row, per `R-11-062`. The screen MUST NOT show an
  operating-system version, because `device_list` carries none, and MUST NOT show a value this
  screen computes for itself. Each value MUST be the platform's own information row and `Remove`
  the platform's own destructive row, per `R-33-073` (amended 2026-09-09, per `R-03-105`: the
  detail was a sheet with a drawn value table). On this phone's own detail the health card of
  `R-31-14-16` adds one value that is not in `device_list`, the App Lock setting this phone holds
  for itself, and carries the pair time and the last seen time; each of the six values still
  shows exactly once on the screen, per `R-03-058` (amended 2026-09-09, per `R-03-113` item 6).
- **R-31-14-09** In every live state exactly one row MUST read as connected, and it MUST be the
  `This phone` row, because a second phone cannot be connected, per `R-03-040`. The connected row
  carries `seen now` and speaks `Connected`; no row carries a state bar (amended 2026-09-09, per
  `R-03-105`; until then the bar of `R-03-100` carried the state, and before it a glyph). In the
  `Host in use` and `Offline` states those marks are the last read value, so the list MUST be
  dimmed and MUST carry the timestamp of that read. In those two states the marks MUST NOT be
  presented as a live connection.
- **R-31-14-10** The platform MUST render as `Android` or `iOS`. Those are the only two values
  `platform` carries, per `R-11-131`. This screen MUST NOT print the raw lower case value, and MUST
  NOT print a marketing name.
- **R-31-14-11** A revoke of another phone MUST keep this screen and MUST remove that row from the
  list, because `R-13-053` deletes the entry. This screen MUST NOT carry a `revoked` row state, as
  no entry survives a revoke to carry one.
- **R-31-14-12** Every revoke this screen offers is a mutating, non-idempotent action, so a revoke
  whose acknowledgement never arrives MUST enter the `Outcome unknown` state of `R-30-518`. That
  rule owns why the outcome is common, why the state is not an error, why no one-tap retry is
  permitted, the two sentences and the `Check now` control. This rule owns only what this screen
  reconciles against, which `R-30-518` leaves to the owner of the entity.
  1. While a revoke is in flight the screen MUST show the `Removing` state and MUST disable every
     revoke control on the screen and on the detail screen: the `Remove phones` action of
     `R-31-14-15` and `Remove` on the detail (amended 2026-09-09, per `R-03-111`: until then the
     three remove rows). One in-flight revoke at a time is the only safe number, because a second
     one is aimed at a list the app can no longer trust.
  2. `Check now` MUST read a fresh `device_list` and MUST NOT re-send `revoke_device`.
  3. **A revoke of another phone reconciles on the key fingerprint, never on the name.** The app
     MUST record that phone's fingerprint from `R-11-062` before it sends. A name is not an
     identity: a person can revoke `old-pixel` and pair a phone with the same name a minute later,
     and a check by name would then read the new phone as the old one. The revoke landed when that
     fingerprint is absent from the fresh list, and it did not land when the same fingerprint is
     still present.
  4. **A revoke of this phone, and a revoke of every phone, reconcile on the reconnection itself.**
     Both revoke this phone, so the app may have lost the access it needs to read any list. The
     reconnection is the check. The computer accepted it, so nothing was revoked and the app reads a
     fresh list. The computer closed with the revoke close code `4004`, so the revoke landed and the
     screen resolves to `Removed, this phone`. `R-30-518` already states why a repeat of
     `Remove every phone` is unsafe, so this file does not restate it.
  5. After reconciliation the screen MUST show a true list and MUST require a fresh confirmation
     before any further revoke. The app MUST NOT queue the unfinished action and MUST NOT replay it.
  6. A `revoke_result` that reports a **failure** is a known outcome and not this state. Nothing was
     removed, so `Revoke refused` re-enables the controls at once and a further attempt is safe.
  7. `Try again` on the `Error` state stays. That state is a failed **read** of the phone list, and
     `R-30-518` exempts a read from the no-retry requirement.
  8. `Remove other phones` is a sequence of single revokes, one per other phone, each awaited
     before the next is sent, so point 1 holds for it (added 2026-09-09, per `R-03-105`). The
     phone whose revoke was refused or never answered stops the sequence and is the one phone
     point 3 or point 6 applies to; the app MUST NOT send the next revoke after it, MUST keep the
     phones already confirmed removed off the list, and MUST NOT replay the rest.
- **R-31-14-13** This screen MUST cite the platform divergences and MUST NOT restate them. There are
  four, and each belongs to `docs/33-platform-chrome.md`. `R-33-070` owns the back control, so this
  file MUST NOT name a back glyph. `R-33-071` owns what the bottom navigation does on this pushed
  route and on the detail screen, so the drawings omit it. `R-33-072` owns the trailing affordance:
  a phone row pushes the detail screen, so it MUST be the platform's push row, which keeps the
  chevron on iOS and carries none on Android, and it MUST NOT carry a labelled control (amended
  2026-09-09, per `R-03-105`: until then the row opened a sheet and carried `Details`). The control
  map of `R-33-033` owns the app bar action and the choice surface of `R-31-14-15`: this file
  names the action, its glyph and its three items, and it MUST NOT name the menu's or the sheet's
  surface, corner, shadow, item height or ink (amended 2026-09-09, per `R-03-111`).
- **R-31-14-14** A `device_list_request` that gets no reply MUST NOT hold the `Loading` state open.
  The product owner found this live on 2026-09-03: a Host that never answered left the screen on
  its skeleton with no way out.
  1. The app MUST wait at most 5 seconds for `device_list` or `error` after it sends the request.
     The value is one named constant beside the request, and it is the same bound the terminal
     attach and the composer already use, so the app holds one reply timeout, not three.
  2. When nothing arrives in time the screen MUST enter the `Error, no reply` state of the states
     table: the `Error` block of `R-30-803` with the raw text `read the paired-device list: no
     device_list reply after 5 s`, and `Try again`. A read is idempotent, so `Try again` sends a
     fresh request, per `R-30-518`'s own exemption, and the timeout itself MUST NOT resend.
  3. The same bound applies to `revoke_device`. A revoke that is never acknowledged is the
     `Outcome unknown` state of `R-31-14-12`, exactly as a dropped link is, and it MUST NOT be
     resent.
  4. The reply is matched by its message type on this phone's one connection, because the
     decoded message stream carries no `corr`. That is safe while one read and at most one revoke
     are in flight, which `R-31-14-12.1` already guarantees.
- **R-31-14-15** The three remove actions MUST reach a person through one `delete` action in the
  app bar, spoken `Remove phones`, and MUST NOT be rows of the list (added 2026-09-09, per
  `R-03-111`, which amends `R-03-105`).
  1. The action MUST be the app bar action of `R-33-033` with the `delete_outline` glyph of the
     icon map of `R-32-401`, in the bar's normal ink, on both platforms. The hue of
     `treat.destructive` MUST live on the items alone, because the action itself removes nothing.
  2. The action MUST open the platform's own choice surface: a Material menu on Android and a
     `CupertinoActionSheet` on iOS, with `Remove this phone`, `Remove other phones` and
     `Remove every phone` in that order, each item drawn per callout 7, and, on iOS, the `Cancel`
     button the component groups apart. This file MUST NOT name the surface's own values.
  3. Picking an item MUST close the surface first, then open that item's confirmation of
     `R-31-14-01` over the list. The surface MUST NOT open a second surface.
  4. `Remove other phones` MUST be disabled on the surface while no other phone exists, and
     `Remove this phone` while this phone is not in the list. A disabled item keeps its place.
  5. The action MUST be disabled, at `opacity.disabled` per `R-32-502`, while the list is unknown
     (`Loading`, `Error`, `Error, no reply`), while `R-31-14-04` forbids a revoke, and while
     `R-31-14-12.1` holds a revoke in flight or an outcome unknown. It MUST stay in the bar in every
     state, so the bar never gains or loses a control.
- **R-31-14-16** This phone's own detail MUST carry a health card, one `HEALTH` group of `R-33-073`
  above the values group, and another phone's detail MUST NOT (added 2026-09-09, per `R-03-113`
  item 6).
  1. The card MUST hold exactly three information rows, in this order: `Last connected`, the age
     and the time of `last_seen` (`now` for the connected phone, else `3m ago · 22 Aug 17:02`);
     `App Lock`, `On` or `Off`, read from the App Lock setting of `R-03-090` that this phone
     holds; and `Pairing`, `Paired 24 Aug 2026 09:14`, the pair time in the detail's full format.
  2. Under the card, one caption in `type.caption` `color.fg.secondary` MUST name the revocation
     path: the `Remove phones` action of `R-31-14-15` and the `r` key in the Relay pane, the `r`
     as the inline key of `R-32-599`, and MUST say that the key removes every phone.
  3. The card MUST NOT show key material, a second fingerprint, a routing handle or a pairing
     phrase, per `R-13-053` and `R-31-14-07`. The fingerprint keeps its one row in the values
     group.
  4. The pair time and the last seen time MUST show once on the screen, per `R-03-058`: in the
     card on this phone's detail, in the values group on another phone's detail.

## Accessibility

- Touch target: the back control, the `Remove phones` action, every row, `Check now` and each item
  of the choice surface meet the minimum target of `R-30-290` and `R-30-740`, at the sizes the
  platform tile, the row of `R-32-515`, the app bar action of `R-33-076` and the platform's own
  menu item and sheet action fix. A disabled action or item keeps its size and its place, so
  nothing on the screen moves when the `Removing` state ends (amended 2026-09-09, per `R-03-105`
  and `R-03-111`).
- Contrast: the name uses `color.fg.primary` and the subtitle and `This phone` use
  `color.fg.secondary`, on the row surface, both passing rows in `R-32-150`, per `R-30-720`. The
  connected state is carried in words, per `R-30-141`, and by no hue (amended 2026-09-09, per
  `R-03-105`: the state bar is gone). The Android menu items and the `Remove` row use the glyph of
  `treat.destructive`, which keeps the red in the icon alone and never in the text or a bar, per
  `R-30-143` and `R-32-527` (amended 2026-09-09 per `R-03-058`); the iOS sheet's destructive ink
  is the platform's own, and the `destructive` announcement carries the risk in words there.
- Screen reader: the connected row MUST carry `Connected` and every other row `Not connected`, per
  `R-30-716`. In a stale list it MUST carry `Last connected` instead, so the row never speaks a
  connection that has ended, per `R-31-14-09`. Each row MUST be one semantics node whose label
  reads the name, `this phone` when it applies, the connection word, the platform, the pair time,
  then the last seen time. The platform is in the label and not in the drawing, because it tells
  two similar names apart when a person cannot compare the rows by sight. It comes from
  `device_list`, per `R-31-14-06`. The app bar action MUST speak `Remove phones` and nothing else,
  per `R-32-505`. Each item of the choice surface and the `Remove` row MUST announce `destructive`
  in its label, so the risk is spoken and not only coloured, per `R-30-141`. The confirmation
  dialog MUST announce its title, its whole body and its exact count when it opens, because the
  body is the entire warning; the `r` key in the `Remove every phone` body is spoken as the plain
  letter, per `R-32-599`. The detail screen MUST speak the name first, in its app bar, then each
  value as a label and value pair, so `Platform, Android` and `App Lock, On` are one node each and
  not two; the `How to revoke` caption is spoken as its plain sentence. In the `Removing` state the
  targeted row MUST expose `removing` in its label, and the disabled action and each disabled item
  MUST expose `disabled`, so a person who cannot see the dimming still learns why the control does
  nothing. The `Outcome unknown` block MUST be announced once when it appears, through the
  mechanism `R-30-742` names, and MUST NOT be a live region. `Check now` MUST NOT announce
  `destructive`, because it changes nothing on the computer.
- Focus order: per `R-30-719`, the back control, the title, the `Remove phones` action, the
  `Outcome unknown` block when present, then each row top to bottom. The choice surface traps the
  focus while it is open, `Remove this phone`, `Remove other phones`, `Remove every phone`, then
  `Cancel` on iOS, and returns it to the action that opened it (amended 2026-09-09, per
  `R-03-111`: until then the three rows and the footnote followed the list). The detail screen is a
  pushed route, so its back control returns the focus to the row that pushed it, per the
  platform's own navigation (amended 2026-09-09, per `R-03-105`: the sheet trapped the focus and
  returned it to `Details`). Its own order is the back control, the name, the health card's three
  rows and its caption on this phone's detail, the values, the rename caption on this phone's
  detail, then `Remove`. A confirmation dialog traps the focus and returns it to the control that
  opened it. This file MUST NOT name that dialog's initial focus target, because `R-33-074` gives
  it to the platform component and forbids a preferred action where a destructive action is
  present.

## Open questions

None.

## Retired rules

This row retires dead **prose**, not a rule id. `R-31-14-05` is still live and keeps its number.
Only the editable half of its old text is dead.

| Subject | Disposition |
| --- | --- |
| The editable name requirement in `R-31-14-05` | Retired. It required the Device name to be editable from the detail sheet, on any row. No rename message exists in `docs/11-relay-protocol.md` and none is planned, so no phone can rename another, per `R-31-15-12`. The live half of `R-31-14-05` keeps the default-name requirement and names the row that replaces the edit. |
| The state bar, the `Details` control, the `THIS PHONE` chip and the two-action set | Retired 2026-09-09, per `R-03-105`. Callouts 2, 3, 5, 6 and 7 and rules `R-31-14-06`, `R-31-14-09` and `R-31-14-13` carried them. The rows are the platform's own, the connected phone is marked by `This phone` and `seen now`, and the row pushes the detail. |
| The three remove rows and the footnote strip | Retired 2026-09-09, per `R-03-111`. Callouts 7 to 10, the `Empty`, `Loading` and `Error` rows of the states table and rules `R-31-14-01`, `R-31-14-02` and `R-31-14-12.1` carried them as `ChromeListRow.destructive` rows in their own section, with the sentence about the `r` key in a footnote strip under them. The three actions are now the items of the choice surface behind the `Remove phones` action of `R-31-14-15`, and the sentence ends the `Remove every phone` confirmation body. |
| The ground grid and the paper blocks | Retired 2026-09-09, per `R-03-107` as amended. Callout 14 put the ground grid of `R-32-332` under both screens, each section on a paper block. Both screens paint plain `color.bg.base`. |

## Sources

- `docs/32-design-language.md` - the app bar `R-32-510`, the list row `R-32-515`, the destructive
  action `R-32-527`, the modal dialog `R-32-547`, the size set `R-32-350` with `size.spinner`, the
  one-hue rest state `R-32-130`, the contrast table `R-32-150`, the icon map `R-32-401` with the
  `Remove phones` row, the upper-case group header `R-32-563`, the inline key `R-32-599` and the
  ground `R-32-332`.
- `docs/30-ux-spec.md` - the destructive treatment `R-30-143`, the modal dialog rule `R-30-005`,
  the `Outcome unknown` state `R-30-518`, the error block `R-30-803` and its one retry `R-30-804`,
  the announcement mechanism `R-30-742`, the revoke convergence rule `R-30-610`, and the per-Host
  route rule `R-30-946`.
- `docs/13-security-pairing.md` - the paired Device record `R-13-049`, the single revoke `R-13-053`
  which deletes the entry, the revoke of every Device `R-13-056`, and the fingerprint format
  `R-13-040`.
- `docs/03-product-decisions.md` - full terminal control for every paired phone, one active phone
  per computer `R-03-040`, one mark per fact `R-03-058`, the App Lock setting `R-03-090`, the
  platform list of `R-03-105`, the ground of `R-03-107`, the list end of `R-03-109`, the `delete`
  action and its choice surface `R-03-111`, and the health card, item 6 of `R-03-113`.
- `docs/20-mobile-framework.md` - the package that reads the device model, which is the default
  Device name.
- `docs/11-relay-protocol.md` - the `device_list` payload and `R-11-062`, which carry every value
  this screen shows; `revoke_device` and `revoke_result` with `R-11-063` and `R-11-064`, which carry
  the computer's own confirmation of a revoke; `device_info` and `R-11-131`, which carry the name
  and the platform; and the close code `4004` for a revoke and `4006` for `host_in_use`.
- `docs/33-platform-chrome.md` - the control map `R-33-033`, the back control `R-33-070`, the
  primary navigation on a pushed route `R-33-071`, the row affordance `R-33-072`, the platform list
  `R-33-073`, the confirmation dialog `R-33-074`, and the control inside the iOS navigation bar
  `R-33-076`.
- `docs/31-mockups/15-appearance.md` - the row `This phone's name` on `/settings`, `R-31-15-12`, the
  one place a person sets this phone's own name.
- The `herdr-scheduled` plugin, `posix/ui.sh` and `windows/ui.ps1` - the reference plugin terminal
  UI that the Relay pane copies.
