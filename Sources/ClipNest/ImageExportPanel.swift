import AppKit
import UniformTypeIdentifiers

@MainActor
enum ImageExportPanel {
  static func chooseDestination(for item: ClipItem) -> URL? {
    let panel = NSSavePanel()
    panel.title = L10n.text("image_export.title", fallback: "Export Image")
    panel.message = L10n.text(
      "image_export.message",
      fallback: "Save a decrypted copy outside ClipNest’s protected storage."
    )
    panel.prompt = L10n.text("image_export.save", fallback: "Export")
    panel.allowedContentTypes = [item.isGIF ? .gif : .png]
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false
    panel.nameFieldStringValue = item.suggestedImageExportFileName
    guard panel.runModal() == .OK else { return nil }
    return panel.url
  }
}
