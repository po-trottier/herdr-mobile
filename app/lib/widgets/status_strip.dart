/// Terminal metadata and the explicit Overview/Readable control.
/// The screen supplies connection, scroll, column-window, and mode state.
/// See `docs/31-mockups/08-terminal.md` and R-21-008's latest 2026-09-08 correction.
library;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoButton;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart'
    show
        Border,
        BorderSide,
        BuildContext,
        BoxConstraints,
        DecoratedBox,
        BoxDecoration,
        ConstrainedBox,
        EdgeInsets,
        EdgeInsetsDirectional,
        Expanded,
        InlineSpan,
        PlaceholderAlignment,
        Padding,
        Row,
        SizedBox,
        StatelessWidget,
        Text,
        TextSpan,
        TextStyle,
        Size,
        ValueKey,
        VoidCallback,
        Widget,
        WidgetSpan;
import 'package:material_ui/material_ui.dart' show TextButton;

import 'status_bar.dart';
import 'theme/app_color.dart';
import 'theme/app_radius.dart' show AppBorder;
import 'theme/app_size.dart';
import 'theme/app_space.dart';
import 'theme/app_type.dart';

/// The four connection words callout 6 names, in the app bar's language merged with the
/// pause state (R-31-08-23): `live`, `paused` (a held paint, live or not — R-31-08-23's
/// "not the network"), `hostInUse` (draws `in use`) and `offline`.
enum StatusStripLinkWord {
  live,
  paused,
  hostInUse,
  offline;

  /// The exact wire word the mockup draws (callout 6: "`live`, `paused`, `in use` or
  /// `offline`").
  String get label => switch (this) {
    StatusStripLinkWord.live => 'live',
    StatusStripLinkWord.paused => 'paused',
    StatusStripLinkWord.hostInUse => 'in use',
    StatusStripLinkWord.offline => 'offline',
  };
}

/// Terminal metadata beside a native button with a minimum 48dp touch target.
/// The metadata is one text run, so its three type sizes share one baseline and it wraps
/// like prose when the viewport is narrow or the system text scale increases.
class StatusStrip extends StatelessWidget {
  const StatusStrip({
    super.key,
    required this.columns,
    required this.rows,
    required this.linkWord,
    required this.revision,
    required this.scrollOffsetFromBottom,
    required this.scrollMaxOffsetFromBottom,
    required this.overview,
    required this.onToggleOverview,
    this.firstVisibleColumn,
    this.lastVisibleColumn,
    this.textSizeFlash,
    this.rtt,
  });

  /// `rect.width` in character cells (R-10-024). Drawn first, per R-31-08-04.
  final int columns;

  /// `scroll.viewport_rows` (R-10-024). MUST NOT come from `rect.height`, per the same
  /// rule; this file trusts the caller already honoured that.
  final int rows;

  final StatusStripLinkWord linkWord;

  final bool overview;
  final VoidCallback onToggleOverview;

  /// `pane.revision` from `watch_ack`/`pane_frame`. Drawn only while
  /// [scrollOffsetFromBottom] is `0`, per R-31-08-18.
  final int revision;

  /// The Device's own scroll offset above the live bottom (R-31-08-18): `0` at the live
  /// bottom. A value above `0` switches the trailing slot to the scroll readout.
  final int scrollOffsetFromBottom;

  /// `max_offset_from_bottom` from `watch_ack` (R-31-08-18): the second number of the
  /// scroll readout, and the only signal the pane holds any scrollback at all.
  final int scrollMaxOffsetFromBottom;

  /// The first visible column of the pan window (R-21-037). `null` together with
  /// [lastVisibleColumn] omits the `c<first>-<last>` segment entirely.
  final int? firstVisibleColumn;

  /// The last visible column of the pan window (R-21-037).
  final int? lastVisibleColumn;

  /// R-30-302: a pinch MUST show the terminal text size it just landed
  /// on in the status strip for `motion.duration.slow`. The caller owns
  /// the timing; non-null takes the trailing slot for that moment (the
  /// leading group has no width to spare on a 390-pixel screen).
  final double? textSizeFlash;
  final Duration? rtt;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final int? firstColumn = firstVisibleColumn;
    final int? lastColumn = lastVisibleColumn;

    // R-31-08-18: the scroll readout whenever the Device's own offset is above zero, the
    // revision otherwise; R-30-302's size flash takes the slot for its slow duration.
    final String trailing = textSizeFlash != null
        ? '${textSizeFlash!.toStringAsFixed(textSizeFlash == textSizeFlash!.roundToDouble() ? 0 : 1)}px'
        : scrollOffsetFromBottom > 0
        ? '-$scrollOffsetFromBottom\u00a0/\u00a0$scrollMaxOffsetFromBottom'
        : 'rev\u00a0$revision';

    final BarState barState = switch (linkWord) {
      StatusStripLinkWord.live => BarState.working,
      StatusStripLinkWord.paused => BarState.idle,
      StatusStripLinkWord.hostInUse => BarState.blocked,
      StatusStripLinkWord.offline => BarState.unknown,
    };

    // One paragraph, not a `Wrap` of boxes: `type.micro` and `type.caption` have different
    // line heights, so box-centred they sit one pixel apart at the baseline (measured
    // 2026-09-08 in `terminal_view_scrolled_dark.png`). A paragraph puts every run on one
    // baseline, and it still breaks between readouts at a narrow width or a large text
    // scale; a no-break space inside a readout keeps `rev 41822` on one line.
    const WidgetSpan gap = WidgetSpan(child: SizedBox(width: AppSpace.space3));
    final TextStyle caption = AppType.caption.copyWith(
      color: color.fgSecondary,
    );
    final Widget metadata = Text.rich(
      TextSpan(
        style: caption,
        children: <InlineSpan>[
          // R-03-100: the link's state is the bar, a short one before the link word, as
          // tall as the paragraph's `type.caption` line, the inline `size.icon.sm`.
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: StatusBar(state: barState, height: AppSize.iconSm),
          ),
          const WidgetSpan(child: SizedBox(width: AppSpace.space2)),
          TextSpan(
            text: linkWord == StatusStripLinkWord.live && rtt != null
                ? '${rtt!.inMilliseconds} MS'
                : linkWord.label.toUpperCase(),
            semanticsLabel: linkWord == StatusStripLinkWord.live && rtt != null
                ? 'Round trip ${rtt!.inMilliseconds} milliseconds'
                : null,
            style: AppType.micro.copyWith(color: color.fgSecondary),
          ),
          gap,
          TextSpan(text: '${columns}x$rows'),
          if (firstColumn != null && lastColumn != null) ...<InlineSpan>[
            gap,
            TextSpan(text: 'c$firstColumn-$lastColumn'),
          ],
          gap,
          TextSpan(text: trailing),
        ],
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.bgRaised,
        // R-32-542's anatomy: one top edge in `color.border.strong`. The key row below
        // carries its own top edge (R-32-535), so a bottom edge here would double it.
        border: Border(
          top: BorderSide(color: color.borderStrong, width: AppBorder.hairline),
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSize.statusStrip),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.space4),
          child: Row(
            children: <Widget>[
              Expanded(child: metadata),
              const SizedBox(width: AppSpace.space2),
              TerminalOverviewControl(
                overview: overview,
                onPressed: onToggleOverview,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The same labeled native control serves both terminal orientations. Its label ends on the
/// strip's trailing inset, in the column the key row's last cap and the send control end on
/// (R-31-09-21), so the padding sits on the leading side only; the minimum size keeps the
/// target whole.
class TerminalOverviewControl extends StatelessWidget {
  const TerminalOverviewControl({
    super.key,
    required this.overview,
    required this.onPressed,
  });

  final bool overview;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final Widget label = Text(
      overview ? 'Readable' : 'Overview',
      style: AppType.label.copyWith(color: AppColor.of(context).accentText),
    );
    const minimumSize = Size(AppSize.targetMin, AppSize.targetMin);
    const padding = EdgeInsetsDirectional.only(start: AppSpace.space2);
    const controlKey = ValueKey('terminalOverviewToggle');
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return CupertinoButton(
        key: controlKey,
        minimumSize: minimumSize,
        padding: padding,
        onPressed: onPressed,
        child: label,
      );
    }
    return TextButton(
      key: controlKey,
      style: TextButton.styleFrom(minimumSize: minimumSize, padding: padding),
      onPressed: onPressed,
      child: label,
    );
  }
}
