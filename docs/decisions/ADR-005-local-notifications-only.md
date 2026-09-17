# ADR-005: Version 1 uses native local notifications only, no push infrastructure

## Status

Amended 2026-09-16 by the product owner.

`docs/03-product-decisions.md` R-03-136 permits fixed-text APNs and FCM wake alerts.
This amendment replaces the push prohibition below. Detailed agent notifications remain local
and use encrypted `agent_status` events. Push carries no agent, pane, tab, workspace, or terminal
content. Background delivery remains best effort. The app shows current attention state after
normal launch or resume. The original decision and its reasons remain below as historical context.

## Date

2026-08-24

## Context

The earlier design used a contentless APNs or FCM push to wake the app. On wake the app would open a
Noise session to the Host (via the relay) and fetch the detail.

That design would have added, for a version 1 product:

- An Apple Push Notification service project (APNs key, provider, topic registration).
- A Google Firebase Cloud Messaging project (FCM server key, sender ID).
- A push gateway that the operator must run, secure and monitor.
- A push token per Device that the Host or the gateway must persistently store.
- A new metadata channel through a third party (Apple or Google) for a product whose entire premise
  is that no third party learns anything about the user's terminal sessions.

The contentless wake model also meant the app received a push, opened a WebSocket, performed a Noise
handshake, waited for `host_info` and `device_info`, then waited for an `agent_status` message — a
chain that can take seconds over a mobile network and can fail at any link.

## Decision

Version 1 raises a native local notification only while the app process is alive. The notification
carries the agent status detail directly; no fetch follows.

No APNs. No FCM. No push gateway. No push tokens. No contentless wake. No background-delivery
guarantee.

The data path is simple: Herdr emits `pane.agent_status_changed` → the Host plugin forwards an
encrypted `agent_status` application message through the relay → the app decrypts it, raises a local
notification, and a tap routes to the matching Host and pane.

The `agent_status` message format and the notification tap route are owned by
`docs/11-relay-protocol.md`. The product-level notification policy is owned by
`docs/03-product-decisions.md`. The platform-specific local-notification implementation is owned by
`docs/22-platform-integration.md`.

## Consequences

The app needs no push project, no push certificate lifecycle, no push gateway deployment guide and
no push-token storage. The operator deploys one container (the relay) instead of two (relay plus
push gateway).

The limitation, stated without softening: if the operating system suspended or terminated the app,
the user learns about a finished agent when they next open the app. There is no wake, no silent
delivery and no lock-screen notification for a killed app.

This is a real product limitation. It is disclosed in the onboarding flow and in the public store
description. It is never called push notification support, and the store copy never uses the word
"push."

The app shows unseen attention state in-app on reconnect, ordered by the `at` timestamp in
`agent_status`. The app never synthesises a system notification for a stale event. A notification
for an event the user already saw is confusing and is avoided.

This decision would be revisited when at least two of three conditions are met:

1. User feedback names missed notifications as the top reason for abandoning the product.
2. The relay and the pairing flow are stable enough that adding a push gateway is the next priority,
   not a distraction.
3. A push gateway design exists that does not weaken the no-third-party premise, for example a
   relay-hosted polling wake or an on-device workaround that does not route metadata through Apple or
   Google.
