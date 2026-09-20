import Foundation

enum ClipKind: String, Codable, CaseIterable, Sendable {
  case text
  case image
  case files
}

enum OCRState: String, Codable, Sendable {
  case notApplicable
  case pending
  case complete
  case noText
  case failed
}

struct ClipItem: Identifiable, Codable, Hashable, Sendable {
  static let maximumRichTextBytes = 2_000_000
  static let lowOCRConfidenceThreshold: Float = 0.60

  let id: UUID
  let kind: ClipKind
  var text: String
  var ocrText: String
  var ocrState: OCRState
  var ocrConfidence: Float?
  var detectedBarcodes: [DetectedBarcode]
  var imageFileName: String?
  var imageMetadata: StoredImageMetadata?
  var filePaths: [String]
  var customTitle: String?
  var alias: String?
  var richTextFileName: String?
  var richTextData: Data?
  var tags: [String]
  var boardIDs: [UUID]
  var isConcealed: Bool
  var sourceApplication: String
  var sourceBundleIdentifier: String?
  var createdAt: Date
  var isPinned: Bool
  var useCount: Int
  var lastUsedAt: Date?
  var expiresAt: Date?
  let fingerprint: String

  init(
    id: UUID = UUID(),
    kind: ClipKind,
    text: String = "",
    ocrText: String = "",
    ocrState: OCRState? = nil,
    ocrConfidence: Float? = nil,
    detectedBarcodes: [DetectedBarcode] = [],
    imageFileName: String? = nil,
    imageMetadata: StoredImageMetadata? = nil,
    filePaths: [String] = [],
    customTitle: String? = nil,
    alias: String? = nil,
    richTextFileName: String? = nil,
    richTextData: Data? = nil,
    tags: [String] = [],
    boardIDs: [UUID] = [],
    isConcealed: Bool = false,
    sourceApplication: String = "Unknown app",
    sourceBundleIdentifier: String? = nil,
    createdAt: Date = .now,
    isPinned: Bool = false,
    useCount: Int = 0,
    lastUsedAt: Date? = nil,
    expiresAt: Date? = nil,
    fingerprint: String
  ) {
    self.id = id
    self.kind = kind
    self.text = text
    self.ocrText = ocrText
    self.ocrState = ocrState ?? (kind == .image ? .pending : .notApplicable)
    self.ocrConfidence = Self.validOCRConfidence(
      ocrConfidence,
      kind: kind,
      state: self.ocrState
    )
    self.detectedBarcodes = DetectedBarcode.normalized(detectedBarcodes)
    self.imageFileName = imageFileName
    self.imageMetadata = kind == .image ? imageMetadata : nil
    self.filePaths = filePaths
    self.customTitle = customTitle
    self.alias = alias
    self.richTextFileName = richTextFileName
    self.richTextData = richTextData
    self.tags = tags
    self.boardIDs = boardIDs
    self.isConcealed = isConcealed
    self.sourceApplication = sourceApplication
    self.sourceBundleIdentifier = Self.normalizedSourceBundleIdentifier(sourceBundleIdentifier)
    self.createdAt = createdAt
    self.isPinned = isPinned
    self.useCount = useCount
    self.lastUsedAt = lastUsedAt
    self.expiresAt = expiresAt
    self.fingerprint = fingerprint
  }

  private enum CodingKeys: String, CodingKey {
    case id, kind, text, ocrText, ocrState, ocrConfidence, detectedBarcodes, imageFileName, imageMetadata, filePaths, customTitle, alias,
      richTextFileName,
      richTextData, tags, boardIDs, isConcealed, sourceApplication, sourceBundleIdentifier, createdAt, isPinned
    case useCount, lastUsedAt, fingerprint
    case expiresAt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    kind = try container.decode(ClipKind.self, forKey: .kind)
    text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
    ocrText = try container.decodeIfPresent(String.self, forKey: .ocrText) ?? ""
    ocrState =
      try container.decodeIfPresent(OCRState.self, forKey: .ocrState)
      ?? (kind == .image ? (ocrText.isEmpty ? .noText : .complete) : .notApplicable)
    ocrConfidence = Self.validOCRConfidence(
      try container.decodeIfPresent(Float.self, forKey: .ocrConfidence),
      kind: kind,
      state: ocrState
    )
    detectedBarcodes = DetectedBarcode.normalized(
      try container.decodeIfPresent([DetectedBarcode].self, forKey: .detectedBarcodes) ?? []
    )
    imageFileName = try container.decodeIfPresent(String.self, forKey: .imageFileName)
    if kind == .image {
      imageMetadata = try? container.decodeIfPresent(
        StoredImageMetadata.self,
        forKey: .imageMetadata
      )
    } else {
      imageMetadata = nil
    }
    filePaths = try container.decodeIfPresent([String].self, forKey: .filePaths) ?? []
    customTitle = try container.decodeIfPresent(String.self, forKey: .customTitle)
    alias = try container.decodeIfPresent(String.self, forKey: .alias)
    richTextFileName = try container.decodeIfPresent(String.self, forKey: .richTextFileName)
    richTextData = try container.decodeIfPresent(Data.self, forKey: .richTextData)
    tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    boardIDs = try container.decodeIfPresent([UUID].self, forKey: .boardIDs) ?? []
    isConcealed = try container.decodeIfPresent(Bool.self, forKey: .isConcealed) ?? false
    sourceApplication =
      try container.decodeIfPresent(String.self, forKey: .sourceApplication) ?? "Unknown app"
    sourceBundleIdentifier = Self.normalizedSourceBundleIdentifier(
      try container.decodeIfPresent(String.self, forKey: .sourceBundleIdentifier)
    )
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    useCount = try container.decodeIfPresent(Int.self, forKey: .useCount) ?? 0
    lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
    expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
    fingerprint = try container.decode(String.self, forKey: .fingerprint)
  }

  var hasSearchableOCR: Bool {
    kind == .image
      && (!ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !detectedBarcodes.isEmpty)
  }

  var hasLowConfidenceOCR: Bool {
    kind == .image && ocrState == .complete
      && ocrConfidence.map { $0 < Self.lowOCRConfidenceThreshold } == true
  }

  var hasUnratedOCR: Bool {
    kind == .image && ocrState == .complete && ocrConfidence == nil
      && !ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var needsOCRReview: Bool {
    kind == .image
      && ([.failed, .noText].contains(ocrState) || hasLowConfidenceOCR || hasUnratedOCR)
  }

  private static func validOCRConfidence(
    _ value: Float?,
    kind: ClipKind,
    state: OCRState
  ) -> Float? {
    guard kind == .image, state == .complete, let value,
      value.isFinite, (0...1).contains(value)
    else { return nil }
    return value
  }

  var searchableText: String {
    if isConcealed {
      return [alias ?? "", sourceApplication, sourceBundleIdentifier ?? ""]
        .joined(separator: " ").localizedLowercase
    }
    return [
      alias ?? "", customTitle ?? "", tags.joined(separator: " "), text, ocrText,
      detectedBarcodes.map { "\($0.localizedKind) \($0.symbology) \($0.payload)" }
        .joined(separator: " "),
      imageMetadata?.searchText ?? "",
      isGIF ? (isAnimatedGIF ? "gif animated animation 动图 动画" : "gif") : "",
      filePaths.joined(separator: " "), sourceApplication, sourceBundleIdentifier ?? "",
    ]
    .joined(separator: " ")
    .localizedLowercase
  }

  var displayTitle: String {
    if let customTitle {
      let normalized = customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
      if !normalized.isEmpty { return normalized }
    }
    if isConcealed {
      return switch kind {
      case .text: "Concealed text"
      case .image: "Concealed image"
      case .files: "Concealed files"
      }
    }
    if kind == .files {
      let names = filePaths.map { URL(fileURLWithPath: $0).lastPathComponent }
      guard let first = names.first else { return "Empty file reference" }
      return names.count == 1 ? first : "\(first) + \(names.count - 1) more"
    }
    let candidate = kind == .text ? text : ocrText
    let compact = candidate.replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if !compact.isEmpty { return compact }
    guard kind == .image else { return "Empty text" }
    if let barcode = detectedBarcodes.first {
      return "\(barcode.isQRCode ? "QR Code" : "Barcode"): \(barcode.payload)"
    }
    return switch ocrState {
    case .pending: "Image awaiting text recognition"
    case .noText: "Image without readable text"
    case .failed: "Image recognition failed"
    case .complete: "Image"
    case .notApplicable: "Image"
    }
  }

  func localizedDisplayTitle(language: String? = nil) -> String {
    if let customTitle {
      let normalized = customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
      if !normalized.isEmpty { return normalized }
    }
    if isConcealed {
      return switch kind {
      case .text:
        L10n.text("clip.title.concealed_text", fallback: "Concealed text", language: language)
      case .image:
        L10n.text("clip.title.concealed_image", fallback: "Concealed image", language: language)
      case .files:
        L10n.text("clip.title.concealed_files", fallback: "Concealed files", language: language)
      }
    }
    if kind == .files {
      let names = filePaths.map { URL(fileURLWithPath: $0).lastPathComponent }
      guard let first = names.first else {
        return L10n.text(
          "clip.title.empty_files", fallback: "Empty file reference", language: language)
      }
      return names.count == 1
        ? first
        : L10n.format(
          "clip.title.more_files",
          fallback: "%@ + %d more",
          language: language,
          first,
          names.count - 1
        )
    }
    let candidate = kind == .text ? text : ocrText
    let compact = candidate.replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if !compact.isEmpty { return compact }
    guard kind == .image else {
      return L10n.text("clip.title.empty_text", fallback: "Empty text", language: language)
    }
    if let barcode = detectedBarcodes.first {
      return L10n.format(
        "clip.title.barcode",
        fallback: "%@: %@",
        language: language,
        barcode.localizedKind(language: language),
        barcode.payload
      )
    }
    return switch ocrState {
    case .pending:
      L10n.text(
        "clip.title.image_pending",
        fallback: "Image awaiting text recognition",
        language: language)
    case .noText:
      L10n.text(
        "clip.title.image_no_text", fallback: "Image without readable text", language: language)
    case .failed:
      L10n.text(
        "clip.title.image_failed", fallback: "Image recognition failed", language: language)
    case .complete, .notApplicable:
      L10n.text("clip.title.image", fallback: "Image", language: language)
    }
  }

  func localizedSourceApplication(language: String? = nil) -> String {
    switch sourceApplication {
    case "Unknown app":
      L10n.text("clip.source.unknown", fallback: "Unknown app", language: language)
    case "Created in ClipNest", "在 ClipNest 中创建":
      L10n.text(
        "clip.source.created", fallback: "Created in ClipNest", language: language)
    case "Edited in ClipNest", "在 ClipNest 中编辑":
      L10n.text(
        "clip.source.edited", fallback: "Edited in ClipNest", language: language)
    case "Selected text", "所选文本":
      L10n.text("clip.source.selected_text", fallback: "Selected text", language: language)
    case "Screenshot", "截图":
      L10n.text("capture.source.screenshot", fallback: "Screenshot", language: language)
    case "Imported screenshot", "导入的截图":
      L10n.text(
        "capture.source.imported", fallback: "Imported screenshot", language: language)
    case "Region capture", "屏幕区域截图":
      L10n.text("capture.source.region", fallback: "Region capture", language: language)
    default:
      sourceApplication
    }
  }

  var hasRichText: Bool {
    richTextFileName != nil || richTextData != nil
  }

  static func normalizedSourceBundleIdentifier(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.utf8.count <= 255,
      trimmed.range(of: #"^[A-Za-z0-9][A-Za-z0-9.-]*$"#, options: .regularExpression) != nil
    else { return nil }
    return trimmed
  }
}

extension ClipItem {
  var isGIF: Bool {
    kind == .image && imageFileName?.lowercased().hasSuffix(".gif") == true
  }

  var isAnimatedGIF: Bool {
    isGIF && (imageMetadata?.frameCount ?? 1) > 1
  }

  func localizedImageFormat(language: String? = nil) -> String? {
    guard isGIF else { return nil }
    guard isAnimatedGIF else { return "GIF" }
    return L10n.text(
      "image.format.animated_gif",
      fallback: "Animated GIF",
      language: language
    )
  }

  var suggestedImageExportFileName: String {
    let fileExtension = isGIF ? "gif" : "png"
    let rawBase: String
    if let title = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
      let suffix = ".\(fileExtension)"
      rawBase = title.lowercased().hasSuffix(suffix) ? String(title.dropLast(suffix.count)) : title
    } else {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
      rawBase = "ClipNest Screenshot \(formatter.string(from: createdAt))"
    }
    let safe = rawBase.map { character -> Character in
      character.isLetter || character.isNumber || " -_.".contains(character)
        ? character : "-"
    }
    let base = String(safe).trimmingCharacters(in: .whitespacesAndNewlines)
    return "\(String((base.isEmpty ? "ClipNest Screenshot" : base).prefix(100))).\(fileExtension)"
  }
}

enum ClipFilter: String, CaseIterable, Identifiable, Codable, Sendable {
  case all = "All"
  case pinned = "Pinned"
  case text = "Text"
  case images = "Images"
  case ocrSearchable = "Searchable OCR"
  case ocrReview = "Review OCR"
  case files = "Files"
  case receipts = "Receipts"
  case links = "Links"
  case emails = "Emails"
  case code = "Code"
  case json = "JSON"
  case colors = "Colors"

  var id: String { rawValue }

  func localizedLabel(language: String? = nil) -> String {
    switch self {
    case .all: L10n.text("main.filter.all", fallback: "All", language: language)
    case .pinned: L10n.text("main.filter.pinned", fallback: "Pinned", language: language)
    case .text: L10n.text("main.filter.text", fallback: "Text", language: language)
    case .images: L10n.text("main.filter.images", fallback: "Images", language: language)
    case .ocrSearchable:
      L10n.text("main.filter.ocr_searchable", fallback: "Searchable OCR", language: language)
    case .ocrReview:
      L10n.text("main.filter.ocr_review", fallback: "Review OCR", language: language)
    case .files: L10n.text("main.filter.files", fallback: "Files", language: language)
    case .receipts:
      L10n.text("main.filter.receipts", fallback: "Receipts & invoices", language: language)
    case .links: L10n.text("main.filter.links", fallback: "Links", language: language)
    case .emails: L10n.text("main.filter.emails", fallback: "Emails", language: language)
    case .code: L10n.text("main.filter.code", fallback: "Code", language: language)
    case .json: "JSON"
    case .colors: L10n.text("main.filter.colors", fallback: "Colors", language: language)
    }
  }

  var systemImage: String {
    switch self {
    case .all: "square.grid.2x2"
    case .pinned: "pin.fill"
    case .text: "text.alignleft"
    case .images: "photo"
    case .ocrSearchable: "text.magnifyingglass"
    case .ocrReview: "exclamationmark.bubble"
    case .files: "doc.on.doc"
    case .receipts: "receipt"
    case .links: "link"
    case .emails: "envelope"
    case .code: "chevron.left.forwardslash.chevron.right"
    case .json: "curlybraces"
    case .colors: "paintpalette"
    }
  }

  var classifiedKind: ClipContentKind? {
    switch self {
    case .receipts: .receipt
    case .links: .link
    case .emails: .email
    case .code: .code
    case .json: .json
    case .colors: .color
    case .all, .pinned, .text, .images, .ocrSearchable, .ocrReview, .files: nil
    }
  }

  func matches(_ item: ClipItem, classifiedKind: ClipContentKind? = nil) -> Bool {
    switch self {
    case .all: true
    case .pinned: item.isPinned
    case .text: item.kind == .text
    case .images: item.kind == .image
    case .ocrSearchable:
      item.hasSearchableOCR
    case .ocrReview: item.needsOCRReview
    case .files: item.kind == .files
    case .receipts, .links, .emails, .code, .json, .colors:
      classifiedKind == self.classifiedKind
    }
  }
}
