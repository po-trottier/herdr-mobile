//! Content-free APNs and FCM delivery. Credentials and provider responses never enter logs.

use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use jsonwebtoken::{Algorithm, EncodingKey, Header, encode};
use reqwest::{Client, StatusCode};
use serde::Deserialize;
use serde_json::{Value, json};
use tokio::sync::Mutex;

const OAUTH_URL: &str = "https://oauth2.googleapis.com/token";
const TITLE: &str = "Herdr Remote";
const BODY: &str = "An agent needs you.";

pub(crate) struct Providers {
    client: Option<Client>,
    apns: Option<Apns>,
    fcm: Option<Fcm>,
}

struct CachedToken {
    value: String,
    expires: Instant,
}

struct Apns {
    key: EncodingKey,
    key_id: String,
    team_id: String,
    bundle_id: String,
    endpoint: &'static str,
    token: Mutex<Option<CachedToken>>,
}

struct Fcm {
    key: EncodingKey,
    email: String,
    endpoint: String,
    token: Mutex<Option<CachedToken>>,
}

#[derive(Deserialize)]
struct ServiceAccount {
    project_id: String,
    client_email: String,
    private_key: String,
}

#[derive(Deserialize)]
struct AccessToken {
    access_token: String,
    expires_in: u64,
}

impl Providers {
    pub(crate) fn from_env() -> Self {
        let _ = rustls::crypto::ring::default_provider().install_default();
        let apns = config_result(Apns::from_env());
        let fcm = config_result(Fcm::from_env());
        let client = if apns.is_some() || fcm.is_some() {
            match Client::builder()
                .connect_timeout(Duration::from_secs(5))
                .timeout(Duration::from_secs(10))
                .redirect(reqwest::redirect::Policy::none())
                .build()
            {
                Ok(client) => Some(client),
                Err(_) => {
                    config_error();
                    None
                }
            }
        } else {
            None
        };
        let providers = Self { client, apns, fcm };
        if !providers.enabled() {
            tracing::info!(event = "push_disabled", error_message = "push: disabled");
        }
        providers
    }

    pub(crate) fn enabled(&self) -> bool {
        self.client.is_some() && (self.apns.is_some() || self.fcm.is_some())
    }

    pub(crate) fn supports(&self, platform: &str) -> bool {
        self.client.is_some()
            && match platform {
                "ios" => self.apns.is_some(),
                "android" => self.fcm.is_some(),
                _ => false,
            }
    }

    /// `Err(true)` means the device token is permanently invalid.
    pub(crate) async fn send(&self, platform: &str, token: &str) -> Result<(), bool> {
        tokio::time::timeout(Duration::from_secs(25), async {
            let client = self.client.as_ref().ok_or(false)?;
            match platform {
                "ios" => self.apns.as_ref().ok_or(false)?.send(client, token).await,
                "android" => self.fcm.as_ref().ok_or(false)?.send(client, token).await,
                _ => Err(false),
            }
        })
        .await
        .map_err(|_| false)?
    }
}

async fn response_json<T: serde::de::DeserializeOwned>(
    mut response: reqwest::Response,
) -> Result<T, bool> {
    const LIMIT: usize = 64 * 1024;
    let mut bytes = Vec::new();
    while let Some(chunk) = response.chunk().await.map_err(|_| false)? {
        if chunk.len() > LIMIT - bytes.len() {
            return Err(false);
        }
        bytes.extend_from_slice(&chunk);
    }
    serde_json::from_slice(&bytes).map_err(|_| false)
}

fn config_error() {
    tracing::error!(
        event = "error",
        error_code = "push_config",
        error_message = "push: invalid configuration"
    );
}

fn config_result<T>(result: Result<Option<T>, ()>) -> Option<T> {
    result.unwrap_or_else(|()| {
        config_error();
        None
    })
}

fn env(name: &str) -> Result<Option<String>, ()> {
    match std::env::var(name) {
        Ok(value) if value.trim().is_empty() => Ok(None),
        Ok(value) => Ok(Some(value)),
        Err(std::env::VarError::NotPresent) => Ok(None),
        Err(_) => Err(()),
    }
}

fn now() -> Result<u64, bool> {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .map_err(|_| false)
}

impl Apns {
    fn from_env() -> Result<Option<Self>, ()> {
        let Some(path) = env("HERDR_RELAY_APNS_KEY_FILE")? else {
            return Ok(None);
        };
        let Some(key_id) = env("HERDR_RELAY_APNS_KEY_ID")? else {
            return Ok(None);
        };
        let Some(team_id) = env("HERDR_RELAY_APNS_TEAM_ID")? else {
            return Ok(None);
        };
        let Some(bundle_id) = env("HERDR_RELAY_APNS_BUNDLE_ID")? else {
            return Ok(None);
        };
        let endpoint = match env("HERDR_RELAY_APNS_SANDBOX")?.as_deref() {
            Some("true" | "1") => "https://api.sandbox.push.apple.com",
            None | Some("false" | "0") => "https://api.push.apple.com",
            _ => return Err(()),
        };
        let key =
            EncodingKey::from_ec_pem(&std::fs::read(path).map_err(|_| ())?).map_err(|_| ())?;
        Ok(Some(Self {
            key,
            key_id,
            team_id,
            bundle_id,
            endpoint,
            token: Mutex::new(None),
        }))
    }

    async fn bearer(&self) -> Result<String, bool> {
        let mut cached = self.token.lock().await;
        if let Some(token) = cached
            .as_ref()
            .filter(|token| token.expires > Instant::now())
        {
            return Ok(token.value.clone());
        }
        let mut header = Header::new(Algorithm::ES256);
        header.kid = Some(self.key_id.clone());
        let value = encode(
            &header,
            &json!({"iss": self.team_id, "iat": now()?}),
            &self.key,
        )
        .map_err(|_| false)?;
        *cached = Some(CachedToken {
            value: value.clone(),
            expires: Instant::now() + Duration::from_secs(50 * 60),
        });
        Ok(value)
    }

    async fn send(&self, client: &Client, token: &str) -> Result<(), bool> {
        // APNs tokens are hexadecimal. Reject path syntax before URL construction.
        if token.is_empty() || !token.bytes().all(|byte| byte.is_ascii_hexdigit()) {
            return Err(true);
        }
        let response = client
            .post(format!("{}/3/device/{token}", self.endpoint))
            .version(reqwest::Version::HTTP_2)
            .bearer_auth(self.bearer().await?)
            .header("apns-topic", &self.bundle_id)
            .header("apns-push-type", "alert")
            .header("apns-priority", "10")
            .header("apns-collapse-id", "herdr-agent")
            .json(&apns_payload())
            .send()
            .await
            .map_err(|_| false)?;
        let status = response.status();
        if status.is_success() {
            return Ok(());
        }
        if status == StatusCode::GONE {
            return Err(true);
        }
        let body = response_json::<Value>(response).await?;
        Err(body.get("reason").and_then(Value::as_str) == Some("BadDeviceToken"))
    }
}

impl Fcm {
    fn from_env() -> Result<Option<Self>, ()> {
        let Some(path) = env("HERDR_RELAY_FCM_SERVICE_ACCOUNT_FILE")? else {
            return Ok(None);
        };
        let account: ServiceAccount =
            serde_json::from_slice(&std::fs::read(path).map_err(|_| ())?).map_err(|_| ())?;
        if account.project_id.is_empty()
            || !account
                .project_id
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-')
            || account.client_email.trim().is_empty()
        {
            return Err(());
        }
        let key = EncodingKey::from_rsa_pem(account.private_key.as_bytes()).map_err(|_| ())?;
        Ok(Some(Self {
            key,
            email: account.client_email,
            endpoint: format!(
                "https://fcm.googleapis.com/v1/projects/{}/messages:send",
                account.project_id
            ),
            token: Mutex::new(None),
        }))
    }

    async fn bearer(&self, client: &Client) -> Result<String, bool> {
        let mut cached = self.token.lock().await;
        if let Some(token) = cached
            .as_ref()
            .filter(|token| token.expires > Instant::now())
        {
            return Ok(token.value.clone());
        }
        let issued = now()?;
        let assertion = encode(
            &Header::new(Algorithm::RS256),
            &json!({
                "iss": self.email,
                "scope": "https://www.googleapis.com/auth/firebase.messaging",
                "aud": OAUTH_URL,
                "iat": issued,
                "exp": issued + 3600
            }),
            &self.key,
        )
        .map_err(|_| false)?;
        let started = Instant::now();
        let response = client
            .post(OAUTH_URL)
            .form(&[
                ("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer"),
                ("assertion", assertion.as_str()),
            ])
            .send()
            .await
            .map_err(|_| false)?
            .error_for_status()
            .map_err(|_| false)?;
        let token: AccessToken = response_json(response).await?;
        if token.access_token.is_empty() {
            return Err(false);
        }
        let expires = started
            .checked_add(Duration::from_secs(token.expires_in.saturating_sub(60)))
            .ok_or(false)?;
        *cached = Some(CachedToken {
            value: token.access_token.clone(),
            expires,
        });
        Ok(token.access_token)
    }

    async fn send(&self, client: &Client, token: &str) -> Result<(), bool> {
        let response = client
            .post(&self.endpoint)
            .bearer_auth(self.bearer(client).await?)
            .json(&fcm_payload(token))
            .send()
            .await
            .map_err(|_| false)?;
        if response.status().is_success() {
            return Ok(());
        }
        let body = response_json::<Value>(response).await?;
        Err(fcm_invalid_token(&body))
    }
}

fn apns_payload() -> Value {
    json!({"aps": {
        "alert": {"title": TITLE, "body": BODY},
        "sound": "default",
        "thread-id": "herdr-agent"
    }})
}

fn fcm_payload(token: &str) -> Value {
    json!({"message": {
        "token": token,
        "notification": {"title": TITLE, "body": BODY},
        "android": {"notification": {
            "channel_id": "herdr_agent_status", "tag": "herdr-agent"
        }}
    }})
}

fn fcm_invalid_token(body: &Value) -> bool {
    body.pointer("/error/details")
        .and_then(Value::as_array)
        .is_some_and(|details| {
            details.iter().any(|detail| {
                detail["@type"] == "type.googleapis.com/google.firebase.fcm.v1.FcmError"
                    && detail["errorCode"] == "UNREGISTERED"
            })
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn payloads_contain_only_fixed_alert_and_destination() {
        assert_eq!(
            apns_payload(),
            json!({"aps": {
                "alert": {"title": "Herdr Remote", "body": "An agent needs you."},
                "sound": "default", "thread-id": "herdr-agent"
            }})
        );
        assert_eq!(
            fcm_payload("destination"),
            json!({"message": {
                "token": "destination",
                "notification": {"title": "Herdr Remote", "body": "An agent needs you."},
                "android": {"notification": {
                    "channel_id": "herdr_agent_status", "tag": "herdr-agent"
                }}
            }})
        );
        assert!(fcm_invalid_token(&json!({"error": {"details": [{
            "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
            "errorCode": "UNREGISTERED"
        }]}})));
        assert!(!fcm_invalid_token(
            &json!({"error": {"status": "INVALID_ARGUMENT"}})
        ));
    }
}
