/// The application root, per `docs/90-implementation-plan.md` `WP-12-b`:
/// one `MaterialApp.router` wired to the `go_router` configuration of
/// `routing.dart`, the Riverpod root, and the one chrome `ColorScheme`
/// this app builds. Both platforms use the fixed Herdr palette.
library;

import 'dart:async' show StreamSubscription, unawaited;

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoTextThemeData, CupertinoThemeData;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart'
    show DefaultMaterialLocalizations, DefaultWidgetsLocalizations;
import 'package:flutter/services.dart' show MethodChannel, SystemUiOverlayStyle;
import 'package:flutter/widgets.dart'
    show
        AnnotatedRegion,
        AppLifecycleState,
        AsyncSnapshot,
        BorderSide,
        Brightness,
        BuildContext,
        Center,
        Color,
        ColoredBox,
        DefaultTextStyle,
        ExcludeFocus,
        ExcludeSemantics,
        FocusManager,
        Icon,
        MediaQuery,
        Offstage,
        Stack,
        StackFit,
        SizedBox,
        StreamBuilder,
        Text,
        TextStyle,
        TickerMode,
        WidgetState,
        WidgetStateProperty,
        WidgetStatePropertyAll,
        WidgetStatesConstraint,
        WidgetsBinding,
        WidgetsBindingObserver;
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart'
    show
        BottomSheetThemeData,
        ButtonStyle,
        ColorScheme,
        Colors,
        FilledButtonThemeData,
        FloatingActionButtonThemeData,
        IconButtonThemeData,
        IconThemeData,
        LocalizationsDelegate,
        MaterialApp,
        NavigationBarThemeData,
        NavigationDestinationLabelBehavior,
        NoSplash,
        OutlinedButtonThemeData,
        SearchViewThemeData,
        SegmentedButtonThemeData,
        State,
        StatefulWidget,
        StatelessWidget,
        SwitchThemeData,
        TabBarThemeData,
        TextButtonThemeData,
        Theme,
        ThemeData,
        ThemeMode,
        Widget;

import 'core/result/result.dart';
import 'routing.dart';
import 'screens/lock_screen.dart';
import 'services/app_settings.dart'
    show AppSettings, AppSettingsService, AppThemeMode;
import 'services/biometric_gate.dart' show BiometricGate;
import 'services/frame_presentation.dart' show RasterizedFrame;
import 'services/notifications.dart';
import 'services/plain_store.dart' show PairedHostRecord, PlainStore;
import 'services/relay.dart'
    show RelayConnected, RelayConnection, RelayConnectionState;
import 'widgets/theme/app_color.dart';
import 'widgets/theme/app_radius.dart' show AppBorder;
import 'widgets/theme/app_size.dart';
import 'widgets/theme/app_type.dart';
import 'widgets/theme/chrome_scheme.dart';
import 'widgets/theme/chrome_snackbar.dart' show chromeSnackbarTheme;

/// SDK `MaterialLocalizations`, added alongside `material_ui`'s own
/// auto-appended delegate, never replacing it. `AdaptiveTextSelectionToolbar`
/// (`package:flutter/material.dart`, R-21-042,
/// `app/lib/widgets/terminal_view_widget.dart` `WP-16-b`) looks up the SDK's
/// own `MaterialLocalizations` type by identity, a different type from
/// `material_ui`'s reimplementation. `test/widgets/terminal_isolated_test.dart`
/// found and worked around this gap locally; this is the real fix.
/// `test/screens/golden_support.dart`'s `goldenApp` reuses this list so a
/// golden renders under the same delegates as the real app root.
const List<LocalizationsDelegate<dynamic>> sdkMaterialLocalizations =
    <LocalizationsDelegate<dynamic>>[
      DefaultWidgetsLocalizations.delegate,
      DefaultMaterialLocalizations.delegate,
    ];

/// The Riverpod and `go_router` root. `main.dart` (`WP-0-b`) calls only
/// `runApp(const HerdrRemoteApp())`.
class HerdrRemoteApp extends StatelessWidget {
  const HerdrRemoteApp({super.key});

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [appLockOverlayProvider.overrideWithValue(true)],
    child: const _AppRoot(),
  );
}

/// One `NotificationsService` for whole app session (`WP-19-a`,
/// `docs/22-platform-integration.md` §3): built once here, `initialize()`
/// called once on mount, and `onNotificationTapped` wired to
/// `routing.dart`'s `routeNotificationTap` through `rootNavigatorKey`.
/// `notifications.dart` holds no `go_router`/`BuildContext` import by its
/// own design, so this composition root supplies both.
class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

/// Also the one `WidgetsBindingObserver` of the session: every lifecycle
/// change goes to `BiometricGate.noteLifecycleChange` (R-22-017, the
/// background relock) and `RelayConnection.noteLifecycleChange` (R-22-025,
/// R-22-026, close on background and resume on foreground), and every
/// `RelayConnected` to not-connected transition writes the R-13-065 last-seen
/// time of the computer whose link just closed, which R-31-05-16 orders the
/// cold-start attempt by.
class _AppRootState extends State<_AppRoot> with WidgetsBindingObserver {
  late final NotificationsService _notifications = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(notificationsServiceProvider);
  late final AppSettingsService _appSettings = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(appSettingsServiceProvider);
  late final RelayConnection _connection = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(relayConnectionProvider);
  late final BiometricGate _gate = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(biometricGateProvider);

  StreamSubscription<RelayConnectionState>? _connectionSub;

  /// The computer of the live session, kept so its last-seen time can be
  /// written when the link closes, when `lastHostInfo` may already be gone.
  String? _connectedHostId;
  bool _ready = false;
  bool _loadFailed = false;
  bool _hasSavedHosts = true;
  bool _obscured = false;
  ({String hostId, String paneId})? _pendingNotification;
  RasterizedFrame? _privacyFrame;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notifications.onNotificationTapped = (hostId, paneId) {
      _pendingNotification = (hostId: hostId, paneId: paneId);
      _deliverPendingNotification();
    };
    unawaited(_notifications.initialize());
    _connectionSub = _connection.connectionState.listen(_onConnectionState);
    unawaited(_loadLockPolicy());
  }

  Future<void> _loadLockPolicy() async {
    final settings = await _appSettings.load();
    final hosts = await PlainStore().pairedHosts();
    if (!mounted) return;
    if (settings is! Ok<AppSettings> || hosts is! Ok<List<PairedHostRecord>>) {
      // Never substitute the fresh-install defaults for an unreadable lock policy.
      setState(() => _loadFailed = true);
      return;
    }
    _hasSavedHosts = hosts.value.isNotEmpty;
    _gate.addListener(_lockChanged);
    appRouter.routerDelegate.addListener(_routeChanged);
    setState(() => _ready = true);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _deliverPendingNotification(),
    );
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      unawaited(_releaseNativePrivacyCover());
    }
  }

  void _lockChanged() {
    if (mounted) setState(() {});
  }

  void _routeChanged() {
    _lockChanged();
    if (!_hasSavedHosts) unawaited(_refreshSavedHosts());
    if (_pendingNotification != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _deliverPendingNotification(),
      );
    }
  }

  void _deliverPendingNotification() {
    if (!mounted || !_ready) return;
    final navigatorContext = rootNavigatorKey.currentContext;
    final notification = _pendingNotification;
    if (navigatorContext == null || notification == null) return;
    _pendingNotification = null;
    routeNotificationTap(
      navigatorContext,
      hostId: notification.hostId,
      paneId: notification.paneId,
    );
  }

  Future<void> _refreshSavedHosts() async {
    final hosts = await PlainStore().pairedHosts();
    if (!mounted) return;
    if (hosts is! Ok<List<PairedHostRecord>> || hosts.value.isNotEmpty) {
      setState(() => _hasSavedHosts = true);
    }
  }

  @override
  void dispose() {
    _privacyFrame?.cancel();
    _notifications.onNotificationTapped = null;
    WidgetsBinding.instance.removeObserver(this);
    if (_ready) {
      _gate.removeListener(_lockChanged);
      appRouter.routerDelegate.removeListener(_routeChanged);
    }
    unawaited(_connectionSub?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_ready) return;
    _privacyFrame?.cancel();
    _gate.noteLifecycleChange(state);
    unawaited(_connection.noteLifecycleChange(state));
    setState(() => _obscured = state != AppLifecycleState.resumed);
    if (_obscured) {
      FocusManager.instance.primaryFocus?.unfocus();
    } else {
      unawaited(_releaseNativePrivacyCover());
    }
  }

  Future<void> _releaseNativePrivacyCover() async {
    _privacyFrame?.cancel();
    final frame = _privacyFrame = RasterizedFrame();
    if (!await frame.ready || !mounted || _obscured) return;
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android) {
      await const MethodChannel('dev.herdr.herdr_mobile/biometric_lock')
          .invokeMethod<void>('frameReady');
    }
  }

  void _onConnectionState(RelayConnectionState state) {
    if (state is RelayConnected) {
      final String? connected =
          _connection.lastHostInfo?.hostId ?? _connectedHostId;
      _connectedHostId = connected;
      // Stamped on connect as well as on close: a killed app (swipe-away,
      // low memory) never closes its link, and without a stamp the cold start
      // of R-31-05-16 read the computer as "never connected" and made no
      // attempt (measured on the emulator, 2026-09-03).
      if (connected != null) unawaited(_recordLinkSeen(connected));
      return;
    }
    final String? closed = _connectedHostId;
    if (closed == null) return;
    _connectedHostId = null;
    unawaited(_recordLinkSeen(closed));
  }

  /// R-13-065: the time of the last contact with that computer, written when the
  /// link opens and again when it closes. Field-specific and serialized inside the
  /// store, so it never overwrites a concurrent `host_name` refresh.
  Future<void> _recordLinkSeen(String hostId) =>
      PlainStore().updateLastSeen(hostId, DateTime.now());

  @override
  Widget build(BuildContext context) => StreamBuilder<AppSettings>(
    stream: _appSettings.changes,
    initialData: _appSettings.current,
    builder: (BuildContext context, AsyncSnapshot<AppSettings> snapshot) =>
        _FixedChromeApp(
          themeMode: themeModeOf(snapshot.requireData.themeMode),
          ready: _ready,
          loadFailed: _loadFailed,
          gate: _ready ? _gate : null,
          obscured: _obscured,
          hasSavedHosts: _hasSavedHosts,
        ),
  );
}

/// R-22-051: `System` follows the operating system; `Light` and `Dark` force one theme.
ThemeMode themeModeOf(AppThemeMode mode) => switch (mode) {
  AppThemeMode.system => ThemeMode.system,
  AppThemeMode.light => ThemeMode.light,
  AppThemeMode.dark => ThemeMode.dark,
};

/// Both platforms: the fixed Herdr chrome scheme. No dynamic colour, no wallpaper scheme.
/// [ResolvedChrome] wraps every route, per R-22-054.
class _FixedChromeApp extends StatelessWidget {
  const _FixedChromeApp({
    required this.themeMode,
    required this.ready,
    required this.loadFailed,
    required this.gate,
    required this.obscured,
    required this.hasSavedHosts,
  });

  final ThemeMode themeMode;
  final bool ready;
  final bool loadFailed;
  final BiometricGate? gate;
  final bool obscured;
  final bool hasSavedHosts;

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    routerConfig: appRouter,
    themeMode: themeMode,
    localizationsDelegates: sdkMaterialLocalizations,
    theme: appThemeFrom(ChromeScheme.fixed(Brightness.light)),
    darkTheme: appThemeFrom(ChromeScheme.fixed(Brightness.dark)),
    builder: (BuildContext context, Widget? child) {
      if (!ready) {
        return ResolvedChrome(
          child: ColoredBox(
            color: AppColor.of(context).bgBase,
            child: loadFailed
                ? const Center(
                    child: Text(
                      'Unable to load App Lock settings. Reopen the app.',
                    ),
                  )
                : const SizedBox.expand(),
          ),
        );
      }
      final path = appRouter.routerDelegate.currentConfiguration.uri.path;
      final onboarding =
          !hasSavedHosts &&
          (path == '/' ||
              path.startsWith('/welcome') ||
              path.startsWith('/pair/'));
      final locked = gate!.isLocked && !onboarding;
      final hidden = locked || (obscured && gate!.appLockEnabled);
      return ResolvedChrome(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ExcludeFocus(
              excluding: hidden,
              child: ExcludeSemantics(
                excluding: hidden,
                child: TickerMode(
                  enabled: !hidden,
                  child: Offstage(offstage: hidden, child: child!),
                ),
              ),
            ),
            if (locked) LockScreen(gate: gate!, onUnlocked: completeAppUnlock),
            if (!locked && hidden)
              const LockScreenBody(
                phase: LockScreenPhase.checking,
                biometric: BiometricPresentation(
                  glyph: Symbols.lock_rounded,
                  label: 'Unlock with biometrics',
                ),
              ),
          ],
        ),
      );
    },
  );
}

/// The `MaterialApp.builder` body. It runs under the resolved `Theme`, so it reads that
/// brightness, not the platform's: with a forced `Light` or `Dark` mode the two differ
/// (R-22-051). It applies the system-bar style of R-22-054 and overrides
/// `MediaQuery.platformBrightness` with the resolved value, so `AppColor.of(context)` and the
/// terminal (R-32-013) agree with the chrome in every mode. `AnnotatedRegion` re-applies on
/// every rebuild, so a mode or system change takes effect without a restart.
/// It sets the one app-wide `DefaultTextStyle` (`type.body` in `color.fg.primary`) because
/// `CupertinoPageScaffold` sets none. This fixes R-41-020; the QR scan iOS golden measured
/// 1268 yellow pixels before and 0 after on 2026-09-08.
class ResolvedChrome extends StatelessWidget {
  const ResolvedChrome({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final AppColor tokens = AppColor.resolve(brightness);
    final Brightness iconBrightness = brightness == Brightness.dark
        ? Brightness.light
        : Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: iconBrightness,
        statusBarBrightness: brightness,
        systemNavigationBarColor: tokens.bgBase,
        systemNavigationBarDividerColor: tokens.bgBase,
        systemNavigationBarIconBrightness: iconBrightness,
        // Android 15+ draws an opaque scrim behind the three-button bar unless the app
        // opts out; the app's own `bgBase` shows through instead, per R-22-054.
        systemNavigationBarContrastEnforced: false,
      ),
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(platformBrightness: brightness),
        child: DefaultTextStyle(
          style: AppType.body.copyWith(color: tokens.fgPrimary),
          child: child,
        ),
      ),
    );
  }
}

/// `opacity.press`, per the opacity table beside R-32-330: the
/// `color.fg.primary` overlay R-32-501 lays over an `accent.primary` fill
/// while it is pressed. Every opacity stays a local constant beside its
/// one caller, per the border-width precedent of `app_elev.dart`.
const double _opacityPress = 0.12;

/// `opacity.disabled`, per the opacity table beside R-32-330: a disabled
/// button keeps its colours and takes this opacity, per R-32-502.
const double _opacityDisabled = 0.38;

/// The shared filled icon colours keep the standard icon theme unchanged.
ButtonStyle? appFilledIconButtonStyle(BuildContext context) =>
    Theme.of(context).filledButtonTheme.style;

/// The native tonal icon button uses the raised field fill.
ButtonStyle appTonalIconButtonStyle(BuildContext context) {
  final AppColor color = AppColor.of(context);
  return ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith<Color>(
      (states) => color.bgHigh.withValues(
        alpha: states.contains(WidgetState.disabled) ? 0.38 : 1,
      ),
    ),
    foregroundColor: WidgetStateProperty.resolveWith<Color>(
      (states) => color.accentText.withValues(
        alpha: states.contains(WidgetState.disabled) ? 0.38 : 1,
      ),
    ),
  );
}

/// Material 3 stays enabled by the SDK default; this file never sets it
/// false. A widget under `lib/widgets/theme/` reads its own colour from
/// `AppColor` directly, per R-32-005, so this `ThemeData` exists only to
/// give the stock Material and Cupertino components this app uses a
/// consistent baseline, not as a second source of token values.
///
/// `fontFamily` and `cupertinoOverrideTheme.textTheme.textStyle` both pin
/// `AppType.interfaceFontFamily`: the one app-wide default for any bare
/// `Text()` that carries no `AppType` token style, on both the Material
/// `DefaultTextStyle` path and the Cupertino widgets (iOS
/// `ChromeListRow`/`CupertinoListTile` and friends, per
/// `docs/33-platform-chrome.md`) that otherwise fall back to
/// `CupertinoSystemText`, a family this app never bundles. A widget styled
/// with `AppType` is unaffected either way, per R-32-005. The colour is `color.fg.primary` per docs/32 section 7.4 so a Cupertino tile title reads on both cards (2026-09-08).
///
/// Additional theme properties per `docs/32-design-language.md` section 6:
/// `scaffoldBackgroundColor`, `dividerColor`, `splashFactory: NoSplash.splashFactory`,
/// `navigationBarTheme`, `switchTheme`.
///
/// Every button is the platform's own widget, per
/// `docs/03-product-decisions.md` R-03-059, and its tokens reach it through
/// this theme only (2026-09-09). On Android that is `filledButtonTheme`
/// (docs/32 section 7.8), `textButtonTheme` (R-32-526),
/// `outlinedButtonTheme` (section 7.28), `iconButtonTheme` and
/// `segmentedButtonTheme` (sections 7.6 and 7.22): fill, ink, the pressed
/// overlay of R-32-501 and the disabled dim of R-32-502, and nothing else.
/// A button label is the platform's own label style, per R-03-104
/// (2026-09-09, the product owner's look at the Notifications strip): the
/// three button themes set no `textStyle`, so a Material 3 button draws
/// `labelLarge` in the interface family this theme sets, as written; until
/// then they set `type.mono.button` and the widgets upper-cased the label.
/// The R-03-059 addendum (2026-09-09, the product owner's second look
/// at the stepper) keeps the platform's own shape, size and layout: no
/// `shape`, `minimumSize`, `fixedSize` or `padding` here, so a Material 3
/// button is its own pill, an icon button its own circle and a segmented
/// control its own stadium. On iOS it is `CupertinoThemeData.primaryColor`
/// (the filled and tinted fill, the plain ink), `primaryContrastingColor`
/// (the filled label) and `textTheme.actionTextStyle` (the component's own
/// action style in the interface family, per R-03-104); `cupertino_ui`
/// 1.0.1 has no theme slot for a button's size or radius, so an iOS button
/// keeps the component's own, as R-32-588 already lets the create control
/// do.
///
/// Public so a golden test renders a screen under the one real theme, not a
/// bare `ThemeData` whose stock widgets fall back to a family the test
/// bundle never loads.
ThemeData appThemeFrom(ColorScheme colorScheme) {
  final AppColor tokens = AppColor.resolve(colorScheme.brightness);

  // R-32-502 through the theme: a disabled button keeps its colour and
  // takes `opacity.disabled`, so a disabled fill, label or border is the
  // same token dimmed, never a second colour (R-32-331).
  WidgetStateProperty<Color> dimmed(Color color) =>
      WidgetStateProperty<Color>.fromMap(<WidgetStatesConstraint, Color>{
        WidgetState.disabled: color.withValues(alpha: _opacityDisabled),
        WidgetState.any: color,
      });

  // R-32-501 as the platform's own ink: the overlay a Material button lays
  // over itself while pressed or focused (R-32-503 lets a platform button
  // keep its own focus response). No hover state, per R-30-718.
  WidgetStateProperty<Color?> pressedOverlay(Color color) =>
      WidgetStateProperty<Color?>.fromMap(<WidgetStatesConstraint, Color?>{
        WidgetState.pressed | WidgetState.focused: color,
      });

  return ThemeData(
    colorScheme: colorScheme,
    fontFamily: AppType.interfaceFontFamily,
    scaffoldBackgroundColor: tokens.bgBase,
    dividerColor: tokens.borderSubtle,
    splashFactory: NoSplash.splashFactory,
    snackBarTheme: chromeSnackbarTheme(tokens),
    // R-33-033's `Content sheet` and `Confirmation` rows: the Material 3 sheet and dialog keep
    // the component's own shape, surface and elevation; the theme sets only the drag handle,
    // so every modal sheet the app opens carries it.
    bottomSheetTheme: const BottomSheetThemeData(showDragHandle: true),
    cupertinoOverrideTheme: CupertinoThemeData(
      textTheme: CupertinoTextThemeData(
        textStyle: TextStyle(
          fontFamily: AppType.interfaceFontFamily,
          color: tokens.fgPrimary,
        ),
        // The label of every `CupertinoButton`: the component's own action
        // style, 17 with the platform's tracking, in the interface family,
        // per R-03-104 and R-32-212 (2026-09-09: until then
        // `type.mono.button`). The button sets the colour itself.
        actionTextStyle: const CupertinoTextThemeData().actionTextStyle
            .copyWith(fontFamily: AppType.interfaceFontFamily),
        navActionTextStyle: const CupertinoTextThemeData().navActionTextStyle
            .copyWith(
              fontFamily: AppType.interfaceFontFamily,
              color: tokens.fgPrimary,
            ),
        navTitleTextStyle: const CupertinoTextThemeData().navTitleTextStyle
            .copyWith(
              fontFamily: AppType.interfaceFontFamily,
              color: tokens.fgPrimary,
            ),
        navLargeTitleTextStyle: const CupertinoTextThemeData()
            .navLargeTitleTextStyle
            .copyWith(
              fontFamily: AppType.interfaceFontFamily,
              color: tokens.fgPrimary,
            ),
      ),
      barBackgroundColor: tokens.bgRaised,
      brightness: colorScheme.brightness,
      primaryColor: tokens.accentPrimary,
      // The label of `CupertinoButton.filled`, per R-32-525.
      primaryContrastingColor: tokens.fgOnAccent,
      scaffoldBackgroundColor: tokens.bgBase,
    ),
    // Section 7.8: `color.accent.primary` fill, `color.fg.on_accent` label;
    // pressed is R-32-501's second case, the fill under `color.fg.primary`
    // at `opacity.press`. Height, radius, inset and label type are the
    // component's own.
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: dimmed(tokens.accentPrimary),
        foregroundColor: dimmed(tokens.fgOnAccent),
        overlayColor: pressedOverlay(
          tokens.fgPrimary.withValues(alpha: _opacityPress),
        ),
      ),
    ),
    // R-32-526: `color.accent.text` ink, a `size.icon.md` glyph when it
    // carries one (the R-32-401 map sizes the glyph, not the button);
    // pressed is the `color.accent.soft` wash. The label type is the
    // component's own, per R-03-104.
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: dimmed(tokens.accentText),
        overlayColor: pressedOverlay(tokens.accentSoft),
        iconSize: const WidgetStatePropertyAll<double>(AppSize.iconMd),
      ),
    ),
    // Section 7.28: no fill, `border.hairline` in `color.border.strong`,
    // `color.fg.primary` label in the component's own type; pressed is the
    // `color.accent.soft` wash under a `color.accent.primary` border, per
    // R-32-591.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: dimmed(tokens.fgPrimary),
        overlayColor: pressedOverlay(tokens.accentSoft),
        side: WidgetStateProperty<BorderSide>.fromMap(
          <WidgetStatesConstraint, BorderSide>{
            WidgetState.disabled: BorderSide(
              color: tokens.borderStrong.withValues(alpha: _opacityDisabled),
              width: AppBorder.hairline,
            ),
            WidgetState.pressed: BorderSide(
              color: tokens.accentPrimary,
              width: AppBorder.hairline,
            ),
            WidgetState.any: BorderSide(
              color: tokens.borderStrong,
              width: AppBorder.hairline,
            ),
          },
        ),
      ),
    ),
    // Every `IconButton` form: its glyph `color.fg.primary` (R-32-405 and
    // every icon control of section 7) dimmed when disabled, in the
    // component's own circle. Its fills are the `ColorScheme` roles of
    // `docs/33-platform-chrome.md` section 4 (`secondaryContainer` is
    // Filled icon buttons use appFilledIconButtonStyle below.
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(foregroundColor: dimmed(tokens.fgPrimary)),
    ),
    // Section 7.6's segmented control: `type.label`, `border.hairline` in
    // `color.border.strong`, the selected segment `color.accent.primary`
    // with its label in `color.fg.on_accent`, an unselected one pressing to
    // `color.bg.high` (R-32-501's third case), in the component's own
    // stadium.
    segmentedButtonTheme: SegmentedButtonThemeData(
      // The one icon set of R-32-401: the component's own `Icons.check` is
      // the MaterialIcons font, which the app does not bundle.
      selectedIcon: const Icon(Symbols.check_rounded),
      style: ButtonStyle(
        textStyle: const WidgetStatePropertyAll<TextStyle>(AppType.label),
        backgroundColor: WidgetStateProperty<Color>.fromMap(
          <WidgetStatesConstraint, Color>{
            WidgetState.selected: tokens.accentPrimary,
            WidgetState.any: Colors.transparent,
          },
        ),
        foregroundColor: WidgetStateProperty<Color>.fromMap(
          <WidgetStatesConstraint, Color>{
            WidgetState.selected: tokens.fgOnAccent,
            WidgetState.any: tokens.fgPrimary,
          },
        ),
        overlayColor: WidgetStateProperty<Color?>.fromMap(
          <WidgetStatesConstraint, Color?>{
            WidgetState.selected: Colors.transparent,
            WidgetState.pressed | WidgetState.focused: tokens.bgHigh,
          },
        ),
        side: WidgetStatePropertyAll<BorderSide>(
          BorderSide(color: tokens.borderStrong, width: AppBorder.hairline),
        ),
      ),
    ),
    // Section 7.26 as R-03-102 leaves it (2026-09-09): the Android view switcher of the
    // Agents screen is a `TabBar` of primary tabs. Its indicator is `color.accent.primary`
    // and its labels `color.fg.primary` and `color.fg.secondary` through the `ColorScheme`;
    // its divider is the header block's one edge, `border.hairline` in `color.border.strong`
    // (R-32-582), so the screen draws none of its own.
    tabBarTheme: TabBarThemeData(
      dividerColor: tokens.borderStrong,
      dividerHeight: AppBorder.hairline,
      labelStyle: AppType.label,
      unselectedLabelStyle: AppType.label,
    ),
    // The Material search view of R-03-102 (`SearchAnchor`, the Agents screen's pane search):
    // a full-screen route on `color.bg.base` with no shadow, because a search view is not on
    // the closed list of floating layers R-32-320 permits one, and the header block's edge
    // under its field. The screen sets the placeholder and the view's body only (R-32-598).
    searchViewTheme: SearchViewThemeData(
      backgroundColor: tokens.bgBase,
      elevation: 0,
      dividerColor: tokens.borderStrong,
      headerTextStyle: AppType.body.copyWith(color: tokens.fgPrimary),
      headerHintStyle: AppType.body.copyWith(color: tokens.fgSecondary),
    ),
    // R-32-588 (restored 2026-09-10 per the corrected R-03-109): the create control of the
    // Agents screen is Material's `FloatingActionButton` on both platforms. Fill
    // `color.accent.primary`, glyph `color.fg.on_accent` at `size.icon.lg`; the shape and the
    // 56 box stay the component's own (Material 3's 16 corner), per the R-03-059 addendum.
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: tokens.accentPrimary,
      foregroundColor: tokens.fgOnAccent,
      iconSize: AppSize.iconLg,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: tokens.bgBase,
      surfaceTintColor: Colors.transparent,
      // decided 2026-09-03 by the product owner: no pill behind the selected icon; docs/32 section 7.22 owns this bar.
      indicatorColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((
        Set<WidgetState> states,
      ) {
        return IconThemeData(
          color: states.contains(WidgetState.selected)
              ? tokens.accentText
              : tokens.fgSecondary,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((
        Set<WidgetState> states,
      ) {
        return AppType.micro.copyWith(
          color: states.contains(WidgetState.selected)
              ? tokens.accentText
              : tokens.fgSecondary,
        );
      }),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color>((
        Set<WidgetState> states,
      ) {
        if (states.contains(WidgetState.selected)) {
          return tokens.fgOnAccent;
        }
        return tokens.fgSecondary;
      }),
      trackColor: WidgetStateProperty.resolveWith<Color>((
        Set<WidgetState> states,
      ) {
        if (states.contains(WidgetState.selected)) {
          return tokens.accentPrimary;
        }
        return tokens.bgHigh;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith<Color>((
        Set<WidgetState> states,
      ) {
        return tokens.borderStrong;
      }),
    ),
  );
}
