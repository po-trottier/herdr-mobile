# 14 — Relay Deployment: Relay-Only Profile

**Owner:** Hosting
**Status:** Draft — documentation phase

This profile runs only `herdr-relay-hub` on a Linux machine.
The operator's TLS ingress runs outside this repository's deployment stack.
Use Docker Compose directly. No installer or task runner is required.

## Prerequisites

**R-14-001** The operator MUST have:

- A Linux machine with access to the container registry.
- Docker Engine 24 or later with Compose v2.
- An ingress that terminates TLS and passes WebSocket upgrades.
- An ingress route that can reach the relay's bound address.
- A public hostname with a valid TLS certificate on that ingress.

The operator does not need Rust, Cargo, or a musl toolchain on the deployment machine.
Replace `relay.example.com` below with the configured public hostname.

**R-14-002** The machine MUST run a supported Linux distribution.
Ubuntu 24.04 LTS and Debian 12 are supported targets for this profile.

## Compose Deployment

**R-14-010** The operator MUST deploy the relay with `deploy/relay/compose.yaml`:

```yaml
# Relay-only deployment profile: R-14-010.
# Directory and optional local environment: R-14-024.
# The operator supplies the TLS ingress outside this repository.
services:
  relay:
    image: ghcr.io/po-trottier/herdr-relay-hub:latest
    container_name: herdr-relay-hub
    restart: unless-stopped
    ports: ["${RELAY_BIND:-127.0.0.1:8080}:8080"]
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
```

The Docker Compose reference in Sources defines the service configuration.
Run these commands from `deploy/relay/`:

```bash
docker compose config --quiet
docker compose pull
docker compose up -d
```

**R-14-011** The relay image MUST be `ghcr.io/po-trottier/herdr-relay-hub:latest`.
R-40-058 owns publication. GHCR package visibility MUST permit anonymous pulls:

```bash
docker pull ghcr.io/po-trottier/herdr-relay-hub:latest
```

The GitHub Container Registry source documents anonymous pulls for public packages.

**R-14-012** The relay container MUST be named `herdr-relay-hub`.
Its restart policy MUST be `unless-stopped`.

**R-14-013** The relay MUST bind the host address and port in `RELAY_BIND`.
The default is `127.0.0.1:8080`.
The relay MUST NOT be exposed directly to the public internet.
Public clients MUST reach it only through the operator's TLS ingress.

A host ingress can use the default loopback address.
An ingress in a separate container can require another address, such as `172.18.0.1:8080`.
The operator can also set `0.0.0.0:8080` and restrict access with the host firewall.
A non-loopback bind does not provide access control by itself.

**R-14-014** The `relay.environment` block MUST use these values:

| Variable | Value | Owner or purpose |
| --- | --- | --- |
| `HERDR_RELAY_LISTEN` | `0.0.0.0:8080` | Relay endpoint inside the container |
| `HERDR_RELAY_METRICS_LISTEN` | `0.0.0.0:9090` | Private metrics endpoint; R-12-050 |
| `HERDR_RELAY_MAX_HANDLES` | `4096` | R-12-034 |
| `HERDR_RELAY_CONNECTION_RATE` | `10` | R-12-031 |
| `HERDR_RELAY_FRAME_RATE` | `100` | R-12-032 |
| `HERDR_RELAY_HANDLE_RATE` | `5` | R-12-033 |
| `HERDR_RELAY_LOG_JSON` | `true` | JSON logs |

The relay takes the client IP for its per-IP limits from `CF-Connecting-IP` or
`X-Forwarded-For` when the ingress sets one, else from the TCP peer (R-12-071). Nothing to
configure. R-12-042 owns log restrictions.

**R-14-015** The relay MUST use the `json-file` log driver.
Set `max-size=10m` and `max-file=3` to bound disk use.

## Ingress requirements

**R-14-025** The operator's TLS ingress MUST terminate TLS and pass WebSocket upgrades.
It MUST route `/healthz` to the relay.
It SHOULD write the client's address in `CF-Connecting-IP` or `X-Forwarded-For`, replacing any
client-supplied value, so the per-IP limits count clients and not the ingress (R-12-071).
The ingress is outside this repository's scope. This profile gives no ingress configuration example.

## Deployment directory

**R-14-024** The committed `deploy/relay/` directory MUST contain only `compose.yaml`.
A GitOps deployment MUST select that file from `main`.
The operator MAY create an optional, uncommitted `.env` beside it with this override:

```dotenv
RELAY_BIND=127.0.0.1:8080
```

The variable has a default. Compose works without `.env`.
The operator MUST NOT commit `.env` or any secret.

## Health Verification

**R-14-030** After the relay starts, the operator MUST check it from the host and through the ingress:

```bash
docker compose ps
curl --fail --silent --show-error http://127.0.0.1:8080/healthz
curl --fail --silent --show-error https://relay.example.com/healthz
# Expected for each request: HTTP 200 and body "ok".
```

Use the configured host address for the first request if `RELAY_BIND` is not the default.

**R-14-031** If a check fails, the operator MUST check relay logs, DNS, and the operator's TLS ingress.
Check the ingress route, its access to the bound relay address, and the host firewall.

## WSS Verification

**R-14-040** The operator SHOULD verify a WebSocket upgrade through the same public hostname:

```bash
websocat -v --protocol herdr-relay.v1 \
  wss://relay.example.com/host/n6Loxf94CfyIO6hOxlaHvA
```

Confirm that the connection opens with the `herdr-relay.v1` subprotocol.
Then close the test connection with Ctrl+C. The example handle is not a secret.
This checks the upgrade, not pairing or an encrypted session.
A TLS error, HTTP error, or refused connection means the WSS check failed.

## Service Lifetime

**R-14-050** The relay MUST use `unless-stopped` so Docker restarts it after a reboot.
A service that the operator explicitly stops remains stopped.

**R-14-051** Before an upgrade, the operator MUST record the current image digest:

```bash
docker image inspect ghcr.io/po-trottier/herdr-relay-hub:latest \
  --format '{{index .RepoDigests 0}}'
```

To upgrade the relay, keep the R-14-011 image name and run:

```bash
docker compose pull relay
docker compose up -d relay
```

Repeat R-14-030 and R-14-040 after the upgrade.
A container restart interrupts connections. R-12-013 owns relay state lifetime.

**R-14-052** To roll back, the operator MUST set the relay image to the recorded digest.
Run `docker compose pull relay`, then `docker compose up -d relay`.
Repeat R-14-030 and R-14-040.
The digest is a temporary rollback override for the normal image.
Restore the normal image when a verified replacement is available.

**R-14-053** The operator MUST NOT back up relay state; see R-12-013.

## Logs and Payload Safety

**R-14-060** The operator MAY inspect the relay with:

```bash
docker compose logs relay
```

**R-14-061** The operator MUST apply R-12-042 to relay, ingress, and container log configuration.
Do not enable request-header or WebSocket-payload debug logs.
R-12-043 owns relay-side enforcement. The operator controls external log configuration.

**R-14-062** The operator SHOULD retain operational logs for at most 30 days.

## Monitoring

**R-14-070** The operator SHOULD scrape the private metrics endpoint specified by R-12-050.
This profile does not publish the metrics port or include a monitoring service.
The operator supplies any private metrics access in a separate deployment override.

**R-14-071** The operator SHOULD use the alert conditions in R-12-051.

## What This Profile Does Not Cover

This profile runs one relay instance on one machine.
It does not provide ingress, horizontal scaling, multi-region routing, automatic failover, or Kubernetes.
The relay's handle map remains in memory. A machine failure disconnects the relay's clients.

## Retired rules

IDs remain reserved. No live rule was renumbered.
The owner moved every ingress out of the repository on 2026-09-16.

| Rule | Disposition |
| --- | --- |
| `R-14-020` | Retired 2026-09-16: Caddy TLS ingress moved outside the repository. |
| `R-14-021` | Retired 2026-09-16: Caddyfile configuration moved outside the repository. |
| `R-14-022` | Retired 2026-09-16: Caddy image selection moved outside the repository. |
| `R-14-023` | Retired 2026-09-16: Caddy WebSocket ingress moved outside the repository. |

## Sources

- Docker Compose reference — <https://docs.docker.com/reference/compose-file/>.

  Defines the service configuration used by R-14-010.

- GitHub Container Registry —

  <https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry>.

  Documents anonymous pulls for public container packages in R-14-011.
