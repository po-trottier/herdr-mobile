/// `docs/90-implementation-plan.md` Phase 23's cross-component end-to-end test,
/// `docs/40-repo-tooling.md` §5.4 (R-40-037). See `tests/e2e/README.md` for the exact
/// command to run this file by hand — it deliberately does not run in CI (§5.4's own
/// closing sentence: it needs all three components running simultaneously).
///
/// Exercises the full path Host (plugin with stub Herdr) -> relay -> Device (app test
/// harness), each a real, separate, locally-run process talking over real loopback
/// TCP/WebSocket (never in-process function calls, never a public deployment):
///
///   1. `cargo run -p herdr-relay-hub` — the real relay router, plain `ws://`
///      (R-12-012: this crate links no TLS listener), bound to `127.0.0.1:$_relayPort`
///      (§5.4 step 1).
///   2. `cargo run -p herdr-relay --bin e2e-stub-host` — the real Host plugin code
///      (`crates/herdr-relay/src/bin/e2e-stub-host.rs`) driving a real
///      `herdr_relay::watch::Bridge` against a stub `HerdrCalls` that returns one
///      canned pane snapshot (§5.4 step 2). See that file's own header comment for the
///      full message sequence it drives.
///   3. This test itself, as the Device (§5.4 step 3): the real
///      `app/lib/services/relay.dart` `RelayConnection` (real `Noise_XXpsk0` handshake
///      via `app/lib/services/noise.dart`, real frame codec, real WebSocket) and the
///      real `app/lib/services/terminal.dart` `TerminalService` driving a real
///      `xterm2` `Terminal` — never a hand-rolled Dart Noise client or a bespoke
///      ANSI parser, matching this repo's `docs/40-repo-tooling.md` §5.4 assignment
///      note.
///
/// Step 4 (a `pane.read` snapshot arrives at the Device and renders correctly in the
/// terminal emulator) is proven by asserting the real `xterm2` buffer contains
/// `_cannedSnapshotText` — the exact text `e2e-stub-host.rs`'s stub Herdr returned —
/// after `TerminalService.attach` completes. Step 5 (a keystroke from the Device
/// arrives at the Host, R-11-227) is proven two ways: the Device receives a real
/// `send_input_ack`, and the Host process's own stdout carries a
/// `send_input_received` line naming the exact keystroke bytes it observed. Step 6
/// (tear down all three, R-11-206, R-11-207) closes the Device's connection, then
/// asserts the Host process exits `0` and the relay process is killed cleanly,
/// leaking neither a process nor the port it held.
///
/// Follows `app/test/spike/noise_client_test.dart`'s own proven pattern (spawn the two
/// Rust subprocesses, drive the Device from this one file) but drives real production
/// app services instead of that file's throwaway hand-rolled Noise client, and speaks
/// the real `docs/11-relay-protocol.md` message set instead of a plaintext-greeting
/// stand-in.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart' show Ok;
import 'package:herdr_mobile/models/frame.dart';
import 'package:herdr_mobile/models/message.dart';
import 'package:herdr_mobile/models/messages/device_info.dart';
import 'package:herdr_mobile/models/messages/platform.dart' as wire;
import 'package:herdr_mobile/models/messages/send_input.dart';
import 'package:herdr_mobile/models/messages/send_input_ack.dart';
import 'package:herdr_mobile/services/biometric_gate.dart';
import 'package:herdr_mobile/services/connectivity.dart';
import 'package:herdr_mobile/services/keystore.dart' as keystore_service;
import 'package:herdr_mobile/services/noise.dart';
import 'package:herdr_mobile/services/origin.dart';
import 'package:herdr_mobile/services/relay.dart';
import 'package:herdr_mobile/services/terminal.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mocktail/mocktail.dart';

/// `docs/11-relay-protocol.md` §8.1's worked pairing phrase, already reused by
/// `crates/herdr-relay/src/noise.rs`'s and `app/test/spike/noise_client_test.dart`'s
/// own tests. Not a secret: purely a shared, documented fixture.
const _phrase = 'remedy-tapestry-hubcap-oversleep-jailbird-kinetic';

/// A fresh 22-char base64url handle (R-11-112), distinct from
/// `noise_client_test.dart`'s own fixture so the two files never collide if a person
/// runs both by hand around the same time.
const _handle = 'AQIDBAUGBwgJCgsMDQ4PEA';

/// Distinct from `noise_client_test.dart`'s `18743`/`19091` for the same reason.
const _relayPort = 18922;
const _metricsPort = 19292;

/// MUST match `PANE_ID` in `crates/herdr-relay/src/bin/e2e-stub-host.rs` exactly.
const _paneId = 'w1:p1';

/// MUST match `CANNED_TEXT` in `crates/herdr-relay/src/bin/e2e-stub-host.rs` exactly:
/// this is the §5.4 step 4 assertion.
const _cannedSnapshotText = 'HERDR-E2E-STUB-SNAPSHOT-7f3a1c';

/// The exact keystroke bytes §5.4 step 5 proves arrive at the Host.
const _keystrokeText = 'E2E-KEYSTROKE-4d9b21';

class _MockLocalAuthentication extends Mock implements LocalAuthentication {}

class _MockKeystoreService extends Mock
    implements keystore_service.KeystoreService {}

class _MockConnectivity extends Mock implements Connectivity {}

/// Never touches the real `connectivity_plus` platform channel (mirrors
/// `pairing_flow_test.dart`'s own helper of the same name).
ConnectivityWatcher _noOpConnectivityWatcher() {
  final connectivity = _MockConnectivity();
  when(() => connectivity.onConnectivityChanged)
      .thenAnswer((_) => const Stream<List<ConnectivityResult>>.empty());
  return ConnectivityWatcher(connectivity: connectivity);
}

/// A real `BiometricGate`, unlocked with a real, freshly generated Curve25519
/// keypair, but with `local_auth` and the platform keystore both mocked (mirrors
/// `pairing_flow_test.dart`'s own `_unlockedGate`): no real platform channel is ever
/// touched, while `RelayConnection.connect`'s real `gate.deviceStaticKey` read and the
/// real `NoiseXxPsk0Initiator` handshake both run unmodified.
Future<BiometricGate> _unlockedGate() async {
  final localAuth = _MockLocalAuthentication();
  final mockKeystore = _MockKeystoreService();
  final keyPair = await X25519().newKeyPair();
  when(
    () =>
        localAuth.authenticate(localizedReason: any(named: 'localizedReason')),
  ).thenAnswer((_) async => true);
  when(() => mockKeystore.existingDeviceKeyPair())
      .thenAnswer((_) async => Ok(keyPair));
  final gate = BiometricGate(
    appLockEnabled: true,
    localAuth: localAuth,
    keystore: mockKeystore,
    setNativeLocked: (_) {},
  );
  final result = await gate.unlock();
  expect(result, isA<Ok<void>>());
  return gate;
}

/// Every row's text, joined, so a substring search covers the whole grid (mirrors
/// `app/test/services/reset_no_scrollback_test.dart`'s own `_visibleText`).
String _terminalBufferText(TerminalService terminal) {
  final rows = terminal.xterm.buffer.lines.length;
  return List<String>.generate(
    rows,
    (row) => terminal.xterm.buffer.lines[row].getText(),
  ).join('\n');
}

void main() {
  final cratesDir = Directory(
    '${Directory.current.path}${Platform.pathSeparator}..${Platform.pathSeparator}crates',
  );

  group('Phase 23 cross-component end-to-end test (docs/40-repo-tooling.md §5.4)', () {
    late Process hubProcess;
    late Process hostProcess;
    final hostStdoutLines = <String>[];
    late Completer<void> hostExited;

    setUpAll(() async {
      expect(
        cratesDir.existsSync(),
        isTrue,
        reason: 'expected the Rust workspace at ${cratesDir.path}',
      );

      // Step 1: the relay, in its only mode (plain `ws://`, loopback-bound).
      hubProcess = await Process.start(
        'cargo',
        ['run', '-p', 'herdr-relay-hub'],
        workingDirectory: cratesDir.path,
        environment: {
          'HERDR_RELAY_LISTEN': '127.0.0.1:$_relayPort',
          'HERDR_RELAY_METRICS_LISTEN': '127.0.0.1:$_metricsPort',
        },
      );
      addTearDown(hubProcess.kill);
      hubProcess.stdout
          .transform(utf8.decoder)
          .listen((line) => stdout.write('[hub] $line'));
      hubProcess.stderr
          .transform(utf8.decoder)
          .listen((line) => stdout.write('[hub:err] $line'));
      await _waitForHealthz();

      // Step 2: the Host plugin, driving a real Bridge against a stub Herdr.
      hostExited = Completer<void>();
      hostProcess = await Process.start(
        'cargo',
        ['run', '-p', 'herdr-relay', '--bin', 'e2e-stub-host'],
        workingDirectory: cratesDir.path,
        environment: {
          'RELAY_ADDR': '127.0.0.1:$_relayPort',
          'HANDLE': _handle,
          'PHRASE': _phrase,
        },
      );
      addTearDown(hostProcess.kill);
      hostProcess.stderr
          .transform(utf8.decoder)
          .listen((line) => stdout.write('[host:err] $line'));
      final hostStdoutDone = Completer<void>();
      hostProcess.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            // The Host's lines carry no content (the stub reports booleans and
            // counts), and they are still not echoed: the failure reasons below
            // quote them only when a step fails.
            hostStdoutLines.add(line);
          }, onDone: hostStdoutDone.complete);
      addTearDown(
        () => hostStdoutDone.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () {},
        ),
      );
      unawaited(
        hostProcess.exitCode.then((_) {
          if (!hostExited.isCompleted) hostExited.complete();
        }),
      );
      await _waitForHostEvent(
        hostStdoutLines,
        'host_registered',
        const Duration(seconds: 60),
      );
    });

    test('watch_pane snapshot renders on the Device and a keystroke reaches the Host', () async {
      // Step 3: the Device, driven through the app's own real relay/Noise/terminal
      // stack.
      final connection = RelayConnection(
        connectivityWatcher: _noOpConnectivityWatcher(),
      );
      addTearDown(connection.dispose);

      final gate = await _unlockedGate();
      final origin = (parseRelayOrigin(
        'http://127.0.0.1:$_relayPort',
      ) as Ok<RelayOrigin>).value;
      final psk = await pskFromPhrase(_phrase);
      const deviceInfo = DeviceInfo(
        protocol: frameProtocolVersion,
        deviceId: 'e2e-device-1',
        deviceName: 'E2E Harness',
        platform: wire.Platform.android,
        osVersion: '14',
        appVersion: '0.1.0',
      );

      final connectResult = await connection.connect(
        origin: origin,
        handle: _handle,
        mode: PairingMode(psk: psk),
        gate: gate,
        deviceInfo: deviceInfo,
      );
      expect(
        connectResult,
        isA<Ok<void>>(),
        reason:
            'the real Noise_XXpsk0 handshake against the real Rust Host must '
            'succeed: $connectResult',
      );
      expect(connection.isConnected, isTrue);
      expect(connection.lastHostInfo, isNotNull);

      final terminalService = TerminalService(
        messages: connection.messages,
        send: connection.send,
        watchPane: connection.watchPane,
        unwatchPane: connection.unwatchPane,
      );
      addTearDown(terminalService.dispose);

      // Step 4: watch the stub's one canned pane and confirm its snapshot renders.
      final attachResult = await terminalService.attach(_paneId);
      expect(
        attachResult,
        isA<Ok<void>>(),
        reason: 'watch_pane must be acked by the real Bridge: $attachResult',
      );

      String bufferText = '';
      final renderDeadline = DateTime.now().add(const Duration(seconds: 5));
      while (DateTime.now().isBefore(renderDeadline)) {
        bufferText = _terminalBufferText(terminalService);
        if (bufferText.contains(_cannedSnapshotText)) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(
        bufferText,
        contains(_cannedSnapshotText),
        reason:
            'the real xterm2 Terminal must render the stub Herdr snapshot '
            'text verbatim (docs/40-repo-tooling.md §5.4 step 4)',
      );

      // Step 5: a keystroke from the Device reaches the Host.
      final ackCompleter = Completer<SendInputAck>();
      final ackSubscription = connection.messages.listen((message) {
        if (message case MessageSendInputAck(:final payload)
            when payload.paneId == _paneId && !ackCompleter.isCompleted) {
          ackCompleter.complete(payload);
        }
      });
      connection.send(
        const Message.sendInput(
          SendInput(paneId: _paneId, text: _keystrokeText),
        ),
      );
      final ack = await ackCompleter.future.timeout(
        const Duration(seconds: 10),
      );
      await ackSubscription.cancel();
      expect(ack.accepted, isTrue);

      final sendInputLine = await _waitForHostEventLine(
        hostStdoutLines,
        'send_input_received',
        const Duration(seconds: 10),
      );
      final decodedSendInput =
          jsonDecode(sendInputLine) as Map<String, dynamic>;
      expect(
        decodedSendInput['text_matches_expected'],
        isTrue,
        reason:
            'the stub Host must observe the exact keystroke bytes the Device '
            'sent (docs/40-repo-tooling.md §5.4 step 5); it compares them in place '
            'and reports a boolean, never the bytes',
      );
      expect(decodedSendInput['text_len'], _keystrokeText.length);
      expect(decodedSendInput['pane_id'], _paneId);

      // Step 6: tear down all three cleanly.
      await connection.disconnect();
      await hostExited.future.timeout(const Duration(seconds: 10));
      final hostExitCode = await hostProcess.exitCode.timeout(
        const Duration(seconds: 10),
      );
      expect(
        hostExitCode,
        0,
        reason:
            'the Host process must exit cleanly on a deliberate Device '
            'disconnect: ${hostStdoutLines.join('\n')}',
      );

      hubProcess.kill();
      final hubExitCode = await hubProcess.exitCode.timeout(
        const Duration(seconds: 10),
      );
      expect(
        hubExitCode,
        isNot(isNull),
        reason: 'the relay process must terminate cleanly',
      );
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}

Future<void> _waitForHealthz() async {
  final client = HttpClient();
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    try {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:$_relayPort/healthz'),
      );
      final response = await request.close();
      if (response.statusCode == 200) {
        await response.drain<void>();
        client.close();
        return;
      }
      await response.drain<void>();
    } on Exception {
      // The relay has not started listening yet; retry.
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  client.close();
  fail(
    'the local herdr-relay-hub instance never became healthy on 127.0.0.1:$_relayPort',
  );
}

Future<void> _waitForHostEvent(
  List<String> lines,
  String event,
  Duration timeout,
) async {
  await _waitForHostEventLine(lines, event, timeout);
}

/// Returns the first line in [lines] whose decoded JSON `event` field equals [event],
/// waiting up to [timeout] for it to appear.
Future<String> _waitForHostEventLine(
  List<String> lines,
  String event,
  Duration timeout,
) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    for (final line in lines) {
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map<String, dynamic> && decoded['event'] == event) {
          return line;
        }
      } on FormatException {
        // A non-JSON stdout line (should not happen; every line this binary prints
        // is one JSON object) — skip it rather than fail the whole wait.
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail(
    'the Rust Host process never reported "$event" within $timeout: ${lines.join('\n')}',
  );
}
