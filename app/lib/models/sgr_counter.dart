/// Counts SGR (`CSI ... m`) parameters outside `docs/30-ux-spec.md` R-30-158's measured
/// vocabulary — `0`, `1`, `2`, `3`, `4`, `38;2`, `48;2`, `38;5`, `48;5` — per
/// `docs/01-architecture.md` R-01-008 and `docs/31-mockups/08-terminal.md` R-31-08-12. Both
/// rules require the app to surface this count on the diagnostics screen
/// (`docs/31-mockups/13-connection.md`), where the expected steady-state value is 0: a
/// non-zero count means Herdr changed its SGR output upstream and rendering is about to
/// break silently. This is `docs/90-implementation-plan.md` `WP-16-c`'s SGR-counter
/// checkbox.
///
/// This model is self-contained: it scans raw ANSI text with a regular expression and never
/// touches `xterm2`, `terminal.dart` or the rendered grid. `terminal.dart` (`WP-16-a`, this
/// package's one dependency by declaration only) is expected to call [SgrCounter.scan] with
/// the same `pane_frame` text it feeds to the renderer, alongside that feed rather than in
/// place of it — this file never runs a VT state machine of its own, per R-31-08-11.
library;

/// Tracks how many SGR parameters, across every `CSI ... m` sequence [scan] has seen, fall
/// outside [measuredVocabulary]. Stateful by design, like `reconnect_policy.dart`'s
/// `ReconnectPolicy`: [unknownCount] both reads and accumulates, and [reset] starts a fresh
/// count for a newly attached pane.
final class SgrCounter {
  SgrCounter();

  /// R-30-158's exact nine-member vocabulary. A scanned parameter is measured when its
  /// normalised form (see [_splitParams]) is one of these.
  static const Set<String> measuredVocabulary = <String>{
    '0',
    '1',
    '2',
    '3',
    '4',
    '38;2',
    '48;2',
    '38;5',
    '48;5',
  };

  /// One SGR sequence: `ESC [` then digits and semicolons, then `m`. `docs/21-terminal-
  /// rendering.md` R-21-007's schema is the source for the character class; other CSI
  /// finals (cursor motion, erase, scroll region) never reach this scanner, per R-31-08-11's
  /// finding that a live pane emits none of them.
  static final RegExp _sgrSequence = RegExp('\x1B\\[([0-9;]*)m');

  int _unknownCount = 0;

  /// The running count of SGR parameters outside [measuredVocabulary], since construction or
  /// the last [reset]. The diagnostics screen reads this; the expected value is 0.
  int get unknownCount => _unknownCount;

  /// Scans [text] for every `CSI ... m` sequence and adds each parameter outside
  /// [measuredVocabulary] to [unknownCount]. Idempotent per call: scanning the same text
  /// twice counts it twice, so a caller MUST scan each `pane_frame` exactly once.
  void scan(String text) {
    for (final RegExpMatch match in _sgrSequence.allMatches(text)) {
      for (final String param in _splitParams(match.group(1)!)) {
        if (!measuredVocabulary.contains(param)) {
          _unknownCount++;
        }
      }
    }
  }

  /// Resets [unknownCount] to 0. `terminal.dart` calls this on a fresh `watch_pane` attach,
  /// per the same clear-and-home cycle R-21-002 gives the renderer, so the count reflects
  /// the pane currently open rather than accumulating across every pane a session has
  /// viewed.
  void reset() {
    _unknownCount = 0;
  }

  /// Splits one sequence's raw parameter text into tokens comparable against
  /// [measuredVocabulary]. An empty params list (`ESC[m`) means SGR 0 per ECMA-48, so it
  /// normalises to `'0'`. A plain numeric parameter stays itself. An extended-colour
  /// parameter (`38` or `48` followed by `2` and three components, or by `5` and one) joins
  /// its introducing pair into a single `'38;2'`/`'38;5'`/`'48;2'`/`'48;5'` token and
  /// consumes the component tokens with it, so the whole colour spec counts as the one
  /// parameter R-30-158 names — never as three or four separate unknown numbers.
  static List<String> _splitParams(String raw) {
    if (raw.isEmpty) return const <String>['0'];
    final List<String> parts = raw.split(';');
    final List<String> result = <String>[];
    int i = 0;
    while (i < parts.length) {
      final String part = parts[i];
      if ((part == '38' || part == '48') && i + 1 < parts.length) {
        final String mode = parts[i + 1];
        if (mode == '2' || mode == '5') {
          result.add('$part;$mode');
          i += mode == '2' ? 5 : 3;
          continue;
        }
      }
      result.add(part.isEmpty ? '0' : part);
      i++;
    }
    return result;
  }
}
