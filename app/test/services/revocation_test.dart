/// Proves `RelayConnection` (`app/lib/services/relay.dart`) distinguishes a mid-session
/// revocation close (WebSocket code `4004`, R-13-054, R-13-055, R-11-121) from an ordinary
/// network drop: publishes `RelayRevoked` on `connectionState` instead of the generic
/// `RelayDisconnected`, and never schedules an automatic reconnect for it — a revoked
/// Device retrying the same key only earns another `4004`.
///
/// Drives a real local `dart:io` `WebSocket` server as the fake Host counterpart. Only the
/// Noise handshake negotiation itself is stubbed via `RelayConnection`'s injectable
/// `handshaker`.
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
import 'package:herdr_mobile/models/messages/platform.dart' as wire;
import 'package:herdr_mobile/services/biometric_gate.dart';
import 'package:herdr_mobile/services/connectivity.dart';
import 'package:herdr_mobile/services/frame_codec.dart';
import 'package:herdr_mobile/services/keystore.dart';
import 'package:herdr_mobile/services/noise.dart';
import 'package:herdr_mobile/services/origin.dart';
import 'package:herdr_mobile/services/relay.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _MockLocalAuthentication extends Mock implements LocalAuthentication {}

class _MockConnectivity extends Mock implements Connectivity {}

ConnectivityWatcher _noOpConnectivityWatcher() {
  final connectivity = _MockConnectivity();
  when(() => connectivity.onConnectivityChanged)
      .thenAnswer((_) => const Stream<List<ConnectivityResult>>.empty());
  return ConnectivityWatcher(connectivity: connectivity);
}

class _MockKeystoreService extends Mock implements KeystoreService {}

final Uint8List _deviceSendKey = Uint8List.fromList(
  List.generate(32, (i) => i),
);
final Uint8List _deviceReceiveKey = Uint8List.fromList(
  List.generate(32, (i) => 31 - i),
);
final Uint8List _fixedRemoteStaticKey = Uint8List.fromList(
  List.filled(32, 0x42),
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
    remoteStaticPublicKey: _fixedRemoteStaticKey,
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
  when(() => keystore.deviceKeyPair()).thenAnswer((_) async => Ok(keyPair));
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

Future<void> _sendHostMessage(
  WebSocket ws,
  NoiseCipher hostSendsWithDeviceReceiveKey,
  Message message,
  int seq,
) async {
  final frame = Frame(
    v: frameProtocolVersion,
    type: message.typeName,
    seq: seq,
    payload: message.payloadJson,
  );
  final envelopeBytes = Uint8List.fromList(
    utf8.encode(jsonEncode(frame.toJson())),
  );
  final encoded = await encodeFrame(
    hostSendsWithDeviceReceiveKey,
    envelopeBytes,
  );
  for (final fragment in (encoded as Ok<List<Uint8List>>).value) {
    ws.add(fragment);
  }
}

const _testHostInfo = HostInfo(
  protocol: frameProtocolVersion,
  hostId: 'host-1',
  hostName: 'test-host',
  herdrVersion: '1.0.0',
  herdrProtocol: 20,
  paired: true,
);

const _testDeviceInfo = DeviceInfo(
  protocol: frameProtocolVersion,
  deviceId: 'device-1',
  deviceName: 'Test Phone',
  platform: wire.Platform.android,
  osVersion: '14',
  appVersion: '0.1.0',
);

void main() {
  test(
    'a mid-session close with code 4004 publishes RelayRevoked, not RelayDisconnected, '
    'and never schedules an automatic reconnect (R-13-054, R-13-055)',
    () async {
      final connections = <WebSocket>[];
      final server = await HttpServer.bind('127.0.0.1', 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        connections.add(await WebSocketTransformer.upgrade(request));
      });

      final gate = await _unlockedGate();
      final origin = (parseRelayOrigin(
        'http://127.0.0.1:${server.port}',
      ) as Ok<RelayOrigin>).value;

      final relay = RelayConnection(
        handshaker: _fakeHandshaker,
        connectivityWatcher: _noOpConnectivityWatcher(),
      );
      addTearDown(relay.dispose);

      final states = <RelayConnectionState>[];
      final statesSub = relay.connectionState.listen(states.add);
      addTearDown(statesSub.cancel);

      final connectResult = relay.connect(
        origin: origin,
        handle: 'h1',
        mode: PairingMode(psk: Uint8List(32)),
        gate: gate,
        deviceInfo: _testDeviceInfo,
      );

      while (connections.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final ws = connections[0];
      addTearDown(() => ws.close());
      final iterator = StreamIterator<dynamic>(ws);
      await iterator.moveNext(); // device_register
      ws.add(jsonEncode({'type': 'session_joined', 'role': 'device'}));
      final hostSend = NoiseCipher.withKey(_deviceReceiveKey);
      await _sendHostMessage(
        ws,
        hostSend,
        const Message.hostInfo(_testHostInfo),
        1,
      );

      expect(await connectResult, isA<Ok<void>>());
      expect(relay.isConnected, isTrue);

      // The Host revokes this Device mid-session: closes with 4004, no error frame.
      await ws.close(4004, 'revoked');

      await expectLater(
        Stream<void>.periodic(const Duration(milliseconds: 10))
            .map((_) => states.whereType<RelayRevoked>().isNotEmpty)
            .firstWhere((seen) => seen)
            .timeout(const Duration(seconds: 5)),
        completes,
        reason: 'RelayRevoked MUST be published on a 4004 mid-session close',
      );
      expect(
        states.whereType<RelayDisconnected>(),
        isEmpty,
        reason: 'a revocation close MUST NOT also publish the generic RelayDisconnected',
      );
      expect(relay.isConnected, isFalse);

      // No automatic reconnect: give the reconnect schedule's own first delay (0.5s,
      // R-22-028) generous headroom, then confirm the server never saw a second socket.
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(
        connections.length,
        1,
        reason: 'a revoked Device MUST NOT auto-reconnect with the same key',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
