# 06 - Agent list, the landing screen

| Field | Value |
| --- | --- |
| Route | `/hosts/:hostId/agents` |
| Surface | Device, Android and iOS |
| Spec | `docs/30-ux-spec.md` |

This screen answers one question: which agent needs me. It also has to make the Herdr hierarchy
legible, because a space, a worktree, a tab and a pane are how a person finds an agent again. It
does that with two axes over one list, not with a second screen. `Priority` is the default axis and
lists agents only. `Workspace` is the other one: it draws the Herdr desktop sidebar's own hierarchy,
`Space > Worktree > Tab > Pane`, over every pane of the computer, agent or not. The pane tree screen
that used to do that job is gone, decided 2026-09-04 by the product owner, so this axis is the one
browser for every pane. The grouping control switches between the two axes.
Note, 2026-09-09 per `R-03-114`: this mockup uses Herdr's word `Priority`; the previous
word was `Urgency`. Note, 2026-09-10 per `R-03-115`: every pane row in a `Workspace` block is
one line high, agent and shell alike. `Priority` agent rows stay two lines.

## Wireframe, priority grouping

The default axis. The four upper-case sections stay, and every row leads with the tab title, the
task the person named, with the workspace, the pane and the agent kind under it (amended
2026-09-11 per `R-03-124`; until then line one was the agent kind, which reads `omp` on every row
of one computer and so said nothing). The `api-server` row shows line two elided from the front:
its workspace is `feature/db-interface`, and the front segment drops out so the pane segment
survives whole. The status word sits on line one and the age under it on line two, one
right edge for both (decided 2026-09-08 by the product owner); the idle `impl` row has no age, so
its word stands alone in that column. The app bar carries the host chip and, at its trailing edge, the
`Status colours` action of callout 26 and, on Android, the search action of callout 2 (amended
2026-09-09 per `R-03-112`; the `Computer actions` control left this bar the same day per
`R-03-055`, because a plugin acts on a pane and the person reaches it from the pane; the `New`
action that stood here for one day left on 2026-09-10 per the corrected `R-03-109`). The
attention count lives on the `Notifications` destination, not here. Every age on screen advances
once a second while the screen is shown, per `R-03-056` (amended 2026-09-09). The create control
is the floating button of callout 18, `[ + ]` bottom right, on both platforms; the list ends at
its last row, with no fixed band under it, per `R-03-109` (corrected 2026-09-10).

```text
+--------------------------------------+
| patrick-desk  v               (i)  q |
|    [ PRIORITY ]         WORKSPACE     |
+--------------------------------------+
| NEEDS YOU                            |
| !  api-server                blocked |
|    ...face > pane 11 · codex  1m 12s |
+--------------------------------------+
| +  notes                        done |
|    scratch > pane 3 · gemini  4m 02s |
+--------------------------------------+
| WORKING                              |
| >  impl                      working |
|    ...kit > pane 1 · claude      12s |
+--------------------------------------+
| IDLE                                 |
| o  impl                         idle |
|    lightspeed-kit > pane 4 · codex   |
|                                      |
|                               [ + ]  |
+--------------------------------------+
|  Agents    Notifications    Settings |
+--------------------------------------+
```

The shell panes `zsh` and `Explorer` that sit beside `claude` in `impl` are absent here: `Priority`
lists agents only, per `R-31-06-14`. The state character in each row's leading slot (`!`, `+`,
`>`, `o`) stands for the state bar of callout 4 at the row's leading edge, which this scale cannot
draw (amended 2026-09-09 per `R-03-100`). In the app bar, `(i)` is the `Status colours` action of
callout 26 and `q` the Android search action of callout 2; the bracketed word is the selected tab
of callout 13 (amended 2026-09-09 per `R-03-102` and `R-03-112`). `[ + ]` bottom right is the
floating create button of callout 18, drawn over the body on both platforms, never a row of the
list (corrected 2026-09-10 per `R-03-109`); the blank line above it is the body showing through
where the list has ended, not a band the list reserves. On iOS the bar carries no `q`, and the
search field sits under the bar as the iOS wireframe below draws it.

## Wireframe, workspace grouping

The same computer, drawn as the desktop sidebar draws it. The pane search of callout 22 lives in
the header block since 2026-09-09 (`R-03-102`): the `q` action on Android, the field under the bar
on iOS; it is the search the pane tree screen used to hold. Each space is one raised block, one per
top-level entry of the desktop sidebar, in the desktop's own order. Inside the block three tiers
read at a glance (amended 2026-09-09 by the product owner, per `R-03-057`, after two rounds that
changed spacing alone left a tab title reading as a grey row): the space header is a band on
`color.bg.high` with its name at the block's inset; a tab is a glyph and a strong title one step
in, with its pane rows hung off a guide rule below it; a pane row is a state bar beside that guide
rule or a pane glyph in the slot, and its text one step further. The four text edges, the space
name, the worktree label, the tab title and
the pane text, step evenly, so parenting reads as a ladder of text edges, and two tab groups are
separated by a gap and a hairline. `lightspeed-kit` is a repo with its main checkout and two
linked worktrees: the main checkout is the parent that names the block, so its tabs `impl` and
`bench` sit directly under the header, and only the two linked worktrees draw a worktree row;
`asset_library` holds no agent, only a shell pane, and still appears. `scratch` has no worktree,
so it is its own space with no worktree row: its tab sits directly under the header. Every pane
row is one line high. An agent puts its kind, pane name, state and optional age on one baseline.
A shell pane puts its display name and optional command on one baseline.

```text
+--------------------------------------+
| patrick-desk  v           (i)  q (x) |
+--------------------------------------+
|                                      |
| .----------------------------------. |
| |[ lightspeed-kit 7 panes (!) 1 - ]| |
| |    T impl                        | |
| |    | > claude  pane 1 working 12s| |
| |    | = pane 2  zsh               | |
| |    | = Explorer                  | |
| |    | o codex  pane 4 idle        | |
| |    ------------------------------| |
| |    T bench                       | |
| |    | = pane 6  cargo bench       | |
| |----------------------------------| |
| |  Y asset_library                 | |
| |    T shell                       | |
| |    | = pane 5  npm run dev       | |
| |----------------------------------| |
| |  Y feature/db-interface          | |
| |    T api-server                  | |
| |    | ! codex pane11 blocked 1m12s| |
| '----------------------------------' |
|                                      |
| .----------------------------------. |
| |[ scratch         1 pane (!) 1 - ]| |
| |    T notes                       | |
| |    | + gemini pane 3 done 4m02s  | |
| '----------------------------------' |
|                               [ + ]  |
+--------------------------------------+
|  Agents    Notifications    Settings |
+--------------------------------------+
```

The wireframe's marks: the brackets `[ ... ]` stand for the `color.bg.high` band of the space
header, with its expander `-` at the trailing edge; `Y` is the worktree glyph, `T` the tab glyph
and `=` the pane glyph, the icons `R-32-401` names for `A worktree`, `A tab` and `A pane`; the
vertical bar under a tab is the guide rule of callout 23, and the short rule before `bench` is the
hairline that separates two tabs of one worktree. Each text edge sits one wireframe step in from
the one above it: the space name, the worktree label, the tab title, the pane text. The `pane 2`,
`Explorer`, `pane 5` and `pane 6` rows are shell panes: each puts the pane glyph, display name
and optional command on one line, with no state bar or status word. Agent rows also use one line:
kind and pane lead, while state and optional age trail on the same baseline. The state character
of an agent row (`>`, `o`, `!`, `+`) stands for its state bar, which this scale cannot draw
(amended 2026-09-09 per `R-03-100`): the bar stands right after the guide rule and spans the
full 48-high row. The blocked `codex` and done `gemini` rows also carry the unread weight and
wash of callout 9.
This drawing also carries the alerts off marker `(x)`, to show that the marker is free of the
axis, and the floating create button `[ + ]` of callout 18 over the body's end (corrected
2026-09-10 per `R-03-109`); on a phone the button overlaps the last card, and the card scrolls
clear of it, so no band sits between the card and the bottom band.

## Wireframe, a collapsed space

```text
+--------------------------------------+
| patrick-desk  v               (i)  q |
|      PRIORITY         [ WORKSPACE ]   |
+--------------------------------------+
| .----------------------------------. |
| |[ lightspeed-kit 7 panes (!) 1 > ]| |
| '----------------------------------' |
|                                      |
| .----------------------------------. |
| |[ scratch         1 pane (!) 1 - ]| |
| |    T notes                       | |
| |    | + gemini pane 3 done 4m02s  | |
| '----------------------------------' |
|                               [ + ]  |
+--------------------------------------+
```

`lightspeed-kit` is closed and its `(!) 1` still reports the blocked `codex` inside it, so
attention cannot hide inside a closed block. A closed block is its band alone: the expander turns
to `>`, and no hairline or row follows.

## Wireframe, the iOS header block at its heaviest

`R-32-512` permits three app bar actions and, beside them, the alerts off marker of callout 12,
which is a state and not an action (amended 2026-09-09 per `R-03-112`; corrected 2026-09-10 per
`R-03-109`: the `New` action left the bar for the floating button of callout 18). On iOS the
heaviest case this screen reaches is the `Status colours` action and the marker together: one
action and the marker, two actions under the ceiling. On Android the search action of callout 2
takes a second slot, so the Android bar holds two actions and `R-31-06-24` says where a later
action goes. The iOS search is not a bar control: on the `Workspace` axis the
`CupertinoSearchTextField` of callout 22 sits under the bar, in the navigation bar area, above the
segmented control (added 2026-09-09 per `R-03-102`); on the `Priority` axis that line is absent.

```text
+--------------------------------------+
| patrick-desk  v            (i)   (x) |
| [ q Search panes                   ] |
|      PRIORITY         [ WORKSPACE ]   |
+--------------------------------------+
```

## Wireframe, the revealed swipe action

A left swipe on the `gemini` row reveals the trailing action pane. The action carries an icon and
the words `Mark as seen`, never the icon alone. The action waits: it clears the marker when the
person taps it, not when the person swipes.

```text
+--------------------------------------+
| patrick-desk  v               (i)  q |
|    [ PRIORITY ]         WORKSPACE     |
+--------------------------------------+
| NEEDS YOU                            |
| !  codex                     blocked |
|    ... > api-server > pane 11 1m 12s |
+--------------------------------------+
| +  gemini            |     (vv)      |
|    scratch > note    | Mark as seen  |
+--------------------------------------+
|  Agents    Notifications    Settings |
+--------------------------------------+
```

The row content slides to the left and the pane takes the trailing edge. The row does not reflow, so
its text clips at the pane's leading edge, as `notes` does here. The state word and the age of that
row sit under the pane until it closes.

## Wireframe, host in use on another phone

```text
+--------------------------------------+
| patrick-desk  v               (i)  q |
|    [ PRIORITY ]         WORKSPACE     |
+--------------------------------------+
| ! Host in use on another phone       |
|   patrick-desk is connected to       |
|   another phone. Disconnect there,   |
|   or remove that phone in the Relay  |
|   pane, then try again.              |
|   [ Try again ]           [ Why ]    |
+--------------------------------------+
| NEEDS YOU                            |
| !  codex                     blocked |
|    ... > api-server > pane 11  14:02 |
|                               [ + ]  |
+--------------------------------------+
|  Agents    Notifications    Settings |
+--------------------------------------+
```

## Callouts

1. Host chip `patrick-desk  v`. Token `type.heading`, in the app bar of `R-32-510`. The name is
   `host_name` from `host_info`, per `R-11-130`. Tapping it routes to `/hosts`. The `v` is the
   collapse icon of `R-32-401` at `size.icon.md`.
2. The trailing slots after the host chip. They carried the `Computer actions` control from
   2026-09-04 to 2026-09-09. Amended 2026-09-09 per `R-03-055`: plugin actions act on a pane, so the
   person reaches them from the pane action sheet of `10-pane-actions.md`, and this bar carries no
   plugin control. It carries no attention count and no bell either: the product owner moved the
   unread attention count to the `Notifications` destination badge on 2026-09-04
   (`07-notifications.md`). The actions sit in this order, every one the `App bar action` of
   `R-33-033` with its glyph of `R-32-401`: the `Status colours` action of callout 26 and, on
   Android only, the search action of callout 22 (added 2026-09-09 per `R-03-102`), drawn while
   the list has something to search, on both axes, which opens the Material search view. iOS
   carries no search action here; its field sits under the bar. So the Android bar holds two of
   the three actions `R-32-512` permits, and the alerts off marker of callout 12 beside them when
   alerts are off; the iOS bar holds one action and that marker. The `New` action stood second in
   this bar for one day, 2026-09-09, per `R-03-109`; the corrected `R-03-109` of 2026-09-10 put
   the create control back on the floating button of callout 18 (amended 2026-09-09 per
   `R-03-112`; corrected 2026-09-10).
3. Section header in `Priority` grouping. `AppSectionHeader`'s upper-case tier (`R-32-563`'s
   upper-case form), `type.micro` upper case, colour `color.fg.secondary`, row height 32,
   background `color.bg.base`. The header is the label alone; no rule trails it. Decided 2026-09-03
   by the product owner. The letter spacing is the one `R-32-204` fixes for that token. Exactly four
   headers exist, in this order: `NEEDS YOU`, `WORKING`, `IDLE`, `UNKNOWN`. `R-32-569` holds the
   upper-case form and `R-32-567` holds the casing: these four are our own words, so they are
   upper case. Each header pins only while a row of its own section is on screen, then scrolls
   away with that section's last row and the next header takes the top, per `R-32-569` (amended
   2026-09-08): two headers never stack, so a long `NEEDS YOU` section never leaves its header
   over the `WORKING` rows.
4. State bar. The `StatusBar` widget of `R-32-592` as `R-03-100` leaves it (amended 2026-09-09
   by the product owner: one state mark, the bar; the dot is retired): a `border.attention` wide
   rectangle in the state's hue, flush to the row's leading edge and as tall as the row, coloured
   per the status table in `docs/30-ux-spec.md`; `working` pulses with `motion.pulse`
   (`R-32-608`), and nothing else varies by shape. The word of callout 6 names the state beside
   it. The wireframe writes `!` for `blocked`, `+` for `done`, `>` for `working`, `o` for `idle`,
   and `?` for `unknown` in the row's leading slot, because the bar is narrower than one character
   at this scale. The slot itself stays where the dot sat and is empty on an agent row: in
   `Priority` grouping it is `space.2` wide, so the text keeps its `space.8` edge; in a space block
   it is `size.icon.sm` wide under the tab title's first letter, so the text keeps `space.16` and
   a shell row's pane glyph of callout 21 sits centred in it, per `R-32-597` and `R-03-057`.
   Inside a space block the row hangs off the guide rule of callout 23, so the row's leading edge
   is the rule's trailing side: the bar starts at `space.8` plus one `border.hairline` from the
   block's edge, right after the rule, and spans the row's height (amended 2026-09-09 by the
   product owner, per `R-03-100`: the one state mark stands at its own row's leading edge; until
   then the bar sat at the block's edge, a tier away from the row it marked, while the row's
   text was indented to tier 3). In `Priority` grouping the row is not indented, so the bar sits
   at the list's edge. The text edges of `R-32-570` do not move, and the unread wash of callout 9
   keeps the row's full width.
5. Primary text. In `Priority`, it is the first line and carries the **tab title** alone, for
   example `api-server`, the task the person named (amended 2026-09-11 per `R-03-124`; until then
   it was the agent kind, which reads `omp` on every row of one computer). A pane in a tab with
   no title shows the pane name here instead. In `Workspace`, the primary text is the agent kind
   in `type.body`, then `space.2`, then the pane name in `type.caption` `color.fg.secondary` on
   the same baseline, per `R-03-115`: there the tab is the header above the row. The primary text
   uses `type.body.strong` while unread and `type.body` after it is read, always in
   `color.fg.primary` (amended 2026-09-10 per `R-03-115`).
6. Status label, right aligned. In `Priority`, it stays on line one in `type.label`, on the
   kind's baseline. In `Workspace`, it uses `type.body` on the row's one baseline. Its colour
   is `color.fg.primary`, never the status colour. See `R-30-402`. The row keeps `space.4`
   after the trailing group.
7. Secondary text. In `Priority`, line two is the breadcrumb component of
   `docs/32-design-language.md` section 7.24 in `type.caption` `color.fg.secondary`, and reads
   the **workspace**, then the **pane**, then the **agent kind** last: `scratch › pane 3 · gemini`
   (amended 2026-09-11 per `R-03-124`; until then it read workspace › tab › pane, and the tab now
   sits on line one). The segments before the kind are joined by `›`, U+203A; the kind follows a
   `·`, U+00B7, because it is a property of the pane and not a level of the tree. The line elides
   from the front per `R-32-573`, so the pane and the kind survive. In `Workspace`, there is no
   second line: the pane name follows the agent kind, or a shell pane's optional `title` follows
   its display name after `space.2`, in the same caption style.
8. Age. In `Priority`, it stays on line two under the status word and shares the breadcrumb's
   baseline and right edge. In `Workspace`, it follows the status word after `space.2` on the
   row's one baseline. It uses `type.caption` in `color.fg.secondary`. With no age, the status
   word stays in place. Format: `12s`, `1m 12s`, `2h 04m`, `3d`. Every Workspace pane row
   is 48 high; a Priority agent row stays 64 high. Both use `space.3` above and below their text
   (amended 2026-09-10 per `R-03-115`). The age is live per `R-03-056`: one screen timer
   redraws only rows that show an age once a second.
9. Unread. Every row in `NEEDS YOU`, and every agent row that needs attention in `Workspace`
   grouping, is unread, and carries that fact as weight and wash: the agent kind of callout 5 in
   `type.body.strong` and the `color.accent.soft` fill of `docs/32-design-language.md` section 7.4
   under the whole row; a read row takes `type.body` and no fill. Amended 2026-09-09 by the product
   owner, per `R-03-100`: until then the unread fact was a `color.accent.primary` bar at the
   leading edge, and a second bar beside the state bar of callout 4 would put two facts in one
   shape, so the bar is the state and the unread fact moved to the weight and the wash, the same
   composed signal the notification row of `07-notifications.md` uses. `R-03-058` still holds:
   one mark per fact, and no mark repeats another mark's colour on the same edge.
10. Bottom navigation. The three destinations of `R-32-562`, with the icons `R-32-401` names for
    `Agents`, `Notifications` and `Settings`. `R-33-035` fixes those three, their order, their
    labels and their icons on both platforms. The bar is full width on both: a `NavigationBar` on
    Android and a `CupertinoTabBar` on iOS. Every frame in this file is platform-neutral, and the
    bottom band is the navigation control alone. Above it, bottom right, floats the create button
    of callout 18 on both platforms; it is not part of this band, and the list ends at its last
    row with no fixed band reserved for the button (corrected 2026-09-10 per `R-03-109`; on
    2026-09-09 the control had moved into the app bar for one day). The `Notifications`
    destination carries the unread attention count as its badge; `07-notifications.md` owns that
    screen and that badge.
11. The `host_in_use` banner. The blocking banner of `R-32-550`, non dismissible, with
    `treat.warning` on `color.bg.raised`. The title uses `type.body.strong` and the explanation
    `type.caption`. Two actions only, `Try again` and `Why`, per `R-30-941`, in the platform
    button's own sentence case (wireframe amended 2026-09-09 per `R-03-104`; it spelt them in
    upper case). The banner sits under the header block of callout 13 and pushes the list down.
    It MUST NOT float over a row.
12. The alerts off marker `(x)`. An app bar trailing control of `R-32-510`, with the icon `R-32-401`
    names for `Alerts are off`. A tap routes to `/settings/notifications`. It is present only while
    the operating system reports the notification permission as denied, and it replaces nothing else
    in the bar. It is a state, not an action, so it sits beside the actions `R-32-512` counts
    and takes the trailing edge (amended 2026-09-09 per `R-03-112`; corrected 2026-09-10 per
    `R-03-109`). The workspace-grouping wireframe draws it.
13. The grouping strip, the component of `docs/32-design-language.md` section 7.26. It holds the
    platform's own view switcher, two views in the order `Priority`, `Workspace`, on
    `color.bg.base`. Amended 2026-09-09 by the product owner, per `R-03-102` (and `R-03-059`
    before it, which made the control the platform's own): a switch between sibling views is a
    `TabBar` of two primary tabs on Android and a `CupertinoSlidingSegmentedControl` on iOS, per
    the `Switch between sibling views` row of `docs/33-platform-chrome.md` `R-33-033`; a
    `SegmentedButton` is a choice of values, not a view switch. On Android the tab bar is full
    width under the app bar, with no inset of its own; its indicator, ink, type and divider come
    from `tabBarTheme` in `app/lib/app.dart`, never from the screen, and its own divider is the
    header block's one edge, so the screen draws no hairline under it. On iOS the segmented
    control is inset `space.4` from each edge with `space.3` above and below, keeps the
    component's own height, thumb and track, lower than `size.target.min`, which the app MUST NOT
    raise, per the `R-33-076` precedent, and the header block's one `border.hairline` in
    `color.border.strong` closes the strip under it. Both fill the width, so the two views share
    it equally. The labels are `Priority` and `Workspace` in the control's own type and case: the
    wireframes write them upper case and the selected view in brackets, as the earlier drawn
    strip did, and the platform marks the selected view its own way, the tab's indicator or the
    thumb, with the semantics state `selected`, per `R-32-520`. The app bar draws no edge while
    the strip is present, per `R-32-582`: one edge for the block, the same edge the notifications
    strip takes. The strip does not scroll away with the list, per `R-32-583`. `R-30-406` through
    `R-30-414` fix the two axes and the default. Pressed and the change of view are the platform
    control's own responses.
14. Space header, tier one. The collapsible header of `docs/32-design-language.md` section 7.23,
    at `size.row.one_line` per `R-32-564`, drawn as a band on `color.bg.high` across the block's
    top (amended 2026-09-09 by the product owner, per `R-03-057`: the header on the block's own
    surface read as one more row). Its name in `type.body.strong` `color.fg.primary` at the
    block's `space.4` inset: the space name of `R-31-06-27`, in the person's own case per
    `R-32-567`. Trailing, on the name's baseline: the count `N panes` in `type.caption`
    `color.fg.secondary`, per `R-31-06-28` and `R-32-595`, the badge of `R-32-518` when a pane
    inside the space needs attention, and then the expander of `R-32-568` at `size.icon.md`, at
    the block's trailing `space.4` inset, written `-` open and `>` closed; the expander moved from
    the leading edge on 2026-09-09 so the name takes the ladder's first step. It does not pin, per
    `R-32-565` (decided 2026-09-04 by the product owner). The band is a control filled with
    `color.bg.high`, so it presses per `R-32-501`'s first case: `color.accent.primary` with its ink
    in `color.fg.on_accent`, the same answer a key cap gives.
15. Tab header, tier two. Amended 2026-09-09 by the product owner, per `R-03-057`: the glyph
    `R-32-401` names for `A tab` at `size.icon.sm` in `color.fg.secondary` at `space.6`, a
    `space.2` gap, then the title in `type.body.strong` `color.fg.primary` at `space.12`, one
    `space.4` step in from the worktree label; its height is the title line plus `space.3` above
    and below. Until 2026-09-09 the title was `type.label` in `color.fg.secondary` with no glyph,
    which the product owner read as a grey row among the pane rows. It does not pin and it does
    not collapse, per `R-32-565`, and it is not a touch target. The name keeps the person's own
    case, per `R-32-567`: it is not upper-cased, decided 2026-09-04 by the product owner. Two tabs
    of one worktree are separated: the group above closes with a `space.3` gap, then a hairline
    runs from the tab glyph's `space.6` to the trailing edge, then this header follows, per
    `R-32-596`; the first tab under a header band or a worktree row draws no hairline. The pane
    rows under it hang off the guide rule of callout 23, their slot centred under the title's
    first letter and their text one `space.4` step in, at `space.16`.
16. A collapsed space. The header keeps its count and its attention badge, per `R-32-566` and
    `R-31-06-16`. The collapsed-space wireframe draws that case: `lightspeed-kit` is closed, and its
    `(!) 1` still reports the blocked agent inside it.
17. The revealed action pane, the component of `docs/32-design-language.md` section 7.25. A left
    swipe reveals it at the trailing edge. It holds one action, `Mark as seen`, with the icon
    `R-32-401` names for it and the words under the icon, per `R-32-577`. The wireframe writes the
    icon `(vv)`. The pane fill is `color.bg.raised` and the ink is `color.fg.primary`: the action is
    not destructive, so it carries no confirmation, no attention bar and no red fill, which
    `R-32-126` forbids in version one. The word is `type.caption` under the icon at
    `size.icon.md`, a `border.hairline` in `color.border.strong` marks the pane's leading edge,
    and the pane is as wide as the word plus `space.3` each side, per `R-32-576` (amended
    2026-09-08 by the product owner: the pane was a fixed 0.32 of the row). The row keeps the
    platform gesture inset of `R-30-295a`, so a swipe never fights the Android back gesture or
    the iOS interactive pop. Only an agent row that needs attention carries the reveal; a shell
    row never does, per `R-32-597`.
18. The create button, `[ + ]`. The create control of `R-31-06-22`: Material's floating action
    button of `docs/32-design-language.md` `R-32-588` on both platforms, the `add` glyph of
    `R-32-401`, spoken `New`, `space.4` from the trailing edge and from the bottom of the body,
    above the connection strip and the bottom band of callout 10, per `R-33-034`. It opens the
    create menu of `docs/31-mockups/17-create.md`, which owns every item in that menu and every
    rule about it. Corrected 2026-09-10 by the product owner, per the corrected `R-03-109`: on
    2026-09-09 the owner saw the empty band under every list and this callout became a `New`
    action in the app bar; the owner then wanted the floating button kept on both platforms and
    only the band removed. So the list reserves no fixed band: a list that fits the screen ends at
    its last row, and a list that overflows scrolls its last row clear of the button through the
    scroll view's own end padding, `size.button.create` plus `space.4`, which comes into view
    only once the list has scrolled that far. While the link is down the button stays on screen,
    disabled and dimmed to `opacity.disabled`, per `R-30-807` and `R-32-502`; the offline strip
    carries the reason.
19. Worktree row, tier one and a half. The worktree form of `docs/32-design-language.md` section
    7.23, amended 2026-09-09 by the product owner per `R-03-057`: the glyph `R-32-401` names for
    `A worktree` at `size.icon.sm` in `color.fg.secondary` at `space.2`, a `space.2` gap, then the
    workspace label in `type.body.strong` `color.fg.primary` at `space.8`, one `space.4` step in
    from the space name and one before the tab title, so the worktree sits between its space and
    its tabs on the ladder of `R-31-06-31` (until 2026-09-09 it shared the space name's column and
    read as a second space). Its height is the label line plus `space.3` above and below. It is
    not a touch target and it does not collapse. A full-width hairline separates it from the tab
    group above it, per `R-32-596`. It is absent for the parent workspace that names the space
    and for a lone workspace, per `R-31-06-27`: the row would only repeat the header.
20. Space block. The component of `docs/32-design-language.md` section 7.32 (`R-32-595`): the card
    anatomy of `R-32-593`, `color.bg.raised` with a 1 px `color.border.subtle` edge and `radius.md`,
    inset `space.4` from the screen edge over the page's `color.bg.base`, blocks `space.6` apart,
    one group gap of `R-30-231` (amended 2026-09-08 by the product owner: `space.3` read tighter
    than the 24 between two rows inside a block). The header band of callout 14 is the block's own
    top edge, so no hairline runs under it (amended 2026-09-09 per `R-03-057`; until then a
    hairline did). The block is the container that makes parenting obvious: everything inside it
    belongs to the space, and the ladder of `R-31-06-31` says which tier each row is.
21. Shell row. A pane that holds no agent, listed because this axis lists every pane
    (`R-31-06-14`). The anatomy of `R-32-597`, amended 2026-09-09 by the product owner per
    `R-03-057`: the glyph `R-32-401` names for `A pane` at `size.icon.sm` in `color.fg.secondary`,
    centred in the leading slot an agent row leaves empty, so a shell row and an agent row
    read apart at a glance and their text still shares one column; the pane display name of
    `R-31-07-08` on line one in `type.body` `color.fg.secondary` (a shell borrows neither the
    agent's weight, decided 2026-09-08, nor its ink, decided 2026-09-09); the pane's `title` (its
    command) on line two in `type.caption` `color.fg.secondary` when it has one; no status word,
    no attention bar and no revealed action. A pane with no `title`, such as `Explorer`, draws one
    line and its row is `size.target.min` high; it MUST NOT keep a blank second line (decided
    2026-09-08 by the product owner, per `R-32-517`). A tap opens the pane like any other row.
22. Pane search. The platform's own search pattern, per the `Search a list` row of `R-33-033` and
    the values of `R-32-598`, amended 2026-09-09 by the product owner, per `R-03-102`: a search
    field MUST NOT sit as a loose pill in the body of a list, and the pill this axis carried under
    its strip was not the native pattern on either platform. On Android the search is the action of
    callout 2 in the app bar, drawn on both axes while the list has something to search; a tap opens
    the Material 3 search view of `SearchAnchor`, a full-screen route whose field carries the
    placeholder `Search panes` and whose body is the `Workspace` tree narrowed as the person types,
    with the `No pane matches "x".` line of `R-32-598` when nothing matches; a result tap closes
    the view and opens the pane, and closing the view shows the whole tree again. The view's fill,
    edge and type come from `searchViewTheme` in `app/lib/app.dart`. On iOS the search is a
    `CupertinoSearchTextField` in the navigation bar area: directly under the bar at the platform's
    own inset, `space.4` from each edge and `space.2` above the segmented control, drawn on the
    `Workspace` axis and absent on `Priority`, which lists agents only; typing narrows the blocks in
    place, per `R-31-06-30`, and the field's own clear control shows them all again. Both carry the
    `Search panes` glyph of `R-32-401`; the wireframes write it `q`. Neither carries a shadow: a
    search field is not on the closed list of `R-32-320`.
23. Guide rule (added 2026-09-09 by the product owner, per `R-03-057`). A `border.hairline` in
    `color.border.subtle` drops from the tab glyph's centre, at `space.8`, through the full
    height of the tab's pane rows. Since 2026-09-10, `R-03-115` makes each of those rows 48 high,
    so agent and shell branches use equal steps. The rule stops with the last row. It is not a
    divider and takes no touch: the rows under it still touch, per `R-31-06-29`. The wireframe
    draws it as the vertical bar under a tab. Section 7.32 of `docs/32-design-language.md` owns it.
24. Ground (added 2026-09-09, per `R-03-107`; amended the same day, per the amended `R-03-107`,
    after the owner saw the grid around solid list blocks). A body with content paints plain
    `color.bg.base`: no grid and no paper block behind the `Priority` sections, the pinned headers,
    the `Workspace` cards or the `No pane matches "x".` line of callout 22. The `Priority` sections
    still sit one `space.6` group gap apart, per `R-30-231`, the cards keep their own
    `color.bg.raised` surface, and the list ends at its last row, per `R-03-109` (corrected
    2026-09-10: the floating create button of callout 18 sits over the body's end, and the list's
    own end padding comes into view only when the list overflows). Only the empty
    block of both `Empty` states takes the ground grid of `docs/32-design-language.md` `R-32-332`,
    painted across the body under the header block with its lines aligned to that body's
    top-left, and the watermark of `R-32-554`, the silhouette in `color.bg.grid` bottom-right. The
    block's anatomy is section 7.19 of that document: the eyebrow `AGENTS`, the title in
    `type.title`, the display face of the screen titles, in `color.accent.text`, and the sentence
    in `type.body` `color.fg.secondary`, left at `space.4`. The drawings omit the grid.
25. The axis switch (added 2026-09-09, per `R-03-108` and `R-30-415`). On Android the two axes are
    the two pages of a `TabBarView` on the segmented control's own controller: a horizontal drag on
    the ground, or on a row that carries no revealed action, tracks the finger one-to-one and hands
    its velocity to the page physics, and the settled page becomes the persisted axis of
    `R-31-06-12`. A drag that starts on a `NEEDS YOU` row still reveals `Mark as seen`, per
    callout 17. Under reduced motion a tap on the control jumps with no slide, per `R-32-606`. On
    iOS the segmented control switches the axis with the platform's own transition and shows one
    body at a time. Neither takes a curve or a duration of `docs/32-design-language.md` section 8.
26. The `Status colours` action, `(i)` (added 2026-09-09 by the product owner, per `R-03-112`).
    An `App bar action` of `R-33-033` with the `info` glyph of `R-32-401`, spoken
    `Status colours`, the first trailing action on both platforms. A tap pushes the legend of
    `docs/31-mockups/20-status-legend.md`, the same page the Settings row of `15-appearance.md`
    pushes, at `/settings/status-colours`, on this branch's own `Navigator`, so the bottom
    destinations stay on screen, per `R-30-045`. It is always present: the colours it explains
    are on every state bar of this screen, and the owner could not find the legend under
    Settings. The Settings row stays.

## States

| State | Trigger | Screen shows |
| --- | --- | --- |
| Default | The connected computer reports one or more agents, and the axis is `Priority`. Only the connected computer reaches this route, per `R-30-946`. | The priority-grouping wireframe. A section with no members is hidden, header included. |
| Workspace grouping | The person selected the `Workspace` view in the switcher of callout 13. | The workspace-grouping wireframe: one block per space, the three tiers of `R-31-06-31` inside it, every pane listed per `R-31-06-14`, and every pane row one line high per `R-31-06-18`. |
| Time passes | One second elapses while the screen is shown (added 2026-09-09, `R-03-056`). | Every age on screen advances, per `R-31-06-32`. Nothing else redraws: a header, a row with no time and the list order stay as they are, and a hidden tab redraws nothing. |
| Grouping switch while the list is scrolled | The person taps the other view while the list sits away from the top. | Every open action pane closes first, the list rebuilds, and it returns to the top, because a scroll offset in one axis names nothing in the other. The header block does not move, per `R-32-583`, and a screen reader announces the new axis once. |
| Collapsed space holds attention | The person collapsed a space and an agent inside it needs attention. | The collapsed header keeps its count and its badge, per `R-31-06-16`. Its rows leave the traversal order until it is expanded, and the badge is the signal `R-30-501` requires in this axis. |
| Swipe action revealed | The person swiped an agent row to the left. | The swipe wireframe. One pane at a time: opening one closes any other. A scroll closes it. The state word and the age of that row sit under the pane while it is open. |
| Loading | The route opened and the `tree_snapshot` reply has not arrived, per `R-11-043`. | Three skeleton rows at the row height of `R-32-515`, each carrying the skeleton bars of `R-32-560`. The skeleton appears only after 150 ms. The grouping strip stays in place, because it belongs to the header block and not to the list. |
| Empty, no agents | The Host is connected and reports zero agents. | One block on the ground grid of callout 24, left aligned at `space.4` (amended 2026-09-09 per `R-03-107`): the `Eyebrow('AGENTS')` of `R-32-590`, the title `No agents on patrick-desk.` in `type.title` and `color.accent.text`, the sentence `Start one in Herdr on your computer, then pull down to refresh.` in `type.body` `color.fg.secondary`, the watermark of `R-32-554` bottom-right, and no action button. When the computer reports no pane at all the grouping strip is hidden too, because there is nothing to group; when it reports panes without agents the strip stays and the `Workspace` axis lists them. The `New` action stays in the bar, because it creates a space and never an agent. The app MUST NOT offer to start an agent in version one. |
| Empty, no panes | The axis is `Workspace` and the Host reports zero workspaces. | The same block with the title `No panes on patrick-desk.` and the sentence `Open one in Herdr on your computer, then pull down to refresh.`. A running Herdr always holds a workspace, so this state is the reconnect gap, not a normal sight. |
| Search narrows the tree | The person typed in the pane search of callout 22: the iOS field on the `Workspace` axis, or the Android search view from either axis. | Only the blocks, worktrees, tabs and panes that match stay, each with its ancestors, per `R-31-06-30`; counts and badges follow what stays. On iOS the list narrows in place; on Android the narrowed tree is the view's body. The `Priority` axis is untouched. |
| Search matches nothing | The typed text matches no name on the computer. | The field or the view stays, and so does the grouping strip. One line under the field reads `No pane matches "x".`, per `R-32-598`. The empty-state block MUST NOT appear: the computer still has its panes, and clearing the field, or closing the view, shows them all again. |
| Error | The Host answered `error` for `tree_request`. | One block: `Could not read patrick-desk.` with `treat.error`, the error text in `type.mono.code`, and one action `Try again`. |
| Host in use | The relay answered `host_in_use` with close code `4006`. | The host-in-use wireframe. Every row keeps its last known state and its capture time in place of a live age. No row is tappable into a live pane, and every row opens the last painted grid instead, per `R-30-944`. |
| Offline | The phone has no network, the relay is unreachable, or the computer is not connected to the relay. | Every row dims to `color.fg.secondary` and every state bar takes the `unknown` hue (amended 2026-09-09 per `R-03-100`). A persistent strip under the header block carries `treat.warning` on `color.bg.raised`. Its first sentence names which of the three failures this is, per `R-30-808`, and its second reads `Showing what we last saw at 14:02.`, per `R-30-805`. A tap on the strip routes to `/hosts/:hostId/diagnostics`, per `R-30-806`. Rows stay tappable, and the terminal opens with its last painted grid. The `New` action stays in the bar, disabled, per `R-31-06-22` as amended 2026-09-08 and 2026-09-09. |
| Stale | The Host is connected and the last event is older than the threshold `R-32-511` fixes for the live bar. | The app bar shows a `border.hairline` progress line in `color.accent.primary` at the foot of the header block. No text, because this is a common and harmless state. |
| Alerts off | The operating system reports the notification permission as denied. | The app bar carries the alerts off marker of callout 12, as the workspace-grouping wireframe draws it. Nothing else on the screen changes. This screen MUST NOT ask for the permission and MUST NOT offer a step that enables alerts, per `R-31-06-21`. |
| Unseen attention after a gap | The app was closed and events arrived while it was stopped. | Every missed `blocked` and `done` appears in `NEEDS YOU`, ordered by the `at` field, per `R-30-513`, and a row the Host could not stamp sorts last, per `R-31-06-25`. The app MUST NOT post a system notification for any of them. |

## Navigation

- In: the app start route for the connected computer, per `R-31-06-01`. Also from a pairing success,
  from `/hosts`, and from the `Agents` destination. Only the connected computer reaches this route,
  per `R-30-946`.
- Out, row tap: `/hosts/:hostId/panes/:paneId`, mockup `08-terminal.md`, for the pane that holds
  that agent, or for the shell pane itself.
- Out, row long press: the pane action sheet, mockup `10-pane-actions.md`.
- Out, host chip: `/hosts`, mockup `05-host-list.md`. A tap on a different computer there starts a
  switch, per `R-30-948`, and `R-30-949` fixes what the app clears and drops. This screen is then
  rebuilt for the chosen computer. The axis and every collapse state stay saved per Host, per
  `R-31-06-12`, so they return whole if the person comes back, and no row from the computer just
  left survives, per `R-31-06-26`.
- Out, plugin actions: none from this screen. Amended 2026-09-09 per `R-03-055`: the pane action
  sheet of `10-pane-actions.md`, reached from a row long press here or from the terminal, carries
  them.
- Out, offline strip: `/hosts/:hostId/diagnostics`, mockup `13-connection.md`, per `R-30-806`.
- Out, `Notifications`: `/hosts/:hostId/notifications`, mockup `07-notifications.md`.
- Out, `Settings`: `/settings`, mockup `15-appearance.md`.
- Out, banner `Why`: `/hosts/:hostId/diagnostics`, mockup `13-connection.md`.
- Out, alerts off marker: `/settings/notifications`, mockup `12-notifications.md`.
- Out, `Status colours` action: `/settings/status-colours`, mockup `20-status-legend.md`, pushed
  on this branch so the bottom destinations stay (added 2026-09-09 per `R-03-112`).
- Out, the create button: the create menu of mockup `17-create.md`, a sheet over this screen, not
  a route change (amended 2026-09-09 per `R-03-109`; corrected 2026-09-10: the control is the
  floating button of callout 18 again).
- A tap on the other view of the switcher changes the axis in place. It is not a route change.
- A space header tap toggles the collapse only. It is not a route change. A worktree row and a tab
  header are not targets, so a tap on either does nothing.
- A tap on `Mark as seen` clears the marker in place. It is not a route change.
- Typing in the pane search narrows the `Workspace` tree in place on iOS, and inside the search
  view on Android. Neither is a route change of this screen's own, and the text is forgotten with
  the screen; a result tap in the Android view closes it and opens the pane.
- A pull down gesture refreshes with one `tree_request`, per `R-11-043`.

## Rules

- **R-31-06-01** This route MUST be the app start route for the connected computer. A person opens
  the app to answer the question, which agent needs me. At a cold start the app connects to at most
  one saved computer, per `R-03-043`, and `R-31-05-16` fixes which one. When no computer is
  connected the start route MUST be `/hosts` instead, per `R-30-946`.
- **R-31-06-02** The order inside `NEEDS YOU` MUST be `blocked` before `done`, and inside each group
  the oldest state change first. So the agent that has waited longest sits at the top.
- **R-31-06-03** The row MUST NOT show pane text or an output preview. The bridge watches one pane
  at a time, so a preview for every agent would cost one read per agent. See `R-02-013`.
- **R-31-06-04** The status MUST come from the `agent_status` message and from `tree_update`, never
  from polling. See `R-11-057`, `R-11-046` and `R-02-011`. `R-30-405` owns where the age comes from.
- **R-31-06-05** The list MUST NOT reorder a row while the user's finger is down, and MUST NOT
  reorder while an action pane is open. A pending reorder MUST apply on the next scroll idle, after
  every open pane closes. A row that moves under a finger, or under an action the person is reaching
  for, is a mis-tap waiting to happen.
- **R-31-06-06** Opening a row MUST clear that agent's attention marker. See `R-30-503`.
- **R-31-06-07** The `host_in_use` banner MUST NOT be dismissible and MUST NOT retry on its own, per
  `R-30-940` and `R-30-942`. One attempt per press of `Try again`.
- **R-31-06-12** The axis MUST default to `Priority`, per `R-30-406` through `R-30-414`. The chosen
  axis MUST survive a route change and an app restart, per Host. The collapse state of every space
  header MUST persist the same way and per Host, keyed by the space key of `R-31-06-27`: the
  `space_id` its members share, or the workspace id of a lone workspace (amended 2026-09-04 by the
  product owner, when the collapse moved from the workspace to the space; the key changed from the
  repo name to `space_id` on 2026-09-08).
- **R-31-06-13** The grouping strip MUST be present whenever this route holds one or more pane
  rows on either axis, even when every agent sits in one workspace. A control that appears and
  disappears teaches nothing, and the `Workspace` axis MUST stay reachable when the computer holds
  panes but no agent.
- **R-31-06-14** `Priority` grouping MUST list agents only. `Workspace` grouping MUST list every
  workspace, every tab and every pane of the tree, agent or not, including a worktree that holds
  no tab yet: with the pane tree screen gone, this axis is the only browser for every pane
  (decided 2026-09-04 by the product owner). A pane that holds no agent MUST draw as the shell row
  of `R-32-597`, and MUST NOT borrow an agent state.
- **R-31-06-15** In `Workspace` grouping the order MUST be the desktop sidebar's own (Herdr
  `src/ui/sidebar.rs` at `b1ff4582e968`, `workspace_list_entries`): a space stands where its first
  member stands in Herdr's workspace order, whether that member is the parent or not; inside a
  space the parent first, then the other members in Herdr's order; tabs in Herdr's own order;
  inside a tab an agent that needs attention first, then Herdr's own pane order (decided
  2026-09-04 by the product owner, per the sidebar it mirrors; the order corrected from
  alphabetical to the desktop's on 2026-09-08). Nothing on this axis sorts by name. A blocked
  agent MUST NOT sit at the foot of a long group, per `R-30-409`. `R-31-06-02` still fixes the
  order inside `NEEDS YOU`.
- **R-31-06-16** A collapsed space header MUST keep its pane count and its attention badge, per
  `R-32-566`. Attention MUST NOT hide inside a closed block on the one screen that exists to report
  it, and `R-30-501` counts that badge as the signal this axis provides.
- **R-31-06-17** The breadcrumb MUST elide from the front and MUST keep the pane segment whole, per
  `R-32-573`. The pane is what the person taps and what a notification names, so it is the segment
  that MUST survive. `... > api-server > pane 11` is correct, and
  `feature/db-interface > api-server > pan...` is not. When the pane segment alone still overflows,
  it truncates at its own tail.
- **R-31-06-18** In `Priority`, the second line MUST carry the workspace, tab and pane because no
  header carries them. In `Workspace`, every pane row MUST use one baseline. An agent MUST show
  its kind, then `space.2`, then its pane name; its state and optional age MUST trail on that line.
  A shell MUST show its pane name, then `space.2` and its optional `title` on that line. The app
  MUST NOT repeat a header's text in every row (amended 2026-09-10 per `R-03-115`).
- **R-31-06-19** This screen MUST NOT gain a pane nested inside a pane, an expander on a worktree
  row or an expander on a tab row. Only the space header collapses, per `R-30-413`. The split
  geometry of the desktop does not help a person on a phone (amended 2026-09-04 by the product
  owner: the four tiers of `R-31-06-27` are the hierarchy, not a split).
- **R-31-06-20** A left swipe on an agent row MUST reveal the `Mark as seen` action and MUST NOT
  clear the marker by itself. The revealed action stays until the person taps it, taps elsewhere or
  scrolls, and the tap clears the marker at once with no dialog, because the action is not
  destructive. The pane is the component of `docs/32-design-language.md` section 7.25, the mechanism
  is `R-30-296` through `R-30-299`, `R-32-581` forbids the dismiss-on-swipe widget, and `R-30-504`
  owns the affordance itself.
- **R-31-06-21** This screen MUST NOT ask for the notification permission, and MUST NOT offer a step
  that enables alerts. The app asks once at first run, per `R-30-509` and
  `docs/31-mockups/01-welcome.md`. The alerts off marker of callout 12 is the only alert affordance
  this screen carries, and its only job is to explain the silence and route to
  `/settings/notifications`.
- **R-31-06-22** This screen MUST carry the create control, because it is a bottom navigation
  destination. The control MUST be the floating create button of callout 18, Material's
  `FloatingActionButton` with the `add` glyph spoken `New`, on both platforms, per `R-33-034` and
  `docs/32-design-language.md` `R-32-588`, and the app MUST NOT draw a create action in the app
  bar. A list on this screen MUST NOT reserve a fixed band at its end for the button, per
  `R-03-109`. (Amended 2026-09-09 by the product owner, per `R-03-109`: the control moved into the
  app bar on both platforms for one day; until then its shape and position differed by platform.
  Corrected 2026-09-10 by the owner, per the corrected `R-03-109`: the floating button stays on
  both platforms and only the band goes.) The menu it opens
  belongs to `docs/31-mockups/17-create.md`. This screen MUST NOT draw that menu and MUST NOT
  restate a rule from it. Amended 2026-09-08: while the link is down the control MUST stay on
  screen, dimmed to `opacity.disabled`, disabled and announced disabled, because every create
  needs the computer (`R-30-807`, `R-32-502`). The offline strip of this screen's `Offline` state
  carries the reason. A tap that races the link drop MUST still answer with the not-connected
  sentence, so the action never fails in silence.
- **R-31-06-24** The app bar MUST NOT carry a plugin-actions control (amended 2026-09-09 per
  `R-03-055`; until then it carried the `Computer actions` control at its trailing edge), and MUST
  NOT carry an attention count: that count moved to the `Notifications` destination badge on
  2026-09-04 by the product owner's decision. Amended 2026-09-09 per `R-03-112`, corrected
  2026-09-10 per `R-03-109`: the trailing actions MUST be, in this order, the `Status colours`
  action of callout 26 and, on Android, the search action of callout 22, then the alerts off
  marker of callout 12 at the trailing edge when alerts are off. The `New` action stood between
  them on 2026-09-09 alone; the create control is the floating button of callout 18. That leaves
  one of the three actions `R-32-512` permits free on Android and two on iOS; a later action MUST
  take the next slot before the marker and MUST NOT move a control that is already in the bar.
- **R-31-06-25** `R-30-405` fixes where the age comes from and what this screen draws when no time
  is known. This screen owns the consequence for order: inside its own section, a row with no time
  MUST sort after every row that has one. `R-30-513` and `R-31-06-02` both order by that time, so a
  row without one can take no place in that order.
- **R-31-06-26** Every signal on this screen belongs to the connected computer. The `NEEDS YOU`
  section, the attention bar of callout 9 and the space badge of callout 14 MUST count agents on
  that computer alone, which is the same limit `R-03-045` puts on an alert. On a switch the list
  MUST rebuild from the chosen computer's `tree_snapshot`, and it MUST NOT carry a row, a count or a
  marker across. Attention remembered from the computer that just disconnected stays on that
  computer's row on `/hosts`, per `R-03-046`.
- **R-31-06-27** `Workspace` grouping MUST draw the Herdr desktop sidebar's hierarchy with the
  desktop's names, `Space > Worktree > Tab > Pane` (decided 2026-09-04 by the product owner). A
  space is one top-level entry of the desktop sidebar, which the Host reports as the workspace's
  `space_id` on the wire (`R-11-044`, decided 2026-09-08 by the product owner): the desktop groups
  the workspaces of one repo only when two or more are open and one of them is not a linked
  worktree, and the first such workspace in Herdr's order is the group's parent. Every member
  carries the parent's workspace id as its `space_id`, the parent included; the space key is that
  id, and the space is named by the parent's label. A workspace with a `null` `space_id` is its
  own space, named by its label, keyed by its workspace id: a workspace with no `worktree`, the
  only open workspace of its repo, or a member of a repo whose open workspaces are all linked
  worktrees. `repo_name` MUST NOT group anything: two clones of one repo are two spaces. A
  worktree is the Herdr workspace itself, named by its label. The screen MUST draw no worktree
  row for the parent or for a lone workspace: their tabs sit directly under the space header,
  because the row would only repeat the header's own name. Every other member draws its worktree
  row. Every tier is drawn inside the space block of `R-32-595` on the ladder of `R-31-06-31`
  (amended 2026-09-09 per `R-03-057`: the tiers of callouts 14, 15, 19 and 21 replaced the header
  forms and the ladder of 2026-09-08, which the product owner read as one weight).

  Known difference, disclosed (2026-09-08): the desktop sidebar shortens an indented linked
  worktree's label to its branch name without the `worktree/` prefix when the workspace has no
  custom name (`grouped_child_display_label` in the same file). The Herdr API exposes no
  `custom_name` flag and the snapshot carries no branch, so the Host cannot reproduce that rule
  without guessing. Every row on the phone keeps the workspace `label` Herdr reports. This is a
  label difference only; grouping, order and eligibility match the desktop exactly.
- **R-31-06-28** Every tier MUST expose three counts: panes, agents among them, and agents that
  need attention among those, each the sum of the tier below. The space header MUST draw the pane
  count as `N panes`, one number, and the attention count as the badge of `R-32-518`; it MUST NOT
  draw a second number in the same caption (decided 2026-09-04 by the product owner, with `R-32-595`
  as the value side). A worktree row and a tab header draw no count.
- **R-31-06-29** Inside a space block no pane row MAY draw a divider, and the lines of `R-32-596`
  are the only lines (amended 2026-09-09 per `R-03-057`): a full-width hairline before a worktree
  row, a hairline from the tab glyph's `space.6` before the second and every later tab of a
  worktree, each after a `space.3` gap that closes the group above, and the guide rule of callout
  23 under each tab. No hairline runs under the header band: the band's own edge is the line. The
  pane rows keep the anatomy of callouts 4 to 9 with their empty slot centred at the tab title's
  edge, their text at `space.16`, their height per `R-32-517`, and the state bar right after the
  guide rule, at the row's own leading edge (amended 2026-09-09 per `R-03-100`: the bar marks its
  row, so it MUST NOT sit at the block's edge while the row is indented; callout 4 gives the
  position).
- **R-31-06-30** The `Workspace` axis MUST carry a pane search (decided 2026-09-08 by the product
  owner): with the pane tree screen gone, this axis is the only place a person can find a pane by
  name. The search MUST be the platform's own search pattern, per the `Search a list` row of
  `R-33-033` and the values of `R-32-598`: on Android a search action in the app bar that opens the
  Material search view, and on iOS a `CupertinoSearchTextField` in the navigation bar area
  (amended 2026-09-09 by the product owner, per `R-03-102`; until then the field was the first
  item of the axis content and never an app bar control, and it MUST NOT return to the body as a
  loose pill). The Android action counts toward the ceiling of `R-32-512`. The match MUST be a
  case-insensitive substring over the space name, the worktree label, the tab title, the pane
  display name of `R-31-07-08`, the pane `title` and the agent kind. A tier whose own name matches
  MUST keep its whole subtree; otherwise it MUST stay only for the descendants that match, so a
  match is always shown with its ancestors and a matching parent shows everything under it. A
  search that matches nothing MUST NOT reach the empty state of `R-32-553`: the field (or the
  view), the strip and the line of `R-32-598` stay, and clearing the field or closing the view
  MUST show every pane again. The search text is session-scoped and MUST NOT persist across an
  app restart. The `Priority` axis MUST NOT be narrowed by it; the Android view searches the
  `Workspace` tree from either axis.
- **R-31-06-31** (added 2026-09-09 by the product owner, per `R-03-057`) Inside a space block the
  tiers MUST read apart at a glance, each by three means at once: a surface or a glyph, a type
  treatment and a text edge. The space header MUST be a band on `color.bg.high`, the one tier with
  its own surface, its name at the block's `space.4` inset and its expander trailing, per callout
  14. A worktree row MUST lead with the `A worktree` glyph and set its label at `space.8`, per
  callout 19. A tab header MUST lead with the `A tab` glyph and set its title in `type.body.strong`
  `color.fg.primary` at `space.12`, per callout 15; it MUST NOT set the title in `type.label` or in
  `color.fg.secondary`, which read as one more row. A pane row MUST set its text at `space.16`,
  with the empty slot of callout 4 or the `A pane` glyph centred in one slot under the tab
  title's first letter, per callouts 4 and 21, and a shell row's name MUST be `type.body`
  `color.fg.secondary`, so an agent row and a shell row read apart too. The four text edges MUST
  step by one `space.4`
  each: `space.4`, `space.8`, `space.12`, `space.16`. The ladder MUST NOT shift when a space draws
  no worktree row: the same tier sits at the same edge in every block. Two tab groups of one
  worktree MUST be separated by a `space.3` gap and the hairline of `R-32-596`, and every tab's
  pane rows MUST hang off the guide rule of callout 23. `docs/32-design-language.md` owns every
  value named here.
- **R-31-06-32** (added 2026-09-09 by the product owner, per `R-03-056`) Every age this screen
  shows MUST advance while the screen is shown, on one timer per screen with the period the
  notifications list shares, so the two lists never disagree by a second. A tick MUST redraw only
  the rows that show an age: a header, a row with no time and the list order MUST NOT redraw for
  it, and the timer MUST NOT reorder a row, because `R-31-06-05` owns when a reorder applies. While
  this screen is the shell's hidden tab the tick MUST redraw nothing, and the screen MUST redraw its
  ages when it returns. The timer MUST stop with the screen.
- **R-31-06-33** (added 2026-09-09 by the product owner, per `R-03-058`; amended the same day per
  `R-03-100`) An agent row carries one mark per fact. The status is the state bar of callout 4 in
  the status hue and the word of callout 6 beside it, the shape-and-word pair `R-30-141` requires.
  The unread state is weight and wash, per callout 9: `type.body.strong` on the agent kind and the
  `color.accent.soft` fill; it MUST NOT be a second bar, and the row MUST NOT draw a status dot. No
  mark on the row MAY repeat another mark's colour on the same edge, and no other mark MAY carry
  either fact: the `NEEDS YOU` header names a section, not a row, and the space badge of callout 14
  counts a block, not a row. `docs/32-design-language.md` sections 7.4 and 7.29 own the values.
- **R-31-06-34** (added 2026-09-09 by the product owner, per `R-03-112`) The app bar MUST carry the
  `Status colours` action of callout 26 on both platforms: the `info` glyph of `R-32-401`, spoken
  `Status colours`, the first trailing action. A tap MUST push the legend of
  `docs/31-mockups/20-status-legend.md` at `/settings/status-colours`, the same page the Settings
  row of `15-appearance.md` pushes, on this branch's own `Navigator`, so the bottom destinations
  stay on screen, per `R-30-045`. The action MUST NOT depend on the list's state: the colours it
  explains are on screen in every state that draws a state bar, and the Settings row stays.
- **R-31-06-35** (added 2026-09-11 by the product owner, after the app listed a pane the computer
  had closed as `Blocked` and a working pane as `Done`) The tree of the connected computer MUST be
  the only source of a row's presence and of its state word. Every row on either axis MUST come
  from a pane in the current `tree_snapshot` as updated by `tree_update`, and its state word MUST
  be that pane's `agent_status`. The attention log of `R-30-501` and the notification list MAY add
  the unread mark to a row and MAY order rows, but MUST NOT create a row, keep a row whose pane
  the tree no longer holds, or override the tree's state. When a `tree_snapshot` arrives, the
  list MUST rebuild from it wholesale, and an attention entry whose pane is absent from the tree or
  whose pane the tree reports as `working` or `idle` MUST be dropped from the list's rows on the
  spot. Pull to refresh MUST request a fresh `tree_snapshot` and MUST leave the list identical to
  the computer's own agent list.

## Retired rules

| Rule | Disposition |
| --- | --- |
| `R-31-06-08` | Retired. It deferred the permission request to the first `blocked` or `done` event on this screen. The app now asks once at first run, per `R-30-509` and `docs/31-mockups/01-welcome.md`, so this screen holds no permission moment. |
| `R-31-06-09` | Retired with the sheet it governed. It kept the list live behind the in-app permission sheet. `R-30-509` and `docs/31-mockups/01-welcome.md` place the request on `/welcome`, and no sheet is raised here. |
| `R-31-06-10` | Retired. It made a refusal on this screen cost nothing. `R-30-509` and `docs/31-mockups/01-welcome.md` own the refusal, and `R-31-06-21` keeps the alerts off marker as this screen's only remaining part. |
| `R-31-06-11` | Retired. It required the sheet to carry both alert sentences. `docs/31-mockups/01-welcome.md` carries them before the request appears, per `R-30-509`, so no sheet needs them here. |
| `R-31-06-23` | Retired 2026-09-09, per `R-03-109`. It reserved bottom padding under the list so the last row scrolled clear of the floating action button, and hid that button while a revealed action pane was open. The corrected `R-03-109` of 2026-09-10 kept the floating button on both platforms, and this rule stays retired: the scroll view's own end padding of callout 18 replaces the reserved band, a list that fits the screen ends at its last row, and the button hides for no reveal. `R-33-029` still owns the inset under the bottom bar. The id stays reserved. |

## Accessibility

- Touch target: the host chip, the `Status colours` action, the create button, the Android search
  action, the alerts off marker, both views of the switcher, the iOS pane search field, every pane
  row, every space header, every revealed action and the three bottom destinations meet the
  minimum target of `R-30-290` and `R-30-740`, at the sizes `R-32-515`, `R-32-521`, `R-32-564`
  and `R-32-562` fix; the search field and the tab bar are platform components and keep their own
  height. A worktree row and a tab header are not targets, per callouts 15 and 19. The guide rule
  of callout 23 takes no touch, so a tap beside a row's slot still reaches the row.
- Contrast: the status label uses `color.fg.primary`, never the status hue, per `R-30-402` and
  `R-30-130`. The breadcrumb, the age and a shell row's name use `color.fg.secondary`, on
  `color.bg.base` in `Priority` and on the block's `color.bg.raised` in `Workspace`, both pairs
  `R-32-150` passes, per `R-30-720`; the space name and its count sit on the band's
  `color.bg.high`, a pair `R-32-150` passes too. The selected view is marked by the tab's
  indicator or the thumb and by a semantics state, never by colour alone, per `R-32-520`. The
  state bar is a non text indicator whose hues clear the 3.0 to 1 floor of `R-30-130` on
  `color.bg.base` and on `color.bg.raised`, per `R-32-150`, and the word beside it carries the
  state in text, per `R-30-141`. The revealed action sits on
  `color.bg.raised` with ink in `color.fg.primary`, and carries no red fill, per `R-32-126`. The
  banner text sits on `color.bg.raised`, passing rows in `R-32-150`, per `R-30-720`. The guide rule
  and the hairlines are decorative, in `color.border.subtle`, and carry no fact a person must read.
- Screen reader: every state bar's row MUST carry the state word in its label, per `R-30-716`, so a
  row reads `Blocked` and not a bare colour. Each agent row MUST be one semantics node whose label
  reads the tab title, the state word, the workspace, the pane, the agent kind and then the age
  (amended 2026-09-11 per `R-03-124`); the age in that label
  advances with
  the tick of `R-31-06-32`. It MUST read the breadcrumb in full even when the drawing elides it,
  per `R-32-574`, because an elision is a layout limit and not a change of identity. A shell row
  MUST be one node whose label reads the pane name and then its `title`; its pane glyph, the tab
  glyph and the worktree glyph are decorative and MUST NOT be announced, because the tier is
  already what the reading order says (added 2026-09-09). A space header MUST announce its name,
  its pane count, its attention count when one exists, and its expanded state, and MUST announce
  `expanded` or `collapsed` once on a toggle, per `R-32-568`. `Mark as seen` MUST also exist as a
  named custom semantics action on the row, per `R-32-515` and `R-32-580`: the swipe package
  exposes nothing to the accessibility tree, a screen reader user cannot swipe, so the app supplies
  the action itself. The banner MUST announce its title once through `SemanticsService.announce`
  when it appears, and MUST NOT be a live region, so it never interrupts a row that is being read.
  The alerts off marker MUST carry the label `Alerts are off`, per `R-30-717`; the create button
  of callout 18 and the action of callout 26 MUST carry the labels `New` and `Status colours`, and
  the create button MUST announce `disabled` while the link is down.
- Focus order: per `R-30-719`, the host chip, then the app bar actions in their drawn order, the
  `Status colours` action, the Android search action and the alerts off marker when present
  (amended 2026-09-09 per `R-03-112`; corrected 2026-09-10 per `R-03-109`: the `New` action left
  this order with the bar), the two grouping segments, the banner when present with
  `Try again` before `Why`, then each block top to bottom: its header, its worktree rows, its tab
  headers and its pane rows in reading order, then the three bottom destinations (the `Computer
  actions` control left this order on 2026-09-09, per `R-03-055`). A collapsed space MUST take its
  rows out of the traversal order. An open action pane MUST place its actions directly after the
  row that owns them.

## Open questions

None.

## Sources

- `docs/32-design-language.md` - the app bar `R-32-510`, the list row `R-32-515` to `R-32-517` and
  the attention bar of section 7.4, the badge `R-32-518`, the segmented control `R-32-520` and
  `R-32-521`, the pressed cases `R-32-501`, the blocking banner `R-32-550`, the bottom navigation
  `R-32-562`, the icon map `R-32-401`, the spacing rule `R-32-302` and the indent ladder `R-32-570`,
  the contrast table `R-32-150`, the red fill decision `R-32-126`, the header forms of section 7.23
  (`R-32-563` to `R-32-569`), the space block of section 7.32 (`R-32-595` to `R-32-597`), the card
  `R-32-593`, the breadcrumb of section 7.24, the swipe action pane of section 7.25, the grouping
  strip of section 7.26, the state bar `R-32-592` of section 7.29, the eyebrow `R-32-590`, and
  `border.attention` `R-32-330`.
- `docs/30-ux-spec.md` - the status model, the age rule `R-30-405`, the attention rules `R-30-501`
  and `R-30-504`, the swipe mechanism `R-30-296` through `R-30-299`, the gesture inset `R-30-295a`,
  the grouping axis `R-30-406` through `R-30-414`, the per-Host persistence `R-30-407`, the first
  run permission `R-30-509`, the offline behaviour `R-30-805` through `R-30-808`, the `host_in_use`
  banner `R-30-940`, the per-Host route scope `R-30-946`, the switch tap `R-30-948`, what a switch
  discards `R-30-949`, and the missed event rule `R-30-513`.
- `docs/03-product-decisions.md` - one active computer per phone, `R-03-043` through `R-03-046`; the
  2026-09-09 decisions this screen answers: no plugin control here `R-03-055`, live ages
  `R-03-056`, the three tiers of the `Workspace` axis `R-03-057`, one mark per fact `R-03-058`,
  the ground and the empty state `R-03-107` as amended, the floating create button on both
  platforms with no fixed band under the list `R-03-109` as corrected 2026-09-10, and the
  `Status colours` action `R-03-112`.
- `docs/31-mockups/05-host-list.md` - the chooser, the switch report `R-31-05-12`, and the
  cold-start choice `R-31-05-16`.
- `docs/31-mockups/07-notifications.md` - the `Notifications` destination that carries the unread
  attention count, and the pane display name `R-31-07-08`.
- `docs/31-mockups/18-actions.md` and `docs/31-mockups/10-pane-actions.md` - where plugin actions
  live since 2026-09-09, per `R-03-055`; this screen reaches the sheet from a row long press only.
- `docs/31-mockups/01-welcome.md` - the first run permission moment this screen no longer holds.
- `docs/02-herdr-probe-results.md` - measured socket behaviour, event payloads, payload sizes.
- `docs/10-herdr-integration.md` - `session.snapshot`, the agent subscriptions, and the workspace
  `worktree` object (`repo_key`, `repo_name`, `is_linked_worktree`) the Host groups from.
- `docs/11-relay-protocol.md` - `tree_request` and `tree_snapshot` in `R-11-043` and `R-11-044`,
  with the `space_id`, `repo_name` and `is_linked_worktree` fields of a workspace, the
  `tree_update` rule `R-11-046`, the nullable `status_at` in `R-11-224`, the `agent_status`
  message and its `at` field in `R-11-057`, the error `host_in_use`, and the close code `4006`.
- Herdr `src/ui/sidebar.rs` at commit `b1ff4582e968` (`workspace_list_entries`,
  `grouped_child_display_label`) - the desktop sidebar's grouping, order and labels this axis
  mirrors, and the branch-label rule it cannot.
- `docs/33-platform-chrome.md` - the destination set `R-33-035`, the native control map `R-33-033`
  with its `App bar action`, `Search a list` and `Switch between sibling views` rows, the create
  control `R-33-034` as corrected 2026-09-10 per `R-03-109`, and the bottom inset `R-33-029`.
- `docs/31-mockups/17-create.md` - the create menu the create button opens.
- `docs/31-mockups/20-status-legend.md` - the legend the `Status colours` action pushes, and
  `15-appearance.md` for the Settings row that pushes the same page.
