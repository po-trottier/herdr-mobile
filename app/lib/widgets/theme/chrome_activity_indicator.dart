import 'package:cupertino_ui/cupertino_ui.dart'
    show
        BuildContext,
        Color,
        CupertinoActivityIndicator,
        SizedBox,
        StatelessWidget,
        Widget;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:material_ui/material_ui.dart' show CircularProgressIndicator;

import 'app_size.dart';

/// The platform activity indicator uses the requested square size.
class ChromeActivityIndicator extends StatelessWidget {
  const ChromeActivityIndicator({
    super.key,
    this.size = AppSize.spinner,
    this.color,
  });

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: defaultTargetPlatform == TargetPlatform.iOS
        ? CupertinoActivityIndicator(radius: size / 2, color: color)
        : CircularProgressIndicator(strokeWidth: 2, color: color),
  );
}
