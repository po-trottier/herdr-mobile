/// `ChromeIconAction` (`app/lib/widgets/theme/chrome_icon_action.dart`) composes
/// the platform control the `App bar action` row of `docs/33-platform-chrome.md`
/// R-33-033 names: a Material `IconButton` with a tooltip on Android, and on
/// iOS a `CupertinoButton` at least `size.target.min` wide that fills the
/// bar's 44 (R-33-076). Both fire the action and speak its label.
library;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoButton;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/widgets/theme/app_size.dart';
import 'package:herdr_mobile/widgets/theme/chrome_icon_action.dart';
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart'
    show IconButton, MaterialApp, Scaffold, Tooltip;

void main() {
  testWidgets('Android: an IconButton with the label as its tooltip', (
    WidgetTester tester,
  ) async {
    int taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChromeIconAction(
            icon: Symbols.add_rounded,
            label: 'Pair a computer',
            onPressed: () => taps++,
          ),
        ),
      ),
    );
    expect(find.byType(IconButton), findsOneWidget);
    expect(find.byType(CupertinoButton), findsNothing);
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      'Pair a computer',
    );
    await tester.tap(find.byType(IconButton));
    expect(taps, 1);
  });

  testWidgets(
    'iOS: a CupertinoButton 48 wide filling the 44 bar, speaking its label',
    (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      int taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChromeIconAction(
              icon: Symbols.add_rounded,
              label: 'Pair a computer',
              onPressed: () => taps++,
            ),
          ),
        ),
      );
      expect(find.byType(IconButton), findsNothing);
      final Finder button = find.byType(CupertinoButton);
      expect(button, findsOneWidget);
      expect(
        tester.getSize(button),
        const Size(AppSize.targetMin, AppSize.appBarIos),
      );
      expect(find.bySemanticsLabel('Pair a computer'), findsOneWidget);
      await tester.tap(button);
      expect(taps, 1);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
