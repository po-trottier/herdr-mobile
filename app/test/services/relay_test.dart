/// Proves `RelayConnection.connect()` (`app/lib/services/relay.dart`) never falls back to
/// a mismatched relay protocol version in either direction (R-23-046, R-23-047; R-11-133's
/// "the side with the higher version sends the error"), that a successful connect's own
/// log line never carries the routing handle (R-41-031, `_originOnly`), and that the state
/// machine publishes the staged progress of `docs/03-product-decisions.md` R-03-113 item 3
/// and reconnects from the cached handle first, per item 7.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart';
import 'package:herdr_mobile/models/frame.dart';
import 'package:herdr_mobile/models/message.dart';
import 'package:herdr_mobile/models/messages/device_info.dart';
import 'package:herdr_mobile/models/messages/host_info.dart';
import 'package:herdr_mobile/models/messages/platform.dart' as wire;
import 'package:herdr_mobile/models/messages/send_input.dart';
import 'package:herdr_mobile/models/messages/tree_request.dart';
import 'package:herdr_mobile/services/biometric_gate.dart';
import 'package:herdr_mobile/services/connectivity.dart';
import 'package:herdr_mobile/services/frame_codec.dart';
import 'package:herdr_mobile/services/keystore.dart';
import 'package:herdr_mobile/services/noise.dart';
import 'package:herdr_mobile/services/origin.dart';
import 'package:herdr_mobile/services/relay.dart';
import 'package:local_auth/local_auth.dart';
import 'package:logging/logging.dart';
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

// Fixed, non-secret test-only keys: never used outside this file.
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

/// Reads and reassembles the next full [Frame] the Device sends, from the fake Host's point
/// of view: the Host decrypts with the Device's send key (mirroring [_deviceSendKey]), the
/// same [decodeFragment] path `relay.dart`'s own `_pumpIncoming` uses.
Future<Frame> _readDeviceFrame(
  StreamIterator<dynamic> iterator,
  NoiseCipher hostReceivesWithDeviceSendKey,
  Reassembler hostReassembler,
) async {
  while (true) {
    await iterator.moveNext();
    final raw = iterator.current as List<int>;
    final outcome = await decodeFragment(
      hostReassembler,
      hostReceivesWithDeviceSendKey,
      Uint8List.fromList(raw),
    );
    final envelopeBytes = (outcome as Ok<Uint8List?>).value;
    if (envelopeBytes == null) {
      continue;
    }
    return Frame.fromJson(
      jsonDecode(utf8.decode(envelopeBytes)) as Map<String, dynamic>,
    );
  }
}

const _testDeviceInfo = DeviceInfo(
  protocol: frameProtocolVersion,
  deviceId: 'device-1',
  deviceName: 'Test Phone',
  platform: wire.Platform.android,
  osVersion: '14',
  appVersion: '0.1.0',
);

HostInfo _hostInfoWithProtocol(int protocol) => HostInfo(
  protocol: protocol,
  hostId: 'host-1',
  hostName: 'test-host',
  herdrVersion: '1.0.0',
  herdrProtocol: 20,
  paired: true,
);

/// One word per state, so a whole sequence compares as a list of strings.
String _describe(RelayConnectionState state) => switch (state) {
  RelayConnecting(:final stage) => 'connecting:${stage.name}',
  RelayConnected() => 'connected',
  RelayDisconnected(:final failedStage) =>
    'disconnected:${failedStage?.name ?? '-'}',
  RelayReconnecting() => 'reconnecting',
  RelayRegistrationError(:final code) => 'refused:${code.wireValue}',
  RelayRevoked() => 'revoked',
};

/// A fake relay: every upgraded socket and the path it was opened on, in arrival order.
final class _FakeRelay {
  _FakeRelay._(this._server);

  static Future<_FakeRelay> start() async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    final relay = _FakeRelay._(server);
    server.listen((request) async {
      relay.paths.add(request.uri.path);
      relay.connections.add(await WebSocketTransformer.upgrade(request));
    });
    addTearDown(() => server.close(force: true));
    return relay;
  }

  final HttpServer _server;
  final List<WebSocket> connections = <WebSocket>[];
  final List<String> paths = <String>[];

  RelayOrigin get origin => (parseRelayOrigin(
    'http://127.0.0.1:${_server.port}',
  ) as Ok<RelayOrigin>).value;

  /// Waits for connection number [index] (zero-based) to arrive.
  Future<WebSocket> connection(int index) async {
    while (connections.length <= index) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final ws = connections[index];
    addTearDown(() => ws.close());
    return ws;
  }

  /// Reads the Device's registration frame, answers `session_joined`, then sends `host_info`
  /// at [protocol], the whole Host side of one successful connect. Returns the decoded
  /// registration frame.
  static Future<Map<String, dynamic>> joinAndGreet(
    WebSocket ws,
    StreamIterator<dynamic> iterator, {
    int protocol = frameProtocolVersion,
  }) async {
    await iterator.moveNext();
    final registration =
        jsonDecode(iterator.current as String) as Map<String, dynamic>;
    ws.add(jsonEncode({'type': 'session_joined', 'role': 'device'}));
    await _sendHostMessage(
      ws,
      NoiseCipher.withKey(_deviceReceiveKey),
      Message.hostInfo(_hostInfoWithProtocol(protocol)),
      1,
    );
    return registration;
  }
}

void main() {
  test('rapid input preserves every encrypted payload and sequence', () async {
    final fake = await _FakeRelay.start();
    final gate = await _unlockedGate();
    final relay = RelayConnection(
      handshaker: _fakeHandshaker,
      connectivityWatcher: _noOpConnectivityWatcher(),
    );
    addTearDown(relay.dispose);
    final connected = relay.connect(
      origin: fake.origin,
      handle: 'h1',
      mode: PairingMode(psk: Uint8List(32)),
      gate: gate,
      deviceInfo: _testDeviceInfo,
    );
    final ws = await fake.connection(0);
    final iterator = StreamIterator<dynamic>(ws);
    await _FakeRelay.joinAndGreet(ws, iterator);
    expect(await connected, isA<Ok<void>>());
    final cipher = NoiseCipher.withKey(_deviceSendKey);
    final reassembler = Reassembler();
    final initial = await _readDeviceFrame(iterator, cipher, reassembler);
    final sample = 'Fast typing keeps  every space, letter, é, 中, and 🧑‍💻. '
        .runes
        .toList();
    final inputs = List.generate(
      600,
      (i) => String.fromCharCode(sample[i % sample.length]),
    );
    // Back-to-back dispatch without awaiting encryption or acknowledgements.
    for (var i = 0; i < inputs.length; i++) {
      relay.send(
        Message.sendInput(SendInput(paneId: 'w1:p1', text: inputs[i])),
        corr: 'burst-$i',
      );
    }
    for (var i = 0; i < inputs.length; i++) {
      final frame = await _readDeviceFrame(iterator, cipher, reassembler);
      expect(frame.seq, initial.seq + i + 1);
      expect(frame.corr, 'burst-$i');
      expect(frame.payload['text'], inputs[i]);
    }
  });

  for (final token in <String?>[null, 'initial']) {
    test('push registration follows session_joined: token $token', () async {
      final fake = await _FakeRelay.start();
      final gate = await _unlockedGate();
      final relay = RelayConnection(
        handshaker: _fakeHandshaker,
        connectivityWatcher: _noOpConnectivityWatcher(),
      );
      addTearDown(relay.dispose);
      relay.setPushToken(token, platform: 'android');
      for (var attempt = 0; attempt < 2; attempt++) {
        final connected = relay.connect(
          origin: fake.origin,
          handle: 'h1',
          mode: PairingMode(psk: Uint8List(32)),
          gate: gate,
          deviceInfo: _testDeviceInfo,
        );
        final ws = await fake.connection(attempt);
        final iterator = StreamIterator<dynamic>(ws);
        final registration = await _FakeRelay.joinAndGreet(ws, iterator);
        expect(registration['type'], 'device_register');
        expect(await connected, isA<Ok<void>>());
        if (token != null) {
          await iterator.moveNext();
          expect(jsonDecode(iterator.current as String), {
            'type': 'push_register',
            'platform': 'android',
            'token': attempt == 0 ? token : 'rotated',
          });
        }
        final deviceInfo = await _readDeviceFrame(
          iterator,
          NoiseCipher.withKey(_deviceSendKey),
          Reassembler(),
        );
        expect(deviceInfo.type, 'device_info');
        if (token != null && attempt == 0) {
          relay.setPushToken('rotated', platform: 'android');
          await iterator.moveNext();
          expect(jsonDecode(iterator.current as String), {
            'type': 'push_register',
            'platform': 'android',
            'token': 'rotated',
          });
        }
      }
    });
  }
  for (final unlockAgain in [false, true]) {
    test(
      'a lock rejects a handshake already in flight, unlocked again: $unlockAgain',
      () async {
        final fake = await _FakeRelay.start();
        final gate = await _unlockedGate();
        final handshakeStarted = Completer<void>();
        final finishHandshake = Completer<void>();
        final relay = RelayConnection(
          handshaker: (iterator, channel, mode, gate, localStatic) async {
            handshakeStarted.complete();
            await finishHandshake.future;
            return _fakeHandshaker(iterator, channel, mode, gate, localStatic);
          },
          connectivityWatcher: _noOpConnectivityWatcher(),
        );
        addTearDown(relay.dispose);
        final result = relay.connect(
          origin: fake.origin,
          handle: 'test-handle',
          mode: ReconnectMode(remoteStaticPublicKey: _fixedRemoteStaticKey),
          gate: gate,
          deviceInfo: _testDeviceInfo,
        );
        final ws = await fake.connection(0);
        await _FakeRelay.joinAndGreet(ws, StreamIterator<dynamic>(ws));
        await handshakeStarted.future;
        gate.noteLifecycleChange(AppLifecycleState.detached);
        if (unlockAgain) expect(await gate.unlock(), isA<Ok<void>>());
        finishHandshake.complete();

        expect(await result, isA<Err<void>>());
        expect(relay.isConnected, isFalse);
        expect(gate.isLocked, !unlockAgain);
      },
    );
  }

  test('locking closes a live session and discards its queued send', () async {
    final fake = await _FakeRelay.start();
    final gate = await _unlockedGate();
    final relay = RelayConnection(
      handshaker: _fakeHandshaker,
      connectivityWatcher: _noOpConnectivityWatcher(),
    );
    addTearDown(relay.dispose);
    final result = relay.connect(
      origin: fake.origin,
      handle: 'test-handle',
      mode: PairingMode(psk: Uint8List(32)),
      gate: gate,
      deviceInfo: _testDeviceInfo,
    );
    final ws = await fake.connection(0);
    final incoming = StreamIterator<dynamic>(ws);
    await _FakeRelay.joinAndGreet(ws, incoming);
    expect(await result, isA<Ok<void>>());
    final frame = await _readDeviceFrame(
      incoming,
      NoiseCipher.withKey(_deviceSendKey),
      Reassembler(),
    );
    expect(frame.type, 'device_info');
    relay.send(const Message.treeRequest(TreeRequest()));
    gate.noteLifecycleChange(AppLifecycleState.detached);

    expect(relay.isConnected, isFalse);
    expect(
      () => relay.send(const Message.treeRequest(TreeRequest())),
      throwsA(isA<RelayNotConnectedException>()),
    );
    expect(await incoming.moveNext(), isFalse);
  });

  for (final locking in [true, false]) {
    test(
      'interruption during real Noise initialization fails safely, locking: $locking',
      () async {
        final fake = await _FakeRelay.start();
        final gate = await _unlockedGate();
        final relay = RelayConnection(
          connectivityWatcher: _noOpConnectivityWatcher(),
        );
        addTearDown(relay.dispose);
        final subscription = relay.connectionState.listen((state) {
          if (state is RelayConnecting &&
              state.stage == ConnectionStage.handshake) {
            if (locking) {
              gate.noteLifecycleChange(AppLifecycleState.detached);
            } else {
              unawaited(relay.noteLifecycleChange(AppLifecycleState.paused));
            }
          }
        });
        addTearDown(subscription.cancel);
        final result = relay.connect(
          origin: fake.origin,
          handle: 'test-handle',
          mode: ReconnectMode(remoteStaticPublicKey: _fixedRemoteStaticKey),
          gate: gate,
          deviceInfo: _testDeviceInfo,
        );
        final ws = await fake.connection(0);
        final incoming = StreamIterator<dynamic>(ws);
        await incoming.moveNext();
        ws.add(jsonEncode({'type': 'session_joined', 'role': 'device'}));

        expect(await result, isA<Err<void>>());
        expect(relay.isConnected, isFalse);
        expect(await incoming.moveNext(), isFalse);
        await ws.close();
      },
    );
  }

  test('foreground reconnect waits until the gate is unlocked', () async {
    final fake = await _FakeRelay.start();
    final gate = await _unlockedGate();
    final relay = RelayConnection(
      handshaker: _fakeHandshaker,
      connectivityWatcher: _noOpConnectivityWatcher(),
    );
    addTearDown(relay.dispose);
    final result = relay.connect(
      origin: fake.origin,
      handle: 'test-handle',
      mode: ReconnectMode(remoteStaticPublicKey: _fixedRemoteStaticKey),
      gate: gate,
      deviceInfo: _testDeviceInfo,
    );
    final ws = await fake.connection(0);
    await _FakeRelay.joinAndGreet(ws, StreamIterator<dynamic>(ws));
    expect(await result, isA<Ok<void>>());
    await relay.noteLifecycleChange(AppLifecycleState.paused);
    gate.noteLifecycleChange(AppLifecycleState.detached);
    await relay.noteLifecycleChange(AppLifecycleState.resumed);
    expect(fake.connections, hasLength(1));
    expect(relay.isConnected, isFalse);

    expect(await gate.unlock(), isA<Ok<void>>());
    final resumed = await fake
        .connection(1)
        .timeout(const Duration(seconds: 3));
    await _FakeRelay.joinAndGreet(resumed, StreamIterator<dynamic>(resumed));
    await relay.connectionState.firstWhere((state) => state is RelayConnected);
    expect(relay.isConnected, isTrue);
  });

  test('a frame that finishes decoding after lock is not published', () async {
    final fake = await _FakeRelay.start();
    final gate = await _unlockedGate();
    var lockOnDecode = false;
    final lockedDuringDecode = Completer<void>();
    final relay = RelayConnection(
      handshaker: _fakeHandshaker,
      connectivityWatcher: _noOpConnectivityWatcher(),
      now: () {
        // Reassembly reads the clock after asynchronous decryption. Lock at that
        // boundary, before the decoded payload can be published to UI listeners.
        if (lockOnDecode) {
          lockOnDecode = false;
          gate.noteLifecycleChange(AppLifecycleState.detached);
          lockedDuringDecode.complete();
        }
        return DateTime.utc(2026);
      },
    );
    addTearDown(relay.dispose);
    final received = <Message>[];
    final subscription = relay.messages.listen(received.add);
    addTearDown(subscription.cancel);
    final result = relay.connect(
      origin: fake.origin,
      handle: 'test-handle',
      mode: PairingMode(psk: Uint8List(32)),
      gate: gate,
      deviceInfo: _testDeviceInfo,
    );
    final ws = await fake.connection(0);
    final incoming = StreamIterator<dynamic>(ws);
    await incoming.moveNext();
    ws.add(jsonEncode({'type': 'session_joined', 'role': 'device'}));
    final hostCipher = NoiseCipher.withKey(_deviceReceiveKey);
    await _sendHostMessage(
      ws,
      hostCipher,
      Message.hostInfo(_hostInfoWithProtocol(frameProtocolVersion)),
      1,
    );
    expect(await result, isA<Ok<void>>());
    lockOnDecode = true;
    await _sendHostMessage(
      ws,
      hostCipher,
      const Message.treeRequest(TreeRequest()),
      2,
    );
    await lockedDuringDecode.future;
    await Future<void>.delayed(Duration.zero);

    expect(received, isEmpty);
    expect(relay.framesIn, 0);
    expect(relay.isConnected, isFalse);
  });

  test(
    'locking discards a decoded message queued for a paused listener',
    () async {
      final fake = await _FakeRelay.start();
      final gate = await _unlockedGate();
      final relay = RelayConnection(
        handshaker: _fakeHandshaker,
        connectivityWatcher: _noOpConnectivityWatcher(),
      );
      addTearDown(relay.dispose);
      final received = <Message>[];
      final subscription = relay.messages.listen(received.add)..pause();
      addTearDown(subscription.cancel);
      final result = relay.connect(
        origin: fake.origin,
        handle: 'test-handle',
        mode: PairingMode(psk: Uint8List(32)),
        gate: gate,
        deviceInfo: _testDeviceInfo,
      );
      final ws = await fake.connection(0);
      final incoming = StreamIterator<dynamic>(ws);
      await incoming.moveNext();
      ws.add(jsonEncode({'type': 'session_joined', 'role': 'device'}));
      final hostCipher = NoiseCipher.withKey(_deviceReceiveKey);
      await _sendHostMessage(
        ws,
        hostCipher,
        Message.hostInfo(_hostInfoWithProtocol(frameProtocolVersion)),
        1,
      );
      expect(await result, isA<Ok<void>>());
      await _sendHostMessage(
        ws,
        hostCipher,
        const Message.treeRequest(TreeRequest()),
        2,
      );
      while (relay.framesIn == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      gate.noteLifecycleChange(AppLifecycleState.detached);
      subscription.resume();
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
    },
  );

  for (final completeHandshake in [false, true]) {
    test(
      'cancelled pairing switch cannot reconnect: handshake complete $completeHandshake',
      () async {
        final fake = await _FakeRelay.start();
        final changes = StreamController<List<ConnectivityResult>>();
        final connectivity = _MockConnectivity();
        when(() => connectivity.onConnectivityChanged)
            .thenAnswer((_) => changes.stream);
        final watcher = ConnectivityWatcher(
          connectivity: connectivity,
          debounce: Duration.zero,
        );
        final relay = RelayConnection(
          handshaker: _fakeHandshaker,
          connectivityWatcher: watcher,
        );
        addTearDown(relay.dispose);
        addTearDown(changes.close);
        final gate = await _unlockedGate();
        final first = relay.connect(
          origin: fake.origin,
          handle: 'first',
          mode: PairingMode(psk: Uint8List(32)),
          gate: gate,
          deviceInfo: _testDeviceInfo,
        );
        final previousSocket = await fake.connection(0);
        final previousFrames = StreamIterator<dynamic>(previousSocket);
        await _FakeRelay.joinAndGreet(previousSocket, previousFrames);
        expect(await first, isA<Ok<void>>());
        final cancellation = PairingCancellation();
        final second = relay.connect(
          origin: fake.origin,
          handle: 'second',
          mode: PairingMode(psk: Uint8List(32)),
          gate: gate,
          deviceInfo: _testDeviceInfo,
          cancellation: cancellation,
        );
        final cancelled = completeHandshake
            ? null
            : expectLater(second, throwsA(isA<PairingCancelledException>()));
        final pendingSocket = await fake.connection(1);
        final pendingFrames = StreamIterator<dynamic>(pendingSocket);
        if (completeHandshake) {
          await _FakeRelay.joinAndGreet(pendingSocket, pendingFrames);
          expect(await second, isA<Ok<void>>());
        } else {
          await pendingFrames.moveNext();
        }
        expect(cancellation.disconnectedHost, isTrue);
        cancellation.cancel();
        if (cancelled != null) await cancelled;
        final states = <RelayConnectionState>[];
        final subscription = relay.connectionState.listen(states.add);
        addTearDown(subscription.cancel);
        final stable = watcher.onNetworkStable.first;
        changes.add([ConnectivityResult.wifi]);
        await stable;
        await Future<void>.delayed(Duration.zero);
        expect(states.whereType<RelayReconnecting>(), isEmpty);
        expect(relay.isConnected, isFalse);
        await previousFrames.cancel();
        await pendingFrames.cancel();
      },
    );
  }
  test('host_theme keeps the latest palette in lastHostInfo', () async {
    final fake = await _FakeRelay.start();
    final gate = await _unlockedGate();
    final relay = RelayConnection(
      handshaker: _fakeHandshaker,
      connectivityWatcher: _noOpConnectivityWatcher(),
    );
    addTearDown(relay.dispose);
    final connected = relay.connect(
      origin: fake.origin,
      handle: 'h1',
      mode: PairingMode(psk: Uint8List(32)),
      gate: gate,
      deviceInfo: _testDeviceInfo,
    );
    final ws = await fake.connection(0);
    final iterator = StreamIterator<dynamic>(ws);
    await iterator.moveNext();
    ws.add(jsonEncode({'type': 'session_joined', 'role': 'device'}));
    final hostSend = NoiseCipher.withKey(_deviceReceiveKey);
    final initialInfo = _hostInfoWithProtocol(frameProtocolVersion);
    await _sendHostMessage(ws, hostSend, Message.hostInfo(initialInfo), 1);
    expect(await connected, isA<Ok<void>>());
    expect(relay.lastHostInfo, initialInfo);

    for (final name in ['first', 'latest']) {
      final update = messageFromTypeAndPayload('host_theme', {
        'theme': {
          'name': name,
          for (final key in [
            'accent',
            'panel_bg',
            'surface0',
            'surface1',
            'surface_dim',
            'overlay0',
            'overlay1',
            'text',
            'subtext0',
            'mauve',
            'green',
            'yellow',
            'red',
            'blue',
            'teal',
            'peach',
          ])
            key: name == 'first' ? '#112233' : '#abcdef',
        },
      }) as MessageHostTheme;
      final received = relay.messages.firstWhere(
        (message) => message is MessageHostTheme,
      );
      await _sendHostMessage(ws, hostSend, update, name == 'first' ? 2 : 3);
      await received;
      expect(
        relay.lastHostInfo,
        initialInfo.copyWith(theme: update.payload.theme),
      );
    }
  }, timeout: const Timeout(Duration(seconds: 30)));
  test('a Host on an older relay protocol never gets a fallback connection: the app sends '
      'protocol_mismatch (R-11-133: the higher version sends it) and connect() fails with no '
      'session established (R-23-046)', () async {
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
    // frameProtocolVersion is 1: this Host speaks 0, an older version V.
    await _sendHostMessage(
      ws,
      hostSend,
      Message.hostInfo(_hostInfoWithProtocol(0)),
      1,
    );

    final hostReceive = NoiseCipher.withKey(_deviceSendKey);
    final hostReassembler = Reassembler();
    final errorFrame = await _readDeviceFrame(
      iterator,
      hostReceive,
      hostReassembler,
    );
    expect(
      errorFrame.payload['code'],
      'protocol_mismatch',
      reason:
          'the app is the higher-version side, so it sends the error '
          '(R-11-133)',
    );

    final result = await connectResult;
    expect(result, isA<Err<void>>());
    final cause = (result as Err<void>).cause! as RelayConnectException;
    expect(cause.failure, RelayConnectFailure.protocolMismatch);
    expect(
      relay.isConnected,
      isFalse,
      reason: 'no fallback to the Host older version V',
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  test(
    'a Host on a newer relay protocol never gets a fallback connection: the app never '
    'speaks and connect() fails with no session established (R-23-047)',
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
      // frameProtocolVersion is 1: this Host speaks 2, a newer version N — the app is the
      // older, lower-version side, so per R-11-133 it never sends protocol_mismatch itself.
      await _sendHostMessage(
        ws,
        hostSend,
        Message.hostInfo(_hostInfoWithProtocol(2)),
        1,
      );

      final result = await connectResult;
      expect(result, isA<Err<void>>());
      final cause = (result as Err<void>).cause! as RelayConnectException;
      expect(cause.failure, RelayConnectFailure.protocolMismatch);
      expect(
        relay.isConnected,
        isFalse,
        reason: 'no fallback to the Host newer version N',
      );

      // The app must never send a further frame on this socket: it just gives up and
      // closes cleanly (R-11-133: only the higher-version side speaks protocol_mismatch).
      final hasMore = await iterator.moveNext().timeout(
        const Duration(seconds: 5),
      );
      expect(
        hasMore,
        isFalse,
        reason:
            'the app is the lower-version side, so it never sends '
            'protocol_mismatch itself (R-11-133) — it only throws and closes',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('a successful connect() logs the origin without the routing handle '
      "(R-41-031, relay.dart's own private _originOnly helper)", () async {
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

    final records = <LogRecord>[];
    final subscription = Logger.root.onRecord.listen((record) {
      if (record.loggerName == 'RelayConnection') {
        records.add(record);
      }
    });
    addTearDown(subscription.cancel);

    // A distinctive routing handle: real handles are opaque tokens, never a short common
    // word, so this cannot pass by accidentally matching some other word in a log line.
    const handle = 'n6Loxf94CfyIO6hOxlaHvA';
    final connectResult = relay.connect(
      origin: origin,
      handle: handle,
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
      Message.hostInfo(_hostInfoWithProtocol(frameProtocolVersion)),
      1,
    );

    expect(await connectResult, isA<Ok<void>>());
    expect(
      records,
      isNotEmpty,
      reason: 'connect() logs an info line once connected',
    );
    for (final record in records) {
      expect(
        record.message.contains(handle),
        isFalse,
        reason: 'a log line MUST NOT contain the routing handle (R-41-031)',
      );
    }
  }, timeout: const Timeout(Duration(seconds: 30)));

  test(
    'a reconnect publishes every stage in order, Reusing handle first, then connected '
    '(R-03-113 item 3); a first pairing starts at Opening WebSocket',
    () async {
      final fake = await _FakeRelay.start();
      final gate = await _unlockedGate();
      final relay = RelayConnection(
        handshaker: _fakeHandshaker,
        connectivityWatcher: _noOpConnectivityWatcher(),
      );
      addTearDown(relay.dispose);
      final states = <RelayConnectionState>[];
      final subscription = relay.connectionState.listen(states.add);
      addTearDown(subscription.cancel);

      final reconnect = relay.connect(
        origin: fake.origin,
        handle: 'h1',
        mode: ReconnectMode(remoteStaticPublicKey: _fixedRemoteStaticKey),
        gate: gate,
        deviceInfo: _testDeviceInfo,
      );
      final ws = await fake.connection(0);
      await _FakeRelay.joinAndGreet(ws, StreamIterator<dynamic>(ws));
      expect(await reconnect, isA<Ok<void>>());
      await Future<void>.delayed(Duration.zero);
      expect(states.map(_describe), <String>[
        'connecting:reusingHandle',
        'connecting:openingSocket',
        'connecting:registeringHandle',
        'connecting:handshake',
        'connecting:hostInfo',
        'connected',
      ]);

      states.clear();
      final pairing = relay.connect(
        origin: fake.origin,
        handle: 'h2',
        mode: PairingMode(psk: Uint8List(32)),
        gate: gate,
        deviceInfo: _testDeviceInfo,
      );
      final ws2 = await fake.connection(1);
      await _FakeRelay.joinAndGreet(ws2, StreamIterator<dynamic>(ws2));
      expect(await pairing, isA<Ok<void>>());
      await Future<void>.delayed(Duration.zero);
      expect(
        states.map(_describe).where((s) => s.startsWith('connecting')),
        <String>[
          'connecting:openingSocket',
          'connecting:registeringHandle',
          'connecting:handshake',
          'connecting:hostInfo',
        ],
        reason:
            'nothing is cached on a first pairing, so no Reusing handle stage',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('a handshake failure publishes the failed stage with the raw error text (R-30-803)', () async {
    final fake = await _FakeRelay.start();
    final gate = await _unlockedGate();
    final relay = RelayConnection(
      handshaker: (iterator, channel, mode, gate, localStatic) async {
        throw const RelayConnectException(
          RelayConnectFailure.handshakeFailed,
          'the Noise handshake failed: FormatException',
        );
      },
      connectivityWatcher: _noOpConnectivityWatcher(),
    );
    addTearDown(relay.dispose);
    final states = <RelayConnectionState>[];
    final subscription = relay.connectionState.listen(states.add);
    addTearDown(subscription.cancel);

    final result = relay.connect(
      origin: fake.origin,
      handle: 'h1',
      mode: ReconnectMode(remoteStaticPublicKey: _fixedRemoteStaticKey),
      gate: gate,
      deviceInfo: _testDeviceInfo,
    );
    final ws = await fake.connection(0);
    final iterator = StreamIterator<dynamic>(ws);
    await iterator.moveNext(); // device_register
    ws.add(jsonEncode({'type': 'session_joined', 'role': 'device'}));

    expect(await result, isA<Err<void>>());
    await ws.close();
    await Future<void>.delayed(Duration.zero);
    final last = states.last as RelayDisconnected;
    expect(last.failedStage, ConnectionStage.handshake);
    expect(last.failure, 'the Noise handshake failed: FormatException');
    expect(_describe(states[states.length - 2]), 'connecting:handshake');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('after the link drops, the automatic reconnect registers the cached handle on the same '
      'path with Noise_KK and no pairing field, and logs stage names and counts only '
      '(R-03-113 item 7, R-11-200, R-41-031)', () async {
    final fake = await _FakeRelay.start();
    final gate = await _unlockedGate();
    final modes = <NoiseHandshakeMode>[];
    final relay = RelayConnection(
      handshaker: (iterator, channel, mode, gate, localStatic) {
        modes.add(mode);
        return _fakeHandshaker(iterator, channel, mode, gate, localStatic);
      },
      connectivityWatcher: _noOpConnectivityWatcher(),
    );
    addTearDown(relay.dispose);
    final states = <RelayConnectionState>[];
    final subscription = relay.connectionState.listen(states.add);
    addTearDown(subscription.cancel);
    final records = <LogRecord>[];
    final previousLevel = Logger.root.level;
    Logger.root.level = Level.ALL;
    addTearDown(() => Logger.root.level = previousLevel);
    final logSubscription = Logger.root.onRecord.listen((record) {
      if (record.loggerName == 'RelayConnection') records.add(record);
    });
    addTearDown(logSubscription.cancel);

    const handle = 'n6Loxf94CfyIO6hOxlaHvA';
    final first = relay.connect(
      origin: fake.origin,
      handle: handle,
      mode: ReconnectMode(remoteStaticPublicKey: _fixedRemoteStaticKey),
      gate: gate,
      deviceInfo: _testDeviceInfo,
    );
    final ws = await fake.connection(0);
    await _FakeRelay.joinAndGreet(ws, StreamIterator<dynamic>(ws));
    expect(await first, isA<Ok<void>>());

    // R-11-125: the relay closes the Device when the Host is gone.
    await ws.close(1001, 'the Host is gone');

    // R-22-028's first delay is 0.5 s; the second socket arrives after it.
    final ws2 = await fake.connection(1);
    final registration = await _FakeRelay.joinAndGreet(
      ws2,
      StreamIterator<dynamic>(ws2),
    );
    while (!relay.isConnected) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await Future<void>.delayed(Duration.zero);

    expect(fake.paths, <String>['/device/$handle', '/device/$handle']);
    expect(
      registration,
      <String, Object>{
        'type': 'device_register',
        'protocol': frameProtocolVersion,
      },
      reason:
          'no pairing field: R-11-114 registers the handle and nothing else',
    );
    expect(modes, hasLength(2));
    expect(
      modes[1],
      isA<ReconnectMode>(),
      reason: 'Noise_KK, never a new pairing',
    );
    final described = states.map(_describe).toList();
    final dropAt = described.indexOf('disconnected:-');
    expect(dropAt, greaterThan(0));
    expect(described.sublist(dropAt), <String>[
      'disconnected:-',
      'reconnecting',
      'connecting:reusingHandle',
      'connecting:openingSocket',
      'connecting:registeringHandle',
      'connecting:handshake',
      'connecting:hostInfo',
      'connected',
    ]);
    expect(
      records.map((r) => r.message),
      contains('reconnect attempt 1: reusing the cached handle'),
    );
    expect(
      records.map((r) => r.message),
      contains('connection stage: reusingHandle'),
    );
    for (final record in records) {
      expect(
        record.message.contains(handle),
        isFalse,
        reason: 'a log line MUST NOT contain the routing handle (R-41-031)',
      );
    }
  }, timeout: const Timeout(Duration(seconds: 30)));
}
