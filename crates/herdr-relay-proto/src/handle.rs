//! The routing-handle codec (128 random bits, 22 unpadded base64url characters) and
//! the `herdr-remote://pair` pairing URI builder/parser.
//!
//! Owning rules: `docs/11-relay-protocol.md` R-11-112 (handle generation source,
//! encoding, alphabet, exact length), R-11-140/R-11-141 (the pairing URI form and
//! 512-byte limit), §9.2 (the field table), §9.5 (the parsing/validation error
//! codes), `docs/13-security-pairing.md` R-13-032 (the handle's security properties),
//! and `docs/03-product-decisions.md` R-03-013 (the `herdr-remote` scheme).
//!
//! Scope note: the `relay_origin_insecure` code in §9.5 depends on the
//! local-development host allow list that `docs/22-platform-integration.md` R-22-040
//! owns. That policy is app-side (Dart); this shared codec validates only that the
//! origin is a well-formed absolute `http`/`https` origin with no path, query or
//! fragment.

use std::fmt;
use std::str::FromStr;

use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
#[cfg(feature = "generate")]
use rand::TryRng;
#[cfg(feature = "generate")]
use rand::rngs::SysRng;

/// The routing handle's raw size: 128 bits (R-11-112).
pub const HANDLE_BYTES: usize = 16;
/// The routing handle's encoded length: 22 unpadded base64url characters (R-11-112).
pub const HANDLE_LEN: usize = 22;
/// The pairing URI scheme (R-03-013).
pub const PAIRING_URI_SCHEME: &str = "herdr-remote";
/// The pairing URI's maximum total length in bytes (R-11-141).
pub const PAIRING_URI_MAX_LEN: usize = 512;

/// An opaque 128-bit routing handle. Carries no structure, no checksum and no
/// embedded time (R-13-032); it is used for relay routing only, never as a bearer
/// token (R-13-033).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct Handle([u8; HANDLE_BYTES]);

/// An error generating or decoding a [`Handle`].
#[derive(Debug, thiserror::Error)]
pub enum HandleError {
    /// The system random source failed while generating a handle. Only compiled with
    /// the `generate` feature (R-41-133: `herdr-relay-hub` never enables it).
    #[cfg(feature = "generate")]
    #[error("routing handle generation failed: {0}")]
    Generate(#[source] rand::rngs::SysError),
    /// The candidate is not exactly [`HANDLE_LEN`] characters.
    #[error("routing handle is not {HANDLE_LEN} unpadded base64url characters")]
    WrongLength,
    /// The candidate is not valid base64url.
    #[error("routing handle contains invalid base64url characters: {0}")]
    Decode(#[source] base64::DecodeError),
}

impl Handle {
    /// Generates a new handle from a cryptographic random source (R-11-112). Only
    /// compiled with the `generate` feature.
    ///
    /// # Errors
    ///
    /// Returns [`HandleError::Generate`] if the system random source fails.
    #[cfg(feature = "generate")]
    pub fn generate() -> Result<Self, HandleError> {
        let mut bytes = [0u8; HANDLE_BYTES];
        SysRng
            .try_fill_bytes(&mut bytes)
            .map_err(HandleError::Generate)?;
        Ok(Self(bytes))
    }

    /// Encodes this handle as 22 unpadded base64url characters (R-11-112).
    #[must_use]
    pub fn encode(&self) -> String {
        URL_SAFE_NO_PAD.encode(self.0)
    }
}

impl fmt::Display for Handle {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.encode())
    }
}

impl FromStr for Handle {
    type Err = HandleError;

    fn from_str(candidate: &str) -> Result<Self, HandleError> {
        if candidate.len() != HANDLE_LEN {
            return Err(HandleError::WrongLength);
        }
        let decoded = URL_SAFE_NO_PAD
            .decode(candidate)
            .map_err(HandleError::Decode)?;
        let bytes: [u8; HANDLE_BYTES] = decoded.try_into().map_err(|_| HandleError::WrongLength)?;
        Ok(Self(bytes))
    }
}

/// A parsed `herdr-remote://pair` pairing URI (R-11-140).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PairingUri {
    /// Canonical relay origin: scheme, host, optional port, no path, query or
    /// fragment.
    pub relay_origin: String,
    pub handle: Handle,
    /// The canonical hyphenated phrase text, unvalidated by this type; validate with
    /// [`crate::phrase::Phrase::parse_canonical`].
    pub phrase: String,
}

/// A pairing URI parsing or validation failure (`docs/11-relay-protocol.md` §9.5).
#[derive(Debug, thiserror::Error)]
pub enum PairingUriError {
    #[error("pairing URI scheme is not {PAIRING_URI_SCHEME}")]
    Scheme,
    #[error("pairing URI path is not pair")]
    Path,
    #[error("pairing URI version field v is absent or is not 1")]
    Version,
    #[error("pairing URI is missing a required field")]
    FieldMissing,
    #[error("pairing URI field appears more than once")]
    FieldRepeated,
    #[error("pairing URI exceeds {PAIRING_URI_MAX_LEN} bytes")]
    TooLong,
    #[error("relay origin r is not an absolute http(s) origin with no path, query or fragment")]
    RelayOriginInvalid,
    #[error("routing handle h is malformed: {0}")]
    HandleMalformed(#[from] HandleError),
}

impl PairingUriError {
    /// The wire validation code this error maps to (§9.5).
    #[must_use]
    pub const fn code(&self) -> &'static str {
        match self {
            Self::Scheme => "pair_uri_scheme",
            Self::Path => "pair_uri_path",
            Self::Version => "pair_uri_version",
            Self::FieldMissing => "pair_uri_field_missing",
            Self::FieldRepeated => "pair_uri_field_repeated",
            Self::TooLong => "pair_uri_too_long",
            Self::RelayOriginInvalid => "relay_origin_invalid",
            Self::HandleMalformed(_) => "handle_malformed",
        }
    }
}

impl PairingUri {
    /// Builds the pairing URI, emitting fields in the order `v`, `r`, `h`, `p`
    /// (R-11-140).
    #[must_use]
    pub fn build(&self) -> String {
        format!(
            "{PAIRING_URI_SCHEME}://pair?v=1&r={}&h={}&p={}",
            percent_encode(&self.relay_origin),
            self.handle.encode(),
            self.phrase
        )
    }

    /// Parses and validates a pairing URI. Accepts fields in any order (R-11-140).
    ///
    /// # Errors
    ///
    /// Returns the specific [`PairingUriError`] variant naming the first structural
    /// failure found.
    pub fn parse(uri: &str) -> Result<Self, PairingUriError> {
        if uri.len() > PAIRING_URI_MAX_LEN {
            return Err(PairingUriError::TooLong);
        }
        let rest = uri
            .strip_prefix(PAIRING_URI_SCHEME)
            .and_then(|rest| rest.strip_prefix("://"))
            .ok_or(PairingUriError::Scheme)?;
        let (path, query) = rest.split_once('?').ok_or(PairingUriError::FieldMissing)?;
        if path != "pair" {
            return Err(PairingUriError::Path);
        }
        let fields = parse_query(query)?;
        if fields.version.as_deref() != Some("1") {
            return Err(PairingUriError::Version);
        }
        let relay_origin = fields.relay_origin.ok_or(PairingUriError::FieldMissing)?;
        let handle_text = fields.handle.ok_or(PairingUriError::FieldMissing)?;
        let phrase = fields.phrase.ok_or(PairingUriError::FieldMissing)?;
        if !is_absolute_http_origin(&relay_origin) {
            return Err(PairingUriError::RelayOriginInvalid);
        }
        let handle: Handle = handle_text.parse()?;
        Ok(Self {
            relay_origin,
            handle,
            phrase,
        })
    }
}

#[derive(Default)]
struct QueryFields {
    version: Option<String>,
    relay_origin: Option<String>,
    handle: Option<String>,
    phrase: Option<String>,
}

fn parse_query(query: &str) -> Result<QueryFields, PairingUriError> {
    let mut fields = QueryFields::default();
    for pair in query.split('&') {
        let (key, value) = pair.split_once('=').ok_or(PairingUriError::FieldMissing)?;
        let slot = match key {
            "v" => &mut fields.version,
            "r" => &mut fields.relay_origin,
            "h" => &mut fields.handle,
            "p" => &mut fields.phrase,
            _ => continue,
        };
        if slot.is_some() {
            return Err(PairingUriError::FieldRepeated);
        }
        *slot = Some(if key == "r" {
            percent_decode(value)
        } else {
            value.to_owned()
        });
    }
    Ok(fields)
}

/// The one Host-side validator for `relay_origin` (the `R-22-037` shape: an
/// absolute `http://` or `https://` origin with a host, an optional port, and no
/// path, query, fragment or userinfo). The Host MUST call this on load and MUST
/// refuse a value that fails it, so a WebSocket URL such as `ws://host:port`
/// never reaches the pairing URI. Reused by `bridge.rs` and `popup.rs`
/// (`herdr-relay`); do not write a second validator.
pub fn is_absolute_http_origin(origin: &str) -> bool {
    let Some((scheme, rest)) = origin.split_once("://") else {
        return false;
    };
    (scheme == "http" || scheme == "https")
        && !rest.is_empty()
        && !rest.contains(['/', '?', '#', '@'])
}

/// Percent-encodes every byte outside the RFC 3986 unreserved set. The field table
/// names only `:` and `/`, but a full unreserved-set encoder is no more code and
/// covers every relay origin, not just the documented example.
fn percent_encode(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for byte in input.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' => {
                out.push(byte as char);
            }
            _ => out.push_str(&format!("%{byte:02X}")),
        }
    }
    out
}

fn percent_decode(input: &str) -> String {
    let bytes = input.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%'
            && i + 3 <= bytes.len()
            && let Ok(value) = u8::from_str_radix(&input[i + 1..i + 3], 16)
        {
            out.push(value);
            i += 3;
            continue;
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

#[cfg(test)]
mod tests {
    use super::{Handle, HandleError, PairingUri, PairingUriError};

    #[cfg(feature = "generate")]
    #[test]
    fn generate_encode_decode_round_trip() {
        let handle = Handle::generate().expect("generation succeeds");
        let encoded = handle.encode();
        assert_eq!(encoded.len(), super::HANDLE_LEN);
        let decoded: Handle = encoded.parse().expect("a freshly encoded handle parses");
        assert_eq!(decoded, handle);
    }

    #[test]
    fn from_str_rejects_wrong_length() {
        let error = "tooshort".parse::<Handle>().expect_err("must reject");
        assert!(matches!(error, HandleError::WrongLength));
    }

    #[test]
    fn from_str_rejects_invalid_base64url() {
        // 22 characters, but '!' is outside the base64url alphabet.
        let error = "!!!!!!!!!!!!!!!!!!!!!!"
            .parse::<Handle>()
            .expect_err("must reject invalid alphabet");
        assert!(matches!(error, HandleError::Decode(_)));
    }

    #[test]
    fn pairing_uri_builds_the_documented_worked_example() {
        let handle: Handle = "n6Loxf94CfyIO6hOxlaHvA"
            .parse()
            .expect("valid example handle");
        let uri = PairingUri {
            relay_origin: "https://relay.example.com".to_owned(),
            handle,
            phrase: "remedy-tapestry-hubcap-oversleep-jailbird-kinetic".to_owned(),
        };
        assert_eq!(
            uri.build(),
            "herdr-remote://pair?v=1&r=https%3A%2F%2Frelay.example.com&h=n6Loxf94CfyIO6hOxlaHvA&p=remedy-tapestry-hubcap-oversleep-jailbird-kinetic"
        );
    }

    #[test]
    fn pairing_uri_round_trips_through_build_and_parse() {
        let handle: Handle = "n6Loxf94CfyIO6hOxlaHvA"
            .parse()
            .expect("valid example handle");
        let uri = PairingUri {
            relay_origin: "https://relay.example.com".to_owned(),
            handle,
            phrase: "remedy-tapestry-hubcap-oversleep-jailbird-kinetic".to_owned(),
        };
        let parsed = PairingUri::parse(&uri.build()).expect("a built URI always parses");
        assert_eq!(parsed, uri);
    }

    #[test]
    fn pairing_uri_parse_accepts_fields_in_any_order() {
        let uri = "herdr-remote://pair?h=n6Loxf94CfyIO6hOxlaHvA&p=remedy-tapestry-hubcap-oversleep-jailbird-kinetic&v=1&r=https%3A%2F%2Frelay.example.com";
        let parsed = PairingUri::parse(uri).expect("field order MUST NOT matter (R-11-140)");
        assert_eq!(parsed.relay_origin, "https://relay.example.com");
    }

    #[test]
    fn pairing_uri_parse_rejects_wrong_scheme() {
        let uri = "https://pair?v=1&r=https%3A%2F%2Frelay.example.com&h=n6Loxf94CfyIO6hOxlaHvA&p=x";
        let error = PairingUri::parse(uri).expect_err("must reject a non-herdr-remote scheme");
        assert!(matches!(error, PairingUriError::Scheme));
        assert_eq!(error.code(), "pair_uri_scheme");
    }

    #[test]
    fn pairing_uri_parse_rejects_a_repeated_field() {
        let uri = "herdr-remote://pair?v=1&v=1&r=https%3A%2F%2Frelay.example.com&h=n6Loxf94CfyIO6hOxlaHvA&p=x";
        let error = PairingUri::parse(uri).expect_err("must reject a repeated field");
        assert!(matches!(error, PairingUriError::FieldRepeated));
    }

    #[test]
    fn pairing_uri_parse_rejects_a_relative_origin() {
        let uri = "herdr-remote://pair?v=1&r=relay.example.com&h=n6Loxf94CfyIO6hOxlaHvA&p=x";
        let error = PairingUri::parse(uri).expect_err("must reject a schemeless origin");
        assert!(matches!(error, PairingUriError::RelayOriginInvalid));
    }

    #[test]
    fn is_absolute_http_origin_accepts_only_plain_http_origins() {
        // The `R-22-037` shape: scheme, host, optional port, nothing else.
        assert!(super::is_absolute_http_origin("http://10.112.107.71:8080"));
        assert!(super::is_absolute_http_origin("https://relay.example.com"));
        assert!(super::is_absolute_http_origin("http://localhost:8080"));
    }

    #[test]
    fn is_absolute_http_origin_rejects_websocket_urls_and_deviations() {
        assert!(!super::is_absolute_http_origin("ws://localhost:8080"));
        assert!(!super::is_absolute_http_origin("wss://x"));
        assert!(!super::is_absolute_http_origin("http://host/path"));
        assert!(!super::is_absolute_http_origin("http://user@host"));
        assert!(!super::is_absolute_http_origin("http://host?x"));
    }
}
