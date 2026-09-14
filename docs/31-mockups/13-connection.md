# 13 - Connection status and diagnostics

| Field | Value |
| --- | --- |
| Route | `/hosts/:hostId/diagnostics` |
| Surface | Device, Android and iOS |
| Spec | `docs/30-ux-spec.md` |

This screen exists so a person can answer one question in one look: which half is broken. It is also
the troubleshooting page, so it carries the alert limitation of `R-30-512` and the insecure relay
warning of `R-30-923`.

## Wireframe

```text
+--------------------------------------+
| <  Connection                   copy |
+--------------------------------------+
| Phone to relay             connected |
|   https://relay.example.com          |
+--------------------------------------+
| Relay to computer          connected |
|   patrick-desk                       |
+--------------------------------------+
| STAGES                               |
| Reusing handle                    ok |
| Opening WebSocket                 ok |
| Registering handle                ok |
| Noise handshake                   ok |
| Host info                         ok |
+--------------------------------------+
| Phone to computer, round trip  49 ms |
+--------------------------------------+
| Herdr protocol                    21 |
| Herdr version               0.8.2-p2 |
| Chrome           fixed Herdr palette |
+--------------------------------------+
| RENDER                               |
| Grid from the computer        144x50 |
| Longest line drawn               141 |
| Unknown SGR codes                  0 |
+--------------------------------------+
| THIS SESSION, THIS COMPUTER          |
| Frames in                      1 284 |
| Frames out                        96 |
| Bytes in, on the wire         1.6 MB |
| Bytes in, unpacked            9.8 MB |
| Compression                     16 % |
+--------------------------------------+
| ALERTS                         READY |
| Alerts arrive while the app is       |
| running. If the phone closes the     |
| app, the alert is waiting in the     |
| app the next time you open it.       |
|                                      |
| Alerts come from the computer you    |
| are connected to. If an agent        |
| finishes on another computer, you    |
| see it when you connect to that      |
| computer.                            |
+--------------------------------------+
| LAST ERROR                  14:02:11 |
| websocket closed 1006                |
+--------------------------------------+
| DISCONNECT, FORGET, REMOVE AND THE   |
| SWITCH                               |
| Disconnect           NOT DESTRUCTIVE |
|   This screen. Closes this phone's   |
|   link to the relay, and keeps the   |
|   pairing and the Device key.        |
|                                      |
| Switching computer   NOT DESTRUCTIVE |
|   The host list, a plain tap on a    |
|   saved row. Disconnects the         |
|   connected computer, then connects  |
|   the tapped one, and keeps every    |
|   pairing and every Device key.      |
|                                      |
| Forget                   DESTRUCTIVE |
|   The host list, revealed by a left  |
|   swipe. Drops the paired computer   |
|   on this phone, and destroys the    |
|   Device key for it.                 |
|                                      |
| Remove                   DESTRUCTIVE |
|   The devices screen. Revokes this   |
|   phone on the computer.             |
+--------------------------------------+
|            Reconnect now             |
+--------------------------------------+
|              Disconnect              |
+--------------------------------------+
```

The same group while an attempt runs, and after one failed (added 2026-09-09, per `R-03-113`
item 3). The bar of each row is the state bar of `R-32-592`; the drawing shows its word only.

```text
+--------------------------------------+     +--------------------------------------+
| STAGES                               |     | STAGES                               |
| Reusing handle                    ok |     | Reusing handle                    ok |
| Opening WebSocket                 ok |     | Opening WebSocket                 ok |
| Registering handle                ok |     | Registering handle                ok |
| Noise handshake              working |     | Noise handshake                error |
| Host info                    pending |     |   the Noise handshake failed:        |
+--------------------------------------+     |   FormatException                    |
                                             | Host info                    pending |
                                             | Retrying in 5 s.                     |
                                             +--------------------------------------+
```

## Callouts

1. Back chevron, title `Connection`, and a `copy` action, all in the app bar of `R-32-510`. `copy`
   puts the whole screen on the clipboard as plain text. That action exists so a bug report costs
   one tap.
2. Leg one, `Phone to relay`. Each leg row carries the state bar of `R-32-592` as `R-03-100`
   leaves it (amended 2026-09-09 by the product owner: one state mark, the bar; the dot is
   retired), `border.attention` wide at the leg's leading edge and as tall as the leg, its label
   and every line under it, in the state's hue: `ok` for `connected` (amended 2026-09-08: the row
   borrowed the agent state `done`; a connected leg is a healthy link, not a finished task, and
   `ok` shares `color.status.ok` with the `treat.ok` word beside it), `warning` for `connecting`
   and `in use` (amended 2026-09-09: the dot borrowed `working`, and only work pulses; a warning
   leg holds still in `color.status.warning`), `error` for `offline`, and `unknown` for
   `checking`, `unknown` and `not connected`. The state word sits on the right in `type.micro`,
   upper case, `color.fg.secondary`, on the label's own baseline. The sub-line under the label and
   every explanatory line take `type.caption` in `color.fg.secondary` and start at the label's
   left edge, `space.2` after the bar, in the label's column (amended 2026-09-08 by the product
   owner: the row had grown a dot in place of the leading subject icon this callout named, and
   its sub-line sat 16 px left of the label it belonged to; one mark per leg keeps the two legs
   scannable, and the words carry the state).
3. The relay origin, exactly as stored. It is shown in full, per `R-30-922`, because it is the
   address a person's terminal traffic crosses. `/settings` owns changing it.
4. Leg two, `Relay to computer`, and the computer's name, drawn exactly like callout 2. The two
   legs are shown separately because knowing which half is broken is the whole value of this
   screen, and the state words are what carry that. The computer's name also heads the list, in
   `type.body.strong`, and scrolls with it (amended 2026-09-08 by the product owner: pinned
   above the list with no edge of its own, scrolled rows ran into it).
5. `Phone to computer, round trip`. The one latency on this screen, and it sits in its own band
   because it belongs to no single leg: it is the phone's own measurement of one correlated request
   against its reply, and that reply travels to the computer and back across both hops. Neither leg
   row carries a number, because the phone holds one WebSocket and nothing else, so it cannot time
   one hop by itself. See `R-31-13-19`.
6. `Herdr protocol` and `Herdr version`. They arrive on the wire in `host_info`, as
   `herdr_protocol` and `herdr_version`, which the Host itself read from `ping`. A mismatch against
   20 causes a whole class of failures, so it sits on screen and not in a log.
7. `Chrome`, reading `fixed Herdr palette`, always. `R-33-045` requires this screen to show
   observably that the fixed Herdr palette is in use on both platforms; there is one palette now,
   per `docs/33-platform-chrome.md` section 4, so this row is a constant fact, never a live value,
   and it replaces the old wallpaper/dynamic-colour `COLOUR` group entirely (see `## Retired
   rules`).
8. `Grid from the computer`. The exact grid size, columns first. Both numbers arrive on the wire in
   `pane_frame`, as `width` and `viewport_rows`, and in `watch_ack` before the first frame. The
   Host reads them from `pane.layout` `rect.width` and from `scroll.viewport_rows`, both measured
   in character cells. See `R-10-024`.
9. `Longest line drawn`. The longest rendered line in the last read. It is the lower bound on the
   column count. The gap against `rect.width` is normally 2 to 4 cells, because the Host pads each
   row with styled spaces out to its own width. A large gap means the read is being trimmed
   somewhere.
10. `Unknown SGR codes`. The count of SGR parameters outside the measured vocabulary `0`, `1`, `2`,
    `3`, `4`, `38;2`, `48;2`, `38;5`, `48;5`. The expected value is 0. This is the single best early
    warning that Herdr changed upstream, and it belongs on screen rather than in a log, because a
    silent rendering break is the failure this app can least afford. See `R-02-018`.
11. Counters for this session. Frames and bytes both ways, all counted on the phone. A session is
    this phone's one link to this one computer, so the header names both scopes. See `R-31-13-06`.
12. `Bytes in, on the wire` against `Bytes in, unpacked`, and the ratio. Measured ANSI compresses to
    13 to 24 percent, so a healthy ratio sits near 16 percent. A ratio near 100 percent means
    compression is off, which is a real defect. See `R-02-016`.
13. `ALERTS` group. The header carries the effective delivery state in one word, per `R-31-13-22`,
    and the body carries the exact wording of `R-30-512` and the exact wording of `R-30-517`. A
    person who came here because a phone stayed silent gets all three answers: the product does not
    promise an alert while the app is closed, an alert follows the connected computer, and this
    phone either will or will not draw one now. The two sentences are two paragraphs in
    `type.caption` with `space.3` between them, per `R-31-13-23`. The product owner decided this on
    2026-09-03: one dense block did not read on a phone.
14. Last error, with a wall clock time and the raw text in `type.mono.code`. The raw text is either
    the close code the phone's own socket reported, or the `message` field of an `error` frame. It
    is shown as it arrived, never as a friendly rewrite, because this screen exists for debugging.
15. `Reconnect now`. It tears down the link and rebuilds it. The filled button of `R-32-525`. It
    resets the reconnect schedule that `docs/22-platform-integration.md` owns in `R-22-028`. It
    rebuilds this same connection and never reaches another computer, per `R-31-13-20`. While the
    last attempt failed at a stage of callout 18 it reads `Try again` and makes one attempt
    (amended 2026-09-09, per `R-03-113` item 3: the `host_in_use` row of the states table already
    did this, and a failed stage is the general case).
16. `Disconnect`. It closes this phone's link to the relay and keeps the pairing and the Device
    key, per `R-30-960`. It is the text action of `R-32-526` on `color.bg.base`, and it sits under
    `Reconnect now`, so the safe rebuild action reads first. It is not destructive, so it raises no
    dialog and acts on the tap. The result is reported by the snackbar of
    `docs/32-design-language.md` section 7.22. After it, no computer is connected, so `/hosts`
    shows every saved row in its not-connected state, per `R-30-961`.
17. Ground (added 2026-09-09, per `R-03-107`; amended 2026-09-09, per `R-03-107` as amended). The
    body paints plain `color.bg.base` with no ground grid and no paper block, because this screen
    has content. The diagnostics list keeps its `space.4` inset and ends at `Disconnect`; the
    ground grid of `docs/32-design-language.md` `R-32-332` is for the hero screens and an empty
    state only.
18. `STAGES` (added 2026-09-09, per `R-03-113` items 3 and 7). One row per step the app awaits
    while it connects, in the order the app runs them, each drawn exactly like a leg row of
    callout 2: the state bar at the leading edge, the stage name in `type.body`, the state word
    trailing it in `type.micro` upper case. The five steps are `Reusing handle`, `Opening
    WebSocket`, `Registering handle`, `Noise handshake` and `Host info`. `Reusing handle` is the
    cheap reconnect of `R-03-113` item 7: the attempt takes the relay origin, the routing handle
    and the pinned Host key from the pairing record, so no rediscovery, no new pairing and no
    built-in origin (`R-03-030`, `R-03-031`); every attempt this screen can show is a reconnect,
    because a first pairing runs on `02-pair-scan.md` and `03-pair-code.md`. A step that
    completed reads `ok`; the step in flight reads `working` and its bar pulses; a step the attempt
    has not reached reads `pending`; the step the attempt stopped at reads `error` and carries the
    raw error text under its name in `type.mono.code`, never rewritten, per `R-30-803` and
    `R-31-13-02`. When the relay refuses the handle, that text is the relay's own sentence of
    `docs/11-relay-protocol.md` `R-11-117` to `R-11-120`, and the failed step is `Registering
    handle`. While the app waits out one delay of `R-22-028`, one `type.caption` line closes the
    group, `Retrying in 5 s.`: a fact about now, which `R-31-13-11` permits. The one retry of
    `R-30-804` is `Reconnect now` reading `Try again`, per callout 15; the group draws no second
    control. The group is absent when there is nothing to describe: before the first state
    arrives, after a deliberate `Disconnect`, and in the `Saved, not connected` state. Nothing in
    the group ever shows the handle, the key or the phrase, per `R-31-13-05`. The resume that
    follows a connect, `tree_request` and `watch_pane` of `R-11-084`, is not a row: the app does
    not wait for it, so it has no end to report.

## Disconnect, Forget, Remove and the switch

Four neighbouring acts, and a reader will confuse them. `R-30-962` names this screen as the one
place that holds the distinction, so every other screen cites this table. The switch belongs here
because it disconnects as well, and a person who meets it on `/hosts` must not read it as a fourth
destructive word.

| Action | Where it lives | What it does | Destructive |
| --- | --- | --- | --- |
| `Disconnect` | this screen | closes this phone's link to the relay, and keeps the pairing and the Device key | no |
| Switching computer | `05-host-list.md`, a plain tap on a saved row | disconnects the connected computer, then connects the tapped one, and keeps every pairing and every Device key | no |
| `Forget` | `05-host-list.md`, revealed by a left swipe | drops the paired computer on this phone, and destroys the Device key for it | yes |
| `Remove` | `14-devices.md` | revokes this phone on the computer | yes |

`Disconnect` and the switch each cost one tap to undo, so neither raises a confirmation. `R-03-044`
states that for the switch. Each of the other two destroys a key or an authorisation, so
`R-31-05-02` and `R-31-14-01` require a confirmation for them. After a `Disconnect` the computer
stays in the list on `/hosts`, and the person does not pair it again. After a switch both computers
stay in that list, and only which one is connected changes.

The table above is the content. The screen does not draw it as a grid: four columns do not fit a
phone. It draws one two-line row per action under the upper-case header `DISCONNECT, FORGET,
REMOVE AND THE SWITCH`, as the wireframe shows, per `R-31-13-23`. The product owner decided this on
2026-09-03, after a live review found the earlier drawing overcrowded: the action word alone on
the title line in `type.body`, the `Destructive` column as the trailing tag `DESTRUCTIVE` or `NOT
DESTRUCTIVE` in `type.micro` and `color.fg.secondary` on that same line, and the `Where it lives`
and `What it does` columns as one `type.caption` line under it, in that order. The header is
`type.micro` and MAY wrap.

## States

| State | Trigger | Screen shows |
| --- | --- | --- |
| Default, healthy | Both legs are connected. | The wireframe above, with no error group when nothing has failed. Every `STAGES` row reads `ok`, because the connected link ran every step (added 2026-09-09, per `R-03-113` item 3). |
| Loading | The screen opened and the first correlated reply has not returned. | Both state words read `checking` in `color.fg.secondary` and the round trip shows `-`. Every counter shows its real value at once, because all of them are local. The `STAGES` group is absent until the first state arrives. |
| Connecting, staged | An attempt is running (added 2026-09-09, per `R-03-113` item 3). | Both legs read `checking`. Every `STAGES` row before the step in flight reads `ok`, that step reads `working` with the pulsing bar, and every later step reads `pending`. `Reusing handle` is always the first row and reads `ok` at once, because the origin, the handle and the key are already on the phone (`R-03-113` item 7). |
| Error, stage failed | The attempt stopped at a step other than `Registering handle` (added 2026-09-09, per `R-03-113` item 3). | That row reads `error` with the `error` bar and the raw text under its name in `type.mono.code`; the rows before it keep `ok` and the rows after it read `pending`. A failure at `Opening WebSocket` is the `Error, leg one down` row. A failure at `Noise handshake` or `Host info` reads leg one `connected` and leg two `unknown`: the Host answered, and the stage row already says what went wrong. `Reconnect now` reads `Try again` and makes one attempt. While the app waits out a delay of `R-22-028`, the group ends with `Retrying in 5 s.` and the failed row stays, because that failure is why the app waits; the next attempt clears it. |
| Error, leg one down | The Device cannot reach the relay: the attempt failed at `Opening WebSocket`, or the link dropped mid-session. | Leg one reads `offline` with the `error` bar. Leg two reads `unknown`, because the Device cannot see past a broken first leg. That honesty matters more than a guess. A mid-session drop shows no `STAGES` group until the next attempt starts, because no step was running when the socket closed. |
| Error, leg two down | The relay answered `handle_unknown` (`R-11-117`): the relay is reachable and no Host is registered (amended 2026-09-09, per `R-03-113` item 3: the failed stage now says which half broke). | Leg one reads `connected`. Leg two reads `offline` and gains one line, `The Relay pane may be closed on patrick-desk.` That single sentence is the most common real cause. The `Registering handle` row reads `error` with the relay's own sentence under it. `Reconnect now` reads `Try again`; the app also keeps retrying on the schedule of `R-22-028`, because the Host re-registers the same handle on its own ladder (`R-11-125`). |
| Error, host in use | The relay answered `host_in_use` with close code `4006`. | Leg one reads `connected`. Leg two reads `in use` with the `warning` bar and gains two lines: `Another phone is using patrick-desk.` and `One phone at a time. Disconnect there, or remove that phone in the Relay pane.` The `Registering handle` row reads `error` with the relay's own sentence under it. `Reconnect now` becomes `Try again` and makes one attempt, per `R-30-942`. |
| Error, protocol mismatch | `ping` returned a protocol other than 21. | The protocol row takes `treat.error` and reads `21 expected, 22 found`, plus one line, `Update Herdr on the computer, or update this app.` |
| Error, unknown SGR seen | The count in callout 9 rose above 0. | That row takes `treat.error` and gains one line, `Rendering may be wrong. Send this with Copy.` The count stays exact and MUST NOT be rounded or capped. |
| Warning, relay not encrypted | The stored origin is a permitted cleartext origin. | A strip above leg one carries the exact words of `R-30-923` with `treat.warning`. It is not dismissible, per the same rule. |
| Saved, not connected | The caller named a computer this app has saved with no live connection. `R-30-946` permits it, and `R-31-05-18` routes here from both the `Switch failed` strip and the `Offline` strip. | Both legs read `not connected` in `color.fg.secondary` and take no treatment, because nothing failed: this is the state a deliberate `Disconnect` or a failed switch leaves, and `R-03-043` makes it normal. The round trip, all three `RENDER` rows and every counter read `-`, per `R-31-13-06`. The `STAGES` group is absent. `Reconnect now` stays the filled action and rebuilds the computer `:hostId` names, per `R-31-13-20`. `Disconnect` is absent, per `R-31-13-13`: there is no link to close, and this screen is already the outcome a disconnect produces. |
| Alerts silenced or off | The alert delivery state that `R-31-12-13` reads is not `ready`. | The `ALERTS` header reads `silenced` when the system is granted and quiet, and `off` when the permission is refused. The group gains one line, `Fix this in Alerts.`, which routes to `/settings/notifications`, per `R-31-13-22`. Both limitation sentences stay, because both still apply. |
| Offline | The phone has no network at all. | A strip at the top: `This phone has no network.` with `treat.error`. Both legs read `offline`. `Reconnect now` stays enabled, so a retry works the moment the network returns. |
| Disconnecting | `Disconnect` was tapped and the link is closing. | `Disconnect` shows the in-place spinner of `R-32-350` in place of its label, and `Reconnect now` is disabled. Every counter freezes at its last value. |
| Disconnected | The link closed on request. | The app routes to `/hosts` and a snackbar reads `Disconnected. This computer stays paired.` No computer is connected now, so every row on `/hosts` shows the not-connected glyph of `R-32-705`. |
| Error, disconnect failed | The close did not complete. | The route does not change and the link stays open. A strip under the app bar reads `Could not disconnect. The link is still open.` with `treat.error`, the raw text in `type.mono.code` per `R-30-803`, and one `Try again` per `R-30-804`. The screen MUST NOT show `/hosts` as if the disconnect succeeded. |
| Disconnect while offline | `Disconnect` was tapped and there is no route to the relay. | There is no socket to close, so the app stops the reconnect attempts, routes to `/hosts`, and the snackbar reads `Stopped trying. This computer stays paired.` |

## Navigation

- In: `Connection` on `15-appearance.md`, the `Why` action of the `host_in_use` banner that
  `R-30-941` defines, or any offline indicator elsewhere in the app, all of which route here.
  `:hostId` is the computer the caller names. It is usually the connected one, and `R-30-946` also
  permits a saved computer with no live connection, which is the case every failure route uses.
- Out, back: the caller.
- Out, `copy`: no route change. A snackbar confirms `Copied.`
- Out, `Disconnect`: `/hosts`, mockup `05-host-list.md`, per `R-30-961`. A snackbar carries the
  result, and the computer stays in the list.
- The bottom navigation stays on this route. `R-30-022` names the terminal as the one screen that
  hides it. This file draws no bar because the three destination mockups own that drawing.

## Rules

- **R-31-13-01** The screen MUST show the two legs separately. A single combined status hides which
  half failed and makes the screen useless.
- **R-31-13-02** The error text MUST be shown raw. The app MUST NOT replace it with a friendly
  sentence, and MAY add a friendly sentence under it.
- **R-31-13-03** Every offline indicator elsewhere in the app MUST route here on a tap.
- **R-31-13-04** The protocol number MUST be checked against 21 on every connect, and a mismatch
  MUST be surfaced here and on `08-terminal.md`. See `R-02-008`.
- **R-31-13-05** `copy` MUST produce plain text with no colour codes and no emoji, so it pastes
  cleanly into an issue. It MUST include the relay origin and MUST NOT include the routing handle, a
  phrase, a key or a key fingerprint.
- **R-31-13-06** The counters MUST be per session and MUST reset on a reconnect, and the screen MUST
  say so with the header `THIS SESSION, THIS COMPUTER`. A session is this phone's one link to one
  computer, per `R-03-043`, so a switch to another computer MUST reset every counter too. A counter
  MUST NOT carry a value measured against a different computer. A computer with no session MUST
  show `-` on every counter and MUST NOT show 0, because 0 claims a measurement that never ran.
- **R-31-13-07** The grid size MUST be shown exactly, with no tilde. See `R-31-08-04`.
- **R-31-13-08** The unknown SGR count MUST default to 0 and MUST be exact. The app MUST NOT hide
  the row when the count is 0, because the value 0 is the reassurance.
- **R-31-13-09** The `RENDER` group MUST report the pane read last. It MUST NOT aggregate across
  panes, because a column count belongs to one pane.
- **R-31-13-10** The `Longest line drawn` row MUST take `treat.warning` when the gap against `Grid
  from the computer` passes 8 cells. The measured gap is 2 to 4 cells because the Host pads each row
  with styled spaces, so 8 is double the widest measured normal gap. Below 8 the row MUST stay
  plain, because a warning that fires on healthy output trains a person to ignore it.
- **R-31-13-11** This screen MUST NOT restate the reconnect schedule. It cites `R-22-028`, per
  `R-30-809`. It MAY show the current attempt number, which is a fact about now, not a schedule.
- **R-31-13-12** This screen MUST carry the `ALERTS` group with the exact wording of `R-30-512` and
  the exact wording of `R-30-517`. A silent phone is the most common reason a person opens
  diagnostics, and the next most common cause is an agent that finished on a computer this phone is
  not connected to.
- **R-31-13-13** `Disconnect` MUST be the text action of `R-32-526`, placed under `Reconnect now`,
  and MUST report its result with the snackbar of `docs/32-design-language.md` section 7.22 in the
  exact words the states table gives. It MUST NOT be a filled button. Exactly one filled control
  sits on this screen and `Reconnect now` is it, per `R-32-525`. `Disconnect` MUST be absent when
  there is no link to close, because a control that can do nothing is worse than no control, and
  this screen is then already the outcome the control produces.
- **R-31-13-14** The app MUST NOT reconnect on its own after a deliberate disconnect. The schedule
  `R-22-028` MUST NOT run, and the link MUST return only when the person asks for it. A schedule
  that undoes a deliberate act is a defect.
- **R-31-13-15** A disconnect that fails MUST leave the link open and MUST keep the route. The app
  MUST NOT route to `/hosts` on a failed disconnect. A person who then reads a connected row cannot
  tell what happened.
- **R-31-13-16** `Disconnect` MUST stay enabled while the phone is offline, and MUST stop the
  reconnect attempts. No socket is open, so stopping the retrying is the act the person asked for.
- **R-31-13-17** `Disconnect` MUST stay enabled in the `host_in_use` state, and MUST close only this
  phone's own link. The screen MUST NOT suggest that it frees the slot on the computer, per
  `R-30-941`.
- **R-31-13-18** This screen MUST hold the one `Disconnect`, `Forget` and `Remove` distinction
  table, and MUST name the screen that owns each of the other two actions. `R-30-962` points every
  other screen here, so a second table anywhere else is a defect. The table MUST also carry the
  switch of `R-03-044`, because a switch disconnects and a reader will otherwise take it for a
  fourth destructive word.
- **R-31-13-19** This screen MUST show exactly one latency, on its own row, labelled `Phone to
  computer, round trip`. It MUST be the phone's own measurement of one correlated request against
  its reply, paired by the `corr` field of `R-11-031`. That reply travels to the computer and back,
  so the number crosses both legs, and the row MUST NOT sit inside either leg group: a whole-path
  number under a leg heading reads as that leg's own. A leg row MUST carry its state word and no
  number. Before the first reply of a session the row MUST read `-`. The app MUST NOT open a second
  network surface to obtain a per-leg number: it holds exactly one WebSocket, per `R-20-009` and
  `R-22-025`, and `R-11-024` forbids it from sending its own WebSocket ping. A connection handshake
  MUST NOT be drawn as a hop latency, because it is several round trips and is not comparable to a
  round trip on an established socket.
- **R-31-13-20** `Reconnect now` MUST rebuild the connection named by `:hostId` and MUST NOT reach
  a different computer. Switching computer is a separate act, and the table above holds it. This
  screen is reachable whenever that computer is saved, per the named exception in `R-30-946`. A
  broken link is the reason the screen exists, so requiring a live connection would make it
  unreachable at its whole purpose.
- **R-31-13-22** The `ALERTS` header MUST carry the effective delivery state as one word: `ready`,
  `silenced` or `off`. The two limitation sentences state what the product does not promise, and
  they cannot tell a person that this phone is refusing to draw an alert, which is the other reason
  a phone stays silent. The word MUST come from the same reading that `R-31-12-13` requires, and
  this screen MUST NOT restate the recovery: `silenced` and `off` route to
  `/settings/notifications`, which owns both states and their `Open Settings` action.
- **R-31-13-23** The `ALERTS` body and the distinction table MUST read on a phone. Decided
  2026-09-03 by the product owner, after a live review found both overcrowded.
  1. The `ALERTS` body MUST be two paragraphs in `type.caption`, one sentence group each, with
     `space.3` between them. The wording stays exactly `R-30-512` and `R-30-517`.
  2. The distinction table MUST be drawn as one two-line row per action, never as a grid: the
     action word alone in `type.body` on the title line, the tag `DESTRUCTIVE` or `NOT
     DESTRUCTIVE` trailing it in `type.micro` and `color.fg.secondary` on the same line, and where
     the action lives then what it does in one `type.caption` line under it.
  3. The tag MUST stay on the title line and MUST NOT wrap into the title. The title takes the
     width the tag leaves, so a long action word wraps and the tag does not.
  4. Rows MUST sit `space.4` apart. The gap is between rows, so the last row carries none, per
     `R-30-231`.
- **R-31-13-24** The screen MUST show the staged progress of `R-03-113` item 3 as the `STAGES`
  group of callout 18, and the app MUST reconnect the way `R-03-113` item 7 requires. Decided
  2026-09-09 by the product owner, from the `deex2/herdroid` comparison.
  1. The rows MUST be the steps the app awaits, in the order it runs them, one row per step, and
     nothing else: `Reusing handle`, `Opening WebSocket`, `Registering handle`, `Noise handshake`,
     `Host info`. A step the app does not wait for MUST NOT be a row.
  2. Every reconnect MUST start with `Reusing handle`: the relay origin, the routing handle and
     the pinned Host key come from the pairing record on this phone, per `R-03-030` and
     `R-03-031`. The app MUST NOT rediscover a relay, MUST NOT start a new pairing on its own and
     MUST NOT carry a built-in origin. When the relay refuses the handle, the app MUST follow the
     path that already exists: `handle_unknown` stays on the schedule of `R-22-028`, because
     `R-11-125` has the Host re-register the same handle; `handle_taken`, `pairing_expired` and
     `host_in_use` stop it, and the person pairs again or frees the slot.
  3. Each row MUST take the leg anatomy of callout 2 and one of four words: `ok` for a completed
     step with the `ok` bar, `working` for the step in flight with the pulsing `working` bar,
     `pending` for a step not yet reached with the `unknown` bar, and `error` for the step the
     attempt stopped at with the `error` bar. The failed row MUST carry the raw error text under
     its name in `type.mono.code`, per `R-30-803` and `R-31-13-02`. A relay refusal MUST show the
     relay's own sentence, per `R-11-092`.
  4. The retry MUST be exactly one control, per `R-30-804`: `Reconnect now` reads `Try again`
     while the last attempt failed at a stage, and the group MUST NOT draw a second control.
  5. The wait before the next attempt MAY be named as one line, `Retrying in 5 s.`, per
     `R-31-13-11`. The failed row MUST stay through the wait and MUST clear when the next attempt
     starts, so a stale error never sits beside a `working` bar.
  6. Each row MUST be one semantics node that reads the step, the word, then the raw text, so
     `Noise handshake, error, the Noise handshake failed: FormatException`.
  7. No row, no log line and no `copy` text MUST carry the handle, the key or the phrase, per
     `R-31-13-05`; a log line names the stage and the attempt count only.

## Accessibility

- Touch target: the back chevron, `copy`, `Reconnect now` and `Disconnect` meet the minimum target
  of `R-30-290` and `R-30-740`. `Disconnect` is the text action height `R-32-526` fixes, which is
  itself a target.
- Contrast: every value uses `color.fg.primary` and every label `color.fg.secondary`, on
  `color.bg.base`, both passing rows in `R-32-150`, per `R-30-720`. A leg's state lives in the
  hue of its bar and in the state word beside it, per `R-30-140` and `R-30-141`, so `connected`
  and `offline` never differ by colour alone (amended 2026-09-08 by the product owner, with
  callout 2, and 2026-09-09 per `R-03-100`). A value row that fails still takes a treatment, which
  carries an icon as well as a colour.
- Screen reader: `copy` MUST carry the label `Copy this page`, per `R-30-717`. Every row MUST be one
  semantics node whose label reads the label then the value, for example `Relay to computer,
  connected` and `Phone to computer, round trip, 49 milliseconds`. The `LAST ERROR` block MUST be
  read only and MUST NOT be a live region, per the same reasoning as `R-30-712`. A state change on
  either leg MUST announce one sentence through `SemanticsService.announce`, and a disconnect MUST
  announce its snackbar sentence the same way, because the route changes under the person.
  `Disconnect` MUST NOT announce `destructive`, because it destroys nothing. Each distinction row
  of `R-31-13-23` MUST be one semantics node that reads the action, then `destructive` or `not
  destructive`, then its caption, so `Forget, destructive, The host list, revealed by a left
  swipe. ...`. That word is spoken as a fact about the action a row describes, not about a control,
  because the row is not a control. Each `STAGES` row is one node that reads the step, the word,
  then the raw text, per `R-31-13-24` (added 2026-09-09).
- Focus order: per `R-30-719`, back chevron, title, `copy`, then each group in drawing order, then
  `Reconnect now`, then `Disconnect`.

## Open questions

None.

## Retired rules

These rows retire wireframe **rows**, not rule ids. The table records why each row was removed.

| Row | Disposition |
| --- | --- |
| `Reads skipped, no change` | Retired. The revision gate runs on the Host, which sends no `pane_frame` at all for a revision that did not move. No message tells the Device how many reads were skipped, so the phone cannot count them. The gate itself stands, per `R-02-012` and `R-10-035`. |
| `Predictions confirmed`, `Mispredictions` | Retired by `R-03-130`. `R-21-043` item 8 added these counters. The native composer removes the prediction engine and both counters. |

This row retires one rule id. The id stays reserved, so an old citation still resolves.

| Rule | Disposition |
| --- | --- |
| `R-31-13-21` | Retired. `docs/33-platform-chrome.md` section 4 fixes one chrome palette on both platforms: `dynamic_color` is removed, no wallpaper scheme exists, and `ChromeScheme.fixed(Brightness)` builds the one `ColorScheme` from the tokens `docs/32-design-language.md` section 6 fixes. The `COLOUR` group this rule required — `Chrome scheme`, `Where it came from`, `Contrast level`, `Pairs below the floor` — has nothing left to report: every phone reads the same fixed palette, so the group and its wireframe rows are deleted, not merely emptied. |

## Sources

- `docs/32-design-language.md` - the app bar `R-32-510`, the filled button `R-32-525`, the text
  action `R-32-526`, the raw error block `R-32-555`, the size set `R-32-350`, the snackbar of
  section 7.22, and the contrast table `R-32-150`.
- `docs/30-ux-spec.md` - the alert limitations `R-30-512` and `R-30-517`, the insecure origin strip
  `R-30-923`, the relay address visibility rule `R-30-922`, the one reconnect schedule rule
  `R-30-809`, the `host_in_use` banner actions `R-30-941`, the per-Host routing rule `R-30-946` and
  its named exception for this screen, the bottom navigation rule `R-30-022`, and the disconnect
  rules `R-30-960` to `R-30-962`.
- `docs/02-herdr-probe-results.md` - measured socket behaviour, event payloads, payload sizes, and
  the SGR vocabulary in `R-02-018`.
- `docs/10-herdr-integration.md` section 4.10 and `R-10-024` - `pane.layout` rects are measured in
  character cells.
- `docs/12-relay-hosting.md` - the relay endpoints and the health endpoint.
- `docs/11-relay-protocol.md` - `host_info`, `pane_frame`, `watch_ack`, the `error` frame, the
  `corr` field that pairs a request with its reply, the keepalive rule `R-11-024`, the transport,
  the `disconnect` message of section 4, the handle registration window `R-11-125`, the error
  `host_in_use`, the close code `4006`, the four relay refusals and their exact sentences
  `R-11-117` to `R-11-120`, the raw-error rule `R-11-092`, and the resume of `R-11-084`.
- `docs/31-mockups/05-host-list.md` - the `Forget` action and its Device key, `R-31-05-02`, and the
  two strips that route here for a saved computer with no live connection, `R-31-05-18`.
- `docs/31-mockups/14-devices.md` - the `Remove` action and its confirmation, `R-31-14-01`.
- `docs/22-platform-integration.md` - `R-22-028`, the one reconnect schedule.
- `docs/03-product-decisions.md` - one active computer per phone, `R-03-043` and `R-03-044`; no
  built-in relay origin, `R-03-030` and `R-03-031`; the ground of a screen with content,
  `R-03-107`; the staged progress and the cheap reconnect, `R-03-113` items 3 and 7.
- `docs/33-platform-chrome.md` - the observability requirement `R-33-045`, the fixed iOS palette
  `R-33-007`, and the fixed Android palette of section 4, `R-33-023` to `R-33-025`.
- `docs/31-mockups/12-notifications.md` - the effective alert delivery state `R-31-12-13`, and the
  screen that owns both the silenced state and its recovery.
