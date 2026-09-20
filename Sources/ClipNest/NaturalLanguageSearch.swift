import Foundation

enum NaturalLanguageSearchFacet: Equatable, Sendable {
  case yesterday
  case today
  case lastSevenDays
  case thisWeek
  case lastWeek
  case thisMonth
  case images
  case files
  case receipts
  case links
  case emails
  case colors
  case json
  case unpinned
  case pinned
  case concealed
  case expiring
  case code
  case application(String)

  var fallbackLabel: String {
    switch self {
    case .yesterday: "Yesterday"
    case .today: "Today"
    case .lastSevenDays: "Last 7 days"
    case .thisWeek: "This week"
    case .lastWeek: "Last week"
    case .thisMonth: "This month"
    case .images: "Images"
    case .files: "Files"
    case .receipts: "Receipts & invoices"
    case .links: "Links"
    case .emails: "Emails"
    case .colors: "Colors"
    case .json: "JSON"
    case .unpinned: "Unpinned"
    case .pinned: "Pinned"
    case .concealed: "Concealed"
    case .expiring: "Expiring"
    case .code: "Code"
    case .application(let name): name
    }
  }

  func localizedLabel(language: String? = nil) -> String {
    switch self {
    case .application(let name): name
    case .json: "JSON"
    default:
      L10n.text(
        "search.facet.\(localizationKey)",
        fallback: fallbackLabel,
        language: language
      )
    }
  }

  private var localizationKey: String {
    switch self {
    case .yesterday: "yesterday"
    case .today: "today"
    case .lastSevenDays: "last_seven_days"
    case .thisWeek: "this_week"
    case .lastWeek: "last_week"
    case .thisMonth: "this_month"
    case .images: "images"
    case .files: "files"
    case .receipts: "receipts"
    case .links: "links"
    case .emails: "emails"
    case .colors: "colors"
    case .unpinned: "unpinned"
    case .pinned: "pinned"
    case .concealed: "concealed"
    case .expiring: "expiring"
    case .code: "code"
    case .json, .application: ""
    }
  }
}

struct NaturalLanguageSearch: Equatable, Sendable {
  let remainingQuery: String
  let applications: [String]
  let kinds: Set<ClipKind>
  let contentKinds: Set<ClipContentKind>
  let pinnedStates: Set<Bool>
  let concealedStates: Set<Bool>
  let expiringStates: Set<Bool>
  let createdOnOrAfter: Date?
  let createdBefore: Date?
  let facetTokens: [NaturalLanguageSearchFacet]

  var facets: [String] { facetTokens.map(\.fallbackLabel) }

  var isActive: Bool { !facetTokens.isEmpty }

  func localizedFacetLabels(language: String? = nil) -> [String] {
    facetTokens.map { $0.localizedLabel(language: language) }
  }

  static func interpret(
    _ rawQuery: String,
    knownApplications: [String],
    now: Date = .now,
    calendar: Calendar = .current
  ) -> NaturalLanguageSearch {
    if containsStructuredFilter(in: rawQuery) { return literal(rawQuery) }
    var working = rawQuery
    var applications: [String] = []
    var kinds: Set<ClipKind> = []
    var contentKinds: Set<ClipContentKind> = []
    var pinnedStates: Set<Bool> = []
    var concealedStates: Set<Bool> = []
    var expiringStates: Set<Bool> = []
    var after: Date?
    var before: Date?
    var facets: [NaturalLanguageSearchFacet] = []

    func addFacet(_ facet: NaturalLanguageSearchFacet) {
      guard !facets.contains(facet) else { return }
      facets.append(facet)
    }

    func consume(_ phrases: [String]) -> Bool {
      for phrase in phrases.sorted(by: { $0.count > $1.count }) {
        if let range = wholePhraseRange(of: phrase, in: working) {
          working.replaceSubrange(range, with: " ")
          return true
        }
      }
      return false
    }

    let startOfToday = calendar.startOfDay(for: now)
    if consume(["yesterday", "昨天"]) {
      after = calendar.date(byAdding: .day, value: -1, to: startOfToday)
      before = startOfToday
      addFacet(.yesterday)
    } else if consume(["today", "今天"]) {
      after = startOfToday
      before = calendar.date(byAdding: .day, value: 1, to: startOfToday)
      addFacet(.today)
    } else if consume(["last 7 days", "past 7 days", "过去7天", "最近7天"]) {
      after = calendar.date(byAdding: .day, value: -6, to: startOfToday)
      before = calendar.date(byAdding: .day, value: 1, to: startOfToday)
      addFacet(.lastSevenDays)
    } else if consume(["this week", "本周", "这周"]) {
      let interval = calendar.dateInterval(of: .weekOfYear, for: now)
      after = interval?.start
      before = interval?.end
      addFacet(.thisWeek)
    } else if consume(["last week", "上周"]) {
      let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now)
      let previousDate = currentWeek.flatMap {
        calendar.date(byAdding: .day, value: -1, to: $0.start)
      }
      let interval = previousDate.flatMap { calendar.dateInterval(of: .weekOfYear, for: $0) }
      after = interval?.start
      before = interval?.end
      addFacet(.lastWeek)
    } else if consume(["this month", "本月", "这个月"]) {
      let interval = calendar.dateInterval(of: .month, for: now)
      after = interval?.start
      before = interval?.end
      addFacet(.thisMonth)
    }

    if consume(["screenshots", "screenshot", "截图", "截屏", "images", "图片"]) {
      kinds.insert(.image)
      addFacet(.images)
    }
    if consume(["files", "文件"]) {
      kinds.insert(.files)
      addFacet(.files)
    }
    let hadPriorFacet = !facets.isEmpty
    let consumedReceiptFacet = consume([
      "receipts", "invoices", "收据", "收據", "发票", "發票", "订单凭证", "訂單憑證",
      "領収書", "請求書",
    ]) || (hadPriorFacet && consume(["receipt", "invoice"]))
    if consumedReceiptFacet {
      contentKinds.insert(.receipt)
      addFacet(.receipts)
    }
    if consume(["links", "链接"]) {
      contentKinds.insert(.link)
      addFacet(.links)
    }
    if consume(["emails", "email addresses", "邮件地址"]) {
      contentKinds.insert(.email)
      addFacet(.emails)
    }
    if consume(["colors", "colours", "颜色", "色值"]) {
      contentKinds.insert(.color)
      addFacet(.colors)
    }
    if consume(["json objects", "json 数据", "JSON数据"]) {
      contentKinds.insert(.json)
      addFacet(.json)
    }

    if consume(["unpinned", "未置顶"]) {
      pinnedStates.insert(false)
      addFacet(.unpinned)
    }
    if consume(["pinned", "favorites", "favourites", "置顶", "收藏"]) {
      pinnedStates.insert(true)
      addFacet(.pinned)
    }
    if consume(["concealed", "private", "隐藏", "私密"]) {
      concealedStates.insert(true)
      addFacet(.concealed)
    }
    if consume(["temporary", "expiring", "临时", "即将过期"]) {
      expiringStates.insert(true)
      addFacet(.expiring)
    }

    let hasStrongIntent = !facets.isEmpty
    if hasStrongIntent, consume(["code", "代码"]) {
      contentKinds.insert(.code)
      addFacet(.code)
    }
    if hasStrongIntent, consume(["json"]) {
      contentKinds.insert(.json)
      addFacet(.json)
    }

    if hasStrongIntent {
      for application in knownApplications.sorted(by: { $0.count > $1.count }) {
        let patterns = [
          "from \(application)", "in \(application)", "来自\(application)",
          "\(application)里的", "\(application) 中的", application,
        ]
        if consume(patterns) {
          applications.append(application)
          addFacet(.application(application))
          break
        }
      }
    }

    if !facets.isEmpty { working = removeConnectors(from: working) }
    return NaturalLanguageSearch(
      remainingQuery: working,
      applications: applications,
      kinds: kinds,
      contentKinds: contentKinds,
      pinnedStates: pinnedStates,
      concealedStates: concealedStates,
      expiringStates: expiringStates,
      createdOnOrAfter: after,
      createdBefore: before,
      facetTokens: facets
    )
  }

  static func literal(_ rawQuery: String) -> NaturalLanguageSearch {
    NaturalLanguageSearch(
      remainingQuery: rawQuery,
      applications: [],
      kinds: [],
      contentKinds: [],
      pinnedStates: [],
      concealedStates: [],
      expiringStates: [],
      createdOnOrAfter: nil,
      createdBefore: nil,
      facetTokens: []
    )
  }

  private static func containsStructuredFilter(in query: String) -> Bool {
    let keys = ["tag:", "app:", "type:", "kind:", "is:", "after:", "before:"]
    return query.split(whereSeparator: \Character.isWhitespace).contains { token in
      let normalized = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"")).lowercased()
      return keys.contains { normalized.hasPrefix($0) }
    }
  }

  private static func wholePhraseRange(of phrase: String, in source: String) -> Range<String.Index>?
  {
    var searchStart = source.startIndex
    while searchStart < source.endIndex,
      let range = source.range(
        of: phrase,
        options: [.caseInsensitive, .diacriticInsensitive],
        range: searchStart..<source.endIndex
      )
    {
      let startsWithWord = phrase.first?.isLetter == true || phrase.first?.isNumber == true
      let endsWithWord = phrase.last?.isLetter == true || phrase.last?.isNumber == true
      let leftIsBoundary =
        !startsWithWord || range.lowerBound == source.startIndex
        || !source[source.index(before: range.lowerBound)].isSearchIdentifierCharacter
      let rightIsBoundary =
        !endsWithWord || range.upperBound == source.endIndex
        || !source[range.upperBound].isSearchIdentifierCharacter
      if leftIsBoundary && rightIsBoundary { return range }
      searchStart = range.upperBound
    }
    return nil
  }

  private static func removeConnectors(from source: String) -> String {
    let connectors = ["from", "in", "of", "the", "的", "来自"]
    let words = source.split(whereSeparator: \Character.isWhitespace).map(String.init)
    let remaining = words.filter { word in
      !connectors.contains { connector in
        word.localizedCaseInsensitiveCompare(connector) == .orderedSame
      }
    }
    return remaining.joined(separator: " ")
  }
}

extension Character {
  fileprivate var isSearchIdentifierCharacter: Bool {
    isASCII && (isLetter || isNumber || "-_./@".contains(self))
  }
}
