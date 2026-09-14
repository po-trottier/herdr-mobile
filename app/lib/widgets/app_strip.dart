/// The one strip, per `docs/32-design-language.md` section 7.22
/// (R-32-561, the `Strip` row of its table) and
/// `docs/90-implementation-plan.md` Phase 12's shared-primitives
/// checklist item.
library;

import 'package:flutter/widgets.dart'
    show
        AnimatedContainer,
        Border,
        BorderSide,
        BoxDecoration,
        BuildContext,
        Color,
        DecoratedBox,
        EdgeInsets,
        Expanded,
        Padding,
        PositionedDirectional,
        Row,
        Stack,
        StatelessWidget,
        VoidCallback,
        Widget;

import 'status_bar.dart' show BarState, StatusBar;
import 'theme/app_color.dart';
import 'theme/app_pressable.dart';
import 'theme/app_radius.dart';
import 'theme/app_space.dart';

/// A full-width band, surface `color.bg.raised`, `radius.none`, padding
/// `space.3` by `space.4`, hairline top and bottom in `color.border.subtle`.
/// [child] is normally one of the four `Treatment` widgets, per the anatomy
/// table's `Text` row, "a treatment for the state": the state hue lives in
/// the treatment's icon and, for `treat.error`, its own `inStrip` bar
/// (R-32-506). The strip draws no bar of its own.
///
/// [onTapDestination] is R-32-561's whole-width tap: permitted only when
/// this strip names a place it routes to, and MUST NOT be work that
/// goes nowhere. [trailing] carries that other kind of work instead — a
/// `Try again` text action or a dismiss control — as a sibling outside
/// the tappable region, so the two controls never compete for the same
/// gesture. The destination region presses to `color.bg.high`, per
/// R-32-501's third case and R-32-609, through `AppPressable`.
class AppStrip extends StatelessWidget {
  const AppStrip({
    super.key,
    required this.child,
    this.onTapDestination,
    this.trailing,
    this.state,
    this.statusColor,
  });

  final Widget child;
  final VoidCallback? onTapDestination;
  final Widget? trailing;

  /// The state bar of R-03-100 at the strip's leading edge, the strip's
  /// full height, when the strip reports a state a person must read at a
  /// glance: the connection strip (2026-09-10, the owner found `Not
  /// connected` indistinguishable from connected). The content keeps its
  /// `space.4` inset, so the bar moves no text. `null` draws none.
  final BarState? state;

  /// Has no effect, and is kept only so the callers of this wave still
  /// compile: the strip anatomy of section 7.22 has no leading bar, and a
  /// bare status colour beside a sentence is what R-32-506 forbids. The
  /// earlier bar never painted (a childless box in a row has no height)
  /// but its `space.3` gutter did, which pushed the strip's text 12 px
  /// right of the column every neighbour uses. Put the hue in a
  /// `Treatment`, or a [state], and drop this argument.
  final Color? statusColor;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    const EdgeInsets inset = EdgeInsets.symmetric(
      horizontal: AppSpace.space4,
      vertical: AppSpace.space3,
    );

    final Widget content = onTapDestination == null
        ? Padding(padding: inset, child: child)
        : AppPressable(
            onTap: onTapDestination,
            builder: (BuildContext context, bool pressed) => AnimatedContainer(
              duration: AppPressable.fillDuration(context, pressed),
              curve: AppPressable.fillCurve(context),
              decoration: BoxDecoration(color: pressed ? color.bgHigh : null),
              padding: inset,
              child: child,
            ),
          );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.bgRaised,
        border: Border(
          top: BorderSide(color: color.borderSubtle, width: AppBorder.hairline),
          bottom: BorderSide(
            color: color.borderSubtle,
            width: AppBorder.hairline,
          ),
        ),
      ),
      child: Stack(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: content),
              ?trailing,
            ],
          ),
          if (state != null)
            PositionedDirectional(
              start: 0,
              top: 0,
              bottom: 0,
              child: StatusBar(state: state!),
            ),
        ],
      ),
    );
  }
}
