//! Content-free push delivery, independent of a room's lifetime (R-12-072..076).

mod providers;

use std::collections::HashMap;
use std::fmt::Write;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, PoisonError};
use std::time::Duration;

use herdr_relay_proto::frame::RelayMessage;
use herdr_relay_proto::handle::Handle;
use herdr_relay_proto::messages::Platform;
use tokio::time::Instant;

use crate::session::{Role, SessionMap};
use providers::Providers;

const CAPACITY: usize = 4096;
const COLLAPSE: Duration = Duration::from_secs(30);

struct Entry {
    platform: &'static str,
    token: String,
    generation: u64,
    last_sent: Option<Instant>,
}

#[derive(Default)]
struct Store {
    entries: HashMap<Handle, Entry>,
    generation: u64,
}

impl Store {
    fn register(&mut self, handle: Handle, platform: &'static str, token: String) {
        let last_sent = self.entries.get(&handle).and_then(|entry| entry.last_sent);
        if self.entries.len() == CAPACITY && !self.entries.contains_key(&handle) {
            // ponytail: scan at most 4096 entries only on eviction; add an index if this becomes hot.
            if let Some(oldest) = self
                .entries
                .iter()
                .min_by_key(|(_, entry)| entry.generation)
                .map(|(&handle, _)| handle)
            {
                self.entries.remove(&oldest);
            }
        }
        self.generation += 1;
        self.entries.insert(
            handle,
            Entry {
                platform,
                token,
                generation: self.generation,
                last_sent,
            },
        );
    }

    fn take_wake(&mut self, handle: Handle, now: Instant) -> Option<(&'static str, String, u64)> {
        let entry = self.entries.get_mut(&handle)?;
        if entry
            .last_sent
            .is_some_and(|last| now.duration_since(last) < COLLAPSE)
        {
            return None;
        }
        entry.last_sent = Some(now);
        Some((entry.platform, entry.token.clone(), entry.generation))
    }

    fn remove_generation(&mut self, handle: Handle, generation: u64) {
        if self
            .entries
            .get(&handle)
            .is_some_and(|entry| entry.generation == generation)
        {
            self.entries.remove(&handle);
        }
    }
}

pub(crate) struct Push {
    providers: Providers,
    store: Mutex<Store>,
    sent: [AtomicU64; 2],
    failed: [AtomicU64; 2],
}

impl Push {
    pub(crate) fn from_env() -> Self {
        Self {
            providers: Providers::from_env(),
            store: Mutex::new(Store::default()),
            sent: Default::default(),
            failed: Default::default(),
        }
    }

    /// Returns an error for malformed frames or frames from the wrong role. Never forwards text.
    pub(crate) fn receive(
        self: &Arc<Self>,
        text: &str,
        handle: Handle,
        role: Role,
        sessions: &SessionMap,
    ) -> Result<(), ()> {
        let frame = parse(text, role)?;
        if !self.providers.enabled() {
            return Ok(());
        }
        match frame {
            RelayMessage::PushRegister { platform, token } => {
                let platform = match platform {
                    Platform::Ios => "ios",
                    Platform::Android => "android",
                };
                if self.providers.supports(platform) {
                    self.store
                        .lock()
                        .unwrap_or_else(PoisonError::into_inner)
                        .register(handle, platform, token);
                }
            }
            RelayMessage::PushUnregister => {
                self.store
                    .lock()
                    .unwrap_or_else(PoisonError::into_inner)
                    .entries
                    .remove(&handle);
            }
            RelayMessage::PushWake => {
                if sessions
                    .peer_of(handle, Role::Host)
                    .is_some_and(|tx| !tx.is_closed())
                {
                    return Ok(());
                }
                let delivery = self
                    .store
                    .lock()
                    .unwrap_or_else(PoisonError::into_inner)
                    .take_wake(handle, Instant::now());
                if let Some((platform, token, generation)) = delivery {
                    let push = Arc::clone(self);
                    tokio::spawn(async move {
                        let result = push.providers.send(platform, &token).await;
                        let counters = if result.is_ok() {
                            &push.sent
                        } else {
                            &push.failed
                        };
                        counters[usize::from(platform == "android")]
                            .fetch_add(1, Ordering::Relaxed);
                        if result == Err(true) {
                            push.store
                                .lock()
                                .unwrap_or_else(PoisonError::into_inner)
                                .remove_generation(handle, generation);
                        }
                    });
                }
            }
        }
        Ok(())
    }

    pub(crate) fn render_metrics(&self, out: &mut String) {
        for (name, counters) in [("sent", &self.sent), ("failed", &self.failed)] {
            let _ = writeln!(
                out,
                "# HELP herdr_relay_push_{name}_total Content-free push results"
            );
            let _ = writeln!(out, "# TYPE herdr_relay_push_{name}_total counter");
            for (i, platform) in ["ios", "android"].iter().enumerate() {
                let value = counters[i].load(Ordering::Relaxed);
                let _ = writeln!(
                    out,
                    "herdr_relay_push_{name}_total{{platform=\"{platform}\"}} {value}"
                );
            }
        }
    }
}

fn parse(text: &str, role: Role) -> Result<RelayMessage, ()> {
    let frame: RelayMessage = serde_json::from_str(text).map_err(|_| ())?;
    match &frame {
        RelayMessage::PushRegister { token, .. }
            if role == Role::Device && !token.is_empty() && token.len() <= 4096 =>
        {
            Ok(frame)
        }
        RelayMessage::PushUnregister if role == Role::Device => Ok(frame),
        RelayMessage::PushWake if role == Role::Host => Ok(frame),
        _ => Err(()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn handle(n: usize) -> Handle {
        format!("{n:021}A").parse().expect("test handle")
    }

    #[test]
    fn store_bounds_replaces_and_removes_without_deleting_new_registration() {
        let mut store = Store::default();
        for n in 0..CAPACITY {
            store.register(handle(n), "ios", "old".into());
        }
        let old_generation = store.entries[&handle(1)].generation;
        store.register(handle(1), "android", "new".into());
        store.register(handle(CAPACITY), "ios", "last".into());
        assert_eq!(store.entries.len(), CAPACITY);
        assert!(!store.entries.contains_key(&handle(0)));
        assert_eq!(store.entries[&handle(1)].platform, "android");
        assert_eq!(store.entries[&handle(1)].token, "new");
        store.remove_generation(handle(1), old_generation);
        assert!(store.entries.contains_key(&handle(1)));
        let generation = store.entries[&handle(1)].generation;
        store.remove_generation(handle(1), generation);
        assert!(!store.entries.contains_key(&handle(1)));
    }

    #[test]
    fn collapse_starts_at_dispatch_and_survives_token_refresh() {
        let mut store = Store::default();
        let now = Instant::now();
        store.register(handle(1), "ios", "first".into());
        assert!(store.take_wake(handle(1), now).is_some());
        store.register(handle(1), "ios", "second".into());
        assert!(
            store
                .take_wake(handle(1), now + COLLAPSE - Duration::from_millis(1))
                .is_none()
        );
        assert_eq!(
            store
                .take_wake(handle(1), now + COLLAPSE)
                .map(|(_, token, _)| token),
            Some("second".into())
        );
        assert!(store.take_wake(handle(2), now).is_none());
    }

    #[test]
    fn frames_enforce_roles_and_token_byte_limit() {
        assert!(
            parse(
                r#"{"type":"push_register","platform":"ios","token":"abc"}"#,
                Role::Device
            )
            .is_ok()
        );
        assert!(parse(r#"{"type":"push_unregister"}"#, Role::Device).is_ok());
        assert!(parse(r#"{"type":"push_wake"}"#, Role::Host).is_ok());
        for text in [
            r#"{"type":"push_register","platform":"other","token":"abc"}"#,
            r#"{"type":"push_register","platform":"ios","token":""}"#,
            r#"{"type":"push_wake"}"#,
            "not json",
        ] {
            assert!(parse(text, Role::Device).is_err());
        }
        assert!(parse(r#"{"type":"push_unregister"}"#, Role::Host).is_err());
        for (length, accepted) in [(4096, true), (4097, false)] {
            let text = serde_json::json!({"type":"push_register","platform":"android","token":"a".repeat(length)}).to_string();
            assert_eq!(parse(&text, Role::Device).is_ok(), accepted);
        }
    }
}
