# 15 - Settings: appearance, haptics, this phone's name and the relay address

| Field | Value |
| --- | --- |
| Route | `/settings` |
| Surface | Device, Android and iOS |
| Spec | `docs/30-ux-spec.md` |

This screen owns the relay address, because the address has no route of its own, per `R-30-025`. It
also owns this phone's own name, because no message renames a phone and a phone may set only its
own, per `R-31-15-12`. Every value here is stored on the phone, so the whole screen reads and writes
with no connection. The name is the only one that later leaves the phone.

## Wireframe

```text
+--------------------------------------+
| Settings                             |
+--------------------------------------+
| RELAY                                |
| Relay address                   Edit |
|   https://relay.example.com          |
+--------------------------------------+
| APPEARANCE                           |
| Theme                                |
| +----------------------------------+ |
| | [ System ]   Light      Dark     | |
| +----------------------------------+ |
| The terminal palette follows this    |
| setting too.                         |
| Status colours                     > |
| Terminal text size             13 pt |
| o------o------o--(o)--o------o-----o |
| +----------------------------------+ |
| | $ dotnet test                    | |
| | Passed!  Failed: 0, Passed: 412  | |
| +----------------------------------+ |
| Terminal text size is separate from  |
| your phone's text size.              |
+--------------------------------------+
| FEEL                                 |
| Haptics                        [on ] |
| Key press haptics              [on ] |
+--------------------------------------+
| THIS PHONE                           |
| This phone's name               Edit |
|   Pixel 8                            |
+--------------------------------------+
| SECURITY                             |
| App Lock                       [off] |
+--------------------------------------+
| Alerts                             > |
+--------------------------------------+
| ON THE CONNECTED COMPUTER            |
| patrick-desk                         |
| Phones on this computer            > |
| Connection                         > |
+--------------------------------------+
| About                              > |
+--------------------------------------+
|  Agents     Notifications   Settings |
+--------------------------------------+
```

## Wireframe, first run, no relay address yet

```text
+--------------------------------------+
| Settings                             |
+--------------------------------------+
| RELAY                                |
| Relay address                      > |
|   Not set. Pair a computer to set    |
|   it.                                |
+--------------------------------------+
| APPEARANCE                           |
| Theme                                |
| +----------------------------------+ |
| | [ System ]   Light      Dark     | |
| +----------------------------------+ |
| The terminal palette follows this    |
| setting too.                         |
| Terminal text size             13 pt |
| o------o------o--(o)--o------o-----o |
+--------------------------------------+
```

## Wireframe, the relay address sheet

```text
+--------------------------------------+
|             ------                   |
| Relay address                        |
|                                      |
| [ https://relay.example.com        ] |
|                                      |
| A scheme, a host, and an optional    |
| port. No path.                       |
|                                      |
| +----------------------------------+ |
| |              Change              | |
| +----------------------------------+ |
|                                      |
|                Cancel                |
+--------------------------------------+
```

## Wireframe, the destructive confirmation

```text
+--------------------------------------+
|                                      |
|  Change the relay address?           |
|                                      |
|  This closes the connection,         |
|  forgets which computers are         |
|  reachable, and forgets the keys     |
|  that prove they are the same        |
|  computers. You will pair every      |
|  computer again.                     |
|                                      |
|  cancelling:   Cancel                |
|  destructive:  Change and unpair     |
|                                      |
+--------------------------------------+
```

The frame names each action by its **role** and draws no order. `R-33-074` fixes the component, the
titles and the placement on each platform, and it forbids this file from naming a position, an
action order or an initial focus target.

## Wireframe, a relay address that does not use HTTPS

```text
+--------------------------------------+
| Settings                             |
+--------------------------------------+
| ! This relay connection does not     |
|   use HTTPS. Terminal content        |
|   remains end-to-end encrypted.      |
|   Use it only on a trusted local     |
|   network.                           |
+--------------------------------------+
| RELAY                                |
| Relay address                   Edit |
|   http://192.168.1.20:8080           |
+--------------------------------------+
```

## Wireframe, the theme control

```text
+--------------------------------------+
| APPEARANCE                           |
| Theme                                |
| +----------------------------------+ |
| | [ System ]   Light      Dark     | |
| +----------------------------------+ |
| The terminal palette follows this    |
| setting too.                         |
| On Android the app colour follows    |
| your wallpaper. The terminal keeps   |
| its own.                             |
| Terminal text size                   |
+--------------------------------------+
```

## Wireframe, this phone's name sheet

```text
+--------------------------------------+
|             ------                   |
| This phone's name                    |
|                                      |
| [ Pixel 8                          ] |
|                                      |
| The name your computers show for     |
| this phone. patrick-desk shows it    |
| after the next connection.           |
|                                      |
| +----------------------------------+ |
| |               Save               | |
| +----------------------------------+ |
|                                      |
|                Cancel                |
+--------------------------------------+
```

## Callouts

1. Title `Settings`. Token `type.title`, in the app bar of `R-32-510`. This is a bottom navigation
   destination, so it has no back chevron.
2. `RELAY` group header. Token `type.micro`, upper case, `color.fg.secondary`, row height
   `size.header`. It sits first, because a person who cannot connect looks here before anything
   else.
3. `Relay address` row. The two line list row of `R-32-515`. The address sits under the label in
   `type.mono.code`, wrapped rather than truncated, because half an address is worse than two lines.
   A tap opens the sheet. The row carries **no chevron**. It opens a sheet and not the next level,
   so `R-33-072` replaces the chevron with the labelled control `Edit`. The whole row is that
   control's target, so the row is still one tap and one semantics node. On iOS the row is the
   platform tile of `R-33-073`, whose subtitle slot is one line, so a very long origin ellipsizes
   there and the full origin is read in the `Edit` sheet; the wrapped, never truncated line reaches
   the Android row (added 2026-09-08). `R-31-15-07` keeps its Android meaning unchanged.
4. The empty state second line, `Not set. Pair a computer to set it.` in `type.caption`. A tap
   routes to `/pair/scan` instead of opening the sheet, per `R-30-920` and `R-30-921`. This state
   keeps the chevron, and callout 3 drops it, because `R-33-072` ties the affordance to the
   destination and the two states have different destinations. Here the row opens the next level, so
   the chevron tells the truth.
5. The sheet. The bottom sheet of `R-32-545`, with one text field of `R-32-530`, one hint, one
   filled button of `R-32-525` and one cancel row. The heading `Relay address` is `type.heading`,
   written as here, never upper-cased (`R-32-213`); the cancel row is `R-32-545`'s: centred,
   `type.body.strong` in `color.fg.secondary`. The field sits at the sheet's own `space.4` inset,
   on the heading's left edge, and the sheet lifts above the keyboard once, as a whole, so the
   actions rise with the field (amended 2026-09-08 by the product owner: the field had its own
   lift as well, so the sheet rose twice, and its heading and cancel row were upper-cased). The
   field uses the URL keyboard with autocorrect and autocapitalisation off.
6. The confirmation dialog. The destructive confirmation dialog of `R-32-547`, one of the two modal
   dialogs `R-30-005` permits (amended 2026-09-10 per `R-03-119`: the other is the terminal-state
   dialog of `docs/31-mockups/08-terminal.md` `R-31-08-27`; until then this callout called it the
   one modal dialog the app is permitted). This file
   fixes five things and no more, which is what `R-33-074` allows: the title and the body, which are
   `R-30-925`'s exact text; the destructive verb `Change and unpair`; that it is the destructive
   action; and that the second action cancels. `R-33-074` owns the rest, which is the component, the
   cancelling title, the ordering and whether any action is preferred. It titles the cancelling
   action `Cancel` on iOS. This file MUST NOT name a position, an action order or an initial focus
   target.
7. The insecure strip. The strip of `R-32-561`, with `treat.warning`. It sits above every group, is
   not dismissible, and never times out, per `R-30-923`.
8. `Theme`. The segmented control of `R-32-520` sits inline under the label, always visible,
   with exactly three segments in this order:
   `System`, `Light`, `Dark`. Amended 2026-09-09 by the product owner, per `R-03-059`: the
   control is the platform's own, `SegmentedButton` on Android and
   `CupertinoSlidingSegmentedControl` on iOS, per the control map of
   `docs/33-platform-chrome.md` `R-33-033`. It fills the block's width, so the three segments
   share it equally. Its height, type, fill and boundary come from the platform theme in
   `app/lib/app.dart`, never from the screen. On iOS the component keeps its own height, thumb
   and track, lower than `size.target.min`, and the app MUST NOT raise it, per the `R-33-076`
   precedent. The platform marks the selected segment its own way, and the semantics state
   `selected` comes with it. The product owner decided this on 2026-09-03: a hidden control did
   not read as clickable, so the row has no expand step, no expansion control and no trailing
   value word. The label `Theme` is not a list row of its own: it is `type.body.strong` at the
   `space.4` screen inset, `space.2` above the control, with `space.2` between the control and
   its line and `space.4` above and below the whole block, which is the text inset of the
   two-line rows beside it (amended 2026-09-08 by the product owner: a full list row with a
   divider cut the label from its control and left 24 px under `Theme` while `Relay address`
   sat tight). `System`
   is selected on first run and after every reinstall, per
   `R-30-112` and `R-32-010`. A tap changes the theme in place, with no route change and no restart,
   per `R-32-013`. One line under the control reads `The terminal palette follows this setting
   too.`, because the terminal is the content and a person MUST NOT have to guess whether it moves
   with the chrome. `R-32-140` holds the two slot sets and `R-32-015` holds what happens to a grid
   that is already painted. A second line reads `On Android the app colour follows your wallpaper.
   The terminal keeps its own.`, because the chrome colour comes from the operating system on that
   platform and a person would otherwise read this control as owning it. `R-33-024` holds that
   colour, so the second line is present on Android and absent on iOS, where the chrome palette is
   fixed. The second line is also absent when the operating system returns no wallpaper scheme,
   because the person turned that colour off in the system settings, per `R-33-031`. A line that
   names a wallpaper the app is not reading would be a lie. Neither line offers a choice: this
   control MUST NOT gain a palette picker, per `R-32-014`.
9. `Terminal text size`. The slider of callout 10 sits inline under the title row, always
   visible. The product owner decided this on 2026-09-03, with the same reason as callout 8. Like
   `Theme`, this row has no expand step, no expansion control and no chevron, and its title row,
   its slider, its preview and its line take the block of callout 8, with `space.2` between each
   of the four.
10. Slider (amended 2026-09-09 by the product owner, per `R-03-110`, who called the `aA` glyph,
    two buttons, a spacer and the value a weird layout). The title row is the label
    `Terminal text size` in `type.body.strong` with the current value at its trailing edge on
    the same baseline, in `type.caption` `color.fg.secondary`, written `13 pt`, never
    upper-cased. Under it, the platform's own discrete slider fills the block's width: `Slider`
    on Android and `CupertinoSlider` on iOS, per `R-33-033`, in the component's own shape, size
    and colours from the platform theme in `app/lib/app.dart`. Its stops are exactly the
    permitted sizes of `docs/21-terminal-rendering.md` `R-21-010`, whose list lives in
    `R-32-208`, one division between each pair of neighbours, so the thumb rests on a size and
    never between two; the line height is `R-32-209`. The slider draws no value bubble: the
    title row carries the value. No `aA` glyph, no `-`/`+` buttons, and no spoken names for
    them: the slider is one semantics node that speaks `Terminal text size, 13 points`, with the
    platform's own increase and decrease actions. One line under the preview reads
    `Terminal text size is separate from your phone's text size.` in `type.caption`.
    `R-31-15-02` requires that line, because the phone's own text scale moves every other row on
    this screen and a person will read this slider as a second way to do the same thing.
    `R-30-702` owns why the terminal grid is exempt.
11. Live preview. The terminal preview of section 7.22 of `docs/32-design-language.md`: two real
    terminal rows that repaint at the chosen size, in `color.term.bg` with `color.term.fg`. It uses
    real ANSI text, so the effect is honest, and it follows the theme with the rest of the screen.
12. `Haptics`. The switch row of `R-32-522`. Default on. It turns every haptic off in one place,
    which is what a person wants at 02:00.
13. `Key press haptics`. The switch row of `R-32-522`. Default on. Disabled and forced off while
    callout 12 is off.
14. `THIS PHONE` group header. Token `type.micro`, upper case, `color.fg.secondary`, row height
    `size.header`. It sits under `FEEL` and above the computer rows for three reasons: `R-31-15-06`
    keeps `RELAY` first, a name is set once and belongs below the two groups a person adjusts often,
    and `Phones on this computer` is two rows below, which is the one list that shows the name.
15. `This phone's name` row. The two line list row of `R-32-515`. The row shows the stored name
    under the label. When no name is stored, the row shows the device model of `R-31-14-05`,
    per `R-31-15-15`. The product owner decided this on 2026-09-03: the row never shows a
    placeholder. A tap opens the name sheet. This is the only place the name is set, per
    `R-31-15-12`. Like callout 3, this row opens a sheet, so `R-33-072` gives it the labelled
    control `Edit` and no chevron.
16. The name sheet. The bottom sheet of `R-32-545`, built exactly like callout 5: one text field of
    `R-32-530`, a hint, one filled button of `R-32-525` labelled `Save`, and one cancel row, with
    the heading `This phone's name` and the same `space.4` gap between the hint and the button
    that callout 5 draws (amended 2026-09-08 by the product owner: the button sat flush under
    the hint here and `space.4` under it there). The field keeps its focus while the person
    types. The field uses the plain text keyboard with autocorrect off, because a device name is
    a label and not prose. The hint names the connected computer and states that the computer
    shows the new name after the next connection, per `R-31-15-14`. There is no confirmation,
    because nothing is destroyed.
17. `SECURITY` group header. Token `type.micro`, upper case, `color.fg.secondary`, row height
    `size.header`, drawn exactly like callout 14. It sits under `THIS PHONE` and above `Alerts`,
    because a security control belongs near where a person has just set up their phone, not
    buried under the connected computer's own rows.
18. `App Lock` row. The switch row of `R-32-522`, drawn exactly like callouts 12 and 13. Default
    off, per `R-03-090`. It turns the biometric or passcode gate on opening the app on or off,
    per `docs/13-security-pairing.md` R-13-073 and `docs/22-platform-integration.md` R-22-013.
    Disabled, with the message of `R-31-15-18`, when the phone reports no screen lock.
19. `Alerts` row, to `12-notifications.md`. It is labelled `Alerts`, because nothing in this
    product is pushed. It carries no group header of its own: it follows `SECURITY` with the group
    gap alone, per `R-31-15-19`.
20. `ON THE CONNECTED COMPUTER` group header, then the connected computer's name as the primary
    line of a row of `R-32-515`, in `type.body.strong` (amended 2026-09-08: it read `type.body`,
    which no row of section 7.4 draws; the name is the platform tile of `R-33-073` like every
    other row here), then the rows to `14-devices.md` and `13-connection.md`. The name sits once,
    above both rows, so neither row can read as covering every saved computer. The app is
    connected to at most one computer, per `R-03-043`, and both rows act on that one, per
    `R-31-15-16`.
21. `About` row, to `19-about.md`. That file owns what the screen shows. Like `Alerts`, it carries
    no group header, per `R-31-15-19`.
22. Bottom navigation with `Settings` active. The three destinations of `R-32-562`, which
    `R-33-035` fixes in the same order with the same labels on both platforms. The control that
    holds them is full width on both, per the native control map `R-33-033`: a `NavigationBar` on
    Android and a `CupertinoTabBar` on iOS. The drawing is platform-neutral. This
    destination carries the navigation control alone and no create control, because nothing on a
    settings screen is a space, a tab or a pane.
23. The list composition. Every group on this screen is a platform list, and the two platforms
    compose one differently. `R-33-073` owns that: `CupertinoListSection` and `CupertinoListTile`
    on iOS, and the Material settings list with a native single-choice screen or dialog on
    Android. Every wireframe here is platform-neutral and draws the row **content**, which
    `docs/32-design-language.md` owns. This file MUST NOT name the composing widget. On iOS the
    platform list draws the one separator between two rows, so no row on this screen draws the
    divider of the section 7.4 table there; on Android every row but the last one in its group
    draws it (amended 2026-09-08: the row hairline sat under the platform separator and the two
    read as one 2 px line). The group header and the row text share one left edge on both
    platforms: the upper-case tier indent and the row inset are both `space.4`, per `R-32-563`.
    Every row of this screen is the platform tile of `R-33-073`, on both platforms (amended
    2026-09-08: only the outer section was native on iOS, and each row inside it was the
    Android row of section 7.4). The two inline blocks of `APPEARANCE`, `Theme` and
    `Terminal text size` (callouts 8 and 9), are not rows and take no tile, per `R-33-073`
    item 2; on iOS the tile keeps the platform's own row height and inset, so the row values of
    section 7.4 reach Android only, per `R-33-073`.
24. `Status colours` row, under `Theme`, to `20-status-legend.md` (added 2026-09-09 by the product
    owner, per `R-03-106`: he saw blue and green bars and had no idea what was what). That file
    owns what the page shows. It is one platform row of `R-33-073` inside the `APPEARANCE` group,
    between the two inline blocks of callouts 8 and 9: it sits under `Theme` because the line of
    callout 8 says the terminal palette follows the theme, and the status hues follow it too. It
    opens the next level and keeps the chevron, per `R-33-072`. On Android it draws the divider of
    section 7.4 under itself, like every row that is not the last in its group.
25. Ground (added 2026-09-09, per `R-03-107`; amended 2026-09-09, per `R-03-107` as amended).
    The body paints plain `color.bg.base` with no ground grid and no paper block, because this
    screen has content. Each group of callout 23 sits directly on that ground under its `space.6`
    gap, per `R-30-231`, and the list ends at the `space.4` bottom inset. The insecure strip of
    callout 7 stays an opaque `color.bg.raised` strip flush under the app bar. The ground grid of
    `docs/32-design-language.md` `R-32-332` is for the hero screens and an empty state only.

## States

| State | Trigger | Screen shows |
| --- | --- | --- |
| Default | An origin is stored. | The first wireframe. |
| Relay empty, first run | No origin is stored. | The second wireframe. The `ON THE CONNECTED COMPUTER` group is hidden, header, name line and both rows, because nothing is paired and nothing is connected. |
| Relay editing | The `Relay address` row was tapped with an origin stored. | The sheet wireframe, prefilled with the current origin. |
| Relay confirming | `Change` was pressed with a valid origin that differs from the stored one. | The confirmation wireframe. |
| Relay unchanged | `Change` was pressed with the same origin. | The sheet closes. Nothing else happens, and no confirmation appears, because nothing is destroyed. |
| Relay invalid | The typed origin is not an origin, or carries a path. Code `relay_origin_invalid`. | The sheet keeps the text, shows `That is not a relay address. Use the form https://relay.example.com.` with `treat.error`, and `Change` stays disabled. |
| Relay insecure, rejected | The typed origin is cleartext and outside the permitted list. Code `relay_origin_insecure`. | The sheet shows `A relay address must start with https, unless the computer is on your own network.` with `treat.error`. `Change` stays disabled. |
| Relay insecure, permitted | The stored origin is a loopback or private network cleartext origin. | The fifth wireframe, with the non dismissible strip of `R-30-923`. |
| Name editing | The `This phone's name` row was tapped with a computer connected. | The name sheet wireframe, prefilled with the current name. The hint names the connected computer. |
| Name editing, nothing connected | The same row was tapped with no computer connected. | The same sheet, and the hint reads `The next computer you connect sees this name.` instead of naming one. |
| Name unchanged | `Save` was pressed with the same name. | The sheet closes. Nothing is written, no snackbar appears and the connection is untouched, because nothing changed. |
| Name too long | The typed name passes the `device_name` limit that the `device_info` field table of `docs/11-relay-protocol.md` fixes. | The sheet keeps the text, shows `That name is too long. Shorten it.` with `treat.error`, and `Save` stays disabled. The count is in UTF-8 bytes, per `R-31-15-13`. |
| Name empty | The typed name trims to nothing. | `Save` stays disabled and no error text appears, because an empty field is not yet a mistake. `device_name` is a required field, per `R-11-131`. |
| Name saved | `Save` was pressed with a different valid name, and a computer is connected. | The sheet closes, the row shows the new name at once, and a snackbar reads `Saved. patrick-desk shows it after the next connection.` |
| Name saved, nothing connected | The same, with no computer connected. | The sheet closes and the row shows the new name. The snackbar reads `Saved.` and names no computer, because there is none to name. |
| Loading | Not applicable for a preference. Every value is local and reads instantly. | - |
| Error | Writing a preference to local storage failed. | A snackbar: `Could not save that setting.` The control returns to its previous value, so the screen never lies about what is stored. |
| Offline | The phone has no network. | Every appearance and feel control stays usable, because all of them are local. The relay row and the name row still open and still save. The `ON THE CONNECTED COMPUTER` group stays while the app still holds that computer, because `13-connection.md` is where a person reads a down link. The confirmation body gains one line, `The connection is already down.` |
| Nothing connected | The app holds no computer. It follows a deliberate `Disconnect`, per `R-31-13-14`, or the first run, or a `Forget` of the last computer. | The `ON THE CONNECTED COMPUTER` group is hidden, because a per-Host route needs a connected computer, per `R-30-946`. Every other group stays, because every other value is local. This is a normal state and not an error, per `R-03-043`, so no strip and no error text appears. |
| No screen lock | The phone reports no PIN, pattern, password or biometric enrolled (`local_auth.isDeviceSupported()` is `false`). | The `App Lock` row is disabled, in `color.fg.disabled`, per `R-30-120`, with one line under it: `This phone has no screen lock. Add a passcode or fingerprint in your phone's settings, then come back.` The switch cannot be turned on. |
| Large text | The system text scale is above 1.3. | Every row grows and the label wraps to two lines. The slider keeps the platform component's own thumb target and never shrinks. See `R-30-701`. |

## Navigation

- In: the `Settings` destination in the bottom navigation.
- Out, `Alerts`: `12-notifications.md`.
- Out, `Phones on this computer`: `14-devices.md`, for the connected computer.
- Out, `Connection`: `13-connection.md`, for the connected computer.
- Out, `About`: `/settings/about`, mockup `19-about.md`.
- Out, `Status colours`: `/settings/status-colours`, mockup `20-status-legend.md` (added
  2026-09-09 per `R-03-106`).
- Out, `This phone's name`: the name sheet, in place.
- Out, a confirmed relay address change: `/welcome`, because nothing is paired any more, per
  `R-30-926`.
- The theme control and the size slider change the app in place, with no route change.

## Rules

- **R-31-15-01** The terminal text size and its line height MUST follow `R-30-210`. This screen MUST
  NOT restate the permitted sizes as a second list, and MUST NOT offer a continuous slider: the
  slider of callout 10 is discrete, one stop per permitted size (amended 2026-09-09, per
  `R-03-110`).
- **R-31-15-02** The terminal text size MUST be independent of the system text scale, because the
  system scale applies to the interface and a terminal grid is content. See `R-30-702`. This screen
  MUST draw one line under the preview that says so, in these exact words: `Terminal text size is
  separate from your phone's text size.` The line MUST be present in every state that shows the
  slider (amended 2026-09-09, per `R-03-110`: the stepper became a slider). A rule that requires a
  line, and a screen that never draws it, is the defect a review found here.
- **R-31-15-03** Changing the size MUST NOT clear the terminal grid or lose the scroll position.
- **R-31-15-04** `Haptics` off MUST silence every haptic in the app, including the error haptic. See
  `R-30-281`.
- **R-31-15-05** The `Theme` control MUST offer exactly `System`, `Light` and `Dark`, and `System`
  MUST be the default, per `R-30-112`. The app MUST follow the platform light and dark setting
  without a restart, and the terminal palette MUST follow the same setting, per `R-30-154` and
  `R-32-140`. This screen MUST state that in one line under the control, because a person cannot see
  the terminal from here.
- **R-31-15-06** The `RELAY` group MUST sit first, above `APPEARANCE`. A person who opens Settings
  because nothing connects MUST find the address without scrolling.
- **R-31-15-07** The relay row MUST show the stored origin in full, wrapped and never truncated, per
  `R-30-922`. It MUST NOT show the routing handle, a phrase, or a key.
- **R-31-15-08** A relay address change MUST follow `R-30-924` to `R-30-927` exactly: one
  destructive confirmation with that text, then close, clear the handle, clear the pinned key,
  store, and route to `/welcome`. This screen MUST NOT offer a way to change the address without
  that confirmation.
- **R-31-15-09** The first run relay row MUST route to `/pair/scan` on a tap, not to the edit sheet.
  An address with no phrase pairs nothing, so an editable field there is a dead end.
- **R-31-15-10** The navigation row for `12-notifications.md` MUST be labelled `Alerts`. The word
  `push` MUST NOT appear on this screen.
- **R-31-15-11** The three theme modes MUST keep choosing light or dark only. They MUST NOT choose a
  palette, and this screen MUST NOT offer a palette picker, per `R-32-014`. On Android the chrome
  colour comes from the operating system's own colour, per `R-33-024`, and the terminal keeps its
  fixed palette there as it does everywhere. This screen MUST say so in the second line of callout 8
  on Android. It MUST NOT show that line on iOS, where the chrome palette is fixed, and MUST NOT
  show it while the operating system returns no wallpaper scheme, per `R-33-031`. This screen MUST
  NOT explain that degenerate colour and MUST NOT offer a way out of it, because the way out is a
  system setting and not an app setting.
- **R-31-15-12** This screen MUST hold the only control that sets this phone's own name. The name
  reaches a computer in `device_info`, per `R-11-131`, and no message renames another phone, so
  `14-devices.md` MUST show a name and MUST NOT edit one. The row MUST carry the label
  `This phone's name` and MUST open the name sheet on a tap.
- **R-31-15-13** The field MUST reject a name longer than the `device_name` limit that the
  `device_info` field table of `docs/11-relay-protocol.md` fixes. It MUST measure UTF-8 bytes and
  not characters, because one emoji can use four bytes. This screen MUST NOT restate that limit as
  a number of its own. `Save` MUST stay disabled while the name is too long or empty, because
  `device_name` is a required field.
- **R-31-15-14** A saved name MUST take effect on this phone at once, and MUST NOT reach the
  connected computer before the next connection. `device_info` is the first frame the Device sends
  and it is sent once per session, per `R-11-131` and `R-11-132`, so nothing can carry a new name
  inside a live session. The sheet MUST say so in plain words and MUST name the connected computer
  while there is one. This screen MUST NOT offer a control that forces the change through, because
  `Reconnect now` on `13-connection.md` already rebuilds the link.
- **R-31-15-15** The name MUST default to the value `R-31-14-05` fixes. This screen MUST NOT name
  that default in its own words, and the sheet MUST open on the current name rather than on an empty
  field.
- **R-31-15-16** `Phones on this computer` and `Connection` MUST act on the one computer the app is
  connected to, per `R-30-946`. This screen MUST name that computer once, above both rows, and MUST
  hide the group when the app holds no computer. Neither row may read as covering every saved
  computer, because the app connects to at most one at a time, per `R-03-043`.
- **R-31-15-17** This screen MUST cite the platform divergences and MUST NOT restate them. There are
  three, and each belongs to `docs/33-platform-chrome.md`. `R-33-073` owns the composing widget of
  every group on this screen. `R-33-072` owns the trailing affordance of every row, and the split it
  produces here is: `Relay address` with an origin stored and `This phone's name` open sheets and
  take a labelled control; `Theme` and `Terminal text size` show their controls inline and take
  no trailing control; `Relay address` on first run, `Status colours` (added 2026-09-09 per
  `R-03-106`), `Alerts`, `Phones on this computer`, `Connection` and `About` open the next level
  and keep the chevron. `R-33-074` owns the confirmation dialog's component, action titles, order
  and focus. This screen MUST NOT name a composing widget, a chevron glyph, an action order or an
  initial focus target.
- **R-31-15-18** The `App Lock` switch MUST default off and MUST let a person turn it on or off
  at any time, per `docs/03-product-decisions.md` R-03-090. When the phone reports no screen
  lock, the row MUST be disabled and MUST show the message of the `No screen lock` state; the app
  MUST NOT let the switch turn on with no screen lock present, and MUST NOT fail silently.
  Turning the setting on or off MUST re-store the same key material under the new protection
  level. It MUST NOT generate a new key, MUST NOT unpair any computer, and MUST NOT require
  re-pairing, per `docs/13-security-pairing.md` R-13-073 and
  `docs/22-platform-integration.md` R-22-083.
- **R-31-15-19** `Alerts` and `About` MUST NOT carry a group header. Each is a single navigation
  row, drawn as the wireframe shows: `Alerts` follows `SECURITY` and `About` follows the connected
  computer's group (or `Alerts`, when nothing is connected), separated by the group gap of
  `R-30-231` alone. The product owner decided this on 2026-09-03, after a live review: a `MORE`
  header over those rows read as an action and did nothing, and a header that names no group is
  not one of the three forms `R-32-563` permits. No group on this screen MAY nest inside another
  group, per the same rule; the connected computer's group sits beside `Alerts`, not inside a
  parent.

## Retired rules

| Rule | Why |
| --- | --- |
| `R-31-15-20` | **Retired.** `R-03-130` removes prediction and the Safe typing switch. The native composer needs no prediction mode or preference. |

## Accessibility

- Touch target: every row, both switches, both sheet fields, `Change`, `Save`, `Cancel`, both
  dialog actions and each of the three theme segments meet the minimum target of `R-30-290` and
  `R-30-740`. A large text scale MUST NOT shrink any of them, per `R-30-741`. One measured
  exception, recorded 2026-09-09 per `R-03-059` and the `R-33-076` precedent: the size slider and,
  on iOS, the theme segments keep the platform component's own thumb and height, `Slider` and
  `CupertinoSlider` their own thumb target and the segmented control its own for
  `CupertinoSlidingSegmentedControl`, and the app MUST NOT raise any of them (amended 2026-09-09,
  per `R-03-110`).
- Contrast: every label uses `color.fg.primary` and every value `color.fg.secondary`, on
  `color.bg.base`. On iOS those chrome pairs are fixed, so they are passing rows in `R-32-150`, per
  `R-30-720`. On Android the same tokens resolve from the operating system's colour, per `R-33-024`,
  so the measured table cannot prove them and the runtime assertion of `R-33-044` proves them
  instead. The live preview uses `color.term.fg` on `color.term.bg`, a passing row in the measured
  table on both platforms, per `R-30-151`, because the terminal palette is fixed everywhere. The
  theme control sits on `color.bg.base` with a `color.border.strong` boundary, its unselected labels
  in `color.fg.primary` and its selected segment filled with `color.accent.primary` under a
  `color.fg.on_accent` label, exactly as `R-32-520` requires, and its label pairs and its
  selected-state boundary are proved by the same split: the measured table on iOS, the runtime
  assertion on Android. `Change` and `Save` are the two filled buttons of `R-32-525`, so each puts
  `color.fg.on_accent` on `color.accent.primary`, proved by the same split. `Change and unpair` uses
  `treat.destructive`, so the red lives in the icon and the bar, never in the text, per `R-30-143`.
- Screen reader: the relay row MUST carry the label `Relay address` and its value as the value, so
  it reads `Relay address, https colon slash slash relay dot example dot com`. The insecure strip
  MUST be announced once when it appears, through the mechanism `R-30-742` names, and MUST NOT be a
  live region, because a live region on a persistent strip would speak again on every repaint. The
  dialog MUST announce its title and its whole body before either action, because the body is the
  entire warning. `Change and unpair` MUST announce `destructive`. Each switch MUST expose `on` or
  `off`, per `R-30-717`. The name row MUST carry the label `This phone's name` and its value as the
  value. The name sheet MUST announce its hint before it reaches the field, because a person needs
  to know about the delay before typing and not after saving.
- Focus order: per `R-30-719`, title, the insecure strip when present, the relay group, the
  appearance group with the slider, the feel group, the name row, `Alerts`, the connected computer
  group, `About`, then the three bottom destinations. The sheet traps the focus. This file MUST NOT
  name the dialog's initial focus target, because `R-33-074` gives it to the platform component and
  forbids a preferred action where a destructive action is present.

## Open questions

None.

## Sources

- `docs/32-design-language.md` - the app bar `R-32-510`, the list row `R-32-515`, the segmented
  control `R-32-520`, the switch row `R-32-522`, the filled button `R-32-525`, the text field
  `R-32-530`, the bottom sheet `R-32-545`, the modal dialog `R-32-547`, the strip `R-32-561`,
  the theme rules `R-32-010` to `R-32-015`, the terminal palette `R-32-140`, the permitted sizes
  `R-32-208`, and the contrast table `R-32-150`.
- `docs/30-ux-spec.md` - the relay origin rules `R-30-920` to `R-30-927`, the relay row state table,
  the theme rule `R-30-112`, the terminal size rule `R-30-210`, the terminal text-scale exemption
  `R-30-702`, the announcement mechanism `R-30-742`, the modal dialog rule `R-30-005`, and the
  per-Host route rule `R-30-946`.
- `docs/11-relay-protocol.md` - the canonical origin form, the codes `relay_origin_invalid` and
  `relay_origin_insecure`, and the `device_info` field table with the `device_name` limit and the
  once-per-session order `R-11-131` and `R-11-132`.
- `docs/03-product-decisions.md` - one connected computer at a time, `R-03-043`, and the App Lock
  policy `R-03-090`.
- `docs/21-terminal-rendering.md` - `R-21-010`, the terminal line height that the preview renders
  with.
- `docs/33-platform-chrome.md` - the Android dynamic chrome colour `R-33-024`, the runtime contrast
  assertion `R-33-044`, the destination set `R-33-035`, the native control map `R-33-033`, the row
  affordance `R-33-072`, the settings list composition `R-33-073`, and the confirmation dialog
  `R-33-074`.
- `docs/13-security-pairing.md` - the App Lock storage-mode rule `R-13-073`.
- `docs/22-platform-integration.md` - the biometric gate `R-22-013` and the App Lock off storage
  shape, `R-22-082` and `R-22-083`.
- `docs/decisions/ADR-009-optional-app-lock.md` - the decision to make App Lock optional.
