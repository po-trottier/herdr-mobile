import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoActivityIndicator;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/widgets/theme/chrome_activity_indicator.dart';
import 'package:material_ui/material_ui.dart'
    show CircularProgressIndicator, MaterialApp, Scaffold;

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('$platform uses its native indicator at the requested size', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ChromeActivityIndicator(size: 32)),
        ),
      );
      expect(
        find.byType(CupertinoActivityIndicator),
        platform == TargetPlatform.iOS ? findsOneWidget : findsNothing,
      );
      expect(
        find.byType(CircularProgressIndicator),
        platform == TargetPlatform.android ? findsOneWidget : findsNothing,
      );
      expect(
        tester.getSize(find.byType(ChromeActivityIndicator)),
        const Size.square(32),
      );
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
