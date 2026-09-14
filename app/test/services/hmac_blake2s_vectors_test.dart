/// Proves `hmacBlake2s` (`app/lib/services/hmac_blake2s.dart`, `WP-14-b`) reproduces every
/// vector in `crates/herdr-relay/tests/hmac_blake2s_vectors.json` byte for byte (R-13-072,
/// R-40-034, R-40-037). This file reads that same committed JSON file directly — it holds no
/// second, hand-transcribed copy of the vectors — exactly as
/// `crates/herdr-relay/tests/hmac_blake2s_vectors.rs` does on the Rust side.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/services/hmac_blake2s.dart';

/// Relative to the package root, which is `flutter test`'s working directory (`app/`).
/// `crates/` is `app/`'s sibling, matching the path convention
/// `app/test/models/vectors_test.dart` already established for a shared Rust/Dart fixture.
const String _vectorsPath =
    '../crates/herdr-relay/tests/hmac_blake2s_vectors.json';

Uint8List _decodeHex(String hex) {
  assert(hex.length.isEven, 'odd-length hex string: $hex');
  final bytes = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

String _encodeHex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final file = File(_vectorsPath);

  test('the shared vectors file exists at the path both languages read', () {
    expect(
      file.existsSync(),
      isTrue,
      reason: 'expected the committed fixture at ${file.path}',
    );
  });

  if (!file.existsSync()) {
    return;
  }

  final document = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final vectors = (document['vectors'] as List<dynamic>)
      .cast<Map<String, dynamic>>();

  test('the committed file is non-empty', () {
    expect(vectors, isNotEmpty);
  });

  for (final vector in vectors) {
    final name = vector['name'] as String;
    test(
      'hmacBlake2s reproduces vector "$name" byte for byte (R-13-072)',
      () async {
        final key = _decodeHex(vector['key_hex'] as String);
        final data = _decodeHex(vector['data_hex'] as String);
        final expectedMacHex = vector['expected_mac_hex'] as String;

        final actual = await hmacBlake2s(key, data);

        expect(_encodeHex(actual), expectedMacHex);
      },
    );
  }

  test('every vector name in the committed file is unique', () {
    final names = vectors.map((vector) => vector['name'] as String).toList();
    expect(
      names.toSet().length,
      names.length,
      reason: 'a duplicate vector name would shadow an earlier one silently',
    );
  });

  test('a 64-byte key (R-13-072\'s stated maximum) is accepted', () async {
    final sixtyFourByteVector = vectors.firstWhere(
      (vector) => vector['name'] == 'sixty_four_byte_key',
    );
    final key = _decodeHex(sixtyFourByteVector['key_hex'] as String);
    expect(key, hasLength(64));

    final mac = await hmacBlake2s(key, const []);

    expect(mac, hasLength(32));
  });
}
