/// Behavioural coverage for `WP-18-d`'s two `connection_screen.dart` checkboxes only
/// (`app/lib/screens/connection_screen.dart`): `Reconnect now` (R-31-13-20) and the
/// `Disconnect` text action (R-31-13-13, R-31-13-15). `app/test/screens/connection_screen_test.dart`
/// is reserved for `WP-21-a`'s own later, full-mockup test, so this file lives under a
/// different name and asserts nothing about the legs, `RENDER`, `COLOUR` or `ALERTS` groups.
library;

import 'dart:async' show Completer;

import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart' show Ok, Result;
import 'package:herdr_mobile/screens/connection_screen.dart';
import 'package:herdr_mobile/widgets/app_filled_button.dart';
import 'package:herdr_mobile/widgets/app_text_button.dart';
import 'package:material_ui/material_ui.dart'
    show AlertDialog, Dialog, MaterialApp;

/// The `Disconnect` text button, not the `Disconnect` row of the actions table, which shares
/// the word since labels draw as written (R-03-104).
final Finder _disconnectButton = find.widgetWithText(
  AppTextButton,
  'Disconnect',
);

void main() {
  testWidgets(
    'Reconnect now calls onReconnect and disables the button while pending',
    (tester) async {
      // The actions are the last rows of one list (13-connection.md); a tall view keeps them on screen.
      tester.view.physicalSize = const Size(1080, 8000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final completer = Completer<Result<void>>();
      var callCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ConnectionScreen(
            hostId: 'host-1',
            hostName: 'patrick-desk',
            onReconnect: () {
              callCount++;
              return completer.future;
            },
          ),
        ),
      );
      await tester.tap(find.text('Reconnect now'));
      await tester.pump();

      expect(callCount, 1);
      final button = tester.widget<AppFilledButton>(
        find.byType(AppFilledButton),
      );
      expect(button.onPressed, isNull);
      expect(button.isLoading, isTrue);

      completer.complete(const Ok<void>(null));
      await tester.pumpAndSettle();

      final settledButton = tester.widget<AppFilledButton>(
        find.byType(AppFilledButton),
      );
      expect(settledButton.onPressed, isNotNull);
      expect(settledButton.isLoading, isFalse);
    },
  );

  testWidgets(
    'Disconnect is absent when connectionState and onDisconnect are null',
    (tester) async {
      // The actions are the last rows of one list (13-connection.md); a tall view keeps them on screen.
      tester.view.physicalSize = const Size(1080, 8000);
      tester.view.devicePixelRatio = 1;
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

      expect(_disconnectButton, findsNothing);
    },
  );

  testWidgets(
    'Disconnect is present and enabled, awaits onDisconnect and calls onDisconnected on success',
    (tester) async {
      // The actions are the last rows of one list (13-connection.md); a tall view keeps them on screen.
      tester.view.physicalSize = const Size(1080, 8000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var disconnectCalls = 0;
      var disconnectedCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ConnectionScreen(
            hostId: 'host-1',
            hostName: 'patrick-desk',
            connectionState: const Stream<Never>.empty(),
            onReconnect: () async => const Ok<void>(null),
            onDisconnect: () async {
              disconnectCalls++;
            },
            onDisconnected: () => disconnectedCalls++,
          ),
        ),
      );

      final disconnectButton = tester.widget<AppTextButton>(
        find.byType(AppTextButton),
      );
      expect(disconnectButton.onPressed, isNotNull);
      await tester.tap(_disconnectButton);
      // One frame, not `pumpAndSettle`: a successful disconnect leaves the screen in its
      // `Disconnecting` state (the app routes away), whose spinner never settles.
      await tester.pump();

      expect(disconnectCalls, 1);
      expect(disconnectedCalls, 1);
      expect(
        find.text('Could not disconnect. The link is still open.'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'a thrown onDisconnect shows the disconnect-failed strip and never calls onDisconnected',
    (tester) async {
      // The actions are the last rows of one list (13-connection.md); a tall view keeps them on screen.
      tester.view.physicalSize = const Size(1080, 8000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var disconnectedCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ConnectionScreen(
            hostId: 'host-1',
            hostName: 'patrick-desk',
            connectionState: const Stream<Never>.empty(),
            onReconnect: () async => const Ok<void>(null),
            onDisconnect: () async {
              throw Exception('websocket closed 1006');
            },
            onDisconnected: () => disconnectedCalls++,
          ),
        ),
      );
      await tester.tap(_disconnectButton);
      await tester.pumpAndSettle();

      expect(
        find.text('Could not disconnect. The link is still open.'),
        findsOneWidget,
      );
      expect(disconnectedCalls, 0);
      // The route stays: `Disconnect` is still drawn, ready for `Try again`, per R-31-13-15.
      expect(_disconnectButton, findsOneWidget);
    },
  );

  testWidgets(
    'Disconnect closes the link immediately with no modal in the way (R-30-960)',
    (tester) async {
      // The actions are the last rows of one list (13-connection.md); a tall view keeps them on screen.
      tester.view.physicalSize = const Size(1080, 8000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var disconnectCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ConnectionScreen(
            hostId: 'host-1',
            hostName: 'patrick-desk',
            connectionState: const Stream<Never>.empty(),
            onReconnect: () async => const Ok<void>(null),
            onDisconnect: () async {
              disconnectCalls++;
            },
          ),
        ),
      );

      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(_disconnectButton);
      await tester.pump();

      // R-30-960: `Disconnect` is not destructive and MUST NOT raise a modal. `onDisconnect`
      // fires the instant the button is tapped, with no confirmation dialog gating it, and no
      // dialog route ever appears.
      expect(disconnectCalls, 1);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
}
