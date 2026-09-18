# 32 - Design language

This document owns every visual value in the phone app: every colour, every type step, every spacing
step, every radius, every elevation, every border width, every opacity, every size, every icon name,
every text glyph the chrome draws in place of an icon, every duration and every easing curve. It
also owns the anatomy of every component, so an implementer can build any screen without a
judgement call. `docs/30-ux-spec.md` owns the screens, the flows, the interaction model, the states
and the accessibility behaviour, and it cites this document for values.
`docs/21-terminal-rendering.md` owns the terminal emulator, the monospace family and the terminal
line-height ratio. `docs/33-platform-chrome.md` owns how a chrome token **resolves** on each
platform and which native control carries a role. This document cites those owners and never
restates them.

Every ratio in this document was computed from a fixed hex value with the WCAG 2.2 relative
luminance formula and is stated to two decimals. No value here is approximate, and no value here is
left to the reader. Section 3.7 states which values that method proves and which values it cannot
reach, because a platform resolves some chrome colours at run time.

## 1. Purpose and ownership

- **R-32-001** This document MUST hold every visual value the app uses. A value MUST NOT be defined
  in two documents. A second definition is a defect, even when the two agree today. One boundary
  exists, and it is not a second definition: this document owns the **token**, and
  `docs/33-platform-chrome.md` owns how a chrome token **resolves** on each platform and which
  native control carries a role. So a reader who wants a number, a hex value, an icon name or a
  component anatomy opens this document, and a reader who wants the platform behaviour of a token
  opens `docs/33`. A token name is the same on both platforms, so a mockup never changes a token
  reference to reach a platform.
- **R-32-002** `docs/30-ux-spec.md` MUST NOT hold a hex value, a type size, a spacing number or an
  icon name. It cites a rule here instead.
- **R-32-003** `docs/21-terminal-rendering.md` owns the terminal emulator, the monospace font family
  in `R-21-011` and the terminal line-height ratio in `R-21-010`. This document MUST NOT restate
  either.
- **R-32-004** A file in `docs/31-mockups/` MUST cite a rule here instead of printing a value. A
  mockup keeps its ASCII wireframe, its callouts, its states and its rules, and it names tokens, not
  numbers.
- **R-32-005** A widget MUST take every value from a token, per `R-30-102`. A new value MUST be
  added here as a token first and used second, per `R-30-103`.

## 2. Themes

| Mode | Brand name | Brightness |
| --- | --- | --- |
| dark | Ink | `Brightness.dark` |
| light | Paper | `Brightness.light` |

- **R-32-010** The app MUST offer exactly these two themes, and `System` MUST be the default mode
  that follows the operating-system setting. `R-31-15-05` owns the control that sets them.
- **R-32-011** Every token in this document MUST hold a value for both themes. A token with a value
  in one theme only is a defect, and a review MUST reject it.
- **R-32-012** Both themes use the same fixed Herdr palette. Neither theme is derived from the other
  at run time. The app MUST NOT produce either theme by inverting, lightening or otherwise
  transforming the other theme at run time — each theme is a separately authored source value, not a
  derivation. Both themes are first class. The same holds for the generated chrome scheme:
  `ChromeScheme.fixed(Brightness)` builds one `ColorScheme` per theme from the tokens below.
- **R-32-013** The app MUST follow the operating-system setting without a restart. The chrome
  follows `MaterialApp.themeMode`, which `R-22-051` maps from the three modes of `R-32-010`. The
  root MUST override `MediaQuery.platformBrightness` below `MaterialApp` with the resolved theme's
  brightness, so the terminal widget and every `AppColor.of(context)` reader, which read
  `MediaQuery.platformBrightnessOf(context)`, agree with the chrome in a forced `Light` or `Dark`
  mode as well as in `System`.
- **R-32-014** The app MUST NOT offer an **in-app** palette picker. The terminal palette is never a
  choice. One terminal palette, two themes, one chrome palette.
- **R-32-015** On a brightness change the app MUST act in this order: apply the new chrome, apply
  the new terminal slot set of `R-32-140`, then force one full `pane.read` and repaint the grid from
  that payload. It MUST NOT recolour the grid in place. A painted cell that came from `38;2` holds
  an absolute colour that MUST NOT move, per `R-30-153`, while a slot-indexed cell would move, so a
  recolour in place produces a frame that is half light and half dark. That frame MUST NOT be a
  reachable state.
- **R-32-016** While that read is in flight the app MUST keep the last painted grid, per
  `R-31-08-05`, MUST NOT blank it and MUST NOT animate the swap, per `R-30-272`. If the read fails,
  the app MUST keep the old grid with the old palette and show the offline strip.
- **R-32-017** The app MUST NOT use pure black or pure white for a **Selenized-sourced** value —
  terminal or semantic-state, per `R-32-100` — per `R-30-111`. Neither Selenized variant supplies
  one, and the two values this document takes from outside those variants, named in `R-32-101`,
  are not pure either. That reason reaches the terminal and semantic-state classes only, and it
  does not reach chrome: `color.bg.base` light is the Paper ground `#efece5`, per section 3.2, not
  an invented one, and using a real source value as-is is the thing `R-32-100` requires, not the
  thing this rule forbids.

## 3. Colour

### 3.1 The Selenized source values (terminal and semantic state only)

Licence: MIT, Copyright (c) 2021 Jan Warchoł,
`https://github.com/jan-warchol/selenized/blob/master/LICENSE.txt`. Values:
`https://github.com/jan-warchol/selenized/blob/master/the-values.md`. Terminal slot mapping:
`https://github.com/jan-warchol/selenized/blob/master/manual-installation.md`. The CIE Lab
coordinates are canonical in that repository and the sRGB values below are the published derivation.

| Selenized name | Selenized dark | Selenized light |
| --- | --- | --- |
| `bg_0` | `#103c48` | `#fbf3db` |
| `bg_1` | `#184956` | `#ece3cc` |
| `bg_2` | `#2d5b69` | `#d5cdb6` |
| `dim_0` | `#72898f` | `#909995` |
| `fg_0` | `#adbcbc` | `#53676d` |
| `fg_1` | `#cad8d9` | `#3a4d53` |
| `red` | `#fa5750` | `#d2212d` |
| `green` | `#75b938` | `#489100` |
| `yellow` | `#dbb32d` | `#ad8900` |
| `blue` | `#4695f7` | `#0072d4` |
| `magenta` | `#f275be` | `#ca4898` |
| `cyan` | `#41c7b9` | `#009c8f` |
| `orange` | `#ed8649` | `#c25d1e` |
| `violet` | `#af88eb` | `#8762c6` |
| `br_red` | `#ff665c` | `#cc1729` |
| `br_green` | `#84c747` | `#428b00` |
| `br_yellow` | `#ebc13d` | `#a78300` |
| `br_blue` | `#58a3ff` | `#006dce` |
| `br_magenta` | `#ff84cd` | `#c44392` |
| `br_cyan` | `#53d6c7` | `#00978a` |
| `br_orange` | `#fd9456` | `#bc5819` |
| `br_violet` | `#bd96fa` | `#825dc0` |

- **R-32-100** Every **terminal** and **semantic-state** colour value (section 3.4, section 3.5)
  MUST be one of the Selenized values above, or one of the two values `R-32-101` names. Terminal
  and semantic-state values MUST NOT invent a hex value, tint one, or compute one at run time.
  **Chrome** colour values (section 3.2, section 3.3) draw from a separate source, section 3.1b below,
  per `R-32-584`'s existing class split: chrome and terminal were always two classes that
  happened to share one source; this rule ends the coincidence, not the split.
- **R-32-101** Two values come from the **Selenized black** variant of the same source file, because
  neither Selenized dark nor Selenized light supplies a near-neutral dark: `#181818`, the `bg_0` of
  Selenized black, is `color.fg.on_accent` in the dark theme and `color.shadow` in both themes. No
  other value from another variant is permitted. Both remain valid unchanged: `#181818` measures
  8.81 against the new `color.accent.primary` dark fill and 5.41 against the new light fill, both
  above the 4.5 text floor `R-32-125`'s label needs, so neither value needed to move when chrome
  moved to the Herdr brand source.
- **R-32-102** `violet`, `br_violet`, `orange` and `br_orange` have no ANSI slot. `orange` serves
  `color.status.warning` and `color.status.blocked`. `violet` and `br_violet` are unused: they
  served the chrome accent in an earlier revision (`R-32-128`, `R-32-129`, retired below) and MUST
  NOT be reintroduced there, because chrome no longer draws from this table. A future terminal or
  semantic-state use remains open and MUST NOT be introduced without a contrast row in `R-32-150`.

### 3.1b The Herdr brand source values (chrome and semantic state)

Licence: MIT, Copyright (c) 2024 Herdr Project,
`https://herdr.dev/css/site.css` (brand values for `html[data-mode="ink"]` and
`html[data-mode="paper"]`) and `https://herdr.dev/css/style.css` (legacy tokens for
`[data-palette="herdr"]` and `:root`). The app's own darkened Paper variants for `accent.text`,
`border.strong`, `status.working`, `status.idle`, `status.done`, `status.unknown` are this
document's measurements, not from the stylesheets.

| Token | Brand name | Ink (dark) | Paper (light) | Role |
| --- | --- | --- | --- | --- |
| `color.bg.base` | `--bg` | `#17171a` | `#efece5` | page ground |
| `color.bg.raised` | `--panel` | `#1e1e22` | `#e7e3da` | card, sheet, strip, banner, app bar on scroll |
| `color.bg.high` | `--mass` | `#26262b` | `#ddd8cc` | fill only: text field, jump pill, off switch track (the key cap left this row on 2026-09-09, per `R-03-059`: an outlined button has no fill) |
| `color.bg.grid` | `--grid` | `#202024` | `#e4e0d6` | the ground grid lines (section 5). Decorative, contrast-exempt |
| `color.border.subtle` | `--line2` | `#35353d` | `#cbc5b6` | card and panel boundary, divider. Decorative, no floor |
| `color.border.strong` | `--faint2` in Ink; a darkened `--faint` in Paper | `#908f96` | `#6f6b5c` | boundary of a control identified by shape only. MUST clear 3.0 on all three surfaces |
| `color.fg.primary` | `--ink` | `#eae8ee` | `#15140f` | primary ink |
| `color.fg.secondary` | `--faint` / `--dim` | `#b0afb6` | `#55534a` | secondary ink; clears 4.5 on all three surfaces |
| `color.fg.disabled` | `--faint2` | `#908f96` | `#928e79` | disabled control, placeholder only |
| `color.accent.primary` | `--spot` | `#cba6f7` | `#8839ef` | a fill, never an ink. The one accent |
| `color.accent.text` | `--spot`, paper darkened | `#cba6f7` | `#7028d8` | accent ink; clears 4.5 on all three surfaces in both themes |
| `color.fg.on_accent` | `--spot-ink` | `#17171a` | `#ffffff` | label on `accent.primary` only |
| `color.accent.soft` | `--accent-soft` | `accent.primary` at 10% alpha | same | selected-row wash, pressed ghost fill, chip fill, the unread notification row wash (2026-09-09, `docs/31-mockups/07-notifications.md` callout 8, beside the `border.attention` bar in `color.accent.primary` of section 7.4). Decorative, contrast-exempt |
| `color.shadow` | Selenized black `bg_0`, kept per `R-32-101` | `#181818` | `#181818` | elevation shadow |

Why paper `accent.text` is `#7028d8` and not the spot: `#8839ef` measures about 4.2 on
`bg.raised` and 3.8 on `bg.high`, below the 4.5 text floor `R-32-125`'s label needs; the darkened
value clears all three.

Why paper `border.strong` is `#6f6b5c`: the brand `--faint2` `#928e79` measures about 2.7 on
`bg.high`; `#6f6b5c` clears 3.0 on all three surfaces.

- **R-32-103** Every **chrome** colour value (section 3.2, section 3.3) MUST be one of the values
  above, or one of the two `R-32-101` values where this document states so explicitly. The app MUST
  NOT invent a hex value, tint one, or compute one at run time, matching `R-32-100`'s own bar for
  the other two classes.
- **R-32-104** Chrome and terminal are independent. `color.bg.base` and `color.term.bg` share no
  value in either theme, and the app MUST NOT infer one from the other. `R-32-584` requires the
  terminal grid to read `color.term.bg` and never `color.bg.base`; because the two values differ in
  both themes, a grid that reads the wrong token is visible on inspection, not only by discipline.

### 3.2 App chrome: surfaces and borders

| Token | Brand name | Dark | Light | On | Dark | Light | Role |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `color.bg.base` | `--bg` | `#17171a` | `#efece5` | - | - | - | The page background. The terminal keeps its own `color.term.bg`, per `R-32-104`. |
| `color.bg.raised` | `--panel` | `#1e1e22` | `#e7e3da` | `bg.base` | 1.09 | 1.06 | A strip, a banner, a sheet, a dialog, a key row, a snackbar. |
| `color.bg.high` | `--mass` | `#26262b` | `#ddd8cc` | `bg.base` | 1.27 | 1.12 | Fill only: a text field, the jump pill, a switch track that is off. The key cap left this row on 2026-09-09, per `R-03-059`. |
| `color.bg.grid` | `--grid` | `#202024` | `#e4e0d6` | `bg.base` | 1.05 | 1.04 | Ground grid lines only. Decorative, contrast-exempt. |
| `color.border.strong` | `--faint2` / darkened `--faint` | `#908f96` | `#6f6b5c` | `bg.base` | **5.58** | **4.53** | The boundary of any control whose shape is its only identifier. |
| `color.border.strong` | `--faint2` / darkened `--faint` | `#908f96` | `#6f6b5c` | `bg.raised` | **5.19** | **4.17** | The same token measured on the second surface. |
| `color.border.strong` | `--faint2` / darkened `--faint` | `#908f96` | `#6f6b5c` | `bg.high` | **4.70** | **3.75** | The same token measured on the third surface, per `R-32-112`. |
| `color.border.subtle` | `--line2` | `#35353d` | `#cbc5b6` | `bg.base` | 1.27 | 1.12 | A decorative divider only. |
| `color.shadow` | Selenized black `bg_0` | `#181818` | `#181818` | - | - | - | The shadow colour of `elev.2` and `elev.3`, at the alphas in `R-32-320`. Unchanged: `R-32-101`. |

- **R-32-110** The table above is normative. A surface or a line MUST use one of these tokens.
- **R-32-111** A raised surface MUST NOT rely on its own step against `color.bg.base` to be seen.
  That step measures 1.09 in dark and 1.06 in light, which is invisible in both themes. Separation
  MUST come from `color.border.strong`.
- **R-32-112** `color.bg.high` is a fill only. Any control filled with it MUST also carry a
  `color.border.strong` boundary, because 1.27 in dark and 1.12 in light cannot identify a component
  under WCAG 2.2 success criterion 1.4.11.
- **R-32-113** `color.border.strong` MUST be the boundary of a text field, a key cap, a floating
  action bar, the jump pill, a switch track that is off, a segmented control, a raw-error block and
  the app bar bottom edge. It clears the 3.0 indicator floor on every surface in both themes.
- **R-32-114** `color.border.subtle` is permitted only for a divider between list rows that their
  own text already identifies, and for the edge of a container that its own contents already
  identify: the card of `R-32-593` and the space block of `R-32-595` (added 2026-09-04 by the
  product owner's hierarchy decision). It MUST NOT be the only boundary of a control. Success
  criterion 1.4.11 does not reach a line that identifies nothing, which is why this token is
  permitted here and nowhere else.
- **R-32-115** The app bar MUST be `color.bg.base` with a 1 wide `color.border.strong` bottom edge.
  It MUST NOT be `color.bg.raised` with no edge. A step of 1.09 in dark and 1.06 in light is
  invisible in both themes.
- **R-32-116** The single token `color.border` is **retired**. Every former use resolves to
  `color.border.strong` when it identifies a control and to `color.border.subtle` when it divides
  two rows. A document that still names `color.border` is wrong.

### 3.3 App chrome: text and accent

| Token | Brand name | Dark | Light | On `bg.base` | On `bg.raised` | On `bg.high` | Permitted on |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `color.fg.primary` | `--ink` | `#eae8ee` | `#15140f` | **14.72** / **15.63** | **13.67** / **14.40** | **12.39** / **12.97** | all three surfaces |
| `color.fg.secondary` | `--faint` / `--dim` | `#b0afb6` | `#55534a` | **8.22** / **6.54** | **7.64** / **6.02** | **6.92** / **5.42** | all three surfaces |
| `color.fg.disabled` | `--faint2` | `#908f96` | `#928e79` | 5.58 / 2.80 | 5.19 / 2.58 | 4.70 / 2.32 | a disabled control and a placeholder only |
| `color.accent.text` | `--spot` (paper darkened) | `#cba6f7` | `#7028d8` | **8.81** / **5.96** | **8.18** / **5.50** | **7.41** / **4.95** | all three surfaces |
| `color.accent.primary` | `--spot` | `#cba6f7` | `#8839ef` | fill | fill | fill | a fill, never an ink |
| `color.fg.on_accent` | `--spot-ink` | `#17171a` | `#ffffff` | - | - | - | on `color.accent.primary` only, at **8.81** / **5.41** |

- **R-32-120** The table above is normative. Every ink in the app is one of these tokens.
- **R-32-121** `color.fg.primary` clears 4.5 on all three surfaces with a wide margin: 12.39 in dark
  and 12.97 in light on `color.bg.high`, its narrowest case.
- **R-32-122** `color.fg.secondary` clears 4.5 on all three surfaces, including `color.bg.high`
  (6.92 in dark, 5.42 in light). A caption inside a filled control MAY now use
  `color.fg.secondary` directly; `color.fg.primary` remains available where more weight is wanted,
  per `R-30-402`.
- **R-32-123** `color.fg.disabled` MUST NOT carry meaningful text. Success criterion 1.4.3 exempts
  an inactive control and a placeholder, and those are its only two uses, per `R-30-120` and
  `R-30-721`.
- **R-32-124** `color.accent.text` clears 4.5 on all three surfaces: 8.81/5.96 on `bg.base`,
  8.18/5.50 on `bg.raised`, 7.41/4.95 on `bg.high`. It is now permitted on every chrome surface.
- **R-32-125** `color.accent.primary` is a fill and MUST NOT carry text. Its label is always
  `color.fg.on_accent`.
- **R-32-126** Chrome has exactly one fill capable of carrying `color.fg.on_accent` at 4.5 or
  better in both themes today: `color.accent.primary` itself, at 8.81 in dark and 5.41 in light,
  per `R-32-101`. `color.status.error` (red) is a semantic token, not a chrome fill, per `R-32-103`
  and `R-32-584`'s class split, so it is not a candidate here even though its own hex would pass
  the same label. A filled destructive control therefore is not available to chrome in version
  one; the destructive treatment of `R-32-506` stays, unchanged. The one red fill in chrome is
  the platform's own tab badge of section 7.5, which reaches `color.status.error` only through
  the theme's `colorScheme.error` (amended 2026-09-09 by the product owner, per `R-03-059`).
- **R-32-127** A focus ring MUST be drawn outside the control's own fill, on the surface the
  control sits on. `color.accent.text` now clears the 3.0 indicator floor on every surface, so a
  ring is never blocked by which surface the control sits on; `color.bg.high`, the narrowest case
  at 7.41 in dark and 4.95 in light, still clears it several times over.

### 3.4 Semantic state colours (Herdr agent-state colours)

| Token | State | Ink | Paper | On `bg.base` | On `bg.raised` | On `bg.high` |
| --- | --- | --- | --- | --- | --- | --- |
| `color.status.working` | `working` | `#e6b84a` | `#9a6f08` | 9.64 / 3.83 | 8.96 / 3.53 | 8.12 / 3.18 |
| `color.status.blocked` | `blocked` | `#e05a5a` | `#c73e3e` | 4.92 / 4.25 | 4.57 / 3.92 | 4.14 / 3.53 |
| `color.status.idle` | `idle` | `#52c97a` | `#268a46` | 8.51 / 3.70 | 7.91 / 3.41 | 7.17 / 3.07 |
| `color.status.done` | `done` | `#94e2d5` | `#1f8078` | 12.01 / 4.03 | 11.15 / 3.71 | 10.11 / 3.34 |
| `color.status.unknown` | `unknown` | `#908f96` | `#6f6b5c` | 5.58 / 4.53 | 5.19 / 4.17 | 4.70 / 3.75 |
| `color.status.error` | a failure | `#e05a5a` | `#c73e3e` | 4.92 / 4.25 | 4.57 / 3.92 | 4.14 / 3.53 |
| `color.status.warning` | a warning | `#e6b84a` | `#9a6f08` | 9.64 / 3.83 | 8.96 / 3.53 | 8.12 / 3.18 |
| `color.status.ok` | a success | `#52c97a` | `#268a46` | 8.51 / 3.70 | 7.91 / 3.41 | 7.17 / 3.07 |
| `color.status.info` | a neutral note | `#cba6f7` | `#8839ef` | 8.81 / 4.59 | 8.18 / 4.23 | 7.41 / 3.81 |

These nine hexes are the Herdr brand state colours; the Paper values for `working`, `idle`, `done`,
`unknown` are darkened by this document to clear the 3.0 indicator floor on all three surfaces.

- **R-32-130** The table above is normative. `color.status.warning` and `color.status.blocked` share
  the red hue on purpose. `color.status.ok` and `color.status.idle` share the green hue, and
  `color.status.info` shares the spot (lavender). The icon and the word separate them, not the hue.
- **R-32-131** A status hue MUST NOT carry text, per `R-30-130`. This is a consistency policy, not
  a universal contrast failure. The state word is always `color.fg.primary`, per `R-30-402`, and
  the hue lives in the icon, the bar or the border (the dot left this list on 2026-09-09, per
  `R-03-100`). One exemption: the tab badge of section 7.5 is the platform's own control, and it
  puts its count in `color.fg.on_accent` on `color.status.error`, as both platforms do (amended
  2026-09-09 by the product owner, per `R-03-059`). That pairing clears 4.5 to 1 in both themes,
  per `R-32-126`.
- **R-32-132** A status hue now clears the 3.0 indicator floor on all three surfaces, in both
  themes. The narrowest case is `color.status.working`/`color.status.warning` at 3.18 in light on
  `bg.high`. A status hue appears only in the state bar of section 7.29 and in the treatments of
  `R-32-131`: the icon, the bar or the border. It MUST NOT appear inside a key cap, on the jump
  pill or on any other control `color.bg.high` fills (amended 2026-09-09 by the product owner, per
  `R-03-100`: a key cap carries no state indicator; an earlier sentence permitted a hue there).
- **R-32-133** Yellow MUST NOT be a status hue. Selenized light yellow measures 2.98 on
  `color.term.bg`, which misses the indicator floor there; that pairing is unaffected by the brand
  palette, since `color.term.bg` stayed Selenized. Yellow stays in the terminal palette, where the
  remote program's choice applies and ours does not.
- **R-32-134** A state MUST be carried by a hue and a distinct shape and a word together, per
  `R-30-141` and `R-30-401`. The five agent-state icons are fixed in `R-32-401`.

### 3.5 The terminal palette

The slot mapping is the published Selenized table with exactly one deviation, recorded in
`R-32-141`.

| Token | Slot | Selenized name | Dark | Light | Dark ratio | Light ratio | Clears 3.0 in both |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `color.term.bg` | background | `bg_0` | `#103c48` | `#fbf3db` | - | - | - |
| `color.term.fg` | foreground | `fg_0` | `#adbcbc` | `#53676d` | 6.07 | 5.37 | yes, and clears 4.5 |
| `color.term.fg_bold` | bold foreground | `fg_1` | `#cad8d9` | `#3a4d53` | 8.14 | 8.01 | yes, and clears 4.5 |
| `color.term.fg_dim` | dim foreground | `dim_0` | `#72898f` | `#909995` | 3.23 | 2.64 | no in light; this is the dim role by definition |
| `color.term.cursor` | cursor | `fg_1` | `#cad8d9` | `#3a4d53` | 8.14 | 8.01 | yes, and clears 4.5 |
| `color.term.selection` | selection background | `bg_2` | `#2d5b69` | `#d5cdb6` | - | - | a background, not an ink |
| `color.term.ansi_0` | 0 black | `bg_1` | `#184956` | `#ece3cc` | 1.21 | 1.15 | background slot, exempt |
| `color.term.ansi_1` | 1 red | `red` | `#fa5750` | `#d2212d` | 3.71 | 4.74 | yes |
| `color.term.ansi_2` | 2 green | `green` | `#75b938` | `#489100` | 4.97 | 3.56 | yes |
| `color.term.ansi_3` | 3 yellow | `yellow` | `#dbb32d` | `#ad8900` | 5.96 | **2.98** | **no in light, by 0.02** |
| `color.term.ansi_4` | 4 blue | `blue` | `#4695f7` | `#0072d4` | 3.92 | 4.35 | yes |
| `color.term.ansi_5` | 5 magenta | `magenta` | `#f275be` | `#ca4898` | 4.58 | 3.87 | yes |
| `color.term.ansi_6` | 6 cyan | `cyan` | `#41c7b9` | `#009c8f` | 5.73 | 3.08 | yes |
| `color.term.ansi_7` | 7 white | **`fg_0`**, deviating from `dim_0` | `#adbcbc` | `#53676d` | **6.07** | **5.37** | yes |
| `color.term.ansi_8` | 8 bright black | `bg_2` | `#2d5b69` | `#d5cdb6` | 1.60 | 1.43 | background slot, exempt |
| `color.term.ansi_9` | 9 bright red | `br_red` | `#ff665c` | `#cc1729` | 4.15 | 5.09 | yes |
| `color.term.ansi_10` | 10 bright green | `br_green` | `#84c747` | `#428b00` | 5.81 | 3.85 | yes |
| `color.term.ansi_11` | 11 bright yellow | `br_yellow` | `#ebc13d` | `#a78300` | 6.94 | 3.22 | yes |
| `color.term.ansi_12` | 12 bright blue | `br_blue` | `#58a3ff` | `#006dce` | 4.60 | 4.64 | yes |
| `color.term.ansi_13` | 13 bright magenta | `br_magenta` | `#ff84cd` | `#c44392` | 5.35 | 4.15 | yes |
| `color.term.ansi_14` | 14 bright cyan | `br_cyan` | `#53d6c7` | `#00978a` | 6.70 | 3.27 | yes |
| `color.term.ansi_15` | 15 bright white | `fg_1` | `#cad8d9` | `#3a4d53` | 8.14 | 8.01 | yes |

- **R-32-140** The emulator MUST be configured with exactly the 22 values above, per `R-30-150`. It
  MUST NOT fall back to a package default palette, and it MUST NOT leave a slot unset.
- **R-32-141** Slot 7 MUST be `fg_0`, which deviates from the published Selenized mapping of
  `dim_0`. A bare `SGR 37` selects slot 7, so it is the highest-traffic ink in the payload. The
  published value measures 3.23 in dark and 2.64 in light; `fg_0` measures 6.07 and 5.37. `dim_0`
  keeps its other published job as `color.term.fg_dim`. The cost is one departure from the published
  table, and the deviation MUST be recorded wherever the mapping is stated.
- **R-32-142** With that deviation applied, exactly one of the 16 slots misses the 3.0 indicator
  floor: light `yellow` at 2.98, short by 0.02. There is no fix inside the palette. `br_yellow` at
  `#a78300` measures 3.22 in light, and taking it for slot 3 would duplicate slot 11 and cost a
  distinct ink, which is the fidelity property that chose this palette. The app MUST accept 2.98 and
  MUST NOT correct it, per `R-30-152`. `R-32-133` already keeps yellow out of the interface, so the
  miss touches payload only. This document records the failure rather than hiding it.
- **R-32-143** The three slots the app picks when the program expresses no preference, which are the
  default foreground, the bold foreground and the cursor, MUST clear 4.5 in both themes. They
  measure 6.07 and 5.37, 8.14 and 8.01, and 8.14 and 8.01. These three are our choice, not the
  program's, so the text threshold applies to them.
- **R-32-144** The selection background MUST be `color.term.selection` and the selected cell MUST
  keep its own ink, so a selection never repaints payload colour. Where the cell holds the default
  ink the pair measures 3.80 in dark and 3.75 in light. Selection is therefore never carried by
  contrast alone: the selection app bar states the line count in words, per
  `docs/31-mockups/08-terminal.md`.
- **R-32-145** A colour the remote program chose is outside this document's contrast budget, per
  `R-30-152` and `R-30-722`. The app MUST NOT correct, boost or remap it. The 16 slots above are
  ours, which is why they carry the 3.0 indicator floor and not the 4.5 text threshold.
- **R-32-146** All 16 slots resolve to 16 distinct inks. A program that separates two things with
  `SGR 31` and `SGR 1;31` MUST keep that separation, so a future palette change MUST NOT map two
  slots to one value.

### 3.6 The contrast table

Method: WCAG 2.2 relative luminance, `L = 0.2126 R + 0.7152 G + 0.0722 B`, each channel linearised
as `c/12.92` when `c <= 0.04045` and `((c + 0.055)/1.055) ^ 2.4` otherwise. The ratio is
`(L_lighter + 0.05) / (L_darker + 0.05)`. Floors: 4.5 for normal text under success
criterion 1.4.3, and 3.0 for a non-text indicator under success criterion 1.4.11.

Scope: this table governs every pair whose two members are both fixed. `R-32-585` states which
tokens those are, and section 3.7 states what the app MUST do where a member is not fixed.

| Pair | Where it appears | Dark | Light | Floor | Verdict |
| --- | --- | --- | --- | --- | --- |
| `color.fg.primary` on `color.bg.base` | every screen label, every value, every sentence | 14.72 | 15.63 | 4.5 | pass, AAA |
| `color.fg.primary` on `color.bg.raised` | a strip, a banner, a sheet row, a dialog body, a snackbar, a key cap label on Android (moved here 2026-09-09, per `R-03-059`: the cap is an outlined button with no fill on the key row's surface) | 13.67 | 14.40 | 4.5 | pass, AAA |
| `color.fg.primary` on `color.bg.high` | a field value, the jump pill label | 12.39 | 12.97 | 4.5 | pass, AAA |
| `color.fg.secondary` on `color.bg.base` | a caption, a section header, a detail line, a count | 8.22 | 6.54 | 4.5 | pass |
| `color.fg.secondary` on `color.bg.raised` | the terminal status strip, a banner explanation, a sheet caption | 7.64 | 6.02 | 4.5 | pass |
| `color.fg.secondary` on `color.bg.high` | a caption inside a filled control, per `R-32-122` | 6.92 | 5.42 | 4.5 | pass |
| `color.fg.disabled` on `color.bg.base` | a disabled text action | 5.58 | 2.80 | exempt, inactive | not applicable |
| `color.fg.disabled` on `color.bg.raised` | a grab handle, a disabled sheet row | 5.19 | 2.58 | exempt, inactive | not applicable |
| `color.fg.disabled` on `color.bg.high` | a field placeholder, a word-field dash | 4.70 | 2.32 | exempt, inactive | not applicable |
| `color.accent.text` on `color.bg.base` | the `send` action, a text button, a step number, a focus ring, the empty-state title of section 7.19 (added 2026-09-09 by the product owner, per `R-03-107`: `#cba6f7` on `#17171a` and `#7028d8` on `#efece5`, the palette of section 3) | 8.81 | 5.96 | 4.5 | pass |
| `color.accent.text` on `color.bg.raised` | a text button in a sheet, a focus ring on a raised surface | 8.18 | 5.50 | 4.5 | pass |
| `color.accent.text` on `color.bg.high` | a focus ring on a text field fill (the key cap keeps the platform's own focus response since 2026-09-09, per `R-03-059`) | 7.41 | 4.95 | 4.5 | pass |
| `color.fg.on_accent` on `color.accent.primary` | the primary button label, a latched key cap, a selected segment | 8.81 | 5.41 | 4.5 | pass |
| `color.fg.on_accent` on the pressed primary fill, `color.accent.primary` under `color.fg.primary` at `opacity.press` (`#cfaef6` dark, `#7a35d4` light) | the primary button label while pressed, per `R-32-501` (added 2026-09-08 by the product owner) | 9.40 | 6.39 | 4.5 | pass |
| `color.fg.on_accent` on `color.status.error` | the count on the platform's tab badge of section 7.5 (added 2026-09-09 by the product owner, per `R-03-059`); otherwise a semantic-hue fill label, not a chrome fill | 8.42 | 5.16 | 4.5 | pass |
| `color.accent.primary` on `color.bg.base` | the primary button fill boundary, the selected segment of the theme control, the composer cursor, the stale progress line | 8.81 | 4.59 | 3.0 | pass |
| `color.accent.primary` on `color.bg.raised` | the `Change` button in a sheet, the active bottom-navigation item | 8.18 | 4.23 | 3.0 | pass |
| `color.border.strong` on `color.bg.base` | a field boundary, the app bar bottom edge, the jump pill | 5.58 | 4.53 | 3.0 | pass |
| `color.border.strong` on `color.bg.raised` | a key cap boundary, a sheet field, a switch track that is off | 5.19 | 4.17 | 3.0 | pass |
| `color.border.strong` on `color.bg.high` | the same boundary read from inside the fill | 4.70 | 3.75 | 3.0 | pass |
| `color.border.subtle` on `color.bg.base` | a divider between two list rows | 1.27 | 1.12 | exempt, decorative | not applicable |
| `color.bg.raised` on `color.bg.base` | a strip or a banner surface, a skeleton bar | 1.09 | 1.06 | exempt, needs a border | not applicable |
| `color.bg.high` on `color.bg.base` | a filled control surface | 1.27 | 1.12 | exempt, needs a border | not applicable |
| `color.status.error` on `color.bg.base` | an error border, an error icon, the destructive bar | 4.92 | 4.25 | 3.0 | pass |
| `color.status.error` on `color.bg.raised` | an error strip icon and bar inside a sheet | 4.57 | 3.92 | 3.0 | pass |
| `color.status.warning` on `color.bg.base` | a warning icon, the insecure-relay strip bar | 9.64 | 3.83 | 3.0 | pass |
| `color.status.warning` on `color.bg.raised` | the `host_in_use` banner bar and icon | 8.96 | 3.53 | 3.0 | pass |
| `color.status.ok` on `color.bg.base` | the `connected` state bar of `R-32-705`, a success icon | 8.51 | 3.70 | 3.0 | pass |
| `color.status.ok` on `color.bg.raised` | the `ok` state bar on a strip | 7.91 | 3.41 | 3.0 | pass |
| `color.status.working` on `color.bg.base` | the `working` icon, the stale progress line | 9.64 | 3.83 | 3.0 | pass |
| `color.status.working` on `color.bg.raised` | the `working` icon inside a sheet header | 8.96 | 3.53 | 3.0 | pass |
| `color.status.blocked` on `color.bg.base` | the `blocked` icon, the attention bar, the inline badge icon | 4.92 | 4.25 | 3.0 | pass |
| `color.status.blocked` on `color.bg.raised` | the `blocked` icon inside a banner or a sheet | 4.57 | 3.92 | 3.0 | pass |
| `color.status.done` on `color.bg.base` | the `done` icon and the attention bar of a `done` row | 12.01 | 4.03 | 3.0 | pass |
| `color.status.done` on `color.bg.raised` | the `done` icon inside a sheet header | 11.15 | 3.71 | 3.0 | pass |
| `color.status.idle` on `color.bg.base` | the `idle` state bar, and the `saved` and `offline` state bars of `R-32-705` | 8.51 | 3.70 | 3.0 | pass |
| `color.status.idle` on `color.bg.raised` | the `idle` state bar inside a sheet header or on a strip | 7.91 | 3.41 | 3.0 | pass |
| `color.status.unknown` on `color.bg.base` | the `unknown` icon | 5.58 | 4.53 | 3.0 | pass |
| `color.status.unknown` on `color.bg.raised` | the `unknown` icon on an offline strip row | 5.19 | 4.17 | 3.0 | pass |
| `color.term.fg` on `color.term.bg` | the terminal default ink, the live preview on `/settings` | 6.07 | 5.37 | 4.5 | pass |
| `color.term.fg_bold` on `color.term.bg` | the terminal bold ink | 8.14 | 8.01 | 4.5 | pass |
| `color.term.cursor` on `color.term.bg` | the terminal cursor | 8.14 | 8.01 | 4.5 | pass |
| `color.term.fg_dim` on `color.term.bg` | `SGR 2` output | 3.23 | 2.64 | exempt, the dim role | not applicable |
| `color.term.fg` on `color.term.selection` | a selected cell that holds the default ink | 3.80 | 3.75 | recorded, per `R-32-144` | recorded |
| `color.term.fg_bold` on `color.term.selection` | a selected cell that holds the bold ink | 5.10 | 5.59 | 4.5 | pass |
| the 16 ANSI slots on `color.term.bg` | payload colour, measured in `R-32-140` | see table | see table | 3.0 | one miss, `R-32-142` |

- **R-32-150** The table above MUST list every pair the app uses. A pair that is not in it MUST NOT
  be used. A new pairing MUST be measured with the method above and added here before a screen
  adopts it, which is the value side of `R-30-720`.
- **R-32-151** A ratio MUST be stated to two decimals and MUST NOT be rounded up to reach a floor. A
  pair that misses by 0.02 has missed.
- **R-32-152** A pair marked `forbidden` MUST NOT appear in any screen, mockup or widget. A review
  MUST reject it.
- **R-32-153** An automated test MUST recompute every row from the tokens and fail on a difference,
  which is the check `docs/30-ux-spec.md` lists in its implementation checklist.

### 3.7 Chrome tokens, terminal tokens, and what the measured table proves

Every colour token above falls in exactly one of four classes. The class decides whether a platform
may resolve the value, and which method proves the contrast.

| Class | Tokens | Resolves per platform | Proof method |
| --- | --- | --- | --- |
| Chrome | `color.bg.*`, `color.border.*`, `color.fg.*`, `color.accent.*` | yes, per `R-33-006` | the measured table where fixed |
| Fixed chrome | `color.shadow` | no | not a contrast pair, per `R-32-321` |
| Semantic state | `color.status.*` | no | the measured table, always |
| Terminal | `color.term.*` | no | the measured table, always |

- **R-32-584** The four classes above are normative. The token names already carry the boundary and
  this rule states it so that no reader has to infer it: a `color.term.*` token is a **terminal**
  value, a token in section 3.2 or 3.3 is a **chrome** value, and, since `R-32-103`, the two draw
  from separate sources on purpose. Two consequences are normative in their own right. First, the
  terminal grid MUST take `color.term.bg`, never `color.bg.base`: before `R-32-103` both resolved
  to Selenized `bg_0` and agreed by coincidence; now they disagree in both themes, so a widget that
  reaches the grid through the chrome token is a visible defect, not only a latent one. Only one of
  the two classes may ever follow a wallpaper, per `R-33-055`, and the source split makes that
  boundary self-enforcing rather than merely disciplined. Second, a `color.status.*` token is
  **semantic**, not chrome, because `R-32-134` binds a state to a hue, so a wallpaper MUST NOT be
  able to recolour a state; it keeps drawing from the Herdr brand, per section 3.1b, unaffected by
  the chrome source change.
- **R-32-585** The measured table of `R-32-150` governs, and still proves, every pair whose two
  members are fixed. Those are the whole terminal palette of section 3.5, every `color.status.*`
  pair, and every chrome pair on a platform that keeps the fixed chrome palette. The table MUST NOT
  be deleted or reduced, and a new fixed pair MUST still be measured by the method above and added
  before a screen adopts it.
- **R-32-586** The measured table cannot reach two cases, and `docs/33` owns both. A pair with a
  generated member falls to the runtime assertion of `R-33-044`, which covers a generated ink on a
  generated surface and a fixed `color.status.*` ink on a generated surface. A translucent material
  cannot be measured at all, because its effective background is the content that scrolls behind it,
  so `R-33-051` and `R-33-052` own it: legibility is proved there by a stated test protocol and by
  honouring the platform Reduce Transparency and Increase Contrast settings, never by a ratio. This
  document MUST NOT state a ratio for either case, and MUST NOT record either case as a pass. One
  consequence is worth naming, because a reader expects the opposite: chrome that overlaps the
  terminal grid rect stays fixed and opaque on both platforms, per `R-33-060`, so the terminal
  status strip and the offline strip keep their measured rows and never leave the table.## 4. Type

## 4. Type

| Role | Family | Weights bundled | Licence | Source | Owner |
| --- | --- | --- | --- | --- | --- |
| display | `Archivo` | 700, 900 | SIL Open Font License 1.1, Copyright 2012 Omnibus-Type | `https://github.com/Omnibus-Type/Archivo` | this document, and `R-30-200` for the bundling rule |
| interface | `IBM Plex Sans` | 400, 600 | SIL Open Font License 1.1, Copyright (c) 2017 IBM Corp. with Reserved Font Name "Plex" | `https://github.com/IBM/plex/blob/master/LICENSE.txt` | this document, and `R-30-200` for the bundling rule |
| mono label | the family `R-21-011` names | as `docs/21-terminal-rendering.md` states | as that document states | as that document states | `docs/21-terminal-rendering.md`; this document only names the tokens that use it |
| terminal content | the family `R-21-011` names | as `docs/21-terminal-rendering.md` states | as that document states | as that document states | `docs/21-terminal-rendering.md` |

Faces to bundle for the display and interface roles:

| Family | Weight | Face | File |
| --- | --- | --- | --- |
| Archivo | 700 | Bold | `Archivo-Bold.ttf` |
| Archivo | 900 | Black | `Archivo-Black.ttf` |
| IBM Plex Sans | 400 | Regular | `IBMPlexSans-Regular.ttf` |
| IBM Plex Sans | 600 | SemiBold | `IBMPlexSans-SemiBold.ttf` |

The Plex path prefix in the source repository is `packages/plex-sans/fonts/complete/ttf/`. The
Archivo static faces come from the `fonts/ttf/` directory of the Archivo repository.

- **R-32-200** The app MUST bundle exactly those four files as assets and MUST synthesise nothing
  else, which is the value side of `R-30-200` and `R-30-202`. IBM also ships a `Text` face at weight
  450 and six other upright weights, and Archivo ships seven other weights and a variable build;
  none of them is bundled. Weight 500 in `type.label` renders from Plex Regular with the platform's
  own weight interpolation.
- **R-32-201** The app MUST NOT use Inter, Roboto, Open Sans or a platform default sans, per
  `R-30-201`. It MUST NOT download a font at run time.

Every size below is a Flutter logical pixel, which equals a density-independent pixel on Android and
a point on iOS. `mono` is the family `R-21-011` names. Letter spacing is in logical pixels, with the
em fraction it derives from in brackets. `UPPER` means the widget applies `toUpperCase()` to the
string; the token itself carries no transform.

| Token | Family | Size/line | Weight | Letter spacing | Case | Use |
| --- | --- | --- | --- | --- | --- | --- |
| `type.display` | Archivo | 42/40 (amended 2026-09-08 by the product owner: at 44 the headline `From anywhere.` measured 345 px against the 343 px column of the 375 reference device and wrapped to a third line, against `R-31-01` callout 4; at 42 it measures 328 px) | 900 | -2.4 (-0.057em) | as written | the `/welcome` headline only |
| `type.title` | Archivo | 28/30 | 900 | -1.1 (-0.04em) | as written | a screen title with no back chevron, the product name on `/lock`, an empty-state title |
| `type.heading` | Archivo | 18/24 | 700 | -0.36 (-0.02em) | as written | an app bar title, a host chip, a sheet heading |
| `type.body` | Plex | 16/24 | 400 | 0 | as written | every row label, every sentence |
| `type.body.strong` | Plex | 16/24 | 600 | 0 | as written | a primary row label |
| `type.label` | Plex | 14/20 | 500 | 0 | as written | a status word, a right-aligned value |
| `type.caption` | Plex | 12/16 | 400 | 0 | as written | a secondary line, a hint, a counter |
| `type.micro` | mono | 11/14 | 700 | 1.76 (0.16em) | UPPER | a section header, an eyebrow, a state word, a tab label, a form label |
| `type.micro.strong` | mono | 11/14 | 700 | 0 | as written | a count beside an attention icon |
| `type.mono.button` | mono | 13/16 | 700 | 1.04 (0.08em) | as written | a step number in the welcome steps card of section 7.31 (amended 2026-09-09 by the product owner, per `R-03-104`: until then every button label, UPPER; a button label is the platform's own style now, per `R-32-212`) |
| `type.mono.code` | mono | 13/20 | 400 | 0 | as written | a raw error, an id, a path, a relay origin shown as a value |
| `type.mono.key` | mono | 13/16 | 500 | 0 | as written | a key cap label |
| `type.mono.compose` | mono | 15/22 | 400 | 0 | as written | the the input bar field |
| `type.mono.phrase` | mono | 18/24 | 500 | 0 | as written | one pairing word in one word field, and every input on `/pair/manual` |
| `type.mono.terminal` | mono | one of `R-32-208`'s sizes, line height per `R-32-209` | 400 | 0 | as written | terminal content |

- **R-32-202** The fifteen tokens above are the complete set. A screen MUST NOT use a size, a line
  height, a weight or a letter spacing outside this table. A platform button's label is the one
  exception, per `R-32-212` (added 2026-09-09, per `R-03-104`).
- **R-32-203** `type.body` is 16 with a line height of 24. Apple publishes Body at 17/22 and
  Material publishes `bodyLarge` at 16/24; one token has to serve both platforms, and this document
  takes the Material value. Three reasons, in order: the terminal is the content and the chrome must
  not compete with it; 24 sits on the 4 grid and 22 does not; and Apple's own published legibility
  floor for iOS is 11, so 16 is comfortably legible rather than merely permitted. The one-point
  deviation from Apple Body is deliberate and is recorded here so a reviewer who knows iOS finds the
  reason beside the value.
- **R-32-204** Letter spacing MUST be exactly the table value: negative on `type.display`,
  `type.title` and `type.heading`, positive on `type.micro` and `type.mono.button`, and 0 on every
  other token. A pairing word is read, not spelled out, so `type.mono.phrase` MUST NOT be tracked
  out.
- **R-32-205** `type.display` is permitted on `/welcome` only. The product name on `/lock` MUST use
  `type.title`, because the subject of that screen is the unlock action and a 44 logical pixel name
  above a platform biometric sheet competes with it. One string, two screens, two sizes, and this
  rule is the reason.
- **R-32-206** No interface token may go below 11. Apple publishes 11 as the iOS minimum and 17 as
  the default, so `type.micro` is the floor and MUST NOT be reduced.
- **R-32-207** A monospace token MUST NOT carry a sentence and a sans token MUST NOT carry a path,
  an id, a raw error, a relay origin or terminal content, per `R-30-212`. A section header is the
  one exception the table names: it is a label, not a sentence (amended 2026-09-09 by the product
  owner, per `R-03-104`: the button label was the second exception until a button label became the
  platform's own sans style).
- **R-32-208** The saved `type.mono.terminal` sizes are exactly 10, 11, 12, 13, 14, 16 and 18,
  and the default is 13. This is the value side of R-30-210 and R-21-010. Settings uses the
  discrete slider of R-30-211. Per the 2026-09-17 user correction, temporary pinch zoom permits
  continuous sizes from 1 to 36 logical pixels. If Overview already paints below that minimum,
  its painted size is the gesture's lower bound so the first movement cannot jump upward.
- **R-32-209** The `type.mono.terminal` line height MUST be the size times the ratio `R-21-010`
  fixes, rounded to one decimal. This document MUST NOT restate that ratio.
- **R-32-210** Every interface token MUST scale with `MediaQuery.textScalerOf(context)` and MUST
  clamp at 2.0, per `R-30-700` and `R-30-701`. A factor of 2.0 lands between Apple's AX1 size, which
  puts Body at 28 from a default of 17 and is a factor of 1.65, and AX2. `type.mono.terminal` MUST
  NOT scale with the system setting, per `R-30-702`.
- **R-32-211** `MediaQuery.boldTextOf(context)` true MUST raise weight 400 to 600 and weight 500 to
  700, and MUST NOT change a size, per `R-30-704`.
- **R-32-212** A button label is the platform's own label style, in the interface family the theme
  sets and as written: on Android the Material 3 `labelLarge` a `FilledButton`, `OutlinedButton` or
  `TextButton` draws when its theme sets no `textStyle`; on iOS the Cupertino action text style a
  `CupertinoButton` draws, at the component's own size and tracking. The three button themes and
  `textTheme.actionTextStyle` in `app/lib/app.dart` set the family and nothing else of the type. A
  screen MUST NOT set a button label in a token of this table, MUST NOT upper-case it and MUST NOT
  set a mono face on it. Amended 2026-09-09 by the product owner, per `R-03-104`, who pointed at
  the Notifications strip: until then this rule made `type.mono.button` UPPER the label of every
  button. A key cap keeps `type.mono.key`, per section 7.12.
- **R-32-213** Upper case is applied by the widget that draws a `type.micro` string; a token carries
  no transform, a semantics label keeps the written case, and a button label, the phrase field and
  the terminal are never upper-cased (amended 2026-09-09, per `R-03-104`: `type.mono.button` left
  this rule with the button label).

## 5. Space, radius, elevation, border, opacity and size

### 5.1 Spacing

A 4 base scale with 8 as the working rhythm. Every value in it appears in IBM Carbon or GitHub
Primer, and the set is closed.

| Token | Value |
| --- | --- |
| `space.0` | 0 |
| `space.1` | 4 |
| `space.2` | 8 |
| `space.3` | 12 |
| `space.4` | 16 |
| `space.5` | 20 |
| `space.6` | 24 |
| `space.8` | 32 |
| `space.10` | 40 |
| `space.12` | 48 |
| `space.16` | 64 |

- **R-32-300** The table above is the complete scale. A value outside it is not permitted, per
  `R-30-232`. `space.7` does not exist. Carbon's 2 and Primer's 6, 28, 36 and 44 are deliberately
  absent: 2 is invisible at phone density, and the other four exist in Primer only to size a
  control, which the size tokens in `R-32-350` already do by name.
- **R-32-301** Which step applies where:

  | Place | Step |
  | --- | --- |
  | Screen edge inset | `space.4`, which is the value side of `R-30-230` |
  | The terminal grid edge inset | `space.0`, the one exception in `R-30-230` |
  | Gap between two rows in one group | `space.0`, per `R-30-231` |
  | Gap between two groups | `space.6`, per `R-30-231` |
  | Gap between an icon and its label inside a treatment | `space.2` |
  | Gap between two adjacent touch targets | `space.1` minimum, per `R-30-292` |
  | Horizontal padding inside a bezelled control | `space.3`, which follows Apple's published guidance of about 12 points of padding around a bezelled element |
  | Gap between two key caps, between two arrow keys, and between two rows of keys | `space.2`; `space.2` is also the padding inside a cap, per `R-31-09-15` (amended 2026-09-09 by the product owner, per `R-03-059`: the arrow cluster and its `space.1` gutter are gone; the four arrows are four buttons at the row's one gap; amended 2026-09-10 per `R-03-116`: the chord key of the retired Shortcuts palette left with it) |

- **R-32-302** A layout MUST NOT invent a step, and MUST NOT reach a value by adding two steps where
  one step exists. `space.4` plus 16 is not a spacing value; the `Workspace` axis of
  `docs/31-mockups/06-agent-list.md` puts its tab label and its pane text at `space.16`, one
  `space.4` past the 48 column its names share, per `R-32-570` (amended 2026-09-08). A text edge
  that follows a glyph and its gap, such as that 48, is a composition of size and spacing tokens,
  not a new step.

### 5.2 Corner radii

| Token | Value | Use |
| --- | --- | --- |
| `radius.none` | 0 | terminal grid, divider, strip, banner, app bar |
| `radius.sm` | 2 | button, chip, segment, focus ring, text field (the key cap left this row on 2026-09-09, per `R-03-059`: it keeps the platform's own button shape) |
| `radius.md` | 4 | card, dialog, raw-error block, sheet body |
| `radius.lg` | 6 | bottom sheet top corners |
| `radius.full` | 999 | grab handle, switch track, badge count (the dot left this row on 2026-09-09, per `R-03-100`) |

- **R-32-310** The terminal grid MUST use `radius.none`, per `R-30-250`. A rounded terminal clips a
  real cell.

### 5.3 Elevation

| Token | Composition |
| --- | --- |
| `elev.0` | No border and no shadow |
| `elev.1` | A 1 wide border in `color.border.strong`, no shadow |
| `elev.2` | Offset y 2, blur 8, spread 0, `color.shadow` at 40 percent in dark and 12 percent in light |
| `elev.3` | Offset y 8, blur 24, spread 0, `color.shadow` at 48 percent in dark and 16 percent in light |

- **R-32-320** Separation MUST come from `elev.1` first, per `R-30-260`. A shadow is permitted only
  on a floating layer, and this is the closed list: a bottom sheet and a dialog at `elev.3`; an
  autocomplete strip, the create control of `R-32-588` and the snackbar of section 7.22 at
  `elev.2` (amended 2026-09-09 by the product owner, per `R-03-109`, when the create control
  left the list for an app bar action; restored 2026-09-10 by the corrected `R-03-109`, which
  keeps the floating button on both platforms; the snackbar was already at `elev.2` in section
  7.22 and is named here so the list is closed in fact). A layer whose own standard component
  draws a translucent surface MUST NOT also carry a shadow, per `R-33-012`. That surface already
  separates the layer, and two separations read as a raised card sitting on a bar.
- **R-32-321** The shadow colour MUST be `color.shadow`, which is `#181818`, and MUST NOT be pure
  black, per `R-30-111`.
- **R-32-322** The app MUST NOT hand-roll a blur, a translucent surface, a glow border or a
  gradient, per `R-30-261`. Both platforms draw the fixed Herdr palette on opaque surfaces, so no
  translucent chrome surface exists to approximate. A `BackdropFilter` blur is not a standard
  component, and the app MUST NOT approximate Liquid Glass by any means, per `R-33-013`. No
  translucent material MUST be drawn over or behind the terminal grid, per `R-33-055`. A glow
  border and a gradient stay forbidden everywhere; the ground grid of `R-32-332` is a line texture,
  not a gradient.

### 5.4 Border widths and opacity

| Token | Value | Colour | Use |
| --- | --- | --- | --- |
| `border.hairline` | 1 | `color.border.strong` or `color.border.subtle` | A control boundary or a divider |
| `border.focus` | 2 | `color.accent.text` | The focus ring, at `radius.sm`, drawn outside a row or a header, per `R-32-127`; a button, and since 2026-09-09 a key cap, keeps the platform's own focus response (amended 2026-09-09 by the product owner, per `R-03-059`) |
| `border.error` | 2 | `color.status.error` | A field that failed validation |
| `border.attention` | 3 | the row's `color.status.*` | The state bar of section 7.29, which is the one leading bar a row carries (amended 2026-09-09 by the product owner, per `R-03-100`), and the leading bar of `treat.error` in a strip; `treat.destructive` left this row on 2026-09-09, per `R-03-058` |
| `border.frame` | 3 | `color.accent.primary` | A corner mark on the QR viewfinder |
| `border.accent` | 2 | `color.accent.primary` | The top edge of a featured card (welcome steps card, empty-state card); the selected segment underline left this row on 2026-09-09, per `R-03-059` and section 7.6 |

| Token | Value | Use |
| --- | --- | --- |
| `opacity.press` | 0.12 | The pressed overlay of `R-32-501`; on a Material button it is the ink overlay the theme hands the platform widget (amended 2026-09-09, per `R-03-059`) |
| `opacity.disabled` | 0.38 | A disabled control, per `R-32-502`; on a button it reaches the fill, the label and the border through the theme's disabled colours (amended 2026-09-09, per `R-03-059`) |
| `opacity.dim` | 0.60 | A scrim over a screen that is not the terminal, and the last painted grid in every non-live state |

- **R-32-330** A border width outside this table is not permitted. The focus ring is 2, which is the
  value side of `R-30-718`.
- **R-32-331** An opacity outside this table is not permitted. A disabled control MUST NOT also
  change colour, because two signals for one state make the disabled state look like an error.
- **R-32-332** The ground grid: 1 px lines in `color.bg.grid` on a 40 px pitch, painted on
  `color.bg.base`. Lines align to the top-left of the area the grid fills: the safe area on a hero
  screen, the list body under the header block behind an empty state (clarified 2026-09-09, per
  `R-03-107`). It is texture: contrast-exempt, and no meaning may rely on it. The grid is the
  ground of a screen that has no content: the four
  hero screens (welcome, lock, QR scan and about) and the empty state of any list,
  per `R-03-107`. A screen that has content (rows, sections, a card, a table) MUST paint plain
  `color.bg.base` as its body ground, with no grid and no paper block. A hero screen sets its text
  on the grid on purpose, and an empty state sets its text block over the grid and the watermark
  of `R-32-554`; those are the only places where text sits on a grid line. The grid MUST NOT be
  painted inside a card, a sheet, a dialog, a strip, the app bar, the tab bar, the key row or the
  terminal (`R-30-272`, `R-33-055`). `app/lib/widgets/ground_grid.dart` `GroundGrid` paints it;
  `app/lib/widgets/app_ground.dart` holds `EmptyMark` and nothing else. History, per `R-03-107`,
  which the product owner decided on 2026-09-09 in two steps. On 2026-09-03 the owner limited the
  grid to the five hero screens. On 2026-09-09, step one, the owner put the grid on every
  non-terminal screen, with content on the opaque paper of `R-32-334` and the grid in the margins
  and under the last block. On 2026-09-09, step two, after seeing the grid around solid list
  blocks, the owner rejected it as ugly and limited the grid to the hero screens and the empty
  state again. `R-32-334` is retired with step two; a document that still says a list screen sits
  on paper over the grid describes step one and is superseded by this rule.
- **R-32-333** `border.accent` 2 px in `color.accent.primary`: the top edge of a featured card
  (welcome steps card, empty-state card). (Amended 2026-09-09 by the product owner, per `R-03-059`.)
  The selected segment underline is gone: the platform segmented control of section 7.6 marks its
  selection itself, and the app draws no segment.

### 5.5 Sizes

| Token | Value | Use |
| --- | --- | --- |
| `size.target.min` | 48 by 48 | Every interactive element, per `R-32-360` |
| `size.appbar` | Android 56; iOS 44, the `CupertinoNavigationBar` height; each plus the top safe-area inset (amended 2026-09-08) | The app bar and the selection app bar. A control inside the iOS bar follows `R-33-076` |
| `size.bar.merged` | 56 | The terminal's landscape bar, where the app bar row and the status strip merge into one, on both platforms; it holds the `size.target.min` mode control of `R-32-543` with the row range and the revision beside it, so it is never the 44 iOS `size.appbar` (added 2026-09-08 by the product owner; `R-32-543` already said "at least 56") |
| `size.bottomnav` | 56, plus the bottom safe-area inset | The three bottom destinations |
| `size.statusstrip` | 48, which is `size.target.min` | The terminal status strip; it holds the labelled mode control (amended 2026-09-08, was 28) |
| `size.keyrow` | 48 | One row of key panel caps |
| `size.header` | 32 | An upper-case group header row |
| `size.row.one_line` | 52 | A settings row, a sheet action row, a toggle row, a tree row |
| `size.row.two_line` | 72 | A host row, an agent row, a paired-phone row, a settings row with a value line |
| `size.button.primary` | platform | A filled button, a ghost button, `Reconnect now`. The height, the radius and the minimum are the platform component's own: Material 3's pill, 40 inside its 48 tap target, on Android; `CupertinoButtonSize.large`, 44 minimum and 48 with its label, on iOS. The tokens that reach a button are colours and type only (amended 2026-09-09 by the product owner, per the `R-03-059` addendum: was 52 through `filledButtonTheme`, a fixed box the addendum forbids; a screen MUST NOT wrap a button in a box of this height either) |
| `size.button.text` | platform | A text-only action, `Cancel` in a sheet. The height, the radius and the minimum are the platform component's own: Material 3's 40 inside its 48 tap target on Android; `CupertinoButtonSize.large`, 48 with its label, on iOS. Colours and type only reach it through the theme (amended 2026-09-09 by the product owner, per the `R-03-059` addendum: was 48 through `textButtonTheme`) |
| `size.button.create` | 56 by 56 | The floating create button of `R-32-588`, the component's own box on both platforms; a list adds this plus `space.4` as its own end padding (retired 2026-09-09 and restored 2026-09-10 by the product owner, per the corrected `R-03-109`) |
| `size.field` | 48 | A text field, a word field, the composer input row |
| `size.field.compose.min` | retired | Retired 2026-09-14 per `R-03-132`: the input bar field grows by line count, not a fixed minimum height |
| `size.keycap` | 48 wide minimum by 48 high | One key cap, one arrow key, one navigation key; the cap is its own target, so it is `size.target.min` high (decided 2026-09-03 by the product owner, `R-31-09-21`). Since 2026-09-09 the cap is the platform's own button, per `R-03-059`, and this value is the layout floor the key row's own button theme sets on it as a minimum size, never a shape; see section 7.12 (amended 2026-09-10 per `R-03-117`: a symbol key took this floor too until then) |
| `size.chordkey` | retired | Retired 2026-09-10 by the product owner, per `R-03-116`: it was the 56 wide minimum of one key in the Shortcuts palette, and that palette is gone with the `Shortcuts` control that opened it (the retired `R-31-09-22` and `R-31-08-24`). Bank two of the key row holds those keys now, at the column module of `R-31-09-21`, so `AppSize.chordkeyWidth` is deleted, as `AppSize.chordkeyHeight` was on 2026-09-09 |
| `size.pill` | 36 | The jump-to-bottom pill |
| `size.grab` | 36 wide by 4 high | The bottom sheet grab handle |
| `size.dot.status`, `size.dot.offline`, `size.dot.live` | retired | Retired 2026-09-09 by the product owner, per `R-03-100`: no screen draws a dot. The state bar of section 7.29 is `border.attention` wide and takes the row's height, so it needs no size token |
| `size.icon.sm` | 16 | A status icon, a treatment icon, an inline icon, a badge icon |
| `size.icon.md` | 20 | A control icon, a chevron, an expander, a destructive treatment icon |
| `size.icon.lg` | 24 | An app bar icon, a bottom-navigation icon |
| `size.icon.hero` | 96 | The biometric glyph on `/lock`, the only hero icon in the app |
| `size.spinner` | 20 | The in-place spinner that replaces a label while an action is in flight |
| `size.skeleton` | 12 high | One skeleton bar, at `radius.sm` in `color.bg.raised` |
| `size.viewfinder.corner` | 24 | The length of one QR viewfinder corner mark |

- **R-32-350** The table above is the complete size set. A screen MUST NOT invent a height, a width
  or an icon size.
- **R-32-360** Every interactive element MUST present a touch target of at least 48 by 48 logical
  pixels, which is the value side of `R-30-290`. The reason, stated correctly: Android publishes
  48dp by 48dp as its recommended minimum, and Apple publishes 44 by 44 points as the **default**
  control size with 28 by 28 points as the **minimum**. 48 therefore satisfies Android's
  recommendation, exceeds Apple's default, and doubles the 24 by 24 CSS pixel floor of WCAG 2.2
  success criterion 2.5.8. Any rule that calls 44 the Apple minimum states a wrong reason for a
  right number. One measured exception: a control inside the 44 point `CupertinoNavigationBar`
  MUST be at least 48 wide and fills the bar's 44 height, per `R-33-076` (2026-09-08).
- **R-32-361** A visual element MAY be smaller than its target, per `R-30-291`. A 20 chevron sits
  inside a 48 target, and a 3 wide state bar is not interactive at all (amended 2026-09-09, per
  `R-03-100`).
- **R-32-362** Two adjacent targets MUST be separated by at least `space.1`, per `R-30-292`. So the
  pitch of adjacent key caps is the cap width plus `space.2`, which is 56 where a key
  cap sits at its 48 floor. The pitch is a formula and
  not a constant, because `R-31-09-15` grows a cap with its label and `size.keycap`
  is a minimum. A wider label therefore widens the pitch, and a target MUST NOT
  shrink to absorb it, per `R-32-363`. What gives way instead belongs to the surface: the key row
  scrolls, per `R-32-536` (amended 2026-09-10 per `R-03-116`: the chord key at its own 56 floor,
  and the Shortcuts palette that grew its layer, are both retired).
- **R-32-363** A large text scale MUST NOT shrink a target below 48, per `R-30-741`.

## 6. Icons

| Fact | Value |
| --- | --- |
| Set | Material Symbols, **Rounded** style, weight 400, `FILL` axis 0, `GRAD` 0 |
| Licence | Apache-2.0, `https://github.com/google/material-design-icons/blob/master/LICENSE` |
| Delivery | the Flutter package `material_symbols_icons`, Apache-2.0, version `4.2960.0` |
| Dart access | `Symbols.<name>` from that package |
| Why not SF Symbols | Apple's terms do not grant a cross-platform app the right to ship the glyphs to Android, so it is disqualified |
| Why not Flutter's bundled `Icons` | it lacks `splitscreen_right` and `splitscreen_bottom`, which the pane action sheet needs for `Split right` and `Split down` |

- **R-32-400** The app MUST use Material Symbols Rounded at weight 400 with `FILL` 0, from the
  package and version above. It MUST NOT mix a second icon set, and MUST NOT use SF Symbols.
- **R-32-401** The map below is normative. A screen MUST NOT use a name outside it. A new action
  adds a row here first. One glyph MAY serve two purposes, and several already do. A native control
  that the operating system draws supplies its own glyph, and that glyph is outside this map,
  because it is not an icon the app chose; `R-32-400` does not reach it. Every icon the app draws
  itself comes from this map, with one exception, and it is the only one. A platform navigation
  component owns the back glyph, the back label and the back gesture, per `R-33-070`, so this map
  holds no `Back` row. That exception is narrow on purpose: Flutter draws that control, not the
  operating system, so the carve-out above cannot reach it.

| Purpose | Material Symbols name |
| --- | --- |
| Scan a QR code | `qr_code_scanner` |
| Show a QR code, Host side only | `qr_code_2` |
| Enter the phrase by hand | `password` |
| Locked | `lock` |
| Unlock, the action | `lock_open` |
| Biometric, face reported | `face` |
| Biometric, fingerprint reported | `fingerprint` |
| Biometric, iris reported | `visibility` |
| Biometric, type not reported | `lock` |
| A computer | `computer` |
| A workspace | `folder` |
| A tab | `tab` |
| A pane | `splitscreen` |
| An agent | `smart_toy` |
| Split right | `splitscreen_right` |
| Split down | `splitscreen_bottom` |
| Create, the floating action button of `R-32-588`, spoken `New` | `add` (amended 2026-09-09 by the product owner, per `R-03-109`, for an app bar action; restored 2026-09-10, per the corrected `R-03-109`: the floating button stays on both platforms) |
| Create a space | `create_new_folder` |
| Create a tab | `tab_new_right` |
| Create a pane, the menu item | `splitscreen_add` |
| Zoom this pane | `zoom_out_map` |
| Close, dismiss, cancel | `close` |
| Close pane, destructive | `delete_outline` |
| Forget this computer, destructive | `delete_outline` |
| Mark as seen | `done_all` |
| Rename | `drive_file_rename_outline` |
| Send | `send` |
| Keyboard | `keyboard` |
| Arrow up | `arrow_upward_rounded` |
| Arrow down | `arrow_downward_rounded` |
| Arrow left | `arrow_back_rounded` |
| Arrow right | `arrow_forward_rounded` |
| Control | `keyboard_control_key` |
| Escape | none exists; use the text cap `esc`, per `R-32-403` |
| Copy | `content_copy` |
| Paste | `content_paste` |
| Select all | `select_all` |
| Scroll to the bottom | `vertical_align_bottom` |
| Alerts | `notifications` |
| An agent needs you | `notifications_active` |
| Alerts are off | `notifications_off` |
| Settings | `settings` |
| Appearance | `palette` |
| Terminal text size | `format_size` |
| Haptics | `vibration` |
| Quiet hours | `bedtime` |
| Paired phones | `devices` |
| This phone | `smartphone` |
| Remove a phone | `phonelink_erase` |
| The relay | `dns` |
| Connected | `cloud_done` |
| Connecting | `cloud_sync` |
| Disconnected | `cloud_off` |
| Disconnect, the action | `link_off` |
| Error | `error` |
| Warning | `warning` |
| A neutral disclosure, not a warning or an error | `info` |
| Agent `idle` | `radio_button_unchecked` |
| Agent `working` | `autorenew` |
| Agent `blocked` | `front_hand` |
| Agent `done` | `check_circle` |
| Agent `unknown` | `help` |
| Pane actions, the overflow | `more_vert` |
| Search panes | `search` |
| Pair a computer | `add` |
| Camera flash | `flash_on` and `flash_off` |
| About pairing | `help` |
| Try again | `refresh` |
| Reconnect now | `restart_alt` |
| Diagnostics | `network_check` |
| Expand, collapse | `expand_more` and `chevron_right` |
| The breadcrumb separator | none; it is the text glyph `›`, U+203A, per `R-32-572` |
| Bottom destination `Agents` | `smart_toy` |
| Bottom destination `Notifications` | `notifications` |
| Bottom destination `Settings` | `settings` |
| Host actions, `Plugin actions` | `extension` (the label became `Plugin actions` on 2026-09-09 per `R-03-055`, `docs/31-mockups/10-pane-actions.md` callout 5a) |
| Terminal shortcuts, `Shortcuts` | retired 2026-09-10 by the product owner, per `R-03-116`: the terminal app bar carries no keyboard control, per the retired `R-31-08-24`, and the key row's one expansion carries its own `more_horiz`/`close` pair. Was `keyboard` |
| A worktree | `fork_right` |
| Remove all notifications, destructive | `delete_sweep` (added 2026-09-08 by the product owner, per `docs/31-mockups/07-notifications.md` callout 3) |
| Remove one notification, destructive | `delete_outline` (added 2026-09-08 by the product owner; the destructive glyph, reused) |
| Notification actions, the row overflow | `more_vert` (added 2026-09-08 by the product owner; the overflow glyph, reused) |
| Read the last 20 lines | `text_to_speech` (added 2026-09-08 by the product owner; the sheet row drew `text_snippet`, which is a file glyph, not a reading action) |
| More keys, the bank-two toggle | `more_horiz` closed and `close` open, spoken `More keys` and `Fewer keys` (added 2026-09-08 by the product owner: the text cap `...` is three baseline periods whose ink centre sat 3.5 px under the cap centre in `key_row_bank_one_dark.png`; a glyph at `size.icon.md` centres like the arrow caps do; amended 2026-09-10 by the product owner, twice: the open state's text cap `abc` read as "type letters", then `expand_less` beside the `↑` cap read as one more arrow key, and both times the owner found no way to collapse; `close` means "close this" and nothing else on this row) |
| Terminal text size, the whole control | none; the control is the platform slider of `R-03-110`, which draws its own thumb and track (amended 2026-09-09 by the product owner, per `R-03-110`: the `remove` and `add` glyphs of the stepper's two buttons left this map with the stepper) |
| Status colours, the `Agents` app bar action that pushes the legend | `info` (added 2026-09-09 by the product owner, per `R-03-112`; the neutral disclosure glyph, reused) |
| Remove phones, the `Phones` app bar action that opens the choice surface | `delete_outline`, the glyph of `treat.destructive`, spoken `Remove phones` (added 2026-09-09 by the product owner, per `R-03-111`; the three menu items carry the same glyph) |
| Selected segment, the Android `SegmentedButton` mark | `check` (added 2026-09-09 by the product owner, per `R-03-059`: the component's own `Icons.check` is the MaterialIcons font, which the app does not bundle, so the theme's `selectedIcon` names this glyph) |
| A key named in a sentence | none; it is the inline key of section 7.33, a text cap in `type.mono.key`, per `R-32-599` (added 2026-09-09 by the product owner, per `R-03-103`) |

- **R-32-402** Icon sizes come from `R-32-350`: `size.icon.sm` for a status icon, a treatment
  icon, an inline icon or a badge icon; `size.icon.md` for a control icon, a chevron, an expander
  and the destructive treatment icon; `size.icon.lg` for an app bar icon and a bottom-navigation
  icon; `size.icon.hero` for the `/lock` biometric glyph. An icon MUST be optically centred in its
  target, which means the icon box centre sits on the target centre and any glyph-internal padding
  is not compensated by a layout offset. A leading icon beside a single-line label MUST align to
  that label's vertical centre, per `Treatment`'s own icon-and-label row (`treatments.dart`,
  R-32-506) — Material Symbols carries no usable text baseline for a non-text `Icon` widget, so
  centring against one line is this app's accepted stand-in for "the first text baseline". A
  leading icon beside a label that wraps to more than one line MUST instead align to the top of
  that label's first line, so the icon marks the block's start rather than floating at its
  midpoint.
- **R-32-403** Neither Material Symbols nor any candidate set carries an Escape glyph. The escape
  key MUST be drawn as the text cap `esc` in `type.mono.key`. `keyboard_capslock` MUST NOT be
  pressed into service, because it means something else.
- **R-32-404** An icon MUST NOT be the only carrier of meaning, per `R-30-141`. The five agent-state
  icons above are distinct in shape as well as in hue, per `R-30-401`: a hollow ring, a circular
  arrow, a raised hand, a tick in a circle, a question mark in a circle.
- **R-32-405** An icon takes `color.fg.primary` by default, the row's `color.status.*` when it
  carries a state, `color.fg.on_accent` on an accent fill, and `color.fg.disabled` when its control
  is disabled. It MUST NOT take `color.accent.text` on a raised or high surface, per `R-32-124`.
- **R-32-406** The attention badge icon MUST be `notifications_active`, not `error`. The badge
  counts agents that need a person; an error glyph in a warning hue claims a failure that did not
  happen.
- **R-32-407** The lock screen glyph MUST be `lock` in every state, and MUST NOT change with the
  biometric type (amended 2026-09-16 by the product owner: the screen first painted the lock, then
  swapped in a face once `getAvailableBiometrics()` answered, and the swap read as a defect; until
  then this rule chose `face`, `fingerprint` or `lock` from the reported type). The primary label
  still comes from the biometric type the operating system **reports at run time**, never from the
  platform: an iPhone with Touch ID reports a fingerprint and an Android phone with face unlock
  reports a face, so a platform-keyed label is wrong on both. `local_auth`
  `getAvailableBiometrics()` returns `BiometricType`; when only a `strong` or `weak` classification
  arrives, the app MUST use the generic label and MUST NOT guess a sensor.
  `docs/22-platform-integration.md` owns the call and `docs/31-mockups/04-lock.md` owns the screen.

### The app icon and the notification icon

Brand art is not documentation, so it lives at the repository root in `assets/icon/`, not under
`docs/`. Authored masters are in `assets/icon/src/`. Everything in `assets/icon/export/` is derived
from them and MUST NOT be hand-edited.

#### Published source

| File | Size | Format | Role |
| --- | --- | --- | --- |
| [`remote.svg`](../assets/icon/src/remote.svg) | 512 x 512 viewBox | SVG, vector | The published master: the brand mark alone, as published at `https://herdr.dev` (source URL in the file's own header comment). Its path MUST NOT be redrawn, traced or edited. |
| [`remote.png`](../assets/icon/src/remote.png) | 1254 x 1254 | 8-bit RGBA | `remote.svg` rasterized. It is already the brand's own tile composition (`https://herdr.dev/assets/logo.png`): the bust starts at 20.3% from the left and 27.1% from the top, and bleeds off the right and bottom edges. |
| [`android_notification.png`](../assets/icon/src/android_notification.png) | 1254 x 1254 | 8-bit RGBA | The near-white silhouette for the status-bar glyph only, per `R-32-420`. |
| [`android_background.png`](../assets/icon/src/android_background.png) | 1254 x 1254 | 8-bit RGB | The flat background colour of `R-32-411` as a raster. `generate.py` regenerates it. |

- **R-32-410** `assets/icon/src/` MUST be the single source for every icon the product ships. Run
  `python assets/icon/generate.py` from the repository root after any source change. It needs only
  Pillow.
- **R-32-411** The launcher background is `#17171a`, the Ink theme's `color.bg.base`, carrying the
  ground grid of `R-32-332` as 1 dp lines in `#35353d`, the Ink theme's `color.border.subtle`, at 8
  cells per side (amended 2026-09-16 by the product owner: the first export used 1 px lines in
  `color.bg.grid`, `#202024`, which measure 1.05:1 and vanished at launcher size, so the tile read
  as plain; the icon takes the next Ink line token and a device-independent width so the grid is
  visible behind the mark on both platforms); the mark is `#cba6f7`, the Ink theme's
  `color.accent.primary`. The icon is the welcome
  hero in miniature, the mark on the gridded ground, so the tile on the launcher and the first
  screen the person opens read as one surface. The eye of the mark is a cutout, so the ground shows
  through it and the `>_` reads as a prompt on a dark terminal. Neither value follows the theme.
  Decided 2026-09-10 by the product owner, who asked for the ink ground, the grid texture and the
  purple mark after the spot-filled tile.
- **R-32-412** The icon MUST NOT change with the theme. `R-32-010` gives the interface three modes;
  a launcher icon has one appearance, because the operating system draws it.
- **R-32-413** Every raster's true bounding box MUST be measured at an alpha floor of 10, not at
  alpha greater than zero. `remote.png` measures `(255, 340)` to `(1253, 1253)` on its 1254 canvas,
  with 777 opaque pixels on its right edge and 494 on its bottom edge: that is the bleed.
  `generate.py` MUST fail when those values drift.
- **R-32-414** The composition is the tile, whole, on every canvas. The mark's two crop edges
  coincide with the canvas edges, so no crop line is ever visible inside an icon. Nothing is
  centred, shrunk or clipped by this repository; a platform mask crops the body.
- **R-32-415** The Android adaptive foreground and monochrome layers MUST be the whole tile scaled
  to the whole 108 dp canvas. The 72 dp mask circle then shows the head and cuts the body, which is
  the design. The adaptive-icon safe zone does not apply to a full-bleed tile; the bleed is
  intentional.
- **R-32-416** `generate.py` MUST verify, per pixel and at every density, that the mark's leftmost
  point (the muzzle) and its topmost point (the horn) lie inside the 72 dp mask circle, so no
  launcher shape ever cuts the head.
- **R-32-417** The iOS export MUST be 1024 x 1024, sRGB, flattened to RGB: the tile composited on
  the background. iOS applies its own corner mask.
- **R-32-418** Android MUST ship the adaptive icon alone: background, foreground and monochrome
  layers on the 108 dp canvas at `mdpi` 1.0, `hdpi` 1.5, `xhdpi` 2.0, `xxhdpi` 3.0 and `xxxhdpi`
  4.0. No legacy `ic_launcher.png` raster ships, because `R-20-026`'s floor is far above API 26.
- **R-32-419** The Google Play store icon MUST be 512 x 512, a 32-bit PNG with a fully opaque alpha
  channel, in the same composition as the iOS export.
- **R-32-420** The status-bar icon MUST be pure white with the shape in the alpha channel only,
  unmasked, its bounding-box height at 0.85 of the 24 dp canvas and centred. Android discards its
  colour and applies its own tint.
- **R-32-421** iOS MUST NOT receive a separate notification icon. iOS shows the app icon beside a
  notification.
- **R-32-422** Regeneration MUST reproduce the committed exports exactly from the sources and the
  constants above. A change to the art MUST regenerate the full set, never a subset by hand.

#### Contrast

- **R-32-423** The mark measures `8.81:1` against the background (`#cba6f7` on `#17171a`, WCAG
  relative-luminance formula), clearing the 4.5 text floor and the 7.0 enhanced floor alike; the
  grid line measures `1.47:1` against the ground and is decorative, so it carries no floor, per
  `R-32-114`. A future art change MUST re-measure this ratio, because it is a property of the
  specific mark and background pair, not a standing guarantee.

#### The brand mark inside the app

- **R-32-426** `assets/icon/export/brand/ram.png` is the mark's true bounding box as a white
  silhouette with alpha, 1024 px wide. It is copied to `app/assets/brand/ram.png`
  (`docs/22-platform-integration.md` section 6A) and drawn by `widgets/brand_mark.dart`, tinted with
  a chrome ink through `BlendMode.srcIn`. Unlike the launcher, this use takes the theme's ink,
  because it sits inside the chrome. The widget MUST sample with `FilterQuality.low`, never
  `medium` or `high`: the mipmap path of the Android renderer drew a 1 px line along the top edge
  of the mark (owner observation, measured on the emulator, 2026-09-03), and bilinear sampling
  draws none.
- **R-32-427** The bust's right and bottom edges are the published crop. A layout MUST place both
  on a real edge: the screen's right edge, a rule line or a card edge. The mark MUST NOT float in
  open space and MUST NOT sit between two text blocks; the retired `R-32-424` records the review
  that forbids that. Section 7.31 fixes the welcome hero composition, and section 7.19 fixes the
  empty-state watermark of `R-32-554` (amended 2026-09-09, per `R-03-107`). No other placement is
  permitted.

## 7. Components

### 7.1 The five interaction states

- **R-32-500** Every interactive component MUST define five states: default, pressed, disabled,
  focused and error. A component with no error condition states that it has none.
- **R-32-501** Pressed MUST arrive over `motion.duration.fast` and leave at
  `motion.duration.instant`, per `R-32-609`, and MUST fire the haptic that `docs/30-ux-spec.md`
  assigns to that control. Three cases, and no fourth:
  - A control filled with `color.bg.high` presses to `color.accent.primary` with its label in
    `color.fg.on_accent`.
  - A control already filled with `color.accent.primary` presses to that fill plus a
    `color.fg.primary` overlay at `opacity.press`.
  - A control with no fill presses to `color.bg.high` with its label in `color.fg.primary`.

  (Amended 2026-09-08 by the product owner.) The third case reaches every pressable that sits on a
  surface rather than in a fill of its own: the list row of section 7.4 on `color.bg.base` or in a
  space block, the tier 1 header of section 7.23, and the destination tap of a strip on
  `color.bg.raised`. The ghost button of section 7.28 and the text action of `R-32-526` are the two
  named exceptions, and their `color.accent.soft` wash is the token's own use. The filled button
  MUST NOT invert to a `color.fg.primary` fill on press: that is the web hover idiom of the Herdr
  site, `R-32-503` forbids a hover state, and the pair `color.bg.base` on `color.fg.primary` is not
  in the table of `R-32-150`.

  A text field has no pressed state: a tap focuses it, and `R-32-503` owns what that looks like.

  (Amended 2026-09-09 by the product owner, per `R-03-059`.) A button is the platform's own widget
  and takes the platform's own press: on Android the Material ink overlay, on iOS the Cupertino
  press fade. The theme of `app/lib/app.dart` hands the Material overlay the case above that fits
  the button, so the second case still describes the filled button and the `color.accent.soft`
  wash still describes the text and ghost buttons, but the timing, the scale and the drawn fill of
  `R-32-609` reach a row, a header and a strip, never a button. The key cap became a platform
  button on the same date and left this list. The app MUST NOT imitate a platform button's pressed
  state.
- **R-32-502** Disabled MUST be the whole control at `opacity.disabled` with no colour change, and a
  disabled control MUST NOT be the only signal: one line of text says why, which every mockup state
  table already supplies. (Amended 2026-09-09 by the product owner, per `R-03-059`.) A button takes
  the dim from the theme's disabled colours: the same fill, label and border tokens at
  `opacity.disabled`, never a second colour. On iOS `cupertino_ui` 1.0.1 recolours a disabled
  button to a system grey, so the button widget hands the component its own fill back and dims the
  whole control itself, as `app/lib/widgets/theme/chrome_icon_action.dart` already does.
- **R-32-503** Focused MUST be `border.focus` at `radius.sm`, drawn outside the control boundary on
  the parent surface, per `R-32-127`. The app MUST NOT rely on a hover state, per `R-30-718`.
  (Amended 2026-09-08 by the product owner.) "Outside the boundary" means the ring's inner edge sits
  on the control's edge and its outer corner is `radius.sm` plus `border.focus`, so it follows the
  control's own corner; the ring MUST NOT add to the control's layout, so focus never moves a
  neighbour, and it MUST NOT be painted under the control's fill, where an opaque fill hides it. A
  focused control MUST activate on Enter and Space, so a person on an external keyboard can do what
  a finger does. (Amended 2026-09-09 by the product owner, per `R-03-059`.) The ring is the focus
  state of a row, a header and a strip, the pressables the app draws itself. A button, and the key
  cap since the same date, keeps the platform's own focus response, the Material focus overlay or
  the Cupertino focus halo, and activates on Enter and Space through the platform widget.
- **R-32-504** Error MUST be `border.error` on the control that failed, plus a `treat.error` message
  under it. The control MUST keep what the person typed, per `R-30-910`.
- **R-32-505** The accessibility label pattern, which `R-30-717` requires and this rule fixes:
  - An icon-only control: the action name alone, for example `Pane actions`.
  - A row: `<label>, <value>`, for example `Phone to relay, connected, 38 milliseconds`.
  - A switch row: `<label>, on` or `<label>, off`, never a bare `switch`.
  - A destructive action: `<name>, destructive`.
  - A status icon: the state word alone, per `R-30-716`.

### 7.2 Treatments

| Token | Composition |
| --- | --- |
| `treat.ok` | Label in `color.fg.primary`, leading `check_circle` at `size.icon.sm` in `color.status.ok`, gap `space.2` |
| `treat.warning` | Label in `color.fg.primary`, leading `warning` at `size.icon.sm` in `color.status.warning`, gap `space.2` |
| `treat.error` | Label in `color.fg.primary`, leading `error` at `size.icon.sm` in `color.status.error`, gap `space.2`, plus a `border.attention` leading bar in `color.status.error` when the message sits in a strip |
| `treat.destructive` | Label in `color.fg.primary` on a row; on a button of `R-32-526` the label keeps the button's own ink, the same `color.accent.text` its neighbour takes (amended 2026-09-09 by the product owner, per `R-03-104`: two buttons side by side share one label ink); leading `delete_outline` at `size.icon.md` in `color.status.error`, gap `space.3`; the glyph alone carries the hue and no bar is drawn, on a row or on a button, per `R-32-527` (amended 2026-09-09 by the product owner, per `R-03-058` and `R-03-100`: a leading bar is a state bar) |

- **R-32-506** The four compositions above are the value side of `R-30-140` to `R-30-143`. A
  message, a state word or a destructive label MUST use one of them and MUST NOT use a bare status
  colour.
- **R-32-589** `Disconnect` is not destructive, so its control MUST NOT take `treat.destructive`.
  It is a plain action row: the label in `color.fg.primary`, `link_off` at `size.icon.md` in
  `color.fg.primary`, no `border.attention` bar, no red ink and no red fill. `Forget` and `Remove`
  are destructive and keep `treat.destructive`, so the three actions MUST NOT be allowed to look
  alike. A person who reads a red bar beside `Disconnect` expects to lose the pairing, which a
  disconnect does not touch.

### 7.3 App bar, with the connection indicator

| Part | Value |
| --- | --- |
| Height | `size.appbar` |
| Surface | `color.bg.base` |
| Bottom edge | `border.hairline` in `color.border.strong`, per `R-32-115` |
| Title | `type.heading` in `color.fg.primary`, left aligned, truncating in the middle |
| Leading control | `size.icon.lg` in `color.fg.primary`, target `size.target.min`; the glyph, the label and the gesture come from `R-33-070` where the control goes back |
| Trailing controls | `size.icon.lg` in `color.fg.primary`, target `size.target.min` each, gap `space.1` |
| Horizontal inset | `space.4` |
| Live bar | the state bar of section 7.29, `border.attention` wide, `size.icon.md` high, the text line it sits beside. It sits before the title, on the leading side, `space.2` before the title text, the way a list row puts its bar in the leading slot before its name (`R-32-592`, `R-32-597`), and it MUST NOT sit among the trailing controls. `color.status.ok` when live, `color.status.warning` when the last event is older than 60 seconds, `color.status.error` when the relay is lost (amended 2026-09-09 by the product owner, per `R-03-100`: the live dot is retired; the bar is the app's one state shape; amended 2026-09-10 by the product owner, per `R-03-121`: it sat among the trailing controls until then, at the right of the terminal bar and before the name everywhere else) |
| Selection variant | the same height and surface; leading `close`, title `<n> lines selected` in `type.body.strong`, trailing text actions in `type.label` in `color.accent.text` |

- **R-32-510** The app bar MUST be `color.bg.base` with a `color.border.strong` bottom edge. That
  edge measures 6.07 in dark and 5.37 in light, where the surface step it replaces measured 1.21 and
  1.15. The change also moves every app bar text action onto `color.bg.base`, where
  `color.accent.text` is permitted at 4.60 and 4.64.
- **R-32-511** The live bar MUST carry the connection word as its semantics label, per `R-30-716`
  (amended 2026-09-09, per `R-03-100`: it was the live dot). The terminal status strip also
  carries that word, and the duplication is accepted here for one reason: the two sit in different
  regions and the traversal order of `R-30-719` visits the app bar, then the grid, then the strip,
  so the word is never spoken twice in one node. A bar inline with text that already names the
  same state MUST be excluded from the semantics tree instead.
- **R-32-512** The app bar MUST NOT carry a status hue as a fill, and MUST NOT hold more than three
  trailing actions, plus the conditional alerts-off marker of `R-30-515`, which is a state, not an
  action (clarified 2026-09-09, per `R-03-109` and `R-03-112`: the `Agents` bar holds `Status
  colours`, `New` and search, and the marker joins them only while alerts are denied).

### 7.4 List row, with a status badge and a timestamp

On a settings screen the row values below reach Android only (noted 2026-09-08 by the product
owner's design pass). There an iOS row is one `CupertinoListTile` inside the `CupertinoListSection`
of `docs/33-platform-chrome.md` `R-33-073`, and that tile keeps the platform's own height, inset and
type; the divider row below already says so. A content row of an agent, host or phone list takes
the table on both platforms. Note, 2026-09-10 per `R-03-115`: Workspace and pane-switcher rows
use one line; Priority agent rows keep two.

| Part | Value |
| --- | --- |
| Height | `size.row.two_line` with a secondary line, `size.row.one_line` with one line of text; the height follows the lines the row declares, not the lines it shows, so a row keeps its height while a spinner replaces its label (clarified 2026-09-08 by the product owner: the widget drew both at a 56 that is in no table, against `R-32-350`) |
| Surface | `color.bg.base` |
| Divider | `border.hairline` in `color.border.subtle`, inset `space.4` from the leading edge; the last row of a list section carries no divider (decided 2026-09-03 by the product owner); on iOS no row draws it, because the platform list section of `R-33-073` draws the one separator between rows, from that same `space.4` inset (added 2026-09-08) |
| Leading status icon | `size.icon.sm` in the row's `color.status.*` |
| Primary line | `type.body.strong` in `color.fg.primary` |
| Secondary line | `type.caption` in `color.fg.secondary` |
| Trailing state word | `type.micro` in `color.fg.secondary`, UPPER, unless a pane rule overrides it; an agent row uses `type.label` `color.fg.primary` in Priority and `type.body` `color.fg.primary` in Workspace and the pane switcher |
| Trailing age | `type.caption` in `color.fg.secondary` |
| Trailing column | in Priority, the state word is on line one and the age is on line two, with one right edge and each on its line's alphabetic baseline; in Workspace, the state word and optional age share the row's one baseline with `space.2` between them (amended 2026-09-10 per `R-03-115`) |
| Pane row height | Workspace and pane-switcher rows are one line plus `space.3` above and below, with `size.target.min` as the floor: 48 at the default text scale; Priority agent rows are two lines plus the same inset: 64 (amended 2026-09-10 per `R-03-115`) |
| Trailing chevron | `chevron_right` at `size.icon.md` in `color.fg.secondary` |
| State bar | the state bar of section 7.29: `border.attention` in the row's `color.status.*`, full row height, flush to the leading edge, painted over the fill so the content keeps its `space.4` inset; the one bar a row carries, and the row's one state indicator (amended 2026-09-09 by the product owner, per `R-03-100`: the accent unread bar of `R-03-058`, the connection dot and the status dot are retired; the bar carries the state, the word beside it names the state) |
| Unread row | `type.body.strong` on the primary line and a `color.accent.soft` wash; no second bar (amended 2026-09-09 by the product owner, per `R-03-100`: weight and wash carry unread, never a bar) |
| Selected row | `color.accent.soft` wash; the content keeps its `space.4` inset, so selecting a row never moves its text (added 2026-09-08 by the product owner: this is the "one that is live" anatomy `docs/31-mockups/05-host-list.md` callout 8 cites; amended 2026-09-09, per `R-03-100`: the `border.accent` leading bar of the selected row is retired, because a row carries one bar and that bar is the state's) |
| Pressed | `color.bg.high` fill, per `R-32-501`'s third case, with the timing and the scale of `R-32-609` (added 2026-09-08 by the product owner) |
| Horizontal inset | `space.4` |
| Gap between the icon and the primary line | `space.3` |

- **R-32-515** A row MUST expose one semantics node whose label follows `R-32-505`, and a row
  action of `R-30-296` MUST also exist as a named custom semantics action. Neither platform menu
  exposes a closed row's actions to the accessibility tree, so the app MUST supply that action
  itself. A screen-reader user cannot long press a row, so an action with no spoken path does not
  exist.
- **R-32-516** A row that needs attention MUST carry its state bar in `color.status.blocked` or
  `color.status.done` in addition to its icon and its word. Three signals, per `R-30-501`
  (amended 2026-09-09 by the product owner, per `R-03-100`: the attention bar and the state bar are
  one bar; a `blocked` or `done` state bar is the attention bar).
- **R-32-517** (added 2026-09-08; amended 2026-09-10 per `R-03-115`) In `Priority`, the state
  word and age MUST form one right-aligned trailing column: word on line one and age on line two,
  with equal right edges. Each MUST share the alphabetic baseline of the text beside it. The age
  MUST NOT be part of the breadcrumb run. In `Workspace`, every pane row MUST use one line. An
  agent MUST put kind, `space.2` and pane name on the leading side. Its state word and optional
  age MUST trail on that baseline with `space.2` between them. A shell MUST put its display name,
  `space.2` and optional `title` on that baseline. The pane switcher MUST use the same line,
  without an age. A Workspace or switcher pane row MUST be 48 high at the default text scale. A
  Priority agent row MUST stay 64 high. Both heights are the text lines plus `space.3` above and
  below, with `size.target.min` as the floor. A notification row of
  `docs/31-mockups/07-notifications.md` carries its state word inside its phrase and has no
  trailing word, so its age stays at the trailing edge of line one on the phrase's baseline.
- **R-32-705** The connection state of a computer row has exactly three states, because `R-03-043`
  saves every paired computer and keeps at most one of them connected. Each state is the state bar
  of section 7.29 in the token below, beside the row's state word (amended 2026-09-09 by the
  product owner, per `R-03-100`: the connection dot, its two shapes and its two diameters are
  retired). Every state sits on `color.bg.base`, which is the row surface:

  | State | Meaning | Colour token | Dark and light |
  | --- | --- | --- | --- |
  | `connected` | the one computer this phone is attached to | `color.status.ok` | 8.51 / 3.70 |
  | `saved` | paired, and not the connected computer | `color.status.unknown` | 5.58 / 4.53 |
  | `offline` | the phone has no network, so no computer can be connected | `color.status.unknown` | 5.58 / 4.53 |

  `saved` is the most common state on the screen, and it takes `color.status.unknown` because this
  phone knows nothing live about a saved computer: `R-03-046` forbids a live status on its row, and
  grey is the colour the app already gives an unknown state everywhere else (section 7.29). It
  MUST NOT take `color.status.idle`, `color.status.error` or `color.status.warning`. Nothing failed,
  and the person is not asked to act (amended 2026-09-10 by the product owner, who saw a
  disconnected row in the same green as the connected one and called the two "no different":
  `color.status.idle` shares the `ok` hue, per `R-32-130`, so the bar alone said nothing).

  The word beside the bar still separates the three states, per `R-30-141`; the row's secondary
  line names `offline` where the bar cannot. Now the hue separates `connected` from the other two
  as well, so a glance at the list finds the one live computer.

  Both pairs already pass in `R-32-150` against the 3.0 indicator floor of `R-30-130`, so this rule
  adds no pair.

  A mockup owns the character it draws for each state, per `R-32-004`. This document owns the
  rendered appearance and MUST NOT name a character.
- **R-32-706** The last-seen line that `R-03-046` puts on a saved row MUST use the secondary line of
  the table above, which is `type.caption` in `color.fg.secondary`. It MUST NOT take a dimmer ink,
  and this document adds no token for one. Two reasons, and the first is arithmetic. The only ink
  below `color.fg.secondary` is `color.fg.disabled`, which measures 3.23 in dark and 2.64 in light
  on `color.bg.base`, so it misses the 4.5 text floor, and `R-32-123` reserves it for an inactive
  control and a placeholder. A last-seen time is meaningful text, because it is the only part of the
  row that says when the state was true. `R-32-100` forbids a value invented between those two
  inks, so no permitted dimmer ink exists. Second, the words MUST carry the staleness, because a
  fainter colour tells a screen reader nothing, per `R-30-141`. The line names the time it was seen,
  and that is the signal.

### 7.5 Badge

Two badges. The inline badge sits in a row or a header, trailing a count or a name. The tab badge
sits on the `Notifications` destination of the bottom navigation and is the platform's own
(amended 2026-09-09 by the product owner, per `R-03-059`: he asked whether the recoloured bell
with a bare count was how a native tab badge looks, and neither platform draws one that way).

| Part | Inline badge | Tab badge |
| --- | --- | --- |
| Icon | `notifications_active` at `size.icon.sm` in `color.status.blocked` | none: the destination glyph, in the bar's own ink, selected or not |
| Count | `type.micro.strong` in `color.fg.primary` | Flutter's `Badge` default label style in `color.fg.on_accent` (`colorScheme.onError`) |
| Gap | `space.1` | none: the `Badge` default offset, at the glyph's top-end corner |
| Fill | none | a filled circle in `color.status.error` (`colorScheme.error`), the `Badge` default geometry |
| State word | `type.micro` UPPER `fg.secondary` | none |

- **R-32-518** An inline badge MUST NOT be a filled pill, per `R-30-142`. The count keeps
  `color.fg.primary` and the hue lives in the icon. The tab badge MUST be the platform's own:
  Flutter's `Badge` with no colour, style or geometry override, over an unrecoloured glyph. It is
  the Material 3 `NavigationBar` destination badge, and it is the red circle a `CupertinoTabBar`
  item carries on iOS, which has no badge widget of its own (amended 2026-09-09 by the product
  owner, per `R-03-059`; before that date the destination drew the inline badge with the bell in
  `color.status.blocked`). The count of either badge is exact and MUST NOT be capped, per
  `R-30-508`.
- **R-32-707** A badge on a saved row MUST look exactly like a badge on the connected row. Under
  `R-03-046` that count is remembered from the last connection instead of live, and the appearance
  MUST NOT change to say so. Three reasons. A dimmed badge is not reachable inside this palette:
  the count would fall to `color.fg.disabled` at 3.23 and 2.64, which `R-32-123` forbids for
  meaningful text, and the icon has no dimmer status hue, because `R-32-100` forbids inventing one.
  `R-30-501` exists to make attention impossible to miss, and a dimmed badge weakens the one signal
  that rule strengthens. The row already states its staleness in words, per `R-32-706`, so a second
  staleness signal would only make the first one quieter.

### 7.6 Segmented control

| Part | Value |
| --- | --- |
| Widget | the platform's own control, per `R-03-059`: `SegmentedButton` on Android, `CupertinoSlidingSegmentedControl` on iOS, per the control map of `docs/33-platform-chrome.md` `R-33-033`; on Android every value below reaches it through `segmentedButtonTheme`, and the app draws no segment of its own (added 2026-09-09 by the product owner) |
| Height | the component's own on both platforms, per the `R-03-059` addendum of 2026-09-09: on Android Material 3's 40 inside its 48 tap target, on iOS the component's own (was `size.target.min` through the theme, a fixed box the addendum forbids) |
| Track | Android: `color.bg.base`, `border.hairline` in `color.border.strong`, from the theme, in the component's own stadium shape (amended 2026-09-09 per the `R-03-059` addendum: was `radius.sm` through the theme; the theme sets colours and type only); iOS: the component's own track and thumb |
| Segment count | two to five, equal width |
| Unselected label | `type.label` in `color.fg.primary` |
| Selected segment | Android: fill `color.accent.primary` through the theme, marked by the platform's own selected glyph, the `check` of the `R-32-401` icon set through `selectedIcon`, no underline (amended 2026-09-09, per `R-03-059`: the drawn `space.1` inset and the `border.accent` underline were the app's own segment); iOS: the component's thumb |
| Selected label | `type.label` in `color.fg.on_accent` on Android; the component's own on iOS |

- **R-32-520** The selected segment MUST be identified by its fill and by the semantics state
  `selected`, never by colour alone. Its fill measures 3.92 in dark and 4.64 in light against a
  `color.bg.base` track, which clears the 3.0 indicator floor. The track MUST therefore be
  `color.bg.base` with a `color.border.strong` boundary: on a `color.bg.high` track the same fill
  measures 2.45 in dark and fails, and an unselected label there could not use
  `color.fg.secondary` either. (Amended 2026-09-09, per `R-03-059`.) The platform control supplies
  the `selected` state and, on Android, the selected glyph as a third mark.
- **R-32-521** Each segment MUST present a `size.target.min` target, and the platform control
  supplies it: Material's tap-target padding on Android, the component's own height on iOS, where
  the strip of section 7.26 keeps the target whole. The theme MUST NOT set the control's height
  (amended 2026-09-09, per the `R-03-059` addendum).

### 7.7 Switch row

| Part | Value |
| --- | --- |
| Height | `size.row.one_line` |
| Label | `type.body` in `color.fg.primary` |
| Track, on | `color.accent.primary` |
| Track, off | `color.bg.high` with `border.hairline` in `color.border.strong`, per `R-32-112` |
| Thumb | `color.fg.on_accent` when on, `color.fg.primary` when off |
| Target | `size.target.min` for the whole row |

- **R-32-522** A switch that is off MUST carry its border. Without it the off track measures 1.60
  and 1.43 against the screen and cannot be seen.

### 7.8 Primary button

| Part | Value |
| --- | --- |
| Widget | the platform's own button, per `R-03-059`: `FilledButton` on Android, `CupertinoButton.filled` on iOS, built by `app/lib/widgets/app_filled_button.dart` alone; every value below reaches it through the theme of `app/lib/app.dart`, `filledButtonTheme` on Android and `CupertinoThemeData.primaryColor`, `primaryContrastingColor` and `textTheme.actionTextStyle` on iOS, and the widget sets no style of its own (added 2026-09-09 by the product owner) |
| Width | the screen width less `space.4` on each side |
| Height | the component's own on both platforms, per the `R-03-059` addendum of 2026-09-09: Material 3's 40 inside its 48 tap target on Android, `CupertinoButtonSize.large`, 48 with its label, on iOS. The theme sets no height (was `size.button.primary` through `filledButtonTheme`, a fixed box the addendum forbids) |
| Fill | `color.accent.primary` |
| Radius | the component's own on both platforms: Material 3's pill on Android, 12 on iOS; a platform component keeps its own corner, and no radius token of this document reaches it (amended 2026-09-09 per the `R-03-059` addendum: was `radius.sm` through the theme; the create control of `R-32-588` was the precedent) |
| Label | the platform's own label style of `R-32-212` in `color.fg.on_accent`, centred, as written (amended 2026-09-09 by the product owner, per `R-03-104`: was `type.mono.button` UPPER) |
| Loading | the label gives way to a `size.spinner` spinner in the label's ink; the control is disabled meanwhile, so it takes the dim of `R-32-502` (amended 2026-09-09, per `R-03-059`: a platform button has no "enabled but not pressable" state, and every caller already disables the button while its action is in flight) |
| Pressed | the platform's own response (amended 2026-09-09 by the product owner, per `R-03-059`): on Android the ink overlay, which the theme sets to `R-32-501`'s second case, `color.fg.primary` at `opacity.press` over the fill; on iOS the Cupertino press fade. No app-drawn fill and no scale (recorded 2026-09-08 by the product owner: the widget inverted to a `color.fg.primary` fill with a `color.bg.base` label, a hover idiom and an unmeasured pair) |
| Disabled | the same fill and label at `opacity.disabled`, no colour change, per `R-32-502`, through the theme's disabled colours (recorded 2026-09-08 by the product owner: the widget also swapped to a `color.bg.high` fill and a `color.fg.disabled` label, the double signal `R-32-331` forbids, and the dimmed grey label was near invisible on `/lock`) |

- **R-32-525** Exactly one filled control type exists, per `R-30-121`. Its fill is
  `color.accent.primary` and its label is `color.fg.on_accent`, at 5.84 in dark and 4.64 in light.
  (Amended 2026-09-09 by the product owner, per `R-03-059`.) That one type is the platform's filled
  button. Exactly two files build it, and no screen builds a third:
  `app/lib/widgets/app_filled_button.dart` for the primary button of this section, and
  `app/lib/widgets/key_row.dart` for the latched key cap of section 7.12, which takes the same
  fill and the same label ink for the one state that needs the platform's high emphasis (the
  second file was named 2026-09-10 per `R-03-118`; until then the latched cap used the tonal form
  and this rule named one file). A screen MUST
  compose one of those two widgets, and MUST NOT set a style on it: `filledButtonTheme` holds
  every value.
- **R-32-526** A text-only action is the platform's own label style of `R-32-212`, as written, in
  `color.accent.text`, at the platform component's own height, inset and corner on both platforms
  (amended 2026-09-09 by the product owner, per `R-03-104`: was `type.mono.button` UPPER, and the
  destructive form inked its label `color.fg.primary`; two text buttons side by side now share one
  label ink and differ by the glyph hue alone, per `R-32-527`; amended the same day per the
  `R-03-059` addendum: was `size.button.text` high with a `space.3` inset through the theme).
  `color.accent.text` clears 4.5 on all three surfaces in both themes, per `R-32-124`, so the same
  ink serves on `color.bg.base`, `color.bg.raised` and `color.bg.high`. (Amended 2026-09-08 by the
  product owner.) Disabled is the whole control at `opacity.disabled` with no colour change, per
  `R-32-502`; while an action is in flight the label gives way to a `size.spinner` spinner in the
  label's ink, like the primary button, and the control is not pressable meanwhile. A quiet sheet
  action MAY instead set `type.body.strong` in `color.fg.secondary` in the label's own case, which
  is the `Cancel` row of section 7.16.

  (Amended 2026-09-09 by the product owner, per `R-03-059`.) The text action is the platform's own
  button, `TextButton` on Android and a plain `CupertinoButton` on iOS, built by
  `app/lib/widgets/app_text_button.dart` alone, and `textButtonTheme` holds every colour value
  above, no type and no geometry (amended 2026-09-09, per `R-03-104`).
  Pressed is the platform's own response: on Android the ink overlay, which the theme sets to the
  `color.accent.soft` wash; on iOS the Cupertino press fade. It MAY carry a glyph of the `R-32-401`
  map at `size.icon.md` before its label, in the label's ink, with the platform's own gap
  (`TextButton.icon`). A destructive text action takes `treat.destructive`, per `R-32-506` and
  `R-32-527`: the glyph in `color.status.error`, the label in the button's own `color.accent.text`
  like its neighbour's, with no `border.attention` bar (amended 2026-09-09 by the product owner,
  per `R-03-058`: the bar beside a red glyph is two marks for one fact, and the owner named it a
  random line; amended the same day per `R-03-104`: until then the label took `color.fg.primary`,
  a second ink beside its sibling, which the owner named inconsistent). One iOS value does
  not come from the theme: `cupertino_ui` 1.0.1 inks a plain button in
  `CupertinoThemeData.primaryColor`, which is the fill token `color.accent.primary`, and that ink
  measures 4.23 on `color.bg.raised` in light, under the 4.5 of `R-32-124`; the widget hands the
  platform button `color.accent.text` as its `foregroundColor` instead, and this sentence is the
  record of that one exception.

### 7.9 Destructive action

| Part | Value |
| --- | --- |
| Widget | the text button of `R-32-526` with a `treat.destructive` child, the composition the confirmation dialog of section 7.17 already draws: `TextButton` on Android, `CupertinoButton` on iOS, per `R-03-059` (added 2026-09-09 by the product owner) |
| Height | the component's own on both platforms, per the `R-03-059` addendum (amended 2026-09-09: was `size.button.text` through `textButtonTheme`, and before that `size.button.primary`, the height of a drawn row) |
| Composition | `treat.destructive` without its bar, at the button's own inset: the hue in the glyph alone (amended 2026-09-09, per `R-03-058`) |
| Fill | none |
| Disabled | the whole control at `opacity.disabled`, no colour change, per `R-32-502` (added 2026-09-09) |
| Position | alone in its own group, separated by a divider |

- **R-32-527** A destructive label MUST NOT be red text, per `R-30-143`. The hue lives in the icon
  alone, on a row and on a button alike: a leading bar is the state bar of `R-03-100`, and a bar
  beside a red glyph is two marks for one fact, which `R-03-058` forbids (amended 2026-09-09 by
  the product owner, who named the bar a random line; until then a row kept the bar, and the
  `Close pane` row of `docs/31-mockups/10-pane-actions.md` still drew it on the emulator). A red
  fill is measurably available, per `R-32-126`, and version one MUST NOT use it. (Amended
  2026-09-09, per `R-03-059`.) The button around the treatment is the platform's own; the app
  draws no destructive row of its own from a box and a gesture.

### 7.10 Text field

| Part | Value |
| --- | --- |
| Height | `size.field` |
| Fill | `color.bg.high` |
| Radius | `radius.sm` |
| Border | `border.hairline` in `color.border.strong` |
| Text | `type.body`, or `type.mono.code` for an origin, an id or a path, in `color.fg.primary`; on `/pair/manual` every field is `type.mono.phrase`, per section 4 |
| Placeholder | the same token in `color.fg.disabled` |
| Horizontal padding | `space.3` |
| Focused | `border.focus`, drawn outside the boundary |
| Error | `border.error`, plus a `treat.error` line under the field |

- **R-32-530** A field MUST carry its `color.border.strong` boundary. Its fill alone measures 1.60
  and 1.43 against the screen, which cannot identify it.

### 7.11 The six-word phrase field

| Part | Value |
| --- | --- |
| Field size | `size.field` high, two fields per row, gap `space.3`, each field taking half the content width less half the gap |
| Text | `type.mono.phrase` in `color.fg.primary` |
| Empty placeholder | a single dash in `color.fg.disabled` |
| Number | `type.micro` in `color.fg.secondary`, outside the field, gap `space.1`; the same size as the group labels above the fields |
| Paste field | full content width, `size.field` high, otherwise a text field; its text and the computer-code field's text are `type.mono.phrase`, so every pairing input shares one size |
| Autocomplete strip | full content width, at most six chips of `size.row.one_line` plus `space.2` vertical padding, surface `color.bg.raised`, a 1 px `color.border.subtle` top rule, `elev.2`, chip label `type.mono.phrase` in `color.fg.primary` |
| Focused | `border.focus` |
| Error | `border.error` on the field that failed |
| Compact manual-pairing actions | below `4 * size.field` of available height, plus the native navigation bar's height on iOS, one row with width shares of 1 for `Pair` and 2 for `Scan the QR code instead`, separated by `space.2`; the focused field stays above the row per `R-31-03-15` |

- **R-32-531** A word field MUST use `type.mono.phrase`, because a phrase is transcribed character
  by character and a proportional font hides a repeated letter.
- **R-32-532** The autocomplete strip MUST sit directly above the keyboard inset, MUST NOT cover
  the focused field, MUST NOT exceed six chips, and MUST scroll horizontally when the chips do not
  fit, per `R-30-904`.

### 7.12 Key cap

| Part | Value |
| --- | --- |
| Widget | the platform's own button, per `R-03-059` (amended 2026-09-09 by the product owner: a key cap is a button and the key row has no exemption) and the `Key cap` row of `docs/33-platform-chrome.md` section 5: `OutlinedButton` on Android and `CupertinoButton.tinted` on iOS, `FilledButton` and `CupertinoButton.filled` while a modifier is latched (amended 2026-09-10 per `R-03-118`: the latched Android form was `FilledButton.tonal`, which is not the platform's high-emphasis form), built by `app/lib/widgets/key_row.dart` alone. Every colour reaches it through the theme of `app/lib/app.dart` (`outlinedButtonTheme`, `filledButtonTheme`, `CupertinoThemeData.primaryColor` and `primaryContrastingColor`); the key row's own button theme adds the layout floor and the type below, and nothing else |
| Layout floor | `size.keycap` high and at least the column module of `R-31-09-21` wide, with `space.2` of horizontal padding: a `minimumSize` and a `padding` that the key row's own `OutlinedButtonTheme` and `FilledButtonTheme` set on Android, and the same two values the row hands `CupertinoButton` on iOS, where `cupertino_ui` 1.0.1 has no theme slot for them. A floor and a padding, never a shape: `R-03-059` forbids a theme to reshape a button into "a square, a fixed box or any geometry the platform does not draw", and a minimum on the platform's own pill is neither; without the floor the arrows scroll off a portrait phone, which `R-31-09-16` forbids (2026-09-09). Amended 2026-09-10 per `R-03-116`: a key in the Shortcuts palette floored at `size.chordkey` until then, and both are retired |
| Target | `size.target.min`; the button is the target, pitch the cap width plus `space.2`, per `R-32-362` |
| Shape | the platform's own: the Material 3 pill on Android, the component's own corner on iOS (amended 2026-09-09, per `R-03-059`: was `radius.sm`) |
| Fill | none on Android; the component's `color.accent.primary` tint on iOS (amended 2026-09-09: was `color.bg.high`) |
| Border | `border.hairline` in `color.border.strong` on Android, from `outlinedButtonTheme`; none on iOS |
| Label | `type.mono.key`, through the row's theme: `textStyle` on Android, `textTheme.actionTextStyle` on iOS. `color.fg.primary` on Android. `color.accent.text` on iOS, which measures 4.68 on the tint over `color.bg.raised` in both themes (computed 2026-09-09): the component's own `color.accent.primary` ink measures 3.6 there in light and misses the 4.5 floor of `R-30-720`, so the row hands the button `color.accent.text`, as `R-32-526`'s iOS branch already does |
| Glyph | `size.icon.md` from the `R-32-401` map, in the label's ink: the four arrows, `More keys`, `Fewer keys` (amended 2026-09-10: `Cancel` closed the retired Shortcuts palette) |
| Pressed | the platform's own response, per `R-32-501`: on Android the ink overlay in `color.accent.soft` under a `color.accent.primary` border, both from `outlinedButtonTheme`; on iOS the Cupertino press fade. No app-drawn fill, scale or timing (amended 2026-09-09: was a `color.accent.primary` fill for `motion.duration.fast`) |
| Latched | the platform's own high-emphasis button, per `R-03-118`: `color.accent.primary` under `color.fg.on_accent` through the theme, until the latch clears. The label keeps its written case, its weight and its text, and the cap reports a toggle to assistive technology; `R-31-09-25` of `docs/31-mockups/09-key-row.md` holds the requirement (amended 2026-09-10: the label went upper case for state until then, the one case-for-state hack in the interface, and the fill was tonal) |
| Focused | the platform's own focus response, per `R-32-503` |
| Disabled | `opacity.disabled`, per `R-32-502`: the theme's disabled colours on Android; on iOS the cap hands the component its own tint back and dims itself, as the ghost button of section 7.28 does |
| Row | `size.keyrow` high per row of caps, with `space.2` between rows. Section 7.13 owns the shared surface, inset, outer padding, and top edge |

- **R-32-535** A key cap MUST be the platform's own button and MUST NOT be a box, a border and a
  gesture the app draws (amended 2026-09-09 by the product owner, per `R-03-059`; until then the
  cap carried its own boundary, per `R-32-112`, and this rule forbade it a status dot, a clause
  `R-03-100` made moot). The four arrow keys MUST be four separate buttons at the row's `space.2`
  gap, never one box with a shared border; `R-31-09-21` puts them in the keyboard's inverted T
  across two rows of the grid (amended 2026-09-10 per `R-03-117`: they sat adjacent on one row
  until then). The key row's own button theme MUST set the layout
  floor and the type of the table above and MUST NOT set a shape, a fill or an ink of its own.
  The latched form is the platform's own high-emphasis button, per `R-03-118`, and the label MUST
  NOT change case for state; `R-31-09-25` of `docs/31-mockups/09-key-row.md` holds that
  requirement and the table above holds the values.
  `app/lib/widgets/key_row.dart` alone builds the cap.
- **R-32-536** The key panel MUST use three rows of six columns without scroll or wrap, per
  R-31-09-21. Each row uses `size.keyrow`, with `space.2` gaps.

### 7.13 Input bar

This surface follows R-03-133. `docs/31-mockups/09-key-row.md` owns its behaviour.

| Part | Value |
| --- | --- |
| Surface | One `color.bg.raised` surface; top `border.hairline` in `color.border.strong` |
| Inset | `space.4` horizontally; `space.2` vertically; keyboard or system inset per R-30-519 |
| Row | Leading `+`, expanded field, trailing send; `space.2` gaps; `crossAxisAlignment: end`. The iOS suffix uses the same alignment. The controls' centres stay level with each other at the bottom of a multiline field |
| Single-line height | Android: `size.field` (48 dp). iOS: 36 pt. The leading circle matches the field. The iOS send circle occupies the suffix inside that height |
| Leading control | Android: round `IconButton.filledTonal`, exactly 48 dp. iOS: `CupertinoButton` with its own `color` and `borderRadius`, 36 pt painted circle in `color.bg.high`, 44 pt `minimumSize` tap target, glyph in `color.accent.text` |
| Leading glyph | `Symbols.add_rounded`, semantics `More keys`; `Symbols.close_rounded` while open, semantics `Fewer keys` |
| Field | Fill `color.bg.high`; corner radius equals half the platform's single-line field height (Android 24 dp; iOS 18 pt), unchanged as the field grows; `border.hairline` in `color.border.strong`. Text `type.mono.compose` in `color.fg.primary`; placeholder `Type here` in `color.fg.disabled`. `minLines: 1`, `maxLines: 5`, multiline keyboard, `textInputAction: send`. Native editing options follow R-31-09-30 |
| Field padding | Android: `space.3` horizontally, 13 dp vertically; one 22 dp text line totals 48 dp. iOS: `space.3` leading, `space.1` trailing, 7 pt vertically; one 22 pt text line totals 36 pt |
| Send control | Android: outside the field, round `IconButton.filled`, exactly 48 dp, `Symbols.send_rounded`. iOS: inside the field suffix, `CupertinoButton` with zero padding and `minimumSize: 30`, a 30 pt circle with equal 3 pt bottom and trailing insets from the field edge, `Symbols.arrow_upward_rounded`. Its 15 pt radius and the field's 18 pt corner share a centre, leaving an even 3 pt gap. Both use `color.accent.primary` with `color.fg.on_accent` glyphs at `size.icon.md` and semantics `Send` |
| Send state | Enabled when empty, per R-31-09-28. Field and send controls stay disabled offline or while the Host is in use, per R-30-807 and R-32-502 |
| Key panel | Closed by default. Above the bar, over the bottom of the grid; its own `color.bg.raised` surface and top `border.hairline` in `color.border.strong`. Use `space.4` horizontal inset and `space.2` gaps and vertical padding. Three rows, six columns, height fits the rows, no scroll. Use the native caps of section 7.12 and the order in R-31-09-21. Opening preserves the keyboard state. Field focus and modifier latches leave it open. Only `×` or a grid tap closes it |

- **R-32-537** The input bar MUST use the anatomy in R-03-133 and the native controls in
  `docs/33-platform-chrome.md` section 5.
  The leading control and Android send control MUST equal their platform's single-line field height.
  The iOS send control MUST fit inside the field suffix at the dimensions above.
  Controls MUST stay bottom-aligned when the field grows, per R-03-133 (amended 2026-09-17).
  The leading circle and Send MUST have level centres. The iOS Send MUST use the inset above.
  Its bottom trailing curve MUST be concentric with the field's corner, per R-03-133.
  The field's corner radius MUST equal half its platform's single-line height, even when taller.
  The key panel MUST overlay the grid above the bar, not replace or cover the keyboard.
  The app MUST NOT draw substitute fields, buttons, or keys.

### 7.14 Jump-to-bottom pill

| Part | Value |
| --- | --- |
| Height | `size.pill`, inside a `size.target.min` target |
| Fill | `color.bg.high` |
| Radius | `radius.full` |
| Border | `border.hairline` in `color.border.strong` |
| Icon | `vertical_align_bottom` at `size.icon.md` in `color.fg.primary` |
| Label | `type.label` in `color.fg.primary`, gap `space.1` |
| Horizontal padding | `space.3` |
| Position | `space.4` from the trailing edge, `space.4` above the status strip |

- **R-32-540** The pill icon MUST be `vertical_align_bottom`, which means "to the end", and MUST NOT
  be a bare downward arrow, which means "one line down".

### 7.15 Terminal status strip

| Part | Value |
| --- | --- |
| Height | `size.statusstrip`, a `size.target.min` row (amended 2026-09-08, was 28), so the mode control below is a full target in portrait; the landscape merged bar is at least 56 |
| Surface | `color.bg.raised` |
| Top edge | `border.hairline` in `color.border.strong` |
| Text | `type.caption` in `color.fg.secondary` |
| State bar | the state bar of section 7.29, `border.attention` wide, as high as the strip's text line, `space.2` before the link word; `working` pulses with `motion.pulse` (amended 2026-09-09 by the product owner, per `R-03-100`: the status dot is retired) |
| Horizontal inset | `space.4` |

- **R-32-542** The strip's text MUST be `color.fg.secondary` on `color.bg.raised`, which measures
  7.64 and 6.02 in the table of `R-32-150`. Its one labelled control, the mode action of
  `R-32-543`, is a text action and MAY take `color.accent.text`, which measures 8.18 and 5.50 on
  this surface, per `R-32-124` (corrected 2026-09-08 by the product owner: an earlier sentence
  carried the pre-brand-palette ratios 5.03 and 4.65 and forbade `color.accent.text` here, which
  the measured table no longer supports).
- **R-32-543** Terminal text mode (added 2026-09-08 by the product owner, superseding the
  fit-to-width default): the terminal opens readable, at the saved `type.mono.terminal` size
  (`R-32-208`'s default 13 until the person changes it). The strip carries one labelled control:
  `Overview` while the grid is readable, `Readable` while it is in overview. `Overview` shrinks
  the whole Host grid to fit the viewport, however small that makes the glyphs, and `Readable`
  restores the saved size. A pinch chooses a custom size under R-21-008. During custom zoom,
  the button retains its labeled preset destination and clears custom zoom when pressed. The button
  MUST be a native labelled control of at least `size.target.min` in both orientations. In landscape
  the merged bar is at least 56 high, the row range sits above the revision beside the mode action,
  and the grid size stays in the key row's trailing slot. Neither mode resizes the Host, per
  `docs/21-terminal-rendering.md`, which owns the cell metrics and the pan.

### 7.16 Bottom sheet

Amended 2026-09-09: every bottom sheet MUST use the root navigator to cover the connection strip
and the tab bar, per `R-30-045`. The owner rejected leaving the strip visible below a sheet.

| Part | Value |
| --- | --- |
| Surface | `color.bg.raised` |
| Radius | `radius.lg` on the top two corners only |
| Elevation | `elev.3` |
| Scrim | `color.bg.base` at `opacity.dim`; opaque and fixed where it overlaps the terminal grid rectangle, per `R-33-060` |
| Grab handle | `size.grab` at `radius.full` in `color.fg.disabled`, centred, `space.2` from the top |
| Row height | `size.row.one_line` |
| Row label | `type.body` in `color.fg.primary`, leading inset `space.4` |
| Header | the title in `type.body.strong`, the second line in `type.caption` in `color.fg.secondary` |
| Group divider | `border.hairline` in `color.border.subtle` |
| Cancel row | `size.button.primary` high, centred, `type.body.strong` in `color.fg.secondary` |
| Motion | `motion.duration.base` with `motion.curve.enter` in, `motion.curve.exit` out |

- **R-32-545** Exactly one sheet MUST be on screen at a time. A confirmation that belongs to a sheet
  action MUST NOT open a second sheet. A non-destructive one, such as a rename field, MUST replace
  that sheet's content. A destructive one is the platform dialog of `R-33-074`, and the sheet MUST
  close before it opens.
- **R-32-546** The grab handle MUST be excluded from the semantics tree, and the sheet MUST trap the
  focus and return it to the control that opened it, per `R-30-719`.

### 7.17 Destructive confirmation dialog

| Part | Value |
| --- | --- |
| Width | the screen width less `space.6` on each side |
| Surface | `color.bg.raised` |
| Radius | `radius.md` |
| Elevation | `elev.3` |
| Scrim | `color.bg.base` at `opacity.dim` |
| Padding | `space.6` on every side |
| Title | `type.heading` in `color.fg.primary` |
| Body | `type.body` in `color.fg.primary`, gap `space.3` under the title |
| Actions | full width, `size.button.primary` high, gap `space.2`; `R-33-074` owns the order and the arrangement |
| Safe action | `type.body.strong` in `color.fg.primary`, on both platforms |
| Destructive action | `treat.destructive`, on both platforms: the hue in the icon alone, the verb in `color.fg.primary`, per `R-32-527` (amended 2026-09-08: the Material branch drew a plain text button, and the iOS branch left the verb red; amended 2026-09-09 per `R-03-058`: the leading bar left this row) |

- **R-32-547** This is the destructive confirmation, one of the two modal dialogs the app is
  permitted, per `R-30-005` as amended 2026-09-10 by `R-03-119`: the other is the terminal state
  that ends the person's work in a pane, per `docs/31-mockups/08-terminal.md` `R-31-08-27`. No
  third modal exists. `R-33-074` owns
  the component, the action titles, the action order and the initial focus, because the two
  platforms differ on all four. This rule owns the shared anatomy only: the scrim, the width, the
  title and body tokens, and the destructive treatment of `R-30-143`. It MUST NOT name a position,
  an order or a focus target. The two role compositions of the table travel with their role onto
  whichever platform action the component provides; the platform keeps its own order and its own
  role flag (amended 2026-09-08).

### 7.18 Full-screen blocking state

| Part | Value |
| --- | --- |
| Banner width | full width, under the app bar, pushing the content down |
| Surface | `color.bg.raised` |
| Leading bar | `border.attention` in `color.status.warning` |
| Bottom edge | `border.hairline` in `color.border.strong` |
| Title | `type.body.strong` in `color.fg.primary` with `treat.warning` |
| Explanation | `type.caption` in `color.fg.secondary` |
| Actions | at most two text actions, `size.button.text` high, `type.label` |
| Padding | `space.4` |
| Dismissal | none |

- **R-32-550** A blocking state MUST NOT float over content, MUST NOT be dismissible and MUST NOT
  offer an action that the blocked phone has no authority to perform, per `R-30-941`.
- **R-32-551** The action a person can actually use MUST come first in the traversal order. Where
  the blocked state is resolved on another surface, the explanatory action is the useful one.

### 7.19 Empty state

| Part | Value |
| --- | --- |
| Ground | the ground grid of `R-32-332` on `color.bg.base`, painted by `GroundGrid`, with the watermark below over it and the text block on top: `GroundGrid(EmptyMark(block))`. The empty state is one of the two places the grid is permitted, and it is the one place a screen with a list route shows it (amended 2026-09-09 by the product owner, per `R-03-107` step two: the paper of the retired `R-32-334` is gone, so "no paper" needs no saying) |
| Alignment | left, at the screen edge inset `space.4` |
| Watermark | `app/lib/widgets/app_ground.dart` `EmptyMark`: the brand silhouette `assets/brand/ram.png` in `color.bg.grid` ink, 60% of the body width (`EmptyMark.widthShare`), anchored bottom-right, right crop flush with the body's right edge and bottom crop on its bottom edge, per `R-32-554` (amended 2026-09-09 by the product owner, per `R-03-107`: it replaces the 96 px mark in `color.fg.disabled` that stood above the eyebrow, so a screen carries one silhouette) |
| Eyebrow | `widgets/eyebrow.dart`: 24x1 rule in `accent.primary`, `space.3` gap, `type.micro` UPPER in `accent.text`; it is the first line of the block (amended 2026-09-09: the `space.5` gap under the retired mark went with it) |
| Title | `type.title`, the display face of the screen titles, in `color.accent.text` on `color.bg.base`, naming the absent thing; it measures 8.81 in dark and 5.96 in light, per `R-32-124` (amended 2026-09-09 by the product owner, per `R-03-107`: was `color.fg.primary`; the accent look is where the fun of this app lives, never a texture behind text. `type.display` stays on `/welcome` only, per `R-32-205`) |
| Body | `type.body` in `color.fg.secondary`, gap `space.2` |
| Action | at most one ghost button, `space.5` under the body |
| Illustration | none; the watermark is ground, not an illustration (amended 2026-09-09) |

- **R-32-553** An empty state MUST NOT be centred, MUST NOT carry an illustration and MUST NOT say
  `Nothing here`, per `R-30-802`.
- **R-32-554** (added 2026-09-09 by the product owner, per `R-03-107`) The empty-state watermark
  and title. Every empty state MUST sit on the ground grid of `R-32-332` and MUST carry the brand
  silhouette once, in `color.bg.grid` ink, the ink of the grid lines. The mark is 60% of the
  body's width, `EmptyMark.widthShare`, and its right and bottom crop edges sit on the body's right
  and bottom edges, never floating: the anchoring of the welcome hero, `R-32-594`. The text block
  of the table above sits over it: the title in `type.title`, the display face of the screen
  titles, in `color.accent.text` on `color.bg.base`, then the sentence in `type.body`
  `color.fg.secondary` (amended 2026-09-09 by the product owner, per `R-03-107` step two: the title
  was `color.fg.primary`; the accent title is the empty state's one brand move now that the paper
  of the retired `R-32-334` is gone). The watermark's ink is the grid's own and clears no contrast
  floor on purpose: the watermark is decorative and contrast-exempt, like the grid, and it MUST be
  excluded from semantics, so a screen reader meets the eyebrow first. The watermark MUST NOT carry
  the message, MUST NOT change with the state and MUST NOT appear behind a loading, an error or an
  offline state. `R-30-801` and `R-30-802` own what the text says.

### 7.20 Error state with a raw error string

| Part | Value |
| --- | --- |
| Sentence | `treat.error` with the label in `type.body` |
| Raw block | `type.mono.code` in `color.fg.primary` on `color.bg.raised`, `radius.md`, `border.hairline` in `color.border.strong`, padding `space.3`, gap `space.3` under the sentence |
| Action | exactly one, labelled `Try again`, as a text action |
| Alignment | left, at `space.4` |

- **R-32-555** The raw text MUST be shown, never replaced, and a friendly sentence MAY sit above it,
  per `R-30-803` and `R-31-13-02`. The block MUST be selectable so a person can copy it.

### 7.21 QR scanner viewport

| Part | Value |
| --- | --- |
| Frame | a square of side `min(preview width - 2 * space.6, preview height - 2 * space.6, 280)`, floored at zero; with zoom controls, also bound it by `preview height - 2 * (space.4 + size.target.min + space.4)` so the controls stay below the centred frame |
| Corner marks | four, each `size.viewfinder.corner` long and `border.frame` thick, in `color.accent.primary`, at `radius.sm` |
| Scrim | `color.bg.base` at `opacity.dim` outside the frame |
| Hint | `type.body` in `color.fg.secondary` on `color.bg.raised`, at most two lines in portrait; wraps in the scrollable landscape panel of `R-31-02-16` |
| Landscape panel | `space.4` outside inset on all sides within its half of the safe area; a complete `border.hairline` frame in `color.border.strong`, including the connecting state |
| Preview | fills the area behind the frame, excluded from the semantics tree |

- **R-32-558** The frame is a framing aid for the person, not a constraint on the decoder. The
  scanner MUST NOT reject a readable code that sits slightly outside the frame.
- **R-32-559** When several codes are readable in one frame, the scanner MUST take the most centred
  one, because the Relay pane often sits beside another terminal.

### 7.22 Bottom navigation, skeleton, strip and snackbar

| Component | Anatomy |
| --- | --- |
| Bottom navigation | three destinations, height `size.bottomnav` plus the safe area, icon `size.icon.lg`, label `type.micro` UPPER, active in `color.accent.text`, inactive in `color.fg.secondary`, each target `size.target.min`, spans the full width, `radius.none`, `elev.0`, surface `color.bg.base`, top edge `border.hairline` in `color.border.strong` (amended 2026-09-08 by the product owner: when the connection strip of `R-33-036` sits above the bar, the strip's bottom hairline is the edge and the bar draws none; two adjacent lines read as one 2 px two-tone line, and Android's bar never drew one, so both platforms match); `R-33-012` owns whether the standard component draws that surface translucently, and `R-33-068` owns the opaque variant |
| Skeleton | one or two bars per row, `size.skeleton` high, `radius.sm`, in `color.bg.raised`, first bar 140 wide and second 90 wide, shown only after 150 ms, per `R-30-004`, and never animated |
| Strip | full width, surface `color.bg.raised`, `radius.none`, text `type.caption`, a treatment for the state, padding `space.3` by `space.4`, top and bottom edge `border.hairline` in `color.border.subtle`; no leading bar of its own, because the hue lives in the treatment's icon and, for `treat.error`, its own bar (clarified 2026-09-08 by the product owner: the widget accepted a bare status colour for a bar it never painted, and its gutter pushed the text `space.3` right of the column); a destination tap presses to `color.bg.high`, per `R-32-501` and `R-32-609`. The connection strip of `R-33-036` is the one exception (amended 2026-09-10 by the product owner, who found `Not connected` indistinguishable from connected): it carries the state bar of section 7.29 at its leading edge, the strip's full height, `ok` while connected, `warning` while a connection is in flight and `error` for every failure, and a failure sentence reads in `type.body.strong` `color.fg.primary` while the connected sentence keeps `type.caption` `color.fg.secondary`; the text keeps its `space.4` inset |
| Snackbar | surface `color.bg.raised`, `radius.md`, `elev.2`, text `type.body` in `color.fg.primary`, padding `space.3` by `space.4`, `space.4` from every edge it floats above |
| Terminal text size slider | one title row, the label in `type.body.strong` `color.fg.primary` with the value in `type.caption` `color.fg.secondary` at the trailing edge on the same baseline, written `13 pt`; under it, `space.2` away, the platform's own discrete slider in the component's own shape, size and colours, `Slider` on Android (the Material 3 default colours of the theme) and `CupertinoSlider` on iOS, one stop per permitted size of `R-32-208` and nothing between two stops, no value bubble; one merged semantics node, label `Terminal text size`, value `13 points` (amended 2026-09-09 by the product owner, per `R-03-110`: the stepper of `R-03-059`, the `aA` glyph, the `remove` and `add` icon buttons and the spacer are gone) |
| Live terminal preview | two real rows in `type.mono.terminal` on `color.term.bg` with `color.term.fg`, `radius.md`, `border.hairline` in `color.border.strong` |

- **R-32-560** A skeleton MUST NOT animate, MUST NOT resemble a terminal grid and MUST be
  accompanied by the state word the screen already shows, per `R-30-003`.
- **R-32-561** A strip MUST be tappable when it reports a link failure, and MUST then route to the
  diagnostics screen, per `R-30-806`. When a strip reports a result that names a destination, it
  MUST be tappable and MUST route to that destination, because a strip that names a place and does
  not go there is a dead end. The whole-width tap is the strip's own affordance, and it MUST NOT be
  read as forbidding a text action: on this surface a text action is the one text action of
  `R-32-526`, the platform's own label style in `color.accent.text` (amended 2026-09-09, per
  `R-03-104`: was `type.mono.button` UPPER), which `R-32-124` permits on
  `color.bg.raised` at 8.18 and 5.50 (corrected 2026-09-08 by the product owner: an earlier
  sentence put a `type.body.strong` `color.fg.primary` action here and misread `R-32-124`; every
  strip in the app already draws the `R-32-526` action, and two action styles for one job is a
  defect under `R-30-121`). The two carry different work, and a strip MUST NOT swap them. The
  whole-width tap serves a **destination** only. Work that goes nowhere, such as re-reading a list,
  retrying a request or dismissing the strip, MUST NOT be the whole-width tap, because a band of
  prose that acts wherever it is touched is a mis-tap waiting to happen on the one control a person
  is still reading. Such work takes its own control: a text action for a retry, which is why several
  strips carry `Try again`, and a dismiss control where a strip is dismissible.
- **R-32-562** The bottom navigation MUST hold exactly the three destinations that `R-30-021` fixes,
  with exactly these icons: `smart_toy` for `Agents`, `notifications` for `Notifications` and
  `settings` for `Settings`, per `R-32-401`. `Notifications` replaced `Panes` on 2026-09-04 by
  the product owner's decision: the pane tree screen is gone, and the `Workspace` axis of
  `docs/31-mockups/06-agent-list.md` is the one browser for every pane. The active destination
  MUST be marked by its icon colour and its label weight together, never by colour alone, per
  `R-30-141`. One control shape carries those three destinations, and it takes the anatomy in the
  table above. `R-33-035` requires the same three destinations in the same order on both
  platforms, and `R-33-033` holds the whole native control map, so this document MUST NOT name a
  platform here: a value is not a platform choice.
- **R-32-588** The create control of the `Agents` screen MUST be Material's floating action
  button on both platforms: 56 by 56, the token `size.button.create`, the component's own 16
  corner, `add` at `size.icon.lg` in `color.fg.on_accent` on `color.accent.primary`, `elev.2`,
  `space.4` from the trailing edge and from the bottom safe area, and `R-33-029` fixes that
  bottom offset on Android. Spoken `New`, per `R-32-505`. Disabled while the link is down: the
  whole control at `opacity.disabled`, per `R-32-502`. A list MUST NOT reserve a fixed band
  for it: the list's own end padding, `size.button.create` plus `space.4`, scrolls the last row
  clear of the button only when the list overflows, per `R-03-109`. Retired 2026-09-09 for an
  app bar action and restored 2026-09-10 by the product owner, per the corrected `R-03-109`:
  the owner wanted the floating button kept on both platforms and only the empty band removed,
  and the band was the ground grid of the retired `R-32-334` showing through the padding, not
  the button. `R-33-034` owns the platform placement; `docs/31-mockups/06-agent-list.md`
  callout 10 draws it.

### 7.23 Section header, collapsible

The agent list needs this header on both of its axes, so it is specified once here instead of in
the mockup. `docs/30-ux-spec.md` owns which grouping shows which tier, in `R-30-412` and
`R-30-413`. On the `Workspace` axis the tiers are the Herdr desktop sidebar's own:
`Space > Worktree > Tab > Pane`, decided 2026-09-04 by the product owner, and the header forms
below are tier 1 for a space, the worktree row for a Herdr workspace inside it, and tier 2 for a
tab. The pane row under them is the list row of section 7.4 inside the space block of section
7.32.

| Part | Value |
| --- | --- |
| Tier 1 surface | a band of `color.bg.high` across the space block's top, `size.row.one_line` high; the band is the block's top edge, so no hairline runs under it (amended 2026-09-09 by the product owner, per `R-03-057`) |
| Tier 1 height | `size.row.one_line`, per `R-32-564` |
| Tier 1 pressed | `R-32-501`'s first case, because the band is a control filled with `color.bg.high`: `color.accent.primary` with the name, the count and the expander in `color.fg.on_accent`, with the timing and the scale of `R-32-609`; the badge icon keeps its hue (amended 2026-09-09) |
| Tier 1 label | `type.body.strong` in `color.fg.primary`, the space name |
| Tier 1 indent | `space.4`, the name's text edge: the first step of the ladder of `R-32-570` (amended 2026-09-09; the expander no longer precedes the name) |
| Tier 1 expander | trailing, at the `space.4` trailing inset, `size.icon.md` in `color.fg.secondary`, gap `space.3` after the count and the badge, glyphs per `R-32-568` (amended 2026-09-09: moved from leading so the name takes the ladder's first step) |
| Tier 1 trailing count | `type.caption` in `color.fg.secondary`, `N panes`, per `R-32-595`, on the label's alphabetic baseline (amended 2026-09-08: a centred row put it 2 px above) |
| Tier 1 badge | the badge of `R-32-518`, trailing the count, gap `space.2`, its count on that same baseline (amended 2026-09-08: a centred row put it 3 px above) |
| Worktree row height | the label line plus `space.3` above and below, 48 at the default text scale (amended 2026-09-08 by the product owner: the 32 box put the worktree label 10 px above its tab while rows sit 24 apart; one rhythm, the precedent of `R-32-517`; was `size.header`) |
| Worktree row label | `type.body.strong` in `color.fg.primary`, the workspace label |
| Worktree row indent | `space.2` for the glyph; the label then lands at `space.8`, one `space.4` step in from the space name and one before the tab title (amended 2026-09-09, per `R-03-057`; until then it shared the name's 48 column and read as a second space) |
| Worktree row glyph | leading, the `A worktree` glyph of `R-32-401` at `size.icon.sm` in `color.fg.secondary`, gap `space.2` |
| Tier 2 height | the title line plus `space.3` above and below, 48 at the default text scale (amended 2026-09-09; was 44 with the `type.label` title) |
| Tier 2 label | `type.body.strong` in `color.fg.primary`, the tab name (amended 2026-09-09 by the product owner, per `R-03-057`: `type.label` in `color.fg.secondary` read as one more grey row among the pane rows) |
| Tier 2 glyph | leading, the `A tab` glyph of `R-32-401` at `size.icon.sm` in `color.fg.secondary`, gap `space.2` (added 2026-09-09) |
| Tier 2 indent | `space.6` for the glyph; the title then lands at `space.12` (amended 2026-09-09, was `space.16` for the label) |
| Upper-case tier height | `size.header` |
| Upper-case tier label | `type.micro` in `color.fg.secondary`, one of our own words |
| Upper-case tier indent | `space.4` |
| Surface | the space block's `color.bg.raised` for tier 1, the worktree row and tier 2 (`R-32-595`); `color.bg.base` for the upper-case tier |
| Trailing inset, every tier | `space.4` |
| Divider | none of its own; the space block draws its hairlines, per `R-32-596` |

- **R-32-563** The table above is normative. Exactly two shared header forms remain: tier 1 and the
  single upper-case tier. The worktree row and tier 2 moved into `docs/31-mockups/06-agent-list.md`'s
  own anatomy, section 7.23 (amended 2026-09-09 by the product owner, per `R-03-057`). A screen
  MUST NOT invent another shared form, and MUST NOT nest a header inside another header of the same
  tier. Tier 1's label, count and badge count MUST share one alphabetic baseline; the expander stays
  centred in the row, because an icon glyph's font baseline says nothing about where its shape sits
  (amended 2026-09-08 by the product owner's design pass).
- **R-32-564** A collapsible header MUST present a target of at least `size.target.min`, so tier 1
  MUST be `size.row.one_line`, which is 52, and MUST NOT be `size.header`, which is 32. The whole
  header row is the expander target, per `R-30-290` and `R-32-360`. The worktree row, tier 2 and
  the upper-case tier are not targets, so no target floor binds them: the upper-case tier is
  `size.header`, and the worktree row and tier 2 take their label line plus `space.3` above and
  below, per the table (amended 2026-09-08 by the product owner; an earlier sentence named
  `size.header` for all three). This is the value side of a rule `docs/30-ux-spec.md` cannot
  state, because `R-32-002` keeps a size out of that document.
- **R-32-565** No tier of the `Workspace` axis pins, per `R-30-413` (decided 2026-09-04 by the
  product owner). Tier 1 collapses and does not pin: Flutter stacks pinned headers under each
  other by default, so a long list piled every scrolled-past header at the top, and the space
  block of `R-32-595` carries the membership while the list scrolls instead. The worktree row
  and tier 2 neither pin nor collapse. Only the upper-case tier pins, per `R-32-569`, and only
  inside its own section.
- **R-32-566** A collapsed tier 1 MUST still show its trailing count and the badge of `R-32-518`,
  per `R-30-414`. Attention MUST NOT be able to hide inside a closed branch.
- **R-32-567** A header MUST keep the case of the words it shows. Our own words are upper case, so
  the priority headers are upper case in `type.micro`. A space name, a workspace label and a tab
  name are the person's own data, so the app MUST NOT upper-case a name it did not write, and MUST
  NOT set one in `type.micro`.
- **R-32-568** The expander MUST use the two glyphs the `Expand, collapse` row of `R-32-401` names:
  `expand_more` when the branch is open and `chevron_right` when it is closed. The header MUST
  announce `expanded` or `collapsed` once when it toggles, and MUST NOT announce that state again
  while the list scrolls.
- **R-32-569** The upper-case tier MUST be `type.micro` at `size.header`, MUST pin and MUST NOT be
  collapsible, per `R-30-412`. It carries our own word, so `R-32-567` permits its case. The pin
  MUST be scoped to the header's own section (amended 2026-09-08): the header stays at the top
  only while a row of its section is on screen, then scrolls away with the section's last row,
  and the next section's header takes the top. Two pinned headers MUST NOT stack. Flutter's
  default stacks them, so each section MUST be one sliver group (`SliverMainAxisGroup`) that
  holds its header and its rows.
- **R-32-570** The `Workspace` axis MUST read as a ladder of **text edges**, four even `space.4`
  steps inside the space block (amended 2026-09-09 by the product owner, per `R-03-057`, after two
  rounds that changed spacing alone left the tiers reading as one weight): the space name at
  `space.4` on the header band, the worktree label at `space.8`, the tab title at `space.12` and
  the pane text at `space.16`. Every glyph sits `size.icon.sm` plus one `space.2` before its text:
  the worktree glyph at `space.2`, the tab glyph at `space.6`, and the pane row's leading slot at
  `space.10`, `size.icon.sm` wide, with the `A pane` glyph of a shell row centred in it; an agent
  row leaves the slot empty and draws its state bar of section 7.29 right after the guide rule of
  section 7.32, at the row's own leading edge (amended 2026-09-09 by the product owner, per
  `R-03-100`: the dot centred in the slot is retired; the bar left the block's edge the same day,
  because it marks the row, not the card; the four text edges do not move). A tab title MUST NOT
  start left of the worktree label above it, and a pane row's text MUST NOT start left of its
  tab's title. A header MUST NOT reach an
  indent by adding two steps. The ladder MUST NOT shift when a space draws no worktree row: the
  same tier sits at the same edge in every block, so a person scans one column per tier. (The
  2026-09-08 ladder, 48, 64, 80 with the expander leading and the worktree label in the name's
  column, is retired.)

### 7.24 Hierarchy breadcrumb

One line that names the workspace, the tab and the pane a row belongs to.

| Part | Value |
| --- | --- |
| Text | `type.caption` in `color.fg.secondary`, one line |
| Segments | workspace, then tab, then pane, each keeping the person's own case, per `R-32-567` |
| Separator | the text glyph `›`, U+203A, in `color.fg.secondary`, per `R-32-572` |
| Space each side of the separator | one hair space, U+200A, inside the same text run |
| Overflow | elides from the front, per `R-32-573` |
| Semantics | exactly one node, per `R-32-574` |

- **R-32-571** The table above is normative. A breadcrumb is one line and MUST NOT wrap to a second
  line. `docs/30-ux-spec.md` owns how many segments each grouping shows.
- **R-32-572** The separator MUST be the single right-pointing angle quotation mark `›`, U+203A,
  with one hair space, U+200A, on each side, set inside the same text run as the segments. The
  separator MUST be a character that cannot appear in a Herdr workspace, tab or pane name. `/` is
  unusable: a workspace often carries the name of a Git branch such as `feature/foo`, so a `/`
  separator splits one name into two and shows a level that does not exist. A hair space is
  typographic space inside a text run and not a layout gap, so `R-32-300` does not reach it. A
  wireframe writes the separator `>`, which is an ASCII convention and not the rendered glyph.
- **R-32-573** A breadcrumb that does not fit MUST elide from the **front** and MUST keep the last
  segment whole: `… › plugin › pane 2`, never `herdr-relay › plugin › pan…`. The last segment is the
  pane, which is the thing the person taps and the thing an alert names, so it is the segment that
  MUST survive. If the last segment alone overflows, it MUST truncate at its own tail.
- **R-32-574** A breadcrumb MUST be exactly one semantics node, read as one phrase. It MUST NOT
  expose one node for each segment. Its label MUST replace each separator with a comma, per
  `R-32-505`, because a screen reader either names U+203A or drops it, and neither outcome is a
  location. A person needs one place spoken, not three labels and a punctuation mark.
- **R-32-575** The separator MUST NOT be an icon widget. Two reasons. Three inline icons on every
  row of a long list is a real cost for no gain. And an icon cannot take part in text elision, so
  `R-32-573` could not be met: the run that elides has to hold its own separators to know where a
  segment ends.

### 7.25 Row action menu

A long press on a row opens this menu, and the person taps an action (`R-30-296`, amended
2026-09-18 by the product owner: the swipe action pane this section drew until then is retired,
because the Flutter SDK ships no swipe-action widget and `R-03-059` forbids an imitation).
`docs/33-platform-chrome.md` `R-33-080` owns the platform surface on each side, `docs/30-ux-spec.md`
owns the behaviour, and this section owns the item anatomy, which is the anatomy of a menu from a
control (`R-33-078`) so a row's `⋮` and its long press draw the same item.

| Part | Value |
| --- | --- |
| Surface | the platform menu's own, per `R-33-080`; the app paints no surface of its own |
| Item | the platform's own item: `MenuItemButton` on Android, `CupertinoContextMenuAction` on iOS |
| Item glyph | the action's glyph from `R-32-401` at `size.icon.md`, leading on Android, trailing on iOS |
| Item label | the action's own word or two, in the interface face of `R-32-200` |
| Ink, a normal action | the platform item's own |
| Ink, a destructive action | `color.status.error` on the glyph and the label on Android, `isDestructiveAction` on iOS |
| iOS preview | the row itself on `color.bg.raised` at `radius.md`, the lifted copy the platform draws |

- **R-32-576** The table above is normative. A destructive action MUST be the last item. The item
  order MUST be the same on both platforms and the same from the `⋮` and from the long press. At
  a large text scale an item MUST grow with its label and MUST NOT shrink its label, its glyph or
  its target, per `R-32-210` and `R-32-363`, which the platform items do on their own.
- **R-32-577** A row action MUST carry an icon **and** a short label. An icon MUST NOT be the
  only carrier of meaning, per `R-32-404` and `R-30-141`, and that rule reaches a menu item as it
  reaches every other control. So a bare trash can is not permitted, although the trash can is still
  the thing the person recognises: it sits beside the word `Forget`.
- **R-32-578** A destructive row action MUST raise the confirmation dialog of section 7.17 on the
  tap and MUST NOT act at once. That dialog is the destructive confirmation of `R-32-547`, which
  `R-30-005` permits; a row action MUST NOT raise any other modal. No gesture MUST be able to reach
  the action and skip the dialog; `R-30-297` fixes that. On cancel the row stays.
- **R-32-579** A destructive row action MUST NOT take a red fill. Its fill is the platform item's
  own, and the destructive signal is the platform's destructive role: the `color.status.error`
  glyph and label on Android, `isDestructiveAction` on iOS. `color.status.error` on
  `color.bg.raised` measures 3.08 in dark and 4.11 in light against the 3.0 indicator floor, and
  passes in `R-32-150`. A red fill is measurably available, per `R-32-126`, and version one MUST
  NOT use it, per `R-32-527`.
- **R-32-580** Every row action MUST also exist as a named custom semantics action on the row,
  per `R-32-515`. Its name MUST be the action's own label, so `Remove` is spoken as `Remove`; the
  one exception is the computer row, whose spoken name `Forget this computer` is fixed by
  `docs/31-mockups/05-host-list.md`.
- **R-32-581** The app MUST NOT build a row action from `Dismissible`, and MUST NOT draw a swipe
  pane of its own. `Dismissible.background` and `Dismissible.secondaryBackground` are
  non-interactive decoration that disappears with the child, so neither one can hold an action,
  and a drawn pane is the imitation `R-03-059` forbids. This rule states the anatomy reason,
  because an implementer who reads `Dismissible.background` in the SDK will otherwise assume it
  can hold action buttons.

### 7.26 The grouping strip

The strip that carries the segmented control of section 7.6 above a grouped list.

| Part | Value |
| --- | --- |
| Height | the control at the component's own height plus `space.3` above and below, on both platforms, per `R-32-521` (amended 2026-09-09 per the `R-03-059` addendum: was `size.target.min` on Android) |
| Surface | `color.bg.base` |
| Control inset | `space.4` from each edge |
| Bottom edge | `border.hairline` in `color.border.strong`, the block's one edge, per `R-32-582` |
| Position | directly under the app bar and above the first row |

- **R-32-582** The app bar and the strip MUST read as one header block. `R-32-115` and `R-32-510`
  fix the app bar's edge and its colour; this rule fixes where it sits. When no strip is present
  the `border.hairline` in `color.border.strong` sits under the app bar. When a strip is present
  the app bar MUST draw no hairline, and the block's one hairline sits under the strip; the first
  group header of the list follows at its own `space.6` gap. (Amended 2026-09-09 by the product
  owner, per `R-03-059`.) Until that date the block drew no hairline at all and the 2 px
  `color.accent.primary` underline of the app's own selected segment was the only edge; the
  platform segmented control of section 7.6 draws no underline, so the edge moves to the strip's
  bottom. The product owner's refusal of 2026-09-03 stands in its point: two hairlines, one under
  the bar and one under the strip, draw a box around the control and split the block in two, and
  the block MUST NOT draw both.
- **R-32-583** The strip MUST NOT scroll away with the list. It is part of the header block, not the
  first row of the list. A control that scrolls out of reach makes the person scroll back before
  changing the axis.

### 7.27 Eyebrow

| Part | Value |
| --- | --- |
| Rule | 24 x 1 px in `color.accent.primary` |
| Gap | `space.3` |
| Text | `type.micro` UPPER in `color.accent.text` |

- **R-32-590** An eyebrow introduces the welcome hero, the empty-state title, and the full-screen
  blocking state title. It is a thin accent rule followed by a tracked upper-case label.

### 7.28 Ghost button

| Part | Value |
| --- | --- |
| Widget | the platform's own secondary button, per `R-03-059`: `OutlinedButton` on Android, `CupertinoButton.tinted` on iOS, built by `app/lib/widgets/app_ghost_button.dart` alone; every value below reaches it through `outlinedButtonTheme` on Android and `CupertinoThemeData.primaryColor` with `textTheme.actionTextStyle` on iOS, and the widget sets no style of its own but the iOS label ink of the `Label` row. iOS has no outlined idiom: the tinted button is its bordered secondary button, so on iOS the ghost is the component's own `color.accent.primary` tint with the label in `color.accent.text`, no border, and the component's own inset, height and corner (added 2026-09-09 by the product owner) |
| Height | the component's own on both platforms, per the `R-03-059` addendum of 2026-09-09: Material 3's 40 inside its 48 tap target on Android; on iOS per the `Widget` row. The theme sets no height (was `size.button.primary` through `outlinedButtonTheme`; the ghost stays the filled button's sibling because both keep the same platform metrics) |
| Fill | none on Android; the component's tint on iOS |
| Border | `border.hairline` in `color.border.strong` on Android; none on iOS |
| Radius | the component's own on both platforms: Material 3's pill on Android, 12 on iOS (amended 2026-09-09 per the `R-03-059` addendum: was `radius.sm` through the theme) |
| Label | the platform's own label style of `R-32-212` in `color.fg.primary`, as written, with the component's own inset, on Android (amended 2026-09-09 by the product owner, per `R-03-104`: was `type.mono.button` UPPER; amended the same day per the `R-03-059` addendum: was `space.4` through the theme); `color.accent.text` with the component's inset on iOS (amended 2026-09-09 by the product owner: was `color.accent.primary`, which measures 3.6 on the tinted fill over `color.bg.raised` in light, under the 4.5 of `R-32-124`; `color.accent.text` measures 4.68 there, and the widget hands it to the component as `foregroundColor`, as the key cap of section 7.12 and the text action of `R-32-526` do) |
| Pressed | the platform's own response (amended 2026-09-09 by the product owner, per `R-03-059`): on Android the ink overlay in `color.accent.soft` under a `color.accent.primary` border, both set by the theme; on iOS the Cupertino press fade. No app-drawn fill and no scale |
| Loading | the label gives way to a `size.spinner` spinner in the label's ink; the control is disabled meanwhile, so it takes the dim of `R-32-502` (amended 2026-09-09, per `R-03-059`) |
| Disabled | the same border and label at `opacity.disabled`, no colour change, per `R-32-502`, through the theme's disabled colours (amended 2026-09-08 by the product owner: an earlier row recoloured the fill, the border and the label, the double signal `R-32-331` forbids) |

- **R-32-591** The ghost button replaces every secondary/outlined button use. Its pressed state on
  Android is a soft accent wash with an accent border, the platform's own overlay coloured by the
  theme; on iOS it is the platform's press fade. It carries no shadow. (Amended 2026-09-09 by the
  product owner, per `R-03-059`.) A screen MUST compose `app/lib/widgets/app_ghost_button.dart`
  and MUST NOT set a style on it.

### 7.29 State bar

The one state indicator of the app, per `R-03-100` (amended 2026-09-09 by the product owner: the
status dot of this section is retired; the section keeps its number, because other documents cite
it). A rectangle in the state's hue, beside the state word its row draws.

| Part | Value |
| --- | --- |
| Width | `border.attention` |
| Height | the full height of its row; on a strip or an app bar, the text line it sits beside |
| Position | flush to the leading edge of its row or block, painted over the fill so the content keeps its inset |
| Shape | a rectangle, `radius.none`; nothing else varies by state, so hue and the word beside the bar carry the state |
| Working | `color.status.working`, `motion.pulse` |
| Idle | `color.status.idle` |
| Blocked | `color.status.blocked` |
| Done | `color.status.done` |
| Error | `color.status.error` |
| Unknown | `color.status.unknown` |
| Ok | `color.status.ok`, no pulse (added 2026-09-08: a connected connection leg on `docs/31-mockups/13-connection.md` had borrowed `done`, whose hue means an agent finished) |
| Warning | `color.status.warning`, no pulse (added 2026-09-09: the live bar of section 7.3 past its 60 seconds and a warning connection leg on `docs/31-mockups/13-connection.md` had borrowed `working`, which pulses; a stale link is not work) |
| Word | the row's own state word, `space.2` after the bar where the bar sits inline with text (the icon-to-label gap of `R-32-301`); the bar itself draws no word |

- **R-32-592** The state bar is the single state indicator for agents, computers, connections, the
  terminal strip and the app bar (amended 2026-09-09 by the product owner, per `R-03-100`: it was
  the status dot, which pulsed for `working`, was hollow for `idle` and filled otherwise; every
  shape is retired). `working` pulses; no other state changes the shape. The word beside the bar
  is the state's non-colour signal, per `R-30-141`. An unread or selected row is carried by weight
  and wash, per section 7.4, never by a second bar. `ok` is the connection leg's healthy state and
  MUST NOT stand in for an agent state, which `R-30-401` fixes as five (amended 2026-09-08).

### 7.30 Card

| Part | Value |
| --- | --- |
| Surface | `color.bg.raised` |
| Border | 1 px `color.border.subtle` |
| Radius | `radius.md` |
| Padding | `space.4` |
| Featured top edge | `border.accent` 2 px `color.accent.primary` |

- **R-32-593** A card is a raised panel with a subtle border. A featured card (welcome steps card,
  empty-state card) adds a 2 px accent top edge.

### 7.31 The welcome hero

| Part | Value |
| --- | --- |
| Block | top safe-area edge, height 42% of screen height, plain `color.bg.base` with no ground grid, bottom edge 1 px `border.subtle` |
| Brand mark | `assets/brand/ram.png` in `color.fg.primary`, height 64% of hero, anchored top-right: right crop flush with screen right edge, bottom crop exactly on hero bottom rule |
| Eyebrow | `HERDR REMOTE` above the bottom rule by `space.4` |
| Headline | `type.display` in `color.fg.primary`, two lines: `Watch the herd.` / `From anywhere.` |
| Subtext | `type.body` in `color.fg.secondary`: `Read a pane. Send a prompt. Nothing else crosses the network.` |
| Featured steps card | three steps; step number `type.mono.button` `color.accent.text` zero-padded `01 02 03` (amended 2026-09-09 by the product owner, per `R-03-104`: the actions below it are the platform's own sans label now, so the step number is the card's one mono size); step text `type.body` |
| Alert note | existing copy, `type.caption` `color.fg.secondary` with `info` icon at `size.icon.sm` aligned to the first line, per `R-32-402` (amended 2026-09-08 by the product owner: in `type.body` the two sentences ran to nine lines, the content column overran the 375 by 667 reference viewport and `R-31-01-08` gave the hero zero height, so the brand mark and the eyebrow never showed; the note is a secondary line, which is the token's own use) |
| Primary button | `Scan QR code` |
| Text button | `Enter the phrase instead` |

- **R-32-594** The welcome hero is the only screen where the brand mark appears in the app chrome
  as a figure. (Amended 2026-09-09 by the product owner, per `R-03-107`: the silhouette is also
  permitted as the empty-state watermark of `R-32-554`, in `color.bg.grid` ink, with the same
  bottom-right anchoring; that watermark is ground, not a figure, and this rule's anchoring is its
  precedent.) The mark's right and bottom crop edges sit on real edges (screen right, hero bottom
  rule), never floating. The hero band is plain `color.bg.base`; the ground grid of `R-32-332`
  starts below the hero rule. The composition: plain hero with mark and eyebrow, then on the grid:
  display headline, subtext, featured card, note, primary button, text button.

### 7.32 Space block

The `Workspace` axis of `docs/31-mockups/06-agent-list.md` draws one block per space, decided
2026-09-04 by the product owner so that parenting reads at a glance: the block is the container,
the headers of section 7.23 sit inside it on the ladder of `R-32-570`, and every pane of the
space is a row inside it.

| Part | Value |
| --- | --- |
| Surface | the card of section 7.30: `color.bg.raised`, 1 px `color.border.subtle`, `radius.md` |
| Screen inset | `space.4` at the leading and trailing edge, over the page's `color.bg.base` |
| Gap between two blocks | `space.6`, the group gap of `R-30-231` (amended 2026-09-08 by the product owner: 12 between two blocks read tighter than the 24 between two rows inside one; was `space.3`); the search field of `R-32-598` keeps `space.3` above it, and the first block follows the field by `space.6` |
| Header | tier 1 of section 7.23: the `color.bg.high` band with the space name, `N panes`, the badge of `R-32-518` when a pane inside needs attention, and the expander trailing (amended 2026-09-09) |
| Hairline under the header | none: the band's own edge is the line (amended 2026-09-09 by the product owner, per `R-03-057`; was a full-width `border.hairline`) |
| Hairline between two worktree rows | `border.hairline` in `color.border.subtle`, the block's full width, after the `space.3` gap that closes the tab group above (amended 2026-09-09) |
| Hairline between two tabs | `border.hairline` in `color.border.subtle`, from the tab glyph's `space.6` to the trailing edge, after the `space.3` gap that closes the group above (amended 2026-09-09, was from `space.16` with no gap) |
| Group gap | `space.3` under the last pane row of every tab, before the next hairline or the block's bottom edge (added 2026-09-09, per `R-03-057`: rows under one tab touch, so one more `space.3` is what separates two groups) |
| Guide rule | `border.hairline` in `color.border.subtle` at `space.8`, the tab glyph's centre, from the tab header's bottom through the full height of its pane rows; not a divider, takes no touch (added 2026-09-09, per `R-03-057`) |
| Divider between two pane rows | none |
| Pane row | one 48-high line with `space.3` above and below; the leading slot is `size.icon.sm` wide at `space.10` and the text starts `space.2` later at `space.16`; an agent leaves the slot empty, draws the full-height state bar after the guide rule, then shows kind in `type.body`, `space.2`, and pane name in `type.caption`, with state in `type.body` and optional age in `type.caption` trailing on that baseline (amended 2026-09-10 per `R-03-115`) |
| Shell row | one 48-high line with the `A pane` glyph in the leading slot, display name in `type.body` `color.fg.secondary`, then `space.2` and optional `title` in `type.caption` `color.fg.secondary`; no state word or bar (amended 2026-09-10 per `R-03-115`) |
| Collapsed | the header alone, with its count and badge (`R-32-566`), no hairline |

- **R-32-595** The table above is normative. A block MUST take the card anatomy of `R-32-593` and
  MUST NOT draw a stronger border: the hairline and the corner are what read as a container, and a
  `color.border.strong` box around every space would read as a control (`R-32-113`). The trailing
  count MUST be `N panes`, one number, because the `Workspace` axis lists every pane and a second
  number in the same caption is noise; the badge carries the count that matters. No block pins,
  per `R-32-565`.
- **R-32-596** The lines of the table are the only lines inside a block, and a pane row MUST NOT
  draw its own divider there (amended 2026-09-09 by the product owner, per `R-03-057`): the
  header band's edge closes the header, the worktree hairline spans the block, the tab hairline
  starts at the tab glyph, each after the `space.3` group gap, and the guide rule hangs a tab's
  rows off its glyph. Rows under one tab touch. The band, the type step, the glyph, the indent and
  the guide rule already say which tier a row is, so no further line is permitted.
- **R-32-597** A shell row MUST NOT borrow an agent state: no state bar or status word. Pin actions
  follow `R-32-708`. Its leading slot holds the `A pane` glyph of `R-32-401` where an agent row
  holds its
  state bar. Its display name and optional `title` MUST share one baseline, separated by
  `space.2`, so it keeps the same 48-high step as an agent row (amended 2026-09-10 per
  `R-03-115`). The `unknown` glyph MUST NOT stand in for "no agent", because `R-30-404`
  reserves it for an agent whose status the app cannot read.
- **R-32-598** The pane search of `docs/31-mockups/06-agent-list.md` `R-31-06-30` uses the
  platform control in the `Search a list` row of `R-33-033`, per `R-03-102`. On Android it is
  the search action of the `Agents` app bar, the `search` glyph of `R-32-401` as a
  `ChromeIconAction`, which opens the Material search view, `SearchAnchor`; the view's fill,
  edge and type come from `searchViewTheme`. On iOS it is a `CupertinoSearchTextField` at the
  start of Workspace content, inset `space.4` horizontally, with `space.3` above and `space.6`
  before the first space block (amended 2026-09-16 by the product owner). It scrolls with the
  content. The title bar and grouping strip keep the same position on both axes. The app sets
  only the placeholder `Search panes`. It MUST NOT restyle the component: no border, radius
  or fill of its own, because a platform component keeps its own shape, per `R-33-033`.
  A search that matches nothing MUST retain the field and grouping strip and MUST say so in
  one `type.body` line in `color.fg.secondary`, `No pane matches "x".`, inset `space.4`; the
  empty state of `R-32-553` is for a computer with no pane, never for a search.

### 7.33 Inline key

A key or a chord named in a sentence, per `R-03-103` (decided 2026-09-09 by the product owner, who
pointed at "the r key" printed as a word): the footnote of `docs/31-mockups/14-devices.md`, the
forget dialog body of `docs/31-mockups/05-host-list.md`, the latch hint of
`docs/31-mockups/09-key-row.md` and the `phrase_expired` sentence of `docs/30-ux-spec.md`. The cap
is `app/lib/widgets/key_label.dart`.

| Part | Value |
| --- | --- |
| Label | `type.mono.key` in `color.fg.primary`, the key as written: `r`, `d`, `Enter`, `ctrl+c` |
| Fill | `color.bg.high` |
| Border | `border.hairline` in `color.border.strong` |
| Radius | `radius.sm` |
| Padding | `space.1` horizontal, `space.0` vertical |
| Alignment | on the sentence's alphabetic baseline, inside the same text run as the prose |
| Escape | the text cap `esc`, per `R-32-403`; never a glyph |
| Semantics | the sentence reads as plain prose with the spoken key name in place of the cap: `r` reads `r`, `ctrl+c` reads `Control C`, the words the key cap of section 7.12 already speaks |

- **R-32-599** A key named in interface text MUST be drawn as this cap and MUST NOT be printed as a
  plain word, per `R-03-103`. The cap is not a control: it takes no target floor, no pressed state
  and no focus ring, so `size.keycap` and `R-32-535` do not reach it, and it MUST NOT be tappable.
  A screen writes the sentence once as a template, `the {r} key in the Relay pane`, and
  `keyedText` draws every `{...}` span as one cap on the prose's baseline; a screen reader gets the
  template with each span replaced by its spoken name, and an announcement of the sentence uses that
  same plain form. The map of `R-32-401` lists `A key named in a sentence` as `none`: the key is
  text, never an icon, and it keeps the case the person types, so `Enter` and `esc` stay as written.

### 7.34 Pinned rows

- **R-32-708** A pinned row MUST show a pin glyph at `size.icon.sm` in `color.fg.secondary`.
  Use `Symbols.keep_rounded` for the row glyph and the `Pin` action.
  Use `Symbols.keep_off_rounded` for the `Unpin` action.
  Each action MUST be an item of the row's platform menu of `R-33-077`, with the
  non-destructive anatomy of section 7.25.
  `Pin` or `Unpin` MUST precede `Mark as seen` when both actions apply.
  Each action MUST expose the named semantics required by `R-32-515`.
  The `Workspace` `PINNED` card MUST use flat rows without hierarchy indentation.
  Pane content MUST start at the header inset, `space.4`.
  An agent state bar MUST sit at the card edge. An agent row MUST NOT reserve an empty leading slot.

## 8. Motion

| Token | Value | Material token it matches |
| --- | --- | --- |
| `motion.duration.instant` | 0 ms | none; the absence of animation |
| `motion.duration.fast` | 120 ms | between `short2` at 100 and `short3` at 150 |
| `motion.duration.base` | 200 ms | `short4` exactly |
| `motion.duration.slow` | 320 ms | closest is `medium3` at 350; a hold, never a transition, per `R-32-604` |
| `motion.curve.enter` | `Curves.easeOutExpo` | - |
| `motion.curve.exit` | `Curves.easeOutQuart` (amended 2026-09-08 by the product owner: an exit is an ease-out too, per `R-32-609`; was `Curves.easeInQuart`) | - |
| `motion.curve.move` | `Curves.easeInOutQuart` | - |
| `motion.curve.emphasis` | `Curves.easeInOutCubicEmphasized` | - |
| `motion.pulse` | 2200 ms, `Curves.easeInOut`, opacity 0.25 to 1.0 and back, repeats | - |
| `motion.scale.press` | 0.97 (added 2026-09-08 by the product owner, per `R-32-609`) | - |

| Purpose | Duration | Curve |
| --- | --- | --- |
| Press feedback on a row, a header or a strip; a platform button, and since 2026-09-09 a key cap, takes its own press timing, per `R-03-059` (amended 2026-09-09) | `motion.duration.fast` in, `motion.duration.instant` out (amended 2026-09-08, per `R-32-609`) | `motion.curve.enter`, plus `motion.scale.press` |
| Screen transition, a route change | `motion.duration.base` | `motion.curve.enter` in, `motion.curve.exit` out |
| Bottom sheet, open and close | `motion.duration.base` | `motion.curve.enter` in, `motion.curve.exit` out |
| Dialog, open and close | `motion.duration.base` | `motion.curve.enter` in, `motion.curve.exit` out |
| Bank two of the key row, open and close | `motion.duration.instant` (amended 2026-09-10 per `R-03-116`: this row named the retired Shortcuts palette, whose own note of 2026-09-08 said the surface is opened tens of times a day, most often to stop a runaway command, and any size change would move the terminal grid, which `R-32-602` forbids; was `motion.duration.slow` with `motion.curve.move`) | none |
| A transient readout, the text-size flash of `R-30-302` | `motion.duration.slow`, as a hold | none |
| A status badge change | `motion.duration.instant` | none |
| A terminal grid repaint | `motion.duration.instant` | none |
| Working state bar pulse | `motion.pulse` | the pulse's own `Curves.easeInOut`, per `R-32-608` (corrected 2026-09-08: an earlier row named `motion.curve.enter`, which is `easeOutExpo`; renamed 2026-09-09 from the status dot, per `R-03-100`) |
| Live bar pulse | `motion.pulse` | the pulse's own `Curves.easeInOut`, per `R-32-608` (renamed 2026-09-09 from the live connection dot, per `R-03-100`) |
| The `Priority` / `Workspace` axis switch on Android | the platform's own: `TabBarView` page physics, which track the finger and take its velocity (added 2026-09-09 by the product owner, per `R-03-108`) | none of this table; the platform's |

- **R-32-600** The tables above are the complete motion set, and they are the value side of
  `R-30-270` to `R-30-274`. (Note, 2026-09-09, per `R-03-108`.) Physical motion comes from the
  platform, not from a new token: the Android axis switch of `R-30-274` is `TabBarView`'s own page
  physics, the iOS axis switch is the segmented control's own transition, a sheet follows the finger
  as the platform's draggable sheet, and a pushed route keeps the platform's interactive back
  gesture (`R-33-070`). This document adds no curve and no duration for any of them, and the app
  MUST NOT drive them with a token of this section. `R-32-606` still reaches the settle after the
  finger lifts, which is then an instant swap like the route change of `R-32-607`; the drag itself
  is input, not animation, and stays.
- **R-32-601** A status badge MUST NOT animate. A cross-fade between `working` and `done` flashes a
  colour through a transitional state on a polling tick, which teaches a person to distrust the
  badge. The only continuous animations in the app are the `working` state bar pulse and the live
  bar pulse (amended 2026-09-09, per `R-03-100`), both using `motion.pulse` (2200 ms,
  `Curves.easeInOut`, opacity 0.25 to 1.0 and back, repeats). Reduce motion holds opacity at 1.0.
- **R-32-602** The terminal grid MUST NOT animate, per `R-30-272`. This is the most important motion
  rule in the product: a fade over pane content makes a person doubt what they read.
- **R-32-603** `motion.duration.fast` at 120 ms is chosen for one reason: the terminal gives no
  local echo for a control key, so the phone must answer before the person's next tap. It equals the
  frame coalescing window that `docs/21-terminal-rendering.md` owns, and that equality is a
  coincidence, not a shared cause.
- **R-32-604** `motion.duration.slow` stays 320 ms rather than moving to the Material `medium3`
  token at 350 ms. The difference is not perceptible, and every mockup and `R-30-270` already fix
  the token by name, so the change would buy a table entry and cost a repository-wide edit.
  (Amended 2026-09-08 by the product owner.) `motion.duration.slow` is a **hold**, not a
  transition: it times how long a transient readout stays on screen, per `R-30-302`, and the period
  of the pairing frame fade of `docs/31-mockups/02-pair-scan.md`. A transition of a UI element, an
  enter, an exit, a move or a press, MUST use `motion.duration.fast` or `motion.duration.base` and
  MUST NOT use `motion.duration.slow`, because a UI transition MUST finish under 300 ms: a 180 ms
  surface reads as more responsive than a 400 ms one, and 320 ms sits on the wrong side of that
  line. The code agrees: the only caller of `AppMotion.durationSlow` is the readout timer of
  `R-30-302`.
- **R-32-605** The app MUST NOT use `Curves.bounceOut`, `Curves.elasticOut`, `Curves.elasticIn`,
  `Curves.elasticInOut`, `Curves.easeOutBack` or any other overshoot curve, per `R-30-271`.
- **R-32-606** Reduced motion. The platform settings are **Reduce Motion** on iOS and iPadOS, at
  Settings > Accessibility > Motion > Reduce Motion, and **Remove animations** on Android, at
  Settings > Accessibility > Colour and motion > Remove animations. The app MUST read both through
  the single Flutter query `MediaQuery.disableAnimationsOf(context)`. When it is true every
  `motion.duration.*` becomes 0 ms, every `motion.curve.*` becomes `Curves.linear`, the `working`
  rotation stops with the icon still in its colour, and no information is removed, per `R-30-730` to
  `R-30-732`.
- **R-32-607** Under reduced motion a route change MUST be an instant swap, not a cross-fade. Apple
  recommends replacing an axis transition with a cross-fade, and this product diverges on purpose: a
  cross-fade over a terminal grid breaks `R-30-272`. The divergence is recorded here so it is not
  read as an oversight.
- **R-32-608** `motion.pulse`: 2200 ms, `Curves.easeInOut`, opacity 0.25 to 1.0 and back, repeats.
  Used by the `working` state bar and the live bar (amended 2026-09-09, per `R-03-100`). Reduce
  motion holds opacity 1.0.
- **R-32-609** (added 2026-09-08 by the product owner) Press feedback MUST answer on pointer-down,
  never on release, and MUST be asymmetric. On pointer-down a pressable control MUST take its
  pressed fill of `R-32-501` **and** scale to `motion.scale.press` around its centre, both over
  `motion.duration.fast` with `motion.curve.enter`. On release, and on a cancelled press, both MUST
  snap back at `motion.duration.instant`: the person decides on the way down, and the system answers
  on the way up. A press that ends before `motion.duration.fast` has elapsed MUST stay visible until
  it has, so a quick tap still shows one full press: Flutter's tap recogniser inside a scrollable
  reports the down and the up together for a tap shorter than its 100 ms deadline, and a press
  nobody sees is no feedback. The scale is a transform only; a control MUST NOT animate its size, its
  padding or its position to show a press, and MUST NOT animate a layout property for any reason.
  This reaches every pressable the app draws itself: the list row, the tier 1 section header and
  the strip's destination tap. Under `R-32-606` the scale is 1.0 and the fill change is instant.
  `motion.curve.exit` is an ease-out for the same reason: an ease-in delays the first frame of the
  movement the person is watching for, so it MUST NOT be used on a UI element. (Amended 2026-09-09
  by the product owner, per `R-03-059`.) A button is the platform's own widget and takes the
  platform's own press response, the Material ink overlay or the Cupertino press fade, on the
  platform's own timing. The filled, ghost and text buttons and the key cap left this rule on that
  date; the app MUST NOT add this scale, this fill or this timing to a platform button.

## 9. The Host popup pane

The plugin's only user surface is a Herdr popup pane drawn with `ratatui` inside the terminal and
the theme the person already chose. Nothing in this document's palette applies to it.

| Purpose | Value |
| --- | --- |
| Default text and default background | `Color::Reset`, which is also the enum default, so a `Style` that names no colour inherits the terminal's own pair |
| The eight basic hues | `Color::Black`, `Color::Red`, `Color::Green`, `Color::Yellow`, `Color::Blue`, `Color::Magenta`, `Color::Cyan`, `Color::White` |
| Bright black, for a second line, a column header and the footer | `Color::DarkGray`, which `ratatui` also accepts as `light-black` and `bright black` |
| Selection | reverse video with `Modifier::REVERSED`, never a colour pair |
| Forbidden | `Color::Rgb` and `Color::Indexed` |

- **R-32-700** The popup pane MUST express every colour as a terminal-relative value. It MUST use
  `Color::Reset`, the eight basic hues, `Color::DarkGray` and `Modifier::REVERSED`, and nothing
  else. This is the value side of `R-30-601` and `R-31-16-11`.
- **R-32-701** `Color::Rgb` and `Color::Indexed` are forbidden. `Color::Rgb` pins an absolute colour
  that collides with some user themes, and `Color::Indexed` reaches beyond the 16 slots the pane is
  permitted. The same guarantee holds one layer down, where `crossterm`'s `Color::Reset` resets the
  terminal colour and is its enum default.
- **R-32-702** The pane MUST NOT have a light variant or a dark variant, and MUST NOT detect
  terminal brightness. It inherits the user's theme by construction, and `Modifier::REVERSED` swaps
  whatever that theme's own pair is, so a selection is readable under any theme.
- **R-32-703** The Selenized values in this document apply to the phone app only. No document may
  make the pane and the app match, and no document may state a hex value for the pane.
- **R-32-704** Colour MUST NOT be the only carrier of a state in the pane, which is the terminal
  form of `R-30-141`. Every state prints its word, so a monochrome terminal loses nothing.

## 10. Inspiration and precedent

| Product or system | URL | The one thing this design language takes from it |
| --- | --- | --- |
| Selenized | `https://github.com/jan-warchol/selenized` | The whole palette, and the practice of designing a light counterpart as a peer rather than as an inversion. |
| Material 3 | `https://m3.material.io/styles/motion/easing-and-duration/tokens-specs` | The numeric duration grid, and `bodyLarge` at 16/24 as `type.body`. |
| Apple Human Interface Guidelines | `https://developer.apple.com/design/human-interface-guidelines/accessibility` | The touch-target facts, the 12 point padding around a bezelled control, and "make motion optional". |
| Apple HIG, Alerts | `https://developer.apple.com/design/human-interface-guidelines/alerts` | An alert only for an uncommon destructive action a person cannot undo, which is why the app has exactly one dialog. |
| Apple HIG, Sheets | `https://developer.apple.com/design/human-interface-guidelines/sheets` | One sheet at a time, and a confirmation that replaces the sheet content instead of stacking. |
| Material Symbols | `https://fonts.google.com/icons` | The icon set, and the two directional split glyphs no other candidate carries. |
| IBM Plex | `https://github.com/IBM/plex` | The interface family, and the decision to bundle two faces and synthesise nothing. |
| IBM Carbon | `https://github.com/carbon-design-system/carbon/blob/main/packages/layout/src/index.ts` | An 8 rhythm over a 4 base, as a closed spacing set. |
| GitHub Primer | `https://github.com/primer/primitives/blob/main/src/tokens/base/size/size.json5` | A flat size scale used for both gap and size, which is why `space.*` is one scale and not two. |
| Vercel Geist, `StatusDot` | `https://vercel.com/geist/status-dot` | Animate only a non-terminal state, never flash a colour through a transitional state, and never add a spinner beside the dot. |
| Vercel Geist, `Badge` | `https://vercel.com/geist/badge` | One status vocabulary for every surface, and the timestamp beside the badge rather than inside it. |
| Vercel Geist, `Empty State` | `https://vercel.com/geist/empty-state.md` | A heading that names the absent thing, one line of guidance, at most one action. |
| Vercel Geist, error guidance | `https://vercel.com/geist/error.md` | A plain sentence with the raw text one step away, never instead of it. |
| Warp | `https://docs.warp.dev/terminal/blocks/block-basics/` | A leading bar reads as status on a dense monospace surface, which is why the attention bar is a bar and not a tint. |
| Termius | `https://docs.termius.com/terminal/mobile-terminal` | A named key strip above the system keyboard, grouped so a cluster reads as one control. |
| Blink Shell | `https://docs.blink.sh/` | The key row belongs to the on-screen keyboard, and pinch is the terminal font-size gesture. |
| Linear Mobile | `https://linear.app/mobile` | Swipe to clear an inbox item, which is the shape of `Mark as seen`. |
| Raycast for iOS | `https://www.raycast.com/changelog` | The agent-finished notification and its tap-through, and the reason this product states its delivery limit where Raycast does not. |
| Tailscale device approval | `https://tailscale.com/docs/features/access-control/device-management/device-approval` | A blocking state the client cannot resolve, with no local override and no false retry. |
| Home Assistant companion | `https://companion.home-assistant.io/docs/getting_started/` | "Enter address manually" as a first-class path, which is the relay-origin field. |
| Signal linked devices | `https://support.signal.org/hc/en-us/articles/360007320551-Linked-Devices` | The QR sits on the secondary device and the phone reads it, which is this product's topology exactly. |
| Google ML Kit barcode scanning | `https://developers.google.com/ml-kit/vision/barcode-scanning` | Any orientation scans, and the most centred code wins when several are visible. |
| 1Password | `https://support.1password.com/unlock-auto-lock/` | Biometric first, device passcode always present, which is the shape of `/lock`. |
| `ratatui` | `https://docs.rs/ratatui/latest/ratatui/style/enum.Color.html` | `Color::Reset` and reverse video, so the Host pane inherits the user's theme instead of choosing one. |
| Herdr (herdr.dev) | `https://herdr.dev/css/site.css`, `https://herdr.dev/css/style.css`, `https://herdr.dev/assets/logo.png` | Ink/Paper grounds, spot accent, Archivo headlines, mono tracked labels, the grid, the pulsing live dot. |

## Retired rules

Seven `R-32` ids are retired, and all seven stay reserved. This table carries one row per retired id,
so an old citation still resolves. No number below is reused, so no row needs the word `old`. Every
other `R-32` rule in this document is live, and a live rule never appears here. Section 7.13 went
with `R-32-538`, and every section after it keeps its own number on purpose: eight other documents
cite `section 7.16` through `section 7.26` by number, so renumbering them would break every one of
those citations.

| Rule | Disposition |
| --- | --- |
| `R-32-587` | **Retired.** It fixed the floating capsule bottom-navigation shape, which came from the glass tab bar. Both platforms now take one full-width bar, per `R-33-033`, so nothing uses a capsule. The id stays reserved. `R-33-029` still forbids a floating control under the system navigation bar, and `R-32-588` carries that citation for the create control (retired 2026-09-09 and restored 2026-09-10, per the corrected `R-03-109`). |
| `R-32-334` | **Retired 2026-09-09**, per `R-03-107` step two. It was added the same day, per step one, and defined paper: an opaque `color.bg.base` or `color.bg.raised` block, exactly as tall as its content, sitting on the ground grid, composed from `PaperSliver` and `GroundRemainder` in `app/lib/widgets/app_ground.dart`. The product owner saw the grid around solid list blocks and rejected it as ugly, so a screen with content paints plain `color.bg.base` and the grid stays on the five hero screens and behind an empty state, per `R-32-332`. `PaperSliver` and `GroundRemainder` went with the rule; `app_ground.dart` keeps `EmptyMark` only. The id stays reserved. |
| `R-32-538` | **Retired.** It fixed the floating action bar, which carried `Copy`, `Paste` and `Select all` over a terminal selection. That selection surface is now the platform's own edit menu, so no screen draws an app-drawn bar and the component has no consumer left. `R-21-042` owns the mechanism and `R-31-08-22` owns the item set. The id stays reserved. Section 7.13 and the `size.fab` token went with it. |
| `R-32-424` | **Retired.** It required the brand mark to keep a fixed, non-themed appearance wherever it appeared inside the app's own chrome, and named `/welcome`'s floating brand mark as the first such use. A direct user review called that floating mark "a random image midway through the page," and `docs/31-mockups/01-welcome.md` `R-31-01-10` retired the placement. The mark now appears on `/welcome` once, as the themed silhouette anchored in the hero of `R-32-594`, tinted in `color.fg.primary`, and since 2026-09-09 as the empty-state watermark of `R-32-554` in `color.bg.grid` ink (per `R-03-107`), so a fixed, non-themed in-app appearance has no live use. The id stays reserved. The fixed appearance still holds where the mark is not in the app chrome: the launcher and the notification icon, per `R-32-411` and `R-32-412`. |
| `R-32-425` | **Retired.** It forbade placing the brand mark directly on `color.bg.base` with no field of its own, and required a `color.border.strong` field boundary for the one in-app placement `R-32-424` covered. It has no live use left, for the same reason `R-32-424` above is retired. The id stays reserved. |
| `R-32-128` | **Retired.** It defined `color.accent.secondary` as `violet`, the chrome's second decorative accent. A direct user review called the shipped result "rainbow vomit," and the fix (`R-32-103`, `R-32-104`) moved chrome to one accent only; a second decorative accent has no live use under that policy and MUST NOT be reintroduced without reopening it. The id stays reserved. |
| `R-32-129` | **Retired.** It defined `color.accent.secondary.bright`, the `br_violet` companion icon ink to `R-32-128`'s border. It is retired for the same reason and at the same time as `R-32-128`, which it always depended on: the two MUST NOT exist independently. The id stays reserved. |

## Open questions

- **The IBM Plex release tag, and whether a variable build of Plex Sans ships.** The Plex README
  points at the releases page without naming a version, and this repository cannot confirm a tag.
  Recommended default, and the rule the body states: bundle the two static TTF faces of `R-32-200`
  from `packages/plex-sans/fonts/complete/ttf/`, never a variable build, and record the exact
  release tag in the dependency table that `docs/20-mobile-framework.md` owns. Page to read:
  `https://github.com/IBM/plex/releases`.
- **The `material_symbols_icons` version at implementation time.** The package tracks upstream icon
  additions, so its version moves. Recommended default, and the rule the body states: pin
  `4.2960.0`, which was the published version on 2026-08-24, and let
  `docs/20-mobile-framework.md` carry the pin as it carries every other dependency version. Page to
  read: `https://pub.dev/packages/material_symbols_icons`.

## Sources

- `https://github.com/jan-warchol/selenized/blob/master/the-values.md` - every hex value in section
  3.1, for Selenized dark, Selenized light and the two Selenized black values of `R-32-101`.
- `https://github.com/jan-warchol/selenized/blob/master/manual-installation.md` - the published slot
  mapping that `R-32-140` follows and `R-32-141` deviates from in one slot.
- `https://github.com/jan-warchol/selenized/blob/master/LICENSE.txt` - MIT, Copyright (c) 2021 Jan
  Warchoł.
- `https://www.w3.org/TR/WCAG22/#dfn-relative-luminance` and
  `https://www.w3.org/TR/WCAG22/#dfn-contrast-ratio` - the formula every ratio in this document was
  computed with.
- `https://www.w3.org/TR/WCAG22/` - success criterion 1.4.1 for colour alone, 1.4.3 for the 4.5 text
  threshold, 1.4.11 for the 3.0 indicator floor, and 2.5.8 for the 24 by 24 target floor.
- `https://developer.apple.com/design/human-interface-guidelines/accessibility` - the published
  default control size of 44 by 44 points, the minimum of 28 by 28 points, the about 12 points of
  padding around a bezelled element, and the Reduce Motion setting.
- `https://developer.android.com/guide/topics/ui/accessibility/apps` - the published 48dp by 48dp
  touch-target recommendation.
- `https://support.google.com/accessibility/answer/11183305` - the Android Remove animations
  setting.
- `https://developer.apple.com/design/human-interface-guidelines/typography` - the Apple Dynamic
  Type table, Body at 17/22, and the iOS legibility floor of 11 that `R-32-206` uses.
- `https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/material/typography.dart`
  - the generated Material 3 type-scale values, including `bodyLarge` at 16/24, which `R-32-203`
  adopts.
- `https://github.com/flutter/flutter/blob/master/dev/tools/gen_defaults/data/motion.json` - the
  Material 3 duration tokens `short2`, `short3`, `short4` and `medium3` that section 8 maps against.
- `https://api.flutter.dev/flutter/animation/Curves-class.html` - `easeOutExpo`, `easeOutQuart`,
  `easeInOutQuart`, `easeInOutCubicEmphasized`, and the overshoot curves `R-32-605` forbids.
- `https://api.flutter.dev/flutter/widgets/MediaQuery/platformBrightnessOf.html` - the aspect query
  that `R-32-013` uses, and its published rebuild behaviour.
- `https://api.flutter.dev/flutter/material/ThemeMode.html` - `ThemeMode.system`, "use either the
  light or dark theme based on what the user has selected in the system settings".
- `https://api.flutter.dev/flutter/widgets/MediaQuery-class.html` - `textScalerOf`, `boldTextOf` and
  `disableAnimationsOf`, which sections 4 and 8 read.
- `https://api.flutter.dev/flutter/widgets/Dismissible-class.html` - the `background` and
  `secondaryBackground` properties that `R-32-581` forbids as a carrier for a revealed action.
- `https://github.com/IBM/plex/blob/master/LICENSE.txt` - SIL Open Font License 1.1 for IBM Plex.
- `https://github.com/IBM/plex/tree/master/packages/plex-sans/fonts/complete/ttf` - the face file
  names in `R-32-200`.
- `https://github.com/google/material-design-icons/blob/master/LICENSE` - Apache-2.0 for Material
  Symbols.
- `https://fonts.google.com/icons` - the Material Symbols name list that `R-32-401` was checked
  against.
- `https://github.com/google/material-design-icons/blob/master/variablefont/MaterialSymbolsRounded%5BFILL%2CGRAD%2Copsz%2Cwght%5D.codepoints`
  - the Rounded codepoint list every name in `R-32-401` was verified against, including the rows for
  `done_all` at `e877`, `delete_outline` at `e92e`, `add` at `e145`, `create_new_folder` at `e2cc`,
  `tab_new_right` at `f741`, `splitscreen_add` at `f4fd` and `link_off` at `e16f`; `remove` at
  `e15b` and the Rounded `check` at `e668` were verified 2026-09-09 in `material_symbols_icons`
  4.2960.0.
- `https://pub.dev/packages/material_symbols_icons` - the delivery package and version in
  `R-32-400`.
- `https://docs.rs/ratatui/latest/ratatui/style/enum.Color.html` and
  `https://github.com/ratatui/ratatui/blob/main/ratatui-core/src/style/color.rs` - `Color::Reset`,
  the eight basic hues, `Color::DarkGray` and its `light-black` aliases, and the `Rgb` and `Indexed`
  variants that `R-32-701` forbids.
- `https://docs.rs/ratatui/latest/ratatui/style/struct.Modifier.html` - `Modifier::REVERSED`.
- `https://github.com/crossterm-rs/crossterm/blob/master/src/style/types/color.rs` - crossterm's
  `Color::Reset`, "Resets the terminal color", and its enum default.
- `https://github.com/carbon-design-system/carbon/blob/main/packages/layout/src/index.ts` - the IBM
  Carbon spacing tokens that section 5.1 measures against.
- `https://vercel.com/geist/status-dot`, `https://vercel.com/geist/badge`,
  `https://vercel.com/geist/empty-state.md`, `https://vercel.com/geist/error.md` and
  `https://vercel.com/geist/tabs.md` - the component precedents in section 10.
- `https://developers.google.com/ml-kit/vision/barcode-scanning` - the scanning facts behind
  `R-32-558` and `R-32-559`.
- `https://herdr.dev/css/site.css` - brand values for `html[data-mode="ink"]` and `html[data-mode="paper"]`.
- `https://herdr.dev/css/style.css` - legacy tokens for `[data-palette="herdr"]` and `:root`.
- `https://herdr.dev/assets/logo.png` - the brand mark tile composition.
- `https://github.com/Omnibus-Type/Archivo` - Archivo font family, SIL OFL 1.1.
- `docs/21-terminal-rendering.md` - `R-21-010` the terminal line-height ratio and the permitted size
  list it cites, and `R-21-011` the monospace family.
- `docs/30-ux-spec.md` - every screen, flow, state and accessibility rule this document supplies
  values for.
- `docs/33-platform-chrome.md` - how every chrome token resolves per platform, which native control
  carries a role, and the runtime contrast assertion that `R-32-586` defers to.
