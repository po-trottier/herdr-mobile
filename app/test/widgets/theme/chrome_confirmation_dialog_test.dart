/// Proves `showChromeConfirmationDialog`
/// (`app/lib/widgets/theme/chrome_confirmation_dialog.dart`) opens the platform dialog
/// R-33-074 names: `CupertinoAlertDialog` with a leading, non-default `Cancel` action on iOS
/// (R-33-074.2, R-33-074.3), the Material `AlertDialog` on Android, with [cancelLabel]
/// applying on Android only, per that widget's own doc comment. On both platforms the actions
/// are the component's own: plain labels with no glyph, the destructive one
/// `isDestructiveAction` on iOS and `color.status.error` on Android (R-33-074.6, amended
/// 2026-09-18); one dark golden per platform records the result.
library;

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoAlertDialog, CupertinoDialogAction;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart'
    show Brightness, BuildContext, Builder, Icon, Text, Widget;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/widgets/theme/app_color.dart';
import 'package:herdr_mobile/widgets/theme/chrome_confirmation_dialog.dart';
import 'package:herdr_mobile/widgets/theme/chrome_confirmation_outcome.dart';
import 'package:material_ui/material_ui.dart'
    show
        AlertDialog,
        Dialog,
        ElevatedButton,
        MaterialApp,
        Scaffold,
        TextButton,
        WidgetState;

import '../../screens/golden_support.dart';

/// Pumps a screen with one `open` button that shows the dialog and records
/// its outcome, then opens it.
Future<ChromeConfirmationOutcome? Function()> _open(
  WidgetTester tester, {
  String? cancelLabel,
  Brightness? golden,
}) async {
  ChromeConfirmationOutcome? outcome;
  final Widget home = Scaffold(
    body: Builder(
      builder: (BuildContext context) => ElevatedButton(
        onPressed: () async {
          outcome = await showChromeConfirmationDialog(
            context: context,
            title: 'Forget this computer?',
            body: 'You will need to pair again.',
            destructiveLabel: 'Forget',
            cancelLabel: cancelLabel ?? 'Cancel',
          );
        },
        child: const Text('open'),
      ),
    ),
  );
  await tester.pumpWidget(
    golden == null
        ? MaterialApp(home: home)
        : goldenApp(brightness: golden, child: home),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => outcome;
}

/// Both actions are plain labels: no glyph inside the dialog (R-33-074.6).
void _expectPlainActions(WidgetTester tester, String cancelLabel) {
  expect(find.text('Forget'), findsOneWidget);
  expect(find.text(cancelLabel), findsOneWidget);
  expect(
    find.descendant(
      of: find.byType(Dialog).evaluate().isEmpty
          ? find.byType(CupertinoAlertDialog)
          : find.byType(Dialog),
      matching: find.byType(Icon),
    ),
    findsNothing,
  );
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('iOS: CupertinoAlertDialog with Cancel leading and the destructive action marked, '
      'per R-33-074.2/.3, both actions plain labels', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final outcome = await _open(tester);

    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    final actions = tester
        .widgetList<CupertinoDialogAction>(find.byType(CupertinoDialogAction))
        .toList();
    expect(actions, hasLength(2));
    expect(
      (actions[0].child as Text).data,
      'Cancel',
      reason: 'Cancel MUST be leading, per R-33-074.2',
    );
    expect(actions[0].isDestructiveAction, isFalse);
    expect(actions[1].isDestructiveAction, isTrue);
    expect(
      actions.every((a) => !a.isDefaultAction),
      isTrue,
      reason: 'neither action is default while a destructive action is present, per R-33-074.3',
    );
    _expectPlainActions(tester, 'Cancel');

    await tester.tap(find.text('Forget'));
    await tester.pumpAndSettle();
    expect(outcome(), ChromeConfirmationOutcome.destructive);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'Android: Material AlertDialog with the destructive action, roles placed by the '
    'component (R-33-074.4), the destructive label in color.status.error',
    (tester) async {
      final outcome = await _open(tester, cancelLabel: 'Not now');

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(CupertinoAlertDialog), findsNothing);
      expect(find.byType(TextButton), findsNWidgets(2));
      _expectPlainActions(tester, 'Not now');
      final TextButton forget = tester.widget(
        find.widgetWithText(TextButton, 'Forget'),
      );
      expect(
        forget.style!.foregroundColor!.resolve(<WidgetState>{}),
        AppColor.light.statusError,
      );
      final TextButton notNow = tester.widget(
        find.widgetWithText(TextButton, 'Not now'),
      );
      expect(
        notNow.style,
        isNull,
        reason: 'the safe action is the theme\'s own',
      );

      await tester.tap(find.text('Forget'));
      await tester.pumpAndSettle();
      expect(outcome(), ChromeConfirmationOutcome.destructive);
    },
  );

  testWidgets('Android: cancelling reports ChromeConfirmationOutcome.cancel', (
    tester,
  ) async {
    final outcome = await _open(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(outcome(), ChromeConfirmationOutcome.cancel);
  });

  for (final (platform, name) in <(TargetPlatform, String)>[
    (TargetPlatform.android, 'android'),
    (TargetPlatform.iOS, 'ios'),
  ]) {
    testWidgets('$name dark golden: the platform dialog with plain actions', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      tester.view.physicalSize = goldenReferenceSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _open(tester, golden: Brightness.dark);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/chrome_confirmation_dialog_${name}_dark.png',
        ),
      );
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
