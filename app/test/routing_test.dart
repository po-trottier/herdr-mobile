/// Structural coverage for [AppLockOfferSheet] (`app/lib/routing.dart`), R-30-522's exact
/// copy and its two actions. Public specifically so this file can pump it directly with no
/// `go_router`/`Riverpod`/platform-channel plumbing, mirroring `welcome_screen_test.dart`'s
/// own `WelcomeScreenBody` split. The sheet's wiring -- the one-time trigger, the
/// `local_auth.isDeviceSupported()` skip of R-30-523, and the storage migration `Turn on`
/// performs -- lives in private, unexported functions this file cannot reach in isolation;
/// `keystore_test.dart`'s `retoggleProtection` group and `app_settings_test.dart`'s
/// `appLockOfferShown` group cover those primitives directly instead.
///
/// The last two groups drive the real `appRouter`: the iOS back label chain of R-33-070.2,
/// and the two ways into the `Status colours` legend, the Settings row (R-03-106) and the
/// `Agents` app bar action (R-03-112), whose cross-branch `push` must land on the `Agents`
/// branch's own `Navigator` with the bottom chrome still on screen (R-30-045).
library;

import 'dart:async' show Stream, unawaited;

import 'package:connectivity_plus/connectivity_plus.dart'
    show Connectivity, ConnectivityResult;
import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoNavigationBar, CupertinoTabBar;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart' show CustomScrollView, Offset, Widget;
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart'
    show GoRoute, RouteMatchBase, ShellRouteMatch;
import 'package:herdr_mobile/models/message.dart' show Message;
import 'package:herdr_mobile/routing.dart';
import 'package:herdr_mobile/screens/agent_list_screen.dart'
    show AgentListScreen;
import 'package:herdr_mobile/screens/settings_screen.dart' show SettingsScreen;
import 'package:herdr_mobile/screens/status_legend_screen.dart'
    show StatusLegendScreen;
import 'package:herdr_mobile/services/agent_status.dart'
    show AgentStatusService;
import 'package:herdr_mobile/services/app_settings.dart'
    show AppSettingsService;
import 'package:herdr_mobile/services/connectivity.dart'
    show ConnectivityWatcher;
import 'package:herdr_mobile/services/notifications.dart'
    show NotificationsService;
import 'package:herdr_mobile/services/plain_store.dart' show PlainStore;
import 'package:herdr_mobile/services/relay.dart' show RelayConnection;
import 'package:herdr_mobile/widgets/app_filled_button.dart';
import 'package:herdr_mobile/widgets/app_text_button.dart';
import 'package:herdr_mobile/widgets/theme/chrome_icon_action.dart'
    show ChromeIconAction;
import 'package:material_ui/material_ui.dart' show MaterialApp;
import 'package:mocktail/mocktail.dart' show Mock, when;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _MockNotificationsService extends Mock implements NotificationsService {}

class _MockConnectivity extends Mock implements Connectivity {}

/// A real `RelayConnection` that never connected, with a no-op connectivity watcher: the
/// default one listens to `connectivity_plus`'s event channel, which no test here fakes.
/// Duplicated from `routing_stack_test.dart`'s own private copy, per R-90-018/R-41-042 rung 1.
RelayConnection _idleRelay() {
  final connectivity = _MockConnectivity();
  when(() => connectivity.onConnectivityChanged)
      .thenAnswer((_) => const Stream<List<ConnectivityResult>>.empty());
  final relay = RelayConnection(
    connectivityWatcher: ConnectivityWatcher(connectivity: connectivity),
  );
  addTearDown(relay.dispose);
  return relay;
}

/// The one `Status colours` action of R-03-112 in the `Agents` app bar.
final Finder _statusColoursAction = find.byWidgetPredicate(
  (Widget widget) =>
      widget is ChromeIconAction && widget.label == 'Status colours',
);

/// The leaf route of the router's current configuration, under every shell.
GoRoute _leafRoute() {
  RouteMatchBase leaf = appRouter.routerDelegate.currentConfiguration.last;
  while (leaf is ShellRouteMatch) {
    leaf = leaf.matches.last;
  }
  return leaf.route as GoRoute;
}

/// Duplicated from `app_shell_test.dart`'s own private copy, per R-90-018/R-41-042 rung 1:
/// that copy is private to a sibling test file.
void _fakePrefs() {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
}

void main() {
  group('AppLockOfferSheet (R-30-521, R-30-522)', () {
    testWidgets('carries the exact title, body, and both actions', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: AppLockOfferSheet()));

      expect(
        find.text("Lock the app behind your phone's screen lock?"),
        findsOneWidget,
      );
      expect(
        find.text('You can turn this on or off later in Settings.'),
        findsOneWidget,
      );
      // The exact words of R-30-522, drawn as written (R-03-104).
      expect(find.text('Turn on'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
    });

    testWidgets('Turn on fires onTurnOn exactly once', (tester) async {
      var turnedOn = 0;
      await tester.pumpWidget(
        MaterialApp(home: AppLockOfferSheet(onTurnOn: () => turnedOn++)),
      );

      await tester.tap(find.byType(AppFilledButton));
      await tester.pump();

      expect(turnedOn, 1);
    });

    testWidgets('Not now never fires onTurnOn', (tester) async {
      var turnedOn = 0;
      await tester.pumpWidget(
        MaterialApp(home: AppLockOfferSheet(onTurnOn: () => turnedOn++)),
      );

      await tester.tap(find.byType(AppTextButton));
      await tester.pump();

      expect(turnedOn, 0);
    });

    testWidgets('a null onTurnOn is a deliberate no-op (R-90-016)', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: AppLockOfferSheet()));

      // Must not throw when `Turn on` fires with no callback supplied.
      await tester.tap(find.byType(AppFilledButton));
      await tester.pump();
    });
  });

  group('R-33-070.2, the iOS back button previous-page title', () {
    testWidgets(
      'pushing About from Settings shows "Settings" as the back label, not a blank one',
      (WidgetTester tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        _fakePrefs();
        await tester.pumpWidget(
          ProviderScope(child: MaterialApp.router(routerConfig: appRouter)),
        );
        await tester.pumpAndSettle();

        appRouter.go('/settings');
        await tester.pumpAndSettle();
        unawaited(appRouter.push('/settings/about'));
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byType(CupertinoNavigationBar),
            matching: find.text('About'),
          ),
          findsOneWidget,
          reason: 'About pushed correctly, as the current app bar middle',
        );
        expect(
          find.descendant(
            of: find.byType(CupertinoNavigationBar),
            matching: find.text('Settings'),
          ),
          findsOneWidget,
          reason:
              'R-33-070.2: the back label reads the previous route\'s own title '
              '(`_platformPage`\'s `title:` on `/settings`\'s `CupertinoPage`), not the '
              'blank `SizedBox.shrink()` `_BackLabel` falls back to for a plain `MaterialPage` '
              '-- deleting `_platformPage` or its `title:` argument makes this vanish.',
        );

        unawaited(appRouter.push('/settings/about/licences'));
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byType(CupertinoNavigationBar),
            matching: find.text('About'),
          ),
          findsOneWidget,
          reason: 'the chain holds: Licences\' own back label now reads About\'s title',
        );
        debugDefaultTargetPlatformOverride = null;
      },
    );
  });

  group('R-03-106, the Status colours legend', () {
    testWidgets('the Status colours row on /settings pushes /settings/status-colours, whose back label '
        'reads Settings (R-33-070.2)', (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      _fakePrefs();
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: appRouter)),
      );
      await tester.pumpAndSettle();

      appRouter.go('/settings');
      await tester.pumpAndSettle();
      // The row sits under `Theme` in `APPEARANCE`, which can be below the fold on a short
      // test surface; the lazy scroll view builds it only once it is near the viewport.
      await tester.dragUntilVisible(
        find.text('Status colours'),
        find.descendant(
          of: find.byType(SettingsScreen),
          matching: find.byType(CustomScrollView),
        ),
        const Offset(0, -200),
      );
      await tester.ensureVisible(find.text('Status colours'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Status colours'));
      // Not `pumpAndSettle`: the legend's `Working` bar pulses forever (R-32-592), so the
      // frame never settles; one second covers the platform page transition.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(StatusLegendScreen), findsOneWidget);
      // The pushed leaf under the `Settings` branch is the named route, not a stray page.
      expect(_leafRoute().name, 'status-colours');
      expect(
        find.descendant(
          of: find.byType(CupertinoNavigationBar),
          matching: find.text('Status colours'),
        ),
        findsOneWidget,
        reason: 'the legend is the current app bar middle',
      );
      expect(
        find.descendant(
          of: find.byType(CupertinoNavigationBar),
          matching: find.text('Settings'),
        ),
        findsOneWidget,
        reason:
            'R-33-070.2: the leaf route is a `CupertinoPage` through `_platformPage`, so '
            'its own bar reads the previous route\'s title back; a plain `builder:` route '
            'would show the blank `SizedBox.shrink()` `_BackLabel` falls back to.',
      );
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('R-03-112, the Status colours action on the Agents screen', () {
    testWidgets(
      'the info action on /hosts/:hostId/agents pushes the same legend onto the Agents '
      'branch, so the bottom chrome stays (R-30-045)',
      (WidgetTester tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        _fakePrefs();
        // Pre-marked shown, so the route's post-frame App Lock offer returns before its
        // `local_auth` platform channel.
        await AppSettingsService().setAppLockOfferShown(value: true);
        final RelayConnection relay = _idleRelay();
        // Land before the first pump, as `routing_stack_test.dart` does: the shared router
        // still sits on the legend the previous group pushed, whose `Working` bar pulses
        // forever, so a settle from there never returns.
        appRouter.go('/hosts/h1/agents');
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              relayConnectionProvider.overrideWithValue(relay),
              agentStatusServiceProvider.overrideWithValue(
                AgentStatusService(
                  messages: const Stream<Message>.empty(),
                  notifications: _MockNotificationsService(),
                  plainStore: PlainStore(),
                  currentHostId: () => null,
                ),
              ),
            ],
            child: MaterialApp.router(routerConfig: appRouter),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AgentListScreen), findsOneWidget);
        expect(find.byType(StatusLegendScreen), findsNothing);

        await tester.tap(_statusColoursAction);
        // Not `pumpAndSettle`: the legend's `Working` bar pulses forever (R-32-592).
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(StatusLegendScreen), findsOneWidget);
        expect(_leafRoute().name, 'status-colours');
        // The page sits on the Agents branch's own Navigator: the list is still in the
        // tree beneath it, and the three destinations of the shell are still on screen.
        expect(
          find.byType(AgentListScreen, skipOffstage: false),
          findsOneWidget,
        );
        expect(find.byType(CupertinoTabBar), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(CupertinoNavigationBar),
            matching: find.text('Status colours'),
          ),
          findsOneWidget,
          reason: 'the legend is the current app bar middle',
        );
        debugDefaultTargetPlatformOverride = null;
      },
    );
  });
}
