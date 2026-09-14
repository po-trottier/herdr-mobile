/// Watches for a network change and tells `relay.dart` (`WP-14-a`) when to attempt a
/// reconnect, per `docs/22-platform-integration.md` R-22-027: detect the change, wait 1
/// second for the new network to stabilise, then signal one reconnect attempt.
///
/// This file owns only the debounced signal. The actual reconnect — opening a new
/// WebSocket, running `Noise_KK`, and resuming with `tree_request` and `watch_pane` — is
/// `relay.dart`'s job (R-22-028, R-11-084, R-11-200); [ConnectivityWatcher] never touches
/// the network itself beyond subscribing to `connectivity_plus`'s own change stream.
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Subscribes to `connectivity_plus`'s connectivity-change stream and republishes it as one
/// debounced signal on [onNetworkStable], per R-22-027's 1-second debounce. A rapid run of
/// changes (for example a phone moving in and out of WiFi range) collapses into a single
/// signal once the network settles.
final class ConnectivityWatcher {
  ConnectivityWatcher({
    Connectivity? connectivity,
    Duration debounce = const Duration(seconds: 1),
  }) : _connectivity = connectivity ?? Connectivity(),
       // `this._debounce` would make the external parameter name `_debounce`, unusable
       // from a different library, per Dart's named-parameter privacy rule (same
       // reasoning as `biometric_gate.dart`'s `_now` constructor param).
       // ignore: prefer_initializing_formals
       _debounce = debounce;

  final Connectivity _connectivity;
  final Duration _debounce;

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _debounceTimer;
  final StreamController<void> _controller = StreamController<void>.broadcast();

  /// Fires once, after [_debounce] of no further connectivity change, every time the
  /// underlying network changes (R-22-027 step 1 and 2). Carries no payload: the listener
  /// (`relay.dart`) re-reads whatever state it needs and attempts a reconnect (R-22-027 step
  /// 3).
  Stream<void> get onNetworkStable => _controller.stream;

  /// Starts watching. MUST be called before [onNetworkStable] emits anything, and MUST be
  /// paired with [dispose].
  void start() {
    _subscription = _connectivity.onConnectivityChanged.listen(_onChange);
  }

  void _onChange(List<ConnectivityResult> results) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () {
      if (!_controller.isClosed) {
        _controller.add(null);
      }
    });
  }

  /// Releases the platform subscription and the debounce timer (R-41-100).
  Future<void> dispose() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _controller.close();
  }
}
