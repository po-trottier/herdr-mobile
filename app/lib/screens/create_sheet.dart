/// The create menu (`docs/90-implementation-plan.md` `WP-18-d`, `docs/31-mockups/17-create.md`,
/// R-90-010): the grab handle, the header, `New space`, `New tab` and `Split this pane`, the
/// workspace-picker sub-list of `R-31-17-11`, and `Cancel` — every wireframe and state that
/// mockup draws (R-31-17-02, R-31-17-03).
///
/// This file also owns the second checkbox of `WP-18-d`: reconciling an unacknowledged create
/// through `tree_request` before the create control is re-enabled, and never repeating the
/// create (`docs/30-ux-spec.md` R-30-518, R-31-17-07, R-31-17-08). It sends every `host_action`
/// and the reconciling `tree_request` through `pane_actions.dart`'s `createWorkspace`,
/// `createTab`, `createPaneSplit` and `reconcileTree` — this file adds no request/reply
/// plumbing of its own.
///
/// Like `pane_actions_sheet.dart`, this screen holds no dependency on where its data comes
/// from: every field arrives as a plain constructor argument ([snapshot], [currentPaneId],
/// [lastCreatedWorkspaceId], [messages], [connectionState], [send]), and [onCreated] is this
/// sheet's whole contract with routing (R-31-17-10 is a caller concern, not drawn here,
/// R-90-024).
library;

import 'dart:async' show StreamSubscription, unawaited;

import 'package:flutter/material.dart'
    show
        CircularProgressIndicator,
        Colors,
        Icon,
        Radius,
        RoundedRectangleBorder,
        MainAxisSize,
        Navigator,
        showModalBottomSheet,
        BoxConstraints,
        Row;
import 'package:flutter/widgets.dart'
    show
        AnimatedContainer,
        BorderRadius,
        BoxDecoration,
        BuildContext,
        Center,
        Column,
        ConstrainedBox,
        Container,
        CrossAxisAlignment,
        DecoratedBox,
        EdgeInsets,
        ExcludeSemantics,
        Expanded,
        Flexible,
        MediaQuery,
        Padding,
        PopScope,
        SafeArea,
        Semantics,
        SingleChildScrollView,
        SizedBox,
        StatefulWidget,
        State,
        StatelessWidget,
        Text,
        ValueChanged,
        VoidCallback,
        Widget;
import 'package:material_symbols_icons/symbols.dart';

import '../core/result/result.dart' show Result, Ok, Err;
import '../models/message.dart' show Message;
import '../models/messages/pane_summary.dart' show PaneSummary;
import '../models/messages/tree_snapshot.dart' show TreeSnapshot;
import '../models/messages/workspace_summary.dart' show WorkspaceSummary;
import '../services/pane_actions.dart'
    show
        reconcileTree,
        createWorkspace,
        createTab,
        createPaneSplit,
        HostActionOutcome,
        HostActionApplied,
        HostActionRefused,
        HostActionOutcomeUnknown;
import '../services/relay.dart'
    show
        RelayConnectionState,
        RelayConnected,
        RelayRegistrationError,
        RelayRegistrationErrorCode;
import '../widgets/app_list_row.dart';
import '../widgets/app_strip.dart';
import '../widgets/app_text_button.dart';
import '../widgets/theme/app_color.dart';
import '../widgets/theme/app_haptic.dart';
import '../widgets/theme/app_pressable.dart';
import '../widgets/theme/app_radius.dart';
import '../widgets/theme/app_size.dart';
import '../widgets/theme/app_space.dart';
import '../widgets/theme/app_type.dart';
import '../widgets/treatments.dart';

/// Function shape for sending a frame, mirrors `pane_actions.dart`'s own private copy.
typedef SendFrame = void Function(Message message, {String? corr});

/// One outcome of this menu (R-31-17-10): the id of the thing that was just created, so a
/// caller can route to it. This file creates the value; routing itself is a caller's job.
sealed class CreateResult {
  const CreateResult();
}

/// `New space` applied. [workspaceId] is the acknowledgement's `result_id`.
final class CreatedWorkspace extends CreateResult {
  const CreatedWorkspace(this.workspaceId);
  final String workspaceId;
}

/// `New tab` (in either menu state) applied. [tabId] is the acknowledgement's `result_id`.
final class CreatedTab extends CreateResult {
  const CreatedTab(this.tabId);
  final String tabId;
}

/// A split applied. [paneId] is the new pane's `result_id`.
final class CreatedPane extends CreateResult {
  const CreatedPane(this.paneId);
  final String paneId;
}

/// R-31-17-08: the control MUST stay enabled and the menu MUST open with every row disabled
/// while the link is down or another phone holds the computer. Mirrors
/// `device_list_screen.dart`'s own `_LiveConnection`, derived from [RelayConnectionState] the
/// same way.
enum _LiveConnection { connected, hostInUse, offline }

/// Which list the sheet is showing: the main menu, the workspace picker of `R-31-17-11`, or the
/// `Outcome unknown` state that replaces either one (R-30-518). A create in flight is tracked
/// separately, by [_CreateSheetState._loadingRowId], so the list that was open when a row was
/// tapped is still the list shown once that create resolves — `Loading` is not a fourth phase.
enum _Phase { menu, choosingWorkspace, outcomeUnknown }

/// Shows [CreateSheet] as the modal bottom sheet: `radius.lg` top corners and `color.bg.raised`,
/// the same shape `pane_actions_sheet.dart`'s `showPaneActionsSheet` uses. `isDismissible` is
/// `true`, so a scrim tap closes an idle sheet, per callout 4 of `docs/31-mockups/17-create.md`
/// ("A tap on the scrim closes the menu"). The barrier tap reaches the sheet as
/// `Navigator.maybePop`, and `CreateSheet`'s own `PopScope` (`canPop: _loadingRowId == null`)
/// refuses it while a create is in flight, per R-31-17-07. `enableDrag` stays `false`: the flag
/// is fixed at show time, and the drag gesture animates the route directly rather than through
/// `maybePop`, so a drag cannot be gated on `_loadingRowId`. R-31-17-07 lists drag down beside
/// the scrim tap, but the owner rejected only the scrim behaviour; the drag decision is pending.
Future<void> showCreateSheet(
  BuildContext context, {
  required String hostName,
  required TreeSnapshot snapshot,
  String? currentPaneId,
  String? lastCreatedWorkspaceId,
  required Stream<Message> messages,
  required Stream<RelayConnectionState> connectionState,
  required SendFrame send,
  required ValueChanged<CreateResult> onCreated,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    // decided 2026-09-03 by the product owner: a scrim tap dismisses an idle sheet (R-31-17-07);
    // PopScope refuses the tap while a create is in flight. Drag stays off, decision pending.
    isDismissible: true,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (BuildContext context) => CreateSheet(
      hostName: hostName,
      snapshot: snapshot,
      currentPaneId: currentPaneId,
      lastCreatedWorkspaceId: lastCreatedWorkspaceId,
      messages: messages,
      connectionState: connectionState,
      send: send,
      onCreated: onCreated,
    ),
  );
}

/// The sheet's content, per every wireframe and callout of `docs/31-mockups/17-create.md`.
class CreateSheet extends StatefulWidget {
  const CreateSheet({
    super.key,
    required this.hostName,
    required this.snapshot,
    this.currentPaneId,
    this.lastCreatedWorkspaceId,
    required this.messages,
    required this.connectionState,
    required this.send,
    required this.onCreated,
  });

  final String hostName;
  final TreeSnapshot snapshot;
  final String? currentPaneId;
  final String? lastCreatedWorkspaceId;
  final Stream<Message> messages;
  final Stream<RelayConnectionState> connectionState;
  final SendFrame send;
  final ValueChanged<CreateResult> onCreated;

  @override
  State<CreateSheet> createState() => _CreateSheetState();
}

class _CreateSheetState extends State<CreateSheet> {
  late TreeSnapshot _snapshot = widget.snapshot;

  // R-31-17-02: resolved once, from the constructor arguments only, and never re-run against a
  // later snapshot — only the display data ([_paneContext], [_workspaceContext]) below re-reads
  // the live [_snapshot] a `Check now` may have replaced.
  late final String? _paneContextId;
  late final String? _workspaceContextId;

  _Phase _phase = _Phase.menu;
  _LiveConnection _connection = _LiveConnection.connected;

  /// Non-null while a `host_action` this sheet sent is in flight (the `Loading` state of the
  /// states table): identifies which row shows the spinner. Every row but that one disables
  /// while it is set, and `PopScope` refuses the system back gesture and the scrim tap
  /// (R-31-17-07).
  String? _loadingRowId;
  String? _refusalText;
  bool _reconciling = false;

  Future<HostActionOutcome> Function()? _pendingSend;
  CreateResult Function(String resultId)? _pendingToResult;

  StreamSubscription<RelayConnectionState>? _connectionSub;

  @override
  void initState() {
    super.initState();
    final PaneSummary? pane = widget.currentPaneId == null
        ? null
        : widget.snapshot.panes.cast<PaneSummary?>().firstWhere(
            (p) => p?.paneId == widget.currentPaneId,
            orElse: () => null,
          );
    _paneContextId = pane?.paneId;
    _workspaceContextId = pane != null
        ? pane.workspaceId
        : widget.snapshot.workspaces.any(
            (w) => w.workspaceId == widget.lastCreatedWorkspaceId,
          )
        ? widget.lastCreatedWorkspaceId
        : widget.snapshot.workspaces.length == 1
        ? widget.snapshot.workspaces.single.workspaceId
        : null;
    _connectionSub = widget.connectionState.listen(_onConnectionState);
  }

  @override
  void dispose() {
    unawaited(_connectionSub?.cancel());
    super.dispose();
  }

  void _onConnectionState(RelayConnectionState state) {
    final _LiveConnection next = switch (state) {
      RelayConnected() => _LiveConnection.connected,
      RelayRegistrationError(:final code)
          when code == RelayRegistrationErrorCode.hostInUse =>
        _LiveConnection.hostInUse,
      _ => _LiveConnection.offline,
    };
    if (mounted) setState(() => _connection = next);
  }

  /// R-30-951: the gate every row but `New space` shares. `New space` needs only this, per
  /// R-30-951's own "never disabled otherwise".
  bool get _canAct =>
      _connection == _LiveConnection.connected && _loadingRowId == null;

  PaneSummary? get _paneContext => _paneContextId == null
      ? null
      : _snapshot.panes.cast<PaneSummary?>().firstWhere(
          (p) => p?.paneId == _paneContextId,
          orElse: () => null,
        );

  WorkspaceSummary? get _workspaceContext => _workspaceContextId == null
      ? null
      : _snapshot.workspaces.cast<WorkspaceSummary?>().firstWhere(
          (w) => w?.workspaceId == _workspaceContextId,
          orElse: () => null,
        );

  void _start(
    String rowId,
    Future<HostActionOutcome> Function() send,
    CreateResult Function(String resultId) toResult,
  ) {
    _pendingSend = send;
    _pendingToResult = toResult;
    setState(() {
      _loadingRowId = rowId;
      _refusalText = null;
    });
    unawaited(_execute());
  }

  /// `Try again` (callout under the `Error` state): re-runs the exact row [_start] last began,
  /// never a fresh action, per R-31-10-11's non-idempotent-action reasoning that
  /// `pane_actions.dart` already cites.
  void _retry() {
    setState(() {
      _refusalText = null;
    });
    unawaited(_execute());
  }

  Future<void> _execute() async {
    final HostActionOutcome outcome = await _pendingSend!();
    if (!mounted) return;
    switch (outcome) {
      case HostActionApplied(:final ack):
        final String? resultId = ack.resultId;
        if (resultId != null) {
          unawaited(AppHaptic.commit());
          Navigator.of(context).pop();
          widget.onCreated(_pendingToResult!(resultId));
        } else {
          // Defensive: R-11-205 says `result_id` MUST be present on a successful create, but
          // this file never trusts the wire blindly. Treated like a refusal, with no haptic.
          setState(() {
            _loadingRowId = null;
            _refusalText = 'The computer did not return the new id.';
          });
        }
      case HostActionRefused(:final message):
        unawaited(AppHaptic.error());
        setState(() {
          _loadingRowId = null;
          _refusalText = message;
        });
      case HostActionOutcomeUnknown():
        // No haptic and no error styling here, per R-30-518.
        setState(() {
          _loadingRowId = null;
          _phase = _Phase.outcomeUnknown;
        });
    }
  }

  /// `Check now` (R-30-518, R-31-17-07): reads a fresh `tree_snapshot` and never resends the
  /// create. `Err` — a read failure or a second dropped link — keeps the `Outcome unknown`
  /// state, since R-30-518 exempts a read from the no-retry rule but offers no `Try again` of
  /// its own; only another `Check now` press retries it.
  Future<void> _checkNow() async {
    setState(() => _reconciling = true);
    final Result<TreeSnapshot> result = await reconcileTree(
      messages: widget.messages,
      connectionState: widget.connectionState,
      send: widget.send,
    );
    if (!mounted) return;
    switch (result) {
      case Ok<TreeSnapshot>(:final value):
        setState(() {
          _snapshot = value;
          _phase = _Phase.menu;
          _reconciling = false;
        });
      case Err<TreeSnapshot>():
        setState(() => _reconciling = false);
    }
  }

  void _backToMenu() => setState(() => _phase = _Phase.menu);

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    return PopScope(
      canPop: _loadingRowId == null,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: SafeArea(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color.bgRaised,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.lg),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const _GrabHandle(),
                _buildHeader(context),
                if (_connection != _LiveConnection.connected)
                  _connectionBanner(),
                if (_refusalText != null) _errorStrip(context),
                _buildBody(context),
                const _GroupDivider(),
                _CancelRow(
                  onTap: _loadingRowId == null
                      ? () => Navigator.of(context).pop()
                      : () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    if (_phase == _Phase.choosingWorkspace) {
      return _WorkspaceListHeader(
        onBack: _loadingRowId == null ? _backToMenu : null,
      );
    }
    return _Header(hostName: widget.hostName);
  }

  Widget _buildBody(BuildContext context) {
    switch (_phase) {
      case _Phase.outcomeUnknown:
        return _OutcomeUnknownBlock(
          reconciling: _reconciling,
          onCheckNow: _reconciling ? null : () => unawaited(_checkNow()),
        );
      case _Phase.choosingWorkspace:
        return _buildWorkspaceList(context);
      case _Phase.menu:
        return _buildActionList(context);
    }
  }

  Widget _buildActionList(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final bool hasWorkspaces = _snapshot.workspaces.isNotEmpty;
    final WorkspaceSummary? workspaceContext = _workspaceContext;
    // The last row of each group draws no divider of its own (`showDivider: false`): the
    // `_GroupDivider` under it is the one hairline of R-32-545, where two stacked read as a 2 px
    // line (corrected 2026-09-08).
    return Flexible(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _ActionGroup(
              children: <Widget>[
                AppListRow(
                  leading: Icon(
                    Symbols.add_rounded,
                    size: AppSize.iconMd,
                    color: color.fgSecondary,
                  ),
                  primary: 'New space',
                  onTap: _canAct
                      ? () => _start(
                          'newSpace',
                          () => createWorkspace(
                            messages: widget.messages,
                            connectionState: widget.connectionState,
                            send: widget.send,
                          ),
                          CreatedWorkspace.new,
                        )
                      : null,
                  isLoading: _loadingRowId == 'newSpace',
                ),
                if (!hasWorkspaces)
                  AppListRow(
                    leading: Icon(
                      Symbols.add_rounded,
                      size: AppSize.iconMd,
                      color: color.fgSecondary,
                    ),
                    primary: 'New tab',
                    secondary: 'Open a workspace first',
                    onTap: null,
                    showDivider: false,
                  )
                else if (workspaceContext != null)
                  AppListRow(
                    leading: Icon(
                      Symbols.add_rounded,
                      size: AppSize.iconMd,
                      color: color.fgSecondary,
                    ),
                    primary: 'New tab in ${workspaceContext.name}',
                    onTap: _canAct
                        ? () => _start(
                            'newTab',
                            () => createTab(
                              messages: widget.messages,
                              connectionState: widget.connectionState,
                              send: widget.send,
                              workspaceId: workspaceContext.workspaceId,
                            ),
                            CreatedTab.new,
                          )
                        : null,
                    isLoading: _loadingRowId == 'newTab',
                    showDivider: false,
                  )
                else
                  AppListRow(
                    leading: Icon(
                      Symbols.add_rounded,
                      size: AppSize.iconMd,
                      color: color.fgSecondary,
                    ),
                    primary: 'New tab...',
                    onTap: _canAct
                        ? () =>
                              setState(() => _phase = _Phase.choosingWorkspace)
                        : null,
                    isLoading: _loadingRowId == 'newTab',
                    showDivider: false,
                  ),
              ],
            ),
            const _GroupDivider(),
            _ActionGroup(children: _buildSplitRows()),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSplitRows() {
    final AppColor color = AppColor.of(context);
    final PaneSummary? pane = _paneContext;
    if (pane == null) {
      return <Widget>[
        AppListRow(
          leading: Icon(
            Symbols.splitscreen_rounded,
            size: AppSize.iconMd,
            color: color.fgDisabled,
          ),
          primary: 'Split a pane',
          secondary: 'Open a pane first',
          onTap: null,
          showDivider: false,
        ),
      ];
    }
    // ponytail: two-level name fallback (label, then title) only; `07-tree.md` owns the full
    // unnamed-pane display algorithm and is out of scope here.
    final String name = pane.label.isNotEmpty ? pane.label : pane.title;
    return <Widget>[
      AppListRow(
        leading: Icon(
          Symbols.splitscreen_right_rounded,
          size: AppSize.iconMd,
          color: color.fgSecondary,
        ),
        primary: 'Split pane $name right',
        onTap: _canAct
            ? () => _start(
                'splitRight',
                () => createPaneSplit(
                  messages: widget.messages,
                  connectionState: widget.connectionState,
                  send: widget.send,
                  targetPaneId: pane.paneId,
                  direction: 'right',
                ),
                CreatedPane.new,
              )
            : null,
        isLoading: _loadingRowId == 'splitRight',
      ),
      AppListRow(
        leading: Icon(
          Symbols.splitscreen_bottom_rounded,
          size: AppSize.iconMd,
          color: color.fgSecondary,
        ),
        primary: 'Split pane $name down',
        onTap: _canAct
            ? () => _start(
                'splitDown',
                () => createPaneSplit(
                  messages: widget.messages,
                  connectionState: widget.connectionState,
                  send: widget.send,
                  targetPaneId: pane.paneId,
                  direction: 'down',
                ),
                CreatedPane.new,
              )
            : null,
        isLoading: _loadingRowId == 'splitDown',
        showDivider: false,
      ),
    ];
  }

  Widget _buildWorkspaceList(BuildContext context) {
    return Flexible(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final (int index, WorkspaceSummary workspace)
                in _snapshot.workspaces.indexed)
              AppListRow(
                primary: workspace.name,
                secondary:
                    _snapshot.panes
                            .where(
                              (p) => p.workspaceId == workspace.workspaceId,
                            )
                            .length ==
                        1
                    ? '1 pane'
                    : '${_snapshot.panes.where((p) => p.workspaceId == workspace.workspaceId).length} panes',
                onTap: _canAct
                    ? () => _start(
                        'workspace:${workspace.workspaceId}',
                        () => createTab(
                          messages: widget.messages,
                          connectionState: widget.connectionState,
                          send: widget.send,
                          workspaceId: workspace.workspaceId,
                        ),
                        CreatedTab.new,
                      )
                    : null,
                isLoading:
                    _loadingRowId == 'workspace:${workspace.workspaceId}',
                showDivider: index < _snapshot.workspaces.length - 1,
              ),
          ],
        ),
      ),
    );
  }

  Widget _connectionBanner() {
    final String text = _connection == _LiveConnection.hostInUse
        ? 'Another phone is using this computer.'
        : 'Offline. Creating needs the computer.';
    return AppStrip(child: Treatment.warning(label: text));
  }

  /// `treat.error` in a strip draws its own `border.attention` bar (R-32-506); the strip adds
  /// nothing of its own.
  Widget _errorStrip(BuildContext context) {
    final AppColor color = AppColor.of(context);
    return AppStrip(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Treatment.error(label: 'Could not create that.', inStrip: true),
          const SizedBox(height: AppSpace.space2),
          Text(
            _refusalText!,
            style: AppType.monoCode.copyWith(color: color.fgPrimary),
          ),
          const SizedBox(height: AppSpace.space2),
          AppTextButton(label: 'Try again', onPressed: _retry),
        ],
      ),
    );
  }
}

/// The grab handle: `size.grab` at `radius.full` in `color.fg.disabled`, centred, excluded from
/// the semantics tree (R-32-546). Mirrors `pane_actions_sheet.dart`'s own private copy.
class _GrabHandle extends StatelessWidget {
  const _GrabHandle();

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.space2),
      child: Center(
        child: ExcludeSemantics(
          child: Container(
            width: AppSize.grabWidth,
            height: AppSize.grabHeight,
            decoration: BoxDecoration(
              color: color.fgDisabled,
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
          ),
        ),
      ),
    );
  }
}

/// Callout 7: `Create on patrick-desk`, `type.body.strong`, the header of R-32-545 (corrected
/// 2026-09-08: it was `type.heading`, while `pane_actions_sheet.dart` and both rules set
/// `type.body.strong`).
class _Header extends StatelessWidget {
  const _Header({required this.hostName});

  final String hostName;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.space4,
        AppSpace.space2,
        AppSpace.space4,
        AppSpace.space3,
      ),
      child: Text(
        'Create on $hostName',
        style: AppType.bodyStrong.copyWith(color: color.fgPrimary),
      ),
    );
  }
}

/// Callout 16's own header: the back chevron and `New tab in which space?`, replacing [_Header]
/// while the workspace list is open.
class _WorkspaceListHeader extends StatelessWidget {
  const _WorkspaceListHeader({required this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.space2,
        AppSpace.space2,
        AppSpace.space4,
        AppSpace.space3,
      ),
      child: Row(
        children: <Widget>[
          _BackControl(onTap: onBack),
          Expanded(
            child: Text(
              'New tab in which space?',
              style: AppType.bodyStrong.copyWith(color: color.fgPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// The back chevron of [_WorkspaceListHeader]: the leading control glyph of R-32-510 at
/// `size.icon.lg` in a `size.target.min` target, pressed through the shared [AppPressable]
/// (R-32-501's third case, R-32-609): `color.bg.high` at `radius.sm` on pointer-down, with the
/// wrapper's own scale, timing and reduce-motion handling. [onTap] `null` leaves the control
/// inert while a create is in flight.
class _BackControl extends StatelessWidget {
  const _BackControl({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    return Semantics(
      label: 'Back',
      button: true,
      enabled: onTap != null,
      excludeSemantics: true,
      child: AppPressable(
        onTap: onTap,
        builder: (BuildContext context, bool pressed) => AnimatedContainer(
          duration: AppPressable.fillDuration(context, pressed),
          curve: AppPressable.fillCurve(context),
          width: AppSize.targetMin,
          height: AppSize.targetMin,
          decoration: BoxDecoration(
            color: pressed ? color.bgHigh : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Icon(
            Symbols.chevron_left_rounded,
            size: AppSize.iconLg,
            color: color.fgPrimary,
          ),
        ),
      ),
    );
  }
}

/// One group of [AppListRow]s with no divider of its own, mirroring `pane_actions_sheet.dart`'s
/// own private copy.
class _ActionGroup extends StatelessWidget {
  const _ActionGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, children: children);
}

/// `border.hairline` in `color.border.subtle`, full width, between two groups (R-32-545).
class _GroupDivider extends StatelessWidget {
  const _GroupDivider();

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    return Container(height: AppBorder.hairline, color: color.borderSubtle);
  }
}

/// The `Outcome unknown` state (R-30-518): two sentences, then `Check now`, never `Try again`,
/// and no `treat.error`. Mirrors `device_list_screen.dart`'s own private copy of the same
/// state, but replaces the whole action list rather than sitting above it, per this mockup's
/// own States table.
class _OutcomeUnknownBlock extends StatelessWidget {
  const _OutcomeUnknownBlock({
    required this.reconciling,
    required this.onCheckNow,
  });

  final bool reconciling;
  final VoidCallback? onCheckNow;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    return AppStrip(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'This phone did not get an answer.',
            style: AppType.body.copyWith(color: color.fgPrimary),
          ),
          Text(
            'The change may already be done.',
            style: AppType.body.copyWith(color: color.fgPrimary),
          ),
          const SizedBox(height: AppSpace.space3),
          reconciling
              ? const SizedBox(
                  width: AppSize.spinner,
                  height: AppSize.spinner,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : AppTextButton(label: 'Check now', onPressed: onCheckNow),
        ],
      ),
    );
  }
}

/// The sheet-level `Cancel` row (callout 11, R-32-545): centred, `type.body.strong` in
/// `color.fg.secondary` as written, the same quiet row `pane_actions_sheet.dart` draws under its
/// list (aligned 2026-09-08; it was the upper-case accent text action of R-32-526, which read as
/// a third button style on one sheet). The button keeps the platform's own height: no box around
/// it (2026-09-09, the R-03-059 addendum; it sat in a `size.button.primary` box). [onTap] is a
/// no-op while a create is in flight rather than this widget disabling itself, per the
/// `Loading` state's own wording ("refuses every dismissal path").
class _CancelRow extends StatelessWidget {
  const _CancelRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) =>
      AppTextButton(label: 'Cancel', onPressed: onTap, subdued: true);
}
