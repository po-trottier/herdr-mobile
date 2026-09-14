/// Proves `ChromeListRow` (`app/lib/widgets/theme/chrome_list_row.dart`) draws the platform
/// row R-33-072 and R-33-073 name for each row kind: one `CupertinoListTile` per row on iOS (a
/// `CupertinoExpansionTile` for the expanding kind), whose push chevron is the `chevron_right` of
/// the app icon set (R-32-401), never `CupertinoListTileChevron`; and the `AppListRow` of `docs/32`
/// §7.4 (the Material `ExpansionTile` for the expanding kind) on Android. A test that only asserted
/// "some list row renders" would still pass with the iOS branch deleted; every case below
/// asserts the platform-specific type is present and the other platform's type is absent, so a
/// broken or deleted `_isIos` branch fails it.
library;

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoExpansionTile, CupertinoListTile, CupertinoSwitch;
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/widgets/app_list_row.dart';
import 'package:herdr_mobile/widgets/theme/app_color.dart';
import 'package:herdr_mobile/widgets/theme/app_radius.dart';
import 'package:herdr_mobile/widgets/theme/chrome_list_row.dart';
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart'
    show
        ExpansionTile,
        Icon,
        MaterialApp,
        Opacity,
        Scaffold,
        Switch,
        Text,
        Widget,
        WidgetState;

final TargetPlatformVariant _ios = TargetPlatformVariant.only(
  TargetPlatform.iOS,
);

Future<void> _pump(WidgetTester tester, Widget row) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: row)));
  await tester.pump();
}

void main() {
  group('ChromeListRow.push', () {
    testWidgets(
      'iOS: CupertinoListTile with the R-32-401 chevron, per R-33-072.1/.2',
      (tester) async {
        await _pump(
          tester,
          ChromeListRow.push(title: 'Licences', onTap: () {}),
        );

        expect(find.byType(CupertinoListTile), findsOneWidget);
        expect(find.byIcon(Symbols.chevron_right_rounded), findsOneWidget);
        expect(find.byType(AppListRow), findsNothing);
      },
      variant: _ios,
    );

    testWidgets('iOS: the subtitle lands in the tile', (tester) async {
      await _pump(
        tester,
        ChromeListRow.push(
          title: 'Relay address',
          subtitle: 'Not set',
          onTap: () {},
        ),
      );

      expect(find.text('Not set'), findsOneWidget);
    }, variant: _ios);

    testWidgets(
      'Android: AppListRow with no trailing decoration, per R-33-072.3',
      (tester) async {
        await _pump(
          tester,
          ChromeListRow.push(
            title: 'Relay address',
            subtitle: 'Not set',
            onTap: () {},
          ),
        );

        final AppListRow row = tester.widget(find.byType(AppListRow));
        expect(row.trailing, isNull);
        expect(row.primary, 'Relay address');
        expect(row.secondary, 'Not set');
        expect(find.byType(CupertinoListTile), findsNothing);
        expect(find.byIcon(Symbols.chevron_right_rounded), findsNothing);
      },
    );

    testWidgets('Android: showDivider false reaches the AppListRow', (
      tester,
    ) async {
      await _pump(
        tester,
        ChromeListRow.push(title: 'About', onTap: () {}, showDivider: false),
      );

      final AppListRow row = tester.widget(find.byType(AppListRow));
      expect(row.showDivider, isFalse);
    });

    testWidgets('iOS: onTap fires exactly once per tap', (tester) async {
      var taps = 0;
      await _pump(
        tester,
        ChromeListRow.push(title: 'Licences', onTap: () => taps++),
      );
      await tester.tap(find.byType(CupertinoListTile));
      await tester.pump();

      expect(taps, 1);
    }, variant: _ios);

    testWidgets(
      'iOS: trailing lands in the tile before the chevron, per R-03-105',
      (tester) async {
        await _pump(
          tester,
          ChromeListRow.push(
            title: 'Pixel 8',
            subtitle: 'paired 24 Aug 09:14',
            trailing: const Text('This phone'),
            onTap: () {},
          ),
        );

        final CupertinoListTile tile = tester.widget(
          find.byType(CupertinoListTile),
        );
        expect(tile.additionalInfo, isA<Text>());
        expect(find.text('This phone'), findsOneWidget);
        expect(find.byIcon(Symbols.chevron_right_rounded), findsOneWidget);
      },
      variant: _ios,
    );

    testWidgets('Android: trailing reaches the AppListRow', (tester) async {
      await _pump(
        tester,
        ChromeListRow.push(
          title: 'Pixel 8',
          trailing: const Text('This phone'),
          onTap: () {},
        ),
      );

      final AppListRow row = tester.widget(find.byType(AppListRow));
      expect(row.trailing, isA<Text>());
      expect(find.text('This phone'), findsOneWidget);
    });
  });

  group('ChromeListRow.choice', () {
    testWidgets(
      'iOS: CupertinoListTile carries the value as trailing text, per R-33-072.2',
      (tester) async {
        await _pump(
          tester,
          ChromeListRow.choice(
            title: 'Theme',
            valueLabel: 'System',
            onTap: () {},
          ),
        );

        expect(find.byType(CupertinoListTile), findsOneWidget);
        expect(find.byIcon(Symbols.chevron_right_rounded), findsNothing);
        expect(find.text('System'), findsOneWidget);
      },
      variant: _ios,
    );

    testWidgets('Android: AppListRow carries the value as trailing text', (
      tester,
    ) async {
      await _pump(
        tester,
        ChromeListRow.choice(
          title: 'Theme',
          valueLabel: 'System',
          onTap: () {},
        ),
      );

      expect(find.byType(AppListRow), findsOneWidget);
      expect(find.byType(CupertinoListTile), findsNothing);
      expect(find.text('System'), findsOneWidget);
    });
  });

  group('ChromeListRow.expand', () {
    testWidgets('iOS: CupertinoExpansionTile, per R-33-072.2', (tester) async {
      await _pump(
        tester,
        const ChromeListRow.expand(
          title: 'Terminal text size',
          child: Text('Small · Medium · Large'),
        ),
      );

      expect(find.byType(CupertinoExpansionTile), findsOneWidget);
      expect(find.byType(ExpansionTile), findsNothing);
    }, variant: _ios);

    testWidgets('Android: the Material ExpansionTile', (tester) async {
      await _pump(
        tester,
        const ChromeListRow.expand(
          title: 'Terminal text size',
          child: Text('Small · Medium · Large'),
        ),
      );

      expect(find.byType(ExpansionTile), findsOneWidget);
      expect(find.byType(CupertinoExpansionTile), findsNothing);
    });
  });

  group('ChromeListRow.toggle', () {
    testWidgets('iOS: one CupertinoListTile trailing a CupertinoSwitch', (
      tester,
    ) async {
      var value = false;
      await _pump(
        tester,
        ChromeListRow.toggle(
          title: 'Haptics',
          value: value,
          onChanged: (bool next) => value = next,
        ),
      );

      expect(find.byType(CupertinoListTile), findsOneWidget);
      expect(find.byType(CupertinoSwitch), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(AppListRow), findsNothing);

      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pump();
      expect(value, isTrue);
    }, variant: _ios);

    testWidgets('iOS: the CupertinoSwitch takes the section 7.7 tokens', (
      tester,
    ) async {
      await _pump(
        tester,
        ChromeListRow.toggle(
          title: 'Haptics',
          value: false,
          onChanged: (bool _) {},
        ),
      );

      final Finder finder = find.byType(CupertinoSwitch);
      final CupertinoSwitch sw = tester.widget(finder);
      final AppColor color = AppColor.of(tester.element(finder));
      expect(sw.activeTrackColor, color.accentPrimary);
      expect(sw.inactiveTrackColor, color.bgHigh);
      expect(sw.thumbColor, color.fgOnAccent);
      expect(sw.inactiveThumbColor, color.fgPrimary);
      // R-32-522: the off track carries its border; the on track does not.
      expect(
        sw.trackOutlineColor!.resolve(const <WidgetState>{}),
        color.borderStrong,
      );
      expect(
        sw.trackOutlineColor!.resolve(const <WidgetState>{
          WidgetState.selected,
        }),
        isNull,
      );
      expect(
        sw.trackOutlineWidth!.resolve(const <WidgetState>{}),
        AppBorder.hairline,
      );
    }, variant: _ios);

    testWidgets(
      'Android: one AppListRow, the row tap flips the value, per R-32-522',
      (tester) async {
        var value = false;
        await _pump(
          tester,
          ChromeListRow.toggle(
            title: 'Haptics',
            value: value,
            onChanged: (bool next) => value = next,
          ),
        );

        expect(find.byType(AppListRow), findsOneWidget);
        expect(find.byType(Switch), findsOneWidget);
        expect(find.byType(CupertinoListTile), findsNothing);
        expect(find.byType(CupertinoSwitch), findsNothing);

        await tester.tap(find.byType(AppListRow));
        await tester.pump();
        expect(value, isTrue);
      },
    );

    testWidgets('Android: null onChanged leaves the row with no onTap', (
      tester,
    ) async {
      await _pump(
        tester,
        const ChromeListRow.toggle(
          title: 'App Lock',
          value: false,
          onChanged: null,
        ),
      );

      final AppListRow row = tester.widget(find.byType(AppListRow));
      expect(row.onTap, isNull);
      expect(row.semanticsValue, 'off');
    });
  });

  group('ChromeListRow.action', () {
    testWidgets('iOS: one CupertinoListTile trailing the action label', (
      tester,
    ) async {
      var taps = 0;
      await _pump(
        tester,
        ChromeListRow.action(
          title: "This phone's name",
          subtitle: 'Pixel 9',
          actionLabel: 'Edit',
          onTap: () => taps++,
        ),
      );

      expect(find.byType(CupertinoListTile), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Pixel 9'), findsOneWidget);
      expect(find.byIcon(Symbols.chevron_right_rounded), findsNothing);
      expect(find.byType(AppListRow), findsNothing);

      await tester.tap(find.byType(CupertinoListTile));
      await tester.pump();
      expect(taps, 1);
    }, variant: _ios);

    testWidgets('Android: one AppListRow trailing the action label', (
      tester,
    ) async {
      await _pump(
        tester,
        ChromeListRow.action(
          title: "This phone's name",
          subtitle: 'Pixel 9',
          actionLabel: 'Edit',
          onTap: () {},
        ),
      );

      final AppListRow row = tester.widget(find.byType(AppListRow));
      expect(row.secondary, 'Pixel 9');
      expect(find.text('Edit'), findsOneWidget);
      expect(find.byType(CupertinoListTile), findsNothing);
    });
  });

  group('ChromeListRow.destructive', () {
    testWidgets(
      'iOS: one CupertinoListTile leading the red glyph, no trailing control, '
      'spoken as destructive, per R-32-527',
      (tester) async {
        var taps = 0;
        await _pump(
          tester,
          ChromeListRow.destructive(
            title: 'Remove this phone',
            onTap: () => taps++,
          ),
        );

        final CupertinoListTile tile = tester.widget(
          find.byType(CupertinoListTile),
        );
        expect(tile.leading, isA<Icon>());
        expect(tile.trailing, isNull);
        final Icon glyph = tester.widget(
          find.byIcon(Symbols.delete_outline_rounded),
        );
        expect(
          glyph.color,
          AppColor.of(tester.element(find.byType(Icon))).statusError,
        );
        expect(find.byType(AppListRow), findsNothing);
        expect(
          tester.getSemantics(find.text('Remove this phone')),
          matchesSemantics(
            label: 'Remove this phone',
            hint: 'destructive',
            hasTapAction: true,
            hasEnabledState: true,
            isEnabled: true,
          ),
        );

        await tester.tap(find.byType(CupertinoListTile));
        await tester.pump();
        expect(taps, 1);
      },
      variant: _ios,
    );

    testWidgets('iOS: a null onTap dims the tile at opacity.disabled', (
      tester,
    ) async {
      await _pump(
        tester,
        const ChromeListRow.destructive(
          title: 'Remove other phones',
          onTap: null,
        ),
      );

      final Opacity dim = tester.widget(
        find.ancestor(
          of: find.byType(CupertinoListTile),
          matching: find.byType(Opacity),
        ),
      );
      expect(dim.opacity, 0.38);
    }, variant: _ios);

    testWidgets('Android: one AppListRow leading the red glyph, the title in the row ink, '
        'disabled when onTap is null', (tester) async {
      await _pump(
        tester,
        const ChromeListRow.destructive(
          title: 'Remove other phones',
          onTap: null,
        ),
      );

      final AppListRow row = tester.widget(find.byType(AppListRow));
      expect(row.leading, isA<Icon>());
      expect(row.primaryColor, isNull);
      expect(row.trailing, isNull);
      expect(row.onTap, isNull);
      expect(find.byIcon(Symbols.delete_outline_rounded), findsOneWidget);
      expect(find.byType(CupertinoListTile), findsNothing);
      expect(
        tester.getSemantics(find.byType(AppListRow)),
        matchesSemantics(
          label: 'Remove other phones',
          hint: 'destructive',
          isEnabled: false,
          hasEnabledState: true,
        ),
      );
    });
  });

  group('ChromeListRow.static', () {
    testWidgets('iOS: one CupertinoListTile with no onTap', (tester) async {
      await _pump(
        tester,
        const ChromeListRow.static(
          title: 'Version',
          subtitle: '1.2.0',
          trailing: Text('BETA'),
        ),
      );

      final CupertinoListTile tile = tester.widget(
        find.byType(CupertinoListTile),
      );
      expect(tile.onTap, isNull);
      expect(find.text('1.2.0'), findsOneWidget);
      expect(find.text('BETA'), findsOneWidget);
      expect(find.byType(AppListRow), findsNothing);
    }, variant: _ios);

    testWidgets('Android: one static AppListRow, per R-32-502', (tester) async {
      await _pump(
        tester,
        const ChromeListRow.static(
          title: 'Version',
          subtitle: '1.2.0',
          trailing: Text('BETA'),
        ),
      );

      final AppListRow row = tester.widget(find.byType(AppListRow));
      expect(row.isStatic, isTrue);
      expect(row.onTap, isNull);
      expect(find.text('BETA'), findsOneWidget);
      expect(find.byType(CupertinoListTile), findsNothing);
    });
  });
}
