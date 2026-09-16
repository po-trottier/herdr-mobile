# 14 — Relay Deployment: The Supported Public Profile

**Owner:** Hosting
**Status:** Draft — documentation phase

This document gives one supported deployment profile for `herdr-relay-hub`. It is copy-ready: an
operator follows the steps on a clean public Linux VM and gets a working relay. No shell installer,
no task runner and no script. Direct `docker compose` commands only.

## Prerequisites

**R-14-001** The operator MUST have:

- A Linux VM with a **public IPv4 address** reachable from the internet
- A **public DNS A record** that points a hostname at that IPv4 address. If the VM has a public IPv6
  address, an AAAA record as well.
- **Inbound TCP port 443** open to the public internet
- **Inbound TCP port 80** open to the public internet, only for the ACME HTTP-01 challenge. After
  the first certificate issuance, port 80 may be closed if the operator uses a DNS challenge or
  Caddy's automatic renewal succeeds over TLS-ALPN.
- **Docker** installed. Docker Engine 24 or later, with the Docker Compose plugin and support for
  the `unless-stopped` restart policy. This is the only relay software installed on the VM. The
  operator MUST NOT install Rust, Cargo, a musl toolchain or Caddy on the host.

**R-14-002** The VM MUST run a supported Linux distribution. Ubuntu 24.04 LTS and Debian 12 are
tested targets. Other distributions that ship Docker and a systemd init are expected to work.

## Compose Deployment

**R-14-010** The operator MUST deploy the relay and Caddy with this `compose.yaml` file:

```yaml
services:
  relay:
    image: ghcr.io/po-trottier/herdr-relay-hub:latest
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

Save the Caddyfile beside `compose.yaml`. Start both services with:

```bash
docker compose up -d
```

**R-14-011** The supported image MUST be `ghcr.io/po-trottier/herdr-relay-hub:latest`.
The container contains the static musl Linux binary. R-40-058 owns image publication and tag rules.
Pull the supported image with:

```bash
docker pull ghcr.io/po-trottier/herdr-relay-hub:latest
```

GHCR packages are private on first publication. The package owner MUST set this package to public
for an operator to pull it without credentials.

**R-14-012** The relay container MUST be named `herdr-relay-hub`. Its restart policy MUST be
`unless-stopped`.

**R-14-013** The relay MUST NOT publish a host port. It listens on `0.0.0.0:8080` only on the
`herdr-relay-network` network. Caddy reaches it by the `relay` service name. The relay is never
directly exposed to the public internet.

**R-14-014** The `relay.environment` block configures these variables:

| Variable | Value | Description |
|---|---|---|
| `HERDR_RELAY_LISTEN` | `0.0.0.0:8080` | Address the relay binds inside the container |
| `HERDR_RELAY_METRICS_LISTEN` | `0.0.0.0:9090` | Private-network address for the `/metrics` endpoint |
| `HERDR_RELAY_MAX_HANDLES` | `4096` | Maximum registered handles |
| `HERDR_RELAY_CONNECTION_RATE` | `10` | Maximum new WebSocket connections per second per source IP |
| `HERDR_RELAY_FRAME_RATE` | `100` | Maximum frames per second per connection |
| `HERDR_RELAY_HANDLE_RATE` | `5` | Maximum new handle registrations per second per source IP |
| `HERDR_RELAY_LOG_JSON` | `true` | Emit JSON log lines to stdout |

The Compose file sets all standard values. `docs/12-relay-hosting.md` owns the normative
requirements behind each limit.

**R-14-015** The relay logging driver MUST be `json-file`. The Compose file MUST set
`max-size=10m` and `max-file=3` to bound log disk use.

## Reverse Proxy: Caddy

**R-14-020** The operator MUST run Caddy as the TLS-terminating reverse proxy.

**R-14-021** The Caddyfile MUST contain:

```caddyfile
relay.example.com {
    reverse_proxy relay:8080
}
```

Replace `relay.example.com` with the operator's public DNS hostname. The `relay` target is the
Compose service name on `herdr-relay-network`.

Caddy 2.11.4 obtains a public TLS certificate automatically through Let's Encrypt on the first
request. No certificate step, no `certbot` command and no manual renewal are needed. The operator
ensures port 80 is reachable during the first launch for the ACME HTTP-01 challenge.

**R-14-022** Caddy MUST run as the `caddy` service in the Compose deployment, with
`restart: unless-stopped` and the exact `caddy:2.11.4` image. It MUST publish ports 80 and 443.
The relay service MUST publish no host port.

Port 80 is published for certificate issuance and renewal.

**R-14-024** An operator whose Compose tool manages only `compose.yaml` and `.env` (Arcane and
similar UIs) MAY replace the `./Caddyfile` bind mount of R-14-010 with a Compose inline config.
The Caddyfile text MUST stay the R-14-021 text; only its delivery changes:

```yaml
  caddy:
    configs:
      - source: caddyfile
        target: /etc/caddy/Caddyfile

configs:
  caddyfile:
    content: |
      ${RELAY_HOSTNAME} {
          reverse_proxy relay:8080
      }
```

`RELAY_HOSTNAME` is set in the project's `.env` file. Every other line of R-14-010 stays as
written. Inline `configs.content` needs Compose 2.23.1 or later.

**R-14-023** Caddy handles the WebSocket upgrade automatically. The `reverse_proxy` directive
forwards the `Connection: Upgrade` and `Upgrade: websocket` headers without extra configuration.

## Health Verification

**R-14-030** After both Compose services are running, the operator MUST verify health:

```bash
docker compose ps

# Local check through the Caddy service.
curl --fail --silent --show-error \
  --resolve relay.example.com:443:127.0.0.1 \
  https://relay.example.com/healthz
# Expected: 200 OK, body "ok"

# Public check.
curl --fail --silent --show-error https://relay.example.com/healthz
# Expected: 200 OK, body "ok"
```

**R-14-031** If both Compose services are running and the public check fails, the operator MUST
verify DNS resolution, Caddy logs and firewall rules for ports 80 and 443.

## WSS Verification

**R-14-040** The operator SHOULD verify that the relay accepts a WebSocket upgrade on the
handle-specific paths. Use a WebSocket client. This example uses `websocat`:

```bash
# Test /host/<handle> upgrade
echo '{"type":"host_info","protocol":1}' | \
  websocat -n --protocol herdr-relay.v1 \
  wss://relay.example.com/host/n6Loxf94CfyIO6hOxlaHvA
```

The relay accepts the upgrade, returns the `herdr-relay.v1` subprotocol, and then closes with
`1006` or `4005` after the Noise handshake fails (because this test sends a fake first frame). The
critical observation is that the **WebSocket upgrade succeeds** and the subprotocol is accepted. A
TCP connection refused or a TLS error means the relay is not reachable on WSS.

The handle `n6Loxf94CfyIO6hOxlaHvA` is a sample value from the project documentation. It is not a
secret.

## Service Lifetime

**R-14-050** The relay and Caddy `unless-stopped` restart policies ensure both services restart
after a host reboot or Docker daemon restart.

**R-14-051** To upgrade the relay, the operator MUST:

1. Replace the relay image tag in `compose.yaml`.
2. Run `docker compose pull relay`.
3. Run `docker compose up -d --no-deps relay`.

The handle map is lost during the upgrade. Every connected Host and Device reconnects with backoff.
No data migration is needed.

**R-14-052** To roll back, the operator MUST restore the previous relay image tag in
`compose.yaml` and run the same Compose commands.

**R-14-053** The operator MUST NOT back up any relay state. The relay holds zero persistent state
(R-12-013). The in-memory handle map is regenerated when peers reconnect after a restart.

## Logs and Payload Safety

**R-14-060** The operator MAY view relay logs with:

```bash
docker compose logs relay
```

**R-14-061** The operator MUST NOT configure the relay, the container runtime or the reverse proxy
to log WebSocket frame payloads. `docs/12-relay-hosting.md` R-12-042 lists every prohibited log
content item. The relay enforces this internally (R-12-043). The operator is responsible for the
reverse proxy and container runtime configuration.

**R-14-062** The operator SHOULD retain relay logs for at most 30 days. Relay logs contain handle
prefixes and connection metadata. They are operational data, not audit records.

## Monitoring

**R-14-070** If the operator runs Prometheus, it SHOULD attach it to `herdr-relay-network` and
scrape `http://relay:9090/metrics`. The Compose deployment does not publish the metrics port. The
metric names are listed in `docs/12-relay-hosting.md` R-12-050.

**R-14-071** The operator SHOULD alert on the conditions listed in
`docs/12-relay-hosting.md` R-12-051.

## What This Profile Does Not Cover

This profile is a **single instance** behind one reverse proxy on one VM. It does not cover:

- **Multi-region deployment.** One relay instance serves one region. A Device in a distant region
  sees higher latency. Multi-region needs multiple VMs each running the full stack, plus DNS
  geo-routing.
- **Horizontal scaling.** The in-memory handle map makes the relay single-instance. Two relay
  instances cannot share a handle map. Horizontal scaling needs a design change (a shared handle
  store or a consistent-hashing routing layer), not a configuration change. Version 1 is
  single-instance.
- **High availability.** If the VM goes down, the relay goes down. Every connected peer reconnects
  with backoff. No automatic failover exists.
- **Load balancer in front of Caddy.** One Caddy instance serves one relay instance. Adding a load
  balancer needs session affinity by handle.
- **Kubernetes.** The relay container runs on Docker. Kubernetes deployment needs a Pod, a Service
  and an Ingress, and the single-instance constraint still applies: one replica, because the handle
  map cannot be shared.
- **Non-Linux hosts.** The static musl binary targets Linux only. A macOS or Windows relay is not
  supported in version 1.

## Sources

- GitHub Actions package publication — <https://docs.github.com/en/actions/publishing-packages/publishing-docker-images>.
  Confirms GHCR login with `GITHUB_TOKEN`, `packages: write`, and Docker metadata and build actions.
- GitHub Container Registry — <https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry>.
  Confirms the initial private visibility and anonymous pulls for public container packages.

- `docs/12-relay-hosting.md` — endpoint definitions, size and rate limits, log-field allow list,
  metric names, alert conditions

- Docker Compose file reference — `https://docs.docker.com/reference/compose-file/`.
- Docker Compose `configs` top-level element — `https://docs.docker.com/reference/compose-file/configs/`.
  Confirms inline `content` for a config, available since Compose 2.23.1.
- Caddy 2.11.4 release — `https://github.com/caddyserver/caddy/releases/tag/v2.11.4`.
