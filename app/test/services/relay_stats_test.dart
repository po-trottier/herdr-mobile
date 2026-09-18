/// Tests `RelayConnection`'s connection-diagnostics stats (`WP-21-a`, R-31-13-06,
/// R-31-13-19, R-31-13-02): per-session frame/byte counters, one corr-paired round-trip
/// latency, and raw close code/reason threaded onto `RelayDisconnected`.
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
import 'package:herdr_mobile/models/messages/ping.dart';
import 'package:herdr_mobile/models/messages/platform.dart' as wire;
import 'package:herdr_mobile/models/messages/pong.dart';
import 'package:herdr_mobile/models/messages/tree_request.dart';
import 'package:herdr_mobile/models/messages/tree_snapshot.dart';
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

Future<void> _sendHostMessage(
  WebSocket ws,
  NoiseCipher hostSendsWithDeviceReceiveKey,
  Message message,
  int seq, {
  String? corr,
}) async {
  final frame = Frame(
    v: frameProtocolVersion,
    type: message.typeName,
    seq: seq,
    corr: corr,
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
  test('framesOut/framesIn/bytesInOnWire/bytesInUnpacked/lastRoundTrip track one real '
      'correlated request-reply pair, reset per connect() (R-31-13-06, R-31-13-19)', () async {
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

    var now = DateTime(2026);
    final relay = RelayConnection(
      now: () => now,
      handshaker: _fakeHandshaker,
      connectivityWatcher: _noOpConnectivityWatcher(),
    );
    addTearDown(relay.dispose);

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
    // device_info is the connection's own unavoidable first send.
    expect(relay.framesOut, 1);
    expect(relay.framesIn, 0);
    expect(relay.lastRoundTrip, isNull);

    relay.send(const Message.treeRequest(TreeRequest()), corr: 'c1');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(relay.framesOut, 2, reason: 'device_info, then tree_request');

    now = now.add(const Duration(milliseconds: 10));
    await _sendHostMessage(
      ws,
      hostSend,
      const Message.treeSnapshot(
        TreeSnapshot(workspaces: [], tabs: [], panes: [], agents: []),
      ),
      2,
      corr: 'c1',
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(relay.framesIn, 1);
    expect(relay.bytesInOnWire, greaterThan(0));
    expect(relay.bytesInUnpacked, greaterThan(0));
    expect(
      relay.lastRoundTrip,
      isNotNull,
      reason: 'tree_snapshot echoed c1, the corr tree_request was sent with',
    );
    expect(relay.lastRoundTrip! >= Duration.zero, isTrue);
    final firstRtt = relay.lastRoundTrip;
    relay.send(const Message.ping(Ping()), corr: 'expired');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    now = now.add(const Duration(minutes: 1));
    relay.send(const Message.ping(Ping()), corr: 'fresh');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final expiredReply = relay.messages.first;
    await _sendHostMessage(
      ws,
      hostSend,
      const Message.pong(Pong()),
      3,
      corr: 'expired',
    );
    expect((await expiredReply as MessagePong).corr, 'expired');
    expect(relay.lastRoundTrip, firstRtt);
    now = now.add(const Duration(milliseconds: 23));
    final freshReply = relay.messages.first;
    await _sendHostMessage(
      ws,
      hostSend,
      const Message.pong(Pong()),
      4,
      corr: 'fresh',
    );
    expect((await freshReply as MessagePong).corr, 'fresh');
    expect(relay.lastRoundTrip, const Duration(milliseconds: 23));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('a non-revoked mid-session close threads the raw close code and reason onto '
      'RelayDisconnected (R-31-13-02, R-11-092)', () async {
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

    await ws.close(1001, 'going away');

    await expectLater(
      Stream<void>.periodic(const Duration(milliseconds: 10))
          .map(
            (_) => states
                .whereType<RelayDisconnected>()
                .where((s) => s.closeCode != null)
                .isNotEmpty,
          )
          .firstWhere((seen) => seen)
          .timeout(const Duration(seconds: 5)),
      completes,
    );
    final disconnected = states.whereType<RelayDisconnected>().last;
    expect(disconnected.closeCode, 1001);
    expect(disconnected.closeReason, 'going away');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('a 4006 close after the handshake, before host_info, is host_in_use, not a broken '
      'link (R-11-121, R-30-940; measured live 2026-09-18 with two paired phones)', () async {
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
    final iterator = StreamIterator<dynamic>(ws);
    await iterator.moveNext(); // device_register
    ws.add(jsonEncode({'type': 'session_joined', 'role': 'device'}));
    // The Host completes the handshake, then finds another Device active
    // (R-10-069) and closes with host_in_use instead of sending host_info.
    await ws.close(4006, 'host_in_use');

    final result = await connectResult;
    expect(result, isA<Err<void>>());
    final cause = (result as Err<void>).cause;
    expect(cause, isA<RelayRegistrationException>());
    expect(
      (cause as RelayRegistrationException).code,
      RelayRegistrationErrorCode.hostInUse,
    );
    expect(cause.message, 'host_in_use');
    // The state stream delivers on a later microtask than the returned future.
    await Future<void>.delayed(Duration.zero);
    expect(
      states.whereType<RelayRegistrationError>().single.code,
      RelayRegistrationErrorCode.hostInUse,
    );
    expect(states.whereType<RelayDisconnected>(), isEmpty);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
