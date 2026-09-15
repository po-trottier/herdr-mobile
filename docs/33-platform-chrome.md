# 33 - Platform chrome

This document owns the two native chrome systems of `Herdr Remote`: the flat Cupertino appearance
on iOS and Material You on Android. It owns how a chrome token **resolves** on each platform, which
**native control** carries each role, the **platform floors**, and the **proof method** for a colour
that no longer has a fixed value.

It owns no value. `docs/32-design-language.md` owns every value, per `R-32-001`. A token name is the
same on both platforms, so a mockup that names a token needs no change here.

The app ships one appearance per platform. This document holds no second appearance for an older
operating system. On Android the chrome takes wallpaper colour, which every supported device has.
On iOS the chrome takes the plain `cupertino_ui` appearance, which is the same on every supported
version. On a current iOS device that appearance is the pre-iOS-26 flat one, on purpose. Section 3
says why, and `R-33-069` says what changes it.

## 1. Purpose and ownership

Open `docs/32-design-language.md` for **what** a colour, a size or a duration is. Open this document
for **what that token becomes on this device**.

- **R-33-001** This document MUST hold the per-platform resolution of a chrome token, the native
  control map, the platform floors and the proof method for a generated or translucent value. It
  MUST NOT define a colour, a size, a duration or an icon name.
- **R-33-002** A token name MUST be identical on both platforms. A widget MUST NOT branch on the
  platform to pick a colour, and a mockup MUST NOT hold a second token reference for a second
  platform. Only the resolution differs.
- **R-33-003** Every fixed value this document needs MUST be named by its token in
  `docs/32-design-language.md`. This document MUST NOT introduce a hex value, per `R-32-100` and
  `R-32-101`.
- **R-33-004** `docs/20-mobile-framework.md` owns the SDK pins and the package pins, in `R-20-026`
  and its package tables. This document names an operating-system floor, which is a platform fact,
  and cites that document for a repository pin.
- **R-33-005** Where this document and `docs/32-design-language.md` disagree, the value belongs to
  `docs/32-design-language.md` and the resolution belongs to this document. A reader MUST NOT find
  the same statement in both.

## 2. The platform split

| Surface | Android | iOS |
| --- | --- | --- |
| Chrome colour | Herdr fixed palette | Herdr fixed palette |
| Bar and sheet material | opaque Material surface | plain `cupertino_ui` surface |
| Terminal grid | Selenized, isolated | Selenized, isolated |

Both platforms now share the same fixed Herdr palette. Android no longer takes a wallpaper
(colour scheme); `dynamic_color` is removed. Material 3 components stay, coloured by one fixed
`ColorScheme` built from the tokens in `docs/32-design-language.md` section 6. iOS keeps the
plain `cupertino_ui` appearance with the same fixed Herdr palette.

- **R-33-006** The table above is normative and has no version dimension. A chrome surface MUST
  resolve to the cell for its platform on every supported device.
- **R-33-007** iOS MUST NOT take a dynamic colour. iOS keeps the Herdr fixed chrome palette. A
  reader who expects symmetry with Android is wrong, and this rule is the answer.
- **R-33-008** Exactly one place in the app MUST build the chrome `ColorScheme`, at the application
  root. A screen, a component or a mockup MUST NOT build a second one.
- **R-33-009** The app MUST NOT offer a choice between the two chrome systems. There is no setting
  that puts Material chrome on iOS or Primer chrome on Android. `R-32-014` owns the wider
  prohibition on an in-app palette choice.
- **R-33-010** Only chrome resolves per platform. Content MUST NOT resolve per platform. Section 7
  owns the terminal grid, which is content.

## 3. iOS flat Cupertino

iOS chrome is the plain appearance that `cupertino_ui` draws, with the fixed Herdr chrome
palette. The app ships **no** Liquid Glass on iOS. That is a decision, not an oversight.

The reasons, once and plainly. Apple's Liquid Glass adoption applies to standard SwiftUI, UIKit and
AppKit components, and Flutter draws its own widgets, so no deployment target gives a Flutter app
the material by itself. Stable Flutter then ships nothing for it: `cupertino_ui` has no glass
widget, no glass parameter on an existing widget, and no engine binding for `UIGlassEffect`. That
left two routes, and the owner rejected both. A native platform view carries the cost of hybrid
composition and, in every package that offers one, a single maintainer. A shader is a
reimplementation rather than the system material, and it must chase a target that Apple has already
moved more than once since the iOS 26 release. So the owner chose to wait for official support, per
`R-33-069`.

- **R-33-012** iOS chrome MUST be the plain `cupertino_ui` appearance with the Herdr fixed chrome
  palette. The app MUST NOT ship Liquid Glass, a platform view that hosts a chrome surface, or a
  dependency whose purpose is a glass material. These are the iOS chrome surfaces and the widget
  that draws each one:
  1. the tab bar that holds the three destinations of `R-30-021`, as `CupertinoTabBar`;
  2. the app bar, including its trailing `+` control, as `CupertinoNavigationBar`;
  3. the persistent connection strip, above the tab bar, per `R-33-036`;
  4. the bottom sheet of `docs/32-design-language.md` section 7.16, per `R-32-545`.

  Each surface keeps every row of its own anatomy table, which is the surface, the radius, the
  elevation, the row height, the type and the ink. Rows 1, 2 and 4 are **translucent** as
  `cupertino_ui` draws them, so `R-33-053` proves their legibility and `R-33-068` owns their opaque
  form.
- **R-33-013** The app MUST NOT approximate Liquid Glass by any means. A `BackdropFilter` blur, a
  shader, a gradient, a translucent overlay, or a stack of them, MUST NOT be called Liquid Glass
  and MUST NOT be shipped as a substitute for it, in a document, a mockup, a widget, a commit
  message or a store listing. A blur samples one rectangle and averages it. The system material
  samples and **refracts**, and it reflects colour from outside its own bounds. So an imitation is a
  different effect that happens to look similar today, and it drifts further from the system
  material with every iOS release. This rule carries more weight now, not less, because the app
  ships no glass on purpose and a fake one would be the easiest thing for a later contributor to
  add. The only acceptable Liquid Glass is the official one, adopted through `R-33-069`. Until then
  the flat appearance is the honest one, and a reviewer MUST reject an imitation.
- **R-33-015** These surfaces MUST be opaque on both platforms: the terminal grid and every chrome
  that overlaps it, per `R-33-060`; the key row; the destructive confirmation dialog of
  `docs/32-design-language.md` section 7.17; a text field; a snackbar; and the lock screen. A
  confirmation and a lock screen ask for a decision, so their background MUST stay still. Where the
  `cupertino_ui` widget for one of these is translucent by default, the app MUST set its opaque
  surface.
- **R-33-017** The iOS deployment target MUST be **15.0**, per `R-20-026`. That is Flutter's own
  minimum supported iOS version, so the floor is the toolchain floor and not a design decision. The
  flat Cupertino appearance needs no higher one, and nothing else in the design needs one either:
  the notification authorisation call, `UIAccessibility.isReduceTransparencyEnabled`,
  `UIAccessibility.isDarkerSystemColorsEnabled`, `openSettingsURLString` and the Secure Enclave
  keys are all iOS 13 or earlier. A higher floor would drop devices and buy nothing.
- **R-33-021** The app MUST NOT ship the `UIDesignRequiresCompatibility` opt-out key. Apple
  documents that key as a temporary measure for one release, so an appearance that depends on it
  breaks when Apple removes it. The app needs no such key: it draws its own flat chrome from
  `cupertino_ui`, per `R-33-012`, and a whole-app opt-out would also freeze the appearance of the
  system surfaces that the app does not draw.
- **R-33-022** Every glyph that the app places in its chrome MUST come from the icon set in
  `R-32-400`. Glyphs that a platform control owns MUST stay native, per `R-20-044`.
  This exception covers the back control, the search field and the expansion tile.
  The app MUST NOT replace a native control to change its glyph.
  Glyphs on an operating-system surface, such as a keyboard or permission dialog, stay outside
  the app map, per `R-32-401`.
- **R-33-068** The **opaque variant** of a translucent chrome surface is the opaque Selenized
  surface that the component's own anatomy already names. It is a user preference, and it is
  neither a fallback nor a version tier. It is reachable in exactly two cases, and each case names
  it: the user asks for it through Reduce Transparency, per `R-33-051`, or through Increase
  Contrast, per `R-33-052`. The app MUST NOT draw a substitute effect in the opaque variant, and
  MUST NOT reach it for any other reason.
- **R-33-069** When `cupertino_ui` ships official Liquid Glass support, the app MUST adopt it on
  exactly the surfaces that `R-33-012` lists, through that library, and MUST NOT adopt it through a
  platform view or a shader. The adoption MUST keep `R-33-055`, so the material MUST NOT reach the
  terminal grid, and MUST keep `R-33-015`, so the opaque surfaces stay opaque. At that point the
  platform split of section 2, the floor of `R-33-017` and the proof method of `R-33-053` MUST all
  be revisited in one change, because official support may need a floor above 15.0. This document
  states **no date**, because Flutter has committed to none. Flutter issue 170310 is the tracking
  reference.

## 4. Android Material 3 with the fixed Herdr palette

Android chrome uses Material 3 components coloured by one fixed `ColorScheme` built from the Herdr
brand tokens in `docs/32-design-language.md` section 6. The `dynamic_color` package is removed;
there is no wallpaper-derived scheme. The pipeline is:

1. `ChromeScheme.fixed(Brightness)` builds one `ColorScheme` per theme from `AppColor` tokens
   (table in `docs/32-design-language.md` section 6).
2. `ThemeData` applies that scheme on both platforms; `app.dart` uses `_FixedChromeApp` on both.
3. Material 3 components read roles from the fixed scheme. No runtime generation, no degenerate
   fallback, no contrast escalation.

- **R-33-023** The app MUST read a Material 3 role from the fixed `ColorScheme` and MUST NOT read
  the wallpaper, an extracted source colour, or a tone directly. The fixed scheme is the only path
  from the brand tokens to a pixel.
- **R-33-024** The chrome scheme MUST be `ChromeScheme.fixed(Brightness)` on every supported device.
  The app MUST NOT test the API level before asking for the scheme, and MUST NOT hold a second
  designed palette. `DynamicColorBuilder`, `DynamicColorPlugin`, the degenerate scheme,
  `proveAndroidChromeScheme`, and `ChromeSchemeSource.wallpaper`/`degenerate` are deleted.
- **R-33-025** The `dynamic_color` package is removed from `pubspec.yaml`. The Flutter SDK cannot
  read the wallpaper, and the app no longer uses wallpaper colour.
- **R-33-027** Material 3 MUST stay enabled. `ThemeData.useMaterial3` is true by default and the app
  MUST NOT set it false. A Material 2 theme has no role for the fixed scheme to fill.
- **R-33-028** The app MUST use only the navigation and action components the Flutter SDK ships:
  `NavigationBar`, `NavigationDestination`, `BottomAppBar` and `FloatingActionButton`. The
  Material 3 Expressive docked toolbar, floating toolbar and FAB menu are open Flutter proposals,
  not implementations. A document MUST NOT specify one as available.
- **R-33-029** A floating control MUST NOT sit under the system navigation bar. Android 15 enforces
  edge-to-edge at `targetSdk` 35, and Android 16 removes the
  `R.attr#windowOptOutEdgeToEdgeEnforcement` opt-out at `targetSdk` 36. `R-20-026` pins
  `targetSdk 36`, so the app cannot opt out. Every floating control, which is the create control
  of `R-33-034`, the connection strip and any snackbar (amended 2026-09-09, per `R-03-109`, when
  the `FloatingActionButton` left the app; restored 2026-09-10, per the corrected `R-03-109`),
  MUST take its bottom offset from the bottom system-bar inset and MUST add the spacing its
  anatomy names on top of that inset.
- **R-33-030** A theme change at run time MUST follow the order of `R-32-015`: apply the new
  chrome, then leave the terminal untouched. A theme change MUST NOT trigger a `pane.read`,
  because the terminal palette did not change.
- **R-33-032** The app MUST use the one fixed `ColorScheme` from `ChromeScheme.fixed`. It MUST NOT
  mix roles from multiple schemes, and it MUST NOT hand-patch one role.

### Role-to-token table (from `docs/32-design-language.md` section 6)

| Material role | Token |
| --- | --- |
| `surface`, `surfaceContainerLowest` | `bg.base` |
| `surfaceContainerLow`, `surfaceContainer` | `bg.raised` |
| `surfaceContainerHigh`, `surfaceContainerHighest` | `bg.high` |
| `onSurface` | `fg.primary` |
| `onSurfaceVariant` | `fg.secondary` |
| `primary`, `secondary`, `tertiary` | `accent.primary` |
| `onPrimary`, `onSecondary`, `onTertiary` | `fg.on_accent` |
| `primaryContainer`, `secondaryContainer`, `tertiaryContainer` | `bg.high` |
| `onPrimaryContainer`, `onSecondaryContainer`, `onTertiaryContainer` | `fg.primary` |
| `outline` | `border.strong` |
| `outlineVariant` | `border.subtle` |
| `error` | `status.error` |
| `onError` | `fg.on_accent` |
| `errorContainer` | `bg.high` |
| `onErrorContainer` | `status.error` |
| `shadow`, `scrim` | `shadow` |
| `inverseSurface` | `fg.primary` |
| `onInverseSurface` | `bg.base` |
| `surfaceTint` | `Colors.transparent` (no tint overlay anywhere) |

## 5. Native controls

"Native controls" means the control a person already knows on that platform. Taken seriously, this
made the **create** control differ in kind until 2026-09-09, because a floating action button was a
Material idiom with no iOS equivalent; `R-03-109` first put the control in the app bar on both
platforms, then on 2026-09-10 kept the floating button on both, and `R-33-034` records why.

The other rows differ too, and each one is a divergence that a screen once stated inline. A screen
has no platform column, so a screen that states one shared control states the wrong control on one
of the two platforms. This section owns every row, so a screen cites a rule and names no widget
and no glyph.

| Concern | Android | iOS |
| --- | --- | --- |
| Three destinations | `NavigationBar` with `NavigationDestination` | `CupertinoTabBar` |
| Create | `FloatingActionButton` in the `Scaffold` slot, above the connection strip and the `NavigationBar`, per `R-33-034` (moved into the app bar 2026-09-09 and restored 2026-09-10, per the corrected `R-03-109`) | the same `FloatingActionButton`, floated over the body above the connection strip and the `CupertinoTabBar`, per `R-33-034` (the same dates and reason) |
| Connection strip | a strip above the navigation bar | a strip above the tab bar |
| Menu surface | bottom sheet | bottom sheet |
| Bottom offset | from the system-bar inset | from the safe area |
| Back | `AppBar` leading, drawn by `BackButton`, plus predictive back | `CupertinoNavigationBar` leading, plus the interactive pop gesture |
| Primary navigation on a pushed route | the parent layout and the primary destinations only | the tab bar stays visible |
| A row that opens the next level | `ListTile` | `CupertinoListTile` with trailing `chevron_right` from the app icon set, per `R-32-401` |
| Settings list | the Material settings list | `CupertinoListSection` with `CupertinoListTile` |
| Confirmation | `AlertDialog`, roles placed by the component | `CupertinoAlertDialog`, `Cancel` leading |
| Terminal state that ends the work: `pane gone`, `read failed`, `protocol mismatch` | `AlertDialog`, not barrier-dismissible, the back gesture refused, the title, the body and one or two actions named by role and placed by the component, the default action trailing (added 2026-09-10, per `R-03-119`; `docs/31-mockups/08-terminal.md` `R-31-08-27` owns the states) | `CupertinoAlertDialog` with `CupertinoDialogAction` actions, the default action marked `isDefaultAction`, no barrier dismissal (added 2026-09-10, per `R-03-119`) |
| A compose task | a full-screen route with a close control | a full-height `CupertinoSheetRoute` with `Cancel` |
| Search a list | a search action (`IconButton`, the `Search` glyph of `R-32-401`) in the top app bar that opens the Material 3 search view, `SearchAnchor`; the view's fill, edge and type come from `searchViewTheme` (amended 2026-09-09, per `R-03-102`: a `SearchBar` pill in the body is not the native pattern) | `CupertinoSearchTextField` in the navigation bar area: the bar's bottom slot, or directly under the bar at the platform's own inset where the screen draws its own bar (amended 2026-09-09, per `R-03-102`) |
| App bar action, an icon control | `IconButton` with its tooltip | `CupertinoButton`, at least 48 wide, filling the bar, per `R-33-076` |
| Input bar field | Filled `TextField`, per `R-03-132` | `CupertinoTextField` with rounded `BoxDecoration`, per `R-03-132` |
| Send control | Round `IconButton.filled` outside the field, 48 dp | `CupertinoButton` inside the field suffix, 30 pt circle with 3 pt inset |
| Primary button | `FilledButton` | `CupertinoButton.filled` |
| Text button, with or without a glyph | `TextButton`, `TextButton.icon` with a glyph | `CupertinoButton`, the glyph and the label in one row |
| Ghost/outlined button | `OutlinedButton` | `CupertinoButton.tinted`; iOS has no outlined idiom, and the tinted button is its bordered secondary button |
| Icon button in a row or a strip | `IconButton` in the component's own circle, its glyph of `R-32-401` at `size.icon.md` in `color.fg.primary` from `iconButtonTheme`; no `size.target.min` square and no `radius.sm` (amended 2026-09-09, per the `R-03-059` addendum) | `CupertinoButton` with the same glyph as its child, at the component's own size; only the `App bar action` row widens it, per `R-33-076` (amended 2026-09-09, per the `R-03-059` addendum) |
| Segmented choice | `SegmentedButton`, filling its row, its colours and type from `segmentedButtonTheme`, in the component's own stadium and height (amended 2026-09-09, per the `R-03-059` addendum) | `CupertinoSlidingSegmentedControl` |
| Switch between sibling views | `TabBar` of primary tabs, full width under the app bar, its indicator, ink, type and divider from `tabBarTheme`; not a `SegmentedButton`, which is a choice, not a view switch (added 2026-09-09, per `R-03-102`) | `CupertinoSlidingSegmentedControl`, in the navigation bar area (added 2026-09-09, per `R-03-102`) |
| Discrete value from a short fixed list, the terminal text size | `Slider` with `divisions` set to one less than the count of permitted values, its colours the component's own, no value label bubble; the title row above it carries the current value at its trailing edge (added 2026-09-09, per `R-03-110`; it replaces the `Stepper` row, whose two `IconButton.filledTonal` controls are gone) | `CupertinoSlider` with the same `divisions`, the same title row and value (added 2026-09-09, per `R-03-110`) |
| Choice among destructive actions from an app bar action, the Phones removes | `MenuAnchor` opened by the `IconButton` app bar action, one `MenuItemButton` per choice with the `treat.destructive` glyph; each choice then opens the confirmation of `R-33-074` (added 2026-09-09, per `R-03-111`) | `CupertinoActionSheet` with one `isDestructiveAction` action per choice and a `Cancel` action; each choice then opens the confirmation of `R-33-074` (added 2026-09-09, per `R-03-111`) |
| Key cap, in the terminal key row | `OutlinedButton`, or `FilledButton` while a modifier is latched, in the component's own pill; colours from `outlinedButtonTheme` and `filledButtonTheme`, the label type and a layout floor (`size.keycap` high, the column module wide, `space.2` of padding) from the key row's own button theme, per `docs/32-design-language.md` section 7.12 (added 2026-09-09, per `R-03-059`; the latched form became `FilledButton` on 2026-09-10, per `R-03-118`: it was `FilledButton.tonal`, which is not the platform's high-emphasis form, and its label went upper case for state) | `CupertinoButton.tinted`, or `CupertinoButton.filled` while latched, in the component's own corner; the row hands it the same floor and the label ink `color.accent.text`, per section 7.12 (added 2026-09-09, per `R-03-059`) |
| Row control, the bank toggle of the terminal key row | `TextButton`, no outline and no fill, the glyph in `color.accent.text`; the same layout floor as the key cap from the key row's own `TextButtonTheme` (added 2026-09-10 by the product owner: the `…` and `×` caps were not discernible from the keys, and a control is not a key; a key has a border, the control has none) | a plain `CupertinoButton`, no fill, `foregroundColor` `color.accent.text`, the same minimum size and padding the row hands its keys (added 2026-09-10, same reason) |
| Page surface, including Welcome and Lock | `Scaffold` | `CupertinoPageScaffold`; Lock stays opaque, per `R-33-015` |
| Pushed route | `MaterialPage` | `CupertinoPage`; the biometric lock uses a full-screen dialog route without an edge-swipe dismissal |
| Content row | `ListTile`, including its selected state | `CupertinoListTile`, including its native selection surface |
| Activity indicator | `CircularProgressIndicator` | `CupertinoActivityIndicator`; both use the caller's size token through `ChromeActivityIndicator` |
| Switch | `Switch`, with colours from `switchTheme` | `CupertinoSwitch`, with the section 7.7 tokens, through `ChromeSwitch` |
| Snackbar | `SnackBar`, with the section 7.22 tokens from `snackBarTheme` | The opaque section 7.22 surface in the root `Overlay`; Cupertino has no snackbar control. `ChromeTransientTimeout` prevents a timeout with a screen reader on both platforms, per `R-30-743` |
| Sheet row | `ListTile`, through `ChromeListRow.sheet` | `CupertinoListTile`, through `ChromeListRow.sheet`; only a navigation row carries a chevron |
| Suggestion chip | `ActionChip`, with native geometry | Small `CupertinoButton.tinted`, through `ChromeSuggestionChip` |
| Host picker | `FilledButton.tonal` | `CupertinoButton.tinted` |
| Jump-to-bottom pill | `FilledButton.tonalIcon` | `CupertinoButton.tinted`; both stay opaque, per `R-33-060` |
| Strip action | `ListTile` | `CupertinoListTile`; `ChromeStripAction` owns the destination tap |
| Section header disclosure | `ListTile` with `IconButton` | `CupertinoListTile` with `CupertinoButton`; the count keeps its trailing inset |
| Workspace inline expansion | `ExpansionTile`, with its own disclosure glyph and rotation | `CupertinoExpansionTile`, through `ChromeListRow.expand`, with its own disclosure glyph; `R-20-044` bundles this native font. `R-32-401` governs glyphs the app places, not glyphs a native control owns |
| Notification swipe action | `TextButton` or `FilledButton.tonal` | Plain `CupertinoButton`; the existing swipe reveal stays |
| In-sheet back control | `BackButton` with an explicit return callback | `CupertinoNavigationBarBackButton` with an explicit return callback |

- **R-33-033** The table above is normative. A screen MUST use the control in its platform column,
  and MUST NOT substitute the other platform's control. The `Search a list` row was added on
  2026-09-08 by decision of the product owner, for the inline pane search of
  `docs/31-mockups/06-agent-list.md` `R-31-06-30`; the app sets only the placeholder and the inset
  on that control, per `R-32-598`. The row was amended and the `Switch between sibling views` row
  added on 2026-09-09 by decision of the product owner, per `R-03-102`: search is the platform's
  own search pattern, an app bar action that opens the Material search view on Android and a
  `CupertinoSearchTextField` in the navigation bar area on iOS, never a loose pill in a list body;
  a switch between sibling views is a `TabBar` of primary tabs on Android and a
  `CupertinoSlidingSegmentedControl` on iOS. The `Segmented choice` row stays for a choice of
  values, such as the theme setting. The `App bar action` row was added on 2026-09-08 by decision of
  the product owner: three screens had built the same control three ways, one of them as a bare
  gesture box, which `R-33-076` forbids. One widget draws it for both platforms,
  `app/lib/widgets/theme/chrome_icon_action.dart`, and a screen MUST compose that widget rather than
  restate the row. The six button rows, `Primary button` to `Segmented choice` plus the `Stepper`
  row that the slider row replaced on 2026-09-09 per `R-03-110`, were added on 2026-09-09 by
  decision of the product owner, per `R-03-059`: every button is the platform's own widget, the app
  draws none of its own from a box, a border and a gesture, and a token reaches a button through
  the theme of `app/lib/app.dart` only (`filledButtonTheme`, `textButtonTheme`,
  `outlinedButtonTheme`, `iconButtonTheme`, `segmentedButtonTheme`, and the Cupertino
  `primaryColor`, `primaryContrastingColor` and `textTheme.actionTextStyle`). One widget draws each
  of the first three for both platforms, `app/lib/widgets/app_filled_button.dart`,
  `app/lib/widgets/app_text_button.dart` and `app/lib/widgets/app_ghost_button.dart`, and a screen
  MUST compose those widgets and MUST NOT set a style on them. The `R-03-059` addendum of
  2026-09-09 narrows what that theme sets: colours and type only (`textStyle`, `foregroundColor`,
  `backgroundColor`, `overlayColor`, `side`, the disabled dim, a glyph's `iconSize`), never
  `shape`, `minimumSize`, `fixedSize` or `padding`, so a Material button keeps its own pill, an
  icon button its own circle and a segmented control its own stadium. `cupertino_ui` 1.0.1 has no
  theme slot for a button's size or corner either, so an iOS button keeps the component's own,
  which `docs/32-design-language.md` sections 7.8 and 7.28 record. The `Key cap` row was added on
  2026-09-09 by decision of the product owner, per `R-03-059`: a key cap is a button and the key
  row has no exemption. `app/lib/widgets/key_row.dart` alone draws it for both platforms. The key
  row's own button theme sets a `minimumSize` and a `padding` on the platform's own shape, and
  nothing else: a layout floor, not a reshaping. The addendum forbids "a square, a fixed box or any
  geometry the platform does not draw", and a minimum on the platform's own pill is none of those;
  without the floor the arrows scroll off a portrait phone, which `R-31-09-16` forbids.
  The latched form of that row became the platform's high-emphasis button on 2026-09-10, per
  `R-03-118`, so `app/lib/widgets/key_row.dart` is the second file that builds a `FilledButton`
  and `R-32-525` names both. `docs/32-design-language.md` section 7.12 records the values and
  `R-31-09-25` of `docs/31-mockups/09-key-row.md` records the requirement.
- **R-33-034** The create control MUST be Material's `FloatingActionButton` on both platforms,
  drawn by the `Agents` screen alone: `space.4` from the trailing edge and from the bottom of the
  body, above the connection strip and the navigation bar or tab bar, with the `add` glyph and
  the spoken label `New`; `docs/32-design-language.md` `R-32-588` owns its values. On Android it
  is the `Scaffold`'s own slot; on iOS the `CupertinoPageScaffold` has no slot, so the screen
  floats the same widget over its body at the same offset, plus the bottom safe area when the
  screen stands alone. The app MUST NOT draw a create action in the app bar on either platform,
  and a list MUST NOT reserve a fixed band at its end for the button: a list that fits the screen
  ends at its last row, and a list that overflows scrolls its last row clear of the button through
  the scroll view's own end padding only, per `R-03-109`. (Corrected 2026-09-10 by the product
  owner, per `R-03-109`: on 2026-09-09 this rule moved the control into the app bar on both
  platforms after the owner saw the empty band under every list; the owner then wanted the
  floating button kept on both platforms and only the band removed. The band was the ground grid
  of the retired `R-32-334` showing through the list's end padding, not the button. A floating
  primary action is no longer foreign to iOS: the platform's own design, Liquid Glass, floats it
  too, so one Material widget on both platforms is a shared control, not a divergence in kind.)
  `R-33-029` governs the button's bottom offset on Android again.
- **R-33-035** Both platforms MUST hold exactly the three destinations of `R-30-021`, `Agents`,
  `Notifications` and `Settings`, in the same order, with the same labels and the same icons.
  `Notifications` replaced `Panes` on 2026-09-04, by decision of the product owner. Apple's guidance
  is three to five tabs on iPhone, so three complies. `R-32-562` owns the anatomy of the Android bar.
- **R-33-036** The persistent connection strip MUST sit above the `NavigationBar` on Android and
  above the `CupertinoTabBar` on iOS. The app MUST NOT use the iOS 26 `tabViewBottomAccessory`,
  which `cupertino_ui` does not expose and which `R-33-012` puts out of scope. Flutter draws the
  strip on both platforms, and the strip content is identical on both. The strip MUST carry the
  link's state bar of `R-03-100` and MUST make a failure read at a glance: the `Strip` row of
  `docs/32-design-language.md` section 7.22 holds the values (amended 2026-09-10 by the product
  owner, who found `Not connected to <name>.` looked no different from connected).
- **R-33-037** The create control MUST open the bottom sheet of `docs/32-design-language.md`
  section 7.16 on **both** platforms, per `R-32-545`. It MUST NOT open a popover, a modal dialog, a
  floating menu or an iOS pull-down menu. Four reasons, so that no document argues them again.

  1. `R-30-005` permits a sheet, a strip or an inline control, and it excludes a dialog for a
     non-destructive choice.
  2. The Material 3 Expressive FAB menu is not available, per `R-33-028`.
  3. A popover anchored to a `+` in the app bar would put the menu at the top of the screen, away
     from the thumb, while a sheet is reachable on both platforms.
  4. A pull-down menu **closes** when a person chooses an item. Apple documents that behaviour as
     the definition of the control. `R-31-17-07` requires the opposite: the create menu stays open
     until the acknowledgement returns, because the new id arrives in that acknowledgement, per
     `R-30-956`. So the menu must hold three states that a pull-down menu cannot hold: a spinner in
     the tapped row, an error strip with a `Try again`, and the remaining rows disabled.

  The fourth reason is a **refusal** of a review finding, recorded here so that it is not reopened
  as an oversight. The finding asked for an iOS `Add` pull-down menu, and Apple does name an `Add`
  button as a pull-down example. The widget also exists: `cupertino_ui` ships `CupertinoMenuAnchor`
  and `CupertinoMenuItem`. The pattern still fails, because this menu waits for a network round
  trip and a pull-down menu does not wait. Apple's own length guidance points the same way: it
  asks for at least three items, and since 2026-09-14 the menu holds two, `New space` and
  `New tab` (`R-03-134` moved the split rows to the pane action sheet; until then this paragraph
  argued from the retired no-pane row of `R-31-17-05`). This rule MUST be revisited only if
  `UxSpec` retires `R-31-17-07` and moves the pending state off the menu surface. Until then the
  sheet is correct on both platforms.
- **R-33-038** The app MUST use the widget that the platform's own design library ships, which is
  `cupertino_ui` on iOS and the Material library that `docs/20-mobile-framework.md` pins on
  Android. It MUST NOT re-implement that widget in Dart, and it MUST NOT host a native control in a
  platform view. The two surfaces that once had no shipped widget, the iOS tab bar and the bottom
  accessory, are both settled by `R-33-012`: `CupertinoTabBar` draws the tab bar, and the accessory
  is out of scope, per `R-33-036`.
- **R-33-039** Every floating control MUST meet the touch target of `R-30-290` and the value of
  `R-32-360`, and MUST take its bottom offset from `R-33-029` on Android and from the safe area on
  iOS. A control MUST NOT rely on a fixed pixel offset from the bottom edge of the screen.
- **R-33-040** The information architecture MUST be identical on both platforms: the same routes,
  the same three destinations and the same order. Only the control shape differs.
- **R-33-070** **Back.** Each platform's navigation component MUST own the back glyph, the back
  label and the back gesture. The app MUST NOT place a back glyph itself, and the normative icon map
  `R-32-401` MUST NOT hold a `Back` row. The native-control exception in `R-33-022` applies.
  A screen MUST cite this rule and MUST NOT name a glyph.
  1. On Android the `AppBar` leading slot MUST hold the Material `BackButton`. `AppBar` supplies it
     by itself when the route is not the first route of its `Navigator`. `BackButtonIcon` resolves
     the glyph from `Theme.of(context).platform`, which gives `Icons.arrow_back` on Android, and it
     supplies the Android semantics label from `MaterialLocalizations.backButtonTooltip`.
  2. On iOS the `CupertinoNavigationBar` leading slot MUST stay empty, so that
     `automaticallyImplyLeading` draws the standard back control. That control carries the previous
     route's title, which comes from `previousPageTitle` or from `CupertinoPageRoute.previousTitle`.
     A screen MUST supply the route `title`, so that the previous title is correct.
  3. The route MUST keep its platform pop gesture. On iOS `CupertinoPageRoute` gives the interactive
     swipe from the leading edge. On Android the route MUST take the predictive-back transition, and
     the app MUST NOT disable it. One honest limitation: Flutter's
     `PredictiveBackPageTransitionsBuilder` needs Android 14, API 34, and it falls back to
     `FadeForwardsPageTransitionsBuilder` on the API 33 floor of `R-33-017`. The floor device still
     goes back; it gets no preview.
  4. One reason for this rule is **not** mirroring, and a document MUST NOT state that it is. Both
     `Icons.arrow_back` and `Icons.arrow_back_ios_new` carry `matchTextDirection: true`, so the
     app-drawn glyph did mirror for a right-to-left language. The real defects were three: the iOS
     chevron appeared on Android, the Android semantics label was absent, and the iOS previous-route
     title and pop gesture were absent. A review finding named mirroring, and this row corrects it.
- **R-33-071** **Primary navigation on a pushed route.** The two platforms diverge here, and the app
  MUST NOT force them to match. `UxSpec` owns which route is a detail route and which is a modal.
  This rule owns what each control does once that choice is made.
  1. On iOS the `CupertinoTabBar` MUST stay visible when a detail route is pushed. The app MUST push
     that route inside the tab's own `Navigator`, which `CupertinoTabView` provides, and MUST NOT
     push it on the root navigator. Apple's reason is orientation: a person who loses the tab bar
     forgets which section they are in.
  2. On iOS the tab bar MUST be covered only by a modal. Apple names that single exception, because
     a modal is temporary and self-contained. The app MUST reach it through `CupertinoSheetRoute` or
     a `fullscreenDialog` route pushed on the root navigator, and MUST NOT hide the tab bar by any
     other means.
  3. On Android the `NavigationBar` is the primary navigation of the parent layout and of the
     primary destinations. A pushed child route MAY omit it. A child route that omits it MUST carry
     the top-app-bar back control of `R-33-070` and the predictive-back path, and it MUST NOT leave
     the person with no way out. Android's guidance sends a child view to a secondary navigation
     pattern, so an omitted bar on Android is not the defect that an omitted tab bar is on iOS.
  4. The terminal keeps its stated full-screen reason, per `R-30-022`, and this rule does not reach
     it.
- **R-33-072** **A row that promises the next level.** One row MUST have one outcome on both
  platforms. A single indicator MUST NOT stand for a push, an inline expansion and a sheet. This
  rule reaches every list row, including a bottom-sheet action row. The row MUST use
  `ListTile`, `CupertinoListTile` or the platform's own expansion control.
  1. On iOS a trailing chevron promises the **next level in the hierarchy**, and nothing else. Apple
     states that a disclosure indicator reveals the next level and does not show details about the
     item. So a row that opens a modal sheet MUST NOT carry a chevron, and a row that expands inline
     MUST NOT carry one either.
  2. A row that opens the next level MUST use `CupertinoListTile` with trailing `chevron_right`
     from the app icon set and the trailing-chevron values of `docs/32-design-language.md`
     section 7.4. It MUST push that level. This app-supplied indicator MUST NOT use
     `CupertinoListTileChevron`, per `R-32-401`. A row that opens a sheet MUST replace the
     chevron with a labelled control, such as `Edit` or a current value.
     A row that expands inline MUST use `CupertinoExpansionTile`. Its native arrow states that
     content opens in place, per `R-33-022`.
  3. On Android a trailing chevron carries no such promise, so the Material row MUST carry the
     current value or a labelled control instead. A Material choice MUST open a single-choice screen
     or a dialog, per `R-33-073`.
  4. This rule settles two screens. A phone row in `docs/31-mockups/14-devices.md` either pushes a
     detail route and keeps its chevron, or keeps its sheet and drops it. The relay-address row and
     the phone-name row in `docs/31-mockups/15-appearance.md` open sheets, so both drop the chevron.
     `UxSpec` picks push or sheet; this rule fixes the affordance that follows the choice.
  5. A **bottom-sheet action row** in `docs/32-design-language.md` section 7.16 MUST use
     `ListTile` on Android and `CupertinoListTile` on iOS, through `ChromeListRow.sheet`.
     The helper MUST own selection, disabled and busy states, and destructive glyph semantics.
     A row that opens a further navigation level MAY carry the iOS chevron from the app icon set.
     An immediate action MUST NOT carry a chevron. A row that expands inline MUST use the
     platform's expansion control. The bottom sheet itself stays shared, per `R-33-037`.
- **R-33-073** **The settings list.** The composition of a settings list MUST come from the
  platform's own list widgets, so that an iOS settings screen does not render as a flat Android
  list. On iOS a settings screen MUST use `CupertinoListSection` for each group and
  `CupertinoListTile` for each row. On Android a settings screen MUST use the Material settings
  list, and a single choice MUST open a native single-choice screen or dialog. This rule owns the
  **composing widget** only. `docs/32-design-language.md` keeps every row value, which is the row
  height, the type, the ink and the inset, and `R-33-003` forbids a value here.
  1. The group header and the separators start on the row text's edge on both platforms (added
     2026-09-08 by the product owner's design pass). The header is the upper-case tier of
     `R-32-563` above the group, not the section's own header slot, and on iOS it is inset by the
     card margin so it lands on the row text; the `CupertinoListSection` separators take the
     row's own `space.4` inset and no leading allowance. The section's defaults put the header at
     20 and the separators at 72 while the row text sat at 32: three left edges in one card.
  2. An inline control block is not a row, and this rule does not reach it (added 2026-09-08 by
     the product owner's design pass). `Theme` and `Terminal text size` in
     `docs/31-mockups/15-appearance.md` put their control under their label, inside the group,
     so they compose the same platform-neutral block on both platforms and never take a
     `CupertinoListTile`. Every other row of a settings screen MUST be one platform row: on iOS
     one `CupertinoListTile`, which keeps the platform's own tile height and inset, and on
     Android one list row of `docs/32-design-language.md` section 7.4. The same pass found the
     iOS screen composing a `CupertinoListSection` from Android rows, so only the outer section
     native. `app/lib/widgets/theme/chrome_list_row.dart` holds one row that composes
     per platform: push, choice, expand, toggle, action, destructive, static and sheet.
- **R-33-074** **A confirmation dialog.** A shared specification MUST name **roles** and MUST NOT
  name a position, an action order or an initial focus target. The two platforms order a safe action
  and a destructive action differently, so one fixed order is wrong on one of them.
  1. A screen MUST fix only these: the title, the body, the destructive verb, which action is
     destructive, and which action cancels. Everything else belongs to the platform component.
  2. On iOS the dialog MUST be a `CupertinoAlertDialog` with `CupertinoDialogAction` actions. The
     cancelling action MUST be titled **`Cancel`**. Apple states that rule without exception, so
     `Keep`, `Not now` and every other cancellation title is wrong on iOS. The destructive action
     MUST set `isDestructiveAction`. Apple places the default action at the trailing side of a row
     or at the top of a stack, and it places `Cancel` at the leading side or at the bottom.
  3. On iOS `Cancel` MUST NOT be the default action. Apple warns that a default `Cancel` teaches a
     person to dismiss an alert without reading it. Where a destructive action is present, Apple
     recommends that **no** action be the default one, so the app MUST NOT mark either action as
     preferred in that dialog.
  4. On Android the dialog MUST be the Material `AlertDialog`. The app MUST pass the destructive
     action as `confirmButton` and the safe action as `dismissButton`, and MUST let the component
     place them. The app MUST NOT hardcode a row order, a button position or a focus order.
  5. A destructive action MUST still reach a confirmation, per `R-30-005` and the owning screen
     rule. This rule changes the actions, not the decision to ask.
  6. Each role carries its own composition from `docs/32-design-language.md` section 7.17 on both
     platforms: the destructive verb is `treat.destructive` and the safe action is
     `type.body.strong` in `color.fg.primary`. The platform component keeps its own order, its
     own role flag (`isDestructiveAction` on iOS) and its own press feedback; the composition is
     the child of the action, never a replacement for it (added 2026-09-08 by the product owner's
     design pass: the Material branch drew two plain text buttons).
- **R-33-075** **A compose task.** A compose surface and its close control are platform controls,
  not one shared route with one shared glyph.
  1. On iOS a compose task MUST be a full-height sheet, pushed as `CupertinoSheetRoute` or through
     `showCupertinoSheet`. It MUST carry two **titled** buttons: a cancelling button, which Apple
     titles `Cancel` or `Close`, and a confirming button, which carries the screen's own verb. The
     surface MUST NOT carry an `x` glyph, because Apple names each of these buttons in words. This
     rule MUST NOT fix which side each button sits on: Apple states that the placement of these
     buttons varies between platforms, so the platform component places them.
  2. On iOS the sheet MUST stay dismissible by the downward drag. Where the sheet holds a
     scrollable, the app MUST pass the `ScrollController` from `scrollableBuilder` to that
     scrollable. Without it the sheet still scrolls and the drag to dismiss stops working.
  3. On Android a compose task MUST be a full-screen route with the Material close control and the
     predictive-back path of `R-33-070`.
  4. A draft MUST NOT be lost by a dismissal that the person did not intend. The owning screen rule
     keeps the draft; this rule only fixes the surface and its actions.
- **R-33-076** **A control inside the iOS navigation bar.** `CupertinoNavigationBar` draws at the
  iOS value of `size.appbar`, 44 points, the platform's own default control height, and the app
  MUST NOT raise it: a taller bar is not the plain Cupertino appearance of `R-33-012`. So a control
  placed in that bar MUST be at least 48 wide (`R-30-290`, `R-32-360`) and MUST fill the bar's
  full height. A control there MUST stay a `CupertinoButton` or another focusable platform
  control, so keyboard focus and activation hold (`R-30-718`); a bare gesture box is not a
  substitute. The 4 points the bar takes from the vertical target is the one measured exception to
  `R-30-290` and `R-32-360`, recorded 2026-09-08: the terminal's `Shortcuts` and `Pane actions`
  controls both measure 48 by 44 in that bar.

## 6. Accessibility once the palette is fixed

Both platforms now share the same fixed Herdr palette. The measured table in `R-32-150` proves every
chrome pair. The terminal palette is proved by `R-32-140`. The semantic state hues are proved by
`R-32-150`. No generated scheme, no wallpaper-derived colour, no translucent material applies to
chrome on either platform.

- **R-33-041** The table above is normative. Every colour pair in the app MUST fall in exactly one
  row, and MUST be proved by that row's method. A pair proved by the wrong method is unproved.
- **R-33-042** A fixed pair MUST stay in the measured table of `R-32-150`. That table MUST NOT be
  deleted or weakened by this change. The whole terminal palette and the whole chrome palette
  are fixed, so most of the app keeps the strongest of the three methods.

### Proof methods

| Kind of value | Example | Proof method |
| --- | --- | --- |
| Fixed chrome | every Herdr chrome token | the measured table of `R-32-150` |
| Fixed terminal | the terminal palette | the measured table of `R-32-140` |
| Fixed semantic | `color.status.*` | the measured table of `R-32-150` |

- **R-33-043** The tonal guarantee is **not** a proof. Material's tonal system keeps a role and its
  `on` role legible by construction, because a tone distance of 50 or more targets 4.5 to 1 and a
  distance of 40 or more targets 3.0 to 1. That guarantee is expressed in HCT tone, and HCT tone is
  not the WCAG sRGB relative-luminance formula. It approximates it closely, and it does not equal
  it. So a document MUST NOT cite the tone distance as evidence that a generated pair passes.
- **R-33-044** The fixed scheme's contrast is proved by the measured table in
  `docs/32-design-language.md` `R-32-150`. No runtime assertion is needed.
- **R-33-045** The diagnostics screen MUST show that the fixed Herdr palette is in use on both
  platforms. The result MUST be observable, not silent.
- **R-33-055** The terminal grid MUST use the Selenized terminal palette of
  `docs/32-design-language.md` section 3.5 on both platforms, always. The chrome palette MUST NOT
  reach it, and no translucent material MUST be drawn over it or behind it. Where this rule meets
  any other rule in this document, this rule wins.
- **R-33-056** **Leak path 1, the theme.** The grid widget MUST NOT read
  `Theme.of(context).colorScheme`, `ColorScheme.of(context)`, `CupertinoTheme.of(context)`, an
  ambient `DefaultTextStyle`, or an ambient `IconTheme`. It MUST take its palette as an explicit
  argument that resolves to the terminal tokens of `R-32-140`. Check: the grid file imports no
  theme lookup, and a search for `colorScheme` in it returns nothing.
- **R-33-057** **Leak path 2, a sampling surface.** A bar, a sheet, a strip or a scrim MUST NOT
  sample grid pixels. A `BackdropFilter` MUST NOT have the grid in its subtree, and a translucent
  chrome surface MUST NOT be composited above it. Check: the grid has no `BackdropFilter` ancestor,
  and no translucent surface shares a rectangle with the grid.
- **R-33-058** **Leak path 3, a tint or an overlay.** A Material elevation tint MUST NOT paint over
  the grid. The grid MUST NOT sit inside a `Material` whose `surfaceTintColor` is a generated role,
  and a `SystemUiOverlayStyle` MUST NOT tint the grid area. Check: `surfaceTintColor` is
  `Colors.transparent` on every ancestor of the grid.
- **R-33-060** Chrome that overlaps the grid rectangle MUST take the fixed Herdr chrome values
  on both platforms and MUST be opaque. This covers the offline strip, the terminal status strip,
  the jump pill and the key row. So these surfaces keep a fixed value on both members of every pair,
  and they stay inside the measured table of `R-32-150` instead of falling to `R-33-044`.
- **R-33-061** The isolation MUST be verified, not assumed. A golden test MUST render the terminal
  route under both themes on both platforms, and the grid pixels MUST be identical in every run.
  A difference of one pixel is a defect.
- **R-33-062** This change MUST NOT weaken `R-30-153` or `R-32-015`. Both keep their current
  meaning and neither gains a platform exception.

## 8. Platform floors

| Platform | Floor | What the floor guarantees |
| --- | --- | --- |
| iOS | 15.0 | nothing beyond the toolchain floor: Flutter supports no lower version |
| Android | API 33 | the wallpaper scheme, and no `POST_NOTIFICATIONS` branch |

One row per platform, and no row for an older release. `R-20-026` owns the pinned values, and
`targetSdk` stays 36. The two floors differ in kind, and a reader MUST NOT read them as one
decision. Android API 33 is a **product decision**: the `POST_NOTIFICATIONS` runtime permission
arrives at API 33, and an older release grants it implicitly, which costs a version branch in the
code. iOS 15.0 is only the **toolchain floor**, because Flutter supports no lower version and
nothing in the design needs a higher one, per `R-33-017`. Section 2 holds what each platform
resolves to, and section 5 holds the control map, so this table names only the floor and what it
buys. The terminal grid is absent on purpose: it is Selenized on both platforms, per `R-33-055`.

- **R-33-063** The table above is normative and complete. A platform MUST NOT be added without a
  filled cell in every column and a source in `## Sources`. A version range MUST NOT be added as a
  row: a second appearance for an older release is out of scope, and a capability that the floor
  already guarantees MUST NOT be tested at run time, at build time, or behind a build flavour.
- **R-33-066** A cell MUST NOT ship as unverified. A version, an API name and a package name in this
  document each carry a primary source in `## Sources`, and a fact that loses its source MUST move
  to `## Open questions` with a stated default.

## Retired rules

The iOS half of the chrome builds no glass, so every rule that specified the material, its surface
list, or the platform view that hosted it is dead. Every id below is retired. The id stays reserved
and no later rule reuses it, so an old citation still resolves to an explanation and not to a gap.
A rule that was only rewritten keeps its id, stays in its own section, and has no row here.

| Rule | What happened |
| --- | --- |
| `R-33-011` | **Retired.** It required iOS 26.0 for glass. The app ships no glass. |
| `R-33-014` | **Retired.** The glass surface list. See below. |
| `R-33-016` | **Retired.** The old iOS gate and its opaque design. See below. |
| `R-33-018` | **Retired.** It handled a failed platform view. See below. |
| `R-33-019` | **Retired.** It scoped the glass platform view to a background layer. |
| `R-33-020` | **Retired.** It scoped a native control hosted in a platform view. |
| `R-33-026` | **Retired.** The degenerate scheme (`ColorScheme.fromSeed` with `contrastLevel` pin). No longer used. |
| `R-33-031` | **Retired.** The operating-system dynamic-colour setting handler. The app uses the fixed Herdr palette. |
| `R-33-046` | **Retired.** The contrast escalation (0.5, 1.0). No longer exists. |
| `R-33-047` | **Retired.** The degenerate scheme fallback. No longer exists. |
| `R-33-048` | **Retired.** The assertion timing for generated schemes. No longer applies. |
| `R-33-049` | **Retired.** The diagnostics screen scheme observability. No longer applies. |
| `R-33-059` | **Retired.** Leak path 4 was a platform-view backdrop. There is none. |
| `R-33-064` | **Retired.** It read the OS version. `R-33-063` forbids that. |
| `R-33-065` | **Retired.** It defined a version gate. `R-33-063` replaces it. |
| `R-33-067` | **Retired.** It forbade a deployment-target gate, now the floor. |
| `R-33-050` | **Retired.** It required a translucent chrome surface to take its translucency from the `cupertino_ui` widget alone. Both platforms now draw an opaque fixed Herdr palette, so no translucent chrome surface exists. |
| `R-33-053` | **Retired.** It fixed the legibility test protocol for a translucent chrome surface. No translucent chrome surface exists. |
| `R-33-054` | **Retired.** It forbade stating a contrast ratio for a translucent surface. Every chrome surface is now opaque and measured in `R-32-150`. |

`R-33-016` needs more than a row, because it carried five citations across two documents. It is
retired, and no later rule reuses its id. It gated glass on the iOS version, and there is now no
glass to gate. The opaque form of a translucent chrome surface is `R-33-068`, and it is reachable
from `R-33-051` and `R-33-052` only. A document that named the old opaque form cites one of those
three ids.

`R-33-014` also needs more than a row, because four sibling documents cited it as the iOS glass
surface list. It is retired, and no later rule reuses its id. The surfaces it named still exist, so
`R-33-012` lists them and names the `cupertino_ui` widget that draws each one. A document that
cited `R-33-014` for the iOS appearance now cites `R-33-012`, and one that cited it to keep a
surface opaque now cites `R-33-015`.

`R-33-018`, `R-33-019` and `R-33-020` are retired together, because all three existed only to
describe the platform view that hosted the material. `R-33-038` carries the surviving requirement,
which is to use the design library's own widget and never re-implement one or host one.

`R-32-014` is rewritten in its own document, because Android chrome now follows the
Herdr fixed palette, and `docs/32-design-language.md` owns that change.

## Open questions

- **When does `cupertino_ui` ship official Liquid Glass support?** The date is unknown. The Flutter
  team has stated an intent to work on Apple's design language, and it has committed to no date.
  Issue 170310 is the tracking reference and it is still open. A "late 2026" figure in circulation
  is a third party's inference, not a commitment, so this document states no date. Recommended
  default until an official release exists: ship the flat Cupertino appearance of `R-33-012` and
  change nothing else. `R-33-069` owns the adoption when it arrives, and no document may state a
  date before Flutter does.

## Sources

- Adopting Liquid Glass, the material, and the automatic adoption that applies to standard SwiftUI,
  UIKit and AppKit components and therefore not to a Flutter widget, with the
  `glassEffect(_:in:)` and `UIGlassEffect` APIs:
  `https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass`
- Flutter is not developing the Apple 26 design features in Cupertino, that work moved to
  standalone packages, and this open issue is the tracking reference for the design language:
  `https://github.com/flutter/flutter/issues/170310`
- Glass reflects colour from outside its own bounds, which a blur does not, in the same issue
  thread: `https://github.com/flutter/flutter/issues/170310`
- `cupertino_ui`, the official Flutter Cupertino design library that draws the iOS chrome:
  `https://pub.dev/packages/cupertino_ui`
- Flutter supports iOS 15 to 26 and does not support iOS 14 or earlier, which makes 15.0 the
  toolchain floor: `https://docs.flutter.dev/reference/supported-platforms`
- Reduce Transparency, `UIAccessibility.isReduceTransparencyEnabled`:
  `https://developer.apple.com/documentation/uikit/uiaccessibility/isreducetransparencyenabled`
- Flutter `MediaQueryData`, which lists `highContrast` and no reduce-transparency field:
  `https://api.flutter.dev/flutter/widgets/MediaQueryData-class.html`
- Wallpaper dynamic colour needs Android 12, API 31, and above, which the API 33 floor exceeds:
  `https://developer.android.com/develop/ui/compose/designsystems/material3`
- `dynamic_color` 2.1.0, Apache-2.0, published by material.io, with `DynamicColorBuilder` and
  `DynamicColorPlugin.getCorePalette`: `https://pub.dev/packages/dynamic_color`
- `ColorScheme.fromSeed` with `contrastLevel` at 0.0 default, 0.5 medium and 1.0 high, and
  `DynamicSchemeVariant.tonalSpot` as the default variant:
  `https://api.flutter.dev/flutter/material/ColorScheme/ColorScheme.fromSeed.html`
- Tone, tonal palettes from 0 to 100, and tone as the driver of contrast, in the file
  `concepts/dynamic_color_scheme.md` of:
  `https://github.com/material-foundation/material-color-utilities`
- Edge-to-edge is enforced at `targetSdk` 36 and `windowOptOutEdgeToEdgeEnforcement` is disabled:
  `https://developer.android.com/about/versions/16/behavior-changes-16`
- Edge-to-edge enforcement began at `targetSdk` 35 on Android 15:
  `https://developer.android.com/about/versions/15/behavior-changes-15`
- WCAG 2.2 contrast minimum, the 4.5 to 1 threshold and its reason:
  `https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html`
- `BackButtonIcon`, the "back" icon that is appropriate for the current `TargetPlatform`, and
  `BackButton`, which `AppBar` supplies in its `leading` slot when the route is not the
  `Navigator`'s first route: `https://api.flutter.dev/flutter/material/BackButtonIcon-class.html`
- The glyph each platform resolves to, `Icons.arrow_back` on Android and
  `Icons.arrow_back_ios_new_rounded` on iOS, and the Android semantics label from
  `MaterialLocalizations.backButtonTooltip`, in `BackButtonIcon.build` in `action_buttons.dart`;
  and `matchTextDirection: true` on both `Icons.arrow_back` and `Icons.arrow_back_ios_new`, in
  `icons.dart`, which is why `R-33-070` does not rest on mirroring. Both files are in:
  `https://github.com/flutter/flutter/tree/main/packages/flutter/lib/src/material`
- `Icons.AutoMirrored.Filled.ArrowBack` as the documented navigation icon of an Android top app bar:
  `https://developer.android.com/develop/ui/compose/components/app-bars-navigate`
- Predictive back, its gesture insets, and the instruction to keep touch and drag targets out of
  those areas: `https://developer.android.com/design/ui/mobile/guides/patterns/predictive-back`
- `PredictiveBackPageTransitionsBuilder`, which needs Android U and falls back to
  `FadeForwardsPageTransitionsBuilder` elsewhere:
  `https://api.flutter.dev/flutter/material/PredictiveBackPageTransitionsBuilder-class.html`
- `CupertinoNavigationBar`, whose `leading` becomes a back chevron button when
  `automaticallyImplyLeading` is true, with `previousPageTitle` for the previous route's title:
  `https://pub.dev/documentation/cupertino_ui/latest/cupertino_ui/CupertinoNavigationBar-class.html`
- `CupertinoPageRoute` and its inherited `popGestureEnabled` and `popGestureInProgress`, which carry
  the iOS back swipe and the Android predictive-back gesture:
  `https://pub.dev/documentation/cupertino_ui/latest/cupertino_ui/CupertinoPageRoute-class.html`
- Keep the tab bar visible when people navigate to different sections, because a hidden tab bar
  makes a person forget which area they are in, and a modal view is the single exception:
  `https://developer.apple.com/design/human-interface-guidelines/tab-bars`
- `CupertinoTabView`, a single tab view with its own `Navigator` state and history, which is how a
  pushed route keeps the tab bar:
  `https://pub.dev/documentation/cupertino_ui/latest/cupertino_ui/CupertinoTabView-class.html`
- The Material navigation bar is primary navigation for a parent layout view and the primary
  destinations, and a child view takes a secondary navigation pattern:
  `https://developer.android.com/design/ui/mobile/guides/layout-and-content/layout-and-nav-patterns`
- A disclosure indicator reveals the next level in a hierarchy and does not show details about the
  item, and a detail disclosure button does not support hierarchical navigation:
  `https://developer.apple.com/design/human-interface-guidelines/lists-and-tables`
- `UITableViewCell.AccessoryType.disclosureIndicator`, whose own abstract is "A chevron-shaped
  control for presenting new content":
  `https://developer.apple.com/documentation/uikit/uitableviewcell/accessorytype-swift.enum`
- `CupertinoListSection`, `CupertinoListTile` and `CupertinoExpansionTile`, the iOS list widgets
  of `R-33-072` and `R-33-073`:
  `https://pub.dev/documentation/cupertino_ui/latest/cupertino_ui/CupertinoListSection-class.html`
- Android settings patterns, which send a single choice to a screen or a dialog:
  `https://developer.android.com/design/ui/mobile/guides/patterns/settings`
- Always use `Cancel` to title a button that cancels an alert's action, place the default button at
  the trailing side of a row or the top of a stack, keep `Cancel` at the leading side or the bottom,
  do not make `Cancel` the default, and prefer no default button where a destructive action is
  present: `https://developer.apple.com/design/human-interface-guidelines/alerts`
- `AlertDialog` takes `confirmButton` and `dismissButton` as roles and places them itself:
  `https://developer.android.com/develop/ui/compose/components/dialog`
- A pull-down button's menu closes when a person chooses an item, an `Add` button is a named
  example, and at least three items are recommended, which together are the refusal in `R-33-037`:
  `https://developer.apple.com/design/human-interface-guidelines/pull-down-buttons`
- `CupertinoMenuAnchor` and `CupertinoMenuItem`, with the `subtitle` and `isDestructiveAction` that
  `R-33-037` records as available but not sufficient:
  `https://pub.dev/documentation/cupertino_ui/latest/cupertino_ui/CupertinoMenuItem-class.html`
- `CupertinoSheetRoute`, its downward drag dismissal, and the `scrollableBuilder` `ScrollController`
  that an inner scrollable must use or the drag to dismiss stops firing:
  `https://pub.dev/documentation/cupertino_ui/latest/cupertino_ui/CupertinoSheetRoute-class.html`
- Sheets, the iOS surface for a task that a person starts and then confirms or cancels:
  `https://developer.apple.com/design/human-interface-guidelines/sheets`
