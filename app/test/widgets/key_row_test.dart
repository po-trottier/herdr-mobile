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
import 'package:herdr_mobile/widgets/theme/app_space.dart' show AppSpace;
import 'package:material_ui/material_ui.dart'
    show
        ButtonStyle,
        ColorScheme,
        FilledButton,
        MaterialApp,
        OutlinedButton,
        Scaffold,
        Theme;

import '../screens/golden_support.dart' show loadAppFonts;

Stream<SendInputAck> _noAcks() => const Stream<SendInputAck>.empty();

const ValueKey<String> _regionKey = ValueKey<String>('keyRowScrollRegion');

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
  Stream<SendInputAck>? acks,
  Object? reconciliation,
  KeyRowLinkState linkState = KeyRowLinkState.live,
  bool landscape = false,
}) => MaterialApp(
  home: Scaffold(
    body: _Harness(
      sent: sent,
      acks: acks,
      reconciliation: reconciliation,
      linkState: linkState,
      landscape: landscape,
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
  });
  final List<Message>? sent;
  final Stream<SendInputAck>? acks;
  final Object? reconciliation;
  final KeyRowLinkState linkState;
  final bool landscape;
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final FocusNode focus = FocusNode();
  final GlobalKey<KeyRowState> row = GlobalKey<KeyRowState>();
  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyRow(
    panelOpen: true,
    key: row,
    focusNode: focus,
    composer: Composer(
      focusNode: focus,
      onText: (_) {},
      onDelete: (_) {},
      onSubmit: () {},
      inputFormatters: <TextInputFormatter>[
        TextInputFormatter.withFunction(
          (before, after) =>
              row.currentState?.formatComposerEdit(before, after) ?? after,
        ),
      ],
    ),
    paneId: 'w1:p1',
    send: (Message message, {String? corr}) => widget.sent?.add(message),
    sendInputAcks: widget.acks ?? _noAcks(),
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
  Stream<SendInputAck>? acks,
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
Future<void> _pumpAt390(WidgetTester tester, {bool landscape = false}) async {
  tester.view.physicalSize = landscape
      ? const Size(844, 390)
      : const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_row(landscape: landscape));
}

/// Every key, chord and control in the row by its `keyRow*` widget key, as the person sees
/// it: a key inside the middle scroll region is clipped to that region, and a key the region
/// has scrolled out of view is dropped; a pinned key (column one, column six) is never
/// clipped. The region is a container, not a key, and is skipped.
Map<String, Rect> _visibleKeyRects(WidgetTester tester) {
  final Rect region = tester.getRect(find.byKey(_regionKey));
  final Map<String, Rect> rects = <String, Rect>{};
  final Finder keyed = find.byWidgetPredicate(
    (Widget widget) =>
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith('keyRow'),
  );
  for (final Element element in keyed.evaluate()) {
    final String id = (element.widget.key! as ValueKey<String>).value;
    if (id == 'keyRowScrollRegion') continue;
    final Finder finder = find.byKey(ValueKey<String>(id));
    Rect rect = tester.getRect(finder);
    final bool scrolls = find
        .descendant(of: find.byKey(_regionKey), matching: finder)
        .evaluate()
        .isNotEmpty;
    if (scrolls) rect = rect.intersect(region);
    if (!rect.isEmpty) rects[id] = rect;
  }
  return rects;
}

void main() {
  setUpAll(loadAppFonts);
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
                  onText: (_) {},
                  onDelete: (_) {},
                  onSubmit: () {},
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
    late StreamController<SendInputAck> acks;

    setUp(() {
      sent.clear();
      acks = StreamController<SendInputAck>.broadcast();
    });
    tearDown(() => acks.close());

    testWidgets('a refused send raises a strip that names it, re-sends nothing, and clears on the '
        'next send', (WidgetTester tester) async {
      await _pumpWithKeyboard(tester, sent: sent, acks: acks.stream);
      await tester.tap(_cap('keyRowEsc'));
      await tester.pump();
      await tester.tap(_cap('keyRowTab'));
      await tester.pump();
      expect(_inputs(sent), hasLength(2));

      acks.add(const SendInputAck(paneId: 'w1:p1', accepted: false));
      await tester.pump();
      expect(find.text('Not sent: esc'), findsOneWidget);
      expect(_inputs(sent), hasLength(2));

      acks.add(const SendInputAck(paneId: 'w1:p1', accepted: false));
      await tester.pump();
      expect(find.text('Not sent: tab'), findsOneWidget);
      expect(find.text('Not sent: esc'), findsNothing);

      await tester.tap(_cap('keyRowTab'));
      await tester.pump();
      expect(find.text('Not sent: tab'), findsNothing);
      expect(_inputs(sent), hasLength(3));
    });

    testWidgets(
      'an accepted acknowledgement settles the oldest send and shows nothing',
      (WidgetTester tester) async {
        await _pumpWithKeyboard(tester, sent: sent, acks: acks.stream);
        await tester.tap(_cap('keyRowTab'));
        await tester.pump();
        acks.add(const SendInputAck(paneId: 'w1:p1', accepted: true));
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
        // The label never changes case, weight or text for state (R-03-118): the
        // `toUpperCase` hack of the latched wireframe is retired.
        expect(_capLabel('keyRowCtrl', 'ctrl'), findsOneWidget);
        expect(_capLabel('keyRowCtrl', 'CTRL'), findsNothing);
        expect(
          tester.widget<Text>(_capLabel('keyRowCtrl', 'ctrl')).style,
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
    for (final pair in <(String, String)>[
      ('keyRowNavins', 'keyRowNavdel'),
      ('keyRowNavhome', 'keyRowNavend'),
      ('keyRowNavpgup', 'keyRowNavpgdn'),
      ('keyRowArrow^', 'keyRowArrowv'),
    ]) {
      expect(rect(pair.$1).center.dx, rect(pair.$2).center.dx);
      expect(rect(pair.$2).top - rect(pair.$1).bottom, AppSpace.space2);
    }
    expect(
      rect('keyRowArrow<').right + AppSpace.space2,
      rect('keyRowArrowv').left,
    );
    expect(
      rect('keyRowArrowv').right + AppSpace.space2,
      rect('keyRowArrow>').left,
    );
    expect(_cap('keyRowBankTwoToggle'), findsNothing);
  });

  group('KeyRow panel (R-31-09-24, R-03-117)', () {
    final List<Message> sent = <Message>[];

    setUp(sent.clear);

    /// Opens panel on a freshly pumped row.
    Future<void> pumpPanel(WidgetTester tester) async {
      await tester.pumpWidget(_row(sent: sent));
      await tester.pumpAndSettle();
    }

    testWidgets('the grid holds exactly these caps, nothing that types a '
        'character, and opening it sends nothing (R-03-117)', (
      WidgetTester tester,
    ) async {
      await pumpPanel(tester);
      expect(sent, isEmpty);
      // Every cap the whole toolbar draws, in one set: the six columns of row one, the
      // six of row two and the three of row three. A symbol cap would show up here.
      expect(_visibleKeyRects(tester).keys.toSet(), <String>{
        'keyRowEsc',
        'keyRowTab',
        'keyRowCtrl',
        'keyRowAlt',
        'keyRowArrow^',
        'keyRowNavins',
        'keyRowNavhome',
        'keyRowNavpgup',
        'keyRowArrow<',
        'keyRowArrowv',
        'keyRowArrow>',
        'keyRowNavdel',
        'keyRowNavend',
        'keyRowNavpgdn',
      });
      // The symbol caps left the row on 2026-09-10: every one of these characters
      // is on the phone keyboard's own symbol pages.
      for (final String symbol in const <String>[
        '-',
        '_',
        '=',
        '+',
        '|',
        r'\',
        '{',
        '}',
        '[',
        ']',
        '(',
        ')',
      ]) {
        expect(find.text(symbol), findsNothing, reason: symbol);
      }
    });

    testWidgets('the alt cap of row one latches one-shot, the next character is an alt chord, and '
        'focuses the composer (R-31-09-19)', (WidgetTester tester) async {
      await pumpPanel(tester);
      // `alt` sits on row one since R-03-117, so it is reachable with the expansion
      // closed too; this case opens it to prove the latch closes it again.
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
