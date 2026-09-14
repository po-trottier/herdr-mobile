/// The manual pairing screen (`WP-15-c`, wave 7 of `docs/90-implementation-plan.md`), the
/// QR-unavailable fallback drawn from `docs/31-mockups/03-pair-code.md` at route
/// `/pair/manual` (R-90-010): a relay-address field, a computer-code field, and six ordered
/// word fields that converge on the same [PairingInput] the QR path produces
/// (`docs/13-security-pairing.md` R-13-017 to R-13-027, R-30-901).
///
/// This file owns the field layout, the keyboard hardening, the paste-fill behaviour, the
/// per-field blur validation, and the pairing-error-text mapping (`docs/30-ux-spec.md`'s
/// table). It owns no route: `app/lib/routing.dart` (`WP-12-b`, not this package's `Paths.`
/// line) wires `/pair/manual` to this widget on request, and supplies [ManualPairingScreen]'s
/// constructor arguments — the loaded EFF word list, a saved relay origin, and the connected
/// flag — from whatever provider owns that state.
///
/// It also drives no handshake: `attemptPairing`, `RelayConnection` and `BiometricGate`
/// belong to Phase 13 and Phase 14, outside this package's `Needs.` line (R-90-024). [onPair]
/// is this screen's whole contract with that later phase — a caller adapts its own
/// `Result<PairingOutcome>` into a [ManualPairingResult] before calling back in, exactly as
/// `LockScreen`'s `onUnlocked` hook lets that screen stay ignorant of where it routes next. A
/// `null` [onPair] or [onScanInstead] is a deliberate no-op (R-90-016), the same idiom
/// `routing.dart`'s `_noOpCreate` already uses for a control this package does not yet wire.
library;

import 'dart:async' show unawaited;
import 'dart:convert' show base64Url;

import 'package:connectivity_plus/connectivity_plus.dart'
    show Connectivity, ConnectivityResult;
import 'package:cupertino_ui/cupertino_ui.dart'
    show
        Alignment,
        AnimatedContainer,
        Axis,
        Border,
        BorderRadius,
        BorderSide,
        BoxDecoration,
        DecoratedBox,
        BuildContext,
        Column,
        Container,
        CrossAxisAlignment,
        CupertinoNavigationBar,
        CupertinoPageScaffold,
        CupertinoTextField,
        EdgeInsets,
        Expanded,
        Focus,
        FocusNode,
        Flex,
        Flexible,
        FocusScope,
        Icon,
        MainAxisSize,
        MediaQuery,
        Padding,
        Row,
        SafeArea,
        Semantics,
        SingleChildScrollView,
        Size,
        SizedBox,
        State,
        StatefulWidget,
        StatelessWidget,
        Text,
        TextAlignVertical,
        TextDirection,
        TextEditingController,
        View,
        VoidCallback,
        Widget;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/semantics.dart' show SemanticsService;
import 'package:flutter/services.dart'
    show
        Clipboard,
        KeyDownEvent,
        KeyEvent,
        LogicalKeyboardKey,
        SmartDashesType,
        SmartQuotesType,
        TextCapitalization,
        TextInputAction,
        TextInputType;
import 'package:flutter/widgets.dart'
    show
        CustomScrollView,
        KeyEventResult,
        LayoutBuilder,
        SliverPadding,
        SliverToBoxAdapter,
        WidgetsBinding;
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart'
    show PreferredSize, Scaffold, SliverAppBar;

import '../core/result/result.dart' show Err, Ok;
import '../services/origin.dart'
    show
        RelayOrigin,
        RelayOriginErrorCode,
        RelayOriginException,
        parseRelayOrigin;
import '../services/pairing.dart'
    show
        PairingInput,
        PairingOutcome,
        PhraseErrorCode,
        PhraseException,
        autocompleteWords,
        buildManualPairingInput,
        isPairingPayload,
        normalizePhraseInput,
        parsePairingUri,
        splitPastedPhrase,
        validatePhrase;
import '../widgets/app_filled_button.dart';
import '../widgets/app_section_header.dart';
import '../widgets/app_strip.dart';
import '../widgets/app_text_button.dart';
import '../widgets/key_label.dart';
import '../widgets/theme/app_color.dart';
import '../widgets/theme/app_haptic.dart';
import '../widgets/theme/app_pressable.dart';
import '../widgets/theme/app_radius.dart';
import '../widgets/theme/app_size.dart';
import '../widgets/theme/app_space.dart';
import '../widgets/theme/app_type.dart';
import '../widgets/theme/chrome_confirmation_dialog.dart';
import '../widgets/treatments.dart';

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

/// `border.focus` and `border.error`, per the width table beside `docs/32-design-language.md`
/// R-32-330: both 2 px, `color.accent.text` while a field holds focus (R-32-503) and
/// `color.status.error` on a field that failed (R-32-504). Local constants beside their one
/// caller, per `app_elev.dart` (`WP-12-a`).
const double _borderFocusWidth = 2;
const double _borderErrorWidth = 2;

/// The screen edge inset of R-30-230, applied per block rather than on the scroll view, so the
/// section headers, which carry their own `space.4` inset (`AppSectionHeader.upperCase`), line
/// up with the fields under them instead of sitting one inset further in.
const EdgeInsets _inset = EdgeInsets.symmetric(horizontal: AppSpace.space4);

/// The number of ordered word fields, per R-30-903 and R-13-017. `pairing.dart` keeps its own
/// copy private; six is a fixed, public fact of the phrase format, not an implementation
/// detail this file borrows.
const int _wordCount = 6;

/// R-11-112's routing-handle shape, mirrored here because `pairing.dart` exposes no
/// standalone single-field handle validator (its own `_validateHandle` is private, used only
/// inside the whole-input assembly `buildManualPairingInput` drives). Mirrors that function's
/// exact check: 22 unpadded base64url characters decoding to 16 bytes.
const int _handleLen = 22;
const int _handleBytes = 16;

bool _isValidHandle(String candidate) {
  if (candidate.length != _handleLen) {
    return false;
  }
  try {
    return base64Url.decode(base64Url.normalize(candidate)).length ==
        _handleBytes;
  } on FormatException {
    return false;
  }
}

/// The exact pairing error text table sentences this screen may show (`docs/30-ux-spec.md`),
/// for the codes a pre-submit local validation can raise. [wordIndex] is exact and 1-based,
/// per the table's own "the number is exact" callouts; `null` for the codes that name no
/// field.
String _sentenceFor(
  PhraseErrorCode code, {
  int? wordIndex,
  int? enteredCount,
}) => switch (code) {
  PhraseErrorCode.phraseWordUnknown =>
    'Word $wordIndex is not in the list. Check it against your computer.',
  PhraseErrorCode.phraseWordCount =>
    'A phrase holds six words. You entered $enteredCount.',
  PhraseErrorCode.phraseSeparator =>
    'Use one space or one hyphen between words.',
  PhraseErrorCode.phraseCase => 'A phrase holds lower case letters only.',
  PhraseErrorCode.phraseExpired =>
    'That phrase expired. Press {p} in the Relay pane for a new one.',
  PhraseErrorCode.phraseAttempts =>
    'Three tries used. The computer made a new phrase. Read it again.',
};

String _originSentenceFor(RelayOriginErrorCode code) => switch (code) {
  RelayOriginErrorCode.relayOriginInvalid =>
    'That is not a relay address. Use the form https://relay.example.com.',
  RelayOriginErrorCode.relayOriginInsecure => 'A relay address must start with https, unless the computer is on your own network.',
};

const String _handleMalformedSentence =
    'That computer address is malformed. Read the code again.';

/// The one sentence mockup `03-pair-code.md` R-31-03-13 fixes for a link failure. The
/// pairing error text table of `docs/30-ux-spec.md` owns no code for it, so it lives here
/// rather than in [_sentenceFor].
const String _linkFailedSentence =
    'Could not pair. Check the network and the six words, then try again.';

/// R-30-940's headline, and the name-free detail line R-31-02-08 fixes for both pairing
/// screens ("`/pair/manual` MUST use this same variant"): `host_in_use` arrives before the
/// Noise tunnel exists, so no computer name is known yet.
const String _hostInUseHeadline = 'Computer in use on another phone';
const String _hostInUseDetail =
    'Another phone is connected to that computer. Disconnect there, or remove that phone in '
    'the Relay pane, then try again.';

/// One post-handshake outcome a caller reports back through [ManualPairingScreen.onPair].
/// This screen holds no relay or handshake type of its own (R-90-024); a caller adapts its
/// real `Result<PairingOutcome>` into one of these two cases.
sealed class ManualPairingResult {
  const ManualPairingResult();
}

/// The handshake completed. [ManualPairingScreen] forwards [outcome] to
/// [ManualPairingScreen.onPaired] and fires `haptic.commit`.
final class ManualPairingSucceeded extends ManualPairingResult {
  const ManualPairingSucceeded(this.outcome);
  final PairingOutcome outcome;
}

/// The attempt failed with one of the four codes this screen can render: the two
/// `PhraseErrorCode` values `attemptPairing` classifies locally
/// (`phraseExpired`, `phraseAttempts`), the wire `host_in_use` error (R-11-124,
/// R-31-02-08), or [ManualPairingFailureCode.linkFailed] — every cause the pairing error
/// text table of `docs/30-ux-spec.md` does not name (the relay unreachable, a connection
/// or a local step that failed, or a handshake that failed while the phrase still has
/// tries left), per mockup `03-pair-code.md` R-31-03-13.
final class ManualPairingFailed extends ManualPairingResult {
  const ManualPairingFailed(this.code, {this.detail});
  final ManualPairingFailureCode code;

  /// The raw cause text of a [ManualPairingFailureCode.linkFailed], shown in
  /// `type.mono.code` under the sentence, per R-30-803. Null for the classified codes.
  final String? detail;
}

enum ManualPairingFailureCode {
  phraseExpired,
  phraseAttempts,
  hostInUse,
  linkFailed,
}

void _noOp() {}

/// The manual pairing screen. See this file's top doc comment for the split between what this
/// widget owns (the fields, the validation, the error text) and what a caller supplies (the
/// word list, the saved-origin and connected state, and the handshake itself).
class ManualPairingScreen extends StatefulWidget {
  const ManualPairingScreen({
    super.key,
    required this.effWords,
    this.savedRelayOrigin,
    this.isConnected = false,
    this.initialInput,
    this.onPair,
    this.onPaired,
    this.onScanInstead,
  });

  /// The bundled EFF long word list (R-13-025), for [validatePhrase]'s and
  /// [autocompleteWords]'s membership checks. Loading it is a caller's job: no state in this
  /// mockup's `## States` table describes a wordlist-loading phase.
  final List<String> effWords;

  /// The last connected computer's origin is an editable default (R-03-126).
  /// A pairing URI supplies its own origin. First pairing has no default.
  final RelayOrigin? savedRelayOrigin;

  /// Whether a computer is currently connected, per R-30-945 and R-30-958.
  final bool isConnected;

  /// Validated link fields. Cold and warm links refill the same editable form
  /// through [_fillFromPairingInput], per R-22-034 and R-31-03-14.
  /// A link never starts pairing. Other entry paths supply no initial input.
  final PairingInput? initialInput;

  /// Fires when `Pair` is pressed with every field valid (R-31-03-04). A caller drives the
  /// actual `attemptPairing` handshake and reports back one [ManualPairingResult]. `null` is a
  /// deliberate no-op (R-90-016).
  final Future<ManualPairingResult> Function(PairingInput input)? onPair;

  /// Fires once [onPair] reports [ManualPairingSucceeded]. Per R-31-04-10's sibling rule on
  /// `/lock`, this widget never decides where to go next; a caller supplies that.
  final void Function(PairingOutcome outcome)? onPaired;

  /// Callout 10: routes to `/pair/scan`. `null` is a deliberate no-op (R-90-016);
  /// `routing.dart` is not this package's path.
  final VoidCallback? onScanInstead;

  @override
  State<ManualPairingScreen> createState() => _ManualPairingScreenState();
}

class _ManualPairingScreenState extends State<ManualPairingScreen> {
  late final TextEditingController _originController = TextEditingController(
    text:
        widget.initialInput?.relayOrigin.canonical ??
        widget.savedRelayOrigin?.canonical ??
        '',
  );
  final TextEditingController _handleController = TextEditingController();
  final List<TextEditingController> _wordControllers = List.generate(
    _wordCount,
    (_) => TextEditingController(),
  );

  final FocusNode _originFocusNode = FocusNode(debugLabel: 'relay-origin');
  final FocusNode _handleFocusNode = FocusNode(debugLabel: 'computer-code');
  final List<FocusNode> _wordFocusNodes = List.generate(
    _wordCount,
    (index) => FocusNode(debugLabel: 'word-$index'),
  );

  bool _submitting = false;
  bool _offline = false;
  bool _hostInUse = false;
  bool _linkFailed = false;
  bool _linkStarted = false;
  String? _linkFailureDetail;

  String? _originError;
  String? _handleError;
  int? _wordErrorIndex;
  String? _wordErrorMessage;
  String? _phraseLevelError;
  int? _focusedWordIndex;

  @override
  void initState() {
    super.initState();
    for (final controller in <TextEditingController>[
      _originController,
      _handleController,
      ..._wordControllers,
    ]) {
      controller.addListener(_onFieldEdited);
    }
    _originFocusNode.addListener(_onOriginFocusChange);
    _handleFocusNode.addListener(_onHandleFocusChange);
    for (var i = 0; i < _wordCount; i++) {
      final index = i;
      _wordFocusNodes[index].addListener(() => _onWordFocusChange(index));
    }
    unawaited(_checkOffline());
    final PairingInput? initialInput = widget.initialInput;
    if (initialInput != null) {
      // Deferred a frame: `_fillFromPairingInput` calls `setState` and
      // `FocusScope.of(context)`, neither safe to call from `initState` itself.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fillFromPairingInput(initialInput, fromLink: true);
      });
    }
  }

  @override
  void didUpdateWidget(ManualPairingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final input = widget.initialInput;
    if (input != null && input != oldWidget.initialInput) {
      _fillFromPairingInput(input, fromLink: true);
    }
  }

  void _onFieldEdited() {
    final input = widget.initialInput;
    if (!_linkStarted || input == null) return;
    if (_originController.text != input.relayOrigin.canonical ||
        _handleController.text != input.handle ||
        _wordControllers.map((controller) => controller.text).join('-') !=
            input.phrase) {
      _linkStarted = false;
    }
  }

  @override
  void dispose() {
    _originController.dispose();
    _handleController.dispose();
    for (final controller in _wordControllers) {
      controller.dispose();
    }
    _originFocusNode.dispose();
    _handleFocusNode.dispose();
    for (final node in _wordFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _checkOffline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (!mounted) {
        return;
      }
      setState(() => _offline = results.contains(ConnectivityResult.none));
    } on Exception {
      // Mirrors `lock_screen.dart`'s own precedent: a connectivity read failing costs this
      // screen nothing beyond not showing the strip.
    }
  }

  bool get _originValid =>
      parseRelayOrigin(_originController.text) is Ok<RelayOrigin>;

  bool get _handleValid => _isValidHandle(_handleController.text);

  bool get _wordsValid {
    if (_wordControllers.any((controller) => controller.text.isEmpty)) {
      return false;
    }
    final phrase = _wordControllers
        .map((controller) => controller.text)
        .join('-');
    return validatePhrase(phrase, widget.effWords) is Ok<String>;
  }

  /// R-31-03-04's three conditions, plus R-30-947's own offline carve-out ("`Pair` is
  /// disabled, so no switch starts").
  bool get _canSubmit =>
      !_submitting && !_offline && _originValid && _handleValid && _wordsValid;

  // --- Origin field ---

  void _onOriginFocusChange() {
    if (_originFocusNode.hasFocus) {
      setState(() {});
      return;
    }
    _validateOriginOnBlur();
  }

  void _validateOriginOnBlur() {
    final text = _originController.text;
    if (text.isEmpty) {
      setState(() => _originError = null);
      return;
    }
    final result = parseRelayOrigin(text);
    final sentence = switch (result) {
      Ok<RelayOrigin>() => null,
      Err<RelayOrigin>(cause: final cause) when cause is RelayOriginException =>
        _originSentenceFor(cause.code),
      Err<RelayOrigin>() => null,
    };
    setState(() => _originError = sentence);
    if (sentence != null) {
      _announce(sentence);
    }
  }

  /// R-30-742's second bullet: a validation failure with no changed node to carry it (the
  /// field only changes its border colour) is one of the four named one-shot cases, per
  /// R-30-912. Mirrors `pane_actions_sheet.dart`'s `_readLast20Lines` idiom exactly: never the
  /// deprecated `SemanticsService.announce`, and only after `MediaQuery.supportsAnnounceOf`
  /// confirms the platform carries it.
  /// A `keyedText` template is spoken as its plain sentence, per R-32-599.
  void _announce(String message) {
    if (MediaQuery.supportsAnnounceOf(context)) {
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          keyedPlain(message),
          TextDirection.ltr,
        ),
      );
    }
  }

  // --- Handle field ---

  void _onHandleFocusChange() {
    if (_handleFocusNode.hasFocus) {
      setState(() {});
      return;
    }
    final text = _handleController.text;
    final sentence = text.isEmpty || _isValidHandle(text)
        ? null
        : _handleMalformedSentence;
    setState(() => _handleError = sentence);
    if (sentence != null) {
      _announce(sentence);
    }
  }

  // --- Word fields ---

  void _onWordFocusChange(int index) {
    final node = _wordFocusNodes[index];
    if (node.hasFocus) {
      setState(() => _focusedWordIndex = index);
      return;
    }
    if (_focusedWordIndex == index) {
      setState(() => _focusedWordIndex = null);
    }
    _validateWordOnBlur(index);
  }

  void _validateWordOnBlur(int index) {
    final raw = _wordControllers[index].text;
    if (raw.isEmpty) {
      if (_wordErrorIndex == index) {
        setState(() {
          _wordErrorIndex = null;
          _wordErrorMessage = null;
        });
      }
      return;
    }
    final normalized = normalizePhraseInput(raw);
    if (widget.effWords.contains(normalized)) {
      if (_wordErrorIndex == index) {
        setState(() {
          _wordErrorIndex = null;
          _wordErrorMessage = null;
        });
      }
      return;
    }
    final message = _sentenceFor(
      PhraseErrorCode.phraseWordUnknown,
      wordIndex: index + 1,
    );
    setState(() {
      _wordErrorIndex = index;
      _wordErrorMessage = message;
      _phraseLevelError = null;
      _linkFailed = false;
      _linkFailureDetail = null;
    });
    unawaited(AppHaptic.error());
    _announce(message);
  }

  KeyEventResult _handleWordKey(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _wordControllers[index].text.isEmpty &&
        index > 0) {
      _wordFocusNodes[index - 1].requestFocus();
    }
    return KeyEventResult.ignored;
  }

  /// R-31-03-02: advances on an accepted suggestion, focuses the field after the last one a
  /// paste filled.
  void _acceptSuggestion(int index, String word) {
    _wordControllers[index].text = word;
    setState(() {
      if (_wordErrorIndex == index) {
        _wordErrorIndex = null;
        _wordErrorMessage = null;
      }
    });
    _advanceFocusAfter(index);
  }

  void _advanceFocusAfter(int index) {
    if (index < _wordCount - 1) {
      _wordFocusNodes[index + 1].requestFocus();
    } else {
      FocusScope.of(context).unfocus();
    }
  }

  /// R-30-907, R-31-03-03: a value that normalises into more than one word — from any word
  /// field, pasted or typed fast enough to look the same — fills the six fields from word 1,
  /// regardless of which field received it.
  void _onWordChanged(int index, String value) {
    final split = splitPastedPhrase(value, widget.effWords);
    if (split.length > 1) {
      _fillFromMultiWordInput(value, split);
      return;
    }
    setState(
      () {},
    ); // Recomputes `_canSubmit`; no error surfaces until blur, per R-30-906.
  }

  void _fillFromMultiWordInput(String raw, List<String> split) {
    for (final controller in _wordControllers) {
      controller.clear();
    }
    final fillCount = split.length > _wordCount ? _wordCount : split.length;
    for (var i = 0; i < fillCount; i++) {
      _wordControllers[i].text = split[i];
    }

    int? unknownIndex;
    String? phraseLevel;
    final phraseResult = validatePhrase(raw, widget.effWords);
    if (phraseResult case Err<String>(cause: final cause)
        when cause is PhraseException) {
      switch (cause.code) {
        case PhraseErrorCode.phraseWordUnknown:
          final index = split.indexWhere(
            (word) => !widget.effWords.contains(word),
          );
          unknownIndex = index < 0 ? null : index;
        case PhraseErrorCode.phraseWordCount:
          phraseLevel = _sentenceFor(cause.code, enteredCount: split.length);
        case PhraseErrorCode.phraseSeparator || PhraseErrorCode.phraseCase:
          phraseLevel = _sentenceFor(cause.code);
        case PhraseErrorCode.phraseExpired || PhraseErrorCode.phraseAttempts:
          break; // `validatePhrase` never raises these two (R-13-027's post-attempt codes).
      }
    }

    final wordMessage = unknownIndex == null
        ? null
        : _sentenceFor(
            PhraseErrorCode.phraseWordUnknown,
            wordIndex: unknownIndex + 1,
          );
    setState(() {
      _wordErrorIndex = unknownIndex;
      _wordErrorMessage = wordMessage;
      _phraseLevelError = phraseLevel;
      _linkFailed = false;
      _linkFailureDetail = null;
    });
    final announcement = wordMessage ?? phraseLevel;
    if (announcement != null) {
      _announce(announcement);
    }
    _advanceFocusAfter(fillCount == 0 ? -1 : fillCount - 1);
  }

  // --- Paste ---

  /// R-31-03-12: reads the whole clipboard on one tap and fills whichever fields it
  /// recognises, trying the richest shape first. A `herdr-remote://pair` URI (R-11-140) fills
  /// all three groups in one action, through the same [parsePairingUri] the QR and deep-link
  /// paths already use (R-30-901's convergence). Failing that, a value that splits into more
  /// than one recognisable word is a phrase-only paste and reuses
  /// [_fillFromMultiWordInput] verbatim — the exact same fill R-31-03-03 already gives a
  /// paste landing directly in a word field. Failing that, a single token matching the
  /// handle form of R-11-112 fills the computer code alone. Anything else, or an empty
  /// clipboard, is a quiet no-op: this control does not assume every paste succeeds, and
  /// R-31-03-07 forbids inventing an error message no failure code names.
  Future<void> _onPastePressed() async {
    if (_submitting) {
      return;
    }
    final String text;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final raw = data?.text;
      if (raw == null || raw.trim().isEmpty) {
        return;
      }
      text = raw.trim();
    } on Exception {
      return; // Clipboard access failed; fail quietly, per this method's own doc comment.
    }
    if (!mounted) {
      return;
    }
    if (isPairingPayload(text)) {
      final result = parsePairingUri(text, widget.effWords);
      if (result is Ok<PairingInput>) {
        _fillFromPairingInput(result.value);
      }
      // A malformed `herdr-remote://` URI cannot also be a bare phrase or handle, so a
      // parse failure ends the attempt here rather than falling through.
      return;
    }
    final split = splitPastedPhrase(text, widget.effWords);
    if (split.length > 1) {
      _fillFromMultiWordInput(text, split);
      return;
    }
    if (_isValidHandle(text)) {
      _handleController.text = text;
      setState(() => _handleError = null);
    }
    // Anything else is unrecognised clipboard content; nothing changes.
  }

  void _fillFromPairingInput(PairingInput input, {bool fromLink = false}) {
    _linkStarted = false;
    _originController.text = input.relayOrigin.canonical;
    _handleController.text = input.handle;
    final words = splitPastedPhrase(input.phrase, widget.effWords);
    for (var i = 0; i < _wordCount; i++) {
      _wordControllers[i].text = i < words.length ? words[i] : '';
    }
    _linkStarted = fromLink;
    setState(() {
      _originError = null;
      _handleError = null;
      _wordErrorIndex = null;
      _wordErrorMessage = null;
      _phraseLevelError = null;
      _linkFailed = false;
      _linkFailureDetail = null;
    });
    FocusScope.of(context).unfocus();
  }

  // --- Submit ---

  Future<void> _onPairPressed() async {
    final onPair = widget.onPair;
    if (onPair == null) {
      return; // R-90-016: deliberate no-op until a later phase wires the handshake.
    }
    final phrase = _wordControllers
        .map((controller) => controller.text)
        .join('-');
    final originText = _originController.text;
    final inputResult = buildManualPairingInput(
      relayOriginText: originText,
      handleText: _handleController.text,
      phraseText: phrase,
      effWords: widget.effWords,
    );
    if (inputResult is! Ok<PairingInput>) {
      return; // `_canSubmit` already guarantees this does not happen; defensive only.
    }
    if (_linkStarted && widget.isConnected) {
      final confirmed = await showChromeAlertDialog<bool>(
        context: context,
        title: 'Switch computers?',
        body:
            'This disconnects the computer you are using now. It stays paired.',
        defaultAction: (label: 'Disconnect and pair', result: true),
        otherAction: (label: 'Cancel', result: false),
      ).result;
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _submitting = true;
      _hostInUse = false;
      _linkFailed = false;
      _linkFailureDetail = null;
    });
    final result = await onPair(inputResult.value);
    if (!mounted) {
      return;
    }
    switch (result) {
      case ManualPairingSucceeded(:final outcome):
        setState(() => _submitting = false);
        unawaited(AppHaptic.commit());
        widget.onPaired?.call(outcome);
      case ManualPairingFailed(:final code, :final detail):
        _showFailure(code, detail);
    }
  }

  void _showFailure(ManualPairingFailureCode code, [String? detail]) {
    switch (code) {
      case ManualPairingFailureCode.phraseExpired:
        final sentence = _sentenceFor(PhraseErrorCode.phraseExpired);
        setState(() {
          _submitting = false;
          _phraseLevelError = sentence;
          _linkFailed = false;
          _linkFailureDetail = null;
        });
        _announce(sentence);
      case ManualPairingFailureCode.phraseAttempts:
        for (final controller in _wordControllers) {
          controller.clear();
        }
        final sentence = _sentenceFor(PhraseErrorCode.phraseAttempts);
        setState(() {
          _submitting = false;
          _wordErrorIndex = null;
          _wordErrorMessage = null;
          _phraseLevelError = sentence;
          _linkFailed = false;
          _linkFailureDetail = null;
        });
        _announce(sentence);
      case ManualPairingFailureCode.hostInUse:
        setState(() {
          _submitting = false;
          _hostInUse = true;
          _linkFailed = false;
          _linkFailureDetail = null;
        });
      // R-31-03-13: the words stay, `Pair` stays enabled as the one
      // `Try again` of R-30-804, and the raw cause shows under the sentence
      // per R-30-803.
      case ManualPairingFailureCode.linkFailed:
        setState(() {
          _submitting = false;
          _linkFailed = true;
          _linkFailureDetail = detail;
          _phraseLevelError = _linkFailedSentence;
        });
        _announce(_linkFailedSentence);
    }
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final color = AppColor.of(context);
    // R-30-904, R-32-532: the suggestion strip shows only while a word field holds focus,
    // holds two or more typed characters, and at least one exact-prefix match exists. No
    // match means no strip, never an empty one.
    final focused = _focusedWordIndex;
    List<String> suggestions = const [];
    if (focused != null) {
      suggestions = autocompleteWords(
        _wordControllers[focused].text,
        widget.effWords,
      );
    }
    final title = Text(
      'Pair by hand',
      style: AppType.heading.copyWith(color: color.fgPrimary),
    );
    // R-31-03-15: the native header scrolls away before a field loses space.
    final header = _isIos
        ? SliverToBoxAdapter(
            child: CupertinoNavigationBar(
              backgroundColor: color.bgBase,
              border: Border(
                bottom: BorderSide(
                  color: color.borderStrong,
                  width: AppBorder.hairline,
                ),
              ),
              middle: title,
            ),
          )
        : SliverAppBar(
            primary: false,
            floating: true,
            snap: true,
            backgroundColor: color.bgBase,
            elevation: 0,
            title: title,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(AppBorder.hairline),
              child: Container(
                color: color.borderStrong,
                height: AppBorder.hairline,
              ),
            ),
          );
    final body = SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  header,
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpace.space4,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: _inset,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_hostInUse) ...[
                                  _HostInUseBanner(color: color),
                                  const SizedBox(height: AppSpace.space4),
                                ],
                                // Callout 2.
                                Text(
                                  'The Relay pane on your computer shows an address, a computer '
                                  'code and six words.',
                                  style: AppType.body.copyWith(
                                    color: color.fgSecondary,
                                  ),
                                ),
                                const SizedBox(height: AppSpace.space2),
                                // Callout 3, R-31-03-12: reads the clipboard and fills whatever it
                                // recognises -- a full pairing URI, a bare phrase, or a bare
                                // computer code.
                                AppTextButton(
                                  label: 'Paste from clipboard',
                                  onPressed: () => unawaited(_onPastePressed()),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpace.space6),
                          const AppSectionHeader.upperCase(
                            label: 'RELAY ADDRESS',
                          ),
                          Padding(
                            padding: _inset,
                            child: _buildOriginField(color),
                          ),
                          const SizedBox(height: AppSpace.space6),
                          const AppSectionHeader.upperCase(
                            label: 'COMPUTER CODE',
                          ),
                          Padding(
                            padding: _inset,
                            child: _buildHandleField(color),
                          ),
                          const SizedBox(height: AppSpace.space6),
                          const AppSectionHeader.upperCase(label: 'PHRASE'),
                          Padding(
                            padding: _inset,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildWordGrid(color),
                                if (widget.isConnected) ...[
                                  const SizedBox(height: AppSpace.space4),
                                  // Callout 9, R-30-945's exact sentence.
                                  Text(
                                    'Pairing disconnects the computer you are using now.',
                                    style: AppType.caption.copyWith(
                                      color: color.fgSecondary,
                                    ),
                                  ),
                                ],
                                if (_offline) ...[
                                  const SizedBox(height: AppSpace.space4),
                                  // R-13-022: a phrase lives 600 seconds. The same sentence, in the
                                  // same `treat.warning`, as `/welcome` and `/pair/scan`.
                                  const AppStrip(
                                    child: Treatment.warning(
                                      label:
                                          'No network. Pairing needs a connection, and a phrase '
                                          'lasts ten minutes.',
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // R-03-128: reserve the footer height outside the scroll view.
            // Its end padding lets the last field clear the actions.
            Padding(
              padding: constraints.maxHeight < 4 * AppSize.field
                  ? _inset
                  : _inset.add(
                      const EdgeInsets.symmetric(vertical: AppSpace.space2),
                    ),
              child: Flex(
                // R-31-03-15: keep a field visible above a landscape keyboard.
                direction: constraints.maxHeight < 4 * AppSize.field
                    ? Axis.horizontal
                    : Axis.vertical,
                crossAxisAlignment: constraints.maxHeight < 4 * AppSize.field
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    flex: constraints.maxHeight < 4 * AppSize.field ? 1 : 0,
                    child: AppFilledButton(
                      label: _hostInUse || _linkFailed ? 'Try again' : 'Pair',
                      isLoading: _submitting,
                      onPressed: _canSubmit ? _onPairPressed : null,
                    ),
                  ),
                  const SizedBox(
                    height: AppSpace.space2,
                    width: AppSpace.space2,
                  ),
                  Flexible(
                    flex: constraints.maxHeight < 4 * AppSize.field ? 1 : 0,
                    child: AppTextButton(
                      label: 'Scan the QR code instead',
                      onPressed: widget.onScanInstead ?? _noOp,
                    ),
                  ),
                ],
              ),
            ),
            // R-30-519, R-32-532: the strip is a control bound to the focused input, so it
            // rides on the keyboard inset -- the `Scaffold` shrinks the body by `viewInsets`
            // and this strip lands at the bottom of the shrunk body, directly above the
            // keyboard. Docked here it cannot sit under the keyboard the way the old under-row
            // list did.
            // R-30-519: suggestions yield before the focused field loses space.
            if (suggestions.isNotEmpty &&
                constraints.maxHeight >= 4 * AppSize.field + AppSize.rowOneLine)
              _SuggestionStrip(
                words: suggestions,
                color: color,
                onTap: (word) => _acceptSuggestion(focused!, word),
              ),
          ],
        ),
      ),
    );
    // R-03-127: forms use plain ground, including the pinned actions.
    final ground = SizedBox.expand(child: body);
    if (_isIos) {
      return CupertinoPageScaffold(
        backgroundColor: color.bgBase,
        child: ground,
      );
    }
    return Scaffold(backgroundColor: color.bgBase, body: ground);
  }

  /// The text field of `docs/32-design-language.md` section 7.10: `color.bg.high` fill,
  /// `border.hairline` in `color.border.strong`, `radius.sm`; `border.error` on the field that
  /// failed (R-32-504); `border.focus` in `color.accent.text` while it holds focus (R-32-503).
  /// Error wins over focus, so the failed field this screen focuses (R-31-03-08) shows why. The
  /// ring sits on the field's own edge: `CupertinoTextField` paints its decoration behind a
  /// fixed content inset, so a 2 px border moves no text.
  BoxDecoration _fieldDecoration(
    AppColor color, {
    required bool focused,
    required bool error,
  }) => BoxDecoration(
    color: color.bgHigh,
    border: Border.all(
      color: error
          ? color.statusError
          : focused
          ? color.accentText
          : color.borderStrong,
      width: error
          ? _borderErrorWidth
          : focused
          ? _borderFocusWidth
          : AppBorder.hairline,
    ),
    borderRadius: BorderRadius.circular(AppRadius.sm),
  );

  // Callout 5.
  Widget _buildOriginField(AppColor color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: AppSize.field,
          child: Semantics(
            textField: true,
            label: 'Relay address',
            child: CupertinoTextField(
              controller: _originController,
              focusNode: _originFocusNode,
              enabled: !_submitting,
              autofocus: widget.initialInput == null,
              textAlignVertical: TextAlignVertical.center,
              placeholder: 'https://',
              placeholderStyle: AppType.monoPhrase.copyWith(
                color: color.fgDisabled,
              ),
              style: AppType.monoPhrase.copyWith(color: color.fgPrimary),
              keyboardType: TextInputType.url,
              textCapitalization: TextCapitalization.none,
              autocorrect: false,
              enableSuggestions: false,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              textInputAction: TextInputAction.next,
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.space3),
              decoration: _fieldDecoration(
                color,
                focused: _originFocusNode.hasFocus,
                error: _originError != null,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _handleFocusNode.requestFocus(),
            ),
          ),
        ),
        if (_originError != null) ...[
          const SizedBox(height: AppSpace.space1),
          Treatment.error(label: _originError!),
        ],
      ],
    );
  }

  // Callout 6.
  Widget _buildHandleField(AppColor color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: AppSize.field,
          child: Semantics(
            textField: true,
            label: 'Computer code',
            child: CupertinoTextField(
              controller: _handleController,
              focusNode: _handleFocusNode,
              enabled: !_submitting,
              textAlignVertical: TextAlignVertical.center,
              style: AppType.monoPhrase.copyWith(color: color.fgPrimary),
              keyboardType: TextInputType.text,
              textCapitalization: TextCapitalization.none,
              autocorrect: false,
              enableSuggestions: false,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              textInputAction: TextInputAction.next,
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.space3),
              decoration: _fieldDecoration(
                color,
                focused: _handleFocusNode.hasFocus,
                error: _handleError != null,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _wordFocusNodes[0].requestFocus(),
            ),
          ),
        ),
        if (_handleError != null) ...[
          const SizedBox(height: AppSpace.space1),
          Treatment.error(label: _handleError!),
        ],
      ],
    );
  }

  // Callout 7: the six-word grid, two per row, numeric focus order (R-30-719). Section 7.11:
  // two fields per row with a `space.3` gap. The autocomplete suggestions no longer open
  // under the focused row; they are the bottom strip `build` docks above the keyboard
  // (R-30-904, R-32-532).
  Widget _buildWordGrid(AppColor color) {
    final rows = <Widget>[];
    for (var row = 0; row < _wordCount ~/ 2; row++) {
      final left = row * 2;
      final right = left + 1;
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildWordField(left, color)),
            const SizedBox(width: AppSpace.space3),
            Expanded(child: _buildWordField(right, color)),
          ],
        ),
      );
      if (row < _wordCount ~/ 2 - 1) {
        rows.add(const SizedBox(height: AppSpace.space3));
      }
    }
    if (_wordErrorMessage != null) {
      rows.add(const SizedBox(height: AppSpace.space2));
      rows.add(Treatment.error(label: _wordErrorMessage!));
    }
    if (_phraseLevelError != null) {
      rows.add(const SizedBox(height: AppSpace.space2));
      rows.add(Treatment.error(label: _phraseLevelError!));
    }
    // R-30-803: the link-failure state shows the raw cause under the sentence.
    if (_linkFailureDetail != null) {
      rows.add(const SizedBox(height: AppSpace.space2));
      rows.add(
        Text(
          _linkFailureDetail!,
          style: AppType.monoCode.copyWith(color: color.fgPrimary),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  Widget _buildWordField(int index, AppColor color) {
    final hasError = _wordErrorIndex == index;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Section 7.11: the number in `type.micro` outside the field, `space.1` before it. No
        // fixed width: `type.micro` is monospaced, so every digit is one advance wide and the
        // two columns stay equal.
        Text(
          '${index + 1}',
          style: AppType.micro.copyWith(color: color.fgSecondary),
        ),
        const SizedBox(width: AppSpace.space1),
        Expanded(
          child: SizedBox(
            height: AppSize.field,
            child: Semantics(
              textField: true,
              label: 'Pairing word ${index + 1} of six',
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: (node, event) => _handleWordKey(index, event),
                child: CupertinoTextField(
                  controller: _wordControllers[index],
                  focusNode: _wordFocusNodes[index],
                  enabled: !_submitting,
                  textAlignVertical: TextAlignVertical.center,
                  placeholder: '\u2014',
                  placeholderStyle: AppType.monoPhrase.copyWith(
                    color: color.fgDisabled,
                  ),
                  style: AppType.monoPhrase.copyWith(color: color.fgPrimary),
                  keyboardType: TextInputType.text,
                  textCapitalization: TextCapitalization.none,
                  autocorrect: false,
                  enableSuggestions: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  textInputAction: index == _wordCount - 1
                      ? TextInputAction.done
                      : TextInputAction.next,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.space3,
                  ),
                  // The strip is outside the viewport; reserve only field spacing.
                  scrollPadding: const EdgeInsets.all(AppSpace.space2),
                  decoration: _fieldDecoration(
                    color,
                    focused: _wordFocusNodes[index].hasFocus,
                    error: hasError,
                  ),
                  onChanged: (value) => _onWordChanged(index, value),
                  onSubmitted: (_) => _advanceFocusAfter(index),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// R-30-904, R-32-532: the autocomplete strip, at most six chips, docked to the bottom of
/// the screen body directly above the keyboard inset (R-30-519: a control bound to the
/// focused input). Section 7.11: chips of `size.row.one_line` with `space.2` vertical padding,
/// on `color.bg.raised` under a 1 px `color.border.subtle` top rule.
class _SuggestionStrip extends StatelessWidget {
  const _SuggestionStrip({
    required this.words,
    required this.color,
    required this.onTap,
  });

  final List<String> words;
  final AppColor color;
  final void Function(String word) onTap;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.bgRaised,
      border: Border(
        top: BorderSide(color: color.borderSubtle, width: AppBorder.hairline),
      ),
    ),
    child: SizedBox(
      height: AppSize.rowOneLine + 2 * AppSpace.space2,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.space2),
        child: Row(
          children: <Widget>[
            for (var i = 0; i < words.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: AppSpace.space2),
              _SuggestionChip(word: words[i], onTap: () => onTap(words[i])),
            ],
          ],
        ),
      ),
    ),
  );
}

/// One autocomplete chip, callout 8 of `docs/31-mockups/03-pair-code.md`: `color.bg.high`, a
/// 1 px `color.border.strong` border, `radius.sm`, `type.mono.phrase`; `size.row.one_line`
/// high, so the chip is its own touch target (R-32-360). It composes `AppPressable`, the one
/// press wrapper of section 7.1: pointer-down feedback, the press scale, the focus ring and
/// keyboard activation come from there; this chip supplies only R-32-501's first case, a
/// `color.bg.high` control pressing to `color.accent.primary` with its label in
/// `color.fg.on_accent`.
class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.word, required this.onTap});

  final String word;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    return Semantics(
      button: true,
      label: word,
      excludeSemantics: true,
      child: AppPressable(
        onTap: onTap,
        builder: (BuildContext context, bool pressed) => AnimatedContainer(
          duration: AppPressable.fillDuration(context, pressed),
          curve: AppPressable.fillCurve(context),
          height: AppSize.rowOneLine,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.space3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: pressed ? color.accentPrimary : color.bgHigh,
            border: Border.all(
              color: pressed ? color.accentPrimary : color.borderStrong,
              width: AppBorder.hairline,
            ),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Text(
            word,
            style: AppType.monoPhrase.copyWith(
              color: pressed ? color.fgOnAccent : color.fgPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// R-30-940's banner, in the name-free form R-31-02-08 fixes for both pairing screens.
class _HostInUseBanner extends StatelessWidget {
  const _HostInUseBanner({required this.color});

  final AppColor color;

  @override
  Widget build(BuildContext context) => AppStrip(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Symbols.warning_rounded,
          size: AppSize.iconSm,
          color: color.statusWarning,
          fill: 0,
          weight: 400,
          grade: 0,
        ),
        const SizedBox(width: AppSpace.space2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _hostInUseHeadline,
                style: AppType.bodyStrong.copyWith(color: color.fgPrimary),
              ),
              const SizedBox(height: AppSpace.space1),
              Text(
                _hostInUseDetail,
                style: AppType.caption.copyWith(color: color.fgSecondary),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
