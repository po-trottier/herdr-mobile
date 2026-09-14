# 17 - Create a space, a tab or a pane

| Field | Value |
| --- | --- |
| Route | `/hosts/:hostId/agents`, menu layer |
| Surface | Device, Android and iOS |
| Spec | `docs/30-ux-spec.md` |

One control opens one menu with two actions: `New space` and `New tab`, per `R-03-134`.
Each action uses one call. The menu has no form, text field or file browser.
The workstation resolves the working directory.

A create lands on the computer this phone is connected to, and no other. Both routes above are
per-Host routes, which the app enters only for the connected computer, per `R-30-946`. This menu
therefore never asks which computer to create on.

The control that opens the menu is the same on both platforms since 2026-09-09, per `R-03-109`,
`R-30-041` and `R-33-034`: since 2026-09-10 Material's floating action button, bottom right of the
`Agents` screen (on 2026-09-09 alone it was a `New` action in the app bar; until that date Android
drew the floating button and iOS a `+` in the app bar, and this file drew both). The menu itself is
the same bottom sheet on both, per `R-33-037`, and only its background material resolves per
platform.

## The two actions

| Menu item | Label on screen | Method | Available when |
| --- | --- | --- | --- |
| `New space` | `New space` | `workspace.create` | always |
| `New tab` | `New tab in herdr-relay`, or `New tab...` | `tab.create` with the workspace context | a workspace is in context, per `R-31-17-02` |

The `New tab` label names its workspace, per `R-31-17-03`.
The action set is fixed by `R-30-950`; `worktree.create` is not offered.

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
|                Cancel                |
+--------------------------------------+
```

## Wireframe, the menu with no workspace on the computer

The computer reports no workspace. `New tab` stays disabled with its reason, per `R-30-951`.

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
|                Cancel                |
+--------------------------------------+
```

## Wireframe, the menu with no workspace selected

The computer holds more than one workspace, and no workspace is in context.
`New tab...` opens the workspace list, per `R-31-17-11`.

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
10. `Cancel`. The cancel row of `R-32-545`, centred, `size.button.primary` high, label
    `type.body.strong` in `color.fg.secondary` as written (the app drew an upper-case accent text
    action until 2026-09-08; corrected to this callout). The last row of each group draws no
    divider of its own, so the group divider of callout 11 is one hairline, never two.
11. Row. The sheet action row of `R-32-545`. Label `type.body`.
    `New space` and `New tab` share one group. A divider separates `Cancel`.
12. The disabled `New tab` in the third wireframe, with the caption `Open a workspace first` under
    it. The row is at `opacity.disabled`, per `R-32-502`, and the caption words are the ones
    `R-30-951` fixes.
13. `New tab...` in the fourth wireframe. The ellipsis says that a choice follows, which is the one
    exception `R-31-17-03` makes to a label naming its target. This tap creates nothing.
14. The workspace list in the fifth wireframe, drawn on the same sheet. Its header replaces the
    create header and carries a back chevron, the leading control glyph of `R-32-510`, which
    returns to the menu. Each row is the sheet action row of callout 11, labelled with the
    workspace `name` and the pane count from the tree snapshot. A workspace with no pane reads
    `0 panes` and is tappable, because it is the workspace this list exists for. `Cancel` closes
    the whole sheet.

## Pane actions

This menu creates spaces and tabs. The pane action sheet in `10-pane-actions.md` owns pane
splitting, per `R-03-134`.

## States

| State | Trigger | Menu shows |
| --- | --- | --- |
| Default | A workspace is in context. | The second wireframe. |
| No workspace selected | More than one workspace exists, and none is in context. | The fourth wireframe. Both rows are enabled. |
| Choosing a workspace | `New tab...` was tapped. | The fifth wireframe. The list reads the tree snapshot the app already holds, so this state never waits and never fails. |
| Loading | A create is in flight. | The tapped row shows the in-place spinner of `R-32-350` in place of its label, and every other row is disabled. The menu stays open, and refuses every dismissal path, until the acknowledgement returns, per `R-31-17-07`. |
| Created | The acknowledgement returned with the new id. | The menu closes over `motion.duration.base` with `motion.curve.exit`, `haptic.commit` fires, which the haptic table in `docs/30-ux-spec.md` assigns to an applied action, and the app routes as `R-31-17-10` requires. |
| Outcome unknown | The create left the phone and no acknowledgement arrived. | The state, its sentence and its one `Check now` control are the ones `R-30-518` fixes, and so is the reconciliation that MUST precede a second attempt. The spinner stops and every dismissal path returns. This row MUST NOT offer `Try again`, because a second `New space` makes a second workspace and a second `New tab` makes a second tab. |
| Empty | The computer reports zero workspaces. | The third wireframe. `New space` is the only enabled row, and it is the action that ends the empty state. `06-agent-list.md` shows the same computer as its own empty state. |
| Error | The computer rejected the call. | A strip appears under the header: the plain sentence `Could not create that.` with `treat.error`, the raw error text in `type.mono.code` per `R-30-803`, and one `Try again` per `R-30-804`. The menu stays open. Haptic `haptic.error`. |
| Host in use | The relay answered `host_in_use` with close code `4006`. | Every row is disabled at `opacity.disabled` and one line under the header reads `Another phone is using this computer.` The line MUST NOT offer to displace that phone, per `R-30-941`. |
| Offline | The link dropped after the menu opened. (A link already down leaves the create control itself disabled, per `R-31-17-08` as amended 2026-09-08.) | Every row is disabled at `opacity.disabled` and one line under the header reads `Offline. Creating needs the computer.` No action here is local, so `R-30-807` disables both rows. |

## Navigation

- In: the create control on `06-agent-list.md`.
- Out, `New space` and `New tab in ...`: the menu closes and the `Agents` destination stays, per
  `R-31-17-10`.
- Out, the back chevron on the workspace list: the menu, with nothing created.
- Out, `Cancel`, back, a scrim tap or a drag down: the menu closes and nothing happens. While a
  create is in flight all four do nothing, per `R-31-17-07`.

## Rules

- **R-31-17-01** The create control MUST appear on `Agents` only, not on notifications, Settings or
  the terminal view.
  The terminal view hides bottom navigation, per `R-30-022`.
  Pane splitting belongs in `10-pane-actions.md`, per `R-03-134`.
  Amended 2026-09-14: this reverses the correction earlier that day which directed splitting to this
  menu.

- **R-31-17-02** Amended 2026-09-14 per `R-03-134`: the menu MUST resolve workspace context only.
  Use the first available source: the workspace last created on this computer; the only workspace in
  the snapshot; the workspace picker.
  The last-created id comes from the acknowledgement, per `R-11-205`. `R-31-17-11` owns the picker.
  The menu MUST NOT use a workspace header as context: that header toggles collapse, not selection.

- **R-31-17-03** The `New tab` label MUST name its target workspace from the tree snapshot.
  The label MUST stay on one line and elide long names from the front, per `R-32-573`.
  When the person must choose a workspace, the label MUST read `New tab...`, per `R-31-17-02`.
  The label MUST NOT shorten to `New tab` while a target exists.

- **R-31-17-04** Retired 2026-09-14 per `R-03-134`.

- **R-31-17-05** Retired 2026-09-14 per `R-03-134`.

- **R-31-17-06** The menu MUST offer only `New space` and `New tab`, per `R-03-134`.

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
- **R-31-17-10** After `New space` or `New tab`, the menu MUST close and remain on `Agents`.
  The new node has no agent yet; `R-30-408` excludes it until it has one.

- **R-31-17-11** When `R-31-17-02` reaches its last source, `New tab` MUST open the workspace list
  of the fifth wireframe inside the same sheet, and MUST create the tab in the workspace the person
  taps. The list MUST hold every workspace the tree snapshot carries, including a workspace with no
  pane. Such a workspace is otherwise unreachable: `R-30-408`
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
  tab`, `Cancel`. On the workspace list of `R-31-17-11` the order is the back
  chevron, the header, each workspace row top to bottom, then `Cancel`, and the focus moves to the
  first workspace row when the list opens and back to `New tab...` when the chevron closes it. On
  close the focus returns to the create control that opened the menu, per `R-32-546`.

## Open questions

None.

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
- `docs/31-mockups/10-pane-actions.md` - pane splitting, per `R-31-10-12` to `R-31-10-14`.

- `docs/31-mockups/05-host-list.md` - the app bar `+` add action.
- `docs/31-mockups/07-notifications.md` - the pane display name `R-31-07-08`, and the destination
  that carries no create control.
- `docs/03-product-decisions.md` - full terminal control for a paired phone, one active phone per
  computer, and one connected computer at a time, `R-03-043`.
- `docs/10-herdr-integration.md` - the Herdr methods `workspace.create`, `tab.create` and
  and the events `workspace.created`, `tab.created`.
- `docs/11-relay-protocol.md` section 4 - the `host_action` and `host_action_ack` messages that
  carry a create and return the new id, and the error `host_in_use` with close code `4006`.
- The Herdr socket API schema: `workspace.create` and `tab.create`.
