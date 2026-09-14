/// Tests host sorting, last-seen formatting, local removal, and relay selection.
library;

import 'dart:convert' show base64Encode;
import 'dart:io' show SocketException;

import 'package:connectivity_plus/connectivity_plus.dart'
    show Connectivity, ConnectivityResult;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart';
import 'package:herdr_mobile/services/biometric_gate.dart';
import 'package:herdr_mobile/services/connectivity.dart'
    show ConnectivityWatcher;
import 'package:herdr_mobile/services/host_list.dart';
import 'package:herdr_mobile/services/keystore.dart';
import 'package:herdr_mobile/services/plain_store.dart';
import 'package:herdr_mobile/services/relay.dart';
import 'package:herdr_mobile/widgets/key_label.dart' show keyedPlain;
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

class _MockConnectivity extends Mock implements Connectivity {}

/// Mirrors `single_socket_test.dart`'s own helper: `RelayConnection`'s constructor starts a
/// real `ConnectivityWatcher`, whose `onConnectivityChanged` subscription needs a live
/// platform binding this plain `flutter_test` `main()` never initialises.
ConnectivityWatcher _noOpConnectivityWatcher() {
  final connectivity = _MockConnectivity();
  when(() => connectivity.onConnectivityChanged)
      .thenAnswer((_) => const Stream<List<ConnectivityResult>>.empty());
  return ConnectivityWatcher(connectivity: connectivity);
}

PairedHostRecord _record({
  String hostId = 'host-1',
  String hostName = 'patrick-desk',
  DateTime? lastSeen,
}) => PairedHostRecord(hostId: hostId, hostName: hostName, lastSeen: lastSeen);

void main() {
  group('sortHostRows (R-31-05-01)', () {
    HostListRow row({
      required String name,
      HostRowState state = HostRowState.saved,
      int attention = 0,
    }) => HostListRow(
      record: _record(hostId: name, hostName: name),
      state: state,
      attentionCount: attention,
    );

    test('orders by attention count descending first', () {
      final sorted = sortHostRows(<HostListRow>[
        row(name: 'zeta', attention: 1),
        row(name: 'alpha', attention: 5),
      ]);
      expect(sorted.map((r) => r.record.hostName), ['alpha', 'zeta']);
    });

    test('then connected above every other state at equal attention', () {
      final sorted = sortHostRows(<HostListRow>[
        row(name: 'zeta', state: HostRowState.saved),
        row(name: 'alpha', state: HostRowState.connected),
      ]);
      expect(sorted.map((r) => r.record.hostName), ['alpha', 'zeta']);
    });

    test('then name, case-insensitively, ascending', () {
      final sorted = sortHostRows(<HostListRow>[
        row(name: 'zeta'),
        row(name: 'Alpha'),
        row(name: 'beta'),
      ]);
      expect(sorted.map((r) => r.record.hostName), ['Alpha', 'beta', 'zeta']);
    });

    test('does not mutate the input list', () {
      final rows = <HostListRow>[row(name: 'zeta'), row(name: 'alpha')];
      final original = List<HostListRow>.of(rows);
      sortHostRows(rows);
      expect(
        rows.map((r) => r.record.hostName),
        original.map((r) => r.record.hostName),
      );
    });
  });

  group('formatLastSeenLong (docs/31-mockups/05-host-list.md callout 5)', () {
    final now = DateTime(2026, 8, 27, 14, 2);

    test('today reads a bare time', () {
      expect(
        formatLastSeenLong(DateTime(2026, 8, 27, 9, 14), now: now),
        'last seen 09:14',
      );
    });

    test('yesterday names the day', () {
      expect(
        formatLastSeenLong(DateTime(2026, 8, 26, 9, 14), now: now),
        'last seen yesterday 09:14',
      );
    });

    test('older names the date, not the time', () {
      expect(
        formatLastSeenLong(DateTime(2026, 3, 3, 9, 14), now: now),
        'last seen 3 Mar',
      );
    });
  });

  test('forgetStillListedSentence names this phone, draws d as a key and never names r '
      '(R-31-05-03, R-03-103)', () {
    final sentence = forgetStillListedSentence('pixel-9');
    expect(
      sentence,
      'The computer still lists this phone. In the Relay pane, select pixel-9 and press {d}.',
    );
    expect(
      keyedPlain(sentence),
      'The computer still lists this phone. In the Relay pane, select pixel-9 and press d.',
    );
    expect(sentence, isNot(contains('press r')));
  });

  group('forgetHost (R-31-05-02)', () {
    late _MockFlutterSecureStorage storage;
    late KeystoreService keystore;
    late PlainStore plainStore;

    setUp(() async {
      storage = _MockFlutterSecureStorage();
      when(() => storage.delete(key: any(named: 'key')))
          .thenAnswer((_) async {});
      keystore = KeystoreService(appLockEnabled: false, storage: storage);
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      plainStore = PlainStore();
      await plainStore.savePairedHost(_record());
    });

    test(
      'removes both the secret and the non-secret record, contacting no relay',
      () async {
        final result = await forgetHost(
          keystore: keystore,
          plainStore: plainStore,
          hostId: 'host-1',
        );
        expect(result, isA<Ok<void>>());
        verify(() => storage.delete(key: 'host_static_public_key_host-1'))
            .called(1);
        verify(() => storage.delete(key: 'host_routing_handle_host-1'))
            .called(1);
        verify(() => storage.delete(key: 'host_relay_origin_host-1')).called(1);
        final remaining = await plainStore.pairedHosts();
        expect((remaining as Ok<List<PairedHostRecord>>).value, isEmpty);
      },
    );
  });

  group('switchToHost', () {
    late RelayConnection connection;
    late BiometricGate gate;

    setUp(() {
      connection = RelayConnection(
        connectivityWatcher: _noOpConnectivityWatcher(),
      );
      // A no-op: `BiometricGate`'s constructor now clears the native `FLAG_SECURE` channel
      // immediately when App Lock starts off (the fresh-install black-screenshot fix), so an
      // off-mode gate needs a `setNativeLocked` stub or the real `_defaultSetNativeLocked`
      // throws with no platform binding in a plain `test()` (no widget binding at all).
      gate = BiometricGate(appLockEnabled: false, setNativeLocked: (_) {});
    });

    tearDown(() async {
      await connection.dispose();
    });

    test('refuses to attempt a switch while offline (R-30-947)', () async {
      final storage = _MockFlutterSecureStorage();
      final keystore = KeystoreService(appLockEnabled: false, storage: storage);
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final plainStore = PlainStore();

      final outcome = await switchToHost(
        connection: connection,
        keystore: keystore,
        plainStore: plainStore,
        gate: gate,
        target: _record(),
        hasNetwork: false,
      );
      expect(outcome, isA<SwitchFailed>());
      expect((outcome as SwitchFailed).reason, SwitchFailureReason.offline);
      verifyZeroInteractions(storage);
    });

    test(
      'fails with unknownHost when this phone has no stored key for the Host',
      () async {
        final storage = _MockFlutterSecureStorage();
        when(() => storage.read(key: any(named: 'key')))
            .thenAnswer((_) async => null);
        final keystore = KeystoreService(
          appLockEnabled: false,
          storage: storage,
        );
        SharedPreferencesAsyncPlatform.instance =
            InMemorySharedPreferencesAsync.empty();
        final plainStore = PlainStore();

        final outcome = await switchToHost(
          connection: connection,
          keystore: keystore,
          plainStore: plainStore,
          gate: gate,
          target: _record(),
          hasNetwork: true,
        );
        expect(outcome, isA<SwitchFailed>());
        expect(
          (outcome as SwitchFailed).reason,
          SwitchFailureReason.unknownHost,
        );
      },
    );

    test('fails when the selected host has no relay origin', () async {
      final storage = _MockFlutterSecureStorage();
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((invocation) async {
            final key = invocation.namedArguments[#key] as String;
            if (key == 'host_static_public_key_host-1') {
              return base64Encode([1, 2, 3, 4]);
            }
            if (key == 'host_routing_handle_host-1') {
              return 'abcdefghijklmnopqrstuv';
            }
            return null; // This host has no saved relay origin.
          });
      final keystore = KeystoreService(appLockEnabled: false, storage: storage);
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final plainStore = PlainStore();

      final outcome = await switchToHost(
        connection: connection,
        keystore: keystore,
        plainStore: plainStore,
        gate: gate,
        target: _record(),
        hasNetwork: true,
      );
      expect(outcome, isA<SwitchFailed>());
      expect((outcome as SwitchFailed).reason, SwitchFailureReason.other);
      expect(outcome.detail, 'No relay address is stored for patrick-desk.');
    });
    test('switching hosts dials each saved relay origin', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('dev.fluttercommunity.plus/device_info');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        return <String, dynamic>{
          'version': <String, dynamic>{
            'baseOS': '',
            'sdkInt': 34,
            'release': '14',
            'codename': 'REL',
            'incremental': '',
            'previewSdkInt': 0,
            'securityPatch': '',
          },
          'board': 'shiba',
          'bootloader': 'test',
          'brand': 'Google',
          'device': 'shiba',
          'display': 'test',
          'fingerprint': 'test',
          'hardware': 'shiba',
          'host': 'test',
          'id': 'test',
          'manufacturer': 'Google',
          'model': 'Pixel 8',
          'product': 'shiba',
          'name': 'shiba',
          'supported32BitAbis': <String>[],
          'supported64BitAbis': <String>['arm64-v8a'],
          'supportedAbis': <String>['arm64-v8a'],
          'tags': 'release-keys',
          'type': 'user',
          'isPhysicalDevice': true,
          'freeDiskSize': 0,
          'totalDiskSize': 0,
          'systemFeatures': <String>[],
          'isLowRamDevice': false,
          'physicalRamSize': 0,
          'availableRamSize': 0,
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      PackageInfo.setMockInitialValues(
        appName: 'Herdr',
        packageName: 'dev.herdr',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );
      final values = <String, String>{};
      final storage = _MockFlutterSecureStorage();
      when(() => storage.read(key: any(named: 'key'))).thenAnswer(
        (invocation) async => values[invocation.namedArguments[#key]],
      );
      when(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((invocation) async {
        values[invocation.namedArguments[#key] as String] =
            invocation.namedArguments[#value] as String;
      });
      final keystore = KeystoreService(appLockEnabled: false, storage: storage);
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final plainStore = PlainStore();
      final hosts = [
        _record(),
        _record(hostId: 'host-2', hostName: 'other-computer'),
      ];
      final origins = [
        Uri.parse('https://first.example.com'),
        Uri.parse('https://second.example.com:8443'),
      ];
      for (var i = 0; i < hosts.length; i++) {
        await plainStore.savePairedHost(hosts[i]);
        await keystore.storeHostSecrets(
          hosts[i].hostId,
          HostSecrets(
            hostStaticPublicKey: List.filled(32, 1),
            routingHandle: 'abcdefghijklmnopqrstuv',
            relayOrigin: origins[i],
          ),
        );
      }
      final dialed = <Uri>[];
      final relay = RelayConnection(
        connectivityWatcher: _noOpConnectivityWatcher(),
        channelFactory: (uri, protocols) async {
          dialed.add(uri);
          throw const SocketException('Test relay unavailable');
        },
      );
      addTearDown(relay.dispose);
      final switchGate = BiometricGate(
        appLockEnabled: false,
        keystore: keystore,
        setNativeLocked: (_) {},
      );
      for (final host in hosts) {
        final outcome = await switchToHost(
          connection: relay,
          keystore: keystore,
          plainStore: plainStore,
          gate: switchGate,
          target: host,
          hasNetwork: true,
        );
        expect(
          outcome,
          isA<SwitchFailed>().having(
            (failure) => failure.reason,
            'reason',
            SwitchFailureReason.other,
          ),
        );
      }
      expect(dialed, [
        Uri.parse('wss://first.example.com/device/abcdefghijklmnopqrstuv'),
        Uri.parse(
          'wss://second.example.com:8443/device/abcdefghijklmnopqrstuv',
        ),
      ]);
    });
  });
}
