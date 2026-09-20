import Foundation

enum ExtractedValueKind: String, CaseIterable, Sendable, Hashable {
  case merchant
  case amount
  case tax
  case reference
  case date
  case errorCode
  case email
  case link
  case phone

  var label: String {
    switch self {
    case .merchant: L10n.text("extract.merchant", fallback: "Merchant")
    case .amount: L10n.text("extract.amount", fallback: "Amount")
    case .tax: L10n.text("extract.tax", fallback: "Tax")
    case .reference: L10n.text("extract.reference", fallback: "Reference")
    case .date: L10n.text("extract.date", fallback: "Date")
    case .errorCode: L10n.text("extract.error_code", fallback: "Error code")
    case .email: L10n.text("extract.email", fallback: "Email")
    case .link: L10n.text("extract.link", fallback: "Link")
    case .phone: L10n.text("extract.phone", fallback: "Phone")
    }
  }

  var systemImage: String {
    switch self {
    case .merchant: "storefront"
    case .amount: "banknote"
    case .tax: "percent"
    case .reference: "number.square"
    case .date: "calendar"
    case .errorCode: "exclamationmark.triangle"
    case .email: "envelope"
    case .link: "link"
    case .phone: "phone"
    }
  }

  fileprivate var priority: Int {
    switch self {
    case .merchant: 0
    case .amount: 1
    case .tax: 2
    case .reference: 3
    case .date: 4
    case .errorCode: 5
    case .email: 6
    case .link: 7
    case .phone: 8
    }
  }

  fileprivate var structuredKey: String {
    switch self {
    case .merchant: "merchant"
    case .amount: "amount"
    case .tax: "tax"
    case .reference: "reference"
    case .date: "date"
    case .errorCode: "error_code"
    case .email: "email"
    case .link: "link"
    case .phone: "phone"
    }
  }
}

struct ExtractedValue: Identifiable, Sendable, Hashable {
  let kind: ExtractedValueKind
  let value: String

  var id: String {
    "\(kind.rawValue):\(value.localizedLowercase)"
  }
}

struct StructuredTSVExport: Equatable, Sendable {
  let text: String
  let rowCount: Int
  let omittedCount: Int
}

struct NormalizedMoney: Equatable, Sendable {
  let value: Decimal
  let normalizedValue: String
  let currency: String
}

struct ReceiptSummaryExport: Equatable, Sendable {
  let text: String
  let receiptCount: Int
  let currencyCount: Int
  let omittedCount: Int
}

enum SmartExtractor {
  private static let receiptMarkerTerms = [
    "invoice", "receipt", "order #", "order number", "order no", "order id", "transaction id",
    "confirmation number", "reference number", "grand total", "amount due", "total due",
    "balance due", "total payable", "payment date", "purchase date", "invoice date",
    "receipt date", "date paid", "paid", "charged",
    "发票", "發票", "收据", "收據", "订单号", "訂單號", "交易号", "交易號",
    "流水号", "流水號", "总计", "總計", "合计", "合計", "应付", "應付",
    "实付", "實付", "付款金额", "付款金額", "支付日期", "付款日期", "开票日期",
    "開票日期", "订单日期", "訂單日期", "請求書", "領収書", "注文番号", "取引番号",
    "総額", "お支払い", "支払日", "購入日", "注文日", "請求日",
  ]

  private struct Pattern {
    let kind: ExtractedValueKind
    let expression: NSRegularExpression
    let valueCaptureGroup: Int?
  }

  private struct Candidate {
    let value: ExtractedValue
    let range: NSRange
    let relevance: Int
  }

  private static let patterns: [(ExtractedValueKind, String, Int?)] = [
    (
      .merchant,
      #"(?im)^(?:merchant|vendor|seller|store|business|商户|商戶|商家|卖方|賣方|销售方|銷售方|店铺|店鋪|店舗|販売者)\s*[:：]\s*([^\r\n]{2,80})\s*$"#,
      1
    ),
    (
      .amount,
      #"(?i)(?:(?:[$€£¥￥₹₩₽₺₫฿₱]|R\$|CHF|HK\$|S\$|A\$|C\$)\s?(?:\d{1,2}(?:,\d{2})+,\d{3}|\d{1,3}(?:[ ,.'’]\d{3})+|\d+)(?:[.,]\d{1,2})?|(?:\d{1,2}(?:,\d{2})+,\d{3}|\d{1,3}(?:[ ,.'’]\d{3})+|\d+)(?:[.,]\d{1,2})?\s?(?:USD|EUR|GBP|JPY|CNY|RMB|KRW|INR|CHF|CAD|AUD|NZD|HKD|SGD|BRL|RUB|TRY|VND|THB|PHP))"#,
      nil
    ),
    (
      .tax,
      #"(?i)(?:sales\s+tax|tax(?:\s+amount)?|vat|gst|hst|税额|稅額|增值税|增值稅|消费税|消費税|税金|内税|外税)\s*(?:[:：])?\s*((?:[$€£¥￥₹₩₽₺₫฿₱]|R\$|CHF|HK\$|S\$|A\$|C\$)\s?(?:\d{1,2}(?:,\d{2})+,\d{3}|\d{1,3}(?:[ ,.'’]\d{3})+|\d+)(?:[.,]\d{1,2})?|(?:\d{1,2}(?:,\d{2})+,\d{3}|\d{1,3}(?:[ ,.'’]\d{3})+|\d+)(?:[.,]\d{1,2})?\s?(?:USD|EUR|GBP|JPY|CNY|RMB|KRW|INR|CHF|CAD|AUD|NZD|HKD|SGD|BRL|RUB|TRY|VND|THB|PHP))"#,
      1
    ),
    (
      .reference,
      #"(?i)\b(?:order(?:\s*(?:id|no\.?|number))?|invoice(?:\s*(?:id|no\.?|number))?|receipt(?:\s*(?:id|no\.?|number))?|transaction(?:\s*(?:id|no\.?|number))?|confirmation(?:\s*(?:id|no\.?|number|code))?|booking(?:\s*(?:id|no\.?|number|code))?|reference|ref\.?|tracking(?:\s*(?:id|no\.?|number))?)\s*(?:#|:|：|号|號)?\s*([A-Z0-9][A-Z0-9_./-]{3,47})\b|(?:订单号?|訂單號?|发票号?|發票號?|交易号?|交易號?|参考号?|參考號?|流水号?|流水號?|运单号?|運單號?|确认号?|確認號?|预订号?|預訂號?|注文番号|請求書番号|取引番号|参照番号|予約番号)\s*(?:#|:|：)?\s*([A-Z0-9][A-Z0-9_./-]{3,47})"#,
      1
    ),
    (
      .date,
      #"(?i)(?<!\d)(?:\d{4}[./-]\d{1,2}[./-]\d{1,2}|\d{1,2}[./-]\d{1,2}[./-]\d{4}|\d{4}年\d{1,2}月\d{1,2}日|(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+\d{1,2},?\s+\d{4}|\d{1,2}\s+(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+\d{4})(?!\d)"#,
      nil
    ),
    (
      .errorCode,
      #"(?i)\b(?:ERR(?:OR)?[_ -]?[A-Z0-9-]{2,}|HTTP\s?[1-5]\d{2}|0x[0-9A-F]{4,}|[A-Z]{2,8}[-_]\d{3,})\b"#,
      nil
    ),
    (
      .email,
      #"(?i)(?<![A-Z0-9._%+\-])[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,63}(?![A-Z0-9._%+\-])"#,
      nil
    ),
    (.link, #"(?i)https?://[^\s<>()，。；：！？《》「」『』【】（）…]+"#, nil),
    (.phone, #"(?<![A-Z0-9])\+?\d[\d ()\-]{5,}\d(?![A-Z0-9])"#, nil),
  ]

  private static let expressions: [Pattern] =
    patterns.compactMap { kind, pattern, valueCaptureGroup in
      guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
      return Pattern(kind: kind, expression: expression, valueCaptureGroup: valueCaptureGroup)
    }

  private static let trailingLinkPunctuation = CharacterSet(
    charactersIn: ".,;:!?)]}'\"，。；：！？》」』】）…"
  )

  static func extract(from text: String, limit: Int = 12) -> [ExtractedValue] {
    guard limit > 0, !text.isEmpty, text.utf8.count <= 2_000_000 else { return [] }
    let source = text as NSString
    let fullRange = NSRange(location: 0, length: source.length)
    var candidates: [Candidate] = []

    for pattern in expressions {
      for match in pattern.expression.matches(in: text, range: fullRange) {
        let valueRange = capturedValueRange(for: match, preferredGroup: pattern.valueCaptureGroup)
        guard valueRange.location != NSNotFound, valueRange.length > 0 else { continue }
        var value = source.substring(with: valueRange)
          .trimmingCharacters(in: .whitespacesAndNewlines)
        if pattern.kind == .link {
          value = value.trimmingCharacters(in: trailingLinkPunctuation)
        }
        guard isPlausible(value, kind: pattern.kind) else { continue }
        candidates.append(
          Candidate(
            value: ExtractedValue(kind: pattern.kind, value: value),
            range: valueRange,
            relevance: contextualRelevance(
              for: pattern.kind,
              range: valueRange,
              source: source
            )
          )
        )
      }
    }

    candidates.sort {
      if $0.value.kind.priority != $1.value.kind.priority {
        return $0.value.kind.priority < $1.value.kind.priority
      }
      if $0.relevance != $1.relevance {
        return $0.relevance > $1.relevance
      }
      return $0.range.location < $1.range.location
    }

    var acceptedRanges: [NSRange] = []
    let referenceRanges = candidates.compactMap {
      $0.value.kind == .reference ? $0.range : nil
    }
    let nonPhoneRanges = candidates.compactMap {
      $0.value.kind == .phone ? nil : $0.range
    }
    var seen = Set<String>()
    var seenValues = Set<String>()
    var values: [ExtractedValue] = []

    func accept(_ candidate: Candidate) {
      guard values.count < limit else { return }
      if candidate.value.kind == .errorCode,
        referenceRanges.contains(where: { NSIntersectionRange($0, candidate.range).length > 0 })
      {
        return
      }
      if candidate.value.kind == .date,
        referenceRanges.contains(where: { NSIntersectionRange($0, candidate.range).length > 0 })
      {
        return
      }
      if candidate.value.kind == .phone,
        nonPhoneRanges.contains(where: { NSIntersectionRange($0, candidate.range).length > 0 })
      {
        return
      }
      guard seen.insert(candidate.value.id).inserted else { return }
      let normalizedValue = candidate.value.value.folding(
        options: [.caseInsensitive, .diacriticInsensitive],
        locale: Locale(identifier: "en_US_POSIX")
      )
      let deduplicationKey =
        candidate.value.kind == .tax ? "tax:\(normalizedValue)" : normalizedValue
      guard seenValues.insert(deduplicationKey).inserted else { return }
      acceptedRanges.append(candidate.range)
      values.append(candidate.value)
    }

    for kind in ExtractedValueKind.allCases where values.count < limit {
      for candidate in candidates where candidate.value.kind == kind {
        let previousCount = values.count
        accept(candidate)
        if values.count > previousCount { break }
      }
    }
    for candidate in candidates where values.count < limit {
      accept(candidate)
    }
    return values
  }

  /// Recognizes locally extractable receipts and invoices without treating any price-like note
  /// as a business document. The bounded prefix keeps classification cheap during list redraws.
  static func isStructuredReceipt(_ text: String) -> Bool {
    guard !text.isEmpty else { return false }
    let source = String(text.prefix(65_536))
    let normalized = source.localizedLowercase
    guard receiptMarkerTerms.contains(where: normalized.contains) else { return false }
    let kinds = Set(extract(from: source, limit: 12).map(\.kind))
    return kinds.contains(.amount) && (kinds.contains(.reference) || kinds.contains(.date))
  }

  static func structuredJSON(from values: [ExtractedValue]) -> String? {
    guard hasEnoughStructuredKinds(values) else { return nil }
    let fields = structuredFields(from: values)
    let object = Dictionary(uniqueKeysWithValues: fields.map { ($0.key, $0.value) })
    guard fields.count >= 2,
      JSONSerialization.isValidJSONObject(object),
      let data = try? JSONSerialization.data(
        withJSONObject: object,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      )
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func structuredTSV(from values: [ExtractedValue]) -> String? {
    guard hasEnoughStructuredKinds(values) else { return nil }
    let fields = structuredFields(from: values)
    guard fields.count >= 2 else { return nil }
    let header = fields.map(\.key).joined(separator: "\t")
    let row = fields.map { sanitizedTSVCell($0.value) }.joined(separator: "\t")
    return "\(header)\n\(row)"
  }

  static func structuredTSV(
    from items: [ClipItem],
    rowLimit: Int = 500,
    sourceByteLimit: Int = 5_000_000
  ) -> StructuredTSVExport? {
    guard rowLimit > 0, sourceByteLimit > 0 else { return nil }
    var rows: [[String: String]] = []
    var includedKeys = Set<String>()
    var omittedCount = 0
    var consumedSourceBytes = 0

    for (index, item) in items.enumerated() {
      guard rows.count < rowLimit else {
        omittedCount += items.count - index
        break
      }
      guard !item.isConcealed else {
        omittedCount += 1
        continue
      }
      let source: String
      switch item.kind {
      case .text: source = item.text
      case .image: source = item.ocrText
      case .files:
        omittedCount += 1
        continue
      }
      let sourceBytes = source.utf8.count
      guard sourceBytes > 0, sourceBytes <= sourceByteLimit - consumedSourceBytes else {
        omittedCount += 1
        continue
      }
      consumedSourceBytes += sourceBytes
      let values = extract(from: source)
      guard hasEnoughStructuredKinds(values) else {
        omittedCount += 1
        continue
      }
      let fields = structuredFields(from: values)
      var row: [String: String] = [:]
      for field in fields {
        row[field.key] = field.value
        includedKeys.insert(field.key)
      }
      guard row.count >= 2 else {
        omittedCount += 1
        continue
      }
      rows.append(row)
    }

    guard !rows.isEmpty else { return nil }
    let columns = structuredColumnOrder.filter(includedKeys.contains)
    let header = columns.joined(separator: "\t")
    let body = rows.map { row in
      columns.map { sanitizedTSVCell(row[$0] ?? "") }.joined(separator: "\t")
    }.joined(separator: "\n")
    return StructuredTSVExport(
      text: "\(header)\n\(body)",
      rowCount: rows.count,
      omittedCount: omittedCount
    )
  }

  static func normalizedMoney(from rawValue: String) -> NormalizedMoney? {
    let upper = rawValue.uppercased()
    let explicitCurrencies = [
      "USD", "EUR", "GBP", "JPY", "CNY", "RMB", "KRW", "INR", "CHF", "CAD",
      "AUD", "NZD", "HKD", "SGD", "BRL", "RUB", "TRY", "VND", "THB", "PHP",
    ]
    let currency: String
    if let explicit = explicitCurrencies.first(where: { upper.contains($0) }) {
      currency = explicit == "RMB" ? "CNY" : explicit
    } else if upper.contains("HK$") {
      currency = "HKD"
    } else if upper.contains("S$") {
      currency = "SGD"
    } else if upper.contains("A$") {
      currency = "AUD"
    } else if upper.contains("C$") {
      currency = "CAD"
    } else if upper.contains("R$") {
      currency = "BRL"
    } else if rawValue.contains("€") {
      currency = "EUR"
    } else if rawValue.contains("£") {
      currency = "GBP"
    } else if rawValue.contains("₹") {
      currency = "INR"
    } else if rawValue.contains("₩") {
      currency = "KRW"
    } else if rawValue.contains("₽") {
      currency = "RUB"
    } else if rawValue.contains("₺") {
      currency = "TRY"
    } else if rawValue.contains("₫") {
      currency = "VND"
    } else if rawValue.contains("฿") {
      currency = "THB"
    } else if rawValue.contains("₱") {
      currency = "PHP"
    } else if rawValue.contains("¥") || rawValue.contains("￥") {
      currency = "¥"
    } else if rawValue.contains("$") {
      currency = "$"
    } else {
      return nil
    }

    let numericCharacters = rawValue.filter {
      $0.isNumber || $0 == "." || $0 == "," || $0 == " " || $0 == "'" || $0 == "’"
    }
    let compact = numericCharacters.filter { $0 != " " && $0 != "'" && $0 != "’" }
    guard compact.contains(where: \.isNumber) else { return nil }
    let dotIndices = compact.indices.filter { compact[$0] == "." }
    let commaIndices = compact.indices.filter { compact[$0] == "," }
    let separators = dotIndices + commaIndices
    let decimalIndex: String.Index?
    if dotIndices.isEmpty || commaIndices.isEmpty {
      let sameKind = dotIndices.isEmpty ? commaIndices : dotIndices
      if let last = sameKind.last {
        let trailingDigits = compact.distance(from: compact.index(after: last), to: compact.endIndex)
        decimalIndex = (1...2).contains(trailingDigits) ? last : nil
      } else {
        decimalIndex = nil
      }
    } else {
      if let last = separators.max() {
        let trailingDigits = compact.distance(from: compact.index(after: last), to: compact.endIndex)
        decimalIndex = (1...2).contains(trailingDigits) ? last : nil
      } else {
        decimalIndex = nil
      }
    }

    var whole = ""
    var fraction = ""
    for index in compact.indices {
      let character = compact[index]
      guard character.isNumber else { continue }
      if let decimalIndex, index > decimalIndex {
        fraction.append(character)
      } else {
        whole.append(character)
      }
    }
    guard !whole.isEmpty else { return nil }
    let normalized = fraction.isEmpty ? whole : "\(whole).\(fraction)"
    guard let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    else { return nil }
    return NormalizedMoney(value: value, normalizedValue: normalized, currency: currency)
  }

  static func receiptSummaryTSV(
    from items: [ClipItem],
    rowLimit: Int = 500,
    sourceByteLimit: Int = 5_000_000
  ) -> ReceiptSummaryExport? {
    struct Summary {
      var receiptCount = 0
      var total = Decimal.zero
      var taxedReceiptCount = 0
      var taxTotal = Decimal.zero
    }
    guard rowLimit > 0, sourceByteLimit > 0 else { return nil }
    var summaries: [String: Summary] = [:]
    var includedCount = 0
    var omittedCount = 0
    var consumedSourceBytes = 0

    for (index, item) in items.enumerated() {
      guard includedCount < rowLimit else {
        omittedCount += items.count - index
        break
      }
      guard !item.isConcealed else {
        omittedCount += 1
        continue
      }
      let source: String
      switch item.kind {
      case .text: source = item.text
      case .image: source = item.ocrText
      case .files:
        omittedCount += 1
        continue
      }
      let sourceBytes = source.utf8.count
      guard sourceBytes > 0, sourceBytes <= sourceByteLimit - consumedSourceBytes else {
        omittedCount += 1
        continue
      }
      consumedSourceBytes += sourceBytes
      guard isStructuredReceipt(source) else {
        omittedCount += 1
        continue
      }
      let values = extract(from: source)
      guard let amount = values.first(where: { $0.kind == .amount }),
        let money = normalizedMoney(from: amount.value)
      else {
        omittedCount += 1
        continue
      }
      var summary = summaries[money.currency] ?? Summary()
      summary.receiptCount += 1
      summary.total += money.value
      if let tax = values.first(where: { $0.kind == .tax }),
        let normalizedTax = normalizedMoney(from: tax.value),
        normalizedTax.currency == money.currency
      {
        summary.taxedReceiptCount += 1
        summary.taxTotal += normalizedTax.value
      }
      summaries[money.currency] = summary
      includedCount += 1
    }

    guard includedCount > 0 else { return nil }
    let header = "currency\treceipt_count\ttotal_amount\ttaxed_receipt_count\ttax_amount"
    let rows = summaries.keys.sorted().map { currency in
      let summary = summaries[currency] ?? Summary()
      return [
        currency,
        String(summary.receiptCount),
        decimalString(summary.total),
        String(summary.taxedReceiptCount),
        decimalString(summary.taxTotal),
      ].joined(separator: "\t")
    }
    return ReceiptSummaryExport(
      text: ([header] + rows).joined(separator: "\n"),
      receiptCount: includedCount,
      currencyCount: summaries.count,
      omittedCount: omittedCount
    )
  }

  private static func structuredFields(
    from values: [ExtractedValue]
  ) -> [(key: String, value: String)] {
    var firstValues: [ExtractedValueKind: String] = [:]
    for value in values.prefix(12) where firstValues[value.kind] == nil {
      firstValues[value.kind] = value.value
    }
    var fields: [(key: String, value: String)] = []
    for kind in ExtractedValueKind.allCases {
      guard let value = firstValues[kind] else { continue }
      fields.append((kind.structuredKey, value))
      if kind == .amount, let normalized = normalizedMoney(from: value) {
        fields.append(("amount_value", normalized.normalizedValue))
        fields.append(("currency", normalized.currency))
      } else if kind == .tax, let normalized = normalizedMoney(from: value) {
        fields.append(("tax_value", normalized.normalizedValue))
      }
    }
    return fields
  }

  private static let structuredColumnOrder = [
    "merchant", "amount", "amount_value", "currency", "tax", "tax_value", "reference",
    "date", "error_code", "email", "link", "phone",
  ]

  private static func hasEnoughStructuredKinds(_ values: [ExtractedValue]) -> Bool {
    Set(values.prefix(12).map(\.kind)).count >= 2
  }

  private static func decimalString(_ value: Decimal) -> String {
    NSDecimalNumber(decimal: value).stringValue
  }

  private static func sanitizedTSVCell(_ value: String) -> String {
    value.split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
  }

  private static func capturedValueRange(
    for match: NSTextCheckingResult,
    preferredGroup: Int?
  ) -> NSRange {
    guard let preferredGroup else { return match.range }
    let preferred = match.range(at: preferredGroup)
    if preferred.location != NSNotFound { return preferred }
    // The multilingual reference pattern has two alternative capture groups.
    for index in (preferredGroup + 1)..<match.numberOfRanges {
      let range = match.range(at: index)
      if range.location != NSNotFound { return range }
    }
    return NSRange(location: NSNotFound, length: 0)
  }

  private static func contextualRelevance(
    for kind: ExtractedValueKind,
    range: NSRange,
    source: NSString
  ) -> Int {
    guard kind == .amount || kind == .date else { return 0 }
    let start = max(0, range.location - 96)
    let prefixRange = NSRange(location: start, length: NSMaxRange(range) - start)
    let lines = source.substring(with: prefixRange)
      .localizedLowercase
      .components(separatedBy: .newlines)
    let currentLine = lines.last ?? ""
    let previousLine = lines.dropLast().last ?? ""

    if kind == .date {
      let negativeTerms = [
        "due date", "delivery", "delivered", "ship date", "expiry", "expires",
        "valid until", "到期", "截止", "配送", "送达", "送達", "发货", "發貨",
        "交付", "有效期", "支払期限", "有効期限", "配送日", "発送日",
      ]
      if negativeTerms.contains(where: currentLine.contains) { return -10 }
      let strongTerms = [
        "transaction date", "purchase date", "order date", "invoice date", "receipt date",
        "date paid", "payment date", "交易日期", "购买日期", "購買日期", "付款日期",
        "支付日期", "开票日期", "開票日期", "订单日期", "訂單日期", "取引日",
        "購入日", "注文日", "請求日", "支払日",
      ]
      if strongTerms.contains(where: currentLine.contains) { return 12 }
      if strongTerms.contains(where: previousLine.contains) { return 6 }
      if currentLine.contains("date") || currentLine.contains("日期") { return 3 }
      return 0
    }

    let negativeTerms = [
      "subtotal", "sub-total", "tax", "discount", "shipping", "tip", "fee",
      "小计", "税", "折扣", "优惠", "运费", "手续费", "小計", "割引", "送料", "手数料",
    ]
    if negativeTerms.contains(where: currentLine.contains) { return -10 }

    let strongTerms = [
      "grand total", "amount due", "total due", "balance due", "total payable",
      "总计", "合计", "应付", "实付", "总额", "付款金额", "合計", "総額", "お支払い",
    ]
    if strongTerms.contains(where: currentLine.contains) { return 12 }
    if currentLine.contains("total") { return 8 }

    let paidTerms = ["paid", "charged", "payment", "支付", "已付", "付款", "支払"]
    if paidTerms.contains(where: currentLine.contains) { return 6 }
    if strongTerms.contains(where: previousLine.contains) { return 4 }
    if previousLine.contains("total") { return 3 }
    return 0
  }

  private static func isPlausible(_ value: String, kind: ExtractedValueKind) -> Bool {
    switch kind {
    case .merchant:
      let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard (2...80).contains(normalized.count),
        normalized.range(of: #"(?i)https?://|\S+@\S+"#, options: .regularExpression) == nil,
        normalized.unicodeScalars.contains(where: CharacterSet.letters.contains)
      else { return false }
      let generic = ["receipt", "invoice", "order", "收据", "收據", "发票", "發票", "領収書", "請求書"]
      return !generic.contains(normalized.localizedLowercase)
    case .phone:
      let digitCount = value.unicodeScalars.count(where: CharacterSet.decimalDigits.contains)
      return (7...15).contains(digitCount)
    case .link:
      guard let components = URLComponents(string: value),
        let scheme = components.scheme?.localizedLowercase,
        ["http", "https"].contains(scheme),
        components.host?.isEmpty == false,
        components.user == nil,
        components.password == nil
      else { return false }
      return true
    case .reference:
      let scalars = value.unicodeScalars
      let digitCount = scalars.count(where: CharacterSet.decimalDigits.contains)
      return digitCount > 0 && value.count <= 48
    case .date:
      return isPlausibleDate(value)
    case .amount, .tax, .errorCode, .email:
      return true
    }
  }

  private static func isPlausibleDate(_ value: String) -> Bool {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let numeric = normalized
      .replacingOccurrences(of: "年", with: "-")
      .replacingOccurrences(of: "月", with: "-")
      .replacingOccurrences(of: "日", with: "")
    let numericParts = numeric.split(whereSeparator: { ["-", "/", "."].contains($0) })
      .compactMap { Int($0) }
    if numericParts.count == 3 {
      if numericParts[0] >= 1_000 {
        return validDate(year: numericParts[0], month: numericParts[1], day: numericParts[2])
      }
      if numericParts[2] >= 1_000 {
        return validDate(year: numericParts[2], month: numericParts[0], day: numericParts[1])
          || validDate(year: numericParts[2], month: numericParts[1], day: numericParts[0])
      }
    }

    let words = normalized.replacingOccurrences(of: ",", with: "")
      .split(whereSeparator: \Character.isWhitespace)
      .map(String.init)
    guard words.count == 3 else { return false }
    let months = [
      "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3,
      "apr": 4, "april": 4, "may": 5, "jun": 6, "june": 6, "jul": 7,
      "july": 7, "aug": 8, "august": 8, "sep": 9, "september": 9,
      "oct": 10, "october": 10, "nov": 11, "november": 11, "dec": 12,
      "december": 12,
    ]
    if let month = months[words[0].localizedLowercase], let day = Int(words[1]),
      let year = Int(words[2])
    {
      return validDate(year: year, month: month, day: day)
    }
    if let day = Int(words[0]), let month = months[words[1].localizedLowercase],
      let year = Int(words[2])
    {
      return validDate(year: year, month: month, day: day)
    }
    return false
  }

  private static func validDate(year: Int, month: Int, day: Int) -> Bool {
    guard (1900...2100).contains(year), (1...12).contains(month), (1...31).contains(day)
    else { return false }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
    else { return false }
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return components.year == year && components.month == month && components.day == day
  }
}

extension ClipItem {
  var extractedValues: [ExtractedValue] {
    let source =
      switch kind {
      case .text: text
      case .image: ocrText
      case .files: ""
      }
    return SmartExtractor.extract(from: source)
  }
}
