import 'dart:ui' show Tristate;

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoActivityIndicator, CupertinoButton;
import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/widgets/app_list_row.dart';
import 'package:herdr_mobile/widgets/status_bar.dart';
import 'package:herdr_mobile/widgets/theme/app_size.dart';
import 'package:herdr_mobile/widgets/theme/app_type.dart';
import 'package:material_ui/material_ui.dart'
    show CircularProgressIndicator, MaterialApp, Scaffold, TextButton;

import '../screens/golden_support.dart' show loadAppFonts;

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(body: RepaintBoundary(child: child)),
);

void main() {
  setUpAll(loadAppFonts);
  for (final TargetPlatform platform in <TargetPlatform>[
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    testWidgets('$platform: tap, disabled, loading and static semantics', (
      WidgetTester tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final SemanticsHandle handle = tester.ensureSemantics();

      int taps = 0;
      await tester.pumpWidget(
        _app(
          AppListRow(
            primary: 'Host',
            semanticsValue: 'Connected',
            selected: true,
            onTap: () => taps++,
          ),
        ),
      );
      final Finder label = find.bySemanticsLabel('Host, Connected');
      expect(label, findsOneWidget);
      expect(
        tester.getSemantics(label).flagsCollection.isSelected,
        Tristate.isTrue,
      );
      await tester.tap(find.text('Host'));
      expect(taps, 1);

      int menuTaps = 0;
      await tester.pumpWidget(
        _app(
          AppListRow(
            primary: 'Host',
            semanticsValue: 'Connected',
            preserveTrailingSemantics: true,
            trailing: platform == TargetPlatform.iOS
                ? CupertinoButton(
                    onPressed: () => menuTaps++,
                    child: const Text('Actions'),
                  )
                : TextButton(
                    onPressed: () => menuTaps++,
                    child: const Text('Actions'),
                  ),
            onTap: () => taps++,
          ),
        ),
      );
      expect(find.bySemanticsLabel('Host, Connected'), findsOneWidget);
      expect(find.bySemanticsLabel('Actions'), findsOneWidget);
      await tester.tap(find.text('Actions'));
      expect(menuTaps, 1);
      expect(taps, 1);
      await tester.pumpWidget(_app(const AppListRow(primary: 'Host')));
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Host'))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse,
      );
      await tester.tap(find.text('Host'));
      expect(taps, 1);

      await tester.pumpWidget(
        _app(
          AppListRow(
            primary: 'Host',
            secondary: 'Connected',
            isLoading: true,
            onTap: () => taps++,
          ),
        ),
      );
      expect(find.text('Host'), findsNothing);
      expect(find.text('Connected'), findsNothing);
      expect(
        find.byType(
          platform == TargetPlatform.iOS
              ? CupertinoActivityIndicator
              : CircularProgressIndicator,
        ),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byType(AppListRow)).height,
        AppSize.rowTwoLine,
      );
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Host'))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse,
      );
      await tester.tap(find.byType(AppListRow));
      expect(taps, 1);

      await tester.pumpWidget(
        _app(
          const AppListRow(
            primary: 'Protocol',
            semanticsValue: '22',
            isStatic: true,
          ),
        ),
      );
      final SemanticsNode staticNode = tester.getSemantics(
        find.bySemanticsLabel('Protocol, 22'),
      );
      expect(staticNode.flagsCollection.isEnabled, Tristate.none);
      handle.dispose();
      debugDefaultTargetPlatformOverride = null;
      expect(
        staticNode.getSemanticsData().hasAction(SemanticsAction.tap),
        isFalse,
      );
    });

    testWidgets('$platform: content and state keep their position', (
      WidgetTester tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.pumpWidget(_app(AppListRow(primary: 'Host', onTap: () {})));
      final double left = tester.getTopLeft(find.text('Host')).dx;
      expect(
        tester.getSize(find.byType(AppListRow)).height,
        AppSize.rowOneLine,
      );
      await tester.pumpWidget(
        _app(
          AppListRow(
            primary: 'Host',
            secondary: 'Connected',
            selected: true,
            state: BarState.working,
            trailing: const Text('Ready', style: AppType.caption),
            onTap: () {},
          ),
        ),
      );
      expect(tester.getTopLeft(find.text('Host')).dx, left);
      final Rect row = tester.getRect(find.byType(AppListRow));
      final Rect bar = tester.getRect(find.byType(StatusBar));
      expect(bar.left, row.left);
      expect(bar.top, row.top);
      expect(bar.bottom, row.bottom);
      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Ready'), findsOneWidget);
      await expectLater(
        find.byType(AppListRow),
        matchesGoldenFile('goldens/app_list_row_${platform.name}.png'),
      );

      await tester.pumpWidget(
        _app(
          const AppListRow(
            primary: 'Accessible name',
            primaryWidget: SizedBox(height: 64, child: Text('Custom title')),
            contentPadding: EdgeInsets.zero,
            isStatic: true,
          ),
        ),
      );
      expect(tester.getSize(find.byType(AppListRow)).height, 64);
      expect(tester.getTopLeft(find.text('Custom title')).dx, 0);
      await tester.pumpWidget(
        _app(
          const AppListRow(
            primary: 'Accessible name',
            primaryWidget: Text('Custom title'),
            secondary: 'Details',
            isStatic: true,
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(AppListRow)).height,
        AppSize.rowTwoLine,
      );
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
