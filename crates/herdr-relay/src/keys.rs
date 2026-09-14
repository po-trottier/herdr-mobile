//! The Host's own Curve25519 static keypair (R-13-035 step 1, R-13-058) and the
//! display fingerprint derived from a static public key (R-13-040).
//!
//! Generation uses `snow`'s own DH resolver so the key is produced in exactly
//! the format the Noise handshake (Phase 4's `noise.rs`) will later load with
//! [`snow::Builder::local_private_key`]. This module never performs a Noise
//! handshake itself; it only asks `snow` to mint and hold a static keypair.

use std::path::PathBuf;

use base64::Engine as _;
use base64::engine::general_purpose::STANDARD as BASE64;
use blake2::{Blake2s256, Digest};
use serde::{Deserialize, Serialize};
use snow::Builder;
use thiserror::Error;

use crate::config::{self, ConfigError, ConfigPaths};

/// The Noise pattern used only to reach `snow`'s Curve25519 DH resolver.
/// `docs/13-security-pairing.md` R-13-013 fixes the cipher suite
/// (`25519_ChaChaPoly_BLAKE2s`) for every pattern the Host uses; the handshake
/// pattern component (`XX` here) is irrelevant to key generation and is
/// overridden per-handshake by `noise.rs`.
const NOISE_PARAMS: &str = "Noise_XX_25519_ChaChaPoly_BLAKE2s";

const KEYRING_SERVICE: &str = "herdr-relay";
const KEYRING_USERNAME: &str = "host-keypair";

/// The Host's Curve25519 static keypair. Both halves are always 32 bytes
/// (R-13-058).
#[derive(Clone, PartialEq, Eq)]
pub struct HostKeypair {
    pub private: [u8; 32],
    pub public: [u8; 32],
}

impl std::fmt::Debug for HostKeypair {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // R-41-030/R-41-031: never format key material into a log line.
        f.debug_struct("HostKeypair")
            .field("public", &self.fingerprint())
            .finish_non_exhaustive()
    }
}

#[derive(Debug, Error)]
pub enum KeysError {
    #[error("generate the Host Curve25519 keypair failed: {0}")]
    Generate(#[source] snow::Error),
    #[error("the Host keypair fallback file at {path} is corrupt: wrong key length")]
    FallbackLength { path: PathBuf },
    #[error("the Host keypair fallback file at {path} is corrupt: {source}")]
    FallbackDecode {
        path: PathBuf,
        #[source]
        source: base64::DecodeError,
    },
    #[error("read the Host keypair fallback file at {path} failed: {source}")]
    FallbackRead {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("parse the Host keypair fallback file at {path} failed: {source}")]
    FallbackParse {
        path: PathBuf,
        #[source]
        source: serde_json::Error,
    },
    #[error("write the Host keypair fallback file failed: {0}")]
    FallbackWrite(#[source] ConfigError),
    #[error(
        "the Host keypair in the {KEYRING_SERVICE} credential store is corrupt: wrong key length"
    )]
    KeyringLength,
}

/// The keyring-fallback file format (R-13-059). Binary key halves are
/// base64-encoded, matching the encoding `herdr-relay-proto` already uses for
/// binary wire fields.
#[derive(Serialize, Deserialize)]
struct FallbackFile {
    private: String,
    public: String,
}

impl HostKeypair {
    fn generate() -> Result<Self, KeysError> {
        let params = NOISE_PARAMS
            .parse()
            .expect("NOISE_PARAMS is a valid Noise pattern string");
        let keypair = Builder::new(params)
            .generate_keypair()
            .map_err(KeysError::Generate)?;
        let mut private = [0u8; 32];
        let mut public = [0u8; 32];
        private.copy_from_slice(&keypair.private);
        public.copy_from_slice(&keypair.public);
        Ok(Self { private, public })
    }

    fn to_keyring_bytes(&self) -> Vec<u8> {
        let mut bytes = Vec::with_capacity(64);
        bytes.extend_from_slice(&self.private);
        bytes.extend_from_slice(&self.public);
        bytes
    }

    fn from_keyring_bytes(bytes: &[u8]) -> Result<Self, KeysError> {
        let (private, public) = split_64(bytes).ok_or(KeysError::KeyringLength)?;
        Ok(Self { private, public })
    }

    fn to_fallback_file(&self) -> FallbackFile {
        FallbackFile {
            private: BASE64.encode(self.private),
            public: BASE64.encode(self.public),
        }
    }

    fn from_fallback_file(path: &std::path::Path, file: FallbackFile) -> Result<Self, KeysError> {
        let private_bytes =
            BASE64
                .decode(file.private)
                .map_err(|source| KeysError::FallbackDecode {
                    path: path.to_path_buf(),
                    source,
                })?;
        let public_bytes =
            BASE64
                .decode(file.public)
                .map_err(|source| KeysError::FallbackDecode {
                    path: path.to_path_buf(),
                    source,
                })?;
        let private: [u8; 32] =
            private_bytes
                .try_into()
                .map_err(|_| KeysError::FallbackLength {
                    path: path.to_path_buf(),
                })?;
        let public: [u8; 32] = public_bytes
            .try_into()
            .map_err(|_| KeysError::FallbackLength {
                path: path.to_path_buf(),
            })?;
        Ok(Self { private, public })
    }

    /// `BLAKE2s-256(public_key)`, first 8 bytes, lowercase hex, four
    /// hyphen-separated groups of four (R-13-040, R-13-042).
    pub fn fingerprint(&self) -> String {
        fingerprint_of(&self.public)
    }
}

fn split_64(bytes: &[u8]) -> Option<([u8; 32], [u8; 32])> {
    if bytes.len() != 64 {
        return None;
    }
    let mut private = [0u8; 32];
    let mut public = [0u8; 32];
    private.copy_from_slice(&bytes[..32]);
    public.copy_from_slice(&bytes[32..]);
    Some((private, public))
}

/// `BLAKE2s-256(public_key)`, first 8 bytes, lowercase hex, four
/// hyphen-separated groups of four (R-13-040). A free function so the Host can
/// also fingerprint a Device's stored `static_public_key` (R-13-070) without
/// constructing a [`HostKeypair`].
pub fn fingerprint_of(public_key: &[u8; 32]) -> String {
    let digest = Blake2s256::digest(public_key);
    let head = &digest[..8];
    let hex: String = head.iter().map(|byte| format!("{byte:02x}")).collect();
    format!(
        "{}-{}-{}-{}",
        &hex[0..4],
        &hex[4..8],
        &hex[8..12],
        &hex[12..16]
    )
}

fn keyring_entry() -> Result<keyring::Entry, keyring::Error> {
    keyring::Entry::new(KEYRING_SERVICE, KEYRING_USERNAME)
}

fn fallback_read(paths: &ConfigPaths) -> Result<Option<HostKeypair>, KeysError> {
    let path = paths.keypair_fallback_file();
    match config::read_to_string_bounded(&path, config::FILE_READ_TIMEOUT) {
        Ok(text) => {
            let file: FallbackFile =
                serde_json::from_str(&text).map_err(|source| KeysError::FallbackParse {
                    path: path.clone(),
                    source,
                })?;
            HostKeypair::from_fallback_file(&path, file).map(Some)
        }
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(source) => Err(KeysError::FallbackRead { path, source }),
    }
}

fn fallback_write(paths: &ConfigPaths, keypair: &HostKeypair) -> Result<(), KeysError> {
    let path = paths.keypair_fallback_file();
    let json = serde_json::to_vec(&keypair.to_fallback_file())
        .expect("FallbackFile serialises: it holds only two base64 strings");
    config::write_restricted_file(&path, &json).map_err(KeysError::FallbackWrite)
}

/// Loads the Host keypair from the platform credential store (R-13-058),
/// generating and persisting one on first run (R-13-035 step 1). Falls back to
/// a permission-restricted file when the credential store itself is
/// unavailable (R-13-059), and uses that file alone for a `ConfigPaths` that
/// does not opt into the OS store (`ConfigPaths::new`: tests and throwaway
/// state directories).
pub fn load_or_generate(paths: &ConfigPaths) -> Result<HostKeypair, KeysError> {
    if !paths.uses_os_keyring() {
        return fallback_load_or_generate(paths);
    }
    let entry = match keyring_entry() {
        Ok(entry) => entry,
        // No credential-store backend resolved at all: go straight to the file
        // fallback (R-13-059).
        Err(_) => return fallback_load_or_generate(paths),
    };
    match entry.get_secret() {
        Ok(bytes) => HostKeypair::from_keyring_bytes(&bytes),
        Err(keyring::Error::NoEntry) => {
            let generated = HostKeypair::generate()?;
            match entry.set_secret(&generated.to_keyring_bytes()) {
                Ok(()) => Ok(generated),
                // The store rejected the write (e.g. it went unavailable
                // between resolving the entry and calling it): keep the
                // generated key, but persist it to the file fallback instead.
                Err(_) => {
                    fallback_write(paths, &generated)?;
                    Ok(generated)
                }
            }
        }
        // Any other error means the store is present but unusable: fall back.
        Err(_) => fallback_load_or_generate(paths),
    }
}

fn fallback_load_or_generate(paths: &ConfigPaths) -> Result<HostKeypair, KeysError> {
    if let Some(keypair) = fallback_read(paths)? {
        return Ok(keypair);
    }
    let generated = HostKeypair::generate()?;
    fallback_write(paths, &generated)?;
    Ok(generated)
}

/// Forces a brand-new Host keypair and overwrites whatever storage currently
/// holds one, keyring or file (R-13-056 step 4, the "Refresh" action). A
/// `ConfigPaths` that does not opt into the OS store rotates its file only.
pub fn rotate(paths: &ConfigPaths) -> Result<HostKeypair, KeysError> {
    let generated = HostKeypair::generate()?;
    let stored_in_keyring = paths.uses_os_keyring()
        && keyring_entry()
            .map(|entry| entry.set_secret(&generated.to_keyring_bytes()).is_ok())
            .unwrap_or(false);
    if stored_in_keyring {
        return Ok(generated);
    }
    fallback_write(paths, &generated)?;
    Ok(generated)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_paths(label: &str) -> ConfigPaths {
        let dir = std::env::temp_dir().join(format!(
            "herdr-relay-keys-test-{label}-{}",
            std::process::id()
        ));
        std::fs::remove_dir_all(&dir).ok();
        ConfigPaths::new(dir)
    }

    #[test]
    fn generate_produces_distinct_keypairs() {
        let a = HostKeypair::generate().expect("generate a keypair");
        let b = HostKeypair::generate().expect("generate a second keypair");
        assert_ne!(a.private, b.private);
        assert_ne!(a.public, b.public);
    }

    #[test]
    fn fingerprint_matches_the_documented_shape() {
        let keypair = HostKeypair::generate().expect("generate a keypair");
        let fingerprint = keypair.fingerprint();
        // R-13-040: four hyphen-separated groups of four lowercase hex digits.
        let groups: Vec<&str> = fingerprint.split('-').collect();
        assert_eq!(groups.len(), 4);
        for group in groups {
            assert_eq!(group.len(), 4);
            assert!(
                group
                    .chars()
                    .all(|c| c.is_ascii_hexdigit() && !c.is_ascii_uppercase())
            );
        }
    }

    #[test]
    fn fallback_round_trips_through_the_file() {
        let paths = temp_paths("fallback-round-trip");
        let generated = HostKeypair::generate().expect("generate a keypair");
        fallback_write(&paths, &generated).expect("write the fallback file");
        let loaded = fallback_read(&paths)
            .expect("read the fallback file")
            .expect("a file was written");
        assert_eq!(loaded.private, generated.private);
        assert_eq!(loaded.public, generated.public);
        std::fs::remove_dir_all(paths.dir()).ok();
    }

    /// The OS credential-store entry as it is right now, or `None` when
    /// there is none (or no backend). Read-only: this test never writes it.
    fn os_entry_bytes() -> Option<Vec<u8>> {
        keyring_entry()
            .ok()
            .and_then(|entry| entry.get_secret().ok())
    }

    /// `ConfigPaths::new` (every test and throwaway directory) keeps a
    /// rotation inside its own fallback file: the one machine-wide credential
    /// store entry, the live Host's key, is byte-for-byte untouched.
    #[test]
    fn rotate_without_the_os_keyring_changes_only_the_fallback_file() {
        let paths = temp_paths("rotate-file-only");
        assert!(!paths.uses_os_keyring());
        paths
            .ensure_dir()
            .expect("create the test config directory");
        let os_before = os_entry_bytes();

        let first = load_or_generate(&paths).expect("generate the first keypair");
        let file_before = std::fs::read(paths.keypair_fallback_file())
            .expect("load_or_generate wrote the fallback file");
        let rotated = rotate(&paths).expect("rotate the keypair");
        let file_after =
            std::fs::read(paths.keypair_fallback_file()).expect("rotate wrote the fallback file");

        assert_ne!(rotated.public, first.public, "rotate mints a new key");
        assert_ne!(file_before, file_after, "the fallback file changed");
        assert_eq!(
            load_or_generate(&paths)
                .expect("reload the rotated keypair")
                .public,
            rotated.public,
            "the file holds the rotated key"
        );
        assert_eq!(
            os_entry_bytes(),
            os_before,
            "the OS credential-store entry is untouched"
        );
        std::fs::remove_dir_all(paths.dir()).ok();
    }
}
