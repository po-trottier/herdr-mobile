/// Native terminal input below the grid (R-03-130, R-31-09-26..30).
library;

import 'dart:async' show unawaited;

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoActivityIndicator, CupertinoButton, CupertinoTextField;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart'
    show
        CircularProgressIndicator,
        IconButton,
        InputDecoration,
        OutlineInputBorder,
        TextField,
        Theme;

import '../app.dart' show appFilledIconButtonStyle, appTonalIconButtonStyle;
import '../models/messages/send_input.dart';
import 'theme/app_color.dart';
import 'theme/app_radius.dart';
import 'theme/app_size.dart';
import 'theme/app_space.dart';
import 'theme/app_type.dart';
import 'theme/chrome_menu.dart';

class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.onLine,
    required this.onSubmit,
    required this.focusNode,
    this.inputFormatters,
    this.enabled = true,
    this.panelOpen = false,
    this.onTogglePanel,
    this.answerInput = false,
    this.onSubmitAnswer,
    this.initialLine = '',
    this.queued = false,
    this.onCancelQueued,
    this.onSendQueuedNow,
  });

  final ValueChanged<String> onLine;

  /// Called with the text the person submits. The field is already empty when
  /// this runs (R-31-09-34): typing continues while the Enter is in flight.
  final Future<bool> Function(String line, {bool whenIdle}) onSubmit;
  final bool queued;
  final VoidCallback? onCancelQueued;
  final VoidCallback? onSendQueuedNow;
  final String initialLine;
  final FocusNode focusNode;
  final List<TextInputFormatter>? inputFormatters;
  final bool enabled;
  final bool panelOpen;

  /// The `+` control toggles the key panel directly (2026-09-23): a tap
  /// opens it on its last page, a tap with it open closes it. No menu.
  final VoidCallback? onTogglePanel;

  /// The Answer page of the key panel makes this field the answer input
  /// (R-31-09-41, 2026-09-23): the main draft is stashed untouched, the
  /// field starts empty with the `Type an answer` placeholder, no `line`
  /// sync runs, and Send goes to [onSubmitAnswer] instead of [onSubmit].
  final bool answerInput;

  /// Sends the answer text as one bypass frame. Resolves with the Host's
  /// ack; the field clears only then, so a refusal keeps the text.
  final Future<bool> Function(String text)? onSubmitAnswer;

  @override
  ComposerState createState() => ComposerState();
}

class ComposerState extends State<Composer> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialLine,
  );
  bool _edited = false;
  bool _submitting = false;

  /// The stashed main draft, text and selection, while [Composer.answerInput]
  /// lends the field to an answer. Restored exactly when the page leaves.
  TextEditingValue? _draftStash;

  /// The main draft — while [Composer.answerInput] holds the answer in the
  /// field, the stashed line the Host still mirrors.
  String get currentLine => _draftStash?.text ?? _controller.text;

  @override
  void didUpdateWidget(Composer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.answerInput == oldWidget.answerInput) return;
    // Neither switch sends a frame: the swap is local only (2026-09-23).
    if (widget.answerInput) {
      _draftStash = _controller.value;
      _controller.clear();
    } else {
      final TextEditingValue? draft = _draftStash;
      _draftStash = null;
      if (draft != null) _controller.value = draft;
    }
  }

  /// Seed the Host line only before the first local edit.
  void seedLine(String line) {
    if (widget.answerInput || _edited || _submitting || currentLine.isNotEmpty) {
      return;
    }
    _controller.value = TextEditingValue(
      text: line,
      selection: TextSelection.collapsed(offset: line.length),
    );
  }

  /// Mirror accepted key controls without another Host update.
  void applyAcceptedInput(SendInput input) {
    // The Answer page's keys never mirror, and a late Keys-page ack must not
    // land in the answer buffer.
    if (widget.answerInput) return;
    String line = currentLine;
    if (input.text case final String text) {
      if (!const <String>{
        '\x1b[2~',
        '\x1b[3~',
        '\x1b[H',
        '\x1b[F',
        '\x1b[5~',
        '\x1b[6~',
      }.contains(text)) {
        line += text;
      }
    }
    for (final String key in input.keys ?? const <String>[]) {
      switch (key.toLowerCase()) {
        case 'enter':
        case 'ctrl+c':
          line = '';
        case 'backspace':
          line = line.characters.skipLast(1).toString();
      }
    }
    if (line == currentLine) return;
    _edited = true;
    _controller.value = TextEditingValue(
      text: line,
      selection: TextSelection.collapsed(offset: line.length),
    );
  }

  void _changed(String text) {
    // Answer mode runs no `line` sync: the field holds the answer, and the
    // main draft stays stashed and untouched.
    if (widget.answerInput) return;
    _edited = true;
    if (!widget.enabled || widget.queued) return;
    widget.onLine(_controller.text);
  }

  Future<void> _submit({bool whenIdle = false}) async {
    if (!widget.enabled || _submitting) return;
    if (widget.answerInput) {
      // The answer send: one bypass frame through `onSubmitAnswer`. The
      // field clears on the ack, so a refusal keeps the text. The queued
      // and `whenIdle` paths do not exist in answer mode.
      final Future<bool> Function(String text)? submitAnswer =
          widget.onSubmitAnswer;
      if (submitAnswer == null) return;
      final String text = _controller.text;
      setState(() => _submitting = true);
      try {
        final bool accepted = await submitAnswer(text);
        if (!mounted) return;
        if (accepted) {
          _controller.clear();
          widget.focusNode.requestFocus();
        }
      } finally {
        if (mounted) setState(() => _submitting = false);
      }
      return;
    }
    if (widget.queued) return;
    final String line = _controller.text;
    // Clear before the round trip: the wire is ordered, so a line frame typed
    // now reaches the Host after the Enter and starts a fresh console line.
    // A held submit (whenIdle) keeps the text: the console line is not
    // submitted yet, and the field goes read-only through `queued`.
    if (!whenIdle) _controller.clear();
    setState(() => _submitting = true);
    try {
      final bool accepted = await widget.onSubmit(line, whenIdle: whenIdle);
      // A switch to the Answer page mid-flight leaves the draft in the
      // stash; nothing lands in the answer buffer.
      if (!mounted || widget.answerInput) return;
      if (accepted) {
        if (whenIdle) _controller.clear();
        widget.focusNode.requestFocus();
      } else if (!whenIdle && _controller.text.isEmpty) {
        // The console still holds the line (the Host shadow kept it). Put it
        // back so the field and the console agree again.
        _controller.value = TextEditingValue(
          text: line,
          selection: TextSelection.collapsed(offset: line.length),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// The long-press choices of the send control, on the platform menu of
  /// R-33-033's `Menu from a control` row, anchored to the control itself.
  /// Empty while the control has nothing to offer, so the menu never opens.
  List<ChromeMenuItem> _sendOptions() {
    // Answer mode has the one send and nothing to defer (2026-09-23).
    if (widget.answerInput) return const <ChromeMenuItem>[];
    final bool canSubmit = widget.enabled && !_submitting && !widget.queued;
    return <ChromeMenuItem>[
      if (canSubmit)
        ChromeMenuItem(
          label: 'Send now',
          icon: Symbols.send_rounded,
          onSelected: () => unawaited(_submit()),
        ),
      if (widget.queued && widget.onSendQueuedNow != null)
        ChromeMenuItem(
          label: 'Send now',
          icon: Symbols.send_rounded,
          onSelected: widget.onSendQueuedNow,
        ),
      if (canSubmit)
        ChromeMenuItem(
          label: 'Send when the agent is done',
          icon: Symbols.schedule_rounded,
          onSelected: () => unawaited(_submit(whenIdle: true)),
        ),
      if (widget.queued && widget.onCancelQueued != null)
        ChromeMenuItem(
          label: 'Cancel queued send',
          icon: Symbols.close_rounded,
          onSelected: widget.onCancelQueued,
          destructive: true,
        ),
    ];
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _queuedIcon(bool ios, AppColor color) => SizedBox.square(
    dimension: AppSize.iconMd,
    child: Stack(
      alignment: Alignment.center,
      children: <Widget>[
        CircularProgressIndicator(
          strokeWidth: 2,
          color: ios ? color.fgOnAccent : null,
        ),
        Icon(
          Symbols.schedule_rounded,
          size: AppSize.iconMd - 6,
          color: ios ? color.fgOnAccent : null,
        ),
      ],
    ),
  );

  /// The `+` control of R-31-09-17, one platform button under one spoken
  /// label: `add` with the panel closed, `close` with it open (2026-09-23).
  Widget _moreButton({
    required bool ios,
    required AppColor color,
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    if (ios) {
      return Semantics(
        label: label,
        child: CupertinoButton(
          color: color.bgHigh,
          borderRadius: BorderRadius.circular(AppRadius.full),
          minimumSize: const Size.square(AppSize.inputIos),
          padding: EdgeInsets.zero,
          onPressed: onPressed,
          child: Icon(icon, color: color.accentText, size: AppSize.iconMd),
        ),
      );
    }
    return IconButton.filledTonal(
      tooltip: label,
      style: appTonalIconButtonStyle(context),
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final TextStyle style = AppType.monoCompose.copyWith(
      color: color.fgPrimary,
    );
    final bool ios = defaultTargetPlatform == TargetPlatform.iOS;
    // The queued state belongs to the main draft; answer mode ignores it.
    final bool queued = widget.queued && !widget.answerInput;
    final double height = ios ? AppSize.inputIos : AppSize.field;
    // R-32-537: growing the field must not grow its corner arcs into a pill.
    final BorderRadius fieldRadius = BorderRadius.circular(height / 2);
    final List<ChromeMenuItem> options = _sendOptions();
    final Widget send = ChromeMenuAnchor(
      items: options,
      builder: (BuildContext context, MenuController menu) {
        final VoidCallback? open = options.isEmpty ? null : menu.open;
        final String sendLabel = widget.answerInput ? 'Send answer' : 'Send';
        final Widget sendButton = ios
            ? Semantics(
                label: sendLabel,
                child: CupertinoButton(
                  key: const ValueKey<String>('composerSend'),
                  color: color.accentPrimary,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  minimumSize: const Size.square(30),
                  padding: EdgeInsets.zero,
                  onPressed: queued
                      ? open
                      : widget.enabled && !_submitting
                      ? _submit
                      : null,
                  child: queued
                      ? _queuedIcon(ios, color)
                      : _submitting
                      ? SizedBox.square(
                          dimension: AppSize.iconMd,
                          child: CupertinoActivityIndicator(
                            radius: AppSize.iconMd / 2,
                            color: color.fgOnAccent,
                          ),
                        )
                      : Icon(
                          Symbols.arrow_upward_rounded,
                          size: AppSize.iconMd,
                          color: color.fgOnAccent,
                        ),
                ),
              )
            : IconButton.filled(
                style: appFilledIconButtonStyle(context),
                onPressed: queued
                    ? open
                    : widget.enabled && !_submitting
                    ? _submit
                    : null,
                icon: queued
                    ? _queuedIcon(ios, color)
                    : _submitting
                    ? const SizedBox.square(
                        dimension: AppSize.iconMd,
                        child: CircularProgressIndicator(),
                      )
                    : const Icon(Symbols.send_rounded, size: AppSize.iconMd),
              );
        return Semantics(
          label: ios ? null : sendLabel,
          child: GestureDetector(onLongPress: open, child: sendButton),
        );
      },
    );
    final OutlineInputBorder border = OutlineInputBorder(
      borderRadius: fieldRadius,
      borderSide: BorderSide(
        color: color.borderStrong,
        width: AppBorder.hairline,
      ),
    );
    final EdgeInsets padding = EdgeInsets.fromLTRB(
      AppSpace.space3,
      ios ? 7 - AppBorder.hairline : 13,
      ios ? AppSpace.space1 : AppSpace.space3,
      ios ? 7 - AppBorder.hairline : 13,
    );
    final Widget field = ios
        ? CupertinoTextField(
            key: const ValueKey<String>('composerField'),
            controller: _controller,
            crossAxisAlignment: CrossAxisAlignment.end,
            suffix: Padding(
              // The 18 pt field corner and 15 pt Send radius share a centre
              // with equal 3 pt edge insets (including the field's border).
              padding: const EdgeInsets.all(3 - AppBorder.hairline),
              child: send,
            ),
            enabled: widget.enabled,
            readOnly: queued,
            inputFormatters: widget.inputFormatters,
            focusNode: widget.focusNode,
            style: style,
            placeholder: widget.answerInput ? 'Type an answer' : 'Type here',
            placeholderStyle: style.copyWith(color: color.fgDisabled),
            padding: padding,
            minLines: 1,
            maxLines: 5,
            keyboardType: TextInputType.multiline,
            // R-03-130, R-31-09-30 (amended 2026-09-16): the platform keyboard edits the
            // composer natively, autocorrect and predictions included. Only smart
            // punctuation stays off: a curly quote or an en dash into a shell breaks the
            // command, and no terminal wants one.
            autocorrect: true,
            enableSuggestions: true,
            enableIMEPersonalizedLearning: true,
            textCapitalization: TextCapitalization.sentences,
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            textInputAction: TextInputAction.newline,
            onChanged: _changed,
            decoration: BoxDecoration(
              color: color.bgHigh,
              borderRadius: fieldRadius,
              border: Border.all(
                color: color.borderStrong,
                width: AppBorder.hairline,
              ),
            ),
          )
        : TextField(
            key: const ValueKey<String>('composerField'),
            controller: _controller,
            enabled: widget.enabled,
            readOnly: queued,
            inputFormatters: widget.inputFormatters,
            focusNode: widget.focusNode,
            style: style,
            minLines: 1,
            maxLines: 5,
            keyboardType: TextInputType.multiline,
            autocorrect: true,
            enableSuggestions: true,
            enableIMEPersonalizedLearning: true,
            textCapitalization: TextCapitalization.sentences,
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            textInputAction: TextInputAction.newline,
            onChanged: _changed,
            decoration: InputDecoration(
              filled: true,
              fillColor: color.bgHigh,
              isDense: true,
              contentPadding: padding,
              hintText: widget.answerInput ? 'Type an answer' : 'Type here',
              hintStyle: style.copyWith(color: color.fgDisabled),
              border: border,
              enabledBorder: border,
              focusedBorder: border.copyWith(
                borderSide:
                    Theme.of(context)
                        .inputDecorationTheme
                        .focusedBorder
                        ?.borderSide ??
                    BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: AppBorder.accent,
                    ),
              ),
            ),
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            SizedBox.square(
              key: const ValueKey<String>('composerMore'),
              dimension: height,
              // R-31-09-17 (amended 2026-09-23): `+` toggles the panel
              // directly, with no menu — it opens on the panel's last page,
              // and with the panel open `+` carries `close` and closes it.
              child: _moreButton(
                ios: ios,
                color: color,
                icon: widget.panelOpen
                    ? Symbols.close_rounded
                    : Symbols.add_rounded,
                label: widget.panelOpen ? 'Fewer keys' : 'More keys',
                onPressed: widget.onTogglePanel,
              ),
            ),
            const SizedBox(width: AppSpace.space2),
            Expanded(child: field),
            if (!ios) ...<Widget>[
              const SizedBox(width: AppSpace.space2),
              SizedBox.square(
                key: const ValueKey<String>('composerSend'),
                dimension: height,
                child: send,
              ),
            ],
          ],
        ),
        if (queued)
          const Text(
            'Queued. Sends when the agent is done.',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}
