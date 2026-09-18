/// The pane action sheet offers plugin actions, split actions, and `Close pane` (R-03-134).
/// It also offers `Read last 20 lines` when a screen reader is on.
/// Split actions close this sheet and report the direction to the terminal screen.
/// `Close pane` opens a confirmation dialog before it reports the action.
library;

import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart'
    show
        CupertinoActionSheet,
        CupertinoActionSheetAction,
        showCupertinoModalPopup;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/semantics.dart' show SemanticsService;
import 'package:flutter/widgets.dart'
    show
        AnimationStyle,
        BoxConstraints,
        BuildContext,
        Column,
        ConstrainedBox,
        Container,
        CrossAxisAlignment,
        EdgeInsets,
        Flexible,
        Icon,
        IconData,
        IgnorePointer,
        MainAxisSize,
        MediaQuery,
        MergeSemantics,
        ModalRoute,
        Navigator,
        Opacity,
        Padding,
        SafeArea,
        Semantics,
        SingleChildScrollView,
        SizedBox,
        StatelessWidget,
        Text,
        TextDirection,
        TextStyle,
        View,
        ValueChanged,
        VoidCallback,
        Widget;
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart' show showModalBottomSheet;

import '../widgets/app_strip.dart';
import '../widgets/app_text_button.dart';
import '../widgets/theme/app_color.dart';
import '../widgets/theme/app_motion.dart' show AppMotion;
import '../widgets/theme/app_size.dart' show AppSize;
import '../widgets/theme/app_space.dart' show AppSpace;
import '../widgets/theme/app_type.dart' show AppType;
import '../widgets/theme/chrome_confirmation_dialog.dart';
import '../widgets/theme/chrome_confirmation_outcome.dart';
import '../widgets/theme/chrome_list_row.dart';
import '../widgets/treatments.dart';

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

/// `opacity.disabled`, per the opacity table beside R-32-330, for an iOS action whose
/// target is gone: `CupertinoActionSheetAction` has no disabled state of its own, so this
/// file dims the whole action the way `ChromeListRow.destructive` dims its Cupertino tile
/// (R-32-502).
const double _opacityDisabled = 0.38;

/// `border.hairline`, per `docs/32-design-language.md` R-32-330; a local constant beside its
/// callers, matching every other screen's own `_hairlineWidth`.
const double _hairlineWidth = 1;

/// One SGR/CSI escape sequence, for stripping the visible grid text before an accessibility
/// announcement (R-31-10-06: "with every escape sequence removed").
final RegExp _ansiEscape = RegExp('\x1B\\[[0-9;]*[A-Za-z]');

/// The last twenty non-empty lines of [visibleText], escape sequences removed and each
/// line's trailing space stripped (R-31-10-06), joined for one announcement.
String _lastTwentyNonEmptyLines(String visibleText) {
  final List<String> lines = visibleText
      .split('\n')
      .map((String line) => line.replaceAll(_ansiEscape, '').trimRight())
      .where((String line) => line.isNotEmpty)
      .toList();
  final int start = lines.length > 20 ? lines.length - 20 : 0;
  return lines.sublist(start).join('\n');
}

/// Which of the mockup's "Host in use" / "Offline" rows, if either, the sheet's `Close pane`
/// row is in. Mirrors `terminal_view_widget.dart`'s own `TerminalGridPhase` precedent: a
/// bare enum plus a caller-composed detail string, rather than this file inventing its own
/// copy of R-30-940's or R-30-808's wording.
enum PaneActionsLinkState { normal, hostInUse, offline }

/// Section 7.16's sheet motion: `motion.duration.base` both ways, `motion.curve.enter` in and
/// `motion.curve.exit` out; under reduce motion no animation at all (R-32-606). `curveExit` is
/// defined in Flutter's reverse space (R-32-609), so a `reverseCurve` takes it unchanged.
AnimationStyle _sheetAnimationStyle(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? AnimationStyle.noAnimation
    : const AnimationStyle(
        duration: AppMotion.durationBase,
        reverseDuration: AppMotion.durationBase,
        curve: AppMotion.curveEnter,
        reverseCurve: AppMotion.curveExit,
      );

/// Shows [PaneActionsSheet] on the platform's own action surface, per R-33-033's `Pane
/// actions` row: on Android the Material 3 modal bottom sheet, its drag handle, corner,
/// colour and elevation the component's own; on iOS a `CupertinoActionSheet`, the pane title
/// its title and the status line its message. Opens from the terminal screen's overflow
/// control (`08-terminal.md` callout 5) or a long press on an agent row, the "In:" entries the
/// mockup's Navigation section names.
Future<void> showPaneActionsSheet(
  BuildContext context, {
  required String paneTitle,
  required String currentLabel,
  String? agentKind,
  String? agentStatusLine,
  String? visibleScreenText,
  PaneActionsLinkState linkState = PaneActionsLinkState.normal,
  String? linkStateDetail,
  VoidCallback? onTapDiagnostics,
  VoidCallback? onOpenPluginActions,
  ValueChanged<String>? onSplit,
  VoidCallback? onClosePane,
}) async {
  final Widget sheet = PaneActionsSheet(
    paneTitle: paneTitle,
    currentLabel: currentLabel,
    agentKind: agentKind,
    agentStatusLine: agentStatusLine,
    visibleScreenText: visibleScreenText,
    linkState: linkState,
    linkStateDetail: linkStateDetail,
    onTapDiagnostics: onTapDiagnostics,
    onOpenPluginActions: onOpenPluginActions,
    onSplit: onSplit,
    onClosePane: onClosePane,
  );
  if (_isIos) {
    await showCupertinoModalPopup<void>(
      context: context,
      useRootNavigator: true,
      builder: (BuildContext sheetContext) => sheet,
    );
    return;
  }
  final double bottomInset = MediaQuery.viewPaddingOf(context).bottom;
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    sheetAnimationStyle: _sheetAnimationStyle(context),
    builder: (BuildContext sheetContext) => Padding(
      // R-31-10-09: the sheet's height is bounded by the keyboard inset while a keyboard the
      // grid raised (R-03-054) is still up, so `Cancel` stays above it. The keyboard inset
      // already spans the system bar, so the two never add up (measured 2026-09-03).
      padding: EdgeInsets.only(
        bottom: math.max(
          bottomInset,
          MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
      ),
      child: sheet,
    ),
  );
}

/// The sheet's content, per the wireframe, callouts and states table of `docs/31-mockups/
/// 10-pane-actions.md`. See this file's top doc comment for what each row does.
class PaneActionsSheet extends StatelessWidget {
  const PaneActionsSheet({
    super.key,
    required this.paneTitle,
    required this.currentLabel,
    this.agentKind,
    this.agentStatusLine,
    this.visibleScreenText,
    this.linkState = PaneActionsLinkState.normal,
    this.linkStateDetail,
    this.onTapDiagnostics,
    this.onOpenPluginActions,
    this.onSplit,
    this.onClosePane,
  });

  final String paneTitle;

  /// The pane's `label`, for the R-31-10-01 dialog title `Close <label>?`.
  final String currentLabel;
  final String? agentKind;
  final String? agentStatusLine;
  final String? visibleScreenText;
  final PaneActionsLinkState linkState;

  /// The line under the header for a non-`normal` [linkState]. A caller composes the exact
  /// wording; this file only draws it.
  final String? linkStateDetail;
  final VoidCallback? onTapDiagnostics;
  final VoidCallback? onOpenPluginActions;
  final ValueChanged<String>? onSplit;
  final VoidCallback? onClosePane;

  /// Pops the sheet, then fires [callback]. Per the mockup's Navigation section, "every other
  /// action: the sheet closes and the caller stays on screen."
  void _actAndClose(BuildContext context, VoidCallback? callback) {
    Navigator.of(context).pop();
    callback?.call();
  }

  /// `Read the last 20 lines` (callout 7, R-31-10-06): announces through
  /// `SemanticsService.sendAnnouncement`, never the deprecated `announce`, only after
  /// `MediaQuery.supportsAnnounceOf` confirms the platform can carry it, then closes the
  /// sheet. Sends nothing to the pane and changes nothing on the computer.
  void _readLast20Lines(BuildContext context) {
    final String? text = visibleScreenText;
    if (text != null && MediaQuery.supportsAnnounceOf(context)) {
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          _lastTwentyNonEmptyLines(text),
          TextDirection.ltr,
        ),
      );
    }
    Navigator.of(context).pop();
  }

  /// Closes the sheet before the R-33-074 confirmation dialog opens. R-31-10-01 fixes the
  /// title `Close <label>?`, the body and the destructive verb; the platform places the rest.
  Future<void> _closePane(BuildContext context) async {
    final VoidCallback? callback = onClosePane;
    if (callback == null) {
      return;
    }
    final navigator = Navigator.of(context);
    final BuildContext dialogContext = navigator.context;
    final ModalRoute<dynamic>? sheetRoute = ModalRoute.of(context);
    navigator.pop();
    if (sheetRoute != null) {
      await sheetRoute.completed;
    }
    if (!dialogContext.mounted) {
      return;
    }
    final ChromeConfirmationOutcome?
    outcome = await showChromeConfirmationDialog(
      context: dialogContext,
      title: 'Close $currentLabel?',
      body: 'Anything running in this pane stops, and its scrollback is gone.',
      destructiveLabel: 'Close pane',
    );
    if (outcome == ChromeConfirmationOutcome.destructive) {
      callback();
    }
  }

  /// The rows of the wireframe, in its order, as one platform-neutral list: each platform
  /// then draws them with its own control. Section 7.16's groups survive as [_PaneAction.group].
  List<_PaneAction> _actions(BuildContext context) {
    final bool screenReaderOn = MediaQuery.accessibleNavigationOf(context);
    final bool linkNormal = linkState == PaneActionsLinkState.normal;
    return <_PaneAction>[
      // Callout 5 (R-03-055): the pane-scoped plugin actions screen of mockup 18. Local: it
      // opens a screen, and that screen reports the link state itself (R-30-807), so the row
      // is never disabled here.
      _PaneAction(
        group: 0,
        label: 'Plugin actions',
        icon: Symbols.extension_rounded,
        onTap: onOpenPluginActions == null
            ? null
            : () => _actAndClose(context, onOpenPluginActions),
        navigation: true,
      ),
      if (screenReaderOn)
        _PaneAction(
          group: 1,
          label: 'Read the last 20 lines',
          // `Read the last 20 lines` in the R-32-401 map (added 2026-09-08).
          icon: Symbols.text_to_speech_rounded,
          onTap: () => _readLast20Lines(context),
        ),
      for (final (String direction, String label, IconData icon) in [
        ('right', 'Split right', Symbols.splitscreen_right_rounded),
        ('down', 'Split down', Symbols.splitscreen_bottom_rounded),
      ])
        _PaneAction(
          group: 2,
          label: label,
          icon: icon,
          onTap: !linkNormal || onSplit == null
              ? null
              : () => _actAndClose(context, () => onSplit!(direction)),
        ),
      _PaneAction(
        group: 2,
        label: 'Close pane',
        icon: Symbols.delete_outline_rounded,
        destructive: true,
        onTap: !linkNormal || onClosePane == null
            ? null
            : () => unawaited(_closePane(context)),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final bool showLinkLine =
        linkState != PaneActionsLinkState.normal && linkStateDetail != null;
    final Widget? linkLine = showLinkLine
        ? _LinkStateLine(
            linkState: linkState,
            detail: linkStateDetail!,
            onTap: linkState == PaneActionsLinkState.offline
                ? onTapDiagnostics
                : null,
          )
        : null;
    final List<_PaneAction> actions = _actions(context);
    if (_isIos) return _iosSheet(context, actions, linkLine);
    return ConstrainedBox(
      // R-31-10-09: the sheet MUST NOT be asked to draw more than it can fit. The header and
      // Cancel stay put; only the action list between them scrolls past this bound.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Header(
              paneTitle: paneTitle,
              agentKind: agentKind,
              agentStatusLine: agentStatusLine,
            ),
            ?linkLine,
            _buildActionList(context, actions),
            _CancelRow(onTap: () => Navigator.of(context).pop()),
          ],
        ),
      ),
    );
  }

  /// The iOS surface: the platform's own `CupertinoActionSheet`. Its actions carry no glyph,
  /// as the platform's own do; `Close pane` takes `isDestructiveAction`; a disabled action
  /// dims to `opacity.disabled` and ignores the tap. The label takes the interface family, as
  /// `app.dart`'s `actionTextStyle` does for every `CupertinoButton` (R-03-104, R-32-212):
  /// the sheet reads no theme slot, so the family is set on the label.
  Widget _iosSheet(
    BuildContext context,
    List<_PaneAction> actions,
    Widget? linkLine,
  ) {
    Widget label(String text) => Text(
      text,
      style: const TextStyle(fontFamily: AppType.interfaceFontFamily),
    );
    final bool hasStatus = agentKind != null && agentStatusLine != null;
    final Widget? message = hasStatus || linkLine != null
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (hasStatus) label(agentStatusLine!),
              if (hasStatus && linkLine != null)
                const SizedBox(height: AppSpace.space2),
              ?linkLine,
            ],
          )
        : null;
    return CupertinoActionSheet(
      title: label(paneTitle),
      message: message,
      actions: <Widget>[
        for (final _PaneAction action in actions)
          MergeSemantics(
            child: Semantics(
              hint: action.destructive ? 'destructive' : null,
              enabled: action.onTap != null,
              child: action.onTap != null
                  ? CupertinoActionSheetAction(
                      isDestructiveAction: action.destructive,
                      onPressed: action.onTap!,
                      child: label(action.label),
                    )
                  : IgnorePointer(
                      child: Opacity(
                        opacity: _opacityDisabled,
                        child: CupertinoActionSheetAction(
                          isDestructiveAction: action.destructive,
                          onPressed: () {},
                          child: label(action.label),
                        ),
                      ),
                    ),
            ),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.of(context).pop(),
        child: label('Cancel'),
      ),
    );
  }

  /// The Android action list: one `ListTile` per action through `ChromeListRow.sheet`, its
  /// glyph leading, with section 7.16's group divider above every group so the header, each
  /// group and `Cancel` read as separate bands, the way the wireframe draws them. Callout 5's
  /// navigation row opens a screen instead of acting at once.
  Widget _buildActionList(BuildContext context, List<_PaneAction> actions) {
    final AppColor color = AppColor.of(context);
    final List<Widget> rows = <Widget>[];
    int? group;
    for (final _PaneAction action in actions) {
      if (action.group != group) {
        group = action.group;
        rows.add(_GroupDivider(color: color));
      }
      rows.add(
        ChromeListRow.sheet(
          title: action.label,
          leading: Icon(
            action.icon,
            size: AppSize.iconMd,
            color: action.destructive ? color.statusError : color.fgPrimary,
          ),
          onTap: action.onTap,
          destructive: action.destructive,
          navigation: action.navigation,
        ),
      );
    }
    return Flexible(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: rows),
      ),
    );
  }
}

/// One row of the wireframe, before a platform draws it. [onTap] `null` is the disabled
/// state. [group] is the section 7.16 group the row belongs to.
class _PaneAction {
  const _PaneAction({
    required this.group,
    required this.label,
    required this.icon,
    required this.onTap,
    this.destructive = false,
    this.navigation = false,
  });

  final int group;
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool destructive;
  final bool navigation;
}

/// Section 7.16's group divider: `border.hairline` in `color.border.subtle`, full width.
class _GroupDivider extends StatelessWidget {
  const _GroupDivider({required this.color});

  final AppColor color;

  @override
  Widget build(BuildContext context) =>
      Container(height: _hairlineWidth, color: color.borderSubtle);
}

/// Callout 4: the pane title in `type.body.strong`, then — only while the pane holds an
/// agent — the pre-composed status line in `type.caption`/`color.fg.secondary`. `space.4`
/// under the platform's drag handle, `space.3` above the first group divider.
class _Header extends StatelessWidget {
  const _Header({
    required this.paneTitle,
    this.agentKind,
    this.agentStatusLine,
  });

  final String paneTitle;
  final String? agentKind;
  final String? agentStatusLine;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.space4,
        AppSpace.space4,
        AppSpace.space4,
        AppSpace.space3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            paneTitle,
            style: AppType.bodyStrong.copyWith(color: color.fgPrimary),
          ),
          if (agentKind != null && agentStatusLine != null) ...<Widget>[
            const SizedBox(height: AppSpace.space1),
            Text(
              agentStatusLine!,
              style: AppType.caption.copyWith(color: color.fgSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// The line under the header for `hostInUse` (R-30-940) or `offline` (R-30-808): a strip of
/// section 7.22 whose treatment carries the state (R-32-506): `treat.warning` for a computer
/// another phone holds, `treat.error` with its bar for a lost link. Tappable only when [onTap]
/// is given (the offline line's R-30-806 diagnostics route).
class _LinkStateLine extends StatelessWidget {
  const _LinkStateLine({
    required this.linkState,
    required this.detail,
    this.onTap,
  });

  final PaneActionsLinkState linkState;
  final String detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => AppStrip(
    onTapDestination: onTap,
    child: linkState == PaneActionsLinkState.hostInUse
        ? Treatment.warning(label: detail)
        : Treatment.error(label: detail, inStrip: true),
  );
}

/// Callout 8: the fixed `Cancel` row under the scrolling action list, centred,
/// `type.body.strong` in `color.fg.secondary`, behind its own group divider. The platform
/// button sizes itself (R-03-059, 2026-09-09); no box fixes its height.
class _CancelRow extends StatelessWidget {
  const _CancelRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      _GroupDivider(color: AppColor.of(context)),
      AppTextButton(label: 'Cancel', onPressed: onTap, subdued: true),
    ],
  );
}
