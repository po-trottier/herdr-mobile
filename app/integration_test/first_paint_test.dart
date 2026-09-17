/// The R-31-08-09 first-paint gate: from the moment the app asks to watch a pane
/// (`RelayConnection.watchPane`, `app/lib/services/relay.dart`, `WP-14-a`, already built)
/// to the moment the first `pane_frame` for that pane arrives, decoded, MUST take under
/// 400 ms on a working mobile network. R-31-08-09's own reasoning is why this file measures
/// the wire round trip rather than a rendered pixel: "the measured payload is about 8 KB of
/// ANSI for a 50 row pane ... so this is a network round trip, not a bandwidth problem."
/// That round trip is exactly what `RelayConnection` — the transport `docs/90-implementation-
/// plan.md` Phase 14 already closed — carries, so this file exercises it directly rather
/// than through `terminal.dart` (`WP-16-a`) or `terminal_view_widget.dart` (`WP-16-b`):
/// `WP-16-c`'s own `Needs.` line names only `WP-16-a`'s declarations, not its
/// implementation, and does not name `WP-16-b` at all (R-90-024).
///
/// **Network gap.** R-31-08-09 says "a working mobile network"; this workstation has no
/// paired phone, no deployed relay and no cellular or WiFi hop to measure — `flutter
/// devices` here lists only Windows desktop, Chrome and Edge, the same gap
/// `spike_render_test.dart` (`WP-2`) already disclosed for its own device requirement. This
/// file serves the Host side of the exchange from a real local `dart:io` `WebSocket` server
/// instead, exactly `pairing_flow_test.dart`'s and `single_socket_test.dart`'s own harness
/// pattern (`_fakeHandshaker` skips only the Noise handshake's wire bytes — every other
/// step, including the real AEAD frame encryption, the real zlib compression and the real
/// fragmentation `frame_codec.dart` performs, runs for real). A loopback socket on one
/// machine has no radio hop and no carrier queueing, so the number this file prints is a
/// floor on the real figure, not a substitute for it — printed alongside the number so it
/// is never mistaken for an on-device, on-network measurement.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart';
import 'package:herdr_mobile/models/frame.dart';
import 'package:herdr_mobile/models/message.dart';
import 'package:herdr_mobile/models/messages/device_info.dart';
import 'package:herdr_mobile/models/messages/host_info.dart';
import 'package:herdr_mobile/models/messages/pane_frame.dart';
import 'package:herdr_mobile/models/messages/platform.dart' as wire;
import 'package:herdr_mobile/models/messages/scroll_offsets.dart';
import 'package:herdr_mobile/models/messages/watch_ack.dart';
import 'package:herdr_mobile/services/biometric_gate.dart';
import 'package:herdr_mobile/services/connectivity.dart';
import 'package:herdr_mobile/services/frame_codec.dart';
import 'package:herdr_mobile/services/keystore.dart';
import 'package:herdr_mobile/services/noise.dart';
import 'package:herdr_mobile/services/origin.dart';
import 'package:herdr_mobile/services/relay.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _MockLocalAuthentication extends Mock implements LocalAuthentication {}

class _MockKeystoreService extends Mock implements KeystoreService {}

class _MockConnectivity extends Mock implements Connectivity {}

ConnectivityWatcher _noOpConnectivityWatcher() {
  final connectivity = _MockConnectivity();
  when(() => connectivity.onConnectivityChanged)
      .thenAnswer((_) => const Stream<List<ConnectivityResult>>.empty());
  return ConnectivityWatcher(connectivity: connectivity);
}

/// Mirrors `pairing_flow_test.dart`'s and `single_socket_test.dart`'s own fixed transport
/// keys: the Device's session sends with [_deviceSendKey] and receives with
/// [_deviceReceiveKey], so the Host side below encrypts with [_deviceReceiveKey] and
/// decrypts with [_deviceSendKey].
final Uint8List _deviceSendKey = Uint8List.fromList(
  List.generate(32, (i) => i),
);
final Uint8List _deviceReceiveKey = Uint8List.fromList(
  List.generate(32, (i) => 31 - i),
);

Future<NoiseSession> _fakeHandshaker(
  StreamIterator<dynamic> iterator,
  WebSocketChannel channel,
  NoiseHandshakeMode mode,
  BiometricGate gate,
  SimpleKeyPair localStatic,
) async {
  return NoiseSession(
    send: NoiseCipher.withKey(_deviceSendKey),
    receive: NoiseCipher.withKey(_deviceReceiveKey),
    remoteStaticPublicKey: Uint8List.fromList(List.filled(32, 0x42)),
  );
}

Future<BiometricGate> _unlockedGate() async {
  final localAuth = _MockLocalAuthentication();
  final keystore = _MockKeystoreService();
  final keyPair = await X25519().newKeyPair();
  when(
    () =>
        localAuth.authenticate(localizedReason: any(named: 'localizedReason')),
  ).thenAnswer((_) async => true);
  when(() => keystore.existingDeviceKeyPair())
      .thenAnswer((_) async => Ok(keyPair));
  final gate = BiometricGate(
    appLockEnabled: true,
    localAuth: localAuth,
    keystore: keystore,
    setNativeLocked: (_) {},
  );
  final result = await gate.unlock();
  expect(result, isA<Ok<void>>());
  return gate;
}

const _testHostInfo = HostInfo(
  protocol: frameProtocolVersion,
  hostId: 'host-1',
  hostName: 'first-paint-host',
  herdrVersion: '1.0.0',
  herdrProtocol: 20,
  paired: false,
);

const _testDeviceInfo = DeviceInfo(
  protocol: frameProtocolVersion,
  deviceId: 'device-1',
  deviceName: 'Test Phone',
  platform: wire.Platform.android,
  osVersion: '14',
  appVersion: '0.1.0',
);

const _paneId = 'pane-1';

/// Serves one Host side of the exchange on [ws]: register, `host_info`, then — on the
/// first `watch_pane` it decodes — `watch_ack` followed immediately by `pane_frame`
/// carrying [ansiText] at [width] columns and [rows] rows, mirroring `_serveOnePairing`'s
/// pattern one step further into the session.
Future<void> _serveFirstPaint(
  WebSocket ws,
  String ansiText, {
  required int width,
  required int rows,
}) async {
  final iterator = StreamIterator<dynamic>(ws);
  await iterator.moveNext(); // device_register
  ws.add(jsonEncode({'type': 'session_joined', 'role': 'device'}));

  final hostSend = NoiseCipher.withKey(_deviceReceiveKey);
  final hostReceive = NoiseCipher.withKey(_deviceSendKey);
  final reassembler = Reassembler();
  var outgoingSeq = 1;

  Future<void> sendFrame(String type, Map<String, dynamic> payload) async {
    final frame = Frame(
      v: frameProtocolVersion,
      type: type,
      seq: outgoingSeq++,
      payload: payload,
    );
    final envelopeBytes = Uint8List.fromList(
      utf8.encode(jsonEncode(frame.toJson())),
    );
    final encoded = await encodeFrame(hostSend, envelopeBytes);
    for (final fragment in (encoded as Ok<List<Uint8List>>).value) {
      ws.add(fragment);
    }
  }

  await sendFrame('host_info', _testHostInfo.toJson());

  // Drain frames (device_info, then watch_pane) until watch_pane arrives.
  while (true) {
    if (!await iterator.moveNext()) {
      return;
    }
    final current = iterator.current;
    if (current is! List<int>) {
      continue;
    }
    final outcome = await decodeFragment(
      reassembler,
      hostReceive,
      Uint8List.fromList(current),
    );
    if (outcome case Err()) {
      continue;
    }
    final envelopeBytes = (outcome as Ok<Uint8List?>).value;
    if (envelopeBytes == null) {
      continue; // still assembling this record's fragments
    }
    final frame = Frame.fromJson(
      jsonDecode(utf8.decode(envelopeBytes)) as Map<String, dynamic>,
    );
    if (frame.type == 'watch_pane') {
      break;
    }
  }

  await sendFrame(
    'watch_ack',
    WatchAck(
      paneId: _paneId,
      revision: 1,
      viewportRows: rows,
      width: width,
      scroll: const ScrollOffsets(offsetFromBottom: 0, maxOffsetFromBottom: 0),
    ).toJson(),
  );
  await sendFrame(
    'pane_frame',
    PaneFrame(
      paneId: _paneId,
      revision: 1,
      viewportRows: rows,
      width: width,
      text: ansiText,
    ).toJson(),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  late RelayOrigin origin;

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://relay.example.com'));
  });

  setUp(() async {
    server = await HttpServer.bind('127.0.0.1', 0);
    // R-22-039: a loopback origin is on the local-development allow list.
    origin = (parseRelayOrigin(
      'http://127.0.0.1:${server.port}',
    ) as Ok<RelayOrigin>).value;
  });

  tearDown(() => server.close(force: true));

  testWidgets(
    'first paint arrives under 400 ms of watch_pane on this (loopback) network '
    '(R-31-08-09)',
    (WidgetTester tester) async {
      final ansiText = File('test/fixtures/pane-50row.ansi').readAsStringSync();
      // Sanity: this is the real ~9.4 KB captured fixture R-02-015 measured for a 50-row
      // pane, not a stub string — a test that passed against a handful of bytes would
      // prove nothing about the network round trip R-31-08-09 actually gates.
      expect(ansiText.length, greaterThan(8000));

      final connections = <WebSocket>[];
      server.listen((HttpRequest request) async {
        final ws = await WebSocketTransformer.upgrade(request);
        connections.add(ws);
        unawaited(_serveFirstPaint(ws, ansiText, width: 282, rows: 50));
      });

      final gate = await _unlockedGate();
      final connection = RelayConnection(
        handshaker: _fakeHandshaker,
        connectivityWatcher: _noOpConnectivityWatcher(),
      );
      addTearDown(connection.dispose);

      final connectResult = await connection.connect(
        origin: origin,
        handle: 'n6Loxf94CfyIO6hOxlaHvA',
        // `PairingMode` skips `connect()`'s reconnect-resume step (`tree_request` plus a
        // re-watch), which this file has no need to serve; `_fakeHandshaker` ignores
        // `mode` entirely, so the `psk` value here is never read.
        mode: PairingMode(psk: Uint8List(32)),
        gate: gate,
        deviceInfo: _testDeviceInfo,
      );
      expect(connectResult, isA<Ok<void>>());

      final firstPaneFrame = Completer<PaneFrame>();
      final subscription = connection.messages.listen((Message message) {
        if (message is MessagePaneFrame && !firstPaneFrame.isCompleted) {
          firstPaneFrame.complete(message.payload);
        }
      });
      addTearDown(subscription.cancel);

      final stopwatch = Stopwatch()..start();
      connection.watchPane(_paneId);
      final paneFrame = await firstPaneFrame.future.timeout(
        const Duration(seconds: 5),
      );
      stopwatch.stop();

      expect(paneFrame.paneId, _paneId);
      expect(paneFrame.text, ansiText);

      // Recorded for the pull request per this file's header comment. This number is NOT
      // an on-device, on-network R-31-08-09 measurement: see the "Network gap" note above.
      // ignore: avoid_print
      print(
        'first_paint_test: watch_pane -> pane_frame took '
        '${stopwatch.elapsedMilliseconds} ms over a loopback socket on this '
        'workstation (not a real mobile network — see this file\'s header comment)',
      );

      expect(stopwatch.elapsedMilliseconds, lessThan(400));
    },
  );
}
