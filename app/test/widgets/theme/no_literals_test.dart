/// Fails when a hard-coded colour, font size or duration appears in a
/// widget under `app/lib/screens/` or `app/lib/widgets/`, outside
/// `app/lib/widgets/theme/`, per `docs/30-ux-spec.md` R-30-102,
/// `docs/41-code-standards.md` R-41-111 and `docs/32-design-language.md`
/// R-32-005, R-32-110 and R-32-120. These rules bind **a widget**,
/// not the whole `app/lib/` tree: a service file such as
/// `app/lib/services/reconnect_policy.dart` (a network backoff schedule)
/// or `app/lib/services/biometric_gate.dart` (a security re-auth window,
/// whose own doc comment states it "has no widget tree and paints
/// nothing") assigns a duration to a well-named constant for a protocol
/// or security reason, not a perceived motion value, so it is not this
/// rule's target and forcing it into `docs/32-design-language.md`'s
/// `motion.duration.*` catalogue would be a category error. Every value
/// MUST come from a named token instead.
///
/// This is a static scan, not an analyser plugin: `docs/41-code-standards.md`
/// R-41-042 forbids a new dependency before the reuse ladder is climbed,
/// and a `RegExp` scan needs none. The scan reports every offending file
/// and line together, so a later package that adds a new file under
/// `app/lib/screens/` or `app/lib/widgets/` is caught the same way
/// without editing this test.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The directories that hold widgets, per R-30-102 and R-41-111's literal
/// "a widget" scope. `app/lib/services/` and `app/lib/models/` are
/// deliberately excluded: neither paints, per this codebase's own
/// file-role convention.
const List<String> _widgetRoots = <String>['lib/screens', 'lib/widgets'];

/// Files and directories under `lib/widgets/` allowed to hold the raw
/// literal a token file defines. `chrome.dart` (`WP-12-c`) also resolves
/// a token from a literal per platform brightness, so the whole `theme/`
/// directory is exempt, not only this package's four files.
const String _tokenDirectory = 'lib/widgets/theme';

final RegExp _colorLiteral = RegExp(r'Color\(\s*0x[0-9A-Fa-f]{6,8}\s*\)');
final RegExp _fontSizeLiteral = RegExp(r'\bfontSize\s*:\s*[0-9]');
final RegExp _durationLiteral = RegExp(
  r'Duration\(\s*(?:days|hours|minutes|seconds|milliseconds|microseconds)\s*:\s*[0-9]',
);

class _Violation {
  const _Violation(this.path, this.lineNumber, this.line, this.rule);

  final String path;
  final int lineNumber;
  final String line;
  final String rule;

  @override
  String toString() => '$path:$lineNumber: $rule literal: ${line.trim()}';
}

List<_Violation> _scan(List<String> roots) {
  final violations = <_Violation>[];
  for (final rootPath in roots) {
    final root = Directory(rootPath);
    if (!root.existsSync()) {
      continue;
    }
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final normalizedPath = entity.path.replaceAll(r'\', '/');
      if (normalizedPath.contains('$_tokenDirectory/')) {
        continue;
      }
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (_colorLiteral.hasMatch(line)) {
          violations.add(_Violation(normalizedPath, i + 1, line, 'colour'));
        }
        if (_fontSizeLiteral.hasMatch(line)) {
          violations.add(_Violation(normalizedPath, i + 1, line, 'font size'));
        }
        if (_durationLiteral.hasMatch(line)) {
          violations.add(_Violation(normalizedPath, i + 1, line, 'duration'));
        }
      }
    }
  }
  return violations;
}

void main() {
  test('no widget under screens/ or widgets/ (outside widgets/theme/) hard-codes a colour, '
      'font size or duration', () {
    final violations = _scan(_widgetRoots);
    expect(
      violations,
      isEmpty,
      reason: violations.map((v) => v.toString()).join('\n'),
    );
  });
}
