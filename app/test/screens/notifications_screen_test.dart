/// Smoke-tests `NotificationsScreen` against `docs/31-mockups/07-notifications.md` (amended
/// 2026-09-09): the worded bulk controls and their disabled states (R-31-07-03, R-31-07-04,
/// R-32-502), the `NEW`/`EARLIER` groups and the badge predicate they share (R-31-07-05,
/// R-31-07-11), the row anatomy and its one unread signal (R-31-07-03, R-03-058), a row tap
/// opening the pane (R-31-07-05), the long-press actions and their semantics (R-31-07-09), the confirmed
/// `Remove all` (docs/32 section 7.17), the live insert and the ticking age (R-31-07-12,
/// R-03-056), the `Empty` state, and the pane-closed strip (R-31-07-07).
library;

import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:cupertino_ui/cupertino_ui.dart'
    show
        CupertinoButton,
        CupertinoContextMenuAction,
        CupertinoListTile,
        CupertinoMenuItem,
        CupertinoNavigationBar;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/semantics.dart'
    show CustomSemanticsAction, SemanticsNode;
import 'package:flutter/widgets.dart'
    show CustomScrollView, SliverPadding, Text, TextStyle;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart' show Err, Ok, Result;
import 'package:herdr_mobile/models/messages/agent_status_kind.dart';
import 'package:herdr_mobile/screens/notifications_screen.dart';
import 'package:herdr_mobile/services/agent_status.dart';
import 'package:herdr_mobile/widgets/app_ground.dart' show EmptyMark;
import 'package:herdr_mobile/widgets/eyebrow.dart';
import 'package:herdr_mobile/widgets/ground_grid.dart' show GroundGrid;
import 'package:herdr_mobile/widgets/theme/app_color.dart' show AppColor;
import 'package:herdr_mobile/widgets/theme/app_space.dart' show AppSpace;
import 'package:herdr_mobile/widgets/theme/app_type.dart' show AppType;
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart'
    show
        AlertDialog,
        IconButton,
        ListTile,
        MaterialApp,
        MenuItemButton,
        TextButton;

import 'row_actions_support.dart';

final DateTime _fixedNow = DateTime.utc(2026, 9, 4, 10, 4);

NotificationItem _entry(
  String paneId, {
  bool seen = false,
  AgentStatusKind status = AgentStatusKind.blocked,
  String? at = '2026-09-04T10:00:00Z',
  String spaceName = 'lightspeed-kit',
  String agentKind = 'claude',
}) => NotificationItem(
  seen: seen,
  item: AttentionItem(
    hostId: 'host-1',
    paneId: paneId,
    workspaceId: 'w1',
    tabId: 'w1:t1',
    spaceName: spaceName,
    agentKind: agentKind,
    tabTitle: 'impl',
    paneTitle: 'main.py',
    status: status,
    at: at,
  ),
);

class _Calls {
  final List<String> markSeen = <String>[];
  final List<String> remove = <String>[];
  final List<String> open = <String>[];
  int markAll = 0;
  int removeAll = 0;

  /// What every action resolves to; a test sets an `Err` to drive the inline strip.
  Result<void> result = const Ok(null);
}

Future<(_Calls, StreamController<List<NotificationItem>>)> _pump(
  WidgetTester tester, {
  List<NotificationItem> items = const <NotificationItem>[],
  String? closedPaneId,
  DateTime Function()? now,
  StreamController<List<NotificationItem>>? controller,
}) async {
  final calls = _Calls();
  final StreamController<List<NotificationItem>> stream =
      controller ?? StreamController<List<NotificationItem>>.broadcast();
  if (controller == null) addTearDown(stream.close);
  await tester.pumpWidget(
    MaterialApp(
      home: NotificationsScreen(
        hostName: 'patrick-desk',
        notifications: stream.stream,
        currentNotifications: items,
        onMarkSeen: (String id) async {
          calls.markSeen.add(id);
          return calls.result;
        },
        onMarkAllSeen: () async {
          calls.markAll++;
          return calls.result;
        },
        onRemove: (String id) async {
          calls.remove.add(id);
          return calls.result;
        },
        onRemoveAll: () async {
          calls.removeAll++;
          return calls.result;
        },
        onOpenPane: calls.open.add,
        closedPaneId: closedPaneId,
        now: now ?? () => _fixedNow,
      ),
    ),
  );
  await tester.pump();
  return (calls, stream);
}

/// The rows drawn under `NEW`: every row whose top sits between the two headers, or under `NEW`
/// alone when `EARLIER` is absent.
int _rowsUnderNew(WidgetTester tester) {
  final double newTop = tester.getTopLeft(find.text(newHeaderLabel)).dy;
  final Finder earlier = find.text(earlierHeaderLabel);
  final double floor = earlier.evaluate().isEmpty
      ? double.infinity
      : tester.getTopLeft(earlier).dy;
  return find.bySemanticsLabel(RegExp(r'^\w+ is \w+, ')).evaluate().where((
    element,
  ) {
    final double top = tester.getTopLeft(find.byWidget(element.widget)).dy;
    return top > newTop && top < floor;
  }).length;
}

void main() {
  testWidgets('the two bulk controls and the row actions control are the platform buttons of R-03-059 on '
      'Android, carry their words and their R-32-401 glyphs, and each fires once (callouts 2, 3 '
      'and 11)', (tester) async {
    final (calls, _) = await _pump(
      tester,
      items: <NotificationItem>[_entry('w1:p1')],
    );

    expect(find.widgetWithText(TextButton, 'Mark all read'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Remove all'), findsOneWidget);
    expect(find.byIcon(Symbols.done_all_rounded), findsOneWidget);
    expect(find.byIcon(Symbols.delete_sweep_rounded), findsOneWidget);
    expect(
      find.widgetWithIcon(IconButton, Symbols.more_vert_rounded),
      findsOneWidget,
    );
    expect(find.byType(CupertinoButton), findsNothing);

    await tester.tap(find.bySemanticsLabel('Mark all read'));
    await tester.pump();
    expect(calls.markAll, 1);
  });

  testWidgets('the rows sit in NEW and EARLIER, unread first, and a read row moves groups on the '
      'emission that carries it (R-31-07-11, R-31-07-03)', (tester) async {
    final (_, controller) = await _pump(
      tester,
      items: <NotificationItem>[
        _entry('w1:p1', agentKind: 'omp'),
        _entry('w1:p2', seen: true, status: AgentStatusKind.done),
      ],
    );

    expect(find.text(newHeaderLabel), findsOneWidget);
    expect(find.text(earlierHeaderLabel), findsOneWidget);
    final double newTop = tester.getTopLeft(find.text(newHeaderLabel)).dy;
    final double unreadTop = tester.getTopLeft(find.text('omp is blocked')).dy;
    final double earlierTop = tester
        .getTopLeft(find.text(earlierHeaderLabel))
        .dy;
    final double readTop = tester.getTopLeft(find.text('claude is done')).dy;
    expect(newTop, lessThan(unreadTop));
    expect(unreadTop, lessThan(earlierTop));
    expect(earlierTop, lessThan(readTop));

    controller.add(<NotificationItem>[
      _entry('w1:p1', agentKind: 'omp', seen: true),
      _entry('w1:p2', seen: true, status: AgentStatusKind.done),
    ]);
    await tester.pumpAndSettle();
    expect(find.text(noNewSentence), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('omp is blocked')).dy,
      greaterThan(tester.getTopLeft(find.text(earlierHeaderLabel)).dy),
    );
  });

  testWidgets('the NEW group holds exactly the rows the badge predicate selects from the same list, '
      'before and after an emission (R-31-07-05)', (tester) async {
    final List<NotificationItem> items = <NotificationItem>[
      _entry('w1:p1'),
      _entry('w1:p2', seen: true),
      _entry('w1:p3', at: null),
    ];
    final (_, controller) = await _pump(tester, items: items);
    // `app_shell.dart`'s badge: `.where((entry) => !entry.seen).length` on the same log.
    int badge(List<NotificationItem> log) =>
        log.where((NotificationItem entry) => !entry.seen).length;

    expect(badge(items), 2);
    expect(_rowsUnderNew(tester), 2);

    final List<NotificationItem> next = <NotificationItem>[
      _entry('w1:p1', seen: true),
      _entry('w1:p2', seen: true),
      _entry('w1:p3', at: null),
    ];
    controller.add(next);
    await tester.pumpAndSettle();
    expect(badge(next), 1);
    expect(_rowsUnderNew(tester), 1);
  });

  testWidgets(
    'EARLIER is absent while no row is read, and NEW carries its one line while no row is '
    'unread, with Mark all read disabled (callouts 4 and 12, R-32-502)',
    (tester) async {
      final (_, controller) = await _pump(
        tester,
        items: <NotificationItem>[_entry('w1:p1')],
      );
      expect(find.text(earlierHeaderLabel), findsNothing);
      expect(find.text(noNewSentence), findsNothing);

      controller.add(<NotificationItem>[_entry('w1:p1', seen: true)]);
      await tester.pumpAndSettle();
      expect(find.text(newHeaderLabel), findsOneWidget);
      expect(find.text(noNewSentence), findsOneWidget);
      expect(find.text(earlierHeaderLabel), findsOneWidget);
      // Disabled is the platform button's own state (R-03-059): the node says so, and the
      // `Empty` golden shows the theme's dim.
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Mark all read'))
            .flagsCollection
            .isEnabled,
        Tristate.isFalse,
      );
    },
  );

  testWidgets(
    'a row draws the phrase with the age at the end of line one and the breadcrumb on line '
    'two, with no status word of its own (callouts 5 to 7, R-03-058)',
    (tester) async {
      await _pump(
        tester,
        items: <NotificationItem>[
          _entry('w1:p1'),
          _entry('w1:p2', seen: true, status: AgentStatusKind.done, at: null),
        ],
      );

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('claude is blocked'), findsOneWidget);
      expect(find.text('claude is done'), findsOneWidget);
      expect(find.text('Blocked'), findsNothing);
      expect(find.text('Done'), findsNothing);
      expect(find.text('4m 00s'), findsOneWidget);
      final Finder breadcrumb = find.text(
        'lightspeed-kit\u2009\u203A\u2009impl\u2009\u203A\u2009main.py',
      );
      expect(breadcrumb, findsNWidgets(2));

      // The age ends line one: right of the phrase, above the breadcrumb.
      expect(
        tester.getTopLeft(find.text('4m 00s')).dx,
        greaterThan(tester.getTopRight(find.text('claude is blocked')).dx),
      );
      expect(
        tester.getBottomLeft(find.text('4m 00s')).dy,
        lessThanOrEqualTo(tester.getTopLeft(breadcrumb.first).dy),
      );
    },
  );

  testWidgets('an empty segment is skipped, never drawn blank (callout 6)', (
    tester,
  ) async {
    await _pump(
      tester,
      items: <NotificationItem>[_entry('w1:p1', spaceName: '')],
    );

    expect(find.text('impl\u2009\u203A\u2009main.py'), findsOneWidget);
  });

  testWidgets(
    'an unread row says so in its semantics label; a read row does not '
    '(R-31-07-03)',
    (tester) async {
      await _pump(
        tester,
        items: <NotificationItem>[_entry('w1:p1'), _entry('w1:p2', seen: true)],
      );

      expect(
        find.bySemanticsLabel(RegExp(r'^claude is blocked, .*, unread$')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'^claude is blocked, .*4m 00s$')),
        findsOneWidget,
      );
    },
  );

  testWidgets('a row tap fires onOpenPane with the pane id (R-31-07-05)', (
    tester,
  ) async {
    final (calls, _) = await _pump(
      tester,
      items: <NotificationItem>[_entry('w1:p1')],
    );

    await tester.tap(find.text('claude is blocked'));
    await tester.pump();

    expect(calls.open, <String>['w1:p1']);
  });

  testWidgets('a long press opens Mark as read and Remove on an unread row, and Remove alone on a read '
      'row (R-31-07-09)', (tester) async {
    final (calls, _) = await _pump(
      tester,
      items: <NotificationItem>[
        _entry('w1:p1'),
        _entry('w1:p2', seen: true, status: AgentStatusKind.done),
      ],
    );

    await openRowActions(tester, find.text('claude is blocked'));
    expect(find.text('Remove'), findsOneWidget);
    expect(find.text('Mark as read'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(calls.remove, <String>['w1:p1']);
    expect(find.text('Remove'), findsNothing, reason: 'the menu closed');

    await openRowActions(tester, find.text('claude is blocked'));
    await tester.tap(find.text('Mark as read'));
    await tester.pumpAndSettle();
    expect(calls.markSeen, <String>['w1:p1']);

    await openRowActions(tester, find.text('claude is done'));
    expect(find.text('Remove'), findsOneWidget);
    expect(
      find.text('Mark as read'),
      findsNothing,
      reason: 'a read row offers no Mark as read',
    );
  });

  testWidgets(
    'every revealed action is also a named custom semantics action (R-30-298)',
    (tester) async {
      final handle = tester.ensureSemantics();
      final (calls, _) = await _pump(
        tester,
        items: <NotificationItem>[_entry('w1:p1'), _entry('w1:p2', seen: true)],
      );

      final SemanticsNode unread = tester.getSemantics(
        find.bySemanticsLabel(RegExp(r'unread$')),
      );
      final SemanticsNode read = tester.getSemantics(
        find.bySemanticsLabel(RegExp(r'^claude is blocked, .*4m 00s$')),
      );
      expect(
        unread.getSemanticsData().customSemanticsActionIds,
        containsAll(<int>[
          CustomSemanticsAction.getIdentifier(
            const CustomSemanticsAction(label: 'Mark as read'),
          ),
          CustomSemanticsAction.getIdentifier(
            const CustomSemanticsAction(label: 'Remove'),
          ),
        ]),
      );
      expect(
        read.getSemanticsData().customSemanticsActionIds,
        isNot(
          contains(
            CustomSemanticsAction.getIdentifier(
              const CustomSemanticsAction(label: 'Mark as read'),
            ),
          ),
        ),
      );
      expect(calls.markSeen, isEmpty);
      handle.dispose();
    },
  );

  testWidgets('the row actions control opens a menu with Mark as read (unread only) and Remove, on '
      'the same callbacks (callout 11)', (tester) async {
    final (calls, _) = await _pump(
      tester,
      items: <NotificationItem>[_entry('w1:p1'), _entry('w1:p2', seen: true)],
    );
    expect(find.bySemanticsLabel('Notification actions'), findsNWidgets(2));

    // The control's own glyph is the hit target: the semantics finder's rect can be the
    // merged row node, whose centre is the row tap, not this control.
    await tester.tap(find.byIcon(Symbols.more_vert_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('Mark as read'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
    await tester.tap(find.text('Mark as read'));
    await tester.pumpAndSettle();
    expect(calls.markSeen, <String>['w1:p1']);
    expect(find.text('Remove'), findsNothing, reason: 'the sheet closed');

    await tester.tap(find.byIcon(Symbols.more_vert_rounded).last);
    await tester.pumpAndSettle();
    expect(
      find.text('Mark as read'),
      findsNothing,
      reason: 'a read row has nothing to mark',
    );
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(calls.remove, <String>['w1:p2']);
  });

  testWidgets('Remove all confirms first; Cancel fires nothing and the destructive verb fires '
      'onRemoveAll (R-31-07-04, docs/32 section 7.17)', (tester) async {
    final (calls, _) = await _pump(
      tester,
      items: <NotificationItem>[_entry('w1:p1')],
    );

    await tester.tap(find.bySemanticsLabel('Remove all'));
    await tester.pumpAndSettle();
    expect(find.text('Remove all notifications?'), findsOneWidget);
    expect(
      find.text(
        'This clears the list on this phone. Nothing changes on patrick-desk.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(calls.removeAll, 0);

    await tester.tap(find.bySemanticsLabel('Remove all'));
    await tester.pumpAndSettle();
    // The dialog's verb, not the strip's button: both read `Remove all` as
    // written (R-03-104).
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Remove all'),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls.removeAll, 1);
  });

  testWidgets(
    'a failed write shows its message inline and clears on the next success '
    '(R-31-07-01, R-30-803)',
    (tester) async {
      final (calls, _) = await _pump(
        tester,
        items: <NotificationItem>[_entry('w1:p1')],
      );
      calls.result = const Err('store the acknowledgement');

      await tester.tap(find.bySemanticsLabel('Mark all read'));
      await tester.pumpAndSettle();
      expect(find.text('store the acknowledgement'), findsOneWidget);

      calls.result = const Ok(null);
      await tester.tap(find.bySemanticsLabel('Mark all read'));
      await tester.pumpAndSettle();
      expect(find.text('store the acknowledgement'), findsNothing);
    },
  );

  testWidgets(
    'the age counts while the screen is on screen, without an emission (R-31-07-12)',
    (tester) async {
      DateTime clock = _fixedNow;
      await _pump(
        tester,
        items: <NotificationItem>[_entry('w1:p1')],
        now: () => clock,
      );
      expect(find.text('4m 00s'), findsOneWidget);

      clock = clock.add(const Duration(seconds: 31));
      await tester.pump(const Duration(seconds: 31));
      expect(find.text('4m 31s'), findsOneWidget);
      expect(find.text('4m 00s'), findsNothing);
    },
  );

  testWidgets('a new agent_status lands at the top of NEW on its emission, and a rebuild with a fresh '
      'log shows that log (R-31-07-12)', (tester) async {
    final controller = StreamController<List<NotificationItem>>.broadcast();
    addTearDown(controller.close);
    await _pump(
      tester,
      items: <NotificationItem>[_entry('w1:p1')],
      controller: controller,
    );
    expect(find.text('omp is done'), findsNothing);

    controller.add(<NotificationItem>[
      _entry(
        'w1:p9',
        agentKind: 'omp',
        status: AgentStatusKind.done,
        at: '2026-09-04T10:03:00Z',
      ),
      _entry('w1:p1'),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('omp is done'), findsOneWidget);
    expect(find.text('1m 00s'), findsOneWidget);
    final double newTop = tester.getTopLeft(find.text(newHeaderLabel)).dy;
    final double insertedTop = tester.getTopLeft(find.text('omp is done')).dy;
    expect(insertedTop, greaterThan(newTop));
    expect(
      insertedTop,
      lessThan(tester.getTopLeft(find.text('claude is blocked')).dy),
    );

    // The route rebuilt the screen with the log as it stands: the rows follow it.
    await _pump(
      tester,
      items: <NotificationItem>[_entry('w1:p1', seen: true)],
      controller: controller,
    );
    expect(find.text('omp is done'), findsNothing);
    expect(find.text(noNewSentence), findsOneWidget);
  });

  testWidgets('the Empty state names the computer and disables both controls', (
    tester,
  ) async {
    final (calls, _) = await _pump(tester);

    expect(find.text('No notifications.'), findsOneWidget);
    expect(find.byType(Eyebrow), findsNothing);
    expect(
      find.text('Agent status changes on patrick-desk appear here.'),
      findsOneWidget,
    );
    expect(find.text(newHeaderLabel), findsNothing);
    for (final String label in <String>['Mark all read', 'Remove all']) {
      expect(
        tester
            .getSemantics(find.bySemanticsLabel(label))
            .flagsCollection
            .isEnabled,
        Tristate.isFalse,
        reason: '$label has nothing to act on',
      );
    }
    await tester.tap(find.bySemanticsLabel('Remove all'));
    await tester.pumpAndSettle();
    expect(find.text('Remove all notifications?'), findsNothing);
    expect(calls.removeAll, 0);
  });

  testWidgets(
    'a list with rows paints no ground grid and ends with its last group; the empty '
    'state is the grid with the mark, its title in the display face in accent ink and its '
    'sentence in body secondary (R-03-107, amended 2026-09-09)',
    (tester) async {
      final (_, controller) = await _pump(
        tester,
        items: <NotificationItem>[_entry('w1:p1'), _entry('w1:p2', seen: true)],
      );

      expect(find.byType(GroundGrid), findsNothing);
      expect(find.byType(EmptyMark), findsNothing);
      // `NEW` and `EARLIER`, each a padded group, and nothing after the last: no remainder and
      // no clearance for a create control (R-03-109).
      final CustomScrollView list = tester.widget<CustomScrollView>(
        find.byType(CustomScrollView),
      );
      expect(list.slivers, hasLength(2));
      expect(list.slivers, everyElement(isA<SliverPadding>()));
      expect(find.text(newHeaderLabel), findsOneWidget);
      expect(find.text(earlierHeaderLabel), findsOneWidget);

      controller.add(const <NotificationItem>[]);
      await tester.pumpAndSettle();

      final Finder title = find.text('No notifications.');
      expect(
        find.descendant(
          of: find.descendant(
            of: find.byType(GroundGrid),
            matching: find.byType(EmptyMark),
          ),
          matching: title,
        ),
        findsOneWidget,
      );
      expect(find.byType(Eyebrow), findsNothing); // R-31-07-10.
      final AppColor color = AppColor.of(tester.element(title));
      final TextStyle titleStyle = tester.widget<Text>(title).style!;
      expect(titleStyle.fontFamily, AppType.title.fontFamily);
      expect(titleStyle.fontSize, AppType.title.fontSize);
      expect(titleStyle.color, color.accentText);
      final TextStyle sentenceStyle = tester
          .widget<Text>(
            find.text('Agent status changes on patrick-desk appear here.'),
          )
          .style!;
      expect(sentenceStyle.fontSize, AppType.body.fontSize);
      expect(sentenceStyle.color, color.fgSecondary);
      // Left aligned at `space.4` (R-32-553), not centred.
      expect(tester.getTopLeft(title).dx, AppSpace.space4);
    },
  );

  testWidgets(
    'the pane-closed strip shows only when a closed pane is named (R-31-07-07)',
    (tester) async {
      await _pump(tester, items: <NotificationItem>[_entry('w1:p1')]);
      expect(find.text(paneClosedSentence), findsNothing);

      await _pump(
        tester,
        items: <NotificationItem>[_entry('w1:p1')],
        closedPaneId: 'w1:p9',
      );
      expect(find.text(paneClosedSentence), findsOneWidget);
      expect(
        find.text('claude is blocked'),
        findsOneWidget,
        reason: 'the list still draws',
      );
    },
  );

  testWidgets(
    'a stream emission redraws the list, from rows to Empty and back',
    (tester) async {
      final (_, controller) = await _pump(
        tester,
        items: <NotificationItem>[_entry('w1:p1')],
      );
      expect(find.text('claude is blocked'), findsOneWidget);

      controller.add(const <NotificationItem>[]);
      await tester.pumpAndSettle();
      expect(find.text('No notifications.'), findsOneWidget);

      controller.add(<NotificationItem>[_entry('w1:p1'), _entry('w1:p2')]);
      await tester.pumpAndSettle();
      expect(find.text('claude is blocked'), findsNWidgets(2));
    },
  );

  testWidgets('iOS draws the Cupertino chrome with the same title, and every control is a CupertinoButton '
      '(R-03-059)', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await _pump(tester, items: <NotificationItem>[_entry('w1:p1')]);

    expect(find.byType(CupertinoNavigationBar), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.bySemanticsLabel('Mark all read'), findsOneWidget);
    expect(find.bySemanticsLabel('Remove all'), findsOneWidget);
    expect(
      find.widgetWithText(CupertinoButton, 'Mark all read'),
      findsOneWidget,
    );
    expect(find.widgetWithText(CupertinoButton, 'Remove all'), findsOneWidget);
    expect(
      find.widgetWithIcon(CupertinoButton, Symbols.more_vert_rounded),
      findsOneWidget,
    );
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(IconButton), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
  for (final platform in <TargetPlatform>[
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    testWidgets(
      'native notification controls preserve actions on ${platform.name}',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final (calls, _) = await _pump(
          tester,
          items: <NotificationItem>[_entry('w1:p1')],
        );
        final Type tile = platform == TargetPlatform.iOS
            ? CupertinoListTile
            : ListTile;
        expect(find.byType(tile), findsOneWidget);
        await openRowActions(tester, find.text('claude is blocked'));
        // The long press opens the platform menu of R-33-033's `Row actions` row:
        // `MenuItemButton` at the finger on Android, `CupertinoContextMenuAction` under the
        // row's preview on iOS, each choice with its glyph.
        final Type rowItem = platform == TargetPlatform.iOS
            ? CupertinoContextMenuAction
            : MenuItemButton;
        expect(calls.remove, isEmpty);
        expect(find.widgetWithText(rowItem, 'Mark as read'), findsOneWidget);
        expect(
          find.descendant(
            of: find.widgetWithText(rowItem, 'Remove'),
            matching: find.byIcon(Symbols.delete_outline_rounded),
          ),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(rowItem, 'Remove'));
        await tester.pumpAndSettle();
        expect(calls.remove, <String>['w1:p1']);
        expect(find.byType(rowItem), findsNothing);
        await openRowActions(tester, find.text('claude is blocked'));
        await tester.tap(find.widgetWithText(rowItem, 'Mark as read'));
        await tester.pumpAndSettle();
        expect(calls.markSeen, <String>['w1:p1']);
        // The row's `⋮` opens the platform menu of R-33-033: `MenuItemButton` on Android,
        // `CupertinoMenuItem` on iOS, each choice with its glyph.
        await tester.tap(find.byIcon(Symbols.more_vert_rounded));
        await tester.pumpAndSettle();
        final Type item = platform == TargetPlatform.iOS
            ? CupertinoMenuItem
            : MenuItemButton;
        expect(find.widgetWithText(item, 'Remove'), findsOneWidget);
        expect(find.widgetWithText(item, 'Mark as read'), findsOneWidget);
        expect(
          find.descendant(
            of: find.widgetWithText(item, 'Mark as read'),
            matching: find.byIcon(Symbols.done_all_rounded),
          ),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(item, 'Remove'));
        await tester.pumpAndSettle();
        expect(calls.remove, <String>['w1:p1', 'w1:p1']);
        expect(calls.open, isEmpty);
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
}
