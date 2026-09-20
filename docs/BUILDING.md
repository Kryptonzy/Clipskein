# Building and verification

Run commands from the `ClipNest` directory. Install a full Xcode with Swift 6.1 or newer and `ripgrep` (`rg`), then inspect the selected toolchain:

```bash
xcode-select -p
xcrun swift --version
xcrun --show-sdk-version
command -v rg
```

If the selected toolchain is not the intended Xcode installation, select it in Xcode's Settings → Locations. A compiler/SDK version mismatch or a missing `SwiftUIMacros` plugin requires a matching Xcode toolchain; installing dependencies in this project cannot repair it.

## Local app bundle

```bash
zsh build-app.sh
open dist/ClipNest.app
```

`build-app.sh` checks localization, compiles an optimized binary, generates the icon, packages resources, signs the bundle, and verifies its signature and plist. It writes `dist/ClipNest.app`. It does not run tests, notarize, publish, or prove runtime compatibility on other Macs. SwiftPM's build sandbox is disabled by this script so the selected local toolchain can build; this is distinct from the app's signing and Hardened Runtime settings.

The default signature is ad-hoc. To preserve a stable signing identity across local upgrades:

```bash
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" zsh build-app.sh
```

Use `security find-identity -v -p codesigning` to inspect locally available identities. Do not share private keys or Keychain passwords. The script also accepts `CLIPNEST_BUNDLE_ID`, `CLIPNEST_VERSION` (`major.minor.patch`), and `CLIPNEST_BUILD_NUMBER` (positive integer). Preserve the bundle identifier and signing identity when testing an upgrade of an existing installation.

`zsh run.sh` invokes the executable through Swift Package Manager for development. It does not create or install an app bundle, so Launch Services, permissions, icons, and app identity should be checked using the packaged app.

## Automated verification

```bash
for script in build-app.sh release-app.sh run.sh scripts/*.sh; do zsh -n "$script" || exit; done
zsh scripts/check-localizations.sh
swift build --build-tests
swift test --skip-build --skip 'maximumHistoryMeaningIndexHasBoundedColdAndWarmLatency|maximumHistoryPersistenceIsCoalescedOffMainAndFlushesLatestSnapshot'
swift test --skip-build --filter maximumHistoryMeaningIndexHasBoundedColdAndWarmLatency
swift test --skip-build --filter maximumHistoryPersistenceIsCoalescedOffMainAndFlushesLatestSnapshot
zsh build-app.sh
codesign --verify --deep --strict --verbose=2 dist/ClipNest.app
plutil -lint dist/ClipNest.app/Contents/Info.plist
```

Compile the application and tests first, then use `--skip-build` for all three test runs. The meaning-search benchmark and the coalesced-persistence benchmark each run alone, keeping their existing latency limits while avoiding interference from the functional suite. In CI, functional tests have a three-minute step timeout and each performance test has a two-minute timeout; compilation has its own preceding step so it does not consume those test limits.

The AppKit integration suite runs serially because its cases share process-level pasteboard services and semantic caches. `@MainActor` alone permits different async tests to interleave. This test isolation does not remove concurrency exercised inside an individual test, and is not a claim that every possible application-level concurrency issue has been ruled out.

English and Simplified Chinese integration tests check Apple's optional word-embedding resources independently. If a language model is absent, its test reports an explicit skip with the language named. When the resource is present, the actual semantic results must still pass. The injected missing-model fallback test always runs and verifies that unavailable models produce an explicit unavailable result with no indexed documents or stale hits. Record both passed and skipped tests, the actual toolchain, host OS, and binary checksum for a release candidate rather than treating previously recorded counts as current evidence.

The localization gate checks valid string-file syntax, duplicate keys, English/Chinese parity, and common hard-coded UI literals. It is a targeted check, not a complete translation or accessibility audit. `codesign --verify` checks signature integrity; it does not replace notarization or a Gatekeeper assessment.

## Manual smoke test before distribution

Use the packaged app in a disposable macOS account or with a backup of existing history. Automated tests cannot grant permissions or prove cross-application behavior.

1. Launch twice and verify only one monitor is active; reopen the library through the Dock and menu bar.
2. Copy text, rich text, a PNG, an animated GIF, and multiple files. Confirm search, duplicate refresh, and paste into suitable destination apps. Confirm GIFs remain concealed under secret protection and single-frame GIFs have no animation label.
3. Capture a region, recognize its text, and exercise screenshot-inbox permission recovery. Check cancellation and a missing source file.
4. Use Quick Picker with Chinese/Japanese/Korean text composition, dismiss it, and try paste-back with Accessibility allowed and denied.
5. Conceal a clip, lock/unlock the Mac, and verify previews and sensitive clipboard actions follow the privacy settings.
6. Create an encrypted backup, restore into a disposable history, relaunch, and confirm text, images, Pinboards, and file references survive. Check the history capacity and retention settings before importing; the merged library still follows those limits. Verify that a locked/unreadable store rejects archive operations and that a save failure reports an error instead of successful import.
7. Upgrade a previously signed build using the same identity. Confirm encrypted history unlocks and existing permissions remain usable.
8. On supported systems, test translation with missing language packs and Apple Intelligence with its model unavailable as well as available.

Local test success is not evidence for untested macOS 14/15 hosts, Intel hardware, or every destination application's clipboard behavior. Keep those as explicit validation gaps until exercised.
