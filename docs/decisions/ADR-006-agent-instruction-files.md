# ADR-006: Single `AGENTS.md` with pointer files, no duplicated guidance

## Status

Accepted.

## Date

2026-08-24

## Context

This repository must serve three agent harnesses: omp, OpenAI Codex and Claude Code. Before this
decision the repository held both a root `AGENTS.md` (read by omp and Codex) and an
`.omp/RULES.md` (read only by omp as sticky always-active rules). The rules in `.omp/RULES.md`
restated standing project rules already in `AGENTS.md`.

Two copies of the same guidance meant two places to update, and a rule only omp could see that
Codex and Claude Code never received. The layout needed to eliminate duplication while keeping
every harness fed.

## Decision

`AGENTS.md` is the single, self-contained source of standing agent guidance. `CLAUDE.md` holds the
literal line `@AGENTS.md` and nothing else except an optional short Claude-only note.
`.omp/RULES.md` is deleted.

No other agent file exists. No `.cursor/rules/`, no `.github/copilot-instructions.md` and no
`GEMINI.md`.

### Evidence

1. `AGENTS.md` is the open format for agent instructions, used by more than 60000 public
   repositories and stewarded by the Agentic AI Foundation under the Linux Foundation.
   Source: `https://agents.md/`.

2. Claude Code reads `CLAUDE.md`, not `AGENTS.md`. Claude's own documentation gives the
   no-duplication pattern: a `CLAUDE.md` that imports `@AGENTS.md`, with any Claude-specific text
   below the import. Source: `https://code.claude.com/docs/en/memory`.

3. Codex reads `AGENTS.md` as plain text and does not expand `@` imports. It walks the directory
   tree and concatenates the files it finds, and it truncates at `project_doc_max_bytes` (default
   32 KiB). Therefore `AGENTS.md` MUST be self-contained and MUST NOT rely on an `@` import to
   deliver a rule. Sources: `https://developers.openai.com/codex/guides/agents-md` and
   `https://agents.md/`.

4. omp reads the standalone root `AGENTS.md` through its `agents-md` discovery provider, which
   walks up from the working directory to the repository root. The file Codex needs is already
   the file omp loads.

### Rejected alternatives

1. **A `CLAUDE.md` symlink to `AGENTS.md`.** Rejected because Claude's own documentation says a
   symlink needs Administrator privileges or Developer Mode on Windows, and this project is
   developed on Windows. A Git symlink checked out without `core.symlinks` becomes a plain text
   file holding a path, which silently breaks the pointer. The `@AGENTS.md` import works everywhere
   and needs no privilege. Source: `https://code.claude.com/docs/en/memory`.

2. **Keep `.omp/RULES.md` as a copy of the standing rules.** Rejected as duplication. Every rule in
   `.omp/RULES.md` was also in `AGENTS.md`, so updating a rule meant updating it twice, and the
   two copies could drift.

3. **Make `.omp/RULES.md` an `@../AGENTS.md` import.** Rejected because omp would then inject
   `AGENTS.md` twice in one session: once as a sticky rule (via `.omp/RULES.md` importing
   `AGENTS.md`) and once as a context file (via the `agents-md` provider). Two copies of the same
   instructions in one session produce redundancy and potential conflict.

## Consequences

The repository loses omp's sticky always-apply reinforcement, which `.omp/RULES.md` provided.
Sticky rules stay active through a long session without being re-read from the file. Without
`.omp/RULES.md`, an omp session relies on the single injection of `AGENTS.md` at session start.

This cost is accepted. A rule that only one of three harnesses can see (the omp sticky rule) is
worse than a rule with no sticky reinforcement but seen by all three.

`AGENTS.md` MUST stay self-contained and MUST stay under 32 KiB so Codex never truncates it. The
target is under 400 lines. `CLAUDE.md` MUST stay a pointer. If a Claude-only instruction is ever
needed, it goes below the `@AGENTS.md` line and nowhere else.

To support a new agent that cannot read `AGENTS.md`, add a pointer file for it — never a copy.
Record the addition in the `AGENTS.md` compatibility section. `README.md` is for humans;
`AGENTS.md` is for agents; `CONTRIBUTING.md` is for the human contributor process. Overlap is
limited to the one-paragraph product summary.
