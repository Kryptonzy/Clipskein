# Commercial access safety contract

Commercial access is intentionally dormant in ordinary and ad-hoc Clipskein builds. The app must
remain fully usable and must not create a trial record, display a purchase prompt, or contact a
licensing service until the release owner selects a provider and supplies a real production
configuration.

## Provider-neutral product states

- `unmanaged`: licensing is disabled; current local builds always use this state.
- `trial`: a bounded evaluation created only after commercial access is enabled.
- `licensed`: the provider entitlement was verified and is still fresh.
- `offlineGrace`: the last verified entitlement is stale, but the user can keep working briefly.
- `needsOnlineVerification`: time moved backward suspiciously or the offline window ended.
- `expired`: the trial ended or a verified entitlement was revoked.

The pure evaluator is independent from checkout and networking. Provider adapters may supply only
an already verified entitlement. They must never make an unverified API response authoritative.

Commercial access can be evaluated only with a complete `CommercialReleaseConfiguration`; there is
no standalone Boolean production switch. The configuration validates non-empty provider and product
identifiers, hosted HTTPS URLs without embedded credentials, a support email, and a 1–10 device
allowance. Omitting the configuration always produces `unmanaged`, even if a commercial record is
already present. This keeps partial release setup fail-open for existing users instead of accidentally
locking them out.

## Storage boundary

The commercial record is stored as a device-only generic password item in macOS Keychain. It holds
an installation identifier, trial timestamps, and minimal entitlement metadata. It must not contain
clipboard contents, OCR, filenames, paths, search history, payment-card data, provider API secrets,
or the local history-encryption key.

## Release owner inputs still required

1. Provider choice and an approved live merchant account.
2. One-time product/variant identifier, hosted HTTPS checkout URL, and device allowance.
3. Provider API/webhook design for activation, deactivation, refunds, and disputes.
4. Support email, privacy-policy URL, terms URL, and refund policy.

API secrets and signing private keys belong in server or Keychain-managed release infrastructure,
never in `CommercialReleaseConfiguration`, the app bundle, or the repository. No build flag should
enable commercial access until an end-to-end test purchase, offline launch, device deactivation, and
refund revocation have passed.
