/// Tests `NotificationSettingsScreenBody` (`app/lib/screens/notification_settings_screen.dart`,
/// `WP-19-b`): the pure presentation renders platform-correct chrome per
/// `docs/33-platform-chrome.md` — a `CupertinoNavigationBar` on iOS, a Material `AppBar` on
/// Android, for both the screen's own app bar and the test-alert row (`_testAlertRow`).
library;

import 'package:cupertino_ui/cupertino_ui.dart'
    show
        CupertinoActivityIndicator,
        CupertinoListTile,
        CupertinoNavigationBar,
        CupertinoSwitch;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart' show Brightness, CustomScrollView, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/screens/notification_settings_screen.dart'
    show NotificationSettingsPhase, NotificationSettingsScreenBody;
import 'package:herdr_mobile/services/notifications.dart'
    show NotificationSettings;
import 'package:herdr_mobile/widgets/ground_grid.dart' show GroundGrid;
import 'package:herdr_mobile/widgets/theme/app_color.dart' show AppColor;
import 'package:material_ui/material_ui.dart'
    show
        AppBar,
        CircularProgressIndicator,
        ColoredBox,
        ListTile,
        Material,
        MaterialApp,
        Opacity,
        Switch;

NotificationSettingsScreenBody _body({
  NotificationSettingsPhase phase = NotificationSettingsPhase.normal,
  bool isSendingTestAlert = false,
}) => NotificationSettingsScreenBody(
  phase: phase,
  settings: const NotificationSettings(),
  savingSettings: const {},
  isSendingTestAlert: isSendingTestAlert,
  onAgentBlockedChanged: (bool _) {},
  onAgentDoneChanged: (bool _) {},
  onOnlyOpenedAgentsChanged: (bool _) {},
  onHoldAlertsChanged: (bool _) {},
  onQuietHoursTap: () {},
  onSendTestAlert: () {},
  onOpenSystemSettings: () {},
);

void main() {
  /// A `color.bg.base` paper block inside the scroll view: R-03-107 (amended 2026-09-09)
  /// forbids it on a screen with content.
  final Finder paper = find.descendant(
    of: find.byType(CustomScrollView),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is ColoredBox &&
          widget.color == AppColor.resolve(Brightness.light).bgBase,
    ),
  );

  /// A surface tall enough for the whole list, so every lazily built block exists.
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      '$platform uses native switches and a native test-alert indicator',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        useTallSurface(tester);
        await tester.pumpWidget(
          MaterialApp(home: Material(child: _body(isSendingTestAlert: true))),
        );
        await tester.pump();
        final isIos = platform == TargetPlatform.iOS;
        expect(find.byType(isIos ? CupertinoSwitch : Switch), findsNWidgets(4));
        expect(find.byType(isIos ? Switch : CupertinoSwitch), findsNothing);
        expect(
          find.byType(
            isIos ? CupertinoActivityIndicator : CircularProgressIndicator,
          ),
          findsOneWidget,
        );
        expect(
          find.byType(
            isIos ? CircularProgressIndicator : CupertinoActivityIndicator,
          ),
          findsNothing,
        );
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
  testWidgets(
    'Android: a Material AppBar titled Alerts, no CupertinoNavigationBar',
    (tester) async {
      await tester.pumpWidget(MaterialApp(home: _body()));
      await tester.pump();
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Alerts'), findsOneWidget);
      expect(find.byType(CupertinoNavigationBar), findsNothing);
    },
  );

  testWidgets(
    'iOS: a CupertinoNavigationBar titled Alerts, no Material AppBar',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await tester.pumpWidget(MaterialApp(home: Material(child: _body())));
      await tester.pump();
      expect(find.byType(CupertinoNavigationBar), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(CupertinoNavigationBar),
          matching: find.text('Alerts'),
        ),
        findsOneWidget,
        reason: 'the navigation bar middle carries the screen title',
      );
      expect(find.text('Alerts'), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'iOS: the test-alert row is a CupertinoListTile, not a Material ListTile',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      // Each block is its own lazily built list child now, and the test row sits below the
      // default fold.
      useTallSurface(tester);
      await tester.pumpWidget(
        MaterialApp(home: Material(child: _body(isSendingTestAlert: false))),
      );
      await tester.pump();
      expect(find.text('Send a test alert'), findsOneWidget);
      expect(find.byType(CupertinoListTile), findsAtLeastNWidgets(1));
      expect(find.byType(ListTile), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('the body is plain color.bg.base: no ground grid and no paper block under any text '
      '(R-03-107, amended 2026-09-09)', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(MaterialApp(home: Material(child: _body())));
    await tester.pump();

    expect(find.byType(GroundGrid), findsNothing);
    expect(paper, findsNothing);
    for (final Finder text in <Finder>[
      find.textContaining('Alerts arrive while the app is running.'),
      find.text('WHEN TO ALERT ME'),
      find.text('WHICH AGENTS'),
      find.text('QUIET HOURS'),
      find.text('Send a test alert'),
      find.textContaining('It never carries pane text.'),
    ]) {
      expect(text, findsOneWidget);
    }
  });

  testWidgets('permission denied dims the groups (callout 89)', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: _body(phase: NotificationSettingsPhase.permissionDenied),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.ancestor(
        of: find.text('WHEN TO ALERT ME'),
        matching: find.byType(Opacity),
      ),
      findsOneWidget,
    );
  });
}
