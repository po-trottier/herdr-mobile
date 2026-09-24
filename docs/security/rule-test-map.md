# Rule-to-test map

Phase 23 item (`docs/90-implementation-plan.md` §6 Phase 23, R-40-038, R-40-039): names, for
every live rule id `R-nn-nnn` defined in `docs/`, the automated test or recorded verification
that proves it, or discloses that none was found in this pass.

## Methodology

This map was first built mechanically (2026-08-27), then worked systematically rule-by-rule
against the 783 rows that pass left in category E (2026-08-28 completion pass): 21 parallel
research passes re-examined every unresolved rule's full definition against real test files,
`docs/90-implementation-plan.md` checkboxes, and this repository's standing gates; genuine false
negatives got a citation added to the test that already proved them; a further 25 parallel passes
wrote real new small tests for genuine, previously-untested application/protocol behavior. Four
increasingly indirect evidence sources are checked, in this priority order, and the first one
found for a given rule id is what the table below cites:

- **A — Automated test.** The exact string `R-nn-nnn` appears in a Rust integration test file
  (`crates/**/tests/**/*.rs`), inside a Rust `#[cfg(test)] mod tests` block in a source file, in
  a Dart file under `app/test/` or `app/integration_test/`, or in a POSIX shell / PowerShell test
  script under `crates/**/tests/` (this repository's Host-plugin shim tests, e.g.
  `crates/herdr-relay/tests/posix/test-ensure-service.sh`,
  `crates/herdr-relay/tests/windows/test-plugin-root.ps1`). Highest confidence: the citing file
  is a real, currently-passing test.
- **B — Recorded verification.** The rule id appears inside a checked (`- [x]`) checkbox's own
  body in `docs/90-implementation-plan.md`, which by this project's own convention (R-90-005)
  states the exact command and evidence that closed it. Cited as a line range in that file.
- **C — Sibling test file, not literally cited.** The rule id appears only in a non-test source
  file (`crates/**/src/**` or `app/lib/**`), but that file's sibling test file exists per this
  repository's own naming convention (`docs/40-repo-tooling.md` §3.3: `app/lib/<path>/<name>.dart`
  → `app/test/<path>/<name>_test.dart`; a Rust `src/<mod>.rs` → `tests/<mod>.rs`). Medium
  confidence: the module is under test, but this pass did not confirm the specific rule's
  behaviour is what the sibling test asserts — spot-check recommended before relying on it.
- **D — Gate-enforced.** The rule's own text names a formatting/lint/documentation convention
  (`rustfmt`, `clippy`, `dart analyze`, `markdownlint`, a `docs/40-repo-tooling.md` §8 audit
  command) that mechanically fails a build or a CI job if the rule is violated. The 2026-08-28
  pass verified each D citation against the real, current `.github/workflows/ci.yml` and
  `docs/40-repo-tooling.md` §8 scripts rather than trusting a keyword match alone — `flutter
  test`/`flutter analyze`/`dart analyze` are configured but NOT run as a standing CI gate today,
  so a rule enforced only by an unconfigured Dart analyzer lint stays in category E, disclosed
  with that fact.
- **E — Unresolved.** None of the above found. Still an **upper bound** on the real gap, not a
  precise count: a further false negative can exist (a test that proves the behaviour without
  literally quoting the rule id) even after this pass. Every remaining row in category E carries,
  in its Proof column, either the concrete reason no test can close it (a process/planning rule,
  a store-console/external-account fact, a not-yet-implemented feature) or the specific effort
  estimate for the test that would close it, so a future pass does not have to re-derive that
  triage from scratch.

**Totals: 1590 live rule ids. A=493, B=331, C=120, D=38 (982 with some form of evidence),
E=608 (unresolved).**

`docs/90-implementation-plan.md` Phase 23's `Done when` line reads: "`docs/security/rule-test-map.md`
names a test for every rule id in `docs/`." **This is still not met**, but the gap shrank from
783 to 608 rows in the 2026-08-28 pass: 179 rules were resolved (165 to A, 2 to B, 12 to D — see
the completion report for the exact breakdown of false-negative-citation-fixes vs. genuine new
tests written). The remaining 608 category-E rows split into two kinds, both disclosed per-row
rather than papered over: rules that describe a real, closeable application/protocol behaviour
with a specific test-and-effort estimate recorded in the Proof column, and rules that are
process/planning/external-account/store-listing facts with no automated test possible in this
repository at all (also stated per-row). See the Phase 23 completion report for the honest final
status and the full per-category accounting.

## Per-document tables

Sorted by document, then by rule id. `Cat.` is the evidence category (A/B/C/D/E) above.

### `docs/01-architecture.md` (9 rules — A=4, B=4, C=1)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-01-005` | B | docs/90-implementation-plan.md:1828-1830 (checked checkbox) |
| `R-01-006` | A | crates/herdr-relay/tests/reject_unknown.rs:2 |
| `R-01-007` | A | crates/herdr-relay/tests/one_pane.rs:2 |
| `R-01-008` | A | app/test/screens/connection_screen_test.dart:6 |
| `R-01-009` | B | docs/90-implementation-plan.md:2837-2839 (checked checkbox) |
| `R-01-010` | B | docs/90-implementation-plan.md:2430-2432 (checked checkbox) |
| `R-01-011` | B | docs/90-implementation-plan.md:3428-3429 (checked checkbox) |
| `R-01-012` | A | crates/herdr-relay-hub/tests/ciphertext_only.rs:8,105 |
| `R-01-013` | C | app/test/services/pairing_test.dart (sibling test of app/lib/services/pairing.dart; rule id not literally cited) |

### `docs/02-herdr-probe-results.md` (25 rules — A=11, B=1, E=13)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-02-001` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-02-002` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-02-003` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-02-004` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-02-005` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-02-006` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-02-007` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-02-008` | A | app/test/models/ping_response_test.dart:2 |
| `R-02-009` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-02-010` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-02-011` | A | crates/herdr-relay/tests/revision_gate.rs:2 |
| `R-02-012` | A | app/test/services/terminal_test.dart:275 |
| `R-02-013` | A | crates/herdr-relay/tests/one_pane.rs:162 |
| `R-02-014` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-02-015` | A | app/integration_test/first_paint_test.dart:244 |
| `R-02-016` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-02-017` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-02-018` | A | app/integration_test/spike_render_test.dart:14 |
| `R-02-019` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-02-020` | A | crates/herdr-relay/src/watch/input.rs |
| `R-02-021` | A | crates/herdr-relay/src/watch/input.rs |
| `R-02-022` | A | crates/herdr-relay/src/watch/input.rs |
| `R-02-023` | A | crates/herdr-relay/src/watch/input.rs |
| `R-02-024` | B | docs/90-implementation-plan.md:3291-3299 (checked checkbox) |
| `R-02-025` | A | crates/herdr-relay/src/watch/plugin_actions.rs:184-187 |

### `docs/03-product-decisions.md` (39 rules — A=8, B=19, C=2, E=10)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-03-001` | B | docs/90-implementation-plan.md:921-924 (checked checkbox) |
| `R-03-002` | B | docs/90-implementation-plan.md:927-928 (checked checkbox) |
| `R-03-003` | B | docs/90-implementation-plan.md:978-982 (checked checkbox) |
| `R-03-010` | B | docs/90-implementation-plan.md:994-995 (checked checkbox) |
| `R-03-011` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-03-012` | B | docs/90-implementation-plan.md:994-995 (checked checkbox) |
| `R-03-013` | A | app/test/services/pairing_test.dart:259 |
| `R-03-020` | B | docs/90-implementation-plan.md:976-977 (checked checkbox) |
| `R-03-021` | B | docs/90-implementation-plan.md:976-977 (checked checkbox) |
| `R-03-022` | B | docs/90-implementation-plan.md:976-977 (checked checkbox) |
| `R-03-030` | A | crates/herdr-relay/src/config.rs:381 |
| `R-03-031` | B | docs/90-implementation-plan.md:954-955 (checked checkbox) |
| `R-03-032` | A | app/test/services/origin_change_test.dart:1 |
| `R-03-033` | A | app/test/services/origin_test.dart:3 |
| `R-03-040` | A | crates/herdr-relay-hub/tests/one_device.rs:3 |
| `R-03-041` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-03-042` | B | docs/90-implementation-plan.md:998-998 (checked checkbox) |
| `R-03-043` | C | app/test/services/host_list_test.dart (sibling test of app/lib/services/host_list.dart; rule id not literally cited) |
| `R-03-044` | B | docs/90-implementation-plan.md:3042-3050 (checked checkbox) |
| `R-03-045` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-03-046` | C | app/test/services/host_list_test.dart (sibling test of app/lib/services/host_list.dart; rule id not literally cited) |
| `R-03-047` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-03-050` | B | docs/90-implementation-plan.md:999-999 (checked checkbox) |
| `R-03-051` | B | docs/90-implementation-plan.md:999-999 (checked checkbox) |
| `R-03-052` | B | docs/90-implementation-plan.md:999-999 (checked checkbox) |
| `R-03-053` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-03-060` | B | docs/90-implementation-plan.md:1000-1001 (checked checkbox) |
| `R-03-061` | B | docs/90-implementation-plan.md:949-950 (checked checkbox) |
| `R-03-062` | A | app/test/services/no_stale_notification_test.dart:1 |
| `R-03-063` | B | docs/90-implementation-plan.md:1000-1001 (checked checkbox) |
| `R-03-070` | B | docs/90-implementation-plan.md:1002-1005 (checked checkbox) |
| `R-03-071` | A | app/integration_test/pairing_flow_test.dart:1 |
| `R-03-072` | B | docs/90-implementation-plan.md:921-924 (checked checkbox) |
| `R-03-080` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-03-081` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-03-082` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-03-083` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-03-084` | A | crates/herdr-relay/src/popup.rs |
| `R-03-085` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |

### `docs/10-herdr-integration.md` (59 rules — A=15, B=13, C=1, D=2, E=28)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-10-001` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-10-002` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-10-003` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-10-004` | A | app/test/services/terminal_test.dart:182 |
| `R-10-005` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-10-006` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-10-007` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-10-008` | D | enforced by standing gate: cargo fmt --check |
| `R-10-009` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-10-010` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-10-011` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-10-012` | A | app/test/models/ping_response_test.dart:3 |
| `R-10-013` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-10-014` | A | crates/herdr-relay/src/relay/backoff.rs:117 |
| `R-10-015` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-10-016` | C | app/test/models/char_width_test.dart (sibling test of app/lib/models/char_width.dart; rule id not literally cited) |
| `R-10-017` | A | app/test/services/sgr_fidelity_test.dart:2 |
| `R-10-018` | A | app/test/services/terminal_test.dart:293 |
| `R-10-019` | A | app/test/services/terminal_test.dart:580-581 |
| `R-10-020` | B | docs/90-implementation-plan.md:2814-2816 (checked checkbox) |
| `R-10-021` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-10-022` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-10-023` | A | app/test/models/char_width_test.dart:1 |
| `R-10-024` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-10-025` | A | app/test/services/terminal_test.dart:402 |
| `R-10-026` | B | docs/90-implementation-plan.md:2890-2891 (checked checkbox) |
| `R-10-027` | B | docs/90-implementation-plan.md:2892-2893 (checked checkbox) |
| `R-10-028` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-10-029` | B | docs/90-implementation-plan.md:2819-2820 (checked checkbox) |
| `R-10-030` | A | crates/herdr-relay/tests/debounce.rs:2 |
| `R-10-031` | A | crates/herdr-relay/src/watch/scheduler.rs:94 |
| `R-10-032` | A | crates/herdr-relay/tests/revision_gate.rs:2 |
| `R-10-033` | A | crates/herdr-relay/tests/reject_unknown.rs:5 |
| `R-10-034` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-10-035` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-10-036` | A | crates/herdr-relay/tests/input_map.rs:1 |
| `R-10-037` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-10-038` | D | enforced by standing gate: cargo fmt --check |
| `R-10-039` | A | crates/herdr-relay/src/watch/key_map.rs:148 |
| `R-10-040` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-10-041` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-10-042` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-10-043` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-10-044` | A | crates/herdr-relay/tests/input_map.rs:3 |
| `R-10-045` | B | docs/90-implementation-plan.md:2030-2035 (checked checkbox) |
| `R-10-046` | B | docs/90-implementation-plan.md:2086-2088 (checked checkbox) |
| `R-10-047` | B | docs/90-implementation-plan.md:2089-2090 (checked checkbox) |
| `R-10-048` | B | docs/90-implementation-plan.md:2082-2083 (checked checkbox) |
| `R-10-049` | B | docs/90-implementation-plan.md:2097-2099 (checked checkbox) |
| `R-10-050` | B | docs/90-implementation-plan.md:2102-2104 (checked checkbox) |
| `R-10-051` | B | docs/90-implementation-plan.md:2030-2035 (checked checkbox) |
| `R-10-052` | B | docs/90-implementation-plan.md:2105-2109 (checked checkbox) |
| `R-10-053` | B | docs/90-implementation-plan.md:2084-2085 (checked checkbox) |
| `R-10-054` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-10-055` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-10-056` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-10-057` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-10-058` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-10-059` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |

### `docs/11-relay-protocol.md` (121 rules — A=68, B=24, C=8, D=2, E=19)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-11-001` | A | crates/herdr-relay-hub/tests/ciphertext_only.rs:7 |
| `R-11-002` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-11-003` | D | enforced by standing gate: jsdom + mermaid.parse() browser-free check (docs/40-repo-tooling.md §8.3, R-40-057) |
| `R-11-013` | A | crates/herdr-relay/src/relay/connection.rs:288 |
| `R-11-022` | A | crates/herdr-relay-hub/src/heartbeat.rs:92-93,108-109 (test doc comments) |
| `R-11-023` | C | app/test/services/frame_codec_test.dart (sibling test of app/lib/services/frame_codec.dart; rule id not literally cited) |
| `R-11-024` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-11-026` | A | crates/herdr-relay/src/relay/connection.rs:259 |
| `R-11-027` | A | crates/herdr-relay-hub/tests/ciphertext_only.rs:7 |
| `R-11-030` | A | crates/herdr-relay-proto/src/frame.rs:161 (to_json_bytes_and_from_json_bytes_round_trip) |
| `R-11-031` | A | crates/herdr-relay-proto/src/frame.rs:149 (wrap_and_message_round_trip) |
| `R-11-032` | A | crates/herdr-relay-proto/src/frame.rs:149 (wrap_and_message_round_trip) |
| `R-11-033` | A | app/test/services/oversized_send_seq_test.dart:2 |
| `R-11-034` | C | app/test/services/tree_test.dart (sibling test of app/lib/services/tree.dart; rule id not literally cited) |
| `R-11-035` | A | app/test/models/frame_size_test.dart:3 |
| `R-11-036` | A | app/test/services/oversized_send_seq_test.dart:4 |
| `R-11-043` | B | docs/90-implementation-plan.md:3097-3101 (checked checkbox) |
| `R-11-044` | B | docs/90-implementation-plan.md:3200-3205 (checked checkbox) |
| `R-11-045` | A | crates/herdr-relay/tests/revision_gate.rs |
| `R-11-046` | A | crates/herdr-relay/tests/revision_gate.rs:159 |
| `R-11-047` | C | app/test/services/agent_list_test.dart (sibling test of app/lib/services/agent_list.dart; rule id not literally cited) |
| `R-11-048` | A | crates/herdr-relay/tests/one_pane.rs:2 |
| `R-11-049` | A | app/test/services/terminal_test.dart:127 |
| `R-11-050` | A | crates/herdr-relay/tests/one_pane.rs:195 |
| `R-11-051` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-11-052` | A | app/test/services/terminal_test.dart:277 |
| `R-11-053` | A | app/test/services/terminal_test.dart:501 |
| `R-11-054` | A | crates/herdr-relay/tests/input_map.rs:147 |
| `R-11-055` | A | crates/herdr-relay/tests/input_map.rs:188 |
| `R-11-056` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-11-057` | A | crates/herdr-relay/tests/agent_status.rs:2 |
| `R-11-058` | A | app/test/services/no_pane_text_test.dart:83 |
| `R-11-059` | A | crates/herdr-relay/tests/agent_status.rs:4 |
| `R-11-060` | A | app/test/services/composer_test.dart:2 |
| `R-11-062` | B | docs/90-implementation-plan.md:2024-2029 (checked checkbox) |
| `R-11-063` | A | crates/herdr-relay/src/watch/devices.rs:269 |
| `R-11-064` | A | crates/herdr-relay/src/watch/devices.rs:255 |
| `R-11-065` | A | crates/herdr-relay/tests/relay_connection.rs:179 |
| `R-11-070` | A | crates/herdr-relay/src/watch/latest_slot.rs:49-51 (latest_slot_keeps_only_the_newest_value) |
| `R-11-071` | A | crates/herdr-relay/tests/revision_gate.rs |
| `R-11-072` | A | crates/herdr-relay/tests/one_pane.rs:178 |
| `R-11-073` | A | crates/herdr-relay/tests/revision_gate.rs |
| `R-11-074` | D | enforced by standing gate: jsdom + mermaid.parse() browser-free check (docs/40-repo-tooling.md §8.3, R-40-057) |
| `R-11-080` | B | docs/90-implementation-plan.md:2481-2482 (checked checkbox) |
| `R-11-081` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-11-082` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-11-083` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-11-084` | A | app/integration_test/reconnect_after_restart_test.dart:149 |
| `R-11-085` | A | app/test/services/resume_test.dart:3 |
| `R-11-086` | A | crates/herdr-relay/src/relay/stale.rs:67-69 (stale_device_detector_flags_a_missed_pong) |
| `R-11-087` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-11-088` | B | docs/90-implementation-plan.md:2487-2489 (checked checkbox) |
| `R-11-090` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-11-091` | A | crates/herdr-relay/src/watch/error_map.rs:58,81-83 |
| `R-11-092` | A | app/integration_test/revocation_test.dart:287 |
| `R-11-100` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-11-101` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-11-102` | A | crates/herdr-relay-proto/src/messages/tree.rs:137 |
| `R-11-103` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-11-104` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-11-110` | C | app/test/services/pairing_test.dart (sibling test of app/lib/services/pairing.dart; rule id not literally cited) |
| `R-11-111` | A | app/test/services/origin_test.dart:109 |
| `R-11-112` | A | app/test/models/vectors_test.dart:132 |
| `R-11-113` | A | crates/herdr-relay/src/relay/connection.rs:145 |
| `R-11-114` | A | crates/herdr-relay-hub/tests/support/mod.rs:66 |
| `R-11-115` | A | crates/herdr-relay-hub/tests/support/mod.rs:68 |
| `R-11-116` | A | crates/herdr-relay-hub/tests/one_device.rs:18 |
| `R-11-117` | A | crates/herdr-relay-hub/tests/handle_isolation.rs:13 |
| `R-11-118` | A | crates/herdr-relay-hub/src/session/tests.rs:29-31 (second_host_is_refused_and_first_untouched) |
| `R-11-119` | B | docs/90-implementation-plan.md:951-952 (checked checkbox) |
| `R-11-120` | A | crates/herdr-relay-hub/src/session/tests.rs:215-216,231-232 (pairing_window_* tests) |
| `R-11-121` | A | crates/herdr-relay/tests/relay_connection.rs:212 |
| `R-11-122` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-11-123` | B | docs/90-implementation-plan.md:951-952 (checked checkbox) |
| `R-11-124` | B | docs/90-implementation-plan.md:2699-2704 (checked checkbox) |
| `R-11-125` | A | crates/herdr-relay-hub/src/session/tests.rs:150-151 (host_loss_closes_the_device_at_once_and_discards_the_room) |
| `R-11-130` | C | app/test/screens/agent_list_screen_test.dart (sibling test of app/lib/screens/agent_list_screen.dart; rule id not literally cited) |
| `R-11-131` | A | app/test/services/oversized_send_seq_test.dart:9 |
| `R-11-132` | B | docs/90-implementation-plan.md:2467-2468 (checked checkbox) |
| `R-11-133` | B | docs/90-implementation-plan.md:2469-2470 (checked checkbox) |
| `R-11-134` | B | docs/90-implementation-plan.md:3430-3431 (checked checkbox) |
| `R-11-140` | A | crates/herdr-relay-proto/src/handle.rs:337 |
| `R-11-141` | B | docs/90-implementation-plan.md:1893-1897 (checked checkbox) |
| `R-11-142` | B | docs/90-implementation-plan.md:1898-1906 (checked checkbox) |
| `R-11-200` | B | docs/90-implementation-plan.md:2492-2494 (checked checkbox) |
| `R-11-201` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-11-202` | B | docs/90-implementation-plan.md:3125-3131 (checked checkbox) |
| `R-11-203` | C | app/test/services/pane_actions_test.dart (sibling test of app/lib/services/pane_actions.dart; rule id not literally cited) |
| `R-11-204` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-11-205` | C | app/test/screens/create_sheet_test.dart (sibling test of app/lib/screens/create_sheet.dart; rule id not literally cited) |
| `R-11-206` | A | app/test/e2e/full_stack_test.dart:33 (Step 6) |
| `R-11-207` | A | app/test/e2e/full_stack_test.dart:33 (Step 6) |
| `R-11-208` | B | docs/90-implementation-plan.md:3247-3251 (checked checkbox) |
| `R-11-209` | A | app/test/screens/actions_screen_test.dart:4 |
| `R-11-210` | A | crates/herdr-relay/src/watch/plugin_actions.rs:184-187 (platform_matches_treats_null_platforms_as_unrestricted) |
| `R-11-211` | A | crates/herdr-relay/src/watch/plugin_actions.rs:211 |
| `R-11-215` | B | docs/90-implementation-plan.md:3258-3263 (checked checkbox) |
| `R-11-216` | B | docs/90-implementation-plan.md:3258-3263 (checked checkbox) |
| `R-11-217` | A | app/test/screens/actions_screen_test.dart:7 |
| `R-11-218` | A | crates/herdr-relay/src/watch/error_map.rs:58 |
| `R-11-219` | A | crates/herdr-relay/src/watch/error_map.rs:58 |
| `R-11-220` | B | docs/90-implementation-plan.md:3300-3303 (checked checkbox) |
| `R-11-221` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-11-222` | A | app/test/services/single_socket_test.dart:112 |
| `R-11-223` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-11-224` | A | app/test/services/tree_test.dart:4 |
| `R-11-225` | C | app/test/services/tree_test.dart (sibling test of app/lib/services/tree.dart; rule id not literally cited) |
| `R-11-226` | B | docs/90-implementation-plan.md:3739-3745 (checked checkbox) |
| `R-11-227` | A | app/test/e2e/full_stack_test.dart:30 (Step 5) |
| `R-11-228` | B | docs/90-implementation-plan.md:2954-2955 (checked checkbox) |
| `R-11-229` | A | crates/herdr-relay/src/relay/connection.rs:224 |
| `R-11-230` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-11-231` | A | crates/herdr-relay/src/frame_codec.rs:623 |
| `R-11-232` | B | docs/90-implementation-plan.md:1398-1408 (checked checkbox) |
| `R-11-233` | B | docs/90-implementation-plan.md:2483-2486 (checked checkbox) |
| `R-11-234` | A | crates/herdr-relay/src/frame_codec.rs:540 |
| `R-11-235` | B | docs/90-implementation-plan.md:1398-1408 (checked checkbox) |
| `R-11-236` | A | crates/herdr-relay/src/frame_codec.rs:507 |
| `R-11-237` | A | crates/herdr-relay/src/frame_codec.rs:561 |
| `R-11-238` | A | crates/herdr-relay/src/frame_codec.rs:603 |
| `R-11-239` | A | app/test/services/frame_codec_test.dart:3 |

### `docs/12-relay-hosting.md` (39 rules — A=27, B=6, D=1, E=5)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-12-001` | B | docs/90-implementation-plan.md:2500-2501 (checked checkbox) |
| `R-12-002` | A | crates/herdr-relay/src/relay/connection.rs:307 |
| `R-12-003` | A | crates/herdr-relay-hub/tests/forward_verbatim.rs:2 |
| `R-12-004` | A | crates/herdr-relay-hub/tests/handle_isolation.rs:2 |
| `R-12-005` | B | docs/90-implementation-plan.md:1898-1906 (checked checkbox) |
| `R-12-006` | A | crates/herdr-relay-hub/tests/latency.rs:3 |
| `R-12-007` | A | crates/herdr-relay-hub/tests/load.rs:3 |
| `R-12-008` | A | crates/herdr-relay-hub/src/session/tests.rs:150-151 (host_loss_closes_the_device_at_once_and_discards_the_room) |
| `R-12-009` | A | crates/herdr-relay-hub/src/session/tests.rs:193-194 (device_loss_closes_the_host_at_once_and_discards_the_room) |
| `R-12-010` | A | crates/herdr-relay-hub/src/routes.rs:183 (healthz_returns_ok_body) |
| `R-12-011` | A | crates/herdr-relay-hub/src/routes/metrics.rs:279-280 (render_includes_every_r_12_050_metric_name) |
| `R-12-012` | D | enforced by standing gate: cargo fmt --check |
| `R-12-013` | A | crates/herdr-relay-hub/tests/no_persistence.rs:2 |
| `R-12-014` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-12-015` | A | crates/herdr-relay-hub/src/routes/metrics.rs:279-280 (render_includes_every_r_12_050_metric_name) |
| `R-12-016` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-12-020` | A | crates/herdr-relay/src/relay/connection.rs:110 |
| `R-12-021` | A | crates/herdr-relay-hub/tests/fuzz_endpoints.rs:4,67,80,290-291 |
| `R-12-022` | A | crates/herdr-relay-hub/src/heartbeat.rs:108-109,121-122,132-133 (test doc comments) |
| `R-12-023` | A | crates/herdr-relay-hub/tests/fuzz_endpoints.rs:221 (assert_relay_still_answers_healthz) |
| `R-12-024` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-12-030` | A | crates/herdr-relay-hub/tests/fuzz_endpoints.rs:4,291 |
| `R-12-031` | A | crates/herdr-relay-hub/tests/limits.rs:1 |
| `R-12-032` | A | crates/herdr-relay-hub/tests/latency.rs:14 |
| `R-12-033` | A | crates/herdr-relay-hub/tests/limits.rs:2 |
| `R-12-034` | A | crates/herdr-relay-hub/tests/limits.rs:3 |
| `R-12-035` | A | crates/herdr-relay-hub/tests/one_device.rs:3 |
| `R-12-036` | A | crates/herdr-relay-hub/tests/load.rs:116 |
| `R-12-037` | A | crates/herdr-relay-hub/src/session/tests.rs:29-31,55-56 (second_host/second_device_is_refused_and_first_untouched) |
| `R-12-038` | A | crates/herdr-relay-hub/src/session/tests.rs:158,161 |
| `R-12-039` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-12-040` | A | crates/herdr-relay-hub/tests/log_fields.rs:2 |
| `R-12-041` | A | crates/herdr-relay-hub/tests/log_fields.rs:2 |
| `R-12-042` | B | docs/90-implementation-plan.md:1438-1446 (checked checkbox) |
| `R-12-043` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-12-050` | A | crates/herdr-relay-hub/src/routes/metrics.rs:279 (render_includes_every_r_12_050_metric_name) |
| `R-12-051` | B | docs/90-implementation-plan.md:1793-1794 (checked checkbox) |
| `R-12-060` | B | docs/90-implementation-plan.md:3944-3952 (checked checkbox) |
| `R-12-070` | B | docs/90-implementation-plan.md:1799-1800 (checked checkbox) |

### `docs/13-security-pairing.md` (63 rules — A=33, B=16, C=5, D=1, E=8)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-13-001` | D | enforced by standing gate: docs/40-repo-tooling.md §8.4 rule-consistency audit (every cited R-nn-nnn must exist exactly once) |
| `R-13-002` | A | crates/herdr-relay-hub/tests/ciphertext_only.rs:8 |
| `R-13-012` | A | crates/herdr-relay-hub/tests/ciphertext_only.rs:8 |
| `R-13-013` | A | crates/herdr-relay-hub/tests/ciphertext_only.rs:119 |
| `R-13-014` | A | crates/herdr-relay/src/noise.rs:197 |
| `R-13-015` | A | crates/herdr-relay/src/noise.rs:257 |
| `R-13-016` | B | docs/90-implementation-plan.md:1427-1432 (checked checkbox) |
| `R-13-017` | B | docs/90-implementation-plan.md:945-946 (checked checkbox) |
| `R-13-018` | B | docs/90-implementation-plan.md:945-946 (checked checkbox) |
| `R-13-019` | A | app/test/models/vectors_test.dart:136 |
| `R-13-020` | C | crates/herdr-relay-proto/tests/phrase.rs (sibling test of crates/herdr-relay-proto/src/phrase.rs; rule id not literally cited) |
| `R-13-021` | C | crates/herdr-relay-proto/tests/phrase.rs (sibling test of crates/herdr-relay-proto/src/phrase.rs; rule id not literally cited) |
| `R-13-022` | A | crates/herdr-relay/src/pairing.rs:367 |
| `R-13-023` | A | crates/herdr-relay/src/pairing.rs:368 |
| `R-13-024` | A | crates/herdr-relay/tests/relay_connection.rs:34 |
| `R-13-025` | A | crates/herdr-relay/src/pairing.rs:313 |
| `R-13-026` | A | crates/herdr-relay-proto/tests/phrase.rs:128 |
| `R-13-027` | A | crates/herdr-relay-proto/tests/phrase.rs:2 |
| `R-13-028` | A | crates/herdr-relay/tests/popup_once.rs:110-111 |
| `R-13-029` | B | docs/90-implementation-plan.md:1890-1892 (checked checkbox) |
| `R-13-030` | B | docs/90-implementation-plan.md:1828-1830 (checked checkbox) |
| `R-13-031` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-13-032` | B | docs/90-implementation-plan.md:947-948 (checked checkbox) |
| `R-13-033` | A | app/test/services/single_socket_test.dart:5 |
| `R-13-034` | A | app/test/services/origin_change_test.dart:1 |
| `R-13-035` | A | app/integration_test/pairing_flow_test.dart:1 |
| `R-13-036` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-13-037` | A | app/integration_test/reconnect_after_restart_test.dart:2 |
| `R-13-038` | A | app/integration_test/reconnect_after_restart_test.dart:19 |
| `R-13-039` | B | docs/90-implementation-plan.md:1337-1341 (checked checkbox) |
| `R-13-040` | A | crates/herdr-relay/src/keys.rs:292 |
| `R-13-041` | B | docs/90-implementation-plan.md:2452-2454 (checked checkbox) |
| `R-13-042` | B | docs/90-implementation-plan.md:1840-1843 (checked checkbox) |
| `R-13-043` | A | app/integration_test/reconnect_after_restart_test.dart:233 |
| `R-13-044` | C | app/test/services/keystore_test.dart (sibling test of app/lib/services/keystore.dart; rule id not literally cited) |
| `R-13-045` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-13-046` | A | app/integration_test/keystore_survival_test.dart:2 |
| `R-13-047` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-13-048` | A | app/integration_test/reconnect_after_restart_test.dart:19 |
| `R-13-049` | B | docs/90-implementation-plan.md:1844-1850 (checked checkbox) |
| `R-13-050` | A | app/integration_test/reconnect_after_restart_test.dart:115 |
| `R-13-051` | A | crates/herdr-relay/src/store.rs:236-239 (reload_from_disk_survives_a_restart) |
| `R-13-052` | A | crates/herdr-relay/src/watch/devices.rs:163 |
| `R-13-053` | A | crates/herdr-relay/src/popup.rs:1729 |
| `R-13-054` | A | app/integration_test/revocation_test.dart:12 |
| `R-13-055` | A | app/integration_test/revocation_test.dart:1 |
| `R-13-056` | A | crates/herdr-relay/src/popup.rs:1793 |
| `R-13-057` | B | docs/90-implementation-plan.md:1944-1948 (checked checkbox) |
| `R-13-058` | B | docs/90-implementation-plan.md:1325-1329 (checked checkbox) |
| `R-13-059` | B | docs/90-implementation-plan.md:1835-1839 (checked checkbox) |
| `R-13-060` | B | docs/90-implementation-plan.md:1844-1850 (checked checkbox) |
| `R-13-061` | B | docs/90-implementation-plan.md:1851-1854 (checked checkbox) |
| `R-13-062` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-13-063` | B | docs/90-implementation-plan.md:2761-2769 (checked checkbox) |
| `R-13-064` | A | app/integration_test/reconnect_after_restart_test.dart:2 |
| `R-13-065` | C | app/test/services/notifications_test.dart (sibling test of app/lib/services/notifications.dart; rule id not literally cited) |
| `R-13-066` | A | app/test/services/single_socket_test.dart:5 |
| `R-13-067` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-13-068` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-13-069` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-13-070` | C | app/test/services/keystore_test.dart (sibling test of app/lib/services/keystore.dart; rule id not literally cited) |
| `R-13-071` | A | crates/herdr-relay/src/relay/connection.rs:172 |
| `R-13-072` | A | crates/herdr-relay/tests/hmac_blake2s_vectors.rs:1 |

### `docs/14-relay-deployment.md` (24 rules — A=1, B=18, E=5)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-14-001` | B | docs/90-implementation-plan.md:925-926 (checked checkbox) |
| `R-14-002` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-14-010` | B | docs/90-implementation-plan.md:1772-1774 (checked checkbox) |
| `R-14-011` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-14-012` | B | docs/90-implementation-plan.md:1778-1780 (checked checkbox) |
| `R-14-013` | B | docs/90-implementation-plan.md:1772-1774 (checked checkbox) |
| `R-14-014` | A | crates/herdr-relay-hub/src/routes/config.rs:59-61 (defaults_match_r_14_014_when_unset) |
| `R-14-015` | B | docs/90-implementation-plan.md:1778-1780 (checked checkbox) |
| `R-14-020` | B | docs/90-implementation-plan.md:925-926 (checked checkbox) |
| `R-14-021` | B | docs/90-implementation-plan.md:1775-1777 (checked checkbox) |
| `R-14-022` | B | docs/90-implementation-plan.md:1373-1397 (checked checkbox) |
| `R-14-023` | B | docs/90-implementation-plan.md:1775-1777 (checked checkbox) |
| `R-14-030` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-14-031` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-14-040` | B | docs/90-implementation-plan.md:1783-1784 (checked checkbox) |
| `R-14-050` | B | docs/90-implementation-plan.md:1778-1780 (checked checkbox) |
| `R-14-051` | B | docs/90-implementation-plan.md:1785-1787 (checked checkbox) |
| `R-14-052` | B | docs/90-implementation-plan.md:1785-1787 (checked checkbox) |
| `R-14-053` | B | docs/90-implementation-plan.md:1788-1789 (checked checkbox) |
| `R-14-060` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-14-061` | B | docs/90-implementation-plan.md:1790-1792 (checked checkbox) |
| `R-14-062` | B | docs/90-implementation-plan.md:1790-1792 (checked checkbox) |
| `R-14-070` | B | docs/90-implementation-plan.md:1793-1794 (checked checkbox) |
| `R-14-071` | B | docs/90-implementation-plan.md:1793-1794 (checked checkbox) |

### `docs/15-nvidia-brev-relay-experiment.md` (6 rules — E=6)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-15-001` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-15-002` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-15-003` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-15-004` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-15-010` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-15-011` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |

### `docs/20-mobile-framework.md` (32 rules — A=8, B=3, C=3, E=18)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-20-001` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-20-002` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-20-003` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-20-004` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-20-005` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-20-006` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-20-007` | A | app/integration_test/reconnect_after_restart_test.dart:29 |
| `R-20-008` | A | app/integration_test/spike_render_test.dart:1 |
| `R-20-009` | A | app/test/services/single_socket_test.dart:2 |
| `R-20-010` | A | app/test/models/vectors_test.dart:100-103 |
| `R-20-011` | B | docs/90-implementation-plan.md:2427-2429 (checked checkbox) |
| `R-20-012` | B | docs/90-implementation-plan.md:2430-2432 (checked checkbox) |
| `R-20-013` | A | app/test/services/terminal_test.dart:128-129,481-482 |
| `R-20-014` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-20-015` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-20-026` | C | app/test/services/notifications_test.dart (sibling test of app/lib/services/notifications.dart; rule id not literally cited) |
| `R-20-027` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-20-028` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-20-029` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-20-030` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-20-031` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-20-032` | A | app/test/spike/noise_client_test.dart:19 |
| `R-20-033` | B | docs/90-implementation-plan.md:3403-3404 (checked checkbox) |
| `R-20-034` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-20-035` | C | app/test/services/keystore_test.dart (sibling test of app/lib/services/keystore.dart; rule id not literally cited) |
| `R-20-036` | A | app/test/screens/settings_screen_test.dart |
| `R-20-037` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-20-038` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-20-039` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-20-040` | A | app/test/services/no_dismissible_test.dart:1 |
| `R-20-042` | C | app/test/services/notifications_test.dart (sibling test of app/lib/services/notifications.dart; rule id not literally cited) |
| `R-20-043` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |

### `docs/21-terminal-rendering.md` (35 rules — A=17, B=9, E=9)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-21-001` | A | app/test/services/reset_no_scrollback_test.dart:4 |
| `R-21-002` | A | app/integration_test/spike_render_test.dart:6 |
| `R-21-003` | A | app/integration_test/spike_render_test.dart:14 |
| `R-21-004` | A | app/test/services/terminal_test.dart:262 |
| `R-21-005` | A | app/test/services/terminal_test.dart:371-372 |
| `R-21-006` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-21-007` | A | app/test/services/sgr_fidelity_test.dart:3 |
| `R-21-008` | B | docs/90-implementation-plan.md:2844-2845 (checked checkbox) |
| `R-21-009` | A | app/integration_test/spike_render_test.dart:58 |
| `R-21-010` | A | app/test/widgets/terminal_isolated_test.dart:219 |
| `R-21-011` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-21-012` | A | app/integration_test/spike_render_test.dart:172 |
| `R-21-013` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-21-014` | A | app/integration_test/spike_render_test.dart:41 |
| `R-21-015` | B | docs/90-implementation-plan.md:2932-2933 (checked checkbox) |
| `R-21-016` | B | docs/90-implementation-plan.md:2939-2940 (checked checkbox) |
| `R-21-017` | B | docs/90-implementation-plan.md:2939-2940 (checked checkbox) |
| `R-21-018` | B | docs/90-implementation-plan.md:2950-2951 (checked checkbox) |
| `R-21-019` | B | docs/90-implementation-plan.md:2936-2938 (checked checkbox) |
| `R-21-020` | B | docs/90-implementation-plan.md:2932-2933 (checked checkbox) |
| `R-21-021` | A | app/test/services/terminal_test.dart:377 |
| `R-21-022` | A | app/test/services/terminal_test.dart:545 |
| `R-21-030` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-21-031` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-21-032` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-21-033` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-21-034` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-21-035` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-21-036` | A | app/test/services/terminal_test.dart:210 |
| `R-21-037` | A | app/test/screens/no_gesture_sends_test.dart:4 |
| `R-21-038` | A | app/test/screens/no_gesture_sends_test.dart:29 |
| `R-21-039` | B | docs/90-implementation-plan.md:2864-2867 (checked checkbox) |
| `R-21-040` | B | docs/90-implementation-plan.md:2868-2870 (checked checkbox) |
| `R-21-041` | A | app/test/services/terminal_test.dart:4 |
| `R-21-042` | A | app/test/widgets/terminal_isolated_test.dart:33 |

### `docs/22-platform-integration.md` (72 rules — A=14, B=12, C=12, E=34)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-22-001` | A | app/test/services/keystore_test.dart:3 |
| `R-22-002` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-22-003` | C | app/test/services/keystore_test.dart (sibling test of app/lib/services/keystore.dart; rule id not literally cited) |
| `R-22-004` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-22-005` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-22-006` | C | app/test/services/keystore_test.dart (sibling test of app/lib/services/keystore.dart; rule id not literally cited) |
| `R-22-007` | C | app/test/services/keystore_test.dart (sibling test of app/lib/services/keystore.dart; rule id not literally cited) |
| `R-22-008` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-22-009` | A | app/integration_test/keystore_survival_test.dart:2 |
| `R-22-010` | A | app/test/services/biometric_gate_test.dart:157 |
| `R-22-011` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-22-012` | B | docs/90-implementation-plan.md:3359-3365 (checked checkbox) |
| `R-22-013` | A | app/test/services/biometric_gate_test.dart:1 |
| `R-22-014` | A | app/test/services/keystore_test.dart:1 |
| `R-22-015` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-22-016` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-22-017` | A | app/test/services/biometric_gate_test.dart:175 |
| `R-22-018` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-22-019` | C | app/test/services/notifications_test.dart (sibling test of app/lib/services/notifications.dart; rule id not literally cited) |
| `R-22-020` | C | app/test/services/notifications_test.dart (sibling test of app/lib/services/notifications.dart; rule id not literally cited) |
| `R-22-021` | B | docs/90-implementation-plan.md:2557-2563 (checked checkbox) |
| `R-22-022` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-22-023` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-22-024` | A | app/test/services/no_stale_notification_test.dart:3 |
| `R-22-025` | A | app/test/services/single_socket_test.dart:2 |
| `R-22-026` | B | docs/90-implementation-plan.md:2492-2494 (checked checkbox) |
| `R-22-027` | B | docs/90-implementation-plan.md:2490-2491 (checked checkbox) |
| `R-22-028` | A | app/integration_test/revocation_test.dart:292 |
| `R-22-029` | C | app/test/services/pairing_test.dart (sibling test of app/lib/services/pairing.dart; rule id not literally cited) |
| `R-22-030` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-22-031` | C | app/test/screens/qr_scan_screen_test.dart (sibling test of app/lib/screens/qr_scan_screen.dart; rule id not literally cited) |
| `R-22-032` | C | app/test/services/pairing_test.dart (sibling test of app/lib/services/pairing.dart; rule id not literally cited) |
| `R-22-033` | B | docs/90-implementation-plan.md:2719-2722 (checked checkbox) |
| `R-22-034` | A | app/integration_test/pairing_flow_test.dart:313 |
| `R-22-035` | B | docs/90-implementation-plan.md:2433-2434 (checked checkbox) |
| `R-22-036` | B | docs/90-implementation-plan.md:2735-2744 (checked checkbox) |
| `R-22-037` | A | app/test/services/origin_test.dart:2 |
| `R-22-038` | A | app/test/services/origin_test.dart:109 |
| `R-22-039` | A | app/integration_test/first_paint_test.dart:231 |
| `R-22-040` | B | docs/90-implementation-plan.md:2473-2474 (checked checkbox) |
| `R-22-041` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-22-042` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-22-043` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-22-044` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-22-045` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-22-050` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-22-051` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-22-052` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-22-053` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-22-054` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-22-055` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-22-056` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-22-060` | C | app/test/services/notifications_test.dart (sibling test of app/lib/services/notifications.dart; rule id not literally cited) |
| `R-22-061` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-22-062` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-22-063` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-22-064` | C | app/test/services/notifications_test.dart (sibling test of app/lib/services/notifications.dart; rule id not literally cited) |
| `R-22-065` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-22-066` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-22-067` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-22-068` | C | app/test/services/notifications_test.dart (sibling test of app/lib/services/notifications.dart; rule id not literally cited) |
| `R-22-069` | C | app/test/services/biometric_gate_test.dart (sibling test of app/lib/services/biometric_gate.dart; rule id not literally cited) |
| `R-22-070` | A | app/test/screens/lock_screen_test.dart:57 |
| `R-22-071` | B | docs/90-implementation-plan.md:2557-2563 (checked checkbox) |
| `R-22-072` | B | docs/90-implementation-plan.md:3416-3417 (checked checkbox) |
| `R-22-073` | B | docs/90-implementation-plan.md:3418-3419 (checked checkbox) |
| `R-22-074` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-22-075` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-22-077` | B | docs/90-implementation-plan.md:2956-2959 (checked checkbox) |
| `R-22-078` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-22-079` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-22-080` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |

### `docs/23-public-release.md` (61 rules — A=10, B=7, E=44)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-23-001` | A | app/test/config/app_identity_test.dart |
| `R-23-002` | A | app/test/config/app_identity_test.dart |
| `R-23-003` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-004` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-005` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-006` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-007` | B | docs/90-implementation-plan.md:929-931 (checked checkbox) |
| `R-23-008` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-009` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-010` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-011` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-012` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-013` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-014` | B | docs/90-implementation-plan.md:929-931 (checked checkbox) |
| `R-23-015` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-016` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-017` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-018` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-019` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-020` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-021` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-022` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-023` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-024` | B | docs/90-implementation-plan.md:929-931 (checked checkbox) |
| `R-23-025` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-026` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-027` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-028` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-029` | B | docs/90-implementation-plan.md:929-931 (checked checkbox) |
| `R-23-030` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-031` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-032` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-033` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-034` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-035` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-036` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-037` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-038` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-039` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-040` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-041` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-042` | B | docs/90-implementation-plan.md:2471-2472 (checked checkbox) |
| `R-23-043` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-044` | B | docs/90-implementation-plan.md:2469-2470 (checked checkbox) |
| `R-23-045` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-046` | A | app/test/services/relay_test.dart |
| `R-23-047` | A | app/test/services/relay_test.dart |
| `R-23-048` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-049` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-050` | A | app/test/config/store_icon_test.dart |
| `R-23-051` | A | app/test/config/store_icon_test.dart |
| `R-23-052` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-053` | A | app/test/config/store_icon_test.dart |
| `R-23-054` | A | app/test/config/app_identity_test.dart |
| `R-23-055` | A | app/test/config/app_identity_test.dart |
| `R-23-056` | A | app/test/config/app_identity_test.dart |
| `R-23-057` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-058` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-059` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-23-060` | B | docs/90-implementation-plan.md:3779-3788 (checked checkbox) |
| `R-23-062` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |

### `docs/30-ux-spec.md` (217 rules — A=80, B=33, C=27, D=1, E=76)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-30-001` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-002` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-003` | C | app/test/screens/agent_list_screen_test.dart (sibling test of app/lib/screens/agent_list_screen.dart; rule id not literally cited) |
| `R-30-004` | B | docs/90-implementation-plan.md:3017-3025 (checked checkbox) |
| `R-30-005` | C | app/test/screens/qr_scan_screen_test.dart (sibling test of app/lib/screens/qr_scan_screen.dart; rule id not literally cited) |
| `R-30-020` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-021` | A | app/test/screens/app_shell_test.dart:2 |
| `R-30-022` | C | app/test/screens/app_shell_test.dart (sibling test of app/lib/screens/app_shell.dart; rule id not literally cited) |
| `R-30-023` | C | app/test/screens/agent_list_screen_test.dart (sibling test of app/lib/screens/agent_list_screen.dart; rule id not literally cited) |
| `R-30-024` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-025` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-030` | B | docs/90-implementation-plan.md:3430-3431 (checked checkbox) |
| `R-30-031` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-040` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-041` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-042` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-043` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-044` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-045` | C | app/test/screens/app_shell_test.dart (sibling test of app/lib/screens/app_shell.dart; rule id not literally cited) |
| `R-30-100` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-101` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-102` | A | app/test/widgets/theme/no_literals_test.dart:3 |
| `R-30-103` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-110` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-111` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-112` | A | app/test/services/app_settings_test.dart |
| `R-30-120` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-121` | A | app/test/widgets/app_filled_button_test.dart |
| `R-30-130` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-131` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-132` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-133` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-140` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-141` | A | app/test/widgets/treatments_test.dart |
| `R-30-142` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-143` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-150` | B | docs/90-implementation-plan.md:2827-2828 (checked checkbox) |
| `R-30-151` | A | app/test/widgets/theme/contrast_test.dart:282-283 |
| `R-30-152` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-153` | A | app/test/services/sgr_fidelity_test.dart:7-9 |
| `R-30-154` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-155` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-156` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-157` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-158` | A | app/test/services/terminal_test.dart:393 |
| `R-30-160` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-200` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-201` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-202` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-210` | A | app/test/widgets/theme/app_type_test.dart |
| `R-30-211` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-212` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-213` | A | app/test/widgets/theme/app_type_test.dart |
| `R-30-230` | A | app/test/widgets/terminal_isolated_test.dart:500 |
| `R-30-231` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-232` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-250` | A | app/test/widgets/terminal_isolated_test.dart:500 |
| `R-30-260` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-261` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-270` | B | docs/90-implementation-plan.md:2946-2947 (checked checkbox) |
| `R-30-271` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-272` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-273` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-280` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-281` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-282` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-283` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-284` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-285` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-290` | B | docs/90-implementation-plan.md:2948-2949 (checked checkbox) |
| `R-30-291` | A | app/test/a11y/touch_target_test.dart |
| `R-30-292` | A | app/test/a11y/touch_target_test.dart |
| `R-30-293` | C | app/test/screens/lock_screen_test.dart (sibling test of app/lib/screens/lock_screen.dart; rule id not literally cited) |
| `R-30-294` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-295` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-296` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-297` | A | app/test/screens/host_list_screen_test.dart:4 |
| `R-30-298` | A | app/test/screens/agent_list_screen_test.dart:5 |
| `R-30-299` | A | app/test/screens/host_list_screen_test.dart:5 |
| `R-30-300` | A | app/test/screens/no_gesture_sends_test.dart:1 |
| `R-30-301` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-302` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-303` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-304` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-305` | A | app/test/widgets/terminal_isolated_test.dart |
| `R-30-306` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-307` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-308` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-400` | A | app/test/screens/agent_list_screen_test.dart |
| `R-30-401` | A | app/test/screens/agent_list_screen_test.dart |
| `R-30-402` | B | docs/90-implementation-plan.md:3080-3086 (checked checkbox) |
| `R-30-403` | A | app/test/a11y/reduce_motion_test.dart:11 |
| `R-30-404` | A | app/test/services/agent_list_test.dart:256 |
| `R-30-405` | A | app/test/services/agent_list_test.dart:6 |
| `R-30-406` | A | app/test/services/agent_list_test.dart:3 |
| `R-30-407` | C | app/test/services/agent_list_test.dart (sibling test of app/lib/services/agent_list.dart; rule id not literally cited) |
| `R-30-408` | A | app/test/screens/agent_list_screen_test.dart |
| `R-30-409` | A | app/test/services/agent_list_test.dart:5 |
| `R-30-410` | C | app/test/screens/agent_list_screen_test.dart (sibling test of app/lib/screens/agent_list_screen.dart; rule id not literally cited) |
| `R-30-411` | A | app/test/screens/agent_list_screen_test.dart |
| `R-30-412` | C | app/test/screens/agent_list_screen_test.dart (sibling test of app/lib/screens/agent_list_screen.dart; rule id not literally cited) |
| `R-30-413` | C | app/test/screens/agent_list_screen_test.dart (sibling test of app/lib/screens/agent_list_screen.dart; rule id not literally cited) |
| `R-30-414` | A | app/test/services/agent_list_test.dart:3 |
| `R-30-500` | C | app/test/services/notifications_test.dart (sibling test of app/lib/services/notifications.dart; rule id not literally cited) |
| `R-30-501` | C | app/test/services/agent_list_test.dart (sibling test of app/lib/services/agent_list.dart; rule id not literally cited) |
| `R-30-502` | C | app/test/services/notifications_test.dart (sibling test of app/lib/services/notifications.dart; rule id not literally cited) |
| `R-30-503` | A | app/test/screens/agent_list_screen_test.dart:5 |
| `R-30-504` | A | app/test/screens/agent_list_screen_test.dart:4 |
| `R-30-505` | A | app/test/services/no_pane_text_test.dart:63 |
| `R-30-506` | C | app/test/services/notifications_test.dart (sibling test of app/lib/services/notifications.dart; rule id not literally cited) |
| `R-30-507` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-508` | C | app/test/services/agent_list_test.dart (sibling test of app/lib/services/agent_list.dart; rule id not literally cited) |
| `R-30-509` | B | docs/90-implementation-plan.md:2557-2563 (checked checkbox) |
| `R-30-510` | A | app/test/services/no_pane_text_test.dart:2 |
| `R-30-511` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-512` | A | app/test/screens/connection_screen_test.dart:159 |
| `R-30-513` | A | app/test/services/no_stale_notification_test.dart:1 |
| `R-30-514` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-515` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-516` | B | docs/90-implementation-plan.md:3435-3441 (checked checkbox) |
| `R-30-517` | A | app/test/screens/connection_screen_test.dart:159 |
| `R-30-518` | A | app/test/screens/create_sheet_test.dart:5 |
| `R-30-519` | B | docs/90-implementation-plan.md:2956-2959 (checked checkbox) |
| `R-30-520` | B | docs/90-implementation-plan.md:3291-3299 (checked checkbox) |
| `R-30-600` | A | crates/herdr-relay/src/popup.rs |
| `R-30-601` | A | crates/herdr-relay/src/popup.rs |
| `R-30-602` | A | crates/herdr-relay/src/popup.rs |
| `R-30-603` | A | crates/herdr-relay/src/popup.rs |
| `R-30-604` | A | crates/herdr-relay/src/popup.rs |
| `R-30-605` | A | crates/herdr-relay/src/popup.rs |
| `R-30-606` | A | crates/herdr-relay/src/popup.rs |
| `R-30-607` | A | crates/herdr-relay/src/popup.rs |
| `R-30-608` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-610` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-611` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-700` | A | app/test/a11y/text_scale_test.dart:1 |
| `R-30-701` | A | app/test/a11y/text_scale_test.dart:1 |
| `R-30-702` | A | app/test/a11y/text_scale_test.dart:3 |
| `R-30-703` | A | app/test/a11y/text_scale_test.dart:1 |
| `R-30-704` | A | app/test/a11y/text_scale_test.dart:1 |
| `R-30-710` | A | app/test/widgets/terminal_isolated_test.dart:237 |
| `R-30-711` | A | app/test/widgets/terminal_isolated_test.dart:237 |
| `R-30-712` | A | app/test/widgets/terminal_isolated_test.dart:237 |
| `R-30-713` | B | docs/90-implementation-plan.md:3841-3844 (checked checkbox) |
| `R-30-714` | A | app/test/services/no_stale_notification_test.dart:7 |
| `R-30-715` | B | docs/90-implementation-plan.md:3861-3870 (checked checkbox) |
| `R-30-716` | B | docs/90-implementation-plan.md:3861-3870 (checked checkbox) |
| `R-30-717` | B | docs/90-implementation-plan.md:3861-3870 (checked checkbox) |
| `R-30-718` | B | docs/90-implementation-plan.md:3861-3870 (checked checkbox) |
| `R-30-719` | B | docs/90-implementation-plan.md:3880-3886 (checked checkbox) |
| `R-30-720` | B | docs/90-implementation-plan.md:3908-3910 (checked checkbox) |
| `R-30-721` | B | docs/90-implementation-plan.md:3908-3910 (checked checkbox) |
| `R-30-722` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-730` | A | app/test/a11y/reduce_motion_test.dart:1 |
| `R-30-731` | A | app/test/a11y/reduce_motion_test.dart:1 |
| `R-30-732` | A | app/test/a11y/reduce_motion_test.dart:1 |
| `R-30-740` | A | app/test/a11y/touch_target_test.dart:1 |
| `R-30-741` | A | app/test/a11y/touch_target_test.dart:1 |
| `R-30-742` | A | app/test/services/no_stale_notification_test.dart:7 |
| `R-30-743` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-800` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-801` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-802` | C | app/test/screens/actions_screen_test.dart (sibling test of app/lib/screens/actions_screen.dart; rule id not literally cited) |
| `R-30-803` | A | app/test/screens/create_sheet_test.dart:3 |
| `R-30-804` | A | app/test/screens/create_sheet_test.dart:4 |
| `R-30-805` | C | app/test/screens/agent_list_screen_test.dart (sibling test of app/lib/screens/agent_list_screen.dart; rule id not literally cited) |
| `R-30-806` | C | app/test/screens/prompt_composer_test.dart (sibling test of app/lib/screens/prompt_composer.dart; rule id not literally cited) |
| `R-30-807` | C | app/test/screens/actions_screen_test.dart (sibling test of app/lib/screens/actions_screen.dart; rule id not literally cited) |
| `R-30-808` | C | app/test/screens/prompt_composer_test.dart (sibling test of app/lib/screens/prompt_composer.dart; rule id not literally cited) |
| `R-30-809` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-900` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-901` | C | app/test/screens/manual_pairing_screen_test.dart (sibling test of app/lib/screens/manual_pairing_screen.dart; rule id not literally cited) |
| `R-30-902` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-903` | B | docs/90-implementation-plan.md:2633-2643 (checked checkbox) |
| `R-30-904` | A | app/test/services/pairing_test.dart:243 |
| `R-30-905` | B | docs/90-implementation-plan.md:2663-2670 (checked checkbox) |
| `R-30-906` | A | app/test/screens/manual_pairing_screen_test.dart:3 |
| `R-30-907` | A | app/test/screens/manual_pairing_screen_test.dart:4 |
| `R-30-908` | B | docs/90-implementation-plan.md:2683-2687 (checked checkbox) |
| `R-30-909` | C | app/test/services/pairing_test.dart (sibling test of app/lib/services/pairing.dart; rule id not literally cited) |
| `R-30-910` | A | app/test/screens/manual_pairing_screen_test.dart:3 |
| `R-30-911` | D | enforced by standing gate: docs/40-repo-tooling.md §8.4 rule-consistency audit script |
| `R-30-912` | B | docs/90-implementation-plan.md:3871-3879 (checked checkbox) |
| `R-30-920` | B | docs/90-implementation-plan.md:3754-3757 (checked checkbox) |
| `R-30-921` | A | app/integration_test/pairing_flow_test.dart:284 |
| `R-30-922` | C | app/test/screens/connection_screen_test.dart (sibling test of app/lib/screens/connection_screen.dart; rule id not literally cited) |
| `R-30-923` | B | docs/90-implementation-plan.md:3766-3769 (checked checkbox) |
| `R-30-924` | A | app/test/screens/settings_screen_test.dart |
| `R-30-925` | A | app/test/screens/settings_screen_test.dart |
| `R-30-926` | A | app/test/services/origin_change_test.dart:1 |
| `R-30-927` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-940` | B | docs/90-implementation-plan.md:3011-3016 (checked checkbox) |
| `R-30-941` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-942` | C | app/test/screens/connection_screen_test.dart (sibling test of app/lib/screens/connection_screen.dart; rule id not literally cited) |
| `R-30-943` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-944` | B | docs/90-implementation-plan.md:3011-3016 (checked checkbox) |
| `R-30-945` | A | app/test/screens/qr_scan_screen_test.dart:152 |
| `R-30-946` | B | docs/90-implementation-plan.md:3770-3774 (checked checkbox) |
| `R-30-947` | A | app/test/screens/host_list_screen_test.dart:6 |
| `R-30-948` | A | app/test/screens/host_list_screen_test.dart:5 |
| `R-30-949` | B | docs/90-implementation-plan.md:3057-3066 (checked checkbox) |
| `R-30-950` | A | app/test/screens/create_sheet_test.dart |
| `R-30-951` | C | app/test/screens/create_sheet_test.dart (sibling test of app/lib/screens/create_sheet.dart; rule id not literally cited) |
| `R-30-952` | C | app/test/services/pane_actions_test.dart (sibling test of app/lib/services/pane_actions.dart; rule id not literally cited) |
| `R-30-953` | A | app/test/screens/create_sheet_test.dart |
| `R-30-954` | C | app/test/services/tree_test.dart (sibling test of app/lib/services/tree.dart; rule id not literally cited) |
| `R-30-955` | A | app/test/screens/create_sheet_test.dart |
| `R-30-956` | A | app/test/screens/create_sheet_test.dart |
| `R-30-960` | A | app/test/screens/connection_screen_actions_test.dart |
| `R-30-961` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-30-962` | B | docs/90-implementation-plan.md:3710-3714 (checked checkbox) |
| `R-30-963` | B | docs/90-implementation-plan.md:3258-3263 (checked checkbox) |
| `R-30-964` | A | app/test/screens/actions_screen_test.dart:4 |
| `R-30-965` | B | docs/90-implementation-plan.md:3285-3290 (checked checkbox) |
| `R-30-966` | A | app/test/screens/actions_screen_test.dart:4 |
| `R-30-967` | B | docs/90-implementation-plan.md:3300-3303 (checked checkbox) |
| `R-30-968` | B | docs/90-implementation-plan.md:3304-3310 (checked checkbox) |

### `docs/31-mockups/01-welcome.md` (7 rules — B=4, C=1, E=2)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-31-01-01` | B | docs/90-implementation-plan.md:2537-2545 (checked checkbox) |
| `R-31-01-02` | B | docs/90-implementation-plan.md:2546-2549 (checked checkbox) |
| `R-31-01-03` | B | docs/90-implementation-plan.md:2537-2545 (checked checkbox) |
| `R-31-01-04` | B | docs/90-implementation-plan.md:2557-2563 (checked checkbox) |
| `R-31-01-05` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-01-07` | C | app/test/screens/welcome_screen_test.dart (sibling test of app/lib/screens/welcome_screen.dart; rule id not literally cited) |
| `R-31-01-08` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |

### `docs/31-mockups/02-pair-scan.md` (12 rules — A=2, B=5, E=5)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-31-02-01` | B | docs/90-implementation-plan.md:2576-2585 (checked checkbox) |
| `R-31-02-02` | A | app/test/services/pairing_test.dart:259 |
| `R-31-02-03` | B | docs/90-implementation-plan.md:2590-2596 (checked checkbox) |
| `R-31-02-04` | B | docs/90-implementation-plan.md:2616-2621 (checked checkbox) |
| `R-31-02-05` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-02-06` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-02-07` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-02-08` | B | docs/90-implementation-plan.md:2699-2704 (checked checkbox) |
| `R-31-02-09` | B | docs/90-implementation-plan.md:2564-2571 (checked checkbox) |
| `R-31-02-10` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-02-11` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-02-12` | A | app/test/screens/qr_scan_screen_test.dart:46 |

### `docs/31-mockups/03-pair-code.md` (10 rules — A=3, B=6, E=1)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-31-03-01` | B | docs/90-implementation-plan.md:2633-2643 (checked checkbox) |
| `R-31-03-02` | B | docs/90-implementation-plan.md:2671-2675 (checked checkbox) |
| `R-31-03-03` | A | app/test/screens/manual_pairing_screen_test.dart:4 |
| `R-31-03-04` | A | app/test/screens/manual_pairing_screen_test.dart:3 |
| `R-31-03-06` | B | docs/90-implementation-plan.md:2699-2704 (checked checkbox) |
| `R-31-03-07` | B | docs/90-implementation-plan.md:2699-2704 (checked checkbox) |
| `R-31-03-08` | B | docs/90-implementation-plan.md:2688-2693 (checked checkbox) |
| `R-31-03-09` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-03-10` | A | app/test/screens/manual_pairing_screen_test.dart:4 |
| `R-31-03-11` | B | docs/90-implementation-plan.md:2633-2643 (checked checkbox) |

### `docs/31-mockups/04-lock.md` (11 rules — A=7, C=4)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-31-04-01` | A | app/test/services/biometric_gate_test.dart:57 |
| `R-31-04-02` | C | app/test/services/biometric_gate_test.dart (sibling test of app/lib/services/biometric_gate.dart; rule id not literally cited) |
| `R-31-04-03` | C | app/test/screens/lock_screen_test.dart (sibling test of app/lib/screens/lock_screen.dart; rule id not literally cited) |
| `R-31-04-04` | C | app/test/screens/lock_screen_test.dart (sibling test of app/lib/screens/lock_screen.dart; rule id not literally cited) |
| `R-31-04-05` | A | app/test/screens/lock_screen_test.dart |
| `R-31-04-06` | A | app/test/screens/lock_screen_test.dart:4 |
| `R-31-04-07` | A | app/test/screens/lock_screen_test.dart |
| `R-31-04-08` | A | app/test/screens/lock_screen_test.dart |
| `R-31-04-09` | A | app/test/services/keystore_test.dart:60 |
| `R-31-04-10` | C | app/test/screens/lock_screen_test.dart (sibling test of app/lib/screens/lock_screen.dart; rule id not literally cited) |
| `R-31-04-11` | A | app/test/services/biometric_gate_test.dart:222 |

### `docs/31-mockups/05-host-list.md` (18 rules — A=8, B=2, C=4, E=4)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-31-05-01` | A | app/test/services/host_list_test.dart:1 |
| `R-31-05-02` | A | app/test/screens/host_list_screen_test.dart:3 |
| `R-31-05-03` | A | app/test/screens/host_list_screen_test.dart:3 |
| `R-31-05-04` | B | docs/90-implementation-plan.md:2997-3001 (checked checkbox) |
| `R-31-05-05` | A | app/test/screens/host_list_screen_test.dart |
| `R-31-05-06` | A | app/test/screens/host_list_screen_test.dart |
| `R-31-05-07` | A | app/test/screens/host_list_screen_test.dart:4 |
| `R-31-05-08` | A | app/test/screens/host_list_screen_test.dart:5 |
| `R-31-05-09` | B | docs/90-implementation-plan.md:3034-3041 (checked checkbox) |
| `R-31-05-10` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-05-11` | C | app/test/services/host_list_test.dart (sibling test of app/lib/services/host_list.dart; rule id not literally cited) |
| `R-31-05-12` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-05-13` | C | app/test/services/host_list_test.dart (sibling test of app/lib/services/host_list.dart; rule id not literally cited) |
| `R-31-05-15` | A | app/test/screens/host_list_screen_test.dart |
| `R-31-05-16` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-05-17` | C | app/test/screens/host_list_screen_test.dart (sibling test of app/lib/screens/host_list_screen.dart; rule id not literally cited) |
| `R-31-05-18` | C | app/test/screens/host_list_screen_test.dart (sibling test of app/lib/screens/host_list_screen.dart; rule id not literally cited) |
| `R-31-05-19` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |

### `docs/31-mockups/06-agent-list.md` (22 rules — A=10, B=5, C=5, E=2)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-31-06-01` | B | docs/90-implementation-plan.md:3067-3072 (checked checkbox) |
| `R-31-06-02` | A | app/test/screens/agent_list_screen_test.dart:2 |
| `R-31-06-03` | B | docs/90-implementation-plan.md:3089-3096 (checked checkbox) |
| `R-31-06-04` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-06-05` | A | app/test/screens/agent_list_screen_test.dart:243 |
| `R-31-06-06` | A | app/test/screens/agent_list_screen_test.dart:5 |
| `R-31-06-07` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-06-12` | A | app/test/services/agent_list_test.dart:6 |
| `R-31-06-13` | A | app/test/screens/agent_list_screen_test.dart |
| `R-31-06-14` | A | app/test/services/agent_list_test.dart:4 |
| `R-31-06-15` | A | app/test/services/agent_list_test.dart:5 |
| `R-31-06-16` | B | docs/90-implementation-plan.md:3168-3174 (checked checkbox) |
| `R-31-06-17` | B | docs/90-implementation-plan.md:3155-3160 (checked checkbox) |
| `R-31-06-18` | A | app/test/screens/agent_list_screen_test.dart:3 |
| `R-31-06-19` | A | app/test/screens/agent_list_screen_test.dart |
| `R-31-06-20` | C | app/test/screens/agent_list_screen_test.dart (sibling test of app/lib/screens/agent_list_screen.dart; rule id not literally cited) |
| `R-31-06-21` | B | docs/90-implementation-plan.md:3110-3113 (checked checkbox) |
| `R-31-06-22` | C | app/test/screens/agent_list_screen_test.dart (sibling test of app/lib/screens/agent_list_screen.dart; rule id not literally cited) |
| `R-31-06-23` | C | app/test/screens/agent_list_screen_test.dart (sibling test of app/lib/screens/agent_list_screen.dart; rule id not literally cited) |
| `R-31-06-24` | C | app/test/screens/agent_list_screen_test.dart (sibling test of app/lib/screens/agent_list_screen.dart; rule id not literally cited) |
| `R-31-06-25` | A | app/test/services/agent_list_test.dart:4 |
| `R-31-06-26` | C | app/test/services/agent_list_test.dart (sibling test of app/lib/services/agent_list.dart; rule id not literally cited) |

### `docs/31-mockups/07-notifications.md` (9 rules — A=9)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-31-07-01` | A | app/test/services/agent_status_test.dart:2 |
| `R-31-07-02` | A | app/test/services/agent_status_test.dart:3 |
| `R-31-07-03` | A | app/test/services/agent_status_test.dart:3 |
| `R-31-07-04` | A | app/test/services/agent_status_test.dart:4 |
| `R-31-07-05` | A | app/test/screens/app_shell_test.dart:4 |
| `R-31-07-06` | A | app/test/services/no_stale_notification_test.dart:2 |
| `R-31-07-07` | A | app/test/screens/notifications_screen_test.dart:1 |
| `R-31-07-08` | A | app/test/services/agent_list_test.dart:5 |
| `R-31-07-09` | A | app/test/screens/notifications_screen_test.dart:1 |

### `docs/31-mockups/08-terminal.md` (23 rules — A=12, B=5, E=6)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-31-08-01` | B | docs/90-implementation-plan.md:2812-2813 (checked checkbox) |
| `R-31-08-02` | A | app/test/services/terminal_test.dart:231 |
| `R-31-08-03` | A | app/test/services/terminal_test.dart:275 |
| `R-31-08-04` | B | docs/90-implementation-plan.md:2852-2854 (checked checkbox) |
| `R-31-08-05` | A | app/test/services/terminal_test.dart:422 |
| `R-31-08-06` | A | app/test/widgets/terminal_isolated_test.dart:483 |
| `R-31-08-07` | A | app/test/widgets/terminal_isolated_test.dart:170 |
| `R-31-08-08` | A | app/test/screens/single_tap_sends_nothing_test.dart:1 |
| `R-31-08-09` | A | app/integration_test/first_paint_test.dart:1 |
| `R-31-08-10` | B | docs/90-implementation-plan.md:2896-2898 (checked checkbox) |
| `R-31-08-11` | A | app/test/services/terminal_test.dart:293 |
| `R-31-08-12` | B | docs/90-implementation-plan.md:2888-2889 (checked checkbox) |
| `R-31-08-13` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-08-14` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-08-15` | A | app/test/widgets/terminal_isolated_test.dart |
| `R-31-08-16` | A | app/test/widgets/terminal_isolated_test.dart |
| `R-31-08-17` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-08-18` | A | app/test/services/terminal_test.dart:470 |
| `R-31-08-19` | A | app/test/widgets/terminal_isolated_test.dart |
| `R-31-08-20` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-08-21` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-08-22` | B | docs/90-implementation-plan.md:2881-2884 (checked checkbox) |
| `R-31-08-23` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |

### `docs/31-mockups/09-key-row.md` (historical coverage, pager amendment 2026-09-23)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-31-09-01` | B | docs/90-implementation-plan.md:2934-2935 (checked checkbox) |
| `R-31-09-02` | B | docs/90-implementation-plan.md:2946-2947 (checked checkbox) |
| `R-31-09-03` | B | docs/90-implementation-plan.md:2936-2938 (checked checkbox) |
| `R-31-09-04` | B | docs/90-implementation-plan.md:2944-2945 (checked checkbox) |
| `R-31-09-05` | B | docs/90-implementation-plan.md:2943-2943 (checked checkbox) |
| `R-31-09-06` | B | docs/90-implementation-plan.md:2952-2953 (checked checkbox) |
| `R-31-09-07` | B | docs/90-implementation-plan.md:2963-2964 (checked checkbox) |
| `R-31-09-08` | A | app/test/widgets/key_row_test.dart, group `KeyRow live typing (R-03-054)`: `ctrl and alt latch together and the next character is one ctrl+alt chord (R-03-120)` and `ctrl locked with alt held sends ctrl+alt+x then ctrl+y (R-03-120)` prove the one-call combined chord and the clearing rule; docs/90-implementation-plan.md:2941-2942 (checked checkbox) still records the single-modifier clearing |
| `R-31-09-09` | A | app/test/widgets/input_field_test.dart |
| `R-31-09-10` | A | app/test/widgets/key_row_test.dart |
| `R-31-09-11` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-09-12` | A | app/test/widgets/terminal_isolated_test.dart |
| `R-31-09-13` | B | docs/90-implementation-plan.md:2954-2955 (checked checkbox) |
| `R-31-09-14` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-09-15` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-09-16` | E | The 2026-09-23 amendment supersedes the old inner-scroll and pinned-column tests. R-31-09-40 now governs pager and overflow coverage. |
| `R-31-09-17` | E | The 2026-09-23 amendment supersedes the old single-grid geometry tests. R-31-09-40 now governs page geometry and overflow coverage. |
| `R-31-09-18` | A | app/test/widgets/key_row_test.dart |
| `R-31-09-19` | A | app/test/a11y/touch_target_test.dart:106; app/test/services/chord_latch_test.dart, group `ChordLatch latches ctrl and alt together (R-03-120)`: `a tap on the other modifier adds it and never replaces it`, `a third tap releases that modifier alone` and `the timeout releases the held modifiers and leaves a locked one` prove the added modifier and the per-modifier exits |
| `R-31-09-20` | retired | Retired 2026-09-10 per `R-03-116` with the Shortcuts palette it laid out; no test proves a retired rule. The test that covered it, `app/test/a11y/touch_target_test.dart`, now covers bank two under `R-31-09-24` as `R-03-117` lays it out |
| `R-31-09-23` | A | app/test/services/chord_latch_test.dart, group `ChordLatch latches ctrl and alt together (R-03-120)`: `one key clears the held modifiers and keeps the locked ones` and `latched reports every latched modifier in the ctrl, alt order a chord joins them` prove the per-modifier state; app/test/widgets/key_row_test.dart, `the hint strip names every latched modifier (R-03-120)` proves the combined hint. Amended 2026-09-10 per `R-03-120` |
| `R-31-09-25` | A | app/test/widgets/key_row_test.dart, group `KeyCap is the platform button (R-03-059, R-03-118)`: the Android and iOS cases assert the latched cap is a `FilledButton` and a `CupertinoButton.filled` whose label keeps its case, and a third case asserts the toggled semantics flag and the spoken `held`/`locked` sentence. Golden cases `ctrl_latched` and `ctrl_locked` in both themes, plus `ctrl_latched_ios`, in app/test/widgets/key_row_golden_test.dart. Added 2026-09-10 with the rule, per `R-03-118` |

### `docs/31-mockups/10-pane-actions.md` (10 rules — A=3, B=5, E=2)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-31-10-01` | B | docs/90-implementation-plan.md:3338-3339 (checked checkbox) |
| `R-31-10-02` | B | docs/90-implementation-plan.md:3338-3339 (checked checkbox) |
| `R-31-10-03` | B | docs/90-implementation-plan.md:3326-3328 (checked checkbox) |
| `R-31-10-05` | B | docs/90-implementation-plan.md:3326-3328 (checked checkbox) |
| `R-31-10-06` | A | app/test/screens/pane_actions_sheet_test.dart |
| `R-31-10-07` | A | app/test/screens/pane_actions_sheet_test.dart |
| `R-31-10-08` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-10-09` | A | app/test/screens/pane_actions_sheet_test.dart |
| `R-31-10-10` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-10-11` | B | docs/90-implementation-plan.md:3333-3337 (checked checkbox) |

### `docs/31-mockups/11-prompt-composer.md` (14 rules — A=8, B=1, C=4, E=1)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-31-11-01` | A | app/test/screens/prompt_composer_test.dart:4 |
| `R-31-11-02` | A | app/test/services/composer_test.dart:4 |
| `R-31-11-03` | A | app/test/services/composer_test.dart:2 |
| `R-31-11-04` | B | docs/90-implementation-plan.md:3344-3348 (checked checkbox) |
| `R-31-11-05` | A | app/test/screens/prompt_composer_test.dart:6 |
| `R-31-11-06` | A | app/test/services/composer_test.dart:4 |
| `R-31-11-07` | C | app/test/screens/prompt_composer_test.dart (sibling test of app/lib/screens/prompt_composer.dart; rule id not literally cited) |
| `R-31-11-08` | A | app/test/services/composer_test.dart:3 |
| `R-31-11-09` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-11-10` | C | app/test/screens/prompt_composer_test.dart (sibling test of app/lib/screens/prompt_composer.dart; rule id not literally cited) |
| `R-31-11-11` | A | app/test/services/composer_test.dart:3 |
| `R-31-11-12` | A | app/test/screens/prompt_composer_test.dart:3 |
| `R-31-11-13` | C | app/test/screens/prompt_composer_test.dart (sibling test of app/lib/screens/prompt_composer.dart; rule id not literally cited) |
| `R-31-11-14` | C | app/test/screens/prompt_composer_test.dart (sibling test of app/lib/screens/prompt_composer.dart; rule id not literally cited) |

### `docs/31-mockups/12-notifications.md` (14 rules — A=3, B=7, C=1, E=3)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-31-12-01` | A | app/test/services/no_pane_text_test.dart:2 |
| `R-31-12-02` | C | app/test/services/notifications_test.dart (sibling test of app/lib/services/notifications.dart; rule id not literally cited) |
| `R-31-12-03` | A | app/test/services/no_pane_text_test.dart:119 |
| `R-31-12-04` | B | docs/90-implementation-plan.md:3425-3427 (checked checkbox) |
| `R-31-12-05` | B | docs/90-implementation-plan.md:3407-3409 (checked checkbox) |
| `R-31-12-06` | B | docs/90-implementation-plan.md:3410-3412 (checked checkbox) |
| `R-31-12-07` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-12-08` | A | app/test/services/notifications_test.dart:5 |
| `R-31-12-09` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-12-10` | B | docs/90-implementation-plan.md:3435-3441 (checked checkbox) |
| `R-31-12-11` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-12-12` | B | docs/90-implementation-plan.md:3442-3445 (checked checkbox) |
| `R-31-12-13` | B | docs/90-implementation-plan.md:3463-3473 (checked checkbox) |
| `R-31-12-14` | B | docs/90-implementation-plan.md:3453-3462 (checked checkbox) |

### `docs/31-mockups/13-connection.md` (22 rules — A=10, B=8, C=1, E=3)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-31-13-01` | B | docs/90-implementation-plan.md:3642-3649 (checked checkbox) |
| `R-31-13-02` | A | app/test/services/relay_stats_test.dart:2 |
| `R-31-13-03` | B | docs/90-implementation-plan.md:3695-3702 (checked checkbox) |
| `R-31-13-04` | A | app/test/screens/connection_screen_test.dart:113 |
| `R-31-13-05` | B | docs/90-implementation-plan.md:3689-3694 (checked checkbox) |
| `R-31-13-06` | A | app/test/screens/connection_screen_test.dart:139 |
| `R-31-13-07` | B | docs/90-implementation-plan.md:3666-3674 (checked checkbox) |
| `R-31-13-08` | A | app/test/screens/connection_screen_test.dart:5 |
| `R-31-13-09` | A | app/test/screens/connection_screen_test.dart:93 |
| `R-31-13-10` | A | app/test/services/terminal_test.dart:314 |
| `R-31-13-11` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-13-12` | B | docs/90-implementation-plan.md:3703-3709 (checked checkbox) |
| `R-31-13-13` | A | app/test/screens/connection_screen_actions_test.dart:3 |
| `R-31-13-14` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-13-15` | A | app/test/screens/connection_screen_actions_test.dart:3 |
| `R-31-13-16` | B | docs/90-implementation-plan.md:3149-3152 (checked checkbox) |
| `R-31-13-17` | B | docs/90-implementation-plan.md:3149-3152 (checked checkbox) |
| `R-31-13-18` | B | docs/90-implementation-plan.md:3710-3714 (checked checkbox) |
| `R-31-13-19` | A | app/test/services/relay_stats_test.dart:2 |
| `R-31-13-20` | A | app/test/screens/connection_screen_actions_test.dart:2 |
| `R-31-13-21` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-13-22` | C | app/test/screens/connection_screen_test.dart (sibling test of app/lib/screens/connection_screen.dart; rule id not literally cited) |

### `docs/31-mockups/14-devices.md` (13 rules — A=3, B=9, E=1)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-31-14-01` | A | app/test/screens/device_list_screen_test.dart:3 |
| `R-31-14-02` | B | docs/90-implementation-plan.md:3524-3525 (checked checkbox) |
| `R-31-14-03` | B | docs/90-implementation-plan.md:3520-3521 (checked checkbox) |
| `R-31-14-04` | B | docs/90-implementation-plan.md:3522-3523 (checked checkbox) |
| `R-31-14-05` | B | docs/90-implementation-plan.md:3505-3506 (checked checkbox) |
| `R-31-14-06` | B | docs/90-implementation-plan.md:3501-3504 (checked checkbox) |
| `R-31-14-07` | B | docs/90-implementation-plan.md:3501-3504 (checked checkbox) |
| `R-31-14-08` | A | app/test/screens/device_list_screen_test.dart:4 |
| `R-31-14-09` | B | docs/90-implementation-plan.md:3507-3510 (checked checkbox) |
| `R-31-14-10` | B | docs/90-implementation-plan.md:3507-3510 (checked checkbox) |
| `R-31-14-11` | B | docs/90-implementation-plan.md:3507-3510 (checked checkbox) |
| `R-31-14-12` | A | app/test/services/device_list_test.dart:2 |
| `R-31-14-13` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |

### `docs/31-mockups/15-appearance.md` (17 rules — A=1, B=15, E=1)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-31-15-01` | B | docs/90-implementation-plan.md:3723-3728 (checked checkbox) |
| `R-31-15-02` | B | docs/90-implementation-plan.md:3729-3732 (checked checkbox) |
| `R-31-15-03` | B | docs/90-implementation-plan.md:3723-3728 (checked checkbox) |
| `R-31-15-04` | B | docs/90-implementation-plan.md:3733-3738 (checked checkbox) |
| `R-31-15-05` | B | docs/90-implementation-plan.md:3715-3722 (checked checkbox) |
| `R-31-15-06` | B | docs/90-implementation-plan.md:3715-3722 (checked checkbox) |
| `R-31-15-07` | B | docs/90-implementation-plan.md:3746-3753 (checked checkbox) |
| `R-31-15-08` | A | app/test/services/origin_change_test.dart:2 |
| `R-31-15-09` | B | docs/90-implementation-plan.md:3754-3757 (checked checkbox) |
| `R-31-15-10` | B | docs/90-implementation-plan.md:3793-3800 (checked checkbox) |
| `R-31-15-11` | B | docs/90-implementation-plan.md:3715-3722 (checked checkbox) |
| `R-31-15-12` | B | docs/90-implementation-plan.md:3739-3745 (checked checkbox) |
| `R-31-15-13` | B | docs/90-implementation-plan.md:3739-3745 (checked checkbox) |
| `R-31-15-14` | B | docs/90-implementation-plan.md:3739-3745 (checked checkbox) |
| `R-31-15-15` | B | docs/90-implementation-plan.md:3739-3745 (checked checkbox) |
| `R-31-15-16` | B | docs/90-implementation-plan.md:3770-3774 (checked checkbox) |
| `R-31-15-17` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |

### `docs/31-mockups/16-host-popup.md` (33 rules — A=21, B=9, E=3)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-31-16-01` | B | docs/90-implementation-plan.md:1898-1906 (checked checkbox) |
| `R-31-16-02` | A | crates/herdr-relay/src/popup.rs:1581 |
| `R-31-16-03` | A | crates/herdr-relay/tests/popup_once.rs:173 |
| `R-31-16-04` | A | crates/herdr-relay/tests/popup_once.rs:2 |
| `R-31-16-05` | A | crates/herdr-relay/src/popup.rs:1628 |
| `R-31-16-06` | A | crates/herdr-relay/src/popup.rs:1527 |
| `R-31-16-07` | B | docs/90-implementation-plan.md:1939-1943 (checked checkbox) |
| `R-31-16-08` | B | docs/90-implementation-plan.md:1949-1952 (checked checkbox) |
| `R-31-16-09` | A | crates/herdr-relay/src/popup.rs:1686 |
| `R-31-16-10` | B | docs/90-implementation-plan.md:1953-1956 (checked checkbox) |
| `R-31-16-11` | B | docs/90-implementation-plan.md:1957-1961 (checked checkbox) |
| `R-31-16-12` | B | docs/90-implementation-plan.md:2086-2088 (checked checkbox) |
| `R-31-16-13` | A | crates/herdr-relay/src/popup.rs:1587 |
| `R-31-16-14` | B | docs/90-implementation-plan.md:1962-1965 (checked checkbox) |
| `R-31-16-15` | A | crates/herdr-relay/src/popup.rs:1850 |
| `R-31-16-16` | A | crates/herdr-relay/src/popup.rs:1867 |
| `R-31-16-17` | A | crates/herdr-relay/tests/popup.rs |
| `R-31-16-18` | B | docs/90-implementation-plan.md:1980-1992 (checked checkbox) |
| `R-31-16-19` | A | crates/herdr-relay/src/popup.rs:1882 |
| `R-31-16-20` | A | crates/herdr-relay/tests/popup.rs |
| `R-31-16-21` | A | crates/herdr-relay/tests/popup.rs |
| `R-31-16-22` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-16-23` | A | crates/herdr-relay/tests/popup.rs |
| `R-31-16-24` | A | crates/herdr-relay/src/popup.rs:1845 |
| `R-31-16-25` | B | docs/90-implementation-plan.md:1919-1925 (checked checkbox) |
| `R-31-16-26` | A | crates/herdr-relay/tests/popup_once.rs:173 |
| `R-31-16-27` | A | crates/herdr-relay/src/popup.rs:1904 |
| `R-31-16-28` | A | crates/herdr-relay/src/popup.rs:1889 |
| `R-31-16-29` | A | crates/herdr-relay/src/popup.rs:1663 |
| `R-31-16-30` | A | crates/herdr-relay/tests/popup.rs |
| `R-31-16-31` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-16-32` | A | crates/herdr-relay/src/popup.rs:1686 |
| `R-31-16-33` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |

### `docs/31-mockups/17-create.md` (11 rules — A=5, B=4, C=1, E=1)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-31-17-01` | B | docs/90-implementation-plan.md:3125-3131 (checked checkbox) |
| `R-31-17-02` | A | app/test/screens/create_sheet_test.dart:3 |
| `R-31-17-03` | A | app/test/screens/create_sheet_test.dart:3 |
| `R-31-17-04` | B | docs/90-implementation-plan.md:3125-3131 (checked checkbox) |
| `R-31-17-05` | A | app/test/screens/create_sheet_test.dart |
| `R-31-17-06` | A | app/test/screens/create_sheet_test.dart |
| `R-31-17-07` | A | app/test/screens/create_sheet_test.dart:5 |
| `R-31-17-08` | B | docs/90-implementation-plan.md:3139-3145 (checked checkbox) |
| `R-31-17-09` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-17-10` | C | app/test/screens/create_sheet_test.dart (sibling test of app/lib/screens/create_sheet.dart; rule id not literally cited) |
| `R-31-17-11` | B | docs/90-implementation-plan.md:3132-3138 (checked checkbox) |

### `docs/31-mockups/18-actions.md` (17 rules — A=2, B=10, E=5)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-31-18-01` | B | docs/90-implementation-plan.md:3229-3233 (checked checkbox) |
| `R-31-18-02` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-18-03` | B | docs/90-implementation-plan.md:3242-3246 (checked checkbox) |
| `R-31-18-04` | B | docs/90-implementation-plan.md:3242-3246 (checked checkbox) |
| `R-31-18-05` | B | docs/90-implementation-plan.md:3269-3272 (checked checkbox) |
| `R-31-18-06` | B | docs/90-implementation-plan.md:3273-3277 (checked checkbox) |
| `R-31-18-07` | B | docs/90-implementation-plan.md:3273-3277 (checked checkbox) |
| `R-31-18-08` | B | docs/90-implementation-plan.md:3285-3290 (checked checkbox) |
| `R-31-18-09` | B | docs/90-implementation-plan.md:3304-3310 (checked checkbox) |
| `R-31-18-10` | B | docs/90-implementation-plan.md:3300-3303 (checked checkbox) |
| `R-31-18-11` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-18-12` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-18-13` | A | app/test/screens/actions_screen_test.dart:305 |
| `R-31-18-14` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-31-18-15` | B | docs/90-implementation-plan.md:3278-3284 (checked checkbox) |
| `R-31-18-16` | A | app/test/screens/actions_screen_test.dart:6 |
| `R-31-18-17` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |

### `docs/31-mockups/19-about.md` (15 rules — A=9, B=3, C=3)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-31-19-01` | B | docs/90-implementation-plan.md:3801-3806 (checked checkbox) |
| `R-31-19-02` | C | app/test/screens/about_screen_test.dart (sibling test of app/lib/screens/about_screen.dart; rule id not literally cited) |
| `R-31-19-03` | A | app/test/screens/about_screen_test.dart |
| `R-31-19-04` | C | app/test/screens/about_screen_test.dart (sibling test of app/lib/screens/about_screen.dart; rule id not literally cited) |
| `R-31-19-05` | A | app/test/screens/about_screen_test.dart:37 |
| `R-31-19-06` | B | docs/90-implementation-plan.md:3793-3800 (checked checkbox) |
| `R-31-19-07` | A | app/test/screens/about_screen_test.dart |
| `R-31-19-08` | A | app/test/screens/about_screen_test.dart |
| `R-31-19-09` | A | app/test/screens/about_screen_test.dart |
| `R-31-19-10` | A | app/test/screens/about_screen_test.dart |
| `R-31-19-11` | B | docs/90-implementation-plan.md:3801-3806 (checked checkbox) |
| `R-31-19-12` | A | app/test/screens/about_screen_test.dart |
| `R-31-19-13` | C | app/test/screens/about_screen_test.dart (sibling test of app/lib/screens/about_screen.dart; rule id not literally cited) |
| `R-31-19-14` | A | app/test/screens/about_screen_test.dart:2 |
| `R-31-19-15` | A | app/test/screens/about_screen_test.dart:62 |

### `docs/32-design-language.md` (175 rules — A=33, B=11, C=20, E=111)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-32-001` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-002` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-003` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-004` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-005` | A | app/test/widgets/theme/no_literals_test.dart:3-5 |
| `R-32-010` | A | app/test/services/app_settings_test.dart |
| `R-32-011` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-012` | A | app/test/screens/lock_screen_golden_test.dart:3 |
| `R-32-013` | A | app/test/services/app_settings_test.dart |
| `R-32-014` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-015` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-016` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-017` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-100` | A | app/test/widgets/theme/app_color_test.dart |
| `R-32-101` | A | app/test/widgets/theme/app_color_test.dart |
| `R-32-102` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-110` | A | app/test/widgets/theme/no_literals_test.dart:3-5 |
| `R-32-111` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-112` | A | app/test/widgets/input_field_test.dart |
| `R-32-113` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-114` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-115` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-116` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-120` | A | app/test/widgets/theme/no_literals_test.dart:3-5 |
| `R-32-121` | A | app/test/widgets/theme/contrast_test.dart:103 |
| `R-32-122` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-123` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-124` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-125` | A | app/test/widgets/theme/app_color_test.dart |
| `R-32-126` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-127` | A | app/test/widgets/app_filled_button_test.dart |
| `R-32-130` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-131` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-132` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-133` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-134` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-140` | A | app/test/widgets/terminal_isolated_test.dart:71 |
| `R-32-141` | A | app/test/widgets/theme/app_color_test.dart |
| `R-32-142` | A | app/test/widgets/theme/contrast_test.dart:338 |
| `R-32-143` | A | app/test/widgets/theme/contrast_test.dart:282-283 |
| `R-32-144` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-145` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-146` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-150` | A | app/test/widgets/theme/contrast_test.dart:3 |
| `R-32-151` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-152` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-153` | A | app/test/widgets/theme/contrast_test.dart:5 |
| `R-32-200` | A | app/test/widgets/theme/app_type_test.dart |
| `R-32-201` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-202` | A | app/test/widgets/theme/app_type_test.dart |
| `R-32-203` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-204` | A | app/test/widgets/theme/app_type_test.dart |
| `R-32-205` | C | app/test/screens/welcome_screen_test.dart (sibling test of app/lib/screens/welcome_screen.dart; rule id not literally cited) |
| `R-32-206` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-207` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-208` | B | docs/90-implementation-plan.md:3723-3728 (checked checkbox) |
| `R-32-209` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-210` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-211` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-300` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-301` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-302` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-310` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-320` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-321` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-322` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-330` | C | app/test/screens/app_shell_test.dart (sibling test of app/lib/screens/app_shell.dart; rule id not literally cited) |
| `R-32-331` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-350` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-360` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-361` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-362` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-363` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-400` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-401` | C | app/test/screens/app_shell_test.dart (sibling test of app/lib/screens/app_shell.dart; rule id not literally cited) |
| `R-32-402` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-403` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-404` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-405` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-406` | B | docs/90-implementation-plan.md:3216-3222 (checked checkbox) |
| `R-32-407` | A | app/test/screens/lock_screen_test.dart:4 |
| `R-32-410` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-411` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-412` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-413` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-414` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-415` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-416` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-417` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-418` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-419` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-420` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-421` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-422` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-423` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-500` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-501` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-502` | C | app/test/screens/create_sheet_test.dart (sibling test of app/lib/screens/create_sheet.dart; rule id not literally cited) |
| `R-32-503` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-504` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-505` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-506` | A | app/test/widgets/treatments_test.dart |
| `R-32-510` | C | app/test/screens/agent_list_screen_test.dart (sibling test of app/lib/screens/agent_list_screen.dart; rule id not literally cited) |
| `R-32-511` | C | app/test/screens/agent_list_screen_test.dart (sibling test of app/lib/screens/agent_list_screen.dart; rule id not literally cited) |
| `R-32-512` | C | app/test/screens/agent_list_screen_test.dart (sibling test of app/lib/screens/agent_list_screen.dart; rule id not literally cited) |
| `R-32-515` | C | app/test/screens/device_list_screen_test.dart (sibling test of app/lib/screens/device_list_screen.dart; rule id not literally cited) |
| `R-32-516` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-518` | B | docs/90-implementation-plan.md:3216-3222 (checked checkbox) |
| `R-32-520` | B | docs/90-implementation-plan.md:3114-3119 (checked checkbox) |
| `R-32-521` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-522` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-525` | A | app/test/widgets/app_filled_button_test.dart |
| `R-32-526` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-527` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-530` | B | docs/90-implementation-plan.md:3223-3228 (checked checkbox) |
| `R-32-531` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-532` | C | app/test/screens/manual_pairing_screen_test.dart (sibling test of app/lib/screens/manual_pairing_screen.dart; rule id not literally cited) |
| `R-32-535` | A | app/test/widgets/key_row_test.dart |
| `R-32-536` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-540` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-542` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-545` | C | app/test/screens/qr_scan_screen_test.dart (sibling test of app/lib/screens/qr_scan_screen.dart; rule id not literally cited) |
| `R-32-546` | C | app/test/screens/create_sheet_test.dart (sibling test of app/lib/screens/create_sheet.dart; rule id not literally cited) |
| `R-32-547` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-550` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-551` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-553` | C | app/test/screens/agent_list_screen_test.dart (sibling test of app/lib/screens/agent_list_screen.dart; rule id not literally cited) |
| `R-32-555` | C | app/test/screens/agent_list_screen_test.dart (sibling test of app/lib/screens/agent_list_screen.dart; rule id not literally cited) |
| `R-32-558` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-559` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-560` | C | app/test/screens/agent_list_screen_test.dart (sibling test of app/lib/screens/agent_list_screen.dart; rule id not literally cited) |
| `R-32-561` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-562` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-563` | B | docs/90-implementation-plan.md:3168-3174 (checked checkbox) |
| `R-32-564` | C | app/test/screens/agent_list_screen_test.dart (sibling test of app/lib/screens/agent_list_screen.dart; rule id not literally cited) |
| `R-32-565` | C | app/test/screens/agent_list_screen_test.dart (sibling test of app/lib/screens/agent_list_screen.dart; rule id not literally cited) |
| `R-32-566` | C | app/test/screens/agent_list_screen_test.dart (sibling test of app/lib/screens/agent_list_screen.dart; rule id not literally cited) |
| `R-32-567` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-568` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-569` | C | app/test/screens/agent_list_screen_test.dart (sibling test of app/lib/screens/agent_list_screen.dart; rule id not literally cited) |
| `R-32-570` | B | docs/90-implementation-plan.md:3168-3174 (checked checkbox) |
| `R-32-571` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-572` | C | app/test/screens/agent_list_screen_test.dart (sibling test of app/lib/screens/agent_list_screen.dart; rule id not literally cited) |
| `R-32-573` | B | docs/90-implementation-plan.md:3155-3160 (checked checkbox) |
| `R-32-574` | C | app/test/screens/agent_list_screen_test.dart (sibling test of app/lib/screens/agent_list_screen.dart; rule id not literally cited) |
| `R-32-575` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-576` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-577` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-578` | B | docs/90-implementation-plan.md:3005-3010 (checked checkbox) |
| `R-32-579` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-580` | A | app/test/screens/agent_list_screen_test.dart:5 |
| `R-32-581` | A | app/test/services/no_dismissible_test.dart:1 |
| `R-32-582` | B | docs/90-implementation-plan.md:3114-3119 (checked checkbox) |
| `R-32-583` | B | docs/90-implementation-plan.md:3114-3119 (checked checkbox) |
| `R-32-584` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-585` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-586` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-588` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-589` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-600` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-601` | A | app/test/a11y/reduce_motion_test.dart:164 |
| `R-32-602` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-603` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-604` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-605` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-606` | A | app/test/a11y/reduce_motion_test.dart:6 |
| `R-32-607` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-700` | A | crates/herdr-relay/src/popup.rs |
| `R-32-701` | A | crates/herdr-relay/src/popup.rs |
| `R-32-702` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-703` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-704` | A | crates/herdr-relay/src/popup.rs:1867 |
| `R-32-705` | C | app/test/screens/host_list_screen_test.dart (sibling test of app/lib/screens/host_list_screen.dart; rule id not literally cited) |
| `R-32-706` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-32-707` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |

### `docs/33-platform-chrome.md` (65 rules — A=11, B=7, C=10, D=1, E=36)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-33-001` | B | docs/90-implementation-plan.md:932-935 (checked checkbox) |
| `R-33-002` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-003` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-004` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-005` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-006` | B | docs/90-implementation-plan.md:932-935 (checked checkbox) |
| `R-33-007` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-008` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-009` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-010` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-012` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-013` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-015` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-017` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-021` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-022` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-023` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-024` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-025` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-026` | A | app/test/widgets/terminal_isolated_test.dart:23 |
| `R-33-027` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-028` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-029` | C | app/test/screens/app_shell_test.dart (sibling test of app/lib/screens/app_shell.dart; rule id not literally cited) |
| `R-33-030` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-031` | A | app/test/widgets/theme/chrome_contrast_test.dart:101-106 |
| `R-33-032` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-033` | B | docs/90-implementation-plan.md:932-935 (checked checkbox) |
| `R-33-034` | B | docs/90-implementation-plan.md:3329-3332 (checked checkbox) |
| `R-33-035` | C | app/test/screens/app_shell_test.dart (sibling test of app/lib/screens/app_shell.dart; rule id not literally cited) |
| `R-33-036` | C | app/test/screens/app_shell_test.dart (sibling test of app/lib/screens/app_shell.dart; rule id not literally cited) |
| `R-33-037` | C | app/test/screens/app_shell_test.dart (sibling test of app/lib/screens/app_shell.dart; rule id not literally cited) |
| `R-33-038` | C | app/test/screens/app_shell_test.dart (sibling test of app/lib/screens/app_shell.dart; rule id not literally cited) |
| `R-33-039` | A | app/test/a11y/touch_target_test.dart |
| `R-33-040` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-041` | B | docs/90-implementation-plan.md:932-935 (checked checkbox) |
| `R-33-042` | A | app/test/widgets/theme/contrast_test.dart:8-9 |
| `R-33-043` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-044` | A | app/test/widgets/theme/chrome_contrast_test.dart:5 |
| `R-33-045` | A | app/test/widgets/theme/chrome_contrast_test.dart:41 |
| `R-33-046` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-047` | A | app/test/widgets/theme/chrome_contrast_test.dart:5 |
| `R-33-048` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-049` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-050` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-051` | B | docs/90-implementation-plan.md:3911-3924 (checked checkbox) |
| `R-33-052` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-053` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-054` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-055` | A | app/test/widgets/terminal_isolated_test.dart:25 |
| `R-33-056` | A | app/test/widgets/terminal_isolated_test.dart:26 |
| `R-33-057` | A | app/test/widgets/terminal_isolated_test.dart:26 |
| `R-33-058` | A | app/test/widgets/terminal_isolated_test.dart |
| `R-33-060` | B | docs/90-implementation-plan.md:2829-2832 (checked checkbox) |
| `R-33-061` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-062` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-063` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-066` | D | enforced by standing gate: docs/40-repo-tooling.md §8.4 rule-consistency audit script |
| `R-33-068` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-069` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-070` | C | app/test/screens/app_shell_test.dart (sibling test of app/lib/screens/app_shell.dart; rule id not literally cited) |
| `R-33-071` | C | app/test/screens/app_shell_test.dart (sibling test of app/lib/screens/app_shell.dart; rule id not literally cited) |
| `R-33-072` | C | app/test/screens/device_list_screen_test.dart (sibling test of app/lib/screens/device_list_screen.dart; rule id not literally cited) |
| `R-33-073` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-33-074` | C | app/test/screens/qr_scan_screen_test.dart (sibling test of app/lib/screens/qr_scan_screen.dart; rule id not literally cited) |
| `R-33-075` | C | app/test/screens/prompt_composer_test.dart (sibling test of app/lib/screens/prompt_composer.dart; rule id not literally cited) |

### `docs/40-repo-tooling.md` (57 rules — A=8, B=21, D=10, E=18)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-40-001` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-40-002` | B | docs/90-implementation-plan.md:972-975 (checked checkbox) |
| `R-40-003` | B | docs/90-implementation-plan.md:969-970 (checked checkbox) |
| `R-40-004` | B | docs/90-implementation-plan.md:969-970 (checked checkbox) |
| `R-40-005` | B | docs/90-implementation-plan.md:971-971 (checked checkbox) |
| `R-40-006` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-40-007` | B | docs/90-implementation-plan.md:972-975 (checked checkbox) |
| `R-40-008` | B | docs/90-implementation-plan.md:972-975 (checked checkbox) |
| `R-40-009` | B | docs/90-implementation-plan.md:972-975 (checked checkbox) |
| `R-40-010` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-40-011` | B | docs/90-implementation-plan.md:972-975 (checked checkbox) |
| `R-40-012` | B | docs/90-implementation-plan.md:969-970 (checked checkbox) |
| `R-40-013` | B | docs/90-implementation-plan.md:936-936 (checked checkbox) |
| `R-40-014` | B | docs/90-implementation-plan.md:936-936 (checked checkbox) |
| `R-40-015` | B | docs/90-implementation-plan.md:2091-2093 (checked checkbox) |
| `R-40-016` | B | docs/90-implementation-plan.md:2086-2088 (checked checkbox) |
| `R-40-017` | B | docs/90-implementation-plan.md:2089-2090 (checked checkbox) |
| `R-40-018` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-40-019` | D | enforced by standing gate: cargo fmt --check |
| `R-40-020` | D | enforced by standing gate: npx markdownlint-cli2@0.23.2 "**/*.md" |
| `R-40-021` | D | enforced by standing gate: npx markdownlint-cli2@0.23.2 "**/*.md" |
| `R-40-022` | B | docs/90-implementation-plan.md:1009-1010 (checked checkbox) |
| `R-40-023` | B | docs/90-implementation-plan.md:1013-1014 (checked checkbox) |
| `R-40-024` | B | docs/90-implementation-plan.md:985-987 (checked checkbox) |
| `R-40-025` | B | docs/90-implementation-plan.md:937-944 (checked checkbox) |
| `R-40-026` | B | docs/90-implementation-plan.md:937-944 (checked checkbox) |
| `R-40-027` | D | enforced by standing gate: lychee 0.24.2 (docs/40-repo-tooling.md §8.2) |
| `R-40-028` | B | docs/90-implementation-plan.md:985-987 (checked checkbox) |
| `R-40-029` | A | crates/herdr-relay/tests/input_map.rs:4 |
| `R-40-030` | A | crates/herdr-relay/tests/one_pane.rs:208 |
| `R-40-031` | A | crates/herdr-relay-proto/tests/handle.rs:4 |
| `R-40-032` | A | crates/herdr-relay-hub/tests/forward_verbatim.rs:2 |
| `R-40-033` | A | crates/herdr-relay-hub/tests/integration.rs:3 |
| `R-40-034` | A | app/test/services/hmac_blake2s_vectors_test.dart:3 |
| `R-40-035` | A | app/test/screens/settings_screen_test.dart |
| `R-40-036` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-40-037` | A | app/test/services/hmac_blake2s_vectors_test.dart:3 |
| `R-40-038` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-40-039` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-40-040` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-40-041` | B | docs/90-implementation-plan.md:1015-1022 (checked checkbox) |
| `R-40-042` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-40-043` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-40-044` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-40-045` | D | enforced by standing gate: docs/40-repo-tooling.md (§8.7.1 + §8.7.2 audit scripts) |
| `R-40-046` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-40-047` | D | enforced by standing gate: docs/40-repo-tooling.md (§8.7.5 audit script) |
| `R-40-048` | D | enforced by standing gate: docs/40-repo-tooling.md (§8.7.6 audit script) |
| `R-40-049` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-40-050` | D | enforced by standing gate: docs/40-repo-tooling.md §8.4 rule-consistency audit script |
| `R-40-051` | D | enforced by standing gate: npx markdownlint-cli2@0.23.2 "**/*.md" |
| `R-40-052` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-40-053` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-40-054` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-40-055` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-40-056` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-40-057` | D | enforced by standing gate: jsdom + mermaid.parse() browser-free check (docs/40-repo-tooling.md §8.3) |

### `docs/41-code-standards.md` (167 rules — A=20, B=12, C=4, D=19, E=112)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-41-001` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-002` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-003` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-004` | D | enforced by standing gate: cargo clippy --all-targets --all-features -- -D warnings (rustc non_camel_case_types, Rust PascalCase clause only) |
| `R-41-005` | D | enforced by standing gate: cargo clippy --all-targets --all-features -- -D warnings (rustc non_snake_case, Rust snake_case clause only) |
| `R-41-006` | D | enforced by standing gate: cargo clippy --all-targets --all-features -- -D warnings (rustc non_upper_case_globals, Rust UPPER_SNAKE_CASE clause only) |
| `R-41-007` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-008` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-009` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-010` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-011` | B | docs/90-implementation-plan.md:1373-1397 (checked checkbox) |
| `R-41-012` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-013` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-014` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-015` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-016` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-017` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-018` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-019` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-020` | B | docs/90-implementation-plan.md:2512-2520 (checked checkbox) |
| `R-41-021` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-022` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-023` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-024` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-025` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-026` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-027` | C | app/test/services/keystore_test.dart (sibling test of app/lib/services/keystore.dart; rule id not literally cited) |
| `R-41-028` | C | app/test/services/keystore_test.dart (sibling test of app/lib/services/keystore.dart; rule id not literally cited) |
| `R-41-029` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-030` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-031` | A | app/test/services/relay_test.dart |
| `R-41-032` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-033` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-034` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-035` | B | docs/90-implementation-plan.md:3793-3800 (checked checkbox) |
| `R-41-036` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-037` | A | crates/herdr-relay/src/watch/requests.rs:306 |
| `R-41-038` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-039` | A | app/test/models/frame_size_test.dart:3 |
| `R-41-040` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-041` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-042` | A | app/test/a11y/reduce_motion_test.dart:10 |
| `R-41-043` | B | docs/90-implementation-plan.md:1325-1329 (checked checkbox) |
| `R-41-044` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-045` | D | enforced by standing gate: cargo fmt --check |
| `R-41-046` | D | enforced by standing gate: cargo fmt --check (Rust files); markdownlint-cli2 MD047 default (Markdown files) |
| `R-41-047` | D | enforced by standing gate: cargo fmt --check (Rust files); markdownlint-cli2 MD009 default permits the documented Markdown hard-break exemption |
| `R-41-048` | D | enforced by standing gate: cargo fmt --check (Rust files); markdownlint-cli2 MD010 default (Markdown files) |
| `R-41-049` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-050` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-051` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-054` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-055` | A | crates/herdr-relay/tests/posix/test-ensure-service.sh |
| `R-41-056` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-057` | A | crates/herdr-relay/tests/posix/test-ensure-service.sh |
| `R-41-058` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-059` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-060` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-061` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-062` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-063` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-064` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-065` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-066` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-067` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-068` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-069` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-070` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-071` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-075` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-076` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-077` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-078` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-079` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-080` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-081` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-082` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-083` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-084` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-085` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-086` | D | enforced by standing gate: cargo fmt --check |
| `R-41-087` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-088` | D | enforced by standing gate: cd app && dart analyze --fatal-infos --fatal-warnings . |
| `R-41-089` | D | enforced by standing gate: cd app && dart analyze --fatal-infos --fatal-warnings . |
| `R-41-090` | D | enforced by standing gate: cd app && dart analyze --fatal-infos --fatal-warnings . |
| `R-41-091` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-092` | B | docs/90-implementation-plan.md:2510-2511 (checked checkbox) |
| `R-41-093` | D | enforced by standing gate: cd app && dart analyze --fatal-infos --fatal-warnings . |
| `R-41-094` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-095` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-096` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-097` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-098` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-099` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-100` | C | app/test/services/terminal_test.dart (sibling test of app/lib/services/terminal.dart; rule id not literally cited) |
| `R-41-101` | A | app/test/screens/host_list_screen_test.dart |
| `R-41-102` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-103` | C | app/test/services/keystore_test.dart (sibling test of app/lib/services/keystore.dart; rule id not literally cited) |
| `R-41-104` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-105` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-106` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-107` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-108` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-109` | B | docs/90-implementation-plan.md:949-950 (checked checkbox) |
| `R-41-110` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-111` | A | app/test/widgets/theme/no_literals_test.dart:4 |
| `R-41-112` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-113` | D | enforced by standing gate: cargo fmt --check |
| `R-41-114` | D | enforced by standing gate: cargo fmt --check (.github/workflows/ci.yml:25) |
| `R-41-115` | D | enforced by standing gate: cargo clippy --all-targets --all-features -- -D warnings |
| `R-41-116` | A | crates/herdr-relay-hub/tests/support/mod.rs:16 |
| `R-41-117` | D | enforced by standing gate: cargo clippy --all-targets --all-features -- -D warnings |
| `R-41-118` | D | enforced by standing gate: cargo clippy --all-targets --all-features -- -D warnings |
| `R-41-119` | D | enforced by standing gate: cargo clippy --all-targets --all-features -- -D warnings |
| `R-41-120` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-121` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-122` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-123` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-124` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-125` | A | crates/herdr-relay/src/watch/devices.rs:271,288 |
| `R-41-126` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-127` | D | enforced by standing gate: cargo clippy --all-targets --all-features -- -D warnings |
| `R-41-128` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-129` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-130` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-131` | A | crates/herdr-relay/src/config.rs:439 |
| `R-41-132` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-133` | B | docs/90-implementation-plan.md:2133-2135 (checked checkbox) |
| `R-41-134` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-135` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-136` | A | crates/herdr-relay/tests/posix/test-ensure-service.sh:5 |
| `R-41-137` | A | crates/herdr-relay/tests/posix/test-ensure-service.sh |
| `R-41-138` | A | crates/herdr-relay/tests/windows/test-plugin-root.ps1:7 |
| `R-41-139` | B | docs/90-implementation-plan.md:2091-2093 (checked checkbox) |
| `R-41-140` | A | crates/herdr-relay/tests/windows/test-plugin-root.ps1:48 |
| `R-41-141` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-142` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-143` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-144` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-145` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-146` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-147` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-148` | B | docs/90-implementation-plan.md:2110-2130 (checked checkbox) |
| `R-41-149` | B | docs/90-implementation-plan.md:2110-2130 (checked checkbox) |
| `R-41-150` | B | docs/90-implementation-plan.md:2110-2130 (checked checkbox) |
| `R-41-151` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-152` | B | docs/90-implementation-plan.md:2110-2130 (checked checkbox) |
| `R-41-153` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-154` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-155` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-156` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-157` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-158` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-159` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-160` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-161` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-162` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-163` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-164` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-165` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-166` | A | crates/herdr-relay-proto/src/codes.rs:217,228 |
| `R-41-167` | A | crates/herdr-relay/tests/revision_gate.rs:2 |
| `R-41-168` | A | crates/herdr-relay/tests/one_pane.rs:161-162 |
| `R-41-169` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-170` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-41-171` | A | app/test/services/terminal_test.dart:128-129,481-482 |
| `R-41-172` | A | crates/herdr-relay/tests/revision_gate.rs:2 |

### `docs/90-implementation-plan.md` (24 rules — A=5, B=6, D=1, E=12)

| Rule | Cat. | Proof |
| --- | --- | --- |
| `R-90-001` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-90-002` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-90-003` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-90-004` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-90-005` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-90-006` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-90-007` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-90-008` | A | crates/herdr-relay-proto/tests/phrase.rs:8 |
| `R-90-009` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-90-010` | A | app/test/widgets/terminal_isolated_test.dart:483 |
| `R-90-011` | A | app/test/screens/lock_screen_golden_test.dart:2 |
| `R-90-012` | B | docs/90-implementation-plan.md:965-966 (checked checkbox) |
| `R-90-013` | B | docs/90-implementation-plan.md:4024-4031 (checked checkbox) |
| `R-90-014` | B | docs/90-implementation-plan.md:3405-3406 (checked checkbox) |
| `R-90-015` | B | docs/90-implementation-plan.md:1015-1022 (checked checkbox) |
| `R-90-016` | A | app/integration_test/spike_render_test.dart:21 |
| `R-90-017` | B | docs/90-implementation-plan.md:2146-2153 (checked checkbox) |
| `R-90-018` | B | docs/90-implementation-plan.md:2644-2662 (checked checkbox) |
| `R-90-019` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-90-020` | D | enforced by standing gate: docs/40-repo-tooling.md §8.5 documentation-completeness checklist item (docs/40-repo-tooling.md:1318-1319, names R-90-020 by id) |
| `R-90-021` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-90-022` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-90-023` | E | UNRESOLVED — no test citation, no recorded Verified: checkbox, no sibling test file, no matched gate |
| `R-90-024` | A | app/integration_test/first_paint_test.dart:11 |
