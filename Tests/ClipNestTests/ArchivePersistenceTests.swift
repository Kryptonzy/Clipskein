import AppKit
import CryptoKit
import Foundation
import Testing

@testable import ClipNest

private final class ArchiveWriteGate: @unchecked Sendable {
  private let lock = NSLock()
  private let semaphore = DispatchSemaphore(value: 0)
  private var started = false

  var hasStarted: Bool {
    lock.lock()
    defer { lock.unlock() }
    return started
  }

  func wait() {
    lock.lock()
    started = true
    lock.unlock()
    _ = semaphore.wait(timeout: .now() + 5)
  }

  func release() { semaphore.signal() }
}

private final class ArchiveWriteFailureSwitch: @unchecked Sendable {
  private let lock = NSLock()
  private var fails = true

  func allowSuccess() {
    lock.lock()
    fails = false
    lock.unlock()
  }

  func write(_ items: [ClipItem], to url: URL, protector: SecureLocalStorage?) -> PersistenceWriteError? {
    lock.lock()
    let shouldFail = fails
    lock.unlock()
    if shouldFail { return PersistenceWriteError(message: "Injected archive write failure") }
    do {
      let data = try JSONEncoder().encode(items)
      let protected = try protector.map { try $0.seal(data) } ?? data
      try protected.write(to: url, options: .atomic)
      return nil
    } catch { return PersistenceWriteError(message: error.localizedDescription) }
  }
}

@Suite(.serialized)
@MainActor
struct ArchivePersistenceTests {
  private let password = "archive regression password"

  private func textArchive() throws -> Data {
    let text = "Imported archive text"
    let item = ClipItem(
      kind: .text, text: text, sourceApplication: "Archive tests",
      fingerprint: SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    )
    return try ClipArchive.seal(
      payload: ClipArchivePayload(exportedAt: .now, items: [item], images: [:]),
      password: password, keyIterations: 100
    )
  }

  @Test func archiveOperationsRejectUnlockingStorageWithoutChangingHistory() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let protector = try SecureLocalStorage(keyData: Data(repeating: 0x37, count: 32))
    let original = ClipStore(rootURL: root, startsMonitoring: false, storageProtector: protector)
    original.addText("Existing encrypted history", source: "Tests")
    let metadataURL = root.appendingPathComponent("clips.json")
    let before = try Data(contentsOf: metadataURL)
    let gate = ArchiveWriteGate()
    defer { gate.release() }
    let unlocking = ClipStore(
      rootURL: root, startsMonitoring: false, asynchronouslyLoadsStorageProtector: true,
      storageProtectorLoader: { gate.wait(); return protector },
      persistsHistoryInBackground: true
    )
    #expect(unlocking.isUnlockingStorage)
    do {
      _ = try unlocking.makeEncryptedArchive(password: password, keyIterations: 100)
      Issue.record("An unavailable store must not produce a successful empty backup")
    } catch {}
    do {
      _ = try await unlocking.makeEncryptedArchiveInBackground(password: password, keyIterations: 100)
      Issue.record("Background export must reject an unavailable store")
    } catch {}
    let archive = try textArchive()
    do {
      _ = try unlocking.importEncryptedArchive(archive, password: password)
      Issue.record("Synchronous import must reject an unavailable store")
    } catch {}
    do {
      _ = try await unlocking.importEncryptedArchiveInBackground(archive, password: password)
      Issue.record("Background import must reject an unavailable store")
    } catch {}
    #expect(unlocking.items.isEmpty)
    #expect(try Data(contentsOf: metadataURL) == before)
    gate.release()
    for _ in 0..<200 where unlocking.isUnlockingStorage {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(!unlocking.isUnlockingStorage)
    #expect(unlocking.items.map(\.text) == ["Existing encrypted history"])
  }

  @Test func archiveOperationsRejectUnreadableStorageWithoutChangingHistory() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let protector = try SecureLocalStorage(keyData: Data(repeating: 0x47, count: 32))
    let original = ClipStore(rootURL: root, startsMonitoring: false, storageProtector: protector)
    original.addText("Unreadable but recoverable history", source: "Tests")
    let metadataURL = root.appendingPathComponent("clips.json")
    let before = try Data(contentsOf: metadataURL)
    let wrongProtector = try SecureLocalStorage(keyData: Data(repeating: 0x48, count: 32))
    let unreadable = ClipStore(
      rootURL: root, startsMonitoring: false, storageProtector: wrongProtector,
      persistsHistoryInBackground: true
    )
    #expect(unreadable.storageIssue != nil)
    do {
      _ = try unreadable.makeEncryptedArchive(password: password, keyIterations: 100)
      Issue.record("Unreadable history must not be exported as an empty successful backup")
    } catch {}
    do {
      _ = try await unreadable.makeEncryptedArchiveInBackground(password: password, keyIterations: 100)
      Issue.record("Background export must reject unreadable history")
    } catch {}
    let archive = try textArchive()
    do {
      _ = try unreadable.importEncryptedArchive(archive, password: password)
      Issue.record("Synchronous import must reject unreadable history")
    } catch {}
    do {
      _ = try await unreadable.importEncryptedArchiveInBackground(archive, password: password)
      Issue.record("Background import must reject unreadable history")
    } catch {}
    #expect(unreadable.items.isEmpty)
    #expect(try Data(contentsOf: metadataURL) == before)
  }

  @Test func archiveImportWaitsForProductionBackgroundPersistenceBeforeReportingSuccess() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let protector = try SecureLocalStorage(keyData: Data(repeating: 0x57, count: 32))
    let gate = ArchiveWriteGate()
    defer { gate.release() }
    let destination = ClipStore(
      rootURL: root, startsMonitoring: false, storageProtector: protector,
      persistsHistoryInBackground: true,
      historyMetadataWriter: { items, url, protector, _ in
        gate.wait()
        do {
          let data = try JSONEncoder().encode(items)
          try protector!.seal(data).write(to: url, options: .atomic)
          return nil
        } catch { return PersistenceWriteError(message: error.localizedDescription) }
      }
    )
    let archive = try textArchive()
    var completed = false
    let operation = Task { @MainActor in
      let summary = try await destination.importEncryptedArchiveInBackground(archive, password: password)
      completed = true
      return summary
    }
    for _ in 0..<200 where !gate.hasStarted {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(gate.hasStarted)
    #expect(!completed, "Import must wait until the encrypted history is actually committed")
    gate.release()
    let summary = try await operation.value
    #expect(summary.added == 1)
    #expect(!destination.hasPendingHistoryPersistence)
    let reloaded = ClipStore(rootURL: root, startsMonitoring: false, storageProtector: protector)
    #expect(reloaded.items.map(\.text) == ["Imported archive text"])
    await destination.flushPendingHistoryPersistence()
  }

  @Test func archiveImportWriteFailureThrowsAndPreservesPreviouslySavedHistoryAndAttachments() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let protector = try SecureLocalStorage(keyData: Data(repeating: 0x67, count: 32))
    let defaultsName = "ArchivePersistenceTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: defaultsName))
    defer { defaults.removePersistentDomain(forName: defaultsName) }
    defaults.set(1, forKey: "itemLimit")
    let preferences = ClipPreferences(defaults: defaults)
    let original = ClipStore(
      rootURL: root, startsMonitoring: false, preferences: preferences, storageProtector: protector,
      imageAnalyzer: { _ in ImageAnalysisResult(ocr: .noText, barcodes: []) }
    )
    let png = try #require(Data(base64Encoded:
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
    _ = try #require(original.addImage(data: png, source: "Tests", createdAt: .now.addingTimeInterval(-60)))
    for _ in 0..<200 where original.pendingImageAnalysisCount > 0 {
      try await Task.sleep(for: .milliseconds(10))
    }
    let item = try #require(original.items.first)
    let fileName = try #require(item.imageFileName)
    let imageURL = root.appendingPathComponent("Images").appendingPathComponent(fileName)
    let savedImage = try Data(contentsOf: imageURL)
    let metadataURL = root.appendingPathComponent("clips.json")
    let before = try Data(contentsOf: metadataURL)
    let writer = ArchiveWriteFailureSwitch()
    let destination = ClipStore(
      rootURL: root, startsMonitoring: false, preferences: preferences, storageProtector: protector,
      persistsHistoryInBackground: true,
      historyMetadataWriter: { items, url, protector, _ in writer.write(items, to: url, protector: protector) }
    )
    do {
      _ = try await destination.importEncryptedArchiveInBackground(try textArchive(), password: password)
      Issue.record("A failed history write must not be reported as successful import")
    } catch {
      #expect(error.localizedDescription.contains("Injected archive write failure"))
    }
    await destination.flushPendingHistoryPersistence()
    #expect(try Data(contentsOf: metadataURL) == before)
    #expect(FileManager.default.fileExists(atPath: imageURL.path))
    if FileManager.default.fileExists(atPath: imageURL.path) {
      #expect(try Data(contentsOf: imageURL) == savedImage)
    }
    #expect(destination.storageIssue?.kind == .persistence)
    let reloaded = ClipStore(rootURL: root, startsMonitoring: false, preferences: preferences, storageProtector: protector)
    #expect(reloaded.items.contains { $0.id == item.id })
    #expect(destination.items.contains { $0.text == "Imported archive text" })
    writer.allowSuccess()
    destination.retryStorage()
    await destination.flushPendingHistoryPersistence()
    let recovered = ClipStore(rootURL: root, startsMonitoring: false, preferences: preferences, storageProtector: protector)
    #expect(recovered.items.map(\.text) == ["Imported archive text"])
    #expect(!FileManager.default.fileExists(atPath: imageURL.path))
  }

  @Test func archiveImportReportsCollectionMetadataWriteFailureAndCanRetry() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let protector = try SecureLocalStorage(keyData: Data(repeating: 0x77, count: 32))
    let store = ClipStore(
      rootURL: root, startsMonitoring: false, storageProtector: protector,
      persistsHistoryInBackground: true
    )
    store.addText("Original history", source: "Tests")
    await store.flushPendingHistoryPersistence()
    let blockedFile = root.appendingPathComponent("boards.json")
    try FileManager.default.createDirectory(at: blockedFile, withIntermediateDirectories: true)
    do {
      _ = try await store.importEncryptedArchiveInBackground(try textArchive(), password: password)
      Issue.record("A collection metadata failure must not report complete import success")
    } catch {}
    #expect(store.storageIssue?.kind == .persistence)
    #expect(store.items.contains { $0.text == "Original history" })
    #expect(store.items.contains { $0.text == "Imported archive text" })
    try FileManager.default.removeItem(at: blockedFile)
    store.retryStorage()
    await store.flushPendingHistoryPersistence()
    let reloaded = ClipStore(rootURL: root, startsMonitoring: false, storageProtector: protector)
    #expect(Set(reloaded.items.map(\.text)) == ["Original history", "Imported archive text"])
    #expect(reloaded.storageIssue == nil)
  }

  @Test func archiveImportDoesNotSilentlyDiscardRichTextWhenItsWriteFails() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let protector = try SecureLocalStorage(keyData: Data(repeating: 0x78, count: 32))
    let store = ClipStore(
      rootURL: root, startsMonitoring: false, storageProtector: protector,
      persistsHistoryInBackground: true
    )
    store.addText("Original history", source: "Tests")
    await store.flushPendingHistoryPersistence()
    let before = try Data(contentsOf: root.appendingPathComponent("clips.json"))
    let text = "Rich archive content"
    let id = UUID()
    let fileName = "\(id.uuidString).rtf"
    let rtf = try NSAttributedString(string: text).data(
      from: NSRange(location: 0, length: text.utf16.count),
      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
    )
    let item = ClipItem(
      id: id, kind: .text, text: text, richTextFileName: fileName,
      sourceApplication: "Archive tests",
      fingerprint: SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    )
    let data = try ClipArchive.seal(
      payload: ClipArchivePayload(exportedAt: .now, items: [item], images: [:], richText: [fileName: rtf]),
      password: password, keyIterations: 100
    )
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("RichText").appendingPathComponent(fileName),
      withIntermediateDirectories: true
    )
    do {
      _ = try await store.importEncryptedArchiveInBackground(data, password: password)
      Issue.record("A failed rich-text write must not become a successful plain-text import")
    } catch {}
    #expect(store.storageIssue?.kind == .persistence)
    #expect(try Data(contentsOf: root.appendingPathComponent("clips.json")) == before)
  }

  @Test func archiveImportDoesNotTreatImageWriteFailureAsAnInvalidEntry() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let protector = try SecureLocalStorage(keyData: Data(repeating: 0x79, count: 32))
    let store = ClipStore(
      rootURL: root, startsMonitoring: false, storageProtector: protector,
      persistsHistoryInBackground: true
    )
    store.addText("Original history", source: "Tests")
    await store.flushPendingHistoryPersistence()
    let before = try Data(contentsOf: root.appendingPathComponent("clips.json"))
    let png = try #require(Data(base64Encoded:
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
    let id = UUID()
    let fileName = "\(id.uuidString).png"
    let item = ClipItem(
      id: id, kind: .image, imageFileName: fileName, sourceApplication: "Archive tests",
      fingerprint: SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
    )
    let data = try ClipArchive.seal(
      payload: ClipArchivePayload(exportedAt: .now, items: [item], images: [fileName: png]),
      password: password, keyIterations: 100
    )
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("Images").appendingPathComponent(fileName),
      withIntermediateDirectories: true
    )
    do {
      _ = try await store.importEncryptedArchiveInBackground(data, password: password)
      Issue.record("A failed image write must not become a successful import with an invalid entry skipped")
    } catch {}
    #expect(store.storageIssue?.kind == .persistence)
    #expect(try Data(contentsOf: root.appendingPathComponent("clips.json")) == before)
  }
}
