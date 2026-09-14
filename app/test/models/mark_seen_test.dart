import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/models/message.dart';
import 'package:herdr_mobile/models/messages/mark_seen.dart';

void main() {
  test('mark_seen round-trips the wire payload (R-11-240)', () {
    const payload = <String, dynamic>{'pane_id': 'w28:p1R'};
    final message = messageFromTypeAndPayload('mark_seen', payload);
    expect(message, const Message.markSeen(MarkSeen(paneId: 'w28:p1R')));
    expect(message.typeName, 'mark_seen');
    expect(message.payloadJson, payload);
  });
}
