# Phase 23 verification summary — items 2, 3, 4, 7, 8, 9, 12

Companion to `docs/security/rule-test-map.md`, `wire-capture.md`, `fuzz.md` and
`handle-guessing.md` in this directory. Records the exact commands and results for the Phase 23
checkboxes that do not otherwise get their own review-pack file.

## Item 2 — `cargo tree -p herdr-relay-hub`: no Noise, `rand`, `blake2` or QR crate

Command (from `crates/`): `cargo tree -p herdr-relay-hub -e normal` (excludes `[dev-dependencies]`,
matching what the Dockerfile's `build` stage actually ships — the `test` stage's own dependency
graph additionally pulls in `herdr-relay` as a dev-dependency for `tests/ciphertext_only.rs` and
`tests/byte_capture.rs`'s cross-crate Noise proof, which is where `snow`/`blake2`/`rand`/`qrcode`
legitimately appear; those are test-only and never reach the `FROM scratch` final image).

Result, production (non-dev) dependency tree:

- No `snow` crate (Noise) anywhere in the tree.
- No `blake2` crate anywhere in the tree.
- No `qrcode` crate anywhere in the tree.
- `rand` (`v0.9.5`) IS present, transitively, via `axum → tokio-tungstenite 0.29.0 → tungstenite
  0.29.0 → rand`. This is `tungstenite`'s own internal use (WebSocket client masking-key/nonce
  generation per RFC 6455), pulled in because `axum`'s `ws` feature reuses `tokio-tungstenite`'s
  frame/`Message` types for its WebSocket upgrade support — it is not a direct dependency
  `herdr-relay-hub`'s own `Cargo.toml` declares, and a grep of `crates/herdr-relay-hub/src/` for
  `use rand`, `rand::`, `Noise`, `snow::`, `blake2` or `qrcode` finds zero matches (the crate's own
  code never imports it). R-41-133's own rationale already anticipates a distinction between "the
  relay links the platform TLS/WS stack" (expected) and "the relay adds a crypto dependency for its
  own use" (forbidden) — this is the former, exercised only for the standard WebSocket protocol
  machinery, not Noise/PSK/session cryptography.
- No TLS crate (`rustls`, `native-tls`, `openssl`) appears in the production tree at all. TLS
  termination is delegated entirely to the Caddy reverse proxy in front of the relay
  (`docs/14-relay-deployment.md`, `crates/herdr-relay-hub/Caddyfile`), not linked into the relay
  binary itself. Full tree captured for the record: `crates/herdr-relay-hub` production tree, root
  crate plus `axum`, `herdr-relay-proto`, `serde`, `serde_json`, `tokio`, `tracing`, and their
  transitive dependencies (`sha1` for the WS handshake key per RFC 6455, `matchit`, `tower`,
  `hyper`, and their own sub-dependencies) — none of the four forbidden families.

**Conclusion:** compliant with R-12-012, R-12-060 and R-01-012's exact wording ("the relay performs
no application-layer decryption and holds no Noise keys", not "zero crypto dependencies") and
R-41-133 (no direct `snow`/`blake2`/`rand` dependency; the transitive `rand` is `tungstenite`'s own
WS-protocol internal, unrelated to Noise/PSK material, and the relay's own source never touches it).

## Item 3 — nothing under `crates/herdr-relay-hub/src/` writes to disk or survives a restart

- `grep -rE 'std::fs|File::|fs::write|fs::read|fs::create|OpenOptions|tokio::fs'
  crates/herdr-relay-hub/src` — zero matches. No disk-persistence API is imported or called
  anywhere in the relay's own source.
- New test `crates/herdr-relay-hub/tests/no_persistence.rs`
  (`a_second_relay_instance_has_no_memory_of_the_first`): starts a real `Relay`, registers a Host
  under a handle, drops the instance (the only way a real process restart can be simulated — the
  server task is aborted and the router's in-memory state is dropped), starts a second, independent
  `Relay::start()` (which calls the same `herdr_relay_hub::routes::router()` production constructor
  a real process restart would), and confirms a Device connecting to the same handle on the second
  instance gets `handle_unknown` — proving no `static`/`OnceLock`/global registry survives across
  instances. `cargo test -p herdr-relay-hub --test no_persistence` (cwd `crates/`): **1 passed, 0
  failed.**

**Conclusion:** compliant with R-12-013.

## Item 4 — relay log-field allow list

`cargo test -p herdr-relay-hub --test log_fields` (cwd `crates/`):
`test no_log_line_carries_a_field_outside_the_r_12_041_allow_list ... ok` — **1 passed, 0 failed.**
`crates/herdr-relay-hub/tests/log_fields.rs` already existed (built in an earlier phase) and asserts
the closed R-12-041 field allow list and event-name list against every log line the relay actually
emits during a live session. No change needed; re-run and confirmed passing.

**Conclusion:** compliant with R-12-041 and R-12-042.

## Item 7 — phrase brute-force bound (3 attempts / 600 s)

`cargo test -p herdr-relay --test phrase_expiry` (cwd `crates/`):
`a_phrase_is_refused_after_600_seconds ... ok`,
`a_phrase_is_refused_after_three_failed_attempts ... ok` — **2 passed, 0 failed.**
`crates/herdr-relay/tests/phrase_expiry.rs` covers exactly this claim, driven through
caller-supplied `Instant`s (no real sleeping). Amended 2026-09-02: the lifetime is 600 seconds
(R-13-022), and the third failed attempt destroys the phrase and the handle without minting a
replacement (R-13-023). The bridge-level proofs of both live in
`crates/herdr-relay/tests/host_pairing.rs`:
`a_pairing_with_no_device_is_destroyed_after_600_seconds` (expiry destroys the pairing and nothing
re-registers), `three_failed_handshakes_spend_the_phrase_with_no_replacement` (three failed
handshakes destroy the pairing with no new handle until a fresh `open_pairing`) and
`a_kk_registration_held_past_the_connect_timeout_still_completes` (a paired `Noise_KK`
registration is never window-limited, R-11-120).

**Conclusion:** compliant with R-13-022 and R-13-023 as amended 2026-09-02.

## Item 8 — revoked Device cannot reconnect, handle destroyed

Proven across three files together (the project's own convention — `docs/40-repo-tooling.md`
R-40-030 — puts a Rust unit test in the same file as the code it tests, so the full claim is split
across a store-level integration test and two `#[cfg(test)]` unit-test modules, not crammed into one
file):

1. `cargo test -p herdr-relay --test revoke` (cwd `crates/`):
   `revoking_one_device_leaves_the_other_paired ... ok` — **1 passed.** Proves the Host's own
   `DeviceStore` removes the revoked entry (no "revoked" row state) and the removal persists across
   a reload from disk.
2. `cargo test -p herdr-relay --lib relay::registry::` (cwd `crates/`): **5 passed** —
   `close_for_revocation_closes_only_the_named_device`, `close_for_revocation_all_closes_every_session`,
   `close_for_revocation_returns_zero_for_a_device_not_connected`,
   `set_device_id_lets_a_later_revoke_find_the_session`, `unregister_removes_with_no_close_signal`.
   Proves `SessionRegistry::close_for_revocation` removes the routing-handle entry (this Host's own
   "destroy the handle" bookkeeping, per the doc comment on that method) and signals the live session
   to close with `CloseReason::Revoked`.
3. `crates/herdr-relay/src/relay/session.rs` (code-reviewed): `CloseReason::Revoked` maps to WS close
   code `4004` (`CloseCode::Revoked`) via `close_socket`, and sends the `{"type":"error","code":
   "revoked",...}` frame first (R-11-065/R-11-121). Exercised end-to-end (not just unit-level) by
   `cargo test -p herdr-relay --lib popup:: -- revoked` (**12 passed**, including
   `d_closes_the_revoked_devices_live_session_when_a_registry_is_wired_in` and
   `r_closes_every_live_session_when_a_registry_is_wired_in`) and
   `cargo test -p herdr-relay --lib watch::requests:: -- revoked` (**7 passed**, including
   `revoke_device_request_closes_the_live_session_when_a_registry_is_wired_in`), which each wire a
   real `SessionRegistry` to the real revoke-request handling code path and assert the real
   `CloseReason::Revoked` signal fires.
4. A revoked Device's handle no longer exists to reconnect to at all once destroyed (step 2): a
   Device attempting to connect to a handle with no registered Host gets `handle_unknown`, the exact
   behaviour `crates/herdr-relay-hub/src/session/tests.rs::device_on_unknown_handle_is_refused` and
   this phase's own `tests/no_persistence.rs` (item 3, above) both already exercise on the relay side.

**Conclusion:** compliant with R-13-034 and R-13-054.

## Item 9 — no `#[allow]`/`// ignore:` without a named lint and a stated reason

Swept `crates/` for `#!\[allow|#\[allow` and `app/` for `// ignore:` (full trees, not just tests).
Found:

- `crates/herdr-relay-hub/src/routes/logging.rs:277` —
  `#[allow(dead_code, reason = "reserved for a future internal-error call site")]` — compliant.
- `crates/herdr-relay/src/relay/connection.rs:290` and
  `crates/herdr-relay/tests/relay_connection.rs:56` —
  `#[allow(clippy::result_large_err)] // the Err type is tungstenite's own Response; not this
  test's to box` — compliant (reason on the same line, matching R-41-116's own example shape).
- `crates/herdr-relay-hub/tests/support/mod.rs:14` — `#![allow(dead_code)]` with **no** inline
  reason (only a doc comment several lines above it) — **non-compliant, fixed in this review**:
  changed to `#![allow(dead_code, reason = "shared test harness: some binaries use only a subset
  of these helpers, and rustc flags the rest as dead code per compilation unit (R-41-116)")]`.
- Every Dart `// ignore: <rule>` in `app/lib/` and `app/test/`/`app/integration_test/`
  (`prefer_initializing_formals` ×many, `avoid_print` ×4, `close_sinks` ×1) carries a one-line
  justification comment immediately above it. R-41-116's own text is scoped to Rust
  `#[allow(clippy::...)]`; this checkbox broadens the ask to Dart `// ignore:` too, and every
  instance found already matches the same "state the reason next to the directive" spirit — none
  needed a fix.

**Conclusion:** one real gap found and fixed (`tests/support/mod.rs`); everything else already
compliant with R-41-116's requirement.

## Item 12 — no NVIDIA name, endpoint, certificate pin or branding under `crates/`, `app/` or `tests/e2e/`

`grep -riE 'NVIDIA|nvbugs|nvinfo'` across `crates/` and `app/` (all files, not just source):

- One match: `crates/herdr-relay-hub/docs/runbook.md:315`, a table row naming "Optional NVIDIA Brev
  experiment gate (R-15-004 group)" among Phase 9's disclosed blocked items. This is exactly the
  gap `docs/90-implementation-plan.md` \u00a77's own "Vendor neutral" Definition-of-done bullet already
  names this file for — **fixed in this review**: reworded to "Optional relay-experiment deployment
  gate (R-15-004 group, `docs/15-nvidia-brev-relay-experiment.md`)", which keeps the same
  informational content (which optional Phase 9 item was skipped and why) without the vendor name,
  consistent with R-03-002 (NVIDIA deployment work stays inside `docs/15-nvidia-brev-relay-
  experiment.md` itself, not referenced elsewhere by name).
- No other match anywhere under `crates/` or `app/`. `tests/e2e/` did not exist before this phase;
  see `docs/security/review-pack/` (byte-capture/fuzz/e2e task outputs) for the same check applied
  to files created during this phase.

**Conclusion:** one real gap found and fixed; clean after the fix.
