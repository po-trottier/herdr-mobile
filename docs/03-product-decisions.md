# Product Decisions

This document is the single source for user-set product policy. Every decision here comes from the
product owner. Every other document defers to these rules. When a design document and this document
disagree on a product-level question, this document wins.

Rules are numbered `R-03-<nnn>`. Other documents cite them by id. This document owns no other prefix,
and no other document defines an `R-03` rule.

## 1. Public and vendor neutral

**R-03-001**: The product MUST be a public Android and iOS app. It MUST carry no NVIDIA branding, no
NVIDIA default endpoint and no NVIDIA certificate pin. The app is distributed through the public Apple
App Store and Google Play. The store metadata, app name, screenshots, description and privacy policy
are specified in `docs/23-public-release.md`.

**R-03-002**: Any NVIDIA deployment work MUST stay in
`docs/15-nvidia-brev-relay-experiment.md`. That document is an internal deployment experiment. It is
NOT a product dependency. The app, the protocol and the public deployment profile MUST function
without it.

**R-03-003**: No document MAY state or imply that the product is an NVIDIA product, an NVIDIA service
or an NVIDIA-endorsed tool. The product is vendor neutral.

## 2. Display name and identifiers

**R-03-010**: The public display name of the app MUST be `Herdr Remote`.

**R-03-011**: The repository name MUST stay `herdr-mobile`.

**R-03-012**: The bundle identifier on iOS and the application id on Android MUST be
`dev.herdr.remote`.

**R-03-013**: The custom URI scheme MUST be `herdr-remote`. Every link that the app registers,
including the pairing URI, MUST use this scheme. No other scheme MAY be registered.

## 3. Licence

**R-03-020**: The project licence MUST be Apache License 2.0. The canonical text lives in the root
`LICENSE` file.

**R-03-021**: The abbreviation `MIT` MUST appear in this repository only as the licence of a
third-party package in a dependency table. It MUST NOT appear as the project licence.

**R-03-022**: No document MAY state or imply that this project is MIT licensed.

## 4. No default relay origin

**R-03-030**: The app MUST ship with no compiled default relay origin. First run has no relay.

**R-03-031**: Pairing MUST supply the relay origin, **per computer**. The origin is an HTTPS
origin, not a WebSocket URL and not a full endpoint. The app stores it as scheme, host and optional
port, with no path, query or fragment, **beside that computer's pinned key and routing handle**
(`docs/13-security-pairing.md` R-13-048 already required this: "The Device stores the Host's static
public key, the relay origin, and the routing handle"). The origin handling rules are owned by
`docs/22-platform-integration.md`.

**R-03-126**: There is no one global relay origin. Amended 2026-09-11 by the product owner: "there's
no reason the relay address cannot be changed when connecting to a new server. Why would I have to
go in the settings when I wanna create a new connection? Why do all connections need the same
relay?" Two computers MAY sit behind two different relays, and pairing a second computer MUST NOT
require a visit to Settings and MUST NOT disturb the first computer's origin. Therefore:

- The relay address on the pairing screens MUST be editable in place, on the screen, as part of
  pairing. A QR scan or a deep link fills it from the URI's `r` field; manual entry types it. The
  field MUST NOT be read-only and MUST NOT send a person to Settings.
- The stored origin belongs to the paired-computer record, not to the app. Forgetting a computer
  takes its origin with it.
- Settings keeps no single global origin to replace. A saved computer's own origin MAY be edited
  from that computer's row or its diagnostics screen, and that edit affects only that computer,
  under the same destructive confirmation R-03-032 describes.

**R-03-032**: Changing a **saved computer's** relay origin MUST require an explicit destructive
confirmation. It MUST close that computer's connection if it is the live one, clear that computer's
stored routing handle and pinned Host key, and require pairing again against the new relay. It MUST
leave every other computer untouched (R-03-126). The confirmation flow is owned by
`docs/30-ux-spec.md`.

**R-03-127**: A screen that carries a form is a content screen, so it MUST paint plain
`color.bg.base` with no ground grid. Decided 2026-09-11 by the product owner, who saw the grid
behind the manual-pairing fields and called it "inconsistent ugly background": a grid line running
under a row of input boxes reads as a rendering fault, which is the same objection that produced
`R-03-107` step two. `R-03-107` named manual pairing a hero screen when it held a sentence and a QR
hint; it now holds an address field, a code field, six word fields and two actions, so it is a form.
The grid stays on `/welcome`, `/lock`, the QR scanner (whose body is a camera preview, not a form)
and `/about`, and on every list empty state. `docs/32-design-language.md` `R-32-332` and
`R-03-107` are amended to match.

**R-03-128**: A screen whose primary action sits at the end of a scrolling body MUST pin that
action, and any action beside it, to the bottom of the screen. Decided 2026-09-11 by the product
owner for the pairing screens: "Try again/connect and Scan QR Code should be sticky at the bottom.
They should not scroll." The pinned block sits on `color.bg.base`, carries the screen edge inset,
respects the safe area and the keyboard inset, and the scrolling body above it ends with enough
padding that its last field can clear the block. A person MUST never scroll to reach the action
that finishes the task.

**R-03-129**: The terminal screen's title MUST be the **tab title** alone. Decided 2026-09-11 by
the product owner: "for the terminal page title, I don't care about 'Pane W' to be there, just the
tab title". The tab is the task a person named (the same reasoning as `R-03-124`); the pane name is
a Herdr identifier that carries no information when the tab holds one pane a person would watch,
which on the measured Host was every agent tab (each one an agent pane beside a sidebar pane). The
pane name MAY follow the tab title, after ` / `, only when the tab holds **two or more agent
panes**, because then it is the only thing that tells them apart; the pane switcher of `R-31-08-25`
still lists every pane by name. A pane with no tab title (a pane whose tab was never titled) shows
the pane name alone, as before. `docs/31-mockups/08-terminal.md` callout 2 owns the drawing.

**R-03-033**: `http://` origins MUST be permitted only for `localhost`, `127.0.0.0/8`, `::1` and the
RFC 1918 private ranges, and MUST show a persistent insecure-development warning. Every other
cleartext origin MUST be rejected. The validation rules are owned by
`docs/22-platform-integration.md`.

## 5. One active phone per Host

**R-03-040**: The relay MUST accept at most one Device connection per Host handle. A second Device that
presents an already active Host handle MUST receive the `host_in_use` protocol error and close code
`4006`, both defined in `docs/11-relay-protocol.md`. The first Device MUST stay connected and MUST
receive nothing.

**R-03-041**: This is a product decision, not a technical limit. One active phone keeps the mental
model, the notification target and the watched-pane state unambiguous. A person has one phone. Two
live phones watching the same pane would fight over input focus and notification delivery.

**R-03-042**: Paired identities MUST stay listed on the Host and MUST stay revocable. A Device that
is
paired but not currently active is not affected by the one-active-Device rule. The paired-device list
and revocation rules are owned by `docs/13-security-pairing.md`.

## 6. One active computer per phone

Section 5 limits how many phones one computer serves. This section limits how many computers one
phone holds. The two rules are mirrors: each side of the relay enforces a one-active-connection
limit, and the reasons are the same.

**R-03-043**: The app MUST save every paired computer, and MUST keep at most one of them connected at
a time. The saved list is how a person chooses. The one-socket rules are `R-22-025` and `R-20-009`.

**R-03-044**: Changing the connected computer MUST disconnect the current one first, then connect to
the chosen one. The app MUST NOT hold two Host connections, even for a moment. A switch is an
ordinary disconnect, per `R-30-960`, so it keeps every pairing and every Device key, and it MUST NOT
raise a confirmation.

**R-03-045**: A local notification MUST arrive only from the connected computer. The app MUST state
that limit in plain words in the same places where it states the app-is-running limit of
`R-03-063`.

**R-03-046**: A saved computer that is not connected MUST NOT show a live agent count or a live
status. It MUST show its last-seen state with the time it was seen. Remembered attention from an
earlier connection MAY stay on the row, and MUST read as last seen rather than as now.

**R-03-047**: A phone MAY set its own device name. No phone may rename another phone. The wire
carries the name in `device_info`, per `R-11-131`. No rename message crosses the relay, and none
will be added.

## 7. Full terminal control

**R-03-050**: A paired phone MUST have full control over every pane action the Herdr socket API exposes
to the plugin. This includes pane split, zoom, close, rename, resize, text input and agent prompt. The
action message set is owned by `docs/11-relay-protocol.md`.

**R-03-051**: Version 1 MUST NOT offer a read-only pairing mode, a read-only grant UI or a per-action
Host approval flow. Every paired phone receives full control.

**R-03-052**: A destructive action on the phone MUST use the phone-side confirmation that
`docs/30-ux-spec.md` owns. The Host MUST NOT show a second confirmation for the same action.

**R-03-053**: The phone is already gated by pairing and biometric authentication. Adding a second
approval surface on the workstation would defeat the purpose of leaving the desk. The user is the same
person on both devices.

**R-03-054**: The terminal MUST be a live terminal. Text a person types while the terminal is on
screen MUST go to the pane as it is typed, one `send_input` per keystroke or per burst of
keystrokes that arrive together, and the pane's own echo MUST be the only authoritative echo
(amended 2026-09-11 per `R-03-123`: a predictive local echo MAY draw the expected effect in front
of it until the pane's frames confirm or remove it; until then this rule read "the only echo"). The
app MUST NOT hold typed text in a field, a draft or a pending line, and MUST NOT ask for a send. A
tap on the grid raises the keyboard and sends nothing. Decided 2026-09-09 by the product owner,
after the composed field of `docs/31-mockups/09-key-row.md` put typing in a box beside the session
instead of in it. `docs/31-mockups/09-key-row.md` and `docs/31-mockups/08-terminal.md` own the key
row and the grid; `docs/11-relay-protocol.md` owns the message.

**R-03-055**: Plugin actions MUST be reachable from the terminal, scoped to the pane on screen. The
Agents screen MUST NOT carry a plugin-actions control. Decided 2026-09-09 by the product owner: a
plugin acts on a pane, so the person reaches it where the pane is. `docs/31-mockups/18-actions.md`
and `docs/31-mockups/10-pane-actions.md` own the entry point and the list.

**R-03-056**: Every list the app shows MUST update live while it is on screen: a new event, a
changed status, a changed age. A value that is true only at the moment the screen opened is a
defect. Decided 2026-09-09 by the product owner. Each owning mockup states how its list updates.

**R-03-057**: The Workspace axis MUST make the parent of every row legible at a glance: which
workspace, which tab, which pane. The three tiers MUST differ in background, in type and in text
edge, and a tab group MUST be separated from the next. Decided 2026-09-09 by the product owner,
after two rounds that changed spacing alone. `docs/31-mockups/06-agent-list.md` owns the anatomy;
`docs/32-design-language.md` owns every value.

**R-03-058**: A screen MUST NOT show one fact twice. One row carries one mark per fact: the
unread state is one mark, the status is one mark, and two marks of the same colour stacked on one
edge are a defect. Decided 2026-09-09 by the product owner, who pointed at a notification row that
drew an unread bar and a status dot in the same teal on the same edge beside the word `Done`.
`docs/32-design-language.md` owns the marks; each mockup names which fact each mark carries.

**R-03-059**: Every button MUST be the platform's own button widget: on Android a Material
button (`FilledButton`, `FilledButton.tonal`, `OutlinedButton`, `TextButton`, `IconButton` and
its filled and outlined forms, `SegmentedButton`), on iOS a Cupertino button (`CupertinoButton`
in its plain, tinted and filled forms, `CupertinoSlidingSegmentedControl`). The app MUST NOT draw
a button of its own from a box, a border and a gesture, and MUST NOT imitate a platform button
with a custom pressed state. The design tokens of `docs/32-design-language.md` reach a button
through the platform theme only. Decided 2026-09-09 by the product owner, who pointed at the
drawn `-` and `+` squares of the terminal text size stepper as fake buttons, and the same day at
the drawn key caps of the terminal key row (`esc`, `tab`, `ctrl`, the arrows, `...`): a key cap
is a button and takes the platform widget too; the row has no exemption.
`docs/33-platform-chrome.md` owns the control map; `docs/32-design-language.md` owns the values.
A platform button MUST keep the platform's own shape, size and layout: the theme MAY set its
colours and its type and MUST NOT reshape it into a square, a fixed box or any geometry the
platform does not draw for that button. Added 2026-09-09 by the product owner, who pointed at
the `-` and `+` stepper a second time after it had become a re-shaped `IconButton`: a square
tonal icon button is still not what the platform draws.

**R-03-100**: Every state indicator in the app MUST be the leading bar, a rectangle in the state's
hue at the row's leading edge, beside the state word. The app MUST NOT draw a status dot anywhere:
not on an agent row, a computer row, a notification row, a connection leg, the terminal status
strip or an app bar. The bar carries the state; the word beside it names the state; an unread or
selected row is carried by weight and wash, never by a second bar. Decided 2026-09-09 by the
product owner: one shape for one meaning across the app; the bar is more compact, more obvious
and cleaner than a dot. This supersedes the bar-for-unread split of `R-03-058`, which stays in
force for its principle: one mark per fact. `docs/32-design-language.md` owns the bar's values;
each mockup names the states its rows show.

**R-03-101**: The pane action sheet MUST hold the plugin actions of `R-03-055`, `Split right`,
`Split down` and `Close pane`, plus the screen-reader `Read the last 20 lines` row where a screen
reader is on (amended 2026-09-14 per `R-03-134`: the two split rows returned, because a shell
beside the agent on screen is a real phone use; until then this rule kept split out as a desktop
layout task). It MUST NOT offer a prompt composer, because the live terminal of `R-03-054` is the
prompt: a person types to the agent in the pane. It MUST NOT offer zoom or rename, which are
desktop layout tasks with no use on a phone. It MUST NOT offer `Copy the whole screen`: the copy
path is
text selection in the grid, which `docs/21-terminal-rendering.md` and
`docs/31-mockups/08-terminal.md` own and which MUST work by long press. Decided 2026-09-09 by the
product owner. `R-03-050` still states that the phone has full control of every pane action the
API exposes; this rule decides which of them the sheet shows. `docs/31-mockups/10-pane-actions.md`
owns the sheet; `docs/31-mockups/11-prompt-composer.md` is retired.

**R-03-102**: Search MUST use the platform's own search pattern, and a switch between sibling
views MUST use the platform's own view switcher. On Android, search is a search action in the top
app bar that opens the Material 3 search view (`SearchAnchor`), and a view switch is a `TabBar` of
primary tabs; on iOS, search is a `CupertinoSearchTextField` in the navigation bar area, and a
view switch is a `CupertinoSlidingSegmentedControl`. A search field MUST NOT sit as a loose pill
in the body of a list. Decided 2026-09-09 by the product owner, who pointed at the search pill of
the Agents screen under its segmented control and asked whether that is the native pattern; it is
not. `docs/33-platform-chrome.md` owns the control map; the owning mockup names the placement.

**R-03-103**: A key or a key combination named in interface text MUST be drawn as a key, not as
a word: an inline key cap in `type.mono.key` on its own small raised box, so `r`, `d`, `Enter`
and `ctrl+c` read as keys at a glance in a sentence such as "the `r` key in the Relay pane". The
app MUST NOT print a key name as plain prose. Decided 2026-09-09 by the product owner, who
pointed at "the r key" printed as a word. `docs/32-design-language.md` owns the inline key's
values; every mockup that names a key in a sentence uses it.

**R-03-104**: A button label MUST take the platform's own label style and case: sentence case in
the interface font, as `TextButton`, `FilledButton`, `OutlinedButton` and `CupertinoButton` draw
it by default. The app MUST NOT upper-case a button label and MUST NOT set a mono face on it. Two
buttons side by side MUST share one label ink, and a destructive button differs from its sibling
by its glyph hue alone, per `R-32-527`. A key cap of the terminal key row is a key, not a button
label in this sense: it keeps `type.mono.key`, per `R-03-103` and `docs/32-design-language.md`
section 7.12. Decided 2026-09-09 by the product owner, who pointed at the Notifications strip:
`MARK ALL READ` in accent mono capitals beside `REMOVE ALL` in white mono capitals with a red
glyph, which read as inconsistent and not native. `docs/32-design-language.md` owns the values.

**R-03-105**: The Phones list of `docs/31-mockups/14-devices.md` MUST be the platform's own list.
Each phone MUST be one platform row that pushes the next level (`ChromeListRow.push` of
`docs/33-platform-chrome.md` `R-33-073`): the name as its title, `paired <date>` plus the last-seen
age as its subtitle, and the row itself opens the detail. The connected phone MUST be marked by a
trailing `This phone` in the platform's secondary label style, sentence case, and never by a chip.
The list MUST carry no state bar: every paired phone shares one state hue (`R-32-130`), and a bar
that cannot differ says nothing (`R-03-058`). The list MUST offer three destructive actions as
platform rows in their own section: `Remove this phone`, `Remove other phones` (every paired phone
except this one) and `Remove every phone`, each behind the confirmation dialog of `R-33-074`.
`Remove other phones` MUST be disabled when no other phone exists. Decided 2026-09-09 by the
product owner, who pointed at the `Phones on NV-25010015` screen: a green bar on every row in one
hue, a `Details` accent action on every row instead of the platform row that pushes, a drawn
`THIS PHONE` chip, two app-drawn destructive rows, and no way to remove every phone except the
connected one. The mockup owns the rows; `docs/32-design-language.md` owns the values.

**R-03-106**: The app MUST have a `Status colours` page, reachable from `Settings`, that lists
every state the state bar of `R-03-100` can show. Each state MUST be one platform row
(`docs/33-platform-chrome.md` `R-33-073`): the bar itself at the row's leading edge in the state's
hue, the state word as the title, and one plain sentence as the subtitle that says what the state
means for an agent or a computer. Two states that share one hue on purpose
(`docs/32-design-language.md` `R-32-130`: `working` and `warning`, `blocked` and `error`, `idle`
and `ok`) MUST sit next to each other, and the page MUST say in words that they share it and that
the word beside the bar tells them apart. The page MUST be reachable in two taps from any tab: the
`Settings` destination, then the row. Decided 2026-09-09 by the product owner, who saw blue and
green bars in the lists and had no idea what was what: the hues cannot be learned from the app
alone, because the pairs above share one hue by design. `docs/31-mockups/20-status-legend.md` owns
the page; `docs/31-mockups/15-appearance.md` owns the row that opens it.

**R-03-107**: The ground grid of `docs/32-design-language.md` `R-32-332` is the ground of a screen
that has no content: the hero screens (welcome, lock, QR scan, about — manual pairing left this list
on 2026-09-11, per `R-03-127`, because it is a form) and the empty
state of any list. A screen that has content (rows, sections, a card, a table) MUST paint plain
`color.bg.base` with no grid and no paper block, because the owner saw the grid around solid list
blocks and rejected it as ugly. An empty state MUST carry the brand silhouette in `color.bg.grid`
ink, anchored bottom-right the way the welcome hero anchors it (`R-32-594`), decorative and
contrast-exempt, and its title MUST take the accent look: the display face of the screen titles in
`color.accent.text` on `color.bg.base`, with the explanatory sentence under it in `type.body`
`color.fg.secondary`. The fun of this app lives in its type, its accent, its brand mark, its state
bars and its motion, never in a texture behind text. The terminal grid and the key row take none of
this (`R-30-272`, `R-33-055`). Decided 2026-09-09 by the product owner, in two steps: first the
grid on every screen with content on paper, then, after seeing it, the grid only where nothing else
is. `docs/32-design-language.md` owns the values.

**R-03-108**: Motion MUST feel physical the way the platform's own motion does, and the app MUST
NOT invent motion of its own to get there. Concretely: press feedback answers on pointer-down
(`R-32-609`); a sheet is the platform's draggable sheet and follows the finger; the `Priority` /
`Workspace` axis switch on Android tracks the finger one-to-one and hands its velocity to the
platform's page physics (`TabBarView`), and on iOS the segmented control switches with the
platform's own transition; a pushed route is the platform's route with its interactive back
gesture. No overshoot curve (`R-30-271`), no continuous animation beyond the two pulses of
`R-32-601`, and reduced motion is honoured everywhere (`R-32-606`). Decided 2026-09-09 by the
product owner, who asked for a fluent app. `docs/30-ux-spec.md` and `docs/32-design-language.md`
own the behaviour and the values.

**R-03-109**: The create control of the `Agents` screen MUST be a floating action button on both
platforms: Material's `FloatingActionButton` on Android and the same floating control on iOS,
where the platform's own design (Liquid Glass) also floats the primary action; `add` glyph, spoken
`New`; the app draws no create action in the app bar. A list MUST NOT reserve a fixed band of empty
space at its end for the button: a list that fits the screen ends at its last row, and a list that
overflows scrolls its last row clear of the button through the scroll view's own end padding
only. Decided 2026-09-09 by the product owner, who saw the empty band under every list; first
recorded as "move the control into the app bar", then corrected on 2026-09-10 by the owner, who
wanted the floating button kept on both platforms and only the band removed.
`docs/31-mockups/06-agent-list.md` and `docs/33-platform-chrome.md` own the placement.

**R-03-110**: The `Terminal text size` setting MUST be one platform control: a title row with the
current value at its trailing edge (`13 pt`), and under it a discrete platform slider (`Slider` on
Android, `CupertinoSlider` on iOS) whose stops are exactly the permitted sizes of
`docs/21-terminal-rendering.md` `R-21-010`, then the preview box. No `aA` glyph, no `-`/`+`
buttons. Decided 2026-09-09 by the product owner, who called the icon, two buttons, a spacer and the
value a weird layout. `docs/31-mockups/15-appearance.md` owns the row.

**R-03-111**: The Phones list MUST expose its remove actions through one `delete` action in the app
bar that opens the platform's own choice surface: a Material menu on Android and a
`CupertinoActionSheet` on iOS, with `Remove this phone`, `Remove other phones` and `Remove every
phone`, each followed by the confirmation dialog of `R-33-074`. The list MUST NOT show the three
actions as rows, and the sentence about the `r` key moves into the body of the `Remove every phone`
confirmation. Amends `R-03-105`. Decided 2026-09-09 by the product owner, who called the three rows
a terrible way of exposing the feature and asked for a delete icon in the title bar with a popup to
pick what to delete.

**R-03-112**: The `Status colours` page of `R-03-106` MUST also be reachable from where the colours
are: an `info` action in the `Agents` app bar, spoken `Status colours`, pushes the same page. The
Settings row stays. Decided 2026-09-09 by the product owner, who could not find the legend under
Settings and asked why there was still none.

**R-03-113**: The following patterns from `deex2/herdroid` MUST be imported, each inside the rules
that already exist: (1) a hierarchy switcher on the terminal, one sheet that moves between
workspace, tab and pane without leaving the terminal (`R-03-101` still excludes split, zoom and
rename); (2) a denser key row with `alt`, `home`, `end`, page keys and a latched modifier state for
`ctrl` and `alt`, every cap a platform button (`R-03-059`, `R-03-103`); (3) staged connection
progress on the connection screen, one named stage per step with the raw error and one retry
(`R-30-803`, `R-30-804`); (4) a `N waiting · N done` summary in the terminal app bar, words only, no
second mark (`R-03-058`, `R-03-100`); (5) one coalesced alert per agent that routes to the exact
Host, tab and pane, with the readable title of `R-30-505`; (6) a paired-phone health card on the
phone detail (this phone's name, last connection, lock state, the revocation path) with no key
material (`R-13-053`); (7) a cheap reconnect from the cached handle before rediscovery, with no
built-in origin (`R-03-030`, `R-03-031`). Attach recovery with a `Take over` action is NOT imported
until the owner decides lease ownership. Decided 2026-09-09 by the product owner after the
comparison report.

**R-03-114**: The app MUST use Herdr's own words for Herdr's own things. The grouping axis that
orders agents by how much they need a person is `Priority`, as Herdr names it, never `Urgency`; the
tree words are `workspace`, `tab`, `pane`, `agent`; the states are `idle`, `working`, `blocked`,
`done` and `unknown`, as `herdr --skill` defines them. A word this product owns (`computer`,
`phone`, `relay`, `pairing`) stays this product's. Decided 2026-09-09 by the product owner, who found
`Urgency` in the app where Herdr says `priority`. `docs/30-ux-spec.md` owns the axis behaviour and
`docs/31-mockups/06-agent-list.md` the screen.

**R-03-115**: Inside a space block on the `Workspace` axis every pane row MUST be one line high,
agent and shell alike: an agent row reads the agent kind in `type.body`, then the pane name in
`type.caption` `color.fg.secondary` on the same baseline after a `space.2` gap, and at the trailing
edge the state word in `type.body` with the age in `type.caption` `color.fg.secondary` after it,
on the same baseline; a shell row reads the pane glyph and the pane name as today. The two-line
agent anatomy stays on the `Priority` axis, where line two is the breadcrumb no header carries.
Decided 2026-09-10 by the product owner, who saw agent rows at 64 beside shell rows at 48 inside
one block and called the heights inconsistent. `docs/31-mockups/06-agent-list.md` owns the row and
`docs/32-design-language.md` owns the values.

**R-03-116**: The key row MUST have exactly one expansion: the `…` cap opens bank two, and bank
two holds every key that is not on the phone keyboard, the symbols, `home`, `end`, `pgup`,
`pgdn`, `del`, `ins`, the four arrows and `alt`. There MUST NOT be a second surface for the same
keys: the Shortcuts palette and the keyboard action in the terminal app bar are retired, because
two controls that expand the keys and show two different things is inconsistent. A control chord
is typed the way a keyboard types it, `ctrl` latched then the key, and no list of chords is drawn.
Decided 2026-09-10 by the product owner, who found `…` and the app-bar keyboard button gave two
different results. `docs/31-mockups/09-key-row.md` owns the bank and `docs/31-mockups/08-terminal.md`
the app bar.

**R-03-117**: The key row MUST hold only the keys the phone keyboard has no key for, and MUST lay
them out the way a keyboard does. The symbol caps (`- _ = + | \ { } [ ] ( )` and the rest) leave
the row: every one of them is on the phone keyboard's own symbol pages. What stays, in a grid of
six columns and three rows, is the keyboard's own navigation block and its inverted-T arrows: row
one, always visible, `esc` `tab` `ctrl` `alt` `↑` and the bank toggle; row two, in the expansion,
`ins` `home` `pgup` `←` `↓` `→`; row three, `del` `end` `pgdn`. So `ins` sits over `del`, `home`
over `end`, `pgup` over `pgdn`, as on a keyboard, and `↑` sits directly over `↓` with `←` and `→`
beside it, the inverted T. `↓` is in the expansion, not the closed row, because the T is the rule.
Amends `R-03-116`. Decided 2026-09-10 by the product owner, who asked why `tab` sat beside `ctrl`
while `alt` sat at the far end of the list, whether `[ ] { }` were not already on the native
keyboard, and then asked for the keys to sit the way they do on a keyboard: the arrows stacked,
`ins`/`del` and `pgup`/`pgdn` vertical pairs. `docs/31-mockups/09-key-row.md` owns the grid.

**R-03-118**: A latched modifier cap (`ctrl`, `alt`, held or locked) MUST show its state through
the platform's own high-emphasis button form: on Android the `FilledButton` (the theme's primary
fill and its `onPrimary` label) against the `OutlinedButton` of an idle cap; on iOS
`CupertinoButton.filled` against `CupertinoButton.tinted`. A locked cap MUST also underline its
label, and a held cap MUST NOT: the underline is the one mark every phone keyboard puts under the
Shift glyph for caps lock, so held and locked are told apart the way Shift and caps lock are
(amended 2026-09-10 per `R-03-122`; until then the two states shared one look and only the hint
strip told them apart). The label MUST NOT change case, weight or text for state, and the app MUST
NOT draw a bar, a dot, a border or a glow of its own: the fill is the latch and the underline is
the lock. The cap MUST report the state to assistive technology as a toggle (`toggled`), and the
spoken label MUST still say `held` or `locked` (`R-31-09-23`). Decided 2026-09-10 by the product
owner, who found the active state of the modifiers unclear and named it one more reason to use
native buttons and not design hacks (`R-03-059`). `docs/31-mockups/09-key-row.md` owns the
wireframe and `docs/32-design-language.md` the values.

**R-03-119**: A terminal state that ends the person's work in a pane and offers only a way out
MUST be the platform's own alert dialog, not a block the app draws over the grid. The three
states are `pane gone` (`This pane closed.`, one action `Back to agents`), `read failed`
(`Could not read this pane.`, the raw error, `Try again` and `Back`) and `protocol mismatch` (one
action `Back`). On Android the dialog is the Material `AlertDialog`; on iOS the
`CupertinoAlertDialog` with `CupertinoDialogAction` actions and the default action marked. The
dialog MUST NOT close on a barrier tap or a back gesture that would leave the person on a pane
that no longer works; its actions are the only way out. The last painted grid MUST stay visible,
dimmed, behind the dialog, because it is often the reason the pane closed. This amends
`R-30-005`: a modal dialog is allowed for a destructive confirmation and for these three terminal
states, and for nothing else. The dialog follows the role rules of `R-33-074`: the app names the
title, the body and the actions; the platform places them. Decided 2026-09-10 by the product owner,
who saw the `This pane closed.` block and rejected it: not a native modal dialog, no hacks, native
controls only (`R-03-059`). `docs/31-mockups/08-terminal.md` owns the states and
`docs/33-platform-chrome.md` the control map row.

**R-03-120**: `ctrl` and `alt` MUST latch together. A tap on the other modifier while one is
latched adds it; it MUST NOT replace it. The next key then composes the chord with every latched
modifier, joined in the order `R-10-038` requires (`ctrl+alt+<key>`), which the Host already
accepts. Each modifier keeps its own one-shot or locked state (`R-31-09-23`): a key press clears
the one-shot latches and keeps the locked ones, so `ctrl` locked plus `alt` held gives
`ctrl+alt+x` then `ctrl+y`. The hint strip names every held modifier (`Control and Alt held.
Press one key.`), and each cap shows its own state (`R-03-118`). Decided 2026-09-10 by the product
owner, who found `ctrl+alt+<key>` impossible to type. `docs/31-mockups/09-key-row.md` owns the
behaviour and `app/lib/services/chord_latch.dart` holds it.

**R-03-121**: The state bar of the terminal app bar MUST sit before the title, on its leading
side, the way every list row in the app puts its bar in its leading slot before its name
(`R-32-592`, `R-32-597`). It MUST NOT sit among the trailing actions. One shape, one position,
everywhere. Decided 2026-09-10 by the product owner, who saw the bar at the right of the terminal
bar and before the name everywhere else. `docs/31-mockups/08-terminal.md` owns the app-bar anatomy
and `docs/32-design-language.md` section 7.20 the values.

**R-03-122**: `ctrl` and `alt` MUST behave like the Shift key of every native phone keyboard. One
tap holds the modifier for the next key. A second tap on a held modifier MUST release it, unless it
lands inside the double-tap window of `R-30-301`, in which case it MUST lock the modifier. A tap on
a locked modifier MUST release it. There is no state a person reaches by tapping slowly that they
cannot leave by tapping once more. Decided 2026-09-10 by the product owner: under the earlier rule a
second tap always locked, so a person who changed their mind after one tap was forced through a
lock to get out. `docs/31-mockups/09-key-row.md` `R-31-09-23` owns the states and the hint text.

**R-03-123**: Typing MUST appear on the phone's terminal at once, without a round trip: every
printable character and every backspace, including the first one on a line. The app MUST run a
predictive local echo of the kind `mosh` proved (Winstein and Balakrishnan, "Mosh: An Interactive
Remote Shell for Mobile Clients", USENIX NSDI 2012): the terminal on the phone is the display, the
computer stays the only authority, and the app draws the effect it expects a keystroke to have
before the computer confirms it. A prediction is an overlay on the authoritative frame, never a
change to it, and the next frames from the computer confirm it or remove it. The default is
`mosh`'s `experimental` display: nothing waits for confirmation. The app MUST offer one switch,
`Safe typing`, that restores `mosh`'s `always` display, where the model earns its confidence anew
on each line and after each control key, so a password prompt never shows a predicted character;
off by default. Decided 2026-09-11 by the product owner, in two steps: first the round trip was
measured at 230 ms median (`R-02-029`) and any visible delay rejected; then an in-app trace of a
real session showed the confidence gate hiding 8 of 21 typed characters, whole lines after an
`enter` that scrolled, and the owner rejected that too. The cost of the default is stated in the
switch's own line: a prompt that hides what is typed can show it for up to one second. This
amends `R-03-054`: the computer's echo remains the only authoritative echo, and the predicted echo
is a provisional overlay in front of it. It retires the "MUST NOT paint" clause of
`docs/31-mockups/09-key-row.md` `R-31-09-12`. `docs/21-terminal-rendering.md` `R-21-043` owns
the prediction engine and `docs/31-mockups/15-appearance.md` `R-31-15-20` owns the switch.

**R-03-124**: On the `Priority` axis an agent row MUST lead with what the person is working on,
not with the tool. Line one MUST be the **tab title** in `type.body` (`type.body.strong` while
unread), because the tab is the task a person named. Line two MUST be the **workspace** name, then
the pane name, then the agent kind last, all in `type.caption` `color.fg.secondary`, separated by
`›`: `herdr-mobile › pane W · omp`. The agent kind MUST NOT be the primary text: every row on this
computer reads `omp`, so it carries no information at the top of a row and hid the one word that
does. Decided 2026-09-11 by the product owner, who read a row as "omp / › Asset Pipeline Parity ›
pane V" and called the priority wrong: tab name big, space smaller, harness last. `R-03-115`'s
`Workspace` axis row is unchanged: there the tab is the header above the row, so the row itself
keeps the kind and the pane name. `docs/31-mockups/06-agent-list.md` owns the row and
`docs/32-design-language.md` section 7.24 owns the breadcrumb component.

**R-03-125**: Attention state MUST be one state, held by the computer, and every surface MUST read
and write that one state. The computer's meaning of "seen" is Herdr's own (`R-02-031`): a `done`
agent is one that finished and nobody has focused since; a focus marks it seen and it reads
`idle`. So: opening an agent pane on the phone, or `Mark as seen` on its row, MUST mark it seen on
the computer through `mark_seen` (`docs/11-relay-protocol.md` R-11-240), which focuses that pane
in Herdr on the workstation, because focus is what seen means there. A focus on the workstation
MUST reach the phone: the pane leaves `NEEDS YOU` and loses its mark with no action on the phone
(R-11-046 as amended). Neither side keeps a private "read" flag that the other cannot see; the
phone's own marker is a mirror that the next snapshot corrects. Decided 2026-09-11 by the product
owner: "opening a done session on mobile should also mark it as read on the server. It should be
a clear two-way sync for every single thing." Consequence stated plainly: a pane opened on the
phone becomes the focused pane in Herdr on the workstation. That is not a side effect to hide; it
is the sync. `docs/30-ux-spec.md` R-30-503 and R-30-504 own the phone gestures.

**R-03-130**: The terminal on the phone MUST be **two surfaces**, not one: the **grid**, which is
the computer's screen and only ever shows what the computer has drawn, and the **composer**, a
native text field under the grid where the person types. The person's keystrokes go into the
composer, which the platform's own keyboard edits natively: instant glyphs, native backspace,
native cursor, native selection and autocorrect, with nothing drawn on top of the grid and nothing
predicted. The composer sends its text to the computer as `send_input` on **every edit**, so the
computer's own echo follows in the grid at the round trip, and `enter` submits. Decided 2026-09-11
by the product owner after the predictive overlay of `R-03-123` shipped: "Characters pop in and
out, cursor moves, it's so weird. I want a real, native feel, where I write in the input field, it
immediately writes the characters at the right place, I can press backspace to remove. It should
not feel like we're watching a bad stream of the terminal, it should look like the terminal
actually lives in the app." The mechanical cause was measured in the code: the overlay design
cleared and re-fed the **whole grid on every keystroke and on every frame**, re-derived a predicted
cursor from a frame that carries none (`R-02-030`), and retracted glyphs on expiry, so every
keystroke was a full-screen repaint plus a guess. No tuning of that fixes the feel; only removing
the guess does. This **retires** `R-03-123`'s prediction engine, `docs/21-terminal-rendering.md`
`R-21-043`, and the `Safe typing` switch of `docs/31-mockups/15-appearance.md` `R-31-15-20`: with
a native field there is nothing to predict and nothing to hide. `R-03-054`'s clause that the
computer's echo is the only echo in the **grid** stands and is now literally true. The composer's
shape, its key row, its `enter` and its raw-key path (a control chord or an arrow goes straight to
the pane, never through the field) are owned by `docs/31-mockups/09-key-row.md`; the grid's
feed-on-arrival and viewport stability are owned by `docs/21-terminal-rendering.md` `R-21-021`
and `R-21-044`.

**R-03-131**: The terminal grid MUST take its **background and foreground from the computer's
Herdr theme**, so the pane on the phone is the pane on the desk. Decided 2026-09-11 by the product
owner: "implement herdr themes for the terminal window. The terminal window background should be
able to change with themes matching the herdr desktop app." Herdr exposes no theme over its socket
(measured 2026-09-11: zero theme, palette or background members in the API schema), so the Host
plugin reads it where the Herdr desktop app reads it: `[theme]` in Herdr's own `config.toml`
(`name`, `dark_name`, `light_name`, `auto_switch`), resolved against the same eighteen-theme
catalogue the desktop app bundles (`ThemePalette.cs`), and sends the resolved palette to the
phone in `host_info` and again in a `host_theme` message whenever the file changes. The phone MUST
apply exactly what the desktop app applies and no more: `SurfaceDim` as the grid background,
`Text` as the default foreground, the ANSI sixteen unchanged (the desktop keeps its fixed table),
the cursor unthemed. A palette value of `reset` (the `terminal` theme) means "no override": the
grid keeps the app's own `color.bg.base` and `color.fg.primary`. The theme reaches the **grid
only**: the app chrome around it stays the app's own design language, per `R-33-055`'s isolation of
the terminal from the chrome. `docs/11-relay-protocol.md` owns the two messages,
`docs/10-herdr-integration.md` owns the Host read and watch, `docs/21-terminal-rendering.md` owns
the grid's application of the palette.

**R-03-132**: The composer and the key row MUST be **one input bar**, shaped like the message bar
of the platform's own messaging app, and every part of it MUST be the platform's own control.
Decided 2026-09-14 by the product owner, who saw the first composer live: "The composer looks
absolutely horrible. Look at messaging apps, see how you can combine the extra keys with the actual
composer, support multi-line text, etc. and it must all look native. Right now you have no
spacing/padding, non-native fields and icons." The bar is one raised surface under the grid: a
rounded text field that grows with its text from one line to a fixed maximum, a round send control
trailing it on the same row, and bank one of the key row directly under it inside the same surface,
with one padding token around every part and no rule between the field and the keys. The field
uses `type.mono.compose`, the token that already exists for this purpose, not `type.mono.code`. The
platform's return action still submits, per `R-31-09-28`, because the pane's `Enter` is what a
terminal means by return; the field wraps long text so it can be read before it is sent. Nothing in
the bar is app-drawn: the field, the send control, the keys and the row toggle are the widgets the
native control map of `docs/33-platform-chrome.md` section 5 names, and the icons come from the one
icon set of `R-32-401`. `docs/31-mockups/09-key-row.md` owns the bar's layout and behaviour,
`docs/32-design-language.md` section 7.13 owns its values, `docs/33-platform-chrome.md` owns the
per-platform widgets.

**R-03-133**: The input bar MUST have the **anatomy of the platform's message bar exactly**, not an
approximation of it. Decided 2026-09-14 by the product owner after the first bar shipped with a
field shorter than its send control and a permanent row of keys under it: "The field is not the
same size as the send button which is a rookie mistake, you still have a whole row of extra buttons
instead of something like the + button iMessage has to show more options." The anatomy, taken from
iOS Messages and Google Messages: one row of three parts, a round `+` control leading, the field in
the middle, the send control trailing. **Every control on the row is exactly the field's
single-line height**, and when the field grows the controls stay bottom-aligned with its last line.
The key row is gone as a permanent surface. The `+` opens the **key panel** in the place of the
The key row is gone as a permanent surface. The `+` opens the **key panel**, and the panel MUST
open **above the bar, over the bottom of the grid, with the keyboard left exactly as it was**:
up stays up, down stays down. The owner ruled out the alternative the same day, a panel that takes
the keyboard's place the way the iOS Messages apps drawer does ("the extra keys being under the
keyboard also seems like a terrible design layout"): a control chord needs a key from the panel and
a letter from the keyboard in one motion, so the two MUST be on screen together, which is the
layout every phone terminal (Termux, Termius, Blink) uses for its extra keys. One tap on `+` shows
every key (the former bank one and bank two as one grid) and the control reads `×`; a tap on `×`
or on the grid closes it; field focus and a modifier latch leave it open. On iOS the send control
sits inside the field's trailing end and the row is the Messages height; on Android the send
control is a filled round icon button outside the field and the row is `size.field`.
`docs/31-mockups/09-key-row.md` owns the panel and the bar, `docs/32-design-language.md` section
7.13 owns the values, and `R-31-09-01`'s "bank one is always visible" is retired by this rule: the
keys are one tap away.

**R-03-134**: A split MUST be offered **on the pane it splits**, in the pane action sheet behind
the terminal's overflow control, and MUST NOT be offered in the create menu of the `Agents`
screen. Decided 2026-09-14 by the product owner, in three steps the same day: first "there's no
splitting in mobile", then "split can make sense but then we should focus the new panel in the
tab, single terminal always", then "if we want a CLI separate from our agent session we'd need to
split, but that can be in the `…` in the menu bar". The use is real: a shell beside the agent you
are watching. So the action lives where that agent is on screen, as `Split right` and `Split down`
rows above `Close pane`, and the create menu of `docs/31-mockups/17-create.md` holds `New space`
and `New tab` only, with no pane context. After the Host acknowledges a split the app MUST open
the new pane in the single terminal view at once: the phone shows one pane at a time and never a
side-by-side layout, so "focus the new pane" is the whole visible result. This amends `R-03-101`,
which removed split from the sheet on 2026-09-09 as a desktop layout task; the two rows return,
and zoom, rename and copy stay out. `docs/31-mockups/10-pane-actions.md` owns the rows,
`docs/31-mockups/17-create.md` owns the menu, `docs/30-ux-spec.md` `R-30-511`'s route owns the
navigation to the new pane.

## 8. Local notifications only

**R-03-060**: The notification model MUST work as follows. Herdr emits `done` or `blocked`. The Host
plugin sends an encrypted `agent_status` protocol event through the relay. If the app process is
alive, the app creates a native local notification and a tap routes to the matching Host and pane. The
`agent_status` payload and the tap route are owned by `docs/11-relay-protocol.md` and
`docs/30-ux-spec.md`.

**R-03-061**: Version 1 MUST NOT depend on any platform push notification service, any wake mechanism
external to the app process, or any background-delivery guarantee. The decision is recorded in
`docs/decisions/ADR-005-local-notifications-only.md`.

**R-03-062**: If the operating system suspended or terminated the app, no notification is promised.
On
the next launch or reconnect, the app MUST show unseen attention state in-app. The app MUST NOT
synthesise a stale system notification for an event that happened while it was suspended.

**R-03-063**: No public text, store description, settings label, onboarding screen or privacy statement
MAY call this push notification support. The public wording MUST be "local notifications while the
app is running".

## 9. QR-first pairing with six words

**R-03-070**: The Host MUST render the pairing QR code. The relay MUST NOT have a QR endpoint.

**R-03-071**: Manual entry of an HTTPS origin plus six Diceware words MUST be the fallback pairing
path. Manual entry and QR entry MUST produce an identical pairing input record.

**R-03-072**: The pairing phrase, the routing handle and the pairing URI are owned by
`docs/13-security-pairing.md` and `docs/11-relay-protocol.md`. This document states the policy. Those
documents state the exact encoding, validation and error codes.

**R-03-073**: A pairing URI opened as a link on the phone MUST be a third pairing path, equal to
the other two. The app MUST open `/pair/manual` with every field filled from the link, so the person
only presses `Pair`; the app MUST NOT pair on the link alone, because a link can be opened by
accident and the press is the person's consent. When a computer is connected at that moment, the
press MUST first raise the one confirmation dialog `R-30-005` permits, and MUST disconnect only on
the confirming action; `R-30-945`'s caption is not enough for a link, because the person did not
type anything that says they meant to switch. Decided 2026-09-10 by the product owner.
`docs/30-ux-spec.md` owns the dialog text and `docs/22-platform-integration.md` the link handling.

## 10. Operating-system theming

**R-03-080**: Every app surface MUST follow the operating-system light or dark setting by default. A
person MUST be able to override the setting to `Light` or `Dark` explicitly.

**R-03-081**: The app MUST support three theme modes: `System`, `Light`, `Dark`. `System` is the
default. It follows the operating-system setting and MUST react to a change while the app runs, with
no restart and no reconnect.

**R-03-082**: Both themes MUST be first class. The light theme MUST be produced from a complete set
of colour values owned by `docs/32-design-language.md`. The app MUST NOT produce the light theme by
inverting the dark theme at run time. Every colour token, including the 16 ANSI terminal slots, MUST
hold a value in both themes.

**R-03-083**: The terminal palette MUST switch with the theme. A terminal is the main surface of this
app. A dark-only terminal on a light phone burns a person's eyes at night. A light-only terminal on
a
dark phone washes out in daylight. The developer's phone follows the system setting everywhere else;
a
terminal app that ignores it is the one app that breaks the pattern.

**R-03-084**: The Host popup pane MUST NOT hardcode any colour value and MUST NOT detect the
operating-system brightness. The popup runs inside the user's terminal under `ratatui`. It uses
`Color::Reset` for default foreground and background, and the eight basic `Color` variants that name
ANSI slots. The user's terminal resolves those slots to its own theme. Selection uses
`Modifier::REVERSED`, which swaps whatever the terminal's own foreground-background pair is.
`Color::Rgb` and `Color::Indexed` are forbidden in the popup. The Selenized colour values owned by
`docs/32-design-language.md` apply to the phone app only.

**R-03-085**: The platform signal that reports the operating-system brightness is owned by
`docs/22-platform-integration.md`. The mechanism that stores the person's theme-mode preference is
also owned by `docs/22-platform-integration.md`. The terminal palette response to a theme change is
owned by `docs/21-terminal-rendering.md`.

## 11. App Lock

**R-03-090**: App Lock MUST be optional and MUST default to off. Pairing, first launch, and every
other app action MUST work fully with App Lock off, on a phone with no device screen lock of any
kind. This reverses the former precondition that a screen lock is mandatory to pair, recorded in
`docs/decisions/ADR-009-optional-app-lock.md`.

**R-03-091**: The app MUST offer to turn App Lock on exactly once, on the first arrival at the
agent list after the first successful pair, alongside the notification-permission ask of
`R-03-060`. It MUST NOT ask a second time and MUST NOT gate pairing, or any other app access, on
the answer. `docs/30-ux-spec.md` owns the exact moment and wording.

**R-03-092**: A person MUST be able to turn App Lock on or off at any later time from Settings.
Turning it on or off MUST NOT generate a new Device key and MUST NOT unpair any computer. The
mechanism, the storage change, and the `/lock` screen's conditional behaviour are owned by
`docs/13-security-pairing.md`, `docs/22-platform-integration.md` and
`docs/31-mockups/04-lock.md`.

## What this document does not decide

This document is the product-owner policy layer. It does not own the following topics. Each cites its
owning document.

| Topic | Owning document |
| --- | --- |
| Wire protocol, frame envelope, message types, close codes | `docs/11-relay-protocol.md` |
| Cryptography, Noise handshake, key storage, revocation mechanism | `docs/13-security-pairing.md` |
| App Lock mechanism, key protection level, `/lock` screen | `docs/13-security-pairing.md`, `docs/22-platform-integration.md`, `docs/31-mockups/04-lock.md` |
| Relay deployment profiles and operator instructions | `docs/14-relay-deployment.md` |
| Internal NVIDIA relay experiment | `docs/15-nvidia-brev-relay-experiment.md` |
| Colour values, design language | `docs/32-design-language.md` |
| Terminal palette, rendering response to theme change | `docs/21-terminal-rendering.md` |
| UX screens, flows, interaction model, design tokens | `docs/30-ux-spec.md` |
| Host list drawing, connection-state glyphs, saved-computer display | `docs/30-ux-spec.md`, `docs/31-mockups/05-host-list.md` |
| App-store metadata, release tracks, signing, versioning | `docs/23-public-release.md` |

## Open questions

No genuine external dependency remains open at the product-policy layer. Every topic this document
does not decide is owned by a named document.

## Sources

- Product owner decisions, recorded in this remediation.
- `docs/00-overview.md` — purpose, requirements and non-goals.
- `docs/01-architecture.md` — component boundaries, data flow and cross-document ownership.
- `docs/11-relay-protocol.md` — wire protocol owner.
- `docs/13-security-pairing.md` — pairing and cryptography owner.
- `docs/15-nvidia-brev-relay-experiment.md` — internal deployment experiment.
- `docs/20-mobile-framework.md` — mobile framework owner.
- `docs/21-terminal-rendering.md` — terminal rendering and palette response to theme change.
- `docs/22-platform-integration.md` — platform integration owner.
- `docs/23-public-release.md` — app-store metadata owner.
- `docs/30-ux-spec.md` — UX specification owner.
- `docs/31-mockups/05-host-list.md` — host list mockup.
- `docs/32-design-language.md` — design language and colour value owner.
- `docs/decisions/ADR-005-local-notifications-only.md` — recorded decision to omit push delivery.
- `docs/decisions/ADR-009-optional-app-lock.md` — recorded decision to make App Lock optional.
