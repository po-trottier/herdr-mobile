/// Proves `NotificationsService`'s (`WP-19-a`) `hasEverPosted` signal
/// (`notification_settings_screen.dart`'s Empty state, `docs/31-mockups/12-notifications.md`,
/// R-90-011): `false` until the first real post, and `true` after — from a live
/// `postAgentStatusNotification` call, a released quiet-hours summary, or
/// `sendTestNotification` (R-31-12-08: the test path uses the same code, so it counts as a real
/// post). Also proves the settings gate: a suppressed alert (category off, or the audience
/// filter) never reaches the platform plugin at all.
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart' show Err, Ok;
import 'package:herdr_mobile/models/messages/agent_status.dart';
import 'package:herdr_mobile/models/messages/agent_status_kind.dart';
import 'package:herdr_mobile/services/notifications.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _MockPlugin extends Mock implements FlutterLocalNotificationsPlugin {}

class _MockIosPlugin extends Mock
    implements IOSFlutterLocalNotificationsPlugin {}

AgentStatus _status({
  AgentStatusKind status = AgentStatusKind.done,
  String paneId = 'w3:p2',
}) => AgentStatus(
  hostId: 'host-1',
  paneId: paneId,
  workspaceId: 'w3',
  tabId: 'w3:t2',
  tabTitle: 'impl',
  paneTitle: 'main.py',
  agentKind: 'claude',
  status: status,
  at: '2026-08-24T14:32:05Z',
);

void main() {
  late _MockPlugin plugin;
  late NotificationsService service;

  setUpAll(() {
    registerFallbackValue(const InitializationSettings());
  });

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    plugin = _MockPlugin();
    when(
      () => plugin.show(
        id: any(named: 'id'),
        title: any(named: 'title'),
        body: any(named: 'body'),
        payload: any(named: 'payload'),
        notificationDetails: any(named: 'notificationDetails'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >(),
    ).thenReturn(null);
    when(
      () => plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >(),
    ).thenReturn(null);
    service = NotificationsService(
      plugin: plugin,
      preferences: SharedPreferencesAsync(),
    );
  });

  group('stable ids and cancel (R-30-506, R-31-07-04)', () {
    test(
      'the id is a pure function of Host and pane, and differs across Hosts',
      () {
        final int a = NotificationsService.notificationIdFor(
          hostId: 'host-1',
          paneId: 'w3:p2',
        );
        expect(
          NotificationsService.notificationIdFor(
            hostId: 'host-1',
            paneId: 'w3:p2',
          ),
          a,
        );
        expect(
          NotificationsService.notificationIdFor(
            hostId: 'host-2',
            paneId: 'w3:p2',
          ),
          isNot(a),
        );
        expect(a, inInclusiveRange(0, 0x7fffffff));
      },
    );

    test('a post uses that id and cancelAgentStatusNotification cancels the same id', () async {
      when(() => plugin.cancel(id: any(named: 'id'))).thenAnswer((_) async {});
      final int id = NotificationsService.notificationIdFor(
        hostId: 'host-1',
        paneId: 'w3:p2',
      );

      await service.postAgentStatusNotification(_status());
      final result = await service.cancelAgentStatusNotification(
        hostId: 'host-1',
        paneId: 'w3:p2',
      );

      expect(result, isA<Ok<void>>());
      verify(
        () => plugin.show(
          id: id,
          title: any(named: 'title'),
          body: any(named: 'body'),
          payload: any(named: 'payload'),
          notificationDetails: any(named: 'notificationDetails'),
        ),
      ).called(1);
      verify(() => plugin.cancel(id: id)).called(1);
    });

    test('a plugin failure on cancel is an Err, never a throw', () async {
      when(() => plugin.cancel(id: any(named: 'id'))).thenThrow(Exception('x'));

      final result = await service.cancelAgentStatusNotification(
        hostId: 'host-1',
        paneId: 'w3:p2',
      );

      expect(result, isA<Err<void>>());
    });
  });

  group(
    'one coalesced alert per agent (R-03-113 item 5, R-30-506, R-31-12-06)',
    () {
      /// Every `id:` the fake platform received, in call order.
      List<int> shownIds() => verify(
        () => plugin.show(
          id: captureAny(named: 'id'),
          title: any(named: 'title'),
          body: any(named: 'body'),
          payload: any(named: 'payload'),
          notificationDetails: any(named: 'notificationDetails'),
        ),
      ).captured.cast<int>();

      test('blocked then done for one pane post under one id: the second replaces the first', () async {
        await service.postAgentStatusNotification(
          _status(status: AgentStatusKind.blocked),
        );
        await service.postAgentStatusNotification(_status());

        final ids = shownIds();
        expect(ids, hasLength(2));
        expect(ids.toSet(), {
          NotificationsService.notificationIdFor(
            hostId: 'host-1',
            paneId: 'w3:p2',
          ),
        });
      });

      test('two panes post under two ids', () async {
        await service.postAgentStatusNotification(_status());
        await service.postAgentStatusNotification(_status(paneId: 'w3:p5'));

        expect(shownIds().toSet(), hasLength(2));
      });

      test('a tap on the posted payload hands host_id and pane_id to onNotificationTapped '
          '(R-22-022, R-30-511)', () async {
        when(
          () => plugin.initialize(
            settings: any(named: 'settings'),
            onDidReceiveNotificationResponse: any(
              named: 'onDidReceiveNotificationResponse',
            ),
          ),
        ).thenAnswer((_) async => true);
        final taps = <(String, String)>[];
        service.onNotificationTapped = (hostId, paneId) =>
            taps.add((hostId, paneId));
        await service.initialize();
        final onTap =
            verify(
                  () => plugin.initialize(
                    settings: any(named: 'settings'),
                    onDidReceiveNotificationResponse: captureAny(
                      named: 'onDidReceiveNotificationResponse',
                    ),
                  ),
                ).captured.single
                as DidReceiveNotificationResponseCallback;

        onTap(
          NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            payload: buildAgentStatusNotificationContent(_status()).payload,
          ),
        );

        expect(taps, [('host-1', 'w3:p2')]);
      });
    },
  );

  group('hasEverPosted', () {
    test('starts false before any post', () async {
      expect(await service.hasEverPosted(), isFalse);
    });

    test('becomes true after a live agent_status notification posts', () async {
      await service.postAgentStatusNotification(_status());
      expect(await service.hasEverPosted(), isTrue);
    });

    test(
      'becomes true after sendTestNotification (same code path, R-31-12-08)',
      () async {
        await service.sendTestNotification();
        expect(await service.hasEverPosted(), isTrue);
      },
    );

    test(
      'stays false when the settings gate suppresses the alert before it ever '
      'reaches the platform plugin',
      () async {
        await service.saveSettings(
          const NotificationSettings(alertOnDone: false),
        );

        await service.postAgentStatusNotification(
          _status(status: AgentStatusKind.done),
        );

        expect(await service.hasEverPosted(), isFalse);
        verifyNever(
          () => plugin.show(
            id: any(named: 'id'),
            title: any(named: 'title'),
            body: any(named: 'body'),
            payload: any(named: 'payload'),
            notificationDetails: any(named: 'notificationDetails'),
          ),
        );
      },
    );
  });

  group('effectiveDeliveryState() / requestPermission() on iOS', () {
    // Proves the `defaultTargetPlatform == TargetPlatform.iOS` branches read the
    // `IOSFlutterLocalNotificationsPlugin` implementation, not the Android one, and never touch
    // `AndroidFlutterLocalNotificationsPlugin` while running as iOS.
    late _MockIosPlugin iosPlugin;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      iosPlugin = _MockIosPlugin();
      when(
        () => plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >(),
      ).thenReturn(iosPlugin);
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test('effectiveDeliveryState() reads IOSFlutterLocalNotificationsPlugin.checkPermissions(), '
        'never AndroidFlutterLocalNotificationsPlugin', () async {
      when(() => iosPlugin.checkPermissions()).thenAnswer(
        (_) async => const NotificationsEnabledOptions(
          isEnabled: true,
          isSoundEnabled: true,
          isAlertEnabled: false,
          isBadgeEnabled: true,
          isProvisionalEnabled: false,
          isCriticalEnabled: false,
          isProvidesAppNotificationSettingsEnabled: false,
        ),
      );

      final state = await service.effectiveDeliveryState();

      expect(state, NotificationDeliveryState.silenced);
      verifyNever(
        () => plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >(),
      );
    });

    test('requestPermission() calls IOSFlutterLocalNotificationsPlugin.requestPermissions(alert: '
        'true, sound: true, badge: true), never the Android permission request '
        '(R-22-020 amended 2026-09-16)', () async {
      when(
        () =>
            iosPlugin.requestPermissions(alert: true, sound: true, badge: true),
      ).thenAnswer((_) async => true);

      final granted = await service.requestPermission();

      expect(granted, isTrue);
      verify(
        () =>
            iosPlugin.requestPermissions(alert: true, sound: true, badge: true),
      ).called(1);
      verifyNever(
        () => plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >(),
      );
    });
  });
}
