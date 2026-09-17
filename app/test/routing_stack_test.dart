/// Proves the navigation-stack fixes made to `app/lib/routing.dart` during the
/// navigation-stack audit: the pairing-toggle swap (the reported bug, `docs/31-mockups/
/// 02-pair-scan.md`/`03-pair-code.md` Navigation), `routeNotificationTap`'s repeat-tap
/// dedupe (R-30-030, R-30-511), and `/lock`'s cold-start held-route landing together with
/// the `herdr-remote://pair` deep-link entry into `/pair/manual` (R-22-034), which the fix
/// makes land under `/hosts` rather than under a stale `/lock` page.
///
/// The pairing-toggle group drives a small local `GoRouter` shaped exactly like
/// `routing.dart`'s own `/welcome`/`/pair/scan`/`/pair/manual` push/`pushReplacement`
/// wiring, mirroring `app_shell_test.dart`'s own documented reason for a local router: the
/// real `QrScanScreen` opens a camera this test environment has no platform channel for.
/// The other two groups drive `routing.dart`'s real, exported `routeNotificationTap` and the
/// real `appRouter` directly, with only the keystore's platform channel faked out (mirroring
/// `e2e/full_stack_test.dart`'s own `_unlockedGate` precedent) — real code, not a copy.
library;

import 'dart:async' show StreamController, StreamIterator, unawaited;
import 'dart:convert' show base64Encode, jsonDecode, jsonEncode, utf8;
import 'dart:io'
    show HttpOverrides, HttpServer, WebSocket, WebSocketTransformer;
import 'dart:typed_data' show Uint8List;

import 'package:connectivity_plus/connectivity_plus.dart'
    show Connectivity, ConnectivityResult;
import 'package:cryptography/cryptography.dart' show SimpleKeyPair;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart'
    show
        AppLifecycleState,
        BuildContext,
        Center,
        Column,
        MainAxisSize,
        StatelessWidget,
        Text,
        TextButton,
        EditableText,
        ValueKey,
        VoidCallback,
        Widget;
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import 'package:flutter_secure_storage/flutter_secure_storage.dart'
    show FlutterSecureStorage;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart'
    show
        GoRoute,
        GoRouter,
        GoRouterHelper,
        GoRouterState,
        RouteBase,
        RouteMatchBase,
        RouteMatchList,
        ShellRouteMatch;
import 'package:herdr_mobile/core/result/result.dart' show Ok;
import 'package:herdr_mobile/models/frame.dart'
    show Frame, frameProtocolVersion;
import 'package:herdr_mobile/models/message.dart' show Message, MessageWire;
import 'package:herdr_mobile/models/messages/agent_status.dart'
    show AgentStatus;
import 'package:herdr_mobile/models/messages/agent_status_kind.dart'
    show AgentStatusKind;
import 'package:herdr_mobile/models/messages/device_info.dart' show DeviceInfo;
import 'package:herdr_mobile/models/messages/host_action_ack.dart';
import 'package:herdr_mobile/models/messages/host_action_kind.dart';
import 'package:herdr_mobile/models/messages/host_info.dart' show HostInfo;
import 'package:herdr_mobile/models/messages/platform.dart' as wire;
import 'package:herdr_mobile/models/messages/tree_snapshot.dart'
    show TreeSnapshot;
import 'package:herdr_mobile/routing.dart';
import 'package:herdr_mobile/screens/agent_list_screen.dart'
    show AgentListScreen;
import 'package:herdr_mobile/screens/host_list_screen.dart' show HostListScreen;
import 'package:herdr_mobile/screens/manual_pairing_screen.dart'
    show ManualPairingScreen;
import 'package:herdr_mobile/screens/notifications_screen.dart'
    show NotificationsScreen;
import 'package:herdr_mobile/screens/qr_scan_screen.dart' show QrScanScreen;
import 'package:herdr_mobile/screens/terminal_screen.dart';
import 'package:herdr_mobile/services/agent_status.dart'
    show AgentStatusService;
import 'package:herdr_mobile/services/app_settings.dart'
    show AppSettingsService;
import 'package:herdr_mobile/services/biometric_gate.dart' show BiometricGate;
import 'package:herdr_mobile/services/connectivity.dart'
    show ConnectivityWatcher;
import 'package:herdr_mobile/services/frame_codec.dart'
    show encodeFrame, decodeFragment, Reassembler;
import 'package:herdr_mobile/services/keystore.dart' show KeystoreService;
import 'package:herdr_mobile/services/noise.dart'
    show NoiseCipher, NoiseSession;
import 'package:herdr_mobile/services/notifications.dart'
    show NotificationsService;
import 'package:herdr_mobile/services/origin.dart'
    show RelayOrigin, parseRelayOrigin;
import 'package:herdr_mobile/services/pane_actions.dart'
    show notConnectedMessage;
import 'package:herdr_mobile/services/plain_store.dart'
    show NotificationAck, PairedHostRecord, PlainStore;
import 'package:herdr_mobile/services/relay.dart'
    show
        NoiseHandshakeMode,
        PairingMode,
        RelayConnected,
        RelayConnection,
        RelayConnectionState;
import 'package:material_ui/material_ui.dart' show Badge, MaterialApp;
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:web_socket_channel/web_socket_channel.dart'
    show WebSocketChannel;

import 'frame_presentation_support.dart';

class _MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

class _MockNotificationsService extends Mock implements NotificationsService {
  _MockNotificationsService() {
    // The app icon badge mirror (R-22-020) fires on every emission; stub it once here.
    when(() => setBadgeCount(any())).thenAnswer((_) async {});
    when(requestPermission).thenAnswer((_) async => true);
  }
}

class _MockPlainStore extends Mock implements PlainStore {}

/// An `AgentStatusService` over [messages] (empty by default) with a mocked
/// `NotificationsService` and an in-memory `PlainStore`, so `routeNotificationTap`'s R-30-511
/// `pane closed` check runs without a real plugin or a real `RelayConnection`. [hostId] mirrors
/// `relayConnectionProvider`'s connected Host, the one whose `tree_snapshot` the service keys
/// its pane set by.
AgentStatusService _agentStatus([Stream<Message>? messages, String? hostId]) {
  _fakePrefs();
  return AgentStatusService(
    messages: messages ?? const Stream<Message>.empty(),
    notifications: _MockNotificationsService(),
    plainStore: PlainStore(),
    currentHostId: () => hostId,
  );
}

/// A trivial stand-in screen: a title `Text` a test asserts on, and zero or more named
/// buttons a test taps by label.
class _Screen extends StatelessWidget {
  const _Screen({required this.title, this.buttons = const {}});

  final String title;
  final Map<String, VoidCallback> buttons;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(title),
        for (final entry in buttons.entries)
          TextButton(onPressed: entry.value, child: Text(entry.key)),
      ],
    ),
  );
}

/// Duplicated from `app_shell_test.dart`'s own private copy, per R-90-018/R-41-042 rung 1.
void _fakePrefs() {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
}

/// A valid 32-byte X25519 seed, base64-encoded: any 32 bytes decode to a usable seed, per
/// `keystore.dart`'s own `deviceKeyPair` (`X25519().newKeyPairFromSeed`). Lets
/// `deviceKeyPair()` -- and so `BiometricGate.unlock()` -- succeed with no
/// `flutter_secure_storage` platform channel, mirroring `e2e/full_stack_test.dart`'s own
/// `_unlockedGate` precedent.
final String _fakeDeviceKeySeed = base64Encode(List<int>.filled(32, 7));

/// Builds a mocked `FlutterSecureStorage` backing a working `keystoreServiceProvider`
/// override, so `WelcomeScreen`'s device-key read, `/pair/manual`'s saved-origin read and
/// `BiometricGate.unlock()` (which reads through the same provider) all succeed with no
/// platform channel, mirroring `keystore_test.dart`'s own `_MockFlutterSecureStorage`.
/// Returns the storage, not the override itself: `overrideWithValue`'s own `Override`
/// return type is riverpod-internal, outside `flutter_riverpod`'s public export surface, so
/// the one call site below builds the override inline where `ProviderScope.overrides`'s
/// own context infers it, exactly as any list literal passed straight to that parameter
/// would.
_MockFlutterSecureStorage _fakeDeviceKeyStorage() {
  final storage = _MockFlutterSecureStorage();
  when(() => storage.read(key: any(named: 'key')))
      .thenAnswer((_) async => _fakeDeviceKeySeed);
  when(
    () => storage.write(
      key: any(named: 'key'),
      value: any(named: 'value'),
    ),
  ).thenAnswer((_) async {});
  return storage;
}

class _MockConnectivity extends Mock implements Connectivity {}

/// The loopback fixture needs real sockets inside Flutter's HTTP-mocking test zone.
class _RealHttpOverrides extends HttpOverrides {}

/// The offline-guard tests' real `RelayConnection` gets a no-op watcher: the default one
/// listens to `connectivity_plus`'s event channel, which no test here fakes. Duplicated from
/// `relay_test.dart`'s own private copy, per R-90-018/R-41-042 rung 1.
ConnectivityWatcher _noOpConnectivityWatcher() {
  final connectivity = _MockConnectivity();
  when(() => connectivity.onConnectivityChanged)
      .thenAnswer((_) => const Stream<List<ConnectivityResult>>.empty());
  return ConnectivityWatcher(connectivity: connectivity);
}

// Fixed, non-secret test-only keys, duplicated from `relay_test.dart`'s private copies (same
// rung-1 rule): the handshake is stubbed, but every frame after it is really encrypted.
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

/// Encrypts and sends one Host->Device frame, exactly as `relay_test.dart`'s own private
/// copy does (rung-1 duplication).
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

const _testDeviceInfo = DeviceInfo(
  protocol: frameProtocolVersion,
  deviceId: 'device-1',
  deviceName: 'Test Phone',
  platform: wire.Platform.android,
  osVersion: '14',
  appVersion: '0.1.0',
);

const _fakeHostInfo = HostInfo(
  protocol: frameProtocolVersion,
  hostId: 'h2',
  hostName: 'test-host',
  herdrVersion: '1.0.0',
  herdrProtocol: 20,
  paired: true,
);

/// Connects a real `RelayConnection` to a loopback fake Host, then drops the link
/// deliberately. `lastHostInfo` stays cached while `isConnected` is false and `send` throws
/// `RelayNotConnectedException` — exactly the state the cached-info create guard exists for.
/// Real async (`dart:io` sockets), so a caller inside `testWidgets` must run this through
/// `tester.runAsync`.
Future<RelayConnection> _connectedThenDroppedRelay({
  void Function(WebSocket, StreamIterator<dynamic>, NoiseCipher)? keepConnected,
}) async {
  final connections = <WebSocket>[];
  final server = await HttpServer.bind('127.0.0.1', 0);
  server.listen((request) async {
    connections.add(await WebSocketTransformer.upgrade(request));
  });

  final gate = BiometricGate(
    appLockEnabled: false,
    keystore: KeystoreService(
      appLockEnabled: false,
      storage: _fakeDeviceKeyStorage(),
    ),
  );
  final origin = (parseRelayOrigin(
    'http://127.0.0.1:${server.port}',
  ) as Ok<RelayOrigin>).value;
  final relay = RelayConnection(
    handshaker: _fakeHandshaker,
    connectivityWatcher: _noOpConnectivityWatcher(),
  );
  addTearDown(relay.dispose);

  final connectResult = HttpOverrides.runWithHttpOverrides(
    () => relay.connect(
      origin: origin,
      handle: 'h2',
      mode: PairingMode(psk: Uint8List(32)),
      gate: gate,
      deviceInfo: _testDeviceInfo,
    ),
    _RealHttpOverrides(),
  );

  while (connections.isEmpty) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  final ws = connections[0];
  final iterator = StreamIterator<dynamic>(ws);
  await iterator.moveNext(); // device_register
  ws.add(
    jsonEncode(<String, Object>{'type': 'session_joined', 'role': 'device'}),
  );
  final hostCipher = NoiseCipher.withKey(_deviceReceiveKey);
  await _sendHostMessage(
    ws,
    hostCipher,
    const Message.hostInfo(_fakeHostInfo),
    1,
  );

  final result = await connectResult;
  assert(result is Ok<void>, 'the fake-host connect succeeds: $result');
  if (keepConnected != null) {
    addTearDown(() async {
      await relay.disconnect();
      await ws.close();
      await server.close(force: true);
    });
    keepConnected(ws, iterator, hostCipher);
    return relay;
  }
  await relay.disconnect();
  assert(!relay.isConnected && relay.lastHostInfo != null);
  await ws.close();
  await server.close(force: true);
  return relay;
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  for (final failed in [false, true]) {
    testWidgets(
      'QR switch callback returns to computers; outcome: ${failed ? 'failure' : 'cancel'}',
      (tester) async {
        _fakePrefs();
        final messenger = tester.binding.defaultBinaryMessenger;
        for (final name in [
          'dev.fluttercommunity.plus/connectivity',
          'dev.fluttercommunity.plus/connectivity_status',
          'dev.steenbakker.mobile_scanner/scanner/method',
        ]) {
          messenger.setMockMethodCallHandler(
            MethodChannel(name),
            (_) async => name.endsWith('/connectivity') ? ['wifi'] : null,
          );
          addTearDown(
            () => messenger.setMockMethodCallHandler(MethodChannel(name), null),
          );
        }
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              keystoreServiceProvider.overrideWithValue(
                KeystoreService(
                  appLockEnabled: false,
                  storage: _fakeDeviceKeyStorage(),
                ),
              ),
            ],
            child: MaterialApp.router(routerConfig: appRouter),
          ),
        );
        appRouter.go('/hosts');
        await tester.pumpAndSettle();
        unawaited(appRouter.push<void>('/pair/scan'));
        await tester.pumpAndSettle();
        final screen = tester.widget<QrScanScreen>(find.byType(QrScanScreen));
        const sentence = 'The host refused the connection.';
        if (failed) {
          screen.onFailedSwitch!(sentence);
        } else {
          screen.onCancelledSwitch!();
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(appRouter.state.uri.path, '/hosts');
        expect(find.byType(HostListScreen), findsOneWidget);
        expect(find.text(sentence), failed ? findsOneWidget : findsNothing);
      },
    );
  }

  group(
    'the pairing toggle swaps /pair/scan and /pair/manual in place '
    '(the reported bug, docs/31-mockups/02-pair-scan.md and 03-pair-code.md)',
    () {
      // Mirrors `routing.dart`'s own `/welcome` -> `push('/pair/scan')`, `/pair/scan`'s
      // `onManualEntry` -> `pushReplacement('/pair/manual')`, and `/pair/manual`'s
      // `onScanInstead` -> `pushReplacement('/pair/scan')` exactly.
      GoRouter buildRouter() => GoRouter(
        initialLocation: '/welcome',
        routes: <RouteBase>[
          GoRoute(
            path: '/welcome',
            builder: (BuildContext context, GoRouterState state) => _Screen(
              title: 'welcome',
              buttons: <String, VoidCallback>{
                'scan': () => context.push('/pair/scan'),
              },
            ),
          ),
          GoRoute(
            path: '/pair/scan',
            builder: (BuildContext context, GoRouterState state) => _Screen(
              title: 'scan',
              buttons: <String, VoidCallback>{
                'manual': () => context.pushReplacement('/pair/manual'),
              },
            ),
          ),
          GoRoute(
            path: '/pair/manual',
            builder: (BuildContext context, GoRouterState state) => _Screen(
              title: 'manual',
              buttons: <String, VoidCallback>{
                'scan': () => context.pushReplacement('/pair/scan'),
              },
            ),
          ),
        ],
      );

      testWidgets(
        'scan, manual, scan, manual, then one pop lands on /welcome, never a '
        'four-deep pairing-screen stack',
        (tester) async {
          final router = buildRouter();
          await tester.pumpWidget(MaterialApp.router(routerConfig: router));
          await tester.pumpAndSettle();
          expect(find.text('welcome'), findsOneWidget);

          await tester.tap(find.text('scan'));
          await tester.pumpAndSettle();
          expect(find.text('scan'), findsOneWidget);

          await tester.tap(find.text('manual'));
          await tester.pumpAndSettle();
          expect(find.text('manual'), findsOneWidget);

          await tester.tap(find.text('scan'));
          await tester.pumpAndSettle();
          expect(find.text('scan'), findsOneWidget);

          await tester.tap(find.text('manual'));
          await tester.pumpAndSettle();
          expect(find.text('manual'), findsOneWidget);

          // The stack is `[/welcome, /pair/manual]`, never four pairing screens deep with
          // `/welcome` at the bottom: one pop reaches `/welcome` directly.
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(find.text('welcome'), findsOneWidget);
        },
      );

      testWidgets(
        'a double tap on the toggle still leaves exactly one pairing screen on the stack',
        (tester) async {
          final router = buildRouter();
          await tester.pumpWidget(MaterialApp.router(routerConfig: router));
          await tester.pumpAndSettle();
          await tester.tap(find.text('scan'));
          await tester.pumpAndSettle();

          await tester.tap(find.text('manual'));
          await tester.tap(find.text('manual'), warnIfMissed: false);
          await tester.pumpAndSettle();
          expect(find.text('manual'), findsOneWidget);

          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(find.text('welcome'), findsOneWidget);
        },
      );
    },
  );

  for (final platform in <TargetPlatform>[
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    testWidgets(
      '$platform: the real notification route badges only its current Host log '
      'and preserves other Host attention (R-31-07-05, R-03-046)',
      (tester) async {
        SharedPreferencesAsyncPlatform.instance =
            InMemorySharedPreferencesAsync.withData({
              'paired_hosts': [
                for (final hostId in <String>['current', 'other', 'empty'])
                  jsonEncode({
                    'hostId': hostId,
                    'hostName': '$hostId computer',
                    'lastSeen': null,
                  }),
              ],
            });
        debugDefaultTargetPlatformOverride = platform;
        final messages = StreamController<Message>.broadcast();
        final states = StreamController<RelayConnectionState>.broadcast();
        // Keep the process-wide PlainStore write queue outside widget fake clocks.
        final store = _MockPlainStore();
        final storedAcks = <NotificationAck>[];
        when(() => store.notificationAcks(any())).thenAnswer((
          invocation,
        ) async {
          final hostId = invocation.positionalArguments.single as String;
          return Ok(storedAcks.where((ack) => ack.hostId == hostId).toList());
        });
        registerFallbackValue(
          const NotificationAck(
            hostId: 'current',
            paneId: 'p1',
            status: 'done',
            at: null,
            removed: false,
          ),
        );
        when(() => store.saveNotificationAck(any()))
            .thenAnswer((invocation) async {
              storedAcks.add(
                invocation.positionalArguments.single as NotificationAck,
              );
              return const Ok(null);
            });
        final notifications = _MockNotificationsService();
        var currentHostId = 'current';
        AgentStatus status(
          String hostId, {
          String at = '2026-09-08T10:00:00Z',
        }) => AgentStatus(
          hostId: hostId,
          paneId: 'p1',
          workspaceId: 'w1',
          tabId: 't1',
          tabTitle: 'Agent tab',
          paneTitle: 'Agent pane',
          agentKind: 'claude',
          status: AgentStatusKind.done,
          at: at,
        );
        registerFallbackValue(status('current'));
        when(() => notifications.postAgentStatusNotification(any()))
            .thenAnswer((_) async => const Ok(null));
        final agentStatus = AgentStatusService(
          messages: messages.stream,
          connectionState: states.stream,
          currentHostId: () => currentHostId,
          notifications: notifications,
          plainStore: store,
        );
        final relay = RelayConnection(
          connectivityWatcher: _noOpConnectivityWatcher(),
        );
        addTearDown(relay.dispose);
        try {
          messages.add(Message.agentStatus(status('other')));
          await tester.pump();
          expect(agentStatus.currentNotifications, isEmpty);
          expect(agentStatus.currentAttention.single.hostId, 'other');

          appRouter.go('/hosts/current/notifications');
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                agentStatusServiceProvider.overrideWithValue(agentStatus),
                relayConnectionProvider.overrideWithValue(relay),
                keystoreServiceProvider.overrideWithValue(
                  KeystoreService(
                    appLockEnabled: false,
                    storage: _fakeDeviceKeyStorage(),
                  ),
                ),
                biometricGateProvider.overrideWithValue(
                  BiometricGate(appLockEnabled: false, setNativeLocked: (_) {}),
                ),
              ],
              child: MaterialApp.router(routerConfig: appRouter),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(NotificationsScreen), findsOneWidget);
          expect(find.text('No notifications.'), findsOneWidget);
          expect(find.byType(Badge), findsNothing);

          messages.add(Message.agentStatus(status('current')));
          await tester.pumpAndSettle();
          expect(find.text('claude is done'), findsOneWidget);
          expect(find.byType(Badge), findsOneWidget);
          expect(find.text('1'), findsOneWidget);
          expect(agentStatus.currentAttention, hasLength(2));

          await tester.tap(find.bySemanticsLabel('Mark all read'));
          await tester.pumpAndSettle();
          expect(find.text('claude is done'), findsOneWidget);
          expect(find.byType(Badge), findsNothing);
          expect(agentStatus.currentNotifications.single.seen, isTrue);
          expect(agentStatus.currentAttention.single.hostId, 'other');
          expect(storedAcks.single.hostId, 'current');
          expect(storedAcks.single.paneId, 'p1');
          expect(storedAcks.single.removed, isFalse);

          messages.add(
            Message.agentStatus(status('current', at: '2026-09-08T11:00:00Z')),
          );
          await tester.pumpAndSettle();
          expect(find.byType(Badge), findsOneWidget);
          expect(find.text('1'), findsOneWidget);

          currentHostId = 'empty';
          states.add(const RelayConnected());
          await tester.pumpAndSettle();
          expect(find.text('No notifications.'), findsOneWidget);
          expect(find.byType(Badge), findsNothing);
          expect(agentStatus.currentNotifications, isEmpty);
          expect(agentStatus.currentAttention, hasLength(2));
          appRouter.go('/hosts/empty/notifications');
          await tester.pumpAndSettle();
          expect(find.text('No notifications.'), findsOneWidget);
          expect(find.byType(Badge), findsNothing);

          appRouter.go('/hosts');
          await tester.pumpAndSettle();
          expect(find.byType(HostListScreen), findsOneWidget);
          expect(find.text('other computer'), findsOneWidget);
          expect(
            find.descendant(
              of: find.byKey(const ValueKey<String>('other')),
              matching: find.text('1'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: find.byKey(const ValueKey<String>('empty')),
              matching: find.text('1'),
            ),
            findsNothing,
          );
          expect(find.text('1'), findsNWidgets(2));
        } finally {
          try {
            // Unmount under the platform the tree was built for, release the service's
            // subscriptions, let their cancellations settle, then close the sources one at
            // a time; the override is cleared last, once nothing platform-specific remains.
            // The relay is disposed by `addTearDown` above, outside this fake-clock body,
            // the same way this file's other relay tests do.
            await tester.pumpWidget(const MaterialApp(home: Text('')));
            agentStatus.dispose();
            await tester.pump();
            await messages.close();
            await states.close();
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        }
      },
    );
  }

  group('routeNotificationTap dedupes repeat taps (R-30-030, R-30-511)', () {
    testWidgets('two taps for the same pane push exactly one terminal page', (
      tester,
    ) async {
      final router = GoRouter(
        navigatorKey: rootNavigatorKey,
        initialLocation: '/agents',
        routes: <RouteBase>[
          GoRoute(
            path: '/agents',
            builder: (BuildContext context, GoRouterState state) =>
                const _Screen(title: 'agents'),
          ),
          GoRoute(
            path: '/lock',
            name: 'lock',
            builder: (BuildContext context, GoRouterState state) =>
                const _Screen(title: 'lock'),
          ),
          GoRoute(
            path: '/hosts/:hostId/panes/:paneId',
            builder: (BuildContext context, GoRouterState state) =>
                _Screen(title: 'terminal-${state.pathParameters['paneId']}'),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            biometricGateProvider.overrideWithValue(
              BiometricGate(appLockEnabled: false),
            ),
            agentStatusServiceProvider.overrideWithValue(_agentStatus()),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      routeNotificationTap(
        rootNavigatorKey.currentContext!,
        hostId: 'h1',
        paneId: 'p1',
      );
      await tester.pumpAndSettle();
      expect(find.text('terminal-p1'), findsOneWidget);

      // A second tap for the identical pane MUST NOT stack a duplicate terminal.
      routeNotificationTap(
        rootNavigatorKey.currentContext!,
        hostId: 'h1',
        paneId: 'p1',
      );
      await tester.pumpAndSettle();
      expect(find.text('terminal-p1'), findsOneWidget);

      // One pop reaches `agents` directly: the stack held only one terminal page.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('agents'), findsOneWidget);
    });

    testWidgets(
      'two taps while locked update the held target in place, never stacking a '
      'second /lock page',
      (tester) async {
        final router = GoRouter(
          navigatorKey: rootNavigatorKey,
          initialLocation: '/agents',
          routes: <RouteBase>[
            GoRoute(
              path: '/agents',
              builder: (BuildContext context, GoRouterState state) =>
                  const _Screen(title: 'agents'),
            ),
            GoRoute(
              path: '/lock',
              name: 'lock',
              builder: (BuildContext context, GoRouterState state) =>
                  _Screen(title: 'lock-${state.uri.queryParameters['from']}'),
            ),
            GoRoute(
              path: '/hosts/:hostId/panes/:paneId',
              builder: (BuildContext context, GoRouterState state) =>
                  const _Screen(title: 'terminal'),
            ),
          ],
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              biometricGateProvider.overrideWithValue(
                BiometricGate(appLockEnabled: true),
              ),
              agentStatusServiceProvider.overrideWithValue(_agentStatus()),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();

        routeNotificationTap(
          rootNavigatorKey.currentContext!,
          hostId: 'h1',
          paneId: 'p1',
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('p1'), findsOneWidget);

        // A second tap for a different pane, still locked, updates the held target
        // instead of pushing a second `/lock` page.
        routeNotificationTap(
          rootNavigatorKey.currentContext!,
          hostId: 'h2',
          paneId: 'p2',
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('p2'), findsOneWidget);

        // One pop reaches `agents` directly: only one `/lock` page was ever on the stack.
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('agents'), findsOneWidget);
      },
    );

    testWidgets(
      'a tap for a pane the last tree_snapshot no longer holds lands on the '
      'Notifications destination with the closed pane named, and opens no terminal '
      '(R-30-511 pane closed, decided 2026-09-04)',
      (tester) async {
        final messages = StreamController<Message>.broadcast();
        addTearDown(messages.close);
        final AgentStatusService agentStatus = _agentStatus(
          messages.stream,
          'h1',
        );
        addTearDown(agentStatus.dispose);
        messages.add(
          const Message.treeSnapshot(
            TreeSnapshot(workspaces: [], tabs: [], panes: [], agents: []),
          ),
        );
        // The service applies the snapshot on microtasks alone (an in-memory `PlainStore`);
        // `pumpAndSettle` below flushes them. A real-timer `pumpEventQueue` would hang under
        // `testWidgets`'s fake clock.

        final router = GoRouter(
          navigatorKey: rootNavigatorKey,
          initialLocation: '/agents',
          routes: <RouteBase>[
            GoRoute(
              path: '/agents',
              builder: (BuildContext context, GoRouterState state) =>
                  const _Screen(title: 'agents'),
            ),
            GoRoute(
              path: '/hosts/:hostId/notifications',
              builder: (BuildContext context, GoRouterState state) => _Screen(
                title:
                    'notifications-${state.uri.queryParameters['closedPane']}',
              ),
            ),
            GoRoute(
              path: '/hosts/:hostId/panes/:paneId',
              builder: (BuildContext context, GoRouterState state) =>
                  const _Screen(title: 'terminal'),
            ),
          ],
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              biometricGateProvider.overrideWithValue(
                BiometricGate(appLockEnabled: false),
              ),
              agentStatusServiceProvider.overrideWithValue(agentStatus),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();

        routeNotificationTap(
          rootNavigatorKey.currentContext!,
          hostId: 'h1',
          paneId: 'p9',
        );
        await tester.pumpAndSettle();

        expect(find.text('notifications-p9'), findsOneWidget);
        expect(find.text('terminal'), findsNothing);

        // A repeat tap for the same closed pane is a no-op.
        routeNotificationTap(
          rootNavigatorKey.currentContext!,
          hostId: 'h1',
          paneId: 'p9',
        );
        await tester.pumpAndSettle();
        expect(find.text('notifications-p9'), findsOneWidget);
      },
    );
  });

  group('R-22-034 deep link + R-31-04-04 held route, together, via the real appRouter', () {
    setUp(_fakePrefs);

    for (final appLockEnabled in <bool>[true, false]) {
      testWidgets(
        '${appLockEnabled ? 'locked' : 'unlocked'} cold pairing link preserves /hosts beneath it and a warm '
        'second link refills the same screen without a stale /lock page',
        (tester) async {
          await tester.runAsync(
            () => PlainStore().savePairedHost(
              PairedHostRecord(
                hostId: 'h1',
                hostName: 'Office desktop',
                lastSeen: DateTime.utc(2026),
              ),
            ),
          );
          await AppSettingsService().setAppLockEnabled(value: appLockEnabled);

          const handle = 'AQIDBAUGBwgJCgsMDQ4PEA';
          const phrase = 'remedy-tapestry-hubcap-oversleep-jailbird-kinetic';
          final link =
              'herdr-remote://pair?v=1&r=${Uri.encodeComponent('https://relay.example.com')}'
              '&h=$handle&p=$phrase';
          final storage = _fakeDeviceKeyStorage();
          const connectivityChannel = MethodChannel(
            'dev.fluttercommunity.plus/connectivity',
          );
          const localAuthChannel = MethodChannel(
            'plugins.flutter.io/local_auth',
          );
          TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                connectivityChannel,
                (_) async => <String>['wifi'],
              );
          // The lock page resolves its glyph before it starts the real gate. This widget
          // test has no native capability channel, just as it has no native Keychain.
          TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                localAuthChannel,
                (_) async => <String>['face'],
              );
          addTearDown(() {
            TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
                .setMockMethodCallHandler(connectivityChannel, null);
            TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
                .setMockMethodCallHandler(localAuthChannel, null);
          });
          appRouter.go(link);

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                keystoreServiceProvider.overrideWithValue(
                  KeystoreService(
                    appLockEnabled: appLockEnabled,
                    storage: storage,
                  ),
                ),
              ],
              child: MaterialApp.router(routerConfig: appRouter),
            ),
          );
          await tester.pumpAndSettle();

          await pumpRasterized(tester);

          // Landed on the pairing flow, unlocked, with no lock prompt left showing.
          expect(find.text('Pair by hand'), findsOneWidget);
          expect(find.text('Unlock to continue.'), findsNothing);
          expect(appRouter.state.uri.path, '/hosts/pair/manual');
          // The pairing form reads no key material: not a pinned Host key, not a routing handle
          // (R-03-126's origin prefill uses the narrow `hostRelayOrigin` read).
          verifyNever(() => storage.read(key: 'host_routing_handle_h1'));
          verifyNever(() => storage.read(key: 'host_static_public_key_h1'));

          // These fixed test values contain no real pairing secrets.
          expect(find.text(handle), findsOneWidget);
          final manual = find.byType(ManualPairingScreen);
          final firstState = tester.state(manual);
          const secondPhrase =
              'kinetic-jailbird-oversleep-hubcap-tapestry-remedy';
          final secondLink = link.replaceFirst(phrase, secondPhrase);
          appRouter.go(secondLink);
          await tester.pumpAndSettle();

          expect(manual, findsOneWidget);
          expect(identical(tester.state(manual), firstState), isTrue);
          final fields = tester.widgetList<EditableText>(
            find.descendant(of: manual, matching: find.byType(EditableText)),
          );
          final displayedWords = fields
              .map((field) => field.controller.text)
              .where(secondPhrase.split('-').contains)
              .join('-');
          expect(
            displayedWords == secondPhrase,
            isTrue,
            reason: 'The second link replaces all six words in order.',
          );

          // Exactly one pop reaches `/hosts` (`HostListScreen`, title "Computers" per
          // R-31-05-19 callout 1) -- never a stale `/lock` page underneath.
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(find.text('Computers'), findsOneWidget);
        },
      );
    }
    testWidgets(
      'a warm link refills a pushed manual screen and preserves its parent',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              keystoreServiceProvider.overrideWithValue(
                KeystoreService(
                  appLockEnabled: true,
                  storage: _fakeDeviceKeyStorage(),
                ),
              ),
            ],
            child: MaterialApp.router(routerConfig: appRouter),
          ),
        );
        appRouter.go('/hosts');
        await tester.pumpAndSettle();
        final onSwitched = tester
            .widget<HostListScreen>(find.byType(HostListScreen))
            .onSwitched!;
        unawaited(appRouter.push<void>('/pair/manual'));
        await tester.pumpAndSettle();

        final manual = find.byType(ManualPairingScreen);
        final firstState = tester.state(manual);
        const phrase = 'remedy-tapestry-hubcap-oversleep-jailbird-kinetic';
        final link =
            'herdr-remote://pair?v=1&r=${Uri.encodeComponent('https://relay.example.com')}'
            '&h=AQIDBAUGBwgJCgsMDQ4PEA&p=$phrase';
        appRouter.go(link);
        await tester.pumpAndSettle();

        expect(manual, findsOneWidget);
        expect(identical(tester.state(manual), firstState), isTrue);
        expect(appRouter.state.uri.path, '/pair/manual');
        onSwitched('h1');
        await tester.pumpAndSettle();
        expect(identical(tester.state(manual), firstState), isTrue);
        String displayedPhrase() => tester
            .widgetList<EditableText>(
              find.descendant(of: manual, matching: find.byType(EditableText)),
            )
            .map((field) => field.controller.text)
            .where(phrase.split('-').contains)
            .join('-');
        expect(displayedPhrase() == phrase, isTrue);
        final acceptedLocation = appRouter.state.uri;

        appRouter.go('herdr-remote://pair?v=1');
        await tester.pumpAndSettle();
        expect(identical(tester.state(manual), firstState), isTrue);
        expect(displayedPhrase() == phrase, isTrue);
        expect(appRouter.state.uri == acceptedLocation, isTrue);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(appRouter.state.uri.path, '/hosts');
        expect(appRouter.canPop(), isFalse);
      },
    );
  });

  group('the actions route after R-03-055 (2026-09-09)', () {
    /// The leaf `GoRoute` of a match, walking through any shell matches.
    GoRoute leafRoute(RouteMatchList matchList) {
      RouteMatchBase match = matchList.matches.last;
      while (match is ShellRouteMatch) {
        match = match.matches.last;
      }
      return match.route as GoRoute;
    }

    test('the computer-scoped /hosts/:hostId/actions route is gone -- the Agents screen '
        'carries no plugin control -- while /hosts/:hostId/panes/:paneId/actions sits on '
        'the root navigator under the terminal (R-31-18-01, R-30-045)', () {
      expect(
        appRouter.configuration
            .findMatch(Uri.parse('/hosts/h1/actions'))
            .isError,
        isTrue,
        reason:
            'no route may answer the retired computer-scoped actions path: a '
            'plugin acts on a pane, so the person reaches it from the pane',
      );

      final RouteMatchList match = appRouter.configuration.findMatch(
        Uri.parse('/hosts/h1/panes/p1/actions'),
      );
      final GoRoute leaf = leafRoute(match);
      expect(leaf.name, 'pane-actions');
      expect(
        leaf.parentNavigatorKey,
        rootNavigatorKey,
        reason:
            'the terminal hides the bottom navigation (R-30-022); the screen '
            'pushed on top of it is the same full-screen exception',
      );
      expect(
        match.matches.map((RouteMatchBase m) => (m.route as GoRoute).name),
        <String>['terminal', 'pane-actions'],
        reason: 'a deep link lands the terminal beneath the actions screen',
      );
      expect(match.pathParameters, <String, String>{
        'hostId': 'h1',
        'paneId': 'p1',
      });
    });
  });

  group("the agent list create control's offline guards, through the real appRouter "
      '(R-31-06-22, amended 2026-09-08)', () {
    // A `BiometricGate` built with App Lock off syncs MainActivity's FLAG_SECURE over this
    // channel (biometric_gate.dart's `_defaultSetNativeLocked`); mock that platform seam
    // only, exactly as `biometric_gate_test.dart` does — every biometric method itself
    // stays real.
    const MethodChannel lockChannel = MethodChannel(
      'dev.herdr.herdr_mobile/biometric_lock',
    );

    setUp(() {
      _fakePrefs();
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            lockChannel,
            (MethodCall call) async => null,
          );
    });
    tearDown(() {
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(lockChannel, null);
    });

    /// Pumps the real `appRouter` and lands on `/hosts/<hostId>/agents`. [relay], when
    /// given, replaces the session's `RelayConnection` (a `final class`, so only a real
    /// instance can). The App Lock offer is pre-marked shown so the route's post-frame
    /// hook returns before its `local_auth` platform channel — `_agentStatus()`'s own
    /// `_fakePrefs()` runs first, or its fresh in-memory store would drop the flag.
    Future<void> pumpAtAgentList(
      WidgetTester tester,
      String hostId, {
      required RelayConnection relay,
    }) async {
      final AgentStatusService agentStatus = _agentStatus();
      await AppSettingsService().setAppLockOfferShown(value: true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            keystoreServiceProvider.overrideWithValue(
              KeystoreService(
                appLockEnabled: false,
                storage: _fakeDeviceKeyStorage(),
              ),
            ),
            agentStatusServiceProvider.overrideWithValue(agentStatus),
            // The route's post-frame hook asks the notification permission (R-30-509); the
            // real plugin has no platform here.
            notificationsServiceProvider.overrideWithValue(
              _MockNotificationsService(),
            ),
            relayConnectionProvider.overrideWithValue(relay),
          ],
          child: MaterialApp.router(routerConfig: appRouter),
        ),
      );
      await tester.pumpAndSettle();
      appRouter.go('/hosts/$hostId/agents');
      await tester.pumpAndSettle();
    }

    testWidgets('split ack replaces the terminal and refreshes the tree once', (
      tester,
    ) async {
      const connectivityChannel = MethodChannel(
        'dev.fluttercommunity.plus/connectivity',
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        connectivityChannel,
        (_) async => <String>['wifi'],
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          connectivityChannel,
          null,
        );
      });
      late WebSocket host;
      late NoiseCipher hostCipher;
      final received = <Map<String, dynamic>>[];
      final relay = (await tester.runAsync(
        () => _connectedThenDroppedRelay(
          keepConnected: (socket, iterator, cipher) {
            host = socket;
            hostCipher = cipher;
            unawaited(() async {
              final reassembler = Reassembler();
              final receiveCipher = NoiseCipher.withKey(_deviceSendKey);
              while (await iterator.moveNext()) {
                final decoded = await decodeFragment(
                  reassembler,
                  receiveCipher,
                  Uint8List.fromList(iterator.current as List<int>),
                );
                final bytes = (decoded as Ok<Uint8List?>).value;
                if (bytes != null) {
                  received.add(
                    jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
                  );
                }
              }
            }());
          },
        ),
      ))!;
      appRouter.go('/hosts/h2/agents');
      await pumpAtAgentList(tester, 'h2', relay: relay);
      await tester.runAsync(
        () => _sendHostMessage(
          host,
          hostCipher,
          const Message.treeSnapshot(
            TreeSnapshot(workspaces: [], tabs: [], panes: [], agents: []),
          ),
          2,
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      unawaited(appRouter.push('/hosts/h2/panes/pane-1'));
      await tester.pumpAndSettle();
      final depth =
          appRouter.routerDelegate.currentConfiguration.matches.length;
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      received.clear();
      await tester.tap(find.bySemanticsLabel('Pane actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Split right'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      final request = received.singleWhere(
        (frame) => frame['type'] == 'host_action',
      );
      final payload = request['payload'] as Map<String, dynamic>;
      expect(payload['action'], 'pane.split');
      expect(payload['pane_id'], 'pane-1');
      expect((payload['params'] as Map<String, dynamic>)['direction'], 'right');
      expect(appRouter.state.uri.path, '/hosts/h2/panes/pane-1');
      expect(
        received.where((frame) => frame['type'] == 'tree_request'),
        isEmpty,
      );
      await tester.runAsync(
        () => _sendHostMessage(
          host,
          hostCipher,
          const Message.hostActionAck(
            HostActionAck(
              success: true,
              action: HostActionKind.paneSplit,
              paneId: 'pane-1',
              resultId: 'pane-2',
            ),
          ),
          3,
          corr: request['corr'] as String?,
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      expect(appRouter.state.uri.path, '/hosts/h2/panes/pane-2');
      expect(
        appRouter.routerDelegate.currentConfiguration.matches.length,
        depth,
      );
      expect(
        tester.widget<TerminalScreen>(find.byType(TerminalScreen)).paneId,
        'pane-2',
      );
      expect(
        received.where((frame) => frame['type'] == 'tree_request'),
        hasLength(1),
      );
      await tester.runAsync(
        () => _sendHostMessage(
          host,
          hostCipher,
          const Message.treeSnapshot(
            TreeSnapshot(workspaces: [], tabs: [], panes: [], agents: []),
          ),
          4,
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AgentListScreen), findsOneWidget);
      expect(appRouter.state.uri.path, '/hosts/h2/agents');
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
    testWidgets('a create tap that races a never-completed handshake (null lastHostInfo) answers '
        'with the not-connected sentence, never silence', (tester) async {
      await pumpAtAgentList(
        tester,
        'h1',
        relay: RelayConnection(connectivityWatcher: _noOpConnectivityWatcher()),
      );

      // The screen itself already knows the link is down: the strip shows and the FAB
      // is disabled. A tap already in flight still reaches the route's own callback...
      expect(find.text('Offline. Showing what we last saw.'), findsOneWidget);
      final screen = tester.widget<AgentListScreen>(
        find.byType(AgentListScreen),
      );

      // ...and the race guard reports the same sentence a caught disconnect does.
      screen.onCreate!();
      await tester.pump();
      await tester.pump();
      expect(find.text(notConnectedMessage), findsOneWidget);

      // Let the snackbar's display duration expire so no timer outlives the test.
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
    });

    testWidgets('cached host info with a dropped link surfaces the reconcile failure as the same '
        'not-connected sentence', (tester) async {
      final RelayConnection relay = (await tester.runAsync(
        _connectedThenDroppedRelay,
      ))!;
      await pumpAtAgentList(tester, 'h2', relay: relay);

      // The cached host_info reached the route (the chip names the Host) while the link
      // is down.
      expect(find.text('test-host'), findsOneWidget);
      final screen = tester.widget<AgentListScreen>(
        find.byType(AgentListScreen),
      );

      screen.onCreate!();
      await tester.pump();
      await tester.pump();
      expect(find.text(notConnectedMessage), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
    });
  });
}
