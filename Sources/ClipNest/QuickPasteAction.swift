import Foundation

enum QuickPasteActionKind: String, Sendable {
  case plainText
  case recognizedText
  case barcodeValue
  case extractedValue
  case extractedJSON
  case extractedTSV
  case matchedOCRLine
  case tableMarkdown
  case tableJSON
  case tableHTML
  case markdownLink
  case cleanTrackingLink
  case markdownCode
  case markdownPlainText
  case prettyJSON
  case uppercase
  case lowercase
  case cleanSpacing
  case singleLine
  case removeBlankLines
  case deduplicateLines
  case sortLines
  case minifyJSON
  case decodePercentEncoding
  case stripHTML
}

struct QuickPasteAction: Identifiable, Equatable, Sendable {
  let kind: QuickPasteActionKind
  let label: String
  let systemImage: String
  let text: String
  let extractedKind: ExtractedValueKind?

  init(
    kind: QuickPasteActionKind,
    label: String,
    systemImage: String,
    text: String,
    extractedKind: ExtractedValueKind? = nil
  ) {
    self.kind = kind
    self.label = label
    self.systemImage = systemImage
    self.text = text
    self.extractedKind = extractedKind
  }

  var id: String { "\(kind.rawValue):\(label):\(text)" }
}

enum QuickPasteActionBuilder {
  static func actions(for item: ClipItem) -> [QuickPasteAction] {
    guard !item.isConcealed else { return [] }
    if item.kind == .image {
      let recognized = item.ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
      var actions: [QuickPasteAction] = []
      if item.ocrState == .complete, !recognized.isEmpty {
        actions.append(
          QuickPasteAction(
            kind: .recognizedText,
            label: L10n.text("quick_paste.recognized_text", fallback: "Paste recognized text"),
            systemImage: "text.viewfinder",
            text: recognized
          )
        )
        actions.append(contentsOf: extractedActions(for: item, excluding: recognized))
        actions.append(contentsOf: structuredExtractionActions(for: item))
      }
      actions.append(
        contentsOf: item.detectedBarcodes.map { barcode in
          QuickPasteAction(
            kind: .barcodeValue,
            label: L10n.format(
              "quick_paste.barcode", fallback: "Paste %@", barcode.localizedKind),
            systemImage: barcode.isQRCode ? "qrcode" : "barcode",
            text: barcode.payload
          )
        }
      )
      if !recognized.isEmpty, let table = OCRTable.detect(in: recognized) {
        actions.append(
          QuickPasteAction(
            kind: .tableMarkdown,
            label: L10n.text("quick_paste.table_markdown", fallback: "Paste table as Markdown"),
            systemImage: "tablecells",
            text: table.markdown
          )
        )
        actions.append(
          QuickPasteAction(
            kind: .tableJSON,
            label: L10n.text("quick_paste.table_json", fallback: "Paste table as JSON"),
            systemImage: "curlybraces",
            text: table.json
          )
        )
        actions.append(
          QuickPasteAction(
            kind: .tableHTML,
            label: L10n.text("quick_paste.table_html", fallback: "Paste table as HTML"),
            systemImage: "chevron.left.forwardslash.chevron.right",
            text: table.html
          )
        )
      }
      return actions
    }

    let input = item.text
    guard !input.isEmpty, input.count <= TextTransformer.maximumInputLength else { return [] }
    var actions: [QuickPasteAction] = []
    let analysis = item.contentAnalysis

    if item.hasRichText {
      actions.append(
        QuickPasteAction(
          kind: .plainText,
          label: L10n.text("quick_paste.plain_text", fallback: "Paste without formatting"),
          systemImage: "textformat",
          text: input
        )
      )
    }

    if let markdown = MarkdownDocument.parse(input), markdown.plainText != input {
      actions.append(
        QuickPasteAction(
          kind: .markdownPlainText,
          label: L10n.text(
            "quick_paste.markdown_plain_text", fallback: "Paste Markdown as plain text"),
          systemImage: "text.alignleft",
          text: markdown.plainText
        )
      )
    }

    actions.append(contentsOf: extractedActions(for: item, excluding: input))
    actions.append(contentsOf: structuredExtractionActions(for: item))

    if analysis.kind == .link,
      let url = analysis.actionURL
    {
      if let cleanedURL = TrackingURLCleaner.clean(input) {
        actions.append(
          QuickPasteAction(
            kind: .cleanTrackingLink,
            label: L10n.text(
              "quick_paste.clean_tracking", fallback: "Paste without tracking parameters"),
            systemImage: "checkmark.shield",
            text: cleanedURL
          )
        )
      }
      let title = markdownLinkTitle(for: item, url: url)
      actions.append(
        QuickPasteAction(
          kind: .markdownLink,
          label: L10n.text("quick_paste.markdown_link", fallback: "Paste as Markdown link"),
          systemImage: "link",
          text:
            "[\(escapedMarkdownTitle(title))](\(escapedMarkdownDestination(url.absoluteString)))"
        )
      )
    }

    if analysis.kind == .code || analysis.kind == .json {
      actions.append(
        QuickPasteAction(
          kind: .markdownCode,
          label: L10n.text("quick_paste.markdown_code", fallback: "Paste as Markdown code"),
          systemImage: "chevron.left.forwardslash.chevron.right",
          text: fencedCode(input, language: analysis.kind == .json ? "json" : "")
        )
      )
    }

    if let formatted = analysis.formattedText, formatted != input {
      actions.append(
        QuickPasteAction(
          kind: .prettyJSON,
          label: L10n.text("quick_paste.pretty_json", fallback: "Paste formatted JSON"),
          systemImage: "curlybraces",
          text: formatted
        )
      )
    }

    if analysis.kind == .text {
      let uppercase = input.uppercased(with: .current)
      if uppercase != input, input.rangeOfCharacter(from: .letters) != nil {
        actions.append(
          QuickPasteAction(
            kind: .uppercase,
            label: L10n.text("quick_paste.uppercase", fallback: "Paste uppercase"),
            systemImage: "textformat.size.larger",
            text: uppercase
          )
        )
      }
      let lowercase = input.lowercased(with: .current)
      if lowercase != input, input.rangeOfCharacter(from: .letters) != nil {
        actions.append(
          QuickPasteAction(
            kind: .lowercase,
            label: L10n.text("quick_paste.lowercase", fallback: "Paste lowercase"),
            systemImage: "textformat.size.smaller",
            text: lowercase
          )
        )
      }
    }

    actions.append(contentsOf: TextTransformer.availableTransformations(for: input).map(action))
    return actions
  }

  static func preferredExtractedAction(
    for item: ClipItem,
    matching query: String = ""
  ) -> QuickPasteAction? {
    preferredExtractedAction(in: actions(for: item), matching: query)
  }

  static func preferredExtractedAction(
    in actions: [QuickPasteAction],
    matching query: String
  ) -> QuickPasteAction? {
    let extracted = actions.filter { $0.kind == .extractedValue }
    guard !extracted.isEmpty else { return nil }
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedQuery.isEmpty else { return extracted.first }

    if let valueMatch = extracted.first(where: {
      $0.text.range(
        of: normalizedQuery,
        options: [.caseInsensitive, .diacriticInsensitive]
      ) != nil
    }) {
      return valueMatch
    }
    if let kind = semanticExtractedKind(for: normalizedQuery),
      let semanticMatch = extractedAction(matching: kind, in: extracted)
    {
      return semanticMatch
    }
    return extracted.first
  }

  static func preferredContextAction(
    for item: ClipItem,
    matching query: String
  ) -> QuickPasteAction? {
    preferredContextAction(in: actions(for: item), for: item, matching: query)
  }

  static func preferredContextAction(
    in actions: [QuickPasteAction],
    for item: ClipItem,
    matching query: String
  ) -> QuickPasteAction? {
    let extracted = actions.filter { $0.kind == .extractedValue }
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedQuery.isEmpty else { return extracted.first }
    guard !SearchMatcher.normalize(normalizedQuery).hasPrefix("regex:") else {
      return extracted.first
    }
    return matchedContextAction(
      in: actions,
      for: item,
      matching: normalizedQuery
    ) ?? extracted.first
  }

  static func matchedContextAction(
    for item: ClipItem,
    matching query: String
  ) -> QuickPasteAction? {
    matchedContextAction(in: actions(for: item), for: item, matching: query)
  }

  static func matchedContextAction(
    in actions: [QuickPasteAction],
    for item: ClipItem,
    matching query: String
  ) -> QuickPasteAction? {
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedQuery.isEmpty,
      !SearchMatcher.normalize(normalizedQuery).hasPrefix("regex:")
    else { return nil }
    let extracted = actions.filter { $0.kind == .extractedValue }
    if let relevantExtracted = relevantExtractedAction(
      in: extracted,
      matching: normalizedQuery
    ) {
      return relevantExtracted
    }
    guard let line = matchingOCRLine(for: item, query: normalizedQuery) else { return nil }
    return QuickPasteAction(
      kind: .matchedOCRLine,
      label: L10n.format(
        "quick_paste.matched_ocr_line",
        fallback: "Paste matching OCR line — %@",
        compactPreview(line)
      ),
      systemImage: "text.line.first.and.arrowtriangle.forward",
      text: line
    )
  }

  private static func relevantExtractedAction(
    in extracted: [QuickPasteAction],
    matching query: String
  ) -> QuickPasteAction? {
    if let valueMatch = extracted.first(where: {
      $0.text.range(
        of: query,
        options: [.caseInsensitive, .diacriticInsensitive]
      ) != nil
    }) {
      return valueMatch
    }
    if let kind = semanticExtractedKind(for: query) {
      return extractedAction(matching: kind, in: extracted)
    }
    return nil
  }

  private static func extractedAction(
    matching kind: ExtractedValueKind,
    in extracted: [QuickPasteAction]
  ) -> QuickPasteAction? {
    if let exact = extracted.first(where: { $0.extractedKind == kind }) { return exact }
    // A value such as ERR_PAY-402 can simultaneously be an error and a receipt reference.
    // The extractor presents one non-duplicated chip, while either user intent should find it.
    if kind == .errorCode {
      return extracted.first(where: { $0.extractedKind == .reference })
    }
    if kind == .reference {
      return extracted.first(where: { $0.extractedKind == .errorCode })
    }
    return nil
  }

  private static func matchingOCRLine(for item: ClipItem, query: String) -> String? {
    guard item.kind == .image, item.ocrState == .complete, !item.isConcealed,
      !SearchMatcher.normalize(query).hasPrefix("regex:")
    else { return nil }
    let matcher = SearchMatcher(query)
    guard !matcher.isEmpty else { return nil }

    let completeText = item.ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
    var seen = Set<String>()
    let candidates = completeText
      .prefix(65_536)
      .split(whereSeparator: \Character.isNewline)
      .prefix(200)
      .compactMap { rawLine -> (line: String, exact: Bool, bonus: Double)? in
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.count >= 2, line.count <= 500, line != completeText,
          seen.insert(line).inserted, matcher.matches(line)
        else { return nil }
        let normalizedLine = SearchMatcher.normalize(line)
        return (
          line,
          normalizedLine.contains(matcher.query),
          matcher.tokenBonus(in: line)
        )
      }

    return candidates.sorted { left, right in
      if left.exact != right.exact { return left.exact && !right.exact }
      if left.bonus != right.bonus { return left.bonus > right.bonus }
      return left.line.count < right.line.count
    }.first?.line
  }

  private static func extractedActions(
    for item: ClipItem,
    excluding completeText: String
  ) -> [QuickPasteAction] {
    item.extractedValues
      .filter { $0.value != completeText }
      .prefix(8)
      .map { extracted in
        QuickPasteAction(
          kind: .extractedValue,
          label: L10n.format(
            "quick_paste.extracted_value",
            fallback: "Paste %@ — %@",
            extracted.kind.label,
            compactPreview(extracted.value)
          ),
          systemImage: extracted.kind.systemImage,
          text: extracted.value,
          extractedKind: extracted.kind
        )
      }
  }

  private static func structuredExtractionActions(for item: ClipItem) -> [QuickPasteAction] {
    let values = item.extractedValues
    var actions: [QuickPasteAction] = []
    if let json = SmartExtractor.structuredJSON(from: values) {
      actions.append(
        QuickPasteAction(
          kind: .extractedJSON,
          label: L10n.text(
            "quick_paste.extracted_json",
            fallback: "Paste extracted details as JSON"
          ),
          systemImage: "curlybraces.square",
          text: json
        )
      )
    }
    if let tsv = SmartExtractor.structuredTSV(from: values) {
      actions.append(
        QuickPasteAction(
          kind: .extractedTSV,
          label: L10n.text(
            "quick_paste.extracted_tsv",
            fallback: "Paste extracted details as a table"
          ),
          systemImage: "tablecells",
          text: tsv
        )
      )
    }
    return actions
  }

  private static func semanticExtractedKind(for query: String) -> ExtractedValueKind? {
    let normalized = query.folding(
      options: [.caseInsensitive, .diacriticInsensitive],
      locale: .current
    ).localizedLowercase
    let terms: [(ExtractedValueKind, [String])] = [
      (
        .merchant,
        [
          "merchant", "vendor", "seller", "store", "business", "商户", "商戶", "商家",
          "卖方", "賣方", "销售方", "銷售方", "店铺", "店鋪", "店舗", "販売者",
        ]
      ),
      (
        .amount,
        [
          "amount", "total", "price", "cost", "金额", "金額", "总额", "总计", "合计",
          "应付", "实付", "総額", "合計", "支払い",
        ]
      ),
      (
        .tax,
        [
          "tax", "vat", "gst", "hst", "税额", "稅額", "增值税", "增值稅", "消费税",
          "消費税", "税金", "内税", "外税",
        ]
      ),
      (
        .reference,
        [
          "order", "invoice", "receipt", "transaction", "confirmation", "booking",
          "reference", "tracking", "订单", "訂單", "发票", "發票", "交易", "参考号",
          "參考號", "流水号", "流水號", "运单", "運單", "注文番号", "請求書番号",
          "取引番号", "参照番号", "予約番号",
        ]
      ),
      (
        .date,
        [
          "date", "dated", "when", "日期", "时间", "時間", "购买日", "購買日",
          "交易日", "付款日", "开票日", "開票日", "注文日", "購入日", "取引日",
          "請求日", "支払日",
        ]
      ),
      (.errorCode, ["error", "err", "错误", "錯誤", "报错", "錯誤碼", "错误码", "エラー"]),
      (.email, ["email", "e-mail", "邮箱", "郵箱", "邮件", "郵件", "電子メール"]),
      (.link, ["url", "link", "网址", "網址", "链接", "連結", "リンク"]),
      (.phone, ["phone", "telephone", "mobile", "tel", "电话", "電話", "手机", "手機"]),
    ]
    return terms.first { _, words in words.contains(where: normalized.contains) }?.0
  }

  static func compactPreview(_ value: String, maximumLength: Int = 42) -> String {
    let compact = value.components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    guard maximumLength > 1, compact.count > maximumLength else { return compact }
    return String(compact.prefix(maximumLength - 1)) + "…"
  }

  private static func action(_ transformation: TextTransformation) -> QuickPasteAction {
    let kind: QuickPasteActionKind =
      switch transformation.kind {
      case .cleanSpacing: .cleanSpacing
      case .singleLine: .singleLine
      case .removeBlankLines: .removeBlankLines
      case .deduplicateLines: .deduplicateLines
      case .sortLines: .sortLines
      case .minifyJSON: .minifyJSON
      case .decodePercentEncoding: .decodePercentEncoding
      case .stripHTML: .stripHTML
      }
    return QuickPasteAction(
      kind: kind,
      label: L10n.format(
        "quick_paste.transformation", fallback: "Paste: %@", transformation.label),
      systemImage: transformation.systemImage,
      text: transformation.result
    )
  }

  private static func markdownLinkTitle(for item: ClipItem, url: URL) -> String {
    if let title = item.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
      !title.isEmpty
    {
      return title.components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }
    return url.host() ?? L10n.text("extract.link", fallback: "Link")
  }

  private static func escapedMarkdownTitle(_ value: String) -> String {
    value.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "[", with: "\\[")
      .replacingOccurrences(of: "]", with: "\\]")
  }

  private static func escapedMarkdownDestination(_ value: String) -> String {
    value.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "(", with: "\\(")
      .replacingOccurrences(of: ")", with: "\\)")
  }

  private static func fencedCode(_ value: String, language: String) -> String {
    var currentRun = 0
    var longestRun = 0
    for character in value {
      if character == "`" {
        currentRun += 1
        longestRun = max(longestRun, currentRun)
      } else {
        currentRun = 0
      }
    }
    let fence = String(repeating: "`", count: max(3, longestRun + 1))
    return "\(fence)\(language)\n\(value)\n\(fence)"
  }
}
