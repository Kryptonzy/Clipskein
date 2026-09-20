import Foundation

enum TextTransformationKind: String, CaseIterable, Sendable {
  case cleanSpacing
  case singleLine
  case removeBlankLines
  case deduplicateLines
  case sortLines
  case minifyJSON
  case decodePercentEncoding
  case stripHTML

  var label: String {
    switch self {
    case .cleanSpacing: L10n.text("transform.clean_spacing", fallback: "Clean spacing")
    case .singleLine: L10n.text("transform.single_line", fallback: "Make one line")
    case .removeBlankLines:
      L10n.text("transform.remove_blank_lines", fallback: "Remove blank lines")
    case .deduplicateLines:
      L10n.text("transform.deduplicate_lines", fallback: "Remove duplicate lines")
    case .sortLines: L10n.text("transform.sort_lines", fallback: "Sort lines")
    case .minifyJSON: L10n.text("transform.minify_json", fallback: "Minify JSON")
    case .decodePercentEncoding:
      L10n.text("transform.decode_url", fallback: "Decode URL text")
    case .stripHTML:
      L10n.text("transform.strip_html", fallback: "Convert HTML to plain text")
    }
  }

  var systemImage: String {
    switch self {
    case .cleanSpacing: "text.alignleft"
    case .singleLine: "arrow.right.to.line"
    case .removeBlankLines: "line.3.horizontal.decrease"
    case .deduplicateLines: "rectangle.on.rectangle.slash"
    case .sortLines: "arrow.up.arrow.down"
    case .minifyJSON: "curlybraces"
    case .decodePercentEncoding: "link"
    case .stripHTML: "chevron.left.forwardslash.chevron.right"
    }
  }
}

struct TextTransformation: Identifiable, Equatable, Sendable {
  let kind: TextTransformationKind
  let result: String

  var id: String { kind.rawValue }
  var label: String { kind.label }
  var systemImage: String { kind.systemImage }
}

enum TextTransformer {
  static let maximumInputLength = 200_000

  static func availableTransformations(for input: String) -> [TextTransformation] {
    guard !input.isEmpty, input.count <= maximumInputLength else { return [] }
    return TextTransformationKind.allCases.compactMap { kind in
      let result = transform(input, using: kind)
      return result == input || result.isEmpty
        ? nil : TextTransformation(kind: kind, result: result)
    }
  }

  static func transform(_ input: String, using kind: TextTransformationKind) -> String {
    switch kind {
    case .cleanSpacing:
      return cleanSpacing(in: input)
    case .singleLine:
      guard input.rangeOfCharacter(from: .newlines) != nil else { return input }
      return input.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    case .removeBlankLines:
      return lines(in: input)
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: "\n")
    case .deduplicateLines:
      return deduplicateLines(in: input)
    case .sortLines:
      return sortLines(in: input)
    case .minifyJSON:
      return minifyJSON(in: input)
    case .decodePercentEncoding:
      return decodePercentEncoding(in: input)
    case .stripHTML:
      return stripHTML(in: input)
    }
  }

  private static func cleanSpacing(in input: String) -> String {
    let cleanedLines = lines(in: input).map { line in
      line.replacingOccurrences(of: #"[\t ]+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespaces)
    }
    var result: [String] = []
    for line in cleanedLines {
      guard !line.isEmpty else {
        if !result.isEmpty, result.last != "" { result.append("") }
        continue
      }
      result.append(line)
    }
    while result.last == "" { result.removeLast() }
    return result.joined(separator: "\n")
  }

  private static func deduplicateLines(in input: String) -> String {
    var seen = Set<String>()
    var result: [String] = []
    for rawLine in lines(in: input) {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty else {
        result.append(rawLine)
        continue
      }
      let key = line.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      if seen.insert(key).inserted { result.append(rawLine) }
    }
    return result.joined(separator: "\n")
  }

  private static func sortLines(in input: String) -> String {
    let inputLines = lines(in: input)
    guard (2...200).contains(inputLines.count),
      inputLines.allSatisfy({
        !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 200
      })
    else { return input }
    return inputLines.sorted {
      $0.trimmingCharacters(in: .whitespaces)
        .localizedCaseInsensitiveCompare($1.trimmingCharacters(in: .whitespaces))
        == .orderedAscending
    }.joined(separator: "\n")
  }

  private static func minifyJSON(in input: String) -> String {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.first == "{" || trimmed.first == "[",
      let data = trimmed.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data),
      JSONSerialization.isValidJSONObject(object),
      let minifiedData = try? JSONSerialization.data(withJSONObject: object),
      let minified = String(data: minifiedData, encoding: .utf8),
      minified != input
    else { return input }
    return minified
  }

  private static func decodePercentEncoding(in input: String) -> String {
    guard input.contains("%"),
      let decoded = input.removingPercentEncoding,
      decoded != input
    else { return input }
    return decoded
  }

  private static func stripHTML(in input: String) -> String {
    guard
      input.range(
        of: #"</?[A-Za-z][^>]*>"#,
        options: [.regularExpression, .caseInsensitive]
      ) != nil
    else { return input }

    var result = input
    result = result.replacingOccurrences(
      of: #"(?s)<!--.*?-->"#,
      with: "",
      options: .regularExpression
    )
    result = result.replacingOccurrences(
      of: #"(?is)<(script|style)\b[^>]*>.*?</\1\s*>"#,
      with: "",
      options: .regularExpression
    )
    result = result.replacingOccurrences(
      of: #"(?i)<br\s*/?>|</(?:p|div|li|tr|h[1-6])\s*>"#,
      with: "\n",
      options: .regularExpression
    )
    result = result.replacingOccurrences(
      of: #"(?i)<li\b[^>]*>"#,
      with: "• ",
      options: .regularExpression
    )
    result = result.replacingOccurrences(
      of: #"(?s)<[^>]+>"#,
      with: "",
      options: .regularExpression
    )
    result = decodeHTMLEntities(in: result)

    var outputLines: [String] = []
    for rawLine in lines(in: result) {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      if line.isEmpty {
        if !outputLines.isEmpty, outputLines.last != "" { outputLines.append("") }
      } else {
        outputLines.append(line)
      }
    }
    while outputLines.last == "" { outputLines.removeLast() }
    let output = outputLines.joined(separator: "\n")
    return output.isEmpty ? input : output
  }

  private static func decodeHTMLEntities(in input: String) -> String {
    var result =
      input
      .replacingOccurrences(of: "&nbsp;", with: "\u{00A0}", options: .caseInsensitive)
      .replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
      .replacingOccurrences(of: "&lt;", with: "<", options: .caseInsensitive)
      .replacingOccurrences(of: "&gt;", with: ">", options: .caseInsensitive)
      .replacingOccurrences(of: "&quot;", with: "\"", options: .caseInsensitive)
      .replacingOccurrences(of: "&apos;", with: "'", options: .caseInsensitive)

    guard
      let expression = try? NSRegularExpression(
        pattern: #"&#(?:x([0-9A-Fa-f]+)|([0-9]+));"#
      )
    else { return result }
    let fullRange = NSRange(result.startIndex..<result.endIndex, in: result)
    for match in expression.matches(in: result, range: fullRange).reversed() {
      let hexRange = Range(match.range(at: 1), in: result)
      let decimalRange = Range(match.range(at: 2), in: result)
      let value =
        hexRange.flatMap { UInt32(result[$0], radix: 16) }
        ?? decimalRange.flatMap { UInt32(result[$0], radix: 10) }
      guard let value, let scalar = UnicodeScalar(value),
        let replacementRange = Range(match.range, in: result)
      else { continue }
      result.replaceSubrange(replacementRange, with: String(scalar))
    }
    return result
  }

  private static func lines(in input: String) -> [String] {
    input.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .components(separatedBy: "\n")
  }
}
