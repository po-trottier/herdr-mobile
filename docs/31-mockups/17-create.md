# 17 - Create a space, a tab or a pane

| Field | Value |
| --- | --- |
| Route | `/hosts/:hostId/agents`, menu layer |
| Surface | Device, Android and iOS |
| Spec | `docs/30-ux-spec.md` |

One control opens one menu with three actions. Every Herdr parameter is optional except the split
direction, so each action is a single call. This menu holds no form, no text field and no file
browser, and the workstation resolves the working directory.

A create lands on the computer this phone is connected to, and no other. Both routes above are
per-Host routes, which the app enters only for the connected computer, per `R-30-946`. This menu
therefore never asks which computer to create on.

The control that opens the menu is the same on both platforms since 2026-09-09, per `R-03-109`,
`R-30-041` and `R-33-034`: since 2026-09-10 Material's floating action button, bottom right of the
`Agents` screen (on 2026-09-09 alone it was a `New` action in the app bar; until that date Android
drew the floating button and iOS a `+` in the app bar, and this file drew both). The menu itself is
the same bottom sheet on both, per `R-33-037`, and only its background material resolves per
platform.

## The three actions

| Menu item | Label on screen | Method | Available when |
| --- | --- | --- | --- |
| `New space` | `New space` | `workspace.create` | always |
| `New tab` | `New tab in herdr-relay`, or `New tab...` | `tab.create` with the workspace context | a workspace is in context, per `R-31-17-02` |
| `Split this pane` | `Split pane 1 right` and `Split pane 1 down` | `pane.split`, `direction` required | a pane is open |

The label names its target, per `R-31-17-03`. A person on a list screen is not looking at a
terminal, so the word `this` names nothing there. The action set is fixed at three by `R-30-950`, so
`worktree.create` is not offered.

## Wireframe, the create control

The `[ + ]` floats bottom right over the body, `space.4` from the trailing edge and from the bottom
band, on both platforms; the app bar trailing row holds the `Status colours` action `(i)` of
`R-03-112` and, on Android, the search action `(s)` of `R-33-033`; iOS draws its search field
under the bar instead (corrected 2026-09-10, per `R-03-109`: on 2026-09-09 this frame drew the
control as `(+)` in the bar; before that date the Android frame had the floating button and the
iOS frame the `+`, and this one frame now serves both). This drawing is the `Agents` destination,
which `06-agent-list.md` owns, in its `Workspace` axis. Since 2026-09-04 it is the only
destination that carries the control, per `R-31-17-01`. The list ends at its last row: no fixed
band under it, and the blank line above `[ + ]` is the body, not a band the list reserves, per
`R-30-041`.

```text
+--------------------------------------+
| patrick-desk  v              (i) (s) |
+--------------------------------------+
|  Priority  | Workspace                |
+--------------------------------------+
| - herdr-relay               2 agents |
|   plugin                             |
|   o claude  pane 1          working  |
+--------------------------------------+
| - scratch                    1 agent |
|   notes                              |
|   o codex   notes.md           idle  |
|                                      |
|                               [ + ]  |
+--------------------------------------+
|  Agents     Notifications   Settings |
+--------------------------------------+
```

## Wireframe, the menu

```text
+--------------------------------------+
|   ... agent list, dimmed ...         |
+--------------------------------------+
|                 ====                 |
| Create on patrick-desk               |
+--------------------------------------+
| New space                            |
| New tab in herdr-relay               |
+--------------------------------------+
| Split pane 1 right                   |
| Split pane 1 down                    |
+--------------------------------------+
|                Cancel                |
+--------------------------------------+
```

## Wireframe, the menu with no workspace on the computer

The computer reports no workspace, so neither a workspace nor a pane is in context. Both
unavailable actions stay on screen with their reason, per `R-30-951`.

```text
+--------------------------------------+
|   ... agent list, dimmed ...         |
+--------------------------------------+
|                 ====                 |
| Create on patrick-desk               |
+--------------------------------------+
| New space                            |
| New tab                              |
|   Open a workspace first             |
+--------------------------------------+
| Split a pane                         |
|   Open a pane first                  |
+--------------------------------------+
|                Cancel                |
+--------------------------------------+
```

## Wireframe, the menu with no pane open

The phone has opened no pane on this computer this session, and the computer holds more than one
workspace. `New tab` therefore has a workspace to create in but cannot name it yet, so its label
ends in an ellipsis and a tap opens the list of the next wireframe, per `R-31-17-11`. A split still
has no target, so its row stays disabled.

```text
+--------------------------------------+
|   ... agent list, dimmed ...         |
+--------------------------------------+
|                 ====                 |
| Create on patrick-desk               |
+--------------------------------------+
| New space                            |
| New tab...                           |
+--------------------------------------+
| Split a pane                         |
|   Open a pane first                  |
+--------------------------------------+
|                Cancel                |
+--------------------------------------+
```

## Wireframe, the workspace list behind `New tab...`

The list of `R-31-17-11`, inside the same sheet. It holds every workspace the tree snapshot
carries, so a workspace with no pane is reachable here and nowhere else.

```text
+--------------------------------------+
|   ... agent list, dimmed ...         |
+--------------------------------------+
|                 ====                 |
| <  New tab in which space?           |
+--------------------------------------+
| herdr-relay                  3 panes |
| scratch                       1 pane |
| worktrees                    0 panes |
+--------------------------------------+
|                Cancel                |
+--------------------------------------+
```

## Callouts

1. The create control, drawn as `[ + ]` bottom right of the first wireframe: Material's
   `FloatingActionButton` of `R-32-588` on both platforms, the `add` glyph of `R-32-401`, spoken
   `New`, `space.4` from the trailing edge and from the bottom of the body, per `R-33-034`
   (amended 2026-09-09, per `R-03-109`: this callout became a `New` action in the app bar for one
   day; corrected 2026-09-10, per the corrected `R-03-109`: the owner kept the floating button on
   both platforms and removed only the empty band under the list). It is the same add glyph that
   `05-host-list.md` uses to pair a computer. `R-30-041` gives the reason one floating button
   serves both platforms.
2. The trailing controls of the app bar: `(i)`, the `Status colours` action of `R-03-112`, first;
   then, on Android, `(s)`, the search action (corrected 2026-09-10, per `R-03-109`: the `(+)` that
   stood between them on 2026-09-09 is the floating button of callout 1 again). Two of the three
   actions `R-32-512` permits; the alerts-off marker of `R-30-515` joins them as a state, not an
   action, while alerts are denied (amended 2026-09-09: the actions control `(e)` of
   `18-actions.md` left this bar per `R-03-055`).
3. The surrounding destination chrome: the host chip, the grouping strip, the agent rows and the
   three destinations. `06-agent-list.md` owns every one of them, and the bottom band is the
   full-width bar of `R-33-033`: a `CupertinoTabBar` on iOS and a `NavigationBar` on Android. The
   drawing is context, and this file changes none of it.
4. Scrim. `color.bg.base` at `opacity.dim` over the destination, per `R-32-545`. A tap on the scrim
   closes the menu.
5. Sheet. The bottom sheet of `R-32-545`, which `R-33-037` fixes as the menu surface on both
   platforms. It rises over `motion.duration.base` with `motion.curve.enter`. On iOS its background
   is the plain translucent `cupertino_ui` sheet surface, per `R-33-012`. The app ships no Liquid
   Glass on iOS, and `R-33-013` forbids an imitation of it. Flutter draws the whole sheet, so every
   row above the background is an ordinary Flutter row. On Android the background is the opaque
   Material surface the anatomy already names.
6. Grab handle, drawn as `====` at the top of the sheet. The handle of `R-32-545`, centred. A drag
   down closes the menu.
7. Header `Create on patrick-desk`. Token `type.body.strong` (the app drew `type.heading` until
   2026-09-08; corrected to this callout and `R-32-545`). It names the connected computer, so a
   person who reaches this menu from either destination reads where the new thing will appear.
8. `New space`. It calls `workspace.create` and needs no context, so it is the one row that is never
   disabled, per `R-30-951`.
9. `New tab in herdr-relay`. It calls `tab.create` with the workspace context of `R-31-17-02`, and
   the label names that workspace. When no context is implied the label is `New tab...`, drawn in
   the fourth wireframe, and the tap opens the workspace list instead of creating anything, per
   `R-31-17-11`.
10. `Split pane 1 right` and `Split pane 1 down`. Both call `pane.split` on the current pane, one
    with `direction: "right"` and one with `direction: "down"`. They carry the two icons `R-32-401`
    names for `Split right` and `Split down`.
11. `Cancel`. The cancel row of `R-32-545`, centred, `size.button.primary` high, label
    `type.body.strong` in `color.fg.secondary` as written (the app drew an upper-case accent text
    action until 2026-09-08; corrected to this callout). The last row of each group draws no
    divider of its own, so the group divider of callout 12 is one hairline, never two.
12. Row. The sheet action row of `R-32-545`. Label `type.body`. Group dividers separate the two
    containers from the split, because a space and a tab hold things and a split changes a layout.
13. The disabled `New tab` in the third wireframe, with the caption `Open a workspace first` under
    it. The row is at `opacity.disabled`, per `R-32-502`, and the caption words are the ones
    `R-30-951` fixes.
14. The disabled `Split a pane` in the third and fourth wireframes, with the caption `Open a pane
    first`. One row replaces the two direction rows, per `R-31-17-05`.
15. `New tab...` in the fourth wireframe. The ellipsis says that a choice follows, which is the one
    exception `R-31-17-03` makes to a label naming its target. This tap creates nothing.
16. The workspace list in the fifth wireframe, drawn on the same sheet. Its header replaces the
    create header and carries a back chevron, the leading control glyph of `R-32-510`, which
    returns to the menu. Each row is the sheet action row of callout 12, labelled with the
    workspace `name` and the pane count from the tree snapshot. A workspace with no pane reads
    `0 panes` and is tappable, because it is the workspace this list exists for. `Cancel` closes
    the whole sheet.

## How this menu differs from the pane action sheet

`10-pane-actions.md` also offers a split, and the two are not duplicates. The difference is the
target, and it is the reason both exist.

| | `10-pane-actions.md` | This menu |
| --- | --- | --- |
| Reached from | the overflow on the terminal view, or a long press on a row | the create control on a destination |
| Target | the pane the person is viewing or pressed | the current pane, named in the label |
| Labels | `Split right`, `Split down` | `Split pane 1 right`, `Split pane 1 down` |
| What it does | acts on a thing that already exists | creates a new thing |
| Also offers | zoom, rename, resize, copy, close pane | nothing else, per `R-31-17-06` |

`R-31-10-01` to `R-31-10-07` govern that sheet. This file cites them and restates none of them.
`R-31-10-01` in particular keeps the one confirmation on that sheet's one destructive action, and
this menu has no destructive action at all, per `R-30-953`.

## States

| State | Trigger | Menu shows |
| --- | --- | --- |
| Default | A pane is open on this computer. | The second wireframe. |
| No pane open | The phone has opened no pane on this computer this session, and the computer holds more than one workspace. | The fourth wireframe. `New space` and `New tab...` are enabled, and `Split a pane` is disabled with its reason. |
| Choosing a workspace | `New tab...` was tapped. | The fifth wireframe. The list reads the tree snapshot the app already holds, so this state never waits and never fails. |
| Loading | A create is in flight. | The tapped row shows the in-place spinner of `R-32-350` in place of its label, and every other row is disabled. The menu stays open, and refuses every dismissal path, until the acknowledgement returns, per `R-31-17-07`. |
| Created | The acknowledgement returned with the new id. | The menu closes over `motion.duration.base` with `motion.curve.exit`, `haptic.commit` fires, which the haptic table in `docs/30-ux-spec.md` assigns to an applied action, and the app routes as `R-31-17-10` requires. |
| Outcome unknown | The create left the phone and no acknowledgement arrived. | The state, its sentence and its one `Check now` control are the ones `R-30-518` fixes, and so is the reconciliation that MUST precede a second attempt. The spinner stops and every dismissal path returns. This row MUST NOT offer `Try again`, because a second `New space` makes a second workspace and a second split makes a second pane. |
| Empty | The computer reports zero workspaces. | The third wireframe. `New space` is the only enabled row, and it is the action that ends the empty state. `06-agent-list.md` shows the same computer as its own empty state. |
| Error | The computer rejected the call. | A strip appears under the header: the plain sentence `Could not create that.` with `treat.error`, the raw error text in `type.mono.code` per `R-30-803`, and one `Try again` per `R-30-804`. The menu stays open. Haptic `haptic.error`. |
| Host in use | The relay answered `host_in_use` with close code `4006`. | Every row is disabled at `opacity.disabled` and one line under the header reads `Another phone is using this computer.` The line MUST NOT offer to displace that phone, per `R-30-941`. |
| Offline | The link dropped after the menu opened. (A link already down leaves the create control itself disabled, per `R-31-17-08` as amended 2026-09-08.) | Every row is disabled at `opacity.disabled` and one line under the header reads `Offline. Creating needs the computer.` No action here is local, so `R-30-807` disables all three. |

## Navigation

- In: the create control on `06-agent-list.md`.
- Out, `New space` and `New tab in ...`: the menu closes and the `Agents` destination stays, per
  `R-31-17-10`.
- Out, a split: `/hosts/:hostId/panes/:paneId` of the new pane, mockup `08-terminal.md`.
- Out, the back chevron on the workspace list: the menu, with nothing created.
- Out, `Cancel`, back, a scrim tap or a drag down: the menu closes and nothing happens. While a
  create is in flight all four do nothing, per `R-31-17-07`.

## Rules

- **R-31-17-01** The create control MUST appear on the `Agents` destination only. Decided
  2026-09-04 by the product owner, when the `Panes` destination was replaced by `Notifications`,
  which creates nothing. It MUST NOT appear on `/hosts/:hostId/notifications` or on `/settings`,
  and it MUST NOT appear on the terminal view, which hides the bottom navigation per `R-30-022`.
  On the terminal view there is no split: `R-03-101` keeps split out of the pane action sheet,
  so a person returns to `Agents`, where the menu offers a split of the pane they just opened,
  per `R-31-17-02` (corrected 2026-09-14; until then this line pointed at `10-pane-actions.md`).
- **R-31-17-02** The menu MUST resolve two contexts separately, because `tab.create` needs a
  workspace and `pane.split` needs a pane. The pane context is the pane this phone opened last on
  the connected computer since the app started, so a cold start reaches this menu with no pane in
  context, and a split MUST use that pane as its target. The workspace context is the first of
  these that exists: the workspace of the pane context; the workspace this phone created here last,
  whose id arrived in the acknowledgement per `R-11-205`; the only workspace in the tree snapshot
  when the snapshot holds exactly one; then the workspace the person picks, per `R-31-17-11`. The
  menu MUST NOT take a workspace from a space header of `06-agent-list.md`, because a header tap
  there toggles the collapse and is not a selection.
- **R-31-17-03** The label of `New tab` and of each split row MUST name its target, because a person
  on a list screen is not looking at a pane. The target name MUST come from the tree snapshot: the
  workspace `name` for `New tab`, and the pane display name of `R-31-07-08` for a split.
  A label MUST stay on one line, MUST NOT wrap, and MUST elide a long name from the front the way
  `R-32-573` elides a breadcrumb, so the distinguishing tail of a branch name survives. There is one
  exception: when `R-31-17-02` reaches its last source and the person must pick the workspace, the
  label MUST read `New tab...` and MUST NOT name a workspace, because naming one the person did not
  choose would state a target the tap does not use. That is the whole of the exception. A label MUST
  NOT be shortened to `New tab` while a target exists.
- **R-31-17-04** The menu MUST offer the split direction as two rows and MUST NOT open a second
  step. `pane.split` requires a direction, and a second step costs a tap for a choice between two.
- **R-31-17-05** When no pane is current, the two direction rows MUST collapse to one disabled row
  labelled `Split a pane`. This is not hiding: the action stays on screen with the reason `R-30-951`
  fixes. Two disabled rows for one unavailable action is noise, and a direction means nothing
  without a target.
- **R-31-17-06** The menu MUST NOT offer zoom, rename, resize, copy or close. Each of those acts on
  a thing that already exists, and `10-pane-actions.md` owns them. This menu creates.
- **R-31-17-07** The menu MUST stay open until the acknowledgement returns, and MUST NOT close on
  the tap. The new id arrives in the acknowledgement, per `R-30-956`, so a menu that closes early
  has nowhere to send the person. Only the tapped row shows a spinner, and every other row disables.
  While a create is in flight the menu MUST refuse every dismissal path: `Cancel`, the system back
  gesture, a scrim tap and a drag down all do nothing. A create that has left the phone cannot be
  recalled, so a dismissal would drop its result rather than cancel it. The wait MUST end: when no
  acknowledgement arrives the menu MUST enter the outcome-unknown state of `R-30-518`, which returns
  every dismissal path. The pane action sheet already waits the same way in its loading state, so
  the two surfaces feel alike.
- **R-31-17-08** Amended 2026-09-08: while the link is down or another phone holds the computer,
  the create control itself stays on screen, dimmed to `opacity.disabled`, disabled and announced
  disabled, per `R-32-502`. The agent list's offline strip carries the reason, so the menu
  never opens onto a dead link. A tap that races the drop answers with the not-connected
  sentence instead of the menu, and a link that drops while the menu is open still gets this
  menu's `Offline` state. (Before this amendment the control stayed enabled and the menu
  opened with every row disabled, because a disabled control then carried no reason of its
  own.)
- **R-31-17-09** The menu MUST NOT open over the terminal grid. `R-31-17-01` keeps the control off
  the terminal view, so no sheet material and no chrome colour reaches the grid, per `R-33-055` and
  `R-33-060`.
- **R-31-17-10** The route after a create MUST be exact. `New space` and `New tab` MUST close the
  menu and stay on the `Agents` destination, because the new node holds no agent yet and
  `R-30-408` keeps it off that list until it does; there is no tree to show it on since 2026-09-04.
  A split MUST route to `/hosts/:hostId/panes/:paneId` of the new pane, using the `result_id` of
  the acknowledgement, per `R-30-956` and `R-11-205`.
- **R-31-17-11** When `R-31-17-02` reaches its last source, `New tab` MUST open the workspace list
  of the fifth wireframe inside the same sheet, and MUST create the tab in the workspace the person
  taps. The list MUST hold every workspace the tree snapshot carries, including a workspace with no
  pane. Such a workspace is otherwise unreachable: it supplies no pane context, and `R-30-408`
  keeps it off the agent list, so without this list a space could be created and never filled.
  The list reads the snapshot the app already holds, so it MUST NOT wait for the computer and MUST
  NOT show a loading state. `New tab` MUST stay disabled with the caption `R-30-951` fixes only when
  the snapshot holds no workspace at all, which is the `Empty` state of this menu.

## Accessibility

- Touch target: every row and `Cancel` are the heights `R-32-545` fixes, and the create button is
  `size.button.create`, 56 by 56, per `R-32-588`, so all clear the minimum in `R-30-290` and
  `R-30-740` (amended 2026-09-09, per `R-03-109`, when the button gave way to an app bar action;
  restored 2026-09-10, per the corrected `R-03-109`). The grab handle is smaller than its target,
  which `R-30-291` permits.
- Contrast: a row label is `color.fg.primary` on `color.bg.raised`, a passing row in `R-32-150`, per
  `R-30-720`. A caption under a disabled row is `color.fg.secondary` on the same surface, also a
  passing row. No action in this menu uses `color.accent.text`, which `R-32-124` forbids on
  `color.bg.raised`. On iOS the plain Cupertino sheet background is translucent, so its legibility
  is proved by the protocol and the platform settings that `R-33-051` and `R-33-052` require, never
  by a ratio. Either setting replaces that background with the opaque variant of `R-33-068`.
- Screen reader: the create control MUST carry the label `Create`, per `R-30-717` and the icon-only
  pattern of `R-32-505`. A disabled row MUST announce its caption as part of its label, so `New tab,
  Open a workspace first, disabled` is spoken and the reason is never carried by `opacity.disabled`
  alone, per `R-30-141`. The grab handle MUST be excluded from the semantics tree, per `R-32-546`.
  `Cancel` MUST carry the label `Cancel`, per `R-30-717`. A successful create changes the route
  under the person, so the screen it opens carries the news in its own semantics. This menu MUST
  NOT announce it, because `R-30-742` prefers a changed node and permits a one-shot announcement in
  four cases only, and a create is not one of them.
- Screen reader, the workspace list: the back chevron MUST carry the label `Back`, per `R-30-717`,
  and each row MUST announce the workspace name with its pane count, so `worktrees, 0 panes` is
  spoken and the person can tell an empty space from a full one.
- Focus order: per `R-30-719`, the sheet traps the focus. The order is header, `New space`, `New
  tab`, the split rows, then `Cancel`. On the workspace list of `R-31-17-11` the order is the back
  chevron, the header, each workspace row top to bottom, then `Cancel`, and the focus moves to the
  first workspace row when the list opens and back to `New tab...` when the chevron closes it. On
  close the focus returns to the create control that opened the menu, per `R-32-546`.

## Open questions

- **Whether to name a new space, tab or pane at creation.** `label` is an optional parameter on all
  three methods, so the menu could ask for a name. The recommended default is to keep it out of
  version one, which is what `R-30-954` fixes today. A name field would add a form, input validation
  and keyboard handling to a menu that is otherwise one tap, and the rename action on
  `10-pane-actions.md` already names a thing after it exists. Revisit only if a person reports that
  an unnamed space is hard to find again.

## Sources

- `docs/30-ux-spec.md` - the four required states `R-30-002`, the modal restriction `R-30-005`, the
  hidden navigation on the terminal view `R-30-022`, the platform-native create control `R-30-040`
  to `R-30-042`, the empty-state rules `R-30-801` and `R-30-802`, the offline rule `R-30-807`, the
  `host_in_use` banner actions `R-30-941`, the connected-computer rule for a per-Host route
  `R-30-946`, the create policy `R-30-950` to `R-30-956`, the outcome-unknown state `R-30-518`, and
  the announcement rule `R-30-742`.
- `docs/33-platform-chrome.md` - the native control map `R-33-033`, the create-control divergence
  `R-33-034`, the destination set `R-33-035`, the create-control anatomy and its menu
  surface `R-33-037`, the iOS chrome surface list `R-33-012`, the prohibition on imitating Liquid
  Glass `R-33-013`, the bottom inset `R-33-029`, the reduce-transparency and increase-contrast
  handling `R-33-051` and `R-33-052`, the opaque variant `R-33-068`, and the terminal isolation
  `R-33-055` and `R-33-060`.
- `docs/32-design-language.md` - the app bar `R-32-510` and its trailing-control ceiling `R-32-512`,
  the bottom sheet `R-32-545` and `R-32-546`, the disabled treatment `R-32-502`, the icon map
  `R-32-401`, the size set `R-32-350`, the accent restriction `R-32-124`, the breadcrumb elision
  `R-32-573`, the label pattern `R-32-505`, and the contrast table `R-32-150`.
- `docs/31-mockups/10-pane-actions.md` - the pane action sheet, `R-31-10-01` to `R-31-10-07`, and
  the split labels it uses for the pane the person is viewing.
- `docs/31-mockups/05-host-list.md` - the app bar `+` add action.
- `docs/31-mockups/07-notifications.md` - the pane display name `R-31-07-08`, and the destination
  that carries no create control.
- `docs/03-product-decisions.md` - full terminal control for a paired phone, one active phone per
  computer, and one connected computer at a time, `R-03-043`.
- `docs/10-herdr-integration.md` - the Herdr methods `workspace.create`, `tab.create` and
  `pane.split`, and the events `workspace.created`, `tab.created` and `pane.created`.
- `docs/11-relay-protocol.md` section 4 - the `host_action` and `host_action_ack` messages that
  carry a create and return the new id, and the error `host_in_use` with close code `4006`.
- The Herdr socket API schema, read at run time with `herdr api schema --json` - the parameters of
  `workspace.create`, `tab.create` and `pane.split`, where every field is optional except
  `direction`. It is never a committed file.
