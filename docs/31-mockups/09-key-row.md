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

Tap `+` to open the pager directly, per R-31-09-24. There is no menu.
The close control replaces `+`. The panel overlays the grid above the bar.
The keyboard keeps its current state. On iOS, Send stays inside the field suffix.
The layouts below illustrate R-31-09-21. A dot marks an empty cell, not a key.
Each bracket represents a native keycap with the shape and type of R-32-535.
The face table below supplies the large glyph and small name inside each cap.

```text
Page 1: Keys
+------------------------------------------------+
| [esc]    .      .    [ins]  [home] [pgup]        |
| [tab]    .      .    [del]  [end]  [pgdn]        |
|   .      .      .      .     [↑]     .          |
| [ctrl] [alt]    .     [←]    [↓]    [→]          |
|                  (*) (o) (o)                   |
+------------------------------------------------+
|  (x) [ Type here                         ] (>) |
+------------------------------------------------+
|          system keyboard, if already up        |
+------------------------------------------------+

Page 2: Function keys
+------------------------------------------------+
| [esc]    .     [F1]   [F2]   [F3]   [F4]        |
|   .      .     [F5]   [F6]   [F7]   [F8]        |
|   .      .     [F9]   [F10]  [F11]  [F12]       |
|   .      .      .      .      .      .          |
|                  (o) (*) (o)                   |
+------------------------------------------------+
|  (x) [ Type here                         ] (>) |
+------------------------------------------------+

Page 3: Answer
+------------------------------------------------+
| [esc]    .      .      .      .      .          |
|   .      .      .      .      .      .          |
|   .      .      .      .     [↑]   [enter*]     |
|   .      .      .     [←]    [↓]    [→]          |
|                  (o) (o) (*)                   |
+------------------------------------------------+
|  (x) [ Type an answer                    ] (>) |
+------------------------------------------------+
|          system keyboard, if already up        |
+------------------------------------------------+
```

`enter*` marks the primary filled cap. The other Answer caps use the idle form.
All pages retain four rows, including empty rows. A page change does not change the panel height.
`(*)` marks the selected SDK page dot, per R-33-081.
R-31-09-40 owns the indicator, page retention, and overflow onto additional pages.

### Composer answer mode

The Answer page uses the same composer below the panel, per R-31-09-41.
The composer stores the main draft and selection, then shows an empty answer buffer.
Its placeholder is `Type an answer`. The send control speaks `Send answer`.
No second field or send control appears in the panel.
When the panel closes or another page appears, the composer restores the main draft and selection.
Answer keys never change either composer buffer. A blocked agent opens Answer under R-31-09-38.

### Keycap faces

R-32-535 owns the rounded rectangle, glyph size, small name type, and native button states.
The following table owns the faces. Spoken labels remain unchanged.

| Key | Large face | Small name |
| --- | --- | --- |
| Escape | `Symbols.cancel_rounded` | `esc` |
| Tab | `Symbols.keyboard_tab_rounded` | `tab` |
| Control | `Symbols.keyboard_control_key_rounded` | `ctrl` |
| Alt | `Symbols.keyboard_option_key_rounded` | `alt` |
| Enter | `Symbols.keyboard_return_rounded` | `enter` |
| Insert | `Symbols.insert_text_rounded` | `ins` |
| Delete | `Symbols.backspace_rounded`, mirrored horizontally | `del` |
| Home | `Symbols.first_page_rounded` | `home` |
| End | `Symbols.last_page_rounded` | `end` |
| Page up | `Symbols.keyboard_double_arrow_up_rounded` | `pgup` |
| Page down | `Symbols.keyboard_double_arrow_down_rounded` | `pgdn` |
| Arrows | `Symbols.arrow_upward_rounded`, `Symbols.arrow_downward_rounded`, `Symbols.arrow_back_rounded`, `Symbols.arrow_forward_rounded` | None |
| Function keys | `F1` through `F12` | None |

Faces use the installed `material_symbols_icons` package, not Unicode key glyphs.
The owner selected native buttons with these icons on 2026-09-23, per R-03-117.

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
| [esc]    .      .    [ins]  [home] [pgup]        |
| [tab]    .      .    [del]  [end]  [pgdn]        |
|   .      .      .      .     [↑]     .          |
| [ctrl] [alt]    .     [←]    [↓]    [→]          |
|                  (*) (o) (o)                   |
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
of that order: it goes as `text`. The panel has no character caps, per R-03-117.
The Answer page uses the one composer for prompt answers, per `R-31-09-41`.

The `Row` column names positions on `Keys`, unless it names another page.

| Key | Row | Path | Wire value |
| --- | --- | --- | --- |
| a typed character | the keyboard | text | the character itself |
| `esc` | 1, column 1 | named | `Esc` |
| `tab` | 2, column 1 | named | `Tab` |
| `ctrl` | 4, column 1 | modifier latch, no call of its own | joins the next key, `ctrl+c`; every key while locked, per `R-31-09-23` |
| `alt` | 4, column 2 | modifier latch, no call of its own | joins the next key, `alt+b`; every key while locked, per `R-31-09-23` |
| `↑` | 3, column 5 | named | `Up` |
| `ins` | 1, column 4 | raw, in `text` | `ESC` `[` `2` `~` |
| `home` | 1, column 5 | raw, in `text` | `ESC` `[` `H` |
| `pgup` | 1, column 6 | raw, in `text` | `ESC` `[` `5` `~` |
| `←` | 4, column 4 | named | `Left` |
| `↓` | 4, column 5 | named | `Down` |
| `→` | 4, column 6 | named | `Right` |
| `del` | 2, column 4 | raw, in `text` | `ESC` `[` `3` `~` |
| `end` | 2, column 5 | raw, in `text` | `ESC` `[` `F` |
| `pgdn` | 2, column 6 | raw, in `text` | `ESC` `[` `6` `~` |
| `f1`–`f4` | Function keys: 1, columns 3–6 | named | `F1`–`F4` |
| `f5`–`f8` | Function keys: 2, columns 3–6 | named | `F5`–`F8` |
| `f9`–`f12` | Function keys: 3, columns 3–6 | named | `F9`–`F12` |
| `enter` | answer mode, or the composer Send control | named | `Enter` |
| `backspace` | the keyboard's delete key | named | `Backspace` |
| `shift+tab` | 2, long press on `tab` | named | `shift+tab` |
| a control chord, `ctrl+c` | `ctrl` latched, then the key | named | `ctrl+<char>`, lower case, per `R-10-038` |
| an Alt chord, `alt+b` | `alt` latched, then the key | named | `alt+<char>`, lower case, per `R-10-038` |
| a combined chord, `ctrl+alt+x` | `ctrl` and `alt` both latched, then the key | named | `ctrl+alt+<char>`, lower case, in the modifier order `R-10-039` fixes, per `R-03-120` |

Every panel page repeats `esc` in row one, column one. Function keys send bare names through
`_sendKeyNames`, for example `keys: ["F1"]`. They leave held and locked modifiers unchanged.
`R-10-038` limits chord bases to one character or `tab`. The caps use widget keys `keyRowFn1`
through `keyRowFn12`, print `F1` through `F12`, and speak `F1` through `F12`.

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
| Modifier latched | A tap on `ctrl` or `alt`. | The hint stays above the caps, or above the closed panel's input bar. The cap shows its held state. A character or Tab consumes the latch. A function key sends its bare name and leaves the latch unchanged. A tap on the other modifier adds it. |
| Modifier locked | A quick second tap on held `ctrl` or `alt`, per `R-31-09-23`. | The hint names the lock. Character and Tab chords retain it. Function keys send bare names and retain it. A third tap or a lifecycle exit releases it. |
| Key panel open | Tap `+`. | The pager overlays the grid above the bar. The keyboard state is unchanged. The leading glyph is `×`. |
| Page changed | Swipe left or right. | The page and indicator change together. Four rows remain. No input is sent. |
| Panel reopened | Close, then tap `+` in the same terminal screen. | The previous page returns. A new pane starts on `Keys`, page 1. |
| Answer selected | Swipe to Answer, or enter blocked status under R-31-09-38. | The composer stores the main draft and selection, then shows an empty answer buffer. Only the Answer `enter` cap is filled. |
| Answer edited | Type in the composer on Answer. | The answer buffer changes locally. No input or line sync occurs. Empty text still permits Send. |
| Answer submitted | Press `Send answer` or the native send action. | One frame follows R-31-09-41. Acceptance clears the answer buffer. Failure retains its text. The stored main draft stays unchanged. |
| Answer left | Close the panel or select another page. | The composer restores the exact main draft and selection without input. |
| Large text scale | Column modules no longer fit. | Columns reflow onto more four-row pages under R-31-09-40. No cap shrinks or clips. |

## Navigation

- The bar has no route of its own. It appears on the terminal in portrait and landscape.
- Tap `+` to open the pager without changing keyboard focus or sending input.
- Tap `×` or the grid to close the panel. The grid tap still focuses the composer.
- Swipe to change the page without closing the panel.
- Field focus and modifier latches leave the panel open.
- Swipe horizontally inside the panel to change pages. This gesture sends no input.
- Close and reopen retain the page within this terminal screen. A new pane resets to page one.
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
- **R-31-09-03** Composer edits MUST follow R-31-09-27. Keycap input MUST send at once,
  once per key or burst. A burst MUST use one frame, not one frame per character.
  Composer answer edits MUST follow R-31-09-41 instead of the live composer path.
- **R-31-09-04** Every key MUST send once. Composer edits use `R-31-09-27`; named keys and
  modifier chords
  use `R-31-09-29`. Composer keyboard return uses `R-31-09-28`. Key caps MUST NOT insert text into the
  composer.
- **R-31-09-05** `ctrl+c` MUST NOT ask for a confirmation. A person reaching for `ctrl+c` is
  stopping a runaway command and a dialog would defeat that.
- **R-31-09-06** The composer MUST use native editing, per `R-03-130` and `R-31-09-30`.
  The app MUST NOT implement its own cursor, selection or backspace.
  `R-31-09-30` keeps the platform's autocorrect, suggestions and capitalisation on.
- **R-31-09-07** Retired. See `## Retired rules`. The live composer is specified by `R-31-09-26`
  through `R-31-09-30`.
- **R-31-09-08** A latched `ctrl` MUST clear after a character or Tab, unless locked per `R-31-09-23`.
  Function keys MUST send bare names and MUST NOT change a held or locked modifier.
  The next character the keyboard types goes as
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
  control. A key acknowledgement or unknown outcome MUST NOT disable further key presses.
  The answer send control also follows the empty-field rule of R-31-09-41.
  The `+` / `×` control MUST stay enabled offline. Every panel key MUST be disabled, per R-30-807.

- **R-31-09-10** Retired. There is no send control to keep enabled. The keyboard's return key is
  the one way to send `Enter` from the keyboard, and it MUST go as `keys: ["Enter"]` with no
  `text`, per step 3 of `R-10-044`; `R-31-09-04` carries that. See `## Retired rules`.
- **R-31-09-11** Several edits MAY be in flight at once. Each acknowledgement MUST settle only
  its matching correlation. An edit acknowledgement MUST NOT change composer text. Typing MUST
  NOT wait for the network.
- **R-31-09-12** Retired by `R-03-130`. See `## Retired rules`.
- **R-31-09-13** The app MUST NOT offer an action that resends input, per `R-11-228`.
  The person checks the grid and edits again. An unknown outcome MUST NOT trigger an automatic
  resend.
- **R-31-09-14** Explicit Send progress follows `R-31-09-33`. A keystroke MUST NOT show progress
  of its own. One spinner per keystroke would
  flicker the row constantly. `R-31-09-02` confirms a cap press, and the next `pane_frame` shows
  the effect. A keystroke whose acknowledgement reports `accepted: false` MUST raise the strip of
  the `Error, send refused` row, and one whose acknowledgement never arrives MUST raise the strip
  of the `Outcome unknown` row; both MUST name the key, or `typing` for a run of characters, and
  MUST NOT re-send (amended 2026-09-09 per `R-03-054`: the rule bound a key press alone until then).
- **R-31-09-15** The shared column module MUST fit the widest face or complete name,
  plus `space.2` on each side.
  Each keycap MUST retain the minimum dimensions and type of R-32-535.
  A cap MUST NOT clip, truncate, or shrink its face or name at text scales through 2.0.
  Rows MUST grow together when their contents need more height.
  R-31-09-40 governs column overflow. R-30-519 owns the keyboard inset.
- **R-31-09-16** The panel MUST use the layouts of R-31-09-21 and the overflow behavior of R-31-09-40.
  No mode toggle MUST appear inside the panel. R-31-09-24 owns the leading control.

- **R-31-09-17** The key panel MUST open above the bar, between the grid and the bar.
  It MUST overlay the bottom of the grid on its own `color.bg.raised` surface with a top
  `border.hairline` in `color.border.strong`. The grid does not need to resize.
  Its height MUST remain unchanged between pages at the same width and text scale.
  R-31-09-40 governs horizontal swipes and overflow.
  Opening MUST preserve the keyboard state. Field focus and modifier latches MUST NOT close it.
  Only the close control or a grid tap MUST close it. The panel MUST NOT sit below the bar,
  replace the keyboard, or appear behind the keyboard.

- **R-31-09-18** Retired. See `## Retired rules`. The live composer is specified by `R-31-09-26`
  through `R-31-09-30`.
- **R-31-09-19** A tap on `ctrl` or `alt` MUST raise the software keyboard and MUST hold it up until
  every latch clears. A latch with no character on screen cannot be completed: every chord needs a
  character, and keys mode carries none. `R-31-09-08` fixes the one-key clearing for `ctrl`. This
  rule extends that clearing to `alt`, and adds four exits for both: 5000 ms with no key, the
  keyboard losing the focus, the app going to the background, and rotation. A modifier that
  survives any of those is a forgotten latch. A locked modifier, per `R-31-09-23`, keeps the last
  three exits and drops the first two. Both modifiers MAY be latched at once, per `R-03-120`: a
  tap on the second one MUST add it and MUST NOT release the first, each one MUST keep its own
  one-shot or locked state, and every exit above MUST act on each held modifier by its own state,
  so the 5000 ms timeout releases the one-shot latches and leaves a lock standing (amended
  2026-09-09 per `R-03-113`; amended 2026-09-10 per `R-03-120`).
- **R-31-09-20** Retired. The Shortcuts palette is gone. The key panel uses R-31-09-21.

- **R-31-09-21** The panel MUST provide `Keys`, `Function keys`, and `Answer`, in that order.
  Each page MUST use six columns and four rows when six modules fit.
  The following table defines the layouts. A dot is an empty cell.

  | Page | Row 1 | Row 2 | Row 3 | Row 4 |
  | --- | --- | --- | --- | --- |
  | Keys | `esc . . ins home pgup` | `tab . . del end pgdn` | `. . . . ↑ .` | `ctrl alt . ← ↓ →` |
  | Function keys | `esc . . . . .` | `. . . . . .` | `F1 F2 F3 F4 F5 F6` | `F7 F8 F9 F10 F11 F12` |
  | Answer | `esc . . . . enter` | `. . . . . .` | `. . ↑ . . .` | `. ← ↓ → . .` |

  `↑` MUST sit directly above `↓`. Empty cells and rows MUST retain their positions.
  All pages MUST share column widths and row heights. All four rows MUST remain visible.
  R-31-09-40 governs narrower layouts. The bar control MUST stay outside the grid.
  The panel MUST use `space.4` horizontal inset, `space.2` gaps and vertical padding.
  Native caps MUST follow R-32-535. Function keys MUST retain the wire behavior of R-10-038.
  Amended 2026-09-23 by the product owner, per R-03-117.

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
  one-shot or locked state. A character or Tab clears the one-shot latches and keeps the locks
  (amended 2026-09-10; until then the other modifier replaced the lock, which made
  `ctrl+alt+<key>` impossible to type). The cap MUST keep the latched state of `R-32-535` and
  `R-31-09-25` with
  no second visual state, per `R-03-100`; the hint line of the latched wireframe MUST change to
  `ctrl is locked. Tap ctrl again to release.` or its `alt` form, and MUST take the combined form
  of the `Modifier hints` section whenever both are held, on the same strip in the same
  type, with every key
  name as an inline key per `R-32-599`, so the state and the way out are on screen together. The
  spoken form is in the accessibility section.
- **R-31-09-24** The key panel MUST be the only extra-key surface.
  The leading control MUST use widget key `composerMore`.
  While closed, it MUST use `Symbols.add_rounded`, spoken `More keys`.
  A tap MUST open the pager directly on its last page, without a menu, input, or a keyboard focus change.
  While open, the control MUST use `Symbols.close_rounded`, spoken `Fewer keys`.
  A tap MUST close the panel directly, without a menu or input.
  Horizontal swipes MUST change pages under R-31-09-40.
  The `keyRowAnswer` toggle and composer menu items MUST NOT exist.
  Chords MUST use the existing modifier latch, not a chord list.
  Amended 2026-09-23 by the product owner, per R-03-133.

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
  `Type here`, except in answer mode under R-31-09-41.
  It MUST have one minimum line and five maximum lines.
  It MUST use a multiline keyboard and
  `textInputAction.send`. Android MUST use `Symbols.send_rounded`; iOS MUST use
  `Symbols.arrow_upward_rounded`. Section 7.13 of `docs/32-design-language.md` owns padding and
  colours. Section 5 of `docs/33-platform-chrome.md` owns the native controls. The bar MUST remain
  above the keyboard or system inset, per R-30-519. No permanent key row MUST appear below the
  field.

The following composer rules apply to the main draft. R-31-09-41 owns answer-mode exceptions.

- **R-31-09-27** Every composer edit MUST send the complete text immediately, per `R-03-137`.
  The app MUST use `send_input.line`, including an empty string after deletion.
  The app MUST NOT calculate deletion keys or replacement tails. `R-11-248` owns reconciliation.
- **R-31-09-28** Keyboard Enter MUST insert a newline into the native composer.
  The trailing Send control MUST submit the composer with `Enter`, including when the field is empty.
  Answer-mode `enter` MUST use the separate direct-key path of R-31-09-38.
  The control MUST follow `R-31-09-33` and `R-31-09-34`.
- **R-31-09-29** A named key or modifier chord MUST bypass the composer and use the raw-key
  path.
  It MUST NOT insert text into the field. The existing latch and lock rules remain in force.
- **R-31-09-30** The composer MUST represent the complete editable text, including newlines.
  It MUST use the Host seed under `R-31-09-32` and preserve failed submissions under `R-31-09-34`.
   Before the Host echoes input, only the native composer MUST show the typed
  text.
  The grid MUST show only Host frames, per `R-03-130`. The app MUST NOT predict glyphs or a cursor.
  Native editing owns the cursor, selection and backspace. The composer MUST keep the platform
  keyboard's autocorrect, suggestions, personalised learning and sentence capitalisation on,
  as `R-03-130` says ("native ... autocorrect"; amended 2026-09-16 by the product owner, who
  found the field without autocorrect "super annoying"; until then this rule turned them off).
  Smart quotes and smart dashes MUST stay off: a curly quote or an en dash sent into a shell
  breaks the command, so the composer sends the ASCII character the person typed.

- **R-31-09-31** The app MUST send full-line edits without waiting for each acknowledgement.
  Each send MUST use the correlation contract in `R-11-248`.
  `R-11-251` and `R-11-252` own Host queue behaviour, not the composer.
- **R-31-09-32** The app MUST seed the composer from `watch_ack.line`, per `R-11-249`,
  on each watch, including rewatch after reconnect. It MUST NOT infer input from the terminal grid.
  Applying the seed MUST NOT send an edit.
- **R-31-09-33** Send MUST show the platform progress indicator until the final acknowledgement
  arrives, except for the queued clock in `R-31-09-37`. With non-empty text, Send MUST send the
  full line and await acceptance before `Enter`, except for deferred submission under
  `R-11-253`. Progress MUST cover both stages. It MUST prevent a second submission while one is
  pending. Ordinary edits MUST NOT show this indicator. The app MUST settle input by
  correlation, not by acknowledgement arrival order.
- **R-31-09-34** (amended 2026-09-18, measured on the Android emulator against the live Host:
  a field that was read-only during the round trip dropped the first keystrokes of the next
  message.) `Send now` MUST clear the field at the tap, before any acknowledgement, and the
  field MUST stay editable while the submit is in flight. The wire is ordered, so a line frame
  typed during the round trip reaches the Host after the `Enter` and starts a fresh console
  line. The clear MUST NOT send deletion keys. When the line or the `Enter` is refused or times
  out, the app MUST show the error or unknown-outcome strip and MUST put the submitted text back
  into the field only while the field is still empty; text the person typed since is kept. A
  deferred submit (`R-31-09-37`) keeps its text in the read-only field until the final accepted
  acknowledgement clears it. The app MUST NOT resend automatically.
- **R-31-09-35** Except for answer sends under R-31-09-38, accepted raw-key acknowledgements
  MUST update the local composer mirror without sending a full-line edit.
  `Enter` and `ctrl+c` MUST clear it. `Backspace` MUST remove
  its last grapheme. Accepted paste text MUST append to it. The six raw control sequences in the
  key table MUST leave it unchanged. Other keys MUST also leave it unchanged. `R-10-076` owns the
  Host shadow lifecycle.
- **R-31-09-36** A long press on Send MUST open the platform-native menu. With no queued
  submission, it MUST offer `Send now` and `Send when done`. A normal tap MUST use `Send now`.
  While a submission is queued, it MUST offer only `Send now` and `Cancel queued send`. It MUST
  hide `Send when done` while queued. `Send when done` MUST use `defer: "until_idle"`.
  Cancellation MUST use `defer: "cancel"`, per `R-11-253`. While queued, `Send now` MUST send
  only `send_input` with `keys: ["Enter"]` and a fresh `corr`. It MUST NOT send `line`, `defer`,
  or a separate cancellation first. The app MUST NOT translate these choices into agent-specific
  keybinds.
- **R-31-09-37** A queued submission MUST show a clock indicator and a hint that it waits for the
  agent to finish. The composer MUST be read-only while queued and MUST retain the submitted
  text. `R-11-253` defines two acknowledgement phases with the same `corr`: intermediate
  `queued: true`, then final `queued: false`. The intermediate acknowledgement MUST NOT clear
  text or complete Send. The clock MUST remain visible until the final acknowledgement. After
  queued acceptance, the app MUST NOT apply an acknowledgement timeout while the Host holds the
  submission. For `Send now` while queued, the Host supersedes the held correlation with
  `accepted: false`, per `R-11-253`. The app MUST treat that acknowledgement as superseded, not
  failed, and await the fresh Enter correlation. Progress MUST continue until the fresh Enter
  receives its final acknowledgement. Only final acceptance MUST clear submitted text, per
  `R-31-09-34`. Cancellation, refusal, timeout, or disconnect MUST retain text. The app MUST NOT
  submit it again automatically.
- **R-31-09-38** A transition into blocked status MUST open the panel on the Answer page.
  The app MUST use pane-tree status and live `agent_status` updates.
  Other statuses MUST NOT close the panel or change its page.
  The person MAY close the panel or change pages while blocked.
  Repeated blocked updates MUST NOT override that choice.
  Every Answer cap MUST send its named key with `bypass_line: true`, per R-11-254.
  It MUST NOT send `line` or `defer`, or change either composer buffer.
  Its acknowledgement MUST NOT call `onInputAccepted` or apply the mirror rules of R-31-09-35.
  The terminal screen MUST own the current page beside `panelOpen`.
  `key_row.dart` MUST export `enum KeyPanelPage { keys, function, answer }`.
  `KeyRow` MUST accept `KeyPanelPage? requestedPage` and `ValueChanged<KeyPanelPage> onPageChanged`.
  A changed non-null request MUST animate or jump to that page.
  The callback MUST report the page on first build and after each page settles.
  `KeyRow` MUST NOT accept `answerMode` or contain an answer field or send control.
  Amended 2026-09-23 by the product owner.
- **R-31-09-39** Send with an empty composer MUST emit `Enter` through the direct key path. It
  MUST NOT send an empty full-line edit first. This exception applies to `R-31-09-33`.
- **R-31-09-40** All panel pages MUST use the SDK pager of R-33-081 on both platforms.
  Horizontal swipes MUST change pages and MUST NOT send input.
  The pager MUST NOT contain an inner horizontal scroll region or columns pinned outside its pages.
  The native indicator MUST sit centred below the pages, separated by `space.2`.
  Its spoken label MUST name the current page, its index, and the total count.
  The six-column layout announces `Keys, page 1 of 3`, `Function keys, page 2 of 3`,
  or `Answer, page 3 of 3`.
  The selected page MUST survive panel close and reopen within one terminal screen.
  A new pane MUST start on Keys. If the modules do not fit, columns MUST reflow onto more pages.
  All keys MUST remain reachable. Every page MUST retain `esc` in row one, column one.
  Each overflow page MUST retain four rows and its logical page identity.
  The indicator MUST include every extra page and announce its actual index and total.
  Reflow MUST preserve the target floor of R-32-363, complete names, and physical-keyboard groups.
  It MUST NOT shrink caps, clip labels, use `Wrap`, or substitute an inner scroll region.
  Amended 2026-09-23 by the product owner, per R-03-117.
- **R-31-09-41** The screen MUST compute `answerInput = panelOpen && page == KeyPanelPage.answer`.
  `Composer` MUST accept `bool answerInput` and `Future<bool> Function(String text) onSubmitAnswer`.
  When answer input starts, Composer MUST store the main draft text and selection.
  It MUST show an empty answer buffer.
  When answer input ends, it MUST restore that draft and selection exactly.
  Neither transition MUST send input. No `line` sync MUST run while answer input is active.
  The one field MUST use placeholder `Type an answer`, and its send control MUST speak `Send answer`.
  The separate `keyRowAnswerField` and `keyRowAnswerSend` controls MUST NOT exist.
  Answer edits MUST stay local. Native editing options MUST follow R-31-09-30.
  Queued and deferred send behavior MUST be disabled for answer input.
  Send and the native send action MUST call `onSubmitAnswer(text)`, including for empty text.
  The screen MUST send one frame with `keys: ["Enter"]` and `bypass_line: true`, per R-11-254.
  It MUST include `text` only when non-empty. It MUST NOT send `line` or `defer`.
  Accepted acknowledgement MUST clear the answer buffer, not the stored main draft.
  Failure or an unknown outcome MUST retain the answer text.
  Answer acknowledgements MUST NOT apply the composer mirror rules of R-31-09-35.
  Styling MUST follow R-32-537. Native controls MUST follow section 5 of `33-platform-chrome.md`.
  Amended 2026-09-23 by the product owner after live review.

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

- Touch target: every panel key and the bar controls
  present the visual size and the target that `R-32-535` and `R-32-362` fix, which meets `R-30-290`
  and `R-30-740`; the visual button is the target, per `R-31-09-21`. Two adjacent keys are
  separated by `space.2`, which clears the minimum in `R-30-292` (amended 2026-09-09 per
  `R-03-059`: the `space.1` gutter between two arrow segments is gone with the cluster). A cap that
  grows to fit its label keeps that target, per `R-31-09-15`.
- Contrast: on Android a key label is `color.fg.primary` on the row's `color.bg.raised`, because an
  outlined button has no fill, and its boundary is `color.border.strong` on the same surface; on
  iOS the label is `color.accent.text` on the component's tint, which measures 4.68 in both themes,
  per `R-32-535`. A latched key is `color.fg.on_accent` on `color.accent.primary` on both, the
  platform's own high-emphasis fill, per `R-31-09-25`.
  The Answer `enter` cap uses the same colours, per R-32-535.
  Every pair is a passing row in `R-32-150` or `R-32-535`, per `R-30-720` and `R-30-121` (amended
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
  which let two modifiers hold at once). Row four's
  `←`, `↓`, and `→` retain the spoken names of R-30-715, as does row three's `↑`.
  Function caps speak `F1` through `F12`. The indicator follows `R-31-09-40`.
  Refusal and unknown-outcome strips MUST each be announced once.
  The one composer MUST expose native text field semantics, label, value, and selection
  in both input modes.
- Focus order follows R-30-719: leading control, native composer, send control, then each visible
  panel row in printed order.
  The panel traps no focus.

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
