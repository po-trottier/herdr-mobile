/// Proves `showChromeComposeTask` (`app/lib/widgets/theme/chrome_compose_task.dart`) pushes
/// the platform surface R-33-075 names: a full-height `CupertinoSheetRoute` with two titled
/// buttons and no `x` glyph on iOS (R-33-075.1), a full-screen Material route with the close
/// control on Android (R-33-075.3). A test that only checked "some route opened" would still
/// pass with the iOS branch deleted; both cases assert the platform route type and the
/// header's own buttons.
library;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoButton;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart' show ModalRoute, ScrollController;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/widgets/theme/chrome_compose_task.dart';
import 'package:material_ui/material_ui.dart'
    show
        AppBar,
        Builder,
        ElevatedButton,
        IconButton,
        MaterialApp,
        MaterialPageRoute,
        Scaffold,
        Text;

void main() {
  testWidgets('iOS: a CupertinoSheetRoute with two titled buttons and no close-icon control, '
      'per R-33-075.1', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var confirmed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showChromeComposeTask<void>(
                context: context,
                cancelLabel: 'Cancel',
                confirmLabel: 'send',
                onConfirm: () => confirmed++,
                content: (sheetContext, ScrollController controller) =>
                    const Text('compose body'),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('compose body'), findsOneWidget);
    // R-32-212, R-32-213: the widget draws every action label in
    // `type.mono.button` upper case; the caller passes the written form.
    expect(find.text('CANCEL'), findsOneWidget);
    expect(find.text('SEND'), findsOneWidget);
    expect(
      find.byType(CupertinoButton),
      findsNWidgets(2),
      reason: 'exactly the two titled buttons, per R-33-075.1 -- no third, icon-only close control',
    );
    expect(find.byType(IconButton), findsNothing);
    expect(find.byType(AppBar), findsNothing);
    expect(
      ModalRoute.of(tester.element(find.text('compose body'))).runtimeType
          .toString(),
      'CupertinoSheetRoute<void>',
    );

    await tester.tap(find.text('SEND'));
    await tester.pump();
    expect(confirmed, 1);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'Android: a full-screen MaterialPageRoute with the Material close control, '
    'per R-33-075.3',
    (tester) async {
      var confirmed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showChromeComposeTask<void>(
                  context: context,
                  cancelLabel: 'Cancel',
                  confirmLabel: 'send',
                  onConfirm: () => confirmed++,
                  content: (sheetContext, ScrollController controller) =>
                      const Text('compose body'),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('compose body'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(IconButton), findsOneWidget);
      expect(find.text('SEND'), findsOneWidget);
      expect(find.byType(CupertinoButton), findsNothing);
      final ModalRoute<void>? route = ModalRoute.of<void>(
        tester.element(find.text('compose body')),
      );
      expect(route, isA<MaterialPageRoute<void>>());
      expect((route! as MaterialPageRoute<void>).fullscreenDialog, isTrue);

      await tester.tap(find.text('SEND'));
      await tester.pump();
      expect(confirmed, 1);
    },
  );
}
