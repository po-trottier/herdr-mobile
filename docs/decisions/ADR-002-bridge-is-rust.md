# ADR-002: The bridge is a Rust binary, not a pair of shell scripts

## Status

## Status note

The repository became specification-only after this ADR was accepted (2026-08-24 remediation).
The bridge remains Rust; the future crate lives at `crates/herdr-relay/` in the Rust workspace
(see ADR-003). The shims do not exist in this specification-only repository.
Accepted

## Date

2026-08-24

## Context

Two finished documents disagreed about what the `herdr-relay` plugin is made of.

`docs/40-repo-tooling.md` section 3.1 scaffolded `plugins/herdr-relay/` as `posix/run.sh` plus
`windows/run.ps1`, and stated that the plugin has no build step. That followed the
`herdr-scheduled` reference plugin, which is entirely shell and PowerShell.

`docs/10-herdr-integration.md` R-10-006 required Rust, citing `herdr-sidebar`, which is a Rust Herdr
plugin that ships a compiled binary for all three platforms.

The bridge is not a short-lived hook. It must hold a long-lived Herdr subscription connection, run a
`Noise_XXpsk0` handshake, keep an outbound WebSocket to the Hub, gate reads on a `revision` counter,
and debounce a render loop at 120 ms.

A shell implementation would also mean every behaviour exists twice, once in `sh` and once in
PowerShell, and the two must stay in step for the life of the project. `docs/41-code-standards.md`
devoted a whole section to that burden.

## Decision

The bridge is one Rust crate. This decision is carried by `docs/10-herdr-integration.md` R-10-006
and `docs/decisions/ADR-003-rust-host-and-relay.md`.

The future `crates/herdr-relay/` within the Rust workspace is a Cargo crate. The bridge, the
Hub client and the `ratatui` popup pane all live in `src/`.

A shell or PowerShell shim will survive in the future implementation only to locate the compiled
binary through `HERDR_PLUGIN_ROOT`, because Herdr resolves a relative program against its own
install directory on Windows (upstream GH #58) and the variable can carry a `\\?\` prefix that
must be stripped. A shim holds no logic and stays under five lines. The five-line shim rule is
carried by `docs/41-code-standards.md` R-41-139.

The shims keep the `posix/` and `windows/` split of `herdr-scheduled`, so the platform gating stays
obvious and `check-twins` still applies to them.

## Consequences

Easier: one source compiles for Windows, Linux and macOS, so no behaviour needs a second
implementation. The `herdr-sidebar` socket client at
`plugins/herdr-sidebar/plugins/herdr-sidebar/src/ipc.rs` becomes a file to copy rather than a pattern
to reimplement; it already solves the named pipe versus `AF_UNIX` split, the one-request-per-connection
lifecycle, a 4 MiB response cap, and the missing read timeout on a Windows named-pipe handle.
`ratatui` and `crossterm` give the popup pane a real terminal UI, which a shell script could not.

Harder: the plugin now has a build step, `cargo build --release`, cross-compiled to three targets. CI
needs a Rust toolchain. Contributors need `cargo`. Three sections of finished documents became stale
and are corrected in `docs/01-architecture.md`:

- `R-01-003` is retired outright. The `justfile` referenced in the original ADR was deleted in the
  documentation-only remediation. This repository has no build step. Future implementation commands
  are specified in `docs/40-repo-tooling.md`.
- `R-01-004`: the POSIX and PowerShell twin rule is carried by `docs/41-code-standards.md`
  (R-41-143 through R-41-147). The twin rule now applies only to the shims.

Supersedes: the shell bridge layout in `docs/40-repo-tooling.md` section 3.1.
