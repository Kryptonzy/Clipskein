import Foundation

enum ClipNestDeepLink: Equatable, Sendable {
  static let maximumQueryLength = 500

  case open
  case search(String)
  case newSnippet
  case quickPicker(String)
  case snippets
  case textActions
  case board(String)

  var url: URL? {
    var components = URLComponents()
    components.scheme = "clipskein"

    switch self {
    case .open:
      components.host = "open"
    case .search(let query):
      components.host = "search"
      components.queryItems = [URLQueryItem(name: "q", value: query)]
    case .newSnippet:
      components.host = "new"
    case .quickPicker(let query):
      components.host = "picker"
      if !query.isEmpty {
        components.queryItems = [URLQueryItem(name: "q", value: query)]
      }
    case .snippets:
      components.host = "snippets"
    case .textActions:
      components.host = "actions"
    case .board(let name):
      components.host = "board"
      components.queryItems = [URLQueryItem(name: "name", value: name)]
    }

    guard let url = components.url, Self(url: url) != nil else { return nil }
    return url
  }

  init?(url: URL) {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let scheme = components.scheme?.lowercased(),
      scheme == "clipskein" || scheme == "clipnest",
      components.user == nil,
      components.password == nil,
      components.port == nil,
      components.fragment == nil,
      components.path.isEmpty || components.path == "/",
      let command = components.host?.lowercased(),
      !command.isEmpty
    else { return nil }

    let queryItems = components.queryItems ?? []
    switch command {
    case "open":
      guard queryItems.isEmpty else { return nil }
      self = .open
    case "search":
      guard let query = Self.singleValue(named: "q", in: queryItems),
        query.count <= Self.maximumQueryLength
      else { return nil }
      self = .search(query)
    case "new":
      guard queryItems.isEmpty else { return nil }
      self = .newSnippet
    case "picker":
      guard queryItems.allSatisfy({ $0.name == "q" }),
        queryItems.count <= 1
      else { return nil }
      let query = queryItems.first?.value ?? ""
      guard query.count <= Self.maximumQueryLength else { return nil }
      self = .quickPicker(query)
    case "snippets":
      guard queryItems.isEmpty else { return nil }
      self = .snippets
    case "actions":
      guard queryItems.isEmpty else { return nil }
      self = .textActions
    case "board":
      guard let rawName = Self.singleValue(named: "name", in: queryItems) else { return nil }
      let normalizedName = rawName.split(whereSeparator: \.isWhitespace).joined(separator: " ")
      guard !normalizedName.isEmpty, normalizedName.count <= ClipBoard.maximumNameLength else {
        return nil
      }
      self = .board(normalizedName)
    default:
      return nil
    }
  }

  private static func singleValue(named name: String, in items: [URLQueryItem]) -> String? {
    guard items.count == 1, items[0].name == name, let value = items[0].value else { return nil }
    return value
  }
}
