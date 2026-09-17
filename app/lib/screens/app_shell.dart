/// The three-destination shell: `Agents`, `Notifications` and `Settings`, per
/// `docs/30-ux-spec.md` R-30-021 (decided 2026-09-04 by the product owner:
/// `Notifications` replaced `Panes`), with the native control of each
/// platform, per `docs/33-platform-chrome.md` R-33-033 to R-33-038, and
/// the persistent connection strip of R-33-036.
///
/// This widget owns only the chrome shared across every branch: the
/// bottom tab/navigation bar, its unread badge on `Notifications`
/// (R-31-07-05, the badge of `docs/32-design-language.md` section 7.5), and
/// the connection strip above it. The top app bar, including the create
/// control (R-33-034, `Agents` only per R-31-17-01), is scoped to whichever
/// screen sits on top of each branch's own `Navigator`, because a pushed
/// route needs its own title and back control, per R-33-070, never a bar
/// this widget shares across branches.
///
/// R-30-045, R-33-071.1: [AppShell.navigationShell] is `go_router`'s
/// `StatefulShellRoute.indexedStack` body, which gives every branch its
/// own `Navigator`. A route a branch pushes stays inside that
/// `Navigator`, and this widget keeps wrapping it, so the bottom chrome
/// never leaves the screen. Only the terminal route, pushed on the root
/// `Navigator` by `routing.dart`, sits outside this widget entirely, per
/// R-30-022 and R-33-071.4.
library;

import 'package:cupertino_ui/cupertino_ui.dart'
    show
        AsyncSnapshot,
        Border,
        BuildContext,
        Column,
        CupertinoPageScaffold,
        CupertinoTabBar,
        CupertinoTheme,
        CupertinoThemeData,
        Expanded,
        MainAxisSize,
        MediaQuery,
        SafeArea,
        StatelessWidget,
        StreamBuilder,
        Text,
        TextDecoration,
        VoidCallback,
        Widget;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:go_router/go_router.dart' show StatefulNavigationShell;
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart'
    show
        Badge,
        BottomNavigationBarItem,
        Icon,
        IconData,
        NavigationBar,
        NavigationDestination,
        Scaffold;

import '../services/agent_status.dart' show NotificationItem;
import '../services/relay.dart'
    show
        RelayConnected,
        RelayConnecting,
        RelayConnectionState,
        RelayDisconnected,
        RelayReconnecting,
        RelayRegistrationError,
        RelayRegistrationErrorCode,
        RelayRevoked;
import '../widgets/app_strip.dart';
import '../widgets/status_bar.dart' show BarState;
import '../widgets/theme/app_color.dart';
import '../widgets/theme/app_size.dart';
import '../widgets/theme/app_type.dart';

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

/// The three destinations, in the fixed order of R-33-035: `smart_toy`
/// for `Agents`, `notifications` for `Notifications`, `settings` for
/// `Settings`, per `docs/32-design-language.md` R-32-401.
const List<String> _destinationLabels = <String>[
  'Agents',
  'Notifications',
  'Settings',
];
const List<IconData> _destinationIcons = <IconData>[
  Symbols.smart_toy_rounded,
  Symbols.notifications_rounded,
  Symbols.settings_rounded,
];

/// The index of `Notifications` in the lists above, the one destination that carries a badge.
const int _notificationsIndex = 1;

class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.navigationShell,
    required this.connectionState,
    required this.isConnected,
    required this.connectedHostName,
    required this.onOpenDiagnostics,
    required this.notifications,
    required this.currentNotifications,
  });

  /// `go_router`'s branch-switching body; see the file doc comment.
  final StatefulNavigationShell navigationShell;

  /// `RelayConnection.connectionState` (`relay.dart`, `WP-14-a`), the one
  /// live link. The strip of R-33-036 redraws on every emission.
  final Stream<RelayConnectionState> connectionState;

  /// `RelayConnection.isConnected`, read at build. The stream above is a
  /// broadcast stream with no replay, and a pairing emits `RelayConnected`
  /// before the router builds this shell, so the first frame must ask.
  final bool Function() isConnected;

  /// The display name of the computer the link is for, read at each
  /// redraw (`RelayConnection.lastHostInfo?.hostName`); `null` before the
  /// first `host_info`.
  final String? Function() connectedHostName;

  /// Returns the action that opens the known computer's diagnostics
  /// (`/hosts/:hostId/diagnostics`), or `null` when no computer is known.
  /// The strip calls it on a failure state (R-32-561, R-30-806).
  final VoidCallback? Function() onOpenDiagnostics;

  /// The current Host's notification log, shared with `NotificationsScreen`.
  /// The badge counts only unread rows and redraws on every emission.
  final Stream<List<NotificationItem>> notifications;

  /// The same log at build time, before the stream's first emission.
  final List<NotificationItem> Function() currentNotifications;

  Widget _strip() => _ConnectionStrip(
    connectionState: connectionState,
    isConnected: isConnected,
    connectedHostName: connectedHostName,
    onOpenDiagnostics: onOpenDiagnostics,
  );

  @override
  Widget build(BuildContext context) {
    final int index = navigationShell.currentIndex;
    return StreamBuilder<List<NotificationItem>>(
      stream: notifications,
      builder:
          (
            BuildContext context,
            AsyncSnapshot<List<NotificationItem>> snapshot,
          ) {
            final int unread = (snapshot.data ?? currentNotifications())
                .where((entry) => !entry.seen)
                .length;
            return _isIos
                ? _iosShell(context, index, unread)
                : _androidShell(context, index, unread);
          },
    );
  }

  /// The destination glyph, with the platform's own count badge on `Notifications` while
  /// [unread] is above zero (R-32-518, amended 2026-09-09 per R-03-059): Flutter's [Badge]
  /// with its theme defaults, the filled `colorScheme.error` circle
  /// (`color.status.error`) with the count in `colorScheme.onError` (`color.fg.on_accent`)
  /// at the glyph's top-end corner. That is the Material 3 `NavigationBar` destination
  /// badge, and it is also the red circle a `CupertinoTabBar` item carries on iOS, which has
  /// no badge widget of its own. The glyph keeps its bar ink on both platforms, selected or
  /// not; the badge alone reports the attention. The count is exact and uncapped, per
  /// R-30-508.
  Widget _icon(int i, int unread) {
    final Icon icon = Icon(_destinationIcons[i], size: AppSize.iconLg);
    if (i != _notificationsIndex || unread == 0) {
      return icon;
    }
    return Badge(label: Text('$unread'), child: icon);
  }

  /// Android: `NavigationBar` per R-33-035 and the connection strip above
  /// it per R-33-036. No `FloatingActionButton`: since 2026-09-04 the
  /// create control belongs to the `Agents` screen alone (R-31-17-01), and
  /// `agent_list_screen.dart` draws it.
  Widget _androidShell(BuildContext context, int index, int unread) => Scaffold(
    body: navigationShell,
    // The bar pads the bottom system inset itself and paints its own surface
    // through it; an outer bottom SafeArea left a page-coloured band under
    // the bar (seen on iPhone, 2026-09-16).
    bottomNavigationBar: SafeArea(
      top: false,
      bottom: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _strip(),
          NavigationBar(
            selectedIndex: index,
            onDestinationSelected: _onDestinationSelected,
            height: AppSize.bottomNav,
            destinations: <Widget>[
              for (int i = 0; i < _destinationLabels.length; i++)
                NavigationDestination(
                  icon: _icon(i, unread),
                  label: _destinationLabels[i].toUpperCase(),
                ),
            ],
          ),
        ],
      ),
    ),
  );

  /// iOS: a full-width `CupertinoTabBar` per R-33-035, with the
  /// connection strip above it per R-33-036. `CupertinoTabScaffold` is not
  /// used here because it owns its own body-switching controller, which
  /// would compete with `navigationShell`'s.
  ///
  /// The bar draws no top edge of its own: the strip above it already ends in its
  /// `border.hairline`, and a second line directly under it read as one 2 px two-tone line
  /// (2026-09-08). The labels take `type.micro` through the bar's own
  /// `tabLabelTextStyle` seam, the one place `CupertinoTabBar` reads a label style from, so
  /// both platforms set the label of R-32-562 in the same token.
  ///
  /// Wraps in [CupertinoPageScaffold], not a bare `ColoredBox`, per R-41-020 and the
  /// identical fix on `welcome_screen.dart` and `lock_screen.dart`: [_ConnectionStrip]'s
  /// `Text` needs a real default text style, which `MaterialApp`'s ugly-on-purpose fallback
  /// replaces with a yellow double underline when no `Material`/`Cupertino` scaffold sits
  /// above it. Do not revert this to a bare `ColoredBox`.
  Widget _iosShell(BuildContext context, int index, int unread) {
    final AppColor color = AppColor.of(context);
    final CupertinoThemeData theme = CupertinoTheme.of(context);
    return CupertinoPageScaffold(
      backgroundColor: color.bgBase,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: <Widget>[
            // The bar below consumes the bottom inset; the body must not pad
            // for it too, as Material's Scaffold arranges on Android.
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeBottom: true,
                child: navigationShell,
              ),
            ),
            _strip(),
            CupertinoTheme(
              data: theme.copyWith(
                textTheme: theme.textTheme.copyWith(
                  tabLabelTextStyle: AppType.micro,
                ),
              ),
              child: CupertinoTabBar(
                currentIndex: index,
                onTap: _onDestinationSelected,
                backgroundColor: color.bgRaised,
                activeColor: color.accentText,
                inactiveColor: color.fgSecondary,
                height: AppSize.bottomNav,
                border: const Border(),
                items: <BottomNavigationBarItem>[
                  for (int i = 0; i < _destinationLabels.length; i++)
                    BottomNavigationBarItem(
                      icon: _icon(i, unread),
                      label: _destinationLabels[i].toUpperCase(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onDestinationSelected(int index) => navigationShell.goBranch(
    index,
    initialLocation: index == navigationShell.currentIndex,
  );
}

/// The persistent connection strip, per R-33-036: above the
/// `NavigationBar` on Android, above the `CupertinoTabBar` on iOS, drawn
/// once by Flutter for both, and identical on both. One caption per link
/// state, in the words the rest of the app already uses:
///
/// | State | Text |
/// | --- | --- |
/// | connected, name known | `Connected to <name>.` |
/// | connected, no `host_info` yet | `Connected.` |
/// | connecting or reconnecting | `Connecting to <name>...` (`Connecting...` without a name) |
/// | `RelayRevoked` | `This computer removed this phone. Pair again.` |
/// | registration error, host not registered | R-30-808's third sentence |
/// | any other disconnected state, a computer known | `Not connected to <name>.` |
/// | nothing known | `Not connected to a computer.` |
///
/// R-30-808's first two failures (no network, relay unreachable) are the
/// screens' job: they hold the connectivity watcher and the reconnect
/// ladder, and their own strips name the failure. This strip states the
/// link and never a cause it cannot know. When it reports a failure and a
/// computer is known it is tappable and routes to that computer's
/// diagnostics (R-32-561, R-30-806); a connected or connecting strip and a
/// strip with no computer to diagnose are plain text.
class _ConnectionStrip extends StatelessWidget {
  const _ConnectionStrip({
    required this.connectionState,
    required this.isConnected,
    required this.connectedHostName,
    required this.onOpenDiagnostics,
  });

  final Stream<RelayConnectionState> connectionState;
  final bool Function() isConnected;
  final String? Function() connectedHostName;

  /// Opens `/hosts/:hostId/diagnostics` for the known computer; `null`
  /// when no computer is known, which leaves the strip plain.
  final VoidCallback? Function() onOpenDiagnostics;

  static String textFor(RelayConnectionState state, String? name) {
    final String to = name == null ? '' : ' to $name';
    return switch (state) {
      RelayConnected() => name == null ? 'Connected.' : 'Connected to $name.',
      RelayConnecting() || RelayReconnecting() => 'Connecting$to...',
      RelayRevoked() => 'This computer removed this phone. Pair again.',
      RelayRegistrationError(code: RelayRegistrationErrorCode.handleUnknown) =>
        'The computer is not connected to the relay. Open its Relay pane.',
      RelayRegistrationError() || RelayDisconnected() =>
        name == null ? 'Not connected to a computer.' : 'Not connected$to.',
    };
  }

  /// A state that reports a link failure, per R-32-561.
  static bool isFailure(RelayConnectionState state) => switch (state) {
    RelayConnected() || RelayConnecting() => false,
    RelayReconnecting() ||
    RelayDisconnected() ||
    RelayRegistrationError() ||
    RelayRevoked() => true,
  };

  /// The link's state bar (R-03-100; 2026-09-10, the owner found `Not
  /// connected` indistinguishable from connected): `ok` while connected,
  /// `warning` while a connection is in flight, `error` for every failure.
  static BarState barStateFor(RelayConnectionState state) => switch (state) {
    RelayConnected() => BarState.ok,
    RelayConnecting() || RelayReconnecting() => BarState.warning,
    RelayDisconnected() ||
    RelayRegistrationError() ||
    RelayRevoked() => BarState.error,
  };

  @override
  Widget build(BuildContext context) => StreamBuilder<RelayConnectionState>(
    stream: connectionState,
    initialData: isConnected()
        ? const RelayConnected()
        : const RelayDisconnected(),
    builder:
        (BuildContext context, AsyncSnapshot<RelayConnectionState> snapshot) {
          final RelayConnectionState state = snapshot.requireData;
          final bool failure = isFailure(state);
          final AppColor color = AppColor.of(context);
          return AppStrip(
            state: barStateFor(state),
            onTapDestination: failure ? onOpenDiagnostics() : null,
            child: Text(
              textFor(state, connectedHostName()),
              // A failure reads in primary ink and body weight, so the
              // strip is not one more caption; connected stays quiet.
              style: (failure ? AppType.bodyStrong : AppType.caption).copyWith(
                color: failure ? color.fgPrimary : color.fgSecondary,
                decoration: TextDecoration.none,
              ),
            ),
          );
        },
  );
}
