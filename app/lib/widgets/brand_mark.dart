/// BrandMark widget per `docs/32-design-language.md` section 8 (R-32-580):
/// Renders `assets/brand/ram.png` with `color:` and `colorBlendMode:
/// BlendMode.srcIn`, `fit: BoxFit.contain`, `filterQuality:
/// FilterQuality.low` (bilinear, no mipmaps: with `medium` the Android renderer drew a
/// 1 px line along the top of the mark, measured on the emulator 2026-09-03; R-32-426),
/// `excludeFromSemantics: true`. Height and colour
/// are configurable.
library;

import 'package:flutter/widgets.dart'
    show
        BlendMode,
        BoxFit,
        BuildContext,
        Color,
        FilterQuality,
        Image,
        StatelessWidget,
        Widget;

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.height = 96, this.color});

  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/brand/ram.png',
      height: height,
      color: color,
      colorBlendMode: BlendMode.srcIn,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.low,
      excludeFromSemantics: true,
    );
  }
}
