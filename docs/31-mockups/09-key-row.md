# 09 - Terminal input bar

| Field | Value |
| --- | --- |
| Route | `/hosts/:hostId/panes/:paneId`, a permanent part of that screen |
| Surface | Device, Android and iOS |
| Spec | `docs/30-ux-spec.md`, gesture table |

The input bar and key panel follow R-03-133. Only Host frames change the grid.

## Wireframes and callouts

The bar follows R-03-133. Parentheses represent native round controls.
The Android send control is outside the field. The iOS send control is inside its suffix.

```text
Android, panel closed, 48 dp
+------------------------------------------------+
|  (+) [ Type here                         ] (>) |
+------------------------------------------------+
|                 system keyboard                |
+------------------------------------------------+

iOS, panel closed, 36 pt
+------------------------------------------------+
|  (+) [ Type here                         (^) ] |
+------------------------------------------------+
|                 system keyboard                |
+------------------------------------------------+
```

### Key panel open

The close control replaces "+". The panel appears above the bar, over the bottom of the grid.
The keyboard keeps its current state. It stays below the bar when visible.
The panel has its own raised surface and top hairline. The grid does not need to resize.
On iOS, use the same panel above the iOS bar. Do not add an outside send control.

```text
+------------------------------------------------+
|                terminal grid                   |
+------------------------------------------------+
|  (esc) (tab) (ctrl) (alt)                        |
|  (ins) (home)(pgup)        ( ^ )                 |
|  (del) (end) (pgdn) ( < )  ( v ) ( > )           |
+------------------------------------------------+
|  (x) [ Type here                         ] (>) |
+------------------------------------------------+
|          system keyboard, if already up        |
+------------------------------------------------+
```

The six-column order is `esc tab ctrl alt empty empty`, `ins home pgup empty Up empty`, then
`del end pgdn Left Down Right` (amended 2026-09-16 per `R-03-117`: the inverted T is
bottom-aligned).

### Wrapped field

The field below has three lines. Send sits at the bottom trailing corner, with `+` beside it.
The corner radius stays fixed as the field grows to five lines, then uses its native scroll.

```text
Android
+------------------------------------------------+
|      /----------------------------------\     |
|      | A long command wraps onto the    |     |
|      | next line and continues onto a   |     |
|  (+) [ third line in the native field.  ] (>) |
+------------------------------------------------+

iOS
+------------------------------------------------+
|      /--------------------------------------\ |
|      | A long command wraps onto the        | |
|      | next line and continues onto a       | |
|  (+) [ third line in the native field. (^)  ] |
+------------------------------------------------+
```

### Refused keystroke

```text
+------------------------------------------------+
|  (!) Not sent: typing                          |
+------------------------------------------------+
|  (+) [ Type here                         ] (>) |
+------------------------------------------------+
|                 system keyboard                |
+------------------------------------------------+
```

The strip uses section 7.22 of `docs/32-design-language.md` and `treat.error`.
It names the refused key, or `typing`. The next send clears it.
An unknown outcome uses `treat.warning`, per R-30-518. Neither strip offers resend.
A keystroke in flight shows no strip, per R-31-09-14.

### Modifier hints

A modifier latch leaves the panel open and raises the keyboard if needed, per R-31-09-19.
The hint stays above the bar. Each key name uses the inline key of R-32-599.
The strip uses section 7.22, `type.caption`, and `color.fg.secondary`.
Each modifier keeps its own one-shot or locked state. Exchange the names for the corresponding `alt`
states.

```text
+------------------------------------------------+
|  ctrl is held. Press one key.                  |
|  (esc) (tab) (ctrl) (alt)                        |
|  (ins) (home)(pgup)        ( ^ )                 |
|  (del) (end) (pgdn) ( < )  ( v ) ( > )           |
+------------------------------------------------+
|  (x) [ Type here                         ] (>) |
+------------------------------------------------+
|                 system keyboard                |
+------------------------------------------------+
```

| State | On screen | Spoken |
| --- | --- | --- |
| `ctrl` held | `ctrl is held. Press one key.` | `Control held. Press one key.` |
| `ctrl` locked | `ctrl is locked. Tap ctrl again to release.` | `Control locked. Tap Control again to release.` |
| both held | `ctrl and alt are held. Press one key.` | `Control and Alt held. Press one key.` |
| both locked | `ctrl and alt are locked. Tap ctrl and alt again to release.` | `Control and Alt locked. Tap Control and Alt again to release.` |
| `ctrl` locked and `alt` held | `ctrl is locked and alt is held. Press one key. Tap ctrl again to release.` | `Control locked and Alt held. Press one key. Tap Control again to release.` |

## Key table

Every name below was probed against live Herdr 0.8.0. A name Herdr rejects returns
`{"code":"invalid_key"}`. Names are case insensitive. The verified table lives in
`docs/10-herdr-integration.md` section 6.

Six keys have no logical name, so they MUST go as raw CSI bytes in the `text` field of
`pane.send_input`, per `R-10-036`. Every other key MUST go by name in `keys`, per `R-10-037`.
`R-10-044` fixes the order in which the app resolves one key press. A typed character is step 1
of that order: it goes as `text`. The keyboard is the one source of a typed character, because
the key row holds no cap that types one, per `R-03-117`.

The `Row` column names the row and column in the key panel.

| Key | Row | Path | Wire value |
| --- | --- | --- | --- |
| a typed character | the keyboard | text | the character itself |
| `esc` | 1, column 1 | named | `Esc` |
| `tab` | 1, column 2 | named | `Tab` |
| `ctrl` | 1, column 3 | modifier latch, no call of its own | joins the next key, `ctrl+c`; every key while locked, per `R-31-09-23` |
| `alt` | 1, column 4 | modifier latch, no call of its own | joins the next key, `alt+b`; every key while locked, per `R-31-09-23` |
| `^` | 1, column 5 | named | `Up` |
| `ins` | 2, column 1 | raw, in `text` | `ESC` `[` `2` `~` |
| `home` | 2, column 2 | raw, in `text` | `ESC` `[` `H` |
| `pgup` | 2, column 3 | raw, in `text` | `ESC` `[` `5` `~` |
| `<` | 2, column 4 | named | `Left` |
| `v` | 2, column 5 | named | `Down` |
| `>` | 2, column 6 | named | `Right` |
| `del` | 3, column 1 | raw, in `text` | `ESC` `[` `3` `~` |
| `end` | 3, column 2 | raw, in `text` | `ESC` `[` `F` |
| `pgdn` | 3, column 3 | raw, in `text` | `ESC` `[` `6` `~` |
| `enter` | the keyboard's return key | named | `Enter` |
| `backspace` | the keyboard's delete key | named | `Backspace` |
| `shift+tab` | 1, long press on `tab` | named | `shift+tab` |
| a control chord, `ctrl+c` | `ctrl` latched, then the key | named | `ctrl+<char>`, lower case, per `R-10-038` |
| an Alt chord, `alt+b` | `alt` latched, then the key | named | `alt+<char>`, lower case, per `R-10-038` |
| a combined chord, `ctrl+alt+x` | `ctrl` and `alt` both latched, then the key | named | `ctrl+alt+<char>`, lower case, in the modifier order `R-10-039` fixes, per `R-03-120` |

A chord is typed, never picked from a list, per `R-03-116`: no surface prints one, so the
`ctrl+<char>` spelling reaches the screen only in a latch hint, as an inline key. The caret form
`^C` never appears on screen and never goes on the wire (decided 2026-09-08 by the product owner,
because a caret is not clear to every person). Amended 2026-09-10 per `R-03-116`: until then this
table listed the twelve chord caps of the Shortcuts palette, and `ctrl+[` among them sent `Esc`.
Amended again the same day per `R-03-117`: until then a row of twenty-four symbol caps typed a
character each, `alt`, `<` and `>` each had a cap on two rows, and the `Bank` column named a bank
rather than a row and a column of the grid. Amended a third time the same day, when the owner
amended `R-03-117`: `alt` returned to row one, `v` moved to row two under `^`, and the three
navigation pairs became vertical. Amended a fourth time the same day per `R-03-120`, which added
the combined chord row: until then only one modifier could be latched, so `ctrl+alt+<char>` was
unreachable.

## States

| State | Trigger | Input bar shows |
| --- | --- | --- |
| Default | The link is live. | The field, `+`, and send control are enabled. The panel is closed. A grid tap focuses the field and raises the keyboard. |
| Keystroke in flight | A `send_input` went out and no `send_input_ack` has come back, per `R-11-227`. | Nothing. A keystroke shows no progress of its own, per `R-31-09-14`, and the next `pane_frame` shows its effect. Typing continues; several keystrokes may be in flight at once, per `R-31-09-11`. |
| Error, send refused | `send_input_ack` returned `accepted: false`. | The strip of the refused-keystroke wireframe with `treat.error`: `Not sent: typing`, or `Not sent:` and the key's label. No action, per `R-31-09-13`. Haptic `haptic.error`. The next send clears it. |
| Outcome unknown | No `send_input_ack` arrived, because the link dropped, the app was in the background, or the reply deadline passed, per `R-30-518`. | The same strip with `treat.warning`: `We do not know whether typing reached the pane.`, or the key's label in the place of `typing`. No action, and the keys stay enabled: a person may retype, the app may not re-send, per `R-11-228`. A fresh `pane_frame` clears it, which is the reconciliation `R-30-518` requires: the grid is the record of what the pane received. |
| Host in use | The relay answered `host_in_use`. | The field, send control, and every key that sends are disabled at `opacity.disabled`, and a keystroke from the keyboard sends nothing, because `R-30-807` disables only what needs the network. The banner of `R-30-940` carries the words, so the toolbar adds no second line. |
| Offline | No route to the relay. | The field, send control, and every panel key are disabled, per R-30-807. The `+` / `×` control stays enabled so the panel can open and close. The offline indicator opens diagnostics, per R-30-806. |
| Keyboard up | Field focus, a grid tap, or a modifier latch. | The bar stays above the keyboard inset, per R-30-519. Field focus and modifier latches leave the panel open. A grid tap closes it. |
| Modifier latched | A tap on `ctrl` or `alt`. | The hint line `ctrl is held. Press one key.` above the caps when the panel is open, else above the input bar (`R-03-117`, 2026-09-16: no cap moves when the hint appears), the latched cap, and the keyboard up, per `R-31-09-19`. One key clears it. A tap on the other modifier adds it rather than replacing it, per `R-03-120`: both caps then read as latched and the hint names both. |
| Modifier locked | A quick second tap, within the double-tap window of `R-30-301`, on the held `ctrl` or `alt`, per `R-31-09-23` and `R-03-122`. (amended 2026-09-10 per R-03-122; until then any second tap locked). | The hint line `ctrl is locked. Tap ctrl again to release.`, the same latched cap, and the keyboard up. Every key is a chord until a third tap or a lifecycle exit of `R-31-09-19`. A lock and a one-shot latch of the other modifier hold together, and the key press clears the one-shot and keeps the lock, per `R-03-120`. |
| Key panel open | Tap `+`. | The panel overlays the bottom of the grid above the bar. The keyboard state is unchanged. The leading glyph is `×`. Field focus and modifier latches leave it open. |

## Navigation

- The bar has no route of its own. It appears on the terminal in portrait and landscape.
- Tap `+` to open the panel without changing keyboard focus or sending input.
- Tap `×` or the grid to close the panel. The grid tap still focuses the composer.
- Field focus and modifier latches leave the panel open.
- Modifier latches and locks keep the lifecycle exits in R-31-09-19 and R-31-09-23.
- Rotation releases the modifier latch. A grid tap raises the keyboard in either orientation.
- A switch to another computer leaves this route, per R-03-044 and R-30-946.

## Rules

- **R-31-09-01** Retired by R-03-133. The key panel replaces the permanent key row. This id stays
  reserved.

- **R-31-09-02** A key press MUST fire `haptic.select` and MUST show the platform's own pressed
  state, per `R-03-059` and `R-32-535`: on Android the Material ink overlay the button theme
  colours, on iOS the Cupertino press fade, on the platform's own timing. The app MUST NOT draw a
  fill, a scale or a timing of its own on a cap, and `R-32-609` no longer reaches a key cap
  (amended 2026-09-09 by the product owner, per `R-03-059`; from 2026-09-08 to that date the cap
  took a `color.accent.primary` fill and the press scale of `R-32-609` on the raw pointer-down,
  because inside a scrolling bank the tap recognizer waits for the gesture arena. The platform
  button reports the press when its own recognizer does, and the row keeps that timing). A
  terminal gives no local echo for a control key, so the phone must give the feedback. A keystroke
  from the software keyboard fires no haptic of its own: the keyboard gives its own (amended
  2026-09-09 per `R-03-054`).
- **R-31-09-03** The app MUST send one `send_input` per keystroke, or per burst of keystrokes that
  arrive together, and MUST send it at once. One editing update from the keyboard is one burst: a
  tap types one character, a swipe or a paste commits a whole word. A burst of characters MUST go
  as one `text` frame, never one call per character, because the Herdr socket answers one request
  per connection, per `R-02-004`. Amended 2026-09-09 per `R-03-054`: until then the rule read
  "one call per send", and a send was the whole field.
- **R-31-09-04** Every key MUST send once. Composer edits use `R-31-09-27`; named keys and
  modifier chords
  use `R-31-09-29`. Keyboard return uses `R-31-09-28`. Key caps MUST NOT insert text into the
  composer.
- **R-31-09-05** `ctrl+c` MUST NOT ask for a confirmation. A person reaching for `ctrl+c` is
  stopping a runaway command and a dialog would defeat that.
- **R-31-09-06** The composer MUST use native editing, per `R-03-130` and `R-31-09-30`.
  The app MUST NOT implement its own cursor, selection or backspace.
  `R-31-09-30` keeps the platform's autocorrect, suggestions and capitalisation on.
- **R-31-09-07** Retired. See `## Retired rules`. The live composer is specified by `R-31-09-26`
  through `R-31-09-30`.
- **R-31-09-08** A latched `ctrl` MUST clear after one key, unless it is locked per `R-31-09-23`.
  It MUST NOT stay latched otherwise, because a forgotten latch turns the next ordinary keystroke
  into a chord. The one key is the next character the keyboard types: it goes as
  `keys: ["ctrl+<char>"]`, in lower case per `R-10-038`, and the characters after it in the same
  burst go as ordinary text. Where `ctrl` and `alt` are both latched, per `R-03-120`, the one key
  MUST go as one call that names both, `keys: ["ctrl+alt+<char>"]`, in the modifier order
  `R-10-039` fixes; the app MUST NOT send one call per modifier. That press MUST clear every
  one-shot latch and MUST keep every lock, so a locked `ctrl` beside a held `alt` sends
  `ctrl+alt+x` and then `ctrl+y` (amended 2026-09-09 per `R-03-054`, per `R-03-113` for the lock,
  and 2026-09-10 per `R-03-120` for the second modifier).
- **R-31-09-09** The toolbar MUST NOT hold a read only mode, per `R-03-051`. Only the keys that
  send, and the keyboard's path to the pane, are ever disabled, and only for one reason: the link
  is down, per `R-30-807`. A permission MUST NOT disable them, because a paired phone has full
  control. Amended 2026-09-09 per `R-03-054`: a waiting acknowledgement and an unknown outcome no
  longer disable anything, because typing may not wait for a network round trip.
  The `+` / `×` control MUST stay enabled offline. Every panel key MUST be disabled, per R-30-807.

- **R-31-09-10** Retired. There is no send control to keep enabled. The keyboard's return key is
  the one way to send `Enter` from the keyboard, and it MUST go as `keys: ["Enter"]` with no
  `text`, per step 3 of `R-10-044`; `R-31-09-04` carries that. See `## Retired rules`.
- **R-31-09-11** Several keystrokes MAY be in flight at once. Each `send_input_ack` MUST settle
  the oldest one.
  An acknowledgement MUST NOT change composer text or settle a later keystroke. Typing MUST NOT
  wait for the network.
- **R-31-09-12** Retired by `R-03-130`. See `## Retired rules`.
- **R-31-09-13** The app MUST NOT offer an action that resends input, per `R-11-228`.
  The person checks the grid and edits again. An unknown outcome MUST NOT trigger an automatic
  resend.
- **R-31-09-14** A keystroke MUST NOT show progress of its own. One spinner per keystroke would
  flicker the row constantly. `R-31-09-02` confirms a cap press, and the next `pane_frame` shows
  the effect. A keystroke whose acknowledgement reports `accepted: false` MUST raise the strip of
  the `Error, send refused` row, and one whose acknowledgement never arrives MUST raise the strip
  of the `Outcome unknown` row; both MUST name the key, or `typing` for a run of characters, and
  MUST NOT re-send (amended 2026-09-09 per `R-03-054`: the rule bound a key press alone until then).
- **R-31-09-15** A key cap's width MUST be the larger of the column module of `R-31-09-21` and
  its label at `type.mono.key` plus `space.2` on each side (amended 2026-09-10 per `R-03-116`:
  until then a chord key in the palette floored at `size.chordkey` instead). The module and the
  padding are the layout floor the row's own button
  theme sets on the platform button, per `R-32-535`; the button paints its boundary inside that
  padding, so the boundary adds no width (amended 2026-09-09 per `R-03-059`). A cap MUST NOT clip,
  truncate or shrink a label at any text scale up to 2.0, per `R-30-701` and `R-30-741`. A
  four-character label, the longest on the grid, is 31.2 pixels at scale 1.0 at the 0.6 advance
  ratio `R-21-010` states, so with its padding it takes 47.2 and sits inside the 48 floor of
  `size.keycap`: at scale 1.0 every cap on every row is one width. At scale 2.0 the same label
  takes 78.4, so a cap grows sideways and its row scrolls. A cap MUST NOT grow taller than
  `size.keycap`. `R-30-519` owns the keyboard inset this toolbar sits above.
- **R-31-09-16** The panel MUST keep the six-column order in R-31-09-21. No toggle MUST occupy a key
  cell. The leading `+` opens the panel.

- **R-31-09-17** The key panel MUST open above the bar, between the grid and the bar.
  It MUST overlay the bottom of the grid on its own `color.bg.raised` surface with a top
  `border.hairline` in `color.border.strong`. The grid does not need to resize.
  The panel MUST show three rows and six columns without scroll or wrap. Its height MUST fit its
  rows.
  Opening MUST preserve the keyboard state. Field focus and modifier latches MUST NOT close it.
  Only the close control or a grid tap MUST close it. The panel MUST NOT sit below the bar,
  replace the keyboard, or appear behind the keyboard.

- **R-31-09-18** Retired. See `## Retired rules`. The live composer is specified by `R-31-09-26`
  through `R-31-09-30`.
- **R-31-09-19** A tap on `ctrl` or `alt` MUST raise the software keyboard and MUST hold it up until
  every latch clears. A latch with no character on screen cannot be completed: every chord needs a
  character, and the key row carries none. `R-31-09-08` fixes the one-key clearing for `ctrl`. This
  rule extends that clearing to `alt`, and adds four exits for both: 5000 ms with no key, the
  keyboard losing the focus, the app going to the background, and rotation. A modifier that
  survives any of those is a forgotten latch. A locked modifier, per `R-31-09-23`, keeps the last
  three exits and drops the first two. Both modifiers MAY be latched at once, per `R-03-120`: a
  tap on the second one MUST add it and MUST NOT release the first, each one MUST keep its own
  one-shot or locked state, and every exit above MUST act on each held modifier by its own state,
  so the 5000 ms timeout releases the one-shot latches and leaves a lock standing (amended
  2026-09-09 per `R-03-113`; amended 2026-09-10 per `R-03-120`).
- **R-31-09-20** Retired. The Shortcuts palette is gone. The key panel uses R-31-09-21.

- **R-31-09-21** The panel MUST use six columns: `esc tab ctrl alt empty empty`; `ins home pgup
  empty Up empty`; `del end pgdn Left Down Right` (amended 2026-09-16 per `R-03-117`; until then
  the T sat on rows one and two). Empty cells MUST stay empty. `Up` MUST sit above
  `Down`. The panel MUST use `space.4` horizontal inset, `space.2` gaps and vertical padding, and
  the native caps of R-32-535. Every row MUST share its column widths. All three rows MUST remain
  visible without scroll. The bar control MUST stay outside the grid.

- **R-31-09-22** Retired. The `Shortcuts` control it governed is gone with the palette it
  opened, per `R-03-116` and `R-31-08-24`. Bank two holds these keys, per `R-31-09-24`, and a
  chord is typed, per `R-31-09-08`. See `## Retired rules`.
- **R-31-09-23** A tap on an idle `ctrl` or `alt` MUST change its state from none to held.
  A quick second tap on that held modifier MUST change held to locked, per `R-03-122`.
  The second tap MUST occur within the double-tap window of `R-30-301` to lock it.
  A later second tap MUST change held to none. A tap on a locked modifier MUST change locked
  to none
  (amended 2026-09-10 per R-03-122; until then any second tap locked).
  While locked, every character the keyboard types MUST go as a chord with that modifier,
  one `send_input` each. Added 2026-09-09 per `R-03-113` item 2, from `deex2/herdroid`.
  The lock MUST NOT time out, because a person locks it to send several chords with
  no rush, and a silent release would turn the next chord into plain text. The three lifecycle
  exits of `R-31-09-19` MUST still release it: the keyboard losing the focus, the app going to the
  background, and rotation. A tap of the other modifier MUST add a one-shot latch of that modifier
  beside the lock and MUST NOT replace the lock, per `R-03-120`: each modifier carries its own
  one-shot or locked state, and one key press clears the one-shot latches and keeps the locks
  (amended 2026-09-10; until then the other modifier replaced the lock, which made
  `ctrl+alt+<key>` impossible to type). The cap MUST keep the latched state of `R-32-535` and
  `R-31-09-25` with
  no second visual state, per `R-03-100`; the hint line of the latched wireframe MUST change to
  `ctrl is locked. Tap ctrl again to release.` or its `alt` form, and MUST take the combined form
  of the `Modifier hints` section whenever both are held, on the same strip in the same
  type, with every key
  name as an inline key per `R-32-599`, so the state and the way out are on screen together. The
  spoken form is in the accessibility section.
- **R-31-09-24** The key panel MUST be the only extra-key surface. The leading control MUST use
  `Symbols.add_rounded`, spoken `More keys`, while closed. A tap MUST open the panel
  without sending input or changing keyboard focus. While open, it MUST use `Symbols.close_rounded`,
  spoken
  `Fewer keys`. A tap MUST close the panel without sending input. The retired `…`/`×` toggle MUST
  NOT occupy a key cell. The panel MUST contain only the keys in R-31-09-21. Symbols remain on the
  native keyboard. Chords MUST use the existing modifier latch, not a chord list. Keys MUST keep the
  named and raw CSI paths in the key table.

- **R-31-09-25** A latched or locked modifier cap MUST state its state through the platform's own
  high-emphasis button form, per `R-03-118`: on Android a `FilledButton` against the
  `OutlinedButton` of an idle cap, on iOS `CupertinoButton.filled` against
  `CupertinoButton.tinted`. A locked cap MUST underline its label and a held cap MUST NOT, the
  way every phone keyboard marks caps lock under the Shift glyph (amended 2026-09-10 per
  `R-03-122`; until then held and locked shared one look). `docs/32-design-language.md` section
  7.12 holds the values and `docs/33-platform-chrome.md` section 5 holds the widget on each
  platform. The cap's label MUST NOT change case, weight or text for state, and the app MUST NOT
  draw a bar, a dot, a border or a glow of its own: the fill is the latch and the underline is
  the lock. The cap MUST report the state to assistive technology as a toggle, and its spoken
  label MUST still be the `held` or `locked` sentence of `R-31-09-23` and the accessibility
  section. Added 2026-09-10 per `R-03-118`, after the product owner found the active state of the
  modifiers unclear: until then the cap was a `FilledButton.tonal` whose label went upper case,
  which was a design hack `R-03-059` and `R-03-104` both bar, and which told a screen reader
  nothing.

- **R-31-09-26** The bar MUST match the platform message bar, per R-03-133. It MUST use one raised
  surface with a top hairline and one row with `space.2` gaps. The leading round `+` MUST match the
  single-line field: 48 dp on Android, 36 pt on iOS. Android MUST use a round 48 dp
  `IconButton.filled` outside the field for Send. iOS MUST use a `CupertinoButton` inside the field
  suffix, at the inset in `docs/32-design-language.md` section 7.13. The iOS leading circle MUST
  retain a 44 pt minimum tap target. Controls MUST stay bottom-aligned when the field grows,
  with the leading circle's centre level with Send's centre. The field's corner
  radius MUST stay fixed, per R-03-133 (amended 2026-09-17). The field MUST
  use `TextField` on Android and `CupertinoTextField` on iOS, `type.mono.compose`, and placeholder
  `Type here`. It MUST have one minimum line, five maximum lines, a multiline keyboard, and
  `textInputAction.send`. Android MUST use `Symbols.send_rounded`; iOS MUST use
  `Symbols.arrow_upward_rounded`. Section 7.13 of `docs/32-design-language.md` owns padding and
  colours. Section 5 of `docs/33-platform-chrome.md` owns the native controls. The bar MUST remain
  above the keyboard or system inset, per R-30-519. No permanent key row MUST appear below the
  field.

- **R-31-09-27** Every composer edit MUST send `send_input` immediately, per `R-03-130`.
  Insertion, deletion, replacement and native selection edits MUST reach the Host in order.
  Deletion MUST send a `keys` array with one `Backspace` entry per removed grapheme,
  through the named-key path in `R-10-037`. Insertion MUST then send raw text.
  For a middle edit, the app MUST delete the old tail this way and then send its replacement.
  It MUST NOT resend the unchanged entire field or wait for an acknowledgement before the next edit.
- **R-31-09-28** The keyboard return action and trailing send control MUST each send `Enter`
  once and clear the composer. Clearing after submission MUST NOT send deletion keys.
  An empty composer MUST still submit `Enter`.
- **R-31-09-29** A named key or modifier chord MUST bypass the composer and use the raw-key
  path.
  It MUST NOT insert text into the field. The existing latch and lock rules remain in force.
- **R-31-09-30** Before the Host echoes input, only the native composer MUST show the typed
  text.
  The grid MUST show only Host frames, per `R-03-130`. The app MUST NOT predict glyphs or a cursor.
  Native editing owns the cursor, selection and backspace. The composer MUST keep the platform
  keyboard's autocorrect, suggestions, personalised learning and sentence capitalisation on,
  as `R-03-130` says ("native ... autocorrect"; amended 2026-09-16 by the product owner, who
  found the field without autocorrect "super annoying"; until then this rule turned them off).
  Smart quotes and smart dashes MUST stay off: a curly quote or an en dash sent into a shell
  breaks the command, so the composer sends the ASCII character the person typed.

## Retired rules

Every id below stays reserved, so an old citation still resolves. The first three died on
2026-09-09 per `R-03-054`, with the composed field they governed; the next two died on 2026-09-10
per `R-03-116`, with the Shortcuts palette they governed. The last two anatomies died the same
day, one per `R-03-117` and one per `R-03-118`.

| Rule | Why |
| --- | --- |
| Landscape key-row readout | **Retired anatomy, 2026-09-14.** R-03-133 removes the permanent row that held `144x50` and the pinch `14px` flash. The landscape app bar already reports the size. |
| `R-31-09-12` | **Retired.** `R-03-130` removes predictive local echo. The native composer shows local edits; the grid shows only Host frames. |
| `R-31-09-07` | **Retired.** It kept the field's text across a route change and a switch of computer, in a `flutter_riverpod` provider, never on disk. This rule described the former submit-only field, not the live composer introduced by `R-03-130`. No later rule reuses this id. |
| `R-31-09-10` | **Retired.** It kept the send control enabled on an empty field, so one tap sent `Enter` alone for a `y/n` prompt. There is no send control; the keyboard's return key sends `Enter`, and `R-31-09-04` carries the wire value. No later rule reuses this id. |
| `R-31-09-18` | **Retired.** It kept the field content, the field focus and the keyboard across a rotation, and made the input row visible in landscape whenever the field held text or the focus. This rule described the former submit-only field. `R-03-130` introduces a separate live composer. No later rule reuses this id. |
| `R-31-09-20` | **Retired.** It laid out the Shortcuts palette: four columns wherever the widest label `ctrl+\` fit four, fewer at a large text scale, the twelve chords first and then the eight navigation caps, `alt` on the title row, and a bounded scroll in landscape. There is no palette. Bank two holds these keys on the toolbar's own geometry, per `R-31-09-24` and `R-31-09-21`. No later rule reuses this id. |
| `R-31-09-22` | **Retired.** It fixed what the `Shortcuts` control of the terminal app bar did: it opened the palette in place, sent nothing on open and nothing on close, sent exactly one `pane.send_input` per selection, held `alt`, the twelve chords, the six navigation keys and the two arrows, and never invoked a plugin action. The control and the palette are both gone, per `R-03-116` and `R-31-08-24`: two controls that expanded the keys and showed two different things was inconsistent. No later rule reuses this id. |
| The Shortcuts palette | **Retired anatomy, not a rule id.** From 2026-09-08 to 2026-09-10 a modal layer over the toolbar drew a `Shortcuts` title, `alt` and a close control on its title row, twelve `ctrl+<char>` chord caps, the six navigation keys, the `<` and `>` arrows, and a caption naming its two openings. The product owner rejected it on 2026-09-10 per `R-03-116`: the `...` cap and the app bar's keyboard control gave two different results. Bank two is the one expansion, and a chord is typed the way a keyboard types it. |
| The input field, the send control and the pending line | **Retired anatomy, not a rule id.** From 2026-09-03 to 2026-09-09 the toolbar drew a composed text field with a send control under bank one, and a pending line above it while a send waited. The product owner rejected them on 2026-09-09 per `R-03-054`: they put typing in a box beside the session instead of in it. The typing surface is the grid, and callouts 6 and 7 of the bank one wireframe hold what replaced them. |
| The symbol rows | **Retired anatomy, not a rule id.** From 2026-09-03 to 2026-09-10 bank two drew two rows of twelve symbol caps, `- _ = + \| \` `~` `` ` `` `'` `"` `:` `;` over `{` `}` `[` `]` `(` `)` `$` `*` `#` `&` `!` `?`, each of which typed its own character. They set the grid at twelve columns, which needed 664 pixels and always scrolled on a phone, and they put a symbol two taps deep behind `...` on the way to a symbol that is two taps deep on the keyboard. The product owner rejected them on 2026-09-10 per `R-03-117`, asking whether `[ ] { }` were not already on the native keyboard: they are, on every phone keyboard's own symbol pages. The row keeps only the keys the keyboard has no key for, and the grid is six columns. |
| The upper-case latched label | **Retired anatomy, not a rule id.** From 2026-09-08 to 2026-09-10 a latched `ctrl` or `alt` cap drew a `FilledButton.tonal` on Android and set its label upper case, `CTRL` and `ALT`, and this file called that the one place the interface used case for state. The product owner rejected it on 2026-09-10 per `R-03-118`: the state was unclear, a tonal fill is not the platform's high-emphasis form, and a case change is a design hack `R-03-059` and `R-03-104` both bar. The cap is now a `FilledButton` or a `CupertinoButton.filled` with its label unchanged, and it reports a toggle, per `R-31-09-25`. |

## Accessibility

- Touch target: every key on all three rows and the bar controls
  present the visual size and the target that `R-32-535` and `R-32-362` fix, which meets `R-30-290`
  and `R-30-740`; the visual button is the target, per `R-31-09-21`. Two adjacent keys are
  separated by `space.2`, which clears the minimum in `R-30-292` (amended 2026-09-09 per
  `R-03-059`: the `space.1` gutter between two arrow segments is gone with the cluster). A cap that
  grows to fit its label keeps that target, per `R-31-09-15`.
- Contrast: on Android a key label is `color.fg.primary` on the row's `color.bg.raised`, because an
  outlined button has no fill, and its boundary is `color.border.strong` on the same surface; on
  iOS the label is `color.accent.text` on the component's tint, which measures 4.68 in both themes,
  per `R-32-535`. A latched key is `color.fg.on_accent` on `color.accent.primary` on both, the
  platform's own high-emphasis fill, per `R-31-09-25`. Every
  pair is a passing row in `R-32-150` or in `R-32-535`, per `R-30-720` and `R-30-121` (amended
  2026-09-09 per `R-03-059`: until then the label sat on a `color.bg.high` fill). A key cap carries
  no state indicator of any kind, per `R-03-100`: the button's own fill is the state, and the
  label's case never carries it, per `R-31-09-25`.
- Screen reader: every key MUST carry a spoken label that differs from its printed glyph, per
  `R-30-715`, which holds the labels for the arrows, `esc` and `ctrl+c`. The panel includes six
  navigation names:
  `ins` is `Insert`, `del` is `Delete`, `home` is `Home`, `end` is `End`, `pgup` is `Page up` and
  `pgdn` is `Page down`. `+` is `More keys` and `×` is `Fewer keys`, per `R-30-717`. A latched or
  locked modifier cap MUST also report the state as a toggle, per
  `R-31-09-25`, so a screen reader states it as well as speaking it. A latched `ctrl` MUST
  announce `Control held. Press one key.` once, and a latched
  `alt` MUST announce `Alt held. Press one key.` once. A locked `ctrl` MUST announce `Control
  locked. Tap Control again to release.` once, and a locked `alt` MUST announce `Alt locked. Tap
  Alt again to release.` once; each cap MUST carry the same sentence
  as its spoken state while it holds, and `Control` or `Alt` otherwise. Where both modifiers hold,
  each cap keeps its own sentence and the strip takes the combined sentence of the `both modifiers
  latched` section, so `Control and Alt held. Press one key.` is announced once and each cap still
  reports its own toggle, per `R-03-120` (added 2026-09-09 per
  `R-03-113`; amended 2026-09-10 per `R-03-116`, where `alt` moved into the expansion, and per
  `R-03-117`, twice: it took column three of row two, then came back to column four of row one
  beside `ctrl`; amended the same day per `R-03-118`, which added the toggle, and per `R-03-120`,
  which let two modifiers hold at once). Row two's
  `<`, `v` and `>` keep the spoken names of `R-30-715`, the same names row one's `^`
  carries. A refused keystroke's strip and an unknown
  outcome's strip MUST each be announced once when they appear. The native composer MUST expose
  the platform text field semantics,
  label, value and selection.
- Focus order follows R-30-719: leading control, native composer, send control, then each visible
  panel row in printed order. The panel traps no focus.

## Open questions

None. The whole key vocabulary was established against a live server, so nothing on this screen is
left to a decision.

## Sources

- [Use Messages on your iPhone or iPad](https://support.apple.com/en-us/104982) - iOS Messages shape
  reference.
- [Google Messages Material 3 Expressive redesign comes to chat
  screen](https://9to5google.com/2025/08/26/google-messages-chat-redesign/) - Android shape
  reference, 2025-08-26.
- [Material 3 icon button specifications](https://m3.material.io/components/icon-buttons/specs) - 48
  dp target reference.

The shape follows the Google Messages compose bar and iOS Messages, per `R-03-132`.
Google Messages supplies the Material 3 filled field and filled icon button reference.
iOS Messages supplies the rounded field and `arrow.up.circle.fill` reference.
Android uses `Symbols.send_rounded`; iOS uses `Symbols.arrow_upward_rounded`, per `R-32-401`.
The Android paper plane distinguishes Send from the nearby Arrow up key.
Both glyphs come from the app's Rounded set, not SF Symbols.

- [Material 3 text fields](https://m3.material.io/components/text-fields/guidelines) - field
  guidance.
- [Material 3 icon buttons](https://m3.material.io/components/icon-buttons/guidelines) - filled
  send control guidance.
- [Apple HIG text
  fields](https://developer.apple.com/design/human-interface-guidelines/text-fields)
  - native field guidance.

- `docs/03-product-decisions.md` - `R-03-054`, the live terminal, and full terminal control for a
  paired phone; `R-03-059`, every key cap is the platform's own button; `R-03-103`, the inline key
  in the latch hint; `R-03-113` item 2, the locked modifier imported from `deex2/herdroid`;
  `R-03-116`, the one expansion and the retired Shortcuts palette; `R-03-117`, the six-column
  grid whose columns carry the keyboard's own blocks, and the retired symbol caps; `R-03-118`, the
  latched cap's platform button form and its toggle; `R-03-120`, the two modifiers that latch
  together and the combined chord.
- `docs/32-design-language.md` - the key cap and the key row `R-32-535` and `R-32-536`, the latched
  values of section 7.12, the icon
  map `R-32-401`, the pressed state `R-32-501`, the inline key `R-32-599`, the strip of section
  7.22, and the contrast table `R-32-150`.
- `docs/33-platform-chrome.md` - the `Key cap` row of the native control table in section 5, per
  `R-33-033`, which names the button widget on each platform.
- `docs/30-ux-spec.md` - gesture model, the key row accessibility rules `R-30-715` and `R-30-719`,
  the keyboard inset `R-30-519`, and the outcome-unknown model `R-30-518`.
- `docs/02-herdr-probe-results.md` - measured socket behaviour, event payloads, payload sizes.
- `docs/10-herdr-integration.md` - `pane.send_input` in section 3.2, the verified logical key
  names of section 6, probed against live Herdr 0.8.0, including `Backspace` and `Enter`, and
  `R-10-039` in section 6.7, the `ctrl` then `alt` order a combined chord joins its modifiers in.
- `docs/11-relay-protocol.md` - the error `host_in_use`, and `send_input_ack` with `R-11-227`,
  which
  fixes what an acknowledgement proves, and `R-11-228`, which forbids an automatic re-send.
- `docs/21-terminal-rendering.md` - `R-21-019c`, the canonical `Esc` name, the input mapping, and
  `R-21-020`, the soft keyboard the key row manages.
- `docs/31-mockups/08-terminal.md` - the grid that is the typing surface, and the app bar this
  row no longer shares an expansion with, per the retired `R-31-08-24`.
- `docs/31-mockups/18-actions.md` - the workstation plugin actions, which are a different thing
  from a key and are reached from the pane action sheet.
- The Herdr socket API schema, read at run time with `herdr api schema --json` -
  `PaneSendKeysParams` and `PaneSendInputParams` declare `keys` as an array of bare `string`. It is
  never a committed file.
