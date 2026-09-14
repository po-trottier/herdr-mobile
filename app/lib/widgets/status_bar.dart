/// The state bar of `docs/32-design-language.md` section 7.29 (`State bar`),
/// per `docs/03-product-decisions.md` R-03-100: a `border.attention` wide
/// rectangle in the state's hue, full row height, flush to the leading edge,
/// beside the state word a caller draws. `working` pulses with
/// `motion.pulse`; nothing else varies by shape. With the platform
/// reduce-motion setting on, the bar is static at full opacity.
library;

import 'package:flutter/widgets.dart'
    show
        AnimationController,
        BuildContext,
        Color,
        ColoredBox,
        CurvedAnimation,
        FadeTransition,
        MediaQuery,
        SingleTickerProviderStateMixin,
        SizedBox,
        State,
        StatefulWidget,
        Tween,
        Widget;

import 'theme/app_color.dart';
import 'theme/app_motion.dart';
import 'theme/app_radius.dart' show AppBorder;

/// The six agent states the bar can show, per `docs/30-ux-spec.md` R-30-401,
/// plus `ok`, `color.status.ok` for a connected connection leg, and
/// `warning`, `color.status.warning` for a stale live bar (R-32-511) or a
/// warning connection leg. Neither pulses.
enum BarState { working, idle, blocked, done, error, unknown, ok, warning }

class StatusBar extends StatefulWidget {
  const StatusBar({super.key, required this.state, this.height});

  final BarState state;

  /// The bar's height where no parent stretches it (a `WidgetSpan`, a
  /// `Stack`). `null` fills the parent's cross axis: put the bar in a `Row`
  /// with `CrossAxisAlignment.stretch`, inside `IntrinsicHeight` when the
  /// row sits in a list, and it takes the row's height.
  final double? height;

  @override
  State<StatusBar> createState() => _StatusBarState();
}

class _StatusBarState extends State<StatusBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: AppMotion.pulseDuration,
    vsync: this,
  );
  late final CurvedAnimation _pulse = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.pulseCurve,
  );

  /// Runs the controller only while a pulse is visible, so a list of idle
  /// bars schedules no frames.
  void _syncPulse(bool pulsing) {
    if (pulsing && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!pulsing && _controller.isAnimating) {
      _controller
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _controller.dispose();
    super.dispose();
  }

  Color _hue(AppColor color) => switch (widget.state) {
    BarState.working => color.statusWorking,
    BarState.idle => color.statusIdle,
    BarState.warning => color.statusWarning,
    BarState.blocked => color.statusBlocked,
    BarState.done => color.statusDone,
    BarState.error => color.statusError,
    BarState.unknown => color.statusUnknown,
    BarState.ok => color.statusOk,
  };

  @override
  Widget build(BuildContext context) {
    final bool pulsing =
        widget.state == BarState.working &&
        !MediaQuery.disableAnimationsOf(context);
    _syncPulse(pulsing);

    final Widget bar = SizedBox(
      width: AppBorder.attention,
      height: widget.height,
      child: ColoredBox(color: _hue(AppColor.of(context))),
    );
    if (!pulsing) {
      return bar;
    }
    return FadeTransition(
      opacity: Tween<double>(
        begin: AppMotion.pulseOpacityFloor,
        end: 1,
      ).animate(_pulse),
      child: bar,
    );
  }
}
