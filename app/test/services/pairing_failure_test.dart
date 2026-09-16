import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/services/pairing_failure.dart';
import 'package:herdr_mobile/services/relay.dart';

void main() {
  test('relay sentences retain their wording without credentials', () {
    expect(
      pairingFailureSentence(
        const RelayRegistrationException(
          RelayRegistrationErrorCode.handleUnknown,
          'Unknown private-handle at wss://relay.example.com/private.',
        ),
        'relay.example.com',
        secrets: ['private-handle'],
      ),
      'Unknown [redacted] at [redacted]',
    );
  });
  test(
    'protocol failures keep their message and closed streams name the cause',
    () {
      expect(
        pairingFailureSentence(
          const RelayConnectException(
            RelayConnectFailure.protocolMismatch,
            'Update the app.',
          ),
          'relay.example.com',
        ),
        'Update the app.',
      );
      expect(
        pairingFailureSentence(
          const RelayConnectException(
            RelayConnectFailure.webSocketFailed,
            'the relay closed the connection before sending a registration response',
          ),
          'relay.example.com',
        ),
        contains('relay closed the connection'),
      );
    },
  );
  test('transport failures identify the relay and the cause', () {
    for (final code in [61, 111, 10061]) {
      expect(
        pairingFailureSentence(
          SocketException('failed', osError: OSError('failed', code)),
          'relay.example.com',
        ),
        'Could not reach relay.example.com: connection refused.',
      );
    }
    expect(
      pairingFailureSentence(
        const SocketException('failed', osError: OSError('failed', 113)),
        'relay.example.com',
      ),
      contains('no route to the network'),
    );
    expect(
      pairingFailureSentence(
        TimeoutException('failed', const Duration(seconds: 10)),
        'relay.example.com',
      ),
      contains('10 s'),
    );
    expect(
      pairingFailureSentence(
        const HandshakeException('failed'),
        'relay.example.com',
      ),
      contains('TLS failed'),
    );
    expect(
      pairingFailureSentence(
        const WebSocketException('failed'),
        'relay.example.com',
      ),
      contains('the relay closed the connection'),
    );
  });

  test('fallback errors cannot disclose credentials or a full URI', () {
    const phrase = 'one-two-three-four-five-six';
    const handle = 'private-routing-handle';
    final sentence = pairingFailureSentence(
      Exception(
        'failed wss://relay.example.com/path?token=secret $phrase $handle one two three four five six',
      ),
      'relay.example.com',
      secrets: [phrase, handle],
    );
    expect(sentence, startsWith('Could not reach relay.example.com: failed'));
    expect(sentence, isNot(contains('wss://')));
    expect(sentence, isNot(contains(phrase)));
    expect(sentence, isNot(contains(handle)));
    expect(sentence, isNot(contains('one two three four five six')));
  });
}
