/// A compose task, pushed as a platform surface, per
/// `docs/33-platform-chrome.md` R-33-075.
///
/// **R-33-069, the deferred Liquid Glass adoption.** `cupertino_ui` ships
/// no glass surface today, so [showChromeComposeTask]'s iOS sheet and
/// every other iOS surface under `lib/widgets/theme/` draw the plain
/// appearance of R-33-012. When `cupertino_ui` ships official support,
/// this directory adopts it on exactly the R-33-012 surface list and
/// nowhere else. This document states no date, per R-33-069 and Flutter
/// issue 170310.
library;

import 'package:cupertino_ui/cupertino_ui.dart'
    show
        BuildContext,
        Builder,
        Column,
        CrossAxisAlignment,
        CupertinoButton,
        CupertinoSheetRoute,
        EdgeInsets,
        Expanded,
        Navigator,
        Opacity,
        Padding,
        Row,
        ScrollController,
        ScrollableWidgetBuilder,
        SizedBox,
        StatelessWidget,
        Text,
        TextAlign,
        TextOverflow,
        ValueListenableBuilder,
        VoidCallback,
        Widget,
        showCupertinoSheet;
import 'package:flutter/foundation.dart'
    show TargetPlatform, ValueListenable, defaultTargetPlatform;
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart'
    show
        AppBar,
        CircularProgressIndicator,
        Icon,
        IconButton,
        MaterialPageRoute,
        Scaffold,
        TextButton;

import 'app_color.dart';
import 'app_size.dart';
import 'app_space.dart';
import 'app_type.dart';

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

/// `opacity.disabled`, per the opacity table beside R-32-330: the confirm
/// control while [ChromeComposeConfirm.enabled] is false, per R-32-502,
/// with no colour change, per R-32-331.
const double _opacityDisabled = 0.38;

/// The spinner stroke, the one width the in-place spinner takes.
const double _spinnerStroke = 2;

/// The confirm control's state, read live through the `confirm` listenable
/// of [showChromeComposeTask] (added 2026-09-08, for the `Loading` and
/// empty states of `docs/31-mockups/11-prompt-composer.md`). [enabled]
/// false dims the control to `opacity.disabled` and makes its tap a no-op;
/// [busy] swaps its label for a `size.spinner` spinner in the label's ink
/// and makes its tap a no-op while the action is in flight.
class ChromeComposeConfirm {
  const ChromeComposeConfirm({this.enabled = true, this.busy = false});

  final bool enabled;
  final bool busy;
}

/// Pushes a compose task as a platform surface, per R-33-075. iOS pushes
/// a full-height [CupertinoSheetRoute] with two titled buttons and no `x`
/// glyph; Android pushes a full-screen Material route with the close
/// control and the predictive-back path of R-33-070, which this file
/// leaves to the route's own default transition rather than disabling it.
///
/// [title], when given, names the task in the header in `type.heading`, the
/// app bar title of `docs/32-design-language.md` section 7.3. [confirm],
/// when given, drives the confirm control's enabled and busy state live;
/// `null` keeps it enabled and idle.
///
/// [content] receives the same [ScrollController] this function passes to
/// the sheet's own scrollable on iOS, per R-33-075.2. A caller MUST
/// attach it to its inner scrollable, or the downward drag to dismiss
/// stops working.
Future<T?> showChromeComposeTask<T>({
  required BuildContext context,
  String? title,
  required String cancelLabel,
  required String confirmLabel,
  required VoidCallback onConfirm,
  ValueListenable<ChromeComposeConfirm>? confirm,
  required ScrollableWidgetBuilder content,
}) {
  if (_isIos) {
    return showCupertinoSheet<T>(
      context: context,
      scrollableBuilder:
          (BuildContext sheetContext, ScrollController controller) =>
              _ChromeComposeChrome(
                title: title,
                cancelLabel: cancelLabel,
                confirmLabel: confirmLabel,
                onConfirm: onConfirm,
                confirm: confirm,
                child: content(sheetContext, controller),
              ),
    );
  }
  return Navigator.of(context).push<T>(
    MaterialPageRoute<T>(
      fullscreenDialog: true,
      builder: (BuildContext routeContext) => _ChromeComposeChrome(
        title: title,
        cancelLabel: cancelLabel,
        confirmLabel: confirmLabel,
        onConfirm: onConfirm,
        confirm: confirm,
        child: Builder(
          builder: (BuildContext c) => content(c, ScrollController()),
        ),
      ),
    ),
  );
}

/// The compose task's own header: two titled buttons on iOS (no `x`
/// glyph, per R-33-075.1), and the Material close control plus the
/// confirming action on Android, per R-33-075.3.
class _ChromeComposeChrome extends StatelessWidget {
  const _ChromeComposeChrome({
    required this.title,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.onConfirm,
    required this.confirm,
    required this.child,
  });

  final String? title;
  final String cancelLabel;
  final String confirmLabel;
  final VoidCallback onConfirm;
  final ValueListenable<ChromeComposeConfirm>? confirm;
  final Widget child;

  /// The confirm control, rebuilt from [confirm] as it changes. The
  /// platform button is kept, per R-33-076's "a focusable platform
  /// control"; this widget only decides its callback and its child.
  Widget _confirmControl(
    Widget Function(VoidCallback? onPressed, Widget child) button,
  ) {
    Widget build(ChromeComposeConfirm state) {
      final bool active = state.enabled && !state.busy;
      final Widget label = state.busy
          ? const _ActionSpinner()
          : _ActionLabel(confirmLabel);
      return Opacity(
        opacity: state.enabled ? 1 : _opacityDisabled,
        child: button(active ? onConfirm : null, label),
      );
    }

    final ValueListenable<ChromeComposeConfirm>? listenable = confirm;
    if (listenable == null) {
      return build(const ChromeComposeConfirm());
    }
    return ValueListenableBuilder<ChromeComposeConfirm>(
      valueListenable: listenable,
      builder: (BuildContext _, ChromeComposeConfirm state, Widget? _) =>
          build(state),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final Widget? titleText = title == null
        ? null
        : Text(
            title!,
            style: AppType.heading.copyWith(color: color.fgPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          );
    if (_isIos) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.space2,
              vertical: AppSpace.space1,
            ),
            child: Row(
              children: <Widget>[
                // R-33-075: two titled platform buttons, no `x`. R-32-212 and
                // R-32-526: the label is `type.mono.button` UPPER in
                // `color.accent.text`, never the control's own default text.
                CupertinoButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: _ActionLabel(cancelLabel),
                ),
                Expanded(child: titleText ?? const SizedBox.shrink()),
                _confirmControl(
                  (VoidCallback? onPressed, Widget child) =>
                      CupertinoButton(onPressed: onPressed, child: child),
                ),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Symbols.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: cancelLabel,
        ),
        title: titleText,
        actions: <Widget>[
          _confirmControl(
            (VoidCallback? onPressed, Widget child) =>
                TextButton(onPressed: onPressed, child: child),
          ),
        ],
      ),
      body: child,
    );
  }
}

/// R-32-212, R-32-526: a text-only action label, `type.mono.button` UPPER
/// in `color.accent.text` (R-32-213: the widget applies the case).
class _ActionLabel extends StatelessWidget {
  const _ActionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label.toUpperCase(),
    style: AppType.monoButton.copyWith(color: AppColor.of(context).accentText),
  );
}

/// The in-place `size.spinner` spinner that replaces the confirm label
/// while the action is in flight, in the label's own ink, like
/// `AppFilledButton`'s `Loading` row.
class _ActionSpinner extends StatelessWidget {
  const _ActionSpinner();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: AppSize.spinner,
    height: AppSize.spinner,
    child: CircularProgressIndicator(
      strokeWidth: _spinnerStroke,
      color: AppColor.of(context).accentText,
    ),
  );
}
