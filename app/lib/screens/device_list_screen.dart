/// The paired-Device list screen (`WP-20-a`, wave 8 of `docs/90-implementation-plan.md`),
/// drawn from `docs/31-mockups/14-devices.md` at route `/hosts/:hostId/devices`
/// (`docs/30-ux-spec.md` row 14). Lists every phone the connected computer knows as the
/// platform's own list (R-03-105, 2026-09-09), pushes the Device detail screen
/// (`device_detail_screen.dart`) for one, and offers the three revoke actions of R-31-14-01
/// through one `delete` action in the app bar that opens the platform's own choice surface
/// (R-03-111, 2026-09-09): a Material menu on Android, a `CupertinoActionSheet` on iOS.
///
/// This file owns no route: `app/lib/routing.dart` (`WP-12-b`, not this package's `Paths.`
/// line) wires `/hosts/:hostId/devices` to this widget on request, and supplies this screen's
/// constructor arguments from whatever provider owns the live `RelayConnection`
/// ([messages], [connectionState], [send] are that connection's own `messages`,
/// `connectionState` and `send`, passed through rather than the whole object — see
/// `device_list.dart`'s own header comment for why). [onRemovedThisPhone] is this screen's
/// whole contract with routing, mirroring `ManualPairingScreen.onPaired`'s "a caller adapts
/// its own outcome" idiom: a `null` value is a deliberate no-op (R-90-016). The detail screen
/// is pushed with `Navigator.push` on this screen's own `Navigator`, not a named route: it
/// carries the one `device_list` entry the row already holds, which no URL could restate.
library;

import 'dart:async' show StreamSubscription, Timer, unawaited;

import 'package:cupertino_ui/cupertino_ui.dart'
    show
        CupertinoActionSheet,
        CupertinoActionSheetAction,
        CupertinoNavigationBar,
        CupertinoPageRoute,
        CupertinoPageScaffold,
        showCupertinoModalPopup;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart'
    show
        Align,
        Alignment,
        Border,
        BorderSide,
        BuildContext,
        Center,
        Column,
        Container,
        CrossAxisAlignment,
        CustomScrollView,
        EdgeInsets,
        Icon,
        IgnorePointer,
        MainAxisSize,
        MergeSemantics,
        Navigator,
        Opacity,
        Padding,
        PreferredSize,
        Route,
        SafeArea,
        Semantics,
        Size,
        SizedBox,
        SliverList,
        SliverPadding,
        State,
        StatefulWidget,
        StatelessWidget,
        Text,
        TextStyle,
        VoidCallback,
        Widget;
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart'
    show
        AppBar,
        CircularProgressIndicator,
        MaterialPageRoute,
        MenuAnchor,
        MenuController,
        MenuItemButton,
        Scaffold,
        ScaffoldMessenger,
        SnackBar;

import '../core/result/result.dart' show Err, Ok, Result;
import '../models/message.dart';
import '../models/messages/device_list_entry.dart';
import '../services/app_settings.dart' show AppSettingsService;
import '../services/device_list.dart';
import '../services/relay.dart'
    show
        RelayConnected,
        RelayConnectionState,
        RelayRegistrationError,
        RelayRegistrationErrorCode;
import '../widgets/app_strip.dart';
import '../widgets/app_text_button.dart';
import '../widgets/theme/app_color.dart';
import '../widgets/theme/app_haptic.dart';
import '../widgets/theme/app_radius.dart';
import '../widgets/theme/app_size.dart';
import '../widgets/theme/app_space.dart';
import '../widgets/theme/app_type.dart';
import '../widgets/theme/chrome_confirmation_dialog.dart';
import '../widgets/theme/chrome_confirmation_outcome.dart';
import '../widgets/theme/chrome_icon_action.dart';
import '../widgets/theme/chrome_list_row.dart';
import '../widgets/theme/chrome_loading_delay.dart';
import '../widgets/theme/chrome_settings_section.dart';
import '../widgets/treatments.dart';
import 'device_detail_screen.dart';

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

/// The spoken name of the app bar's `delete` action (R-03-111), the icon-only pattern of
/// R-32-505 and its Android tooltip.
const String _removeActionLabel = 'Remove phones';

/// The sentence the `Remove every phone` confirmation ends with (R-03-111, 2026-09-09: until
/// then a footnote strip under the three remove rows). `{r}` is the inline key of R-32-599;
/// `chrome_confirmation_dialog.dart` renders every body through `keyedText`, so the cap
/// draws in the dialog too.
const String _everyPhoneKeyNote =
    'Removing every phone is the same as the {r} key in the Relay pane on your computer.';

/// `opacity.dim`, per `docs/32-design-language.md`'s opacity table beside R-32-330: the stale
/// list in the `Host in use` and `Offline` states (R-31-14-09). Mirrors `qr_scan_screen.dart`'s
/// and `terminal_view_widget.dart`'s own local copy of the same token.
const double _opacityDim = 0.60;

/// `opacity.disabled`, per the same table, for the one `Remove other phones` action of the iOS
/// sheet while no other phone exists: `CupertinoActionSheetAction` has no disabled state of
/// its own, so this file dims the whole action the way `ChromeListRow.destructive` dims its
/// Cupertino tile (R-32-502).
const double _opacityDisabled = 0.38;

/// The three choices the `Remove phones` surface offers (R-03-111), in the order the
/// mockup draws them.
enum _RemoveChoice { thisPhone, others, all }

enum _Phase { loading, loaded, error, outcomeUnknown }

/// R-30-940 (`host_in_use`) and the generic offline case both dim the list and disable every
/// revoke control, per R-31-14-04 and R-31-14-09; only the header sentence differs.
enum _LiveConnection { connected, hostInUse, offline }

/// The pending target of a revoke whose outcome is unknown, kept so `Check now`'s fresh read
/// can reconcile on the right value: the fingerprint for another phone (R-31-14-12.3), never
/// the name.
class _PendingRevoke {
  const _PendingRevoke({this.fingerprint, this.name, required this.selfOrAll});
  final String? fingerprint;
  final String? name;
  final bool selfOrAll;
}

/// `<n> other phone` or `<n> other phones`, the exact count R-31-14-01 asks of a confirmation.
String _otherPhones(int count) => '$count other phone${count == 1 ? '' : 's'}';

class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({
    super.key,
    required this.hostName,
    required this.localDeviceId,
    required this.messages,
    required this.connectionState,
    required this.send,
    this.onRemovedThisPhone,
    this.appSettings,
  });

  /// The connected computer's display name, for the app bar title and the confirmation
  /// dialogs' exact wording (R-31-14-01).
  final String hostName;

  /// This phone's own `device_id`, so the row it owns can carry `This phone`, so
  /// `Remove this phone` targets the right entry and `Remove other phones` never does
  /// (R-31-14-06's own six fields carry no "this phone" flag; the app derives it by matching
  /// this id, per `docs/13-security-pairing.md` R-13-049's paired-device record).
  final String localDeviceId;

  final Stream<Message> messages;
  final Stream<RelayConnectionState> connectionState;
  final SendFrame send;

  /// Called once `revoke_result` confirms this Device (or every Device) was removed
  /// (R-11-064). The mockup's own `Navigation` section routes this to `/hosts`; wiring that
  /// route is `routing.dart`'s job, not this file's (R-90-024).
  final VoidCallback? onRemovedThisPhone;

  /// The App Lock setting the health card of this phone's detail reads (R-03-113 item 6,
  /// `appLockEnabled` of `docs/03-product-decisions.md` R-03-090). `null` reads the persisted
  /// setting through a fresh `AppSettingsService`, the way `routing.dart`'s own
  /// `_DeviceListRoute` reads `PlainStore()` for this phone's id: the preferences store is the
  /// one source `settings_screen.dart` writes, so a second reader sees the same value. A test
  /// passes its own instance.
  final AppSettingsService? appSettings;

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  _Phase _phase = _Phase.loading;
  List<DeviceListEntry>? _devices;
  String? _errorText;
  String? _refusalText;
  DateTime? _lastReadAt;
  _LiveConnection _connection = _LiveConnection.connected;
  final Set<String> _revokingIds = <String>{};
  bool _revokingAll = false;
  bool _reconciling = false;
  _PendingRevoke? _pendingRevoke;
  bool _showSkeleton = false;
  late final AppSettingsService _appSettings =
      widget.appSettings ?? AppSettingsService();

  StreamSubscription<RelayConnectionState>? _connectionSub;
  Timer? _skeletonTimer;

  @override
  void initState() {
    super.initState();
    _connectionSub = widget.connectionState.listen(_onConnectionState);
    _skeletonTimer = Timer(ChromeLoadingDelay.skeleton, () {
      if (mounted && _phase == _Phase.loading) {
        setState(() => _showSkeleton = true);
      }
    });
    // A provided service is the session's own, already loaded by `routing.dart`'s startup
    // read; a fresh one holds the documented defaults until its first `load()`.
    if (widget.appSettings == null) unawaited(_appSettings.load());
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_connectionSub?.cancel());
    _skeletonTimer?.cancel();
    // Only a service this screen constructed is this screen's to close.
    if (widget.appSettings == null) unawaited(_appSettings.dispose());
    super.dispose();
  }

  void _onConnectionState(RelayConnectionState state) {
    final _LiveConnection next = switch (state) {
      RelayConnected() => _LiveConnection.connected,
      RelayRegistrationError(:final code)
          when code == RelayRegistrationErrorCode.hostInUse =>
        _LiveConnection.hostInUse,
      _ => _LiveConnection.offline,
    };
    if (mounted) setState(() => _connection = next);
  }

  bool get _isOffline => _connection != _LiveConnection.connected;

  /// R-31-14-04 and R-31-14-12.1: every revoke control is disabled while offline, while
  /// another phone holds the computer, while a revoke is already in flight, or while an
  /// earlier revoke's outcome is still unknown.
  bool get _canRevoke =>
      !_isOffline &&
      _revokingIds.isEmpty &&
      !_revokingAll &&
      _phase != _Phase.outcomeUnknown;

  bool _isThisPhone(DeviceListEntry device) =>
      device.id == widget.localDeviceId;

  /// Guards the leading `setState` so the very first call — made synchronously from
  /// `initState` via `unawaited(_load())`, before this element's first build completes —
  /// never calls `setState` mid-build: `_phase` already starts at [_Phase.loading], so that
  /// call is a no-op then. A later call (`Try again`, always from a tap handler, long after
  /// the first build) does need it, to leave whatever phase it was showing.
  Future<void> _load() async {
    if (_phase != _Phase.loading) {
      setState(() => _phase = _Phase.loading);
    }
    final Result<List<DeviceListEntry>> result = await fetchDeviceList(
      messages: widget.messages,
      connectionState: widget.connectionState,
      send: widget.send,
    );
    if (!mounted) return;
    switch (result) {
      case Ok<List<DeviceListEntry>>(:final value):
        setState(() {
          _devices = value;
          _phase = _Phase.loaded;
          _lastReadAt = DateTime.now();
        });
      case Err<List<DeviceListEntry>>(:final message):
        setState(() {
          _phase = _Phase.error;
          _errorText = message;
        });
    }
  }

  /// `Check now` (R-31-14-12.2): reads a fresh `device_list` and never resends
  /// `revoke_device`. A read failure keeps the `Outcome unknown` state, per R-30-518's own
  /// exemption of a read from the no-retry rule.
  Future<void> _checkNow() async {
    setState(() => _reconciling = true);
    final Result<List<DeviceListEntry>> result = await fetchDeviceList(
      messages: widget.messages,
      connectionState: widget.connectionState,
      send: widget.send,
    );
    if (!mounted) return;
    switch (result) {
      case Ok<List<DeviceListEntry>>(:final value):
        final _PendingRevoke? pending = _pendingRevoke;
        if (pending != null &&
            !pending.selfOrAll &&
            !value.any((d) => d.fingerprint == pending.fingerprint)) {
          unawaited(AppHaptic.commit());
          _showSnackbar('Removed ${pending.name}.');
        }
        setState(() {
          _devices = value;
          _phase = _Phase.loaded;
          _lastReadAt = DateTime.now();
          _reconciling = false;
          _pendingRevoke = null;
        });
      case Err<List<DeviceListEntry>>():
        setState(() => _reconciling = false);
    }
  }

  Future<void> _confirmRevokeOne(DeviceListEntry device) async {
    final bool isThisPhone = _isThisPhone(device);
    final String title = isThisPhone
        ? 'Remove this phone from ${widget.hostName}?'
        : 'Remove ${device.name} from ${widget.hostName}?';
    final String body = isThisPhone
        ? 'You will have to pair again to reach this computer.'
        : 'That phone will have to pair again to reach this computer.';
    final ChromeConfirmationOutcome? outcome =
        await showChromeConfirmationDialog(
          context: context,
          title: title,
          body: body,
          destructiveLabel: 'Remove',
        );
    if (outcome != ChromeConfirmationOutcome.destructive || !mounted) return;
    setState(() {
      _revokingIds.add(device.id);
      _refusalText = null;
    });
    final RevokeOutcome result = await revokeDevice(
      messages: widget.messages,
      connectionState: widget.connectionState,
      send: widget.send,
      deviceId: device.id,
    );
    if (!mounted) return;
    _handleRevokeOutcome(
      result,
      pendingFingerprint: device.fingerprint,
      pendingName: device.name,
      selfOrAll: isThisPhone,
      revokingDeviceId: device.id,
    );
  }

  /// `Remove other phones` (R-03-105): one `revoke_device` per phone that is not this one,
  /// in sequence, each awaited before the next is sent, so at most one revoke is ever in
  /// flight (R-31-14-12.1, R-31-14-14.4). The wire offers no "every phone but one" request
  /// (R-11-063 carries one `device_id` or `all`), so the sequence is the request. Every row
  /// the sequence covers shows `removing` from the start, and each confirmed phone leaves the
  /// list as its `revoke_result` arrives. A refusal or a silent revoke stops the sequence at
  /// that phone and hands it to [_handleRevokeOutcome], so the strip or the `Outcome unknown`
  /// block names that one phone; the phones already removed stay gone and the rest keep
  /// their rows, because a second revoke aimed at a list the app can no longer trust is what
  /// R-31-14-12.1 forbids.
  Future<void> _confirmRevokeOthers() async {
    final List<DeviceListEntry> others = _devices!
        .where((d) => !_isThisPhone(d))
        .toList();
    final ChromeConfirmationOutcome? outcome =
        await showChromeConfirmationDialog(
          context: context,
          title:
              'Remove ${_otherPhones(others.length)} from ${widget.hostName}?',
          body: 'They pair again. This phone keeps access.',
          destructiveLabel: 'Remove other phones',
        );
    if (outcome != ChromeConfirmationOutcome.destructive || !mounted) return;
    setState(() {
      _revokingIds.addAll(others.map((d) => d.id));
      _refusalText = null;
    });
    int removed = 0;
    for (final DeviceListEntry device in others) {
      final RevokeOutcome result = await revokeDevice(
        messages: widget.messages,
        connectionState: widget.connectionState,
        send: widget.send,
        deviceId: device.id,
      );
      if (!mounted) return;
      if (result is! RevokeSucceeded) {
        // The rows still waiting return to their last read value; the one that stopped the
        // sequence is reported like a single revoke.
        _revokingIds.clear();
        _handleRevokeOutcome(
          result,
          pendingFingerprint: device.fingerprint,
          pendingName: device.name,
          selfOrAll: false,
          revokingDeviceId: device.id,
        );
        return;
      }
      removed += result.revokedIds.length;
      setState(() {
        _devices = _devices!
            .where((d) => !result.revokedIds.contains(d.id))
            .toList();
        _revokingIds.removeWhere(result.revokedIds.contains);
      });
    }
    unawaited(AppHaptic.commit());
    _showSnackbar('Removed ${_otherPhones(removed)}.');
  }

  /// The `Remove every phone` confirmation (R-31-14-01): the exact count, then the sentence
  /// about the `r` key, which R-03-111 moved here from the list's footnote.
  Future<void> _confirmRevokeAll() async {
    final int others = _devices!.where((d) => !_isThisPhone(d)).length;
    final String consequence = others == 0
        ? 'This phone loses access. You pair again.'
        : 'This phone and ${_otherPhones(others)} lose access at once. '
              'Everyone pairs again.';
    final ChromeConfirmationOutcome? outcome =
        await showChromeConfirmationDialog(
          context: context,
          title: 'Remove every phone from ${widget.hostName}?',
          body: '$consequence $_everyPhoneKeyNote',
          destructiveLabel: 'Remove every phone',
        );
    if (outcome != ChromeConfirmationOutcome.destructive || !mounted) return;
    setState(() {
      _revokingAll = true;
      _refusalText = null;
    });
    final RevokeOutcome result = await revokeAllDevices(
      messages: widget.messages,
      connectionState: widget.connectionState,
      send: widget.send,
    );
    if (!mounted) return;
    _handleRevokeOutcome(result, selfOrAll: true, revokingDeviceId: null);
  }

  void _handleRevokeOutcome(
    RevokeOutcome result, {
    String? pendingFingerprint,
    String? pendingName,
    required bool selfOrAll,
    required String? revokingDeviceId,
  }) {
    switch (result) {
      case RevokeSucceeded(:final revokedIds, :final all):
        unawaited(AppHaptic.commit());
        final bool removedThisPhone =
            all || revokedIds.contains(widget.localDeviceId);
        if (removedThisPhone) {
          widget.onRemovedThisPhone?.call();
          return;
        }
        setState(() {
          _devices = _devices!
              .where((d) => !revokedIds.contains(d.id))
              .toList();
          _revokingIds.removeWhere(revokedIds.contains);
          _revokingAll = false;
        });
        _showSnackbar('Removed ${pendingName ?? ''}.');
      case RevokeRefused(:final message):
        unawaited(AppHaptic.error());
        setState(() {
          if (revokingDeviceId != null) _revokingIds.remove(revokingDeviceId);
          _revokingAll = false;
          _refusalText = message;
        });
      case RevokeOutcomeUnknown():
        setState(() {
          if (revokingDeviceId != null) _revokingIds.remove(revokingDeviceId);
          _revokingAll = false;
          _phase = _Phase.outcomeUnknown;
          _pendingRevoke = _PendingRevoke(
            fingerprint: pendingFingerprint,
            name: pendingName,
            selfOrAll: selfOrAll,
          );
        });
    }
  }

  void _showSnackbar(String message) {
    final AppColor color = AppColor.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color.bgRaised,
        content: Text(
          message,
          style: AppType.body.copyWith(color: color.fgPrimary),
        ),
      ),
    );
  }

  /// Pushes the Device detail screen as the next level, on this screen's own `Navigator`, so
  /// the platform's own page transition and back control carry it (R-33-070, R-33-072.1).
  /// `Remove` there pops the detail first, so the confirmation dialog of R-33-074 opens over
  /// this list, then re-checks [_canRevoke]: the detail's own `canRemove` is the value at the
  /// moment it was pushed, and the link may have dropped since (R-31-14-04). This phone's
  /// detail also gets the App Lock setting for its health card (R-03-113 item 6), read here
  /// at push time, so the card shows the value the moment it opens.
  void _openDetail(DeviceListEntry device) {
    Widget detail(BuildContext routeContext) => DeviceDetailScreen(
      device: device,
      isThisPhone: _isThisPhone(device),
      appLockEnabled: _appSettings.current.appLockEnabled,
      canRemove: _canRevoke,
      onRemove: () {
        Navigator.of(routeContext).pop();
        if (_canRevoke) unawaited(_confirmRevokeOne(device));
      },
    );
    final Route<void> route = _isIos
        ? CupertinoPageRoute<void>(builder: detail)
        : MaterialPageRoute<void>(builder: detail);
    unawaited(Navigator.of(context).push<void>(route));
  }

  /// This phone's own entry, when the loaded list holds it.
  DeviceListEntry? get _thisPhone => _devices
      ?.cast<DeviceListEntry?>()
      .firstWhere((d) => _isThisPhone(d!), orElse: () => null);

  bool get _hasOthers => _devices?.any((d) => !_isThisPhone(d)) ?? false;

  /// The `Remove phones` action opens only over a list the app can trust: the loaded one,
  /// with every gate of [_canRevoke] open. Removing from an unknown list is a guess, so the
  /// action is disabled while the list loads or failed to load, exactly as the rows it
  /// replaces were absent then (R-03-111 amends R-03-105).
  bool get _canOpenRemove => _phase == _Phase.loaded && _canRevoke;

  /// Runs the choice the menu or the sheet returned. Each choice opens its own confirmation
  /// of R-33-074 (R-31-14-01); a choice whose target is gone (this phone left the list, no
  /// other phone exists) is disabled on the surface, so this only re-checks the gate a
  /// dropped link may have closed since the surface opened (R-31-14-04).
  void _onRemoveChoice(_RemoveChoice choice) {
    if (!_canOpenRemove) return;
    switch (choice) {
      case _RemoveChoice.thisPhone:
        final DeviceListEntry? thisPhone = _thisPhone;
        if (thisPhone != null) unawaited(_confirmRevokeOne(thisPhone));
      case _RemoveChoice.others:
        if (_hasOthers) unawaited(_confirmRevokeOthers());
      case _RemoveChoice.all:
        unawaited(_confirmRevokeAll());
    }
  }

  /// The one `delete` action of R-03-111 in the app bar, spoken `Remove phones`, the
  /// [ChromeIconAction] of R-33-033 with the glyph of `treat.destructive`. On Android it is
  /// the anchor of a Material menu: the three choices as [MenuItemButton]s, each with the
  /// destructive glyph, disabled when their target is gone. On iOS it opens the
  /// `CupertinoActionSheet` of [_showRemoveSheet]. Disabled at `opacity.disabled` while
  /// [_canOpenRemove] is false, so the bar never gains or loses a control (R-32-502).
  Widget _removeAction(AppColor color) {
    if (_isIos) {
      return ChromeIconAction(
        icon: Symbols.delete_outline_rounded,
        label: _removeActionLabel,
        onPressed: _canOpenRemove ? () => unawaited(_showRemoveSheet()) : null,
      );
    }
    return MenuAnchor(
      builder:
          (BuildContext context, MenuController controller, Widget? child) =>
              ChromeIconAction(
                icon: Symbols.delete_outline_rounded,
                label: _removeActionLabel,
                onPressed: _canOpenRemove
                    ? () => controller.isOpen
                          ? controller.close()
                          : controller.open()
                    : null,
              ),
      menuChildren: <Widget>[
        _removeMenuItem(
          color,
          'Remove this phone',
          enabled: _thisPhone != null,
          choice: _RemoveChoice.thisPhone,
        ),
        _removeMenuItem(
          color,
          'Remove other phones',
          enabled: _hasOthers,
          choice: _RemoveChoice.others,
        ),
        _removeMenuItem(
          color,
          'Remove every phone',
          enabled: true,
          choice: _RemoveChoice.all,
        ),
      ],
    );
  }

  /// One item of the Android menu: the platform's own [MenuItemButton], its label in the
  /// component's own type, the `delete_outline` glyph of `treat.destructive` at `size.icon.md`
  /// in `color.status.error` leading it (R-32-527), the same token dimmed when the item is
  /// disabled (R-32-502). The item announces `destructive`, per R-30-141, as the rows it
  /// replaces did.
  Widget _removeMenuItem(
    AppColor color,
    String title, {
    required bool enabled,
    required _RemoveChoice choice,
  }) => MergeSemantics(
    child: Semantics(
      hint: 'destructive',
      child: MenuItemButton(
        style: MenuItemButton.styleFrom(
          iconColor: color.statusError,
          disabledIconColor: color.statusError.withValues(
            alpha: _opacityDisabled,
          ),
          iconSize: AppSize.iconMd,
        ),
        leadingIcon: const Icon(Symbols.delete_outline_rounded),
        onPressed: enabled ? () => _onRemoveChoice(choice) : null,
        child: Text(title),
      ),
    ),
  );

  /// The iOS choice surface of R-03-111: the platform's own `CupertinoActionSheet`, three
  /// `isDestructiveAction` actions in the mockup's order and the `Cancel` button the platform
  /// groups apart. Each label keeps the component's own size, colour and case and takes the
  /// interface family, as `app.dart`'s `actionTextStyle` does for every `CupertinoButton`
  /// (R-03-104, R-32-212): the sheet reads no theme slot, so the family is set on the label.
  /// The sheet returns the choice and closes; the confirmation of R-33-074 then opens over
  /// the list, never over the sheet.
  Future<void> _showRemoveSheet() async {
    final bool hasThisPhone = _thisPhone != null;
    final bool hasOthers = _hasOthers;
    Widget label(String title) => Text(
      title,
      style: const TextStyle(fontFamily: AppType.interfaceFontFamily),
    );
    final _RemoveChoice? choice = await showCupertinoModalPopup<_RemoveChoice>(
      context: context,
      builder: (BuildContext sheetContext) {
        Widget action(
          String title,
          _RemoveChoice choice, {
          required bool enabled,
        }) {
          final Widget action = CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(sheetContext).pop(choice),
            child: label(title),
          );
          return MergeSemantics(
            child: Semantics(
              hint: 'destructive',
              enabled: enabled,
              child: enabled
                  ? action
                  : IgnorePointer(
                      child: Opacity(opacity: _opacityDisabled, child: action),
                    ),
            ),
          );
        }

        return CupertinoActionSheet(
          actions: <Widget>[
            action(
              'Remove this phone',
              _RemoveChoice.thisPhone,
              enabled: hasThisPhone,
            ),
            action(
              'Remove other phones',
              _RemoveChoice.others,
              enabled: hasOthers,
            ),
            action('Remove every phone', _RemoveChoice.all, enabled: true),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop(),
            child: label('Cancel'),
          ),
        );
      },
    );
    if (choice != null && mounted) _onRemoveChoice(choice);
  }

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    // `color.bg.base` with a `border.hairline`-wide `color.border.strong` bottom edge, per
    // R-32-115, matching `actions_screen.dart`, `settings_screen.dart` and
    // `qr_scan_screen.dart`'s own app bars: a bare `Scaffold`/`AppBar`/`CupertinoPageScaffold`
    // left this title on the platform's own default surface colour and typeface, off
    // `color.bg.base` and off `type.heading`/`IBM Plex Sans` alike. `type.heading`, not
    // `type.title`, because this screen carries a back chevron, matching
    // `actions_screen.dart`'s own `type.heading`-versus-`settings_screen.dart`'s-`type.title`
    // (no back chevron) precedent.
    final Widget title = Text(
      'Phones on ${widget.hostName}',
      style: AppType.heading.copyWith(color: color.fgPrimary),
    );
    // R-03-107 (amended 2026-09-09): a screen with content paints plain `color.bg.base`, the
    // scaffold's own ground, with no grid and no paper block behind the list.
    final Widget body = SafeArea(top: false, child: _buildBody(context));
    final Widget removeAction = _removeAction(color);
    // R-32-115, R-32-510: the app bar's bottom edge is `color.border.strong` on both platforms.
    if (_isIos) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          backgroundColor: color.bgBase,
          border: Border(
            bottom: BorderSide(
              color: color.borderStrong,
              width: AppBorder.hairline,
            ),
          ),
          middle: title,
          trailing: removeAction,
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
        actions: <Widget>[removeAction],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(AppBorder.hairline),
          child: Container(
            color: color.borderStrong,
            height: AppBorder.hairline,
          ),
        ),
      ),
      body: body,
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_phase) {
      case _Phase.loading:
        return _showSkeleton ? const _SkeletonList() : const SizedBox.shrink();
      case _Phase.error:
        return _ErrorBlock(
          text: _errorText ?? '',
          onRetry: () => unawaited(_load()),
        );
      case _Phase.loaded:
      case _Phase.outcomeUnknown:
        return _buildLoaded(context);
    }
  }

  /// The loaded list (R-03-105, 2026-09-09): the strips and blocks of the live states first,
  /// then the phones as one platform list section, one push row per phone. The section is a
  /// `ChromeSettingsSection`, the composing widget of R-33-073, so the iOS list is an
  /// inset-grouped card and the Android list a plain column, each with the platform's own gap
  /// above it. The list carries no state bar: every paired phone shares one state hue
  /// (R-32-130), and a bar that cannot differ says nothing (R-03-058); `This phone` and `now`
  /// separate the connected phone instead. The remove actions live in the app bar
  /// (R-03-111, [_removeAction]), so the list ends with its last phone (R-03-109).
  Widget _buildLoaded(BuildContext context) {
    final List<DeviceListEntry> devices = _devices!;
    final String readAtLabel = _lastReadAt == null
        ? ''
        : formatPairedShort(_lastReadAt!.toLocal()).split(' ').skip(2).join();

    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.only(bottom: AppSpace.space4),
          sliver: SliverList.list(
            children: <Widget>[
              if (_connection == _LiveConnection.hostInUse)
                _bannerStrip(
                  'Another phone is using this computer. This list is from $readAtLabel.',
                ),
              if (_connection == _LiveConnection.offline)
                _bannerStrip('Offline. This list is from $readAtLabel.'),
              if (_phase == _Phase.outcomeUnknown)
                _OutcomeUnknownBlock(
                  reconciling: _reconciling,
                  onCheckNow: _reconciling
                      ? null
                      : () => unawaited(_checkNow()),
                ),
              if (_refusalText != null)
                AppStrip(
                  child: Treatment.error(label: _refusalText!, inStrip: true),
                ),
              // R-31-14-09: the stale list of `Host in use` and `Offline` dims as one.
              Opacity(
                opacity: _isOffline ? _opacityDim : 1,
                child: ChromeSettingsSection(
                  rows: <Widget>[
                    for (final (int index, DeviceListEntry device)
                        in devices.indexed)
                      _DeviceRow(
                        device: device,
                        isThisPhone: _isThisPhone(device),
                        isStale: _isOffline,
                        isRemoving:
                            _revokingAll || _revokingIds.contains(device.id),
                        // R-32-515: the last row of a section carries no divider.
                        showDivider: index < devices.length - 1,
                        onOpen: () => _openDetail(device),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bannerStrip(String text) =>
      AppStrip(child: Treatment.warning(label: text));
}

/// The two skeleton rows of the `Loading` state, shown only after a 150 ms grace period, on
/// the screen's plain `color.bg.base` (R-03-107, amended 2026-09-09: no paper block).
class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    Widget bar() => Container(
      height: AppSize.skeleton,
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpace.space4,
        vertical: AppSpace.space2,
      ),
      color: color.bgRaised,
    );
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: AppSize.rowTwoLine * 2,
        width: double.infinity,
        child: Column(children: <Widget>[bar(), bar(), bar(), bar()]),
      ),
    );
  }
}

/// The `Error` state: `Could not read the phone list.`, the raw text, and `Try again`
/// (R-30-803, R-30-804), on the screen's plain `color.bg.base`.
class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.space4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Treatment.error(label: 'Could not read the phone list.'),
            const SizedBox(height: AppSpace.space2),
            Text(
              text,
              style: AppType.monoCode.copyWith(color: color.fgPrimary),
            ),
            const SizedBox(height: AppSpace.space4),
            AppTextButton(label: 'Try again', onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

/// The `Outcome unknown` state (R-30-518, R-31-14-12): two sentences, then `Check now`, never
/// `Try again`, and no `treat.error`.
class _OutcomeUnknownBlock extends StatelessWidget {
  const _OutcomeUnknownBlock({
    required this.reconciling,
    required this.onCheckNow,
  });

  final bool reconciling;
  final VoidCallback? onCheckNow;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    return AppStrip(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'This phone did not get an answer.',
            style: AppType.body.copyWith(color: color.fgPrimary),
          ),
          Text(
            'The change may already be done.',
            style: AppType.body.copyWith(color: color.fgPrimary),
          ),
          const SizedBox(height: AppSpace.space3),
          reconciling
              ? const SizedBox(
                  width: AppSize.spinner,
                  height: AppSize.spinner,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : AppTextButton(label: 'Check now', onPressed: onCheckNow),
        ],
      ),
    );
  }
}

/// One paired-device row (`docs/31-mockups/14-devices.md`'s first wireframe, R-03-105): the
/// platform's own push row, [ChromeListRow.push], with the name as its title, `paired <time>`
/// and the last-seen age as its subtitle, and, on this phone's row alone, `This phone` at
/// the trailing edge in `type.label` `color.fg.secondary`, sentence case, the platform's
/// secondary label and no chip. The row itself pushes the detail (R-33-072.1), so iOS keeps
/// the chevron. No state bar and no connection glyph: see [_DeviceListScreenState._buildLoaded].
///
/// Callout 11: while a revoke is in flight the spinner `size.spinner` takes the trailing slot
/// and `removing` replaces the two times. One semantics node, named here one level up (the
/// platform row's own node would speak the name alone): the name, `this phone` when it
/// applies, the connection word, the platform, the pair time, then the last seen time, per
/// the mockup's own Accessibility section.
class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.isThisPhone,
    required this.isStale,
    required this.isRemoving,
    required this.showDivider,
    required this.onOpen,
  });

  final DeviceListEntry device;
  final bool isThisPhone;

  /// `true` while the list is the last-read, dimmed value shown during `Host in use` or
  /// `Offline` (R-31-14-09): the row MUST NOT speak a live connection then.
  final bool isStale;
  final bool isRemoving;
  final bool showDivider;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final DateTime paired = parseWireTimestamp(device.pairedAt);
    final DateTime lastSeen = parseWireTimestamp(device.lastSeen);
    // A connected row reads `now` regardless of `last_seen` (the `now` rows of
    // docs/31-mockups/14-devices.md): the Host stamps `last_seen` on every frame it serves,
    // so a relative time on a connected row is a stale-read artifact, decided 2026-09-03.
    final String lastSeenLabel = device.connected
        ? 'now'
        : formatLastSeen(lastSeen);
    final String connectionWord = device.connected
        ? (isStale ? 'Last connected' : 'Connected')
        : 'Not connected';
    final String semanticsLabel = <String>[
      device.name,
      if (isThisPhone) 'this phone',
      connectionWord,
      platformLabel(device.platform),
      'paired ${formatPairedShort(paired)}',
      isRemoving ? 'removing' : 'last seen $lastSeenLabel',
    ].join(', ');

    final Widget? trailing = isRemoving
        ? const SizedBox(
            width: AppSize.spinner,
            height: AppSize.spinner,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : isThisPhone
        ? Text(
            'This phone',
            style: AppType.label.copyWith(color: color.fgSecondary),
          )
        : null;

    return Semantics(
      label: semanticsLabel,
      button: true,
      onTap: onOpen,
      excludeSemantics: true,
      child: ChromeListRow.push(
        title: device.name,
        subtitle: isRemoving
            ? 'removing'
            : 'paired ${formatPairedShort(paired)} \u00b7 seen $lastSeenLabel',
        trailing: trailing,
        onTap: onOpen,
        showDivider: showDivider,
      ),
    );
  }
}
