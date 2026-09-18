/// Native terminal input below the grid (R-03-130, R-31-09-26..30).
library;

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoButton, CupertinoTextField;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart'
    show IconButton, InputDecoration, OutlineInputBorder, TextField, Theme;

import '../app.dart' show appFilledIconButtonStyle, appTonalIconButtonStyle;
import 'theme/app_color.dart';
import 'theme/app_radius.dart';
import 'theme/app_size.dart';
import 'theme/app_space.dart';
import 'theme/app_type.dart';

class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.onText,
    required this.onDelete,
    required this.onSubmit,
    required this.focusNode,
    this.inputFormatters,
    this.enabled = true,
    this.panelOpen = false,
    this.onTogglePanel,
  });

  final ValueChanged<String> onText;
  final ValueChanged<int> onDelete;
  final VoidCallback onSubmit;
  final FocusNode focusNode;
  final List<TextInputFormatter>? inputFormatters;
  final bool enabled;
  final bool panelOpen;
  final VoidCallback? onTogglePanel;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final TextEditingController _controller = TextEditingController();
  String _sent = '';

  void _changed(String text) {
    if (!widget.enabled) return;
    // R-03-130: Send only the edit. The native field owns its selection.
    final List<String> before = _sent.characters.toList();
    final List<String> after = text.characters.toList();
    int prefix = 0;
    while (prefix < before.length &&
        prefix < after.length &&
        before[prefix] == after[prefix]) {
      prefix++;
    }
    // R-03-130: The Host cursor stays at the end. Replace its tail after a middle edit.
    final int deleted = before.length - prefix;
    final String inserted = after.skip(prefix).join();
    _sent = text;
    if (deleted > 0) widget.onDelete(deleted);
    if (inserted.isNotEmpty) widget.onText(inserted);
  }

  void _submit() {
    if (!widget.enabled) return;
    widget.onSubmit();
    _sent = '';
    _controller.clear();
    widget.focusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final TextStyle style = AppType.monoCompose.copyWith(
      color: color.fgPrimary,
    );
    final bool ios = defaultTargetPlatform == TargetPlatform.iOS;
    final double height = ios ? AppSize.inputIos : AppSize.field;
    // R-32-537: growing the field must not grow its corner arcs into a pill.
    final BorderRadius fieldRadius = BorderRadius.circular(height / 2);
    final Widget send = ios
        ? Semantics(
            label: 'Send',
            child: CupertinoButton(
              key: const ValueKey<String>('composerSend'),
              color: color.accentPrimary,
              borderRadius: BorderRadius.circular(AppRadius.full),
              minimumSize: const Size.square(30),
              padding: EdgeInsets.zero,
              onPressed: widget.enabled ? _submit : null,
              child: Icon(
                Symbols.arrow_upward_rounded,
                size: AppSize.iconMd,
                color: color.fgOnAccent,
              ),
            ),
          )
        : IconButton.filled(
            tooltip: 'Send',
            style: appFilledIconButtonStyle(context),
            onPressed: widget.enabled ? _submit : null,
            icon: const Icon(Symbols.send_rounded, size: AppSize.iconMd),
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
            crossAxisAlignment: CrossAxisAlignment.center,
            suffix: Padding(
              padding: const EdgeInsets.all(3 - AppBorder.hairline),
              child: send,
            ),
            enabled: widget.enabled,
            inputFormatters: widget.inputFormatters,
            focusNode: widget.focusNode,
            style: style,
            placeholder: 'Type here',
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
            textInputAction: TextInputAction.send,
            onChanged: _changed,
            onSubmitted: (_) => _submit(),
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
            textInputAction: TextInputAction.send,
            onChanged: _changed,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              filled: true,
              fillColor: color.bgHigh,
              isDense: true,
              contentPadding: padding,
              hintText: 'Type here',
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        SizedBox.square(
          key: const ValueKey<String>('composerMore'),
          dimension: height,
          child: ios
              ? Semantics(
                  label: widget.panelOpen ? 'Fewer keys' : 'More keys',
                  child: CupertinoButton(
                    color: color.bgHigh,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    minimumSize: const Size.square(AppSize.inputIos),
                    padding: EdgeInsets.zero,
                    onPressed: widget.onTogglePanel,
                    child: Icon(
                      widget.panelOpen
                          ? Symbols.close_rounded
                          : Symbols.add_rounded,
                      color: color.accentText,
                      size: AppSize.iconMd,
                    ),
                  ),
                )
              : IconButton.filledTonal(
                  tooltip: widget.panelOpen ? 'Fewer keys' : 'More keys',
                  style: appTonalIconButtonStyle(context),
                  onPressed: widget.onTogglePanel,
                  icon: Icon(
                    widget.panelOpen
                        ? Symbols.close_rounded
                        : Symbols.add_rounded,
                  ),
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
    );
  }
}
