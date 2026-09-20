import Foundation

struct SavedClipView: Identifiable, Codable, Hashable, Sendable {
  static let maximumCount = 12
  static let maximumNameLength = 40
  static let maximumQueryLength = 500

  let id: UUID
  let name: String
  let query: String
  let filter: ClipFilter
  let tag: String?
  let boardID: UUID?
  let interpretsNaturalLanguage: Bool

  init(
    id: UUID = UUID(),
    name: String,
    query: String,
    filter: ClipFilter,
    tag: String?,
    boardID: UUID? = nil,
    interpretsNaturalLanguage: Bool = true
  ) {
    self.id = id
    self.name = name
    self.query = query
    self.filter = filter
    self.tag = tag
    self.boardID = boardID
    self.interpretsNaturalLanguage = interpretsNaturalLanguage
  }

  func matches(
    query: String,
    filter: ClipFilter,
    tag: String?,
    boardID: UUID? = nil,
    interpretsNaturalLanguage: Bool = true
  ) -> Bool {
    self.query == query.trimmingCharacters(in: .whitespacesAndNewlines)
      && self.filter == filter
      && normalizedTag(self.tag) == normalizedTag(tag)
      && self.boardID == boardID
      && self.interpretsNaturalLanguage == interpretsNaturalLanguage
  }

  var criteriaDescription: String {
    criteriaDescription(language: nil)
  }

  func criteriaDescription(language: String?) -> String {
    var parts: [String] = []
    if filter != .all { parts.append(filter.localizedLabel(language: language)) }
    if let tag { parts.append("#\(tag)") }
    if boardID != nil {
      parts.append(L10n.text("saved_view.criteria.pinboard", fallback: "Pinboard", language: language))
    }
    if !interpretsNaturalLanguage {
      parts.append(
        L10n.text(
          "saved_view.criteria.literal", fallback: "Literal search", language: language))
    }
    if !query.isEmpty { parts.append("“\(query)”") }
    return parts.isEmpty
      ? L10n.text("saved_view.criteria.all", fallback: "All clips", language: language)
      : parts.joined(separator: " · ")
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, query, filter, tag, boardID, interpretsNaturalLanguage
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    query = try container.decode(String.self, forKey: .query)
    filter = try container.decode(ClipFilter.self, forKey: .filter)
    tag = try container.decodeIfPresent(String.self, forKey: .tag)
    boardID = try container.decodeIfPresent(UUID.self, forKey: .boardID)
    interpretsNaturalLanguage =
      try container.decodeIfPresent(Bool.self, forKey: .interpretsNaturalLanguage) ?? true
  }

  private func normalizedTag(_ value: String?) -> String? {
    value?.folding(
      options: [.caseInsensitive, .diacriticInsensitive],
      locale: .current
    )
  }
}
