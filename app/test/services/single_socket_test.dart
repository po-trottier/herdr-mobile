/// Proves `RelayConnection` (`app/lib/services/relay.dart`, `WP-14-a`) never holds two
/// relay sockets at once (R-20-009, R-22-025), and that an async connection failure — a
/// connect-refused/unreachable host, which `WebSocketChannel.connect`'s eager-return
/// pattern would otherwise let escape a naive `try`/`catch` — is caught and reported as an
/// `Err`, with no routing handle leaked into the error text (R-13-033, R-13-066).
///
/// This file's default `RelayConnection` uses the raw `dart:io` `WebSocket.connect`
/// directly (awaited, not the eager-return `IOWebSocketChannel.connect` adapter pattern —
/// see `relay.dart`'s own header doc comment), so a real connection failure is caught
/// exactly where `connect()`'s own `try`/`catch` expects it.
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

class _MockKeystoreService extends Mock implements KeystoreService {}

ConnectivityWatcher _noOpConnectivityWatcher() {
  final connectivity = _MockConnectivity();
  when(() => connectivity.onConnectivityChanged)
      .thenAnswer((_) => const Stream<List<ConnectivityResult>>.empty());
  return ConnectivityWatcher(connectivity: connectivity);
}

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
  test('connecting a second time closes the first socket before opening the '
      'second (R-20-009, R-22-025, R-11-222)', () async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    addTearDown(() => server.close(force: true));

    final connections = <WebSocket>[];
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

    Future<void> serveOneHandshake(WebSocket ws) async {
      final iterator = StreamIterator<dynamic>(ws);
      await iterator.moveNext(); // device_register
      ws.add(jsonEncode({'type': 'session_joined', 'role': 'device'}));
      final hostSend = NoiseCipher.withKey(_deviceReceiveKey);
      final frame = Frame(
        v: frameProtocolVersion,
        type: 'host_info',
        seq: 1,
        payload: _testHostInfo.toJson(),
      );
      final envelopeBytes = Uint8List.fromList(
        utf8.encode(jsonEncode(frame.toJson())),
      );
      final encoded = await encodeFrame(hostSend, envelopeBytes);
      for (final fragment in (encoded as Ok<List<Uint8List>>).value) {
        ws.add(fragment);
      }
    }

    final result1 = relay.connect(
      origin: origin,
      handle: 'h1',
      mode: ReconnectMode(remoteStaticPublicKey: _fixedRemoteStaticKey),
      gate: gate,
      deviceInfo: _testDeviceInfo,
    );
    while (connections.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await serveOneHandshake(connections[0]);
    expect(await result1, isA<Ok<void>>());
    expect(relay.isConnected, isTrue);

    final result2 = relay.connect(
      origin: origin,
      handle: 'h2',
      mode: ReconnectMode(remoteStaticPublicKey: _fixedRemoteStaticKey),
      gate: gate,
      deviceInfo: _testDeviceInfo,
    );
    while (connections.length < 2) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    // connect() always awaits closing any existing socket before opening a new one
    // (see relay.dart's own connect()), so serving the second handshake now is safe.
    await serveOneHandshake(connections[1]);
    expect(await result2, isA<Ok<void>>());
    expect(relay.isConnected, isTrue);
    expect(
      connections.length,
      2,
      reason: 'never more than one socket at once across the two connects',
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('a connect-refused/unreachable host is caught as an Err with no handle leak '
      '(R-13-033, R-13-066)', () async {
    final gate = await _unlockedGate();
    // R-22-039: a port nothing listens on, on the local-development allow list.
    final origin =
        (parseRelayOrigin('http://127.0.0.1:1') as Ok<RelayOrigin>).value;
    final relay = RelayConnection(
      handshaker: _fakeHandshaker,
      connectivityWatcher: _noOpConnectivityWatcher(),
    );
    addTearDown(relay.dispose);

    final result = await relay.connect(
      origin: origin,
      handle: 'n6Loxf94CfyIO6hOxlaHvA',
      mode: ReconnectMode(remoteStaticPublicKey: _fixedRemoteStaticKey),
      gate: gate,
      deviceInfo: _testDeviceInfo,
    );

    expect(result, isA<Err<void>>());
    final err = result as Err<void>;
    expect(err.cause, isA<RelayConnectException>());
    expect(
      (err.cause! as RelayConnectException).failure,
      RelayConnectFailure.webSocketFailed,
    );
    expect(
      err.message.contains('n6Loxf94CfyIO6hOxlaHvA'),
      isFalse,
      reason: 'the routing handle MUST NOT appear in the error message',
    );
    expect(
      (err.cause! as RelayConnectException).message.contains(
        'n6Loxf94CfyIO6hOxlaHvA',
      ),
      isFalse,
      reason: 'the routing handle MUST NOT appear in the exception message',
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('connect() fails cleanly with no session when the app is biometrically '
      'locked (R-13-064)', () async {
    final localAuth = _MockLocalAuthentication();
    final keystore = _MockKeystoreService();
    final lockedGate = BiometricGate(
      appLockEnabled: true,
      localAuth: localAuth,
      keystore: keystore,
      setNativeLocked: (_) {},
    );
    expect(lockedGate.isLocked, isTrue);
    expect(lockedGate.deviceStaticKey, isNull);

    final relay = RelayConnection(
      handshaker: _fakeHandshaker,
      connectivityWatcher: _noOpConnectivityWatcher(),
    );
    addTearDown(relay.dispose);
    final origin = (parseRelayOrigin(
      'https://relay.example.com',
    ) as Ok<RelayOrigin>).value;

    final result = await relay.connect(
      origin: origin,
      handle: 'h1',
      mode: ReconnectMode(remoteStaticPublicKey: _fixedRemoteStaticKey),
      gate: lockedGate,
      deviceInfo: _testDeviceInfo,
    );

    expect(result, isA<Err<void>>());
    expect(
      ((result as Err<void>).cause! as RelayConnectException).failure,
      RelayConnectFailure.deviceLocked,
    );
    expect(relay.isConnected, isFalse);
  });
}
