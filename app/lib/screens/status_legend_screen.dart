/// The `Status colours` legend, `docs/03-product-decisions.md` R-03-106 (decided 2026-09-09 by
/// the product owner, who saw blue and green bars in the lists and could not tell what was what),
/// drawn from `docs/31-mockups/20-status-legend.md` (R-90-010, R-90-011): every state the state
/// bar of `docs/32-design-language.md` section 7.29 can show, one platform row each, grouped by
/// hue so that the states which share one hue on purpose (R-32-130) sit together under that
/// colour's name.
///
/// This file owns no route (R-90-024): `app/lib/routing.dart` wires `/settings/status-colours`
/// to this widget, and `settings_screen.dart`'s `Status colours` row pushes it, so the page is
/// two taps from any tab (R-03-106). It reads no service and holds no state: every value is a
/// build constant, the [BarState] set of `status_bar.dart` and the words of
/// `docs/30-ux-spec.md`'s agent status table, so the page works with no network and no
/// connected computer (R-31-20-07).
library;

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoNavigationBar, CupertinoPageScaffold;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart'
    show
        Border,
        BorderSide,
        BuildContext,
        Container,
        CustomScrollView,
        EdgeInsets,
        Padding,
        PositionedDirectional,
        SafeArea,
        Semantics,
        SliverList,
        SliverPadding,
        Stack,
        StatelessWidget,
        Text,
        TextStyle,
        Widget;
import 'package:material_ui/material_ui.dart'
    show AppBar, PreferredSize, Scaffold, Size;

import '../widgets/status_bar.dart' show BarState, StatusBar;
import '../widgets/theme/app_color.dart' show AppColor;
import '../widgets/theme/app_radius.dart' show AppBorder;
import '../widgets/theme/app_space.dart' show AppSpace;
import '../widgets/theme/app_type.dart' show AppType;
import '../widgets/theme/chrome_list_row.dart' show ChromeListRow;
import '../widgets/theme/chrome_settings_section.dart'
    show ChromeSettingsSection;

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

/// The lead line of R-31-20-04, verbatim: the one place the page says in words which states
/// share a hue and how a person tells them apart (R-03-106, R-32-130).
const String statusLegendLead =
    'Every state bar takes one of these colours. Working and Warning share '
    'one amber, Blocked and Error share one red, and Idle and Ok share one '
    'green. The word beside the bar tells them apart.';

/// One legend row (R-31-20-02): the bar state, the word the app writes beside that bar, and one
/// plain sentence saying what the state means for an agent or a computer.
class _LegendEntry {
  const _LegendEntry(this.state, this.word, this.meaning);

  final BarState state;
  final String word;
  final String meaning;
}

/// One hue group (R-31-20-03): the colour's name as the group header, the states that draw it,
/// and one caption line under the rows where the rows alone leave a fact unsaid.
class _LegendGroup {
  const _LegendGroup({
    required this.header,
    required this.entries,
    this.caption,
  });

  final String header;
  final List<_LegendEntry> entries;
  final String? caption;
}

/// The eight states of [BarState], grouped by hue in the order R-31-20-03 fixes: the three
/// shared hues first, each pair together, then the two hues one state draws alone. The words
/// are the ones the app writes beside the bar (`docs/30-ux-spec.md` R-30-400 for the five
/// agent states; `Ok`, `Warning` and `Error` for the connection legs and the live bar), and
/// each meaning is one sentence a `CupertinoListTile` subtitle or a section 7.4 secondary line
/// holds on one line at the reference width up to the 1.3 text scale of R-30-703 (measured
/// with the bundled face on 2026-09-09; the platform tile does not wrap a subtitle), which is
/// why the sharing itself is said once in [statusLegendLead] and not repeated in every subtitle.
const List<_LegendGroup> _groups = <_LegendGroup>[
  _LegendGroup(
    header: 'AMBER',
    entries: <_LegendEntry>[
      _LegendEntry(
        BarState.working,
        'Working',
        'An agent is doing something now.',
      ),
      _LegendEntry(
        BarState.warning,
        'Warning',
        'A link is stale, in use or still connecting.',
      ),
    ],
  ),
  _LegendGroup(
    header: 'RED',
    entries: <_LegendEntry>[
      _LegendEntry(
        BarState.blocked,
        'Blocked',
        'An agent is waiting for a person.',
      ),
      _LegendEntry(
        BarState.error,
        'Error',
        'A connection is lost or a check failed.',
      ),
    ],
  ),
  _LegendGroup(
    header: 'GREEN',
    entries: <_LegendEntry>[
      _LegendEntry(
        BarState.idle,
        'Idle',
        'An agent runs and waits for nothing.',
      ),
      _LegendEntry(BarState.ok, 'Ok', 'The computer is connected and healthy.'),
    ],
    // R-32-705: a saved computer rests in `idle`, and so does a phone that is not connected on
    // `docs/31-mockups/14-devices.md`; the `Idle` row alone would read as an agent's state only.
    caption: 'A paired computer or phone that is not connected shows Idle too.',
  ),
  _LegendGroup(
    header: 'TEAL',
    entries: <_LegendEntry>[
      _LegendEntry(BarState.done, 'Done', 'Unseen background work finished.'),
    ],
  ),
  _LegendGroup(
    header: 'GREY',
    entries: <_LegendEntry>[
      _LegendEntry(
        BarState.unknown,
        'Unknown',
        'The app cannot tell, usually a lost link.',
      ),
    ],
  ),
];

/// `/settings/status-colours`: the lead line, then one platform group per hue (R-31-20-01).
class StatusLegendScreen extends StatelessWidget {
  const StatusLegendScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    // The lead line and every caption sit on the group header's edge: `space.4` on Android, and
    // on iOS one more `space.4`, the card margin `ChromeSettingsSection` insets its header by.
    final double textInset = _isIos ? AppSpace.space4 * 2 : AppSpace.space4;
    final TextStyle captionStyle = AppType.caption.copyWith(
      color: color.fgSecondary,
    );

    // R-03-107 (amended 2026-09-09): a screen with content paints plain `color.bg.base`, no
    // ground grid and no paper block, like `/settings` (R-31-20-05). The lead line sits under a
    // `space.4` gap; every group brings its `space.6` gap (R-30-231), and a group's caption
    // follows its rows after `space.2`.
    final body = SafeArea(
      child: CustomScrollView(
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.only(bottom: AppSpace.space4),
            sliver: SliverList.list(
              children: <Widget>[
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    textInset,
                    AppSpace.space4,
                    textInset,
                    0,
                  ),
                  child: Text(statusLegendLead, style: captionStyle),
                ),
                for (final _LegendGroup group in _groups) ...<Widget>[
                  ChromeSettingsSection(
                    header: group.header,
                    rows: <Widget>[
                      for (final (int index, _LegendEntry entry)
                          in group.entries.indexed)
                        _LegendRow(
                          entry: entry,
                          // Android only: the last row of a group carries no divider (R-32-515).
                          showDivider: index < group.entries.length - 1,
                        ),
                    ],
                  ),
                  if (group.caption case final String caption)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        textInset,
                        AppSpace.space2,
                        textInset,
                        0,
                      ),
                      child: Text(caption, style: captionStyle),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    // R-32-510, R-32-115: `color.bg.base` with a `border.hairline` `color.border.strong` bottom
    // edge on both platforms, `type.heading` because the screen carries a back control, which
    // the platform's own navigation component draws (R-33-070); this file places no glyph.
    final title = Text(
      'Status colours',
      style: AppType.heading.copyWith(color: color.fgPrimary),
    );
    if (_isIos) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          backgroundColor: color.bgBase,
          border: Border(
            bottom: BorderSide(
              color: color.borderStrong,
              width: AppBorder.hairline,
            ),
          ),
          middle: title,
        ),
        child: body,
      );
    }
    return Scaffold(
      backgroundColor: color.bgBase,
      appBar: AppBar(
        backgroundColor: color.bgBase,
        elevation: 0,
        title: title,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(AppBorder.hairline),
          child: Container(
            color: color.borderStrong,
            height: AppBorder.hairline,
          ),
        ),
      ),
      body: body,
    );
  }
}

/// One legend row: the platform's static tile of R-33-073 (`ChromeListRow.static`, information
/// and not a control) with the state bar of section 7.29 painted over its leading edge, the same
/// positioned composition every list row of the app uses (`app_list_row.dart`,
/// `notifications_screen.dart`, `device_list_screen.dart`): `border.attention` wide, the row's
/// full height, flush to the leading edge, and the text keeps the tile's own inset. The bar is
/// the real [StatusBar], so `Working` pulses here exactly as it pulses in a list (R-32-592) and
/// holds still under reduce motion. The row is one semantics node reading `<word>, <meaning>`
/// (R-32-505, R-31-20-06): `container` makes it a boundary of its own, because a label-only
/// node with no action would otherwise merge with its neighbours into one node that reads the
/// whole group in one breath; the bar itself has no node, because the words carry the state.
class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.entry, required this.showDivider});

  final _LegendEntry entry;
  final bool showDivider;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: '${entry.word}, ${entry.meaning}',
    excludeSemantics: true,
    child: Stack(
      children: <Widget>[
        ChromeListRow.static(
          title: entry.word,
          subtitle: entry.meaning,
          showDivider: showDivider,
        ),
        PositionedDirectional(
          start: 0,
          top: 0,
          bottom: 0,
          child: StatusBar(state: entry.state),
        ),
      ],
    ),
  );
}
