import Foundation

enum ClipStackFormat: String, CaseIterable, Sendable {
  case paragraphs
  case lines
  case bullets
  case numbered

  var label: String {
    switch self {
    case .paragraphs: "Paragraphs"
    case .lines: "Plain lines"
    case .bullets: "Bullet list"
    case .numbered: "Numbered list"
    }
  }

  var systemImage: String {
    switch self {
    case .paragraphs: "text.alignleft"
    case .lines: "line.3.horizontal"
    case .bullets: "list.bullet"
    case .numbered: "list.number"
    }
  }
}

struct ClipStackComposer: Sendable {
  static func content(for item: ClipItem) -> String {
    let source =
      switch item.kind {
      case .text: item.text
      case .image: item.ocrText
      case .files: ""
      }
    return source.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func compose(_ items: [ClipItem], format: ClipStackFormat) -> String {
    let values = items.map(content).filter { !$0.isEmpty }
    switch format {
    case .paragraphs:
      return values.joined(separator: "\n\n")
    case .lines:
      return values.map(singleLine).joined(separator: "\n")
    case .bullets:
      return values.map { "• \(indented($0))" }.joined(separator: "\n")
    case .numbered:
      return values.enumerated().map { index, value in
        "\(index + 1). \(indented(value))"
      }.joined(separator: "\n")
    }
  }

  private static func singleLine(_ value: String) -> String {
    value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  private static func indented(_ value: String) -> String {
    value.replacingOccurrences(of: "\n", with: "\n   ")
  }
}
