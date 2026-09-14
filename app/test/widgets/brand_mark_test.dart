/// Widget test for `BrandMark` per `docs/32-design-language.md` section 8
/// (R-32-580): tints the asset with the given color using srcIn blend mode.
library;

import 'package:flutter/widgets.dart'
    show AssetImage, BlendMode, BoxFit, Color, FilterQuality, Image;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/widgets/brand_mark.dart';
import 'package:material_ui/material_ui.dart' show MaterialApp, Scaffold;

void main() {
  testWidgets('BrandMark renders Image.asset with correct parameters', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: BrandMark(height: 96, color: Color(0xFF17171A))),
      ),
    );

    final imageFinder = find.byType(Image);
    expect(imageFinder, findsOneWidget);

    final Image image = tester.widget(imageFinder);
    expect(image.image, isA<AssetImage>());
    final AssetImage assetImage = image.image as AssetImage;
    expect(assetImage.assetName, 'assets/brand/ram.png');
    expect(image.height, 96);
    expect(image.color, const Color(0xFF17171A));
    expect(image.colorBlendMode, BlendMode.srcIn);
    expect(image.fit, BoxFit.contain);
    expect(image.filterQuality, FilterQuality.low);
    expect(image.excludeFromSemantics, true);
  });

  testWidgets('BrandMark works without color parameter', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BrandMark(height: 64))),
    );

    final imageFinder = find.byType(Image);
    expect(imageFinder, findsOneWidget);

    final Image image = tester.widget(imageFinder);
    expect(image.color, isNull);
  });
}
