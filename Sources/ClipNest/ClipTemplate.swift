import Foundation

struct ClipTemplateField: Identifiable, Equatable, Sendable {
  let key: String
  let label: String
  let defaultValue: String

  var id: String { key }
}

struct ClipTemplate: Equatable, Sendable {
  static let maximumCustomFieldCount = 12

  let source: String
  let fields: [ClipTemplateField]
  let hasPlaceholders: Bool

  var isSupported: Bool {
    hasPlaceholders && fields.count <= Self.maximumCustomFieldCount
  }

  init(_ source: String) {
    self.source = source
    let matches = Self.matches(in: source)
    hasPlaceholders = !matches.isEmpty

    var seen = Set<String>()
    var parsedFields: [ClipTemplateField] = []
    for match in matches {
      guard let name = Self.captured(1, in: source, match: match) else { continue }
      let label = Self.collapsed(name)
      let key = Self.normalizedKey(label)
      guard !key.isEmpty, !Self.isBuiltInKey(key), seen.insert(key).inserted else {
        continue
      }
      let defaultValue = Self.captured(2, in: source, match: match) ?? ""
      parsedFields.append(ClipTemplateField(key: key, label: label, defaultValue: defaultValue))
    }
    fields = parsedFields
  }

  static func isEligible(_ item: ClipItem) -> Bool {
    guard item.kind == .text, !item.isConcealed, item.alias != nil || item.isPinned else {
      return false
    }
    return ClipTemplate(item.text).isSupported
  }

  static func appendingPlaceholder(_ placeholder: String, to source: String) -> String {
    guard !placeholder.isEmpty else { return source }
    guard let last = source.last, !last.isWhitespace else { return source + placeholder }
    return source + " " + placeholder
  }

  static func insertingPlaceholder(
    _ placeholder: String,
    into source: String,
    replacing selection: NSRange?
  ) -> (text: String, selectedRange: NSRange) {
    guard !placeholder.isEmpty else {
      let safeLocation = min(selection?.location ?? source.utf16.count, source.utf16.count)
      return (source, NSRange(location: safeLocation, length: 0))
    }

    let sourceLength = source.utf16.count
    if let selection,
      selection.location <= sourceLength,
      selection.length <= sourceLength - selection.location
    {
      let result = (source as NSString).replacingCharacters(in: selection, with: placeholder)
      return (
        result,
        NSRange(location: selection.location + placeholder.utf16.count, length: 0)
      )
    }

    let result = appendingPlaceholder(placeholder, to: source)
    return (result, NSRange(location: result.utf16.count, length: 0))
  }

  func previewValues(
    emptyFieldPrefix: String = "‹",
    emptyFieldSuffix: String = "›"
  ) -> [String: String] {
    Dictionary(
      uniqueKeysWithValues: fields.map { field in
        (
          field.key,
          field.defaultValue.isEmpty
            ? emptyFieldPrefix + field.label + emptyFieldSuffix
            : field.defaultValue
        )
      }
    )
  }

  func render(
    values: [String: String] = [:],
    now: Date = .now,
    identifier: UUID = UUID(),
    locale: Locale = .current,
    timeZone: TimeZone = .current
  ) -> String {
    let normalizedValues = Dictionary(
      values.map { (Self.normalizedKey($0.key), $0.value) },
      uniquingKeysWith: { _, latest in latest }
    )
    let matches = Self.matches(in: source)
    var rendered = source
    for match in matches.reversed() {
      guard let name = Self.captured(1, in: source, match: match) else { continue }
      let key = Self.normalizedKey(name)
      let defaultValue = Self.captured(2, in: source, match: match) ?? ""
      let replacement =
        Self.builtInValue(
          for: key,
          now: now,
          identifier: identifier,
          locale: locale,
          timeZone: timeZone
        ) ?? normalizedValues[key] ?? defaultValue
      guard let range = Range(match.range, in: rendered) else { continue }
      rendered.replaceSubrange(range, with: replacement)
    }
    return rendered.replacingOccurrences(of: #"\{{"#, with: "{{")
  }

  private static let builtInKeys: Set<String> = [
    "date", "time", "datetime", "iso8601", "uuid",
  ]

  private static let offsetBuiltInExpression: NSRegularExpression = {
    try! NSRegularExpression(pattern: #"^(date|datetime)([+-])(\d{1,4})(mo|[dhw])$"#)
  }()

  private static let expression: NSRegularExpression = {
    // A leading backslash escapes a placeholder. Custom fields may include a default after `|`.
    try! NSRegularExpression(
      pattern: #"(?<!\\)\{\{\s*([^{}|]+?)(?:\|([^{}]*))?\s*\}\}"#
    )
  }()

  private static func matches(in source: String) -> [NSTextCheckingResult] {
    expression.matches(in: source, range: NSRange(source.startIndex..., in: source))
  }

  private static func captured(
    _ index: Int,
    in source: String,
    match: NSTextCheckingResult
  ) -> String? {
    let range = match.range(at: index)
    guard range.location != NSNotFound, let swiftRange = Range(range, in: source) else {
      return nil
    }
    return String(source[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func collapsed(_ value: String) -> String {
    value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  private static func normalizedKey(_ value: String) -> String {
    collapsed(value).folding(
      options: [.caseInsensitive, .diacriticInsensitive],
      locale: Locale(identifier: "en_US_POSIX")
    )
  }

  private static func isBuiltInKey(_ key: String) -> Bool {
    builtInKeys.contains(key)
      || offsetBuiltInExpression.firstMatch(
        in: key,
        range: NSRange(key.startIndex..., in: key)
      ) != nil
  }

  private static func builtInValue(
    for key: String,
    now: Date,
    identifier: UUID,
    locale: Locale,
    timeZone: TimeZone
  ) -> String? {
    func formatted(
      _ date: Date,
      dateStyle: DateFormatter.Style,
      timeStyle: DateFormatter.Style
    ) -> String {
      let formatter = DateFormatter()
      formatter.locale = locale
      formatter.timeZone = timeZone
      formatter.dateStyle = dateStyle
      formatter.timeStyle = timeStyle
      return formatter.string(from: date)
    }

    switch key {
    case "date":
      return formatted(now, dateStyle: .medium, timeStyle: .none)
    case "time":
      return formatted(now, dateStyle: .none, timeStyle: .short)
    case "datetime":
      return formatted(now, dateStyle: .medium, timeStyle: .short)
    case "iso8601":
      let formatter = ISO8601DateFormatter()
      formatter.timeZone = timeZone
      formatter.formatOptions = [.withInternetDateTime]
      return formatter.string(from: now)
    case "uuid":
      return identifier.uuidString.lowercased()
    default:
      break
    }

    guard
      let match = offsetBuiltInExpression.firstMatch(
        in: key,
        range: NSRange(key.startIndex..., in: key)
      ),
      let base = captured(1, in: key, match: match),
      let sign = captured(2, in: key, match: match),
      let rawAmount = captured(3, in: key, match: match),
      let amount = Int(rawAmount),
      let unit = captured(4, in: key, match: match)
    else {
      return nil
    }

    let signedAmount = sign == "-" ? -amount : amount
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let component: Calendar.Component
    switch unit {
    case "h": component = .hour
    case "w": component = .weekOfYear
    case "mo": component = .month
    default: component = .day
    }
    guard let shifted = calendar.date(byAdding: component, value: signedAmount, to: now) else {
      return nil
    }
    return base == "datetime"
      ? formatted(shifted, dateStyle: .medium, timeStyle: .short)
      : formatted(shifted, dateStyle: .medium, timeStyle: .none)
  }
}
