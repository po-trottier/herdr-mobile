# 15 — NVIDIA Brev Relay Experiment

**Owner:** Hosting
**Status:** Internal experiment — not a product dependency

> **This document is an internal deployment experiment.** It is not a public product dependency. It
> is not an approval claim. The app never defaults to the relay origin described here. The
> public-supported profile is `docs/14-relay-deployment.md`.

## Status

| Aspect | Status |
|---|---|
| Product dependency | **No.** The app and the protocol depend on no specific relay deployment (R-12-070). |
| Approval claim | **No.** Policy status remains unverified. |
| Technical suitability | **Unverified.** The mandatory gate below has not been run. |
| App default origin | **None.** The app has no compiled default relay origin. Pairing supplies the origin. |

## Evidence

One row per source. Each row states what the source proves and what it does not prove. Sources were
consulted during the repository documentation phase. The Brev connectivity page was re-read on
2026-08-24.

### Brev Direct Instances

**R-15-001** Brev instances have a public IPv4 address. The Brev CLI documentation shows direct SSH
to `<instance-ip>` and confirms that `curl ifconfig.me` on the instance returns the public address.
The IP is stable while the instance is running but may change after a stop and restart.

Source: `https://docs.nvidia.com/brev/cli/connectivity` (re-read 2026-08-24).

What this proves: a Brev instance can receive inbound TCP if the operator configures the host
firewall. What it does not prove: that inbound port 443 is permitted by Brev's network policy
without an explicit firewall rule or approval ticket.

### Brev Tunnels (Web Console)

**R-15-002** Brev tunnels route through Cloudflare and require browser authentication on first
access. The documentation states: "For direct API access without browser authentication, use
`brev port-forward` instead."

Source: `https://docs.nvidia.com/brev/cli/connectivity`, Using Tunnels section.

What this proves: Brev tunnels are **unsuitable** as a native mobile app relay endpoint. The app
opens a raw WSS connection. It cannot complete a browser authentication redirect.

### Brev Port Forwarding

**R-15-003** `brev port-forward` creates a secure SSH tunnel from the operator's local machine to
the instance. It forwards `localhost:<local_port>` to `instance:<remote_port>`. It does not expose a
port to the public internet.

Source: `https://docs.nvidia.com/brev/cli/connectivity`, Port Forwarding section.

What this proves: port forwarding is for local development access, not for a public relay endpoint.

### Direct Inbound WSS

**R-15-004** Direct inbound WSS on port 443 from the public internet is **unverified**. The Brev
documentation does not mention binding a public port, configuring a host firewall or accepting
inbound TLS from arbitrary clients. The mandatory gate is designed to test this.

### Horde

Horde provides GPU instances with IP addresses. Non-corporate inbound access requires firewall
handling. Horde is a compute platform, not a public-ingress platform. It is not documented as a
supported public relay host.

Source (internal): `https://nvidia.atlassian.net/wiki/spaces/MLOPS/pages/3169590353`

### Omnistation

Omnistation access uses VPN or Teleport. It does not provide a public-internet URL without a VPN
client. It is not a supported public relay host.

Source (internal): `https://nvidia.atlassian.net/wiki/spaces/EngInfoSec/pages/2258666985`

### Databricks Apps

Databricks Apps require onboarding and are an application-hosting platform. They are not a proven
raw public WSS relay endpoint. They are not a supported public relay host.

### OpenShell

OpenShell remote service URLs require gateway authentication. An unauthenticated WebSocket upgrade
from a mobile app is not supported. OpenShell is not a supported public relay host.

Source (internal): `https://nvidia.atlassian.net/wiki/spaces/COS/pages/2189787550`

### Codexter Precedent

Codexter used an ITSS VM, ITSS DNS, Caddy and the NVIDIA Private CA. This pattern proves that an
internal corporate or VPN-only relay service works. It is **not** evidence of public mobile
reachability: the NVIDIA Private CA certificate is not trusted by a phone on a cell network, and the
ITSS DNS name does not resolve on the public internet.

## Mandatory Gate

This gate determines technical suitability. It does not determine policy approval. Run each step in
order. Record the result.

- [ ] **Step 1 — Provision a Brev VM.** Create a Brev instance with a public IP. Record the instance
  ID and the public IPv4 address.
- [ ] **Step 2 — Install Docker on the instance.** Follow
  `docs/14-relay-deployment.md` prerequisites R-14-001 and R-14-002. Ensure Docker is installed
  and running.
- [ ] **Step 3 — Deploy the Compose services.** Deploy the `herdr-relay-hub` relay and Caddy per
  `docs/14-relay-deployment.md` R-14-010, R-14-021 and R-14-022. This deployment runs Caddy from
  the `caddy:2.11.4` container image and runs the relay service with Caddy on the shared private
  network. Caddy forwards to `relay:8080`. Do not install Caddy on the host or run separate relay
  and Caddy processes.
- [ ] **Step 4 — Configure public ingress.** Configure the Compose deployment Caddyfile with a
  self-signed certificate or a Let's Encrypt certificate for a DNS name that points at the Brev
  instance public IP. Verify that `curl -k https://<brev-ip>/healthz` returns `200 ok` from the
  instance itself.
- [ ] **Step 5 — Cellular-data WSS upgrade.** From a phone on **cellular data** (Wi-Fi disabled),
  open a WebSocket connection to `wss://<brev-ip-or-dns>/host/<handle>` with subprotocol
  `herdr-relay.v1`. Use a test client such as a short Flutter snippet or a WebSocket testing app.
  Confirm that the TCP handshake, the TLS handshake and the WebSocket upgrade all complete **with no
  browser authentication redirect, no portal interception and no certificate error**.
- [ ] **Step 6 — Service lifetime.** Keep the instance and relay running for 72 hours. Verify that
  the public IP is unchanged, the relay `/healthz` still returns `200`, and the WSS upgrade still
  succeeds.
- [ ] **Step 7 — Stop.** Record the results.

### Pass Criteria

Every step succeeds. The cellular-data WSS upgrade completes without browser authentication. The
public IP survives the service lifetime. The relay remains reachable for the full 72 hours.

### Fail Criteria

Any step fails. The most likely failure is Step 5: the phone cannot complete a raw WSS upgrade
because Brev's network blocks inbound port 443, or a portal intercepts the connection, or the TLS
handshake fails because no public CA trusts the certificate.

## Failure Path

**R-15-010** If any gate step fails, the Brev profile remains unsupported. The NVIDIA relay MUST
use a separately provisioned public VM under applicable NVIDIA policy, following
`docs/14-relay-deployment.md`. The Brev experiment document records the failure and the reason, and
is not updated further unless someone re-runs the gate with changed conditions.

**R-15-011** If the gate passes every step, the Brev profile becomes a supported NVIDIA-internal
deployment option. The document is updated to record the pass, the instance configuration and any
operational notes. It remains an internal experiment: the app still has no default relay origin, and
the public profile in `docs/14-relay-deployment.md` remains the vendor-neutral recommendation.

## Policy Status

**Policy status remains unverified.** This document records technical evidence only. Whether an
NVIDIA employee may provision a Brev instance for this purpose, bind a public port, obtain a public
DNS name pointing at it, and operate a relay service that forwards encrypted terminal content from
the corporate network to the public internet — these questions have not been answered by any source
consulted during this documentation phase. They need an explicit answer from the applicable policy
owner before the relay is deployed on Brev.

## Internal Sources Appendix

The URLs in this appendix are internal NVIDIA resources. They are checked only from the NVIDIA
network. They are kept here as evidence of what was consulted, not as links for a public reader.

- Horde / NVPARK platform: `https://nvidia.atlassian.net/wiki/spaces/MLOPS/pages/3169590353`
- Omnistation / Teleport for Farm: `https://nvidia.atlassian.net/wiki/spaces/EngInfoSec/pages/2258666985`
- OpenShell / nvproxy: `https://nvidia.atlassian.net/wiki/spaces/COS/pages/2189787550`
- Brev CLI connectivity: `https://docs.nvidia.com/brev/cli/connectivity` (public)
- DMZ Architecture Standard: `https://nvidia.atlassian.net/wiki/spaces/INS/pages/2814218760`
- Network Security Standard: `https://nvidia.atlassian.net/wiki/spaces/INS/pages/2814218976`
- Cloudflare at NVIDIA: `https://nvidia.atlassian.net/wiki/spaces/TEC/pages/2857392236`

## Sources

- `docs/12-relay-hosting.md` — relay architecture requirements, endpoints, rate limits
- `docs/14-relay-deployment.md` — the supported public deployment profile
- `docs/03-product-decisions.md` §4 — app has no default relay origin, pairing supplies origin
- `https://docs.nvidia.com/brev/cli/connectivity` — re-read 2026-08-24, confirmed public IP, tunnel
  limitations, port-forwarding scope
