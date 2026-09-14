# 18 - Host actions

| Field | Value |
| --- | --- |
| Route | `/hosts/:hostId/panes/:paneId/actions` |
| Surface | Device, Android and iOS |
| Spec | `docs/30-ux-spec.md` |

A Herdr plugin publishes named actions, and the workstation binds some of them to a key. A phone
cannot press a prefix chord comfortably, so this screen offers the same actions as rows. It invokes
each one by its `action_id`, per `R-30-963`.

This screen is the workstation's own plugin actions, and it is not the phone's own keys. The
terminal carries the key row of `docs/31-mockups/09-key-row.md`, whose one expansion holds every
key a phone keyboard lacks and sends one key to the pane. This screen invokes a
plugin on the computer, and the result appears where the plugin puts it, which is usually a pane
on the workstation. `R-31-09-24` owns the keys; `R-31-18-01` owns this screen's one entry (amended
2026-09-10 per `R-03-116`: the terminal app bar carried a `Shortcuts` control until then, and the
retired `R-31-08-24` owned it).

One entry exists: the `Plugin actions` row of the pane action sheet, `10-pane-actions.md` callout
5a, which supplies the pane on screen as the scope. Decided 2026-09-09 by the product owner, per
`R-03-055`: a plugin acts on a pane, so the person reaches it where the pane is, and the `Agents`
screen carries no plugin control. The route carries the pane id, and the caller resolves the three
breadcrumb names from the tree snapshot, per `R-31-18-05`. The computer-scope drawings below stay
because the caller falls back to the computer alone when it cannot read the tree or the pane has
left it; the shape a person meets is the pane-scope drawing.

History. The entry moved twice. From 2026-09-03 the terminal app bar carried a control that pushed
this route; on 2026-09-08 the product owner replaced it with `Shortcuts`, because a key and an
invocation on the computer were confused, and the `Agents` app bar's `Computer actions` control at
`/hosts/:hostId/actions` became the one entry, computer scoped. On 2026-09-09 the product owner
rejected that placement on the emulator, per `R-03-055`, and this file returned the entry to the
pane, on the sheet and not in the app bar, so the terminal app bar keeps `Shortcuts` alone.

Half of these actions open a pane. A measured workstation published twenty actions, and ten of them
open, focus or close one: `herdr-scheduled/open` opens the scheduled job manager, and three
`herdr-sidebar` actions open or close a sidebar pane. The phone renders a pane, so an action that
opens one is the most useful kind on this screen, not the least. A tap that opened a pane and then
stranded the person on this list would defeat the whole screen, so `R-31-18-13` carries them to the
pane the action opened.

Every action on this screen belongs to the computer this phone is connected to. The app enters this
per-Host route only for the connected computer, per `R-30-946`, so no row here can reach a second
computer.

The socket API carries no keybinding, no hotkey and no configuration read. The method list in
`docs/10-herdr-integration.md` holds none of them. A Herdr `prefix + key` binding is client-side
configuration on the workstation, and it never crosses the socket, so this screen cannot show a
person their own chord. It shows the action instead, which is the better target anyway, and
`R-30-963` holds both reasons. The phone's own key row is a different set: a fixed vocabulary of
keys the app itself owns, identical on every workstation, per
`R-31-09-24`. Neither surface reads a person's configured bindings, because no method returns
them.

The Device receives five fields per action and no more: `plugin_id`, `action_id`, `title`,
`description` and `contexts`. `R-30-964` and `R-11-209` fix that projection, because the raw Herdr
record carries a `command` array of real shell commands and the plugin list carries `manifest_path`
and `plugin_root`. Those name directories on the person's own workstation. This screen therefore has
nothing to draw except a title, a description, and the plugin each action came from. The list
arrives in the `action_list` message that `docs/11-relay-protocol.md` defines.

The Device never sees `platforms`, and never sees a duplicate pair. Of the twenty measured actions,
five were the same action published twice, once for `linux` and `macos` and once for `windows`:
`open` beside `open-windows`, `sync` beside `sync-windows`, `open-git` beside `open-git-windows`.
`R-30-964` and `R-11-210` keep that twin off the wire, because the Host filters by its own platform
before it projects. Fifteen rows reach the phone, not twenty. The phone therefore has nothing to
de-duplicate, and no wireframe in this file draws a duplicate pair.

## What a row can and cannot show

| Field | On the row | Reason |
| --- | --- | --- |
| `title` | the first line | the plugin author's own words |
| `description` | the line below the title, in full | the only explanation that exists, and the only warning a row can carry |
| `plugin_id` | the group header | the only grouping the projected data supports |
| `contexts` | not drawn, and never as a scope word; it decides whether the row is present at all | `R-30-966`, `R-11-211`, `R-31-18-12` |
| `action_id` | never drawn | an identifier is not a label |
| `command`, `manifest_path`, `plugin_root` | never sent and never drawn | `R-30-964`, `R-11-209` |
| `platforms` | never sent and never drawn; the Host filters by its own platform first, so no duplicate pair ever arrives | `R-30-964`, `R-11-210` |
| An icon | none | `R-32-401` forbids a name outside its map, and holds none for a plugin action |

There is no icon per row, and that is a data fact rather than a style choice. Herdr supplies no
glyph and no category for an action, so any icon here would be the app guessing. A row is text.

## Wireframe, the entry row on the pane action sheet

`10-pane-actions.md` owns every other part of this drawing. The `Plugin actions` row `(e)` is the
only line this file cares about. Amended 2026-09-09 per `R-03-055`; until then two other drawings
here placed the entry in the `Agents` app bar, and the `## Retired rules` section holds the note.

```text
+--------------------------------------+
|                 ====                 |
| plugin / pane 1                      |
| claude  -  working 12s               |
+--------------------------------------+
| Send a prompt to claude            > |
| Plugin actions (e)                 > |
+--------------------------------------+
| Split right                          |
| ...                                  |
+--------------------------------------+
```

## Why the entry is on the pane

A plugin action is invoked with a context, and the context that matters is a pane: `R-11-215`
makes the Host build the invocation from the most specific surface the Device names, and half of
the measured actions open, focus or close a pane. The person who wants one is looking at a pane.
The `Agents` app bar carried the entry from 2026-09-04 to 2026-09-09, and it could supply the
computer alone, so every `tab` or `pane` action was hidden there and the hidden-row line of
`R-31-18-06` could name no step that brought it back. The product owner rejected that on the
emulator, per `R-03-055`. The sheet is where every other action on a pane already lives, and one
row there costs nothing the `R-32-512` ceiling guards. `R-31-10-03` holds the sheet's row count.

Every frame of the pushed screen below omits the bottom navigation bar. That is not a drawing
convention here: the route is pushed on top of the terminal, which hides the bar per `R-30-022`, so
this screen is the same full-screen exception, per `R-30-045`.

## Wireframe, the screen, scoped to a pane

Two groups are open and one is collapsed, so the drawing shows both header states and the count that
survives a collapse. Every title and every description below is one a live workstation reported.
This is the shape the entry row produces: the pane on screen is the scope.

```text
+--------------------------------------+
| <  Actions on patrick-desk           |
+--------------------------------------+
| A tap sends pane 1 as the context.   |
| herdr-relay > plugin > pane 1        |
+--------------------------------------+
| - herdr-scheduled          2 actions |
|   Scheduled jobs                     |
|   Opens the scheduled job manager    |
|   on Windows.                        |
|   Sync scheduled jobs                |
|   Reconciles the job files into      |
|   Windows Task Scheduler.            |
+--------------------------------------+
| - herdr-sidebar            3 actions |
|   Toggle source control              |
|   Open a separate Source Control     |
|   pane (focus it if open; close it   |
|   if focused).                       |
|   Toggle sidebar                     |
|   Redeploy sidebar panes             |
|   Close all sidebar panes in every   |
|   workspace so they respawn on the   |
|   latest build.                      |
+--------------------------------------+
| + tab-smart-rename         5 actions |
+--------------------------------------+
```

## Wireframe, context gating, with a pane in scope

`tab-smart-rename` is expanded on the same scope. `Smart Rename: reset tab` declares `tab` and
`pane`, and the scope satisfies both, so the row is present. Its four siblings declare `global` and
`workspace`, or declare nothing at all, so they are present on every scope.

```text
+--------------------------------------+
| <  Actions on patrick-desk           |
+--------------------------------------+
| A tap sends pane 1 as the context.   |
| herdr-relay > plugin > pane 1        |
+--------------------------------------+
| - tab-smart-rename         5 actions |
|   Smart Rename: current tab          |
|   Smart Rename: all tabs             |
|   Smart Rename: status               |
|   Smart Rename: start                |
|   Smart Rename: reset tab            |
+--------------------------------------+
```

## Wireframe, context gating, with the computer alone in scope

The caller supplies the computer alone when it could not read the tree snapshot, or when the pane
has left it, so no workspace, no tab and no pane is in scope (amended 2026-09-09 per `R-03-055`;
until then this was the shape the `Agents` entry produced on every visit). `Smart Rename: reset
tab` cannot be satisfied, so it is absent and the count reads four. The line at the foot gives the
exact number missing, and nothing more: no step on this screen brings the row back.

```text
+--------------------------------------+
| <  Actions on patrick-desk           |
+--------------------------------------+
| A tap sends patrick-desk as the      |
| context.                             |
+--------------------------------------+
| - tab-smart-rename         4 actions |
|   Smart Rename: current tab          |
|   Smart Rename: all tabs             |
|   Smart Rename: status               |
|   Smart Rename: start                |
+--------------------------------------+
| 1 action needs a tab or a pane.      |
+--------------------------------------+
```

## Wireframe, a tap that opened a pane

`Scheduled jobs` was tapped, and the acknowledgement of `R-11-217` named one new pane. The strip
under the app bar names that pane and routes to it. `R-30-520` owns whether the app offers the
route or takes it, and `R-31-18-13` owns what this screen draws.

```text
+--------------------------------------+
| <  Actions on patrick-desk           |
+--------------------------------------+
| Scheduled jobs opened a pane.      > |
| herdr-relay > plugin > jobs          |
+--------------------------------------+
| A tap sends pane 1 as the context.   |
| herdr-relay > plugin > pane 1        |
+--------------------------------------+
| - herdr-scheduled          2 actions |
|   Scheduled jobs                     |
|   Opens the scheduled job manager    |
|   on Windows.                        |
+--------------------------------------+
```

## Wireframe, a tap that named no pane

`Toggle sidebar` was tapped and the acknowledgement named no pane. `R-11-217a` sends a pane id only
when exactly one pane appeared that was not there before, and `R-11-217b` sends none when a toggle
closed its pane, so this is the common answer and never a failure. The screen stays, the row stays,
and the snackbar carries the result.

```text
+--------------------------------------+
| <  Actions on patrick-desk           |
+--------------------------------------+
| A tap sends pane 1 as the context.   |
| herdr-relay > plugin > pane 1        |
+--------------------------------------+
| - herdr-sidebar            3 actions |
|   Toggle source control              |
|   Open a separate Source Control     |
|   pane (focus it if open; close it   |
|   if focused).                       |
|   Toggle sidebar                     |
|   Redeploy sidebar panes             |
|   Close all sidebar panes in every   |
|   workspace so they respawn on the   |
|   latest build.                      |
+--------------------------------------+
|                                      |
|  Sent Toggle sidebar. Agents shows   |
|  what exists now.                    |
+--------------------------------------+
```

## Wireframe, the outcome is unknown

`Toggle sidebar` was tapped and the link dropped before any answer came back. The workstation may
have run it, and the phone cannot tell. `R-30-518` owns this state everywhere in the app, and it
forbids the one-tap retry that would close the pane the first tap opened. Every row stays disabled
until the person refreshes.

```text
+--------------------------------------+
| <  Actions on patrick-desk           |
+--------------------------------------+
| ! Toggle sidebar may have run on     |
|   patrick-desk. The link dropped     |
|   before the answer came back.       |
|   [ Refresh actions ]                |
+--------------------------------------+
| A tap sends pane 1 as the context.   |
| herdr-relay > plugin > pane 1        |
+--------------------------------------+
| - herdr-scheduled          2 actions |
|   Scheduled jobs                     |
|   Opens the scheduled job manager    |
|   on Windows.                        |
|   Sync scheduled jobs                |
|   Reconciles the job files into      |
|   Windows Task Scheduler.            |
+--------------------------------------+
```

## Wireframe, a plugin that went away after the list was read

The list held `herdr-sidebar` when the screen opened. Somebody switched that plugin off on the
workstation, and the tap arrived after that. The failure is on screen, never swallowed.

```text
+--------------------------------------+
| <  Actions on patrick-desk           |
+--------------------------------------+
| ! herdr-sidebar is switched off on   |
|   patrick-desk.                      |
|   plugin_disabled                    |
|   [ Refresh actions ]                |
+--------------------------------------+
| A tap sends pane 1 as the context.   |
| herdr-relay > plugin > pane 1        |
+--------------------------------------+
| - tab-smart-rename         5 actions |
|   Smart Rename: current tab          |
|   Smart Rename: all tabs             |
+--------------------------------------+
```

## Wireframe, no plugin offers an action

A workstation with no plugin installed has no action at all. That is a normal workstation and not a
fault, and the words say so.

```text
+--------------------------------------+
| <  Actions on patrick-desk           |
+--------------------------------------+
| No plugin on patrick-desk offers an  |
| action.                              |
| Install a Herdr plugin on the        |
| computer, then come back.            |
+--------------------------------------+
```

## Callouts

1. `Plugin actions (e)` in the first wireframe. A sheet action row of `10-pane-actions.md` callout
   5a, with the icon `R-32-401` names for `Host actions`. The wireframe writes it `(e)`, which is an
   ASCII convention and not the rendered glyph. It routes to
   `/hosts/:hostId/panes/:paneId/actions` with the pane on screen as the scope (amended 2026-09-09
   per `R-03-055`; the `Agents` app bar carried an `(e)` control until then).
2. `plugin / pane 1`, `claude  -  working 12s`, `Send a prompt to claude` and `Split right` in the
   first wireframe. `10-pane-actions.md` owns every one of them and this file changes none of it.
3. The trailing `>` on `Plugin actions` in the first wireframe. The chevron of `10-pane-actions.md`
   callout 5: the row opens a screen instead of acting at once.
4. `<  Actions on patrick-desk`. The back control and the title, in the app bar of `R-32-510`. The
   title names the computer, because an action lands on one machine, and `R-31-18-01` requires the
   route to carry it so the iOS back control shows the right previous title. This file draws the
   control `<` and names no glyph: each platform's navigation component owns the glyph, the
   localised label and the pop gesture, per `R-33-070`.
5. `A tap sends pane 1 as the context.` The scope sentence, the strip of
   `docs/32-design-language.md` section 7.22 in `type.caption`. It names the context the invocation
   carries, per `R-30-964` and `R-31-18-05`, and it names no effect. `Sync scheduled jobs` writes
   into Windows Task Scheduler and touches pane 1 not at all, so a sentence that promised an effect
   would be false on that very row. The context that was sent is what is true of every row.
6. `herdr-relay > plugin > pane 1`. The breadcrumb of `docs/32-design-language.md` section 7.24, one
   line, eliding from the front per `R-32-573`. It is absent when the computer alone is in scope, as
   the fourth wireframe shows.
7. `- herdr-scheduled          2 actions`. A tier 1 section header of `R-32-563`, collapsible, with
   the plugin id as its label and the count trailing. The label keeps the plugin author's case, per
   `R-32-567`. The expander reads `-` when open and `+` when closed, per `R-32-568`.
8. `+ tab-smart-rename         5 actions`. The same header collapsed. The count stays on screen, so
   a person sees that a closed group still holds five actions.
9. `Scheduled jobs`. An action row, which is the two-line list row of `docs/32-design-language.md`
   section 7.4 with no leading icon and no trailing anything. Title in `type.body.strong` in
   `color.fg.primary`. The row carries no chevron, because a tap invokes the action here and opens
   no screen. Its indent is `space.4`, the list edge of `R-32-302`. This callout covers
   every other title drawn in this file the same way: `Sync scheduled jobs`,
   `Toggle source control`, `Redeploy sidebar panes`, `Smart Rename: current tab`,
   `Smart Rename: all tabs`, `Smart Rename: status` and `Smart Rename: start`.
10. `Opens the scheduled job manager` and `on Windows.` The `description`, which is the secondary
    line of that same list row: `type.caption` in `color.fg.secondary`, on the title's inset. It
    covers every other description drawn in this file the same way, each one wrapped and none
    clamped: `Reconciles the job files into` and `Windows Task Scheduler.`, plus the two longer
    ones that callout 11 names, whose first lines are `Open a separate Source Control` and
    `Close all sidebar panes in every`.
11. `pane (focus it if open; close it` and `if focused).` The rest of that same description, wrapped
    and not elided. `R-31-18-03` shows a `description` in full, because it is the only warning a
    row can carry. `Close all sidebar panes in every`, `workspace so they respawn on the` and
    `latest build.` is the row that proves why: that sentence is the whole warning on the one
    measured action that reaches every workspace, and an earlier draft of this file hid it.
12. `Toggle sidebar`, drawn with no second line. The live row carries a description, and this file
    captured only part of it, so the drawing shows none: a mockup MUST NOT finish a plugin author's
    sentence. The shape drawn here is the one-line variant `R-31-18-03` requires when a
    `description` is genuinely absent, which every `tab-smart-rename` row in the third wireframe
    also shows. The app MUST NOT invent a description.
13. `Smart Rename: reset tab`, present in the third wireframe and absent from the fourth. It
    declares `tab` and `pane`, so the scope decides whether the row exists at all, per `R-30-966`.
14. `1 action needs a tab or a pane.` The hidden-row line of `R-31-18-06`, which reads
    `N actions need a tab or a pane.` above one. It gives the exact count, so a shorter list is
    never a puzzle. It names no next step (amended 2026-09-09 per `R-03-055`): on a pane scope the
    only hidden rows are `selection` actions, which no step reaches in version one, per
    `R-31-18-07`; on the computer fallback the tree could not be read, so nothing on this screen
    brings a row back, and a line that told a person to open a pane would send them on an errand
    that changes nothing.
15. `Sent Toggle sidebar. Agents shows` and `what exists now.` The snackbar of
    `docs/32-design-language.md` section 7.22, the same result surface `R-31-13-13` uses for
    `Disconnect`. The wording stops at `Sent`, per `R-31-18-08`. It does not name the computer,
    because the app bar two lines above already does and `R-30-946` permits only one connected
    computer. The second sentence is there because this one answer covers three different truths:
    the action opened no pane, or it closed one, or it changed many. `Redeploy sidebar panes` is the
    extreme case and it reaches every workspace, so the words MUST NOT read as `nothing happened`.
    They point instead at the one surface that shows what exists now: the `Workspace` axis of
    `06-agent-list.md`, since the `Panes` destination left on 2026-09-04.
16. `! herdr-sidebar is switched off on`, `patrick-desk.`, `plugin_disabled` and
    `[ Refresh actions ]`. The error state of `R-32-555`: the plain sentence, the raw error string
    in `type.mono.code` per `R-30-803`, and exactly one recovery per `R-30-804`. `R-11-218` owns
    that error code. The label reads `Refresh actions` and not `Try again`, because it reads the
    action list again and never invokes the action a second time, per `R-31-18-09`. The
    `Error, list` state keeps `Try again`, because there the failed request and the recovery are the
    same request.
17. `No plugin on patrick-desk offers an`, `action.`, `Install a Herdr plugin on the` and
    `computer, then come back.` The empty state of `R-32-553`, left aligned, naming the absent thing
    and the next step per `R-30-802`. Amended 2026-09-09 per `R-03-107`: the anatomy of
    `docs/32-design-language.md` section 7.19, the first sentence as the title in `type.title`, the
    display face of the screen titles, in `color.accent.text`, and the second as the sentence in
    `type.body` `color.fg.secondary`, `space.2` under it, both at `space.4`. No eyebrow: the app
    bar already names the screen. It offers no action of its own, because a plugin is installed on
    the computer, per `R-30-801`.
18. `Scheduled jobs opened a pane.` and the trailing `>` in the fifth wireframe. The pane strip of
    `R-31-18-13`, tappable across its whole width like the offline strip of `R-32-561`, routing to
    `/hosts/:hostId/panes/:paneId`. The verb `opened` is provable: `R-11-217a` sends a pane id only
    when exactly one pane appeared that was not there before, so an id names a new pane and never
    one that was merely focused. The strip carries no text action and no dismiss control, and both
    are choices about this strip rather than prohibitions inherited from anywhere: `R-32-561`
    permits a text action and `R-32-526` gives it an ink for a raised surface. Both are refused
    because the strip already spends its second line on the breadcrumb, and the whole-width tap
    already reaches the only destination there is. `R-31-18-13` names the three ways it goes away.
19. `herdr-relay > plugin > jobs` in the fifth wireframe. The breadcrumb of callout 6, naming the
    new pane in place of the scope. It is the strip's own second line, so a person reads which pane
    the tap opens before taking it.
20. `! Toggle sidebar may have run on`, `patrick-desk. The link dropped`,
    `before the answer came back.` and `[ Refresh actions ]` in the seventh wireframe. The
    outcome-unknown state of `R-30-518`. The words say `may have run` because that is the whole of
    what the phone knows. There is no retry at all, per `R-31-18-15`: one more tap on
    `Toggle sidebar` would close the pane the first tap opened.
21. The `herdr-scheduled` rows in the seventh wireframe. Every row is disabled at
    `opacity.disabled` until the person refreshes, per `R-30-518` and `R-31-18-15`. A drawing cannot
    show opacity, so the rule carries it.
22. The absent `herdr-relay` group, in every wireframe in this file. A real Host runs that plugin,
    so its four actions will be in the list, and the app removes the whole group before it draws,
    per `R-31-18-16`. No line reports the removal, because the person can do nothing about it.
23. Ground (added 2026-09-09, per `R-03-107`; amended the same day, per the amended `R-03-107`).
    A list with rows paints plain `color.bg.base` under the opaque app bar: no grid and no paper
    block behind the scope strip, the plugin headers, the rows, the hidden-row strip, the skeleton
    or the error block, and the list ends at its last strip or row, per `R-03-109`. Only the
    no-plugin block of the ninth wireframe takes the ground grid of `docs/32-design-language.md`
    `R-32-332`, painted across the body under the bar and the state strips, and the watermark of
    `R-32-554`, the silhouette in `color.bg.grid` bottom-right. The drawings omit the grid.

## Context gating

`contexts` is the only field that changes what this screen holds. `R-30-966` owns the rule and
`R-11-211` owns the wire side of it. The measured data is the reason both matter: a live
workstation left the field out on half of its actions, so the absent case is the common case and
not an edge.

| Declared `contexts` | Present when | Drawn in |
| --- | --- | --- |
| absent | always | every wireframe that draws a row |
| `global` | always | every wireframe that draws a row |
| `global`, `workspace` | always; a paired phone is always on one computer | the third wireframe and the fourth |
| `tab`, `pane` | a tab or a pane is in scope | the third wireframe only |
| `selection` | never in version one, per `R-31-18-07` | not drawn |

Two measured actions carry the whole idea. `Smart Rename: reset tab` declares `tab` and `pane`, so
it appears on a pane scope and disappears on a computer scope. `Smart Rename: start` declares
`global` and `workspace`, so it appears on both. The two are therefore not both available from the
same place, and the scope sentence of callout 5 is what tells a person which place they are in.

A `selection` action is unreachable in version one, and the honest reason is worth stating instead
of hiding. A phone holds a text selection only inside the terminal view, and this screen is not that
view. More importantly, `R-30-964` and `R-11-216` keep `selected_text` out of the Device's hands
entirely, and `R-11-215` makes the Host build the invocation context itself. An action invoked from
here could therefore run only against whatever the workstation had selected. That is a different
thing from what the person on the phone meant, and it is exactly the confusion this screen exists
to remove.

## The destructive-action decision

Every other risky surface in this app asks first. This one asks nothing, and that needs a reason
rather than an apology. There are two questions here, and they have different answers.

**A third-party plugin: classify nothing, and show the author's own words instead.**
`PluginActionInfo` carries no field that marks an action as changing anything, which `R-11-220`
records as an upstream gap, and `R-30-967` fixes the consequence. A heuristic over the title text
would call `Smart Rename: all tabs` safe and `Sync scheduled jobs` dangerous by matching English
words, and it would be wrong the first time a plugin author writes a title in another language.

Being unable to classify an action is a reason to be careful with it, and not a reason to hide the
danger. So this screen makes the one real warning visible instead of raising a dialog that can say
nothing the row does not. `Redeploy sidebar panes` describes itself:
`Close all sidebar panes in every workspace so they respawn on the latest build.` That sentence is
the whole warning, the person who wrote the action wrote it, and an earlier draft of this file
clamped it to two lines and drew that row with none at all. A confirmation dialog whose body can
only repeat the title is a speed bump, and a speed bump teaches nobody what an action does.
`R-31-18-03` therefore shows every `description` in full, before the row can invoke.

**The `herdr-relay` plugin: hide its rows.** This is a different question, because this project
writes that manifest. `R-31-16-33` names its four actions, the title each one shows on the phone,
and which two of them are destructive, so the `plugin_id` `herdr-relay` is a known identity and not
a guess, and `R-30-967` does not reach it. Two of the four are destructive, and all four are
unusable or self-destroying from a phone. Those are two different reasons and both hold.

| Action | Why the phone MUST NOT offer it |
| --- | --- |
| `refresh` | It revokes the phone doing the tapping, so no phone can undo it. |
| `stop` | It closes the transport the answer would return on. |
| `pair` | It opens the pane that shows the QR code and the six-word phrase, so `R-31-18-13` would render a live pairing secret onto an already-paired phone. |
| `clients` | It writes to a Host log the phone cannot read, and `14-devices.md` already lists every paired phone. |

Read no `action_id` as English. `refresh` is the action that revokes every phone, and `R-31-16-33`
records that same trap on the workstation side. A person on the phone reads only the `title`,
because `R-31-18-03` and `R-31-18-12` keep an identifier off a row, so the guard MUST match on the
`plugin_id` field and never on a word in a label.

The two that `R-31-16-33` marks destructive are worse than that from a phone: they are
self-terminating. `R-11-217a` gives the Host a 200 ms settle window to attribute a pane, and a Host
that has just been told to stop the relay cannot finish that window, so the acknowledgement never
arrives either. The person is left in the outcome-unknown state of `R-30-518`, on an action no
phone can undo.

Hiding the group costs the person nothing, because no row in it does anything they can see or want,
and it removes the only path by which this screen could revoke the phone in their own hand.
`R-31-18-16` holds the rule. `R-30-967` needs one sentence to record the carve-out, and that
sentence belongs to `docs/30-ux-spec.md`.

**What stands in place of a dialog.** One explicit tap on a labelled row that shows its whole
description, with no swipe pane, no long press and no repeat on hold, per `R-30-965`. One tap that
cannot become two, per `R-31-18-15`. And no retry after an unknown outcome, per `R-30-518`, because
a second invocation of an unclassified action is a second unknown change. The missing upstream flag
stays in `## Open questions` with its recommended default.

## States

| State | Trigger | Screen shows |
| --- | --- | --- |
| Default | The action list returned and a pane is in scope. | The second wireframe. |
| Default, computer scope | The action list returned and the caller supplied the computer alone, because it could not read the tree or the pane has left it. | The fourth wireframe. Every action that needs no tab and no pane stays, and the hidden-row line reports the rest. |
| Loading | The action list has not returned. | Two skeleton rows after 150 ms, per `R-30-004` and `R-32-560`, under the app bar and the scope sentence, which `R-30-800` keeps on screen. |
| Empty | The computer reports no plugin action at all. | The ninth wireframe. A computer with no plugin installed is normal, so the words MUST NOT read as a fault. |
| Error, list | The action list request failed. | A block: `Could not read the actions on patrick-desk.` with `treat.error`, the raw error in `type.mono.code` per `R-30-803`, and one `Try again` per `R-30-804`. No row is drawn, because half a list is a guess. |
| Error, invoke | The invocation returned an error, for example a plugin switched off since the list was read. | The eighth wireframe. The list stays on screen, the strip names the plugin and carries the raw code, and `Refresh actions` reads the list again, per `R-31-18-09`. Haptic `haptic.error`. |
| Invoking | A row was tapped and no answer has arrived. | That row shows the in-place spinner of `R-32-350` in place of its title, and every row is disabled at `opacity.disabled`, the tapped one included. The request is latched before the repaint, so one tap cannot become two, per `R-31-18-15`. The screen stays, per `R-31-18-08`. |
| Invoked, a pane | The acknowledgement carried a `pane_id` that the tree snapshot holds. | The pane strip of the fifth wireframe, and `haptic.commit`. `R-30-520` owns whether the app offers the route or takes it, and `R-31-18-13` owns the drawing. |
| Invoked, no pane | The acknowledgement carried no `pane_id`. | The snackbar of the sixth wireframe, and `haptic.commit`, which the haptic table in `docs/30-ux-spec.md` assigns to an applied action. No route changes. This is the common answer and never a failure, per `R-11-217b` and `R-31-18-14`. |
| Outcome unknown | The invocation timed out, or the link dropped, before any answer arrived. | The seventh wireframe. Every row stays disabled, no retry is offered, and `Refresh actions` reconciles by reading the action list and the tree snapshot again, per `R-30-518` and `R-31-18-15`. No haptic: nothing was applied and nothing failed. |
| Host in use | The relay answered `host_in_use`. | The banner of `R-30-940` and `R-30-941` sits under the app bar, and every row is disabled at `opacity.disabled`. This phone has no authority over that computer, so a tap MUST do nothing at all. The last known list stays visible and timestamped, per `R-30-805`. |
| Offline | No route to the relay. | The last known list stays visible and dimmed, with the header line `Offline. This list is from 14:02.`, per `R-30-805`. Every row is disabled, because no action here is local, per `R-30-807`. The strip routes to diagnostics, per `R-32-561`. |

## Navigation

- In: the `Plugin actions` row of the pane action sheet, `10-pane-actions.md` callout 5a, and
  nothing else. It supplies the pane on screen as the scope (amended 2026-09-09 per `R-03-055`;
  the `Agents` app bar was the entry from 2026-09-04 to 2026-09-09, and the terminal app bar from
  2026-09-03 to 2026-09-08).
- Out, back: the terminal of `08-terminal.md` the sheet opened over, per `R-30-031`.
- Out, a row tap that named a pane: `/hosts/:hostId/panes/:paneId`, mockup `08-terminal.md`, from
  the pane strip of `R-31-18-13`. Back returns here, per `R-30-031`.
- Out, a row tap that named no pane: no route change at all. The result arrives as the snackbar of
  callout 15.
- Out, the `Why` action of the `host_in_use` banner, and the offline strip:
  `/hosts/:hostId/diagnostics`, mockup `13-connection.md`, per `R-30-941` and `R-30-806`.
- Out, nothing else. No row and no header opens a screen. The pane strip is the only row-shaped
  thing on this screen that routes anywhere.

## Rules

- **R-31-18-01** The screen MUST be the route `/hosts/:hostId/panes/:paneId/actions`, and it MUST
  be reached from one row of the pane action sheet, labelled `Plugin actions`, per
  `10-pane-actions.md` callout 5a. Amended 2026-09-09 per `R-03-055`, decided by the product owner:
  a plugin acts on a pane, so the person reaches it where the pane is. The route MUST carry the
  pane on screen as the scope, and the caller MUST resolve the three breadcrumb names from the tree
  snapshot, per `R-31-18-05`; when it cannot read the tree, or the pane has left it, the caller
  MUST fall back to the computer alone, so that the scope sentence and the gating state one truth.
  The `Agents` destination MUST NOT carry a plugin-actions control, and no app bar MUST carry one:
  the terminal app bar carries no local control of its own since 2026-09-10, per the retired
  `R-31-08-24`, and a
  control there would return the confusion between a key and an invocation on the computer that
  the 2026-09-08 change removed. The screen MUST NOT become a fourth bottom destination, per
  `R-30-021`, and MUST NOT be placed on `Notifications`, which acts on nothing. The route is pushed
  on top of the terminal, on the root navigator, so it is the terminal's own full-screen exception
  of `R-30-022` and `R-30-045`, not a second one. That route is the only one this screen has.
  History: the `Agents` app bar carried the entry at `/hosts/:hostId/actions`, computer scoped,
  from 2026-09-04 to 2026-09-09, and the terminal app bar carried a pane-scoped entry from
  2026-09-03 to 2026-09-08; both are retired with their routes, and the `## Retired rules` section
  holds the note.
- **R-31-18-02** These actions MUST NOT be added to the pane action sheet. `R-31-10-03` caps that
  sheet at nine rows, and a measured workstation offers fifteen once the Host has filtered by its
  own platform, per `R-11-210`. A separate screen is the only shape that fits. The one row that
  opens this screen, `10-pane-actions.md` callout 5a, is not one of these actions: it is the entry
  `R-03-055` requires, and it counts as one of the nine (amended 2026-09-09).
- **R-31-18-03** A row MUST be the two-line list row of `docs/32-design-language.md` section 7.4,
  carrying the `title` on the first line and the `description` below it. It MUST carry no leading
  icon, no trailing chevron and no state word. The `description` MUST be shown in full: it MUST NOT
  clamp, MUST NOT elide, and MUST NOT hide behind a disclosure control. It is the only warning a
  row can carry, and `Close all sidebar panes in every workspace so they respawn on the latest
  build.` is the measured proof, so a sighted person MUST NOT have to invoke an action to learn what
  a screen reader is already told. The row grows and the list scrolls. A row whose `description` is
  absent MUST be the one-line variant of the same row, and the app MUST NOT invent a description.
  `R-30-964` owns what MUST NOT reach the row at all.
- **R-31-18-04** Rows MUST be grouped by `plugin_id` and by nothing else, under the collapsible tier
  1 header of `R-32-563` with the count trailing. `plugin_id` is the only grouping the projected
  data supports. A collapsed group MUST keep its count on screen.
- **R-31-18-05** The screen MUST name the context it sends in one sentence above the first group, in
  the words of callout 5, and MUST show the breadcrumb of `docs/32-design-language.md` section 7.24
  under it whenever a pane is in scope. The sentence MUST name the context the invocation carries,
  per `R-30-964`, and MUST NOT name an effect. `contexts` cannot prove an effect, per `R-31-18-12`,
  and `Sync scheduled jobs` writes into Windows Task Scheduler without touching the pane in scope at
  all, so a sentence such as `These actions hit pane 1` would be false on that row. The three
  segments MUST come from the tree snapshot: the workspace `name`, the tab `title` and the pane
  display name of `R-31-07-08`. `R-30-966` decides which rows exist; this rule lets the
  person see which tab or pane the invocation will carry before they tap.
- **R-31-18-06** When the scope hides one row or more, the screen MUST show one line at the foot
  giving the exact count, in the words of callout 14. A silently shorter list breaks the promise
  `R-32-502` makes everywhere else, that a person always learns why something is out of reach. The
  line MUST NOT name a next step. It carried `Open one, then come back.` until 2026-09-08, when the
  pane-scoped entry was retired, and an instruction that cannot change the list is worse than none.
  The pane-scoped entry returned on 2026-09-09 per `R-03-055`, and the line still names no step: on
  a pane scope only `selection` actions are hidden, per `R-31-18-07`, and no step reaches those.
- **R-31-18-07** The screen MUST NOT offer a `selection` action in version one. `R-30-964` and
  `R-11-216` keep `selected_text` out of the Device's reach, and `R-11-215` gives the Host the job
  of building the invocation context, so an invocation from here could carry only the workstation's
  own selection, which is not the text the person on the phone can see. Such a row MUST be absent
  and MUST be counted in the line of `R-31-18-06`.
- **R-31-18-08** Every tap MUST report its result, and the result has exactly three shapes. The
  screen MUST stay put and MUST show the spinner of `R-32-350` on the tapped row until an answer
  arrives. An acknowledgement that carries a `pane_id` MUST take `R-31-18-13`. An acknowledgement
  that carries none MUST take the snackbar of `docs/32-design-language.md` section 7.22 with
  `haptic.commit`, exactly as `R-31-13-13` reports a `Disconnect`. No answer at all MUST take
  `R-31-18-15`. The snackbar MUST name the action that was sent, MUST NOT say the action finished,
  and MUST NOT read as though nothing happened: the acknowledgement of `R-11-217` proves the
  workstation accepted the invocation, and no field and no event reports completion. `R-30-743`
  owns how long the snackbar stays, and it keeps a result-bearing transient control on screen for a
  screen reader user, which is why this screen needs no announcement for it.
- **R-31-18-09** A stale row MUST fail visibly. When an invocation returns `plugin_disabled` of
  `R-11-218` or `action_unknown` of `R-11-219`, the screen MUST show the error strip of callout 16,
  MUST keep the raw code on screen, and MUST offer exactly one recovery, labelled
  `Refresh actions`. That control MUST read the action list again and MUST NOT invoke the action a
  second time, so it MUST NOT be labelled `Try again`: a control MUST NOT be named for an operation
  it does not perform. The `Error, list` state keeps `Try again`, because there the failed request
  and the recovery are one request. The screen MUST NOT drop the tap silently and MUST NOT retry on
  its own, because a second invocation of an unclassified action is a second unknown change to the
  workstation. The screen MUST NOT offer to switch the plugin back on: `R-30-968` and `R-11-204`
  both forbid it, and only the person at the computer can do it.
- **R-31-18-10** No row of a third-party plugin MUST carry `treat.destructive`, a status hue, a
  warning icon or a red fill. `R-30-967` removes the confirmation because the app cannot classify
  such an action, and a screen that cannot classify an action equally cannot paint one as dangerous.
  `R-32-527` and `R-32-126` hold the values this rule refuses. What stands in place of the paint is
  the author's own sentence, shown whole by `R-31-18-03`. This rule does not reach the `herdr-relay`
  plugin, whose rows `R-31-18-16` removes before anything is painted at all.
- **R-31-18-11** The app MUST NOT write a `title` or a `description` into a log, a crash report or
  an analytics event. Both are workstation text that a plugin author MAY have written with a
  directory in it, and `R-30-964` keeps a workstation path off the wire for the same reason.
- **R-31-18-12** No row MUST carry a scope word. `contexts` declares where an action MAY be shown,
  not what it acts on, and the measured set separates the two: `Smart Rename: current tab` declares
  no `tab` context at all, yet its title says it acts on a tab. A word taken from `contexts` would
  therefore print `No scope` beside a title that names one. The scope a person needs is the scope
  the screen is on, and `R-31-18-05` puts that in one sentence above the first group.
- **R-31-18-13** When the acknowledgement of `R-11-217` carries a `pane_id`, the screen MUST offer
  the route to that pane. It MUST do so on one strip under the app bar, tappable across its whole
  width like the offline strip of `R-32-561`, carrying the action title, the verb `opened` and the
  breadcrumb of the new pane, and routing to `/hosts/:hostId/panes/:paneId`. `R-30-520` owns whether
  the app offers that route or takes it; this rule owns what the screen draws either way. The strip
  MUST persist until the person takes it, invokes another action or leaves the screen, and MUST NOT
  time out: a route offer that vanishes is a route the person loses. It MUST NOT be dismissible, and
  so MUST carry no dismiss control. Those three exits are enough, and `R-32-561` keeps a dismissal
  off the whole-width tap, so a fourth exit would cost a second control in a thin band beside a
  breadcrumb that already elides. The verb `opened` is provable, because `R-11-217a` sends an id
  only when exactly one pane appeared that was not there before, so an id never names a pane that
  was merely focused. The strip MUST NOT be shown when the named pane is absent from the current
  tree snapshot, and MUST disappear the moment that pane leaves the snapshot, because a
  plugin-opened pane MAY close before the person taps. A tap that still wins the race MUST land on
  the `Empty, pane gone` state that `08-terminal.md` already owns, and this screen MUST NOT invent a
  second answer for it. The strip MUST carry no text action either. `R-32-561` permits one, so this
  is a choice about this strip: the second line is already the breadcrumb, and a text action would
  compete with it while reaching the same single destination the whole-width tap already reaches.
  The error strip of `R-31-18-09` is the other case that `R-32-561` separates, and it MUST keep its
  one text action.
- **R-31-18-14** An acknowledgement that carries no `pane_id` MUST NOT be treated as a failure and
  MUST NOT be reported as though nothing happened. `R-11-217a` sends no id when no pane appeared and
  also when several did, and `R-11-217b` sends none when a toggle closed its pane, so one answer
  covers three different truths and the phone cannot tell them apart. `Redeploy sidebar panes`
  closes sidebar panes in every workspace and returns exactly this answer. The screen therefore MUST
  NOT name a pane the Host did not name, MUST NOT print `Opened` or `Closed` as a row state, and
  MUST NOT add a verb of its own to a `title`. `Toggle source control` and `Toggle sidebar` create a
  pane on one tap and destroy it on the next, and this screen cannot know which in advance, so no
  label on it may promise one outcome.
- **R-31-18-15** One tap MUST NOT become two, and a spinner MUST NOT last forever. The screen MUST
  latch the invocation before the repaint and MUST disable every row, the tapped row included, until
  an answer arrives. On a timeout or a lost link it MUST enter the outcome-unknown state of
  `R-30-518`, MUST keep every row disabled, and MUST NOT offer a retry of the invocation. The one
  control MUST be `Refresh actions`, which reconciles by reading the action list and the tree
  snapshot again, because which panes exist is the only observable evidence of what a plugin action
  did. A one-tap retry is worse here than elsewhere: `Toggle source control` and `Toggle sidebar`
  close on a second tap what they opened on the first, so a retry does not repeat the outcome, it
  reverses it.
- **R-31-18-16** The app MUST remove every action whose `plugin_id` is `herdr-relay` before it draws
  the list, and MUST NOT count those rows in the line of `R-31-18-06`. The guard MUST match on that
  field, and MUST NOT match on a word in a `title` or in an `action_id`, because `R-31-16-33`
  records that the id `refresh` is the action that revokes every phone. This project writes that
  plugin's manifest in `docs/10-herdr-integration.md`, so the identity is known and this is not the
  classification `R-30-967` forbids. `R-31-16-33` marks `refresh` and `stop` destructive, and from
  a phone each is worse than that, because each closes the path its own answer would return on, so
  no phone can undo either. The other two are not destructive and are still unreachable: `pair`
  opens the pane that shows the QR code and the six-word phrase, so `R-31-18-13` would render a live
  pairing secret onto an already-paired phone, and `clients` writes to a Host log the phone cannot
  read while `14-devices.md` already lists every paired phone. No line MUST report the removal,
  because the person can do nothing about it, and `R-31-18-06` exists to report a shorter list
  honestly rather than to promise a way back.
- **R-31-18-17** Every row MUST expose the button role, and MUST NOT be static text. Its semantics
  MUST carry the whole label, which is the plugin id, the title and the whole `description`, and
  MUST carry the enabled state. A disabled row MUST report itself disabled and MUST NOT activate.
  Pending state MUST be announced separately and MUST NOT be spliced into the label. Without the
  role and the state, a screen reader announces a row a person can act on as text they cannot.

## Accessibility

- Touch target: every header and every row meet the minimum of `R-30-290` and `R-30-740`, at the
  heights `R-32-564` and `R-32-515` fix. The whole header row is the expander target, per
  `R-32-564`. The entry row is a sheet action row, and `10-pane-actions.md` owns its target. Two
  adjacent rows keep the separation `R-30-292` requires.
- Contrast: a title is `color.fg.primary` and a `description` is `color.fg.secondary`, both on
  `color.bg.base`, and both are passing rows in `R-32-150`, per `R-30-720`. The snackbar text is
  `color.fg.primary` on `color.bg.raised`, another passing row. `Refresh actions` is the text
  action of `R-32-526`, the platform's own label style in `color.accent.text` (amended 2026-09-09,
  per `R-03-104`: was `type.mono.button` UPPER), which `R-32-124` now
  permits on `color.bg.raised` at 8.18 in dark and 5.50 in light (amended 2026-09-08 by the
  product owner: an earlier text kept the older `R-32-526`, which barred accent ink from a
  strip). No row carries a status hue, because no row has a state.
- Screen reader: each row MUST be exactly one semantics node, with the button role, the whole label
  and the enabled state that `R-31-18-17` fixes, labelled as `R-32-505` requires. The visible
  `description` no longer clamps, per `R-31-18-03`, so speech and sight now carry the same text.
  The breadcrumb MUST be one node with commas for separators, per `R-32-574`. The scope sentence and
  the hidden-row line MUST both sit in the traversal order, so a person who cannot see the list
  still learns the context and the count. No row MUST announce `destructive`, because `R-30-967`
  records that a third-party action cannot be classified, and `R-31-18-16` removes the rows this
  project can classify.
- Announcements: `R-30-742` forbids the deprecated announcement call and orders the two
  replacements it permits, and this screen MUST take the first of them wherever it reaches. A
  header that toggles MUST carry the `expanded` state on its own node, so the state change itself
  speaks, per `R-30-742` and `R-32-568`. It MUST NOT be a one-shot announcement, because the node
  that changed is the node the person is already on. The pane strip of `R-31-18-13` MUST be one node
  with the button role and MUST take accessibility focus when it appears, which makes it a changed
  node the person reaches, so it needs no announcement either. Only the error strip of callout 16
  and the outcome-unknown strip of `R-31-18-15` MUST be announced, because both appear away from the
  focus and neither moves it, which is exactly the persistent-strip case `R-30-742` names. The
  snackbar MUST NOT be announced: `R-30-743` keeps it on screen for a screen reader user, and the
  traversal order reaches it there.
- Focus order: per `R-30-719`, the back control, the title, the pane strip or the error strip when
  one is drawn, the scope sentence, the breadcrumb, then each header and its rows in drawing order,
  then the hidden-row line. A strip takes the position it is drawn in, directly under the app bar.
  On back the focus returns to the terminal, where `R-32-546` already returned it to the overflow
  control that opened the sheet (amended 2026-09-09 per `R-03-055`).

## Retired rules

| Rule | Why |
| --- | --- |
| `Computer actions`, the `Agents` app bar control | **Retired control, not a rule id.** From 2026-09-04 to 2026-09-09 it was this screen's one entry, at `/hosts/:hostId/actions`, computer scoped. The product owner rejected it on 2026-09-09 per `R-03-055`: it could supply the computer alone, so every `tab` or `pane` action was hidden, and a plugin acts on a pane. `R-31-18-01` carries the entry, so no rule id dies. `06-agent-list.md` callout 2 holds the slot it left. |
| `/hosts/:hostId/actions` | **Retired route, not a rule id.** The computer-scoped route of the control above. `/hosts/:hostId/panes/:paneId/actions` is the only route since 2026-09-09; it existed once before, from 2026-09-03 to 2026-09-08, pushed from a terminal app bar control that the now-retired `R-31-08-24` replaced with `Shortcuts`, and that control left the bar on 2026-09-10 per `R-03-116`. |

## Open questions

- **`PluginActionInfo` carries no destructive flag.** Nothing in the record says whether an action
  changes the workstation, although `Sync scheduled jobs` and `Redeploy sidebar panes` clearly do.
  This is a gap in the Herdr socket API and not a decision this app can take for itself. The
  recommended default, which `R-30-967` and `R-31-18-10` fix today, is to classify no third-party
  action, to raise no dialog, and to show the author's own `description` whole instead, per
  `R-31-18-03`. The app MUST NOT infer risk from the title text. `R-11-220` records the same gap on
  the wire side. This gap does not reach the `herdr-relay` plugin, whose four actions
  `R-31-18-16` removes on identity rather than on a flag. Revisit when a field on
  `PluginActionInfo` marks an action: a marked action then takes the destructive confirmation dialog
  of `docs/32-design-language.md` section 7.17, which `R-30-005` already permits. Until then, ask
  the Herdr maintainers for the flag rather than guessing at it.
- **Closed. `R-32-561` now covers a strip that routes somewhere other than diagnostics.** It
  requires a strip that reports a result naming a destination to be tappable and to route there.
  `R-31-18-13` cites it for both the whole-width tap and the destination. Recorded because the
  first draft of this file justified the pane strip with a false reason, that `R-32-124` forbids a
  text action on a strip. `R-32-124` reaches only `color.accent.text`, and `R-32-526` gives a text
  action on a raised surface `type.body.strong` in `color.fg.primary`. The false reason would also
  have forbidden the `Refresh actions` control that `R-31-18-09` requires on this screen's own error
  strip.
- **Whether a `selection` action ever becomes reachable.** The recommended default is the one
  `R-31-18-07` fixes: keep it out of version one. A phone selection lives in the terminal view, and
  giving the Device any way to set `selected_text` would hand a phone a path to pull terminal
  content back out through an invocation, which `R-30-964` and `R-11-216` exist to prevent. Revisit
  only with a design where the terminal view itself offers the action, so that the selection and
  the invocation belong to one surface.

## Sources

- `docs/32-design-language.md` - the app bar `R-32-510` and its trailing-control ceiling `R-32-512`,
  the two-line list row of section 7.4 and `R-32-515`, the disabled treatment `R-32-502`, the icon
  map `R-32-401`, the size set `R-32-350`, the accent restriction `R-32-124`, the text-action ink
  for a raised surface `R-32-526`, the section header `R-32-563` to `R-32-570`, the breadcrumb of
  section 7.24 and `R-32-573` and `R-32-574`, the empty state `R-32-553`, the raw error block
  `R-32-555`, the skeleton `R-32-560`, the tappable strip `R-32-561`, the label pattern `R-32-505`,
  the destructive values `R-32-527` and `R-32-126`, the strip and the snackbar of section 7.22, the
  destructive confirmation dialog of section 7.17, and the contrast table `R-32-150`.
- `docs/30-ux-spec.md` - the three destinations `R-30-021`, the four required states `R-30-002`, the
  modal restriction `R-30-005`, the delayed spinner `R-30-004`, the loading frame `R-30-800`, the
  back behaviour `R-30-031`, the empty-state rules `R-30-801` and `R-30-802`, the raw error text
  `R-30-803`, the single retry `R-30-804`, the outcome-unknown state `R-30-518`, the pane-result
  navigation choice `R-30-520`, the offline rules `R-30-805` and `R-30-807`, the touch-target rules
  `R-30-290`, `R-30-292` and `R-30-740`, the icon-only label rule `R-30-717`, the contrast rule
  `R-30-720`, the traversal order `R-30-719`, the `host_in_use` banner `R-30-940` and `R-30-941`,
  the tappable offline indicator `R-30-806`, the connected-computer rule for a per-Host route
  `R-30-946`, the haptic table, the announcement rule `R-30-742`, the transient-timing rule
  `R-30-743`, and the Host action rules `R-30-963` to `R-30-968`.
- `docs/33-platform-chrome.md` - the back-control rule `R-33-070`, which owns the glyph, the
  localised label and the pop gesture and requires this route to supply its `title`.
- `docs/31-mockups/07-notifications.md` - the destination that replaced `Panes` on 2026-09-04, and
  the pane display name `R-31-07-08`.
- `docs/31-mockups/06-agent-list.md` - the `Agents` destination, whose app bar carried this
  screen's entry from 2026-09-04 to 2026-09-09 and carries no plugin control since `R-03-055`.
- `docs/31-mockups/10-pane-actions.md` - the `Plugin actions` row of callout 5a, this screen's one
  entry, and the nine-row ceiling `R-31-10-03`, which is the reason these actions are a screen and
  not more rows on that sheet.
- `docs/31-mockups/08-terminal.md` - the terminal this route is pushed over, which the pane
  strip of `R-31-18-13` routes to, its `Empty, pane gone` state, which owns a pane that closed under
  the route, and the retired `R-31-08-24`, which took the local `Shortcuts` control off that app
  bar on 2026-09-10.
- `docs/31-mockups/09-key-row.md` - the key row, the phone's own fixed key vocabulary, which
  `R-31-09-24` keeps local and separate from a plugin invocation.
- `docs/31-mockups/14-devices.md` - the screen that already lists every paired phone, which is why
  `R-31-18-16` loses nothing by removing the `List paired phones` row.
- `docs/31-mockups/16-host-popup.md` - `R-31-16-33`, which names the four `herdr-relay` actions,
  the title each one shows on the phone, and which two are destructive, and which records that the
  id `refresh` is the action that revokes every phone.
- `docs/31-mockups/13-connection.md` - the snackbar result precedent `R-31-13-13`, and the
  diagnostics screen the offline strip and the banner route to.
- `docs/03-product-decisions.md` - full terminal control for a paired phone, one active phone per
  computer, one connected computer at a time, `R-03-043`, and `R-03-055`, which puts the entry to
  this screen on the pane action sheet.
- `docs/10-herdr-integration.md` - the method list that holds `plugin.action.list` and
  `plugin.action.invoke`, and that holds no keybinding read and no configuration read; and the
  `herdr-relay` manifest, whose `[[actions]]` blocks declare `pair`, `clients`, `refresh` and
  `stop` with their `-windows` twins, which is the evidence `R-31-18-16` rests on.
- `docs/11-relay-protocol.md` - the `action_list_request` and `action_list` messages, the projection
  `R-11-209`, the Host platform filter `R-11-210`, the absent-`contexts` rule `R-11-211`, the
  invocation context `R-11-215` and `R-11-216`, the acknowledgement `R-11-217` with its optional
  `pane_id`, the pane attribution `R-11-217a` and its 200 ms settle window, the toggle rule
  `R-11-217b`, the errors `R-11-218` and `R-11-219`, the missing destructive flag `R-11-220`, the
  Device prohibition `R-11-204`, and the error `host_in_use`.
- The Herdr socket API schema, read at run time with `herdr api schema --json` - the fields of
  `PluginActionInfo`, which are `plugin_id`, `action_id`, `title`, `command`, `description`,
  `contexts` and `platforms`, and which include no destructive flag. It is never a committed file.
