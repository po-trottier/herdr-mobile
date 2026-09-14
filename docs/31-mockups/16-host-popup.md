# 16 - Host plugin popup pane

| Field | Value |
| --- | --- |
| Route | not a route. Herdr popup pane, entrypoint `relay` and `relay-windows` |
| Surface | Host: Windows, Linux, macOS |
| Opened by | `herdr plugin pane open --plugin herdr-relay --entrypoint relay` |
| Spec | `docs/30-ux-spec.md`, Host popup pane section |

This is a terminal user interface, not a graphical one. A popup pane is the only user surface
a Herdr plugin can open. Every mock below is exactly what the pane prints, and every mock is 72
columns wide.

72 columns is not a given. The manifest in `docs/10-herdr-integration.md` asks for a popup of
`70%` by `70%`, so 72 columns need a terminal of 103 columns, and the 46 row full pairing layout
needs a terminal of 66 rows. That is a large terminal. The cause is the QR code: a 49 module
symbol plus its quiet zone is 29 printed rows, and no arithmetic makes it smaller. The compact
layout is therefore the common case, not the exception. A `ratatui` frame does not scroll, so the
pane measures its own rectangle and drops a whole region rather than clip one, per `R-31-16-25`
and `R-31-16-26`.

The layout and the key bindings copy `herdr-scheduled`, so a person who already uses one plugin
already knows this one. The differences are named in the rules below.

**This pane inherits the user's terminal theme.** It has no light variant and no dark variant, it
never detects terminal brightness, and it holds no hex value of any kind. Every colour it prints is
terminal relative: the default pair, the eight basic ANSI hues, bright black and reverse video, per
`R-32-700`. The Selenized palette that the phone app uses does not apply here, per `R-32-703`, and
nobody may make the two match: the person already chose a theme for this terminal, and the pane's
job is to be readable inside it.

This pane is where the secret is born. It draws the six words and the routing handle, it encodes
the pairing URI, and it prints the QR itself. There is no QR endpoint on the relay to ask, and
there is no numeric code anywhere in this product.

## Wireframe and callouts, pairing, full layout

```text
herdr relay (2 phones)
relay: https://relay.example.com   connected

pair a phone                                             expires in 1:47


      █▀▀▀▀▀█   █▄▄▄▄▀▄▀█ █▀▄██▀▀▀█▀▄▄█▄▄▄ █▄▄█ █▀▀▀▀▀█
      █ ███ █ █ ▀█ █ ▀ █ ▀▀▄▄▄▀▀ ▀▀█▄█▀█  ▄▄ █▀ █ ███ █
      █ ▀▀▀ █ █ ▀▄█ ▀▀█  ▀█▀█▀▀▀█  ▄▀▀▀▄▄▀▀█▄   █ ▀▀▀ █
      ▀▀▀▀▀▀▀ █ █ █▄█▄█▄▀▄█ █ ▀ █▄█▄▀▄█ █ ▀ █ █ ▀▀▀▀▀▀▀
      █▄▀▀█▀▀▄ ▀ ▄▀▄ █▄▀█▄▀ █▀▀█▀▄ ██  ▀▀▄█▄  ▀▄██▀██ ▄
      █▀▀ ▀█▀▄ ██▀█  █▄▀ ▀▀  ▀ █▀▀█▄▄▄█▀██▀ ▀▄▄▄   ▀ ▀▀
      ▄▀ ▀▄█▀▀  ▀ █  ▄███▀ █▀ █ ▀▄ ▄█ ▄  █▀▄▀ ▀██▀▄▀▀ ▀
      ▀▄ █ ▄▀  ██ ██▀▄▄ █▀ ▄  ▀▀▀▀▀▀▄▀  ▀▀  ▀ ▄▀▄▀▄  ▀█
      ▄ ▀██▄▀▀  ██▄▄▄▄ █▄█▀▄ █▀▄▀▀ ▀█    ██▄▀ ▀██▀  ▀
      █▄█▀  ▀█ ▄ ▄▀ ▀█▀█▀ ▀ ▀ ▀ ▀▀▄▀█▄▄▄▀▄ ▄▀  ▀▄▀█  ██
      ▄ ▀▀  ▀ █▄▄▄▄ ▄▀  ▀▄▀█▄▄▀▀ ▄ ▀██   ▀█▄ ▀▀▀█ ▄ ▀█▀
      ▄▀▄██▀▀▀█▄▄ ▀  ▄ ▀ ▄▀▀█▀▀▀█▀█▄ ▀▄█▀▀▀ ▀▄█▀▀▀█▀▀█▀
      ▀▄▄ █ ▀ ███ █▀  █▄ ▄ ▀█ ▀ █ ▄ ▄▀▄ ▀▀██  █ ▀ █ ██
      █▄▀▀▀█▀██ ▄ ██▀▄▀▀▀ ▀▀▀▀██▀▄█▀▄█▄▀▀▀ ▄▀▀█▀▀▀▀▀ ▄█
      ██ ▄▀█▀ ▀▀▄▄█▄▀█▀██▄▄▄█▀█▀   ▄▄█▄▀ ▄▀█ ▀ ▄▄▄▀█▀▀▀
       ▀█▀▄ ▀▄▀▀▀ ▄█▄▀▄▀▄▄█ █▀██▄▄▀█ ▀▀▀▀▀ ▄▀▀▀▀▀ ██ ▀▀
      █▄▀   ▀▀▄▄ █▀▄▀█▀▀▄█▀ ▀█▄▄▀▄█▄ ▄▄▀ █▀  █  ▀█▀█▀▀▀
      ▄█▄█▄▄▀█▀▄█  ▀▀▀ ▄▄█ █▀▀█▄▄▄█▄█ ▄██  ▄▀▀▄▀▀ ▄▀▀▀█
      ▄ ▄▄█▀▀▄█  ▀▄▀█▄ █ ▀▀█▄▄█▄▄  ▄▄▀   ██▀ ▀▄▄▄▄▀█▀▀▄
       █▄▄ ▀▀ █▀ ▄▄▄ ▀██▀██  ▄█▀▄▄██▄ ▄ █▀▀██ ▄ ▀█ ▀▀▀█
      ▀▀▀   ▀ ▄▀█ ▀█▀ ▀ █▀▀██▀▀▀█▄ ▄▄▄  ▀▀██ ▀█▀▀▀██▀
      █▀▀▀▀▀█ ▄▄▀█▄█ █▄▀██ ▄█ ▀ █ █ ▀███▀ ▀██▀█ ▀ █   ▀
      █ ███ █ ██ █ █ █▀▄ ▀ ▄▀█▀███▄▀█ ▄   ▀█ ██████▀▄▀█
      █ ▀▀▀ █ ▀▄ ▀ █ ▄▀▄ ▀ ▄▄▀█▄█▀  ▄ ▄▄█  ▄█▄ ▄▄▀    ▄
      ▀▀▀▀▀▀▀ ▀▀  ▀▀▀  ▀  ▀   ▀  ▀ ▀▀▀   ▀▀▀  ▀▀ ▀ ▀▀▀▀


  or type these in on the phone:
    relay:    https://relay.example.com
    computer: n6Loxf94CfyIO6hOxlaHvA
    phrase:   remedy tapestry hubcap oversleep jailbird kinetic
press c to copy the pairing link

Phone            Platform     Paired            Last seen    State
pixel-8-pat      android 15   08-24 09:14       now          connected
iphone-15-pat    ios 18.5     08-22 17:02       3m ago       idle

paired 22 Aug 17:02  -  last seen 3m ago  -  ios 18.5
key 3f9a-1c04-be77-20d5
p pair  c copy  d remove  r all  s stop  f reload  q quit
```

1. Title line. `herdr relay (N phones)` in ANSI cyan, which is `ESC [ 36 m`, exactly as `ui.sh` line
   170 prints `herdr scheduled jobs (%s)`. `N` counts the phones in the stored paired-device list,
   not the connected one, per `R-31-16-20`.
2. Second line. The relay origin, exactly as configured, then the link state, in ANSI bright black,
   `ESC [ 90 m`. Both come from the bridge's `status` answer (R-10-064): the origin is the value
   the bridge validated on load (R-10-061), and the pane prints it in full, per `R-30-922`. The
   pane prints the `https` origin, not the `wss` URL the bridge dials, because the origin is the
   value a person configured. The link state is one of R-10-064's four words, and no round trip
   prints, per `R-31-16-21`.
3. Section line `pair a phone`, with the countdown right aligned at column 72. The countdown runs
   from the moment the phrase was drawn and ends at 600 seconds (`R-13-022`). It is bright black
   until 60 seconds remain, then ANSI yellow, `ESC [ 33 m`.
4. QR region. The plugin encodes the pairing URI with the `qrcode` crate and renders it with half
   block glyphs, two module rows per printed row, exactly as `docs/13-security-pairing.md`
   `R-13-030` requires. For the worked example URI of `R-30-900`, which is 134 bytes, the encoder
   chooses QR version 8 at error correction level `M`, so the symbol is 49 by 49 modules and the
   region is 57 columns by 29 printed rows, per `R-31-16-02`. The region is indented by two
   columns. Its first two rows, its last two rows and its four outer columns on each side are the
   4 module quiet zone, so the symbol starts at column 7 and fills the middle 25 rows. Nothing may
   print inside the quiet zone. The 25 rows of glyphs above are the version 8 level `M` encoding of
   that exact URI.
5. The text block. The relay origin, the computer code, and the six words separated by single
   spaces. It is always printed, never only as a fallback, because a person reading words aloud to
   someone across a desk needs them on screen. The words are shown with spaces, and the URI carries
   them with hyphens, per `docs/13-security-pairing.md`.
6. Table header, bright black. Column budgets are fixed: phone 16, platform 12, paired 17, last
   seen 12, state to the end. `ui.sh` line 176 uses the same fixed width style. A budget counts
   display cells, and a value wider than its budget elides, per `R-31-16-28`.
7. Table rows. The selected row prints in reverse video, `ESC [ 7 m`, exactly as the reference marks
   its selection. Every printed value comes from the Host's own stored record of `R-13-049`: the
   phone from `device_name`, the platform from `platform` and `os_version`, the pair time from
   `paired_at`, and the last seen time from `last_seen`.
8. State colour on a row that is not selected: `connected` in ANSI green, `idle` with no colour, and
   `unknown` in ANSI yellow. `R-31-16-19` holds the condition that produces each word. At most one
   row reads `connected`, because one phone is active at a time. A phone that loses access has no
   row at all. `R-13-053` removes the entry, so the loss prints on the notice line of callout 11,
   and the row is gone in the same redraw. The reference colours its status column the same way.
9. Detail block for the selected phone, under a blank line. Line one holds the pair time, the last
   seen time and the platform, all three from the stored record of `R-13-049`. Line two holds that
   phone's key fingerprint, which the Host computes from the stored `static_public_key` in the
   format `R-13-040` owns. The block carries no access level, because every paired phone has full
   control.
10. Footer, bright black, one line, the same shape as the reference footer. It has three widths and
    it omits an inert binding, per `R-31-16-30`.
11. A notice line prints under the footer in ANSI yellow after an action, and clears on the next
    redraw. The reference does this with its `notice` variable.
12. The copy hint line. `press c to copy the pairing link`, bright black, directly under the
    phrase line of the credential block, in both pairing layouts, per `R-31-16-34`. The footer at
    72 columns prints `c copy` in its short form, because `c copy` makes the labelled form 80 cells
    and `R-31-16-30` prints the widest form that fits.

## Wireframe and callouts, pairing, compact layout

The QR region does not always fit. `R-31-16-26` then drops it whole and keeps the words, because
the words are the credential and the QR is only a faster way to carry them. The mock below sits at
the pairing floor of 12 rows, so the detail block and the table are dropped as well.

```text
herdr relay (2 phones)
relay: https://relay.example.com   connected

pair a phone                                             expires in 1:47

  no room for the qr code. type these in on the phone:
    relay:    https://relay.example.com
    computer: n6Loxf94CfyIO6hOxlaHvA
    phrase:   remedy tapestry hubcap oversleep jailbird kinetic
press c to copy the pairing link

p pair  c copy  r remove all  s stop  f reload  q quit
```

 1. The compact layout prints one extra line that says why the QR is absent and what to do instead.
    It names the phone's `type it in` path, so the person is not left guessing.
 2. The footer drops `up/down select` and `d remove`, because the table is dropped and no phone row
    is drawn, per `R-31-16-29` and `R-31-16-30`. A taller pane keeps the table and both bindings.
    `c copy` stays, per `R-31-16-34`, because the pairing session is still open and `c` still acts.

## Wireframe and callouts, pairing, registering

`p` asks the bridge for a pairing, and the bridge registers the handle with the relay in the
background (R-10-064). Until the relay answers `session_joined`, the status answer carries
`registered: false` and null credential fields, and the pane shows no QR, no words and no handle,
per `R-31-16-39`.

```text
herdr relay (2 phones)
relay: https://relay.example.com   idle

pair a phone                                            expires in 10:00

  registering...

p pair  s stop  f reload  q quit
```

 1. The countdown runs from the status answer's `expires_in_s`. The credential block is one
    `registering...` line and nothing else. `c copy` is absent from the footer, because there is no
    URI to copy yet (R-31-16-34).

## Wireframe and callouts, bridge not running

The pane is a client of the bridge (R-10-066). When no bridge answers the R-10-062 endpoint —
never started, stopped, or a stale endpoint after a crash — the pane shows the exact notice of
R-10-066 and no pairing surface. A `relay_origin` that fails R-10-061 lands here too: the bridge
refuses to start on one, so this state is what its refusal produces.

```text
herdr relay

bridge not running - start herdr-relay first (the service starts it at login)

q quit
```

 1. The notice wraps rather than clips when the pane is narrower than its 79 cells. The only key
    that still acts is `q`; `f` retries the status call.

## Wireframe and callouts, idle, no pairing session open

```text
herdr relay (2 phones)
relay: https://relay.example.com   connected

Phone            Platform     Paired            Last seen    State
pixel-8-pat      android 15   08-24 09:14       now          connected
iphone-15-pat    ios 18.5     08-22 17:02       3m ago       idle

paired 24 Aug 09:14  -  last seen now  -  android 15
key 8c21-04ad-77be-1d05

up/down select  p pair  d remove  r remove all  s stop  f reload  q quit
press p to pair another phone
```

 1. With no pairing session open, the QR block, the words and the computer code are all absent, and
    the pane ends with a hint line. Nothing about a live pairing is left on screen, because a phrase
    visible on a screen behind a person is a real risk.

## Wireframe and callouts, empty

```text
herdr relay (0 phones)
relay: https://relay.example.com   connected

no phones yet - press p to pair one.

p pair  s stop  f reload  q quit
```

 1. The empty text copies the reference wording shape, `no jobs yet - press n to create one.`, from
    `ui.sh` line 173.
 2. The footer drops `up/down select`, `d remove` and `r remove all`, because the stored list holds
    no phone, so all three would act on nothing, per `R-31-16-29`.

## Wireframe and callouts, relay offline

```text
herdr relay (2 phones)
relay: https://relay.example.com   offline

Phone            Platform     Paired            Last seen    State
pixel-8-pat      android 15   08-24 09:14       14:02        unknown
iphone-15-pat    ios 18.5     08-22 17:02       14:02        unknown

relay unreachable since 14:02:11 - connect: i/o timeout
retrying, attempt 4

up/down select  p pair  d remove  r remove all  s stop  f reload  q quit
```

 1. The second line drops the latency and reads `offline` in ANSI red.
 2. Every last seen value freezes at the time the link dropped, and every state becomes `unknown` in
    yellow. The pane never claims a phone is connected while the relay is unreachable.
 3. Two lines replace the detail block: the raw error, and the current attempt number. The pane
    prints the attempt number only. It MUST NOT print a delay, a cap or a total, because
    `docs/22-platform-integration.md` owns the schedule in `R-22-028`.

## Wireframe and callouts, confirmations

The reference confirms a destructive action with a full screen clear and a `y/n` question,
`ui.sh` lines 301 to 304. Three keys ask a question here, `d`, `r` and `s`, per `R-31-16-09`. While
a question is open it owns every key, and `q` cancels it rather than quits the pane, per
`R-31-16-32`. A question wraps rather than clips, so its count of affected phones always reads.

```text
remove pixel-8-pat? 1 phone loses access. y/n
```

```text
remove every phone? 2 phones lose access at once. y/n
```

```text
stop the relay? this phone list is kept, and no phone can connect. y/n
```

## Wireframe and callouts, terminal too small

```text
pane too small
enlarge the terminal
q quit
```

 1. Three lines, 20 cells at the widest, so they fit the 28 column floor of `R-31-16-26`. The pane
    prints as many of them as fit, from the top down.
 2. The pane prints no part of the credential and no phone row here, per `R-31-16-27`. A truncated
    address, code or phrase is worse than none, because a person cannot tell it is truncated.

## Layout regions

`R-31-16-25` measures the pane rectangle on every draw and fills it with these regions, from the
top. A drop order of `-` means the region is never dropped. The idle, empty and offline mocks use
a subset of these regions plus their own one or two lines.

| Region | Height in printed rows | Drop order |
| --- | --- | --- |
| Title and relay line | 2, or more when the origin wraps | - |
| `pair a phone` with the countdown | 1 | it goes with the pairing session |
| QR region | `R-31-16-02`; 29 for the worked example | 1 |
| Credential block, plus the copy hint line | 5, or more when a value wraps; 1 while registering (R-31-16-39) | - while a pairing session is open |
| Table header and phone rows | 1, plus one row for each phone | 3 |
| Detail block | 2 | 2 |
| Footer | 1 | - |
| Notice line | 0 or 1 | - |

One blank row separates two neighbouring regions, and that blank row goes with the region below
it. The QR region is the exception. Its quiet zone already gives two blank rows above the symbol
and two below, so the pane adds no separator on either side of it.

Row arithmetic at 72 columns, with two phones and no notice line. The full pairing layout is 47
rows, the compact pairing layout is 12, the idle layout is 11, the offline layout is 11, and the
empty layout is 6. The notice line adds one row to any of them, and the idle mock above shows it as
the hint line, which makes that mock 12 rows. The compact mock above sits at the pairing floor of
`R-31-16-26`, where drop orders 1, 2 and 3 are all spent.

Column arithmetic in display cells. The footer is 80, 57 or 13 cells, per `R-31-16-30` and
`R-31-16-34`. The five table columns with `connected` need 70 cells, four need 57, three need 39,
and the last two need 26. The QR region needs 59 with its two column indent. The relay line is 52
for the worked example origin. The credential block is 63 for the worked example phrase, and 73
for a phrase of six nine-letter words. 73 is one cell wider than the
frame, so `R-31-16-27` wraps that block. The word list of `R-13-017` holds words of 3 to 9 letters,
so a phrase is 23 to 59 cells.

## Key bindings

| Key | Action | Matches the reference |
| --- | --- | --- |
| `up`, `k` | move the selection up, and nothing when no row is drawn, per `R-31-16-29` | yes, `ui.sh` lines 52 and 59 |
| `down`, `j` | move the selection down, and nothing when no row is drawn, per `R-31-16-29` | yes, `ui.sh` lines 53 and 60 |
| `p` | ask the bridge for a pairing session (`open_pairing`, R-10-064): the bridge mints six words per `R-13-017` and a handle per `R-11-112` and registers the handle with the relay, and the pane draws what the next `status` answer carries. With an invalid `relay_origin` the bridge refuses to start (R-10-061) and the pane shows the bridge-not-running state | new, the reference uses `n` for new |
| `c` | copy the full pairing URI to the clipboard while a session is open, per `R-31-16-34`, and set the nothing-to-copy notice with no session open | new, no reference twin |
| `d` | remove the selected phone, per `R-13-053`, with a `y/n` confirmation, and nothing when no row is drawn | yes, the reference `d delete` |
| `r` | remove every phone, per `R-13-056`, with a `y/n` confirmation, and nothing when the list is empty | new. The reference `r` is `run now` |
| `s` | stop this computer's own relay connection, per `R-31-16-24`, with a `y/n` confirmation | the reference `s` is `sync`, also a write |
| `f` | reload the phone list and redraw, per `R-31-16-07` and `R-31-16-08` | yes, the reference `f refresh` |
| `q`, `esc` | quit the pane, which also ends a pairing session, per `R-31-16-05` (`q` sends `close_pairing` first, per `R-31-16-40`), except while a `y/n` question is open, when both cancel it, per `R-31-16-32` | yes, `ui.sh` line 273 |

The word `refresh` in the product brief means `revoke every Device`. In this pane that action
is `r remove all`, and `f` keeps the reference meaning of redraw. Two keys that both read as
`refresh` would be a trap, because one is harmless and one destroys every grant.

### The plugin's own actions

The manifest in `docs/10-herdr-integration.md` declares four actions. Each one has a platform twin,
`<id>` for macOS and Linux and `<id>-windows` for Windows, and the twins are one action.

| Action id | Title the phone shows | Destructive | Key in this pane |
| --- | --- | --- | --- |
| `pair` | Pair a phone | no | `p`, and the action itself opens this pane |
| `clients` | List paired phones | no | none. It writes to the plugin log |
| `refresh` | Revoke all phones | yes | `r` |
| `stop` | Stop the relay | yes | `s` |

`R-31-16-33` owns the destructive column, and it is the rule a phone screen cites.

## States

| State | Trigger | Pane shows |
| --- | --- | --- |
| Loading | The pane started, or `f` was pressed and the reload is running. | One line, `loading...`, in bright black, exactly as `ui.sh` line 258 and line 370 print it. Then the full redraw. |
| Idle | The relay link is up and no pairing session is open. | The idle mock. |
| Pairing, full | `p` was pressed, the registration is accepted and the QR region fits the pane rectangle. | The full pairing mock, with the countdown ticking once a second. |
| Pairing, compact | `p` was pressed, the registration is accepted and the QR region does not fit, so `R-31-16-26` dropped it. | The compact pairing mock. |
| Pairing, registering | `p` was pressed and the bridge has not reported `registered` yet (R-10-064). | The registering mock: the `pair a phone` header, the countdown, one `registering...` line, and no credential, per `R-31-16-39`. |
| Bridge not running | No bridge answers the R-10-062 endpoint, including when an invalid `relay_origin` stopped it at load (R-10-061). | The bridge-not-running mock: the exact notice of R-10-066 and no pairing surface. |
| Empty | The relay link is up and the stored list holds no phone. | The empty mock. |
| Offline, relay unreachable | The Host's own relay connection dropped. | The offline mock, with the current attempt number. |
| Error, the URI is too long | The configured origin makes the pairing URI exceed the 512 byte limit of `R-11-141`, which the bridge checks when it mints. | No pairing opens: `open_pairing` answers `bad_request`, and the pane shows the rejection notice. The fix is a shorter origin in `config.toml`. |
| Error, phrase expired | The countdown reached zero with no phone paired. | The QR block, the words and the computer code all clear. One yellow line reads `phrase expired - press p for a new one`. |
| Error, phrase spent | The third failed handshake attempt destroyed the phrase and the handle (`R-13-023`). The bridge mints no replacement, so a poll answer drops `pairing` while the local countdown still showed time. | The QR block, the words and the computer code all clear, as in the expired row. One yellow line reads `phrase spent - press p for a new one`. The pane tells spent from expired by that drop arriving early, with no new phone in the list; it never mints a phrase itself, per `R-31-16-38`. |
| Error, invalid relay origin | `relay_origin` holds a value that `R-10-061` rejects, such as a `ws://` URL. | The bridge refuses to start and prints the `R-31-16-37` line; the pane itself shows the bridge-not-running state, per `R-10-066`. |
| Copied | `c` was pressed while a session was open, and the platform clipboard tool accepted the URI. | One yellow line reads `copied - paste it into the phone app with Paste from clipboard`. The pane keeps the credential block and the QR. |
| Copy failed | `c` was pressed while a session was open, and the platform clipboard tool failed. | One yellow line reads `copy failed: no clipboard tool found`, per `R-31-16-35`. The URI never prints in the message, per `R-31-16-36`. |
| Nothing to copy | `c` was pressed with no session open, or one whose phrase expired. | One yellow line reads `press p first - there is nothing to copy yet`. |
| A phone lost access | `d` was confirmed, so `R-13-053` removed that entry, or `r` was confirmed, so `R-13-056` cleared the list. | Every removed row is gone in the same redraw, and the notice line names what lost access. |
| Confirming | `d`, `r` or `s` was pressed. | A cleared screen with one `y/n` question. `y` confirms, and every other key cancels, including `q` and `esc`, per `R-31-16-32`. |
| Terminal too small | The pane rectangle is below the floor of `R-31-16-26`. | The terminal too small mock, and nothing else. |

## Navigation

- In: the plugin action `pair` on macOS and Linux, `pair-windows` on Windows. Both run the command
  of the `Opened by` field. A key binding in the Herdr `config.toml` opens the pane too.
- Out: `q` or `esc` closes the pane. Nothing else leaves it, because a popup pane owns the screen
  until it exits.
- The pane holds no sub screens. Every action completes in place or asks one `y/n` question.

## Rules

- **R-31-16-01** The pane MUST encode the pairing URI itself, with the `qrcode` crate that
  `docs/13-security-pairing.md` pins in `R-13-030`. It MUST NOT call an external encoder such as
  `qrencode`, which is absent on a stock Windows install and on many Linux images, and it MUST NOT
  ask the relay for a QR block, because the relay has no such endpoint.
- **R-31-16-02** The pane MUST compute the QR region from the encoder output, never from a fixed
  constant. A version `V` symbol is `4V + 17` modules on a side. The 4 module quiet zone on every
  side makes the region `4V + 25` columns wide, and one printed row carries two module rows, so the
  region is `4V + 25` divided by 2 and rounded up in printed rows. For the worked example URI that
  is version 8, 49 modules, 57 columns and 29 rows. A shorter phrase can drop the encoder to
  version 7, which is 53 columns and 27 rows, and a longer origin can raise it, so the pane MUST
  measure the region on every draw. The pane MUST render half block glyphs at two module rows per
  printed row. The `--once` test of `R-31-16-06` MUST decode the captured output and MUST compare
  the decoded bytes with the URI the pane encoded.
- **R-31-16-03** The pane MUST print the QR region only when the whole region fits the rectangle
  that `R-31-16-25` measures, quiet zone included. It MUST NOT clip a QR code and MUST NOT clip a
  quiet zone, because a clipped symbol scans as nothing and still looks like a working one. When
  the region does not fit, the pane MUST drop it whole, per `R-31-16-26`.
- **R-31-16-04** The pane MUST always print the relay origin, the computer code and the six words as
  text while a pairing session is open, in both layouts. The QR is a convenience, and the words are
  the credential.
- **R-31-16-05** The pane MUST hide the QR block, the six words and the computer code as soon as the
  pairing session ends, whether by a successful pair, by expiry, by the third failed handshake
  attempt (`R-13-023`), or by `q`.
- **R-31-16-06** The pane MUST support `--once`, which renders one pass and exits, exactly as
  `ui.sh` does at line 11 and line 261. That flag is how a test asserts the output without a
  terminal.
- **R-31-16-07** The pane MUST draw from a snapshot taken once, and MUST reload only after a write
  or after `f`. Moving the selection MUST cost no network call, which is the rule the reference
  states at `ui.sh` lines 66 to 72. The poll cadence of `R-31-16-41` is the one exception.
- **R-31-16-08** The pane MUST print a `loading...` line before a reload, so a slow relay never
  looks like a hang.
- **R-31-16-09** `d`, `r` and `s` MUST each ask a `y/n` question and MUST state the exact count of
  phones affected.
- **R-31-16-10** The pane MUST NOT print any pane content, any agent output, or any prompt text. It
  is a pairing and access surface only.
- **R-31-16-11** Colour MUST come from the eight basic ANSI colours plus bright black and reverse
  video, exactly as the reference does, and every one of them MUST be expressed as a
  terminal-relative value, per `R-32-700`. The pane MUST NOT emit 24 bit colour and MUST NOT use an
  indexed colour beyond those 16 slots, per `R-32-701`, because a Herdr popup pane must stay
  readable under any user terminal theme. The half block glyphs are drawn in the default foreground
  on the default background, so the QR inverts correctly under a light terminal theme as well as a
  dark one.
- **R-31-16-12** The Windows entrypoint MUST resolve its script through `HERDR_PLUGIN_ROOT` and MUST
  strip a leading `\\?\` prefix, because Herdr resolves a relative program against its own install
  directory on Windows. It MUST also set the console output to UTF-8, because the half block glyphs
  are not ASCII.
- **R-31-16-13** The pane MUST NOT print a numeric code of any kind as a pairing credential. The
  secret is six words, per `docs/13-security-pairing.md`.
- **R-31-16-14** The pane MUST NOT print an access level, a grant kind, or a read only marker beside
  a phone. Every paired phone has full control, per `docs/03-product-decisions.md`.
- **R-31-16-15** The pane MUST show at most one phone in the `connected` state, because the relay
  allows one active Device per Host, per `docs/11-relay-protocol.md`. The connected phone is not
  disturbed by a second phone that tries, per `R-30-943`, and this pane prints nothing about the
  attempt, per `R-31-16-22`.
- **R-31-16-16** The pane MUST NOT print a reconnect delay, a cap or an attempt total. It prints the
  current attempt number only, and `R-22-028` owns the schedule.
- **R-31-16-17** The pane MUST NOT hold a light variant, a dark variant, a theme setting or a
  brightness probe, per `R-32-702`. It MUST NOT print a hex value, and it MUST NOT take a value from
  the phone app's palette, per `R-32-703`. Selection MUST use reverse video rather than a colour
  pair, so it stays readable under every theme by construction.
- **R-31-16-18** The `Platform` column and the platform in the detail block MUST come from the
  `platform` and `os_version` fields of the stored paired-device record, per `R-13-049`. The pane
  MUST print them for a phone that is not connected, because they are stored, not live. It MUST NOT
  ask the phone for them: `device_info` arrives once per session, per `R-11-131`, so a live read
  would leave the column empty on every idle row.
- **R-31-16-19** A row state MUST be exactly one of three words. `connected` while the Host holds a
  live Noise session for that pairing. `idle` while it holds none and the relay link is up.
  `unknown` while the Host's own relay connection is down, because a phone reaches the Host only
  through the relay, so the Host cannot then tell an idle phone from a connected one. The pane MUST
  NOT print a fourth word, and MUST NOT print `revoked` as a row state, because `R-13-053` removes
  the entry and takes the row with it.
- **R-31-16-20** `N` in the title line MUST count the entries in the stored paired-device list, per
  `R-13-049`. It MUST NOT count connected phones, so it does not change when a phone connects, when
  a phone disconnects, or when the relay link drops.
- **R-31-16-21** The pane MUST print the link state word alone. R-10-064's `link` object carries
  no round trip, and the pane holds no relay connection it could measure one on (R-10-066): the
  `host_register` measurement this rule once described lived on a connection the pane no longer
  holds. The pane MUST NOT print a manufactured `ms` value, and MUST NOT send a WebSocket ping to
  obtain one, because `R-11-024` gives the keepalive to the relay.
- **R-31-16-22** The pane MUST NOT report an event the relay never tells it about. After
  `session_joined` the relay sends the Host no further text message, per `R-11-115`, so the pane
  MUST NOT print a notice for a phone the relay refused with `host_in_use`, and MUST NOT name a
  phone it has never held a session with. The relay refuses that phone directly, per `R-11-119`,
  and that phone shows the refusal itself, per `R-30-940`. Nobody may add a relay-to-Host notice
  frame to feed this line, because `R-12-003` keeps the relay a forwarder that carries no message
  of its own about a peer.
- **R-31-16-23** The pane MUST NOT offer to edit a phone's name. The name arrives in `device_info`,
  per `R-11-131`, and the next handshake would overwrite a local edit. A phone sets its own name on
  its own settings screen, per `R-31-15-12` in `docs/31-mockups/15-appearance.md`.
- **R-31-16-24** `s` MUST close this computer's own relay connection and nothing else. It MUST NOT
  stop the Herdr server and MUST NOT clear a pairing. `R-11-204` keeps `server.stop` away from a
  phone. `s` is a key pressed at the computer's own keyboard, so it is not a phone action, and the
  pane MUST NOT send it as a `host_action`.
- **R-31-16-25** The pane MUST derive every region from the rectangle that `Frame::area` returns,
  on every draw. It MUST split that rectangle with one `ratatui` `Layout`, with
  `Constraint::Length` for a region of known height and `Constraint::Min(0)` for the phone rows.
  `ratatui` solves those constraints with the Cassowary algorithm in its `kasuari` crate, and that
  solver returns an arbitrary near solution when a set of constraints cannot all hold. The pane
  MUST therefore reduce the region set to one that fits, by `R-31-16-26`, before it calls the
  solver. It MUST NOT compare the terminal size with a compiled constant, and MUST NOT clip a
  region.
- **R-31-16-26** When the regions do not fit, the pane MUST drop a whole region, in this order: the
  QR region first, the detail block second, the table header and its rows third. It MUST NOT drop
  the title, the relay line, the credential block of an open pairing session, or the footer. With
  every droppable region gone, the floor is 12 printed rows while a pairing session is open, 6 rows
  otherwise, and 28 columns in both cases. The pairing floor is 12, not 11, since the copy hint line
  of `R-31-16-34` joined the never-dropped credential block. Below the floor the pane MUST print
  the terminal too small state and nothing else.
- **R-31-16-27** The pane MUST print the credential block in the terminal default pair, and MUST
  NOT print any part of it in bright black. A person reads these three values off the screen and
  types them into a phone, so they are the one thing that MUST stay legible under every theme. The
  pane MUST NOT break the 22 character computer code, and MUST NOT break a word of the phrase. When
  a value does not fit beside its label, the pane MUST print that value on its own row at column 7,
  which is why the floor of `R-31-16-26` is 28 columns. When a value still does not fit on one row,
  the pane MUST wrap it at a space, MUST indent the continuation to the value column, and MUST NOT
  insert a hyphen or any other character at the break. The pane MUST NOT print a truncated address,
  code or phrase in any state.
- **R-31-16-28** A column budget counts display cells, not characters, and the pane MUST measure a
  value the same way, because one code point can occupy two cells, per `R-21-014` in
  `docs/21-terminal-rendering.md`. `device_name` holds up to 32 bytes, per `R-13-049`, so the 16
  cell `Phone` column elides often. A value wider than its budget MUST elide at its tail with one
  `…`, and the pane MUST measure that marker with the same width function, so the column keeps its
  budget exactly. When the five columns do not fit, the pane MUST drop a whole column from the
  right, in this order: `Last seen`, `Paired`, `Platform`. It MUST always print `Phone` and
  `State`.
- **R-31-16-29** The phone rows MUST scroll so the selected row is always drawn, because a selection
  a person cannot see is a selection they cannot check before they press `d`. When the pane draws no
  phone row, whether `R-31-16-26` dropped the table or the stored list is empty, `up`, `down` and
  `d` MUST do nothing. When the stored list is empty, `r` MUST do nothing as well. The pane MUST NOT
  hold a selection it does not draw.
- **R-31-16-30** The footer MUST stay one line, per `R-30-600`, and MUST NOT clip. It has three
  forms, and the pane MUST print the widest one that fits: the labelled form of the mocks at 80
  cells with `c copy`, then `p pair  c copy  d remove  r all  s stop  f reload  q quit` at 57
  cells, then the keys alone at 13 cells. While no pairing session is open the labelled form is 72
  cells and `c copy` is absent, per `R-31-16-34`. The footer MUST omit a binding that
  `R-31-16-29` made inert, and MUST NOT shorten a key.
- **R-31-16-31** On a `crossterm` `Event::Resize` the pane MUST redraw at once from the snapshot it
  already holds, and MUST NOT reload, because `R-31-16-07` gives a reload to a write or to `f`
  alone. It MUST measure the new rectangle per `R-31-16-25`, and MUST change layout in one redraw,
  so no frame mixes an old geometry with a new one. A resize during a `y/n` question MUST redraw
  that question and MUST NOT answer it.
- **R-31-16-32** While a `y/n` question is open, the question owns every key. `y` MUST confirm.
  `n`, `esc`, `q` and every other key MUST cancel. `q` MUST NOT quit the pane while a question is
  open, because a key that both cancels and quits leaves a person unsure which one happened. The
  question MUST print its two keys as `y/n`, and MUST wrap rather than clip, so the count of
  affected phones always reads.
- **R-31-16-33** Of the actions that the manifest in `docs/10-herdr-integration.md` declares for
  this plugin, two are destructive: `refresh`, titled `Revoke all phones`, and `stop`, titled `Stop
  the relay`. `pair` and `clients` are not. A surface that lists these actions MUST take the
  classification from this rule, and MUST NOT read an id as English: the id `refresh` revokes every
  phone, while the pane key `f` named reload only redraws the screen.
- **R-31-16-34** The pane MUST offer `c` to copy the full pairing URI, the exact string the QR
  encodes, while a pairing session is open. It MUST take the URI from the live session object, and
  MUST NOT rebuild it from the handle, the phrase and the origin, because a rebuild can drift from
  the value the QR encodes. It MUST print the hint line `press c to copy the pairing link` directly
  under the credential block in both pairing layouts, and MUST list `c copy` in the footer only
  while a session is open, per `R-31-16-30`. With no session open, or one whose phrase expired, `c`
  MUST set the notice `press p first - there is nothing to copy yet` and MUST NOT call the
  clipboard tool. On success the notice MUST read `copied - paste it into the phone app with Paste
  from clipboard`, because the phone app's manual pairing screen already carries a `Paste from
  clipboard` button that accepts the full pairing URI.
- **R-31-16-35** The pane MUST copy through the platform clipboard tool over stdin: `clip` on
  Windows, `pbcopy` on macOS, and on Linux the first found of `wl-copy`, then
  `xclip -selection clipboard`, then `xsel --clipboard --input`. Every child process MUST go
  through the crate's console window suppression, like every other child this plugin spawns. The
  pane MUST NOT copy through an OSC 52 escape sequence. This is a measured fact of this
  repository's own probe: the Herdr documentation index at `https://herdr.dev/llms.txt` lists
  mouse-select copy and a copied toast only, so OSC 52 passthrough is not a documented Herdr
  capability, and a popup pane that emits the escape could paste nothing into the user's
  clipboard while claiming a copy. When no tool exists, or the tool exits non-zero, the pane MUST
  report `copy failed: no clipboard tool found`, a fixed message that names no path.
- **R-31-16-36** The pane MUST NOT log or print the copied text anywhere but the pane's own
  credential block. No log line, no error message and no notice may carry the URI, the handle, the
  phrase or any part of them, because the copied value is the pairing secret itself. The clipboard
  failure message MUST be fixed and MUST NOT include any part of the input text.
- **R-31-16-37** The origin gate lives in the bridge, not the pane. When `relay_origin` holds a
  value that is not an absolute `http://` or `https://` origin, the bridge MUST refuse to start
  (R-10-061) and MUST print `relay_origin must be an http:// or https:// origin, for example
  http://192.168.1.20:8080 - set it in config.toml` as its exit line, because the phone app rejects
  a `ws://` or `wss://` origin outright. The pane MUST NOT hold a second validator and MUST NOT
  gate `p` on one: a bridge that refused to start reads as the bridge-not-running state of
  R-10-066, which is the surface a person fixes `config.toml` from.
- **R-31-16-38** The pane MUST take the pairing session, the link state and the device list from
  the bridge's `status` answer over the R-10-062 transport, and MUST NOT mint a handle, a phrase
  or a QR of its own (R-10-066). It encodes the QR from the answer's `uri` field (R-31-16-01) and
  MUST NOT rebuild the URI from parts (R-31-16-34).
- **R-31-16-39** While `pairing.registered` is false the pane MUST show `registering...` and MUST
  NOT show the URI, the handle, the words or a QR. R-10-064 keeps those fields null until the
  relay accepted the registration, so a phone that arrives first is never refused with
  `handle_unknown` for a handle the pane already shows (R-11-117).
- **R-31-16-40** `q` and `esc` MUST send `close_pairing` when a pairing is open before they quit
  the pane (R-10-066), and the pane MUST hide the credential in the same key press
  (R-31-16-05).
- **R-31-16-41** The pane MUST re-ask the bridge for `status` after every write and after `f`
  (R-31-16-07), and MUST also poll the bridge every 500 ms while a pairing is open and every 2 s
  otherwise, so the link state and `registered` track the bridge. The countdown needs no
  per-second reload: it counts down locally from the last answer's `expires_in_s`.
- **R-31-16-42** The `State` column's `connected` word MUST come from the row's own `connected`
  flag in the status answer (R-10-064), never from the pane's own guess. `R-31-16-15`'s one-row
  limit then holds by construction, because the flag reflects the bridge's one active session
  (R-10-069).

## Accessibility

This is a terminal interface on a workstation, so the phone rules do not apply to it. Two of them
still have a terminal equivalent, and the pane MUST honour both.

- Touch target: not applicable. There is no pointer. Every action has a single key, and the footer
  prints every key that still acts, per `R-31-16-30`, so no action is reachable only by a gesture.
  The narrowest footer prints the keys without their labels, which loses the labels and never a key.
- Contrast: the pane MUST NOT rely on colour alone to carry a state, which is the terminal form of
  `R-30-141`. Every state prints its word, `connected`, `idle` or `unknown`, and the colour only
  reinforces it. Under a monochrome terminal the pane loses nothing. The pane MUST NOT
  emit 24 bit colour, per `R-31-16-11`, so a user theme with a high contrast palette always wins.
- Screen reader: a terminal screen reader reads the buffer, so every value MUST be a word or a
  number and never a glyph on its own. The QR block is decoration for a camera, so the pane MUST
  print the words and the address as text beside it, per `R-31-16-04`, and a screen reader user
  pairs from those.
- Focus order: the pane has one selection, moved by `up` and `down`, and it MUST follow the printed
  row order. The row area MUST scroll to keep the selection drawn, and the pane MUST hold no
  selection when it draws no row, per `R-31-16-29`. The detail block MUST describe the selected row
  and MUST update in the same redraw as the selection, so what is spoken and what is highlighted
  never disagree.

## Open questions

None.

## Sources

- The `herdr-scheduled` plugin, `posix/ui.sh` - colours at lines 13 to 20, `read_key` at 44 to 63,
  `render` at 163 to 237, the key loop at 263 to 386, the `y/n` confirm at 301 to 304, `--once` at
  11 and 261.
- The `herdr-scheduled` plugin, `windows/ui.ps1` - `Show-Ui` at 69 to 144, the same header, column
  widths, status colours and footer.
- The `herdr-scheduled` plugin, `herdr-plugin.toml` - `[[panes]]` with `placement = "popup"`, and
  the reference plugin's own popup size of `width = "90%"` and `height = "80%"`, plus the Windows
  `HERDR_PLUGIN_ROOT` and verbatim prefix handling.
- `docs/32-design-language.md` - the popup pane colour rules `R-32-700` to `R-32-704`, which is the
  only part of the design language that applies to this surface.
- `docs/30-ux-spec.md` - the Host popup pane section, `R-30-601` on colour, `R-30-604` on local
  encoding, `R-30-900` for the worked example URI, `R-30-922` on showing the relay origin, and
  `R-30-943` on not disturbing the connected phone.
- `docs/10-herdr-integration.md` - `R-10-051`, the plugin config directory that holds `config.toml`,
  where the relay origin is set; `R-10-061`, the origin form the bridge enforces at load; and §7.7
  and §7.8 (`R-10-062` to `R-10-069`), the control transport and the serving model this pane is a
  client of.
- `https://herdr.dev/llms.txt` - the Herdr documentation index, probed from this repository. It
  lists mouse-select copy and a copied toast only, which is the measured basis of the OSC 52
  prohibition in `R-31-16-35`.
- `docs/11-relay-protocol.md` - the pairing URI form, its 512 byte limit, the QR encoding
  parameters, the registration exchange, the relay-owned keepalive, the error `host_in_use`, and the
  close codes.
- `docs/13-security-pairing.md` - the six word phrase, its 600 second lifetime, the routing handle,
  the stored paired-device record `R-13-049`, the revoke steps of `R-13-053`, and the key
  fingerprint format.
- `docs/03-product-decisions.md` - full control for every paired phone, and one active phone per
  computer.
- `docs/22-platform-integration.md` - `R-22-028`, the one reconnect schedule.
- `https://ratatui.rs/concepts/layout/` - the `Constraint` set and `Frame::area`.
- `https://docs.rs/ratatui/latest/ratatui/layout/index.html` - the Cassowary algorithm in the
  `kasuari` crate, and the arbitrary near solution that an unsatisfiable constraint set returns.
- `https://docs.rs/crossterm/latest/crossterm/event/enum.Event.html` - `Event::Resize`.
- `https://www.qrcode.com/en/about/version.html` and `https://www.qrcode.com/en/howto/code.html` -
  the module count of a QR version, and the 4 module quiet zone.
- `https://www.eff.org/files/2016/07/18/eff_large_wordlist.txt` - the word list of `R-13-017`,
  measured at 3 to 9 letters a word.
