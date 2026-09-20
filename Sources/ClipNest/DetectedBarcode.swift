import Foundation

struct DetectedBarcode: Codable, Hashable, Sendable {
  static let maximumCount = 20
  static let maximumPayloadBytes = 16_384
  static let maximumSymbologyLength = 64

  let payload: String
  let symbology: String

  private enum CodingKeys: String, CodingKey {
    case payload, symbology
  }

  init?(payload: String, symbology: String) {
    guard !payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      payload.utf8.count <= Self.maximumPayloadBytes
    else { return nil }
    let normalizedSymbology = String(
      symbology.trimmingCharacters(in: .whitespacesAndNewlines)
        .prefix(Self.maximumSymbologyLength)
    )
    guard !normalizedSymbology.isEmpty else { return nil }
    self.payload = payload
    self.symbology = normalizedSymbology
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let payload = try container.decode(String.self, forKey: .payload)
    let symbology = try container.decode(String.self, forKey: .symbology)
    guard let validated = DetectedBarcode(payload: payload, symbology: symbology) else {
      throw DecodingError.dataCorruptedError(
        forKey: .payload,
        in: container,
        debugDescription: "Invalid barcode payload"
      )
    }
    self = validated
  }

  var isQRCode: Bool {
    let normalized = symbology.localizedLowercase
    return normalized == "qr" || normalized.contains("qr")
  }

  var localizedKind: String {
    localizedKind()
  }

  func localizedKind(language: String? = nil) -> String {
    if isQRCode {
      return L10n.text("barcode.kind.qr", fallback: "QR Code", language: language)
    }
    return L10n.text("barcode.kind.barcode", fallback: "Barcode", language: language)
  }

  var webURL: URL? {
    guard payload.utf8.count <= 8_192,
      let components = URLComponents(string: payload),
      let scheme = components.scheme?.localizedLowercase,
      ["http", "https"].contains(scheme),
      components.host?.isEmpty == false,
      components.user == nil,
      components.password == nil
    else { return nil }
    return components.url
  }

  static func normalized(_ barcodes: [DetectedBarcode]) -> [DetectedBarcode] {
    var seen = Set<String>()
    var result: [DetectedBarcode] = []
    for barcode in barcodes {
      guard let barcode = DetectedBarcode(
        payload: barcode.payload,
        symbology: barcode.symbology
      ) else { continue }
      let key = barcode.payload + "\u{0}" + barcode.symbology.localizedLowercase
      guard seen.insert(key).inserted else { continue }
      result.append(barcode)
      if result.count == maximumCount { break }
    }
    return result
  }
}
