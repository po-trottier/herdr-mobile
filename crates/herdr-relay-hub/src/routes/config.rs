//! Environment-configured limits and switches (`docs/14-relay-deployment.md` R-14-014).
//!
//! Read fresh on every [`super::build`] call rather than cached in a process-wide
//! static, so a test can set an environment variable and get a freshly configured
//! relay instance without fighting a lazily-initialized global (R-41-038: no silent
//! substitute for an unset value, just the stated default).

/// The five Phase 8 environment variables this crate reads itself. `HERDR_RELAY_LISTEN`
/// and `HERDR_RELAY_METRICS_LISTEN` are bind addresses `main.rs` reads directly, since
/// only `main.rs` binds a `TcpListener` (R-14-014).
#[derive(Debug, Clone, Copy)]
pub(crate) struct Config {
    /// `HERDR_RELAY_MAX_HANDLES`, default `4096` (R-12-034).
    pub(crate) max_handles: usize,
    /// `HERDR_RELAY_CONNECTION_RATE`, default `10` (R-12-031).
    pub(crate) connection_rate_per_sec: usize,
    /// `HERDR_RELAY_FRAME_RATE`, default `100` (R-12-032).
    pub(crate) frame_rate_per_sec: usize,
    /// `HERDR_RELAY_HANDLE_RATE`, default `5` (R-12-033).
    pub(crate) handle_rate_per_sec: usize,
    /// `HERDR_RELAY_LOG_JSON`, default `true` (R-14-014, R-12-040).
    pub(crate) log_json: bool,
}

impl Config {
    /// Reads every variable from the process environment, falling back to the
    /// `docs/14-relay-deployment.md` R-14-014 default for anything unset or
    /// unparsable (R-41-038: a bad value is never silently repaired into something
    /// else — it is simply not a value, so the stated default applies).
    pub(crate) fn from_env() -> Self {
        Self {
            max_handles: env_usize("HERDR_RELAY_MAX_HANDLES", 4096),
            connection_rate_per_sec: env_usize("HERDR_RELAY_CONNECTION_RATE", 10),
            frame_rate_per_sec: env_usize("HERDR_RELAY_FRAME_RATE", 100),
            handle_rate_per_sec: env_usize("HERDR_RELAY_HANDLE_RATE", 5),
            log_json: env_bool("HERDR_RELAY_LOG_JSON", true),
        }
    }
}

fn env_usize(name: &str, default: usize) -> usize {
    std::env::var(name)
        .ok()
        .and_then(|value| value.parse().ok())
        .unwrap_or(default)
}

fn env_bool(name: &str, default: bool) -> bool {
    std::env::var(name)
        .ok()
        .and_then(|value| value.parse().ok())
        .unwrap_or(default)
}

#[cfg(test)]
mod tests {
    use super::Config;

    /// Confirms every default value documented for `Config::from_env` in
    /// `docs/14-relay-deployment.md` (R-14-014) when no environment variable
    /// is set.
    #[test]
    fn defaults_match_r_14_014_when_unset() {
        // ponytail: reads only variables this test does not set, so it is safe next
        // to the other tests in this binary that do set them (each test file is its
        // own process; this file never sets an env var itself).
        let config = Config::from_env();
        assert_eq!(config.max_handles, 4096);
        assert_eq!(config.connection_rate_per_sec, 10);
        assert_eq!(config.frame_rate_per_sec, 100);
        assert_eq!(config.handle_rate_per_sec, 5);
        assert!(config.log_json);
    }
}
