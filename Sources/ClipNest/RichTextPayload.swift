import AppKit
import Foundation

enum RichTextPayload {
  static let maximumHTMLBytes = 512 * 1_024

  static func validated(_ data: Data?, matching text: String) -> Data? {
    guard let data, !data.isEmpty, data.count <= ClipItem.maximumRichTextBytes,
      let attributed = try? NSAttributedString(
        data: data,
        options: [.documentType: NSAttributedString.DocumentType.rtf],
        documentAttributes: nil
      ),
      attributed.string.trimmingCharacters(in: .whitespacesAndNewlines) == text
    else { return nil }
    return data
  }

  static func isValid(_ data: Data, matching text: String) -> Bool {
    validated(data, matching: text) != nil
  }

  static func resolved(
    rtfData: Data?,
    htmlData: Data?,
    matching text: String
  ) -> Data? {
    if let rtf = validated(rtfData, matching: text) { return rtf }
    guard let htmlData, !htmlData.isEmpty, htmlData.count <= maximumHTMLBytes,
      let html = String(data: htmlData, encoding: .utf8),
      isSafeLocalHTML(html),
      let attributed = try? NSAttributedString(
        data: htmlData,
        options: [
          .documentType: NSAttributedString.DocumentType.html,
          .characterEncoding: String.Encoding.utf8.rawValue,
        ],
        documentAttributes: nil
      ),
      attributed.string.trimmingCharacters(in: .whitespacesAndNewlines) == text,
      let rtf = try? attributed.data(
        from: NSRange(location: 0, length: attributed.length),
        documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
      )
    else { return nil }
    return validated(rtf, matching: text)
  }

  static func resolveHTMLInBackground(_ htmlData: Data, matching text: String) async -> Data? {
    await Task.detached(priority: .utility) {
      guard !Task.isCancelled else { return nil }
      let result = resolved(rtfData: nil, htmlData: htmlData, matching: text)
      return Task.isCancelled ? nil : result
    }.value
  }

  private static func isSafeLocalHTML(_ html: String) -> Bool {
    let normalized = html.lowercased()
    let externalResourcePatterns = [
      #"<\s*/?\s*(img|picture|video|audio|iframe|frame|object|embed|link|script|style|svg|math)\b"#,
      #"\b(src|srcset|background|poster)\s*="#,
      #"@import\b"#,
      #"\b(url|image-set)\s*\("#,
    ]
    return !externalResourcePatterns.contains {
      normalized.range(of: $0, options: .regularExpression) != nil
    }
  }
}
