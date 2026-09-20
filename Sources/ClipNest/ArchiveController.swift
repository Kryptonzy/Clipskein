import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum ArchiveController {
  private static var operationTask: Task<Void, Never>?
  private static var progressPanel: ArchiveProgressPanel?

  static func cancelForPrivacySuspension() {
    guard operationTask != nil else { return }
    operationTask?.cancel()
    progressPanel?.markCancelling()
  }

  static func exportArchive(from store: ClipStore) {
    guard operationTask == nil else {
      showOperationAlreadyRunning()
      return
    }
    guard let password = requestPassword(confirm: true) else { return }

    let panel = NSSavePanel()
    panel.allowedContentTypes = [.data]
    panel.nameFieldStringValue = L10n.format(
      "archive.export.default_name",
      fallback: "ClipNest Backup.%@",
      ClipArchive.fileExtension)
    panel.message = L10n.text(
      "archive.export.panel_message",
      fallback: "Save an encrypted backup of your complete ClipNest history.")
    guard panel.runModal() == .OK, let url = panel.url else { return }

    let progress = ArchiveProgressPanel(
      title: L10n.text("archive.progress.export_title", fallback: "Creating encrypted backup"),
      detail: L10n.text(
        "archive.progress.export_detail",
        fallback: "Reading local attachments and encrypting them. ClipNest stays usable."
      )
    )
    beginOperation(progress: progress)
    operationTask = Task {
      do {
        let data = try await store.makeEncryptedArchiveInBackground(password: password)
        try Task.checkCancellation()
        progress.update(
          detail: L10n.text(
            "archive.progress.saving", fallback: "Finishing the backup file…")
        )
        progress.setCancellable(false)
        try await writeArchiveData(data, to: url)
        finishOperation()
        showExportSuccess(url: url)
      } catch is CancellationError {
        finishOperation()
      } catch {
        finishOperation()
        showError(error)
      }
    }
  }

  static func importArchive(into store: ClipStore) {
    guard operationTask == nil else {
      showOperationAlreadyRunning()
      return
    }
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.data]
    panel.allowsMultipleSelection = false
    panel.message = L10n.text(
      "archive.import.panel_message",
      fallback:
        "Choose an encrypted ClipNest archive to merge. Your current history will not be replaced."
    )
    guard panel.runModal() == .OK, let url = panel.url else { return }
    guard let password = requestPassword(confirm: false) else { return }

    let progress = ArchiveProgressPanel(
      title: L10n.text("archive.progress.import_title", fallback: "Opening encrypted backup"),
      detail: L10n.text(
        "archive.progress.import_detail",
        fallback: "Verifying the password and archive without replacing current history."
      )
    )
    beginOperation(progress: progress)
    operationTask = Task {
      do {
        let data = try await readArchiveData(from: url)
        try Task.checkCancellation()
        progress.update(
          detail: L10n.text(
            "archive.progress.merging", fallback: "Verifying and merging archive entries…")
        )
        let result = try await store.importEncryptedArchiveInBackground(
          data,
          password: password
        )
        finishOperation()
        showMessage(
          title: L10n.text("archive.import.success_title", fallback: "Archive imported"),
          detail: L10n.format(
            "archive.import.success_detail",
            fallback:
              "Added %d clips, merged %d, restored %d Stack items, %d Pinboards, and %d saved views; skipped %d invalid entries. Current history was kept.",
            result.added,
            result.merged,
            result.stacked,
            result.boards,
            result.savedViews,
            result.skipped
          )
        )
      } catch is CancellationError {
        finishOperation()
      } catch {
        finishOperation()
        showError(error)
      }
    }
  }

  private static func beginOperation(progress: ArchiveProgressPanel) {
    progress.onCancel = {
      operationTask?.cancel()
      progress.markCancelling()
    }
    progressPanel = progress
    progress.show()
  }

  private static func finishOperation() {
    progressPanel?.close()
    progressPanel = nil
    operationTask = nil
  }

  private static func readArchiveData(from url: URL) async throws -> Data {
    let worker = Task.detached(priority: .userInitiated) {
      try Data(contentsOf: url, options: .mappedIfSafe)
    }
    return try await withTaskCancellationHandler {
      try await worker.value
    } onCancel: {
      worker.cancel()
    }
  }

  private static func writeArchiveData(_ data: Data, to url: URL) async throws {
    let worker = Task.detached(priority: .userInitiated) {
      try Task.checkCancellation()
      try data.write(to: url, options: .atomic)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: url.path
      )
    }
    try await withTaskCancellationHandler {
      try await worker.value
    } onCancel: {
      worker.cancel()
    }
  }

  private static func showOperationAlreadyRunning() {
    showMessage(
      title: L10n.text("archive.progress.busy_title", fallback: "Backup operation in progress"),
      detail: L10n.text(
        "archive.progress.busy_detail",
        fallback: "Finish or cancel the current backup operation before starting another."
      )
    )
  }

  private static func requestPassword(confirm: Bool) -> String? {
    var passwordValue = ""
    var confirmationValue = ""
    while true {
      let password = NSSecureTextField(string: passwordValue)
      password.placeholderString = L10n.text("archive.password", fallback: "Password")
      password.frame.size.width = 320

      let fields = [password]
      let confirmation = NSSecureTextField(string: "")
      if confirm {
        confirmation.stringValue = confirmationValue
        confirmation.placeholderString = L10n.text(
          "archive.confirm_password", fallback: "Confirm password")
        confirmation.frame.size.width = 320
      }
      let stack = NSStackView(views: confirm ? fields + [confirmation] : fields)
      stack.orientation = .vertical
      stack.spacing = 8
      stack.frame = NSRect(x: 0, y: 0, width: 320, height: confirm ? 54 : 24)

      let alert = NSAlert()
      alert.messageText =
        confirm
        ? L10n.text("archive.protect_title", fallback: "Protect this backup")
        : L10n.text("archive.unlock_title", fallback: "Unlock this backup")
      alert.informativeText =
        confirm
        ? L10n.text(
          "archive.protect_detail",
          fallback: "Use at least 8 characters. ClipNest cannot recover a forgotten password.")
        : L10n.text(
          "archive.unlock_detail", fallback: "Enter the password used when this backup was created."
        )
      alert.accessoryView = stack
      alert.addButton(
        withTitle: confirm
          ? L10n.text("archive.create", fallback: "Create Backup")
          : L10n.text("archive.unlock", fallback: "Unlock"))
      alert.addButton(withTitle: L10n.text("archive.cancel", fallback: "Cancel"))
      guard alert.runModal() == .alertFirstButtonReturn else { return nil }

      passwordValue = password.stringValue
      confirmationValue = confirmation.stringValue

      if passwordValue.isEmpty {
        showMessage(
          title: L10n.text("archive.password_required_title", fallback: "Password required"),
          detail: L10n.text(
            "archive.password_required_detail", fallback: "Enter the archive password."))
        continue
      }
      if confirm, passwordValue.count < 8 {
        showMessage(
          title: L10n.text("archive.password_short_title", fallback: "Password too short"),
          detail: L10n.text(
            "archive.password_short_detail",
            fallback: "Use at least 8 characters. Your entries are still filled in."))
        continue
      }
      if confirm, passwordValue != confirmationValue {
        showMessage(
          title: L10n.text(
            "archive.password_mismatch_title", fallback: "Passwords do not match"),
          detail: L10n.text(
            "archive.password_mismatch_detail",
            fallback: "Correct either password and try again; both entries are preserved."))
        continue
      }
      return passwordValue
    }
  }

  private static func showError(_ error: Error) {
    let recovery = (error as? LocalizedError)?.recoverySuggestion
    let detail = [error.localizedDescription, recovery]
      .compactMap { $0 }
      .joined(separator: "\n\n")
    showMessage(
      title: L10n.text("archive.failed_title", fallback: "Archive operation failed"),
      detail: detail)
  }

  private static func showExportSuccess(url: URL) {
    let alert = NSAlert()
    alert.messageText = L10n.text(
      "archive.export.success_title", fallback: "Encrypted backup created")
    alert.informativeText = L10n.text(
      "archive.export.success_detail",
      fallback:
        "Text, images, OCR, usage history, Stack, Pinboards, and saved views were encrypted and saved. Keep the password separately; ClipNest cannot recover it."
    )
    alert.addButton(withTitle: L10n.text("archive.show_finder", fallback: "Show in Finder"))
    alert.addButton(withTitle: L10n.text("archive.done", fallback: "Done"))
    if alert.runModal() == .alertFirstButtonReturn {
      NSWorkspace.shared.activateFileViewerSelecting([url])
    }
  }

  private static func showMessage(title: String, detail: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = detail
    alert.addButton(withTitle: L10n.text("archive.ok", fallback: "OK"))
    alert.runModal()
  }
}

@MainActor
private final class ArchiveProgressPanel {
  var onCancel: (() -> Void)?

  private let panel: NSPanel
  private let detailLabel = NSTextField(wrappingLabelWithString: "")
  private let cancelButton = NSButton()

  init(title: String, detail: String) {
    panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 430, height: 154),
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    panel.title = title
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.hidesOnDeactivate = false

    let indicator = NSProgressIndicator()
    indicator.style = .spinning
    indicator.controlSize = .regular
    indicator.startAnimation(nil)
    indicator.setContentHuggingPriority(.required, for: .horizontal)

    detailLabel.stringValue = detail
    detailLabel.textColor = .secondaryLabelColor
    detailLabel.maximumNumberOfLines = 3

    let row = NSStackView(views: [indicator, detailLabel])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 14

    cancelButton.title = L10n.text("archive.cancel", fallback: "Cancel")
    cancelButton.bezelStyle = .rounded
    cancelButton.target = self
    cancelButton.action = #selector(cancel)

    let buttonRow = NSStackView(views: [NSView(), cancelButton])
    buttonRow.orientation = .horizontal
    buttonRow.distribution = .fill

    let stack = NSStackView(views: [row, buttonRow])
    stack.orientation = .vertical
    stack.spacing = 18
    stack.translatesAutoresizingMaskIntoConstraints = false
    panel.contentView = NSView()
    panel.contentView?.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor, constant: 22),
      stack.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor, constant: -22),
      stack.topAnchor.constraint(equalTo: panel.contentView!.topAnchor, constant: 22),
      stack.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor, constant: -18),
      detailLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 320),
    ])
  }

  func show() {
    panel.center()
    panel.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func update(detail: String) {
    detailLabel.stringValue = detail
  }

  func markCancelling() {
    detailLabel.stringValue = L10n.text(
      "archive.progress.cancelling",
      fallback: "Stopping safely…"
    )
    cancelButton.isEnabled = false
  }

  func setCancellable(_ isCancellable: Bool) {
    cancelButton.isEnabled = isCancellable
  }

  func close() {
    panel.orderOut(nil)
    panel.close()
  }

  @objc private func cancel() {
    onCancel?()
  }
}
