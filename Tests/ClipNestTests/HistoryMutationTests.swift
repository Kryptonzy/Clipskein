import Foundation
import Testing

@testable import ClipNest

@Suite(.serialized)
@MainActor
struct HistoryMutationTests {
  @Test func capacityTrimSkipsPinnedTailStopsAtLimitAndPrunesStack() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let defaultsName = "HistoryMutationTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: defaultsName))
    defer {
      defaults.removePersistentDomain(forName: defaultsName)
      try? FileManager.default.removeItem(at: root)
    }
    defaults.set(8, forKey: "itemLimit")
    defaults.set(0, forKey: "retentionDays")
    let preferences = ClipPreferences(defaults: defaults)
    let protector = try SecureLocalStorage(keyData: Data(repeating: 0x52, count: 32))
    let store = ClipStore(
      rootURL: root, startsMonitoring: false, preferences: preferences,
      storageProtector: protector
    )
    store.addText("Pinned first", source: "Tests")
    let firstPin = try #require(store.items.first)
    store.togglePin(firstPin)
    store.addText("Pinned second", source: "Tests")
    let secondPin = try #require(store.items.first)
    store.togglePin(secondPin)

    // New captures prepend ahead of the pinned group. Trimming must walk past
    // the pinned tail before it reaches the oldest removable records.
    store.addText("Oldest removable", source: "Tests")
    let oldest = try #require(store.items.first)
    store.addText("Next removable", source: "Tests")
    let nextOldest = try #require(store.items.first)
    store.addText("Newest retained", source: "Tests")
    let retained = try #require(store.items.first)
    #expect(store.items.suffix(2).allSatisfy { $0.isPinned })
    #expect(store.addItemsToStack([oldest, firstPin, nextOldest, retained]) == 4)
    let removedIDs: Set<UUID> = [oldest.id, nextOldest.id]
    let retainedOrder = store.items.filter { !removedIDs.contains($0.id) }.map(\.id)

    preferences.itemLimit = 4
    store.addText("New head", source: "Tests")

    #expect(store.items.count == 4)
    #expect(store.items.first?.text == "New head")
    #expect(Array(store.items.dropFirst().map(\.id)) == retainedOrder)
    #expect(!store.items.contains { removedIDs.contains($0.id) })
    #expect(store.items.filter(\.isPinned).count == 2)
    #expect(store.stackIDs == [firstPin.id, retained.id])
    let reloaded = ClipStore(
      rootURL: root, startsMonitoring: false, preferences: preferences,
      storageProtector: protector
    )
    #expect(Set(reloaded.items.map(\.id)) == Set(store.items.map(\.id)))
    #expect(reloaded.stackIDs == [firstPin.id, retained.id])
    #expect(reloaded.storageIssue == nil)
  }

  @Test func capacityTrimKeepsAllPinnedHistoryEvenWhenItExceedsTheLimit() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let defaultsName = "HistoryMutationTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: defaultsName))
    defer {
      defaults.removePersistentDomain(forName: defaultsName)
      try? FileManager.default.removeItem(at: root)
    }
    defaults.set(8, forKey: "itemLimit")
    defaults.set(0, forKey: "retentionDays")
    let preferences = ClipPreferences(defaults: defaults)
    let protector = try SecureLocalStorage(keyData: Data(repeating: 0x53, count: 32))
    let store = ClipStore(
      rootURL: root, startsMonitoring: false, preferences: preferences,
      storageProtector: protector
    )
    for number in 1...3 {
      store.addText("Pinned \(number)", source: "Tests")
      store.togglePin(try #require(store.items.first))
    }
    let pinnedOrder = store.items.map(\.id)
    #expect(store.addItemsToStack(store.items) == 3)

    preferences.itemLimit = 1
    store.addText("Cannot evict pinned history", source: "Tests")

    #expect(store.items.map(\.id) == pinnedOrder)
    #expect(store.items.count > preferences.itemLimit)
    #expect(store.items.allSatisfy { $0.isPinned })
    #expect(store.stackIDs == pinnedOrder)
    #expect(store.selectedID.map { pinnedOrder.contains($0) } == true)
    let reloaded = ClipStore(
      rootURL: root, startsMonitoring: false, preferences: preferences,
      storageProtector: protector
    )
    #expect(reloaded.items.map(\.id) == pinnedOrder)
    #expect(reloaded.stackIDs == pinnedOrder)
    #expect(reloaded.storageIssue == nil)
  }
}
