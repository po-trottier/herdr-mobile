# Security

## What is sensitive

The following items are sensitive in this product. Protect them. Do not log them, print them, include
them in an example, paste them into a chat message, or commit them to version control.

| Item | Why it is sensitive |
| --- | --- |
| Terminal content | The developer's own terminal output. Contains source code, secrets, credentials, build output and agent reasoning. |
| Keystrokes | Everything the developer types on the phone, which may include passwords, tokens, API keys and shell commands. |
| Pairing phrases | Six EFF Diceware words. A captured phrase lets an attacker complete the Noise handshake and impersonate a new Device during the 120-second pairing window. |
| Routing handles | 128-bit opaque identifiers in unpadded base64url. Knowing a handle lets an attacker reach the relay's routing table, but Noise still protects the content. |
| Static Noise keys | Curve25519 keypairs that authenticate the Host and the Device on every reconnect. A compromised static key breaks the session permanently and requires unpairing. |
| Tokens | Any session token, correlation token or authentication token that the protocol carries inside the Noise channel. |
| Host file paths | Paths to the Herdr socket, the plugin root, the keyring storage location and the plugin log file. These reveal the workstation layout and the user's file-system structure. |

The sample values in the normative documents (for example
`remedy-tapestry-hubcap-oversleep-jailbird-kinetic`, `n6Loxf94CfyIO6hOxlaHvA`,
`https://relay.example.com`) are examples only and are not real secrets.

## Reporting a vulnerability

Report a security vulnerability through the hosting platform's private security advisory feature. Do
not file a public issue. Do not send a vulnerability report through email.

### GitHub Security Advisory

1. Go to the repository's **Security** tab.
2. Select **Report a vulnerability**.
3. Complete the form. Describe the affected component, the version, the steps to reproduce and the
   observed and expected behaviour.
4. Submit. The advisory is private. The maintainers will respond within the commitment window below.

If the hosting platform changes, the `SECURITY.md` in the repository root will state the current
reporting route.

## Supported versions

This product has no release yet. Once a release exists:

| Version | Status |
| --- | --- |
| Latest `MAJOR.MINOR` release | Supported with security fixes |
| Previous `MAJOR.MINOR` release, within 12 months of the newer release | Supported with critical fixes only |
| All other versions | Not supported |

The relay protocol deprecation policy in `docs/23-public-release.md` R-23-045 governs how long a
protocol version is supported by the relay. The app follows the same window: the latest released app
version talks the current protocol, and the previous protocol is accepted for 12 months.

## What a report must contain

A complete vulnerability report includes:

1. **Affected component.** Which part of the system: the Host plugin (`herdr-relay`), the relay
   (`herdr-relay-hub`), the app, the protocol library (`herdr-relay-proto`), or the pairing URI
   format.
2. **Version.** The exact version numbers of every affected component. If the vulnerability is in the
   relay protocol itself, state the protocol version integer.
3. **Environment.** The operating system, the app platform (Android or iOS), the relay deployment
   method, and any configuration that matters.
4. **Reproduction.** Steps that start from a clean state and produce the vulnerability. Include
   commands, sample inputs and the exact error or behaviour.
5. **Observed behaviour.** What happened: a crash, a leaked secret, a decrypted frame, a bypassed
   authentication check, a denial of service.
6. **Expected behaviour.** What should have happened instead.
7. **Impact.** What an attacker can achieve: read terminal content, inject keystrokes, impersonate a
   Device, deny service, bypass the pairing handshake, or read a key.

## What a report MUST NOT contain

A reporter MUST NOT include in a vulnerability report:

- Real terminal content from any pane.
- A real pairing phrase, even an expired one.
- A real routing handle.
- A real static key, public or private.
- A real Host file path.
- A real device identifier (`device_id`, `host_id`).

Instead, use:

- A synthetic terminal session printed by a script, such as `echo "Hello from test pane"`.
- The sample phrase `remedy-tapestry-hubcap-oversleep-jailbird-kinetic`.
- The sample handle `n6Loxf94CfyIO6hOxlaHvA`.
- A freshly generated test keypair, labelled as such.
- Path placeholders such as `/tmp/test-socket` or `C:\test\herdr-plugin`.
- A freshly generated test UUID, labelled as such.

## Response commitment

| Stage | Time window |
| --- | --- |
| Acknowledgement | Within 72 hours of submission. The maintainer confirms receipt and asks for missing information. |
| Assessment | Within 10 business days. The maintainer determines severity, affected versions, and the fix approach. |
| Fix development | No fixed window. Severity and complexity determine the timeline. The reporter gets an update every 14 days. |
| Disclosure | After the fix is released. The advisory is published. Credit is given to the reporter unless the reporter asks to stay anonymous. |

These windows begin when a complete report is received. An incomplete report resets the clock.

## Scope

This security policy covers:

- The relay protocol as specified in `docs/11-relay-protocol.md`.
- The pairing URI format as specified in `docs/13-security-pairing.md`.
- The Noise handshake pattern and key storage rules in `docs/13-security-pairing.md`.
- The routing handle scheme in `docs/11-relay-protocol.md`.
- The frame envelope and error taxonomy in `docs/11-relay-protocol.md`.
- Design-level cryptographic choices: the cipher suite, the handshake patterns and the fingerprint
  derivation.

This security policy does not cover:

- The security of a user's workstation, Herdr installation, phone or relay server.
- The security of the operating-system keystore or keychain.
- The security of the TLS termination in front of the relay.
- The security of a third-party relay operator's deployment.
- Vulnerabilities in dependencies (`snow`, `tokio-tungstenite`, `axum`, etc.) unless the product's
  use of the dependency creates the vulnerability.
