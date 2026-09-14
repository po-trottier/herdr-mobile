/// The paired-computer list service (Phase 18, `WP-18-a`), driven from
/// `docs/31-mockups/05-host-list.md` and `docs/30-ux-spec.md` row 05 (`/hosts`): sorting the
/// list (R-31-05-01), switching the app's one live connection to a saved computer (R-03-044,
/// R-30-945, R-30-948, R-30-949) and forgetting a computer locally (R-31-05-02, R-31-05-03).
///
/// `host_list_screen.dart` is the one caller (R-90-024). It owns assembling each row from
/// `PlainStore.pairedHosts()`, the live `RelayConnection` (the connected row's own
/// `tree_snapshot`) and `AgentStatusService.currentAttention` (a whole-app-session singleton
/// this file never touches); this file owns the pure sort and the switch/forget
/// orchestration only.
library;

import 'dart:typed_data' show Uint8List;

import 'package:device_info_plus/device_info_plus.dart' show DeviceInfoPlugin;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:package_info_plus/package_info_plus.dart' show PackageInfo;

import '../core/result/result.dart' show Err, Ok, Result;
import '../models/frame.dart' show frameProtocolVersion;
import '../models/messages/device_info.dart' as messages show DeviceInfo;
import '../models/messages/platform.dart' as messages show Platform;
import 'biometric_gate.dart';
import 'keystore.dart' show HostSecrets, KeystoreService;
import 'origin.dart' show RelayOrigin, parseRelayOrigin;
import 'plain_store.dart' show PairedHostRecord, PlainStore;
import 'relay.dart';

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

/// One row's connection state, per the wireframe of `docs/31-mockups/05-host-list.md` and its
/// States table. [saved] is the ordinary rest state of every computer this phone is not using
/// (R-31-05-11); the other four are transient or terminal outcomes of a switch attempt scoped
/// to one row (R-30-947, R-30-940).
enum HostRowState {
  /// The one computer this phone is attached to (R-03-043). At most one row.
  connected,

  /// Paired, and not the connected computer (R-31-05-11). The rest state.
  saved,

  /// `R-30-948`'s single connection attempt is in flight for this row.
  switching,

  /// The attempt to reach this row failed for a reason other than `hostInUse` or `rejected`
  /// (R-30-947).
  switchFailed,

  /// `host_in_use`, close code `4006` (R-03-040, R-30-944): another phone holds this
  /// computer.
  hostInUse,

  /// The Host rejected this Device's pinned key, for example after a revoke (the `Error` row
  /// state of `docs/31-mockups/05-host-list.md`'s States table).
  rejected,
}

/// One row, already assembled by `host_list_screen.dart` from `PlainStore.pairedHosts()`,
/// the live `RelayConnection` and `AgentStatusService.currentAttention` — this file owns the
/// sort and the switch/forget orchestration, not the assembly (R-90-024).
final class HostListRow {
  const HostListRow({
    required this.record,
    required this.state,
    this.liveAgentCount,
    this.attentionCount = 0,
  });

  final PairedHostRecord record;
  final HostRowState state;

  /// `agents.length` from the last `tree_snapshot` on this row's own connection. `null`
  /// before one has arrived. Only meaningful when [state] is [HostRowState.connected];
  /// R-31-05-11 forbids a live value on any other row.
  final int? liveAgentCount;

  /// Unseen `blocked`/`done` agents for this Host (R-30-500, R-30-513) — live while
  /// connected, remembered otherwise (R-31-05-13).
  final int attentionCount;

  HostListRow copyWith({
    HostRowState? state,
    int? liveAgentCount,
    int? attentionCount,
  }) => HostListRow(
    record: record,
    state: state ?? this.state,
    liveAgentCount: liveAgentCount ?? this.liveAgentCount,
    attentionCount: attentionCount ?? this.attentionCount,
  );
}

/// R-31-05-01: attention count descending, then connection state — the rule names only
/// `connected` above every other value, including every transient one this file adds — then
/// name, case-insensitively. Returns a new list; never mutates [rows].
List<HostListRow> sortHostRows(List<HostListRow> rows) {
  final sorted = List<HostListRow>.of(rows);
  sorted.sort((a, b) {
    final byAttention = b.attentionCount.compareTo(a.attentionCount);
    if (byAttention != 0) return byAttention;
    final aConnected = a.state == HostRowState.connected;
    final bConnected = b.state == HostRowState.connected;
    if (aConnected != bConnected) return aConnected ? -1 : 1;
    return a.record.hostName.toLowerCase().compareTo(
      b.record.hostName.toLowerCase(),
    );
  });
  return sorted;
}

/// Why a switch attempt (R-30-947) did not reach [SwitchSucceeded].
enum SwitchFailureReason {
  /// The phone has no network; the app MUST NOT even attempt the switch (R-30-947).
  offline,

  /// `host_in_use`, close code `4006` (R-03-040).
  hostInUse,

  /// The relay does not know this computer's handle, or this phone has no stored key for it.
  unknownHost,

  /// The Host rejected this Device's pinned key — the `rejected` row state.
  rejected,

  /// Every other failure: the relay is unreachable, a timeout, a decode failure.
  other,
}

sealed class SwitchOutcome {
  const SwitchOutcome();
}

/// The switch reached [hostId] and it is now the one live connection (R-30-948).
final class SwitchSucceeded extends SwitchOutcome {
  const SwitchSucceeded({required this.hostId, required this.hostName});
  final String hostId;
  final String hostName;
}

/// The switch to [hostId] did not succeed. [detail] is the raw sentence a screen shows
/// verbatim (R-11-092).
final class SwitchFailed extends SwitchOutcome {
  const SwitchFailed({
    required this.hostId,
    required this.reason,
    required this.detail,
  });
  final String hostId;
  final SwitchFailureReason reason;
  final String detail;
}

/// Switches the app's one live [connection] to [target] (R-03-044, R-30-945, R-30-948).
/// Drops whatever pane [connection] was watching first, so a stale watch never resumes
/// against the wrong Host once connected (R-30-949, [RelayConnection.watchedPaneId]),
/// disconnects the current computer, then connects to [target] with [ReconnectMode] — never
/// [PairingMode], since [target] is already paired. Raises no confirmation and never
/// schedules the reconnect backoff of `R-22-028`: this is one explicit attempt.
///
/// [hasNetwork] MUST be checked by the caller before calling this at all: R-30-947 forbids
/// even attempting a switch while the phone is offline. This function still returns
/// [SwitchFailed] rather than throwing when given `false`, so a caller bug degrades to a
/// normal failure outcome.
Future<SwitchOutcome> switchToHost({
  required RelayConnection connection,
  required KeystoreService keystore,
  required PlainStore plainStore,
  required BiometricGate gate,
  required PairedHostRecord target,
  required bool hasNetwork,
}) async {
  if (!hasNetwork) {
    return SwitchFailed(
      hostId: target.hostId,
      reason: SwitchFailureReason.offline,
      detail: 'This phone has no network.',
    );
  }

  final secretsResult = await keystore.hostSecrets(target.hostId);
  final HostSecrets? secrets = secretsResult is Ok<HostSecrets?>
      ? secretsResult.value
      : null;
  if (secrets == null) {
    return SwitchFailed(
      hostId: target.hostId,
      reason: SwitchFailureReason.unknownHost,
      detail: 'This phone has no stored key for that computer.',
    );
  }

  final Uri? originUri = secrets.relayOrigin;
  if (originUri == null) {
    return SwitchFailed(
      hostId: target.hostId,
      reason: SwitchFailureReason.other,
      detail: 'No relay address is stored for ${target.hostName}.',
    );
  }
  final parsedOrigin = parseRelayOrigin(originUri.toString());
  if (parsedOrigin is Err<RelayOrigin>) {
    return SwitchFailed(
      hostId: target.hostId,
      reason: SwitchFailureReason.other,
      detail: parsedOrigin.message,
    );
  }
  final origin = (parsedOrigin as Ok<RelayOrigin>).value;

  final deviceInfoResult = await _buildDeviceInfo(plainStore);
  if (deviceInfoResult is Err<messages.DeviceInfo>) {
    return SwitchFailed(
      hostId: target.hostId,
      reason: SwitchFailureReason.other,
      detail: deviceInfoResult.message,
    );
  }
  final deviceInfo = (deviceInfoResult as Ok<messages.DeviceInfo>).value;

  final unlockResult = await gate.unlock();
  if (unlockResult is Err<void>) {
    return SwitchFailed(
      hostId: target.hostId,
      reason: SwitchFailureReason.other,
      detail: unlockResult.message,
    );
  }

  final watchedPaneId = connection.watchedPaneId;
  if (watchedPaneId != null) {
    connection.unwatchPane(watchedPaneId);
  }
  // R-03-044: disconnect the current computer before connecting to the chosen one.
  // Belt-and-suspenders — `connect()` already closes any existing socket first — but this is
  // also the point `_deliberateClose` is set, so a lost link mid-switch never triggers
  // relay.dart's own automatic reconnect against the computer being left.
  await connection.disconnect();

  final connectResult = await connection.connect(
    origin: origin,
    handle: secrets.routingHandle,
    mode: ReconnectMode(
      remoteStaticPublicKey: Uint8List.fromList(secrets.hostStaticPublicKey),
    ),
    gate: gate,
    deviceInfo: deviceInfo,
  );
  switch (connectResult) {
    case Ok<void>():
      final hostInfo = connection.lastHostInfo;
      final hostName = hostInfo?.hostName ?? target.hostName;
      if (hostInfo != null && hostInfo.hostName != target.hostName) {
        // R-13-065: the stored display name is rewritten on every connection. One field
        // only: a whole-record save from the row read before connecting would erase the
        // last-seen stamp `app.dart` writes on the same connect.
        await plainStore.updateHostName(target.hostId, hostName);
      }
      return SwitchSucceeded(hostId: target.hostId, hostName: hostName);
    case Err<void>(:final message, :final cause):
      return SwitchFailed(
        hostId: target.hostId,
        reason: _classifyFailure(cause),
        detail: cause?.toString() ?? message,
      );
  }
}

SwitchFailureReason _classifyFailure(Object? cause) {
  if (cause is RelayRegistrationException) {
    return cause.code == RelayRegistrationErrorCode.hostInUse
        ? SwitchFailureReason.hostInUse
        : SwitchFailureReason.unknownHost;
  }
  if (cause is RelayConnectException &&
      cause.failure == RelayConnectFailure.handshakeFailed) {
    return SwitchFailureReason.rejected;
  }
  return SwitchFailureReason.other;
}

/// Forgets [hostId] locally (R-31-05-02): removes its secret record (`KeystoreService`) and
/// its non-secret record (`PlainStore`). Never contacts the relay or the Host — forgetting is
/// a Device-local act, and R-31-05-03 forbids ever claiming it revoked the Device on the
/// Host.
Future<Result<void>> forgetHost({
  required KeystoreService keystore,
  required PlainStore plainStore,
  required String hostId,
}) async {
  final secretsResult = await keystore.deleteHostSecrets(hostId);
  if (secretsResult is Err<void>) return secretsResult;
  return plainStore.removePairedHost(hostId);
}

/// The exact sentence R-31-05-03 requires, with this phone's own device name — never `r`,
/// and the selection step a person still has to do on the Relay pane's own row list. A
/// `keyedText` template, per R-03-103: the screen draws `{d}` as an inline key cap.
String forgetStillListedSentence(String thisDeviceName) =>
    'The computer still lists this phone. In the Relay pane, select '
    '$thisDeviceName and press {d}.';

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

/// `last seen 14:02` today, `last seen yesterday 14:02` yesterday, or `last seen 3 Mar`
/// before that (`docs/31-mockups/05-host-list.md` callout 5, R-03-046). [now] lets a test fix
/// the clock; both [local] and [now] MUST already be in local time.
String formatLastSeenLong(DateTime local, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final today = DateTime(reference.year, reference.month, reference.day);
  final seenDay = DateTime(local.year, local.month, local.day);
  final diffDays = today.difference(seenDay).inDays;
  final hm = '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
  if (diffDays == 0) return 'last seen $hm';
  if (diffDays == 1) return 'last seen yesterday $hm';
  return 'last seen ${local.day} ${_monthAbbreviations[local.month - 1]}';
}

/// Builds the `device_info` payload for [RelayConnection.connect], mirroring
/// `qr_scan_screen.dart`'s own private `_buildDeviceInfo` (R-11-226 caps `deviceName` at 32
/// UTF-8 bytes; truncating by character count is a safe approximation for the ASCII device
/// model names this reads in practice). Duplicated rather than shared: that method is private
/// to a sibling work package's file, and R-90-018 assigns a shared factoring only once a
/// second *reachable* caller needs one — this is that second caller, but across a work
/// package boundary this codebase does not otherwise cross.
Future<Result<messages.DeviceInfo>> _buildDeviceInfo(
  PlainStore plainStore,
) async {
  try {
    final idResult = await plainStore.deviceId();
    if (idResult is Err<String>) {
      return Err(idResult.message, cause: idResult.cause);
    }
    final deviceId = (idResult as Ok<String>).value;
    final nameResult = await plainStore.deviceName();
    final storedName = nameResult is Ok<String?> ? nameResult.value : null;

    final String modelName;
    final String osVersion;
    if (_isIos) {
      final info = await DeviceInfoPlugin().iosInfo;
      modelName = info.modelName;
      osVersion = info.systemVersion;
    } else {
      final info = await DeviceInfoPlugin().androidInfo;
      modelName = info.model;
      osVersion = info.version.release;
    }
    final packageInfo = await PackageInfo.fromPlatform();
    final name = storedName ?? modelName;
    return Ok(
      messages.DeviceInfo(
        protocol: frameProtocolVersion,
        deviceId: deviceId,
        deviceName: name.length > 32 ? name.substring(0, 32) : name,
        platform: _isIos ? messages.Platform.ios : messages.Platform.android,
        osVersion: osVersion,
        appVersion: packageInfo.version,
      ),
    );
  } on Exception catch (e) {
    return Err('build device info', cause: e);
  }
}
