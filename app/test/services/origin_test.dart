/// Proves `parseRelayOrigin` (`app/lib/services/origin.dart`, `WP-14-b`) accepts the
/// canonical `https://`/local-development `http://` forms R-22-037 to R-22-039 describe and
/// rejects every other cleartext origin with `relay_origin_insecure` (R-03-033), and every
/// malformed origin with `relay_origin_invalid`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart' show Err, Ok;
import 'package:herdr_mobile/services/origin.dart';

void main() {
  group('accepted origins', () {
    test('a plain https:// origin round-trips to its canonical form', () {
      final result = parseRelayOrigin('https://relay.example.com');

      expect(result, isA<Ok<RelayOrigin>>());
      final origin = (result as Ok<RelayOrigin>).value;
      expect(origin.scheme, 'https');
      expect(origin.host, 'relay.example.com');
      expect(origin.port, isNull);
      expect(origin.canonical, 'https://relay.example.com');
      expect(origin.isInsecureDevelopment, isFalse);
    });

    test('an https:// origin with an explicit port keeps the port', () {
      final result = parseRelayOrigin('https://relay.example.com:8443');

      final origin = (result as Ok<RelayOrigin>).value;
      expect(origin.port, 8443);
      expect(origin.canonical, 'https://relay.example.com:8443');
    });

    test('a bare trailing slash is accepted as an empty path', () {
      final result = parseRelayOrigin('https://relay.example.com/');

      expect(result, isA<Ok<RelayOrigin>>());
    });

    for (final host in <String>[
      'localhost',
      '127.0.0.1',
      '127.255.255.254',
      '10.0.0.5',
      '172.16.0.1',
      '172.31.255.255',
      '192.168.1.1',
      '[::1]',
    ]) {
      test(
        'http://$host is accepted, per the R-22-039 local-development allow list',
        () {
          final result = parseRelayOrigin('http://$host:9944');

          expect(result, isA<Ok<RelayOrigin>>());
          final origin = (result as Ok<RelayOrigin>).value;
          expect(origin.isInsecureDevelopment, isTrue);
        },
      );
    }
  });

  group('rejected as relay_origin_insecure (R-03-033)', () {
    for (final host in <String>[
      'relay.example.com',
      '8.8.8.8',
      '172.32.0.1', // one address above the 172.16.0.0/12 range
      '9.255.255.255', // one address below 10.0.0.0/8
      '193.168.1.1', // not 192.168.0.0/16
    ]) {
      test('http://$host is rejected outside the local allow list', () {
        final result = parseRelayOrigin('http://$host');

        expect(result, isA<Err<RelayOrigin>>());
        final cause = (result as Err<RelayOrigin>).cause;
        expect(cause, isA<RelayOriginException>());
        expect(
          (cause as RelayOriginException).code,
          RelayOriginErrorCode.relayOriginInsecure,
        );
      });
    }
  });

  group('rejected as relay_origin_invalid', () {
    for (final text in <String>[
      'not a uri at all',
      'ftp://relay.example.com',
      'relay.example.com', // no scheme
      'https://', // no host
      'https://relay.example.com/path',
      'https://relay.example.com?query=1',
      'https://relay.example.com#fragment',
      'https://user@relay.example.com',
    ]) {
      test('"$text" is rejected as malformed', () {
        final result = parseRelayOrigin(text);

        expect(result, isA<Err<RelayOrigin>>());
        final cause = (result as Err<RelayOrigin>).cause;
        expect(cause, isA<RelayOriginException>());
        expect(
          (cause as RelayOriginException).code,
          RelayOriginErrorCode.relayOriginInvalid,
        );
      });
    }
  });

  group('webSocketUri (R-22-038, R-11-111)', () {
    test('https:// maps to wss://', () {
      final origin = (parseRelayOrigin(
        'https://relay.example.com',
      ) as Ok<RelayOrigin>).value;

      final uri = origin.webSocketUri('/device/n6Loxf94CfyIO6hOxlaHvA');

      expect(
        uri.toString(),
        'wss://relay.example.com/device/n6Loxf94CfyIO6hOxlaHvA',
      );
    });

    test('http:// maps to ws://, preserving the port', () {
      final origin =
          (parseRelayOrigin('http://127.0.0.1:9944') as Ok<RelayOrigin>).value;

      final uri = origin.webSocketUri('/host/abc');

      expect(uri.toString(), 'ws://127.0.0.1:9944/host/abc');
    });
  });
}
