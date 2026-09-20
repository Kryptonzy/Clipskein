import Foundation

enum L10n {
  static func text(
    _ key: String,
    fallback: String,
    language: String? = nil,
    resourceBundle: Bundle = .module
  ) -> String {
    let requestedLanguage = language ?? preferredLanguage()
    let bundle = localizedBundle(for: requestedLanguage, in: resourceBundle) ?? resourceBundle
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
    availableLanguages(in: .module)
  }

  static func availableLanguages(in bundle: Bundle) -> [String] {
    Array(Set(resourceLanguages(in: bundle).map(canonicalLanguageIdentifier))).sorted()
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

  private static func localizedBundle(for language: String?, in bundle: Bundle) -> Bundle? {
    guard let language else { return nil }
    let normalized = canonicalLanguageIdentifier(language).lowercased()
    // Match canonical identifiers, but keep the resource's actual spelling for its path.
    // SwiftPM versions differ in whether they preserve script casing in .lproj names.
    let matchedLanguage = resourceLanguages(in: bundle).sorted { $0.count > $1.count }.first { available in
      let candidate = canonicalLanguageIdentifier(available).lowercased()
      return normalized == candidate
        || normalized.hasPrefix("\(candidate)-")
        || candidate.hasPrefix("\(normalized)-")
    }
    guard let matchedLanguage,
      let path = bundle.path(forResource: matchedLanguage, ofType: "lproj")
    else { return nil }
    return Bundle(path: path)
  }

  private static func resourceLanguages(in bundle: Bundle) -> [String] {
    bundle.localizations.filter { $0.caseInsensitiveCompare("Base") != .orderedSame }
  }

  private static func canonicalLanguageIdentifier(_ language: String) -> String {
    Locale.canonicalLanguageIdentifier(from: language.replacingOccurrences(of: "_", with: "-"))
  }
}
