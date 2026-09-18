/// A sheet that carries content, per `docs/33-platform-chrome.md`
/// R-33-033's `Content sheet` row: on Android the Material 3 modal bottom
/// sheet through `showModalBottomSheet`, its drag handle, corner, colour
/// and elevation the component's own from `bottomSheetTheme`; on iOS the
/// platform's sheet, `CupertinoSheetRoute`, with its own grabber, over a
/// `CupertinoPageScaffold` in `color.bg.raised`, because that route paints
/// no surface of its own and Apple's sheets carry a page inside. The
/// content draws no handle and no surface of its own.
///
/// [builder] receives the sheet's own [ScrollController] on iOS, which a
/// scrollable inside the sheet MUST take so the drag to dismiss keeps
/// working (R-33-075.2); on Android it receives `null`, and the content
/// scrolls the Material way.
library;

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoPageScaffold, CupertinoSheetRoute;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show showModalBottomSheet;

import 'app_color.dart';

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

typedef ChromeSheetBuilder = Widget Function(
  BuildContext context,
  ScrollController? controller,
);

Future<T?> showChromeSheet<T>({
  required BuildContext context,
  required ChromeSheetBuilder builder,
  bool isDismissible = true,
  bool enableDrag = true,
}) {
  if (_isIos) {
    return Navigator.of(context, rootNavigator: true).push<T>(
      CupertinoSheetRoute<T>(
        enableDrag: enableDrag,
        showDragHandle: true,
        scrollableBuilder:
            (BuildContext sheetContext, ScrollController controller) =>
                CupertinoPageScaffold(
                  backgroundColor: AppColor.of(sheetContext).bgRaised,
                  // The route hands the grabber's height down as top padding.
                  child: SafeArea(
                    bottom: false,
                    child: builder(sheetContext, controller),
                  ),
                ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: enableDrag,
    builder: (BuildContext sheetContext) => builder(sheetContext, null),
  );
}
