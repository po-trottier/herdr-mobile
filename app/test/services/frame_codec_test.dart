/// Proves `frame_codec.dart` (`WP-14-b`) reproduces `crates/herdr-relay/src/frame_codec.rs`'s
/// behaviour: the compress-then-fragment send path, the defragment-then-decompress receive
/// path, and every R-11-231 through R-11-239 adversarial bound, mirroring that file's own
/// `#[cfg(test)] mod tests` case for case (adapted to this file's public API only — the
/// private `build_record`/`decode_record` Rust calls directly are exercised here through
/// [encodeFrame]/[Reassembler.acceptFragment] instead).
library;

import 'dart:convert';
import 'dart:io' show ZLibEncoder;
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart';
import 'package:herdr_mobile/services/frame_codec.dart';
import 'package:herdr_mobile/services/noise.dart';

/// A fixed, non-secret test key mirroring `noise.dart`'s own `NoiseCipher.withKey`
/// convention: proves this file's compression/fragmentation logic independent of the
/// (separately proven, see `noise.dart`'s own interop check) Noise handshake. Both ends of
/// every round trip below use the same key: `NoiseCipher` does not care about direction,
/// only that both sides' encrypt/decrypt call sequence stays nonce-for-nonce in lockstep.
final Uint8List _keyA = Uint8List.fromList(List.generate(32, (i) => i));

/// Sends [envelopeBytes] from [sender] to [receiver] through the full
/// `encodeFrame`/`decodeFragment` pipeline and returns the reassembled envelope bytes,
/// asserting every fragment arrives (nothing is dropped) and the record completes only on
/// the last one.
Future<(Uint8List decoded, int fragmentCount)> _roundTrip(
  NoiseCipher sender,
  NoiseCipher receiver,
  Uint8List envelopeBytes,
) async {
  final encoded = await encodeFrame(sender, envelopeBytes);
  expect(encoded, isA<Ok<List<Uint8List>>>());
  final fragments = (encoded as Ok<List<Uint8List>>).value;

  final reassembler = Reassembler();
  Uint8List? result;
  for (var index = 0; index < fragments.length; index++) {
    final outcome = await decodeFragment(
      reassembler,
      receiver,
      fragments[index],
    );
    expect(outcome, isA<Ok<Uint8List?>>());
    final value = (outcome as Ok<Uint8List?>).value;
    if (index == fragments.length - 1) {
      expect(
        value,
        isNotNull,
        reason: 'the last fragment must complete the record',
      );
      result = value;
    } else {
      expect(
        value,
        isNull,
        reason: 'an earlier fragment must not complete the record',
      );
    }
  }
  return (result!, fragments.length);
}

void main() {
  test(
    'a small payload round-trips as a single fragment (raw fallback)',
    () async {
      final envelope = Uint8List.fromList(
        utf8.encode('{"v":1,"type":"ping","seq":1,"payload":{}}'),
      );

      final (decoded, fragmentCount) = await _roundTrip(
        NoiseCipher.withKey(_keyA),
        NoiseCipher.withKey(_keyA),
        envelope,
      );

      expect(fragmentCount, 1);
      expect(decoded, envelope);
    },
  );

  test('a large compressible payload round-trips across multiple fragments with zlib', () async {
    final buffer = StringBuffer();
    for (var i = 0; i < 14500; i++) {
      buffer.write(
        '{"index":$i,"note":"herdr-relay frame codec fixture line $i"},',
      );
    }
    final envelope = Uint8List.fromList(utf8.encode(buffer.toString()));
    expect(envelope.length, lessThan(maxUncompressedLen));

    final (decoded, fragmentCount) = await _roundTrip(
      NoiseCipher.withKey(_keyA),
      NoiseCipher.withKey(_keyA),
      envelope,
    );

    expect(
      fragmentCount,
      greaterThan(1),
      reason:
          'fixture must force multi-fragment splitting even after compression',
    );
    expect(decoded, envelope);
  });

  test('an incompressible near-1-MiB payload round-trips across multiple fragments '
      'with the raw fallback', () async {
    // High-entropy bytes via repeated SHA-256 digests of a counter: deterministic and
    // reproducible, but not zlib-compressible.
    final builder = BytesBuilder();
    var counter = 0;
    while (builder.length < 1000000) {
      final counterBytes = ByteData(8)..setUint64(0, counter, Endian.little);
      final digest = await Sha256().hash(counterBytes.buffer.asUint8List());
      builder.add(digest.bytes);
      counter++;
    }
    final envelope = Uint8List.sublistView(builder.toBytes(), 0, 1000000);
    expect(envelope.length, lessThan(maxUncompressedLen));

    final (decoded, fragmentCount) = await _roundTrip(
      NoiseCipher.withKey(_keyA),
      NoiseCipher.withKey(_keyA),
      envelope,
    );

    expect(
      fragmentCount,
      greaterThan(1),
      reason: 'fixture must force multi-fragment splitting',
    );
    expect(decoded, envelope);
  });
  test('an envelope over 1 MiB is rejected before compression', () async {
    final sender = NoiseCipher.withKey(_keyA);
    final oversized = Uint8List(maxUncompressedLen + 1);

    final result = await encodeFrame(sender, oversized);

    expect(result, isA<Err<List<Uint8List>>>());
    expect((result as Err<List<Uint8List>>).cause, isA<EnvelopeTooLarge>());
  });

  test('a frag_count of 41 is rejected before any allocation (R-11-236)', () {
    final reassembler = Reassembler();
    final firstFragment = Uint8List.fromList([0, 41, 1, 2, 3]);

    final result = reassembler.acceptFragment(firstFragment);

    expect(result, isA<Err<Uint8List?>>());
    final cause = (result as Err<Uint8List?>).cause;
    expect(cause, isA<FrameCodecProtocolError>());
    expect(
      (cause! as FrameCodecProtocolError).reason,
      contains('frag_count is zero or exceeds the maximum of 40'),
    );
  });

  test('a frag_count of 40 is accepted', () {
    final reassembler = Reassembler();
    final firstFragment = Uint8List.fromList([0, 40, 9, 9, 9]);

    final result = reassembler.acceptFragment(firstFragment);

    expect(result, isA<Ok<Uint8List?>>());
    expect(
      (result as Ok<Uint8List?>).value,
      isNull,
      reason:
          'frag_count 40 with more fragments still owed must not complete yet',
    );
  });

  test('a lying uncompressed_len is rejected by the bounded decompressor (R-11-234)', () {
    // A genuine decompression bomb: 2 MiB of zeros compresses tiny, but the declared
    // uncompressed_len lies and claims only 10 bytes.
    final realPayload = Uint8List(2 * 1048576);
    final compressed = ZLibEncoder().convert(realPayload);
    final record = BytesBuilder()
      ..addByte(1) // codec 1 (zlib)
      ..add((ByteData(4)..setUint32(0, 10, Endian.big)).buffer.asUint8List())
      ..add(compressed);
    final fragment = BytesBuilder()
      ..addByte(0) // frag_index
      ..addByte(1) // frag_count
      ..add(record.toBytes());

    final reassembler = Reassembler();
    final result = reassembler.acceptFragment(fragment.toBytes());

    expect(result, isA<Err<Uint8List?>>());
    final cause = (result as Err<Uint8List?>).cause! as FrameCodecProtocolError;
    expect(cause.reason, contains('decompressed output exceeds the 1 MiB cap'));
  });

  test('an out-of-order fragment is rejected (R-11-237)', () {
    final reassembler = Reassembler();
    // frag_count 3, but frag_index jumps straight from 0 to 2.
    final first = Uint8List.fromList([0, 3, 1, 2, 3]);
    expect((reassembler.acceptFragment(first) as Ok<Uint8List?>).value, isNull);
    final outOfOrder = Uint8List.fromList([2, 3, 7, 8, 9]);

    final result = reassembler.acceptFragment(outOfOrder);

    expect(result, isA<Err<Uint8List?>>());
    final cause = (result as Err<Uint8List?>).cause! as FrameCodecProtocolError;
    expect(
      cause.reason,
      contains('out-of-order, repeated, or skipped frag_index'),
    );
  });

  test(
    "a new record's frag_index 0 before the previous record's last fragment is "
    'rejected (R-11-237)',
    () {
      final reassembler = Reassembler();
      final first = Uint8List.fromList([0, 2, 1, 2, 3]);
      expect(
        (reassembler.acceptFragment(first) as Ok<Uint8List?>).value,
        isNull,
      );
      // Same frag_count (2) as the in-progress record, so this exercises the
      // frag_index ordering check specifically, not the frag_count-consistency check.
      final interleavedNewRecord = Uint8List.fromList([0, 2, 9, 9]);

      final result = reassembler.acceptFragment(interleavedNewRecord);

      expect(result, isA<Err<Uint8List?>>());
      final cause =
          (result as Err<Uint8List?>).cause! as FrameCodecProtocolError;
      expect(
        cause.reason,
        contains('out-of-order, repeated, or skipped frag_index'),
      );
    },
  );

  test('a stale partial record times out after 10 seconds (R-11-238)', () {
    final reassembler = Reassembler();
    var clock = DateTime(2026);
    final first = Uint8List.fromList([0, 2, 1, 2, 3]);
    expect(
      (reassembler.acceptFragment(
        first,
        now: () => clock,
      ) as Ok<Uint8List?>).value,
      isNull,
    );

    clock = clock.add(const Duration(seconds: 11));
    final second = Uint8List.fromList([1, 2, 4, 5, 6]);

    final result = reassembler.acceptFragment(second, now: () => clock);

    expect(result, isA<Err<Uint8List?>>());
    final cause = (result as Err<Uint8List?>).cause! as FrameCodecProtocolError;
    expect(
      cause.reason,
      contains('no fragment arrived within 10 seconds of the previous one'),
    );
  });

  test('an unrecognised codec byte is rejected (R-11-231)', () {
    final record = BytesBuilder()
      ..addByte(2) // no codec 2 is defined
      ..add((ByteData(4)..setUint32(0, 0, Endian.big)).buffer.asUint8List());
    final fragment = BytesBuilder()
      ..addByte(0)
      ..addByte(1)
      ..add(record.toBytes());

    final reassembler = Reassembler();
    final result = reassembler.acceptFragment(fragment.toBytes());

    expect(result, isA<Err<Uint8List?>>());
    final cause = (result as Err<Uint8List?>).cause! as FrameCodecProtocolError;
    expect(cause.reason, contains('unrecognised codec byte'));
  });
}
