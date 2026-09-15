import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoListTile;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/widgets/app_strip.dart';
import 'package:herdr_mobile/widgets/app_text_button.dart';
import 'package:herdr_mobile/widgets/theme/app_size.dart';
import 'package:herdr_mobile/widgets/theme/app_space.dart';
import 'package:herdr_mobile/widgets/theme/app_type.dart';
import 'package:material_ui/material_ui.dart' show ListTile, Scaffold;

import '../screens/golden_support.dart';

void main() {
  testWidgets(
    'non-tappable one-line strip uses caption height and strip padding',
    (tester) async {
      await loadAppFonts();
      for (final platform in <TargetPlatform>[
        TargetPlatform.android,
        TargetPlatform.iOS,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        await tester.pumpWidget(
          goldenApp(
            brightness: Brightness.light,
            child: const Scaffold(body: AppStrip(child: Text('Connected'))),
          ),
        );
        expect(
          tester.getSize(find.byType(AppStrip)).height,
          AppType.caption.fontSize! * AppType.caption.height! +
              2 * AppSpace.space3,
        );
      }
      debugDefaultTargetPlatformOverride = null;
    },
  );
  testWidgets('tappable one-line strip keeps the native minimum target', (
    tester,
  ) async {
    await loadAppFonts();
    for (final platform in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.iOS,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      var taps = 0;
      await tester.pumpWidget(
        goldenApp(
          brightness: Brightness.light,
          child: Scaffold(
            body: AppStrip(
              onTapDestination: () => taps++,
              child: const Text('Connected'),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(AppStrip)).height, AppSize.targetMin);
      await tester.tap(find.text('Connected'));
      expect(taps, 1);
    }
    debugDefaultTargetPlatformOverride = null;
  });
  for (final platform in <TargetPlatform>[
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'strip ${platform.name} ${brightness.name} separates destination and action',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          await loadAppFonts();
          tester.view.physicalSize = goldenReferenceSize;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var destinations = 0;
          var actions = 0;
          await tester.pumpWidget(
            goldenApp(
              brightness: brightness,
              child: Scaffold(
                body: AppStrip(
                  onTapDestination: () => destinations++,
                  trailing: AppTextButton(
                    label: 'Try again',
                    onPressed: () => actions++,
                  ),
                  child: const Text(
                    'No computer is connected. Choose one, or open Connection details.',
                  ),
                ),
              ),
            ),
          );
          expect(
            find.byType(
              platform == TargetPlatform.iOS ? CupertinoListTile : ListTile,
            ),
            findsOneWidget,
          );
          final text = find.text(
            'No computer is connected. Choose one, or open Connection details.',
          );
          expect(
            tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
            isFalse,
          );
          await tester.tap(text);
          await tester.pumpAndSettle();
          expect(destinations, 1);
          expect(actions, 0);
          await tester.tap(find.text('Try again'));
          await tester.pumpAndSettle();
          expect(destinations, 1);
          expect(actions, 1);
          await expectLater(
            find.byType(AppStrip),
            matchesGoldenFile(
              'goldens/app_strip_${platform.name}_${brightness.name}.png',
            ),
          );
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }
  }
}
