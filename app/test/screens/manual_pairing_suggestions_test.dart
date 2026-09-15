import 'dart:io' show File;

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoButton, CupertinoButtonSize, CupertinoTextField;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/screens/manual_pairing_screen.dart';
import 'package:herdr_mobile/services/pairing.dart' show autocompleteWords;
import 'package:herdr_mobile/widgets/theme/chrome_suggestion_chip.dart';
import 'package:material_ui/material_ui.dart' show ActionChip;

import 'golden_support.dart';

void main() {
  final words = File('assets/wordlists/eff_large_wordlist.txt')
      .readAsLinesSync()
      .where((line) => line.isNotEmpty)
      .toList();
  setUpAll(loadAppFonts);

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final brightness in Brightness.values) {
      testWidgets('suggestions ${platform.name} ${brightness.name}', (
        tester,
      ) async {
        tester.view.physicalSize = goldenReferenceSize;
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.reset);
        debugDefaultTargetPlatformOverride = platform;
        try {
          await tester.pumpWidget(
            goldenApp(
              brightness: brightness,
              child: ManualPairingScreen(effWords: words),
            ),
          );
          await tester.pumpAndSettle();
          final fields = find.byType(CupertinoTextField);
          await tester.enterText(fields.at(2), 'ab');
          await tester.pumpAndSettle();

          final chips = find.byType(ChromeSuggestionChip);
          expect(chips, findsNWidgets(6));
          final controls = find.descendant(
            of: chips,
            matching: find.byType(
              platform == TargetPlatform.iOS ? CupertinoButton : ActionChip,
            ),
          );
          expect(controls, findsNWidgets(6));
          if (platform == TargetPlatform.iOS) {
            for (final button in tester.widgetList<CupertinoButton>(controls)) {
              expect(button.sizeStyle, CupertinoButtonSize.small);
            }
          }
          final scroll = find.ancestor(
            of: chips.first,
            matching: find.byType(SingleChildScrollView),
          );
          expect(
            tester.widget<SingleChildScrollView>(scroll).scrollDirection,
            Axis.horizontal,
          );
          expect(tester.getRect(scroll).bottom, lessThanOrEqualTo(667 - 300));
          await expectLater(
            find.byType(ManualPairingScreen),
            matchesGoldenFile(
              'goldens/manual_pairing_suggestions_${platform.name}_${brightness.name}.png',
            ),
          );

          await tester.drag(scroll, const Offset(-1000, 0));
          await tester.pumpAndSettle();
          final lastWord = autocompleteWords('ab', words).last;
          await tester.tap(
            find.descendant(of: chips.last, matching: find.text(lastWord)),
          );
          await tester.pumpAndSettle();
          expect(
            tester.widget<CupertinoTextField>(fields.at(2)).controller!.text,
            lastWord,
          );
          expect(
            tester.widget<CupertinoTextField>(fields.at(3)).focusNode!.hasFocus,
            isTrue,
          );
          expect(chips, findsNothing);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }
}
