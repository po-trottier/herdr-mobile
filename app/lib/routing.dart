/// The `go_router` configuration: the three-destination shell, the pairing flow, and every
/// deep-linkable detail route, per `docs/90-implementation-plan.md` `WP-12-b`. `docs/90` §5.3
/// routes a later package's route addition through this file on request; that package's own
/// task states the exact route and the rule it serves.
library;

import 'dart:async' show StreamController, StreamSubscription, unawaited;

import 'package:connectivity_plus/connectivity_plus.dart'
    show Connectivity, ConnectivityResult;
import 'package:cupertino_ui/cupertino_ui.dart'
    show
        BuildContext,
        Center,
        Column,
        CrossAxisAlignment,
        CupertinoPage,
        EdgeInsets,
        GlobalKey,
        MainAxisSize,
        NavigatorState,
        Padding,
        SafeArea,
        StatelessWidget,
        Text,
        Widget;
import 'package:device_info_plus/device_info_plus.dart' show DeviceInfoPlugin;
import 'package:flutter/foundation.dart'
    show
        LicenseEntry,
        TargetPlatform,
        VoidCallback,
        defaultTargetPlatform,
        ValueNotifier;
import 'package:flutter/widgets.dart'
    show
        BorderRadius,
        BoxDecoration,
        ColoredBox,
        ExcludeSemantics,
        LocalKey,
        MediaQuery,
        Navigator,
        Page,
        SizedBox,
        State,
        StatefulWidget,
        StreamBuilder,
        WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show Provider, ProviderScope, Ref;
import 'package:go_router/go_router.dart'
    show
        Allow,
        Block,
        GoRoute,
        GoRouter,
        GoRouterHelper,
        GoRouterState,
        RouteBase,
        StatefulNavigationShell,
        StatefulShellBranch,
        StatefulShellRoute;
import 'package:local_auth/local_auth.dart' show LocalAuthentication;
import 'package:material_ui/material_ui.dart'
    show
        Container,
        MaterialPage,
        ScaffoldMessenger,
        SnackBar,
        showModalBottomSheet;
import 'package:package_info_plus/package_info_plus.dart' show PackageInfo;

import 'core/result/result.dart' show Err, Ok, Result;
import 'models/frame.dart' show frameProtocolVersion;
import 'models/message.dart' show Message;
import 'models/messages/device_info.dart' as messages show DeviceInfo;
import 'models/messages/host_info.dart' show HostInfo;
import 'models/messages/pane_summary.dart' show PaneSummary;
import 'models/messages/platform.dart' as messages show Platform;
import 'models/messages/tab_summary.dart' show TabSummary;
import 'models/messages/tree_snapshot.dart' show TreeSnapshot;
import 'models/messages/workspace_summary.dart' show WorkspaceSummary;
import 'screens/about_screen.dart'
    show
        AboutScreen,
        LicenceDetailScreen,
        LicenceIndexScreen,
        LicensedPackage,
        loadLicensedPackages;
import 'screens/actions_screen.dart';
import 'screens/agent_list_screen.dart';
import 'screens/app_shell.dart';
import 'screens/connection_screen.dart';
import 'screens/create_sheet.dart'
    show CreatedPane, CreatedWorkspace, CreateResult, showCreateSheet;
import 'screens/device_list_screen.dart' show DeviceListScreen;
import 'screens/host_list_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/manual_pairing_screen.dart'
    show
        ManualPairingFailed,
        ManualPairingFailureCode,
        ManualPairingResult,
        ManualPairingScreen,
        ManualPairingSucceeded;
import 'screens/notification_settings_screen.dart'
    show NotificationSettingsScreen;
import 'screens/notifications_screen.dart';
import 'screens/qr_scan_screen.dart' show QrScanScreen;
import 'screens/settings_screen.dart' show SettingsScreen;
import 'screens/status_legend_screen.dart' show StatusLegendScreen;
import 'screens/terminal_screen.dart' show TerminalScreen;
import 'screens/welcome_screen.dart' show WelcomeScreen;
import 'services/agent_status.dart';
import 'services/app_settings.dart';
import 'services/biometric_gate.dart';
import 'services/device_list.dart' show SendFrame;
import 'services/host_actions.dart' show ActionScope;
import 'services/host_list.dart'
    show SwitchFailed, SwitchOutcome, SwitchSucceeded, forgetHost, switchToHost;
import 'services/keystore.dart' show HostSecrets, KeystoreService;
import 'services/notifications.dart';
import 'services/origin.dart' show RelayOrigin;
import 'services/pairing.dart';
import 'services/pane_actions.dart' show notConnectedMessage, reconcileTree;
import 'services/plain_store.dart' show PairedHostRecord, PlainStore;
import 'services/relay.dart';
import 'services/terminal.dart' show TerminalFrameState;
import 'services/tree.dart' show fetchTreeSnapshot, paneDisplayName;
import 'widgets/app_filled_button.dart';
import 'widgets/app_text_button.dart';
import 'widgets/theme/app_color.dart';
import 'widgets/theme/app_size.dart';
import 'widgets/theme/app_space.dart';
import 'widgets/theme/app_type.dart';

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

/// R-33-070.2: the previous-page title `CupertinoNavigationBar`'s automatic back label needs.
/// `pageBuilder` -- a real `CupertinoPage`/`MaterialPage`, not the plain `builder:` every other
/// route in this file still uses -- is the only way to give a route a `title` that Flutter's
/// own `CupertinoRouteTransitionMixin` reads back as the *next* pushed route's previous-title,
/// per `cupertino_ui`'s own `_BackLabel` (it only fires when both the current and the previous
/// route are `CupertinoPageRoute`s, which plain `builder:`'s `MaterialPage` never is on any
/// platform -- confirmed by reading `go_router`'s `pageBuilderForMaterialApp`).
///
/// Applied to the routes something is genuinely pushed on top of, within that same
/// `Navigator` (`/settings`, `/hosts/:hostId/notifications`, `/settings/about`,
/// `/settings/about/licences`, and since 2026-09-09 `/hosts/:hostId/devices`, whose detail
/// screen `device_list_screen.dart` pushes itself): a route nothing pushes on top of needs no
/// title, since nothing ever reads it. The same `_BackLabel` also requires the *current* route
/// to be a `CupertinoPageRoute` before it reads the previous title at all, so a leaf route that
/// wants its own bar to read `Settings` back takes the `CupertinoPage` too, with no `title`:
/// `/settings/status-colours` does (2026-09-09, R-03-106). The leaf routes still built with
/// plain `builder:` (`/settings/notifications`, `/hosts/:hostId/diagnostics`,
/// `/settings/about/licences/:package`) therefore show a blank back label on iOS; that
/// pre-existing gap is disclosed here, not fixed by this change.
/// A route reached only through `parentNavigatorKey: rootNavigatorKey`
/// (`/hosts`, the terminal route) sits, on the root `Navigator`, below just `AppShell`'s own
/// single `StatefulShellRoute` page -- one page standing for the whole three-tab shell, not a
/// single screen -- so no per-screen title exists there for this mechanism to read regardless
/// of what `title:` this function is given; that residual gap is disclosed, not silently
/// papered over with a wrong title.
Page<void> _platformPage({
  required LocalKey key,
  required Widget child,
  String? title,
}) => _isIos
    ? CupertinoPage<void>(key: key, title: title, child: child)
    : MaterialPage<void>(key: key, child: child);

/// The `/hosts/:hostId/panes/:paneId/actions` route body (R-03-055; `docs/31-mockups/
/// 18-actions.md` R-31-18-01, amended 2026-09-09): the plugin actions screen scoped to the
/// pane on screen. R-31-18-05 makes the caller source the three breadcrumb segments from the
/// tree snapshot, and a `GoRoute.builder` cannot await that read, so this wrapper reads the
/// tree once on mount (`tree.dart`'s `fetchTreeSnapshot`, the same one-shot read the terminal
/// makes) and renders the real [ActionsScreen] once the scope is known. Until then it draws
/// the bare `color.bg.base` surface the pushed page transition covers: a screen whose scope
/// sentence named the computer for one round trip and then the pane would state two
/// different truths in a row.
///
/// When the read fails or the pane is no longer in the tree, the scope falls back to the
/// computer alone: the sentence and the gating then agree with each other and with what the
/// invocation carries, which a pane id with no name could not promise (R-31-18-05 forbids an
/// identifier in place of a label).
class _PaneActionsRoute extends StatefulWidget {
  const _PaneActionsRoute({required this.hostId, required this.paneId});

  final String hostId;
  final String paneId;

  @override
  State<_PaneActionsRoute> createState() => _PaneActionsRouteState();
}

class _PaneActionsRouteState extends State<_PaneActionsRoute> {
  ActionScope? _scope;

  @override
  void initState() {
    super.initState();
    unawaited(_resolveScope());
  }

  Future<void> _resolveScope() async {
    final RelayConnection conn = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(relayConnectionProvider);
    final Result<TreeSnapshot> result = await fetchTreeSnapshot(
      messages: conn.messages,
      connectionState: conn.connectionState,
      send: conn.send,
    );
    if (!mounted) return;
    setState(() => _scope = _scopeFor(result));
  }

  ActionScope _scopeFor(Result<TreeSnapshot> result) {
    if (result is! Ok<TreeSnapshot>) return const ActionScope();
    final TreeSnapshot tree = result.value;
    PaneSummary? pane;
    for (final PaneSummary candidate in tree.panes) {
      if (candidate.paneId == widget.paneId) pane = candidate;
    }
    if (pane == null) return const ActionScope();
    String? tabName;
    for (final TabSummary tab in tree.tabs) {
      if (tab.tabId == pane.tabId) tabName = tab.title;
    }
    String? workspaceName;
    for (final WorkspaceSummary workspace in tree.workspaces) {
      if (workspace.workspaceId == pane.workspaceId) {
        workspaceName = workspace.name;
      }
    }
    return ActionScope(
      workspaceId: pane.workspaceId,
      workspaceName: workspaceName,
      tabId: pane.tabId,
      tabName: tabName,
      paneId: pane.paneId,
      paneName: paneDisplayName(pane),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ActionScope? scope = _scope;
    if (scope == null) {
      return ColoredBox(color: AppColor.of(context).bgBase);
    }
    final RelayConnection conn = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(relayConnectionProvider);
    final String hostId = widget.hostId;
    return ActionsScreen(
      hostId: hostId,
      hostName: conn.lastHostInfo?.hostName ?? hostId,
      messages: conn.messages,
      connectionState: conn.connectionState,
      send: conn.send,
      scope: scope,
      onOpenPane: (String hostId, String paneId) =>
          unawaited(context.push('/hosts/$hostId/panes/$paneId')),
    );
  }
}

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);
final GlobalKey<NavigatorState> _agentsNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'agents',
);
final GlobalKey<NavigatorState> _notificationsNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'notifications');
final GlobalKey<NavigatorState> _settingsNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'settings');

/// One `AppSettingsService` for whole session, mirrors [notificationsServiceProvider]'s
/// pattern. `settings_screen.dart` (`WP-21-b`) reads this for the theme, terminal-size,
/// haptic and App Lock settings it owns (Phase 21's own `Owns.` line; R-90-018 — no earlier
/// phase named a provider for it). [keystoreServiceProvider] and [biometricGateProvider]
/// both read [AppSettingsService.current] to construct in the right App Lock mode.
final Provider<AppSettingsService> appSettingsServiceProvider =
    Provider<AppSettingsService>((Ref ref) => AppSettingsService());

/// One `KeystoreService` for whole session, mirrors [relayConnectionProvider]'s pattern.
/// Built once, in whatever App Lock mode `AppSettingsService.current` reports at that first
/// read — `_resolveStartupRedirect` below awaits one real `load()` before any route builds,
/// so `.current` is warm by then (that field's own doc comment). Every route below that needs
/// a `KeystoreService` reads this same instance, rather than constructing its own, so
/// `settings_screen.dart`'s App Lock toggle (`KeystoreService.retoggleProtection`) mutates the
/// one instance every other route sees too, with no separate invalidation wiring.
final Provider<KeystoreService> keystoreServiceProvider =
    Provider<KeystoreService>(
      (Ref ref) => KeystoreService(
        appLockEnabled: ref
            .read(appSettingsServiceProvider)
            .current
            .appLockEnabled,
      ),
    );

/// One `BiometricGate` for whole session, per `docs/22-platform-integration.md`
/// R-22-013: `biometric_gate.dart`'s own doc comment names "the app root or
/// router redirect" as reader. This file reads it. Starts locked (R-31-04-01
/// cold-start default): `routeNotificationTap` below checks it before any
/// notification-tap navigation. Shares [keystoreServiceProvider]'s single instance, per that
/// provider's own doc comment, and is told the same starting App Lock mode; `isLocked` stays
/// correct after a later toggle because `settings_screen.dart` calls
/// `BiometricGate.setAppLockEnabled` on this very instance once the storage migration
/// succeeds.
final Provider<BiometricGate> biometricGateProvider = Provider<BiometricGate>(
  (Ref ref) => BiometricGate(
    appLockEnabled: ref.read(appSettingsServiceProvider).current.appLockEnabled,
    keystore: ref.read(keystoreServiceProvider),
  ),
);

/// One `RelayConnection` for whole session, mirrors
/// [biometricGateProvider]'s pattern. `device_list_screen.dart`'s own doc
/// comment names this file as supplier of `messages`/`connectionState`/
/// `send` for its own `/hosts/:hostId/devices` route; this file reads it the
/// same way for every route below.
final Provider<RelayConnection> relayConnectionProvider =
    Provider<RelayConnection>((Ref ref) => RelayConnection());

/// One `NotificationsService` for whole session. `app.dart`'s `_AppRootState`
/// reads this same instance to wire `onNotificationTapped` and call
/// `initialize()` once on mount — single shared instance, one real Android
/// channel, one real init call, no split state.
final Provider<NotificationsService> notificationsServiceProvider =
    Provider<NotificationsService>((Ref ref) => NotificationsService());

/// One `AgentStatusService` for whole session, mirrors [relayConnectionProvider]'s pattern.
/// `agent_list_screen.dart` (`WP-18-b`) reads this for its `NEEDS YOU` section (R-30-501),
/// `app_shell.dart` for the `Notifications` badge and `notifications_screen.dart` for the log.
/// Shares [notificationsServiceProvider]'s single `NotificationsService` instance with
/// `app.dart`'s notification-tap wiring — real local notifications fire from the one
/// initialised instance, not a second, un-initialised one. Its `PlainStore` holds the
/// per-Host read/removed acknowledgements (R-31-07-01); `PlainStore` is constructed wherever it
/// is needed, as every other route here does.
final Provider<AgentStatusService> agentStatusServiceProvider =
    Provider<AgentStatusService>(
      (Ref ref) => AgentStatusService(
        messages: ref.watch(relayConnectionProvider).messages,
        notifications: ref.watch(notificationsServiceProvider),
        send: ref.watch(relayConnectionProvider).send,
        plainStore: PlainStore(),
        currentHostId: () =>
            ref.read(relayConnectionProvider).lastHostInfo?.hostId,
        connectionState: ref.watch(relayConnectionProvider).connectionState,
      ),
    );

/// The last [TerminalFrameState] any pane published, with the Host it belongs to, or `null`
/// before the first pane read. `/hosts/:hostId/panes/:paneId` writes it through
/// `TerminalScreen.onFrameState`; `/hosts/:hostId/diagnostics` reads it for the `RENDER`
/// group (R-31-13-07 to R-31-13-10), which must show real values once a pane of that Host was
/// read and the hint only before. A different Host's frame is never shown.
final Provider<ValueNotifier<({String hostId, TerminalFrameState state})?>>
lastFrameStateProvider =
    Provider<ValueNotifier<({String hostId, TerminalFrameState state})?>>(
      (Ref ref) =>
          ValueNotifier<({String hostId, TerminalFrameState state})?>(null),
    );

/// The one `GoRouter` the app builds, consumed by `app.dart`'s
/// `MaterialApp.router`. The three destinations of `docs/30-ux-spec.md`
/// R-30-021 (`Agents`, `Notifications`, `Settings`, decided 2026-09-04) are
/// `StatefulShellBranch`es, each with its own `Navigator`.
/// R-30-045 and R-33-071.1: a route a branch pushes stays inside that
/// branch's own `Navigator` and never reaches the root, so the bottom
/// chrome `AppShell` draws stays on screen.
///
/// `/agents` and `/notifications` are each their branch's own required
/// paramless default route (`go_router` forbids a `StatefulShellBranch`'s
/// first route from carrying a path parameter unless a static
/// `initialLocation` supplies one, and this file has no host to hardcode
/// there). Each `redirect`s at once to the real host-scoped route below it
/// in the same branch when a computer is connected, and to `/hosts`
/// otherwise — real behaviour, not a placeholder body; see each route's own
/// comment.
///
/// `initialLocation` starts at `/`, whose own `redirect` resolves the cold
/// start per `docs/30-ux-spec.md`'s Navigation model and
/// `docs/31-mockups/01-welcome.md`/`04-lock.md`: `/welcome` with zero saved
/// computers (R-03-043, "saved, never connected"); with one or more, `/lock`
/// while App Lock is on, or straight to `/hosts` while it is off, per
/// R-31-04-12. See [_resolveStartupRedirect]'s own doc comment.
final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/',
  onEnter: (context, currentState, nextState, router) async {
    if (nextState.uri.scheme == 'herdr-remote' &&
        currentState.uri.path.endsWith('/pair/manual') &&
        !ProviderScope.containerOf(
          context,
          listen: false,
        ).read(biometricGateProvider).isLocked) {
      final link = nextState.uri
          .replace(path: nextState.uri.path == '/' ? '' : nextState.uri.path)
          .toString();
      final words = await loadEffWordlist();
      if (words is! Ok<List<String>> ||
          parsePairingUri(link, words.value) is! Ok<PairingInput>) {
        return const Block.stop();
      }
      final target = Uri(
        path: currentState.uri.path,
        queryParameters: <String, String>{'link': link},
      );
      return Block.then(() {
        unawaited(router.replace<void>(target.toString()));
      });
    }
    return const Allow();
  },
  routes: <RouteBase>[
    StatefulShellRoute.indexedStack(
      builder:
          (
            BuildContext context,
            GoRouterState state,
            StatefulNavigationShell navigationShell,
          ) {
            final container = ProviderScope.containerOf(context, listen: false);
            final RelayConnection conn = container.read(
              relayConnectionProvider,
            );
            final AgentStatusService agentStatus = container.read(
              agentStatusServiceProvider,
            );
            return AppShell(
              navigationShell: navigationShell,
              connectionState: conn.connectionState,
              isConnected: () => conn.isConnected,
              connectedHostName: () => conn.lastHostInfo?.hostName,
              onOpenDiagnostics: () {
                final String? hostId = conn.lastHostInfo?.hostId;
                if (hostId == null) return null;
                return () =>
                    unawaited(context.push('/hosts/$hostId/diagnostics'));
              },
              notifications: agentStatus.notifications,
              currentNotifications: () => agentStatus.currentNotifications,
            );
          },
      branches: <StatefulShellBranch>[
        StatefulShellBranch(
          navigatorKey: _agentsNavigatorKey,
          routes: <RouteBase>[
            // Branch default (see this file's `appRouter` doc comment): redirects to the
            // connected computer's real agent list, or to `/hosts` to choose one.
            GoRoute(
              path: '/agents',
              name: 'agents',
              redirect: (BuildContext context, GoRouterState state) {
                final String? hostId = ProviderScope.containerOf(
                  context,
                  listen: false,
                ).read(relayConnectionProvider).lastHostInfo?.hostId;
                return hostId == null ? '/hosts' : '/hosts/$hostId/agents';
              },
              builder: (BuildContext context, GoRouterState state) =>
                  const Center(),
            ),
            // R-31-06-01 real route (docs/30-ux-spec.md row 06, R-30-021). Wrapped in
            // `_AgentListRoute` rather than built inline: R-03-091/R-30-521 fire the one-time
            // App Lock offer at exactly this arrival, which needs a post-frame hook this
            // plain `builder` cannot run.
            GoRoute(
              path: '/hosts/:hostId/agents',
              name: 'agent-list',
              builder: (BuildContext context, GoRouterState state) =>
                  _AgentListRoute(hostId: state.pathParameters['hostId']!),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _notificationsNavigatorKey,
          routes: <RouteBase>[
            // Branch default (see this file's `appRouter` doc comment): redirects to the
            // connected computer's notification log, or to `/hosts` to choose one.
            GoRoute(
              path: '/notifications',
              name: 'notifications',
              redirect: (BuildContext context, GoRouterState state) {
                final String? hostId = ProviderScope.containerOf(
                  context,
                  listen: false,
                ).read(relayConnectionProvider).lastHostInfo?.hostId;
                return hostId == null
                    ? '/hosts'
                    : '/hosts/$hostId/notifications';
              },
              builder: (BuildContext context, GoRouterState state) =>
                  const Center(),
            ),
            // R-30-021 real route (docs/30-ux-spec.md row 07, decided 2026-09-04). The
            // `closedPane` query parameter is `routeNotificationTap`'s R-30-511 `pane closed`
            // hand-off: the screen draws its `That pane has closed.` strip and opens nothing.
            GoRoute(
              path: '/hosts/:hostId/notifications',
              name: 'host-notifications',
              pageBuilder: (BuildContext context, GoRouterState state) {
                final container = ProviderScope.containerOf(
                  context,
                  listen: false,
                );
                final RelayConnection conn = container.read(
                  relayConnectionProvider,
                );
                final AgentStatusService agentStatus = container.read(
                  agentStatusServiceProvider,
                );
                final String hostId = state.pathParameters['hostId']!;
                return _platformPage(
                  key: state.pageKey,
                  title: 'Notifications',
                  child: NotificationsScreen(
                    hostName: conn.lastHostInfo?.hostName ?? hostId,
                    notifications: agentStatus.notifications,
                    currentNotifications: agentStatus.currentNotifications,
                    onMarkSeen: agentStatus.markSeen,
                    onMarkAllSeen: agentStatus.markAllSeen,
                    onRemove: agentStatus.remove,
                    onRemoveAll: agentStatus.removeAll,
                    // R-31-07-05: opening counts as reading (R-30-503).
                    onOpenPane: (String paneId) {
                      // The read mark's stored outcome surfaces on the screen's next action;
                      // opening the pane is never held back by it (R-31-07-05).
                      unawaited(agentStatus.notePaneOpened(paneId));
                      unawaited(context.push('/hosts/$hostId/panes/$paneId'));
                    },
                    closedPaneId: state.uri.queryParameters['closedPane'],
                  ),
                );
              },
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _settingsNavigatorKey,
          routes: <RouteBase>[
            // R-31-15-01 real route (docs/30-ux-spec.md row 15). No path parameter, so this
            // is a legal branch default on its own (see this file's `appRouter` doc comment)
            // — `Agents`/`Notifications` need the redirect trick above only because their
            // real content is host-scoped; `Settings` never is.
            GoRoute(
              path: '/settings',
              name: 'settings',
              pageBuilder: (BuildContext context, GoRouterState state) {
                final container = ProviderScope.containerOf(
                  context,
                  listen: false,
                );
                final RelayConnection conn = container.read(
                  relayConnectionProvider,
                );
                return _platformPage(
                  key: state.pageKey,
                  title: 'Settings',
                  child: SettingsScreen(
                    appSettings: container.read(appSettingsServiceProvider),
                    keystore: container.read(keystoreServiceProvider),
                    gate: container.read(biometricGateProvider),
                    plainStore: PlainStore(),
                    connection: conn,
                    onOpenAlerts: () =>
                        unawaited(context.push('/settings/notifications')),
                    onOpenAbout: () =>
                        unawaited(context.push('/settings/about')),
                    onOpenStatusColours: () =>
                        unawaited(context.push('/settings/status-colours')),
                    onOpenDevices: (String hostId) =>
                        unawaited(context.push('/hosts/$hostId/devices')),
                    onOpenDiagnostics: (String hostId) =>
                        unawaited(context.push('/hosts/$hostId/diagnostics')),
                  ),
                );
              },
            ),
            // R-31-13-01: connection diagnostics screen.
            GoRoute(
              path: '/hosts/:hostId/diagnostics',
              name: 'diagnostics',
              builder: (BuildContext context, GoRouterState state) =>
                  _DiagnosticsRoute(hostId: state.pathParameters['hostId']!),
            ),
            // `/settings/notifications` (docs/30-ux-spec.md row 12), already referenced by
            // `agent_list_screen.dart`'s `onOpenAlertsSettings` above.
            GoRoute(
              path: '/settings/notifications',
              name: 'settings-notifications',
              builder: (BuildContext context, GoRouterState state) =>
                  NotificationSettingsScreen(
                    service: ProviderScope.containerOf(
                      context,
                      listen: false,
                    ).read(notificationsServiceProvider),
                  ),
            ),
            // `/hosts/:hostId/devices` (docs/30-ux-spec.md row 14). `localDeviceId` needs an
            // async `PlainStore.deviceId()` read this route's own builder cannot await, so
            // `_DeviceListRoute` below loads it once, mirroring `_ManualPairingRoute`'s
            // pattern for `/pair/manual`. A titled `_platformPage` since 2026-09-09 (R-03-105):
            // `device_list_screen.dart` pushes its detail screen on top with a
            // `CupertinoPageRoute` on iOS, so this route is one "something is genuinely pushed
            // on top of" and its title is what that detail's back label reads.
            GoRoute(
              path: '/hosts/:hostId/devices',
              name: 'devices',
              pageBuilder: (BuildContext context, GoRouterState state) {
                final RelayConnection conn = ProviderScope.containerOf(
                  context,
                  listen: false,
                ).read(relayConnectionProvider);
                final String hostId = state.pathParameters['hostId']!;
                final String hostName = conn.lastHostInfo?.hostName ?? hostId;
                return _platformPage(
                  key: state.pageKey,
                  title: 'Phones on $hostName',
                  child: _DeviceListRoute(
                    hostName: hostName,
                    messages: conn.messages,
                    connectionState: conn.connectionState,
                    send: conn.send,
                    onRemovedThisPhone: () {
                      unawaited(conn.disconnect());
                      context.go('/hosts');
                    },
                  ),
                );
              },
            ),
            // `/settings/status-colours` (docs/30-ux-spec.md row 20; R-03-106, decided
            // 2026-09-09 by the product owner): the colour legend of
            // `docs/31-mockups/20-status-legend.md`, pushed by the `Status colours` row above.
            // A `CupertinoPage` on iOS so its own bar reads `Settings` back (R-33-070.2, see
            // `_platformPage`'s doc comment); nothing is pushed on top of it, so no `title`.
            GoRoute(
              path: '/settings/status-colours',
              name: 'status-colours',
              pageBuilder: (BuildContext context, GoRouterState state) =>
                  _platformPage(
                    key: state.pageKey,
                    child: const StatusLegendScreen(),
                  ),
            ),
            // `/settings/about` and its two licence pages (docs/30-ux-spec.md row 19).
            GoRoute(
              path: '/settings/about',
              name: 'about',
              pageBuilder: (BuildContext context, GoRouterState state) =>
                  _platformPage(
                    key: state.pageKey,
                    title: 'About',
                    child: AboutScreen(
                      onOpenLicences: () =>
                          unawaited(context.push('/settings/about/licences')),
                    ),
                  ),
            ),
            GoRoute(
              path: '/settings/about/licences',
              name: 'licences',
              pageBuilder: (BuildContext context, GoRouterState state) =>
                  _platformPage(
                    key: state.pageKey,
                    title: 'Licences',
                    child: LicenceIndexScreen(
                      onOpenPackage: (LicensedPackage package) => unawaited(
                        context.push(
                          '/settings/about/licences/${Uri.encodeComponent(package.name)}',
                          extra: package.entries,
                        ),
                      ),
                    ),
                  ),
            ),
            GoRoute(
              path: '/settings/about/licences/:package',
              name: 'licence-detail',
              builder: (BuildContext context, GoRouterState state) {
                final String packageName = state.pathParameters['package']!;
                final Object? extra = state.extra;
                if (extra is List<LicenseEntry>) {
                  return LicenceDetailScreen(
                    packageName: packageName,
                    entries: extra,
                  );
                }
                // A direct deep link, never a link this app itself creates: re-derives the
                // same data `loadLicensedPackages` already gave the index page, per that
                // function's own doc comment ("always show the same data from one load").
                return _LicenceDetailRoute(packageName: packageName);
              },
            ),
          ],
        ),
      ],
    ),
    // R-31-13-20's host chip target and this diagnostics screen's own
    // `onDisconnected` above both name this route. Root navigator,
    // `parentNavigatorKey: rootNavigatorKey`: switching computers is
    // cross-cutting, reached from an app-bar control per
    // `docs/30-ux-spec.md` row 05's entry point, not one bottom
    // destination's own pushed detail view, so R-30-045's
    // bottom-nav-preserving rule does not apply here. `onSwitch`/`onForget`
    // call `host_list.dart`'s `switchToHost`/`forgetHost` verbatim, never
    // reimplemented. `onPairAnother` routes to the now-real `/pair/scan`.
    // R-31-05-16: the first `/hosts` build of the session is the cold-start
    // landing of `_resolveStartupRedirect` (directly, or after `/lock`), and it
    // makes exactly one connection attempt; every later visit makes none.
    GoRoute(
      path: '/hosts',
      name: 'hosts',
      parentNavigatorKey: rootNavigatorKey,
      builder: (BuildContext context, GoRouterState state) {
        final container = ProviderScope.containerOf(context, listen: false);
        final RelayConnection conn = container.read(relayConnectionProvider);
        final AgentStatusService agentStatus = container.read(
          agentStatusServiceProvider,
        );
        final BiometricGate gate = container.read(biometricGateProvider);
        final PlainStore plainStore = PlainStore();
        final KeystoreService keystore = container.read(
          keystoreServiceProvider,
        );
        return HostListScreen(
          pairedHosts: plainStore.pairedHosts,
          messages: conn.messages,
          connectionState: conn.connectionState,
          initialConnectionState: conn.isConnected
              ? const RelayConnected()
              : const RelayDisconnected(),
          connectedHostId: conn.lastHostInfo?.hostId,
          unseenAttention: agentStatus.unseenAttention,
          currentAttention: agentStatus.currentAttention,
          thisDeviceName: () => _thisDeviceName(plainStore),
          onSwitch: (PairedHostRecord target) async => switchToHost(
            connection: conn,
            keystore: keystore,
            plainStore: plainStore,
            gate: gate,
            target: target,
            hasNetwork: await _defaultHasNetwork(),
          ),
          onForget: (PairedHostRecord target) => forgetHost(
            keystore: keystore,
            plainStore: plainStore,
            hostId: target.hostId,
          ),
          onSwitched: (String hostId) {
            if (appRouter.state.uri.path == '/hosts') {
              context.go('/hosts/$hostId/agents');
            }
          },
          onPairAnother: () => unawaited(context.push('/pair/scan')),
          onOpenDiagnostics: (String hostId) =>
              unawaited(context.push('/hosts/$hostId/diagnostics')),
          attemptOnLoad: _takeColdStartAttempt(),
        );
      },
      routes: <RouteBase>[
        _pairManualDeepLinkRoute(name: 'hosts-pair-manual-deeplink'),
      ],
    ),
    // R-11-134, R-41-110: the notification-tap route, and the ordinary route
    // for opening a pane from the agent list or the notification log. `parentNavigatorKey`
    // pushes it on the root `Navigator`, outside every branch, so it hides
    // the bottom navigation, per R-30-022 and R-33-071.4, the terminal's
    // stated full-screen exception. R-30-031: this file names no route that
    // pops here, so a caller MUST reach it with `context.push`, never
    // `context.go`, and `Navigator.pop` then returns to whatever route
    // pushed it, never a fixed one. `TerminalScreen` (`terminal_screen.dart`)
    // composes `terminal.dart`'s `TerminalService` with
    // `terminal_view_widget.dart`'s grid and `status_strip.dart`'s strip —
    // see that file's own doc comment for the grid contract.
    GoRoute(
      path: '/hosts/:hostId/panes/:paneId',
      name: 'terminal',
      parentNavigatorKey: rootNavigatorKey,
      builder: (BuildContext context, GoRouterState state) {
        final container = ProviderScope.containerOf(context, listen: false);
        final RelayConnection conn = container.read(relayConnectionProvider);
        final AppSettingsService settings = container.read(
          appSettingsServiceProvider,
        );
        final String hostId = state.pathParameters['hostId']!;
        final String paneId = state.pathParameters['paneId']!;
        // R-31-17-02: the pane this phone opened last is the split target the
        // create menu offers on the `Agents` screen, where no pane is on screen.
        _lastOpenedPaneId = paneId;
        return TerminalScreen(
          hostId: hostId,
          paneId: paneId,
          hostName: conn.lastHostInfo?.hostName ?? hostId,
          messages: conn.messages,
          connectionState: conn.connectionState,
          initialConnectionState: conn.isConnected
              ? const RelayConnected()
              : const RelayDisconnected(),
          send: conn.send,
          watchPane: conn.watchPane,
          unwatchPane: conn.unwatchPane,
          // R-30-210: the ladder position the person chose in Settings
          // seeds the grid; a pinch steps it for the screen only.
          initialTextSize: settings.current.terminalTextSize,
          initialHostTheme: conn.lastHostInfo?.theme,
          onBack: () => context.pop(),
          // R-03-113 item 1: the hierarchy switcher sheet moves to a sibling pane in place,
          // so the terminal route is replaced, never stacked.
          onSwitchPane: (String switchedPaneId) =>
              context.pushReplacement('/hosts/$hostId/panes/$switchedPaneId'),
          // R-03-055: the pane action sheet's `Plugin actions` row (mockup 10
          // callout 5) opens this pane's plugin actions, the nested route below.
          onOpenPluginActions: () =>
              unawaited(context.push('/hosts/$hostId/panes/$paneId/actions')),
          onDiagnostics: () =>
              unawaited(context.push('/hosts/$hostId/diagnostics')),
          onRevoked: () =>
              unawaited(_handleHostRevoked(context: context, hostId: hostId)),
          onFrameState: (TerminalFrameState frame) => ProviderScope.containerOf(
            context,
            listen: false,
          ).read(lastFrameStateProvider).value = (hostId: hostId, state: frame),
        );
      },
      routes: <RouteBase>[
        // R-03-055, R-31-18-01 (amended 2026-09-09): the plugin actions screen, scoped to
        // the pane on screen and reached only from that pane's action sheet. Nested under
        // the terminal route so a deep link lands the terminal beneath it, and on the root
        // navigator like its parent: the terminal already hides the bottom bar (R-30-022),
        // so this screen is the same stated full-screen exception (R-30-045).
        GoRoute(
          path: 'actions',
          name: 'pane-actions',
          parentNavigatorKey: rootNavigatorKey,
          builder: (BuildContext context, GoRouterState state) =>
              _PaneActionsRoute(
                hostId: state.pathParameters['hostId']!,
                paneId: state.pathParameters['paneId']!,
              ),
        ),
      ],
    ),
    // R-31-04-04, R-30-030: lock screen. `routeNotificationTap` below pushes
    // here when app locked, holding real target in `from` query param;
    // `_resolveStartupRedirect` below redirects here on cold start with a
    // saved computer, holding nothing. Root navigator: lock covers whole
    // app, not one branch.
    GoRoute(
      path: '/lock',
      name: 'lock',
      parentNavigatorKey: rootNavigatorKey,
      builder: (BuildContext context, GoRouterState state) {
        final BiometricGate gate = ProviderScope.containerOf(
          context,
          listen: false,
        ).read(biometricGateProvider);
        final String? held = state.uri.queryParameters['from'];
        return LockScreen(
          gate: gate,
          onUnlocked: () {
            final bool canGoBack = context.canPop();
            if (canGoBack) {
              context.pop();
            }
            if (held != null && held.isNotEmpty) {
              if (canGoBack) {
                unawaited(context.push(held));
              } else {
                // A notification tap or an R-22-034 deep link reaching `/lock` straight
                // from `_resolveStartupRedirect`, with nothing under this cold-started
                // lock: `go`, never `push`, or this screen -- now unlocked and never
                // popped -- stays a stale page under the held route, and back from it
                // lands the person on a dead lock screen instead of R-30-031's "the
                // route that opened it".
                context.go(held);
              }
            } else if (!canGoBack) {
              // docs/31-mockups/04-lock.md Navigation, "Out, success": "If
              // neither, /hosts... This screen MUST NOT choose a per-Host
              // route of its own." A cold start with no held route and
              // nothing to pop back to lands here, never on a computer this
              // file picked itself.
              context.go('/hosts');
            }
          },
        );
      },
    ),
    // R-31-01-01 (docs/30-ux-spec.md row 01): first-run welcome screen,
    // shown when the saved-computer count is zero.
    GoRoute(
      path: '/welcome',
      name: 'welcome',
      parentNavigatorKey: rootNavigatorKey,
      builder: (BuildContext context, GoRouterState state) => WelcomeScreen(
        onScanPressed: () => unawaited(context.push('/pair/scan')),
        onManualPressed: () => unawaited(context.push('/pair/manual')),
      ),
      routes: <RouteBase>[
        _pairManualDeepLinkRoute(name: 'welcome-pair-manual-deeplink'),
      ],
    ),
    // `/pair/scan` (docs/30-ux-spec.md row 02). `QrScanScreen` owns the whole
    // handshake internally (`attemptPairing`/`persistPairing`); this route
    // only supplies the app's real singletons and the two "where next"
    // hooks.
    GoRoute(
      path: '/pair/scan',
      name: 'pair-scan',
      parentNavigatorKey: rootNavigatorKey,
      builder: (BuildContext context, GoRouterState state) {
        final container = ProviderScope.containerOf(context, listen: false);
        final RelayConnection conn = container.read(relayConnectionProvider);
        final BiometricGate gate = container.read(biometricGateProvider);
        return QrScanScreen(
          connection: conn,
          gate: gate,
          keystore: container.read(keystoreServiceProvider),
          plainStore: PlainStore(),
          hasConnectedHost: conn.isConnected,
          // R-31-02: "Out, fallback: /pair/manual", "Out, back: the previous route" --
          // the two pairing screens swap in place, they never stack. `push` here (the
          // reported bug) let repeated toggling grow the stack without bound; back then
          // had to walk every earlier pairing screen instead of landing on the route
          // that opened the flow.
          onManualEntry: () => context.pushReplacement('/pair/manual'),
          onPaired: (PairingOutcome outcome, PairingInput input) =>
              context.go('/hosts/${outcome.hostId}/agents'),
        );
      },
    ),
    // `/pair/manual` (docs/30-ux-spec.md row 03). Unlike `QrScanScreen`, this
    // screen drives no handshake itself (its own doc comment): `_ManualPairingRoute`
    // below loads the EFF word list and the saved relay origin once (both async
    // reads this route's own builder cannot await) and `_attemptManualPairing`
    // drives `attemptPairing`/`persistPairing` on every `Pair` press.
    GoRoute(
      path: '/pair/manual',
      name: 'pair-manual',
      parentNavigatorKey: rootNavigatorKey,
      builder: (BuildContext context, GoRouterState state) =>
          _ManualPairingRoute(link: state.uri.queryParameters['link']),
    ),
    // The cold-start decision. See this file's `appRouter` doc comment and
    // [_resolveStartupRedirect]'s own doc comment.
    GoRoute(
      path: '/',
      name: 'start',
      parentNavigatorKey: rootNavigatorKey,
      redirect: (BuildContext context, GoRouterState state) =>
          _resolveStartupRedirect(context, state),
      builder: (BuildContext context, GoRouterState state) =>
          const SizedBox.shrink(),
    ),
  ],
);

/// Routes notification tap to terminal view, per R-11-134/R-22-023,
/// holding target behind `/lock` when app locked, per
/// R-30-030/R-31-04-04. `WP-19-a`'s notification service calls this from
/// `didReceiveNotificationResponse` with `hostId`/`paneId` from tapped
/// `agent_status` payload.
///
/// Of R-30-511's four degenerate cases this file decides two: the locked
/// one, and (since 2026-09-04) the `pane closed` one, which lands on
/// `/hosts/:hostId/notifications?closedPane=<paneId>` when
/// `AgentStatusService.paneClosedSinceSnapshot` already knows the pane is
/// gone. The host-disconnected and host-unknown cases are not decided here:
/// this file holds no live connection or pairing state, and the terminal
/// route owns its own disconnected/unknown-host rendering.
void routeNotificationTap(
  BuildContext context, {
  required String hostId,
  required String paneId,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  final bool paneClosed = container
      .read(agentStatusServiceProvider)
      .paneClosedSinceSnapshot(hostId: hostId, paneId: paneId);
  final String target = paneClosed
      ? '/hosts/$hostId/notifications?closedPane=$paneId'
      : '/hosts/$hostId/panes/$paneId';
  final BiometricGate gate = container.read(biometricGateProvider);
  final Uri current = GoRouter.of(context).state.uri;
  if (gate.isLocked) {
    final String lockTarget = '/lock?from=${Uri.encodeQueryComponent(target)}';
    if (current.path == '/lock') {
      // A second tap while still locked MUST NOT stack a second `/lock` page: the first
      // tap's held target would survive underneath, and unlocking twice would surface it
      // by surprise. Update the held target in place; a repeat of the identical target is
      // a pure no-op.
      if (current.queryParameters['from'] == target) return;
      context.pushReplacement(lockTarget);
      return;
    }
    unawaited(context.push(lockTarget));
    return;
  }
  if (current.path == target || current.toString() == target) {
    // Already showing this exact target: a repeat tap MUST NOT stack a duplicate page.
    return;
  }
  if (paneClosed) {
    // A branch route: `go`, not `push`, so the shell switches to the `Notifications`
    // destination instead of stacking the screen over the root navigator.
    context.go(target);
    return;
  }
  unawaited(context.push(target));
}

/// R-31-05-16: one cold-start attempt per session. The first caller receives
/// `true`, every later caller `false`.
bool _coldStartAttemptPending = true;
bool _takeColdStartAttempt() {
  final bool pending = _coldStartAttemptPending;
  _coldStartAttemptPending = false;
  return pending;
}

/// The cold-start landing decision, per `docs/30-ux-spec.md`'s Navigation
/// model (`Cold start -> {any paired computer} -> no: /welcome; yes: /lock`)
/// and `docs/31-mockups/01-welcome.md` R-31-01-01: "The test is saved, never
/// connected." `docs/31-mockups/04-lock.md`'s own Navigation section and
/// R-31-04-12 are explicit that a cold start enters `/lock` only while App
/// Lock is on. With one or more computers saved and App Lock off, this
/// function lands exactly where `/lock`'s own `onUnlocked` (held-route-null
/// branch) would have: `/hosts`, never a specific computer — `05-host-list
/// .md`'s "Single Host" state row states plainly that `/hosts` "MUST NOT" be
/// skipped, because the `+` action lives only there.
///
/// R-31-05-16's "connect to the newest last-seen computer" cold-start attempt
/// is `host_list_screen.dart`'s `_attemptColdStartOnce`, armed by the
/// `attemptOnLoad` flag the `/hosts` builder receives from
/// [_takeColdStartAttempt]: `true` exactly once per session, so the landing
/// build attempts once and every later visit attempts nothing.
///
/// Also syncs `MainActivity.kt`'s native `FLAG_SECURE` for the whole session, per
/// `biometric_gate.dart`'s `syncNativeLockState` doc comment: this is the one point every
/// session passes through before any route builds, so it is the right place to fix that
/// flag's starting state once, for every landing screen alike — not only the ones that
/// happen to construct a `BiometricGate` later.
Future<String> _resolveStartupRedirect(
  BuildContext context,
  GoRouterState state,
) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final AppSettingsService appSettings = container.read(
    appSettingsServiceProvider,
  );
  // This `load()` also warms `AppSettingsService.current` for every later synchronous route
  // builder in this session, per that field's own doc comment — `/` always resolves first
  // (`initialLocation: '/'`), before any other route in the app builds. Loaded before the
  // `hasSavedHost` branch below (moved up from that branch) because `syncNativeLockState`
  // needs it too, on every path, not only the one with a saved Host.
  await appSettings.load();
  // `biometric_gate.dart`'s `syncNativeLockState`: the one point every session passes through
  // before any route builds, so `MainActivity.kt`'s native `FLAG_SECURE` starts correct for
  // every landing screen, including `/welcome` below, which never constructs a `BiometricGate`
  // at all (R-31-01-09: zero paired computers, nothing yet to protect). See that function's
  // own doc comment for why this does not replace `BiometricGate`'s own constructor-time sync.
  syncNativeLockState(appLockEnabled: appSettings.current.appLockEnabled);
  final Result<List<PairedHostRecord>> pairedResult = await PlainStore()
      .pairedHosts();
  final bool hasSavedHost =
      pairedResult is Ok<List<PairedHostRecord>> &&
      pairedResult.value.isNotEmpty;
  final String landing;
  if (!hasSavedHost) {
    landing = '/welcome';
  } else if (appSettings.current.appLockEnabled) {
    landing = '/lock';
  } else {
    landing = '/hosts';
  }
  // R-22-034/R-22-035: a `herdr-remote://pair` deep link (cold or warm launch) is delivered
  // here as this route's own location: its URI has no path segment of its own -- `pair` is
  // the *authority*, per R-22-035's `android:host="pair"`, so `Uri.parse` leaves `path`
  // empty, and `RouteConfiguration.normalizeUri` folds that empty path to `/`, the exact
  // location this route owns. Anything else falls straight through to the ordinary landing
  // below, discarded silently (R-22-034's own words), never an error screen. Rebuilt from
  // `state.uri.query` alone, not `state.uri.toString()`: that normalized path fold means the
  // whole URI now stringifies as `herdr-remote://pair/?...` -- a trailing slash
  // `parsePairingUri`'s own strict `path != 'pair'` check (R-22-034's "path is not pair")
  // rejects, discarding every deep-linked field silently. The query component alone was
  // never touched by that fold, so it alone rebuilds the exact canonical form the parser
  // expects.
  if (state.uri.scheme == 'herdr-remote') {
    // R-22-034/R-31-05-16: Pairing consumes the startup attempt without connecting.
    _takeColdStartAttempt();
    final String link = 'herdr-remote://pair?${state.uri.query}';
    if (landing == '/lock') {
      // `/pair/manual` reads the keystore; it MUST NOT render before the biometric check
      // passes. Held exactly like a notification tap (R-30-030): `/lock`'s own `onUnlocked`
      // reveals it once the person actually unlocks.
      final String heldTarget =
          '/hosts/pair/manual?link=${Uri.encodeQueryComponent(link)}';
      return '/lock?from=${Uri.encodeQueryComponent(heldTarget)}';
    }
    return '$landing/pair/manual?link=${Uri.encodeQueryComponent(link)}';
  }
  return landing;
}

/// Reconnects [hostId] via `host_list.dart`'s `switchToHost`, per
/// `docs/31-mockups/13-connection.md` R-31-13-20. Looks up its
/// `PairedHostRecord` first (`switchToHost` needs the record, not a bare
/// id), checks network (R-30-947: no attempt while offline), adapts
/// `SwitchOutcome` to the `Result<void>` `ConnectionScreen.onReconnect`
/// wants. Never reimplements `switchToHost`'s own origin/handle/mode/
/// deviceInfo assembly — WP-14-app-transport's own doc comment there
/// names every source; this file only supplies the record and the
/// network check.
Future<Result<void>> _reconnectHost({
  required RelayConnection connection,
  required KeystoreService keystore,
  required PlainStore plainStore,
  required BiometricGate gate,
  required String hostId,
}) async {
  final Result<List<PairedHostRecord>> pairedResult = await plainStore
      .pairedHosts();
  if (pairedResult is Err<List<PairedHostRecord>>) {
    return Err(pairedResult.message, cause: pairedResult.cause);
  }
  final List<PairedHostRecord> paired =
      (pairedResult as Ok<List<PairedHostRecord>>).value;
  PairedHostRecord? target;
  for (final PairedHostRecord record in paired) {
    if (record.hostId == hostId) {
      target = record;
      break;
    }
  }
  if (target == null) {
    return Err('reconnect to $hostId: no stored record for that computer');
  }
  final bool hasNetwork = await _defaultHasNetwork();
  final SwitchOutcome outcome = await switchToHost(
    connection: connection,
    keystore: keystore,
    plainStore: plainStore,
    gate: gate,
    target: target,
    hasNetwork: hasNetwork,
  );
  return switch (outcome) {
    SwitchSucceeded() => const Ok(null),
    SwitchFailed(:final reason, :final detail) => Err(detail, cause: reason),
  };
}

/// `host_list_screen.dart`'s own `_defaultHasNetwork`, duplicated per
/// R-41-042 rung 1: that copy is private to a sibling work package's
/// file, and this is a second, cross-package caller (R-90-018).
Future<bool> _defaultHasNetwork() async {
  final List<ConnectivityResult> results = await Connectivity()
      .checkConnectivity();
  return !results.contains(ConnectivityResult.none);
}

/// `HostListScreen`'s `thisDeviceName`, per R-31-13-20. `plainStore.deviceName()`
/// returns `Ok(null)` before the user has set a name (`plain_store.dart`'s own
/// doc comment) and `settings_screen.dart`'s `_defaultDeviceName` is that
/// screen's own private fallback for the same case — duplicated here per
/// R-90-018/R-41-042 rung 1, same as `_defaultHasNetwork` above.
Future<String> _thisDeviceName(PlainStore plainStore) async {
  final Result<String?> stored = await plainStore.deviceName();
  if (stored case Ok<String?>(value: final String name)) {
    return name;
  }
  if (_isIos) {
    return (await DeviceInfoPlugin().iosInfo).modelName;
  }
  return (await DeviceInfoPlugin().androidInfo).model;
}

/// Builds the `device_info` payload for [attemptPairing], mirroring
/// `host_list.dart`'s own private `_buildDeviceInfo`, which itself already
/// mirrors `qr_scan_screen.dart`'s (R-11-226 caps `deviceName` at 32 UTF-8
/// bytes). Duplicated a third time per that function's own doc comment and
/// R-90-018/R-41-042 rung 1: none of the three is on another's `Paths.` line.
Future<Result<messages.DeviceInfo>> _buildDeviceInfo(
  PlainStore plainStore,
) async {
  try {
    final idResult = await plainStore.deviceId();
    if (idResult is Err<String>) {
      return Err(idResult.message, cause: idResult.cause);
    }
    final deviceId = (idResult as Ok<String>).value;
    final nameResult = await plainStore.deviceName();
    final storedName = nameResult is Ok<String?> ? nameResult.value : null;

    final String modelName;
    final String osVersion;
    if (_isIos) {
      final info = await DeviceInfoPlugin().iosInfo;
      modelName = info.modelName;
      osVersion = info.systemVersion;
    } else {
      final info = await DeviceInfoPlugin().androidInfo;
      modelName = info.model;
      osVersion = info.version.release;
    }
    final packageInfo = await PackageInfo.fromPlatform();
    final name = storedName ?? modelName;
    return Ok(
      messages.DeviceInfo(
        protocol: frameProtocolVersion,
        deviceId: deviceId,
        deviceName: name.length > 32 ? name.substring(0, 32) : name,
        platform: _isIos ? messages.Platform.ios : messages.Platform.android,
        osVersion: osVersion,
        appVersion: packageInfo.version,
      ),
    );
  } on Exception catch (e) {
    return Err('build device info', cause: e);
  }
}

/// Drives `pairing.dart`'s `attemptPairing`/`persistPairing` for
/// `/pair/manual`'s `ManualPairingScreen.onPair`, adapting the result into
/// one of [ManualPairingScreen]'s outcomes (`manual_pairing_screen.dart`'s
/// own "a caller adapts its own `Result<PairingOutcome>`" contract).
///
/// The failure mapping, one [ManualPairingFailureCode] per cause: the two
/// `PhraseErrorCode` values `attemptPairing` classifies locally —
/// `phraseExpired`, and `phraseAttempts` once `pairing.dart`'s own
/// `PairingAttemptTracker` reaches the third consecutive handshake failure
/// against the same phrase — map to their named codes, and the wire
/// `host_in_use` error maps to `hostInUse`. Every other cause maps to
/// `linkFailed` with its raw text in [ManualPairingFailed.detail] for the
/// screen's `type.mono.code` line (R-30-803): the relay unreachable, a
/// connection or a local step that failed (for example this function's own
/// `_buildDeviceInfo` reading local storage), or a handshake mismatch whose
/// count has not reached three. None of those may surface as
/// `phraseAttempts`: no third try happened, so that sentence would be false
/// (the 2026-09-03 live defect; mockup `03-pair-code.md` R-31-03-13).
Future<ManualPairingResult> _attemptManualPairing({
  required BuildContext context,
  required PairingInput input,
  required PairingAttemptTracker tracker,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final RelayConnection conn = container.read(relayConnectionProvider);
  final BiometricGate gate = container.read(biometricGateProvider);
  final PlainStore plainStore = PlainStore();
  final KeystoreService keystore = container.read(keystoreServiceProvider);

  final deviceInfoResult = await _buildDeviceInfo(plainStore);
  if (deviceInfoResult is! Ok<messages.DeviceInfo>) {
    final error = deviceInfoResult as Err<messages.DeviceInfo>;
    return ManualPairingFailed(
      ManualPairingFailureCode.linkFailed,
      detail: '${error.message}: ${error.cause}',
    );
  }

  final Result<PairingOutcome> result = await attemptPairing(
    connection: conn,
    input: input,
    gate: gate,
    deviceInfo: deviceInfoResult.value,
    tracker: tracker,
  );
  if (result case Ok<PairingOutcome>(value: final PairingOutcome outcome)) {
    await persistPairing(
      keystore: keystore,
      plainStore: plainStore,
      input: input,
      outcome: outcome,
    );
    return ManualPairingSucceeded(outcome);
  }
  final err = result as Err<PairingOutcome>;
  final Object? cause = err.cause;
  if (cause case PhraseException(:final code)) {
    if (code == PhraseErrorCode.phraseExpired) {
      return const ManualPairingFailed(ManualPairingFailureCode.phraseExpired);
    }
    if (code == PhraseErrorCode.phraseAttempts) {
      return const ManualPairingFailed(ManualPairingFailureCode.phraseAttempts);
    }
  }
  if (cause case RelayRegistrationException(:final code)
      when code == RelayRegistrationErrorCode.hostInUse) {
    return const ManualPairingFailed(ManualPairingFailureCode.hostInUse);
  }
  // Every remaining cause is a link failure (R-31-03-13): the relay
  // unreachable, a connection or local step that failed, or a handshake
  // mismatch whose count has not reached three.
  return ManualPairingFailed(
    ManualPairingFailureCode.linkFailed,
    detail: cause?.toString() ?? err.message,
  );
}

/// R-22-034's deep-link entry into `/pair/manual`, nested under whichever cold-start
/// landing [_resolveStartupRedirect] chose (`/welcome/pair/manual` or
/// `/hosts/pair/manual`), so back from the prefilled pairing screen returns to that
/// landing instead of leaving nothing under it: `/pair/manual` on its own is reached only
/// by `push`/`pushReplacement` everywhere else in this file, never by the bare `go` a deep
/// link's `redirect` performs. Both parents share this one builder -- the rendered screen
/// is identical either way; only the landing beneath differs.
GoRoute _pairManualDeepLinkRoute({required String name}) => GoRoute(
  path: 'pair/manual',
  name: name,
  builder: (BuildContext context, GoRouterState state) =>
      _ManualPairingRoute(link: state.uri.queryParameters['link']),
);

/// The `/pair/manual` route body. Loads the EFF word list
/// (`pairing.dart`'s `loadEffWordlist`) and the saved relay origin
/// (`keystore.dart`'s `KeystoreService.relayOrigin`) once on mount — both
/// async reads a `GoRoute.builder` cannot await — then renders the real
/// [ManualPairingScreen]. Keeps one [PairingAttemptTracker] for its own
/// lifetime, per that class's own doc comment ("MUST be reused across
/// retries of the same manual-entry attempt").
class _ManualPairingRoute extends StatefulWidget {
  const _ManualPairingRoute({this.link});

  /// R-22-034: the raw `herdr-remote://pair` deep-link URI, still encoded in this route's
  /// own `link` query parameter -- see [_resolveStartupRedirect]'s own doc comment for why
  /// it never reaches here any other way. `null` on the top-level `/pair/manual` route and
  /// every push/`pushReplacement` that reaches it (welcome, the scan-to-manual toggle,
  /// `/hosts`'s `+` action): none of those callers supply a query at all.
  final String? link;

  @override
  State<_ManualPairingRoute> createState() => _ManualPairingRouteState();
}

class _ManualPairingRouteState extends State<_ManualPairingRoute> {
  final PairingAttemptTracker _tracker = PairingAttemptTracker();
  List<String>? _effWords;
  RelayOrigin? _savedOrigin;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final wordsResult = await loadEffWordlist();
    if (!mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final savedOrigin = await loadPairingOriginDefault(
      keystore: container.read(keystoreServiceProvider),
      plainStore: PlainStore(),
    );
    if (!mounted) return;
    setState(() {
      _effWords = wordsResult is Ok<List<String>>
          ? wordsResult.value
          : const <String>[];
      _savedOrigin = savedOrigin;
      _loaded = true;
    });
  }

  /// R-22-034: "discard a malformed URL without showing an error" -- a parse failure (bad
  /// scheme, a missing field, a stale or garbled link) yields `null` silently here, exactly
  /// like every other `Err` this screen's own clipboard-paste path already swallows the
  /// same way (`_onPastePressed`'s own doc comment).
  PairingInput? get _deepLinkInput {
    final String? link = widget.link;
    final List<String>? words = _effWords;
    if (link == null || words == null || words.isEmpty) {
      return null;
    }
    final Result<PairingInput> parsed = parsePairingUri(link, words);
    return parsed is Ok<PairingInput> ? parsed.value : null;
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const SizedBox.shrink();
    }
    final RelayConnection conn = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(relayConnectionProvider);
    return StreamBuilder<RelayConnectionState>(
      stream: conn.connectionState,
      builder: (context, snapshot) => ManualPairingScreen(
        effWords: _effWords!,
        savedRelayOrigin: _savedOrigin,
        isConnected: conn.isConnected,
        initialInput: _deepLinkInput,
        onPair: (PairingInput input) => _attemptManualPairing(
          context: context,
          input: input,
          tracker: _tracker,
        ),
        onPaired: (PairingOutcome outcome) =>
            context.go('/hosts/${outcome.hostId}/agents'),
        // R-31-03-13/R-31-02: Replace the other pairing screen without an extra page.
        onScanInstead: () => context.pushReplacement('/pair/scan'),
      ),
    );
  }
}

/// Route wrapper for `/hosts/:hostId/diagnostics` ([ConnectionScreen]). It supplies the
/// three inputs the screen's own header names as its caller's job: the stored relay origin
/// (an async keystore read, as [_ManualPairingRoute] does), the link state at open (the
/// stream has no replay), and the [ConnectionDiagnostics] snapshots. A snapshot is emitted
/// once at subscription and again on every incoming application message, which is exactly
/// when `RelayConnection`'s counters change; the render numbers stay `null` because they
/// belong to an open pane's terminal service, and the screen already says so.
class _DiagnosticsRoute extends StatefulWidget {
  const _DiagnosticsRoute({required this.hostId});

  final String hostId;

  @override
  State<_DiagnosticsRoute> createState() => _DiagnosticsRouteState();
}

class _DiagnosticsRouteState extends State<_DiagnosticsRoute> {
  String? _relayOrigin;
  String? _alertsWord;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final container = ProviderScope.containerOf(context, listen: false);
    final secretsResult = await container
        .read(keystoreServiceProvider)
        .hostSecrets(widget.hostId);
    final NotificationDeliveryState delivery = await container
        .read(notificationsServiceProvider)
        .effectiveDeliveryState();
    if (!mounted) return;
    // R-31-13-22's three words: `ready`, `silenced`, `off`.
    final String alertsWord = switch (delivery) {
      NotificationDeliveryState.granted => 'ready',
      NotificationDeliveryState.silenced => 'silenced',
      NotificationDeliveryState.denied => 'off',
    };
    setState(() {
      if (secretsResult case Ok<HostSecrets?>(:final value)) {
        _relayOrigin = value?.relayOrigin?.toString();
      }
      _alertsWord = alertsWord;
    });
  }

  ConnectionDiagnostics _snapshot(RelayConnection conn) {
    final frame = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(lastFrameStateProvider).value;
    // R-31-13-07 to R-31-13-10: the RENDER numbers are the last pane read on this Host;
    // another Host's pane says nothing about this one, so it stays `-` with the hint.
    final TerminalFrameState? render = frame?.hostId == widget.hostId
        ? frame?.state
        : null;
    return ConnectionDiagnostics(
      herdrProtocol: conn.lastHostInfo?.herdrProtocol,
      herdrVersion: conn.lastHostInfo?.herdrVersion,
      framesIn: conn.isConnected ? conn.framesIn : null,
      framesOut: conn.isConnected ? conn.framesOut : null,
      bytesInOnWire: conn.isConnected ? conn.bytesInOnWire : null,
      bytesInUnpacked: conn.isConnected ? conn.bytesInUnpacked : null,
      roundTrip: conn.lastRoundTrip,
      gridColumns: render?.columns,
      gridRows: render?.rows,
      longestLineDrawn: render?.longestLineDrawn,
      unknownSgrCount: render?.unknownSgrCount,
    );
  }

  /// One snapshot at subscription, then one on every incoming application message (when
  /// the counters change) and on every frame-state change while a pane is open.
  Stream<ConnectionDiagnostics> _diagnostics(RelayConnection conn) {
    final notifier = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(lastFrameStateProvider);
    late final StreamController<ConnectionDiagnostics> out;
    StreamSubscription<Message>? sub;
    void emit() {
      if (!out.isClosed) out.add(_snapshot(conn));
    }

    out = StreamController<ConnectionDiagnostics>(
      onListen: () {
        emit();
        sub = conn.messages.listen((_) => emit());
        notifier.addListener(emit);
      },
      onCancel: () async {
        await sub?.cancel();
        notifier.removeListener(emit);
        await out.close();
      },
    );
    return out.stream;
  }

  @override
  Widget build(BuildContext context) {
    final container = ProviderScope.containerOf(context, listen: false);
    final RelayConnection conn = container.read(relayConnectionProvider);
    final BiometricGate gate = container.read(biometricGateProvider);
    final KeystoreService keystore = container.read(keystoreServiceProvider);
    final PlainStore plainStore = PlainStore();
    final String hostId = widget.hostId;
    return ConnectionScreen(
      hostId: hostId,
      hostName: conn.lastHostInfo?.hostName ?? hostId,
      connectionState: conn.connectionState,
      initialConnectionState: conn.isConnected
          ? const RelayConnected()
          : const RelayDisconnected(),
      relayOrigin: _relayOrigin,
      diagnostics: _diagnostics(conn),
      messages: conn.messages,
      alertsDeliveryWord: _alertsWord,
      onOpenAlertsSettings: () =>
          unawaited(context.push('/settings/notifications')),
      onReconnect: () => _reconnectHost(
        connection: conn,
        keystore: keystore,
        plainStore: plainStore,
        gate: gate,
        hostId: hostId,
      ),
      onDisconnect: conn.disconnect,
      onDisconnected: () => context.go('/hosts'),
    );
  }
}

/// The `/hosts/:hostId/devices` route body. Loads this phone's own
/// `device_id` (`plain_store.dart`'s `PlainStore.deviceId`) once on mount —
/// an async read a `GoRoute.builder` cannot await — then renders the real
/// [DeviceListScreen].
class _DeviceListRoute extends StatefulWidget {
  const _DeviceListRoute({
    required this.hostName,
    required this.messages,
    required this.connectionState,
    required this.send,
    this.onRemovedThisPhone,
  });

  final String hostName;
  final Stream<Message> messages;
  final Stream<RelayConnectionState> connectionState;
  final SendFrame send;
  final VoidCallback? onRemovedThisPhone;

  @override
  State<_DeviceListRoute> createState() => _DeviceListRouteState();
}

class _DeviceListRouteState extends State<_DeviceListRoute> {
  String? _localDeviceId;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final Result<String> result = await PlainStore().deviceId();
    if (!mounted) return;
    setState(() => _localDeviceId = result is Ok<String> ? result.value : '');
  }

  @override
  Widget build(BuildContext context) {
    final String? id = _localDeviceId;
    if (id == null) {
      return const SizedBox.shrink();
    }
    return DeviceListScreen(
      hostName: widget.hostName,
      localDeviceId: id,
      messages: widget.messages,
      connectionState: widget.connectionState,
      send: widget.send,
      onRemovedThisPhone: widget.onRemovedThisPhone,
    );
  }
}

/// The `/settings/about/licences/:package` route body for a direct deep
/// link, when no `extra` payload rode along with the push (see that route's
/// own comment). Re-derives the package's licence entries from
/// `about_screen.dart`'s `loadLicensedPackages`.
class _LicenceDetailRoute extends StatefulWidget {
  const _LicenceDetailRoute({required this.packageName});

  final String packageName;

  @override
  State<_LicenceDetailRoute> createState() => _LicenceDetailRouteState();
}

class _LicenceDetailRouteState extends State<_LicenceDetailRoute> {
  List<LicensedPackage>? _packages;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final List<LicensedPackage> packages = await loadLicensedPackages();
    if (mounted) {
      setState(() => _packages = packages);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<LicensedPackage>? packages = _packages;
    if (packages == null) {
      return const SizedBox.shrink();
    }
    List<LicenseEntry> entries = const <LicenseEntry>[];
    for (final LicensedPackage package in packages) {
      if (package.name == widget.packageName) {
        entries = package.entries;
        break;
      }
    }
    return LicenceDetailScreen(
      packageName: widget.packageName,
      entries: entries,
    );
  }
}

/// Clears a Device revoked mid-session (R-13-054, R-13-055), fired from
/// [TerminalScreen.onRevoked]: disconnects, clears [hostId]'s secrets and
/// non-secret record via `pairing.dart`'s `clearRevokedHost` (never
/// reimplemented here — that function already names exactly this as its own
/// purpose), and routes to `/welcome` once no saved computer remains, else
/// to `/hosts` per R-13-055's "the only way out is back to the pairing
/// screen".
Future<void> _handleHostRevoked({
  required BuildContext context,
  required String hostId,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final RelayConnection conn = container.read(relayConnectionProvider);
  await conn.disconnect();
  final Result<bool> result = await clearRevokedHost(
    keystore: container.read(keystoreServiceProvider),
    plainStore: PlainStore(),
    hostId: hostId,
  );
  final bool noneLeft = result is Ok<bool> && result.value;
  if (!context.mounted) return;
  context.go(noneLeft ? '/welcome' : '/hosts');
}

/// R-31-17-02's two session-scoped contexts for the create menu: the pane this phone opened
/// last on the connected computer (the split target) and the workspace it created last (the
/// `New tab` target). Session scope is exactly what the rule asks for, so a cold start offers
/// no split and a plain variable is the whole mechanism. A pane that has since closed is
/// harmless: `CreateSheet` resolves the id against the fresh snapshot and shows the disabled
/// row when it is gone.
String? _lastOpenedPaneId;
String? _lastCreatedWorkspaceId;

/// `AgentListScreen`'s `New` action (the `add` glyph in its app bar on both platforms since
/// 2026-09-09, R-03-109; the `Agents` destination alone carries one since 2026-09-04,
/// R-31-17-01), wired here rather than in the screen itself: opening the real [CreateSheet]
/// needs a live [RelayConnection] and a fresh `TreeSnapshot` (`pane_actions.dart`'s
/// `reconcileTree`), mirroring every other screen's "a caller supplies the data" idiom this
/// file already uses everywhere else.
Future<void> _openCreateSheet(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final RelayConnection conn = container.read(relayConnectionProvider);
  final HostInfo? hostInfo = conn.lastHostInfo;
  if (hostInfo == null) {
    // The control that calls this is disabled while the link is down
    // (`agent_list_screen.dart` gates it on the live connection state), so a null
    // `lastHostInfo` here is the stale-frame race: the tap landed before the drop (or a
    // never-completed handshake) reached the screen. Report the same sentence the
    // dropped-link `Err` below surfaces (R-30-807's offline wording family), never nothing.
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(notConnectedMessage)));
    }
    return;
  }
  final Result<TreeSnapshot> result = await reconcileTree(
    messages: conn.messages,
    connectionState: conn.connectionState,
    send: conn.send,
  );
  if (result is Err<TreeSnapshot>) {
    // R-30-803: the real cause (for example `pane_actions.dart`'s `notConnectedMessage` on a
    // down link), never a fixed sentence that hides it.
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.message)));
    }
    return;
  }
  if (result is! Ok<TreeSnapshot>) return;
  if (!context.mounted) return;
  await showCreateSheet(
    context,
    hostName: hostInfo.hostName,
    snapshot: result.value,
    currentPaneId: _lastOpenedPaneId,
    lastCreatedWorkspaceId: _lastCreatedWorkspaceId,
    messages: conn.messages,
    connectionState: conn.connectionState,
    send: conn.send,
    onCreated: (CreateResult created) {
      // Every create acknowledgement is followed by one fresh `tree_request`. The
      // acknowledgement itself carries no snapshot, and the Host's one `events.subscribe`
      // subscription -- opened at session start since 2026-09-08 (`crates/herdr-relay/src/
      // bridge.rs` `bridge_thread`; an earlier note here claimed it opened only on
      // `watch_pane`, which is stale) -- resubscribes before its next `tree_update`
      // (R-02-013a), so the explicit request is what lands the new entity in the agent list
      // at once. The reply is one `tree_snapshot` on the shared `messages` stream:
      // `AgentListService` applies it like any other snapshot, so the list gains the new
      // entity with its search and collapse state untouched. Only a failure is surfaced here,
      // as the raw text (R-30-803), because nothing else reports it.
      unawaited(_refreshTreeAfterCreate(context, conn));
      if (created is CreatedWorkspace) {
        _lastCreatedWorkspaceId = created.workspaceId;
      }
      if (created is CreatedPane && context.mounted) {
        unawaited(
          context.push('/hosts/${hostInfo.hostId}/panes/${created.paneId}'),
        );
      }
    },
  );
}

/// One `tree_request` after a create acknowledgement (see [_openCreateSheet]'s `onCreated`).
/// The snapshot itself is consumed by every listener on [RelayConnection.messages]; this
/// function only reports a refusal or a dropped link, in the reply's own words.
Future<void> _refreshTreeAfterCreate(
  BuildContext context,
  RelayConnection conn,
) async {
  final Result<TreeSnapshot> result = await reconcileTree(
    messages: conn.messages,
    connectionState: conn.connectionState,
    send: conn.send,
  );
  if (result is Err<TreeSnapshot> && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.message)));
  }
}

/// Wraps [AgentListScreen] at `/hosts/:hostId/agents` to add the one-time App Lock offer of
/// R-03-091/R-30-521, at the exact same "first arrival at the agent list" moment
/// R-30-509 places the (separately unwired -- see [_maybeOfferAppLock]'s own doc comment)
/// notification-permission ask. The screen itself is built identically to the plain inline
/// builder every other branch-default route in this file uses; only the post-frame hook is
/// new.
class _AgentListRoute extends StatefulWidget {
  const _AgentListRoute({required this.hostId});

  final String hostId;

  @override
  State<_AgentListRoute> createState() => _AgentListRouteState();
}

class _AgentListRouteState extends State<_AgentListRoute> {
  @override
  void initState() {
    super.initState();
    // Fires after the first frame, mirroring `_openCreateSheet`'s own "needs a live
    // `BuildContext` with a mounted `Navigator`" requirement -- `showModalBottomSheet` inside
    // `initState` itself would run before that `Navigator` exists.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_maybeOfferAppLock(context)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final container = ProviderScope.containerOf(context, listen: false);
    final RelayConnection conn = container.read(relayConnectionProvider);
    final AgentStatusService agentStatus = container.read(
      agentStatusServiceProvider,
    );
    final String hostId = widget.hostId;
    return AgentListScreen(
      hostId: hostId,
      hostName: conn.lastHostInfo?.hostName ?? hostId,
      messages: conn.messages,
      connectionState: conn.connectionState,
      initialConnectionState: conn.isConnected
          ? const RelayConnected()
          : const RelayDisconnected(),
      send: conn.send,
      unseenAttention: agentStatus.unseenAttention,
      currentAttention: agentStatus.currentAttention,
      onMarkSeen: agentStatus.markSeen,
      onNotePaneOpened: agentStatus.notePaneOpened,
      onOpenPane: (String paneId) =>
          unawaited(context.push('/hosts/$hostId/panes/$paneId')),
      onHostChip: () => unawaited(context.push('/hosts')),
      onOpenAlertsSettings: () =>
          unawaited(context.push('/settings/notifications')),
      onOpenDiagnostics: () =>
          unawaited(context.push('/hosts/$hostId/diagnostics')),
      onCreate: () => unawaited(_openCreateSheet(context)),
      // R-03-112 (2026-09-09): the same legend the Settings row pushes. A `push` from this
      // branch lands the `/settings/status-colours` page on this branch's own `Navigator`
      // (`go_router`'s `RouteMatchList.push` merges the pushed match into the shell match it
      // shares with the current location, and the shell keeps the current branch key), so the
      // bottom chrome stays, per R-30-045; no second route is needed.
      onOpenStatusColours: () =>
          unawaited(context.push('/settings/status-colours')),
    );
  }
}

/// R-03-091/R-30-521/R-30-522/R-30-523: the one-time App Lock offer. `appLockOfferShown`
/// makes the trigger moment itself -- not just the sheet -- fire exactly once: this route is
/// unreachable without a `hostId`, which does not exist before a first successful pair, so the
/// very first arrival here in the phone's whole history already satisfies "the first arrival
/// at the agent list after the first successful pair" with no separate pairing-moment flag to
/// track.
///
/// **Disclosed, pre-existing gap.** R-30-509/R-30-521 place this offer "after the platform
/// notification-permission request resolves". `notifications.dart`'s own doc comment on
/// `requestPermission()` already names this exact same arrival as its call site, but nothing
/// in this repository calls `requestPermission()` anywhere -- confirmed by a repository-wide
/// search before writing this function. That gap predates this change and is out of this
/// task's scope (`docs/13-security-pairing.md` and `docs/22-platform-integration.md` name no
/// App-Lock-specific rule that depends on fixing it); it is reported here, not silently fixed
/// or silently left unmentioned, per `AGENTS.md`'s "never diverge silently from the owning
/// document". This function wires the App Lock sheet at the same conceptual integration point
/// the notification permission belongs at, regardless.
Future<void> _maybeOfferAppLock(BuildContext context) async {
  if (!context.mounted) {
    return;
  }
  final container = ProviderScope.containerOf(context, listen: false);
  final AppSettingsService appSettings = container.read(
    appSettingsServiceProvider,
  );
  final loaded = await appSettings.load();
  if (!context.mounted) {
    return;
  }
  final AppSettings settings = loaded is Ok<AppSettings>
      ? loaded.value
      : appSettings.current;
  if (settings.appLockOfferShown) {
    return;
  }
  // R-03-091: the trigger moment itself only ever happens once, whether or not the sheet
  // below actually shows (R-30-523's silent-skip case included).
  await appSettings.setAppLockOfferShown(value: true);
  if (!context.mounted) {
    return;
  }
  final bool supported = await LocalAuthentication().isDeviceSupported();
  if (!context.mounted || !supported) {
    return; // R-30-523: no screen-lock capability -- skip silently, leave App Lock off.
  }
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: AppColor.of(context).bgRaised,
    builder: (sheetContext) =>
        AppLockOfferSheet(onTurnOn: () => unawaited(_turnAppLockOn(context))),
  );
}

/// R-03-092/R-13-073/R-22-083: turns App Lock on from the one-time offer, sharing every
/// primitive `settings_screen.dart`'s own toggle uses -- `KeystoreService.retoggleProtection`
/// migrates the stored secrets, `AppSettingsService.setAppLockEnabled` persists the switch
/// only once that succeeds, and `BiometricGate.setAppLockEnabled` keeps the session-shared
/// gate in sync. A failure leaves App Lock off with no error surface: `docs/30-ux-spec.md`
/// R-30-522 names no failure copy for this sheet, and the switch itself, reachable from
/// Settings at any time per R-03-092, is the recovery path.
Future<void> _turnAppLockOn(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final KeystoreService keystore = container.read(keystoreServiceProvider);
  final BiometricGate gate = container.read(biometricGateProvider);
  final AppSettingsService appSettings = container.read(
    appSettingsServiceProvider,
  );
  final Result<List<PairedHostRecord>> pairedResult = await PlainStore()
      .pairedHosts();
  final List<String> hostIds = pairedResult is Ok<List<PairedHostRecord>>
      ? pairedResult.value.map((record) => record.hostId).toList()
      : const <String>[];
  final Result<void> retoggleResult = await keystore.retoggleProtection(
    appLockEnabled: true,
    hostIds: hostIds,
  );
  if (retoggleResult is! Ok<void>) {
    return;
  }
  final Result<void> settingResult = await appSettings.setAppLockEnabled(
    value: true,
  );
  if (settingResult is! Ok<void>) {
    return;
  }
  gate.setAppLockEnabled(value: true);
}

/// The one-time App Lock offer's content, R-30-522's exact copy. Public, unlike every other
/// private sheet/route helper in this file, specifically so `test/routing_test.dart` can pump
/// it directly with no `go_router`/`Riverpod`/platform-channel plumbing -- mirroring
/// `welcome_screen.dart`'s `WelcomeScreenBody` split. Shaped exactly like
/// `settings_screen.dart`'s private `_RelayAddressSheet`/`_NameSheet`: a grab handle, a
/// heading, one line of body text, one filled button, one text-button cancel row -- never new
/// sheet chrome. `R-30-005` forbids a modal dialog for this choice; this is the bottom sheet
/// that rule requires instead.
class AppLockOfferSheet extends StatelessWidget {
  const AppLockOfferSheet({super.key, this.onTurnOn});

  /// Fires once, right before the sheet closes, when the person taps `Turn on`. `null` is a
  /// deliberate no-op (R-90-016).
  final VoidCallback? onTurnOn;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.space4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const _AppLockSheetGrabHandle(),
              const SizedBox(height: AppSpace.space4),
              Text(
                "Lock the app behind your phone's screen lock?",
                style: AppType.heading.copyWith(color: color.fgPrimary),
              ),
              const SizedBox(height: AppSpace.space2),
              Text(
                'You can turn this on or off later in Settings.',
                style: AppType.body.copyWith(color: color.fgSecondary),
              ),
              const SizedBox(height: AppSpace.space4),
              AppFilledButton(
                label: 'Turn on',
                onPressed: () {
                  onTurnOn?.call();
                  Navigator.of(context).pop();
                },
              ),
              const SizedBox(height: AppSpace.space2),
              Center(
                child: AppTextButton(
                  label: 'Not now',
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

/// The grab handle: `size.grab` at `radius.full` in `color.fg.disabled`, duplicated from
/// `settings_screen.dart`'s own private `_GrabHandle` per that widget's own doc comment
/// (R-32-546, R-90-018 -- no shared bottom-sheet primitive exists on any package's `Paths.`
/// line yet).
class _AppLockSheetGrabHandle extends StatelessWidget {
  const _AppLockSheetGrabHandle();

  @override
  Widget build(BuildContext context) => Center(
    child: ExcludeSemantics(
      child: Container(
        width: AppSize.grabWidth,
        height: AppSize.grabHeight,
        decoration: BoxDecoration(
          color: AppColor.of(context).fgDisabled,
          borderRadius: BorderRadius.circular(AppSize.grabHeight / 2),
        ),
      ),
    ),
  );
}
