/// Tests `pane_actions_sheet.dart` (`WP-16-c`) against `docs/31-mockups/10-pane-actions.md`:
/// the row set R-03-101 fixes (R-31-10-03), the `Read the last 20 lines` accessibility
/// announcement (R-31-10-06), the sheet drawing no read-only/permission indicator on any row
/// (R-31-10-07), the `Plugin actions` row that closes the sheet and hands the route to the
/// caller, even offline (callout 5, R-03-055), the `Close pane` confirmation (R-31-10-01), and
/// the action region scrolling under a fixed grab handle, header and Cancel at a small viewport
/// and a large text scale, plus `Cancel` staying above a raised keyboard (R-31-10-09).
library;

import 'package:flutter/widgets.dart'
    show
        EdgeInsets,
        Icon,
        MediaQuery,
        MediaQueryData,
        Offset,
        Size,
        TextScaler,
        VoidCallback;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/screens/pane_actions_sheet.dart';
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart'
    show Builder, ElevatedButton, MaterialApp, Scaffold, Text;

/// Every row R-03-101 removed from the sheet. Not one of them may come back under any state.
const List<String> _removedRows = <String>[
  'Send a prompt to claude',
  'Split right',
  'Split down',
  'Zoom this pane',
  'Rename pane',
  'Copy the whole screen',
];

/// Opens [PaneActionsSheet] from a plain button under [mediaQueryData]. The override sits
/// above `MaterialApp`, not inside `home`: `showModalBottomSheet` pushes the sheet as a new
/// route mounted as a sibling of `home`'s route content under the same `Navigator`/`Overlay`,
/// so a `MediaQuery` placed only inside `home` never reaches it. `MaterialApp` itself never
/// introduces its own `MediaQuery` (the `View` widget does, further up, above this one), so
/// nothing shadows an override placed here.
Future<void> _openSheet(
  WidgetTester tester, {
  MediaQueryData mediaQueryData = const MediaQueryData(),
  String paneTitle = 'claude / main',
  String currentLabel = 'main',
  String? agentKind,
  String? agentStatusLine,
  String? visibleScreenText,
  PaneActionsLinkState linkState = PaneActionsLinkState.normal,
  VoidCallback? onOpenPluginActions,
  VoidCallback? onClosePane,
}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: mediaQueryData,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showPaneActionsSheet(
                context,
                paneTitle: paneTitle,
                currentLabel: currentLabel,
                agentKind: agentKind,
                agentStatusLine: agentStatusLine,
                visibleScreenText: visibleScreenText,
                linkState: linkState,
                onOpenPluginActions: onOpenPluginActions,
                onClosePane: onClosePane,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'on an agent pane with a screen reader on, the sheet holds Plugin actions, Read the last '
    '20 lines and Close pane, and none of the rows R-03-101 removed (R-31-10-03)',
    (WidgetTester tester) async {
      await _openSheet(
        tester,
        mediaQueryData: const MediaQueryData(
          size: Size(400, 1200),
          accessibleNavigation: true,
        ),
        agentKind: 'claude',
        agentStatusLine: 'claude - working 12s',
        onOpenPluginActions: () {},
        onClosePane: () {},
      );

      expect(find.text('Plugin actions'), findsOneWidget);
      expect(find.text('Read the last 20 lines'), findsOneWidget);
      expect(find.text('Close pane'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      for (final String label in _removedRows) {
        expect(find.text(label), findsNothing, reason: '$label left the sheet');
      }
    },
  );

  testWidgets(
    'Read the last 20 lines announces the last 20 non-empty lines with every escape sequence '
    'and trailing space stripped, and sends nothing to the pane (R-31-10-06)',
    (WidgetTester tester) async {
      // 22 lines, one of them (line 3) blank: 21 non-empty lines, so the earliest (line 1) is
      // dropped. Every kept line carries an SGR escape pair and trailing spaces.
      final List<int> nonEmptyLineNumbers = <int>[
        for (int n = 1; n <= 22; n++)
          if (n != 3) n,
      ];
      final String screenText = <int>[for (int n = 1; n <= 22; n++) n]
          .map((int n) => n == 3 ? '' : '\x1B[31mline $n\x1B[0m  ')
          .join('\n');
      final String expectedAnnouncement = nonEmptyLineNumbers
          .skip(1)
          .map((int n) => 'line $n')
          .join('\n');
      bool actedOnComputer = false;

      await _openSheet(
        tester,
        mediaQueryData: const MediaQueryData(
          size: Size(400, 1200),
          accessibleNavigation: true,
          supportsAnnounce: true,
        ),
        visibleScreenText: screenText,
        onClosePane: () => actedOnComputer = true,
      );

      await tester.tap(find.text('Read the last 20 lines'));
      await tester.pump();

      final List<CapturedAccessibilityAnnouncement> announcements = tester
          .takeAnnouncements();
      expect(announcements, hasLength(1));
      expect(announcements.single.message, expectedAnnouncement);
      expect(
        actedOnComputer,
        isFalse,
        reason: 'the row only announces; it never acts on the computer',
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Read the last 20 lines'),
        findsNothing,
        reason: 'the sheet closed',
      );
    },
  );

  testWidgets('the sheet draws no read-only-mode indicator, grant badge or per-action permission line '
      'for any row (R-31-10-07)', (WidgetTester tester) async {
    await _openSheet(
      tester,
      agentKind: 'claude',
      agentStatusLine: 'claude - working 12s',
      onOpenPluginActions: () {},
      onClosePane: () {},
    );

    expect(
      find.byType(Icon),
      findsNWidgets(3),
      reason:
          'each action has one leading icon, and the one row that opens a screen '
          '(Plugin actions) also carries the chevron; none is a permission indicator',
    );
    expect(find.byIcon(Symbols.extension_rounded), findsOneWidget);
    expect(find.byIcon(Symbols.chevron_right_rounded), findsOneWidget);
    // `Close pane, destructive` takes its R-32-401 glyph.
    expect(find.byIcon(Symbols.delete_outline_rounded), findsOneWidget);
    expect(
      find.textContaining(RegExp('permission', caseSensitive: false)),
      findsNothing,
    );
    expect(
      find.textContaining(RegExp('grant', caseSensitive: false)),
      findsNothing,
    );
    expect(
      find.textContaining(RegExp('read.?only', caseSensitive: false)),
      findsNothing,
    );
  });

  testWidgets(
    'Plugin actions closes the sheet and fires onOpenPluginActions, and stays enabled '
    'offline because it opens a screen (callout 5, R-03-055, R-30-807)',
    (WidgetTester tester) async {
      int opened = 0;
      await _openSheet(
        tester,
        mediaQueryData: const MediaQueryData(size: Size(400, 1200)),
        linkState: PaneActionsLinkState.offline,
        onOpenPluginActions: () => opened++,
      );
      expect(find.byType(PaneActionsSheet), findsOneWidget);

      await tester.tap(find.text('Plugin actions'));
      await tester.pumpAndSettle();

      expect(opened, 1);
      expect(find.byType(PaneActionsSheet), findsNothing);
    },
  );

  testWidgets('Close pane closes the sheet before confirmation and calls back only after confirmation '
      '(R-31-10-01)', (WidgetTester tester) async {
    bool closed = false;
    await _openSheet(
      tester,
      mediaQueryData: const MediaQueryData(size: Size(800, 600)),
      onClosePane: () => closed = true,
    );

    await tester.tap(find.text('Close pane'));
    await tester.pumpAndSettle();

    expect(find.text('Plugin actions'), findsNothing);
    // R-31-10-01's exact title and body.
    expect(find.text('Close main?'), findsOneWidget);
    expect(
      find.text(
        'Anything running in this pane stops, and its scrollback is gone.',
      ),
      findsOneWidget,
    );
    expect(closed, isFalse);

    await tester.tap(find.text('Close pane').last);
    await tester.pumpAndSettle();
    expect(closed, isTrue);
  });

  testWidgets('offline, Close pane is disabled and a tap sends nothing, while the sheet still opens '
      '(R-30-807)', (WidgetTester tester) async {
    bool closed = false;
    await _openSheet(
      tester,
      mediaQueryData: const MediaQueryData(size: Size(400, 1200)),
      linkState: PaneActionsLinkState.offline,
      onClosePane: () => closed = true,
    );

    await tester.tap(find.text('Close pane'));
    await tester.pumpAndSettle();

    expect(find.text('Close main?'), findsNothing);
    expect(closed, isFalse);
    expect(find.byType(PaneActionsSheet), findsOneWidget);
  });

  testWidgets(
    'at a small viewport and a 2.0 text scale, the action list scrolls to reveal Close pane '
    'while the header and Cancel stay fixed in place (R-31-10-09)',
    (WidgetTester tester) async {
      await _openSheet(
        tester,
        mediaQueryData: const MediaQueryData(
          size: Size(320, 300),
          textScaler: TextScaler.linear(2),
          accessibleNavigation: true,
        ),
        agentKind: 'claude',
        agentStatusLine: 'claude - working 12s',
        onOpenPluginActions: () {},
        onClosePane: () {},
      );

      expect(
        tester.takeException(),
        isNull,
        reason: 'no RenderFlex overflow at this scale',
      );
      expect(
        find.text('Close pane').hitTestable(),
        findsNothing,
        reason:
            'the last row starts scrolled out of the fixed 90%-height sheet',
      );

      final Offset headerBefore = tester.getTopLeft(find.text('claude / main'));
      final Offset cancelBefore = tester.getTopLeft(find.text('Cancel'));

      await tester.drag(find.text('Plugin actions'), const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(
        find.text('Close pane').hitTestable(),
        findsOneWidget,
        reason: 'the action region scrolled to reveal the last row',
      );
      expect(
        tester.getTopLeft(find.text('claude / main')),
        headerBefore,
        reason: 'the header stayed fixed above the scrolling action region',
      );
      expect(
        tester.getTopLeft(find.text('Cancel')),
        cancelBefore,
        reason: 'Cancel stayed fixed below the scrolling action region',
      );
    },
  );

  testWidgets(
    'with the keyboard raised, Cancel stays above the keyboard inset (R-31-10-09)',
    (WidgetTester tester) async {
      const double keyboard = 300;
      await _openSheet(
        tester,
        mediaQueryData: const MediaQueryData(
          size: Size(400, 800),
          viewInsets: EdgeInsets.only(bottom: keyboard),
        ),
      );

      const double keyboardTop = 800 - keyboard;
      expect(find.text('Cancel').hitTestable(), findsOneWidget);
      expect(
        tester.getBottomLeft(find.text('Cancel')).dy,
        lessThanOrEqualTo(keyboardTop),
        reason: 'Cancel sits above the keyboard',
      );
    },
  );
}
