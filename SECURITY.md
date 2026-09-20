# Security policy

ClipNest handles clipboard history, which may contain sensitive information. Do not post real clipboard contents, archive passwords, encryption keys, or unredacted logs in a public issue.

## Report a vulnerability

Use [GitHub's private vulnerability reporting](https://github.com/Kryptonzy/ClipNest/security/advisories/new) for suspected security problems. Include the affected commit or version, macOS version, reproducible steps using synthetic data, expected versus actual behavior, and potential impact. Keep exploit details private while a fix is being prepared.

Security fixes currently target the latest `main` branch. There are no maintained long-term-support branches or guaranteed response times.

## Security boundaries

- History and stored attachments are encrypted at rest with a key held in macOS Keychain. This does not protect against an attacker controlling an unlocked user session.
- Secret detection is heuristic. App exclusions and privacy rules provide additional controls, not a guarantee that every sensitive item will be recognized.
- Copy, paste, drag, and export intentionally move data outside the encrypted history. Referenced files remain at their original locations.
- Password-encrypted archives need a strong password kept separately from the archive. Losing the password or the history key can make data unrecoverable.
- Source builds are not notarized releases. Signing and distribution checks are described in [RELEASE.md](docs/RELEASE.md).

Automated tests and source review do not constitute an independent security audit.
