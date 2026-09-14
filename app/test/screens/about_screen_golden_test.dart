/// Golden tests for `AboutScreen` and its two licence pages (`app/lib/screens/about_screen.dart`,
/// `WP-21-b`), one per state row of `docs/31-mockups/19-about.md`'s `## States` table these
/// widgets paint (R-90-011): `Default` (the first wireframe, every row read at once because
/// every value is a build constant), `Index default` (the second wireframe) and `Detail
/// default` (the third). Rendered in both Selenized dark and light (R-32-012).
///
/// The two licence pages take the ground grid too since 2026-09-09 (R-03-107): the rows are one
/// paper block on it, the grid shows below the last row, and no brand mark and no eyebrow
/// follow them from `/settings/about`. Their goldens are the proof of that decision.
///
/// `AboutScreen` reads its version line from `PackageInfo.fromPlatform()`, an async platform
/// channel call `about_screen_test.dart` never mocks — in the test binding that call never
/// replies, so `_versionLine` stays `null` forever and the row would golden the `…` placeholder
/// instead of a real version. `PackageInfo.setMockInitialValues` (the package's own testing
/// entry point) makes the call resolve synchronously instead, so this file needs no second fake
/// scaffold for it.
///
/// Fonts, the app theme and the 375 x 667 reference size come from `golden_support.dart`
/// (`loadAppFonts`, `goldenApp`, `goldenReferenceSize`); see its doc comment for why.
/// `devicePixelRatio` stays fixed at 1.0.
library;

import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/widgets.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/screens/about_screen.dart';
import 'package:herdr_mobile/widgets/brand_mark.dart' show BrandMark;
import 'package:herdr_mobile/widgets/eyebrow.dart' show Eyebrow;
import 'package:herdr_mobile/widgets/ground_grid.dart' show GroundGrid;
import 'package:package_info_plus/package_info_plus.dart' show PackageInfo;

import 'golden_support.dart';

const _themes = <(String, Brightness)>[
  ('dark', Brightness.dark),
  ('light', Brightness.light),
];

void main() {
  setUpAll(loadAppFonts);

  setUp(() {
    // The mockup's own `1.0.0 (412)` value (R-31-19-02: semantic version, then the platform
    // build number in brackets). `LicenseRegistry.reset` mirrors `about_screen_test.dart`, even
    // though the default page's `Licences` row is a static label: the row's target route reads
    // the registry, and a leftover entry from another test file must not leak into this one.
    PackageInfo.setMockInitialValues(
      appName: 'Herdr Remote',
      packageName: 'herdr_mobile',
      version: '1.0.0',
      buildNumber: '412',
      buildSignature: '',
    );
    LicenseRegistry.reset();
  });
  tearDown(LicenseRegistry.reset);

  /// The mockup's own second wireframe: the app's own package first, then `Skia`, `go_router`
  /// and `xterm2` in case-insensitive alphabetical order, with `Skia` carrying three entries.
  void addSampleLicences() {
    LicenseRegistry.addLicense(
      () => Stream<LicenseEntryWithLineBreaks>.fromIterable(
        const <LicenseEntryWithLineBreaks>[
          LicenseEntryWithLineBreaks(<String>['xterm2'], 'The xterm2 licence.'),
          LicenseEntryWithLineBreaks(<String>['Skia'], 'Skia licence one.'),
          LicenseEntryWithLineBreaks(<String>['go_router'], 'BSD licence.'),
          LicenseEntryWithLineBreaks(<String>['Skia'], 'Skia licence two.'),
          LicenseEntryWithLineBreaks(
            <String>['herdr_mobile'],
            'Apache License\nVersion 2.0, January 2004\n'
            'http://www.apache.org/licenses/\n\n'
            'TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION\n\n'
            '1. Definitions.',
          ),
          LicenseEntryWithLineBreaks(<String>['Skia'], 'Skia licence three.'),
        ],
      ),
    );
  }

  for (final (themeName, brightness) in _themes) {
    testWidgets('default ($themeName) matches docs/31-mockups/19-about.md', (
      tester,
    ) async {
      tester.view.physicalSize = goldenReferenceSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        goldenApp(brightness: brightness, child: const AboutScreen()),
      );
      await tester.pumpAndSettle();

      // Structural proof alongside the visual one: every callout the mockup names is really
      // present in the tree, not just painted to look right by coincidence.
      expect(find.text('About'), findsOneWidget);
      expect(find.text('Herdr Remote'), findsOneWidget);
      expect(find.text('1.0.0 (412)'), findsOneWidget);
      expect(find.text('Herdr protocol targeted'), findsOneWidget);
      expect(find.text(targetedHerdrProtocol.toString()), findsOneWidget);
      expect(find.text('Licences'), findsOneWidget);
      expect(find.text('This app: Apache-2.0'), findsOneWidget);

      await expectLater(
        find.byType(AboutScreen),
        matchesGoldenFile('goldens/about_screen_default_$themeName.png'),
      );
    });

    testWidgets(
      'licence index ($themeName) matches docs/31-mockups/19-about.md',
      (tester) async {
        tester.view.physicalSize = goldenReferenceSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addSampleLicences();

        await tester.pumpWidget(
          goldenApp(
            brightness: brightness,
            child: LicenceIndexScreen(onOpenPackage: (_) {}),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Licences'), findsOneWidget);
        expect(find.text('Herdr Remote'), findsOneWidget);
        expect(find.text('Skia'), findsOneWidget);
        expect(find.text('3 licences'), findsOneWidget);
        expect(find.text('go_router'), findsOneWidget);
        expect(find.text('xterm2'), findsOneWidget);
        // R-03-107 (amended 2026-09-09): a list page has content, so no grid.
        expect(find.byType(GroundGrid), findsNothing);
        expect(find.byType(BrandMark), findsNothing);
        expect(find.byType(Eyebrow), findsNothing);

        await expectLater(
          find.byType(LicenceIndexScreen),
          matchesGoldenFile('goldens/licence_index_screen_$themeName.png'),
        );
      },
    );

    testWidgets(
      'licence detail ($themeName) matches docs/31-mockups/19-about.md',
      (tester) async {
        tester.view.physicalSize = goldenReferenceSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addSampleLicences();
        final List<LicensedPackage> packages = await loadLicensedPackages();
        final LicensedPackage own = packages.first;

        await tester.pumpWidget(
          goldenApp(
            brightness: brightness,
            child: LicenceDetailScreen(
              packageName: own.displayName,
              entries: own.entries,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Herdr Remote'), findsOneWidget);
        expect(find.text('1 licence'), findsOneWidget);
        expect(find.textContaining('Apache License'), findsOneWidget);
        expect(find.byType(GroundGrid), findsNothing);
        expect(find.byType(BrandMark), findsNothing);
        expect(find.byType(Eyebrow), findsNothing);

        await expectLater(
          find.byType(LicenceDetailScreen),
          matchesGoldenFile('goldens/licence_detail_screen_$themeName.png'),
        );
      },
    );
  }
}
