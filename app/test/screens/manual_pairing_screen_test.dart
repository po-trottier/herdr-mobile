/// Smoke-tests `ManualPairingScreen` (`WP-15-c`) against
/// `docs/31-mockups/03-pair-code.md`: the field layout, the Pair-enablement gate of
/// R-31-03-04, per-word blur validation (R-30-906, R-30-910), the paste-fill behaviour of
/// R-30-907/R-31-03-03, and the editable per-computer relay origin (R-03-126).
///
/// Reads the real, build-time-bundled EFF word list from disk
/// (`assets/wordlists/eff_large_wordlist.txt`, relative to `app/`, `flutter test`'s working
/// directory), the same precedent `app/test/services/pairing_test.dart` already uses:
/// `validatePhrase` sanity-checks the list length against the real 7776-entry count (R-13-025)
/// before it checks anything else, so a hand-picked short fixture can never validate here.
library;

import 'dart:async' show Completer;
import 'dart:convert' show base64Url;
import 'dart:io' show File;
import 'dart:typed_data' show Uint8List;
import 'dart:ui' show Rect, Size;

import 'package:cupertino_ui/cupertino_ui.dart'
    show
        CupertinoAlertDialog,
        CupertinoNavigationBar,
        CupertinoNavigationBarBackButton,
        CupertinoTextField;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart' show AppBar;
import 'package:flutter/rendering.dart' show RenderBox;
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, MethodCall, SystemChannels, TextInputAction;
import 'package:flutter/widgets.dart'
    show
        CustomScrollView,
        EdgeInsets,
        MediaQuery,
        MediaQueryData,
        Offset,
        SingleChildScrollView,
        Size,
        SizedBox;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart' show Ok;
import 'package:herdr_mobile/screens/manual_pairing_screen.dart';
import 'package:herdr_mobile/services/keystore.dart';
import 'package:herdr_mobile/services/origin.dart' show RelayOrigin;
import 'package:herdr_mobile/services/pairing.dart'
    show
        PairingCancellation,
        PairingInput,
        PairingOutcome,
        autocompleteWords,
        persistPairing;
import 'package:herdr_mobile/services/plain_store.dart';
import 'package:herdr_mobile/widgets/app_filled_button.dart';
import 'package:herdr_mobile/widgets/ground_grid.dart';
import 'package:material_ui/material_ui.dart' show AlertDialog, MaterialApp;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// Relative to the package root, which is `flutter test`'s working directory (`app/`).
const String _wordlistPath = 'assets/wordlists/eff_large_wordlist.txt';

List<String> _loadRealWords() =>
    File(_wordlistPath)
        .readAsLinesSync()
        .where((line) => line.isNotEmpty)
        .toList();

/// The mockup's own worked example (`docs/13-security-pairing.md` R-13-019); all six are real
/// EFF long-list entries.
const List<String> _phraseWords = <String>[
  'remedy',
  'tapestry',
  'hubcap',
  'oversleep',
  'jailbird',
  'kinetic',
];

/// A structurally valid routing handle (R-11-112): 22 unpadded base64url characters decoding
/// to 16 bytes. Content is irrelevant to every assertion here.
final String _validHandle = base64Url.encode(Uint8List(16)).replaceAll('=', '');

final String _pairingUri =
    'herdr-remote://pair?v=1&r=https%3A%2F%2Frelay.example.com&h=$_validHandle'
    '&p=remedy-tapestry-hubcap-oversleep-jailbird-kinetic';

Future<void> _fillValidPhrase(WidgetTester tester) async {
  final fields = find.byType(CupertinoTextField);
  // Field 0: relay origin, field 1: computer code, fields 2-7: the six words.
  await tester.enterText(fields.at(0), 'https://relay.example.com');
  await tester.enterText(fields.at(1), _validHandle);
  for (var i = 0; i < _phraseWords.length; i++) {
    await tester.enterText(fields.at(2 + i), _phraseWords[i]);
  }
  await tester.pump();
}

void main() {
  final words = _loadRealWords();

  // No default mock exists for the clipboard platform channel in `flutter_test`; every test
  // that reads or writes the clipboard needs one. An in-memory string stands in for the real
  // OS clipboard, backing both `Clipboard.setData` and `Clipboard.getData`.
  String? clipboardText;
  setUp(() {
    clipboardText = null;
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (
          MethodCall call,
        ) async {
          switch (call.method) {
            case 'Clipboard.setData':
              clipboardText = (call.arguments as Map)['text'] as String?;
              return null;
            case 'Clipboard.getData':
              return <String, dynamic>{'text': clipboardText};
            default:
              return null;
          }
        });
  });
  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  setUpAll(() {
    expect(
      words.length,
      7776,
      reason:
          'run `dart run tool/fetch_eff_wordlist.dart` from app/ before '
          'this test suite (R-13-025)',
    );
  });

  testWidgets('renders the relay-address field, the computer-code field and six word fields, with '
      'Pair disabled', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ManualPairingScreen(effWords: words)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoTextField), findsNWidgets(8));
    expect(find.text('Pair'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(
      tester.widget(
        find.ancestor(
          of: find.text('Pair'),
          matching: find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == 'AppFilledButton',
          ),
        ),
      ),
      isNotNull,
    );
  });

  testWidgets('form has no ground grid (R-03-127)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ManualPairingScreen(effWords: words)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(GroundGrid), findsNothing);
  });

  testWidgets('actions stay pinned at both scroll ends (R-03-128)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: ManualPairingScreen(effWords: words)),
    );
    await tester.pumpAndSettle();
    final pair = find.byType(AppFilledButton);
    final scan = find.text('Scan the QR code instead');
    final pairPosition = tester.getTopLeft(pair);
    final scanPosition = tester.getTopLeft(scan);
    expect(pair.hitTestable(), findsOneWidget);
    expect(scan.hitTestable(), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(pair.hitTestable(), findsOneWidget);
    expect(scan.hitTestable(), findsOneWidget);
    expect(tester.getTopLeft(pair), pairPosition);
    expect(tester.getTopLeft(scan), scanPosition);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 2000));
    await tester.pumpAndSettle();
    expect(pair.hitTestable(), findsOneWidget);
    expect(scan.hitTestable(), findsOneWidget);
    expect(tester.getTopLeft(pair), pairPosition);
    expect(tester.getTopLeft(scan), scanPosition);
  });
  testWidgets(
    'iOS: renders CupertinoNavigationBar, not Material AppBar, on iOS',
    (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await tester.pumpWidget(
        MaterialApp(home: ManualPairingScreen(effWords: words)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoNavigationBar), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'enables Pair once the address, the code and all six words validate',
    (WidgetTester tester) async {
      ManualPairingResult? pressedWith;
      await tester.pumpWidget(
        MaterialApp(
          home: ManualPairingScreen(
            effWords: words,
            onPair: (input, cancellation) async {
              pressedWith = ManualPairingSucceeded(
                PairingOutcome(
                  hostId: 'host-1',
                  hostName: 'patrick-desk',
                  hostStaticPublicKey: Uint8List(32),
                  hostFingerprintText: 'fingerprint',
                  connectedAt: DateTime.utc(2026, 9, 4),
                ),
              );
              return pressedWith!;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _fillValidPhrase(tester);
      await tester.pumpAndSettle();

      final pairButtonFinder = find.text('Pair');
      expect(pairButtonFinder, findsOneWidget);
      await tester.ensureVisible(pairButtonFinder);
      await tester.pumpAndSettle();
      await tester.tap(pairButtonFinder);
      await tester.pumpAndSettle();

      expect(pressedWith, isA<ManualPairingSucceeded>());
    },
  );

  testWidgets('shows "not in the list" on blur for a word outside the EFF list, and keeps every '
      'other typed word', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ManualPairingScreen(effWords: words)),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(CupertinoTextField);
    await tester.enterText(fields.at(2), 'notarealword');
    // Move focus to the next word field, triggering the first field's on-blur validation.
    await tester.enterText(fields.at(3), 'tapestry');
    await tester.pumpAndSettle();

    expect(
      find.text('Word 1 is not in the list. Check it against your computer.'),
      findsOneWidget,
    );
    expect(find.text('notarealword'), findsOneWidget);
  });

  testWidgets(
    'fills all six fields from one pasted phrase, regardless of which field received it',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ManualPairingScreen(effWords: words)),
      );
      await tester.pumpAndSettle();

      final fields = find.byType(CupertinoTextField);
      // Paste the full phrase into the fourth word field (index 5 overall); R-30-907 fills from
      // word 1 regardless.
      await tester.enterText(fields.at(5), _phraseWords.join('-'));
      await tester.pumpAndSettle();

      for (final word in _phraseWords) {
        expect(find.text(word), findsOneWidget);
      }
    },
  );

  testWidgets('stores an edited relay default only for the new computer', (
    WidgetTester tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final keystore = KeystoreService(appLockEnabled: false);
    final plainStore = PlainStore();
    const savedOrigin = RelayOrigin(scheme: 'https', host: 'relay.example.com');
    await keystore.storeHostSecrets(
      'old-host',
      HostSecrets(
        hostStaticPublicKey: Uint8List(32),
        routingHandle: _validHandle,
        relayOrigin: Uri.parse(savedOrigin.canonical),
      ),
    );
    final outcome = PairingOutcome(
      hostId: 'new-host',
      hostName: 'New computer',
      hostStaticPublicKey: Uint8List(32),
      hostFingerprintText: 'fingerprint',
      connectedAt: DateTime.utc(2026, 9, 11),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ManualPairingScreen(
          effWords: words,
          savedRelayOrigin: savedOrigin,
          onPair: (input, cancellation) async {
            final result = await persistPairing(
              keystore: keystore,
              plainStore: plainStore,
              input: input,
              outcome: outcome,
            );
            expect(result, isA<Ok<void>>());
            return ManualPairingSucceeded(outcome);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final fields = find.byType(CupertinoTextField);
    expect(fields, findsNWidgets(8));
    expect(
      tester.widget<CupertinoTextField>(fields.first).controller!.text,
      savedOrigin.canonical,
    );
    await _fillValidPhrase(tester);
    await tester.enterText(fields.first, 'http://public.example.com');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(find.textContaining('must start with https'), findsOneWidget);
    expect(
      tester.widget<AppFilledButton>(find.byType(AppFilledButton)).onPressed,
      isNull,
    );
    await tester.enterText(fields.first, 'https://second.example.com');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pair'));
    await tester.pumpAndSettle();
    final saved = await keystore.hostSecrets('new-host');
    expect(
      (saved as Ok<HostSecrets?>).value?.relayOrigin,
      Uri.parse('https://second.example.com'),
    );
    final previous = await keystore.hostSecrets('old-host');
    expect(
      (previous as Ok<HostSecrets?>).value?.relayOrigin,
      Uri.parse(savedOrigin.canonical),
    );
  });

  group('Paste from clipboard (R-31-03-12)', () {
    testWidgets(
      'a full herdr-remote:// URI fills the address, the code and all six words in one tap',
      (WidgetTester tester) async {
        await Clipboard.setData(ClipboardData(text: _pairingUri));
        await tester.pumpWidget(
          MaterialApp(
            home: ManualPairingScreen(
              effWords: words,
              savedRelayOrigin: const RelayOrigin(
                scheme: 'https',
                host: 'previous.example.com',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Paste from clipboard'));
        await tester.pumpAndSettle();

        final fields = find.byType(CupertinoTextField);
        expect(
          tester.widget<CupertinoTextField>(fields.at(0)).controller?.text,
          'https://relay.example.com',
        );
        expect(
          tester.widget<CupertinoTextField>(fields.at(1)).controller?.text,
          _validHandle,
        );
        for (final word in _phraseWords) {
          expect(find.text(word), findsOneWidget);
        }
      },
    );

    testWidgets(
      'a bare six-word phrase on the clipboard fills only the word fields',
      (WidgetTester tester) async {
        await Clipboard.setData(ClipboardData(text: _phraseWords.join(' ')));
        await tester.pumpWidget(
          MaterialApp(home: ManualPairingScreen(effWords: words)),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Paste from clipboard'));
        await tester.pumpAndSettle();

        for (final word in _phraseWords) {
          expect(find.text(word), findsOneWidget);
        }
        final fields = find.byType(CupertinoTextField);
        expect(
          tester.widget<CupertinoTextField>(fields.at(0)).controller?.text,
          isEmpty,
          reason: 'a bare phrase paste MUST NOT touch the address field',
        );
        expect(
          tester.widget<CupertinoTextField>(fields.at(1)).controller?.text,
          isEmpty,
          reason: 'a bare phrase paste MUST NOT touch the computer-code field',
        );
      },
    );

    testWidgets(
      'a bare computer code on the clipboard fills only the computer-code field',
      (WidgetTester tester) async {
        await Clipboard.setData(ClipboardData(text: _validHandle));
        await tester.pumpWidget(
          MaterialApp(home: ManualPairingScreen(effWords: words)),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Paste from clipboard'));
        await tester.pumpAndSettle();

        final fields = find.byType(CupertinoTextField);
        expect(
          tester.widget<CupertinoTextField>(fields.at(1)).controller?.text,
          _validHandle,
        );
        expect(
          tester.widget<CupertinoTextField>(fields.at(0)).controller?.text,
          isEmpty,
          reason: 'a bare code paste MUST NOT touch the address field',
        );
        for (final word in _phraseWords) {
          expect(
            find.text(word),
            findsNothing,
            reason: 'a bare code paste MUST NOT touch the word fields',
          );
        }
      },
    );

    testWidgets(
      'unrecognisable clipboard content is a quiet no-op: no crash, no field changes',
      (WidgetTester tester) async {
        await Clipboard.setData(
          const ClipboardData(text: 'not a pairing value at all'),
        );
        await tester.pumpWidget(
          MaterialApp(home: ManualPairingScreen(effWords: words)),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Paste from clipboard'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final fields = find.byType(CupertinoTextField);
        expect(
          tester.widget<CupertinoTextField>(fields.at(0)).controller?.text,
          isEmpty,
        );
        expect(
          tester.widget<CupertinoTextField>(fields.at(1)).controller?.text,
          isEmpty,
        );
      },
    );

    testWidgets('an empty clipboard is a quiet no-op: no crash', (
      WidgetTester tester,
    ) async {
      await Clipboard.setData(const ClipboardData(text: ''));
      await tester.pumpWidget(
        MaterialApp(home: ManualPairingScreen(effWords: words)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Paste from clipboard'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('Auto-advance focus on Enter/Next (word fields)', () {
    testWidgets(
      'submitting word field N moves focus to word field N+1, for fields 1 through 5',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(home: ManualPairingScreen(effWords: words)),
        );
        await tester.pumpAndSettle();

        final fields = find.byType(CupertinoTextField);
        for (var i = 0; i < 5; i++) {
          await tester.tap(fields.at(2 + i));
          await tester.enterText(fields.at(2 + i), _phraseWords[i]);
          await tester.testTextInput.receiveAction(TextInputAction.next);
          await tester.pumpAndSettle();

          final nextField = tester.widget<CupertinoTextField>(
            fields.at(2 + i + 1),
          );
          expect(
            nextField.focusNode?.hasFocus,
            isTrue,
            reason:
                'word field ${i + 2} MUST gain focus once word field ${i + 1} submits',
          );
        }
      },
    );

    testWidgets(
      'submitting the sixth, last word field dismisses the keyboard rather than doing nothing',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(home: ManualPairingScreen(effWords: words)),
        );
        await tester.pumpAndSettle();

        final fields = find.byType(CupertinoTextField);
        await tester.ensureVisible(fields.at(7));
        await tester.pumpAndSettle();
        await tester.tap(fields.at(7));
        await tester.enterText(fields.at(7), _phraseWords.last);
        await tester.pumpAndSettle();
        expect(
          tester.widget<CupertinoTextField>(fields.at(7)).focusNode?.hasFocus,
          isTrue,
          reason: 'sanity check: field 6 holds focus before it submits',
        );

        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        for (final field in tester.widgetList<CupertinoTextField>(fields)) {
          expect(
            field.focusNode?.hasFocus,
            isFalse,
            reason:
                'the last field\'s Done dismisses the keyboard (unfocuses), matching '
                '_advanceFocusAfter\'s existing behaviour for a paste/suggestion fill -- it '
                'MUST NOT leave focus stuck on a field with nowhere further to advance',
          );
        }
      },
    );
  });

  testWidgets(
    'a nine-character EFF word does not wrap onto a second line in its word field',
    (WidgetTester tester) async {
      // The longest EFF long-list entries run to nine characters. Picked at runtime from the
      // real bundled list so this test cannot go stale against the asset.
      final nineCharWord = words.firstWhere((w) => w.length == 9);
      await tester.pumpWidget(
        MaterialApp(home: ManualPairingScreen(effWords: words)),
      );
      await tester.pumpAndSettle();

      final fields = find.byType(CupertinoTextField);
      await tester.enterText(fields.at(2), nineCharWord);
      await tester.pumpAndSettle();

      // Scoped to the field's own subtree: the exact word also appears in the autocomplete
      // suggestion row below the field (an unrelated `Text` sibling), so an unscoped
      // `find.text` would match two widgets.
      final rendered = tester.renderObject<RenderBox>(
        find.descendant(of: fields.at(2), matching: find.text(nineCharWord)),
      );
      // The laid-out box height is the real test: more than one visual line roughly doubles
      // it. One `AppType.monoPhrase` line (18px font, 24/18 line height) is 24 logical
      // pixels; anything past ~30 means a wrap happened.
      expect(
        rendered.size.height,
        lessThan(30),
        reason:
            'the word must stay on one line inside its field; a taller render means it '
            'wrapped, the exact defect this fix removes',
      );
    },
  );

  group('Autocomplete strip (R-30-904, R-32-532, R-30-519)', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'iOS rotation keeps the focused final word above landscape actions at ${scale}x text',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(393, 852);
          tester.view.padding = const FakeViewPadding(top: 59);
          tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
          tester.view.viewInsets = const FakeViewPadding(bottom: 336);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pumpWidget(
            MaterialApp(home: ManualPairingScreen(effWords: words)),
          );
          await tester.pumpAndSettle();
          await _fillValidPhrase(tester);
          await tester.pumpAndSettle();

          tester.view.physicalSize = const Size(852, 393);
          tester.view.padding = const FakeViewPadding(left: 59, right: 59);
          tester.view.viewPadding = const FakeViewPadding(
            left: 59,
            right: 59,
            bottom: 21,
          );
          tester.view.viewInsets = const FakeViewPadding(bottom: 216);
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          final fields = find.byType(CupertinoTextField);
          final focused = tester.widget<CupertinoTextField>(fields.last);
          expect(focused.focusNode!.hasFocus, isTrue);
          expect(focused.controller!.text, _phraseWords.last);
          final fieldRect = tester.getRect(fields.last);
          final viewport = tester.getRect(find.byType(CustomScrollView));
          expect(fieldRect.top, greaterThanOrEqualTo(viewport.top));
          expect(fieldRect.bottom, lessThanOrEqualTo(viewport.bottom));
          expect(fieldRect.height, greaterThanOrEqualTo(48));
          expect(fieldRect.left, greaterThanOrEqualTo(59));
          expect(fieldRect.right, lessThanOrEqualTo(852 - 59));
          final pair = find.byType(AppFilledButton);
          expect(pair.hitTestable(), findsOneWidget);
          expect(tester.widget<AppFilledButton>(pair).onPressed, isNotNull);
          expect(tester.getRect(pair).bottom, lessThanOrEqualTo(393 - 216));
          expect(
            find.text('Scan the QR code instead').hitTestable(),
            findsOneWidget,
          );

          tester.view.physicalSize = const Size(393, 852);
          tester.view.padding = const FakeViewPadding(top: 59);
          tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
          tester.view.viewInsets = const FakeViewPadding(bottom: 336);
          await tester.pumpAndSettle();
          final portraitField = tester.getRect(fields.last);
          final portraitViewport = tester.getRect(
            find.byType(CustomScrollView),
          );
          expect(portraitField.top, greaterThanOrEqualTo(portraitViewport.top));
          expect(
            portraitField.bottom,
            lessThanOrEqualTo(portraitViewport.bottom),
          );
          expect(focused.focusNode!.hasFocus, isTrue);
          expect(
            tester
                .widgetList<CupertinoTextField>(fields)
                .map((field) => field.controller!.text),
            ['https://relay.example.com', _validHandle, ..._phraseWords],
          );
        },
        variant: TargetPlatformVariant.only(TargetPlatform.iOS),
      );
    }

    testWidgets(
      'iOS dragging the landscape form dismisses the keyboard to reach Back',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(852, 393);
        tester.view.padding = const FakeViewPadding(left: 59, right: 59);
        tester.view.viewPadding = const FakeViewPadding(
          left: 59,
          right: 59,
          bottom: 21,
        );
        tester.view.viewInsets = const FakeViewPadding(bottom: 216);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            initialRoute: '/pair',
            routes: {
              '/': (_) => const SizedBox(),
              '/pair': (_) => ManualPairingScreen(effWords: words),
            },
          ),
        );
        await tester.pumpAndSettle();
        await _fillValidPhrase(tester);
        await tester.pumpAndSettle();
        final lastWord = tester.widget<CupertinoTextField>(
          find.byType(CupertinoTextField).last,
        );
        expect(lastWord.focusNode!.hasFocus, isTrue);
        await tester.drag(find.byType(CustomScrollView), const Offset(0, 2000));
        await tester.pumpAndSettle();
        expect(lastWord.focusNode!.hasFocus, isFalse);
        expect(lastWord.controller!.text, _phraseWords.last);

        tester.view.viewInsets = const FakeViewPadding();
        tester.view.padding = const FakeViewPadding(
          left: 59,
          right: 59,
          bottom: 21,
        );
        await tester.pumpAndSettle();
        expect(find.text('Pair by hand').hitTestable(), findsOneWidget);
        final back = find.byType(CupertinoNavigationBarBackButton);
        expect(back.hitTestable(), findsOneWidget);
        await tester.tap(back);
        await tester.pumpAndSettle();
        expect(find.byType(ManualPairingScreen), findsNothing);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );

    /// Pumps the screen at a phone size with a simulated 300 px keyboard inset, per
    Future<void> pumpWithKeyboard(WidgetTester tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      // The real view's data with only the keyboard inset swapped in: a bare
      // `MediaQueryData(viewInsets: ...)` would zero the size and break layout.
      final mediaQuery = MediaQueryData.fromView(tester.view)
          .copyWith(viewInsets: const EdgeInsets.only(bottom: 300));
      await tester.pumpWidget(
        MediaQuery(
          data: mediaQuery,
          child: MaterialApp(home: ManualPairingScreen(effWords: words)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('small landscape viewport keeps the relay field visible', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(640, 360);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 239);
      tester.view.padding = const FakeViewPadding(top: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 24);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          initialRoute: '/pair',
          routes: {
            '/': (_) => const SizedBox(),
            '/pair': (_) => ManualPairingScreen(effWords: words),
          },
        ),
      );
      await tester.pumpAndSettle();
      final relay = find.byType(CupertinoTextField).first;
      await tester.enterText(relay, 'https://relay.example.com');
      await tester.pumpAndSettle();
      final field = tester.getRect(relay);
      expect(field.height, greaterThanOrEqualTo(48));
      expect(field.top, greaterThanOrEqualTo(24));
      expect(field.bottom, lessThanOrEqualTo(360 - 239));
      expect(
        tester.widget<CupertinoTextField>(relay).focusNode!.hasFocus,
        isTrue,
      );
      final pair = find.byType(AppFilledButton);
      await tester.ensureVisible(pair);
      await tester.pumpAndSettle();
      expect(tester.getRect(pair).top, greaterThanOrEqualTo(24));
      expect(tester.getRect(pair).bottom, lessThanOrEqualTo(360 - 239));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 70));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
      expect(find.text('Pair by hand').hitTestable(), findsOneWidget);
    });
    testWidgets('short landscape viewport keeps the final word visible', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(997, 448);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 304);
      addTearDown(tester.view.reset);
      tester.view.padding = const FakeViewPadding(top: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 24);
      await tester.pumpWidget(
        MaterialApp(home: ManualPairingScreen(effWords: words)),
      );
      await tester.pumpAndSettle();
      final fields = find.byType(CupertinoTextField);
      await tester.enterText(fields.at(0), 'https://relay.example.com');
      await tester.enterText(fields.at(1), _validHandle);
      for (var index = 2; index < 8; index++) {
        await tester.enterText(fields.at(index), 'abacus');
        await tester.pumpAndSettle();
      }
      final field = tester.getRect(fields.at(7));
      expect(field.height, greaterThanOrEqualTo(48));
      expect(field.top, greaterThanOrEqualTo(24));
      expect(field.bottom, lessThanOrEqualTo(448 - 304));
      expect(
        tester.widget<CupertinoTextField>(fields.at(7)).focusNode!.hasFocus,
        isTrue,
      );
      expect(
        tester.widget<AppFilledButton>(find.byType(AppFilledButton)).onPressed,
        isNotNull,
      );
      final strip = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_SuggestionStrip',
      );
      expect(strip, findsNothing);
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      await tester.pumpAndSettle();
      expect(strip, findsOneWidget);
      final restoredField = tester.getRect(fields.at(7));
      expect(restoredField.top, greaterThanOrEqualTo(24));
      expect(
        restoredField.bottom,
        lessThanOrEqualTo(tester.getRect(strip).top),
      );
    });
    testWidgets(
      'two typed characters with matches show the strip docked above the keyboard inset, '
      'and a chip tap fills the field and advances focus',
      (WidgetTester tester) async {
        await pumpWithKeyboard(tester);

        final fields = find.byType(CupertinoTextField);
        await tester.enterText(fields.at(2), 'ab');
        await tester.pumpAndSettle();

        // (a) The strip exists, and the first chip is the first `ab` prefix match.
        final stripFinder = find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_SuggestionStrip',
        );
        expect(stripFinder, findsOneWidget);

        // (b) The strip bottom sits at or above the inset top.
        final Rect strip = tester.getRect(stripFinder);
        expect(strip.bottom, lessThanOrEqualTo(667 - 300));

        // (c) The focused field stays fully visible above the strip.
        final Rect word1 = tester.getRect(fields.at(2));
        expect(word1.bottom, lessThanOrEqualTo(strip.top));

        // (d) Tapping the first chip fills word 1 and moves focus to word 2.
        final String firstMatch = autocompleteWords(
          'ab',
          words,
        ).first; // never log this
        await tester.tap(find.text(firstMatch).first);
        await tester.pumpAndSettle();
        expect(
          tester.widget<CupertinoTextField>(fields.at(2)).controller?.text,
          firstMatch,
        );
        expect(
          tester.widget<CupertinoTextField>(fields.at(3)).focusNode?.hasFocus,
          isTrue,
          reason: 'R-31-03-02: focus MUST advance on an accepted suggestion',
        );
      },
    );

    testWidgets(
      'one typed character, or no exact-prefix match, shows no strip',
      (WidgetTester tester) async {
        await pumpWithKeyboard(tester);

        final fields = find.byType(CupertinoTextField);
        // One character: `autocompleteWords` fires only after the second character.
        await tester.enterText(fields.at(2), 'a');
        await tester.pumpAndSettle();
        expect(
          find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_SuggestionStrip',
          ),
          findsNothing,
        );

        // No exact-prefix match: two characters that start no list word.
        await tester.enterText(fields.at(2), 'zqx');
        await tester.pumpAndSettle();
        expect(
          find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_SuggestionStrip',
          ),
          findsNothing,
        );
      },
    );
  });

  testWidgets('Cancel aborts pairing and ignores a late failure', (
    tester,
  ) async {
    final pending = Completer<ManualPairingResult>();
    PairingCancellation? cancellation;
    var cancelledSwitches = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ManualPairingScreen(
          effWords: words,
          onCancelled: () => cancelledSwitches++,
          onPair: (input, token) {
            cancellation = token;
            return pending.future;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _fillValidPhrase(tester);
    await tester.ensureVisible(find.text('Pair'));
    await tester.tap(find.text('Pair'));
    await tester.pump();
    expect(find.text('CONNECTING'), findsOneWidget);
    expect(find.text('Connecting to relay.example.com...'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(cancellation!.isCancelled, isTrue);
    expect(cancelledSwitches, 0);
    expect(find.text('Pairing cancelled.'), findsOneWidget);
    pending.complete(
      const ManualPairingFailed(ManualPairingFailureCode.linkFailed),
    );
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsNothing);
    expect(find.text('Pair'), findsOneWidget);
  });

  testWidgets(
    'iOS landscape pairing keeps Cancel reachable while the keyboard closes',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(852, 393);
      tester.view.padding = const FakeViewPadding(left: 59, right: 59);
      tester.view.viewPadding = const FakeViewPadding(
        left: 59,
        right: 59,
        bottom: 21,
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 216);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final pending = Completer<ManualPairingResult>();
      PairingCancellation? cancellation;
      await tester.pumpWidget(
        MaterialApp(
          home: ManualPairingScreen(
            effWords: words,
            onPair: (input, token) {
              cancellation = token;
              return pending.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _fillValidPhrase(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pair'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final cancel = find.text('Cancel');
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -400),
      );
      // Finish the iOS scroll spring without waiting on the activity indicator.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(cancel.hitTestable(), findsOneWidget);
      expect(tester.getRect(cancel).bottom, lessThanOrEqualTo(393 - 216));
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(cancellation!.isCancelled, isTrue);
      pending.complete(
        const ManualPairingFailed(ManualPairingFailureCode.linkFailed),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pair'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  group('Post-attempt failures (mockup 03 states table)', () {
    testWidgets('a link failure keeps the typed words, shows the safe transport cause and '
        'the raw cause, and keeps the primary action enabled as Try again '
        '(R-31-03-13, R-30-803, R-30-804)', (WidgetTester tester) async {
      const rawCause =
          'Could not open a connection to wss://relay.example.com: SocketException';
      await tester.pumpWidget(
        MaterialApp(
          home: ManualPairingScreen(
            effWords: words,
            onPair: (input, cancellation) async => const ManualPairingFailed(
              ManualPairingFailureCode.linkFailed,
              detail: rawCause,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _fillValidPhrase(tester);
      await tester.pumpAndSettle();

      final pairButton = find.text('Pair');
      await tester.ensureVisible(pairButton);
      await tester.pumpAndSettle();
      await tester.tap(pairButton);
      await tester.pumpAndSettle();

      // The sentence of R-31-03-13 and the raw cause of R-30-803 both show.
      expect(
        find.textContaining('Could not reach relay.example.com:'),
        findsOneWidget,
      );
      expect(find.text(rawCause), findsNothing);

      // Every field keeps what the person typed.
      final fields = find.byType(CupertinoTextField);
      for (var i = 0; i < _phraseWords.length; i++) {
        expect(
          tester.widget<CupertinoTextField>(fields.at(2 + i)).controller?.text,
          _phraseWords[i],
        );
      }

      // `Pair` becomes the one `Try again` of R-30-804 and stays enabled.
      final button = tester.widget<AppFilledButton>(
        find.ancestor(
          of: find.text('Try again'),
          matching: find.byType(AppFilledButton),
        ),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('phrase_attempts still clears the six words and disables Pair '
        '(R-13-023, unchanged)', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ManualPairingScreen(
            effWords: words,
            onPair: (input, cancellation) async => const ManualPairingFailed(
              ManualPairingFailureCode.phraseAttempts,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _fillValidPhrase(tester);
      await tester.pumpAndSettle();

      final pairButton = find.text('Pair');
      await tester.ensureVisible(pairButton);
      await tester.pumpAndSettle();
      await tester.tap(pairButton);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Three tries used. The computer made a new phrase. Read it again.',
        ),
        findsOneWidget,
      );
      final fields = find.byType(CupertinoTextField);
      for (var i = 0; i < _phraseWords.length; i++) {
        expect(
          tester.widget<CupertinoTextField>(fields.at(2 + i)).controller?.text,
          isEmpty,
        );
      }
      final button = tester.widget<AppFilledButton>(
        find.byType(AppFilledButton),
      );
      expect(button.onPressed, isNull);
    });
  });
  for (final platform in <TargetPlatform>[
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    testWidgets('link switch asks before pairing on ${platform.name}', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      var calls = 0;
      PairingInput? submitted;
      final input = PairingInput(
        relayOrigin: const RelayOrigin(
          scheme: 'https',
          host: 'relay.example.com',
        ),
        handle: _validHandle,
        phrase: _phraseWords.join('-'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ManualPairingScreen(
            effWords: words,
            initialInput: input,
            isConnected: true,
            onPair: (value, cancellation) async {
              submitted = value;
              calls++;
              return const ManualPairingFailed(
                ManualPairingFailureCode.linkFailed,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Pair'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pair'));
      await tester.pumpAndSettle();
      expect(find.text('Switch computers?'), findsOneWidget);
      expect(
        find.byType(
          platform == TargetPlatform.iOS ? CupertinoAlertDialog : AlertDialog,
        ),
        findsOneWidget,
      );
      expect(calls, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(
        tester
                .widget<CupertinoTextField>(
                  find.byType(CupertinoTextField).at(2),
                )
                .controller!
                .text ==
            _phraseWords.first,
        isTrue,
      );
      await tester.tap(find.text('Pair'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disconnect and pair'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(submitted == input, isTrue);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  for (final linked in <bool>[false, true]) {
    testWidgets(
      'connected typed or edited link bypasses confirmation: $linked',
      (tester) async {
        var calls = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: ManualPairingScreen(
              effWords: words,
              initialInput: linked
                  ? PairingInput(
                      relayOrigin: const RelayOrigin(
                        scheme: 'https',
                        host: 'relay.example.com',
                      ),
                      handle: _validHandle,
                      phrase: _phraseWords.join('-'),
                    )
                  : null,
              isConnected: true,
              onPair: (_, cancellation) async {
                calls++;
                return const ManualPairingFailed(
                  ManualPairingFailureCode.linkFailed,
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (linked) {
          await tester.enterText(
            find.byType(CupertinoTextField).at(2),
            'abacus',
          );
        } else {
          await _fillValidPhrase(tester);
        }
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Pair'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Pair'));
        await tester.pumpAndSettle();
        expect(find.text('Switch computers?'), findsNothing);
        expect(calls, 1);
      },
    );
  }
  testWidgets(
    'unconnected link keeps its editable origin and hyphenated words',
    (tester) async {
      PairingInput? submitted;
      final phraseWords = <String>['yo-yo', ..._phraseWords.skip(1)];
      final input = PairingInput(
        relayOrigin: const RelayOrigin(
          scheme: 'https',
          host: 'link.example.com',
        ),
        handle: _validHandle,
        phrase: phraseWords.join('-'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ManualPairingScreen(
            effWords: words,
            savedRelayOrigin: const RelayOrigin(
              scheme: 'https',
              host: 'saved.example.com',
            ),
            initialInput: input,
            onPair: (value, cancellation) async {
              submitted = value;
              return const ManualPairingFailed(
                ManualPairingFailureCode.linkFailed,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoTextField), findsNWidgets(8));
      expect(submitted, isNull);
      final fields = tester
          .widgetList<CupertinoTextField>(find.byType(CupertinoTextField))
          .toList();
      expect(fields[0].controller!.text, input.relayOrigin.canonical);
      expect(fields[2].controller!.text == phraseWords.first, isTrue);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Pair'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pair'));
      await tester.pumpAndSettle();
      expect(find.text('Switch computers?'), findsNothing);
      expect(submitted?.relayOrigin.canonical, input.relayOrigin.canonical);
      expect(submitted?.phrase == input.phrase, isTrue);
    },
  );
}
