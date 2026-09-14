# ADR-007: The Device static key stays software Curve25519; the hardware-backed P-256 spike is blocked, not resolved

## Status

Accepted.

## Date

2026-08-28

## Context

`docs/13-security-pairing.md` R-13-043 requires the Device static keypair for `Noise_XXpsk0`/`Noise_KK`
to be Curve25519, stored as biometric-gated Keychain (iOS) or Keystore (Android) data. R-13-044 already
records why the key cannot live inside the iOS Secure Enclave for version 1: the Secure Enclave signs
and performs ECDH only with the secp256r1 (NIST P-256) curve, never Curve25519. R-13-045 names the
open question this ADR exists to answer: could a future version replace the software Curve25519 key
with a hardware-backed P-256 key stored inside the Secure Enclave (iOS) and StrongBox (Android)?

`docs/90-implementation-plan.md` Phase 23 assigns this question one task: generate a P-256 key inside
the real iOS Secure Enclave and inside real Android StrongBox hardware, then attempt to complete
`Noise_KK` with each key, and record what actually happened.

Only a real device answers this. The Secure Enclave and StrongBox are physical hardware security
modules; there is no software emulator, simulator, or desktop substitute that exercises the same
key-non-extractability guarantee the spike exists to test — an emulator's "Secure Enclave" or
"StrongBox" is a software stand-in with different (usually weaker) guarantees, so a result obtained
from one would not answer the real question and could not be reported as a hardware-key spike result
without misrepresenting it.

This workstation is Windows, with no iPhone, no Android device with StrongBox, and no other path to
real Secure Enclave or StrongBox hardware. `docs/90-implementation-plan.md` Phase 4's own SPIKE C
section already recorded the identical shape of gap for a different spike (public relay, real phone,
cellular data) as Blocked-work item B14: the live-Herdr half closed and was verified locally, and the
remaining step needed hardware this environment does not have. This ADR and the paired Blocked-work
entry (B18) follow that same precedent: do not fabricate or simulate a hardware result, do not stall
the plan on the gap, and record the exact hardware, the exact question, and the default that already
governs version 1 in the meantime.

## Decision

The hardware-key spike did not run. No P-256 key was generated inside a real iOS Secure Enclave or a
real Android StrongBox module during this review, and no `Noise_KK` attempt against such a key was
made. `docs/90-implementation-plan.md` Phase 23's hardware-key-spike checkbox stays unticked; the gap
is recorded as Blocked-work item B18, per R-90-009.

Version 1 keeps the R-13-043/R-13-044/R-13-045 default unchanged: the Device generates a Curve25519
static keypair in software on first launch. The private key is stored as Keychain data (iOS,
`kSecAttrAccessControl` biometry-gated) or Keystore data (Android,
`setUserAuthenticationRequired(true)`, backed by StrongBox when the device has it) — the storage
container may already use StrongBox or the Secure Enclave's data-protection class today; what remains
untested is only whether the *key itself*, not just its storage container, can live inside those
modules under Curve25519's replacement curve, P-256, and still complete `Noise_KK`.

## Consequences

Nothing in the shipped protocol or code changes. `Noise_XXpsk0` and `Noise_KK` continue to run
Curve25519 exactly as `crates/herdr-relay/src/noise.rs` and the Dart Device implementation already
build them (`docs/90-implementation-plan.md` Phase 4, `WP-10-b`). No `docs/13-security-pairing.md`
rule changes: R-13-043 through R-13-045 already state the version-1 rule and already name this ADR as
the task that closes the open question, so no other document carries a stale or premature claim.

The unresolved half of the question — can a real Secure Enclave key and a real StrongBox key each
complete `Noise_KK`, and is the migration worth the `Noise_XX`/`Noise_KK` pattern change a mixed
Curve25519-Host/P-256-Device world would need — stays open until the hardware in Blocked-work item B18
is available. Revisit this ADR when at least one of these becomes true:

1. A real iPhone with Secure Enclave and a real Android device with StrongBox are both available to
   the reviewer, so the spike in the Phase 23 checkbox can run as specified.
2. A future release of the Device's Noise or platform-crypto library adds first-class P-256 Noise
   support (`Noise_XXpsk0_P256_...`/`Noise_KK_P256_...`) verified against `crates/herdr-relay/src/noise.rs`'s
   own vector-based tests, removing the need for a hand-verified spike.
3. A security review finds a concrete, exploitable weakness in the current software-Curve25519 plus
   biometric-gated-storage design that only a hardware-bound private key would close.
