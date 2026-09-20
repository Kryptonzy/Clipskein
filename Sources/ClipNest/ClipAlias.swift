import Foundation

enum ClipAlias {
  static let maximumLength = 32

  static func normalized(_ rawValue: String) -> String? {
    guard let prepared = prepared(rawValue) else { return nil }
    let candidate = String(prepared.prefix(maximumLength))
    guard
      candidate.allSatisfy({
        $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_"
      })
    else { return nil }
    return candidate
  }

  static func exceedsMaximumLength(_ rawValue: String) -> Bool {
    (prepared(rawValue)?.count ?? 0) > maximumLength
  }

  private static func prepared(_ rawValue: String) -> String? {
    var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    while value.first == "@" { value.removeFirst() }
    value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }

    let collapsed = value.split(whereSeparator: \.isWhitespace).joined(separator: "-")
    let folded =
      collapsed
      .folding(
        options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
        locale: .current
      )
      .lowercased(with: .current)
    return folded.isEmpty ? nil : folded
  }

  static func isValidStored(_ value: String) -> Bool {
    !value.isEmpty && value.count <= maximumLength && normalized(value) == value
  }
}
