/// `GroundGrid`, `docs/32-design-language.md` R-32-332: the ground is
/// `color.bg.base`, and a 1 px line in `color.bg.grid` sits on every 40 px
/// pitch in both directions, starting at the widget's top-left corner.
library;

import 'dart:typed_data' show ByteData;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/widgets.dart'
    show Brightness, MediaQuery, MediaQueryData, RepaintBoundary, SizedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/widgets/ground_grid.dart';
import 'package:herdr_mobile/widgets/theme/app_color.dart';

void main() {
  for (final Brightness brightness in Brightness.values) {
    testWidgets('paints the ground and the 40 px grid in $brightness', (
      tester,
    ) async {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(platformBrightness: brightness),
          child: const GroundGrid(child: SizedBox(width: 100, height: 100)),
        ),
      );
      final RenderRepaintBoundary boundary = tester.renderObject(
        find.byType(RepaintBoundary),
      );
      final ui.Image image =
          await tester.runAsync(() => boundary.toImage()) as ui.Image;
      final ByteData? bytes = await tester.runAsync<ByteData?>(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      int pixel(int x, int y) {
        final int o = (y * image.width + x) * 4;
        return (0xFF << 24) |
            (bytes!.getUint8(o) << 16) |
            (bytes.getUint8(o + 1) << 8) |
            bytes.getUint8(o + 2);
      }

      final AppColor color = AppColor.resolve(brightness);
      expect(pixel(20, 20), color.bgBase.toARGB32(), reason: 'the ground');
      expect(pixel(40, 20), color.bgGrid.toARGB32(), reason: 'a vertical line');
      expect(
        pixel(20, 80),
        color.bgGrid.toARGB32(),
        reason: 'a horizontal line',
      );
      expect(pixel(41, 21), color.bgBase.toARGB32(), reason: 'lines are 1 px');
    });
  }
}
