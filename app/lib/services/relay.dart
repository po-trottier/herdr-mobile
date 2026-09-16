/// The Device's one relay transport: exactly one `IOWebSocketChannel`
/// (`docs/11-relay-protocol.md` §2, R-20-009, R-22-025), the Noise session lifecycle
/// (`Noise_XXpsk0` for first pairing, `Noise_KK` for reconnect — `noise.dart`, `WP-14-b`),
/// the `host_info`/`device_info` handshake, `seq` accounting, the 1 MiB frame ceiling, and
/// the reconnect-and-resume flow every app screen ultimately reads from.
///
/// [RelayConnection] never holds two sockets at once: [connect] always closes any existing
/// socket first (R-20-009, R-22-025, R-11-222). It never buffers a frame for replay
/// (R-11-085): reconnect resynchronises with a fresh `tree_request` and, if a pane was being
/// watched, a fresh `watch_pane` (R-11-084, R-11-200).
///
/// This file always disables WebSocket-level compression, passing
/// `CompressionOptions.compressionOff` explicitly to `dart:io`'s `WebSocket.connect`
/// (R-11-230, R-20-011): neither pinned WebSocket library implements `permessage-deflate`
/// in the first place, and even one that did would only ever see already-Noise-encrypted
/// ciphertext, which is high-entropy and does not compress (R-13-012). Real compression now
/// happens one layer up, on the plaintext frame envelope before Noise encryption, in
/// `frame_codec.dart` (`docs/11-relay-protocol.md` §3.4, §3.5). `IOWebSocketChannel.connect`
/// (`package:web_socket_channel/io.dart`) does not forward a `compression` parameter at
/// all, so [_defaultChannelFactory] connects with the raw `WebSocket.connect` itself first
/// — passing `compressionOff` there — and only then wraps that same live instance with
/// `IOWebSocketChannel(webSocket)`, a documented alternate constructor that accepts an
/// already-connected `WebSocket`.
///
/// The four relay-level registration errors (R-11-117 to R-11-120) and every other
/// connection-state transition are published on [connectionState] with the exact raw
/// sentence R-11-092 requires; every decrypted application [Message] — including `error`
/// frames from inside the Noise session — is published verbatim on [messages]. Painting
/// `Computer in use on another phone` (R-30-940) or any other banner from these streams is a
/// later phase's screen (`app/lib/screens/`, not on this work package's `Paths.` line,
/// R-90-024): this file only ever raises, never paints.
///
/// Since 2026-09-09 (`docs/03-product-decisions.md` R-03-113 items 3 and 7) [connect] also
/// publishes one [RelayConnecting] per awaited step, [ConnectionStage], and a connect-time
/// failure carries the stage it stopped at with its raw text ([RelayDisconnected.failedStage],
/// [RelayDisconnected.failure]). A [ReconnectMode] attempt starts with
/// [ConnectionStage.reusingHandle]: the cached origin, handle and pinned key of the pairing
/// record, never a rediscovery and never a built-in origin (R-03-030, R-03-031);
/// `reconnect_policy.dart`'s [ReconnectPolicy.afterFailure] decides when that path stops. No
/// wire message changed for either: `device_register` (R-11-114) and both Noise patterns are
/// exactly as before.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show CompressionOptions, HttpClient, WebSocket;
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:logging/logging.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/result/result.dart' show Err, Ok, Result;
import '../models/codes.dart';
import '../models/frame.dart';
import '../models/message.dart';
import '../models/messages/device_info.dart';
import '../models/messages/disconnect.dart';
import '../models/messages/error_message.dart';
import '../models/messages/host_info.dart';
import '../models/messages/tree_request.dart';
import '../models/messages/unwatch_pane.dart';
import '../models/messages/watch_pane.dart';
import 'biometric_gate.dart';
import 'connectivity.dart';
import 'frame_codec.dart';
import 'noise.dart';
import 'origin.dart';
import 'reconnect_policy.dart';

/// R-11-013, R-12-020: the one relay subprotocol.
const String _subprotocol = 'herdr-relay.v1';

/// Cancels one pairing attempt and its socket.
final class PairingCancellation {
  final Completer<void> _cancelled = Completer<void>();

  bool _completed = false;

  /// True after this attempt starts to disconnect the previous host.
  bool disconnectedHost = false;

  bool get isCancelled => _cancelled.isCompleted;

  void cancel() {
    if (!_completed && !isCancelled) _cancelled.complete();
  }

  /// Releases cancellation after the caller receives a successful outcome.
  void complete() {
    _completed = true;
  }

  void check() {
    if (isCancelled) throw const PairingCancelledException();
  }

  Future<T> wait<T>(Future<T> operation) async {
    final value = await Future.any<T>([
      operation,
      _cancelled.future.then<T>((_) => throw const PairingCancelledException()),
    ]);
    check();
    return value;
  }
}

/// The person cancelled the attempt. This is not a phrase failure.
final class PairingCancelledException implements Exception {
  const PairingCancelledException();
}

/// A factory for the one [WebSocketChannel] [RelayConnection] ever opens. The default value
/// ([_defaultChannelFactory]) connects for real, with WebSocket-level compression always
/// disabled (R-11-230, R-20-011); tests inject a fake to exercise [RelayConnection]'s own
/// wire-level state machine — seq accounting, resume ordering, single-socket enforcement,
/// the frame-size ceiling — against a local, real WebSocket server, independent of the
/// (separately proven, see `noise.dart`'s own interop check) Noise cryptography.
typedef ChannelFactory = Future<WebSocketChannel> Function(
  Uri uri,
  List<String> protocols,
);

/// Connects with the raw `dart:io` `WebSocket.connect`, passing
/// `CompressionOptions.compressionOff` explicitly (R-11-230, R-20-011), then wraps that same
/// live instance with `IOWebSocketChannel(webSocket)` (see this file's own header doc
/// comment for why: `IOWebSocketChannel.connect` does not forward a `compression` parameter
/// at all).
Future<WebSocketChannel> _defaultChannelFactory(
  Uri uri,
  List<String> protocols, {
  PairingCancellation? cancellation,
}) async {
  final client = cancellation == null ? null : HttpClient();
  if (cancellation != null) {
    unawaited(
      cancellation._cancelled.future.then((_) {
        client?.close(force: true);
      }),
    );
  }
  try {
    cancellation?.check();
    // The caller owns the returned socket.
    // ignore: close_sinks
    final webSocket = await WebSocket.connect(
      uri.toString(),
      protocols: protocols,
      compression: CompressionOptions.compressionOff,
      customClient: client,
    );
    return IOWebSocketChannel(webSocket);
  } finally {
    client?.close();
  }
}

/// The scheme, host and port of [uri] — never its path, which carries the routing handle
/// (R-13-033). A log line or an `Err`/exception message a caller might display or log MUST
/// use this instead of the raw connection URI: the routing handle MUST NOT be logged,
/// printed, or surfaced in any user-visible string (`AGENTS.md` "Never log", R-41-031,
/// R-13-066). `Uri.origin` is not used here because it throws for the `ws`/`wss` schemes
/// this file always builds — it accepts only `http`/`https`.
String _originOnly(Uri uri) => uri.hasPort
    ? '${uri.scheme}://${uri.host}:${uri.port}'
    : '${uri.scheme}://${uri.host}';

/// Establishes the [NoiseSession] [RelayConnection.connect] uses, given the WebSocket
/// [channel]/[iterator] already past registration. [_defaultHandshaker] drives the real
/// `NoiseXxPsk0Initiator`/`NoiseKkInitiator` state machines from `noise.dart` against the
/// wire. Tests inject a fake with no real handshake bytes and a [NoiseSession] built from
/// [NoiseCipher.withKey] on a fixed, pre-agreed key, so [RelayConnection]'s own wire-level
/// behaviour — resume ordering, single-socket enforcement, seq accounting, the frame-size
/// ceiling — is testable against a real local WebSocket server, independent of the Noise
/// handshake itself, whose correctness `noise.dart`'s own interop check already proves byte
/// for byte against the real Rust responder.
typedef NoiseHandshaker = Future<NoiseSession> Function(
  StreamIterator<dynamic> iterator,
  WebSocketChannel channel,
  NoiseHandshakeMode mode,
  BiometricGate gate,
  SimpleKeyPair localStatic,
);

Future<NoiseSession> _defaultHandshaker(
  StreamIterator<dynamic> iterator,
  WebSocketChannel channel,
  NoiseHandshakeMode mode,
  BiometricGate gate,
  SimpleKeyPair localStatic,
) async {
  try {
    switch (mode) {
      case PairingMode(:final psk):
        final initiator = NoiseXxPsk0Initiator();
        await initiator.init(gate: gate, localStatic: localStatic);
        channel.sink.add(await initiator.writeMessage1(psk));
        await initiator.readMessage2(
          await _expectBinary(iterator, 'Noise handshake message 2'),
        );
        channel.sink.add(await initiator.writeMessage3());
        return await initiator.finish();
      case ReconnectMode(:final remoteStaticPublicKey):
        final initiator = NoiseKkInitiator();
        await initiator.init(
          gate: gate,
          localStatic: localStatic,
          remoteStaticPublicKey: remoteStaticPublicKey,
        );
        channel.sink.add(await initiator.writeMessage1());
        await initiator.readMessage2(
          await _expectBinary(iterator, 'Noise handshake message 2'),
        );
        final session = await initiator.finish();
        if (!_bytesEqual(
          session.remoteStaticPublicKey,
          remoteStaticPublicKey,
        )) {
          throw const RelayConnectException(
            RelayConnectFailure.pinnedKeyMismatch,
            "the Host's static key did not match the pinned key (R-13-037)",
          );
        }
        return session;
    }
  } on RelayConnectException {
    rethrow;
  } on NoiseSessionLockedException {
    rethrow;
  } on Exception catch (error) {
    // Never interpolate a caught exception's own message text: some Dart/package
    // exceptions embed the full connection URL, which carries the routing handle
    // (R-13-033, R-13-066, `AGENTS.md` "Never log"). The type name is enough for triage.
    throw RelayConnectException(
      RelayConnectFailure.handshakeFailed,
      'the Noise handshake failed: ${error.runtimeType}',
    );
  }
}

/// Which Noise pattern establishes the session (R-13-071): [PairingMode] for first pairing
/// (`Noise_XXpsk0`, the phrase-derived PSK), [ReconnectMode] for every connection after that
/// (`Noise_KK`, the pinned Host static key).
sealed class NoiseHandshakeMode {
  const NoiseHandshakeMode();
}

/// First pairing (R-13-014). [psk] is `noise.dart`'s `pskFromPhrase` output.
final class PairingMode extends NoiseHandshakeMode {
  const PairingMode({required this.psk});
  final Uint8List psk;
}

/// Every reconnect after the first pairing (R-13-015), including the one
/// [RelayConnection] performs automatically after a network change, a background/foreground
/// cycle, or a dropped socket.
final class ReconnectMode extends NoiseHandshakeMode {
  const ReconnectMode({required this.remoteStaticPublicKey});
  final Uint8List remoteStaticPublicKey;
}

/// `docs/11-relay-protocol.md` §9.5 / §2.4's four relay-level registration failures
/// (R-11-117 to R-11-120), each raised before the Noise tunnel exists.
enum RelayRegistrationErrorCode {
  handleUnknown('handle_unknown'),
  handleTaken('handle_taken'),
  hostInUse('host_in_use'),
  pairingExpired('pairing_expired');

  const RelayRegistrationErrorCode(this.wireValue);

  final String wireValue;

  static RelayRegistrationErrorCode? fromWireValue(String value) {
    for (final code in values) {
      if (code.wireValue == value) return code;
    }
    return null;
  }
}

/// Set as an [Err.cause] when the relay refuses registration. [message] is the relay's own
/// raw sentence (R-11-117 to R-11-120), shown verbatim per R-11-092 — never replaced with a
/// friendly sentence, though a screen MAY add one under it (R-30-940 for [hostInUse]).
final class RelayRegistrationException implements Exception {
  const RelayRegistrationException(this.code, this.message);
  final RelayRegistrationErrorCode code;
  final String message;
  @override
  String toString() => message;
}

/// Every other way [RelayConnection.connect] can fail.
enum RelayConnectFailure {
  /// [BiometricGate.deviceStaticKey] was `null`: the app is biometrically locked, so no
  /// real device key is available to build the Noise handshake with (R-13-064).
  deviceLocked,

  /// Opening or reading the raw WebSocket itself failed.
  webSocketFailed,

  /// The Noise handshake failed to complete or to authenticate the peer.
  handshakeFailed,

  /// R-11-133: `host_info.protocol` did not match this app's `frameProtocolVersion`.
  protocolMismatch,

  /// R-13-037: the Host's static key, learned during the handshake, did not match the
  /// pinned key [ReconnectMode] was given.
  pinnedKeyMismatch,

  /// R-11-237, R-11-238: a fragment's `frag_index` was out of order, or a `frag_count`
  /// above 40 was declared — the peer violated the frame codec's reassembly contract.
  frameReassemblyFailed,
}

/// Set as an [Err.cause] for every [RelayConnection.connect] failure that is not one of the
/// four [RelayRegistrationException] codes. [inner] is the transport exception a
/// [RelayConnectFailure.webSocketFailed] wraps, kept for `pairing_failure.dart` to classify
/// (refused, timed out, no route) without its text ever reaching a screen or a log: dart:io's
/// messages embed the connection URL, which carries the routing handle (R-13-066).
final class RelayConnectException implements Exception {
  const RelayConnectException(this.failure, this.message, {this.inner});
  final RelayConnectFailure failure;
  final String message;
  final Object? inner;
  @override
  String toString() => message;
}

/// Thrown by [RelayConnection.send] when no session is up. A person's tap can land while
/// the link is down (`Offline. Showing what we last saw.`), so this is an expected
/// operational condition, not a caller bug: send entry points reachable while offline
/// (`pane_actions.dart`'s FAB and pane action sheet) catch it and report their
/// not-connected text instead of letting it escape the tap handler.
final class RelayNotConnectedException implements Exception {
  const RelayNotConnectedException();
  @override
  String toString() => 'RelayConnection.send() called while not connected';
}

/// The awaited steps of one [RelayConnection.connect] attempt, in order, published one at a
/// time as [RelayConnecting.stage] (`docs/03-product-decisions.md` R-03-113 item 3). A
/// screen paints them as a staged list; this file only raises them. Only a step `connect()`
/// awaits is a stage: the post-connect `tree_request`/`watch_pane` resume (R-11-084) is
/// fire-and-forget with no completion signal, so it is not one. A log line names a stage by
/// [name] and never carries the handle or the origin path (`AGENTS.md` "Never log").
enum ConnectionStage {
  /// R-03-113 item 7: a [ReconnectMode] attempt reuses the relay origin, the routing handle
  /// and the pinned Host key the pairing record already holds. No rediscovery, no new
  /// pairing, no built-in origin (R-03-030, R-03-031). Absent from a [PairingMode] attempt.
  reusingHandle('Reusing handle'),

  /// Opening the one WebSocket to `/device/<handle>` (R-11-114).
  openingSocket('Opening WebSocket'),

  /// `device_register` sent, `session_joined` awaited (R-11-114 to R-11-120).
  registeringHandle('Registering handle'),

  /// The Noise handshake the [NoiseHandshakeMode] selects (R-13-014, R-13-015).
  handshake('Noise handshake'),

  /// `host_info` read and its protocol checked, `device_info` sent (R-11-130 to R-11-133).
  hostInfo('Host info');

  const ConnectionStage(this.label);

  /// The row title a screen shows for this stage (`docs/31-mockups/13-connection.md`).
  final String label;
}

/// [RelayConnection]'s own connection lifecycle, published on
/// [RelayConnection.connectionState]. A later phase's screen paints these; this file only
/// raises them (R-90-024 — no `app/lib/screens/` path is on this work package's `Paths.`
/// line).
sealed class RelayConnectionState {
  const RelayConnectionState();
}

/// One attempt is running and [stage] is its current step (R-03-113 item 3). Every stage
/// before it in [ConnectionStage.values] completed; every stage after it has not started.
final class RelayConnecting extends RelayConnectionState {
  const RelayConnecting(this.stage);
  final ConnectionStage stage;
}

final class RelayConnected extends RelayConnectionState {
  const RelayConnected();
}

final class RelayDisconnected extends RelayConnectionState {
  const RelayDisconnected({
    this.closeCode,
    this.closeReason,
    this.failedStage,
    this.failure,
  });

  /// R-31-13-02, R-11-092: raw WebSocket close code when link dropped with no preceding
  /// `error` frame (network drop, abnormal closure). `null` for deliberate app-initiated
  /// close or connect-time failure with no live session. Shown raw, e.g.
  /// "websocket closed 1006" — never replaced with a friendly sentence.
  final int? closeCode;
  final String? closeReason;

  /// R-03-113 item 3: the stage a connect attempt was in when it failed, with [failure] as
  /// the raw error text (R-30-803, R-11-092). Both `null` when no attempt was running: a
  /// deliberate close, or a link that dropped mid-session. A relay refusal at
  /// [ConnectionStage.registeringHandle] is [RelayRegistrationError] instead.
  final ConnectionStage? failedStage;
  final String? failure;
}

/// Between reconnect attempts, waiting out [delay] (R-22-028).
final class RelayReconnecting extends RelayConnectionState {
  const RelayReconnecting(this.delay);
  final Duration delay;
}

/// One of the four relay-level registration errors just refused a connection or a
/// background reconnect attempt (R-11-117 to R-11-120). Per R-30-942 the app MUST NOT retry
/// `host_in_use` on the backoff schedule; [RelayConnection] stops the automatic retry loop
/// for all four, conservatively, since none of them is a transient network condition a retry
/// could fix.
final class RelayRegistrationError extends RelayConnectionState {
  const RelayRegistrationError(this.code, this.message);
  final RelayRegistrationErrorCode code;
  final String message;
}

/// R-13-054, R-13-055: the socket closed mid-session with code `4004` (`revoked`,
/// R-11-121). The Device MUST show "Connection lost — this device has been revoked" and
/// clear that computer's stored Host key and handle (never the relay origin, never another
/// saved computer), per R-13-054. [RelayConnection] never auto-reconnects after this state
/// — a revoked Device retrying the same key only earns another `4004`.
final class RelayRevoked extends RelayConnectionState {
  const RelayRevoked();
}

/// The parameters needed to retry the current computer's connection (R-22-028) or to
/// reconnect on foreground (R-22-026). Never used to reach a different computer
/// (R-03-044) — a caller starts a fresh [RelayConnection] for that. Holds no static key of
/// its own: [RelayConnection.connect] re-derives it fresh from [gate].`deviceStaticKey` on
/// every attempt, so a reconnect scheduled after the app re-locked correctly fails instead
/// of reusing a stale cached key object (R-13-064).
final class _ConnectParams {
  const _ConnectParams({
    required this.origin,
    required this.handle,
    required this.gate,
    required this.deviceInfo,
    required this.pinnedHostKey,
  });

  final RelayOrigin origin;
  final String handle;
  final BiometricGate gate;
  final DeviceInfo deviceInfo;
  final Uint8List pinnedHostKey;
}

/// The app's one relay transport (R-20-009, R-22-025). See this file's own doc comment for
/// the full contract.
final class RelayConnection {
  RelayConnection({
    ChannelFactory? channelFactory,
    NoiseHandshaker? handshaker,
    ConnectivityWatcher? connectivityWatcher,
    Logger? logger,
    DateTime Function()? now,
  }) : _channelFactory = channelFactory ?? _defaultChannelFactory,
       _handshaker = handshaker ?? _defaultHandshaker,
       _connectivity = connectivityWatcher ?? ConnectivityWatcher(),
       _log = logger ?? Logger('RelayConnection'),
       _now = now ?? DateTime.now {
    _connectivity.start();
    _connectivitySubscription = _connectivity.onNetworkStable.listen(
      (_) => _onNetworkStable(),
    );
  }

  final ChannelFactory _channelFactory;
  final NoiseHandshaker _handshaker;
  final ConnectivityWatcher _connectivity;
  final Logger _log;
  // R-11-238: threaded into every `decodeFragment`/`acceptFragment` call and into
  // `_awaitNextFragment`'s own deadline race, so a test can inject a fake clock instead of
  // sleeping through the real 10-second inter-fragment timeout.
  final DateTime Function() _now;
  late final StreamSubscription<void> _connectivitySubscription;

  final ReconnectPolicy _reconnectPolicy = ReconnectPolicy();
  Timer? _reconnectTimer;

  WebSocketChannel? _channel;
  NoiseSession? _session;
  // Every call to send() chains onto this future rather than firing `_sendOn`
  // independently. `NoiseCipher.encrypt` is not reentrant-safe: two concurrent calls can
  // both read its `_nonce` counter before either increments it, encrypting two frames with
  // the same nonce and silently corrupting the stream for every frame after (a receiver
  // decrypting in wire order eventually hits a MAC mismatch). `_resume` sends `tree_request`
  // then `watch_pane` back to back (R-11-084), which reproduces this without the queue.
  Future<void> _sendQueue = Future<void>.value();
  int _outgoingSeq = 0;
  int? _incomingSeq;
  String? _watchedPaneId;
  bool _deliberateClose = false;
  bool _wasConnectedBeforeBackground = false;
  _ConnectParams? _lastParams;
  HostInfo? _lastHostInfo;
  // R-31-13-06: every counter below resets to zero/empty/null on each successful connect()
  // (WP-21-a's connection screen). Sites: framesOut/bytesOut-adjacent tracking lives in
  // _sendFrame; framesIn/bytesInOnWire/bytesInUnpacked in _pumpIncoming;
  // _outstandingCorr/_lastRoundTrip span both (R-31-13-19: one phone-measured round trip,
  // paired by R-11-031's corr, never a dedicated ping — R-11-024).
  int _framesIn = 0;
  int _framesOut = 0;
  int _bytesInOnWire = 0;
  int _bytesInUnpacked = 0;
  Duration? _lastRoundTrip;
  final Map<String, DateTime> _outstandingCorr = {};

  final StreamController<Message> _messagesController =
      StreamController<Message>.broadcast();
  final StreamController<RelayConnectionState> _stateController =
      StreamController<RelayConnectionState>.broadcast();

  /// Every decrypted application [Message] this session receives, in wire order, including
  /// `error` frames (R-11-092: shown raw, never replaced with a friendly sentence).
  Stream<Message> get messages => _messagesController.stream;

  /// This connection's own lifecycle (see [RelayConnectionState]).
  Stream<RelayConnectionState> get connectionState => _stateController.stream;

  /// `true` while a Noise session is established and frames may be sent.
  bool get isConnected => _channel != null && _session != null;

  /// The pane this connection is currently watching (R-11-048, R-11-084), or `null`. A
  /// caller that is about to point this connection at a different Host reads this before
  /// calling [connect] again, so it can [unwatchPane] first — a stale watch means nothing in
  /// another Host's pane-id space, and [_resume] would otherwise resend `watch_pane` for it
  /// after the switch (R-30-949).
  String? get watchedPaneId => _watchedPaneId;

  /// Host static public key learned during the last successful handshake (R-13-037,
  /// R-13-040). `null` before first successful [connect]. Persists across disconnect
  /// (survives until next successful [connect] overwrites it, same lifecycle as
  /// [_lastParams]) so a caller reads it right after `connect()` returns `Ok`, for
  /// R-13-048/R-13-063 keystore persistence.
  Uint8List? get pinnedHostKey => _lastParams?.pinnedHostKey;

  /// `host_info` received as the first frame of the last successful handshake. `null`
  /// before first successful [connect]. Same lifecycle as [pinnedHostKey] — for
  /// R-13-048/R-13-063 plain-store persistence and R-13-041's fingerprint/hostName
  /// display; not republished on [messages] since [connect] itself consumes it before
  /// [_pumpIncoming] starts listening.
  HostInfo? get lastHostInfo => _lastHostInfo;

  /// Application frames dispatched from the current session (R-31-13-06). Reset to `0` on
  /// each successful [connect]; not persisted across a disconnect/reconnect boundary.
  int get framesIn => _framesIn;

  /// Application frames actually placed on the wire from the current session — the
  /// original attempt or, for a rejected oversized frame, its `frame_too_large`
  /// replacement, whichever one real physical frame occupied that seq (R-31-13-06).
  int get framesOut => _framesOut;

  /// Sum of compressed record bytes read off the wire for every reassembled incoming
  /// frame this session (R-31-13-06, `frame_codec.dart` §3.4). Excludes the `host_info`
  /// handshake frame, consumed by [connect] before this counter's own reset point.
  int get bytesInOnWire => _bytesInOnWire;

  /// Sum of decompressed frame-envelope bytes for every reassembled incoming frame this
  /// session (R-31-13-06). A caller derives the compression percentage as
  /// `bytesInOnWire / bytesInUnpacked * 100`; this file publishes only the two counts.
  int get bytesInUnpacked => _bytesInUnpacked;

  /// The most recent phone-measured round trip (R-31-13-19): an outgoing frame's `corr`
  /// (R-11-031) timestamped in [_sendOn], matched against the next incoming frame that
  /// echoes the same `corr`. Never a dedicated keep-alive — R-11-024 already forbids a
  /// second network surface for this. `null` before the first correlated reply of a
  /// session.
  Duration? get lastRoundTrip => _lastRoundTrip;

  /// Opens the one relay socket, registers on `/device/<handle>` (R-11-114), runs the Noise
  /// handshake [mode] selects, exchanges `host_info`/`device_info` (R-11-130 to R-11-133),
  /// and — for [ReconnectMode] — resumes with `tree_request` and, if a pane was previously
  /// watched, `watch_pane` (R-11-084, R-11-200). Always closes any existing socket first
  /// (R-20-009, R-22-025, R-11-222).
  Future<Result<void>> connect({
    required RelayOrigin origin,
    required String handle,
    required NoiseHandshakeMode mode,
    required BiometricGate gate,
    required DeviceInfo deviceInfo,
    PairingCancellation? cancellation,
  }) async {
    // R-13-064: the real device key comes from the biometric-gated read the gate already
    // performed, never an independently generated or passed-in one. While App Lock is off
    // (R-31-04-12) no `/lock` screen ever runs `unlock()`, so the gate reports unlocked with
    // no key loaded yet; that first read raises no OS prompt, because the key was written
    // without an authentication requirement. `null` after that means locked — a
    // precondition failure, not a connection attempt with no key.
    if (gate.deviceStaticKey == null && !gate.isLocked) {
      await gate.unlock();
    }
    cancellation?.check();
    final localStatic = gate.deviceStaticKey;
    if (localStatic == null) {
      return const Err(
        'connect to relay',
        cause: RelayConnectException(
          RelayConnectFailure.deviceLocked,
          'the app is biometrically locked; no device key is available (R-13-064)',
        ),
      );
    }

    if (cancellation != null) cancellation.disconnectedHost = isConnected;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    if (mode is PairingMode) {
      _lastParams = null;
      _wasConnectedBeforeBackground = false;
    }
    await _closeCurrentSocket(deliberate: false);
    cancellation?.check();
    if (mode is ReconnectMode) {
      // R-03-113 item 7, the cheap path: `origin`, `handle` and the pinned key all come from
      // the pairing record the caller read (`host_list.dart`) or from [_lastParams]. This
      // file never rediscovers a relay and ships no origin of its own (R-03-030, R-03-031).
      _enterStage(ConnectionStage.reusingHandle);
    }
    var stage = _enterStage(ConnectionStage.openingSocket);

    final uri = origin.webSocketUri('/device/$handle');
    final WebSocketChannel channel;
    try {
      channel = await (_channelFactory == _defaultChannelFactory
          ? _defaultChannelFactory(uri, const [
              _subprotocol,
            ], cancellation: cancellation)
          : _channelFactory(uri, const [_subprotocol]));
    } on Exception catch (error) {
      // Never interpolate a caught exception's own message text here: dart:io's
      // WebSocket/HttpException/SocketException messages routinely embed the full
      // connection URL, which carries the routing handle (R-13-033, R-13-066, `AGENTS.md`
      // "Never log"). The type name is enough for triage.
      final failure = RelayConnectException(
        RelayConnectFailure.webSocketFailed,
        'Could not open a connection to ${_originOnly(uri)}: ${error.runtimeType}',
        inner: error,
      );
      cancellation?.check();
      _stateController.add(
        RelayDisconnected(failedStage: stage, failure: failure.message),
      );
      return Err('connect to relay ${_originOnly(uri)}', cause: failure);
    }
    final iterator = StreamIterator<dynamic>(channel.stream);

    if (cancellation != null) {
      unawaited(
        cancellation._cancelled.future.then((_) async {
          final Future<dynamic> close;
          if (identical(_channel, channel)) {
            _lastParams = null;
            _wasConnectedBeforeBackground = false;
            _reconnectTimer?.cancel();
            _reconnectTimer = null;
            close = _closeCurrentSocket(deliberate: true);
          } else {
            close = channel.sink.close(ws_status.normalClosure);
          }
          await iterator.cancel();
          await close;
        }),
      );
    }
    try {
      cancellation?.check();
      stage = _enterStage(ConnectionStage.registeringHandle);
      channel.sink.add(
        jsonEncode({
          'type': 'device_register',
          'protocol': frameProtocolVersion,
        }),
      );
      final registration = await _expectText(
        iterator,
        'a registration response',
      );
      cancellation?.check();
      final decoded = jsonDecode(registration) as Map<String, dynamic>;
      if (decoded['type'] == 'error') {
        final message = decoded['message'] as String;
        final code = RelayRegistrationErrorCode.fromWireValue(
          decoded['code'] as String? ?? '',
        );
        if (code == null) {
          throw RelayConnectException(
            RelayConnectFailure.webSocketFailed,
            'registration refused: $message',
          );
        }
        throw RelayRegistrationException(code, message);
      }
      if (decoded['type'] != 'session_joined') {
        throw RelayConnectException(
          RelayConnectFailure.webSocketFailed,
          'unexpected registration response: $registration',
        );
      }

      stage = _enterStage(ConnectionStage.handshake);
      final session = await _handshaker(
        iterator,
        channel,
        mode,
        gate,
        localStatic,
      );
      cancellation?.check();
      final reassembler = Reassembler();

      stage = _enterStage(ConnectionStage.hostInfo);

      final firstFrame = await _readEnvelope(
        iterator,
        session,
        reassembler,
        'host_info',
      );
      cancellation?.check();
      if (firstFrame.type != 'host_info') {
        // R-11-132: the first frame after transport mode MUST be host_info.
        throw const RelayConnectException(
          RelayConnectFailure.protocolMismatch,
          'the Host sent a message other than host_info as its first frame',
        );
      }
      final hostInfo = HostInfo.fromJson(firstFrame.payload);
      _incomingSeq = firstFrame.seq;
      if (hostInfo.protocol != frameProtocolVersion) {
        if (frameProtocolVersion > hostInfo.protocol) {
          // R-11-133: the side with the higher version sends the error.
          await _sendFrame(
            channel,
            session,
            Frame(
              v: frameProtocolVersion,
              type: 'error',
              seq: 1,
              payload: ErrorMessage(
                code: ErrorCode.protocolMismatch,
                message:
                    'This app speaks relay protocol $frameProtocolVersion; '
                    'the Host speaks ${hostInfo.protocol}.',
                fatal: true,
              ).toJson(),
            ),
          );
        }
        throw RelayConnectException(
          RelayConnectFailure.protocolMismatch,
          'relay protocol version mismatch: Host speaks ${hostInfo.protocol}, '
          'this app speaks $frameProtocolVersion',
        );
      }

      cancellation?.check();
      _channel = channel;
      _session = session;
      _outgoingSeq = 0;
      _framesIn = 0;
      _framesOut = 0;
      _bytesInOnWire = 0;
      _bytesInUnpacked = 0;
      _lastRoundTrip = null;
      _outstandingCorr.clear();
      _deliberateClose = false;
      _lastParams = _ConnectParams(
        origin: origin,
        handle: handle,
        gate: gate,
        deviceInfo: deviceInfo,
        pinnedHostKey: session.remoteStaticPublicKey,
      );
      _lastHostInfo = hostInfo;

      // R-11-131: device_info is the Device's own first frame, sent immediately.
      await _sendOn(channel, session, Message.deviceInfo(deviceInfo));

      cancellation?.check();
      _reconnectPolicy.noteConnected();
      _stateController.add(const RelayConnected());
      _log.info(
        'connected to ${_originOnly(uri)}; WebSocket-level compression is off '
        '(R-11-230, R-20-011)',
      );

      unawaited(_pumpIncoming(channel, iterator, session, reassembler));

      if (mode is ReconnectMode) {
        await _resume();
      }

      return const Ok(null);
    } on PairingCancelledException {
      await iterator.cancel();
      await channel.sink.close(ws_status.normalClosure);
      rethrow;
    } on RelayRegistrationException catch (error) {
      await iterator.cancel();
      await channel.sink.close(ws_status.normalClosure);
      cancellation?.check();
      _stateController.add(RelayRegistrationError(error.code, error.message));
      return Err('register on ${_originOnly(uri)}', cause: error);
    } on RelayConnectException catch (error) {
      await iterator.cancel();
      // R-11-121: a frame-reassembly violation closes with protocol_error (4003); every
      // other connect failure closes normally — the peer never spoke the wire protocol
      // wrongly, this app simply gave up on the attempt.
      await channel.sink.close(
        error.failure == RelayConnectFailure.frameReassemblyFailed
            ? 4003
            : ws_status.normalClosure,
      );
      cancellation?.check();
      _stateController.add(
        RelayDisconnected(failedStage: stage, failure: error.message),
      );
      return Err('connect to relay ${_originOnly(uri)}', cause: error);
    } on NoiseSessionLockedException catch (error) {
      await iterator.cancel();
      await channel.sink.close(ws_status.normalClosure);
      cancellation?.check();
      _stateController.add(
        RelayDisconnected(failedStage: stage, failure: '$error'),
      );
      return Err('connect to relay ${_originOnly(uri)}', cause: error);
    }
  }

  /// Sends [message] on the current session, maintaining the outgoing `seq` (R-11-080) and
  /// enforcing the 1 MiB frame ceiling (R-11-035, R-11-036). Throws
  /// [RelayNotConnectedException] when called while not connected — an expected operational
  /// condition a caller can catch, not a caller bug.
  void send(Message message, {String? corr}) {
    final channel = _channel;
    final session = _session;
    if (channel == null || session == null) {
      throw const RelayNotConnectedException();
    }
    _sendQueue = _sendQueue
        .then((_) => _sendOn(channel, session, message, corr: corr))
        .catchError((Object error) {
          _log.warning(
            'failed to send a ${message.typeName} frame: ${error.runtimeType}',
          );
        });
  }

  /// The Device watches at most one pane at a time (R-11-048); a later call replaces the
  /// pane a resume re-watches (R-11-084).
  void watchPane(String paneId, {String? corr}) {
    _watchedPaneId = paneId;
    send(Message.watchPane(WatchPane(paneId: paneId)), corr: corr);
  }

  void unwatchPane(String paneId, {String? corr}) {
    if (_watchedPaneId == paneId) {
      _watchedPaneId = null;
    }
    send(Message.unwatchPane(UnwatchPane(paneId: paneId)), corr: corr);
  }

  /// A deliberate disconnect (R-11-206): sends `disconnect`, then closes cleanly with code
  /// `1000`. Keeps the pairing and the key; does not clear [_lastParams], so an explicit
  /// [connect] later still has them, but does not itself schedule an automatic reconnect.
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    await _closeCurrentSocket(deliberate: true, sendDisconnectFrame: true);
  }

  /// R-22-025, R-22-026: close cleanly on background, reconnect and resume on foreground.
  Future<void> noteLifecycleChange(AppLifecycleState state) async {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (isConnected) {
        _wasConnectedBeforeBackground = true;
        await _closeCurrentSocket(deliberate: true, sendDisconnectFrame: true);
      }
      return;
    }
    if (state == AppLifecycleState.resumed) {
      final params = _lastParams;
      if (params != null && !isConnected && _wasConnectedBeforeBackground) {
        _wasConnectedBeforeBackground = false;
        _reconnectTimer?.cancel();
        await connect(
          origin: params.origin,
          handle: params.handle,
          mode: ReconnectMode(remoteStaticPublicKey: params.pinnedHostKey),
          gate: params.gate,
          deviceInfo: params.deviceInfo,
        );
      }
    }
  }

  /// Releases every resource this connection holds (R-41-100).
  Future<void> dispose() async {
    _reconnectTimer?.cancel();
    await _connectivitySubscription.cancel();
    await _connectivity.dispose();
    await _closeCurrentSocket(deliberate: true);
    await _messagesController.close();
    await _stateController.close();
  }

  Future<void> _resume() async {
    send(const Message.treeRequest(TreeRequest()));
    final paneId = _watchedPaneId;
    if (paneId != null) {
      send(Message.watchPane(WatchPane(paneId: paneId)));
    }
  }

  void _onNetworkStable() {
    // R-22-027: the 1-second debounce already happened inside ConnectivityWatcher. A
    // reconnect only makes sense once a connection has existed before; the first pairing
    // is a person's own explicit action, not something a network blip should retry.
    if (_lastParams != null && !isConnected && _reconnectTimer == null) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    final params = _lastParams;
    if (params == null) return;
    _reconnectTimer?.cancel();
    final delay = _reconnectPolicy.nextDelay();
    _stateController.add(RelayReconnecting(delay));
    _reconnectTimer = Timer(delay, () => unawaited(_attemptReconnect(params)));
  }

  Future<void> _attemptReconnect(_ConnectParams params) async {
    _reconnectTimer = null;
    // R-03-113 item 7: the cheap path first. [params] is the cached origin, handle and
    // pinned key; `connect()` raises `ConnectionStage.reusingHandle` for it. The log carries
    // the attempt count only, never the handle (`AGENTS.md` "Never log").
    _log.info(
      'reconnect attempt ${_reconnectPolicy.attempts}: reusing the cached handle',
    );
    final result = await connect(
      origin: params.origin,
      handle: params.handle,
      mode: ReconnectMode(remoteStaticPublicKey: params.pinnedHostKey),
      gate: params.gate,
      deviceInfo: params.deviceInfo,
    );
    if (result case Err(:final cause)) {
      switch (_reconnectPolicy.afterFailure(cause)) {
        case ReconnectStep.reuseHandle:
          _scheduleReconnect();
        case ReconnectStep.stop:
          _log.warning('stopping automatic reconnect: $cause');
      }
    }
  }

  /// Publishes [stage] as the running step of the current attempt (R-03-113 item 3) and logs
  /// its name — the stage name only, never the handle or the origin path. Returns [stage] so
  /// a caller can track the stage a later failure lands in.
  ConnectionStage _enterStage(ConnectionStage stage) {
    _stateController.add(RelayConnecting(stage));
    _log.fine('connection stage: ${stage.name}');
    return stage;
  }

  Future<void> _closeCurrentSocket({
    required bool deliberate,
    bool sendDisconnectFrame = false,
    int closeCode = ws_status.normalClosure,
  }) async {
    final channel = _channel;
    final session = _session;
    _channel = null;
    _session = null;
    if (channel == null) {
      return;
    }
    _deliberateClose = deliberate;
    if (sendDisconnectFrame && session != null) {
      try {
        await _sendOn(channel, session, const Message.disconnect(Disconnect()));
      } on Exception catch (error) {
        _log.warning(
          'failed to send a deliberate disconnect frame: ${error.runtimeType}',
        );
      }
    }
    try {
      await channel.sink.close(closeCode);
    } on Exception catch (error) {
      _log.warning(
        'failed to close the relay socket cleanly: ${error.runtimeType}',
      );
    }
    if (deliberate) {
      _stateController.add(const RelayDisconnected());
    }
  }

  Future<void> _pumpIncoming(
    WebSocketChannel channel,
    StreamIterator<dynamic> iterator,
    NoiseSession session,
    Reassembler reassembler,
  ) async {
    try {
      var wireBytesForRecord = 0;
      pump:
      while (true) {
        final Uint8List raw;
        switch (await _awaitNextFragment(iterator, reassembler, _now)) {
          case _StreamClosed():
            break pump;
          case _FragmentTimedOut():
            // R-11-121, R-11-238: no fragment arrived within 10 seconds of the previous
            // one — an active deadline, not one only checked reactively when a next
            // fragment happens to show up, since here none ever does.
            _log.warning(
              'no fragment arrived within 10 seconds of the previous one (R-11-238)',
            );
            if (identical(_channel, channel)) {
              await _closeCurrentSocket(deliberate: false, closeCode: 4003);
              _scheduleReconnect();
            }
            return;
          case _FragmentReceived(:final current):
            if (current is! List<int>) {
              _log.warning(
                'ignoring a non-binary frame after the Noise handshake',
              );
              continue pump;
            }
            raw = Uint8List.fromList(current);
        }
        wireBytesForRecord += raw.length;
        final outcome = await decodeFragment(
          reassembler,
          session.receive,
          raw,
          now: _now,
        );
        if (outcome case Err(:final cause)) {
          // R-11-121, R-11-237, R-11-238: a fragmentation/reassembly violation closes
          // with protocol_error (4003), never a silent drop (`frame_codec.dart`'s own
          // header comment).
          _log.warning('frame reassembly violation: $cause');
          if (identical(_channel, channel)) {
            await _closeCurrentSocket(deliberate: false, closeCode: 4003);
            _scheduleReconnect();
          }
          return;
        }
        final envelopeBytes = (outcome as Ok<Uint8List?>).value;
        if (envelopeBytes == null) {
          // Still assembling this record's fragments (R-11-235).
          continue;
        }
        _bytesInOnWire += wireBytesForRecord;
        _bytesInUnpacked += envelopeBytes.length;
        wireBytesForRecord = 0;
        _framesIn++;
        final Frame frame;
        try {
          frame = Frame.fromJson(
            jsonDecode(utf8.decode(envelopeBytes)) as Map<String, dynamic>,
          );
        } on FormatException catch (error) {
          _log.warning(
            'failed to parse a reassembled frame envelope: ${error.runtimeType}',
          );
          continue;
        }
        final expectedSeq = (_incomingSeq ?? 0) + 1;
        if (frame.seq != expectedSeq) {
          _log.warning(
            'incoming seq gap: expected $expectedSeq, got ${frame.seq} (R-11-080)',
          );
        }
        _incomingSeq = frame.seq;
        if (frame.corr != null) {
          final sentAt = _outstandingCorr.remove(frame.corr);
          if (sentAt != null) {
            _lastRoundTrip = _now().difference(sentAt);
          }
        }

        final Message message;
        try {
          message = messageFromTypeAndPayload(frame.type, frame.payload);
        } on FormatException catch (error) {
          _log.warning(
            'unknown message type "${frame.type}": ${error.runtimeType}',
          );
          continue;
        }
        if (message is MessageHostTheme) {
          _lastHostInfo = _lastHostInfo?.copyWith(theme: message.payload.theme);
        }
        _messagesController.add(message);
        if (message is MessageError && message.payload.fatal) {
          _log.severe(
            'fatal error from Host: ${message.payload.code.wireValue} '
            '${message.payload.message}',
          );
          if (identical(_channel, channel)) {
            // R-13-054, R-13-055, R-11-065: `revoked` is fatal:true and MUST be the last
            // frame before the Host closes — authoritative at the application layer, so
            // this never races the WebSocket close code the way the `finally` block's own
            // `channel.closeCode == 4004` check does. Detected here first: by the time
            // `_closeCurrentSocket` clears `_channel`, the outer `finally` block's own
            // `identical(_channel, channel)` guard is already false and never runs.
            if (message.payload.code == ErrorCode.revoked) {
              await _closeCurrentSocket(deliberate: false);
              _reconnectPolicy.noteDisconnected();
              _stateController.add(const RelayRevoked());
              _lastParams = null;
            } else {
              await _closeCurrentSocket(deliberate: false);
              _scheduleReconnect();
            }
          }
          return;
        }
      }
    } finally {
      if (identical(_channel, channel)) {
        final wasDeliberate = _deliberateClose;
        // R-13-054, R-13-055: read before _closeCurrentSocket runs — the peer already
        // closed this socket (this is the finally block, not a return inside the loop),
        // so `channel.closeCode` already holds whatever code the peer sent; closing an
        // already-closed WebSocket again is a no-op and never overwrites it.
        final revoked = !wasDeliberate && channel.closeCode == 4004;
        await _closeCurrentSocket(deliberate: false);
        if (!wasDeliberate) {
          _reconnectPolicy.noteDisconnected();
          if (revoked) {
            _log.warning('the Host revoked this Device (R-13-054, R-13-055)');
            _stateController.add(const RelayRevoked());
            // Never auto-reconnect: the same key only earns another 4004.
            _lastParams = null;
          } else {
            _stateController.add(
              RelayDisconnected(
                closeCode: channel.closeCode,
                closeReason: channel.closeReason,
              ),
            );
            _scheduleReconnect();
          }
        }
      }
    }
  }

  Future<void> _sendOn(
    WebSocketChannel channel,
    NoiseSession session,
    Message message, {
    String? corr,
  }) async {
    // R-11-033: seq increments once per frame actually sent. An oversized frame is
    // rejected before it ever reaches the wire (R-11-036), so its candidate seq MUST be
    // reused by the `frame_too_large` reply that takes its place on the wire instead —
    // never burned on a frame nobody ever received.
    final candidateSeq = _outgoingSeq + 1;
    final frame = Frame(
      v: frameProtocolVersion,
      type: message.typeName,
      seq: candidateSeq,
      corr: corr,
      payload: message.payloadJson,
    );
    final sentAt = _now();
    final sent = await _sendFrame(channel, session, frame);
    if (sent case Ok() when corr != null) {
      _outstandingCorr[corr] = sentAt;
    }
    if (sent case Err()) {
      await _sendFrame(
        channel,
        session,
        Frame(
          v: frameProtocolVersion,
          type: 'error',
          seq: candidateSeq,
          payload: const ErrorMessage(
            code: ErrorCode.frameTooLarge,
            message: 'This frame exceeds the 1 MiB limit and was not sent.',
            fatal: false,
          ).toJson(),
        ),
      );
    }
    _outgoingSeq = candidateSeq;
  }

  /// R-11-229: compresses, fragments and Noise-encrypts [frame]'s envelope, then sends
  /// every fragment as its own physical WebSocket binary frame, in order. Returns
  /// [Err] only for [EnvelopeTooLarge] (R-11-035, R-11-036) — logged here, since every
  /// caller's own response to an oversized frame is the same `frame_too_large` reply.
  Future<Result<void>> _sendFrame(
    WebSocketChannel channel,
    NoiseSession session,
    Frame frame,
  ) async {
    final envelopeBytes = Uint8List.fromList(
      utf8.encode(jsonEncode(frame.toJson())),
    );
    if (envelopeBytes.length > maxUncompressedLen) {
      // R-11-035, R-11-233: relay.dart's own transport-level ceiling, checked before the
      // envelope ever reaches frame_codec.dart — separate from that file's own compressed-
      // record and fragment-count bounds (R-11-234, R-11-236).
      _log.warning(
        'dropped an outgoing ${frame.type} frame: ${envelopeBytes.length} bytes '
        'exceeds the 1 MiB ceiling (R-11-035, R-11-036)',
      );
      return Err('encode ${frame.type} frame', cause: const EnvelopeTooLarge());
    }
    final encoded = await encodeFrame(session.send, envelopeBytes);
    if (encoded case Err(:final cause)) {
      _log.warning(
        'dropped an outgoing ${frame.type} frame: $cause (R-11-035, R-11-036)',
      );
      return Err('encode ${frame.type} frame', cause: cause);
    }
    for (final fragment in (encoded as Ok<List<Uint8List>>).value) {
      channel.sink.add(fragment);
    }
    _framesOut++;
    return const Ok(null);
  }

  /// R-11-229 step 5, R-11-237, R-11-238: reads and Noise-decrypts physical WebSocket
  /// binary frames from [iterator], feeding each into [reassembler], until one complete
  /// frame envelope has been reassembled and decompressed — actively racing an in-progress
  /// record's own R-11-238 deadline the same way [_pumpIncoming] does, so a Host that sends
  /// one fragment and then nothing at all can never hang this synchronous read forever.
  /// Used only for [connect]'s own `host_info` read; the ongoing [_pumpIncoming] loop has
  /// its own per-fragment handling, since a reassembly failure there closes the live
  /// session with code `4003` rather than failing a pending [connect] call.
  Future<Frame> _readEnvelope(
    StreamIterator<dynamic> iterator,
    NoiseSession session,
    Reassembler reassembler,
    String what,
  ) async {
    while (true) {
      final Uint8List ciphertext;
      switch (await _awaitNextFragment(iterator, reassembler, _now)) {
        case _StreamClosed():
          throw RelayConnectException(
            RelayConnectFailure.webSocketFailed,
            'the relay closed the connection before sending $what',
          );
        case _FragmentTimedOut():
          throw RelayConnectException(
            RelayConnectFailure.frameReassemblyFailed,
            'reassembling $what timed out: no fragment arrived within 10 seconds '
            'of the previous one (R-11-238)',
          );
        case _FragmentReceived(:final current):
          if (current is! List<int>) {
            throw RelayConnectException(
              RelayConnectFailure.webSocketFailed,
              'expected a binary frame for $what, got: $current',
            );
          }
          ciphertext = Uint8List.fromList(current);
      }
      final outcome = await decodeFragment(
        reassembler,
        session.receive,
        ciphertext,
        now: _now,
      );
      if (outcome case Err(:final cause)) {
        throw RelayConnectException(
          RelayConnectFailure.frameReassemblyFailed,
          'reassembling $what failed: $cause',
        );
      }
      final envelopeBytes = (outcome as Ok<Uint8List?>).value;
      if (envelopeBytes == null) {
        continue;
      }
      return Frame.fromJson(
        jsonDecode(utf8.decode(envelopeBytes)) as Map<String, dynamic>,
      );
    }
  }
}

Future<String> _expectText(
  StreamIterator<dynamic> iterator,
  String what,
) async {
  if (!await iterator.moveNext()) {
    throw RelayConnectException(
      RelayConnectFailure.webSocketFailed,
      'the relay closed the connection before sending $what',
    );
  }
  final current = iterator.current;
  if (current is! String) {
    throw RelayConnectException(
      RelayConnectFailure.webSocketFailed,
      'expected a text frame for $what, got: $current',
    );
  }
  return current;
}

Future<Uint8List> _expectBinary(
  StreamIterator<dynamic> iterator,
  String what,
) async {
  if (!await iterator.moveNext()) {
    throw RelayConnectException(
      RelayConnectFailure.webSocketFailed,
      'the relay closed the connection before sending $what',
    );
  }
  final current = iterator.current;
  if (current is! List<int>) {
    throw RelayConnectException(
      RelayConnectFailure.webSocketFailed,
      'expected a binary frame for $what, got: $current',
    );
  }
  return Uint8List.fromList(current);
}

/// The outcome of racing [iterator]'s next event against [reassembler]'s own R-11-238
/// inter-fragment deadline. Never constructed outside [_awaitNextFragment].
sealed class _FragmentWait {
  const _FragmentWait();
}

/// [iterator] produced its next event; [current] is `iterator.current` at that point.
final class _FragmentReceived extends _FragmentWait {
  const _FragmentReceived(this.current);
  final dynamic current;
}

/// [iterator]'s stream ended before a next event arrived.
final class _StreamClosed extends _FragmentWait {
  const _StreamClosed();
}

/// [reassembler] held a partial record whose R-11-238 deadline elapsed before [iterator]
/// produced a next event.
final class _FragmentTimedOut extends _FragmentWait {
  const _FragmentTimedOut();
}

/// R-11-238: while [reassembler] holds a partial record, races [iterator]'s next event
/// against that record's own inter-fragment deadline with a real [Timer] — one that fires
/// even when the peer never sends another byte at all, not just a check that only runs
/// reactively when a next fragment happens to arrive ([Reassembler.acceptFragment]'s own
/// check, which [decodeFragment] still performs as a second line of defence). A connection
/// idling between complete, separate application messages never times out this way: the
/// race only happens while [Reassembler.hasPartial] is true. [now] lets a test inject a
/// fake clock instead of sleeping through the real 10-second window.
Future<_FragmentWait> _awaitNextFragment(
  StreamIterator<dynamic> iterator,
  Reassembler reassembler,
  DateTime Function() now,
) async {
  final deadline = reassembler.partialDeadline;
  if (deadline == null) {
    return await iterator.moveNext()
        ? _FragmentReceived(iterator.current)
        : const _StreamClosed();
  }
  final remaining = deadline.difference(now());
  if (remaining <= Duration.zero) {
    return const _FragmentTimedOut();
  }
  final outcome = Completer<_FragmentWait>();
  final timer = Timer(remaining, () {
    if (!outcome.isCompleted) {
      outcome.complete(const _FragmentTimedOut());
    }
  });
  unawaited(
    iterator.moveNext().then((hasNext) {
      if (!outcome.isCompleted) {
        outcome.complete(
          hasNext ? _FragmentReceived(iterator.current) : const _StreamClosed(),
        );
      }
    }),
  );
  final result = await outcome.future;
  timer.cancel();
  return result;
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
