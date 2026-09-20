import Foundation

enum ClipContextRelation: Sendable {
  case before
  case after
}

struct ClipContextEntry: Identifiable, Sendable {
  let item: ClipItem
  let relation: ClipContextRelation

  var id: UUID { item.id }
}

enum ClipContextTrail {
  static let defaultWindow: TimeInterval = 30 * 60
  static let defaultLimitPerDirection = 2

  static func entries(
    around selected: ClipItem,
    in items: [ClipItem],
    window: TimeInterval = defaultWindow,
    limitPerDirection: Int = defaultLimitPerDirection
  ) -> [ClipContextEntry] {
    guard window >= 0, limitPerDirection > 0 else { return [] }

    let candidates = items.filter {
      $0.id != selected.id && abs($0.createdAt.timeIntervalSince(selected.createdAt)) <= window
    }
    let before = candidates
      .filter { $0.createdAt <= selected.createdAt }
      .sorted(by: contextOrderDescending)
      .prefix(limitPerDirection)
      .reversed()
      .map { ClipContextEntry(item: $0, relation: .before) }
    let after = candidates
      .filter { $0.createdAt > selected.createdAt }
      .sorted(by: contextOrderAscending)
      .prefix(limitPerDirection)
      .map { ClipContextEntry(item: $0, relation: .after) }

    return before + after
  }

  private static func contextOrderAscending(_ lhs: ClipItem, _ rhs: ClipItem) -> Bool {
    if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
    return lhs.id.uuidString < rhs.id.uuidString
  }

  private static func contextOrderDescending(_ lhs: ClipItem, _ rhs: ClipItem) -> Bool {
    if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
    return lhs.id.uuidString > rhs.id.uuidString
  }
}
