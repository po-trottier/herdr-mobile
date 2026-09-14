# ADR-003: The Host plugin and the relay are both Rust

## Status

Accepted. Supersedes the Go relay decision.

## Date

2026-08-24

## Context

The earlier design used three languages, one per network boundary: Rust for the Host plugin, Go for
the relay, and Dart for the app. Go was chosen for the relay because a small WebSocket forwarder is
easy to write in Go, the `nhooyr.io/websocket` library is maintained, and the binary is small (under
20 MiB with a static Alpine build). The relay language sections of `docs/12-relay-hosting.md` and
`docs/41-code-standards.md` carried that decision.

During the documentation remediation it became clear that two languages are sufficient and simpler
than three. The Host plugin (Rust) and the relay share the same wire-protocol elements: the frame
envelope, the application message types, the close-code enum, the error taxonomy, the
routing-handle codec and the pairing-phrase codec. These form a shared protocol contract that, in two
languages, must be translated twice and kept in step by prose alone. Drift is silent and costly.

Third, the relay's responsibilities grew beyond simple forwarding: it must validate handles at
connection time, enforce the one-active-Device rule, emit typed close codes, serve `/healthz` and
`/metrics`, and hold an in-memory routing map with precise hold-open behaviour. A relay that
validates and enforces is closer to the Host than it is to a dumb pipe, so sharing a type system
with the Host is useful.

Fourth, cross-platform Rust expertise and review capacity concentrate in one language instead of
splitting across Go and Rust.

## Decision

Both the Host plugin (`herdr-relay`) and the relay service (`herdr-relay-hub`) are Rust, edition
2024. The shared protocol library is one crate, `herdr-relay-proto`. The app remains Dart (Flutter).

Two languages serve three deliverables. The workspace layout is:

```text
crates/herdr-relay-proto/   frame envelope, message types, close codes, error codes,
                            routing-handle codec, pairing-phrase codec, test vectors
crates/herdr-relay/         Herdr plugin: Herdr socket client, watch loop, Noise session,
                            relay client, ratatui popup pane
crates/herdr-relay-hub/     relay service: WebSocket server, in-memory handle map,
                            /healthz, /metrics
```

`herdr-relay-proto` holds the frame envelope, the message types, the close-code enum, the error
taxonomy, the routing-handle codec, the pairing-phrase codec and the protocol test vectors once. The
compiler enforces agreement between the Host and the relay. The verified crate versions are owned by
`docs/41-code-standards.md`.

The relay depends on `axum` for HTTP routing and WebSocket upgrade, `tokio-tungstenite` for the
WebSocket transport and `tracing` for structured logs. It does not depend on `snow`, `blake2` or
`rand`, because it holds no keys and performs no cryptography beyond the TLS its HTTP stack
provides.

The relay binary is a single static executable in a minimal container image, built with a musl
target.

Explicitly removed by this ADR, and retired from every normative document:

- Go as a product language.
- `nhooyr.io/websocket` and every Go WebSocket library.
- `go-qrcode` (QR generation moved to the Rust Host, which already held the pairing phrase).
- `go vet`, `golangci-lint` and every Go lint rule.
- The Alpine-Go build stage.
- The Go source tree (`hub/herdr-relay-hub/`) and every Go continuous-integration job.

`docs/12-relay-hosting.md` and `docs/41-code-standards.md` now carry the Rust relay decision.

## Consequences

Easier: the protocol crate is a single source of truth. A close-code or message-type change is one
edit. The Host and the relay share the same serialization, the same validation and the same test
vectors. Cross-platform Rust expertise concentrates: a contributor who learns the protocol crate can
work on either side.

Harder: a Rust WebSocket server needs more lines than the Go equivalent. `axum` plus
`tokio-tungstenite` is a larger dependency tree than `nhooyr.io/websocket` alone. The container
build needs a `rust:alpine` or cross-compilation image with a musl target, which is heavier than the
Alpine-Go build stage it replaces.

A contributor must know Rust to touch either the Host or the relay. Before this decision, a Go
developer could work on the relay without learning Rust. That path is now closed. Mitigation: the
relay is the least Rust-intensive crate in the workspace; it owns no cryptography, holds no state on
disk and is under 500 lines.

These costs are accepted. The protection against protocol drift and the concentration of expertise
outweigh them.
