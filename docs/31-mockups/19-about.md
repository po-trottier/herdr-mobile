# 19 - About

| Field | Value |
| --- | --- |
| Route | `/settings/about` |
| Surface | Device, Android and iOS |
| Spec | `docs/30-ux-spec.md` |

This screen is the legal surface of the app. `R-23-060` requires it to carry the licence list and
the attribution notices, and it states why that obligation lands here rather than on a store
listing. The project licence is Apache License 2.0, per `R-03-020`. This file owns how the screen
meets the requirement, and not the requirement itself.

The screen holds three rows and nothing else. Every value on it is a build constant or a bundled
asset, so the screen needs no network and no connected computer.

## Wireframe

```text
+--------------------------------------+
| <  About                             |
+--------------------------------------+
| Herdr Remote                         |
|   1.0.0 (412)                        |
+--------------------------------------+
| Herdr protocol targeted           21 |
+--------------------------------------+
| Licences   This app: Apache-2.0    > |
+--------------------------------------+
```

## Wireframe, the licence index

```text
+--------------------------------------+
| <  Licences                          |
+--------------------------------------+
| Herdr Remote                       > |
|   1 licence                          |
+--------------------------------------+
| Skia                               > |
|   3 licences                         |
+--------------------------------------+
| go_router                          > |
|   1 licence                          |
+--------------------------------------+
| xterm2                             > |
|   1 licence                          |
+--------------------------------------+
```

## Wireframe, one package's licence

```text
+--------------------------------------+
| <  Herdr Remote                      |
|    1 licence                         |
+--------------------------------------+
| Apache License                       |
| Version 2.0, January 2004            |
| http://www.apache.org/licenses/      |
|                                      |
| TERMS AND CONDITIONS FOR USE,        |
| REPRODUCTION, AND DISTRIBUTION       |
|                                      |
| 1. Definitions.                      |
|                                      |
| "License" shall mean the terms and   |
| conditions for use, reproduction,    |
| ...                                  |
+--------------------------------------+
```

## Wireframe, the licence bundle failed to load

```text
+--------------------------------------+
| <  Licences                          |
+--------------------------------------+
| ! The licence list did not load.     |
|   Unable to load asset: NOTICES      |
|                                      |
|   This build shipped without its     |
|   attributions. No action here can   |
|   repair it.                         |
+--------------------------------------+
```

## Callouts

1. The back control and the title `About`. The app bar of `R-32-510`, title token `type.heading`.
   The title takes `type.heading` and not `type.title`, because this screen carries a back control.
   The drawn `<` is a placeholder for that control and not a glyph choice: `R-33-070` gives the back
   glyph, the back label and the back gesture to each platform's own navigation component, so this
   file names none of them.
2. `Herdr Remote` and `1.0.0 (412)`. The hero of this screen, which `R-32-332` names as one of the
   five hero screens: the eyebrow `ABOUT` of `R-32-590`, then the name in `type.title`, then the
   version and the build in `type.mono.code` in `color.fg.secondary`, all at the `space.4` screen
   inset, with the brand mark of `R-32-426` at the top trailing corner. The rows of callouts 3 and
   4 follow at `space.6` below, full width, so their `space.4` text inset is the hero's left edge
   (amended 2026-09-08 by the product owner: this callout still drew the name as a two-line list
   row after the hero decision of 2026-09-03, and the rows sat inside the hero's inset, 16 px
   right of the name). The name is the exact string `R-03-010` fixes. The block is not
   interactive, so it carries no chevron and takes no tap.
3. `Herdr protocol targeted` and `21`. The one-line list row of `R-32-515` at `size.row.one_line`,
   with the value as the trailing state word in `type.label`. The label says `targeted`, because
   this number is a build constant and not a reading. `13-connection.md` owns the live number, and
   the two screens MUST NOT read as one.
4. `Licences`, the value `This app: Apache-2.0`, and a trailing chevron, all from the row anatomy of
   `R-32-515`. The chevron is honest here, per `R-33-072`: this row opens the next level in the
   hierarchy, and a tap routes to `/settings/about/licences`. The value is scoped with `This app:`
   because the licence index behind it lists packages under other licences, and a bare `Apache-2.0`
   on this row would read as a claim about all of them.
5. The back control and the title `Licences` on the index. The app bar of `R-32-510`, title token
   `type.heading`, with the back glyph of `R-33-070`. The index body is a plain `color.bg.base`
   list with no ground grid and no paper block, like every other list screen, and no brand mark and
   no eyebrow, per `R-31-19-16` (amended 2026-09-09 by the product owner, per `R-03-107` as
   amended: for part of that day the index painted the grid with the rows on paper).
   `/settings/about` itself is a hero screen and sets its text on the grid of `R-32-332`; its two
   list pages have content and set their text on plain `color.bg.base`.
6. A package row on the index. The two-line list row of `R-32-515`: the package name on the primary
   line in `type.body.strong`, then the licence count on the secondary line in `type.caption` in
   `color.fg.secondary`. A trailing chevron, because this row also opens the next level. The count
   reads `1 licence` or `N licences`, because one package can carry more than one licence entry. The
   app's own package sits first, per `R-31-19-05`. Every other package follows in case-insensitive
   alphabetical order, which is the one place this screen orders anything.
7. The detail app bar. Title the package name in `type.heading`, and the same licence count under it
   in `type.caption`, so the count a person tapped is still on screen. The back control is
   `R-33-070`'s. The detail body is plain `color.bg.base` too, with no grid and no paper block, per
   `R-31-19-16` (amended 2026-09-09, per `R-03-107` as amended).
8. The licence text. Token `type.mono.code` in `color.fg.primary` on `color.bg.base`, wrapped and
   never truncated. A licence is a legal text, so a monospace token is correct here for the reason
   `R-30-212` gives for a path or a raw error: the line breaks and the indents carry meaning. The
   text is selectable, per `R-31-19-13`. Where a package holds more than one licence entry, the
   entries sit on this one page in the order the collector returns them, separated by a divider.
9. `http://www.apache.org/licenses/`. A URL inside a licence text stays inert text in the same
   `type.mono.code` run. It is not a link, it is not underlined, and it takes no accent ink, per
   `R-31-19-11`.
10. `! The licence list did not load.`, the raw line, and the two sentences that follow. The error
    block of `R-32-555`: the plain sentence with `treat.error` and the raw text in `type.mono.code`,
    per `R-30-803`. There is **no** retry control. A bundled asset that is missing or unparseable at
    run time is missing or unparseable in every run of that build, so a retry would repeat the same
    read and fail the same way. `R-31-19-14` holds that, and it makes the same call for an empty
    list.
11. Primary navigation. This screen and its two child pages are pushed from the `Settings`
    destination, and the two platforms diverge on what the bottom control does then. The drawing is
    platform-neutral and omits it. `R-33-071` owns the divergence.

## Where the licence list comes from

The list is generated at build time. It is never authored.

The Flutter tool collects the `LICENSE` file at the root of every package in the build into one
`NOTICES` asset. The `services` package registers a collector that splits that asset and adds each
entry to `LicenseRegistry`. So the app reads `LicenseRegistry.licenses` and draws what it returns.
The reuse rung is the framework feature that the pinned SDK already ships. The app adds no package
and writes no collector.

Two consequences earn that choice:

1. A hand-written list would be a second copy of the dependency table in
   `docs/20-mobile-framework.md`. A second copy drifts, and a drifted attribution is a licence
   breach that looks like a typing error.
2. The project's own entry arrives through the same collector, because the app package carries the
   Apache-2.0 text as its own `LICENSE` file. One mechanism serves the project licence and every
   third-party licence, so both licence pages read from one source.

## Why the app draws the licence pages itself

A review challenged `R-31-19-06`. It argued that the rejection of `LicensePage` and
`showLicensePage` is right for iOS and wrong for Android, where the Material page is the native
answer and the framework already built it. The rule was re-decided against that argument. It stands,
but not for the reason it first gave.

**The old reason was wrong.** It rejected both entry points because they draw Material chrome, and
`R-33-006`, `R-33-012` and `R-33-033` require `cupertino_ui` chrome on iOS. That rules them out on
iOS. It says nothing about Android, where Material chrome is the correct chrome. The reviewer is
right about that, and the rule no longer relies on it.

**Two points of the argument are conceded.** `LicensePage` is what an Android person has met in
other apps. It is also genuinely built: at the pinned Flutter 3.47.0 it is a package index plus a
per-package detail page, it puts the application's own package first, it parses each licence off the
main thread, and it costs no drawing code.

The second concession changed this file. The same review found the old single scrolling document
unusable, and the framework's structure is the right one, so this screen now copies it. See
`R-31-19-15`. Structure therefore no longer separates the two answers. One question is left: on
Android, does the app draw that structure, or call `showLicensePage`?

**Three checked properties of `LicensePage` at 3.47.0 answer it.**

1. It draws each licence paragraph with a plain `Text`, so a person cannot select the text.
   `R-31-19-13` requires selection. A `SelectionArea` around the page repairs this, so it is a
   wrapper and not a blocker. It is listed because it is one more thing to remember on one platform.
2. An empty registry draws an empty index and no error. `_initDefaultDetailPage` returns early when
   the package list is empty, and the index then draws its header alone. `R-31-19-14` requires an
   error there, so the app writes that guard before the push in either design.
3. It runs its own nested `Navigator` for its master-and-detail flow. The app routes with
   `go_router`, per `docs/20-mobile-framework.md`. On Android the licences route would hold a
   navigator that the router cannot see, and no package page would have an address.

It also fixes the licence body to `theme.textTheme.bodySmall`, so the monospace run that callout 8
requires is reachable only by redefining a theme text style for that one route.

**Why Android reuse loses.** A second page structure makes this file speak twice. `R-31-19-11`,
`R-31-19-13`, the focus order and the semantics labels would each need an Android clause that reads
`as the framework draws it`. One page states each of them once, and one page is one behaviour to
test. Against that, reuse would save the index list, the detail list, and the fold from
`LicenseRegistry.licenses` into a package map. That is a modest amount of list code with no logic in
it, and the app writes it once for both platforms. Shared list code is cheaper than a platform
branch that makes six rules conditional and puts an unrouted navigator inside a routed app.

So Android reuse loses on integration cost, not on quality. Chrome still diverges by platform: the
app bar, the back control, the list composition and the row affordance come from `R-33-070`,
`R-33-072` and `R-33-073`. Only the page structure and the content rules are shared.

## States

| State | Trigger | Screen shows |
| --- | --- | --- |
| Default | The route opened. | The first wireframe. Every row reads at once, because every value is a build constant. |
| Index default | The collected bundle parsed. | The second wireframe. The app's own package is the first row. |
| Index loading | The licences route opened and the bundle has not finished parsing. | Skeleton bars of `R-32-560` at `size.row.two_line`, shown only after 150 ms, per `R-30-004`. The app bar stays. |
| Detail default | A package row was tapped. | The third wireframe, at the top of that package's first licence entry. |
| Bundle failed | The `NOTICES` asset is missing, or it did not parse, or it parsed to no entry at all. | The fourth wireframe, on the index route. It carries no retry, per `R-31-19-14`. The detail route is unreachable, because no package row exists to open it. |
| Empty | Not reachable as a state of its own. A build always carries the project licence, so the index always holds one row. An empty index proves the bundle failed, and `R-31-19-14` folds it into `Bundle failed`. | - |
| Offline | The phone has no network. | Nothing changes. No strip appears, no row dims and no value is withheld, per `R-31-19-07`. |
| No computer saved | No computer was ever paired, or every one was forgotten. | Nothing changes. This screen reads no Host state. |
| Not connected | A computer is saved and none is connected, per `R-03-046`. | Nothing changes. No value on this screen comes from a computer. |
| Large text | The system text scale is above 1.3. | Every row grows and every label wraps to two lines, per `R-30-703`. The licence text reflows. No target shrinks, per `R-30-741`. |

## Navigation

- In: the `About` row on `15-appearance.md`.
- Out, back: `/settings`, mockup `15-appearance.md`.
- Out, `Licences`: `/settings/about/licences`, the index, drawn in this file.
- Out, a package row: `/settings/about/licences/:package`, the detail, drawn in this file. The
  segment is the package name from `LicenseRegistry`, percent-encoded.
- Out, back from the detail: the index. Out, back from the index: `/settings/about`.
- No other route leaves this screen. No control on it leaves the app, per `R-31-19-11`.

## Rules

- **R-31-19-01** This screen MUST hold exactly three rows: the app name with its version, the Herdr
  protocol the build targets, and the licences row. It MUST NOT hold a fourth row. This file owns
  that set, and every addition a reader will suggest is refused by one of `R-31-19-08` to
  `R-31-19-12`.
- **R-31-19-02** The version MUST be read from the build and MUST NOT be written into the source of
  this screen. It MUST be the same value the app sends as `device_info.app_version`, so one build
  has one version everywhere. The form is the semantic version of `R-23-038`, then the platform
  build number in brackets.
- **R-31-19-03** The protocol row MUST show the Herdr socket protocol the build targets, which
  `R-02-008` fixes. It MUST read that value from the same build constant and MUST NOT restate the
  number as a fact of its own. It MUST NOT show a live reading, because this screen reaches no
  computer, and `13-connection.md` owns the live number and the mismatch state. It MUST NOT show the
  relay protocol version of `R-23-042`, which is a different number and would invite a person to
  compare two unrelated integers.
- **R-31-19-04** The licence list MUST be generated from `LicenseRegistry`, whose entries the
  Flutter tool collects from each package's own `LICENSE` file at build time. The app MUST NOT hold
  a hand-maintained list, and MUST NOT restate the dependency table of
  `docs/20-mobile-framework.md`.
- **R-31-19-05** The full Apache-2.0 text MUST be reachable in the app, which is the licence half of
  `R-23-060`. It MUST arrive through the collector of `R-31-19-04` as the entry for the app's own
  package, and it MUST be the first row of the licence index. `R-03-020` owns the canonical text in
  the root `LICENSE` file, so this screen MUST NOT carry a second copy of that text in its own
  source.
- **R-31-19-06** The app MUST NOT call `showLicensePage` and MUST NOT show `LicensePage`, on either
  platform. The app MUST reuse the framework's licence **data**, per `R-31-19-04`, and MUST draw
  both licence pages itself with the app bar of `R-32-510` and the rows of `R-32-515`. On iOS the
  refusal is chrome: both draw Material chrome, and `R-33-006`, `R-33-012` and `R-33-033` require
  `cupertino_ui` chrome there. On Android that reason does not apply, because Material chrome is
  correct there, so Android reuse was re-decided on its own merits and still loses. The section
  `Why the app draws the licence pages itself` holds the argument, the three checked properties of
  `LicensePage` at the pinned 3.47.0, and the cost of the platform branch. A future reader who
  wants to reopen this MUST answer that section, and MUST NOT reopen it on the chrome reason alone.
- **R-31-19-07** This screen and both licence pages MUST work with no network at all. Every value is
  a build constant or a bundled asset. They MUST NOT show an offline strip, MUST NOT dim a row, MUST
  NOT disable a control and MUST NOT gate a value on a connection. `R-30-805` and `R-30-806` govern
  a screen that lost data it needs, and this screen needs none, so neither applies here.
- **R-31-19-08** This screen MUST NOT show the relay origin, the routing handle, a pairing phrase, a
  static key or a key fingerprint. `R-31-15-07` refuses the handle, the phrase and the key on
  `/settings`, which does own the origin. This screen owns none of them, so it shows none of them.
  `R-13-041` gives the Device fingerprint exactly one home, and this screen is not it.
- **R-31-19-09** This screen MUST NOT show an analytics identifier, a crash-report identifier, an
  install identifier or a device identifier. None exists. The app collects nothing and ships no
  analytics framework and no crash-reporting framework, per `R-23-015` and `R-23-019`. An identifier
  on this screen is evidence that the product gained one.
- **R-31-19-10** This screen MUST NOT carry NVIDIA branding of any kind: no name, no mark, no logo,
  no endpoint and no copyright line, per `R-03-001` and `R-03-003`. An about screen is where a
  vendor name creeps in, so the prohibition is stated here and not left to the general rule.
- **R-31-19-11** No control on this screen or on either licence page MAY leave the app. There is no
  external link, no in-app browser and no web view, per `R-20-002`. A URL inside a licence text MUST
  stay inert text in the licence text run: not tappable, not underlined and not in accent ink. The
  reason is that a licence text must be readable offline, and a link that opens a browser turns a
  legal text into a network request. If a later row ever does leave the app, it MUST say so in its
  own label before it leaves.
- **R-31-19-12** This screen MUST NOT offer a copy action, a share action, an update check, a rate
  action or a feedback action. `R-31-13-05` gives the copy-for-a-bug-report action one home on
  `/hosts/:hostId/diagnostics`, and that page already carries the protocol number. A store handles
  an update, and `docs/23-public-release.md` owns the support page.
- **R-31-19-13** The licence text MUST be selectable, for the reason `R-32-555` makes a raw error
  selectable. An attribution a person cannot copy fails the purpose of carrying it.
- **R-31-19-14** A failed licence bundle MUST be an error, and the error MUST NOT offer a retry.
  1. A licence index with no row MUST be treated as an error and MUST NOT be drawn as an empty
     state. A build always carries the project licence, so an empty index proves the collected
     bundle did not load, which means the app is shipping without its attributions. The screen MUST
     use the error block of `R-30-803`, and MUST NOT show a sentence that reads as if no licence
     applies.
  2. A missing `NOTICES` asset, an asset that does not parse, and an empty index are one state. All
     three have the same cause, which is a build that shipped wrong, and the same remedy, which is a
     new build.
  3. That state MUST NOT carry a retry control. The asset is bundled, so the read never reaches a
     network and never depends on a connection. A second read in the same build reads the same bytes
     and fails the same way. A control that cannot repair its own cause teaches a person to press it
     and wait. This is a **second** exemption from the one retry of `R-30-804`, alongside the
     `Outcome unknown` state of `R-30-518` that `R-30-804` already names. The two exemptions have
     different reasons: `R-30-518` forbids a retry because a repeat can act twice on the computer,
     and this rule forbids one because a repeat cannot act at all.
  4. The state MUST instead say that the build is at fault, in the words of the fourth wireframe,
     and MUST show the raw line in `type.mono.code` so a bug report carries it.
  5. The release build MUST fail when the `NOTICES` asset is absent or does not parse, so this state
     is unreachable in a shipped build. `R-23-060` sets the attribution obligation that the gate
     protects, and `docs/90-implementation-plan.md` owns the build step. Where the gate is in place,
     this state is an assertion surface for a development build and nothing more.
- **R-31-19-15** The licences surface MUST be a package index and a per-package detail page, and
  MUST NOT be one document that concatenates every licence.
  1. The index MUST list one row per package, with the package name and the number of licence
     entries it carries. A row MUST open that package's detail page.
  2. The detail page MUST show every licence entry bound to that one package, in the order the
     collector returns them.
  3. The reason is scale, not taste. `LicenseRegistry` returns an entry for every package in the
     build, which includes each third-party component the Flutter engine carries, so the list runs
     to dozens of packages and thousands of lines. One scrolling document gives a person no way to
     reach the package they came for.
  4. The index MUST put the app's own package first, per `R-31-19-05`, then every other package in
     case-insensitive alphabetical order. Inside one package the entry order MUST stay as the
     collector gives it, because a licence file is not the app's to reorder.
- **R-31-19-16** The licence index and the licence detail page MUST paint plain `color.bg.base`
  behind their content, with no ground grid and no paper block: the index rows and the detail
  page's text sit directly on that ground. No brand mark and no eyebrow: those belong to the hero of
  `/settings/about`, and the two licence pages are a list and a document. Neither page is ever
  empty, per `R-31-19-14`, so neither takes the watermark of `R-32-554`. The index rows are the
  rows of `R-32-515` at full width, with the hairline divider of that anatomy and no gap between
  them, per `R-30-231`. (Decided 2026-09-03; amended 2026-09-09 by the product owner, per
  `R-03-107` as amended: for part of that day both pages painted the grid of `R-32-332` with their
  content on paper, until the owner limited the grid to the hero screens and the empty states.)

## Accessibility

- Touch target: the back control on all three pages, the `Licences` row, and every package row on
  the index meet the minimum target of `R-30-290` and `R-30-740`. The name row and the protocol row
  are not interactive, so neither is a target and neither MUST be given a tap. The failure state
  carries no control at all, per `R-31-19-14`. A large text scale MUST NOT shrink any target, per
  `R-30-741`.
- Contrast: every label uses `color.fg.primary` and every secondary line and trailing chevron
  `color.fg.secondary`, on `color.bg.base`. The trailing value uses `color.fg.primary`. On iOS those
  chrome pairs are fixed, so they are passing rows in `R-32-150`, per `R-30-720`. On Android the
  same tokens resolve from the operating system's colour, per `R-33-024`, so the runtime assertion
  of `R-33-044` proves them instead. The licence text uses `type.mono.code` in `color.fg.primary` on
  `color.bg.base`, the same pair as a raw error block. The error sentence uses `treat.error`, which
  carries the `error` icon as well as the hue, so the failure never differs by colour alone, per
  `R-30-140` and `R-30-141`.
- Screen reader: the back control belongs to the platform's navigation component, per `R-33-070`,
  and that component supplies its own accessibility label. The app MUST NOT set one, so `R-30-717`
  reaches no control on these three pages. Each row MUST be one semantics node whose label reads the
  label then the value, per `R-32-505`. The name row MUST expose `Herdr Remote, version 1.0.0, build
  412`, so a screen reader speaks the build number and never a bracket. The protocol row MUST read
  `Herdr protocol targeted, 21`. The licences row MUST read `Licences, this app: Apache-2.0`. Each
  index row MUST read the package name then the count, so `xterm2, 1 licence`. The `error` icon of
  the failure state MUST carry `error` as its semantics label, per `R-30-716`. The licence text MUST
  be exposed as readable text and MUST NOT be a live region, because it never changes while a person
  reads it.
- Focus order: per `R-30-719`. On `/settings/about`: the back control, the title, the name row, the
  protocol row, then the licences row. On the index: the back control, the title, then each package
  row in drawing order. On a detail page: the back control, the title with its count, then the
  licence text in drawing order. In the failure state the order ends at the error block, because no
  control follows it.

## Open questions

None.

## Sources

- `docs/03-product-decisions.md` - the vendor neutrality rules `R-03-001` and `R-03-003`, the
  display name `R-03-010`, the project licence `R-03-020`, and the not-connected rule `R-03-046`.
- `docs/32-design-language.md` - the app bar `R-32-510`, the list row `R-32-515`, the error block
  `R-32-555`, the skeleton `R-32-560`, the treatment compositions `R-32-506`, the semantics label
  pattern `R-32-505`, the size set `R-32-350`, the type tokens, and the contrast table `R-32-150`.
- `docs/30-ux-spec.md` - the spinner delay `R-30-004`, the treatment rules `R-30-140` and
  `R-30-141`, the monospace rule `R-30-212`, the touch target `R-30-290`, the error state rules
  `R-30-803` and `R-30-804`, the offline rules `R-30-805` and `R-30-806`, the large-text row rule
  `R-30-703`, and the accessibility rules `R-30-716`, `R-30-717`, `R-30-719`, `R-30-720`, `R-30-740`
  and `R-30-741`.
- `docs/02-herdr-probe-results.md` - `R-02-008`, the Herdr socket protocol this build targets.
- `docs/11-relay-protocol.md` - the `device_info` message and its `app_version` field, `R-11-131`.
- `docs/13-security-pairing.md` - the display fingerprint `R-13-040` and its one home `R-13-041`.
- `docs/20-mobile-framework.md` - the dependency table this screen MUST NOT restate, and the web
  view prohibition `R-20-002`.
- `docs/23-public-release.md` - the attribution obligation `R-23-060`, which this screen meets, the
  semantic versioning rule `R-23-038`, the relay protocol constant `R-23-042`, and the privacy
  statements `R-23-015` and `R-23-019`.
- `docs/33-platform-chrome.md` - the platform split `R-33-006`, the plain `cupertino_ui` appearance
  `R-33-012`, the Android dynamic chrome colour `R-33-024`, the native control map `R-33-033`, the
  runtime contrast assertion `R-33-044`, the back control `R-33-070`, the primary navigation on a
  pushed route `R-33-071`, and the row affordance `R-33-072`.
- `https://api.flutter.dev/flutter/foundation/LicenseRegistry-class.html` - the Flutter tool
  collects every package `LICENSE` file into one `NOTICES` asset, and the `services` package
  registers the collector that splits it.
- `https://api.flutter.dev/flutter/material/showLicensePage.html` - `showLicensePage` pushes a
  Material `LicensePage`.
- `https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/material/about.dart` -
  the `LicensePage` source at the pinned SDK. It is the evidence for the three checked properties in
  `Why the app draws the licence pages itself`: `_PackageLicensePageState._initLicenses` builds each
  paragraph as a plain `Text`, `_PackagesViewState._initDefaultDetailPage` returns early on an empty
  package list, and `_MasterDetailFlowState._nestedUI` runs its own `Navigator`. It is also the
  evidence that the framework page is an index plus a detail page, which `R-31-19-15` copies.
- `docs/31-mockups/15-appearance.md` - the `About` row that routes here.
- `docs/31-mockups/13-connection.md` - the live Herdr protocol reading and the copy action, both of
  which stay there.
