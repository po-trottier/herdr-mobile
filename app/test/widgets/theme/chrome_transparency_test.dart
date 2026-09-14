/// Proves `ChromeTransparency.isReduceTransparencyEnabled`
/// (`app/lib/widgets/theme/chrome_transparency.dart`), per R-33-051: Android has no equivalent
/// setting and returns `false` with no channel call, and iOS reads
/// `UIAccessibility.isReduceTransparencyEnabled` over the `chrome_reduce_transparency` channel.
/// A test that only checked the Android short-circuit would still pass with the iOS branch
/// deleted, so this file drives both.
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/widgets/theme/chrome_transparency.dart';

const MethodChannel _channel = MethodChannel(
  'herdr_mobile/chrome_reduce_transparency',
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
  });

  test('Android: returns false with no channel call, per R-33-051', () async {
    var invoked = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
      MethodCall call,
    ) async {
      invoked = true;
      return true;
    });

    final bool result = await ChromeTransparency.isReduceTransparencyEnabled();

    expect(result, isFalse);
    expect(
      invoked,
      isFalse,
      reason: 'Android has no equivalent setting and needs none, per R-33-051',
    );
  });

  test(
    'iOS: reads UIAccessibility.isReduceTransparencyEnabled over the channel',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      MethodCall? received;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
        MethodCall call,
      ) async {
        received = call;
        return true;
      });

      final bool result =
          await ChromeTransparency.isReduceTransparencyEnabled();

      expect(result, isTrue);
      expect(received?.method, 'isReduceTransparencyEnabled');
      debugDefaultTargetPlatformOverride = null;
    },
  );

  test('iOS: a null platform response falls back to false', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
      MethodCall call,
    ) async {
      return null;
    });

    final bool result = await ChromeTransparency.isReduceTransparencyEnabled();

    expect(result, isFalse);
    debugDefaultTargetPlatformOverride = null;
  });

  group('shouldUseOpaqueVariant (R-33-068)', () {
    test('true when Reduce Transparency is on', () {
      expect(
        ChromeTransparency.shouldUseOpaqueVariant(
          reduceTransparency: true,
          increaseContrast: false,
        ),
        isTrue,
      );
    });

    test('true when Increase Contrast is on', () {
      expect(
        ChromeTransparency.shouldUseOpaqueVariant(
          reduceTransparency: false,
          increaseContrast: true,
        ),
        isTrue,
      );
    });

    test('false when neither is on', () {
      expect(
        ChromeTransparency.shouldUseOpaqueVariant(
          reduceTransparency: false,
          increaseContrast: false,
        ),
        isFalse,
      );
    });
  });
}
