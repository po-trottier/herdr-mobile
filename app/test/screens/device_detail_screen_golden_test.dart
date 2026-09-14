/// Golden test for `DeviceDetailScreen` (`app/lib/screens/device_detail_screen.dart`,
/// `WP-20-a`), drawn from `docs/31-mockups/14-devices.md`'s second wireframe (R-90-011). The
/// screen had no test file at all before its first golden — not a widget test, not a golden —
/// so this file is both.
///
/// [DeviceDetailScreen] takes every value it paints as a plain constructor argument and calls
/// no service, mirroring `LockScreenBody`'s split documented at the top of
/// `lock_screen_golden_test.dart`: no `_Harness` stream fake is needed here. It is a pushed
/// route since 2026-09-09 (R-03-105, R-33-072.1; until then a bottom sheet), so it renders
/// as `goldenApp`'s home with its own app bar and scaffold surface, and no stand-in `Material`.
///
/// Two shapes, each in both Selenized dark and light (R-32-012). `This phone` carries the
/// `Health` card of R-03-113 item 6 (2026-09-09): `Last connected`, `App Lock` (on here, so the
/// golden shows the value that differs from the default), `Pairing` and the `How to revoke`
/// caption with its inline `r` key, then the platform and the fingerprint, the rename-hint
/// caption (R-31-14-05) and `Remove`; it renders on both platforms (R-03-059, R-33-073),
/// because every row is the platform's own, so the iOS case proves the Cupertino tiles inside
/// their inset-grouped sections. `Another phone` has no card: its four values sit in one
/// group, with no caption, and one platform is enough to show the group.
///
/// Fonts, the app theme and the 375 x 667 reference size come from `golden_support.dart`
/// (`loadAppFonts`, `goldenApp`, `goldenReferenceSize`); see its doc comment for why.
/// `devicePixelRatio` stays fixed at 1.0.
library;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoListTile;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/models/messages/device_list_entry.dart';
import 'package:herdr_mobile/models/messages/platform.dart' as wire;
import 'package:herdr_mobile/screens/device_detail_screen.dart';
import 'package:herdr_mobile/services/device_list.dart'
    show formatPairedFull, parseWireTimestamp;
import 'package:herdr_mobile/widgets/app_list_row.dart';
import 'package:herdr_mobile/widgets/key_label.dart' show InlineKey;
import 'package:herdr_mobile/widgets/theme/chrome_list_row.dart';
import 'package:herdr_mobile/widgets/theme/chrome_settings_section.dart';
import 'package:material_symbols_icons/symbols.dart' show Symbols;

import 'golden_support.dart';

final _thisPhone = DeviceListEntry(
  id: 'device-1',
  name: 'Pixel 8',
  pairedAt: '2026-08-24T09:14:00Z',
  lastSeen: DateTime.now().toUtc().toIso8601String(),
  connected: true,
  platform: wire.Platform.android,
  fingerprint: '3f9a-1c04-be77-20d5',
);

/// A second phone, seen three minutes ago, the mockup's own `iPhone 15` row.
final _otherPhone = DeviceListEntry(
  id: 'device-2',
  name: 'iPhone 15',
  pairedAt: '2026-08-22T17:02:00Z',
  lastSeen: DateTime.now()
      .toUtc()
      .subtract(const Duration(minutes: 3))
      .toIso8601String(),
  connected: false,
  platform: wire.Platform.ios,
  fingerprint: '7b2e-90af-13c8-d4e1',
);

const _themes = <(String, Brightness)>[
  ('dark', Brightness.dark),
  ('light', Brightness.light),
];

/// The two platforms a golden renders on: the file suffix and the platform override, `null`
/// for the test host's default, Android.
const _platforms = <(String, TargetPlatform?)>[
  ('', null),
  ('_ios', TargetPlatform.iOS),
];

void main() {
  setUpAll(loadAppFonts);

  Future<void> pumpDetail(
    WidgetTester tester, {
    required Brightness brightness,
    required TargetPlatform? platform,
    required DeviceListEntry device,
    required bool isThisPhone,
  }) async {
    debugDefaultTargetPlatformOverride = platform;
    // A failed expect below must not leak the override into the next test; the binding
    // checks the variable before the tear-downs run, so the body resets it too.
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = goldenReferenceSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      goldenApp(
        brightness: brightness,
        child: DeviceDetailScreen(
          device: device,
          isThisPhone: isThisPhone,
          appLockEnabled: true,
          canRemove: true,
          onRemove: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final (platformSuffix, platform) in _platforms) {
    for (final (themeName, brightness) in _themes) {
      testWidgets(
        'this phone ($themeName$platformSuffix) matches docs/31-mockups/14-devices.md',
        (tester) async {
          await pumpDetail(
            tester,
            brightness: brightness,
            platform: platform,
            device: _thisPhone,
            isThisPhone: true,
          );

          // Structural proof alongside the visual one: every one of R-31-14-08's six values is
          // really present in the tree, once (R-03-058), with the health card of R-03-113
          // item 6 carrying the two times, the lock state and the revocation path.
          expect(find.text('Pixel 8'), findsOneWidget);
          expect(find.text('HEALTH'), findsOneWidget);
          expect(find.text('Last connected'), findsOneWidget);
          expect(find.text('now'), findsOneWidget);
          expect(find.text('App Lock'), findsOneWidget);
          expect(find.text('On'), findsOneWidget);
          expect(find.text('Pairing'), findsOneWidget);
          expect(
            find.text(
              'Paired ${formatPairedFull(parseWireTimestamp(_thisPhone.pairedAt))}',
            ),
            findsOneWidget,
          );
          expect(find.textContaining('How to revoke'), findsOneWidget);
          expect(
            find.byType(InlineKey),
            findsOneWidget,
            reason: 'the r key is a cap (R-32-599)',
          );
          expect(find.text('Paired'), findsNothing);
          expect(find.text('Last seen'), findsNothing);
          expect(find.text('Platform'), findsOneWidget);
          expect(find.text('Android'), findsOneWidget);
          expect(find.text('Key fingerprint'), findsOneWidget);
          expect(find.text('3f9a-1c04-be77-20d5'), findsOneWidget);
          expect(find.text('Rename this phone in Settings.'), findsOneWidget);
          // Every row is the platform row of R-33-073 (R-03-105): three health rows, two value
          // rows and the `Remove` row, whose hue is the glyph alone (R-32-527), and nothing
          // drawn from a box and a gesture. `Close` is gone with the sheet: the back control
          // is the platform's own (R-33-070).
          expect(find.byType(ChromeListRow), findsNWidgets(6));
          expect(find.byIcon(Symbols.delete_outline_rounded), findsOneWidget);
          expect(find.text('Remove'), findsOneWidget);
          expect(find.text('Close'), findsNothing);
          final bool ios = platform == TargetPlatform.iOS;
          expect(
            find.byType(CupertinoListTile),
            ios ? findsNWidgets(6) : findsNothing,
          );
          expect(
            find.byType(AppListRow),
            ios ? findsNothing : findsNWidgets(6),
          );
          // R-03-107 (amended): plain ground, three groups, nothing after the last.
          expect(find.byType(ChromeSettingsSection), findsNWidgets(3));

          await expectLater(
            find.byType(DeviceDetailScreen),
            matchesGoldenFile(
              'goldens/device_detail_screen_this_phone$platformSuffix'
              '_$themeName.png',
            ),
          );
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }
  }

  for (final (themeName, brightness) in _themes) {
    testWidgets(
      'another phone ($themeName) matches docs/31-mockups/14-devices.md',
      (tester) async {
        await pumpDetail(
          tester,
          brightness: brightness,
          platform: null,
          device: _otherPhone,
          isThisPhone: false,
        );

        expect(find.text('iPhone 15'), findsOneWidget);
        expect(find.text('Paired'), findsOneWidget);
        expect(
          find.text(formatPairedFull(parseWireTimestamp(_otherPhone.pairedAt))),
          findsOneWidget,
        );
        expect(find.text('Last seen'), findsOneWidget);
        expect(find.text('3m ago'), findsOneWidget);
        expect(find.text('Platform'), findsOneWidget);
        expect(find.text('iOS'), findsOneWidget);
        expect(find.text('Key fingerprint'), findsOneWidget);
        expect(find.text('7b2e-90af-13c8-d4e1'), findsOneWidget);
        expect(find.text('Remove'), findsOneWidget);
        // No health card and no caption on another phone's detail.
        expect(find.text('HEALTH'), findsNothing);
        expect(find.text('App Lock'), findsNothing);
        expect(find.textContaining('How to revoke'), findsNothing);
        expect(find.text('Rename this phone in Settings.'), findsNothing);
        expect(find.byType(ChromeListRow), findsNWidgets(5));
        expect(find.byType(ChromeSettingsSection), findsNWidgets(2));

        await expectLater(
          find.byType(DeviceDetailScreen),
          matchesGoldenFile(
            'goldens/device_detail_screen_other_phone_$themeName.png',
          ),
        );
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
}
