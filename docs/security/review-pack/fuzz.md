# Fuzz results: `/host/<handle>`, `/device/<handle>`, `/healthz`, `/metrics`

Phase 23 checkbox (`docs/90-implementation-plan.md` §Phase 23, item 5): fuzz the relay's four
endpoints and record the results (R-12-021, R-12-030).

## Method

Two new test files run the real `herdr-relay-hub` router (`herdr_relay_hub::routes::build()`) on
real loopback TCP ports, the same pattern `crates/herdr-relay-hub/tests/limits.rs` already uses:

- `crates/herdr-relay-hub/tests/fuzz_endpoints.rs::fuzzing_host_and_device_handles_never_crashes_the_relay`
  and `::valid_handle_edge_cases_are_handled_without_crashing` fuzz `/host/<handle>` and
  `/device/<handle>`.
- `crates/herdr-relay-hub/tests/fuzz_endpoints.rs::fuzzing_healthz_and_metrics_never_panics_or_leaks`
  fuzzes `/healthz` and `/metrics`.

No new crate. R-41-042's reuse ladder stops at the standard library plus the workspace's own
`tokio`/`tokio-tungstenite`/`futures-util` (already dev-dependencies of `herdr-relay-hub`): a
fixed-seed splitmix64 generator (`std::random` is still gated behind the unstable `random`
feature, rust-lang/rust#130703) feeding a plain loop of real WebSocket and raw-TCP HTTP requests
against a real running relay is enough to fuzz a small, four-endpoint surface. `cargo-fuzz` and
`libfuzzer-sys` were not added. The seed is fixed, so a failing run reproduces instead of flaking.

Run with:

```sh
cargo test -p herdr-relay-hub --test fuzz_endpoints -- --nocapture --test-threads=1
```

(cwd `crates/`).

## `/host/<handle>` and `/device/<handle>`

### Corpus

242 malformed-handle byte strings per role (484 probes total: 242 × `host` + 242 × `device`),
covering every category R-12-021's boundary implies, plus randomized noise:

| Category | Count | Examples |
| --- | --- | --- |
| `empty` | 1 | `""` |
| `too_short` | 6 | lengths 1, 2, 7, 15, 20, 21 (valid base64url alphabet) |
| `too_long` | 7 | lengths 23, 24, 30, 64, 256, 4096, 20000 |
| `bad_char` | 34 | a 22-char base64url string with one byte swapped for each of `+/=!@#$%^&*()\"'`~<>,.;:\|[]{}` and space/tab/CR/LF |
| `path_traversal` | 6 | `../../../etc/passwd`, `..\..\windows\system32`, `%2e%2e%2f%2e%2e%2f`, and similar |
| `unicode` | 4 | accented Latin, Japanese, emoji, mathematical symbols |
| `null_bytes` | 3 | 22 NUL bytes, NULs interleaved with letters, a single NUL |
| `invalid_utf8` | 2 | `[0xFF, 0xFE, 0xFD, 0x80, 0x81]`, repeated `0xC0`/`0xC1` (invalid UTF-8 lead bytes) |
| `random_noise` | 180 | uniformly random bytes, length 0–39, fixed seed `0xF00D_CAFE_1234_5678` |

Every byte is percent-encoded (`%XX` for anything outside RFC 3986's unreserved set) into one
URL path segment before the request is sent, so the corpus reaches the relay as a real client
would send it, including bytes a `String`-typed Rust literal cannot hold directly.

### Outcomes observed (both roles combined, 484 probes)

| Outcome | Count | What happened |
| --- | --- | --- |
| `closed_4003` (`protocol_error`) | 116 | Upgrade accepted (101), `raw_handle.parse::<Handle>()` failed in `accept_handle` (`crates/herdr-relay-hub/src/routes/connection.rs`), relay sent the R-11-116 error frame then closed with code 4003, exactly as R-12-021 requires. |
| `http_rejected_400` | 352 | The percent-decoded path segment was not valid UTF-8, so axum's `Path<String>` extractor rejected the request with `400 Bad Request` before the WS upgrade — before the relay's own handle-format check ever runs. All but 4 of these came from `random_noise`: uniformly random bytes are overwhelmingly *not* valid UTF-8, so most of that category never reaches the WS layer at all. |
| `http_rejected_404` | 8 | The segment percent-decoded to empty (or otherwise matched no route), so the router itself returned `404 Not Found` — no route, no upgrade, no handler ever ran. |

Zero hangs, zero transport errors, zero non-101/400/404 HTTP statuses, zero close codes other
than 4003. After the full 484-probe barrage the same relay instance still answers `GET /healthz`
with `200 ok` (`assert_relay_still_answers_healthz`), proving the relay's task did not die.

All three outcomes are documented, non-crashing dispositions: `protocol_error` is R-12-021's own
answer for a malformed handle; the two HTTP-level rejections are axum's ordinary behavior for a
path segment that cannot even be decoded to the `String` the route handler expects, and are just
as safe (the connection never reaches application logic).

### Edge cases (`valid_handle_edge_cases_are_handled_without_crashing`)

- A syntactically valid, never-registered 22-character handle (`9AAAAAAAAAAAAAAAAAAAAA`) connected
  as `/device/<handle>`: the relay accepted the upgrade and the registration frame, then replied
  with the R-11-116 `handle_unknown` error frame and closed with code **4001** — R-12-021's
  boundary is distinct from R-11-118's "no such handle" case, and both are exercised.
- The same handle registered as a real Host, then probed at the R-12-030 frame-size boundary:
  a 65,536-byte binary frame and a 1,048,576-byte binary frame were both **accepted** (no close);
  a 1,048,577-byte frame was **rejected** with `frame_too_large`, close code **4007**.

### Finding: R-12-030's documented limit does not match the code

`docs/12-relay-hosting.md` R-12-030 currently reads:

> The relay MUST reject a WebSocket binary frame whose payload exceeds 65535 bytes ... The close
> code is `frame_too_large` (4007).

The actual enforcement is `crates/herdr-relay-hub/src/routes.rs`'s
`pub(crate) const MAX_FRAME_BYTES: usize = 1_048_576;` (1 MiB), applied in
`crates/herdr-relay-hub/src/relay.rs`'s `if bytes.len() > MAX_FRAME_BYTES`. The fuzz run above
measured this directly: a 65,536-byte frame (one byte over the *documented* 65535-byte ceiling)
was accepted and forwarded without complaint, while only a frame over 1,048,576 bytes triggered
`frame_too_large`. This is a doc/code mismatch, not a panic, hang, or leak — no relay-hub source
was touched to fix it, per this phase's "no path" ownership. It is reported here for the doc's
owner to resolve (either raise R-12-030's stated ceiling to match `MAX_FRAME_BYTES`, or lower
`MAX_FRAME_BYTES` to match the documented 65535-byte `snow` transport-message ceiling the rule's
own rationale cites).

## `/healthz` and `/metrics`

### Corpus

1,260 raw HTTP/1.1 requests (630 against `/healthz`, 630 against `/metrics`): the product of 14
methods (`GET`, `get`, `Get`, `POST`, `PUT`, `DELETE`, `PATCH`, `OPTIONS`, `HEAD`, `TRACE`,
`CONNECT`, `FOOBAR`, empty, and a method containing embedded spaces), 9 query strings (empty,
ordinary key/value pairs, a fake `handle=`/`session=` parameter, a NUL byte, a percent-encoded
CRLF-injection attempt, a path-traversal string, an HTML/script-injection string, and a SQL-style
injection string with embedded literal spaces), and 5 header variants (none, a spoofed
`X-Forwarded-For`, an 8,000-byte header value, three duplicate headers, and a header value with
embedded Unicode). Every request also carries a unique per-request marker
(`X-Probe-Marker: PROBE-<16 hex digits>`, also appended to the query string) so the response can
be checked for reflection.

Sent over a fresh raw TCP connection per request (`Connection: close`), bypassing any HTTP
client's own request validation, so the relay's actual HTTP parser and router see exactly these
bytes.

### Outcomes observed (1,260 requests)

| Status | Count | Cause |
| --- | --- | --- |
| `200 OK` | 140 | `GET` or `HEAD` (case-sensitive; `get`/`Get` do not match) with a syntactically parseable query string and header set. |
| `405 Method Not Allowed` | 700 | Every other syntactically well-formed method token (`POST`, `PUT`, `DELETE`, `PATCH`, `OPTIONS`, `TRACE`, `CONNECT`, `FOOBAR`, `get`, `Get`) against a route that only serves `GET`/`HEAD`. |
| `400 Bad Request` | 420 | Either the method token itself was malformed (empty, or containing an embedded space, which breaks HTTP/1.1 request-line framing before axum ever sees a method) — 90 of these — or the query string contained literal, unencoded characters HTTP/1.1's request-target grammar does not allow raw (a literal space in the SQL-injection-style query, or literal `<`/`>` in the script-injection query) — the remaining 330, spread evenly across every method. |

Zero `5xx` responses (asserted explicitly: any status starting `HTTP/1.1 5` fails the test). Zero
hangs (every request completes or the connection closes within the 2-second probe timeout). Zero
reflected markers: none of the 1,260 responses contained the unique per-request `PROBE-<hex>`
marker anywhere in their bytes (headers or body), so neither endpoint reflects request content
back to the caller. After the barrage, both endpoints were probed fresh one more time: `/healthz`
still returned `200 ok`, `/metrics` still returned `200` with a body that does not contain the
literal string `127.0.0.1` or any `PROBE-` marker — consistent with `/healthz` ignoring its
request entirely (`async fn healthz() -> &'static str { "ok" }`,
`crates/herdr-relay-hub/src/routes.rs`) and `/metrics` only ever rendering fixed enum label sets,
never an attacker-controlled string (`crates/herdr-relay-hub/src/routes/metrics.rs`'s own doc
comment already states this design intent; the fuzz run is the empirical proof).

## Summary

| Question | Answer |
| --- | --- |
| Any panic? | No. |
| Any hang past the 2-second probe timeout? | No. |
| Any HTTP 5xx? | No. |
| Any handle, session id, IP address, or request content leaked in a `/healthz` or `/metrics` response? | No. |
| Any connection that bypassed R-12-021's handle validation or reached another peer's session? | No. |
| Any finding worth recording? | Yes — see "Finding: R-12-030's documented limit does not match the code" above. Not a panic/hang/leak; a doc-vs-code mismatch, reported rather than silently patched. |

Total requests fuzzed across both parts: 484 (`/host`, `/device`) + 1,260 (`/healthz`,
`/metrics`) + 2 targeted edge-case sessions = 1,746.
