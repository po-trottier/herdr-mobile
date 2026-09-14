/// Asserts the PNG header properties `docs/23-platform-integration.md` fixes
/// for the committed store icon exports: the Apple App Store icon's
/// dimensions and lack of an alpha channel (R-23-050, checkable half of
/// R-23-053), and the Google Play icon's dimensions and alpha channel
/// (R-23-051). Nothing previously asserted these: a regenerated export that
/// silently drifted in size or alpha would ship undetected until a store
/// upload rejected it.
///
/// This is a raw PNG `IHDR` chunk parse, not an image-decoding dependency:
/// `docs/41-code-standards.md` R-41-042 forbids a new dependency before the
/// reuse ladder is climbed, and the fixed 8-byte PNG signature followed by a
/// fixed-layout 13-byte `IHDR` chunk (width, height, bit depth, colour type)
/// needs none. The sRGB colour-space half of R-23-050 and the byte-for-byte
/// export-match half of R-23-053 are not encoded in the `IHDR` chunk, so
/// they stay unverified here (same gap noted for R-23-052).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Width, height and PNG colour type (0/2/3/4/6 per the PNG spec's `IHDR`
/// chunk) decoded from a file's first 33 bytes: the 8-byte signature plus
/// the fixed-layout `IHDR` chunk (4-byte length, 4-byte type, 13-byte body).
class _PngHeader {
  _PngHeader(this.width, this.height, this.colorType);

  factory _PngHeader.read(String path) {
    final Uint8List bytes = File(path).readAsBytesSync().sublist(0, 33);
    const List<int> signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
    expect(bytes.sublist(0, 8), signature, reason: '$path is not a PNG file');
    final ByteData data = ByteData.sublistView(bytes);
    final String chunkType = String.fromCharCodes(bytes.sublist(12, 16));
    expect(
      chunkType,
      'IHDR',
      reason: '$path does not start with an IHDR chunk',
    );
    return _PngHeader(data.getUint32(16), data.getUint32(20), bytes[25]);
  }

  final int width;
  final int height;

  /// PNG colour type: 0 grayscale, 2 truecolour (RGB, no alpha), 3 indexed,
  /// 4 grayscale+alpha, 6 truecolour+alpha (RGBA).
  final int colorType;

  bool get hasAlpha => colorType == 4 || colorType == 6;
}

void main() {
  group('store icon PNG headers', () {
    const String iosIcon =
        '../assets/icon/export/ios/AppIcon.appiconset/Icon-1024.png';
    const String playIcon = '../assets/icon/export/store/play-store-512.png';

    test('Icon-1024.png is 1024x1024 (R-23-050)', () {
      final _PngHeader header = _PngHeader.read(iosIcon);
      expect(header.width, 1024);
      expect(header.height, 1024);
    });

    test('Icon-1024.png carries no alpha channel (R-23-050, R-23-053)', () {
      final _PngHeader header = _PngHeader.read(iosIcon);
      expect(
        header.hasAlpha,
        isFalse,
        reason: 'Apple applies its own mask and rejects an icon with an alpha channel',
      );
    });

    test('play-store-512.png is 512x512 with an alpha channel (R-23-051)', () {
      final _PngHeader header = _PngHeader.read(playIcon);
      expect(header.width, 512);
      expect(header.height, 512);
      expect(header.hasAlpha, isTrue);
    });
  });
}
