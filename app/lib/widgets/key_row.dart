/// Native terminal key controls. Composer owns text input (R-03-130).
library;

import 'dart:async' show StreamSubscription, Timer;
import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart'
    show
        CupertinoButton,
        CupertinoTheme,
        CupertinoThemeData,
        kCupertinoButtonTintedOpacityDark,
        kCupertinoButtonTintedOpacityLight;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart'
    show
        ButtonStyle,
        FilledButton,
        FilledButtonTheme,
        FilledButtonThemeData,
        OutlinedButton,
        OutlinedButtonTheme,
        OutlinedButtonThemeData,
        TabController,
        TabPageSelector;

import '../models/message.dart';
import '../models/messages/send_input.dart';
import '../models/messages/send_input_ack.dart';
import '../services/chord_latch.dart';
import '../services/terminal.dart' show terminalReplyTimeout;
import 'app_strip.dart';
import 'key_label.dart';
import 'theme/app_color.dart';
import 'theme/app_haptic.dart';
import 'theme/app_radius.dart';
import 'theme/app_size.dart';
import 'theme/app_space.dart';
import 'theme/app_type.dart';
import 'treatments.dart';

/// Whether Herdr 0.8.0 accepts or rejects a key name, per the live-probed vocabulary of
/// `docs/10-herdr-integration.md` §6.2/§6.3 (R-10-044). A closed, static classifier over the
/// exact vocabulary this file's key caps and chords ever place in a `send_input` `keys`
/// array — not a live schema call — so `_sendKeyNames`'s debug assertion, and
/// `key_map_test.dart`, can check every name this file might send with no network call.
enum KeyNameAcceptance { accepted, rejected }

/// `docs/10-herdr-integration.md` §6.2's bare accepted names (arrows, submit, tab, escape,
/// editing, space), lower case — names are case-insensitive, per that section's own note.
const Set<String> _acceptedBareKeyNames = <String>{
  'up',
  'down',
  'left',
  'right',
  'enter',
  'return',
  'tab',
  'esc',
  'escape',
  'backspace',
  'space',
};

/// §6.2's modifier chord vocabulary. `super`/`cmd`/`meta` are accepted here — Herdr does not
/// reject them — even though R-10-039 forbids this file from ever sending one.
const Set<String> _acceptedChordModifiers = <String>{
  'ctrl',
  'alt',
  'shift',
  'super',
  'cmd',
  'meta',
};

/// Classifies [name] the way live Herdr 0.8.0 does, per §6.2/§6.3. See this file's top doc
/// comment and `key_map_test.dart` for the exact accepted and rejected names this checks
/// against.
KeyNameAcceptance classifyKeyName(String name) {
  if (name.isEmpty) return KeyNameAcceptance.rejected;
  // §6.2 "Printable": any single character, including one that would otherwise look like a
  // hyphen or a caret below — `-` and `^` are themselves valid single-character keys.
  if (name.length == 1) return KeyNameAcceptance.accepted;

  final String lower = name.toLowerCase();
  if (_acceptedBareKeyNames.contains(lower)) return KeyNameAcceptance.accepted;

  final RegExpMatch? functionKey = RegExp(r'^f([0-9]{1,2})$').firstMatch(lower);
  if (functionKey != null) return KeyNameAcceptance.accepted;

  // §6.3: caret notation (`^C`) and every hyphen form — the emacs-style `M-x`/`A-x`/`S-Tab`
  // prefixes and the hyphen chord separator `ctrl-c` alike — are rejected outright.
  if (name.startsWith('^') || lower.contains('-')) {
    return KeyNameAcceptance.rejected;
  }

  if (lower.contains('+')) {
    final List<String> parts = lower.split('+');
    final String base = parts.last;
    final bool baseAccepted = base.length == 1 || base == 'tab';
    final bool modifiersAccepted = parts
        .take(parts.length - 1)
        .every(_acceptedChordModifiers.contains);
    if (baseAccepted && modifiersAccepted) return KeyNameAcceptance.accepted;
  }

  return KeyNameAcceptance.rejected;
}

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

/// `opacity.disabled`, per `docs/32-design-language.md`'s opacity table beside R-32-330, for
/// iOS only: `cupertino_ui` 1.0.1 recolours a disabled button to a system grey, the second
/// signal R-32-331 forbids, so a disabled cap on iOS keeps its tint and dims itself, exactly
/// as `app_ghost_button.dart` does. Android takes the dim from the button theme. See
/// `app_filled_button.dart`'s sibling constant for why this is a local constant rather than
/// a token import.
const double _opacityDisabled = 0.38;

/// The function shape `RelayConnection.send` already has (`relay.dart`, `WP-14-a`), and the
/// same shape `device_list.dart` names `SendFrame`. Declared fresh here rather than imported
/// from either file: neither is on this package's `Needs.` line, and the shape itself is the
/// only thing this file depends on.
typedef KeyRowSendFrame = void Function(Message message, {String? corr});

/// The three link conditions that gate every sendable control, per the mockup's states
/// table. A caller derives this from `RelayConnection.connectionState` and the
/// `host_in_use` error the same way `status_strip.dart`'s `StatusStripLinkWord` is derived
/// one level up — that merge is a screen-composition decision outside this package's
/// `Needs.` line (R-90-024), exactly as `status_strip.dart`'s own header comment explains
/// for its own `linkWord`.
enum KeyRowLinkState { live, hostInUse, offline }

/// One arrow key (R-21-019): the glyph R-32-401 names for it, the spoken label of R-30-715,
/// and the `keys` name it sends. [id] is the mockup's own printed glyph, kept as the widget
/// key `keyRowArrow<id>` that the tests address.
final class _ArrowKey {
  const _ArrowKey({
    required this.id,
    required this.icon,
    required this.semanticLabel,
    required this.name,
  });
  final String id;
  final IconData icon;
  final String semanticLabel;
  final String name;
}

/// One of the six keys with no logical name, sent as a raw escape sequence in `text`
/// (R-21-019a, R-10-036). The cap face is the keybind glyph of the 2026-09-23 keycap
/// decision — a Material Symbols icon of the R-32-401 set, never a Unicode glyph — with
/// [label] small underneath. [flipIcon] mirrors the glyph for a forward-facing key
/// (`del`, the forward delete, is the mirrored backspace key).
final class _RawKey {
  const _RawKey({
    required this.label,
    required this.icon,
    required this.semanticLabel,
    required this.sequence,
    this.flipIcon = false,
  });
  final String label;
  final IconData icon;
  final String semanticLabel;
  final String sequence;
  final bool flipIcon;
}

/// The four arrow keys of the inverted T (R-03-117, R-31-09-16): `↑` alone on row one, in
/// column five, and `←` `↓` `→` on row two, in columns four to six, so `↓` sits directly
/// under `↑` with `←` and `→` beside it.
const _ArrowKey _arrowUp = _ArrowKey(
  id: '^',
  icon: Symbols.arrow_upward_rounded,
  semanticLabel: 'Arrow up',
  name: 'Up',
);
const _ArrowKey _arrowDown = _ArrowKey(
  id: 'v',
  icon: Symbols.arrow_downward_rounded,
  semanticLabel: 'Arrow down',
  name: 'Down',
);
const _ArrowKey _arrowLeft = _ArrowKey(
  id: '<',
  icon: Symbols.arrow_back_rounded,
  semanticLabel: 'Arrow left',
  name: 'Left',
);
const _ArrowKey _arrowRight = _ArrowKey(
  id: '>',
  icon: Symbols.arrow_forward_rounded,
  semanticLabel: 'Arrow right',
  name: 'Right',
);

/// The keyboard's own navigation block (R-03-117): three vertical pairs, `ins` over `del`,
/// `home` over `end` and `pgup` over `pgdn`, the way a keyboard stacks them. All six are
/// raw-CSI keys (R-21-019a, R-10-036). The glyphs are the Material Symbols keyboard set
/// (verified against material_symbols_icons 4.2960.0): the package has no
/// `keyboard_delete`-family icon, so `del` mirrors the tag-shaped `backspace` (⌫) into ⌦,
/// and no insert-key icon exists beyond `insert_text`.
const _RawKey _keyIns = _RawKey(
  label: 'ins',
  icon: Symbols.insert_text_rounded,
  semanticLabel: 'Insert',
  sequence: '\x1b[2~',
);
const _RawKey _keyDel = _RawKey(
  label: 'del',
  icon: Symbols.backspace_rounded,
  semanticLabel: 'Delete',
  sequence: '\x1b[3~',
  flipIcon: true,
);
const _RawKey _keyHome = _RawKey(
  label: 'home',
  icon: Symbols.first_page_rounded,
  semanticLabel: 'Home',
  sequence: '\x1b[H',
);
const _RawKey _keyEnd = _RawKey(
  label: 'end',
  icon: Symbols.last_page_rounded,
  semanticLabel: 'End',
  sequence: '\x1b[F',
);
const _RawKey _keyPgup = _RawKey(
  label: 'pgup',
  icon: Symbols.keyboard_double_arrow_up_rounded,
  semanticLabel: 'Page up',
  sequence: '\x1b[5~',
);
const _RawKey _keyPgdn = _RawKey(
  label: 'pgdn',
  icon: Symbols.keyboard_double_arrow_down_rounded,
  semanticLabel: 'Page down',
  sequence: '\x1b[6~',
);

/// One send this file is still waiting to hear back about. [label] names it in a strip —
/// `esc`, `ctrl+c`, `backspace`, `enter`, or `typing` for a run of characters — and [timer]
/// is its `terminalReplyTimeout` deadline. See `KeyRowState._onAck`'s doc comment for how it
/// is matched to an incoming `SendInputAck`.
final class _PendingSend {
  const _PendingSend({
    required this.label,
    required this.timer,
    required this.input,
    this.mirror = true,
  });
  final SendInput input;
  final String label;
  final Timer timer;

  /// Whether an accepted acknowledgement mirrors into the Composer, per
  /// R-31-09-35. An answer send opts out (R-31-09-38), so the held prompt
  /// draft survives it.
  final bool mirror;
}

/// One page of the key panel's pager (decided 2026-09-23 by the product owner): `Keys`,
/// `Function keys`, then `Answer`. The panel is one pager across all three; at a large
/// text scale a grid reflows onto further pages (R-31-09-40), so a value here names the
/// FIRST page of its grid. The screen maps the reported page to its Composer answer mode:
/// `answerInput = panelOpen && page == KeyPanelPage.answer`.
enum KeyPanelPage { keys, function, answer }

/// The terminal key row and the live typing surface. See this file's top doc comment.
class KeyRow extends StatefulWidget {
  const KeyRow({
    super.key,
    required this.paneId,
    required this.send,
    required this.sendInputAcks,
    this.onInputAccepted,
    this.linkState = KeyRowLinkState.live,
    this.offlineReason,
    this.onDiagnostics,
    this.reconciliationSignal,
    this.landscape = false,
    this.focusNode,
    this.composer,
    this.grid,
    this.panelOpen = false,
    this.requestedPage,
    this.onPageChanged,
  });

  final String paneId;

  /// Shows every terminal key above the input bar.
  final bool panelOpen;

  /// Jumps the panel's pager to the first page of the requested grid when the value
  /// changes to non-null (2026-09-23): a blocked agent opens the panel on the Answer
  /// page this way. Holding the same value re-requests nothing, so the person keeps the
  /// page they swiped to; a `null` clears a pending request. `+` reopens the panel on
  /// the last page instead, which needs no request.
  final KeyPanelPage? requestedPage;

  /// Reports the page the pager rests on: on every settled swipe, on the first build
  /// after the panel opens (the page the bucket remembered), and after a
  /// [requestedPage] jump lands. Never fires synchronously during build — the screen
  /// setStates in it.
  final ValueChanged<KeyPanelPage>? onPageChanged;

  /// Matches `RelayConnection.send`'s exact signature; a caller passes `connection.send`
  /// directly, mirroring `terminal.dart`'s `TerminalMessageSender` seam.
  final KeyRowSendFrame send;
  final ValueChanged<SendInput>? onInputAccepted;

  /// Acknowledgements with their envelope correlation. The caller filters
  /// `MessageSendInputAck` messages without a correlation before this stream.
  final Stream<({String corr, SendInputAck ack})> sendInputAcks;

  final KeyRowLinkState linkState;

  /// R-30-808's exact failure sentence, required when [linkState] is
  /// [KeyRowLinkState.offline]. `null` in every other state.
  final String? offlineReason;

  /// A tap on the offline strip (R-30-806).
  final VoidCallback? onDiagnostics;

  /// Changes identity (`!=` the previous value) whenever a fresh `pane_frame` proves the
  /// pane's real state again, clearing the `Outcome unknown` state per R-30-518's
  /// reconciliation requirement. `null` when the caller has nothing to reconcile with yet.
  final Object? reconciliationSignal;

  /// Clears modifier state after rotation.
  final bool landscape;

  /// Composer focus for modifier keys (R-03-130).
  final FocusNode? focusNode;

  /// The native field row inside the shared input surface.
  final Widget? composer;

  /// The terminal surface below the panel overlay.
  final Widget? grid;

  @override
  State<KeyRow> createState() => KeyRowState();
}

class KeyRowState extends State<KeyRow>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late final ChordLatch _chordLatch = ChordLatch(lockWindow: kDoubleTapTimeout);
  late final StreamSubscription<void> _latchSub;
  StreamSubscription<({String corr, SendInputAck ack})>? _ackSub;

  /// The pager's scroll controller. The selected page itself lives in the
  /// [PageStorageBucket], so it survives the panel's close and reopen (R-31-09-40).
  late final PageController _pager = PageController();

  /// The bucket that remembers the page while the panel is closed.
  /// A new pane gets a fresh bucket, so it starts on page one (R-31-09-40).
  PageStorageBucket _pagerBucket = PageStorageBucket();

  /// The indicator's controller. The reflow of R-31-09-40 changes the page count with
  /// the width and the text scale, so [_syncTabs] recreates it when the count changes.
  late TabController _tabs;

  /// The selected page, kept beside the pager so the indicator's spoken label always
  /// has a value, even before the viewport attaches.
  int _page = 0;

  /// How many of the leading pages are the `Keys` grid's, and how many of the
  /// following pages are `Function keys`; the rest are `Answer`. The panel's layout
  /// sets them on every pass.
  int _keysPageCount = 1;
  int _functionPageCount = 1;

  /// A [KeyRow.requestedPage] change the pager has not applied yet. Set in
  /// `didUpdateWidget`, consumed by the next panel layout — the pager may not exist
  /// yet when the request arrives, so the layout applies it post-frame.
  KeyPanelPage? _pendingPageRequest;

  int _corrSeq = 0;
  String _nextCorr() => 'key-row-${_corrSeq++}';

  final Map<String, _PendingSend> _pending = <String, _PendingSend>{};

  /// The label of the send whose acknowledgement never came (R-30-518), or `null`.
  String? _outcomeUnknownLabel;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // A request that arrives with the widget (a blocked agent opening the panel on the
    // Answer page) never passes through `didUpdateWidget`; seed it here.
    _pendingPageRequest = widget.requestedPage;
    WidgetsBinding.instance.addObserver(this);
    widget.focusNode?.addListener(_onFocusChanged);
    _latchSub = _chordLatch.changes.listen((_) {
      if (mounted) setState(() {});
    });
    _ackSub = widget.sendInputAcks.listen(_onAck);
    // Three pages when six column modules fit (R-03-117, 2026-09-23); the first layout
    // reflows and recreates the controller when they do not (R-31-09-40).
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void didUpdateWidget(KeyRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_onFocusChanged);
      widget.focusNode?.addListener(_onFocusChanged);
    }
    if (oldWidget.sendInputAcks != widget.sendInputAcks) {
      unawaited(_ackSub?.cancel());
      _ackSub = widget.sendInputAcks.listen(_onAck);
    }
    if (oldWidget.linkState == KeyRowLinkState.live &&
        widget.linkState != KeyRowLinkState.live) {
      _markOutcomeUnknown();
    }
    if (widget.reconciliationSignal != oldWidget.reconciliationSignal) {
      _reconcile();
    }
    // R-31-09-19: a rotation clears a forgotten latch. Read off the caller's orientation,
    // not `didChangeMetrics`: the keyboard rising is a metrics change too, and it must not
    // clear the latch that raised it.
    if (oldWidget.landscape != widget.landscape) _chordLatch.clear();
    if (widget.requestedPage != oldWidget.requestedPage) {
      // Only a change to non-null moves the pager; a held value leaves the page the
      // person swiped to, and a null clears a request the panel never consumed.
      _pendingPageRequest = widget.requestedPage;
    }
    if (oldWidget.paneId != widget.paneId) {
      // A new pane starts on page one (R-31-09-40): forget the stored page, and take the
      // live pager and the indicator back with it.
      _page = 0;
      _pagerBucket = PageStorageBucket();
      if (_tabs.index != 0) _tabs.index = 0;
      if (_pager.hasClients && _pager.page?.round() != 0) _pager.jumpToPage(0);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // R-31-09-19: the app going to the background clears a forgotten latch, and R-30-518
    // treats it exactly like a dropped link for whatever send is still in flight.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _chordLatch.clear();
      _markOutcomeUnknown();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final _PendingSend send in _pending.values) {
      send.timer.cancel();
    }
    unawaited(_ackSub?.cancel());
    unawaited(_latchSub.cancel());
    widget.focusNode?.removeListener(_onFocusChanged);
    _chordLatch.dispose();
    _pager.dispose();
    _tabs.dispose();
    super.dispose();
  }

  bool get _sendingEnabled => widget.linkState == KeyRowLinkState.live;

  // R-03-130: Native input owns edits. Only modifier chords bypass it.
  TextEditingValue formatComposerEdit(
    TextEditingValue before,
    TextEditingValue after,
  ) {
    if (!_sendingEnabled ||
        _chordLatch.latched.isEmpty ||
        !after.composing.isCollapsed) {
      return after;
    }
    final int prefix = _commonPrefixLength(before.text, after.text);
    final int suffix = _commonSuffixLength(before.text, after.text, prefix);
    final String inserted = after.text.substring(
      prefix,
      after.text.length - suffix,
    );
    if (inserted.isEmpty) return after;
    final StringBuffer remaining = StringBuffer();
    int consumed = 0;
    for (final String char in inserted.characters) {
      final List<ChordModifier> modifiers = _chordLatch.latched;
      if (modifiers.isEmpty || char.length != 1) {
        remaining.write(char);
        continue;
      }
      final String chord = <String>[
        for (final ChordModifier modifier in modifiers) modifier.name,
        char.toLowerCase(),
      ].join('+');
      _chordLatch.consume();
      _dispatch(
        SendInput(paneId: widget.paneId, keys: <String>[chord]),
        label: chord,
      );
      consumed += char.length;
    }
    if (consumed == 0) return after;
    if (remaining.isEmpty) return before;
    final String text =
        before.text.substring(0, prefix) +
        remaining.toString() +
        after.text.substring(after.text.length - suffix);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: prefix + remaining.length),
    );
  }

  void _onFocusChanged() {
    if (!(widget.focusNode?.hasFocus ?? false)) {
      _chordLatch.clear();
    }
  }

  void _requestKeyboard() {
    widget.focusNode?.requestFocus();
  }

  // --- Sending ---

  /// One `send_input` frame, tracked until its acknowledgement or its deadline. A send that
  /// follows a failure clears the failure strip: the person typed again, which is the one
  /// recovery R-31-09-13 allows. [mirror] decides what an accepted acknowledgement does
  /// locally; see [_PendingSend].
  void _dispatch(
    SendInput input, {
    required String label,
    bool mirror = true,
  }) {
    if (!_sendingEnabled) return;
    assert(
      input.keys?.every(
            (String k) => classifyKeyName(k) == KeyNameAcceptance.accepted,
          ) ??
          true,
      'key_row.dart must only ever send an accepted key name (R-10-044): '
      '${input.keys}',
    );
    if (_errorMessage != null) setState(() => _errorMessage = null);
    final String corr = _nextCorr();
    late final _PendingSend send;
    send = _PendingSend(
      input: input,
      label: label,
      timer: Timer(terminalReplyTimeout, () => _onAckTimeout(send)),
      mirror: mirror,
    );
    _pending[corr] = send;
    widget.send(Message.sendInput(input), corr: corr);
  }

  /// A key cap press: `haptic.select` (R-31-09-02), then one named-key frame.
  void _sendKeyNames(List<String> keys, {required String label}) {
    if (!_sendingEnabled) return;
    unawaited(AppHaptic.select());
    _dispatch(
      SendInput(paneId: widget.paneId, keys: keys),
      label: label,
    );
  }

  /// A key cap press that sends text: `haptic.select`, then one `text` frame — a raw
  /// escape sequence for the six keys with no logical name (R-10-036).
  void _sendRawText(String text, {required String label}) {
    if (!_sendingEnabled) return;
    unawaited(AppHaptic.select());
    _dispatch(
      SendInput(paneId: widget.paneId, text: text),
      label: label,
    );
  }

  /// One answer-page send (R-31-09-38): the frame goes with `bypass_line: true`, and its
  /// acknowledgement never mirrors into the Composer, so the held prompt draft survives
  /// the answer. Every cap of the Answer page sends this way (2026-09-23).
  void _sendAnswer(SendInput input, {required String label}) {
    if (!_sendingEnabled) return;
    assert(
      input.bypassLine == true &&
          input.line == null &&
          input.defer == null &&
          (input.text != null || input.keys != null),
      'an answer send is exactly the R-11-254 shape: $input',
    );
    _dispatch(input, label: label, mirror: false);
  }

  /// One Answer cap press (R-31-09-41): `haptic.select`, then the cap's named
  /// key on the answer path of R-31-09-38.
  void _answerKey(String name, {required String label}) {
    if (!_sendingEnabled) return;
    unawaited(AppHaptic.select());
    _sendAnswer(
      SendInput(
        paneId: widget.paneId,
        keys: <String>[name],
        bypassLine: true,
      ),
      label: label,
    );
  }

  /// Match acknowledgements by correlation, regardless of arrival order.
  void _onAck(({String corr, SendInputAck ack}) reply) {
    final _PendingSend? send = _pending[reply.corr];
    if (send == null) return;
    send.timer.cancel();
    if (reply.ack.queued ?? false) return;
    _pending.remove(reply.corr);
    if (reply.ack.accepted) {
      // Every accepted control but an answer send mirrors into the Composer,
      // so the field and the Host shadow hold the same line (R-03-130).
      // R-31-09-38: an answer send's acknowledgement MUST NOT (R-31-09-41).
      if (send.mirror) widget.onInputAccepted?.call(send.input);
      return;
    }
    // R-31-09-13, R-11-228: nothing here ever re-sends.
    unawaited(AppHaptic.error());
    setState(() => _errorMessage = 'Not sent: ${send.label}');
  }

  /// Clear the previous failure before a new Composer submission.
  void clearInputFailure() {
    if (_errorMessage == null && _outcomeUnknownLabel == null) return;
    setState(() {
      _errorMessage = null;
      _outcomeUnknownLabel = null;
    });
  }

  /// Show a rejected Composer submission without discarding its text.
  void reportInputFailure() {
    unawaited(AppHaptic.error());
    setState(() => _errorMessage = 'Not sent: typing');
  }

  void _onAckTimeout(_PendingSend send) {
    if (_pending.containsValue(send)) _markOutcomeUnknown();
  }

  /// R-30-518's outcome-unknown state for whatever is still in flight: the oldest send
  /// names the strip, and every pending send is dropped, because its acknowledgement will
  /// not come — the link is gone, the app is in the background, or the deadline passed.
  /// The next `pane_frame` reconciles it: the grid is the record of what the pane received.
  void _markOutcomeUnknown() {
    if (_pending.isEmpty) return;
    final String label = _pending.values.first.label;
    for (final _PendingSend send in _pending.values) {
      send.timer.cancel();
    }
    _pending.clear();
    setState(() => _outcomeUnknownLabel = label);
  }

  void _reconcile() {
    if (_outcomeUnknownLabel == null) return;
    setState(() => _outcomeUnknownLabel = null);
  }

  // --- The latch ---

  void _toggleLatch(ChordModifier modifier) {
    if (!_sendingEnabled) return;
    _chordLatch.toggle(modifier);
    // R-31-09-19: a latch raises the software keyboard and holds it up.
    if (_chordLatch.latched.isNotEmpty) _requestKeyboard();
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    // R-30-701, R-30-741: the app clamps at 2.0 rather than growing without bound, because
    // the terminal chrome cannot shrink further.
    final TextScaler clamped = MediaQuery.textScalerOf(context)
        .clamp(maxScaleFactor: 2.0);
    // R-03-117 (2026-09-16): every status strip sits ABOVE the caps. With the panel open
    // the strips join the panel overlay, which is anchored to the bottom and grows
    // upward, so a latch hint appearing under a tap moves no cap.
    final List<Widget> strips = <Widget>[
      if (widget.linkState == KeyRowLinkState.offline) _buildOfflineStrip(),
      if (_outcomeUnknownLabel case final String label)
        _buildOutcomeUnknownStrip(label),
      if (_outcomeUnknownLabel == null && _errorMessage != null)
        _buildErrorStrip(),
      if (_chordLatch.latched.isNotEmpty) _buildLatchHint(color),
    ];
    final Widget bar = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (!widget.panelOpen) ...strips,
        _buildToolbar(color),
      ],
    );
    Widget panel() => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[...strips, _buildPanel(color)],
    );
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: clamped),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (widget.grid case final Widget grid)
            Expanded(
              child: Stack(
                children: <Widget>[
                  Positioned.fill(child: grid),
                  if (widget.panelOpen)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: SafeArea(
                        top: false,
                        bottom: false,
                        child: panel(),
                      ),
                    ),
                ],
              ),
            )
          else if (widget.panelOpen)
            panel(),
          if (widget.grid != null) SafeArea(top: false, child: bar) else bar,
        ],
      ),
    );
  }

  Widget _buildOfflineStrip() => AppStrip(
    onTapDestination: widget.onDiagnostics,
    child: Treatment.warning(
      label: widget.offlineReason ?? 'No route to the relay.',
    ),
  );

  /// The outcome-unknown strip of R-30-518: it names the send, offers nothing, and clears
  /// on the next `pane_frame`. There is no buffer to copy or restore (R-03-054): the person
  /// reads the grid and types again.
  Widget _buildOutcomeUnknownStrip(String label) => AppStrip(
    child: Treatment.warning(
      label: 'We do not know whether $label reached the pane.',
    ),
  );

  /// The refused-send strip of R-31-09-14: it names the send and offers no action, per
  /// R-31-09-13. The next send clears it.
  Widget _buildErrorStrip() =>
      AppStrip(child: Treatment.error(label: _errorMessage!, inStrip: true));

  /// The latched-modifier hint (the mockup's "ctrl latched" callout 2): the strip of
  /// section 7.22 of `docs/32-design-language.md`, so every line above the key row shares
  /// one surface, one inset and one padding, with the hint in `type.caption` in
  /// `color.fg.secondary`. Every key name in the sentence is an inline key (R-32-599,
  /// R-03-103); the spoken sentence names each modifier in full. A locked latch (R-31-09-23)
  /// says so, and names the way out, because it clears on no key and no timeout. Both
  /// modifiers may be latched at once (R-03-120), so the sentence names every one of them.
  ///
  /// `keyedText` gives its own `Text.rich` a `semanticsLabel` of the template with each
  /// `{key}` spoken, which reads `ctrl and alt are held` — the printed wording, not the
  /// spoken one. [excludeSemantics] drops it, so the one node this strip publishes carries
  /// [_latchGroupSpoken] alone and a screen reader never hears the sentence twice.
  Widget _buildLatchHint(AppColor color) => AppStrip(
    child: Semantics(
      liveRegion: true,
      label: _latchGroupSpoken(),
      excludeSemantics: true,
      child: keyedText(
        _latchGroupPrinted(),
        style: AppType.caption.copyWith(color: color.fgSecondary),
        color: color,
      ),
    ),
  );

  /// Every modifier in [state], in the `ctrl` then `alt` order R-10-038 joins a chord in.
  List<ChordModifier> _inState(ChordLatchState state) => ChordModifier.values
      .where((ChordModifier m) => _chordLatch.stateOf(m) == state)
      .toList(growable: false);

  /// The printed hint of the strip. The locked modifiers come first, then the held ones, so
  /// the sentence reads in the order the states end: `{ctrl} is locked and {alt} is held.`
  /// One modifier keeps the exact sentence the row printed before R-03-120.
  String _latchGroupPrinted() {
    final List<ChordModifier> locked = _inState(ChordLatchState.locked);
    final List<ChordModifier> held = _inState(ChordLatchState.held);
    final String names = <String>[
      if (locked.isNotEmpty) '${_printedNames(locked)} ${_verb(locked)} locked',
      if (held.isNotEmpty) '${_printedNames(held)} ${_verb(held)} held',
    ].join(' and ');
    return <String>[
      '$names.',
      if (held.isNotEmpty) 'Press one key.',
      if (locked.isNotEmpty) 'Tap ${_printedNames(locked)} again to release.',
    ].join(' ');
  }

  /// The same sentence for a screen reader: the full name of each modifier, and no inline-key
  /// braces, exactly as the cap's own label says it (R-30-715).
  String _latchGroupSpoken() {
    final List<ChordModifier> locked = _inState(ChordLatchState.locked);
    final List<ChordModifier> held = _inState(ChordLatchState.held);
    final String names = <String>[
      if (locked.isNotEmpty) '${_spokenNames(locked)} locked',
      if (held.isNotEmpty) '${_spokenNames(held)} held',
    ].join(' and ');
    return <String>[
      '$names.',
      if (held.isNotEmpty) 'Press one key.',
      if (locked.isNotEmpty) 'Tap ${_spokenNames(locked)} again to release.',
    ].join(' ');
  }

  /// `{ctrl}`, or `{ctrl} and {alt}`: the inline-key markup `keyedText` reads (R-32-599).
  String _printedNames(List<ChordModifier> modifiers) =>
      modifiers.map((ChordModifier m) => '{${m.name}}').join(' and ');

  /// `Control`, or `Control and Alt`: the spoken full names of R-30-715.
  String _spokenNames(List<ChordModifier> modifiers) =>
      modifiers.map(_spokenName).join(' and ');

  /// The verb one modifier and two modifiers take, so the printed sentence is grammatical
  /// either way: `{ctrl} is held`, `{ctrl} and {alt} are held`.
  String _verb(List<ChordModifier> modifiers) =>
      modifiers.length == 1 ? 'is' : 'are';

  String _spokenName(ChordModifier modifier) =>
      modifier == ChordModifier.ctrl ? 'Control' : 'Alt';

  /// The spoken state of one `ctrl` or `alt` cap: the modifier's full name, then `held` for
  /// one key or `locked` until the cap is tapped again (R-31-09-23). The bare name when this
  /// modifier is not latched. Each cap speaks its own state alone, even while both are
  /// latched (R-03-120): the strip is where the group is named.
  String _latchSpoken(ChordModifier modifier) {
    final String name = _spokenName(modifier);
    return switch (_chordLatch.stateOf(modifier)) {
      ChordLatchState.none => name,
      ChordLatchState.held => '$name held. Press one key.',
      ChordLatchState.locked => '$name locked. Tap $name again to release.',
    };
  }

  Widget _buildToolbar(AppColor color) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.bgRaised,
      border: Border(
        top: BorderSide(color: color.borderStrong, width: AppBorder.hairline),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.space4,
        vertical: AppSpace.space2,
      ),
      child: widget.composer,
    ),
  );

  /// A settled swipe: record the page, move the indicator with it (R-31-09-40), and
  /// report the grid it landed in. A scroll notification fires this, never a build, so
  /// the listener may setState.
  void _onPageChanged(int page) {
    setState(() => _page = page);
    if (_tabs.index != page) _tabs.index = page;
    widget.onPageChanged?.call(_pageEnum(page));
  }

  /// The grid a pager index belongs to: the leading [_keysPageCount] pages are `Keys`,
  /// the next [_functionPageCount] are `Function keys`, the rest are `Answer`.
  KeyPanelPage _pageEnum(int page) {
    if (page < _keysPageCount) return KeyPanelPage.keys;
    if (page < _keysPageCount + _functionPageCount) return KeyPanelPage.function;
    return KeyPanelPage.answer;
  }

  /// The pager index of a grid's first page, for [KeyRow.requestedPage].
  int _firstPageOf(KeyPanelPage page) => switch (page) {
    KeyPanelPage.keys => 0,
    KeyPanelPage.function => _keysPageCount,
    KeyPanelPage.answer => _keysPageCount + _functionPageCount,
  };

  /// Keeps the indicator's controller matched to the page count the current layout
  /// produces, recreating it when the reflow of R-31-09-40 changes the count. The
  /// selector lets go of the old controller in its own `didUpdateWidget`, which
  /// tolerates a disposed one — the pattern `agent_list_screen.dart` documents. When the
  /// count shrank past the selected page, the pager and the indicator are mid-layout, so
  /// the correction to the last page lands after this frame.
  void _syncTabs(int pageCount) {
    if (_page >= pageCount) {
      _page = pageCount - 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_pager.hasClients && _pager.page?.round() != _page) {
          _pager.jumpToPage(_page);
        }
        if (_tabs.index != _page) _tabs.index = _page;
      });
    }
    if (_tabs.length != pageCount) {
      final TabController previous = _tabs;
      _tabs = TabController(
        length: pageCount,
        initialIndex: _page,
        vsync: this,
      );
      previous.dispose();
    }
  }

  /// The indicator's spoken label (R-31-09-40): the grid's name, the page's index and
  /// the total — `Keys, page 1 of 3`, `Function keys, page 2 of 3`, `Answer, page 3 of
  /// 3`.
  String get _pageSpoken {
    final String name = switch (_pageEnum(_page)) {
      KeyPanelPage.keys => 'Keys',
      KeyPanelPage.function => 'Function keys',
      KeyPanelPage.answer => 'Answer',
    };
    return '$name, page ${_page + 1} of ${_tabs.length}';
  }

  /// The key panel overlays the grid without changing keyboard state.
  Widget _buildPanel(AppColor color) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.bgRaised,
      border: Border(
        top: BorderSide(color: color.borderStrong, width: AppBorder.hairline),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.space4,
        vertical: AppSpace.space2,
      ),
      child: _buildPager(),
    ),
  );

  /// The panel's one pager across the three grids of the 2026-09-23 keycap decision —
  /// `Keys`, `Function keys` and `Answer`, in that order — under the reflow of
  /// R-31-09-40. Every page is its grid's cells restricted to the columns the reflow
  /// gives it, and every grid runs four rows, so the panel is one fixed height and the
  /// indicator never moves between pages.
  Widget _buildPager() => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      final (double module, int columns) = _moduleWidth(
        context,
        constraints.maxWidth,
        _capFaceMeasures,
        6,
      );
      final bool sendable = _sendingEnabled;
      final List<List<Widget?>> keysCells = _keysCells(sendable);
      final List<List<Widget?>> functionCells = _functionCells(sendable);
      final List<List<Widget?>> answerCells = _answerCells(sendable);
      final List<List<int>> keysPages = _pageColumns(columns, keysCells);
      final List<List<int>> functionPages = _pageColumns(
        columns,
        functionCells,
      );
      final List<List<int>> answerPages = _pageColumns(columns, answerCells);
      final List<(List<List<Widget?>> cells, List<int> columns)> grids =
          <(List<List<Widget?>>, List<int>)>[
            for (final List<int> page in keysPages) (keysCells, page),
            for (final List<int> page in functionPages) (functionCells, page),
            for (final List<int> page in answerPages) (answerCells, page),
          ];
      _keysPageCount = keysPages.length;
      _functionPageCount = functionPages.length;
      // A requested page (KeyRow.requestedPage) takes the pager to the first page of
      // its grid. The value moves `_page` here, so the indicator's spoken label is
      // right from this pass; the pager and the dots follow post-frame, and the
      // report goes out there too — never synchronously during build.
      final KeyPanelPage? request = _pendingPageRequest;
      _pendingPageRequest = null;
      if (request != null) _page = _firstPageOf(request);
      _syncTabs(grids.length);
      if (request != null || !_pager.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_tabs.index != _page) _tabs.index = _page;
          if (_pager.hasClients && _pager.page?.round() != _page) {
            _pager.jumpToPage(_page);
          }
          // A jump reports through the pager's own onPageChanged; this call covers
          // the case where no scroll happened — the first build after the panel
          // opened, or a request for the page the pager already shows.
          widget.onPageChanged?.call(_pageEnum(_page));
        });
      }
      // Every page of every grid runs four rows. A cap never grows taller than
      // `size.keycap` (R-31-09-15), so the pages are one fixed height and the
      // indicator below them never moves.
      const int rows = 4;
      return _capTheme(
        context,
        minWidth: module,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              height:
                  rows * AppSize.keycapHeight + (rows - 1) * AppSpace.space2,
              child: PageStorage(
                bucket: _pagerBucket,
                child: PageView(
                  key: const PageStorageKey<String>('keyRowPages'),
                  controller: _pager,
                  onPageChanged: _onPageChanged,
                  children: <Widget>[
                    for (final (
                          List<List<Widget?>> cells,
                          List<int> page,
                        )
                        in grids)
                      _gridPage(cells, page, module),
                  ],
                ),
              ),
            ),
            // R-31-09-40: the native indicator, centred, a `space.2` below the
            // caps, drawn when the pager has more than one page. `cupertino_ui`
            // 1.0.1 has no page control, so the Material SDK one serves both
            // platforms (R-33-081, the R-33-034 precedent).
            if (grids.length > 1) ...<Widget>[
              _rowGap,
              Center(
                child: Semantics(
                  container: true,
                  liveRegion: true,
                  excludeSemantics: true,
                  label: _pageSpoken,
                  child: TabPageSelector(controller: _tabs),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );


  /// The Answer page's `enter` cap (R-31-09-41): the platform's high-emphasis
  /// filled button in the primary colour, the grid's one filled cap.
  Widget _answerEnterCap(bool sendable) => _KeyCap(
    key: const ValueKey<String>('keyRowAnswerEnter'),
    icon: Symbols.keyboard_return_rounded,
    name: 'enter',
    semanticLabel: 'Enter',
    filled: true,
    onTap: sendable ? () => _answerKey('Enter', label: 'enter') : null,
  );

  /// The Answer page's `esc` cap: the way out of the prompt, sent on the
  /// answer path of R-31-09-38 like every answer cap.
  Widget _answerEscCap(bool sendable) => _KeyCap(
    key: const ValueKey<String>('keyRowAnswerEsc'),
    icon: Symbols.cancel_rounded,
    name: 'esc',
    semanticLabel: 'Escape',
    onTap: sendable ? () => _answerKey('Esc', label: 'esc') : null,
  );

  /// One Answer arrow: the glyph of R-32-401, the spoken label and the `keys`
  /// name of the Keys page's arrow caps, sent on the answer path of
  /// R-31-09-38.
  Widget _answerArrowCap(_ArrowKey arrow, bool sendable) => _KeyCap(
    key: ValueKey<String>('keyRowAnswer${arrow.name}'),
    icon: arrow.icon,
    semanticLabel: arrow.semanticLabel,
    onTap: sendable ? () => _answerKey(arrow.name, label: arrow.name) : null,
  );

  /// One `space.2` between two rows of a page. An empty cell is a blank module, built
  /// where it sits in [_gridPage], so the rows of every column stay level.
  static const Widget _rowGap = SizedBox(height: AppSpace.space2);

  /// The `esc` cap the Keys and Function keys pages carry in row one, column one
  /// (R-03-117): the way out of a mode a person entered by accident stays on every page
  /// (R-31-09-40). The package has no escape-key glyph, so the face is `cancel`, the
  /// dismiss icon, with `esc` small under it.
  Widget _escCap(bool sendable) => _KeyCap(
    key: const ValueKey<String>('keyRowEsc'),
    icon: Symbols.cancel_rounded,
    name: 'esc',
    semanticLabel: 'Escape',
    onTap: sendable ? () => _sendKeyNames(<String>['Esc'], label: 'esc') : null,
  );

  /// The `tab` cap: a long press sends `shift+tab` (R-21-019).
  Widget _tabCap(bool sendable) => _KeyCap(
    key: const ValueKey<String>('keyRowTab'),
    icon: Symbols.keyboard_tab_rounded,
    name: 'tab',
    semanticLabel: 'Tab',
    onTap: sendable ? () => _sendKeyNames(<String>['Tab'], label: 'tab') : null,
    onLongPress: sendable
        ? () => _sendKeyNames(<String>['shift+tab'], label: 'shift+tab')
        : null,
  );

  /// One latched modifier cap: `ctrl` or `alt`. Both latch and lock exactly the same
  /// way (R-31-09-19, R-31-09-23); the latch raises the keyboard, per R-31-09-17.
  Widget _modifierCap(ChordModifier modifier, bool sendable) => _KeyCap(
    key: ValueKey<String>(
      modifier == ChordModifier.ctrl ? 'keyRowCtrl' : 'keyRowAlt',
    ),
    icon: modifier == ChordModifier.ctrl
        ? Symbols.keyboard_control_key_rounded
        : Symbols.keyboard_option_key_rounded,
    name: modifier.name,
    semanticLabel: _latchSpoken(modifier),
    latched: _chordLatch.isLatched(modifier),
    locked: _chordLatch.isLocked(modifier),
    onTap: sendable ? () => _toggleLatch(modifier) : null,
  );

  /// One function key cap (R-03-117): the face is the key's own `F1`…`F12` in
  /// `type.mono.key` (2026-09-23), spoken `F1`, sending the bare `F1` of
  /// `docs/10-herdr-integration.md` §6.2 through the named-key path. A latch neither
  /// modifies it nor clears for it: R-10-038 permits only a character or `tab` as a
  /// chord base.
  Widget _fnCap(int number, bool sendable) => _KeyCap(
    key: ValueKey<String>('keyRowFn$number'),
    label: 'F$number',
    semanticLabel: 'F$number',
    onTap: sendable
        ? () => _sendKeyNames(<String>['F$number'], label: 'F$number')
        : null,
  );

  /// The six columns and four rows of the `Keys` grid (R-03-117, re-laid 2026-09-23 to
  /// physical-keyboard positions): row one `esc . . ins home pgup`, row two
  /// `tab . . del end pgdn`, row three `. . . . ↑ .`, row four `ctrl alt . ← ↓ →` —
  /// the navigation pairs stack over the arrow columns the way a keyboard stacks them,
  /// and `↑` sits directly over `↓` in the inverted T of the bottom row. `null` is an
  /// empty cell, drawn as one blank module so every row shares its column widths
  /// (R-31-09-21).
  List<List<Widget?>> _keysCells(bool sendable) => <List<Widget?>>[
    <Widget?>[
      _escCap(sendable),
      null,
      null,
      _rawCap(_keyIns, sendable),
      _rawCap(_keyHome, sendable),
      _rawCap(_keyPgup, sendable),
    ],
    <Widget?>[
      _tabCap(sendable),
      null,
      null,
      _rawCap(_keyDel, sendable),
      _rawCap(_keyEnd, sendable),
      _rawCap(_keyPgdn, sendable),
    ],
    <Widget?>[null, null, null, null, _arrowCap(_arrowUp, sendable), null],
    <Widget?>[
      _modifierCap(ChordModifier.ctrl, sendable),
      _modifierCap(ChordModifier.alt, sendable),
      null,
      _arrowCap(_arrowLeft, sendable),
      _arrowCap(_arrowDown, sendable),
      _arrowCap(_arrowRight, sendable),
    ],
  ];

  /// The same module and four rows for the `Function keys` grid (R-03-117, amended
  /// 2026-09-23): `esc` alone top left, then the function row in two full rows at the
  /// bottom — F1–F6 on row three, F7–F12 on row four.
  List<List<Widget?>> _functionCells(bool sendable) => <List<Widget?>>[
    <Widget?>[_escCap(sendable), null, null, null, null, null],
    const <Widget?>[null, null, null, null, null, null],
    <Widget?>[for (int n = 1; n <= 6; n++) _fnCap(n, sendable)],
    <Widget?>[for (int n = 7; n <= 12; n++) _fnCap(n, sendable)],
  ];

  /// The `Answer` grid of R-31-09-41 (2026-09-23, amended): `esc` top left and the one
  /// filled `enter` top right, like a keyboard's corners; the inverted T sits centred
  /// low — row three `. . ↑ . . .`, row four `. ← ↓ → . .`. Every cap sends on the
  /// answer path of R-31-09-38: `bypass_line: true`, never mirrored into the Composer.
  /// The answer TEXT is the Composer's answer mode, not a field of this panel.
  List<List<Widget?>> _answerCells(bool sendable) => <List<Widget?>>[
    <Widget?>[
      _answerEscCap(sendable),
      null,
      null,
      null,
      null,
      _answerEnterCap(sendable),
    ],
    const <Widget?>[null, null, null, null, null, null],
    <Widget?>[null, null, _answerArrowCap(_arrowUp, sendable), null, null, null],
    <Widget?>[
      null,
      _answerArrowCap(_arrowLeft, sendable),
      _answerArrowCap(_arrowDown, sendable),
      _answerArrowCap(_arrowRight, sendable),
      null,
      null,
    ],
  ];

  /// The columns one page of [cells] shows: column one first — the leading column every
  /// page retains (R-31-09-40): `esc` on all three grids — then one run of the
  /// remaining columns, as many as [fit] leaves room for. A run with no key in any row
  /// (the function grid's empty column two, the keys grid's gutter column three) adds
  /// no page. When the grid's own column count fits, this is the one unbroken grid
  /// (R-31-09-16).
  List<List<int>> _pageColumns(int fit, List<List<Widget?>> cells) {
    final int gridColumns = cells.first.length;
    final int chunk = math.max(1, fit - 1);
    final List<List<int>> pages = <List<int>>[];
    for (int start = 1; start < gridColumns; start += chunk) {
      final List<int> run = <int>[
        for (
          int column = start;
          column < math.min(start + chunk, gridColumns);
          column++
        )
          column,
      ];
      final bool empty = run.every(
        (int column) => cells.every((List<Widget?> row) => row[column] == null),
      );
      if (!empty) pages.add(<int>[0, ...run]);
    }
    return pages;
  }

  /// One page of a grid: the rows of [cells] restricted to [columns], every empty cell a
  /// blank [module] so the rows stay level with the caps.
  Widget _gridPage(
    List<List<Widget?>> cells,
    List<int> columns,
    double module,
  ) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      for (int row = 0; row < cells.length; row++) ...<Widget>[
        if (row > 0) _rowGap,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (int i = 0; i < columns.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: AppSpace.space2),
              cells[row][columns[i]] ??
                  SizedBox(width: module, height: AppSize.keycapHeight),
            ],
          ],
        ),
      ],
    ],
  );

  /// One arrow cap: the glyph of R-32-401 and the `keys` name of R-21-019. The widget key is
  /// `keyRowArrow<id>` wherever the arrow sits, so a test addresses one arrow by one id.
  Widget _arrowCap(_ArrowKey arrow, bool sendable) => _KeyCap(
    key: ValueKey<String>('keyRowArrow${arrow.id}'),
    icon: arrow.icon,
    semanticLabel: arrow.semanticLabel,
    onTap: sendable
        ? () => _sendKeyNames(<String>[arrow.name], label: arrow.semanticLabel)
        : null,
  );

  /// Sends the raw CSI sequence for a navigation key.
  Widget _rawCap(_RawKey def, bool sendable) => _KeyCap(
    key: ValueKey<String>('keyRowNav${def.label}'),
    icon: def.icon,
    name: def.label,
    flipIcon: def.flipIcon,
    semanticLabel: def.semanticLabel,
    onTap: sendable ? () => _sendRawText(def.sequence, label: def.label) : null,
  );
}

/// The length of the longest common prefix of [a] and [b], in code units.
int _commonPrefixLength(String a, String b) {
  final int limit = math.min(a.length, b.length);
  int i = 0;
  while (i < limit && a.codeUnitAt(i) == b.codeUnitAt(i)) {
    i++;
  }
  return i;
}

/// The length of the longest common suffix of [a] and [b], in code units, that does not
/// reach into their common [prefix].
int _commonSuffixLength(String a, String b, int prefix) {
  final int limit = math.min(a.length, b.length) - prefix;
  int i = 0;
  while (i < limit &&
      a.codeUnitAt(a.length - 1 - i) == b.codeUnitAt(b.length - 1 - i)) {
    i++;
  }
  return i;
}

void unawaited(Future<void>? future) {}

/// Every face a grid cap can print, in the style that prints it: the small name under a
/// glyph in `type.micro.strong`, and the F-key faces in `type.mono.key`. [_moduleWidth]
/// measures them all, so the module never sits under one face's own width — a cap wider
/// than the module would push its row out of the grid's columns, and each row holds
/// different faces.
const List<(String, TextStyle)> _capFaceMeasures = <(String, TextStyle)>[
  ('esc', AppType.microStrong),
  ('tab', AppType.microStrong),
  ('ctrl', AppType.microStrong),
  ('alt', AppType.microStrong),
  ('enter', AppType.microStrong),
  ('ins', AppType.microStrong),
  ('del', AppType.microStrong),
  ('home', AppType.microStrong),
  ('end', AppType.microStrong),
  ('pgup', AppType.microStrong),
  ('pgdn', AppType.microStrong),
  ('F1', AppType.monoKey),
  ('F2', AppType.monoKey),
  ('F3', AppType.monoKey),
  ('F4', AppType.monoKey),
  ('F5', AppType.monoKey),
  ('F6', AppType.monoKey),
  ('F7', AppType.monoKey),
  ('F8', AppType.monoKey),
  ('F9', AppType.monoKey),
  ('F10', AppType.monoKey),
  ('F11', AppType.monoKey),
  ('F12', AppType.monoKey),
];

/// The panel's column measure (R-31-09-15, R-31-09-40): how many column modules fit
/// [width] at `space.2` gaps — never more than the six columns R-03-117's grids are
/// built on, and never fewer than two, so a reflowed page always keeps its grid's
/// leading column and one more — and the width that lets exactly that many fill it. The
/// widest of [measures] at the current text scale is a floor beside `size.keycap`,
/// padding included: every cap in every row takes the module as a minimum width, so
/// with the module at or past every face's own measure each cap is exactly one module
/// wide and the rows line up as one grid at any text scale. Below a full grid's room
/// the panel reflows cells onto more pages (R-31-09-40); it never shrinks a cap, clips
/// a face, or scrolls.
(double module, int columns) _moduleWidth(
  BuildContext context,
  double width,
  List<(String, TextStyle)> measures,
  int gridColumns,
) {
  if (!width.isFinite) return (AppSize.keycapWidth, gridColumns);
  final TextPainter probe = TextPainter(
    textScaler: MediaQuery.textScalerOf(context),
    textDirection: TextDirection.ltr,
  );
  double labels = 0;
  for (final (String text, TextStyle style) in measures) {
    probe.text = TextSpan(text: text, style: style);
    probe.layout();
    labels = math.max(labels, probe.width);
  }
  probe.dispose();
  // The padding here is the cap's own horizontal inset: `space.1` a side, the same
  // inset [_capTheme] hands the buttons.
  final double floor = math.max(
    AppSize.keycapWidth,
    labels + 2 * AppSpace.space1,
  );
  final int columns = ((width + AppSpace.space2) / (floor + AppSpace.space2))
      .floor()
      .clamp(2, gridColumns);
  return (
    math.max(floor, (width - (columns - 1) * AppSpace.space2) / columns),
    columns,
  );
}

/// The one style every cap under [child] takes, per R-31-09-21, R-03-059 and the
/// 2026-09-23 keycap decision: `size.keycap` high, at least [minWidth] wide, `space.1`
/// of horizontal padding, `type.mono.key`, and a `radius.sm` rounded rectangle — a
/// keycap shape, not the component's stadium. The padding is the minimum `space.1` so
/// the five-letter `enter` name under its glyph still fits one 48-wide module at a 360
/// dp width; a wider inset would reflow the panel at the review phone's own width.
/// On Android it is the row's own
/// `OutlinedButtonTheme` and `FilledButtonTheme`, laid over the app theme of
/// `app.dart`, which keeps every colour, side and overlay it sets. On iOS the type
/// reaches `CupertinoButton` through `textTheme.actionTextStyle`, the one slot the
/// component reads; `cupertino_ui` 1.0.1 has no theme slot for a button's size or
/// padding (R-33-033), so [_KeyCap] reads this same style back from
/// `OutlinedButtonTheme.of` and hands the component the minimum size, the padding and
/// the corner radius the Android cap takes from the theme.
Widget _capTheme(
  BuildContext context, {
  required double minWidth,
  required Widget child,
}) {
  final ButtonStyle caps = ButtonStyle(
    minimumSize: WidgetStatePropertyAll<Size>(
      Size(minWidth, AppSize.keycapHeight),
    ),
    padding: const WidgetStatePropertyAll<EdgeInsets>(
      EdgeInsets.symmetric(horizontal: AppSpace.space1),
    ),
    textStyle: const WidgetStatePropertyAll<TextStyle>(AppType.monoKey),
    shape: const WidgetStatePropertyAll<OutlinedBorder>(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.sm)),
      ),
    ),
  );
  final Widget themed = OutlinedButtonTheme(
    data: OutlinedButtonThemeData(
      style: caps.merge(OutlinedButtonTheme.of(context).style),
    ),
    child: FilledButtonTheme(
      data: FilledButtonThemeData(
        style: caps.merge(FilledButtonTheme.of(context).style),
      ),
      child: child,
    ),
  );
  if (!_isIos) return themed;
  final CupertinoThemeData cupertino = CupertinoTheme.of(context);
  return CupertinoTheme(
    data: cupertino.copyWith(
      textTheme: cupertino.textTheme.copyWith(actionTextStyle: AppType.monoKey),
    ),
    child: themed,
  );
}

/// One key cap or arrow key: the platform's own button, per R-03-059 (decided
/// 2026-09-09 by the product owner: a key cap is a button and the row has no exemption) and
/// the `Key cap` row of `docs/33-platform-chrome.md` section 5. On Android an
/// `OutlinedButton`, or a `FilledButton` while a modifier is [latched]; on iOS
/// `CupertinoButton.tinted`, or `CupertinoButton.filled` while latched. Its height, minimum
/// width, padding and type come from the row's theme, [_capTheme]; its colours and its
/// pressed, focused and disabled responses are the platform's own through the theme of
/// `app.dart` (R-32-501, R-32-502, R-32-503). The cap is its own 48-by-48 target
/// (R-30-290, R-30-740): `size.keycap` high, at least the theme's minimum wide, growing
/// sideways with its label at a large text scale (R-31-09-15).
///
/// [onLongPress] is the button's own slot on both platforms (`tab` sends `shift+tab`); no
/// gesture wrapper sits around a cap. A cap with neither
/// callback is disabled: on Android the theme dims it; on iOS, where `cupertino_ui` 1.0.1
/// would grey it instead, the cap hands the component its own tint back and dims itself, as
/// `app_ghost_button.dart` does.
///
/// **The latched state is the button's fill and nothing else (R-03-118, 2026-09-10).** The
/// high-emphasis form of the platform is the whole signal: the label keeps its case, its
/// weight and its text, and the cap draws no bar, no dot, no border and no glow of its own.
/// The upper-case label this file drew until 2026-09-10 is gone with it. A modifier cap
/// reports the state to assistive technology as a `toggled` flag, on one merged node with
/// the button's own label and tap, so the spoken sentence still says `held` or `locked`
/// (R-31-09-23).
class _KeyCap extends StatelessWidget {
  const _KeyCap({
    super.key,
    required this.semanticLabel,
    this.label,
    this.icon,
    this.name,
    this.flipIcon = false,
    this.onTap,
    this.onLongPress,
    this.latched,
    this.locked = false,
    this.filled = false,
  }) : assert(
         (label == null) != (icon == null),
         'a key cap carries a label or a glyph, never both',
       ),
       assert(
         name == null || icon != null,
         'a small name rides under a glyph, never under a label',
       );

  /// The face text of a cap with no glyph: the F keys' own `F1`…`F12` (2026-09-23).
  final String? label;

  /// The keybind glyph of the face: a Material Symbols icon of the R-32-401 set,
  /// never a Unicode glyph (2026-09-23).
  final IconData? icon;

  /// The key's small name under the glyph, in `type.micro.strong` — the Mac-keycap
  /// read of the 2026-09-23 decision, so the face never depends on the glyph alone.
  /// `null` on the arrow caps, whose arrows need no name. At the 2.0 text-scale clamp
  /// the face is exactly `size.keycap` high: 20 of glyph plus 28 of name.
  final String? name;

  /// Mirrors the glyph for a forward-facing key: `del` draws the mirrored
  /// backspace-key glyph of the forward delete.
  final bool flipIcon;

  final String semanticLabel;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// The platform's high-emphasis filled form without a latch (R-31-09-41):
  /// the Answer grid's `enter`, the grid's one filled cap. Unlike [latched]
  /// it reports no `toggled` flag — the cap is not a toggle.
  final bool filled;

  /// The latch state of a modifier cap, or `null` on a cap that has no latch. A modifier
  /// reports the state to assistive technology as a `toggled` flag (R-03-118); every other
  /// cap is not a toggle and reports none, so a screen reader never says "not ticked" for
  /// `esc`.
  final bool? latched;

  /// Whether a latched modifier is locked (R-03-118 as amended 2026-09-10, R-31-09-25). A
  /// locked cap underlines its name, the one mark every phone keyboard puts under the Shift
  /// glyph for caps lock; a held cap has the same fill and a plain name. Nothing else on the
  /// cap changes.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    // The spoken name rides the face, not a wrapper: the button's own semantics node
    // takes the label of its child (R-30-715, R-32-505). The `toggled` flag of R-03-118
    // rides the same face, so it merges onto that one node beside the label, the tap and
    // the enabled state, rather than adding a second node beside the button. A cap with no
    // latch is not a toggle and reports no flag. Inside the face is also inside the iOS
    // `Opacity` of a disabled cap, so a disabled latched modifier still reads. A two-line
    // face carries the spoken name on its own node and excludes the printed name, so the
    // button merges exactly one label.
    Widget face;
    if (icon == null) {
      face = Text(
        label!,
        semanticsLabel: semanticLabel,
        style: locked
            // R-31-09-25: a stronger typographic underline marks the lock.
            ? const TextStyle(
                decoration: TextDecoration.underline,
                decorationThickness: 2,
              )
            : null,
      );
    } else {
      Widget glyph = Icon(
        icon,
        size: AppSize.iconMd,
        semanticLabel: name == null ? semanticLabel : null,
      );
      if (flipIcon) {
        glyph = Transform.scale(
          scaleX: -1,
          alignment: Alignment.center,
          child: glyph,
        );
      }
      face = name == null
          ? glyph
          : Semantics(
              label: semanticLabel,
              excludeSemantics: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  glyph,
                  Text(
                    name!,
                    style: locked
                        ? AppType.microStrong.copyWith(
                            decoration: TextDecoration.underline,
                            decorationThickness: 2,
                          )
                        : AppType.microStrong,
                  ),
                ],
              ),
            );
    }
    if (latched != null) face = Semantics(toggled: latched, child: face);
    return _button(context, face);
  }

  Widget _button(BuildContext context, Widget face) {
    if (!_isIos) {
      // R-03-118: the high-emphasis form of the platform, the theme's primary fill under its
      // `onPrimary` label, against the outlined idle cap. Not the tonal form, which the owner
      // found unclear beside an outline (2026-09-10).
      return latched == true || filled
          ? FilledButton(
              onPressed: onTap,
              onLongPress: onLongPress,
              child: face,
            )
          : OutlinedButton(
              onPressed: onTap,
              onLongPress: onLongPress,
              child: face,
            );
    }
    // See [_capTheme]: the row's one style, read back for the component that has no slot.
    final ButtonStyle caps = OutlinedButtonTheme.of(context).style!;
    final Size minimumSize = caps.minimumSize!.resolve(const <WidgetState>{})!;
    final EdgeInsetsGeometry padding = caps.padding!.resolve(
      const <WidgetState>{},
    )!;
    // The same `radius.sm` the Android cap takes from the theme's shape (2026-09-23).
    final BorderRadius radius = BorderRadius.circular(AppRadius.sm);
    final Color primary = CupertinoTheme.of(context).primaryColor;
    return Opacity(
      opacity: onTap == null && onLongPress == null ? _opacityDisabled : 1,
      child: latched == true || filled
          ? CupertinoButton.filled(
              minimumSize: minimumSize,
              padding: padding,
              borderRadius: radius,
              onPressed: onTap,
              onLongPress: onLongPress,
              disabledColor: primary,
              child: face,
            )
          : CupertinoButton.tinted(
              minimumSize: minimumSize,
              padding: padding,
              borderRadius: radius,
              onPressed: onTap,
              onLongPress: onLongPress,
              // The component's own label ink is its `primaryColor`, `color.accent.primary`,
              // which measures 3.6 on the light tint over `color.bg.raised` (computed
              // 2026-09-09) and misses the 4.5 floor of R-30-720; `color.accent.text`
              // measures 4.68 there in both themes, so the cap hands the button that ink,
              // as `app_text_button.dart` does for its iOS branch.
              foregroundColor: AppColor.of(context).accentText,
              disabledColor: primary.withValues(
                alpha: CupertinoTheme.brightnessOf(context) == Brightness.light
                    ? kCupertinoButtonTintedOpacityLight
                    : kCupertinoButtonTintedOpacityDark,
              ),
              child: face,
            ),
    );
  }
}
