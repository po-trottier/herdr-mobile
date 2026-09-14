/// Compress-then-fragment on send, defragment-then-decompress on receive, between the
/// frame envelope (`docs/11-relay-protocol.md` §3.2) and `noise.dart`'s `NoiseCipher`
/// (`docs/11-relay-protocol.md` §3.4, §3.5, R-11-229 through R-11-239). The exact byte-for-
/// byte mirror of `crates/herdr-relay/src/frame_codec.rs`, read directly to build this file.
///
/// `uncompressed_len` is **big-endian** (R-11-231's exact text: `[codec: u8]
/// [uncompressed_len: u32, big-endian][body: bytes]`), not little-endian.
///
/// This file owns no networking and no WebSocket close-code logic: it is pure codec and
/// reassembly logic over byte lists and `noise.dart`'s `NoiseCipher`. Every
/// [FrameCodecProtocolError] is this file's signal for an R-11-237/R-11-238 violation;
/// `relay.dart`, which owns the actual WebSocket connection, maps it to closing with code
/// `4003` (R-11-121).
library;

import 'dart:io' show ZLibDecoder, ZLibEncoder;
import 'dart:typed_data';

import '../core/result/result.dart' show Err, Ok, Result;
import 'noise.dart' show NoiseCipher;

/// R-11-035, R-11-233: the frame envelope's raw byte length cap, and the cap on
/// `uncompressed_len` and on decompression output.
const int maxUncompressedLen = 1048576;

/// R-11-231: `codec` (1 byte) + `uncompressed_len` (4 bytes).
const int _recordHeaderLen = 5;

/// R-11-236: the largest a legal compression record can be — 1 MiB raw (codec `0`), or
/// zlib's worst-case expansion on already-compact data plus this record's own header:
/// `1048576 + 1048576 / 1000 + 12 + 5`.
const int maxCompressedRecordLen = 1049641;

/// R-11-235: `snow`'s 65535-byte Noise message ceiling (`noise.rs`'s `MAX_MESSAGE_LEN`,
/// matching `snow`'s own limit) less the 16-byte ChaChaPoly AEAD tag every
/// `NoiseCipher.encrypt` call appends.
const int _noisePlaintextCeiling = 65535 - 16;

/// R-11-235: `[frag_index: u8][frag_count: u8]`.
const int _fragmentHeaderLen = 2;

/// R-11-235: usable `chunk` bytes per physical Noise transport message.
const int maxChunkLen = _noisePlaintextCeiling - _fragmentHeaderLen;

/// R-11-236: a receiver MUST reject a `frag_count` above this, on the first fragment,
/// before allocating a reassembly buffer.
const int maxFragCount = 40;

/// R-11-238: matches R-11-023's existing pong-response bound; no new timing constant.
const Duration interFragmentTimeout = Duration(seconds: 10);

/// A codec, fragmentation, or reassembly-timing violation. Every instance maps to
/// R-11-121's `protocol_error` / WebSocket close code `4003` at `relay.dart`'s transport
/// layer; this file itself closes nothing.
sealed class FrameCodecError implements Exception {
  const FrameCodecError();
}

/// R-11-035, R-11-233: the envelope's raw bytes exceed 1 MiB before this record is even
/// built. Distinct from [FrameCodecProtocolError] because R-11-036 already gives it a
/// separate wire error code (`frame_too_large`), never `protocol_error`.
final class EnvelopeTooLarge extends FrameCodecError {
  const EnvelopeTooLarge();

  @override
  String toString() =>
      'the envelope exceeds the 1 MiB frame-size cap (R-11-035, R-11-233)';
}

/// Every R-11-231, R-11-234, R-11-236, R-11-237 or R-11-238 violation.
final class FrameCodecProtocolError extends FrameCodecError {
  const FrameCodecProtocolError(this.reason);

  final String reason;

  @override
  String toString() => 'protocol_error: $reason';
}

/// R-11-229 steps 1 through 4: builds the compression record from [envelopeBytes],
/// splits it into fragments, and Noise-encrypts each one — one [NoiseCipher.encrypt] call
/// per fragment, exactly as R-11-229 specifies. The caller sends each returned ciphertext
/// as its own physical WebSocket binary frame, in order (step 5, not this file's job).
Future<Result<List<Uint8List>>> encodeFrame(
  NoiseCipher sendCipher,
  Uint8List envelopeBytes,
) async {
  final recordResult = _buildRecord(envelopeBytes);
  if (recordResult is Err<Uint8List>) {
    return Err(recordResult.message, cause: recordResult.cause);
  }
  final record = (recordResult as Ok<Uint8List>).value;
  final ciphertexts = <Uint8List>[];
  for (final fragment in _splitIntoFragments(record)) {
    ciphertexts.add(await sendCipher.encrypt(fragment));
  }
  return Ok(ciphertexts);
}

/// Receive-side reassembly state for one Noise session (R-11-237, R-11-238, R-11-239).
/// One instance tracks at most one in-progress record at a time; a fresh `Noise_KK`
/// session (reconnect) needs a fresh [Reassembler], since R-11-238 already notes a lost
/// connection discards any partial buffer.
final class Reassembler {
  _PartialRecord? _partial;

  /// `true` while a record is only partially reassembled — a caller with an active
  /// deadline (`relay.dart`'s own R-11-238 wiring) races its next read against
  /// [partialDeadline] only during this window; a connection idling between complete,
  /// separate application messages MUST NOT time out.
  bool get hasPartial => _partial != null;

  /// The instant by which the next fragment of the in-progress record MUST arrive
  /// (R-11-238's 10-second inter-fragment window measured from the last fragment
  /// accepted), or `null` while [hasPartial] is `false`. [acceptFragment] itself only
  /// checks this reactively, when a next fragment happens to arrive; a caller that needs
  /// to notice a peer that never sends another byte at all MUST race its own read against
  /// this deadline with a real timer (`relay.dart`'s `_awaitNextFragment`).
  DateTime? get partialDeadline =>
      _partial?.lastFragmentAt.add(interFragmentTimeout);

  /// Feeds one already-Noise-decrypted fragment plaintext ([NoiseCipher.decrypt]'s
  /// output). Returns `Ok(envelopeBytes)` once a complete record has been reassembled and
  /// decompressed, `Ok(null)` while a record is still in progress, or `Err` on any
  /// R-11-236/R-11-237/R-11-238 violation — which always discards this reassembler's
  /// partial buffer (R-11-237), leaving it ready for a fresh record on the next call, on
  /// the assumption the caller closes the connection.
  ///
  /// [now] defaults to [DateTime.now] so R-11-238's 10-second inter-fragment timeout is
  /// deterministically testable with no real sleeping.
  Result<Uint8List?> acceptFragment(
    Uint8List plaintext, {
    DateTime Function() now = DateTime.now,
  }) {
    final currentTime = now();
    final existing = _partial;
    if (existing != null &&
        currentTime.difference(existing.lastFragmentAt) >
            interFragmentTimeout) {
      _partial = null;
      return const Err(
        'reassemble a fragmented frame',
        cause: FrameCodecProtocolError(
          'no fragment arrived within 10 seconds of the previous one (R-11-238)',
        ),
      );
    }

    if (plaintext.length < _fragmentHeaderLen) {
      _partial = null;
      return const Err(
        'reassemble a fragmented frame',
        cause: FrameCodecProtocolError(
          'fragment shorter than its 2-byte header (R-11-235)',
        ),
      );
    }
    final fragIndex = plaintext[0];
    final fragCount = plaintext[1];
    final chunk = plaintext.sublist(_fragmentHeaderLen);

    if (existing == null) {
      if (fragIndex != 0) {
        return const Err(
          'reassemble a fragmented frame',
          cause: FrameCodecProtocolError(
            'the first fragment of a record must be frag_index 0 (R-11-237)',
          ),
        );
      }
      // R-11-236: reject an out-of-bounds frag_count before allocating any reassembly
      // buffer or accepting any chunk bytes.
      if (fragCount == 0 || fragCount > maxFragCount) {
        return const Err(
          'reassemble a fragmented frame',
          cause: FrameCodecProtocolError(
            'frag_count is zero or exceeds the maximum of 40 (R-11-236)',
          ),
        );
      }
      if (chunk.length > maxCompressedRecordLen) {
        return const Err(
          'reassemble a fragmented frame',
          cause: FrameCodecProtocolError(
            'running fragment byte total exceeds the compression-record cap (R-11-236)',
          ),
        );
      }
      if (fragCount == 1) {
        return _wrapDecoded(_decodeRecord(Uint8List.fromList(chunk)));
      }
      _partial = _PartialRecord(
        fragCount: fragCount,
        nextIndex: 1,
        buffer: BytesBuilder()..add(chunk),
        lastFragmentAt: currentTime,
      );
      return const Ok(null);
    }

    if (fragCount != existing.fragCount) {
      _partial = null;
      return const Err(
        'reassemble a fragmented frame',
        cause: FrameCodecProtocolError(
          'frag_count changed within one record (R-11-237)',
        ),
      );
    }
    if (fragIndex != existing.nextIndex) {
      _partial = null;
      return const Err(
        'reassemble a fragmented frame',
        cause: FrameCodecProtocolError(
          'out-of-order, repeated, or skipped frag_index (R-11-237)',
        ),
      );
    }
    existing.buffer.add(chunk);
    existing.lastFragmentAt = currentTime;
    // R-11-236: independent of frag_count, reject the moment the running total exceeds
    // the cap, checked after every fragment, not only once reassembly finishes.
    if (existing.buffer.length > maxCompressedRecordLen) {
      _partial = null;
      return const Err(
        'reassemble a fragmented frame',
        cause: FrameCodecProtocolError(
          'running fragment byte total exceeds the compression-record cap (R-11-236)',
        ),
      );
    }

    if (fragIndex == fragCount - 1) {
      final buffer = existing.buffer.toBytes();
      _partial = null;
      return _wrapDecoded(_decodeRecord(buffer));
    }
    existing.nextIndex++;
    return const Ok(null);
  }

  Result<Uint8List?> _wrapDecoded(Result<Uint8List> decoded) =>
      switch (decoded) {
        Ok(:final value) => Ok(value),
        Err(:final message, :final cause) => Err(message, cause: cause),
      };
}

final class _PartialRecord {
  _PartialRecord({
    required this.fragCount,
    required this.nextIndex,
    required this.buffer,
    required this.lastFragmentAt,
  });

  final int fragCount;
  int nextIndex;
  final BytesBuilder buffer;
  DateTime lastFragmentAt;
}

/// Convenience symmetric to [encodeFrame]: Noise-decrypts one physical WebSocket binary
/// frame's ciphertext, then feeds the plaintext into [reassembler]. See
/// [Reassembler.acceptFragment] for the return-value contract.
Future<Result<Uint8List?>> decodeFragment(
  Reassembler reassembler,
  NoiseCipher receiveCipher,
  Uint8List ciphertext, {
  DateTime Function() now = DateTime.now,
}) async {
  final Uint8List plaintext;
  try {
    plaintext = await receiveCipher.decrypt(ciphertext);
  } on Exception {
    // A Noise decrypt failure on a fragment is itself a wire-level integrity failure
    // with no more specific R-11 code than protocol_error, mirroring
    // frame_codec.rs's `From<NoiseError>` mapping.
    return const Err(
      'decode a Noise-encrypted fragment',
      cause: FrameCodecProtocolError(
        'Noise transport error while encoding or decoding a fragment',
      ),
    );
  }
  return reassembler.acceptFragment(plaintext, now: now);
}

/// R-11-229 step 2, R-11-231, R-11-232, R-11-233: builds one compression record from a
/// frame envelope's serialized UTF-8 bytes.
Result<Uint8List> _buildRecord(Uint8List envelopeBytes) {
  // R-11-233: check the raw cap before this record is built, exactly as R-11-036
  // already does at the envelope level.
  if (envelopeBytes.length > maxUncompressedLen) {
    return const Err('build a compression record', cause: EnvelopeTooLarge());
  }

  final compressed = _zlibCompress(envelopeBytes);
  // R-11-232: codec 1 only when it actually shrinks the payload; codec 0 otherwise.
  final int codec;
  final List<int> body;
  if (compressed.length < envelopeBytes.length) {
    codec = 1;
    body = compressed;
  } else {
    codec = 0;
    body = envelopeBytes;
  }

  final record = BytesBuilder();
  record.addByte(codec);
  final lengthBytes = ByteData(4)
    ..setUint32(0, envelopeBytes.length, Endian.big);
  record.add(lengthBytes.buffer.asUint8List());
  record.add(body);
  return Ok(record.toBytes());
}

/// R-11-231, R-11-234: parses and decompresses one reassembled compression record back
/// into the frame envelope's serialized UTF-8 bytes.
Result<Uint8List> _decodeRecord(Uint8List record) {
  if (record.length < _recordHeaderLen) {
    return const Err(
      'decode a compression record',
      cause: FrameCodecProtocolError(
        'compression record shorter than its 5-byte header (R-11-231)',
      ),
    );
  }
  final codec = record[0];
  final uncompressedLen = ByteData.sublistView(
    record,
    1,
    5,
  ).getUint32(0, Endian.big);
  final body = record.sublist(_recordHeaderLen);

  // R-11-234: reject a declared uncompressed_len already over the cap, before
  // attempting decompression at all.
  if (uncompressedLen > maxUncompressedLen) {
    return const Err(
      'decode a compression record',
      cause: FrameCodecProtocolError(
        'declared uncompressed_len exceeds the 1 MiB cap (R-11-234)',
      ),
    );
  }

  switch (codec) {
    case 0:
      // R-11-231: uncompressed_len MUST equal body's length for codec 0.
      if (body.length != uncompressedLen) {
        return const Err(
          'decode a compression record',
          cause: FrameCodecProtocolError(
            "codec 0's uncompressed_len does not match its body length (R-11-231)",
          ),
        );
      }
      return Ok(body);
    case 1:
      return _boundedZlibDecompress(body);
    default:
      return const Err(
        'decode a compression record',
        cause: FrameCodecProtocolError('unrecognised codec byte (R-11-231)'),
      );
  }
}

/// R-11-229 step 3, R-11-235: splits one compression record into fragment plaintexts,
/// each prefixed with `[frag_index: u8][frag_count: u8]`. [record] is never empty
/// ([_buildRecord] always emits at least its 5-byte header), so this always returns at
/// least one fragment.
List<Uint8List> _splitIntoFragments(Uint8List record) {
  final chunks = <Uint8List>[];
  for (var offset = 0; offset < record.length; offset += maxChunkLen) {
    final end = offset + maxChunkLen < record.length
        ? offset + maxChunkLen
        : record.length;
    chunks.add(record.sublist(offset, end));
  }
  assert(
    chunks.isNotEmpty,
    '_buildRecord always emits at least its 5-byte header',
  );
  assert(
    chunks.length <= maxFragCount,
    "_buildRecord's own maxUncompressedLen cap keeps every record this file "
    'produces well under maxFragCount fragments',
  );
  final fragCount = chunks.length;
  return [
    for (var index = 0; index < chunks.length; index++)
      Uint8List.fromList([index, fragCount, ...chunks[index]]),
  ];
}

/// Compresses [data] with zlib (RFC 1950), for [_buildRecord]'s R-11-232 codec decision.
/// `dart:io`'s `ZLibEncoder` defaults to the zlib format (a 2-byte header plus an Adler-32
/// trailer, `raw: false`), matching `flate2::write::ZlibEncoder`'s own default format —
/// the two implementations decompress each other's output regardless of any compression
/// *level* difference, since zlib decompression does not depend on the level used to
/// compress (R-11-232, R-20-011: no new pub.dev dependency).
Uint8List _zlibCompress(List<int> data) =>
    Uint8List.fromList(ZLibEncoder().convert(data));

/// R-11-234: decompresses [body] with a bounded, streaming reader that aborts the instant
/// its *actual* output exceeds [maxUncompressedLen] — the declared `uncompressed_len` in
/// [_buildRecord]'s record is never trusted as the sole bound, so a sender that lies about
/// it while shipping an oversized compressed payload (a decompression bomb) is stopped
/// here, not by the declared field. Input is fed to the streaming decoder in small
/// chunks so a pathological input (zlib's worst-case expansion is roughly 1032:1) is
/// caught well before its full output would ever be materialised.
Result<Uint8List> _boundedZlibDecompress(List<int> body) {
  const inputChunkSize = 256;
  final sink = _BoundedByteSink(maxUncompressedLen);
  final decoderSink = ZLibDecoder().startChunkedConversion(sink);
  try {
    for (var offset = 0; offset < body.length; offset += inputChunkSize) {
      final end = offset + inputChunkSize < body.length
          ? offset + inputChunkSize
          : body.length;
      decoderSink.add(body.sublist(offset, end));
      if (sink.exceeded) {
        return const Err(
          'decompress a compression record',
          cause: FrameCodecProtocolError(
            'decompressed output exceeds the 1 MiB cap '
            '(R-11-234, decompression-bomb defence)',
          ),
        );
      }
    }
    decoderSink.close();
  } on FormatException {
    return const Err(
      'decompress a compression record',
      cause: FrameCodecProtocolError('zlib decompression failed (R-11-234)'),
    );
  }
  if (sink.exceeded) {
    return const Err(
      'decompress a compression record',
      cause: FrameCodecProtocolError(
        'decompressed output exceeds the 1 MiB cap '
        '(R-11-234, decompression-bomb defence)',
      ),
    );
  }
  return Ok(sink.bytes());
}

/// A [Sink] that accumulates decompressed bytes and marks [exceeded] the instant the
/// running total passes [maxBytes], without ever growing its buffer past one chunk
/// beyond that point.
final class _BoundedByteSink implements Sink<List<int>> {
  _BoundedByteSink(this.maxBytes);

  final int maxBytes;
  final BytesBuilder _builder = BytesBuilder(copy: false);
  bool exceeded = false;

  @override
  void add(List<int> chunk) {
    if (exceeded) {
      return;
    }
    _builder.add(chunk);
    if (_builder.length > maxBytes) {
      exceeded = true;
    }
  }

  @override
  void close() {}

  Uint8List bytes() => _builder.toBytes();
}
