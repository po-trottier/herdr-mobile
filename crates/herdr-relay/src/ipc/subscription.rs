//! The one long-lived Herdr event-subscription connection (R-10-011, R-41-160).

use std::io::{self, BufReader};
use std::sync::mpsc::{self, Receiver};

use super::transport::{PlatformStream, read_bounded_line};

/// The one long-lived Herdr event-subscription connection (R-10-011, R-41-160).
/// Never send a request on it (R-02-006, R-41-161) — there is deliberately no
/// method here that writes anything after `HerdrClient::subscribe` sent
/// `events.subscribe`.
pub struct SubscriptionConnection {
    reader: BufReader<PlatformStream>,
    max_response_bytes: u64,
}

impl SubscriptionConnection {
    /// Wraps an already-handshaken connection: `events.subscribe` was already
    /// sent and its `subscription_started` acknowledgement already read.
    /// Constructed only by `HerdrClient::subscribe`.
    pub(super) fn new(reader: BufReader<PlatformStream>, max_response_bytes: u64) -> Self {
        Self {
            reader,
            max_response_bytes,
        }
    }

    /// Reads one push line, blocking with no timeout. Returns `Ok(None)` when Herdr
    /// half-closed the connection (a restart, for example), which the caller
    /// reconnects to per R-10-014.
    pub fn read_line(&mut self) -> io::Result<Option<String>> {
        let mut line = String::new();
        let read = read_bounded_line(&mut self.reader, self.max_response_bytes, &mut line)?;
        if read == 0 {
            return Ok(None);
        }
        Ok(Some(line))
    }

    /// Moves this connection onto a dedicated reader thread and returns the channel
    /// it forwards lines on, so the caller's main loop can multiplex it with a
    /// debounce timer through `Receiver::recv_timeout` — the exact pattern
    /// `src/bin/spike-subscribe.rs` proved live (R-01-005).
    pub fn spawn_reader(mut self) -> Receiver<io::Result<String>> {
        let (tx, rx) = mpsc::channel();
        std::thread::spawn(move || {
            loop {
                match self.read_line() {
                    Ok(Some(line)) => {
                        if tx.send(Ok(line)).is_err() {
                            return; // the main loop stopped listening
                        }
                    }
                    Ok(None) => return, // server half-closed
                    Err(err) => {
                        let _ = tx.send(Err(err));
                        return;
                    }
                }
            }
        });
        rx
    }
}
