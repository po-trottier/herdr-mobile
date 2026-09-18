/// The actions of one list row, opened by a long press, per
/// `docs/33-platform-chrome.md` R-33-033's `Row actions` row and R-33-080:
/// on Android a Material `MenuAnchor` opened at the finger
/// (`MenuController.open(position:)`) with one `MenuItemButton` per action;
/// on iOS the platform's context menu, `CupertinoContextMenu`, which lifts
/// a preview of the row and lists one `CupertinoContextMenuAction` per
/// action. Both are the SDK's own widgets, per R-03-059; the app draws no
/// swipe pane (`docs/30-ux-spec.md` R-30-296, retired 2026-09-18).
///
/// A destructive action takes the platform's own role, as in
/// `chrome_menu.dart`. The caller keeps every action reachable as a named
/// custom semantics action on the row (R-32-515, R-30-298): a long press has
/// no spoken path either.
library;

import 'dart:async' show unawaited;

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoContextMenu, CupertinoContextMenuAction;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show Feedback, MenuAnchor;

import 'app_color.dart';
import 'app_radius.dart';
import 'app_type.dart';
import 'chrome_menu.dart';

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

class ChromeRowActions extends StatefulWidget {
  const ChromeRowActions({super.key, required this.items, required this.child});

  /// At least one item. The list is drawn in this order on both platforms.
  final List<ChromeMenuItem> items;

  /// The tappable row. Its own tap keeps winning a short press.
  final Widget child;

  /// Opens the enclosing row's Material menu from a control inside the row,
  /// with the menu's top-left at the control's bottom-left, the way a
  /// `MenuAnchor` anchored to that control opens. The Android path for a
  /// row's `⋮`: a second `MenuAnchor` inside the row would register as a
  /// submenu of the row's own and share its tap region, so a row holds one
  /// menu and two ways to open it. On iOS the `⋮` opens its own
  /// `ChromeMenuAnchor`, and this method does nothing.
  static void openFrom(BuildContext control) {
    final _ChromeRowActionsState? row = control
        .findAncestorStateOfType<_ChromeRowActionsState>();
    if (row == null || _isIos) return;
    final RenderBox controlBox = control.findRenderObject()! as RenderBox;
    final RenderBox rowBox = row.context.findRenderObject()! as RenderBox;
    row._controller.open(
      position: rowBox.globalToLocal(
        controlBox.localToGlobal(Offset(0, controlBox.size.height)),
      ),
    );
  }

  @override
  State<ChromeRowActions> createState() => _ChromeRowActionsState();
}

class _ChromeRowActionsState extends State<ChromeRowActions> {
  final MenuController _controller = MenuController();

  @override
  Widget build(BuildContext context) {
    assert(widget.items.isNotEmpty, 'A row with actions offers at least one');
    if (_isIos) {
      final AppColor color = AppColor.of(context);
      // The row's resting width, so the lifted copy and the preview lay the
      // row out at that width and scale it into the rect the menu gives
      // them, the way the SDK's own default preview fits any child.
      return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) =>
            CupertinoContextMenu.builder(
              enableHapticFeedback: true,
              actions: <Widget>[
                for (final ChromeMenuItem item in widget.items)
                  CupertinoContextMenuAction(
                    isDestructiveAction: item.destructive,
                    trailingIcon: item.icon,
                    // The action runs after the pop's first frame, as a
                    // `MenuItemButton` runs its own after its close, so a
                    // dialog the action raises never opens in the frame the
                    // menu route leaves.
                    onPressed: item.onSelected == null
                        ? null
                        : () {
                            Navigator.of(context, rootNavigator: true).pop();
                            SchedulerBinding.instance.addPostFrameCallback(
                              (_) => item.onSelected!(),
                            );
                          },
                    child: Text(
                      item.label,
                      style: const TextStyle(
                        fontFamily: AppType.interfaceFontFamily,
                      ),
                    ),
                  ),
              ],
              // At rest the row is drawn as is. While the press lifts it and
              // in the open menu's preview it takes a raised surface, so the
              // preview is a card and not text over the blurred screen.
              builder: (BuildContext context, Animation<double> animation) {
                final double t =
                    (animation.value / CupertinoContextMenu.animationOpensAt)
                        .clamp(0.0, 1.0);
                if (t == 0) return widget.child;
                return FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: constraints.maxWidth,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.md * t),
                      child: ColoredBox(
                        color: color.bgRaised.withValues(alpha: t),
                        child: widget.child,
                      ),
                    ),
                  ),
                );
              },
            ),
      );
    }
    return MenuAnchor(
      controller: _controller,
      consumeOutsideTap: true,
      menuChildren: materialMenuChildren(context, widget.items),
      builder: (BuildContext context, MenuController controller, Widget? _) =>
          GestureDetector(
            onLongPressStart: (LongPressStartDetails details) {
              unawaited(Feedback.forLongPress(context));
              controller.open(position: details.localPosition);
            },
            child: widget.child,
          ),
    );
  }
}
