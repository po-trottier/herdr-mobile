/// A menu that opens from a control, per `docs/33-platform-chrome.md`
/// R-33-033's `Menu from a control` row: on Android a Material `MenuAnchor`
/// with one `MenuItemButton` per choice, its glyph leading; on iOS the
/// platform's pull-down menu, `CupertinoMenuAnchor` with one
/// `CupertinoMenuItem` per choice, its glyph in the trailing slot the way
/// an SF Symbol sits in a system menu. Both anchor to the control that
/// opened them and close on a choice.
///
/// A destructive choice takes the platform's own role: `isDestructiveAction`
/// on iOS, and the `color.status.error` glyph and label on Android. Both
/// announce `destructive`, per R-30-141.
library;

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoMenuAnchor, CupertinoMenuItem;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show MenuAnchor, MenuItemButton;

import 'app_color.dart';
import 'app_size.dart';
import 'app_type.dart';

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

/// One choice of a [ChromeMenuAnchor]. [onSelected] `null` renders the
/// platform's own disabled state.
class ChromeMenuItem {
  const ChromeMenuItem({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.destructive = false,
  });

  final String label;

  /// A glyph from the map of R-32-401.
  final IconData icon;
  final VoidCallback? onSelected;
  final bool destructive;
}

/// The control that opens the menu. Call `controller.open()` from its
/// press or long press; the menu closes itself on a choice or an outside tap.
typedef ChromeMenuAnchorBuilder = Widget Function(
  BuildContext context,
  MenuController controller,
);

class ChromeMenuAnchor extends StatelessWidget {
  const ChromeMenuAnchor({
    super.key,
    required this.items,
    required this.builder,
    this.controller,
  });

  final List<ChromeMenuItem> items;
  final ChromeMenuAnchorBuilder builder;
  final MenuController? controller;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    Widget anchorChild(BuildContext c, MenuController controller, Widget? _) =>
        builder(c, controller);
    Widget roleSemantics(ChromeMenuItem item, Widget child) => MergeSemantics(
      child: Semantics(
        hint: item.destructive ? 'destructive' : null,
        child: child,
      ),
    );
    if (_isIos) {
      return CupertinoMenuAnchor(
        controller: controller,
        builder: anchorChild,
        menuChildren: <Widget>[
          for (final ChromeMenuItem item in items)
            roleSemantics(
              item,
              CupertinoMenuItem(
                isDestructiveAction: item.destructive,
                onPressed: item.onSelected,
                trailing: Icon(item.icon, size: AppSize.iconMd),
                child: Text(
                  item.label,
                  style: const TextStyle(
                    fontFamily: AppType.interfaceFontFamily,
                  ),
                ),
              ),
            ),
        ],
      );
    }
    return MenuAnchor(
      controller: controller,
      builder: anchorChild,
      menuChildren: <Widget>[
        for (final ChromeMenuItem item in items)
          roleSemantics(
            item,
            MenuItemButton(
              style: item.destructive
                  ? MenuItemButton.styleFrom(
                      foregroundColor: color.statusError,
                      iconColor: color.statusError,
                      iconSize: AppSize.iconMd,
                    )
                  : MenuItemButton.styleFrom(iconSize: AppSize.iconMd),
              leadingIcon: Icon(item.icon),
              onPressed: item.onSelected,
              child: Text(item.label),
            ),
          ),
      ],
    );
  }
}
