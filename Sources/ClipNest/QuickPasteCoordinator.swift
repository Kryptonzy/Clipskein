import AppKit
import ApplicationServices

enum QuickPasteResult: Equatable {
  case pasteRequested
  case copiedOnly
  case permissionRequired
  case copyFailed
  case clipboardChanged
}

enum PasteBackFailureReason: Sendable {
  case destinationUnavailable
  case clipboardChanged
}

struct PasteBackFailure: Sendable {
  let targetName: String?
  let reason: PasteBackFailureReason
}

@MainActor
final class QuickPasteCoordinator {
  private(set) var targetApplication: NSRunningApplication?
  private var pendingPasteboardChangeCount: Int?
  private var pasteAttemptID: UUID?

  var targetApplicationName: String? {
    guard let targetApplication,
      Self.isEligiblePasteTarget(
        isCurrentProcess: targetApplication.processIdentifier
          == ProcessInfo.processInfo.processIdentifier,
        isTerminated: targetApplication.isTerminated,
        isRegularApplication: targetApplication.activationPolicy == .regular
      )
    else { return nil }
    return targetApplication.localizedName
  }

  var targetApplicationBundleIdentifier: String? {
    guard let targetApplication, targetApplicationName != nil else { return nil }
    return targetApplication.bundleIdentifier
  }

  func captureTargetApplication() {
    clearPendingPaste()
    guard let application = NSWorkspace.shared.frontmostApplication,
      Self.isEligiblePasteTarget(
        isCurrentProcess: application.processIdentifier
          == ProcessInfo.processInfo.processIdentifier,
        isTerminated: application.isTerminated,
        isRegularApplication: application.activationPolicy == .regular
      )
    else {
      targetApplication = nil
      return
    }
    targetApplication = application
  }

  func paste(_ item: ClipItem, using store: ClipStore) -> QuickPasteResult {
    let copySucceeded: Bool
    if usesPlainTextDefault(for: item, using: store) {
      copySucceeded =
        item.isConcealed
        ? store.secureCopyText(item.text, recording: item)
        : store.copyText(item.text, recording: item)
    } else {
      copySucceeded = item.isConcealed ? store.secureCopy(item) : store.copy(item)
    }
    return finishPaste(copySucceeded: copySucceeded)
  }

  func pasteAfterPreparingImage(_ item: ClipItem, using store: ClipStore) async
    -> QuickPasteResult
  {
    guard item.kind == .image else { return paste(item, using: store) }
    let copySucceeded = await store.copyForUse(item, securely: item.isConcealed)
    return finishPaste(copySucceeded: copySucceeded)
  }

  func usesPlainTextDefault(for item: ClipItem, using store: ClipStore) -> Bool {
    Self.shouldUsePlainText(
      for: item,
      targetBundleIdentifier: targetApplicationBundleIdentifier,
      plainTextBundleIDs: store.preferences.plainTextBundleIDs
    )
  }

  static func shouldUsePlainText(
    for item: ClipItem,
    targetBundleIdentifier: String?,
    plainTextBundleIDs: Set<String>
  ) -> Bool {
    guard item.kind == .text, item.hasRichText, let targetBundleIdentifier else { return false }
    return plainTextBundleIDs.contains(targetBundleIdentifier)
  }

  func paste(text: String, from item: ClipItem, using store: ClipStore) -> QuickPasteResult {
    let copySucceeded =
      item.isConcealed
      ? store.secureCopyText(text, recording: item)
      : store.copyText(text, recording: item)
    return finishPaste(copySucceeded: copySucceeded)
  }

  func pasteStack(
    format: ClipStackFormat = .paragraphs,
    using store: ClipStore
  ) -> QuickPasteResult {
    finishPaste(copySucceeded: store.copyStack(format: format))
  }

  func pasteNextStackItem(using store: ClipStore) -> QuickPasteResult {
    finishPaste(copySucceeded: store.copyNextStackItem())
  }

  private func finishPaste(copySucceeded: Bool) -> QuickPasteResult {
    clearPendingPaste()
    let hasUsableTarget = targetApplication?.isTerminated == false
    let accessibilityGranted = hasUsableTarget && AXIsProcessTrusted()
    let result = Self.expectedResult(
      copySucceeded: copySucceeded,
      hasUsableTarget: hasUsableTarget,
      accessibilityGranted: accessibilityGranted
    )
    guard result == .pasteRequested else { return result }
    pendingPasteboardChangeCount = NSPasteboard.general.changeCount
    return requestPasteDelivery()
  }

  func retryPasteDelivery() -> QuickPasteResult {
    let hasPendingPayload = pendingPasteboardChangeCount != nil
    let clipboardUnchanged = pendingPasteboardChangeCount == NSPasteboard.general.changeCount
    let hasUsableTarget = targetApplication?.isTerminated == false
    let result = Self.expectedRetryResult(
      hasPendingPayload: hasPendingPayload,
      clipboardUnchanged: clipboardUnchanged,
      hasUsableTarget: hasUsableTarget,
      accessibilityGranted: hasUsableTarget && AXIsProcessTrusted()
    )
    guard result == .pasteRequested else {
      clearPendingPaste()
      return result
    }
    return requestPasteDelivery()
  }

  private func requestPasteDelivery() -> QuickPasteResult {
    guard let targetApplication else {
      clearPendingPaste()
      return .copiedOnly
    }

    guard targetApplication.activate(options: []) else {
      clearPendingPaste()
      return .copiedOnly
    }
    let targetName = targetApplication.localizedName
    let attemptID = UUID()
    pasteAttemptID = attemptID
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(140))
      guard let self, pasteAttemptID == attemptID else { return }
      guard pendingPasteboardChangeCount == NSPasteboard.general.changeCount else {
        clearPendingPaste()
        NotificationCenter.default.post(
          name: .pasteBackFailed,
          object: PasteBackFailure(targetName: targetName, reason: .clipboardChanged)
        )
        return
      }
      guard
        Self.canDeliverPaste(
          targetIsTerminated: targetApplication.isTerminated,
          targetIsActive: targetApplication.isActive,
          frontmostProcessIdentifier: NSWorkspace.shared.frontmostApplication?.processIdentifier,
          targetProcessIdentifier: targetApplication.processIdentifier
        ),
        Self.postPasteShortcut()
      else {
        NotificationCenter.default.post(
          name: .pasteBackFailed,
          object: PasteBackFailure(targetName: targetName, reason: .destinationUnavailable)
        )
        return
      }
      clearPendingPaste()
    }
    return .pasteRequested
  }

  func restoreTargetApplication() {
    guard let targetApplication, !targetApplication.isTerminated else { return }
    targetApplication.activate(options: [])
  }

  func suspendForPrivacy() {
    clearPendingPaste()
    targetApplication = nil
  }

  static func expectedResult(
    copySucceeded: Bool,
    hasUsableTarget: Bool,
    accessibilityGranted: Bool
  ) -> QuickPasteResult {
    guard copySucceeded else { return .copyFailed }
    guard hasUsableTarget else { return .copiedOnly }
    guard accessibilityGranted else { return .permissionRequired }
    return .pasteRequested
  }

  nonisolated static func expectedRetryResult(
    hasPendingPayload: Bool,
    clipboardUnchanged: Bool,
    hasUsableTarget: Bool,
    accessibilityGranted: Bool
  ) -> QuickPasteResult {
    guard hasPendingPayload, clipboardUnchanged else { return .clipboardChanged }
    guard hasUsableTarget else { return .copiedOnly }
    guard accessibilityGranted else { return .permissionRequired }
    return .pasteRequested
  }

  nonisolated static func isEligiblePasteTarget(
    isCurrentProcess: Bool,
    isTerminated: Bool,
    isRegularApplication: Bool
  ) -> Bool {
    !isCurrentProcess && !isTerminated && isRegularApplication
  }

  nonisolated static func canDeliverPaste(
    targetIsTerminated: Bool,
    targetIsActive: Bool,
    frontmostProcessIdentifier: pid_t?,
    targetProcessIdentifier: pid_t
  ) -> Bool {
    !targetIsTerminated && targetIsActive
      && frontmostProcessIdentifier == targetProcessIdentifier
  }

  private static func postPasteShortcut() -> Bool {
    guard let source = CGEventSource(stateID: .combinedSessionState),
      let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
      let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
    else { return false }

    keyDown.flags = .maskCommand
    keyUp.flags = .maskCommand
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
    return true
  }

  private func clearPendingPaste() {
    pendingPasteboardChangeCount = nil
    pasteAttemptID = nil
  }
}
