/// The notification settings screen, per `docs/90-implementation-plan.md` `WP-19-b` and
/// `docs/31-mockups/12-notifications.md` at route `/settings/notifications` (R-90-010, R-90-011).
///
/// [NotificationSettingsScreenBody] is the pure, stateless presentation of one named state,
/// mirroring `lock_screen.dart`'s split: it takes every value it paints as a constructor
/// argument and calls nothing. [NotificationSettingsScreen] is the stateful orchestrator: it
/// reads the saved settings and the effective delivery state from `WP-19-a`'s
/// `NotificationsService` once on mount and again on every foreground resume (R-22-072,
/// R-31-12-13), and drives a write, a test alert and an `Open Settings` tap straight through it.
///
/// [NotificationsService] is documented "one instance covers the whole app session" (its own top
/// doc comment), because it holds live, in-memory quiet-hours state (the held-alert queue and
/// release timer) that a second, independently constructed instance would not share. Unlike
/// `LockScreen`'s `BiometricGate` — a stateless per-check wrapper `LockScreen` is free to
/// default-construct — this screen therefore takes [NotificationSettingsScreen.service] as a
/// required constructor argument: a caller (`app/lib/routing.dart`, `WP-12-b`, not in this
/// package's `Paths.` line) threads through the one instance the app root already constructed
/// and called `initialize()` on.
///
/// **The empty state.** `NotificationsService.hasEverPosted()` reports whether a real alert, a
/// released quiet-hours summary, or a test alert has ever posted on this phone — a test alert
/// counts, per R-31-12-08's "same code path as a real alert" — and this screen drives
/// `NotificationSettingsPhase.empty` from it: `_phaseFor` shows `empty` only while the delivery
/// state is `granted` and nothing has posted yet, and `_sendTestAlert` clears it immediately on
/// the first successful test send.
///
/// **The quiet-hours row.** The wireframe draws a trailing chevron on the "From 22:00 to 07:30"
/// row, but `docs/33-platform-chrome.md` R-33-072.4 names this exact shape — a settings row that
/// opens a platform picker rather than pushing a route — as one of the two rows R-33-072 itself
/// settles: it drops the chevron and shows the current value instead, per R-33-072.2 and
/// R-33-072.3. This file follows the chrome rule, not the wireframe glyph, per R-32-004's own
/// "a mockup owns the character it draws... this document owns the rendered appearance" split.
library;

import 'dart:async' show unawaited;

import 'package:cupertino_ui/cupertino_ui.dart'
    show
        BorderSide,
        BuildContext,
        Column,
        CrossAxisAlignment,
        CupertinoButton,
        CupertinoDatePicker,
        CupertinoDatePickerMode,
        CupertinoListTile,
        CupertinoNavigationBar,
        CupertinoPageScaffold,
        CupertinoPopupSurface,
        CustomScrollView,
        EdgeInsets,
        ExcludeSemantics,
        Expanded,
        IgnorePointer,
        MainAxisAlignment,
        MainAxisSize,
        MediaQuery,
        MergeSemantics,
        Navigator,
        Opacity,
        Padding,
        Row,
        SafeArea,
        SizedBox,
        SliverList,
        SliverPadding,
        State,
        StatefulWidget,
        StatelessWidget,
        Text,
        ValueChanged,
        VoidCallback,
        Widget,
        showCupertinoModalPopup;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:material_ui/material_ui.dart'
    show
        AppBar,
        Border,
        Container,
        PreferredSize,
        Scaffold,
        Size,
        TimeOfDay,
        showTimePicker;

import '../core/result/result.dart' show Err, Ok, Result;
import '../services/notifications.dart'
    show
        ClockTime,
        NotificationDeliveryState,
        NotificationSettings,
        NotificationsService;
import '../widgets/app_list_row.dart';
import '../widgets/app_section_header.dart';
import '../widgets/app_strip.dart';
import '../widgets/app_text_button.dart';
import '../widgets/theme/app_color.dart';
import '../widgets/theme/app_haptic.dart';
import '../widgets/theme/app_space.dart';
import '../widgets/theme/app_type.dart';
import '../widgets/theme/chrome_activity_indicator.dart';
import '../widgets/theme/chrome_switch.dart';
import '../widgets/treatments.dart';

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

/// `border.hairline`, per `docs/32-design-language.md` R-32-330. See `app_shell.dart`'s sibling
/// constant for why this is a local constant rather than a token import.
const double _hairlineWidth = 1;

/// `opacity.disabled`, per the opacity table beside R-32-330.
const double _opacityDisabled = 0.38;

/// One of the four screen phases this file drives live. See this file's top doc comment for
/// `empty`'s trigger, and `_phaseFor` for the mapping from [NotificationDeliveryState] and
/// `NotificationsService.hasEverPosted()`.
enum NotificationSettingsPhase {
  /// `Default`, `Loading` and `Offline`: the mockup draws all three identically (Loading's only
  /// difference, one row dimmed to `opacity.disabled` for a write's round trip, is carried by
  /// [NotificationSettingsScreenBody.savingSettings], not by a phase; Offline's own row states
  /// plainly that every control "stays usable", which is already true here), mirroring
  /// `LockScreenPhase.checking`'s precedent for collapsing indistinguishable rows into one value.
  normal,

  /// No alert has ever posted on this phone. See this file's top doc comment for the trigger.
  empty,

  /// The platform notification permission was refused. The only recovery is `Open Settings`.
  permissionDenied,

  /// The permission is granted and the platform is silencing the channel anyway (R-31-12-13).
  silenced,
}

/// One setting this screen can be mid-write on, per the mockup's `Loading` row: the row being
/// written dims to `opacity.disabled` for the round trip.
enum NotificationSetting {
  agentBlocked,
  agentDone,
  onlyOpenedAgents,
  holdAlerts,
  quietHours,
}

const String _alertRunningLimitation =
    'Alerts arrive while the app is running. If the phone closes the app, '
    'the alert is waiting in the app the next time you open it.';

const String _alertScopeLimitation =
    'Alerts come from the computer you are connected to. If an agent '
    'finishes on another computer, you see it when you connect to that '
    'computer.';

const String _emptyStateLine =
    'No alerts yet. The app posts one when an agent needs you, on the '
    'computer you are connected to.';

const String _permissionDeniedLine = 'Alerts are off for this app.';

const String _silencedLine =
    'Alerts are on for this app. This phone is not showing them.';

const String _testAlertFailedLine = 'This phone would not show the alert.';

const String _privacyFootnote =
    'An alert carries the agent kind, the tab name and the pane name. It never carries pane text.';

/// The pure presentation of one screen state. See this file's top doc comment for why this is
/// split from [NotificationSettingsScreen].
class NotificationSettingsScreenBody extends StatelessWidget {
  const NotificationSettingsScreenBody({
    super.key,
    required this.phase,
    required this.settings,
    required this.savingSettings,
    required this.isSendingTestAlert,
    this.testOutcome,
    required this.onAgentBlockedChanged,
    required this.onAgentDoneChanged,
    required this.onOnlyOpenedAgentsChanged,
    required this.onHoldAlertsChanged,
    required this.onQuietHoursTap,
    required this.onSendTestAlert,
    required this.onOpenSystemSettings,
  });

  final NotificationSettingsPhase phase;
  final NotificationSettings settings;
  final Set<NotificationSetting> savingSettings;
  final bool isSendingTestAlert;
  final Result<NotificationDeliveryState>? testOutcome;
  final ValueChanged<bool> onAgentBlockedChanged;
  final ValueChanged<bool> onAgentDoneChanged;
  final ValueChanged<bool> onOnlyOpenedAgentsChanged;
  final ValueChanged<bool> onHoldAlertsChanged;
  final VoidCallback onQuietHoursTap;
  final VoidCallback onSendTestAlert;
  final VoidCallback onOpenSystemSettings;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final title = Text(
      'Alerts',
      style: AppType.heading.copyWith(color: color.fgPrimary),
    );
    // R-03-107 (amended 2026-09-09): a screen with content paints plain
    // `color.bg.base`, no ground grid and no paper block. The error strip is
    // opaque on its own (`AppStrip` paints `bg.raised`).
    final body = SafeArea(
      child: CustomScrollView(
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.space4),
            sliver: SliverList.list(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.space4,
                  ),
                  child: _limitationBlock(color),
                ),
                ..._stateBlock(color),
                if (testOutcome
                    case final Err<NotificationDeliveryState> failed)
                  _errorStrip(color, failed),
                const SizedBox(height: AppSpace.space6),
                ..._content(color),
              ],
            ),
          ),
        ],
      ),
    );
    // R-32-115, R-32-510: the app bar's bottom edge is `color.border.strong` on both platforms.
    if (_isIos) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          backgroundColor: color.bgBase,
          border: Border(
            bottom: BorderSide(
              color: color.borderStrong,
              width: _hairlineWidth,
            ),
          ),
          middle: title,
        ),
        child: body,
      );
    }
    return Scaffold(
      backgroundColor: color.bgBase,
      appBar: AppBar(
        backgroundColor: color.bgBase,
        elevation: 0,
        title: title,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(_hairlineWidth),
          child: Container(color: color.borderStrong, height: _hairlineWidth),
        ),
      ),
      body: body,
    );
  }

  /// Callout 2: `R-30-512` then `R-30-517`, one semantics passage (accessibility section). The
  /// two limits are two paragraphs with `space.3` between them, the same reading
  /// `docs/31-mockups/13-connection.md` R-31-13-23 gives the same two sentences (amended
  /// 2026-09-08 by the product owner: one dense block did not read on a phone).
  Widget _limitationBlock(AppColor color) {
    final style = AppType.caption.copyWith(color: color.fgSecondary);
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(_alertRunningLimitation, style: style),
          const SizedBox(height: AppSpace.space3),
          Text(_alertScopeLimitation, style: style),
          if (phase == NotificationSettingsPhase.empty) ...<Widget>[
            const SizedBox(height: AppSpace.space3),
            Text(_emptyStateLine, style: style),
          ],
        ],
      ),
    );
  }

  /// The permission-denied or silenced recovery block. Empty and normal add nothing here: the
  /// empty line lives inside [_limitationBlock] instead, per its own accessibility passage.
  List<Widget> _stateBlock(AppColor color) {
    final Widget? block = switch (phase) {
      NotificationSettingsPhase.normal ||
      NotificationSettingsPhase.empty => null,
      NotificationSettingsPhase.permissionDenied => _recovery(
        label: _permissionDeniedLine,
        treatment: null,
        color: color,
      ),
      NotificationSettingsPhase.silenced => _recovery(
        label: _silencedLine,
        treatment: const Treatment.warning(label: _silencedLine),
        color: color,
      ),
    };
    if (block == null) {
      return const <Widget>[];
    }
    return <Widget>[const SizedBox(height: AppSpace.space4), block];
  }

  Widget _recovery({
    required String label,
    required Widget? treatment,
    required AppColor color,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpace.space4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        treatment ??
            Text(label, style: AppType.body.copyWith(color: color.fgPrimary)),
        const SizedBox(height: AppSpace.space2),
        AppTextButton(label: 'Open Settings', onPressed: onOpenSystemSettings),
      ],
    ),
  );

  /// State row `Error`: triggered by a failed test alert, not by [phase]. `R-30-512`'s limitation
  /// already repeats above unconditionally, so callout 91's "repeats the limitation" line needs
  /// no second copy here.
  Widget _errorStrip(AppColor color, Err<NotificationDeliveryState> failed) =>
      Padding(
        padding: const EdgeInsets.only(top: AppSpace.space4),
        child: AppStrip(
          trailing: AppTextButton(
            label: 'Try again',
            onPressed: onSendTestAlert,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Treatment.error(label: _testAlertFailedLine, inStrip: true),
              const SizedBox(height: AppSpace.space1),
              Text(
                failed.message,
                style: AppType.monoCode.copyWith(color: color.fgSecondary),
              ),
            ],
          ),
        ),
      );

  /// The three groups, the test-alert row and the footnote, with a `space.6` gap between
  /// them. Permission denied dims the whole block, per callout 89: "no preference can take
  /// effect".
  List<Widget> _content(AppColor color) {
    final bool interactive =
        phase != NotificationSettingsPhase.permissionDenied;
    Widget block(Widget child) => interactive
        ? child
        : IgnorePointer(
            child: Opacity(opacity: _opacityDisabled, child: child),
          );
    Widget group(String header, List<Widget> rows) => block(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppSectionHeader.upperCase(label: header),
          ...rows,
        ],
      ),
    );
    return <Widget>[
      group('WHEN TO ALERT ME', _whenToAlertRows()),
      const SizedBox(height: AppSpace.space6),
      group('WHICH AGENTS', <Widget>[_audienceRow()]),
      const SizedBox(height: AppSpace.space6),
      group('QUIET HOURS', _quietHoursRows(color)),
      const SizedBox(height: AppSpace.space6),
      block(_testAlertRow(color)),
      const SizedBox(height: AppSpace.space6),
      block(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.space4),
          child: Text(
            _privacyFootnote,
            style: AppType.caption.copyWith(color: color.fgSecondary),
          ),
        ),
      ),
    ];
  }

  List<Widget> _whenToAlertRows() => <Widget>[
    _SwitchRow(
      label: 'An agent is blocked',
      value: settings.alertOnBlocked,
      onChanged: onAgentBlockedChanged,
      saving: savingSettings.contains(NotificationSetting.agentBlocked),
    ),
    _SwitchRow(
      label: 'An agent is done',
      value: settings.alertOnDone,
      onChanged: onAgentDoneChanged,
      saving: savingSettings.contains(NotificationSetting.agentDone),
    ),
  ];

  /// Callout 7: one Boolean, one control, per `R-31-12-12`. The secondary line always names the
  /// value not currently in force.
  Widget _audienceRow() => _SwitchRow(
    label: 'Only agents I have opened',
    value: settings.audienceOpenedOnly,
    onChanged: onOnlyOpenedAgentsChanged,
    saving: savingSettings.contains(NotificationSetting.onlyOpenedAgents),
    secondary: settings.audienceOpenedOnly
        ? 'Only agents you have opened'
        : 'Every agent on this computer',
  );

  List<Widget> _quietHoursRows(AppColor color) => <Widget>[
    _SwitchRow(
      label: 'Hold alerts',
      value: settings.quietHoursEnabled,
      onChanged: onHoldAlertsChanged,
      saving: savingSettings.contains(NotificationSetting.holdAlerts),
    ),
    Opacity(
      opacity: savingSettings.contains(NotificationSetting.quietHours)
          ? _opacityDisabled
          : 1,
      child: AppListRow(
        primary: 'Quiet hours',
        secondary:
            'From ${settings.quietHoursFrom} to ${settings.quietHoursTo}',
        onTap: onQuietHoursTap,
      ),
    ),
  ];

  /// Callout 9: a plain action row per `R-32-589`'s "Disconnect" precedent, no chevron, and
  /// callout 9/`R-31-12-14`'s own outcome text under the label. R-33-073: on iOS the row is a
  /// `CupertinoListTile` and the outcome rides its `subtitle`; on Android the outcome sits
  /// under the Material row at the row's own text inset, the way the `App Lock` message sits
  /// under its row on `/settings`.
  Widget _testAlertRow(AppColor color) {
    final Widget? outcomeText = switch (testOutcome) {
      null => null,
      Ok(value: NotificationDeliveryState.granted) => Text(
        'Alert posted.',
        style: AppType.caption.copyWith(color: color.fgSecondary),
      ),
      Ok(value: NotificationDeliveryState.silenced) => Text(
        _silencedLine,
        style: AppType.caption.copyWith(color: color.fgSecondary),
      ),
      Ok(value: NotificationDeliveryState.denied) => Text(
        _permissionDeniedLine,
        style: AppType.caption.copyWith(color: color.fgSecondary),
      ),
      Err() => const Treatment.error(label: _testAlertFailedLine),
    };
    final Widget? trailing = isSendingTestAlert
        ? const ChromeActivityIndicator()
        : null;
    final VoidCallback? onTap = isSendingTestAlert ? null : onSendTestAlert;
    if (_isIos) {
      // R-33-073: an iOS settings screen MUST use `CupertinoListTile` for each
      // row. The row keeps its `Send a test alert` semantics label, per R-30-717.
      return CupertinoListTile(
        title: const Text('Send a test alert'),
        subtitle: outcomeText,
        trailing: trailing,
        onTap: onTap,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AppListRow(
          primary: 'Send a test alert',
          trailing: trailing,
          onTap: onTap,
        ),
        if (outcomeText != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.space4,
              AppSpace.space2,
              AppSpace.space4,
              AppSpace.space2,
            ),
            child: outcomeText,
          ),
      ],
    );
  }
}

/// The switch row of `docs/32-design-language.md` section 7.7 (R-32-522): height
/// `size.row.one_line`, or `size.row.two_line` with [secondary]; the whole row is the
/// `size.target.min` target, not just the thumb. The row is the one semantics node and reads
/// `<label>, on` or `<label>, off` (R-32-505); the switch inside it is decoration.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.secondary,
    this.saving = false,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? secondary;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final bool enabled = !saving;
    final String state = value ? 'on' : 'off';
    return AppListRow(
      primary: label,
      secondary: secondary,
      semanticsValue: secondary == null ? state : '$state, $secondary',
      trailing: ExcludeSemantics(
        child: Opacity(
          opacity: enabled ? 1 : _opacityDisabled,
          child: IgnorePointer(
            child: ChromeSwitch(value: value, onChanged: (_) {}),
          ),
        ),
      ),
      onTap: enabled ? () => onChanged(!value) : null,
    );
  }
}

/// The stateful orchestrator. See this file's top doc comment for why [service] is required
/// rather than defaulted.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key, required this.service});

  /// The app's single `NotificationsService` instance (see this file's top doc comment).
  final NotificationsService service;

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen>
    with WidgetsBindingObserver {
  NotificationSettingsPhase _phase = NotificationSettingsPhase.normal;
  NotificationSettings _settings = const NotificationSettings();
  final Set<NotificationSetting> _saving = <NotificationSetting>{};
  bool _sendingTestAlert = false;
  Result<NotificationDeliveryState>? _testOutcome;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_reload());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // R-22-072, R-31-12-13: a person can revoke the permission or silence the channel from the
    // operating system at any time, so this screen re-reads the effective state on every resume.
    if (state == AppLifecycleState.resumed) {
      unawaited(_reload());
    }
  }

  static NotificationSettingsPhase _phaseFor(
    NotificationDeliveryState delivery,
    bool hasEverPosted,
  ) => switch (delivery) {
    NotificationDeliveryState.granted =>
      hasEverPosted
          ? NotificationSettingsPhase.normal
          : NotificationSettingsPhase.empty,
    NotificationDeliveryState.silenced => NotificationSettingsPhase.silenced,
    NotificationDeliveryState.denied =>
      NotificationSettingsPhase.permissionDenied,
  };

  Future<void> _reload() async {
    final NotificationDeliveryState delivery = await widget.service
        .effectiveDeliveryState();
    final bool everPosted = await widget.service.hasEverPosted();
    final Result<NotificationSettings> loaded = await widget.service
        .loadSettings();
    if (!mounted) {
      return;
    }
    setState(() {
      _phase = _phaseFor(delivery, everPosted);
      if (loaded case Ok(:final value)) {
        _settings = value;
      }
    });
  }

  Future<void> _change(
    NotificationSetting setting,
    NotificationSettings optimistic,
  ) async {
    final NotificationSettings previous = _settings;
    setState(() {
      _settings = optimistic;
      _saving.add(setting);
    });
    unawaited(AppHaptic.confirm());
    final Result<void> result = await widget.service.saveSettings(optimistic);
    if (mounted) {
      setState(() {
        if (result is Err<void>) {
          _settings = previous;
        }
        _saving.remove(setting);
      });
    }
  }

  Future<void> _sendTestAlert() async {
    setState(() {
      _sendingTestAlert = true;
      _testOutcome = null;
    });
    final Result<NotificationDeliveryState> result = await widget.service
        .sendTestNotification();
    unawaited(
      result is Err<NotificationDeliveryState>
          ? AppHaptic.error()
          : AppHaptic.commit(),
    );
    if (mounted) {
      setState(() {
        _testOutcome = result;
        _sendingTestAlert = false;
        // R-31-12-08: a test alert uses the same code path as a real one, so a successful send
        // also counts toward `hasEverPosted` and clears the Empty state immediately.
        if (result is Ok<NotificationDeliveryState> &&
            _phase == NotificationSettingsPhase.empty) {
          _phase = NotificationSettingsPhase.normal;
        }
      });
    }
  }

  Future<void> _pickQuietHours() async {
    final TimeOfDay? from = await _pickTime(
      context,
      _clockToTimeOfDay(_settings.quietHoursFrom),
    );
    if (from == null || !mounted) {
      return;
    }
    final TimeOfDay? to = await _pickTime(
      context,
      _clockToTimeOfDay(_settings.quietHoursTo),
    );
    if (to == null || !mounted) {
      return;
    }
    final NotificationSettings updated = _settings.copyWith(
      quietHoursFrom: ClockTime(hour: from.hour, minute: from.minute),
      quietHoursTo: ClockTime(hour: to.hour, minute: to.minute),
    );
    await _change(NotificationSetting.quietHours, updated);
  }

  @override
  Widget build(BuildContext context) => NotificationSettingsScreenBody(
    phase: _phase,
    settings: _settings,
    savingSettings: _saving,
    isSendingTestAlert: _sendingTestAlert,
    testOutcome: _testOutcome,
    onAgentBlockedChanged: (bool v) => unawaited(
      _change(
        NotificationSetting.agentBlocked,
        _settings.copyWith(alertOnBlocked: v),
      ),
    ),
    onAgentDoneChanged: (bool v) => unawaited(
      _change(
        NotificationSetting.agentDone,
        _settings.copyWith(alertOnDone: v),
      ),
    ),
    onOnlyOpenedAgentsChanged: (bool v) => unawaited(
      _change(
        NotificationSetting.onlyOpenedAgents,
        _settings.copyWith(audienceOpenedOnly: v),
      ),
    ),
    onHoldAlertsChanged: (bool v) => unawaited(
      _change(
        NotificationSetting.holdAlerts,
        _settings.copyWith(quietHoursEnabled: v),
      ),
    ),
    onQuietHoursTap: () => unawaited(_pickQuietHours()),
    onSendTestAlert: () => unawaited(_sendTestAlert()),
    onOpenSystemSettings: () =>
        unawaited(widget.service.openNotificationSettings()),
  );
}

TimeOfDay _clockToTimeOfDay(ClockTime clock) =>
    TimeOfDay(hour: clock.hour, minute: clock.minute);

/// Opens the platform's own time picker (callout 8), always in 24-hour digits to match the
/// mockup's exact wording.
Future<TimeOfDay?> _pickTime(BuildContext context, TimeOfDay initial) => _isIos
    ? _pickCupertinoTime(context, initial)
    : _pickMaterialTime(context, initial);

Future<TimeOfDay?> _pickMaterialTime(BuildContext context, TimeOfDay initial) =>
    showTimePicker(
      context: context,
      initialTime: initial,
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );

/// The iOS picker sits on the platform's own `CupertinoPopupSurface`, the surface an action
/// sheet draws on, with a `Done` action above the wheel; the screen paints no surface of its
/// own (R-03-059).
Future<TimeOfDay?> _pickCupertinoTime(BuildContext context, TimeOfDay initial) {
  TimeOfDay selected = initial;
  final DateTime base = DateTime(2000, 1, 1, initial.hour, initial.minute);
  return showCupertinoModalPopup<TimeOfDay>(
    context: context,
    builder: (BuildContext sheetContext) => CupertinoPopupSurface(
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 260,
          child: Column(
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  CupertinoButton(
                    onPressed: () => Navigator.of(sheetContext).pop(selected),
                    child: const Text('Done'),
                  ),
                ],
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  initialDateTime: base,
                  use24hFormat: true,
                  onDateTimeChanged: (DateTime dt) =>
                      selected = TimeOfDay(hour: dt.hour, minute: dt.minute),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
