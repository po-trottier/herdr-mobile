# Relay push credentials

Provider credentials for the push wake (`docs/14-relay-deployment.md` R-14-017). Never committed:
`.gitignore` excludes everything here except this file. The compose file mounts this directory
read-only at `/run/secrets` and reads two fixed names:

| File | Content |
| --- | --- |
| `apns.p8` | The APNs auth key from the Apple Developer portal |
| `firebase-service-account.json` | The Firebase service account with the Cloud Messaging role |

With a GitOps deployment, this directory is created on the host by the operator, not by the sync.
