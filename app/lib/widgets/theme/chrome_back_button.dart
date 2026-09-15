import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoNavigationBarBackButton;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show BackButton;

import 'app_color.dart';

/// A native back control returns within a sheet without a route pop (R-33-070).
class ChromeBackButton extends StatelessWidget {
  const ChromeBackButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  /// The disabled opacity from R-32-330.
  static const double _disabledOpacity = 0.38;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    final Color color = AppColor.of(context).fgPrimary;
    final Widget control = defaultTargetPlatform == TargetPlatform.iOS
        ? CupertinoNavigationBarBackButton(onPressed: onPressed, color: color)
        : BackButton(onPressed: onPressed, color: color);
    return Semantics(
      label: 'Back',
      button: true,
      enabled: enabled,
      onTap: onPressed,
      excludeSemantics: true,
      child: ExcludeFocus(
        excluding: !enabled,
        child: IgnorePointer(
          ignoring: !enabled,
          child: Opacity(
            opacity: enabled ? 1 : _disabledOpacity,
            child: control,
          ),
        ),
      ),
    );
  }
}
