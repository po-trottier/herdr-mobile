/// The ground grid of `docs/32-design-language.md` R-32-332 (amended
/// 2026-09-09, per R-03-107): 1 px lines in `color.bg.grid` on a 40 px pitch
/// over `color.bg.base`, the ground of every non-terminal screen. Content sits
/// on it as the opaque paper of `app_ground.dart`. Never painted inside a card,
/// a sheet, a strip or the terminal. Lines align to this widget's top-left
/// corner, so a screen places it inside its safe area. It is texture:
/// contrast-exempt, and no meaning may rely on it.
library;

import 'package:flutter/widgets.dart'
    show
        BuildContext,
        Canvas,
        Color,
        CustomPaint,
        CustomPainter,
        Offset,
        Paint,
        PaintingStyle,
        RepaintBoundary,
        Size,
        StatelessWidget,
        Widget;

import 'theme/app_color.dart';

/// The grid pitch in logical pixels, R-32-332.
const double groundGridPitch = 40;

class _GroundGridPainter extends CustomPainter {
  const _GroundGridPainter({required this.ground, required this.line});

  final Color ground;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = ground);
    final Paint stroke = Paint()
      ..color = line
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    // A half-pixel offset centres a 1 px stroke on the pixel row, so the line
    // stays crisp instead of blurring over two rows.
    for (double x = 0.5; x <= size.width; x += groundGridPitch) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), stroke);
    }
    for (double y = 0.5; y <= size.height; y += groundGridPitch) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _GroundGridPainter oldDelegate) =>
      oldDelegate.ground != ground || oldDelegate.line != line;
}

/// Paints the ground grid under [child]. The grid sits in its own
/// `RepaintBoundary`, so a change inside [child] does not repaint it.
class GroundGrid extends StatelessWidget {
  const GroundGrid({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    return RepaintBoundary(
      child: CustomPaint(
        painter: _GroundGridPainter(ground: color.bgBase, line: color.bgGrid),
        child: child,
      ),
    );
  }
}
