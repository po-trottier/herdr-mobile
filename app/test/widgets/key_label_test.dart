/// Widget tests for the inline key of `docs/32-design-language.md` section
/// 7.33 (R-32-599, per R-03-103): a `{key}` span in a `keyedText` template
/// draws one `InlineKey`, the prose keeps its style, and a screen reader
/// gets the plain sentence.
library;

import 'package:flutter/widgets.dart'
    show
        Brightness,
        DecoratedBox,
        BoxDecoration,
        RichText,
        Text,
        TextSpan,
        TextStyle;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/widgets/key_label.dart';
import 'package:herdr_mobile/widgets/theme/app_color.dart';
import 'package:herdr_mobile/widgets/theme/app_type.dart';
import 'package:material_ui/material_ui.dart' show MaterialApp, Scaffold;

void main() {
  final AppColor color = AppColor.resolve(Brightness.light);
  final TextStyle prose = AppType.caption.copyWith(color: color.fgSecondary);

  testWidgets('one InlineKey per {key}, prose in its own style, spoken plain', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: keyedText(
            'Press {ctrl+c} to stop, then the {r} key.',
            style: prose,
            color: color,
          ),
        ),
      ),
    );

    expect(find.byType(InlineKey), findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byType(InlineKey),
        matching: find.text('ctrl+c'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(InlineKey), matching: find.text('r')),
      findsOneWidget,
    );

    final RichText rich = tester.widget<RichText>(
      find
          .descendant(of: find.byType(Text), matching: find.byType(RichText))
          .first,
    );
    final TextSpan outer = rich.text as TextSpan;
    expect((outer.children!.single as TextSpan).style, prose);

    final Text cap = tester.widget<Text>(
      find.descendant(of: find.byType(InlineKey), matching: find.text('r')),
    );
    expect(cap.style, AppType.monoKey.copyWith(color: color.fgPrimary));
    final DecoratedBox box = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(InlineKey),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect((box.decoration as BoxDecoration).color, color.bgHigh);

    expect(
      find.bySemanticsLabel('Press Control C to stop, then the r key.'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Control C'), findsNothing);
  });

  testWidgets('a template with no key is one plain text run', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: keyedText('No key here.', style: prose, color: color),
        ),
      ),
    );

    expect(find.byType(InlineKey), findsNothing);
    expect(find.text('No key here.', findRichText: true), findsOneWidget);
  });

  test(
    'keyedPlain speaks a modifier by name and a chord letter upper case',
    () {
      expect(keyedPlain('the {r} key'), 'the r key');
      expect(keyedPlain('{ctrl+c} and {esc}'), 'Control C and Escape');
      expect(InlineKey.spoken('alt'), 'Alt');
    },
  );
}
