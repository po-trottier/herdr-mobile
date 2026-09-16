/// Golden tests for `ManualPairingScreen` (`app/lib/screens/manual_pairing_screen.dart`,
/// `WP-15-c`), one per row of `docs/31-mockups/03-pair-code.md`'s `## States` table this
/// widget can reach with no platform channel (R-90-011), each in both Selenized dark and light
/// (R-32-012).
///
/// `ManualPairingScreen` is stateful and owns its fields, so there is no pure body to render.
/// Each case drives the real widget the way `manual_pairing_screen_test.dart` does: it types into
/// the `CupertinoTextField`s, moves focus to trigger the on-blur validation, and hands `Pair` an
/// `onPair` that answers with the one `ManualPairingResult` the row names. The `Offline` row reads
/// `connectivity_plus` directly and cannot be injected, so it has no golden here.
///
/// The `loading` case keeps `Pair`'s spinner running, an animation `pumpAndSettle` never settles,
/// so it pumps two plain frames instead.
///
/// Fonts, the app theme and the 375 x 667 reference size come from `golden_support.dart`.
library;

import 'dart:async' show Completer;
import 'dart:convert' show base64Url;
import 'dart:io' show File, SocketException, OSError;
import 'dart:typed_data' show Uint8List;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoTextField;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart'
    show Brightness, CustomScrollView, FocusManager, Offset;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/screens/manual_pairing_screen.dart';
import 'package:herdr_mobile/services/origin.dart' show RelayOrigin;
import 'package:herdr_mobile/services/pairing.dart'
    show PairingInput, PairingCancellation;
import 'package:herdr_mobile/widgets/app_filled_button.dart'
    show AppFilledButton;

import 'golden_support.dart';

/// Relative to the package root, which is `flutter test`'s working directory (`app/`).
const String _wordlistPath = 'assets/wordlists/eff_large_wordlist.txt';

List<String> _loadRealWords() =>
    File(_wordlistPath)
        .readAsLinesSync()
        .where((line) => line.isNotEmpty)
        .toList();

/// The mockup's own worked example (`docs/13-security-pairing.md` R-13-019).
const List<String> _phraseWords = <String>[
  'remedy',
  'tapestry',
  'hubcap',
  'oversleep',
  'jailbird',
  'kinetic',
];

/// A structurally valid routing handle (R-11-112): 22 unpadded base64url characters decoding
/// to 16 bytes.
final String _validHandle = base64Url.encode(Uint8List(16)).replaceAll('=', '');

const RelayOrigin _savedOrigin = RelayOrigin(
  scheme: 'https',
  host: 'relay.example.com',
);

enum _Fill { none, badWord, fourWords, all }

class _Case {
  const _Case(
    this.name, {
    this.saved = false,
    this.connected = false,
    this.fill = _Fill.none,
    this.result,
    this.loading = false,
    this.ios = false,
  });
  final String name;
  final bool saved;
  final bool connected;
  final _Fill fill;
  final ManualPairingResult? result;
  final bool loading;
  final bool ios;
}

const _cases = <_Case>[
  _Case('default'),
  // The iOS branch sits under `CupertinoPageScaffold`, which sets no default text style; this
  // frame proves no `Text` falls back to `MaterialApp`'s yellow double underline (R-41-020).
  _Case('default_ios', ios: true),
  _Case('saved', saved: true),
  _Case('connected', saved: true, connected: true),
  _Case('word_error', fill: _Fill.badWord),
  _Case('word_count_error', fill: _Fill.fourWords),
  _Case('loading', fill: _Fill.all, loading: true),
  _Case(
    'host_in_use',
    fill: _Fill.all,
    result: ManualPairingFailed(ManualPairingFailureCode.hostInUse),
  ),
  _Case(
    'link_failed',
    fill: _Fill.all,
    result: ManualPairingFailed(
      ManualPairingFailureCode.linkFailed,
      cause: SocketException(
        'Connection refused',
        osError: OSError('Connection refused', 111),
      ),
    ),
  ),
];

const _themes = <(String, Brightness)>[
  ('dark', Brightness.dark),
  ('light', Brightness.light),
];

void main() {
  final words = _loadRealWords();
  setUpAll(loadAppFonts);

  for (final testCase in _cases) {
    for (final (themeName, brightness) in _themes) {
      testWidgets(
        '${testCase.name} ($themeName) matches docs/31-mockups/03-pair-code.md',
        (tester) async {
          tester.view.physicalSize = goldenReferenceSize;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          // Reset inside the body: the binding checks foundation debug variables before
          // `addTearDown` callbacks run.
          if (testCase.ios) {
            debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
          }

          final pending = Completer<ManualPairingResult>();
          Future<ManualPairingResult> onPair(
            PairingInput input,
            PairingCancellation cancellation,
          ) => testCase.loading
              ? pending.future
              : Future<ManualPairingResult>.value(testCase.result);

          await tester.pumpWidget(
            goldenApp(
              brightness: brightness,
              child: ManualPairingScreen(
                effWords: words,
                savedRelayOrigin: testCase.saved ? _savedOrigin : null,
                isConnected: testCase.connected,
                onPair: onPair,
                onScanInstead: () {},
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Field 0: relay address, field 1: computer code, fields 2 to 7: the six words.
          final fields = find.byType(CupertinoTextField);
          switch (testCase.fill) {
            case _Fill.none:
              break;
            case _Fill.badWord:
              await tester.enterText(fields.at(2), 'notarealword');
              // Focus the next field: the first field's on-blur validation fires.
              await tester.enterText(fields.at(3), 'tapestry');
              await tester.pumpAndSettle();
            case _Fill.fourWords:
              await tester.enterText(
                fields.at(2),
                _phraseWords.take(4).join(' '),
              );
              await tester.pumpAndSettle();
            case _Fill.all:
              // Re-resolve the finder each time and pump between entries: the sliver form
              // (R-31-03-15) rebuilds its children as focus moves, so one snapshot of the
              // fields taken before typing can point at elements that were replaced.
              await tester.enterText(
                find.byType(CupertinoTextField).at(0),
                'https://relay.example.com',
              );
              await tester.pump();
              await tester.enterText(
                find.byType(CupertinoTextField).at(1),
                _validHandle,
              );
              await tester.pump();
              for (var i = 0; i < _phraseWords.length; i++) {
                await tester.enterText(
                  find.byType(CupertinoTextField).at(2 + i),
                  _phraseWords[i],
                );
                await tester.pump();
              }
              await tester.pumpAndSettle();
              await tester.tap(find.byType(AppFilledButton));
              if (testCase.loading) {
                await tester.pump();
                await tester.pump();
              } else {
                await tester.pumpAndSettle();
              }
          }
          if (testCase.loading) {
            expect(find.text('CONNECTING'), findsOneWidget);
            expect(find.text('Cancel'), findsOneWidget);
            await expectLater(
              find.byType(ManualPairingScreen),
              matchesGoldenFile(
                'goldens/manual_pairing_loading_$themeName.png',
              ),
            );
            return;
          }
          // R-03-128: actions stay pinned while the form returns to its start.
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump();
          await tester.drag(
            find.byType(CustomScrollView),
            const Offset(0, 2000),
          );
          if (testCase.loading) {
            await tester.pump(const Duration(seconds: 1));
          } else {
            await tester.pumpAndSettle();
          }

          expect(find.text('Pair by hand'), findsOneWidget);
          // R-03-126: the saved origin remains editable during pairing.
          expect(find.byType(CupertinoTextField), findsNWidgets(8));
          expect(find.text('Scan the QR code instead'), findsOneWidget);
          expect(
            find.text('Change the relay address in Settings.'),
            findsNothing,
          );
          expect(
            find.text('Pairing disconnects the computer you are using now.'),
            findsNWidgets(testCase.connected ? 1 : 0),
          );
          if (testCase.fill == _Fill.badWord) {
            expect(
              find.text(
                'Word 1 is not in the list. Check it against your computer.',
              ),
              findsOneWidget,
            );
          }
          if (testCase.fill == _Fill.fourWords) {
            expect(
              find.text('A phrase holds six words. You entered 4.'),
              findsOneWidget,
            );
          }
          if (testCase.result != null) {
            expect(find.text('Try again'), findsOneWidget);
          }

          // R-30-803: show each error below the fields, above the pinned actions.
          if (testCase.connected ||
              testCase.fill == _Fill.badWord ||
              testCase.fill == _Fill.fourWords ||
              testCase.name == 'link_failed') {
            await tester.drag(
              find.byType(CustomScrollView),
              const Offset(0, -2000),
            );
            await tester.pumpAndSettle();
          }
          await expectLater(
            find.byType(ManualPairingScreen),
            matchesGoldenFile(
              'goldens/manual_pairing_${testCase.name}_$themeName.png',
            ),
          );
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }
  }
}
