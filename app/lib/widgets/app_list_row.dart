/// The one row, per `docs/32-design-language.md` section 7.4 (list row,
/// with a status badge and a timestamp) and
/// `docs/90-implementation-plan.md` Phase 12's shared-primitives
/// checklist item. This is the content row a list of agents, hosts or
/// paired phones is built from; `chrome_list_row.dart`'s `ChromeListRow`
/// is a distinct, platform-native settings-navigation row and is out of
/// scope here.
///
/// [leading] and [trailing] are open slots. The row's state is not a
/// leading widget: it is the state bar of [state], per
/// `docs/03-product-decisions.md` R-03-100, flush to the leading edge.
library;

import 'package:flutter/widgets.dart'
    show
        AnimatedContainer,
        Border,
        BorderSide,
        BoxDecoration,
        BuildContext,
        Color,
        Column,
        CrossAxisAlignment,
        DecoratedBox,
        EdgeInsets,
        ExcludeSemantics,
        Expanded,
        MainAxisAlignment,
        Opacity,
        Padding,
        PositionedDirectional,
        Row,
        Semantics,
        SizedBox,
        Stack,
        StackFit,
        StatelessWidget,
        Text,
        TextOverflow,
        VoidCallback,
        Widget;
import 'package:material_ui/material_ui.dart' show CircularProgressIndicator;

import 'status_bar.dart';
import 'theme/app_color.dart';
import 'theme/app_pressable.dart';
import 'theme/app_radius.dart';
import 'theme/app_size.dart';
import 'theme/app_space.dart';
import 'theme/app_type.dart';

/// `opacity.disabled`, per the opacity table beside R-32-330, for a row
/// that is a control and is disabled, per R-32-502.
const double _opacityDisabled = 0.38;

/// The spinner stroke, the one width the in-place spinner takes.
const double _spinnerStroke = 2;

/// One content row, per the anatomy table of section 7.4: `size.row.one_line`
/// high with [primary] alone and `size.row.two_line` with a [secondary]
/// line; `primary` in `type.body.strong` `fg.primary`, `secondary` in
/// `type.caption` `fg.secondary`; optional [leading] and [trailing] slots;
/// a divider `border.hairline` in `color.border.subtle` inset `space.4`
/// from the leading edge, which [showDivider] false removes for the last
/// row of a section; pressed `color.bg.high`, per R-32-501's third case
/// and R-32-609; [selected] an `accent.soft` wash; [state] the state bar of
/// R-03-100, `border.attention` wide in the state's hue, flush to the
/// leading edge.
///
/// R-32-515: this widget exposes exactly one semantics node. [onTap]'s
/// action MUST also exist as a named custom semantics action where a
/// swipe reveals it — that composition is the caller's, one level up,
/// because this widget owns the row's own content only.
class AppListRow extends StatelessWidget {
  const AppListRow({
    super.key,
    this.leading,
    required this.primary,
    this.primaryColor,
    this.secondary,
    this.semanticsValue,
    this.trailing,
    this.state,
    this.onTap,
    this.selected = false,
    this.isLoading = false,
    this.isStatic = false,
    this.showDivider = true,
  });

  /// A leading glyph, `size.icon.md` or smaller. Never a state mark: the
  /// state is the bar of [state] (R-03-100).
  final Widget? leading;

  /// `type.body.strong` in `color.fg.primary`.
  final String primary;

  /// Overrides the primary label color for status or destructive actions.
  final Color? primaryColor;

  /// `type.caption` in `color.fg.secondary`. `null` selects the one-line
  /// height; a value selects the two-line height even while [isLoading]
  /// hides it, so a row never changes height as an action runs.
  final String? secondary;

  /// The `<value>` half of the `<label>, <value>` semantics pattern of
  /// R-32-505. `null` when [primary] alone already names the row.
  final String? semanticsValue;

  /// A trailing state word, age, chevron or badge cluster. Expected to use
  /// `type.micro` UPPER in `fg.secondary`.
  final Widget? trailing;

  /// The row's state, drawn as the state bar of R-03-100: `border.attention`
  /// wide in the state's hue, full row height, flush to the leading edge,
  /// beside the state word a caller puts in [trailing]. `null` draws no bar.
  final BarState? state;

  final VoidCallback? onTap;

  /// Whether the row is "the one that is live": an `accent.soft` wash, the
  /// selected-row anatomy of section 7.4 (`docs/31-mockups/05-host-list.md`
  /// callout 8). Weight and wash carry a selection, never a second bar
  /// (R-03-100). The content keeps its `space.4` inset, so selecting a row
  /// never moves its text.
  final bool selected;

  /// Whether the row is in a loading state (shows spinner in place of label).
  final bool isLoading;

  /// A row that is information, not a control: it never dims and keeps its
  /// semantics node. `opacity.disabled` of `R-32-502` is for a disabled
  /// control only; a row that was never tappable is not disabled
  /// (`docs/31-mockups/19-about.md`, callouts 2 and 3, R-31-19-07).
  final bool isStatic;

  /// Whether the row draws its bottom divider. The last row of a list
  /// section passes false, per the section 7.4 table (decided 2026-09-03
  /// by the product owner), so a section's own hairline never stacks on
  /// the row's into a 2 px line.
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final bool twoLine = secondary != null;
    final double height = twoLine ? AppSize.rowTwoLine : AppSize.rowOneLine;

    final Widget primaryWidget = isLoading
        ? const SizedBox(
            width: AppSize.spinner,
            height: AppSize.spinner,
            child: CircularProgressIndicator(strokeWidth: _spinnerStroke),
          )
        : Text(
            primary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.bodyStrong.copyWith(
              color: primaryColor ?? color.fgPrimary,
            ),
          );

    final Widget textColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        primaryWidget,
        if (twoLine && !isLoading)
          Text(
            secondary!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.caption.copyWith(color: color.fgSecondary),
          ),
      ],
    );

    // The divider and the content share one inset from the leading edge,
    // so the hairline starts under the first glyph, never under the state
    // bar or the gutter.
    Widget inset = Padding(
      padding: const EdgeInsets.only(right: AppSpace.space4),
      child: Row(
        children: <Widget>[
          if (leading != null) ...<Widget>[
            leading!,
            const SizedBox(width: AppSpace.space3),
          ],
          Expanded(child: textColumn),
          ?trailing,
        ],
      ),
    );
    if (showDivider) {
      inset = DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: color.borderSubtle,
              width: AppBorder.hairline,
            ),
          ),
        ),
        child: inset,
      );
    }

    final bool interactive = onTap != null && !isLoading;

    // The bar is a positioned child over the fill: it sits flush to the
    // leading edge, spans the row's height and adds nothing to the content
    // inset, so the text stays in the `space.4` column whether the row has
    // a state, is selected or neither.
    final Widget row = AppPressable(
      onTap: interactive ? onTap : null,
      builder: (BuildContext context, bool pressed) => AnimatedContainer(
        duration: AppPressable.fillDuration(context, pressed),
        curve: AppPressable.fillCurve(context),
        height: height,
        decoration: BoxDecoration(
          color: pressed
              ? color.bgHigh
              : selected
              ? color.accentSoft
              : null,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(left: AppSpace.space4),
              child: inset,
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
      ),
    );

    final String label = semanticsValue == null
        ? primary
        : '$primary, $semanticsValue';

    final bool disabled = onTap == null && !isLoading && !isStatic;

    return Semantics(
      label: label,
      button: onTap != null,
      enabled: isStatic ? null : interactive,
      onTap: interactive ? onTap : null,
      excludeSemantics: true,
      child: disabled
          ? Opacity(
              opacity: _opacityDisabled,
              child: ExcludeSemantics(child: row),
            )
          : row,
    );
  }
}
