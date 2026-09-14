# Public Release

## Identity and metadata

| Field | iOS | Android |
| --- | --- | --- |
| App display name | `Herdr Remote` | `Herdr Remote` |
| Bundle / application id | `dev.herdr.remote` | `dev.herdr.remote` |
| Primary category | Developer Tools | Tools |
| Secondary category | Utilities | none |
| Age rating | 4+ | IARC 3+ / ESRB E / PEGI 3 |
| Subtitle | Remote terminal for your coding agents | not applicable |
| Price | Free | Free |
| In-app purchases | none | none |
| Licence | Apache-2.0 | Apache-2.0 |
| Custom URI scheme | `herdr-remote` | `herdr-remote` |

### Rule: Identity

- R-23-001: The app display name MUST be `Herdr Remote` on both stores.
- R-23-002: The bundle identifier and application id MUST be `dev.herdr.remote`.
- R-23-003: The primary category on the Apple App Store MUST be Developer Tools. The secondary category
  MAY be Utilities.
- R-23-004: The primary category on Google Play MUST be Tools.
- R-23-005: The app MUST have no in-app purchases, no advertisements and no subscription.
- R-23-006: The app MUST be free to download on both stores.

### Rule: Platform floors and store consequences

The platform floors are iOS `15.0` and Android `minSdk 33` (`targetSdk 36`). The Android
floor is a deliberate decision to take the `POST_NOTIFICATIONS` runtime permission at API 33;
the iOS floor is the Flutter 3.47 toolchain minimum, because nothing in the design needs more.
See `R-20-026` for the floor values and `R-20-027` for the recorded reason.

Raising a floor drops devices that cannot run the minimum OS version. The audience cost is
bounded:

- iOS 15.0 is the Flutter 3.47 toolchain minimum, so no iOS device is dropped for a Herdr
  design choice. Nothing the app needs between iOS 15 and iOS 26 costs a version branch.
- Android 13 (API 33) adoption: `unverified — confirm first`. Check the official Android
  Distribution Dashboard at `https://developer.android.com/about/dashboards`.

- R-23-054: The Apple App Store product page MUST show "Requires iOS 15.0 or later." The
  deployment target in the Xcode project sets the `MinimumOSVersion` key, and the App Store
  reads that key to display the "Requires" line. Source:
  `https://developer.apple.com/documentation/bundleresources/information-property-list/minimumosversion`.
- R-23-055: The Google Play store listing MUST filter device eligibility by `minSdk 33`. A
  device below API 33 cannot see or install the app. A device model with variants on both
  sides of the floor shows the app only to the variants at API 33 or above. Source:
  `https://support.google.com/googleplay/android-developer/answer/7353455`.
- R-23-056: The app MUST target `targetSdk 36` (Android 16). Google Play requires new apps
  and app updates to target API 36 or higher from August 31, 2026. An extension to November
  1, 2026 is available on request. Source:
  `https://support.google.com/googleplay/android-developer/answer/11926878`.
- R-23-057: iOS builds submitted to App Store Connect MUST be built with the iOS 26 SDK or
  later, from April 28, 2026. This is an SDK-build requirement, not a deployment-target
  floor: the app is built with the iOS 26 SDK and deploys to iOS 15.0. Source:
  `https://developer.apple.com/news/?id=ueeok6yw`.

### Rule: Store icon

The brand art, the placement constants and the export rules live in `docs/32-design-language.md`
`R-32-410` through `R-32-423`. These rules cover submission only.

- R-23-050: The Apple App Store icon MUST be the committed
  `assets/icon/export/ios/AppIcon.appiconset/Icon-1024.png`: 1024 x 1024, sRGB, flattened, **no alpha
  channel**, full bleed, square corners. Apple applies its own mask and rejects an icon that carries
  an alpha channel, per `R-32-417`.
- R-23-051: The Google Play store icon MUST be the committed
  `assets/icon/export/store/play-store-512.png`: 512 x 512, 32-bit PNG with alpha, per `R-32-419`.
- R-23-052: Neither store icon may be redrawn, recoloured or re-cropped at submission time. A change
  MUST be made to the masters in `assets/icon/src/` and every export regenerated, per `R-32-422`.
- R-23-053: The submitter MUST verify before upload that the iOS icon carries no alpha channel and
  that both files match the committed exports byte for byte.

## Licence and attribution

The project licence is Apache-2.0, per `R-03-020`. Section 4(d) of the Apache License requires
attribution notices to be carried with the distribution.

### Store listing

Neither the Apple App Store nor Google Play has a store-listing field for an open-source licence
type. The App Store provides an optional custom EULA field; if it is not filled, the standard Apple
EULA applies. Google Play has no equivalent field.

`unverified — confirm first`: whether Apple requires the licence to be stated in the description or
the custom EULA field for an Apache-2.0 project. Source:
`https://developer.apple.com/help/app-store-connect/manage-app-information/provide-a-custom-license-agreement/`.

- R-23-060: The in-app About screen at `/settings/about` (per `docs/31-mockups/19-about.md`) MUST
  carry the licence list and attribution notices. This satisfies the Apache-2.0 section 4(d)
  obligation to carry attribution in the distribution. The store listing is not the only vehicle for
  this obligation.
- R-23-062: The store listing description SHOULD state the project licence (Apache-2.0) for
  transparency, but the store listing is not required to satisfy the section 4(d) attribution
  obligation.

## Age rating

### Apple App Store

The app renders a developer's own terminal. It does not generate, distribute or amplify content. The
age rating questionnaire in App Store Connect receives these answers:

| Content descriptor | Answer |
| --- | --- |
| Unrestricted Web Access | None |
| User-Generated Content | None (no distribution to other users) |
| Social Media | None (no social feed) |
| Messaging and Chat | None (no communication feature) |
| Advertising | None |
| Profanity or Crude Humor | None |
| Horror / Fear Themes | None |
| Alcohol, Tobacco, or Drug Use or References | None |
| Medical or Treatment Information | None |
| Health or Wellness Topics | None |
| Mature or Suggestive Themes | None |
| Sexual Content or Nudity | None |
| Graphic Sexual Content and Nudity | None |
| Cartoon or Fantasy Violence | None |
| Realistic Violence | None |
| Prolonged Graphic or Sadistic Realistic Violence | None |
| Guns or Other Weapons | None |
| Gambling | None |
| Simulated Gambling | None |
| Contests | None |
| Loot Boxes | None |

The resulting rating is **4+**. The app contains no objectionable material. A terminal may display any
text the developer's own tools produce, but that content is not distributed, not amplified, and not
visible to other users. No content descriptor in the Apple questionnaire matches a personal,
single-user remote terminal.

### Google Play IARC

The IARC questionnaire answers are equivalent: no violence, no sexual content, no language, no
substances, no gambling, no in-app purchases, no user-generated content distributed to others. The
regional ratings are **ESRB Everyone**, **PEGI 3**, **CLASSIND L**, and equivalent minimum-age ratings
in every region.

- R-23-007: The Apple App Store age rating MUST be 4+.
- R-23-008: The Google Play IARC answers MUST reflect no objectionable content, no distributed
  user-generated content, no communication between users, no advertising, and no in-app purchases.

Sources:

- `https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/`
- `https://support.google.com/googleplay/android-developer/answer/9898843`

## Store copy

### Subtitle (Apple App Store only)

> Remote terminal for your coding agents.

### Short description (Google Play only)

> Read and type in your coding agent terminals from your phone. Pair once with a six-word QR code.
> Your terminal, your relay, your keys. No analytics, no ads.

### Full description

> **Herdr Remote** lets a developer watch and control a coding agent's terminal from an Android or
> iOS phone. Pair once by scanning a QR code with six random words, then read the terminal exactly as
> it appears on the workstation and type a reply.
>
> **Your terminal, your relay.** Herdr Remote connects to a relay that you set up. No relay is built
> in, and no relay is shared with anyone else. The relay forwards encrypted frames and stores nothing.
> The relay operator cannot read your terminal content, your keystrokes or your pairing phrase.
>
> **The phone is a full terminal.** Herdr Remote paints your terminal with a real VT emulator.
> Colours, cursor, and text layout match the workstation exactly. You can scroll, zoom, and read
> every pane in every tab. A dedicated key row gives you Esc, Ctrl, Tab and arrow keys. You can
> compose a prompt for a coding agent or type a raw command.
>
> **Notifications while the app is running.** When an agent finishes or gets blocked on the connected
> computer, you get a local notification on your phone. Tap it to jump to that pane. Herdr Remote
> does not use push notifications. If the app is not running, you will see the agent's status the
> next time you open it.
>
> **Security that the relay cannot break.** The Host and the Device run an end-to-end Noise
> handshake, first with a six-word Diceware phrase and then with pinned static keys. The relay
> forwards opaque frames. It holds no keys and cannot decrypt a payload.
>
> **One phone at a time.** Your Host accepts one active Device. A second phone sees "Host in use on
> another phone." You can pair more than one Device with one Host, and you can revoke a Device from
> the Host at any time.
>
> **One computer at a time.** You can pair the app with every computer you own. The app connects to
> one at a time. Alerts come from the computer you are connected to. If an agent finishes on another
> computer, you see it when you connect to that computer.
>
> **Free, no ads, no analytics.** Herdr Remote collects nothing. It sends nothing to a server you do
> not operate. There are no ad SDKs, no crash-reporting SDKs, and no analytics frameworks.
>
> **You need three things to get started.** A workstation running Herdr with the `herdr-relay`
> plugin installed, a relay (`herdr-relay-hub`) on a public Linux server with a domain name, and this
> app. The plugin shows a QR code. Scan it and you are connected.

### Keywords

Keywords submitted to the Apple App Store keyword field (100 characters maximum):

`herdr,terminal,remote,coding,agent,developer,ai,ssh,cli,console,devtools,pairing,workspace`

Google Play uses the full description for indexing and has no separate keyword field.

- R-23-009: The full description MUST state that the user supplies their own relay and that no relay
  is built in.
- R-23-010: The full description MUST state that the relay operator cannot read the terminal.
- R-23-011: The full description MUST state that notifications are local only while the app is
  running. It MUST NOT claim push notification support.
- R-23-012: The full description MUST state that the app collects no analytics and contains no
  advertisements.
- R-23-013: The full description MUST be clear to a developer who has never heard of Herdr. It MUST
  explain what Herdr is and what a coding agent is in the first three sentences.

- R-23-058: The full description MUST state that the app saves every paired computer and connects to
  one at a time, per `R-03-043`.
- R-23-059: The full description MUST state that alerts arrive only from the connected computer, per
  `R-03-045`.

## Privacy

### Data collected

The app collects no user data. It sends nothing to a server the user does not operate. There are no
analytics SDKs, no crash-reporting SDKs, no advertising SDKs and no telemetry frameworks. Terminal
content, keystrokes, pairing phrases, routing handles, static keys and device identifiers stay on the
device or travel end-to-end encrypted through the user's own relay.

### What the relay operator can see

The relay (`herdr-relay-hub`) forwards encrypted frames between the Host plugin and the app. The
relay operator's observable surface is:

- Connection metadata: source IP addresses, connection times, connection durations.
- Frame metadata: frame sizes, frame counts, message rates.
- TLS handshake metadata: the SNI hostname, the negotiated cipher suite.
- The routing handle (a 22-character opaque identifier that routes the two streams to one another).
- The `/healthz` and `/metrics` endpoints.

The relay operator cannot see terminal content, keystrokes, pairing phrases, Noise static keys,
device identifiers, host identifiers, or the content of any application message.

### Apple App Store privacy questionnaire

| Question | Answer |
| --- | --- |
| Does your app collect any data? | No. The app collects no data types listed in the Apple privacy questionnaire. |
| Data Used to Track You | None. The app performs no tracking. |
| Data Linked to You | None. No user data is collected. |
| Data Not Linked to You | None. No user data is collected. |
| Privacy Policy URL | A public URL to the privacy policy page. Required. |

The privacy label on the App Store product page shows **"No Data Collected"** and the text "This
developer does not collect any data from this app."

### Google Play Data safety form

| Section | Answer |
| --- | --- |
| Does your app collect or share any of the required user data types? | No |
| Data collected | None of the 14 data categories |
| Data shared | None |
| Encryption in transit | The form is skipped when "No" is selected. The app encrypts all protocol traffic end-to-end within the Noise channel; the relay transport uses WSS. |
| Data deletion | The app stores no user data on a server. The user can delete all local state by uninstalling the app. |
| Privacy Policy URL | A public URL to the privacy policy page. Required. |
| Committed to follow the Families Policy | No. The app is not directed at children. |

### Privacy policy page

- R-23-014: The project MUST maintain a public privacy policy page reachable at a stable HTTPS URL.
- R-23-015: The privacy policy page MUST state that the app collects no user data, sends nothing to
  a
  server the developer operates, and uses end-to-end encryption through the user's own relay.
- R-23-016: The privacy policy page MUST state what the relay operator can observe: connection
  metadata, frame sizes, timing, source IP address, and the routing handle.
- R-23-017: The privacy policy page MUST state that the relay operator cannot read terminal content
  or keystrokes.
- R-23-018: The privacy policy page MUST state that notifications are local only, that they arrive
  only from the connected computer (per `R-03-045`), and that no push notification infrastructure
  exists.
- R-23-019: The privacy policy page MUST state that the app contains no advertising and no analytics.

### Support page

- R-23-020: The project MUST maintain a public support page reachable at a stable HTTPS URL.
- R-23-021: The support page MUST state that the app requires iOS 15.0 or later and Android 13
  (API 33) or later. These floors are set in `docs/20-mobile-framework.md` per `R-20-026`.
- R-23-022: The support page MUST state that the user must supply their own relay and link to
  `docs/14-relay-deployment.md`.
- R-23-023: The support page MUST link to `SECURITY.md` for vulnerability reporting.

Sources: `https://developer.apple.com/app-store/app-privacy-details/`, `https://support.google.com/googleplay/android-developer/answer/10787469`.

## Encryption export

### Apple App Store

The app uses the Noise protocol framework for end-to-end encryption. This is standard cryptography
that is not Apple OS built-in, so it requires an export compliance determination. The app answers:

- R-23-024: The app MUST declare in App Store Connect that it uses non-OS encryption. The answer to
  "Does your app use encryption?" is **Yes**.
- R-23-025: The app MUST declare that the encryption is limited to the categories listed in the
  questionnaire: the app encrypts its own protocol traffic between Host and Device.
- R-23-026: The ITSAppUsesNonExemptEncryption key in `Info.plist` MUST be `NO` if the
  self-classification applies; `YES` if a separate export documentation upload is required. The exact
  answer depends on the App Store Connect questionnaire verdict.
  `unverified — confirm first`: the questionnaire path for a Noise-based custom protocol. Source:
  `https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations`.

### Google Play

Google Play requires the developer to determine the app's US export classification. The app uses
standard encryption (Noise `XXpsk0` and `KK` with ChaChaPoly) for its own protocol traffic.

- R-23-027: The developer MUST self-classify the app under the US Commerce Department encryption
  export regulations. The app falls under "publicly available" or "mass market" encryption software.
- R-23-028: The developer MUST verify the classification against the current BIS encryption guidance
  at `https://www.bis.doc.gov/index.php/policy-guidance/encryption` before the first release.
  `unverified — confirm first`.

Sources:

- `https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance`
- `https://support.google.com/googleplay/android-developer/answer/113770`

## Screenshot matrix

### Apple App Store

Screenshots are uploaded for the largest display size; App Store Connect scales them for smaller
sizes. The required set for an iPhone-only app:

| Display | Portrait size | Count |
| --- | --- | --- |
| 6.9-inch | 1320 × 2868 pixels | up to 10, at least 4 recommended |
| 6.5-inch | 1284 × 2778 pixels or 1242 × 2688 pixels | required if 6.9-inch not provided |

`unverified — confirm first`: the exact count of required device families and whether 6.9-inch
supersedes 6.5-inch entirely for new apps submitted after the iPhone Air / 17 Pro Max launch. Source:
`https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications`.

The app does not run on iPad, Apple Watch, Apple TV, Mac, or Apple Vision Pro. Screenshots for those
device families are not required.

### Google Play

| Device type | Recommended size | Count |
| --- | --- | --- |
| Phone (portrait) | 1080 × 1920 pixels | minimum 2, up to 8, at least 4 recommended |
| 10-inch tablet | 1600 × 2560 pixels | minimum 1, up to 8 |

Files: JPEG or 24-bit PNG, no alpha channel, under 8 MB each. Aspect ratio between 16:9 and 9:16.

`unverified — confirm first`: whether the tablet screenshot requirement applies to a phone-only
manifest. Source: `https://support.google.com/googleplay/android-developer/answer/10787469`.

### Screenshot to mockup mapping

Each screenshot depicts one screen from the mockups in `docs/31-mockups/`. The screenshot shows the
real rendered UI, not the ASCII wireframe. The mapping follows the user story order.

| Screenshot | Mockup | What it shows |
| --- | --- | --- |
| 1 | `01-welcome.md` | "Welcome to Herdr Remote" with the "Pair a Host" and "Scan QR Code" buttons |
| 2 | `02-pair-scan.md` | QR scanning viewfinder over a QR code, with the "Enter manually" link |
| 3 | `03-pair-code.md` | Manual pairing screen: origin field filled with `https://relay.example.com`, six word fields, and the handle field |
| 4 | `05-host-list.md` | Host list with one paired Host, showing the host name, connection status, and the three-dot menu per Host |
| 5 | `06-agent-list.md` | Agent list for one Host: three agents, one `done`, one `working`, one `blocked`, with the agent kind and pane title |
| 6 | `07-notifications.md` | Notifications list for one Host: three agent status changes, two unread with the leading bar, one read, with the space, tab and pane breadcrumb |
| 7 | `08-terminal.md` | Terminal view: ANSI-rendered pane content with a coloured prompt, scroll indicator, and the pane title bar |
| 8 | `09-key-row.md` | Terminal with the key row visible: Esc, Ctrl, Tab, ↑, ↓, ←, →, /, and the agent prompt button |
| 9 | `10-pane-actions.md` | Pane actions sheet: split, zoom, close, rename, resize, input mode, agent prompt |
| 10 | `12-notifications.md` | Lock screen or notification centre showing one local notification: "agent done — claude, w1:p2, auth.rs" |

- R-23-029: The screenshot set MUST show the pairing flow, the terminal, the agent list, the key
  row, the pane actions, and a local notification. The screenshots MUST NOT show simulated push
  notification UI.
- R-23-030: Screenshots MUST use the sample values in `docs/11-relay-protocol.md` §8. They MUST NOT
show a real terminal session, a real phrase or a real handle.

Sources:

- `https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications`
- `https://support.google.com/googleplay/android-developer/answer/10787469`

## Accounts and ownership

- R-23-031: A project owner MUST create and hold the Apple Developer account at
  `https://developer.apple.com/account/`. The account owner MUST enrol in the Apple Developer Program
  as an organisation.
- R-23-032: A project owner MUST create and hold the Google Play Console account at
  `https://play.google.com/console/`. The account MUST be a developer account with a verified
  organisation identity.
- R-23-033: The Apple Distribution signing certificate private key and the Google Play app signing
  key MUST be stored on a hardware security key or in a password-managed encrypted keystore. A key
  MUST NOT be committed to version control.
- R-23-034: A signing key MUST NOT be sent through a chat channel, email or any plaintext medium.
- R-23-035: Both store accounts MUST have at least two account holders with Admin role. At least one
  MUST be a role, not a named person, such as "project lead" or "release manager."

## Release process

### Store tracks

| Store | Public track | Beta channel |
| --- | --- | --- |
| Apple App Store | App Store (production) | TestFlight, external testers |
| Google Play | Production | Open testing or Closed testing |

- R-23-036: A public release MUST go through the beta channel first. The beta build MUST be tested by
  at least one external tester on each supported platform before promotion to production.
- R-23-037: A release MAY use staged rollout on Google Play. The staged rollout percentage, duration
  and halt conditions are at the release manager's discretion.

### Versioning

- R-23-038: The app version MUST follow semantic versioning: `MAJOR.MINOR.PATCH`.
- R-23-039: A `MAJOR` bump indicates a breaking change in the relay protocol version the app speaks.
- R-23-040: A `MINOR` bump indicates a new feature that does not change the protocol.
- R-23-041: A `PATCH` bump indicates a bug fix or a store-metadata change with no code change visible
  to the user.

### App version to relay protocol version mapping

- R-23-042: The app MUST embed the relay protocol version it speaks in a constant. The constant is the
  integer from `host_info.protocol` and `device_info.protocol`. The app MUST send that integer in
  `device_info`.
- R-23-043: The app `MAJOR` version MUST equal the relay protocol version integer when the protocol
  version increases by a breaking change. For example, app version `2.0.0` speaks protocol version
  `2`.
- R-23-044: When the app accepts a `protocol_mismatch` error from the Host, the app MUST display the
  error with the Host's protocol version and the app's protocol version, and offer to check for an
  app update.

### Relay protocol deprecation policy

- R-23-045: When a new relay protocol version N is released, the Host plugin and the app MUST both
  speak N. The previous version N-1 MUST remain supported by the relay for at least 12 months from
  the public release of N.
- R-23-046: When a Host speaks an older version V and the app speaks a newer version N, the Host sends
  `protocol_mismatch` as defined in R-11-050. The app displays the version gap and the Host's
  version, and recommends the user update the Host plugin. The app does not fall back to V.
- R-23-047: When the app speaks an older version V and the Host speaks a newer version N, the Host
  sends `protocol_mismatch` as defined in R-11-050. The app displays the version gap and prompts the
  user to update the app from the store. The Host does not fall back to V.
- R-23-048: The relay MUST accept registrations for any protocol version it supports. It MUST NOT
  inspect `host_info.protocol` or `device_info.protocol` to reject a connection. Protocol version
  negotiation is between Host and Device only.

## Public security reporting

- R-23-049: The app store listing pages and the support page MUST link to `SECURITY.md`.

## Sources

- Apple App Store Connect age ratings:
  `https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/`
  — proved the content descriptor list, rating tiers, and the rule that an unrated app cannot be
  published.
- Apple App Store categories:
  `https://developer.apple.com/app-store/categories/`
  — proved the available categories and their definitions.
- Apple app privacy details:
  `https://developer.apple.com/app-store/app-privacy-details/`
  — proved the data type list, the data-use categories, the tracking definition, and the optional
  disclosure criteria.
- Apple screenshot specifications:
  `https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications`
  — proved the required device families, display sizes and pixel dimensions.
- Apple export compliance:
  `https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance`
  — proved the encryption questionnaire requirement and the exemption criteria.
  `https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations`
  — proved the self-classification path and the ITSAppUsesNonExemptEncryption key.

- Apple custom licence agreement:
  `https://developer.apple.com/help/app-store-connect/manage-app-information/provide-a-custom-license-agreement/`
  — proved that the custom EULA field is optional and that the standard Apple EULA applies when it
  is not filled.
- Google Play content ratings:
  `https://support.google.com/googleplay/android-developer/answer/9898843`
  — proved the IARC questionnaire requirement.
- Google Play Data safety:
  `https://support.google.com/googleplay/android-developer/answer/10787469`
  — proved the data categories, the per-category question structure, the ephemeral-processing rule,
  and the end-to-end encryption exemption.
- Google Play export compliance:
  `https://support.google.com/googleplay/android-developer/answer/113770`
  — proved the self-classification requirement and the BIS guidance link.
- Google Play categories:
  `https://support.google.com/googleplay/android-developer/answer/9859673`
  — proved the available app categories.
- Apple MinimumOSVersion:
  `https://developer.apple.com/documentation/bundleresources/information-property-list/minimumosversion`
  — proved that the deployment target sets the `MinimumOSVersion` key and the App Store uses it to
  show the "Requires" line on the product page.
- Apple SDK minimum requirements:
  `https://developer.apple.com/news/?id=ueeok6yw`
  — proved that iOS and iPadOS apps must be built with the iOS 26 SDK or later from April 28,
  2026, and that this is independent of the deployment target.
- Apple iOS and iPadOS usage:
  `https://developer.apple.com/support/app-store/`
  — the official source for iOS version adoption share. The iOS 15.0 floor is the Flutter 3.47
  toolchain minimum, not an adoption-driven cut, so no adoption figure drives the floor decision.
- Google Play device catalog and filtering:
  `https://support.google.com/googleplay/android-developer/answer/7353455`
  — proved that `minSdk` filters device eligibility and that a device below the floor cannot see or
  install the app.
- Google Play target API level requirements:
  `https://support.google.com/googleplay/android-developer/answer/11926878`
  — proved that new apps and updates must target API 36 or higher from August 31, 2026, with an
  extension to November 1, 2026 on request.
- Android Distribution Dashboard:
  `https://developer.android.com/about/dashboards`
  — the official source for Android version adoption share. `unverified — confirm first`: the
  current API 33 figure must be read from this page at submission time.

## Open questions

None. Every store-government requirement that the official pages answer is stated as a rule. Three
items require confirmation at submission time and are marked `unverified — confirm first`.
