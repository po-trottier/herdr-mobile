/// Native notification controls on both platforms and brightnesses.
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart' show Brightness, Navigator;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart' show Ok;
import 'package:herdr_mobile/models/messages/agent_status_kind.dart';
import 'package:herdr_mobile/screens/notifications_screen.dart';
import 'package:herdr_mobile/services/agent_status.dart';
import 'package:material_symbols_icons/symbols.dart' show Symbols;

import 'golden_support.dart';
import 'row_actions_support.dart';

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

void main() {
  setUpAll(loadAppFonts);
  for (final platform in <TargetPlatform>[
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    for (final brightness in Brightness.values) {
      for (final state in <String>[
        'default',
        'all_read',
        'empty',
        'pane_closed',
        'row_actions',
        'actions',
      ]) {
        final suffix =
            '${platform == TargetPlatform.iOS ? "ios_" : ""}${brightness.name}';
        testWidgets('notifications $state $suffix', (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          tester.view.physicalSize = goldenReferenceSize;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final items = switch (state) {
            'all_read' => _allReadLog(),
            'empty' => <NotificationItem>[],
            'pane_closed' => _defaultLog().take(1).toList(),
            _ => _defaultLog(),
          };
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
                closedPaneId: state == 'pane_closed' ? 'w9:p9' : null,
                now: () => DateTime.utc(2026, 9, 4, 10),
              ),
            ),
          );
          await tester.pump();
          if (state == 'empty') {
            await precacheBrandMark(tester, find.byType(NotificationsScreen));
          } else if (state == 'row_actions') {
            await openRowActions(tester, find.text('omp is blocked'));
          } else if (state == 'actions') {
            await tester.tap(find.byIcon(Symbols.more_vert_rounded).first);
          }
          await tester.pumpAndSettle();
          await expectLater(
            state == 'actions' || state == 'row_actions'
                ? find.byType(Navigator).first
                : find.byType(NotificationsScreen),
            matchesGoldenFile(
              'goldens/notifications_screen_${state}_$suffix.png',
            ),
          );
          debugDefaultTargetPlatformOverride = null;
        });
      }
    }
  }
}
