import Combine
import Foundation

#if canImport(Translation)
  import Translation
#endif

struct LocalTranslationTarget: Identifiable, Hashable, Sendable {
  let id: String
  let name: String
  let nativeName: String

  var displayName: String {
    name == nativeName ? name : "\(name) · \(nativeName)"
  }

  static let common: [LocalTranslationTarget] = [
    .init(id: "en", name: "English", nativeName: "English"),
    .init(id: "zh-Hans", name: "Chinese (Simplified)", nativeName: "简体中文"),
    .init(id: "zh-Hant", name: "Chinese (Traditional)", nativeName: "繁體中文"),
    .init(id: "ja", name: "Japanese", nativeName: "日本語"),
    .init(id: "ko", name: "Korean", nativeName: "한국어"),
    .init(id: "es", name: "Spanish", nativeName: "Español"),
    .init(id: "fr", name: "French", nativeName: "Français"),
    .init(id: "de", name: "German", nativeName: "Deutsch"),
    .init(id: "it", name: "Italian", nativeName: "Italiano"),
    .init(id: "pt-BR", name: "Portuguese (Brazil)", nativeName: "Português"),
  ]

  static var defaultTarget: LocalTranslationTarget {
    let preferred = Locale.preferredLanguages.first?.localizedLowercase ?? ""
    if preferred.hasPrefix("zh") {
      return common.first { $0.id == "en" } ?? common[0]
    }
    return common.first { $0.id == "zh-Hans" } ?? common[0]
  }
}

struct LocalTranslationRequest: Identifiable, Equatable, Sendable {
  let id: UUID
  let text: String
  let target: LocalTranslationTarget
}

enum LocalTranslationError: LocalizedError, Equatable {
  case unavailable
  case emptyInput
  case inputTooLong
  case unsupportedLanguage
  case unableToIdentifyLanguage
  case languageDownloadDeclined
  case emptyResponse
  case translationFailed

  var errorDescription: String? {
    switch self {
    case .unavailable:
      L10n.text(
        "translation.error.unavailable", fallback: "Local translation requires macOS 15 or later."
      )
    case .emptyInput:
      L10n.text("translation.error.empty", fallback: "There is no text to translate.")
    case .inputTooLong:
      L10n.text(
        "translation.error.too_long",
        fallback: "This clip is too long for a reliable local translation."
      )
    case .unsupportedLanguage:
      L10n.text(
        "translation.error.unsupported", fallback: "macOS does not support this language pair."
      )
    case .unableToIdentifyLanguage:
      L10n.text(
        "translation.error.identify", fallback: "macOS could not identify the source language."
      )
    case .languageDownloadDeclined:
      L10n.text(
        "translation.error.download", fallback: "The required language download was not completed."
      )
    case .emptyResponse:
      L10n.text(
        "translation.error.empty_response",
        fallback: "The local translator returned an empty result."
      )
    case .translationFailed:
      L10n.text(
        "translation.error.failed", fallback: "The local translator could not finish. Try again."
      )
    }
  }
}

@MainActor
final class LocalTranslationController: ObservableObject {
  enum State: Equatable {
    case idle
    case checking(LocalTranslationTarget)
    case preparing(LocalTranslationTarget)
    case translating(LocalTranslationTarget)
    case result(LocalTranslationTarget, String)
    case failed(String)
  }

  nonisolated static let maximumInputLength = 10_000

  @Published private(set) var state: State = .idle
  @Published private(set) var pendingRequest: LocalTranslationRequest?
  private var translationTaskState: AnyObject?

  var isAvailable: Bool {
    if #available(macOS 15.0, *) { return true }
    return false
  }

  func request(text: String, target: LocalTranslationTarget) {
    let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !input.isEmpty else {
      state = .failed(LocalTranslationError.emptyInput.localizedDescription)
      return
    }
    guard input.count <= Self.maximumInputLength else {
      state = .failed(LocalTranslationError.inputTooLong.localizedDescription)
      return
    }
    guard isAvailable else {
      state = .failed(LocalTranslationError.unavailable.localizedDescription)
      return
    }
    let request = LocalTranslationRequest(id: UUID(), text: input, target: target)
    state = .checking(target)
    pendingRequest = request
  }

  func cancel() {
    pendingRequest = nil
    state = .idle
  }

  func reset() {
    cancel()
  }

  #if canImport(Translation)
    @available(macOS 15.0, *)
    func taskState() -> LocalTranslationTaskState {
      if let state = translationTaskState as? LocalTranslationTaskState { return state }
      let state = LocalTranslationTaskState(requests: $pendingRequest)
      translationTaskState = state
      return state
    }

    @available(macOS 15.0, *)
    func perform(_ session: sending TranslationSession) async {
      guard let request = pendingRequest else { return }
      let requestID = request.id
      defer {
        if pendingRequest?.id == requestID {
          pendingRequest = nil
        }
      }

      do {
        let targetLanguage = Locale.Language(identifier: request.target.id)
        let status = try await LanguageAvailability().status(
          for: request.text,
          to: targetLanguage
        )
        guard pendingRequest?.id == requestID else { return }
        switch status {
        case .unsupported:
          throw LocalTranslationError.unsupportedLanguage
        case .supported:
          state = .preparing(request.target)
          try await session.prepareTranslation()
        case .installed:
          break
        @unknown default:
          throw LocalTranslationError.translationFailed
        }

        guard pendingRequest?.id == requestID else { return }
        state = .translating(request.target)
        let response = try await session.translate(request.text)
        guard pendingRequest?.id == requestID else { return }
        let result = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw LocalTranslationError.emptyResponse }
        state = .result(request.target, result)
      } catch is CancellationError {
        if pendingRequest?.id == requestID { state = .idle }
      } catch let error as LocalTranslationError {
        if pendingRequest?.id == requestID { state = .failed(error.localizedDescription) }
      } catch {
        if pendingRequest?.id == requestID {
          state = .failed(Self.userMessage(for: error))
        }
      }
    }

    @available(macOS 15.0, *)
    private static func userMessage(for error: Error) -> String {
      if TranslationError.unsupportedSourceLanguage ~= error
        || TranslationError.unsupportedTargetLanguage ~= error
        || TranslationError.unsupportedLanguagePairing ~= error
      {
        return LocalTranslationError.unsupportedLanguage.localizedDescription
      }
      if TranslationError.unableToIdentifyLanguage ~= error {
        return LocalTranslationError.unableToIdentifyLanguage.localizedDescription
      }
      if TranslationError.nothingToTranslate ~= error {
        return LocalTranslationError.emptyInput.localizedDescription
      }
      if #available(macOS 26.0, *), TranslationError.notInstalled ~= error {
        return LocalTranslationError.languageDownloadDeclined.localizedDescription
      }
      return LocalTranslationError.translationFailed.localizedDescription
    }
  #endif
}

#if canImport(Translation)
  @available(macOS 15.0, *)
  @MainActor
  final class LocalTranslationTaskState: ObservableObject {
    @Published private(set) var configuration: TranslationSession.Configuration?
    private var cancellable: AnyCancellable?

    init(requests: Published<LocalTranslationRequest?>.Publisher) {
      cancellable = requests.sink { [weak self] request in
        guard let self else { return }
        guard let request else {
          configuration = nil
          return
        }
        let target = Locale.Language(identifier: request.target.id)
        if configuration?.target == target {
          configuration?.invalidate()
        } else {
          configuration = TranslationSession.Configuration(source: nil, target: target)
        }
      }
    }
  }
#endif
