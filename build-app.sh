#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
APP_NAME=Clipskein
# Keep the internal Swift executable/resource identities stable across the rename.
EXECUTABLE_NAME=ClipNest
APP_DIR="$SCRIPT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
CACHE_DIR="$SCRIPT_DIR/.build/module-cache"
ICON_PATH="$SCRIPT_DIR/.build/AppIcon.icns"
IDENTITY=${CODESIGN_IDENTITY:--}
# Legacy CLIPNEST_* inputs remain accepted for existing release automation.
BUNDLE_ID=${CLIPSKEIN_BUNDLE_ID:-${CLIPNEST_BUNDLE_ID:-app.clipnest.ClipNest}}
MARKETING_VERSION=${CLIPSKEIN_VERSION:-${CLIPNEST_VERSION:-0.1.0}}
BUILD_NUMBER=${CLIPSKEIN_BUILD_NUMBER:-${CLIPNEST_BUILD_NUMBER:-1}}

if [[ ! "$BUNDLE_ID" =~ '^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$' ]]; then
  print -u2 "CLIPSKEIN_BUNDLE_ID (or legacy CLIPNEST_BUNDLE_ID) must be a reverse-DNS identifier containing only letters, digits, periods, and hyphens."
  exit 2
fi
if [[ ! "$MARKETING_VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  print -u2 "CLIPSKEIN_VERSION (or legacy CLIPNEST_VERSION) must contain three numeric components, for example 1.0.0."
  exit 2
fi
if [[ ! "$BUILD_NUMBER" =~ '^[1-9][0-9]*$' ]]; then
  print -u2 "CLIPSKEIN_BUILD_NUMBER (or legacy CLIPNEST_BUILD_NUMBER) must be a positive integer."
  exit 2
fi

export CLANG_MODULE_CACHE_PATH="$CACHE_DIR"
export SWIFTPM_MODULECACHE_OVERRIDE="$CACHE_DIR"

mkdir -p "$CACHE_DIR" "$SCRIPT_DIR/dist"
cd "$SCRIPT_DIR"

zsh "$SCRIPT_DIR/scripts/check-localizations.sh"
swift build -c release --disable-sandbox
BIN_DIR=$(swift build -c release --show-bin-path --disable-sandbox)

if [[ ! -d "$BIN_DIR/ClipNest_ClipNest.bundle" ]]; then
  print -u2 "SwiftPM localization resource bundle is missing; refusing to package an incomplete app."
  exit 1
fi

swift "$SCRIPT_DIR/Packaging/make-icns.swift" "$SCRIPT_DIR/Packaging/AppIcon.iconset" "$ICON_PATH"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
ditto "$BIN_DIR/$EXECUTABLE_NAME" "$MACOS_DIR/$EXECUTABLE_NAME"
ditto "$BIN_DIR/ClipNest_ClipNest.bundle" "$RESOURCES_DIR/ClipNest_ClipNest.bundle"
ditto "$SCRIPT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
ditto "$ICON_PATH" "$RESOURCES_DIR/AppIcon.icns"
chmod 755 "$MACOS_DIR/$EXECUTABLE_NAME"

/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"

if /usr/libexec/PlistBuddy -c "Print :LSUIElement" "$CONTENTS_DIR/Info.plist" >/dev/null 2>&1; then
  print -u2 "Release Info.plist must not set LSUIElement; SwiftUI needs regular launch policy to create the library window."
  exit 1
fi

if [[ "$IDENTITY" == "-" ]]; then
  print -u2 "warning: creating an ad-hoc signed development build. Its code identity changes after every rebuild, so macOS Keychain may require access approval again."
  print -u2 "warning: use CODESIGN_IDENTITY with a stable Apple Development or Developer ID Application certificate for upgrade testing."
  codesign --force --options runtime --identifier "$BUNDLE_ID" --sign - "$APP_DIR"
else
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --identifier "$BUNDLE_ID" \
    --sign "$IDENTITY" \
    "$APP_DIR"
fi
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
plutil -lint "$CONTENTS_DIR/Info.plist"

echo "$APP_DIR"
