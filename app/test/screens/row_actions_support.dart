/// The one gesture every row-action test uses to open a row's actions
/// (`app/lib/widgets/theme/chrome_row_actions.dart`, R-30-296): a press held
/// past both platforms' thresholds. Material's `LongPressGestureRecognizer`
/// fires at 500 ms; `CupertinoContextMenu` opens its route after an 800 ms
/// press, so `WidgetTester.longPress`, which lifts at 600 ms, opens nothing on
/// iOS. The finger lifts only once the menu has settled, as a real one does.
library;

import 'package:flutter_test/flutter_test.dart';

Future<void> openRowActions(WidgetTester tester, Finder row) async {
  final TestGesture press = await tester.startGesture(tester.getCenter(row));
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
  await press.up();
  await tester.pumpAndSettle();
}
