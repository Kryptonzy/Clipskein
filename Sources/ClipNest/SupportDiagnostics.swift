import Foundation

struct SupportDiagnostics: Equatable, Sendable {
  let appVersion: String
  let buildNumber: String
  let operatingSystem: String
  let architecture: String
  let clipCount: Int
  let pinnedCount: Int
  let stackCount: Int
  let storageEncrypted: Bool
  let storageHealthy: Bool
  let monitoringActive: Bool
  let screenshotInboxEnabled: Bool
  let screenshotInboxHealthy: Bool
  let accessibilityGranted: Bool
  let screenRecordingGranted: Bool
  let quickPickerShortcut: String
  let screenOCRShortcut: String
  let snippetShortcut: String
  let newSnippetShortcut: String
  let textActionShortcut: String

  static var currentAppVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "development"
  }

  static var currentBuildNumber: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development"
  }

  static var currentArchitecture: String {
    #if arch(arm64)
      "Apple silicon"
    #elseif arch(x86_64)
      "Intel"
    #else
      "Unknown"
    #endif
  }

  var report: String {
    """
    ClipNest diagnostics
    Version: \(appVersion) (\(buildNumber))
    macOS: \(operatingSystem)
    Architecture: \(architecture)
    History: \(clipCount) clips, \(pinnedCount) pinned, \(stackCount) in Stack
    Encrypted storage: \(yesNo(storageEncrypted))
    Storage health: \(storageHealthy ? "Ready" : "Needs attention")
    Clipboard monitoring: \(monitoringActive ? "Active" : "Paused")
    Screenshot Inbox: \(screenshotInboxEnabled ? (screenshotInboxHealthy ? "Ready" : "Needs attention") : "Off")
    Accessibility: \(accessibilityGranted ? "Granted" : "Not granted")
    Screen Recording: \(screenRecordingGranted ? "Granted" : "Not granted")
    Quick Picker shortcut: \(quickPickerShortcut)
    Screen OCR shortcut: \(screenOCRShortcut)
    Snippets shortcut: \(snippetShortcut)
    New Snippet shortcut: \(newSnippetShortcut)
    Text Actions shortcut: \(textActionShortcut)

    Privacy note: This report contains app and system versions, architecture, counts, and readiness states. It does not include clipboard text, OCR text, images, filenames, file paths, source applications, tags, aliases, search queries, or encryption keys.
    """
  }

  private func yesNo(_ value: Bool) -> String {
    value ? "Yes" : "No"
  }
}
