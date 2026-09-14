/// Proves `ReconnectPolicy` (`app/lib/services/reconnect_policy.dart`, `WP-14-a`) hands out
/// the exact six-step R-22-028 delay sequence, resets to attempt 1 only after a
/// connection that stayed up at least 30 seconds, and keeps the cached handle on every
/// failure except a relay refusal that no repeat can fix (R-03-113 item 7).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/services/reconnect_policy.dart';
import 'package:herdr_mobile/services/relay.dart'
    show
        RelayConnectException,
        RelayConnectFailure,
        RelayRegistrationErrorCode,
        RelayRegistrationException;

void main() {
  test('the delay sequence matches R-22-028 exactly, then caps at 30 s', () {
    final policy = ReconnectPolicy();

    expect(policy.nextDelay(), const Duration(milliseconds: 500));
    expect(policy.nextDelay(), const Duration(seconds: 1));
    expect(policy.nextDelay(), const Duration(seconds: 2));
    expect(policy.nextDelay(), const Duration(seconds: 5));
    expect(policy.nextDelay(), const Duration(seconds: 10));
    expect(policy.nextDelay(), const Duration(seconds: 30));
    expect(policy.nextDelay(), const Duration(seconds: 30));
    expect(policy.nextDelay(), const Duration(seconds: 30));
  });

  test('a connection that stays up 30 seconds or more resets the schedule to attempt 1', () {
    var clock = DateTime(2026);
    final policy = ReconnectPolicy(now: () => clock);

    // Burn through a few attempts first.
    expect(policy.nextDelay(), const Duration(milliseconds: 500));
    expect(policy.nextDelay(), const Duration(seconds: 1));
    expect(policy.nextDelay(), const Duration(seconds: 2));

    policy.noteConnected();
    clock = clock.add(const Duration(seconds: 30));
    policy.noteDisconnected();

    expect(policy.nextDelay(), const Duration(milliseconds: 500));
    expect(policy.nextDelay(), const Duration(seconds: 1));
  });

  test(
    'a connection that lasts under 30 seconds does NOT reset the schedule',
    () {
      var clock = DateTime(2026);
      final policy = ReconnectPolicy(now: () => clock);

      expect(policy.nextDelay(), const Duration(milliseconds: 500));
      expect(policy.nextDelay(), const Duration(seconds: 1));

      policy.noteConnected();
      clock = clock.add(const Duration(seconds: 29));
      policy.noteDisconnected();

      // Attempt 3 continues the schedule, it does not restart at 0.5 s.
      expect(policy.nextDelay(), const Duration(seconds: 2));
    },
  );

  test(
    'a connection that never called noteConnected is never treated as stable',
    () {
      var clock = DateTime(2026);
      final policy = ReconnectPolicy(now: () => clock);

      expect(policy.nextDelay(), const Duration(milliseconds: 500));
      clock = clock.add(const Duration(minutes: 5));
      policy.noteDisconnected();

      expect(policy.nextDelay(), const Duration(seconds: 1));
    },
  );

  test('after a failure the next step reuses the cached handle, unless the relay refused the '
      'handle for good or another phone holds the Host (R-03-113 item 7, R-11-125, R-30-942)', () {
    final policy = ReconnectPolicy();

    expect(policy.afterFailure(null), ReconnectStep.reuseHandle);
    expect(
      policy.afterFailure(
        const RelayConnectException(
          RelayConnectFailure.webSocketFailed,
          'Could not open a connection to https://relay.example.com: '
          'SocketException',
        ),
      ),
      ReconnectStep.reuseHandle,
    );
    expect(
      policy.afterFailure(
        const RelayRegistrationException(
          RelayRegistrationErrorCode.handleUnknown,
          'No Host is registered under this handle',
        ),
      ),
      ReconnectStep.reuseHandle,
      reason: 'the Host re-registers the same handle on its own ladder',
    );
    for (final code in <RelayRegistrationErrorCode>[
      RelayRegistrationErrorCode.handleTaken,
      RelayRegistrationErrorCode.pairingExpired,
      RelayRegistrationErrorCode.hostInUse,
    ]) {
      expect(
        policy.afterFailure(RelayRegistrationException(code, 'x')),
        ReconnectStep.stop,
        reason: code.wireValue,
      );
    }
  });

  test('host_in_use inside 45 s of this phone\'s own drop is its stale slot and keeps the '
      'schedule; after the window it is another phone and stops (R-30-942, 2026-09-10)', () {
    var clock = DateTime(2026);
    final policy = ReconnectPolicy(now: () => clock);
    const inUse = RelayRegistrationException(
      RelayRegistrationErrorCode.hostInUse,
      'A Device is already active on this Host',
    );

    // No drop of our own yet: another phone holds the Host.
    expect(policy.afterFailure(inUse), ReconnectStep.stop);

    policy.noteConnected();
    clock = clock.add(const Duration(minutes: 1));
    policy.noteDisconnected();
    clock = clock.add(const Duration(seconds: 8));
    expect(policy.afterFailure(inUse), ReconnectStep.reuseHandle);
    clock = clock.add(const Duration(seconds: 36)); // 44 s after the drop
    expect(policy.afterFailure(inUse), ReconnectStep.reuseHandle);
    clock = clock.add(const Duration(seconds: 2)); // 46 s after the drop
    expect(policy.afterFailure(inUse), ReconnectStep.stop);
  });

  test(
    'attempts counts the delays handed out and resets with the schedule',
    () {
      var clock = DateTime(2026);
      final policy = ReconnectPolicy(now: () => clock);

      expect(policy.attempts, 0);
      policy.nextDelay();
      policy.nextDelay();
      expect(policy.attempts, 2);

      policy.noteConnected();
      clock = clock.add(const Duration(seconds: 30));
      policy.noteDisconnected();
      expect(policy.attempts, 0);
    },
  );
}
