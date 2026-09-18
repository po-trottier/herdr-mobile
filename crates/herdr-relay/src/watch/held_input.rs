//! Session-owned submit requests that wait for an agent to stop work.

use herdr_relay_proto::messages::{Defer, Message, SendInput, SendInputAck};

use super::bridge::{Bridge, WatchError};
use super::herdr_calls::HerdrCalls;
use super::input::validate_send_input;

pub(super) struct PendingInput {
    pane_id: String,
    keys: Vec<String>,
    corr: Option<String>,
}

impl<H: HerdrCalls> Bridge<H> {
    /// Handles a deferred request and returns its correlated replies.
    pub fn handle_deferred_input(
        &mut self,
        mut request: SendInput,
        corr: Option<String>,
    ) -> Vec<(Message, Option<String>)> {
        let pane_id = request.pane_id.clone();
        let result = (|| match request.defer.take() {
            Some(Defer::Cancel) => {
                if request.line.is_some() || request.text.is_some() || request.keys.is_some() {
                    return Err(WatchError::InvalidInput(
                        "cancel cannot include line, text, or keys".to_owned(),
                    ));
                }
                if self
                    .pending_input
                    .as_ref()
                    .is_some_and(|p| p.pane_id == request.pane_id)
                {
                    self.cancel_pending_inputs();
                }
                Ok(input_ack(request.pane_id, true, false))
            }
            Some(Defer::UntilIdle) => {
                self.require_watched(&request.pane_id)?;
                if request.line.is_some()
                    || request.text.is_some()
                    || !request.keys.as_ref().is_some_and(|keys| {
                        keys.iter().any(|key| key.eq_ignore_ascii_case("Enter"))
                    })
                {
                    return Err(WatchError::InvalidInput(
                        "until_idle requires keys containing Enter and no line or text".to_owned(),
                    ));
                }
                validate_send_input(&request)?;
                let snapshot = match self.fetch_snapshot() {
                    Ok(snapshot) => snapshot,
                    Err(_) => return Ok(input_ack(request.pane_id, false, false)),
                };
                let working = snapshot.agents.iter().any(|agent| {
                    agent.pane_id == request.pane_id && agent.agent_status == "working"
                });
                self.cancel_pending_inputs();
                if working {
                    self.pending_input = Some(PendingInput {
                        pane_id: request.pane_id.clone(),
                        keys: request.keys.take().unwrap_or_default(),
                        corr: corr.clone(),
                    });
                    Ok(input_ack(request.pane_id, true, true))
                } else {
                    self.send_input(request)
                }
            }
            None => self.send_input(request),
        })();
        self.input_replies.push((
            result.unwrap_or_else(|_: WatchError| input_ack(pane_id, false, false)),
            corr,
        ));
        self.take_input_replies()
    }

    /// Drains final replies from status events and watch lifecycle changes.
    pub fn take_input_replies(&mut self) -> Vec<(Message, Option<String>)> {
        std::mem::take(&mut self.input_replies)
    }

    /// Cancels the session's held submit without sending terminal input.
    pub fn cancel_pending_inputs(&mut self) {
        if let Some(pending) = self.pending_input.take() {
            self.input_replies
                .push((input_ack(pending.pane_id, false, false), pending.corr));
        }
    }

    pub(super) fn release_pending_input(&mut self, pane_id: &str) {
        if self
            .session_active
            .as_ref()
            .is_some_and(|active| !active.load(std::sync::atomic::Ordering::Acquire))
        {
            self.cancel_pending_inputs();
            return;
        }
        if !self
            .pending_input
            .as_ref()
            .is_some_and(|p| p.pane_id == pane_id)
        {
            return;
        }
        if let Some(pending) = self.pending_input.take() {
            let request = SendInput {
                pane_id: pending.pane_id.clone(),
                line: None,
                text: None,
                keys: Some(pending.keys),
                defer: None,
            };
            let reply = self
                .send_input(request)
                .unwrap_or_else(|_| input_ack(pending.pane_id, false, false));
            self.input_replies.push((reply, pending.corr));
        }
    }
}

fn input_ack(pane_id: String, accepted: bool, queued: bool) -> Message {
    Message::SendInputAck(SendInputAck {
        pane_id,
        accepted,
        queued,
    })
}
