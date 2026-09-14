# 12 — Relay Hosting Architecture and Requirements

**Owner:** Hosting
**Status:** Draft — documentation phase

This document owns the relay architecture and hosting requirements. It tells implementers what the
relay MUST do and how it fits into the system. It does not tell an operator how to deploy it. That is
`docs/14-relay-deployment.md`.

## Requirements

These rules govern every architecture decision. They are numbered for cross-reference from other
documents.

### Functional

**R-12-001** The relay MUST be reachable from the public internet over TLS on port 443. The Device
(a phone on a cell network or public Wi-Fi) MUST connect with no VPN client, no enterprise MDM
profile and no pre-installed certificate.

**R-12-002** The Host (a developer laptop) MUST open only outbound connections to the relay. Zero
inbound firewall rules, zero public IP on the Host, zero changes to the Host network configuration
beyond outbound TCP to one host and port.

**R-12-003** The relay MUST forward opaque binary frames between one Host and one Device. The relay
MUST NOT inspect, decrypt, modify, log or persist any frame payload.

**R-12-004** The relay MUST route connections by an opaque 128-bit handle. The Host generates the
handle from a cryptographic random source, encodes it as 22 characters of unpadded base64url, and
presents it in the WebSocket path. The relay reads the handle only to map streams. Noise
authenticates peers and protects content. See `docs/11-relay-protocol.md` for the handle wire format
and `docs/13-security-pairing.md` for the generation rules.

**R-12-005** The relay MUST NOT generate, render or serve a QR code. The Host renders the pairing QR
code. The relay has no QR endpoint and no pairing URI endpoint. See
`docs/13-security-pairing.md` and `docs/30-ux-spec.md`.

**R-12-006** Added latency from relay ingress to egress (frame arrival to frame departure) MUST stay
under 5 ms at p50 and under 20 ms at p99 under normal load. A person typing at 60 wpm sees
approximately 100 ms per character. An extra 20 ms is invisible.

**R-12-007** The relay MUST support at least 500 concurrent Host-Device pairs on one instance. This
covers a team of 200 developers with two devices each plus headroom.

**R-12-008** If the Host WebSocket drops (laptop sleep, network flap, Herdr restart), the relay MUST
close the Device side at once (R-12-038) and discard the handle registration at once. The Host
registration lives as long as its connection lives. The Host re-registers on its reconnect ladder
(R-10-014); the Device reconnects with `Noise_KK` (R-13-037) on the R-22-028 ladder, and a Device
that arrives before the Host has re-registered receives `handle_unknown` (R-11-117) and retries.
There is no grace window: a Noise transport state lives in the peer process, so no relay-side
window can resume a session across a Host restart. Rationale: the 30-second hold-open this rule
replaces deadlocked exactly that case — a new Host registration inherited a Device that held a dead
Noise session and never sent its `Noise_KK` first message.

**R-12-009** If the Device WebSocket drops (cell handover, app background), the symmetric rule
applies (R-11-125): the relay MUST close the Host side at once (R-12-038) and discard the handle
registration at once. The Host re-registers on its reconnect ladder; the Device reconnects with
`Noise_KK`. A peer loss never keeps a room.

**R-12-010** The relay MUST expose a `/healthz` endpoint that returns HTTP `200` with body `ok` when
the process is alive and the WebSocket acceptor is listening. No authentication. No session data.

**R-12-011** The relay MUST expose a `/metrics` endpoint in Prometheus text format on the loopback
interface or behind the reverse proxy. See the metrics section below.

### Non-functional

**R-12-012** The relay MUST build and test only through its multi-stage Dockerfile, and MUST run only
as a container made from that Dockerfile. The build stage MUST produce one static
`x86_64-unknown-linux-musl` binary. The test stage MUST run the relay formatter, linter and tests.
The final `FROM scratch` image MUST hold only the binary and the CA certificate bundle, and SHOULD
stay under 20 MiB compressed. A developer workstation MUST need only a Docker client and Docker
Engine for relay work. It MUST NOT need a Linux distribution package, a host musl target or a host
Rust toolchain for the relay.

**R-12-013** The relay MUST hold zero persistent state. The in-memory handle map is the only routing
data. Nothing is written to disk. Nothing survives a restart. Backups are not needed because there
is nothing to back up.

**R-12-014** The relay MUST emit structured JSON logs to stdout. Log fields are limited to the
explicit allow list in the Logging section. Payload content MUST NOT appear in any log field.

**R-12-015** The relay MUST expose Prometheus metrics on the `/metrics` endpoint. See the metrics
table in the Observability section.

**R-12-016** The relay MUST support a self-hosted deployment path. An operator runs the container and
a reverse proxy on a public Linux VM and gets the full relay behaviour. See
`docs/14-relay-deployment.md` for the supported profile.

## Architecture Options

This section records why a rendezvous WebSocket relay won over every alternative. It is a record,
not a live decision.

### Option A — Rendezvous Relay (WebSocket Hub)

The relay is a purpose-built WebSocket server. The Host connects to
`wss://<relay>/host/<handle>` and waits. The Device connects to
`wss://<relay>/device/<handle>`. The relay pairs the two sockets by handle and copies frames
bidirectionally. Frames are Noise ciphertext. No plaintext exists on the relay.

A reverse proxy (normally Caddy) terminates public TLS. The supported deployment uses a private
Compose network, where Caddy forwards WebSocket connections to the `relay:8080` service
(`docs/14-relay-deployment.md` R-14-021 and R-14-022).

### Option B — SSH Reverse Tunnel to a Bastion

The Host opens an SSH reverse tunnel to a bastion. The Device connects through SSH to the bastion
and reaches the forwarded port. Requires an SSH client on the phone — unacceptable. Also needs SSH
key management on the phone. Violates R-12-001.

### Option C — WireGuard / Tailscale Mesh

Every node joins a WireGuard mesh. The Host and Device get mesh IPs and communicate directly. The
"Hub" is the coordination server. Requires a Tailscale client on the phone — violates R-12-001.
The mesh model also gives every Device lateral movement risk on the tailnet.

### Option D — Cloudflare Tunnel as the Relay

The Host runs `cloudflared`. Cloudflare gives a public URL. The Device connects to that URL.
Cloudflare forwards bytes. No custom relay code, but Cloudflare terminates TLS and sees the outer
WebSocket bytes. The free tier is 50 users. Cloudflare Teams pricing for 500 seats is approximately
USD 3500 per month. Also, Cloudflare Tunnel ownership means no control over session pairing logic
and peer-loss policy.

### Option E — WebRTC / QUIC Peer-to-Peer with Signalling Server

The relay is only a signalling server. Data flows peer-to-peer over WebRTC data channels. A TURN
relay handles NAT cases. NAT traversal fails for symmetric NATs common on corporate and cell
networks, so the TURN fallback is the common case and the TURN relay is functionally identical to
Option A. The WebRTC stack is complex — ten times the code of a plain WebSocket relay.

### Comparison Table

| Criterion | A (WS Hub) | B (SSH Bastion) | C (Tailscale) | D (CF Tunnel) | E (WebRTC) |
|---|---|---|---|---|---|
| No phone client (R-12-001) | ✅ | ❌ | ❌ | ✅ | ✅ |
| Host outbound only (R-12-002) | ✅ | ✅ | ✅ | ✅ | ✅ |
| Opaque, no store (R-12-003) | ✅ | ❌ | ❌ | ❌ | ❌ |
| Handle routing (R-12-004) | ✅ | ❌ | ❌ | ❌ | ✅ |
| No QR on relay (R-12-005) | ✅ | ❌ | ❌ | ❌ | ❌ |
| 500 pairs (R-12-007) | ✅ | ❌ | ✅ | ❌ | ✅ |
| Peer-loss policy (R-12-008/009) | ✅ | ❌ | ❌ | ❌ | ❌ |
| Operational complexity | Low | Medium | Low (but cost) | Low (but cost) | High |

### Verdict

**Option A (Rendezvous Relay WebSocket Hub) is the decision.** It is the only option that satisfies
every requirement.

The relay is Rust, not Go. The reason is `herdr-relay-proto`: a shared protocol crate that holds the
frame envelope, close-code enum, error taxonomy, handle codec, phrase codec and protocol test
vectors. It is shared by the Host plugin (`herdr-relay`) and the relay (`herdr-relay-hub`) by
compilation, not by prose. Two languages (Rust and Dart) beat three. See
`docs/decisions/ADR-003-rust-host-and-relay.md` for the full rationale.

Option D (Cloudflare Tunnel as the relay) is rejected because it removes control over pairing
logic, peer-loss policy and handle routing. Option C (Tailscale) is only for private testing on a
shared corporate network, not for public mobile use.

## Language and Crates

The relay is Rust, edition 2024. Its crate is `herdr-relay-hub`. It sits in a workspace with
`herdr-relay-proto` (the shared protocol library) and `herdr-relay` (the Host plugin).

The relay depends on these crates. Versions are the verified pins from the project dependency table.

| Crate | Version | Purpose |
|---|---|---|
| `axum` | `0.8.9` | HTTP routing, WebSocket upgrade, `/healthz`, `/metrics` |
| `tokio` | `1.53.1` | Async runtime, `rt-multi-thread`, `macros`, `net`, `time`, `sync` |
| `herdr-relay-proto` | workspace | Shared frame envelope, close codes, error codes, handle codec |
| `serde` | `1.0.229` | derive (via proto) |
| `serde_json` | `1.0.151` | JSON envelope (via proto) |
| `thiserror` | `2.0.20` | Typed boundary errors |
| `tracing` | `0.1.44` | Structured logging, metadata only |

The relay does not depend on `snow`, `blake2`, `rand`, `qrcode`, `ratatui` or `crossterm`. Those
belong to the Host plugin. The relay holds no keys and performs no cryptography beyond the TLS its
HTTP stack provides.

The multi-stage Dockerfile owns the `x86_64-unknown-linux-musl` toolchain and every relay build
dependency. Its `FROM scratch` final image holds only the binary and the CA certificate bundle.
Target compressed size: under 20 MiB.

Rejected crates and why:

| Crate | Why rejected |
|---|---|
| `tokio-tungstenite` | The relay serves WebSocket, not connects. `axum` handles the upgrade. |
| A database driver | The relay holds zero persistent state (R-12-013). |
| `snow` or any Noise crate | The relay holds no Noise keys and performs no Noise handshake. |
| `qrcode` or any QR crate | The Host renders the QR (R-12-005). |
| A web framework beyond `axum` | `axum` covers routing, upgrade, health and metrics. |

## Handle Routing

The relay holds one in-memory map. It is the only routing state.

```text
handle (22-char base64url) → { host_connection: Option<WebSocket>,
                               device_connection: Option<WebSocket>,
                               host_registered_at: Instant }
```

- A Host that presents an already-registered handle receives `handle_taken` (`4002`). The first
  Host is untouched.
- A Device that presents a handle whose Device slot is occupied receives `host_in_use` (`4006`).
  The first Device is untouched.
- The handle map is in memory only. Nothing is written to disk. Nothing survives a restart.
- The handle map size limit is configurable. The default is `4096` handles. Exceeding it returns
  `rate_limited` (`4008`).

## Endpoints

| Path | Method | Caller | Authentication stage | Behaviour |
|---|---|---|---|---|
| `/host/<handle>` | `GET`, WebSocket upgrade | Host | Noise after upgrade | Register handle, keep one persistent connection. Subprotocol: `herdr-relay.v1`. |
| `/device/<handle>` | `GET`, WebSocket upgrade | Device | Noise after upgrade | Join the Host registered under `<handle>`. Subprotocol: `herdr-relay.v1`. |
| `/healthz` | `GET` | Operator, load balancer | None | `200 OK`, body `ok`. No session data, no handle, no IP, no content. |
| `/metrics` | `GET` | Operator, Prometheus | None | Prometheus text format. Bound to loopback by default; in Compose, it can bind to the private network. No session data. |

**R-12-020** The relay MUST require the WebSocket subprotocol `herdr-relay.v1` on `/host/<handle>`
and `/device/<handle>`. A connection that does not request it receives `protocol_error` (`4003`).

**R-12-021** The relay MUST validate that `<handle>` is exactly 22 characters of unpadded base64url
before accepting the upgrade. A malformed handle receives `protocol_error` (`4003`).

**R-12-022** The relay MUST send a WebSocket ping to each connected peer every 30 seconds. A peer
MUST respond with a pong within 10 seconds. The relay owns the heartbeat. Peers MUST NOT send their
own pings.

**R-12-023** The relay MUST bind `/healthz` to the same port as the WebSocket acceptor. It MUST NOT
require authentication. It MUST NOT expose a handle, a session identifier, an IP address, a peer
count or any payload content in the response.

**R-12-024** Outside the Compose deployment, the relay MUST bind `/metrics` to the loopback
interface by default. It MAY protect the endpoint behind the reverse proxy. The relay MAY bind
`/metrics` to `0.0.0.0:9090` only when no host-published metrics port exists and the relay is
attached to the private `herdr-relay-network` Compose network named in
`docs/14-relay-deployment.md`. It MUST NOT expose a handle, a session identifier, an IP address or
any payload content in the metric labels or values.

## Size Limits and Rate Limits

**R-12-030** The relay MUST reject a WebSocket binary frame whose payload exceeds 1 MiB
(1048576 bytes), the single frame-size value `docs/11-relay-protocol.md` R-11-035 sets for the
whole repository, matching `crates/herdr-relay-hub/src/routes.rs`'s `MAX_FRAME_BYTES`.
The close code is `frame_too_large` (`4007`). The relay never decrypts, so it cannot see or check
the uncompressed JSON envelope size that `docs/11-relay-protocol.md` R-11-035 bounds at 1 MiB; that
cap is enforced by the sender before compression and by the receiver after decompression, both
inside the Noise session (R-11-233, R-11-234), never by the relay.

**R-12-031** The relay MUST limit new WebSocket connections to 10 per second per source IP address.
A connection that exceeds the limit receives `rate_limited` (`4008`).

**R-12-032** The relay MUST limit the frame rate to 100 frames per second per connection. A peer
that exceeds the limit receives `rate_limited` (`4008`).

**R-12-033** The relay MUST limit the handle-registration rate to 5 new handles per second from the
same source IP address. Exceeding the limit receives `rate_limited` (`4008`).

**R-12-034** The relay MUST limit the total registered handles to the configured maximum. The default
is `4096`. Exceeding the maximum receives `rate_limited` (`4008`). This limit protects the in-memory
map from exhaustion.

**R-12-035** The relay MUST accept at most one Device connection per handle at a time. A second
Device receives `host_in_use` (`4006`). The first Device is untouched. See
`docs/03-product-decisions.md` for the product policy.

**R-12-036** When a WebSocket frame arrives for a handle whose peer slot is empty (no connected
peer on the other side), the relay MUST drop the frame silently. The relay MUST NOT close the
connection. The peer may reconnect. This covers the case where the Host sends a frame before the
Device joins, and the case where a frame arrives while the peer's loss is still being torn down
(R-11-125).

**R-12-037** A rejected second Host (`handle_taken`, `4002`) or second Device (`host_in_use`,
`4006`) connection MUST NOT trigger cleanup of the live connection. The relay MUST identify the
live connection by socket identity, not by handle alone, before running any teardown logic. A
rejected connection that closes must not tear down the room it was rejected from.

**R-12-038** When either peer's WebSocket ends, the relay MUST close the surviving peer at once
with close code `going_away` (`1001`) and a reason that names the peer that is gone (`the Host is
gone` or `the Device is gone`). This rule applies in both directions. The relay MUST NOT close the
survivor with `normal` (`1000`), because the survivor did not initiate the shutdown. The relay MUST
discard the handle registration at once, in the same step.

**R-12-039** A relay restart or crash MUST drop every live handle registration. The relay MUST
NOT attempt to persist or recover the handle map. Peers reconnect with the same handle and the
relay creates a fresh registration. This is the restart behaviour that R-12-013 implies, stated
explicitly for the crash case. No peer receives advance notice; the Device detects the drop
through the WebSocket close or the ping timeout (R-12-022) and reconnects with backoff.

## Logging

**R-12-040** The relay MUST emit one JSON object per log event to stdout. The container runtime
captures stdout.

**R-12-041** The relay MUST include only these fields in a log event:

| Field | Type | When | Description |
|---|---|---|---|
| `ts` | string | always | ISO 8601 timestamp with milliseconds, UTC |
| `event` | string | always | One of: `host_connected`, `host_disconnected`, `device_connected`, `device_disconnected`, `relay_started`, `handle_expired`, `error` |
| `handle_first_6` | string | connection events | First 6 characters of the 22-character handle, for correlation only. The full handle is never logged. |
| `peer` | string | connection events | `host` or `device` |
| `active_handles` | integer | after the event | Current count of registered handles |
| `frames_forwarded` | integer | at disconnect | Total frames forwarded during the session |
| `bytes_forwarded` | integer | at disconnect | Total bytes forwarded during the session |
| `duration_ms` | integer | at disconnect | Session duration in milliseconds |
| `error_code` | string | error events | One of the close-code names from `docs/11-relay-protocol.md` |
| `error_message` | string | error events | Human-readable message, at most 256 characters |

**R-12-042** The relay MUST NOT log any of these:

- A full routing handle
- A pairing phrase or any part of one
- A device id, host id or user path
- Terminal ANSI content or keyboard input
- A frame payload or any data derived from a Noise ciphertext
- A source IP address (the reverse proxy may log it; the relay does not)
- An `Authorization` header, a cookie or a token

Rationale: this product moves terminal content for a living. Terminal content on a developer machine
is Confidential. A relay log that captures it becomes a data-classification incident.

**R-12-043** The relay MUST NOT log at a level that writes a WebSocket frame payload to stdout, even
at `trace` or `debug` level. The `tracing` subscriber MUST filter frame bodies before emission.

## Observability

**R-12-050** The relay MUST expose these Prometheus metrics on `/metrics`:

| Metric | Type | Labels | Description |
|---|---|---|---|
| `herdr_relay_handles_active` | Gauge | — | Current active handle registrations |
| `herdr_relay_handles_total` | Counter | — | Total handle registrations since start |
| `herdr_relay_frames_forwarded_total` | Counter | `direction` (`host_to_device`, `device_to_host`) | Total frames relayed |
| `herdr_relay_bytes_forwarded_total` | Counter | `direction` | Total bytes relayed |
| `herdr_relay_session_duration_seconds` | Histogram | — | Session lifetime, buckets: 1, 5, 15, 30, 60, 120, 300, 600, 1800, 3600 |
| `herdr_relay_errors_total` | Counter | `code` (close-code name) | Error count by type |
| `herdr_relay_connections_rejected_total` | Counter | `reason` (`rate_limited`, `handle_malformed`, `handle_taken`, `host_in_use`) | Rejected connection count |

**R-12-051** An operator SHOULD alert on:

- `herdr_relay_handles_active` drops to zero while the process is alive
- `herdr_relay_errors_total` rate exceeds 10 per minute
- `herdr_relay_connections_rejected_total` rate exceeds 20 per minute
- `/healthz` returns non-200 for more than 60 seconds

## TLS and Cryptography

The reverse proxy in front of the relay, normally Caddy, terminates the public TLS hop. The relay
binary still links the platform TLS stack through its HTTP and WebSocket libraries, because it may
serve TLS directly in a single-host deployment and because its client-side test harness connects
outward.

**R-12-060** The relay performs no application-layer payload decryption and holds no Noise keys.
This is the correct claim. The statement "the relay binary has zero crypto dependencies" is false.
The relay links the platform TLS stack.

## Deployment Paths

The relay has one supported deployment profile: a public Linux VM running the relay container behind
Caddy. See `docs/14-relay-deployment.md`.

An internal NVIDIA experiment using Brev direct instances is documented separately. It is not a
product dependency. See `docs/15-nvidia-brev-relay-experiment.md`.

**R-12-070** The app and the wire protocol MUST NOT depend on any one operator's relay deployment.
The pairing URI carries the relay origin. An operator chooses their own relay hostname.

## Prior art: the omp collab relay

The omp project (`can1357/oh-my-pi` on GitHub) runs a production collab relay at
`wss://my.omp.sh`. It is a content-blind rendezvous relay that joins a host to guests,
forwards sealed frames, and keeps no state beyond live connections. It is the closest working
precedent for `herdr-relay-hub`.

The production relay is a small Go service whose source is not published. A source-available
WebSocket-only stand-in at `packages/collab-web/scripts/local-relay.ts` implements the exact

### What the omp relay confirms

The omp relay confirms three design decisions already in this document:

- An in-memory room map with no persistence is sufficient and is what a production relay really
  does. The omp relay keeps a `Map<string, Room>` in memory. A restart drops every room. Clients
  reconnect. This supports R-12-013.
- A content-blind relay needs no cryptography library. The stand-in relay imports only
  4-byte header operations. No AES, no Noise, no key import. This supports R-12-060.
- Separating a routing id from a secret is the established pattern. omp separates the room id
  (routing, visible to relay) from the room key (secret, never sent to relay). herdr-mobile
  does the same: handle (routing) vs phrase (Noise PSK). This supports R-12-004.

### Design dimensions: matches and deliberate differences

| Dimension | omp collab relay | herdr-relay-hub | Relationship |
|---|---|---|---|
| Routing key | Room id, base64url, host-generated | 128-bit handle, 22-char base64url, Host-generated | Matches: opaque random id from the host |
| Secret transport | URL fragment (browser) or dot-joined path; never sent to relay | Custom-scheme URI query parameter; never fetched over HTTP | Deliberate difference: custom scheme is never fetched, so the query parameter never reaches a server |
| Role selection | `?role=host\|guest` on one path `/r/<roomId>` | Two paths: `/host/<handle>` and `/device/<handle>` | Deliberate difference: two paths give routing clarity and prevent role mix-up |
| Peer count | One host, many guests | One Host, one Device | Deliberate difference: product decision is one phone per Host |
| Encryption | AES-256-GCM, application-layer, room key in the link | Noise `XXpsk0` / `KK`, handshake authenticates peers | Deliberate difference: Noise authenticates peers; AES-GCM alone does not |
| Framing | Binary `[4B peerId][sealed payload]` plus TEXT control | Noise ciphertext frames, 1 MiB cap | Deliberate difference: no routing prefix needed for one Device |
| Size cap | No hard cap in stand-in; chunking keeps frames within a 30 s progress timeout | 1 MiB per WebSocket frame at the relay, matching the envelope cap R-11-035 sets, checked end to end inside Noise | Deliberate difference: hard cap is safer than a soft timeout |
| Keepalive | No ping/pong in stand-in | Relay pings every 30 s, 10 s pong deadline | Deliberate difference: herdr specifies a heartbeat |
| Peer loss | Room dies with host | Room dies with either peer, the survivor gets 1001 | Matches in spirit; herdr also closes the Host when the Device leaves |
| Health endpoint | `/healthz` in production | `/healthz` | Matches |
| Metrics endpoint | Not documented | `/metrics` in Prometheus format | herdr adds one |
| State | In-memory, no persistence, no restart recovery | In-memory, no persistence, no restart recovery | Matches |
| Self-hosting | Production relay not published; stand-in is source-available | Self-hosted Rust binary in a container | Deliberate difference: herdr is self-hostable |
| Permission levels | Two: full (48-byte link with write token) and view-only (32-byte link) | One: full control only | Deliberate difference: version 1 is full-control only |

### What the omp relay does that herdr-mobile should copy

The stand-in relay checks that the disconnecting socket is the live host before tearing down
the room. A rejected second host that closes does not destroy the live room. This pattern is
now R-12-037: a rejected connection close event must not trigger cleanup of the live
connection.

The stand-in relay drops frames for a room with no peer silently, without closing the
connection. This is now R-12-036: a frame for an empty peer slot is dropped, not treated as
an error.

## Sources

- `docs/11-relay-protocol.md` — wire protocol, close codes, frame envelope, heartbeat
- `docs/13-security-pairing.md` — handle generation, Noise handshake, handle lifetime
- `docs/decisions/ADR-003-rust-host-and-relay.md` — Rust relay decision
- `docs/03-product-decisions.md` — one active Device per Host policy
- `docs/14-relay-deployment.md` — supported deployment profile
- `docs/15-nvidia-brev-relay-experiment.md` — internal experiment
