# Secure automatic updates

Sparkle is not integrated in this source tree: there is no updater dependency, feed, or working Check for Updates command. The following is the design and release checklist for a future integration. A public updater must not ship with a placeholder feed, an ad-hoc signature, disabled Library Validation, or an update key generated outside the release owner's Keychain.

## Inputs the release owner supplies

1. A final HTTPS URL for `appcast.xml` on a domain or release host the owner controls.
2. A `Developer ID Application` certificate plus an existing `notarytool` Keychain profile.
3. The public key printed by Sparkle's `generate_keys` tool. Keep the private key in Keychain; never send it to a collaborator or commit it to this repository.
4. The local path to Sparkle's `generate_appcast` executable after the current Sparkle release is downloaded.

Run the non-destructive preflight before integrating or publishing the updater:

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
SPARKLE_FEED_URL="https://updates.your-domain.tld/clipnest/appcast.xml" \
SPARKLE_PUBLIC_ED_KEY="PUBLIC_KEY_FROM_GENERATE_KEYS" \
SPARKLE_GENERATE_APPCAST="/path/to/Sparkle/bin/generate_appcast" \
zsh scripts/check-sparkle-prerequisites.sh
```

The command checks input formats and the local signing identity without printing the public-key value. It never reads or exports the private key. It does not verify feed reachability, the appcast tool's provenance, ownership of the corresponding private key, notarization credentials, or a successful real update.

## Integration acceptance criteria

- Pin the current stable Sparkle version in Swift Package Manager.
- Embed the signed `Sparkle.framework` with symlinks and permissions intact.
- Keep Hardened Runtime and Library Validation enabled in public builds.
- Configure `SUFeedURL`, `SUPublicEDKey`, `SURequireSignedFeed`, and update verification in the signed app bundle.
- Expose a native Check for Updates command and an understandable background-update preference.
- Generate the appcast only from the notarized, stapled release archive.
- Sign every update archive with the Keychain-held EdDSA key and publish the archive before the appcast.
- Verify a real upgrade from the previous notarized build, including relaunch and rollback-safe failure behavior.
- Keep local ad-hoc builds usable without pretending automatic updates are configured.

The private update key and notarization credentials must remain in Keychain. They are not repository inputs.
