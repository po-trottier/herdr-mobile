# Verified Herdr Socket Probe Results

This document records facts measured directly against a live Herdr server. Every number here comes
from a real probe, not from documentation and not from inference. Treat this file as ground truth.
If another document contradicts it, this file wins.

- Herdr version: `0.9.0-preview.2026-09-08-62431dbd033b`, measured 2026-09-10 (R-02-028)
- Socket protocol: `22`
- Host platform of the probe: Windows 11, `win32 10.0.26200`
- Probe client: Node `net.connect({ path })`

## R-02-001 Transport uses one path string on every platform

Herdr reports one socket path from `herdr status`. On this machine:

```text
socket: C:\Users\<user>\AppData\Roaming\herdr\herdr.sock
```

That file is **not** a socket. It is a 25-byte text file that holds `<pid>:<starttime_ns>`:

```text
54888:1787194020218079000
```

`54888` is the Herdr server process ID. The file is an identity and liveness marker only.

On Windows the real channel is a **named pipe whose name is the full socket path**, including the
drive letter and the backslashes. Enumerating live pipes confirms it:

```text
\\.\pipe\C:\Users\<user>\AppData\Roaming\herdr\herdr.sock
\\.\pipe\C:\Users\<user>\AppData\Roaming\herdr\herdr-client.sock
```

A client therefore prefixes the reported path with `\\.\pipe\` on Windows and uses the path directly
as an `AF_UNIX` address on Linux and macOS.

**R-02-001**: A client MUST read the socket path from `herdr status`, then on Windows MUST connect to
`\\.\pipe\` + that path, and on Linux and macOS MUST connect to that path as an `AF_UNIX` address.

**R-02-002**: A client MUST NOT parse the `.sock` file as a socket address. It MAY read it to learn
the server process ID and to check that the server is alive.

There is a second pipe, `herdr-client.sock`. Its purpose is not yet established.

### Independent corroboration from `herdr-sidebar`

`herdr-sidebar` is a Rust Herdr plugin that ships a compiled binary for all three platforms. Its
socket client is at
`C:/Development/Repositories/other/herdr-standalone/plugins/herdr-sidebar/plugins/herdr-sidebar/src/ipc.rs`.
Its module comment states the same two facts this document measured, reached independently:

> Minimal client for herdr's socket API: newline-delimited JSON, one request/response per connection
> (`{"id":..,"method":"pane.split","params":{..}}`).
>
> On Windows the socket is a named pipe at `\\.\pipe\<HERDR_SOCKET_PATH>` (herdr feeds the whole path
> through interprocess' namespaced naming), which a plain `File` can speak. On unix it is an ordinary
> unix domain socket.

That file is the reference implementation to copy. Three practical details it adds:

1. **`HERDR_SOCKET_PATH` is injected into plugin hook and action commands.** Read that environment
   variable first and fall back to the default socket location. This beats parsing `herdr status`.
2. A Windows named-pipe `File` has **no** `set_read_timeout` through the Rust standard library, so
   `ipc.rs` bounds the read with a background thread and `recv_timeout`. A POSIX socket supports a
   native read timeout, so the unix path needs no thread.
3. It caps a response line at 4 MiB and times out after 5 seconds, so a malformed reply cannot grow
   without bound and a wedged peer cannot hang the caller.

**R-02-001a**: A client MUST read the socket path from `HERDR_SOCKET_PATH` when that variable is set,
and MUST fall back to the platform default location otherwise.

## R-02-003 CPython on Windows cannot speak this protocol over AF_UNIX

`socket.AF_UNIX` does not exist in CPython on Windows, so a Python client cannot use the POSIX path
form. Node, Bun, and .NET all handle both forms: `net.connect({ path })` accepts the pipe name and
the socket path, and .NET offers `NamedPipeClientStream` and `UnixDomainSocketEndPoint`.

**R-02-003**: The bridge process MUST NOT be written in Python if it must run on Windows.

## R-02-004 Strictly one request per connection

The server reads exactly one request line, sends exactly one response, then half-closes. This is
measured, and it is the single most important constraint on the bridge design.

Two pings written in one `write` call:

```text
+1ms   wrote 102B   (two complete request lines)
+101ms recv id=a result:pong
+101ms END           (server half-close)
```

The second request is discarded. A three-request pipeline behaves the same way: only `id=a` answers.
Any later write on that connection fails with `EPIPE`.

**R-02-004**: A client MUST open a new connection for every request. A client MUST NOT pipeline, and
MUST NOT reuse a connection after a response.

**R-02-005**: A client MUST treat `EPIPE` on write as the normal end of a used connection, not as an
error worth reporting.

## R-02-006 A subscription connection is event-only

`events.subscribe` behaves differently. It answers `subscription_started` and then streams events on
the same connection for as long as the client holds it open. That connection will **not** answer any
further request. A `ping` and a `pane.read` sent afterwards both received no response, while events
continued to arrive normally:

```text
+2ms    sent events.subscribe
+103ms  recv id=1 result:subscription_started
+105ms  recv event:pane_updated
+302ms  sent ping                 <- never answered
+602ms  sent pane.read            <- never answered
+612ms  recv event:pane_updated
...     events continue for as long as the socket stays open
```

**R-02-006**: The bridge MUST hold one long-lived connection per subscription set, and MUST issue
every request on its own separate short-lived connection.

## R-02-007 Envelope shapes

Request:

```json
{"id":"<string>","method":"<string>","params":{}}
```

`params` is **required**, even when empty. Omitting it fails:

```json
{"id":"","error":{"code":"invalid_request","message":"invalid request: missing field `params` at line 1 column 27"}}
```

Success responses wrap the payload in a typed envelope. `result.type` is a discriminator and the
payload sits under a second key that varies by method:

| Method             | `result.type`          | Payload key |
| ------------------ | ---------------------- | ----------- |
| `ping`             | `pong`                 | inline      |
| `session.snapshot` | `session_snapshot`     | `snapshot`  |
| `pane.read`        | `pane_read`            | `read`      |
| `events.subscribe` | `subscription_started` | inline      |

A real `ping` result:

```json
{"id":"omp-2","result":{"type":"pong","version":"0.8.2-preview.2026-08-31-b1ff4582e968","protocol":21,"capabilities":{"live_handoff":false,"detached_server_daemon":false}}}
```

**R-02-007**: A client MUST send `params`, even as `{}`. A client MUST read a result through
`result.<payload_key>`, not directly from `result`.

**R-02-008**: The client MUST call `ping` first and compare `result.protocol` with this build's
exact protocol, `22`.

Protocol `22` is a compatible increment for every call this repository makes. `R-02-028` records
the 2026-09-10 comparison with protocol `21` and the live probes against protocol `22`. The
comparison found one optional request field and three capability fields. No client call needs a
shape change. The Host MUST reject every protocol integer other than `22`.

## R-02-009 A malformed request closes the connection

An invalid enum value returns an error with an **empty** `id`, then the connection closes:

```json
{"id":"","error":{"code":"invalid_request","message":"invalid request: unknown variant `Visible`, expected one of `visible`, `recent`, `recent_unwrapped`, `detection` at line 1 column 96"}}
```

Enum values are lowercase with underscores. `Visible` fails and `visible` succeeds.

**R-02-009**: The bridge MUST validate a request against the schema before forwarding it, because a
malformed request costs the connection and returns an error that cannot be correlated by `id`.

## R-02-010 Throughput

| Measurement            | Result  |
| ---------------------- | ------- |
| 5 pings, serial        | 103 ms  |
| 5 pings, parallel      | 101 ms  |
| Effective serial rate  | ~50 req/s |

**Corrected.** `pane.read` round-trip is **1 ms at p50**. The ~100 ms figure above appears only at
p95, so it is a tail, not a floor. One connection per request is much cheaper than the ping table
suggests, and a coalescing window sized around a 100 ms floor would be wrong.

**R-02-010**: A coalescing window MUST be sized against the 1 ms p50 round trip and never against
the ~100 ms p95 tail. One connection per request is cheap, so a window chosen to amortise a 100 ms
floor would be wrong.

## R-02-011 The `pane.updated` event carries the whole pane object

This removes the need for a read just to detect change. The event payload is
`{"type":"pane_updated","pane":{...}}`, and the pane object holds `revision` and the viewport size:

```json
{
  "event": "pane_updated",
  "data": {
    "type": "pane_updated",
    "pane": {
      "pane_id": "w1V:pE",
      "workspace_id": "w1V",
      "tab_id": "w1V:t1",
      "terminal_id": "term_6597188ea2acdd",
      "label": "Explorer",
      "cwd": "D:\\Repositories\\...",
      "focused": false,
      "agent_status": "unknown",
      "revision": 82195,
      "scroll": { "offset_from_bottom": 0, "max_offset_from_bottom": 0, "viewport_rows": 85 },
      "tokens": { "herdr-sidebar-explorer": "1787621906" }
    }
  }
}
```

**R-02-011**: On the event path the bridge MUST use `data.pane.revision` from the event to decide
whether to read. It MUST NOT call `pane.read` in reaction to an event merely to discover whether
anything changed. The bounded timer read of `R-02-026` and `R-10-070` is the one exception, and
it exists because the event path alone misses the agent panes measured there (corrected
2026-09-03).

## R-02-012 `revision` is a reliable change token

Two reads of the same pane 1.2 s apart, with an unchanged `revision`, produced byte-identical text.

```text
same pane two reads 1.2s apart: rev 0 -> 0, identical text? true
lines: 50 -> 50, changed lines: 0
```

**R-02-012**: On the event path the bridge MUST skip the read when `revision` did not move. This
rule scopes the event path only: `R-02-026` records the agent panes whose text changes while
`revision` stays still, and `R-10-070` owns the timer read that catches them (corrected
2026-09-03).

**Corrected.** The `revision` field inside a `pane.read` result is **always `0`**, for all four
sources. It is not a separate counter, it is simply unpopulated. At the same instant
`session.snapshot` reported `82606` for the same pane.

**R-02-012a**: A client MUST take `revision` only from a `pane_updated` event or from
`session.snapshot`. It MUST NOT read `revision` from a `pane.read` result. See
`docs/10-herdr-integration.md` R-10-020.

## R-02-013 There is no server-side pane filter, and idle plugin panes are chatty

The `pane.updated` subscription accepts only `{"type":"pane.updated"}`. It has no `pane_id` field, so
there is no server-side filter.

Measured over 10 s on an otherwise idle machine:

```text
events in 10s: 98  (9.8/s)

pane            n  distinctRev  first->last  rows  label
w1V:pE         15           15  82200->82214    85  Explorer
w1W:p7         14           14  82461->82474    85  Explorer
w1X:p9         13           13  82182->82194    85  Explorer
w28:p2         14           14  303->316        85  Explorer
w3:pS          15           15  82416->82430    85  Explorer
w3:pY          13           13  5077->5089      85  Explorer
w5:p45         14           14  82513->82526    85  Explorer

panes whose revision actually moved: 7 of 7
```

Every event came from a `herdr-sidebar` `Explorer` pane, each repainting about 1.4 times per second.
The seven idle agent panes produced no events at all. So the stream is genuinely change-driven, but
background plugin panes generate about 10 events per second of pure noise.

**R-02-013**: The bridge MUST filter events to the panes a Device is actually viewing. Forwarding the
raw event stream would waste roughly 10 events per second on panes nobody is watching.

**R-02-013a**: Unlike `pane.updated`, a `pane.agent_status_changed` subscription entry requires its
own `pane_id` field. `{"type":"pane.agent_status_changed"}` alone is refused. Measured (re-measured
2026-09-02 against Herdr `0.8.2-preview.2026-08-31-b1ff4582e968`, protocol `21`, superseding the
2026-08-27 measurement at protocol `20`):

```json
{"id":"","error":{"code":"invalid_request","message":"invalid request: missing field `pane_id` at line 1 column 157"}}
```

`{"type":"pane.agent_status_changed","pane_id":"<id>"}` is accepted and answers
`subscription_started`. See `docs/10-herdr-integration.md` §3.3.

## R-02-014 ANSI fidelity is real

`pane.read` with `format: "ansi"` and `strip_ansi: false` returns genuine ANSI, including 24-bit
truecolour SGR. A real captured fragment, with `ESC` shown as `\e`:

```text
 implementation: \e[0m\e[38;2;0;255;136mbase_hash\e[0m + \e[0m\e[38;2;0;255;136mvalidation_passed\e[0m, never \e[0m\e[38...
```

`\e[38;2;0;255;136m` is a 24-bit foreground colour. A real VT emulator on the Device will paint this
exactly as the Host shows it.

**R-02-014**: A faithful read MUST pass `format: "ansi"` and `strip_ansi: false`. The default
`strip_ansi` is `true`, which silently discards all styling.

## R-02-015 Measured payload sizes

`source: "visible"`, 50-row panes:

| Pane     | Rows | Label    | ANSI bytes | Text bytes | ANSI / text |
| -------- | ---- | -------- | ---------- | ---------- | ----------- |
| `w3:p2`  | 50   | omp      | 8105       | 3509       | 2.31x       |
| `w3:pX`  | 50   | omp      | 9378       | 5970       | 1.57x       |
| `w1X:p1` | 50   | omp      | 7555       | 3545       | 2.13x       |
| `w5:p1`  | 50   | omp      | 8601       | 4640       | 1.85x       |
| `w3:pS`  | 50   | Explorer | 2438       | 1162       | 2.10x       |
| `w5:p45` | 50   | Explorer | 972        | 320        | 3.04x       |

**R-02-015**: A design MUST size its transport budget against roughly 8 KB per full-viewport ANSI
read of an agent pane. ANSI is about twice the size of stripped text.

## R-02-016 ANSI compresses extremely well

| Pane     | Raw  | gzip | deflateRaw | brotli | gzip % | brotli % |
| -------- | ---- | ---- | ---------- | ------ | ------ | -------- |
| `w3:p2`  | 8105 | 1922 | 1904       | 1534   | 24%    | 19%      |
| `w3:pX`  | 9378 | 1507 | 1489       | 1221   | 16%    | 13%      |
| `w1X:p1` | 7555 | 1156 | 1138       | 981    | 15%    | 13%      |
| `w5:p1`  | 8601 | 1810 | 1792       | 1466   | 21%    | 17%      |

Compression cuts an 8 KB frame to about 1.2 KB to 1.9 KB.

**R-02-016**: The Host-to-Device transport MUST compress frames. This requires application code:
zlib compression applied to the frame envelope's bytes before Noise encryption
(`docs/11-relay-protocol.md` R-11-229 to R-11-239), not WebSocket-level `permessage-deflate`, which
neither pinned WebSocket library implements. The measurement above used `gzip`, `deflateRaw` and
`brotli` generically, not the pinned `flate2`/`dart:io` `ZLibCodec` zlib pipeline; the 13-24 percent
figure MUST be re-measured through the real implementation once R-11-229 to R-11-239 are built,
rather than assumed to hold unchanged. This makes the full-snapshot approach affordable on a mobile
network and removes any early need for a cell-level diff.

## R-02-017 Rows and columns are both available, from two different calls

> **Corrected.** An earlier version of this rule said no field reports the column count. That was
> too pessimistic. `HerdrIntegration` found the column count in `pane.layout`.

Every pane object carries `scroll.viewport_rows`, plus `offset_from_bottom` and
`max_offset_from_bottom`, which together describe the scrollback position. Measured values were 50
and 85 rows, and `max_offset_from_bottom` reached 9184 on a busy agent pane.

`pane.layout` returns a rect measured in **character cells**, not pixels. The proof is arithmetic:
across all seven tabs the pane widths sum exactly to the area width, for example `22+61+61=144` and
`22+122=144`.

There is one trap. `rect.height` minus `scroll.viewport_rows` was `2` in every split tab and `0` in
the single-pane tab `w3:t7`. Tab chrome is therefore included conditionally, and the difference is
not safely subtractable.

**R-02-017**: The bridge MUST take the row count from `scroll.viewport_rows` and MUST NOT derive it
from `rect.height`. It MUST take the column count from `pane.layout` `rect.width`. The Device
receives the grid size in the `pane_frame` relay message, per `docs/11-relay-protocol.md`
R-11-051, and calls no Herdr method itself. See `docs/10-herdr-integration.md` R-10-024.

## R-02-018 `pane.read` returns a pre-rendered flat grid, styled only with SGR

This is the most consequential measurement in this document. It removes a whole class of work from
the Device.

I scanned all 14 live panes and matched **every** escape form, not only SGR: `CSI` with any final
byte, `OSC`, charset selects, and single-character escapes. The result:

```text
panes scanned: 14, total escapes: 3972
   2003  CSI m (SGR:0)
    851  CSI m (SGR:38)     truecolour and 256-colour foreground
    735  CSI m (SGR:48)     background
    282  CSI m (SGR:2)      dim
     72  CSI m (SGR:1)      bold
     28  CSI m (SGR:3)      italic
      1  CSI m (SGR:4)      underline

NON-SGR escape kinds: NONE
```

Zero cursor motion. Zero erase. Zero scroll region. Zero `OSC`. Zero mode switches. Zero
alternate-screen switches. This held even for panes running full-screen TUI applications on the
alternate screen.

So `pane.read` is not a terminal byte stream. Herdr already ran the VT state machine and handed back
a flattened grid: one line per row, styled only with SGR. The complete measured vocabulary is `0`,
`1`, `2`, `3`, `4`, `38;2`, `48;2`, `38;5`, `48;5`, and nothing else.

**R-02-018**: The Device needs an SGR parser over an array of rows. It MUST NOT be given a
cursor-addressing VT state machine on the assumption that one is required. `docs/21-terminal-rendering.md`
owns the resulting render decision.

## R-02-019 `source: "detection"` ignores `strip_ansi`

`source: "detection"` silently returns stripped text while still echoing `"format":"ansi"` in the
result.

**R-02-019**: The Device MUST NOT use `source: "detection"` for rendering. Use `source: "visible"`.

## R-02-020 The pane-action parameter shapes

`herdr api schema --json` is a runtime call and never a committed file, so these shapes are recorded
here. Four of them appear nowhere else in this repository, and two fabricated parameter lists
survived several reviews because nobody could check them.

| Method | Params object | Fields | Required |
| --- | --- | --- | --- |
| `pane.split` | `PaneSplitParams` | `cwd`, `direction`, `env`, `focus`, `ratio`, `target_pane_id`, `workspace_id` | `direction` |
| `pane.zoom` | `PaneZoomParams` | `mode`, `pane_id` | none |
| `pane.close` | none | `pane_id` at the top level only | - |
| `pane.rename` | `PaneRenameParams` | `label`, `pane_id` | `pane_id` |
| `pane.resize` | `PaneResizeParams` | `amount`, `direction`, `pane_id` | `direction` |

`PaneZoomMode` is an enum of `toggle`, `on` and `off`, and it defaults to `toggle`.
`SplitDirection` is `right` or `down`. `PaneDirection`, which `pane.resize` takes, is `left`,
`right`, `up` or `down`.

**R-02-020**: `pane.split` MUST NOT carry a `label`. `WorkspaceCreateParams` and `TabCreateParams`
each hold one and `PaneSplitParams` does not, so a new pane cannot be named as it is created.
`R-30-954` already omits the parameter for every create; this measurement is why a pane has no
choice in the matter.

**R-02-021**: `pane.resize` MUST NOT be given a column or a row count. It moves a split boundary by
`amount` in one `direction`, so no request can set explicit terminal dimensions.

**R-02-022**: `pane.rename` MAY send `label` as `null`, which clears the label.

**R-02-023**: `pane.zoom` with `mode` `on` or `off` is idempotent and `toggle` is not. A retry after
an unknown outcome MUST use `on` or `off`, per `R-30-518`.

## R-02-024 Plugin actions, and how many of them open a pane

Measured with `plugin.action.list` against a live server: 20 actions across four plugins,
`herdr-scheduled`, `herdr-sidebar`, `tab-smart-rename`, and platform-suffixed twins of several.

**Ten of the twenty open, focus or close a pane.** Five of the descriptions, verbatim:

| Action | Description returned by the server |
| --- | --- |
| `herdr-scheduled/open` | Opens the scheduled job manager (macOS, Linux). |
| `herdr-sidebar/open-git` | Open a separate Source Control pane (focus it if open; close it if focused). |
| `herdr-sidebar/open-sidebar` | Open the sidebar docked on the left (focus it if open; close it if focused). |
| `herdr-sidebar/redeploy` | Close all sidebar panes in every workspace so they respawn on the latest build. |
| `tab-smart-rename/configure-ai` | Open the private AI provider configuration. |

`contexts` is absent on all ten, so `R-30-966` treats them as `global`.

**R-02-024**: A plugin action MAY create, focus or close a pane. No document may state that a
plugin action creates no entity. `R-11-217` carries the pane the Host attributes to an invocation.

**R-02-025**: The list carries platform twins, `open` beside `open-windows`, so the Host MUST filter
by its own platform before the list crosses the wire. Twenty actions collapse to about fifteen on
one Host.

## R-02-026 An agent pane can repaint without its `revision` ever moving

Measured 2026-09-03 against Herdr `0.8.2-preview.2026-08-31-b1ff4582e968` (protocol 21), pane
`w28:pW`, an `omp` agent pane with `agent_status: "working"` that produced output the whole time:

- Two `session.snapshot` calls 5 s apart: `revision` stayed `30`. Over the same session its
  `scroll.max_offset_from_bottom` moved from 1814 to 1821.
- Two `pane.read` calls (`source: "visible"`, `format: "ansi"`) bracketing the same 5 s: the text
  changed. 2 of 85 rows differ; the sha256 of the payload differs.
- A 7 s `events.subscribe` capture on `pane.updated` in the same window: **zero** events for
  `w28:pW`, while every `Explorer` (herdr-sidebar) pane kept emitting. The Explorer pane `w28:p15`
  moved `31089 -> 31090` across the same two snapshots (31227 -> 31228 on the CLI repeat).

So R-02-011 and R-02-012 hold for the plugin panes they were measured on, but not for this agent
pane: its revision is not a change token, and no event announces its repaints. A watch loop that
reads only on revision movement freezes at the first frame for exactly these panes.

**R-02-026**: The bridge MUST NOT rely on `revision` movement alone to deliver frames for a watched
pane. It MUST also read on a timer and suppress unchanged frames itself, per
`docs/10-herdr-integration.md` R-10-070.

The raw `session.snapshot` pane object of this build does carry `screen_detection_skipped: true`
and a moving `state_change_seq` (195 on the same pane, read on 2026-09-03 with `herdr api
snapshot`); the typed `PaneInfo` model in `crates/herdr-relay-proto` does not keep either field,
and neither is a documented change token. The measurable signature of the defect on protocol 21
is therefore the frozen revision plus the silent event stream above.

## R-02-027 No blank or half-painted `pane.read` snapshot was observed in 766 reads

Measured 2026-09-08 against Herdr `0.8.2-preview.2026-08-31-b1ff4582e968` (protocol 21), pane
`w2N:p2`, a 240x85 `omp` agent pane redrawing its bottom rows while it worked. A probe reproduced
the bridge's exact schedule (the 120 ms leading-edge window of R-10-029 that never restarts, the
250 ms poll of R-10-070, the 8 reads per second cap of R-10-030) and recorded counts only:

- 766 reads over four runs, driven by five to seven redraw bursts per run.
- 0 blank frames and 0 partial frames. Every frame carried 83 or 85 lines, 713 to 940 non-blank
  cells and 74 to 79 non-blank rows.
- No frame carried a cursor move, an erase, a private-mode set or an OSC sequence.
- 2 reads failed at the socket (`Connect`, Windows named-pipe exhaustion) and returned no frame.
- 209 consecutive poll reads on a static pane: 3382 to 3387 cells and 46 rows, every time.
- The frame's own last non-blank row moved between consecutive frames, 83 and 85 on the 85-row
  pane, about four frames a second.

A first run reported six blank frames; the probe had converted a failed read into an empty
string. Within this sample, Herdr's grid was complete at read time while the TUI repainted.

**R-02-027**: A design that reasons about a blank or half-painted snapshot MUST cite this
measurement as its baseline: on this build, pane and schedule, 766 reads produced none, and the
frame's last non-blank row is not stable between frames. This rule records the observation only.
`docs/10-herdr-integration.md` R-10-029 owns the read-schedule consequence and
`docs/21-terminal-rendering.md` R-21-021 owns the Device anchor consequence.

## R-02-028 Protocol 22 compatibility probe, 2026-09-10

Measured against Herdr `0.9.0-preview.2026-09-08-62431dbd033b` on Windows 11.
The live server reports protocol `22`. The schema reports `schema_version: 1`.

### Schema evidence

The probe saved `herdr api schema --json` to `C:/tmp/proto22/schema.json`. It compared that
capture with the saved protocol-21 schema at `C:/tmp/herdr-schema.json` and the fields previously
listed in R-02-008. The complete structural comparison is `C:/tmp/proto22/schema-diff.json`.

| Capture | SHA-256 |
| --- | --- |
| Protocol 21 | `076549b3c37619dcfa530c946c6555b94923ac363a916cc7ae336ac41dfc0611` |
| Protocol 22 | `5fb46b13fdaf39c88cf699b9806685868c7ee6b0142523d84391b1606416dc0a` |

The method count increased from 91 to 102. No method was removed.
The added methods are `product_announcement.dismiss`, `release_notes.dismiss`, `command.invoke`,
`client_shell.surface.set`, `pane.scroll`, `pane.edit_scrollback`, `pane.selection.read`,
`pane.copy_motion`, `pane.copy_search`, `pane.link.activate`, and `integration.list`.
None is a call this repository makes.

The comparison found these changes to existing calls:

| Contract | Protocol 21 to 22 difference |
| --- | --- |
| `workspace.create` | Added optional `source_workspace_id`, a string or null. It selects the workspace whose focused pane supplies the `follow` cwd policy. No required field changed. |
| `ping` capabilities | Added optional `endpoint_protocol_generation`, an integer (uint32) or null, `surface_interest: boolean`, and `health_check: boolean`. The boolean defaults are `false`. |
| Other existing request and result shapes | No change. |
| Event and subscription-event schemas | No change. |

The live capability map keeps `live_handoff: false` and `detached_server_daemon: false`.
It adds `endpoint_protocol_generation: 1`, `surface_interest: true`, and `health_check: true`.
The ping envelope is saved in `C:/tmp/proto22/ping.json`.

The new result variants are `pane_selection`, `pane_copy_motion`, `pane_copy_search`,
`integration_list`, `pane_link_activated`, and `client_shell_surface_set`.
They do not change an existing result variant or a Host call.
The request schema adds `ClientShellSurfaceSetParams`, `CommandInvokeParams`, `PaneCopyMotion`,
`PaneCopyMotionParams`, `PaneCopySearchDirection`, `PaneCopySearchParams`, `PaneLinkActivateParams`,
`PaneScrollParams`, `PaneSelectionReadParams`, `PaneTextPoint`, `PaneTextRange`,
`ProductAnnouncementDismissParams`, and `ReleaseNotesDismissParams`.
The result schema adds `IntegrationInfo`, `IntegrationState`, `PaneTextPoint`, and `PaneTextRange`.

These R-02-008 fields have identical definitions in both captures:

- `PaneReadParams{pane_id*, source*, format, strip_ansi, lines}`.
- `ReadSource`: `visible|recent|recent_unwrapped|detection`; `ReadFormat`: `text|ansi`.
- `EventsSubscribeParams{subscriptions*}` and `PaneSendInputParams{pane_id*, keys, text}`.
- `PaneReadResult.revision`, `PaneInfo.revision`, `PaneInfo.scroll.viewport_rows`, and
  `PaneLayoutRect.width`.

### Live call evidence

Every request used a new connection and included `params`.
The subscription connection sent only `events.subscribe`, received `subscription_started`
and one `pane_updated` event, then closed. The event carried a pane object and `revision: 1`.
The probe saved request and response evidence in `C:/tmp/proto22/probes.json`.

| Call | Observed result |
| --- | --- |
| `ping` | `result.type: pong`, `result.protocol: 22`. |
| `session.snapshot` | `result.snapshot`; the first probe pane had `revision: 0` and `scroll.viewport_rows: 87`. |
| `pane.layout` | `result.layout`; the first probe pane had `rect.width: 292`. |
| `pane.read`, visible and recent | `result.type: pane_read`, `result.read.revision: 0`. Both retained the exact SGR sequence `ESC[38;2;17;34;51mproto22-ansi`. |
| `pane.send_input` | `result.type: ok`; the owned shell printed the marker. |
| `workspace.create` | `result.workspace`, `result.tab`, and `result.root_pane`; created `w2F` with `focus: false`. |
| `tab.create` | `result.tab` and `result.root_pane`; created `w2F:t2`. |
| `pane.split`, `pane.focus`, `pane.rename` | `result.type: pane_info`, payload `result.pane`. |
| `pane.resize` | `result.type: pane_resize`, payload `result.resize`. |
| `pane.zoom` | `result.type: pane_zoom`, payload `result.zoom`; toggled twice on the owned pane. |
| `pane.close` | `result.type: ok`; closed only the owned split child. |
| `plugin.action.list` | `result.type: plugin_action_list`, payload `result.actions`. |

The CLI read also printed the owned pane's marker with
`herdr pane read w28:p1A --source visible --format ansi`.
`agent.prompt` and `plugin.action.invoke` received schema comparison only, as authorized.
Their complete request and result shapes did not change. No agent or plugin action was invoked.

The probe closed tabs `w28:tC` and `w28:tD`, and workspace `w2F` with its tabs. The final
`herdr api snapshot` capture, `C:/tmp/proto22/snapshot-after.json`, contains no `proto22-probe`
label. The probe did not stop or restart the Herdr server.

**R-02-028**: Protocol `22` is a compatible increment for every call this repository makes.
No call requires a client shape change. The Host and Device protocol checks now target `22`.
The relay protocol remains `1`.

### Bridge verification

The isolated Rust run passed 249 tests, with one ignored test. Clippy passed with `-D warnings`.
The eight changed Dart files passed analysis with fatal infos and warnings. Their four test files
passed 45 tests. The isolated bridge build passed. The foreground command
`timeout 10 C:/tmp/herdr-host-verify-target/debug/herdr-relay.exe` ran for 10.07 seconds and
exited with timeout status `124`. It did not exit before the timeout. Standard error was empty.
Standard output contained only these two lines:

```text
herdr-relay: 7 paired device registration(s) started
herdr-relay: bridge started
```

There was no third standard-output line. `bridge started` confirms that the bridge passed the ping check.
The run did not replace the installed bridge or start the scheduled task.

## R-02-029 A typed character moves no `revision` and emits no event, 2026-09-11

Measured against Herdr `0.9.0-preview.2026-09-08-62431dbd033b` (protocol 22) on Windows 11, pane
`w28:p1H`, a fresh PowerShell pane at its prompt, created and closed by the probe.

A subscription to `pane.updated` was held open while `herdr pane send-text` sent one character at a
time. In 1.5 s after each of four characters, **zero** `pane_updated` events arrived for the pane,
although the prompt line repainted with the character each time. A keystroke echo is therefore
invisible to the event path of `docs/10-herdr-integration.md` R-10-029; only the R-10-070 poll
carries it.

On the workstation itself, the same probe timed the keystroke to the repainted prompt as read by
`pane.read`: eight samples, **129 to 185 ms, median 131 ms**, with about 72 ms of that being one
CLI read call. The shell's own redraw through Herdr's PTY is the floor under every remote echo.

Through the phone, timed from `send_input` dispatch to `pane_frame` receipt in the app, with the
Device applying each frame in 0 to 5 ms:

| Bridge schedule                             | Samples | Median | Min | Max |
| ------------------------------------------- | ------- | ------ | --- | --- |
| Trailing 120 ms window, 250 ms poll         | 6       | 283 ms | 138 | 436 |
| Leading-edge window, 125 ms poll            | 10      | 230 ms | 133 | 322 |

**R-02-029**: A design that reasons about keystroke echo latency MUST start from these two facts:
the event path never fires for a typed character on a shell pane, and the shell's own repaint is
about 130 ms before any transport. `docs/10-herdr-integration.md` R-10-070 owns the poll period
this measurement set; `docs/21-terminal-rendering.md` R-21-021 owns the Device's feed-on-arrival.

## R-02-030 A `pane.read` frame carries no cursor position, 2026-09-11

Measured against Herdr `0.9.0-preview.2026-09-08-62431dbd033b` (protocol 22) on Windows 11, pane
`w28:pW`, an agent TUI (`omp`) with its input line about 40 rows above its status line.

`herdr pane read w28:pW --source visible --format ansi` returned 85 rows and 43 931 bytes. The
text held **zero** `CSI ... H` or `CSI ... f` cursor-position sequences and **zero**
`CSI ?25 h/l` cursor-visibility sequences. `PaneReadResult` has the fields `pane_id`,
`workspace_id`, `tab_id`, `source`, `format`, `text`, `revision` and `truncated`, and no cursor
field. The `cursor` members in the schema belong to `PaneTextPoint` for copy and search, not to
the terminal cursor. The pane object of `session.snapshot` has no cursor field either.

So after an emulator feeds a frame, its cursor rests wherever the last byte left it: the end of
the **last non-blank row**. On the probed pane that row was the TUI's status line, while the real
cursor sat on the input line 40 rows above. On a plain shell pane the two coincide only because
the prompt is the last non-blank row.

**R-02-030**: A design that needs the position of the Host's cursor MUST NOT read it from the
emulator after a frame feed and MUST NOT assume the last non-blank row. The frame does not carry
it. `docs/21-terminal-rendering.md` R-21-043 owns the Device's anchor for predictive local echo,
which derives the input position from frame content instead.

## R-02-031 `done` is ready-and-unseen, `agent.focus` marks seen with no status event, 2026-09-11

Measured against Herdr `0.9.0-preview.2026-09-08-62431dbd033b` (protocol 22) on Windows 11, pane
`w28:p1R`, an `omp` agent pane the probe created, prompted and closed itself.

Herdr's own skill text (`herdr --skill`) states the model: "`idle` and `done` both mean the agent is
ready for input. The CLI/API uses the server's seen state to distinguish them; explicit focus
commands mark the target seen, while reads do not." The probe confirmed it four times:

- After a prompt finished, `session.snapshot` reported `agent_status: "done"`.
- `agent.focus {target}` returned `agent_info` with `agent_status: "idle"` at once, and
  `state_change_seq` did not move (`157` before and after). Seen is not a state change.
- On a subscription to `pane.agent_status_changed`, `pane.updated`, `pane.focused` and
  `layout.updated`, the flip emitted **no** `pane_agent_status_changed` and **no** `pane_updated`.
  The only event was `pane_focused` with the flat payload
  `{"pane_id","workspace_id","type":"pane_focused"}`.
- While the pane stayed focused, a later completion never showed `done`: it went straight to
  `idle`. Focus is the seen mechanism, and a focused pane is seen continuously.
- `pane.focus {pane_id}` answered `pane_not_found` for the same live pane id, so `agent.focus` is
  the call that marks seen. `pane.read` did not change the status.

**R-02-031**: A design that shows or clears "needs attention" for a `done` agent MUST treat the
server's seen state as the truth, MUST use `agent.focus` to set it, and MUST learn of a change
through `pane.focused` followed by a fresh read, because no status event carries it.
`docs/11-relay-protocol.md` owns the wire message and the snapshot-follow rule;
`docs/10-herdr-integration.md` R-10-072 owns the Host call; `docs/03-product-decisions.md`
R-03-125 owns the product meaning.

## Consequences for the design

1. The bridge holds one long-lived subscription connection and opens a short-lived connection per
   request. This is not optional; it follows from R-02-004 and R-02-006.
2. Change detection is free. The event already carries `revision`, so a read happens only when the
   revision of a **watched** pane moves. Exception for agent panes, whose revision can freeze while
   the pane repaints: R-02-026.
3. The Device subscribes to one pane at a time. The bridge filters, because the server will not.
4. Frames are compressed on the wire. An 8 KB ANSI viewport becomes about 1.5 KB.
5. A cell-level diff is not needed for the first version. Compression plus revision-gating already
   removes most of the cost.

## Reproducing these probes

The probe client is about 20 lines of Bun. One request per connection, read one line, close:

```js
const net = require('net');
const PIPE = '\\\\.\\pipe\\C:\\Users\\<user>\\AppData\\Roaming\\herdr\\herdr.sock';

function once(method, params = {}) {
  return new Promise((resolve) => {
    const sock = net.connect({ path: PIPE });
    let buf = '';
    sock.on('connect', () => sock.write(JSON.stringify({ id: 'q', method, params }) + '\n'));
    sock.on('data', (d) => {
      buf += d.toString('utf8');
      const i = buf.indexOf('\n');
      if (i >= 0) { sock.destroy(); resolve(JSON.parse(buf.slice(0, i))); }
    });
    sock.on('error', () => resolve(null));
    setTimeout(() => { sock.destroy(); resolve(null); }, 8000);
  });
}

const snap = (await once('session.snapshot')).result.snapshot;
const r = await once('pane.read', {
  pane_id: snap.panes[0].pane_id, source: 'visible', format: 'ansi', strip_ansi: false,
});
console.log(r.result.read.text);
```

R-02-026 used the same client, with two snapshots 5 s apart around two reads of one agent pane:

```js
const pane = '<pane-id>'; // an agent pane; `herdr api snapshot` lists them
const read = () =>
  once('pane.read', { pane_id: pane, source: 'visible', format: 'ansi' })
    .then((r) => r.result.read.text);
const at = (s) => s.result.snapshot.panes.find((p) => p.pane_id === pane);
const a = at(await once('session.snapshot'));
const t1 = await read();
await new Promise((r) => setTimeout(r, 5000));
const b = at(await once('session.snapshot'));
const t2 = await read();
console.log('revision', a.revision, '->', b.revision, 'text changed:', t1 !== t2);
```

The CLI shows the same two halves (`jq` selects the pane; the read prints raw bytes):

```text
herdr api snapshot | jq '.result.snapshot.panes[] | select(.pane_id == "<pane-id>") | .revision'
herdr pane read <pane-id> --source visible --format ansi | sha256sum
```

## Sources

- Live Herdr server on this machine, protocol 21, probed with Node `net.connect({ path })`.
  Measured 2026-09-02 against Herdr `0.8.2-preview.2026-08-31-b1ff4582e968`, superseding the
  2026-08-27 measurement against Herdr `0.8.2-preview.2026-08-19-b5c4a0176e91`, protocol 20, and
  the original 2026-08-04 measurement against Herdr `0.8.0-preview.2026-08-04-d78e3d3b5126`,
  protocol 19 (both superseded probes used Bun `net`).
- `herdr status`, `herdr api schema`, `herdr api snapshot`.
- `herdr api schema --json` (runtime, schema is never a committed file)
- `[System.IO.Directory]::GetFiles('\\.\pipe\')` for the named pipe enumeration.
