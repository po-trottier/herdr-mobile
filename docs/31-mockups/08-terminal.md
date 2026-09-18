# 08 - Terminal view

| Field | Value |
| --- | --- |
| Route | `/hosts/:hostId/panes/:paneId` |
| Surface | Device, Android and iOS |
| Spec | `docs/30-ux-spec.md` |

This is the screen the product exists for. It renders one Herdr pane at full fidelity.
It is not a video stream and not a screen share. The Host sends ANSI text, and a real
terminal emulator on the Device parses and paints it. See `R-02-014`.

A paired phone has full control of this pane: it reads, it types, it sends a chord, and it drives
every pane action. `docs/03-product-decisions.md` sets that policy. There is no read only pairing
and no grant to check.

This screen is full-screen. `R-30-022` hides the bottom navigation here, so the create control does
not appear on it either, per `R-31-08-17`. A split is a create-menu task of `17-create.md`, reached
from a screen that carries the create control.
> **2026-09-08 correction.** Latest user screenshots supersede the earlier same-day fit-default
> decision. Readable text is the default; `Overview` is the explicit whole-grid fit action.
> **2026-09-10 amendment, `R-03-115`.** Every pane row in the switcher is one line high.
> An agent row puts its kind, pane name and state on one baseline.

## Wireframe, portrait, live

```text
+--------------------------------------+
| <  * plugin v                      : |
|      2 waiting   1 done              |
+--------------------------------------+
|   Passed!  Failed: 0, Passed: 412    |
|                                      |
| * claude                             |
| | I will add the missing test for    |
| | the socket reconnect path.         |
| |                                    |
| | > Read  socket_test.dart           |
| |   + 34 lines                       |
| |                                    |
| | Waiting for your approval:         |
| | Allow write to socket_test.dart?   |
| |   1. Yes  2. Always  3. No         |
|                                      |
| > _                                  |
+--------------------------------------+
| 144x50 c1-50 live rev 41822 Overview |
+--------------------------------------+
| esc  tab  ctrl  alt  ^         ...   |
+--------------------------------------+
```

The `v` after the title opens the pane switcher (callout 10, `R-31-08-25`), imported on 2026-09-09
per `R-03-113`. The attention summary under it is the title's own subtitle, per callout 11 and
`R-31-08-26`. Amended 2026-09-11 by the product owner, who saw the summary as a separate band
under the bar and rejected it: the summary now sits inside the title control as a second line,
on the title's text edge, so the bar reads as one two-line heading. The numbers alone take the
`type.body.strong` weight; the pairs sit `space.3` apart with no separator glyph. The summary is
absent while both counts are zero, as in the other portrait wireframes.

## Wireframe, portrait, pane switcher

```text
+--------------------------------------+
|                                      |
|   . . . the terminal, dimmed . . .   |
|                                      |
+--------------------------------------+
|                 ==                   |
| Switch pane                          |
|                                      |
| v plugin                    3 panes  |
|     [] plugin                        |
|      ############################    |
|      #| claude  main       Blocked#  |
|      ############################    |
|         = pane 3  zsh                |
|     [] tests                         |
|       | codex  pane 2         Done   |
| v docs                       1 pane  |
|     [] notes                         |
|       | claude  review      Working  |
+--------------------------------------+
```

The box of `#` marks the selected row, the pane on screen: the `color.accent.soft` wash. `|`
before an agent row is its full-height state bar, `=` before a shell row is the `A pane` glyph,
`[]` is the `A tab` glyph, and `v` is the expander. Every pane row uses one line.

## Wireframe, portrait, Overview

```text
+--------------------------------------+
| <  * plugin                        : |
+--------------------------------------+
|   Passed!  Failed: 0, Passed: 412    |
| * claude   | > Read socket_test.dart |
| > _                                  |
+--------------------------------------+
| 144x50 live rev 41822       Readable |
+--------------------------------------+
| esc  tab  ctrl  alt  ^         ...   |
+--------------------------------------+
```

Overview fits the whole grid with measured cells, so it hides the column range. The same native
labeled action reads `Readable`; pressing it restores the current saved readable glyph width.

## Callouts

1. Back control. The app bar leading control of `R-32-510`. Returns to the route that opened this
   screen. The mock draws `<` because a 40-column text frame has one glyph available. The real
   glyph belongs to each platform's own navigation component, per `R-33-070`, so it is a chevron
   on iOS and a full arrow on Android.
2. Pane title `plugin`. The tab `title` alone, from `tree_snapshot` per `R-11-044` (amended
   2026-09-11 per `R-03-129`: the pane name after ` / ` appears only when the tab holds two or
   more agent panes, and a pane whose tab has no title shows the pane display name of `R-31-07-08`
   alone). Token `type.heading` in `color.fg.primary`, the `Title` row of the app bar table of
   `R-32-510` (corrected 2026-09-09: this callout said `type.body.strong`, which the app bar never
   took). It truncates with an ellipsis. There is no host chip here, per `R-31-08-20`. Since
   2026-09-09 the title is a control (amended per `R-03-113` item 1): callout 10 owns the button
   and the `v` after the title.
3. Live bar. The connection indicator of the app bar of `R-32-510`, the state bar of `R-32-592` as
   `R-03-100` leaves it (amended 2026-09-09 by the product owner: one state mark, the bar; the dot
   is retired): `border.attention` wide, `size.icon.md` high like the control glyphs, in one of
   three hues, `color.status.ok` while frames arrive, `color.status.warning` once the last frame
   is older than the age `R-32-511` fixes, `color.status.error` while the link is down. It never
   pulses: a stale link is not work. Its semantics label is the connection word, per `R-32-511`.
   It sits before the title, on the bar's leading side, `space.2` before the title text, the way
   every list row puts its bar in the leading slot before its name, per `R-03-121` and the
   `Live bar` row of `docs/32-design-language.md` section 7.3 (amended 2026-09-10 by the product
   owner: until then it sat among the trailing controls, at the right of the bar). The mock draws
   it as `*` after the back control. It is an indicator, not a control, so it counts against no
   control ceiling, and on Android the attention summary of callout 11 starts on the title text
   edge past it, per `R-31-08-28`.
4. Retired. This bar carried a `Shortcuts` control from 2026-09-08 to 2026-09-10. It opened the
   Shortcuts palette of `09-key-row.md`, and both are gone, per `R-03-116` and the retired
   `R-31-08-24`. The key row has exactly one expansion, the `...` cap of `R-31-09-24`, and a
   control chord is typed there, `ctrl` latched then the key. This callout number stays reserved,
   so an old citation still resolves. The bar's own history: the `Computer actions` control left it
   on 2026-09-08, and the `Shortcuts` control that replaced it left on 2026-09-10.
5. Overflow `:`, with the icon `R-32-401` names for `Pane actions`, as an app bar trailing control
   of `R-32-510`. It is the bar's one trailing control, well under the `R-32-512` ceiling of three
   (amended 2026-09-10 per `R-03-116`: it trailed the `Shortcuts` control until then, and the
   slack the retirement leaves MUST stay empty). Opens the pane action sheet, mockup
   `10-pane-actions.md`.
6. Terminal grid. The emulator owns every pixel inside it. Font `type.mono.terminal`. Background
   `color.term.bg`. Foreground `color.term.fg`. It is content and not chrome, so no glass and no
   translucent material reaches it on either platform, per `R-31-08-15`.
   The grid **background** runs to the screen edges and under a display cutout, and a grid **cell**
   never does: `R-21-039` owns that split and how the cell rectangle is measured. `R-21-040` owns
   the horizontal pan and why it starts inside the system gesture insets.
   `docs/21-terminal-rendering.md` owns the write path, the line height in `R-21-010`, the
   coalescing window in `R-21-021` and the render fallback in `R-21-022`. This mockup restates none
   of those numbers. Per `R-21-008`, Readable mode starts at the saved ladder size, default 13px;
   a wide grid clips at the viewport edge, supports the horizontal pan of `R-21-037`, and reports
   its readable column range. The labeled `Overview` action enables whole-grid fit without changing
   the Host grid or saved settings.
7. Status strip. The strip of `R-32-542`. It keeps all metadata and has the labeled mode control.
   The metadata is one text run from the leading inset, in the printed order below with `space.3`
   between two readouts, so its three type sizes share one baseline and it wraps like prose at a
   narrow width or a large text scale; the mode control's label ends on the trailing inset, the
   column the key row's last cap ends on, per `R-31-09-21` (amended 2026-09-08
   by the product owner: the readouts were spread across the width, so the size readout moved
   every time the scroll readout changed width, and the connection word sat one pixel under the
   caption baseline). The strip carries the one top edge `R-32-542`'s anatomy fixes and no bottom
   edge; the key row below carries its own top edge, per `R-32-535`.
   - `144x50` is the exact grid size, columns first, then rows. There is no tilde and no word such
     as `about`.
   - The column count is `width` and the row count is `viewport_rows`. The Device reads both from
     `watch_ack` and from every `pane_frame`, per `R-11-049` and `R-11-051`. The Host takes `width`
     from `pane.layout` `rect.width`, measured in character cells, and the rows from
     `scroll.viewport_rows`. Rows MUST NOT come from `rect.height`, which carries a conditional
     chrome offset in a split tab. See `R-10-024`.
   - `c1-50` is the Readable column window: the first and last column the screen holds. It appears
     whenever the grid is wider than the Readable window, including at default 13px, per `R-21-037`.
     Overview fits the whole grid and hides this range.
   - `live`, `paused`, `in use` or `offline` is the connection word, and the state bar of
     `R-32-592` sits before it, a short bar as tall as the text line, `size.icon.sm`, in the
     word's hue: `working` for `live`, which pulses, `idle` for `paused`, `blocked` for `in use`,
     `unknown` for `offline` (amended 2026-09-09 by the product owner, per `R-03-100`: one state
     mark, the bar; the dot is retired). Amended 2026-09-18 per `R-31-08-29`: while live, the
     word is the measured round-trip time, `N MS`, not `LIVE`. The other states keep their words.
   - `rev 41822` is `revision` from the same two messages. It is shown because it proves the view
     is current and makes a bug report exact.
   - `Overview` is the native labeled action with a 48dp minimum target in Readable mode. In Overview
     mode the visible label is `Readable`, and pressing it restores the current readable size
     immediately. Portrait status height is normally 48dp and MAY grow for system text scale; metadata
     MAY wrap at narrow widths.
8. Key row. Mockup `09-key-row.md` owns every key, both banks, the modifier latch and the one
   expansion of `R-31-09-24`.
9. Typing surface (amended 2026-09-09 per `R-03-054`; until then this callout drew an input
   field and a send control under the key row). The grid is the typing surface. A tap on it
   raises the keyboard and sends nothing, per `R-31-08-08`, and every keystroke then goes to the
   pane as it is typed: `09-key-row.md` callout 6 owns the path and the key table. Nothing on
   this screen echoes a keystroke; the next `pane_frame` does. The keyboard rising hides the key
   row's second bank, never the first. `docs/30-ux-spec.md` `R-30-519` owns the keyboard inset
   and the text-scale behaviour of this screen; the grid itself never follows the system text
   scale, per `R-21-038`.
10. Title control `plugin / pane 1 v` (added 2026-09-09 per `R-03-113` item 1, `R-31-08-25`). The
    title of callout 2 is the platform's own button, per `R-03-059`: a `TextButton` on Android in
    the heading's own `color.fg.primary` ink over the theme's `color.accent.soft` press wash, a
    plain `CupertinoButton` as the navigation bar `middle` on iOS with the platform's press fade.
    After the title, `space.1` later, the `expand_more` glyph of the `Expand, collapse` row of
    `R-32-401` at `size.icon.md` in `color.fg.secondary`, the same pair the host chip of
    `06-agent-list.md` draws for a title that opens a chooser. A tap opens the pane switcher sheet
    of the switcher wireframe; it sends nothing and changes no route by itself. Until the first
    `tree_snapshot` lands there is nothing to list, so the title is the plain heading of callout 2
    with no glyph. One semantics node, `<title>, switch pane`, a button.
11. Attention summary `2 waiting   1 done` (added 2026-09-09 per `R-03-113` item 4,
    `R-31-08-26`; amended 2026-09-11 twice, see the rule). The summary is the second line of the
    title control of callout 10: one `type.caption` line in `color.fg.secondary` directly under
    the name, on the name's text edge, inside the same button, so a tap on it opens the switcher
    too. The `v` glyph stays on the name's line. Two count/unit pairs sit `space.3` apart with no
    separator glyph; the numbers alone take the `type.body.strong` weight and the words keep the
    caption weight. The bar's height is the platform's own: the two lines fit the 56 Android row
    and the 44 iOS row of `R-33-076`, and no `bottom` slot is used. The bar's one bottom hairline
    is unchanged.
    `2 waiting` counts agent panes whose `agent_status` is `blocked`; `1 done` counts those whose
    status is `done`. Both counts cover the whole live tree of the connected computer:
    `pane.agent` set, `agent_status` on the pane, as `06-agent-list.md` reads them.
    A `tree_update` changes the numbers. Words only: no state mark, bar, dot, badge or state colour,
    per `R-03-058` and `R-03-100`. State bars belong on the switcher and agent list rows.
    The line is absent while both numbers are zero. Landscape uses the same title control in the
    merged bar, so the subtitle sits under the name there too.

### Callouts, pane switcher

1. The sheet. The bottom sheet of `docs/32-design-language.md` section 7.16 on both platforms
   (`R-33-037`), the platform's own draggable sheet per `R-03-108`, on the root navigator like
   every other sheet: `radius.lg` top corners, `color.bg.raised`, the grab handle of `R-32-546`,
   then the heading `Switch pane` in `type.heading` `color.fg.primary`. It is bounded like the pane
   action sheet of `R-31-10-09`: the handle and the heading stay put and the tree scrolls. It
   draws the tree it was opened with; a person reopens it for a later `tree_update`.
2. Tier 1, a workspace. The shared tier-1 header of `R-32-563`: the expander of `R-32-568`, the
   workspace `name` in `type.body.strong`, the trailing count `3 panes` in `type.caption`. It is
   the one tier that is a control: a tap collapses the tabs and panes under it in place and keeps
   the count, per `R-32-566`, for the life of the sheet only. Every workspace opens expanded, and
   the sheet keeps no memory of a collapse: the `R-31-07-02` store belongs to the browser of
   `06-agent-list.md`, not to a transient sheet.
3. Tier 2, a tab. The `A tab` glyph of `R-32-401` at `size.icon.sm` in `color.fg.secondary`,
   `space.2`, the tab `title` in `type.body.strong` `color.fg.primary`; the line plus `space.3`
   above and below, 48 at the default text scale like the tab tier of `06-agent-list.md`. It is
   not a target: a tab has no phone action, per `R-03-101`, and its panes are the targets under it.
4. Tier 3, a pane. The row sits one `space.10` in from the sheet edge, so its state bar stands
   in the tab glyph's column. It is 48 high: one line with `space.3` above and below. An agent
   row puts its kind in `type.body` `color.fg.primary`, then `space.2`, then its pane display
   name in `type.caption` `color.fg.secondary`. The state word trails on that baseline in
   `type.body` `color.fg.primary`; the state bar spans the full row. A shell row puts the
   `A pane` glyph in the slot, then its display name in `type.body` and, after `space.2`, its
   optional `title` in `type.caption`, both in `color.fg.secondary`. It has no bar or state
   word (amended 2026-09-10 per `R-03-115`). The ladder stays three steps: workspace name, tab
   title and pane text, per `R-03-057`.
5. The selected row. The pane on screen takes the `color.accent.soft` wash of the section 7.4
   selected-row anatomy and the semantics state `selected`; weight and wash carry a selection,
   never a second bar, per `R-03-100`. A tap on it closes the sheet and does nothing else.
6. A tap on any other pane closes the sheet and replaces this route with that pane's terminal,
   `/hosts/:hostId/panes/:paneId`, so the new screen attaches, watches and unwatches on its own
   lifecycle, the nested `/actions` route keeps the right pane, and back still returns to the route
   that opened the first terminal, per `R-30-031`. The sheet sends nothing to the computer. It
   offers no split, no zoom and no rename, per `R-03-101`: a split is a create-menu task of
   `17-create.md`, per `R-31-08-17`.
7. Empty. A tree with no pane draws one line, `No panes on this computer.`, in `type.body`
   `color.fg.secondary` under the heading, and no row.

## Wireframe, portrait, scrolled back

```text
+--------------------------------------+
| <  * plugin                        : |
+--------------------------------------+
|   restore.                           |
|   Restored /src/HerdrStandalone/     |
|   HerdrStandalone.csproj (in 412 ms  |
|                                      |
|   Determining projects to restore    |
|   All projects are up to date        |
|                                      |
|   socket_test.dart(84,7): warning    |
|   CS0168: variable declared but      |
|   never used                         |
|                                      |
|                   +--------------+   |
|                   | v  to bottom |   |
|                   +--------------+   |
+--------------------------------------+
| 144x50 c1-50 paused -120 / 240    |
| Overview                           |
+--------------------------------------+
| esc  tab  ctrl  alt  ^         ...   |
+--------------------------------------+
```

 1. Jump to bottom pill. It appears when the Device's own scroll offset is greater than zero, per
    `R-31-08-18`. The pill of `R-32-540`, which fixes its height, its fill, its boundary, its icon
    and its position. Its `size.target.min` target stands above the pill, so the pill itself stays
    `space.4` above the strip. Pressed, it takes the first case of `R-32-501`, `color.accent.primary`
    with the glyph and the label in `color.fg.on_accent`, and the press scale of `R-32-609`
    (amended 2026-09-08 by the product owner: the pill was its own 36-pixel target and gave no
    answer on pointer-down).
 2. The connection word turns `paused`, and it is exact. The emulator holds the fetched scrollback
    window and the Device stops writing to it, per `R-21-041`. A new frame is held, not painted, so
    the line the person is reading cannot move under them. Reaching the bottom paints the held frame
    at once, per `R-31-08-06`. The grid is **not** dimmed here: dimming means a lost or a blocked
    link, per `R-31-08-05`, and this link is live.
 3. The scroll readout `-120 / 240` gives the Device's own offset above the live bottom, then
    `max_offset_from_bottom` from `watch_ack`, per `R-31-08-18`. It is exact, not a proportion.

## Wireframe, portrait, selection

```text
+--------------------------------------+
| x  3 lines selected                  |
+--------------------------------------+
|   Passed!  Failed: 0, Passed: 412    |
|                                      |
| * claude                             |
| |[I will add the missing test for]   |
| |[the socket reconnect path.     ]   |
| |[                              ]    |
|  +------------------------------+    |
|  | Copy   Select visible screen |    |
|  +------------------------------+    |
| |   + 34 lines                       |
| |                                    |
| | Waiting for your approval:         |
| | Allow write to socket_test.dart?   |
| |   1. Yes  2. Always  3. No         |
|                                      |
| > _                                  |
+--------------------------------------+
| 144x50 c1-50 paused rev 41822     |
| Overview                           |
+--------------------------------------+
```

 1. The app bar becomes the selection variant of `R-32-510`. It carries no action. `x` cancels the
    selection, and `3 lines selected` is text and not a control. The cancel earns its place because
    `R-31-08-08` gives a grid tap one job only, raising the keyboard, so this screen has no
    tap-elsewhere-to-dismiss. The count earns its place because a selection may run past the
    column window and past the viewport, so the person cannot always see how much they hold.
 2. Selected cells take `color.term.selection` as the background, and the cell keeps its own
    foreground colour, per `R-32-144`.
 3. The platform edit menu, anchored at the selection, with the platform's own selection handles.
    `R-21-042` owns the mechanism and `R-31-08-22` owns the item set. There are exactly two items,
    `Copy` and `Select visible screen`, and the grid offers no `Paste`. The platform positions the
    menu, including above the keyboard, so this mockup fixes neither its place nor its shape. The
    mock draws it over the middle of the grid because that is where a selection usually sits.
    This is the one copy path on the phone (2026-09-09, `R-03-101`): the pane action sheet of
    `10-pane-actions.md` offers no `Copy the whole screen`. A long press of `R-30-301`'s 400 ms
    starts the selection and a drag extends it, per the gesture table of `docs/30-ux-spec.md`;
    `Select visible screen` then `Copy` copies the whole screen.
 4. The status word reads `paused` while the selection is live, and the strip stays. The emulator is
    frozen, per `R-21-041`, so the text `Copy` returns is the text that was selected. `rev` keeps
    moving, which is how the person sees the link is still alive while the paint is held.
 5. The key row is unchanged and is cropped from this mock. A selection does not disable it, and
    nothing on this screen loses its place while a selection is live.

## Wireframe, landscape

The landscape mock is 72 columns wide, because a landscape phone genuinely is wider. The
other mocks in this repository are 40 columns.

```text
+----------------------------------------------------------------------+
| <  * plugin v               c1-108    Overview       :               |
|      2 waiting   1 done              rev 41822                       |
+----------------------------------------------------------------------+
|   Passed!  Failed: 0, Passed: 412, Skipped: 3                        |
|                                                                      |
| * claude                                                             |
| | I will add the missing test for the socket reconnect path.         |
| |                                                                    |
| | > Read  socket_test.dart                                           |
| |   + 34 lines                                                       |
| |                                                                    |
| | > Edit  socket_test.dart                                           |
| |   Waiting for your approval:                                       |
| |   Allow write to socket_test.dart?                                 |
| |     1. Yes   2. Yes, always   3. No, tell claude what to do        |
|                                                                      |
| > _                                                                  |
|                                                                      |
|                                                                      |
|   esc  tab  ctrl  alt  < ^ v >  ins del  home end  pgup pgdn  144x50 |
+----------------------------------------------------------------------+
```

 1. Landscape uses one merged status bar instead of a separate portrait strip, so the grid gets every
    remaining row. The bar keeps the live bar and the existing overflow (amended 2026-09-10 per
    `R-03-116`: it kept a `Shortcuts` control between them until then), and the live bar sits
    before the title here too, per `R-03-121` and `R-31-08-28` (amended 2026-09-10). Its
    metadata column places the readable range above the revision beside the native labeled action.
    The title control of callout 10 and attention summary of callout 11 remain at the leading side
    (added 2026-09-09 per `R-03-113`). Amended 2026-09-11: the two count/unit pairs replace the
    equal-weight, middle-dot-separated caption and its extra `space.1` bottom gap.
    The same paragraph sits under the title, exactly at its text edge, with `space.3` between pairs.
    It uses `type.caption` and `color.fg.secondary` throughout; numbers alone take the existing
    `type.body.strong` font weight. It takes one scaled caption line, 16 logical pixels at normal
    text scale, with no extra bottom gap. The app bar alone draws its existing bottom hairline.
    The merged bar keeps its existing `size.bar.merged` minimum of 56 logical pixels and grows
    beyond it only as needed.
 2. Retired on 2026-09-14 per R-03-133: the key-row trailing size readout and pinch-size flash.
   The landscape app bar reports the size. Its metadata column keeps
    the `c<first>-<last>` range and `revision`; the live bar before the title carries connection
    state without a visible status word. The schematic range is `c1-108`.
    Readable mode shows the range at default 13px when the grid is wider than the landscape window.
    Overview fits the whole grid and hides the range. The action label is `Overview` in Readable mode
    and `Readable` in Overview mode. The merged bar has a 56dp minimum height and MAY grow for
    system text scale; no new unlabeled toolbar icon is added.
 3. There is no input field in either orientation (amended 2026-09-09 per `R-03-054`; until then
    a field appeared here on a grid tap or a key press). A tap on the grid raises the keyboard,
    and typing goes to the pane as it is typed, exactly as in portrait. Reading is still the
    rule in landscape: the keyboard is up only while the person wants it.
 4. The key row gains the nine keys that portrait holds in the expansion behind `...`, so it
    carries all fourteen on one line and needs no toggle. `09-key-row.md` owns which keys they
    are, the order they take and the column each one holds in portrait (amended 2026-09-10 per
    `R-03-117`: portrait hid four keys until then, and this row printed a `...` cap it does not
    need). The four arrows stay one cluster, and the three navigation pairs stay adjacent, because
    landscape has one row and no column to carry the pairing.
 5. The grid **background** MUST run the full width and under a display cutout. A grid **cell** MUST
    NOT: `R-21-039` requires the cell rectangle to come from the unobscured viewport, and landscape
    is where this matters most, because a cutout that sits in a top bezel in portrait sits in a side
    bezel in landscape, exactly where the columns are. `R-21-040` keeps the system edge gestures
    ahead of the horizontal pan.

## States

| State | Trigger | Screen shows |
| --- | --- | --- |
| Live | The subscription is up and the revision moves. | The live wireframe. The live bar is `color.status.ok`. |
| Loading, first paint | The route opened and the first `pane_frame` has not arrived, per `R-11-051`. | The grid shows one centred line, `Reading pane...`, in `type.mono.terminal` in `color.fg.secondary`. No spinner, and no skeleton grid, because a fake grid of grey bars looks like real output. The line appears only after 150 ms. |
| Loading, reconnecting | The relay link dropped and the app is retrying on the one schedule in `docs/22-platform-integration.md` `R-22-028`. | The last painted grid stays on screen, dimmed to `opacity.dim`. A strip under the app bar reads `Reconnecting... try 3` with `treat.warning`. The attempt number is exact and the total is not shown, because `R-22-028` owns the schedule. The key row is disabled and a keystroke sends nothing. The grid MUST NOT be cleared, because the last known screen is the most useful thing on the phone. |
| Empty | The pane exists and holds no output at all, for example a shell that has printed nothing. | The grid shows the real pane, which is a single cursor on line one. This is correct and needs no empty state text. |
| Empty, pane gone | The pane closed while the screen was open. It arrives as `tree_update` with the event `pane.closed`, per `R-11-046`. | The grid dims to `opacity.dim` and the platform's own alert dialog opens over it, per `R-03-119` and `R-31-08-27`: the title `This pane closed.` and one action, `Back to agents`, which is the default action. No body. The last painted content stays visible, dimmed, behind the dialog, because it is often the reason the pane closed (amended 2026-09-10 by the product owner, per `R-03-119`: until then the app drew a centred block over the grid). |
| Error, read failed | The Host answered `error` for `watch_pane` or `scroll_request`. | The grid dims and the platform's own alert dialog opens over it, per `R-03-119` and `R-31-08-27`: the title `Could not read this pane.`, the raw error text as the body in `type.mono.code` in `color.fg.secondary`, and two actions, `Back` and `Try again`, with `Try again` the default action. `Try again` closes the dialog and sends `watch_pane` once more; a second failure opens the dialog again with the new text (amended 2026-09-10 per `R-03-119`: until then a centred block; the title takes the dialog's own title style, and the `treat.error` glyph the block row named is not drawn). |
| Error, protocol mismatch | `herdr_protocol` in `host_info` is not 21, per `R-11-130`. | The grid dims and the platform's own alert dialog opens over it, per `R-03-119` and `R-31-08-27`: the title `This computer runs a different Herdr version.`, the body `Update Herdr on patrick-desk, or update this app.` in `type.body`, and one action, `Back`, which is the default action. See `R-02-008` (amended 2026-09-10 per `R-03-119`: until then a centred block). |
| Host in use | The relay answered `host_in_use` with close code `4006`. | The banner of `R-30-940`, drawn as `R-32-550` fixes it, sits under the app bar. The last painted grid stays, dimmed to `opacity.dim`, and the status word reads `in use`. The key row and the overflow actions that write are disabled, and a keystroke sends nothing. Scrolling and copying still work, because they are local. |
| Offline | The phone has no network, the relay is unreachable, or the computer is not connected to the relay. | The last painted grid stays, dimmed to `opacity.dim`, and the status word reads `offline`. The key row is disabled and a keystroke sends nothing. A strip with `treat.warning` names which of the three failures this is, per `R-30-808`, then reads `This is patrick-desk as it was at 14:02.`, per `R-30-805`, in `type.caption` in `color.fg.secondary`, `space.1` under the label and hanging under it, not under the glyph (amended 2026-09-08 by the product owner: the second line sat flush under the warning glyph). A tap on the strip routes to `/hosts/:hostId/diagnostics`, per `R-30-806`. Scrolling and copying still work, because they are local. |
| Truncated | The person reached the top of the fetched scrollback and `scroll_response` reported `truncated: true`. | A strip at the top of the grid reads `This is the most recent output. Older lines stay on the computer.` with `treat.warning`, per `R-31-08-19`. It is dismissible and returns on the next fetch whose top the person reaches. |

## Navigation

- In: a row tap on `06-agent-list.md`, a row tap on `07-notifications.md`, or a local notification
  tap, which routes through `/lock` first, per `R-30-511`. The pane belongs to the connected
  computer, per `R-30-946`.
- Out, back: the route that opened this screen. The app MUST return there, not to a fixed route.
- Out, overflow: mockup `10-pane-actions.md`.
- Not out, the title: the pane switcher sheet of the switcher wireframe opens in place, on the root
  navigator (added 2026-09-09 per `R-03-113` item 1, `R-31-08-25`). Opening it pushes no route and
  sends nothing. A tap on the current pane or on the scrim, or a drag down, closes it and nothing
  else happens.
- Out, a pane row in the switcher: `/hosts/:hostId/panes/:paneId` for the chosen pane **replaces**
  this route (`pushReplacement`), so the stack keeps one terminal, the new pane gets its own
  `watch_pane` and this one gets its `unwatch_pane`, and back from the new terminal returns to the
  route that opened the first one, per `R-30-031`.
- Not out, bank two: the one expansion of `09-key-row.md` opens in place under bank one. It is no
  route, it pushes nothing and it sends nothing on open, per `R-31-09-24`. History: the
  workstation's plugin actions left this app bar on 2026-09-08; a `Shortcuts` control held that
  slot from then to 2026-09-10, when `R-03-116` retired it with the palette it opened.
- Out, `Plugin actions` on the action sheet: `/hosts/:hostId/panes/:paneId/actions`, mockup
  `18-actions.md`, scoped to this pane (2026-09-09 per `R-03-055`). The app bar itself is
  unchanged: it carries no local control of its own, per the retired `R-31-08-24`.
- Out, `Back to agents`: `/hosts/:hostId/agents`, mockup `06-agent-list.md`. That is the one action
  the `pane gone` alert dialog of `R-31-08-27` offers, and it is the same back navigation the bar's
  back control makes, per `R-30-031`. `Back` on the `read failed` and `protocol mismatch` alert
  dialogs is that navigation too.
- Out, banner `Why`: `/hosts/:hostId/diagnostics`, mockup `13-connection.md`.
- Out, offline strip: `/hosts/:hostId/diagnostics`, mockup `13-connection.md`, per `R-30-806`.
- The Device watches exactly one pane at a time, so leaving this route sends `unwatch_pane` and ends
  the pane watch. See `R-02-013` and `R-11-050`.
- This screen carries no host chip, per `R-31-08-20`, so a switch to another computer starts
  somewhere else. It begins on `/hosts`, which the person reaches by going back. `R-30-948` owns
  that tap, `R-30-949` clears this route and drops this pane watch, and `R-31-08-21` forbids
  re-opening the same `paneId` on the chosen computer.

## Rules

- **R-31-08-01** The grid MUST be painted by a real terminal emulator that parses ANSI. The app MUST
  NOT render pane output as styled rich text, and MUST NOT strip escape sequences. See `R-02-014`.
- **R-31-08-02** The grid depends on `pane_frame` carrying unstripped ANSI, which `R-11-051` fixes
  with `format: "ansi"` and `strip_ansi: false`. This screen issues no read of its own: it sends
  `watch_pane` and paints the frames that follow. A read that omits either parameter is a Host
  defect, because `strip_ansi` defaults to `true`.
- **R-31-08-03** The app MUST repaint on every `pane_frame` whose revision is not older than the
  last painted one, and MUST drop an older frame. A frame that repeats a revision carries new
  text: the Host sends one only when the text changed (`R-10-070`), because Herdr does not move
  `revision` for an agent pane that repaints (`R-02-026`, measured 2026-09-03). An event that
  repeats a revision still costs no read on the Host, per `R-02-011` and `R-02-012`.
- **R-31-08-04** The grid size MUST be shown as an exact figure, columns first, for example
  `144x50`. There MUST be no tilde and no word such as `about`. Columns come from `rect.width` in
  `pane.layout`, and rows come from `scroll.viewport_rows`. Rows MUST NOT come from `rect.height`.
  See `R-10-024`.
- **R-31-08-05** The app MUST NOT clear the grid on a disconnect. The last known screen MUST stay
  visible and dimmed. This holds for every non live state on this screen: reconnecting, host in use,
  offline, pane gone, read failed and protocol mismatch. For the last three the dimmed grid stays
  visible behind the alert dialog of `R-31-08-27` (amended 2026-09-10 per `R-03-119`).
- **R-31-08-06** Reaching the bottom of the scrollback MUST resume the live follow on its own. The
  bottom is the Device's own scroll offset reaching zero, per `R-31-08-18`. The user MUST NOT have
  to press the pill.
- **R-31-08-07** `R-21-008` owns the sizing model, and this screen restates neither the model nor
  its reasoning. What the screen draws follows from it: the grid is exactly `rect.width` columns, it
  never reflows, and Readable mode starts at the saved ladder size, default 13px. A wide grid shows
  the horizontal window and range of `R-21-037`, including at the default size. The labeled `Overview`
  action enables whole-grid fit; its label becomes `Readable` and restores the current readable size.
  No layout choice this screen makes may resize the Host pane, per `R-21-036`.
- **R-31-08-08** A single tap on the grid MUST NOT send anything to the pane. It raises the
  keyboard only, per `R-03-054`, and the keystrokes that follow are the sends (amended 2026-09-09
  per `R-03-054`: the tap moved the focus to an input field until then). An accidental keystroke
  into a running agent is the worst outcome this screen can produce.
- **R-31-08-09** The first paint MUST arrive inside 400 ms on a working mobile network. The measured
  payload is about 8 KB of ANSI for a 50 row pane, about 1.2 to 1.9 KB compressed, so this is a
  network round trip, not a bandwidth problem. See `R-02-015` and `R-02-016`.
- **R-31-08-10** The grid MUST hold both offsets across an app background and resume, and across a
  rotation: the vertical scroll offset and the horizontal column window of `R-21-037`. It MUST NOT
  jump to the bottom on resume while the Device's own scroll offset is greater than zero, per
  `R-31-08-18`, and it MUST NOT reset to column 1 on a rotation. The route-local Overview state
  MUST survive rotation, reset for a new pane or restart, and MUST NOT change saved settings.
- **R-31-08-11** The app MUST NOT run a VT state machine of its own beyond painting SGR. `pane.read`
  returns a pre-rendered flat grid. Across all 14 live panes the payload held 3972 escape sequences,
  every one of them SGR, with no cursor motion, no erase, no scroll region, no OSC and no mode
  switch, even for a full screen TUI on the alternate screen. Herdr already ran the state machine.
  See `R-02-018`.
- **R-31-08-12** The app MUST count any SGR parameter outside the measured vocabulary `0`, `1`, `2`,
  `3`, `4`, `38;2`, `48;2`, `38;5`, `48;5`, and MUST surface that count on `13-connection.md`. A non
  zero count means Herdr changed upstream and rendering is about to break silently. See `R-02-018`.
- **R-31-08-13** This screen MUST NOT restate a rendering constant. The line height is `R-21-010`,
  the coalescing window is `R-21-021`, the render fallback threshold is `R-21-022`, the canonical
  name of the escape key is `R-21-019c`, the sizing model is `R-21-008`, the cell rectangle under a
  display cutout is `R-21-039`, the gesture priority is `R-21-040`, the frame freeze is `R-21-041`
  and the selection surface is `R-21-042`, all in `docs/21-terminal-rendering.md`. The reconnect
  schedule is `R-22-028`, per `R-30-809`. The keyboard inset is `R-30-519`.
- **R-31-08-14** This screen MUST NOT hold a read only mode, a permission check, or a grant badge.
  Version one pairs with full control, per `docs/03-product-decisions.md`. A control is disabled
  only when the link is down, which the offline and host in use states cover.
- **R-31-08-15** No glass material and no translucent material MUST be drawn over the terminal grid
  or behind it. The grid keeps the Selenized palette on both platforms, always, and a
  wallpaper-derived colour MUST NOT reach it. `R-33-055` owns the isolation, `R-33-060` owns chrome
  that overlaps the grid rect, and `R-30-153` owns the absolute colour the grid renders. This screen
  restates none of the three.
- **R-31-08-16** Every control this screen draws over the grid MUST be opaque. That is the jump to
  bottom pill of `R-32-540` and every strip this screen raises for reconnecting, host in use,
  offline and truncated output. Each one covers real output, so a person MUST be able to read the
  boundary between the control and the grid. A blurred sample of terminal pixels is not a boundary,
  and it would also carry pane colour into the chrome, which `R-33-060` forbids. The platform edit
  menu of `R-21-042` is out of scope here: the platform draws it, and `R-33-055` already keeps its
  material off the grid.
- **R-31-08-17** This screen MUST NOT carry the bottom navigation, per `R-30-022`, so it MUST NOT
  carry the create control either, and it MUST NOT gain a path to a split of its own. A split is
  `Split pane 1 right` or `Split pane 1 down` on the create menu of
  `docs/31-mockups/17-create.md`, reached from a screen that carries the create control (amended
  2026-09-09 per `R-03-101`: until then the pane action sheet of `10-pane-actions.md` held
  `Split right` and `Split down`, and this rule pointed at them).
- **R-31-08-18** The first number in the scroll readout MUST be the Device's own offset above the
  live bottom, counted in lines of fetched scrollback. It MUST NOT be `offset_from_bottom` from the
  pane object: that field reports where the person at the workstation scrolled the pane, and it does
  not move when this phone scrolls. The second number MUST be `max_offset_from_bottom` from
  `watch_ack`, which is also the only signal that the pane holds any scrollback at all, per
  `R-10-026`. The jump to bottom pill, `R-31-08-06` and `R-31-08-10` MUST all test the Device's own
  offset.
- **R-31-08-19** The truncated strip MUST NOT say that the computer dropped output. A scrollback
  read of a pane that holds scrollback returns `truncated: true` every time, because the window is
  capped, per `R-10-019` and `R-10-027`. So the strip MUST appear only when the person reaches the
  top of the fetched window, and it MUST report that the phone read the most recent output rather
  than that lines were lost. A strip that fires on every scrollback read, and blames the computer
  for a cap this app chose, teaches a person to distrust the screen.
- **R-31-08-20** This screen MUST NOT carry a host chip. The title budget belongs to the tab and the
  pane, and exactly one computer is connected, so the app bar has nothing to disambiguate. Every
  state that reports a lost or a blocked link MUST name the computer instead, because that is the
  moment a person needs to know which one: the offline strip, the protocol mismatch alert dialog of
  `R-31-08-27` (amended 2026-09-10 per `R-03-119`: was a block) and the banner of `R-30-940` each
  name it, using `host_name` from `host_info`, per `R-11-130`.
- **R-31-08-21** `R-30-946` forbids this route for a computer that is not connected, and `R-30-949`
  clears it on a switch. This screen owns one consequence: after a switch the app MUST NOT open the
  same `paneId` on the chosen computer. A pane id is unique inside one Herdr session only, so the
  same id can name a different pane, or no pane, on the computer the person switched to.
- **R-31-08-22** Terminal selection MUST use the platform's own selection surface and handles, per
  `R-21-042`. This screen MUST NOT draw a bar of its own for a selection action. The item set is
  exactly two: `Copy`, and `Select visible screen`. The grid MUST NOT offer `Paste`, because the
  grid is read only and the write path to the pane is the keyboard the grid raises, per
  `R-03-054`, whose paste lands in the pane through `R-21-018`. The command MUST NOT be named
  `Select all`: it selects the visible screen and not the pane's scrollback, and a name that
  promises more than the command delivers is a defect on the one screen whose whole purpose is being
  exact. The selection app bar keeps the cancel `x` and the count `3 lines selected`, and neither is
  an action the selection surface already offers.
- **R-31-08-23** The status word MUST read `paused` whenever the paint is held, per `R-21-041`. That
  is two cases: a live selection, and a Device scroll offset greater than zero. The grid MUST NOT be
  dimmed in either case, because `R-31-08-05` gives dimming one meaning on this screen, a lost or a
  blocked link, and a held paint is neither. `rev` MUST keep moving while the paint is held, because
  it is the one readout that shows the link is still alive.
- **R-31-08-24** Retired 2026-09-10 per `R-03-116`. It required this app bar to carry a local
  `Shortcuts` control that opened the Shortcuts palette of the retired `R-31-09-22` in place, sent
  no message of any kind, and was disabled whenever the keys that send were disabled. The control
  and the palette are both gone: the product owner found that the `...` cap of the key row and the
  app bar's keyboard control gave two different results, and two controls that expand the keys and
  show two different things is inconsistent. The key row has exactly one expansion, `R-31-09-24`,
  and a control chord is typed there, per `R-31-09-08`. The bar keeps the back control, the title
  control, the live bar and the `Pane actions` overflow; the slack this retirement leaves under the
  `R-32-512` ceiling of three trailing controls MUST stay empty. The app bar MUST NOT carry the
  `Computer actions` control either, and MUST NOT push an actions route from the bar: `18-actions.md`
  is reached from the pane action sheet. No later rule reuses this id. This id stays reserved, so
  an old citation still resolves.
- **R-31-08-25** (added 2026-09-09, per `R-03-113` item 1) The app bar title MUST be the
  platform's own button, per `R-03-059`, and a tap on it MUST open the pane switcher sheet: the
  bottom sheet of `docs/32-design-language.md` section 7.16 on both platforms, per `R-33-037`, on
  the root navigator, listing the live tree of `tree_snapshot` as three tiers, workspace, tab and
  pane, in the Host's own order, per `R-11-044`. The title MUST carry the `expand_more` glyph of
  `R-32-401` after its text while it is a control, and MUST be the plain heading with no glyph
  before the first `tree_snapshot` lands. The pane on screen MUST be the one selected row, the
  `color.accent.soft` wash and the semantics state `selected`. A tap on another pane MUST close
  the sheet and **replace** this route with `/hosts/:hostId/panes/:paneId` for that pane, never
  push a second terminal, so the Device still watches exactly one pane, per `R-11-050`, and back
  still returns to the route that opened the first terminal, per `R-30-031`. A tap on the current
  pane MUST only close the sheet. Every pane row MUST be one line and 48 high. An agent row MUST
  show its kind, then `space.2`, then its pane name, with the state word trailing on the same
  baseline; it MUST carry the full-height state bar of `R-03-100`. A shell row MUST show the
  `A pane` glyph, pane name, then `space.2` and its optional `title` on that baseline
  (amended 2026-09-10 per `R-03-115`). The sheet MUST NOT offer a split, zoom or rename, per
  `R-03-101`, and MUST NOT send anything to the computer or change the route when it opens.
- **R-31-08-26** (added 2026-09-09, per `R-03-113` item 4; amended 2026-09-11) The app bar MUST
  carry the attention summary as the second line of the title control of `R-31-08-25`, directly
  under the name on the name's text edge and inside the same button, for example
  `2 waiting   1 done`. It MUST NOT take a `bottom` slot or any row of its own under the bar
  (amended 2026-09-11 by the product owner, who rejected the separate band; until then the line
  took `AppBar.bottom` and `CupertinoNavigationBar.bottom`). The switcher glyph MUST stay on the
  name's line. The line MUST use `type.caption` in `color.fg.secondary`; the numbers alone MUST
  take the `type.body.strong` weight and the words MUST keep the caption weight. The two
  count/unit pairs MUST sit `space.3` apart with no separator glyph (amended the same day; until
  then a middle dot separated two equal-weight halves). The first number MUST count agent panes
  whose `agent_status` is `blocked`; the second MUST count agent panes whose status is `done`.
  Both counts MUST cover the whole live tree of the connected computer and MUST change with
  `tree_update`. The line MUST be absent while both numbers are zero. It MUST be words only: no
  state mark, no bar, no dot, no badge and no state colour, per `R-03-058` and `R-03-100`. Those
  state bars belong on the switcher rows and the `06-agent-list.md` rows. The two lines MUST fit
  the platform's own bar height, so the 44 row of `R-33-076` MUST NOT grow. Landscape MUST use
  the same title control inside the merged bar, which keeps its `size.bar.merged` minimum.
- **R-31-08-27** (added 2026-09-10, per `R-03-119`) The `pane gone`, `read failed` and
  `protocol mismatch` states of the States table MUST be the platform's own alert dialog, and the
  app MUST NOT draw a block of its own over the grid for them. On Android the dialog MUST be the
  Material `AlertDialog`; on iOS it MUST be the `CupertinoAlertDialog` with `CupertinoDialogAction`
  actions, and the default action MUST set `isDefaultAction`. The screen fixes only the title, the
  body and the actions named in the States table, and the platform component places them, per the
  role rules of `R-33-074`; the default action is listed last, so it is the trailing action on both
  platforms. The dialog MUST NOT close on a barrier tap or on a back gesture: its actions are the
  only way out. The screen MUST open the dialog once when the state begins, after the frame that
  first shows the state, and MUST close it when the state ends, for example when `Try again`
  succeeds or the link drops; the next entry into one of the three states opens it again. The grid
  under the dialog stays dimmed and MUST NOT be cleared, per `R-31-08-05`. The title is
  `type.heading` and the body `type.body`, both `color.fg.primary`; a raw error in the body is
  `type.mono.code` in `color.fg.secondary`; the default action is `type.body.strong` and the other
  action `type.body`, both `color.fg.primary`. `R-30-005` as amended by `R-03-119` permits these
  three dialogs and the destructive confirmation, and nothing else.
- **R-31-08-28** (added 2026-09-10, per `R-03-121`) The live bar of callout 3 MUST sit before the
  title, on the app bar's leading side, `space.2` before the title text, on both platforms and in
  the landscape merged bar: the bar, the gap, then the title, the way every list row puts its
  state bar in the leading slot before its name (`R-32-592`, `R-32-597`, the `Live bar` row of
  `docs/32-design-language.md` section 7.3). It MUST NOT sit among the trailing actions. The bar
  keeps its own semantics node with the connection word (`R-32-511`), so the traversal of
  `R-30-719` reads the bar, then the title. The attention summary of `R-31-08-26` MUST still start
  on the title text edge: on Android and in landscape its start inset adds the bar's
  `border.attention` width and the `space.2` gap to the title's own inset.

- **R-31-08-29** The live status word MUST show the measured round-trip time as `N MS`,
  not `LIVE`, per `R-30-969`. Until the first sample arrives it MUST show `LIVE`.
  Paused, reconnecting, offline, and other non-live states MUST retain their existing words.
  `R-11-250` owns ping/pong measurement. A terminal frame MUST NOT supply the RTT sample.

## Accessibility

- Touch target: the back control, the title control, the overflow `:`, the
  labeled `Overview`/`Readable` action, the jump to bottom pill and the selection app bar cancel
  each meet the minimum target of `R-30-290` and `R-30-740`; the title control is the platform's
  own button and takes the platform's own hit area. The native mode button is at least 48dp in
  portrait and 56dp in the landscape merged bar. The portrait status strip is normally 48dp and MAY
  grow for system text scale. Metadata MAY wrap at narrow widths. The pill is smaller than its target,
  which `R-30-291` permits. The selection handles and edit menu items are the platform's own, per
  `R-21-042`, so the platform owns their targets. In the switcher, a workspace header and a pane row
  are each at least `size.target.min` high; a tab header is not a target.
- Contrast: `color.term.fg` on `color.term.bg` is a passing row in `R-32-150`, per `R-30-151`. A
  colour that the remote program chose is out of scope, per `R-30-152` and `R-30-722`, and
  `R-32-142` records the one payload slot that misses the indicator floor. The status strip pair is
  `color.fg.secondary` on `color.bg.raised`, a passing row in `R-32-150`, per `R-30-720`. The jump
  pill and the app bar bottom edge each carry `color.border.strong`, per `R-32-112` and `R-32-113`,
  so neither is identified by a fill alone, and each stays opaque over the grid, per `R-31-08-16`.
- Screen reader: the grid MUST be exactly one semantics node, per `R-30-710`, whose label is the
  visible screen as plain text, per `R-30-711`. The label MUST carry every row at its full
  `rect.width`, not the columns the screen currently holds, per `R-21-037`: a screen reader cannot
  pan, so a label clipped to the column window would hide content with no way to reach it. It MUST
  be read only and multiline and MUST NOT be a live region, per `R-30-712`. The way to hear output
  on demand is `Read the last 20 lines` in the pane action sheet, per `R-30-713` and `R-31-10-06`.
  When the agent on this pane reaches `blocked` or `done`, the app MUST announce exactly one
  sentence, per   `R-30-714`. The live bar MUST carry the connection word as its label, per
  `R-30-716`, and the overflow MUST carry `Pane actions`, per `R-30-717`. The title control is one
  node, `<title>, switch pane`, a button
  (added 2026-09-09 per `R-03-113`). The attention summary is plain text and is not a live
  region: its two numbers are read where the focus lands on them, and the one announcement of
  `R-30-714` already says when this pane's agent reaches `blocked` or `done`.
- Screen reader, the switcher: the sheet is one dialog semantics scope with the heading
  `Switch pane` as its header, and it traps the focus and returns it to the title control, per
  `R-30-719` and `R-32-546`. A workspace header speaks `<name>, <N> panes`, a button, and
  `expanded` or `collapsed`, per `R-32-568`. A tab header speaks its title. A pane row is one node
  that speaks `agent kind, state, pane`, for example `claude, Blocked, main`, and the current pane
  adds the state `selected`; a shell row speaks `pane, title`, for example `pane 3, zsh`. The grab
  handle is excluded, per `R-32-546`.
- Focus order: per `R-30-719`, back control, live bar, the title control, overflow
  (amended 2026-09-10 per `R-03-121`: the live bar moved before the title),
  then the grid as one node, then the status strip and its `Overview`/`Readable` action, then the
  key row left to right, then bank two if open (amended 2026-09-09 per `R-03-054`: the input field
  and the send control that followed it are gone; amended 2026-09-10 per `R-03-116`: the
  `Shortcuts` control and the palette that trapped the focus are gone). The attention summary
  follows the title control as plain text. The pane action sheet traps the focus and returns it to
  the overflow. The pane switcher traps the focus and returns it to the title control.

## Open questions

None.

## Sources

- `docs/32-design-language.md` - the app bar and its live bar `R-32-510` and `R-32-511`, the state
  bar `R-32-592` of section 7.29, the status strip `R-32-542`, the jump pill `R-32-540`, the
  blocking banner `R-32-550`, the terminal palette `R-32-140`, the selection rule `R-32-144`, the
  contrast table `R-32-150`, the icon map `R-32-401`, the bottom sheet of section 7.16 with
  `R-32-546`, the section 7.4 list row and its selected wash, the tier-1 header `R-32-563` to
  `R-32-568`, and the shell row `R-32-597`.
- `docs/30-ux-spec.md` - gesture model, status model, the offline behaviour `R-30-805` to
  `R-30-808`, the `host_in_use` banner `R-30-940`, the per-Host route scope `R-30-946`, the switch
  tap `R-30-948`, what a switch discards `R-30-949`, the one reconnect schedule rule `R-30-809`, the
  keyboard inset `R-30-519`, and the terminal accessibility rules `R-30-710` to `R-30-719`.
- `docs/02-herdr-probe-results.md` - measured socket behaviour, event payloads, payload sizes.
- `docs/21-terminal-rendering.md` - emulator package, write path, the sizing model `R-21-008`, the
  Host pane geometry rule `R-21-036`, the column window `R-21-037`, the widget parameters
  `R-21-038`, the cell rectangle under a display cutout `R-21-039`, the gesture priority `R-21-040`,
  the frame freeze `R-21-041`, the selection surface `R-21-042`, `R-21-010` line height, `R-21-021`
  coalescing, `R-21-022` render fallback, and `R-21-019c` the canonical `Esc` name.
- `docs/22-platform-integration.md` - `R-22-028`, the one reconnect schedule.
- `docs/10-herdr-integration.md` section 4.10 and `R-10-024` - `pane.layout` rects are measured in
  character cells, so `rect.width` is the column count and `rect.height` is not the row count. Also
  the scrollback affordance `R-10-026` and the 1000 line window `R-10-019` and `R-10-027`.
- `docs/03-product-decisions.md` - full terminal control for a paired phone, one phone per computer,
  one active computer per phone in `R-03-043` and `R-03-044`, the live terminal `R-03-054`, the
  pane-scoped plugin actions `R-03-055`, `R-03-101`, which makes grid selection the copy path,
  `R-03-058` and `R-03-100` on one mark per fact, `R-03-059` on platform buttons, `R-03-108` on
  the platform's draggable sheet, `R-03-113` items 1 and 4, the pane switcher and the
  attention summary imported from `deex2/herdroid` on 2026-09-09, and `R-03-119`, the platform
  alert dialog for a terminal state that ends the work.
- `docs/11-relay-protocol.md` - `watch_ack` and `pane_frame` in `R-11-049` and `R-11-051`, the
  `unwatch_pane` rule `R-11-050`, the `tree_snapshot` fields `R-11-044`, the `scroll_response`
  fields in section 4.11, the error `host_in_use`, and the close code `4006`.
- `docs/31-mockups/07-notifications.md` - the pane display name `R-31-07-08`.
- `docs/31-mockups/06-agent-list.md` - the host chip that opens a chooser from a title, the
  three-tier Workspace axis the switcher mirrors, and the agent-row reading of `agent_status`.
- `docs/31-mockups/09-key-row.md` - every key, both banks and the one expansion of `R-31-09-24`,
  which holds the keys this bar no longer offers a second way to.
- `docs/33-platform-chrome.md` - the terminal isolation invariant `R-33-055`, the treatment of
  chrome that overlaps the grid rect `R-33-060`, the platform pop gesture `R-33-070`, which
  `R-21-040` builds on, the bottom sheet on both platforms `R-33-037`, the dialog role rules
  `R-33-074` that `R-31-08-27` follows, and the 44 navigation bar row `R-33-076`.
