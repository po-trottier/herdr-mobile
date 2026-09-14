/// Proves R-30-730, R-30-731, R-30-732 (`docs/90-implementation-plan.md` Phase 22): under
/// `MediaQuery.disableAnimationsOf`, every `motion.duration.*`/`motion.curve.*` use is
/// substituted, the `working` icon's rotation stops, and no information is lost.
///
/// `app/lib/widgets/theme/app_motion.dart`'s own doc comment states the substitution is "the
/// caller's responsibility, not a member of this token set" (R-32-606), so the general claim
/// is a static scan for every widget file that reads an `AppMotion.duration`/`AppMotion.curve`
/// token without also checking `MediaQuery.disableAnimationsOf` — the same source-scan idiom
/// `test/widgets/theme/no_literals_test.dart` already uses for a sibling per-widget policy
/// (a `RegExp` scan needs no new dependency, per `docs/41-code-standards.md` R-41-042). The
/// concrete, named case — the `working` icon (R-30-403's "one permitted continuous animation")
/// — is proved by pumping the real widget.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart'
    show FadeTransition, MediaQuery, MediaQueryData;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/models/message.dart';
import 'package:herdr_mobile/models/messages/agent_summary.dart';
import 'package:herdr_mobile/models/messages/pane_scroll_state.dart';
import 'package:herdr_mobile/models/messages/pane_summary.dart';
import 'package:herdr_mobile/models/messages/tab_summary.dart';
import 'package:herdr_mobile/models/messages/tree_snapshot.dart';
import 'package:herdr_mobile/models/messages/workspace_summary.dart';
import 'package:herdr_mobile/screens/agent_list_screen.dart';
import 'package:herdr_mobile/services/agent_status.dart' show AttentionItem;
import 'package:herdr_mobile/services/relay.dart';
import 'package:herdr_mobile/widgets/status_bar.dart' show StatusBar;
import 'package:material_ui/material_ui.dart' show MaterialApp;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

// ---------------------------------------------------------------------------
// General contract: every `AppMotion.duration`/`AppMotion.curve` reference in a widget file
// must sit beside a `disableAnimationsOf` check in the same file (R-30-730).
// ---------------------------------------------------------------------------

const List<String> _widgetRoots = <String>['lib/screens', 'lib/widgets'];
const String _tokenDirectory = 'lib/widgets/theme';

final RegExp _motionTokenUse = RegExp(r'AppMotion\.(duration|curve)[A-Za-z]+');
final RegExp _reduceMotionGate = RegExp(r'disableAnimationsOf');

class _Violation {
  const _Violation(this.path);
  final String path;

  @override
  String toString() =>
      '$path: uses an AppMotion.duration*/curve* token but never checks '
      'MediaQuery.disableAnimationsOf, so R-30-730\'s substitution never happens';
}

List<_Violation> _scanForUngatedMotion(List<String> roots) {
  final violations = <_Violation>[];
  for (final rootPath in roots) {
    final root = Directory(rootPath);
    if (!root.existsSync()) continue;
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final normalizedPath = entity.path.replaceAll(r'\', '/');
      if (normalizedPath.contains('$_tokenDirectory/')) continue;
      final contents = entity.readAsStringSync();
      if (_motionTokenUse.hasMatch(contents) &&
          !_reduceMotionGate.hasMatch(contents)) {
        violations.add(_Violation(normalizedPath));
      }
    }
  }
  return violations;
}

// ---------------------------------------------------------------------------
// The concrete case: the `working` state bar (`agent_list_screen.dart`'s row
// → `widgets/status_bar.dart`, R-03-100). R-30-403's one permitted
// continuous `working` animation is the `StatusBar` `motion.pulse` (R-32-601,
// R-32-608): opacity 0.25 to 1.0 and back, running only while animations are
// enabled; static at full opacity under reduce motion, with the state word
// kept for a screen reader (R-30-731, R-30-732).
// ---------------------------------------------------------------------------

Future<void> _pumpWorkingAgent(
  WidgetTester tester, {
  required bool disableAnimations,
}) async {
  final messages = StreamController<Message>.broadcast();
  addTearDown(messages.close);
  final connectionState = StreamController<RelayConnectionState>.broadcast();
  addTearDown(connectionState.close);
  final attention = StreamController<List<AttentionItem>>.broadcast();
  addTearDown(attention.close);

  final screen = AgentListScreen(
    hostId: 'host-1',
    hostName: 'patrick-desk',
    messages: messages.stream,
    connectionState: connectionState.stream,
    initialConnectionState: const RelayConnected(),
    send: (Message message, {String? corr}) {},
    unseenAttention: attention.stream,
    currentAttention: const <AttentionItem>[],
    onMarkSeen: (_) {},
    onNotePaneOpened: (_) {},
    onOpenPane: (_) {},
  );

  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: screen,
      ),
    ),
  );
  messages.add(
    const Message.treeSnapshot(
      TreeSnapshot(
        workspaces: [
          WorkspaceSummary(
            workspaceId: 'w1',
            name: 'herdr-relay',
            focused: true,
          ),
        ],
        tabs: [
          TabSummary(
            tabId: 'w1:t2',
            workspaceId: 'w1',
            title: 'impl',
            focused: true,
          ),
        ],
        panes: [
          PaneSummary(
            paneId: 'w1:p2',
            workspaceId: 'w1',
            tabId: 'w1:t2',
            terminalId: 'term_w1p2',
            label: 'my-agent',
            title: 'claude command',
            cwd: '/home/user',
            focused: false,
            agent: 'claude',
            agentStatus: 'working',
            revision: 1,
            scroll: PaneScrollState(
              offsetFromBottom: 0,
              maxOffsetFromBottom: 0,
              viewportRows: 50,
            ),
          ),
        ],
        agents: [
          AgentSummary(agentKind: 'claude', paneId: 'w1:p2', status: 'working'),
        ],
      ),
    ),
  );
  await tester.pump();
}

void main() {
  test(
    'no widget under screens/ or widgets/ (outside widgets/theme/) reads an AppMotion '
    'duration/curve token without checking MediaQuery.disableAnimationsOf',
    () {
      final violations = _scanForUngatedMotion(_widgetRoots);
      expect(
        violations,
        isEmpty,
        reason: violations.map((v) => v.toString()).join('\n'),
      );
    },
  );

  group('The working icon (R-30-403, R-32-601)', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
    });

    testWidgets('pulses continuously with animations enabled', (
      WidgetTester tester,
    ) async {
      await _pumpWorkingAgent(tester, disableAnimations: false);
      final Finder workingDotFinder = find.descendant(
        of: find.byType(StatusBar),
        matching: find.byType(FadeTransition),
      );
      expect(workingDotFinder, findsOneWidget);
      final FadeTransition fade = tester.widget<FadeTransition>(
        workingDotFinder,
      );
      final double before = fade.opacity.value;
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        fade.opacity.value,
        isNot(equals(before)),
        reason:
            'the working state bar must keep pulsing while animations are '
            'enabled (R-32-601, R-32-608)',
      );
    });

    testWidgets('stops pulsing under reduce motion, and stays visible in its state (R-30-731, '
        'R-30-732: no information lost)', (WidgetTester tester) async {
      await _pumpWorkingAgent(tester, disableAnimations: true);
      // Reduce motion: no pulse FadeTransition is built inside a StatusBar —
      // the bar sits at full opacity, still in its hue (R-32-608).
      expect(
        find.descendant(
          of: find.byType(StatusBar),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );

      // No information lost: the bar is still on screen, and the row still
      // names the agent's state for a screen reader.
      expect(
        find.bySemanticsLabel(RegExp('Working')),
        findsOneWidget,
        reason: 'a static dot must still carry the same state word (R-30-732)',
      );
    });
  });
}
