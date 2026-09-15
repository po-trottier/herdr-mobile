/// A platform-native content row with one accessible label.
library;

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoColors, CupertinoListTile;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart'
    show Divider, ListTile, Material, MaterialType;

import 'status_bar.dart';
import 'theme/app_color.dart';
import 'theme/app_radius.dart';
import 'theme/app_size.dart';
import 'theme/app_space.dart';
import 'theme/app_type.dart';
import 'theme/chrome_activity_indicator.dart';

class AppListRow extends StatelessWidget {
  const AppListRow({
    super.key,
    this.leading,
    required this.primary,
    this.primaryWidget,
    this.contentPadding,
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
    this.preserveTrailingSemantics = false,
    this.customSemanticsActions,
  });

  final Widget? leading;
  final String primary;
  final Widget? primaryWidget;
  final EdgeInsetsGeometry? contentPadding;
  final Color? primaryColor;
  final String? secondary;
  final String? semanticsValue;
  final Widget? trailing;
  final BarState? state;
  final VoidCallback? onTap;
  final bool selected;
  final bool isLoading;
  final bool isStatic;
  final bool showDivider;
  final bool preserveTrailingSemantics;
  final Map<CustomSemanticsAction, VoidCallback>? customSemanticsActions;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final bool ios = defaultTargetPlatform == TargetPlatform.iOS;
    final bool interactive = onTap != null && !isLoading;
    final bool disabled = onTap == null && !isLoading && !isStatic;
    final double height = secondary == null
        ? AppSize.rowOneLine
        : AppSize.rowTwoLine;
    final Widget title = isLoading
        ? const Align(
            alignment: AlignmentDirectional.centerStart,
            child: ChromeActivityIndicator(),
          )
        : primaryWidget ??
              Text(
                primary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.bodyStrong.copyWith(
                  color: primaryColor ?? color.fgPrimary,
                ),
              );
    final Widget? subtitle = secondary != null && !isLoading
        ? Text(
            secondary!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.caption.copyWith(color: color.fgSecondary),
          )
        : null;
    final Widget tile = ios
        ? CupertinoListTile(
            title: ExcludeSemantics(
              excluding: preserveTrailingSemantics,
              child: title,
            ),
            subtitle: subtitle == null
                ? null
                : ExcludeSemantics(
                    excluding: preserveTrailingSemantics,
                    child: subtitle,
                  ),
            leading: leading,
            leadingSize: AppSize.iconMd,
            leadingToTitle: AppSpace.space3,
            trailing: trailing,
            padding:
                contentPadding?.resolve(Directionality.of(context)) ??
                const EdgeInsets.symmetric(
                  horizontal: AppSpace.space4,
                  vertical: AppSpace.space3,
                ),
            backgroundColor: selected
                ? color.accentSoft
                : CupertinoColors.transparent,
            backgroundColorActivated: color.bgHigh,
            onTap: interactive ? onTap : null,
          )
        : ListTile(
            title: ExcludeSemantics(
              excluding: preserveTrailingSemantics,
              child: title,
            ),
            subtitle: subtitle == null
                ? null
                : ExcludeSemantics(
                    excluding: preserveTrailingSemantics,
                    child: subtitle,
                  ),
            leading: leading,
            trailing: trailing,
            contentPadding:
                contentPadding ??
                const EdgeInsets.symmetric(horizontal: AppSpace.space4),
            minLeadingWidth: AppSize.iconMd,
            horizontalTitleGap: AppSpace.space3,
            minTileHeight: primaryWidget == null || secondary != null
                ? height
                : 0,
            minVerticalPadding: 0,
            selected: selected,
            selectedTileColor: color.accentSoft,
            enabled: !disabled && !isLoading,
            onTap: interactive ? onTap : null,
          );
    final Widget row = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: primaryWidget == null || secondary != null ? height : 0,
      ),
      child: Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          if (ios)
            tile
          else
            Material(type: MaterialType.transparency, child: tile),
          if (showDivider)
            PositionedDirectional(
              start: AppSpace.space4,
              end: 0,
              bottom: 0,
              child: Divider(
                height: AppBorder.hairline,
                thickness: AppBorder.hairline,
                color: color.borderSubtle,
              ),
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
    return Semantics(
      label: semanticsValue == null ? primary : '$primary, $semanticsValue',
      button: onTap != null,
      selected: selected,
      enabled: isStatic ? null : interactive,
      onTap: interactive ? onTap : null,
      excludeSemantics: !preserveTrailingSemantics,
      container: preserveTrailingSemantics,
      customSemanticsActions: customSemanticsActions,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[disabled ? Opacity(opacity: 0.38, child: row) : row],
      ),
    );
  }
}
