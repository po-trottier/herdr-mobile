/// Widget tests for the four `treat.*` compositions of
/// `docs/32-design-language.md` section 7.2 (R-32-506), whose icon,
/// label and `border.attention` bar plumbing is otherwise unexercised
/// by any pumped widget (R-30-141).
library;

import 'package:flutter/widgets.dart'
    show Border, BoxDecoration, Brightness, DecoratedBox, Icon, Key;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/widgets/theme/app_color.dart';
import 'package:herdr_mobile/widgets/theme/app_size.dart';
import 'package:herdr_mobile/widgets/treatments.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart' show MaterialApp, Scaffold;

void main() {
  final AppColor color = AppColor.resolve(Brightness.light);

  Finder iconUnder(Key key) =>
      find.descendant(of: find.byKey(key), matching: find.byType(Icon));

  Finder attentionBarUnder(Key key) =>
      find.descendant(of: find.byKey(key), matching: find.byType(DecoratedBox));

  testWidgets('Treatment.ok renders its icon and label, no bar (R-30-141, '
      'R-32-506)', (WidgetTester tester) async {
    const Key key = Key('treatment');
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Treatment.ok(key: key, label: 'Connected'),
        ),
      ),
    );

    expect(find.text('Connected'), findsOneWidget);
    final Icon icon = tester.widget<Icon>(iconUnder(key));
    expect(icon.icon, Symbols.check_circle_rounded);
    expect(icon.color, color.statusOk);
    expect(icon.size, AppSize.iconSm);
    expect(attentionBarUnder(key), findsNothing);
  });

  testWidgets('Treatment.warning renders its icon and label, no bar '
      '(R-30-141, R-32-506)', (WidgetTester tester) async {
    const Key key = Key('treatment');
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Treatment.warning(key: key, label: 'Expiring soon'),
        ),
      ),
    );

    expect(find.text('Expiring soon'), findsOneWidget);
    final Icon icon = tester.widget<Icon>(iconUnder(key));
    expect(icon.icon, Symbols.warning_rounded);
    expect(icon.color, color.statusWarning);
    expect(icon.size, AppSize.iconSm);
    expect(attentionBarUnder(key), findsNothing);
  });

  testWidgets('Treatment.error outside a strip renders its icon and label, '
      'no bar (R-30-141, R-32-506)', (WidgetTester tester) async {
    const Key key = Key('treatment');
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Treatment.error(key: key, label: 'Request failed'),
        ),
      ),
    );

    expect(find.text('Request failed'), findsOneWidget);
    final Icon icon = tester.widget<Icon>(iconUnder(key));
    expect(icon.icon, Symbols.error_rounded);
    expect(icon.color, color.statusError);
    expect(icon.size, AppSize.iconSm);
    expect(attentionBarUnder(key), findsNothing);
  });

  testWidgets('Treatment.error in a strip adds the leading '
      'border.attention bar (R-32-506)', (WidgetTester tester) async {
    const Key key = Key('treatment');
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Treatment.error(
            key: key,
            label: 'Relay unreachable',
            inStrip: true,
          ),
        ),
      ),
    );

    expect(find.text('Relay unreachable'), findsOneWidget);
    final DecoratedBox bar = tester.widget<DecoratedBox>(
      attentionBarUnder(key),
    );
    final BoxDecoration decoration = bar.decoration as BoxDecoration;
    expect((decoration.border! as Border).left.color, color.statusError);
  });

  testWidgets('Treatment.destructive renders its icon and label, no bar '
      '(R-30-141, R-32-527, R-03-058)', (WidgetTester tester) async {
    const Key key = Key('treatment');
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Treatment.destructive(key: key, label: 'Forget'),
        ),
      ),
    );

    expect(find.text('Forget'), findsOneWidget);
    final Icon icon = tester.widget<Icon>(iconUnder(key));
    expect(icon.icon, Symbols.delete_outline_rounded);
    expect(icon.color, color.statusError);
    expect(icon.size, AppSize.iconMd);
    expect(attentionBarUnder(key), findsNothing);
  });
}
