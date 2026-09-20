import Foundation

enum TemporaryCodeDetector {
  static let defaultLifetime: TimeInterval = 15 * 60

  static func isLikelyCode(_ rawText: String) -> Bool {
    let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, text.utf8.count <= 10_000 else { return false }

    if text.range(of: #"^[0-9]{6}$"#, options: .regularExpression) != nil {
      return true
    }

    if isLikelyGroupedCode(text) { return true }

    let normalized = SearchMatcher.normalize(text)
    let hasContext = [
      "verification", "security code", "authentication", "one-time", "one time",
      "otp", "passcode", "验证码", "校验码", "动态码", "一次性密码",
    ].contains { normalized.contains($0) }
    guard hasContext else { return false }

    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard
      let expression = try? NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9])[A-Za-z0-9]{4,8}(?![A-Za-z0-9])"#
      )
    else { return false }
    return expression.matches(in: text, range: range).contains { match in
      guard let candidateRange = Range(match.range, in: text) else { return false }
      return text[candidateRange].contains(where: \.isNumber)
    }
  }

  private static func isLikelyGroupedCode(_ text: String) -> Bool {
    guard text.range(of: #"^[A-Z0-9]{4}-[A-Z0-9]{4}$"#, options: .regularExpression) != nil
    else { return false }
    let groups = text.split(separator: "-")
    guard groups.count == 2, groups.allSatisfy({ $0.contains(where: \.isNumber) }) else {
      return false
    }
    let characters = text.filter { $0 != "-" }
    let digitCount = characters.count(where: \.isNumber)
    let letterCount = characters.count(where: \.isLetter)
    return digitCount >= 2 && letterCount >= 2
  }

  static func expiration(
    for text: String,
    enabled: Bool,
    now: Date = .now
  ) -> Date? {
    guard enabled, isLikelyCode(text) else { return nil }
    return now.addingTimeInterval(defaultLifetime)
  }
}
