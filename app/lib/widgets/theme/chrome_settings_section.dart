/// The settings-list composing widget, per `docs/33-platform-chrome.md`
/// R-33-073.
library;

import 'package:cupertino_ui/cupertino_ui.dart'
    show
        BorderRadius,
        BoxDecoration,
        BuildContext,
        Column,
        CrossAxisAlignment,
        CupertinoListSection,
        EdgeInsets,
        Padding,
        SizedBox,
        StatelessWidget,
        Widget;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;

import '../app_section_header.dart';
import 'app_color.dart';
import 'app_space.dart';

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

/// The inset-grouped corner `CupertinoListSection` draws itself, 10, kept
/// as the platform's own value like the FAB corner of R-32-588: R-33-012
/// asks for the plain Cupertino appearance in the Herdr palette, and the
/// widget takes the whole decoration or none, so recolouring the rows
/// container means restating its shape.
const double _insetGroupedCorner = 10;

/// One settings group, composed from the platform's own list widgets: on
/// iOS a [CupertinoListSection], and on Android the Material settings
/// convention of a small caption header above a plain column of rows. A
/// single choice inside [rows] MUST open a native single-choice screen or
/// dialog, which this widget does not build: it owns composition, not the
/// row content, per R-33-073.
///
/// The section paints nothing of its own: it sits on the screen's plain
/// `color.bg.base` (R-03-107, amended 2026-09-09: no paper block behind
/// content) and keeps the `space.6` group gap above it.
class ChromeSettingsSection extends StatelessWidget {
  const ChromeSettingsSection({super.key, this.header, required this.rows});

  final String? header;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    // R-33-073 owns composition only; the header's ink, type and height are
    // R-32-563's upper-case tier (`type.micro`, `fg.secondary`, `size.header`),
    // the form `docs/31-mockups/15-appearance.md` callouts 2, 14 and 17 name
    // for every group. Every group, with a header or without one, keeps the
    // group gap of R-30-231 (`space.6`) above it, so the header binds to its
    // own rows below rather than floating equidistant between two groups, and
    // a lone `Alerts` or `About` row never sits flush under the group before
    // it (amended 2026-09-08: a headered group had no gap at all).
    //
    // On iOS the same header sits above the `CupertinoListSection`, inset by
    // the card margin so it starts on the row text's edge (`space.4` margin
    // plus the row's `space.4` inset), and the separators start on that same
    // edge (amended 2026-09-08, R-33-073.1: the section's own header margin
    // put the header at 20, and its 14 + 42 divider margin put the
    // separators at 72, three left edges in one card).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: AppSpace.space6),
        if (header != null)
          Padding(
            padding: EdgeInsets.only(left: _isIos ? AppSpace.space4 : 0),
            child: AppSectionHeader.upperCase(label: header!),
          ),
        if (_isIos)
          // R-33-012: the plain Cupertino composition in the Herdr fixed
          // chrome palette, never the iOS system grouped greys.
          CupertinoListSection.insetGrouped(
            backgroundColor: color.bgBase,
            decoration: BoxDecoration(
              color: color.bgRaised,
              borderRadius: BorderRadius.circular(_insetGroupedCorner),
            ),
            separatorColor: color.borderSubtle,
            margin: const EdgeInsets.symmetric(horizontal: AppSpace.space4),
            dividerMargin: AppSpace.space4,
            additionalDividerMargin: 0,
            children: rows,
          )
        else
          ...rows,
      ],
    );
  }
}
