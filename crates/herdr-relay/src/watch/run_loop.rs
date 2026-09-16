//! Resynchronising after a dropped connection (R-10-035, R-11-200), and the main
//! run loop that multiplexes Herdr subscription pushes with the coalescing window
//! and delivers outbound messages.

use std::io;
use std::sync::mpsc::{Receiver, RecvTimeoutError};
use std::time::Instant;

use herdr_relay_proto::messages::{Message, PaneFrame, TreeEvent, TreeUpdate};

use crate::ipc::IpcError;

use super::bridge::{Bridge, WatchError, frame_hash};
use super::events::SubscriptionAction;
use super::herdr_calls::HerdrCalls;
use super::latest_slot::LatestSlot;
use super::scheduler::FireOutcome;

impl<H: HerdrCalls> Bridge<H> {
    /// R-10-035, R-11-200: after the subscription reconnects (or a Device
    /// reconnects), re-fetch `session.snapshot`, compare the watched pane's
    /// revision against the stored one, read and send a fresh frame only if it
    /// moved, and report the pane closed — stopping the watch — if it is gone
    /// (§5.5 steps 3-6, R-11-071).
    pub fn resynchronize(&mut self) -> Result<Vec<Message>, WatchError> {
        let Some(watched) = self.watched.clone() else {
            return Ok(Vec::new());
        };
        let raw = self.fetch_snapshot()?;
        let Some(pane) = raw.panes.iter().find(|p| p.pane_id == watched.pane_id) else {
            self.watched = None;
            self.scheduler = None;
            return Ok(vec![Message::TreeUpdate(Box::new(TreeUpdate {
                event: TreeEvent::PaneClosed,
                pane: None,
                workspace: None,
                tab: None,
            }))]);
        };

        if pane.revision == watched.last_revision {
            return Ok(Vec::new()); // already correct, send nothing (§5.5 step 5)
        }

        let width = if pane.scroll.viewport_rows != watched.viewport_rows {
            self.fetch_width(&watched.pane_id)?
        } else {
            watched.width
        };
        let text = self.fetch_visible_text(&watched.pane_id)?;

        if let Some(w) = &mut self.watched {
            w.last_revision = pane.revision;
            w.viewport_rows = pane.scroll.viewport_rows;
            w.width = width;
            w.last_frame_hash = frame_hash(&text, pane.scroll.viewport_rows, width);
        }

        Ok(vec![Message::PaneFrame(PaneFrame {
            pane_id: watched.pane_id,
            revision: pane.revision,
            viewport_rows: pane.scroll.viewport_rows,
            width,
            text,
        })])
    }

    /// The next `Instant` the run loop should wake for, driven by the pending
    /// coalescing/rate-cap deadline or the R-10-070 poll deadline, if any.
    fn next_deadline(&self) -> Option<Instant> {
        self.scheduler.as_ref().and_then(|s| s.next_deadline())
    }

    /// Called after an event or a timer wake. Issues the due `pane.read` and returns the
    /// frame to send, or `None` when the cap deferred it (a later call, at the
    /// new deadline, tries again), when there is nothing pending, when a poll
    /// read found the pane unchanged (R-10-070), or when the read itself
    /// failed.
    ///
    /// R-10-034: a read that fails or does not answer is simply not sent as a
    /// frame; the stored revision is untouched by this failure path (it was
    /// already updated at event time), so the next event naturally retries.
    /// This is deliberately infallible: a single Herdr call failure here MUST
    /// NOT end the whole run loop. Measured live: a burst of short-lived
    /// connections can transiently exhaust Windows named-pipe instances
    /// ("All pipe instances are busy", os error 231) even after `ipc.rs`'s own
    /// one-retry (R-10-015) — a real, self-healing condition, not a fatal one.
    fn poll_scheduler(&mut self, now: Instant) -> Option<PaneFrame> {
        let scheduler = self.scheduler.as_mut()?;
        let outcome = scheduler.fire(now)?;
        let is_poll = match outcome {
            FireOutcome::RateLimited => return None,
            FireOutcome::Read => false,
            FireOutcome::PollRead => true,
        };
        let watched = self.watched.clone()?;
        // R-10-029/034: this synchronous read holds `&mut self` until completion
        // or timeout. The loop cannot issue another read during that call.
        let text = self.fetch_visible_text(&watched.pane_id).ok()?;
        let hash = frame_hash(&text, watched.viewport_rows, watched.width);
        if is_poll && hash == watched.last_frame_hash {
            // R-10-070: a poll read whose text and geometry match the last sent
            // frame is not sent; an unchanged pane costs no wire bytes. A
            // revision-triggered read always sends (R-11-073), even when the
            // text happens to be identical.
            return None;
        }
        if let Some(w) = &mut self.watched {
            w.last_frame_hash = hash;
        }
        Some(PaneFrame {
            pane_id: watched.pane_id,
            revision: watched.last_revision,
            viewport_rows: watched.viewport_rows,
            width: watched.width,
            text,
        })
    }

    /// Drives the watch loop until `deadline`, reading Herdr subscription pushes
    /// from `rx` (fed by a background thread via
    /// `SubscriptionConnection::spawn_reader`) and invoking `emit_frame`/
    /// `emit_other` for every outbound message the loop produces. This is the same
    /// loop `relay.rs`'s Device connection handler drives in production; a manual
    /// live-Herdr run drives it directly with no Device attached, to observe the
    /// same frames a Device would receive (`pane_frame` uses the backpressure-safe
    /// [`LatestSlot`] per R-11-070; every other message uses reliable delivery).
    pub fn run_until(
        &mut self,
        rx: &Receiver<io::Result<String>>,
        deadline: Instant,
        frame_slot: &LatestSlot<PaneFrame>,
        mut emit_other: impl FnMut(Message),
        mut on_resubscribe_needed: impl FnMut(),
    ) -> Result<(), WatchError> {
        loop {
            let now = Instant::now();
            if now >= deadline {
                // A late entry still serves a read that came due; otherwise the frame
                // waits for the next tick (R-10-029).
                if let Some(frame) = self.poll_scheduler(now) {
                    frame_slot.put(frame);
                }
                return Ok(());
            }
            let wait = self
                .next_deadline()
                .map(|due| due.saturating_duration_since(now))
                .unwrap_or(std::time::Duration::from_millis(200))
                .min(deadline.saturating_duration_since(now));

            match rx.recv_timeout(wait) {
                Ok(Ok(line)) => {
                    let (messages, action) = self.handle_subscription_line(&line)?;
                    for message in messages {
                        emit_other(message);
                    }
                    if action == SubscriptionAction::Resubscribe {
                        on_resubscribe_needed();
                    }
                }
                Ok(Err(err)) => return Err(WatchError::Herdr(IpcError::Io(err))),
                Err(RecvTimeoutError::Timeout) => {}
                Err(RecvTimeoutError::Disconnected) => return Err(WatchError::SubscriptionClosed),
            }
            // R-10-029/070: serve the leading read before the next event.
            // Continued subscription traffic must not prevent timer reads.
            if let Some(frame) = self.poll_scheduler(Instant::now()) {
                frame_slot.put(frame);
            }
        }
    }
}
