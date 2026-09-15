/// Golden tests for `NotificationSettingsScreenBody`
/// (`app/lib/screens/notification_settings_screen.dart`, `WP-19-b`), one per named row of
/// `docs/31-mockups/12-notifications.md`'s `## States` table this file's scope covers
/// (`Default` and `Permission denied`), each rendered in both Selenized dark and light
/// (R-32-012).
///
/// Renders `NotificationSettingsScreenBody` directly, not the stateful
/// `NotificationSettingsScreen`: the presentational split documented at the top of
/// `notification_settings_screen.dart` exists exactly so this file needs no
/// `NotificationsService`, mirroring `lock_screen_golden_test.dart`'s precedent.
///
/// Fonts, the app theme and the 375 x 667 reference size come from `golden_support.dart`
/// (`loadAppFonts`, `goldenApp`, `goldenReferenceSize`); see its doc comment for why.
/// `devicePixelRatio` stays fixed at 1.0.
library;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoSwitch;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart'
    show
        addTearDown,
        expect,
        expectLater,
        find,
        findsNWidgets,
        findsOneWidget,
        matchesGoldenFile,
        setUpAll,
        testWidgets;
import 'package:herdr_mobile/screens/notification_settings_screen.dart'
    show NotificationSettingsPhase, NotificationSettingsScreenBody;
import 'package:herdr_mobile/services/notifications.dart'
    show NotificationSettings;
import 'package:material_ui/material_ui.dart' show Switch;

import 'golden_support.dart';

NotificationSettingsScreenBody _body(NotificationSettingsPhase phase) =>
    NotificationSettingsScreenBody(
      phase: phase,
      settings: const NotificationSettings(),
      savingSettings: const {},
      isSendingTestAlert: false,
      onAgentBlockedChanged: (bool _) {},
      onAgentDoneChanged: (bool _) {},
      onOnlyOpenedAgentsChanged: (bool _) {},
      onHoldAlertsChanged: (bool _) {},
      onQuietHoursTap: () {},
      onSendTestAlert: () {},
      onOpenSystemSettings: () {},
    );

/// One entry per named row of the mockup's `## States` table this file covers: `Default`, the
/// toggle-list row, and `Permission denied`, the one named recovery state.
class _Case {
  const _Case({required this.name, required this.phase});

  final String name;
  final NotificationSettingsPhase phase;
}

const _cases = <_Case>[
  _Case(name: 'default', phase: NotificationSettingsPhase.normal),
  _Case(
    name: 'permission_denied',
    phase: NotificationSettingsPhase.permissionDenied,
  ),
];

const _themes = <(String, Brightness)>[
  ('dark', Brightness.dark),
  ('light', Brightness.light),
];

void main() {
  setUpAll(loadAppFonts);

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final testCase in _cases) {
      for (final (themeName, brightness) in _themes) {
        testWidgets(
          '${testCase.name} ($platform, $themeName) matches docs/31-mockups/12-notifications.md',
          (tester) async {
            debugDefaultTargetPlatformOverride = platform;
            addTearDown(() => debugDefaultTargetPlatformOverride = null);
            tester.view.physicalSize = goldenReferenceSize;
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await tester.pumpWidget(
              goldenApp(brightness: brightness, child: _body(testCase.phase)),
            );
            await tester.pumpAndSettle();
            expect(
              find.byType(
                platform == TargetPlatform.iOS ? CupertinoSwitch : Switch,
              ),
              findsNWidgets(4),
            );
            // Structural proof alongside the visual one: every callout the mockup names is
            // really present in the tree, not just painted to look right by coincidence.
            expect(find.text('Alerts'), findsOneWidget);
            expect(find.text('An agent is blocked'), findsOneWidget);
            expect(find.text('An agent is done'), findsOneWidget);
            expect(find.text('Only agents I have opened'), findsOneWidget);
            expect(find.text('Every agent on this computer'), findsOneWidget);
            expect(find.text('Hold alerts'), findsOneWidget);
            expect(find.text('From 22:00 to 07:30'), findsOneWidget);
            expect(
              find.text('Alerts are off for this app.'),
              findsNWidgets(
                testCase.phase == NotificationSettingsPhase.permissionDenied
                    ? 1
                    : 0,
              ),
            );
            expect(
              find.text('Open Settings'),
              findsNWidgets(
                testCase.phase == NotificationSettingsPhase.permissionDenied
                    ? 1
                    : 0,
              ),
            );

            await expectLater(
              find.byType(NotificationSettingsScreenBody),
              matchesGoldenFile(
                'goldens/notification_settings_${testCase.name}${platform == TargetPlatform.iOS ? '_ios' : ''}_$themeName.png',
              ),
            );

            // Each block is its own lazily built list child (R-03-107), and the test row sits
            // below the fold on the reference surface, so the golden above is taken first and
            // the row is scrolled in only afterwards.
            await tester.scrollUntilVisible(
              find.text('Send a test alert'),
              200,
            );
            expect(find.text('Send a test alert'), findsOneWidget);
            debugDefaultTargetPlatformOverride = null;
          },
        );
      }
    }
  }
}
