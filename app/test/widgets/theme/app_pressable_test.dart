/// `AppPressable` (`app/lib/widgets/theme/app_pressable.dart`), the value
/// side of `docs/32-design-language.md` R-32-609: pointer-down scales to
/// `motion.scale.press` over `motion.duration.fast`, release snaps back at
/// `motion.duration.instant`, a quick tap holds one full press, reduce
/// motion drops the scale, `onTap` null attaches nothing, and a focused
/// control shows the ring of R-32-503 and activates on Enter.
library;

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart'
    show
        AnimatedScale,
        BoxDecoration,
        BuildContext,
        DecoratedBox,
        Directionality,
        Focus,
        MediaQuery,
        MediaQueryData,
        Rect,
        SizedBox,
        Text,
        TextDirection,
        Widget;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/widgets/theme/app_motion.dart';
import 'package:herdr_mobile/widgets/theme/app_pressable.dart';

Widget _host(Widget child, {bool disableAnimations = false}) => MediaQuery(
  data: MediaQueryData(disableAnimations: disableAnimations),
  child: Directionality(textDirection: TextDirection.ltr, child: child),
);

Widget _pressable({
  void Function()? onTap,
  void Function({required bool pressed})? onBuild,
}) => AppPressable(
  onTap: onTap,
  builder: (BuildContext context, bool pressed) {
    onBuild?.call(pressed: pressed);
    return const SizedBox(width: 200, height: 48, child: Text('Go'));
  },
);

AnimatedScale _scale(WidgetTester tester) =>
    tester.widget<AnimatedScale>(find.byType(AnimatedScale));

void main() {
  testWidgets(
    'pointer-down scales to motion.scale.press over motion.duration.fast with '
    'motion.curve.enter; release snaps back at motion.duration.instant',
    (WidgetTester tester) async {
      bool? lastPressed;
      await tester.pumpWidget(
        _host(
          _pressable(
            onTap: () {},
            onBuild: ({required bool pressed}) => lastPressed = pressed,
          ),
        ),
      );
      expect(_scale(tester).scale, 1);
      expect(lastPressed, isFalse);

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.text('Go')),
      );
      await tester.pump();
      expect(_scale(tester).scale, AppMotion.scalePress);
      expect(_scale(tester).duration, AppMotion.durationFast);
      expect(_scale(tester).curve, AppMotion.curveEnter);
      expect(lastPressed, isTrue, reason: 'the builder sees the press');

      // Past the press-in, the release lands at once and snaps.
      await tester.pump(AppMotion.durationFast);
      await gesture.up();
      await tester.pump();
      expect(_scale(tester).scale, 1);
      expect(_scale(tester).duration, AppMotion.durationInstant);
      expect(lastPressed, isFalse);
    },
  );

  testWidgets(
    'a tap shorter than motion.duration.fast stays pressed until the press-in '
    'has run, then releases',
    (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(_host(_pressable(onTap: () => taps++)));

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.text('Go')),
      );
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(taps, 1, reason: 'the tap itself is not delayed');
      expect(
        _scale(tester).scale,
        AppMotion.scalePress,
        reason: 'the press stays visible for the rest of the press-in',
      );

      await tester.pump(AppMotion.durationFast);
      expect(_scale(tester).scale, 1);
    },
  );

  testWidgets('a cancelled press lets go at once', (WidgetTester tester) async {
    await tester.pumpWidget(_host(_pressable(onTap: () {})));
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.text('Go')),
    );
    await tester.pump();
    expect(_scale(tester).scale, AppMotion.scalePress);

    await gesture.cancel();
    await tester.pump();
    expect(_scale(tester).scale, 1);
  });

  testWidgets(
    'reduce motion: no scale, and the builder still sees the press so the fill '
    'can change instantly (R-32-606)',
    (WidgetTester tester) async {
      bool? lastPressed;
      await tester.pumpWidget(
        _host(
          _pressable(
            onTap: () {},
            onBuild: ({required bool pressed}) => lastPressed = pressed,
          ),
          disableAnimations: true,
        ),
      );
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.text('Go')),
      );
      await tester.pump();
      expect(_scale(tester).scale, 1);
      expect(_scale(tester).duration, AppMotion.durationInstant);
      expect(lastPressed, isTrue);
      await tester.pump(AppMotion.durationFast);
      await gesture.up();
      await tester.pump();
    },
  );

  testWidgets('onTap null: no press, no focus, and the tap goes nowhere', (
    WidgetTester tester,
  ) async {
    bool? lastPressed;
    await tester.pumpWidget(
      _host(
        _pressable(onBuild: ({required bool pressed}) => lastPressed = pressed),
      ),
    );
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.text('Go')),
    );
    await tester.pump();
    expect(lastPressed, isFalse);
    expect(_scale(tester).scale, 1);
    await gesture.up();
    await tester.pump();

    final Focus focus = tester.widget<Focus>(
      find.descendant(
        of: find.byType(AppPressable),
        matching: find.byType(Focus),
      ),
    );
    expect(focus.canRequestFocus, isFalse);
    expect(focus.skipTraversal, isTrue);
  });

  testWidgets(
    'focus draws the border.focus ring outside the control without moving it, '
    'and Enter activates (R-32-503, R-30-718)',
    (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(_host(_pressable(onTap: () => taps++)));

      bool isRing(Widget w) =>
          w is DecoratedBox &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).border != null;
      final Finder ring = find.byWidgetPredicate(isRing);
      expect(ring, findsNothing);
      final Rect before = tester.getRect(find.text('Go'));

      Focus.of(tester.element(find.text('Go'))).requestFocus();
      // The focus change lands in a microtask and then schedules a frame.
      await tester.pump();
      await tester.pump();

      expect(ring, findsOneWidget);
      expect(
        tester.getRect(find.text('Go')),
        before,
        reason: 'the ring adds nothing to layout',
      );
      final Rect control = tester.getRect(find.byType(AnimatedScale));
      final double ringWidth =
          (tester.widget<DecoratedBox>(ring).decoration as BoxDecoration)
              .border!
              .top
              .width;
      expect(tester.getRect(ring), control.inflate(ringWidth));

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(taps, 1);
    },
  );
}
