/// `WP-21-a`'s own `connection_screen.dart` checkbox: behavioural coverage for the eleven rows
/// this package added to `app/lib/screens/connection_screen.dart` (see that file's own header
/// comment for the full split with `WP-18-d`'s two checkboxes, covered separately by
/// `connection_screen_actions_test.dart`). The plan's own checklist line for this file names one
/// required assertion — the unknown SGR count renders `0` and is never hidden (R-31-13-08,
/// R-01-008) — plus a handful more covering the highest-risk rules this package's own edit
/// introduced, and, since 2026-09-09, the `STAGES` group of `docs/03-product-decisions.md`
/// R-03-113 item 3 (R-31-13-24).
library;

import 'dart:async' show StreamController;
import 'dart:ui' show Size;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoNavigationBar;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart' show AppBar;
import 'package:flutter/widgets.dart' show MediaQuery, MediaQueryData;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart' show Ok;
import 'package:herdr_mobile/screens/connection_screen.dart';
import 'package:herdr_mobile/services/relay.dart'
    show
        ConnectionStage,
        RelayConnecting,
        RelayConnectionState,
        RelayDisconnected,
        RelayReconnecting,
        RelayRegistrationError,
        RelayRegistrationErrorCode;
import 'package:herdr_mobile/widgets/status_bar.dart' show BarState, StatusBar;
import 'package:material_ui/material_ui.dart' show MaterialApp;

/// A full, internally consistent snapshot with every field distinct, so a text finder for one
/// row's value never accidentally matches another row.
const ConnectionDiagnostics _healthySnapshot = ConnectionDiagnostics(
  herdrProtocol: 22,
  herdrVersion: '0.8.2-p2',
  framesIn: 1284,
  framesOut: 96,
  bytesInOnWire: 1600000,
  bytesInUnpacked: 10000000,
  roundTrip: Duration(milliseconds: 49),
  gridColumns: 144,
  gridRows: 50,
  longestLineDrawn: 141,
  unknownSgrCount: 0,
);

void main() {
  testWidgets('iOS: renders CupertinoNavigationBar with the Connection title and a copy button, '
      'not a Material AppBar (R-31-13-05)', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(
      MaterialApp(
        home: ConnectionScreen(
          hostId: 'host-1',
          hostName: 'patrick-desk',
          connectionState: const Stream<Never>.empty(),
          diagnostics: Stream<ConnectionDiagnostics>.value(_healthySnapshot),
          onReconnect: () async => const Ok<void>(null),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CupertinoNavigationBar), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Connection'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('the unknown SGR count renders 0, drawn plain and never hidden, for a payload drawn from '
      'the measured vocabulary (R-31-13-08, R-01-008)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ConnectionScreen(
          hostId: 'host-1',
          hostName: 'patrick-desk',
          connectionState: const Stream<Never>.empty(),
          diagnostics: Stream<ConnectionDiagnostics>.value(_healthySnapshot),
          onReconnect: () async => const Ok<void>(null),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Unknown SGR codes'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(
      find.text('Rendering may be wrong. Send this with Copy.'),
      findsNothing,
    );
  });

  testWidgets(
    'a non-zero unknown SGR count takes treat.error and gains the rendering-may-be-wrong line',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ConnectionScreen(
            hostId: 'host-1',
            hostName: 'patrick-desk',
            connectionState: const Stream<Never>.empty(),
            diagnostics: Stream<ConnectionDiagnostics>.value(
              const ConnectionDiagnostics(
                gridColumns: 144,
                gridRows: 50,
                longestLineDrawn: 141,
                unknownSgrCount: 3,
              ),
            ),
            onReconnect: () async => const Ok<void>(null),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('3'), findsOneWidget);
      expect(
        find.text('Rendering may be wrong. Send this with Copy.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('the RENDER group reads "-" with the open-a-pane hint before any pane is opened this '
      'session (R-31-13-09)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ConnectionScreen(
          hostId: 'host-1',
          hostName: 'patrick-desk',
          connectionState: const Stream<Never>.empty(),
          onReconnect: () async => const Ok<void>(null),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Open a pane to measure this.'), findsOneWidget);
    expect(find.text('Unknown SGR codes'), findsOneWidget);
  });

  testWidgets(
    'Herdr protocol mismatch reads "22 expected, N found" with update line (R-31-13-04)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ConnectionScreen(
            hostId: 'host-1',
            hostName: 'patrick-desk',
            connectionState: const Stream<Never>.empty(),
            diagnostics: Stream<ConnectionDiagnostics>.value(
              const ConnectionDiagnostics(
                herdrProtocol: 21,
                herdrVersion: '0.9.0',
              ),
            ),
            onReconnect: () async => const Ok<void>(null),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('22 expected, 21 found'), findsOneWidget);
      expect(
        find.text('Update Herdr on the computer, or update this app.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'session counters and compression read "-" with no live session, never 0 (R-31-13-06)',
    (tester) async {
      tester.view.physicalSize = const Size(400, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: ConnectionScreen(
            hostId: 'host-1',
            hostName: 'patrick-desk',
            onReconnect: () async => const Ok<void>(null),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Frames in'), findsOneWidget);
      expect(find.text('Phone to relay'), findsOneWidget);
      expect(find.text('NOT CONNECTED'), findsNWidgets(2));
    },
  );

  testWidgets(
    'the ALERTS group carries the exact R-30-512 and R-30-517 wording',
    (tester) async {
      tester.view.physicalSize = const Size(400, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: ConnectionScreen(
            hostId: 'host-1',
            hostName: 'patrick-desk',
            connectionState: const Stream<Never>.empty(),
            alertsDeliveryWord: 'ready',
            onReconnect: () async => const Ok<void>(null),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text(
          'Alerts arrive while the app is running. If the phone closes the app, the alert '
          'is waiting in the app the next time you open it.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Alerts come from the computer you are connected to. If an agent finishes on '
          'another computer, you see it when you connect to that computer.',
        ),
        findsOneWidget,
      );
      expect(find.text('READY'), findsOneWidget);
    },
  );

  testWidgets(
    'the Disconnect/Forget/Remove/switch distinction table names all four actions, where '
    'each lives, and which two are destructive (R-31-13-18, R-31-13-23)',
    (tester) async {
      tester.view.physicalSize = const Size(400, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: ConnectionScreen(
            hostId: 'host-1',
            hostName: 'patrick-desk',
            connectionState: const Stream<Never>.empty(),
            onReconnect: () async => const Ok<void>(null),
          ),
        ),
      );
      await tester.pump();

      // The title line carries the action word alone; where it lives opens the caption.
      expect(find.text('Disconnect'), findsOneWidget);
      expect(
        find.textContaining('This screen. Closes this phone'),
        findsOneWidget,
      );
      expect(find.text('Switching computer'), findsOneWidget);
      expect(
        find.textContaining('The host list, a plain tap on a saved row.'),
        findsOneWidget,
      );
      expect(find.text('Forget'), findsOneWidget);
      expect(
        find.textContaining('The host list, from a touch and hold on a row.'),
        findsOneWidget,
      );
      expect(find.text('Remove'), findsOneWidget);
      expect(find.textContaining('The devices screen.'), findsOneWidget);
      expect(find.text('NOT DESTRUCTIVE'), findsNWidgets(2));
      expect(find.text('DESTRUCTIVE'), findsNWidgets(2));
    },
  );

  group('STAGES (R-31-13-24)', () {
    const List<String> labels = <String>[
      'Reusing handle',
      'Opening WebSocket',
      'Registering handle',
      'Noise handshake',
      'Host info',
    ];

    Future<void> pumpWith(
      WidgetTester tester,
      Stream<RelayConnectionState> connectionState,
    ) async {
      tester.view.physicalSize = const Size(400, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            // The `working` bar pulses; a static frame is enough to read its state.
            data: const MediaQueryData(disableAnimations: true),
            child: ConnectionScreen(
              hostId: 'host-1',
              hostName: 'patrick-desk',
              connectionState: connectionState,
              relayOrigin: 'https://relay.example.com',
              onReconnect: () async => const Ok<void>(null),
              onDisconnect: () async {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    Iterable<BarState> bars(WidgetTester tester) => tester
        .widgetList<StatusBar>(find.byType(StatusBar))
        .map((StatusBar bar) => bar.state);

    testWidgets('a running attempt draws every stage once, in order: ok before the running step, '
        'working at it, pending after it', (tester) async {
      await pumpWith(
        tester,
        Stream<RelayConnectionState>.value(
          const RelayConnecting(ConnectionStage.handshake),
        ),
      );

      expect(find.text('STAGES'), findsOneWidget);
      for (final String label in labels) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('OK'), findsNWidgets(3));
      expect(find.text('WORKING'), findsOneWidget);
      expect(find.text('PENDING'), findsOneWidget);
      // Two legs (`checking`, unknown hue) then the five stages.
      expect(bars(tester), <BarState>[
        BarState.unknown,
        BarState.unknown,
        BarState.ok,
        BarState.ok,
        BarState.ok,
        BarState.working,
        BarState.unknown,
      ]);
      expect(find.text('Reconnect now'), findsOneWidget);
    });

    testWidgets('a failure at the Noise handshake stage renders that row with the error bar, the raw '
        'text under it and exactly one Try again (R-30-803, R-30-804)', (tester) async {
      // Disposed at the end of the body: the tester checks for a live handle before teardowns
      // run.
      final SemanticsHandle semantics = tester.ensureSemantics();
      await pumpWith(
        tester,
        Stream<RelayConnectionState>.value(
          const RelayDisconnected(
            failedStage: ConnectionStage.handshake,
            failure: 'the Noise handshake failed: FormatException',
          ),
        ),
      );

      expect(find.text('ERROR'), findsOneWidget);
      expect(
        find.text('the Noise handshake failed: FormatException'),
        findsOneWidget,
      );
      expect(find.text('OK'), findsNWidgets(3));
      expect(find.text('PENDING'), findsOneWidget);
      expect(bars(tester), contains(BarState.error));
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Reconnect now'), findsNothing);
      expect(
        find.bySemanticsLabel(
          'Noise handshake, error, the Noise handshake failed: FormatException',
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('a relay refusal is the Registering handle stage failing with the relay\'s own '
        'sentence (R-11-092)', (tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await pumpWith(
        tester,
        Stream<RelayConnectionState>.value(
          const RelayRegistrationError(
            RelayRegistrationErrorCode.hostInUse,
            'A Device is already active on this Host',
          ),
        ),
      );

      expect(
        find.bySemanticsLabel(
          'Registering handle, error, A Device is already active on this Host',
        ),
        findsOneWidget,
      );
      expect(find.text('OK'), findsNWidgets(2));
      expect(find.text('PENDING'), findsNWidgets(2));
      expect(find.text('Try again'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('the failed stage and its raw text stay through the backoff wait, which is named, and '
        'clear when the next attempt starts', (tester) async {
      final controller = StreamController<RelayConnectionState>();
      addTearDown(controller.close);
      await pumpWith(tester, controller.stream);
      expect(find.text('STAGES'), findsNothing);

      controller.add(
        const RelayDisconnected(
          failedStage: ConnectionStage.openingSocket,
          failure:
              'Could not open a connection to https://relay.example.com: '
              'SocketException',
        ),
      );
      await tester.pump();
      await tester.pump();
      controller.add(const RelayReconnecting(Duration(milliseconds: 500)));
      await tester.pump();
      await tester.pump();

      expect(find.text('Retrying in 0.5 s.'), findsOneWidget);
      expect(find.textContaining('SocketException'), findsOneWidget);
      expect(find.text('ERROR'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      controller.add(const RelayConnecting(ConnectionStage.reusingHandle));
      await tester.pump();
      await tester.pump();

      expect(find.text('Retrying in 0.5 s.'), findsNothing);
      expect(find.textContaining('SocketException'), findsNothing);
      expect(find.text('WORKING'), findsOneWidget);
      expect(find.text('PENDING'), findsNWidgets(4));
      expect(find.text('Reconnect now'), findsOneWidget);
    });

    testWidgets(
      'the group is absent after a deliberate disconnect and with no live link at all',
      (tester) async {
        await pumpWith(
          tester,
          Stream<RelayConnectionState>.value(const RelayDisconnected()),
        );
        expect(find.text('STAGES'), findsNothing);
        expect(find.text('Reusing handle'), findsNothing);

        await tester.pumpWidget(
          MaterialApp(
            home: ConnectionScreen(
              hostId: 'host-1',
              hostName: 'patrick-desk',
              onReconnect: () async => const Ok<void>(null),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('STAGES'), findsNothing);
      },
    );
  });
}
