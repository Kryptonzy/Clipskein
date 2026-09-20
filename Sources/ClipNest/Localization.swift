import Foundation

enum L10n {
  static func text(
    _ key: String,
    fallback: String,
    language: String? = nil
  ) -> String {
    let requestedLanguage = language ?? preferredLanguage()
    let bundle = localizedBundle(for: requestedLanguage) ?? .module
    return bundle.localizedString(forKey: key, value: fallback, table: "Localizable")
  }

  static func format(
    _ key: String,
    fallback: String,
    language: String? = nil,
    _ arguments: CVarArg...
  ) -> String {
    let template = text(key, fallback: fallback, language: language)
    let locale = language.map(Locale.init(identifier:)) ?? .current
    return String(format: template, locale: locale, arguments: arguments)
  }

  static var availableLanguages: [String] {
    Bundle.module.localizations.filter { $0 != "Base" }.sorted()
  }

  static func preferredLanguage(
    arguments: [String] = ProcessInfo.processInfo.arguments,
    storedLanguages: [String]? = UserDefaults.standard.stringArray(forKey: "AppleLanguages"),
    systemLanguages: [String] = Locale.preferredLanguages
  ) -> String? {
    if let optionIndex = arguments.firstIndex(of: "-AppleLanguages"),
      arguments.indices.contains(optionIndex + 1)
    {
      let rawValue = arguments[optionIndex + 1]
      let firstValue = rawValue.split(separator: ",", maxSplits: 1).first.map(String.init)
      let cleaned = firstValue?.trimmingCharacters(
        in: CharacterSet(charactersIn: "()[]'\" ")
      )
      if let cleaned, !cleaned.isEmpty { return cleaned }
    }
    return storedLanguages?.first ?? systemLanguages.first
  }

  private static func localizedBundle(for language: String?) -> Bundle? {
    guard let language else { return nil }
    let normalized = language.replacingOccurrences(of: "_", with: "-").lowercased()
    let matchedLanguage = availableLanguages.sorted { $0.count > $1.count }.first { available in
      let candidate = available.lowercased()
      return normalized == candidate
        || normalized.hasPrefix("\(candidate)-")
        || candidate.hasPrefix("\(normalized)-")
    }
    guard let matchedLanguage,
      let path = Bundle.module.path(forResource: matchedLanguage, ofType: "lproj")
    else { return nil }
    return Bundle(path: path)
  }
}
