import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ScreenshotFileSnapshot: Hashable, Sendable {
  let url: URL
  let modifiedAt: Date
  let byteCount: Int

  var identity: String {
    "\(url.standardizedFileURL.path)|\(modifiedAt.timeIntervalSince1970)|\(byteCount)"
  }
}

enum ScreenshotInbox {
  static let maximumExistingImportCount = 500
  private static let supportedExtensions: Set<String> = [
    "png", "jpg", "jpeg", "heic", "tif", "tiff",
  ]
  private static let knownNamePrefixes = [
    "screenshot",
    "screen shot",
    "capture d’écran",
    "capture d'ecran",
    "captura de pantalla",
    "bildschirmfoto",
    "schermata",
    "скриншот",
    "스크린샷",
    "截屏",
    "屏幕截图",
    "螢幕截圖",
  ]

  static func configuredDirectory(
    screenCaptureDefaults: UserDefaults = UserDefaults(suiteName: "com.apple.screencapture")
      ?? .standard,
    fileManager: FileManager = .default
  ) -> URL {
    if let storedPath = screenCaptureDefaults.string(forKey: "location"), !storedPath.isEmpty {
      let expanded = (storedPath as NSString).expandingTildeInPath
      return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
    }
    return fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first
      ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
        "Desktop", isDirectory: true)
  }

  static func isLikelyScreenshot(_ url: URL) -> Bool {
    guard supportedExtensions.contains(url.pathExtension.lowercased()) else { return false }
    let name = url.deletingPathExtension().lastPathComponent
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .lowercased()
    return knownNamePrefixes.contains { name.hasPrefix($0) }
  }

  static func snapshots(
    in directory: URL,
    fileManager: FileManager = .default
  ) throws -> [ScreenshotFileSnapshot] {
    let keys: Set<URLResourceKey> = [
      .isRegularFileKey,
      .contentModificationDateKey,
      .fileSizeKey,
    ]
    return try fileManager.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: Array(keys),
      options: [.skipsHiddenFiles]
    )
    .compactMap { url in
      guard isLikelyScreenshot(url) else { return nil }
      let values = try? url.resourceValues(forKeys: keys)
      guard values?.isRegularFile == true,
        let modifiedAt = values?.contentModificationDate,
        let byteCount = values?.fileSize,
        byteCount > 0
      else { return nil }
      return ScreenshotFileSnapshot(url: url, modifiedAt: modifiedAt, byteCount: byteCount)
    }
    .sorted { $0.modifiedAt < $1.modifiedAt }
  }

  static func pngData(at url: URL) -> Data? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return pngData(from: source)
  }

  static func pngData(from data: Data) -> Data? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return pngData(from: source)
  }

  private static func pngData(from source: CGImageSource) -> Data? {
    guard
      CGImageSourceGetCount(source) > 0,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
        as? [CFString: Any],
      let pixelWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
      let pixelHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
      pixelWidth > 0,
      pixelHeight > 0,
      let image = CGImageSourceCreateThumbnailAtIndex(
        source,
        0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: max(pixelWidth, pixelHeight),
          kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary
      )
    else { return nil }

    let output = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        output,
        UTType.png.identifier as CFString,
        1,
        nil
      )
    else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return output as Data
  }

  static func readyCandidates(
    from snapshots: [ScreenshotFileSnapshot],
    excluding seenIdentities: Set<String>,
    startedAt: Date,
    now: Date = .now,
    settlingDelay: TimeInterval = 0.75
  ) -> [ScreenshotFileSnapshot] {
    snapshots.filter { snapshot in
      snapshot.modifiedAt >= startedAt
        && now.timeIntervalSince(snapshot.modifiedAt) >= settlingDelay
        && !seenIdentities.contains(snapshot.identity)
    }
  }

  static func existingImportCandidates(
    from snapshots: [ScreenshotFileSnapshot],
    limit: Int = maximumExistingImportCount
  ) -> [ScreenshotFileSnapshot] {
    guard limit > 0 else { return [] }
    let boundedLimit = min(limit, maximumExistingImportCount)
    return Array(
      snapshots.sorted { $0.modifiedAt < $1.modifiedAt }.suffix(boundedLimit)
    )
  }
}
