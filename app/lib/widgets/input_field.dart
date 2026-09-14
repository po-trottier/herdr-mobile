/// The hardened, keyboard-lifted text field (`docs/90-implementation-plan.md` `WP-17`,
/// R-31-09-06, R-30-519, R-22-077) behind the pane rename field of
/// `pane_actions_sheet.dart` (mockup 10) and the relay URL and phone name fields of
/// `settings_screen.dart` (mockup 15). It began as the terminal key row's field; R-03-054
/// removed that field on 2026-09-09 — the terminal is a live terminal, and typing goes to
/// the pane as it is typed — and this widget stayed for the fields that still hold text.
///
/// Two things this file owns:
///
/// - **Keyboard hardening (R-31-09-06).** Autocorrect, autocapitalisation, predictive
///   suggestions, smart quotes and smart dashes are all off. A shell command, a URL or a
///   pane name is not prose, and a curly quote or an en dash inside one is a silent
///   corruption. This mirrors `manual_pairing_screen.dart`'s `CupertinoTextField` fields
///   (`WP-15-c`), the established convention for a hardened field in this codebase.
/// - **The keyboard-inset lift (R-30-519, R-22-077).** With [liftsAboveKeyboard] on, the
///   field rises above `MediaQuery.viewInsetsOf(context).bottom`, the part of the display
///   the keyboard obscures. This file MUST NOT and does not read
///   `MediaQuery.viewPaddingOf`, which ignores the keyboard entirely (R-22-077's own
///   distinction). This widget never wraps itself in `Expanded`/`Flexible`: it sizes to its
///   own content, so a caller's scrollable list above it is what compresses first and this
///   field never shrinks to fit one, per R-30-519's last bullet.
///
/// Single line by default, grows to four lines at most. This file owns no widget beyond the
/// field itself (R-90-024): what a caller does with the text is the caller's.
library;

import 'package:cupertino_ui/cupertino_ui.dart'
    show
        Border,
        BorderRadius,
        BoxDecoration,
        BuildContext,
        CupertinoTextField,
        EdgeInsets,
        FocusNode,
        Padding,
        StatelessWidget,
        TextEditingController,
        ValueChanged,
        Widget;

import 'package:flutter/services.dart'
    show
        SmartDashesType,
        SmartQuotesType,
        TextCapitalization,
        TextInputAction,
        TextInputType;

import 'package:flutter/widgets.dart'
    show BoxConstraints, ConstrainedBox, MediaQuery, TextAlignVertical;

import 'theme/app_color.dart';
import 'theme/app_radius.dart';
import 'theme/app_size.dart';
import 'theme/app_space.dart';
import 'theme/app_type.dart';

/// The maximum number of lines the field grows to before it scrolls internally: a long
/// pane name or URL wraps instead of scrolling sideways out of view.
const int inputFieldMaxLines = 4;

/// `border.error` width, per `docs/32-design-language.md` R-32-330. A local constant beside
/// its one caller, like `app_filled_button.dart`'s `_borderFocusWidth`.
const double _borderErrorWidth = 2;

/// The hardened, keyboard-lifted text field. See this file's top doc comment.
class InputField extends StatelessWidget {
  const InputField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.placeholder,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
    this.errorText,
    this.padding = const EdgeInsets.all(AppSpace.space2),
    this.minHeight = AppSize.field,
    this.liftsAboveKeyboard = true,
  });

  /// Holds exactly what the person is typing now. The caller owns clearing it.
  final TextEditingController controller;

  final FocusNode focusNode;

  /// The placeholder, drawn in `color.fg.disabled` (R-32-530 anatomy). The caller builds
  /// the exact sentence; this file draws whatever it is given.
  final String placeholder;

  /// `false` while the caller's `Host in use` or `Offline` states are showing (R-30-807):
  /// the field itself stays visible and holds its text either way; only editing is gated.
  final bool enabled;

  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Optional error text. When present, the field shows a 2 px `statusError` border.
  final String? errorText;

  /// The space around the field, inside the keyboard-inset lift: the `space.2` default, or
  /// `EdgeInsets.zero` where the caller's own layout owns the inset.
  final EdgeInsets padding;

  /// The bordered field's minimum height: `size.field` for one line (a sheet),
  /// `size.field.compose.min` for the composer's text area (R-32-530). The minimum belongs
  /// to the bordered box itself; a constraint around the whole widget would only stretch
  /// the row that holds it and leave the box at its text height.
  final double minHeight;

  /// Whether this widget adds the keyboard inset under itself (R-30-519). `true` where the
  /// field is the last thing on the screen. A sheet that holds actions
  /// under the field passes `false` and applies the inset to the whole sheet instead, so the
  /// actions rise with the field (R-31-10-09; measured 2026-09-03: the field's own lift had
  /// pushed `Cancel` and `Rename` under the keyboard).
  final bool liftsAboveKeyboard;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final bool hasError = errorText != null && errorText!.isNotEmpty;

    return Padding(
      // R-30-519, R-22-077: `viewInsetsOf`, never `viewPaddingOf`, which ignores the
      // keyboard. Reading the per-aspect getter rebuilds only when this one value changes.
      padding: EdgeInsets.only(
        bottom: liftsAboveKeyboard
            ? MediaQuery.viewInsetsOf(context).bottom
            : 0,
      ),
      child: Padding(
        padding: padding,
        // R-32-530's height: [minHeight] on the bordered box itself. One line sits
        // centred in it; the field grows only when the text needs more.
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: CupertinoTextField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            minLines: 1,
            maxLines: inputFieldMaxLines,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            textAlignVertical: TextAlignVertical.center,
            // R-31-09-06: every one of the five substitutions off.
            textCapitalization: TextCapitalization.none,
            autocorrect: false,
            enableSuggestions: false,
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            placeholder: placeholder,
            placeholderStyle: AppType.body.copyWith(color: color.fgDisabled),
            style: AppType.body.copyWith(color: color.fgPrimary),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.space3,
              vertical: AppSpace.space2,
            ),
            decoration: BoxDecoration(
              color: color.bgHigh,
              // `border.hairline` in `color.border.strong` (R-32-530), or
              // `border.error` while [errorText] shows (R-32-504).
              border: Border.all(
                color: hasError ? color.statusError : color.borderStrong,
                width: hasError ? _borderErrorWidth : AppBorder.hairline,
              ),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            onChanged: onChanged,
            onSubmitted: onSubmitted,
          ),
        ),
      ),
    );
  }
}
