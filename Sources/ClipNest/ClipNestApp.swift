import AppKit
import Combine
import SwiftUI

@main
struct ClipNestApp: App {
  @StateObject private var store = ClipStore()
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    WindowGroup {
      ContentView(store: store)
        .frame(minWidth: 840, minHeight: 560)
        .background(.clear)
        .onAppear { appDelegate.configure(store: store) }
    }
    .windowStyle(.hiddenTitleBar)
    .defaultSize(width: 1040, height: 680)
    .commands {
      CommandGroup(replacing: .newItem) {
        Button(newSnippetCommandTitle) {
          AppDelegate.showNewSnippet()
        }
        .keyboardShortcut("n", modifiers: .command)
      }
      CommandGroup(after: .undoRedo) {
        Button(L10n.text("menu.undo_delete", fallback: "Undo Delete")) {
          store.undoLastDeletion()
        }
        .keyboardShortcut("z", modifiers: [.command])
        .disabled(!store.canUndoDeletion)
      }
      CommandMenu(L10n.text("menu.clips", fallback: "Clips")) {
        Button(quickPickerMenuTitle) {
          NotificationCenter.default.post(name: .showQuickPicker, object: nil)
        }
        Button(snippetsMenuTitle) {
          NotificationCenter.default.post(name: .showSnippetPicker, object: nil)
        }
        Button(textActionsMenuTitle) {
          NotificationCenter.default.post(name: .showTextActions, object: nil)
        }
        Divider()
        Button(screenOCRMenuTitle) { store.captureRegion() }
          .keyboardShortcut("4", modifiers: [.command, .shift])
          .disabled(store.isCapturingRegion)
        if let progress = store.imageImportProgress {
          Button(
            progress.isCancelling
              ? L10n.text("main.import.stopping", fallback: "Stopping import…")
              : L10n.format(
                "menu.import_screenshots.cancel",
                fallback: "Stop screenshot import (%d/%d)",
                progress.completed,
                progress.total
              )
          ) {
            store.cancelImageImport()
          }
          .disabled(progress.isCancelling)
        } else {
          Button(L10n.text("menu.import_screenshots", fallback: "Import screenshots…")) {
            store.importImage()
          }
          .keyboardShortcut("o", modifiers: [.command])
        }
        Button(
          store.preferences.watchScreenshots
            ? L10n.text(
              "menu.stop_watching_screenshots", fallback: "Stop watching new screenshots")
            : L10n.text("menu.watch_screenshots", fallback: "Watch new screenshots")
        ) {
          store.setScreenshotWatching(!store.preferences.watchScreenshots)
        }
        Divider()
        Button(L10n.text("menu.export_backup", fallback: "Export encrypted backup…")) {
          ArchiveController.exportArchive(from: store)
        }
        .disabled(!store.canPerformArchiveOperations)
        Button(L10n.text("menu.import_backup", fallback: "Import encrypted backup…")) {
          ArchiveController.importArchive(into: store)
        }
        .disabled(!store.canPerformArchiveOperations)
        Divider()
        Button(
          store.isMonitoring
            ? L10n.text("menu.pause_monitoring", fallback: "Pause monitoring")
            : L10n.text("menu.resume_monitoring", fallback: "Resume monitoring")
        ) {
          store.toggleMonitoring()
        }
        Button(
          store.isIgnoringNextCopy
            ? L10n.text("menu.cancel_ignore_next", fallback: "Cancel Ignore Next Copy")
            : L10n.text("menu.ignore_next", fallback: "Ignore Next Copy")
        ) {
          if store.isIgnoringNextCopy {
            store.cancelIgnoringNextCopy()
          } else {
            store.ignoreNextCopy()
          }
        }
        Divider()
        Button(L10n.text("menu.welcome", fallback: "Welcome & Setup…")) {
          NotificationCenter.default.post(name: .showWelcome, object: nil)
        }
      }
    }

    Settings {
      SettingsView(store: store)
    }

    MenuBarExtra {
      Text(menuMonitoringStatus)
      Text(
        L10n.format(
          "menu.history_status",
          fallback: "%d clips · %d pinned · %d in Stack",
          store.items.count,
          store.items.count { $0.isPinned },
          store.stackItems.count
        )
      )
      if let issue = store.storageIssue {
        Button {
          AppDelegate.showMainWindow()
        } label: {
          Label(issue.message, systemImage: "exclamationmark.triangle.fill")
        }
      }
      Divider()
      Button(L10n.text("menu.open_app", fallback: "Open ClipNest")) {
        AppDelegate.showMainWindow()
      }
      Button(newSnippetMenuTitle) {
        AppDelegate.showNewSnippet()
      }
      Button(quickPickerMenuTitle) {
        NotificationCenter.default.post(name: .showQuickPicker, object: nil)
      }
      Button(snippetsMenuTitle) {
        NotificationCenter.default.post(name: .showSnippetPicker, object: nil)
      }
      Button(textActionsMenuTitle) {
        NotificationCenter.default.post(name: .showTextActions, object: nil)
      }
      Button(screenOCRMenuTitle) { store.captureRegion() }
        .disabled(store.isCapturingRegion)
      Button(
        store.preferences.watchScreenshots
          ? L10n.text(
            "menu.stop_watching_screenshots", fallback: "Stop Watching Screenshots")
          : L10n.text("menu.watch_screenshots", fallback: "Watch New Screenshots")
      ) {
        store.setScreenshotWatching(!store.preferences.watchScreenshots)
      }
      Menu(L10n.text("menu.encrypted_backup", fallback: "Encrypted Backup")) {
        Button(L10n.text("menu.export", fallback: "Export…")) {
          ArchiveController.exportArchive(from: store)
        }
        Button(L10n.text("menu.import", fallback: "Import…")) {
          ArchiveController.importArchive(into: store)
        }
      }
      .disabled(!store.canPerformArchiveOperations)
      Divider()
      Button(
        store.isMonitoring
          ? L10n.text("menu.pause_monitoring", fallback: "Pause monitoring")
          : L10n.text("menu.resume_monitoring", fallback: "Resume monitoring")
      ) {
        store.toggleMonitoring()
      }
      Button(
        store.isIgnoringNextCopy
          ? L10n.text("menu.cancel_ignore_next", fallback: "Cancel Ignore Next Copy")
          : L10n.text("menu.ignore_next", fallback: "Ignore Next Copy")
      ) {
        if store.isIgnoringNextCopy {
          store.cancelIgnoringNextCopy()
        } else {
          store.ignoreNextCopy()
        }
      }
      Menu(L10n.text("menu.pause_for", fallback: "Pause for…")) {
        Button(L10n.text("menu.five_minutes", fallback: "5 minutes")) {
          store.pause(for: 5 * 60)
        }
        Button(L10n.text("menu.one_hour", fallback: "1 hour")) {
          store.pause(for: 60 * 60)
        }
      }
      if let pauseUntil = store.pauseUntil {
        Text(
          L10n.format(
            "menu.resumes",
            fallback: "Resumes %@",
            pauseUntil.formatted(date: .omitted, time: .shortened)
          )
        )
      }
      Divider()
      Button(L10n.text("menu.welcome", fallback: "Welcome & Setup…")) {
        NotificationCenter.default.post(name: .showWelcome, object: nil)
        AppDelegate.showMainWindow()
      }
      SettingsLink { Text(L10n.text("menu.settings", fallback: "Settings…")) }
      Button(L10n.text("menu.quit", fallback: "Quit ClipNest")) { NSApp.terminate(nil) }
    } label: {
      Image(systemName: store.isMonitoring ? "square.on.square" : "pause.circle")
        .accessibilityLabel(menuBarStatusLabel)
    }
  }

  private var menuBarStatusLabel: String {
    L10n.format("menu.status_label", fallback: "ClipNest — %@", menuMonitoringStatus)
  }

  private var menuMonitoringStatus: String {
    if !store.isSessionActive {
      return L10n.text(
        "menu.monitoring_privacy_paused",
        fallback: "Capture paused while this Mac is unavailable"
      )
    }
    if store.isMonitoring {
      return L10n.text("menu.monitoring_active", fallback: "Clipboard monitoring active")
    }
    if let pauseUntil = store.pauseUntil {
      return L10n.format(
        "menu.monitoring_paused_until",
        fallback: "Clipboard monitoring paused until %@",
        pauseUntil.formatted(date: .omitted, time: .shortened))
    }
    return L10n.text("menu.monitoring_paused", fallback: "Clipboard monitoring paused")
  }

  private var quickPickerMenuTitle: String {
    let preset = store.preferences.hotKeyPreset
    if preset != .disabled, !store.quickPickerShortcutRegistrationSucceeded {
      return L10n.text(
        "menu.open_picker_unavailable",
        fallback: "Open Quick Picker — shortcut unavailable")
    }
    return preset == .disabled
      ? L10n.text("menu.open_picker", fallback: "Open Quick Picker")
      : L10n.format(
        "menu.open_picker_shortcut", fallback: "Open Quick Picker — %@", preset.display)
  }

  private var screenOCRMenuTitle: String {
    if store.isCapturingRegion {
      return L10n.text(
        "menu.screen_ocr_running", fallback: "Screen OCR selection in progress…")
    }
    let preset = store.preferences.screenOCRHotKeyPreset
    if preset != .disabled, !store.screenOCRShortcutRegistrationSucceeded {
      return L10n.text(
        "menu.screen_ocr_unavailable", fallback: "Screen OCR… — shortcut unavailable")
    }
    return preset == .disabled
      ? L10n.text("menu.screen_ocr", fallback: "Screen OCR…")
      : L10n.format(
        "menu.screen_ocr_shortcut", fallback: "Screen OCR… — %@", preset.display)
  }

  private var snippetsMenuTitle: String {
    let preset = store.preferences.snippetHotKeyPreset
    if preset != .disabled, !store.snippetShortcutRegistrationSucceeded {
      return L10n.text(
        "menu.open_snippets_unavailable",
        fallback: "Open Snippets — shortcut unavailable")
    }
    return preset == .disabled
      ? L10n.text("menu.open_snippets", fallback: "Open Snippets")
      : L10n.format(
        "menu.open_snippets_shortcut", fallback: "Open Snippets — %@", preset.display)
  }

  private var newSnippetMenuTitle: String {
    let preset = store.preferences.newSnippetHotKeyPreset
    if preset != .disabled, !store.newSnippetShortcutRegistrationSucceeded {
      return L10n.text(
        store.hasPendingNewSnippetDraft
          ? "menu.resume_snippet_unavailable" : "menu.new_snippet_unavailable",
        fallback: store.hasPendingNewSnippetDraft
          ? "Resume Snippet Draft… — shortcut unavailable"
          : "New Snippet… — shortcut unavailable")
    }
    return preset == .disabled
      ? newSnippetCommandTitle
      : L10n.format(
        store.hasPendingNewSnippetDraft
          ? "menu.resume_snippet_shortcut" : "menu.new_snippet_shortcut",
        fallback: store.hasPendingNewSnippetDraft
          ? "Resume Snippet Draft… — %@" : "New Snippet… — %@",
        preset.display)
  }

  private var newSnippetCommandTitle: String {
    store.hasPendingNewSnippetDraft
      ? L10n.text("menu.resume_snippet", fallback: "Resume Snippet Draft…")
      : L10n.text("menu.new_snippet", fallback: "New Snippet…")
  }

  private var textActionsMenuTitle: String {
    let preset = store.preferences.textActionHotKeyPreset
    if preset != .disabled, !store.textActionShortcutRegistrationSucceeded {
      return L10n.text(
        "menu.text_actions_unavailable",
        fallback: "Text Actions — shortcut unavailable")
    }
    return preset == .disabled
      ? L10n.text("menu.open_text_actions", fallback: "Open Text Actions")
      : L10n.format(
        "menu.text_actions_shortcut", fallback: "Text Actions — %@", preset.display)
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private static let activateExistingInstanceNotification = Notification.Name(
    "app.clipnest.ClipNest.activateExistingInstance"
  )

  private var singleInstanceLock: SingleInstanceLock?
  private var isSecondaryInstance = false
  private var hotKey: GlobalHotKey?
  private var screenOCRHotKey: ScreenOCRGlobalHotKey?
  private var snippetHotKey: SnippetGlobalHotKey?
  private var newSnippetHotKey: NewSnippetGlobalHotKey?
  private var textActionHotKey: TextActionGlobalHotKey?
  private var quickPanel: QuickPanelController?
  private var terminationFlushTask: Task<Void, Never>?
  private var shortcutCancellable: AnyCancellable?
  private var screenOCRShortcutCancellable: AnyCancellable?
  private var snippetShortcutCancellable: AnyCancellable?
  private var newSnippetShortcutCancellable: AnyCancellable?
  private var textActionShortcutCancellable: AnyCancellable?
  private var searchWarmupTask: Task<Void, Never>?
  private var newSnippetCaptureTask: Task<Void, Never>?
  private var pendingDeepLinks: [ClipNestDeepLink] = []
  private weak var store: ClipStore?
  private var workspaceSuspensionReasons = Set<WorkspaceSuspensionReason>()

  private enum WorkspaceSuspensionReason: Hashable {
    case inactiveSession
    case systemSleep
    case screenSleep
  }

  override init() {
    super.init()
    DistributedNotificationCenter.default().addObserver(
      self,
      selector: #selector(activateFromAnotherLaunch),
      name: Self.activateExistingInstanceNotification,
      object: nil
    )
  }

  func applicationWillFinishLaunching(_ notification: Notification) {
    guard let lock = SingleInstanceLock.acquireForCurrentUser() else {
      isSecondaryInstance = true
      activateExistingInstance()
      NSApp.terminate(nil)
      return
    }
    singleInstanceLock = lock
    registerWorkspacePrivacyObservers()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard !isSecondaryInstance else { return }
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(showQuickPicker),
      name: .showQuickPicker,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(dismissQuickPicker),
      name: .dismissQuickPicker,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(recoverQuickPickerAfterPasteFailure),
      name: .pasteBackFailed,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(showSnippetPicker),
      name: .showSnippetPicker,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(showTextActions),
      name: .showTextActions,
      object: nil
    )
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    guard !isSecondaryInstance else { return false }
    Self.showMainWindow()
    return true
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    guard !isSecondaryInstance else { return }
    for deepLink in urls.compactMap(ClipNestDeepLink.init(url:)) {
      if store == nil {
        pendingDeepLinks.append(deepLink)
      } else {
        handle(deepLink)
      }
    }
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !isSecondaryInstance, let store,
      store.hasPendingHistoryPersistence || store.hasPendingNewSnippetDraftPersistence
    else {
      return .terminateNow
    }
    guard terminationFlushTask == nil else { return .terminateLater }
    terminationFlushTask = Task { @MainActor [weak self, weak store] in
      await store?.flushPendingHistoryPersistence()
      await store?.flushPendingNewSnippetDraftPersistence()
      self?.terminationFlushTask = nil
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }

  func applicationWillTerminate(_ notification: Notification) {
    NotificationCenter.default.removeObserver(self)
    DistributedNotificationCenter.default().removeObserver(self)
    NSWorkspace.shared.notificationCenter.removeObserver(self)
    searchWarmupTask?.cancel()
    newSnippetCaptureTask?.cancel()
    terminationFlushTask?.cancel()
    store?.cancelImageCopyPreparation()
    store?.cancelImageExport()
    singleInstanceLock?.release()
    singleInstanceLock = nil
  }

  func configure(store: ClipStore) {
    guard !isSecondaryInstance else { return }
    guard self.store == nil else { return }
    self.store = store
    if !workspaceSuspensionReasons.isEmpty { store.suspendForInactiveSession() }
    searchWarmupTask = Task(priority: .utility) { @MainActor [weak store] in
      await store?.warmSearchIndex()
    }
    quickPanel = QuickPanelController(store: store)
    hotKey = GlobalHotKey(preset: store.preferences.hotKeyPreset)
    store.reportQuickPickerShortcutRegistration(hotKey?.registrationSucceeded ?? false)
    if store.preferences.hotKeyPreset != .disabled,
      hotKey?.registrationSucceeded == false
    {
      store.reportNotice(
        L10n.text(
          "shortcut.quick_unavailable",
          fallback: "That shortcut is unavailable. Choose another in Settings."),
        systemImage: "exclamationmark.triangle.fill"
      )
    }
    screenOCRHotKey = ScreenOCRGlobalHotKey(
      preset: store.preferences.screenOCRHotKeyPreset
    ) { [weak store] in
      store?.captureRegion()
    }
    store.reportScreenOCRShortcutRegistration(
      screenOCRHotKey?.registrationSucceeded ?? false
    )
    if store.preferences.screenOCRHotKeyPreset != .disabled,
      screenOCRHotKey?.registrationSucceeded == false
    {
      store.reportNotice(
        L10n.text(
          "shortcut.ocr_unavailable",
          fallback: "The Screen OCR shortcut is unavailable. Choose another in Settings."),
        systemImage: "exclamationmark.triangle.fill"
      )
    }
    snippetHotKey = SnippetGlobalHotKey(preset: store.preferences.snippetHotKeyPreset) {
      NotificationCenter.default.post(name: .showSnippetPicker, object: nil)
    }
    store.reportSnippetShortcutRegistration(snippetHotKey?.registrationSucceeded ?? false)
    if store.preferences.snippetHotKeyPreset != .disabled,
      snippetHotKey?.registrationSucceeded == false
    {
      store.reportNotice(
        L10n.text(
          "shortcut.snippets_unavailable",
          fallback: "The Snippets shortcut is unavailable. Choose another in Settings."),
        systemImage: "exclamationmark.triangle.fill"
      )
    }
    newSnippetHotKey = NewSnippetGlobalHotKey(
      preset: store.preferences.newSnippetHotKeyPreset
    ) { [weak self] in
      self?.showNewSnippetFromSelection()
    }
    store.reportNewSnippetShortcutRegistration(
      newSnippetHotKey?.registrationSucceeded ?? false
    )
    if store.preferences.newSnippetHotKeyPreset != .disabled,
      newSnippetHotKey?.registrationSucceeded == false
    {
      store.reportNotice(
        L10n.text(
          "shortcut.new_snippet_unavailable",
          fallback: "The New Snippet shortcut is unavailable. Choose another in Settings."),
        systemImage: "exclamationmark.triangle.fill"
      )
    }
    textActionHotKey = TextActionGlobalHotKey(
      preset: store.preferences.textActionHotKeyPreset
    ) {
      NotificationCenter.default.post(name: .showTextActions, object: nil)
    }
    store.reportTextActionShortcutRegistration(
      textActionHotKey?.registrationSucceeded ?? false
    )
    if store.preferences.textActionHotKeyPreset != .disabled,
      textActionHotKey?.registrationSucceeded == false
    {
      store.reportNotice(
        L10n.text(
          "shortcut.actions_unavailable",
          fallback: "The Text Actions shortcut is unavailable. Choose another in Settings."),
        systemImage: "exclamationmark.triangle.fill"
      )
    }
    shortcutCancellable = store.preferences.$hotKeyPreset
      .dropFirst()
      .sink { [weak self, weak store] preset in
        Task { @MainActor in
          guard let self, let store else { return }
          let succeeded = self.hotKey?.update(to: preset) ?? false
          store.reportQuickPickerShortcutRegistration(succeeded)
          if !succeeded {
            store.reportNotice(
              L10n.format(
                "shortcut.value_unavailable",
                fallback: "%@ is unavailable. Choose another shortcut.",
                preset.title),
              systemImage: "exclamationmark.triangle.fill"
            )
          } else if preset == .disabled {
            store.reportNotice(
              L10n.text("shortcut.quick_disabled", fallback: "Quick picker shortcut disabled"),
              systemImage: "keyboard")
          } else {
            store.reportNotice(
              L10n.format(
                "shortcut.quick_changed",
                fallback: "Quick picker shortcut changed to %@",
                preset.display),
              systemImage: "checkmark.circle.fill"
            )
          }
        }
      }

    screenOCRShortcutCancellable = store.preferences.$screenOCRHotKeyPreset
      .dropFirst()
      .sink { [weak self, weak store] preset in
        Task { @MainActor in
          guard let self, let store else { return }
          let succeeded = self.screenOCRHotKey?.update(to: preset) ?? false
          store.reportScreenOCRShortcutRegistration(succeeded)
          if !succeeded {
            store.reportNotice(
              L10n.format(
                "shortcut.ocr_value_unavailable",
                fallback: "%@ is unavailable. Choose another Screen OCR shortcut.",
                preset.title),
              systemImage: "exclamationmark.triangle.fill"
            )
          } else if preset == .disabled {
            store.reportNotice(
              L10n.text("shortcut.ocr_disabled", fallback: "Screen OCR shortcut disabled"),
              systemImage: "keyboard")
          } else {
            store.reportNotice(
              L10n.format(
                "shortcut.ocr_changed",
                fallback: "Screen OCR shortcut changed to %@",
                preset.display),
              systemImage: "checkmark.circle.fill"
            )
          }
        }
      }

    snippetShortcutCancellable = store.preferences.$snippetHotKeyPreset
      .dropFirst()
      .sink { [weak self, weak store] preset in
        Task { @MainActor in
          guard let self, let store else { return }
          let succeeded = self.snippetHotKey?.update(to: preset) ?? false
          store.reportSnippetShortcutRegistration(succeeded)
          if !succeeded {
            store.reportNotice(
              L10n.format(
                "shortcut.snippets_value_unavailable",
                fallback: "%@ is unavailable. Choose another Snippets shortcut.",
                preset.title),
              systemImage: "exclamationmark.triangle.fill"
            )
          } else if preset == .disabled {
            store.reportNotice(
              L10n.text("shortcut.snippets_disabled", fallback: "Snippets shortcut disabled"),
              systemImage: "keyboard")
          } else {
            store.reportNotice(
              L10n.format(
                "shortcut.snippets_changed",
                fallback: "Snippets shortcut changed to %@",
                preset.display),
              systemImage: "checkmark.circle.fill"
            )
          }
        }
      }

    newSnippetShortcutCancellable = store.preferences.$newSnippetHotKeyPreset
      .dropFirst()
      .sink { [weak self, weak store] preset in
        Task { @MainActor in
          guard let self, let store else { return }
          let succeeded = self.newSnippetHotKey?.update(to: preset) ?? false
          store.reportNewSnippetShortcutRegistration(succeeded)
          if !succeeded {
            store.reportNotice(
              L10n.format(
                "shortcut.new_snippet_value_unavailable",
                fallback: "%@ is unavailable. Choose another New Snippet shortcut.",
                preset.title),
              systemImage: "exclamationmark.triangle.fill"
            )
          } else if preset == .disabled {
            store.reportNotice(
              L10n.text(
                "shortcut.new_snippet_disabled", fallback: "New Snippet shortcut disabled"),
              systemImage: "keyboard")
          } else {
            store.reportNotice(
              L10n.format(
                "shortcut.new_snippet_changed",
                fallback: "New Snippet shortcut changed to %@",
                preset.display),
              systemImage: "checkmark.circle.fill"
            )
          }
        }
      }

    textActionShortcutCancellable = store.preferences.$textActionHotKeyPreset
      .dropFirst()
      .sink { [weak self, weak store] preset in
        Task { @MainActor in
          guard let self, let store else { return }
          let succeeded = self.textActionHotKey?.update(to: preset) ?? false
          store.reportTextActionShortcutRegistration(succeeded)
          if !succeeded {
            store.reportNotice(
              L10n.format(
                "shortcut.actions_value_unavailable",
                fallback: "%@ is unavailable. Choose another Text Actions shortcut.",
                preset.title),
              systemImage: "exclamationmark.triangle.fill"
            )
          } else if preset == .disabled {
            store.reportNotice(
              L10n.text("shortcut.actions_disabled", fallback: "Text Actions shortcut disabled"),
              systemImage: "keyboard")
          } else {
            store.reportNotice(
              L10n.format(
                "shortcut.actions_changed",
                fallback: "Text Actions shortcut changed to %@",
                preset.display),
              systemImage: "checkmark.circle.fill"
            )
          }
        }
      }

    let queuedDeepLinks = pendingDeepLinks
    pendingDeepLinks.removeAll(keepingCapacity: false)
    queuedDeepLinks.forEach(handle)
  }

  static func showMainWindow() {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.windows.first(where: { !($0 is NSPanel) && $0.canBecomeKey })?.makeKeyAndOrderFront(nil)
  }

  static func showNewSnippet() {
    showMainWindow()
    DispatchQueue.main.async {
      NotificationCenter.default.post(name: .showNewSnippet, object: nil)
    }
  }

  private func handle(_ deepLink: ClipNestDeepLink) {
    guard let store else { return }
    switch deepLink {
    case .open:
      Self.showMainWindow()
    case .search(let query):
      store.searchText = query
      store.filter = .all
      store.selectedTag = nil
      store.selectedBoardID = nil
      store.normalizeSelection()
      Self.showMainWindow()
    case .newSnippet:
      Self.showNewSnippet()
    case .quickPicker(let query):
      quickPanel?.show(initialQuery: query)
    case .snippets:
      quickPanel?.show(initialQuery: "@")
    case .textActions:
      quickPanel?.showTextActions()
    case .board(let name):
      guard
        let board = store.boards.first(where: {
          $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        })
      else {
        store.reportNotice(
          L10n.format(
            "deep_link.board_missing",
            fallback: "No Pinboard named %@ was found.",
            name
          ),
          systemImage: "rectangle.stack.badge.minus"
        )
        Self.showMainWindow()
        return
      }
      store.searchText = ""
      store.filter = .all
      store.selectedTag = nil
      store.selectedBoardID = board.id
      store.normalizeSelection()
      Self.showMainWindow()
    }
  }

  private func showNewSnippetFromSelection() {
    guard let store else {
      Self.showNewSnippet()
      return
    }
    guard !store.hasPendingNewSnippetDraft else {
      Self.showNewSnippet()
      return
    }
    let sourceApplication = NSWorkspace.shared.frontmostApplication
    newSnippetCaptureTask?.cancel()
    newSnippetCaptureTask = Task { @MainActor [weak self, weak store] in
      guard let self, let store else { return }
      let result = await store.captureSelectedText(
        from: sourceApplication,
        maximumCharacters: nil,
        maximumUTF8Bytes: ClipStore.maximumEditedTextBytes
      )
      guard !Task.isCancelled, store.isSessionActive else { return }
      switch result {
      case .captured(let item):
        store.updatePendingNewSnippetDraft(
          NewSnippetDraft(
            text: item.text,
            title: "",
            alias: "",
            conceal: false,
            tags: [],
            boardID: nil,
            sourceApplication: item.sourceApplication,
            sourceBundleIdentifier: item.sourceBundleIdentifier,
            richTextData: item.richTextData
          )
        )
      case .permissionRequired:
        store.reportNotice(
          L10n.text(
            "new_snippet.selection_permission",
            fallback: "Opened an empty draft. Allow Accessibility to capture selected text."),
          systemImage: "hand.raised.fill")
      case .protectedApplication:
        store.reportNotice(
          L10n.text(
            "new_snippet.selection_protected",
            fallback: "Opened an empty draft. Selection capture is blocked for this app."),
          systemImage: "lock.shield.fill")
      case .clipboardPreservationUnavailable:
        store.reportNotice(
          L10n.text(
            "new_snippet.selection_clipboard_preserved",
            fallback: "Opened an empty draft because the clipboard could not be preserved safely."),
          systemImage: "doc.on.clipboard")
      case .selectionTooLarge:
        store.reportNotice(
          L10n.format(
            "new_snippet.selection_too_large",
            fallback: "Opened an empty draft. Keep selected text under %d MB.",
            ClipStore.maximumEditedTextBytes / 1_024 / 1_024),
          systemImage: "doc.badge.ellipsis")
      case .noSelection:
        break
      }
      self.newSnippetCaptureTask = nil
      Self.showNewSnippet()
    }
  }

  private func registerWorkspacePrivacyObservers() {
    let center = NSWorkspace.shared.notificationCenter
    center.addObserver(
      self,
      selector: #selector(sessionDidResignActive),
      name: NSWorkspace.sessionDidResignActiveNotification,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(sessionDidBecomeActive),
      name: NSWorkspace.sessionDidBecomeActiveNotification,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(workspaceWillSleep),
      name: NSWorkspace.willSleepNotification,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(workspaceDidWake),
      name: NSWorkspace.didWakeNotification,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(screensDidSleep),
      name: NSWorkspace.screensDidSleepNotification,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(screensDidWake),
      name: NSWorkspace.screensDidWakeNotification,
      object: nil
    )
  }

  private func suspend(for reason: WorkspaceSuspensionReason) {
    workspaceSuspensionReasons.insert(reason)
    newSnippetCaptureTask?.cancel()
    newSnippetCaptureTask = nil
    NotificationCenter.default.post(name: .privacySessionDidSuspend, object: nil)
    quickPanel?.suspendForPrivacy()
    ArchiveController.cancelForPrivacySuspension()
    store?.suspendForInactiveSession()
  }

  private func resume(from reason: WorkspaceSuspensionReason) {
    workspaceSuspensionReasons.remove(reason)
    guard workspaceSuspensionReasons.isEmpty else { return }
    store?.resumeAfterInactiveSession()
  }

  @objc private func sessionDidResignActive() {
    suspend(for: .inactiveSession)
  }

  @objc private func sessionDidBecomeActive() {
    resume(from: .inactiveSession)
  }

  @objc private func workspaceWillSleep() {
    suspend(for: .systemSleep)
  }

  @objc private func workspaceDidWake() {
    resume(from: .systemSleep)
  }

  @objc private func screensDidSleep() {
    suspend(for: .screenSleep)
  }

  @objc private func screensDidWake() {
    resume(from: .screenSleep)
  }

  private func activateExistingInstance() {
    if let bundleIdentifier = Bundle.main.bundleIdentifier {
      let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
      NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        .first { $0.processIdentifier != currentProcessIdentifier && !$0.isTerminated }?
        .activate(options: [.activateAllWindows])
    }
    DistributedNotificationCenter.default().post(
      name: Self.activateExistingInstanceNotification,
      object: nil
    )
  }

  @objc private func activateFromAnotherLaunch() {
    guard !isSecondaryInstance else { return }
    Self.showMainWindow()
  }

  @objc private func showQuickPicker() {
    quickPanel?.toggle()
  }

  @objc private func showSnippetPicker() {
    quickPanel?.show(initialQuery: "@")
  }

  @objc private func showTextActions() {
    quickPanel?.showTextActions()
  }

  @objc private func dismissQuickPicker() {
    quickPanel?.dismiss()
  }

  @objc private func recoverQuickPickerAfterPasteFailure() {
    quickPanel?.recoverAfterPasteFailure()
  }
}
