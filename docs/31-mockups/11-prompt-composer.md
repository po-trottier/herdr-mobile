# 11 - Agent prompt composer (retired)

| Field | Value |
| --- | --- |
| Route | none since 2026-09-09; was `/hosts/:hostId/agents/:agentId/prompt` |
| Surface | none; was Device, Android and iOS |
| Spec | `docs/30-ux-spec.md` |

This screen is retired. `R-03-101` (decided 2026-09-09 by the product owner) removes the prompt
composer from the product: the live terminal of `R-03-054` is the prompt, so a person types to the
agent in the pane, and the `Send a prompt to <agent>` row that opened this screen left the pane
action sheet of `10-pane-actions.md` the same day. The app holds no composer screen, no composer
service, no draft store and no `RECENT` list; `agent_prompt` and `agent_prompt_ack` stay in the
protocol of `docs/11-relay-protocol.md`, which owns them, and no screen sends them. This file stays
as the permanent record of the rule ids `R-31-11-01` to `R-31-11-14`, so that no later rule reuses
one of them. Every wireframe, callout and state it once held is gone with the screen.

## Retired rules

| Rule | Why |
| --- | --- |
| `R-31-11-01` | **Retired 2026-09-09 per `R-03-101`.** Enter inserted a newline and only the confirming action sent. There is no field: on the terminal the return key is `Enter` to the pane, per `R-03-054` and `R-31-09-04`. |
| `R-31-11-02` | **Retired 2026-09-09 per `R-03-101`.** The per-agent draft in `flutter_secure_storage`. There is no draft: a keystroke reaches the pane as it is typed, per `R-03-054`, so nothing unsent exists to keep. The draft bullet of `R-30-949` is retired with it. |
| `R-31-11-03` | **Retired 2026-09-09 per `R-03-101`.** One `agent_prompt` with `target` and `text`. No screen sends `agent_prompt`; the protocol keeps the message, per `docs/11-relay-protocol.md` section 4.14. `agentId` as the `pane_id` of the agent's pane was this rule's normative half; no route carries `:agentId` any more. |
| `R-31-11-04` | **Retired 2026-09-09 per `R-03-101`.** Autocorrect, autocapitalisation and predictive text off in the field. `R-31-09-06` keeps the same guarantee on the keyboard the grid raises. |
| `R-31-11-05` | **Retired 2026-09-09 per `R-03-101`.** Route to the agent's pane after a successful send. The person is already on the pane. |
| `R-31-11-06` | **Retired 2026-09-09 per `R-03-101`.** The five-entry in-memory `RECENT` list. |
| `R-31-11-07` | **Retired 2026-09-09 per `R-03-101`.** Reachable from any paired phone. `R-03-051` still grants full control; there is no route to reach. |
| `R-31-11-08` | **Retired 2026-09-09 per `R-03-101`.** `agent_prompt_stalled` without a one-tap resend. No screen sends a prompt through the API. |
| `R-31-11-09` | **Retired 2026-09-09 per `R-03-101`.** A switch to another computer closed the route without asking. `R-30-949` still clears every `:hostId` route. |
| `R-31-11-10` | **Retired 2026-09-09 per `R-03-101`.** The keyboard-bound layout and the symbol row of the composer. `09-key-row.md` keeps the symbol banks of the terminal. |
| `R-31-11-11` | **Retired 2026-09-09 per `R-03-101`.** The outcome-unknown reconciliation against `status` and `status_at`. `R-30-518` keeps the general rule for the actions that remain. |
| `R-31-11-12` | **Retired 2026-09-09 per `R-03-101`.** `RECENT` present only while the field was empty. |
| `R-31-11-13` | **Retired 2026-09-09 per `R-03-101`.** The compose surface and its two actions from `R-33-075`. `R-33-075` stays the rule for a compose task; no screen is one today. |
| `R-31-11-14` | **Retired 2026-09-09 per `R-03-101`.** The context line named the workspace, the tab and the pane. The terminal app bar names the tab and the pane, per `08-terminal.md` callout 2. |

## Accessibility

Retired with the screen. `R-30-024` requires this section on every mockup file; a retired screen has
no touch target, contrast, screen reader label or focus order to cite.

## Open questions

None.

## Sources

- `docs/03-product-decisions.md` - `R-03-101`, which retires this screen, and `R-03-054`, the live
  terminal that is the prompt.
- `docs/31-mockups/10-pane-actions.md` - the sheet that held the entry to this screen, and its
  `## Retired rules` note on the `Send a prompt to <agent>` row.
- `docs/11-relay-protocol.md` - `agent_prompt` in section 4.14 and `agent_prompt_ack` in section
  4.15, which stay in the protocol with no sender in the app.
