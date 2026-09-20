# Safe automation links

Clipskein registers the `clipskein://` URL scheme so Shortcuts, Raycast, browsers, shell scripts,
and other local automation can navigate the app without receiving clipboard data or silently
triggering a paste.

New links use `clipskein://`. Existing `clipnest://` links remain supported with the same commands
and validation rules, so saved shortcuts do not need to be rewritten immediately.

Supported links:

- `clipskein://open` — show the main library.
- `clipskein://search?q=invoice%20total` — show the library and search for the decoded query.
- `clipskein://picker` — open Quick Picker.
- `clipskein://picker?q=%23work` — open Quick Picker with an initial query.
- `clipskein://new` — open a blank reusable-snippet draft.
- `clipskein://snippets` — open the snippet and `@alias` picker.
- `clipskein://actions` — open Text Actions.
- `clipskein://board?name=Launch%20Kit` — open an existing Pinboard by name.

Settings → Automation includes ready-to-copy examples, a safe custom search-link
builder, and a menu that generates links for existing Pinboards. Clipskein performs the query and
Pinboard-name encoding, then marks those copies as app-generated so they do not re-enter clipboard
history.

Search and picker queries are limited to 500 characters. Pinboard names use the same 32-character
limit as the app. Unknown commands, duplicate parameters, credentials, ports, fragments, extra
paths, and unexpected parameters are rejected.

Deep links deliberately cannot return history, create clips from URL content, copy, paste, delete,
export, change privacy settings, or reveal concealed items. Automation that needs to provide a
query must percent-encode it as a URL query value.
