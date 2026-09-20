# Clipskein brand and assets

Clipskein is a local reference workbench: find saved material, arrange it for a project, and reuse it while working. The short product line is **Find. Arrange. Reuse.** / **找回资料，组合使用。**

## Mark

The mark is drawn in code: three ivory index tracks on a plum tile, with a pale-green retrieval marker. It uses flat geometry, transparent outer corners, and no external illustration, stock icon, font, or image input.

The authoritative geometry and colors are in [`ClipskeinMarkArtwork`](../Sources/ClipNest/ClipskeinMark.swift). The in-app `ClipskeinMark` view and packaged SVG, PNG, and ICNS assets share that source. The mark and generated assets are covered by the repository's [MIT license](../LICENSE).

Use the complete square mark at its original aspect ratio. Do not add shadows, gradients, a wordmark inside the tile, or additional detail to the small icon. Adjacent text provides the product name; decorative copies inside the interface are hidden from accessibility to avoid reading the name twice.

## Interface palette

| Role | Light surface | Dark surface |
| --- | --- | --- |
| Primary action | Plum `#70466F` | Pale plum `#D4ADD7` |
| Strong brand text | Deep plum `#442B48` | Native adaptive label |
| Canvas | Paper `#F4F1F6` | `#241F28` |
| Secondary accent | Green `#39796B` | Pale green `#A4D0BD` |

[`BrandTheme.swift`](../Sources/ClipNest/BrandTheme.swift) owns semantic UI colors. Body text uses native system labels and system typography. Destructive, caution, and success states keep their semantic colors rather than adopting the brand palette. The Quick Picker remains a deliberately dark, compact keyboard surface; the main library follows the system appearance.

## Regenerate assets

From the repository root on macOS with Xcode selected:

```bash
mkdir -p .build/brand-assets
swiftc -parse-as-library Sources/ClipNest/ClipskeinMark.swift \
  Packaging/render-brand-assets.swift -o .build/brand-assets/render
.build/brand-assets/render Packaging
swift Packaging/make-icns.swift Packaging/AppIcon.iconset Packaging/AppIcon.icns
```

This updates `AppIcon.svg`, `AppIcon-Master.png`, the ten PNGs in `AppIcon.iconset`, and `AppIcon.icns`. The generator does not launch the application or access clipboard data. Normal app builds package a fresh ICNS from the checked-in iconset into `.build`, without modifying source assets.

## Development history

The application used the working name ClipNest and a generated illustration before the Clipskein rebrand on 2026-09-20. That earlier image and its prompt remain in Git history; neither is the source of the current geometric artwork. Internal module and persistence identifiers retain the old name for compatibility, as described in the [upgrade notes](../docs/BUILDING.md#upgrade-an-existing-clipnest-installation).
