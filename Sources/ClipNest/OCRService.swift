import Foundation
import ImageIO
import Vision

enum OCRResult: Sendable, Equatable {
  case recognized(String)
  case noText
  case failed
}

struct ImageAnalysisResult: Sendable, Equatable {
  let ocr: OCRResult
  let barcodes: [DetectedBarcode]
  let ocrConfidence: Float?

  init(ocr: OCRResult, barcodes: [DetectedBarcode], ocrConfidence: Float? = nil) {
    self.ocr = ocr
    self.barcodes = barcodes
    if case .recognized = ocr, let ocrConfidence,
      ocrConfidence.isFinite, (0...1).contains(ocrConfidence)
    {
      self.ocrConfidence = ocrConfidence
    } else {
      self.ocrConfidence = nil
    }
  }
}

enum OCRService {
  static let maximumCustomWordCount = 50
  static let maximumCustomWordLength = 64

  static let configurableRecognitionLanguages = [
    "en-US", "zh-Hans", "zh-Hant", "ja-JP", "ko-KR", "fr-FR", "de-DE", "es-ES",
    "it-IT", "pt-BR",
  ]

  private static let fallbackRecognitionLanguages = [
    "en-US", "fr-FR", "de-DE", "es-ES", "it-IT", "pt-BR", "zh-Hans", "zh-Hant",
    "ja-JP", "ko-KR",
  ]

  static func preferredRecognitionLanguages(
    preferred: [String],
    supported: [String],
    limit: Int = 10
  ) -> [String] {
    guard limit > 0, !supported.isEmpty else { return [] }
    var result: [String] = []
    var used = Set<String>()

    func normalized(_ identifier: String) -> String {
      identifier.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    func appendBestMatch(for requested: String) {
      guard result.count < limit else { return }
      let requestedID = normalized(requested)
      let requestedLanguage = requestedID.split(separator: "-").first.map(String.init) ?? requestedID
      let candidate = supported.first { normalized($0) == requestedID }
        ?? supported.first {
          let supportedID = normalized($0)
          return requestedID.hasPrefix(supportedID + "-")
            || supportedID.hasPrefix(requestedID + "-")
        }
        ?? supported.first {
          normalized($0).split(separator: "-").first.map(String.init) == requestedLanguage
        }
      guard let candidate else { return }
      let key = normalized(candidate)
      guard used.insert(key).inserted else { return }
      result.append(candidate)
    }

    for language in preferred + fallbackRecognitionLanguages {
      appendBestMatch(for: language)
      if result.count == limit { break }
    }
    return result
  }

  static func recognizeText(in imageData: Data) async -> OCRResult {
    await analyzeImage(imageData).ocr
  }

  static func detectBarcodes(in imageData: Data) async -> [DetectedBarcode] {
    await analyzeImage(imageData).barcodes
  }

  static func supportedRecognitionLanguages() -> [String] {
    let request = VNRecognizeTextRequest()
    return (try? request.supportedRecognitionLanguages()) ?? []
  }

  static func supportedConfigurableRecognitionLanguages(
    supported: [String]
  ) -> [String] {
    configurableRecognitionLanguages.filter { requested in
      bestSupportedLanguage(for: requested, supported: supported) != nil
    }
  }

  static func bestSupportedLanguage(for requested: String, supported: [String]) -> String? {
    let requestedID = normalizedLanguageIdentifier(requested)
    let requestedLanguage = requestedID.split(separator: "-").first.map(String.init) ?? requestedID
    return supported.first { normalizedLanguageIdentifier($0) == requestedID }
      ?? supported.first {
        let supportedID = normalizedLanguageIdentifier($0)
        return requestedID.hasPrefix(supportedID + "-")
          || supportedID.hasPrefix(requestedID + "-")
      }
      ?? supported.first {
        normalizedLanguageIdentifier($0).split(separator: "-").first.map(String.init)
          == requestedLanguage
      }
  }

  static func analyzeImage(
    _ imageData: Data,
    preferredLanguages: [String] = [],
    customWords: [String] = []
  ) async -> ImageAnalysisResult {
    await Task.detached(priority: .utility) {
      guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
        let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
      else { return ImageAnalysisResult(ocr: .failed, barcodes: []) }
      let orientation = ImageMetadata.orientation(in: source)

      let textRequest = VNRecognizeTextRequest()
      textRequest.recognitionLevel = .accurate
      textRequest.usesLanguageCorrection = true
      textRequest.automaticallyDetectsLanguage = true
      textRequest.customWords = normalizedCustomWords(customWords)
      if let supported = try? textRequest.supportedRecognitionLanguages() {
        let languages = preferredRecognitionLanguages(
          preferred: preferredLanguages.isEmpty ? Locale.preferredLanguages : preferredLanguages,
          supported: supported
        )
        if !languages.isEmpty { textRequest.recognitionLanguages = languages }
      }
      let barcodeRequest = VNDetectBarcodesRequest()

      do {
        try VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
          .perform([textRequest, barcodeRequest])
        let candidates = (textRequest.results ?? [])
          .compactMap { $0.topCandidates(1).first }
        let text = candidates
          .map(\.string)
          .joined(separator: "\n")
          .trimmingCharacters(in: .whitespacesAndNewlines)
        let confidenceWeight = candidates.reduce(0) { $0 + max($1.string.count, 1) }
        let confidence = confidenceWeight > 0
          ? candidates.reduce(Float(0)) { partial, candidate in
            partial + candidate.confidence * Float(max(candidate.string.count, 1))
          } / Float(confidenceWeight)
          : nil
        let barcodes = DetectedBarcode.normalized(
          (barcodeRequest.results ?? []).compactMap { observation in
            guard let payload = observation.payloadStringValue else { return nil }
            return DetectedBarcode(
              payload: payload,
              symbology: observation.symbology.rawValue
            )
          }
        )
        return ImageAnalysisResult(
          ocr: text.isEmpty ? .noText : .recognized(text),
          barcodes: barcodes,
          ocrConfidence: confidence
        )
      } catch {
        return ImageAnalysisResult(ocr: .failed, barcodes: [])
      }
    }.value
  }

  private static func normalizedLanguageIdentifier(_ identifier: String) -> String {
    identifier.replacingOccurrences(of: "_", with: "-").lowercased()
  }

  static func normalizedCustomWords(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var normalized: [String] = []
    normalized.reserveCapacity(min(values.count, maximumCustomWordCount))
    for value in values {
      let word = value
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
      guard !word.isEmpty, word.count <= maximumCustomWordLength,
        !word.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
      else { continue }
      let key = word.folding(
        options: [.caseInsensitive, .diacriticInsensitive],
        locale: Locale(identifier: "en_US_POSIX")
      )
      guard seen.insert(key).inserted else { continue }
      normalized.append(word)
      if normalized.count == maximumCustomWordCount { break }
    }
    return normalized
  }
}
