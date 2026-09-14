# Handle guessing against a running relay

Phase 23 checkbox (`docs/90-implementation-plan.md` §Phase 23, item 6): attempt to guess a
routing handle against a running relay and record the refusal behaviour (R-13-033, R-12-031).

## Method

`crates/herdr-relay-hub/tests/handle_guessing.rs` runs the real `herdr-relay-hub` router
(`herdr_relay_hub::routes::router()`) on a real loopback TCP port, the same pattern
`crates/herdr-relay-hub/tests/limits.rs` uses (self-contained: it deliberately exercises the
*default* `HERDR_RELAY_CONNECTION_RATE`, 10 connections/second/IP, rather than raising or
lowering it, so `tests/support/mod.rs`'s shared `Relay` — sized for Phase 3's own tests, which do
not need to survive a rejection before registering — is not reused here).

1. A real Host and a real Device register and join one handle
   (`n6Loxf94CfyIO6hOxlaHvA`, `docs/11-relay-protocol.md` §2.1's own worked example) — something
   worth protecting, and a live session to prove undisturbed afterward.
2. 100 syntactically valid, 22-character base64url handles, all distinct from the real one, are
   dialed at `/device/<handle>` back to back, as fast as the test process can open them. Each one
   is a real attacker's best-case guess: R-12-021's own format check cannot reject it for free.
3. Each attempt sends the Device registration frame (harmless if the connection is rejected
   before the relay ever reads it) and then reads the relay's reply.

Run with:

```sh
cargo test -p herdr-relay-hub --test handle_guessing -- --nocapture --test-threads=1
```

(cwd `crates/`).

## Result

```text
handle_guessing: 100 guesses against 127.0.0.1:<ephemeral port>
  handle_unknown_4001: 8
  rate_limited_4008: 92
```

Reproduced identically across repeated runs (three consecutive runs all split exactly 8/92). Two,
and only two, refusal codes were ever observed:

| Outcome | Count | Meaning |
| --- | --- | --- |
| `handle_unknown` (close code **4001**) | 8 | The relay accepted the connection (inside R-12-031's budget), read the Device registration frame, looked the handle up in its routing table, found no Host registered under it, and refused (`crates/herdr-relay-hub/src/session.rs`'s `Role::Device` branch of `register()` returns `RegisterError::HandleUnknown`). |
| `rate_limited` (close code **4008**) | 92 | The relay's `IpRateLimiter` (`crates/herdr-relay-hub/src/routes/limits.rs`, a real one-second sliding window over `Instant`s per source IP) had already counted 10 connections from `127.0.0.1` — the real Host, the real Device, and the first 8 guesses — within the trailing second, and refused every further connection attempt before it was even allowed to send a registration frame (`reject_if_rate_limited` runs first in `crates/herdr-relay-hub/src/routes/connection.rs`'s `drive_connection`). |

Both are documented, non-crashing, R-11-116-shaped refusals: a plaintext `error` frame naming the
code, followed by a close frame carrying it (`close_with_error`,
`crates/herdr-relay-hub/src/routes/connection.rs`). No guess ever received `session_joined`, and
no guess ever received any frame at all beyond its own two-message refusal — confirmed inline in
`attempt_guess`, which fails the test on any unexpected message shape.

## The real session was undisturbed

After the 100-guess barrage, the test has the real Host send one more marked binary frame and
asserts the real Device receives exactly that payload:

```text
the real Device must receive exactly what the real Host sent, unaffected by the guessing barrage
```

This passed. The real session's traffic is keyed by the routing handle in the relay's
in-process session map (`crates/herdr-relay-hub/src/session.rs`); none of the 100 guesses ever
named the real handle, so there was never a routing-table entry a guess could have reached even in
principle. The empirical proof above rules out a bug in that isolation, not just a theoretical
guarantee.

## Conclusion

This matches R-13-033's own reasoning exactly: **a handle is not a bearer token.** An attacker who
learns or successfully guesses a handle can reach the relay's routing table and attempt to connect
— which is all this test demonstrates, and even that attempt is refused, first for lacking a
registered Host under the guess (`handle_unknown`) and then, once the guessing itself becomes
abusive, by R-12-031's connection-rate limiter (`rate_limited`) regardless of whether any guess
would otherwise have succeeded. Guessing correctly would only earn an attacker a WebSocket
connection to a Host that still requires a full `Noise_XXpsk0`/`Noise_KK` handshake authenticated
by a static keypair and PSK the attacker does not have (R-13-033's own "cannot" list: decrypt any
frame content, impersonate the Host or the Device, learn terminal content, keystrokes or the
pairing phrase). The handle only routes; Noise is what authorizes and protects.

## Finding

None. No panic, no hang, and no observed outcome outside the two documented refusal codes above.
