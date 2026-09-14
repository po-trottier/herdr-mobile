/// Asserts the frame envelope's 1 MiB maximum size against the same literal
/// value the shared Rust protocol crate uses, per `docs/11-relay-protocol.md`
/// R-11-035 and `docs/41-code-standards.md` R-41-039.
///
/// `maxFrameSizeBytes` below is transcribed from
/// `crates/herdr-relay-proto/src/frame.rs:19`:
/// `pub const MAX_FRAME_SIZE: usize = 1_048_576;`
///
/// No `app/lib/` model exists yet for this phase (`docs/90-implementation-plan.md`
/// Phase 5's `app/lib/models/` codegen checkbox belongs to a later work
/// package), so this test checks the same length comparison the Rust crate's
/// `Frame::from_json_bytes` performs
/// (`crates/herdr-relay-proto/src/frame.rs:116-119`: the byte length is
/// checked against `MAX_FRAME_SIZE` before any JSON allocation, mirrored here
/// by `dart:convert`'s `utf8.encode`) rather than exercising a Dart decoder.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

/// Mirrors `MAX_FRAME_SIZE` in `crates/herdr-relay-proto/src/frame.rs:19`.
const int maxFrameSizeBytes = 1048576;

void main() {
  test(
    'the maximum frame size is the single 1 MiB value the repository names',
    () {
      // R-11-035: "1 MiB (1048576 bytes)... the single value for the whole
      // repository."
      expect(maxFrameSizeBytes, equals(1024 * 1024));
    },
  );

  test('a frame of exactly the maximum size is not oversized', () {
    final bytes = utf8.encode('a' * maxFrameSizeBytes);
    expect(bytes.length, equals(maxFrameSizeBytes));
    expect(bytes.length > maxFrameSizeBytes, isFalse);
  });

  test('a frame one byte over the maximum size is oversized', () {
    // Mirrors crates/herdr-relay-proto/src/frame.rs:169-173
    // (`from_json_bytes_rejects_a_frame_over_the_max_size`), which checks
    // `bytes.len() > MAX_FRAME_SIZE` on a `MAX_FRAME_SIZE + 1`-byte input.
    final bytes = utf8.encode('a' * (maxFrameSizeBytes + 1));
    expect(bytes.length, equals(maxFrameSizeBytes + 1));
    expect(bytes.length > maxFrameSizeBytes, isTrue);
  });
}
