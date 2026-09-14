/// The paired-Device list service (Phase 20, `WP-20-a`), driven from
/// `docs/31-mockups/14-devices.md` and `docs/11-relay-protocol.md` §4.18-4.21:
/// `device_list_request`/`device_list` (R-11-062) to read the Host's paired-phone list, and
/// `revoke_device`/`revoke_result` (R-11-063, R-11-064) to revoke one Device or every Device.
///
/// Every function here takes a `Stream<Message>`, a `Stream<RelayConnectionState>` and a
/// [SendFrame] rather than a whole `RelayConnection`, on purpose: `RelayConnection` opens a
/// real WebSocket internally with no injectable fake short of the full local-server harness
/// `app/test/services/single_socket_test.dart` already built for `relay.dart`'s own transport
/// tests. This file's own logic — matching a reply by type, racing it against a connection
/// drop and against [deviceListReplyTimeout], never resending `revoke_device` — has nothing to
/// do with that transport and is fully exercised against plain `StreamController`s in
/// `app/test/services/device_list_test.dart`.
/// `device_list_screen.dart` is the one caller, and passes `connection.messages`,
/// `connection.connectionState` and `connection.send` straight through.
///
/// This file owns no screen: `device_list_screen.dart` and `device_detail_screen.dart` paint
/// every state this file raises (R-90-024).
library;

import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart' show DeviceInfoPlugin;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;

import '../core/result/result.dart' show Err, Ok, Result;
import '../models/message.dart';
import '../models/messages/device_list_entry.dart';
import '../models/messages/device_list_request.dart';
import '../models/messages/revoke_device.dart';
import 'relay.dart' show RelayConnected, RelayConnectionState;

/// The function shape `RelayConnection.send` already has; accepted here instead of the whole
/// connection object (see this file's own header comment).
typedef SendFrame = void Function(Message message, {String? corr});

/// One outcome of a `revoke_device` request (`docs/30-ux-spec.md` R-30-518): the Host applied
/// it, the Host refused it, or the acknowledgement never arrived. `Result<T>`'s plain Ok/Err
/// cannot express the third case, which is why this is its own three-variant type rather than
/// a `Result<RevokeResult>`.
sealed class RevokeOutcome {
  const RevokeOutcome();
}

/// The Host applied the revoke (R-11-064). [revokedIds] are every device UUIDv4 it removed;
/// [all] is `true` for a `Remove every phone` revoke (R-13-056).
final class RevokeSucceeded extends RevokeOutcome {
  const RevokeSucceeded({required this.revokedIds, required this.all});
  final List<String> revokedIds;
  final bool all;
}

/// The Host refused the revoke. [message] is its raw `error` text (R-30-803). Nothing was
/// removed, so the outcome is known and a further attempt is safe at once (R-31-14-12.6).
final class RevokeRefused extends RevokeOutcome {
  const RevokeRefused(this.message);
  final String message;
}

/// The link dropped before `revoke_result` arrived (R-31-14-12, R-30-518). This is not an
/// error: the Host may have applied the revoke anyway. The caller MUST NOT resend
/// `revoke_device` and MUST reconcile with a fresh [fetchDeviceList] instead (R-31-14-12.2).
final class RevokeOutcomeUnknown extends RevokeOutcome {
  const RevokeOutcomeUnknown();
}

int _corrSeq = 0;

/// A correlation id for one outgoing request (R-11-034: "MUST be present on every request").
/// This client cannot read `corr` back off an incoming reply — `relay.dart`'s `messages`
/// stream publishes the decoded [Message] only, stripping the frame envelope — so every
/// function below matches a reply by its message type instead, which is safe under
/// R-31-14-12.1's own rule that only one revoke is ever in flight at a time.
String _nextCorr() => 'device-list-${_corrSeq++}';

/// How long [fetchDeviceList] and the two revoke calls wait for their reply before they give
/// up, matching `terminal.dart`'s own `terminalReplyTimeout` shape (R-31-14-14). A Host that
/// never answers `device_list_request` used to hold the devices screen in its `Loading`
/// skeleton forever (found live, 2026-09-03); a silent revoke is the `Outcome unknown` case
/// of R-30-518 either way.
const Duration deviceListReplyTimeout = Duration(seconds: 5);

/// The raw text the `Error, no reply` state of `docs/31-mockups/14-devices.md` shows.
const String deviceListNoReplyText =
    'read the paired-device list: no device_list reply after 5 s';

/// Races [messages] for the first message [onMessage] accepts against [connectionState] for a
/// transition off [RelayConnected] — the "link dropped before the reply arrived" half of
/// R-30-518's three-outcome model — and against [deviceListReplyTimeout]. Returns `null` on
/// a drop and [onTimeout] when nothing arrived in time.
///
/// Cancels both subscriptions once [completer] settles, but does not await either cancellation:
/// awaiting `StreamSubscription.cancel()` from inside the async continuation of that same
/// subscription's own delivered event never resumes under `flutter_test`'s widget-pump cycle
/// (reproduced in isolation against a plain `StreamController`, independent of every other
/// part of this file). Neither controller this file is ever given owns an `onCancel`
/// callback, so a fire-and-forget cancel still runs to completion; nothing here needs to wait
/// for it.
Future<T?> _awaitReply<T>({
  required Stream<Message> messages,
  required Stream<RelayConnectionState> connectionState,
  required T? Function(Message) onMessage,
  required T onTimeout,
}) async {
  final Completer<T?> completer = Completer<T?>();
  void finish(T? value) {
    if (!completer.isCompleted) completer.complete(value);
  }

  final StreamSubscription<Message> messageSub = messages.listen((message) {
    final T? result = onMessage(message);
    if (result != null) finish(result);
  });
  final StreamSubscription<RelayConnectionState> stateSub = connectionState
      .listen((state) {
        if (state is! RelayConnected) finish(null);
      });
  try {
    return await completer.future.timeout(
      deviceListReplyTimeout,
      onTimeout: () => onTimeout,
    );
  } finally {
    unawaited(messageSub.cancel());
    unawaited(stateSub.cancel());
  }
}

/// Requests the paired-device list (`device_list_request`, R-11-062) and awaits `device_list`.
/// `Err` covers an `error` reply, a dropped link and a reply that never came within
/// [deviceListReplyTimeout]. R-30-518 exempts a read from the no-retry rule, but only a
/// person's own `Try again`/`Check now` press triggers the next one; this function itself does
/// not loop.
Future<Result<List<DeviceListEntry>>> fetchDeviceList({
  required Stream<Message> messages,
  required Stream<RelayConnectionState> connectionState,
  required SendFrame send,
}) async {
  send(const Message.deviceListRequest(DeviceListRequest()), corr: _nextCorr());
  final Result<List<DeviceListEntry>>? reply =
      await _awaitReply<Result<List<DeviceListEntry>>>(
        messages: messages,
        connectionState: connectionState,
        onMessage: (message) => switch (message) {
          MessageDeviceList(:final payload) => Ok(payload.devices),
          MessageError(:final payload) => Err(payload.message),
          _ => null,
        },
        onTimeout: const Err(deviceListNoReplyText),
      );
  return reply ??
      const Err('read the paired-device list: the connection dropped');
}

/// Revokes one Device (`revoke_device` with `device_id`, R-11-063).
Future<RevokeOutcome> revokeDevice({
  required Stream<Message> messages,
  required Stream<RelayConnectionState> connectionState,
  required SendFrame send,
  required String deviceId,
}) => _revoke(
  messages: messages,
  connectionState: connectionState,
  send: send,
  request: RevokeDevice(deviceId: deviceId),
);

/// Revokes every Device (`revoke_device` with `all: true`, R-11-063, R-13-056).
Future<RevokeOutcome> revokeAllDevices({
  required Stream<Message> messages,
  required Stream<RelayConnectionState> connectionState,
  required SendFrame send,
}) => _revoke(
  messages: messages,
  connectionState: connectionState,
  send: send,
  request: const RevokeDevice(all: true),
);

Future<RevokeOutcome> _revoke({
  required Stream<Message> messages,
  required Stream<RelayConnectionState> connectionState,
  required SendFrame send,
  required RevokeDevice request,
}) async {
  send(Message.revokeDevice(request), corr: _nextCorr());
  final RevokeOutcome? outcome = await _awaitReply<RevokeOutcome>(
    messages: messages,
    connectionState: connectionState,
    onMessage: (message) => switch (message) {
      MessageRevokeResult(:final payload) => RevokeSucceeded(
        revokedIds: payload.revoked,
        all: payload.all,
      ),
      MessageError(:final payload) => RevokeRefused(payload.message),
      _ => null,
    },
    onTimeout: const RevokeOutcomeUnknown(),
  );
  return outcome ?? const RevokeOutcomeUnknown();
}

/// The default Device name (R-31-14-05): the platform device model (`Pixel 8`, `iPhone 15`),
/// read from `device_info_plus` 13.2.0, declared in `app/pubspec.yaml`
/// (`docs/20-mobile-framework.md`). Mirrors `qr_scan_screen.dart`'s own private
/// `_buildDeviceInfo` helper (`WP-15-b`); factored here, public, as the one canonical reader
/// once a second caller needs it (R-90-018). Returns the raw model string; a caller building
/// the `device_info` wire message truncates to 32 UTF-8 bytes itself (R-11-226), since only
/// that message's own limit applies here.
Future<String> defaultDeviceName() async {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    final iosInfo = await DeviceInfoPlugin().iosInfo;
    return iosInfo.modelName;
  }
  final androidInfo = await DeviceInfoPlugin().androidInfo;
  return androidInfo.model;
}

/// Parses a `paired_at`/`last_seen` RFC 3339 UTC string (R-11-062) into the phone's local time
/// zone for display.
DateTime parseWireTimestamp(String iso) => DateTime.parse(iso).toLocal();

const List<String> _monthAbbreviations = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _twoDigits(int value) => value.toString().padLeft(2, '0');

/// `24 Aug 09:14`, the paired-device row's pair-time format
/// (`docs/31-mockups/14-devices.md`).
String formatPairedShort(DateTime local) =>
    '${_twoDigits(local.day)} ${_monthAbbreviations[local.month - 1]} '
    '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';

/// `24 Aug 2026 09:14`, the device detail sheet's full pair-time format
/// (`docs/31-mockups/14-devices.md`).
String formatPairedFull(DateTime local) =>
    '${_twoDigits(local.day)} ${_monthAbbreviations[local.month - 1]} '
    '${local.year} ${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';

/// `now` inside the last 30 seconds (callout 4 of `docs/31-mockups/14-devices.md`), else
/// `<n>m ago`, `<n>h ago` or `<n>d ago`, rounding down. [now] lets a test fix the clock.
String formatLastSeen(DateTime local, {DateTime? now}) {
  final DateTime reference = now ?? DateTime.now();
  final Duration age = reference.difference(local);
  if (age.inSeconds < 30) return 'now';
  if (age.inMinutes < 60) return '${age.inMinutes}m ago';
  if (age.inHours < 24) return '${age.inHours}h ago';
  return '${age.inDays}d ago';
}
