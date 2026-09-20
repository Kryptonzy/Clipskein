import Foundation

struct OCRTable: Equatable, Sendable {
  let rows: [[String]]

  var columnCount: Int { rows.first?.count ?? 0 }

  static func detect(in recognizedText: String) -> OCRTable? {
    let sourceLines = recognizedText.components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard sourceLines.count >= 2 else { return nil }

    let candidateRows = sourceLines.compactMap(splitRow).filter { (2...20).contains($0.count) }
    guard candidateRows.count >= 2 else { return nil }
    let frequencies = Dictionary(grouping: candidateRows, by: \.count).mapValues(\.count)
    guard
      let columnCount = frequencies.max(by: { lhs, rhs in
        lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value < rhs.value
      })?.key
    else { return nil }
    let consistentRows = candidateRows.filter { $0.count == columnCount }
    guard consistentRows.count >= 2,
      consistentRows.count * 2 >= candidateRows.count
    else { return nil }

    return OCRTable(rows: Array(consistentRows.prefix(200)))
  }

  var markdown: String {
    guard let header = rows.first else { return "" }
    let divider = Array(repeating: "---", count: columnCount)
    return ([header, divider] + rows.dropFirst()).map { row in
      "| " + row.map(Self.escapeMarkdown).joined(separator: " | ") + " |"
    }.joined(separator: "\n")
  }

  var json: String {
    guard let first = rows.first else { return "[]" }
    let headers = Self.uniqueHeaders(first)
    let dataRows = rows.count > 1 ? Array(rows.dropFirst()) : rows
    let objects = dataRows.map { row in
      Dictionary(uniqueKeysWithValues: zip(headers, row))
    }
    guard JSONSerialization.isValidJSONObject(objects),
      let data = try? JSONSerialization.data(
        withJSONObject: objects,
        options: [.prettyPrinted, .sortedKeys]
      )
    else { return "[]" }
    return String(data: data, encoding: .utf8) ?? "[]"
  }

  var html: String {
    guard let header = rows.first else { return "<table></table>" }
    let headerHTML = header.map { "<th>\(Self.escapeHTML($0))</th>" }.joined()
    let bodyHTML = rows.dropFirst().map { row in
      "  <tr>" + row.map { "<td>\(Self.escapeHTML($0))</td>" }.joined() + "</tr>"
    }.joined(separator: "\n")
    return """
      <table>
        <thead><tr>\(headerHTML)</tr></thead>
        <tbody>
      \(bodyHTML)
        </tbody>
      </table>
      """
  }

  private static func splitRow(_ line: String) -> [String]? {
    if line.contains("|") {
      let cells = line.split(separator: "|", omittingEmptySubsequences: false)
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      let trimmed = cells.drop(while: \.isEmpty).reversed().drop(while: \.isEmpty).reversed()
      return normalized(Array(trimmed))
    }

    var cells: [String] = []
    var current = ""
    var whitespace = ""
    func flushWhitespace() {
      guard !whitespace.isEmpty else { return }
      if whitespace.contains("\t") || whitespace.count >= 2 {
        let value = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { cells.append(value) }
        current = ""
      } else {
        current += " "
      }
      whitespace = ""
    }

    for character in line {
      if character == " " || character == "\t" {
        whitespace.append(character)
      } else {
        flushWhitespace()
        current.append(character)
      }
    }
    flushWhitespace()
    let finalValue = current.trimmingCharacters(in: .whitespacesAndNewlines)
    if !finalValue.isEmpty { cells.append(finalValue) }
    return normalized(cells)
  }

  private static func normalized(_ cells: [String]) -> [String]? {
    let values = cells.map {
      String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
    }
    guard values.count >= 2, values.contains(where: { !$0.isEmpty }) else { return nil }
    return values
  }

  private static func escapeMarkdown(_ value: String) -> String {
    value.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "|", with: "\\|")
      .replacingOccurrences(of: "\n", with: "<br>")
  }

  private static func uniqueHeaders(_ values: [String]) -> [String] {
    var counts: [String: Int] = [:]
    return values.enumerated().map { index, value in
      let base = value.isEmpty ? "column_\(index + 1)" : value
      let count = (counts[base] ?? 0) + 1
      counts[base] = count
      return count == 1 ? base : "\(base)_\(count)"
    }
  }

  private static func escapeHTML(_ value: String) -> String {
    value.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&#39;")
  }
}
