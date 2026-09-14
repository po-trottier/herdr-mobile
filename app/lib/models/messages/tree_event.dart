/// The Herdr event that triggered a `tree_update`
/// (`docs/11-relay-protocol.md` §4.5, R-11-047's exact subscription set).
/// Mirrors `TreeEvent` in
/// `crates/herdr-relay-proto/src/messages/tree.rs:87-117`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

enum TreeEvent {
  @JsonValue('workspace.created')
  workspaceCreated,
  @JsonValue('workspace.updated')
  workspaceUpdated,
  @JsonValue('workspace.renamed')
  workspaceRenamed,
  @JsonValue('workspace.closed')
  workspaceClosed,
  @JsonValue('tab.created')
  tabCreated,
  @JsonValue('tab.closed')
  tabClosed,
  @JsonValue('tab.renamed')
  tabRenamed,
  @JsonValue('tab.focused')
  tabFocused,
  @JsonValue('pane.created')
  paneCreated,
  @JsonValue('pane.closed')
  paneClosed,
  @JsonValue('pane.updated')
  paneUpdated,
  @JsonValue('pane.focused')
  paneFocused,
  @JsonValue('pane.agent_status_changed')
  paneAgentStatusChanged,
  @JsonValue('layout.updated')
  layoutUpdated,
}
