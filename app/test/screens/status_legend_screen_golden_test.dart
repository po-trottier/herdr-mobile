/// Golden tests for `StatusLegendScreen` (`app/lib/screens/status_legend_screen.dart`), the
/// `Status colours` legend of `docs/31-mockups/20-status-legend.md` (R-03-106), rendered in both
/// Selenized dark and light (R-32-012) and on both platforms (R-33-073). The mockup has one
/// `Default` state; the iPhone SE reference viewport is too short for its five groups, so each
/// platform takes two frames, the top of the list (`default`) and the list scrolled to its end
/// (`list_end`), mirroring `settings_screen_golden_test.dart`. Together the frames read back every
/// bar swatch in its hue group beside its word.
///
/// Animations are disabled through the `MediaQuery` (`disableAnimations`), as
/// `agent_list_screen_golden_test.dart` does: the `Working` bar pulses with `motion.pulse`
/// (R-32-592) and a repeating animation never settles; under reduce motion the bar is static at
/// full opacity (R-30-403), which is also the frame a golden can hold.
///
/// Fonts, the app theme and the 375 x 667 reference size come from `golden_support.dart`
/// (`loadAppFonts`, `goldenApp`, `goldenReferenceSize`); see its doc comment for why.
/// `devicePixelRatio` stays fixed at 1.0.
library;

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoListSection, CupertinoListTile;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart' show Brightness, CustomScrollView, Offset;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/screens/status_legend_screen.dart';
import 'package:herdr_mobile/widgets/app_list_row.dart' show AppListRow;
import 'package:herdr_mobile/widgets/status_bar.dart' show BarState, StatusBar;

import 'golden_support.dart';

const _themes = <(String, Brightness)>[
  ('dark', Brightness.dark),
  ('light', Brightness.light),
];

void main() {
  setUpAll(loadAppFonts);

  Future<void> pumpLegend(WidgetTester tester, Brightness brightness) async {
    tester.view.physicalSize = goldenReferenceSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      goldenApp(
        brightness: brightness,
        adjust: (ambient) => ambient.copyWith(disableAnimations: true),
        child: const StatusLegendScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Scrolls the list to `Unknown`, the last row, so the frame holds `GREEN`, `TEAL` and `GREY`.
  Future<void> scrollToEnd(WidgetTester tester) async {
    await tester.dragUntilVisible(
      find.text('Unknown'),
      find.byType(CustomScrollView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
  }

  for (final (themeName, brightness) in _themes) {
    testWidgets(
      'default ($themeName) matches docs/31-mockups/20-status-legend.md',
      (tester) async {
        await pumpLegend(tester, brightness);

        // Structural proof alongside the visual one: the top frame holds the lead line and the
        // two hue groups whose rows are all agent-or-connection pairs.
        expect(find.text('Status colours'), findsOneWidget);
        expect(find.text(statusLegendLead), findsOneWidget);
        expect(find.text('AMBER'), findsOneWidget);
        expect(find.text('Working'), findsOneWidget);
        expect(find.text('Warning'), findsOneWidget);
        expect(find.text('RED'), findsOneWidget);
        expect(find.text('Blocked'), findsOneWidget);
        expect(find.text('Error'), findsOneWidget);
        expect(find.byType(AppListRow), findsWidgets);
        expect(find.byType(CupertinoListTile), findsNothing);

        await expectLater(
          find.byType(StatusLegendScreen),
          matchesGoldenFile(
            'goldens/status_legend_screen_default_$themeName.png',
          ),
        );
      },
    );

    testWidgets(
      'list_end ($themeName) matches docs/31-mockups/20-status-legend.md',
      (tester) async {
        await pumpLegend(tester, brightness);
        await scrollToEnd(tester);

        expect(find.text('GREEN'), findsOneWidget);
        expect(find.text('Idle'), findsOneWidget);
        expect(find.text('Ok'), findsOneWidget);
        expect(
          find.text(
            'A paired computer or phone that is not connected shows Idle too.',
          ),
          findsOneWidget,
        );
        expect(find.text('TEAL'), findsOneWidget);
        expect(find.text('Done'), findsOneWidget);
        expect(find.text('GREY'), findsOneWidget);
        expect(find.text('Unknown'), findsOneWidget);
        // Every state that the frame shows draws its own bar, one per row.
        expect(
          tester
              .widgetList<StatusBar>(find.byType(StatusBar))
              .map((StatusBar bar) => bar.state),
          containsAll(<BarState>[
            BarState.idle,
            BarState.ok,
            BarState.done,
            BarState.unknown,
          ]),
        );

        await expectLater(
          find.byType(StatusLegendScreen),
          matchesGoldenFile(
            'goldens/status_legend_screen_list_end_$themeName.png',
          ),
        );
      },
    );
  }

  // The iOS branch: `CupertinoPageScaffold` over `ChromeSettingsSection`'s inset-grouped
  // `CupertinoListSection`, every row a `CupertinoListTile` through `ChromeListRow.static`
  // (R-33-073), the state bar flush to the card's leading edge. The frames prove that the bar
  // paints over the tile without moving its text, and that no `Text` falls back to
  // `MaterialApp`'s yellow double underline (R-41-020).
  for (final (themeName, brightness) in _themes) {
    testWidgets(
      'default_ios ($themeName) matches docs/31-mockups/20-status-legend.md',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        await pumpLegend(tester, brightness);

        expect(find.text('Status colours'), findsOneWidget);
        expect(find.byType(CupertinoListSection), findsWidgets);
        expect(find.byType(AppListRow), findsNothing);
        for (final String word in <String>['Working', 'Warning', 'Blocked']) {
          expect(
            find.ancestor(
              of: find.text(word),
              matching: find.byType(CupertinoListTile),
            ),
            findsOneWidget,
          );
        }

        await expectLater(
          find.byType(StatusLegendScreen),
          matchesGoldenFile(
            'goldens/status_legend_screen_default_ios_$themeName.png',
          ),
        );
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      'list_end_ios ($themeName) matches docs/31-mockups/20-status-legend.md',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        await pumpLegend(tester, brightness);
        await scrollToEnd(tester);

        expect(find.byType(AppListRow), findsNothing);
        for (final String word in <String>['Idle', 'Ok', 'Done', 'Unknown']) {
          expect(
            find.ancestor(
              of: find.text(word),
              matching: find.byType(CupertinoListTile),
            ),
            findsOneWidget,
          );
        }

        await expectLater(
          find.byType(StatusLegendScreen),
          matchesGoldenFile(
            'goldens/status_legend_screen_list_end_ios_$themeName.png',
          ),
        );
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
}
