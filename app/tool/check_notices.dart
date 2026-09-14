// Build-time-only dev tool for `WP-21-b`, self-declared under Phase 21's `Owns.` line
// (R-90-018: no earlier phase named this path). Fails the build when the app's own
// attribution would silently be missing from a shipped app (R-31-19-14 group, R-23-060,
// R-03-021).
//
// The Flutter tool's own license collector (`package:flutter_tools/src/license_collector.dart`
// at the pinned 3.47.0, not a published API this app can import) silently skips a package
// whose `LICENSE` file is missing — a plain `continue`, no error, no warning — so a deleted or
// misplaced `app/LICENSE` would ship a real app with `LicenseRegistry` never carrying this
// project's own Apache-2.0 entry, and `about_screen.dart`'s licence index would simply lose
// its first row rather than fail loudly. This script reimplements the one check that matters
// for this repository's own attribution (not third-party packages, which pub.dev already
// requires to ship a `LICENSE`): that `app/LICENSE` exists and parses as a real Apache-2.0
// notice.
//
// Run with: `dart run tool/check_notices.dart` from `app/`, before `flutter build` (any
// target, debug or release) — wired into `.github/workflows/ci.yml`'s `flutter` job
// (`WP-0-a`'s path, `on request` per `docs/90-implementation-plan.md` §5.3).
//
// This script never ships: `app/tool/` sits outside `app/lib/`, mirroring
// `fetch_eff_wordlist.dart`'s own scope note.

import 'dart:io';

/// The 80-hyphen separator `license_collector.dart`'s own doc comment fixes between
/// component licenses inside one `LICENSE` file. `app/LICENSE` (the plain, single-component
/// Apache-2.0 text `docs/03-product-decisions.md` R-03-020 owns) carries none of these, but a
/// future multi-component file would, so this script checks the first component only, per
/// the collector's own fallback rule for a file with no separator.
final RegExp _licenseSeparator = RegExp('\n-{80}\n');

void main() {
  final file = File('LICENSE');
  if (!file.existsSync()) {
    stderr.writeln(
      'check_notices: app/LICENSE is missing. LicenseRegistry would ship with no entry '
      'for this project (R-31-19-05, R-23-060).',
    );
    exit(1);
  }
  final String text;
  try {
    text = file.readAsStringSync();
  } on FileSystemException catch (e) {
    stderr.writeln('check_notices: could not read app/LICENSE: $e');
    exit(1);
  }
  final String firstComponent = text.split(_licenseSeparator).first.trim();
  if (firstComponent.isEmpty ||
      !firstComponent.contains('Apache License') ||
      !firstComponent.contains('Version 2.0')) {
    stderr.writeln(
      'check_notices: app/LICENSE does not parse as an Apache License 2.0 notice '
      '(R-03-020, R-03-021). Found ${firstComponent.length} characters in its first '
      'component.',
    );
    exit(1);
  }
  stdout.writeln(
    'check_notices: app/LICENSE present and parses (R-31-19-14 group).',
  );
}
