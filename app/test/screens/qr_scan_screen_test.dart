/// Structural coverage for `QrScanScreenBody` (`app/lib/screens/qr_scan_screen.dart`,
/// `WP-15-b`), one per non-empty row of `docs/31-mockups/02-pair-scan.md`'s `## States` table
/// that this file's own presentational split can reach with no `mobile_scanner` platform
/// channel: `QrScanScreenBody` never opens a camera itself (it only paints whatever
/// `MobileScannerController` its caller passes, or none), mirroring
/// `lock_screen_golden_test.dart`'s reasoning for testing the pure `*Body` widget directly.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ClipOp, Tristate;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoButton, CupertinoNavigationBar;
import 'package:flutter/foundation.dart'
    show Brightness, TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart' show Offset, SizedBox, StatefulBuilder;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart'
    show
        Border,
        BorderStyle,
        BoxDecoration,
        CustomPaint,
        DecoratedBox,
        MediaQuery,
        Rect,
        Size,
        TextScaler;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart';
import 'package:herdr_mobile/models/frame.dart';
import 'package:herdr_mobile/models/messages/device_info.dart' as messages;
import 'package:herdr_mobile/models/messages/platform.dart' as wire;
import 'package:herdr_mobile/screens/qr_scan_screen.dart';
import 'package:herdr_mobile/services/biometric_gate.dart';
import 'package:herdr_mobile/services/connectivity.dart';
import 'package:herdr_mobile/services/frame_codec.dart';
import 'package:herdr_mobile/services/keystore.dart' show KeystoreService;
import 'package:herdr_mobile/services/noise.dart';
import 'package:herdr_mobile/services/origin.dart';
import 'package:herdr_mobile/services/pairing.dart';
import 'package:herdr_mobile/services/plain_store.dart';
import 'package:herdr_mobile/services/relay.dart';
import 'package:herdr_mobile/widgets/app_text_button.dart';
import 'package:herdr_mobile/widgets/theme/app_color.dart';
import 'package:herdr_mobile/widgets/theme/app_space.dart';
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart'
    show AppBar, IconButton, Material, MaterialApp;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:web_socket_channel/io.dart';

// `material_ui`'s `AppBar` and `IconButton` are the screen's own types; `flutter/material`'s
// would never match a finder here.

/// The Android flash control: an `IconButton` whose tooltip is the mockup's exact label
/// (callout 8), the same control `connection_screen.dart` and `terminal_screen.dart` use in
/// their bars. iOS keeps a `CupertinoButton`, covered by the iOS test below.
IconButton _flashButton(WidgetTester tester) => tester.widget<IconButton>(
  find.ancestor(
    of: find.byIcon(Symbols.flash_off_rounded),
    matching: find.byType(IconButton),
  ),
);

void main() {
  for (final phase in [QrScanPhase.ready, QrScanPhase.pairing]) {
    testWidgets(
      'landscape ${phase.name} panel has visible side borders and margins',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(812, 375);
        tester.view.padding = const FakeViewPadding(
          left: 44,
          right: 44,
          bottom: 21,
        );
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(home: QrScanScreenBody(phase: phase)),
        );
        await tester.pump();
        final label = find.text(
          phase == QrScanPhase.ready ? 'PAIRING' : 'CONNECTING',
        );
        final panel = find
            .ancestor(of: label, matching: find.byType(DecoratedBox))
            .first;
        final decoration =
            tester.widget<DecoratedBox>(panel).decoration as BoxDecoration;
        final border = decoration.border! as Border;
        final color = AppColor.of(tester.element(panel));
        for (final side in [
          border.top,
          border.right,
          border.bottom,
          border.left,
        ]) {
          expect(side.style, BorderStyle.solid);
          expect(side.width, greaterThan(0));
          expect(side.color, color.borderStrong);
        }
        final rect = tester.getRect(panel);
        expect(rect.left, greaterThanOrEqualTo(406 + AppSpace.space4));
        expect(rect.right, lessThanOrEqualTo(812 - 44 - AppSpace.space4));
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }

  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in [
      'dev.fluttercommunity.plus/connectivity_status',
      'dev.steenbakker.mobile_scanner/scanner/method',
      'dev.herdr.herdr_mobile/camera_zoom',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(name),
        (_) async => null,
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(MethodChannel(name), null),
      );
    }
  });
  for (final existingHost in [false, true]) {
    testWidgets('cancel aborts the handshake; existing host: $existingHost', (
      tester,
    ) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      const connectivityChannel = MethodChannel(
        'dev.fluttercommunity.plus/connectivity',
      );
      const deviceChannel = MethodChannel(
        'dev.fluttercommunity.plus/device_info',
      );
      messenger.setMockMethodCallHandler(
        connectivityChannel,
        (_) async => ['wifi'],
      );
      messenger.setMockMethodCallHandler(deviceChannel, (_) async {
        return <String, dynamic>{
          'version': <String, dynamic>{
            'baseOS': '',
            'sdkInt': 34,
            'release': '14',
            'codename': 'REL',
            'incremental': '',
            'previewSdkInt': 0,
            'securityPatch': '',
          },
          'board': 'shiba',
          'bootloader': 'test',
          'brand': 'Google',
          'device': 'shiba',
          'display': 'test',
          'fingerprint': 'test',
          'hardware': 'shiba',
          'host': 'test',
          'id': 'test',
          'manufacturer': 'Google',
          'model': 'Pixel 8',
          'product': 'shiba',
          'name': 'shiba',
          'supported32BitAbis': <String>[],
          'supported64BitAbis': <String>['arm64-v8a'],
          'supportedAbis': <String>['arm64-v8a'],
          'tags': 'release-keys',
          'type': 'user',
          'isPhysicalDevice': true,
          'freeDiskSize': 0,
          'totalDiskSize': 0,
          'systemFeatures': <String>[],
          'isLowRamDevice': false,
          'physicalRamSize': 0,
          'availableRamSize': 0,
        };
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(connectivityChannel, null);
        messenger.setMockMethodCallHandler(deviceChannel, null);
      });
      PackageInfo.setMockInitialValues(
        appName: 'Herdr',
        packageName: 'dev.herdr',
        version: '1',
        buildNumber: '1',
        buildSignature: '',
      );
      // A real gate over a mocked keystore, like `relay_test.dart`: `connect` reads
      // `isLocked`, `lockGeneration` and `addListener`, which a bare mock returns null for.
      final keystore = _Keystore();
      final key = await tester.runAsync(() => X25519().newKeyPair());
      when(() => keystore.deviceKeyPair()).thenAnswer((_) async => Ok(key!));
      when(() => keystore.existingDeviceKeyPair())
          .thenAnswer((_) async => Ok(key!));
      final gate = BiometricGate(
        appLockEnabled: false,
        keystore: keystore,
        setNativeLocked: (_) {},
      );
      final store = _Store();
      final connectivity = _Connectivity();
      when(() => connectivity.onConnectivityChanged)
          .thenAnswer((_) => const Stream<List<ConnectivityResult>>.empty());
      when(() => store.deviceId())
          .thenAnswer((_) async => const Ok('device-1'));
      when(() => store.deviceName())
          .thenAnswer((_) async => const Ok<String?>('Phone'));
      expect(await tester.runAsync(gate.unlock), isA<Ok<void>>());
      final entered = Completer<void>();
      final released = Completer<NoiseSession>();
      final closed = Completer<void>();
      final server = await tester.runAsync(
        () => HttpServer.bind('127.0.0.1', 0),
      );
      var sockets = 0;
      final oldClosed = Completer<void>();
      await tester.runAsync(() async {
        server!.listen((request) async {
          final previous = existingHost && sockets++ == 0;
          final socket = await WebSocketTransformer.upgrade(request);
          addTearDown(() => socket.close());
          socket.listen((data) async {
            if (data is! String) return;
            socket.add(
              jsonEncode({'type': 'session_joined', 'role': 'device'}),
            );
            if (previous) {
              final encoded = await encodeFrame(
                NoiseCipher.withKey(Uint8List(32)),
                Uint8List.fromList(
                  utf8.encode(
                    jsonEncode(
                      const Frame(
                        v: frameProtocolVersion,
                        type: 'host_info',
                        seq: 1,
                        payload: {
                          'protocol': frameProtocolVersion,
                          'host_id': 'old-host',
                          'host_name': 'Old host',
                          'herdr_version': '1.0',
                          'herdr_protocol': 20,
                          'paired': true,
                        },
                      ).toJson(),
                    ),
                  ),
                ),
              );
              for (final fragment in (encoded as Ok<List<Uint8List>>).value) {
                socket.add(fragment);
              }
            }
          }, onDone: previous ? oldClosed.complete : closed.complete);
        });
      });
      var handshakes = 0;
      final client = _RealHttp().createHttpClient(null);
      addTearDown(() => client.close(force: true));
      final relay = RelayConnection(
        channelFactory: (uri, protocols) async => IOWebSocketChannel.connect(
          uri,
          protocols: protocols,
          customClient: client,
        ),
        connectivityWatcher: ConnectivityWatcher(connectivity: connectivity),
        handshaker: (iterator, channel, mode, gate, localStatic) {
          if (existingHost && handshakes++ == 0) {
            return Future.value(
              NoiseSession(
                send: NoiseCipher.withKey(Uint8List(32)),
                receive: NoiseCipher.withKey(Uint8List(32)),
                remoteStaticPublicKey: Uint8List(32),
              ),
            );
          }
          entered.complete();
          return released.future;
        },
      );
      if (existingHost) {
        final result = await tester.runAsync(
          () => relay.connect(
            origin: (parseRelayOrigin(
              'http://127.0.0.1:${server!.port}',
            ) as Ok<RelayOrigin>).value,
            handle: 'old',
            mode: PairingMode(psk: Uint8List(32)),
            gate: gate,
            deviceInfo: const messages.DeviceInfo(
              protocol: frameProtocolVersion,
              deviceId: 'device-1',
              deviceName: 'Phone',
              platform: wire.Platform.android,
              osVersion: '14',
              appVersion: '1',
            ),
          ),
        );
        expect(result, isA<Ok<void>>());
        expect(relay.isConnected, isTrue);
      }
      final camera = _TestCamera();
      var paired = 0;
      var cancelledSwitch = 0;
      var failedSwitch = 0;
      const phrase = 'remedy-tapestry-hubcap-oversleep-jailbird-kinetic';
      await tester.pumpWidget(
        MaterialApp(
          home: QrScanScreen(
            scanner: PairingScanner(controller: camera),
            connection: relay,
            gate: gate,
            plainStore: store,
            effWords: File('assets/wordlists/eff_large_wordlist.txt')
                .readAsLinesSync(),
            hasConnectedHost: existingHost,
            onPaired: (_, _) => paired++,
            onCancelledSwitch: () => cancelledSwitch++,
            onFailedSwitch: (_) => failedSwitch++,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() async {
        camera.captures.add(
          BarcodeCapture(
            barcodes: [
              Barcode(
                rawValue:
                    'herdr-remote://pair?v=1&r=${Uri.encodeComponent('http://127.0.0.1:${server!.port}')}&h=n6Loxf94CfyIO6hOxlaHvA&p=$phrase',
              ),
            ],
          ),
        );
      });
      await tester.pump();
      for (var i = 0; i < 100 && !entered.isCompleted; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(
        entered.isCompleted,
        isTrue,
        reason:
            '${tester.widget<QrScanScreenBody>(find.byType(QrScanScreenBody)).phase}: ${tester.widget<QrScanScreenBody>(find.byType(QrScanScreenBody)).hint?.text}',
      );
      expect(find.text('CONNECTING'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      for (var i = 0; i < 100 && !closed.isCompleted; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      await tester.runAsync(() async {
        if (existingHost) {
          await oldClosed.future.timeout(const Duration(seconds: 5));
        }
        await closed.future.timeout(const Duration(seconds: 5));
        released.complete(
          NoiseSession(
            send: NoiseCipher.withKey(Uint8List(32)),
            receive: NoiseCipher.withKey(Uint8List(32)),
            remoteStaticPublicKey: Uint8List(32),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(relay.isConnected, isFalse);
      expect(find.text('Pairing cancelled.'), findsOneWidget);
      expect(find.text('Type it in'), findsOneWidget);
      expect(paired, 0);
      expect(cancelledSwitch, existingHost ? 1 : 0);
      expect(failedSwitch, 0);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.runAsync(() async {
        await relay.dispose();
        await server!.close(force: true);
      });
      expect(cancelledSwitch, existingHost ? 1 : 0);
    });
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final textScale in [1.0, 2.0]) {
      for (final phase in QrScanPhase.values) {
        testWidgets(
          '${platform.name} landscape ${phase.name} fits at text scale $textScale',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = const Size(812, 375);
            tester.view.padding = const FakeViewPadding(
              left: 44,
              right: 44,
              bottom: 21,
            );
            addTearDown(tester.view.reset);
            var manual = false;
            var settings = false;
            var cancelled = false;
            await tester.pumpWidget(
              MaterialApp(
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(textScale),
                    disableAnimations: true,
                  ),
                  child: child!,
                ),
                home: QrScanScreenBody(
                  phase: phase,
                  hasConnectedHost: true,
                  offline: phase != QrScanPhase.pairing,
                  hint: phase == QrScanPhase.ready
                      ? const QrHintIssue('That is not a Herdr pairing code.')
                      : null,
                  connectingHost: 'relay.example.com',
                  onManualEntry: () => manual = true,
                  onOpenSettings: () => settings = true,
                  onCancel: () => cancelled = true,
                ),
              ),
            );
            await tester.pump();
            expect(tester.takeException(), isNull);

            if (phase != QrScanPhase.cameraUnavailable &&
                phase != QrScanPhase.permissionDenied) {
              final geometry = _viewfinderGeometry(tester)!;
              expect(geometry.frame.width, greaterThan(0));
              expect(geometry.frame.width, geometry.frame.height);
              expect(
                geometry.frame.left,
                greaterThanOrEqualTo(geometry.bounds.left + 24),
              );
              expect(
                geometry.frame.right,
                lessThanOrEqualTo(geometry.bounds.right - 24),
              );
              expect(
                geometry.frame.top,
                greaterThanOrEqualTo(geometry.bounds.top + 24),
              );
              expect(
                geometry.frame.bottom,
                lessThanOrEqualTo(geometry.bounds.bottom - 24),
              );
            }
            if (phase == QrScanPhase.permissionDenied) {
              final action = find.text('Open Settings');
              await tester.ensureVisible(action);
              await tester.pump();
              await tester.tap(action);
              expect(settings, isTrue);
            }
            final action = find.text(
              phase == QrScanPhase.pairing ? 'Cancel' : 'Type it in',
            );
            await tester.ensureVisible(action);
            await tester.pump();
            final rect = tester.getRect(action);
            expect(rect.left, greaterThanOrEqualTo(44));
            expect(rect.right, lessThanOrEqualTo(768));
            expect(rect.bottom, lessThanOrEqualTo(354));
            await tester.tap(action);
            expect(phase == QrScanPhase.pairing ? cancelled : manual, isTrue);
            expect(tester.takeException(), isNull);
          },
          variant: TargetPlatformVariant.only(platform),
        );
      }
    }
  }

  testWidgets(
    'iOS rotation keeps the scanner and zoom targets inside safe areas',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 812);
      addTearDown(tester.view.reset);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dev.herdr.herdr_mobile/camera_zoom'),
        (_) async => {
          'minZoom': 1.0,
          'maxZoom': 8.0,
          'wideZoom': 1.0,
          'switchOverFactors': <double>[],
        },
      );
      final camera = _TestCamera();
      await tester.pumpWidget(
        MaterialApp(
          home: QrScanScreenBody(phase: QrScanPhase.ready, controller: camera),
        ),
      );
      await tester.pumpAndSettle();
      final scannerState = tester.state(find.byType(MobileScanner));
      tester.view.physicalSize = const Size(812, 375);
      tester.view.padding = const FakeViewPadding(
        left: 44,
        right: 44,
        bottom: 21,
      );
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(MobileScanner)), same(scannerState));
      expect(tester.takeException(), isNull);
      final frameRect = _viewfinderGeometry(tester)!.frame;
      for (final label in ['1x', '2x', '5x']) {
        final target = tester.getRect(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(CupertinoButton),
          ),
        );
        expect(target.top, greaterThan(frameRect.bottom));
        expect(target.left, greaterThanOrEqualTo(44));
        expect(target.bottom, lessThanOrEqualTo(354));
        expect(target.height, greaterThanOrEqualTo(48));
        expect(find.text(label).hitTestable(), findsOneWidget);
      }
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await camera.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('camera presets use real factors on ${platform.name}', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dev.herdr.herdr_mobile/camera_zoom'),
        (call) async {
          calls.add(call);
          return call.method == 'getRange'
              ? {
                  'minZoom': 1.0,
                  'maxZoom': 8.0,
                  'wideZoom': 1.0,
                  'switchOverFactors': <double>[],
                }
              : null;
        },
      );
      final camera = _TestCamera();
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: QrScanScreenBody(phase: QrScanPhase.ready, controller: camera),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in ['1x', '2x', '5x']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('0.5x'), findsNothing);
      await tester.tap(find.text('5x'));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.text('5x')).flagsCollection.isSelected,
        Tristate.isTrue,
      );
      if (platform == TargetPlatform.iOS) {
        expect(calls.last.method, 'setZoom');
        expect(calls.last.arguments, {'zoom': 5.0, 'animated': false});
      } else {
        expect(camera.zoom, closeTo((1 - 1 / 5) / (1 - 1 / 8), 0.000001));
      }
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await camera.dispose();
      semantics.dispose();
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('wide camera presets respect the available range', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.herdr.herdr_mobile/camera_zoom'),
      (_) async => {
        'minZoom': 1.0,
        'maxZoom': 4.0,
        'wideZoom': 2.0,
        'switchOverFactors': [2.0],
      },
    );
    final camera = _TestCamera();
    await tester.pumpWidget(
      MaterialApp(
        home: QrScanScreenBody(phase: QrScanPhase.ready, controller: camera),
      ),
    );
    await tester.pumpAndSettle();
    for (final label in ['0.5x', '1x', '2x']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('5x'), findsNothing);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await camera.dispose();
  });

  testWidgets('pinch uses the gesture start ratio and keeps the last ratio', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.herdr.herdr_mobile/camera_zoom'),
      (_) async => {
        'minZoom': 1.0,
        'maxZoom': 8.0,
        'wideZoom': 1.0,
        'switchOverFactors': <double>[],
      },
    );
    final camera = _TestCamera();
    await tester.pumpWidget(
      MaterialApp(
        home: QrScanScreenBody(phase: QrScanPhase.ready, controller: camera),
      ),
    );
    await tester.pumpAndSettle();
    final center = tester.getCenter(find.byType(MobileScanner));
    Future<void> pinch() async {
      final first = await tester.startGesture(
        center - const Offset(40, 0),
        pointer: 1,
      );
      final second = await tester.startGesture(
        center + const Offset(40, 0),
        pointer: 2,
      );
      await tester.pump();
      await first.moveTo(center - const Offset(60, 0));
      await second.moveTo(center + const Offset(60, 0));
      await tester.pump();
      await first.moveTo(center - const Offset(80, 0));
      await second.moveTo(center + const Offset(80, 0));
      await tester.pump();
      await first.up();
      await second.up();
    }

    await pinch();
    expect(camera.zoom, closeTo((1 - 1 / 2) / (1 - 1 / 8), 0.000001));
    await pinch();
    expect(camera.zoom, closeTo((1 - 1 / 4) / (1 - 1 / 8), 0.000001));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await camera.dispose();
  });

  for (final phase in [
    QrScanPhase.ready,
    QrScanPhase.cameraStarting,
    QrScanPhase.cameraUnavailable,
  ]) {
    testWidgets('zoom is hidden without a range during ${phase.name}', (
      tester,
    ) async {
      final camera = _TestCamera();
      await tester.pumpWidget(
        MaterialApp(
          home: QrScanScreenBody(phase: phase, controller: camera),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1x'), findsNothing);
      expect(find.text('2x'), findsNothing);
      expect(find.text('5x'), findsNothing);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await camera.dispose();
    });
  }
  for (final code in [
    MobileScannerErrorCode.permissionDenied,
    MobileScannerErrorCode.genericError,
  ]) {
    testWidgets('native camera failure $code survives help', (tester) async {
      const connectivity = MethodChannel(
        'dev.fluttercommunity.plus/connectivity',
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        connectivity,
        (_) async => <String>['wifi'],
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          connectivity,
          null,
        );
      });
      const camera = MethodChannel(
        'dev.steenbakker.mobile_scanner/scanner/method',
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        camera,
        (_) async => null,
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          camera,
          null,
        );
      });
      var manualEntries = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: QrScanScreen(
            scanner: PairingScanner(controller: _FailedCamera(code)),
            effWords: const [],
            onManualEntry: () => manualEntries++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final message = code == MobileScannerErrorCode.permissionDenied
          ? 'The app needs the camera to scan. Open Settings to allow it.'
          : 'The camera is not available. Type the phrase instead.';
      expect(find.text(message), findsOneWidget);
      expect(
        find.text(
          'Point the camera at the QR code in the Relay pane on your computer.',
        ),
        findsNothing,
      );
      expect(_flashButton(tester).onPressed, isNull);
      expect(
        find.text('Open Settings'),
        code == MobileScannerErrorCode.permissionDenied
            ? findsOneWidget
            : findsNothing,
      );
      await tester.tap(find.byIcon(Symbols.info_rounded));
      await tester.pumpAndSettle();
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      for (final brightness in [Brightness.dark, Brightness.light]) {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        await tester.pumpAndSettle();
        final surface = tester
            .element(find.byType(HelpSheetContent))
            .findAncestorWidgetOfExactType<Material>()!;
        expect(surface.color, AppColor.resolve(brightness).bgRaised);
      }
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      await tester.tap(find.text('Type it in'));
      expect(manualEntries, 1);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
    });
  }

  testWidgets('default: draws the app bar title and the default hint', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: QrScanScreenBody(phase: QrScanPhase.ready)),
    );

    expect(find.text('Pair a computer'), findsOneWidget);
    expect(
      find.text(
        'Point the camera at the QR code in the Relay pane on your computer.',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Symbols.flash_off_rounded), findsOneWidget);
    expect(find.text('Type it in'), findsOneWidget);
  });
  testWidgets('flash icon starts off and toggles with exact semantics', (
    tester,
  ) async {
    var torchOn = false;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => QrScanScreenBody(
            phase: QrScanPhase.ready,
            torchOn: torchOn,
            onFlashToggle: () => setState(() => torchOn = !torchOn),
          ),
        ),
      ),
    );

    expect(find.byIcon(Symbols.flash_off_rounded), findsOneWidget);
    expect(find.byTooltip('Turn flash on'), findsOneWidget);

    await tester.tap(find.byTooltip('Turn flash on'));
    await tester.pump();

    expect(find.byIcon(Symbols.flash_on_rounded), findsOneWidget);
    expect(find.byTooltip('Turn flash off'), findsOneWidget);
  });

  testWidgets(
    'iOS: renders CupertinoNavigationBar, not Material AppBar, on iOS',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await tester.pumpWidget(
          const MaterialApp(home: QrScanScreenBody(phase: QrScanPhase.ready)),
        );

        final navBar = tester.widget<CupertinoNavigationBar>(
          find.byType(CupertinoNavigationBar),
        );
        expect(find.text('Pair a computer'), findsOneWidget);
        expect(navBar.trailing, isNotNull);
        expect(
          find.descendant(
            of: find.byType(CupertinoNavigationBar),
            matching: find.byType(CupertinoButton),
          ),
          findsNWidgets(2),
        );
        expect(
          find.descendant(
            of: find.widgetWithText(AppTextButton, 'Type it in'),
            matching: find.byType(CupertinoButton),
          ),
          findsOneWidget,
        );
        expect(find.byType(IconButton), findsNothing);
        expect(find.bySemanticsLabel('Turn flash on'), findsOneWidget);
        expect(find.byType(AppBar), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'loading, camera starting: shows the starting hint and disables flash',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: QrScanScreenBody(
            phase: QrScanPhase.cameraStarting,
            onManualEntry: () {},
          ),
        ),
      );

      expect(find.text('Starting camera...'), findsOneWidget);
      expect(_flashButton(tester).onPressed, isNull);
      // R-31-02-12: `type it in` stays enabled while the camera is still starting.
      final typeItIn = tester.widget<AppTextButton>(
        find.widgetWithText(AppTextButton, 'Type it in'),
      );
      expect(typeItIn.onPressed, isNotNull);
    },
  );

  testWidgets('pairing shows the host and permits cancellation', (
    tester,
  ) async {
    var cancelled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: QrScanScreenBody(
          phase: QrScanPhase.pairing,
          connectingHost: 'host',
          onCancel: () => cancelled = true,
        ),
      ),
    );
    expect(find.text('CONNECTING'), findsOneWidget);
    expect(find.text('Connecting to host...'), findsOneWidget);

    expect(_flashButton(tester).onPressed, isNull);
    expect(find.text('Type it in'), findsNothing);
    await tester.tap(find.text('Cancel'));
    expect(cancelled, isTrue);
  });

  testWidgets(
    'camera unavailable: shows the fallback line and only "type it in" is enabled',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: QrScanScreenBody(phase: QrScanPhase.cameraUnavailable),
        ),
      );

      expect(
        find.text('The camera is not available. Type the phrase instead.'),
        findsOneWidget,
      );
      // One instruction, not two: the bar drops "Point the camera..." while the preview
      // area says the camera is not there.
      expect(
        find.text(
          'Point the camera at the QR code in the Relay pane on your computer.',
        ),
        findsNothing,
      );
      expect(find.text('Type it in'), findsOneWidget);
    },
  );

  testWidgets(
    'permission denied: shows the recovery line and an Open Settings action',
    (tester) async {
      var openedSettings = false;
      await tester.pumpWidget(
        MaterialApp(
          home: QrScanScreenBody(
            phase: QrScanPhase.permissionDenied,
            onOpenSettings: () => openedSettings = true,
          ),
        ),
      );

      expect(
        find.text(
          'The app needs the camera to scan. Open Settings to allow it.',
        ),
        findsOneWidget,
      );
      expect(find.text('Open Settings'), findsOneWidget);
      expect(find.text('flash off'), findsNothing);
      expect(
        find.text(
          'Point the camera at the QR code in the Relay pane on your computer.',
        ),
        findsNothing,
      );

      await tester.tap(find.text('Open Settings'));
      expect(openedSettings, isTrue);
    },
  );

  testWidgets(
    'unreadable/malformed hint: takes the error treatment and keeps the scanner reachable',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: QrScanScreenBody(
            phase: QrScanPhase.ready,
            hint: QrHintIssue('That is not a Herdr pairing code.'),
          ),
        ),
      );

      expect(find.text('That is not a Herdr pairing code.'), findsOneWidget);
      // The scanner keeps running: both actions remain in the tree.
      expect(find.text('Type it in'), findsOneWidget);
    },
  );

  testWidgets(
    'offline: shows the persistent strip while both actions stay reachable',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: QrScanScreenBody(phase: QrScanPhase.ready, offline: true),
        ),
      );

      expect(
        find.text(
          'No network. Pairing needs a connection, and a phrase lasts ten minutes.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('a connected computer adds the switch caption, per R-30-945', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: QrScanScreenBody(
          phase: QrScanPhase.ready,
          hasConnectedHost: true,
        ),
      ),
    );

    expect(
      find.text('Pairing disconnects the computer you are using now.'),
      findsOneWidget,
    );
  });
}

({Rect frame, Rect bounds})? _viewfinderGeometry(WidgetTester tester) {
  for (final widget in tester.widgetList<CustomPaint>(
    find.descendant(
      of: find.byType(QrScanScreenBody),
      matching: find.byType(CustomPaint),
    ),
  )) {
    final finder = find.byWidget(widget);
    final canvas = _FrameCanvas();
    widget.painter?.paint(canvas, tester.getSize(finder));
    final frame = canvas.frame;
    if (frame != null) {
      final bounds = tester.getRect(finder);
      return (frame: frame.shift(bounds.topLeft), bounds: bounds);
    }
  }
  return null;
}

class _FrameCanvas extends TestRecordingCanvas {
  Rect? frame;

  @override
  void clipRect(
    Rect rect, {
    ClipOp clipOp = ClipOp.intersect,
    bool doAntiAlias = true,
  }) {
    if (clipOp == ClipOp.difference) frame = rect;
    super.clipRect(rect, clipOp: clipOp, doAntiAlias: doAntiAlias);
  }
}

class _FailedCamera extends MobileScannerController {
  _FailedCamera(this.code) : super(autoStart: false);

  final MobileScannerErrorCode code;

  @override
  Future<void> start({
    CameraFacing? cameraDirection,
    CameraLensType? cameraLensType,
  }) async {
    value = value.copyWith(
      isInitialized: true,
      error: MobileScannerException(errorCode: code),
    );
  }

  @override
  Future<void> pause() async {}
}

class _Keystore extends Mock implements KeystoreService {}

class _Store extends Mock implements PlainStore {}

class _Connectivity extends Mock implements Connectivity {}

class _TestCamera extends MobileScannerController {
  _TestCamera() : super(autoStart: false) {
    value = value.copyWith(zoomScale: 0);
  }
  final captures = StreamController<BarcodeCapture>.broadcast();
  double zoom = 0;
  @override
  Stream<BarcodeCapture> get barcodes => captures.stream;
  @override
  Future<void> start({
    CameraFacing? cameraDirection,
    CameraLensType? cameraLensType,
  }) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> setZoomScale(double scale) async {
    zoom = scale;
  }

  @override
  Future<void> resetZoomScale() async {
    zoom = 0;
  }

  @override
  Future<void> dispose() async {
    await captures.close();
    await super.dispose();
  }
}

class _RealHttp extends HttpOverrides {}
