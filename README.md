# ClipNest

A local-first macOS clipboard and screenshot library. Save copied text, images, and file references, recognize screenshot text, and retrieve it from a keyboard-driven picker.

## What it does

- Captures text, validated rich text, images (including original animated GIFs), and file references.
- Runs screenshot OCR and barcode recognition on-device; supports region capture and an opt-in screenshot inbox.
- Offers Quick Picker, typo-tolerant and structured search, snippets, tags, Pinboards, and a multi-clip Stack.
- Extracts receipt fields and exports structured tables; provides local text cleanup and optional Apple translation and AI actions.
- Encrypts history and attachments with a Keychain-protected key; includes per-app exclusions, privacy rules, concealed items, and encrypted backups.
- Includes English and Simplified Chinese interfaces. It has no ClipNest account, telemetry, or cloud sync.

The [feature reference](docs/FEATURES.md) describes the detailed behavior and limits.

## Requirements

The deployment target is macOS 14+. Building requires a full Xcode installation with Swift 6.1 or later and `ripgrep` (`rg`) for the localization check. There are no third-party Swift package dependencies. The default build targets the current Mac's architecture; it is not a universal binary.

| Capability | Availability |
| --- | --- |
| Clipboard library, OCR, search, snippets, encryption | macOS 14+ deployment target |
| Local translation | macOS 15+, supported language pair and downloaded Apple language packs |
| Apple Intelligence actions | macOS 26+, a build using the Foundation Models SDK, and an available on-device Apple Intelligence model |
| Paste into another app | Accessibility permission; otherwise copy and paste manually |
| Screen-region capture | Screen Recording permission when macOS requests it |

The minimum deployment target is not a claim that every OS and hardware combination has been manually tested. Optional model and language downloads are managed by macOS. GIF OCR examines the first frame only; with secret protection enabled, multi-frame GIFs remain concealed because later frames are not scanned. Static GIFs are not labeled as animated.

## Build and run

Clone the repository and build the app:

```bash
git clone https://github.com/Kryptonzy/ClipNest.git
cd ClipNest
zsh build-app.sh
open dist/ClipNest.app
```

This produces an ad-hoc signed local build. Use the app bundle for normal testing; `zsh run.sh` is a development-only SwiftPM launch. Rebuilding with ad-hoc signing can trigger new Keychain or permission prompts. A stable Apple Development identity is useful for repeated local upgrades; public distribution requires Developer ID signing and notarization.

```bash
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" zsh build-app.sh
```

For verification:

```bash
zsh scripts/check-localizations.sh
swift build --build-tests
swift test --skip-build --skip 'maximumHistoryMeaningIndexHasBoundedColdAndWarmLatency|maximumHistoryPersistenceIsCoalescedOffMainAndFlushesLatestSnapshot'
swift test --skip-build --filter maximumHistoryMeaningIndexHasBoundedColdAndWarmLatency
swift test --skip-build --filter maximumHistoryPersistenceIsCoalescedOffMainAndFlushesLatestSnapshot
```

Compile once, then run functional tests and the two performance tests separately so concurrent work does not distort search or persistence latency. CI allows three minutes for functional tests and two minutes for each isolated performance test, excluding compilation. Optional system-embedding integration tests report an explicit skip for each unavailable language; the missing-model fallback test always runs. See [building and verification](docs/BUILDING.md) for environment diagnostics and the manual smoke-test checklist.

## Data and privacy

Live data is stored in `~/Library/Application Support/ClipNest`; the encryption key is stored in macOS Keychain. File clips reference the original files rather than copying their contents. Keep a password-encrypted backup before moving or resetting the application. Do not delete the Keychain key to resolve a prompt: encrypted history needs that key.

Clipboard monitoring necessarily sees content copied by other applications. Configure exclusions and privacy rules in Settings. Automatic secret detection is heuristic and cannot guarantee recognition of every sensitive value. Deliberate copy, paste, drag, and export actions place the selected data outside the encrypted store.

Backup imports merge into the library and still follow your history size and retention limits. Import is not an all-or-nothing transaction across history, attachments, and collections: a failed operation can leave partial changes. Keep the original backup, resolve the reported storage problem, retry saving or importing, and verify the result after relaunch before discarding the backup.

## Project status

ClipNest is an early-stage macOS application available as source. Build locally using the instructions above; there is no notarized app download yet.

Automatic updates are not integrated. Payments, license activation, and trial enforcement are not connected to a provider; ordinary builds remain fully enabled. A successful local signature check does not mean the app is notarized or approved by Gatekeeper for distribution.

- [Build, troubleshooting, and verification](docs/BUILDING.md)
- [Signing and public release procedure](docs/RELEASE.md)
- [Automation links](docs/DEEPLINKS.md)
- [Automatic-update integration requirements](docs/AUTOMATIC_UPDATES.md)
- [Dormant commercial-access design](docs/COMMERCIAL_ACCESS.md)

Source code lives in `Sources/ClipNest`, regression tests in `Tests/ClipNestTests`, and bundle metadata and icon assets in `Packaging`. Build output and local application data should not be committed.

## Contributing and license

See [CONTRIBUTING.md](CONTRIBUTING.md) for bug reports and pull requests, and [SECURITY.md](SECURITY.md) for private vulnerability reports.

Code, documentation, and the included icon assets are distributed under the [MIT license](LICENSE). The icon's generation record is kept in [Packaging/ICON_PROMPT.md](Packaging/ICON_PROMPT.md).
