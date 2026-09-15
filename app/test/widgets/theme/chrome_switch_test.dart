import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoSwitch;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart' show StatefulBuilder;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/widgets/theme/chrome_switch.dart';
import 'package:material_ui/material_ui.dart'
    show MaterialApp, Scaffold, Switch;

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('$platform uses its native switch and toggles', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      var value = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => ChromeSwitch(
                value: value,
                onChanged: (next) => setState(() => value = next),
              ),
            ),
          ),
        ),
      );
      expect(
        find.byType(CupertinoSwitch),
        platform == TargetPlatform.iOS ? findsOneWidget : findsNothing,
      );
      expect(
        find.byType(Switch),
        platform == TargetPlatform.android ? findsOneWidget : findsNothing,
      );
      await tester.tap(find.byType(ChromeSwitch));
      await tester.pumpAndSettle();
      expect(value, isTrue);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('$platform disables the switch without a callback', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ChromeSwitch(value: true, onChanged: null)),
        ),
      );
      expect(
        tester.getSemantics(find.byType(ChromeSwitch)),
        matchesSemantics(
          hasEnabledState: true,
          isEnabled: false,
          hasToggledState: true,
          isToggled: true,
        ),
      );
      semantics.dispose();
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
