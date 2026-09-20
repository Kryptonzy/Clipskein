import Foundation

enum ClipboardPrivacyRuleMode: String, Codable, CaseIterable, Identifiable, Sendable {
  case contains
  case regularExpression

  var id: String { rawValue }

  var localizedLabel: String {
    switch self {
    case .contains:
      L10n.text("privacy_rule.mode.contains", fallback: "Contains phrase")
    case .regularExpression:
      L10n.text("privacy_rule.mode.regex", fallback: "Regular expression")
    }
  }
}

struct ClipboardPrivacyRule: Codable, Identifiable, Equatable, Sendable {
  static let maximumCount = 20
  static let maximumPatternLength = SafeRegexSearch.maximumPatternLength
  static let maximumInspectedCharacters = 2_000_000

  let id: UUID
  var pattern: String
  var mode: ClipboardPrivacyRuleMode
  var isEnabled: Bool
  var matchCount: Int
  var lastMatchedAt: Date?

  init(
    id: UUID = UUID(),
    pattern: String,
    mode: ClipboardPrivacyRuleMode,
    isEnabled: Bool = true,
    matchCount: Int = 0,
    lastMatchedAt: Date? = nil
  ) {
    self.id = id
    self.pattern = pattern
    self.mode = mode
    self.isEnabled = isEnabled
    self.matchCount = max(0, matchCount)
    self.lastMatchedAt = lastMatchedAt
  }

  private enum CodingKeys: String, CodingKey {
    case id, pattern, mode, isEnabled, matchCount, lastMatchedAt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    pattern = try container.decode(String.self, forKey: .pattern)
    mode = try container.decode(ClipboardPrivacyRuleMode.self, forKey: .mode)
    isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    matchCount = max(0, try container.decodeIfPresent(Int.self, forKey: .matchCount) ?? 0)
    lastMatchedAt = try container.decodeIfPresent(Date.self, forKey: .lastMatchedAt)
  }

  func matches(_ text: String) -> Bool {
    guard isEnabled else { return false }
    switch mode {
    case .contains:
      return SearchMatcher.normalize(text).contains(SearchMatcher.normalize(pattern))
    case .regularExpression:
      guard let regex = try? SafeRegexSearch(pattern) else { return false }
      return regex.matches(text, maximumCharacters: Self.maximumInspectedCharacters)
    }
  }
}

enum ClipboardPrivacyRuleValidationError: Equatable, Sendable {
  case empty
  case tooLong
  case duplicate
  case limitReached
  case invalidRegex(RegexSearchValidationError)

  var localizedMessage: String {
    switch self {
    case .empty:
      L10n.text("privacy_rule.error.empty", fallback: "Enter a phrase or pattern.")
    case .tooLong:
      L10n.format(
        "privacy_rule.error.too_long",
        fallback: "Keep rules under %d characters.",
        ClipboardPrivacyRule.maximumPatternLength
      )
    case .duplicate:
      L10n.text("privacy_rule.error.duplicate", fallback: "That rule already exists.")
    case .limitReached:
      L10n.format(
        "privacy_rule.error.limit",
        fallback: "Keep no more than %d privacy rules.",
        ClipboardPrivacyRule.maximumCount
      )
    case .invalidRegex(let error):
      RegexSearchStatus.invalid(error).localizedMessage
        ?? L10n.text("privacy_rule.error.invalid", fallback: "Invalid regular expression.")
    }
  }
}
