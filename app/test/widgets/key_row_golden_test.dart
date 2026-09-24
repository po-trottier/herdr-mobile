/// Native message bars and the optional key panel (R-03-133).
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/models/messages/send_input_ack.dart'
    show SendInputAck;
import 'package:herdr_mobile/widgets/composer.dart';
import 'package:herdr_mobile/widgets/key_row.dart';
import 'package:material_ui/material_ui.dart' show Scaffold;

import '../screens/golden_support.dart';

const Size _portrait = Size(390, 844);
const Size _landscape = Size(844, 390);

const _themes = <(String, Brightness)>[
  ('dark', Brightness.dark),
  ('light', Brightness.light),
];

KeyRow _keyRow({
  bool landscape = false,
  bool panelOpen = true,
  KeyPanelPage? requestedPage,
  KeyRowLinkState linkState = KeyRowLinkState.live,
}) => KeyRow(
  panelOpen: panelOpen,
  requestedPage: requestedPage,
  paneId: 'w3:p1',
  send: (message, {corr}) {},
  sendInputAcks: const Stream<({String corr, SendInputAck ack})>.empty(),
  linkState: linkState,
  offlineReason: linkState == KeyRowLinkState.offline
      ? 'Not connected to patrick-desk.'
      : null,
  landscape: landscape,
);

const ValueKey<String> _captureKey = ValueKey<String>('keyRowGoldenCapture');

Future<void> _goldenCase(
  WidgetTester tester, {
  required String name,
  required Brightness brightness,
  required KeyRow keyRow,
  Size size = _portrait,
  Future<void> Function(WidgetTester)? settle,
}) async {
  // R-03-130: Capture the native Composer beside the key controls.
  final FocusNode focus = FocusNode();
  addTearDown(focus.dispose);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    goldenApp(
      brightness: brightness,
      child: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          // `matchesGoldenFile` captures the nearest repaint boundary, so this one
          // keeps the PNG to the toolbar alone, not the empty screen above it.
          child: RepaintBoundary(
            key: _captureKey,
            child: KeyRow(
              panelOpen: keyRow.panelOpen,
              requestedPage: keyRow.requestedPage,
              paneId: keyRow.paneId,
              send: keyRow.send,
              sendInputAcks: keyRow.sendInputAcks,
              linkState: keyRow.linkState,
              offlineReason: keyRow.offlineReason,
              landscape: keyRow.landscape,
              focusNode: focus,
              composer: Composer(
                focusNode: focus,
                panelOpen: keyRow.panelOpen,
                onTogglePanel: () {},
                enabled: keyRow.linkState == KeyRowLinkState.live,
                onLine: (_) {},
                onSubmit: (String line, {bool whenIdle = false}) async => true,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (settle != null) {
    await settle(tester);
  } else {
    await tester.pump();
  }

  await tester.pumpAndSettle();
  await expectLater(
    find.byKey(_captureKey),
    matchesGoldenFile('goldens/key_row_${name}_${brightness.name}.png'),
  );
}

void main() {
  setUpAll(loadAppFonts);
  for (final (themeName, brightness) in _themes) {
    for (final TargetPlatform platform in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.iOS,
    ]) {
      testWidgets('multiline input ($themeName, ${platform.name})', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        await _goldenCase(
          tester,
          name: 'multiline_${platform.name}',
          brightness: brightness,
          keyRow: _keyRow(),
          settle: (tester) async {
            await tester.enterText(
              find.byType(EditableText),
              'first line\nsecond line\nthird line',
            );
            await tester.pumpAndSettle();
          },
        );
        debugDefaultTargetPlatformOverride = null;
      });
    }

    for (final TargetPlatform platform in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.iOS,
    ]) {
      testWidgets('Answer keys ($themeName, $platform)', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        await _goldenCase(
          tester,
          name: 'answer_${platform.name}',
          brightness: brightness,
          keyRow: _keyRow(requestedPage: KeyPanelPage.answer),
        );
        debugDefaultTargetPlatformOverride = null;
      });
    }

    testWidgets('closed bar ($themeName) matches mockup 09', (tester) async {
      await _goldenCase(
        tester,
        name: 'bank_one',
        brightness: brightness,
        keyRow: _keyRow(panelOpen: false),
      );
    });

    testWidgets('open panel ($themeName) matches mockup 09', (tester) async {
      await _goldenCase(
        tester,
        name: 'bank_two',
        brightness: brightness,
        keyRow: _keyRow(),
      );
    });

    testWidgets('ctrl latched ($themeName) matches mockup 09', (tester) async {
      await _goldenCase(
        tester,
        name: 'ctrl_latched',
        brightness: brightness,
        keyRow: _keyRow(),
        settle: (tester) async {
          await tester.tap(find.byKey(const ValueKey<String>('keyRowCtrl')));
          // Past `motion.duration.fast`, so the latched fill has landed.
          await tester.pumpAndSettle();
        },
      );
    });

    testWidgets('ctrl locked ($themeName) matches mockup 09', (tester) async {
      await _goldenCase(
        tester,
        name: 'ctrl_locked',
        brightness: brightness,
        keyRow: _keyRow(),
        settle: (tester) async {
          // Two taps: one-shot, then locked (R-31-09-23). The hint strip changes.
          await tester.tap(find.byKey(const ValueKey<String>('keyRowCtrl')));
          await tester.pump();
          await tester.tap(find.byKey(const ValueKey<String>('keyRowCtrl')));
          await tester.pumpAndSettle();
        },
      );
    });

    testWidgets('offline ($themeName) matches mockup 09', (tester) async {
      await _goldenCase(
        tester,
        name: 'offline',
        brightness: brightness,
        keyRow: _keyRow(linkState: KeyRowLinkState.offline),
      );
    });

    testWidgets('landscape ($themeName) matches mockup 08', (tester) async {
      await _goldenCase(
        tester,
        name: 'landscape',
        brightness: brightness,
        keyRow: _keyRow(landscape: true),
        size: _landscape,
      );
    });

    // The iOS branch of R-03-059: `CupertinoButton.tinted` caps under the row's own
    // `actionTextStyle`, and `CupertinoButton.filled` for the latched modifier.
    testWidgets('closed bar on iOS ($themeName) matches mockup 09', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      // A failed expect below must not leak the override into the next test; the binding
      // checks the variable before the tear-downs run, so the body resets it too.
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await _goldenCase(
        tester,
        name: 'bank_one_ios',
        brightness: brightness,
        keyRow: _keyRow(panelOpen: false),
      );
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('ctrl latched on iOS ($themeName) matches mockup 09', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await _goldenCase(
        tester,
        name: 'ctrl_latched_ios',
        brightness: brightness,
        keyRow: _keyRow(),
        settle: (tester) async {
          await tester.tap(find.byKey(const ValueKey<String>('keyRowCtrl')));
          await tester.pumpAndSettle();
        },
      );
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
