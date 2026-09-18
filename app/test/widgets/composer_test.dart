/// Composer edits and raw chords follow R-03-130.
library;

import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoTextField;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/models/message.dart';
import 'package:herdr_mobile/models/messages/pane_frame.dart';
import 'package:herdr_mobile/models/messages/scroll_offsets.dart';
import 'package:herdr_mobile/models/messages/send_input_ack.dart';
import 'package:herdr_mobile/models/messages/watch_ack.dart';
import 'package:herdr_mobile/services/terminal.dart';
import 'package:herdr_mobile/widgets/composer.dart';
import 'package:herdr_mobile/widgets/key_row.dart';
import 'package:material_ui/material_ui.dart'
    show MaterialApp, OutlineInputBorder, Scaffold, TextField;

void main() {
  testWidgets('native edits never write to the Host grid (R-31-09-30)', (
    WidgetTester tester,
  ) async {
    final StreamController<Message> messages =
        StreamController<Message>.broadcast(sync: true);
    final FocusNode focus = FocusNode();
    final List<Message> sent = <Message>[];
    final TerminalService service = TerminalService(
      messages: messages.stream,
      send: (Message message, {String? corr}) => sent.add(message),
      watchPane: (String paneId, {String? corr}) {},
      unwatchPane: (String paneId, {String? corr}) {},
    );
    addTearDown(messages.close);
    addTearDown(service.dispose);
    addTearDown(focus.dispose);
    final Future<void> attached = service.attach('w1:p1');
    messages.add(
      const Message.watchAck(
        WatchAck(
          paneId: 'w1:p1',
          revision: 1,
          viewportRows: 10,
          width: 40,
          scroll: ScrollOffsets(offsetFromBottom: 0, maxOffsetFromBottom: 0),
        ),
      ),
    );
    await attached;
    messages.add(
      const Message.paneFrame(
        PaneFrame(
          paneId: 'w1:p1',
          revision: 2,
          viewportRows: 10,
          width: 40,
          text: 'HOST',
        ),
      ),
    );
    final List<int> before = List<int>.generate(
      40,
      service.xterm.buffer.lines[0].getCodePoint,
    );
    int gridWrites = 0;
    service.xterm.addListener(() => gridWrites++);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Composer(
            focusNode: focus,
            onText: service.sendComposerText,
            onDelete: service.sendComposerDeletions,
            onSubmit: service.sendComposerSubmit,
          ),
        ),
      ),
    );
    final Finder field = find.byType(EditableText);
    await tester.enterText(field, 'a');
    await tester.enterText(field, 'ab');
    await tester.enterText(field, 'ac');
    await tester.enterText(field, 'a');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.widget<EditableText>(field).controller.text, '');
    expect(
      List<int>.generate(40, service.xterm.buffer.lines[0].getCodePoint),
      before,
    );
    expect(gridWrites, 0);
    expect(
      sent
          .whereType<MessageSendInput>()
          .where(
            (MessageSendInput message) =>
                message.payload.keys?.contains('Backspace') ?? false,
          )
          .map((MessageSendInput message) => message.payload.keys),
      <List<String>>[
        <String>['Backspace'],
        <String>['Backspace'],
      ],
    );
    messages.add(
      const Message.paneFrame(
        PaneFrame(
          paneId: 'w1:p1',
          revision: 3,
          viewportRows: 10,
          width: 40,
          text: 'HOST a',
        ),
      ),
    );
    expect(gridWrites, 1);
    expect(
      List<int>.generate(6, service.xterm.buffer.lines[0].getCodePoint),
      'HOST a'.codeUnits,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('disabled Composer does not send or request keyboard', (
    WidgetTester tester,
  ) async {
    final FocusNode focus = FocusNode();
    addTearDown(focus.dispose);
    final List<String> sent = <String>[];
    int submits = 0;
    int panelToggles = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Composer(
            enabled: false,
            focusNode: focus,
            onText: sent.add,
            onDelete: (int count) => sent.add('\b' * count),
            onSubmit: () => submits++,
            onTogglePanel: () => panelToggles++,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.tap(find.byTooltip('Send'), warnIfMissed: false);
    await tester.pump();
    await tester.tap(find.byTooltip('More keys'));
    await tester.pump();
    expect(panelToggles, 1);
    expect(focus.hasFocus, isFalse);
    expect(sent, isEmpty);
    expect(submits, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final TargetPlatform platform in <TargetPlatform>[
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    testWidgets(
      'multiline field keeps its corners and centers controls on ${platform.name}',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final focus = FocusNode();
        addTearDown(focus.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Composer(
                focusNode: focus,
                onText: (_) {},
                onDelete: (_) {},
                onSubmit: () {},
                onTogglePanel: () {},
              ),
            ),
          ),
        );
        final field = find.byKey(const ValueKey<String>('composerField'));
        final more = find.byKey(const ValueKey<String>('composerMore'));
        double paintedCornerRadius() {
          final BorderRadiusGeometry radius = platform == TargetPlatform.iOS
              ? tester
                    .widget<CupertinoTextField>(field)
                    .decoration!
                    .borderRadius!
              : (tester.widget<TextField>(field).decoration!.border!
                        as OutlineInputBorder)
                    .borderRadius;
          return radius
              .resolve(TextDirection.ltr)
              .toRRect(tester.getRect(field))
              .scaleRadii()
              .tlRadiusX;
        }

        final double height = platform == TargetPlatform.iOS ? 36 : 48;
        expect(tester.getSize(field).height, height);
        final singleLineRadius = paintedCornerRadius();
        expect(tester.getSize(more).height, height);
        expect(tester.getCenter(more).dy, tester.getCenter(field).dy);
        final send = find.byKey(const ValueKey<String>('composerSend'));
        final double sendHeight = platform == TargetPlatform.iOS ? 30 : height;
        expect(tester.getSize(send).height, sendHeight);
        expect(tester.getCenter(send).dy, tester.getCenter(field).dy);
        await tester.enterText(find.byType(EditableText), 'one\ntwo\nthree');
        await tester.pump();
        expect(tester.getSize(field).height, height + 44);
        expect(paintedCornerRadius(), singleLineRadius);
        expect(tester.getSize(more).height, height);
        expect(tester.getCenter(more).dy, tester.getCenter(field).dy);
        expect(tester.getSize(send).height, sendHeight);
        expect(tester.getCenter(send).dy, tester.getCenter(field).dy);
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );
    testWidgets(
      'rapid native edits preserve the complete field on ${platform.name}',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final focus = FocusNode();
        addTearDown(focus.dispose);
        var received = '';
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Composer(
                focusNode: focus,
                onText: (text) => received += text,
                onDelete: (count) => received = received.characters
                    .take(received.characters.length - count)
                    .join(),
                onSubmit: () {},
              ),
            ),
          ),
        );
        await tester.showKeyboard(find.byType(EditableText));
        const text =
            'Fast typing keeps  every space, repeated letter, é, 中, and 🧑‍💻.';
        var typed = '';
        for (final char in text.characters) {
          typed += char;
          tester.testTextInput.updateEditingValue(
            TextEditingValue(
              text: typed,
              selection: TextSelection.collapsed(offset: typed.length),
            ),
          );
        }
        await tester.pump();
        expect(received, text);
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .controller
              .text,
          text,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );
    testWidgets(
      'native edits, replacement, selection and submit on ${platform.name}',
      (WidgetTester tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final FocusNode focus = FocusNode();
        addTearDown(focus.dispose);
        final List<String> sent = <String>[];
        int submitted = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Composer(
                focusNode: focus,
                onText: sent.add,
                onDelete: (int count) => sent.add('\b' * count),
                onSubmit: () => submitted++,
              ),
            ),
          ),
        );
        expect(
          find.byType(
            platform == TargetPlatform.iOS ? CupertinoTextField : TextField,
          ),
          findsOneWidget,
        );
        final Finder field = find.byType(EditableText);
        await tester.enterText(field, 'a');
        await tester.enterText(field, 'ab');
        expect(sent, <String>['a', 'b']);
        await tester.enterText(field, 'ac');
        expect(sent.sublist(2), <String>['\b', 'c']);
        await tester.enterText(field, 'a');
        expect(sent.last, '\b');
        await tester.enterText(field, 'abc');
        await tester.enterText(field, 'axbc');
        expect(sent.sublist(sent.length - 2), <String>['\b\b', 'xbc']);
        await tester.enterText(field, 'a');
        final int sends = sent.length;
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: 'a',
            selection: TextSelection(baseOffset: 0, extentOffset: 1),
          ),
        );
        await tester.pump();
        expect(sent.length, sends);
        expect(
          tester.widget<EditableText>(field).controller.selection,
          const TextSelection(baseOffset: 0, extentOffset: 1),
        );
        await tester.testTextInput.receiveAction(TextInputAction.send);
        await tester.pump();
        expect(submitted, 1);
        expect(tester.widget<EditableText>(field).controller.text, '');
        expect(sent.length, sends);
        await tester.enterText(field, 'z');
        expect(sent.last, 'z');
        // An autocorrect replacement ("helo " -> "hello ") arrives as one edit: the
        // Host sees one Backspace and the tail, never a cleared and retyped word.
        await tester.enterText(field, 'helo');
        await tester.enterText(field, 'hello ');
        expect(sent.sublist(sent.length - 2), <String>['\b', 'lo ']);
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );
    testWidgets(
      'native field grows, stays bounded, and submits empty on ${platform.name}',
      (WidgetTester tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final FocusNode focus = FocusNode();
        addTearDown(focus.dispose);
        int submits = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Composer(
                focusNode: focus,
                onText: (_) {},
                onDelete: (_) {},
                onSubmit: () => submits++,
              ),
            ),
          ),
        );
        final Finder field = find.byType(EditableText);
        final double initialHeight = tester.getSize(field).height;
        final SemanticsHandle semantics = tester.ensureSemantics();
        await tester.tap(
          platform == TargetPlatform.iOS
              ? find.bySemanticsLabel('Send')
              : find.byTooltip('Send'),
        );
        await tester.pump();
        expect(submits, 1);
        await tester.enterText(field, 'one\ntwo\nthree');
        await tester.pump();
        expect(tester.getSize(field).height, greaterThan(initialHeight));
        await tester.enterText(field, '1\n2\n3\n4\n5');
        await tester.pump();
        final double maximumHeight = tester.getSize(field).height;
        await tester.enterText(field, '1\n2\n3\n4\n5\n6\n7');
        await tester.pump();
        expect(tester.getSize(field).height, maximumHeight);
        await tester.testTextInput.receiveAction(TextInputAction.send);
        await tester.pump();
        expect(submits, 2);
        expect(tester.widget<EditableText>(field).controller.text, isEmpty);
        expect(tester.getSize(field).height, initialHeight);
        await tester.pumpWidget(const SizedBox.shrink());
        semantics.dispose();
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets('ctrl+c bypass preserves native field on ${platform.name}', (
      WidgetTester tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final FocusNode focus = FocusNode();
      addTearDown(focus.dispose);
      final GlobalKey<KeyRowState> row = GlobalKey<KeyRowState>();
      final List<String> text = <String>[];
      final List<Message> sent = <Message>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KeyRow(
              panelOpen: true,
              composer: Composer(
                focusNode: focus,
                onText: text.add,
                onDelete: (int count) => text.add('\b' * count),
                onSubmit: () {},
                inputFormatters: <TextInputFormatter>[
                  TextInputFormatter.withFunction(
                    (TextEditingValue before, TextEditingValue after) =>
                        row.currentState!.formatComposerEdit(before, after),
                  ),
                ],
              ),
              key: row,
              focusNode: focus,
              paneId: 'w1:p1',
              send: (Message message, {String? corr}) => sent.add(message),
              sendInputAcks: const Stream<SendInputAck>.empty(),
            ),
          ),
        ),
      );
      final Finder field = find.byType(EditableText);
      await tester.enterText(field, 'ab');
      final TextEditingValue before = tester
          .widget<EditableText>(field)
          .controller
          .value;
      await tester.tap(find.byKey(const ValueKey<String>('keyRowCtrl')));
      await tester.pump();
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'abc',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      await tester.pump();
      expect(text, <String>['ab']);
      expect(tester.widget<EditableText>(field).controller.value, before);
      expect((sent.single as MessageSendInput).payload.keys, <String>[
        'ctrl+c',
      ]);
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const ValueKey<String>('keyRowCtrl')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('keyRowAlt')));
      await tester.pump();
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'abx',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      await tester.pump();
      expect((sent.last as MessageSendInput).payload.keys, <String>[
        'ctrl+alt+x',
      ]);
      expect(tester.widget<EditableText>(field).controller.value, before);
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const ValueKey<String>('keyRowCtrl')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('keyRowCtrl')));
      await tester.pump();
      for (final String char in <String>['c', 'd']) {
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: 'ab$char',
            selection: const TextSelection.collapsed(offset: 3),
          ),
        );
        await tester.pump();
        expect((sent.last as MessageSendInput).payload.keys, <String>[
          'ctrl+$char',
        ]);
        expect(tester.widget<EditableText>(field).controller.value, before);
      }
      expect(text, <String>['ab']);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
