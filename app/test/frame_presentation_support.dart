/// Engine-boundary fixtures for widget tests, which do not run a raster thread (WP-13-b).
library;

import 'dart:ui' show FrameTiming;

import 'package:flutter_test/flutter_test.dart';

void reportRaster(WidgetTester tester, {int? frameNumber}) {
  tester.binding.platformDispatcher.onReportTimings?.call([
    FrameTiming(
      vsyncStart: 1,
      buildStart: 2,
      buildFinish: 3,
      rasterStart: 4,
      rasterFinish: 5,
      rasterFinishWallTime: 6,
      frameNumber:
          frameNumber ??
          tester.binding.platformDispatcher.frameData.frameNumber,
    ),
  ]);
}

Future<void> pumpRasterized(WidgetTester tester) async {
  await tester.pumpAndSettle();
  reportRaster(tester);
  await tester.pumpAndSettle();
}
