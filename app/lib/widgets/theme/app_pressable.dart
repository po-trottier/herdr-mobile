/// The one interactive wrapper for a pressable row or key cap, per
/// `docs/32-design-language.md` section 7.1. It owns three of the five
/// states of R-32-500 so every pressable the app draws shares one feel:
///
/// - **Pressed**, per R-32-609: the control answers on pointer-down with
///   its pressed fill **and** a scale to `motion.scale.press`, both over
///   `motion.duration.fast` with `motion.curve.enter`, and snaps back at
///   `motion.duration.instant` on release.
/// - **Focused**, per R-32-503 and R-32-127: `border.focus` in
///   `color.accent.text`, drawn outside the control on the parent surface,
///   without moving layout. Enter and Space activate a focused control, so
///   a person on an external keyboard can do what a finger does
///   (`docs/30-ux-spec.md` R-30-718).
/// - **Disabled** by absence: `onTap` null attaches no gesture, no focus and
///   no feedback. The caller dims the control, per R-32-502.
///
/// The list row, the tier 1 section header, the strip's destination tap
/// and the key cap's timing compose this widget. A button does
/// not: every button is the platform's own widget with the platform's own
/// press, focus and disabled responses, per `docs/03-product-decisions.md`
/// R-03-059 (2026-09-09). The scale is a transform only (`AnimatedScale`):
/// no size, padding or position animates, per R-32-609's layout clause.
library;

import 'dart:async' show Timer;

import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter/widgets.dart'
    show
        AnimatedScale,
        Border,
        BorderRadius,
        BoxDecoration,
        BuildContext,
        Clip,
        Curve,
        Curves,
        DecoratedBox,
        Focus,
        FocusNode,
        GestureDetector,
        HitTestBehavior,
        IgnorePointer,
        KeyEvent,
        KeyEventResult,
        MediaQuery,
        Positioned,
        Stack,
        StackFit,
        State,
        StatefulWidget,
        TapDownDetails,
        TapUpDetails,
        VoidCallback,
        Widget;

import 'app_color.dart';
import 'app_motion.dart';
import 'app_radius.dart';

/// `border.focus`, per R-32-330: the one width the focus ring takes.
/// Every border width outside `elev.1`'s stays a local constant beside its
/// one caller, per `app_elev.dart`; this file is the ring's one caller.
const double _borderFocusWidth = 2;

/// Builds the control for one press state. [pressed] is true from
/// pointer-down until release, and never true while [AppPressable.onTap]
/// is null. The flag is positional on purpose, the shape of Flutter's own
/// `ValueWidgetBuilder<bool>`: a builder callback reads as
/// `(context, pressed) => ...` at every call site, and a named flag there
/// would cost each caller a `{required pressed}` for no clearer call.
// ignore: avoid_positional_boolean_parameters
typedef PressableBuilder = Widget Function(BuildContext context, bool pressed);

class AppPressable extends StatefulWidget {
  const AppPressable({
    super.key,
    required this.onTap,
    required this.builder,
    this.radius = AppRadius.sm,
  });

  /// `null` renders [builder] with `pressed` false and attaches no gesture,
  /// no focus and no feedback: a disabled or static control.
  final VoidCallback? onTap;

  final PressableBuilder builder;

  /// The control's own corner radius, which the focus ring follows from
  /// outside: `radius.sm` for a row or a header, `radius.full` for the
  /// jump-to-bottom pill of section 7.14.
  final double radius;

  /// The duration a [builder] hands its `AnimatedContainer` for the
  /// pressed fill: `motion.duration.fast` on the way in,
  /// `motion.duration.instant` on the way out, and instant both ways under
  /// reduce motion, per R-32-606 and R-32-609. Positional like the
  /// builder's own flag, so a caller forwards `pressed` as it received it.
  // ignore: avoid_positional_boolean_parameters
  static Duration fillDuration(BuildContext context, bool pressed) =>
      pressed && !MediaQuery.disableAnimationsOf(context)
      ? AppMotion.durationFast
      : AppMotion.durationInstant;

  /// The curve that pairs with [fillDuration]: `motion.curve.enter`, or
  /// `Curves.linear` under reduce motion, per R-32-606.
  static Curve fillCurve(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
      ? Curves.linear
      : AppMotion.curveEnter;

  @override
  State<AppPressable> createState() => _AppPressableState();
}

class _AppPressableState extends State<AppPressable> {
  bool _pressed = false;
  bool _focused = false;

  /// Runs while the press-in is still animating. A release that lands
  /// before it fires waits for it, so a quick tap shows one full press:
  /// inside a scrollable, Flutter reports the down and the up together for
  /// a tap shorter than its 100 ms deadline, per R-32-609.
  Timer? _pressIn;
  bool _releasePending = false;

  void _down(TapDownDetails _) {
    _pressIn?.cancel();
    _releasePending = false;
    _pressIn = Timer(AppMotion.durationFast, () {
      _pressIn = null;
      if (_releasePending) {
        _release();
      }
    });
    setState(() => _pressed = true);
  }

  void _up(TapUpDetails _) {
    if (_pressIn == null) {
      _release();
    } else {
      _releasePending = true;
    }
  }

  /// A cancelled press, most often a scroll that began under the finger,
  /// lets go at once: the person is no longer pressing this control.
  void _cancel() {
    _pressIn?.cancel();
    _pressIn = null;
    _release();
  }

  void _release() {
    _releasePending = false;
    if (mounted && _pressed) {
      setState(() => _pressed = false);
    }
  }

  KeyEventResult _onKeyEvent(FocusNode _, KeyEvent event) {
    final VoidCallback? onTap = widget.onTap;
    if (onTap == null || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    if (key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter &&
        key != LogicalKeyboardKey.space &&
        key != LogicalKeyboardKey.select) {
      return KeyEventResult.ignored;
    }
    onTap();
    return KeyEventResult.handled;
  }

  @override
  void didUpdateWidget(AppPressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onTap == null && oldWidget.onTap != null) {
      _cancel();
    }
  }

  @override
  void dispose() {
    _pressIn?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onTap != null;
    final bool pressed = _pressed && enabled;
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);

    final Widget control = AnimatedScale(
      scale: pressed && !reduceMotion ? AppMotion.scalePress : 1,
      duration: AppPressable.fillDuration(context, pressed),
      curve: AppPressable.fillCurve(context),
      child: widget.builder(context, pressed),
    );

    return Focus(
      canRequestFocus: enabled,
      skipTraversal: !enabled,
      onFocusChange: (bool hasFocus) => setState(() => _focused = hasFocus),
      onKeyEvent: _onKeyEvent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? _down : null,
        onTapUp: enabled ? _up : null,
        onTapCancel: enabled ? _cancel : null,
        onTap: widget.onTap,
        child: Stack(
          fit: StackFit.passthrough,
          clipBehavior: Clip.none,
          children: <Widget>[
            control,
            // The ring sits outside the control's own bounds, on the parent
            // surface, and adds nothing to layout: focus never moves a
            // neighbour. Its outer corner is the control's own radius plus
            // the ring's own width, so its inner edge hugs the control.
            if (_focused && enabled)
              Positioned(
                left: -_borderFocusWidth,
                top: -_borderFocusWidth,
                right: -_borderFocusWidth,
                bottom: -_borderFocusWidth,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppColor.of(context).accentText,
                        width: _borderFocusWidth,
                      ),
                      borderRadius: BorderRadius.circular(
                        widget.radius + _borderFocusWidth,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
