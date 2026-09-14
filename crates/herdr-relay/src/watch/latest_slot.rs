//! A single-slot backpressure mailbox for the watched pane's outbound frames.

use std::sync::{Condvar, Mutex, PoisonError};

/// A single-slot mailbox holding only the newest value pushed to it (R-11-070,
/// R-10-018: every `pane_frame` is a full repaint, so an older one has no value
/// once a newer one exists). Bounded at one item; the overflow policy is
/// "replace", never "block" or "grow" (R-41-130) — this is how a slow Device loses
/// only stale frames, never falls permanently behind or exhausts memory.
pub struct LatestSlot<T> {
    state: Mutex<Option<T>>,
    ready: Condvar,
}

impl<T> Default for LatestSlot<T> {
    fn default() -> Self {
        Self::new()
    }
}

impl<T> LatestSlot<T> {
    pub fn new() -> Self {
        Self {
            state: Mutex::new(None),
            ready: Condvar::new(),
        }
    }

    /// Overwrites any unread value with `value` (R-11-070).
    pub fn put(&self, value: T) {
        let mut guard = self.state.lock().unwrap_or_else(PoisonError::into_inner);
        *guard = Some(value);
        self.ready.notify_one();
    }

    /// Takes a value if one is ready, without blocking.
    pub fn try_take(&self) -> Option<T> {
        self.state
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .take()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Proves the single-slot overflow policy is "replace", never "block" or
    /// "grow": a second `put` before a `try_take` drops the stale value and
    /// keeps only the newest (R-11-070, R-41-130).
    #[test]
    fn latest_slot_keeps_only_the_newest_value() {
        let slot: LatestSlot<u32> = LatestSlot::new();
        slot.put(1);
        slot.put(2);
        assert_eq!(slot.try_take(), Some(2));
        assert_eq!(slot.try_take(), None);
    }
}
