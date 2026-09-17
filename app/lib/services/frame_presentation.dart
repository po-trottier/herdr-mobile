/// Frame presentation barrier for App Lock (WP-13-b).
library;

import 'dart:async';
import 'dart:ui' show FrameTiming;

import 'package:flutter/widgets.dart' show WidgetsBinding;

/// Waits for the next submitted frame to finish rasterizing. A post-frame callback
/// alone only proves submission; iOS can still be displaying the launch screen.
/// The frame number rejects batched reports for earlier bootstrap frames.
class RasterizedFrame {
  RasterizedFrame() {
    _binding.addTimingsCallback(_report);
    _binding.addPostFrameCallback((_) {
      if (!_done.isCompleted) {
        _frameNumber = _binding.platformDispatcher.frameData.frameNumber;
      }
    });
    _binding.scheduleFrame();
  }

  final WidgetsBinding _binding = WidgetsBinding.instance;
  final Completer<bool> _done = Completer<bool>();
  int? _frameNumber;

  /// False when the caller cancels because its page has gone away.
  Future<bool> get ready => _done.future;

  void _report(List<FrameTiming> timings) {
    final frame = _frameNumber;
    if (frame != null && timings.any((timing) => timing.frameNumber >= frame)) {
      _finish(true);
    }
  }

  void cancel() => _finish(false);

  void _finish(bool rendered) {
    if (_done.isCompleted) return;
    _binding.removeTimingsCallback(_report);
    _done.complete(rendered);
  }
}
