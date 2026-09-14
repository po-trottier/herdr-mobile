/// Golden tests for `NotificationsScreen` (`app/lib/screens/notifications_screen.dart`), one per
/// named row of `docs/31-mockups/07-notifications.md`'s `## States` table (R-90-011): `Default`,
/// `All read`, `Empty` and `Pane closed`. Each renders in both Selenized dark and light
/// (R-32-012), on Android; `Default` renders on iOS too (2026-09-09, R-03-059), because the
/// bulk controls and the row actions control are the platform's own buttons and differ there.
/// The rest of the iOS chrome differs only by the navigation bar
/// `notifications_screen_test.dart` already proves.
///
/// The screen is fed its rows directly through `currentNotifications` and a silent stream, the
/// way `lock_screen_golden_test.dart` renders a body with fixed inputs: the log is in memory and
/// this screen loads nothing. The clock is pinned so the ages never drift; the screen's own age
/// tick redraws the same pinned time.
///
/// Fonts, the app theme and the 375 x 667 reference size come from `golden_support.dart`
/// (`loadAppFonts`, `goldenApp`, `goldenReferenceSize`); see its doc comment for why.
/// `devicePixelRatio` stays fixed at 1.0.
library;

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoButton, CupertinoNavigationBar;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart' show Ok;
import 'package:herdr_mobile/models/messages/agent_status_kind.dart';
import 'package:herdr_mobile/screens/notifications_screen.dart';
import 'package:herdr_mobile/services/agent_status.dart';
import 'package:herdr_mobile/widgets/app_ground.dart' show EmptyMark;
import 'package:herdr_mobile/widgets/ground_grid.dart' show GroundGrid;
import 'package:material_symbols_icons/symbols.dart' show Symbols;

import 'golden_support.dart';

NotificationItem _entry({
  required String paneId,
  required String spaceName,
  required String tabTitle,
  required String paneTitle,
  required String agentKind,
  required AgentStatusKind status,
  required String? at,
  bool seen = false,
}) => NotificationItem(
  seen: seen,
  item: AttentionItem(
    hostId: 'host-1',
    paneId: paneId,
    workspaceId: 'w1',
    tabId: 'w1:t1',
    spaceName: spaceName,
    agentKind: agentKind,
    tabTitle: tabTitle,
    paneTitle: paneTitle,
    status: status,
    at: at,
  ),
);

/// The mockup's first wireframe, in the service's own order (R-31-07-02: newest first, no time
/// last): two unread rows and one read row, so both groups draw.
List<NotificationItem> _defaultLog() => <NotificationItem>[
  _entry(
    paneId: 'w1:p1',
    spaceName: 'lightspeed-kit',
    tabTitle: 'impl',
    paneTitle: 'main.py',
    agentKind: 'omp',
    status: AgentStatusKind.blocked,
    at: '2026-09-04T09:56:00Z',
  ),
  _entry(
    paneId: 'w2:p4',
    spaceName: 'scratch',
    tabTitle: 'notes',
    paneTitle: 'pane 4',
    agentKind: 'codex',
    status: AgentStatusKind.done,
    at: '2026-09-04T09:48:00Z',
    seen: true,
  ),
  _entry(
    paneId: 'w3:p2',
    spaceName: 'herdr-mobile',
    tabTitle: 'tests',
    paneTitle: 'pytest',
    agentKind: 'claude',
    status: AgentStatusKind.done,
    at: null,
  ),
];

/// The mockup's second wireframe: every row read, so `NEW` carries its one line.
List<NotificationItem> _allReadLog() => <NotificationItem>[
  for (final NotificationItem entry in _defaultLog())
    NotificationItem(item: entry.item, seen: true),
];

const _themes = <(String, Brightness)>[
  ('dark', Brightness.dark),
  ('light', Brightness.light),
];

void main() {
  setUpAll(loadAppFonts);

  Future<void> pumpScreen(
    WidgetTester tester,
    Brightness brightness, {
    required List<NotificationItem> items,
    String? closedPaneId,
  }) async {
    tester.view.physicalSize = goldenReferenceSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      goldenApp(
        brightness: brightness,
        child: NotificationsScreen(
          hostName: 'patrick-desk',
          notifications: const Stream<List<NotificationItem>>.empty(),
          currentNotifications: items,
          onMarkSeen: (_) async => const Ok(null),
          onMarkAllSeen: () async => const Ok(null),
          onRemove: (_) async => const Ok(null),
          onRemoveAll: () async => const Ok(null),
          onOpenPane: (_) {},
          closedPaneId: closedPaneId,
          now: () => DateTime.utc(2026, 9, 4, 10),
        ),
      ),
    );
    await tester.pump();
  }

  for (final (themeName, brightness) in _themes) {
    testWidgets(
      'default ($themeName) matches docs/31-mockups/07-notifications.md',
      (tester) async {
        await pumpScreen(tester, brightness, items: _defaultLog());

        expect(find.text('Notifications'), findsOneWidget);
        expect(find.text('Mark all read'), findsOneWidget);
        expect(find.text('Remove all'), findsOneWidget);
        expect(find.text(newHeaderLabel), findsOneWidget);
        expect(find.text(earlierHeaderLabel), findsOneWidget);
        expect(find.text('omp is blocked'), findsOneWidget);
        expect(find.text('claude is done'), findsOneWidget);
        expect(find.text('codex is done'), findsOneWidget);
        expect(find.text('4m 00s'), findsOneWidget);
        expect(find.text('12m 00s'), findsOneWidget);
        // R-03-107 (amended 2026-09-09): a list with rows paints plain `color.bg.base`, no
        // grid.
        expect(find.byType(GroundGrid), findsNothing);

        await expectLater(
          find.byType(NotificationsScreen),
          matchesGoldenFile(
            'goldens/notifications_screen_default_$themeName.png',
          ),
        );
      },
    );

    testWidgets(
      'all read ($themeName) matches docs/31-mockups/07-notifications.md',
      (tester) async {
        await pumpScreen(tester, brightness, items: _allReadLog());

        expect(find.text(noNewSentence), findsOneWidget);
        expect(find.text(earlierHeaderLabel), findsOneWidget);
        expect(find.text('omp is blocked'), findsOneWidget);

        await expectLater(
          find.byType(NotificationsScreen),
          matchesGoldenFile(
            'goldens/notifications_screen_all_read_$themeName.png',
          ),
        );
      },
    );

    testWidgets(
      'empty ($themeName) matches docs/31-mockups/07-notifications.md',
      (tester) async {
        await pumpScreen(tester, brightness, items: const <NotificationItem>[]);
        await precacheBrandMark(tester, find.byType(NotificationsScreen));
        await tester.pumpAndSettle();

        // R-03-107 (amended 2026-09-09): the empty block sits on the ground grid inside the
        // mark.
        expect(
          find.descendant(
            of: find.descendant(
              of: find.byType(GroundGrid),
              matching: find.byType(EmptyMark),
            ),
            matching: find.text('No notifications.'),
          ),
          findsOneWidget,
        );
        expect(
          find.text('Agent status changes on patrick-desk appear here.'),
          findsOneWidget,
        );

        await expectLater(
          find.byType(NotificationsScreen),
          matchesGoldenFile(
            'goldens/notifications_screen_empty_$themeName.png',
          ),
        );
      },
    );

    testWidgets(
      'pane closed ($themeName) matches docs/31-mockups/07-notifications.md',
      (tester) async {
        await pumpScreen(
          tester,
          brightness,
          items: _defaultLog().take(1).toList(),
          closedPaneId: 'w9:p9',
        );

        expect(find.text(paneClosedSentence), findsOneWidget);

        await expectLater(
          find.byType(NotificationsScreen),
          matchesGoldenFile(
            'goldens/notifications_screen_pane_closed_$themeName.png',
          ),
        );
      },
    );
  }

  // The `Default` state on iOS (added 2026-09-09, R-03-059): the two bulk controls and the row
  // actions control are Cupertino buttons there, so the platform form gets its own golden.
  for (final (themeName, brightness) in _themes) {
    testWidgets(
      'default (ios_$themeName) matches docs/31-mockups/07-notifications.md',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        // A failed expect below must not leak the override into the next test; the binding
        // checks the variable before the tear-downs run, so the body resets it too.
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        await pumpScreen(tester, brightness, items: _defaultLog());

        expect(find.byType(CupertinoNavigationBar), findsOneWidget);
        expect(
          find.widgetWithText(CupertinoButton, 'Mark all read'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(CupertinoButton, 'Remove all'),
          findsOneWidget,
        );
        expect(
          find.widgetWithIcon(CupertinoButton, Symbols.more_vert_rounded),
          findsNWidgets(3),
        );

        await expectLater(
          find.byType(NotificationsScreen),
          matchesGoldenFile(
            'goldens/notifications_screen_default_ios_$themeName.png',
          ),
        );
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
}
