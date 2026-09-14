/// `HMAC-BLAKE2s`, per `docs/13-security-pairing.md` R-13-072 exactly.
///
/// `cryptography` 2.9.0's `Blake2s.blockLengthInBytes` (in
/// `lib/src/cryptography/algorithms.dart`) returns `32`. RFC 7693 sets the BLAKE2s block
/// length at `64`, matching `snow` 0.10.0's own `HashBLAKE2s::block_len()` on the Host and
/// `blake2` 0.10.6's `BlockSize` type parameter. Because HMAC's inner/outer padding width is
/// exactly the block length, `cryptography`'s own `Hmac.blake2s()` therefore pads to the
/// wrong width and computes a MAC that does not match `snow`'s. `Hmac.blake2s()` MUST NOT be
/// used anywhere in the Noise state machine (`app/lib/services/noise.dart`); every `HKDF`,
/// `MixKey` and `MixKeyAndHash` call there MUST route through [hmacBlake2s] instead.
///
/// This is not a new instance of hand-rolled cryptography: R-13-072 assembles the public RFC
/// 2104 HMAC specification from the already-pinned, non-HMAC `Blake2s()` digest, working
/// around a padding-width defect in one wrapper method, not inventing a primitive.
///
/// `crates/herdr-relay/tests/hmac_blake2s_vectors.json` holds the fixed key/data/expected-MAC
/// triples both `crates/herdr-relay/tests/hmac_blake2s_vectors.rs` and this file's own
/// `app/test/services/hmac_blake2s_vectors_test.dart` assert against, byte for byte.
library;

import 'package:cryptography/cryptography.dart';

/// RFC 7693's BLAKE2s block length in bytes. `cryptography` 2.9.0's own
/// `Blake2s.blockLengthInBytes` reports `32`; this file hard-codes the correct value instead
/// (R-13-072).
const int _blockLengthInBytes = 64;

/// `HMAC-BLAKE2s(key, data)`, mirroring `snow` 0.10.0's own `HashBLAKE2s::hmac()`
/// (R-13-072): `ipad` is 64 bytes of `0x36`, `opad` is 64 bytes of `0x5c`, each XORed with
/// `key` zero-padded to 64 bytes, and the result is
/// `Blake2s().hash(opad + Blake2s().hash(ipad + data).bytes)` using the plain (non-HMAC)
/// `Blake2s()` digest for both the inner and the outer hash.
///
/// [key] MUST be at most 64 bytes. Every call site in `noise.dart` passes a `chaining_key`
/// of at most 32 bytes (the BLAKE2s digest size), so RFC 2104's over-length-key branch
/// (hashing the key down before use) is never exercised by this codebase and is
/// intentionally not implemented here, matching the same stated simplification in
/// `crates/herdr-relay/tests/hmac_blake2s_vectors.rs`.
Future<List<int>> hmacBlake2s(List<int> key, List<int> data) async {
  assert(
    key.length <= _blockLengthInBytes,
    'hmacBlake2s: key MUST be at most $_blockLengthInBytes bytes (R-13-072); '
    'got ${key.length}',
  );
  final paddedKey = List<int>.filled(_blockLengthInBytes, 0)
    ..setRange(0, key.length, key);
  final innerPad = List<int>.generate(
    _blockLengthInBytes,
    (i) => paddedKey[i] ^ 0x36,
  );
  final outerPad = List<int>.generate(
    _blockLengthInBytes,
    (i) => paddedKey[i] ^ 0x5c,
  );
  final inner = (await Blake2s().hash([...innerPad, ...data])).bytes;
  final outer = await Blake2s().hash([...outerPad, ...inner]);
  return outer.bytes;
}
