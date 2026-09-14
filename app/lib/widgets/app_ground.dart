/// The one piece an empty state lays on the ground grid, per
/// `docs/03-product-decisions.md` R-03-107 (amended 2026-09-09) and
/// `docs/32-design-language.md` R-32-332: the grid is the ground of a screen
/// that has no content, the hero screens and the empty state of a list, and a
/// screen with content paints plain `color.bg.base`. `GroundGrid`
/// (`ground_grid.dart`) paints the grid; this file holds [EmptyMark], the
/// brand silhouette in `color.bg.grid` ink behind an empty state, anchored
/// bottom-right like the welcome hero (`R-32-594`), contrast-exempt and
/// excluded from semantics. An empty body is `GroundGrid(EmptyMark(block))`.
///
/// `PaperSliver` and `GroundRemainder`, the paper-on-grid pieces of the first
/// R-03-107 (every list a paper block on the grid), left with the amendment:
/// no screen lays paper any more. The terminal grid never takes any of this
/// (`R-30-272`, `R-33-055`).
library;

import 'package:flutter/widgets.dart'
    show
        BuildContext,
        LayoutBuilder,
        Positioned,
        Stack,
        StackFit,
        StatelessWidget,
        Widget;

import 'brand_mark.dart' show BrandMark;
import 'theme/app_color.dart' show AppColor;

/// The brand silhouette in `color.bg.grid` ink behind [child]: 60% of the
/// width, its right crop flush with the right edge and its bottom crop on the
/// bottom edge, the same anchoring as the welcome hero.
class EmptyMark extends StatelessWidget {
  const EmptyMark({super.key, required this.child});

  final Widget child;

  /// The mark's width as a share of the available width.
  static const double widthShare = 0.6;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, constraints) => Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Positioned(
            right: 0,
            bottom: 0,
            child: BrandMark(
              height: constraints.maxWidth * widthShare,
              color: color.bgGrid,
            ),
          ),
          child,
        ],
      ),
    );
  }
}
