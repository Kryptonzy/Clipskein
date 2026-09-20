import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation

@MainActor
final class PermissionController: ObservableObject {
  @Published private(set) var accessibilityGranted = false
  @Published private(set) var screenRecordingGranted = false

  init() {
    refresh()
  }

  func refresh() {
    accessibilityGranted = AXIsProcessTrusted()
    screenRecordingGranted = CGPreflightScreenCaptureAccess()
  }

  func requestAccessibility() {
    // The exported C global is not concurrency-annotated in current SDKs; use its documented key.
    let promptKey = "AXTrustedCheckOptionPrompt"
    accessibilityGranted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
  }

  func requestScreenRecording() {
    screenRecordingGranted = CGRequestScreenCaptureAccess()
  }

  func openAccessibilitySettings() {
    openSystemSettings(
      "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )
  }

  func openScreenRecordingSettings() {
    openSystemSettings(
      "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )
  }

  private func openSystemSettings(_ address: String) {
    guard let url = URL(string: address) else { return }
    NSWorkspace.shared.open(url)
  }
}
