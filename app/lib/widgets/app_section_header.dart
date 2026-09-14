/// The one section header, per `docs/32-design-language.md` section
/// 7.23 (R-32-563 to R-32-570) and `docs/90-implementation-plan.md`
/// Phase 12 shared-primitives checklist item. The shared widget has two forms.
/// Forms are [AppSectionHeader.tier1] and [AppSectionHeader.upperCase].
/// The agent-list anatomy owns its tab and worktree tiers.
library;

import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart'
    show
        AnimatedContainer,
        BoxDecoration,
        BuildContext,
        CrossAxisAlignment,
        EdgeInsets,
        Expanded,
        Icon,
        IconData,
        Padding,
        Row,
        Semantics,
        SizedBox,
        StatelessWidget,
        Text,
        TextBaseline,
        TextOverflow,
        VoidCallback,
        Widget;

import 'theme/app_color.dart';
import 'theme/app_pressable.dart';
import 'theme/app_size.dart';
import 'theme/app_space.dart';
import 'theme/app_type.dart';

enum _Tier { one, upperCase }

/// One of the two shared header forms of R-32-563. [AppSectionHeader.tier1]
/// is the only form a screen collapses, per R-32-564 and R-32-565: it
/// presents a `size.target.min`-or-larger target and toggles [expanded]
/// through [onToggle]. The agent-list anatomy owns the tier ladder of
/// R-32-570.
class AppSectionHeader extends StatelessWidget {
  /// Tier 1: a space name, in `type.body.strong`, height
  /// `size.row.one_line`, indent `space.4`. [count] and [trailingBadge]
  /// stay visible while [expanded] is false, per R-32-566.
  /// [semanticsLabel], when given, replaces [label] as the spoken label,
  /// so a screen reader hears the count and the attention count too.
  const AppSectionHeader.tier1({
    super.key,
    required this.label,
    required this.expanded,
    this.onToggle,
    this.count,
    this.trailingBadge,
    this.semanticsLabel,
  }) : _tier = _Tier.one;

  /// The single upper-case tier: one of our own words, in `type.micro`
  /// UPPER `fg.secondary`, height `size.header`, indent `space.4`. Always
  /// pins and never collapses, per R-32-569. The header is the label
  /// alone; no rule trails it (decided 2026-09-03 by the product owner).
  /// [label] MUST already be the upper-case form the caller wants shown,
  /// per R-32-567: this widget upper-cases nothing, because a person's
  /// own data MUST NOT be re-cased.
  const AppSectionHeader.upperCase({super.key, required this.label})
    : _tier = _Tier.upperCase,
      expanded = true,
      onToggle = null,
      count = null,
      trailingBadge = null,
      semanticsLabel = null;

  /// The header's own text. Its case is the caller's choice, per
  /// R-32-567.
  final String label;

  /// Tier 1 only: whether the branch below is open. Ignored by every
  /// other tier.
  final bool expanded;

  /// Tier 1 only. `null` renders a non-interactive header.
  final VoidCallback? onToggle;

  /// Tier 1's trailing count, `type.caption` in `color.fg.secondary`.
  final String? count;

  /// Tier 1's trailing badge, per R-32-518, drawn after [count] with a
  /// `space.2` gap. `null` draws none.
  final Widget? trailingBadge;

  /// Tier 1 only: the spoken label when it differs from [label].
  final String? semanticsLabel;

  final _Tier _tier;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    switch (_tier) {
      case _Tier.one:
        return _buildTier1(color);
      case _Tier.upperCase:
        return _buildUpperCase(color);
    }
  }

  /// Tier 1 is the one header that is a control, so it takes the pressed
  /// state of R-32-501's third case through `AppPressable`: no fill presses
  /// to `color.bg.high`, the label unchanged, plus the press scale of
  /// R-32-609. `onToggle` null renders the same row with no gesture.
  ///
  /// The label, the count and the badge share one alphabetic baseline,
  /// per R-32-563's table (amended 2026-09-08): a centred row put the
  /// smaller `type.caption` count and the `type.micro.strong` badge count
  /// 2 to 3 px above the name's baseline. The expander stays outside that
  /// row, centred in the 52 box, because an icon glyph's font baseline
  /// says nothing about where its shape sits.
  Widget _buildTier1(AppColor color) {
    final IconData expander = expanded
        ? Symbols.expand_more_rounded
        : Symbols.chevron_right_rounded;
    final Widget text = Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: AppType.bodyStrong.copyWith(color: color.fgPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (count != null)
          Text(
            count!,
            style: AppType.caption.copyWith(color: color.fgSecondary),
          ),
        if (trailingBadge != null) ...<Widget>[
          const SizedBox(width: AppSpace.space2),
          trailingBadge!,
        ],
      ],
    );
    final Widget row = Row(
      children: <Widget>[
        Icon(expander, size: AppSize.iconMd, color: color.fgSecondary),
        const SizedBox(width: AppSpace.space3),
        Expanded(child: text),
      ],
    );
    return Semantics(
      label: semanticsLabel ?? label,
      button: onToggle != null,
      expanded: expanded,
      onTap: onToggle,
      excludeSemantics: true,
      child: AppPressable(
        onTap: onToggle,
        builder: (BuildContext context, bool pressed) => AnimatedContainer(
          duration: AppPressable.fillDuration(context, pressed),
          curve: AppPressable.fillCurve(context),
          height: AppSize.rowOneLine,
          decoration: BoxDecoration(color: pressed ? color.bgHigh : null),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.space4),
          child: row,
        ),
      ),
    );
  }

  /// alone, with no rule under or beside it.
  /// decided 2026-09-03 by the product owner: no trailing tape rule.
  Widget _buildUpperCase(AppColor color) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpace.space4),
    child: SizedBox(
      height: AppSize.header,
      child: Row(
        children: <Widget>[
          Text(label, style: AppType.micro.copyWith(color: color.fgSecondary)),
        ],
      ),
    ),
  );
}
