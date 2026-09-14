/// Elevation tokens from `docs/32-design-language.md` section 5.3.
/// R-32-320 fixes the closed list of layers permitted a shadow, and
/// R-32-321 fixes the shadow colour as `color.shadow`, never pure black.
/// `docs/30-ux-spec.md` R-30-101 fixes the Dart naming: `elev.2` becomes
/// `AppElev.elev2`.
library;

import 'package:flutter/widgets.dart'
    show Border, BoxDecoration, BoxShadow, Brightness, Offset;

import 'app_color.dart';

/// `border.hairline`, per `docs/32-design-language.md` R-32-330: the
/// width of `elev.1`'s border. Every other border width stays a local
/// constant beside its one caller, per the precedent
/// `app/lib/widgets/treatments.dart` (`WP-12-a`) set for
/// `border.attention`; `elev.1`'s border is this file's one use of the
/// hairline width, so it is named here rather than duplicated.
const double _borderHairlineWidth = 1;

const double _shadowOffsetY2 = 2;
const double _shadowBlur2 = 8;
const double _shadowAlphaDark2 = 0.40;
const double _shadowAlphaLight2 = 0.12;

const double _shadowOffsetY3 = 8;
const double _shadowBlur3 = 24;
const double _shadowAlphaDark3 = 0.48;
const double _shadowAlphaLight3 = 0.16;

/// The four elevation compositions, each a [BoxDecoration] a caller
/// applies to the layer's own container. Separation MUST come from
/// [elev1] first, per R-30-260; a shadow is permitted only on the closed
/// list of floating layers R-32-320 names.
class AppElev {
  const AppElev._();

  /// `elev.0`. No border and no shadow.
  static const BoxDecoration elev0 = BoxDecoration();

  /// `elev.1`. A 1 wide border in `color.border.strong`, no shadow.
  static BoxDecoration elev1(AppColor color) => BoxDecoration(
    border: Border.all(color: color.borderStrong, width: _borderHairlineWidth),
  );

  /// `elev.2`. Offset y 2, blur 8, spread 0, `color.shadow` at 40 percent
  /// in dark and 12 percent in light. A bottom sheet and a dialog are
  /// `elev.3`; an autocomplete list and the create control of R-32-588
  /// are the only `elev.2` layers, per R-32-320.
  static BoxDecoration elev2(AppColor color) => BoxDecoration(
    boxShadow: <BoxShadow>[
      BoxShadow(
        color: color.shadow.withValues(
          alpha: color.brightness == Brightness.dark
              ? _shadowAlphaDark2
              : _shadowAlphaLight2,
        ),
        offset: const Offset(0, _shadowOffsetY2),
        blurRadius: _shadowBlur2,
      ),
    ],
  );

  /// `elev.3`. Offset y 8, blur 24, spread 0, `color.shadow` at 48
  /// percent in dark and 16 percent in light. A bottom sheet and a
  /// dialog, per R-32-320.
  static BoxDecoration elev3(AppColor color) => BoxDecoration(
    boxShadow: <BoxShadow>[
      BoxShadow(
        color: color.shadow.withValues(
          alpha: color.brightness == Brightness.dark
              ? _shadowAlphaDark3
              : _shadowAlphaLight3,
        ),
        offset: const Offset(0, _shadowOffsetY3),
        blurRadius: _shadowBlur3,
      ),
    ],
  );
}
