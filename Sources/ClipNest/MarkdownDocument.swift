import Foundation

struct MarkdownDocument: Equatable, Sendable {
  static let maximumUTF8Bytes = 500_000
  static let maximumLineCount = 5_000

  enum Block: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case listItem(number: Int?, text: String)
    case quote(String)
    case code(language: String?, text: String)
    case divider
  }

  let source: String
  let blocks: [Block]
  let plainText: String

  static func parse(_ source: String) -> MarkdownDocument? {
    guard !source.isEmpty, source.utf8.count <= maximumUTF8Bytes else { return nil }
    let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    guard lines.count <= maximumLineCount else { return nil }

    var blocks: [Block] = []
    var paragraphLines: [String] = []
    var codeLines: [String] = []
    var codeFence: String?
    var codeLanguage: String?
    var markdownSignals = 0

    func flushParagraph() {
      guard !paragraphLines.isEmpty else { return }
      blocks.append(.paragraph(paragraphLines.joined(separator: "\n")))
      paragraphLines.removeAll(keepingCapacity: true)
    }

    func flushCode() {
      guard codeFence != nil else { return }
      blocks.append(
        .code(
          language: codeLanguage,
          text: codeLines.joined(separator: "\n")
        )
      )
      codeLines.removeAll(keepingCapacity: true)
      codeFence = nil
      codeLanguage = nil
    }

    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      if let activeFence = codeFence {
        if trimmed.hasPrefix(activeFence) {
          flushCode()
        } else {
          codeLines.append(line)
        }
        continue
      }

      if let fence = fenceMarker(in: trimmed) {
        flushParagraph()
        codeFence = fence
        let language = String(trimmed.dropFirst(fence.count))
          .trimmingCharacters(in: .whitespacesAndNewlines)
        codeLanguage = language.isEmpty ? nil : String(language.prefix(40))
        markdownSignals += 1
        continue
      }

      if trimmed.isEmpty {
        flushParagraph()
        continue
      }

      if let heading = heading(in: line) {
        flushParagraph()
        blocks.append(.heading(level: heading.level, text: heading.text))
        markdownSignals += 1
        continue
      }

      if isDivider(trimmed) {
        flushParagraph()
        blocks.append(.divider)
        markdownSignals += 1
        continue
      }

      if let quote = quotedText(in: line) {
        flushParagraph()
        blocks.append(.quote(quote))
        markdownSignals += 1
        continue
      }

      if let item = unorderedListItem(in: line) {
        flushParagraph()
        blocks.append(.listItem(number: nil, text: item))
        markdownSignals += 1
        continue
      }

      if let item = orderedListItem(in: line) {
        flushParagraph()
        blocks.append(.listItem(number: item.number, text: item.text))
        markdownSignals += 1
        continue
      }

      if containsInlineMarkdown(line) { markdownSignals += 1 }
      paragraphLines.append(line)
    }

    flushParagraph()
    flushCode()

    guard markdownSignals > 0, !blocks.isEmpty else { return nil }
    let plainText = makePlainText(from: blocks)
    guard !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return MarkdownDocument(source: source, blocks: blocks, plainText: plainText)
  }

  static func inlineAttributedText(_ source: String) -> AttributedString {
    var attributed =
      (try? AttributedString(
        markdown: source,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
      )) ?? AttributedString(source)

    let unsafeLinks = attributed.runs.compactMap { run -> Range<AttributedString.Index>? in
      guard let link = run.link else { return nil }
      let scheme = link.scheme?.localizedLowercase
      return ["http", "https", "mailto"].contains(scheme) ? nil : run.range
    }
    for range in unsafeLinks { attributed[range].link = nil }
    return attributed
  }

  private static func plainText(for block: Block) -> String? {
    switch block {
    case .heading(_, let text), .paragraph(let text):
      return inlinePlainText(text)
    case .listItem(let number, let text):
      let prefix = number.map { "\($0). " } ?? "• "
      return prefix + inlinePlainText(text)
    case .quote(let text):
      return "> " + inlinePlainText(text)
    case .code(_, let text):
      return text
    case .divider:
      return "———"
    }
  }

  private static func makePlainText(from blocks: [Block]) -> String {
    var result = ""
    var previous: Block?
    for block in blocks {
      guard let text = plainText(for: block), !text.isEmpty else { continue }
      if let previous {
        let compactSequence: Bool
        switch (previous, block) {
        case (.listItem, .listItem), (.quote, .quote):
          compactSequence = true
        default:
          compactSequence = false
        }
        result += compactSequence ? "\n" : "\n\n"
      }
      result += text
      previous = block
    }
    return result
  }

  private static func inlinePlainText(_ source: String) -> String {
    String(inlineAttributedText(source).characters)
  }

  private static func fenceMarker(in line: String) -> String? {
    if line.hasPrefix("```") { return "```" }
    if line.hasPrefix("~~~") { return "~~~" }
    return nil
  }

  private static func heading(in line: String) -> (level: Int, text: String)? {
    let content = line.drop(while: { $0 == " " || $0 == "\t" })
    let level = content.prefix(while: { $0 == "#" }).count
    guard (1...6).contains(level) else { return nil }
    let afterMarker = content.dropFirst(level)
    guard afterMarker.first?.isWhitespace == true else { return nil }
    let text = afterMarker.drop(while: \Character.isWhitespace)
    guard !text.isEmpty else { return nil }
    return (level, String(text))
  }

  private static func quotedText(in line: String) -> String? {
    let content = line.drop(while: { $0 == " " || $0 == "\t" })
    guard content.first == ">" else { return nil }
    return String(content.dropFirst().drop(while: \Character.isWhitespace))
  }

  private static func unorderedListItem(in line: String) -> String? {
    let content = line.drop(while: { $0 == " " || $0 == "\t" })
    guard let marker = content.first, "-*+".contains(marker) else { return nil }
    let remainder = content.dropFirst()
    guard remainder.first?.isWhitespace == true else { return nil }
    let text = remainder.drop(while: \Character.isWhitespace)
    return text.isEmpty ? nil : String(text)
  }

  private static func orderedListItem(in line: String) -> (number: Int, text: String)? {
    let content = line.drop(while: { $0 == " " || $0 == "\t" })
    let digits = content.prefix(while: \Character.isNumber)
    guard !digits.isEmpty, digits.count <= 5, let number = Int(digits) else { return nil }
    let afterDigits = content.dropFirst(digits.count)
    guard let marker = afterDigits.first, marker == "." || marker == ")" else { return nil }
    let remainder = afterDigits.dropFirst()
    guard remainder.first?.isWhitespace == true else { return nil }
    let text = remainder.drop(while: \Character.isWhitespace)
    return text.isEmpty ? nil : (number, String(text))
  }

  private static func isDivider(_ line: String) -> Bool {
    let compact = line.filter { !$0.isWhitespace }
    guard compact.count >= 3, let marker = compact.first, "-*_".contains(marker) else {
      return false
    }
    return compact.allSatisfy { $0 == marker }
  }

  private static func containsInlineMarkdown(_ line: String) -> Bool {
    let patterns = [
      #"(?<!\\)!?\[[^\]\n]+\]\((?:https?://|mailto:)[^)\n]+\)"#,
      #"(?<!\\)(?:\*\*|__|~~)[^\n]+?(?:\*\*|__|~~)"#,
      #"(?<!\\)`[^`\n]+`"#,
    ]
    return patterns.contains { line.range(of: $0, options: .regularExpression) != nil }
  }
}
