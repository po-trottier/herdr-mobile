/// Proves R-30-740/R-30-741 (`docs/90-implementation-plan.md` Phase 22): every interactive
/// element measures at least 48 by 48 logical pixels, and a large text scale never shrinks one
/// below that floor. Covers every key row key in the panel (`key_row.dart`), and every switch
/// (`notification_settings_screen.dart`'s `_SwitchRow`). The settings screen's
/// terminal-size control (`settings_screen.dart`, `WP-21-b`) is the platform's own slider since
/// R-03-110 and is not pumped here — see the note at the bottom of this file for why.
library;

import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/widgets.dart'
    show
        MediaQuery,
        MediaQueryData,
        PageView,
        Semantics,
        TextScaler,
        ValueKey,
        Widget;
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    hide Message;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/models/message.dart';
import 'package:herdr_mobile/models/messages/send_input_ack.dart';
import 'package:herdr_mobile/screens/notification_settings_screen.dart';
import 'package:herdr_mobile/services/notifications.dart';
import 'package:herdr_mobile/widgets/app_list_row.dart' show AppListRow;
import 'package:herdr_mobile/widgets/app_section_header.dart'
    show AppSectionHeader;
import 'package:herdr_mobile/widgets/key_row.dart';
import 'package:herdr_mobile/widgets/theme/app_size.dart' show AppSize;
import 'package:herdr_mobile/widgets/theme/app_space.dart' show AppSpace;
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart'
    show
        FilledButton,
        IconButton,
        MaterialApp,
        OutlinedButton,
        Scaffold,
        Switch;
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../screens/golden_support.dart' show loadAppFonts;

class _MockPlugin extends Mock implements FlutterLocalNotificationsPlugin {}

Stream<({String corr, SendInputAck ack})> _noAcks() =>
    const Stream<({String corr, SendInputAck ack})>.empty();

void _noSend(Message message, {String? corr}) {}

Future<void> _pumpKeyRow(WidgetTester tester) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: KeyRow(
        panelOpen: true,
        paneId: 'w1:p1',
        send: _noSend,
        sendInputAcks: _noAcks(),
      ),
    ),
  ),
);

/// Fails when [finder] resolves to a render size smaller than
/// [AppSize.targetMin] (48) in either dimension. `tester.getSize` reads the laid-out
/// `RenderBox`, so this is the real tappable area, not a declared constant.
void _expectAtLeast48(WidgetTester tester, Finder finder, String label) {
  final size = tester.getSize(finder);
  expect(
    size.width >= 48 && size.height >= 48,
    isTrue,
    reason:
        '$label measures ${size.width}x${size.height}, below the 48x48 floor',
  );
}

void main() {
  group('KeyRow touch targets', () {
    testWidgets('the named keys meet 48x48', (WidgetTester tester) async {
      await _pumpKeyRow(tester);
      for (final String key in <String>[
        'keyRowEsc',
        'keyRowTab',
        'keyRowCtrl',
        'keyRowAlt',
      ]) {
        _expectAtLeast48(tester, find.byKey(ValueKey<String>(key)), key);
      }
      // `↑` shares its page with them: the inverted T of R-03-117, re-laid
      // 2026-09-23, keeps `←`, `↓` and `→` beside one another on row four.
      _expectAtLeast48(
        tester,
        find.byKey(const ValueKey<String>('keyRowArrow^')),
        'arrow ^',
      );
    });

    testWidgets('first-row keys stay at 48x48 at a 2.0 text scale', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: KeyRow(
                panelOpen: true,
                paneId: 'w1:p1',
                send: _noSend,
                sendInputAcks: _noAcks(),
              ),
            ),
          ),
        ),
      );
      _expectAtLeast48(
        tester,
        find.byKey(const ValueKey<String>('keyRowEsc')),
        'esc at 2.0x',
      );
    });

    testWidgets('every panel key meets 48x48', (WidgetTester tester) async {
      await _pumpKeyRow(tester);
      await tester.pumpAndSettle();
      // The navigation block: `ins home pgup` on row one over `del end pgdn` on
      // row two, and `← ↓ →` on row four (R-03-117, re-laid 2026-09-23).
      for (final String label in <String>[
        'ins',
        'home',
        'pgup',
        'del',
        'end',
        'pgdn',
      ]) {
        _expectAtLeast48(
          tester,
          find.byKey(ValueKey<String>('keyRowNav$label')),
          'nav $label',
        );
      }
      for (final String key in <String>[
        'keyRowArrow<',
        'keyRowArrowv',
        'keyRowArrow>',
      ]) {
        _expectAtLeast48(tester, find.byKey(ValueKey<String>(key)), key);
      }
    });

    // R-31-09-15: a cap grows sideways with its label and never clips it. The row clamps at
    // 2.0 (R-30-703), so 5.0 must render exactly as 2.0 does. `pgup` and `pgdn` carry the
    // longest labels the grid holds. At this width and scale six modules no longer fit, so
    // the grid reflows onto more pages (R-31-09-40): the check pages through them all.
    for (final double ambient in <double>[2, 5]) {
      testWidgets(
        'the panel clips no label at an ambient $ambient text scale, and every cap '
        'keeps its target',
        (WidgetTester tester) async {
          await loadAppFonts();
          tester.view.physicalSize = const Size(360 * 3, 800 * 3);
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(ambient)),
                child: Scaffold(
                  body: KeyRow(
                    panelOpen: true,
                    paneId: 'w1:p1',
                    send: _noSend,
                    sendInputAcks: _noAcks(),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // The 48 floor holds on every page the reflow added. The indicator's spoken
          // label carries the page count (`Keys, page 1 of 6`). Page two of the
          // reflowed `Keys` grid holds the longest names, `pgup` and `pgdn`
          // (2026-09-23 layout); the ink check runs when the walk reaches it.
          final Finder spoken = find.byWidgetPredicate(
            (Widget w) =>
                w is Semantics &&
                (w.properties.label ?? '').startsWith('Keys, page 1 of '),
          );
          final int pageCount = int.parse(
            (tester.widget<Semantics>(spoken).properties.label ?? '')
                .split(' of ')
                .last,
          );
          for (int page = 0; page < pageCount; page++) {
            if (page > 0) {
              await tester.fling(
                find.byType(PageView),
                const Offset(-260, 0),
                900,
              );
              await tester.pumpAndSettle();
            }
            if (page == 1) {
              // A cap never clips its name: the ink of `pgup` and `pgdn` sits
              // inside the cap's box (R-31-09-15).
              for (final String label in <String>['pgup', 'pgdn']) {
                final Finder cap = find.byKey(
                  ValueKey<String>('keyRowNav$label'),
                );
                final Rect box = tester.getRect(cap);
                final Rect ink = tester.getRect(
                  find.descendant(of: cap, matching: find.text(label)),
                );
                expect(
                  box.left <= ink.left && ink.right <= box.right,
                  isTrue,
                  reason: 'the $label ink $ink must sit inside its cap $box',
                );
              }
            }
            final Finder caps = find.descendant(
              of: find.byType(PageView),
              matching: find.byWidgetPredicate(
                (Widget w) => w is OutlinedButton || w is FilledButton,
              ),
            );
            expect(caps, findsWidgets, reason: 'page ${page + 1} holds caps');
            for (int i = 0; i < tester.widgetList(caps).length; i++) {
              _expectAtLeast48(
                tester,
                caps.at(i),
                'cap $i on page ${page + 1}',
              );
            }
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  group('Switch touch targets', () {
    testWidgets(
      'every notification settings switch row meets 48x48 (size.row.one_line/two_line, both >= 48)',
      (WidgetTester tester) async {
        SharedPreferencesAsyncPlatform.instance =
            InMemorySharedPreferencesAsync.empty();
        final plugin = _MockPlugin();
        when(
          () => plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >(),
        ).thenReturn(null);
        when(
          () => plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >(),
        ).thenReturn(null);
        final service = NotificationsService(
          plugin: plugin,
          preferences: SharedPreferencesAsync(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: NotificationSettingsScreen(service: service)),
          ),
        );
        await tester.pump();

        // Every switch row's own tap target is the whole row (`_SwitchRow`'s doc comment:
        // "the whole row is the `size.target.min` target, not just the thumb"), so this walks
        // up from Flutter's own `Switch` — the one part of that private row this test's
        // different library can address — to the `AppListRow` that owns the row's height
        // (`AppListRow` composes a `SizedBox` + `DecoratedBox`, so `Container` finds nothing).
        final switches = find.byType(Switch);
        expect(switches, findsWidgets);
        for (var i = 0; i < tester.widgetList(switches).length; i++) {
          final row = find
              .ancestor(of: switches.at(i), matching: find.byType(AppListRow))
              .first;
          _expectAtLeast48(tester, row, 'switch row $i');
        }
      },
    );
  });

  group('Chevron visual size against its target (R-30-291)', () {
    testWidgets(
      'AppSectionHeader.tier1 draws its chevron smaller than the 48 target it sits in',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AppSectionHeader.tier1(
                label: 'Space one',
                expanded: false,
                onToggle: () {},
              ),
            ),
          ),
        );
        final Finder disclosure = find.descendant(
          of: find.byType(AppSectionHeader),
          matching: find.byType(IconButton),
        );
        final Size chevron = tester.getSize(
          find.descendant(
            of: disclosure,
            matching: find.byIcon(Symbols.chevron_right_rounded),
          ),
        );
        final Size target = tester.getSize(disclosure);
        expect(target.width, greaterThanOrEqualTo(AppSize.targetMin));
        expect(
          target.height >= AppSize.targetMin,
          isTrue,
          reason: 'the disclosure button must meet the 48 target',
        );
        expect(
          chevron.height < target.height,
          isTrue,
          reason:
              'the chevron glyph (${chevron.height}) must render smaller than '
              'its enclosing target (${target.height})',
        );
      },
    );
  });

  group('Adjacent touch target spacing (R-30-292)', () {
    testWidgets('ctrl and alt keep at least space.1 of gap', (
      WidgetTester tester,
    ) async {
      await _pumpKeyRow(tester);
      // The panel's one adjacent pair of named caps since the 2026-09-23
      // re-layout: `ctrl` and `alt` sit side by side on row four.
      final double ctrlRight = tester
          .getTopRight(find.byKey(const ValueKey<String>('keyRowCtrl')))
          .dx;
      final double altLeft = tester
          .getTopLeft(find.byKey(const ValueKey<String>('keyRowAlt')))
          .dx;
      expect(
        altLeft - ctrlRight,
        greaterThanOrEqualTo(AppSpace.space1),
        reason:
            'ctrl and alt must keep at least space.1 '
            '(${AppSpace.space1}) of gap between them',
      );
    });
  });

  // `settings_screen.dart`'s terminal-size control (R-30-740, R-30-741, `WP-21-b`, on request)
  // is not pumped here: since R-03-110 (2026-09-09) it is the platform's own discrete slider,
  // a `Slider` on Android and a `CupertinoSlider` on iOS, whose thumb target is the
  // component's own, the measured exception R-33-076 records. The floor holds by the
  // platform, not by anything a widget pump here could observe.
}
