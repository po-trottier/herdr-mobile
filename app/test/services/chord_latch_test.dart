/// Independent modifier states and native Shift timing (R-03-120, R-03-122).
/// A quick second tap locks; a later second tap releases the held modifier.
/// A key or timeout releases held modifiers only (R-31-09-19). A lifecycle exit
/// clears every modifier. Tests inject the tap clock and use a short real timeout.
library;

import 'dart:async' show StreamSubscription;

import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/services/chord_latch.dart';

const Duration _short = Duration(milliseconds: 20);
const Duration _pastShort = Duration(milliseconds: 60);

const Duration _lockWindow = Duration(milliseconds: 300);

void main() {
  late DateTime now;
  setUp(() => now = DateTime(2026, 9, 10));
  test('a fresh latch has nothing latched', () {
    final ChordLatch latch = ChordLatch(
      lockWindow: _lockWindow,
      now: () => now,
    );
    expect(latch.latched, isEmpty);
    expect(latch.stateOf(ChordModifier.ctrl), ChordLatchState.none);
    expect(latch.stateOf(ChordModifier.alt), ChordLatchState.none);
    latch.dispose();
  });

  test('one tap is one-shot: one key clears it', () {
    final ChordLatch latch = ChordLatch(
      lockWindow: _lockWindow,
      now: () => now,
    );
    latch.toggle(ChordModifier.ctrl);
    expect(latch.stateOf(ChordModifier.ctrl), ChordLatchState.held);
    expect(latch.isLatched(ChordModifier.ctrl), isTrue);
    expect(latch.isLocked(ChordModifier.ctrl), isFalse);

    latch.consume();
    expect(latch.stateOf(ChordModifier.ctrl), ChordLatchState.none);
    latch.dispose();
  });

  test('a quick second tap locks: keys and the timeout leave it; a third tap clears', () async {
    final ChordLatch latch = ChordLatch(
      lockWindow: _lockWindow,
      now: () => now,
      timeout: _short,
    );
    latch.toggle(ChordModifier.alt);
    latch.toggle(ChordModifier.alt);
    expect(latch.stateOf(ChordModifier.alt), ChordLatchState.locked);

    latch.consume();
    latch.consume();
    await Future<void>.delayed(_pastShort);
    expect(latch.stateOf(ChordModifier.alt), ChordLatchState.locked);

    latch.toggle(ChordModifier.alt);
    expect(latch.stateOf(ChordModifier.alt), ChordLatchState.none);
    expect(latch.latched, isEmpty);
    latch.dispose();
  });

  test('a one-shot latch times out', () async {
    final ChordLatch latch = ChordLatch(
      lockWindow: _lockWindow,
      now: () => now,
      timeout: _short,
    );
    latch.toggle(ChordModifier.ctrl);
    await Future<void>.delayed(_pastShort);
    expect(latch.latched, isEmpty);
    latch.dispose();
  });

  test('a lifecycle clear releases a locked modifier too', () {
    final ChordLatch latch = ChordLatch(
      lockWindow: _lockWindow,
      now: () => now,
    );
    latch.toggle(ChordModifier.ctrl);
    latch.toggle(ChordModifier.ctrl);
    expect(latch.isLocked(ChordModifier.ctrl), isTrue);

    latch.clear();
    expect(latch.latched, isEmpty);
    latch.dispose();
  });

  group('ChordLatch latches ctrl and alt together (R-03-120)', () {
    test('a tap on the other modifier adds it and never replaces it', () {
      final ChordLatch latch = ChordLatch(
        lockWindow: _lockWindow,
        now: () => now,
      );
      latch.toggle(ChordModifier.ctrl);
      latch.toggle(ChordModifier.alt);

      expect(latch.stateOf(ChordModifier.ctrl), ChordLatchState.held);
      expect(latch.stateOf(ChordModifier.alt), ChordLatchState.held);
      latch.dispose();
    });

    test('a tap on the other modifier leaves a lock alone', () {
      final ChordLatch latch = ChordLatch(
        lockWindow: _lockWindow,
        now: () => now,
      );
      latch.toggle(ChordModifier.ctrl);
      latch.toggle(ChordModifier.ctrl);
      latch.toggle(ChordModifier.alt);

      expect(latch.stateOf(ChordModifier.ctrl), ChordLatchState.locked);
      expect(latch.stateOf(ChordModifier.alt), ChordLatchState.held);
      latch.dispose();
    });

    test('latched reports every latched modifier in the ctrl, alt order a chord joins '
        'them (R-10-038)', () {
      final ChordLatch latch = ChordLatch(
        lockWindow: _lockWindow,
        now: () => now,
      );
      // Latched in the other order: the list is the chord's order, not the tap order.
      latch.toggle(ChordModifier.alt);
      latch.toggle(ChordModifier.ctrl);

      expect(latch.latched, <ChordModifier>[
        ChordModifier.ctrl,
        ChordModifier.alt,
      ]);
      latch.dispose();
    });

    test('one key releases the held modifiers and keeps the locked ones', () {
      final ChordLatch latch = ChordLatch(
        lockWindow: _lockWindow,
        now: () => now,
      );
      latch.toggle(ChordModifier.ctrl);
      latch.toggle(ChordModifier.ctrl); // locked
      latch.toggle(ChordModifier.alt); // held

      latch.consume();
      // The `ctrl+alt+x` then `ctrl+y` sequence of R-03-120.
      expect(latch.latched, <ChordModifier>[ChordModifier.ctrl]);
      expect(latch.stateOf(ChordModifier.alt), ChordLatchState.none);

      latch.consume();
      expect(latch.latched, <ChordModifier>[ChordModifier.ctrl]);
      latch.dispose();
    });

    test('a third tap releases that modifier alone', () {
      final ChordLatch latch = ChordLatch(
        lockWindow: _lockWindow,
        now: () => now,
      );
      latch.toggle(ChordModifier.ctrl);
      latch.toggle(ChordModifier.ctrl); // ctrl locked
      latch.toggle(ChordModifier.alt);
      latch.toggle(ChordModifier.alt); // alt locked

      latch.toggle(ChordModifier.ctrl); // the third tap of ctrl
      expect(latch.stateOf(ChordModifier.ctrl), ChordLatchState.none);
      expect(latch.stateOf(ChordModifier.alt), ChordLatchState.locked);
      latch.dispose();
    });

    test(
      'the timeout releases every held modifier and leaves a locked one',
      () async {
        final ChordLatch latch = ChordLatch(
          lockWindow: _lockWindow,
          now: () => now,
          timeout: _short,
        );
        latch.toggle(ChordModifier.ctrl);
        latch.toggle(
          ChordModifier.ctrl,
        ); // locked: the timeout never touches it
        latch.toggle(ChordModifier.alt); // held

        await Future<void>.delayed(_pastShort);
        expect(latch.stateOf(ChordModifier.alt), ChordLatchState.none);
        expect(latch.stateOf(ChordModifier.ctrl), ChordLatchState.locked);
        latch.dispose();
      },
    );

    test('each latch restarts the one shared deadline, so the second modifier gets its '
        'own full timeout', () async {
      final ChordLatch latch = ChordLatch(
        lockWindow: _lockWindow,
        now: () => now,
        timeout: _short,
      );
      latch.toggle(ChordModifier.ctrl);
      // Two thirds of the way through `ctrl`'s deadline, `alt` latches and restarts it.
      await Future<void>.delayed(
        Duration(milliseconds: _short.inMilliseconds * 2 ~/ 3),
      );
      latch.toggle(ChordModifier.alt);
      await Future<void>.delayed(
        Duration(milliseconds: _short.inMilliseconds * 2 ~/ 3),
      );

      // Past `ctrl`'s original deadline, both are still held: one deadline serves the group.
      expect(latch.latched, <ChordModifier>[
        ChordModifier.ctrl,
        ChordModifier.alt,
      ]);

      await Future<void>.delayed(_pastShort);
      expect(latch.latched, isEmpty);
      latch.dispose();
    });

    test('changes fires on every transition, so a listener re-reads the whole group', () async {
      final ChordLatch latch = ChordLatch(
        lockWindow: _lockWindow,
        now: () => now,
      );
      int events = 0;
      final StreamSubscription<void> sub = latch.changes.listen(
        (_) => events++,
      );

      latch.toggle(ChordModifier.ctrl);
      latch.toggle(ChordModifier.alt);
      latch.consume();
      await Future<void>.delayed(Duration.zero);

      expect(events, 3);
      await sub.cancel();
      latch.dispose();
    });
  });

  group('native Shift transitions (R-03-122)', () {
    for (final ChordModifier modifier in ChordModifier.values) {
      final ChordModifier other = modifier == ChordModifier.ctrl
          ? ChordModifier.alt
          : ChordModifier.ctrl;
      test(
        'slow second tap releases ${modifier.name} without changing the other modifier',
        () {
          final ChordLatch latch = ChordLatch(
            lockWindow: _lockWindow,
            now: () => now,
          );
          addTearDown(latch.dispose);
          latch.toggle(other);
          latch.toggle(modifier);
          expect(latch.stateOf(other), ChordLatchState.held);
          now = now.add(const Duration(milliseconds: 301));
          latch.toggle(modifier);
          expect(latch.stateOf(modifier), ChordLatchState.none);
          expect(latch.stateOf(other), ChordLatchState.held);
          latch.consume();
          expect(latch.latched, isEmpty);
        },
      );
      test(
        'quick second tap locks ${modifier.name} and the next tap releases only it',
        () {
          final ChordLatch latch = ChordLatch(
            lockWindow: _lockWindow,
            now: () => now,
          );
          addTearDown(latch.dispose);
          latch.toggle(other);
          latch.toggle(modifier);
          now = now.add(_lockWindow);
          latch.toggle(modifier);
          expect(latch.stateOf(modifier), ChordLatchState.locked);
          expect(latch.stateOf(other), ChordLatchState.held);
          latch.toggle(modifier);
          expect(latch.stateOf(modifier), ChordLatchState.none);
          expect(latch.stateOf(other), ChordLatchState.held);
        },
      );
      for (final String release in <String>['consume', 'timeout', 'clear']) {
        test(
          '$release starts a fresh hold window for ${modifier.name}',
          () async {
            final ChordLatch latch = ChordLatch(
              lockWindow: _lockWindow,
              now: () => now,
              timeout: _short,
            );
            addTearDown(latch.dispose);
            latch.toggle(other);
            latch.toggle(other);
            latch.toggle(modifier);
            now = now.add(const Duration(milliseconds: 100));
            switch (release) {
              case 'consume':
                latch.consume();
              case 'timeout':
                await Future<void>.delayed(_pastShort);
              case 'clear':
                latch.clear();
            }
            expect(latch.stateOf(modifier), ChordLatchState.none);
            latch.toggle(modifier);
            expect(latch.stateOf(modifier), ChordLatchState.held);
            expect(
              latch.stateOf(other),
              release == 'clear'
                  ? ChordLatchState.none
                  : ChordLatchState.locked,
            );
            now = now.add(const Duration(milliseconds: 250));
            latch.toggle(modifier);
            expect(latch.stateOf(modifier), ChordLatchState.locked);
          },
        );
      }
    }
  });
}
