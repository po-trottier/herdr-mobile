/// `StatusBar`, `docs/32-design-language.md` section 7.29 (`State bar`), per
/// R-03-100: one `border.attention` wide bar per state in the state's hue,
/// `working` pulses, reduce-motion holds it static at full opacity, and a
/// stretched `Row` gives it the row's full height.
library;

import 'package:flutter/widgets.dart'
    show
        Center,
        Color,
        ColoredBox,
        CrossAxisAlignment,
        Directionality,
        IntrinsicHeight,
        ListView,
        FadeTransition,
        MediaQuery,
        MediaQueryData,
        Row,
        SizedBox,
        TextDirection,
        Widget;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/widgets/status_bar.dart';
import 'package:herdr_mobile/widgets/theme/app_color.dart';
import 'package:herdr_mobile/widgets/theme/app_radius.dart' show AppBorder;
import 'package:herdr_mobile/widgets/theme/app_size.dart';

Widget _host(Widget child, {bool disableAnimations = false}) => MediaQuery(
  data: MediaQueryData(disableAnimations: disableAnimations),
  child: Directionality(textDirection: TextDirection.ltr, child: child),
);

void main() {
  const AppColor light = AppColor.light;
  final Map<BarState, Color> hue = <BarState, Color>{
    BarState.working: light.statusWorking,
    BarState.idle: light.statusIdle,
    BarState.blocked: light.statusBlocked,
    BarState.done: light.statusDone,
    BarState.error: light.statusError,
    BarState.warning: light.statusWarning,
    BarState.unknown: light.statusUnknown,
    BarState.ok: light.statusOk,
  };

  for (final BarState state in BarState.values) {
    testWidgets('${state.name} is one border.attention bar in its hue', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          Center(
            child: StatusBar(state: state, height: AppSize.rowTwoLine),
          ),
        ),
      );
      expect(find.byType(ColoredBox), findsOneWidget);
      final ColoredBox box = tester.widget(find.byType(ColoredBox));
      expect(box.color, hue[state]);
      expect(
        tester.getSize(find.byType(ColoredBox)).width,
        AppBorder.attention,
      );
      expect(
        find.byType(FadeTransition),
        state == BarState.working ? findsOneWidget : findsNothing,
      );
    });
  }

  testWidgets('working pulses', (tester) async {
    await tester.pumpWidget(
      _host(
        const Center(child: StatusBar(state: BarState.working, height: 10)),
      ),
    );
    final FadeTransition fade = tester.widget(find.byType(FadeTransition));
    final double before = fade.opacity.value;
    await tester.pump(const Duration(milliseconds: 1100));
    expect(fade.opacity.value, isNot(before), reason: 'the pulse animates');
  });

  testWidgets('reduce motion holds working static at full opacity', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const Center(child: StatusBar(state: BarState.working, height: 10)),
        disableAnimations: true,
      ),
    );
    expect(find.byType(FadeTransition), findsNothing);
    expect(
      tester.widget<ColoredBox>(find.byType(ColoredBox)).color,
      light.statusWorking,
    );
  });

  testWidgets('a stretched row in a list gives the bar the full row height', (
    tester,
  ) async {
    // A list gives its rows no height, so a stretched `Row` needs
    // `IntrinsicHeight`: the row is then as tall as its text and the bar
    // follows it.
    await tester.pumpWidget(
      _host(
        ListView(
          children: const <Widget>[
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  StatusBar(state: BarState.done),
                  SizedBox(width: 20, height: AppSize.rowTwoLine),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    expect(tester.getSize(find.byType(StatusBar)).height, AppSize.rowTwoLine);
    expect(tester.getSize(find.byType(StatusBar)).width, AppBorder.attention);
  });
}
