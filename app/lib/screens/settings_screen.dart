/// Settings controls for this phone. Relay origins belong to computers (R-03-126).
library;

import 'dart:async' show StreamSubscription, unawaited;
import 'dart:convert' show utf8;

import 'package:cupertino_ui/cupertino_ui.dart'
    show
        CupertinoNavigationBar,
        CupertinoPageScaffold,
        CupertinoSlider,
        CupertinoSlidingSegmentedControl;
import 'package:device_info_plus/device_info_plus.dart' show DeviceInfoPlugin;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart'
    show
        Border,
        BorderRadius,
        BorderSide,
        BoxDecoration,
        Brightness,
        BuildContext,
        Center,
        Column,
        Container,
        CrossAxisAlignment,
        EdgeInsets,
        Expanded,
        CustomScrollView,
        MainAxisSize,
        MediaQuery,
        MergeSemantics,
        Navigator,
        Padding,
        PreferredSize,
        Radius,
        RoundedRectangleBorder,
        Row,
        SafeArea,
        Semantics,
        Size,
        SizedBox,
        SliverList,
        SliverPadding,
        StatefulWidget,
        State,
        StatelessWidget,
        Text,
        TextBaseline,
        TextEditingController,
        ValueChanged,
        VoidCallback,
        Widget;
import 'package:local_auth/local_auth.dart' show LocalAuthentication;
import 'package:material_ui/material_ui.dart'
    show
        AppBar,
        ButtonSegment,
        ExcludeSemantics,
        FocusNode,
        Scaffold,
        ScaffoldMessenger,
        SegmentedButton,
        Slider,
        SnackBar,
        showModalBottomSheet;

import '../core/result/result.dart' show Ok, Err;
import '../services/app_settings.dart'
    show AppSettings, AppSettingsService, AppThemeMode;
import '../services/biometric_gate.dart' show BiometricGate;
import '../services/keystore.dart' show KeystoreService;
import '../services/plain_store.dart' show PlainStore, PairedHostRecord;
import '../services/relay.dart'
    show
        RelayConnection,
        RelayConnectionState,
        RelayConnected,
        RelayDisconnected;
import '../widgets/app_filled_button.dart' show AppFilledButton;
import '../widgets/app_text_button.dart' show AppTextButton;
import '../widgets/input_field.dart' show InputField;
import '../widgets/theme/app_color.dart' show AppColor;
import '../widgets/theme/app_haptic.dart' show AppHaptic;
import '../widgets/theme/app_radius.dart' show AppRadius, AppBorder;
import '../widgets/theme/app_size.dart' show AppSize;
import '../widgets/theme/app_space.dart' show AppSpace;
import '../widgets/theme/app_type.dart' show AppType;
import '../widgets/theme/chrome_list_row.dart' show ChromeListRow;
import '../widgets/theme/chrome_settings_section.dart'
    show ChromeSettingsSection;
import '../widgets/treatments.dart' show Treatment;

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

/// R-31-15-02's exact wording.
const String _terminalSizeIndependenceLine =
    "Terminal text size is separate from your phone's text size.";

/// R-31-15-05's exact wording (callout 8).
const String _themePaletteLine =
    'The terminal palette follows this setting too.';

/// The three segment labels of R-31-15-05, in `type.label` as written (R-32-520, R-32-213).
String _themeSegmentLabel(AppThemeMode mode) => switch (mode) {
  AppThemeMode.system => 'System',
  AppThemeMode.light => 'Light',
  AppThemeMode.dark => 'Dark',
};

/// `Could not save that setting.` — the Error state's exact wording.
const String _saveFailedSnackbar = 'Could not save that setting.';

/// R-31-15-13's exact wording.
const String _nameTooLongText = 'That name is too long. Shorten it.';

/// `No screen lock` state's exact line, R-31-15-18/`docs/31-mockups/15-appearance.md` callout
/// 305.
const String _noScreenLockMessage =
    "This phone has no screen lock. Add a passcode or fingerprint in your "
    "phone's settings, then come back.";

/// The `device_name` byte limit, R-11-226. This screen MUST NOT restate it as a number of its
/// own elsewhere; it is used only to bound the field here.
const int _deviceNameByteLimit = 32;

/// The Settings screen's stateful orchestrator. Every live value — the stored origin, the
/// paired-computer list, the connected computer, this phone's saved name — is read from the
/// services below on mount and re-read after a write; this widget holds no route and no
/// navigation service of its own (R-90-024).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.appSettings,
    required this.keystore,
    required this.gate,
    required this.plainStore,
    required this.connection,
    LocalAuthentication? localAuth,
    this.onOpenAlerts,
    this.onOpenAbout,
    this.onOpenStatusColours,
    this.onOpenDevices,
    this.onOpenDiagnostics,
  }) : _providedLocalAuth = localAuth;

  final AppSettingsService appSettings;
  final KeystoreService keystore;

  /// The session-shared gate `routing.dart`'s `biometricGateProvider` builds. R-31-15-18's
  /// App Lock switch calls [BiometricGate.setAppLockEnabled] on this same instance once
  /// [keystore]'s [KeystoreService.retoggleProtection] succeeds, so the very next R-22-017
  /// trigger sees the new setting with no app restart.
  final BiometricGate gate;
  final PlainStore plainStore;
  final RelayConnection connection;
  final LocalAuthentication? _providedLocalAuth;

  final VoidCallback? onOpenAlerts;
  final VoidCallback? onOpenAbout;

  /// `Status colours`, the legend of `docs/31-mockups/20-status-legend.md` (R-03-106, decided
  /// 2026-09-09 by the product owner). `null` is a deliberate no-op (R-90-016).
  final VoidCallback? onOpenStatusColours;

  /// `Phones on this computer`, scoped to the connected computer's `hostId` (R-31-15-16).
  final void Function(String hostId)? onOpenDevices;

  /// `Connection`, scoped the same way.
  final void Function(String hostId)? onOpenDiagnostics;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final LocalAuthentication _localAuth =
      widget._providedLocalAuth ?? LocalAuthentication();

  AppSettings _settings = const AppSettings();
  String? _deviceName;

  /// The device model, loaded on init for R-31-14-05/R-31-15-15's default. Stays `null` where
  /// no device-info channel answers; the name row then shows the stored name alone.
  String? _deviceModelName;
  List<PairedHostRecord> _pairedHosts = const <PairedHostRecord>[];
  RelayConnectionState _connectionState = const RelayDisconnected();

  /// R-31-15-18/`No screen lock` state: `local_auth.isDeviceSupported()`. Starts `true` so
  /// the row is not disabled for one frame before the real read completes.
  bool _deviceLockAvailable = true;

  StreamSubscription<AppSettings>? _settingsSubscription;
  StreamSubscription<RelayConnectionState>? _connectionSubscription;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAll());
    unawaited(_loadDeviceModelName());
    unawaited(_checkDeviceLockAvailable());
    _settingsSubscription = widget.appSettings.changes.listen((settings) {
      if (mounted) {
        setState(() => _settings = settings);
      }
    });
    _connectionSubscription = widget.connection.connectionState.listen((state) {
      if (mounted) {
        setState(() => _connectionState = state);
      }
    });
  }

  @override
  void dispose() {
    unawaited(_settingsSubscription?.cancel());
    unawaited(_connectionSubscription?.cancel());
    super.dispose();
  }

  Future<void> _checkDeviceLockAvailable() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      if (!mounted) {
        return;
      }
      setState(() => _deviceLockAvailable = supported);
    } on Exception {
      // Leaves the row enabled; the real toggle attempt is the definitive check.
    }
  }

  Future<void> _loadAll() async {
    final settingsResult = await widget.appSettings.load();
    final nameResult = await widget.plainStore.deviceName();
    final hostsResult = await widget.plainStore.pairedHosts();
    if (!mounted) {
      return;
    }
    setState(() {
      if (settingsResult case Ok<AppSettings>(:final value)) {
        _settings = value;
      }
      if (nameResult case Ok<String?>(:final value)) {
        _deviceName = value;
      }
      if (hostsResult case Ok<List<PairedHostRecord>>(:final value)) {
        _pairedHosts = value;
      }
      _connectionState = widget.connection.isConnected
          ? const RelayConnected()
          : const RelayDisconnected();
    });
  }

  /// decided 2026-09-03 by the product owner: the name row shows the stored name or the device
  /// model (R-31-14-05/R-31-15-15), never an ellipsis. This future stays separate from
  /// [_loadAll] because the device-info channel can stay silent where no plugin answers (a
  /// test without the mock); it must never gate the stored values.
  Future<void> _loadDeviceModelName() async {
    final String model;
    try {
      model = await _defaultDeviceName();
    } on Exception {
      return; // No device-info channel: the row falls back to the stored name.
    }
    if (!mounted) {
      return;
    }
    setState(() => _deviceModelName = model);
  }

  String? get _connectedHostId {
    if (_connectionState is! RelayConnected) {
      return null;
    }
    return widget.connection.lastHostInfo?.hostId;
  }

  String? get _connectedHostName {
    final hostId = _connectedHostId;
    if (hostId == null) {
      return null;
    }
    final matches = _pairedHosts.where((host) => host.hostId == hostId);
    if (matches.isNotEmpty) {
      return matches.first.hostName;
    }
    return widget.connection.lastHostInfo?.hostName;
  }

  /// R-31-14-05's default: the device model. A third occurrence of the same read
  /// `qr_scan_screen.dart`'s and `host_list.dart`'s own private `_buildDeviceInfo` already
  /// perform; duplicated for the same reason `host_list.dart` states for its own copy
  /// (R-90-018).
  Future<String> _defaultDeviceName() async {
    if (_isIos) {
      return (await DeviceInfoPlugin().iosInfo).modelName;
    }
    return (await DeviceInfoPlugin().androidInfo).model;
  }

  Future<void> _fireHaptic(Future<void> Function() haptic) async {
    if (!_settings.hapticsEnabled) {
      return; // R-31-15-04: `Haptics` off silences every haptic, including the error haptic.
    }
    await haptic();
  }

  // --- Theme and terminal size ---

  Future<void> _onThemeModeChanged(AppThemeMode mode) async {
    await _fireHaptic(AppHaptic.select);
    final result = await widget.appSettings.setThemeMode(mode);
    if (result case Err()) {
      _showSnackbar(_saveFailedSnackbar);
    }
  }

  Future<void> _onTerminalSizeChanged(int size) async {
    await _fireHaptic(AppHaptic.select);
    // R-31-15-03: never clears the grid or loses scroll position — this call only persists a
    // preference; it never rebuilds a live terminal grid, which lives on a different screen.
    final result = await widget.appSettings.setTerminalTextSize(size);
    if (result case Err()) {
      _showSnackbar(_saveFailedSnackbar);
    }
  }

  // --- Haptics ---

  Future<void> _onHapticsChanged(bool value) async {
    final result = await widget.appSettings.setHapticsEnabled(value: value);
    if (result case Ok()) {
      if (value) {
        unawaited(AppHaptic.confirm());
      }
    } else {
      _showSnackbar(_saveFailedSnackbar);
    }
  }

  Future<void> _onKeyHapticsChanged(bool value) async {
    await _fireHaptic(AppHaptic.confirm);
    final result = await widget.appSettings.setKeyPressHapticsEnabled(
      value: value,
    );
    if (result case Err()) {
      _showSnackbar(_saveFailedSnackbar);
    }
  }

  // --- App Lock (callout 18) ---

  /// R-03-092/R-13-073/R-22-083: migrates every secret [widget.keystore] owns to the new
  /// protection level first, and only persists the switch (and syncs [widget.gate]) once
  /// that succeeds -- never regenerates the Device key, never unpairs (`retoggleProtection`'s
  /// own doc comment). A failure at either step leaves the switch, the storage mode, and the
  /// gate all exactly as they were.
  Future<void> _onAppLockChanged(bool value) async {
    await _fireHaptic(AppHaptic.select);
    final hostIds = _pairedHosts.map((host) => host.hostId).toList();
    final retoggleResult = await widget.keystore.retoggleProtection(
      appLockEnabled: value,
      hostIds: hostIds,
    );
    if (!mounted) {
      return;
    }
    if (retoggleResult case Err()) {
      _showSnackbar(_saveFailedSnackbar);
      return;
    }
    final settingResult = await widget.appSettings.setAppLockEnabled(
      value: value,
    );
    if (!mounted) {
      return;
    }
    if (settingResult case Err()) {
      _showSnackbar(_saveFailedSnackbar);
      return;
    }
    widget.gate.setAppLockEnabled(value: value);
  }

  // --- This phone's name ---

  Future<void> _openNameSheet() async {
    final defaultName = await _defaultDeviceName();
    if (!mounted) {
      return;
    }
    final currentName = _deviceName ?? defaultName;
    final result = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppColor.of(context).bgRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (sheetContext) => _NameSheet(
        currentName: currentName,
        connectedComputerName: _connectedHostName,
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    if (result == currentName) {
      return; // Name unchanged: nothing is written, no snackbar.
    }
    final writeResult = await widget.plainStore.setDeviceName(result);
    if (!mounted) {
      return;
    }
    if (writeResult case Err()) {
      _showSnackbar(_saveFailedSnackbar);
      return;
    }
    setState(() => _deviceName = result);
    final hostName = _connectedHostName;
    _showSnackbar(
      hostName == null
          ? 'Saved.'
          : 'Saved. $hostName shows it after the next connection.',
    );
  }

  void _showSnackbar(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final title = Text(
      'Settings',
      style: AppType.title.copyWith(color: color.fgPrimary),
    );

    // R-03-107 (amended 2026-09-09): a screen with content paints plain
    // `color.bg.base`, no ground grid and no paper block. Every section
    // brings the `space.6` group gap of R-30-231 above it, so the list adds
    // no top inset: the insecure strip sits flush under the app bar
    // (callout 7) and the first header lands at the group gap. Every row is
    // a `ChromeListRow`, the platform tile of R-33-073 (amended 2026-09-08):
    // on iOS a `CupertinoListTile` whose section draws the one separator, so
    // `showDivider` reaches Android only, where the last row of every section
    // carries none (R-32-515). The two inline blocks of `APPEARANCE` are not
    // rows (R-33-073 item 2); the `Status colours` row between them is one
    // (R-03-106, decided 2026-09-09 by the product owner): it sits under
    // `Theme`, whose line says the terminal palette follows the theme, because
    // the status hues follow it too, and it pushes the legend of
    // `docs/31-mockups/20-status-legend.md`.
    final body = SafeArea(
      child: CustomScrollView(
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.only(bottom: AppSpace.space4),
            sliver: SliverList.list(
              children: <Widget>[
                ChromeSettingsSection(
                  header: 'APPEARANCE',
                  rows: <Widget>[
                    _ThemeRow(
                      themeMode: _settings.themeMode,
                      onChanged: _onThemeModeChanged,
                    ),
                    ChromeListRow.push(
                      title: 'Status colours',
                      onTap: widget.onOpenStatusColours,
                    ),
                    _TerminalSizeRow(
                      size: _settings.terminalTextSize,
                      themeMode: _settings.themeMode,
                      onChanged: _onTerminalSizeChanged,
                    ),
                  ],
                ),
                ChromeSettingsSection(
                  header: 'FEEL',
                  rows: <Widget>[
                    ChromeListRow.toggle(
                      title: 'Haptics',
                      value: _settings.hapticsEnabled,
                      onChanged: _onHapticsChanged,
                    ),
                    ChromeListRow.toggle(
                      title: 'Key press haptics',
                      value:
                          _settings.hapticsEnabled &&
                          _settings.keyPressHapticsEnabled,
                      onChanged: _settings.hapticsEnabled
                          ? _onKeyHapticsChanged
                          : null,
                    ),
                  ],
                ),
                ChromeSettingsSection(
                  header: 'THIS PHONE',
                  rows: <Widget>[
                    ChromeListRow.action(
                      title: "This phone's name",
                      // decided 2026-09-03 by the product owner: stored name or the
                      // device model (R-31-14-05/R-31-15-15), never an ellipsis.
                      subtitle: _deviceName ?? _deviceModelName ?? '',
                      actionLabel: 'Edit',
                      onTap: _openNameSheet,
                      showDivider: false,
                    ),
                  ],
                ),
                ChromeSettingsSection(
                  header: 'SECURITY',
                  rows: <Widget>[
                    _AppLockRow(
                      appLockEnabled: _settings.appLockEnabled,
                      deviceLockAvailable: _deviceLockAvailable,
                      onChanged: _onAppLockChanged,
                    ),
                  ],
                ),
                // `Alerts` and `About` are single rows with no group header, as the
                // wireframe of `docs/31-mockups/15-appearance.md` draws them
                // (decided 2026-09-03 by the product owner: a `MORE` header read as
                // an action and did nothing). Each is its own headerless section, so
                // the platform list gap separates it from its neighbours (R-33-073),
                // and no section nests inside another (R-32-563).
                ChromeSettingsSection(
                  rows: <Widget>[
                    ChromeListRow.push(
                      title: 'Alerts',
                      onTap: widget.onOpenAlerts,
                      showDivider: false,
                    ),
                  ],
                ),
                if (_connectedHostId case final String hostId)
                  ChromeSettingsSection(
                    header: 'ON THE CONNECTED COMPUTER',
                    rows: <Widget>[
                      ChromeListRow.static(title: _connectedHostName ?? hostId),
                      ChromeListRow.push(
                        title: 'Phones on this computer',
                        onTap: widget.onOpenDevices == null
                            ? null
                            : () => widget.onOpenDevices!(hostId),
                      ),
                      ChromeListRow.push(
                        title: 'Connection',
                        onTap: widget.onOpenDiagnostics == null
                            ? null
                            : () => widget.onOpenDiagnostics!(hostId),
                        showDivider: false,
                      ),
                    ],
                  ),
                ChromeSettingsSection(
                  rows: <Widget>[
                    ChromeListRow.push(
                      title: 'About',
                      onTap: widget.onOpenAbout,
                      showDivider: false,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // R-32-115, R-32-510: `color.bg.base` with a `border.hairline` `color.border.strong`
    // bottom edge on both platforms, like every other app bar.
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
}

/// A labelled inline control (callouts 8 and 9): the label in `type.body.strong`, the control
/// under it, then one `type.caption` line, `space.2` between the three and `space.4` above and
/// below the block, which is the text inset of the two-line rows beside it. The label is not a
/// list row of its own (amended 2026-09-08 by the product owner: a full row with a divider cut
/// the label from its control and left 24 px under `Theme` while `Relay address` sat tight).
/// When [value] is set, it sits at the trailing edge of the label's line, on the label's
/// baseline, in `type.caption` `color.fg.secondary` (R-03-110: `13 pt` beside
/// `Terminal text size`).
class _InlineControlBlock extends StatelessWidget {
  const _InlineControlBlock({
    required this.label,
    this.value,
    required this.control,
    required this.caption,
  });

  final String label;
  final String? value;
  final Widget control;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final Widget title = Text(
      label,
      style: AppType.bodyStrong.copyWith(color: color.fgPrimary),
    );
    return Padding(
      padding: const EdgeInsets.all(AppSpace.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (value == null)
            title
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Expanded(child: title),
                Text(
                  value!,
                  style: AppType.caption.copyWith(color: color.fgSecondary),
                ),
              ],
            ),
          const SizedBox(height: AppSpace.space2),
          control,
          const SizedBox(height: AppSpace.space2),
          Text(
            caption,
            style: AppType.caption.copyWith(color: color.fgSecondary),
          ),
        ],
      ),
    );
  }
}

/// The theme row: the segmented control of R-32-520 always visible under its label, then the
/// one line R-31-15-05 requires. decided 2026-09-03 by the product owner: no expand/collapse and
/// no trailing value word.
class _ThemeRow extends StatelessWidget {
  const _ThemeRow({required this.themeMode, required this.onChanged});

  final AppThemeMode themeMode;
  final void Function(AppThemeMode) onChanged;

  @override
  Widget build(BuildContext context) => _InlineControlBlock(
    label: 'Theme',
    control: _SegmentedThemeControl(value: themeMode, onChanged: onChanged),
    caption: _themePaletteLine,
  );
}

/// The theme control, the platform's own segmented control (R-03-059, decided 2026-09-09 by the
/// product owner): three segments `System`, `Light`, `Dark` (R-31-15-05). On Android a
/// `SegmentedButton` takes its type, fill, ink and boundary from `segmentedButtonTheme` in
/// `app.dart` and keeps the component's own height and stadium shape (the R-03-059 addendum of
/// 2026-09-09: the theme sets colours and type only); on iOS a
/// `CupertinoSlidingSegmentedControl` keeps the component's own height, thumb and track, because
/// `cupertino_ui` 1.0.1 has no theme slot for it. Both fill the block's width, so the three
/// segments share it equally, as callout 8 draws them. The selected segment is the one the
/// platform marks, and the semantics state `selected` comes with it (R-32-520).
class _SegmentedThemeControl extends StatelessWidget {
  const _SegmentedThemeControl({required this.value, required this.onChanged});

  final AppThemeMode value;
  final void Function(AppThemeMode) onChanged;

  @override
  Widget build(BuildContext context) {
    if (_isIos) {
      return SizedBox(
        width: double.infinity,
        child: CupertinoSlidingSegmentedControl<AppThemeMode>(
          groupValue: value,
          onValueChanged: (AppThemeMode? mode) {
            if (mode != null) onChanged(mode);
          },
          children: <AppThemeMode, Widget>{
            for (final AppThemeMode mode in AppThemeMode.values)
              mode: Text(_themeSegmentLabel(mode)),
          },
        ),
      );
    }
    return SegmentedButton<AppThemeMode>(
      segments: <ButtonSegment<AppThemeMode>>[
        for (final AppThemeMode mode in AppThemeMode.values)
          ButtonSegment<AppThemeMode>(
            value: mode,
            label: Text(_themeSegmentLabel(mode)),
          ),
      ],
      selected: <AppThemeMode>{value},
      onSelectionChanged: (Set<AppThemeMode> selection) =>
          onChanged(selection.single),
      expandedInsets: EdgeInsets.zero,
    );
  }
}

/// The terminal size block (callouts 9 to 11, R-03-110): the title row with the value `13 pt`
/// at its trailing edge, the platform slider, the live preview and the independence line of
/// R-31-15-02, always visible. decided 2026-09-03 by the product owner: no expand/collapse.
class _TerminalSizeRow extends StatelessWidget {
  const _TerminalSizeRow({
    required this.size,
    required this.themeMode,
    required this.onChanged,
  });

  final int size;
  final AppThemeMode themeMode;
  final void Function(int) onChanged;

  @override
  Widget build(BuildContext context) {
    final Brightness? brightnessOverride = switch (themeMode) {
      AppThemeMode.light => Brightness.light,
      AppThemeMode.dark => Brightness.dark,
      AppThemeMode.system => null,
    };
    Widget preview = _TerminalPreview(size: size);
    if (brightnessOverride != null) {
      preview = MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(platformBrightness: brightnessOverride),
        child: preview,
      );
    }
    return _InlineControlBlock(
      label: 'Terminal text size',
      value: '$size pt',
      control: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _TerminalSizeSlider(size: size, onChanged: onChanged),
          const SizedBox(height: AppSpace.space2),
          preview,
        ],
      ),
      caption: _terminalSizeIndependenceLine,
    );
  }
}

/// The discrete platform slider of R-03-110 (decided 2026-09-09 by the product owner, who
/// called the `aA` glyph, two buttons, a spacer and the value a weird layout): a `Slider` on
/// Android in the theme's M3 default colours, a `CupertinoSlider` on iOS, each in the
/// component's own shape and size (R-03-059). Its stops are exactly the permitted sizes of
/// R-21-010 (`AppType.monoTerminalSizes`, R-32-208), so the slider moves over their indices and
/// no size between two stops exists. No `label`, so no value bubble: the block's title row
/// carries the value. One merged semantics node speaks `Terminal text size, 13 points`
/// (R-32-505) with the slider's own increase and decrease actions.
class _TerminalSizeSlider extends StatelessWidget {
  const _TerminalSizeSlider({required this.size, required this.onChanged});

  final int size;
  final void Function(int) onChanged;

  static const List<int> _sizes = AppType.monoTerminalSizes;

  static String _points(int index) => '${_sizes[index]} points';

  @override
  Widget build(BuildContext context) {
    final int index = _sizes.indexOf(size);
    final double max = (_sizes.length - 1).toDouble();
    void onSlide(double value) {
      final int next = _sizes[value.round()];
      if (next != size) onChanged(next);
    }

    final Widget slider = _isIos
        ? CupertinoSlider(
            value: index.toDouble(),
            max: max,
            divisions: _sizes.length - 1,
            onChanged: onSlide,
          )
        : Slider(
            value: index.toDouble(),
            max: max,
            divisions: _sizes.length - 1,
            onChanged: onSlide,
          );
    return MergeSemantics(
      child: Semantics(
        label: 'Terminal text size',
        value: _points(index),
        increasedValue: _points((index + 1).clamp(0, _sizes.length - 1)),
        decreasedValue: _points((index - 1).clamp(0, _sizes.length - 1)),
        child: slider,
      ),
    );
  }
}

/// The live terminal preview of section 7.22 (callout 11): two real rows in
/// `type.mono.terminal` on `color.term.bg` with `color.term.fg`, `radius.md`, `border.hairline`
/// in `color.border.strong`, `space.3` by `space.2` inside the boundary (R-32-301).
class _TerminalPreview extends StatelessWidget {
  const _TerminalPreview({required this.size});

  final int size;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final style = AppType.monoTerminal(size: size)
        .copyWith(color: color.termFg);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.space3,
        vertical: AppSpace.space2,
      ),
      decoration: BoxDecoration(
        color: color.termBg,
        border: Border.all(
          color: color.borderStrong,
          width: AppBorder.hairline,
        ),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(r'$ dotnet test', style: style),
          Text('Passed!  Failed: 0, Passed: 412', style: style),
        ],
      ),
    );
  }
}

/// App Lock row, the one row of `SECURITY`, so it carries no divider; the `No screen lock`
/// message sits under it at the row's text inset when the phone has no screen lock. The row is
/// the toggle tile of R-33-073 through `ChromeListRow.toggle` (amended 2026-09-08), which owns
/// the switch row of R-32-522 and its `<label>, on` or `<label>, off` semantics (R-32-505).
class _AppLockRow extends StatelessWidget {
  const _AppLockRow({
    required this.appLockEnabled,
    required this.deviceLockAvailable,
    required this.onChanged,
  });

  final bool appLockEnabled;
  final bool deviceLockAvailable;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    if (deviceLockAvailable) {
      return ChromeListRow.toggle(
        title: 'App Lock',
        value: appLockEnabled,
        onChanged: onChanged,
        showDivider: false,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ChromeListRow.toggle(
          title: 'App Lock',
          value: appLockEnabled,
          onChanged: null,
          showDivider: false,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.space4,
            0,
            AppSpace.space4,
            AppSpace.space2,
          ),
          child: Text(
            _noScreenLockMessage,
            style: AppType.caption.copyWith(color: color.fgSecondary),
          ),
        ),
      ],
    );
  }
}

/// Callout 16: the name sheet, R-31-15-13/14/15. `Save` stays disabled while the trimmed name
/// is empty or exceeds [_deviceNameByteLimit] UTF-8 bytes.
class _NameSheet extends StatefulWidget {
  const _NameSheet({
    required this.currentName,
    required this.connectedComputerName,
  });

  final String currentName;
  final String? connectedComputerName;

  @override
  State<_NameSheet> createState() => _NameSheetState();
}

class _NameSheetState extends State<_NameSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.currentName,
  );

  /// Held by the state, never built in `build`: a node created per rebuild loses focus and
  /// closes the keyboard on the first keystroke, because `onChanged` rebuilds the sheet.
  final FocusNode _focusNode = FocusNode(debugLabel: 'settings-device-name');

  int get _byteLength => utf8.encode(_controller.text.trim()).length;
  bool get _isEmpty => _controller.text.trim().isEmpty;
  bool get _isTooLong => _byteLength > _deviceNameByteLimit;
  bool get _canSave => !_isEmpty && !_isTooLong;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String get _hint {
    final computer = widget.connectedComputerName;
    if (computer == null) {
      return 'The next computer you connect sees this name.';
    }
    return 'The name your computers show for this phone. $computer shows it '
        'after the next connection.';
  }

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.space4,
            AppSpace.space2,
            AppSpace.space4,
            AppSpace.space4,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const _GrabHandle(),
              const SizedBox(height: AppSpace.space4),
              Text(
                "This phone's name",
                style: AppType.heading.copyWith(color: color.fgPrimary),
              ),
              const SizedBox(height: AppSpace.space3),
              InputField(
                controller: _controller,
                focusNode: _focusNode,
                placeholder: 'Enter name',
                padding: EdgeInsets.zero,
                liftsAboveKeyboard: false,
                onChanged: (_) => setState(() {}),
                errorText: _isTooLong ? _nameTooLongText : null,
              ),
              const SizedBox(height: AppSpace.space2),
              _isTooLong
                  ? const Treatment.error(label: _nameTooLongText)
                  : Text(
                      _hint,
                      style: AppType.caption.copyWith(color: color.fgSecondary),
                    ),
              const SizedBox(height: AppSpace.space4),
              AppFilledButton(
                label: 'Save',
                onPressed: _canSave
                    ? () => Navigator.of(context).pop(_controller.text.trim())
                    : null,
              ),
              const SizedBox(height: AppSpace.space2),
              Center(
                child: AppTextButton(
                  label: 'Cancel',
                  subdued: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The grab handle: `size.grab` at `radius.full` in `color.fg.disabled`, mirroring
/// `create_sheet.dart`'s own private `_GrabHandle` copy (R-32-546).
class _GrabHandle extends StatelessWidget {
  const _GrabHandle();

  @override
  Widget build(BuildContext context) => Center(
    child: ExcludeSemantics(
      child: Container(
        width: AppSize.grabWidth,
        height: AppSize.grabHeight,
        decoration: BoxDecoration(
          color: AppColor.of(context).fgDisabled,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
      ),
    ),
  );
}
