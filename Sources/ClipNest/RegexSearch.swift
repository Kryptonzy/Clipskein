import Foundation

enum RegexSearchValidationError: Equatable, Sendable {
  case empty
  case tooLong
  case tooMany
  case unsafe
  case invalid
}

enum RegexSearchStatus: Equatable, Sendable {
  case inactive
  case active([String])
  case invalid(RegexSearchValidationError)
}

extension RegexSearchStatus {
  var localizedMessage: String? {
    switch self {
    case .inactive:
      nil
    case .active(let patterns):
      L10n.format(
        "search.regex.active",
        fallback: "Regex search: %@",
        patterns.joined(separator: " · ")
      )
    case .invalid(.empty):
      L10n.text("search.regex.empty", fallback: "Enter a pattern after regex:")
    case .invalid(.tooLong):
      L10n.format(
        "search.regex.too_long",
        fallback: "Keep regex patterns under %d characters.",
        SafeRegexSearch.maximumPatternLength
      )
    case .invalid(.tooMany):
      L10n.format(
        "search.regex.too_many",
        fallback: "Use no more than %d regex patterns at once.",
        SafeRegexSearch.maximumPatternCount
      )
    case .invalid(.unsafe):
      L10n.text(
        "search.regex.unsafe",
        fallback: "That pattern was rejected to keep search responsive."
      )
    case .invalid(.invalid):
      L10n.text(
        "search.regex.invalid",
        fallback: "Invalid regular expression. Check brackets and escapes."
      )
    }
  }

  var isInvalid: Bool {
    if case .invalid = self { return true }
    return false
  }
}

/// A deliberately bounded regular-expression search. Clipboard entries can be large and search
/// runs on the main actor, so patterns with common catastrophic-backtracking shapes are rejected
/// and matching only examines a bounded prefix of the privacy-safe search index.
struct SafeRegexSearch: @unchecked Sendable {
  static let maximumPatternLength = 160
  static let maximumPatternCount = 3
  static let maximumSearchCharacters = 32_768

  let pattern: String
  private let expression: NSRegularExpression

  init(_ pattern: String) throws {
    let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw RegexSearchValidationError.empty }
    guard trimmed.count <= Self.maximumPatternLength else {
      throw RegexSearchValidationError.tooLong
    }
    guard Self.isSafe(trimmed) else { throw RegexSearchValidationError.unsafe }
    do {
      expression = try NSRegularExpression(
        pattern: trimmed,
        options: [.caseInsensitive, .useUnicodeWordBoundaries]
      )
    } catch {
      throw RegexSearchValidationError.invalid
    }
    self.pattern = trimmed
  }

  func matches(
    _ text: String,
    maximumCharacters: Int = SafeRegexSearch.maximumSearchCharacters
  ) -> Bool {
    firstMatch(in: text, maximumCharacters: maximumCharacters) != nil
  }

  func firstMatch(
    in text: String,
    maximumCharacters: Int = SafeRegexSearch.maximumSearchCharacters
  ) -> RegexSearchMatch? {
    let bounded = String(text.prefix(max(0, maximumCharacters)))
    let range = NSRange(bounded.startIndex..<bounded.endIndex, in: bounded)
    guard let result = expression.firstMatch(in: bounded, range: range),
      let matchRange = Range(result.range, in: bounded)
    else { return nil }
    return RegexSearchMatch(text: bounded, range: matchRange)
  }

  private static func isSafe(_ pattern: String) -> Bool {
    let forbiddenFragments = ["(?=", "(?!", "(?<=", "(?<!", ".*.*", ".+.+"]
    guard !forbiddenFragments.contains(where: pattern.contains) else { return false }

    var escaped = false
    var inCharacterClass = false
    var groupQuantifierStack: [Bool] = []
    var groupAlternationStack: [Bool] = []
    var previousClosedGroupWasRisky = false
    let characters = Array(pattern)

    for (index, character) in characters.enumerated() {
      if escaped {
        if character.isNumber && character != "0" { return false }
        escaped = false
        previousClosedGroupWasRisky = false
        continue
      }
      if character == "\\" {
        escaped = true
        continue
      }
      if character == "[" && !inCharacterClass {
        inCharacterClass = true
        previousClosedGroupWasRisky = false
        continue
      }
      if character == "]" && inCharacterClass {
        inCharacterClass = false
        previousClosedGroupWasRisky = false
        continue
      }
      guard !inCharacterClass else { continue }

      if character == "(" {
        groupQuantifierStack.append(false)
        groupAlternationStack.append(false)
        previousClosedGroupWasRisky = false
        continue
      }
      if character == ")" {
        let containedQuantifier = groupQuantifierStack.popLast() ?? false
        let containedAlternation = groupAlternationStack.popLast() ?? false
        previousClosedGroupWasRisky = containedQuantifier || containedAlternation
        if previousClosedGroupWasRisky, !groupQuantifierStack.isEmpty {
          groupQuantifierStack[groupQuantifierStack.count - 1] = true
        }
        continue
      }
      if character == "|", !groupAlternationStack.isEmpty {
        groupAlternationStack[groupAlternationStack.count - 1] = true
      }

      let isGroupPrefixQuestionMark = character == "?" && index > 0 && characters[index - 1] == "("
      let isQuantifier =
        character == "*" || character == "+" || character == "{"
        || (character == "?" && !isGroupPrefixQuestionMark)
      if isQuantifier {
        if character == "{",
          let closingIndex = characters.indices.dropFirst(index + 1).first(where: {
            characters[$0] == "}"
          })
        {
          let bounds = String(characters[(index + 1)..<closingIndex])
            .split(separator: ",", omittingEmptySubsequences: false)
          if bounds.compactMap({ Int($0) }).contains(where: { $0 > 1_000 }) {
            return false
          }
        }
        if previousClosedGroupWasRisky { return false }
        if !groupQuantifierStack.isEmpty {
          groupQuantifierStack[groupQuantifierStack.count - 1] = true
        }
        if index > 0 {
          let previous = characters[index - 1]
          if previous == "*" || previous == "+" || previous == "?" || previous == "}" {
            return false
          }
        }
      }
      previousClosedGroupWasRisky = false
    }
    // Syntax errors (including unclosed groups/classes or a dangling escape) are reported by ICU
    // as invalid patterns; this pass is only responsible for rejecting valid but risky shapes.
    return true
  }
}

struct RegexSearchMatch {
  let text: String
  let range: Range<String.Index>
}

extension RegexSearchValidationError: Error {}
