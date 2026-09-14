/// Eyebrow widget per `docs/32-design-language.md` section 7.1 (R-32-505):
/// a 24x1 rule in `accent.primary`, `space.3` gap, then `type.micro` UPPER
/// in `accent.text`. Used above the welcome headline, the empty-state title,
/// and the full-screen blocking state title.
library;

import 'package:flutter/widgets.dart'
    show
        BuildContext,
        Column,
        CrossAxisAlignment,
        DecoratedBox,
        BoxDecoration,
        MainAxisSize,
        SizedBox,
        StatelessWidget,
        Text,
        Widget;

import 'theme/app_color.dart';
import 'theme/app_space.dart';
import 'theme/app_type.dart';

class Eyebrow extends StatelessWidget {
  const Eyebrow({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 24,
          height: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(color: color.accentPrimary),
          ),
        ),
        const SizedBox(height: AppSpace.space3),
        Text(
          text.toUpperCase(),
          style: AppType.micro.copyWith(color: color.accentText),
        ),
      ],
    );
  }
}
