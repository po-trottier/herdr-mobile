/// Tests `LicenceIndexScreen` (`app/lib/screens/about_screen.dart`, `WP-21-b`): an empty
/// licence list is the `Bundle failed` error state, never an empty state (R-31-19-14.1).
/// Also covers `AboutScreen`/`LicenceIndexScreen`/`LicenceDetailScreen`'s content guarantees:
/// the protocol row is a build constant (R-31-19-03), nothing here ever depends on
/// connectivity (R-31-19-07), and the screen leaks no relay identity (R-31-19-08), no
/// telemetry/device identifier (R-31-19-09), no NVIDIA branding (R-31-19-10), and offers no
/// copy/share/update/rate/feedback action (R-31-19-12).
library;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoNavigationBar;
import 'package:flutter/foundation.dart'
    show
        LicenseEntry,
        LicenseEntryWithLineBreaks,
        LicenseRegistry,
        TargetPlatform,
        debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart' show Opacity, Text;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/screens/about_screen.dart';
import 'package:material_ui/material_ui.dart' show AppBar, MaterialApp;

/// Every rendered `Text`'s string data, lower-cased, for a substring-absence assertion.
String _renderedText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? '')
    .join(' ')
    .toLowerCase();

void main() {
  setUp(LicenseRegistry.reset);
  tearDown(LicenseRegistry.reset);

  testWidgets(
    'iOS: AboutScreen renders CupertinoNavigationBar with the About title, not AppBar',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
      await tester.pump();

      expect(find.byType(CupertinoNavigationBar), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('About'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'iOS: LicenceIndexScreen renders CupertinoNavigationBar with the Licences title, not AppBar',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await tester.pumpWidget(const MaterialApp(home: LicenceIndexScreen()));
      await tester.pump();

      expect(find.byType(CupertinoNavigationBar), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('Licences'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'iOS: LicenceDetailScreen renders CupertinoNavigationBar with the package name, not AppBar',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await tester.pumpWidget(
        const MaterialApp(
          home: LicenceDetailScreen(
            packageName: 'herdr_mobile',
            entries: <LicenseEntry>[
              LicenseEntryWithLineBreaks(<String>[
                'herdr_mobile',
              ], 'Apache License\nVersion 2.0, January 2004'),
            ],
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CupertinoNavigationBar), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('herdr_mobile'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'an empty licence list shows the bundle-failed error, not an empty state (R-31-19-14.1)',
    (tester) async {
      // No `LicenseRegistry.addLicense` call at all: `licenses` yields nothing, exactly the
      // "missing or unparseable NOTICES" failure this rule folds into one state.
      await tester.pumpWidget(const MaterialApp(home: LicenceIndexScreen()));
      await tester.pumpAndSettle();

      expect(find.text('The licence list did not load.'), findsOneWidget);
      expect(find.text('Unable to load asset: NOTICES'), findsOneWidget);
      expect(
        find.text(
          'This build shipped without its attributions. No action here can repair it.',
        ),
        findsOneWidget,
      );
      // R-31-19-14.3: no retry control anywhere on this state.
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Try again'), findsNothing);
    },
  );

  testWidgets(
    'a non-empty licence list shows the package index, with this app first (R-31-19-05)',
    (tester) async {
      LicenseRegistry.addLicense(
        () => Stream<LicenseEntryWithLineBreaks>.fromIterable(
          <LicenseEntryWithLineBreaks>[
            const LicenseEntryWithLineBreaks(<String>[
              'xterm2',
            ], 'The xterm2 licence text.'),
            const LicenseEntryWithLineBreaks(<String>[
              'herdr_mobile',
            ], 'Apache License\nVersion 2.0, January 2004\n\nFull text.'),
          ],
        ),
      );

      await tester.pumpWidget(const MaterialApp(home: LicenceIndexScreen()));
      await tester.pumpAndSettle();

      expect(find.text('The licence list did not load.'), findsNothing);
      expect(find.text('Herdr Remote'), findsOneWidget);
      expect(find.text('xterm2'), findsOneWidget);

      // The app's own package sorts first regardless of alphabetical order against "xterm2".
      final herdrOffset = tester.getTopLeft(find.text('Herdr Remote')).dy;
      final xtermOffset = tester.getTopLeft(find.text('xterm2')).dy;
      expect(herdrOffset, lessThan(xtermOffset));
    },
  );

  testWidgets(
    'tapping a package row opens its detail with the licence text (R-31-19-15.2)',
    (tester) async {
      LicenseRegistry.addLicense(
        () => Stream<LicenseEntryWithLineBreaks>.value(
          const LicenseEntryWithLineBreaks(<String>[
            'herdr_mobile',
          ], 'Apache License\nVersion 2.0, January 2004'),
        ),
      );

      LicensedPackage? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: LicenceIndexScreen(
            onOpenPackage: (package) => opened = package,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Herdr Remote'));
      expect(opened, isNotNull);
      expect(opened!.name, 'herdr_mobile');
      expect(opened!.displayName, 'Herdr Remote');
      expect(opened!.entries, hasLength(1));
    },
  );

  testWidgets(
    'the protocol row shows the build constant, never a live connection reading (R-31-19-03)',
    (tester) async {
      // `AboutScreen` takes no connection stream or state of any kind (unlike
      // `connection_screen.dart`'s `RelayConnectionState`-driven rows): the only value this
      // row can ever show is the compile-time `targetedHerdrProtocol` constant.
      await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Herdr protocol targeted'), findsOneWidget);
      expect(find.text('$targetedHerdrProtocol'), findsOneWidget);
    },
  );

  testWidgets('the about screen and both licence pages render unchanged with no connectivity wiring '
      'at all (R-31-19-07)', (tester) async {
    // Unlike `settings_screen.dart` and `host_list_screen.dart`, none of these three
    // widgets imports `connectivity_plus` or takes a connection/offline parameter, so no
    // simulated offline state can ever strip, dim, or disable anything here — the same
    // full content renders regardless.
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(home: AboutScreen(onOpenLicences: () => tapped = true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Licences'), findsOneWidget);
    expect(find.byType(Opacity), findsNothing);
    await tester.tap(find.text('Licences'));
    expect(tapped, isTrue);

    LicenseRegistry.addLicense(
      () => Stream<LicenseEntryWithLineBreaks>.value(
        const LicenseEntryWithLineBreaks(<String>[
          'herdr_mobile',
        ], 'Full text.'),
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: LicenceIndexScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Herdr Remote'), findsOneWidget);
    expect(find.byType(Opacity), findsNothing);

    await tester.pumpWidget(
      const MaterialApp(
        home: LicenceDetailScreen(
          packageName: 'herdr_mobile',
          entries: [
            LicenseEntryWithLineBreaks(<String>['herdr_mobile'], 'Full text.'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Full text.'), findsOneWidget);
    expect(find.byType(Opacity), findsNothing);
  });

  testWidgets('the about screen shows no relay origin, routing handle, pairing phrase, static key, or '
      'key fingerprint (R-31-19-08)', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
    await tester.pumpAndSettle();

    final text = _renderedText(tester);
    for (final forbidden in <String>[
      'relay origin',
      'routing handle',
      'pairing phrase',
      'static key',
      'fingerprint',
    ]) {
      expect(text, isNot(contains(forbidden)));
    }
  });

  testWidgets('no analytics, crash-report, install, or device identifier renders anywhere on the '
      'about screen (R-31-19-09)', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
    await tester.pumpAndSettle();

    final text = _renderedText(tester);
    for (final forbidden in <String>[
      'analytics',
      'crash report',
      'crash-report',
      'install id',
      'device id',
      'device identifier',
    ]) {
      expect(text, isNot(contains(forbidden)));
    }
  });

  testWidgets('no NVIDIA name, mark, logo, endpoint, or copyright line renders on the about screen '
      '(R-31-19-10)', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
    await tester.pumpAndSettle();

    final text = _renderedText(tester);
    expect(text, isNot(contains('nvidia')));
    expect(text, isNot(contains('©')));
    expect(text, isNot(contains('copyright')));
  });

  testWidgets('the about screen offers no copy, share, update-check, rate, or feedback action '
      '(R-31-19-12)', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
    await tester.pumpAndSettle();

    final text = _renderedText(tester);
    for (final forbidden in <String>[
      'copy',
      'share',
      'check for update',
      'update available',
      'rate',
      'feedback',
    ]) {
      expect(text, isNot(contains(forbidden)));
    }
  });
}
