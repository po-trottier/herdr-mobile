/// Forbids `Dismissible` anywhere under `app/lib/` (R-32-581, R-20-040): the app's one
/// reveal-then-tap package is `flutter_slidable`, and the SDK's `Dismissible` widget cannot
/// carry a tappable revealed action at all (`Dismissible.background` and
/// `Dismissible.secondaryBackground` are non-interactive decoration that disappears with the
/// child). A static source scan, not a widget-tree assertion: the failure mode this rule
/// guards against is an implementer reaching for the SDK's own, wrong, closest-sounding
/// class, which no widget test would ever exercise unless it happened to be built.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no .dart file under lib/ constructs the SDK Dismissible widget', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'run from the app/ directory');

    final offenders = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final content = entity.readAsStringSync();
      // The SDK widget constructor call, never `dismissible:`/`ActionPane.dismissible` (a
      // flutter_slidable parameter name, lower-case `d`, no trailing `(`) or prose mentioning
      // the word.
      if (content.contains('Dismissible(')) {
        offenders.add(entity.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'R-32-581/R-20-040: the app MUST use flutter_slidable, never Dismissible, for a '
          'swipe that reveals an action. Offending files: $offenders',
    );
  });
}
