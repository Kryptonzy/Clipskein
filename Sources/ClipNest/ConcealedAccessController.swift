import Combine
import Foundation
import LocalAuthentication

enum ConcealedAuthenticationResult: Equatable, Sendable {
  case authorized
  case denied(String)
}

@MainActor
final class ConcealedAccessController: ObservableObject {
  typealias Evaluator = (String) async -> ConcealedAuthenticationResult

  @Published private(set) var isAuthenticating = false
  @Published private(set) var errorMessage: String?
  @Published private(set) var authorizedUntil: Date?

  private let authorizationDuration: TimeInterval
  private let now: () -> Date
  private let evaluator: Evaluator

  init(
    authorizationDuration: TimeInterval = 5 * 60,
    now: @escaping () -> Date = Date.init,
    evaluator: @escaping Evaluator = ConcealedAccessController.systemEvaluator
  ) {
    self.authorizationDuration = authorizationDuration
    self.now = now
    self.evaluator = evaluator
  }

  var isAuthorized: Bool {
    authorizedUntil.map { $0 > now() } ?? false
  }

  @discardableResult
  func authorize(reason: String) async -> Bool {
    if isAuthorized {
      errorMessage = nil
      return true
    }
    guard !isAuthenticating else { return false }
    isAuthenticating = true
    errorMessage = nil
    defer { isAuthenticating = false }

    switch await evaluator(reason) {
    case .authorized:
      authorizedUntil = now().addingTimeInterval(authorizationDuration)
      return true
    case .denied(let message):
      authorizedUntil = nil
      errorMessage = message
      return false
    }
  }

  func lock() {
    authorizedUntil = nil
    errorMessage = nil
  }

  private static func systemEvaluator(reason: String) async -> ConcealedAuthenticationResult {
    let context = LAContext()
    context.localizedCancelTitle = L10n.text(
      "authentication.keep_hidden", fallback: "Keep Hidden")
    var evaluationError: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evaluationError) else {
      return .denied(
        L10n.text(
          "authentication.unavailable",
          fallback: "Authentication is unavailable. Check this Mac’s password or Touch ID settings."
        )
      )
    }
    do {
      return try await context.evaluatePolicy(
        .deviceOwnerAuthentication,
        localizedReason: reason
      )
        ? .authorized
        : .denied(
          L10n.text(
            "authentication.not_completed", fallback: "Authentication was not completed."))
    } catch let error as LAError {
      switch error.code {
      case .userCancel, .appCancel, .systemCancel:
        return .denied(
          L10n.text(
            "authentication.cancelled",
            fallback: "Authentication was cancelled. The clip remains hidden."
          ))
      case .biometryLockout:
        return .denied(
          L10n.text(
            "authentication.biometry_locked",
            fallback: "Touch ID is locked. Use this Mac’s password to continue."
          ))
      default:
        return .denied(
          L10n.text(
            "authentication.failed",
            fallback: "Authentication failed. The clip remains hidden."
          ))
      }
    } catch {
      return .denied(
        L10n.text(
          "authentication.failed",
          fallback: "Authentication failed. The clip remains hidden."
        ))
    }
  }
}
