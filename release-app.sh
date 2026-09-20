#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
APP_NAME=Clipskein
APP_DIR="$SCRIPT_DIR/dist/$APP_NAME.app"
RELEASE_DIR="$SCRIPT_DIR/dist/release"

: ${CODESIGN_IDENTITY:?Set CODESIGN_IDENTITY to a Developer ID Application certificate.}
: ${NOTARYTOOL_PROFILE:?Set NOTARYTOOL_PROFILE to a notarytool keychain profile.}
# Prefer the new names while retaining existing release automation inputs.
MARKETING_VERSION=${CLIPSKEIN_VERSION:-${CLIPNEST_VERSION:-}}
BUILD_NUMBER=${CLIPSKEIN_BUILD_NUMBER:-${CLIPNEST_BUILD_NUMBER:-}}
: ${MARKETING_VERSION:?Set CLIPSKEIN_VERSION (or legacy CLIPNEST_VERSION), for example 1.0.0.}
: ${BUILD_NUMBER:?Set CLIPSKEIN_BUILD_NUMBER (or legacy CLIPNEST_BUILD_NUMBER) to a positive integer.}

if [[ "$CODESIGN_IDENTITY" != Developer\ ID\ Application:* ]]; then
  print -u2 "release-app.sh requires the full name of a Developer ID Application certificate; ad-hoc and Apple Development signing are not distribution identities."
  exit 2
fi
if [[ ! "$MARKETING_VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  print -u2 "CLIPSKEIN_VERSION (or legacy CLIPNEST_VERSION) must contain three numeric components, for example 1.0.0. Use release titles for beta labels."
  exit 2
fi
if [[ ! "$BUILD_NUMBER" =~ '^[1-9][0-9]*$' ]]; then
  print -u2 "CLIPSKEIN_BUILD_NUMBER (or legacy CLIPNEST_BUILD_NUMBER) must be a positive integer."
  exit 2
fi

command -v xcrun >/dev/null
command -v ditto >/dev/null
command -v codesign >/dev/null
command -v spctl >/dev/null
command -v rg >/dev/null
command -v security >/dev/null

if ! security find-identity -v -p codesigning | rg -F -- "\"$CODESIGN_IDENTITY\"" >/dev/null; then
  print -u2 "The requested Developer ID Application identity is not available in Keychain."
  exit 2
fi

export CODESIGN_IDENTITY NOTARYTOOL_PROFILE
export CLIPSKEIN_VERSION="$MARKETING_VERSION" CLIPSKEIN_BUILD_NUMBER="$BUILD_NUMBER"
zsh "$SCRIPT_DIR/build-app.sh"

mkdir -p "$RELEASE_DIR"
UPLOAD_ZIP="$RELEASE_DIR/$APP_NAME-$MARKETING_VERSION-notarization.zip"
FINAL_ZIP="$RELEASE_DIR/$APP_NAME-$MARKETING_VERSION.zip"
CHECKSUM_FILE="$FINAL_ZIP.sha256"
rm -f "$UPLOAD_ZIP" "$FINAL_ZIP" "$CHECKSUM_FILE"

ditto -c -k --keepParent "$APP_DIR" "$UPLOAD_ZIP"
xcrun notarytool submit "$UPLOAD_ZIP" \
  --keychain-profile "$NOTARYTOOL_PROFILE" \
  --wait

xcrun stapler staple "$APP_DIR"
xcrun stapler validate "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
spctl --assess --type execute --verbose=4 "$APP_DIR"

ditto -c -k --keepParent "$APP_DIR" "$FINAL_ZIP"
shasum -a 256 "$FINAL_ZIP" > "$CHECKSUM_FILE"
rm -f "$UPLOAD_ZIP"

print "$FINAL_ZIP"
print "$CHECKSUM_FILE"
