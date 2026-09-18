/// Smoke-tests `DeviceListScreen` (`WP-20-a`) against `docs/31-mockups/14-devices.md`: the
/// platform rows of R-03-105 (one `ChromeListRow` per phone, `This phone` on this phone's
/// row, no state bar), the one `Remove phones` app bar action of R-03-111 and the platform
/// menu it opens (a Material `MenuAnchor` on Android, a `CupertinoMenuAnchor` on iOS), the
/// confirmation dialogs' exact wording (R-31-14-01), the `Remove other phones` sequence (one
/// `revoke_device` per other phone, never this one, stopped by a refusal), the `Error` state's
/// `Try again`, and the pushed Device detail screen: its six values (R-31-14-08) and, on this
/// phone's own detail, the health card of R-03-113 item 6.
library;

import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart'
    show
        CupertinoActivityIndicator,
        CupertinoAlertDialog,
        CupertinoMenuItem,
        CupertinoNavigationBar;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart' show AppBar;
import 'package:flutter/widgets.dart'
    show CustomScrollView, Icon, SizedBox, SliverPadding;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart';
import 'package:herdr_mobile/models/codes.dart';
import 'package:herdr_mobile/models/message.dart';
import 'package:herdr_mobile/models/messages/device_list.dart';
import 'package:herdr_mobile/models/messages/device_list_entry.dart';
import 'package:herdr_mobile/models/messages/error_message.dart';
import 'package:herdr_mobile/models/messages/platform.dart' as wire;
import 'package:herdr_mobile/models/messages/revoke_result.dart';
import 'package:herdr_mobile/screens/device_detail_screen.dart';
import 'package:herdr_mobile/screens/device_list_screen.dart';
import 'package:herdr_mobile/services/device_list.dart'
    show
        deviceListNoReplyText,
        deviceListReplyTimeout,
        formatPairedFull,
        formatPairedShort,
        parseWireTimestamp;
import 'package:herdr_mobile/services/relay.dart';
import 'package:herdr_mobile/widgets/status_bar.dart' show StatusBar;
import 'package:herdr_mobile/widgets/theme/chrome_icon_action.dart';
import 'package:herdr_mobile/widgets/theme/chrome_list_row.dart';
import 'package:herdr_mobile/widgets/theme/chrome_settings_section.dart';
import 'package:material_ui/material_ui.dart'
    show CircularProgressIndicator, MaterialApp, MenuItemButton;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

DeviceListEntry _entry({
  required String id,
  required String name,
  bool connected = false,
  wire.Platform platform = wire.Platform.android,
  String? lastSeen,
}) => DeviceListEntry(
  id: id,
  name: name,
  pairedAt: '2026-08-24T09:14:00Z',
  lastSeen: lastSeen ?? DateTime.now().toUtc().toIso8601String(),
  connected: connected,
  platform: platform,
  fingerprint: '3f9a-1c04-be77-20d5',
);

/// An ISO-8601 UTC stamp [age] behind the wall clock.
String _seenAgo(Duration age) =>
    DateTime.now().toUtc().subtract(age).toIso8601String();

/// This phone plus two others, the shape of the mockup's first wireframe.
List<DeviceListEntry> _threePhones() => <DeviceListEntry>[
  _entry(id: 'device-1', name: 'Pixel 8', connected: true),
  _entry(id: 'device-2', name: 'iPhone 15', platform: wire.Platform.ios),
  _entry(id: 'device-3', name: 'old-pixel'),
];

/// This phone alone, the `Empty` row of the mockup's states table.
List<DeviceListEntry> _thisPhoneOnly() => <DeviceListEntry>[
  _entry(id: 'device-1', name: 'Pixel 8', connected: true),
];

class _Harness {
  _Harness()
    : messages = StreamController<Message>.broadcast(),
      connectionState = StreamController<RelayConnectionState>.broadcast();

  final StreamController<Message> messages;
  final StreamController<RelayConnectionState> connectionState;
  final List<Message> sent = <Message>[];

  void send(Message message, {String? corr}) => sent.add(message);

  /// Delivers [message] on the fake wire, then pumps to render the resulting `setState`.
  Future<void> deliver(WidgetTester tester, Message message) async {
    messages.add(message);
    await tester.pump();
    await tester.pump();
  }

  Future<void> dispose() async {
    await messages.close();
    await connectionState.close();
  }

  /// Every `device_id` sent in a `revoke_device` so far, in wire order.
  List<String?> get revokedIds => sent
      .whereType<MessageRevokeDevice>()
      .map((m) => m.payload.deviceId)
      .toList();
}

Future<_Harness> _pumpScreen(
  WidgetTester tester, {
  void Function()? onRemovedThisPhone,
  Future<Result<void>> Function()? reauthenticate,
}) async {
  final harness = _Harness();
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: DeviceListScreen(
        hostName: 'patrick-desk',
        localDeviceId: 'device-1',
        messages: harness.messages.stream,
        connectionState: harness.connectionState.stream,
        send: harness.send,
        // Existing fixtures model App Lock off; security cases inject their own gate.
        reauthenticate: reauthenticate ?? () async => const Ok(null),
        onRemovedThisPhone: onRemovedThisPhone,
      ),
    ),
  );
  return harness;
}

/// Pumps the screen and delivers [devices] as its first `device_list`.
Future<_Harness> _pumpLoaded(
  WidgetTester tester,
  List<DeviceListEntry> devices, {
  void Function()? onRemovedThisPhone,
  Future<Result<void>> Function()? reauthenticate,
}) async {
  final harness = await _pumpScreen(
    tester,
    onRemovedThisPhone: onRemovedThisPhone,
    reauthenticate: reauthenticate,
  );
  await harness.deliver(
    tester,
    Message.deviceList(DeviceList(devices: devices)),
  );
  return harness;
}

/// The one `Remove phones` action of the app bar (R-03-111).
ChromeIconAction _removeAction(WidgetTester tester) =>
    tester.widget<ChromeIconAction>(find.byType(ChromeIconAction));

/// Opens the choice surface behind `Remove phones` and settles its animation.
Future<void> _openRemove(WidgetTester tester) async {
  await tester.tap(find.byType(ChromeIconAction));
  await tester.pumpAndSettle();
}

/// Opens the surface, then picks [title] and settles, so its confirmation is on screen.
Future<void> _pickRemove(WidgetTester tester, String title) async {
  await _openRemove(tester);
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

/// The Android menu item titled [title].
MenuItemButton _menuItem(WidgetTester tester, String title) =>
    tester.widget<MenuItemButton>(find.widgetWithText(MenuItemButton, title));

/// Pins the platform to iOS for one test and resets it afterwards. A failed expect must not
/// leak the override into the next test; the binding checks the variable before the
/// tear-downs run, so the body resets it too.
void _useIos() {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
}

void main() {
  setUp(() {
    // `DeviceListScreen` reads the App Lock setting through a fresh `AppSettingsService` when
    // none is passed, and `SharedPreferencesAsync` needs a platform to construct.
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  for (final action in <(String, String)>[
    ('Remove this phone', 'Remove'),
    ('Remove other phones', 'Remove other phones'),
    ('Remove every phone', 'Remove every phone'),
  ]) {
    testWidgets(
      '${action.$1} sends nothing while authentication is pending or cancelled',
      (tester) async {
        final authentication = Completer<Result<void>>();
        var attempts = 0;
        final harness = await _pumpLoaded(
          tester,
          _threePhones(),
          reauthenticate: () {
            attempts++;
            return authentication.future;
          },
        );
        await _pickRemove(tester, action.$1);
        expect(attempts, 0, reason: 'confirm the action before asking the OS');
        await tester.tap(find.text(action.$2));
        await tester.pump();
        expect(attempts, 1);
        expect(harness.revokedIds, isEmpty);
        expect(_removeAction(tester).onPressed, isNull);

        authentication.complete(const Err('authentication cancelled'));
        await tester.pumpAndSettle();
        expect(harness.revokedIds, isEmpty);
        expect(_removeAction(tester).onPressed, isNotNull);

        await _pickRemove(tester, action.$1);
        await tester.tap(find.text(action.$2));
        await tester.pumpAndSettle();
        expect(attempts, 2, reason: 'another removal must authenticate again');
        expect(harness.revokedIds, isEmpty);
      },
    );
  }

  testWidgets(
    'a successful fresh authentication permits the confirmed removal',
    (tester) async {
      final authentication = Completer<Result<void>>();
      final harness = await _pumpLoaded(
        tester,
        _threePhones(),
        reauthenticate: () => authentication.future,
      );
      await _pickRemove(tester, 'Remove this phone');
      await tester.tap(find.text('Remove'));
      await tester.pump();
      expect(harness.revokedIds, isEmpty);

      authentication.complete(const Ok(null));
      await tester.pump();
      expect(harness.revokedIds, ['device-1']);
      await harness.deliver(
        tester,
        const Message.revokeResult(
          RevokeResult(revoked: ['device-1'], all: false),
        ),
      );
    },
  );

  testWidgets(
    'authentication completing after the screen closes sends no removal',
    (tester) async {
      final authentication = Completer<Result<void>>();
      final harness = await _pumpLoaded(
        tester,
        _threePhones(),
        reauthenticate: () => authentication.future,
      );
      await _pickRemove(tester, 'Remove this phone');
      await tester.tap(find.text('Remove'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());

      authentication.complete(const Ok(null));
      await tester.pump();
      expect(harness.revokedIds, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a disconnect during authentication prevents removal', (
    tester,
  ) async {
    final authentication = Completer<Result<void>>();
    final harness = await _pumpLoaded(
      tester,
      _threePhones(),
      reauthenticate: () => authentication.future,
    );
    await _pickRemove(tester, 'Remove this phone');
    await tester.tap(find.text('Remove'));
    await tester.pump();
    harness.connectionState.add(const RelayDisconnected());
    await tester.pump();

    authentication.complete(const Ok(null));
    await tester.pumpAndSettle();
    expect(harness.revokedIds, isEmpty);
    expect(_removeAction(tester).onPressed, isNull);
  });

  testWidgets('iOS: renders CupertinoNavigationBar with the phones-on-host title and the Remove '
      'phones action, not a Material AppBar', (WidgetTester tester) async {
    _useIos();
    await _pumpScreen(tester);
    await tester.pump();

    expect(find.byType(CupertinoNavigationBar), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Phones on patrick-desk'), findsOneWidget);
    expect(find.byType(ChromeIconAction), findsOneWidget);
    expect(
      _removeAction(tester).onPressed,
      isNull,
      reason: 'the list is still unknown, so removing from it is a guess',
    );

    // The request this test never answers times out; elapse it so no timer is left pending.
    await tester.pump(deviceListReplyTimeout);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('draws one platform row per phone with This phone on this phone alone, no chip, no state '
      'bar and no remove row; the one Remove phones action sits in the app bar (R-03-105, '
      'R-03-111)', (WidgetTester tester) async {
    await _pumpLoaded(tester, _threePhones());

    expect(find.text('Phones on patrick-desk'), findsOneWidget);
    expect(find.byType(ChromeListRow), findsNWidgets(3));
    expect(find.text('Pixel 8'), findsOneWidget);
    expect(find.text('iPhone 15'), findsOneWidget);
    expect(find.text('old-pixel'), findsOneWidget);
    expect(find.text('This phone'), findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(ChromeListRow, 'Pixel 8'),
        matching: find.text('This phone'),
      ),
      findsOneWidget,
      reason: 'the mark sits on this phone\'s own row',
    );
    expect(find.text('THIS PHONE'), findsNothing, reason: 'no chip');
    expect(find.text('Details'), findsNothing, reason: 'no labelled control');
    expect(find.byType(StatusBar), findsNothing, reason: 'no state bar');
    expect(find.text('Remove this phone'), findsNothing);
    expect(find.text('Remove other phones'), findsNothing);
    expect(find.text('Remove every phone'), findsNothing);
    expect(
      find.textContaining('Relay pane'),
      findsNothing,
      reason: 'no footnote',
    );

    expect(find.byTooltip('Remove phones'), findsOneWidget);
    expect(_removeAction(tester).onPressed, isNotNull);
  });

  testWidgets('the body is plain ground: the phones are the one section and the list ends with its '
      'last phone (R-03-107, R-03-109)', (WidgetTester tester) async {
    await _pumpLoaded(tester, _threePhones());

    expect(find.byType(ChromeSettingsSection), findsOneWidget);
    final CustomScrollView list = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView),
    );
    expect(list.slivers, hasLength(1));
    expect(list.slivers.single, isA<SliverPadding>());
  });

  testWidgets(
    'Android: Remove phones opens a Material menu of three destructive items; with only this '
    'phone paired, Remove other phones is disabled and the other two stay enabled (R-03-111)',
    (WidgetTester tester) async {
      await _pumpLoaded(tester, _thisPhoneOnly());

      await _openRemove(tester);

      expect(find.byType(MenuItemButton), findsNWidgets(3));
      expect(_menuItem(tester, 'Remove this phone').onPressed, isNotNull);
      expect(
        _menuItem(tester, 'Remove other phones').onPressed,
        isNull,
        reason: 'no other phone exists (R-03-105)',
      );
      expect(_menuItem(tester, 'Remove every phone').onPressed, isNotNull);
      for (final MenuItemButton item in tester.widgetList<MenuItemButton>(
        find.byType(MenuItemButton),
      )) {
        expect(item.leadingIcon, isNotNull, reason: 'the destructive glyph');
      }
      expect(
        tester.getSemantics(
          find.widgetWithText(MenuItemButton, 'Remove other phones'),
        ),
        isSemantics(
          label: 'Remove other phones',
          hint: 'destructive',
          isEnabled: false,
        ),
      );
    },
  );

  testWidgets(
    'Android: each menu item opens its own confirmation with the exact copy; Remove every '
    'phone ends with the sentence about the r key (R-31-14-01, R-03-111)',
    (WidgetTester tester) async {
      await _pumpLoaded(tester, _threePhones());

      await _pickRemove(tester, 'Remove this phone');
      expect(find.text('Remove this phone from patrick-desk?'), findsOneWidget);
      expect(
        find.text('You will have to pair again to reach this computer.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNothing, reason: 'menu closed');

      await _pickRemove(tester, 'Remove other phones');
      expect(
        find.text('Remove 2 other phones from patrick-desk?'),
        findsOneWidget,
      );
      expect(
        find.text('They pair again. This phone keeps access.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await _pickRemove(tester, 'Remove every phone');
      expect(
        find.text('Remove every phone from patrick-desk?'),
        findsOneWidget,
      );
      // The body is one `keyedText`, so the `r` is a cap, not a word: match the prose around it.
      expect(
        find.textContaining(
          'This phone and 2 other phones lose access at once. Everyone pairs '
          'again. Removing every phone is the same as the ',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(' key in the Relay pane on your computer.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'This phone and 2 other phones lose access at once. Everyone pairs '
          'again. Removing every phone is the same as the r key in the Relay '
          'pane on your computer.',
        ),
        findsOneWidget,
        reason: 'a screen reader gets the plain sentence',
      );
    },
  );

  testWidgets(
    'offline: the Remove phones action is disabled and the list dims (R-31-14-04)',
    (WidgetTester tester) async {
      final harness = await _pumpLoaded(tester, _threePhones());
      // One pump delivers the stream event, the next renders its `setState`.
      harness.connectionState.add(const RelayDisconnected());
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Offline. This list is from'), findsOneWidget);
      expect(_removeAction(tester).onPressed, isNull);

      harness.connectionState.add(const RelayConnected());
      await tester.pump();
      await tester.pump();
      expect(_removeAction(tester).onPressed, isNotNull);
    },
  );

  testWidgets('iOS: Remove phones opens a CupertinoMenuAnchor menu of three destructive items with a '
      'trailing glyph; picking Remove every phone opens its confirmation over the list '
      '(R-03-111, R-33-033)', (WidgetTester tester) async {
    _useIos();
    await _pumpLoaded(tester, _threePhones());

    await _openRemove(tester);

    final List<CupertinoMenuItem> items = tester
        .widgetList<CupertinoMenuItem>(find.byType(CupertinoMenuItem))
        .toList();
    expect(items, hasLength(3));
    expect(items.every((CupertinoMenuItem i) => i.isDestructiveAction), isTrue);
    expect(
      items.every((CupertinoMenuItem i) => i.trailing is Icon),
      isTrue,
      reason: 'the glyph sits in the trailing slot on iOS',
    );
    expect(find.text('Remove this phone'), findsOneWidget);
    expect(find.text('Remove other phones'), findsOneWidget);
    expect(find.text('Remove every phone'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing, reason: 'a menu has no Cancel');

    await tester.tap(find.text('Remove every phone'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoMenuItem), findsNothing);
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(find.text('Remove every phone from patrick-desk?'), findsOneWidget);
    expect(
      find.textContaining(' key in the Relay pane on your computer.'),
      findsOneWidget,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'iOS with only this phone paired: Remove other phones is disabled in the menu and a tap '
    'on it does nothing; Remove this phone still confirms (R-03-105, R-03-111)',
    (WidgetTester tester) async {
      _useIos();
      await _pumpLoaded(tester, _thisPhoneOnly());

      await _openRemove(tester);

      expect(
        tester
            .widget<CupertinoMenuItem>(
              find.widgetWithText(CupertinoMenuItem, 'Remove other phones'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester.getSemantics(
          find.widgetWithText(CupertinoMenuItem, 'Remove other phones'),
        ),
        isSemantics(hint: 'destructive', isEnabled: false),
      );
      await tester.tap(find.text('Remove other phones'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoMenuItem), findsNWidgets(3));
      expect(find.byType(CupertinoAlertDialog), findsNothing);

      await tester.tap(find.text('Remove this phone'));
      await tester.pumpAndSettle();
      expect(find.text('Remove this phone from patrick-desk?'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('a connected row reads "seen now" even with an old last_seen, a row that is not '
      'connected reads the relative time', (WidgetTester tester) async {
    await _pumpLoaded(tester, <DeviceListEntry>[
      _entry(
        id: 'device-1',
        name: 'Pixel 8',
        connected: true,
        lastSeen: _seenAgo(const Duration(minutes: 4)),
      ),
      _entry(
        id: 'device-2',
        name: 'iPhone 15',
        platform: wire.Platform.ios,
        lastSeen: _seenAgo(const Duration(minutes: 4)),
      ),
    ]);

    final String paired = formatPairedShort(
      parseWireTimestamp('2026-08-24T09:14:00Z'),
    );
    expect(
      find.text('paired $paired \u00b7 seen now'),
      findsOneWidget,
      reason:
          'The connected row reads now regardless of last_seen (the now rows of '
          'docs/31-mockups/14-devices.md, decided 2026-09-03)',
    );
    expect(find.text('paired $paired \u00b7 seen 4m ago'), findsOneWidget);
  });
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      '$platform: Remove this phone: confirms with exact wording, sends revoke_device, reports '
      'onRemovedThisPhone once revoke_result confirms it',
      (WidgetTester tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        bool removed = false;
        final harness = await _pumpLoaded(
          tester,
          _threePhones(),
          onRemovedThisPhone: () => removed = true,
        );

        await _pickRemove(tester, 'Remove this phone');

        expect(
          find.text('Remove this phone from patrick-desk?'),
          findsOneWidget,
        );
        expect(
          find.text('You will have to pair again to reach this computer.'),
          findsOneWidget,
        );

        await tester.tap(find.text('Remove'));
        await tester.pump();
        expect(
          find.byType(
            platform == TargetPlatform.iOS
                ? CupertinoActivityIndicator
                : CircularProgressIndicator,
          ),
          findsOneWidget,
        );
        expect(harness.revokedIds, ['device-1']);
        expect(
          _removeAction(tester).onPressed,
          isNull,
          reason: 'one revoke in flight disables every revoke control (R-31-14-12.1)',
        );

        await harness.deliver(
          tester,
          const Message.revokeResult(
            RevokeResult(revoked: ['device-1'], all: false),
          ),
        );

        expect(removed, isTrue);
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
  testWidgets('Remove other phones: confirms with the exact count and wording, then sends one '
      'revoke_device per other phone in sequence, never for this phone, and each confirmed '
      'row leaves the list', (WidgetTester tester) async {
    final harness = await _pumpLoaded(tester, _threePhones());

    await _pickRemove(tester, 'Remove other phones');

    expect(
      find.text('Remove 2 other phones from patrick-desk?'),
      findsOneWidget,
    );
    expect(
      find.text('They pair again. This phone keeps access.'),
      findsOneWidget,
    );

    // The destructive verb repeats the menu item's title; the menu is closed, so the dialog's
    // copy is the one left.
    await tester.tap(find.text('Remove other phones'));
    await tester.pump();

    expect(harness.revokedIds, [
      'device-2',
    ], reason: 'one revoke in flight at a time (R-31-14-12.1)');
    expect(find.text('removing'), findsNWidgets(2));
    expect(_removeAction(tester).onPressed, isNull);

    await harness.deliver(
      tester,
      const Message.revokeResult(
        RevokeResult(revoked: ['device-2'], all: false),
      ),
    );

    expect(harness.revokedIds, ['device-2', 'device-3']);
    expect(find.text('iPhone 15'), findsNothing);
    expect(find.text('old-pixel'), findsOneWidget);

    await harness.deliver(
      tester,
      const Message.revokeResult(
        RevokeResult(revoked: ['device-3'], all: false),
      ),
    );

    expect(harness.revokedIds, ['device-2', 'device-3']);
    expect(find.text('old-pixel'), findsNothing);
    expect(find.text('Pixel 8'), findsOneWidget);
    expect(find.text('Removed 2 other phones.'), findsOneWidget);
    expect(_removeAction(tester).onPressed, isNotNull);

    await _openRemove(tester);
    expect(
      _menuItem(tester, 'Remove other phones').onPressed,
      isNull,
      reason: 'no other phone is left',
    );
  });

  testWidgets('Remove other phones: a refusal stops the sequence at that phone, shows its raw text, '
      'keeps the rest, and re-enables the action', (WidgetTester tester) async {
    final harness = await _pumpLoaded(tester, <DeviceListEntry>[
      ..._threePhones(),
      _entry(id: 'device-4', name: 'spare'),
    ]);

    await _pickRemove(tester, 'Remove other phones');
    expect(
      find.text('Remove 3 other phones from patrick-desk?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Remove other phones'));
    await tester.pump();

    await harness.deliver(
      tester,
      const Message.revokeResult(
        RevokeResult(revoked: ['device-2'], all: false),
      ),
    );
    await harness.deliver(
      tester,
      const Message.error(
        ErrorMessage(
          code: ErrorCode.internalError,
          message: 'boom: not paired',
          fatal: false,
        ),
      ),
    );

    expect(harness.revokedIds, [
      'device-2',
      'device-3',
    ], reason: 'device-4 is never sent after device-3 was refused');
    expect(find.text('boom: not paired'), findsOneWidget);
    expect(find.text('iPhone 15'), findsNothing);
    expect(find.text('old-pixel'), findsOneWidget);
    expect(find.text('spare'), findsOneWidget);
    expect(find.text('removing'), findsNothing);
    expect(_removeAction(tester).onPressed, isNotNull);
  });

  testWidgets(
    'Remove every phone with only this phone paired confirms without a count of others, still '
    'ending with the r key sentence, and sends revoke_device all',
    (WidgetTester tester) async {
      bool removed = false;
      final harness = await _pumpLoaded(
        tester,
        _thisPhoneOnly(),
        onRemovedThisPhone: () => removed = true,
      );

      await _pickRemove(tester, 'Remove every phone');

      expect(
        find.text('Remove every phone from patrick-desk?'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'This phone loses access. You pair again. Removing every phone is the '
          'same as the ',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('other phone'), findsNothing);

      await tester.tap(find.text('Remove every phone'));
      await tester.pump();

      final MessageRevokeDevice request = harness.sent
          .whereType<MessageRevokeDevice>()
          .single;
      expect(request.payload.all, isTrue);
      expect(request.payload.deviceId, isNull);

      await harness.deliver(
        tester,
        const Message.revokeResult(
          RevokeResult(revoked: ['device-1'], all: true),
        ),
      );
      expect(removed, isTrue);
    },
  );

  testWidgets('tapping another phone\'s row pushes the Device detail screen with the name, pair time, '
      'last seen, platform, fingerprint and one Remove row, no health card, and its '
      'confirmation names that phone', (WidgetTester tester) async {
    await _pumpLoaded(tester, _threePhones());

    await tester.tap(find.text('iPhone 15'));
    await tester.pumpAndSettle();

    expect(find.byType(DeviceDetailScreen), findsOneWidget);
    expect(find.text('Paired'), findsOneWidget);
    expect(find.text('Last seen'), findsOneWidget);
    expect(find.text('Platform'), findsOneWidget);
    expect(find.text('iOS'), findsOneWidget);
    expect(find.text('Key fingerprint'), findsOneWidget);
    expect(find.text('3f9a-1c04-be77-20d5'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
    expect(find.byType(ChromeListRow), findsNWidgets(5));
    expect(
      find.text('Close'),
      findsNothing,
      reason: 'a pushed route, not a sheet',
    );
    expect(
      find.text('Rename this phone in Settings.'),
      findsNothing,
      reason: 'the caption is for this phone alone (R-31-14-05)',
    );
    expect(
      find.text('HEALTH'),
      findsNothing,
      reason: 'the health card is this phone\'s alone (R-03-113 item 6)',
    );
    expect(find.text('App Lock'), findsNothing);
    expect(
      find.text(formatPairedFull(parseWireTimestamp('2026-08-24T09:14:00Z'))),
      findsOneWidget,
      reason: 'the detail uses the full pair-time format, unlike the row',
    );

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(
      find.byType(DeviceDetailScreen),
      findsNothing,
      reason: 'popped first',
    );
    expect(find.text('Remove iPhone 15 from patrick-desk?'), findsOneWidget);
  });

  testWidgets(
    'this phone\'s detail carries the Health card: Last connected, App Lock off from an empty '
    'store, Pairing, the How to revoke caption, and each time once (R-03-113 item 6, R-03-058)',
    (WidgetTester tester) async {
      await _pumpLoaded(tester, _threePhones());

      await tester.tap(find.text('Pixel 8'));
      await tester.pumpAndSettle();

      expect(find.byType(DeviceDetailScreen), findsOneWidget);
      expect(find.text('HEALTH'), findsOneWidget);
      expect(find.text('Last connected'), findsOneWidget);
      expect(find.text('now'), findsOneWidget);
      expect(find.text('App Lock'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
      expect(find.text('Pairing'), findsOneWidget);
      expect(
        find.text(
          'Paired ${formatPairedFull(parseWireTimestamp('2026-08-24T09:14:00Z'))}',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'How to revoke: Remove phones on the phone list removes one phone or '
          'every phone. The r key in the Relay pane on your computer removes '
          'every phone.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Paired'),
        findsNothing,
        reason: 'the pair time shows once',
      );
      expect(
        find.text('Last seen'),
        findsNothing,
        reason: 'the last seen time shows once',
      );
      expect(find.text('Platform'), findsOneWidget);
      expect(find.text('Android'), findsOneWidget);
      expect(find.text('Key fingerprint'), findsOneWidget);
      expect(find.text('Rename this phone in Settings.'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
      // Three health rows, two value rows and `Remove`: every one the platform row.
      expect(find.byType(ChromeListRow), findsNWidgets(6));
      // The Android group merges its static rows into one node; the pair is still one entry.
      expect(find.bySemanticsLabel(RegExp('App Lock, Off')), findsOneWidget);
    },
  );

  testWidgets(
    'the App Lock row reads the persisted setting when no service is passed (R-03-090)',
    (WidgetTester tester) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData(<String, Object>{
            'app_lock_enabled': true,
          });
      await _pumpLoaded(tester, _threePhones());

      await tester.tap(find.text('Pixel 8'));
      await tester.pumpAndSettle();

      expect(find.text('On'), findsOneWidget);
      expect(find.text('Off'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('App Lock, On')), findsOneWidget);
    },
  );

  testWidgets(
    'Error state shows the raw error text and Try again, which re-sends device_list_request; '
    'the Remove phones action is disabled until the list is known',
    (WidgetTester tester) async {
      final harness = await _pumpScreen(tester);
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
      expect(_removeAction(tester).onPressed, isNull);

      final int requestsBefore = harness.sent
          .whereType<MessageDeviceListRequest>()
          .length;
      await tester.tap(find.text('Try again'));
      await tester.pump();

      expect(
        harness.sent.whereType<MessageDeviceListRequest>().length,
        requestsBefore + 1,
      );

      // Reply to the retry too, so no request this test sent is left unanswered when it ends.
      await harness.deliver(
        tester,
        Message.deviceList(DeviceList(devices: _thisPhoneOnly())),
      );
      expect(find.text('Pixel 8'), findsOneWidget);
      expect(_removeAction(tester).onPressed, isNotNull);
    },
  );

  testWidgets(
    'No reply: the skeleton gives way to the Error block with the no-reply text and Try again '
    'after deviceListReplyTimeout, so the screen never hangs (R-31-14-14)',
    (WidgetTester tester) async {
      final harness = await _pumpScreen(tester);
      expect(harness.sent.whereType<MessageDeviceListRequest>(), hasLength(1));

      // Past the 150 ms skeleton grace period (R-30-004), still waiting.
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Could not read the phone list.'), findsNothing);

      await tester.pump(deviceListReplyTimeout);
      await tester.pump();

      expect(find.text('Could not read the phone list.'), findsOneWidget);
      expect(find.text(deviceListNoReplyText), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(
        harness.sent.whereType<MessageDeviceListRequest>(),
        hasLength(1),
        reason: 'the timeout itself never resends; only Try again does',
      );

      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(harness.sent.whereType<MessageDeviceListRequest>(), hasLength(2));

      await harness.deliver(
        tester,
        Message.deviceList(DeviceList(devices: _thisPhoneOnly())),
      );
      expect(find.text('Pixel 8'), findsOneWidget);
    },
  );
}
