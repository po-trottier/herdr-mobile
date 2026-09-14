# 07 - Notifications

| Field | Value |
| --- | --- |
| Route | `/hosts/:hostId/notifications` |
| Surface | Device, Android and iOS |
| Spec | `docs/30-ux-spec.md` |

This destination replaced the `Panes` tree on 2026-09-04, by decision of the product owner after a
live review of the Android build. The tree was a weaker copy of the `Workspace` axis of
`06-agent-list.md`, and the agent status changes had no list of their own. This file keeps the
`R-31-07-` prefix. Every rule of the old tree is retired in the table at the end, and the pane
display-name rule the tree owned is now `R-31-07-08` here, because the rest of the app still cites
it.

On 2026-09-09 the product owner reviewed the screen on the emulator and rejected four things: the
two bulk controls were unlabelled glyphs; every row opened with the agent kind alone, so the rows
read as identical; an unread row differed from a read row by a thin bar and a weight only; the age
read `0s` and did not move until the screen was rebuilt, and the badge said `3` while four rows drew
a bar. His standing ask is `a clear easy way to mark as read, remove, remove all, mark all as read`.
This revision answers each point, under `R-03-056` (every list updates live) and `R-03-058` (one
mark per fact). The wireframes, callouts and rules below carry the 2026-09-09 notes.

## Wireframe

```text
+--------------------------------------+
| Notifications                        |
| (=) Mark all read     (x) Remove all |
+--------------------------------------+
| NEW                                  |
|| omp is blocked            4m 00s  : |
||  lightspeed-kit > impl > main.py    |
+--------------------------------------+
|| claude is done                    : |
||  herdr-mobile > tests > pytest      |
+--------------------------------------+
| EARLIER                              |
|| codex is done            12m 00s  : |
||  scratch > notes > pane 4           |
+--------------------------------------+
|  Agents     Notifications   Settings |
+--------------------------------------+
```

Every row carries the state bar of callout 8 at its leading edge, the doubled `|`, in the hue of the
status its phrase names (amended 2026-09-09 per `R-03-100`). The two rows under `NEW` are unread:
the phrase in `type.body.strong` and the row washed in `color.accent.soft`. The row under `EARLIER`
was read: no wash, the phrase in `type.body`. The `claude` row has no age, because its Host reported
no time.

## Wireframe, all read

```text
+--------------------------------------+
| Notifications                        |
| (=) Mark all read     (x) Remove all |
+--------------------------------------+
| NEW                                  |
| No new notifications. You have read  |
| everything below.                    |
| EARLIER                              |
|| omp is blocked            4m 00s  : |
||  lightspeed-kit > impl > main.py    |
+--------------------------------------+
|| codex is done            12m 00s  : |
||  scratch > notes > pane 4           |
+--------------------------------------+
|  Agents     Notifications   Settings |
+--------------------------------------+
```

`Mark all read` is drawn at `opacity.disabled`, and the line under `NEW` says why: nothing is
unread. Every row keeps its state bar; none carries the weight or the wash. The `Notifications`
destination carries no badge in this state.

## Wireframe, empty

```text
+--------------------------------------+
| Notifications                        |
| (=) Mark all read     (x) Remove all |
+--------------------------------------+
|                                      |
| No notifications.                    |
| Agent status changes on patrick-desk |
| appear here.                         |
|                                      |
+--------------------------------------+
|  Agents     Notifications   Settings |
+--------------------------------------+
```

Both bulk controls are drawn at `opacity.disabled`, because the list holds nothing to act on. The
empty body is the block of callout 13, left at `space.4` on the ground grid of callout 14, with
the watermark bottom-right (amended 2026-09-09 per `R-03-107`; the body centred both lines until
then). The product owner removed the repeated `NOTIFICATIONS` heading and purple decorative rule
on 2026-09-08.

## Wireframe, a notification tap named a closed pane

```text
+--------------------------------------+
| Notifications                        |
| (=) Mark all read     (x) Remove all |
+--------------------------------------+
| /!\ That pane has closed.            |
+--------------------------------------+
| NEW                                  |
|| omp is blocked            4m 00s  : |
||  lightspeed-kit > impl > main.py    |
+--------------------------------------+
|  Agents     Notifications   Settings |
+--------------------------------------+
```

## Callouts

1. Title `Notifications`, token `type.title`, in the app bar of `R-32-510`. There is no host chip
   and no back control: this is a bottom destination. The bar carries no trailing control and no
   hairline of its own: the bar and the strip of callouts 2 and 3 are one header block, closed by
   one `border.hairline` in `color.border.strong` under the strip, per `R-32-582` (amended
   2026-09-09 by the product owner: the two glyph controls of the old bar were unlabelled, and he
   could not tell what they did).
2. `Mark all read` `(=)`. The first control of the strip under the title, `size.button.text` high
   on `color.bg.base`. It is the text action of `R-32-526`, `Mark all read` in the platform's own
   label style of `R-32-212`, as written, in `color.accent.text` (amended 2026-09-09 by the
   product owner, per `R-03-104`: until then `MARK ALL READ` in `type.mono.button` UPPER, which he
   named inconsistent and not native), with the `Mark as seen` glyph of `R-32-401`, `done_all`, at
   `size.icon.md` in the same ink before it. `(=)` is the ASCII stand-in for that glyph. Amended
   2026-09-09 by the product owner, per `R-03-059`: the control is the one text button of
   `app/lib/widgets/app_text_button.dart`, the platform's own, `TextButton.icon` on Android and
   a `CupertinoButton` on iOS, per `R-33-033`; its height, inset, type, ink, glyph size, pressed
   and disabled states are the component's own or come from the platform theme in
   `app/lib/app.dart`. On Android the
   theme's `space.3` inset sits in the gutter, so the glyph starts on the `space.4` column the
   title and every row share. On iOS the Cupertino button keeps the component's own inset and
   height, which the app MUST NOT change, per the `R-33-076` precedent, so the glyph starts at
   that inset. It flags every row read in place and is not a route change. It is dimmed and
   answers no tap while no row is unread, per `R-32-502`; the line of callout 12 says why
   (amended 2026-09-09, per the product owner's ask for controls with words).
3. `Remove all` `(x)`. The second control of the strip, at its trailing edge, `Remove all` in the
   same text action form, the same platform button in its `destructive` form (2026-09-09,
   `R-03-059`), with the `delete_sweep` glyph of `R-32-401`. `(x)` is the ASCII stand-in. It is
   destructive, so it takes `treat.destructive` on a button (`R-32-506`, `R-32-527`): the glyph
   in `color.status.error` and the label in the same `color.accent.text` as callout 2's, with no
   bar; the two controls share one label ink and one type, and the red glyph alone tells them
   apart (amended 2026-09-09 by the product owner per `R-03-058`: the bar was a second mark; and
   the same day per `R-03-104`: until then the label took `color.fg.primary`, a second ink beside
   its neighbour). On Android its label ends on the `space.4`
   trailing inset, one column with the rows' actions glyph of callout 11; on iOS it ends at the
   Cupertino button's own inset. It opens the confirmation dialog of `docs/32-design-language.md`
   section 7.17, titled `Remove all notifications?`, body `This clears the list on this phone.
   Nothing changes on patrick-desk.`, destructive verb `Remove all`. It is dimmed while the list is
   empty. The verb is `Remove`, the same verb the row action of callout 11 uses, because one word
   carries one meaning (amended 2026-09-09).
4. Group headers `NEW` and `EARLIER`. Two upper-case tier headers of `R-32-563`: `type.micro` in
   `color.fg.secondary`, `size.header` high, indent `space.4`, on `color.bg.base`. They are our own
   words, so they are upper case, per `R-32-567`. Each pins only while its own group is on screen,
   per `R-32-569`, and neither collapses. `NEW` holds every unread row and is always drawn; with
   nothing unread it carries the line of callout 12. `EARLIER` holds every read row and is drawn
   only while one exists. The first header follows the strip by the `space.6` group gap of
   `R-32-582`. Added 2026-09-09 by the product owner: the unread rows must be obvious at a glance,
   and a group says it once for every row in it, per `R-03-058`.
5. Phrase, line one: the agent kind and the status word as one sentence, `omp is done`, the same
   phrase the system notification's title carries (`R-31-12-01`), so the row reads as the alert it
   logs. `agent_kind` and `status` come from `agent_status`, per `R-30-510`. Token
   `type.body.strong` in `color.fg.primary` on an unread row, `type.body` on a read row. The word
   names the status and the state bar of callout 8 beside it carries the hue, per `R-03-100`; no
   dot, no icon and no second bar repeats it (amended 2026-09-09 by the product owner: with the
   agent kind alone on line one every row read `omp`, and a status dot in the status hue stood
   beside a bar in the same hue on the same edge).
6. Breadcrumb `space > tab > pane`, line two, token `type.caption` in `color.fg.secondary`. The
   space is the name of the workspace the pane's workspace groups under, the parent workspace
   `space_id` names, or the workspace's own `label` when it has no parent, joined from the last
   `tree_snapshot` (`R-11-044`). `repo_name` is never the source: a custom-renamed workspace leaves
   it stale. (`WorkspaceSummary.spaceId` carries the parent's workspace id; every group member
   carries it, the parent included, and the parent is always in the same snapshot.) The tab and
   the pane segments are `tab_title` and `pane_title` from the same `agent_status` message, per
   `R-30-510`. A segment the app does not know is skipped, never drawn blank. The wireframe writes
   the separator `>`; the app renders `›`, U+203A, per `R-32-572`. Line two carries the breadcrumb
   alone (amended 2026-09-09: the age moved to line one).
7. Age, token `type.caption` in `color.fg.secondary`, measured from `at`, at the trailing edge of
   line one on the phrase's alphabetic baseline, gap `space.3` before it. Its format is the one
   `06-agent-list.md` callout 8 fixes: `12s`, `1m 12s`, `2h 04m`, `3d`. Absent when the Host
   reported no time, per `R-11-224`. It counts while the screen is on screen, per `R-31-07-12`
   (amended 2026-09-09 by the product owner, per `R-03-056`: the age read `0s` and stayed there
   until the screen was rebuilt).
8. State bar and unread signal. The leading bar is the state bar of `R-32-592` as `R-03-100`
   leaves it (amended 2026-09-09 by the product owner: one state mark, the bar; the dot is
   retired): `border.attention` wide, as tall as the row, flush to the leading edge, in the hue of
   the status the phrase names, `color.status.blocked` or `color.status.done` for the two statuses
   the log holds, on every row, read or unread. The unread fact is weight and wash, one composed
   signal for one fact per `R-03-058`: the phrase in `type.body.strong` and the row washed in
   `color.accent.soft`, the wash of the selected row of `docs/32-design-language.md` section 7.4.
   A read row draws neither. The unread fact MUST NOT be a second bar (until 2026-09-09 it was a
   `color.accent.primary` bar, and before that a bar in the status hue beside a status dot).
9. The pane-closed strip. The strip of `R-32-561` with `treat.warning`, one sentence, `That pane
   has closed.`, under the bulk strip and above the list. Present only when this route opened for
   the `pane closed` case of `R-30-511`. The rows below it are the ordinary list.
10. Bottom navigation, with `Notifications` active. The three destinations of `R-32-562`, which
    `R-33-035` fixes in the same order with the same labels on both platforms. The control is full
    width on both, per `R-33-033`: a `NavigationBar` on Android and a `CupertinoTabBar` on iOS.
    The `Notifications` destination carries the tab badge of `R-32-518` while the current Host
    has unread rows: the platform's own filled red circle with the count at the bell's top-end
    corner, and the bell in the bar's normal ink (amended 2026-09-09 by the product owner, per
    `R-03-059`; before that date the bell was recoloured and the count sat bare beside it, which
    neither platform does). That count is the number of rows under `NEW`, from the same log, per
    `R-31-07-05`. There is no create control on this destination, per `R-31-17-01`.
11. The row actions control `:`, the `more_vert` icon of `R-32-401` at `size.icon.md`, trailing on
    every row, with the label `Notification actions`. Amended 2026-09-09 by the product owner,
    per `R-03-059`: the control is the platform's own icon button, a plain `IconButton` on
    Android and a plain `CupertinoButton` on iOS in a `size.target.min` box, per `R-33-033`; its
    box, ink and pressed state come from the platform theme in `app/lib/app.dart`, so on iOS the
    glyph takes the Cupertino tint. The visible glyph ends on the `space.4` trailing inset, where
    every other row's trailing text ends, while the control keeps its `size.target.min` hit
    target (2026-09-08). A tap opens a bottom sheet, the menu surface of `R-33-033`, headed by
    the row's phrase over its breadcrumb, with the sheet action rows `Mark as read` (unread rows
    only) and `Remove`, then `Cancel`. It is the visible path to the two per-row actions; the
    swipes of `R-31-07-09` are the shortcuts.
12. The empty `NEW` line. When no row is unread, the `NEW` group holds one `type.body` line in
    `color.fg.secondary`, inset `space.4` with `space.3` above and below: `No new notifications.
    You have read everything below.` It names the absent thing and the next step, per `R-30-801`
    and `R-30-802`, and it is the one line of text `R-32-502` requires beside the disabled
    `Mark all read`. Added 2026-09-09.
13. The empty body contains only `No notifications.` and `Agent status changes on <host> appear
    here.` Amended 2026-09-09 per `R-03-107`: the first is the title of the empty state of
    `docs/32-design-language.md` section 7.19, `type.title`, the display face of the screen titles,
    in `color.accent.text`; the second is its sentence in `type.body` `color.fg.secondary`,
    `space.2` under it; both left at `space.4`, per `R-32-553`, not centred. No eyebrow, per
    `R-31-07-10`. The app bar title, the bulk strip and the bottom destination label remain.
14. Ground (added 2026-09-09, per `R-03-107`; amended the same day, per the amended `R-03-107`).
    A list with rows paints plain `color.bg.base`: no grid and no paper block behind `NEW` or
    `EARLIER`, which sit `space.6` under the strip and `space.6` apart, per `R-30-231`, and the
    list ends at its last row, per `R-03-109`. Only the empty body of callout 13 takes the ground
    grid of `docs/32-design-language.md` `R-32-332`, painted across the body under the header
    block, and the watermark of `R-32-554`, the silhouette in `color.bg.grid` bottom-right. The
    drawings omit the grid.

## States

| State | Trigger | Screen shows |
| --- | --- | --- |
| Default | This route's computer is the connected one, per `R-30-946`, and the log holds an unread row. | The first wireframe. `EARLIER` is present only while a read row exists. |
| All read | The log holds rows and none is unread. | The second wireframe. `NEW` carries the line of callout 12, `Mark all read` is disabled, and the destination carries no badge. |
| Empty | The log holds no row: nothing arrived this session, or the person removed every row. | The third wireframe. Both bulk controls are disabled. |
| Pane closed | A notification tap named a pane the last `tree_snapshot` no longer holds. | The fourth wireframe. The strip of callout 9 sits above the list, and no pane opens. |

There is no loading state. The rows live in memory (`R-31-07-06`), so the first paint already
holds every row; only the acknowledgements of `R-31-07-01` are read from the store.

Every state updates in place while it is on screen, per `R-31-07-12`: a new row lands at the top
of `NEW`, a row a person reads moves to `EARLIER`, a removed row leaves, and every age counts.

A switch of the connected computer re-scopes the log at once: the screen shows the newly
connected computer's rows, its empty state included, from the moment the connection succeeds,
never the previous computer's rows. The previous computer's rows stay in memory for the host
list's remembered attention (`R-03-046`) and come back, acknowledgements applied, when the
person switches back.

## Navigation

- In: the `Notifications` destination in the bottom navigation, or the `pane closed` case of
  `R-30-511`. This route exists for the connected computer only, per `R-30-946`.
- Out, row tap: `/hosts/:hostId/panes/:paneId`, mockup `08-terminal.md`. The tap marks the row read
  first, per `R-31-07-05`.
- Out, `Agents`: `/hosts/:hostId/agents`, mockup `06-agent-list.md`.
- Out, `Settings`: `/settings`, mockup `15-appearance.md`.
- `Mark as read`, `Mark all read`, `Remove` and `Remove all` act in place. None is a route change.

## Rules

- **R-31-07-01** The screen MUST hold one row per pane. A later `agent_status` for the same pane
  MUST replace that row, with the new status, the new time and the unread state. The rows
  themselves MUST NOT persist: the app stores no agent content, and a relaunch rebuilds the log
  from `tree_snapshot` alone, per `R-30-513`. What persists is the acknowledgement (decided
  2026-09-08 by the product owner, from review). Each row has the identity
  `(pane_id, status, at)`. When a person reads or removes a row, the app MUST store that identity,
  with the verb, per Host, as metadata only (`R-30-510`), in the non-secret store beside the
  paired-computer record, and MUST load it before it applies the first `tree_snapshot` or
  `agent_status` of that Host. A `tree_snapshot` or an `agent_status` that carries an acknowledged
  identity, or an older one, MUST come back read, or not at all when it was removed. Only a change
  with a different status or a later `at` MUST re-add the row unread. A row MUST turn read, or
  leave the list, only once its acknowledgement is stored; a failed write MUST show its own text
  inline, per `R-30-803`, and MUST leave the row as it was. Forgetting a computer, or being
  removed by it, MUST clear its acknowledgements with its record.
- **R-31-07-02** The rows MUST sort most recent first by `at` inside each group of `R-31-07-11`,
  and a row with no time MUST sort last in its group, exactly as `R-30-513` orders unseen
  attention (amended 2026-09-09: the order is now applied per group).
- **R-31-07-03** A row MUST be unread until a person opens its pane, taps `Mark as read` on it, or
  taps `Mark all read`. Those three are the only ways a row becomes read. An unread row MUST
  carry the one composed signal of callout 8, the weight and the wash, and MUST sit under `NEW`;
  a read row MUST carry neither and MUST sit under `EARLIER`. Every row carries the state bar of
  callout 8 in its status hue, read or unread. A row MUST NOT carry a second mark for its unread
  state or for its status, per `R-03-058`, and the unread state MUST NOT be a bar, per `R-03-100`
  (amended 2026-09-09 by the product owner, twice: the control was named `Mark all as read`
  before this date, and the unread bar left the row the same day). These unread rows are the
  current Host's unseen attention under `R-30-501`. The destination badge, the current Host's
  `NEEDS YOU` section and this screen MUST agree.
- **R-31-07-04** `Remove` MUST drop one row from the log, read or unread, at once and without a
  confirmation, because a row is a phone-local record and nothing on the computer changes.
  `Remove all` MUST confirm first through the dialog of `docs/32-design-language.md` section 7.17,
  because it is the one action here that a person cannot undo row by row. Both MUST record the
  removed identity per `R-31-07-01`, so a refresh or a reconnect does not bring the row back.
  Neither action MUST send a message to the Host. Both bulk controls MUST carry their word on
  screen, never a glyph alone, per the product owner's decision of 2026-09-09.
- **R-31-07-05** A row tap MUST mark the row read and open `/hosts/:hostId/panes/:paneId`, in that
  order. The `Notifications` destination MUST count only unread rows in the current Host's log,
  and that count MUST equal the number of rows under `NEW`: both MUST read the same log with the
  same predicate, so the two can never disagree (amended 2026-09-09 by the product owner, who saw
  a badge of `3` over four barred rows). The count MUST stay exact and uncapped per `R-30-508`,
  and MUST hide at zero. A switch to a Host with no unread rows MUST remove the badge.
  Other Hosts' remembered attention MUST remain on their own chooser rows, per `R-03-046`.
- **R-31-07-06** The log MUST fill from two sources only: a live `agent_status` message
  (`R-30-500`), and the `agents[]` of a `tree_snapshot` (`R-30-513`). A `tree_snapshot` MUST NOT
  turn a read row unread and MUST NOT post a system notification. This screen MUST NOT poll and
  MUST NOT send a message of its own.
- **R-31-07-07** When this route opens because a notification named a closed pane, it MUST show
  `That pane has closed.` in the strip of callout 9 and MUST NOT open any other pane on its own.
- **R-31-07-08** Wherever the app names a pane from a `tree_snapshot` pane object, the display name
  MUST be `label`. A pane created from the phone is unnamed, per `R-30-954`, so when `label` is
  empty the app MUST write the word `pane` and the pane's own suffix from `pane_id`: `w3:p11` draws
  as `pane 11`, and `w3:pS` draws as `pane S`. The command beside the name is `title` from the same
  object, never a terminal-set title, which `R-11-225` keeps off the wire.
  `docs/31-mockups/06-agent-list.md` and `docs/31-mockups/08-terminal.md` both name a pane by this
  rule. A row on this screen draws `pane_title` from `agent_status` instead, per callout 6, because
  that message carries no `label`.
- **R-31-07-09** Every row MUST carry a visible actions control, callout 11, that opens `Remove`
  and, on an unread row, `Mark as read`, on the menu surface of `R-33-033`. Decided 2026-09-08 by
  the product owner: an action a person finds only by a swipe is not an easy action. A swipe toward
  the trailing edge MUST reveal `Remove`, and a swipe toward the leading edge MUST reveal
  `Mark as read` on an unread row, each through the reveal-then-tap pane of `R-32-580` (amended
  2026-09-09 by the product owner, per his ask for an easy path to each action; before this date
  one trailing pane held both). A read row MUST have no leading pane. The swipe MUST NOT act by
  itself, and a full swipe MUST NOT remove the row, per `R-30-297`. Each action MUST also exist as
  a named custom semantics action on the row, per `R-30-298`. Every path MUST call the same
  actions, so the row's state is the same whichever path a person takes.
- **R-31-07-10** The empty body MUST contain only the title and sentence of callout 13, in the
  empty-state anatomy of `docs/32-design-language.md` section 7.19 (amended 2026-09-09 per
  `R-03-107`: the title takes `type.title` in `color.accent.text`, the sentence `type.body`
  `color.fg.secondary`, and the block is left aligned, not centred). It MUST NOT show an eyebrow
  heading or a decorative rule, per the product owner's correction of 2026-09-08.
- **R-31-07-11** The list MUST be two groups, `NEW` then `EARLIER`, each under the upper-case tier
  header of callout 4. `NEW` MUST hold every unread row and MUST always be drawn; when it holds no
  row it MUST show the line of callout 12. `EARLIER` MUST hold every read row and MUST be drawn only
  while one exists. No third group exists. Decided 2026-09-09 by the product owner, under
  `R-03-058`: the group states the unread fact once for its rows.
- **R-31-07-12** This screen MUST update in place while it is on screen, per `R-03-056`. A new
  `agent_status` MUST appear at the top of `NEW` on the emission that carries it, with no
  navigation and no rebuild by the person. A row that becomes read MUST move to `EARLIER` on the
  emission that carries the stored acknowledgement. Every age MUST redraw on one periodic timer,
  once a second, because the format of callout 7 shows seconds under an hour, and the timer MUST
  stop when the screen leaves the tree. While this screen is the offstage tab of the bottom
  navigation, the timer MAY skip its redraw, and the first frame after the tab returns MUST show
  the current ages. Decided 2026-09-09 by the product owner.

## Retired rules

Every rule of the `Panes` tree this file used to describe is retired, by the product owner's
decision of 2026-09-04. Each id below is marked **old**, because `R-31-07-01` to `R-31-07-09` are
reused above for the Notifications screen. A reader who finds an old citation reads the row.

| Rule | Disposition |
| --- | --- |
| `R-31-07-01` **old** | Retired. The three-level tree is gone. `R-30-410` owns the hierarchy the `Workspace` axis of `06-agent-list.md` shows. |
| `R-31-07-02` **old** | Retired. The tree's expander state is gone. `R-30-407` persists the space collapse state of the agent list. |
| `R-31-07-03` **old** | Retired. A tap on a workspace row toggled the expander. `06-agent-list.md` owns the header tap of the `Workspace` axis. |
| `R-31-07-04` **old** | Retired. The tree came from one `tree_snapshot` and followed `tree_update`. `R-31-06-04` and `R-11-046` say the same for the agent list. |
| `R-31-07-05` **old** | Retired. Replaced by `R-31-07-07` above: the pane-closed sentence moved with the route. |
| `R-31-07-06` **old** | Retired. The tree showed every pane, agent or not. No screen does now; the desktop shows every pane. |
| `R-31-07-07` **old** | Retired. The tree carried the create control. `R-31-17-01` puts it on `Agents` alone. |
| `R-31-07-08` **old** | Retired with the create control it padded the list for. |
| `R-31-07-09` **old** | Retired. The actions entry point moved to the `Agents` app bar, per `R-31-18-01`. |
| `R-31-07-10` **old** | Moved. The pane display-name rule is `R-31-07-08` above, unchanged in substance. |
| `R-31-07-11` **old** | Retired. The tree search moved to the inline pane search of the agent list's `Workspace` axis, `R-31-06-30`. |
| `R-31-07-12` **old** | Retired. The platform search control is now the `Search a list` row of `R-33-033`, which `R-31-06-30` uses. |

## Accessibility

- Touch target: both bulk controls, every row and every revealed action meet the minimum target
  of `R-30-290` and `R-30-740`, at the sizes `R-32-515`, `R-32-526` and `R-32-562` fix.
- Contrast: the phrase uses `color.fg.primary`, the breadcrumb and the age use
  `color.fg.secondary`, on `color.bg.base` and on the `color.accent.soft` wash, which the brand
  source table of `docs/32-design-language.md` section 3.1b marks decorative and contrast-exempt;
  every pair passes rows in `R-32-150`, per `R-30-720`. The state bar's hues clear the 3.0 to 1
  floor of `R-30-130` on both surfaces, and the word in the phrase carries the status in text. An
  unread row is marked by its group, by its weight and by the word `unread` in its semantics
  label, never by colour alone, per `R-30-142`.
- Screen reader: a row MUST read the phrase, the breadcrumb with commas for the separator per
  `R-32-574`, the age when present, and `unread` when unread, per `R-30-716`. The two bulk
  controls MUST carry the labels `Mark all read` and `Remove all`, per `R-30-717`, and MUST report
  a disabled state when disabled. Each revealed action MUST exist as a custom semantics action
  with its own label, per `R-30-298`. The two group headers are read as `NEW` and `EARLIER`.
- Focus order: per `R-30-719`, `Mark all read`, `Remove all`, the pane-closed strip when present,
  the `NEW` header, its rows or its line, the `EARLIER` header, its rows, then the three bottom
  destinations.

## Sources

- `docs/03-product-decisions.md` - the live-list decision `R-03-056`, the one-mark rule
  `R-03-058`, the state bar `R-03-100` and the button label `R-03-104`, all of 2026-09-09.
- `docs/30-ux-spec.md` - the destination set `R-30-021`, the attention signals `R-30-500` and
  `R-30-501`, the clearing rules `R-30-503` and `R-30-504`, the exact count `R-30-508`, the
  notification fields `R-30-510`, the tap cases `R-30-511`, the no-synthesis rule `R-30-513`, the
  swipe rules `R-30-297` to `R-30-299`, the age format `R-30-405`, the empty-state words
  `R-30-801` and `R-30-802`, the per-Host route scope `R-30-946`, and the unnamed create
  `R-30-954`.
- `docs/32-design-language.md` - the app bar `R-32-510`, the header block `R-32-582`, the text
  action `R-32-526`, the disabled opacity `R-32-502`, the destructive treatment `R-32-506` and
  `R-32-527`, the badge `R-32-518`, the strip `R-32-561`, the destinations `R-32-562`, the
  upper-case header `R-32-563`, `R-32-567` and `R-32-569`, the breadcrumb `R-32-572` and
  `R-32-574`, the revealed action `R-32-580`, the selected-row wash of section 7.4, the state bar
  `R-32-592` of section 7.29, the confirmation dialog of section 7.17, and the contrast table
  `R-32-150`.
- `docs/31-mockups/06-agent-list.md` - the agent list whose `NEEDS YOU` section shares this
  screen's unread set, the age format of its callout 8, and the `Workspace` axis that replaced the
  tree.
- `docs/31-mockups/08-terminal.md` - the terminal a row opens.
- `docs/31-mockups/12-notifications.md` - the system notification whose title the row phrase
  repeats, `R-31-12-01`.
- `docs/31-mockups/17-create.md` - the create control, absent from this destination.
- `docs/31-mockups/18-actions.md` - the actions screen, reached from the terminal.
- `docs/11-relay-protocol.md` - `agent_status` in `R-11-057`, `tree_snapshot` in `R-11-044`, the
  nullable `status_at` in `R-11-224`, and the pane `title` rule `R-11-225`.
- `docs/33-platform-chrome.md` - the destination set `R-33-035`, the native control map `R-33-033`
  and the create control divergence `R-33-034`.
