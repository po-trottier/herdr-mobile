/// The `error` application message's `code` field
/// (`docs/11-relay-protocol.md` §7.1). Mirrors [`ErrorCode`] in
/// `crates/herdr-relay-proto/src/codes.rs:108-155`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
library;

/// A peer-to-peer error code carried inside the Noise session, distinct from
/// the relay-to-peer WebSocket close codes. [wireValue] is the exact JSON
/// string, mirroring `#[serde(rename_all = "snake_case")]` on
/// `crates/herdr-relay-proto/src/codes.rs:111-112`.
enum ErrorCode {
  /// Relay protocol version mismatch. Raised by both peers. Fatal.
  protocolMismatch('protocol_mismatch'),

  /// Herdr socket protocol is not `22`. Raised by Host. Fatal.
  herdrProtocolMismatch('herdr_protocol_mismatch'),

  /// Unknown message `type`. Raised by both peers. Not fatal.
  unknownMessage('unknown_message'),

  /// Frame exceeds 1 MiB. Raised by both peers. Not fatal.
  frameTooLarge('frame_too_large'),

  /// Pane does not exist. Raised by the Host. Not fatal.
  paneNotFound('pane_not_found'),

  /// Agent does not exist. Raised by the Host. Not fatal.
  agentNotFound('agent_not_found'),

  /// Malformed request rejected by Herdr (R-02-009). Raised by the Host. Not
  /// fatal.
  invalidRequest('invalid_request'),

  /// Unsupported key name. Raised by the Host. Not fatal.
  invalidKey('invalid_key'),

  /// Herdr request timed out. Raised by the Host. Not fatal.
  timeout('timeout'),

  /// Agent did not respond within 5000 ms. Raised by the Host. Not fatal.
  agentPromptStalled('agent_prompt_stalled'),

  /// Pane is not being watched. Raised by the Host. Not fatal.
  notWatching('not_watching'),

  /// Device has been revoked. Raised by the Host. Fatal.
  revoked('revoked'),

  /// No Host registered under this handle. Raised by the relay. Fatal.
  handleUnknown('handle_unknown'),

  /// A Device is already active on this Host. Raised by the relay. Fatal.
  hostInUse('host_in_use'),

  /// The 120-second phrase lifetime elapsed. Raised by the relay. Fatal.
  pairingExpired('pairing_expired'),

  /// Connection-rate or frame-rate limit exceeded. Raised by the relay.
  /// Fatal.
  rateLimited('rate_limited'),

  /// Noise handshake failed. Raised by both peers. Fatal.
  handshakeFailed('handshake_failed'),

  /// Named plugin has been disabled since the action list was fetched.
  /// Raised by the Host. Not fatal.
  pluginDisabled('plugin_disabled'),

  /// Action id is unknown to the named plugin. Raised by the Host. Not
  /// fatal.
  actionUnknown('action_unknown'),

  /// Unexpected error. Raised by both peers. Not fatal.
  internalError('internal_error');

  const ErrorCode(this.wireValue);

  /// The exact string this code serializes to on the wire.
  final String wireValue;

  /// Recovers the [ErrorCode] whose [wireValue] matches `value`.
  ///
  /// Throws a [FormatException] for an unknown code, per R-41-037: a
  /// validation failure MUST produce a typed error, never a silent default.
  factory ErrorCode.fromWireValue(String value) => values.firstWhere(
    (code) => code.wireValue == value,
    orElse: () => throw FormatException('unknown error code: $value'),
  );
}

/// `json_serializable` `fromJson` helper for a field typed [ErrorCode].
ErrorCode errorCodeFromJson(String value) => ErrorCode.fromWireValue(value);

/// `json_serializable` `toJson` helper for a field typed [ErrorCode].
String errorCodeToJson(ErrorCode code) => code.wireValue;
