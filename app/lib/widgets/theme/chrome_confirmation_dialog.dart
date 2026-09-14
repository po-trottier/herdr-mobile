/// The two dialogs the app is permitted, both named by role: the destructive
/// confirmation of `docs/33-platform-chrome.md` R-33-074, and the alert of
/// `docs/03-product-decisions.md` R-03-119 for a terminal state that ends the
/// person's work. One platform split, [_show], serves both.
library;

import 'package:cupertino_ui/cupertino_ui.dart'
    show
        BuildContext,
        Column,
        CrossAxisAlignment,
        CupertinoAlertDialog,
        CupertinoDialogAction,
        MainAxisSize,
        ModalRoute,
        Navigator,
        NavigatorState,
        PopScope,
        SizedBox,
        Text,
        Widget,
        WidgetsBinding,
        showCupertinoDialog;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:material_ui/material_ui.dart'
    show
        AlertDialog,
        BorderRadius,
        BorderSide,
        RoundedRectangleBorder,
        TextButton,
        showDialog;

import '../key_label.dart';
import '../treatments.dart';
import 'app_color.dart';
import 'app_radius.dart';
import 'app_space.dart';
import 'app_type.dart';
import 'chrome_confirmation_outcome.dart';

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

/// Shows a confirmation dialog named by role, never by position: the
/// caller fixes only the title, the body and the destructive verb, per
/// R-33-074.1. On iOS the cancelling action is always titled `Cancel`,
/// per R-33-074.2, and neither action is the default, per R-33-074.3.
/// [cancelLabel] applies on Android only, where the platform names no
/// required word.
///
/// The Material `AlertDialog` this package ships takes an `actions` list,
/// not the named `confirmButton`/`dismissButton` slots R-33-074.4
/// describes; passing the safe action first and the destructive action
/// last, in that fixed role order, is this file's compliance with "let
/// the component place them": neither an explicit position nor a row
/// order is chosen here, only the role order the widget's own layout
/// then arranges.
///
/// Each role carries its own composition from `docs/32` section 7.17 on
/// both platforms (amended 2026-09-08): the destructive verb is
/// `treat.destructive`, its hue in the icon and the leading bar and its
/// text `color.fg.primary`, per R-32-527; the safe action is
/// `type.body.strong` in `color.fg.primary`. The platform component keeps
/// its own order, its own role flag and its own press feedback.
Future<ChromeConfirmationOutcome?> showChromeConfirmationDialog({
  required BuildContext context,
  required String title,
  required String body,
  required String destructiveLabel,
  String cancelLabel = 'Cancel',
}) {
  final AppColor color = AppColor.of(context);
  return _show<ChromeConfirmationOutcome>(
    context: context,
    color: color,
    title: _title(title, color),
    content: _body(body, color),
    actions: <_Action<ChromeConfirmationOutcome>>[
      (
        child: _safe(_isIos ? 'Cancel' : cancelLabel, color),
        result: ChromeConfirmationOutcome.cancel,
        isDefault: false,
        isDestructive: false,
      ),
      (
        child: Treatment.destructive(label: destructiveLabel),
        result: ChromeConfirmationOutcome.destructive,
        isDefault: false,
        isDestructive: true,
      ),
    ],
    dismissible: true,
  ).result;
}

/// One action of [showChromeAlertDialog], named by role: the [label] a
/// person reads and the [result] [ChromeDialogHandle.result] completes with.
typedef ChromeAlertAction<T> = ({String label, T result});

/// Shows the alert of R-03-119 for a terminal state that ends the person's
/// work and offers only a way out. The caller fixes the [title], an optional
/// [body] sentence, an optional [detail] such as a raw error, the
/// [defaultAction] and, where the state offers two ways out, the
/// [otherAction]; the platform component places them (R-33-074.1). The
/// dialog closes on an action, or on [ChromeDialogHandle.dismiss] when the
/// state that raised it ends, and on nothing else: not a barrier tap, not a
/// back gesture.
///
/// The shared anatomy of `docs/32` section 7.17 (R-32-547): the title in
/// `type.heading` and the body in `type.body`, both `color.fg.primary`; the
/// detail in `type.mono.code` in `color.fg.secondary`, the raw-error
/// treatment the terminal's own state block used until R-03-119. The default
/// action is `type.body.strong` and the other action `type.body`, both
/// `color.fg.primary`, so the default reads the way the platform marks it:
/// bold on iOS, where `isDefaultAction` is set too, and trailing on both,
/// per R-33-074.2.
ChromeDialogHandle<T> showChromeAlertDialog<T>({
  required BuildContext context,
  required String title,
  String? body,
  String? detail,
  required ChromeAlertAction<T> defaultAction,
  ChromeAlertAction<T>? otherAction,
}) {
  final AppColor color = AppColor.of(context);
  final List<Widget> lines = <Widget>[
    if (body != null) _body(body, color),
    if (detail != null)
      Text(detail, style: AppType.monoCode.copyWith(color: color.fgSecondary)),
  ];
  return _show<T>(
    context: context,
    color: color,
    title: _title(title, color),
    content: switch (lines) {
      [] => null,
      [final Widget line] => line,
      _ => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          lines.first,
          const SizedBox(height: AppSpace.space2),
          lines.last,
        ],
      ),
    },
    actions: <_Action<T>>[
      if (otherAction != null)
        (
          child: Text(
            otherAction.label,
            style: AppType.body.copyWith(color: color.fgPrimary),
          ),
          result: otherAction.result,
          isDefault: false,
          isDestructive: false,
        ),
      (
        child: _safe(defaultAction.label, color),
        result: defaultAction.result,
        isDefault: true,
        isDestructive: false,
      ),
    ],
    dismissible: false,
  );
}

/// A platform dialog this file pushed. [result] completes with the chosen
/// action's result, or with `null` when the dialog closed with no choice: a
/// barrier tap or a back gesture where the dialog allowed one, [dismiss], or
/// the route under it leaving the navigator.
class ChromeDialogHandle<T> {
  ChromeDialogHandle._();

  late final Future<T?> result;
  ModalRoute<Object?>? _route;
  bool _dismissed = false;

  /// Closes this dialog and nothing else: a route above it, such as the lock
  /// screen, stays. A dialog not on screen yet closes as soon as it is.
  void dismiss() {
    _dismissed = true;
    _close();
  }

  /// Remembers the dialog's own route from its first build.
  void _attach(BuildContext dialogContext) {
    if (_route != null) return;
    _route = ModalRoute.of<Object?>(dialogContext);
    if (_dismissed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _close());
    }
  }

  void _close() {
    final ModalRoute<Object?>? route = _route;
    if (route == null || !route.isActive) return;
    final NavigatorState navigator = route.navigator!;
    if (route.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
  }
}

/// One action of [_show], composed for its role: [child] is the role's own
/// composition from `docs/32` section 7.17, [result] what the handle's future
/// completes with, and the two flags the platform component's own role marks
/// (R-33-074.2).
typedef _Action<T> = ({
  Widget child,
  T result,
  bool isDefault,
  bool isDestructive,
});

/// The one platform split of this file: the Material `AlertDialog` through
/// `showDialog` on Android, the `CupertinoAlertDialog` with
/// `CupertinoDialogAction` actions through `showCupertinoDialog` on iOS, both
/// on the root navigator, with [actions] in role order for the component to
/// place (R-33-074.4). [dismissible] `false` keeps the barrier tap and the
/// back gesture (`PopScope`) from closing the dialog, so its actions are the
/// only way out (R-03-119). On iOS the barrier never closes a dialog, whatever
/// [dismissible] says: Apple's own alerts do not, and `showCupertinoDialog`
/// defaults to that.
ChromeDialogHandle<T> _show<T>({
  required BuildContext context,
  required AppColor color,
  required Widget title,
  required Widget? content,
  required List<_Action<T>> actions,
  required bool dismissible,
}) {
  final ChromeDialogHandle<T> handle = ChromeDialogHandle<T>._();
  Widget dialog(BuildContext dialogContext) {
    handle._attach(dialogContext);
    void choose(_Action<T> action) =>
        Navigator.of(dialogContext).pop(action.result);
    final Widget body = _isIos
        ? CupertinoAlertDialog(
            title: title,
            content: content,
            actions: <Widget>[
              for (final _Action<T> action in actions)
                CupertinoDialogAction(
                  isDefaultAction: action.isDefault,
                  isDestructiveAction: action.isDestructive,
                  onPressed: () => choose(action),
                  child: action.child,
                ),
            ],
          )
        : AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              side: BorderSide(
                color: color.borderSubtle,
                width: AppBorder.hairline,
              ),
            ),
            title: title,
            content: content,
            actions: <Widget>[
              for (final _Action<T> action in actions)
                TextButton(
                  onPressed: () => choose(action),
                  child: action.child,
                ),
            ],
          );
    return dismissible ? body : PopScope(canPop: false, child: body);
  }

  handle.result = _isIos
      ? showCupertinoDialog<T>(context: context, builder: dialog)
      : showDialog<T>(
          context: context,
          barrierDismissible: dismissible,
          builder: dialog,
        );
  return handle;
}

/// The title in `type.heading`, `color.fg.primary` (R-32-547).
Widget _title(String title, AppColor color) =>
    Text(title, style: AppType.heading.copyWith(color: color.fgPrimary));

/// The body in `type.body`, `color.fg.primary` (R-32-547); a key named in
/// it, such as `press {d}`, draws as a cap (R-32-599).
Widget _body(String body, AppColor color) => keyedText(
  body,
  style: AppType.body.copyWith(color: color.fgPrimary),
  color: color,
);

/// A safe action's own composition: `type.body.strong` in `color.fg.primary`
/// (section 7.17).
Widget _safe(String label, AppColor color) =>
    Text(label, style: AppType.bodyStrong.copyWith(color: color.fgPrimary));
