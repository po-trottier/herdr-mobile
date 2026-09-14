/// One case per accepted name and one per rejected name from
/// `docs/10-herdr-integration.md` §6.2 and §6.3 (`docs/90-implementation-plan.md` `WP-17`,
/// R-10-044). Every literal name in both of those tables — probed live against Herdr 0.8.0
/// — is a case here; a name outside both tables is out of scope, per that document's own
/// "no enum in the schema, the only way to establish the vocabulary is to probe" framing.
///
/// This exercises `key_row.dart`'s [classifyKeyName], the closed classifier that file's own
/// `_sendKeyNames` asserts against before every send (R-10-044) — not a live Herdr socket,
/// which this package's `Needs.` line does not reach.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/widgets/key_row.dart';

void main() {
  // docs/10-herdr-integration.md §6.2 "Accepted", one case per literal name in the table.
  const List<String> accepted = <String>[
    // Arrows
    'Up', 'Down', 'Left', 'Right',
    // Submit
    'Enter', 'Return',
    // Tab
    'Tab',
    // Escape
    'Esc', 'escape', 'Escape',
    // Editing
    'Backspace',
    // Space
    'Space',
    // Function keys: "F1 through F99, and F0"
    'F0', 'F1', 'F99',
    // Printable: any single character
    'a', 'Z', '1', '!',
    // Modifier chords
    'ctrl+c',
    'Ctrl+C',
    'CTRL+C',
    'ctrl+shift+c',
    'ctrl+alt+a',
    'alt+b',
    'shift+tab',
    'super+a', 'cmd+a', 'meta+a',
  ];

  for (final String name in accepted) {
    test('accepts "$name" (docs/10-herdr-integration.md §6.2)', () {
      expect(classifyKeyName(name), KeyNameAcceptance.accepted);
    });
  }

  // docs/10-herdr-integration.md §6.3 "Rejected", one case per literal name in the table.
  const List<String> rejected = <String>[
    // "no logical name exists" — the six raw-CSI keys
    'Home', 'End', 'PageUp', 'PageDown', 'Delete', 'Insert',
    // "not aliases"
    'Del', 'Ins', 'Newline', 'BackTab', 'ShiftTab',
    // "emacs style not supported"
    'M-x', 'A-x', 'S-Tab',
    // "hyphen separator rejected"
    'ctrl-c',
    // "caret notation rejected"
    '^C',
    // "win is not a modifier"
    'win+a',
  ];

  for (final String name in rejected) {
    test('rejects "$name" (docs/10-herdr-integration.md §6.3)', () {
      expect(classifyKeyName(name), KeyNameAcceptance.rejected);
    });
  }
}
