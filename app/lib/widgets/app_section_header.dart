import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart' show Symbols;

import 'app_list_row.dart';
import 'theme/app_color.dart';
import 'theme/app_size.dart';
import 'theme/app_space.dart';
import 'theme/app_type.dart';
import 'theme/chrome_icon_action.dart';

/// A section label or a platform row with a disclosure control.
class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader.tier1({
    super.key,
    required this.label,
    required this.expanded,
    this.onToggle,
    this.count,
    this.trailingBadge,
    this.semanticsLabel,
  }) : _upperCase = false;

  const AppSectionHeader.upperCase({super.key, required this.label})
    : _upperCase = true,
      expanded = true,
      onToggle = null,
      count = null,
      trailingBadge = null,
      semanticsLabel = null;

  final String label;
  final bool expanded;
  final VoidCallback? onToggle;
  final String? count;
  final Widget? trailingBadge;
  final String? semanticsLabel;
  final bool _upperCase;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    if (_upperCase) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.space4),
        child: SizedBox(
          height: AppSize.header,
          child: Row(
            children: <Widget>[
              Text(
                label,
                style: AppType.micro.copyWith(color: color.fgSecondary),
              ),
            ],
          ),
        ),
      );
    }
    return SizedBox(
      height: AppSize.rowOneLine,
      child: Semantics(
        expanded: expanded,
        child: AppListRow(
          primary: semanticsLabel ?? label,
          primaryWidget: SizedBox(
            height: AppSize.rowOneLine,
            child: Center(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      label,
                      style: AppType.bodyStrong.copyWith(
                        color: color.fgPrimary,
                      ),
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
              ),
            ),
          ),
          leading: ChromeIconAction(
            icon: expanded
                ? Symbols.expand_more_rounded
                : Symbols.chevron_right_rounded,
            label: semanticsLabel ?? label,
            onPressed: onToggle,
            color: color.fgSecondary,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpace.space4,
          ),
          onTap: onToggle,
          isStatic: onToggle == null,
          showDivider: false,
        ),
      ),
    );
  }
}
