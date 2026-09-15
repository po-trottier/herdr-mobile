import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoButton;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show FilledButton;

import 'app_color.dart';
import 'app_radius.dart';
import 'app_size.dart';
import 'app_space.dart';

/// A tonal action with the platform's own button.
class ChromeTonalButton extends StatelessWidget {
  const ChromeTonalButton({
    super.key,
    required this.child,
    this.onPressed,
    this.icon,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final Widget? glyph = icon == null
        ? null
        : Icon(icon, size: AppSize.iconMd, fill: 0, weight: 400, grade: 0);
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // R-33-015/R-33-060: an opaque surface backs the native tint.
      return DecoratedBox(
        decoration: BoxDecoration(
          color: AppColor.of(context).bgHigh,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: CupertinoButton.tinted(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.space3,
            vertical: AppSpace.space2,
          ),
          minimumSize: const Size(AppSize.targetMin, AppSize.targetMin),
          borderRadius: BorderRadius.circular(AppRadius.full),
          color: AppColor.of(context).bgHigh,
          foregroundColor: AppColor.of(context).fgPrimary,
          onPressed: onPressed,
          child: glyph == null
              ? child
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    glyph,
                    const SizedBox(width: AppSpace.space1),
                    child,
                  ],
                ),
        ),
      );
    }
    return glyph == null
        ? FilledButton.tonal(onPressed: onPressed, child: child)
        : FilledButton.tonalIcon(
            onPressed: onPressed,
            icon: glyph,
            label: child,
          );
  }
}
