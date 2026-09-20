import AppKit
import Combine
import Foundation

struct SavedLocalInstruction: Codable, Identifiable, Equatable, Sendable {
  let id: UUID
  var name: String
  var prompt: String

  init(id: UUID = UUID(), name: String, prompt: String) {
    self.id = id
    self.name = name
    self.prompt = prompt
  }
}

@MainActor
final class ClipPreferences: ObservableObject {
  private enum Key {
    static let captureImages = "captureImages"
    static let captureFiles = "captureFiles"
    static let captureFeedbackSound = "captureFeedbackSound"
    static let watchScreenshots = "watchScreenshots"
    static let protectSecrets = "protectSecrets"
    static let expireLikelyCodes = "expireLikelyCodes"
    static let authenticateConcealedPreviews = "authenticateConcealedPreviews"
    static let retentionDays = "retentionDays"
    static let itemLimit = "itemLimit"
    static let excludedBundleIDs = "excludedBundleIDs"
    static let plainTextBundleIDs = "plainTextBundleIDs"
    static let appContextBoardIDs = "appContextBoardIDs"
    static let autoCollectContextBundleIDs = "autoCollectContextBundleIDs"
    static let hotKeyPreset = "hotKeyPreset"
    static let screenOCRHotKeyPreset = "screenOCRHotKeyPreset"
    static let snippetHotKeyPreset = "snippetHotKeyPreset"
    static let newSnippetHotKeyPreset = "newSnippetHotKeyPreset"
    static let textActionHotKeyPreset = "textActionHotKeyPreset"
    static let ocrPreferredLanguages = "ocrPreferredLanguages"
    static let ocrCustomWords = "ocrCustomWords"
    static let savedLocalInstructions = "savedLocalInstructions"
    static let onboardingVersion = "onboardingVersion"
  }

  static let currentOnboardingVersion = 2
  static let maximumOCRPreferredLanguages = 6

  private static let protectedAppDefaults: Set<String> = [
    "2BUA8C4S2C.com.1password.1password",
    "com.1password.1password",
    "com.agilebits.onepassword7",
    "com.apple.keychainaccess",
    "com.bitwarden.desktop",
    "com.dashlane.Dashlane",
    "com.lastpass.LastPass",
  ]

  @Published var captureImages: Bool {
    didSet { defaults.set(captureImages, forKey: Key.captureImages) }
  }

  @Published var captureFiles: Bool {
    didSet { defaults.set(captureFiles, forKey: Key.captureFiles) }
  }

  @Published var captureFeedbackSound: Bool {
    didSet { defaults.set(captureFeedbackSound, forKey: Key.captureFeedbackSound) }
  }

  @Published var watchScreenshots: Bool {
    didSet { defaults.set(watchScreenshots, forKey: Key.watchScreenshots) }
  }

  @Published var protectSecrets: Bool {
    didSet { defaults.set(protectSecrets, forKey: Key.protectSecrets) }
  }

  @Published var expireLikelyCodes: Bool {
    didSet { defaults.set(expireLikelyCodes, forKey: Key.expireLikelyCodes) }
  }

  @Published var authenticateConcealedPreviews: Bool {
    didSet {
      defaults.set(authenticateConcealedPreviews, forKey: Key.authenticateConcealedPreviews)
    }
  }

  @Published var retentionDays: Int {
    didSet { defaults.set(retentionDays, forKey: Key.retentionDays) }
  }

  @Published var itemLimit: Int {
    didSet { defaults.set(itemLimit, forKey: Key.itemLimit) }
  }

  @Published var excludedBundleIDs: Set<String> {
    didSet { defaults.set(Array(excludedBundleIDs), forKey: Key.excludedBundleIDs) }
  }

  @Published var plainTextBundleIDs: Set<String> {
    didSet { defaults.set(Array(plainTextBundleIDs), forKey: Key.plainTextBundleIDs) }
  }

  @Published private(set) var appContextBoardIDs: [String: UUID] {
    didSet {
      defaults.set(
        appContextBoardIDs.mapValues(\.uuidString),
        forKey: Key.appContextBoardIDs
      )
    }
  }

  @Published private(set) var autoCollectContextBundleIDs: Set<String> {
    didSet {
      defaults.set(Array(autoCollectContextBundleIDs), forKey: Key.autoCollectContextBundleIDs)
    }
  }

  @Published var hotKeyPreset: HotKeyPreset {
    didSet { defaults.set(hotKeyPreset.rawValue, forKey: Key.hotKeyPreset) }
  }

  @Published var screenOCRHotKeyPreset: ScreenOCRHotKeyPreset {
    didSet { defaults.set(screenOCRHotKeyPreset.rawValue, forKey: Key.screenOCRHotKeyPreset) }
  }

  @Published var snippetHotKeyPreset: SnippetHotKeyPreset {
    didSet { defaults.set(snippetHotKeyPreset.rawValue, forKey: Key.snippetHotKeyPreset) }
  }

  @Published var newSnippetHotKeyPreset: NewSnippetHotKeyPreset {
    didSet { defaults.set(newSnippetHotKeyPreset.rawValue, forKey: Key.newSnippetHotKeyPreset) }
  }

  @Published var textActionHotKeyPreset: TextActionHotKeyPreset {
    didSet { defaults.set(textActionHotKeyPreset.rawValue, forKey: Key.textActionHotKeyPreset) }
  }

  @Published private(set) var ocrPreferredLanguages: [String] {
    didSet { defaults.set(ocrPreferredLanguages, forKey: Key.ocrPreferredLanguages) }
  }

  @Published private(set) var ocrCustomWords: [String] {
    didSet { defaults.set(ocrCustomWords, forKey: Key.ocrCustomWords) }
  }

  @Published private(set) var savedLocalInstructions: [SavedLocalInstruction] {
    didSet {
      guard let data = try? JSONEncoder().encode(savedLocalInstructions) else { return }
      defaults.set(data, forKey: Key.savedLocalInstructions)
    }
  }

  @Published private(set) var onboardingVersion: Int {
    didSet { defaults.set(onboardingVersion, forKey: Key.onboardingVersion) }
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    captureImages = defaults.object(forKey: Key.captureImages) as? Bool ?? true
    captureFiles = defaults.object(forKey: Key.captureFiles) as? Bool ?? true
    captureFeedbackSound = defaults.object(forKey: Key.captureFeedbackSound) as? Bool ?? false
    watchScreenshots = defaults.object(forKey: Key.watchScreenshots) as? Bool ?? false
    protectSecrets = defaults.object(forKey: Key.protectSecrets) as? Bool ?? true
    expireLikelyCodes = defaults.object(forKey: Key.expireLikelyCodes) as? Bool ?? true
    authenticateConcealedPreviews =
      defaults.object(forKey: Key.authenticateConcealedPreviews) as? Bool ?? true
    retentionDays = max(0, defaults.object(forKey: Key.retentionDays) as? Int ?? 30)
    itemLimit = max(1, defaults.object(forKey: Key.itemLimit) as? Int ?? 500)
    let stored = Set(defaults.stringArray(forKey: Key.excludedBundleIDs) ?? [])
    excludedBundleIDs =
      defaults.object(forKey: Key.excludedBundleIDs) == nil ? Self.protectedAppDefaults : stored
    plainTextBundleIDs = Set(defaults.stringArray(forKey: Key.plainTextBundleIDs) ?? [])
    let storedAppContexts =
      defaults.dictionary(forKey: Key.appContextBoardIDs) as? [String: String] ?? [:]
    let decodedAppContextBoardIDs: [String: UUID] = Dictionary(
      uniqueKeysWithValues: storedAppContexts.compactMap { bundleIdentifier, boardID in
        let cleanBundleIdentifier = bundleIdentifier.trimmingCharacters(
          in: .whitespacesAndNewlines)
        guard !cleanBundleIdentifier.isEmpty, cleanBundleIdentifier.count <= 255,
          let boardID = UUID(uuidString: boardID)
        else { return nil }
        return (cleanBundleIdentifier, boardID)
      }
    )
    appContextBoardIDs = decodedAppContextBoardIDs
    autoCollectContextBundleIDs = Set(
      defaults.stringArray(forKey: Key.autoCollectContextBundleIDs) ?? []
    ).intersection(decodedAppContextBoardIDs.keys)
    hotKeyPreset =
      defaults.string(forKey: Key.hotKeyPreset).flatMap(HotKeyPreset.init(rawValue:))
      ?? .controlShiftV
    screenOCRHotKeyPreset =
      defaults.string(forKey: Key.screenOCRHotKeyPreset)
      .flatMap(ScreenOCRHotKeyPreset.init(rawValue:))
      ?? .controlShiftO
    snippetHotKeyPreset =
      defaults.string(forKey: Key.snippetHotKeyPreset).flatMap(SnippetHotKeyPreset.init(rawValue:))
      ?? .controlShiftB
    newSnippetHotKeyPreset =
      defaults.string(forKey: Key.newSnippetHotKeyPreset)
      .flatMap(NewSnippetHotKeyPreset.init(rawValue:))
      ?? .controlShiftN
    textActionHotKeyPreset =
      defaults.string(forKey: Key.textActionHotKeyPreset)
      .flatMap(TextActionHotKeyPreset.init(rawValue:))
      ?? .controlK
    ocrPreferredLanguages = Self.normalizedOCRLanguages(
      defaults.stringArray(forKey: Key.ocrPreferredLanguages) ?? []
    )
    ocrCustomWords = OCRService.normalizedCustomWords(
      defaults.stringArray(forKey: Key.ocrCustomWords) ?? []
    )
    savedLocalInstructions =
      defaults.data(forKey: Key.savedLocalInstructions)
      .flatMap { try? JSONDecoder().decode([SavedLocalInstruction].self, from: $0) }
      ?? []
    onboardingVersion = max(0, defaults.integer(forKey: Key.onboardingVersion))
  }

  var needsOnboarding: Bool {
    onboardingVersion < Self.currentOnboardingVersion
  }

  func completeOnboarding() {
    onboardingVersion = Self.currentOnboardingVersion
  }

  func isExcluded(bundleIdentifier: String?) -> Bool {
    guard let bundleIdentifier else { return false }
    return excludedBundleIDs.contains(bundleIdentifier)
  }

  func setExcluded(_ excluded: Bool, bundleIdentifier: String) {
    if excluded {
      excludedBundleIDs.insert(bundleIdentifier)
    } else {
      excludedBundleIDs.remove(bundleIdentifier)
    }
  }

  func restoreProtectedAppDefaults() {
    excludedBundleIDs.formUnion(Self.protectedAppDefaults)
  }

  func prefersPlainText(bundleIdentifier: String?) -> Bool {
    guard let bundleIdentifier else { return false }
    return plainTextBundleIDs.contains(bundleIdentifier)
  }

  func setPrefersPlainText(_ prefersPlainText: Bool, bundleIdentifier: String) {
    if prefersPlainText {
      plainTextBundleIDs.insert(bundleIdentifier)
    } else {
      plainTextBundleIDs.remove(bundleIdentifier)
    }
  }

  func appContextBoardID(bundleIdentifier: String?) -> UUID? {
    guard let bundleIdentifier else { return nil }
    return appContextBoardIDs[bundleIdentifier]
  }

  func setAppContextBoard(_ boardID: UUID?, bundleIdentifier: String) {
    let bundleIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !bundleIdentifier.isEmpty, bundleIdentifier.count <= 255 else { return }
    appContextBoardIDs[bundleIdentifier] = boardID
    if boardID == nil { autoCollectContextBundleIDs.remove(bundleIdentifier) }
  }

  func automaticallyCollectsContext(bundleIdentifier: String?) -> Bool {
    guard let bundleIdentifier else { return false }
    return autoCollectContextBundleIDs.contains(bundleIdentifier)
  }

  func setAutomaticallyCollectsContext(_ enabled: Bool, bundleIdentifier: String) {
    let bundleIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !bundleIdentifier.isEmpty, bundleIdentifier.count <= 255 else { return }
    if enabled, appContextBoardIDs[bundleIdentifier] != nil {
      autoCollectContextBundleIDs.insert(bundleIdentifier)
    } else {
      autoCollectContextBundleIDs.remove(bundleIdentifier)
    }
  }

  func removeAppContextBoard(_ boardID: UUID) {
    let removedBundleIdentifiers = Set(
      appContextBoardIDs.compactMap { $0.value == boardID ? $0.key : nil }
    )
    appContextBoardIDs = appContextBoardIDs.filter { $0.value != boardID }
    autoCollectContextBundleIDs.subtract(removedBundleIdentifiers)
  }

  func clearAppContextBoards() {
    appContextBoardIDs.removeAll()
    autoCollectContextBundleIDs.removeAll()
  }

  var usesAutomaticOCRLanguages: Bool { ocrPreferredLanguages.isEmpty }

  func useAutomaticOCRLanguages() {
    ocrPreferredLanguages = []
  }

  func enableCustomOCRLanguages(supported: [String]) {
    guard ocrPreferredLanguages.isEmpty else { return }
    let options = OCRService.supportedConfigurableRecognitionLanguages(supported: supported)
    let preferred = OCRService.preferredRecognitionLanguages(
      preferred: Locale.preferredLanguages,
      supported: options,
      limit: 2
    )
    ocrPreferredLanguages = Self.normalizedOCRLanguages(
      preferred.isEmpty ? Array(options.prefix(1)) : preferred
    )
  }

  func setOCRLanguage(_ identifier: String, enabled: Bool) {
    guard OCRService.configurableRecognitionLanguages.contains(identifier) else { return }
    if enabled {
      guard ocrPreferredLanguages.count < Self.maximumOCRPreferredLanguages,
        !ocrPreferredLanguages.contains(identifier)
      else { return }
      ocrPreferredLanguages.append(identifier)
    } else {
      guard ocrPreferredLanguages.count > 1 else { return }
      ocrPreferredLanguages.removeAll { $0 == identifier }
    }
  }

  func moveOCRLanguage(_ identifier: String, offset: Int) {
    guard let source = ocrPreferredLanguages.firstIndex(of: identifier) else { return }
    let destination = source + offset
    guard ocrPreferredLanguages.indices.contains(destination) else { return }
    ocrPreferredLanguages.swapAt(source, destination)
  }

  @discardableResult
  func addOCRCustomWord(_ value: String) -> Bool {
    let normalized = OCRService.normalizedCustomWords(ocrCustomWords + [value])
    guard normalized.count > ocrCustomWords.count else { return false }
    ocrCustomWords = normalized
    return true
  }

  func removeOCRCustomWord(_ value: String) {
    let key = value.folding(
      options: [.caseInsensitive, .diacriticInsensitive],
      locale: Locale(identifier: "en_US_POSIX")
    )
    ocrCustomWords.removeAll {
      $0.folding(
        options: [.caseInsensitive, .diacriticInsensitive],
        locale: Locale(identifier: "en_US_POSIX")
      ) == key
    }
  }

  private static func normalizedOCRLanguages(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.compactMap { value in
      guard configurableOCRLanguage(value) != nil else { return nil }
      let canonical = configurableOCRLanguage(value)!
      guard seen.insert(canonical).inserted else { return nil }
      return canonical
    }.prefix(maximumOCRPreferredLanguages).map { $0 }
  }

  private static func configurableOCRLanguage(_ value: String) -> String? {
    let normalized = value.replacingOccurrences(of: "_", with: "-").lowercased()
    return OCRService.configurableRecognitionLanguages.first { $0.lowercased() == normalized }
  }

  @discardableResult
  func saveLocalInstruction(name: String, prompt: String) -> Bool {
    let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanName.isEmpty, cleanName.count <= 60, !cleanPrompt.isEmpty,
      cleanPrompt.count <= LocalIntelligenceService.maximumInstructionLength
    else { return false }

    if let index = savedLocalInstructions.firstIndex(where: {
      $0.name.localizedCaseInsensitiveCompare(cleanName) == .orderedSame
    }) {
      savedLocalInstructions[index].name = cleanName
      savedLocalInstructions[index].prompt = cleanPrompt
      let updated = savedLocalInstructions.remove(at: index)
      savedLocalInstructions.insert(updated, at: 0)
    } else {
      savedLocalInstructions.insert(
        SavedLocalInstruction(name: cleanName, prompt: cleanPrompt), at: 0)
      savedLocalInstructions = Array(savedLocalInstructions.prefix(12))
    }
    return true
  }

  func deleteLocalInstruction(id: UUID) {
    savedLocalInstructions.removeAll { $0.id == id }
  }
}

struct RunningApp: Identifiable, Hashable {
  let id: String
  let name: String
  let icon: NSImage?

  @MainActor
  static func available() -> [RunningApp] {
    var seen = Set<String>()
    return NSWorkspace.shared.runningApplications
      .compactMap { app -> RunningApp? in
        guard let id = app.bundleIdentifier,
          let name = app.localizedName,
          app.activationPolicy == .regular,
          seen.insert(id).inserted
        else { return nil }
        return RunningApp(id: id, name: name, icon: app.icon)
      }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }
}
