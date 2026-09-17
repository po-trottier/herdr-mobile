# 40 — Repository Tooling

> **Scope.** This document owns the repository layout, the agent-facing guidance surface, the
> documentation validation commands and the future implementation tree. As of Phase 0, `crates/`
> and `app/` are real; §3.1.1 tracks what exists. It still holds no task runner and no generated
> API artifact.

## 1. Agent-Facing Repository Setup

This repository is omp-centric and MUST also work for OpenAI Codex and Claude Code, with **no
duplicated guidance text**. The layout below is decided and MUST NOT be changed without an ADR.

### 1.1 The decided layout

| File | Read by | Content |
| --- | --- | --- |
| `AGENTS.md` | omp, Codex, Cursor, Gemini CLI, Aider, Jules, Zed, goose, opencode, Warp, Copilot coding agent, and about 30 more | **The single source of standing agent guidance.** Complete and self-contained. |
| `CLAUDE.md` | Claude Code only | A pointer. The literal line `@AGENTS.md`, then an optional short Claude-only note. It holds no guidance of its own. |

Nothing else. There is no `.omp/RULES.md`, no `.omp/AGENTS.md`, no `.cursor/rules/`, no
`.github/copilot-instructions.md`, and no `GEMINI.md`.

### 1.2 Why exactly this

- `AGENTS.md` is the open format for agent instructions, used by more than 60000 public repositories
  and stewarded by the Agentic AI Foundation under the Linux Foundation. Source: `https://agents.md/`.
- **Codex reads `AGENTS.md` as plain text and does not expand `@` imports.** It walks the directory
  tree and concatenates the files it finds, and it truncates at `project_doc_max_bytes`, which
  defaults to 32 KiB. Therefore `AGENTS.md` MUST be self-contained, MUST NOT rely on an `@` import to
  deliver a rule, and MUST stay well under 32 KiB. Sources:
  `https://developers.openai.com/codex/guides/agents-md` and `https://agents.md/`.
- **Claude Code reads `CLAUDE.md`, not `AGENTS.md`.** Its own documentation gives the
  no-duplication pattern: a `CLAUDE.md` that imports `@AGENTS.md`, with any Claude-specific text
  below the import. Source: `https://code.claude.com/docs/en/memory`.
- **A symlink is the other documented option, and it is rejected here.** Claude's documentation says
  a symlink needs Administrator privileges or Developer Mode on Windows and tells a Windows user to
  use the `@AGENTS.md` import instead. This project is developed on Windows, and a Git symlink
  checked out without `core.symlinks` becomes a plain text file that holds a path, which silently
  breaks the pointer. The import works everywhere and needs no privilege. Source:
  `https://code.claude.com/docs/en/memory`.
- **omp reads the standalone root `AGENTS.md`** through its `agents-md` discovery provider, which
  walks up from the working directory to the repository root. So the one file that Codex needs is
  already the file omp loads.
- **`.omp/RULES.md` was deleted on purpose.** Every rule it held was a standing project rule that
  Codex and Claude also need, so keeping it meant holding the same text in two files. omp gains a
  sticky always-apply rule from it, but a rule that only one of three harnesses can see is worse than
  a rule with no sticky reinforcement. Reliability beats reinforcement. Making `.omp/RULES.md` an
  `@../AGENTS.md` import was also rejected: omp would then inject `AGENTS.md` twice in one session,
  once as a context file and once as a sticky rule.

### 1.3 Rules

**R-40-001** This repository MUST contain a root `AGENTS.md`. **Rationale:** the `agents-md` provider
discovers it at priority 10 and injects it into every OMP session that starts inside this repository,
and Codex discovers it by walking the directory tree.

**R-40-002** This repository MUST NOT contain `.omp/AGENTS.md`. **Rationale:** the `native` provider
discovers it at priority 100 and it shadows the root `AGENTS.md` completely, so the root file would
never load.

**R-40-003** `AGENTS.md` MUST be the single, self-contained source of standing agent guidance. It
MUST NOT use an `@` import to deliver a rule, because Codex does not expand one. **Rationale:**
Codex concatenates files as plain text. An `@` import that expands on other harnesses is invisible
to Codex, so any rule inside it is missing from the largest audience.

**R-40-004** `AGENTS.md` MUST stay under 32 KiB on disk, targeting under 400 lines. **Rationale:**
Codex truncates a project document at `project_doc_max_bytes`, which defaults to 32 KiB. A
truncated file drops tail rules without warning.

**R-40-005** `CLAUDE.md` MUST hold the literal line `@AGENTS.md` and an optional short Claude-only
note. It MUST hold no guidance of its own. **Rationale:** the no-duplication rule. Claude Code
expands the `@` import and reads `AGENTS.md` through it. Any guidance written in `CLAUDE.md` silos
it from the 30 other agents.

**R-40-006** To support one more agent that cannot read `AGENTS.md`, add a **pointer** file for it.
Never add a copy. Record the addition in the `AGENTS.md` compatibility section. **Rationale:** a
copy silos a rule from the main file, and a stale copy is worse than no copy.

**R-40-007** This repository MUST NOT carry `.omp/RULES.md`. It was deleted. **Rationale:** every
rule it held duplicated `AGENTS.md`, Codex does not expand `@` imports, and a duplication is
worse than a missing sticky rule. See §1.2 for the full evidence.

**R-40-008** This repository MUST NOT carry `.omp/skills/` in v1. **Rationale:** a skill that only
repeats a document is waste. Every fact an agent needs lives in `docs/` and `AGENTS.md`. The reuse
ladder says: if the knowledge already exists in a document, a skill adds cost without value. Add a
skill only when a workflow needs to be triggered by task context and cannot be expressed as a
document. The `feature-worktree` skill in `herdr-sidebar` earns its place because it is a multi-step
Herdr pane workflow, not a document. No workflow in this repository has that shape yet.

**R-40-009** This repository MUST NOT carry `.omp/rules/` in v1. **Rationale:** regular non-sticky
rule files under `.omp/rules/` are for conditional or opt-in rules with `applyTo` globs. No rule in
this repository needs conditional application. Everything is persistent context (`AGENTS.md`). Add
`.omp/rules/` only when a rule must apply to a specific file glob, not the whole repository.

**R-40-010** A file under `.omp/rules/` MUST NOT be named `RULES.md`. **Rationale:** native regular
rules load earlier and would shadow a sticky `RULES.md` candidate. This is a verified OMP constraint.

**R-40-011** This repository MUST NOT carry `.agents/` or `.codex/` directories. **Rationale:**
`herdr-scheduled` carries both, but both are empty. The `.codex/` provider discovers only
`~/.codex/AGENTS.md` at user scope, not a project-level file, so a project `.codex/` directory does
nothing for OMP. The `.agents/` provider discovers `.agents/AGENTS.md` at priority 70, which would
shadow the root `AGENTS.md` (priority 10) at the same depth. An empty `.agents/` directory
contributes nothing. Carrying either directory adds clutter without value.

**R-40-012** `AGENTS.md` MUST NOT use `@` to import any file under `docs/`. **Rationale:** every
`docs/` file is large. Codex does not expand `@` imports anyway. For every other harness, use a
plain path reference instead.

### 1.4 Boundaries between the human and agent guidance files

**R-40-013** `README.md` is for humans: what the product is, how the documents are organised, how to
contribute. `AGENTS.md` is for agents: conventions, ownership, validation commands, traps. Overlap
is limited to a one-paragraph product summary; everything else lives in one file only.
**Rationale:** a human needs the product story and the entry point. An agent needs the rules and the
layout. A file that serves both serves neither well.

**R-40-014** `CONTRIBUTING.md` is for a human contributor's process: ownership map, rule-id
convention, source citation format, the ADR process and the validation commands. `AGENTS.md` cites
it rather than restating the process. **Rationale:** `CONTRIBUTING.md` is the procedure; `AGENTS.md`
is the standing knowledge. They share only the validation command table.

## 2. House Style From Sibling Repositories

### 2.1 What was read

Two reference repositories were read:

- `herdr-scheduled` — a mature Herdr plugin. POSIX shell plus PowerShell, no build step.
- `herdr-standalone` — the Herdr desktop application. C# / .NET 8.0 / WPF, xUnit tests, Inno Setup
  installer.

### 2.2 Conventions worth copying (future implementation)

The rules below apply to the future implementation phase. None of them can be verified yet: Phase 0
built the Rust workspace and the Flutter project skeleton, but the plugin shim layout these rules
describe is a later phase's work.

**R-40-015** The future plugin MUST follow the `herdr-scheduled` directory split: `posix/` for
launcher shims, `windows/` for PowerShell launcher shims. **Rationale:** this is the proven layout.
The shim is at most five lines; the Rust binary owns every behaviour. The plugin manifest gates each
shim by the `platforms` key.

**R-40-016** Every shim MUST locate its root through `HERDR_PLUGIN_ROOT`, never through a relative
path. **Rationale:** Herdr resolves a relative program against its own install directory on Windows
(GH #58) and the working directory of an action is not reliable. This is documented in
`herdr-scheduled/herdr-plugin.toml` lines 7-11 and
`herdr-default-layout/herdr-plugin.toml` lines 14-18.

**R-40-017** Action ids MUST be unique per manifest. The Windows variant MUST carry a `-windows`
suffix. **Rationale:** `herdr-scheduled` and `herdr-default-layout` both use this convention. It is
the established pattern.

**R-40-018** The `.gitattributes` file MUST pin line endings before the first commit. Shell scripts
MUST stay LF on every platform. PowerShell scripts MUST stay CRLF. **Rationale:** a CRLF checkout
breaks the shebang on macOS and Linux. This repository already has `.gitattributes` at the root.
See `docs/41-code-standards.md` for the full line-ending and lint configuration.

**R-40-019** The repository MUST NOT add a lint or format rule that `docs/41-code-standards.md` does
not specify. **Rationale:** `docs/41-code-standards.md` owns line endings, formatters and lint rules.
This document cites it and does not duplicate it.

## 3. Repository Layout

### 3.1 This repository, now

This repository holds specification and planning documents, the guidance surface, and the brand
assets in `assets/`. §3.1.1 below tracks what Phase 0 has since added beside this tree.

```text
herdr-mobile/
├── README.md                          # For humans: overview, document map, how to contribute
├── AGENTS.md                          # For agents: conventions, ownership, traps, commands
├── CLAUDE.md                          # Pointer: @AGENTS.md
├── CONTRIBUTING.md                    # Human contributor process: ownership, rule ids,
│                                       #   source citation format, ADR process, validation commands
├── SECURITY.md                        # Public security-reporting route, supported-version table
├── LICENSE                            # Apache License 2.0 (canonical text)
├── .markdownlint-cli2.jsonc           # markdownlint config: MD013 100 cols, relaxations
├── .editorconfig                      # UTF-8, LF, final newline, Markdown trailing space
├── .gitattributes                     # LF for every text file; images marked binary
├── .gitignore                         # Documentation-authoring output and editor or OS files only
├── assets/                            # Brand art. Not documentation, so it sits at the root
│   └── icon/
│       ├── src/                       # Published remote icon (remote.svg, remote.png)
│       │                              #   raster companions, notification and tile references
│       └── export/                    # Generated. Never hand-edited. See docs/32 R-32-422
│           └── store/                 #   play-store-512.png
└── docs/                              # Every design decision and specification
    ├── 00-overview.md                 # Product purpose, components, requirements
    ├── 01-architecture.md             # Cross-document ownership index and data flow
    ├── 02-herdr-probe-results.md      # Measured Herdr socket facts
    ├── 03-product-decisions.md        # User-set product policy
    ├── 10-herdr-integration.md        # Plugin-to-Herdr integration
    ├── 11-relay-protocol.md           # Wire protocol between Host, relay and Device
    ├── 12-relay-hosting.md            # Relay architecture and hosting requirements
    ├── 13-security-pairing.md         # Cryptography, pairing, identity, revocation, secret storage
    ├── 14-relay-deployment.md         # The supported public deployment profile
    ├── 15-nvidia-brev-relay-experiment.md  # Internal Brev experiment and its gate
    ├── 20-mobile-framework.md         # Framework decision and app stack
    ├── 21-terminal-rendering.md       # Terminal emulator, render strategy, font
    ├── 22-platform-integration.md     # Keystore, biometrics, local notifications, deep links
    ├── 23-public-release.md           # App-store metadata, release tracks, signing, versioning
    ├── 30-ux-spec.md                  # UX specification
    ├── 31-mockups/                    # One ASCII wireframe per screen
    │   ├── 01-welcome.md
    │   ├── 02-pair-scan.md
    │   ├── 03-pair-code.md
    │   ├── 04-lock.md
    │   ├── 05-host-list.md
    │   ├── 06-agent-list.md
    │   ├── 07-notifications.md
    │   ├── 08-terminal.md
    │   ├── 09-key-row.md
    │   ├── 10-pane-actions.md
    │   ├── 11-prompt-composer.md
    │   ├── 12-notifications.md
    │   ├── 13-connection.md
    │   ├── 14-devices.md
    │   ├── 15-appearance.md
    │   ├── 16-host-popup.md
    │   ├── 17-create.md
    │   ├── 18-actions.md
    │   ├── 19-about.md
    │   └── 20-status-legend.md
    ├── 32-design-language.md          # Design tokens: colour, motion, space, type, chrome
    ├── 33-platform-chrome.md          # Per-platform chrome: plain Cupertino, Material You
    ├── 40-repo-tooling.md             # This file
    ├── 41-code-standards.md           # Coding rules, formatters, linters, anti-patterns
    ├── 90-implementation-plan.md      # Ordered implementation checklist
    └── decisions/                     # Architecture Decision Records
        ├── ADR-001-plugin-stays-in-monorepo.md
        ├── ADR-002-bridge-is-rust.md
        ├── ADR-003-rust-host-and-relay.md
        ├── ADR-004-pairing-phrase-and-routing.md
        ├── ADR-005-local-notifications-only.md
        └── ADR-006-agent-instruction-files.md
```

There is still no `plugins/`, no `hub/`, no `justfile`, no `.omp/` file, no `go.mod` and no
`.herdr-api-schema.json` in this repository. The Herdr socket API schema is obtained at runtime
with `herdr api schema --json`. It is never a committed file.

#### 3.1.1 As of Phase 0

Phase 0 of `docs/90-implementation-plan.md` has landed alongside the tree above:

```text
herdr-mobile/
├── .github/                           # dependabot.yml, workflows/ci.yml
├── crates/                            # Cargo workspace: Cargo.toml, rust-toolchain.toml
│   ├── herdr-relay/                   # Cargo.toml, src/main.rs
│   ├── herdr-relay-hub/               # Cargo.toml, Dockerfile, src/main.rs
│   └── herdr-relay-proto/             # Cargo.toml, src/lib.rs and six sibling module stubs
└── app/                               # pubspec.yaml, analysis_options.yaml, android/, ios/
    └── lib/main.dart
```

Every other path under `crates/` or `app/` is still a later phase's target; §3.2 lists the full
target tree. `docs/90-implementation-plan.md` §5.3 names the one owning work package for every path
above. A further code change follows that plan's phase, wave and work-package process, never this
document.

### 3.2 The future implementation tree

The tree below is still mostly a target. Phase 0 has already created the workspace and project
skeleton that §3.1.1 lists; every other path here is a future file that a later implementation
phase creates. The Rust workspace shares one protocol crate (`herdr-relay-proto`) between the
plugin and the relay, so the wire types, close-code enum, error taxonomy, routing-handle codec and
pairing-phrase codec are defined once and verified by compilation in both consumers.

The CI workflow and the Rust and Flutter toolchains exist as of Phase 0 (§3.1.1). There is still no
task runner; the implementation phase adds none.

#### 3.2.1 Rust workspace (`crates/`)

```text
crates/
├── Cargo.toml
├── rust-toolchain.toml
├── herdr-relay-proto/
│   ├── Cargo.toml
│   ├── src/
│   │   ├── lib.rs
│   │   ├── codes.rs
│   │   ├── frame.rs
│   │   ├── handle.rs
│   │   ├── messages.rs
│   │   ├── messages/
│   │   │   ├── action.rs
│   │   │   ├── control.rs
│   │   │   ├── device.rs
│   │   │   ├── input.rs
│   │   │   ├── session.rs
│   │   │   ├── status.rs
│   │   │   ├── tree.rs
│   │   │   └── watch.rs
│   │   ├── phrase.rs
│   │   └── test_vectors.rs
│   └── tests/
│       ├── handle.rs
│       └── vectors.rs
├── herdr-relay/
│   ├── Cargo.toml
│   ├── herdr-plugin.toml
│   ├── src/
│   │   ├── main.rs
│   │   ├── config.rs
│   │   ├── control.rs
│   │   ├── ipc.rs
│   │   ├── ipc/
│   │   │   ├── client.rs
│   │   │   ├── discover.rs
│   │   │   ├── subscription.rs
│   │   │   └── transport.rs
│   │   ├── keys.rs
│   │   ├── keybind.rs
│   │   ├── process.rs
│   │   ├── noise.rs
│   │   ├── pairing.rs
│   │   ├── pairing/
│   │   │   └── wordlist.rs
│   │   ├── popup.rs
│   │   ├── relay.rs
│   │   ├── store.rs
│   │   ├── watch.rs
│   │   ├── watch/
│   │   │   ├── bridge.rs
│   │   │   ├── devices.rs
│   │   │   ├── events.rs
│   │   │   ├── herdr_calls.rs
│   │   │   ├── incoming.rs
│   │   │   ├── latest_slot.rs
│   │   │   ├── raw.rs
│   │   │   ├── requests.rs
│   │   │   ├── run_loop.rs
│   │   │   └── scheduler.rs
│   │   └── bin/
│   │       ├── spike-read.rs
│   │       └── spike-subscribe.rs
│   ├── posix/
│   │   ├── run.sh
│   │   ├── ensure-service.sh
│   │   ├── relayctl.sh
│   │   ├── ui.sh
│   │   └── common.sh
│   ├── windows/
│   │   ├── run.ps1
│   │   ├── ensure-service.ps1
│   │   ├── relayctl.ps1
│   │   ├── ui.ps1
│   │   └── common.ps1
│   └── tests/
│       ├── debounce.rs
│       ├── hmac_blake2s_vectors.json
│       ├── hmac_blake2s_vectors.rs
│       ├── input_map.rs
│       ├── one_pane.rs
│       ├── phrase_expiry.rs
│       ├── poll_timer.rs
│       ├── popup_once.rs
│       ├── reject_unknown.rs
│       ├── revision_gate.rs
│       ├── revoke.rs
│       ├── revoke_all.rs
│       ├── posix/
│       │   └── test-ensure-service.sh
│       └── windows/
│           ├── test-ensure-service.ps1
│           └── test-plugin-root.ps1
└── herdr-relay-hub/
    ├── Cargo.toml
    ├── Dockerfile
    ├── src/
    │   ├── main.rs
    │   ├── heartbeat.rs
    │   ├── lib.rs
    │   ├── relay.rs
    │   ├── routes.rs
    │   └── session.rs
    └── tests/
        ├── ciphertext_only.rs
        ├── forward_verbatim.rs
        ├── handle_isolation.rs
        ├── integration.rs
        ├── latency.rs
        ├── limits.rs
        ├── load.rs
        ├── log_fields.rs
        ├── one_device.rs
        └── support/
            └── mod.rs
```

#### 3.2.2 Flutter app (`app/`)

```text
app/
├── pubspec.yaml
├── analysis_options.yaml
├── LICENSE
├── assets/
│   ├── brand/
│   │   └── ram.png
│   ├── fonts/
│   │   ├── Archivo-Black.ttf
│   │   ├── Archivo-Bold.ttf
│   │   ├── IBMPlexSans-Regular.ttf
│   │   ├── IBMPlexSans-SemiBold.ttf
│   │   ├── JetBrainsMonoNerdFontMono-Bold.ttf
│   │   ├── JetBrainsMonoNerdFontMono-BoldItalic.ttf
│   │   ├── JetBrainsMonoNerdFontMono-Italic.ttf
│   │   └── JetBrainsMonoNerdFontMono-Regular.ttf
│   └── wordlists/
│       └── eff_large_wordlist.txt
├── lib/
│   ├── app.dart
│   ├── main.dart
│   ├── routing.dart
│   ├── core/
│   │   └── result/
│   │       └── result.dart
│   ├── models/
│   │   ├── char_width.dart
│   │   ├── codes.dart
│   │   ├── frame.dart
│   │   ├── message.dart
│   │   ├── sgr_counter.dart
│   │   └── messages/
│   │       ├── action_list_entry.dart
│   │       ├── action_list_request.dart
│   │       ├── action_list.dart
│   │       ├── agent_prompt_ack.dart
│   │       ├── agent_prompt.dart
│   │       ├── agent_status_kind.dart
│   │       ├── agent_status.dart
│   │       ├── agent_summary.dart
│   │       ├── device_info.dart
│   │       ├── device_list_entry.dart
│   │       ├── device_list_request.dart
│   │       ├── device_list.dart
│   │       ├── disconnect.dart
│   │       ├── error_message.dart
│   │       ├── host_action_ack.dart
│   │       ├── host_action_kind.dart
│   │       ├── host_action.dart
│   │       ├── host_info.dart
│   │       ├── mark_seen.dart
│   │       ├── pane_frame.dart
│   │       ├── pane_scroll_state.dart
│   │       ├── pane_summary.dart
│   │       ├── platform.dart
│   │       ├── revoke_device.dart
│   │       ├── revoke_result.dart
│   │       ├── scroll_offsets.dart
│   │       ├── scroll_request.dart
│   │       ├── scroll_response.dart
│   │       ├── send_input_ack.dart
│   │       ├── send_input.dart
│   │       ├── tab_summary.dart
│   │       ├── tree_event.dart
│   │       ├── tree_request.dart
│   │       ├── tree_snapshot.dart
│   │       ├── tree_update.dart
│   │       ├── unwatch_pane.dart
│   │       ├── watch_ack.dart
│   │       ├── watch_pane.dart
│   │       └── workspace_summary.dart
│   ├── screens/
│   │   ├── about_screen.dart
│   │   ├── actions_screen.dart
│   │   ├── agent_list_screen.dart
│   │   ├── app_shell.dart
│   │   ├── connection_screen.dart
│   │   ├── create_sheet.dart
│   │   ├── device_detail_screen.dart
│   │   ├── device_list_screen.dart
│   │   ├── host_list_screen.dart
│   │   ├── lock_screen.dart
│   │   ├── manual_pairing_screen.dart
│   │   ├── notification_settings_screen.dart
│   │   ├── notifications_screen.dart
│   │   ├── pane_actions_sheet.dart
│   │   ├── pane_switcher_sheet.dart
│   │   ├── prompt_composer.dart
│   │   ├── qr_scan_screen.dart
│   │   ├── settings_screen.dart
│   │   ├── status_legend_screen.dart
│   │   ├── terminal_screen.dart
│   │   └── welcome_screen.dart
│   ├── services/
│   │   ├── agent_list.dart
│   │   ├── agent_status.dart
│   │   ├── app_settings.dart
│   │   ├── biometric_gate.dart
│   │   ├── camera_zoom.dart      # Owner: CameraZoom (R-90-018)
│   │   ├── chord_latch.dart
│   │   ├── composer.dart
│   │   ├── connectivity.dart
│   │   ├── contrast_assert.dart
│   │   ├── device_list.dart
│   │   ├── draft_store.dart
│   │   ├── frame_codec.dart
│   │   ├── hmac_blake2s.dart
│   │   ├── host_actions.dart
│   │   ├── host_list.dart
│   │   ├── keystore.dart
│   │   ├── noise.dart
│   │   ├── notifications.dart
│   │   ├── origin.dart
│   │   ├── pairing.dart
│   │   ├── pane_actions.dart
│   │   ├── plain_store.dart
│   │   ├── prediction_engine.dart  # WP-16-a, R-21-043's engine (R-90-018)
│   │   ├── reconnect_policy.dart
│   │   ├── relay.dart
│   │   ├── terminal.dart
│   │   └── tree.dart
│   └── widgets/
│       ├── app_filled_button.dart
│       ├── app_ghost_button.dart
│       ├── app_ground.dart  # EmptyMark only since 2026-09-09 (R-32-334 retired)
│       ├── app_list_row.dart
│       ├── app_section_header.dart
│       ├── app_strip.dart
│       ├── app_text_button.dart
│       ├── brand_mark.dart
│       ├── eyebrow.dart
│       ├── ground_grid.dart
│       ├── input_field.dart
│       ├── key_row.dart
│       ├── status_dot.dart
│       ├── status_strip.dart
│       ├── terminal_view_widget.dart
│       ├── treatments.dart
│       └── theme/
│           ├── app_color.dart
│           ├── app_elev.dart
│           ├── app_haptic.dart
│           ├── app_live_dot.dart
│           ├── app_motion.dart
│           ├── app_radius.dart
│           ├── app_size.dart
│           ├── app_space.dart
│           ├── app_type.dart
│           ├── chrome_compose_task.dart
│           ├── chrome_confirmation_dialog.dart
│           ├── chrome_confirmation_outcome.dart
│           ├── chrome_contrast_preference.dart
│           ├── chrome_gesture_timing.dart
│           ├── chrome_list_row.dart
│           ├── chrome_loading_delay.dart
│           ├── chrome_scheme_source.dart
│           ├── chrome_scheme.dart
│           ├── chrome_settings_section.dart
│           ├── chrome_transient_timeout.dart
│           ├── chrome_transparency.dart
│           └── chrome_working_icon_motion.dart
├── test/
│   ├── routing_stack_test.dart
│   ├── routing_test.dart
│   ├── a11y/
│   │   ├── reduce_motion_test.dart
│   │   ├── text_scale_test.dart
│   │   └── touch_target_test.dart
│   ├── config/
│   │   ├── app_identity_test.dart
│   │   └── store_icon_test.dart
│   ├── e2e/
│   │   └── full_stack_test.dart
│   ├── fixtures/
│   │   └── pane-50row.ansi
│   ├── models/
│   │   ├── char_width_test.dart
│   │   ├── frame_size_test.dart
│   │   ├── ping_response_test.dart
│   │   └── vectors_test.dart
│   ├── screens/
│   │   ├── about_screen_golden_test.dart
│   │   ├── about_screen_test.dart
│   │   ├── actions_screen_golden_test.dart
│   │   ├── actions_screen_test.dart
│   │   ├── agent_list_screen_golden_test.dart
│   │   ├── agent_list_screen_test.dart
│   │   ├── app_shell_golden_test.dart
│   │   ├── app_shell_test.dart
│   │   ├── connection_screen_actions_test.dart
│   │   ├── connection_screen_golden_test.dart
│   │   ├── connection_screen_test.dart
│   │   ├── create_sheet_golden_test.dart
│   │   ├── create_sheet_test.dart
│   │   ├── device_detail_screen_golden_test.dart
│   │   ├── device_list_screen_golden_test.dart
│   │   ├── device_list_screen_test.dart
│   │   ├── golden_support.dart
│   │   ├── host_list_screen_golden_test.dart
│   │   ├── host_list_screen_test.dart
│   │   ├── lock_screen_golden_test.dart
│   │   ├── lock_screen_test.dart
│   │   ├── manual_pairing_screen_test.dart
│   │   ├── no_gesture_sends_test.dart
│   │   ├── notification_settings_screen_golden_test.dart
│   │   ├── notification_settings_screen_test.dart
│   │   ├── notifications_screen_golden_test.dart
│   │   ├── notifications_screen_test.dart
│   │   ├── pane_actions_sheet_golden_test.dart
│   │   ├── pane_actions_sheet_test.dart
│   │   ├── pane_switcher_sheet_golden_test.dart
│   │   ├── pane_switcher_sheet_test.dart
│   │   ├── prompt_composer_golden_test.dart
│   │   ├── prompt_composer_test.dart
│   │   ├── qr_scan_screen_test.dart
│   │   ├── settings_screen_golden_test.dart
│   │   ├── settings_screen_test.dart
│   │   ├── single_tap_sends_nothing_test.dart
│   │   ├── status_legend_screen_golden_test.dart
│   │   ├── status_legend_screen_test.dart
│   │   ├── terminal_screen_test.dart
│   │   ├── welcome_screen_test.dart
│   │   └── goldens/  # 172 masters as of 2026-09-09, named per section 3.3
│   ├── services/
│   │   ├── agent_list_test.dart
│   │   ├── agent_status_test.dart
│   │   ├── app_settings_test.dart
│   │   ├── biometric_gate_test.dart
│   │   ├── composer_test.dart
│   │   ├── device_list_test.dart
│   │   ├── fragment_timeout_test.dart
│   │   ├── frame_codec_test.dart
│   │   ├── hmac_blake2s_vectors_test.dart
│   │   ├── host_list_test.dart
│   │   ├── key_map_test.dart
│   │   ├── keystore_test.dart
│   │   ├── no_dismissible_test.dart
│   │   ├── no_pane_text_test.dart
│   │   ├── no_stale_notification_test.dart
│   │   ├── notifications_test.dart
│   │   ├── origin_change_test.dart
│   │   ├── origin_test.dart
│   │   ├── oversized_send_seq_test.dart
│   │   ├── pairing_test.dart
│   │   ├── pane_actions_test.dart
│   │   ├── prediction_engine_test.dart
│   │   ├── reconnect_policy_test.dart
│   │   ├── relay_stats_test.dart
│   │   ├── relay_test.dart
│   │   ├── reset_no_scrollback_test.dart
│   │   ├── resume_test.dart
│   │   ├── revocation_error_frame_test.dart
│   │   ├── revocation_test.dart
│   │   ├── sgr_fidelity_test.dart
│   │   ├── single_socket_test.dart
│   │   ├── terminal_test.dart
│   │   └── tree_test.dart
│   ├── spike/
│   │   └── noise_client_test.dart
│   └── widgets/
│       ├── app_filled_button_test.dart
│       ├── app_ghost_button_test.dart
│       ├── app_section_header_test.dart
│       ├── brand_mark_test.dart
│       ├── eyebrow_test.dart
│       ├── ground_grid_test.dart
│       ├── input_field_test.dart
│       ├── key_row_golden_test.dart
│       ├── key_row_test.dart
│       ├── primitives_test.dart
│       ├── status_dot_test.dart
│       ├── terminal_isolated_test.dart
│       ├── terminal_view_widget_golden_test.dart
│       ├── treatments_test.dart
│       ├── goldens/  # 40 masters, named per section 3.3
│       └── theme/
│           ├── app_color_test.dart
│           ├── app_type_test.dart
│           ├── chrome_compose_task_test.dart
│           ├── chrome_confirmation_dialog_test.dart
│           ├── chrome_contrast_test.dart
│           ├── chrome_list_row_test.dart
│           ├── chrome_settings_section_test.dart
│           ├── chrome_transparency_test.dart
│           ├── contrast_test.dart
│           └── no_literals_test.dart
├── integration_test/
│   ├── first_paint_test.dart
│   ├── host_dispatch_test.dart
│   ├── keystore_survival_test.dart
│   ├── live_review_fixes_test.dart
│   ├── pairing_flow_test.dart
│   ├── real_host_ui_test.dart
│   ├── reconnect_after_restart_test.dart
│   ├── revocation_test.dart
│   ├── spike_render_test.dart
│   └── terminal_test.dart
├── tool/
│   ├── check_notices.dart
│   └── fetch_eff_wordlist.dart
├── android/
│   └── app/
│       ├── build.gradle.kts
│       └── src/main/
│           ├── AndroidManifest.xml
│           ├── kotlin/dev/herdr/herdr_mobile/
│           │   ├── CameraZoomChannel.kt # Owner: CameraZoom (R-90-018)
│           │   └── MainActivity.kt
│           └── res/
│               ├── drawable-mdpi/
│               ├── drawable-hdpi/
│               ├── drawable-xhdpi/
│               ├── drawable-xxhdpi/
│               └── drawable-xxxhdpi/
└── ios/
    ├── Runner.xcodeproj/
    │   └── project.pbxproj
    ├── RunnerTests/
    │   └── KeychainSessionTests.swift # Owner: WP-13-a
    └── Runner/
        ├── AppDelegate.swift
        ├── KeychainSession.swift # Owner: WP-13-a
        ├── CameraZoomChannel.swift # Owner: CameraZoom (R-90-018)
        ├── ChromeReduceTransparencyChannel.swift
        ├── Info.plist
        ├── Assets.xcassets/
        │   └── LaunchGrid.imageset/
        │       ├── Contents.json
        │       ├── launch_grid_light@1x.png
        │       ├── launch_grid_light@2x.png
        │       ├── launch_grid_light@3x.png
        │       ├── launch_grid_dark@1x.png
        │       ├── launch_grid_dark@2x.png
        │       └── launch_grid_dark@3x.png
        └── PrivacyInfo.xcprivacy
```

The `android/` and `ios/` directories hold the complete Flutter platform projects. The
toolchain generates every file not named here. Only the files the plan touches are listed.

`app/LICENSE` is a copy of the root `LICENSE`, which `R-03-020` keeps canonical. Flutter reads the
copy for the licence page. Edit the root file, never the copy.

#### 3.2.3 Brand assets are an input, not a deliverable

`assets/` is not in this tree. It exists in this repository today and §3.1 declares it in full. The
implementation reads it and never regenerates it, so no work package owns a path inside it. See
`docs/32-design-language.md` R-32-422 for how `assets/icon/export/` is produced, and
`docs/23-public-release.md` for the store files that the release phase uploads from it.

#### 3.2.4 CI and agent guidance (`.github/`)

```text
.github/
├── copilot-instructions.md
├── dependabot.yml
└── workflows/
    └── ci.yml                  # Owner: WP-0-a (R-90-018); gates and image publication
```

`ci.yml` holds every gate of §6, including the optional `ios` job. `dependabot.yml` holds the daily
dependency-update configuration of `R-40-055`, which is native platform behaviour and needs no
workflow of its own.

#### 3.2.4a Relay deployment profile (`deploy/relay/`)

```text
deploy/
└── relay/
    └── compose.yaml            # Relay only; docs/14 (R-14-010, R-14-024), R-90-018
```

The directory is the GitOps deployment source, per `R-14-024`. It contains no secret.
An optional, uncommitted `.env` beside the Compose file sets `RELAY_BIND`;
`docs/14-relay-deployment.md` R-14-024 owns that setting.
The operator manages all ingress outside this repository, with TLS and WebSocket support,
per R-14-001 and R-14-010.

#### 3.2.5 Cross-component end-to-end test (`tests/e2e/`)

```text
tests/e2e/
└── README.md
```

§5.4 (R-40-037) owns this tree. The end-to-end test itself is not a file directly under
`tests/e2e/`: its Device harness, `app/test/e2e/full_stack_test.dart`, lives under `app/`
(§3.2.2's "Dart tests" pattern in §3.3) so `dart analyze`/an IDE's Dart plugin resolve its
`package:herdr_mobile/...` imports — the analyzer resolves a package by walking up from a
file to the nearest `pubspec.yaml`, and this repository has none at its root. Its Host stub,
`crates/herdr-relay/src/bin/e2e-stub-host.rs`, lives under `crates/herdr-relay/src/bin/` per
§3.3's "binary target" pattern, for the matching reason: a Cargo binary target must live
inside a crate `cargo` already knows about. `tests/e2e/README.md` is the one file this tree
owns directly: the top-level entry point naming both real files and the exact command to run
them together by hand.

### 3.3 File placement patterns

The tree in §3.2 declares every known path. The patterns below tell an implementer where a new
file goes. Each pattern is checkable by reading a path.

#### Dart files in the Flutter app

- A **screen** lives in `app/lib/screens/`. Its file name ends in `_screen.dart`, except
  `create_sheet.dart`, `pane_actions_sheet.dart`, `pane_switcher_sheet.dart` (sheets),
  `prompt_composer.dart` (a composer overlay) and `app_shell.dart` (the shell widget).
  `device_detail_screen.dart` was `device_detail_sheet.dart` until 2026-09-09, when `R-03-105`
  made the detail a pushed screen.
- A **service** lives in `app/lib/services/`. Its file name is `snake_case.dart`.
- A **model** lives in `app/lib/models/`. Its file name is `snake_case.dart`.
- A **widget** lives in `app/lib/widgets/` or a subgroup under it. Its file name is
  `snake_case.dart`.
- A **theme token** lives in `app/lib/widgets/theme/`. Its file name is `app_<kind>.dart`.

#### Dart tests

- A **unit test** for `app/lib/<path>/<name>.dart` lives at
  `app/test/<path>/<name>_test.dart`. The directory under `test/` mirrors the directory under
  `lib/`.
- A **widget test** for a screen lives at `app/test/screens/<screen>_test.dart`.
- An **integration test** lives in `app/integration_test/<name>.dart` and runs on a device or
  emulator.
- A **test fixture** lives in `app/test/fixtures/<name>.<ext>`.
- A **golden test** for a screen lives at `app/test/screens/<screen>_golden_test.dart`, with its
  reference images at `app/test/screens/goldens/<screen>_<state>_<light|dark>.png`.
  `app/test/screens/golden_support.dart` is the shared harness the golden tests import: it loads
  every app font family and wraps a screen in the app's real theme (`appThemeFrom`). `WP-13-b` owns
  it, per R-90-018, because the lock screen is the earliest golden.

#### Rust files

- A **unit test** lives in the same file as the code it tests, in a `#[cfg(test)] mod tests`
  block. Rust convention; no separate unit-test file.
- An **integration test** lives in `crates/<crate>/tests/<name>.rs`. Each `.rs` file under
  `tests/` is a separate test binary.
- A **shared protocol module** lives in `crates/herdr-relay-proto/src/<module>.rs` and is
  re-exported from `lib.rs`.
- A **binary target** (spike, tool) lives in `crates/herdr-relay/src/bin/<name>.rs`.

#### Platform-specific files

- An **Android platform file** lives under `app/android/app/src/main/`. Kotlin sources go in
  `kotlin/.../` (the package path `...` is `dev/herdr/remote`). The Android project interior
  is generated by the Flutter toolchain.
- An **iOS platform file** lives under `app/ios/Runner/`. The Xcode project interior is
  generated by the Flutter toolchain.

#### Launcher shims

- A **POSIX launcher shim** lives in `crates/herdr-relay/posix/<name>.sh`. Its paired Windows
  shim lives in `crates/herdr-relay/windows/<name>.ps1` with the same base name.
- A **shim test** for a POSIX shim lives in `crates/herdr-relay/tests/posix/test-<name>.sh`.
  Its Windows counterpart lives in `crates/herdr-relay/tests/windows/test-<name>.ps1`.

### 3.4 Tree authority

**R-40-042** The implementation phase MUST create a file at the path the tree in §3.2 declares.
A file that the tree does not declare MUST be added to the tree in the same change that creates
it. **Rationale:** the tree is the single answer to "where does this file go?". A file that
exists only in a checkout is invisible to the next implementer.

**R-40-043** The implementation tree in §3.2 and the ordered checklist in
`docs/90-implementation-plan.md` are the two places a path appears. They MUST agree. Where they
disagree, the plan wins, because it is the ordered checklist, and the disagreement MUST be
reported. **Rationale:** the plan is the step-by-step instruction. The tree is the reference. A
disagreement means one of them is wrong, and the implementer follows the plan first.

**R-40-044** §3.2 owns every path-placement decision. `docs/90-implementation-plan.md`,
`docs/41-code-standards.md` and `docs/20-mobile-framework.md` cite §3.2; they do not own a path
decision. **Rationale:** a path that appears in two documents with two locations is a conflict.
One owner prevents it.
**R-40-045** Every path declared in §3.2 MUST have exactly one owning work package in
`docs/90-implementation-plan.md`. The plan's `**Owns.**` lines and its shared-path registry
together assign every path. **Rationale:** a path without an owner has no one responsible for
it. A path with two owners collides. The plan is where the assignment lives.

**R-40-046** A new implementation path MUST be added to the tree in §3.2 and assigned to exactly
one work package in the same change that creates it. **Rationale:** R-40-042 already requires
the tree entry. This rule adds the ownership requirement. A path that exists only in a checkout
is invisible; a path with no owner is unmaintained.

**R-40-047** Every file listed under `docs/31-mockups/` in §3.1 MUST be cited by at least
one checkbox in `docs/90-implementation-plan.md`. **Rationale:** a mockup that no plan step
cites has no `Draw` step, so `R-90-010` never binds its wireframe, callouts or numbered
rules. The gap that produced the actions screen was a mockup that landed without a plan
step. This rule makes the plan cite every mockup, so the §8.7.2 ownership check can then
catch a missing tree path.

## 4. Documentation Conventions

### 4.1 Numeric file-prefix scheme

Documents use a two-digit numeric prefix. The prefix groups documents by topic:

| Prefix | Topic |
| --- | --- |
| `00`-`09` | Overview, architecture, probe results |
| `10`-`19` | Integration, protocol, hosting, security |
| `20`-`29` | Mobile framework, rendering, platform integration |
| `30`-`39` | UX specification, mockups |
| `40`-`49` | Repository tooling, code standards |
| `90`-`99` | Implementation plan |

**R-40-020** Every document MUST use a two-digit numeric prefix. **Rationale:** the prefix gives a
sort order and a topic group. An agent or a developer can find a document by its number.

### 4.2 Heading style

**R-40-021** Documents MUST use Markdown ATX headings (`#`, `##`, `###`). **Rationale:** ATX headings
are the Markdown standard. They render in every Markdown viewer.

### 4.3 Diagrams

**R-40-022** Diagrams MUST use Mermaid. **Rationale:** Mermaid renders in GitHub, GitLab and most
Markdown viewers. It is text, so it diffs and reviews like code.

### 4.4 Checkbox convention

**R-40-023** TODO items MUST use the `- [ ]` checkbox syntax. **Rationale:** GitHub renders
checkboxes as clickable items. An agent can update a checkbox by editing the file.

### 4.5 Rule numbering

**R-40-024** Every rule MUST be numbered in one of two forms. A normal document uses
`R-<dd>-<nnn>`, where `<dd>` is the document's two-digit numeric prefix and `<nnn>` is a
zero-padded three-digit sequence. A mockup in `docs/31-mockups/` uses `R-31-<nn>-<nn>`,
where the first `<nn>` is the mockup's two-digit file number and the second `<nn>` is a
zero-padded two-digit sequence. **Rationale:** the prefix tells you which document owns the
rule. The sequence number is unique within the document. Examples: `R-40-020` is rule 20 in
this document; `R-31-13-04` is rule 04 in mockup `13-connection.md`.

### 4.6 Architecture Decision Records

**R-40-025** Architecture Decision Records (ADRs) MUST live in `docs/decisions/`. **Rationale:** ADRs
are decisions, not specifications. They belong with the documentation but in a separate directory so
they accumulate without cluttering the numbered documents.

**R-40-026** Each ADR MUST be named `ADR-<nnn>-<kebab-case-title>.md`. **Rationale:** the number
gives a stable reference. The title gives a human-readable summary. Example:
`ADR-001-plugin-stays-in-monorepo.md`.

### 4.7 Cross-references

**R-40-027** Documents MUST cross-reference each other by file path, not by title. **Rationale:** a
file path is stable. A title can change. Example: "See `docs/02-herdr-probe-results.md` for socket
protocol details."

**R-40-028** A rule in one document that depends on a rule in another MUST cite the rule by its full
ID. **Rationale:** the full ID is unique and traceable. Example: "Per R-02-004, a client MUST open a
new connection for every request."

### 4.8 ADR template

```markdown
# ADR-NNN: Title

## Status

Accepted | Superseded by ADR-XXX | Deprecated

## Date

YYYY-MM-DD

## Context

What is the problem? What constraints apply? What alternatives were considered?

## Decision

What did we decide? State the rule.

## Consequences

What follows from this decision? What becomes easier? What becomes harder?
```

## 5. Testing Strategy (Future Implementation)

The rules below describe the testing strategy for the implementation phase. Phase 0 added the
first real test, `healthz_returns_ok_body`; `WP-3` moved it into
`crates/herdr-relay-hub/src/routes.rs` alongside the other endpoint tests once that file existed.
The rest of the strategy below — the shim tests, the remaining crate and app tests, the end-to-end
test — is still future work.

### 5.1 Plugin shim tests

The shim tests follow the `herdr-scheduled` pattern: standalone scripts, stub `herdr`, temp
directories, pass/fail helpers, no test framework.

**R-40-029** The shim tests MUST follow the `herdr-scheduled` pattern: standalone scripts, stub
`herdr`, temp directories, pass/fail helpers, no test framework. **Rationale:** this is the proven
pattern for a cross-platform shell shim. It needs no framework, no dependency, and no real Herdr
server.

**R-40-030** A Host-side test that uses the real local Herdr server MUST NOT close a pane, stop the
server, or mutate layout it did not create. **Rationale:** the developer's Herdr session is their
work environment. A test that closes a pane or stops the server destroys the developer's work. The
stub-based tests avoid this entirely; a test that needs the real server must be read-only or must
clean up after itself.

### 5.2 Rust crate tests

**R-40-031** `herdr-relay-proto` MUST have unit tests for the frame envelope, the close-code enum,
the error taxonomy, the handle codec and the phrase codec. **Rationale:** a bug in the shared
protocol crate breaks every consumer at once.

**R-40-032** The relay (`herdr-relay-hub`) MUST have unit tests for frame forwarding, connection
management and the opaque-frame contract (the relay never reads or stores frame content).
**Rationale:** the relay is the trust boundary. A bug in frame forwarding or connection management
breaks the relay. The opaque-frame contract is a security requirement.

**R-40-033** The relay MUST have integration tests that start the relay, connect a Host and a Device,
and verify that frames flow through without modification. **Rationale:** this tests the real
WebSocket path end to end within the relay process.

### 5.3 App tests

**R-40-034** The app MUST have unit tests for pure Dart logic (protocol parsing, state machines,
crypto helpers). **Rationale:** pure logic tests are fast, deterministic and need no emulator.

**R-40-035** The app MUST have widget tests for every screen. **Rationale:** widget tests verify the
UI without a device. They catch layout and interaction regressions.

**R-40-036** The app MUST have integration tests that run on a device or emulator and exercise the
full app stack (WebSocket, terminal emulator, notifications). **Rationale:** integration tests catch
platform-specific bugs that widget tests miss. Run them on a local emulator or a physical device, not
in CI.

### 5.4 End-to-end test

**R-40-037** The implementation phase MUST deliver one end-to-end test that exercises the full path:
Host (plugin with stub Herdr) → relay → Device (app test harness). **Rationale:** this is the only
test that verifies the three components work together. It catches protocol mismatches and integration
bugs that per-component tests miss.

Delivered: entry point and run command at `tests/e2e/` (§3.2.5). The end-to-end test:

1. Starts the relay in a test mode (no TLS, loopback only).
2. Starts the plugin with a stub `herdr` that returns a canned pane snapshot.
3. Starts the app test harness (a Dart program that connects to the relay and acts as a Device).
4. Verifies that a `pane.read` snapshot arrives at the Device and renders correctly in the terminal
   emulator.
5. Verifies that a keystroke from the Device arrives at the Host.
6. Tears down all three.

This test runs locally, not in CI, because it needs all three components running
simultaneously; `tests/e2e/README.md` states the exact command.

### 5.5 Coverage

**R-40-038** "Done" means every rule `R-<docprefix>-<nnn>` in every document has at least one test
that would fail if the rule were violated. **Rationale:** a vanity percentage does not measure
correctness. A rule without a test is an unverified claim. The rule is the contract; the test is the
proof.

**R-40-039** Coverage MUST NOT be measured as a percentage threshold. **Rationale:** a percentage
does not tell you which rules are tested. It rewards tests for trivial code and misses tests for
critical rules. The rule-to-test mapping is the real measure.

## 6. Continuous Integration (Future Implementation)

Continuous integration belongs to the implementation phase. Phase 0 created it:
`.github/workflows/ci.yml` runs on Linux, Windows and macOS runners.

CI runs on a platform that provides Linux, Windows and macOS runners. `.github/workflows/ci.yml` is
that configuration.

| Gate | Job | Required result |
| --- | --- | --- |
| Native Rust | `rust` | R-41-114 and R-41-115 |
| Relay container and image publication | `relay-container` | R-12-012 and R-40-058 |
| Host release targets | `host-release` | R-90-016, Phase 11 |
| Android app | `flutter` | §7.2.3 |
| iOS app | `ios` | Optional; R-90-012 |

**R-40-058** The `relay-container` job MUST build the Dockerfile test and final stages on pull requests.
It MUST NOT publish a pull request build.
It MUST publish the R-14-011 image on pushes to `main` and `v*` tags.
A `main` build MUST publish `latest` and `sha-<short>` tags.
A `v<version>` build MUST publish `<version>` without changing `latest`.
Manual runs MUST publish only from `main` or a `v*` tag; other refs build only.
The job MUST use SHA-pinned actions, `GITHUB_TOKEN`, and the GitHub Actions build cache.
It MUST build `linux/amd64` from the repository root.
The Dockerfile's target and `COPY` paths require this platform and context.

### 6.1 Scheduled dependency updates

A pin goes stale between releases, and nobody notices until somebody looks. One scheduled job removes
that gap. It matters most for `cupertino_ui`, because `docs/33-platform-chrome.md` R-33-069 waits for
an official release of that package and states no date.

**R-40-055** The future CI MUST run a scheduled dependency-update job for the Flutter app, daily, and
it MUST also be runnable on demand. The job MUST open a pull request and MUST NOT merge one. It MUST
place `cupertino_ui` in its own pull request, separate from every other package, so that a
`cupertino_ui` release is visible on its own. **Rationale:** daily detection costs one scheduled run
and answers `docs/33-platform-chrome.md` R-33-069 without a person remembering to look. An automatic
merge would move a pin with no compatibility evidence, which `R-40-054` forbids.

**R-40-056** A dependency-update pull request MUST report the data that
`docs/20-mobile-framework.md` R-20-043 names, and MUST pass the same gates as any other change. A
`cupertino_ui` pull request that carries official Liquid Glass support MUST NOT merge on its own: it
MUST land with the single revisit that `docs/33-platform-chrome.md` R-33-069 requires.
**Rationale:** the release is the trigger, not the adoption. Merging the bump alone would leave the
documents and the tests behind the dependency.

## 7. Developer Environment

This section is the single source for the developer environment. It names the tools, the pinned
versions, the install commands for each operating system, and the reference editor. The validation
commands in §8 use the tools here.

### 7.1 For documentation contributors, today

| Tool | Minimum version | Purpose | Verify |
| --- | --- | --- | --- |
| Git | 2.43.0 | Clone and branch | `git --version` |
| Node.js | 24 LTS | Run the `npx` and `npm` tools | `node --version` |
| `npx` / `npm` | Bundled with Node | Run `markdownlint-cli2`; install `mermaid` and `jsdom` into an isolated `/tmp` prefix for §8.3 | `npx --version`; `npm --version` |
| `lychee` | 0.24.2 | Link checker | `lychee --version` |

**R-40-040** A documentation contributor MUST have Git, Node.js and `lychee` installed.
**Rationale:** these are the tools that validate the documentation. Without them the validation
commands in §8 fail.

#### 7.1.1 Install per operating system

`markdownlint-cli2` is an npm package `npx` fetches at the pinned version on demand. `mermaid` and
`jsdom` are npm packages `npm install --prefix` installs into an isolated `/tmp` directory for
§8.3, never into the repository. `lychee` is a standalone binary, so its pinned release asset is
downloaded once and placed on `PATH`.

**Windows** (PowerShell):

```powershell
winget install Git.Git
winget install OpenJS.NodeJS.LTS
# lychee 0.24.2: download the pinned release asset, then unzip it.
#   https://github.com/lycheeverse/lychee/releases/download/lychee-v0.24.2/
#     lychee-x86_64-pc-windows-msvc.zip
# Put lychee.exe in a directory on PATH, for example %USERPROFILE%\.local\bin
```

**macOS** (Homebrew):

```bash
brew install git node
brew install lychee
```

**Linux** (Debian or Ubuntu):

```bash
apt install git
curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
apt install nodejs
cargo install lychee --locked --version 0.24.2
```

The `cargo` command needs the Rust toolchain. When it is absent, download the
`lychee-x86_64-unknown-linux-musl` asset from the same release page.

#### 7.1.2 Verify the environment

Run these commands. Each one must print a version.

```bash
git --version
node --version
npx --version
lychee --version
```

Then run the section 8 checks once. A clean run means the environment is ready.

#### 7.1.3 The editor

A contributor MAY use any editor that reads `.editorconfig` and lints Markdown. The reference
editor is VS Code version 1.121 or newer, because it renders Mermaid in the built-in Markdown
preview.

```bash
code --install-extension DavidAnson.vscode-markdownlint
code --install-extension EditorConfig.EditorConfig
```

The `markdownlint` extension shows the same rules as the command-line gate. The `EditorConfig`
extension applies the committed `.editorconfig`.

**R-40-051** A VS Code setup MUST install the `DavidAnson.vscode-markdownlint` and
`EditorConfig.EditorConfig` extensions. It MUST NOT install `bierner.markdown-mermaid`, because VS
Code 1.121 added built-in Mermaid preview and the extension conflicts with it. **Rationale:** the
two extensions keep the editor in line with the command-line gate; the conflict
(microsoft/vscode#317870) stops Mermaid from rendering in the preview.

### 7.2 For the future implementation phase

These tools are needed once implementation begins, and Phase 0 has begun: `crates/` and `app/` now
hold real `Cargo.toml`, `pubspec.yaml` and `crates/herdr-relay-hub/Dockerfile` files, and the
§7.2.3 component build commands run against them. A path §3.2 still lists as future does not exist
until its owning phase creates it.

**R-40-052** The future implementation prerequisites MUST live in §7.2 only. Any other document
MUST cite §7.2 and MUST NOT duplicate a build prerequisite table. **Rationale:** a version or a
platform limit written in two places drifts. One owner prevents it.

#### 7.2.1 The full dependency matrix

| Tool | Pinned version | Windows | Linux | macOS | What it builds |
| --- | --- | --- | --- | --- | --- |
| Herdr | 0.8.2 (protocol 21) | Yes | Yes | Yes | The local server the Host plugin drives (`docs/10-herdr-integration.md`). |
| Rust workspace toolchain | 1.98.0, edition 2024 | Yes | Yes | Yes | Native Host plugin and shared protocol work. The relay Dockerfile uses the same pin inside its build stages. |
| Flutter (bundles Dart) | Flutter 3.47.0, Dart 3.13.0 | Yes | Yes | Yes | Android and iOS app toolchain (`docs/20-mobile-framework.md`). |
| JDK | 17 | Required | Required | Required | Required for Android builds. Android Studio bundles it. Install a standalone JDK only for a CLI-only setup. |
| Android SDK | Platform 36, build-tools 36.0.0, platform-tools | Yes | Yes | Yes | Android build (`docs/20-mobile-framework.md` §7). |
| Android Studio | Optional IDE | Optional | Optional | Optional | SDK Manager and Android IDE. Command-line SDK tools are sufficient for builds. |
| Docker client and engine | Engine 24+ | Docker Engine in WSL 2 | Docker Engine | Docker Engine through Colima | The only relay build, test and deployment prerequisite (`docs/12-relay-hosting.md` R-12-012). |
| Xcode + iOS SDK | Xcode 27, iOS 26 SDK | No | No | Yes | iOS build and signing; native dependencies use Swift Package Manager (R-20-026). |

Each listed version is an exact pin. Update a pin only through a deliberate compatibility change.
Do not use a floating `latest` tag or version.
**R-40-054** A dependency update MUST first evaluate the latest stable release available on the update
date. The update MUST record the latest compatible release as an exact pin after its compatibility
checks pass. An older pin MUST carry a documented compatibility reason. **Rationale:** this keeps the
implementation current without allowing an unreviewed `latest` value to change a build.

#### 7.2.2 Install and verify

Install and verify the cross-platform tools first. Then add the platform-only tools.

```bash
# Rust: from `crates/`, the workspace `rust-toolchain.toml` selects its one exact 1.98.0 toolchain.
cargo --version   # must print 1.98.0


# Flutter, from https://docs.flutter.dev/get-started/install:
flutter --version   # Flutter 3.47.0 and bundled Dart 3.13.0
flutter doctor -v

# Windows: use Docker Engine inside WSL 2. Do not install Docker Desktop. The WSL distribution needs
# Docker only; do not install a Rust toolchain, a musl target or relay build packages in it.
wsl.exe -- docker version

# First-time Windows Docker setup. The distribution name is an example, not a project dependency.
wsl.exe --list --online
wsl.exe --install -d Ubuntu-26.04
wsl.exe -d Ubuntu-26.04 -- sudo apt-get update
wsl.exe -d Ubuntu-26.04 -- sudo apt-get install docker.io
wsl.exe -d Ubuntu-26.04 -- sudo service docker start
wsl.exe -d Ubuntu-26.04 -- docker version

# Native Linux or macOS Docker engine:
docker version
```

The workspace uses exactly one Rust 1.98.0 toolchain through `crates/rust-toolchain.toml`, with
edition 2024.

JDK 17 is required for Android builds. Choose one Android setup. Both choices use the same Flutter
SDK and the same Android package pins.

##### Option A — Android Studio

1. Install Flutter separately. Android Studio does not include Flutter.
2. Install Android Studio. Use its bundled JDK 17.
3. In **SDK Manager**, install `platform-tools`, `platforms;android-36` and
   `build-tools;36.0.0`.
4. Accept the Android SDK licences.
5. Install the Flutter plugin only if Android Studio will edit or launch the app. The plugin also
   installs Dart editor support.

Use **Device Manager** if you want an emulator. An emulator and its system image are optional; a
physical Android device is sufficient.

##### Option B — Command-line tools

1. Install a standalone JDK 17.
2. Install Google's **Command line tools only** package.
3. Run:

```bash
sdkmanager --licenses
sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0"
flutter doctor -v
```

The command-line setup does not install an emulator or a system image. Use a physical device, or
install those optional packages separately.

The host-platform and Android checks in `flutter doctor -v` MUST be clean. On Windows, iOS-only
findings remain expected because Xcode is macOS-only. A container engine is ready only when its
platform-specific command prints both a client and a reachable server:

```bash
# Windows with Docker Engine in your default WSL 2 distribution:
wsl.exe -- docker version

# Native Linux or macOS runtime:
docker version
```

**R-40-053** An implementation environment MUST NOT be marked ready until the Android SDK licences
are accepted, the API 36 platform and build-tools are installed, `flutter doctor -v` reports clean
host-platform and Android checks, and the platform-specific `docker version` command reaches a
server. **Rationale:** package presence does not prove that the build tools can compile or that the
container engine can run.

The relay needs no platform-only build tool. Its Dockerfile installs the musl target and every Linux
build dependency inside its build stages (R-12-012).

macOS-only tools:

```bash
# Xcode 27, from the App Store, then:
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
xcodebuild -version   # Xcode 27
```

Xcode includes Swift Package Manager. All pinned iOS plugins support it, so this app needs no
CocoaPods installation or separate Ruby runtime (R-20-026).

#### 7.2.3 Component build commands

| Component | Command | Owner |
| --- | --- | --- |
| Rust formatting | `cargo fmt --check` | `docs/41-code-standards.md` R-41-114 |
| Host plugin and shared protocol | `cargo clippy -p herdr-relay -p herdr-relay-proto --all-targets --all-features -- -D warnings`; `cargo test -p herdr-relay -p herdr-relay-proto` | `docs/41-code-standards.md` R-41-115; `docs/10-herdr-integration.md` §7 |
| Relay test image | `docker build --target test -f crates/herdr-relay-hub/Dockerfile .` | `docs/12-relay-hosting.md` R-12-012 |
| Relay final image | `docker build -f crates/herdr-relay-hub/Dockerfile -t herdr-relay-hub .`; deploy with `docker compose` per R-14-010 | `docs/12-relay-hosting.md`; `docs/14-relay-deployment.md` |
| Android app | `flutter build apk --debug` | `docs/20-mobile-framework.md` §7 |
| iOS app, macOS only | `flutter build ios --debug --no-codesign` | `docs/20-mobile-framework.md` §7 |

##### Launch the Android app

`app/` exists as of Phase 0. Run these commands from the repository root:

```bash
flutter doctor -v
flutter devices
cd app
flutter pub get
dart run tool/fetch_eff_wordlist.dart      # gitignored asset, R-13-025
dart run build_runner build --delete-conflicting-outputs
flutter run -d <device-id>
```

For a physical Android device, enable Developer options and USB debugging. Confirm that `adb devices`
shows its serial number, then use that serial number as `<device-id>`. For an Android Studio emulator,
start the device in **Device Manager** before `flutter devices`. The same `flutter run` command works
for both.

#### 7.2.4 Platform limits

Three limits are fixed. An iOS build needs macOS with Xcode 27 and the iOS 26 SDK. No other platform
can build or sign iOS (`docs/23-public-release.md` R-23-057). The relay binary is Linux-only musl,
but every relay build, test and run command uses Docker on every developer platform. Windows may
host Docker Engine inside WSL 2, but the WSL distribution needs no project package other than
Docker. `docs/14-relay-deployment.md` R-14-010 owns the relay-only deployment profile.
R-14-001 owns the requirements for external ingress, including TLS and WebSocket support.

## 8. Validate the Documentation

These commands check the documentation in this repository. No task runner and no committed script is
needed. Run each command directly.

### 8.1 Markdown structure

```bash
npx markdownlint-cli2@0.23.2 "**/*.md"
```

The command reads the committed `.markdownlint-cli2.jsonc` config at the repository root. That config
sets MD013 line length to 100 (with tables, code blocks and headings exempt) and relaxes rules that
conflict with intentional repository conventions. A contributor MUST NOT relax a rule without a
stated reason in the config file itself. The file already carries a comment for every relaxation;
follow that pattern.

### 8.2 Link resolution

First pass, offline for relative links:

```bash
lychee --offline --no-progress "**/*.md"  # pinned at 0.24.2; see lychee --version
```

Second pass, online for public URLs:

```bash
lychee --no-progress "**/*.md"  # pinned at 0.24.2; see lychee --version
```

Internal NVIDIA URLs in `docs/15-nvidia-brev-relay-experiment.md` are checked only from the NVIDIA
network.

`lychee`'s version is pinned in prose, in the trailing comment, not in the command itself,
because `lychee` is a standalone binary, not an npm package that `npx` fetches: a bare version
number on the `lychee` command line would be parsed as an input path, not a version. Do not move
the version into the `lychee` argument list.

### 8.3 Mermaid diagrams

```bash
mkdir -p /tmp/mermaid-check
trap 'rm -rf /tmp/mermaid-check' EXIT
npm install --prefix /tmp/mermaid-check mermaid@11.16.0 jsdom@30.0.1 --no-audit --no-fund
cat > /tmp/mermaid-check/check.mjs <<'SCRIPT'
import { JSDOM } from "jsdom";
import fs from "fs";
import path from "path";
const dom = new JSDOM("<!doctype html><html><body></body></html>", { pretendToBeVisual: true });
for (const n of ["window", "document", "navigator", "DOMParser", "XMLSerializer",
  "Node", "Element", "HTMLElement", "SVGElement", "SVGSVGElement"]) {
  Object.defineProperty(globalThis, n, { value: dom.window[n] ?? dom.window, configurable: true, writable: true });
}
const { default: mermaid } = await import("mermaid");
mermaid.initialize({ startOnLoad: false });
const FENCE = "\x60\x60\x60";
const RE = new RegExp(FENCE + "mermaid\\r?\\n([\\s\\S]*?)" + FENCE, "g");
const files = [];
(function walk(dir) {
  for (const e of fs.readdirSync(dir)) {
    if (["node_modules", ".git"].includes(e)) continue;
    const f = path.join(dir, e);
    if (fs.statSync(f).isDirectory()) walk(f);
    else if (f.endsWith(".md")) files.push(f);
  }
})(".");
let total = 0, failed = 0;
for (const f of files) {
  const text = fs.readFileSync(f, "utf8");
  for (const m of text.matchAll(RE)) {
    total++;
    try { await mermaid.parse(m[1]); }
    catch (err) { failed++; console.log(`FAIL: ${f}: ${err.message.split("\n")[0]}`); }
  }
}
console.log(`${total - failed}/${total} Mermaid blocks parse`);
process.exit(failed ? 1 : 0);
SCRIPT
node /tmp/mermaid-check/check.mjs
```

`mermaid` 11.16.0 is the exact parser version `@mermaid-js/mermaid-cli` 11.16.0 used to bundle;
`jsdom` 30.0.1 was the latest stable release on the pin date, per `R-40-054`. The command installs
both into an isolated `/tmp` prefix, so nothing installs into the repository, then calls
`mermaid.parse()` on every extracted block in process. The `trap` removes the prefix on any exit
path without overwriting the exit status, so `node check.mjs` stays the block's true last command:
a parse failure's exit code `1` survives to the caller, not masked by a trailing `rm`'s own `0`.

`@mermaid-js/mermaid-cli` used to run this check. It drove Puppeteer's `chrome-headless-shell.exe`
to render each block to SVG before discarding the image. On Windows, `chrome-headless-shell.exe`
is a console-subsystem binary: it allocates a visible console window for the child processes
Puppeteer forks internally, and no Puppeteer or Chrome launch flag suppresses that allocation,
because the window is a side effect of the binary's own subsystem type, not of anything Puppeteer
configures. Every check run popped a visible window on the contributor's desktop.

**R-40-057** Mermaid validation in this repository MUST NOT depend on a headless browser or on
Puppeteer, in any form. The command above satisfies the actual requirement `§8.5` states — every
block **parses** — without rendering a pixel, because this repository never ships or runs Mermaid
at runtime: every diagram is rendered by whatever platform displays the document, for example
GitHub's native fence renderer. A future change MUST NOT reintroduce `mermaid-cli` or another
Puppeteer-based tool "to be more thorough": rendering fidelity is strictly more than `§8.5`
requires, and the incident above is the reason this repository stays without it. **Rationale:** a
syntax check that happens to also render is still just a syntax check with an expensive, fragile
and, on Windows, disruptive side effect.

### 8.4 Rule-consistency audit

Every cited rule `R-nn-nnn` must exist exactly once, either as a live definition or as an entry in
the owning document's `## Retired rules` table that names a replacement. No placeholder `R-xx-xxx`,
no `[UNVERIFIED]` without a named owner and a stated fallback, no `TODO`, no `TBD`, and no "language
undecided" or "stale" marker remains in normative text. Verify with a one-off command:

```bash
# Extract every cited rule id from the full repository.
grep -roPh 'R-\d{2}-\d{3}' docs/ | sort -u > /tmp/cited.txt

# Extract every live-defined rule id. A rule is defined as a bold-wrapped id, which may carry a
# trailing sub-letter or an inline title before the closing bold marker (docs/20 and docs/21 use
# this form), or as a colon-terminated line at the start of a paragraph (docs/13) or a list item
# (docs/23). All three forms are established conventions already in use across the repository; the
# pattern accepts each rather than forcing one prose style.
grep -roPh '\*\*R-\d{2}-\d{3}[a-z]?[^\n*]*\*\*' docs/ | grep -oP 'R-\d{2}-\d{3}[a-z]?' > /tmp/defined.txt
grep -roPh -- '- R-\d{2}-\d{3}[a-z]?(?=:)' docs/ | grep -oP 'R-\d{2}-\d{3}[a-z]?' >> /tmp/defined.txt
grep -roPh '^R-\d{2}-\d{3}[a-z]?(?=:)' docs/ | grep -oP 'R-\d{2}-\d{3}[a-z]?' >> /tmp/defined.txt
sort /tmp/defined.txt -o /tmp/defined.txt
sort -u /tmp/defined.txt -o /tmp/defined_u.txt

# Extract every id resolved by retirement: a backtick-wrapped id inside its document's own
# "## Retired rules" table. That table is the id's permanent record once a rule is retired, so a
# citation of it is resolved, not dangling.
awk 'FNR==1{flag=0} /^## Retired rules/{flag=1; next} /^## /{flag=0} flag' $(find docs -name '*.md') \
  | grep -oP '(?<=`)R-\d{2}-\d{3}[a-z]?(?=`)' | sort -u > /tmp/retired_u.txt
sort -u /tmp/defined_u.txt /tmp/retired_u.txt -o /tmp/resolved_u.txt

# Placeholders (R-xx-xxx) must be zero. This file's own description of the check is excluded,
# because the command necessarily writes the literal search string once, in its own argument.
grep -r 'R-xx-xxx' docs/ --exclude=40-repo-tooling.md \
  && echo "FAIL: placeholder rule ids found" || echo "OK: no placeholders"

# A live rule id must be defined exactly once. A retirement mention does not count here: an id may
# carry one live definition and a separate historical mention in a "Retired rules" table, for
# example when the id was retired and later reused for an unrelated rule.
uniq -d /tmp/defined.txt

# Dangling citations: cited but neither defined nor resolved by retirement.
comm -23 /tmp/cited.txt /tmp/resolved_u.txt
```

`uniq -d` prints any id defined more than once. `comm` prints any id that is cited but resolves
nowhere.

### 8.5 Documentation-completeness checklist

Before marking a documentation change as done:

- [ ] All relative Markdown links resolve to a file that exists.
- [ ] Every Mermaid diagram parses without error.
- [ ] One `H1` per document, outside a code fence.
- [ ] Every code fence balances its opening and closing markers.
- [ ] Every file ends with exactly one newline.
- [ ] Every `## Sources` section names the primary source for each mutable fact.
- [ ] Every `## Open questions` item is either a genuine external dependency with a recommended
  default, or removed.
- [ ] No `TODO`, `TBD`, `[UNVERIFIED]` without an owner and fallback, `R-xx-xxx` placeholder,
  "language undecided", or "stale" marker remains in normative text.
- [ ] No harness-internal URI remains in a committed Markdown file, per `R-40-041`.
- [ ] Every implementation path declared in §3.2 has exactly one owning work package in
  `docs/90-implementation-plan.md`, per R-40-045.
- [ ] Every new work package in `docs/90-implementation-plan.md` declares its owned paths in an
  `**Owns.**` line and its contract before its wave starts, per R-90-020.
- [ ] Every shared path in the plan has exactly one owning package and one mechanism in the
  shared-path registry, per R-90-017.

### 8.6 Harness-internal URI check

**R-40-041** A committed Markdown file MUST NOT contain a harness-internal URI. Those are the
schemes `local`, `artifact`, `agent` and `history`, each followed by a colon and two slashes.
**Rationale:** those schemes resolve only inside an agent session, so a reader who has nothing but
the repository cannot follow them. This document names the schemes as words, and the check below
matches the separator as a pattern, so neither one matches itself. The check therefore scans every
Markdown file, including this one, and has no blind spot.

```bash
grep -rnP '\b(local|artifact|agent|history):/{2}' --include='*.md' . \
  && echo "FAIL: harness-internal URI found" \
  || echo "OK: no harness-internal URI"
```

### 8.7 Parallel-execution model

The commands below check the parallel-execution model in
`docs/90-implementation-plan.md`. They verify that the model is safe to fan out to many agents
at implementation time. Run each command from the repository root.

#### 8.7.1 Ownership is disjoint

No path may appear in two `**Owns.**` lines. A path that does means two work packages both
claim it, and they will collide.

```bash
node -e '
const fs = require("fs");
const lines = fs.readFileSync(
  "docs/90-implementation-plan.md", "utf8").split("\n");
const paths = [];
let inOwns = false;
for (const line of lines) {
    const s = line.trimEnd();
    if (s.startsWith("**Owns.**")) {
        inOwns = true;
        for (const m of s.matchAll(/`([^`]+)`/g))
            paths.push(m[1]);
    } else if (inOwns) {
        if (s.trim() === "") {
            inOwns = false;
        } else if (s.trimStart().startsWith("`")) {
            for (const m of s.matchAll(/`([^`]+)`/g))
                paths.push(m[1]);
        } else {
            inOwns = false;
        }
    }
}
const counts = new Map();
for (const p of paths)
    counts.set(p, (counts.get(p) || 0) + 1);
const dupes = [...counts.entries()]
    .filter(([,c]) => c > 1)
    .map(([p]) => p).sort();
if (dupes.length) {
    for (const p of dupes) console.log(p);
    process.exit(1);
}
console.log("OK: no path appears in two Owns. lines");
'
```

A pass prints `OK: no path appears in two Owns. lines`. A failure prints each path that
appears more than once.

#### 8.7.2 Ownership is total

Every path declared in §3.2 must have an owner: it must appear in exactly one `**Owns.**`
line or in the shared-path registry. A path in neither is unowned.

```bash
node -e '
const fs = require("fs");

// ---- Extract every file path from the \u00a73.2 tree ----
let text = fs.readFileSync("docs/40-repo-tooling.md", "utf8");
const sec32 = text.match(
  /### 3\.2 The future implementation tree.*?(?=### 3\.[3-9]|## 4\.)/s);
if (!sec32) {
    console.log("ERROR: \u00a73.2 not found");
    process.exit(1);
}
const fences = [...sec32[0].matchAll(
  /```text\n(.*?)```/gs)].map(m => m[1]);
const treePaths = new Set();
for (const fence of fences) {
    const stack = [];
    for (let line of fence.split("\n")) {
        line = line.split("#")[0].trimEnd();
        if (!line) continue;
        const m = line.match(
          /^([ \u2502]*)([\u251C\u2514]\u2500\u2500 )?(.+)$/);
        if (!m) continue;
        const prefix = m[1], branch = m[2], name = m[3];
        const depth = branch
          ? Math.floor(prefix.length / 4) + 1 : 0;
        stack.length = depth;
        if (name.endsWith("/")) {
            stack.push({depth, name});
        } else {
            treePaths.add(
              stack.map(d => d.name).join("") + name);
        }
    }
}

// ---- Extract paths from Owns. lines ----
const ownsPaths = new Set();
let inOwns = false;
for (const line of fs.readFileSync(
  "docs/90-implementation-plan.md", "utf8").split("\n")) {
    const s = line.trimEnd();
    if (s.startsWith("**Owns.**")) {
        inOwns = true;
        for (const m of s.matchAll(/`([^`]+)`/g))
            ownsPaths.add(m[1]);
    } else if (inOwns) {
        if (s.trim() === "") {
            inOwns = false;
        } else if (s.trimStart().startsWith("`")) {
            for (const m of s.matchAll(/`([^`]+)`/g))
                ownsPaths.add(m[1]);
        } else {
            inOwns = false;
        }
    }
}

// ---- Extract paths from the shared-path registry ----
let plan = fs.readFileSync(
  "docs/90-implementation-plan.md", "utf8");
plan = plan.replace(/\r\n/g, "\n");
const regSec = plan.match(
  /### [^\n]*[Rr]egistry[^\n]*\n(.*?)(?=\n### |\n## |$)/s);
const registryPaths = new Set();
let owned;
if (regSec) {
    for (const m of regSec[1].matchAll(/`([^`]+)`/g))
        registryPaths.add(m[1]);
    owned = new Set([...ownsPaths, ...registryPaths]);
} else {
    owned = ownsPaths;
    console.log("NOTE: shared-path registry section not found"
      + " -- only Owns. paths counted");
}

const unowned = [...treePaths]
    .filter(p => !owned.has(p)).sort();
if (unowned.length) {
    for (const p of unowned) console.log(p);
    if (!regSec)
        console.log("(" + unowned.length
          + " paths with no owner; registry may cover some)");
    process.exit(1);
}
console.log("OK: every \u00a73.2 path has an owner");
'
```

A pass prints `OK: every §3.2 path has an owner`. A failure prints each unowned path. When
the shared-path registry section has not been written yet, the command prints a note and
lists paths that the registry may later cover.

#### 8.7.3 Shared-path registry is complete

Every path that the plan mentions in more than one phase must appear in the shared-path
registry. A multi-phase path that is missing from the registry is a collision waiting to
happen.

```bash
node -e '
const fs = require("fs");
let plan = fs.readFileSync(
  "docs/90-implementation-plan.md", "utf8");
plan = plan.replace(/\r\n/g, "\n");

// ---- Find the shared-path registry section ----
const regSec = plan.match(
  /### [^\n]*[Rr]egistry[^\n]*\n(.*?)(?=\n### |\n## |$)/s);
if (!regSec) {
    console.log("NOTE: shared-path registry section not found"
      + " -- nothing to check");
    process.exit(0);
}
const registryPaths = new Set();
for (const m of regSec[1].matchAll(/`([^`]+)`/g))
    registryPaths.add(m[1]);

// ---- Extract tree paths (same as \u00a78.7.2) ----
let text40 = fs.readFileSync("docs/40-repo-tooling.md", "utf8");
const sec32 = text40.match(
  /### 3\.2 The future implementation tree.*?(?=### 3\.[3-9]|## 4\.)/s);
if (!sec32) {
    console.log("ERROR: \u00a73.2 not found");
    process.exit(1);
}
const fences = [...sec32[0].matchAll(
  /```text\n(.*?)```/gs)].map(m => m[1]);
const treePaths = new Set();
for (const fence of fences) {
    const stack = [];
    for (let line of fence.split("\n")) {
        line = line.split("#")[0].trimEnd();
        if (!line) continue;
        const m = line.match(
          /^([ \u2502]*)([\u251C\u2514]\u2500\u2500 )?(.+)$/);
        if (!m) continue;
        const prefix = m[1], branch = m[2], name = m[3];
        const depth = branch
          ? Math.floor(prefix.length / 4) + 1 : 0;
        stack.length = depth;
        if (name.endsWith("/")) {
            stack.push({depth, name});
        } else {
            treePaths.add(
              stack.map(d => d.name).join("") + name);
        }
    }
}

// ---- Count how many phase sections mention each path ----
const sec6 = plan.match(
  /## 6\. Phases\n(.*?)(?=\n## [7-9]|$)/s);
if (!sec6) {
    console.log("ERROR: Phases section not found");
    process.exit(1);
}
const phaseSecs = sec6[1].split(
  /\n(?=### (?:Documentation readiness|Phase \d+))/);
const pathPhases = new Map();
for (const sec of phaseSecs) {
    const lm = sec.match(/### (.*?)\n/);
    const label = lm ? lm[1] : "unknown";
    // Only a "- [ ]" checkbox line counts, per this section's own definition: a shared path is
    // one that "carries more than one phase's checkboxes." A path merely cited in "Goal.",
    // "Owns." or "Done when." prose (for example a later phase's build/verify command) is not a
    // second owner and must not force a registry row.
    const secPaths = new Set();
    for (const cbLine of sec.matchAll(/^- \[[ x]\].*$/gm))
        for (const pm of cbLine[0].matchAll(/`([^`]+)`/g))
            secPaths.add(pm[1]);
    for (const p of secPaths) {
        if (!treePaths.has(p)) continue;
        if (!pathPhases.has(p))
            pathPhases.set(p, new Set());
        pathPhases.get(p).add(label);
    }
}
const multi = new Set(
    [...pathPhases.entries()]
        .filter(([,s]) => s.size > 1)
        .map(([p]) => p));
const missing = [...multi]
    .filter(p => !registryPaths.has(p)).sort();
if (missing.length) {
    for (const p of missing) console.log(p);
    process.exit(1);
}
console.log("OK: every multi-phase path is in the registry");
'
```

A pass prints `OK: every multi-phase path is in the registry`. A failure prints each
multi-phase path that is missing from the registry. When the registry section has not been
written yet, the command prints a note and exits cleanly.

#### 8.7.4 Work-package dependency graph is acyclic

The Mermaid work-package graph in `docs/90-implementation-plan.md` must have no cycle. A
cycle means no valid build order exists.

```bash
node -e '
const fs = require("fs");
const text = fs.readFileSync(
  "docs/90-implementation-plan.md", "utf8");
const edges = [...text.matchAll(
  /(\w[\w-]*)\s*-->\s*(\w[\w-]*)/g)]
    .map(m => [m[1], m[2]]);
const graph = new Map();
const indeg = new Map();
for (const [u, v] of edges) {
    if (!graph.has(u)) graph.set(u, []);
    graph.get(u).push(v);
    indeg.set(v, (indeg.get(v) || 0) + 1);
    if (!indeg.has(u)) indeg.set(u, 0);
}
const q = [...indeg.entries()]
    .filter(([,d]) => d === 0)
    .map(([n]) => n);
const order = [];
while (q.length) {
    const u = q.shift();
    order.push(u);
    for (const v of (graph.get(u) || [])) {
        indeg.set(v, indeg.get(v) - 1);
        if (indeg.get(v) === 0) q.push(v);
    }
}
if (order.length !== indeg.size) {
    const remaining = [...indeg.entries()]
        .filter(([,d]) => d > 0)
        .map(([n]) => n).sort();
    console.log("CYCLE: nodes in cycle: " + remaining);
    process.exit(1);
}
console.log(
  "OK: work-package dependency graph is acyclic "
  + "(" + order.length + " nodes, "
  + edges.length + " edges)");
'
```

A pass prints the node and edge count. A failure prints the nodes that remain in a cycle.

#### 8.7.5 Every mockup has a plan step

Every file listed under `docs/31-mockups/` in §3.1 must be cited by at least one checkbox
in `docs/90-implementation-plan.md`. A mockup that no step cites has no `Draw` step, so
`R-90-010` never binds its content. This check catches the gap that produced the actions
screen: a mockup that landed without a plan step.

```bash
node -e '
const fs = require("fs");

// ---- Extract mockup filenames from the §3.1 tree ----
let text = fs.readFileSync("docs/40-repo-tooling.md", "utf8");
const sec31 = text.match(
  /### 3\.1 This repository, now.*?```text\n(.*?)```/s);
if (!sec31) {
    console.log("ERROR: §3.1 tree not found");
    process.exit(1);
}
const mockups = new Set();
for (const m of sec31[1].matchAll(/^[ \u2502]*[\u251C\u2514]\u2500\u2500 (\d{2}-[a-z-]+\.md)$/gm))
    mockups.add(m[1]);

// ---- Extract cited mockup paths from the plan ----
const plan = fs.readFileSync(
  "docs/90-implementation-plan.md", "utf8");
const cited = new Set();
for (const m of plan.matchAll(
  /docs\/31-mockups\/(\d{2}-[a-z-]+\.md)/g))
    cited.add(m[1]);

const uncited = [...mockups].filter(m => !cited.has(m)).sort();
if (uncited.length) {
    for (const m of uncited) console.log(m);
    process.exit(1);
}
console.log("OK: every mockup is cited by a plan step");
'
```

A pass prints `OK: every mockup is cited by a plan step`. A failure prints each mockup
file that no plan step cites.

#### 8.7.6 Every named surface is drawn

**R-40-048** A mockup that names a screen, sheet, dialog, palette, menu or panel as a destination
MUST name a mockup file, a route, or an in-place action that the same file draws as a
`## Wireframe`. A pointer to a platform-native control, for example a time picker, is not a mockup
surface and needs no wireframe. **Rationale:** a named surface with no drawing is a screen a person
can reach but an implementer cannot build. The About screen and the Device detail sheet were both
named as destinations before either had a drawing.

The check scans each mockup's `## Navigation` `Out` lines for a named surface. A surface is
satisfied by one of: a mockup-file citation, a route, or an `in place` marker backed by a matching
`## Wireframe` heading in the same file.

```bash
node -e '
const fs = require("fs");

// ---- Mockup files from the \u00a73.1 tree ----
let text40 = fs.readFileSync("docs/40-repo-tooling.md", "utf8");
const sec31 = text40.match(
  /### 3\.1 This repository, now.*?```text\n(.*?)```/s);
if (!sec31) {
    console.log("ERROR: \u00a73.1 tree not found");
    process.exit(1);
}
const mockups = [...sec31[1].matchAll(
  /^[ \u2502]*[\u251C\u2514]\u2500\u2500 (\d{2}-[a-z-]+\.md)$/gm)]
    .map(m => "docs/31-mockups/" + m[1]);

// ---- A named surface: a Title-Case phrase ending in a surface noun. ----
// Determiners and pronouns are excluded, so "This screen" and "the sheet"
// (bare references) do not read as named surfaces.
const DET = "This|That|These|Those|The|A|An|No|Every|Each|Some|Any|Another|Other|One|Both|All|Either|Neither|Same|Such|It|He|She|They|We|You|I|My|Your|Our|Their|Its|And|But|Or|So|Then|Also|Plus|Because";
const SURFACE = new RegExp(
    "\\b((?!(?:" + DET + ")\\b)[A-Z][A-Za-z]*"
    + "(?: [A-Za-z][A-Za-z]*){0,2}"
    + " (?:screen|sheet|dialog|palette|menu|panel|popup))\\b", "g");
const FILE = /\d{2}-[a-z-]+\.md/;
const ROUTE = /\/[A-Za-z]{2,}[A-Za-z0-9:_\/-]*/;

function norm(s) {
    return s.toLowerCase().replace(/^(the|a|an)\s+/, "")
        .replace(/[^a-z0-9]+/g, " ")
        .replace(/\s+/g, " ").trim();
}

const problems = [];
for (const file of mockups) {
    let text;
    try {
        text = fs.readFileSync(file, "utf8");
    } catch (e) {
        problems.push(file + " (missing file)");
        continue;
    }
    const nav = text.match(
      /\n## Navigation\n([\s\S]*?)(?=\n## |\n$)/);
    if (!nav) continue;

    // ---- Surfaces this file draws: the H1 title and each wireframe heading ----
    const drawn = new Set();
    const h1 = text.match(/^# \d+ - (.*)$/m);
    if (h1) drawn.add(norm(h1[1]));
    for (const m of text.matchAll(/^## Wireframe(?:,\s*(.+))?$/gm))
        if (m[1]) drawn.add(norm(m[1]));

    // A list item wraps at 100 columns, so join its continuation lines before
    // reading it. A physical line hides a trailing "in place" clause and the
    // check then reports a surface that the file does draw.
    const items = [];
    for (const line of nav[1].split("\n")) {
        if (/^\s*- /.test(line)) items.push(line.trim());
        else if (items.length && line.trim())
            items[items.length - 1] += " " + line.trim();
    }
    for (const s of items) {
        if (!s.startsWith("- Out")) continue;
        for (const m of s.matchAll(SURFACE)) {
            const name = norm(m[1]);
            const rest = s.slice(m.index + m[0].length);
            if (FILE.test(rest) || ROUTE.test(rest)) continue;
            if (/in place|no route change/.test(rest)) {
                const covered = [...drawn].some(
                    d => d.includes(name) || name.includes(d));
                if (covered) continue;
            }
            problems.push(file + " :: " + s + "  ->  " + m[1]);
        }
    }
}

if (problems.length) {
    for (const p of problems) console.log(p);
    process.exit(1);
}
console.log("OK: every named surface is drawn or cited");
'
```

A pass prints `OK: every named surface is drawn or cited`. A failure prints each file, the `Out`
line and the surface that has no drawing and no citation.

**Blind spot.** The check keys on a Title-Case surface name, for example `Device detail sheet` or
`About screen`. A surface named only in lowercase prose, for example `the help sheet`, reads as an
in-file description and is not checked. The check scans only the `## Navigation` section. A surface
named in a callout or a rule, but not in `## Navigation`, is not caught. The wireframe match is a
normalized containment. A heading that names the surface differently is flagged. A heading that
happens to contain the surface name validates it. Read a flagged line by eye before you edit. The
check names a candidate, not a proof.

#### 8.7.7 Every displayed value names its source

**R-40-049** A mockup author MUST name, in the `## Sources` section, the message in
`docs/11-relay-protocol.md` or the method in `docs/10-herdr-integration.md` that carries each value
the panel displays. **Rationale:** a value with no source is a column an implementer cannot fill.
The `platform` and `fingerprint` columns landed in `14-devices.md` and `16-host-popup.md` before
either field crossed the wire.

This property is not mechanically checkable. A wireframe is ASCII art and a column header is prose,
so no command can tell which strings are displayed values and which are labels or decoration. The
rule converts an uncheckable property into a reviewable one. A reviewer reads the `## Sources`
section and asks, for each displayed value, which message or method carries it.

#### 8.7.8 No cross-file callout by number

**R-40-050** A cross-file pointer to a mockup callout MUST name the mockup file and the row label.
It MUST NOT name the callout by its ordinal number. **Rationale:** a callout number is positional.
It moves when a row is added or removed. A pointer to `callout 15` can point at a different callout
after any edit, and no rule audit sees it, because no rule id is involved.

The check searches every Markdown file for `callout <n>` paired with a mockup file. Two pairings
count: a file token immediately before `callout <n>`, and `callout <n>` followed by `of`, `on`,
`in` or `at` and a file token. A pairing that names the current file is skipped, because it is not
cross-file.

```bash
node -e '
const fs = require("fs");
const path = require("path");

function* walk(dir) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const p = path.join(dir, entry.name);
        if (entry.isDirectory()) yield* walk(p);
        else if (entry.name.endsWith(".md")) yield p;
    }
}

const FILE = "`[^`]*\\d{2}-[a-z-]+\\.md`";
const CALL = "callout\\s+\\d+";
const A = new RegExp(
    "`[^`]*(\\d{2}-[a-z-]+\\.md)`\\s+" + CALL, "gi");
const B = new RegExp(
    CALL + "\\s+(?:of|on|in|at)\\s+(?:the\\s+)?`[^`]*(\\d{2}-[a-z-]+\\.md)`", "gi");

const problems = [];
for (const file of walk("docs")) {
    const text = fs.readFileSync(file, "utf8");
    const self = path.basename(file);
    for (const re of [A, B]) {
        for (const m of text.matchAll(re)) {
            if (m[1] !== self)
                problems.push(file + " :: " + m[1]
                    + " :: " + m[0].replace(/\s+/g, " "));
        }
    }
}
if (problems.length) {
    for (const p of problems) console.log(p);
    process.exit(1);
}
console.log("OK: no cross-file callout-by-number reference");
'
```

A pass prints `OK: no cross-file callout-by-number reference`. A failure prints each file, the
referenced file and the matched text.

**Blind spot.** The check keys on a tight pairing: a file token beside `callout <n>`. A pointer that
names the file earlier in the same bullet and the ordinal later, with other text between, is not
caught. An in-file `callout <n>` that goes stale is not caught. A pointer that names a row label
which the target file later renames is not caught.

## Retired rules

Rules retired during the 2026-08 remediation. Their ids are kept so a reader who finds an old
citation is not lost.

| Retired id | What it said | Replaced by |
|---|---|---|
| `R-40-004` old | Repository MUST contain `.omp/RULES.md`. | Deleted. `.omp/RULES.md` was removed. Every rule it held duplicates `AGENTS.md`. See §1.2 for the full evidence. |
| `R-40-005` old | `.omp/RULES.md` MUST stay under 30 lines. | Replaced by R-40-004: `AGENTS.md` MUST stay under 32 KiB, targeting under 400 lines. |
| `R-40-006` old | `.omp/RULES.md` MUST contain five specific hard requirements. | Deleted. Those requirements live in `AGENTS.md` now. |
| `R-40-021` old | The repository MUST use `just` 1.58.0 as the task runner. | Deleted. This is a documentation repository with no build project. Documentation validation uses direct commands per §8. The future implementation phase adds its own task runner or CI. |

## Implementation TODO

These items belong to the implementation phase. `docs/90-implementation-plan.md` is the
authoritative, currently-ticked checklist; several of these — the Rust workspace, the protocol
module stubs, the plugin binary, the relay service, `app/`, the CI pipeline — are already done as
of Phase 0.

- [ ] Create the Rust workspace at `crates/` with `Cargo.toml`, `rust-toolchain.toml`, the three
  member crates, and every dependency pin from `docs/12-relay-hosting.md` §2.1.
- [ ] Create `crates/herdr-relay-proto/src/` with frame, messages, codes, handle, phrase and
  test_vectors modules.
- [ ] Create `crates/herdr-relay/` with the Rust plugin binary, the `herdr-plugin.toml` manifest,
  and the POSIX and PowerShell launcher shims (at most five lines each).
- [ ] Create `crates/herdr-relay-hub/` with the axum relay service and the `Dockerfile`.
- [ ] Create `app/` with `flutter create` and the directory structure in §3.2.
- [ ] Add a CI pipeline for the implementation phase. Phase 0 delivered `.github/workflows/ci.yml`;
  the exact configuration (platform, jobs, matrix) is that file.
- [ ] Deliver the end-to-end test described in §5.4.

## Sources

- `https://agents.md/` — AGENTS.md format steward, adoption, tool list, `@` import note.
- `https://developers.openai.com/codex/guides/agents-md` — Codex reads `AGENTS.md`, no `@` expansion,
  `project_doc_max_bytes` default 32 KiB.
- `https://code.claude.com/docs/en/memory` — Claude Code reads `CLAUDE.md`, `@AGENTS.md` import,
  symlink Administrator-privilege limitation on Windows.
- `docs/00-overview.md` — product purpose, three components, hard requirements, document map.
- `docs/02-herdr-probe-results.md` — measured Herdr socket facts, rules R-02-001 to R-02-017.
- `docs/03-product-decisions.md` — user-set product policy.
- `docs/11-relay-protocol.md` — wire protocol, messages, close codes, error taxonomy.
- `docs/12-relay-hosting.md` — relay architecture, crate dependency pins, workspace layout.
- `docs/13-security-pairing.md` — cryptography, pairing, identity, revocation.
- `docs/20-mobile-framework.md` — Flutter 3.47.0, Dart 3.13.0, dependency table.
- `docs/21-terminal-rendering.md` — terminal emulator library pick, render strategy.
- `docs/22-platform-integration.md` — keystore, biometrics, local notifications, deep links.
- `docs/23-public-release.md` — app-store metadata, release tracks, signing, versioning.
- `docs/41-code-standards.md` — coding rules, formatters, linters, anti-patterns.
- `.editorconfig` — editor configuration (already exists at repository root).
- `.gitattributes` — line-ending pins (already exists at repository root).
- `.gitignore` — ignore rules (already exists at repository root).
- `C:/Development/Repositories/other/herdr-scheduled/herdr-plugin.toml` — plugin manifest structure,
  `HERDR_PLUGIN_ROOT`, `-windows` suffix convention.
- `C:/Development/Repositories/other/herdr-scheduled/README.md` — test commands, test directory
  layout.
- `C:/Development/Repositories/other/herdr-scheduled/.gitattributes` — line-ending pins for shell and
  PowerShell.
- `C:/Development/Repositories/other/herdr-scheduled/tests/posix/test-headless-timeout.sh` — test
  pattern: stub `herdr`, temp dirs, pass/fail, no controlling terminal.
- `C:/Development/Repositories/other/herdr-standalone/.gitmodules` — plugin submodules
  (`herdr-scheduled`, `herdr-sidebar`).
- `C:/Development/Repositories/other/herdr-standalone/plugins/herdr-sidebar/CLAUDE.md` —
  agent-facing file in a sibling plugin.
- `C:/Development/Repositories/other/herdr-default-layout/herdr-plugin.toml` — plugin manifest,
  `HERDR_PLUGIN_ROOT`, `-windows` suffix.
- `C:/Development/Repositories/other/herdr-default-layout/.gitattributes` — line-ending pin for shell
  scripts.
- `markdownlint-cli2` 0.23.2 — <https://github.com/DavidAnson/markdownlint-cli2>
- `lychee` 0.24.2 — <https://github.com/lycheeverse/lychee>
- `mermaid` 11.16.0 — <https://github.com/mermaid-js/mermaid> — the exact parser version
  `@mermaid-js/mermaid-cli` 11.16.0 used to bundle.
- `jsdom` 30.0.1 — <https://github.com/jsdom/jsdom> — latest stable release on the pin date, per
  `R-40-054`.
- Node.js release schedule — `https://nodejs.org/en/about/releases` — Node 20 reached end of life
  on April 30, 2026; Node 24 is the Active LTS line.
- VS Code 1.121 release notes — `https://code.visualstudio.com/updates/v1_121` — built-in Mermaid
  Markdown Features extension; the third-party `bierner.markdown-mermaid` conflicts with it
  (microsoft/vscode#317870).
- VS Code marketplace, `DavidAnson.vscode-markdownlint` —
  `https://marketplace.visualstudio.com/items?itemName=DavidAnson.vscode-markdownlint`.
- VS Code marketplace, `EditorConfig.EditorConfig` —
  `https://marketplace.visualstudio.com/items?itemName=EditorConfig.EditorConfig`.
- `docs/10-herdr-integration.md` — Herdr 0.8.2, protocol 21, plugin manifest and packaging.
- Rust 1.98.0 stable release — `https://blog.rust-lang.org/2026/08/20/Rust-1.98.0/` — latest stable
  Rust release on the update date; edition 2024.
- Flutter releases — `https://docs.flutter.dev/release/archive` — Flutter 3.47.0 stable.
- Dart SDK — `https://dart.dev/get-dart` — Dart 3.13.0, bundled with Flutter.
- Android Studio — `https://developer.android.com/studio` — SDK platform 36, build-tools 36,
  platform-tools.
- Docker install — `https://docs.docker.com/engine/install/` — Docker Engine 24+.
- Ubuntu release list — `https://ubuntu.com/project/docs/release-team/list-of-releases/` — Ubuntu 26.04
  LTS is the latest Ubuntu LTS example for WSL guidance.
- Xcode — `https://developer.apple.com/xcode/` — Xcode 27, iOS 26 SDK.
- Flutter Swift Package Manager —
  `https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers` —
  native iOS dependency setup and removal of redundant CocoaPods integration.

## Open questions

1. **iOS CI build.** An iOS build needs a macOS runner with Xcode. **Recommended default:** when the
   implementation CI is set up, add an optional `ios` job with `continue-on-error: true` on
   `macos-latest`. Promote it to a required gate when the iOS signing pipeline is ready.

2. **Future task runner.** The implementation phase selects its own task runner (or direct
   invocations). This documentation repository uses direct commands only per §8.
   **Recommended default:** keep direct `cargo` and `flutter` commands in CI scripts. Add a task
   runner only if the workspace grows beyond three crates and one Flutter project.
