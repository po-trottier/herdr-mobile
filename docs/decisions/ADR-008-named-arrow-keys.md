# ADR-008: The bridge sends arrow keys by name, never as a raw escape sequence

## Status

Accepted.

## Date

2026-08-27

## Context

`docs/10-herdr-integration.md` R-10-037 requires the bridge to send every named key —
especially the arrows — through Herdr's `pane.send_input` `keys` field (`{"keys":["Up"]}`),
never as a raw CSI byte sequence in `text`. The stated reason: only Herdr owns the pane's
terminal state, so only Herdr knows whether the foreground program has set DECCKM
(application cursor mode), which changes the correct arrow encoding from `ESC [ A` to
`ESC O A`. A bridge that sent the raw form itself would guess, and guess wrong whenever a
full-screen program (an editor, a pager, a TUI) has DECCKM set.

Until this phase, that requirement carried an explicit `[UNVERIFIED]` marker in
`docs/10-herdr-integration.md` §6.5: nobody had measured whether Herdr actually resolves
DECCKM correctly for the named path, because the Herdr server is closed-source and the
repository holds no server code to read. `docs/90-implementation-plan.md` Phase 7 required
this phase to run the spike and record the real result before the input path shipped.

### The spike

`crates/herdr-relay/src/bin/spike-input.rs`'s `decckm_spike` function, run against a live
Herdr `0.8.2-preview.2026-08-19-b5c4a0176e91` server (protocol 20, superseded by protocol 21 on
2026-09-02) on Windows 11 `10.0.26200`:

1. Create a scratch pane and launch real `vim` (Git for Windows' `vim.exe`) in it.
2. Type three distinguishable lines — `AAAA`, `BBBB`, `CCCC` — leaving the cursor on the
   last character of `CCCC`.
3. Send the named key `Up` through `pane.send_input {"keys":["Up"]}` — the exact call
   `watch/input.rs`'s `send_input` handler makes in production.
4. Send `x` (delete-under-cursor in vim's normal mode).
5. Read the pane and compare which line lost a character. If `Up` moved the cursor to
   `BBBB`, that line loses a character. If it did not move the cursor, `CCCC` loses one
   instead, or the raw escape bytes leak into the buffer as literal text.

This is a behavioural test, not a byte-level capture: on Windows, every keystroke the
bridge writes into a pane's input passes through ConPTY before a console client (vim's
Windows console I/O layer included) can observe it, and ConPTY normalises `ESC [ A` and
`ESC O A` into the same logical "Up arrow" input event before delivering it. There is no
way to inspect, from inside a Windows pane, which of the two raw forms Herdr actually chose
on the wire to the PTY. The functional outcome — did the cursor move to the correct line —
is the only thing observable on this platform, and it is also the only thing that matters:
a Device sending a named key cares whether Herdr moved the cursor correctly, not which byte
sequence it used to do it.

### Measured result

Two independent runs (2026-08-27) produced the identical, reproducible outcome:

```text
decckm spike: after typing three lines: "AAAA\r\nBBBB\r\nCCCCi\r\n..."
decckm spike: after Up + x: "AAAA\r\nBBBBx\r\nCCCCi\r\n..."
```

The named `Esc` key sent between steps 2 and 3 did not return vim to normal mode in this
run (both `i` and `x` landed as literal inserted characters, visible as the trailing `i`
and the appended `x`), so the whole sequence executed while vim was still in insert mode —
a byproduct of the test harness's timing, not of the `Up` key itself. That turned out to be
informative rather than a wasted run: vim recognises cursor keys in insert mode too, moving
the cursor without leaving insert mode, so the `x` character's exact landing spot is still a
faithful, unambiguous marker of where `Up` actually placed the cursor.

The `x` landed at the end of `BBBB` (`BBBBx`), not at the end of `CCCC`. That is exactly the
position `Up` should produce: one line above the cursor's starting position, at the same
column. Herdr moved the cursor correctly in response to the named `Up` key, sent while vim
held its own terminal-mode state (including whatever cursor-key mode vim itself set on
entry). The named path produced the functionally correct result.

## Decision

The bridge sends every key that has a Herdr-accepted name — including all four arrows —
through `pane.send_input`'s `keys` field, per R-10-037, R-10-044 and R-11-054. It never
constructs a raw arrow-key escape sequence itself. `crates/herdr-relay/src/watch/input.rs`
implements no DECCKM-aware branching of its own: it forwards the Device's already-resolved
`keys` entries after validating them against the accepted vocabulary
(`crates/herdr-relay/src/watch/key_map.rs`), and lets Herdr make the DECCKM decision, which
this spike confirms Herdr does correctly for a real full-screen program.

The `[UNVERIFIED]` marker on R-10-037 in `docs/10-herdr-integration.md` §6.5 is resolved:
the recommended default (prefer the named path) is now a measured result, not just a
delegation of the decision to the component that owns the terminal state.

## Consequences

- `send_input`'s four-step resolution order (R-11-054) needs no fifth, DECCKM-aware step.
  The bridge's only job for a named key is validation (`key_map::validate_key`), not
  encoding.
- The six keys with no Herdr name (`Home`, `End`, `PageUp`, `PageDown`, `Delete`, `Insert`)
  remain the one deliberate exception: they still cross the wire as a raw sequence in
  `text` (R-10-036), because Herdr genuinely offers no name for them, not because the named
  path is unsafe.
- This spike ran on Windows only, because that is the only live Herdr host available to
  this session. The ConPTY input-normalisation limitation described above applies to
  Windows specifically. A POSIX host (Linux or macOS) can observe the raw bytes directly —
  for example by running `cat -v` in the target pane instead of vim, which echoes every
  byte it receives without any console-level reinterpretation — and would give a
  byte-level (not just behavioural) confirmation of which escape form Herdr chose. Revisit
  with that POSIX byte-level capture if this result is ever contested; the recommended
  default until then is to trust this measurement, because it tests the thing a Device
  actually depends on (correct cursor movement), not an implementation detail Herdr is free
  to change.
- `crates/herdr-relay/src/bin/spike-input.rs` keeps this spike in the repository, matching
  the precedent `src/bin/spike-read.rs` and `src/bin/spike-subscribe.rs` set in Phase 1: a
  live-Herdr measurement stays runnable so a future Herdr upgrade can be re-verified with
  one command (`cargo run -p herdr-relay --bin spike-input`) instead of re-deriving the
  finding from memory.
