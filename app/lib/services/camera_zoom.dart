import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// The active camera range, in factors relative to its standard lens (R-22-088).
final class CameraZoomRange {
  CameraZoomRange._(this.min, this.max, this._wideZoom);

  static const _channel = MethodChannel('dev.herdr.herdr_mobile/camera_zoom');
  final double min;
  final double max;
  final double _wideZoom;
  double factorFromScale(double scale) {
    final factor = defaultTargetPlatform == TargetPlatform.iOS
        ? (1 + 4 * scale) / _wideZoom
        : 1 / (1 / min - scale * (1 / min - 1 / max));
    return factor.clamp(min, max);
  }

  late final List<double> presets = <double>{
    for (final factor in <double>[0.5, 1, 2, 5])
      if (factor >= min && factor <= max) factor,
    if (max < 5) max,
  }.toList()..sort();

  static Future<CameraZoomRange?> load() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getRange',
      );
      if (result == null) return null;
      final min = (result['minZoom'] as num?)?.toDouble();
      final max = (result['maxZoom'] as num?)?.toDouble();
      final wide = (result['wideZoom'] as num?)?.toDouble();
      if (min == null ||
          max == null ||
          wide == null ||
          !min.isFinite ||
          !max.isFinite ||
          !wide.isFinite ||
          min <= 0 ||
          max < min ||
          wide <= 0) {
        return null;
      }
      return CameraZoomRange._(min / wide, max / wide, wide);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> setFactor(
    MobileScannerController controller,
    double factor, {
    bool animated = false,
  }) async {
    final target = factor.clamp(min, max);
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _channel.invokeMethod<void>('setZoom', <String, Object>{
        'zoom': target * _wideZoom,
        'animated': animated,
      });
    } else {
      // CameraX interpolates the field of view, not the zoom ratio.
      final scale = min == max
          ? 0.0
          : (1 / min - 1 / target) / (1 / min - 1 / max);
      await controller.setZoomScale(scale.clamp(0.0, 1.0));
    }
  }
}
