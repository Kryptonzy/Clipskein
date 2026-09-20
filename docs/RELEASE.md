# Signing and public release

Uploading source to GitHub does not require notarization or a commercial service. Publishing a downloadable macOS app is a separate step. The included release script prepares a notarized ZIP; it does not upload a GitHub release or enable billing or automatic updates.

## Signing levels

| Build | Purpose | What it does not establish |
| --- | --- | --- |
| Ad-hoc (`CODESIGN_IDENTITY=-`, default) | Local development | Stable identity across rebuilds, notarization, or public distribution readiness |
| Apple Development | Repeated local development with a stable certificate | Developer ID distribution or notarization readiness |
| Developer ID Application + notarization | Direct distribution outside the Mac App Store | Functional correctness, Intel/universal compatibility, or an update service |

Ad-hoc rebuilds change the code identity and may prompt again for Keychain access or permissions. ClipNest does not weaken Keychain protection to hide those prompts. Never delete a history encryption key as a routine upgrade fix.

## Notarized archive

Before running the release script, install a valid Developer ID Application identity and create a `notarytool` Keychain profile using the release owner's Apple credentials. Keep private keys and credentials out of this repository. Run the automated and manual checks in [BUILDING.md](BUILDING.md) first.

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARYTOOL_PROFILE="clipnest-notary" \
CLIPNEST_VERSION="1.0.0" \
CLIPNEST_BUILD_NUMBER="100" \
zsh release-app.sh
```

The marketing version must contain exactly three numeric components; put beta/release-candidate labels in the release title, not `CFBundleShortVersionString`. Increase the build number for each distributed build. The output matches the build host's architecture unless the build procedure is explicitly extended and verified for other architectures.

The script validates the Developer ID identity and metadata before building, signs with Hardened Runtime and a timestamp, submits a temporary ZIP to Apple, waits for notarization, staples the ticket, validates it, and runs a Gatekeeper assessment. Only after those steps succeed does it create:

- `dist/release/ClipNest-VERSION.zip`
- `dist/release/ClipNest-VERSION.zip.sha256`

Keep release files separate from source commits. Verify the final archive on a clean Mac before announcing a public download. The script does not configure Sparkle; see [AUTOMATIC_UPDATES.md](AUTOMATIC_UPDATES.md). Commercial access also remains dormant until a provider integration is implemented and verified; see [COMMERCIAL_ACCESS.md](COMMERCIAL_ACCESS.md).
