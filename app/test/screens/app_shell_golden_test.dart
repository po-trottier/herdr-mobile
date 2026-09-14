/// Golden tests for `AppShell` (`app/lib/screens/app_shell.dart`, `WP-12-b`): the three-
/// destination shell chrome of `docs/30-ux-spec.md` R-30-021 and R-30-045, and the native
/// control map of `docs/33-platform-chrome.md` R-33-033 to R-33-038, on both the Android
/// (`NavigationBar`) and iOS (`CupertinoTabBar`) branches, each in Selenized dark and light
/// (R-32-012). `app_shell.dart` has no `docs/31-mockups/` file of its own -- see its top doc
/// comment -- so this file's own golden names cite the `docs/33-platform-chrome.md` rule range
/// instead of a mockup path.
///
/// Router harness: a minimal three-branch `StatefulShellRoute.indexedStack`, structurally
/// identical to `app_shell_test.dart`'s own `_buildTestRouter`, with one static `Text` per
/// branch instead of a real, data-loading screen -- `app_shell_test.dart`'s top doc comment
/// records why a real per-Host screen is not used here either. This file cannot import that
/// helper directly, because it is a private top-level function of a sibling test file, so the
/// same small router is rebuilt here rather than widened into a shared, exported test helper for
/// a single six-line function two files use.
///
/// Fonts, the app theme and the 375 x 667 reference size come from `golden_support.dart`
/// (`loadAppFonts`, `goldenApp`, `goldenReferenceSize`); see its doc comment for why.
/// `devicePixelRatio` stays fixed at 1.0. The router runs under `goldenApp`'s `home` through
/// `Router.withConfig`, because `goldenApp` owns the one `MaterialApp` this file needs.
///
/// State axis: the destination selected and the unread badge (R-31-07-05, R-30-508). Each
/// platform gets `Agents` selected with no unread row, and `Notifications` selected with two
/// unread rows so the count badge draws on both the `NavigationBar` and the `CupertinoTabBar`:
/// eight goldens total. Since 2026-09-09 (R-32-518, per R-03-059) that badge is the platform's
/// own: the filled `color.status.error` circle with the count in `color.fg.on_accent` at the
/// bell's top-end corner, and the bell keeps the bar's ink. No create control appears here since
/// 2026-09-04 (R-31-17-01: the `Agents` screen alone draws one).
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart' show Router;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart'
    show GoRoute, GoRouter, RouteBase, StatefulShellBranch, StatefulShellRoute;
import 'package:herdr_mobile/models/messages/agent_status_kind.dart'
    show AgentStatusKind;
import 'package:herdr_mobile/screens/app_shell.dart' show AppShell;
import 'package:herdr_mobile/services/agent_status.dart'
    show AttentionItem, NotificationItem;
import 'package:herdr_mobile/services/relay.dart' show RelayConnectionState;
import 'package:material_ui/material_ui.dart' show Brightness, Material, Text;

import 'golden_support.dart';

/// Structurally matches `routing.dart`'s real `StatefulShellRoute.indexedStack`: three
/// `StatefulShellBranch`es, one `AppShell`. See this file's own top doc comment for why a static
/// `Text` per branch, not a real screen.
GoRouter _buildTestRouter({required int unread}) => GoRouter(
  initialLocation: '/a',
  routes: <RouteBase>[
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) => AppShell(
        navigationShell: navigationShell,
        connectionState: const Stream<RelayConnectionState>.empty(),
        isConnected: () => false,
        connectedHostName: () => null,
        onOpenDiagnostics: () => null,
        notifications: const Stream<List<NotificationItem>>.empty(),
        currentNotifications: () => List<NotificationItem>.generate(
          unread,
          (int i) => NotificationItem(
            item: AttentionItem(
              hostId: 'h1',
              paneId: 'p$i',
              workspaceId: 'w1',
              tabId: 't1',
              agentKind: 'claude',
              tabTitle: 'impl',
              paneTitle: 'main.py',
              status: AgentStatusKind.blocked,
              at: null,
            ),
            seen: false,
          ),
        ),
      ),
      branches: <StatefulShellBranch>[
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/a',
              builder: (_, _) => const Material(child: Text('Agents body')),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/b',
              builder: (_, _) =>
                  const Material(child: Text('Notifications body')),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/c',
              builder: (_, _) => const Material(child: Text('Settings body')),
            ),
          ],
        ),
      ],
    ),
  ],
);

class _Case {
  const _Case(this.name, this.platform, {this.selectNotifications = false});
  final String name;
  final TargetPlatform platform;

  /// `true` taps the `Notifications` destination before the golden is taken, with two unread
  /// rows so the count badge shows (R-31-07-05).
  final bool selectNotifications;
}

const _cases = <_Case>[
  _Case('android_agents', TargetPlatform.android),
  _Case(
    'android_notifications',
    TargetPlatform.android,
    selectNotifications: true,
  ),
  _Case('ios_agents', TargetPlatform.iOS),
  _Case('ios_notifications', TargetPlatform.iOS, selectNotifications: true),
];

const _themes = <(String, Brightness)>[
  ('dark', Brightness.dark),
  ('light', Brightness.light),
];

void main() {
  setUpAll(loadAppFonts);

  for (final testCase in _cases) {
    for (final (themeName, brightness) in _themes) {
      testWidgets(
        '${testCase.name} ($themeName) matches docs/33-platform-chrome.md R-33-033 to R-33-038',
        (tester) async {
          debugDefaultTargetPlatformOverride = testCase.platform;

          tester.view.physicalSize = goldenReferenceSize;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            goldenApp(
              brightness: brightness,
              child: Router.withConfig(
                config: _buildTestRouter(
                  unread: testCase.selectNotifications ? 2 : 0,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          if (testCase.selectNotifications) {
            await tester.tap(find.text('NOTIFICATIONS').first);
            await tester.pumpAndSettle();
            expect(find.text('2'), findsOneWidget);
          }

          // Structural proof alongside the visual one: the three destinations and the
          // persistent connection strip's placeholder text are really present, not just
          // painted to look right by coincidence.
          expect(find.text('AGENTS'), findsWidgets);
          expect(find.text('NOTIFICATIONS'), findsWidgets);
          expect(find.text('SETTINGS'), findsWidgets);
          expect(find.text('Not connected to a computer.'), findsOneWidget);

          await expectLater(
            find.byType(AppShell),
            matchesGoldenFile(
              'goldens/app_shell_${testCase.name}_$themeName.png',
            ),
          );
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }
  }
}
