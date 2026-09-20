import SwiftUI

struct MarkdownPreviewView: View {
  let document: MarkdownDocument

  var body: some View {
    LazyVStack(alignment: .leading, spacing: 12) {
      ForEach(Array(document.blocks.enumerated()), id: \.offset) { _, block in
        blockView(block)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private func blockView(_ block: MarkdownDocument.Block) -> some View {
    switch block {
    case .heading(let level, let text):
      Text(MarkdownDocument.inlineAttributedText(text))
        .font(headingFont(level))
        .padding(.top, level == 1 ? 3 : 0)

    case .paragraph(let text):
      Text(MarkdownDocument.inlineAttributedText(text))
        .font(.system(size: 15, weight: .regular, design: .rounded))
        .lineSpacing(4)

    case .listItem(let number, let text):
      HStack(alignment: .firstTextBaseline, spacing: 9) {
        Text(number.map { "\($0)." } ?? "•")
          .font(.system(size: 13, weight: .bold, design: .rounded))
          .foregroundStyle(.secondary)
          .frame(minWidth: 18, alignment: .trailing)
        Text(MarkdownDocument.inlineAttributedText(text))
          .font(.system(size: 15, weight: .regular, design: .rounded))
          .lineSpacing(4)
      }

    case .quote(let text):
      HStack(alignment: .top, spacing: 11) {
        RoundedRectangle(cornerRadius: 2)
          .fill(Color.secondary.opacity(0.35))
          .frame(width: 3)
        Text(MarkdownDocument.inlineAttributedText(text))
          .font(.system(size: 15, weight: .regular, design: .serif))
          .italic()
          .foregroundStyle(.secondary)
          .lineSpacing(4)
      }

    case .code(let language, let text):
      VStack(alignment: .leading, spacing: 8) {
        if let language {
          Text(language.uppercased())
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        Text(text)
          .font(.system(size: 13, weight: .regular, design: .monospaced))
          .textSelection(.enabled)
          .lineSpacing(3)
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.black.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))

    case .divider:
      Divider().opacity(0.7)
    }
  }

  private func headingFont(_ level: Int) -> Font {
    switch level {
    case 1: .system(size: 25, weight: .bold, design: .rounded)
    case 2: .system(size: 21, weight: .bold, design: .rounded)
    case 3: .system(size: 18, weight: .semibold, design: .rounded)
    default: .system(size: 15, weight: .semibold, design: .rounded)
    }
  }
}
