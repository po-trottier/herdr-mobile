/// The one text button, per `docs/32-design-language.md` section 7.8
/// (R-32-526) and `docs/03-product-decisions.md` R-03-059: the platform's
/// own button, `TextButton` on Android and a plain `CupertinoButton` on
/// iOS, and the only file that builds either for a text action.
///
/// Every value reaches the button through the theme `app.dart` builds:
/// `textButtonTheme` on Android (ink, glyph size, the `color.accent.soft`
/// wash of R-32-526 and the disabled dim of R-32-502),
/// `textTheme.actionTextStyle` on iOS. The label type is the platform's
/// own, per `docs/03-product-decisions.md` R-03-104 (2026-09-09): Material
/// 3's `labelLarge` and the Cupertino action style, in the interface family
/// the theme sets, drawn as written. One iOS exception is
/// recorded in R-32-526: `cupertino_ui` 1.0.1 inks a plain button in
/// `CupertinoThemeData.primaryColor`, the fill token `color.accent.primary`,
/// which R-32-124 does not clear as text on `color.bg.raised`, so this file
/// hands the platform widget `color.accent.text` as its `foregroundColor`.
library;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoButton;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart'
    show
        BuildContext,
        Color,
        DefaultTextStyle,
        Icon,
        IconData,
        MainAxisSize,
        Opacity,
        Row,
        SizedBox,
        StatelessWidget,
        Text,
        VoidCallback,
        Widget;
import 'package:material_ui/material_ui.dart'
    show CircularProgressIndicator, TextButton;

import 'theme/app_color.dart';
import 'theme/app_size.dart';
import 'theme/app_space.dart';
import 'theme/app_type.dart';

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

/// `opacity.disabled`, per the opacity table beside R-32-330. On iOS
/// `cupertino_ui` 1.0.1 recolours a disabled button's ink to a system grey,
/// the second signal R-32-331 forbids, so the widget fixes the ink and dims
/// the whole control itself, as `ChromeIconAction` does. On Android the
/// theme's disabled colours dim the button's own ink; the subdued label and
/// the destructive glyph are inked by the widget, so it dims them by the
/// same value, and the whole control dims as one.
const double _opacityDisabled = 0.38;

/// The spinner stroke, the one width the in-place spinner takes.
const double _spinnerStroke = 2;

/// A text-only action, per R-32-526: the platform's own label, sentence
/// case in the interface font (R-03-104), in `color.accent.text`, at the
/// platform's own height, no fill, spoken as written (R-32-213).
/// [isLoading] replaces the label with a `size.spinner` indicator in the
/// label's ink, like `AppFilledButton`, and the control is not pressable
/// meanwhile. Pressed, focused and disabled are the platform's own
/// responses (amended 2026-09-09 per R-03-059). This control raises no
/// error state, per R-32-500's own carve-out.
///
/// Like `AppFilledButton`, this widget fires no haptic itself: a caller
/// fires its own `AppHaptic` token from [onPressed], per R-32-501.
class AppTextButton extends StatelessWidget {
  const AppTextButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.subdued = false,
    this.icon,
    this.destructive = false,
  });

  /// The button's label, drawn and spoken as written, per R-03-104
  /// (2026-09-09: until then the widget upper-cased the drawn form).
  final String label;

  /// `null` renders the disabled state at `opacity.disabled`.
  final VoidCallback? onPressed;

  /// Replaces [label] with a `size.spinner` indicator while an action is
  /// in flight. The control is not pressable meanwhile.
  final bool isLoading;

  /// Uses title-case `type.body.strong` in `color.fg.secondary` for the
  /// quiet sheet action of R-32-526, the `Cancel` row of section 7.16.
  final bool subdued;

  /// A glyph of the R-32-401 map before the label, at the theme's
  /// `size.icon.md`: `TextButton.icon` on Android, the same row inside the
  /// Cupertino button on iOS.
  final IconData? icon;

  /// The `treat.destructive` composition of R-32-506 and R-32-527 on a
  /// button: the glyph in `color.status.error`, the label in the button's
  /// own ink, the same ink its neighbour takes (2026-09-09, per R-03-104;
  /// until then the label took `color.fg.primary`). The hue lives in the
  /// glyph alone, never in the text, and no `border.attention` bar (per
  /// R-03-058).
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final VoidCallback? onTap = isLoading ? null : onPressed;
    // Content the widget inks itself dims with the button, per R-32-502. On
    // iOS the `Opacity` below dims the whole control, content included.
    final bool dimContent = onTap == null && !_isIos;
    Color ink(Color token) =>
        dimContent ? token.withValues(alpha: _opacityDisabled) : token;

    // The label takes the `DefaultTextStyle` the platform button sets from
    // the theme; only the subdued form carries its own ink and type.
    final Widget text = isLoading
        ? const _Spinner()
        : subdued
        ? Text(
            label,
            style: AppType.bodyStrong.copyWith(
              color: ink(color.fgSecondary),
              inherit: false,
            ),
          )
        : Text(label);

    final Widget? glyph = icon == null
        ? null
        : Icon(icon, color: destructive ? ink(color.statusError) : null);

    if (_isIos) {
      return Opacity(
        opacity: onTap == null ? _opacityDisabled : 1,
        child: CupertinoButton(
          onPressed: onTap,
          foregroundColor: color.accentText,
          child: glyph == null
              ? text
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    glyph,
                    const SizedBox(width: AppSpace.space2),
                    text,
                  ],
                ),
        ),
      );
    }
    return TextButton.icon(onPressed: onTap, icon: glyph, label: text);
  }
}

/// The `size.spinner` indicator that takes the label's place, in the
/// label's own ink: the `DefaultTextStyle` the platform button sets from
/// the theme.
class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: AppSize.spinner,
    height: AppSize.spinner,
    child: CircularProgressIndicator(
      strokeWidth: _spinnerStroke,
      color: DefaultTextStyle.of(context).style.color,
    ),
  );
}
