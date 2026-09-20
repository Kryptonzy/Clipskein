import Combine
import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginController: ObservableObject {
  enum State: Equatable {
    case off
    case on
    case requiresApproval
    case unavailable
  }

  @Published private(set) var state: State = .off
  @Published private(set) var errorMessage: String?

  private let service: SMAppService

  init(service: SMAppService = .mainApp) {
    self.service = service
    refresh()
  }

  var isRequested: Bool {
    state == .on || state == .requiresApproval
  }

  var statusText: String {
    switch state {
    case .off: "Off"
    case .on: "On"
    case .requiresApproval: "Approval required"
    case .unavailable: "Available after installing Clipskein.app"
    }
  }

  func setEnabled(_ enabled: Bool) {
    errorMessage = nil
    do {
      if enabled {
        guard service.status != .enabled else {
          refresh()
          return
        }
        if service.status == .requiresApproval {
          refresh()
          return
        }
        try service.register()
      } else if service.status != .notRegistered {
        try service.unregister()
      }
      refresh()
    } catch {
      errorMessage = friendlyMessage(for: error)
      refresh(keepingError: true)
    }
  }

  func refresh(keepingError: Bool = false) {
    if !keepingError { errorMessage = nil }
    state = Self.state(for: service.status)
  }

  static func state(for status: SMAppService.Status) -> State {
    switch status {
    case .notRegistered: .off
    case .enabled: .on
    case .requiresApproval: .requiresApproval
    case .notFound: .unavailable
    @unknown default: .unavailable
    }
  }

  func openSystemSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }

  private func friendlyMessage(for error: Error) -> String {
    L10n.format(
      "settings.login.error",
      fallback: "macOS could not update Login Items: %@",
      error.localizedDescription
    )
  }
}
