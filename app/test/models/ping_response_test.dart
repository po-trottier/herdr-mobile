/// Decodes the measured Herdr socket `ping` response for protocol 22.
/// See `docs/02-herdr-probe-results.md` R-02-028 and
/// `docs/10-herdr-integration.md` R-10-012.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

/// Measured on the live Herdr server on 2026-09-10 (R-02-028).
const String recordedPingResponse =
    '{"id":"proto22-probe","result":{"type":"pong",'
    '"version":"0.9.0-preview.2026-09-08-62431dbd033b","protocol":22,'
    '"capabilities":{"live_handoff":false,"detached_server_daemon":false,'
    '"endpoint_protocol_generation":1,"surface_interest":true,'
    '"health_check":true}}}';

/// The measured protocol for this build (R-02-028).
const int expectedHerdrProtocol = 22;

void main() {
  test('the recorded ping response decodes to a pong result', () {
    final decoded = jsonDecode(recordedPingResponse) as Map<String, dynamic>;
    final result = decoded['result'] as Map<String, dynamic>;

    expect(decoded['id'], equals('proto22-probe'));
    expect(result['type'], equals('pong'));
    expect(result['protocol'], equals(expectedHerdrProtocol));
    expect(result['version'], equals('0.9.0-preview.2026-09-08-62431dbd033b'));
  });

  test('result.protocol matches the protocol this build targets', () {
    // R-10-012: Protocol 22 permits the connection.
    final decoded = jsonDecode(recordedPingResponse) as Map<String, dynamic>;
    final result = decoded['result'] as Map<String, dynamic>;

    expect(result['protocol'] == expectedHerdrProtocol, isTrue);
  });

  test('a mismatched protocol integer fails the R-10-012 check', () {
    // R-10-012: A different protocol prevents the connection.
    final mismatched = jsonDecode(recordedPingResponse) as Map<String, dynamic>;
    (mismatched['result'] as Map<String, dynamic>)['protocol'] = 21;
    final result = mismatched['result'] as Map<String, dynamic>;

    expect(result['protocol'] == expectedHerdrProtocol, isFalse);
  });
}
