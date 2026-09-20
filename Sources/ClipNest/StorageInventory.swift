import Foundation

struct StorageInventory: Equatable, Sendable {
  let totalBytes: Int64
  let fileCount: Int
  let imageBytes: Int64
  let imageFileCount: Int
  let richTextBytes: Int64
  let richTextFileCount: Int
  let unusedBytes: Int64
  let unusedFileCount: Int
  let missingImageCount: Int
  let missingRichTextCount: Int

  var missingAttachmentCount: Int {
    missingImageCount + missingRichTextCount
  }
}

struct StorageCleanupResult: Equatable, Sendable {
  let removedBytes: Int64
  let removedFileCount: Int
  let failedFileCount: Int
}

enum StorageInventoryScanner {
  private struct StoredFile: Sendable {
    let url: URL
    let name: String
    let bytes: Int64
    let modificationDate: Date?
  }

  static func scan(
    rootURL: URL,
    referencedImageFileNames: Set<String>,
    referencedRichTextFileNames: Set<String>,
    fileManager: FileManager = .default
  ) -> StorageInventory {
    let imagesURL = rootURL.appendingPathComponent("Images", isDirectory: true)
    let richTextURL = rootURL.appendingPathComponent("RichText", isDirectory: true)
    let imageFiles = storedFiles(
      in: imagesURL, expectedExtensions: ["png", "gif"], fileManager: fileManager
    )
    let richTextFiles = storedFiles(
      in: richTextURL,
      expectedExtensions: ["rtf"],
      fileManager: fileManager
    )
    let allFiles = regularFilesRecursively(in: rootURL, fileManager: fileManager)
    let unusedImages = imageFiles.filter { !referencedImageFileNames.contains($0.name) }
    let unusedRichText = richTextFiles.filter { !referencedRichTextFileNames.contains($0.name) }
    let imageNames = Set(imageFiles.map(\.name))
    let richTextNames = Set(richTextFiles.map(\.name))

    return StorageInventory(
      totalBytes: allFiles.reduce(0) { $0 + $1.bytes },
      fileCount: allFiles.count,
      imageBytes: imageFiles.reduce(0) { $0 + $1.bytes },
      imageFileCount: imageFiles.count,
      richTextBytes: richTextFiles.reduce(0) { $0 + $1.bytes },
      richTextFileCount: richTextFiles.count,
      unusedBytes: (unusedImages + unusedRichText).reduce(0) { $0 + $1.bytes },
      unusedFileCount: unusedImages.count + unusedRichText.count,
      missingImageCount: referencedImageFileNames.subtracting(imageNames).count,
      missingRichTextCount: referencedRichTextFileNames.subtracting(richTextNames).count
    )
  }

  static func removeUnusedFiles(
    rootURL: URL,
    referencedImageFileNames: Set<String>,
    referencedRichTextFileNames: Set<String>,
    now: Date = .now,
    minimumAge: TimeInterval = 30,
    fileManager: FileManager = .default
  ) -> StorageCleanupResult {
    let candidates =
      storedFiles(
        in: rootURL.appendingPathComponent("Images", isDirectory: true),
        expectedExtensions: ["png", "gif"],
        fileManager: fileManager
      ).filter { !referencedImageFileNames.contains($0.name) }
      + storedFiles(
        in: rootURL.appendingPathComponent("RichText", isDirectory: true),
        expectedExtensions: ["rtf"],
        fileManager: fileManager
      ).filter { !referencedRichTextFileNames.contains($0.name) }

    var removedBytes: Int64 = 0
    var removedFileCount = 0
    var failedFileCount = 0
    for candidate in candidates {
      if let modificationDate = candidate.modificationDate,
        now.timeIntervalSince(modificationDate) < minimumAge
      {
        continue
      }
      do {
        try fileManager.removeItem(at: candidate.url)
        removedBytes += candidate.bytes
        removedFileCount += 1
      } catch {
        failedFileCount += 1
      }
    }
    return StorageCleanupResult(
      removedBytes: removedBytes,
      removedFileCount: removedFileCount,
      failedFileCount: failedFileCount
    )
  }

  private static func storedFiles(
    in directory: URL,
    expectedExtensions: Set<String>,
    fileManager: FileManager
  ) -> [StoredFile] {
    guard
      let urls = try? fileManager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [
          .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey,
        ],
        options: [.skipsHiddenFiles]
      )
    else { return [] }

    return urls.compactMap { url in
      guard expectedExtensions.contains(url.pathExtension.lowercased()),
        isOwnedAttachmentName(url.lastPathComponent, extension: url.pathExtension.lowercased()),
        let values = try? url.resourceValues(forKeys: [
          .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey,
        ]),
        values.isRegularFile == true,
        values.isSymbolicLink != true
      else { return nil }
      return StoredFile(
        url: url,
        name: url.lastPathComponent,
        bytes: Int64(values.fileSize ?? 0),
        modificationDate: values.contentModificationDate
      )
    }
  }

  private static func regularFilesRecursively(
    in directory: URL,
    fileManager: FileManager
  ) -> [StoredFile] {
    guard
      let enumerator = fileManager.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
      )
    else { return [] }

    var result: [StoredFile] = []
    for case let url as URL in enumerator {
      guard
        let values = try? url.resourceValues(forKeys: [
          .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
        ]),
        values.isRegularFile == true,
        values.isSymbolicLink != true
      else { continue }
      result.append(
        StoredFile(
          url: url,
          name: url.lastPathComponent,
          bytes: Int64(values.fileSize ?? 0),
          modificationDate: nil
        )
      )
    }
    return result
  }

  private static func isOwnedAttachmentName(_ name: String, extension expected: String) -> Bool {
    let url = URL(fileURLWithPath: name)
    guard url.pathExtension.lowercased() == expected,
      url.deletingPathExtension().lastPathComponent + "." + url.pathExtension == name
    else { return false }
    return UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil
  }
}
