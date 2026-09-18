import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoActivityIndicator, CupertinoTextField;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/models/messages/send_input.dart';
import 'package:herdr_mobile/widgets/composer.dart';
import 'package:herdr_mobile/widgets/theme/app_size.dart';
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart'
    show
        CircularProgressIndicator,
        MaterialApp,
        OutlineInputBorder,
        Scaffold,
        TextField;

void main() {
  for (final TargetPlatform platform in <TargetPlatform>[
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    testWidgets(
      'multiline field keeps fixed corners and bottom inset controls on ${platform.name}',
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
                onLine: (_) {},
                onSubmit: (String line, {bool whenIdle = false}) async => true,
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
        final double sendBottomInset = platform == TargetPlatform.iOS ? 3 : 0;
        expect(tester.getSize(send).height, sendHeight);
        expect(tester.getCenter(send).dy, tester.getCenter(field).dy);
        if (platform == TargetPlatform.iOS) {
          expect(tester.getRect(field).right - tester.getRect(send).right, 3);
        }
        await tester.enterText(find.byType(EditableText), 'one\ntwo\nthree');
        await tester.pump();
        expect(tester.getSize(field).height, height + 44);
        expect(paintedCornerRadius(), singleLineRadius);
        expect(tester.getSize(more).height, height);
        expect(tester.getRect(more).bottom, tester.getRect(field).bottom);
        expect(tester.getSize(send).height, sendHeight);
        expect(
          tester.getRect(field).bottom - tester.getRect(send).bottom,
          sendBottomInset,
        );
        expect(tester.getCenter(more).dy, tester.getCenter(send).dy);
        if (platform == TargetPlatform.iOS) {
          expect(
            tester.getCenter(send),
            tester.getRect(field).bottomRight -
                Offset(singleLineRadius, singleLineRadius),
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );
    testWidgets('send choices and queued cancellation on $platform', (
      WidgetTester tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final FocusNode focus = FocusNode();
      addTearDown(focus.dispose);
      final List<bool> submissions = <bool>[];
      Completer<bool> result = Completer<bool>();
      bool queued = false;
      int cancellations = 0;
      int immediateSends = 0;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) {
                rebuild = setState;
                return Composer(
                  focusNode: focus,
                  queued: queued,
                  onLine: (_) {},
                  onSubmit: (String line, {bool whenIdle = false}) {
                    submissions.add(whenIdle);
                    return whenIdle ? result.future : Future<bool>.value(true);
                  },
                  onSendQueuedNow: () {
                    immediateSends++;
                    rebuild(() => queued = false);
                  },
                  onCancelQueued: () {
                    cancellations++;
                    rebuild(() => queued = false);
                    result.complete(false);
                  },
                );
              },
            ),
          ),
        ),
      );
      final Finder send = find.byKey(const ValueKey<String>('composerSend'));
      final Finder field = find.byType(EditableText);
      // An empty draft still submits Enter.
      await tester.tap(send);
      await tester.pump();
      expect(submissions, <bool>[false]);
      await tester.enterText(field, 'send this later');
      await tester.longPress(send);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send now'));
      await tester.pumpAndSettle();
      expect(submissions, <bool>[false, false]);
      expect(tester.widget<EditableText>(field).controller.text, '');
      await tester.enterText(field, 'retain queued draft');
      await tester.longPress(send);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send when the agent is done'));
      await tester.pump();
      rebuild(() => queued = true);
      await tester.pump(const Duration(seconds: 1));
      expect(submissions, <bool>[false, false, true]);
      expect(tester.widget<EditableText>(field).readOnly, isTrue);
      expect(
        tester.widget<EditableText>(field).controller.text,
        'retain queued draft',
      );
      expect(
        find.text('Queued. Sends when the agent is done.'),
        findsOneWidget,
      );
      expect(find.byIcon(Symbols.schedule_rounded), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.longPress(send);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Send now'), findsOneWidget);
      expect(find.text('Send when the agent is done'), findsNothing);
      await tester.tap(find.text('Cancel queued send'));
      await tester.pumpAndSettle();
      expect(cancellations, 1);
      expect(tester.widget<EditableText>(field).readOnly, isFalse);
      expect(
        tester.widget<EditableText>(field).controller.text,
        'retain queued draft',
      );
      expect(submissions, <bool>[false, false, true]);
      result = Completer<bool>();
      await tester.longPress(send);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send when the agent is done'));
      await tester.pump();
      rebuild(() => queued = true);
      await tester.pump(const Duration(seconds: 1));
      await tester.longPress(send);
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Send now'));
      // The platform menu fires its choice in a post-frame callback, so one more frame lands
      // the rebuild; the queued spinner never settles.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(immediateSends, 1);
      expect(submissions, <bool>[false, false, true, true]);
      expect(tester.widget<EditableText>(field).readOnly, isFalse);
      expect(
        tester.widget<EditableText>(field).controller.text,
        'retain queued draft',
      );
      result.complete(true);
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(field).controller.text, '');
      expect(tester.widget<EditableText>(field).readOnly, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('full-line edits survive async submission on $platform', (
      WidgetTester tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final FocusNode focus = FocusNode();
      addTearDown(focus.dispose);
      final GlobalKey<ComposerState> key = GlobalKey<ComposerState>();
      final List<String> lines = <String>[];
      Completer<bool> result = Completer<bool>();
      int submissions = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Composer(
              key: key,
              focusNode: focus,
              onLine: lines.add,
              onSubmit: (String line, {bool whenIdle = false}) {
                submissions++;
                return result.future;
              },
              inputFormatters: <TextInputFormatter>[
                TextInputFormatter.withFunction(
                  (before, after) =>
                      after.copyWith(text: after.text.replaceAll('teh', 'the')),
                ),
              ],
            ),
          ),
        ),
      );
      key.currentState!.seedLine('host');
      expect(key.currentState!.currentLine, 'host');
      key.currentState!.seedLine('other');
      expect(key.currentState!.currentLine, 'host');
      expect(lines, isEmpty);
      final Finder field = find.byType(EditableText);
      await tester.enterText(field, 'teh');
      await tester.enterText(field, 'the cat');
      await tester.enterText(field, 'the bat');
      await tester.enterText(field, 'the');
      expect(lines, <String>['the', 'the cat', 'the bat', 'the']);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'the',
          selection: TextSelection(baseOffset: 0, extentOffset: 3),
        ),
      );
      await tester.pump();
      expect(lines.length, 4);
      expect(
        tester.widget<EditableText>(field).textInputAction,
        TextInputAction.newline,
      );
      await tester.enterText(field, 'the\ncat');
      await tester.testTextInput.receiveAction(TextInputAction.newline);
      await tester.pump();
      expect(submissions, 0);
      expect(lines.last, 'the\ncat');
      final Finder send = find.byKey(const ValueKey<String>('composerSend'));
      await tester.tap(send);
      await tester.pump();
      expect(submissions, 1);
      expect(tester.widget<EditableText>(field).readOnly, isFalse);
      expect(key.currentState!.currentLine, '');
      final Finder indicator = find.byType(
        platform == TargetPlatform.iOS
            ? CupertinoActivityIndicator
            : CircularProgressIndicator,
      );
      expect(indicator, findsOneWidget);
      expect(tester.getSize(indicator), const Size.square(AppSize.iconMd));
      await tester.tap(send);
      expect(submissions, 1);
      result.complete(false);
      await tester.pump();
      expect(key.currentState!.currentLine, 'the\ncat');
      expect(tester.widget<EditableText>(field).readOnly, isFalse);
      expect(indicator, findsNothing);
      for (final accepted in <bool>[false, true]) {
        result = Completer<bool>();
        await tester.tap(send);
        await tester.pump();
        expect(key.currentState!.currentLine, '');
        expect(tester.widget<EditableText>(field).readOnly, isFalse);
        await tester.enterText(field, 'next draft');
        await tester.pump();
        expect(lines.last, 'next draft');
        expect(key.currentState!.currentLine, 'next draft');
        expect(indicator, findsOneWidget);
        result.complete(accepted);
        await tester.pump();
        expect(key.currentState!.currentLine, 'next draft');
        expect(indicator, findsNothing);
      }
      result = Completer<bool>();
      await tester.tap(send);
      await tester.pump();
      result.complete(true);
      await tester.pump();
      expect(key.currentState!.currentLine, '');
      expect(focus.hasFocus, isTrue);
      key.currentState!.seedLine('stale');
      expect(key.currentState!.currentLine, '');
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets(
    'initial line and local deletion cannot be overwritten by a seed',
    (WidgetTester tester) async {
      final FocusNode focus = FocusNode();
      addTearDown(focus.dispose);
      final GlobalKey<ComposerState> key = GlobalKey<ComposerState>();
      final List<String> lines = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Composer(
              key: key,
              focusNode: focus,
              initialLine: 'initial',
              onLine: lines.add,
              onSubmit: (String line, {bool whenIdle = false}) async => true,
            ),
          ),
        ),
      );
      expect(key.currentState!.currentLine, 'initial');
      await tester.enterText(find.byType(EditableText), '');
      key.currentState!.seedLine('late host line');
      expect(key.currentState!.currentLine, '');
      expect(lines, <String>['']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('disabled Composer keeps its draft and cannot submit', (
    tester,
  ) async {
    final FocusNode focus = FocusNode();
    addTearDown(focus.dispose);
    int submitted = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Composer(
            focusNode: focus,
            enabled: false,
            initialLine: 'draft',
            onLine: (_) => fail('Disabled Composer emitted a line'),
            onSubmit: (String line, {bool whenIdle = false}) async {
              submitted++;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('composerSend')));
    await tester.pump();
    expect(submitted, 0);
    expect(focus.hasFocus, isFalse);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'draft',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('accepted key controls mirror the Host without line echoes', (
    tester,
  ) async {
    final FocusNode focus = FocusNode();
    addTearDown(focus.dispose);
    final GlobalKey<ComposerState> key = GlobalKey<ComposerState>();
    final List<String> lines = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Composer(
            key: key,
            focusNode: focus,
            initialLine: 'a👨‍👩‍👧',
            onLine: lines.add,
            onSubmit: (String line, {bool whenIdle = false}) async => true,
          ),
        ),
      ),
    );
    final ComposerState state = key.currentState!;
    state.applyAcceptedInput(
      const SendInput(paneId: 'p', keys: <String>['Backspace']),
    );
    expect(state.currentLine, 'a');
    for (final String text in <String>[
      '\x1b[2~',
      '\x1b[3~',
      '\x1b[H',
      '\x1b[F',
      '\x1b[5~',
      '\x1b[6~',
    ]) {
      state.applyAcceptedInput(SendInput(paneId: 'p', text: text));
    }
    state.applyAcceptedInput(
      const SendInput(paneId: 'p', keys: <String>['Up', 'Escape', 'ctrl+a']),
    );
    expect(state.currentLine, 'a');
    state.applyAcceptedInput(
      const SendInput(paneId: 'p', text: ' paste\ntext'),
    );
    expect(state.currentLine, 'a paste\ntext');
    state.applyAcceptedInput(
      const SendInput(paneId: 'p', keys: <String>['Enter']),
    );
    expect(state.currentLine, '');
    state.applyAcceptedInput(const SendInput(paneId: 'p', text: 'draft'));
    state.applyAcceptedInput(
      const SendInput(paneId: 'p', keys: <String>['ctrl+c', 'Backspace']),
    );
    expect(state.currentLine, '');
    expect(lines, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
