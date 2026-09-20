#!/bin/zsh
set -euo pipefail

fail() {
  print -u2 "Sparkle preflight failed: $1"
  exit 2
}

: ${CODESIGN_IDENTITY:?Set CODESIGN_IDENTITY to a Developer ID Application certificate.}
: ${SPARKLE_FEED_URL:?Set SPARKLE_FEED_URL to the production HTTPS appcast URL.}
: ${SPARKLE_PUBLIC_ED_KEY:?Set SPARKLE_PUBLIC_ED_KEY to the public key printed by Sparkle generate_keys.}
: ${SPARKLE_GENERATE_APPCAST:?Set SPARKLE_GENERATE_APPCAST to the Sparkle generate_appcast executable.}

[[ "$CODESIGN_IDENTITY" != "-" ]] \
  || fail "ad-hoc signing cannot be used for public automatic updates."
[[ "$CODESIGN_IDENTITY" == Developer\ ID\ Application:* ]] \
  || fail "CODESIGN_IDENTITY must be a Developer ID Application certificate."

[[ "$SPARKLE_FEED_URL" =~ '^https://[A-Za-z0-9.-]+(:[0-9]+)?(/[^[:space:]#]*)?$' ]] \
  || fail "SPARKLE_FEED_URL must be a hosted HTTPS URL without credentials, whitespace, or a fragment."
[[ "$SPARKLE_FEED_URL" != *"example.com"* \
  && "$SPARKLE_FEED_URL" != *"example.org"* \
  && "$SPARKLE_FEED_URL" != *"example.net"* \
  && "$SPARKLE_FEED_URL" != *"localhost"* \
  && "$SPARKLE_FEED_URL" != *".invalid"* \
  && "$SPARKLE_FEED_URL" != *"your-domain"* ]] \
  || fail "SPARKLE_FEED_URL must be a real production URL, not a placeholder."
[[ "$SPARKLE_FEED_URL" != *[[:space:]]* ]] \
  || fail "SPARKLE_FEED_URL cannot contain whitespace."

command -v openssl >/dev/null \
  || fail "openssl is required to validate the public update key."

KEY_BYTES=$(
  printf '%s' "$SPARKLE_PUBLIC_ED_KEY" \
    | openssl base64 -d -A 2>/dev/null \
    | wc -c \
    | tr -d '[:space:]'
) || fail "SPARKLE_PUBLIC_ED_KEY is not valid Base64."
[[ "$KEY_BYTES" == "32" ]] \
  || fail "SPARKLE_PUBLIC_ED_KEY must decode to a 32-byte Ed25519 public key."

[[ -x "$SPARKLE_GENERATE_APPCAST" ]] \
  || fail "SPARKLE_GENERATE_APPCAST must point to an executable generate_appcast tool."
[[ "${SPARKLE_GENERATE_APPCAST:t}" == "generate_appcast" ]] \
  || fail "SPARKLE_GENERATE_APPCAST must point to Sparkle's generate_appcast tool."

security find-identity -v -p codesigning \
  | grep -F -- "\"$CODESIGN_IDENTITY\"" >/dev/null \
  || fail "the requested Developer ID Application identity is not available in Keychain."

print "Sparkle input-format and local-identity checks passed."
print "Feed reachability, tool provenance, private-key ownership, and a real update are not verified by this preflight."
print "Feed: $SPARKLE_FEED_URL"
print "Signing identity: $CODESIGN_IDENTITY"
print "Appcast tool: $SPARKLE_GENERATE_APPCAST"
print "Public key: valid 32-byte Ed25519 key (value intentionally not printed)"
