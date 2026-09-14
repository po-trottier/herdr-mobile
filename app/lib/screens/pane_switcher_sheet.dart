/// The hierarchy switcher of `docs/03-product-decisions.md` R-03-113 item 1, drawn from
/// `docs/31-mockups/08-terminal.md` (the switcher wireframe, callout 10, R-31-08-25): one bottom
/// sheet that lists the live tree the terminal screen already follows — workspace headers, tab
/// headers and pane rows — and moves between panes without leaving the terminal. A tap on a
/// pane closes the sheet and hands the pane id to the caller, who replaces the terminal route
/// (`routing.dart` pushes `/hosts/:hostId/panes/:paneId` in place of the current one). Nothing
/// here splits, zooms or renames (R-03-101), and nothing here sends a frame.
///
/// The workspace header uses `AppSectionHeader.tier1`. Each pane uses the one-line Workspace
/// anatomy of R-03-115 (amended 2026-09-10): an agent kind and pane name lead its state word,
/// while a shell pane leads its display name and optional title with the pane glyph. An agent row
/// is a pane whose `agent` is set, and its state is the pane's own `agent_status`, the same
/// reading `agent_list.dart` takes: `tree_update` keeps that field current while `agents[]`
/// refreshes only with a full `tree_snapshot`.
///
/// ponytail: the sheet draws the tree it was opened with. A `tree_update` that lands while the
/// sheet is open reaches it on the next open; a pane that closed meanwhile opens as the
/// terminal's own pane-gone state, which is honest. A live sheet needs the terminal to hand
/// over a listenable tree; add it when a person reports a stale row.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart'
    show
        AnimatedContainer,
        AnimationStyle,
        BorderRadius,
        BoxConstraints,
        BoxDecoration,
        BuildContext,
        Center,
        Column,
        ColoredBox,
        ConstrainedBox,
        DraggableScrollableSheet,
        Container,
        CrossAxisAlignment,
        EdgeInsets,
        EdgeInsetsDirectional,
        ExcludeSemantics,
        Expanded,
        Icon,
        ListView,
        MainAxisSize,
        MediaQuery,
        Navigator,
        Padding,
        PlaceholderAlignment,
        PositionedDirectional,
        Radius,
        Row,
        SafeArea,
        ScrollController,
        Semantics,
        SizedBox,
        Stack,
        State,
        StatefulWidget,
        StatelessWidget,
        Text,
        TextBaseline,
        TextOverflow,
        TextSpan,
        ValueChanged,
        VoidCallback,
        Widget,
        WidgetSpan;
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart'
    show Colors, Material, RoundedRectangleBorder, showModalBottomSheet;

import '../models/messages/pane_summary.dart' show PaneSummary;
import '../models/messages/tree_snapshot.dart' show TreeSnapshot;
import '../services/tree.dart'
    show TabNode, WorkspaceNode, buildTree, paneDisplayName;
import '../widgets/app_section_header.dart' show AppSectionHeader;
import '../widgets/status_bar.dart' show BarState, StatusBar;
import '../widgets/theme/app_color.dart';
import '../widgets/theme/app_motion.dart' show AppMotion;
import '../widgets/theme/app_pressable.dart' show AppPressable;
import '../widgets/theme/app_radius.dart' show AppBorder, AppRadius;
import '../widgets/theme/app_size.dart' show AppSize;
import '../widgets/theme/app_space.dart' show AppSpace;
import '../widgets/theme/app_type.dart' show AppType;

/// The switcher's own ladder of tiers: a workspace header keeps `AppSectionHeader.tier1`'s
/// text edge, and the tab header and the pane rows under it start one `space.10` in, so the
/// tab glyph and the pane row's state bar share one column and each tier's text sits further
/// in than the tier above (R-03-057's "tiers read apart").
const double _tierInset = AppSpace.space10;

/// Section 7.16's sheet motion, the same values `pane_actions_sheet.dart` applies:
/// `motion.duration.base` both ways, `motion.curve.enter` in and `motion.curve.exit` out; under
/// reduce motion no animation at all (R-32-606).
AnimationStyle _sheetAnimationStyle(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? AnimationStyle.noAnimation
    : const AnimationStyle(
        duration: AppMotion.durationBase,
        reverseDuration: AppMotion.durationBase,
        curve: AppMotion.curveEnter,
        reverseCurve: AppMotion.curveExit,
      );

/// Shows [PaneSwitcherSheet] as the modal bottom sheet of section 7.16 on both platforms
/// (R-33-037, R-03-108: the platform's own draggable sheet), on the root navigator like every
/// other sheet: `radius.lg` top corners and `color.bg.raised`. [currentPaneId] marks the row
/// that is already on screen; [onSwitchPane] receives any other pane a person chooses, after
/// the sheet has closed.
Future<void> showPaneSwitcherSheet(
  BuildContext context, {
  required TreeSnapshot tree,
  required String currentPaneId,
  required ValueChanged<String> onSwitchPane,
}) async {
  final double bottomInset = MediaQuery.viewPaddingOf(context).bottom;
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: false,
    backgroundColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    sheetAnimationStyle: _sheetAnimationStyle(context),
    builder: (BuildContext sheetContext) => Padding(
      // The keyboard the grid raised (R-03-054) may still be up: the sheet sits above it, the
      // way the pane action sheet does (R-31-10-09).
      padding: EdgeInsets.only(
        bottom: math.max(
          bottomInset,
          MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
      ),
      // Material's own scrollable-sheet pattern: the sheet opens part-height so the scrim
      // stays tappable, the list scrolls inside it, and a drag past the top of the list pulls
      // the sheet down and dismisses it. A `shrinkWrap` list in an `isScrollControlled` sheet
      // grew a long tree to the whole screen and swallowed every drag, so the only way out was
      // the back gesture (product owner, 2026-09-14).
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (BuildContext context, ScrollController scrollController) =>
            Material(
              color: AppColor.of(context).bgRaised,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.lg),
              ),
              child: PaneSwitcherSheet(
                tree: tree,
                currentPaneId: currentPaneId,
                onSwitchPane: onSwitchPane,
                scrollController: scrollController,
              ),
            ),
      ),
    ),
  );
}

/// The sheet's content: the grab handle, the `Switch pane` heading, then the joined tree of
/// `tree.dart`'s [buildTree] as one scrolling list. See this file's top doc comment.
class PaneSwitcherSheet extends StatefulWidget {
  const PaneSwitcherSheet({
    super.key,
    required this.tree,
    required this.currentPaneId,
    required this.onSwitchPane,
    this.scrollController,
  });

  final TreeSnapshot tree;

  /// The pane the terminal shows now: its row takes the `color.accent.soft` wash and the
  /// semantics state `selected`, and a tap on it only closes the sheet.
  final String currentPaneId;

  /// Fires with the chosen pane id after the sheet has popped; never with [currentPaneId].
  final ValueChanged<String> onSwitchPane;

  /// The `DraggableScrollableSheet` controller from [showPaneSwitcherSheet], so the list's
  /// overscroll drags the sheet instead of stopping at the list's edge. `null` in a bare test
  /// harness.
  final ScrollController? scrollController;

  @override
  State<PaneSwitcherSheet> createState() => _PaneSwitcherSheetState();
}

class _PaneSwitcherSheetState extends State<PaneSwitcherSheet> {
  /// The workspaces a person collapsed in this sheet. Every workspace starts expanded, and the
  /// set dies with the sheet.
  final Set<String> _collapsed = <String>{};

  void _choose(String paneId) {
    Navigator.of(context).pop();
    if (paneId != widget.currentPaneId) widget.onSwitchPane(paneId);
  }

  List<Widget> _rows() {
    final List<Widget> rows = <Widget>[];
    for (final WorkspaceNode node in buildTree(widget.tree)) {
      final String id = node.workspace.workspaceId;
      final bool expanded = !_collapsed.contains(id);
      final String count = node.paneCount == 1
          ? '1 pane'
          : '${node.paneCount} panes';
      rows.add(
        AppSectionHeader.tier1(
          label: node.workspace.name,
          expanded: expanded,
          count: count,
          semanticsLabel: '${node.workspace.name}, $count',
          onToggle: () => setState(() {
            if (!_collapsed.remove(id)) _collapsed.add(id);
          }),
        ),
      );
      if (!expanded) continue;
      for (final TabNode tab in node.tabs) {
        rows.add(_TabHeader(title: tab.tab.title));
        for (final (int index, PaneSummary pane) in tab.panes.indexed) {
          rows.add(
            _PaneRow(
              pane: pane,
              selected: pane.paneId == widget.currentPaneId,
              showDivider: index < tab.panes.length - 1,
              onTap: () => _choose(pane.paneId),
            ),
          );
        }
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final List<Widget> rows = _rows();
    return SizedBox.expand(
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const _GrabHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.space4,
                AppSpace.space4,
                AppSpace.space4,
                AppSpace.space3,
              ),
              child: Semantics(
                header: true,
                child: Text(
                  'Switch pane',
                  style: AppType.heading.copyWith(color: color.fgPrimary),
                ),
              ),
            ),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.space4,
                  AppSpace.space0,
                  AppSpace.space4,
                  AppSpace.space4,
                ),
                child: Text(
                  'No panes on this computer.',
                  style: AppType.body.copyWith(color: color.fgSecondary),
                ),
              )
            else
              Expanded(
                child: ListView(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.only(bottom: AppSpace.space2),
                  children: rows,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The grab handle: `size.grab` at `radius.full` in `color.fg.disabled`, centred, `space.2`
/// from the top, excluded from the semantics tree (R-32-546); the copy every sheet carries.
class _GrabHandle extends StatelessWidget {
  const _GrabHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.space2),
      child: Center(
        child: ExcludeSemantics(
          child: Container(
            width: AppSize.grabWidth,
            height: AppSize.grabHeight,
            decoration: BoxDecoration(
              color: AppColor.of(context).fgDisabled,
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tier 2, one tab: the `A tab` glyph of R-32-401 at `size.icon.sm` in `color.fg.secondary`
/// at [_tierInset], a `space.2` gap, the title in `type.body.strong` `color.fg.primary`; its
/// line plus `space.3` above and below, so the row is 48 at the default text scale like the
/// tab tier of `docs/31-mockups/06-agent-list.md`. Not a target: a tab has no phone action
/// (R-03-101), and its panes are the targets under it.
class _TabHeader extends StatelessWidget {
  const _TabHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        _tierInset,
        AppSpace.space3,
        AppSpace.space4,
        AppSpace.space3,
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Symbols.tab_rounded,
            size: AppSize.iconSm,
            color: color.fgSecondary,
          ),
          const SizedBox(width: AppSpace.space2),
          Expanded(
            child: Text(
              title,
              style: AppType.bodyStrong.copyWith(color: color.fgPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// The state bar's state and the state word for a pane's `agent_status` (R-03-100, R-30-402),
/// one hue and one word per state of R-30-401; an unrecognised string is `unknown`, never
/// `idle` (R-30-404).
({BarState bar, String word}) _stateOf(String status) => switch (status) {
  'working' => (bar: BarState.working, word: 'Working'),
  'idle' => (bar: BarState.idle, word: 'Idle'),
  'blocked' => (bar: BarState.blocked, word: 'Blocked'),
  'done' => (bar: BarState.done, word: 'Done'),
  _ => (bar: BarState.unknown, word: 'Unknown'),
};

/// Tier 3, one pane, inset by [_tierInset] so its state bar stands in the tab glyph's column.
/// Since 2026-09-10, per R-03-115, agent and shell rows share one baseline and one 48-high
/// anatomy. An agent row reads kind, `space.2`, pane name on the leading side, then the state
/// word at the trailing edge. A shell row reads its pane glyph, display name, `space.2`, and
/// optional title. [selected] is the pane on screen: the `color.accent.soft` wash and the
/// semantics state `selected`. The one semantics node reads `agent kind, state, pane` for an
/// agent row and `pane, title` for a shell row.
class _PaneRow extends StatelessWidget {
  const _PaneRow({
    required this.pane,
    required this.selected,
    required this.showDivider,
    required this.onTap,
  });

  final PaneSummary pane;
  final bool selected;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final String name = paneDisplayName(pane);
    final String? agentKind = pane.agent;
    final ({BarState bar, String word})? state = agentKind == null
        ? null
        : _stateOf(pane.agentStatus);
    final String label = state == null
        ? <String>[name, if (pane.title.isNotEmpty) pane.title].join(', ')
        : '$agentKind, ${state.word}, $name';
    final Widget paneLabel = agentKind == null
        ? Text.rich(
            TextSpan(
              text: name,
              style: AppType.body.copyWith(color: color.fgSecondary),
              children: [
                if (pane.title.isNotEmpty)
                  const WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: SizedBox(width: AppSpace.space2),
                  ),
                if (pane.title.isNotEmpty)
                  TextSpan(
                    text: pane.title,
                    style: AppType.caption.copyWith(color: color.fgSecondary),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                agentKind,
                style: AppType.body.copyWith(color: color.fgPrimary),
              ),
              const SizedBox(width: AppSpace.space2),
              Expanded(
                child: Text(
                  name,
                  style: AppType.caption.copyWith(color: color.fgSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );

    final Widget row = Semantics(
      label: label,
      selected: selected,
      button: true,
      onTap: onTap,
      excludeSemantics: true,
      child: AppPressable(
        onTap: onTap,
        builder: (BuildContext context, bool pressed) => AnimatedContainer(
          duration: AppPressable.fillDuration(context, pressed),
          curve: AppPressable.fillCurve(context),
          color: pressed
              ? color.bgHigh
              : selected
              ? color.accentSoft
              : Colors.transparent,
          child: Stack(
            children: <Widget>[
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppSize.targetMin),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.space4,
                    AppSpace.space3,
                    AppSpace.space4,
                    AppSpace.space3,
                  ),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: AppSize.iconSm,
                        child: agentKind == null
                            ? Icon(
                                Symbols.splitscreen_rounded,
                                size: AppSize.iconSm,
                                color: color.fgSecondary,
                              )
                            : null,
                      ),
                      const SizedBox(width: AppSpace.space3),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: <Widget>[
                            Expanded(child: paneLabel),
                            if (state != null) ...<Widget>[
                              const SizedBox(width: AppSpace.space3),
                              Text(
                                state.word,
                                style: AppType.body.copyWith(
                                  color: color.fgPrimary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (showDivider)
                PositionedDirectional(
                  start: AppSpace.space4,
                  end: 0,
                  bottom: 0,
                  child: SizedBox(
                    height: AppBorder.hairline,
                    child: ColoredBox(color: color.borderSubtle),
                  ),
                ),
              if (state != null)
                PositionedDirectional(
                  start: 0,
                  top: 0,
                  bottom: 0,
                  child: StatusBar(state: state.bar),
                ),
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: _tierInset),
      child: row,
    );
  }
}
