/// Proves `RelayConnection._sendOn` (`app/lib/services/relay.dart`, `WP-14-a`) allocates
/// exactly one `seq` value per attempted send (R-11-033), even when `_sendFrame`'s own
/// R-11-035 pre-check rejects an oversized envelope before it ever reaches the wire
/// (R-11-036). A prior defect double-incremented `_outgoingSeq` on rejection — once for
/// the candidate frame that was never sent, once more for the `frame_too_large` reply that
/// replaced it — permanently burning a seq value and shifting every later frame's `seq` by
/// one for the rest of the connection.
///
/// `device_info` is always the connection's true first frame (R-11-131; `relay.dart`'s own
/// `connect()` sends it before returning), so it always claims `seq: 1` on a real
/// connection. This test's own first `send()` call is deliberately oversized: it MUST
/// produce a `frame_too_large` reply at `seq: 2` (immediately after `device_info`'s `1`,
/// never `3`), and a normal-sized send right after MUST land at `seq: 3` (never `4`) —
/// proving no seq value is ever skipped.
///
/// Drives a real local `dart:io` `WebSocket` server as the fake Host counterpart, decoding
/// what actually reaches the wire through `frame_codec.dart`'s own `decodeFragment`, so this
/// is a transport-level proof, not a codec-level unit test.
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

/// Reads and reassembles the next full [Frame] the Device sends, from the fake Host's
/// point of view: the Host decrypts and reassembles fragments with the Device's send key
/// (mirroring [_deviceSendKey]), the same [decodeFragment] path `relay.dart`'s own
/// `_pumpIncoming` uses. Unlike a plain `Message` read, this keeps `Frame.seq` visible —
/// exactly the field this test asserts on.
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
  test('an oversized send never burns a seq value: the frame_too_large reply reuses the '
      'rejected candidate seq instead of skipping it (R-11-033, R-11-035, R-11-036)', () async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    addTearDown(() => server.close(force: true));

    final connection = Completer<WebSocket>();
    server.listen((request) async {
      connection.complete(await WebSocketTransformer.upgrade(request));
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

    final ws = await connection.future;
    final iterator = StreamIterator<dynamic>(ws);
    await iterator.moveNext(); // device_register
    ws.add(jsonEncode({'type': 'session_joined', 'role': 'device'}));
    final hostSend = NoiseCipher.withKey(_deviceReceiveKey);
    final hostReceive = NoiseCipher.withKey(_deviceSendKey);
    final hostReassembler = Reassembler();
    await _sendHostMessage(
      ws,
      hostSend,
      const Message.hostInfo(_testHostInfo),
      1,
    );

    // device_info is the connection's real, unavoidable first frame (R-11-131) — it
    // always succeeds (small, fixed-size payload), so it always claims seq 1.
    final deviceInfoFrame = await _readDeviceFrame(
      iterator,
      hostReceive,
      hostReassembler,
    );
    expect(deviceInfoFrame.type, 'device_info');
    expect(deviceInfoFrame.seq, 1, reason: 'device_info is always seq 1');

    expect(await connectResult, isA<Ok<void>>());

    // This test's own first send: deliberately oversized (well past the 1 MiB R-11-035
    // ceiling), rejected by _sendFrame's own pre-check before it ever reaches the wire.
    final oversizedPaneId = 'x' * 1100000;
    relay.watchPane(oversizedPaneId);

    final errorFrame = await _readDeviceFrame(
      iterator,
      hostReceive,
      hostReassembler,
    );
    expect(errorFrame.type, 'error');
    expect(
      errorFrame.payload['code'],
      'frame_too_large',
      reason: 'the oversized watch_pane is replaced by a frame_too_large error',
    );
    expect(
      errorFrame.seq,
      2,
      reason:
          'the rejected candidate seq MUST be reused by its replacement, never '
          'skipped: device_info was 1, so this MUST be 2, not 3',
    );

    // A normal-sized send right after MUST land immediately after the error reply, at
    // seq 3 — proving the earlier rejection left no permanent gap.
    relay.watchPane('w1:p1');
    final watchFrame = await _readDeviceFrame(
      iterator,
      hostReceive,
      hostReassembler,
    );
    expect(watchFrame.type, 'watch_pane');
    expect((watchFrame.payload['pane_id']), 'w1:p1');
    expect(
      watchFrame.seq,
      3,
      reason:
          'no permanent drift: seq resumes immediately after the error reply',
    );
  }, timeout: const Timeout(Duration(seconds: 30)));
}
