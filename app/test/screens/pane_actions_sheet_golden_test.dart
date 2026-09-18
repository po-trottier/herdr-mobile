/// Golden tests for `PaneActionsSheet` (`app/lib/screens/pane_actions_sheet.dart`, `WP-16-c`),
/// one per named state of `docs/31-mockups/10-pane-actions.md`'s `## States` table this file
/// covers (R-90-011), each rendered in both Selenized dark and light (R-32-012).
///
/// Opens the sheet through the real `showPaneActionsSheet` API, mirroring
/// `pane_actions_sheet_test.dart`'s own `_openSheet` helper, rather than constructing
/// `PaneActionsSheet` directly: `showModalBottomSheet` is the one place that wraps the sheet's
/// content in a `Material` ancestor and applies its `shape`/`backgroundColor` (`radius.lg`
/// top corners, `color.bg.raised`, per R-32-320 and section 7.16). A bare `Directionality` +
/// `MediaQuery` harness with no `Material` ancestor would let every `Text` here fall back to
/// `MaterialApp`'s own ugly yellow-underline error style, per `lock_screen.dart`'s and
/// `welcome_screen.dart`'s own top doc comments on the same trap.
///
/// Fonts, the app theme and the 375 x 667 reference size come from `golden_support.dart`
/// (`loadAppFonts`, `goldenApp`, `goldenReferenceSize`); see its doc comment for why.
/// `devicePixelRatio` stays fixed at 1.0.
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart' show Brightness, MediaQueryData;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/screens/pane_actions_sheet.dart';
import 'package:material_ui/material_ui.dart'
    show Builder, ElevatedButton, MaterialApp, Scaffold, Text;

import 'golden_support.dart';

/// Opens [PaneActionsSheet] under a fixed [brightness], mirroring `pane_actions_sheet_test.
/// dart`'s own `_openSheet`. `goldenApp`'s `MediaQuery` sits above the `MaterialApp`, so the
/// sheet `showModalBottomSheet` pushes above `home` reads the same brightness and the real
/// reference size R-31-10-09's `sizeOf(context).height * 0.9` height bound needs.
/// [screenReaderOn] sets `accessibleNavigation`, which adds the `Read the last 20 lines` row.
Future<void> _openSheet(
  WidgetTester tester, {
  required Brightness brightness,
  String paneTitle = 'claude / main',
  String currentLabel = 'main',
  String? agentKind,
  String? agentStatusLine,
  PaneActionsLinkState linkState = PaneActionsLinkState.normal,
  String? linkStateDetail,
  bool screenReaderOn = false,
}) async {
  void noOp() {}
  // Every row gets a callback, so a golden shows the rows a person meets (enabled), not the
  // disabled look a missing callback would draw. No golden taps one.
  await tester.pumpWidget(
    goldenApp(
      brightness: brightness,
      adjust: (MediaQueryData ambient) =>
          ambient.copyWith(accessibleNavigation: screenReaderOn),
      child: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showPaneActionsSheet(
              context,
              paneTitle: paneTitle,
              currentLabel: currentLabel,
              agentKind: agentKind,
              agentStatusLine: agentStatusLine,
              linkState: linkState,
              linkStateDetail: linkStateDetail,
              onTapDiagnostics: noOp,
              onOpenPluginActions: noOp,
              onClosePane: noOp,
              onSplit: (_) {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

class _Case {
  const _Case(
    this.name, {
    this.agentKind,
    this.agentStatusLine,
    this.linkState = PaneActionsLinkState.normal,
    this.linkStateDetail,
    this.screenReaderOn = false,
  });

  final String name;
  final String? agentKind;
  final String? agentStatusLine;
  final PaneActionsLinkState linkState;
  final String? linkStateDetail;
  final bool screenReaderOn;
}

/// The sheet offers plugin actions, splits, and close on an agent pane.
/// A screen reader adds Read last 20 lines.
/// Offline and host-in-use states disable the split and close actions.
/// Plugin actions stays enabled because it only opens a screen.
const _cases = <_Case>[
  _Case(
    'default_agent_pane',
    agentKind: 'claude',
    agentStatusLine: 'claude - working 12s',
  ),
  _Case(
    'screen_reader_on',
    agentKind: 'claude',
    agentStatusLine: 'claude - working 12s',
    screenReaderOn: true,
  ),
  _Case(
    'host_in_use',
    agentKind: 'claude',
    agentStatusLine: 'claude - working 12s',
    linkState: PaneActionsLinkState.hostInUse,
    linkStateDetail: 'Another phone is using this pane.',
  ),
  _Case(
    'offline',
    agentKind: 'claude',
    agentStatusLine: 'claude - working 12s',
    linkState: PaneActionsLinkState.offline,
    linkStateDetail: 'No route to the relay.',
  ),
];

const _themes = <(String, Brightness)>[
  ('dark', Brightness.dark),
  ('light', Brightness.light),
];

void main() {
  setUpAll(loadAppFonts);

  for (final (platformName, platform) in [
    ('', TargetPlatform.android),
    ('ios_', TargetPlatform.iOS),
  ]) {
    for (final testCase in _cases) {
      for (final (themeName, brightness) in _themes) {
        testWidgets(
          '$platformName${testCase.name} ($themeName) matches docs/31-mockups/10-pane-actions.md',
          (tester) async {
            debugDefaultTargetPlatformOverride = platform;
            addTearDown(() => debugDefaultTargetPlatformOverride = null);
            tester.view.physicalSize = goldenReferenceSize;
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await _openSheet(
              tester,
              brightness: brightness,
              agentKind: testCase.agentKind,
              agentStatusLine: testCase.agentStatusLine,
              linkState: testCase.linkState,
              linkStateDetail: testCase.linkStateDetail,
              screenReaderOn: testCase.screenReaderOn,
            );

            // Structural proof alongside the visual one: every row the wireframe names is
            // really present, and no row R-03-101 removed came back.
            expect(find.text('claude / main'), findsOneWidget);
            expect(find.text('Plugin actions'), findsOneWidget);
            expect(
              find.text('Read the last 20 lines'),
              findsNWidgets(testCase.screenReaderOn ? 1 : 0),
            );
            expect(find.text('Split right'), findsOneWidget);
            expect(find.text('Split down'), findsOneWidget);
            expect(find.text('Close pane'), findsOneWidget);
            expect(find.text('Cancel'), findsOneWidget);
            expect(find.text('Send a prompt to claude'), findsNothing);
            expect(find.text('Copy the whole screen'), findsNothing);
            expect(
              find.text(testCase.linkStateDetail ?? ''),
              findsNWidgets(testCase.linkStateDetail == null ? 0 : 1),
            );

            // The whole app, not the content alone: the sheet's surface, corner and handle
            // are the platform component's own, drawn around the content (R-33-033).
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile(
                'goldens/pane_actions_sheet_${testCase.name}_$platformName$themeName.png',
              ),
            );
            debugDefaultTargetPlatformOverride = null;
          },
        );
      }
    }
  }
}
