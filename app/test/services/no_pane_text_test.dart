/// Proves `notifications.dart`'s notification-content construction (`WP-19-a`) carries only the
/// `agent_status` fields R-31-12-01 and R-30-510 name — agent kind, status, tab title and pane
/// title in what a person reads, `host_id`/`pane_id`/`workspace_id`/`tab_id` in the (never
/// displayed) routing payload — and never pane text, never a workspace name, and never any other
/// field. Exercises [buildAgentStatusNotificationContent] and
/// [buildHeldSummaryNotificationContent] directly: both are pure, so this test needs no platform
/// plugin and no mock.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/models/messages/agent_status.dart';
import 'package:herdr_mobile/models/messages/agent_status_kind.dart';
import 'package:herdr_mobile/services/notifications.dart';

AgentStatus _status({
  String paneTitle = 'main.py',
  String tabTitle = 'impl',
  String agentKind = 'claude',
  AgentStatusKind status = AgentStatusKind.done,
  String hostId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  String paneId = 'w3:p2',
  String workspaceId = 'w3',
  String tabId = 'w3:t2',
}) => AgentStatus(
  hostId: hostId,
  paneId: paneId,
  workspaceId: workspaceId,
  tabId: tabId,
  tabTitle: tabTitle,
  paneTitle: paneTitle,
  agentKind: agentKind,
  status: status,
  at: '2026-08-24T14:32:05Z',
);

void main() {
  group('buildAgentStatusNotificationContent (R-31-12-01, R-30-510)', () {
    test('the title carries only the agent kind and the status word', () {
      final content = buildAgentStatusNotificationContent(
        _status(agentKind: 'claude', status: AgentStatusKind.done),
      );
      expect(content.title, 'claude is done');
    });

    test('a blocked agent reads "blocked" in the title', () {
      final content = buildAgentStatusNotificationContent(
        _status(agentKind: 'codex', status: AgentStatusKind.blocked),
      );
      expect(content.title, 'codex is blocked');
    });

    test('the body carries only the pane title and the tab title', () {
      final content = buildAgentStatusNotificationContent(
        _status(paneTitle: 'main.py', tabTitle: 'impl'),
      );
      expect(content.body, 'main.py in impl');
    });

    test('the readable title and body never carry a routing id: no host_id, workspace_id, tab_id '
        'or pane_id substring leaks into what a person reads (R-30-505)', () {
      final status = _status(
        hostId: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
        paneId: 'w3:p2',
        workspaceId: 'w3',
        tabId: 'w3:t2',
      );
      final content = buildAgentStatusNotificationContent(status);
      final readable = '${content.title}\n${content.body}';

      expect(readable, isNot(contains(status.hostId)));
      expect(readable, isNot(contains(status.workspaceId)));
      expect(readable, isNot(contains(status.tabId)));
      expect(readable, isNot(contains(status.paneId)));
    });

    test('the payload carries exactly the four routing/deep-navigation ids, and nothing else '
        '(R-11-058: "the Host MUST NOT send pane text")', () {
      final status = _status();
      final content = buildAgentStatusNotificationContent(status);
      final payload = jsonDecode(content.payload) as Map<String, Object?>;

      expect(payload.keys.toSet(), {
        'host_id',
        'pane_id',
        'workspace_id',
        'tab_id',
      });
      expect(payload['host_id'], status.hostId);
      expect(payload['pane_id'], status.paneId);
      expect(payload['workspace_id'], status.workspaceId);
      expect(payload['tab_id'], status.tabId);
    });

    test('a pane title or tab title that looks like terminal output still passes through '
        'unchanged: `AgentStatus` has no separate pane-text field to leak, by construction '
        '(R-11-058 is enforced on the wire, by the Host)', () {
      final content = buildAgentStatusNotificationContent(
        _status(paneTitle: r'$ rm -rf / # do not run this', tabTitle: 'shell'),
      );
      expect(content.body, r'$ rm -rf / # do not run this in shell');
    });
  });

  group(
    'buildHeldSummaryNotificationContent (R-31-12-03 collapsed summary)',
    () {
      test(
        'the summary body lists only pane titles, never a workspace name',
        () {
          final held = [
            _status(paneId: 'w1:p1', paneTitle: 'main.py', workspaceId: 'w1'),
            _status(paneId: 'w2:p9', paneTitle: 'server.rs', workspaceId: 'w2'),
          ];
          final content = buildHeldSummaryNotificationContent(held);

          expect(content.title, '2 agents need you');
          expect(content.body, 'main.py, server.rs');
          expect(content.body, isNot(contains('w1')));
          expect(content.body, isNot(contains('w2')));
        },
      );

      test('the summary payload routes to the most recently held pane', () {
        final held = [
          _status(paneId: 'w1:p1', hostId: 'host-a'),
          _status(paneId: 'w2:p9', hostId: 'host-b'),
        ];
        final content = buildHeldSummaryNotificationContent(held);
        final payload = jsonDecode(content.payload) as Map<String, Object?>;

        expect(payload['pane_id'], 'w2:p9');
        expect(payload['host_id'], 'host-b');
      });
    },
  );
}
