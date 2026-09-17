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
        OutlinedButtonThemeData;

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
/// (R-21-019a, R-10-036).
final class _RawKey {
  const _RawKey({
    required this.label,
    required this.semanticLabel,
    required this.sequence,
  });
  final String label;
  final String semanticLabel;
  final String sequence;
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
/// raw-CSI keys (R-21-019a, R-10-036).
const _RawKey _keyIns = _RawKey(
  label: 'ins',
  semanticLabel: 'Insert',
  sequence: '\x1b[2~',
);
const _RawKey _keyDel = _RawKey(
  label: 'del',
  semanticLabel: 'Delete',
  sequence: '\x1b[3~',
);
const _RawKey _keyHome = _RawKey(
  label: 'home',
  semanticLabel: 'Home',
  sequence: '\x1b[H',
);
const _RawKey _keyEnd = _RawKey(
  label: 'end',
  semanticLabel: 'End',
  sequence: '\x1b[F',
);
const _RawKey _keyPgup = _RawKey(
  label: 'pgup',
  semanticLabel: 'Page up',
  sequence: '\x1b[5~',
);
const _RawKey _keyPgdn = _RawKey(
  label: 'pgdn',
  semanticLabel: 'Page down',
  sequence: '\x1b[6~',
);

/// One send this file is still waiting to hear back about. [label] names it in a strip —
/// `esc`, `ctrl+c`, `backspace`, `enter`, or `typing` for a run of characters — and [timer]
/// is its `terminalReplyTimeout` deadline. See `KeyRowState._onAck`'s doc comment for how it
/// is matched to an incoming `SendInputAck`.
final class _PendingSend {
  const _PendingSend({required this.label, required this.timer});
  final String label;
  final Timer timer;
}

/// The terminal key row and the live typing surface. See this file's top doc comment.
class KeyRow extends StatefulWidget {
  const KeyRow({
    super.key,
    required this.paneId,
    required this.send,
    required this.sendInputAcks,
    this.linkState = KeyRowLinkState.live,
    this.offlineReason,
    this.onDiagnostics,
    this.reconciliationSignal,
    this.landscape = false,
    this.focusNode,
    this.composer,
    this.grid,
    this.panelOpen = false,
  });

  final String paneId;

  /// Shows every terminal key above the input bar.
  final bool panelOpen;

  /// Matches `RelayConnection.send`'s exact signature; a caller passes `connection.send`
  /// directly, mirroring `terminal.dart`'s `TerminalMessageSender` seam.
  final KeyRowSendFrame send;

  /// Every `send_input_ack` this pane's connection receives. A caller filters
  /// `connection.messages` to `MessageSendInputAck` and unwraps the payload; this file
  /// imports no `relay.dart` symbol.
  final Stream<SendInputAck> sendInputAcks;

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

class KeyRowState extends State<KeyRow> with WidgetsBindingObserver {
  late final ChordLatch _chordLatch = ChordLatch(lockWindow: kDoubleTapTimeout);
  late final StreamSubscription<void> _latchSub;
  StreamSubscription<SendInputAck>? _ackSub;

  int _corrSeq = 0;
  String _nextCorr() => 'key-row-${_corrSeq++}';

  final List<_PendingSend> _pending = <_PendingSend>[];

  /// The label of the send whose acknowledgement never came (R-30-518), or `null`.
  String? _outcomeUnknownLabel;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.focusNode?.addListener(_onFocusChanged);
    _latchSub = _chordLatch.changes.listen((_) {
      if (mounted) setState(() {});
    });
    _ackSub = widget.sendInputAcks.listen(_onAck);
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
    for (final _PendingSend send in _pending) {
      send.timer.cancel();
    }
    unawaited(_ackSub?.cancel());
    unawaited(_latchSub.cancel());
    widget.focusNode?.removeListener(_onFocusChanged);
    _chordLatch.dispose();
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

  /// Tracks Composer sends with the same acknowledgement states (R-03-130).
  void sendInput(SendInput input, {required String label}) =>
      _dispatch(input, label: label);

  // --- Sending ---

  /// One `send_input` frame, tracked until its acknowledgement or its deadline. A send that
  /// follows a failure clears the failure strip: the person typed again, which is the one
  /// recovery R-31-09-13 allows.
  void _dispatch(SendInput input, {required String label}) {
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
    late final _PendingSend send;
    send = _PendingSend(
      label: label,
      timer: Timer(terminalReplyTimeout, () => _onAckTimeout(send)),
    );
    _pending.add(send);
    widget.send(Message.sendInput(input), corr: _nextCorr());
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

  /// A key cap press for one of the six keys with no logical name: `haptic.select`, then
  /// one raw-sequence frame (R-10-036).
  void _sendRawText(String text, {required String label}) {
    if (!_sendingEnabled) return;
    unawaited(AppHaptic.select());
    _dispatch(
      SendInput(paneId: widget.paneId, text: text),
      label: label,
    );
  }

  /// Resolves the oldest still-pending send against an incoming `SendInputAck`. See this
  /// file's top doc comment for why FIFO, not `corr`, is what is available to match with.
  void _onAck(SendInputAck ack) {
    if (_pending.isEmpty) return;
    final _PendingSend send = _pending.removeAt(0);
    send.timer.cancel();
    if (ack.accepted) return;
    // R-31-09-13, R-11-228: nothing here ever re-sends.
    unawaited(AppHaptic.error());
    setState(() => _errorMessage = 'Not sent: ${send.label}');
  }

  void _onAckTimeout(_PendingSend send) {
    if (_pending.contains(send)) _markOutcomeUnknown();
  }

  /// R-30-518's outcome-unknown state for whatever is still in flight: the oldest send
  /// names the strip, and every pending send is dropped, because its acknowledgement will
  /// not come — the link is gone, the app is in the background, or the deadline passed.
  /// The next `pane_frame` reconciles it: the grid is the record of what the pane received.
  void _markOutcomeUnknown() {
    if (_pending.isEmpty) return;
    final String label = _pending.first.label;
    for (final _PendingSend send in _pending) {
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
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double module = _moduleWidth(constraints.maxWidth);
          return _capTheme(
            context,
            minWidth: module,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _buildLeadingColumn(),
                const SizedBox(width: AppSpace.space2),
                Expanded(
                  child: SingleChildScrollView(
                    key: const ValueKey<String>('keyRowScrollRegion'),
                    scrollDirection: Axis.horizontal,
                    child: _buildMiddleColumns(module),
                  ),
                ),
                const SizedBox(width: AppSpace.space2),
                _buildTrailingColumn(),
              ],
            ),
          );
        },
      ),
    ),
  );

  /// One `space.2` between two rows of a column, and an empty cell where a column has no key
  /// on a row: `size.keycap` high, so the rows of every column stay level.
  static const Widget _rowGap = SizedBox(height: AppSpace.space2);
  static const Widget _emptyCell = SizedBox(height: AppSize.keycapHeight);

  /// Column one, pinned at the leading edge: `esc` on row one, then `ins` over `del` in the
  /// expansion, the first navigation pair (R-03-117). `esc` is the way out of a mode a person
  /// entered by accident, and a way out behind a scroll is not a way out (R-31-09-16).
  Widget _buildLeadingColumn() {
    final bool sendable = _sendingEnabled;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _KeyCap(
          key: const ValueKey<String>('keyRowEsc'),
          label: 'esc',
          semanticLabel: 'Escape',
          onTap: sendable
              ? () => _sendKeyNames(<String>['Esc'], label: 'esc')
              : null,
        ),
        if (widget.panelOpen) ...<Widget>[
          _rowGap,
          _rawCap(_keyIns, sendable),
          _rowGap,
          _rawCap(_keyDel, sendable),
        ],
      ],
    );
  }

  /// The middle four columns scroll together and preserve the navigation pairs.
  Widget _buildMiddleColumns(double module) {
    final bool sendable = _sendingEnabled;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _KeyCap(
              key: const ValueKey<String>('keyRowTab'),
              label: 'tab',
              semanticLabel: 'Tab',
              onTap: sendable
                  ? () => _sendKeyNames(<String>['Tab'], label: 'tab')
                  : null,
              onLongPress: sendable
                  ? () =>
                        _sendKeyNames(<String>['shift+tab'], label: 'shift+tab')
                  : null,
            ),
            const SizedBox(width: AppSpace.space2),
            _KeyCap(
              key: const ValueKey<String>('keyRowCtrl'),
              label: 'ctrl',
              semanticLabel: _latchSpoken(ChordModifier.ctrl),
              latched: _chordLatch.isLatched(ChordModifier.ctrl),
              locked: _chordLatch.isLocked(ChordModifier.ctrl),
              onTap: sendable ? () => _toggleLatch(ChordModifier.ctrl) : null,
            ),
            const SizedBox(width: AppSpace.space2),
            // Column four: `alt`, beside `ctrl`. It latches and locks exactly as `ctrl`
            // does (R-31-09-19, R-31-09-23); the latch raises the keyboard, which closes
            // the expansion, per R-31-09-17.
            _KeyCap(
              key: const ValueKey<String>('keyRowAlt'),
              label: 'alt',
              semanticLabel: _latchSpoken(ChordModifier.alt),
              latched: _chordLatch.isLatched(ChordModifier.alt),
              locked: _chordLatch.isLocked(ChordModifier.alt),
              onTap: sendable ? () => _toggleLatch(ChordModifier.alt) : null,
            ),
            // Column five is empty on row one: the inverted T is bottom-aligned, `↑`
            // on row two over `↓` on row three (R-03-117, amended 2026-09-16).
          ],
        ),
        if (widget.panelOpen) ...<Widget>[
          _rowGap,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Columns two and three: the top of the `home` and `pgup` pairs.
              _rawCap(_keyHome, sendable),
              const SizedBox(width: AppSpace.space2),
              _rawCap(_keyPgup, sendable),
              // Column five: `↑`, directly over `↓` on row three (R-10-037).
              const SizedBox(width: AppSpace.space2),
              SizedBox(width: module, height: AppSize.keycapHeight),
              const SizedBox(width: AppSpace.space2),
              _arrowCap(_arrowUp, sendable),
            ],
          ),
          _rowGap,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Columns two and three: the bottom of each pair, directly under row two's.
              // Columns four and five: `←` and the stem `↓` of the inverted T.
              _rawCap(_keyEnd, sendable),
              const SizedBox(width: AppSpace.space2),
              _rawCap(_keyPgdn, sendable),
              const SizedBox(width: AppSpace.space2),
              _arrowCap(_arrowLeft, sendable),
              const SizedBox(width: AppSpace.space2),
              _arrowCap(_arrowDown, sendable),
            ],
          ),
        ],
      ],
    );
  }

  /// The right arrow occupies the fixed sixth column, on the bottom row beside `↓`.
  Widget _buildTrailingColumn() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: <Widget>[
      _emptyCell,
      _rowGap,
      _emptyCell,
      _rowGap,
      _arrowCap(_arrowRight, _sendingEnabled),
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
    label: def.label,
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

/// The six-column module of R-03-133: how many `size.keycap` caps fit [width] at `space.2`
/// gaps — never fewer than six, the count the grid of R-03-117 is built on — and the width
/// that lets exactly that many fill it. Every cap in every row takes it as a minimum width,
/// so the three rows line up as one grid and each column carries one meaning. Below six caps
/// of room the module floors at `size.keycap` and the row scrolls, per R-32-363.
double _moduleWidth(double width) {
  if (!width.isFinite) return AppSize.keycapWidth;
  const int columns = 6;
  return math.max(
    AppSize.keycapWidth,
    (width - (columns - 1) * AppSpace.space2) / columns,
  );
}

/// The one style every cap under [child] takes, per R-31-09-21 and R-03-059: `size.keycap`
/// high, at least [minWidth] wide, `space.2` of horizontal padding, `type.mono.key`. On
/// Android it is the row's own `OutlinedButtonTheme` and `FilledButtonTheme`, laid over the
/// app theme of `app.dart`, which keeps every colour, side, overlay and shape it sets. On iOS
/// the type reaches `CupertinoButton` through `textTheme.actionTextStyle`, the one slot the
/// component reads; `cupertino_ui` 1.0.1 has no theme slot for a button's size or padding
/// (R-33-033), so [_KeyCap] reads this same style back from `OutlinedButtonTheme.of` and hands
/// the component the minimum size and the padding the Android cap takes from the theme.
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
      EdgeInsets.symmetric(horizontal: AppSpace.space2),
    ),
    textStyle: const WidgetStatePropertyAll<TextStyle>(AppType.monoKey),
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
    this.onTap,
    this.onLongPress,
    this.latched,
    this.locked = false,
  }) : assert(
         (label == null) != (icon == null),
         'a key cap carries a label or a glyph, never both',
       );

  final String? label;
  final IconData? icon;
  final String semanticLabel;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// The latch state of a modifier cap, or `null` on a cap that has no latch. A modifier
  /// reports the state to assistive technology as a `toggled` flag (R-03-118); every other
  /// cap is not a toggle and reports none, so a screen reader never says "not ticked" for
  /// `esc`.
  final bool? latched;

  /// Whether a latched modifier is locked (R-03-118 as amended 2026-09-10, R-31-09-25). A
  /// locked cap underlines its label, the one mark every phone keyboard puts under the Shift
  /// glyph for caps lock; a held cap has the same fill and a plain label. Nothing else on the
  /// cap changes.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    // The spoken name rides the face, not a wrapper: the button's own semantics node
    // takes the label of its child (R-30-715, R-32-505). The `toggled` flag of R-03-118
    // rides the same face, so it merges onto that one node beside the label, the tap and
    // the enabled state, rather than adding a second node beside the button. A cap with no
    // latch is not a toggle and reports no flag. Inside the face is also inside the iOS
    // `Opacity` of a disabled cap, so a disabled latched modifier still reads.
    Widget face = icon != null
        ? Icon(icon, size: AppSize.iconMd, semanticLabel: semanticLabel)
        : Text(
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
    if (latched != null) face = Semantics(toggled: latched, child: face);
    return _button(context, face);
  }

  Widget _button(BuildContext context, Widget face) {
    if (!_isIos) {
      // R-03-118: the high-emphasis form of the platform, the theme's primary fill under its
      // `onPrimary` label, against the outlined idle cap. Not the tonal form, which the owner
      // found unclear beside an outline (2026-09-10).
      return latched == true
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
    final Color primary = CupertinoTheme.of(context).primaryColor;
    return Opacity(
      opacity: onTap == null && onLongPress == null ? _opacityDisabled : 1,
      child: latched == true
          ? CupertinoButton.filled(
              minimumSize: minimumSize,
              padding: padding,
              onPressed: onTap,
              onLongPress: onLongPress,
              disabledColor: primary,
              child: face,
            )
          : CupertinoButton.tinted(
              minimumSize: minimumSize,
              padding: padding,
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
