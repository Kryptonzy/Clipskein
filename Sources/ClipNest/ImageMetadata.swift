import Foundation
import ImageIO

struct StoredImageMetadata: Codable, Hashable, Sendable {
  static let maximumPixelDimension = 1_000_000
  static let maximumByteCount = 2_000_000_000

  let pixelWidth: Int
  let pixelHeight: Int
  let byteCount: Int
  // Nil identifies older metadata that predates frame counting.
  let frameCount: Int?

  init?(pixelWidth: Int, pixelHeight: Int, byteCount: Int, frameCount: Int? = nil) {
    guard pixelWidth > 0, pixelWidth <= Self.maximumPixelDimension,
      pixelHeight > 0, pixelHeight <= Self.maximumPixelDimension,
      byteCount > 0, byteCount <= Self.maximumByteCount,
      frameCount.map({ $0 > 0 && $0 <= 1_000_000 }) ?? true
    else { return nil }
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    self.byteCount = byteCount
    self.frameCount = frameCount
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard
      let valid = Self(
        pixelWidth: try container.decode(Int.self, forKey: .pixelWidth),
        pixelHeight: try container.decode(Int.self, forKey: .pixelHeight),
        byteCount: try container.decode(Int.self, forKey: .byteCount),
        frameCount: try container.decodeIfPresent(Int.self, forKey: .frameCount)
      )
    else {
      throw DecodingError.dataCorruptedError(
        forKey: .pixelWidth,
        in: container,
        debugDescription: "Invalid stored image metadata"
      )
    }
    self = valid
  }

  var dimensionsText: String {
    L10n.format(
      "image.metadata.dimensions",
      fallback: "%d × %d",
      pixelWidth,
      pixelHeight
    )
  }

  var localizedSummary: String {
    L10n.format(
      "image.metadata.summary",
      fallback: "%@ · %@",
      dimensionsText,
      ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    )
  }

  var searchText: String {
    "\(pixelWidth)x\(pixelHeight) \(pixelWidth)×\(pixelHeight) \(pixelWidth) \(pixelHeight)"
  }
}

enum ImageMetadata {
  static func storedMetadata(for data: Data) -> StoredImageMetadata? {
    guard
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      CGImageSourceGetStatus(source) == .statusComplete,
      CGImageSourceGetCount(source) > 0,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
        as? [CFString: Any],
      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
    else { return nil }
    return StoredImageMetadata(
      pixelWidth: width, pixelHeight: height, byteCount: data.count,
      frameCount: CGImageSourceGetCount(source)
    )
  }

  static func isValidGIF(_ data: Data) -> Bool {
    guard hasCompleteGIFStructure(data),
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      CGImageSourceGetType(source) as String? == "com.compuserve.gif",
      CGImageSourceGetStatus(source) == .statusComplete,
      storedMetadata(for: data) != nil
    else { return false }
    return (0..<CGImageSourceGetCount(source)).allSatisfy {
      CGImageSourceGetStatusAtIndex(source, $0) == .statusComplete
    }
  }

  // ImageIO accepts a truncated GIF when its first frame is intact. Check the
  // complete block stream before preserving the original animation payload.
  private static func hasCompleteGIFStructure(_ data: Data) -> Bool {
    data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> Bool in
      guard bytes.count >= 14 else { return false }
      let header = String(decoding: bytes.prefix(6), as: UTF8.self)
      guard header == "GIF87a" || header == "GIF89a" else { return false }
      var offset = 13
      if bytes[10] & 0x80 != 0 {
        offset += 3 * (1 << (Int(bytes[10] & 0x07) + 1))
      }
      var frames = 0

      func skipDataBlocks() -> Bool {
        while offset < bytes.count {
          let count = Int(bytes[offset])
          offset += 1
          if count == 0 { return true }
          guard count <= bytes.count - offset else { return false }
          offset += count
        }
        return false
      }

      while offset < bytes.count {
        let marker = bytes[offset]
        offset += 1
        switch marker {
        case 0x3B:
          return frames > 0 && offset == bytes.count
        case 0x21:
          guard offset < bytes.count else { return false }
          offset += 1 // Extension label; its payload is a sequence of sub-blocks.
          guard skipDataBlocks() else { return false }
        case 0x2C:
          guard bytes.count - offset >= 9 else { return false }
          let packed = bytes[offset + 8]
          offset += 9
          if packed & 0x80 != 0 {
            offset += 3 * (1 << (Int(packed & 0x07) + 1))
          }
          guard offset < bytes.count, (2...8).contains(bytes[offset]) else { return false }
          offset += 1 // LZW minimum code size.
          guard skipDataBlocks() else { return false }
          frames += 1
        default:
          return false
        }
      }
      return false
    }
  }

  static func orientation(in source: CGImageSource, at index: Int = 0)
    -> CGImagePropertyOrientation
  {
    guard
      let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
        as? [CFString: Any],
      let rawValue = (properties[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value,
      let orientation = CGImagePropertyOrientation(rawValue: rawValue)
    else { return .up }
    return orientation
  }
}
