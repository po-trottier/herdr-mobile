/// Key controls remain native and send directly (R-03-130).
library;

import 'dart:async' show StreamController;
import 'dart:ui' show Color, Rect, Size, Tristate;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoButton;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/models/message.dart';
import 'package:herdr_mobile/models/messages/send_input.dart' show SendInput;
import 'package:herdr_mobile/models/messages/send_input_ack.dart';
import 'package:herdr_mobile/services/terminal.dart' show terminalReplyTimeout;
import 'package:herdr_mobile/widgets/composer.dart';
import 'package:herdr_mobile/widgets/key_row.dart';
import 'package:herdr_mobile/widgets/theme/app_color.dart' show AppColor;
import 'package:herdr_mobile/widgets/theme/app_radius.dart' show AppRadius;
import 'package:herdr_mobile/widgets/theme/app_space.dart' show AppSpace;
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart'
    show
        ButtonStyle,
        ColorScheme,
        FilledButton,
        FilledButtonTheme,
        MaterialApp,
        OutlinedButton,
        OutlinedButtonTheme,
        Scaffold,
        TabPageSelector,
        Theme;

import '../screens/golden_support.dart' show loadAppFonts;

Stream<({String corr, SendInputAck ack})> _noAcks() =>
    const Stream<({String corr, SendInputAck ack})>.empty();

final List<String> _sentCorr = <String>[];
final List<SendInput> _acceptedInputs = <SendInput>[];

/// The enabled state set a `ButtonStyle` resolves against, as
/// `app_filled_button_test.dart` names it.
const Set<WidgetState> _enabled = <WidgetState>{};

Finder _cap(String key) => find.byKey(ValueKey<String>(key));

/// The latched form of R-03-118 on Android: the cap's own `FilledButton`, the platform's
/// high-emphasis button, where an idle cap draws an `OutlinedButton`. Not `FilledButton.tonal`
/// — that form is a `FilledButton` too, so every case that reads this also checks the
/// `toggled` flag or the idle `OutlinedButton` it replaced.
Finder _latchedCap(String key) =>
    find.descendant(of: _cap(key), matching: find.byType(FilledButton));

/// The label a cap prints. Scoped to the cap on purpose: the hint strip draws the same word
/// as an inline key cap (R-32-599), so a bare `find.text('ctrl')` matches two widgets while a
/// modifier is latched and proves nothing about the cap.
Finder _capLabel(String key, String label) =>
    find.descendant(of: _cap(key), matching: find.text(label));

/// The hint strip's printed sentence, with every inline key put back as its label. The strip
/// draws `{ctrl} is held.` as one `Text.rich` whose `{...}` spans are key caps on the
/// sentence's baseline (R-32-599), so the rendered string holds a placeholder where each cap
/// sits and `find.text` can never match the sentence whole. It is the one `Text` in the row
/// built from spans rather than from a string.

/// Whether the cap reports itself to assistive technology as a toggle that is on, off, or not
/// a toggle at all (R-03-118). It reads the cap's own toggled node, the one the button merges
/// its label and its tap onto: `tester.getSemantics` of the cap key resolves an ancestor node
/// on iOS, where an `Opacity` sits between the key and the button, and that node carries no
/// flag of its own.
Tristate _toggledOf(WidgetTester tester, String key) {
  final Finder toggled = find.descendant(
    of: _cap(key),
    matching: find.byWidgetPredicate(
      (Widget w) => w is Semantics && w.properties.toggled != null,
    ),
  );
  if (toggled.evaluate().isEmpty) return Tristate.none;
  return tester.getSemantics(toggled).flagsCollection.isToggled;
}

/// The row under a caller that owns the grid-tap count, the way
/// `terminal_screen.dart`'s grid tap does.
Widget _row({
  List<Message>? sent,
  Stream<({String corr, SendInputAck ack})>? acks,
  Object? reconciliation,
  KeyRowLinkState linkState = KeyRowLinkState.live,
  bool landscape = false,
  bool withGrid = false,
  bool panelOpen = true,
  KeyPanelPage? requestedPage,
  ValueChanged<KeyPanelPage>? onPageChanged,
  String paneId = 'w1:p1',
}) => MaterialApp(
  home: Scaffold(
    body: _Harness(
      sent: sent,
      acks: acks,
      reconciliation: reconciliation,
      linkState: linkState,
      landscape: landscape,
      withGrid: withGrid,
      panelOpen: panelOpen,
      requestedPage: requestedPage,
      onPageChanged: onPageChanged,
      paneId: paneId,
    ),
  ),
);

class _Harness extends StatefulWidget {
  const _Harness({
    this.sent,
    this.acks,
    this.reconciliation,
    required this.linkState,
    required this.landscape,
    this.withGrid = false,
    this.panelOpen = true,
    this.requestedPage,
    this.onPageChanged,
    this.paneId = 'w1:p1',
  });
  final List<Message>? sent;
  final Stream<({String corr, SendInputAck ack})>? acks;
  final Object? reconciliation;
  final KeyRowLinkState linkState;
  final bool landscape;

  /// With a grid the panel overlays it bottom-anchored, as on the terminal screen.
  final bool withGrid;

  /// Mirrors `terminal_screen.dart`'s `+` toggle, so a test can close and reopen the
  /// panel on the same row state.
  final bool panelOpen;

  /// Mirrors the page request `terminal_screen.dart` sends when a blocked agent
  /// opens the panel on the Answer page (2026-09-23).
  final KeyPanelPage? requestedPage;

  /// Mirrors the screen's page listener, which feeds the Composer's answer mode.
  final ValueChanged<KeyPanelPage>? onPageChanged;

  /// Mirrors a pane switch on the terminal screen.
  final String paneId;
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final FocusNode focus = FocusNode();
  final GlobalKey<KeyRowState> row = GlobalKey<KeyRowState>();
  final GlobalKey<ComposerState> composer = GlobalKey<ComposerState>();
  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyRow(
    panelOpen: widget.panelOpen,
    requestedPage: widget.requestedPage,
    onPageChanged: widget.onPageChanged,
    key: row,
    focusNode: focus,
    composer: Composer(
      key: composer,
      focusNode: focus,
      onLine: (_) {},
      onSubmit: (String line, {bool whenIdle = false}) async => true,
      inputFormatters: <TextInputFormatter>[
        TextInputFormatter.withFunction(
          (before, after) =>
              row.currentState?.formatComposerEdit(before, after) ?? after,
        ),
      ],
    ),
    paneId: widget.paneId,
    grid: widget.withGrid ? const SizedBox.expand() : null,
    send: (Message message, {String? corr}) {
      _sentCorr.add(corr!);
      widget.sent?.add(message);
    },
    sendInputAcks: widget.acks ?? _noAcks(),
    // The terminal_screen.dart wiring: an accepted control mirrors into the Composer.
    onInputAccepted: (SendInput input) {
      _acceptedInputs.add(input);
      composer.currentState?.applyAcceptedInput(input);
    },
    linkState: widget.linkState,
    offlineReason: widget.linkState == KeyRowLinkState.offline
        ? 'Offline. Showing what we last saw.'
        : null,
    landscape: widget.landscape,
    reconciliationSignal: widget.reconciliation,
  );
}

List<SendInput> _inputs(List<Message> sent) => sent
    .whereType<MessageSendInput>()
    .map((MessageSendInput m) => m.payload)
    .toList();

/// Opens the native Composer keyboard (R-03-130).
Future<void> _pumpWithKeyboard(
  WidgetTester tester, {
  required List<Message> sent,
  Stream<({String corr, SendInputAck ack})>? acks,
  KeyRowLinkState linkState = KeyRowLinkState.live,
}) async {
  await tester.pumpWidget(_row(sent: sent, acks: acks, linkState: linkState));
  await tester.tap(find.byType(EditableText));
  await tester.pump();
}

/// Enters a character through the native field (R-03-130).
class _Keyboard {
  _Keyboard(this.tester);
  final WidgetTester tester;
  Future<void> type(String text) async {
    final String previous = tester
        .widget<EditableText>(find.byType(EditableText))
        .controller
        .text;
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: previous + text,
        selection: TextSelection.collapsed(
          offset: previous.length + text.length,
        ),
      ),
    );
    await tester.pump();
  }
}

/// Pumps the key row at a 390 logical pixel portrait width, the owner's review phone.
Future<void> _pumpAt390(
  WidgetTester tester, {
  bool landscape = false,
  List<Message>? sent,
}) async {
  tester.view.physicalSize = landscape
      ? const Size(844, 390)
      : const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_row(landscape: landscape, sent: sent));
}

/// One settled swipe one page to the left or the right on the panel's pager
/// (R-31-09-40). The horizontal drag wins over a cap's tap: the swipe turns the page
/// and sends nothing.
Future<void> _pageLeft(WidgetTester tester) async {
  await tester.fling(find.byType(PageView), const Offset(-260, 0), 900);
  await tester.pumpAndSettle();
}

Future<void> _pageRight(WidgetTester tester) async {
  await tester.fling(find.byType(PageView), const Offset(260, 0), 900);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  /// The `EditableText` inside the field that carries [key] — the Composer's
  /// own field, or the answer panel's.
  Finder editableIn(String key) => find.descendant(
    of: find.byKey(ValueKey<String>(key)),
    matching: find.byType(EditableText),
  );

  String fieldText(WidgetTester tester, String key) =>
      tester.widget<EditableText>(editableIn(key)).controller.text;

  testWidgets(
    'the Answer page caps send their keys with bypass_line, and nothing '
    'mirrors into the Composer (R-31-09-38, R-31-09-41)',
    (tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      final List<Message> sent = <Message>[];
      final acks = StreamController<({String corr, SendInputAck ack})>();
      addTearDown(acks.close);
      _sentCorr.clear();
      _acceptedInputs.clear();
      await tester.pumpWidget(
        _row(
          sent: sent,
          acks: acks.stream,
          requestedPage: KeyPanelPage.answer,
        ),
      );
      await tester.pumpAndSettle();
      const String composerField = 'composerField';
      await tester.enterText(_cap(composerField), 'keep draft');
      // The Answer page is the pager's third grid: the Keys caps are not here,
      // and the panel's own answer field is gone (2026-09-23) — the Composer's
      // answer mode owns answer text now.
      expect(_cap('keyRowCtrl'), findsNothing);
      expect(_cap('keyRowAnswerField'), findsNothing);
      expect(_cap('keyRowAnswerSend'), findsNothing);
      expect(find.bySemanticsLabel('Answer, page 3 of 3'), findsOneWidget);

      // Six caps (R-31-09-41, re-laid 2026-09-23), each its own target at or
      // over the 48 floor of R-32-363, each sending its named key with
      // bypass_line.
      const Map<String, String> caps = <String, String>{
        'keyRowAnswerUp': 'Up',
        'keyRowAnswerDown': 'Down',
        'keyRowAnswerLeft': 'Left',
        'keyRowAnswerRight': 'Right',
        'keyRowAnswerEsc': 'Esc',
        'keyRowAnswerEnter': 'Enter',
      };
      for (final MapEntry<String, String> cap in caps.entries) {
        final Finder finder = _cap(cap.key);
        final Size size = tester.getSize(finder);
        expect(size.height, greaterThanOrEqualTo(48), reason: cap.key);
        expect(size.width, greaterThanOrEqualTo(48), reason: cap.key);
        await tester.tap(finder);
        await tester.pump();
        final SendInput input = _inputs(sent).last;
        expect(input.keys, <String>[cap.value], reason: cap.key);
        expect(input.text, isNull, reason: cap.key);
        expect(input.line, isNull, reason: cap.key);
        expect(input.bypassLine, isTrue, reason: cap.key);
        acks.add((
          corr: _sentCorr.last,
          ack: const SendInputAck(paneId: 'w1:p1', accepted: true),
        ));
        await tester.pump();
        // No accepted answer key mirrors into the Composer (R-31-09-38).
        expect(fieldText(tester, composerField), 'keep draft', reason: cap.key);
      }
      expect(sent, hasLength(6));
      expect(_acceptedInputs, isEmpty);

      // The Answer inverted T matches the Keys one: `↑` exactly above `↓`, one
      // row pitch. The filled `enter` caps row one at the right edge, across
      // from `esc` (R-31-09-41, amended 2026-09-23).
      final Rect up = tester.getRect(_cap('keyRowAnswerUp'));
      final Rect down = tester.getRect(_cap('keyRowAnswerDown'));
      expect(up.center.dx, down.center.dx);
      expect(down.top - up.bottom, AppSpace.space2);
      expect(
        tester.getRect(_cap('keyRowAnswerEnter')).top,
        tester.getRect(_cap('keyRowAnswerEsc')).top,
      );
      semantics.dispose();
    },
  );

  testWidgets('requestedPage jumps the pager to the requested grid', (
    tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    KeyPanelPage? requested;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return KeyRow(
                paneId: 'w1:p1',
                send: (message, {corr}) {},
                sendInputAcks: _noAcks(),
                panelOpen: true,
                requestedPage: requested,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_cap('keyRowCtrl'), findsOneWidget);
    expect(_cap('keyRowAnswerEnter'), findsNothing);

    // A blocked agent opens the panel on the Answer page (2026-09-23).
    update(() => requested = KeyPanelPage.answer);
    await tester.pumpAndSettle();
    expect(_cap('keyRowAnswerEnter'), findsOneWidget);
    expect(_cap('keyRowCtrl'), findsNothing);
    expect(find.bySemanticsLabel('Answer, page 3 of 3'), findsOneWidget);

    update(() => requested = KeyPanelPage.keys);
    await tester.pumpAndSettle();
    expect(_cap('keyRowCtrl'), findsOneWidget);
    expect(_cap('keyRowAnswerEnter'), findsNothing);

    // A held value re-requests nothing: the page the person swiped to stays.
    update(() => requested = KeyPanelPage.answer);
    await tester.pumpAndSettle();
    expect(_cap('keyRowAnswerEnter'), findsOneWidget);
    await _pageRight(tester);
    expect(_cap('keyRowFn1'), findsOneWidget);
    update(() {});
    await tester.pumpAndSettle();
    expect(_cap('keyRowFn1'), findsOneWidget);
    expect(_cap('keyRowAnswerEnter'), findsNothing);
    semantics.dispose();
  });

  testWidgets(
    'onPageChanged reports the resting page on first build and on every '
    'settle, and again when the reopened panel restores its page',
    (tester) async {
      final List<KeyPanelPage> pages = <KeyPanelPage>[];
      await tester.pumpWidget(_row(onPageChanged: pages.add));
      await tester.pumpAndSettle();
      expect(pages, <KeyPanelPage>[KeyPanelPage.keys]);
      await _pageLeft(tester);
      expect(pages, <KeyPanelPage>[KeyPanelPage.keys, KeyPanelPage.function]);
      await _pageLeft(tester);
      expect(pages, <KeyPanelPage>[
        KeyPanelPage.keys,
        KeyPanelPage.function,
        KeyPanelPage.answer,
      ]);

      // Closed, the row reports nothing; reopened, it restores the page the
      // person left (R-31-09-40) and reports it on the first build.
      await tester.pumpWidget(
        _row(panelOpen: false, onPageChanged: pages.add),
      );
      await tester.pumpAndSettle();
      expect(pages, hasLength(3));
      await tester.pumpWidget(_row(onPageChanged: pages.add));
      await tester.pumpAndSettle();
      expect(pages.last, KeyPanelPage.answer);
      expect(_cap('keyRowAnswerEnter'), findsOneWidget);
    },
  );

  testWidgets(
    'the Answer enter cap is the platform high-emphasis filled button, the '
    'page’s one filled cap (R-31-09-41)',
    (tester) async {
      for (final TargetPlatform platform in <TargetPlatform>[
        TargetPlatform.android,
        TargetPlatform.iOS,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        await tester.pumpWidget(_row(requestedPage: KeyPanelPage.answer));
        await tester.pumpAndSettle();
        final Finder enter = _cap('keyRowAnswerEnter');
        if (platform == TargetPlatform.android) {
          final Finder filled = find.descendant(
            of: enter,
            matching: find.byType(FilledButton),
          );
          expect(filled, findsOneWidget);
          // The high-emphasis form, not the tonal one — read by the resolved
          // default style, exactly as the latched-modifier case reads it.
          final BuildContext capContext = tester.element(filled);
          final ColorScheme scheme = Theme.of(capContext).colorScheme;
          final ButtonStyle defaults = tester
              .widget<FilledButton>(filled)
              .defaultStyleOf(capContext);
          expect(defaults.backgroundColor!.resolve(_enabled), scheme.primary);
          expect(
            defaults.foregroundColor!.resolve(_enabled),
            scheme.onPrimary,
          );
          // Every other answer cap stays an OutlinedButton.
          for (final String key in <String>[
            'keyRowAnswerUp',
            'keyRowAnswerDown',
            'keyRowAnswerEsc',
          ]) {
            expect(
              find.descendant(
                of: _cap(key),
                matching: find.byType(OutlinedButton),
              ),
              findsOneWidget,
              reason: key,
            );
          }
        } else {
          // `cupertino_ui` 1.0.1 keeps the tinted-or-filled choice private, so
          // the ink tells the form: a filled cap takes `color.fg.on_accent`, a
          // tinted one `color.accent.text` — the read the latched-modifier case
          // makes above.
          final AppColor color = AppColor.of(tester.element(enter));
          Color inkOf(String key, String label) =>
              DefaultTextStyle.of(tester.element(_capLabel(key, label)))
                  .style
                  .color!;
          expect(inkOf('keyRowAnswerEnter', 'enter'), color.fgOnAccent);
          expect(inkOf('keyRowAnswerEsc', 'esc'), color.accentText);
        }
        // Filled is not latched: the enter cap reports no toggle flag.
        expect(_toggledOf(tester, 'keyRowAnswerEnter'), Tristate.none);
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'at 360 dp and scale 1 every grid is one page wide: Keys, Function keys '
    'and Answer, with page dots (2026-09-23)',
    (tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_row());
      await tester.pumpAndSettle();

      expect(find.byType(TabPageSelector), findsOneWidget);
      expect(find.bySemanticsLabel('Keys, page 1 of 3'), findsOneWidget);
      // The Keys page is the one unbroken grid (R-31-09-16).
      for (final String key in <String>[
        'keyRowEsc',
        'keyRowTab',
        'keyRowCtrl',
        'keyRowAlt',
        'keyRowNavins',
        'keyRowNavpgdn',
        'keyRowArrow^',
        'keyRowArrow>',
      ]) {
        expect(_cap(key), findsOneWidget, reason: key);
      }
      await _pageLeft(tester);
      expect(
        find.bySemanticsLabel('Function keys, page 2 of 3'),
        findsOneWidget,
      );
      for (int n = 1; n <= 12; n++) {
        expect(_cap('keyRowFn$n'), findsOneWidget, reason: 'F$n');
      }
      await _pageLeft(tester);
      expect(find.bySemanticsLabel('Answer, page 3 of 3'), findsOneWidget);
      for (final String key in <String>[
        'keyRowAnswerEsc',
        'keyRowAnswerUp',
        'keyRowAnswerEnter',
        'keyRowAnswerLeft',
        'keyRowAnswerDown',
        'keyRowAnswerRight',
      ]) {
        expect(_cap(key), findsOneWidget, reason: key);
      }
      semantics.dispose();
    },
  );

  testWidgets(
    'every page is four rows at one height, so the panel and its dots never '
    'move between pages (2026-09-23)',
    (tester) async {
      await _pumpAt390(tester);
      await tester.pumpAndSettle();
      final Rect pager = tester.getRect(find.byType(PageView));
      // Four 48-high rows at space.2 gaps.
      expect(pager.height, 4 * 48 + 3 * AppSpace.space2);
      // Keys page: `esc` on row one, `ctrl` and the bottom arrows on row four.
      expect(tester.getRect(_cap('keyRowEsc')).top, pager.top);
      expect(
        tester.getRect(_cap('keyRowCtrl')).top,
        pager.top + 3 * (48 + AppSpace.space2),
      );
      expect(
        tester.getRect(_cap('keyRowArrowv')).top,
        pager.top + 3 * (48 + AppSpace.space2),
      );
      final Rect dots = tester.getRect(find.byType(TabPageSelector));

      await _pageLeft(tester);
      // Function keys: the same pager and dots; F1–F6 on row three, F7–F12 on
      // row four (R-03-117, amended 2026-09-23).
      expect(tester.getRect(find.byType(PageView)), pager);
      expect(tester.getRect(find.byType(TabPageSelector)), dots);
      expect(
        tester.getRect(_cap('keyRowFn1')).top,
        pager.top + 2 * (48 + AppSpace.space2),
      );
      expect(
        tester.getRect(_cap('keyRowFn7')).top,
        pager.top + 3 * (48 + AppSpace.space2),
      );

      await _pageLeft(tester);
      // Answer: the same again; `enter` on row one across from `esc`, the
      // inverted T centred low with `←` `↓` `→` on row four.
      expect(tester.getRect(find.byType(PageView)), pager);
      expect(tester.getRect(find.byType(TabPageSelector)), dots);
      expect(
        tester.getRect(_cap('keyRowAnswerDown')).top,
        pager.top + 3 * (48 + AppSpace.space2),
      );
      expect(tester.getRect(_cap('keyRowAnswerEnter')).top, pager.top);
      expect(
        tester.getRect(_cap('keyRowAnswerUp')).top,
        pager.top + 2 * (48 + AppSpace.space2),
      );
    },
  );

  testWidgets(
    'every non-arrow cap shows its keybind glyph with its small name under '
    'it; F keys are text faces; arrows are glyphs alone (2026-09-23)',
    (tester) async {
      await _pumpAt390(tester);
      await tester.pumpAndSettle();
      const Map<String, (IconData, String)> keysFaces =
          <String, (IconData, String)>{
            'keyRowEsc': (Symbols.cancel_rounded, 'esc'),
            'keyRowTab': (Symbols.keyboard_tab_rounded, 'tab'),
            'keyRowCtrl': (Symbols.keyboard_control_key_rounded, 'ctrl'),
            'keyRowAlt': (Symbols.keyboard_option_key_rounded, 'alt'),
            'keyRowNavins': (Symbols.insert_text_rounded, 'ins'),
            'keyRowNavdel': (Symbols.backspace_rounded, 'del'),
            'keyRowNavhome': (Symbols.first_page_rounded, 'home'),
            'keyRowNavend': (Symbols.last_page_rounded, 'end'),
            'keyRowNavpgup': (
              Symbols.keyboard_double_arrow_up_rounded,
              'pgup',
            ),
            'keyRowNavpgdn': (
              Symbols.keyboard_double_arrow_down_rounded,
              'pgdn',
            ),
          };
      for (final MapEntry<String, (IconData, String)> face
          in keysFaces.entries) {
        final Finder icon = find.descendant(
          of: _cap(face.key),
          matching: find.byIcon(face.value.$1),
        );
        final Finder name = _capLabel(face.key, face.value.$2);
        expect(icon, findsOneWidget, reason: '${face.key} glyph');
        expect(name, findsOneWidget, reason: '${face.key} name');
        // The name sits under the glyph, the Mac-keycap read.
        expect(
          tester.getRect(name).top,
          greaterThanOrEqualTo(tester.getRect(icon).bottom),
          reason: face.key,
        );
      }
      // An arrow cap carries its glyph and no text.
      for (final String id in const <String>['^', 'v', '<', '>']) {
        expect(
          find.descendant(
            of: _cap('keyRowArrow$id'),
            matching: find.byType(Text),
          ),
          findsNothing,
          reason: 'arrow $id',
        );
      }

      await _pageLeft(tester);
      for (int n = 1; n <= 12; n++) {
        expect(_capLabel('keyRowFn$n', 'F$n'), findsOneWidget, reason: 'F$n');
      }

      await _pageLeft(tester);
      expect(
        find.descendant(
          of: _cap('keyRowAnswerEnter'),
          matching: find.byIcon(Symbols.keyboard_return_rounded),
        ),
        findsOneWidget,
      );
      expect(_capLabel('keyRowAnswerEnter', 'enter'), findsOneWidget);
      expect(
        find.descendant(
          of: _cap('keyRowAnswerEsc'),
          matching: find.byIcon(Symbols.cancel_rounded),
        ),
        findsOneWidget,
      );
      expect(_capLabel('keyRowAnswerEsc', 'esc'), findsOneWidget);
    },
  );

  testWidgets(
    'the cap shape is a radius.sm rounded rectangle on both button forms, '
    'never a stadium (2026-09-23)',
    (tester) async {
      await tester.pumpWidget(_row());
      await tester.pumpAndSettle();
      final BuildContext capContext = tester.element(_cap('keyRowEsc'));
      const BorderRadius expected = BorderRadius.all(
        Radius.circular(AppRadius.sm),
      );
      final OutlinedBorder? outlined = OutlinedButtonTheme.of(
        capContext,
      ).style!.shape!.resolve(_enabled);
      expect(outlined, isA<RoundedRectangleBorder>());
      expect(
        (outlined! as RoundedRectangleBorder).borderRadius,
        expected,
        reason: 'an idle cap is a keycap, not a stadium',
      );
      final OutlinedBorder? filled = FilledButtonTheme.of(
        capContext,
      ).style!.shape!.resolve(_enabled);
      expect((filled! as RoundedRectangleBorder).borderRadius, expected);

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.pumpWidget(_row());
      await tester.pumpAndSettle();
      final CupertinoButton cap = tester.widget<CupertinoButton>(
        find.descendant(
          of: _cap('keyRowEsc'),
          matching: find.byType(CupertinoButton),
        ),
      );
      expect(cap.borderRadius, expected);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'panel grid holds one module across text scale, reopen and keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(_row());
      await tester.pumpAndSettle();

      // At this width and scale six modules no longer fit, so the grid reflows onto
      // more pages (R-31-09-40). Every page keeps the one module.
      Map<String, Rect> rectsOf(List<String> keys) => <String, Rect>{
        for (final String key in keys) key: tester.getRect(_cap(key)),
      };
      void expectOneModule(Map<String, Rect> rects) {
        // One module: every grid cap is the same width at a 2.0 text scale, so each
        // column keeps its meaning.
        final double module = rects['keyRowEsc']!.width;
        expect(module, greaterThanOrEqualTo(48));
        for (final MapEntry<String, Rect> entry in rects.entries) {
          expect(
            entry.value.width,
            moreOrLessEquals(module, epsilon: 0.01),
            reason: entry.key,
          );
        }
      }

      // Page one of the reflowed `Keys` grid (2026-09-23 layout): the `esc`
      // column, the gutter and `alt`, and the first navigation column.
      const List<String> firstPage = <String>[
        'keyRowEsc',
        'keyRowTab',
        'keyRowCtrl',
        'keyRowAlt',
        'keyRowNavins',
        'keyRowNavdel',
        'keyRowArrow<',
      ];
      final Map<String, Rect> first = rectsOf(firstPage);
      expectOneModule(first);
      expect(
        first['keyRowNavins']!.left,
        moreOrLessEquals(first['keyRowNavdel']!.left, epsilon: 0.01),
      );

      // Page two of the reflowed `Keys` grid: the same module, and `↑` still directly
      // over `↓`.
      await _pageLeft(tester);
      final Map<String, Rect> second = rectsOf(const <String>[
        'keyRowEsc',
        'keyRowNavhome',
        'keyRowNavend',
        'keyRowNavpgup',
        'keyRowNavpgdn',
        'keyRowArrow^',
        'keyRowArrowv',
        'keyRowArrow>',
      ]);
      expectOneModule(second);
      expect(
        second['keyRowArrow^']!.left,
        moreOrLessEquals(second['keyRowArrowv']!.left, epsilon: 0.01),
      );
      expect(
        second['keyRowEsc']!.width,
        moreOrLessEquals(first['keyRowEsc']!.width, epsilon: 0.01),
      );

      // Back on page one, a fresh panel at the same width and scale draws the same
      // geometry.
      await _pageRight(tester);
      final Map<String, Rect> before = rectsOf(firstPage);
      await tester.pumpWidget(_row());
      await tester.pumpAndSettle();
      expect(rectsOf(firstPage), before);

      // A raised keyboard changes the insets, not the grid.
      tester.view.viewInsets = const FakeViewPadding(bottom: 336);
      await tester.pump();
      final Map<String, Rect> raised = rectsOf(firstPage);
      for (final String key in firstPage) {
        expect(raised[key]!.width, before[key]!.width, reason: key);
        expect(raised[key]!.left, before[key]!.left, reason: key);
      }
    },
  );

  group('KeyRow pages (R-03-117, R-31-09-40)', () {
    final List<Message> sent = <Message>[];

    setUp(() {
      sent.clear();
      _sentCorr.clear();
      _acceptedInputs.clear();
    });

    testWidgets(
      'a swipe shows the function keys, moves the indicator, and keeps esc in place',
      (tester) async {
        final SemanticsHandle semantics = tester.ensureSemantics();
        await _pumpAt390(tester, sent: sent);
        await tester.pumpAndSettle();

        expect(_cap('keyRowTab'), findsOneWidget);
        expect(_cap('keyRowFn1'), findsNothing);
        expect(find.bySemanticsLabel('Keys, page 1 of 3'), findsOneWidget);
        // The pager owns the horizontal swipes; the inner scroll region of the old
        // panel is gone (R-31-09-40).
        expect(
          find.descendant(
            of: find.byType(PageView),
            matching: find.byWidgetPredicate(
              (Widget w) =>
                  w is SingleChildScrollView &&
                  w.scrollDirection == Axis.horizontal,
            ),
          ),
          findsNothing,
        );
        final Rect escOnKeys = tester.getRect(_cap('keyRowEsc'));

        await _pageLeft(tester);
        for (int n = 1; n <= 12; n++) {
          expect(_cap('keyRowFn$n'), findsOneWidget, reason: 'f$n');
        }
        expect(_cap('keyRowTab'), findsNothing);
        expect(
          find.bySemanticsLabel('Function keys, page 2 of 3'),
          findsOneWidget,
        );
        // The way out sits on every page, in the same place.
        expect(tester.getRect(_cap('keyRowEsc')), escOnKeys);

        // One more swipe shows the Answer page (2026-09-23).
        await _pageLeft(tester);
        expect(_cap('keyRowAnswerEnter'), findsOneWidget);
        expect(_cap('keyRowFn1'), findsNothing);
        expect(find.bySemanticsLabel('Answer, page 3 of 3'), findsOneWidget);
        expect(tester.getRect(_cap('keyRowAnswerEsc')), escOnKeys);

        await _pageRight(tester);
        expect(
          find.bySemanticsLabel('Function keys, page 2 of 3'),
          findsOneWidget,
        );
        await _pageRight(tester);
        expect(_cap('keyRowTab'), findsOneWidget);
        expect(_cap('keyRowFn1'), findsNothing);
        expect(find.bySemanticsLabel('Keys, page 1 of 3'), findsOneWidget);
        // The swipes together sent no input.
        expect(sent, isEmpty);
        semantics.dispose();
      },
    );

    testWidgets(
      'a function key sends its bare name and never takes a latch (R-10-038)',
      (tester) async {
        await _pumpAt390(tester, sent: sent);
        await tester.pumpAndSettle();
        await tester.tap(_cap('keyRowCtrl'));
        await tester.pump();
        expect(find.textContaining('is held. Press one key.'), findsOneWidget);

        await _pageLeft(tester);
        await tester.tap(_cap('keyRowFn5'));
        await tester.pump();

        // No `ctrl+` chord: R-10-038 permits only a character or `tab` as a chord
        // base, and the tap leaves the latch as it found it.
        expect(_inputs(sent).single.keys, <String>['F5']);
        expect(_inputs(sent).single.text, isNull);
        expect(find.textContaining('is held. Press one key.'), findsOneWidget);
      },
    );

    testWidgets(
      'the selected page survives close and reopen, and a new pane starts on page one',
      (tester) async {
        final SemanticsHandle semantics = tester.ensureSemantics();
        await _pumpAt390(tester);
        await tester.pumpAndSettle();
        await _pageLeft(tester);
        expect(_cap('keyRowFn5'), findsOneWidget);

        // Closed and reopened on the same terminal screen, the panel shows the page
        // the person left (R-31-09-40).
        await tester.pumpWidget(_row(panelOpen: false));
        await tester.pumpAndSettle();
        expect(_cap('keyRowEsc'), findsNothing);
        await tester.pumpWidget(_row(panelOpen: true));
        await tester.pumpAndSettle();
        expect(_cap('keyRowFn5'), findsOneWidget);
        expect(
          find.bySemanticsLabel('Function keys, page 2 of 3'),
          findsOneWidget,
        );

        // A new pane starts on page one.
        await tester.pumpWidget(_row(panelOpen: true, paneId: 'w1:p2'));
        await tester.pumpAndSettle();
        expect(_cap('keyRowTab'), findsOneWidget);
        expect(_cap('keyRowFn5'), findsNothing);
        expect(find.bySemanticsLabel('Keys, page 1 of 3'), findsOneWidget);
        semantics.dispose();
      },
    );

    testWidgets('at 360 px and a 2.0 text scale the grid reflows and every cap stays reachable '
        'at full size (R-31-09-40)', (tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(_row());
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Keys, page 1 of 6'), findsOneWidget);

      // Two `Keys` pages, two `Function keys` pages and two `Answer` pages, the
      // `esc` column on every one (2026-09-23 layout). Each entry: the page's
      // own esc cap — the Answer grid's esc sends on the answer path, so it is
      // a distinct widget key — then the caps the page holds.
      const List<(String, List<String>)> pages = <(String, List<String>)>[
        (
          'keyRowEsc',
          <String>[
            'keyRowTab',
            'keyRowCtrl',
            'keyRowAlt',
            'keyRowNavins',
            'keyRowNavdel',
            'keyRowArrow<',
          ],
        ),
        (
          'keyRowEsc',
          <String>[
            'keyRowNavhome',
            'keyRowNavend',
            'keyRowNavpgup',
            'keyRowNavpgdn',
            'keyRowArrow^',
            'keyRowArrowv',
            'keyRowArrow>',
          ],
        ),
        (
          'keyRowEsc',
          <String>[
            'keyRowFn1',
            'keyRowFn7',
            'keyRowFn2',
            'keyRowFn8',
            'keyRowFn3',
            'keyRowFn9',
            'keyRowFn4',
            'keyRowFn10',
          ],
        ),
        (
          'keyRowEsc',
          <String>[
            'keyRowFn1',
            'keyRowFn7',
            'keyRowFn5',
            'keyRowFn11',
            'keyRowFn6',
            'keyRowFn12',
          ],
        ),
        (
          'keyRowAnswerEsc',
          <String>[
            'keyRowAnswerLeft',
            'keyRowAnswerUp',
            'keyRowAnswerDown',
            'keyRowAnswerRight',
          ],
        ),
        ('keyRowAnswerEsc', <String>['keyRowAnswerEnter']),
      ];
      final Rect pager = tester.getRect(find.byType(PageView));
      final Rect escOnFirst = tester.getRect(_cap('keyRowEsc'));
      for (int p = 0; p < pages.length; p++) {
        if (p > 0) await _pageLeft(tester);
        for (final String key in <String>[pages[p].$1, ...pages[p].$2]) {
          final Rect rect = tester.getRect(_cap(key));
          expect(
            rect.width >= 48 && rect.height >= 48,
            isTrue,
            reason:
                '$key on page ${p + 1} is ${rect.width}x${rect.height}, '
                'under the 48 floor of R-32-363',
          );
          // Inside the page: no cap is clipped by the pager.
          expect(rect.left, greaterThanOrEqualTo(pager.left), reason: key);
          expect(rect.right, lessThanOrEqualTo(pager.right), reason: key);
        }
        // The way out is on every page, in the same place.
        expect(
          tester.getRect(_cap(pages[p].$1)),
          escOnFirst,
          reason: 'esc on page ${p + 1}',
        );
      }
      expect(
        find.bySemanticsLabel('Answer, page 6 of 6'),
        findsOneWidget,
      );

      // A scale change with the panel open reflows back: the count drops to
      // three and the pager lands on the last page left, the Answer page.
      tester.platformDispatcher.textScaleFactorTestValue = 1;
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Answer, page 3 of 3'), findsOneWidget);
      expect(_cap('keyRowAnswerEnter'), findsOneWidget);
      expect(_cap('keyRowFn1'), findsNothing);
      semantics.dispose();
    });
  });

  testWidgets('queued acknowledgement retains correlation until final reply', (
    tester,
  ) async {
    final acks = StreamController<({String corr, SendInputAck ack})>();
    addTearDown(acks.close);
    _sentCorr.clear();
    _acceptedInputs.clear();
    await tester.pumpWidget(_row(acks: acks.stream));
    await tester.tap(_cap('keyRowEsc'));
    await tester.pump();
    acks.add((
      corr: _sentCorr.single,
      ack: const SendInputAck(paneId: 'w1:p1', accepted: true, queued: true),
    ));
    await tester.pump();
    await tester.pump(terminalReplyTimeout * 2);
    expect(_acceptedInputs, isEmpty);
    expect(find.textContaining('Outcome unknown'), findsNothing);
    acks.add((
      corr: _sentCorr.single,
      ack: const SendInputAck(paneId: 'w1:p1', accepted: true),
    ));
    await tester.pump();
    expect(_acceptedInputs.single.keys, <String>['Esc']);
  });
  testWidgets('panel overlays the grid and keeps keyboard focus', (
    tester,
  ) async {
    final FocusNode focus = FocusNode();
    addTearDown(focus.dispose);
    final List<Message> sent = <Message>[];
    bool open = false;
    late StateSetter update;
    const gridKey = ValueKey<String>('panelTestGrid');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return KeyRow(
                paneId: 'w1:p1',
                send: (message, {corr}) => sent.add(message),
                sendInputAcks: _noAcks(),
                focusNode: focus,
                panelOpen: open,
                grid: const SizedBox.expand(key: gridKey),
                composer: Composer(
                  focusNode: focus,
                  onLine: (_) {},
                  onSubmit: (String line, {bool whenIdle = false}) async =>
                      true,
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byType(EditableText));
    await tester.pump();
    final Rect grid = tester.getRect(find.byKey(gridKey));
    final Rect bar = tester.getRect(find.byType(Composer));
    update(() => open = true);
    await tester.pump();
    expect(tester.getRect(find.byKey(gridKey)), grid);
    expect(tester.getRect(find.byType(Composer)), bar);
    expect(focus.hasFocus, isTrue);
    expect(tester.getRect(_cap('keyRowNavdel')).bottom, lessThan(bar.top));
    await tester.tap(_cap('keyRowEsc'));
    await tester.pump();
    expect(_inputs(sent).single.keys, <String>['Esc']);
    await tester.tap(_cap('keyRowCtrl'));
    await tester.pump();
    expect(_cap('keyRowNavhome'), findsOneWidget);
    expect(focus.hasFocus, isTrue);
    update(() => open = false);
    await tester.pump();
    expect(_cap('keyRowEsc'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  group('KeyRow acknowledgements (R-31-09-13, R-31-09-14, R-30-518)', () {
    final List<Message> sent = <Message>[];
    late StreamController<({String corr, SendInputAck ack})> acks;

    setUp(() {
      sent.clear();
      _sentCorr.clear();
      _acceptedInputs.clear();
      acks = StreamController<({String corr, SendInputAck ack})>.broadcast();
    });
    tearDown(() => acks.close());

    testWidgets(
      'accepted callbacks match reordered correlations exactly once',
      (tester) async {
        await _pumpWithKeyboard(tester, sent: sent, acks: acks.stream);
        await tester.tap(_cap('keyRowEsc'));
        await tester.tap(_cap('keyRowTab'));
        await tester.pump();
        acks.add((
          corr: _sentCorr[1],
          ack: const SendInputAck(paneId: 'w1:p1', accepted: true),
        ));
        acks.add((
          corr: _sentCorr[0],
          ack: const SendInputAck(paneId: 'w1:p1', accepted: true),
        ));
        acks.add((
          corr: _sentCorr[1],
          ack: const SendInputAck(paneId: 'w1:p1', accepted: true),
        ));
        await tester.pump();
        expect(_acceptedInputs.map((input) => input.keys), <List<String>>[
          <String>['Tab'],
          <String>['Esc'],
        ]);
      },
    );

    testWidgets('unknown correlations do not settle pending keys', (
      tester,
    ) async {
      await _pumpWithKeyboard(tester, sent: sent, acks: acks.stream);
      await tester.tap(_cap('keyRowTab'));
      await tester.pump();
      acks.add((
        corr: 'another-send',
        ack: const SendInputAck(paneId: 'w1:p1', accepted: true),
      ));
      await tester.pump();
      await tester.pump(terminalReplyTimeout);
      expect(find.textContaining('We do not know'), findsOneWidget);
    });

    testWidgets('Composer failures use the existing error strip', (
      tester,
    ) async {
      await tester.pumpWidget(_row());
      tester.state<KeyRowState>(find.byType(KeyRow)).reportInputFailure();
      await tester.pump();
      expect(find.text('Not sent: typing'), findsOneWidget);
      tester.state<KeyRowState>(find.byType(KeyRow)).clearInputFailure();
      await tester.pump();
      expect(find.text('Not sent: typing'), findsNothing);
    });

    testWidgets('a refused send raises a strip that names it, re-sends nothing, and clears on the '
        'next send', (WidgetTester tester) async {
      await _pumpWithKeyboard(tester, sent: sent, acks: acks.stream);
      await tester.tap(_cap('keyRowEsc'));
      await tester.pump();
      await tester.tap(_cap('keyRowTab'));
      await tester.pump();
      expect(_inputs(sent), hasLength(2));

      acks.add((
        corr: _sentCorr[1],
        ack: const SendInputAck(paneId: 'w1:p1', accepted: false),
      ));
      await tester.pump();
      expect(find.text('Not sent: tab'), findsOneWidget);
      expect(_inputs(sent), hasLength(2));

      acks.add((
        corr: _sentCorr[0],
        ack: const SendInputAck(paneId: 'w1:p1', accepted: false),
      ));
      await tester.pump();
      expect(find.text('Not sent: esc'), findsOneWidget);
      expect(find.text('Not sent: tab'), findsNothing);
      expect(_acceptedInputs, isEmpty);

      await tester.tap(_cap('keyRowTab'));
      await tester.pump();
      expect(find.text('Not sent: tab'), findsNothing);
      expect(_inputs(sent), hasLength(3));
    });

    testWidgets(
      'an accepted acknowledgement settles the matching send and shows nothing',
      (WidgetTester tester) async {
        await _pumpWithKeyboard(tester, sent: sent, acks: acks.stream);
        await tester.tap(_cap('keyRowTab'));
        await tester.pump();
        acks.add((
          corr: _sentCorr.single,
          ack: const SendInputAck(paneId: 'w1:p1', accepted: true),
        ));
        await tester.pump();
        expect(find.textContaining('Not sent'), findsNothing);
        expect(find.textContaining('We do not know'), findsNothing);
      },
    );

    testWidgets(
      'no acknowledgement within the reply timeout enters outcome unknown, names the send, '
      're-sends nothing, and the next frame clears it',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          _row(sent: sent, acks: acks.stream, reconciliation: 1),
        );
        await tester.pumpWidget(
          _row(sent: sent, acks: acks.stream, reconciliation: 1),
        );
        await tester.pump();
        await tester.tap(_cap('keyRowTab'));
        await tester.pump();
        expect(_inputs(sent), hasLength(1));

        await tester.pump(terminalReplyTimeout);
        expect(
          find.text('We do not know whether tab reached the pane.'),
          findsOneWidget,
        );
        expect(_inputs(sent), hasLength(1));

        // Typing stays possible while the outcome is unknown: a person may
        // retype, the app may not re-send (R-11-228).
        await tester.tap(_cap('keyRowTab'));
        await tester.pump();
        expect(_inputs(sent), hasLength(2));

        await tester.pumpWidget(
          _row(sent: sent, acks: acks.stream, reconciliation: 2),
        );
        await tester.pump();
        expect(find.textContaining('We do not know'), findsNothing);
        // Flush the second send's own deadline, so the case ends with no timer.
        await tester.pump(terminalReplyTimeout);
      },
    );
  });

  testWidgets('closed panel hides every key without sending', (tester) async {
    final List<Message> sent = <Message>[];
    await tester.pumpWidget(
      MaterialApp(
        home: KeyRow(
          paneId: 'w1:p1',
          send: (message, {corr}) => sent.add(message),
          sendInputAcks: _noAcks(),
        ),
      ),
    );
    expect(_cap('keyRowEsc'), findsNothing);
    expect(_cap('keyRowNavhome'), findsNothing);
    expect(sent, isEmpty);
  });

  group('KeyRow rotation (R-31-09-19)', () {
    testWidgets('rotation clears an active latch', (WidgetTester tester) async {
      await tester.pumpWidget(_row());
      await tester.tap(_cap('keyRowCtrl'));
      await tester.pump();
      expect(_latchedCap('keyRowCtrl'), findsOneWidget);

      await tester.pumpWidget(_row(landscape: true));
      await tester.pump();

      expect(_latchedCap('keyRowCtrl'), findsNothing);
      expect(_capLabel('keyRowCtrl', 'ctrl'), findsOneWidget);
    });
  });

  group('KeyCap is the platform button (R-03-059, R-03-118)', () {
    testWidgets(
      'Android: every idle cap is an OutlinedButton, each arrow its own, and a latched '
      'modifier is the high-emphasis FilledButton whose label keeps its case',
      (WidgetTester tester) async {
        await tester.pumpWidget(_row());
        // `←`, `↓` and `→` and the navigation pairs sit in the expansion since R-03-117.
        await tester.pumpAndSettle();

        for (final String key in const <String>[
          'keyRowEsc',
          'keyRowTab',
          'keyRowCtrl',
          'keyRowAlt',
          'keyRowArrow^',
          'keyRowArrowv',
          'keyRowArrow<',
          'keyRowArrow>',
        ]) {
          expect(
            find.descendant(
              of: _cap(key),
              matching: find.byType(OutlinedButton),
            ),
            findsOneWidget,
            reason: '$key is not an OutlinedButton',
          );
        }
        expect(find.byType(FilledButton), findsNothing);
        expect(find.byType(CupertinoButton), findsNothing);

        await tester.tap(_cap('keyRowCtrl'));
        await tester.pump();
        // R-03-118: the platform's high-emphasis form, the theme's primary fill under its
        // `onPrimary` label, and no outline left on the cap.
        final Finder filled = _latchedCap('keyRowCtrl');
        expect(filled, findsOneWidget);
        expect(
          find.descendant(
            of: _cap('keyRowCtrl'),
            matching: find.byType(OutlinedButton),
          ),
          findsNothing,
        );
        final BuildContext capContext = tester.element(filled);
        // `FilledButton.tonal` is a `FilledButton` too, so the type alone cannot tell the
        // two forms apart: `_FilledButtonVariant` is private. What separates them is the
        // default style each form resolves — the high-emphasis form takes the scheme's
        // `primary`, the tonal form its `secondaryContainer` — and R-03-118 asks for the
        // high-emphasis one. `app.dart` then lays `color.accent.primary` over it, which
        // `app_filled_button_test.dart` proves for the theme.
        final ColorScheme scheme = Theme.of(capContext).colorScheme;
        final ButtonStyle defaults = tester
            .widget<FilledButton>(filled)
            .defaultStyleOf(capContext);
        expect(defaults.backgroundColor!.resolve(_enabled), scheme.primary);
        expect(
          defaults.backgroundColor!.resolve(_enabled),
          isNot(scheme.secondaryContainer),
          reason: 'a tonal cap is what R-03-118 replaced',
        );
        expect(defaults.foregroundColor!.resolve(_enabled), scheme.onPrimary);
        // The name never changes case, weight or text for state (R-03-118): the
        // `toUpperCase` hack of the latched wireframe is retired. A held cap's
        // small name carries no decoration; the lock's underline comes below.
        expect(_capLabel('keyRowCtrl', 'ctrl'), findsOneWidget);
        expect(_capLabel('keyRowCtrl', 'CTRL'), findsNothing);
        expect(
          tester
              .widget<Text>(_capLabel('keyRowCtrl', 'ctrl'))
              .style
              ?.decoration,
          isNull,
        );

        // The quick second tap locks (R-31-09-23): still the one filled cap, and the label
        // takes the caps-lock underline of R-03-118 as amended; held had none (above). The
        // third releases.
        await tester.tap(_cap('keyRowCtrl'));
        await tester.pump();
        expect(find.byType(FilledButton), findsOneWidget);
        expect(_capLabel('keyRowCtrl', 'ctrl'), findsOneWidget);
        expect(
          tester
              .widget<Text>(_capLabel('keyRowCtrl', 'ctrl'))
              .style
              ?.decoration,
          TextDecoration.underline,
        );

        await tester.tap(_cap('keyRowCtrl'));
        await tester.pump();
        expect(find.byType(FilledButton), findsNothing);
        expect(
          find.descendant(
            of: _cap('keyRowCtrl'),
            matching: find.byType(OutlinedButton),
          ),
          findsOneWidget,
        );
        expect(_capLabel('keyRowCtrl', 'ctrl'), findsOneWidget);
      },
    );

    testWidgets(
      'iOS: every idle cap is a CupertinoButton.tinted, and a latched modifier is '
      'CupertinoButton.filled whose label keeps its case',
      (WidgetTester tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        // A failed expect below must not leak the override into the next test; the binding
        // checks the variable before the tear-downs run, so the body resets it too.
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final List<Message> sent = <Message>[];
        await tester.pumpWidget(_row(sent: sent));

        for (final String key in const <String>[
          'keyRowEsc',
          'keyRowCtrl',
          'keyRowAlt',
          'keyRowArrow^',
        ]) {
          expect(
            find.descendant(
              of: _cap(key),
              matching: find.byType(CupertinoButton),
            ),
            findsOneWidget,
            reason: '$key is not a CupertinoButton',
          );
        }
        expect(find.byType(OutlinedButton), findsNothing);
        expect(find.byType(FilledButton), findsNothing);

        // `cupertino_ui` 1.0.1 keeps the tinted-or-filled choice in a private field, so the
        // one thing a test can read is what each form paints on the label: a tinted cap
        // takes the `color.accent.text` ink this file hands it for the 4.5 floor of
        // R-30-720, and a filled cap takes the theme's own `primaryContrastingColor`,
        // `color.fg.on_accent`. `app_filled_button_test.dart` reads its iOS fill the same way.
        Color inkOf(String key, String label) =>
            DefaultTextStyle.of(tester.element(_capLabel(key, label)))
                .style
                .color!;
        final AppColor color = AppColor.of(tester.element(_cap('keyRowCtrl')));
        expect(inkOf('keyRowCtrl', 'ctrl'), color.accentText);

        await tester.tap(_cap('keyRowCtrl'));
        await tester.pump();
        expect(inkOf('keyRowCtrl', 'ctrl'), color.fgOnAccent);
        expect(_capLabel('keyRowCtrl', 'CTRL'), findsNothing);
        expect(
          find.descendant(
            of: _cap('keyRowCtrl'),
            matching: find.byType(CupertinoButton),
          ),
          findsOneWidget,
        );
        // `esc` never latched, so its ink is still the tinted one: the fill is the state,
        // and it belongs to the latched cap alone.
        expect(inkOf('keyRowEsc', 'esc'), color.accentText);

        expect(_inputs(sent), isEmpty);

        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      'a modifier cap reports the latch as a toggle to assistive technology, and still '
      'speaks held or locked (R-03-118, R-31-09-23)',
      (WidgetTester tester) async {
        final SemanticsHandle semantics = tester.ensureSemantics();
        await tester.pumpWidget(_row());

        // Idle: a toggle that is off, not a cap with no state at all.
        expect(_toggledOf(tester, 'keyRowCtrl'), Tristate.isFalse);
        expect(_toggledOf(tester, 'keyRowAlt'), Tristate.isFalse);
        // A key that cannot latch is not a toggle, so a screen reader never calls `esc`
        // "not ticked".
        expect(_toggledOf(tester, 'keyRowEsc'), Tristate.none);
        expect(_toggledOf(tester, 'keyRowArrow^'), Tristate.none);
        expect(_toggledOf(tester, 'keyRowBankTwoToggle'), Tristate.none);

        await tester.tap(_cap('keyRowCtrl'));
        await tester.pump();
        expect(_toggledOf(tester, 'keyRowCtrl'), Tristate.isTrue);
        expect(_toggledOf(tester, 'keyRowAlt'), Tristate.isFalse);
        // The spoken sentence is unchanged: the flag is added beside it, not instead of it.
        expect(
          tester.getSemantics(_cap('keyRowCtrl')).label,
          'Control held. Press one key.',
        );

        await tester.tap(_cap('keyRowCtrl'));
        await tester.pump();
        expect(_toggledOf(tester, 'keyRowCtrl'), Tristate.isTrue);
        expect(
          tester.getSemantics(_cap('keyRowCtrl')).label,
          'Control locked. Tap Control again to release.',
        );

        // Both latched at once (R-03-120): each cap reports its own state, and each speaks
        // its own sentence; the group is named on the strip, not on a cap.
        await tester.tap(_cap('keyRowAlt'));
        await tester.pump();
        expect(_toggledOf(tester, 'keyRowCtrl'), Tristate.isTrue);
        expect(_toggledOf(tester, 'keyRowAlt'), Tristate.isTrue);
        expect(
          tester.getSemantics(_cap('keyRowCtrl')).label,
          'Control locked. Tap Control again to release.',
        );
        expect(
          tester.getSemantics(_cap('keyRowAlt')).label,
          'Alt held. Press one key.',
        );

        // The third tap of `ctrl` releases `ctrl` alone.
        await tester.tap(_cap('keyRowCtrl'));
        await tester.pump();
        expect(_toggledOf(tester, 'keyRowCtrl'), Tristate.isFalse);
        expect(_toggledOf(tester, 'keyRowAlt'), Tristate.isTrue);
        expect(tester.getSemantics(_cap('keyRowCtrl')).label, 'Control');
        semantics.dispose();
      },
    );

    testWidgets(
      'offline, a disabled modifier cap still reports its latch state (R-03-118)',
      (WidgetTester tester) async {
        final SemanticsHandle semantics = tester.ensureSemantics();
        // The offline row disables every cap, so no tap can latch one; the toggle flag is
        // still there to read, so a screen reader never loses the state on a dimmed cap.
        await tester.pumpWidget(_row(linkState: KeyRowLinkState.offline));
        expect(_toggledOf(tester, 'keyRowCtrl'), Tristate.isFalse);
        expect(_toggledOf(tester, 'keyRowAlt'), Tristate.isFalse);
        semantics.dispose();
      },
    );

    testWidgets('iOS: offline, the flag survives the Opacity a disabled cap dims itself with '
        '(R-03-118, R-32-331)', (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final SemanticsHandle semantics = tester.ensureSemantics();
      await tester.pumpWidget(_row(linkState: KeyRowLinkState.offline));

      // The iOS cap dims itself rather than take the component's grey (R-32-331), so the
      // flag rides inside that `Opacity` — this is the case that would lose it.
      expect(_toggledOf(tester, 'keyRowCtrl'), Tristate.isFalse);
      expect(
        tester
            .widget<Opacity>(
              find
                  .descendant(
                    of: _cap('keyRowCtrl'),
                    matching: find.byType(Opacity),
                  )
                  .first,
            )
            .opacity,
        0.38,
      );
      semantics.dispose();
      debugDefaultTargetPlatformOverride = null;
    });
  });

  testWidgets('panel keeps navigation pairs and inverted arrows aligned', (
    tester,
  ) async {
    await _pumpAt390(tester);
    Rect rect(String id) => tester.getRect(_cap(id));
    // R-03-117 re-laid 2026-09-23: the navigation pairs stack on rows one and
    // two of their arrow column, one row apart.
    for (final pair in <(String, String)>[
      ('keyRowNavins', 'keyRowNavdel'),
      ('keyRowNavhome', 'keyRowNavend'),
      ('keyRowNavpgup', 'keyRowNavpgdn'),
    ]) {
      expect(rect(pair.$1).center.dx, rect(pair.$2).center.dx);
      expect(rect(pair.$2).top - rect(pair.$1).bottom, AppSpace.space2);
    }
    // `↑` is exactly above `↓`, one row pitch, and `←` `→` flank `↓` on row four.
    expect(rect('keyRowArrow^').center.dx, rect('keyRowArrowv').center.dx);
    expect(
      rect('keyRowArrowv').top - rect('keyRowArrow^').bottom,
      AppSpace.space2,
    );
    expect(
      rect('keyRowArrow<').right + AppSpace.space2,
      rect('keyRowArrowv').left,
    );
    expect(
      rect('keyRowArrowv').right + AppSpace.space2,
      rect('keyRowArrow>').left,
    );
    expect(_cap('keyRowBankTwoToggle'), findsNothing);
    // The inverted T is bottom-aligned: `←` `↓` `→` share row four with `ctrl`
    // and `alt`; `↑` alone on row three, directly under row two.
    expect(rect('keyRowArrowv').top, rect('keyRowCtrl').top);
    expect(rect('keyRowArrow>').top, rect('keyRowAlt').top);
    expect(
      rect('keyRowArrow^').top,
      rect('keyRowNavdel').bottom + AppSpace.space2,
    );
    expect(rect('keyRowEsc').top, lessThan(rect('keyRowArrow^').top));
  });

  testWidgets(
    'latching ctrl adds the hint above the caps and moves no cap (R-03-117)',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_row(withGrid: true));
      await tester.pumpAndSettle();
      final Map<String, Rect> before = <String, Rect>{
        for (final id in <String>['keyRowEsc', 'keyRowCtrl', 'keyRowArrowv'])
          id: tester.getRect(_cap(id)),
      };
      await tester.tap(_cap('keyRowCtrl'));
      await tester.pumpAndSettle();
      final Finder hint = find.textContaining('is held. Press one key.');
      expect(hint, findsOneWidget);
      for (final entry in before.entries) {
        expect(tester.getRect(_cap(entry.key)), entry.value, reason: entry.key);
      }
      expect(
        tester.getRect(hint).bottom,
        lessThanOrEqualTo(before['keyRowEsc']!.top),
      );
    },
  );

  group('KeyRow panel (R-31-09-24, R-03-117)', () {
    final List<Message> sent = <Message>[];

    setUp(sent.clear);

    /// Opens panel on a freshly pumped row.
    Future<void> pumpPanel(WidgetTester tester) async {
      await tester.pumpWidget(_row(sent: sent));
      await tester.pumpAndSettle();
    }

    testWidgets('the alt cap latches one-shot, the next character is an alt chord, and '
        'focuses the composer (R-31-09-19)', (WidgetTester tester) async {
      await pumpPanel(tester);
      await tester.tap(_cap('keyRowAlt'));
      await tester.pump();

      // R-31-09-17: the latch raises the keyboard, which closes the expansion.
      expect(tester.testTextInput.isVisible, isTrue);
      expect(_cap('keyRowNavins'), findsOneWidget);
      // R-03-118: the fill is the state, and the label keeps its case.
      expect(_latchedCap('keyRowAlt'), findsOneWidget);
      expect(_capLabel('keyRowAlt', 'alt'), findsOneWidget);
      expect(_capLabel('keyRowAlt', 'ALT'), findsNothing);
      expect(sent, isEmpty);

      await _Keyboard(tester).type('x');
      expect(_inputs(sent), hasLength(1));
      expect(_inputs(sent).single.keys, <String>['alt+x']);
      expect(_inputs(sent).single.text, isNull);
    });

    testWidgets("panel's arrows go by name (R-10-037) and leave panel open", (
      WidgetTester tester,
    ) async {
      await pumpPanel(tester);
      await tester.tap(_cap('keyRowArrow<'));
      await tester.pump();
      expect(_inputs(sent).single.keys, <String>['Left']);
      expect(_inputs(sent).single.paneId, 'w1:p1');
      expect(_inputs(sent).single.text, isNull);

      await tester.tap(_cap('keyRowArrow>'));
      await tester.pump();
      expect(_inputs(sent), hasLength(2));
      expect(_inputs(sent).last.keys, <String>['Right']);
      // A key is not a way out: `Fewer keys` is (R-31-09-17).
      expect(_cap('keyRowArrow<'), findsOneWidget);
    });

    testWidgets(
      'every navigation key sends its own raw sequence and leaves panel open '
      '(R-10-036)',
      (WidgetTester tester) async {
        await pumpPanel(tester);
        const Map<String, String> sequences = <String, String>{
          'keyRowNavins': '\x1b[2~',
          'keyRowNavdel': '\x1b[3~',
          'keyRowNavhome': '\x1b[H',
          'keyRowNavend': '\x1b[F',
          'keyRowNavpgup': '\x1b[5~',
          'keyRowNavpgdn': '\x1b[6~',
        };
        for (final MapEntry<String, String> entry in sequences.entries) {
          await tester.tap(_cap(entry.key));
          await tester.pump();
          expect(_inputs(sent).last.text, entry.value, reason: entry.key);
          expect(_inputs(sent).last.keys, isNull, reason: entry.key);
        }
        expect(_inputs(sent), hasLength(sequences.length));
        expect(_cap('keyRowNavhome'), findsOneWidget);
      },
    );

    testWidgets('offline, every panel cap is disabled and sends nothing', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _row(sent: sent, linkState: KeyRowLinkState.offline),
      );
      await tester.pumpAndSettle();
      for (final String key in const <String>[
        'keyRowNavins',
        'keyRowNavdel',
        'keyRowAlt',
        'keyRowArrow<',
        'keyRowArrow>',
        'keyRowNavhome',
        'keyRowNavend',
        'keyRowNavpgup',
        'keyRowNavpgdn',
      ]) {
        await tester.tap(_cap(key));
        await tester.pump();
      }
      expect(sent, isEmpty);
    });
  });
}
