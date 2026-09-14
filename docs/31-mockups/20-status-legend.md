# 20 - Status colours

| Field | Value |
| --- | --- |
| Route | `/settings/status-colours` |
| Surface | Device, Android and iOS |
| Spec | `docs/30-ux-spec.md` |

This screen is the legend for the state bar of `docs/32-design-language.md` section 7.29. Every
list row in the app carries one bar in a status hue, per `R-03-100`, and `R-32-130` makes three
pairs of states share one hue on purpose: `working` and `warning`, `blocked` and `error`, `idle`
and `ok`. A person cannot learn the code from the lists alone. On 2026-09-09 the product owner
said so: he saw blue and green bars and had no idea what was what. `R-03-106` decides that the app
carries this page. This file owns how the page meets the decision.

The page holds one lead line, one group per hue, and one row per state the bar can show. Every
value on it is a build constant, so the page needs no network and no connected computer.

## Wireframe

```text
+--------------------------------------+
| <  Status colours                    |
+--------------------------------------+
| Every state bar takes one of these   |
| colours. Working and Warning share   |
| one amber, Blocked and Error share   |
| one red, and Idle and Ok share one   |
| green. The word beside the bar tells |
| them apart.                          |
|                                      |
| AMBER                                |
|| Working                             |
||   An agent is doing something now.  |
|| Warning                             |
||   A link is stale, in use or still  |
||   connecting.                       |
|                                      |
| RED                                  |
|| Blocked                             |
||   An agent is waiting for a person. |
|| Error                               |
||   A connection is lost or a check   |
||   failed.                           |
|                                      |
| GREEN                                |
|| Idle                                |
||   An agent runs and waits for       |
||   nothing.                          |
|| Ok                                  |
||   The computer is connected and     |
||   healthy.                          |
| A paired computer or phone that is   |
| not connected shows Idle too.        |
|                                      |
| TEAL                                 |
|| Done                                |
||   Unseen background work finished.  |
|                                      |
| GREY                                 |
|| Unknown                             |
||   The app cannot tell, usually a    |
||   lost link.                        |
+--------------------------------------+
```

Every row carries the state bar of callout 4 at its leading edge, the doubled `|`, in the hue its
group is named for. The drawing wraps each meaning to fit this scale; on screen each meaning is one
line, per `R-31-20-02`. The drawing is platform-neutral, per callout 10.

## Callouts

1. The back control and the title `Status colours`. The app bar of `R-32-510`, title token
   `type.heading`, because this screen carries a back control. The drawn `<` is a placeholder for
   that control and not a glyph choice: `R-33-070` gives the back glyph, the back label and the
   back gesture to each platform's own navigation component, so this file names none of them.
2. The lead line. Token `type.caption` in `color.fg.secondary`, at the group header's text edge,
   `space.4` below the app bar. It is the one place the page says in words which states share a
   hue and how a person tells them apart, in the exact wording of `R-31-20-04`. The subtitles do
   not repeat it, because a platform tile holds one line under its title and a meaning plus a
   sharing clause does not fit one line.
3. `AMBER`, the first group header. The upper-case tier of `R-32-563`: `type.micro`, upper case,
   `color.fg.secondary`, height `size.header`, with the group gap of `R-30-231` above it. The word
   is the colour's own name, because this page answers the question "what does this colour mean",
   and a person who cannot tell amber from green by eye reads the name. The five names, in order,
   are `AMBER`, `RED`, `GREEN`, `TEAL` and `GREY`, per `R-31-20-03`. The owner called the teal bar
   "blue"; the header tells him what the app calls it.
4. The `Working` row. One platform row of `R-33-073`, information and not a control: the state bar
   of `R-32-592` flush to the row's leading edge in `color.status.working`, as tall as the row,
   painted over the fill so the text keeps the tile's own inset, the word `Working` as the title
   in the tile's own primary type, and one sentence as the subtitle in the tile's own secondary
   type. The bar is the real state bar, so it pulses with `motion.pulse` here exactly as it does
   in a list, and holds still at full opacity under reduce motion, per `R-30-403`. The row takes
   no tap, no chevron and no trailing control, and it never dims, per `R-32-502`: a row that was
   never tappable is not disabled.
5. The `Warning` row, drawn exactly like callout 4 in `color.status.warning`. It sits directly
   under `Working` because the two share one hue, per `R-32-130` and `R-31-20-03`. Its sentence
   names the three surfaces that draw it: the live bar of `docs/31-mockups/08-terminal.md` past
   its 60 seconds, the `in use` leg and the `connecting` leg of `docs/31-mockups/13-connection.md`.
6. `RED`: `Blocked`, then `Error`, drawn like callouts 3 to 5 in `color.status.blocked` and
   `color.status.error`. `Blocked` is the agent state of `R-30-400`; `Error` is the lost link of
   `13-connection.md` and the terminal live bar, and a check that failed on the diagnostics page,
   which is why its sentence says `a check failed`.
7. `GREEN`: `Idle`, then `Ok`, in `color.status.idle` and `color.status.ok`, then one caption line
   under the group at the header's text edge, `space.2` below the last row, in `type.caption`
   `color.fg.secondary`: `A paired computer or phone that is not connected shows Idle too.` The
   line exists because `R-32-705` gives a saved computer the `idle` bar and `14-devices.md` gives
   a phone that is not connected the same bar, and the `Idle` row alone would read as an agent's
   state. It is the only group caption on the page, per `R-31-20-04`.
8. `TEAL`: `Done` alone, in `color.status.done`. No other state draws this hue, so the group has
   one row and no caption.
9. `GREY`: `Unknown` alone, in `color.status.unknown`. Its sentence is the one `R-30-400` gives.
   A connection leg that is `checking` or `not connected` draws this bar too, and `The app cannot
   tell` covers both.
10. The list composition. Every group is a platform list and every row is one platform static
    tile, per `R-33-073`: the platform list section on iOS with the one separator between two
    rows, and the Material settings list on Android where every row but the last in its group
    draws the divider of `docs/32-design-language.md` section 7.4. The wireframe is
    platform-neutral and draws the row **content**, which `docs/32-design-language.md` owns. This
    file MUST NOT name the composing widget. On iOS the bar sits flush to the leading edge of the
    inset card, so the card's corner clips its first and last rows' bars, as it clips every other
    edge of the card.
11. Primary navigation. This screen is pushed from the `Settings` destination and keeps the bottom
    navigation on screen, per `R-30-045`. The two platforms diverge on what the bottom control does
    then, and `R-33-071` owns the divergence. The drawing omits it.
12. Ground (added 2026-09-09, per `R-03-107`; amended 2026-09-09, per `R-03-107` as amended).
    The body paints plain `color.bg.base` with no ground grid and no paper block, because this
    page has content. The lead sentence of callout 2 sits under a `space.4` gap, each hue group is
    the settings section of `R-33-073` under its `space.6` gap, and the caption of callout 7
    follows its group after `space.2`. The ground grid of `docs/32-design-language.md` `R-32-332`
    is for the hero screens and an empty state only.

## States

| State | Trigger | Screen shows |
| --- | --- | --- |
| Default | The route opened. | The wireframe. Every row reads at once, because every value is a build constant. `Working` pulses. |
| Reduce motion | The platform reduce-motion setting is on. | The wireframe, with the `Working` bar still at full opacity, per `R-30-403` and `R-30-730`. Nothing else changes. |
| Offline | The phone has no network. | Nothing changes. No strip appears, no row dims and no value is withheld, per `R-31-20-07`. |
| No computer saved | No computer was ever paired, or every one was forgotten. | Nothing changes. This screen reads no Host state. |
| Not connected | A computer is saved and none is connected, per `R-03-046`. | Nothing changes. No value on this screen comes from a computer. |
| Large text | The system text scale is above 1.3. | Every row grows with its text, per `R-30-703`, and the bar keeps the row's full height. Each meaning is written to fit one line at the 1.3 scale on the reference device, per `R-31-20-02`; above that scale the platform tile's own one-line subtitle truncates, a limit of the tile of `R-33-073` that every settings row shares. No target exists to shrink. |

## Navigation

- In: the `Status colours` row on `15-appearance.md`, under `Theme`. Two taps from any tab: the
  `Settings` destination, then the row, per `R-03-106`.
- Out, back: `/settings`, mockup `15-appearance.md`.
- No other route leaves this screen. No row on it is a control, per `R-31-20-06`, and no control
  on it leaves the app.

## Rules

- **R-31-20-01** This screen MUST list every state the state bar of `docs/32-design-language.md`
  section 7.29 can show, each exactly once, as one platform row: the bar at the row's leading edge
  in the state's hue, the state word as the title, and one sentence as the subtitle. Today those
  states are `working`, `warning`, `blocked`, `error`, `idle`, `ok`, `done` and `unknown`. It MUST
  NOT list a state the bar cannot show, and a state the bar gains MUST gain a row here in the same
  change, so the legend and the bar never disagree.
- **R-31-20-02** The title of a row MUST be the word the app writes beside that bar: the label of
  `R-30-400` for the five agent states, and `Ok`, `Warning` and `Error` for a connection leg and
  the live bar. The subtitle MUST be one plain sentence that says what the state means for an
  agent or a computer, and it MUST fit one line at the reference width up to the 1.3 text scale
  of `R-30-703`, because the platform tile of `R-33-073` does not wrap a subtitle and a truncated
  meaning explains nothing. The bar MUST be the state bar of `R-32-592` itself, so `working`
  pulses and every state draws the same rectangle; this screen MUST NOT draw a swatch of its own.
- **R-31-20-03** The rows MUST be grouped by hue, one group per hue, with the colour's name as the
  group header, in this order: `AMBER` (`working`, `warning`), `RED` (`blocked`, `error`), `GREEN`
  (`idle`, `ok`), `TEAL` (`done`), `GREY` (`unknown`). Two states that share a hue on purpose, per
  `R-32-130`, MUST sit next to each other in one group, the agent state first, so a person who
  looked at one colour finds every state it can mean in one place. The order MUST NOT change with
  data, because the page holds none.
- **R-31-20-04** The lead line MUST read, exactly: `Every state bar takes one of these colours.
  Working and Warning share one amber, Blocked and Error share one red, and Idle and Ok share one
  green. The word beside the bar tells them apart.` It is the one place the sharing is said in
  words, per `R-03-106`. The `GREEN` group MUST carry the one caption line of callout 7 under its
  rows, because `R-32-705` gives a saved computer the `idle` bar. No other group MAY carry a
  caption, and the page MUST NOT repeat the lead line's content under a group.
- **R-31-20-05** The page MUST paint plain `color.bg.base` behind its content, with no ground grid
  and no paper block, per callout 12 (amended 2026-09-09 by the product owner, per `R-03-107` as
  amended: for part of that day the page painted the grid of `R-32-332` with paper under the lead
  sentence and each hue group, until the owner saw the grid around solid list blocks and limited
  it to the hero screens and the empty states). It keeps the app bar of `R-32-510`, no brand mark
  and no eyebrow: the page is a list, not a hero screen, and it is never empty, so it takes no
  watermark of `R-32-554`. It MUST keep the bottom navigation, per `R-30-045`.
- **R-31-20-06** No row on this screen is a control. A row MUST take no tap, MUST carry no chevron
  and no trailing control, and MUST NOT dim, per `R-32-502`. Each row MUST be one semantics node
  whose label reads the word, then the meaning, per `R-32-505`: `Working, An agent is doing
  something now.` The bar MUST carry no node of its own, because the words carry the state, per
  `R-30-141`.
- **R-31-20-07** This screen MUST work with no network and no connected computer. Every value is a
  build constant. It MUST NOT show an offline strip, MUST NOT dim a row and MUST NOT gate a value
  on a connection. It MUST NOT show a hex value or a token name: the colour's plain name in the
  group header is the only name a person needs, and `docs/32-design-language.md` owns the values.
- **R-31-20-08** This screen explains the colours and MUST NOT change them. It MUST NOT offer a
  palette picker, a per-state override or any control, per `R-32-014` and `R-31-15-11`. The status
  hues follow the theme with the rest of the app, and the `Theme` control of `15-appearance.md` is
  the one control that affects them.

## Accessibility

- Touch target: the back control is the one interactive element on this screen, and it belongs to
  the platform's navigation component, which meets the minimum target of `R-30-290` and `R-30-740`
  itself. No row is a target and no row MUST be given a tap, per `R-31-20-06`. A large text scale
  has no target to shrink, per `R-30-741`.
- Contrast: every title uses the platform tile's primary ink and every subtitle, the lead line, the
  caption and the group headers use `color.fg.secondary`, on `color.bg.base` and on the iOS card's
  `color.bg.raised`. The chrome scheme is the fixed Herdr palette on both platforms, per
  `R-33-024`, so those pairs are passing rows in `R-32-150`, per `R-30-720` and `R-33-044`. Each
  bar is a non-text indicator whose hue clears the 3.0 to 1 floor of `R-30-130` on both surfaces,
  per `R-32-132`, and no state is carried by colour alone, per `R-30-141`: the word names the
  state, the group header names the colour, and the lead line names the pairs that share one.
- Screen reader: the back control belongs to the platform's navigation component, per `R-33-070`,
  and supplies its own label; the app MUST NOT set one, so `R-30-717` reaches no control here. Each
  row MUST be one semantics node reading the word then the meaning, per `R-31-20-06` and
  `R-32-505`. Each group header, the lead line and the `GREEN` caption are plain text nodes. The
  bar carries no node, per `R-31-20-06`. Nothing on this screen is a live region, because nothing
  on it changes while a person reads it.
- Focus order: per `R-30-719`: the back control, the title, the lead line, then each group in
  drawing order, header first, then its rows top to bottom, then its caption where one exists. The
  order ends at the `Unknown` row, because no control follows it.

## Open questions

None.

## Sources

- `docs/03-product-decisions.md` - the legend decision `R-03-106`, the state bar `R-03-100`, the
  one-mark rule `R-03-058` and the not-connected rule `R-03-046`, all of 2026-09-09 except the
  last.
- `docs/32-design-language.md` - the state bar of section 7.29 and `R-32-592`, the status tokens
  and their shared hues `R-32-130`, the indicator floor `R-32-132`, the ground grid `R-32-332`, the
  app bar `R-32-510`, the list row of section 7.4 and `R-32-515`, the disabled rule `R-32-502`,
  the semantics label pattern `R-32-505`, the upper-case header `R-32-563`, the computer row
  tokens `R-32-705`, the palette prohibition `R-32-014`, and the contrast table `R-32-150`.
- `docs/30-ux-spec.md` - the agent status table and `R-30-400` to `R-30-403`, the treatment rules
  `R-30-130` and `R-30-141`, the group gap `R-30-231`, the touch target `R-30-290`, the pushed
  route rule `R-30-045`, the large-text row rule `R-30-703`, the reduced-motion rule `R-30-730`,
  and the accessibility rules `R-30-717`, `R-30-719`, `R-30-720`, `R-30-740` and `R-30-741`.
- `docs/33-platform-chrome.md` - the fixed chrome scheme `R-33-024`, the measured-table contrast
  proof `R-33-044`, the back control `R-33-070`, the primary navigation on a pushed route
  `R-33-071`, and the settings list `R-33-073`.
- `docs/31-mockups/15-appearance.md` - the `Status colours` row that routes here, and the `Theme`
  control the hues follow (`R-31-15-11`).
- `docs/31-mockups/13-connection.md` - the `connected`, `connecting`, `in use` and `offline` legs
  whose bars the `Ok`, `Warning` and `Error` rows explain.
- `docs/31-mockups/08-terminal.md` - the live bar whose `ok`, `warning` and `error` states the
  same three rows explain.
- `docs/31-mockups/14-devices.md` - the phone row whose `idle` bar the `GREEN` caption names.
- `docs/31-mockups/05-host-list.md` - the computer rows whose `ok` and `idle` bars the `GREEN`
  group explains.
