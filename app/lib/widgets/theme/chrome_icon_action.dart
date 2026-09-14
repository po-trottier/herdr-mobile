/// An icon action in the app bar, per `docs/33-platform-chrome.md`
/// R-33-033's `App bar action` row and R-33-076: on Android a Material
/// `IconButton` with its tooltip, on iOS a `CupertinoButton` at least
/// `size.target.min` wide that fills the bar's own height. Both are
/// focusable platform controls, so keyboard focus and activation hold
/// (`R-30-718`); a bare gesture box is not a substitute.
///
/// The glyph is `size.icon.lg` in `color.fg.primary` by default, per the
/// app bar table of `docs/32-design-language.md` section 7.3 and R-32-405;
/// [label] is the spoken name of the action, per R-32-505's icon-only
/// pattern, and on Android also its tooltip.
library;

import 'package:cupertino_ui/cupertino_ui.dart'
    show
        BuildContext,
        Color,
        CupertinoButton,
        EdgeInsets,
        Icon,
        IconData,
        Opacity,
        SizedBox,
        StatelessWidget,
        VoidCallback,
        Widget;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:material_ui/material_ui.dart' show IconButton;

import 'app_color.dart';
import 'app_size.dart';

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

/// `opacity.disabled`, per the opacity table beside R-32-330: the whole
/// control while disabled, per R-32-502, with no colour change, per
/// R-32-331. Both platform buttons would recolour the glyph instead, so
/// this widget keeps the ink and dims the control itself; a caller MUST
/// NOT wrap it in a second `Opacity`.
const double _opacityDisabled = 0.38;

class ChromeIconAction extends StatelessWidget {
  const ChromeIconAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });

  /// A glyph from the map of R-32-401.
  final IconData icon;

  /// The action name alone, for example `Pane actions`, per R-32-505.
  final String label;

  /// `null` renders the platform's own disabled state.
  final VoidCallback? onPressed;

  /// The glyph's ink. `null` is `color.fg.primary`, per R-32-405.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Color ink = color ?? AppColor.of(context).fgPrimary;
    final Widget control = _isIos
        ? SizedBox(
            width: AppSize.targetMin,
            height: AppSize.appBarIos,
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: onPressed,
              child: Icon(
                icon,
                size: AppSize.iconLg,
                color: ink,
                semanticLabel: label,
                fill: 0,
                weight: 400,
                grade: 0,
              ),
            ),
          )
        : IconButton(
            icon: Icon(
              icon,
              size: AppSize.iconLg,
              semanticLabel: label,
              fill: 0,
              weight: 400,
              grade: 0,
            ),
            color: ink,
            disabledColor: ink,
            tooltip: label,
            onPressed: onPressed,
          );
    return Opacity(
      opacity: onPressed == null ? _opacityDisabled : 1,
      child: control,
    );
  }
}
