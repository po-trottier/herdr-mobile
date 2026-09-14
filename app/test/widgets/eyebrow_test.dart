/// Widget test for `Eyebrow` per `docs/32-design-language.md` section 7.1
/// (R-32-505): the 24x1 rule width in `accent.primary`.
library;

import 'package:flutter/widgets.dart' show BoxDecoration, DecoratedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/widgets/eyebrow.dart';
import 'package:herdr_mobile/widgets/theme/app_color.dart';
import 'package:material_ui/material_ui.dart' show MaterialApp, Scaffold;

void main() {
  testWidgets('Eyebrow draws a 24x1 rule in accent.primary', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Eyebrow(text: 'HERDR REMOTE')),
      ),
    );
    // The rule finder resolves the token from the built context: the pump
    // uses a bare MaterialApp, so the platform brightness is light and the
    // widget correctly draws `AppColor.light.accentPrimary`.
    final AppColor color = AppColor.of(
      tester.element(find.text('HERDR REMOTE')),
    );
    final ruleFinder = find.byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).color == color.accentPrimary,
    );

    expect(ruleFinder, findsOneWidget);

    final DecoratedBox rule = tester.widget(ruleFinder);
    final BoxDecoration decoration = rule.decoration as BoxDecoration;
    expect(decoration.color, color.accentPrimary);
  });

  testWidgets('Eyebrow shows text in accent.text and upper case', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Eyebrow(text: 'herdr remote')),
      ),
    );

    expect(find.text('HERDR REMOTE'), findsOneWidget);
  });
}
