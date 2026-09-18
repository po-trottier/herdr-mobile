# 05 - Host list

| Field | Value |
| --- | --- |
| Route | `/hosts` |
| Surface | Device, Android and iOS |
| Spec | `docs/30-ux-spec.md` |

## Wireframe

```text
+--------------------------------------+
| Computers                          + |
+--------------------------------------+
| *  patrick-desk                    > |
|    3 agents                    (!) 2 |
+--------------------------------------+
| o  build-box                       > |
|    last seen 09:14             (!) 1 |
+--------------------------------------+
| o  macbook-pat                     > |
|    last seen 3 Mar                   |
+--------------------------------------+
|                                      |
| Touch and hold a row, then tap       |
| Forget.                              |
|                                      |
+--------------------------------------+
```

The state character before each name (`*`, `o`, `.`) stands for the state bar of callout 3 at the
row's leading edge, which this scale cannot draw; on screen the name starts at the row inset and
nothing sits between the bar and the name (amended 2026-09-09 per `R-03-100`).

## Wireframe, a row's menu open

```text
+--------------------------------------+
| Computers                          + |
+--------------------------------------+
| *  patrick-desk                    > |
|    3 agents                    (!) 2 |
+--------------------------------------+
| o  build-box                       > |
|    last seen 09:14             (!) 1 |
+--------------------------------------+
| o  macbook-pat                     > |
|    last seen 3 Mar                   |
|        +-------------+               |
|        | d  Forget   |               |
|        +-------------+               |
|                                      |
| Touch and hold a row, then tap       |
| Forget.                              |
+--------------------------------------+
```

The menu sits at the point of the long press on Android; on iOS the platform context menu lifts
the row as a preview and lists the action under it, per `R-33-080`.

## Callouts

1. Title `Computers`. The app bar of `R-32-510`, title token `type.heading`. The word `Host` never
   appears in the interface. It is a document word. The interface says `computer`. See `R-30-001`.
2. Add action `+`. An app bar trailing control, per `R-32-510`, with the icon `R-32-401` names for
   `Pair a computer`. Routes to `/pair/scan`.
3. Connection state. Three states, drawn as the state bar of `R-32-592` as `R-03-100` leaves it
   (amended 2026-09-09 by the product owner: one state mark, the bar; the dot is retired): a
   `border.attention` wide rectangle in the state's hue, flush to the row's leading edge, as tall
   as the row, with no state word (amended 2026-09-08 by the product owner: the optional word of
   `R-32-592` drew `WORKING` and `IDLE`, agent words that `R-31-05-11` keeps off a computer's
   row, and its varying width started the host names on two edges). Every name starts on one
   text edge: the row inset of section 7.4, `space.4`, because the bar sits outside it. Each
   wireframe character stands for one state, so the drawing and the screen agree:
   - `*` connected, the `ok` bar in `color.status.ok`, the healthy link of section 7.29. At most
     one row shows it, per `R-31-05-10`, and that row also carries the wash of callout 8.
   - `o` saved and not connected, the `unknown` bar in `color.status.unknown`. This is the
     ordinary state of every computer the person is not using. It is not an error, and it is not
     offline; it is a computer this phone knows nothing live about, per `R-03-046`. A switch under
     way, a failed switch, `in use on another phone` and a revoke all draw this bar: the `States`
     table below draws each as an ordinary saved row, and the detail line of callout 5 carries the
     failure in words.
   - `.` offline, the `unknown` bar too, per `R-32-705`: this phone has no network, nothing failed
     on any computer, and the strip and the detail line name `offline` where the bar cannot.
     Offline belongs to the phone and not to a computer, so every row takes `.` at once or no
     row does. It never shares a frame with the other two characters, which is why one character
     can carry it.
   The connected row is the only green one (amended 2026-09-10 by the product owner; until then
   `saved` took `color.status.idle`, which shares the `ok` hue per `R-32-130`, and a disconnected
   row read as connected). The bar finds the live computer; the connected row's wash, the detail
   line and the announcement still separate the three states in words, and `R-32-705` owns the
   three tokens. The bar is the row's one leading mark: the attention count of callout 6 is a badge
   in the trailing slot, never a second bar.
4. Host name. Token `type.body.strong`, colour `color.fg.primary`. It is `host_name` from
   `host_info`, per `R-11-130`. A saved row draws the name this phone stored at its last
   connection, because `host_info` arrives only while connected, and `R-13-065` owns that storage.
   No screen on this phone renames a computer, per `R-03-047`.
5. Detail line. Token `type.micro` UPPER, colour `color.fg.secondary`. One form per row, never
   two:
   - Connected: the agent count, `3 AGENTS`. It counts the `agents` array of `tree_snapshot`, per
     `R-11-044`. Until this screen's own frames carry a `tree_snapshot`, the line reads
     `CONNECTED` (amended 2026-09-08 by the product owner: the detail slot is always filled, so
     every row is the two-line row of `R-32-515` and every name sits on line one; a connected
     row with no count drew one line and its name 8 px lower than its neighbours').
   - Switching: `SWITCHING`, with the spinner of `size.spinner` in the trailing slot (amended
     2026-09-08 by the product owner: the state word replaces the skeleton the `Switching` row
     of the states table named, so the row keeps its two lines).
   - Saved and not connected: `LAST SEEN 14:02`, the time of the last contact with that computer. It
     reads from this phone's own stored record, per `R-13-065`, so it needs no network. A saved row
     shows this state and no live value, per `R-03-046`. The time MUST carry its day, because
     `R-32-706` puts the staleness in the words, and a bare `HH:mm` reads as today on a computer
     nobody has opened for a week. Three forms: `LAST SEEN 14:02` today, `LAST SEEN YESTERDAY
     14:02` yesterday, and `LAST SEEN 3 MAR` before that. The row's semantics node speaks the full
     localised date and time in ordinary case, so the short drawn form costs a screen reader
     nothing.
   - Saved and never connected: `NOT CONNECTED YET`.
   - `IN USE ON ANOTHER PHONE` on the row a switch tried and lost, per `R-30-944`.
   - While this phone has no network every row takes the last-seen form, including the row that was
     connected. `R-30-805` requires the last known data with the time it was seen, and that form
     already is it. The strip of the `Offline` state carries the network fault, so no row
     repeats it.
6. Attention count `(!) 2`. Shown only when one or more agents on that Host are `blocked` or `done`.
   It is the badge of `R-32-518`: the icon `R-32-406` fixes, in `color.status.blocked`, then the
   count in `type.micro.strong` in `color.fg.primary`. It is not a filled pill, because a filled
   pill would put text on a hue, which `R-30-130` forbids. See `R-30-142`.
   A badge on a saved row is remembered attention from an earlier connection, never a live count.
   It is the unseen attention that `R-30-513` keeps in the app, so it survives a disconnect. The
   detail line beside it reads `LAST SEEN 09:14`, which fixes the time the badge belongs to, per
   `R-03-046`. Counting needs the socket, so a saved row MUST NOT be re-counted. See `R-31-05-13`.
7. Chevron `>`. It fills the trailing slot of `R-31-05-15` and opens `/hosts/:hostId/agents`. The
   slot holds a recovery word instead when the app offers one.
8. Row. `AppListRow` (`R-32-593`'s card family; the row itself is the list-row anatomy of
   `docs/32-design-language.md` section 7), with its divider in `color.border.subtle`. The
   connected row alone carries the `color.accent.soft` fill, the selected-row anatomy every other
   list on this phone uses for "the one that is live"; its leading bar is the state bar of callout
   3, and it carries no second bar (amended 2026-09-09 by the product owner, per `R-03-100`: until
   then a 2 px `color.accent.primary` bar marked the selection, and weight and wash carry a
   selection now). The whole row is one hit target, and it does what its trailing slot says. A tap
   on the connected row opens the route. A tap on a saved row switches the connection to that
   computer first, per `R-31-05-12`.
9. Hint text. Token `type.caption`, colour `color.fg.secondary`, plain text under the last row on
   the names' text edge of callout 3, `space.4` above and below, never a strip (amended
   2026-09-08 by the product owner: a footer strip put the hint 20 px left of the names it
   explains). It names the gesture and the word
   the action uses, because a long press is invisible. The word is `Forget`, not `Remove`:
   `14-devices.md` says `Remove` for revoking a phone on the computer, which is a different act.
   This line is also the alternative path to a hidden action.
10. The row's menu. A long press on a row opens the platform menu of `R-33-080`: on Android a
    Material menu at the point of the press, drawn in the wireframe below the row; on iOS the
    platform context menu, which lifts the row as a preview and lists the action under it. It is
    the row action menu of `docs/32-design-language.md` section 7.25. The row keeps its place.
11. The `Forget` action. The glyph `d` is the icon that `R-32-401` names for `Forget this computer,
    destructive`, beside the word `Forget` in the platform's own item. An icon alone is not
    permitted, per `R-32-577` and `R-32-404`. The action is destructive, so it takes the platform's
    destructive role and no fill in a status hue, per `R-32-579` and `R-32-126` (amended
    2026-09-18 by the product owner: until then the action sat in a swipe pane of its own
    anatomy). A tap raises the confirmation, per `R-32-578`, and forgets nothing on its own, per
    `R-31-05-02`.
12. Ground (added 2026-09-09, per `R-03-107`; amended the same day, per the amended `R-03-107`).
    A list with rows paints plain `color.bg.base` inside the safe area: no grid and no paper block
    behind the rows, the `Touch and hold a row, then tap Forget.` hint of callout 9, the skeleton rows
    or the error block, and the list ends at the hint, per `R-03-109`. The `Computer in use` and
    `No network.` strips stay opaque `color.bg.raised` strips. Only the empty block of the `Empty`
    state takes the ground grid of `docs/32-design-language.md` `R-32-332`, painted across the
    body under the app bar, and the watermark of `R-32-554`, the silhouette in `color.bg.grid`
    bottom-right at 60% of the width; the 96 px mark above the eyebrow is gone. The drawings omit
    the grid.

## States

| State | Trigger | Screen shows |
| --- | --- | --- |
| Default | Two or more computers are saved and one of them is connected. | The wireframe above. |
| Loading | A cold start, with one connection attempt running, per `R-31-05-16`. | The row being attempted keeps its name and shows the skeleton of `R-32-560` in place of its detail line. The skeleton appears only after 150 ms, so a fast connection never flashes. Every other row draws its saved state at once, because a saved row reads from storage and needs no network. Every control that would start a second attempt is disabled, per `R-31-05-17`. |
| Switching | A switch is running, per `R-30-948`. | The row the app is leaving takes the saved bar at once, and its detail line takes the last-seen form of callout 5 with the time of its last contact. The row the app is reaching shows the skeleton of `R-32-560`. No row carries the connected bar, per `R-31-05-10`. Every other row is inert, and only scrolling still works, per `R-31-05-17`. |
| Switch failed | The outcome `R-30-947` fixes. Nothing is connected, and every computer is still saved. | Every row draws as an ordinary saved row, because none of them is broken. A strip under the title reads `Could not connect to <host name>. Tap for details.` with `treat.warning`, and it opens diagnostics for the computer the app tried, per `R-31-05-18`. The trailing slot of the row the app tried reads `Try again`, per `R-31-05-15`, and that row's detail line names which failure it was: `in use on another phone` per `R-30-944`, or the third failure sentence of `R-30-808` when the relay does not know that computer. |
| Disconnected | The person tapped `Disconnect` on `/hosts/:hostId/diagnostics`, per `R-30-960`. | No row carries the connected bar. That row draws its saved state, and its trailing slot reads `Reconnect`, per `R-30-961` and `R-31-05-15`. The app MUST NOT reconnect on its own, per `R-31-13-14`. |
| Empty | No Host is paired. | This route is not reachable at a cold start. The app shows `/welcome` instead. See `R-31-01-01`. This screen shows its own empty-state block, the anatomy of `docs/32-design-language.md` section 7.19 on the ground grid of callout 12, left at `space.4` (amended 2026-09-09 per `R-03-107`; it was centred): the eyebrow `COMPUTERS`, the title `No computer yet.` in `type.title` and `color.accent.text`, the sentence `Scan a QR code or enter a phrase to pair your first computer.` in `type.body` `color.fg.secondary`, one `AppGhostButton` routing to `/pair/scan`, and the watermark bottom-right. It appears if a person forgets the last saved computer without leaving `/hosts`, because `R-31-05-02`'s forget action never navigates away. The hint text of callout 9 is absent: there is no row to swipe. |
| Single Host | Exactly one Host is paired. | This route is still reachable from the host chip, and it shows one row. The app MUST NOT skip it, because the `+` action lives here. |
| Error | A Host rejected this Device, for example after a revoke. | That row shows `Removed by this computer. Pair again.` with `treat.error`, and its trailing slot reads `Pair again` and routes to `/pair/scan`, per `R-31-05-15`. |
| Host in use | A switch lost to `host_in_use` with close code `4006`. | The `Switch failed` state above, because a switch has already closed the old connection, so nothing is connected. The row keeps `in use on another phone` per `R-30-944`. No banner appears, per `R-30-947`. `R-31-05-06` still forbids offering to disconnect the other phone. |
| Offline | The phone has no network. | Every row shows the offline bar `.`, and every row keeps its last-seen detail line, per `R-30-805`. A strip under the title reads `No network.` with `treat.warning` and routes to diagnostics, per `R-30-806` and the third failure wording of `R-30-808`. `R-31-05-18` fixes which computer that strip opens. A row tap MUST NOT start a switch, per `R-30-947`. The `+` action stays enabled, because a scan works offline. |

## Navigation

- In, pushed: the host chip in the app bar of `/hosts/:hostId/agents`. The caller stays on the
  stack, per `R-31-05-19`.
- In, as the root: the first route after a revoke, the route a failed switch lands on per
  `R-30-947`, the route every per-Host screen falls back to when no computer is connected per
  `R-30-946`, the cold start of `R-31-05-16`, and the target of the `unpaired` and `disconnected`
  notification tap cases of `R-30-511`. Nothing is open behind it, so it carries no dismissal.
- Out, the connected row: `/hosts/:hostId/agents`, mockup `06-agent-list.md`.
- Out, a saved row: the app connects to that computer, then routes to `/hosts/:hostId/agents` for
  it, per `R-31-05-12`. A failure keeps the person here, in the `Switch failed` state.
- Out, `Reconnect` or `Try again` in a trailing slot: the same two outcomes as a saved row above.
  The word only names which failure came before it, per `R-31-05-15`.
- Out, `+`: `/pair/scan`, mockup `02-pair-scan.md`.
- Out, touch and hold a row, tap `Forget`, then confirm: the Host is forgotten locally, and the
  row leaves the list.
- Out, the dismissal of `R-31-05-19`: back to the caller, with the connection untouched. It exists
  only on the pushed variant.
- Out, the strip of the `Switch failed` or the `Offline` state: `/hosts/:hostId/diagnostics`,
  mockup `13-connection.md`, per `R-31-05-18`.

## Rules

- **R-31-05-01** The list MUST sort by attention count first, then by connection state, then by
  name. So the computer that needs a person sits at the top, even when it is a saved computer the
  person must switch to in order to answer it. Connection state orders the connected computer above
  a saved one, and those are the only two values this key ever compares, because the offline state
  of callout 3 belongs to the phone and reaches every row at once.
- **R-31-05-02** A long press on a row MUST open the row's actions, `Forget` alone, per
  `R-30-296` and `R-33-080` (amended 2026-09-18 by the product owner: until then a left swipe
  revealed the action; swipe actions are retired). The menu MUST stay open until the person taps
  the action or taps outside it. The tap MUST raise the destructive confirmation. The press
  itself MUST NOT forget anything, because forgetting destroys the Device key for that Host.
- **R-31-05-03** Forgetting a Host on the Device MUST NOT claim that it revoked the Device on the
  Host. The interface MUST say `The computer still lists this phone. In the Relay pane, select
  pixel-9 and press d.` The name in the sentence is this phone's own device name, which is the name
  the Relay pane draws on its row, per `R-03-047`, so the sentence names exactly one phone out of
  the list and no other. The `d` is the inline key of section 7.33 of `docs/32-design-language.md`,
  per `R-32-599`: a `type.mono.key` cap in the dialog body, never the plain letter (amended
  2026-09-09 by the product owner, per `R-03-103`); a screen reader gets the plain sentence. The
  sentence MUST NOT name `r`. In `16-host-popup.md` `d` removes the selected phone, per
  `R-13-053`, and `r` removes every phone and rotates the Host key, per
  `R-13-056`. A sentence that named `r` would tell a person to revoke every pairing in order to
  undo one, which is the widest possible reading of a one-phone repair. `d` alone is meaningless,
  because it acts on whatever row is selected, so the selection step MUST stay in the sentence.
- **R-31-05-04** The row MUST NOT show pane text, because the bridge watches one pane at a time. See
  `R-02-013`.
- **R-31-05-05** A row MUST NOT show the relay address. One relay serves every computer in this
  list, and its address lives on `/settings`, per `R-30-922`.
- **R-31-05-06** The `host_in_use` row MUST NOT offer to disconnect the other phone, per `R-30-941`.
  This phone has no authority over it.
- **R-31-05-07** No gesture MUST forget a computer or bypass the confirmation. `Forget` acts only
  from a tap on its menu item, and that tap raises the dialog first, per `R-32-578`.
- **R-31-05-08** Only one row in this list MUST hold its menu open at a time. The platform menu
  is modal on both sides, per `R-33-080`, so a second row cannot open while one is open.
- **R-31-05-09** The app MUST close an open row menu before this list re-sorts. `R-31-05-01`
  re-sorts by attention count, so a re-sort would otherwise leave the menu open over a row that
  has moved, and the person would tap `Forget` on a different computer.
- **R-31-05-10** `R-30-948` fixes the one-connected invariant. This file draws it: every wireframe
  here MUST show exactly one `*`, and a frame that shows two is wrong on its face, because two
  would mean two sockets. The `o` and `.` characters of callout 3 MUST NOT appear in the same
  frame, because `.` reaches every row at once.
- **R-31-05-11** A saved row MUST NOT show a live value. No agent count, no latency, no agent
  state, and nothing else that needs the socket. It shows the name it stored and the last-seen text
  of callout 5, per `R-03-046`. `R-31-05-04` already forbids pane text on every row, and this rule
  carries the same reasoning to every value a computer cannot currently report.
- **R-31-05-12** `R-30-948` owns the tap and `R-30-946` owns where it lands. This screen owns the
  report: the app MUST tell the person with the snackbar of `docs/32-design-language.md` section
  7.22, reading `Switched to build-box. patrick-desk is disconnected.` A switch raises no
  confirmation, so the snackbar is the only place a person learns that a row they did not touch
  has dropped. It MUST name both computers for that reason.
- **R-31-05-13** A badge on a saved row MUST be the unseen attention that `R-30-513` keeps in the
  app, and the app MUST NOT re-count it while that computer is not connected. It reads as
  remembered because the detail line beside it gives the time, per `R-03-046`. It MUST survive a
  switch away and a switch back, as the per-Host state of `R-30-407` does.
- **R-31-05-14** Retired. `R-30-948` states that a switch MUST make one attempt and MUST NOT use
  the reconnect schedule `R-22-028`. See the retired rules table below.
- **R-31-05-15** The trailing slot of a row MUST hold one thing at a time, and a row tap MUST do
  what that slot says. It holds the chevron `>` normally. It holds `Reconnect` after a deliberate
  disconnect, per `R-30-961`. It holds `Try again` after a failed attempt, per `R-30-947` and
  `R-30-511`. It holds `Pair again` after a revoke. A `host_in_use` failure is a failed switch, so
  its slot reads `Try again` like any other, and only the detail line differs. A word MUST replace
  the chevron rather than join it, so one row never offers two ways to do one thing.
- **R-31-05-16** At a cold start the app MUST make exactly one connection attempt, to the computer
  whose stored last-seen time is the newest, which is the computer the person used last. It MUST
  NOT attempt a second one. When no computer has a last-seen time, or that attempt fails, no
  computer is connected and `/hosts` is the start route, per `R-30-946`.
- **R-31-05-17** While a connection attempt runs, this screen MUST disable every control that could
  start a second one: every row tap, the `+` action, and the trailing-slot word of `R-31-05-15`.
  The app holds exactly one WebSocket, per `R-20-009`, so a second attempt would race the first
  over one transport, and neither the winner nor the computer the person ends up on would be
  defined. Scrolling MUST stay available, per `R-30-807`, because it needs nothing from the
  network. The `Loading` state of `R-31-05-16`, the `Switching` state of `R-30-948` and a
  `Try again` or `Reconnect` tap all run the same single attempt, so this rule covers all of them.
  The attempt ends on success, on the failure of `R-30-947`, or when the phone loses the network.
  The long press stays a different gesture from the tap, which is what `R-30-948` requires, so
  this rule does not disable it in general. Two narrow limits apply while an attempt runs. An open
  row menu MUST close when the attempt starts, because a switch changes the connection-state sort
  key of `R-31-05-01` and `R-31-05-09` already forbids an open menu across a re-sort. A long
  press MUST NOT offer `Forget` on the row the attempt is reaching, because forgetting that
  computer mid-attempt would destroy the Device key the attempt is using.
- **R-31-05-18** The strip of the `Switch failed` state MUST be tappable and MUST open
  `/hosts/:hostId/diagnostics`, mockup `13-connection.md`. It reads `Could not connect to
  <host name>. Tap for details.` (amended 2026-09-16 by the product owner: the earlier `No
  computer is connected. Choose one, or see why.` named neither the computer nor the failure and
  read as unclear). The row the app tried carries the raw failure text in its detail line, per
  `R-30-803`: the relay's error message, the close code, or the timeout, never a friendly
  paraphrase. `R-30-946` names diagnostics as its one exception to route entry, so a saved computer
  with no live connection is a legal target, and this is the moment a person most needs that
  screen: `Try again` repeats the attempt without ever saying what failed. `:hostId` is the computer
  the app tried. The
  strip of the `Offline` state, which `R-30-806` already requires to be tappable, MUST use the same
  target rule: the computer whose link the app is trying to recover, or, when there is none, the
  computer `R-31-05-16` names, which is the newest stored last-seen time. Neither strip may open
  diagnostics for a computer this phone has not saved, because `R-30-946` grants the exception only
  to a saved one.
- **R-31-05-19** This screen is a chooser, not a destination, and it MUST keep the caller's way
  back. When the host chip of `06-agent-list.md` opens it, the app MUST push it on the caller's
  stack and MUST take the back control of `R-33-070`. This file MUST NOT name a glyph or a gesture,
  per `R-33-001` and `R-33-070`. The route `title` is `Computers`, per callout 1, which `R-33-070`
  needs so that the iOS back control on any screen this one pushes reads the right previous title.
  Back MUST leave the connection untouched and MUST return to the caller, so a person who opened
  the chooser can cancel and land back where they were. Without it the only way out is a tap on
  the connected row, which opens `Agents`. This screen MUST stay on the stack after a successful
  switch, because `R-30-949` clears the caller's `:hostId` routes and requires `Back` from the
  chosen computer's agent list to reach `/hosts`.
  - **Pushed.** The bottom navigation MUST stay, per `R-33-071`. On iOS the app MUST push this
    screen inside the caller's own tab navigator, so the `CupertinoTabBar` stays visible.
    `R-33-071` permits an Android child route to drop the bar, and this screen MUST NOT drop it: a
    computer is connected while the chooser is pushed, so all three destinations of `R-30-021` are
    live, and a person who opened the chooser by mistake gets a second way out.
  - **Root.** No caller exists, so the screen MUST carry no back control and MUST carry no bottom
    navigation. Nothing is connected on any route that reaches it this way, so `R-30-946` makes two
    of the three destinations of `R-30-021` unreachable, and a bar with two dead destinations is
    worse than none. The Navigation section lists every route that reaches this variant. Both
    wireframes above draw it, which is why neither shows a back control or a bottom bar.

## Retired rules

This row retires one rule id. The id stays reserved, so an old citation still resolves.

| Rule | Disposition |
| --- | --- |
| `R-31-05-14` | Retired. It forbade the reconnect schedule `R-22-028` from reaching a different computer. `R-30-948` now states that a switch makes exactly one attempt and never uses that schedule, so this rule restated an owner's fact. The reason it gave is still the right one: a schedule that wandered would connect the computer the person did not choose. |

## Accessibility

- Touch target: the `+` action, every row and every row action meet the minimum target of
  `R-30-290` and `R-30-740`, at the row height `R-32-515` fixes.
- Contrast: the name uses `color.fg.primary` and the detail line `color.fg.secondary`, both on
  `color.bg.base`, and both are passing rows in `R-32-150`, per `R-30-720`. The state bar and the
  attention icon are non text indicators whose hues clear the 3.0 to 1 floor of `R-30-130`, and
  neither carries meaning by colour alone, per `R-30-141`: each state has its own character in
  callout 3, its own detail line in callout 5 and its own announcement in the screen reader bullet
  below, and the connected row carries the wash of callout 8 (amended 2026-09-09 per `R-03-100`:
  the dot separated its states by shape and diameter, and the bar has one shape and, per
  `R-32-705`, one hue for two of the three states, so the words carry the fact). A drawing or an
  announcement that let two states collapse into one would undo that separation.
- Screen reader: `+` MUST carry the label `Pair a computer`, per `R-30-717`. The state bar's row
  MUST carry one announcement per state of callout 3, per `R-30-716`. The three announcements are
  `Connected`, `Saved, not connected`, and `No network`. Three states need three announcements, and
  `Not connected` alone MUST NOT serve two of them, because it hides which half is at fault.
  `Saved, not connected` names a computer this phone is not using. `No network` names this phone.
  Each row MUST be one semantics node whose label reads the name, that announcement, the detail
  line, then the attention count, so one swipe speaks the whole row. The trailing slot of
  `R-31-05-15` speaks its own word when it holds one, and speaks nothing when it holds nothing. The
  row action MUST also be reachable as a custom semantics action named `Forget this computer`,
  per `R-32-580`, because a screen reader user cannot long press a row.
- Screen reader, a running attempt: the app MUST announce a connection attempt twice through
  `SemanticsService.announce`, as `R-30-912` does. The start sentence names the computer, for
  example `Connecting to build-box`. The outcome sentence is the one the screen already shows: the
  snackbar of `R-31-05-12` on success, and the strip sentence of `R-31-05-18` on failure. Both are
  needed. `R-31-05-17` makes every other control inert for the length of the attempt, so a person
  who hears only the start hears the screen go silent and stop answering, with nothing to say why.
  Each disabled control MUST also carry the disabled semantics flag, so the reason is reachable by
  touch and not only by hearing the announcement.
- Focus order: per `R-30-719`, the back control of `R-31-05-19` when the screen was pushed, the
  title, `+`, the strip when one is present, then each row top to bottom, then the hint text, then
  the bottom navigation when the pushed variant carries it. `R-30-719` puts the app bar leading
  control first, and the back control is that control. Its label comes from the platform navigation
  component, per `R-33-070`, so this screen supplies none.

## Open questions

None.

## Sources

- `docs/32-design-language.md` - the app bar `R-32-510`, the list row `R-32-515`, the state bar
  `R-32-592`, the badge `R-32-518`, the badge icon `R-32-406`, the skeleton `R-32-560`, the icon map
  `R-32-401`, the destructive treatment `R-32-506`, the snackbar of section 7.22, the row action
  menu of section 7.25, `R-32-576` to `R-32-581`, the last-seen line `R-32-706`, the eyebrow
  `R-32-590`, the ghost button `R-32-591`, the card `R-32-593`, `border.attention` `R-32-330`, and
  the contrast table `R-32-150`.
- `docs/03-product-decisions.md` - many saved computers and one connected, `R-03-043` to
  `R-03-046`, and the rename authority `R-03-047`.
- `docs/30-ux-spec.md` - the attention badge rule `R-30-142`, the notification tap cases `R-30-511`,
  the unseen attention of `R-30-513`, the offline state `R-30-805` to `R-30-808`, the screen reader
  state word `R-30-716`, the `host_in_use` detail line `R-30-944` and the two banner actions
  `R-30-941`, the connected-computer route rule `R-30-946`, the failed switch `R-30-947`, the row
  tap that switches `R-30-948`, `Disconnect` and its landing row `R-30-960` and `R-30-961`, and the
  per-Host state that survives a switch `R-30-407`, the announcement mechanism `R-30-912`, the
  offline state that keeps every local action `R-30-807`, the traversal order `R-30-719`, and the
  navigation stack a switch clears `R-30-949`.
- `docs/31-mockups/13-connection.md` - the `Disconnect`, `Forget` and `Remove` distinction table,
  the diagnostics route `/hosts/:hostId/diagnostics`, and the rule against an automatic reconnect
  after a deliberate disconnect, `R-31-13-14`.
- `docs/31-mockups/16-host-popup.md` - the Relay pane key table, where `d` removes the selected
  phone and `r` removes every phone.
- `docs/33-platform-chrome.md` - the back control `R-33-070`, primary navigation on a pushed route
  `R-33-071`, and the ownership rule `R-33-001` that keeps a glyph out of this file.
- `docs/20-mobile-framework.md` - the single WebSocket `R-20-009`.
- `docs/22-platform-integration.md` - the reconnect schedule `R-22-028`, which recovers the current
  connection only.
- `docs/02-herdr-probe-results.md` - measured socket behaviour, event payloads, payload sizes.
- `docs/11-relay-protocol.md` - `host_info` and its `host_name`, `R-11-130`, the `agents` array of
  `tree_snapshot`, `R-11-044`, and the error `host_in_use` with close code `4006`.
- `docs/13-security-pairing.md` - the Device's own stored record for a paired computer, `R-13-065`,
  the single revoke `R-13-053`, and the revoke of every Device `R-13-056`.
