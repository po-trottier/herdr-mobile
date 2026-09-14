//! Phase 7: maps a bridge/Herdr error to a wire `error` frame — shared by
//! `input.rs` and `plugin_actions.rs` (R-11-091, R-11-090). Split into its own
//! file per `docs/90-implementation-plan.md` Phase 7's own file-size guidance.

use herdr_relay_proto::codes::ErrorCode;
use herdr_relay_proto::messages::ErrorMessage;

use crate::ipc::IpcError;

use super::bridge::WatchError;
use super::devices::DeviceError;

/// R-11-091, R-11-090: maps any error from a `send_input`/`host_action`/
/// `action_list_request`/`revoke_device`/`device_list_request` handler to an
/// `error` frame. Always `fatal: false` — the Herdr connection is
/// one-request-per-connection (R-02-004), so a rejected call loses only that
/// connection, never the Noise session.
pub fn map_watch_error(err: &WatchError) -> ErrorMessage {
    let (code, message) = match err {
        WatchError::NotWatching(pane_id) => (
            ErrorCode::NotWatching,
            format!("pane {pane_id} is not watched"),
        ),
        WatchError::InvalidInput(reason) => (ErrorCode::InvalidRequest, reason.clone()),
        // R-11-240: agent.focus reports a missing agent as a missing pane.
        WatchError::Herdr(IpcError::Rejected {
            method,
            code,
            message,
        }) if method == "agent.focus" && code == "agent_not_found" => {
            (ErrorCode::PaneNotFound, message.clone())
        }
        WatchError::Herdr(IpcError::Rejected { code, message, .. }) => {
            (herdr_error_code(code), message.clone())
        }
        WatchError::Device(DeviceError::InvalidRevokeRequest) => {
            (ErrorCode::InvalidRequest, err.to_string())
        }
        other => (ErrorCode::InternalError, other.to_string()),
    };
    ErrorMessage {
        code,
        message,
        fatal: false,
    }
}

fn herdr_error_code(code: &str) -> ErrorCode {
    match code {
        "invalid_request" => ErrorCode::InvalidRequest,
        "invalid_key" => ErrorCode::InvalidKey,
        "pane_not_found" => ErrorCode::PaneNotFound,
        "agent_not_found" => ErrorCode::AgentNotFound,
        "timeout" => ErrorCode::Timeout,
        "agent_prompt_stalled" => ErrorCode::AgentPromptStalled,
        "plugin_disabled" => ErrorCode::PluginDisabled, // R-11-218
        "action_unknown" => ErrorCode::ActionUnknown,   // R-11-219
        _ => ErrorCode::InternalError,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// R-11-218, R-11-219, R-11-091: both map to their named code, and neither is fatal —
    /// this is the "never fatal to the Noise session" guarantee in checkable form.
    #[test]
    fn plugin_disabled_and_action_unknown_map_and_stay_non_fatal() {
        let disabled = WatchError::Herdr(IpcError::Rejected {
            method: "plugin.action.invoke".to_string(),
            code: "plugin_disabled".to_string(),
            message: "plugin is disabled".to_string(),
        });
        let mapped = map_watch_error(&disabled);
        assert_eq!(mapped.code, ErrorCode::PluginDisabled);
        assert!(!mapped.fatal);

        let unknown = WatchError::Herdr(IpcError::Rejected {
            method: "plugin.action.invoke".to_string(),
            code: "action_unknown".to_string(),
            message: "no such action".to_string(),
        });
        let mapped = map_watch_error(&unknown);
        assert_eq!(mapped.code, ErrorCode::ActionUnknown);
        assert!(!mapped.fatal);
    }

    /// R-11-091: local rejections (not-watching, invalid input) also stay non-fatal —
    /// the Herdr validation error MUST NOT close the Noise session guarantee holds for
    /// these too.
    #[test]
    fn not_watching_and_invalid_input_are_non_fatal_local_rejections() {
        let mapped = map_watch_error(&WatchError::NotWatching("w1:p9".to_string()));
        assert_eq!(mapped.code, ErrorCode::NotWatching);
        assert!(!mapped.fatal);

        let mapped = map_watch_error(&WatchError::InvalidInput("bad input".to_string()));
        assert_eq!(mapped.code, ErrorCode::InvalidRequest);
        assert!(!mapped.fatal);
    }
}
