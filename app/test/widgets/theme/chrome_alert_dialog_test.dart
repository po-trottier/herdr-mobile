/// Proves `showChromeAlertDialog` and `ChromeDialogHandle`
/// (`app/lib/widgets/theme/chrome_confirmation_dialog.dart`) give the alert of R-03-119 the
/// platform dialog R-33-074 names: the Material `AlertDialog` on Android with the default action
/// trailing, the `CupertinoAlertDialog` on iOS with `isDefaultAction` on the default and nothing
/// destructive; the body in `type.body` and the detail in `type.mono.code`; no barrier tap and no
/// back gesture closes it; and `dismiss` closes exactly this dialog, even under a route pushed
/// above it, or before its first frame.
library;

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoAlertDialog, CupertinoDialogAction;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart'
    show BuildContext, Builder, Navigator, Offset, Text;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/widgets/theme/app_color.dart';
import 'package:herdr_mobile/widgets/theme/app_type.dart';
import 'package:herdr_mobile/widgets/theme/chrome_confirmation_dialog.dart';
import 'package:material_ui/material_ui.dart'
    show
        AlertDialog,
        ElevatedButton,
        MaterialApp,
        MaterialPageRoute,
        Scaffold,
        TextButton;

enum _Way { back, tryAgain }

/// Pumps a screen with one `open` button that shows a two-action alert, taps
/// it, and lands the dialog. [detail] and [body] shape the content.
Future<ChromeDialogHandle<_Way>> _open(
  WidgetTester tester, {
  String? body = 'Update Herdr on patrick-desk, or update this app.',
  String? detail,
}) async {
  late ChromeDialogHandle<_Way> handle;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => ElevatedButton(
            onPressed: () {
              handle = showChromeAlertDialog<_Way>(
                context: context,
                title: 'Could not read this pane.',
                body: body,
                detail: detail,
                defaultAction: (label: 'Try again', result: _Way.tryAgain),
                otherAction: (label: 'Back', result: _Way.back),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return handle;
}

void main() {
  testWidgets(
    'Android: the Material AlertDialog, `Back` then `Try again` (the default, trailing), the '
    'body in type.body and the detail in type.mono.code; the chosen action is the result',
    (tester) async {
      final handle = await _open(tester, detail: 'attach to pane w3:p1');
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(CupertinoAlertDialog), findsNothing);

      final labels = tester
          .widgetList<TextButton>(find.byType(TextButton))
          .map((TextButton b) => (b.child! as Text).data)
          .toList();
      expect(labels, <String>['Back', 'Try again']);

      final Text sentence = tester.widget(
        find.text('Update Herdr on patrick-desk, or update this app.'),
      );
      expect(
        (sentence.style ?? sentence.textSpan!.style)!.fontFamily,
        AppType.body.fontFamily,
      );
      final Text raw = tester.widget(find.text('attach to pane w3:p1'));
      expect(raw.style!.fontFamily, AppType.monoCode.fontFamily);
      expect(raw.style!.color, AppColor.light.fgSecondary);
      expect(
        tester.getTopLeft(find.text('attach to pane w3:p1')).dy,
        greaterThanOrEqualTo(
          tester
              .getBottomLeft(
                find.text('Update Herdr on patrick-desk, or update this app.'),
              )
              .dy,
        ),
        reason: 'the detail stacks under the body',
      );

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(await handle.result, _Way.tryAgain);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets('iOS: the CupertinoAlertDialog, `Back` leading and `Try again` marked isDefaultAction, '
      'nothing destructive (R-33-074.2)', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final handle = await _open(tester);
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    final actions = tester
        .widgetList<CupertinoDialogAction>(find.byType(CupertinoDialogAction))
        .toList();
    expect(actions.map((a) => (a.child as Text).data).toList(), <String>[
      'Back',
      'Try again',
    ]);
    expect(actions[0].isDefaultAction, isFalse);
    expect(actions[1].isDefaultAction, isTrue);
    expect(actions.any((a) => a.isDestructiveAction), isFalse);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(await handle.result, _Way.back);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'neither a barrier tap nor the back gesture closes it: the actions are the only way out',
    (tester) async {
      final handle = await _open(tester);
      var completed = false;
      // ignore: unawaited_futures
      handle.result.then((_) => completed = true);

      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(completed, isFalse);

      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(await handle.result, _Way.back);
    },
  );

  testWidgets(
    'dismiss closes exactly this dialog: a route pushed above it stays, and result is null',
    (tester) async {
      final handle = await _open(tester);
      final BuildContext context = tester.element(find.byType(AlertDialog));
      // ignore: unawaited_futures
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext _) => const Scaffold(body: Text('lock')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('lock'), findsOneWidget);

      handle.dismiss();
      await tester.pumpAndSettle();
      expect(await handle.result, isNull);
      expect(find.text('lock'), findsOneWidget, reason: 'only the dialog left');

      // Back from the pushed route lands on the screen, not on a stale dialog.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('lock'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('open'), findsOneWidget);
    },
  );

  testWidgets(
    'dismiss before the first frame closes the dialog once it is built',
    (tester) async {
      late ChromeDialogHandle<_Way> handle;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => ElevatedButton(
                onPressed: () {
                  handle = showChromeAlertDialog<_Way>(
                    context: context,
                    title: 'This pane closed.',
                    defaultAction: (label: 'Back to agents', result: _Way.back),
                  );
                  handle.dismiss();
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(await handle.result, isNull);
    },
  );
}
