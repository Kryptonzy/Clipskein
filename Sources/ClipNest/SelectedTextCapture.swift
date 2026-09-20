import AppKit
import ApplicationServices

enum SelectedTextCaptureResult: Sendable {
  case captured(ClipItem)
  case noSelection
  case permissionRequired
  case protectedApplication
  case clipboardPreservationUnavailable
  case selectionTooLarge
}

struct PasteboardSnapshot {
  struct Item {
    let representations: [(type: NSPasteboard.PasteboardType, data: Data)]
  }

  static let maximumBytes = 64 * 1_024 * 1_024
  let items: [Item]

  static func capture(
    from pasteboard: NSPasteboard,
    maximumBytes: Int = maximumBytes
  ) -> PasteboardSnapshot? {
    var totalBytes = 0
    var snapshots: [Item] = []
    let sourceItems = pasteboard.pasteboardItems
    if sourceItems == nil, !(pasteboard.types?.isEmpty ?? true) { return nil }
    for item in sourceItems ?? [] {
      var representations: [(type: NSPasteboard.PasteboardType, data: Data)] = []
      for type in item.types {
        guard let data = item.data(forType: type) else { return nil }
        totalBytes += data.count
        guard totalBytes <= maximumBytes else { return nil }
        representations.append((type, data))
      }
      snapshots.append(Item(representations: representations))
    }
    return PasteboardSnapshot(items: snapshots)
  }

  @discardableResult
  func restore(to pasteboard: NSPasteboard, ifUnchangedFrom expectedChangeCount: Int) -> Bool {
    guard pasteboard.changeCount == expectedChangeCount else { return false }
    pasteboard.clearContents()
    guard !items.isEmpty else { return true }
    let restoredItems = items.map { snapshot -> NSPasteboardItem in
      let item = NSPasteboardItem()
      for representation in snapshot.representations {
        item.setData(representation.data, forType: representation.type)
      }
      return item
    }
    return pasteboard.writeObjects(restoredItems)
  }
}

enum SelectedTextCapture {
  static func item(
    beforeChangeCount: Int,
    afterChangeCount: Int,
    text: String?,
    richTextData: Data? = nil,
    sourceName: String,
    sourceBundleIdentifier: String? = nil,
    maximumCharacters: Int? = TextTransformer.maximumInputLength,
    maximumUTF8Bytes: Int? = nil
  ) -> ClipItem? {
    guard afterChangeCount != beforeChangeCount, let text,
      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !exceedsLimit(
        text,
        maximumCharacters: maximumCharacters,
        maximumUTF8Bytes: maximumUTF8Bytes)
    else { return nil }
    return ClipItem(
      kind: .text,
      text: text,
      richTextData: RichTextPayload.validated(richTextData, matching: text),
      sourceApplication: sourceName,
      sourceBundleIdentifier: sourceBundleIdentifier,
      fingerprint: "selected:\(UUID().uuidString)"
    )
  }

  static func exceedsLimit(
    _ text: String,
    maximumCharacters: Int?,
    maximumUTF8Bytes: Int?
  ) -> Bool {
    if let maximumCharacters, text.count > maximumCharacters { return true }
    if let maximumUTF8Bytes, text.utf8.count > maximumUTF8Bytes { return true }
    return false
  }

  static func postCopyShortcut() -> Bool {
    guard let source = CGEventSource(stateID: .combinedSessionState),
      let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
      let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false)
    else { return false }
    keyDown.flags = .maskCommand
    keyUp.flags = .maskCommand
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
    return true
  }
}
