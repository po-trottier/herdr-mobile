/// Proves `RelayConnection` (`app/lib/services/relay.dart`, `WP-14-a`) resumes a reconnect
/// by sending `tree_request` first, then `watch_pane` for the pane it was previously
/// watching — and nothing else, in particular no replay-style request (R-11-084, R-11-085).
///
/// Drives a real local `dart:io` `WebSocket` server as the fake Host counterpart, so the
/// real WebSocket transport, the real JSON frame envelope, and the real AEAD frame
/// encryption all run for real. Only the Noise handshake negotiation itself is stubbed via
/// [RelayConnection]'s injectable `handshaker`, using [NoiseCipher.withKey] on a fixed,
/// pre-agreed key both ends of this test share — the handshake's own byte-for-byte
/// correctness is proven separately, by `noise.dart`'s own interop check against the real
/// Rust responder.
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

/// A [ConnectivityWatcher] over a mocked `connectivity_plus` `Connectivity` whose change
/// stream never fires, so [RelayConnection]'s constructor never touches the real platform
/// channel `connectivity_plus` needs (unavailable under plain `flutter_test`).
ConnectivityWatcher _noOpConnectivityWatcher() {
  final connectivity = _MockConnectivity();
  when(() => connectivity.onConnectivityChanged)
      .thenAnswer((_) => const Stream<List<ConnectivityResult>>.empty());
  return ConnectivityWatcher(connectivity: connectivity);
}

class _MockKeystoreService extends Mock implements KeystoreService {}

// Fixed, non-secret test-only keys: never used outside this file. Every connection this
// file opens gets a brand-new [NoiseCipher] instance on both ends (fresh nonce counters), so
// reusing the same key bytes across sequential test connections causes no cross-connection
// interaction — only real production sessions carry a real, freshly negotiated key.
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

/// Reads the next fully-reassembled message the Device sends, from the fake Host's point
/// of view: the Host decrypts and reassembles fragments with the Device's send key
/// (mirroring [_deviceSendKey]), the same [decodeFragment] path `relay.dart`'s own
/// `_pumpIncoming` uses (`WP-14-a`/`WP-14-b` compression+fragmentation wiring).
Future<Message> _readDeviceMessage(
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
    final frame = Frame.fromJson(
      jsonDecode(utf8.decode(envelopeBytes)) as Map<String, dynamic>,
    );
    return messageFromTypeAndPayload(frame.type, frame.payload);
  }
}

/// Compresses, fragments and encrypts one message as the fake Host: the Host encrypts
/// with the Device's receive key (mirroring [_deviceReceiveKey]), the same [encodeFrame]
/// path `relay.dart`'s own `_sendFrame` uses.
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
  test('a reconnect sends tree_request then the previously watched pane\'s '
      'watch_pane, and nothing else (R-11-084, R-11-085)', () async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    addTearDown(() => server.close(force: true));

    final firstConnection = Completer<WebSocket>();
    final secondConnection = Completer<WebSocket>();
    var connectionCount = 0;
    server.listen((request) async {
      final ws = await WebSocketTransformer.upgrade(request);
      connectionCount++;
      if (connectionCount == 1) {
        firstConnection.complete(ws);
      } else {
        secondConnection.complete(ws);
      }
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

    // --- First connection: establishes the session; no pane watched yet, so resume
    // sends only tree_request. ---
    final connect1 = relay.connect(
      origin: origin,
      handle: 'h1',
      mode: ReconnectMode(remoteStaticPublicKey: _fixedRemoteStaticKey),
      gate: gate,
      deviceInfo: _testDeviceInfo,
    );

    final ws1 = await firstConnection.future;
    final iterator1 = StreamIterator<dynamic>(ws1);
    await iterator1.moveNext(); // device_register
    ws1.add(jsonEncode({'type': 'session_joined', 'role': 'device'}));
    final hostSend1 = NoiseCipher.withKey(_deviceReceiveKey);
    final hostReceive1 = NoiseCipher.withKey(_deviceSendKey);
    final hostReassembler1 = Reassembler();
    await _sendHostMessage(
      ws1,
      hostSend1,
      const Message.hostInfo(_testHostInfo),
      1,
    );

    final deviceInfoMessage = await _readDeviceMessage(
      iterator1,
      hostReceive1,
      hostReassembler1,
    );
    expect(deviceInfoMessage, isA<MessageDeviceInfo>());

    final firstResume = await _readDeviceMessage(
      iterator1,
      hostReceive1,
      hostReassembler1,
    );
    expect(
      firstResume,
      isA<MessageTreeRequest>(),
      reason: 'R-11-084: connecting sends tree_request',
    );

    expect(await connect1, isA<Ok<void>>());

    // The app now watches a pane.
    relay.watchPane('w1:p1');
    final watchMessage = await _readDeviceMessage(
      iterator1,
      hostReceive1,
      hostReassembler1,
    );
    expect(watchMessage, isA<MessageWatchPane>());
    expect((watchMessage as MessageWatchPane).payload.paneId, 'w1:p1');

    // --- Second connection: the reconnect under test. Resume MUST send tree_request
    // first, then watch_pane for 'w1:p1', and nothing else (no replay/scroll request). ---
    final connect2 = relay.connect(
      origin: origin,
      handle: 'h1',
      mode: ReconnectMode(remoteStaticPublicKey: _fixedRemoteStaticKey),
      gate: gate,
      deviceInfo: _testDeviceInfo,
    );

    final ws2 = await secondConnection.future;
    final iterator2 = StreamIterator<dynamic>(ws2);
    await iterator2.moveNext(); // device_register
    ws2.add(jsonEncode({'type': 'session_joined', 'role': 'device'}));
    final hostSend2 = NoiseCipher.withKey(_deviceReceiveKey);
    final hostReceive2 = NoiseCipher.withKey(_deviceSendKey);
    final hostReassembler2 = Reassembler();
    await _sendHostMessage(
      ws2,
      hostSend2,
      const Message.hostInfo(_testHostInfo),
      1,
    );

    final deviceInfoMessage2 = await _readDeviceMessage(
      iterator2,
      hostReceive2,
      hostReassembler2,
    );
    expect(deviceInfoMessage2, isA<MessageDeviceInfo>());

    final resumeMessage1 = await _readDeviceMessage(
      iterator2,
      hostReceive2,
      hostReassembler2,
    );
    expect(
      resumeMessage1,
      isA<MessageTreeRequest>(),
      reason: 'R-11-084: resume MUST send tree_request first',
    );

    final resumeMessage2 = await _readDeviceMessage(
      iterator2,
      hostReceive2,
      hostReassembler2,
    );
    expect(
      resumeMessage2,
      isA<MessageWatchPane>(),
      reason: 'R-11-084: resume MUST re-send watch_pane for the watched pane',
    );
    expect((resumeMessage2 as MessageWatchPane).payload.paneId, 'w1:p1');

    // R-11-085: no replay buffer, no further catch-up request follows.
    await expectLater(
      iterator2.moveNext().timeout(const Duration(milliseconds: 300)),
      throwsA(isA<TimeoutException>()),
      reason: 'resume MUST send nothing beyond tree_request and watch_pane',
    );

    expect(await connect2, isA<Ok<void>>());
  }, timeout: const Timeout(Duration(seconds: 30)));
}
