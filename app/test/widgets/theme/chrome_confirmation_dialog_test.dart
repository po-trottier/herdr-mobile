/// Proves `showChromeConfirmationDialog`
/// (`app/lib/widgets/theme/chrome_confirmation_dialog.dart`) opens the platform dialog
/// R-33-074 names: `CupertinoAlertDialog` with a leading, non-default `Cancel` action on iOS
/// (R-33-074.2, R-33-074.3), the Material `AlertDialog` on Android, with [cancelLabel]
/// applying on Android only, per that widget's own doc comment. On both platforms the
/// destructive verb is `treat.destructive` and the safe action is `type.body.strong` in
/// `color.fg.primary`, per `docs/32-design-language.md` section 7.17 and R-32-527 (amended
/// 2026-09-08); one dark golden per platform records the result.
library;

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoAlertDialog, CupertinoDialogAction;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart'
    show Brightness, BuildContext, Builder, Icon, Text, Widget;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/widgets/theme/app_color.dart';
import 'package:herdr_mobile/widgets/theme/app_type.dart';
import 'package:herdr_mobile/widgets/theme/chrome_confirmation_dialog.dart';
import 'package:herdr_mobile/widgets/theme/chrome_confirmation_outcome.dart';
import 'package:herdr_mobile/widgets/treatments.dart';
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart'
    show AlertDialog, ElevatedButton, MaterialApp, Scaffold, TextButton;

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

/// The destructive verb carries `treat.destructive`: the `delete_outline`
/// glyph in `color.status.error` and the label in `color.fg.primary`, never
/// red text (R-32-527). The safe action is `type.body.strong` in
/// `color.fg.primary`.
void _expectRoles(WidgetTester tester, String cancelLabel) {
  final Finder treatment = find.byType(Treatment);
  expect(treatment, findsOneWidget);
  expect(
    find.descendant(of: treatment, matching: find.text('Forget')),
    findsOneWidget,
  );
  final Icon glyph = tester.widget(
    find.descendant(of: treatment, matching: find.byType(Icon)),
  );
  expect(glyph.icon, Symbols.delete_outline_rounded);
  expect(glyph.color, AppColor.light.statusError);
  // `Treatment` renders its label through `keyedText` (R-32-599), a
  // `Text.rich` whose style sits on the root span, not on the widget.
  final Text verb = tester.widget(
    find.descendant(of: treatment, matching: find.text('Forget')),
  );
  expect((verb.style ?? verb.textSpan!.style)!.color, AppColor.light.fgPrimary);

  final Text safe = tester.widget(find.text(cancelLabel));
  expect(safe.style!.fontWeight, AppType.bodyStrong.fontWeight);
  expect(safe.style!.color, AppColor.light.fgPrimary);
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('iOS: CupertinoAlertDialog with Cancel leading and the destructive action marked, '
      'per R-33-074.2/.3, each role in its 7.17 composition', (tester) async {
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
    _expectRoles(tester, 'Cancel');

    await tester.tap(find.text('Forget'));
    await tester.pumpAndSettle();
    expect(outcome(), ChromeConfirmationOutcome.destructive);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'Android: Material AlertDialog with the destructive action, roles placed by the '
    'component (R-33-074.4), each role in its 7.17 composition',
    (tester) async {
      final outcome = await _open(tester, cancelLabel: 'Not now');

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(CupertinoAlertDialog), findsNothing);
      expect(find.byType(TextButton), findsNWidgets(2));
      _expectRoles(tester, 'Not now');

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
    testWidgets(
      '$name dark golden: the destructive verb carries treat.destructive',
      (tester) async {
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
      },
    );
  }
}
