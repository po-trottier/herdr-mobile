/// Proves `AppShell` (`WP-12-b`) renders the three-destination shell of
/// `docs/30-ux-spec.md` R-30-021 (`Agents`, `Notifications`, `Settings`, decided 2026-09-04),
/// switches branches on tap, and carries the unread count badge on `Notifications`
/// (R-31-07-05, R-30-508).
///
/// Most of this file drives `AppShell` behind a minimal, local `GoRouter` with trivial
/// per-branch content, rather than the app's real `appRouter`: the real per-Host screen
/// `appRouter` wires (`AgentListScreen`) calls `RelayConnection.send`
/// unconditionally on mount to load its initial data, and that call throws by design
/// while disconnected ("a caller bug, not a recoverable runtime condition", `relay.dart`'s
/// own doc comment) -- correct for the real app, where a per-Host route is never reached
/// without an already-connected computer, but not a state this file's own concern (the
/// shell chrome, not per-Host data loading) should have to fake a whole Noise handshake to
/// avoid. One test still drives the real `appRouter`, to prove the cold-start redirect
/// wiring itself (`routing.dart`'s `/notifications` branch default) reaches the real
/// `HostListScreen` rather than a placeholder; it reaches `/notifications` directly, never
/// through a per-Host route, so it never touches that crash either.
library;

import 'dart:async' show StreamController;
import 'dart:ui' show Rect, Size;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoTabBar;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart'
    show GoRoute, GoRouter, RouteBase, StatefulShellBranch, StatefulShellRoute;
import 'package:herdr_mobile/app.dart' show appThemeFrom;
import 'package:herdr_mobile/models/messages/agent_status_kind.dart'
    show AgentStatusKind;
import 'package:herdr_mobile/routing.dart';
import 'package:herdr_mobile/screens/app_shell.dart' show AppShell;
import 'package:herdr_mobile/screens/host_list_screen.dart' show HostListScreen;
import 'package:herdr_mobile/services/agent_status.dart'
    show AttentionItem, NotificationItem;
import 'package:herdr_mobile/services/relay.dart';
import 'package:herdr_mobile/widgets/app_strip.dart' show AppStrip;
import 'package:herdr_mobile/widgets/status_bar.dart' show BarState, StatusBar;
import 'package:herdr_mobile/widgets/theme/app_color.dart' show AppColor;
import 'package:herdr_mobile/widgets/theme/app_size.dart' show AppSize;
import 'package:herdr_mobile/widgets/theme/app_type.dart' show AppType;
import 'package:herdr_mobile/widgets/theme/chrome_scheme.dart'
    show ChromeScheme;
import 'package:material_ui/material_ui.dart'
    show
        Badge,
        Brightness,
        BuildContext,
        Colors,
        FloatingActionButton,
        Icon,
        MaterialApp,
        NavigationBar,
        NavigationBarTheme,
        NavigationBarThemeData,
        Widget,
        Text;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// The shell's connection and current-Host notification inputs, controlled per test.
/// The shell reads the current values at build and follows the streams after that.
class _Link {
  _Link({
    this.connected = false,
    this.hostName,
    this.hostId,
    this.currentNotifications = const <NotificationItem>[],
  });
  bool connected;
  String? hostName;
  String? hostId;
  List<NotificationItem> currentNotifications;
  final StreamController<RelayConnectionState> states =
      StreamController<RelayConnectionState>.broadcast();
  final StreamController<List<NotificationItem>> notifications =
      StreamController<List<NotificationItem>>.broadcast();
  int diagnosticsOpened = 0;

  Future<void> dispose() async {
    await states.close();
    await notifications.close();
  }
}

NotificationItem _item(String paneId, {bool seen = false}) => NotificationItem(
  item: AttentionItem(
    hostId: 'h1',
    paneId: paneId,
    workspaceId: 'w1',
    tabId: 'w1:t1',
    agentKind: 'claude',
    tabTitle: 'impl',
    paneTitle: 'main.py',
    status: AgentStatusKind.blocked,
    at: null,
  ),
  seen: seen,
);

/// This router matches the app's three-branch shell without a relay connection.
/// Most tests use static content. The sheet test supplies the real notifications screen.
GoRouter _buildTestRouter([_Link? link, Widget? notificationsBody]) {
  final _Link l = link ?? _Link();
  return GoRouter(
    initialLocation: '/a',
    routes: <RouteBase>[
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(
          navigationShell: navigationShell,
          connectionState: l.states.stream,
          isConnected: () => l.connected,
          connectedHostName: () => l.hostName,
          onOpenDiagnostics: () =>
              l.hostId == null ? null : () => l.diagnosticsOpened++,
          notifications: l.notifications.stream,
          currentNotifications: () => l.currentNotifications,
        ),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(path: '/a', builder: (_, _) => const Text('Agents body')),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/b',
                builder: (_, _) =>
                    notificationsBody ?? const Text('Notifications body'),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/c',
                builder: (_, _) => const Text('Settings body'),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

void _fakePrefs() {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
}

void main() {
  testWidgets('renders all three destinations and switches between them', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp.router(routerConfig: _buildTestRouter()),
    );
    await tester.pumpAndSettle();

    expect(find.text('AGENTS'), findsWidgets);
    expect(find.text('NOTIFICATIONS'), findsWidgets);
    expect(find.text('SETTINGS'), findsWidgets);
    expect(find.text('Agents body'), findsOneWidget);
    expect(find.text('Notifications body'), findsNothing);
    expect(find.text('Settings body'), findsNothing);

    await tester.tap(find.text('NOTIFICATIONS').first);
    await tester.pumpAndSettle();

    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    expect(find.text('Notifications body'), findsOneWidget);

    await tester.tap(find.text('SETTINGS').first);
    await tester.pumpAndSettle();

    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
    expect(find.text('Settings body'), findsOneWidget);

    await tester.tap(find.text('AGENTS').first);
    await tester.pumpAndSettle();

    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
    expect(find.text('Agents body'), findsOneWidget);
  });

  testWidgets('iOS: renders a CupertinoTabBar with the three destinations, not a NavigationBar, and '
      'switches between them, per R-33-035', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(
      MaterialApp.router(routerConfig: _buildTestRouter()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoTabBar), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Agents body'), findsOneWidget);
    expect(find.text('Notifications body'), findsNothing);

    expect(
      tester.widget<CupertinoTabBar>(find.byType(CupertinoTabBar)).currentIndex,
      0,
    );

    await tester.tap(find.text('NOTIFICATIONS').first);
    await tester.pumpAndSettle();

    expect(
      tester.widget<CupertinoTabBar>(find.byType(CupertinoTabBar)).currentIndex,
      1,
    );
    expect(find.text('Notifications body'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  for (final platform in <TargetPlatform>[
    TargetPlatform.iOS,
    TargetPlatform.android,
  ]) {
    testWidgets(
      '$platform: the tab bar reaches the screen bottom through the home-indicator inset; '
      'no page-coloured band below it (2026-09-16)',
      (WidgetTester tester) async {
        debugDefaultTargetPlatformOverride = platform;
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        tester.view.padding = const FakeViewPadding(bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(bottom: 34);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp.router(routerConfig: _buildTestRouter()),
        );
        await tester.pumpAndSettle();

        final Finder bar = platform == TargetPlatform.iOS
            ? find.byType(CupertinoTabBar)
            : find.byType(NavigationBar);
        final Rect rect = tester.getRect(bar);
        expect(rect.bottom, 844, reason: 'the bar owns the bottom inset');
        // The bar is taller than its nominal height by exactly the inset.
        expect(rect.height, AppSize.bottomNav + 34);
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets(
    'draws no FloatingActionButton on any destination -- the create control is the '
    'Agents screen\'s own, per R-33-034 and R-31-17-01 (2026-09-04)',
    (WidgetTester tester) async {
      for (final platform in <TargetPlatform>[
        TargetPlatform.android,
        TargetPlatform.iOS,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        await tester.pumpWidget(
          MaterialApp.router(routerConfig: _buildTestRouter()),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('NOTIFICATIONS').first);
        await tester.pumpAndSettle();

        expect(
          find.byType(FloatingActionButton),
          findsNothing,
          reason: '$platform',
        );
      }
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('Android: the NavigationBar has no selection pill and a bg.base surface, per '
      'docs/32 section 7.22', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp.router(
        theme: appThemeFrom(ChromeScheme.fixed(Brightness.light)),
        routerConfig: _buildTestRouter(),
      ),
    );
    await tester.pumpAndSettle();

    final BuildContext barContext = tester.element(find.byType(NavigationBar));
    final NavigationBarThemeData barTheme = NavigationBarTheme.of(barContext);
    expect(barTheme.indicatorColor, Colors.transparent);
    expect(barTheme.backgroundColor, AppColor.of(barContext).bgBase);
  });

  group('unread badge on Notifications (R-31-07-05, R-30-508)', () {
    for (final platform in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.iOS,
    ]) {
      testWidgets(
        '$platform: counts only unread rows at build and on emissions, and hides at zero',
        (WidgetTester tester) async {
          debugDefaultTargetPlatformOverride = platform;
          try {
            final link = _Link(
              currentNotifications: <NotificationItem>[
                _item('p1'),
                _item('p2'),
                _item('p3', seen: true),
              ],
            );
            addTearDown(link.dispose);
            await tester.pumpWidget(
              MaterialApp.router(routerConfig: _buildTestRouter(link)),
            );
            await tester.pumpAndSettle();

            expect(find.byType(Badge), findsOneWidget);
            expect(find.text('2'), findsOneWidget);
            // R-32-518 (2026-09-09, R-03-059): the platform badge carries the hue; the bell
            // keeps the bar's own ink and the Badge keeps its theme defaults.
            final Badge badge = tester.widget<Badge>(find.byType(Badge));
            expect((badge.child! as Icon).color, isNull);
            expect(badge.backgroundColor, isNull);
            expect(badge.textColor, isNull);
            expect(badge.textStyle, isNull);

            link.notifications.add(<NotificationItem>[
              _item('p1'),
              _item('p2', seen: true),
              _item('p3', seen: true),
            ]);
            await tester.pumpAndSettle();
            expect(find.text('1'), findsOneWidget);
            expect(find.text('2'), findsNothing);

            link.notifications.add(<NotificationItem>[_item('p1', seen: true)]);
            await tester.pumpAndSettle();
            expect(find.byType(Badge), findsNothing);
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        },
      );
    }

    testWidgets('the count is exact and uncapped (R-30-508)', (
      WidgetTester tester,
    ) async {
      final link = _Link(
        currentNotifications: List<NotificationItem>.generate(
          120,
          (int i) => _item('p$i'),
        ),
      );
      addTearDown(link.dispose);
      await tester.pumpWidget(
        MaterialApp.router(routerConfig: _buildTestRouter(link)),
      );
      await tester.pumpAndSettle();

      expect(find.text('120'), findsOneWidget);
      expect(find.text('99+'), findsNothing);
    });
  });

  testWidgets(
    'the Notifications destination, with no computer connected this session, routes to the '
    'real host chooser rather than a placeholder',
    (WidgetTester tester) async {
      _fakePrefs();
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: appRouter)),
      );
      await tester.pumpAndSettle();

      // No `RelayConnection` has ever connected in this test, so `/notifications`'s own
      // redirect (see `routing.dart`'s `appRouter` doc comment) sends the app to `/hosts`,
      // the real host chooser, per R-30-946 -- not a fake placeholder, and not a dead
      // end: `HostListScreen`'s own root variant (`05-host-list.md` R-31-05-19) is the
      // legitimate landing spot here.
      appRouter.go('/notifications');
      await tester.pumpAndSettle();

      expect(find.byType(HostListScreen), findsOneWidget);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'renders the three destinations under $brightness with no crash',
      (WidgetTester tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

        await tester.pumpWidget(
          MaterialApp.router(routerConfig: _buildTestRouter()),
        );
        await tester.pumpAndSettle();

        expect(find.text('AGENTS'), findsWidgets);
        expect(find.text('NOTIFICATIONS'), findsWidgets);
        expect(find.text('SETTINGS'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('R-30-022, R-30-045: /hosts/:hostId/panes/:paneId/actions pushes over '
      'the terminal on the root Navigator, without bottom navigation', () {
    final match = appRouter.configuration.findMatch(
      Uri.parse('/hosts/h1/panes/p1/actions'),
    );
    expect(match.isError, isFalse);
    expect(match.matches.map((m) => (m.route as GoRoute).name), <String>[
      'terminal',
      'pane-actions',
    ], reason: 'the actions screen must have the terminal beneath it');
    expect(
      match.matches.map((m) => (m.route as GoRoute).parentNavigatorKey),
      everyElement(same(rootNavigatorKey)),
      reason:
          'both screens cover AppShell on the root navigator, so neither '
          'shows bottom navigation (R-30-045, amended 2026-09-09)',
    );
    expect(match.pathParameters, <String, String>{
      'hostId': 'h1',
      'paneId': 'p1',
    });
    expect(
      appRouter.configuration.findMatch(Uri.parse('/hosts/h1/actions')).isError,
      isTrue,
      reason: 'R-03-055 retired the computer-scoped actions route',
    );
  });

  group('connection strip (R-33-036, R-32-561, R-30-806)', () {
    testWidgets(
      'reads the live snapshot at build, so a link made before the shell exists is shown',
      (WidgetTester tester) async {
        final link = _Link(
          connected: true,
          hostName: 'patrick-desk',
          hostId: 'h1',
        );
        addTearDown(link.dispose);
        await tester.pumpWidget(
          MaterialApp.router(routerConfig: _buildTestRouter(link)),
        );
        await tester.pumpAndSettle();
        expect(find.text('Connected to patrick-desk.'), findsOneWidget);
        expect(find.text('Not connected to a computer yet.'), findsNothing);
      },
    );

    testWidgets('follows every later state and names the computer', (
      WidgetTester tester,
    ) async {
      final link = _Link(hostName: 'patrick-desk', hostId: 'h1');
      addTearDown(link.dispose);
      await tester.pumpWidget(
        MaterialApp.router(routerConfig: _buildTestRouter(link)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Not connected to patrick-desk.'), findsOneWidget);

      final cases = <(RelayConnectionState, String)>[
        (
          const RelayConnecting(ConnectionStage.openingSocket),
          'Connecting to patrick-desk...',
        ),
        (const RelayConnected(), 'Connected to patrick-desk.'),
        (
          const RelayReconnecting(Duration(seconds: 2)),
          'Connecting to patrick-desk...',
        ),
        (
          const RelayRegistrationError(
            RelayRegistrationErrorCode.handleUnknown,
            'x',
          ),
          'The computer is not connected to the relay. Open its Relay pane.',
        ),
        (const RelayRevoked(), 'This computer removed this phone. Pair again.'),
        (const RelayDisconnected(), 'Not connected to patrick-desk.'),
      ];
      for (final (state, text) in cases) {
        link.states.add(state);
        await tester.pumpAndSettle();
        expect(find.text(text), findsOneWidget, reason: '$state');
      }
    });

    testWidgets(
      'a failure strip is tappable and opens diagnostics; a connected one is not',
      (WidgetTester tester) async {
        final link = _Link(hostName: 'patrick-desk', hostId: 'h1');
        addTearDown(link.dispose);
        await tester.pumpWidget(
          MaterialApp.router(routerConfig: _buildTestRouter(link)),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Not connected to patrick-desk.'));
        await tester.pump();
        expect(link.diagnosticsOpened, 1);

        link.states.add(const RelayConnected());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Connected to patrick-desk.'));
        await tester.pump();
        expect(link.diagnosticsOpened, 1, reason: 'a connected strip is plain');
      },
    );

    testWidgets('with no computer known the strip is plain text', (
      WidgetTester tester,
    ) async {
      final link = _Link();
      addTearDown(link.dispose);
      await tester.pumpWidget(
        MaterialApp.router(routerConfig: _buildTestRouter(link)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Not connected to a computer.'), findsOneWidget);
      await tester.tap(find.text('Not connected to a computer.'));
      await tester.pump();
      expect(link.diagnosticsOpened, 0);
    });

    testWidgets('the strip carries the link state bar and a failure reads in primary ink (R-03-100, '
        '2026-09-10)', (WidgetTester tester) async {
      final link = _Link(hostName: 'patrick-desk', hostId: 'h1');
      addTearDown(link.dispose);
      await tester.pumpWidget(
        MaterialApp.router(routerConfig: _buildTestRouter(link)),
      );
      await tester.pumpAndSettle();
      const AppColor color = AppColor.light;

      StatusBar bar() => tester.widget<StatusBar>(
        find.descendant(
          of: find.byType(AppStrip),
          matching: find.byType(StatusBar),
        ),
      );
      Text label(String text) => tester.widget<Text>(find.text(text));

      expect(bar().state, BarState.error);
      final Text failed = label('Not connected to patrick-desk.');
      expect(failed.style!.color, color.fgPrimary);
      expect(failed.style!.fontWeight, AppType.bodyStrong.fontWeight);
      final strip = tester.getRect(find.byType(AppStrip));
      final barRect = tester.getRect(find.byType(StatusBar));
      expect(barRect.left, strip.left);
      expect(barRect.top, strip.top);
      expect(barRect.bottom, strip.bottom);

      link.states.add(const RelayConnecting(ConnectionStage.openingSocket));
      await tester.pumpAndSettle();
      expect(bar().state, BarState.warning);

      link.states.add(const RelayConnected());
      await tester.pumpAndSettle();
      expect(bar().state, BarState.ok);
      final Text connected = label('Connected to patrick-desk.');
      expect(connected.style!.color, color.fgSecondary);
      expect(connected.style!.fontWeight, isNot(AppType.bodyStrong.fontWeight));
    });
  });
}
