import Foundation

struct SearchMatcher: Sendable {
  let query: String
  let queryTokens: [String]
  private let literalTokens: [String]
  private let fuzzyTokens: [String]

  init(_ rawQuery: String) {
    query = Self.normalize(rawQuery.trimmingCharacters(in: .whitespacesAndNewlines))
    queryTokens = Self.tokens(in: query)
    literalTokens = queryTokens.filter(Self.requiresLiteralMatch)
    fuzzyTokens = queryTokens.filter { !Self.requiresLiteralMatch($0) }
  }

  var isEmpty: Bool { query.isEmpty }

  func matches(_ rawText: String) -> Bool {
    let text = Self.normalize(rawText)
    return matches(normalizedText: text, tokens: Self.tokens(in: text))
  }

  func matches(normalizedText text: String, tokens words: [String]) -> Bool {
    guard !isEmpty else { return true }
    if text.contains(query) { return true }
    guard literalTokens.allSatisfy({ text.contains($0) }) else { return false }
    return !queryTokens.isEmpty
      && fuzzyTokens.allSatisfy { token in
        words.contains { Self.matchQuality(query: token, word: $0) > 0 }
      }
  }

  func tokenBonus(in rawText: String) -> Double {
    let text = Self.normalize(rawText)
    return tokenBonus(normalizedText: text, tokens: Self.tokens(in: text))
  }

  func tokenBonus(normalizedText: String, tokens words: [String]) -> Double {
    guard !isEmpty else { return 0 }
    return queryTokens.reduce(0) { total, token in
      total + Double(words.map { Self.matchQuality(query: token, word: $0) }.max() ?? 0)
    }
  }

  static func normalize(_ value: String) -> String {
    value
      .folding(
        options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
        locale: .current
      )
      .lowercased(with: .current)
  }

  static func tokens(in value: String) -> [String] {
    value.components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }
  }

  private static func matchQuality(query: String, word: String) -> Int {
    if query == word { return 120 }
    if word.hasPrefix(query) { return 80 }
    if word.contains(query) { return 55 }

    let threshold = editThreshold(for: query.count)
    guard threshold > 0,
      abs(query.count - word.count) <= threshold,
      query.count <= 64,
      word.count <= 64
    else { return 0 }

    let distance = boundedEditDistance(query, word, limit: threshold)
    guard distance <= threshold else { return 0 }
    return distance == 1 ? 42 : 24
  }

  private static func editThreshold(for length: Int) -> Int {
    switch length {
    case ..<4: 0
    case 4...6: 1
    default: 2
    }
  }

  private static func requiresLiteralMatch(_ token: String) -> Bool {
    token.count < 4 || token.allSatisfy(\.isNumber)
  }

  private static func boundedEditDistance(_ left: String, _ right: String, limit: Int) -> Int {
    let lhs = Array(left)
    let rhs = Array(right)
    if lhs.isEmpty { return min(rhs.count, limit + 1) }
    if rhs.isEmpty { return min(lhs.count, limit + 1) }

    var previous = Array(0...rhs.count)
    for (leftIndex, leftCharacter) in lhs.enumerated() {
      var current = [leftIndex + 1]
      current.reserveCapacity(rhs.count + 1)
      var rowMinimum = current[0]

      for (rightIndex, rightCharacter) in rhs.enumerated() {
        let insertion = current[rightIndex] + 1
        let deletion = previous[rightIndex + 1] + 1
        let substitution = previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
        let value = min(insertion, deletion, substitution)
        current.append(value)
        rowMinimum = min(rowMinimum, value)
      }

      if rowMinimum > limit { return limit + 1 }
      previous = current
    }
    return previous[rhs.count]
  }
}
