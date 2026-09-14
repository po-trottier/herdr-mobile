/// The one filled button, per `docs/32-design-language.md` section 7.8
/// (R-32-525) and `docs/03-product-decisions.md` R-03-059: the platform's
/// own button, `FilledButton` on Android and `CupertinoButton.filled` on
/// iOS, and the only file that builds either. A screen MUST NOT build a
/// second filled-button widget, per R-30-121.
///
/// Every value reaches the button through the theme `app.dart` builds and
/// nothing else: `filledButtonTheme` on Android (height, radius, inset,
/// type, fill, ink, the pressed overlay of R-32-501 and the disabled dim
/// of R-32-502), `CupertinoThemeData.primaryColor`,
/// `primaryContrastingColor` and `textTheme.actionTextStyle` on iOS. This
/// file sets no colour, size, radius or type of its own.
library;

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoButton, CupertinoTheme;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart'
    show
        BuildContext,
        DefaultTextStyle,
        Opacity,
        SizedBox,
        StatelessWidget,
        Text,
        VoidCallback,
        Widget;
import 'package:material_ui/material_ui.dart'
    show CircularProgressIndicator, FilledButton;

import 'theme/app_size.dart';

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

/// `opacity.disabled`, per the opacity table beside R-32-330, for iOS
/// only. `cupertino_ui` 1.0.1 recolours a disabled button to a system
/// grey, the second signal R-32-331 forbids, so on iOS the widget hands
/// the button its own fill back as `disabledColor` and dims the whole
/// control itself, as `ChromeIconAction` does. Android takes the dim from
/// `filledButtonTheme`. Every opacity stays a local constant beside its
/// one caller, per the border-width precedent of `app_elev.dart`.
const double _opacityDisabled = 0.38;

/// The spinner stroke, the one width the in-place spinner takes.
const double _spinnerStroke = 2;

/// The primary button of `docs/32-design-language.md` section 7.8, full
/// available width. The label is the platform's own, sentence case in the
/// interface font, per R-03-104 and R-32-212 (2026-09-09: until then
/// `type.mono.button` UPPER), drawn and spoken as written. [isLoading]
/// replaces the label with a `size.spinner` indicator in the label's own
/// ink, per the anatomy table's `Loading` row, and the control is not
/// pressable meanwhile.
///
/// Pressed, focused and disabled are the platform's own responses
/// (R-32-501, R-32-503, R-32-502, amended 2026-09-09 per R-03-059): the
/// Material ink overlay and the Cupertino press fade. This control raises
/// no error state, per R-32-500's own carve-out.
///
/// [onPressed] fires no haptic itself: R-32-501 assigns the haptic per
/// **control**, which `docs/30-ux-spec.md` fixes screen by screen, so a
/// caller fires its own `AppHaptic` token from [onPressed].
class AppFilledButton extends StatelessWidget {
  const AppFilledButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  /// The button's label, drawn and spoken as written.
  final String label;

  /// `null` renders the disabled state: the same colours at
  /// `opacity.disabled`.
  final VoidCallback? onPressed;

  /// Replaces [label] with a `size.spinner` indicator while an action is
  /// in flight. The control is not pressable meanwhile.
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final VoidCallback? onTap = isLoading ? null : onPressed;
    final Widget child = isLoading ? const _Spinner() : Text(label);
    if (_isIos) {
      return Opacity(
        opacity: onTap == null ? _opacityDisabled : 1,
        child: SizedBox(
          width: double.infinity,
          child: CupertinoButton.filled(
            onPressed: onTap,
            disabledColor: CupertinoTheme.of(context).primaryColor,
            child: child,
          ),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: FilledButton(onPressed: onTap, child: child),
    );
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
