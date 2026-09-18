import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/models/message.dart';
import 'package:herdr_mobile/models/messages/send_input.dart';
import 'package:herdr_mobile/models/messages/watch_ack.dart';

void main() {
  test('complete line preserves empty text and Unicode', () {
    for (final line in ['', 'a🙂\n漢字']) {
      final input = SendInput.fromJson({'pane_id': 'p', 'line': line});
      expect(input.line, line);
      expect(input.toJson(), {'pane_id': 'p', 'line': line});
    }
    expect(
      SendInput.fromJson({
        'pane_id': 'p',
        'keys': ['Enter'],
      }).line,
      isNull,
    );
  });

  test('watch ACK defaults missing line and preserves a present line', () {
    final payload = <String, dynamic>{
      'pane_id': 'p',
      'revision': 1,
      'viewport_rows': 24,
      'width': 80,
      'scroll': {'offset_from_bottom': 0, 'max_offset_from_bottom': 0},
    };
    expect(WatchAck.fromJson(payload).line, '');
    expect(WatchAck.fromJson({...payload, 'line': 'draft'}).line, 'draft');
  });

  test('RTT codecs preserve envelope corr without changing payload', () {
    final ping = messageFromTypeAndPayload('ping', {});
    expect(ping.typeName, 'ping');
    expect(ping.payloadJson, isEmpty);
    final pong =
        messageFromTypeAndPayload('pong', {}, corr: 'probe') as MessagePong;
    expect(pong.corr, 'probe');
    expect(pong.typeName, 'pong');
    expect(pong.payloadJson, isEmpty);
    final ack = messageFromTypeAndPayload('send_input_ack', {
      'pane_id': 'p',
      'accepted': true,
    }, corr: 'input') as MessageSendInputAck;
    expect(ack.corr, 'input');
    expect(ack.payload.queued, isNull);
    expect(ack.payloadJson, {'pane_id': 'p', 'accepted': true});
  });
  test('deferred input and queued acknowledgement survive wire encoding', () {
    final input = SendInput.fromJson({
      'pane_id': 'p',
      'keys': ['Enter'],
      'defer': 'until_idle',
    });
    expect(input.defer, 'until_idle');
    expect(input.toJson()['defer'], 'until_idle');
    expect(
      const SendInput(paneId: 'p', defer: 'cancel').toJson()['defer'],
      'cancel',
    );
    final ack = messageFromTypeAndPayload('send_input_ack', {
      'pane_id': 'p',
      'accepted': true,
      'queued': true,
    }, corr: 'held') as MessageSendInputAck;
    expect(ack.payload.queued, isTrue);
    expect(ack.payloadJson['queued'], isTrue);
    expect(ack.corr, 'held');
  });
}
