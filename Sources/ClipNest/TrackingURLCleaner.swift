import Foundation

enum TrackingURLCleaner {
  private static let trackingNames: Set<String> = [
    "dclid",
    "fbclid",
    "gclid",
    "igshid",
    "mc_cid",
    "mc_eid",
    "mkt_tok",
    "msclkid",
    "vero_conv",
    "vero_id",
    "_hsenc",
    "_hsmi",
  ]

  static func clean(_ input: String) -> String? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard var components = URLComponents(string: trimmed),
      let scheme = components.scheme?.lowercased(),
      scheme == "https" || scheme == "http",
      let host = components.host?.lowercased(),
      components.user == nil,
      components.password == nil,
      let originalItems = components.queryItems,
      !originalItems.isEmpty
    else { return nil }

    let cleanedItems = originalItems.filter { item in
      !isTrackingParameter(item.name, host: host)
    }
    guard cleanedItems.count != originalItems.count else { return nil }
    components.queryItems = cleanedItems.isEmpty ? nil : cleanedItems
    guard let cleaned = components.string, cleaned != trimmed else { return nil }
    return cleaned
  }

  private static func isTrackingParameter(_ name: String, host: String) -> Bool {
    let normalized = name.lowercased()
    if normalized.hasPrefix("utm_") || trackingNames.contains(normalized) { return true }
    if normalized == "si" {
      return host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com")
    }
    return false
  }
}
