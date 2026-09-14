# 12 - Notification settings

| Field | Value |
| --- | --- |
| Route | `/settings/notifications` |
| Surface | Device, Android and iOS |
| Spec | `docs/30-ux-spec.md` |

Every alert on this screen is a **local** notification. The app builds it on the phone from an
`agent_status` message that arrived over the encrypted link, and it posts it with the platform's own
notification API. There is no push service and no notification server anywhere in this product.
`docs/22-platform-integration.md` owns the platform call and `docs/11-relay-protocol.md` owns the
message.

## Wireframe

```text
+--------------------------------------+
| <  Alerts                            |
+--------------------------------------+
| Alerts arrive while the app is       |
| running. If the phone closes the     |
| app, the alert is waiting in the     |
| app the next time you open it.       |
| Alerts come from the computer you    |
| are connected to. If an agent        |
| finishes on another computer, you    |
| see it when you connect to that      |
| computer.                            |
+--------------------------------------+
| WHEN TO ALERT ME                     |
| An agent is blocked            [on ] |
| An agent is done               [on ] |
+--------------------------------------+
| WHICH AGENTS                         |
| Only agents I have opened      [off] |
|   Every agent on this computer       |
+--------------------------------------+
| QUIET HOURS                          |
| Hold alerts                    [off] |
| From 22:00 to 07:30                > |
+--------------------------------------+
| Send a test alert                    |
+--------------------------------------+
| An alert carries the agent kind,     |
| the tab name and the pane name. It   |
| never carries pane text.             |
+--------------------------------------+
```

## Callouts

1. Back chevron and title `Alerts`. The app bar of `R-32-510`, title token `type.heading`. The title
   says `Alerts`, not `Push`, because nothing here is pushed.
2. The limitation block. Token `type.caption` in `color.fg.secondary`. It holds two limits as two
   paragraphs with `space.3` between them, one semantics passage: the exact wording of `R-30-512`,
   then the exact wording of `R-30-517` (amended 2026-09-08 by the product owner: the same two
   sentences read as two paragraphs on `13-connection.md` per `R-31-13-23`, and one dense block
   did not read on a phone there either). The first limit is about time and the second is about
   place. Both sit at the top because both change what every switch below means.
3. Group header. Token `type.micro`, upper case, `color.fg.secondary`, row height `size.header`.
4. Toggle row. The switch row of `R-32-522`. Every switch shows a visible on and off label in the
   wireframe, because a bare switch renders identically in a monospace mock.
5. `An agent is blocked`. Default on. This is the one that matters: the agent waits for a person.
6. `An agent is done`. Default on. Unseen background work finished.
7. `Only agents I have opened`. One switch, default off. On, it limits alerts to agents whose pane
   this Device has opened at least once, so a shared computer does not flood one phone. Off, every
   agent on that computer earns one. The label names one computer because `R-30-517` limits every
   alert to the connected one. The row is the switch row of `R-32-522` at `size.row.two_line`, and
   its secondary line in `type.caption` names the value in force: `Every agent on this computer`
   while the switch is off, and `Only agents you have opened` while it is on. One control carries
   one Boolean, per `R-31-12-12`, and that line keeps the second label on screen.
8. Quiet hours. `Hold alerts` defaults off. The window is 22:00 to 07:30 in the phone's own time
   zone, and a tap on the time row opens the platform's own time pickers. The operating system
   draws them, so this repository owns no wireframe for them. The time row stays usable while the
   hold is off, so a person can set the window before they turn the hold on.
9. `Send a test alert`. It posts a real local notification at once through the real path, so a
   person can prove the chain works. This row is the fastest way to debug a silent phone. It
   reports the outcome on the row, per `R-31-12-14`, because on this screen a drawn banner is not
   the proof: the app itself is in the foreground.
10. Privacy footnote. Token `type.caption` in `color.fg.secondary`. It names the three fields a
    person can read on a lock screen, which `R-30-510` fixes.
11. Ground (added 2026-09-09, per `R-03-107`; amended 2026-09-09, per `R-03-107` as amended).
    The body paints plain `color.bg.base` with no ground grid and no paper block, because this
    screen has content. The limitation passage of callout 2, the recovery block of the
    permission-denied and silenced states, the three groups, the `Send a test alert` row and the
    privacy footnote of callout 10 sit directly on that ground, with their `space.4` and `space.6`
    gaps between them. The error strip stays an opaque `color.bg.raised` strip. The
    `opacity.disabled` dim of the `Permission denied` and `Alerts silenced by the system` states
    covers each block. The ground grid of `docs/32-design-language.md` `R-32-332` is for the hero
    screens and an empty state only.

## States

| State | Trigger | Screen shows |
| --- | --- | --- |
| Default | The notification permission is granted, and the system will draw an alert. | The wireframe above. |
| Loading | The screen is reading the saved settings, or writing one. | The row being written shows the switch at `opacity.disabled` for the round trip. No full screen spinner, because a settings screen must never blank. |
| Empty | No alert has ever been posted on this phone. | The limitation block stays, so both limits stay on screen, and it gains one line, `No alerts yet. The app posts one when an agent needs you, on the computer you are connected to.` Every switch stays usable. This is the notification empty state that `R-30-512` and `R-30-517` both name. |
| Permission denied | The person refused at first run, or turned alerts off in the operating system. | A block under the limitation text reads `Alerts are off for this app.` and carries one action, `Open Settings`, which opens the operating system's own settings for this app. Every row below dims to `opacity.disabled`, because no preference can take effect. The app MUST NOT ask again, per `R-30-509`, so this row and the silenced row below it are the only two recoveries this screen offers. |
| Alerts silenced by the system | The platform permission is granted and the system still shows nothing. On Android the channel `herdr_agent_status` sits at importance `IMPORTANCE_NONE`. On iOS the app is authorised and its alert setting is off. | A block under the limitation text reads `Alerts are on for this app. This phone is not showing them.` with `treat.warning`, and carries one action, `Open Settings`, which reaches that channel on Android and this app's notification settings on iOS. Every row below stays usable, which is the difference from `Permission denied`: each preference applies again the moment the system stops silencing them. `R-31-12-13` owns the detection. |
| Error | The platform refused to post the test alert. | A strip: `This phone would not show the alert.` with `treat.error`, the raw platform error in `type.mono.code`, plus `Try again`. One line under it repeats the limitation of `R-30-512`, because a closed app is the most common reason a person reaches this screen. The limitation block stays at the top, so `R-30-517` is stated here too. The switches stay usable. |
| Offline | No route to the relay. | Every switch stays usable, because the preferences are local. `Send a test alert` stays enabled too, because a local notification needs no network. |

## Navigation

- In: `Alerts` on `15-appearance.md`.
- Out, quiet hours row: the platform's own time pickers, in place. The operating system draws them,
  so this repository owns no wireframe for them.
- Out, back: `/settings`.
- The bottom navigation stays on this route. `R-30-022` names the terminal as the one screen that
  hides it. This file draws no bar because the three destination mockups own that drawing.

## Rules

- **R-31-12-01** An alert MUST show the agent kind, the tab title and the pane title, and nothing
  else a person can read. `R-30-510` fixes that field set. It MUST NOT carry pane text, not even
  one line, and MUST NOT name a workspace: `agent_status` carries `workspace_id` and no workspace
  title, so no workspace name exists to show. Pane text is the thing a person did not agree to put
  on a lock screen.
- **R-31-12-02** `An agent is blocked` and `An agent is done` MUST default to on. Those two states
  are the reason the app exists.
- **R-31-12-03** Quiet hours MUST hold an alert, not drop it. The held alert MUST arrive at the end
  of the quiet window, collapsed into one summary when several are held. A hold that outlives the
  app process is lost, and this screen MUST NOT promise otherwise.
- **R-31-12-04** An alert MUST carry the `host_id` and the `pane_id` from `agent_status`, so a tap
  routes to the exact pane through `/lock`, per `R-30-511`.
- **R-31-12-05** The app MUST NOT alert for `idle`, `working` or `unknown`. Only `blocked` and
  `done` earn an alert, per `R-30-502`. Those five are every agent state there is, so this screen
  MUST NOT offer a category outside the two that earn one.
- **R-31-12-06** The app MUST collapse repeated alerts for one agent into one entry. A flapping
  agent MUST NOT produce a queue of alerts. The entry's identity is the pair `host_id` and
  `pane_id`, and its notification id MUST be a stable function of that pair, the same after a
  relaunch, because a pane identifier such as `w3:p2` is one computer's name and two computers may
  share it (decided 2026-09-08, from review). A newer `blocked` or `done` for the same pane MUST
  post under that same id, so the platform replaces the delivered alert in place and never shows a
  second one for that pane, while the log of `docs/31-mockups/07-notifications.md` keeps every
  change as its own row. Two panes MUST post under two ids. A tap on the replaced alert MUST route
  to the exact pane of `R-31-12-04`, and, when that pane has closed, to the
  `That pane has closed.` state of `docs/31-mockups/07-notifications.md` `R-31-07-07` (amended
  2026-09-09 by the product owner, per `docs/03-product-decisions.md` `R-03-113` item 5: one
  coalesced alert per agent that routes to the exact Host, tab and pane). When a person removes the
  row of `docs/31-mockups/07-notifications.md` for that pane (`R-31-07-04`), the app MUST cancel
  the delivered alert with that id and MUST drop any quiet-hours hold for the same pane, so a
  removed change never surfaces later. A repeat of a change the person already read or removed
  MUST NOT post again; only a change with a different status or a later `at` does.
- **R-31-12-07** This screen MUST carry the limitation of `R-30-512` and the limitation of
  `R-30-517` in one block at the top, each in its exact wording, and MUST keep that block on screen
  in the empty state and in the error state. It MUST NOT use the word `push`, name a push service,
  or offer a setting that implies background delivery.
- **R-31-12-08** `Send a test alert` MUST use the same code path as a real alert. A separate test
  path proves nothing.
- **R-31-12-09** The app MUST NOT post a system notification for an event that arrived while its
  process was stopped. Those events appear as unseen attention in the app instead, per `R-30-513`.
- **R-31-12-10** Every alert category MUST default to on and every suppression MUST default to off,
  so a person who changes nothing receives every alert. The app asks for the platform permission
  once, at first run, per `R-30-509`.
- **R-31-12-11** This screen MUST NOT offer a master alert switch, an app-level enable step, or any
  control that claims to re-enable a refused permission. The switches on this screen are opt-outs
  only. The single recovery from a refusal is `Open Settings`, which opens the operating system's
  own settings for this app.
- **R-31-12-12** No row on this screen MAY offer an alert from a computer the app is not connected
  to. `R-30-517` limits every alert to the connected computer, so an audience label MUST NOT say
  `every computer`. The audience MUST be one control, because it is one Boolean with two opposing
  values, and two switches would permit an off-off state that means nothing. Apple fixes a toggle
  as the control for a pair of opposing states, and the Android settings pattern requires a switch
  for a setting with a Boolean status and forbids a radio button there. The value not in force MUST
  stay visible on the secondary line, so one control loses no information.
- **R-31-12-13** This screen MUST read the effective delivery state, and MUST NOT read the app
  authorisation alone. A granted permission is not proof that a person will see an alert: Android
  permits a channel at importance `IMPORTANCE_NONE` while `POST_NOTIFICATIONS` stays granted, and
  iOS permits an authorised app whose alert setting is off. Either case MUST show the silenced
  state of the table above, and MUST NOT show the default state. A screen that reports every switch
  as on while the phone draws nothing sends a person to look for a broken agent. The detection is
  the disabled-channel and silenced-alert rule of `docs/22-platform-integration.md`, and this
  screen MUST NOT restate it.
- **R-31-12-14** `Send a test alert` MUST report its outcome on the row itself, and silence MUST
  NOT be the only result. iOS hands a notification raised while its own app is in the foreground to
  the app, and draws nothing unless the delegate asks for a banner, so on this screen an undrawn
  banner proves nothing about the chain. The row MUST state that the alert was posted, and MUST
  name the silenced state of the table above when the system will not draw it.

## Accessibility

- Touch target: the back chevron, every toggle row, the quiet hours row and `Send a test alert` meet
  the minimum target of `R-30-290` and `R-30-740`, at the row height `R-32-522` fixes.
- Contrast: a row label is `color.fg.primary` on `color.bg.base` and a group header is
  `color.fg.secondary`, both passing rows in `R-32-150`, per `R-30-720`. A switch in the off state
  uses `color.bg.high` as a track and MUST carry the boundary that `R-32-522` requires, because the
  fill alone cannot be seen. A disabled row at `opacity.disabled` carries no unique information,
  which `R-30-120` requires.
- Screen reader: each switch MUST expose its state as `on` or `off`, never as a bare `switch`. The
  audience switch MUST read its label, its state and its secondary line as one node, so a person
  hears which agents alert without moving focus. The limitation block MUST be one semantics node,
  so a screen reader reads both limits as one passage and never stops between them. `Send a test
  alert` MUST carry the label `Send a test alert`, per `R-30-717`.
- Focus order: per `R-30-719`, back chevron, title, the limitation block, then each group header
  with its rows top to bottom, then `Send a test alert`, then the privacy footnote.

## Open questions

None.

## Retired rules

These rows retire a screen **state** and an alert **category**, not a rule id. No rule ever carried
either one, so a reader who finds an old reference is looking for something that can no longer
happen.

| Subject | Disposition |
| --- | --- |
| The `Permission not asked` state | Retired. The app asks for the platform alert permission once, at first run, per `R-30-509` and `R-31-01-04`. After first run the app has always asked, so this state cannot exist. `Permission denied` is now the only refusal state. |
| The `An agent stopped early` category | Retired. `R-30-502` owns the five agent states, and only `blocked` and `done` earn an alert. Early stop was a sixth category built on `pane.exited`, which is not an agent state, so no switch on this screen can carry it. |

## Sources

- `docs/32-design-language.md` - the app bar `R-32-510`, the switch row `R-32-522`, the two-line row
  height `size.row.two_line`, the opacity tokens `R-32-331`, and the contrast table `R-32-150`.
- `docs/30-ux-spec.md` - the local notification rules `R-30-500` to `R-30-517`.
- `docs/22-platform-integration.md` - the platform call that posts a local notification, the
  background behaviour that limits it, and the disabled-channel and silenced-alert detection that
  `R-31-12-13` cites.
- `docs/11-relay-protocol.md` - the `agent_status` message and its fields.
- `docs/10-herdr-integration.md` - `pane.agent_status_changed`.
- `https://developer.apple.com/design/human-interface-guidelines/toggles` - a toggle is the control
  for a pair of opposing states, which is why the audience is one switch.
- `https://developer.android.com/design/ui/mobile/guides/patterns/settings` - the settings patterns:
  a switch for a Boolean status, no radio button there, and a secondary line that reflects the value
  in force.
- `https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate` -
  `userNotificationCenter(_:willPresent:withCompletionHandler:)` receives a notification that
  arrives while the app is in the foreground, and the system draws nothing when the delegate asks
  for nothing.
