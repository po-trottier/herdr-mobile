import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoListTile;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart'
    show ListTile, Material, MaterialType;

import 'app_size.dart';
import 'app_space.dart';

/// A destination strip uses the platform's own row.
class ChromeStripAction extends StatelessWidget {
  const ChromeStripAction({
    super.key,
    required this.child,
    required this.onTap,
  });

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return defaultTargetPlatform == TargetPlatform.iOS
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppSize.targetMin),
                child: CupertinoListTile(
                  leadingSize: 0,
                  title: Builder(
                    builder: (context) => DefaultTextStyle(
                      style: DefaultTextStyle.of(context).style,
                      softWrap: true,
                      overflow: TextOverflow.visible,
                      child: child,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.space4,
                    vertical: AppSpace.space3,
                  ),
                  onTap: onTap,
                ),
              ),
            ],
          )
        : Material(
            type: MaterialType.transparency,
            child: ListTile(
              title: child,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpace.space4,
              ),
              minVerticalPadding: AppSpace.space3,
              minTileHeight: AppSize.targetMin,
              onTap: onTap,
            ),
          );
  }
}
