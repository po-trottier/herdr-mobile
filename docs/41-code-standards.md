# Code Standards

This document is normative. Every rule states `MUST` or `SHOULD` and carries a one-line rationale.
A `MUST` violation is a bug. A `SHOULD` violation needs a stated reason in a code comment.

Other documents cite these rules as `R-41-nnn`.

Scope of each section:

| Section | Applies to | Status |
|---|---|---|
| §1 Universal rules | Every file, every language | Active |
| §2 POSIX shell | `crates/herdr-relay/posix/*.sh` (future launcher shims) | Active |
| §3 PowerShell | `crates/herdr-relay/windows/*.ps1` (future launcher shims) | Active |
| §4 Dart | Future Flutter app | Active |
| §5 Rust | `crates/herdr-relay-proto/`, `crates/herdr-relay/`, `crates/herdr-relay-hub/` | Active |
| §6 Cross-platform plugin scripts | The future POSIX and PowerShell launcher shims | Active |
| §7 Herdr socket client | Any code that opens the Herdr socket | Active |

There is no task runner in this repository. Every command shown in this document is a direct
invocation. `docs/40-repo-tooling.md` §8 documents the validation commands for this documentation
repository. The implementation commands below are for the future implementation phase.

## §1 Universal rules

### 1.1 Naming

**R-41-001** A file name MUST use `kebab-case`. Exceptions: a Dart file MUST use `snake_case`
(R-41-104). **Rationale:** one convention per language ecosystem removes the guess.

**R-41-002** A directory name MUST use `kebab-case`. **Rationale:** a directory name is never
compiled, so one repository-wide rule applies.

**R-41-003** A file name and a directory name MUST use lowercase ASCII letters, digits, hyphens, and
underscores only. **Rationale:** Windows is case-insensitive and Linux is case-sensitive. Lowercase
names cannot collide across the two.

**R-41-004** A type, a class, an enum, and a struct name MUST use `PascalCase`. **Rationale:** all
three languages in this product use this convention.

**R-41-005** A function name and a method name MUST use `camelCase` in Dart. It MUST use `snake_case`
in Rust. It MUST use `snake_case` in POSIX shell. It MUST use `Verb-Noun` in PowerShell.
**Rationale:** each language has one accepted form. A second form beside it creates two conventions.

**R-41-006** A constant MUST use `UPPER_SNAKE_CASE` in POSIX shell and Rust. It MUST use
`PascalCase` in PowerShell. It MUST use `camelCase` in Dart. **Rationale:** same as R-41-005.

**R-41-007** A boolean name MUST start with `is`, `has`, `can`, `should`, or `was`. Examples:
`isPaired`, `hasRevoked`, `canReconnect`. **Rationale:** a boolean answers a question. The prefix
makes `true` unambiguous.

**R-41-008** A name MUST NOT abbreviate unless the abbreviation is a standard term. `ansi`, `qr`,
`id`, `url`, and `tls` are permitted. `cfg`, `mgr`, `hdlr`, and `btn` are not. **Rationale:** an
invented abbreviation costs the reader a lookup.

**R-41-009** A name MUST NOT repeat its container. Write `session.id`, never `session.sessionId`.
**Rationale:** the container already supplies the context.

### 1.2 File size and structure

**R-41-010** A source file MUST NOT exceed 400 lines, excluding a licence header and import block.
**Rationale:** a reviewer reads a 400-line file in one sitting. A longer file hides defects.

**R-41-011** A file that exceeds 400 lines MUST be split along a responsibility boundary, not at an
arbitrary line. Each new file MUST have one reason to change. **Rationale:** a split at line 400
produces two files that both need the same edit. A split at a responsibility boundary does not.

**R-41-012** A function MUST NOT exceed 60 lines. **Rationale:** 60 lines fit one screen. A function
that does not fit cannot be verified by reading.

**R-41-013** A function that exceeds 60 lines MUST be split by extracting a named private helper.
**Rationale:** a name is documentation that the compiler checks.

**R-41-014** A function MUST NOT take more than 5 parameters. **Rationale:** six positional
arguments at a call site are easy to transpose, and the compiler cannot detect it when the types
match.

**R-41-015** A function that needs more than 5 inputs MUST take one options object, struct, or
parameter block. **Rationale:** a named field at the call site cannot be transposed.

**R-41-016** Nesting depth MUST NOT exceed 4 levels, where the function body is level 0.
**Rationale:** deep nesting hides the exit conditions.

**R-41-017** A function SHOULD return early to reduce nesting. Validate first, then act.
**Rationale:** an early return removes an `else` branch and one nesting level.

### 1.3 Comments

**R-41-018** A comment MUST explain why the code does something. **Rationale:** the code states
what it does. A reader needs the reason, which the code cannot state.

**R-41-019** A comment MUST NOT restate the code. `// increment the counter` above `counter++` is
forbidden. **Rationale:** a restating comment adds no information and rots when the code changes.

**R-41-020** A comment MUST record a non-obvious constraint, a measured value, an upstream defect, or
a rejected alternative. **Rationale:** these four facts are invisible in the code and expensive to
rediscover. The reference plugins do exactly this. See `herdr-scheduled/posix/common.sh` lines
745–757, which record a measured convergence sequence and the reason `pane resize` replaced
`pane swap`.

**R-41-021** A commented-out code block MUST NOT be committed. Delete it. **Rationale:** Git holds
the history. Disabled code makes the reader ask whether it should run.

**R-41-022** Every exported symbol MUST carry a doc-comment of at least one sentence that states its
purpose. **Rationale:** a symbol with no doc-comment forces the reader to read the body.

**R-41-023** A deliberate shortcut MUST carry a `ponytail:` comment that states the accepted risk.
**Rationale:** the reference plugins use this marker. See `herdr-scheduled/posix/common.sh` lines
462–464. It makes a deferral visible instead of silent.

### 1.4 Error handling

**R-41-024** A caught exception MUST NOT be discarded. Every catch block MUST log the error, wrap and
rethrow it, or change observable behaviour. **Rationale:** a discarded exception hides a defect and
moves the symptom far from the cause.

**R-41-025** An empty catch block MUST NOT be committed. **Rationale:** it is the written form of
R-41-024's violation.

**R-41-026** An error that crosses a module boundary MUST be a typed error or a wrapped error. It
MUST NOT be a bare string or a bare platform exception. **Rationale:** the caller needs to branch on
the error kind. A string forces string matching, which breaks when the message changes.

**R-41-027** A wrapped error MUST keep the cause. Use `#[source]` on a `thiserror` variant in Rust,
the `cause` field in Dart, and `-Exception` in PowerShell. **Rationale:** the root cause is the only
actionable part of a stack of five wraps.

**R-41-028** An error message MUST name the operation and the entity. `connection refused` is
forbidden. `hub connect wss://relay.example.com/device/<handle> failed: connection refused` is
required. **Rationale:** an operator reads the log without the source open.

**R-41-029** An error message MUST be one sentence and MUST NOT end with a full stop.
**Rationale:** a log aggregator concatenates messages. A consistent form stays readable.

### 1.5 Logging

This product moves terminal content across a network. The logging rules matter more here than in a
normal project, because the payload is exactly the thing that must never be logged.

**R-41-030** A log line MUST NOT contain terminal content, in ANSI form or in plain text.
**Rationale:** a terminal pane shows source code, passwords typed at a prompt, tokens echoed by a
build, and private repository names. It is the highest-value payload in the system.

**R-41-031** A log line MUST NOT contain a pairing phrase, a routing handle, a key, a token, a
password, or any key material. **Rationale:** a pairing phrase grants access to a Host. A log
aggregator has weaker access control than the Host screen that showed the phrase.

**R-41-032** A log line MAY contain the length, the count, the revision, and the duration of a
payload. **Rationale:** these describe the payload without disclosing it, which is enough to debug a
transport defect.

**R-41-033** A frame-forwarding path MUST NOT log at `DEBUG` in a way that a configuration change can
turn into payload logging. The payload MUST NOT be reachable from any log call site.
**Rationale:** a `DEBUG` switch that leaks terminal content is one environment variable away from a
breach. Absence of the code is the only reliable control.

**R-41-034** A log level MUST follow this table:

| Level | Meaning |
|---|---|
| `ERROR` | The operation failed. A person must act. |
| `WARN` | The operation degraded and recovered. A person SHOULD review it. |
| `INFO` | A lifecycle event: start, stop, paired, revoked, connected, disconnected. |
| `DEBUG` | Trace detail for a reported defect. Off by default. |

**Rationale:** an explicit table removes the per-author judgement call.

**R-41-035** The relay MUST log only the fields that `docs/12-relay-hosting.md` R-12-014 permits:
timestamp, session ID, connection event, peer count, frame count, frame byte total, and error
message. **Rationale:** R-12-014 is the security commitment made to the reviewer. The code must
match it.

### 1.6 Input validation

**R-41-036** Every trust boundary MUST validate its input before use. The trust boundaries are: the
Herdr socket, the relay WebSocket, the Device WebSocket, a file read, an environment variable, and a
command-line argument. **Rationale:** an unvalidated input at a boundary is either a crash or a
silent wrong answer.

**R-41-037** Validation MUST reject, not repair. An invalid input MUST produce a typed error.
**Rationale:** a repaired input produces a plausible wrong result, which is harder to diagnose than
a rejection.

**R-41-038** Validation MUST NOT substitute a silent default for an invalid value. **Rationale:** a
silent default converts a configuration mistake into a runtime mystery.

**R-41-039** A length-prefixed frame MUST have its length checked against the maximum before
allocation. The maximum is 1 MiB (1048576 bytes) uncompressed JSON, per
`docs/11-relay-protocol.md` R-11-035. **Rationale:** an attacker who sends a 4 GiB length prefix
causes an allocation failure. The single value for the whole repository is 1 MiB.

**R-41-040** A value that reaches a shell command, a file path, or a process argument MUST be
validated against an allow-list character set, never an escape-and-hope filter. **Rationale:** the
reference plugins do this. `herdr-scheduled/posix/common.sh` line 54 validates an identifier with
`^[a-z][a-z0-9_-]{0,31}$` before it becomes a file name.

### 1.7 Dependencies

**R-41-041** A new dependency MUST be justified in the commit message in one sentence. The sentence
MUST name the alternative that was rejected and the reason. **Rationale:** every dependency is a
future CVE, a build cost, and a breaking change outside our control.

**R-41-042** A new dependency MUST NOT be added before the reuse ladder is climbed. Stop at the
first rung that holds:

1. Does this need to exist? Cut it if it is speculative.
2. Does the platform or the framework do it natively?
3. Does the standard library do it?
4. Does a dependency already in the manifest do it?
5. Only then add the minimum new dependency.

**Rationale:** this is the project's headline constraint. A rung skipped is a dependency that did not
need to exist.

**R-41-043** A dependency version MUST be pinned to an exact `major.minor.patch` triple. A caret
range, a tilde range, and `latest` are forbidden. **Rationale:** a floating version means a green
build can turn red with no commit. It also means a local build and a CI build can run different code.

**R-41-044** A dependency MUST be recorded with its exact package name, version, licence, and
repository URL in the document that selects it. **Rationale:** a licence review needs these four
facts, and finding them later costs more than recording them now.

**R-41-045** A dependency whose last release is more than 24 months old MUST NOT be added unless no
maintained alternative exists, and the commit message MUST state that finding. **Rationale:**
`docs/12-relay-hosting.md` rejected Gorilla WebSocket for exactly this reason: unmaintained since
December 2022.

### 1.8 Formatting

**R-41-046** Every file MUST end with exactly one newline. **Rationale:** POSIX tools and Git treat
a
missing final newline as a diff artefact on every later change.

**R-41-047** A line MUST NOT carry trailing whitespace. Markdown is exempt, because two trailing
spaces mean a hard line break there. **Rationale:** trailing whitespace is invisible and produces
noise in every diff.

**R-41-048** Indentation MUST use spaces. **Rationale:** a tab renders at a different width in
different tools, which breaks alignment.

**R-41-049** Line endings MUST be `LF`, except `*.ps1`, `*.psm1`, and `*.psd1`, which MUST be `CRLF`.
`.gitattributes` enforces this. **Rationale:** `sh` refuses a script whose lines end in `CR`. The
reference plugins pin `LF` for this reason. See `herdr-scheduled/.gitattributes` lines 1–2.

### 1.9 Paths

**R-41-050** A file path MUST be built with the platform's join function: `Join-Path` in PowerShell,
`path.join` in Dart, `Path::join` in Rust. String concatenation with a literal separator is
forbidden. **Rationale:** `"dir" + "/" + "file"` is wrong on Windows.

**R-41-051** A hard-coded platform path MUST NOT appear in cross-platform code. `/tmp`, `/var/run`,
`C:\Windows`, and a literal `%APPDATA%` are forbidden. Use the platform's environment variable or
the standard library function. **Rationale:** a path that is correct on one operating system is
absent on another.

## §2 POSIX shell

Applies to the future `crates/herdr-relay/posix/*.sh` launcher and service shims. These shims are at
most five lines each. They launch the Rust binary and forward the exit code. They hold no application
logic, no temporary files, no locks and no scheduling. Every behaviour the Rust binary owns MUST NOT
be duplicated in a shim.

**R-41-054** A `.sh` file MUST NOT use a bashism. It MUST run under `dash`, `ash`, `busybox sh`, and
`bash`. Arrays, `[[ ]]`, `local -n`, `${var,,}`, and `$RANDOM` are forbidden. **Rationale:** Debian
and Alpine link `/bin/sh` to `dash` and `ash`. macOS ships `bash` 3.2. The plugin runs on all of
them.

**R-41-055** A `.sh` file MUST NOT require `jq`, `python`, `perl`, or any tool outside a POSIX base
system. **Rationale:** `herdr-default-layout/scripts/lib.sh` lines 4–6 state this rule and honour it.
A shim that needs `jq` fails on a clean machine.

### 2.2 Strict-mode preamble

**R-41-056** Every `.sh` file MUST begin with exactly these two lines:

```sh
#!/bin/sh
set -eu
```

`set -e` exits on the first unchecked failure. `set -u` makes a reference to an unset variable an
error. **Rationale:** both reference plugins use this preamble. `herdr-scheduled/posix/common.sh`
line 4 is `set -eu`. Without it, a failed command leaves the script running on garbage state.

**R-41-057** A sourced library file MUST NOT carry a shebang, and MUST carry `set -eu`.
**Rationale:** `herdr-default-layout/scripts/lib.sh` line 1 documents that the file is sourced and
never run alone. A shebang on a sourced file is misleading.

### 2.3 Naming

**R-41-058** A shell function MUST use `snake_case`. **Rationale:** POSIX convention, and both
reference plugins follow it (`valid_id`, `now_stamp`, `workspace_slot`).

**R-41-059** A global variable MUST use `UPPER_SNAKE_CASE`. **Rationale:** it matches the environment
variables it sits beside, such as `CFG_DIR` and `STATE_DIR` in
`herdr-scheduled/posix/common.sh` lines 10 and 15.

**R-41-060** A private helper function and a private global MUST start with one underscore.
**Rationale:** `herdr-scheduled/posix/common.sh` uses `_ws_map_get`, `_ws_probe`, and `_TAB` for
exactly this. The underscore marks the symbol as internal, which shell cannot enforce.

### 2.4 File layout

**R-41-061** A `.sh` file MUST order its contents:

1. Shebang, then a comment block that states the file's purpose and how it is invoked.
2. `set -eu`.
3. Directory and path constants derived from `HERDR_PLUGIN_ROOT`.
4. Other constants.
5. Helper functions, grouped by topic under a `# --- topic ---` banner comment.
6. Main logic, or a `main "$@"` call on the last line.

**Rationale:** `herdr-scheduled/posix/common.sh` follows this order exactly, including the banner
comments at lines 6, 27, 52, 93, and 126. A reader always finds the entry point at the bottom.

### 2.5 Quoting and word splitting

**R-41-062** Every variable expansion MUST be double-quoted. **Rationale:** an unquoted expansion
that holds a space splits into two arguments, and one that holds `*` expands against the working
directory.

**R-41-063** An expansion MAY be unquoted only when word splitting is the intent, and the line MUST
carry a comment that says so. **Rationale:** intentional splitting and a defect look identical
without the comment.

**R-41-064** `"$@"` MUST be used to forward arguments. `$*` and `"$*"` MUST NOT be used for
forwarding. **Rationale:** `"$@"` preserves argument boundaries. `"$*"` joins every argument into
one string.

**R-41-065** Command substitution MUST use `$(...)`. Backticks MUST NOT be used. **Rationale:**
backticks do not nest and are hard to see.

**R-41-066** A variable that reaches a `grep`, `sed`, or `awk` pattern MUST be escaped for that tool,
or validated against an allow-list first. **Rationale:** `herdr-scheduled/posix/common.sh` lines
531–536 document this hazard and escape the backslash and the quote before matching a label.

**R-41-067** `printf '%s' "$var"` MUST be used to emit a variable. `echo "$var"` MUST NOT be used.
**Rationale:** `echo` interprets a leading `-` as an option and processes backslash escapes on some
shells. Both reference plugins use `printf`.

### 2.6 Error handling

**R-41-068** A function that can fail MUST return a non-zero exit status. **Rationale:** shell has no
exceptions. The exit status is the only error channel.

**R-41-069** A caller that can recover MUST test the status with `if ! fn; then` or `fn || handler`.
A caller that cannot recover MUST leave `set -e` to exit. **Rationale:** an untested call under
`set -e` aborts the script, which is correct for an unrecoverable error and wrong for a recoverable
one.

**R-41-070** A pipeline MUST NOT hide a failure. POSIX `sh` has no `pipefail`, so a pipeline whose
first stage can fail MUST be restructured into separate commands with an intermediate variable.
**Rationale:** `set -e` inspects only the last command in a pipeline. A failure upstream is silent.

**R-41-071** A required environment variable MUST be asserted with `:?` and a message that names the
plugin. The exact form is in R-41-153. **Rationale:** the expansion prints the message to stderr and
exits 1, which is the shortest correct form.

## §3 PowerShell

Applies to the future `crates/herdr-relay/windows/*.ps1` launcher and service shims. These shims are
at most five lines each. They launch the Rust binary and forward the exit code. They hold no
application logic, no temporary files, no locks, no concurrency and no scheduling. Every behaviour
the Rust binary owns MUST NOT be duplicated in a shim.

### 3.1 Strict-mode preamble

**R-41-075** Every `.ps1` file MUST begin with exactly these two lines:

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
```

`Set-StrictMode -Version Latest` makes an uninitialised variable and a missing property into errors.
`$ErrorActionPreference = 'Stop'` makes a cmdlet error terminate the script.
**Rationale:** `herdr-scheduled/windows/common.ps1` lines 1–2 are exactly these two lines. Without
`Stop`, PowerShell prints a red line and continues with wrong state.

**R-41-076** Every read of an optional property on a Herdr object MUST test
`$obj.PSObject.Properties[$name]` first. **Rationale:** Herdr omits a field it has no value for, so
`$pane.label` throws under `Set-StrictMode`. `herdr-default-layout/scripts/lib.ps1` lines 10–15
document this and provide `Get-PaneField` for it:

```powershell
function Get-PaneField($pane, [string]$name) {
    if ($pane.PSObject.Properties[$name]) { return [string]$pane.$name }
    return ''
}
```

### 3.2 Naming

**R-41-077** A function MUST be named `Verb-Noun`, where the verb comes from `Get-Verb`.
**Rationale:** the reference plugins use this form (`Get-TaskName`, `Save-Job`, `Invoke-Herdr`,
`Remove-VerbatimPrefix`).

**R-41-078** A variable MUST use `PascalCase`. **Rationale:** `herdr-scheduled/windows/common.ps1`
uses `$HerdrBin`, `$PluginRoot`, `$CfgDir`, and `$StateDir`.

**R-41-079** The PowerShell executable path MUST be the literal
`C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`. **Rationale:**
`herdr-scheduled/windows/common.ps1` line 20 states this is the only PowerShell the plugin may
assume on Windows. `pwsh` is not guaranteed present.

### 3.3 File layout

**R-41-080** A `.ps1` file MUST order its contents:

1. `Set-StrictMode` and `$ErrorActionPreference`.
2. A comment block that states the file's purpose and how it is dot-sourced or invoked.
3. `$HerdrBin` resolution.
4. `$PluginRoot` resolution, including the `\\?\` strip.
5. Directory variables.
6. Other constants.
7. Functions.
8. Main logic.

**Rationale:** `herdr-scheduled/windows/common.ps1` follows this order: preamble at lines 1–2,
purpose at 4–5, `$HerdrBin` at 8–17, `$PluginRoot` at 23, directories at 27–53, constants at 55–56,
functions from 58.

### 3.4 Error handling

**R-41-081** A native command's exit code MUST be tested explicitly. **Rationale:**
`$ErrorActionPreference` does not apply to a native command. The reference pattern from
`herdr-scheduled/windows/common.ps1` lines 306–310:

```powershell
$p = Invoke-HerdrProcess $HerdrArgs
if ($p.ExitCode -ne 0) { throw "herdr $($HerdrArgs -join ' ') failed with exit code $($p.ExitCode): $($p.Stderr)" }
```

**R-41-082** A native command's stderr MUST be redirected to a pipe, not to the PowerShell error
stream. **Rationale:** `herdr-scheduled/windows/common.ps1` lines 267–268 state the reason: with
`$ErrorActionPreference = 'Stop'`, stderr on the error stream becomes a `NativeCommandError` and
aborts the script even when the command succeeded.

**R-41-083** A fatal condition MUST use `throw` with a one-sentence message that names the operation
and the entity. **Rationale:** under `Stop`, `throw` produces a terminating error whose message
reaches both the popup pane and the plugin log.

**R-41-084** A `try`/`catch` that intends to ignore a failure MUST state why in a comment inside the
`catch` block. **Rationale:** `herdr-default-layout/scripts/lib.ps1` line 29 uses `catch { }`, and
lines 17–20 explain it: a payload that does not parse must degrade to the caller's next resolution
step. Without that comment the empty catch violates R-41-025.

**R-41-085** A UTF-8 file write MUST use `New-Object System.Text.UTF8Encoding($false)` and
`[System.IO.File]::WriteAllText`. **Rationale:** `herdr-scheduled/windows/common.ps1` line 35 does
this. `Out-File` and `Set-Content` write a byte-order mark by default, which the POSIX twin then
reads as content.

## §4 Dart

Applies to the future Flutter app. Flutter 3.47.0 and Dart 3.13.0 are the pinned toolchain per
`docs/20-mobile-framework.md`. The terminal emulator is `xterm2` 5.2.0 per
`docs/21-terminal-rendering.md` R-21-005.

### 4.1 Formatter

**R-41-086** Every `.dart` file MUST be formatted by `dart format`. The formatter ships in the Dart
SDK and has no configuration file. **Rationale:** `dart format` is opinionated by design. Arguing
with it produces churn and no benefit.

**R-41-087** The CI check MUST be exactly:

```sh
dart format --output=none --set-exit-if-changed .
```

**Rationale:** `--set-exit-if-changed` is the only flag that makes an unformatted file fail a build.
`--output=none` suppresses the rewritten source, which CI does not need.

**R-41-088** The page width MUST stay at the `dart format` default of 80 columns. It MUST NOT be
overridden in `analysis_options.yaml`. **Rationale:** the default is what every Dart tool, example,
and training corpus assumes.

### 4.2 Analyser

**R-41-089** Every `.dart` file MUST pass `dart analyze` with zero findings of any severity.
**Rationale:** the analyser is the compiler's front end. A warning it reports is a defect the type
system already found.

**R-41-090** The CI check MUST be exactly:

```sh
dart analyze --fatal-infos --fatal-warnings
```

**Rationale:** without both flags an `info` and a `warning` exit 0, so CI passes with findings.

**R-41-091** The app MUST depend on `flutter_lints` 6.0.0. Package:
<https://pub.dev/packages/flutter_lints>. Licence BSD-3-Clause. It requires Dart SDK `^3.8.0` and
pulls `lints` `^6.0.0`. It MUST be declared under `dev_dependencies` with the exact version:

```yaml
dev_dependencies:
  flutter_lints: 6.0.0
```

**Rationale:** `include: package:flutter_lints/flutter.yaml` resolves from the package, so the
package must be present. The exact pin satisfies R-41-043.

**R-41-092** The file `app/analysis_options.yaml` MUST have exactly this content:

```yaml
# Dart static analysis for herdr-mobile.
# Enforced by: dart analyze --fatal-infos --fatal-warnings
#
# The Flutter recommended set is the base. Everything below either escalates a
# finding to an error or adds a rule the base set omits.
include: package:flutter_lints/flutter.yaml

analyzer:
  # All three strict flags. Dart's type system only pays off when implicit
  # dynamic cannot leak in.
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true

  errors:
    # A swallowed or dropped async error is the defect R-41-024 forbids.
    # The analyser can prove these, so they are errors, not warnings.
    unawaited_futures: error
    discarded_futures: error
    body_might_complete_normally_catch_error: error

    # Correctness findings that the analyser proves.
    invalid_null_aware_operator: error
    dead_code: error
    unnecessary_null_comparison: error
    unreachable_switch_case: error

    # Hygiene. An unused import or variable is a leftover from an edit.
    unused_import: error
    unused_local_variable: error
    unused_field: error
    unused_element: error

    # A deprecated API is removed in a later Flutter release. Fix it now.
    deprecated_member_use: error
    deprecated_member_use_from_same_package: error

    # TODO without an owner rots. Use a ponytail: comment (R-41-023) instead.
    todo: ignore

  exclude:
    - '**/*.g.dart'
    - '**/*.freezed.dart'
    - '**/generated_plugin_registrant.dart'

linter:
  rules:
    # --- Error handling (R-41-024 .. R-41-028) ---
    - only_throw_errors
    - avoid_catches_without_on_clauses
    - avoid_catching_errors
    - use_rethrow_when_possible

    # --- Async correctness (R-41-097 .. R-41-099) ---
    - avoid_slow_async_io
    - cancel_subscriptions
    - close_sinks
    - unawaited_futures
    - discarded_futures
    - use_build_context_synchronously

    # --- Logging discipline (R-41-030, R-41-031) ---
    # print() writes terminal content to the platform log with no redaction.
    - avoid_print

    # --- Immutability. A const widget subtree is not rebuilt. ---
    - prefer_const_constructors
    - prefer_const_constructors_in_immutables
    - prefer_const_declarations
    - prefer_const_literals_to_create_immutables
    - prefer_final_locals
    - prefer_final_in_for_each

    # --- Type discipline ---
    - always_declare_return_types
    - avoid_dynamic_calls
    - avoid_positional_boolean_parameters
    - avoid_type_to_string

    # --- Widget conventions ---
    - use_key_in_widget_constructors
    - use_super_parameters
    - sized_box_for_whitespace

    # --- Structure ---
    - avoid_relative_lib_imports
    - directives_ordering
    - prefer_relative_imports
    - unnecessary_late
    - use_enums
```

**Rationale:** every escalation to `error` is a finding the analyser can prove, so it never produces
a false positive that an implementer must suppress. `avoid_print` is a logging control, not a style
preference: `print` sends its argument to the platform log, which R-41-030 forbids for terminal
content.

### 4.3 Naming

**R-41-093** A `.dart` file name MUST use `snake_case`. **Rationale:** the Dart style guide mandates
it, and `dart analyze` reports `file_names` otherwise. This is the stated exception to R-41-001.

**R-41-094** A private symbol MUST start with one underscore. **Rationale:** the underscore is
Dart's only privacy mechanism, and it is library-scoped, not class-scoped.

**R-41-095** A widget class MUST end in a noun that names what it renders, not `Widget`.
`TerminalPane` is correct. `TerminalPaneWidget` is not. **Rationale:** every class in the tree is a
widget, so the suffix carries no information.

### 4.4 File layout

**R-41-096** A `.dart` file MUST order its contents:

1. A file-level doc comment that states the file's purpose.
2. Imports in three groups, each separated by one blank line and each sorted alphabetically:
   `dart:`, then `package:`, then relative.
3. Exports.
4. Top-level constants.
5. Enums and sealed class hierarchies.
6. Public classes.
7. Private classes.
8. Top-level functions.
9. Extensions.

**Rationale:** the `directives_ordering` lint enforces items 2 and 3 mechanically. The rest puts the
public surface above the private one, so a reader stops as soon as the question is answered.

### 4.5 Async and concurrency

**R-41-097** Every `Future` MUST be awaited, returned, or passed to `unawaited()` from
`package:meta`. **Rationale:** an unawaited `Future` that completes with an error drops that error,
which violates R-41-024. `unawaited_futures` and `discarded_futures` prove this at analysis time.

**R-41-098** Work that takes more than 8 ms MUST run off the root isolate through `Isolate.run`.
**Rationale:** the root isolate paints the UI. A frame budget at 120 Hz is 8.3 ms, so any longer
task drops a frame. Measured costs from `docs/21-terminal-rendering.md` §7.1: an 8 KB ANSI parse is
under 5 ms and stays inline; a Noise handshake, a `deflate` of a large scrollback, and a keychain
round trip do not.

**R-41-099** An ANSI feed into the `xterm2` `Terminal` MUST run on the root isolate.
**Rationale:** `Terminal` owns Flutter-side state and is not sendable across an isolate boundary.
R-41-098's threshold permits it, because the measured parse is under 5 ms.

**R-41-100** Every `StreamSubscription`, `Timer`, `AnimationController`, and `TerminalController`
MUST be released in `dispose()`. **Rationale:** a live subscription after unmount writes to disposed
state and throws. `cancel_subscriptions` and `close_sinks` catch the stream cases; a `Timer` is
manual and checklist item C-26 catches it in review.

**R-41-101** A `BuildContext` MUST NOT be used after an `await` without a `mounted` test.
**Rationale:** the widget can unmount during the await. `use_build_context_synchronously` proves it.

**R-41-102** A pane event stream MUST be filtered, revision-gated, and coalesced before it triggers
a read. The coalescing window MUST be 120 ms. **Rationale:**
`docs/21-terminal-rendering.md` owns the 120 ms coalescing window per R-21-021. The measured Herdr
server tick is near 100 ms (`docs/02-herdr-probe-results.md` R-02-010). A shorter window costs read
cycles and gains no frames. See R-41-168 for the filter and R-41-172 for the revision gate.

### 4.6 Error handling

**R-41-103** A fallible operation that crosses a layer boundary MUST return a sealed result type, not
throw. The canonical type:

```dart
/// The outcome of an operation that can fail for a known reason.
sealed class Result<T> {
  const Result();
}

/// The operation succeeded and produced [value].
final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

/// The operation failed. [message] names the operation and the entity
/// (R-41-028). [cause] keeps the root error (R-41-027).
final class Err<T> extends Result<T> {
  const Err(this.message, {this.cause});
  final String message;
  final Object? cause;
}
```

**Rationale:** a sealed hierarchy makes the compiler reject a `switch` that forgets the error branch.
A thrown exception across an `await` has no such check.

**R-41-104** A `catch` clause MUST name the exception type with `on`. A bare `catch` is forbidden.
**Rationale:** a bare `catch` also catches `Error`, which signals a programming defect that must
crash, not be handled. `avoid_catches_without_on_clauses` and `avoid_catching_errors` prove this.

**R-41-105** A thrown object MUST implement `Exception`. Throwing a `String` or an `int` is
forbidden. **Rationale:** `only_throw_errors` proves it, and a caller cannot write a typed `on`
clause for a `String`.

### 4.7 Dependencies

**R-41-106** The app MUST NOT add a package for a capability the Flutter SDK provides.
`Navigator`, `AnimationController`, `TextField`, `MethodChannel`, `http` via `dart:io`, and
`StreamController` are all in the SDK. **Rationale:** R-41-042 rung 2. An SDK capability has no
version drift and no CVE surface of its own.

**R-41-107** The app MUST NOT implement an ANSI or VT parser. It MUST use `xterm2` 5.2.0.
**Rationale:** `docs/21-terminal-rendering.md` R-21-005 selected it. A correct VT parser is a large
state machine, and a wrong one breaks 1-to-1 fidelity, which is the product's core claim.

**R-41-108** The app MUST NOT implement a QR encoder. The Host generates and renders the QR code per
`docs/13-security-pairing.md`. The app needs a camera scanner only. **Rationale:** R-41-042 rung 1.
The capability already exists on the Host side, so the app needs only a decoder, not an encoder.

### 4.8 Notifications

**R-41-109** The app MUST create local native notifications only while its process is alive. The
one push registration it MAY perform is the content-free wake of `docs/03-product-decisions.md`
R-03-136 (amended 2026-09-16): an APNs or FCM token sent to the relay, and a fixed-text push that
carries no agent, pane, tab or workspace. No other push service, and no payload handling in the
app. **Rationale:** R-03-060 limits the alert content to local notifications. The wake exists
because the phone is suspended within seconds of leaving the app; it promises nothing about
delivery.

**R-41-110** A notification tap MUST route to `/hosts/:hostId/panes/:paneId` using `go_router`. The
degenerate cases are owned by `docs/30-ux-spec.md` R-30-511. **Rationale:** the
`agent_status` payload carries the routing fields, defined by `docs/11-relay-protocol.md`.

### 4.9 Design tokens

**R-41-111** A widget MUST NOT hard-code a colour, a font family, a font size, a spacing value, a
corner radius, a motion duration, or an easing curve. Each MUST reference the named token that
`docs/30-ux-spec.md` defines and cite its `R-30-nnn` rule. **Rationale:** `docs/30-ux-spec.md` owns
every visual value, and it derives them from published sources: the Selenized dark and light
palettes, JetBrainsMono Nerd Font Mono 2.304 patched by Nerd Fonts v3.5.1 (R-21-011, R-21-012),
IBM Plex Sans 1.1.0, a 4-unit spacing scale, a 48 by 48 logical pixel minimum touch target, and the
three durations 120 ms, 200 ms
and 320 ms. A literal `Color(0xFF...)` or `fontSize: 15` in a widget is a value somebody invented,
which is exactly what this repository forbids.

**R-41-112** A text label MUST NOT take its colour from a status hue. A status MUST use the named
treatment `treat.ok`, `treat.warning`, `treat.error`, or `treat.destructive`, which places the hue in
an icon and a bar and keeps the label on `color.fg.primary`. **Rationale:** `docs/30-ux-spec.md`
measured the contrast: Selenized dark red reaches 3.71 to 1 and light green 3.56 to 1, both below the
4.5 to 1 that body text requires. Colouring an error label red is the intuitive change and it fails
accessibility, so the rule has to be explicit.

## §5 Rust

Applies to every `.rs` file in the workspace `crates/herdr-relay-proto/`, `crates/herdr-relay/` and
`crates/herdr-relay-hub/`. Edition 2024. The workspace layout and the crate dependency pins are in
`docs/12-relay-hosting.md` §2.

`herdr-relay-proto` is the only crate that defines a wire type, a close-code enum, an error code, a
routing-handle codec or a pairing-phrase codec. Every other crate imports `herdr-relay-proto`; it
MUST NOT define a duplicate of any of those types.

### 5.1 Formatter

**R-41-113** Every `.rs` file MUST be formatted by `rustfmt`, which ships in the Rust toolchain. The
edition is 2024. **Rationale:** R-41-042 rung 3. `rustfmt` is the standard formatter and has no
configuration file worth diverging from.

**R-41-114** The CI check MUST be exactly:

```sh
cargo fmt --check
```

**Rationale:** `--check` fails the build when a file is unformatted, without changing it.

### 5.2 Linter

**R-41-115** Every `.rs` file MUST pass `cargo clippy` with zero warnings at the project's strictest
gate. Native Host-plugin and shared-protocol work MUST use:

```sh
cargo clippy -p herdr-relay -p herdr-relay-proto --all-targets --all-features -- -D warnings
```

The `test` stage in `crates/herdr-relay-hub/Dockerfile` MUST use:

```sh
cargo clippy -p herdr-relay-hub --all-targets --all-features -- -D warnings
```

The developer MUST invoke that relay gate only through `docker build --target test`, per
`docs/12-relay-hosting.md` R-12-012. **Rationale:** `--all-targets` covers tests, benches and
examples. `--all-features` enables conditional code. `-D warnings` fails the build for one warning.

**R-41-116** A `#[allow(clippy::lint_name)]` directive MUST carry a reason on the same line:
`#[allow(clippy::too_many_lines)] // table-driven test, all cases must stay together for review`.
**Rationale:** a bare `allow` silences a future defect of the same type.

### 5.3 Naming

**R-41-117** A type, a struct, an enum and a trait MUST use `PascalCase`.
**Rationale:** Rust's convention, enforced by `clippy::upper_case_acronyms`.

**R-41-118** A function, a method, a variable and a module MUST use `snake_case`.
**Rationale:** Rust's convention, enforced by `clippy::nonstandard_style`.

**R-41-119** A constant and a static MUST use `UPPER_SNAKE_CASE`.
**Rationale:** Rust's convention. `SCREAMING_SNAKE_CASE` is the clippy lint name.

**R-41-120** A crate name MUST use `kebab-case`. **Rationale:** Cargo maps `kebab-case` crate names
to `snake_case` imports, so the two conventions are consistent.

**R-41-121** A constructor MUST be named `new` when it takes no fallible inputs. It MUST be named
`try_new` when it can fail and returns `Result<Self, E>`. **Rationale:** the standard library
convention. A caller knows whether to expect an error from the name.

### 5.4 File layout and module rules

**R-41-122** A crate MUST have one responsibility. A crate named `herdr-relay-proto` holds the wire
protocol and nothing else, and a crate named `herdr-relay-hub` holds the relay service and nothing
else. **Rationale:** a crate with one responsibility has one reason to change.

**R-41-123** A module MUST NOT be named `util`, `common`, `helpers`, `misc`, or `base`.
**Rationale:** such a module has no responsibility, so nothing can be excluded from it and it grows
without bound.

**R-41-124** A `.rs` file MUST order its contents:

1. A module-level doc-comment.
2. `use` statements in three groups separated by a blank line: `std`, external crates, then
   `crate` and `super`.
3. Constants.
4. Types: structs, enums, type aliases, in order from public to private.
5. Traits and their implementations, grouped under the type that implements them.
6. Free functions, public before private.

**Rationale:** `rustfmt` orders `use` statements mechanically when configured. The rest puts the
public surface above the private one, so a reader stops as soon as the question is answered.

### 5.5 Error handling

**R-41-125** An error that crosses a crate boundary MUST be a typed error derived with `thiserror`
2.0.20. Every variant MUST carry a `#[error("...")]` attribute that names the operation and the
entity per R-41-028. A variant that wraps another error MUST carry `#[source]`.
**Rationale:** `thiserror` produces `Display`, `Error` and `source` with no boilerplate.
`#[source]` satisfies R-41-027.

**R-41-126** `unwrap` and `expect` MUST NOT appear outside `#[cfg(test)]`. Use `?`, `match`, or
`if let` in production code. **Rationale:** `unwrap` on a `Result` converts a recoverable error into
a process crash. The compiler offers `?` for the common case.

**R-41-127** A `Result<T, E>` MUST NOT be discarded. Use `let _ = ...` with a comment that states
why the error is irrelevant, or handle the `Err` arm. **Rationale:** a discarded `Result` is
R-41-024's violation. `clippy::let_underscore_must_use` catches some cases; the code review catches
the rest.

### 5.6 Async and concurrency

**R-41-128** Every `tokio::spawn` MUST have a named owner that stores the `JoinHandle` and either
awaits it or aborts it on shutdown. A bare `tokio::spawn(task)` whose completion nobody observes is
forbidden. **Rationale:** an unobserved task that panics kills the runtime, and one that blocks
forever is a leak.

**R-41-129** Every `tokio::select!` arm MUST be cancel-safe or carry a comment that explains how the
state is protected when the arm is dropped mid-operation. **Rationale:** `select!` drops every
pending future when one branch completes. An `async fn` that writes to a buffer and is dropped before
`await` leaves the buffer half-written. Cancel-safety is a runtime property, not a compile-time
check, so every arm needs a documented decision.

**R-41-130** A channel MUST be bounded, and the bound MUST be stated in a comment at the declaration
together with the overflow policy. Example:
`// ponytail: mpsc::channel(8) — a burst of 8 frames is fine; any more and the sender blocks, which
is an explicit backpressure signal`. **Rationale:** an unbounded channel consumes unlimited memory
under load.

**R-41-131** A file read, a WebSocket read, and a connection attempt MUST carry a timeout. Use
`tokio::time::timeout`. **Rationale:** a socket with no timeout blocks the task forever when the
peer stalls. The relay serves up to 500 concurrent pairs per `docs/12-relay-hosting.md` R-12-007,
so one stuck task leaks one pair.

### 5.7 Dependencies

**R-41-132** A crate MUST NOT add a dependency for a capability the standard library provides.
`std::sync::Mutex`, `std::collections::HashMap`, `std::net` and `std::time` are all in the standard
library. **Rationale:** R-41-042 rung 3.

**R-41-133** `herdr-relay-hub` MUST NOT depend on `snow`, `blake2`, or `rand`. It holds no Noise
keys and performs no application-layer cryptography. **Rationale:** the relay performs no
application-layer payload decryption per `docs/12-relay-hosting.md`. A crypto dependency in the
relay is evidence against that claim. The relay still links the platform TLS stack through `axum`,
because it terminates TLS in a single-host deployment and connects outward in its test harness.

**R-41-134** A crate MUST NOT add a database, a cache, or a Redis client. Session state lives in
memory. **Rationale:** `docs/12-relay-hosting.md` accepts session loss on restart for v1, and
R-12-003 forbids persisting frames. Storage the design does not need is storage a reviewer must audit.

**R-41-135** The workspace MUST use the exact crate version pins recorded in
`docs/12-relay-hosting.md` §2.1. Every pin is a three-part `major.minor.patch` version verified
against `crates.io` during this remediation. **Rationale:** every pin satisfies R-41-043.
A pin not in that table is a pin somebody invented, which is exactly what this repository forbids.

## §6 Cross-platform plugin scripts

Applies to the future `crates/herdr-relay/posix/*.sh` and `crates/herdr-relay/windows/*.ps1`
launcher and service shims. Every rule here comes from the two reference plugins.

### 6.1 Locating the plugin root

**R-41-136** A script MUST locate the plugin root through `HERDR_PLUGIN_ROOT`. It MUST NOT use a
relative path, `dirname "$0"`, or `$PSScriptRoot` for this purpose.

**Rationale:** two independent reasons, both recorded upstream.
`herdr-default-layout/herdr-plugin.toml` lines 14–18 state them: Herdr resolves a relative program
against its own install directory on Windows (`herdr-file-viewer` GH #58), and the working directory
of an action command is not guaranteed. `herdr-scheduled/herdr-plugin.toml` lines 7–11 repeat the
same finding.

**R-41-137** The POSIX form MUST be exactly:

```sh
: "${HERDR_PLUGIN_ROOT:?herdr-relay: HERDR_PLUGIN_ROOT not set}"
```

**Rationale:** `:?` writes the message to stderr and exits 1 when the variable is unset or empty.
`herdr-scheduled/herdr-plugin.toml` line 28 uses this exact construct:
`r=${HERDR_PLUGIN_ROOT:?herdr-scheduled: HERDR_PLUGIN_ROOT not set}`.

**R-41-138** The Windows form MUST be exactly:

```powershell
$r = $env:HERDR_PLUGIN_ROOT
if (-not $r) {
    $b = $env:HERDR_BIN_PATH
    if (-not $b) { $b = 'herdr' }
    $r = ((& $b plugin list --json | ConvertFrom-Json).result.plugins |
        Where-Object { $_.plugin_id -eq 'herdr-relay' }).plugin_root
}
if ($r -and $r.StartsWith('\\?\')) { $r = $r.Substring(4) }
$PluginRoot = $r
```

**Rationale:** this is the pattern in `herdr-scheduled/herdr-plugin.toml` lines 34–35 and
`herdr-default-layout/herdr-plugin.toml` lines 35–36, with the plugin id changed. It handles the
three real cases: Herdr injected the variable; the variable is absent because the OS scheduler
invoked the script with no Herdr environment; and the value carries the verbatim prefix.

**R-41-139** A shim MUST NOT hold the relay connection. The Rust binary owns the long-lived bridge.
The shim launches the binary and forwards the exit code. **Rationale:**
`herdr-scheduled/herdr-plugin.toml` lines 2–4 record that `[[startup]]` hooks are one-shot and that
Herdr exposes no timer event, which is why that plugin delegates to cron and Task Scheduler.
A bridge started inside a hook dies when the hook returns. The Rust binary is the bridge; the shim
must not become it.

### 6.2 The Windows verbatim prefix

**R-41-140** Every path that arrives from Herdr on Windows MUST pass through a verbatim-prefix strip
before use. The exact function, from `herdr-default-layout/scripts/lib.ps1` lines 5–8:

```powershell
function Remove-VerbatimPrefix([string]$path) {
    if ($path -and $path.StartsWith('\\?\')) { return $path.Substring(4) }
    return $path
}
```

**Rationale:** Herdr reports a plugin root and a config directory with a `\\?\` prefix. The prefix is
a valid Win32 path form but `Join-Path` and several .NET APIs mishandle it.
`herdr-default-layout/scripts/lib.ps1` applies it at lines 42 and 50, to `plugin_root` and to the
output of `plugin config-dir`.

**R-41-141** The strip MUST be applied to `HERDR_PLUGIN_ROOT`, to `plugin_root` from
`plugin list --json`, and to the output of `plugin config-dir`. **Rationale:** these are the three
sources the reference plugins observed carrying the prefix.

### 6.3 Twin implementations

**R-41-142** Every behaviour MUST have a POSIX implementation and a PowerShell implementation.
**Rationale:** the manifest declares `platforms = ["linux", "macos", "windows"]`. A behaviour present
on one platform only makes the plugin broken, not partial.

**R-41-143** A change to one twin MUST be accompanied by the equivalent change to the other twin in
the same commit. The commit message MUST name both files. **Rationale:** divergence between twins
surfaces only when a user changes operating system, which is the slowest possible feedback loop.

**R-41-144** The two twins MUST produce byte-identical output for machine-readable data, and
semantically identical output for text a person reads. **Rationale:** the reference plugins state
this requirement where it bites. `herdr-scheduled/windows/common.ps1` lines 174–181 describe
`ConvertTo-Field` and end with "The POSIX twin applies the identical rule", and
`herdr-scheduled/posix/common.sh` lines 72–83 hold that twin. A state file written by one twin is
read by the other after the user switches machines.

**R-41-145** A change to a twin MUST be verified by running the twin's test on its own platform.
**Rationale:** a twin verified only by reading is not verified.

**R-41-146** When a behaviour cannot be tested on the other platform in CI, the pull request MUST
state which twin was executed and which was only reviewed. **Rationale:** an honest gap is
manageable; a silent one is not.

**R-41-147** A shared data format MUST be documented once, in a comment on the POSIX twin, and the
PowerShell twin MUST reference that comment. **Rationale:** two independent descriptions of one
format drift. `herdr-scheduled` uses one canonical description of its tab-separated index format.

### 6.4 Exit codes

**R-41-148** Exit code `0` MUST mean success.

**R-41-149** Exit code `1` MUST mean a known, actionable failure: a missing environment variable,
invalid input, or an unmet precondition. **Rationale:** `1` is what `:?` produces (R-41-137) and what
a PowerShell `throw` produces, so it is already the value both platforms emit for this class.

**R-41-150** Exit code `2` MUST mean an unexpected failure: Herdr unreachable, a network error, or a
defect. **Rationale:** separating `1` from `2` lets a caller distinguish "the user must fix
something" from "retry or report a bug".

**R-41-151** A script MUST NOT exit with a code above `2`. **Rationale:** more codes need a table
nobody maintains, and the popup pane shows a message anyway.

**R-41-152** A failure MUST write a one-line reason to stderr before exiting non-zero.
**Rationale:** an exit code alone tells the user nothing, and the popup pane shows stderr.

## §7 Herdr socket client

Applies to any code that opens the Herdr socket. Every rule restates a measured finding from
`docs/02-herdr-probe-results.md`. That document is ground truth; these rules are its coding form.

**R-41-153** The client MUST read the socket path from `herdr status`. On Windows it MUST prefix the
path with `\\.\pipe\`. On Linux and macOS it MUST use the path as an `AF_UNIX` address.
**Rationale:** R-02-001. The reported `.sock` file is a 25-byte text file holding
`<pid>:<starttime_ns>`, not a socket.

**R-41-154** The client MUST NOT parse the `.sock` file as a socket address. It MAY read it to learn
the server process ID. **Rationale:** R-02-002.

**R-41-155** The bridge MUST NOT be written in Python if it runs on Windows. **Rationale:** R-02-003.
CPython on Windows has no `socket.AF_UNIX`.

**R-41-156** The client MUST open a new connection for every request. **Rationale:** R-02-004. The
server reads exactly one request line, sends one response, then half-closes.

**R-41-157** The client MUST NOT pipeline requests on one connection. **Rationale:** R-02-004. A
second request in the same write is discarded silently, which is worse than an error.

**R-41-158** The client MUST NOT reuse a connection after it has received a response.
**Rationale:** R-02-004. A later write returns `EPIPE`.

**R-41-159** The client MUST treat `EPIPE` on a spent connection as the normal end of that
connection, and MUST NOT log it as an error. **Rationale:** R-02-005. Logging it produces one false
error per request.

**R-41-160** The bridge MUST hold one long-lived connection per subscription set.
**Rationale:** R-02-006. After `events.subscribe` answers `subscription_started`, the connection
streams events for as long as it stays open.

**R-41-161** The bridge MUST NOT send a request on a subscription connection. **Rationale:** R-02-006.
A `ping` and a `pane.read` on that connection both received no answer, while events kept arriving.
The request is lost with no error.

**R-41-162** Every request MUST include `params`, even when it is empty as `{}`.
**Rationale:** R-02-007. Omitting it returns
`invalid_request: missing field 'params' at line 1 column 27`.

**R-41-163** The client MUST read a result through its wrapped payload key, such as `result.read` for
`pane.read` and `result.snapshot` for `session.snapshot`. It MUST NOT read fields directly off
`result`. **Rationale:** R-02-007. `result.type` is the discriminator and the payload sits under a
second key that varies by method.

**R-41-164** The client MUST call `ping` first and MUST compare `result.protocol` against `21`.
**Rationale:** R-02-008. This build targets protocol 21, and a mismatch must fail at startup rather
than at the first unrecognised field.

**R-41-165** The bridge MUST validate a request against the schema before forwarding it.
**Rationale:** R-02-009. A malformed request costs the connection and returns an error with an
**empty** `id`, so it cannot be correlated with the request that caused it.

**R-41-166** An enum value MUST be lowercase with underscores. **Rationale:** R-02-009. `Visible`
fails and `visible` succeeds.

**R-41-167** The bridge MUST decide whether to read from `data.pane.revision` on the event. It MUST
NOT call `pane.read` to discover whether anything changed. **Rationale:** R-02-011 and R-02-012. The
`pane_updated` event carries the whole pane object, and two reads with an unchanged revision produced
byte-identical text.

**R-41-168** The bridge MUST filter events to the panes a Device is actually viewing.
**Rationale:** R-02-013. The subscription accepts only `{"type":"pane.updated"}` with no `pane_id`
field, so there is no server-side filter. Measured on an idle machine: 98 events in 10 seconds, all
from background `herdr-sidebar` Explorer panes, while all seven real agent panes stayed silent.

**R-41-169** A read that must be faithful MUST pass `format: "ansi"` and `strip_ansi: false`.
**Rationale:** R-02-014. `strip_ansi` defaults to `true` and silently discards all styling,
including the 24-bit truecolour that the probe confirmed is real.

**R-41-170** The Host-to-Device transport MUST enable WebSocket `permessage-deflate`.
**Rationale:** R-02-016. A measured 8 KB ANSI frame compresses to 1.1 to 1.9 KB, which removes any
need for a cell-level diff in v1.

**R-41-171** The Device MUST derive the column count from the `pane_frame` relay message, per
`docs/11-relay-protocol.md` R-11-051, and MUST NOT derive columns from the content. The bridge
calls `pane.layout` and reads `rect.width`. **Rationale:** R-02-017 was corrected after the initial
probe. `pane.layout` returns a `PaneLayoutRect` measured in character cells, proven because
`rect.width` increases when a pane is resized wider. R-10-024, R-20-013, R-21-009 and R-30-160 all
state this.

**R-41-172** A revision from an event MUST be compared only against another revision from an event.
**Rationale:** R-02-012 records that the `revision` inside a `pane.read` result did not match the
`revision` for the same pane in `session.snapshot`. They may be separate counters.

## §8 Review checklist

An agent MUST run this checklist against its own diff before it yields. Every item is verifiable by
reading the diff alone.

- [ ] **C-01** No `catch` block is empty, and none discards the error without logging, wrapping, or
  changing behaviour. (R-41-024, R-41-025)
- [ ] **C-02** No log call, `print`, `echo`, `Write-Host`, or `tracing` event receives terminal
  content, a pane read result, or an ANSI payload. (R-41-030)
- [ ] **C-03** No log call receives a pairing phrase, a key, a token, or a password. (R-41-031)
- [ ] **C-04** Every error that crosses a crate or module boundary is wrapped and names the
  operation and the entity. (R-41-026, R-41-028)
- [ ] **C-05** No new file exceeds 400 lines. (R-41-010)
- [ ] **C-06** No new function exceeds 60 lines, takes more than 5 parameters, or nests deeper than
  4 levels. (R-41-012, R-41-014, R-41-016)
- [ ] **C-07** Every new exported symbol has a doc-comment. (R-41-022)
- [ ] **C-08** No comment restates the code, and no commented-out code block is added. (R-41-019,
  R-41-021)
- [ ] **C-09** Every new dependency has a one-sentence justification in the commit message naming the
  rejected alternative. (R-41-041)
- [ ] **C-10** Every new dependency version is an exact triple, with no caret, tilde, or `latest`.
  (R-41-043)
- [ ] **C-11** No added code reimplements a capability that the platform, the standard library, or an
  existing dependency provides. (R-41-042)
- [ ] **C-12** Every path is built with a join function, and no hard-coded `/tmp`, `/var/run`,
  `C:\Windows`, or `%APPDATA%` literal is added. (R-41-050, R-41-051)
- [ ] **C-13** Every new `.sh` file starts with `#!/bin/sh` and `set -eu`. (R-41-056)
- [ ] **C-14** Every new `.ps1` file starts with `Set-StrictMode -Version Latest` and
  `$ErrorActionPreference = 'Stop'`. (R-41-075)
- [ ] **C-15** Every variable expansion in changed shell lines is double-quoted, or carries a comment
  that says the splitting is intended. (R-41-062, R-41-063)
- [ ] **C-16** No shim locates its root through a relative path, `dirname "$0"`, or
  `$PSScriptRoot`. (R-41-136)
- [ ] **C-17** Every Windows path from Herdr passes through `Remove-VerbatimPrefix`. (R-41-140)
- [ ] **C-18** A change to a `posix/*.sh` file has the matching change to the `windows/*.ps1` twin in
  the same diff, and the commit message names both. (R-41-143)
- [ ] **C-19** Every new script exit is `0`, `1`, or `2`, and a non-zero exit writes a reason to
  stderr. (R-41-149, R-41-150, R-41-152)
- [ ] **C-20** Every Herdr request includes `params`, even as `{}`. (R-41-162)
- [ ] **C-21** Every Herdr result is read through its wrapped key, such as `result.read`, not off
  `result` directly. (R-41-163)
- [ ] **C-22** No Herdr connection is used for a second request, and no request is sent on a
  subscription connection. (R-41-156, R-41-158, R-41-161)
- [ ] **C-23** Every `pane.read` that must be faithful passes `format: "ansi"` and
  `strip_ansi: false`. (R-41-169)
- [ ] **C-24** Every read is gated on a moved `revision`, and the event stream is filtered to the
  watched pane. (R-41-167, R-41-168)
- [ ] **C-25** Every `Future` is awaited, returned, or wrapped in `unawaited()`. (R-41-097)
- [ ] **C-26** Every new `StreamSubscription`, `Timer`, and controller is released in `dispose()`.
  (R-41-100)
- [ ] **C-27** No work longer than 8 ms is added to the root isolate. (R-41-098)
- [ ] **C-28** Every `tokio::spawn` has an owner that stores the `JoinHandle`. Every `select!` arm
  is cancel-safe or documented. Every channel is bounded. (R-41-128, R-41-129, R-41-130)
- [ ] **C-29** No `unwrap` or `expect` appears outside `#[cfg(test)]`. (R-41-126)
- [ ] **C-30** No file adds trailing whitespace, and every file ends with exactly one newline.
  (R-41-046, R-41-047)
- [ ] **C-31** No widget adds a literal colour, font size, spacing value, radius, duration, or
  easing curve. Each references a named token from `docs/30-ux-spec.md`. (R-41-111)
- [ ] **C-32** No text label takes its colour from a status hue. Every status uses `treat.ok`,
  `treat.warning`, `treat.error`, or `treat.destructive`. (R-41-112)

## §9 Anti-patterns

Each entry shows the smallest wrong form and the right form beside it.

### AP-01 Reinventing a library

The parser is a large state machine. A wrong one breaks the product's 1-to-1 fidelity claim.

```dart
// WRONG: a hand-written SGR parser.
if (chunk.startsWith('\x1b[')) {
  final code = int.parse(chunk.substring(2, chunk.indexOf('m')));
  if (code == 31) currentColor = Colors.red;
}
```

```dart
// RIGHT: xterm2 5.2.0 owns the VT state machine (R-41-107).
terminal.write(chunk);
```

### AP-02 Logging terminal content

The pane holds source code, typed passwords, and echoed tokens.

```rust
// WRONG: the whole frame reaches the log aggregator.
tracing::debug!("forwarding frame", payload = %String::from_utf8_lossy(&frame));
```

```rust
// RIGHT: metadata describes the frame without disclosing it (R-41-030, R-41-032).
tracing::debug!("forwarding frame", bytes = frame.len(), session = %session_id);
```

### AP-03 Logging a pairing phrase

The phrase grants access to a Host.

```rust
// WRONG: the phrase is now searchable in the log store.
tracing::info!("pairing started", phrase = %phrase);
```

```rust
// RIGHT: the event is logged, the secret is not (R-41-031).
tracing::info!("pairing started", session = %session_id);
```

### AP-04 Swallowing an exception

```dart
// WRONG: the send failed and nobody knows.
try {
  await hub.send(frame);
} catch (_) {}
```

```dart
// RIGHT: typed clause, logged, and behaviour changes (R-41-024, R-41-104).
try {
  await hub.send(frame);
} on SocketException catch (e) {
  _log.warning('hub send failed, queueing frame', e);
  _pending.add(frame);
}
```

### AP-05 Relative path in a plugin shim

Herdr resolves a relative program against its own install directory on Windows, and the working
directory of an action is not guaranteed.

```sh
# WRONG: resolves against the working directory, which Herdr does not set.
. ./common.sh
```

```sh
# RIGHT: the injected root is the only reliable anchor (R-41-136, R-41-137).
: "${HERDR_PLUGIN_ROOT:?herdr-relay: HERDR_PLUGIN_ROOT not set}"
. "$HERDR_PLUGIN_ROOT/posix/common.sh"
```

### AP-06 Hard-coded platform path

```rust
// WRONG: /tmp does not exist on Windows.
let lock_dir = Path::new("/tmp/herdr-relay.lock");
```

```rust
// RIGHT: the platform reports its own temp directory (R-41-050, R-41-051).
let lock_dir = std::env::temp_dir().join("herdr-relay.lock");
```

### AP-07 Blocking the UI thread with a parse

The root isolate paints the UI. A 120 Hz frame budget is 8.3 ms.

```dart
// WRONG: a full scrollback parse on the root isolate drops frames.
for (final chunk in scrollbackChunks) {
  terminal.write(chunk);   // 40 chunks x 5 ms = 200 ms frozen
}
```

```dart
// RIGHT: decompress off the root isolate, then feed the viewport only (R-41-098).
final ansi = await Isolate.run(() => inflate(compressed));
terminal.write(ansi);
```

### AP-08 Unbounded read loop with no revision gate

Measured: 98 events in 10 seconds on an idle machine, all from background Explorer panes.

```dart
// WRONG: one read per event, on every pane, with no gate. ~10 reads/s of noise.
events.listen((e) async {
  final r = await client.request('pane.read', {
    'pane_id': e.pane.paneId, 'source': 'visible',
    'format': 'ansi', 'strip_ansi': false,
  });
  device.send(r.read.text);
});
```

```dart
// RIGHT: filter, gate on revision, coalesce (R-41-168, R-41-167, R-41-102).
events
    .where((e) => e.pane.paneId == watchedPaneId)
    .where((e) => e.pane.revision != _lastRevision)
    .debounce(const Duration(milliseconds: 120))
    .listen(_readAndForward);
```

### AP-09 Reusing a Herdr socket connection

The server answers one request per connection, then half-closes. The second request is discarded
with no error.

```dart
// WRONG: the second request is silently dropped; the third write throws EPIPE.
final conn = await HerdrSocket.connect();
final a = await conn.request('pane.read', {...});
final b = await conn.request('pane.read', {...});   // never answered
```

```dart
// RIGHT: one connection per request (R-41-156, R-41-158).
final a = await HerdrSocket.oneShot('pane.read', {...});
final b = await HerdrSocket.oneShot('pane.read', {...});
```

### AP-10 Sending a request on the subscription connection

```dart
// WRONG: the subscription connection never answers a request again.
final sub = await HerdrSocket.connect();
await sub.request('events.subscribe', {'subscriptions': [...]});
final snap = await sub.request('session.snapshot', {});   // never answered
```

```dart
// RIGHT: the subscription stays event-only (R-41-160, R-41-161).
final sub = await HerdrSocket.subscribe([...]);           // long-lived, events only
final snap = await HerdrSocket.oneShot('session.snapshot', {});
```

### AP-11 Omitting `params`

```dart
// WRONG: returns invalid_request with an empty id, then closes the connection.
await client.send({'id': 'a', 'method': 'ping'});
```

```dart
// RIGHT: params is required, even when empty (R-41-162).
await client.send({'id': 'a', 'method': 'ping', 'params': <String, Object?>{}});
```

### AP-12 Reading `result` directly

```dart
// WRONG: the payload is not on result; result.type is a discriminator.
final text = response['result']['text'] as String;
```

```dart
// RIGHT: read through the wrapped payload key (R-41-163).
final text = response['result']['read']['text'] as String;
```

### AP-13 Using `unwrap` in production Rust code

```rust
// WRONG: a failed Noise handshake kills the process instead of reporting an error.
let transport = builder.build_handshake_state(psk).unwrap();
```

```rust
// RIGHT: propagate the error to the caller (R-41-126).
let transport = builder.build_handshake_state(psk)
    .map_err(|e| RelayError::HandshakeFailed(e.to_string()))?;
```

## §10 Validate the documentation

`docs/40-repo-tooling.md` §8 owns the documentation validation commands, rule audit and completion
checklist. Use that section. This document does not duplicate those commands.

## Retired rules

Rules retired during the 2026-08 remediation. Their ids are kept so a reader who finds an old
citation is not lost.

| Retired id | What it said | Replaced by |
|---|---|---|
| `R-41-039` old | Frame maximum 256 KiB. | R-41-039 now cites the single 1 MiB value from `docs/11-relay-protocol.md` R-11-035. |
| `R-41-052` | ShellCheck requirement for POSIX shims. | Retired. ShellCheck is not used. |
| `R-41-053` | ShellCheck command for POSIX shims. | Retired. ShellCheck is not used. |
| `R-41-072` old | POSIX temporary files under `XDG_RUNTIME_DIR`; later reused for the PSScriptAnalyzer requirement. | Retired. The Rust binary owns temporary files, and PSScriptAnalyzer is not used. |
| `R-41-073` old | POSIX directory lock via `mkdir`; later reused for the PSScriptAnalyzer settings path. | Retired. The shim holds no lock, and PSScriptAnalyzer is not used. |
| `R-41-074` old | Lock directory path under `$STATE_DIR`; later reused for the PSScriptAnalyzer command. | Retired. The shim holds no lock, and PSScriptAnalyzer is not used. |
| `R-41-075` old | Lock owner file with `<pid> <hostname>`. | Deleted. Same reason. |
| `R-41-076` old | Lock acquisition timeout 10 seconds. | Deleted. Same reason. |
| `R-41-077` old | Former duplicate of the rule later assigned R-41-072. | Retired with R-41-072. |
| `R-41-078` old | Former duplicate of the rule later assigned R-41-073. | Retired with R-41-073. |
| `R-41-079` old | Former duplicate of the rule later assigned R-41-074. | Retired with R-41-074. |
| `R-41-080` old | Strict-mode preamble (duplicate). | Renumbered; the preamble rule is now R-41-075. |
| `R-41-081` old | Optional property test (duplicate). | Renumbered; the optional-property rule is now R-41-076. |
| `R-41-082` old | Verb-Noun naming (duplicate). | Renumbered; the naming rule is now R-41-077. |
| `R-41-083` old | PascalCase variables (duplicate). | Renumbered; the variable-naming rule is now R-41-078. |
| `R-41-084` old | Powershell.exe path (duplicate). | Renumbered; the path rule is now R-41-079. |
| `R-41-085` old | File layout (duplicate). | Renumbered; the layout rule is now R-41-080. |
| `R-41-086` old | PowerShell `Start-Job` forbidden. | Deleted. The Rust binary owns concurrency; the shim starts one process and exits. |
| `R-41-087` old | Long-lived process started detached. | Deleted. Same reason. |
| `R-41-088` old | Directory-lock scheme. | Deleted. Same reason. |
| `R-41-089` old | `ReadAllLines` before `WriteAllText`. | Deleted. Same reason. |
| `R-41-090` old | Native exit-code check (duplicate). | Renumbered; the exit-code rule is now R-41-081. |
| `R-41-091` old | Stderr to pipe (duplicate). | Renumbered; the stderr rule is now R-41-082. |
| `R-41-092` old | `throw` with message (duplicate). | Renumbered; the throw rule is now R-41-083. |
| `R-41-093` old | Empty catch with reason (duplicate). | Renumbered; the catch rule is now R-41-084. |
| `R-41-094` old | UTF-8 without BOM (duplicate). | Renumbered; the UTF-8 rule is now R-41-085. |
| `R-41-095` old | PowerShell temporary files under `$env:TEMP`. | Deleted. Same reason as POSIX temp files. |
| `R-41-096` old | PowerShell lock directory path. | Deleted. Same reason. |
| `R-41-097` old | `dart format` rule (duplicate). | Renumbered; the formatter rule is now R-41-086. |
| `R-41-098` old | `dart format` CI check (duplicate). | Renumbered; the CI rule is now R-41-087. |
| `R-41-099` old | Page width 80 (duplicate). | Renumbered; the width rule is now R-41-088. |
| `R-41-100` old | `dart analyze` zero findings (duplicate). | Renumbered; the analyser rule is now R-41-089. |
| `R-41-101` old | `dart analyze` CI check (duplicate). | Renumbered; the CI rule is now R-41-090. |
| `R-41-102` old | `flutter_lints` 6.0.0 (duplicate). | Renumbered; the lints rule is now R-41-091. |
| `R-41-103` old | `analysis_options.yaml` content (duplicate). | Renumbered; the config rule is now R-41-092. |
| `R-41-119` old | Hub renders QR code, app must not implement encoder. | Replaced by R-41-108. The Host now generates and renders the QR code per `docs/13-security-pairing.md`. |
| `R-41-120` through `R-41-151` | All Go rules: `gofmt`, `golangci-lint`, Go naming, Go file layout, Go concurrency, Go error handling and Go dependencies. | Deleted. Go is removed from this product. The relay is Rust. |
| `R-41-187` | Device MUST derive column count from content. | Retired. The Device derives the column count from `pane.layout` `rect.width`, per R-41-171. Nothing carries this number now. |
| `R-41-189` | Hard-coded design token rule (duplicate). | Retired as a duplicate. The design token rule is R-41-111. Nothing carries this number now. |
| `R-41-190` | Status colour on text (duplicate). | Retired as a duplicate. The contrast rule is R-41-112. Nothing carries this number now. |

## Implementation TODO

These items belong to the implementation phase. `docs/90-implementation-plan.md` is the
authoritative, currently-ticked checklist; some of these — `app/analysis_options.yaml`, the
workspace `Cargo.toml` — are already done as of Phase 0.

- [ ] Add `flutter_lints: 6.0.0` to `app/pubspec.yaml` under `dev_dependencies` per R-41-091.
- [ ] Create `app/analysis_options.yaml` with the content in R-41-092.
- [ ] Create the POSIX and PowerShell launcher shims in `crates/herdr-relay/posix/` and
  `crates/herdr-relay/windows/`, at most five lines each per R-41-139.
- [ ] Add the Rust workspace `Cargo.toml` at `crates/Cargo.toml` with the exact crate pins in
  `docs/12-relay-hosting.md` §2.1 and the `[workspace]` members `herdr-relay-proto`, `herdr-relay`
  and `herdr-relay-hub`.
- [ ] Confirm `cargo fmt --check` and the native Host-plugin and shared-protocol command in R-41-115
  pass on the first workspace commit.
- [ ] Confirm the relay `test` image passes the formatter, linter and test gates in Docker
  (R-12-012, R-41-114, R-41-115).
- [ ] Add CI jobs that run the native Host and Dart gates, and the Docker-only relay gates. The
  exact CI configuration belongs to the implementation phase.
- [ ] Confirm `dart analyze --fatal-infos --fatal-warnings` is clean on the generated Flutter
  template before the first feature commit, and add any generated path to the
  `exclude` list in `app/analysis_options.yaml`.
- [ ] Add `unawaited_futures: error` to `app/analysis_options.yaml` (R-41-092).

## Sources

Reference plugin sources, read directly:

- `C:/Development/Repositories/other/herdr-scheduled/posix/common.sh` — `set -eu` preamble (line 4);
  `CFG_DIR` and `STATE_DIR` derivation (lines 10–25); `HERDR_BIN` resolution (lines 27–48);
  `valid_id` allow-list (line 54); `field_clean` twin rule (lines 72–83); banner comment structure
  (lines 6, 27, 52, 93, 126); the measured `pane resize` convergence and the reason `pane swap` was
  rejected (lines 739–757); `ponytail:` marker usage (lines 462–464, 537–539)
- `C:/Development/Repositories/other/herdr-scheduled/windows/common.ps1` — `Set-StrictMode` and
  `$ErrorActionPreference` preamble (lines 1–2); `$HerdrBin` resolution (lines 8–17); the fixed
  `powershell.exe` path (line 20); `$PluginRoot` (line 23); `$CfgDir` and `$StateDir` (lines 27–45);
  UTF-8 without BOM (line 35); `ConvertTo-Field` and its "POSIX twin applies the identical rule"
  note (lines 174–186); `ConvertTo-QuotedArg` (lines 258–264); stderr to a pipe to avoid
  `NativeCommandError` (lines 267–268); native exit-code check (lines 306–310);
  `ReadAllLines` versus a streaming reader (lines 333–336)
- `C:/Development/Repositories/other/herdr-scheduled/herdr-plugin.toml` — one-shot startup hooks and
  the delegation to the OS scheduler (lines 2–4); `HERDR_PLUGIN_ROOT` indirection and the GH #58
  reason (lines 7–11); the `-windows` action id suffix (lines 12–13); the POSIX `:?` assertion
  (line 28); the Windows root-resolution and prefix-strip snippet (lines 34–35)
- `C:/Development/Repositories/other/herdr-default-layout/scripts/lib.sh` — the "no bash, no jq, no
  python" constraint and the two JSON-reading rules (lines 1–14); token-only field decoding (lines
  21–31)
- `C:/Development/Repositories/other/herdr-default-layout/scripts/lib.ps1` — `Remove-VerbatimPrefix`
  (lines 5–8); `Get-PaneField` and the reason optional fields throw under `Set-StrictMode` (lines
  10–15); the documented empty `catch` with its stated reason (lines 17–31); prefix strip applied to
  `plugin_root` and `plugin config-dir` (lines 42, 50)
- `C:/Development/Repositories/other/herdr-default-layout/herdr-plugin.toml` — the two reasons for
  `HERDR_PLUGIN_ROOT` over a relative path (lines 14–18); the Windows snippet (lines 35–36); which
  event names Herdr actually dispatches to plugin hooks (lines 66–69)
- `C:/Development/Repositories/other/herdr-scheduled/.gitattributes` — `LF` for `*.sh`, `CRLF` for
  `*.ps1`, and the shebang reason (lines 1–11)
- `C:/Development/Repositories/other/herdr-default-layout/.gitattributes` — the `bash` refuses `CR`
  reason (lines 1–2)

Project documents in this repository:

- `docs/02-herdr-probe-results.md` — R-02-001 through R-02-017. Every rule in §7 derives from it.
- `docs/03-product-decisions.md` — R-03-060 (local notifications only).
- `docs/11-relay-protocol.md` — R-11-035 (1 MiB frame size), `host_info` and `device_info` message
  definitions, `agent_status` payload.
- `docs/12-relay-hosting.md` — §2 workspace layout and crate dependency pins, R-12-003 (opaque
  forwarding), R-12-007 (500 pairs), R-12-014 (permitted log fields).
- `docs/13-security-pairing.md` — Host generates and renders QR code.
- `docs/20-mobile-framework.md` — Flutter 3.47.0, Dart 3.13.0, the full dependency table.
- `docs/21-terminal-rendering.md` — R-21-005 (`xterm2` 5.2.0), R-21-021 (120 ms coalescing window),
  R-21-009 (columns from `rect.width`).
- `docs/30-ux-spec.md` — screens, flows, interaction model, states and accessibility behaviour.
  R-30-511 (notification degenerate routes).
- `docs/32-design-language.md` — every visual value: the Selenized dark and light palettes,
  JetBrainsMono Nerd Font Mono 2.304 with Nerd Fonts v3.5.1 (R-21-011, R-21-012), IBM Plex Sans
  1.1.0, the 4-unit spacing scale, the 48 by 48 logical pixel minimum touch target, the motion
  durations, the Material Symbols
  icon map, and the computed contrast table that forbids a status hue on text.
- `docs/40-repo-tooling.md` — validation commands, future implementation tree.

External sources:

- `flutter_lints` 6.0.0, BSD-3-Clause, SDK `^3.8.0`, depends on `lints` `^6.0.0` —
  <https://pub.dev/packages/flutter_lints>
- `xterm2` 5.2.0, MIT, Flutter `>=3.19.0`, Dart `>=3.0.0 <4.0.0` —
  <https://pub.dev/packages/xterm2>
- `dart format` documentation, page reflects Dart 3.13.0 — <https://dart.dev/tools/dart-format>
- Dart linter rules catalogue — <https://dart.dev/tools/linter-rules>
- Rust edition 2024 — <https://doc.rust-lang.org/edition-guide/rust-2024/>
- `cargo clippy` lint levels — <https://doc.rust-lang.org/clippy/>
- `thiserror` 2.0.20 — <https://crates.io/crates/thiserror/2.0.20>
- `tokio` 1.53.1 — <https://crates.io/crates/tokio/1.53.1>
- Verified crate version pins — `docs/12-relay-hosting.md` §2.1

## Open questions

1. **`xterm2` version conflict.** The parent's brief named `xterm2` 5.3.0.
   `docs/21-terminal-rendering.md` R-21-005 names 5.2.0, and the pub.dev API reports
   `Latest: 5.2.0`. **Decision applied:** this document states 5.2.0, because the package registry
   is authoritative and it agrees with the owning document. If 5.3.0 is published later, update
   R-41-107 and the pin in `app/pubspec.yaml` together.

2. **Function-length limit for table-driven tests.** R-41-012 sets 60 lines, and a Rust `#[test]`
   table-driven test or a Dart `group` block legitimately exceeds it. **Decision applied:** the
   Rust `#[cfg(test)]` exemption from R-41-126 already accepts that test code has different rules.
   R-41-012 is reviewed, not enforced, for test files in both Rust and Dart.
