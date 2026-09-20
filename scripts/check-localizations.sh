#!/bin/zsh
set -euo pipefail

# A missing rg must not turn the UI-literal checks below into an empty successful scan.
if ! command -v rg >/dev/null; then
  print -u2 "Localization checks require ripgrep (rg). Install it before building."
  exit 2
fi
export LC_ALL=C

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
ENGLISH="$PROJECT_DIR/Sources/ClipNest/Resources/en.lproj/Localizable.strings"
CHINESE="$PROJECT_DIR/Sources/ClipNest/Resources/zh-Hans.lproj/Localizable.strings"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

plutil -lint "$ENGLISH" "$CHINESE"

extract_keys() {
  awk -F'"' '/^"/{print $2}' "$1" | sort
}

extract_keys "$ENGLISH" > "$TEMP_DIR/en.keys"
extract_keys "$CHINESE" > "$TEMP_DIR/zh.keys"

for language in en zh; do
  duplicates=$(uniq -d "$TEMP_DIR/$language.keys")
  if [[ -n "$duplicates" ]]; then
    print -u2 "Duplicate localization keys in $language:"
    print -u2 "$duplicates"
    exit 1
  fi
done

missing_chinese=$(comm -23 "$TEMP_DIR/en.keys" "$TEMP_DIR/zh.keys")
missing_english=$(comm -13 "$TEMP_DIR/en.keys" "$TEMP_DIR/zh.keys")
if [[ -n "$missing_chinese" || -n "$missing_english" ]]; then
  if [[ -n "$missing_chinese" ]]; then
    print -u2 "Keys missing from Simplified Chinese:"
    print -u2 "$missing_chinese"
  fi
  if [[ -n "$missing_english" ]]; then
    print -u2 "Keys missing from English:"
    print -u2 "$missing_english"
  fi
  exit 1
fi

# User-facing transient notices are easy to miss because Swift string literals compile
# without going through the localization catalog. Keep this release gate narrow: it only
# rejects a literal passed directly to the two notice entry points, while allowing keys,
# formatted strings, and previously localized variables.
hardcoded_notices=$(
  rg -U -n '(showNotice|reportNotice)\(\s*\n?\s*"[^"\n]+' \
    "$PROJECT_DIR/Sources/ClipNest" --glob '*.swift' || true
)
if [[ -n "$hardcoded_notices" ]]; then
  print -u2 "Hard-coded user-facing notices must use L10n:"
  print -u2 "$hardcoded_notices"
  exit 1
fi

# Catch the most common SwiftUI regressions as well. A small explicit allowlist covers brand names,
# keyboard glyphs, and search-syntax examples that must remain language-independent.
hardcoded_controls=$(
  {
    rg -n '(^|[^[:alnum:]_])(Text|Button|Label)\("[A-Za-z][^"\n]*"' \
      "$PROJECT_DIR/Sources/ClipNest" --glob '*.swift' || true
    rg -U -n 'BoardEditorView\(\s*title:\s*"[A-Za-z][^"\n]*"' \
      "$PROJECT_DIR/Sources/ClipNest" --glob '*.swift' || true
    rg -n '(navigationTitle|confirmationDialog|alert|help|accessibilityLabel)\("[A-Za-z][^"\n]*"' \
      "$PROJECT_DIR/Sources/ClipNest" --glob '*.swift' || true
  } | rg -v 'Text\("(CLIPSKEIN|Clipskein|ESC|regex:|app:Safari|after:2026-09-01|before:2026-10-01)"\)|accessibilityLabel\("Clipskein"\)' || true
)
if [[ -n "$hardcoded_controls" ]]; then
  print -u2 "Hard-coded SwiftUI labels and presentation copy must use L10n:"
  print -u2 "$hardcoded_controls"
  exit 1
fi

print "Localization parity verified: $(wc -l < "$TEMP_DIR/en.keys" | tr -d ' ') keys per language."
