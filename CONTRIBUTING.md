# Contributing

## What this repository is

This repository holds the specification, the agent and contributor guidance, and — as of Phase 0 —
the implementation itself. `crates/` (the Rust workspace) and `app/` (the Flutter project) now
exist and build, lint and test clean, in this same repository.

A documentation contributor may change `docs/**` and the root guidance files. A code contributor
follows the phase, wave and work-package process in `docs/90-implementation-plan.md`: a package
writes only the paths its `Owns.`/`Paths.` line names (R-90-016), and a shared path routes through
the `§5.3` registry (R-90-017).

## Document ownership map

One document owns one numeric rule prefix. Define a rule only inside your own prefix. Cite another
document's rule by id. The canonical index lives in `docs/01-architecture.md` section 8.
`AGENTS.md` section 3 repeats it for agents. This file does not copy the table.

`SECURITY.md`, `CONTRIBUTING.md`, `README.md`, `AGENTS.md` and `CLAUDE.md` define no rules. They
cite rules from the documents above.

## Rule-id convention

Every rule is numbered `R-<prefix>-<nnn>`. The prefix matches a document prefix in the index in
`docs/01-architecture.md` section 8. `<nnn>` is a three-digit zero-padded number, for example
`R-11-035`. A mockup is the one
exception: its prefix has two parts and its sequence has two digits, for example `R-31-13-04`,
because one file per screen keeps each list short. Each rule uses one of these words at the start:

- `MUST` — an absolute requirement.
- `MUST NOT` — an absolute prohibition.
- `SHOULD` — a strong recommendation. Deviate only with a documented reason.
- `MAY` — permitted, not required.

One fact lives in one place. A reader cites a fact from another document by rule id, for example
`R-11-035`. A reader never restates the nucleated fact in prose. A rule id appears exactly once as a
definition and zero or more times as a citation.

### Retiring a rule, and reusing its number

A retired rule keeps its id, so a reader who finds an old citation is not lost. Each owning document
carries a `## Retired rules` table with one row per retired id.

Two things can happen to a retired id, and the table MUST tell them apart. Write the id plainly when
nothing carries that number any more. Write the word `old` directly after the id when a different
rule now carries the number.

```markdown
| `R-30-514` | Retired. Replaced by `R-30-509`. |
| `R-41-072` old | Retired, and the id is reused. See `R-41-072` above. |
```

Always write `old` when the number is reused. Without it, a reader or a check cannot tell a live
citation from a dangling one, and a live rule looks retired. Every citation of a reused id points at
the current rule, never at the old one.

## Source citation format

Every mutable fact carries a source in `## Sources` at the end of its document. The format is:

```markdown
- Short title:
  `https://example.com/page`
  — what the source proved.
```

A mutable fact is anything that can change independently of this repository: an external version
number, a store requirement, a measured performance number, an external API behaviour. A design
decision that this repository made is not mutable and does not need a source. A source URL links to
the exact page, not to a root domain or an index page.

### A rule that rests on a platform gap

A rule whose reason is that a platform publishes no guidance is making a claim about the world, and
the claim decays. The phrase to watch is `publishes no rule`, or any wording that turns an absence
of research into a licence to decide.

Three rules in this repository carried that shape and all three were wrong. One fixed a dialog
button order because "Apple publishes no button-order rule", and Apple does publish one. One
required a per-platform back control because a shared icon "does not mirror for right-to-left", and
it does. One stated that a plugin action "creates no entities", and half of the measured actions
create a pane.

So a rule that rests on an absence MUST name, in `## Sources`, the page that was read, the date it
was read, and **what was searched for**. The third part matters as much as the first two. These
claims go wrong because the author searched for the wrong noun, not because the author skipped the
search. One verification in this repository succeeded only because the page happened to state the
platform behaviour beside the deprecation notice; a search for the API name alone would have
reported a rename and missed that the platform discourages the whole mechanism.

### A rule that cites another rule as a prohibition

A rule that says `R-nn-nnn forbids X` is the easiest claim in this repository to check and the least
often checked, because citing a neighbouring rule feels like rigour. Read the cited rule and confirm
it forbids **X** and not some narrower Y. Then quote the clause you relied on, so the next reader
checks a sentence instead of a number.

Two rules in this repository asserted a prohibition that the cited rule did not contain. One would
have removed a control from four live surfaces, including one required by the same author's own
rule. Both had defensible conclusions, which is why review found nothing: a reviewer who checks
conclusions cannot see a false reason.

The two smells above share a shape. The conclusion is sound and the stated reason is false, so the
rule survives review and then decays, because the next author extends the reason rather than the
conclusion. Prefer a reason that can be checked from inside the repository, and quote it.

## Simplified Technical English

Prose is ASD-STE100 Simplified Technical English. This is a controlled subset of English designed to
make technical text clear, unambiguous and translatable. The key rules:

- One meaning for each word. One word for each meaning.
- Short sentences. At most 20 words for an instruction, 25 words for a description.
- One instruction in one sentence. Put the action at the start.
- Active voice. Name the person or the thing that does the action.
- Do not make a noun from a verb.
- Use simple verb tenses.
- Do not use an `-ing` phrase as a modifier. Write a new sentence, or use `that` or `which`.
- Do not use slang, idioms or metaphors. Do not use jargon that a plain word can replace.
- Change a long sentence into a list or a table.

### Before and after

**Before (not STE):**

> Upon completion of the handshake, the developer will be presented with a pairing confirmation
> dialog, which, after being acknowledged, will result in the Device's static public key being
> pinned to the Host's keystore.

**After:**

> The handshake finishes. The Host shows a pairing confirmation dialog. The developer acknowledges
> the dialog. The Host pins the Device's static public key in the Host's keystore.

**Before (not STE):**

> In the event that the relay service experiences an unexpected termination, the Host and Device
> connections are both severed, necessitating a reconnect attempt with exponential backoff.

**After:**

> The relay stops. The Host connection and the Device connection both close. The Host and the
> Device each try to reconnect. The reconnect backoff schedule is in R-22-028.

**Before (not STE):**

> It is recommended that contributors utilize the built-in validation commands to ensure their
> documentation modifications maintain consistency with the repository's established conventions.

**After:**

> Use the validation commands in the `## Validate the documentation` section to check your
> documentation changes.

Code, identifiers, paths and commands stay exact. Do not rewrite them to STE. The prose around them
is STE.

## Architecture Decision Records

A decision that needs a permanent record becomes an Architecture Decision Record, an ADR. The file
name pattern is `docs/decisions/ADR-<nnn>-<slug>.md`. `<nnn>` is a sequential three-digit number.
`<slug>` is a short hyphenated phrase that names the decision, for example
`ADR-003-rust-host-and-relay`.

### Required sections

| Section | Purpose |
| --- | --- |
| `# <Title>` | The decision in a sentence. |
| `## Status` | `Accepted` or `Superseded by ADR-<nnn>`. |
| `## Context` | The problem, the alternatives and the constraints that shaped the choice. |
| `## Decision` | What was chosen and why. |
| `## Consequences` | What becomes easier, what becomes harder, and what follow-up work is needed. |

### Superseding an ADR

A new ADR that reverses a previous one MUST state `## Status: Supersedes ADR-<nnn>` in its own status
section. The previous ADR's status MUST be changed to `Superseded by ADR-<nnn>`. Both changes go in
one pull request. The superseded ADR stays in the repository, with its content unchanged except for
the status line.

## Agent instruction files

The repository gives guidance to coding agents through one `AGENTS.md` plus pointer files, with no
duplicated text.

- Layout, rules and pointer procedure: `AGENTS.md` section "Agent compatibility".
- Decision, evidence and rejected alternatives:
  `docs/decisions/ADR-006-agent-instruction-files.md`.

There is no `.omp/`, no `.cursor/`, no `.claude/`, no `GEMINI.md` and no
`.github/copilot-instructions.md` in this repository.

## Validate the documentation

No task runner, no package manifest and no committed script. Run these commands directly. Use the
exact pinned versions.
The per-OS install commands and the reference editor are in `docs/40-repo-tooling.md` §7.1. The
future build prerequisites are in §7.2.

### Markdown structure

```bash
npx markdownlint-cli2@0.23.2 "**/*.md"
```

### Local links

```bash
lychee 0.24.2 --offline --no-progress "**/*.md"
```

Then an online pass for public URLs:

```bash
lychee 0.24.2 --no-progress "**/*.md" --exclude 'docs/15-nvidia-brev-relay-experiment.md'
```

URLs in `docs/15-nvidia-brev-relay-experiment.md` point to internal NVIDIA resources. Check those
only from the NVIDIA network, as a separate step.

### Mermaid diagrams

`docs/40-repo-tooling.md` §8.3 has the exact command: `mermaid` plus `jsdom` calling
`mermaid.parse()` in an isolated `/tmp` prefix, with no headless browser (`R-40-057`). It is one
script, so it is not restated here.

### Rule-consistency audit

Check that every cited rule id exists exactly once and that no placeholder remains:

```bash
# List every defined rule id
grep -rohP 'R-\d{2}(-\d{1,2})?-\d{3}' docs/ | sort | uniq -c | sort -rn
```

Look for:

- A count greater than 1: a rule is defined more than once.
- A cited rule id that does not appear in this list: the definition is missing.
- `R-xx-xxx`: a placeholder that was never replaced.

A manual check for banned terms completes the audit. Search for each term in the list under
`## Docs-only completion checklist`. A normative match is a failure. A match inside a `## Sources`
URL, a code fence, or a historical ADR record is acceptable.

### Docs-only completion checklist

After every documentation change, confirm these items before submitting a pull request:

- [ ] Every relative Markdown link resolves to a file that exists in the repository.
- [ ] Every Mermaid block parses. Run the Mermaid checker above.
- [ ] Every document has exactly one `H1` heading outside a code fence.
- [ ] Every code fence is balanced. Every ` ``` ` has a matching close.
- [ ] Every `.md` file ends with a final newline.
- [ ] Every document that states a mutable fact has a `## Sources` section that lists the URL and what
  it proved.
- [ ] Every `## Open questions` item is either a genuine external dependency with a stated default,
  or
  it is removed.
- [ ] No normative text contains a banned claim. Search for: `firebase_messaging`, `FCM`, `APNs`,
  `silent push`, `contentless push`, `nhooyr`, `go-qrcode`, `golangci`, `go vet`, `plugins/` as a
  current-path claim, `justfile` as a current-path claim, `.herdr-api-schema.json` as a current-path
  claim, `relay.herdr.nvidia.com` as an app default, a Hub QR endpoint, a reconnect broadcast,
  `TODO`, `TBD`, `R-xx-xxx`, "language undecided", "stale", 8-digit code, 6-digit code,
  `SHA256(code)`, and `device_already_joined`.

## Pull request expectations

A pull request description MUST state:

1. What changed and why.
2. Which document's rules were added, changed or removed. Cite rule ids.
3. Which open questions were resolved or added.
4. Whether the change requires an ADR and, if so, which one.

A commit that adds a future implementation dependency to a document MUST name the reuse-ladder rung
that failed. The ladder, in order:

1. Does it need to exist at all?
2. Does the platform do it natively?
3. Does the standard library do it?
4. Does a dependency the project already picked do it?
5. Only then: new dependency.

The commit message states the rung that failed, for example: "Add `crossterm` to plugin dependency
table — native terminal control on Windows needs the Windows Console API, stdlib has no cross-platform
abstraction, no existing workspace crate covers it."
