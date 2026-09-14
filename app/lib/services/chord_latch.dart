/// The terminal key row modifier latch (R-31-09-08, R-31-09-19, R-31-09-23).
///
/// Each modifier has an independent state (R-03-120). One tap holds it for one key.
/// A quick second tap locks it; a later second tap releases it (R-03-122).
/// A tap on a locked modifier releases it. A key press or the shared 5000 ms
/// timeout releases held modifiers only. A lifecycle exit clears all modifiers.
/// This service owns no widget (R-90-024).
library;

import 'dart:async';

/// The two latchable modifiers the key row's row one carries, in the order R-10-038 requires
/// a chord to join them: `ctrl` before `alt`. The enum's own `name` is the exact word a
/// `send_input` chord and an inline key both use, so no caller maps it.
enum ChordModifier { ctrl, alt }

/// One modifier's own latch state (R-31-09-23, R-03-120).
enum ChordLatchState {
  /// Not latched: a key press sends the character itself.
  none,

  /// Latched for one key press (R-31-09-08), or until the timeout or a lifecycle exit.
  held,

  /// Latched until its own next tap or a lifecycle exit (R-31-09-23): every key press
  /// composes a chord, and neither a key press nor the timeout ends it.
  locked,
}

final class ChordLatch {
  ChordLatch({
    required this.lockWindow,
    this.timeout = const Duration(milliseconds: 5000),
    this.now = DateTime.now,
  });

  /// The native double-tap window (R-03-122, R-30-301).
  final Duration lockWindow;
  final DateTime Function() now;
  final Map<ChordModifier, DateTime> _heldAt = <ChordModifier, DateTime>{};

  /// R-31-09-19's 5000 ms exit. A test passes a short value so it does not wait out the
  /// real 5 seconds.
  final Duration timeout;

  final Map<ChordModifier, ChordLatchState> _states =
      <ChordModifier, ChordLatchState>{
        for (final ChordModifier modifier in ChordModifier.values)
          modifier: ChordLatchState.none,
      };
  Timer? _timer;
  final StreamController<void> _controller = StreamController<void>.broadcast();

  /// [modifier]'s own latch state.
  ChordLatchState stateOf(ChordModifier modifier) => _states[modifier]!;

  /// Whether [modifier] composes the next key into a chord, held or locked alike. What a cap
  /// draws its high-emphasis fill from (R-03-118).
  bool isLatched(ChordModifier modifier) =>
      stateOf(modifier) != ChordLatchState.none;

  /// Whether [modifier] is locked, so no key press and no timeout ends it (R-31-09-23).
  bool isLocked(ChordModifier modifier) =>
      stateOf(modifier) == ChordLatchState.locked;

  /// Every latched modifier, in the `ctrl` then `alt` order a chord joins them (R-10-038,
  /// R-03-120). Empty when nothing is latched.
  List<ChordModifier> get latched =>
      ChordModifier.values.where(isLatched).toList(growable: false);

  /// Fires on every latch, lock, release and clear transition. Carries no value: a listener
  /// reads [stateOf] or [latched] for the new state, because one transition may change one
  /// modifier or both.
  Stream<void> get changes => _controller.stream;

  /// Changes only this modifier (R-03-120), with native Shift timing (R-03-122).
  void toggle(ChordModifier modifier) {
    final DateTime tappedAt = now();
    _states[modifier] = switch (stateOf(modifier)) {
      ChordLatchState.none => ChordLatchState.held,
      ChordLatchState.held =>
        tappedAt.difference(_heldAt[modifier]!) <= lockWindow
            ? ChordLatchState.locked
            : ChordLatchState.none,
      ChordLatchState.locked => ChordLatchState.none,
    };
    if (stateOf(modifier) == ChordLatchState.held) {
      _heldAt[modifier] = tappedAt;
    } else {
      _heldAt.remove(modifier);
    }
    _restartTimeout();
    _controller.add(null);
  }

  /// One key composed a chord with every latched modifier (R-31-09-08). It releases the
  /// one-shot latches and keeps the locked ones, so the next key still composes with those
  /// (R-03-120). A no-op when nothing is held.
  void consume() => _releaseHeld();

  /// A lost field focus, an app backgrounding and a rotation all clear every modifier through
  /// this one method, locked ones included (R-31-09-19). A no-op when nothing is latched, so a
  /// caller may call it unconditionally from a lifecycle hook.
  void clear() {
    if (latched.isEmpty) return;
    _states.updateAll((_, _) => ChordLatchState.none);
    _heldAt.clear();
    _restartTimeout();
    _controller.add(null);
  }

  /// Releases the held modifiers and keeps the locked ones: what one key press and the 5000 ms
  /// timeout both do (R-03-120).
  void _releaseHeld() {
    if (!_states.values.contains(ChordLatchState.held)) return;
    _heldAt.clear();
    _states.updateAll(
      (_, ChordLatchState state) =>
          state == ChordLatchState.held ? ChordLatchState.none : state,
    );
    _restartTimeout();
    _controller.add(null);
  }

  /// Runs the one shared deadline while any modifier is held, and cancels it when none is:
  /// each new latch restarts it, and a locked modifier never keeps it alive.
  void _restartTimeout() {
    _timer?.cancel();
    _timer = _states.values.contains(ChordLatchState.held)
        ? Timer(timeout, _releaseHeld)
        : null;
  }

  /// Releases the pending timeout timer and closes [changes] (R-41-100).
  void dispose() {
    _timer?.cancel();
    unawaited(_controller.close());
  }
}

void unawaited(Future<void> future) {}
