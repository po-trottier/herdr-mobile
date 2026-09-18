/// R-11-048, R-11-050, R-21-002, R-21-004: verify the watch lifecycle and full-frame feed.
/// R-21-021, R-21-022: verify feeds on arrival, pending-frame replacement and the slow-render fallback.
/// R-21-041, R-11-053, R-21-009: verify freezes, scrollback requests and Host-reported geometry.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart' show Err, Ok;
import 'package:herdr_mobile/models/codes.dart';
import 'package:herdr_mobile/models/message.dart';
import 'package:herdr_mobile/models/messages/error_message.dart';
import 'package:herdr_mobile/models/messages/pane_frame.dart';
import 'package:herdr_mobile/models/messages/scroll_offsets.dart';
import 'package:herdr_mobile/models/messages/scroll_request.dart';
import 'package:herdr_mobile/models/messages/scroll_response.dart';
import 'package:herdr_mobile/models/messages/send_input.dart';
import 'package:herdr_mobile/models/messages/watch_ack.dart';
import 'package:herdr_mobile/models/messages/watch_pane.dart';
import 'package:herdr_mobile/services/terminal.dart';
import 'package:xterm2/xterm.dart';

/// A recorded outbound call, either a raw [send] or a [watchPane]/[unwatchPane].
sealed class _Sent {
  const _Sent();
}

final class _SentMessage extends _Sent {
  const _SentMessage(this.message);
  final Message message;
}

final class _SentWatch extends _Sent {
  const _SentWatch(this.paneId);
  final String paneId;
}

final class _SentUnwatch extends _Sent {
  const _SentUnwatch(this.paneId);
  final String paneId;
}

/// Harness bundling a fake [Message] stream and a recording sender, matching
/// [TerminalService]'s four injected function seams.
final class _Harness {
  _Harness({DateTime Function()? now})
    : _controller = StreamController<Message>.broadcast(sync: true),
      _now = now ?? DateTime.now;

  final StreamController<Message> _controller;
  final DateTime Function() _now;
  final List<_Sent> sent = [];

  void push(Message message) => _controller.add(message);

  TerminalService build({Duration replyTimeout = terminalReplyTimeout}) =>
      TerminalService(
        messages: _controller.stream,
        send: (message, {corr}) => sent.add(_SentMessage(message)),
        watchPane: (paneId, {corr}) => sent.add(_SentWatch(paneId)),
        unwatchPane: (paneId, {corr}) => sent.add(_SentUnwatch(paneId)),
        terminal: Terminal(maxLines: 0),
        replyTimeout: replyTimeout,
        now: _now,
      );

  Future<void> dispose() => _controller.close();
}

const _scroll = ScrollOffsets(offsetFromBottom: 0, maxOffsetFromBottom: 0);

WatchAck _ack({
  String paneId = 'w1:p1',
  int revision = 100,
  int viewportRows = 10,
  int width = 40,
  ScrollOffsets scroll = _scroll,
}) => WatchAck(
  paneId: paneId,
  revision: revision,
  viewportRows: viewportRows,
  width: width,
  scroll: scroll,
);

PaneFrame _frame({
  String paneId = 'w1:p1',
  required int revision,
  int viewportRows = 10,
  int width = 40,
  String text = 'hello',
}) => PaneFrame(
  paneId: paneId,
  revision: revision,
  viewportRows: viewportRows,
  width: width,
  text: text,
);

BufferLine _firstRow(Terminal terminal) => terminal.buffer.lines[0];

String _rowText(Terminal terminal, int cols) {
  final row = _firstRow(terminal);
  final buffer = StringBuffer();
  for (var i = 0; i < cols; i++) {
    final codePoint = row.getCodePoint(i);
    if (codePoint == 0) break;
    buffer.writeCharCode(codePoint);
  }
  return buffer.toString();
}

void main() {
  group('attach()/detach() (R-11-048, R-11-050, R-11-049)', () {
    test('attach() sends watch_pane, applies watch_ack and resizes xterm (R-20-013, '
        'R-41-171)', () async {
      final harness = _Harness();
      final service = harness.build();
      addTearDown(() => service.dispose());
      addTearDown(harness.dispose);

      final future = service.attach('w1:p1');
      await pumpEventQueue();
      expect(harness.sent, [isA<_SentWatch>()]);
      expect((harness.sent.single as _SentWatch).paneId, 'w1:p1');

      harness.push(
        Message.watchAck(_ack(viewportRows: 12, width: 33, revision: 5)),
      );
      final result = await future;

      expect(result, isA<Ok<void>>());
      expect(service.state.paneId, 'w1:p1');
      expect(service.state.revision, 5);
      expect(service.state.columns, 33);
      expect(service.state.rows, 12);
      expect(service.xterm.viewWidth, 33);
      expect(service.xterm.viewHeight, 12);
    });

    test('attach() resolves Err on an error reply', () async {
      final harness = _Harness();
      final service = harness.build();
      addTearDown(() => service.dispose());
      addTearDown(harness.dispose);

      final future = service.attach('w1:p1');
      await pumpEventQueue();
      harness.push(
        const Message.error(
          ErrorMessage(
            code: ErrorCode.paneNotFound,
            message: 'no such pane',
            fatal: false,
          ),
        ),
      );
      final result = await future;
      expect(result, isA<Err<void>>());
      expect(
        (result as Err<void>).cause,
        isA<TerminalAttachException>().having(
          (e) => e.errorCode,
          'errorCode',
          ErrorCode.paneNotFound,
        ),
      );
    });

    test('attach() times out when no reply arrives (R-10-004)', () async {
      final harness = _Harness();
      final service = harness.build(
        replyTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(() => service.dispose());
      addTearDown(harness.dispose);

      final result = await service.attach('w1:p1');
      expect(result, isA<Err<void>>());
      expect((result as Err<void>).cause, isA<TerminalAttachException>());
    });

    test('detach() sends unwatch_pane and clears state', () async {
      final harness = _Harness();
      final service = harness.build();
      addTearDown(() => service.dispose());
      addTearDown(harness.dispose);

      final future = service.attach('w1:p1');
      await pumpEventQueue();
      harness.push(Message.watchAck(_ack()));
      await future;

      service.detach();
      expect(harness.sent.last, isA<_SentUnwatch>());
      expect((harness.sent.last as _SentUnwatch).paneId, 'w1:p1');
      expect(service.state.paneId, isNull);
    });

    test(
      'never sends a host_action or any pane-resize request (R-21-036)',
      () async {
        final harness = _Harness();
        final service = harness.build();
        addTearDown(() => service.dispose());
        addTearDown(harness.dispose);

        final future = service.attach('w1:p1');
        await pumpEventQueue();
        harness.push(Message.watchAck(_ack()));
        await future;
        harness.push(Message.paneFrame(_frame(revision: 101)));
        await pumpEventQueue(times: 10);

        for (final call in harness.sent) {
          if (call is _SentMessage) {
            expect(call.message, isNot(isA<MessageHostAction>()));
          }
        }
      },
    );
  });

  group('watch_pane/scroll_request carry no read-selection fields (R-31-08-02, R-21-002a)', () {
    test('WatchPane JSON has only pane_id', () {
      final json = const WatchPane(paneId: 'w1:p1').toJson();
      expect(json.keys, ['pane_id']);
    });

    test('ScrollRequest JSON has only pane_id and lines, never format/strip_ansi/source', () {
      final json = const ScrollRequest(paneId: 'w1:p1', lines: 100).toJson();
      expect(json.keys.toSet(), {'pane_id', 'lines'});
    });
  });

  group('pane_frame pipeline', () {
    Future<TerminalService> attached(_Harness harness) async {
      final service = harness.build();
      final future = service.attach('w1:p1');
      harness.push(Message.watchAck(_ack(revision: 1)));
      await future;
      return service;
    }

    testWidgets('a single frame paints with no timer advance (R-21-021)', (
      tester,
    ) async {
      final harness = _Harness(now: tester.binding.clock.now);
      final service = await attached(harness);
      addTearDown(() => service.dispose());
      addTearDown(harness.dispose);
      final receivedAt = tester.binding.clock.now();

      harness.push(Message.paneFrame(_frame(revision: 2, text: 'echo')));

      expect(_rowText(service.xterm, 4), 'echo');
      expect(service.state.revision, 2);
      expect(service.state.lastRenderMs, [0]);
      expect(tester.binding.clock.now(), receivedAt);
    });

    test(
      'a frame for a different pane is discarded (R-21-004a, R-01-007)',
      () async {
        final harness = _Harness();
        final service = await attached(harness);
        addTearDown(() => service.dispose());
        addTearDown(harness.dispose);

        harness.push(
          Message.paneFrame(
            _frame(paneId: 'w9:p9', revision: 999, text: 'nope'),
          ),
        );

        expect(service.state.revision, 1);
      },
    );

    test("the pane's first frame is painted even though its revision equals watch_ack's — "
        'the real production race found by Phase 23\'s e2e test '
        '(R-21-004, R-02-012, R-11-049, R-11-052)', () async {
      final harness = _Harness();
      final service = harness.build();
      addTearDown(() => service.dispose());
      addTearDown(harness.dispose);

      // Production `Bridge::watch_pane` (`crates/herdr-relay/src/watch/requests.rs`)
      // always builds `watch_ack` and the pane's first `pane_frame` from the very same
      // snapshot read, so the first frame's revision always equals `watch_ack`'s, never
      // exceeds it. Gating "paint" on `_state.revision` (already seeded from that same
      // `watch_ack`) used to discard this first frame unconditionally, leaving the grid
      // permanently blank until an unrelated later revision happened to arrive.
      final future = service.attach('w1:p1');
      await pumpEventQueue();
      harness.push(Message.watchAck(_ack(revision: 42)));
      await future;

      harness.push(
        Message.paneFrame(_frame(revision: 42, text: 'FIRST-CONTENT')),
      );

      expect(
        _rowText(service.xterm, 'FIRST-CONTENT'.length),
        'FIRST-CONTENT',
        reason:
            'the first frame must be painted, not silently dropped because its '
            "revision matches watch_ack's",
      );
      expect(service.state.revision, 42);
    });

    test('a second frame at the same revision with new text is painted — Herdr freezes '
        'revision on an agent pane, so the Host polls and sends a frame only when the text '
        'changed (R-02-026, R-10-070; decided 2026-09-03)', () async {
      final harness = _Harness();
      final service = harness.build();
      addTearDown(() => service.dispose());
      addTearDown(harness.dispose);

      final future = service.attach('w1:p1');
      await pumpEventQueue();
      harness.push(Message.watchAck(_ack(revision: 30)));
      await future;

      harness.push(Message.paneFrame(_frame(revision: 30, text: 'FIRST')));
      expect(_rowText(service.xterm, 5), 'FIRST');

      harness.push(Message.paneFrame(_frame(revision: 30, text: 'LATER')));

      expect(_rowText(service.xterm, 5), 'LATER');
      expect(service.state.revision, 30);
    });

    test(
      'a frame older than the last painted revision is ignored (R-31-08-03)',
      () async {
        final harness = _Harness();
        final service = harness.build();
        addTearDown(() => service.dispose());
        addTearDown(harness.dispose);

        final future = service.attach('w1:p1');
        await pumpEventQueue();
        harness.push(Message.watchAck(_ack(revision: 2)));
        await future;

        harness.push(Message.paneFrame(_frame(revision: 2, text: 'NEWER')));
        expect(_rowText(service.xterm, 5), 'NEWER');

        harness.push(Message.paneFrame(_frame(revision: 1, text: 'STALE')));

        expect(_rowText(service.xterm, 5), 'NEWER');
        expect(service.state.revision, 2);
      },
    );

    test('a newer attach frame replaces the first snapshot on arrival (R-21-004, R-21-021)', () async {
      final harness = _Harness();
      final service = harness.build();
      addTearDown(() => service.dispose());
      addTearDown(harness.dispose);

      final future = service.attach('w1:p1');
      await pumpEventQueue();
      harness.push(Message.watchAck(_ack(revision: 100)));
      await future;

      harness.push(
        Message.paneFrame(_frame(revision: 100, text: 'FIRST-SNAPSHOT')),
      );
      harness.push(
        Message.paneFrame(_frame(revision: 101, text: 'BUMPED-SNAPSHOT')),
      );

      // R-21-004: the newer revision replaces the initial snapshot without a timer.
      expect(service.state.revision, 101);
      expect(
        _rowText(service.xterm, 'BUMPED-SNAPSHOT'.length),
        'BUMPED-SNAPSHOT',
      );
    });

    test('applies clear-and-home reset then the full grid, never appended (R-21-001, '
        'R-21-002, R-21-005, R-10-018, R-31-08-11)', () async {
      final harness = _Harness();
      final service = await attached(harness);
      addTearDown(() => service.dispose());
      addTearDown(harness.dispose);

      harness.push(Message.paneFrame(_frame(revision: 2, text: 'AAAA')));
      expect(_rowText(service.xterm, 4), 'AAAA');
      expect(service.state.revision, 2);

      harness.push(Message.paneFrame(_frame(revision: 3, text: 'BB')));
      // A shorter second frame proves the grid was cleared, not appended to: no leftover
      // "AA" tail from the first frame.
      expect(_rowText(service.xterm, 4), 'BB');
      expect(service.state.revision, 3);
    });

    test('measures longestLineDrawn (ANSI-stripped) and unknownSgrCount per applied frame '
        '(R-31-13-08, R-31-13-09, R-31-13-10, R-30-158)', () async {
      final harness = _Harness();
      final service = await attached(harness);
      addTearDown(() => service.dispose());
      addTearDown(harness.dispose);

      expect(service.state.longestLineDrawn, 0);
      expect(service.state.unknownSgrCount, 0);

      // SGR 1 and 0 are in the measured vocabulary; SGR 9 (strikethrough) is not. The
      // second line is also the longer one once the SGR codes are stripped.
      harness.push(
        Message.paneFrame(
          _frame(
            revision: 2,
            text: '\x1b[1mshort\x1b[0m\n\x1b[9mlonger line here\x1b[0m',
          ),
        ),
      );

      expect(service.state.longestLineDrawn, 'longer line here'.length);
      expect(service.state.unknownSgrCount, 1);
    });

    test('longestLineDrawn and unknownSgrCount reset to 0 on a fresh attach, never '
        'aggregating across panes (R-31-13-09)', () async {
      final harness = _Harness();
      final service = await attached(harness);
      addTearDown(() => service.dispose());
      addTearDown(harness.dispose);

      harness.push(
        Message.paneFrame(
          _frame(revision: 2, text: '\x1b[9munknown sgr line\x1b[0m'),
        ),
      );
      expect(service.state.unknownSgrCount, greaterThan(0));
      expect(service.state.longestLineDrawn, greaterThan(0));

      final future = service.attach('w1:p2');
      await pumpEventQueue();
      harness.push(Message.watchAck(_ack(paneId: 'w1:p2', revision: 50)));
      await future;

      expect(service.state.unknownSgrCount, 0);
      expect(service.state.longestLineDrawn, 0);
    });

    test('a burst during a feed paints only the newest pending revision (R-21-004, R-21-021)', () async {
      final harness = _Harness();
      final service = await attached(harness);
      addTearDown(() => service.dispose());
      addTearDown(harness.dispose);
      final painted = <String>[];
      var sendBurst = true;
      service.xterm.addListener(() {
        painted.add(_rowText(service.xterm, 10));
        if (!sendBurst) return;
        sendBurst = false;
        harness.push(
          Message.paneFrame(_frame(revision: 3, text: 'superseded')),
        );
        harness.push(Message.paneFrame(_frame(revision: 4, text: 'newest')));
        harness.push(Message.paneFrame(_frame(revision: 2, text: 'stale')));
      });

      // R-21-041: start the feed on unfreeze so the message stream can deliver during it.
      service.setSelectionLive(live: true);
      harness.push(Message.paneFrame(_frame(revision: 2, text: 'first')));
      service.setSelectionLive(live: false);

      expect(painted, ['first']);
      expect(service.state.revision, 2);
      await pumpEventQueue();
      expect(painted, ['first', 'newest']);
      expect(service.state.revision, 4);
    });

    test('resizes xterm on a layout change reported by pane_frame (R-21-009, R-10-025, '
        'R-20-013, R-41-171)', () async {
      final harness = _Harness();
      final service = await attached(harness);
      addTearDown(() => service.dispose());
      addTearDown(harness.dispose);

      harness.push(
        Message.paneFrame(
          _frame(revision: 2, viewportRows: 24, width: 80, text: 'x'),
        ),
      );

      expect(service.xterm.viewWidth, 80);
      expect(service.xterm.viewHeight, 24);
      expect(service.state.columns, 80);
      expect(service.state.rows, 24);
    });
  });

  group('R-21-041 selection/scroll freeze', () {
    test('a frame arriving while a selection is live is held, not fed, and status is '
        'paused (R-31-08-05)', () async {
      final harness = _Harness();
      final service = harness.build();
      addTearDown(() => service.dispose());
      addTearDown(harness.dispose);
      final future = service.attach('w1:p1');
      await pumpEventQueue();
      harness.push(Message.watchAck(_ack(revision: 1)));
      await future;

      service.setSelectionLive(live: true);
      expect(service.state.status, TerminalPaneStatus.paused);

      harness.push(Message.paneFrame(_frame(revision: 2, text: 'held')));

      expect(
        service.state.revision,
        1,
        reason: 'the held frame must not be applied yet',
      );
      expect(service.state.status, TerminalPaneStatus.paused);
    });

    test('the held frame is fed through the normal cycle the instant the freeze clears, '
        'replacing (not queuing) any earlier held frame', () async {
      final harness = _Harness();
      final service = harness.build();
      addTearDown(() => service.dispose());
      addTearDown(harness.dispose);
      final future = service.attach('w1:p1');
      await pumpEventQueue();
      harness.push(Message.watchAck(_ack(revision: 1)));
      await future;

      service.setSelectionLive(live: true);
      harness.push(Message.paneFrame(_frame(revision: 2, text: 'stale-held')));
      harness.push(Message.paneFrame(_frame(revision: 3, text: 'latest-held')));

      expect(service.state.revision, 1);

      service.setSelectionLive(live: false);
      await pumpEventQueue();

      expect(service.state.revision, 3);
      expect(service.state.status, TerminalPaneStatus.live);
      expect(_rowText(service.xterm, 11), 'latest-held');
    });

    test('a scroll offset above zero also freezes; both conditions must clear to resume '
        '(R-31-08-18)', () async {
      final harness = _Harness();
      final service = harness.build();
      addTearDown(() => service.dispose());
      addTearDown(harness.dispose);
      final future = service.attach('w1:p1');
      await pumpEventQueue();
      harness.push(Message.watchAck(_ack(revision: 1)));
      await future;

      service.setSelectionLive(live: true);
      service.setScrollOffset(3);
      harness.push(Message.paneFrame(_frame(revision: 2, text: 'held')));

      service.setSelectionLive(live: false);
      await pumpEventQueue();
      expect(
        service.state.revision,
        1,
        reason: 'scroll offset alone still holds the freeze',
      );
      expect(service.state.status, TerminalPaneStatus.paused);

      service.setScrollOffset(0);
      await pumpEventQueue();
      expect(service.state.revision, 2);
      expect(service.state.status, TerminalPaneStatus.live);
    });
  });

  group('scroll_request/scroll_response (R-11-053)', () {
    for (final cancel in ['bottom', 'detach', 'selection']) {
      test('history reply does not replace the grid after $cancel', () async {
        final harness = _Harness();
        final service = harness.build();
        addTearDown(service.dispose);
        addTearDown(harness.dispose);
        final attached = service.attach('w1:p1');
        harness.push(Message.watchAck(_ack()));
        await attached;
        harness.push(
          Message.paneFrame(_frame(revision: 101, text: 'visible live')),
        );
        service.setScrollOffset(3);
        final fetched = service.requestScrollback(lines: 1000);
        if (cancel == 'bottom') service.setScrollOffset(0);
        if (cancel == 'detach') service.detach();
        if (cancel == 'selection') service.setSelectionLive(live: true);
        harness.push(
          const Message.scrollResponse(
            ScrollResponse(
              paneId: 'w1:p1',
              text: 'old response',
              lines: 1,
              truncated: false,
            ),
          ),
        );
        await fetched;
        expect(service.xterm.buffer.getText(), isNot(contains('old response')));
      });
    }

    test('concurrent history gestures share one request and resume without a newer frame', () async {
      final harness = _Harness();
      final service = harness.build();
      addTearDown(service.dispose);
      addTearDown(harness.dispose);
      final attached = service.attach('w1:p1');
      harness.push(Message.watchAck(_ack()));
      await attached;
      harness.push(
        Message.paneFrame(_frame(revision: 101, text: 'same live prompt')),
      );
      final first = service.requestScrollback(lines: 1000);
      final second = service.requestScrollback(lines: 1000);
      expect(
        harness.sent.whereType<_SentMessage>().where(
          (s) => s.message is MessageScrollRequest,
        ),
        hasLength(1),
      );
      harness.push(
        Message.scrollResponse(
          ScrollResponse(
            paneId: 'w1:p1',
            text: List.generate(1000, (i) => 'old row $i').join('\r\n'),
            lines: 1000,
            truncated: false,
          ),
        ),
      );
      await Future.wait([first, second]);
      service.setScrollOffset(0);
      expect(service.xterm.buffer.getText(), contains('same live prompt'));
      expect(service.xterm.buffer.lines.length, 10);
      for (var i = 0; i < 3; i++) {
        harness.push(
          Message.paneFrame(
            _frame(
              revision: 102 + i,
              text:
                  "${List.generate(10, (n) => 'live row $n').join('\r\n')}\r\n",
            ),
          ),
        );
        expect(service.xterm.buffer.lines.length, 10);
        expect(service.xterm.buffer.scrollBack, 0);
      }
    });

    test(
      'scrollback paints every fetched row and restores the live frame',
      () async {
        final harness = _Harness();
        final service = harness.build();
        addTearDown(service.dispose);
        addTearDown(harness.dispose);
        final attached = service.attach('w1:p1');
        harness.push(Message.watchAck(_ack(viewportRows: 10)));
        await attached;
        harness.push(
          Message.paneFrame(_frame(revision: 101, text: 'live prompt')),
        );
        service.setScrollOffset(5);
        final fetched = service.requestScrollback(lines: 1000);
        harness.push(
          Message.scrollResponse(
            ScrollResponse(
              paneId: 'w1:p1',
              text: List.generate(1000, (i) => 'history row $i').join('\r\n'),
              lines: 1000,
              truncated: true,
            ),
          ),
        );
        await fetched;
        // A ten-row live emulator must not discard 990 fetched rows.
        expect(service.xterm.buffer.getText(), contains('history row 0'));
        expect(service.xterm.buffer.getText(), contains('history row 500'));
        expect(service.xterm.buffer.getText(), contains('history row 999'));
        expect(service.state.rows, 10, reason: 'Host geometry stays unchanged');
        harness.push(
          Message.paneFrame(_frame(revision: 102, text: 'new live prompt')),
        );
        expect(service.xterm.buffer.getText(), contains('history row 0'));
        service.setScrollOffset(0);
        expect(service.xterm.buffer.getText(), contains('new live prompt'));
        expect(service.xterm.buffer.getText(), isNot(contains('history row')));
        expect(service.xterm.viewHeight, 10);
      },
    );

    test('requestScrollback sends scroll_request capped at 1000 lines and resolves on '
        'scroll_response (R-10-019)', () async {
      final harness = _Harness();
      final service = harness.build();
      addTearDown(() => service.dispose());
      addTearDown(harness.dispose);
      final future = service.attach('w1:p1');
      await pumpEventQueue();
      harness.push(Message.watchAck(_ack()));
      await future;

      final scrollFuture = service.requestScrollback(lines: 5000);
      await pumpEventQueue();
      final sentMessage =
          (harness.sent.last as _SentMessage).message as MessageScrollRequest;
      expect(sentMessage.payload.lines, 1000);

      harness.push(
        const Message.scrollResponse(
          ScrollResponse(
            paneId: 'w1:p1',
            text: 'scrollback text',
            lines: 1000,
            truncated: true,
          ),
        ),
      );
      final result = await scrollFuture;
      expect(result, isA<Ok<ScrollResponse>>());
      expect((result as Ok<ScrollResponse>).value.text, 'scrollback text');
    });

    test('requestScrollback fails fast with no pane attached', () async {
      final harness = _Harness();
      final service = harness.build();
      addTearDown(() => service.dispose());
      addTearDown(harness.dispose);

      final result = await service.requestScrollback(lines: 10);
      expect(result, isA<Err<ScrollResponse>>());
    });
  });

  group('render_ms measurement and the 200 ms / 5-frame fallback (R-21-022)', () {
    testWidgets(
      'five slow frames enable the 240 ms throttle and keep render_ms accurate',
      (tester) async {
        var renderTime = Duration.zero;
        final harness = _Harness(
          now: () => tester.binding.clock.now().add(renderTime),
        );
        final service = harness.build();
        addTearDown(() => service.dispose());
        addTearDown(harness.dispose);
        final future = service.attach('w1:p1');
        harness.push(Message.watchAck(_ack(revision: 1)));
        await future;
        // R-21-022: advance the measured clock during each emulator write, not before receipt.
        service.xterm.addListener(() {
          renderTime += const Duration(milliseconds: 250);
        });

        for (var i = 0; i < 5; i++) {
          harness.push(
            Message.paneFrame(_frame(revision: 2 + i, text: 'frame$i')),
          );
          expect(service.state.revision, 2 + i);
          expect(service.state.renderSlowTripCount, i == 4 ? 1 : 0);
        }
        expect(service.state.debounceWindow, terminalFallbackCoalesceWindow);
        expect(service.state.lastRenderMs, [250, 250, 250, 250, 250]);

        harness.push(
          Message.paneFrame(_frame(revision: 7, text: 'superseded')),
        );
        await tester.pump(const Duration(milliseconds: 120));
        harness.push(Message.paneFrame(_frame(revision: 8, text: 'newest')));
        await tester.pump(const Duration(milliseconds: 119));
        expect(service.state.revision, 6);
        await tester.pump(const Duration(milliseconds: 1));
        expect(service.state.revision, 8);
        expect(_rowText(service.xterm, 6), 'newest');
        expect(service.state.lastRenderMs, [250, 250, 250, 250, 370]);
        expect(service.state.renderSlowTripCount, 1);

        // R-21-041: a freeze holds even when the fallback timer expires. Unfreeze feeds at once.
        harness.push(Message.paneFrame(_frame(revision: 9, text: 'held')));
        service.setSelectionLive(live: true);
        await tester.pump(terminalFallbackCoalesceWindow);
        expect(service.state.revision, 8);
        service.setSelectionLive(live: false);
        expect(service.state.revision, 9);
        expect(service.state.status, TerminalPaneStatus.live);
        expect(_rowText(service.xterm, 4), 'held');
      },
    );

    test(
      'a frame at the threshold resets the consecutive-slow count (R-21-022)',
      () async {
        var clock = DateTime(2026);
        var renderTime = const Duration(milliseconds: 250);
        final harness = _Harness(now: () => clock);
        final service = harness.build();
        addTearDown(() => service.dispose());
        addTearDown(harness.dispose);
        final future = service.attach('w1:p1');
        harness.push(Message.watchAck(_ack(revision: 1)));
        await future;
        service.xterm.addListener(() => clock = clock.add(renderTime));

        for (var revision = 2; revision <= 5; revision++) {
          harness.push(Message.paneFrame(_frame(revision: revision)));
        }
        renderTime = const Duration(milliseconds: 200);
        harness.push(Message.paneFrame(_frame(revision: 6)));
        expect(service.state.renderSlowTripCount, 0);

        renderTime = const Duration(milliseconds: 250);
        for (var revision = 7; revision <= 10; revision++) {
          harness.push(Message.paneFrame(_frame(revision: revision)));
        }
        expect(service.state.renderSlowTripCount, 0);
        harness.push(Message.paneFrame(_frame(revision: 11)));
        expect(service.state.renderSlowTripCount, 1);
      },
    );
  });

  testWidgets('composer input never writes over a Host frame (R-03-130)', (
    tester,
  ) async {
    final harness = _Harness();
    final service = harness.build();
    addTearDown(service.dispose);
    addTearDown(harness.dispose);
    final attached = service.attach('w1:p1');
    harness.push(Message.watchAck(_ack()));
    await attached;
    harness.push(Message.paneFrame(_frame(revision: 101, text: '> ')));
    var paints = 0;
    service.xterm.addListener(() => paints++);

    service.sendComposerLine('w1:p1', 'a');
    service.sendComposerLine('w1:p1', 'ab');
    service.sendComposerLine('w1:p1', 'a');
    service.sendComposerLine('w1:p1', 'ac');
    await tester.pump(terminalReplyTimeout);

    expect(_rowText(service.xterm, 10), '> ');
    expect(paints, 0);
    expect(harness.sent.whereType<_SentMessage>().map((sent) => sent.message), [
      const Message.sendInput(SendInput(paneId: 'w1:p1', line: 'a')),
      const Message.sendInput(SendInput(paneId: 'w1:p1', line: 'ab')),
      const Message.sendInput(SendInput(paneId: 'w1:p1', line: 'a')),
      const Message.sendInput(SendInput(paneId: 'w1:p1', line: 'ac')),
    ]);

    harness.push(Message.paneFrame(_frame(revision: 102, text: '> ac')));
    expect(_rowText(service.xterm, 10), '> ac');
    expect(paints, 1);
  });
}
