/// Proves the R-11-238 inter-fragment timeout is an ACTIVE deadline, not just a check that
/// runs reactively when a next fragment happens to arrive
/// (`app/lib/services/frame_codec.dart`'s own `Reassembler.acceptFragment`).
///
/// Before this fix, `_readEnvelope` and `_pumpIncoming`
/// (`app/lib/services/relay.dart`) both `await iterator.moveNext()` with no timeout of
/// their own. A Host that sent fragment 0 of a multi-fragment record and then nothing else
/// — no more data, no close frame — left `iterator.moveNext()` waiting forever: nothing
/// ever called `acceptFragment` again to trigger its own elapsed-time check, so `connect()`
/// itself never resolved. This test drives exactly that scenario against `connect()`'s own
/// synchronous `host_info` read (`_readEnvelope`), the more severe of the two hang sites
/// named in the defect report, and asserts `connect()` actually resolves — with the
/// connection closed at WebSocket code `4003` — instead of hanging.
///
/// Uses `RelayConnection`'s injectable `now` clock (mirroring
/// `Reassembler.acceptFragment`'s own `now` parameter) so this never sleeps through the
/// real 10-second window: the fake clock reports the fragment-0 arrival instant on its
/// first call, then jumps 11 (fake) seconds forward on every call after — so the very next
/// deadline check `_awaitNextFragment` performs sees an already-elapsed window and fires
/// with no real timer wait at all.
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

/// High-entropy, low-compressibility filler: forces `encodeFrame`'s compression record
/// well past `maxChunkLen` (65517 bytes) even after zlib, so it always splits into at
/// least two physical fragments — a sequential or repeated string would compress down to
/// well under one fragment and prove nothing about mid-record reassembly.
String _incompressibleFiller(int chars) {
  final buffer = StringBuffer();
  var x = 0;
  for (var i = 0; i < chars ~/ 4; i++) {
    x = (x * 2654435761 + 1) & 0xffffffff;
    buffer.write((x & 0xffff).toRadixString(16).padLeft(4, '0'));
  }
  return buffer.toString();
}

final _testHostInfo = HostInfo(
  protocol: frameProtocolVersion,
  hostId: 'host-1',
  hostName: _incompressibleFiller(200000),
  herdrVersion: '1.0.0',
  herdrProtocol: 20,
  paired: true,
);

/// Returns `T0` on its first call, then `T0 + 11s` on every call after — deterministic on
/// call count, not wall-clock coordination with the test body. `acceptFragment` calls
/// `now()` exactly once per fragment (call #1, recording fragment 0's arrival at `T0`);
/// `_awaitNextFragment`'s very next deadline check is call #2, which already sees an
/// instant 11 (fake) seconds past `T0` — 1 second past the real R-11-238 10-second window
/// — so it fires immediately, with no fragment 1 ever sent and no real timer wait.
DateTime Function() _jumpingClock() {
  final t0 = DateTime.utc(2024);
  var calls = 0;
  return () {
    calls++;
    return calls == 1 ? t0 : t0.add(const Duration(seconds: 11));
  };
}

void main() {
  test('a Host that sends fragment 0 of host_info and then nothing else times out '
      'connect() with a 4003 close, instead of hanging forever (R-11-238)', () async {
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
      now: _jumpingClock(),
    );
    addTearDown(relay.dispose);

    final connectResult = relay.connect(
      origin: origin,
      handle: 'h1',
      mode: PairingMode(psk: Uint8List(32)),
      gate: gate,
      deviceInfo: const DeviceInfo(
        protocol: frameProtocolVersion,
        deviceId: 'device-1',
        deviceName: 'Test Phone',
        platform: wire.Platform.android,
        osVersion: '14',
        appVersion: '0.1.0',
      ),
    );

    final ws = await connection.future;
    addTearDown(() => ws.close());
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
    final fragments = (encoded as Ok<List<Uint8List>>).value;
    expect(
      fragments.length,
      greaterThan(1),
      reason:
          'fixture must actually split into multiple fragments, or this test proves '
          'nothing about mid-record reassembly',
    );

    // Send only fragment 0, then nothing else at all — no fragment 1, no close frame.
    ws.add(fragments[0]);

    final result = await connectResult.timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw TimeoutException(
        'connect() hung: the R-11-238 inter-fragment timeout is not an active '
        'deadline',
      ),
    );
    expect(result, isA<Err<void>>());
    expect(
      ((result as Err<void>).cause! as RelayConnectException).failure,
      RelayConnectFailure.frameReassemblyFailed,
    );

    final hasMore = await iterator.moveNext().timeout(
      const Duration(seconds: 5),
      onTimeout: () =>
          throw TimeoutException('the Device never closed the socket'),
    );
    expect(hasMore, isFalse);
    expect(
      ws.closeCode,
      4003,
      reason:
          'R-11-121: a reassembly-timeout violation closes with protocol_error',
    );
  }, timeout: const Timeout(Duration(seconds: 30)));
}
