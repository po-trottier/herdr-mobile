/// Golden tests for `DeviceListScreen` (`app/lib/screens/device_list_screen.dart`, `WP-20-a`),
/// one per named row of `docs/31-mockups/14-devices.md`'s `## States` table that this screen
/// paints without a platform dialog on screen (R-90-011): `Default`, `Loading`, `Empty`,
/// `Error`, `Error, no reply`, `Outcome unknown` and `Removing`, plus the two choice surfaces
/// of R-03-111 (2026-09-09): `Choosing, Android`, the Material menu under the `Remove phones`
/// action, and `Choosing, iOS`, the `CupertinoActionSheet`. Each renders in both Selenized
/// dark and light (R-32-012). Since 2026-09-09 (R-03-105) the list is the platform's own: one
/// push row per phone with `This phone` at the trailing edge of this phone's row and no state
/// bar; since R-03-111 the three remove actions are the items of the choice surface, so the
/// list ends with its last phone and the `Empty` state is one row.
///
/// `Confirming, *` is the platform `AlertDialog`/`CupertinoAlertDialog` of
/// `chrome_confirmation_dialog.dart`, drawn with no app token (R-32-547 names it the one modal
/// dialog the app is permitted, styled by the platform, not by `AppColor`/`AppType`), so it adds
/// nothing to a design-token audit and is left out of this file. The two choice surfaces are
/// in: their items carry the `delete_outline` glyph of `treat.destructive` in
/// `color.status.error`, an app token. `Host in use` and `Offline` both print the real
/// wall-clock minute the list was last read (`_buildLoaded`'s own `readAtLabel`), which this
/// file has no way to fix without a clock parameter on the screen itself — a logic change
/// outside this audit's scope — so a golden of either state would be flaky across a minute
/// boundary and is left out too; both states reuse the same `_bannerStrip`/`Treatment.warning`
/// banner and the same per-row `_opacityDim` this file's other states already exercise, so
/// nothing about their own token use goes unseen.
///
/// The connection-fake `_Harness` mirrors `device_list_screen_test.dart`'s own class, per
/// `actions_screen_golden_test.dart`'s precedent: `DeviceListScreen` is stateful and reads its
/// list off a `Stream<Message>`/`Stream<RelayConnectionState>` pair, so it cannot be
/// golden-tested as a pure body the way `lock_screen_golden_test.dart` renders `LockScreenBody`
/// directly.
///
/// Fonts, the app theme and the 375 x 667 reference size come from `golden_support.dart`
/// (`loadAppFonts`, `goldenApp`, `goldenReferenceSize`); see its doc comment for why.
/// `devicePixelRatio` stays fixed at 1.0. A screen state captures `DeviceListScreen`; a choice
/// surface lives in the navigator's overlay above it, so those two capture the `MaterialApp`,
/// as `chrome_confirmation_dialog_test.dart` does for its dialog.
library;

import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart'
    show
        CupertinoActionSheet,
        CupertinoActionSheetAction,
        CupertinoListSection,
        CupertinoListTile;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/models/codes.dart';
import 'package:herdr_mobile/models/message.dart';
import 'package:herdr_mobile/models/messages/device_list.dart';
import 'package:herdr_mobile/models/messages/device_list_entry.dart';
import 'package:herdr_mobile/models/messages/error_message.dart';
import 'package:herdr_mobile/models/messages/platform.dart' as wire;
import 'package:herdr_mobile/screens/device_list_screen.dart';
import 'package:herdr_mobile/services/device_list.dart'
    show deviceListNoReplyText, deviceListReplyTimeout;
import 'package:herdr_mobile/services/relay.dart';
import 'package:herdr_mobile/widgets/theme/chrome_icon_action.dart';
import 'package:herdr_mobile/widgets/theme/chrome_settings_section.dart'
    show ChromeSettingsSection;
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart' show MaterialApp, MenuItemButton;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'golden_support.dart';

/// Mirrors `device_list_screen_test.dart`'s own `_Harness` class.
class _Harness {
  _Harness()
    : messages = StreamController<Message>.broadcast(),
      connectionState = StreamController<RelayConnectionState>.broadcast();

  final StreamController<Message> messages;
  final StreamController<RelayConnectionState> connectionState;
  final List<Message> sent = <Message>[];

  void send(Message message, {String? corr}) => sent.add(message);

  Future<void> deliver(WidgetTester tester, Message message) async {
    messages.add(message);
    await tester.pump();
    await tester.pump();
  }

  Future<void> dispose() async {
    await messages.close();
    await connectionState.close();
  }
}

DeviceListEntry _entry({
  required String id,
  required String name,
  required String pairedAt,
  required Duration lastSeenAge,
  bool connected = false,
  wire.Platform platform = wire.Platform.android,
}) => DeviceListEntry(
  id: id,
  name: name,
  pairedAt: pairedAt,
  lastSeen: DateTime.now().toUtc().subtract(lastSeenAge).toIso8601String(),
  connected: connected,
  platform: platform,
  fingerprint: '3f9a-1c04-be77-20d5',
);

/// Three paired phones with varied last-seen times, mirroring the mockup's own first
/// wireframe: this phone, connected and seen `now`; a second phone seen minutes ago; a third
/// phone, renamed away from its device model, seen weeks ago.
List<DeviceListEntry> _defaultDevices() => <DeviceListEntry>[
  _entry(
    id: 'device-1',
    name: 'Pixel 8',
    pairedAt: '2026-08-24T09:14:00Z',
    lastSeenAge: Duration.zero,
    connected: true,
  ),
  _entry(
    id: 'device-2',
    name: 'iPhone 15',
    pairedAt: '2026-08-22T17:02:00Z',
    lastSeenAge: const Duration(minutes: 3),
    platform: wire.Platform.ios,
  ),
  _entry(
    id: 'device-3',
    name: 'old-pixel',
    pairedAt: '2026-08-02T11:30:00Z',
    lastSeenAge: const Duration(days: 21),
  ),
];

/// This phone alone, the `Empty` row of the states table.
List<DeviceListEntry> _thisPhoneOnly() => <DeviceListEntry>[
  _entry(
    id: 'device-1',
    name: 'Pixel 8',
    pairedAt: '2026-08-24T09:14:00Z',
    lastSeenAge: Duration.zero,
    connected: true,
  ),
];

const _themes = <(String, Brightness)>[
  ('dark', Brightness.dark),
  ('light', Brightness.light),
];

void main() {
  setUpAll(loadAppFonts);

  setUp(() {
    // `DeviceListScreen` reads the App Lock setting through a fresh `AppSettingsService`, and
    // `SharedPreferencesAsync` needs a platform to construct.
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  Future<_Harness> pumpScreen(
    WidgetTester tester,
    Brightness brightness,
  ) async {
    tester.view.physicalSize = goldenReferenceSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final harness = _Harness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      goldenApp(
        brightness: brightness,
        child: DeviceListScreen(
          hostName: 'patrick-desk',
          localDeviceId: 'device-1',
          messages: harness.messages.stream,
          connectionState: harness.connectionState.stream,
          send: harness.send,
        ),
      ),
    );
    return harness;
  }

  /// Opens the `Remove phones` surface, then picks `Remove this phone` and confirms it, so a
  /// revoke of this phone is in flight.
  Future<void> revokeThisPhone(WidgetTester tester) async {
    await tester.tap(find.byType(ChromeIconAction));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove this phone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pump();
  }

  for (final (themeName, brightness) in _themes) {
    testWidgets('default ($themeName) matches docs/31-mockups/14-devices.md', (
      tester,
    ) async {
      final harness = await pumpScreen(tester, brightness);
      await harness.deliver(
        tester,
        Message.deviceList(DeviceList(devices: _defaultDevices())),
      );

      expect(find.text('Phones on patrick-desk'), findsOneWidget);
      expect(find.text('Pixel 8'), findsOneWidget);
      expect(find.text('This phone'), findsOneWidget);
      expect(find.text('THIS PHONE'), findsNothing);
      expect(find.text('iPhone 15'), findsOneWidget);
      expect(find.text('old-pixel'), findsOneWidget);
      expect(find.textContaining('seen now'), findsOneWidget);
      expect(find.textContaining('seen 3m ago'), findsOneWidget);
      expect(find.textContaining('seen 21d ago'), findsOneWidget);
      // R-03-111: the remove actions are behind the one app bar action, not rows.
      expect(find.byTooltip('Remove phones'), findsOneWidget);
      expect(find.byIcon(Symbols.delete_outline_rounded), findsOneWidget);
      expect(find.text('Remove this phone'), findsNothing);
      expect(find.text('Remove other phones'), findsNothing);
      expect(find.text('Remove every phone'), findsNothing);
      // R-03-107 (amended): plain ground, the phones as the one section, nothing after it.
      expect(find.byType(ChromeSettingsSection), findsOneWidget);

      await expectLater(
        find.byType(DeviceListScreen),
        matchesGoldenFile('goldens/device_list_screen_default_$themeName.png'),
      );
    });

    // The same `Default` state on iOS (R-03-105, R-33-073): the phones as `CupertinoListTile`s
    // inside one inset-grouped `CupertinoListSection`, the push chevron on every phone row,
    // `This phone` in the tile's own secondary slot before the chevron, no state bar, and the
    // `Remove phones` action at the bar's trailing edge (R-03-111, R-33-076).
    testWidgets(
      'default ($themeName, iOS) matches docs/31-mockups/14-devices.md',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        // A failed expect below must not leak the override into the next test; the binding
        // checks the variable before the tear-downs run, so the body resets it too.
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final harness = await pumpScreen(tester, brightness);
        await harness.deliver(
          tester,
          Message.deviceList(DeviceList(devices: _defaultDevices())),
        );

        expect(find.byType(CupertinoListTile), findsNWidgets(3));
        expect(find.byType(CupertinoListSection), findsOneWidget);
        expect(find.byIcon(Symbols.chevron_right_rounded), findsNWidgets(3));
        expect(find.text('This phone'), findsOneWidget);
        expect(find.byType(ChromeIconAction), findsOneWidget);

        await expectLater(
          find.byType(DeviceListScreen),
          matchesGoldenFile(
            'goldens/device_list_screen_default_ios_$themeName.png',
          ),
        );
        debugDefaultTargetPlatformOverride = null;
      },
    );

    // `Choosing, Android` (R-03-111): the Material menu under the `Remove phones` action,
    // three `MenuItemButton`s each leading the `delete_outline` glyph of `treat.destructive`.
    testWidgets(
      'choosing ($themeName, Android menu) matches docs/31-mockups/14-devices.md',
      (tester) async {
        final harness = await pumpScreen(tester, brightness);
        await harness.deliver(
          tester,
          Message.deviceList(DeviceList(devices: _defaultDevices())),
        );

        await tester.tap(find.byType(ChromeIconAction));
        await tester.pumpAndSettle();

        expect(find.byType(MenuItemButton), findsNWidgets(3));
        expect(find.byIcon(Symbols.delete_outline_rounded), findsNWidgets(4));
        expect(find.text('Remove this phone'), findsOneWidget);
        expect(find.text('Remove other phones'), findsOneWidget);
        expect(find.text('Remove every phone'), findsOneWidget);

        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/device_list_screen_menu_$themeName.png'),
        );
      },
    );

    // `Choosing, iOS` (R-03-111): the `CupertinoActionSheet`, three destructive actions and
    // the `Cancel` button the platform groups apart, over the dimmed list.
    testWidgets(
      'choosing ($themeName, iOS action sheet) matches docs/31-mockups/14-devices.md',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final harness = await pumpScreen(tester, brightness);
        await harness.deliver(
          tester,
          Message.deviceList(DeviceList(devices: _defaultDevices())),
        );

        await tester.tap(find.byType(ChromeIconAction));
        await tester.pumpAndSettle();

        expect(find.byType(CupertinoActionSheet), findsOneWidget);
        expect(find.byType(CupertinoActionSheetAction), findsNWidgets(4));
        expect(find.text('Cancel'), findsOneWidget);

        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/device_list_screen_sheet_ios_$themeName.png',
          ),
        );
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets('loading ($themeName) matches docs/31-mockups/14-devices.md', (
      tester,
    ) async {
      await pumpScreen(tester, brightness);
      // Past `ChromeLoadingDelay.skeleton`'s 150 ms grace period, per R-30-004.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();

      // The action is present and disabled while the list is unknown (R-03-111).
      expect(
        tester
            .widget<ChromeIconAction>(find.byType(ChromeIconAction))
            .onPressed,
        isNull,
      );

      await expectLater(
        find.byType(DeviceListScreen),
        matchesGoldenFile('goldens/device_list_screen_loading_$themeName.png'),
      );

      // The request this case never answers times out; elapse it so no timer is left pending.
      await tester.pump(deviceListReplyTimeout);
    });

    testWidgets('empty ($themeName) matches docs/31-mockups/14-devices.md', (
      tester,
    ) async {
      final harness = await pumpScreen(tester, brightness);
      await harness.deliver(
        tester,
        Message.deviceList(DeviceList(devices: _thisPhoneOnly())),
      );

      expect(find.text('Pixel 8'), findsOneWidget);
      expect(find.text('This phone'), findsOneWidget);
      expect(
        tester
            .widget<ChromeIconAction>(find.byType(ChromeIconAction))
            .onPressed,
        isNotNull,
        reason: 'Remove this phone and Remove every phone still act (R-03-105)',
      );

      await expectLater(
        find.byType(DeviceListScreen),
        matchesGoldenFile('goldens/device_list_screen_empty_$themeName.png'),
      );
    });

    testWidgets('error ($themeName) matches docs/31-mockups/14-devices.md', (
      tester,
    ) async {
      final harness = await pumpScreen(tester, brightness);
      await harness.deliver(
        tester,
        const Message.error(
          ErrorMessage(
            code: ErrorCode.internalError,
            message: 'boom: connection reset',
            fatal: false,
          ),
        ),
      );

      expect(find.text('Could not read the phone list.'), findsOneWidget);
      expect(find.text('boom: connection reset'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      await expectLater(
        find.byType(DeviceListScreen),
        matchesGoldenFile('goldens/device_list_screen_error_$themeName.png'),
      );
    });

    // Error, no reply (R-31-14-14): the Host never answered `device_list_request`, so after
    // `deviceListReplyTimeout` the skeleton gives way to the same Error block, with the
    // no-reply raw text, and `Try again`. This is the state the live review found missing:
    // the screen used to stay on the skeleton forever.
    testWidgets(
      'error no reply ($themeName) matches docs/31-mockups/14-devices.md',
      (tester) async {
        await pumpScreen(tester, brightness);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(deviceListReplyTimeout);
        await tester.pump();

        expect(find.text('Could not read the phone list.'), findsOneWidget);
        expect(find.text(deviceListNoReplyText), findsOneWidget);
        expect(find.text('Try again'), findsOneWidget);

        await expectLater(
          find.byType(DeviceListScreen),
          matchesGoldenFile(
            'goldens/device_list_screen_error_no_reply_$themeName.png',
          ),
        );
      },
    );

    testWidgets(
      'outcome unknown ($themeName) matches docs/31-mockups/14-devices.md',
      (tester) async {
        final harness = await pumpScreen(tester, brightness);
        await harness.deliver(
          tester,
          Message.deviceList(DeviceList(devices: _defaultDevices())),
        );

        await revokeThisPhone(tester);

        // The link drops before `revoke_result` arrives (R-30-518), then recovers on its own,
        // mirroring a real reconnect: the persistent `_onConnectionState` listener returns
        // `_connection` to `connected`, so only the `Outcome unknown` block shows, with no
        // `Offline`/`Host in use` banner layered under it.
        harness.connectionState.add(const RelayDisconnected());
        await tester.pump();
        harness.connectionState.add(const RelayConnected());
        await tester.pump();

        expect(find.text('This phone did not get an answer.'), findsOneWidget);
        expect(find.text('The change may already be done.'), findsOneWidget);
        expect(find.text('Check now'), findsOneWidget);
        expect(find.text('Offline.'), findsNothing);
        expect(
          tester
              .widget<ChromeIconAction>(find.byType(ChromeIconAction))
              .onPressed,
          isNull,
          reason: 'every revoke control stays disabled (R-31-14-12)',
        );

        await expectLater(
          find.byType(DeviceListScreen),
          matchesGoldenFile(
            'goldens/device_list_screen_outcome_unknown_$themeName.png',
          ),
        );
      },
    );

    testWidgets('removing ($themeName) matches docs/31-mockups/14-devices.md', (
      tester,
    ) async {
      final harness = await pumpScreen(tester, brightness);
      await harness.deliver(
        tester,
        Message.deviceList(DeviceList(devices: _defaultDevices())),
      );

      await revokeThisPhone(tester);

      expect(find.text('removing'), findsOneWidget);

      await expectLater(
        find.byType(DeviceListScreen),
        matchesGoldenFile('goldens/device_list_screen_removing_$themeName.png'),
      );

      // The revoke this case never answers times out; elapse it so no timer is left pending.
      await tester.pump(deviceListReplyTimeout);
    });
  }
}
