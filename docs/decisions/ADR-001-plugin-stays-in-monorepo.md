# ADR-001: The `herdr-relay` plugin stays in this monorepo

## Status

Accepted

## Status note

The repository became specification-only after this ADR was accepted (2026-08-24 remediation).
The monorepo decision stands for when implementation begins. ADR-003 changed the future
workspace layout from `plugins/` to `crates/`.

## Date

2026-08-24

## Context

At the time of this decision the repository held four sub-projects: the documentation, the
`herdr-relay` plugin, the `herdr-relay-hub` service, and the `herdr-mobile` app. The
repository is now specification-only; the four sub-projects are future implementation targets.

Both reference Herdr plugins are separate repositories. `herdr-standalone` consumes them as git
submodules:

```ini
[submodule "plugins/herdr-scheduled"]
    path = plugins/herdr-scheduled
[submodule "plugins/herdr-sidebar"]
    path = plugins/herdr-sidebar
```

So the house convention is one repository per plugin. Following it here would mean splitting the
plugin out immediately.

Two options were considered.

| Option | Installation consequence | Coordination cost |
| --- | --- | --- |
| A. Keep in the monorepo | `herdr plugin link <path>/plugins/herdr-relay` for local work. The whole monorepo is cloned even when only the plugin is needed. | Low. A protocol change is one commit. |
| B. Split into its own repository | `herdr plugin install <git-url>` installs only the plugin. `herdr-standalone` can add it as a submodule. | High. A protocol change needs coordinated commits in several repositories, and the three components drift. |

The deciding fact is that the plugin, the Hub and the app all implement the same wire protocol,
defined in `docs/11-relay-protocol.md`. A change to that protocol touches all three at once.

## Decision

The `herdr-relay` plugin stays in this monorepo for version 1. This is `R-40-020`.
The decision that the plugin stays in one repository with the shared protocol crate and the
relay is unchanged. The future Rust workspace layout is under `crates/` (see ADR-003).
The path within the workspace is `crates/herdr-relay/`.
The `herdr-standalone` convention of one directory per plugin is preserved.

## Consequences

Easier: one commit changes the protocol on all three sides, so the three components cannot drift out
of step. One CI run gates the whole product. One version number describes a working set.

Harder: a user who wants only the plugin clones more than they need. The plugin cannot be consumed as
a submodule by `herdr-standalone` until it is split.

Revisit when: `herdr-standalone` needs `herdr-relay` as a submodule, or the protocol stops changing
and the three components genuinely version independently. At that point the move is
`git mv plugins/herdr-relay` into a fresh repository, and this ADR is superseded.
