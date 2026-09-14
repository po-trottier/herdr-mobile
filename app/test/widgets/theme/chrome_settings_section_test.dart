/// Proves `ChromeSettingsSection`
/// (`app/lib/widgets/theme/chrome_settings_section.dart`) composes the settings-list widget
/// R-33-073 names for each platform: `CupertinoListSection.insetGrouped` on iOS, a plain
/// column with a caption header on Android. Each case asserts the platform-specific
/// composing widget is present, so a deleted or broken `_isIos` branch fails it. On iOS the
/// header sits above the section and the separators take the row's `space.4` inset, per
/// R-33-073.1 (added 2026-09-08). The section paints nothing of its own (R-03-107, amended
/// 2026-09-09): no paper block, and the `space.6` gap above it stays.
library;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoListSection;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart' show ColoredBox, Widget;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/widgets/app_section_header.dart'
    show AppSectionHeader;
import 'package:herdr_mobile/widgets/theme/app_space.dart';
import 'package:herdr_mobile/widgets/theme/chrome_settings_section.dart';
import 'package:material_ui/material_ui.dart' show MaterialApp, Scaffold, Text;

void main() {
  testWidgets('iOS: CupertinoListSection.insetGrouped carries every row under the shared header, its '
      'separators on the row inset, per R-33-073.1', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChromeSettingsSection(
            header: 'APPEARANCE',
            rows: <Widget>[Text('Theme'), Text('Terminal text size')],
          ),
        ),
      ),
    );
    await tester.pump();

    final CupertinoListSection section = tester.widget(
      find.byType(CupertinoListSection),
    );
    expect(
      section.header,
      isNull,
      reason: 'the header is R-32-563\'s tier, above the card',
    );
    expect(section.dividerMargin, AppSpace.space4);
    expect(section.additionalDividerMargin, 0);
    expect(find.text('APPEARANCE'), findsOneWidget);
    // Card margin plus the row's own inset: the header starts on the row text's edge.
    expect(tester.getTopLeft(find.text('APPEARANCE')).dx, AppSpace.space4 * 2);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Terminal text size'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'iOS: a null header omits the section header text, not a fallback label',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChromeSettingsSection(rows: <Widget>[Text('Row')]),
          ),
        ),
      );
      await tester.pump();

      final CupertinoListSection section = tester.widget(
        find.byType(CupertinoListSection),
      );
      expect(section.header, isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'Android: no CupertinoListSection is built, and the header renders as plain text',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChromeSettingsSection(
              header: 'APPEARANCE',
              rows: <Widget>[Text('Theme'), Text('Terminal text size')],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CupertinoListSection), findsNothing);
      expect(find.text('APPEARANCE'), findsOneWidget);
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Terminal text size'), findsOneWidget);
    },
  );

  testWidgets('the section paints no paper of its own and keeps the space.6 gap above its header '
      '(R-03-107, amended 2026-09-09)', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChromeSettingsSection(
            header: 'APPEARANCE',
            rows: <Widget>[Text('Theme')],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(ChromeSettingsSection),
        matching: find.byType(ColoredBox),
      ),
      findsNothing,
    );
    expect(
      tester.getTopLeft(find.byType(AppSectionHeader)).dy -
          tester.getTopLeft(find.byType(ChromeSettingsSection)).dy,
      AppSpace.space6,
    );
  });
}
