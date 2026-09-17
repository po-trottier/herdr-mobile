# 03 - Pair by phrase, entered by hand

| Field | Value |
| --- | --- |
| Route | `/pair/manual` |
| Surface | Device, Android and iOS |
| Spec | `docs/30-ux-spec.md` |

This is the path for a phone with no working camera, a QR the pane could not draw, or a person who
prefers to read words aloud. It takes the same three values the QR carries, so it produces the same
pairing input record, per `R-30-901`.

## Wireframe

```text
+--------------------------------------+
| <  Pair by hand                      |
+--------------------------------------+
|                                      |
| The Relay pane on your computer      |
| shows an address, a computer code    |
| and six words.                       |
|        Paste from clipboard          |
| RELAY ADDRESS                        |
| [ https://relay.example.com        ] |
| COMPUTER CODE                        |
| [ n6Loxf94CfyIO6hOxlaHvA           ] |
| PHRASE                               |
| 1 [ remedy    ]   2 [ tapestry    ]  |
| 3 [ hubcap    ]   4 [ oversleep   ]  |
| 5 [ jailbird  ]   6 [ kinetic     ]  |
| +----------------------------------+ |
| |               Pair               | |
| +----------------------------------+ |
|                                      |
|       Scan the QR code instead       |
+--------------------------------------+

| [abacus] [abandon] [abide] [...]    | <- chips strip
+--------------------------------------+
|               [ keyboard ]          |
+--------------------------------------+
```

## Wireframe, while a computer is connected

The relay address is prefilled and read only once one computer is **saved**, per `R-31-03-10`. The
action block carries the switch caption of `R-30-945` once one computer is **connected**. A
connected computer is always a saved one, so the two changes arrive in that order. Only the two
blocks that change are drawn.

```text
+--------------------------------------+
| RELAY ADDRESS                        |
|   https://relay.example.com          |
| Change the relay address in Settings.|
+--------------------------------------+
| Pairing disconnects the computer you |
| are using now.                       |
|                                      |
| +----------------------------------+ |
| |               Pair               | |
| +----------------------------------+ |
|                                      |
|       Scan the QR code instead       |
+--------------------------------------+
```

## Callouts

1. The back chevron and `Pair by hand` title use the app bar anatomy.
2. The screen has one title, `Pair by hand`, in the app bar. The body starts with the
   description sentence; no eyebrow and no second title, so the screen carries one heading
   size. The ground grid uses `R-32-332` behind the screen body.
3. The shared text button shows `Paste from clipboard`, as written (amended 2026-09-09, per
   `R-03-104`: was `PASTE FROM CLIPBOARD`). It keeps the behavior from `R-31-03-12`.
4. Each group header is the upper-case tier of `R-32-563`: the label alone in `type.micro`,
   with no rule beside or under it. Decided 2026-09-03 by the product owner. The header carries
   the screen edge inset of `R-30-230` itself, and every block under it takes that same inset,
   so a label and its field share one left edge (amended 2026-09-08 by the product owner: the
   headers sat one inset further in than the fields).
5. The relay address field is the text field of `docs/32-design-language.md` section 7.10:
   `color.bg.high`, `border.hairline` in `color.border.strong`, and `radius.sm`. Focus uses
   `border.focus` in `color.accent.text`. Error uses `border.error`. Once a computer is saved,
   per `R-31-03-10`, the address is a value and not a control: plain `type.mono.phrase` text in
   the field's slot with no box, announced read only, as the second wireframe draws it (amended
   2026-09-08 by the product owner: the fill and the focus colour restated the table with other
   values, and a boxed read-only field invited the tap its caption refuses).
6. The computer code field uses the same field anatomy. Its text, the relay address text and
   the six words all use `type.mono.phrase`, so every input on this screen has one size. The
   number beside each word field uses `type.micro`, the same size as the group headers, and sits
   `space.1` before its field, per section 7.11 of `docs/32-design-language.md`.
7. The six word fields keep two fields per row, `space.3` apart, per section 7.11 of
   `docs/32-design-language.md`. They use the same border states and `type.mono.phrase`
   (amended 2026-09-08 by the product owner: the gap was `space.4`).
8. Each autocomplete suggestion is a chip in the bottom strip above the keyboard. It uses
   `color.bg.high`, a 1 px `color.border.strong` border, `radius.sm`, and `type.mono.phrase`. A
   chip is `size.row.one_line` high, so it is its own touch target, and presses per the first
   case of `R-32-501` (amended 2026-09-08 by the product owner: the chips were 40 high inside a
   68 strip and had no pressed state).
9. The switch caption keeps the exact sentence from `R-30-945`. It appears only while a
   computer is connected.
10. The shared primary button shows `Pair`. The shared text button shows
    `Scan the QR code instead`. Both are the platform's own label style of `R-32-212`, as written
    (amended 2026-09-09 by the product owner, per `R-03-104`: until then `type.mono.button` with
    widget-applied upper case).

## Wireframe, Connecting

The bottom actions use the panel of `R-31-02-14`. The form stays visible but read only.

```text
+--------------------------------------+
| -- CONNECTING                        |
| Connecting to 172.16.188.73:8080...    |
| [ platform activity indicator ]      |
|               Cancel                 |
+--------------------------------------+
```

## States

| State | Trigger | Screen shows |
| --- | --- | --- |
| Default, first pairing | The route opens, nothing is saved and nothing is connected. | The first wireframe. The relay address field holds the focus and is editable. `Pair` is disabled. The keyboard is up. No switch caption, per `R-30-945`. |
| Default, a computer is saved | The route opens with at least one computer saved and none connected. | The address field is prefilled and read only, per `R-31-03-10`, with one caption under it: `Change the relay address in Settings.` The computer code field holds the focus instead. Still no switch caption. |
| Default, a computer is connected | The route opens with one computer connected. | The second wireframe: the read-only address block, and the switch caption of `R-30-945` above `Pair`. |
| Link | A valid pairing link opens the app, cold or warm. | The relay address, computer code and six words come from the link. Every field stays editable, per `R-31-03-14`. The switch caption appears only while a computer is connected. No pairing starts. |
| Loading | `Pair` was pressed. | The panel of `R-31-02-14` replaces the bottom actions. Every field is read only. Show the relay host, platform activity indicator, and enabled `Cancel`. |
| Cancelled | The person pressed `Cancel`. | Close the attempt and use the outcome of `R-31-02-14`. Keep all entered fields when this screen remains open. |
| Empty | Nothing is entered. | Each word field shows its number and a dash placeholder in `color.fg.disabled`. |
| Error, one word | A word is not in the list. Code `phrase_word_unknown`. | That field takes `border.error`, per `R-32-504`. One line reads `Word 3 is not in the list. Check it against your computer.` The number is exact. The other five words stay. Haptic `haptic.error`. |
| Error, word count | The pasted phrase split into a number other than six. Code `phrase_word_count`. | One line reads `A phrase holds six words. You entered four.` The count is exact. The fields fill as far as the paste reached. |
| Error, separators | The paste held an empty word, a repeated hyphen, or inner whitespace. Code `phrase_separator`. | One line reads `Use one space or one hyphen between words.` |
| Error, case | A character survived normalisation and is not lower case ASCII. Code `phrase_case`. | One line reads `A phrase holds lower case letters only.` |
| Error, address | The address is not an origin, or carries a path. Code `relay_origin_invalid`. | The address field takes the error border and one line reads `That is not a relay address. Use the form https://relay.example.com.` |
| Error, address not encrypted | The address is cleartext and outside the permitted list. Code `relay_origin_insecure`. | One line reads `A relay address must start with https, unless the computer is on your own network.` `Pair` stays disabled. |
| Error, computer code | The code does not match the handle form of `R-11-112`. Code `handle_malformed`. | That field takes the error border and one line reads `That computer address is malformed. Read the code again.` |
| Error, phrase used up | Three failed handshakes used that phrase. Code `phrase_attempts`. | One line reads `Three tries used. The computer made a new phrase. Read it again.` The six word fields clear. The address and the code stay, because both survive a new phrase. Each attempt runs after the disconnect, so `R-31-02-08` decides where the person lands. |
| Error, expired | The handshake reported expiry after `Pair` was pressed. Code `phrase_expired`. | One line reads the `phrase_expired` sentence from the pairing error text table in `docs/30-ux-spec.md`. `R-31-02-08` decides where the person lands, because the disconnect has already run. |
| Error, host in use | Another phone already holds that computer. Error `host_in_use`, close code `4006`. | `R-31-02-08` decides. When this screen keeps it, the name-free banner appears above the primary action and `Pair` becomes `Try again`. |
| Error, link failed | The relay connection or handshake failed after `Pair`. | `R-31-02-08` decides the destination. This screen uses `Could not reach <host>: <reason>.` for transport failures, per `R-31-02-15`. Protocol errors keep their existing sentences. Keep every field and enable `Try again`. |
| Offline | No route to the relay. | `Pair` is disabled, so no switch starts and the connected computer stays connected, per `R-30-947`. A strip reads `No network. Pairing needs a connection, and a phrase lasts ten minutes.` with `treat.warning`. Every field the person may edit stays editable (amended 2026-09-08 by the product owner: the lifetime is the 600 seconds of `R-13-022`). |

## Navigation

- In: `/welcome` secondary action, or the `type it in` action on `/pair/scan`.
- In, link: `herdr-remote://pair` opens this route with the link values, per `R-03-073`.
  Cold and warm delivery use the same screen. A new link refills an open screen without
  adding another route, per `R-22-034`.
- Before pairing from a link: if a computer is connected, `Pair` opens the native confirmation
  dialog of `R-30-958`. Its title is `Switch computers?`.
  Its body is `This disconnects the computer you are using now. It stays paired.`
  `Disconnect and pair` closes the current connection before the handshake starts.
  The action has no destructive style. The platform cancel action leaves the connection and fields unchanged.
- Out, success: `/hosts/:hostId/agents` for the computer just paired, mockup `06-agent-list.md`.
  That computer is the connected one, per `R-30-945`, which is what makes a per-Host route legal
  under `R-30-946`.
- Out, alternative: `/pair/scan`, mockup `02-pair-scan.md`.
- Out, failure after the disconnect: `/hosts`, mockup `05-host-list.md`, when a computer was
  connected. `R-30-947` owns that landing state. When nothing was connected the screen stays, per
  `R-31-02-08`.
- Out, back: the previous route.

## Rules

- **R-31-03-01** The six word fields MUST raise a plain ASCII text keyboard with autocorrect,
  autocapitalisation, predictive text and smart punctuation all off, per `R-30-905`. No field on
  this screen may raise a digit keypad, per `R-30-902`.
- **R-31-03-02** The focus MUST advance to the next word field when the person accepts an
  autocomplete suggestion, and MUST move back on a backspace in an empty field.
- **R-31-03-03** A paste into any word field MUST be normalised before it is validated, and a pasted
  value that splits into more than one word MUST fill the six fields from word 1, whichever field
  received it, per `R-30-907`, which also fixes which separators normalise. `R-31-03-12` gives this
  screen a second paste path, a general action that reads the clipboard directly rather than
  waiting for a paste gesture inside one field.
- **R-31-03-04** `Pair` MUST stay disabled until three conditions hold together: the address is a
  valid origin per `R-30-921`, the computer code matches the handle form of `R-11-112`, and all six
  word fields hold a list word per `R-30-908`. `R-30-908` also forbids an automatic submit when the
  sixth word lands, so the person always presses `Pair`.
- **R-31-03-06** After a failed handshake the screen MUST show the one sentence the pairing error
  text table of `docs/30-ux-spec.md` gives for that code, and nothing more. It MUST NOT show a
  tries-left counter. `docs/13-security-pairing.md` owns the attempt limit, and that table owns no
  sentence for a partial count, so a counter would have to invent one, which `R-31-03-07` forbids.
- **R-31-03-07** Every failure the pairing error text table of `docs/30-ux-spec.md` names MUST map
  to exactly one sentence from that table. This screen MUST NOT invent a message and MUST NOT
  print an error code. The one failure that table does not name is the link failure of
  `R-31-03-13`, whose sentence this file's states table fixes.
- **R-31-03-08** A failure MUST keep every field the person filled and MUST focus the field that
  failed, per `R-30-910`. Clearing six words because one is wrong is the fastest way to make a
  person give up.
- **R-31-03-09** Pressing `Pair` MUST disconnect the connected computer before the pairing handshake
  starts, in the order `R-30-945` fixes for both pairing screens and `R-31-02-10` states for the
  scan path. That disconnect is the switch of `R-03-044`, so it keeps every pairing and every Device
  key. Typed pairing MUST NOT raise a confirmation; link pairing uses `R-31-03-14`.
  `R-30-947` owns the landing state after a failed switch,
  including the prohibition on dialling the computer the person left.
- **R-31-03-10** On the by-hand path, once one computer is saved, the relay address field MUST
  be prefilled with the stored origin and MUST be read only.
  `R-30-927` forbids the app changing the origin on its own and
  `R-30-924` makes a change destructive and owned by `/settings`, so a second origin cannot be typed
  here. This removes on the by-hand path the conflict that `R-31-02-11` must refuse on the scan
  path, because a camera cannot be prefilled.
- **R-31-03-11** This screen MUST NOT show a countdown, an expiry clock, or any remaining-time
  wording. Manual entry holds an origin, a computer code and a phrase, and no message delivers the
  expiry before `Pair` is pressed. The app learns expiry only from the failure the pairing error
  text table names `phrase_expired`, which `R-11-120` answers with close code `4000` after the
  Device joins. A screen MUST NOT draw a value that no message carries, so this screen reports an
  expiry and never predicts one. `02-pair-scan.md` shows the same failure the same way.
- **R-31-03-12** Callout 3, `Paste from clipboard`, MUST read the clipboard once per tap and fill
  whichever fields it recognises, trying the richest shape first: a `herdr-remote://pair` URI
  (`R-11-140`) fills the relay address, the computer code and all six words in one action; failing
  that, a value that splits into more than one recognisable word fills the six word fields exactly
  as `R-31-03-03` fixes for a paste landing directly in a word field; failing that, a single token
  matching the handle form of `R-11-112` fills the computer code alone. A clipboard value that
  matches none of the three shapes, or an empty clipboard, MUST leave every field unchanged: this
  screen MUST NOT invent an error for a clipboard the person did not mean for it.
- **R-31-03-13** Failures outside the pairing error text table MUST use the shared sentence builder
  of `R-31-02-15`.
  The `Error, link failed` state MUST keep the fields and enable `Try again`.
  A failure that never reached the computer MUST NOT report used phrase attempts.

- **R-31-03-14** A pairing link MUST fill the relay address, computer code and all six words,
  per `R-03-073`. These fields MUST stay editable, including the relay address when a computer
  is saved, per `R-30-958`. The screen MUST NOT press `Pair` automatically.
  If a computer is connected when the person presses `Pair`, the screen MUST first show
  the confirmation in `R-30-958`. Cancellation MUST NOT disconnect or start a handshake.
  Confirmation MUST close the current connection before the handshake starts, per `R-30-945`.
  This exception to `R-31-03-10` MUST NOT change the stored origin automatically, per `R-30-927`.
- **R-31-03-15** When the viewport above the keyboard cannot hold the app bar and one full field,
  the app bar MUST scroll with the content, so the focused field stays fully visible, per
  `R-30-519`. On a viewport that holds both, nothing changes. The app bar MUST NOT be removed,
  collapsed or hidden by any other means, and the back control MUST return with one scroll.
  Rotation and a change to the keyboard inset MUST keep the whole focused field visible above
  the pinned actions. Every entered value and the current field focus MUST survive rotation.
  The compact action row uses the allocation in `docs/32-design-language.md` section 7.11.
- **R-31-03-16** On iOS, a finger drag on the form MUST dismiss the keyboard and release field
  focus, so the person can scroll back to the navigation bar. A scroll that the screen performs
  to reveal a field MUST preserve focus. Both paths MUST preserve every entered value.
- **R-31-03-17** The connecting panel MUST scroll when it exceeds the available height, including
  while the keyboard closes after `Pair`. `Cancel` MUST remain reachable at the maximum text
  scale of `R-30-701` and MUST keep the cancellation behaviour of `R-31-02-14`.

## Retired rules

This row retires one rule id. The id stays reserved, so an old citation still resolves.

| Rule | Disposition |
| --- | --- |
| `R-31-03-05` | Retired. It required the countdown to run from the expiry the Host reports, which is the right requirement for a countdown this screen can no longer draw. No message delivers that expiry before `Pair`, so the rule described a display with no data source. `R-31-03-11` now forbids the countdown, and `docs/30-ux-spec.md` owns `R-30-911`. |

## Accessibility

- Touch target: every field and every action, including `Paste from clipboard`, meets the minimum
  target of `R-30-290` and `R-30-740`, at the heights `R-32-350` fixes. Two adjacent word fields are
  separated by more than `space.1`, per `R-30-292`.
- Contrast: `type.mono.phrase` renders in `color.fg.primary` on `color.bg.high` in every field,
  which `R-32-121` makes the only permitted ink there, and the placeholder uses `color.fg.disabled`,
  which `R-30-120` permits for a placeholder only. Both pairs have a row in `R-32-150`, per
  `R-30-720`.
- Screen reader: each word field MUST carry the label `Pairing word <n> of six`, per `R-30-912`. The
  address field MUST carry `Relay address` and the code field `Computer code`. A read-only address
  field, per `R-31-03-10`, MUST also be announced as read only. Every failure MUST announce its
  sentence once, per `R-30-742` and `R-30-912`.
- Focus order: per `R-30-719`, back chevron, title, instruction, `Paste from clipboard`, relay
  address, computer code, word 1 to word 6 in order, the switch caption when it is present, `Pair`,
  then `Scan the QR code instead`. The word fields MUST be traversed in numeric order even though
  they are drawn two to a row, because the order is part of the secret.
- Keyboard and text scale: this screen raises the software keyboard as it opens, and eight fields
  sit under it. The inset behaviour, the scroll that keeps the focused field visible above the
  autocomplete strip, and the reflow of the two-column word grid at the scale `R-30-700` and
  `R-30-701` fix are the ones `R-30-519` owns. This screen MUST NOT state a different behaviour,
  and MUST NOT hold the word grid at two columns when the reflow of `R-30-519` calls for one.

## Open questions

None.

## Sources

- `docs/31-mockups/02-pair-scan.md` — connecting panel and cancellation `R-31-02-14`; failure
  sentences `R-31-02-15`.

- `docs/32-design-language.md` - the app bar `R-32-510`, the text field `R-32-530`, the six word
  phrase field `R-32-531` and `R-32-532`, the interaction states `R-32-503` and `R-32-504`, the
  section header size in `R-32-350`, and the contrast table `R-32-150`.
- `docs/30-ux-spec.md` - the six word field rules `R-30-903` to `R-30-912`, the pairing error text
  table, the numeric-code prohibition `R-30-902`, the origin rules `R-30-921`, `R-30-924` and
  `R-30-927`, the pairing switch `R-30-945`, the per-Host route rule `R-30-946`, the failed
  switch `R-30-947`, the keyboard inset and text-scale behaviour `R-30-519`, the text scale
  `R-30-700` and `R-30-701`, and the announcement rule `R-30-742`.
- `docs/11-relay-protocol.md` - the pairing error codes, the routing handle `R-11-112`, the
  plaintext `host_in_use` error `R-11-119`, the expired pairing window `R-11-120`, the pairing URI
  form `R-11-140`, and the close codes `4000` and `4006`.
- `docs/13-security-pairing.md` - the six word phrase, its 600 second lifetime (`R-13-022`), the
  three attempt limit, and the word list normalisation.
- `docs/03-product-decisions.md` - the saved-computer policy `R-03-043` and the switch rule
  `R-03-044`.
