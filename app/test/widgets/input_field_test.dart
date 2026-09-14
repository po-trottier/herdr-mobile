/// Widget tests closing rule-test-map gaps for `input_field.dart`, the hardened field behind
/// the pane rename sheet and the settings fields (the key row's own field went with
/// R-03-054, 2026-09-09).
///
/// - R-30-807: `enabled` is a pure pass-through onto the underlying
///   `CupertinoTextField` — this file derives no permission logic of its
///   own, and a disabled field truly ignores pointer input.
/// - R-32-112: the field's `bgHigh` fill always carries a `borderStrong`
///   boundary (see also `key_row.dart`'s key caps, tested separately).
library;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoTextField;
import 'package:flutter/widgets.dart'
    show Border, Brightness, FocusNode, TextEditingController;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/widgets/input_field.dart';
import 'package:herdr_mobile/widgets/theme/app_color.dart';
import 'package:material_ui/material_ui.dart' show MaterialApp, Scaffold;

void main() {
  group('InputField.enabled (R-30-807)', () {
    testWidgets(
      'false forwards to CupertinoTextField.enabled and ignores taps',
      (WidgetTester tester) async {
        final controller = TextEditingController();
        final focusNode = FocusNode();
        addTearDown(() {
          controller.dispose();
          focusNode.dispose();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InputField(
                controller: controller,
                focusNode: focusNode,
                placeholder: 'Pane name',
                enabled: false,
              ),
            ),
          ),
        );

        final field = tester.widget<CupertinoTextField>(
          find.byType(CupertinoTextField),
        );
        expect(field.enabled, isFalse);

        await tester.tap(find.byType(CupertinoTextField), warnIfMissed: false);
        await tester.pump();
        expect(focusNode.hasFocus, isFalse);
      },
    );

    testWidgets(
      'true (the default) forwards to CupertinoTextField.enabled and accepts taps',
      (WidgetTester tester) async {
        final controller = TextEditingController();
        final focusNode = FocusNode();
        addTearDown(() {
          controller.dispose();
          focusNode.dispose();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InputField(
                controller: controller,
                focusNode: focusNode,
                placeholder: 'Pane name',
              ),
            ),
          ),
        );

        final field = tester.widget<CupertinoTextField>(
          find.byType(CupertinoTextField),
        );
        expect(field.enabled, isTrue);

        await tester.tap(find.byType(CupertinoTextField));
        await tester.pump();
        expect(focusNode.hasFocus, isTrue);
      },
    );
  });

  testWidgets(
    'InputField pairs its bgHigh fill with a borderStrong boundary (R-32-112)',
    (WidgetTester tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(() {
        controller.dispose();
        focusNode.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InputField(
              controller: controller,
              focusNode: focusNode,
              placeholder: 'Pane name',
            ),
          ),
        ),
      );
      await tester.pump();

      final field = tester.widget<CupertinoTextField>(
        find.byType(CupertinoTextField),
      );
      final decoration = field.decoration!;
      expect(decoration.color, AppColor.dark.bgHigh);
      expect(decoration.border, Border.all(color: AppColor.dark.borderStrong));
    },
  );
}
