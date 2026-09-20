import AppKit
import SwiftUI

private struct AutomationLinkExample: Identifiable {
  let id: String
  let title: String
  let link: ClipNestDeepLink
}

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject var store: ClipStore
  @ObservedObject var preferences: ClipPreferences
  @StateObject private var launchAtLogin = LaunchAtLoginController()
  @StateObject private var permissions = PermissionController()
  @State private var apps = RunningApp.available()
  @State private var privacyRulePattern = ""
  @State private var privacyRuleMode = ClipboardPrivacyRuleMode.contains
  @State private var editingPrivacyRuleID: UUID?
  @State private var deletingPrivacyRule: ClipboardPrivacyRule?
  @State private var privacyRuleTestText = ""
  @State private var diagnosticsCopied = false
  @State private var copiedAutomationLinkID: String?
  @State private var automationSearchQuery = ""
  @State private var isDiscoveringExistingScreenshots = false
  @State private var existingScreenshotCandidates: [URL] = []
  @State private var showingExistingScreenshotConfirmation = false
  @State private var supportedOCRLanguages = OCRService.supportedRecognitionLanguages()
  @State private var ocrCustomWordDraft = ""

  init(store: ClipStore) {
    self.store = store
    self.preferences = store.preferences
  }

  private var configuredPlainTextAppsNotRunning: [String] {
    let runningIDs = Set(apps.map(\.id))
    return preferences.plainTextBundleIDs.subtracting(runningIDs).sorted()
  }

  private var configuredExcludedAppsNotRunning: [String] {
    let runningIDs = Set(apps.map(\.id))
    return preferences.excludedBundleIDs.subtracting(runningIDs).sorted()
  }

  private var configuredContextAppsNotRunning: [String] {
    let runningIDs = Set(apps.map(\.id))
    return preferences.appContextBoardIDs.keys.filter { !runningIDs.contains($0) }.sorted()
  }

  private func historicalApplicationName(for bundleIdentifier: String) -> String? {
    store.sourceApplicationFacet(bundleIdentifier: bundleIdentifier)?.name
  }

  private var privacyRuleDraftError: ClipboardPrivacyRuleValidationError? {
    store.privacyRuleValidationError(
      pattern: privacyRulePattern,
      mode: privacyRuleMode,
      excludingID: editingPrivacyRuleID
    )
  }

  private var matchedPrivacyRule: ClipboardPrivacyRule? {
    let text = privacyRuleTestText.trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : store.matchingPrivacyRule(for: text)
  }

  var body: some View {
    TabView {
      ScrollView {
        Form {
          Toggle(
            t("settings.capture_images", "Capture copied images"), isOn: $preferences.captureImages)
          Toggle(
            t("settings.capture_files", "Capture copied file references"),
            isOn: $preferences.captureFiles
          )
          Text(
            t(
              "settings.capture_files.detail",
              "ClipNest remembers local file locations, not copies of the file contents."
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          Toggle(
            t("settings.capture_feedback_sound", "Play a sound after a successful capture"),
            isOn: $preferences.captureFeedbackSound
          )
          Text(
            t(
              "settings.capture_feedback_sound.detail",
              "Plays only after an external clipboard item is saved or refreshed. Blocked, ignored, and failed captures stay silent."
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          Toggle(
            t("settings.watch_screenshots", "Make new screenshots searchable automatically"),
            isOn: $preferences.watchScreenshots
          )
          Text(
            t(
              "settings.watch_screenshots.detail",
              "Watches the screenshot folder configured by macOS. Existing files are ignored; only new screenshots are copied into ClipNest and read locally with OCR."
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          HStack(alignment: .firstTextBaseline) {
            Button {
              isDiscoveringExistingScreenshots = true
              Task { @MainActor in
                let urls = await store.discoverExistingScreenshotURLs()
                isDiscoveringExistingScreenshots = false
                guard !urls.isEmpty else { return }
                existingScreenshotCandidates = urls
                showingExistingScreenshotConfirmation = true
              }
            } label: {
              if isDiscoveringExistingScreenshots {
                Label(
                  t("settings.import_existing_screenshots.scanning", "Scanning screenshot folder…"),
                  systemImage: "hourglass"
                )
              } else {
                Label(
                  t("settings.import_existing_screenshots", "Import existing screenshots…"),
                  systemImage: "photo.stack"
                )
              }
            }
            .disabled(isDiscoveringExistingScreenshots || store.imageImportProgress != nil)
            Spacer()
            Text(
              t(
                "settings.import_existing_screenshots.limit",
                "Most recent 500 · duplicates skipped"
              )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
          ScreenshotImportStatusView(store: store)

          Section(t("settings.ocr.title", "Screenshot text recognition")) {
            let summary = store.imageAnalysisSummary
            VStack(alignment: .leading, spacing: 7) {
              HStack {
                Label(
                  t("settings.ocr.library_status", "Library health"),
                  systemImage: "text.viewfinder"
                )
                .font(.caption.weight(.bold))
                Spacer()
                if summary.total > 0 {
                  Text(
                    L10n.format(
                      "settings.ocr.library_analyzed",
                      fallback: "%d of %d analyzed",
                      summary.analyzed,
                      summary.total
                    )
                  )
                  .font(.caption.monospacedDigit())
                  .foregroundStyle(.secondary)
                }
              }
              if summary.total == 0 {
                Text(
                  t(
                    "settings.ocr.library_empty",
                    "No screenshots yet. Imported images are indexed locally and appear here."
                  )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
              } else {
                ProgressView(value: summary.analyzedFraction)
                  .accessibilityLabel(
                    t("settings.ocr.library_progress", "Screenshot analysis progress")
                  )
                  .accessibilityValue(
                    L10n.format(
                      "settings.ocr.library_analyzed",
                      fallback: "%d of %d analyzed",
                      summary.analyzed,
                      summary.total
                    )
                  )
                Text(
                  L10n.format(
                    "settings.ocr.library_detail",
                    fallback:
                      "%d searchable · %d low confidence · %d unassessed · %d no text · %d failed",
                    summary.searchable,
                    summary.lowConfidence,
                    summary.unrated,
                    summary.noText,
                    summary.failed
                  )
                )
                .font(.caption)
                .foregroundStyle(summary.failed > 0 ? .orange : .secondary)
                HStack(spacing: 12) {
                  Button {
                    openLibrary(filter: .ocrSearchable)
                  } label: {
                    Label(
                      t("settings.ocr.show_searchable", "Show searchable"),
                      systemImage: "text.magnifyingglass"
                    )
                  }
                  .disabled(summary.searchable == 0)
                  Button {
                    openLibrary(filter: .ocrReview)
                  } label: {
                    Label(
                      L10n.format(
                        "settings.ocr.review_results",
                        fallback: "Review %d",
                        summary.review
                      ),
                      systemImage: "exclamationmark.bubble"
                    )
                  }
                  .disabled(summary.review == 0)
                }
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
              }
            }
            .padding(9)
            .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))

            Picker(
              t("settings.ocr.language_mode", "Language priority"),
              selection: Binding(
                get: { preferences.usesAutomaticOCRLanguages ? "automatic" : "custom" },
                set: { mode in
                  if mode == "automatic" {
                    preferences.useAutomaticOCRLanguages()
                  } else {
                    preferences.enableCustomOCRLanguages(supported: supportedOCRLanguages)
                  }
                }
              )
            ) {
              Text(t("settings.ocr.automatic", "Follow system languages")).tag("automatic")
              Text(t("settings.ocr.custom", "Choose priority")).tag("custom")
            }
            .pickerStyle(.segmented)
            .disabled(supportedConfigurableOCRLanguages.isEmpty)

            if !preferences.usesAutomaticOCRLanguages {
              VStack(spacing: 0) {
                ForEach(
                  Array(preferences.ocrPreferredLanguages.enumerated()),
                  id: \.element
                ) { index, identifier in
                  HStack(spacing: 10) {
                    Text("\(index + 1)")
                      .font(.caption.monospacedDigit().weight(.bold))
                      .foregroundStyle(.secondary)
                      .frame(width: 18)
                    Text(ocrLanguageName(identifier))
                    Spacer()
                    Button {
                      preferences.moveOCRLanguage(identifier, offset: -1)
                    } label: {
                      Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == 0)
                    .accessibilityLabel(
                      t("settings.ocr.move_earlier", "Move language earlier")
                    )
                    Button {
                      preferences.moveOCRLanguage(identifier, offset: 1)
                    } label: {
                      Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == preferences.ocrPreferredLanguages.count - 1)
                    .accessibilityLabel(
                      t("settings.ocr.move_later", "Move language later")
                    )
                    Button {
                      preferences.setOCRLanguage(identifier, enabled: false)
                    } label: {
                      Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(preferences.ocrPreferredLanguages.count == 1)
                    .accessibilityLabel(
                      t("settings.ocr.remove_language", "Remove language")
                    )
                  }
                  .padding(.vertical, 6)
                  if index < preferences.ocrPreferredLanguages.count - 1 { Divider() }
                }
              }

              Menu {
                ForEach(availableOCRLanguages, id: \.self) { identifier in
                  Button(ocrLanguageName(identifier)) {
                    preferences.setOCRLanguage(identifier, enabled: true)
                  }
                }
              } label: {
                Label(
                  t("settings.ocr.add_language", "Add language"),
                  systemImage: "plus.circle"
                )
              }
              .disabled(
                availableOCRLanguages.isEmpty
                  || preferences.ocrPreferredLanguages.count
                    >= ClipPreferences.maximumOCRPreferredLanguages
              )
            }

            Text(
              preferences.usesAutomaticOCRLanguages
                ? t(
                  "settings.ocr.automatic_detail",
                  "Uses your Mac’s language order, then adds supported fallbacks. Language detection stays automatic."
                )
                : L10n.format(
                  "settings.ocr.custom_detail",
                  fallback: "Earlier languages get priority. Add up to %d; recognition and detection stay entirely on this Mac.",
                  ClipPreferences.maximumOCRPreferredLanguages
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 7) {
              Text(t("settings.ocr.vocabulary", "Recognition vocabulary"))
                .font(.caption.weight(.bold))
              HStack {
                TextField(
                  t("settings.ocr.vocabulary_placeholder", "Brand, client, or product term"),
                  text: $ocrCustomWordDraft
                )
                .onSubmit(addOCRCustomWord)
                Button(t("settings.ocr.vocabulary_add", "Add")) {
                  addOCRCustomWord()
                }
                .disabled(!canAddOCRCustomWord)
              }
              if !preferences.ocrCustomWords.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                  HStack(spacing: 6) {
                    ForEach(preferences.ocrCustomWords, id: \.self) { word in
                      Button {
                        preferences.removeOCRCustomWord(word)
                      } label: {
                        Label(word, systemImage: "xmark.circle.fill")
                          .lineLimit(1)
                      }
                      .buttonStyle(.bordered)
                      .controlSize(.small)
                      .accessibilityLabel(
                        L10n.format(
                          "settings.ocr.vocabulary_remove",
                          fallback: "Remove %@ from recognition vocabulary",
                          word
                        )
                      )
                    }
                  }
                }
              }
              Text(
                L10n.format(
                  "settings.ocr.vocabulary_detail",
                  fallback:
                    "Up to %d terms guide on-device recognition. Stored in local preferences; do not add passwords or private data.",
                  OCRService.maximumCustomWordCount
                )
              )
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
            }

            if let progress = store.bulkOCRRetryProgress {
              VStack(alignment: .leading, spacing: 7) {
                HStack {
                  Label(
                    progress.isCancelling
                      ? t("settings.ocr.stopping", "Stopping recognition…")
                      : t("settings.ocr.retrying", "Retrying historical screenshots"),
                    systemImage: progress.isCancelling ? "stop.circle" : "text.viewfinder"
                  )
                  .font(.caption.weight(.bold))
                  Spacer()
                  Text(
                    L10n.format(
                      "settings.ocr.progress",
                      fallback: "%d of %d",
                      progress.completed,
                      progress.total
                    )
                  )
                  .font(.caption.monospacedDigit())
                  .foregroundStyle(.secondary)
                }
                ProgressView(
                  value: Double(progress.completed),
                  total: Double(max(progress.total, 1))
                )
                HStack {
                  Text(
                    L10n.format(
                      "settings.ocr.progress_detail",
                      fallback: "%d found text · %d no text · %d failed",
                      progress.recognized,
                      progress.noText,
                      progress.failed
                    )
                  )
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  Spacer()
                  Button(t("settings.ocr.stop", "Stop"), role: .destructive) {
                    store.cancelBulkOCRRetry()
                  }
                  .disabled(progress.isCancelling)
                }
              }
              .padding(9)
              .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            } else {
              HStack {
                Button {
                  store.retryAllOCR()
                } label: {
                  Label(
                    L10n.format(
                      "settings.ocr.retry_all",
                      fallback: "Retry %d screenshots",
                      store.retryableImageAnalysisCount
                    ),
                    systemImage: "arrow.clockwise"
                  )
                }
                .disabled(store.retryableImageAnalysisCount == 0)
                .help(
                  t(
                    "settings.ocr.retry_all_help",
                    "Recheck screenshots with low-confidence, unassessed, failed, or empty OCR results."
                  )
                )
                Spacer()
                if store.pendingImageAnalysisCount > 0 {
                  Label(
                    L10n.format(
                      "settings.ocr.pending",
                      fallback: "%d queued",
                      store.pendingImageAnalysisCount
                    ),
                    systemImage: "hourglass"
                  )
                  .font(.caption)
                  .foregroundStyle(.secondary)
                }
              }
            }
          }

          Toggle(
            t("settings.protect_secrets", "Protect likely passwords and API keys"),
            isOn: $preferences.protectSecrets
          )
          Toggle(
            t(
              "settings.authenticate_concealed",
              "Authenticate before revealing concealed previews"
            ),
            isOn: $preferences.authenticateConcealedPreviews
          )
          Text(
            t(
              "settings.authenticate_concealed.detail",
              "Uses Touch ID when available, with this Mac’s password as fallback. Authorization lasts five minutes and visible previews hide when ClipNest loses focus."
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          Toggle(
            t(
              "settings.expire_codes",
              "Expire likely one-time codes after 15 minutes"
            ),
            isOn: $preferences.expireLikelyCodes
          )
          Text(
            t(
              "settings.expire_codes.detail",
              "Recognizes six-digit codes, grouped alphanumeric codes, and verification messages locally. Turn this off if future matches should follow normal retention."
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          Picker(
            t("settings.shortcut.quick_picker", "Quick picker shortcut"),
            selection: $preferences.hotKeyPreset
          ) {
            ForEach(HotKeyPreset.allCases) { preset in
              Text(shortcutTitle(preset.title)).tag(preset)
            }
          }
          HStack {
            Text(
              t(
                "settings.shortcut.quick_picker.detail",
                "Open searchable clipboard history from any app."
              )
            )
            Spacer()
            Text(quickPickerShortcutStatus)
              .fontWeight(.semibold)
              .foregroundStyle(quickPickerShortcutStatusColor)
          }
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          Picker(
            t("settings.shortcut.screen_ocr", "Screen OCR shortcut"),
            selection: $preferences.screenOCRHotKeyPreset
          ) {
            ForEach(ScreenOCRHotKeyPreset.allCases) { preset in
              Text(shortcutTitle(preset.title)).tag(preset)
            }
          }
          HStack {
            Text(
              t(
                "settings.shortcut.screen_ocr.detail",
                "Select a screen region from any app, save it to history, and copy recognized text."
              )
            )
            Spacer()
            Text(screenOCRShortcutStatus)
              .fontWeight(.semibold)
              .foregroundStyle(screenOCRShortcutStatusColor)
          }
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          Picker(
            t("settings.shortcut.snippets", "Snippets shortcut"),
            selection: $preferences.snippetHotKeyPreset
          ) {
            ForEach(SnippetHotKeyPreset.allCases) { preset in
              Text(shortcutTitle(preset.title)).tag(preset)
            }
          }
          HStack {
            Text(
              t(
                "settings.shortcut.snippets.detail",
                "Open every @alias and dynamic template directly from any app."
              )
            )
            Spacer()
            Text(snippetShortcutStatus)
              .fontWeight(.semibold)
              .foregroundStyle(snippetShortcutStatusColor)
          }
          .font(.caption)
          .foregroundStyle(.secondary)
          Picker(
            t("settings.shortcut.new_snippet", "New Snippet shortcut"),
            selection: $preferences.newSnippetHotKeyPreset
          ) {
            ForEach(NewSnippetHotKeyPreset.allCases) { preset in
              Text(shortcutTitle(preset.title)).tag(preset)
            }
          }
          HStack {
            Text(
              t(
                "settings.shortcut.new_snippet.detail",
                "Create a reusable snippet from any app without changing the clipboard."
              )
            )
            Spacer()
            Text(newSnippetShortcutStatus)
              .fontWeight(.semibold)
              .foregroundStyle(newSnippetShortcutStatusColor)
          }
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          Picker(
            t("settings.shortcut.text_actions", "Text Actions shortcut"),
            selection: $preferences.textActionHotKeyPreset
          ) {
            ForEach(TextActionHotKeyPreset.allCases) { preset in
              Text(shortcutTitle(preset.title)).tag(preset)
            }
          }
          HStack {
            Text(
              t(
                "settings.shortcut.text_actions.detail",
                "Transform the most recent text or OCR result and paste it back from any app."
              )
            )
            Spacer()
            Text(textActionShortcutStatus)
              .fontWeight(.semibold)
              .foregroundStyle(textActionShortcutStatusColor)
          }
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          Picker(t("settings.retention", "Keep history"), selection: $preferences.retentionDays) {
            Text(t("settings.retention.one_day", "1 day")).tag(1)
            Text(L10n.format("settings.retention.days", fallback: "%d days", 7)).tag(7)
            Text(L10n.format("settings.retention.days", fallback: "%d days", 30)).tag(30)
            Text(L10n.format("settings.retention.days", fallback: "%d days", 90)).tag(90)
            Text(t("settings.retention.forever", "Forever")).tag(0)
          }
          Picker(
            t("settings.maximum_clips", "Maximum clips"),
            selection: $preferences.itemLimit
          ) {
            Text("100").tag(100)
            Text("500").tag(500)
            Text("1,000").tag(1_000)
            Text("5,000").tag(5_000)
          }

          Section(t("settings.storage", "Storage")) {
            HStack {
              Label(
                store.isStorageEncrypted
                  ? t("settings.storage.encrypted", "Encrypted · Key protected by macOS Keychain")
                  : t("settings.storage.local", "Stored locally"),
                systemImage: store.isStorageEncrypted ? "lock.fill" : "internaldrive"
              )
              .foregroundStyle(store.isStorageEncrypted ? Color.green : Color.secondary)
              Spacer()
              if store.isInspectingStorage || store.isCleaningStorage {
                ProgressView().controlSize(.small)
              } else if let inventory = store.storageInventory {
                Text(ClipStore.formattedByteCount(inventory.totalBytes))
                  .foregroundStyle(.secondary)
              }
            }

            if let inventory = store.storageInventory {
              Text(
                L10n.format(
                  "settings.storage.contents",
                  fallback: "%d image files · %d rich-text files · %d files total",
                  inventory.imageFileCount,
                  inventory.richTextFileCount,
                  inventory.fileCount
                )
              )
              .font(.caption)
              .foregroundStyle(.secondary)

              if inventory.missingAttachmentCount > 0 {
                Label(
                  L10n.format(
                    "settings.storage.missing",
                    fallback: "%d referenced attachments are missing",
                    inventory.missingAttachmentCount
                  ),
                  systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
              }

              if inventory.unusedFileCount > 0 {
                HStack {
                  Label(
                    L10n.format(
                      "settings.storage.unused",
                      fallback: "%d unused files · %@ reclaimable",
                      inventory.unusedFileCount,
                      ClipStore.formattedByteCount(inventory.unusedBytes)
                    ),
                    systemImage: "sparkles"
                  )
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  Spacer()
                  Button(t("settings.storage.clean_up", "Clean Up")) {
                    store.cleanUnusedStorage()
                  }
                  .disabled(store.isCleaningStorage)
                }
              } else if inventory.missingAttachmentCount == 0 {
                Label(
                  t("settings.storage.healthy", "All referenced attachments are present"),
                  systemImage: "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.green)
              }
            }

            HStack {
              Button(t("settings.storage.refresh", "Inspect Again")) {
                store.refreshStorageInventory()
              }
              .disabled(store.isInspectingStorage || store.isCleaningStorage)
              Button(t("settings.about.show_storage", "Show local storage")) {
                store.revealStorage()
              }
            }
            Text(
              t(
                "settings.storage.detail",
                "ClipNest inspects only file names and sizes inside its local Application Support folder. Clipboard contents never leave this Mac."
              )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          }

          Section(t("settings.startup", "Startup")) {
            Toggle(
              t("settings.launch_at_login", "Launch ClipNest at login"),
              isOn: Binding(
                get: { launchAtLogin.isRequested },
                set: { launchAtLogin.setEnabled($0) }
              )
            )
            LabeledContent(t("settings.status", "Status")) {
              Text(launchAtLoginStatusText)
                .foregroundStyle(
                  launchAtLogin.state == .requiresApproval ? Color.orange : Color.secondary
                )
            }
            if let error = launchAtLogin.errorMessage {
              Text(error)
                .font(.caption)
                .foregroundStyle(.red)
            }
            if launchAtLogin.state == .requiresApproval || launchAtLogin.errorMessage != nil {
              Button(t("settings.login.open", "Open Login Items Settings")) {
                launchAtLogin.openSystemSettings()
              }
            }
          }

          Section(t("settings.permissions", "Permissions")) {
            LabeledContent(t("settings.permissions.paste", "Paste into other apps")) {
              Text(
                permissions.accessibilityGranted
                  ? t("settings.permissions.ready", "Ready")
                  : t("settings.permissions.accessibility_needed", "Needs Accessibility")
              )
              .foregroundStyle(permissions.accessibilityGranted ? Color.green : Color.orange)
            }
            LabeledContent(t("settings.permissions.capture", "Capture a screen region")) {
              Text(
                permissions.screenRecordingGranted
                  ? t("settings.permissions.ready", "Ready")
                  : t(
                    "settings.permissions.screen_recording_needed",
                    "Needs Screen Recording"
                  )
              )
              .foregroundStyle(permissions.screenRecordingGranted ? Color.green : Color.orange)
            }
            Text(
              t(
                "settings.permissions.detail",
                "Accessibility is used only to paste back into another app or let Text Actions read your current selection. Screen Recording is used only after you choose Screen OCR."
              )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
              if !permissions.accessibilityGranted {
                Button(t("settings.permissions.allow_paste", "Allow paste & selection")) {
                  permissions.requestAccessibility()
                }
              }
              if !permissions.screenRecordingGranted {
                Button(t("settings.permissions.allow_capture", "Allow capture")) {
                  permissions.requestScreenRecording()
                }
              }
              Button(t("settings.permissions.check", "Check again")) {
                permissions.refresh()
              }
            }
            HStack {
              Button(
                t("settings.permissions.accessibility_settings", "Accessibility Settings")
              ) { permissions.openAccessibilitySettings() }
              Button(
                t("settings.permissions.screen_recording_settings", "Screen Recording Settings")
              ) { permissions.openScreenRecordingSettings() }
            }
          }

          Section(t("settings.help", "Help")) {
            Button(t("settings.help.welcome", "Show Welcome & Setup")) {
              NotificationCenter.default.post(name: .showWelcome, object: nil)
              AppDelegate.showMainWindow()
            }
          }
        }
        .padding(24)
      }
      .tabItem {
        Label(t("settings.tab.general", "General"), systemImage: "slider.horizontal.3")
      }

      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          VStack(alignment: .leading, spacing: 4) {
            Text(t("settings.privacy.title", "Never capture from these apps"))
              .font(.headline)
            Text(
              t(
                "settings.privacy.detail",
                "Common password managers are protected by default. Changes apply immediately."
              )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }

          GroupBox {
            LazyVStack(spacing: 0) {
              ForEach(apps) { app in
                Toggle(
                  isOn: Binding(
                    get: { preferences.excludedBundleIDs.contains(app.id) },
                    set: { preferences.setExcluded($0, bundleIdentifier: app.id) }
                  )
                ) {
                  HStack(spacing: 9) {
                    if let icon = app.icon {
                      Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                      Text(app.name)
                      Text(app.id).font(.caption2).foregroundStyle(.secondary)
                    }
                  }
                }
                .padding(.vertical, 6)
                if app.id != apps.last?.id { Divider() }
              }
              if !configuredExcludedAppsNotRunning.isEmpty {
                if !apps.isEmpty { Divider() }
                Text(t("settings.privacy.not_running", "Configured but not running"))
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.secondary)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .padding(.vertical, 7)
                ForEach(configuredExcludedAppsNotRunning, id: \.self) { bundleID in
                  Toggle(
                    isOn: Binding(
                      get: { preferences.excludedBundleIDs.contains(bundleID) },
                      set: { preferences.setExcluded($0, bundleIdentifier: bundleID) }
                    )
                  ) {
                    HStack(spacing: 9) {
                      if let icon = store.sourceApplicationIcon(bundleIdentifier: bundleID) {
                        Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                      } else {
                        Image(systemName: "app.dashed").frame(width: 22, height: 22)
                      }
                      VStack(alignment: .leading, spacing: 1) {
                        Text(historicalApplicationName(for: bundleID) ?? bundleID)
                        if historicalApplicationName(for: bundleID) != nil {
                          Text(bundleID).font(.caption2).foregroundStyle(.secondary)
                        }
                      }
                    }
                  }
                  .padding(.vertical, 6)
                  if bundleID != configuredExcludedAppsNotRunning.last { Divider() }
                }
              }
            }
          }

          HStack {
            Button(t("settings.apps.refresh", "Refresh running apps")) {
              apps = RunningApp.available()
            }
            Spacer()
            Button(t("settings.privacy.restore", "Protect common password managers")) {
              preferences.restoreProtectedAppDefaults()
            }
          }

          Divider()

          VStack(alignment: .leading, spacing: 5) {
            Text(t("privacy_rule.title", "Never capture matching text"))
              .font(.headline)
            Text(
              t(
                "privacy_rule.detail",
                "Rules are checked before copied text is written to history. Rules are encrypted with the rest of ClipNest’s local data."
              )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          }

          Picker(t("privacy_rule.mode", "Rule type"), selection: $privacyRuleMode) {
            ForEach(ClipboardPrivacyRuleMode.allCases) { mode in
              Text(mode.localizedLabel).tag(mode)
            }
          }
          .pickerStyle(.segmented)

          HStack(alignment: .firstTextBaseline, spacing: 8) {
            TextField(
              privacyRuleMode == .contains
                ? t("privacy_rule.placeholder.contains", "Phrase to ignore")
                : t("privacy_rule.placeholder.regex", "Regex pattern to ignore"),
              text: $privacyRulePattern
            )
            .textFieldStyle(.roundedBorder)
            .font(privacyRuleMode == .regularExpression ? .system(.body, design: .monospaced) : .body)
            .onSubmit(savePrivacyRuleDraft)

            Button(
              editingPrivacyRuleID == nil
                ? t("privacy_rule.add", "Add Rule")
                : t("privacy_rule.save", "Save Changes")
            ) { savePrivacyRuleDraft() }
            .disabled(privacyRuleDraftError != nil)

            if editingPrivacyRuleID != nil {
              Button(t("common.cancel", "Cancel")) { resetPrivacyRuleDraft() }
            }
          }

          if !privacyRulePattern.isEmpty, let error = privacyRuleDraftError {
            Label(error.localizedMessage, systemImage: "exclamationmark.triangle.fill")
              .font(.caption)
              .foregroundStyle(.orange)
          }

          if store.privacyRules.isEmpty {
            Label(
              t(
                "privacy_rule.empty",
                "No text rules yet. Add a phrase for simple protection or a regular expression for structured values."
              ),
              systemImage: "text.badge.plus"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
          } else {
            VStack(spacing: 8) {
              ForEach(store.privacyRules) { rule in
                HStack(spacing: 10) {
                  Toggle(
                    "",
                    isOn: Binding(
                      get: { rule.isEnabled },
                      set: { store.setPrivacyRuleEnabled($0, id: rule.id) }
                    )
                  )
                  .labelsHidden()
                  VStack(alignment: .leading, spacing: 2) {
                    Text(rule.pattern)
                      .font(.system(.body, design: .monospaced))
                      .lineLimit(2)
                    Text(rule.mode.localizedLabel)
                      .font(.caption2)
                      .foregroundStyle(.secondary)
                    Text(privacyRuleEvidence(rule))
                      .font(.caption2)
                      .foregroundStyle(rule.matchCount > 0 ? Color.green : Color.secondary)
                  }
                  Spacer()
                  Button(t("common.edit", "Edit")) { editPrivacyRule(rule) }
                  Button(role: .destructive) {
                    deletingPrivacyRule = rule
                  } label: {
                    Image(systemName: "trash")
                  }
                  .buttonStyle(.borderless)
                  .help(t("privacy_rule.delete", "Delete privacy rule"))
                }
                .padding(10)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
              }
            }
          }

          VStack(alignment: .leading, spacing: 6) {
            Text(t("privacy_rule.test.title", "Test without saving"))
              .font(.subheadline.weight(.semibold))
            TextField(
              t("privacy_rule.test.placeholder", "Paste example text here"),
              text: $privacyRuleTestText,
              axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(2...4)
            if !privacyRuleTestText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
              if let matchedPrivacyRule {
                Label(
                  L10n.format(
                    "privacy_rule.test.ignored",
                    fallback: "Would be ignored by: %@",
                    matchedPrivacyRule.pattern
                  ),
                  systemImage: "hand.raised.fill"
                )
                .foregroundStyle(.green)
              } else {
                Label(
                  t("privacy_rule.test.captured", "Would be captured"),
                  systemImage: "square.and.arrow.down"
                )
                .foregroundStyle(.secondary)
              }
            }
            Text(
              t(
                "privacy_rule.test.detail",
                "Test text stays only in this field and is never added to clipboard history."
              )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
        }
        .padding(20)
      }
      .confirmationDialog(
        t("privacy_rule.delete.confirm", "Delete this privacy rule?"),
        isPresented: Binding(
          get: { deletingPrivacyRule != nil },
          set: { if !$0 { deletingPrivacyRule = nil } }
        ),
        titleVisibility: .visible
      ) {
        Button(t("privacy_rule.delete", "Delete privacy rule"), role: .destructive) {
          if let deletingPrivacyRule {
            store.deletePrivacyRule(id: deletingPrivacyRule.id)
            if editingPrivacyRuleID == deletingPrivacyRule.id { resetPrivacyRuleDraft() }
          }
          deletingPrivacyRule = nil
        }
        Button(t("common.cancel", "Cancel"), role: .cancel) { deletingPrivacyRule = nil }
      } message: {
        Text(
          t(
            "privacy_rule.delete.detail",
            "Future copied text matching this rule may be saved to history."
          )
        )
      }
      .tabItem { Label(t("settings.tab.privacy", "Privacy"), systemImage: "hand.raised") }

      VStack(alignment: .leading, spacing: 14) {
        VStack(alignment: .leading, spacing: 4) {
          Text(t("settings.paste.title", "Always paste without formatting in these apps"))
            .font(.headline)
          Text(
            t(
              "settings.paste.detail",
              "Only rich-text clips are affected. One-time paste formats remain available in Quick Picker."
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        List {
          ForEach(apps) { app in
            Toggle(
              isOn: Binding(
                get: { preferences.plainTextBundleIDs.contains(app.id) },
                set: { preferences.setPrefersPlainText($0, bundleIdentifier: app.id) }
              )
            ) {
              HStack(spacing: 9) {
                if let icon = app.icon {
                  Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                }
                VStack(alignment: .leading, spacing: 1) {
                  Text(app.name)
                  Text(app.id).font(.caption2).foregroundStyle(.secondary)
                }
              }
            }
          }
          if !configuredPlainTextAppsNotRunning.isEmpty {
            Section(t("settings.paste.not_running", "Configured but not running")) {
              ForEach(configuredPlainTextAppsNotRunning, id: \.self) { bundleID in
                Toggle(
                  bundleID,
                  isOn: Binding(
                    get: { preferences.plainTextBundleIDs.contains(bundleID) },
                    set: {
                      preferences.setPrefersPlainText($0, bundleIdentifier: bundleID)
                    }
                  )
                )
              }
            }
          }
        }

        HStack {
          Button(t("settings.apps.refresh", "Refresh running apps")) {
            apps = RunningApp.available()
          }
          Spacer()
          if !preferences.plainTextBundleIDs.isEmpty {
            Button(t("settings.paste.clear", "Clear all")) {
              preferences.plainTextBundleIDs = []
            }
          }
        }
      }
      .padding(20)
      .tabItem { Label(t("settings.tab.paste", "Paste"), systemImage: "textformat") }

      VStack(alignment: .leading, spacing: 14) {
        VStack(alignment: .leading, spacing: 4) {
          Text(t("settings.context.title", "Quick Picker app contexts"))
            .font(.headline)
          Text(
            t(
              "settings.context.detail",
              "Associate an app with a Pinboard. Quick Picker prioritizes that working set, and you can optionally collect future copies from the app into it automatically."
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }

        if store.boards.isEmpty {
          ContentUnavailableView {
            Label(
              t("settings.context.empty.title", "Create a Pinboard first"),
              systemImage: "rectangle.stack.badge.plus"
            )
          } description: {
            Text(
              t(
                "settings.context.empty.detail",
                "Pinboards turn reusable clips into an app-specific working set."
              )
            )
          }
        } else {
          List {
            Section(t("settings.context.running", "Running applications")) {
              ForEach(apps) { app in
                appContextRow(
                  bundleIdentifier: app.id,
                  name: app.name,
                  icon: app.icon
                )
              }
            }
            if !configuredContextAppsNotRunning.isEmpty {
              Section(t("settings.context.not_running", "Configured but not running")) {
                ForEach(configuredContextAppsNotRunning, id: \.self) { bundleIdentifier in
                  appContextRow(
                    bundleIdentifier: bundleIdentifier,
                    name: historicalApplicationName(for: bundleIdentifier) ?? bundleIdentifier,
                    icon: store.sourceApplicationIcon(bundleIdentifier: bundleIdentifier)
                  )
                }
              }
            }
          }
        }

        HStack {
          Button(t("settings.apps.refresh", "Refresh running apps")) {
            apps = RunningApp.available()
          }
          Spacer()
          if !preferences.appContextBoardIDs.isEmpty {
            Button(t("settings.context.clear", "Clear all contexts")) {
              preferences.clearAppContextBoards()
            }
          }
        }
      }
      .padding(20)
      .tabItem {
        Label(t("settings.tab.context", "Contexts"), systemImage: "rectangle.stack.person.crop")
      }

      automationSettingsView
        .tabItem {
          Label(t("settings.tab.automation", "Automation"), systemImage: "link.badge.plus")
        }

      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          HStack(alignment: .center, spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
              .resizable()
              .frame(width: 68, height: 68)
              .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
              Text("ClipNest")
                .font(.system(size: 24, weight: .bold, design: .rounded))
              Text(
                L10n.format(
                  "settings.about.version",
                  fallback: "Version %@ (%@)",
                  SupportDiagnostics.currentAppVersion,
                  SupportDiagnostics.currentBuildNumber
                )
              )
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(.secondary)
              Text(t("settings.about.tagline", "Private memory for your Mac"))
                .font(.system(size: 13, weight: .semibold))
            }
          }

          HStack(spacing: 10) {
            aboutStatusCard(
              icon: "lock.shield.fill",
              title: t("settings.about.encrypted", "Encrypted locally"),
              detail: t(
                "settings.about.encrypted.detail",
                "The key is protected by macOS Keychain."
              ),
              color: store.isStorageEncrypted ? .green : .orange
            )
            aboutStatusCard(
              icon: "eye.slash.fill",
              title: t("settings.about.no_tracking", "No accounts or tracking"),
              detail: t(
                "settings.about.no_tracking.detail",
                "No telemetry, analytics, or cloud clipboard."
              ),
              color: .blue
            )
          }

          GroupBox {
            VStack(alignment: .leading, spacing: 14) {
              HStack {
                VStack(alignment: .leading, spacing: 3) {
                  Text(t("settings.about.diagnostics", "Support diagnostics"))
                    .font(.headline)
                  Text(
                    t(
                      "settings.about.diagnostics.detail",
                      "Copy version and readiness information when asking for help."
                    )
                  )
                  .font(.caption)
                  .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "stethoscope")
                  .font(.system(size: 22, weight: .semibold))
                  .foregroundStyle(.blue)
              }

              Divider()

              diagnosticsRow(
                t("settings.about.system", "System"),
                "\(ProcessInfo.processInfo.operatingSystemVersionString) · \(SupportDiagnostics.currentArchitecture)"
              )
              diagnosticsRow(
                t("settings.about.history", "History"),
                L10n.format(
                  "settings.about.history.detail",
                  fallback: "%d clips · %d pinned · %d in Stack",
                  store.items.count,
                  store.items.count(where: \.isPinned),
                  store.stackItems.count
                )
              )
              diagnosticsRow(
                t("settings.about.storage_health", "Storage health"),
                storageHealthIsReady
                  ? t("settings.about.ready", "Ready")
                  : t("settings.about.attention", "Needs attention")
              )

              Text(
                t(
                  "settings.about.diagnostics.privacy",
                  "The copied report contains counts and readiness states only—never clipboard contents, screenshots, filenames, paths, apps, searches, or encryption keys."
                )
              )
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)

              HStack {
                Button {
                  let pasteboard = NSPasteboard.general
                  pasteboard.clearContents()
                  diagnosticsCopied = pasteboard.setString(supportDiagnostics.report, forType: .string)
                } label: {
                  Label(
                    diagnosticsCopied
                      ? t("settings.about.diagnostics.copied", "Diagnostics copied")
                      : t("settings.about.diagnostics.copy", "Copy diagnostics"),
                    systemImage: diagnosticsCopied ? "checkmark" : "doc.on.doc"
                  )
                }
                .buttonStyle(.borderedProminent)

                Button(t("settings.about.show_storage", "Show local storage")) {
                  store.revealStorage()
                }
                .buttonStyle(.bordered)
              }
            }
            .padding(8)
          }

          Text(
            t(
              "settings.about.copyright",
              "© 2026 ClipNest. Built for private, focused work."
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(24)
      }
      .tabItem { Label(t("settings.tab.about", "About"), systemImage: "info.circle") }
    }
    .frame(width: 640, height: 620)
    .confirmationDialog(
      L10n.format(
        "settings.import_existing_screenshots.confirm_title",
        fallback: "%d existing screenshots found",
        existingScreenshotCandidates.count
      ),
      isPresented: $showingExistingScreenshotConfirmation,
      titleVisibility: .visible
    ) {
      Button(
        L10n.format(
          "settings.import_existing_screenshots.confirm",
          fallback: "Import %d screenshots",
          existingScreenshotCandidates.count
        )
      ) {
        let urls = existingScreenshotCandidates
        existingScreenshotCandidates = []
        store.importImages(urls)
      }
      Button(t("common.cancel", "Cancel"), role: .cancel) {
        existingScreenshotCandidates = []
      }
    } message: {
      Text(
        t(
          "settings.import_existing_screenshots.confirm_detail",
          "Only likely screenshots in the folder configured by macOS are considered. Files stay in place; ClipNest imports encrypted copies and runs OCR locally."
        )
      )
    }
    .onAppear {
      permissions.refresh()
      launchAtLogin.refresh()
      store.refreshStorageInventory()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    {
      _ in
      permissions.refresh()
      launchAtLogin.refresh()
    }
  }

  private var automationSettingsView: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        HStack(alignment: .top, spacing: 14) {
          Image(systemName: "link.badge.plus")
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(.blue)
            .frame(width: 36)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 4) {
            Text(t("settings.automation.title", "Automation links"))
              .font(.title2.weight(.semibold))
            Text(
              t(
                "settings.automation.detail",
                "Open ClipNest from Shortcuts, Raycast, browsers, or scripts. These links only navigate; they never reveal history, paste, delete, export, or change privacy settings."
              )
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          }
        }

        GroupBox {
          VStack(spacing: 0) {
            ForEach(Array(automationLinkExamples.enumerated()), id: \.element.id) {
              index, example in
              if let url = example.link.url {
                HStack(spacing: 12) {
                  VStack(alignment: .leading, spacing: 4) {
                    Text(example.title)
                      .font(.body.weight(.medium))
                    Text(url.absoluteString)
                      .font(.caption.monospaced())
                      .foregroundStyle(.secondary)
                      .lineLimit(1)
                      .truncationMode(.middle)
                      .textSelection(.enabled)
                  }
                  Spacer(minLength: 10)
                  Button {
                    copyAutomationLink(example.link, confirmationID: example.id)
                  } label: {
                    Label(
                      copiedAutomationLinkID == example.id
                        ? t("settings.automation.copied", "Copied")
                        : t("settings.automation.copy", "Copy"),
                      systemImage: copiedAutomationLinkID == example.id
                        ? "checkmark" : "doc.on.doc"
                    )
                  }
                  .buttonStyle(.borderless)
                  .accessibilityHint(
                    t(
                      "settings.automation.copy_hint",
                      "Copies this ClipNest link without adding it to clipboard history"
                    )
                  )
                }
                .padding(.vertical, 9)
                if index < automationLinkExamples.count - 1 { Divider() }
              }
            }
          }
          .padding(.horizontal, 4)
        } label: {
          Label(
            t("settings.automation.examples", "Ready-to-copy links"),
            systemImage: "doc.on.doc"
          )
        }

        GroupBox {
          VStack(alignment: .leading, spacing: 12) {
            Text(
              t(
                "settings.automation.custom_detail",
                "ClipNest safely encodes spaces, Chinese text, and special characters for you."
              )
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            TextField(
              t("settings.automation.query", "Search query"),
              text: $automationSearchQuery
            )
            .textFieldStyle(.roundedBorder)
            .onChange(of: automationSearchQuery) { _, newValue in
              if newValue.count > ClipNestDeepLink.maximumQueryLength {
                automationSearchQuery = String(
                  newValue.prefix(ClipNestDeepLink.maximumQueryLength)
                )
              }
            }

            HStack {
              Button {
                copyAutomationLink(
                  .search(normalizedAutomationQuery), confirmationID: "custom-search"
                )
              } label: {
                Label(
                  copiedAutomationLinkID == "custom-search"
                    ? t("settings.automation.copied", "Copied")
                    : t("settings.automation.copy_search", "Copy Library search"),
                  systemImage: copiedAutomationLinkID == "custom-search"
                    ? "checkmark" : "magnifyingglass"
                )
              }
              .disabled(normalizedAutomationQuery.isEmpty)

              Button {
                copyAutomationLink(
                  .quickPicker(normalizedAutomationQuery),
                  confirmationID: "custom-picker"
                )
              } label: {
                Label(
                  copiedAutomationLinkID == "custom-picker"
                    ? t("settings.automation.copied", "Copied")
                    : t("settings.automation.copy_picker", "Copy Quick Picker search"),
                  systemImage: copiedAutomationLinkID == "custom-picker"
                    ? "checkmark" : "bolt"
                )
              }
              .disabled(normalizedAutomationQuery.isEmpty)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
              Text(t("settings.automation.pinboards", "Pinboard links"))
                .font(.subheadline.weight(.semibold))
              if store.boards.isEmpty {
                Label(
                  t(
                    "settings.automation.no_pinboards",
                    "Create a Pinboard to generate a direct link to it."
                  ),
                  systemImage: "rectangle.stack.badge.plus"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
              } else {
                Menu {
                  ForEach(store.boards) { board in
                    Button(board.name) {
                      copyAutomationLink(
                        .board(board.name), confirmationID: "board-\(board.id.uuidString)"
                      )
                    }
                  }
                } label: {
                  Label(
                    copiedAutomationLinkID?.hasPrefix("board-") == true
                      ? t("settings.automation.pinboard_copied", "Pinboard link copied")
                      : t("settings.automation.copy_pinboard", "Copy Pinboard link"),
                    systemImage: copiedAutomationLinkID?.hasPrefix("board-") == true
                      ? "checkmark" : "square.grid.2x2"
                  )
                }
              }
            }
          }
          .padding(6)
        } label: {
          Label(
            t("settings.automation.custom", "Build a custom link"),
            systemImage: "wand.and.stars"
          )
        }

        HStack(alignment: .top, spacing: 10) {
          Image(systemName: "checkmark.shield.fill")
            .foregroundStyle(.green)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 3) {
            Text(t("settings.automation.navigation_only", "Navigation only"))
              .font(.subheadline.weight(.semibold))
            Text(
              t(
                "settings.automation.privacy",
                "Copied examples are marked as app-generated and are not added to ClipNest history."
              )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
      }
      .padding(24)
    }
  }

  private func savePrivacyRuleDraft() {
    guard privacyRuleDraftError == nil else { return }
    guard
      store.savePrivacyRule(
        id: editingPrivacyRuleID,
        pattern: privacyRulePattern,
        mode: privacyRuleMode
      )
    else { return }
    resetPrivacyRuleDraft()
  }

  private var supportedConfigurableOCRLanguages: [String] {
    OCRService.supportedConfigurableRecognitionLanguages(supported: supportedOCRLanguages)
  }

  private var availableOCRLanguages: [String] {
    supportedConfigurableOCRLanguages.filter {
      !preferences.ocrPreferredLanguages.contains($0)
    }
  }

  private func ocrLanguageName(_ identifier: String) -> String {
    let localized = Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    let native = Locale(identifier: identifier).localizedString(forIdentifier: identifier)
      ?? localized
    return localized.localizedCaseInsensitiveCompare(native) == .orderedSame
      ? localized
      : "\(localized) · \(native)"
  }

  private var supportDiagnostics: SupportDiagnostics {
    SupportDiagnostics(
      appVersion: SupportDiagnostics.currentAppVersion,
      buildNumber: SupportDiagnostics.currentBuildNumber,
      operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
      architecture: SupportDiagnostics.currentArchitecture,
      clipCount: store.items.count,
      pinnedCount: store.items.count(where: \.isPinned),
      stackCount: store.stackItems.count,
      storageEncrypted: store.isStorageEncrypted,
      storageHealthy: storageHealthIsReady,
      monitoringActive: store.isMonitoring && store.isSessionActive,
      screenshotInboxEnabled: preferences.watchScreenshots,
      screenshotInboxHealthy: !preferences.watchScreenshots || store.screenshotWatchIssue == nil,
      accessibilityGranted: permissions.accessibilityGranted,
      screenRecordingGranted: permissions.screenRecordingGranted,
      quickPickerShortcut: diagnosticShortcutStatus(
        enabled: preferences.hotKeyPreset != .disabled,
        registered: store.quickPickerShortcutRegistrationSucceeded
      ),
      screenOCRShortcut: diagnosticShortcutStatus(
        enabled: preferences.screenOCRHotKeyPreset != .disabled,
        registered: store.screenOCRShortcutRegistrationSucceeded
      ),
      snippetShortcut: diagnosticShortcutStatus(
        enabled: preferences.snippetHotKeyPreset != .disabled,
        registered: store.snippetShortcutRegistrationSucceeded
      ),
      newSnippetShortcut: diagnosticShortcutStatus(
        enabled: preferences.newSnippetHotKeyPreset != .disabled,
        registered: store.newSnippetShortcutRegistrationSucceeded
      ),
      textActionShortcut: diagnosticShortcutStatus(
        enabled: preferences.textActionHotKeyPreset != .disabled,
        registered: store.textActionShortcutRegistrationSucceeded
      )
    )
  }

  private var storageHealthIsReady: Bool {
    store.storageIssue == nil && (store.storageInventory?.missingAttachmentCount ?? 0) == 0
  }

  private func diagnosticShortcutStatus(enabled: Bool, registered: Bool) -> String {
    enabled ? (registered ? "Registered" : "Unavailable") : "Off"
  }

  private func diagnosticsRow(_ title: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title).font(.system(size: 12, weight: .semibold))
      Spacer()
      Text(value)
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.trailing)
    }
  }

  private func aboutStatusCard(
    icon: String,
    title: String,
    detail: String,
    color: Color
  ) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: icon)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(color)
        .frame(width: 30, height: 30)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.system(size: 12, weight: .bold))
        Text(detail)
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(13)
    .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
  }

  private func appContextRow(
    bundleIdentifier: String,
    name: String,
    icon: NSImage?
  ) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 9) {
        if let icon {
          Image(nsImage: icon)
            .resizable()
            .frame(width: 22, height: 22)
        } else {
          Image(systemName: "app.dashed")
            .frame(width: 22, height: 22)
        }
        VStack(alignment: .leading, spacing: 1) {
          Text(name)
          Text(bundleIdentifier)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 12)
        Picker(
          t("settings.context.pinboard", "Pinboard"),
          selection: Binding<UUID?>(
            get: {
              guard let boardID = preferences.appContextBoardID(
                bundleIdentifier: bundleIdentifier
              ), store.boards.contains(where: { $0.id == boardID })
              else { return nil }
              return boardID
            },
            set: {
              preferences.setAppContextBoard($0, bundleIdentifier: bundleIdentifier)
            }
          )
        ) {
          Text(t("settings.context.none", "No context"))
            .tag(UUID?.none)
          ForEach(store.boards) { board in
            Text(board.name).tag(Optional(board.id))
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 180)
      }
      if preferences.appContextBoardID(bundleIdentifier: bundleIdentifier) != nil {
        Toggle(
          t("settings.context.auto_collect", "Automatically collect new copies"),
          isOn: Binding(
            get: {
              preferences.automaticallyCollectsContext(bundleIdentifier: bundleIdentifier)
            },
            set: {
              preferences.setAutomaticallyCollectsContext(
                $0,
                bundleIdentifier: bundleIdentifier
              )
            }
          )
        )
        .font(.caption)
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(.leading, 31)
      }
    }
    .padding(.vertical, 3)
  }

  private func editPrivacyRule(_ rule: ClipboardPrivacyRule) {
    editingPrivacyRuleID = rule.id
    privacyRulePattern = rule.pattern
    privacyRuleMode = rule.mode
  }

  private func resetPrivacyRuleDraft() {
    editingPrivacyRuleID = nil
    privacyRulePattern = ""
    privacyRuleMode = .contains
  }

  private func privacyRuleEvidence(_ rule: ClipboardPrivacyRule) -> String {
    guard rule.matchCount > 0, let lastMatchedAt = rule.lastMatchedAt else {
      return t("privacy_rule.matches.none", "No matches yet")
    }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    let relativeTime = formatter.localizedString(for: lastMatchedAt, relativeTo: .now)
    return L10n.format(
      "privacy_rule.matches.summary",
      fallback: "Blocked %d · %@",
      rule.matchCount,
      relativeTime
    )
  }

  private var quickPickerShortcutStatus: String {
    if preferences.hotKeyPreset == .disabled {
      return t("settings.shortcut.disabled", "Disabled")
    }
    return store.quickPickerShortcutRegistrationSucceeded
      ? t("settings.shortcut.registered", "Registered")
      : t("settings.shortcut.unavailable", "Unavailable")
  }

  private var quickPickerShortcutStatusColor: Color {
    if preferences.hotKeyPreset == .disabled { return .secondary }
    return store.quickPickerShortcutRegistrationSucceeded ? .green : .orange
  }

  private var screenOCRShortcutStatus: String {
    if preferences.screenOCRHotKeyPreset == .disabled {
      return t("settings.shortcut.disabled", "Disabled")
    }
    return store.screenOCRShortcutRegistrationSucceeded
      ? t("settings.shortcut.registered", "Registered")
      : t("settings.shortcut.unavailable", "Unavailable")
  }

  private var screenOCRShortcutStatusColor: Color {
    if preferences.screenOCRHotKeyPreset == .disabled { return .secondary }
    return store.screenOCRShortcutRegistrationSucceeded ? .green : .orange
  }

  private var snippetShortcutStatus: String {
    if preferences.snippetHotKeyPreset == .disabled {
      return t("settings.shortcut.disabled", "Disabled")
    }
    return store.snippetShortcutRegistrationSucceeded
      ? t("settings.shortcut.registered", "Registered")
      : t("settings.shortcut.unavailable", "Unavailable")
  }

  private var snippetShortcutStatusColor: Color {
    if preferences.snippetHotKeyPreset == .disabled { return .secondary }
    return store.snippetShortcutRegistrationSucceeded ? .green : .orange
  }

  private var newSnippetShortcutStatus: String {
    if preferences.newSnippetHotKeyPreset == .disabled {
      return t("settings.shortcut.disabled", "Disabled")
    }
    return store.newSnippetShortcutRegistrationSucceeded
      ? t("settings.shortcut.registered", "Registered")
      : t("settings.shortcut.unavailable", "Unavailable")
  }

  private var newSnippetShortcutStatusColor: Color {
    if preferences.newSnippetHotKeyPreset == .disabled { return .secondary }
    return store.newSnippetShortcutRegistrationSucceeded ? .green : .orange
  }

  private var textActionShortcutStatus: String {
    if preferences.textActionHotKeyPreset == .disabled {
      return t("settings.shortcut.disabled", "Disabled")
    }
    return store.textActionShortcutRegistrationSucceeded
      ? t("settings.shortcut.registered", "Registered")
      : t("settings.shortcut.unavailable", "Unavailable")
  }

  private var textActionShortcutStatusColor: Color {
    if preferences.textActionHotKeyPreset == .disabled { return .secondary }
    return store.textActionShortcutRegistrationSucceeded ? .green : .orange
  }

  private var launchAtLoginStatusText: String {
    switch launchAtLogin.state {
    case .off: t("settings.login.off", "Off")
    case .on: t("settings.login.on", "On")
    case .requiresApproval: t("settings.login.approval", "Approval required")
    case .unavailable:
      t("settings.login.unavailable", "Available after installing ClipNest.app")
    }
  }

  private var automationLinkExamples: [AutomationLinkExample] {
    [
      AutomationLinkExample(
        id: "search",
        title: t("settings.automation.search", "Search for invoice"),
        link: .search("invoice")
      ),
      AutomationLinkExample(
        id: "picker",
        title: t("settings.automation.picker", "Open Quick Picker"),
        link: .quickPicker("")
      ),
      AutomationLinkExample(
        id: "new",
        title: t("settings.automation.new", "Create a snippet"),
        link: .newSnippet
      ),
      AutomationLinkExample(
        id: "actions",
        title: t("settings.automation.actions", "Open Text Actions"),
        link: .textActions
      ),
    ]
  }

  private var normalizedAutomationQuery: String {
    automationSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var normalizedOCRCustomWordDraft: String? {
    OCRService.normalizedCustomWords([ocrCustomWordDraft]).first
  }

  private var canAddOCRCustomWord: Bool {
    guard let normalizedOCRCustomWordDraft,
      preferences.ocrCustomWords.count < OCRService.maximumCustomWordCount
    else { return false }
    return !preferences.ocrCustomWords.contains {
      $0.localizedCaseInsensitiveCompare(normalizedOCRCustomWordDraft) == .orderedSame
    }
  }

  private func addOCRCustomWord() {
    guard preferences.addOCRCustomWord(ocrCustomWordDraft) else { return }
    ocrCustomWordDraft = ""
  }

  private func copyAutomationLink(_ link: ClipNestDeepLink, confirmationID: String) {
    guard store.copyAutomationLink(link) else { return }
    copiedAutomationLinkID = confirmationID
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(2))
      guard copiedAutomationLinkID == confirmationID else { return }
      copiedAutomationLinkID = nil
    }
  }

  private func openLibrary(filter: ClipFilter) {
    store.searchText = ""
    store.selectedTag = nil
    store.selectedBoardID = nil
    store.filter = filter
    dismiss()
  }

  private func shortcutTitle(_ title: String) -> String {
    let key =
      switch title {
      case "Control + Shift + V": "settings.shortcut.control_shift_v"
      case "Option + Space": "settings.shortcut.option_space"
      case "Control + Option + V": "settings.shortcut.control_option_v"
      case "Control + Shift + O": "settings.shortcut.control_shift_o"
      case "Control + Option + O": "settings.shortcut.control_option_o"
      case "Control + Shift + B": "settings.shortcut.control_shift_b"
      case "Control + Option + B": "settings.shortcut.control_option_b"
      case "Control + K": "settings.shortcut.control_k"
      case "Control + Option + K": "settings.shortcut.control_option_k"
      case "Off": "settings.shortcut.off"
      default: ""
      }
    guard !key.isEmpty else { return title }
    return L10n.text(key, fallback: title)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    L10n.text(key, fallback: fallback)
  }
}
