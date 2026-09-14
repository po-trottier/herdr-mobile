/// Tests `pane_actions.dart` (`WP-18-d`): the `host_action`/`host_action_ack` request-reply,
/// matching a reply by type, racing it against a connection drop (R-30-518), and the
/// `tree_request`/`tree_snapshot` reconciliation `reconcileTree` performs for it. Mirrors
/// `device_list_test.dart`'s own structure for the sibling `revoke_device` plumbing.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart';
import 'package:herdr_mobile/models/codes.dart';
import 'package:herdr_mobile/models/message.dart';
import 'package:herdr_mobile/models/messages/error_message.dart';
import 'package:herdr_mobile/models/messages/host_action_ack.dart';
import 'package:herdr_mobile/models/messages/host_action_kind.dart';
import 'package:herdr_mobile/models/messages/tree_snapshot.dart';
import 'package:herdr_mobile/services/pane_actions.dart';
import 'package:herdr_mobile/services/relay.dart';

void main() {
  group('createWorkspace / createTab / createPaneSplit', () {
    test(
      'createWorkspace sends focus:false and resolves HostActionApplied',
      () async {
        final messages = StreamController<Message>.broadcast();
        final connectionState =
            StreamController<RelayConnectionState>.broadcast();
        final sent = <Message>[];

        final future = createWorkspace(
          messages: messages.stream,
          connectionState: connectionState.stream,
          send: (message, {corr}) => sent.add(message),
        );
        await Future<void>.delayed(Duration.zero);
        final request = sent.single as MessageHostAction;
        expect(request.payload.action, HostActionKind.workspaceCreate);
        expect(request.payload.params, <String, dynamic>{'focus': false});

        const ack = HostActionAck(
          action: HostActionKind.workspaceCreate,
          success: true,
          resultId: 'workspace-1',
        );
        messages.add(const Message.hostActionAck(ack));

        final result = await future;
        expect(result, isA<HostActionApplied>());
        expect((result as HostActionApplied).ack.resultId, 'workspace-1');

        await messages.close();
        await connectionState.close();
      },
    );

    test('createTab carries the workspace_id and focus:false', () async {
      final messages = StreamController<Message>.broadcast();
      final connectionState =
          StreamController<RelayConnectionState>.broadcast();
      final sent = <Message>[];

      final future = createTab(
        messages: messages.stream,
        connectionState: connectionState.stream,
        send: (message, {corr}) => sent.add(message),
        workspaceId: 'workspace-1',
      );
      await Future<void>.delayed(Duration.zero);
      final request = sent.single as MessageHostAction;
      expect(request.payload.action, HostActionKind.tabCreate);
      expect(request.payload.workspaceId, 'workspace-1');
      expect(request.payload.params, <String, dynamic>{'focus': false});

      connectionState.add(const RelayDisconnected());
      final result = await future;
      expect(result, isA<HostActionOutcomeUnknown>());

      await messages.close();
      await connectionState.close();
    });

    test(
      'createPaneSplit carries pane_id as the split target and the direction',
      () async {
        final messages = StreamController<Message>.broadcast();
        final connectionState =
            StreamController<RelayConnectionState>.broadcast();
        final sent = <Message>[];

        final future = createPaneSplit(
          messages: messages.stream,
          connectionState: connectionState.stream,
          send: (message, {corr}) => sent.add(message),
          targetPaneId: 'pane-1',
          direction: 'right',
        );
        await Future<void>.delayed(Duration.zero);
        final request = sent.single as MessageHostAction;
        expect(request.payload.action, HostActionKind.paneSplit);
        expect(request.payload.paneId, 'pane-1');
        expect(request.payload.params, <String, dynamic>{
          'focus': false,
          'direction': 'right',
        });

        messages.add(
          const Message.error(
            ErrorMessage(
              code: ErrorCode.internalError,
              message: 'refused',
              fatal: false,
            ),
          ),
        );
        final result = await future;
        expect(result, isA<HostActionRefused>());
        expect((result as HostActionRefused).message, 'refused');

        await messages.close();
        await connectionState.close();
      },
    );
  });

  group('closePane', () {
    test('targets the pane and sends no params', () async {
      final sent = <Message>[];
      final messages = StreamController<Message>.broadcast();
      final connectionState =
          StreamController<RelayConnectionState>.broadcast();

      unawaited(
        closePane(
          messages: messages.stream,
          connectionState: connectionState.stream,
          send: (message, {corr}) => sent.add(message),
          paneId: 'pane-1',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final close = sent.single as MessageHostAction;
      expect(close.payload.action, HostActionKind.close);
      expect(close.payload.paneId, 'pane-1');
      expect(close.payload.params, isNull);

      await messages.close();
      await connectionState.close();
    });
  });

  group('reconcileTree', () {
    test('sends tree_request and resolves Ok on tree_snapshot', () async {
      final messages = StreamController<Message>.broadcast();
      final connectionState =
          StreamController<RelayConnectionState>.broadcast();
      final sent = <Message>[];

      final future = reconcileTree(
        messages: messages.stream,
        connectionState: connectionState.stream,
        send: (message, {corr}) => sent.add(message),
      );
      await Future<void>.delayed(Duration.zero);
      expect(sent.single, isA<MessageTreeRequest>());

      const snapshot = TreeSnapshot(
        workspaces: [],
        tabs: [],
        panes: [],
        agents: [],
      );
      messages.add(const Message.treeSnapshot(snapshot));

      final result = await future;
      expect(result, isA<Ok<TreeSnapshot>>());
      expect((result as Ok<TreeSnapshot>).value, snapshot);

      await messages.close();
      await connectionState.close();
    });

    test(
      'resolves Err when the connection drops before tree_snapshot arrives',
      () async {
        final messages = StreamController<Message>.broadcast();
        final connectionState =
            StreamController<RelayConnectionState>.broadcast();

        final future = reconcileTree(
          messages: messages.stream,
          connectionState: connectionState.stream,
          send: (message, {corr}) {},
        );
        connectionState.add(const RelayDisconnected());

        final result = await future;
        expect(result, isA<Err<TreeSnapshot>>());

        await messages.close();
        await connectionState.close();
      },
    );

    test('a send that throws RelayNotConnectedException on a down link resolves Err '
        'with the not-connected text instead of escaping the caller (inert + FAB, '
        '2026-09-04)', () async {
      final messages = StreamController<Message>.broadcast();
      final connectionState =
          StreamController<RelayConnectionState>.broadcast();

      final result = await reconcileTree(
        messages: messages.stream,
        connectionState: connectionState.stream,
        send: (message, {corr}) => throw const RelayNotConnectedException(),
      );
      expect(result, isA<Err<TreeSnapshot>>());
      expect((result as Err<TreeSnapshot>).message, notConnectedMessage);

      await messages.close();
      await connectionState.close();
    });

    test(
      'sendHostAction on a down link is a refusal, not an unknown outcome',
      () async {
        final messages = StreamController<Message>.broadcast();
        final connectionState =
            StreamController<RelayConnectionState>.broadcast();

        final outcome = await createWorkspace(
          messages: messages.stream,
          connectionState: connectionState.stream,
          send: (message, {corr}) => throw const RelayNotConnectedException(),
        );
        expect(outcome, isA<HostActionRefused>());
        expect((outcome as HostActionRefused).message, notConnectedMessage);

        await messages.close();
        await connectionState.close();
      },
    );
  });
}
