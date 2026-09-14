/// Tests `device_list.dart` (`WP-20-a`): matching a reply by type, racing it against a
/// connection drop (R-30-518, R-31-14-12), and the relative-time formatters
/// `docs/31-mockups/14-devices.md`'s row and sheet both use.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart';
import 'package:herdr_mobile/models/codes.dart';
import 'package:herdr_mobile/models/message.dart';
import 'package:herdr_mobile/models/messages/device_list.dart';
import 'package:herdr_mobile/models/messages/device_list_entry.dart';
import 'package:herdr_mobile/models/messages/error_message.dart';
import 'package:herdr_mobile/models/messages/platform.dart' as wire;
import 'package:herdr_mobile/models/messages/revoke_result.dart';
import 'package:herdr_mobile/services/device_list.dart';
import 'package:herdr_mobile/services/relay.dart';

DeviceListEntry _sampleEntry({
  String id = 'device-1',
  String name = 'Pixel 8',
}) => DeviceListEntry(
  id: id,
  name: name,
  pairedAt: '2026-08-24T09:14:00Z',
  lastSeen: '2026-08-27T00:00:00Z',
  connected: true,
  platform: wire.Platform.android,
  fingerprint: '3f9a-1c04-be77-20d5',
);

void main() {
  group('fetchDeviceList', () {
    test('sends device_list_request and resolves Ok on device_list', () async {
      final messages = StreamController<Message>.broadcast();
      final connectionState =
          StreamController<RelayConnectionState>.broadcast();
      final sent = <Message>[];

      final future = fetchDeviceList(
        messages: messages.stream,
        connectionState: connectionState.stream,
        send: (message, {corr}) => sent.add(message),
      );
      await Future<void>.delayed(Duration.zero);
      expect(sent, hasLength(1));
      expect(sent.single, isA<MessageDeviceListRequest>());

      final entry = _sampleEntry();
      messages.add(Message.deviceList(DeviceList(devices: [entry])));

      final result = await future;
      expect(result, isA<Ok<List<DeviceListEntry>>>());
      expect((result as Ok<List<DeviceListEntry>>).value, [entry]);

      await messages.close();
      await connectionState.close();
    });

    test('resolves Err on an error reply', () async {
      final messages = StreamController<Message>.broadcast();
      final connectionState =
          StreamController<RelayConnectionState>.broadcast();

      final future = fetchDeviceList(
        messages: messages.stream,
        connectionState: connectionState.stream,
        send: (message, {corr}) {},
      );
      messages.add(
        const Message.error(
          ErrorMessage(
            code: ErrorCode.internalError,
            message: 'boom',
            fatal: false,
          ),
        ),
      );

      final result = await future;
      expect(result, isA<Err<List<DeviceListEntry>>>());
      expect((result as Err<List<DeviceListEntry>>).message, 'boom');

      await messages.close();
      await connectionState.close();
    });

    test(
      'resolves Err when the connection drops before a reply arrives',
      () async {
        final messages = StreamController<Message>.broadcast();
        final connectionState =
            StreamController<RelayConnectionState>.broadcast();

        final future = fetchDeviceList(
          messages: messages.stream,
          connectionState: connectionState.stream,
          send: (message, {corr}) {},
        );
        connectionState.add(const RelayDisconnected());

        final result = await future;
        expect(result, isA<Err<List<DeviceListEntry>>>());

        await messages.close();
        await connectionState.close();
      },
    );

    // R-31-14-14: a Host that never answers MUST NOT hold the read open. `testWidgets` runs
    // under a fake clock, so `tester.pump` elapses the timeout without a real 5 s wait.
    testWidgets(
      'resolves Err with the no-reply text when device_list never arrives',
      (WidgetTester tester) async {
        final messages = StreamController<Message>.broadcast();
        final connectionState =
            StreamController<RelayConnectionState>.broadcast();
        final sent = <Message>[];

        final future = fetchDeviceList(
          messages: messages.stream,
          connectionState: connectionState.stream,
          send: (message, {corr}) => sent.add(message),
        );
        await tester.pump(deviceListReplyTimeout - const Duration(seconds: 1));
        expect(
          messages.hasListener,
          isTrue,
          reason: 'still waiting one second before the timeout',
        );
        await tester.pump(const Duration(seconds: 1));

        final result = await future;
        expect(result, isA<Err<List<DeviceListEntry>>>());
        expect(
          (result as Err<List<DeviceListEntry>>).message,
          deviceListNoReplyText,
        );
        expect(sent, hasLength(1), reason: 'a timeout never resends');
        expect(
          messages.hasListener,
          isFalse,
          reason: 'the reply listener is released after the timeout',
        );

        await messages.close();
        await connectionState.close();
      },
    );

    test(
      'ignores an unrelated message and a benign connectionState no-op',
      () async {
        final messages = StreamController<Message>.broadcast();
        final connectionState =
            StreamController<RelayConnectionState>.broadcast();

        final future = fetchDeviceList(
          messages: messages.stream,
          connectionState: connectionState.stream,
          send: (message, {corr}) {},
        );
        // Reasserting the already-connected state MUST NOT finish the race.
        connectionState.add(const RelayConnected());
        final entry = _sampleEntry();
        messages.add(Message.deviceList(DeviceList(devices: [entry])));

        final result = await future;
        expect(result, isA<Ok<List<DeviceListEntry>>>());

        await messages.close();
        await connectionState.close();
      },
    );
  });

  group('revokeDevice / revokeAllDevices', () {
    test(
      'sends device_id and resolves RevokeSucceeded on revoke_result',
      () async {
        final messages = StreamController<Message>.broadcast();
        final connectionState =
            StreamController<RelayConnectionState>.broadcast();
        final sent = <Message>[];

        final future = revokeDevice(
          messages: messages.stream,
          connectionState: connectionState.stream,
          send: (message, {corr}) => sent.add(message),
          deviceId: 'device-2',
        );
        await Future<void>.delayed(Duration.zero);
        final request = sent.single as MessageRevokeDevice;
        expect(request.payload.deviceId, 'device-2');
        expect(request.payload.all, isNull);

        messages.add(
          const Message.revokeResult(
            RevokeResult(revoked: ['device-2'], all: false),
          ),
        );

        final outcome = await future;
        expect(outcome, isA<RevokeSucceeded>());
        expect((outcome as RevokeSucceeded).revokedIds, ['device-2']);
        expect(outcome.all, isFalse);

        await messages.close();
        await connectionState.close();
      },
    );

    test('revokeAllDevices sends all: true', () async {
      final messages = StreamController<Message>.broadcast();
      final connectionState =
          StreamController<RelayConnectionState>.broadcast();
      final sent = <Message>[];

      final future = revokeAllDevices(
        messages: messages.stream,
        connectionState: connectionState.stream,
        send: (message, {corr}) => sent.add(message),
      );
      await Future<void>.delayed(Duration.zero);
      final request = sent.single as MessageRevokeDevice;
      expect(request.payload.all, isTrue);
      expect(request.payload.deviceId, isNull);

      messages.add(
        const Message.revokeResult(
          RevokeResult(revoked: ['device-1', 'device-2'], all: true),
        ),
      );
      final outcome = await future;
      expect(outcome, isA<RevokeSucceeded>());
      expect((outcome as RevokeSucceeded).all, isTrue);

      await messages.close();
      await connectionState.close();
    });

    test(
      'resolves RevokeRefused on an error reply, safe to retry at once',
      () async {
        final messages = StreamController<Message>.broadcast();
        final connectionState =
            StreamController<RelayConnectionState>.broadcast();

        final future = revokeDevice(
          messages: messages.stream,
          connectionState: connectionState.stream,
          send: (message, {corr}) {},
          deviceId: 'device-2',
        );
        messages.add(
          const Message.error(
            ErrorMessage(
              code: ErrorCode.internalError,
              message: 'refused',
              fatal: false,
            ),
          ),
        );
        final outcome = await future;
        expect(outcome, isA<RevokeRefused>());
        expect((outcome as RevokeRefused).message, 'refused');

        await messages.close();
        await connectionState.close();
      },
    );

    test(
      'resolves RevokeOutcomeUnknown when the link drops before revoke_result, '
      'and never resends revoke_device',
      () async {
        final messages = StreamController<Message>.broadcast();
        final connectionState =
            StreamController<RelayConnectionState>.broadcast();
        final sent = <Message>[];

        final future = revokeDevice(
          messages: messages.stream,
          connectionState: connectionState.stream,
          send: (message, {corr}) => sent.add(message),
          deviceId: 'device-2',
        );
        connectionState.add(const RelayReconnecting(Duration(seconds: 1)));

        final outcome = await future;
        expect(outcome, isA<RevokeOutcomeUnknown>());
        expect(
          sent,
          hasLength(1),
          reason: 'never resend revoke_device (R-31-14-12.2)',
        );

        await messages.close();
        await connectionState.close();
      },
    );

    // R-31-14-12 and R-31-14-14: a revoke that is never acknowledged is the same unknown
    // outcome as a dropped link, and it is never resent.
    testWidgets(
      'resolves RevokeOutcomeUnknown when revoke_result never arrives',
      (WidgetTester tester) async {
        final messages = StreamController<Message>.broadcast();
        final connectionState =
            StreamController<RelayConnectionState>.broadcast();
        final sent = <Message>[];

        final future = revokeDevice(
          messages: messages.stream,
          connectionState: connectionState.stream,
          send: (message, {corr}) => sent.add(message),
          deviceId: 'device-2',
        );
        await tester.pump(deviceListReplyTimeout);

        final outcome = await future;
        expect(outcome, isA<RevokeOutcomeUnknown>());
        expect(sent, hasLength(1), reason: 'never resend revoke_device');

        await messages.close();
        await connectionState.close();
      },
    );
  });

  group('relative-time formatters', () {
    final DateTime now = DateTime(2026, 8, 27, 12, 0, 0);

    test('formatLastSeen: now inside 30 seconds', () {
      expect(
        formatLastSeen(now.subtract(const Duration(seconds: 10)), now: now),
        'now',
      );
    });

    test('formatLastSeen: minutes, hours, days', () {
      expect(
        formatLastSeen(now.subtract(const Duration(minutes: 3)), now: now),
        '3m ago',
      );
      expect(
        formatLastSeen(now.subtract(const Duration(hours: 2)), now: now),
        '2h ago',
      );
      expect(
        formatLastSeen(now.subtract(const Duration(days: 21)), now: now),
        '21d ago',
      );
    });

    test('formatPairedShort and formatPairedFull', () {
      final DateTime paired = DateTime(2026, 8, 24, 9, 14);
      expect(formatPairedShort(paired), '24 Aug 09:14');
      expect(formatPairedFull(paired), '24 Aug 2026 09:14');
    });
  });
}
