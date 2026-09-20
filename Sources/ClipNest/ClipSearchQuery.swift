import Foundation

enum SearchTokenEditor {
  static func contains(_ token: String, in query: String) -> Bool {
    tokens(in: query).contains(token)
  }

  static func toggling(_ token: String, in query: String) -> String {
    var tokens = tokens(in: query)
    if let index = tokens.firstIndex(of: token) {
      tokens.remove(at: index)
    } else {
      let oppositeTokens = [
        "is:pinned": "is:unpinned",
        "is:unpinned": "is:pinned",
        "is:concealed": "is:visible",
        "is:visible": "is:concealed",
        "is:expiring": "is:permanent",
        "is:permanent": "is:expiring",
      ]
      if let opposite = oppositeTokens[token] {
        tokens.removeAll { $0 == opposite }
      }
      tokens.append(token)
    }
    return tokens.joined(separator: " ")
  }

  private static func tokens(in query: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    var isQuoted = false
    var isEscaping = false

    func finishToken() {
      guard !current.isEmpty else { return }
      tokens.append(current)
      current = ""
    }

    for character in query {
      if isEscaping {
        current.append(character)
        isEscaping = false
      } else if character == "\\" && isQuoted {
        current.append(character)
        isEscaping = true
      } else if character == "\"" {
        current.append(character)
        isQuoted.toggle()
      } else if character.isWhitespace && !isQuoted {
        finishToken()
      } else {
        current.append(character)
      }
    }
    finishToken()
    return tokens
  }
}

struct ClipSearchQuery: Sendable {
  let naturalLanguage: NaturalLanguageSearch
  let matcher: SearchMatcher
  let regexes: [SafeRegexSearch]
  let regexStatus: RegexSearchStatus
  let tags: [String]
  let applications: [String]
  let kinds: Set<ClipKind>
  let contentKinds: Set<ClipContentKind>
  let pinnedStates: Set<Bool>
  let concealedStates: Set<Bool>
  let expiringStates: Set<Bool>
  let createdOnOrAfter: Date?
  let createdBefore: Date?

  init(
    _ rawQuery: String,
    calendar: Calendar = .current,
    knownApplications: [String] = [],
    interpretNaturalLanguage: Bool = true,
    now: Date = .now
  ) {
    let interpreted =
      interpretNaturalLanguage
      ? NaturalLanguageSearch.interpret(
        rawQuery,
        knownApplications: knownApplications,
        now: now,
        calendar: calendar
      )
      : NaturalLanguageSearch.interpret(
        rawQuery,
        knownApplications: [],
        now: now,
        calendar: calendar
      )
    naturalLanguage =
      interpretNaturalLanguage
      ? interpreted
      : NaturalLanguageSearch.literal(rawQuery)
    var freeTerms: [String] = []
    var parsedTags: [String] = []
    var parsedApplications = naturalLanguage.applications.map(SearchMatcher.normalize)
    var parsedKinds = naturalLanguage.kinds
    var parsedContentKinds = naturalLanguage.contentKinds
    var parsedPinnedStates = naturalLanguage.pinnedStates
    var parsedConcealedStates = naturalLanguage.concealedStates
    var parsedExpiringStates = naturalLanguage.expiringStates
    var parsedAfter = naturalLanguage.createdOnOrAfter
    var parsedBefore = naturalLanguage.createdBefore
    var parsedRegexes: [SafeRegexSearch] = []
    var regexValidationError: RegexSearchValidationError?

    for token in Self.lex(naturalLanguage.remainingQuery) {
      let parts = token.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
      guard parts.count == 2 else {
        freeTerms.append(token)
        continue
      }

      let key = SearchMatcher.normalize(String(parts[0]))
      let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
      let normalizedValue = SearchMatcher.normalize(value)
      var consumed = !value.isEmpty

      switch key {
      case "regex":
        consumed = true
        if parsedRegexes.count >= SafeRegexSearch.maximumPatternCount {
          regexValidationError = .tooMany
        } else if regexValidationError == nil {
          do {
            parsedRegexes.append(try SafeRegexSearch(value))
          } catch let error as RegexSearchValidationError {
            regexValidationError = error
          } catch {
            regexValidationError = .invalid
          }
        }
      case "tag" where consumed:
        parsedTags.append(normalizedValue)
      case "app" where consumed:
        parsedApplications.append(normalizedValue)
      case "type" where consumed:
        switch normalizedValue {
        case "text": parsedKinds.insert(.text)
        case "image", "images": parsedKinds.insert(.image)
        case "file", "files": parsedKinds.insert(.files)
        default: consumed = false
        }
      case "kind" where consumed:
        switch normalizedValue {
        case "receipt", "receipts", "invoice", "invoices": parsedContentKinds.insert(.receipt)
        case "link", "links": parsedContentKinds.insert(.link)
        case "email", "emails": parsedContentKinds.insert(.email)
        case "code": parsedContentKinds.insert(.code)
        case "json": parsedContentKinds.insert(.json)
        case "color", "colors": parsedContentKinds.insert(.color)
        case "text": parsedContentKinds.insert(.text)
        case "image", "images": parsedContentKinds.insert(.image)
        case "file", "files": parsedContentKinds.insert(.files)
        default: consumed = false
        }
      case "is" where consumed:
        switch normalizedValue {
        case "pinned": parsedPinnedStates.insert(true)
        case "unpinned": parsedPinnedStates.insert(false)
        case "concealed": parsedConcealedStates.insert(true)
        case "visible": parsedConcealedStates.insert(false)
        case "expiring", "temporary": parsedExpiringStates.insert(true)
        case "permanent": parsedExpiringStates.insert(false)
        default: consumed = false
        }
      case "after" where consumed:
        if let date = Self.date(from: value, calendar: calendar) {
          parsedAfter = max(parsedAfter ?? date, date)
        } else {
          consumed = false
        }
      case "before" where consumed:
        if let date = Self.date(from: value, calendar: calendar) {
          parsedBefore = min(parsedBefore ?? date, date)
        } else {
          consumed = false
        }
      default:
        consumed = false
      }

      if !consumed { freeTerms.append(token) }
    }

    matcher = SearchMatcher(freeTerms.joined(separator: " "))
    regexes = parsedRegexes
    if let regexValidationError {
      regexStatus = .invalid(regexValidationError)
    } else if parsedRegexes.isEmpty {
      regexStatus = .inactive
    } else {
      regexStatus = .active(parsedRegexes.map(\.pattern))
    }
    tags = parsedTags
    applications = parsedApplications
    kinds = parsedKinds
    contentKinds = parsedContentKinds
    pinnedStates = parsedPinnedStates
    concealedStates = parsedConcealedStates
    expiringStates = parsedExpiringStates
    createdOnOrAfter = parsedAfter
    createdBefore = parsedBefore
  }

  var requiresContentClassification: Bool { !contentKinds.isEmpty }

  func matches(
    _ item: ClipItem,
    classifiedKind: ClipContentKind? = nil,
    normalizedSearchableText: String? = nil,
    searchableTokens: [String]? = nil,
    normalizedTags: [String]? = nil,
    normalizedSource: String? = nil
  ) -> Bool {
    if case .invalid = regexStatus { return false }
    if let normalizedSearchableText, let searchableTokens {
      guard
        matcher.matches(
          normalizedText: normalizedSearchableText,
          tokens: searchableTokens
        )
      else { return false }
    } else if !matcher.matches(item.searchableText) {
      return false
    }
    let regexText = normalizedSearchableText ?? SearchMatcher.normalize(item.searchableText)
    guard regexes.allSatisfy({ $0.matches(regexText) }) else { return false }

    if !tags.isEmpty {
      let itemTags = Set(normalizedTags ?? item.tags.map(SearchMatcher.normalize))
      guard tags.allSatisfy(itemTags.contains) else { return false }
    }

    if !applications.isEmpty {
      let source = normalizedSource ?? SearchMatcher.normalize(item.sourceApplication)
      guard applications.contains(where: source.contains) else { return false }
    }
    guard kinds.isEmpty || kinds.contains(item.kind) else { return false }
    guard
      contentKinds.isEmpty
        || contentKinds.contains(classifiedKind ?? item.privacySafeContentKind)
    else { return false }
    guard pinnedStates.isEmpty || pinnedStates.contains(item.isPinned) else { return false }
    guard concealedStates.isEmpty || concealedStates.contains(item.isConcealed) else {
      return false
    }
    guard expiringStates.isEmpty || expiringStates.contains(item.expiresAt != nil) else {
      return false
    }
    if let createdOnOrAfter, item.createdAt < createdOnOrAfter { return false }
    if let createdBefore, item.createdAt >= createdBefore { return false }
    return true
  }

  private static func lex(_ query: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    var isQuoted = false
    var isEscaping = false

    func finishToken() {
      guard !current.isEmpty else { return }
      tokens.append(current)
      current = ""
    }

    for character in query {
      if isEscaping {
        if character != "\"" && character != "\\" { current.append("\\") }
        current.append(character)
        isEscaping = false
      } else if character == "\\" && isQuoted {
        isEscaping = true
      } else if character == "\"" {
        isQuoted.toggle()
      } else if character.isWhitespace && !isQuoted {
        finishToken()
      } else {
        current.append(character)
      }
    }
    if isEscaping { current.append("\\") }
    finishToken()
    return tokens
  }

  private static func date(from value: String, calendar: Calendar) -> Date? {
    let parts = value.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3,
      parts[0].count == 4,
      parts[1].count == 2,
      parts[2].count == 2,
      let year = Int(parts[0]),
      let month = Int(parts[1]),
      let day = Int(parts[2])
    else { return nil }

    let components = DateComponents(year: year, month: month, day: day)
    guard let date = calendar.date(from: components) else { return nil }
    let verified = calendar.dateComponents([.year, .month, .day], from: date)
    guard verified.year == year, verified.month == month, verified.day == day else { return nil }
    return calendar.startOfDay(for: date)
  }
}
