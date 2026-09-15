import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoButton, CupertinoButtonSize;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show ActionChip;

import 'app_color.dart';
import 'app_radius.dart';
import 'app_type.dart';

/// An autocomplete action with the platform's native shape and feedback.
class ChromeSuggestionChip extends StatelessWidget {
  const ChromeSuggestionChip({
    super.key,
    required this.word,
    required this.onPressed,
  });

  final String word;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = AppColor.of(context);
    final label = Text(word, style: AppType.monoPhrase);
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return CupertinoButton.tinted(
        sizeStyle: CupertinoButtonSize.small,
        color: color.bgHigh,
        foregroundColor: color.fgPrimary,
        onPressed: onPressed,
        child: label,
      );
    }
    return ActionChip(
      label: label,
      labelStyle: AppType.monoPhrase.copyWith(color: color.fgPrimary),
      backgroundColor: color.bgHigh,
      side: BorderSide(color: color.borderStrong, width: AppBorder.hairline),
      onPressed: onPressed,
    );
  }
}
