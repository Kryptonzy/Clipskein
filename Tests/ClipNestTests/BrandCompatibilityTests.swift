import CryptoKit
import Foundation
import Testing

@testable import ClipNest

@Suite(.serialized)
@MainActor
struct BrandCompatibilityTests {
  @Test func legacySourceLabelsDisplayCurrentBrandWithoutChangingStoredValues() {
    let groups: [(legacy: [String], english: String, chinese: String)] = [
      (["Created in ClipNest", "在 ClipNest 中创建"], "Created in Clipskein", "在 Clipskein 中创建"),
      (["Edited in ClipNest", "在 ClipNest 中编辑"], "Edited in Clipskein", "在 Clipskein 中编辑"),
      (["ClipNest Local Intelligence", "ClipNest 本地智能"], "Clipskein Local Intelligence", "Clipskein 本地智能"),
      (["ClipNest Local Translation", "ClipNest 本地翻译"], "Clipskein Local Translation", "Clipskein 本地翻译"),
    ]
    for group in groups {
      for source in group.legacy + [group.english, group.chinese] {
        let item = ClipItem(kind: .text, text: "Saved text", sourceApplication: source, fingerprint: "source-test")
        #expect(item.localizedSourceApplication(language: "en") == group.english)
        #expect(item.localizedSourceApplication(language: "zh-Hans") == group.chinese)
        #expect(item.sourceApplication == source)
      }
    }
  }

  @Test(arguments: ["clipskein", "clipnest"])
  func bothDeepLinkSchemesRejectUnsafeOrUnboundedCommands(scheme: String) {
    let invalidRoutes = [
      "user@search?q=invoice", "search/path?q=invoice", "search", "search?q=one&q=two",
      "new?text=secret", "unknown", "open#fragment", "open:123", "open?export=true",
      "search?q=\(String(repeating: "x", count: 501))",
      "board?name=\(String(repeating: "x", count: 33))",
    ]
    for route in invalidRoutes {
      #expect(URL(string: "\(scheme)://\(route)").flatMap(ClipNestDeepLink.init(url:)) == nil)
    }
  }

  @Test func legacyEncryptedHistoryLoadsAndSavesWithTheSameEnvelope() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let keyData = Data(repeating: 0x63, count: 32)
    let oldText = "History saved before the display-name change"
    let oldItem = ClipItem(
      kind: .text, text: oldText, sourceApplication: "Created in ClipNest",
      fingerprint: SHA256.hash(data: Data(oldText.utf8)).map { String(format: "%02x", $0) }.joined()
    )
    // Construct the legacy envelope independently of SecureLocalStorage.seal.
    let prefix = Data("CLIPNEST-SEALED\u{0}\u{1}".utf8)
    let sealed = try AES.GCM.seal(
      JSONEncoder().encode([oldItem]), using: SymmetricKey(data: keyData),
      nonce: AES.GCM.Nonce(data: Data(repeating: 0x24, count: 12))
    )
    let encrypted = prefix + (try #require(sealed.combined))
    let metadataURL = root.appendingPathComponent("clips.json")
    try encrypted.write(to: metadataURL)
    let protector = try SecureLocalStorage(keyData: keyData)
    let store = ClipStore(rootURL: root, startsMonitoring: false, storageProtector: protector)
    let loaded = try #require(store.items.first)
    #expect(loaded.id == oldItem.id)
    #expect(loaded.text == oldText)
    #expect(loaded.sourceApplication == "Created in ClipNest")
    #expect(loaded.localizedSourceApplication(language: "en") == "Created in Clipskein")
    store.addText("New history after rename", source: "Tests")
    let saved = try Data(contentsOf: metadataURL)
    #expect(saved.starts(with: prefix))
    let reloaded = ClipStore(rootURL: root, startsMonitoring: false, storageProtector: protector)
    #expect(Set(reloaded.items.map(\.text)) == [oldText, "New history after rename"])
    #expect(ClipArchive.fileExtension == "clipnestarchive")
  }
}
