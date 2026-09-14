/// Asserts the app's platform identity strings and version floors that
/// `docs/23-platform-integration.md` fixes: the display name (R-23-001),
/// the bundle/application id (R-23-002), the iOS deployment target
/// (R-23-054) and the Android `minSdk`/`targetSdk` pair (R-23-055,
/// R-23-056). These values live in platform project files
/// (`AndroidManifest.xml`, `Info.plist`, `build.gradle.kts`,
/// `project.pbxproj`), not in any Dart source Flutter's analyzer would
/// otherwise cover, so nothing previously asserted them: a manifest edit
/// that silently drifted from the rule would ship undetected.
///
/// This is a static text scan, not a manifest/plist parser:
/// `docs/41-code-standards.md` R-41-042 forbids a new dependency before
/// the reuse ladder is climbed, and a `RegExp` match on the known,
/// hand-authored file layout needs none. Mirrors `app/tool/check_notices.dart`'s
/// plain `File`/`RegExp` pattern for parsing a project file as text.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('platform identity strings', () {
    test('AndroidManifest.xml android:label is "Herdr Remote" (R-23-001)', () {
      final String manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      expect(manifest, contains('android:label="Herdr Remote"'));
    });

    test('Info.plist CFBundleDisplayName is "Herdr Remote" (R-23-001)', () {
      final String plist = File('ios/Runner/Info.plist').readAsStringSync();
      final RegExp displayName = RegExp(
        r'<key>CFBundleDisplayName</key>\s*<string>([^<]*)</string>',
      );
      final Match? match = displayName.firstMatch(plist);
      expect(
        match,
        isNotNull,
        reason: 'CFBundleDisplayName key not found in Info.plist',
      );
      expect(match!.group(1), 'Herdr Remote');
    });

    test('build.gradle.kts applicationId is "dev.herdr.remote" (R-23-002)', () {
      final String gradle = File('android/app/build.gradle.kts')
          .readAsStringSync();
      expect(gradle, contains('applicationId = "dev.herdr.remote"'));
    });

    test('project.pbxproj PRODUCT_BUNDLE_IDENTIFIER is "dev.herdr.remote" for the Runner '
        'target (R-23-002)', () {
      final String pbxproj = File('ios/Runner.xcodeproj/project.pbxproj')
          .readAsStringSync();
      expect(
        pbxproj,
        contains('PRODUCT_BUNDLE_IDENTIFIER = dev.herdr.remote;'),
      );
    });
  });

  group('platform version floors', () {
    test('project.pbxproj IPHONEOS_DEPLOYMENT_TARGET is 15.0 (R-23-054)', () {
      final String pbxproj = File('ios/Runner.xcodeproj/project.pbxproj')
          .readAsStringSync();
      expect(pbxproj, contains('IPHONEOS_DEPLOYMENT_TARGET = 15.0;'));
    });

    test('build.gradle.kts minSdk is 33 (R-23-055)', () {
      final String gradle = File('android/app/build.gradle.kts')
          .readAsStringSync();
      expect(gradle, contains('minSdk = 33'));
    });

    test('build.gradle.kts targetSdk is 36 (R-23-056)', () {
      final String gradle = File('android/app/build.gradle.kts')
          .readAsStringSync();
      expect(gradle, contains('targetSdk = 36'));
    });
  });
}
