import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart'
    show ExpansionTile, ListTile, Divider, Theme;

import '../app_list_row.dart';
import 'app_color.dart';
import 'app_size.dart';
import 'app_space.dart';
import 'app_type.dart';
import 'chrome_activity_indicator.dart';
import 'chrome_switch.dart';

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

enum _RowKind {
  push,
  choice,
  expand,
  toggle,
  action,
  destructive,
  static,
  sheet,
}

/// A row that uses the platform's list or disclosure control.
class ChromeListRow extends StatelessWidget {
  const ChromeListRow._({
    super.key,
    required this.title,
    required _RowKind kind,
    this.subtitle,
    this.onTap,
    this.showDivider = true,
    Widget? trailing,
    String? trailingLabel,
    Widget? child,
    bool value = false,
    ValueChanged<bool>? onChanged,
    this.initiallyExpanded = false,
    this.onExpansionChanged,
    this.backgroundColor,
    this.padding,
    this.leading,
    this.titleWidget,
    this.selected = false,
    this.destructive = false,
    this.loading = false,
    this.navigation = false,
    // ignore: prefer_initializing_formals
  }) : _kind = kind,
       // ignore: prefer_initializing_formals
       _trailing = trailing,
       // ignore: prefer_initializing_formals
       _trailingLabel = trailingLabel,
       // ignore: prefer_initializing_formals
       _child = child,
       // ignore: prefer_initializing_formals
       _value = value,
       // ignore: prefer_initializing_formals
       _onChanged = onChanged;

  const ChromeListRow.push({
    Key? key,
    required String title,
    String? subtitle,
    Widget? trailing,
    required VoidCallback? onTap,
    bool showDivider = true,
  }) : this._(
         key: key,
         title: title,
         kind: _RowKind.push,
         subtitle: subtitle,
         trailing: trailing,
         onTap: onTap,
         showDivider: showDivider,
       );

  const ChromeListRow.choice({
    Key? key,
    required String title,
    required String valueLabel,
    required VoidCallback? onTap,
    bool showDivider = true,
  }) : this._(
         key: key,
         title: title,
         kind: _RowKind.choice,
         trailingLabel: valueLabel,
         onTap: onTap,
         showDivider: showDivider,
       );

  const ChromeListRow.expand({
    Key? key,
    required String title,
    required Widget child,
    bool initiallyExpanded = false,
    ValueChanged<bool>? onExpansionChanged,
    Widget? trailing,
    Color? backgroundColor,
    EdgeInsetsGeometry? padding,
  }) : this._(
         key: key,
         title: title,
         kind: _RowKind.expand,
         child: child,
         initiallyExpanded: initiallyExpanded,
         onExpansionChanged: onExpansionChanged,
         trailing: trailing,
         backgroundColor: backgroundColor,
         padding: padding,
       );

  const ChromeListRow.toggle({
    Key? key,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
    bool showDivider = true,
  }) : this._(
         key: key,
         title: title,
         kind: _RowKind.toggle,
         subtitle: subtitle,
         value: value,
         onChanged: onChanged,
         showDivider: showDivider,
       );

  const ChromeListRow.action({
    Key? key,
    required String title,
    String? subtitle,
    required String actionLabel,
    required VoidCallback? onTap,
    bool showDivider = true,
  }) : this._(
         key: key,
         title: title,
         kind: _RowKind.action,
         subtitle: subtitle,
         trailingLabel: actionLabel,
         onTap: onTap,
         showDivider: showDivider,
       );

  const ChromeListRow.destructive({
    Key? key,
    required String title,
    required VoidCallback? onTap,
    bool showDivider = true,
  }) : this._(
         key: key,
         title: title,
         kind: _RowKind.destructive,
         onTap: onTap,
         showDivider: showDivider,
       );

  const ChromeListRow.static({
    Key? key,
    required String title,
    String? subtitle,
    Widget? trailing,
    bool showDivider = true,
  }) : this._(
         key: key,
         title: title,
         kind: _RowKind.static,
         subtitle: subtitle,
         trailing: trailing,
         showDivider: showDivider,
       );

  const ChromeListRow.sheet({
    Key? key,
    required String title,
    Widget? titleWidget,
    Widget? leading,
    Widget? trailing,
    String? subtitle,
    VoidCallback? onTap,
    bool selected = false,
    bool destructive = false,
    bool loading = false,
    bool navigation = false,
    bool showDivider = false,
  }) : this._(
         key: key,
         title: title,
         titleWidget: titleWidget,
         kind: _RowKind.sheet,
         leading: leading,
         trailing: trailing,
         subtitle: subtitle,
         onTap: onTap,
         selected: selected,
         destructive: destructive,
         loading: loading,
         navigation: navigation,
         showDivider: showDivider,
       );

  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool showDivider;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;
  final Color? backgroundColor;

  /// The Android disclosure header inset. iOS uses its native fixed inset.
  final EdgeInsetsGeometry? padding;
  final Widget? leading;
  final Widget? titleWidget;
  final bool selected;
  final bool destructive;
  final bool loading;
  final bool navigation;
  final _RowKind _kind;
  final String? _trailingLabel;
  final Widget? _trailing;
  final Widget? _child;
  final bool _value;
  final ValueChanged<bool>? _onChanged;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final Widget titleText = Text(title);
    final Widget? subtitleText = subtitle == null ? null : Text(subtitle!);
    final Widget chevron = Icon(
      Symbols.chevron_right_rounded,
      size: AppSize.iconMd,
      color: color.fgSecondary,
    );
    switch (_kind) {
      case _RowKind.sheet:
        final Widget? glyph = leading == null
            ? null
            : IconTheme.merge(
                data: IconThemeData(
                  color: destructive ? color.statusError : null,
                ),
                child: leading!,
              );
        final List<Widget> accessories = <Widget>[
          if (loading) const ChromeActivityIndicator(),
          ?_trailing,
          if (_isIos && selected)
            Icon(Symbols.check_rounded, color: color.accentText),
          if (_isIos && navigation) chevron,
        ];
        final Widget? accessory = accessories.isEmpty
            ? null
            : Row(mainAxisSize: MainAxisSize.min, children: accessories);
        final Widget label = _WrappingText(child: titleWidget ?? titleText);
        final Widget? description = subtitleText == null
            ? null
            : _WrappingText(child: subtitleText);
        final Widget row = _isIos
            ? Semantics(
                selected: selected,
                enabled: onTap != null && !loading,
                child: Opacity(
                  opacity: onTap == null && !loading ? 0.38 : 1,
                  child: CupertinoListTile(
                    title: label,
                    subtitle: description,
                    leading: glyph,
                    trailing: accessory,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.space4,
                    ),
                    onTap: loading ? null : onTap,
                  ),
                ),
              )
            : ListTile(
                title: label,
                minTileHeight: AppSize.targetMin,
                minVerticalPadding: 0,
                enabled: onTap != null && !loading,
                subtitle: description,
                leading: glyph,
                trailing: accessory,
                selected: selected,
                selectedTileColor: Theme.of(context)
                    .colorScheme
                    .secondaryContainer,
                textColor: onTap != null && !loading ? color.fgPrimary : null,
                selectedColor: onTap != null && !loading
                    ? color.fgPrimary
                    : null,
                onTap: loading ? null : onTap,
              );
        return Semantics(
          hint: destructive ? 'destructive' : null,
          child: showDivider && !_isIos
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[row, const Divider(height: 1)],
                )
              : row,
        );
      case _RowKind.expand:
        if (_isIos) return _IosExpansion(row: this);
        return ExpansionTile(
          title: _trailing == null
              ? titleText
              : Row(
                  children: <Widget>[
                    Expanded(child: titleText),
                    _trailing,
                  ],
                ),
          initiallyExpanded: initiallyExpanded,
          onExpansionChanged: onExpansionChanged,
          backgroundColor: backgroundColor,
          collapsedBackgroundColor: backgroundColor,
          tilePadding: padding,
          children: <Widget>[_child!],
        );
      case _RowKind.toggle:
        final ValueChanged<bool>? onChanged = _onChanged;
        final Widget control = ChromeSwitch(
          value: _value,
          onChanged: onChanged,
        );
        return _isIos
            ? MergeSemantics(
                child: CupertinoListTile(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.space4,
                  ),
                  title: titleText,
                  subtitle: subtitleText,
                  trailing: control,
                ),
              )
            : AppListRow(
                primary: title,
                secondary: subtitle,
                semanticsValue: _value ? 'on' : 'off',
                trailing: ExcludeSemantics(
                  child: IgnorePointer(child: control),
                ),
                onTap: onChanged == null ? null : () => onChanged(!_value),
                showDivider: showDivider,
              );
      case _RowKind.destructive:
        final Widget glyph = Icon(
          Symbols.delete_outline_rounded,
          size: AppSize.iconMd,
          color: color.statusError,
        );
        return MergeSemantics(
          child: Semantics(
            hint: 'destructive',
            enabled: onTap != null,
            child: _isIos
                ? Opacity(
                    opacity: onTap == null ? 0.38 : 1,
                    child: CupertinoListTile(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.space4,
                      ),
                      leading: glyph,
                      title: titleText,
                      onTap: onTap,
                    ),
                  )
                : AppListRow(
                    leading: glyph,
                    primary: title,
                    onTap: onTap,
                    showDivider: showDivider,
                  ),
          ),
        );
      case _RowKind.push:
      case _RowKind.choice:
      case _RowKind.action:
      case _RowKind.static:
        final Widget? trailing = _trailingLabel == null
            ? _trailing
            : Text(
                _trailingLabel,
                style: _kind == _RowKind.action
                    ? AppType.label.copyWith(color: color.accentText)
                    : AppType.body.copyWith(color: color.fgSecondary),
              );
        return _isIos
            ? CupertinoListTile(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.space4,
                ),
                title: titleText,
                subtitle: subtitleText,
                additionalInfo: _kind == _RowKind.push ? trailing : null,
                trailing: _kind == _RowKind.push ? chevron : trailing,
                onTap: onTap,
              )
            : AppListRow(
                primary: title,
                secondary: subtitle,
                trailing: trailing,
                onTap: onTap,
                isStatic: _kind == _RowKind.static,
                showDivider: showDivider,
              );
    }
  }
}

/// Removes the native tile's single-line text limit without replacing its layout.
class _WrappingText extends StatelessWidget {
  const _WrappingText({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DefaultTextStyle(
    style: DefaultTextStyle.of(context).style,
    softWrap: true,
    overflow: TextOverflow.visible,
    child: child,
  );
}

class _IosExpansion extends StatefulWidget {
  const _IosExpansion({required this.row});
  final ChromeListRow row;
  @override
  State<_IosExpansion> createState() => _IosExpansionState();
}

class _IosExpansionState extends State<_IosExpansion> {
  final ExpansibleController _controller = ExpansibleController();
  @override
  void initState() {
    super.initState();
    if (widget.row.initiallyExpanded) _controller.expand();
    _controller.addListener(_changed);
  }

  void _changed() =>
      widget.row.onExpansionChanged?.call(_controller.isExpanded);
  @override
  void dispose() {
    _controller.removeListener(_changed);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ChromeListRow row = widget.row;
    final Widget title = row._trailing == null
        ? Text(row.title)
        : Row(
            children: <Widget>[
              Expanded(child: Text(row.title)),
              row._trailing,
            ],
          );
    final Widget tile = CupertinoExpansionTile(
      title: title,
      controller: _controller,
      child: row._child!,
    );
    return row.backgroundColor == null
        ? tile
        : ColoredBox(color: row.backgroundColor!, child: tile);
  }
}
