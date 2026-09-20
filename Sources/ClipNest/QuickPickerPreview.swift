import AppKit
import SwiftUI

struct QuickPickerPreviewPayload: Identifiable, Equatable {
  enum Content: Equatable {
    case text(String)
    case image(Data, recognizedText: String)
  }

  nonisolated static let maximumTextCharacters = 100_000
  nonisolated static let maximumRecognizedTextCharacters = 20_000

  let id: UUID
  let title: String
  let sourceApplication: String
  let createdAt: Date
  let content: Content
  let isTruncated: Bool

  init?(item: ClipItem, imageData: Data? = nil, decodedImage: NSImage? = nil) {
    guard !item.isConcealed else { return nil }
    id = item.id
    title = item.localizedDisplayTitle()
    sourceApplication = item.localizedSourceApplication()
    createdAt = item.createdAt

    switch item.kind {
    case .text:
      let bounded = Self.bounded(item.text, limit: Self.maximumTextCharacters)
      content = .text(bounded.value)
      isTruncated = bounded.isTruncated
    case .image:
      guard let imageData, decodedImage != nil || NSImage(data: imageData) != nil else { return nil }
      let recognized = Self.bounded(
        item.ocrText,
        limit: Self.maximumRecognizedTextCharacters
      )
      content = .image(imageData, recognizedText: recognized.value)
      isTruncated = recognized.isTruncated
    case .files:
      return nil
    }
  }

  private static func bounded(_ text: String, limit: Int) -> (value: String, isTruncated: Bool)
  {
    guard text.count > limit else { return (text, false) }
    return (String(text.prefix(limit)), true)
  }
}

struct QuickPickerPreviewView: View {
  let payload: QuickPickerPreviewPayload
  let decodedImage: NSImage?
  let onClose: () -> Void

  init(
    payload: QuickPickerPreviewPayload,
    decodedImage: NSImage? = nil,
    onClose: @escaping () -> Void
  ) {
    self.payload = payload
    self.decodedImage = decodedImage
    self.onClose = onClose
  }

  private let textColor = BrandTheme.text
  private let canvas = BrandTheme.canvas
  private let actionColor = BrandTheme.action

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(payload.title)
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .lineLimit(2)
          HStack(spacing: 5) {
            Text(payload.sourceApplication)
            Text("·")
            Text(payload.createdAt, style: .relative).monospacedDigit()
            if payload.isTruncated {
              Text("·")
              Label(
                L10n.text("picker.preview.truncated", fallback: "Preview shortened"),
                systemImage: "ellipsis"
              )
            }
          }
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(.secondary)
        }
        Spacer(minLength: 12)
        Button(L10n.text("picker.preview.close", fallback: "Close"), action: onClose)
          .keyboardShortcut(.cancelAction)
      }
      .padding(18)

      Divider()

      previewContent
    }
    .frame(minWidth: 620, minHeight: 480)
    .background(canvas)
    .foregroundStyle(textColor)
    .tint(actionColor)
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder
  private var previewContent: some View {
    switch payload.content {
    case .text(let text):
      ScrollView {
        Text(text.isEmpty ? L10n.text("picker.preview.empty", fallback: "No text to preview") : text)
          .font(.system(size: 13, weight: .regular, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .topLeading)
          .padding(20)
      }
    case .image(let data, let recognizedText):
      HSplitView {
        Group {
          if let image = decodedImage ?? NSImage(data: data) {
            ScrollView([.horizontal, .vertical]) {
              Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(16)
            }
          } else {
            unavailableImage
          }
        }
        .frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)

        VStack(alignment: .leading, spacing: 10) {
          Label(
            L10n.text("picker.preview.recognized_text", fallback: "Recognized text"),
            systemImage: "text.viewfinder"
          )
          .font(.system(size: 11, weight: .bold, design: .rounded))
          .foregroundStyle(actionColor)

          ScrollView {
            Text(
              recognizedText.isEmpty
                ? L10n.text(
                  "picker.preview.no_recognized_text", fallback: "No readable text was found.")
                : recognizedText
            )
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(recognizedText.isEmpty ? Color.secondary : textColor)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .topLeading)
          }
        }
        .padding(16)
        .frame(minWidth: 220, idealWidth: 260, maxHeight: .infinity, alignment: .topLeading)
      }
    }
  }

  private var unavailableImage: some View {
    VStack(spacing: 10) {
      Image(systemName: "photo.badge.exclamationmark")
        .font(.system(size: 34, weight: .light))
      Text(L10n.text("picker.preview.image_unavailable", fallback: "Image unavailable"))
        .font(.system(size: 13, weight: .semibold))
    }
    .foregroundStyle(.secondary)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
