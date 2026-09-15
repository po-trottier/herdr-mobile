import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/app.dart' show appThemeFrom;
import 'package:herdr_mobile/widgets/theme/app_space.dart';
import 'package:herdr_mobile/widgets/theme/chrome_scheme.dart';
import 'package:herdr_mobile/widgets/theme/chrome_snackbar.dart';
import 'package:material_ui/material_ui.dart'
    show MaterialApp, Scaffold, SnackBar, TextButton;

import '../../screens/golden_support.dart' show loadAppFonts;

Widget _app({bool accessibleNavigation = false, double bottomInset = 0}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: appThemeFrom(ChromeScheme.fixed(Brightness.dark)),
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          platformBrightness: Brightness.dark,
          accessibleNavigation: accessibleNavigation,
          padding: EdgeInsets.only(bottom: bottomInset),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showChromeSnackbar(context, 'Saved'),
            child: const Text('Show feedback'),
          ),
        ),
      ),
    );

void main() {
  setUpAll(loadAppFonts);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('Android uses SnackBar and removes it after its timeout', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(_app());
    await tester.tap(find.text('Show feedback'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/chrome_snackbar_android_dark.png'),
    );
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iOS uses the root overlay above the inset until its timeout', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(_app(bottomInset: 34));
    await tester.tap(find.text('Show feedback'));
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
    final Finder feedback = find
        .ancestor(of: find.text('Saved'), matching: find.byType(DecoratedBox))
        .first;
    expect(feedback, findsOneWidget);
    expect(
      find.descendant(of: find.byType(Overlay), matching: find.text('Saved')),
      findsOneWidget,
    );
    expect(
      tester.getBottomRight(feedback).dy,
      tester.view.physicalSize.height / tester.view.devicePixelRatio -
          34 -
          AppSpace.space4,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/chrome_snackbar_ios_dark.png'),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Saved'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Saved'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  for (final TargetPlatform platform in <TargetPlatform>[
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    testWidgets('$platform feedback does not time out with a screen reader', (
      WidgetTester tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(_app(accessibleNavigation: true));
      await tester.tap(find.text('Show feedback'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(days: 1));
      expect(find.text('Saved'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('iOS cancels the timeout when a screen reader starts', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(_app());
    await tester.tap(find.text('Show feedback'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(_app(accessibleNavigation: true));
    await tester.pump(const Duration(days: 1));
    expect(find.text('Saved'), findsOneWidget);
    await tester.drag(find.text('Saved'), const Offset(800, 0));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsOneWidget);
    final Semantics surface = tester.widget<Semantics>(
      find
          .ancestor(of: find.text('Saved'), matching: find.byType(Semantics))
          .first,
    );
    surface.properties.onDismiss!();
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
