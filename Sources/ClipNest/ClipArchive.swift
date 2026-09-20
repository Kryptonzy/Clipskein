import CryptoKit
import Foundation
import Security

enum ClipArchiveError: LocalizedError, Equatable {
  case passwordTooShort
  case invalidArchive
  case unsupportedVersion
  case wrongPasswordOrCorruptArchive
  case randomGenerationFailed
  case missingLocalImage(String)
  case missingLocalRichText(String)

  var errorDescription: String? {
    switch self {
    case .passwordTooShort:
      L10n.text(
        "archive.error.password_short", fallback: "Use a password with at least 8 characters.")
    case .invalidArchive:
      L10n.text(
        "archive.error.invalid", fallback: "This file is not a valid Clipskein archive.")
    case .unsupportedVersion:
      L10n.text(
        "archive.error.unsupported",
        fallback: "This archive was created by an unsupported Clipskein version.")
    case .wrongPasswordOrCorruptArchive:
      L10n.text(
        "archive.error.password_or_damage",
        fallback: "The password is incorrect, or the archive is damaged.")
    case .randomGenerationFailed:
      L10n.text(
        "archive.error.random", fallback: "Clipskein could not generate secure random data.")
    case .missingLocalImage(let fileName):
      L10n.format(
        "archive.error.missing_image",
        fallback: "The local image %@ is missing, so the backup could not be completed.",
        fileName)
    case .missingLocalRichText(let fileName):
      L10n.format(
        "archive.error.missing_rich_text",
        fallback: "The local rich-text file %@ is missing, so the backup could not be completed.",
        fileName)
    }
  }

  var recoverySuggestion: String? {
    switch self {
    case .passwordTooShort:
      L10n.text(
        "archive.recovery.password_short", fallback: "Choose a longer password and try again.")
    case .invalidArchive:
      L10n.text(
        "archive.recovery.invalid", fallback: "Choose another .clipnestarchive file and try again.")
    case .unsupportedVersion:
      L10n.text(
        "archive.recovery.unsupported",
        fallback: "Update Clipskein, then try importing this backup again.")
    case .wrongPasswordOrCorruptArchive:
      L10n.text(
        "archive.recovery.password_or_damage",
        fallback: "Check the password. If it is correct, choose another copy of the backup.")
    case .randomGenerationFailed:
      L10n.text(
        "archive.recovery.random", fallback: "Try creating the backup again.")
    case .missingLocalImage, .missingLocalRichText:
      L10n.text(
        "archive.recovery.missing_file",
        fallback: "Open Clipskein storage to check the missing file, then create the backup again.")
    }
  }
}

struct ClipArchivePayload: Codable, Sendable {
  let exportedAt: Date
  let items: [ClipItem]
  let images: [String: Data]
  let richText: [String: Data]
  let stackFingerprints: [String]
  let savedViews: [SavedClipView]
  let boards: [ClipBoard]

  init(
    exportedAt: Date,
    items: [ClipItem],
    images: [String: Data],
    richText: [String: Data] = [:],
    stackFingerprints: [String] = [],
    savedViews: [SavedClipView] = [],
    boards: [ClipBoard] = []
  ) {
    self.exportedAt = exportedAt
    self.items = items
    self.images = images
    self.richText = richText
    self.stackFingerprints = stackFingerprints
    self.savedViews = savedViews
    self.boards = boards
  }

  private enum CodingKeys: String, CodingKey {
    case exportedAt, items, images, richText, stackFingerprints, savedViews, boards
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    exportedAt = try container.decode(Date.self, forKey: .exportedAt)
    items = try container.decode([ClipItem].self, forKey: .items)
    images = try container.decode([String: Data].self, forKey: .images)
    richText = try container.decodeIfPresent([String: Data].self, forKey: .richText) ?? [:]
    stackFingerprints =
      try container.decodeIfPresent([String].self, forKey: .stackFingerprints) ?? []
    savedViews = try container.decodeIfPresent([SavedClipView].self, forKey: .savedViews) ?? []
    boards = try container.decodeIfPresent([ClipBoard].self, forKey: .boards) ?? []
  }
}

private struct ClipArchiveEnvelope: Codable {
  let formatVersion: Int
  let keyIterations: Int
  let salt: Data
  let sealedPayload: Data
}

enum ClipArchive {
  // Keep the established backup format/extension readable across the Clipskein rename.
  static let fileExtension = "clipnestarchive"
  static let productionKeyIterations = 210_000

  static func seal(
    payload: ClipArchivePayload,
    password: String,
    keyIterations: Int = productionKeyIterations
  ) throws -> Data {
    guard password.count >= 8 else { throw ClipArchiveError.passwordTooShort }
    guard (1...1_000_000).contains(keyIterations) else {
      throw ClipArchiveError.invalidArchive
    }

    let salt = try secureRandomData(count: 16)
    let key = try deriveKey(password: password, salt: salt, iterations: keyIterations)
    try Task.checkCancellation()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let payloadData = try encoder.encode(payload)
    try Task.checkCancellation()
    let sealed = try AES.GCM.seal(payloadData, using: key)
    guard let combined = sealed.combined else { throw ClipArchiveError.invalidArchive }

    let envelope = ClipArchiveEnvelope(
      formatVersion: 1,
      keyIterations: keyIterations,
      salt: salt,
      sealedPayload: combined
    )
    return try encoder.encode(envelope)
  }

  static func open(data: Data, password: String) throws -> ClipArchivePayload {
    guard !data.isEmpty, data.count <= 2_000_000_000 else {
      throw ClipArchiveError.invalidArchive
    }
    let envelope: ClipArchiveEnvelope
    do {
      envelope = try JSONDecoder().decode(ClipArchiveEnvelope.self, from: data)
    } catch {
      throw ClipArchiveError.invalidArchive
    }
    guard envelope.formatVersion == 1 else { throw ClipArchiveError.unsupportedVersion }
    guard (1...1_000_000).contains(envelope.keyIterations),
      (16...64).contains(envelope.salt.count),
      !envelope.sealedPayload.isEmpty
    else {
      throw ClipArchiveError.invalidArchive
    }

    do {
      let key = try deriveKey(
        password: password,
        salt: envelope.salt,
        iterations: envelope.keyIterations
      )
      try Task.checkCancellation()
      let box = try AES.GCM.SealedBox(combined: envelope.sealedPayload)
      let decrypted = try AES.GCM.open(box, using: key)
      try Task.checkCancellation()
      let payload = try JSONDecoder().decode(ClipArchivePayload.self, from: decrypted)
      let itemFingerprints = Set(payload.items.map(\.fingerprint))
      let aliases = payload.items.compactMap(\.alias)
      let richTextFileNames = payload.items.compactMap(\.richTextFileName)
      let savedViewIDs = Set(payload.savedViews.map(\.id))
      let savedViewNames = Set(payload.savedViews.map { SearchMatcher.normalize($0.name) })
      let boardIDs = Set(payload.boards.map(\.id))
      let boardNames = Set(payload.boards.map { SearchMatcher.normalize($0.name) })
      guard payload.items.count <= 100_000,
        payload.images.count <= 100_000,
        payload.richText.count <= 100_000,
        Set(richTextFileNames).count == richTextFileNames.count,
        Set(payload.richText.keys) == Set(richTextFileNames),
        payload.stackFingerprints.count <= ClipStore.maximumStackCount,
        payload.savedViews.count <= SavedClipView.maximumCount,
        payload.boards.count <= ClipBoard.maximumCount,
        boardIDs.count == payload.boards.count,
        boardNames.count == payload.boards.count,
        payload.boards.allSatisfy({
          !$0.name.isEmpty && $0.name == ClipStore.normalizedBoardName($0.name)
        }),
        savedViewIDs.count == payload.savedViews.count,
        savedViewNames.count == payload.savedViews.count,
        payload.savedViews.allSatisfy({
          !$0.name.isEmpty
            && $0.name == ClipStore.normalizedSavedViewName($0.name)
            && $0.query.count <= SavedClipView.maximumQueryLength
            && $0.tag.map({ !$0.isEmpty && $0.count <= ClipStore.maximumTagLength }) ?? true
            && $0.boardID.map(boardIDs.contains) ?? true
        }),
        Set(payload.stackFingerprints).count == payload.stackFingerprints.count,
        payload.stackFingerprints.allSatisfy({
          !$0.isEmpty && $0.utf8.count <= 512 && itemFingerprints.contains($0)
        }),
        payload.items.allSatisfy({
          (0...10_000_000).contains($0.useCount)
            && $0.text.utf8.count <= 20_000_000
            && $0.ocrText.utf8.count <= 20_000_000
            && $0.ocrConfidence.map({ $0.isFinite && (0...1).contains($0) }) ?? true
            && $0.detectedBarcodes.count <= DetectedBarcode.maximumCount
            && $0.detectedBarcodes.allSatisfy {
              !$0.payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.payload.utf8.count <= DetectedBarcode.maximumPayloadBytes
                && !$0.symbology.isEmpty
                && $0.symbology.count <= DetectedBarcode.maximumSymbologyLength
            }
            && $0.filePaths.count <= ClipStore.maximumFilesPerClip
            && $0.filePaths.allSatisfy { !$0.isEmpty && $0.utf8.count <= 16_384 }
            && ($0.customTitle?.utf8.count ?? 0) <= 1_024
            && $0.alias.map(ClipAlias.isValidStored) ?? true
            && $0.tags.count <= ClipStore.maximumTagCount
            && $0.tags.allSatisfy { !$0.isEmpty && $0.count <= ClipStore.maximumTagLength }
            && $0.boardIDs.count <= ClipBoard.maximumCount
            && Set($0.boardIDs).count == $0.boardIDs.count
            && $0.boardIDs.allSatisfy(boardIDs.contains)
            && $0.sourceApplication.utf8.count <= 4_096
            && $0.sourceBundleIdentifier.map {
              ClipItem.normalizedSourceBundleIdentifier($0) == $0
            } ?? true
        }),
        payload.items.allSatisfy({ item in
          if item.kind == .files {
            return !item.filePaths.isEmpty
              && Set(item.filePaths).count == item.filePaths.count
              && item.filePaths.allSatisfy {
                URL(fileURLWithPath: $0).standardizedFileURL.path == $0
              }
          }
          return item.filePaths.isEmpty
        }),
        payload.items.allSatisfy({ item in
          guard item.kind == .text else {
            return item.richTextFileName == nil && item.richTextData == nil
          }
          if let inline = item.richTextData {
            return item.richTextFileName == nil
              && RichTextPayload.isValid(inline, matching: item.text)
          }
          guard let fileName = item.richTextFileName else { return true }
          return fileName == URL(fileURLWithPath: fileName).lastPathComponent
            && fileName.utf8.count <= 255
            && payload.richText[fileName].map {
              RichTextPayload.isValid($0, matching: item.text)
            } ?? false
        }),
        payload.images.allSatisfy({ key, value in
          !key.isEmpty && key.utf8.count <= 255 && value.count <= 100_000_000
        }),
        payload.richText.allSatisfy({ key, value in
          !key.isEmpty && key.utf8.count <= 255 && value.count <= ClipItem.maximumRichTextBytes
        }),
        Set(aliases).count == aliases.count
      else {
        throw ClipArchiveError.invalidArchive
      }
      return payload
    } catch let error as ClipArchiveError {
      throw error
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw ClipArchiveError.wrongPasswordOrCorruptArchive
    }
  }

  private static func deriveKey(password: String, salt: Data, iterations: Int) throws
    -> SymmetricKey
  {
    try Task.checkCancellation()
    let passwordKey = SymmetricKey(data: Data(password.utf8))
    var block = salt
    block.append(contentsOf: [0, 0, 0, 1])

    var current = Data(HMAC<SHA256>.authenticationCode(for: block, using: passwordKey))
    var derived = [UInt8](current)
    if iterations > 1 {
      for iteration in 1..<iterations {
        if iteration.isMultiple(of: 4_096) { try Task.checkCancellation() }
        current = Data(HMAC<SHA256>.authenticationCode(for: current, using: passwordKey))
        let bytes = [UInt8](current)
        for index in derived.indices { derived[index] ^= bytes[index] }
      }
    }
    return SymmetricKey(data: Data(derived))
  }

  private static func secureRandomData(count: Int) throws -> Data {
    var bytes = [UInt8](repeating: 0, count: count)
    guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
      throw ClipArchiveError.randomGenerationFailed
    }
    return Data(bytes)
  }
}
