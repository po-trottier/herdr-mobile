/// Forbids a swipe action anywhere under `app/lib/` (R-30-296, R-32-581): swipe actions were
/// retired 2026-09-18 by the product owner, because the SDK ships no swipe-action widget and
/// R-03-059 forbids an imitation, so neither the SDK's `Dismissible` (dismiss-only, its
/// backgrounds non-interactive decoration) nor the retired `flutter_slidable` package may
/// return. A static source scan, not a widget-tree assertion: the failure mode this rule guards
/// against is an implementer reaching for the closest-sounding class, which no widget test would
/// ever exercise unless it happened to be built.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no .dart file under lib/ builds a swipe action', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'run from the app/ directory');

    final offenders = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final content = entity.readAsStringSync();
      // The SDK widget constructor call (never prose mentioning the word) or the retired
      // package's import.
      if (content.contains('Dismissible(') ||
          content.contains('package:flutter_slidable/')) {
        offenders.add(entity.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'R-30-296/R-32-581: a row action opens from a long press, never a swipe. '
          'Offending files: $offenders',
    );
  });
}
