/// Golden test for `ActionsScreen` (`app/lib/screens/actions_screen.dart`, `WP-18-f`), the
/// `Default` state row of `docs/31-mockups/18-actions.md`'s `## States` table (R-90-011): the
/// action list returned and a pane is in scope, the mockup's third wireframe. Rendered in both
/// Selenized dark and light (R-32-012).
///
/// The connection-fake `_Harness` (a `StreamController` pair plus a recording `send`) mirrors
/// `actions_screen_test.dart`'s own class, rather than a second fake-service scaffold:
/// `ActionsScreen` is stateful and reads the action list off its own `ActionListCache`, so it
/// cannot be golden-tested as a pure body the way `lock_screen_golden_test.dart` renders
/// `LockScreenBody` directly.
///
/// Fonts, the app theme and the 375 x 667 reference size come from `golden_support.dart`
/// (`loadAppFonts`, `goldenApp`, `goldenReferenceSize`); see its doc comment for why.
/// `devicePixelRatio` stays fixed at 1.0.
library;

import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/models/message.dart';
import 'package:herdr_mobile/models/messages/action_list.dart';
import 'package:herdr_mobile/models/messages/action_list_entry.dart';
import 'package:herdr_mobile/models/messages/host_action_ack.dart';
import 'package:herdr_mobile/models/messages/host_action_kind.dart';
import 'package:herdr_mobile/screens/actions_screen.dart';
import 'package:herdr_mobile/services/host_actions.dart';
import 'package:herdr_mobile/services/relay.dart';
import 'package:herdr_mobile/widgets/app_ground.dart' show EmptyMark;
import 'package:herdr_mobile/widgets/ground_grid.dart' show GroundGrid;

import 'golden_support.dart';

class _Harness {
  _Harness()
    : messages = StreamController<Message>.broadcast(),
      connectionState = StreamController<RelayConnectionState>.broadcast();

  final StreamController<Message> messages;
  final StreamController<RelayConnectionState> connectionState;

  void send(Message message, {String? corr}) {}

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

/// `herdr-scheduled` and `herdr-sidebar`, both open, plus the collapsed `tab-smart-rename`
/// group, on a pane scope. The mockup's own live-measured titles and descriptions
/// (`docs/31-mockups/18-actions.md`'s third wireframe).
const _paneScope = ActionScope(
  workspaceId: 'ws-1',
  workspaceName: 'herdr-relay',
  tabId: 'tab-1',
  tabName: 'plugin',
  paneId: 'pane-1',
  paneName: 'pane 1',
);

const _actions = <ActionListEntry>[
  ActionListEntry(
    pluginId: 'herdr-scheduled',
    actionId: 'open',
    title: 'Scheduled jobs',
    description: 'Opens the scheduled job manager on Windows.',
  ),
  ActionListEntry(
    pluginId: 'herdr-scheduled',
    actionId: 'sync',
    title: 'Sync scheduled jobs',
    description: 'Reconciles the job files into Windows Task Scheduler.',
  ),
  ActionListEntry(
    pluginId: 'herdr-sidebar',
    actionId: 'toggle-source-control',
    title: 'Toggle source control',
    description:
        'Open a separate Source Control pane (focus it if open; close it '
        'if focused).',
  ),
  ActionListEntry(
    pluginId: 'herdr-sidebar',
    actionId: 'toggle',
    title: 'Toggle sidebar',
  ),
  ActionListEntry(
    pluginId: 'herdr-sidebar',
    actionId: 'redeploy',
    title: 'Redeploy sidebar panes',
    description:
        'Close all sidebar panes in every workspace so they respawn on the '
        'latest build.',
  ),
  ActionListEntry(
    pluginId: 'tab-smart-rename',
    actionId: 'current-tab',
    title: 'Smart Rename: current tab',
    contexts: ['tab', 'pane'],
  ),
  ActionListEntry(
    pluginId: 'tab-smart-rename',
    actionId: 'all-tabs',
    title: 'Smart Rename: all tabs',
    contexts: ['tab', 'pane'],
  ),
  ActionListEntry(
    pluginId: 'tab-smart-rename',
    actionId: 'status',
    title: 'Smart Rename: status',
    contexts: ['tab', 'pane'],
  ),
  ActionListEntry(
    pluginId: 'tab-smart-rename',
    actionId: 'start',
    title: 'Smart Rename: start',
    contexts: ['global', 'workspace'],
  ),
  ActionListEntry(
    pluginId: 'tab-smart-rename',
    actionId: 'reset-tab',
    title: 'Smart Rename: reset tab',
    contexts: ['tab', 'pane'],
  ),
];

const _themes = <(String, Brightness)>[
  ('dark', Brightness.dark),
  ('light', Brightness.light),
];

void main() {
  setUpAll(loadAppFonts);

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    final platformSuffix = platform == TargetPlatform.iOS ? '_ios' : '';
    for (final (themeName, brightness) in _themes) {
      testWidgets(
        'default ($themeName, ${platform.name}) matches docs/31-mockups/18-actions.md',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          tester.view.physicalSize = goldenReferenceSize;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          final harness = _Harness();
          addTearDown(harness.dispose);
          await tester.pumpWidget(
            goldenApp(
              brightness: brightness,
              child: ActionsScreen(
                hostId: 'host-1',
                hostName: 'patrick-desk',
                messages: harness.messages.stream,
                connectionState: harness.connectionState.stream,
                send: harness.send,
                scope: _paneScope,
              ),
            ),
          );
          await harness.deliver(
            tester,
            const Message.actionList(ActionList(actions: _actions)),
          );
          // `tab-smart-rename` starts collapsed, matching the mockup's third wireframe.
          await tester.tap(find.text('tab-smart-rename'));
          await tester.pumpAndSettle();

          // Structural proof alongside the visual one: the callouts the mockup names are really
          // present in the tree, not just painted to look right by coincidence.
          expect(find.text('Actions on patrick-desk'), findsOneWidget);
          expect(
            find.text('A tap sends pane 1 as the context.'),
            findsOneWidget,
          );
          // The wireframe writes `>`; the app renders `›` (U+203A) with hair spaces (R-32-572).
          expect(
            find.text(
              'herdr-relay\u2009\u203A\u2009plugin\u2009\u203A\u2009pane 1',
            ),
            findsOneWidget,
          );
          expect(find.text('herdr-scheduled'), findsOneWidget);
          expect(find.text('2 actions'), findsOneWidget);
          expect(find.text('herdr-sidebar'), findsOneWidget);
          expect(find.text('3 actions'), findsOneWidget);
          expect(find.text('tab-smart-rename'), findsOneWidget);
          expect(find.text('5 actions'), findsOneWidget);
          expect(find.text('Smart Rename: reset tab'), findsNothing);
          // R-03-107 (amended 2026-09-09): a list with rows paints plain `color.bg.base`, no grid.
          expect(find.byType(GroundGrid), findsNothing);

          await expectLater(
            find.byType(ActionsScreen),
            matchesGoldenFile(
              'goldens/actions_screen_default${platformSuffix}_$themeName.png',
            ),
          );
          await tester.tap(find.text('Scheduled jobs'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          await expectLater(
            find.byType(ActionsScreen),
            matchesGoldenFile(
              'goldens/actions_screen_pending${platformSuffix}_$themeName.png',
            ),
          );
          await harness.deliver(
            tester,
            const Message.hostActionAck(
              HostActionAck(
                action: HostActionKind.pluginInvoke,
                success: true,
                paneId: 'pane-new',
              ),
            ),
          );
          debugDefaultTargetPlatformOverride = null;
        },
      );

      testWidgets(
        'empty ($themeName, ${platform.name}) matches docs/31-mockups/18-actions.md',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          tester.view.physicalSize = goldenReferenceSize;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          final harness = _Harness();
          addTearDown(harness.dispose);
          await tester.pumpWidget(
            goldenApp(
              brightness: brightness,
              child: ActionsScreen(
                hostId: 'host-1',
                hostName: 'patrick-desk',
                messages: harness.messages.stream,
                connectionState: harness.connectionState.stream,
                send: harness.send,
                scope: _paneScope,
              ),
            ),
          );
          await harness.deliver(
            tester,
            const Message.actionList(ActionList(actions: <ActionListEntry>[])),
          );
          await precacheBrandMark(tester, find.byType(ActionsScreen));
          await tester.pumpAndSettle();

          // R-03-107 (amended 2026-09-09): the ninth wireframe's block sits on the ground grid
          // inside the mark; the list's scope strip is absent, because there is no list.
          expect(
            find.descendant(
              of: find.descendant(
                of: find.byType(GroundGrid),
                matching: find.byType(EmptyMark),
              ),
              matching: find.text(
                'No plugin on patrick-desk offers an action.',
              ),
            ),
            findsOneWidget,
          );
          expect(
            find.text(
              'Install a Herdr plugin on the computer, then come back.',
            ),
            findsOneWidget,
          );
          expect(find.text('A tap sends pane 1 as the context.'), findsNothing);

          await expectLater(
            find.byType(ActionsScreen),
            matchesGoldenFile(
              'goldens/actions_screen_empty${platformSuffix}_$themeName.png',
            ),
          );
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }
  }
}
