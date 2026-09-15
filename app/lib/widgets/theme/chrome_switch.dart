import 'package:cupertino_ui/cupertino_ui.dart'
    show
        BuildContext,
        Color,
        CupertinoSwitch,
        StatelessWidget,
        ValueChanged,
        Widget,
        WidgetState,
        WidgetStateProperty,
        WidgetStatePropertyAll;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:material_ui/material_ui.dart' show Switch;

import 'app_color.dart';
import 'app_radius.dart';

/// The platform switch uses the app's track and thumb colors.
class ChromeSwitch extends StatelessWidget {
  const ChromeSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return Switch(value: value, onChanged: onChanged);
    }
    final AppColor color = AppColor.of(context);
    return CupertinoSwitch(
      value: value,
      onChanged: onChanged,
      activeTrackColor: color.accentPrimary,
      inactiveTrackColor: color.bgHigh,
      thumbColor: color.fgOnAccent,
      inactiveThumbColor: color.fgPrimary,
      trackOutlineColor: WidgetStateProperty.resolveWith<Color?>(
        (Set<WidgetState> states) =>
            states.contains(WidgetState.selected) ? null : color.borderStrong,
      ),
      trackOutlineWidth: const WidgetStatePropertyAll<double>(
        AppBorder.hairline,
      ),
    );
  }
}
