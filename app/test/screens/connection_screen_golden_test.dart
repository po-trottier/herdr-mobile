/// Golden tests for `ConnectionScreen` (`app/lib/screens/connection_screen.dart`, `WP-18-d`/
/// `WP-21-a`), one per named row of `docs/31-mockups/13-connection.md`'s `## States` table
/// (R-90-011) this widget actually renders, each in both Selenized dark and light (R-32-012).
///
/// `ConnectionScreen` is stateful and reads its leg words and diagnostics off its own
/// `connectionState`/`diagnostics` streams, so it cannot be golden-tested as a pure body the way
/// `lock_screen_golden_test.dart` renders `LockScreenBody` directly. Each case below feeds a
/// one-shot `Stream.value(...)` (or omits the stream, for the states that need no live link),
/// mirroring `connection_screen_test.dart` and `connection_screen_actions_test.dart`'s own
/// pattern, rather than building a second fake-service scaffold.
///
/// Two states below (`disconnecting`, `disconnect_failed`) drive `Disconnect` itself: the first
/// taps it with a never-completing `Completer` and captures the frame before it settles, the
/// same technique `connection_screen_actions_test.dart`'s pending-button case already uses; the
/// second lets a thrown `onDisconnect` settle to its failed strip.
///
/// `docs/31-mockups/13-connection.md`'s wireframe also names an `Offline`/`Warning, relay not
/// encrypted` strip. `connection_screen.dart`'s own top doc comment records that `WP-21-a` built
/// only rows R-31-13-01 to 04, 06 to 10, 12, 13, 18, 19 — those two strips are a different,
/// not-yet-built work package, not a rendering defect this file's cases can show. The mockup's
/// old `COLOUR` group (`R-31-13-21`) is retired: the brand redesign fixes one chrome palette on
/// both platforms, so `_buildBody` now draws a constant `Chrome: fixed Herdr palette` row in its
/// place, and every case below renders it.
///
/// `stages_connecting`, `stages_failed` and `leg_two_down` (added 2026-09-09) cover the `STAGES`
/// group of `docs/03-product-decisions.md` R-03-113 item 3 (R-31-13-24) and the `Error, leg two
/// down` row it made reachable: a `handle_unknown` refusal means the relay answered and no Host
/// is registered, so leg one reads `connected` and leg two `offline` with the `Relay pane` line.
/// Every golden here was regenerated the same day for the ground revert of R-03-107: the body is
/// plain `color.bg.base`, no grid, no paper block.
///
/// Fonts, the app theme and the 375 x 667 reference size come from `golden_support.dart`
/// (`loadAppFonts`, `goldenApp`, `goldenReferenceSize`); see its doc comment for why.
/// `devicePixelRatio` stays fixed at 1.0.
library;

import 'dart:async' show Completer;

import 'package:flutter/widgets.dart' show Brightness, Scrollable;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart' show Ok;
import 'package:herdr_mobile/screens/connection_screen.dart';
import 'package:herdr_mobile/services/relay.dart'
    show
        ConnectionStage,
        RelayConnected,
        RelayConnecting,
        RelayConnectionState,
        RelayDisconnected,
        RelayReconnecting,
        RelayRegistrationError,
        RelayRegistrationErrorCode;
import 'package:herdr_mobile/widgets/app_filled_button.dart'
    show AppFilledButton;
import 'package:herdr_mobile/widgets/app_text_button.dart' show AppTextButton;
import 'package:material_ui/material_ui.dart' show CircularProgressIndicator;

import 'golden_support.dart';

/// The `Disconnect` text button, not the `Disconnect` row of the actions table, which shares
/// the word since labels draw as written (R-03-104).
final Finder _disconnectButton = find.widgetWithText(
  AppTextButton,
  'Disconnect',
);

/// A full, internally consistent snapshot with every field distinct, matching
/// `docs/31-mockups/13-connection.md`'s wireframe numbers (round trip 49 ms, protocol 22,
/// version `0.8.2-p2`, grid `144x50`, longest line 141, unknown SGR 0, frames 1284/96, bytes
/// 1.6 MB / 9.8 MB, a 16% compression ratio).
const ConnectionDiagnostics _healthySnapshot = ConnectionDiagnostics(
  herdrProtocol: 22,
  herdrVersion: '0.8.2-p2',
  framesIn: 1284,
  framesOut: 96,
  bytesInOnWire: 1600000,
  bytesInUnpacked: 9800000,
  roundTrip: Duration(milliseconds: 49),
  gridColumns: 144,
  gridRows: 50,
  longestLineDrawn: 141,
  unknownSgrCount: 0,
);

const _themes = <(String, Brightness)>[
  ('dark', Brightness.dark),
  ('light', Brightness.light),
];

void main() {
  setUpAll(loadAppFonts);

  Future<void> setSize(WidgetTester tester) async {
    tester.view.physicalSize = goldenReferenceSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  for (final (themeName, brightness) in _themes) {
    // Default, healthy (R-31-13-01, 06 to 11, 19): both legs connected, every counter filled,
    // the alerts group reads `ready` with no `Fix this in Alerts.` line.
    testWidgets(
      'connected ($themeName) matches docs/31-mockups/13-connection.md',
      (tester) async {
        await setSize(tester);
        await tester.pumpWidget(
          goldenApp(
            brightness: brightness,
            adjust: (ambient) => ambient.copyWith(disableAnimations: true),
            child: ConnectionScreen(
              hostId: 'host-1',
              hostName: 'patrick-desk',
              connectionState: Stream<RelayConnectionState>.value(
                const RelayConnected(),
              ),
              relayOrigin: 'https://relay.example.com',
              diagnostics: Stream<ConnectionDiagnostics>.value(
                _healthySnapshot,
              ),
              alertsDeliveryWord: 'ready',
              onReconnect: () async => const Ok<void>(null),
              onDisconnect: () async {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('patrick-desk'), findsWidgets);
        expect(find.text('CONNECTED'), findsNWidgets(2));
        expect(find.text('49 ms'), findsOneWidget);
        expect(find.text('FIX THIS IN ALERTS.'), findsNothing);

        await expectLater(
          find.byType(ConnectionScreen),
          matchesGoldenFile(
            'goldens/connection_screen_connected_$themeName.png',
          ),
        );
      },
    );

    // Loading (R-31-13-06): the correlated round trip has not returned, but the local session
    // counters already read their real starting value, `0`, never `-`.
    testWidgets(
      'loading ($themeName) matches docs/31-mockups/13-connection.md',
      (tester) async {
        await setSize(tester);
        await tester.pumpWidget(
          goldenApp(
            brightness: brightness,
            adjust: (ambient) => ambient.copyWith(disableAnimations: true),
            child: ConnectionScreen(
              hostId: 'host-1',
              hostName: 'patrick-desk',
              connectionState: const Stream<RelayConnectionState>.empty(),
              relayOrigin: 'https://relay.example.com',
              diagnostics: Stream<ConnectionDiagnostics>.value(
                const ConnectionDiagnostics(
                  framesIn: 0,
                  framesOut: 0,
                  bytesInOnWire: 0,
                  bytesInUnpacked: 0,
                ),
              ),
              onReconnect: () async => const Ok<void>(null),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('CHECKING'), findsNWidgets(2));
        expect(find.text('-'), findsWidgets);

        await expectLater(
          find.byType(ConnectionScreen),
          matchesGoldenFile('goldens/connection_screen_loading_$themeName.png'),
        );
      },
    );

    // Error, leg one down (callout 4: "That honesty matters more than a guess"): the relay is
    // unreachable, so leg two honestly reads `unknown` rather than a guess. The same close code
    // also feeds `LAST ERROR`, per R-31-13-02.
    testWidgets(
      'leg_one_down ($themeName) matches docs/31-mockups/13-connection.md',
      (tester) async {
        await setSize(tester);
        await tester.pumpWidget(
          goldenApp(
            brightness: brightness,
            adjust: (ambient) => ambient.copyWith(disableAnimations: true),
            child: ConnectionScreen(
              hostId: 'host-1',
              hostName: 'patrick-desk',
              connectionState: Stream<RelayConnectionState>.value(
                const RelayDisconnected(closeCode: 1006),
              ),
              relayOrigin: 'https://relay.example.com',
              onReconnect: () async => const Ok<void>(null),
              onDisconnect: () async {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('OFFLINE'), findsOneWidget);
        expect(find.text('UNKNOWN'), findsOneWidget);

        await expectLater(
          find.byType(ConnectionScreen),
          matchesGoldenFile(
            'goldens/connection_screen_leg_one_down_$themeName.png',
          ),
        );
      },
    );

    // Error, host in use (R-30-942): leg one stays connected, leg two takes `treat.warning` and
    // gains its two explanatory lines, and `Reconnect now` becomes `Try again`.
    testWidgets(
      'host_in_use ($themeName) matches docs/31-mockups/13-connection.md',
      (tester) async {
        await setSize(tester);
        await tester.pumpWidget(
          goldenApp(
            brightness: brightness,
            adjust: (ambient) => ambient.copyWith(disableAnimations: true),
            child: ConnectionScreen(
              hostId: 'host-1',
              hostName: 'patrick-desk',
              connectionState: Stream<RelayConnectionState>.value(
                const RelayRegistrationError(
                  RelayRegistrationErrorCode.hostInUse,
                  'host_in_use',
                ),
              ),
              relayOrigin: 'https://relay.example.com',
              onReconnect: () async => const Ok<void>(null),
              onDisconnect: () async {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('IN USE'), findsOneWidget);
        expect(
          find.text('Another phone is using patrick-desk.'),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(
          find.text('Try again'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Try again'), findsOneWidget);
        await expectLater(
          find.byType(ConnectionScreen),
          matchesGoldenFile(
            'goldens/connection_screen_host_in_use_$themeName.png',
          ),
        );
      },
    );

    // Error, leg two down (states table): the relay answered `handle_unknown`, so leg one reads
    // `connected`, leg two `offline` with `The Relay pane may be closed on patrick-desk.`, and
    // the `Registering handle` stage carries the relay's raw sentence (R-11-092).
    testWidgets(
      'leg_two_down ($themeName) matches docs/31-mockups/13-connection.md',
      (tester) async {
        await setSize(tester);
        await tester.pumpWidget(
          goldenApp(
            brightness: brightness,
            adjust: (ambient) => ambient.copyWith(disableAnimations: true),
            child: ConnectionScreen(
              hostId: 'host-1',
              hostName: 'patrick-desk',
              connectionState: Stream<RelayConnectionState>.value(
                const RelayRegistrationError(
                  RelayRegistrationErrorCode.handleUnknown,
                  'No Host is registered under this handle',
                ),
              ),
              relayOrigin: 'https://relay.example.com',
              onReconnect: () async => const Ok<void>(null),
              onDisconnect: () async {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('CONNECTED'), findsOneWidget);
        expect(find.text('OFFLINE'), findsOneWidget);
        expect(
          find.text('The Relay pane may be closed on patrick-desk.'),
          findsOneWidget,
        );
        expect(
          find.text('No Host is registered under this handle'),
          findsOneWidget,
        );

        await expectLater(
          find.byType(ConnectionScreen),
          matchesGoldenFile(
            'goldens/connection_screen_leg_two_down_$themeName.png',
          ),
        );
      },
    );

    // Leg one `connecting` (callout 2, `treat.warning`), between reconnect attempts.
    testWidgets(
      'leg_connecting ($themeName) matches docs/31-mockups/13-connection.md',
      (tester) async {
        await setSize(tester);
        await tester.pumpWidget(
          goldenApp(
            brightness: brightness,
            adjust: (ambient) => ambient.copyWith(disableAnimations: true),
            child: ConnectionScreen(
              hostId: 'host-1',
              hostName: 'patrick-desk',
              connectionState: Stream<RelayConnectionState>.value(
                const RelayReconnecting(Duration(seconds: 5)),
              ),
              relayOrigin: 'https://relay.example.com',
              onReconnect: () async => const Ok<void>(null),
              onDisconnect: () async {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('CONNECTING'), findsOneWidget);
        expect(find.text('UNKNOWN'), findsOneWidget);

        await expectLater(
          find.byType(ConnectionScreen),
          matchesGoldenFile(
            'goldens/connection_screen_leg_connecting_$themeName.png',
          ),
        );
      },
    );

    // Saved, not connected (R-30-946): both legs read `not connected` with no treatment, and
    // `Disconnect` is absent because there is no link to close, per R-31-13-13.
    testWidgets(
      'saved_not_connected ($themeName) matches docs/31-mockups/13-connection.md',
      (tester) async {
        await setSize(tester);
        await tester.pumpWidget(
          goldenApp(
            brightness: brightness,
            adjust: (ambient) => ambient.copyWith(disableAnimations: true),
            child: ConnectionScreen(
              hostId: 'host-1',
              hostName: 'patrick-desk',
              onReconnect: () async => const Ok<void>(null),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('NOT CONNECTED'), findsNWidgets(2));
        expect(_disconnectButton, findsNothing);
        await tester.scrollUntilVisible(
          find.text('Reconnect now'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Reconnect now'), findsOneWidget);

        await expectLater(
          find.byType(ConnectionScreen),
          matchesGoldenFile(
            'goldens/connection_screen_saved_not_connected_$themeName.png',
          ),
        );
      },
    );

    // Connecting, staged (R-03-113 item 3, R-31-13-24): an attempt is at the Noise handshake,
    // so the three stages before it read `ok`, the handshake reads `working` (its pulse held
    // still by `disableAnimations`), `Host info` reads `pending`, and both legs read `checking`.
    testWidgets(
      'stages_connecting ($themeName) matches docs/31-mockups/13-connection.md',
      (tester) async {
        await setSize(tester);
        await tester.pumpWidget(
          goldenApp(
            brightness: brightness,
            adjust: (ambient) => ambient.copyWith(disableAnimations: true),
            child: ConnectionScreen(
              hostId: 'host-1',
              hostName: 'patrick-desk',
              connectionState: Stream<RelayConnectionState>.value(
                const RelayConnecting(ConnectionStage.handshake),
              ),
              relayOrigin: 'https://relay.example.com',
              onReconnect: () async => const Ok<void>(null),
              onDisconnect: () async {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('STAGES'), findsOneWidget);
        expect(find.text('OK'), findsNWidgets(3));
        expect(find.text('WORKING'), findsOneWidget);
        expect(find.text('PENDING'), findsOneWidget);

        await expectLater(
          find.byType(ConnectionScreen),
          matchesGoldenFile(
            'goldens/connection_screen_stages_connecting_$themeName.png',
          ),
        );
      },
    );

    // Error, stage failed (R-31-13-24, R-30-803, R-30-804): the attempt stopped at the Noise
    // handshake. That row takes the `error` bar with the raw text in `type.mono.code` under it,
    // `Host info` stays `pending`, and the one filled control reads `Try again`.
    testWidgets(
      'stages_failed ($themeName) matches docs/31-mockups/13-connection.md',
      (tester) async {
        await setSize(tester);
        await tester.pumpWidget(
          goldenApp(
            brightness: brightness,
            adjust: (ambient) => ambient.copyWith(disableAnimations: true),
            child: ConnectionScreen(
              hostId: 'host-1',
              hostName: 'patrick-desk',
              connectionState: Stream<RelayConnectionState>.value(
                const RelayDisconnected(
                  failedStage: ConnectionStage.handshake,
                  failure: 'the Noise handshake failed: FormatException',
                ),
              ),
              relayOrigin: 'https://relay.example.com',
              onReconnect: () async => const Ok<void>(null),
              onDisconnect: () async {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('ERROR'), findsOneWidget);
        expect(
          find.text('the Noise handshake failed: FormatException'),
          findsOneWidget,
        );
        expect(find.text('Reconnect now'), findsNothing);

        await expectLater(
          find.byType(ConnectionScreen),
          matchesGoldenFile(
            'goldens/connection_screen_stages_failed_$themeName.png',
          ),
        );
      },
    );

    // Disconnecting: `Disconnect` was tapped and the link is still closing, so it shows the
    // in-place spinner in place of its label and `Reconnect now` is disabled. Captured mid-flight
    // with a never-completing `Completer`, the same technique
    // `connection_screen_actions_test.dart`'s pending-`Reconnect now` case already uses.
    testWidgets(
      'disconnecting ($themeName) matches docs/31-mockups/13-connection.md',
      (tester) async {
        await setSize(tester);
        final completer = Completer<void>();
        addTearDown(() => completer.complete());
        await tester.pumpWidget(
          goldenApp(
            brightness: brightness,
            adjust: (ambient) => ambient.copyWith(disableAnimations: true),
            child: ConnectionScreen(
              hostId: 'host-1',
              hostName: 'patrick-desk',
              connectionState: Stream<RelayConnectionState>.value(
                const RelayConnected(),
              ),
              relayOrigin: 'https://relay.example.com',
              diagnostics: Stream<ConnectionDiagnostics>.value(
                _healthySnapshot,
              ),
              onReconnect: () async => const Ok<void>(null),
              onDisconnect: () => completer.future,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          _disconnectButton,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        // The `STAGES` rows make the list taller than the viewport by more than one
        // `scrollUntilVisible` step, which stops at the first built frame of the button.
        await tester.ensureVisible(_disconnectButton);
        await tester.pumpAndSettle();
        await tester.tap(_disconnectButton);
        await tester.pump();

        // The mockup's `Disconnecting` row: the in-place spinner of R-32-350 replaces the
        // `Disconnect` label, and `Reconnect now` is disabled while the link closes.
        expect(_disconnectButton, findsNothing);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(
          tester
              .widget<AppFilledButton>(find.byType(AppFilledButton))
              .onPressed,
          isNull,
        );

        await expectLater(
          find.byType(ConnectionScreen),
          matchesGoldenFile(
            'goldens/connection_screen_disconnecting_$themeName.png',
          ),
        );
      },
    );

    // Error, disconnect failed (R-31-13-15): the close did not complete, the route stays, and a
    // strip under the app bar carries the raw failure text and a `Try again`.
    testWidgets(
      'disconnect_failed ($themeName) matches docs/31-mockups/13-connection.md',
      (tester) async {
        await setSize(tester);
        await tester.pumpWidget(
          goldenApp(
            brightness: brightness,
            adjust: (ambient) => ambient.copyWith(disableAnimations: true),
            child: ConnectionScreen(
              hostId: 'host-1',
              hostName: 'patrick-desk',
              connectionState: Stream<RelayConnectionState>.value(
                const RelayConnected(),
              ),
              relayOrigin: 'https://relay.example.com',
              diagnostics: Stream<ConnectionDiagnostics>.value(
                _healthySnapshot,
              ),
              onReconnect: () async => const Ok<void>(null),
              onDisconnect: () async =>
                  throw Exception('websocket closed 1006'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          _disconnectButton,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(_disconnectButton);
        await tester.pumpAndSettle();
        await tester.tap(_disconnectButton);
        await tester.pumpAndSettle();

        expect(
          find.text('Could not disconnect. The link is still open.'),
          findsOneWidget,
        );

        await expectLater(
          find.byType(ConnectionScreen),
          matchesGoldenFile(
            'goldens/connection_screen_disconnect_failed_$themeName.png',
          ),
        );
      },
    );

    // Alerts silenced or off (R-31-13-22): the `ALERTS` header carries the delivery word and the
    // group gains the `Fix this in Alerts.` line.
    testWidgets(
      'alerts_silenced ($themeName) matches docs/31-mockups/13-connection.md',
      (tester) async {
        await setSize(tester);
        await tester.pumpWidget(
          goldenApp(
            brightness: brightness,
            adjust: (ambient) => ambient.copyWith(disableAnimations: true),
            child: ConnectionScreen(
              hostId: 'host-1',
              hostName: 'patrick-desk',
              connectionState: Stream<RelayConnectionState>.value(
                const RelayConnected(),
              ),
              relayOrigin: 'https://relay.example.com',
              diagnostics: Stream<ConnectionDiagnostics>.value(
                _healthySnapshot,
              ),
              alertsDeliveryWord: 'silenced',
              onOpenAlertsSettings: () {},
              onReconnect: () async => const Ok<void>(null),
              onDisconnect: () async {},
            ),
          ),
        );
        // `ALERTS` sits below the fold at the 375x667 reference size once every other group is
        // filled in, so this case scrolls it into view: the point of this golden is the group
        // itself, not the legs above it, which every other case already covers.
        await tester.scrollUntilVisible(
          find.text('ALERTS'),
          300,
          scrollable: find.byType(Scrollable),
        );
        await tester.pumpAndSettle();

        expect(find.text('SILENCED'), findsOneWidget);
        // R-32-561: the strip names its destination in one sentence and the whole strip
        // routes there; there is no separate text action.
        expect(
          find.text('Alerts are silenced. Fix this in Alerts.'),
          findsOneWidget,
        );
        expect(find.text('FIX THIS IN ALERTS.'), findsNothing);

        await expectLater(
          find.byType(ConnectionScreen),
          matchesGoldenFile(
            'goldens/connection_screen_alerts_silenced_$themeName.png',
          ),
        );
      },
    );
  }
}
