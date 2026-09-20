import AppKit
import SwiftUI

struct WelcomeView: View {
  @ObservedObject var store: ClipStore
  @ObservedObject var preferences: ClipPreferences
  @StateObject private var permissions = PermissionController()
  @State private var isDiscoveringExistingScreenshots = false
  @State private var existingScreenshotCandidates: [URL] = []
  @State private var showingExistingScreenshotConfirmation = false
  let finish: () -> Void

  init(store: ClipStore, finish: @escaping () -> Void) {
    self.store = store
    self.preferences = store.preferences
    self.finish = finish
  }

  private let textColor = BrandTheme.text
  private let actionColor = BrandTheme.action

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      HStack(alignment: .top, spacing: 16) {
        ClipskeinMark()
          .frame(width: 54, height: 54)
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 5) {
          Text(L10n.text("welcome.title", fallback: "Welcome to Clipskein"))
            .font(.system(size: 26, weight: .semibold, design: .rounded))
          Text(
            L10n.text(
              "welcome.subtitle",
              fallback: "Find. Arrange. Reuse."
            )
          )
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(.secondary)
        }
      }

      HStack(alignment: .top, spacing: 12) {
        readinessCard(
          icon: "checkmark.shield.fill",
          title: L10n.text("welcome.private.title", fallback: "Private by default"),
          detail: L10n.text(
            "welcome.private.detail",
            fallback:
              "Clips are stored locally, and likely one-time codes expire automatically."
          ),
          status: L10n.text("welcome.ready", fallback: "Ready"),
          statusColor: .green
        )
        readinessCard(
          icon: "keyboard",
          title: L10n.text("welcome.workflows.title", fallback: "Four global workflows"),
          detail: L10n.text(
            "welcome.workflows.detail",
            fallback:
              "Search history, fill snippets, transform text, or capture screen text without breaking focus."
          ),
          status: L10n.text("welcome.keyboard_first", fallback: "KEYBOARD FIRST"),
          statusColor: actionColor
        )
      }

      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
        shortcutCard(
          title: L10n.text("welcome.quick_picker", fallback: "Quick Picker"),
          detail: L10n.text(
            "welcome.quick_picker.detail", fallback: "Find and paste any memory"),
          shortcut: preferences.hotKeyPreset.display,
          systemImage: "magnifyingglass"
        )
        shortcutCard(
          title: L10n.text("welcome.snippets", fallback: "Snippets"),
          detail: L10n.text(
            "welcome.snippets.detail", fallback: "Open @aliases and templates"),
          shortcut: preferences.snippetHotKeyPreset.display,
          systemImage: "text.badge.star"
        )
        shortcutCard(
          title: L10n.text("welcome.text_actions", fallback: "Text Actions"),
          detail: L10n.text(
            "welcome.text_actions.detail", fallback: "Transform a selection or recent text"),
          shortcut: preferences.textActionHotKeyPreset.display,
          systemImage: "wand.and.sparkles"
        )
        shortcutCard(
          title: L10n.text("welcome.screen_ocr", fallback: "Screen OCR"),
          detail: L10n.text(
            "welcome.screen_ocr.detail", fallback: "Capture and recognize a region"),
          shortcut: preferences.screenOCRHotKeyPreset.display,
          systemImage: "viewfinder"
        )
      }

      screenshotInboxSetup

      VStack(alignment: .leading, spacing: 14) {
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text(
              L10n.text(
                "welcome.accessibility.title",
                fallback: "Optional: paste-back and selected text"
              )
            )
            .font(.system(size: 15, weight: .bold))
            Text(
              L10n.text(
                "welcome.accessibility.detail",
                fallback:
                  "Accessibility lets Return paste into the app you came from and lets Text Actions transform the current selection. Without it, Clipskein copies safely and uses recent text instead."
              )
            )
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          }
          Spacer(minLength: 24)
          Label(
            permissions.accessibilityGranted
              ? L10n.text("welcome.ready", fallback: "Ready")
              : L10n.text("welcome.optional", fallback: "Optional"),
            systemImage: permissions.accessibilityGranted
              ? "checkmark.circle.fill" : "circle.dashed"
          )
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(permissions.accessibilityGranted ? Color.green : Color.orange)
        }

        if !permissions.accessibilityGranted {
          HStack {
            Button(
              L10n.text(
                "welcome.accessibility.allow", fallback: "Allow paste & selection")
            ) { permissions.requestAccessibility() }
            .buttonStyle(.bordered)
            Button(L10n.text("welcome.check_again", fallback: "Check again")) {
              permissions.refresh()
            }
            .buttonStyle(.plain)
            .foregroundStyle(actionColor)
            Button(L10n.text("welcome.open_settings", fallback: "Open Settings")) {
              permissions.openAccessibilitySettings()
            }
            .buttonStyle(.plain)
            .foregroundStyle(actionColor)
          }
        }
      }
      .padding(18)
      .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))

      HStack(alignment: .center) {
        Label(
          preferences.screenOCRHotKeyPreset == .disabled
            ? L10n.text(
              "welcome.screen_ocr.disabled",
              fallback: "Screen Recording is requested only when you choose Screen OCR."
            )
            : L10n.format(
              "welcome.screen_ocr.enabled",
              fallback:
                "%@ starts Screen OCR; permission is requested only when you use it.",
              preferences.screenOCRHotKeyPreset.display
            ),
          systemImage: "viewfinder"
        )
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)

        Spacer()

        Button(L10n.text("welcome.start", fallback: "Start using Clipskein")) { finish() }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(30)
    .frame(width: 660)
    .background(BrandTheme.canvas)
    .foregroundStyle(textColor)
    .tint(actionColor)
    .interactiveDismissDisabled()
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
      Button(L10n.text("common.cancel", fallback: "Cancel"), role: .cancel) {
        existingScreenshotCandidates = []
      }
    } message: {
      Text(
        L10n.text(
          "settings.import_existing_screenshots.confirm_detail",
          fallback:
            "Only likely screenshots in the folder configured by macOS are considered. Files stay in place; Clipskein imports encrypted copies and runs OCR locally."
        )
      )
    }
    .onAppear { permissions.refresh() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    {
      _ in
      permissions.refresh()
    }
  }

  private var screenshotInboxSetup: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: "photo.stack")
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(actionColor)
        .frame(width: 34, height: 34)
        .background(actionColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))

      VStack(alignment: .leading, spacing: 5) {
        Text(L10n.text("welcome.screenshot_inbox.title", fallback: "Screenshot Inbox"))
          .font(.system(size: 14, weight: .bold))
        Text(
          L10n.text(
            "welcome.screenshot_inbox.detail",
            fallback:
              "Make every new macOS screenshot searchable with local OCR. Existing screenshots are ignored."
          )
        )
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

        if let issue = store.screenshotWatchIssue {
          HStack(spacing: 8) {
            Label(issue, systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(Color.orange)
              .lineLimit(2)
            Button(
              store.isRetryingScreenshotWatch
                ? L10n.text("welcome.screenshot_inbox.checking", fallback: "Checking…")
                : L10n.text("welcome.screenshot_inbox.retry", fallback: "Retry now")
            ) {
              Task { await store.retryScreenshotWatching() }
            }
            .buttonStyle(.plain)
            .foregroundStyle(actionColor)
            .disabled(store.isRetryingScreenshotWatch)
          }
          .font(.system(size: 10, weight: .semibold))
        } else if preferences.watchScreenshots {
          Label(
            L10n.text(
              "welcome.screenshot_inbox.active", fallback: "Watching for new screenshots"),
            systemImage: "checkmark.circle.fill"
          )
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(Color.green)
        }

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
          Label(
            isDiscoveringExistingScreenshots
              ? L10n.text(
                "settings.import_existing_screenshots.scanning",
                fallback: "Scanning screenshot folder…"
              )
              : L10n.text(
                "welcome.screenshot_inbox.import_existing",
                fallback: "Review existing screenshots…"
              ),
            systemImage: isDiscoveringExistingScreenshots ? "hourglass" : "clock.arrow.circlepath"
          )
        }
        .buttonStyle(.plain)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(actionColor)
        .disabled(isDiscoveringExistingScreenshots || store.imageImportProgress != nil)

        ScreenshotImportStatusView(store: store, accentColor: actionColor)
      }

      Spacer(minLength: 18)

      Toggle(
        L10n.text("welcome.screenshot_inbox.enable", fallback: "Enable"),
        isOn: Binding(
          get: { preferences.watchScreenshots },
          set: { store.setScreenshotWatching($0) }
        )
      )
      .toggleStyle(.switch)
      .labelsHidden()
      .help(L10n.text("welcome.screenshot_inbox.enable", fallback: "Enable"))
    }
    .padding(16)
    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
  }

  private func readinessCard(
    icon: String,
    title: String,
    detail: String,
    status: String,
    statusColor: Color
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Image(systemName: icon)
          .foregroundStyle(actionColor)
        Spacer()
        Text(status)
          .font(.system(size: 10, weight: .bold, design: .monospaced))
          .foregroundStyle(statusColor)
      }
      Text(title)
        .font(.system(size: 15, weight: .bold))
      Text(detail)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(18)
    .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
  }

  private func shortcutCard(
    title: String,
    detail: String,
    shortcut: String,
    systemImage: String
  ) -> some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(actionColor)
        .frame(width: 30, height: 30)
        .background(actionColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 12, weight: .bold))
        Text(detail)
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer(minLength: 6)
      Text(shortcut)
        .font(.system(size: 10, weight: .bold, design: .monospaced))
        .foregroundStyle(shortcut == "Off" ? Color.orange : actionColor)
        .padding(.horizontal, 7)
        .frame(height: 23)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
    }
    .padding(.horizontal, 12)
    .frame(height: 54)
    .background(Color.primary.opacity(0.028), in: RoundedRectangle(cornerRadius: 11))
  }
}
