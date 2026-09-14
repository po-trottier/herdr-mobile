//! One pane's coalescing window, poll timer, input-triggered reads and
//! read-rate cap (R-10-029/030/031/070/071). Callers supply each `Instant`, so
//! scheduler tests use a deterministic clock without sleeping.

use std::collections::VecDeque;
use std::time::{Duration, Instant};

#[derive(Debug)]
pub(super) struct PaneScheduler {
    window: Duration,
    poll: Duration,
    /// R-10-071: offsets from a forwarded `send_input`, ascending.
    input_offsets: Vec<Duration>,
    max_per_sec: u32,
    pending_due: Option<Instant>,
    window_open_until: Option<Instant>,
    next_poll: Instant,
    /// R-10-071: the armed input-read deadlines, ascending. A new `send_input`
    /// replaces them all, so the sequence restarts from the newest write.
    input_due: Vec<Instant>,
    read_history: VecDeque<Instant>,
}

pub(super) enum FireOutcome {
    /// Issue the read now: the revision moved (R-10-029).
    Read,
    /// Issue the read now: the R-10-070 poll period elapsed, or an R-10-071
    /// input-read deadline came due. The caller MUST hash-compare the text
    /// against the last sent frame and send nothing when they match.
    PollRead,
    /// The R-10-030 cap is full; a revision trigger is re-armed to retry once a
    /// slot frees, keeping only this newest pending revision (R-10-031). A poll
    /// or input trigger is simply skipped: its own next deadline already stands.
    RateLimited,
}

impl PaneScheduler {
    pub(super) fn new(
        window: Duration,
        poll: Duration,
        mut input_offsets: Vec<Duration>,
        max_per_sec: u32,
        now: Instant,
    ) -> Self {
        input_offsets.sort_unstable();
        Self {
            window,
            poll,
            input_offsets,
            max_per_sec,
            pending_due: None,
            window_open_until: None,
            next_poll: now + poll,
            input_due: Vec::new(),
            read_history: VecDeque::new(),
        }
    }

    /// R-10-071: call after a `send_input` for this pane reached Herdr. Arms one
    /// read per configured offset, timed from the write. A later `send_input`
    /// replaces the whole sequence rather than adding to it.
    pub(super) fn on_input_sent(&mut self, now: Instant) {
        self.input_due.clear();
        self.input_due
            .extend(self.input_offsets.iter().map(|offset| now + *offset));
    }

    /// Call after the R-10-032 revision gate passes. The first event is due now
    /// (R-10-029). Later events wait until the open window closes. The caller
    /// stores the newest revision; these events do not extend the window (R-10-031).
    pub(super) fn on_revision_changed(&mut self, now: Instant) {
        if self.pending_due.is_none() {
            self.pending_due = Some(self.window_open_until.map_or(now, |until| until.max(now)));
        }
    }

    /// The next `Instant` the caller's run loop should wake for. While a pane is
    /// watched this is always `Some`: the R-10-070 poll deadline is armed from
    /// construction, so the loop wakes for it even when no event ever arrives
    /// (R-02-026: an agent pane can repaint without its `revision` ever moving).
    /// An armed R-10-071 input read is earlier than the poll, so it is included
    /// here; without it the loop would sleep through the keystroke echo.
    pub(super) fn next_deadline(&self) -> Option<Instant> {
        let mut due = self.next_poll;
        if let Some(pending) = self.pending_due {
            due = due.min(pending);
        }
        if let Some(&input) = self.input_due.first() {
            due = due.min(input);
        }
        Some(due)
    }

    /// Issue a due read, or return `None` when no timer is due. A due revision
    /// trigger, a due poll trigger and a due input read produce one read. Each
    /// revision-triggered read opens the next R-10-029 window. The poll keeps its
    /// independent period.
    pub(super) fn fire(&mut self, now: Instant) -> Option<FireOutcome> {
        let revision_due = self.pending_due.is_some_and(|due| now >= due);
        let poll_due = now >= self.next_poll;
        let input_due = self.input_due.first().is_some_and(|&due| now >= due);
        if !revision_due && !poll_due && !input_due {
            return None;
        }
        if poll_due {
            // Re-arm before the cap check so a skipped poll never shifts the
            // schedule, and a read never counts against the *next* period.
            self.next_poll = now + self.poll;
        }
        if input_due {
            // R-10-071: consume every deadline this read serves, before the cap
            // check, so a capped input read never shifts the rest of the
            // sequence. The remaining offsets stay timed from the write.
            self.input_due.retain(|&due| due > now);
        }
        while matches!(self.read_history.front(), Some(&t) if now.duration_since(t) >= Duration::from_secs(1))
        {
            self.read_history.pop_front();
        }
        if self.read_history.len() as u32 >= self.max_per_sec {
            if revision_due {
                let retry_at =
                    self.read_history.front().copied().unwrap_or(now) + Duration::from_secs(1);
                self.pending_due = Some(retry_at);
            }
            return Some(FireOutcome::RateLimited);
        }
        if revision_due {
            // R-10-029/031: clear the consumed trigger. The window alone cannot
            // issue a trailing read; another qualifying event must arm it.
            self.pending_due = None;
            self.window_open_until = Some(now + self.window);
        }
        self.read_history.push_back(now);
        Some(if revision_due {
            FireOutcome::Read
        } else {
            FireOutcome::PollRead
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const WINDOW: Duration = Duration::from_millis(120);
    const POLL: Duration = Duration::from_millis(250);
    /// Far enough out that the R-10-070 poll never fires inside a test, so every
    /// `PollRead` an input test observes is an R-10-071 input read.
    const NO_POLL: Duration = Duration::from_millis(60_000);

    fn ms(value: u64) -> Duration {
        Duration::from_millis(value)
    }

    /// The R-10-029/030/070 tests arm no input read, so they pass no offset.
    fn event_scheduler(now: Instant) -> PaneScheduler {
        PaneScheduler::new(WINDOW, POLL, Vec::new(), 8, now)
    }

    /// The R-10-071 tests use the three documented offsets and the R-10-030
    /// default cap of 16.
    fn input_scheduler(now: Instant) -> PaneScheduler {
        PaneScheduler::new(WINDOW, NO_POLL, vec![ms(60), ms(130), ms(250)], 16, now)
    }

    #[test]
    fn scheduler_arms_only_the_poll_timer_until_a_revision_changes() {
        let t0 = Instant::now();
        let scheduler = event_scheduler(t0);
        // R-10-070: the poll deadline exists before the first event.
        assert_eq!(
            scheduler.next_deadline(),
            Some(t0 + Duration::from_millis(250))
        );
    }

    #[test]
    fn scheduler_poll_fires_without_any_revision_event() {
        let t0 = Instant::now();
        let mut scheduler = event_scheduler(t0);
        assert!(scheduler.fire(t0 + Duration::from_millis(249)).is_none());
        assert!(matches!(
            scheduler.fire(t0 + Duration::from_millis(250)),
            Some(FireOutcome::PollRead)
        ));
        assert_eq!(
            scheduler.next_deadline(),
            Some(t0 + Duration::from_millis(500))
        );
    }

    #[test]
    fn scheduler_reads_first_event_immediately_without_trailing_read() {
        let t0 = Instant::now();
        let mut scheduler = event_scheduler(t0);
        scheduler.on_revision_changed(t0);
        assert_eq!(scheduler.next_deadline(), Some(t0));
        assert!(matches!(scheduler.fire(t0), Some(FireOutcome::Read)));
        assert!(scheduler.fire(t0).is_none());
        assert!(scheduler.fire(t0 + Duration::from_millis(120)).is_none());
        assert_eq!(
            scheduler.next_deadline(),
            Some(t0 + Duration::from_millis(250))
        );
    }

    #[test]
    fn scheduler_coalesces_events_inside_the_window() {
        let t0 = Instant::now();
        let mut scheduler = event_scheduler(t0);
        scheduler.on_revision_changed(t0);
        assert!(matches!(scheduler.fire(t0), Some(FireOutcome::Read)));
        scheduler.on_revision_changed(t0 + Duration::from_millis(40));
        assert_eq!(
            scheduler.next_deadline(),
            Some(t0 + Duration::from_millis(120))
        );
        scheduler.on_revision_changed(t0 + Duration::from_millis(80));
        assert_eq!(
            scheduler.next_deadline(),
            Some(t0 + Duration::from_millis(120)),
            "R-10-031: another event does not extend the window"
        );
        assert!(scheduler.fire(t0 + Duration::from_millis(119)).is_none());
        assert!(matches!(
            scheduler.fire(t0 + Duration::from_millis(120)),
            Some(FireOutcome::Read)
        ));
        assert!(scheduler.fire(t0 + Duration::from_millis(120)).is_none());
        assert!(scheduler.fire(t0 + Duration::from_millis(240)).is_none());
    }

    #[test]
    fn scheduler_poll_fires_independently_inside_an_open_window() {
        let t0 = Instant::now();
        let mut scheduler = event_scheduler(t0);
        let event_at = t0 + Duration::from_millis(200);
        scheduler.on_revision_changed(event_at);
        assert!(matches!(scheduler.fire(event_at), Some(FireOutcome::Read)));
        scheduler.on_revision_changed(t0 + Duration::from_millis(240));
        assert!(matches!(
            scheduler.fire(t0 + Duration::from_millis(250)),
            Some(FireOutcome::PollRead)
        ));
        // R-10-029/070: the poll neither delays nor extends the event window.
        assert_eq!(
            scheduler.next_deadline(),
            Some(t0 + Duration::from_millis(320))
        );
        assert!(scheduler.fire(t0 + Duration::from_millis(319)).is_none());
        assert!(matches!(
            scheduler.fire(t0 + Duration::from_millis(320)),
            Some(FireOutcome::Read)
        ));
        assert_eq!(
            scheduler.next_deadline(),
            Some(t0 + Duration::from_millis(500))
        );
    }

    #[test]
    fn scheduler_collapses_a_due_poll_and_a_due_event_into_one_read() {
        let t0 = Instant::now();
        let mut scheduler = event_scheduler(t0);
        let event_at = t0 + Duration::from_millis(130);
        scheduler.on_revision_changed(event_at);
        assert!(matches!(scheduler.fire(event_at), Some(FireOutcome::Read)));
        scheduler.on_revision_changed(t0 + Duration::from_millis(170));
        let both_due = t0 + Duration::from_millis(250);
        assert!(matches!(scheduler.fire(both_due), Some(FireOutcome::Read)));
        assert!(scheduler.fire(both_due).is_none());
        assert_eq!(
            scheduler.next_deadline(),
            Some(t0 + Duration::from_millis(500))
        );
    }

    #[test]
    fn scheduler_rate_caps_at_the_configured_ceiling_across_both_triggers() {
        let t0 = Instant::now();
        let mut scheduler = event_scheduler(t0);
        // R-10-030/070: six event reads and two poll reads fill the shared cap.
        for (offset, event) in [
            (0, true),
            (120, true),
            (240, true),
            (250, false),
            (360, true),
            (480, true),
            (500, false),
            (600, true),
        ] {
            let now = t0 + Duration::from_millis(offset);
            if event {
                scheduler.on_revision_changed(now);
                assert!(matches!(scheduler.fire(now), Some(FireOutcome::Read)));
            } else {
                assert!(matches!(scheduler.fire(now), Some(FireOutcome::PollRead)));
            }
        }
        let excess_at = t0 + Duration::from_millis(720);
        scheduler.on_revision_changed(excess_at);
        assert!(matches!(
            scheduler.fire(excess_at),
            Some(FireOutcome::RateLimited)
        ));
        assert!(matches!(
            scheduler.fire(t0 + Duration::from_millis(750)),
            Some(FireOutcome::RateLimited)
        ));
        scheduler.on_revision_changed(t0 + Duration::from_millis(800));
        assert_eq!(scheduler.next_deadline(), Some(t0 + Duration::from_secs(1)));
        assert!(scheduler.fire(t0 + Duration::from_millis(999)).is_none());
        // R-10-030/031: retry only the newest pending revision when a slot frees.
        let retry_at = t0 + Duration::from_secs(1);
        assert!(matches!(scheduler.fire(retry_at), Some(FireOutcome::Read)));
        assert!(scheduler.fire(retry_at).is_none());
    }

    #[test]
    fn scheduler_reads_three_times_after_one_input() {
        let t0 = Instant::now();
        let mut scheduler = input_scheduler(t0);
        scheduler.on_input_sent(t0);
        // R-10-071: the run loop must wake for the first offset, not the poll.
        assert_eq!(scheduler.next_deadline(), Some(t0 + ms(60)));
        assert!(scheduler.fire(t0 + ms(59)).is_none());
        for offset in [60, 130, 250] {
            assert!(
                matches!(scheduler.fire(t0 + ms(offset)), Some(FireOutcome::PollRead)),
                "R-10-071: an input read is due at {offset} ms after the write"
            );
            assert!(scheduler.fire(t0 + ms(offset)).is_none());
        }
        // The sequence is spent; only the poll remains armed.
        assert_eq!(scheduler.next_deadline(), Some(t0 + NO_POLL));
    }

    #[test]
    fn scheduler_restarts_the_input_sequence_on_the_next_input() {
        let t0 = Instant::now();
        let mut scheduler = input_scheduler(t0);
        scheduler.on_input_sent(t0);
        scheduler.on_input_sent(t0 + ms(40));
        // R-10-071: the second write replaces the first sequence.
        assert_eq!(scheduler.next_deadline(), Some(t0 + ms(100)));
        assert!(scheduler.fire(t0 + ms(60)).is_none());
        for offset in [100, 170, 290] {
            assert!(
                matches!(scheduler.fire(t0 + ms(offset)), Some(FireOutcome::PollRead)),
                "R-10-071: the restarted read is due at {offset} ms"
            );
        }
        assert_eq!(scheduler.next_deadline(), Some(t0 + NO_POLL));
    }

    #[test]
    fn scheduler_input_reads_count_against_the_rate_cap() {
        let t0 = Instant::now();
        // A cap of 2 makes the shared R-10-030 ceiling observable in one sequence.
        let mut scheduler =
            PaneScheduler::new(WINDOW, NO_POLL, vec![ms(60), ms(130), ms(250)], 2, t0);
        scheduler.on_input_sent(t0);
        assert!(matches!(
            scheduler.fire(t0 + ms(60)),
            Some(FireOutcome::PollRead)
        ));
        assert!(matches!(
            scheduler.fire(t0 + ms(130)),
            Some(FireOutcome::PollRead)
        ));
        // R-10-030: the third read exceeds the cap. An input read is dropped, not
        // deferred: its deadline has passed and the echo it wanted is now stale.
        assert!(matches!(
            scheduler.fire(t0 + ms(250)),
            Some(FireOutcome::RateLimited)
        ));
        assert!(scheduler.fire(t0 + ms(250)).is_none());
    }

    #[test]
    fn scheduler_bounds_events_and_inputs_together_at_sixteen_reads_per_second() {
        let t0 = Instant::now();
        let mut scheduler = input_scheduler(t0);
        let mut reads = 0;
        for step in 0..1000u64 {
            let now = t0 + ms(step);
            if step % 200 == 0 {
                scheduler.on_input_sent(now);
            }
            if step % 30 == 0 {
                scheduler.on_revision_changed(now);
            }
            if matches!(
                scheduler.fire(now),
                Some(FireOutcome::Read | FireOutcome::PollRead)
            ) {
                reads += 1;
            }
        }
        // R-10-030: 33 events and 5 writes in one second, still at most 16 reads.
        assert!(reads <= 16, "R-10-030: {reads} reads in one second");
        assert!(reads >= 8, "the cap must not stop the reads altogether");
    }
}
