import 'package:flutter/widgets.dart' show Brightness, SizedBox, Text;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/widgets/status_strip.dart';

import '../screens/golden_support.dart' show goldenApp;

void main() {
  testWidgets('live RTT uses milliseconds and an accessible description', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    // The test disposes semantics before Flutter checks its handles.
    await tester.pumpWidget(
      goldenApp(
        brightness: Brightness.dark,
        child: StatusStrip(
          columns: 80,
          rows: 24,
          revision: 1,
          scrollOffsetFromBottom: 0,
          scrollMaxOffsetFromBottom: 0,
          linkWord: StatusStripLinkWord.live,
          overview: false,
          onToggleOverview: () {},
          rtt: const Duration(milliseconds: 123),
        ),
      ),
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            (widget.textSpan
                    ?.toPlainText(includeSemanticsLabels: false)
                    .contains('123 MS') ??
                false),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('Round trip 123 milliseconds')),
      findsOneWidget,
    );
    expect(find.textContaining('LIVE'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  for (final state in StatusStripLinkWord.values) {
    testWidgets('${state.name} keeps its label without a live RTT', (
      tester,
    ) async {
      await tester.pumpWidget(
        goldenApp(
          brightness: Brightness.dark,
          child: StatusStrip(
            columns: 80,
            rows: 24,
            revision: 1,
            scrollOffsetFromBottom: 0,
            scrollMaxOffsetFromBottom: 0,
            linkWord: state,
            overview: false,
            onToggleOverview: () {},
            rtt: state == StatusStripLinkWord.live
                ? null
                : const Duration(milliseconds: 123),
          ),
        ),
      );
      expect(find.textContaining(state.label.toUpperCase()), findsOneWidget);
      expect(find.textContaining('123 MS'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
