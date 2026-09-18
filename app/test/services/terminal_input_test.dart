import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/models/codes.dart';
import 'package:herdr_mobile/models/message.dart';
import 'package:herdr_mobile/models/messages/error_message.dart';
import 'package:herdr_mobile/models/messages/pong.dart';
import 'package:herdr_mobile/models/messages/send_input.dart';
import 'package:herdr_mobile/models/messages/send_input_ack.dart';
import 'package:herdr_mobile/services/terminal.dart';

void main() {
  late StreamController<Message> incoming;
  late TerminalService service;
  late List<({Message message, String? corr})> sent;
  late DateTime now;

  setUp(() {
    incoming = StreamController<Message>.broadcast(sync: true);
    sent = [];
    now = DateTime(2026);
    service = TerminalService(
      messages: incoming.stream,
      send: (message, {corr}) => sent.add((message: message, corr: corr)),
      watchPane: (paneId, {corr}) {},
      unwatchPane: (paneId, {corr}) {},
      now: () => now,
    );
  });
  tearDown(() async {
    await service.dispose();
    await incoming.close();
  });

  void ack(
    String? corr, {
    String paneId = 'p',
    bool accepted = true,
    bool queued = false,
  }) {
    incoming.add(
      Message.sendInputAck(
        SendInputAck(paneId: paneId, accepted: accepted, queued: queued),
        corr: corr,
      ),
    );
  }

  testWidgets('submit waits for its line and Enter ACKs, not other input', (
    tester,
  ) async {
    service.sendComposerLine('p', 'old');
    final result = service.sendComposerSubmit('p', 'latest');
    expect(sent.map((e) => e.corr).toSet().length, 2);
    expect(sent.every((e) => e.corr != null), isTrue);
    expect((sent.last.message as MessageSendInput).payload.line, 'latest');
    final lineCorr = sent.last.corr;
    ack(sent.first.corr);
    ack(lineCorr, paneId: 'other');
    await tester.pump();
    expect(sent.length, 2);
    ack(lineCorr);
    await tester.pump();
    expect(sent.length, 3);
    final enter = sent.last.message as MessageSendInput;
    expect(enter.payload.line, isNull);
    expect(enter.payload.keys, ['Enter']);
    expect(sent.last.corr, isNot(lineCorr));
    var completed = false;
    unawaited(result.then((_) => completed = true));
    ack(lineCorr);
    await tester.pump();
    expect(completed, isFalse);
    ack(sent.last.corr);
    expect(await result, isTrue);
  });

  testWidgets('rejected or timed-out line never sends Enter', (tester) async {
    final rejected = service.sendComposerSubmit('p', 'bad');
    ack(sent.last.corr, accepted: false);
    expect(await rejected, isFalse);
    expect(sent.length, 1);
    final timedOut = service.sendComposerSubmit('p', 'retry');
    await tester.pump(terminalReplyTimeout);
    expect(await timedOut, isFalse);
    expect(sent.length, 2);
  });

  test('correlated line error fails submit without Enter', () async {
    final result = service.sendComposerSubmit('p', 'line');
    incoming.add(
      Message.error(
        const ErrorMessage(
          code: ErrorCode.paneNotFound,
          message: 'missing pane',
          fatal: false,
        ),
        corr: sent.last.corr,
      ),
    );
    expect(await result, isFalse);
    expect(sent.length, 1);
  });

  testWidgets('Enter timeout preserves failed submit result', (tester) async {
    final result = service.sendComposerSubmit('p', 'line');
    ack(sent.last.corr);
    await tester.pump();
    expect(sent.length, 2);
    await tester.pump(terminalReplyTimeout);
    expect(await result, isFalse);
  });

  testWidgets('RTT matches input and probes and stops when disabled', (
    tester,
  ) async {
    service.send(
      const Message.sendInput(SendInput(paneId: 'p', keys: ['Tab'])),
      corr: 'key',
    );
    now = now.add(const Duration(milliseconds: 37));
    ack('unknown');
    expect(service.latestRtt.value, isNull);
    ack('key');
    expect(service.latestRtt.value, const Duration(milliseconds: 37));
    service.setRttProbeEnabled(enabled: true);
    await tester.pump(const Duration(seconds: 5));
    service.setRttProbeEnabled(enabled: true);
    await tester.pump(const Duration(seconds: 5));
    expect(sent.last.message, isA<MessagePing>());
    final probe = sent.last.corr;
    now = now.add(const Duration(milliseconds: 19));
    incoming.add(Message.pong(const Pong(), corr: probe));
    expect(service.latestRtt.value, const Duration(milliseconds: 19));
    service.setRttProbeEnabled(enabled: false);
    final count = sent.length;
    await tester.pump(const Duration(seconds: 30));
    expect(sent.length, count);
  });

  testWidgets('empty submit preserves Host answer text and sends only Enter', (
    tester,
  ) async {
    final result = service.sendComposerSubmit('p', '');
    expect(sent.length, 1);
    final input = (sent.single.message as MessageSendInput).payload;
    expect(input.line, isNull);
    expect(input.keys, ['Enter']);
    expect(input.defer, isNull);
    ack(sent.single.corr);
    expect(await result, isTrue);
  });

  for (final accepted in [true, false]) {
    testWidgets('queued submit waits for final accepted=$accepted', (
      tester,
    ) async {
      final result = service.sendComposerSubmit('p', 'draft', whenIdle: true);
      ack(sent.single.corr);
      await tester.pump();
      final enter = (sent.last.message as MessageSendInput).payload;
      expect(enter.keys, ['Enter']);
      expect(enter.line, isNull);
      expect(enter.defer, 'until_idle');
      now = now.add(const Duration(milliseconds: 12));
      ack(sent.last.corr, queued: true);
      expect(service.composerQueued.value, isTrue);
      bool? completed;
      unawaited(result.then((value) => completed = value));
      await tester.pump(const Duration(seconds: 20));
      expect(completed, isNull);
      now = now.add(const Duration(seconds: 20));
      ack(sent.last.corr, accepted: accepted);
      expect(await result, accepted);
      expect(service.composerQueued.value, isFalse);
      expect(service.latestRtt.value, const Duration(milliseconds: 12));
    });
  }

  testWidgets('cancel has a fresh corr and final rejection releases submit', (
    tester,
  ) async {
    final result = service.sendComposerSubmit('p', '', whenIdle: true);
    final heldCorr = sent.single.corr;
    ack(heldCorr, queued: true);
    final cancel = service.cancelComposerSubmit('p');
    final input = (sent.last.message as MessageSendInput).payload;
    expect(input.defer, 'cancel');
    expect(input.line, isNull);
    expect(input.keys, isNull);
    expect(sent.last.corr, isNot(heldCorr));
    ack(sent.last.corr);
    expect(await cancel, isTrue);
    expect(service.composerQueued.value, isTrue);
    ack(heldCorr, accepted: false);
    expect(await result, isFalse);
    expect(service.composerQueued.value, isFalse);
  });

  for (final oldAckFirst in [true, false]) {
    testWidgets('Send now transfers submit, old ACK first=$oldAckFirst', (
      tester,
    ) async {
      final result = service.sendComposerSubmit('p', '', whenIdle: true);
      final oldCorr = sent.single.corr;
      ack(oldCorr, queued: true);
      service.sendQueuedComposerNow('p');
      expect(sent.length, 2);
      final input = (sent.last.message as MessageSendInput).payload;
      expect(input.keys, ['Enter']);
      expect(input.line, isNull);
      expect(input.defer, isNull);
      expect(sent.last.corr, isNot(oldCorr));
      expect(service.composerQueued.value, isFalse);
      bool? completed;
      unawaited(result.then((value) => completed = value));
      if (oldAckFirst) ack(oldCorr, accepted: false);
      await tester.pump();
      expect(completed, isNull);
      ack(sent.last.corr);
      expect(await result, isTrue);
      if (!oldAckFirst) ack(oldCorr, accepted: false);
    });
  }

  testWidgets('Send now restores the normal acknowledgement timeout', (
    tester,
  ) async {
    final result = service.sendComposerSubmit('p', '', whenIdle: true);
    ack(sent.single.corr, queued: true);
    service.sendQueuedComposerNow('p');
    await tester.pump(terminalReplyTimeout);
    expect(await result, isFalse);
  });

  testWidgets('disconnect releases a queued submit without a timer', (
    tester,
  ) async {
    final result = service.sendComposerSubmit('p', '', whenIdle: true);
    ack(sent.single.corr, queued: true);
    service.disconnect();
    expect(await result, isFalse);
    expect(service.composerQueued.value, isFalse);
    ack(sent.single.corr);
    await tester.pump(terminalReplyTimeout);
  });

  testWidgets('disconnect after line ACK prevents a late Enter', (
    tester,
  ) async {
    final result = service.sendComposerSubmit('p', 'draft', whenIdle: true);
    ack(sent.single.corr);
    service.disconnect();
    await tester.pump();
    expect(await result, isFalse);
    expect(sent.length, 1);
  });
  test('dispose releases a queued submit', () async {
    final result = service.sendComposerSubmit('p', '', whenIdle: true);
    ack(sent.single.corr, queued: true);
    await service.dispose();
    expect(await result, isFalse);
    service = TerminalService(
      messages: incoming.stream,
      send: (message, {corr}) {},
      watchPane: (paneId, {corr}) {},
      unwatchPane: (paneId, {corr}) {},
    );
  });
  test('dispose fails the pending submit and prevents more sends', () async {
    service.setRttProbeEnabled(enabled: true);
    final result = service.sendComposerSubmit('p', 'draft');
    await service.dispose();
    expect(await result, isFalse);
    service.sendComposerLine('p', 'after dispose');
    expect(sent.length, 1);
    service = TerminalService(
      messages: incoming.stream,
      send: (message, {corr}) {},
      watchPane: (paneId, {corr}) {},
      unwatchPane: (paneId, {corr}) {},
    );
  });
}
