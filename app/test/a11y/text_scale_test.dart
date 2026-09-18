/// Proves R-30-700, R-30-701, R-30-703, R-30-704 (`docs/90-implementation-plan.md` Phase 22):
/// no clipped text and no overlapping control up to a text scale of 2.0, and a clamp above it
/// wherever the app supplies its own (`key_row.dart`'s terminal chrome, per R-30-702). A
/// `RenderFlex` overflow reports through `FlutterError`, which `tester.takeException()`
/// surfaces — the same idiom every screen test in this package already uses to prove "no
/// crash".
library;

import 'dart:io' show File;

import 'package:flutter/widgets.dart'
    show MediaQuery, MediaQueryData, TextScaler, ValueKey, Widget;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/models/message.dart';
import 'package:herdr_mobile/models/messages/send_input_ack.dart';
import 'package:herdr_mobile/screens/manual_pairing_screen.dart';
import 'package:herdr_mobile/widgets/key_row.dart';
import 'package:material_ui/material_ui.dart' show MaterialApp, Scaffold;

/// Relative to the package root, which is `flutter test`'s working directory (`app/`). Mirrors
/// `manual_pairing_screen_test.dart`'s own loader: `validatePhrase` sanity-checks the real
/// 7776-entry list length (R-13-025), so a hand-picked short fixture can never validate here.
const String _wordlistPath = 'assets/wordlists/eff_large_wordlist.txt';

List<String> _loadRealWords() =>
    File(_wordlistPath)
        .readAsLinesSync()
        .where((line) => line.isNotEmpty)
        .toList();

Stream<({String corr, SendInputAck ack})> _noAcks() =>
    const Stream<({String corr, SendInputAck ack})>.empty();

void _noSend(Message message, {String? corr}) {}

/// The panel is open so the caps exist: the closed bar holds only the `+`, the field and send
/// (R-03-133).
KeyRow _keyRow() => KeyRow(
  paneId: 'w1:p1',
  send: _noSend,
  sendInputAcks: _noAcks(),
  panelOpen: true,
);

/// Nests the scaled `MediaQuery` inside `MaterialApp`, not above it: `MaterialApp` builds its
/// own root `MediaQuery` from the real test window, which would otherwise shadow one placed
/// above it.
Future<void> _pumpAtScale(WidgetTester tester, Widget child, double scale) =>
    tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: child),
        ),
      ),
    );

void main() {
  group('KeyRow at scale (R-30-700, R-30-701, R-30-703)', () {
    for (final scale in <double>[1, 2]) {
      testWidgets('renders with no clipping or overlap at ${scale}x', (
        WidgetTester tester,
      ) async {
        await _pumpAtScale(tester, _keyRow(), scale);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('clamps at maxScaleFactor 2.0 above it (R-30-701, R-30-702)', (
      WidgetTester tester,
    ) async {
      await _pumpAtScale(tester, _keyRow(), 2);
      expect(tester.takeException(), isNull);
      final atTwo = tester.getSize(
        find.byKey(const ValueKey<String>('keyRowEsc')),
      );

      await _pumpAtScale(tester, _keyRow(), 5);
      expect(tester.takeException(), isNull);
      final atFive = tester.getSize(
        find.byKey(const ValueKey<String>('keyRowEsc')),
      );

      expect(
        atFive,
        equals(atTwo),
        reason:
            'key_row.dart clamps its own subtree with TextScaler.clamp(maxScaleFactor: 2.0) '
            '(R-30-702), so a scale of 5.0 must render identically to exactly 2.0',
      );
    });
  });

  group(
    'ManualPairingScreen at scale (R-30-700, R-30-701, R-30-703, R-30-704)',
    () {
      for (final scale in <double>[1, 2]) {
        testWidgets('renders with no clipping or overlap at ${scale}x', (
          WidgetTester tester,
        ) async {
          await _pumpAtScale(
            tester,
            ManualPairingScreen(effWords: _loadRealWords()),
            scale,
          );
          expect(tester.takeException(), isNull);
        });
      }
    },
  );
}
