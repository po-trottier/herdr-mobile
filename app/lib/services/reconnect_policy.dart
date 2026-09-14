/// The one reconnect backoff schedule for the whole repository
/// (`docs/22-platform-integration.md` R-22-028, restated by `docs/11-relay-protocol.md`
/// R-11-088): 0.5 s, 1 s, 2 s, 5 s, 10 s, then a 30 s cap repeated indefinitely, resetting to
/// the first delay after any connection that stayed up at least 30 seconds.
///
/// This schedule recovers the current connection to the active computer only. It MUST NOT
/// be used to reach a different computer (`docs/03-product-decisions.md` R-03-044); a switch
/// to a different computer is a fresh connection, not a retry, and `relay.dart` (`WP-14-a`)
/// creates a new [ReconnectPolicy] for that case rather than reusing this one's state.
///
/// Every attempt on this schedule is the cheap reconnect of R-03-113 item 7: it reuses the
/// relay origin, the routing handle and the pinned Host key the pairing record already holds.
/// [ReconnectPolicy.afterFailure] decides whether the next attempt keeps that path or the
/// schedule stops; there is no rediscovery and no built-in origin to fall back to (R-03-030,
/// R-03-031), so the only other path is the one that always existed: the person pairs again.
library;

import 'relay.dart' show RelayRegistrationErrorCode, RelayRegistrationException;

/// What the schedule does after a reconnect attempt failed (R-03-113 item 7).
enum ReconnectStep {
  /// Retry after the next delay with the same cached origin and handle. `handle_unknown`
  /// stays here: the relay discards the room the moment the Host drops and the Host
  /// re-registers the same handle on its own ladder (R-11-125), so the next attempt finds it.
  /// Every other failure is a network condition the schedule exists for.
  reuseHandle,

  /// Stop the schedule. The relay refused the handle for a reason no repeat can fix
  /// (`handle_taken`, `pairing_expired`), or another phone holds the Host (`host_in_use`
  /// outside [ReconnectPolicy.staleSlotWindow], R-30-942: one attempt per press of
  /// `Try again`, never the schedule).
  stop,
}

/// Tracks reconnect attempts and hands out the next delay from R-22-028's schedule. Stateful
/// by design: [nextDelay] both reads and advances the attempt counter, and
/// [noteConnected]/[noteDisconnected] bracket a live connection so the counter can reset
/// after a stable one.
final class ReconnectPolicy {
  ReconnectPolicy({DateTime Function() now = DateTime.now})
    // `this._now` would make the external parameter name `_now`, unusable from
    // `reconnect_policy_test.dart`, a different library, per Dart's named-parameter
    // privacy rule (same reasoning as `biometric_gate.dart`'s `_now` constructor param).
    // ignore: prefer_initializing_formals
    : _now = now;

  final DateTime Function() _now;

  /// The delay schedule for attempts 1 through 5 (R-22-028). Attempt 6 and every attempt
  /// after it use [_cap] instead.
  static const List<Duration> _schedule = [
    Duration(milliseconds: 500),
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
  ];

  /// The delay for attempt 6 and every attempt after it, repeated indefinitely.
  static const Duration _cap = Duration(seconds: 30);

  /// A connection that stayed up at least this long resets the schedule to attempt 1
  /// (R-22-028's "stable reset").
  static const Duration _stableConnectionThreshold = Duration(seconds: 30);

  /// How long after this phone's own link dropped a `host_in_use` refusal still names this
  /// phone's stale slot, not another phone (R-30-942, amended 2026-09-10). The relay learns of
  /// a dead socket through its keepalive: a ping every 30 s and a pong deadline of 10 s
  /// (R-11-022, R-11-023), so the slot is free again within 40 s; 45 s leaves one round trip
  /// of slack. Measured 2026-09-10 on the emulator: an 8 s network blip left the phone's
  /// socket open on the relay, the first reconnect got `host_in_use`, and the schedule
  /// stopped, so the app never reconnected until `Reconnect now`.
  static const Duration staleSlotWindow = Duration(seconds: 45);

  int _attempt = 0;
  DateTime? _connectedSince;
  DateTime? _disconnectedAt;

  /// How many delays [nextDelay] handed out since the schedule last reset: the attempt number
  /// of the reconnect that follows the latest delay. A log line carries this count, never the
  /// handle (`AGENTS.md` "Never log").
  int get attempts => _attempt;

  /// The delay before the next reconnect attempt, and advances the internal counter so the
  /// following call returns the next step of the schedule. The very first call (attempt 1)
  /// returns 0.5 s.
  Duration nextDelay() {
    final delay = _attempt < _schedule.length ? _schedule[_attempt] : _cap;
    _attempt++;
    return delay;
  }

  /// The next step after an attempt failed with [cause], the `Err.cause` of
  /// `RelayConnection.connect` (R-03-113 item 7). `handle_unknown` keeps the schedule; so
  /// does `host_in_use` inside [staleSlotWindow] after this phone's own drop, because the
  /// occupant is this phone's dead socket. Every other relay refusal stops it; see
  /// [ReconnectStep].
  ReconnectStep afterFailure(Object? cause) {
    if (cause is! RelayRegistrationException) return ReconnectStep.reuseHandle;
    return switch (cause.code) {
      RelayRegistrationErrorCode.handleUnknown => ReconnectStep.reuseHandle,
      RelayRegistrationErrorCode.hostInUse when _withinStaleSlotWindow =>
        ReconnectStep.reuseHandle,
      _ => ReconnectStep.stop,
    };
  }

  bool get _withinStaleSlotWindow {
    final DateTime? droppedAt = _disconnectedAt;
    return droppedAt != null && _now().difference(droppedAt) < staleSlotWindow;
  }

  /// Records that a connection just started, so a later [noteDisconnected] can judge
  /// whether it was stable.
  void noteConnected() {
    _connectedSince = _now();
  }

  /// Records that the connection just ended. Resets the attempt counter to 0 — so the next
  /// [nextDelay] call returns to 0.5 s — when the connection that just ended had lasted at
  /// least 30 seconds (R-22-028's stable reset). A connection that never called
  /// [noteConnected] is treated as never having been stable.
  void noteDisconnected() {
    final connectedSince = _connectedSince;
    _connectedSince = null;
    _disconnectedAt = _now();
    if (connectedSince != null &&
        _now().difference(connectedSince) >= _stableConnectionThreshold) {
      _attempt = 0;
    }
  }
}
