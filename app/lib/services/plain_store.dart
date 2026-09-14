// The Device's non-secret, app-wide and per-paired-computer state.
//
// R-13-065 lists exactly what belongs here: the Device identifier (`device_id`), the Device
// human-readable name (`device_name`), and, for each paired computer, its pairing identifier
// (`host_id`), its display name (`host_name`), and the time of the last contact with it (link
// open or close). None
// of these values need a biometric gate, so they live in `shared_preferences`, not the
// keychain or keystore.
//
// Everything R-13-063 protects behind the biometric gate — the Device's Curve25519 private
// key, each paired computer's pinned Host public key and routing handle, and the app-wide
// relay origin (R-30-922) — lives in `keystore.dart` instead, even though the relay origin is
// app-wide like the values in this file. R-13-063 is explicit that the origin is stored
// alongside the other secrets, so it is not duplicated here. A `PairedHostRecord` here and a
// `HostSecrets` record in `keystore.dart` share one `hostId`; neither file reads the other's
// storage.
//
// Every public method returns `Result<T>` per R-41-103, imported from `keystore.dart` (see
// that file's header for why the shared type lives there rather than in a dedicated
// `app/lib/core/result/` file).

import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/result/result.dart' show Err, Ok, Result;

/// One paired computer's non-secret metadata (R-13-065). `host_name` is rewritten on every
/// connection, because `host_info` arrives only while connected.
final class PairedHostRecord {
  const PairedHostRecord({
    required this.hostId,
    required this.hostName,
    this.lastSeen,
  });

  /// The Host's pairing identifier (a UUIDv4 the Host assigns at enrolment, R-13-048).
  final String hostId;

  /// The Host's display name, at most 32 UTF-8 bytes on the wire (R-11-226).
  final String hostName;

  /// The time of the last contact with this computer (link opened or closed, R-13-065), or
  /// `null` if the link never opened.
  final DateTime? lastSeen;

  PairedHostRecord copyWith({String? hostName, DateTime? lastSeen}) =>
      PairedHostRecord(
        hostId: hostId,
        hostName: hostName ?? this.hostName,
        lastSeen: lastSeen ?? this.lastSeen,
      );

  Map<String, Object?> _toJson() => {
    'hostId': hostId,
    'hostName': hostName,
    'lastSeen': lastSeen?.toIso8601String(),
  };

  static PairedHostRecord _fromJson(Map<String, Object?> json) {
    final lastSeenText = json['lastSeen'] as String?;
    return PairedHostRecord(
      hostId: json['hostId']! as String,
      hostName: json['hostName']! as String,
      lastSeen: lastSeenText == null ? null : DateTime.parse(lastSeenText),
    );
  }
}

/// One acknowledged notification (`docs/31-mockups/07-notifications.md` R-31-07-01, decided
/// 2026-09-04): the identity `(paneId, status, at)` of the agent status change a person marked
/// read or removed on one computer. Metadata only, never pane content (R-30-510). One record per
/// `(hostId, paneId)`; a later acknowledgement of the same pane replaces it.
final class NotificationAck {
  const NotificationAck({
    required this.hostId,
    required this.paneId,
    required this.status,
    required this.at,
    required this.removed,
  });

  final String hostId;
  final String paneId;

  /// The `AgentStatusKind` name, `blocked` or `done`.
  final String status;

  /// The RFC 3339 `at` of the acknowledged change, or `null` when the Host reported none.
  final String? at;

  /// `true` for `Remove`/`Remove all`, `false` for `Mark as read`/`Mark all as read`.
  final bool removed;

  Map<String, Object?> _toJson() => {
    'host_id': hostId,
    'pane_id': paneId,
    'status': status,
    'at': at,
    'removed': removed,
  };

  static NotificationAck _fromJson(Map<String, Object?> json) =>
      NotificationAck(
        hostId: json['host_id'] as String,
        paneId: json['pane_id'] as String,
        status: json['status'] as String,
        at: json['at'] as String?,
        removed: json['removed'] as bool,
      );
}

/// The Device's non-secret persisted state, backed by `shared_preferences` 2.5.5.
class PlainStore {
  PlainStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  static const _deviceIdStorageKey = 'device_id';
  static const _deviceNameStorageKey = 'device_name';
  static const _pairedHostsStorageKey = 'paired_hosts';
  static const _notificationAcksStorageKey = 'notification_acks';

  /// The Device's UUIDv4 identifier for the `device_info` wire message
  /// (`docs/11-relay-protocol.md` section 4.2), generated once with `Random.secure()`
  /// (R-20-035) and reused for every session until the app is uninstalled.
  Future<Result<String>> deviceId() async {
    try {
      final existing = await _preferences.getString(_deviceIdStorageKey);
      if (existing != null) {
        return Ok(existing);
      }
      final generated = _generateUuidV4();
      await _preferences.setString(_deviceIdStorageKey, generated);
      return Ok(generated);
    } on Exception catch (e) {
      return Err('read or generate the device id', cause: e);
    }
  }

  /// The Device's human-readable name, or `Ok(null)` before the user has set one.
  Future<Result<String?>> deviceName() async {
    try {
      return Ok(await _preferences.getString(_deviceNameStorageKey));
    } on Exception catch (e) {
      return Err('read the device name', cause: e);
    }
  }

  Future<Result<void>> setDeviceName(String name) async {
    try {
      await _preferences.setString(_deviceNameStorageKey, name);
      return const Ok(null);
    } on Exception catch (e) {
      return Err('store the device name', cause: e);
    }
  }

  /// Every paired computer's non-secret record (R-03-043).
  Future<Result<List<PairedHostRecord>>> pairedHosts() async {
    try {
      return Ok(await _readPairedHosts());
    } on Exception catch (e) {
      return Err('read paired hosts', cause: e);
    }
  }

  /// Inserts [record], or replaces the existing record with the same `hostId`. Used at
  /// enrolment only (R-13-048). A later change to one field goes through [updateHostName] or
  /// [updateLastSeen], never through a whole-record save built from a stale read.
  Future<Result<void>> savePairedHost(PairedHostRecord record) =>
      _mutatePairedHosts('save paired host ${record.hostId}', (hosts) {
        final index = hosts.indexWhere((host) => host.hostId == record.hostId);
        if (index >= 0) {
          hosts[index] = record;
        } else {
          hosts.add(record);
        }
      });

  /// Rewrites the display name of one saved computer from `host_info` (R-13-065) and touches
  /// nothing else on its record, so a concurrent [updateLastSeen] stamp is never overwritten.
  /// A computer removed in the meantime stays removed: no record is recreated.
  Future<Result<void>> updateHostName(String hostId, String hostName) =>
      _mutatePairedHosts('rename paired host $hostId', (hosts) {
        final index = hosts.indexWhere((host) => host.hostId == hostId);
        if (index >= 0) {
          hosts[index] = hosts[index].copyWith(hostName: hostName);
        }
      });

  /// Stamps the last-contact time of one saved computer (R-13-065) and touches nothing else
  /// on its record, so a concurrent [updateHostName] refresh is never overwritten. A computer
  /// removed in the meantime stays removed: no record is recreated.
  Future<Result<void>> updateLastSeen(String hostId, DateTime at) =>
      _mutatePairedHosts('stamp last seen for $hostId', (hosts) {
        final index = hosts.indexWhere((host) => host.hostId == hostId);
        if (index >= 0) hosts[index] = hosts[index].copyWith(lastSeen: at);
      });

  /// Removes a paired computer's non-secret record and every notification acknowledgement
  /// stored for it. The caller MUST also remove its secret record via `keystore.dart`'s
  /// `deleteHostSecrets` (R-13-063).
  Future<Result<void>> removePairedHost(String hostId) async {
    final Result<void> hosts = await _mutatePairedHosts(
      'remove paired host $hostId',
      (hosts) => hosts.removeWhere((host) => host.hostId == hostId),
    );
    if (hosts is Err<void>) return hosts;
    return _mutateAcks(
      'clear notification acknowledgements for $hostId',
      (acks) => acks.removeWhere((ack) => ack.hostId == hostId),
    );
  }

  /// Every acknowledged notification of one computer (R-31-07-01).
  Future<Result<List<NotificationAck>>> notificationAcks(String hostId) async {
    try {
      final acks = await _readAcks();
      return Ok(acks.where((ack) => ack.hostId == hostId).toList());
    } on Exception catch (e) {
      return Err('read notification acknowledgements', cause: e);
    }
  }

  /// Inserts [ack], or replaces the record with the same `hostId` and `paneId`.
  Future<Result<void>> saveNotificationAck(NotificationAck ack) => _mutateAcks(
    'save notification acknowledgement for ${ack.paneId}',
    (acks) {
      acks.removeWhere((a) => a.hostId == ack.hostId && a.paneId == ack.paneId);
      acks.add(ack);
    },
  );

  /// The acknowledgement list shares the paired-host queue: both are one preference key each,
  /// written from more than one place, and one queue is simpler than two.
  Future<Result<void>> _mutateAcks(
    String action,
    void Function(List<NotificationAck> acks) mutate,
  ) {
    final Future<Result<void>> run = _pairedHostsQueue.then((_) async {
      try {
        final acks = await _readAcks();
        mutate(acks);
        await _preferences.setStringList(
          _notificationAcksStorageKey,
          acks.map((ack) => jsonEncode(ack._toJson())).toList(),
        );
        return const Ok(null);
      } on Exception catch (e) {
        return Err(action, cause: e);
      }
    });
    _pairedHostsQueue = run.then((_) {});
    return run;
  }

  Future<List<NotificationAck>> _readAcks() async {
    final raw =
        await _preferences.getStringList(_notificationAcksStorageKey) ??
        const <String>[];
    return raw
        .map(
          (json) => NotificationAck._fromJson(
            jsonDecode(json) as Map<String, Object?>,
          ),
        )
        .toList();
  }

  /// One process-wide queue for every read-modify-write of the paired-host list. The list is
  /// one preference key, `PlainStore` is constructed wherever it is needed, and the app root
  /// stamps `lastSeen` on connect while `host_list.dart` refreshes `hostName` from the same
  /// `host_info` (measured race, 2026-09-03): without the queue the later write drops the
  /// earlier change.
  static Future<void> _pairedHostsQueue = Future<void>.value();

  Future<Result<void>> _mutatePairedHosts(
    String action,
    void Function(List<PairedHostRecord> hosts) mutate,
  ) {
    final Future<Result<void>> run = _pairedHostsQueue.then((_) async {
      try {
        final hosts = await _readPairedHosts();
        mutate(hosts);
        await _writePairedHosts(hosts);
        return const Ok(null);
      } on Exception catch (e) {
        return Err(action, cause: e);
      }
    });
    _pairedHostsQueue = run.then((_) {});
    return run;
  }

  Future<List<PairedHostRecord>> _readPairedHosts() async {
    final raw =
        await _preferences.getStringList(_pairedHostsStorageKey) ??
        const <String>[];
    return raw
        .map(
          (json) => PairedHostRecord._fromJson(
            jsonDecode(json) as Map<String, Object?>,
          ),
        )
        .toList();
  }

  Future<void> _writePairedHosts(List<PairedHostRecord> hosts) =>
      _preferences.setStringList(
        _pairedHostsStorageKey,
        hosts.map((host) => jsonEncode(host._toJson())).toList(),
      );
}

/// A UUIDv4 (RFC 4122) drawn from `Random.secure()` (R-20-035, R-13-016).
String _generateUuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int start, int end) => bytes
      .sublist(start, end)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
