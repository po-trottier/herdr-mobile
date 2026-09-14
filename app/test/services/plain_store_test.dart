/// Tests `plain_store.dart`'s paired-host mutations (R-13-065, R-03-043): every
/// read-modify-write of the one `paired_hosts` key runs through one process-wide queue, and
/// `updateLastSeen` changes one field of one record. Measured on 2026-09-03: the app root
/// stamps `lastSeen` on connect while `host_list.dart` refreshes `hostName` from the same
/// `host_info`, and two unqueued read-copy-save sequences dropped whichever change landed
/// first.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart';
import 'package:herdr_mobile/services/plain_store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

Future<PairedHostRecord> _host(PlainStore store, String hostId) async {
  final Result<List<PairedHostRecord>> hosts = await store.pairedHosts();
  return (hosts as Ok<List<PairedHostRecord>>).value.singleWhere(
    (record) => record.hostId == hostId,
  );
}

void main() {
  late PlainStore store;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    store = PlainStore();
    await store.savePairedHost(
      const PairedHostRecord(hostId: 'h1', hostName: 'old-name'),
    );
    await store.savePairedHost(
      const PairedHostRecord(hostId: 'h2', hostName: 'other'),
    );
  });

  test(
    'a concurrent hostName refresh and lastSeen stamp both land, through two '
    'separately constructed stores, with no await between the two starts',
    () async {
      final DateTime at = DateTime.utc(2026, 9, 3, 12);
      // The two production writers: `host_list.dart` renames from `host_info`, and
      // `app.dart` stamps the time from its own `PlainStore()`.
      final Future<Result<void>> rename = store.updateHostName(
        'h1',
        'new-name',
      );
      final Future<Result<void>> stamp = PlainStore().updateLastSeen('h1', at);
      await Future.wait(<Future<Result<void>>>[rename, stamp]);

      final PairedHostRecord h1 = await _host(store, 'h1');
      expect(h1.hostName, 'new-name', reason: 'the name refresh must survive');
      expect(h1.lastSeen, at, reason: 'the stamp must survive');
      final PairedHostRecord h2 = await _host(store, 'h2');
      expect(h2.hostName, 'other', reason: 'the other row is untouched');
    },
  );

  test('the reverse order, stamp then rename, keeps both too', () async {
    final DateTime at = DateTime.utc(2026, 9, 3, 12, 30);
    final Future<Result<void>> stamp = store.updateLastSeen('h1', at);
    final Future<Result<void>> rename = PlainStore().updateHostName(
      'h1',
      'new-name',
    );
    await Future.wait(<Future<Result<void>>>[stamp, rename]);

    final PairedHostRecord h1 = await _host(store, 'h1');
    expect(h1.hostName, 'new-name');
    expect(h1.lastSeen, at, reason: 'a rename touches only the name field');
  });

  test(
    'updateHostName never recreates a computer removed in the meantime',
    () async {
      final Future<Result<void>> remove = store.removePairedHost('h1');
      final Future<Result<void>> rename = PlainStore().updateHostName(
        'h1',
        'x',
      );
      await Future.wait(<Future<Result<void>>>[remove, rename]);

      final Result<List<PairedHostRecord>> hosts = await store.pairedHosts();
      final List<String> ids = (hosts as Ok<List<PairedHostRecord>>).value
          .map((record) => record.hostId)
          .toList();
      expect(ids, <String>['h2']);
    },
  );

  test(
    'updateLastSeen never recreates a computer removed in the meantime',
    () async {
      final Future<Result<void>> remove = store.removePairedHost('h1');
      final Future<Result<void>> stamp = PlainStore().updateLastSeen(
        'h1',
        DateTime.utc(2026, 9, 3, 13),
      );
      await Future.wait(<Future<Result<void>>>[remove, stamp]);

      final Result<List<PairedHostRecord>> hosts = await store.pairedHosts();
      final List<String> ids = (hosts as Ok<List<PairedHostRecord>>).value
          .map((record) => record.hostId)
          .toList();
      expect(ids, <String>['h2']);
    },
  );
}
