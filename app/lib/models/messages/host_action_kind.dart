/// The nine action kinds `host_action.action` accepts
/// (`docs/11-relay-protocol.md` §4.16, R-11-202's mapping table).
/// `server.stop`, `workspace.close`, `tab.close` and the plugin lifecycle
/// actions MUST NOT be reachable here (R-11-204); they are not variants of
/// this enum. Mirrors `HostActionKind` in
/// `crates/herdr-relay-proto/src/messages/action.rs:32-54`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

enum HostActionKind {
  @JsonValue('workspace.create')
  workspaceCreate,
  @JsonValue('tab.create')
  tabCreate,

  /// Create a pane by split. Maps to Herdr's `pane.split`.
  @JsonValue('pane.split')
  paneSplit,

  /// Split an existing pane. Also maps to Herdr's `pane.split`.
  @JsonValue('split')
  split,
  @JsonValue('zoom')
  zoom,
  @JsonValue('close')
  close,
  @JsonValue('rename')
  rename,
  @JsonValue('resize')
  resize,
  @JsonValue('plugin.invoke')
  pluginInvoke,
}
