/// Tests `ActionsScreen` (`WP-18-f`) against the context-gating table of
/// `docs/31-mockups/18-actions.md`: every declared `contexts` value is checked against both
/// the "computer alone" scope and a pane scope, treating the absent-`contexts` row as the
/// common case per R-30-966 and R-11-211. Also a privacy test (R-30-964, R-11-209): a
/// `command`, `manifest_path` or `plugin_root` field on the wire MUST NOT reach the screen,
/// and the `herdr-relay` plugin (R-31-18-16) MUST NOT be drawn at all. Two smoke tests round
/// out `plugin.invoke`'s two acknowledgement shapes (R-11-217a, R-11-217b).
library;

import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoNavigationBar;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart'
    show CustomScrollView, SizedBox, SliverList, Text, TextStyle;
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
import 'package:herdr_mobile/widgets/theme/app_color.dart' show AppColor;
import 'package:herdr_mobile/widgets/theme/app_type.dart' show AppType;
import 'package:material_ui/material_ui.dart' show AppBar, MaterialApp;

class _Harness {
  _Harness()
    : messages = StreamController<Message>.broadcast(),
      connectionState = StreamController<RelayConnectionState>.broadcast();

  final StreamController<Message> messages;
  final StreamController<RelayConnectionState> connectionState;
  final List<Message> sent = <Message>[];

  void send(Message message, {String? corr}) => sent.add(message);

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

Future<void> _pump(
  WidgetTester tester,
  _Harness harness, {
  required List<ActionListEntry> actions,
  ActionScope scope = const ActionScope(),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ActionsScreen(
        hostId: 'host-1',
        hostName: 'patrick-desk',
        messages: harness.messages.stream,
        connectionState: harness.connectionState.stream,
        send: harness.send,
        scope: scope,
      ),
    ),
  );
  await harness.deliver(
    tester,
    Message.actionList(ActionList(actions: actions)),
  );
}

const ActionScope _paneScope = ActionScope(
  workspaceId: 'ws-1',
  workspaceName: 'herdr-relay',
  tabId: 'tab-1',
  tabName: 'plugin',
  paneId: 'pane-1',
  paneName: 'pane 1',
);

void main() {
  group(
    'context gating (docs/31-mockups/18-actions.md context-gating table)',
    () {
      testWidgets(
        'absent contexts (the common case) is visible on both scopes',
        (WidgetTester tester) async {
          const entry = ActionListEntry(
            pluginId: 'herdr-scheduled',
            actionId: 'open',
            title: 'Scheduled jobs',
            description: 'Opens the scheduled job manager.',
          );
          final harnessA = _Harness();
          addTearDown(harnessA.dispose);
          await _pump(tester, harnessA, actions: [entry]);
          expect(find.text('Scheduled jobs'), findsOneWidget);

          final harnessB = _Harness();
          addTearDown(harnessB.dispose);
          await _pump(tester, harnessB, actions: [entry], scope: _paneScope);
          expect(find.text('Scheduled jobs'), findsOneWidget);
        },
      );

      testWidgets('global context is visible on both scopes', (
        WidgetTester tester,
      ) async {
        const entry = ActionListEntry(
          pluginId: 'p',
          actionId: 'a',
          title: 'Global action',
          contexts: ['global'],
        );
        final harness = _Harness();
        addTearDown(harness.dispose);
        await _pump(tester, harness, actions: [entry]);
        expect(find.text('Global action'), findsOneWidget);
      });

      testWidgets(
        '[global, workspace] is visible even with the computer alone in scope, per '
        '"a paired phone is always on one computer"',
        (WidgetTester tester) async {
          const entry = ActionListEntry(
            pluginId: 'p',
            actionId: 'a',
            title: 'Smart Rename: start',
            contexts: ['global', 'workspace'],
          );
          final harness = _Harness();
          addTearDown(harness.dispose);
          await _pump(tester, harness, actions: [entry]);
          expect(find.text('Smart Rename: start'), findsOneWidget);
        },
      );

      testWidgets('[tab, pane] is visible with a pane in scope, hidden and counted with the computer '
          'alone in scope', (WidgetTester tester) async {
        const entry = ActionListEntry(
          pluginId: 'tab-smart-rename',
          actionId: 'reset-tab',
          title: 'Smart Rename: reset tab',
          contexts: ['tab', 'pane'],
        );

        final harnessPane = _Harness();
        addTearDown(harnessPane.dispose);
        await _pump(tester, harnessPane, actions: [entry], scope: _paneScope);
        expect(find.text('Smart Rename: reset tab'), findsOneWidget);
        expect(find.textContaining('needs a tab or a pane'), findsNothing);

        final harnessAlone = _Harness();
        addTearDown(harnessAlone.dispose);
        await _pump(tester, harnessAlone, actions: [entry]);
        expect(find.text('Smart Rename: reset tab'), findsNothing);
        expect(find.text('1 action needs a tab or a pane.'), findsOneWidget);
      });

      testWidgets(
        'selection is never offered in version one, and is counted as hidden',
        (WidgetTester tester) async {
          const entry = ActionListEntry(
            pluginId: 'p',
            actionId: 'use-selection',
            title: 'Act on selection',
            contexts: ['selection'],
          );
          final harness = _Harness();
          addTearDown(harness.dispose);
          await _pump(tester, harness, actions: [entry], scope: _paneScope);
          expect(find.text('Act on selection'), findsNothing);
          expect(find.text('1 action needs a tab or a pane.'), findsOneWidget);
        },
      );
    },
  );

  testWidgets(
    'herdr-relay rows are removed entirely (R-31-18-16) and not counted in the hidden-row line',
    (WidgetTester tester) async {
      const relayAction = ActionListEntry(
        pluginId: 'herdr-relay',
        actionId: 'pair',
        title: 'Pair a new phone',
      );
      const otherAction = ActionListEntry(
        pluginId: 'herdr-sidebar',
        actionId: 'toggle',
        title: 'Toggle sidebar',
      );
      final harness = _Harness();
      addTearDown(harness.dispose);
      await _pump(tester, harness, actions: [relayAction, otherAction]);
      expect(find.text('Pair a new phone'), findsNothing);
      expect(find.textContaining('needs a tab or a pane'), findsNothing);
      expect(find.text('Toggle sidebar'), findsOneWidget);
    },
  );

  testWidgets('a command, manifest_path or plugin_root field on the wire never reaches this screen '
      '(privacy test, R-30-964, R-11-209)', (WidgetTester tester) async {
    final Map<String, dynamic> rawEntry = <String, dynamic>{
      'plugin_id': 'herdr-scheduled',
      'action_id': 'open',
      'title': 'Scheduled jobs',
      'description': 'Opens the scheduled job manager.',
      'command': ['/bin/sh', '-c', 'rm -rf /home/patrick/secret-project'],
      'manifest_path':
          '/home/patrick/.config/herdr/plugins/herdr-scheduled/manifest.toml',
      'plugin_root': '/home/patrick/.config/herdr/plugins/herdr-scheduled',
    };
    final harness = _Harness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ActionsScreen(
          hostId: 'host-1',
          hostName: 'patrick-desk',
          messages: harness.messages.stream,
          connectionState: harness.connectionState.stream,
          send: harness.send,
        ),
      ),
    );
    await harness.deliver(
      tester,
      Message.actionList(
        ActionList.fromJson(<String, dynamic>{
          'actions': [rawEntry],
        }),
      ),
    );

    expect(find.text('Scheduled jobs'), findsOneWidget);
    expect(find.textContaining('rm -rf'), findsNothing);
    expect(find.textContaining('manifest.toml'), findsNothing);
    expect(find.textContaining('/home/patrick'), findsNothing);
  });

  testWidgets('sends action_list_request on open', (WidgetTester tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ActionsScreen(
          hostId: 'host-1',
          hostName: 'patrick-desk',
          messages: harness.messages.stream,
          connectionState: harness.connectionState.stream,
          send: harness.send,
        ),
      ),
    );
    await tester.pump();
    expect(harness.sent, hasLength(1));
    expect(harness.sent.single, isA<MessageActionListRequest>());
    await harness.deliver(
      tester,
      const Message.actionList(ActionList(actions: [])),
    );
  });

  testWidgets(
    'a list with rows paints no ground grid and ends with its last row; the no-plugin '
    'state is the grid with the mark, its title in the display face in accent ink and its '
    'sentence in body secondary (R-03-107, amended 2026-09-09)',
    (WidgetTester tester) async {
      const entry = ActionListEntry(
        pluginId: 'herdr-scheduled',
        actionId: 'open',
        title: 'Scheduled jobs',
      );
      final loaded = _Harness();
      addTearDown(loaded.dispose);
      await _pump(tester, loaded, actions: [entry], scope: _paneScope);

      expect(find.byType(GroundGrid), findsNothing);
      expect(find.byType(EmptyMark), findsNothing);
      for (final String text in <String>[
        'A tap sends pane 1 as the context.',
        'herdr-scheduled',
        'Scheduled jobs',
      ]) {
        expect(find.text(text), findsOneWidget);
      }
      // The strip, the headers and the rows are the one sliver, and nothing follows it: no
      // remainder and no clearance for a create control (R-03-109).
      final CustomScrollView list = tester.widget<CustomScrollView>(
        find.byType(CustomScrollView),
      );
      expect(list.slivers, hasLength(1));
      expect(list.slivers.single, isA<SliverList>());

      final empty = _Harness();
      addTearDown(empty.dispose);
      // A fresh screen: the same widget type in the same slot would keep the first screen's
      // state and its cache on the first harness's streams.
      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(tester, empty, actions: const []);

      final Finder title = find.text(
        'No plugin on patrick-desk offers an action.',
      );
      expect(
        find.descendant(
          of: find.descendant(
            of: find.byType(GroundGrid),
            matching: find.byType(EmptyMark),
          ),
          matching: title,
        ),
        findsOneWidget,
      );
      final AppColor color = AppColor.of(tester.element(title));
      final TextStyle titleStyle = tester.widget<Text>(title).style!;
      expect(titleStyle.fontFamily, AppType.title.fontFamily);
      expect(titleStyle.fontSize, AppType.title.fontSize);
      expect(titleStyle.color, color.accentText);
      final TextStyle sentenceStyle = tester
          .widget<Text>(
            find.text(
              'Install a Herdr plugin on the computer, then come back.',
            ),
          )
          .style!;
      expect(sentenceStyle.fontSize, AppType.body.fontSize);
      expect(sentenceStyle.color, color.fgSecondary);
    },
  );

  testWidgets(
    'iOS: renders CupertinoNavigationBar with the host title, not Material AppBar',
    (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final harness = _Harness();
      addTearDown(harness.dispose);
      await _pump(tester, harness, actions: const []);

      expect(find.byType(CupertinoNavigationBar), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('Actions on patrick-desk'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'invoking an action with no pane_id in the ack shows the snackbar, never a route',
    (WidgetTester tester) async {
      const entry = ActionListEntry(
        pluginId: 'herdr-sidebar',
        actionId: 'toggle',
        title: 'Toggle sidebar',
      );
      final harness = _Harness();
      addTearDown(harness.dispose);
      String? openedHostId;
      String? openedPaneId;
      await tester.pumpWidget(
        MaterialApp(
          home: ActionsScreen(
            hostId: 'host-1',
            hostName: 'patrick-desk',
            messages: harness.messages.stream,
            connectionState: harness.connectionState.stream,
            send: harness.send,
            onOpenPane: (hostId, paneId) {
              openedHostId = hostId;
              openedPaneId = paneId;
            },
          ),
        ),
      );
      await harness.deliver(
        tester,
        const Message.actionList(ActionList(actions: [entry])),
      );

      await tester.tap(find.text('Toggle sidebar'));
      await tester.pump();
      final invokeSent = harness.sent
          .whereType<MessageHostAction>()
          .last
          .payload;
      expect(invokeSent.action, HostActionKind.pluginInvoke);
      expect(invokeSent.pluginId, 'herdr-sidebar');
      expect(invokeSent.actionId, 'toggle');

      await harness.deliver(
        tester,
        const Message.hostActionAck(
          HostActionAck(action: HostActionKind.pluginInvoke, success: true),
        ),
      );

      expect(
        find.text('Sent Toggle sidebar. Agents shows what exists now.'),
        findsOneWidget,
      );
      expect(openedHostId, isNull);
      expect(openedPaneId, isNull);
    },
  );

  testWidgets('invoking an action whose ack names a pane offers the route, and a tap on the strip '
      'takes it (R-31-18-13)', (WidgetTester tester) async {
    const entry = ActionListEntry(
      pluginId: 'herdr-scheduled',
      actionId: 'open',
      title: 'Scheduled jobs',
    );
    final harness = _Harness();
    addTearDown(harness.dispose);
    String? openedPaneId;
    await tester.pumpWidget(
      MaterialApp(
        home: ActionsScreen(
          hostId: 'host-1',
          hostName: 'patrick-desk',
          messages: harness.messages.stream,
          connectionState: harness.connectionState.stream,
          send: harness.send,
          onOpenPane: (hostId, paneId) => openedPaneId = paneId,
        ),
      ),
    );
    await harness.deliver(
      tester,
      const Message.actionList(ActionList(actions: [entry])),
    );

    await tester.tap(find.text('Scheduled jobs'));
    await tester.pump();
    await harness.deliver(
      tester,
      const Message.hostActionAck(
        HostActionAck(
          action: HostActionKind.pluginInvoke,
          success: true,
          paneId: 'pane-42',
        ),
      ),
    );

    expect(find.text('Scheduled jobs opened a pane.'), findsOneWidget);
    await tester.tap(find.text('Scheduled jobs opened a pane.'));
    await tester.pump();
    expect(openedPaneId, 'pane-42');
  });
}
