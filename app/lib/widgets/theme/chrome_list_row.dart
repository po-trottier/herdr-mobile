/// A list row with exactly one outcome, per `docs/33-platform-chrome.md`
/// R-33-072, composed from the platform's own row widget, per R-33-073.
///
/// **R-33-070, back.** Omitted on purpose, here and in every sibling file
/// under `lib/widgets/theme/`. This directory places no back glyph and
/// holds no icon map. A screen leaves `AppBar.leading` and
/// `CupertinoNavigationBar.leading` unset when it pushes the next level
/// through [ChromeListRow.push], so Flutter's own `BackButton` and the
/// automatic Cupertino back control draw the glyph, the localised label
/// and the pop gesture. Nothing here constructs one.
library;

import 'package:cupertino_ui/cupertino_ui.dart'
    show
        BuildContext,
        Color,
        CupertinoExpansionTile,
        CupertinoListTile,
        CupertinoSwitch,
        ExcludeSemantics,
        Icon,
        IgnorePointer,
        MergeSemantics,
        Opacity,
        Semantics,
        StatelessWidget,
        Text,
        ValueChanged,
        VoidCallback,
        Widget,
        WidgetState,
        WidgetStateProperty,
        WidgetStatePropertyAll;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart'
    show ExpansionTile, Material, MaterialType, Switch;

import '../app_list_row.dart';
import 'app_color.dart';
import 'app_radius.dart';
import 'app_size.dart';
import 'app_type.dart';

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

/// `opacity.disabled`, per the opacity table beside R-32-330, for the
/// Material switch of a disabled toggle row, per R-32-502. The row itself
/// stays at full opacity, because its label is still information; only
/// the control dims.
const double _opacityDisabled = 0.38;

enum _RowKind { push, choice, expand, toggle, action, destructive, static }

/// One settings row, composed per R-33-073: on iOS a [CupertinoListTile]
/// (or a [CupertinoExpansionTile]), which keeps the platform's own tile
/// height and inset; on Android the [AppListRow] of
/// `docs/32-design-language.md` section 7.4, whose row values reach
/// Android only (noted there 2026-09-08). One row, one outcome, per
/// R-33-072: [ChromeListRow.push] pushes the next level,
/// [ChromeListRow.choice] opens a sheet or a single-choice screen,
/// [ChromeListRow.expand] opens in place, [ChromeListRow.toggle] flips one
/// switch, [ChromeListRow.action] runs one labelled action (its
/// destructive form is [ChromeListRow.destructive]), and
/// [ChromeListRow.static] is information only. This rule reaches a list
/// row only; a bottom-sheet action row is out of scope, per R-33-072.5.
class ChromeListRow extends StatelessWidget {
  /// Pushes the next level in the hierarchy. iOS carries the chevron that
  /// promises exactly that, per R-33-072.1, drawn from the app icon set per
  /// R-32-401; Android carries no trailing decoration, because a chevron
  /// there promises nothing, per
  /// R-33-072.3. [trailing] marks one row among its siblings, such as the
  /// `This phone` of `docs/31-mockups/14-devices.md` (R-03-105), or holds
  /// the in-place spinner of a row whose action is in flight: on iOS it
  /// takes the tile's own `additionalInfo` slot, where the platform puts a
  /// row's secondary value before the chevron; on Android the trailing
  /// slot of section 7.4 (added 2026-09-09).
  const ChromeListRow.push({
    super.key,
    required this.title,
    this.subtitle,
    Widget? trailing,
    required this.onTap,
    this.showDivider = true,
  }) : _kind = _RowKind.push,
       _trailingLabel = null,
       // ignore: prefer_initializing_formals
       _trailing = trailing,
       _child = null,
       _value = false,
       _onChanged = null;

  /// Opens a sheet or a single-choice screen. Both platforms replace the
  /// chevron with the current value, per R-33-072.2 and R-33-072.3.
  const ChromeListRow.choice({
    super.key,
    required this.title,
    required String valueLabel,
    required this.onTap,
    this.showDivider = true,
  }) : _kind = _RowKind.choice,
       subtitle = null,
       _trailingLabel = valueLabel,
       _trailing = null,
       _child = null,
       _value = false,
       _onChanged = null;

  /// Expands in place. iOS uses [CupertinoExpansionTile], whose own arrow
  /// states that the content opens in place, per R-33-072.2.
  const ChromeListRow.expand({
    super.key,
    required this.title,
    required Widget child,
  }) : _kind = _RowKind.expand,
       subtitle = null,
       onTap = null,
       showDivider = true,
       _trailingLabel = null,
       _trailing = null,
       // ignore: prefer_initializing_formals
       _child = child,
       _value = false,
       _onChanged = null;

  /// Flips one switch. iOS trails a [CupertinoSwitch], the control Apple
  /// puts on a settings row; Android is the switch row of R-32-522: the
  /// row is the one semantics node and reads `<title>, on` or
  /// `<title>, off` (R-32-505), the Material [Switch] inside it is
  /// decoration with no node and no pointer of its own, and a tap on the
  /// row flips the value. `null` [onChanged] disables the row.
  const ChromeListRow.toggle({
    super.key,
    required this.title,
    this.subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
    this.showDivider = true,
  }) : _kind = _RowKind.toggle,
       onTap = null,
       _trailingLabel = null,
       _trailing = null,
       _child = null,
       // ignore: prefer_initializing_formals
       _value = value,
       // ignore: prefer_initializing_formals
       _onChanged = onChanged;

  /// Runs one action named by a trailing labelled control such as `Edit`,
  /// per R-33-072.2 and R-33-072.3, in `type.label` `color.accent.text`
  /// on both platforms.
  const ChromeListRow.action({
    super.key,
    required this.title,
    this.subtitle,
    required String actionLabel,
    required this.onTap,
    this.showDivider = true,
  }) : _kind = _RowKind.action,
       _trailingLabel = actionLabel,
       _trailing = null,
       _child = null,
       _value = false,
       _onChanged = null;

  /// The destructive form of [ChromeListRow.action] (added 2026-09-09, per
  /// R-03-105: the three remove actions of `docs/31-mockups/14-devices.md`
  /// are platform rows in their own section). The row's own title names the
  /// action, so it trails no control; the hue lives in the leading glyph
  /// alone, `delete_outline` at `size.icon.md` in `color.status.error`,
  /// while the title keeps the row's normal ink, per R-32-527 and R-30-143,
  /// and no bar, per R-03-058. `null` [onTap] disables the row at
  /// `opacity.disabled` on both platforms, per R-32-502. The one semantics
  /// node reads `<title>, destructive` (R-32-505) and exposes `disabled`
  /// while [onTap] is null.
  const ChromeListRow.destructive({
    super.key,
    required this.title,
    required this.onTap,
    this.showDivider = true,
  }) : _kind = _RowKind.destructive,
       subtitle = null,
       _trailingLabel = null,
       _trailing = null,
       _child = null,
       _value = false,
       _onChanged = null;

  /// Information, not a control: no tap, no press fill, and on Android no
  /// `opacity.disabled`, because a row that was never tappable is not
  /// disabled (R-32-502, `docs/31-mockups/19-about.md` callouts 2 and 3).
  const ChromeListRow.static({
    super.key,
    required this.title,
    this.subtitle,
    Widget? trailing,
    this.showDivider = true,
  }) : _kind = _RowKind.static,
       onTap = null,
       _trailingLabel = null,
       // ignore: prefer_initializing_formals
       _trailing = trailing,
       _child = null,
       _value = false,
       _onChanged = null;

  /// The row's own label. On Android it is the `type.body.strong` primary
  /// line of section 7.4; on iOS the tile draws it in the platform's type.
  final String title;

  /// The line under [title]. On Android it is the `type.caption` secondary
  /// line of section 7.4, which selects `size.row.two_line`; on iOS the
  /// tile's own subtitle slot.
  final String? subtitle;

  /// Called when a push, choice, action or destructive row is tapped.
  /// `null` for the other kinds, which act through their own control or
  /// not at all, and for a disabled destructive row.
  final VoidCallback? onTap;

  /// Android only: whether the row draws its own bottom divider. The last
  /// row of a section passes false, per section 7.4. On iOS the
  /// `CupertinoListSection` of R-33-073 draws the one separator between
  /// rows, so no row draws one and this flag is not read.
  final bool showDivider;

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
    switch (_kind) {
      case _RowKind.push:
        return _isIos
            ? CupertinoListTile(
                title: titleText,
                subtitle: subtitleText,
                additionalInfo: _trailing,
                // The trailing chevron of section 7.4 (`chevron_right`,
                // `size.icon.md`, `color.fg.secondary`) from the one icon set
                // of R-32-401, not `CupertinoListTileChevron`: that widget
                // draws from the cupertino_icons font, which this app does
                // not bundle, so it rendered a tofu box (2026-09-08).
                trailing: Icon(
                  Symbols.chevron_right_rounded,
                  size: AppSize.iconMd,
                  color: color.fgSecondary,
                ),
                onTap: onTap,
              )
            : AppListRow(
                primary: title,
                secondary: subtitle,
                trailing: _trailing,
                onTap: onTap,
                showDivider: showDivider,
              );
      case _RowKind.choice:
        final Widget value = Text(
          _trailingLabel!,
          style: AppType.body.copyWith(color: color.fgSecondary),
        );
        return _isIos
            ? CupertinoListTile(title: titleText, trailing: value, onTap: onTap)
            : AppListRow(
                primary: title,
                trailing: value,
                onTap: onTap,
                showDivider: showDivider,
              );
      case _RowKind.expand:
        return _isIos
            ? CupertinoExpansionTile(title: titleText, child: _child!)
            : ExpansionTile(title: titleText, children: <Widget>[_child!]);
      case _RowKind.toggle:
        final ValueChanged<bool>? onChanged = _onChanged;
        return _isIos
            ? CupertinoListTile(
                title: titleText,
                subtitle: subtitleText,
                // The switch row of section 7.7 in the Herdr palette, not
                // Apple's system green: track on `color.accent.primary`,
                // track off `color.bg.high` with `border.hairline` in
                // `color.border.strong` (R-32-522: the off track is
                // invisible without it), thumb `color.fg.on_accent` on and
                // `color.fg.primary` off.
                trailing: CupertinoSwitch(
                  value: _value,
                  onChanged: onChanged,
                  activeTrackColor: color.accentPrimary,
                  inactiveTrackColor: color.bgHigh,
                  thumbColor: color.fgOnAccent,
                  inactiveThumbColor: color.fgPrimary,
                  trackOutlineColor: WidgetStateProperty.resolveWith<Color?>(
                    (Set<WidgetState> states) =>
                        states.contains(WidgetState.selected)
                        ? null
                        : color.borderStrong,
                  ),
                  trackOutlineWidth: const WidgetStatePropertyAll<double>(
                    AppBorder.hairline,
                  ),
                ),
              )
            : AppListRow(
                primary: title,
                secondary: subtitle,
                semanticsValue: _value ? 'on' : 'off',
                trailing: ExcludeSemantics(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: onChanged == null ? _opacityDisabled : 1,
                      child: Material(
                        type: MaterialType.transparency,
                        child: Switch(value: _value, onChanged: onChanged),
                      ),
                    ),
                  ),
                ),
                onTap: onChanged == null ? null : () => onChanged(!_value),
                showDivider: showDivider,
              );
      case _RowKind.action:
        final Widget label = Text(
          _trailingLabel!,
          style: AppType.label.copyWith(color: color.accentText),
        );
        return _isIos
            ? CupertinoListTile(
                title: titleText,
                subtitle: subtitleText,
                trailing: label,
                onTap: onTap,
              )
            : AppListRow(
                primary: title,
                secondary: subtitle,
                trailing: label,
                onTap: onTap,
                showDivider: showDivider,
              );
      case _RowKind.destructive:
        final bool enabled = onTap != null;
        final Widget glyph = Icon(
          Symbols.delete_outline_rounded,
          size: AppSize.iconMd,
          color: color.statusError,
        );
        // `AppListRow` dims itself at `opacity.disabled` when it has no tap;
        // the Cupertino tile has no disabled look of its own, so the iOS
        // branch dims the whole tile the same way (R-32-502).
        final Widget row = _isIos
            ? Opacity(
                opacity: enabled ? 1 : _opacityDisabled,
                child: CupertinoListTile(
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
              );
        return MergeSemantics(
          child: Semantics(hint: 'destructive', enabled: enabled, child: row),
        );
      case _RowKind.static:
        return _isIos
            ? CupertinoListTile(
                title: titleText,
                subtitle: subtitleText,
                trailing: _trailing,
              )
            : AppListRow(
                primary: title,
                secondary: subtitle,
                trailing: _trailing,
                isStatic: true,
                showDivider: showDivider,
              );
    }
  }
}
