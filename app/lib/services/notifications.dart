/// The Device's local-notification platform wrapper (Phase 19, `WP-19-a`), per
/// `docs/22-platform-integration.md` §3 and `docs/30-ux-spec.md` R-30-500 to R-30-517: version 1
/// posts a native local notification only while the app process is alive (R-22-019). The one
/// push element in this product is the content-free wake of R-03-136 (`push_token.dart`, the
/// relay's `push_wake`): a fixed-text push that carries no agent, pane, tab or workspace. This
/// file handles no push payload; the OS shows the wake on its own.
///
/// This file owns every platform call `flutter_local_notifications` 22.3.0 wraps: creating the
/// Android channel `herdr_agent_status` (R-22-020), reading the current authorisation /
/// effective-delivery state (R-22-072, R-31-12-13), requesting the permission once (R-22-021,
/// R-22-071 — the *call*; `WP-18-a`'s agent-list screen owns the *moment*, R-30-509, R-90-024),
/// opening the operating system's own notification settings as the only recovery (R-22-073), and
/// posting the notification itself from `agent_status` fields alone (R-11-057, R-30-505,
/// R-31-12-01) — every human-readable word in it arrived inside the Noise session (R-01-011),
/// because [postAgentStatusNotification] reads no other source. This file also owns the
/// notification-settings persistence and the quiet-hours hold/release behaviour
/// (`docs/31-mockups/12-notifications.md` R-31-12-03) that `notification_settings_screen.dart`
/// (`WP-19-b`) reads and writes through [loadSettings]/[saveSettings].
///
/// This file paints nothing: `docs/31-mockups/12-notifications.md`'s wireframe, its five states
/// and its accessibility notes belong to `WP-19-b`'s screen (R-90-024). It also holds no
/// `go_router`/`BuildContext` import: a notification tap carries no `BuildContext`
/// (`flutter_local_notifications`'s `didReceiveNotificationResponse` gives none), so
/// [onNotificationTapped] is a plain callback hook a composition root (`app.dart`, `WP-12-b`)
/// wires to `routing.dart`'s `routeNotificationTap` once a `NavigatorState` exists.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/painting.dart' show Color;
import 'package:flutter/services.dart'
    show MethodChannel, MissingPluginException, PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/result/result.dart' show Err, Ok, Result;
import '../models/messages/agent_status.dart';
import '../models/messages/agent_status_kind.dart';

/// The one Android notification channel and iOS notification "identity" for the whole product
/// (R-22-020). No other channel exists.
const String notificationChannelId = 'herdr_agent_status';
const String _notificationChannelName = 'Agent status';

/// R-22-063, R-22-064: the small icon copied to `app/android/app/src/main/res/drawable-*/` from
/// `assets/icon/export/android/drawable-*/`. This file references the resource name
/// unconditionally, per R-22-064's requirement on the notification call itself.
const String _androidSmallIcon = 'ic_stat_agent';

/// How often a list redraws its relative ages while it is on screen (R-03-056, decided
/// 2026-09-09 by the product owner: a value true only at the moment the screen opened is a
/// defect). One second, because the age format of `docs/31-mockups/06-agent-list.md` callout 8
/// shows seconds under an hour (`4m 31s`), and a coarser tick would show a second count that is
/// false most of the time. `notifications_screen.dart` and `agent_list_screen.dart` both run one
/// periodic timer on this period and cancel it on dispose. Declared here, not in a widget file,
/// because `no_literals_test.dart` reads a `Duration` literal in a widget as a motion value; this
/// is a clock cadence, not motion, and it is not one of the `motion.duration.*` tokens.
const Duration ageTickPeriod = Duration(seconds: 1);

/// The exact title, body and payload an `agent_status` notification carries (R-30-510,
/// R-31-12-01): the agent kind and status word in the title, the pane title and tab title in the
/// body, and the four routing/deep-navigation ids in the payload alone (never displayed —
/// R-30-505: "MUST NOT name a workspace"). Every word comes from [status]; nothing else. A pure
/// function, with no platform plugin involved, so `no_pane_text_test.dart` can assert this
/// construction directly.
({String title, String body, String payload})
buildAgentStatusNotificationContent(AgentStatus status) {
  final statusWord = switch (status.status) {
    AgentStatusKind.blocked => 'blocked',
    AgentStatusKind.done => 'done',
    _ => status.status.name,
  };
  return (
    title: '${status.agentKind} is $statusWord',
    body: '${status.paneTitle} in ${status.tabTitle}',
    payload: jsonEncode({
      'host_id': status.hostId,
      'pane_id': status.paneId,
      'workspace_id': status.workspaceId,
      'tab_id': status.tabId,
    }),
  );
}

/// The collapsed summary R-31-12-03 requires when quiet hours releases more than one held alert.
/// The tap target is the most recently held pane — see `NotificationsService._release`'s own doc
/// comment for why. A pure function for the same reason [buildAgentStatusNotificationContent] is.
({String title, String body, String payload})
buildHeldSummaryNotificationContent(List<AgentStatus> held) {
  assert(
    held.isNotEmpty,
    'buildHeldSummaryNotificationContent requires at least one item',
  );
  final latest = held.last;
  return (
    title: '${held.length} agents need you',
    body: held.map((s) => s.paneTitle).toSet().join(', '),
    payload: jsonEncode({
      'host_id': latest.hostId,
      'pane_id': latest.paneId,
      'workspace_id': latest.workspaceId,
      'tab_id': latest.tabId,
    }),
  );
}

/// A wall-clock time of day, minute precision. `notifications.dart` is a service and does not
/// import `material_ui`'s time-picker type (R-20-042): `WP-19-b`'s screen converts whatever
/// picker widget it uses to and from this plain value.
final class ClockTime {
  const ClockTime({required this.hour, required this.minute})
    : assert(hour >= 0 && hour <= 23, 'hour out of range'),
      assert(minute >= 0 && minute <= 59, 'minute out of range');

  final int hour;
  final int minute;

  int get _minutesSinceMidnight => hour * 60 + minute;

  @override
  bool operator ==(Object other) =>
      other is ClockTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// The persisted preferences `docs/31-mockups/12-notifications.md` draws
/// (`notification_settings_screen.dart`, `WP-19-b`). Every category defaults on and every
/// suppression defaults off (R-31-12-02, R-31-12-10, R-30-516), so a person who changes nothing
/// receives every alert.
final class NotificationSettings {
  const NotificationSettings({
    this.alertOnBlocked = true,
    this.alertOnDone = true,
    this.audienceOpenedOnly = false,
    this.quietHoursEnabled = false,
    this.quietHoursFrom = const ClockTime(hour: 22, minute: 0),
    this.quietHoursTo = const ClockTime(hour: 7, minute: 30),
  });

  /// `An agent is blocked` (R-31-12-05). Default on (R-31-12-02).
  final bool alertOnBlocked;

  /// `An agent is done` (R-31-12-05). Default on (R-31-12-02).
  final bool alertOnDone;

  /// `Only agents I have opened`, one Boolean (R-31-12-12). Default off: every agent on the
  /// connected computer earns an alert.
  final bool audienceOpenedOnly;

  /// `Hold alerts` (R-31-12-03). Default off.
  final bool quietHoursEnabled;

  final ClockTime quietHoursFrom;
  final ClockTime quietHoursTo;

  NotificationSettings copyWith({
    bool? alertOnBlocked,
    bool? alertOnDone,
    bool? audienceOpenedOnly,
    bool? quietHoursEnabled,
    ClockTime? quietHoursFrom,
    ClockTime? quietHoursTo,
  }) => NotificationSettings(
    alertOnBlocked: alertOnBlocked ?? this.alertOnBlocked,
    alertOnDone: alertOnDone ?? this.alertOnDone,
    audienceOpenedOnly: audienceOpenedOnly ?? this.audienceOpenedOnly,
    quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
    quietHoursFrom: quietHoursFrom ?? this.quietHoursFrom,
    quietHoursTo: quietHoursTo ?? this.quietHoursTo,
  );

  Map<String, Object?> _toJson() => {
    'alert_on_blocked': alertOnBlocked,
    'alert_on_done': alertOnDone,
    'audience_opened_only': audienceOpenedOnly,
    'quiet_hours_enabled': quietHoursEnabled,
    'quiet_hours_from_hour': quietHoursFrom.hour,
    'quiet_hours_from_minute': quietHoursFrom.minute,
    'quiet_hours_to_hour': quietHoursTo.hour,
    'quiet_hours_to_minute': quietHoursTo.minute,
  };

  static NotificationSettings _fromJson(Map<String, Object?> json) =>
      NotificationSettings(
        alertOnBlocked: json['alert_on_blocked'] as bool? ?? true,
        alertOnDone: json['alert_on_done'] as bool? ?? true,
        audienceOpenedOnly: json['audience_opened_only'] as bool? ?? false,
        quietHoursEnabled: json['quiet_hours_enabled'] as bool? ?? false,
        quietHoursFrom: ClockTime(
          hour: json['quiet_hours_from_hour'] as int? ?? 22,
          minute: json['quiet_hours_from_minute'] as int? ?? 0,
        ),
        quietHoursTo: ClockTime(
          hour: json['quiet_hours_to_hour'] as int? ?? 7,
          minute: json['quiet_hours_to_minute'] as int? ?? 30,
        ),
      );
}

/// Whether the platform will actually draw an alert right now (R-22-072, R-31-12-13). A granted
/// permission is not proof: Android permits the channel at `IMPORTANCE_NONE` while
/// `POST_NOTIFICATIONS` stays granted, and iOS permits an authorised app whose alert setting is
/// off. `notification_settings_screen.dart` (`WP-19-b`) MUST read this, not the bare permission
/// flag, per R-31-12-13.
enum NotificationDeliveryState {
  /// The permission is granted and the platform will draw the alert.
  granted,

  /// The permission is granted but the platform will not draw the alert (a silenced Android
  /// channel, or an iOS alert setting turned off).
  silenced,

  /// The permission was refused, or has not been decided yet.
  denied,
}

/// The Device's local-notification service (`docs/22-platform-integration.md` §3). One instance
/// covers the whole app session.
class NotificationsService {
  NotificationsService({
    FlutterLocalNotificationsPlugin? plugin,
    SharedPreferencesAsync? preferences,
    DateTime Function() now = DateTime.now,
    Logger? logger,
    Future<void> Function(int count)? setBadge,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _preferences = preferences ?? SharedPreferencesAsync(),
       // `this._now` would make the external parameter name `_now`, unusable from
       // `notifications_test.dart`, a different library (Dart's named-parameter privacy rule) —
       // same reasoning `biometric_gate.dart`'s `_now` param documents.
       // ignore: prefer_initializing_formals
       _now = now,
       _setBadge = setBadge ?? _nativeSetBadge,
       _log = logger ?? Logger('NotificationsService');

  /// `AppDelegate.swift`'s badge channel (R-22-020): iOS only. Android draws its launcher dot
  /// from the posted notifications themselves and has no app-set count.
  static const MethodChannel _badgeChannel = MethodChannel(
    'dev.herdr.herdr_mobile/badge',
  );

  static Future<void> _nativeSetBadge(int count) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    await _badgeChannel.invokeMethod<void>('set', count);
  }

  final Future<void> Function(int count) _setBadge;
  int? _lastBadge;

  /// R-22-020: the app icon badge shows [count] unread rows; zero clears it. Idempotent per
  /// value, so a caller may pass the count on every emission. A missing channel or a platform
  /// error is logged and swallowed: the badge is a mirror, never the record.
  Future<void> setBadgeCount(int count) async {
    if (count == _lastBadge) return;
    _lastBadge = count;
    try {
      await _setBadge(count);
    } on PlatformException catch (e) {
      _log.warning('set app icon badge', e);
    } on MissingPluginException catch (e) {
      _log.warning('set app icon badge', e);
    }
  }

  final FlutterLocalNotificationsPlugin _plugin;
  final SharedPreferencesAsync _preferences;
  final DateTime Function() _now;
  final Logger _log;

  /// The single Android/iOS notification presentation for every alert this file posts, real or
  /// held-summary (R-22-020's channel, R-22-064's small icon). Constructed once, not per call.
  static const NotificationDetails _notificationDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      notificationChannelId,
      _notificationChannelName,
      icon: _androidSmallIcon,
      importance: Importance.defaultImportance,
      // R-22-065: an explicit accent colour, not the platform default. This file has no
      // `BuildContext` (see the header comment for why) so it cannot read the resolved theme's
      // `AppColor.accentPrimary`; it uses that getter's own dark-branch literal instead, per
      // `docs/32-design-language.md` §3.3's `color.accent.primary` row (R-32-120, R-32-125):
      // Primer `fgColor.accent`, `#4493F8`. The icon (R-32-412) sets the precedent for a
      // value fixed across themes outside the app's own chrome.
      color: Color(0xFF4493F8),
    ),
    iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
  );

  static const _settingsStorageKey = 'notification_settings_v1';
  static const _hasEverPostedStorageKey = 'notification_has_ever_posted_v1';

  NotificationSettings _settings = const NotificationSettings();
  final Set<String> _openedPaneIds = <String>{};
  final List<AgentStatus> _held = <AgentStatus>[];
  Timer? _releaseTimer;

  /// Invoked with the `host_id`/`pane_id` a person tapped a notification for. `null` until a
  /// composition root (`app.dart`, `WP-12-b`) sets it. This file never imports `go_router` or
  /// `BuildContext` itself; see this file's own header comment for why.
  void Function(String hostId, String paneId)? onNotificationTapped;

  /// Creates the Android channel (R-22-020) before any notification is posted, and wires the
  /// plugin's tap callback to [onNotificationTapped]. A caller (a later phase's app root) calls
  /// this once, on app start, before any [postAgentStatusNotification] call.
  Future<Result<void>> initialize() async {
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings(_androidSmallIcon),
        // R-22-021: the app requests the permission itself, once, at the R-30-509 moment — not
        // implicitly here — so every `request*Permission` flag stays false.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
      );
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: _handleResponse,
      );
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.createNotificationChannel(
              const AndroidNotificationChannel(
                notificationChannelId,
                _notificationChannelName,
                importance: Importance.defaultImportance,
              ),
            );
      }
      await loadSettings();
      return const Ok(null);
    } on Exception catch (e) {
      return Err('initialize notifications', cause: e);
    }
  }

  void _handleResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;
    try {
      final decoded = jsonDecode(payload) as Map<String, Object?>;
      final hostId = decoded['host_id'] as String?;
      final paneId = decoded['pane_id'] as String?;
      if (hostId != null && paneId != null) {
        onNotificationTapped?.call(hostId, paneId);
      }
    } on FormatException catch (e) {
      _log.warning('discard malformed notification tap payload', e);
    }
  }

  /// R-22-072, R-31-12-13: the effective delivery state, read on every foreground resume and by
  /// `notification_settings_screen.dart`.
  Future<NotificationDeliveryState> effectiveDeliveryState() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final enabled = await android?.areNotificationsEnabled() ?? false;
      if (!enabled) return NotificationDeliveryState.denied;
      final channels = await android?.getNotificationChannels();
      final channel = channels?.firstWhereOrNull(
        (c) => c.id == notificationChannelId,
      );
      if (channel != null && channel.importance == Importance.none) {
        return NotificationDeliveryState.silenced;
      }
      return NotificationDeliveryState.granted;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final permissions = await ios?.checkPermissions();
      if (permissions == null || !permissions.isEnabled) {
        return NotificationDeliveryState.denied;
      }
      if (!permissions.isAlertEnabled) {
        return NotificationDeliveryState.silenced;
      }
      return NotificationDeliveryState.granted;
    }
    // Every platform this product ships (R-20-026 group): Android and iOS only. Any other
    // platform a test harness runs on reports granted, so tests never block on a permission
    // dialog that cannot appear.
    return NotificationDeliveryState.granted;
  }

  /// Requests the platform notification permission (R-22-021, R-22-071): alerts, sound and, on
  /// iOS, the badge (R-22-020, amended 2026-09-16). The *call*, not the *moment*:
  /// a caller (`WP-18-a`'s agent-list screen) invokes this exactly once, at the first arrival at
  /// `/hosts/:hostId/agents` after the first successful pair (R-30-509).
  Future<bool> requestPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      return granted ?? false;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, sound: true, badge: true);
      return granted ?? false;
    }
    return false;
  }

  /// R-22-073: the only recovery from a refusal. Cross-platform: the top-level plugin call
  /// already falls back correctly on both Android and iOS.
  Future<bool> openNotificationSettings() async =>
      await _plugin.openAppNotificationSettings() ?? false;

  Future<Result<NotificationSettings>> loadSettings() async {
    try {
      final raw = await _preferences.getString(_settingsStorageKey);
      _settings = raw == null
          ? const NotificationSettings()
          : NotificationSettings._fromJson(
              jsonDecode(raw) as Map<String, Object?>,
            );
      return Ok(_settings);
    } on Exception catch (e) {
      return Err('load notification settings', cause: e);
    }
  }

  Future<Result<void>> saveSettings(NotificationSettings settings) async {
    try {
      _settings = settings;
      await _preferences.setString(
        _settingsStorageKey,
        jsonEncode(settings._toJson()),
      );
      return const Ok(null);
    } on Exception catch (e) {
      return Err('save notification settings', cause: e);
    }
  }

  /// Whether a real local notification has ever been posted on this phone — a genuine "an alert
  /// was posted" (or a released quiet-hours summary) at least once through [_showNow]. A test
  /// alert counts too: R-31-12-08 requires it to use the same code path, so factually it *was* an
  /// alert posted. `notification_settings_screen.dart` (`WP-19-b`) reads this for the Empty state
  /// (`docs/31-mockups/12-notifications.md`'s states table, R-90-011: "No alert has ever been
  /// posted on this phone").
  Future<bool> hasEverPosted() async =>
      await _preferences.getBool(_hasEverPostedStorageKey) ?? false;

  Future<void> _markHasEverPosted() async {
    try {
      await _preferences.setBool(_hasEverPostedStorageKey, true);
    } on Exception catch (e) {
      // Best-effort: the notification itself already succeeded by the time this is called: a
      // failure to persist the Empty-state flag must not turn a successful post into an `Err`.
      _log.warning('persist hasEverPosted flag', e);
    }
  }

  /// The audience filter's "opened" half (R-31-12-12): a later phase's pane-open point
  /// (`AgentStatusService.notePaneOpened`) calls this so `Only agents I have opened` has
  /// something to test against. Session-scoped only, like the quiet-hours hold itself
  /// (R-31-12-03: "A hold that outlives the app process is lost") — not persisted across a
  /// restart, since no rule requires it and `docs/13-security-pairing.md` R-13-065 does not list
  /// it among what plain storage must hold.
  void notePaneOpened(String paneId) => _openedPaneIds.add(paneId);

  /// Posts the local notification an `agent_status` message earns (R-11-057, R-30-502), subject
  /// to [NotificationSettings] (R-30-516: "subject only to an explicit opt-out the person set on
  /// `/settings/notifications`") and the quiet-hours hold (R-31-12-03). Every human-readable word
  /// comes from [status] alone (R-01-011, R-30-510): [status] arrived inside the Noise session, so
  /// this function reads no other source.
  Future<Result<void>> postAgentStatusNotification(AgentStatus status) async {
    if (status.status != AgentStatusKind.blocked &&
        status.status != AgentStatusKind.done) {
      // R-30-500, R-31-12-05: defence in depth. `crates/herdr-relay/src/watch/incoming.rs`
      // already filters to blocked/done before sending.
      return const Ok(null);
    }
    if (status.status == AgentStatusKind.blocked && !_settings.alertOnBlocked) {
      return const Ok(null);
    }
    if (status.status == AgentStatusKind.done && !_settings.alertOnDone) {
      return const Ok(null);
    }
    if (_settings.audienceOpenedOnly &&
        !_openedPaneIds.contains(status.paneId)) {
      return const Ok(null);
    }
    if (_isWithinQuietHours(_now())) {
      _hold(status);
      return const Ok(null);
    }
    return _showNow(status);
  }

  /// R-31-12-08: `Send a test alert` MUST use the same code path as a real alert — the same
  /// [_showNow] call this function and [postAgentStatusNotification] both use — but bypasses the
  /// settings gate and the quiet-hours hold, because it is a debugging tool a person reaches for
  /// specifically when they suspect those are silently eating alerts.
  Future<Result<NotificationDeliveryState>> sendTestNotification() async {
    // A person taps this to find out why alerts are silent. The most common reason is a
    // permission the OS was never asked for (an install that predates the R-30-509 request,
    // 2026-09-16): iOS drops an unauthorised `show()` with no error, so the tap did nothing.
    // The OS shows its dialog only while the answer is undetermined; a settled refusal returns
    // at once and the outcome row then points at the system settings (R-22-073).
    if (await effectiveDeliveryState() == NotificationDeliveryState.denied) {
      await requestPermission();
    }
    final result = await _showNow(
      AgentStatus(
        hostId: '',
        paneId: '',
        workspaceId: '',
        tabId: '',
        tabTitle: 'Test alert',
        paneTitle: 'This is a test',
        agentKind: 'herdr',
        status: AgentStatusKind.done,
        at: _now().toUtc().toIso8601String(),
      ),
    );
    return switch (result) {
      Ok() => Ok(await effectiveDeliveryState()),
      Err(:final message, :final cause) => Err(message, cause: cause),
    };
  }

  Future<Result<void>> _showNow(AgentStatus status) async {
    try {
      final content = buildAgentStatusNotificationContent(status);
      await _plugin.show(
        id: notificationIdFor(hostId: status.hostId, paneId: status.paneId),
        title: content.title,
        body: content.body,
        payload: content.payload,
        notificationDetails: _notificationDetails,
      );
      unawaited(_markHasEverPosted());
      return const Ok(null);
    } on Exception catch (e) {
      return Err('post local notification for pane ${status.paneId}', cause: e);
    }
  }

  /// Withdraws the alert for one pane (`docs/31-mockups/07-notifications.md` R-31-07-04, decided
  /// 2026-09-08): a delivered shade entry is cancelled by its stable id, a quiet-hours hold for
  /// the same pane is dropped before it can release, and the release timer stops when nothing is
  /// held any more. A pane id is one computer's name, so [hostId] is part of the identity.
  Future<Result<void>> cancelAgentStatusNotification({
    required String hostId,
    required String paneId,
  }) async {
    _held.removeWhere((s) => s.hostId == hostId && s.paneId == paneId);
    if (_held.isEmpty) {
      _releaseTimer?.cancel();
      _releaseTimer = null;
    }
    try {
      await _plugin.cancel(
        id: notificationIdFor(hostId: hostId, paneId: paneId),
      );
      return const Ok(null);
    } on Exception catch (e) {
      return Err('cancel local notification for pane $paneId', cause: e);
    }
  }

  void _hold(AgentStatus status) {
    _held.add(status);
    _releaseTimer ??= Timer(
      _durationUntilQuietHoursEnd(_now()),
      () => unawaited(_release()),
    );
  }

  Future<void> _release() async {
    _releaseTimer = null;
    final held = List<AgentStatus>.of(_held);
    _held.clear();
    if (held.isEmpty) return;
    if (held.length == 1) {
      await _showNow(held.single);
      return;
    }
    // R-31-12-03: "collapsed into one summary when several are held". No mockup gives literal
    // copy for the multi-item case (`12-notifications.md` only draws the single-alert
    // wireframe), so this is a considered, self-contained choice: the tap target is the most
    // recently held pane, which is the one a person is likeliest to still care about.
    final content = buildHeldSummaryNotificationContent(held);
    try {
      await _plugin.show(
        id: notificationIdFor(hostId: '', paneId: '__quiet_hours_summary__'),
        title: content.title,
        body: content.body,
        payload: content.payload,
        notificationDetails: _notificationDetails,
      );
      unawaited(_markHasEverPosted());
    } on Exception catch (e) {
      _log.warning('post held-alert summary', e);
    }
  }

  bool _isWithinQuietHours(DateTime at) {
    if (!_settings.quietHoursEnabled) return false;
    final nowMinutes = at.hour * 60 + at.minute;
    final from = _settings.quietHoursFrom._minutesSinceMidnight;
    final to = _settings.quietHoursTo._minutesSinceMidnight;
    if (from == to) return false;
    return from < to
        ? nowMinutes >= from && nowMinutes < to
        : nowMinutes >= from || nowMinutes < to;
  }

  Duration _durationUntilQuietHoursEnd(DateTime at) {
    final to = _settings.quietHoursTo;
    var end = DateTime(at.year, at.month, at.day, to.hour, to.minute);
    if (!end.isAfter(at)) {
      end = end.add(const Duration(days: 1));
    }
    return end.difference(at);
  }

  /// R-30-506/R-30-507, R-03-113 item 5 (2026-09-09): one notification id per Host and pane, so
  /// a newer `blocked`/`done` for the same pane replaces the delivered alert in place, never adds
  /// a second one, and `cancelAgentStatusNotification` can find it later. A 32-bit FNV-1a hash of
  /// the pair, not `String.hashCode`, which the Dart VM may vary between runs and platforms; an
  /// id posted before a relaunch must still be the id a cancel names after it.
  static int notificationIdFor({
    required String hostId,
    required String paneId,
  }) {
    var hash = 0x811c9dc5;
    for (final unit in '$hostId\u0000$paneId'.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash & 0x7fffffff;
  }

  /// Cancels the pending quiet-hours release timer. A caller (the app root) calls this on
  /// disposal; no other cleanup is owned here.
  void dispose() {
    _releaseTimer?.cancel();
    _releaseTimer = null;
  }
}

extension<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
