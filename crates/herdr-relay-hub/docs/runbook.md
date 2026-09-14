# `herdr-relay-hub` operator runbook

**Owner:** WP-9 (`docs/90-implementation-plan.md` Phase 9 — Relay deployment profile)
**Source of truth:** `docs/14-relay-deployment.md` (R-14-001 through R-14-071) and
`docs/12-relay-hosting.md` (R-12-050, R-12-051, R-12-070). This runbook restates no rule; it
records the deployment as built and the verification commands that were actually run against
this machine's local Docker Compose stack.

## Status of this runbook

Every check in this document ran against a **local** Docker Compose stack on the implementer's
own workstation (`wsl.exe -- docker ...`), because this environment holds no public Linux VM, no
DNS A record and no image registry. The local stack uses the exact `compose.yaml` and `Caddyfile`
committed beside this file, so it exercises the real deployment configuration. It does not, and
cannot, prove reachability from the public internet or from a phone on cellular data. The
`Done when` line of Phase 9 stays open until that infrastructure exists. See
[Blocked items](#blocked-items).

## Compose deployment

`compose.yaml` beside this file is the exact shape from R-14-010:

```yaml
services:
  relay:
    image: ghcr.io/herdr/herdr-relay-hub:v1.0.0
    container_name: herdr-relay-hub
    restart: unless-stopped
    environment:
      HERDR_RELAY_LISTEN: "0.0.0.0:8080"
      HERDR_RELAY_METRICS_LISTEN: "0.0.0.0:9090"
      HERDR_RELAY_MAX_HANDLES: "4096"
      HERDR_RELAY_CONNECTION_RATE: "10"
      HERDR_RELAY_FRAME_RATE: "100"
      HERDR_RELAY_HANDLE_RATE: "5"
      HERDR_RELAY_LOG_JSON: "true"
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
    networks:
      - relay

  caddy:
    image: caddy:2.11.4
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - caddy_data:/data
      - caddy_config:/config
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
    networks:
      - relay

networks:
  relay:
    name: herdr-relay-network

volumes:
  caddy_data:
  caddy_config:
```

`ghcr.io/herdr/herdr-relay-hub:v1.0.0` is the placeholder tag from R-14-011. **This tag is not
published.** No image registry exists for this project yet. An operator MUST replace it with the
real published tag before running this Compose file. See [Blocked items](#blocked-items).

Only Caddy publishes host ports (`80` and `443`). The `relay` service publishes no host port; it
listens on `0.0.0.0:8080` only on the private `herdr-relay-network` (R-14-010, R-14-013, R-14-022).
Confirmed by inspecting the running containers:

```text
$ docker inspect herdr-relay-hub --format "PublishedPorts={{.NetworkSettings.Ports}}"
PublishedPorts=map[]

$ docker inspect herdr-relay-hub-caddy-1 --format "PublishedPorts={{.NetworkSettings.Ports}}"
PublishedPorts=map[80/tcp:[{0.0.0.0 80} {:: 80}] 443/tcp:[{0.0.0.0 443} {:: 443}] 443/udp:[] 2019/tcp:[]]
```

### Restart policy and logging (R-14-012, R-14-015, R-14-050)

Both services set `restart: unless-stopped`, so both services restart after a host reboot or a
Docker daemon restart. The relay service sets the `json-file` logging driver with `max-size=10m`
and `max-file=3` to bound log disk use. Confirmed by inspecting the running relay container:

```text
$ docker inspect herdr-relay-hub --format \
    "RestartPolicy={{.HostConfig.RestartPolicy.Name}} LogDriver={{.HostConfig.LogConfig.Type}} LogOpts={{.HostConfig.LogConfig.Config}}"
RestartPolicy=unless-stopped LogDriver=json-file LogOpts=map[max-file:3 max-size:10m]
```

## Reverse proxy: Caddyfile

`Caddyfile` beside this file is the exact shape from R-14-021:

```caddyfile
relay.example.com {
    reverse_proxy relay:8080
}
```

Replace `relay.example.com` with the operator's real public DNS hostname. Caddy 2.11.4 obtains a
public TLS certificate automatically through Let's Encrypt on the first request; no certificate
step is needed (R-14-021). The `reverse_proxy` directive forwards `Connection: Upgrade` and
`Upgrade: websocket` with no extra configuration, so Caddy handles the WebSocket upgrade
automatically (R-14-023). This was confirmed by the WSS verification below: the upgrade request
reached the relay through this exact directive and returned the `herdr-relay.v1` subprotocol.

## Local verification method

`relay.example.com` cannot obtain a Let's Encrypt certificate on a machine with no public IP and
no public DNS record: the ACME HTTP-01 challenge needs Let's Encrypt to reach the VM from the
internet. To verify the same `compose.yaml` and the same `reverse_proxy relay:8080` directive
locally, the Caddy site address was swapped, for this verification run only, from
`relay.example.com` to `localhost` in a scratch copy of the Caddyfile mounted through a Compose
override file. `localhost` is not a public domain, so Caddy issues a certificate from its own
internal CA instead of requesting one from Let's Encrypt — no other line of the Compose file or
the Caddyfile changed. The committed `Caddyfile` in this directory keeps the `relay.example.com`
placeholder; the override was not committed and was deleted after the run.

Commands run from the repository root through `wsl.exe -- bash -lc '...'`:

```bash
# Validate the committed Compose file.
docker compose -f crates/herdr-relay-hub/compose.yaml config --quiet
# -> exits 0, no output.

# Build and locally tag the relay image at the placeholder tag, since no registry exists.
docker build --target test -f crates/herdr-relay-hub/Dockerfile .
docker build -f crates/herdr-relay-hub/Dockerfile -t ghcr.io/herdr/herdr-relay-hub:v1.0.0 .

# Bring up the committed compose.yaml plus a scratch override that only swaps the
# Caddy site address to localhost (see above).
docker compose -f crates/herdr-relay-hub/compose.yaml -f /tmp/herdr-relay-verify/compose.override.yaml up -d
```

`docker compose ps` output:

```text
NAME                      IMAGE                                  COMMAND                  SERVICE   STATUS         PORTS
herdr-relay-hub           ghcr.io/herdr/herdr-relay-hub:v1.0.0   "/herdr-relay-hub"       relay     Up 5 seconds
herdr-relay-hub-caddy-1   caddy:2.11.4                           "caddy run --config …"   caddy     Up 5 seconds   0.0.0.0:80->80/tcp, [::]:80->80/tcp, 0.0.0.0:443->443/tcp, [::]:443->443/tcp, 443/udp, 2019/tcp
```

## Health verification (R-14-030)

Local check through the Caddy service, from inside WSL, against the locally-exposed Caddy port:

```text
$ curl --fail --silent --show-error --resolve localhost:443:127.0.0.1 -k https://localhost/healthz -w "\nHTTP_STATUS:%{http_code}\n"
ok
HTTP_STATUS:200
```

This is `200`, body `ok`, exactly as R-14-030 requires. `-k` accepts Caddy's locally-issued
internal-CA certificate for this run only; a production deployment presents a real Let's Encrypt
certificate for the operator's hostname and needs no `-k`.

**The public check (`curl --fail --silent --show-error https://relay.example.com/healthz` from
outside the VM) was not run.** It needs the public VM, DNS record and open ports that R-14-001
requires and that do not exist in this environment. See [Blocked items](#blocked-items).

## WSS verification (R-14-040)

`websocat` is not installed on this workstation or in the WSL distribution, and R-90 policy for
this project keeps the WSL distribution Docker-only (`docs/40-repo-tooling.md` §7.2.4). The
verification below runs `websocat` from the official `ghcr.io/vi/websocat` container image
instead of installing it on the host, joined to the Docker host network so it can reach the
locally-published Caddy port:

```text
$ echo '{"type":"host_info","protocol":1}' | \
    docker run --rm -i --network host ghcr.io/vi/websocat:latest -v -n -k \
    --protocol herdr-relay.v1 "wss://localhost/host/n6Loxf94CfyIO6hOxlaHvA"

[INFO  websocat::ws_client_peer] Connected to ws, response headers: Headers { Alt-Svc: h3=":443"; ma=2592000
, Connection: upgrade
, Date: Thu, 27 Aug 2026 21:30:16 GMT
, Sec-WebSocket-Accept: FH/JdtdhB+9XOGoE5veLy66BgbU=
, Sec-WebSocket-Protocol: herdr-relay.v1
, Server: Caddy
, Upgrade: websocket
, }
{"type":"error","code":"protocol_error","message":"missing or malformed registration frame"}
[INFO  websocat::ws_peer] Received WebSocket close message
```

The WebSocket upgrade succeeded (`Connection: upgrade`, `Upgrade: websocket`) and the relay
returned the requested `Sec-WebSocket-Protocol: herdr-relay.v1` subprotocol, which is the critical
observation R-14-040 names. The relay then closed the connection with `protocol_error` because the
test sent a plain JSON line, not a real Noise handshake frame — the same intentional failure mode
R-14-040 describes, observed here as `protocol_error` rather than `1006`/`4005` because this
relay's malformed-first-frame path returns `protocol_error` (`4003`) rather than waiting for a
Noise timeout. The handle `n6Loxf94CfyIO6hOxlaHvA` is the sample value from
`docs/14-relay-deployment.md`; it is not a secret.

**The WSS check from a phone on a cellular network was not run.** It needs the same public
infrastructure as the health check above. See [Blocked items](#blocked-items).

After verification, the stack was torn down (`docker compose down -v`), the scratch override
directory was deleted, and the locally-tagged `ghcr.io/herdr/herdr-relay-hub:v1.0.0` image was
removed, so nothing from this local run persists in this workstation's Docker state.

## Upgrade and rollback (R-14-051, R-14-052)

To upgrade the relay:

1. Replace the relay image tag in `compose.yaml`.
2. Run `docker compose pull relay`.
3. Run `docker compose up -d --no-deps relay`.

The handle map is lost during the upgrade. Every connected Host and Device reconnects with
backoff. No data migration is needed, because the relay holds no persistent state (R-12-013).

To roll back, restore the previous relay image tag in `compose.yaml` and run the same two
Compose commands (`docker compose pull relay`, `docker compose up -d --no-deps relay`).

## Backups (R-14-053, R-12-013)

The operator MUST NOT back up any relay state. The relay holds zero persistent state: the
in-memory handle map is the only routing data, nothing is written to disk, and nothing survives a
restart. The map regenerates as peers reconnect after a restart or a crash (R-12-039). There is
nothing to back up.

## Logs and payload safety (R-14-061, R-14-062)

- The operator MAY view relay logs with `docker compose logs relay`.
- The operator MUST NOT configure the relay, the container runtime or the reverse proxy to log
  WebSocket frame payloads. `docs/12-relay-hosting.md` R-12-042 lists every prohibited log field
  (a full handle, a pairing phrase, a device/host/user id, terminal content or keyboard input, a
  frame payload or ciphertext-derived data, a source IP, or any `Authorization` header, cookie or
  token). The relay enforces this internally for its own JSON log lines (R-12-043); the operator
  is responsible for keeping the reverse proxy's and the container runtime's own logs to the same
  standard (do not add a Caddy `log` directive that records request bodies or headers containing
  secrets).
- The operator SHOULD retain relay logs for at most 30 days. Relay logs contain handle prefixes
  and connection metadata; they are operational data, not audit records.

## Monitoring (R-14-070, R-14-071, R-12-051)

If the operator runs Prometheus, it SHOULD attach it to the `herdr-relay-network` Compose network
and scrape:

```text
http://relay:9090/metrics
```

The Compose deployment does not publish the metrics port to the host; only a container already
attached to `herdr-relay-network` can reach it. The metric names are listed in
`docs/12-relay-hosting.md` R-12-050 (`herdr_relay_handles_active`, `herdr_relay_handles_total`,
`herdr_relay_frames_forwarded_total`, `herdr_relay_bytes_forwarded_total`,
`herdr_relay_session_duration_seconds`, `herdr_relay_errors_total`,
`herdr_relay_connections_rejected_total`).

The operator SHOULD alert on the four conditions R-12-051 names:

1. `herdr_relay_handles_active` drops to zero while the process is alive.
2. `herdr_relay_errors_total` rate exceeds 10 per minute.
3. `herdr_relay_connections_rejected_total` rate exceeds 20 per minute.
4. `/healthz` returns non-`200` for more than 60 seconds.

## What this profile does not cover

This profile is a single instance behind one reverse proxy on one VM
(`docs/14-relay-deployment.md` §What This Profile Does Not Cover). It does not cover:

1. **Multi-region deployment.** One relay instance serves one region. Multi-region needs multiple
   VMs each running the full stack, plus DNS geo-routing.
2. **Horizontal scaling.** The in-memory handle map makes the relay single-instance. Two relay
   instances cannot share a handle map. Horizontal scaling needs a design change (a shared handle
   store or a consistent-hashing routing layer), not a configuration change. Version 1 is
   single-instance (R-14-053).
3. **High availability.** If the VM goes down, the relay goes down. Every connected peer
   reconnects with backoff. No automatic failover exists.
4. **A load balancer in front of Caddy.** One Caddy instance serves one relay instance. Adding a
   load balancer needs session affinity by handle.
5. **Kubernetes.** The relay container runs on Docker. Kubernetes deployment needs a Pod, a
   Service and an Ingress, and the single-instance constraint still applies: one replica, because
   the handle map cannot be shared.
6. **Non-Linux hosts.** The static musl binary targets Linux only. A macOS or Windows relay is not
   supported in version 1.

## Operator independence (R-12-070, R-03-030)

The app and the wire protocol MUST NOT depend on any one operator's relay deployment. The pairing
URI carries the relay origin as data; an operator chooses their own relay hostname.

Verified by search: `crates/herdr-relay-proto/src/` uses the string `relay.example.com` only in
doc comments, unit-test fixtures and `test_vectors.rs`'s worked example — every occurrence
populates the runtime `PairingUri.relay_origin` field (or a test assertion against it), never a
compiled-in default that a peer connects to without first parsing a pairing URI. `app/lib/`
contains no reference to `relay.example.com`, `ghcr.io/herdr`, `herdr-relay-hub`, or any other
operator-specific hostname or image name. Command run from the repository root:

```text
grep -rn "relay\.example\.com\|ghcr\.io/herdr\|herdr-relay-hub\|DEFAULT_RELAY" app/lib crates/herdr-relay-proto/src
```

Every hit in `crates/herdr-relay-proto/src/` is a doc comment or a test fixture that assigns the
string to a runtime `relay_origin` field; `app/lib/` has zero hits.

## Blocked items

These Phase 9 checkboxes could not be completed in this environment. Each is blocked on
infrastructure this environment does not have, not on undone work:

| Checkbox | Blocked on | What would unblock it |
|---|---|---|
| Publish the relay image and replace the placeholder tag (R-14-011) | No image registry credentials or target exist for this project | Provision an image registry (for example a `ghcr.io/herdr` organization), push the image built by `docker build -f crates/herdr-relay-hub/Dockerfile -t <real-tag> .`, then edit the `image:` line in `compose.yaml` and this runbook |
| Public `/healthz` check from outside the VM (R-14-030) | No public Linux VM, no public IPv4/IPv6, no open inbound 443/80 | Provision the VM and DNS record R-14-001 requires, deploy this Compose file there, run `curl https://<hostname>/healthz` from a network outside the VM |
| WSS check from a phone on cellular data (R-14-040, Phase 9 `Done when`) | No physical phone, no cellular network reachable from this workstation, and the public VM above does not exist yet | Once the public VM is live, run the R-14-040 `websocat` command from a phone's terminal app or from any host on a cellular network |
| Optional relay-experiment deployment gate (R-15-004 group, `docs/15-nvidia-brev-relay-experiment.md`) | Explicitly optional; skipped per this work package's assignment | Not required; no later phase depends on it |

The `Done when` line of Phase 9 (`curl -s https://<hostname>/healthz` returns `ok` from a phone on
a cell network with no VPN, and the R-14-040 `websocat` upgrade returns the `herdr-relay.v1`
subprotocol from the same network) stays unmet until the public VM, DNS record and a phone on
cellular data exist. Every other Phase 9 checkbox is complete and verified above against a local
Docker Compose stack running the exact committed `compose.yaml` and `Caddyfile`.
