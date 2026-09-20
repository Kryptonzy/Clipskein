import Foundation

struct ClipBoard: Identifiable, Codable, Hashable, Sendable {
  static let maximumCount = 16
  static let maximumNameLength = 32

  let id: UUID
  let name: String

  init(id: UUID = UUID(), name: String) {
    self.id = id
    self.name = name
  }
}
