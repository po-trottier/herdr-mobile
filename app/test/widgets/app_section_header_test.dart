import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoButton, CupertinoListTile;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/widgets/app_section_header.dart';
import 'package:herdr_mobile/widgets/theme/app_size.dart';
import 'package:herdr_mobile/widgets/theme/app_space.dart';
import 'package:material_ui/material_ui.dart'
    show IconButton, ListTile, Scaffold;

import '../screens/golden_support.dart';

void main() {
  for (final platform in <TargetPlatform>[
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'header ${platform.name} ${brightness.name} toggles and aligns its count',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          await loadAppFonts();
          tester.view.physicalSize = goldenReferenceSize;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var expanded = false;
          await tester.pumpWidget(
            goldenApp(
              brightness: brightness,
              child: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) => AppSectionHeader.tier1(
                    label: 'Workspace',
                    expanded: expanded,
                    count: '3 panes',
                    onToggle: () => setState(() => expanded = !expanded),
                  ),
                ),
              ),
            ),
          );
          final rowType = platform == TargetPlatform.iOS
              ? CupertinoListTile
              : ListTile;
          final buttonType = platform == TargetPlatform.iOS
              ? CupertinoButton
              : IconButton;
          expect(find.byType(rowType), findsOneWidget);
          expect(find.byType(buttonType), findsOneWidget);
          expect(
            tester.getSize(find.byType(rowType)).height,
            greaterThanOrEqualTo(AppSize.targetMin),
          );
          expect(
            tester.getCenter(find.text('Workspace')).dy,
            closeTo(tester.getCenter(find.byType(rowType)).dy, 0.5),
          );
          expect(
            tester.getTopRight(find.text('3 panes')).dx,
            closeTo(goldenReferenceSize.width - AppSpace.space4, 0.5),
          );
          await tester.tap(find.text('Workspace'));
          await tester.pumpAndSettle();
          expect(expanded, isTrue);
          await tester.tap(find.byType(buttonType));
          await tester.pumpAndSettle();
          expect(expanded, isFalse);
          await expectLater(
            find.byType(AppSectionHeader),
            matchesGoldenFile(
              'goldens/app_section_header_${platform.name}_${brightness.name}.png',
            ),
          );
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }
  }
}
