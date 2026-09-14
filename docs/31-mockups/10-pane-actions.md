# 10 - Pane action sheet

| Field | Value |
| --- | --- |
| Route | `/hosts/:hostId/panes/:paneId`, modal layer |
| Surface | Device, Android and iOS |
| Spec | `docs/30-ux-spec.md` |

Every action is available on any paired phone. The sheet has no permission check or grant badge.
It offers plugin actions, two split directions and `Close pane`, plus a row for the screen reader.
`R-03-101`, amended 2026-09-14 per `R-03-134`, restores the split rows.
The sheet still excludes the prompt composer, zoom, rename and whole-screen copy.
The terminal accepts input and supports text selection, per `08-terminal.md`.

## Wireframe

```text
+--------------------------------------+
|   opaque surface over the grid       |
+--------------------------------------+
|                 ====                 |
| plugin / pane 1                      |
| claude  -  working 12s               |
+--------------------------------------+
| Plugin actions                     > |
| Split right                          |
| Split down                           |
+--------------------------------------+
| Close pane                           |
+--------------------------------------+
|                Cancel                |
+--------------------------------------+
```

## Wireframe, screen reader on

```text
+--------------------------------------+
|   opaque surface over the grid       |
+--------------------------------------+
|                 ====                 |
| plugin / pane 1                      |
| claude  -  working 12s               |
+--------------------------------------+
| Plugin actions                     > |
| Split right                          |
| Split down                           |
+--------------------------------------+
| Read the last 20 lines               |
+--------------------------------------+
| Close pane                           |
+--------------------------------------+
|                Cancel                |
+--------------------------------------+
```

This is the tallest the sheet ever is: five rows and `Cancel`. `R-31-10-09` holds what happens
when that does not fit.

## Wireframe, the close confirmation

```text
+--------------------------------------+
|   opaque surface over the grid       |
+--------------------------------------+
|  +--------------------------------+  |
|  | Close pane 1?                  |  |
|  |                                |  |
|  | Anything running in this pane  |  |
|  | stops, and its scrollback is   |  |
|  | gone.                          |  |
|  |                                |  |
|  | the cancelling action and      |  |
|  | Close pane, placed by the      |  |
|  | platform, per R-33-074         |  |
|  +--------------------------------+  |
+--------------------------------------+
```

The sheet is gone in this wireframe, not behind the dialog. `R-31-10-01` holds why.

## Callouts

1. The surface over the grid. It MUST be opaque, per `R-31-10-10`. It is not a scrim at
   `opacity.dim`: this sheet opens over the terminal, and a translucent surface MUST NOT share a
   rectangle with the grid. A tap on it closes the sheet.
2. Sheet. The bottom sheet of `docs/32-design-language.md` section 7.16. It rises over
   `motion.duration.base` with `motion.curve.enter`. It is resizable, and `R-31-10-09` holds its
   height and its scrolling.
3. Grab handle. The handle of the same anatomy, centred at the top, drawn `====` here. A drag down
   closes the sheet, and a drag up resizes it. It MUST stay visible, per `R-31-10-09`.
4. Header. The pane's `label` from `tree_snapshot` in `type.body.strong`. A pane the phone created
   is unnamed, per `R-30-954`, and `R-31-07-08` owns how an unnamed pane reads. Then `agent_kind`
   and `status` from the same message, in `type.caption` in `color.fg.secondary`. The age after the
   status is measured from `status_at`, which `R-11-224` allows to be absent. When it is absent the
   header draws the status with no age. The second line is absent when the pane holds no agent.
5. `Plugin actions`. Present on every pane. Added 2026-09-09 per `R-03-055`: a plugin acts on a
   pane, so the person reaches the plugin actions of the computer from the pane, and this row is
   the one entry to `18-actions.md`. It routes to `/hosts/:hostId/panes/:paneId/actions` with this
   pane as the scope. It carries a `>` chevron, per `R-33-072` point 5, which permits one on a
   sheet action row: the chevron marks a row that opens a screen instead of acting at once, and
   this is the only row that carries one, so the chevron keeps one meaning. Its glyph is the one
   `R-32-401` names for `Host actions`. It is not one of the plugin actions: `R-31-18-02` keeps
   those off this sheet, and one row that opens their screen is what stands in their place. It is
   a local row: it stays enabled in the `Host in use` and `Offline` states, because the screen it
   opens reports the link state itself, per `R-30-807`. Until 2026-09-09 this row was callout 5a,
   beside the `Send a prompt` row that `R-03-101` retired.
6. `Close pane` calls `pane.close`, after the confirmation of callout 10, and it is the only row
   that destroys work. Label uses `treat.destructive`. It sits alone in its own group,
   separated by a divider, so a mis-tap does not reach it from the group above. It is disabled in
   the `Host in use` and `Offline` states, per `R-30-807`.
7. `Read the last 20 lines`. Present only while the platform screen reader is on, which
   `MediaQuery.accessibleNavigationOf(context)` reports. It announces the last twenty non empty
   lines of the visible grid through the mechanism `R-30-742` names, with `TextDirection.ltr`,
   then closes the sheet. It sends nothing to the pane and changes nothing on the computer. It
   sits in its own group, after the split rows and before `Close pane`.
8. `Cancel`. The cancel row of section 7.16, centred, label `type.body.strong` in
   `color.fg.secondary`. It MUST stay visible, per `R-31-10-09`.
9. Row. The sheet action row of section 7.16. Label `type.body`. Each row leads with its own
   glyph of `R-32-401` at `size.icon.md` in `color.fg.primary`, gap `space.3`, and rows inside
   one group carry no divider: the group divider of section 7.16 sits above every group and
   above `Cancel`, the way the wireframe draws its bands (amended 2026-09-08 by the product
   owner: the app drew the labels in `type.body.strong`, a divider under every row, and `Close
   pane` in red text; the craft pass returned each to its owning rule).
10. The close confirmation. It is the platform dialog of `R-33-074`, and this screen fixes only the
    five things that rule permits. `R-31-10-01` holds the wording and the roles.

## Which actions destroy something

Three rows change the computer. Only `Close pane` destroys work and requires confirmation.

| Action | Effect on the computer | Confirmation |
| --- | --- | --- |
| `Split right`, `Split down` | Send `split`, per `R-31-10-12`. | No. |
| `Close pane` | The pane and its scrollback are gone. Anything running in it stops. | Yes, the dialog of `R-33-074`, with the title, the body and the roles that `R-31-10-01` fixes. |
| `Plugin actions`, `Read the last 20 lines` | Nothing. One opens a screen, the other speaks on the phone. `Plugin actions` opens the screen of `18-actions.md`, and that screen owns what a tap there does. | No. |

Copying pane text is not a row here. A long press on the grid starts a selection, and `Copy` in the
platform's own edit menu copies it, per `R-31-08-22` and the gesture table of `docs/30-ux-spec.md`.

## States

| State | Trigger | Sheet shows |
| --- | --- | --- |
| Default, agent pane | Opened over a pane that holds an agent. | The first wireframe. |
| Default, plain pane | Opened over a shell pane. | The same sheet without the second header line. |
| Screen reader on | `MediaQuery.accessibleNavigationOf(context)` is true. | The second wireframe, with `Read the last 20 lines` in its own group. |
| Too tall to fit | The rows, the header and `Cancel` need more than the safe height, because the phone is small, the text scale is large, or the keyboard the grid raised is still up. | The action region scrolls and the handle, the header and `Cancel` stay put, per `R-31-10-09`. |
| Host in use | The relay answered `host_in_use`. | `Split right`, `Split down` and `Close pane` are disabled at `opacity.disabled`. `Plugin actions` and `Read the last 20 lines` stay enabled, because both are local and `R-30-807` disables only what needs the network. A line under the header carries the words of `R-30-940`, because the opaque surface of `R-31-10-10` covers that banner. |
| Offline | No route to the relay. | The same disabled set as the row above. A line under the header carries the words of `R-30-808` and routes to `/hosts/:hostId/diagnostics`, per `R-30-806`. |
| Confirming | `Close pane` was tapped. | The sheet closes and the dialog of `R-33-074` opens, as the last wireframe draws. |
| Loading | A split is in flight. | Show a spinner on that row. Disable all actions and dismissal until the result, per `R-31-10-13`. |
| Created | The Host acknowledges the split with `result_id`. | Close the sheet and replace the terminal view, per `R-31-10-14`. |
| Error | The Host refuses the split. | Keep the sheet open and show the refusal, per `R-31-10-13`. |
| Outcome unknown | No acknowledgement arrives. | Stop the spinner and allow dismissal. Reconcile before another split, per `R-31-10-13`. |

## Navigation

- This sheet is a modal layer on a per-Host route, so it names the connected computer, per
  `R-30-946`.
- In: the overflow `:` on `08-terminal.md`, or a long press on a row of `06-agent-list.md`.
- Out, `Split right` or `Split down`: replace the terminal view after acknowledgement, per
  `R-31-10-14`.
- Out, `Plugin actions`: `/hosts/:hostId/panes/:paneId/actions`, mockup `18-actions.md`, with this
  pane as the scope (added 2026-09-09 per `R-03-055`).
- Out, `Read the last 20 lines`: the sheet closes after the announcement starts.
- Out, `Close pane`: the sheet closes and the dialog opens. Whichever action the person chooses,
  the sheet does not come back, and the focus returns to the control that opened it, per
  `R-32-546`.
- Out, back or a tap outside or drag down: the sheet closes and nothing happens.

## Rules

- **R-31-10-01** `Close pane` MUST ask for a confirmation, and that confirmation MUST be the
  platform dialog of `R-33-074`. This screen fixes five things and no more: the title
  `Close pane 1?`, the body `Anything running in this pane stops, and its scrollback is gone.`, the
  destructive verb `Close pane`, that `Close pane` is the destructive action, and that the other
  action cancels. This screen MUST NOT name the cancelling title, an action order, a button
  position or an initial focus target, because `R-33-074` places all four and the two platforms
  place them differently. The sheet MUST close before the dialog opens, so that exactly one sheet
  is ever on screen, per `R-32-545`, and so that the dialog does not fight the sheet focus trap of
  `R-32-546`. Every other action MUST NOT ask, because no other action destroys work.
- **R-31-10-02** Retirement reversed 2026-09-14 per `R-03-134`.
  A successful split MUST fire `haptic.commit` and close the sheet over `motion.duration.base`.
  `R-31-10-14` owns the route after the acknowledgement.

- **R-31-10-03** Amended 2026-09-14 per `R-03-134`: the sheet MUST show at most five action rows,
  excluding `Cancel`.
  The rows are `Plugin actions`, `Split right`, `Split down`, `Close pane`, and the optional
  screen-reader row.
  The screen-reader row keeps its separate group before `Close pane`.
  Plugin actions stay on their separate screen, per `R-31-18-02`.

- **R-31-10-05** The sheet MUST NOT offer a font size control. Font size lives in Settings, because
  it is a preference, not a pane action.
- **R-31-10-06** The sheet MUST offer `Read the last 20 lines` while the platform screen reader is
  on. It MUST announce the last twenty non empty lines of the visible grid through the mechanism
  `R-30-742` names, with `TextDirection.ltr`, with every escape sequence removed and every trailing
  space stripped. It MUST send nothing to the pane. This is the intended way to hear pane output,
  because `R-30-712` forbids a live region on the grid.
- **R-31-10-07** The sheet MUST NOT hold a read only mode, a grant badge, or a per action permission
  line, per `R-03-051`.
- **R-31-10-08** Every row that acts on the computer MUST map to an action that `R-11-202` lists,
  and the sheet MUST NOT offer any action that `R-11-204` excludes. A row with no method behind it
  MUST NOT be drawn, because a person taps it expecting a workstation to answer. A mapped action
  whose parameters cannot express what the row promises MUST NOT be drawn either, which is what
  retired the resize row. The split rows map to `split`; `Close pane` maps to `close`.
- **R-31-10-09** The sheet MUST NOT be asked to draw more than it can fit. Its height MUST be
  bounded by the safe area and, while a keyboard the grid raised is still up, by the keyboard inset
  that `R-30-519` owns (amended 2026-09-09 per `R-03-101`: until then the rename field inside the
  sheet raised the keyboard). The action region between the header and `Cancel` MUST scroll inside
  that bound. The grab handle, the header and `Cancel` MUST stay visible at every height and MUST
  NOT scroll away, because the handle and `Cancel` are the two ways out. The sheet MUST be resizable
  by the handle and by a scroll of its own content, which is the behaviour both platforms already
  give a modal sheet, so the app MUST NOT hand-roll a detent. `R-31-10-03` caps the content; this
  rule caps the height. The two are different limits and both apply.
- **R-31-10-10** Every surface this sheet draws over the terminal grid rectangle MUST be opaque and
  MUST take the fixed Herdr chrome values, per `R-33-060`. The surface behind the sheet MUST
  NOT be `color.bg.base` at `opacity.dim`, and MUST NOT sample grid pixels, per `R-33-057`.
  `R-33-055` outranks every other rule in that document, so the sheet anatomy of section 7.16 does
  not win here. This is the same requirement `R-31-08-16` puts on every control the terminal screen
  draws over the grid, and the sheet is one more such control.
- **R-31-10-11** `Close pane` is non-idempotent: a close ends a pane, and a second tap after a lost
  acknowledgement can end the pane that took its place. So the sheet MUST NOT offer a one tap retry
  after an unknown outcome, and `R-30-518` owns that state and the reconciliation it requires.
  `R-30-518` requires each screen to name the field that answers its own action, and for
  `Close pane` that field is the absence of that `pane_id` from `panes[]`. The sheet is gone before
  `pane.close` is sent, per `R-31-10-01`, so the screen that reads that field is `08-terminal.md`
  under the dialog: a `pane.closed` `tree_update` raises its `pane gone` state, per `R-11-046`, and
  that state is the answer. The sheet draws no `Check now` of its own. Amended 2026-09-09 per
  `R-03-101`: until then this rule named four fields, one per row of the layout group and one for
  `Rename pane`, and `## Retired rules` holds them.

- **R-31-10-12** Added 2026-09-14 per `R-03-134`: the sheet MUST offer `Split right` and `Split
  down` after `Plugin actions`.
  This reverses their retirement on 2026-09-09. The create menu MUST NOT offer them.
  Each row MUST send the existing `split` Host action with this pane as the target.
  The directions are `right` and `down`, respectively. The glyphs are
  `Symbols.splitscreen_right_rounded` and `Symbols.splitscreen_bottom_rounded`.
  Neither row destroys work, so neither MUST ask for confirmation.
- **R-31-10-13** A split MUST use the same loading, disabled, offline and refusal behaviour as
  `Close pane`, without its confirmation.
  While the request is pending, only its row shows a spinner. All actions and dismissal MUST be
  disabled.
  A Host refusal MUST keep the sheet open and show the error under `R-30-803` and `R-30-804`.
  Offline and `Host in use` MUST disable both split rows, per `R-30-807`.
  An unknown outcome MUST stop the spinner and restore dismissal, per `R-30-518`.
  The sheet MUST NOT offer an immediate repeat of a split whose outcome is unknown.
  Reconciliation checks for a new `pane_id` in the same tab's `panes[]`.
- **R-31-10-14** The sheet MUST wait for `host_action_ack` with the new pane id in `result_id`.
  After success, the sheet MUST close and the terminal MUST replace its route with
  `/hosts/:hostId/panes/:newPaneId`.
  The back gesture MUST return to `Agents`, not the old pane. The screen MUST show one terminal,
  never adjacent terminals.
  The app MUST send one `tree_request` after the acknowledgement, as the create flow does.

## Retired rules

| Rule | Why |
| --- | --- |
| `R-31-10-04` | **Retired.** It required a warning line and the exact column and row numbers on `Match this pane to my screen`. That action left version one, so the rule has no subject. No later rule reuses this id. See below. |
| `Send a prompt to <agent>` | **Retired row 2026-09-09 per `R-03-101`, not a rule id.** It opened the agent prompt composer of `11-prompt-composer.md`, which is retired with it. The live terminal of `R-03-054` is the prompt: a person types to the agent in the pane. |
| `Zoom this pane`, `Rename pane` | **Retired rows 2026-09-09 per `R-03-101`, not rule ids.** These desktop layout actions remain excluded. `R-11-202` keeps the protocol mappings. |
| `Copy the whole screen` | **Retired row 2026-09-09 per `R-03-101`, not a rule id.** It copied the visible text without ANSI codes. The copy path is text selection in the grid: a long press starts it and `Copy` in the platform's own edit menu copies it, per `R-31-08-22` and `R-21-042`. |
| `Show in tree` | **Retired row, not a rule id.** The local-group row routed to the `Panes` tree. The product owner dropped that destination on 2026-09-04 (`R-30-021`), so the row has no target. No rule carried it; `R-31-10-03`'s cap fell from nine to eight. |

`Match this pane to my screen` is removed from version one, and no rule replaces it. Three reasons:

1. It cannot be built as it was specified. It sent `resize` with `columns` and `rows`, which
   `R-11-202` maps to the Herdr `pane.resize` method. Section 4.3 of `docs/21-terminal-rendering.md`
   records that method's real parameters, read from the live schema: a `direction` from four values
   and a float `amount`. There is no column count and no row count, and no other method sets them.
   Section 4.2 of the same document already rejected this approach for the same reason.
2. It is hostile to the person at the workstation, and this reason would stand even if the method
   could do it. `R-30-952` already forbids a phone from stealing focus, because somebody may be
   sitting at that desk. Reshaping their layout is the larger intrusion.
3. It fights the sizing decision it sits inside. `docs/21-terminal-rendering.md` makes the phone
   adapt to the Host grid, so an action that makes the Host grid adapt to the phone works against
   the screen that opens this sheet.

An approximation was considered and rejected: repeated `resize` calls in one direction still change
the workstation layout, and still cannot land on an exact column count.

Two consequences land outside this file, and `Main` routes them. `R-11-202` keeps its `resize`
mapping, and this screen no longer uses it. The icon map in `docs/32-design-language.md` holds a
`Match this pane to my screen` row, and two implementation checklists name the action.

## Accessibility

- Touch target: every row and `Cancel` are the heights section 7.16 fixes, so all clear the minimum
  in `R-30-290` and `R-30-740`. The grab handle is smaller than its target, which `R-30-291`
  permits. A large text scale MUST NOT shrink any of them, per `R-30-741`, so a large scale makes
  the sheet scroll rather than shrink, per `R-31-10-09`.
- Contrast: a row label is `color.fg.primary` on `color.bg.raised`, a passing row in `R-32-150`, per
  `R-30-720`. `Close pane` uses `treat.destructive`, which carries the red in the icon alone and
  never in the text or a leading bar, per `R-30-143` and `R-32-527` (amended 2026-09-09 by the
  product owner per `R-03-058`: the emulator drew a red bar beside the red glyph, two marks for
  one fact, and under `R-03-100` a leading bar is a state). A text action inside this sheet
  MUST NOT use `color.accent.text`, which `R-32-124` forbids on `color.bg.raised`.
- Screen reader: `Read the last 20 lines` is the pane output action of `R-30-713`. The grab handle
  MUST be excluded from the semantics tree. `Cancel` MUST carry the label `Cancel`, per `R-30-717`.
  The destructive row MUST announce `Close pane, destructive` so the risk is spoken and not only
  coloured, per `R-30-141`. The scrolled state MUST NOT hide a row from the semantics tree: a
  screen reader MUST be able to reach every row the sheet holds, per `R-31-10-09`.
- Focus order: per `R-30-719`, the sheet traps the focus. The order is header, `Plugin actions`,
  `Split right`, `Split down`,
  `Read the last 20 lines` when present, `Close pane`, then `Cancel`. On close the focus returns to
  the overflow `:` that opened the sheet. The confirmation dialog places its own focus, per
  `R-33-074`, and this screen MUST NOT set it.

## Open questions

None.

## Sources

- `docs/32-design-language.md` - the bottom sheet of section 7.16 with `R-32-545` and `R-32-546`,
  the destructive action `R-32-527`, the accent restriction `R-32-124`, the contrast table
  `R-32-150`, and the size set `R-32-350`.
- `docs/33-platform-chrome.md` - the confirmation dialog `R-33-074`, the chevron promise
  `R-33-072`, the terminal isolation `R-33-055`, `R-33-057` and `R-33-060`, and the native control
  map `R-33-033`.
- `docs/30-ux-spec.md` - the destructive treatment `R-30-143`, the modal dialog rule `R-30-005`, the
  pane output action `R-30-713`, the unknown outcome `R-30-518`, the keyboard inset and text scale
  `R-30-519`, the announcement mechanism `R-30-742`, and the gesture table that starts a selection
  by long press.
- `docs/31-mockups/08-terminal.md` - the selection surface `R-31-08-22`, the copy path since
  `R-03-101`.
- `docs/21-terminal-rendering.md` - sections 4.2 and 4.3, which hold the measured `pane.resize`
  parameters and reject a Host-side resize, and `R-21-042`, the platform selection surface.
- `docs/02-herdr-probe-results.md` - measured socket behaviour, event payloads, payload sizes.
- `docs/03-product-decisions.md` - full terminal control for a paired phone, `R-03-055`, which
  puts the entry to the plugin actions on this sheet, and `R-03-101`, which fixes the row set.
- `docs/11-relay-protocol.md` - `host_action` and its mapping `R-11-202`, the version-one
  exclusions `R-11-204`, the `pane.closed` tree event `R-11-046`, and the `tree_snapshot` fields
  the header draws.
- The Herdr socket API schema, read at run time with `herdr api schema --json` - `pane.close`. It
  is never a committed file.
- Apple Human Interface Guidelines, Sheets - a resizable sheet expands when its content scrolls or
  the grabber is dragged, and a grabber shows that the sheet resizes and works with VoiceOver:
  `https://developer.apple.com/design/human-interface-guidelines/sheets`
- Material Design 3, Bottom sheets - a modal bottom sheet scrolls internally for a long list, and a
  full-height modal bottom sheet keeps a close affordance:
  `https://m3.material.io/components/bottom-sheets/guidelines`
