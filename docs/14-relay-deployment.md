# 14 — Relay Deployment: Supported Public Profile

**Owner:** Hosting
**Status:** Draft — documentation phase

This profile runs `herdr-relay-hub` beside a Cloudflare Tunnel container on a Linux machine.
Use Docker Compose directly. No installer or task runner is required.

## Prerequisites

**R-14-001** The operator MUST have:

- A Linux machine with outbound internet access. No public IP address or inbound ports are required.
- Docker Engine 24 or later and the Docker Compose plugin.
- A Cloudflare account with the public hostname's DNS zone active in Cloudflare.
- A remotely managed tunnel created in the Cloudflare Zero Trust dashboard.
- A public hostname on that tunnel with service `http://relay:8080`.
- The tunnel token from the dashboard, stored in `.env` per R-14-024.

The operator MUST NOT install Rust, Cargo, or the musl toolchain on the deployment machine.
Allow outbound tunnel connections. Do not open inbound firewall ports.
Replace `relay.example.com` below with the configured public hostname.

**R-14-002** The machine MUST run a supported Linux distribution.
Ubuntu 24.04 LTS and Debian 12 are the supported targets for this profile.

## Compose Deployment

**R-14-010** The operator MUST deploy the relay and `cloudflared` with this `compose.yaml`:

```yaml
services:
  relay:
    image: ghcr.io/po-trottier/herdr-relay-hub:latest
    container_name: herdr-relay-hub
    restart: unless-stopped
    environment:
      HERDR_RELAY_LISTEN: "0.0.0.0:8080"
      HERDR_RELAY_METRICS_LISTEN: "0.0.0.0:9090"
      HERDR_RELAY_CLIENT_IP_HEADER: "CF-Connecting-IP"
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

  cloudflared:
    image: cloudflare/cloudflared:2026.9.0
    restart: unless-stopped
    command: tunnel --no-autoupdate run
    environment:
      TUNNEL_TOKEN: ${TUNNEL_TOKEN:?set TUNNEL_TOKEN in .env}
    depends_on:
      - relay
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
    networks:
      - relay

networks:
  relay:
    name: herdr-relay-network
```

Run these commands from `deploy/relay/` after creating `.env`:

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

**R-14-012** The relay container MUST be named `herdr-relay-hub`.
Its restart policy MUST be `unless-stopped`.

**R-14-013** The relay MUST NOT publish a host port.
The `cloudflared` container reaches `relay:8080` on `herdr-relay-network`.
Only trusted containers MAY join this network, because the relay trusts the configured client-IP header.

**R-14-014** The `relay.environment` block MUST use these values:

| Variable | Value | Owner or purpose |
| --- | --- | --- |
| `HERDR_RELAY_LISTEN` | `0.0.0.0:8080` | Relay endpoint inside the container |
| `HERDR_RELAY_METRICS_LISTEN` | `0.0.0.0:9090` | Private metrics endpoint; R-12-050 |
| `HERDR_RELAY_CLIENT_IP_HEADER` | `CF-Connecting-IP` | Trusted client IP; R-12-071 |
| `HERDR_RELAY_MAX_HANDLES` | `4096` | Handle limit; docs/12 |
| `HERDR_RELAY_CONNECTION_RATE` | `10` | R-12-031 |
| `HERDR_RELAY_FRAME_RATE` | `100` | R-12-032 |
| `HERDR_RELAY_HANDLE_RATE` | `5` | R-12-033 |
| `HERDR_RELAY_LOG_JSON` | `true` | JSON logs |

R-12-071 owns header parsing, peer-IP fallback, and use by the per-IP limits.
R-12-042 owns log restrictions.

**R-14-015** Both containers MUST use the `json-file` log driver.
Set `max-size=10m` and `max-file=3` to bound disk use.

## Cloudflare Tunnel

Cloudflare terminates public TLS at its edge and forwards requests through the encrypted tunnel.
The final connection from `cloudflared` to `relay:8080` uses HTTP on the Docker network.
Cloudflare supports WebSocket upgrades; the public relay URL uses `wss://`.
The sources below document these properties.

**R-14-024** The committed deployment directory, `deploy/relay/`, MUST contain only `compose.yaml`.
A GitOps deployment MUST select that file from `main`.
The operator MUST put `TUNNEL_TOKEN` in an uncommitted `.env` beside it.
The operator MUST NOT commit the token or any other secret.
The hostname and its `http://relay:8080` service stay in the Cloudflare Zero Trust dashboard.

Create `.env` with this entry, then replace the example value with the dashboard token:

```dotenv
TUNNEL_TOKEN=replace-with-your-tunnel-token
```

Restrict access to this file. A tunnel token permits a connector to run that tunnel.
The container uses `TUNNEL_TOKEN`, the environment equivalent of `tunnel run --token`.
The image pin `cloudflare/cloudflared:2026.9.0` was verified on Docker Hub on 2026-09-16.

## Health Verification

**R-14-030** After both services start, the operator MUST check the public hostname:

```bash
docker compose ps
curl --fail --silent --show-error https://relay.example.com/healthz
# Expected: HTTP 200 and body "ok".
```

There is no local host port to check. The public request checks the complete tunnel route.

**R-14-031** If the check fails, the operator MUST check both container logs and the tunnel status.
Check DNS resolution and the dashboard route to `http://relay:8080`.
Check outbound tunnel access, not inbound ports.

## WSS Verification

**R-14-040** The operator SHOULD verify a WebSocket upgrade through the same public hostname:

```bash
websocat -v --protocol herdr-relay.v1 \
  wss://relay.example.com/host/n6Loxf94CfyIO6hOxlaHvA
```

Confirm that the WebSocket connection opens with the `herdr-relay.v1` subprotocol.
Then close the test connection with Ctrl+C. The example handle is not a secret.
This checks the upgrade, not pairing or an encrypted session.
A TLS error, an HTTP error, or a refused connection means that the WSS check failed.

## Service Lifetime

**R-14-050** Both services MUST use `unless-stopped` so Docker restarts them after a reboot.
A service that the operator explicitly stops remains stopped.

**R-14-051** Before an upgrade, the operator MUST record the current image digests:

```bash
docker image inspect ghcr.io/po-trottier/herdr-relay-hub:latest \
  --format '{{index .RepoDigests 0}}'
docker image inspect cloudflare/cloudflared:2026.9.0 \
  --format '{{index .RepoDigests 0}}'
```

To upgrade the relay, keep the R-14-011 image name and run:

```bash
docker compose pull relay
docker compose up -d --no-deps relay
```

To upgrade `cloudflared`, verify the new exact image tag and update its Compose image value.
Then run:

```bash
docker compose pull cloudflared
docker compose up -d --no-deps cloudflared
```

Repeat R-14-030 and R-14-040 after either upgrade.
A container restart interrupts connections. R-12-013 owns relay state lifetime.

**R-14-052** To roll back, the operator MUST set the affected service's image to its recorded digest.
Run `docker compose pull <service>`, then `docker compose up -d --no-deps <service>`.
Replace `<service>` with `relay` or `cloudflared`. Repeat R-14-030 and R-14-040.
The digest is a temporary rollback override of the normal image pin.
Restore the normal image value after a verified replacement is available.

**R-14-053** The operator MUST NOT back up relay state; see R-12-013.
Keep the tunnel token separate from logs and repository backups.

## Logs and Payload Safety

**R-14-060** The operator MAY inspect both services with:

```bash
docker compose logs relay
docker compose logs cloudflared
```

**R-14-061** The operator MUST apply R-12-042 to relay, tunnel, and container log configuration.
Do not enable request-header or WebSocket-payload debug logs.
R-12-043 owns relay-side enforcement. The operator controls external log configuration.

**R-14-062** The operator SHOULD retain operational logs for at most 30 days.

## Monitoring

**R-14-070** A trusted Prometheus container SHOULD join `herdr-relay-network` and scrape
`http://relay:9090/metrics`. The profile does not publish the metrics port.
R-12-050 owns the metric names.

**R-14-071** The operator SHOULD use the alert conditions in R-12-051.

## What This Profile Does Not Cover

This profile runs one relay instance on one machine. It does not provide horizontal scaling,
multi-region routing, automatic failover, or a Kubernetes deployment.
A tunnel does not make the relay's in-memory handle map shared or persistent.
A machine failure disconnects the relay's clients.

## Retired rules

These IDs remain reserved. No live rule was renumbered.

| Rule | Disposition |
| --- | --- |
| `R-14-020` | **Retired 2026-09-16.** Cloudflare Tunnel replaces the Caddy TLS proxy; see R-14-010. |
| `R-14-021` | **Retired 2026-09-16.** The dashboard route replaces the Caddyfile; see R-14-024. |
| `R-14-022` | **Retired 2026-09-16.** The cloudflared image replaces the Caddy image; see R-14-010. |
| `R-14-023` | **Retired 2026-09-16.** Cloudflare replaces Caddy WebSocket upgrades; see R-14-040. |

## Sources

- Cloudflare Docker image — <https://hub.docker.com/r/cloudflare/cloudflared>.
  Tag verification on 2026-09-16:
  <https://hub.docker.com/v2/repositories/cloudflare/cloudflared/tags/2026.9.0>.
  The API returned HTTP 200 and an active tag with Linux amd64 and arm64 images.
- Tunnel setup — <https://developers.cloudflare.com/tunnel/setup/>.
  Documents dashboard configuration and the Docker command.
- Run parameters —
  <https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/configure-tunnels/run-parameters/>.
  Documents `tunnel run --token` and its `TUNNEL_TOKEN` environment variable.
- Tunnel tokens — <https://developers.cloudflare.com/tunnel/reference/tunnel-tokens/>.
  Documents token access and remotely managed tunnels.
- WebSockets — <https://developers.cloudflare.com/network/websockets/>.
  Confirms support for proxied WebSocket connections.
- TLS concepts — <https://developers.cloudflare.com/ssl/concepts/>.
  Explains the edge certificate presented to clients and the separate origin connection.
- Tunnel origin protocols —
  <https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/routing-to-tunnel/protocols/>.
  Documents HTTPS requests proxied to an HTTP origin through the tunnel.
- Docker Compose reference — <https://docs.docker.com/reference/compose-file/>.
- GitHub Container Registry —
  <https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry>.
  Documents anonymous pulls for public container packages.
