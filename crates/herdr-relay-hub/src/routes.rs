//! The relay's `axum` router: the WebSocket rendezvous routes, `/healthz` and
//! `/metrics` (`docs/12-relay-hosting.md` "## Endpoints", R-12-020, R-12-021,
//! R-12-023), the connection-rate limit (R-12-031) and the shared [`AppState`]
//! every handler reads. The registration-frame handshake itself
//! (R-11-113 to R-11-120) lives in `routes::registration`.
//!
//! `pub(crate) mod config/limits/logging/metrics/registration` are nested here
//! rather than as crate-root siblings declared in `lib.rs`: `lib.rs` stays
//! `WP-3`'s (Phase 3), and this phase's authorized exception covers exactly
//! `routes.rs`, `session.rs` and `relay.rs` (`docs/90-implementation-plan.md`
//! §5.2 `WP-8`). Rust resolves a `mod` declared inside `routes.rs` against
//! `src/routes/<name>.rs`, so these utility modules need no `lib.rs` change;
//! `pub(crate)` makes them reachable from `session.rs`/`relay.rs` too.

pub(crate) mod config;
mod connection;
pub(crate) mod limits;
pub(crate) mod logging;
pub(crate) mod metrics;
mod registration;

use std::net::{IpAddr, SocketAddr};
use std::sync::Arc;
use std::time::Duration;

use axum::Router;
use axum::extract::ws::WebSocketUpgrade;
use axum::extract::{ConnectInfo, Path, State};
use axum::http::{HeaderMap, header};
use axum::response::{IntoResponse, Response};
use axum::routing::get;
use herdr_relay_proto::handle::Handle;

use self::limits::IpRateLimiter;
use self::metrics::Metrics;
use crate::session::{Role, SessionMap};

pub(crate) use registration::handle_first_6;

/// The one relay wire subprotocol every connection MUST request (R-12-020, R-11-013).
const SUBPROTOCOL: &str = "herdr-relay.v1";

/// R-12-030: the single frame-size limit for the whole repository (also cited as
/// R-11-035, R-41-039).
pub(crate) const MAX_FRAME_BYTES: usize = 1_048_576;

/// How long the relay waits for the registration frame (R-11-113, R-11-114) after a
/// successful upgrade before giving up with `protocol_error`. Not itself a numbered
/// rule: the doc requires the frame, not a specific wait bound, so this reuses the
/// crate's existing bounded-I/O convention (R-41-131) rather than waiting forever.
const REGISTER_TIMEOUT: Duration = Duration::from_secs(10);

/// The shared state every route handler reads: the handle-routing map, the
/// Prometheus counters, the two IP-keyed rate limiters and the resolved
/// environment configuration (R-14-014).
#[derive(Clone)]
pub(crate) struct AppState {
    pub(crate) sessions: SessionMap,
    pub(crate) metrics: Arc<Metrics>,
    pub(crate) limits: Arc<Limits>,
    pub(crate) config: config::Config,
}

/// The two IP-keyed rate limiters (R-12-031, R-12-033). Frame-rate limiting
/// (R-12-032) lives per connection in `relay.rs` instead — it has no IP to key on
/// and needs no shared/locked state.
pub(crate) struct Limits {
    pub(crate) connections: IpRateLimiter,
    pub(crate) handles: IpRateLimiter,
}

/// Builds the relay's two routers, sharing one [`AppState`]: the main rendezvous
/// router (`/host/<handle>`, `/device/<handle>`, `/healthz`) for `HERDR_RELAY_LISTEN`,
/// and a `/metrics`-only router for the separately bound `HERDR_RELAY_METRICS_LISTEN`
/// (R-12-024). Reads the environment fresh on every call (see `config`'s doc
/// comment), emits `relay_started` (R-12-041) and installs the process-wide log
/// subscriber the first time it runs.
pub fn build() -> (Router, Router) {
    let config = config::Config::from_env();
    logging::init(config.log_json);
    logging::relay_started();
    let state = AppState {
        sessions: SessionMap::new(),
        metrics: Arc::new(Metrics::new()),
        limits: Arc::new(Limits {
            connections: IpRateLimiter::new(config.connection_rate_per_sec),
            handles: IpRateLimiter::new(config.handle_rate_per_sec),
        }),
        config,
    };
    let main_router = Router::new()
        .route("/host/{handle}", get(host_upgrade))
        .route("/device/{handle}", get(device_upgrade))
        .route("/healthz", get(healthz))
        .with_state(state.clone());
    let metrics_router = Router::new()
        .route("/metrics", get(metrics_endpoint))
        .with_state(state);
    (main_router, metrics_router)
}

/// Convenience for callers that only need the main rendezvous router (every
/// existing caller: `main.rs` pairs this with [`build`]'s second router on its own
/// listener, and every integration test under `tests/` only ever exercises
/// `/host`, `/device` and `/healthz`).
pub fn router() -> Router {
    build().0
}

async fn host_upgrade(
    Path(handle): Path<String>,
    headers: HeaderMap,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    State(state): State<AppState>,
    ws: WebSocketUpgrade,
) -> Response {
    let ip = client_ip(&headers, addr.ip(), &state.config.client_ip_header);
    accept(ws, &headers, state, ip, &handle, Role::Host)
}

async fn device_upgrade(
    Path(handle): Path<String>,
    headers: HeaderMap,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    State(state): State<AppState>,
    ws: WebSocketUpgrade,
) -> Response {
    let ip = client_ip(&headers, addr.ip(), &state.config.client_ip_header);
    accept(ws, &headers, state, ip, &handle, Role::Device)
}

/// Resolves the address for both per-IP limits (R-12-071).
fn client_ip(headers: &HeaderMap, peer: IpAddr, header_name: &str) -> IpAddr {
    headers
        .get(header_name)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.split(',').next())
        .and_then(|value| value.trim().parse().ok())
        .unwrap_or(peer)
}

/// Liveness probe: `200 ok`, no handle, session id, IP address or peer count
/// (R-12-010, R-12-023).
async fn healthz() -> &'static str {
    "ok"
}

/// `/metrics`: Prometheus text exposition (R-12-011, R-12-015, R-12-050). Served
/// only from the router [`build`] binds to `HERDR_RELAY_METRICS_LISTEN`, never
/// alongside the public rendezvous routes (R-12-024).
async fn metrics_endpoint(State(state): State<AppState>) -> impl IntoResponse {
    let body = state.metrics.render(state.sessions.active_handles());
    ([(header::CONTENT_TYPE, "text/plain; version=0.0.4")], body)
}

/// Accepts the upgrade, then validates the subprotocol, the handle format and the
/// registration slot before handing the joined connection to [`relay::run_peer`].
fn accept(
    ws: WebSocketUpgrade,
    headers: &HeaderMap,
    state: AppState,
    ip: IpAddr,
    raw_handle: &str,
    role: Role,
) -> Response {
    let protocol_ok = requests_subprotocol(headers);
    let handle = raw_handle.parse::<Handle>();
    let ws = if protocol_ok {
        ws.protocols([SUBPROTOCOL])
    } else {
        ws
    };
    ws.on_upgrade(move |socket| async move {
        connection::drive_connection(socket, state, ip, protocol_ok, handle, role).await;
    })
}

/// `true` when the client offered [`SUBPROTOCOL`] in `Sec-WebSocket-Protocol`
/// (R-12-020, R-11-013).
fn requests_subprotocol(headers: &HeaderMap) -> bool {
    headers
        .get_all(header::SEC_WEBSOCKET_PROTOCOL)
        .iter()
        .filter_map(|value| value.to_str().ok())
        .flat_map(|value| value.split(','))
        .any(|protocol| protocol.trim() == SUBPROTOCOL)
}

#[cfg(test)]
mod tests {
    #[test]
    fn trusted_client_ip_header() {
        let peer = "192.0.2.1".parse().unwrap();
        for (value, expected) in [
            (None, peer),
            (Some("198.51.100.2"), "198.51.100.2".parse().unwrap()),
            (
                Some(" 198.51.100.3 , 192.0.2.2"),
                "198.51.100.3".parse().unwrap(),
            ),
            (Some("garbage"), peer),
            (Some("garbage, 198.51.100.2"), peer),
            (Some("2001:db8::1"), "2001:db8::1".parse().unwrap()),
        ] {
            let mut headers = axum::http::HeaderMap::new();
            if let Some(value) = value {
                headers.insert("x-forwarded-for", HeaderValue::from_str(value).unwrap());
            }
            assert_eq!(
                super::client_ip(&headers, peer, "X-Forwarded-For"),
                expected
            );
            assert_eq!(super::client_ip(&headers, peer, ""), peer);
        }
    }

    use super::{healthz, requests_subprotocol};
    use axum::http::HeaderValue;

    /// `/healthz` returns `200 ok` (R-12-010).
    #[tokio::test]
    async fn healthz_returns_ok_body() {
        assert_eq!(healthz().await, "ok");
    }

    #[test]
    fn subprotocol_header_absent_is_rejected() {
        let headers = axum::http::HeaderMap::new();
        assert!(!requests_subprotocol(&headers));
    }

    #[test]
    fn subprotocol_header_present_is_accepted() {
        let mut headers = axum::http::HeaderMap::new();
        headers.insert(
            axum::http::header::SEC_WEBSOCKET_PROTOCOL,
            HeaderValue::from_static("herdr-relay.v1"),
        );
        assert!(requests_subprotocol(&headers));
    }

    #[test]
    fn subprotocol_header_with_other_offers_is_accepted() {
        let mut headers = axum::http::HeaderMap::new();
        headers.insert(
            axum::http::header::SEC_WEBSOCKET_PROTOCOL,
            HeaderValue::from_static("chat, herdr-relay.v1"),
        );
        assert!(requests_subprotocol(&headers));
    }

    #[test]
    fn wrong_subprotocol_is_rejected() {
        let mut headers = axum::http::HeaderMap::new();
        headers.insert(
            axum::http::header::SEC_WEBSOCKET_PROTOCOL,
            HeaderValue::from_static("chat"),
        );
        assert!(!requests_subprotocol(&headers));
    }
}
