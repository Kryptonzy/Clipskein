import Foundation

enum ClipContentKind: String, Sendable, Equatable, Hashable {
  case image
  case files
  case receipt
  case link
  case email
  case color
  case json
  case code
  case text

  var label: String {
    switch self {
    case .image: "Image"
    case .files: "Files"
    case .receipt: "Receipt"
    case .link: "Link"
    case .email: "Email"
    case .color: "Color"
    case .json: "JSON"
    case .code: "Code"
    case .text: "Text"
    }
  }

  func localizedLabel(language: String? = nil) -> String {
    switch self {
    case .image:
      L10n.text("main.kind.image", fallback: label, language: language)
    case .files:
      L10n.text("main.kind.files", fallback: label, language: language)
    case .receipt:
      L10n.text("main.kind.receipt", fallback: label, language: language)
    case .link:
      L10n.text("main.kind.link", fallback: label, language: language)
    case .email:
      L10n.text("main.kind.email", fallback: label, language: language)
    case .color:
      L10n.text("main.kind.color", fallback: label, language: language)
    case .json:
      label
    case .code:
      L10n.text("main.kind.code", fallback: label, language: language)
    case .text:
      L10n.text("main.kind.text", fallback: label, language: language)
    }
  }

  var systemImage: String {
    switch self {
    case .image: "photo"
    case .files: "doc.on.doc"
    case .receipt: "receipt"
    case .link: "link"
    case .email: "envelope"
    case .color: "paintpalette"
    case .json: "curlybraces"
    case .code: "chevron.left.forwardslash.chevron.right"
    case .text: "text.alignleft"
    }
  }
}

struct ClipColor: Sendable, Equatable {
  let red: Double
  let green: Double
  let blue: Double
  let alpha: Double
}

struct ClipContentAnalysis: Sendable, Equatable {
  let kind: ClipContentKind
  let actionURL: URL?
  let color: ClipColor?
  let formattedText: String?
}

enum ContentClassifier {
  static func analyze(_ item: ClipItem) -> ClipContentAnalysis {
    if item.isConcealed {
      let kind: ClipContentKind = switch item.kind {
      case .text: .text
      case .image: .image
      case .files: .files
      }
      return ClipContentAnalysis(kind: kind, actionURL: nil, color: nil, formattedText: nil)
    }
    if item.kind == .files {
      return ClipContentAnalysis(kind: .files, actionURL: nil, color: nil, formattedText: nil)
    }
    if item.kind == .image {
      let kind: ClipContentKind =
        SmartExtractor.isStructuredReceipt(item.ocrText) ? .receipt : .image
      return ClipContentAnalysis(kind: kind, actionURL: nil, color: nil, formattedText: nil)
    }

    let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let url = webURL(from: text) {
      return ClipContentAnalysis(kind: .link, actionURL: url, color: nil, formattedText: nil)
    }
    if isEmail(text), let url = URL(string: "mailto:\(text)") {
      return ClipContentAnalysis(kind: .email, actionURL: url, color: nil, formattedText: nil)
    }
    if let color = color(from: text) {
      return ClipContentAnalysis(kind: .color, actionURL: nil, color: color, formattedText: nil)
    }
    if let formatted = formattedJSON(from: text) {
      return ClipContentAnalysis(kind: .json, actionURL: nil, color: nil, formattedText: formatted)
    }
    if looksLikeCode(text) {
      return ClipContentAnalysis(kind: .code, actionURL: nil, color: nil, formattedText: nil)
    }
    if SmartExtractor.isStructuredReceipt(text) {
      return ClipContentAnalysis(kind: .receipt, actionURL: nil, color: nil, formattedText: nil)
    }
    return ClipContentAnalysis(kind: .text, actionURL: nil, color: nil, formattedText: nil)
  }

  static func webURL(from text: String) -> URL? {
    guard text == text.trimmingCharacters(in: .whitespacesAndNewlines),
      text.utf8.count <= 8_192,
      let components = URLComponents(string: text),
      let scheme = components.scheme?.localizedLowercase,
      ["http", "https"].contains(scheme),
      components.host?.isEmpty == false,
      components.user == nil,
      components.password == nil
    else { return nil }
    return components.url
  }

  private static func isEmail(_ text: String) -> Bool {
    guard text.utf8.count <= 320 else { return false }
    return text.range(
      of: #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,63}$"#,
      options: [.regularExpression, .caseInsensitive]
    ) != nil
  }

  private static func color(from text: String) -> ClipColor? {
    guard
      text.range(
        of: #"^#[0-9A-Fa-f]{3}([0-9A-Fa-f]{3})?([0-9A-Fa-f]{2})?$"#, options: .regularExpression)
        != nil
    else { return nil }
    var hex = String(text.dropFirst())
    if hex.count == 3 {
      hex = hex.map { "\($0)\($0)" }.joined()
    }
    guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }
    let hasAlpha = hex.count == 8
    let red = Double((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
    let green = Double((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
    let blue = Double((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
    let alpha = hasAlpha ? Double(value & 0xFF) / 255 : 1
    return ClipColor(red: red, green: green, blue: blue, alpha: alpha)
  }

  private static func formattedJSON(from text: String) -> String? {
    guard text.utf8.count <= 1_000_000,
      text.first == "{" || text.first == "[",
      let data = text.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data),
      JSONSerialization.isValidJSONObject(object),
      let formatted = try? JSONSerialization.data(
        withJSONObject: object,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      )
    else { return nil }
    return String(data: formatted, encoding: .utf8)
  }

  private static func looksLikeCode(_ text: String) -> Bool {
    guard text.utf8.count <= 2_000_000 else { return false }
    let lower = text.localizedLowercase
    let prefixes = [
      "func ", "class ", "struct ", "enum ", "protocol ", "import ", "let ", "var ",
      "const ", "function ", "def ", "from ", "select ", "insert ", "update ", "#!/",
      "<?xml", "<!doctype", "<html", "#include",
    ]
    if prefixes.contains(where: { lower.hasPrefix($0) }) { return true }
    guard text.contains("\n") else { return false }
    let signals = ["=>", "==", "!=", "{", "}", "();", "</", "::", "->"]
    return signals.filter { text.contains($0) }.count >= 2
  }
}

extension ClipItem {
  var contentAnalysis: ClipContentAnalysis { ContentClassifier.analyze(self) }

  var privacySafeContentKind: ClipContentKind {
    guard !isConcealed else {
      return switch kind {
      case .text: .text
      case .image: .image
      case .files: .files
      }
    }
    return contentAnalysis.kind
  }
}
