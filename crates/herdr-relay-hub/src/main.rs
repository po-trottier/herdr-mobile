//! `herdr-relay-hub`: the relay service binary entry point.
//!
//! Binds `HERDR_RELAY_LISTEN`, default `0.0.0.0:8080`, for the main `/host`,
//! `/device` and `/healthz` router, and `HERDR_RELAY_METRICS_LISTEN`, default
//! `127.0.0.1:9090`, for the separated `/metrics` router (R-12-024). Both routers
//! share one `AppState` from `herdr_relay_hub::routes::build()`. The main listener
//! carries `ConnectInfo<SocketAddr>` for the per-IP connection-rate limiter
//! (R-12-031). Terminates no TLS in process; the reverse proxy does that
//! (R-14-014, R-12-001).

#[tokio::main]
async fn main() -> std::io::Result<()> {
    let addr = std::env::var("HERDR_RELAY_LISTEN").unwrap_or_else(|_| "0.0.0.0:8080".to_owned());
    let metrics_addr =
        std::env::var("HERDR_RELAY_METRICS_LISTEN").unwrap_or_else(|_| "127.0.0.1:9090".to_owned());
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    let metrics_listener = tokio::net::TcpListener::bind(&metrics_addr).await?;
    let (app, metrics_app) = herdr_relay_hub::routes::build();
    let main_server = axum::serve(
        listener,
        app.into_make_service_with_connect_info::<std::net::SocketAddr>(),
    );
    let metrics_server = axum::serve(metrics_listener, metrics_app);
    tokio::try_join!(main_server, metrics_server)?;
    Ok(())
}
