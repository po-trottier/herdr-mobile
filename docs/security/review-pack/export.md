# Encryption export declaration answers

Phase 24 checkbox (`docs/90-implementation-plan.md`): "Complete both encryption export
declarations, including `ITSAppUsesNonExemptEncryption` in `app/ios/Runner/Info.plist`, and file
the answers at `docs/security/review-pack/export.md`" (R-23-024, R-23-027).

The answers below are copied verbatim from `docs/23-public-release.md` §Encryption export, the
owning document (R-90-008). This file records them for the review pack; it does not re-derive or
restate the rule text, only files the determined answer alongside its rule id.

## Apple App Store

The app uses the Noise protocol framework for end-to-end encryption. This is standard cryptography
that is not Apple OS built-in, so it requires an export compliance determination.

| Question | Answer | Rule |
| --- | --- | --- |
| Does your app use encryption? | **Yes** | R-23-024 |
| Encryption category | The app encrypts its own protocol traffic between Host and Device | R-23-025 |
| `ITSAppUsesNonExemptEncryption` (`app/ios/Runner/Info.plist`) | `NO` (`<false/>`) — set in `Info.plist` | R-23-026 |

`Info.plist` already carries `ITSAppUsesNonExemptEncryption` as `<false/>`, matching the "self-
classification applies" branch of R-23-026 and the `## 8. Blocked work` item B8 interim default
("yes, exempt" with the operating-system-cryptography exemption, per `docs/22-platform-
integration.md` R-22-045).

`unverified — confirm first` (R-23-026, carried from `docs/23-public-release.md`): the exact
App Store Connect questionnaire path for a Noise-based custom protocol. This must be confirmed
against the real questionnaire at submission time; tracked as `## 8. Blocked work` item B8.
Source: `https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations`.

## Google Play

Google Play requires the developer to determine the app's US export classification. The app uses
standard encryption (Noise `XXpsk0` and `KK` with ChaChaPoly) for its own protocol traffic.

| Question | Answer | Rule |
| --- | --- | --- |
| US export classification | "Publicly available" or "mass market" encryption software (self-classified) | R-23-027 |
| BIS guidance check | Not yet performed | R-23-028 |

`unverified — confirm first` (R-23-028, carried from `docs/23-public-release.md`): the
classification must be verified against the current BIS encryption guidance at
`https://www.bis.doc.gov/index.php/policy-guidance/encryption` before the first release; tracked
as `## 8. Blocked work` item B8.

## Status

The declaration answers above are determined and recorded. Entering them into the real App Store
Connect and Google Play Console forms still needs the real developer accounts
(`## 8. Blocked work` item B20) and remains blocked until then; the two `unverified — confirm
first` items above must also be confirmed against the live questionnaire and the live BIS guidance
page at submission time (item B8).

Sources:

- `https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance`
- `https://support.google.com/googleplay/android-developer/answer/113770`
