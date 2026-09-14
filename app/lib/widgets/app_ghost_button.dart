/// The one ghost button, per `docs/32-design-language.md` section 7.28
/// (R-32-591) and `docs/03-product-decisions.md` R-03-059: the platform's
/// own secondary button, `OutlinedButton` on Android and
/// `CupertinoButton.tinted` on iOS, and the only file that builds either.
/// It replaces every secondary/outlined button use and mirrors
/// `AppFilledButton`'s API.
///
/// Every value reaches the button through the theme `app.dart` builds:
/// `outlinedButtonTheme` on Android (height, radius, inset, type, ink, the
/// `border.strong` side, the `color.accent.soft` wash under a
/// `color.accent.primary` side while pressed, the disabled dim of
/// R-32-502), `CupertinoThemeData.primaryColor` and
/// `textTheme.actionTextStyle` on iOS. iOS has no outlined idiom; the
/// tinted button is its bordered secondary button, and it keeps the
/// component's own tint, size and corner, as section 7.28 records. Its
/// label is the one exception: `color.accent.primary` measures 3.6 on the
/// tinted fill over `bg.raised` in light, under the 4.5 of R-32-124, so
/// the widget hands the button `color.accent.text` as `foregroundColor`,
/// as the key cap and `app_text_button.dart` do (2026-09-09).
library;

import 'package:cupertino_ui/cupertino_ui.dart'
    show
        CupertinoButton,
        CupertinoTheme,
        kCupertinoButtonTintedOpacityDark,
        kCupertinoButtonTintedOpacityLight;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart'
    show
        Brightness,
        BuildContext,
        Color,
        DefaultTextStyle,
        Opacity,
        SizedBox,
        StatelessWidget,
        Text,
        VoidCallback,
        Widget;
import 'package:material_ui/material_ui.dart'
    show CircularProgressIndicator, OutlinedButton;

import 'theme/app_color.dart';
import 'theme/app_size.dart';

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

/// `opacity.disabled`, per the opacity table beside R-32-330, for iOS
/// only. `cupertino_ui` 1.0.1 recolours a disabled button to a system
/// grey, the second signal R-32-331 forbids, so on iOS the widget hands
/// the button its own tint back as `disabledColor`, fixes the ink, and dims
/// the whole control itself, as `ChromeIconAction` does. Android takes the
/// dim from `outlinedButtonTheme`.
const double _opacityDisabled = 0.38;

/// The spinner stroke, the one width the in-place spinner takes.
const double _spinnerStroke = 2;

/// The ghost button of `docs/32-design-language.md` section 7.28: full
/// available width unless [fullWidth] is false. The label is the platform's
/// own, sentence case in the interface font, per R-03-104 and R-32-212
/// (2026-09-09: until then `type.mono.button` UPPER), drawn and spoken as
/// written. [isLoading] replaces the label with a `size.spinner` indicator
/// in the label's ink, and the control is not pressable meanwhile.
///
/// Pressed, focused and disabled are the platform's own responses
/// (amended 2026-09-09 per R-03-059). This control raises no error state,
/// per R-32-500's own carve-out.
///
/// [onPressed] fires no haptic itself: R-32-501 assigns the haptic per
/// **control**, so a caller fires its own `AppHaptic` token from
/// [onPressed].
class AppGhostButton extends StatelessWidget {
  const AppGhostButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.fullWidth = true,
  });

  /// The button's label, drawn and spoken as written.
  final String label;

  /// `null` renders the disabled state: the same colours at
  /// `opacity.disabled`.
  final VoidCallback? onPressed;

  /// Replaces [label] with a `size.spinner` indicator while an action is
  /// in flight. The control is not pressable meanwhile.
  final bool isLoading;

  /// Whether the button fills the available width. False lets it sit
  /// beside another control in a row.
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final VoidCallback? onTap = isLoading ? null : onPressed;
    final Widget child = isLoading ? const _Spinner() : Text(label);

    Widget button;
    if (_isIos) {
      final Color primary = CupertinoTheme.of(context).primaryColor;
      button = Opacity(
        opacity: onTap == null ? _opacityDisabled : 1,
        child: CupertinoButton.tinted(
          onPressed: onTap,
          foregroundColor: AppColor.of(context).accentText,
          disabledColor: primary.withValues(
            alpha: CupertinoTheme.brightnessOf(context) == Brightness.light
                ? kCupertinoButtonTintedOpacityLight
                : kCupertinoButtonTintedOpacityDark,
          ),
          child: child,
        ),
      );
    } else {
      button = OutlinedButton(onPressed: onTap, child: child);
    }

    if (fullWidth) {
      button = SizedBox(width: double.infinity, child: button);
    }
    return button;
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
