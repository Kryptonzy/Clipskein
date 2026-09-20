import SwiftUI

enum TextActionPickerOptionKind: Equatable {
  case immediate(String)
  case intelligence(LocalIntelligenceAction, customInstruction: String?)
  case translation(LocalTranslationTarget)
}

struct TextActionPickerOption: Identifiable, Equatable {
  let id: String
  let label: String
  let systemImage: String
  let preview: String
  let kind: TextActionPickerOptionKind
}

enum TextActionPickerOptionBuilder {
  static func options(
    for item: ClipItem,
    intelligenceAvailable: Bool,
    translationAvailable: Bool,
    savedInstructions: [SavedLocalInstruction],
    quickActions providedQuickActions: [QuickPasteAction]? = nil
  ) -> [TextActionPickerOption] {
    var quickActions = providedQuickActions ?? QuickPasteActionBuilder.actions(for: item)
    if item.kind == .text {
      quickActions.removeAll { $0.kind == .plainText }
      quickActions.insert(
        QuickPasteAction(
          kind: .plainText,
          label: L10n.text("text_actions.original", fallback: "Original text"),
          systemImage: "text.alignleft",
          text: item.text
        ),
        at: 0
      )
    }
    var options = quickActions.map {
      TextActionPickerOption(
        id: "quick:\($0.id)",
        label: $0.label,
        systemImage: $0.systemImage,
        preview: $0.text,
        kind: .immediate($0.text)
      )
    }

    let input = sourceText(for: item)
    if intelligenceAvailable {
      let privatePreview = L10n.text(
        "text_actions.ai_private", fallback: "Apple Intelligence · private on this Mac")
      let builtIns: [LocalIntelligenceAction] =
        input.count >= 120 ? [.summarize, .concise, .professional] : [.concise, .professional]
      options.append(
        contentsOf: builtIns.map { action in
          TextActionPickerOption(
            id: "intelligence:\(action.rawValue)",
            label: action.label,
            systemImage: action.systemImage,
            preview: privatePreview,
            kind: .intelligence(action, customInstruction: nil)
          )
        })
      options.append(
        contentsOf: savedInstructions.map { saved in
          TextActionPickerOption(
            id: "instruction:\(saved.id.uuidString)",
            label: saved.name,
            systemImage: "wand.and.sparkles",
            preview: saved.prompt,
            kind: .intelligence(.custom, customInstruction: saved.prompt)
          )
        })
    }
    if translationAvailable && input.count <= LocalTranslationController.maximumInputLength {
      let preview = L10n.text(
        "text_actions.translation_private", fallback: "macOS language packs · on this Mac")
      options.append(
        contentsOf: LocalTranslationTarget.common.map { target in
          TextActionPickerOption(
            id: "translation:\(target.id)",
            label: L10n.format(
              "text_actions.translate_to", fallback: "Translate to %@", target.displayName),
            systemImage: "character.bubble",
            preview: preview,
            kind: .translation(target)
          )
        })
    }
    return options
  }

  private static func sourceText(for item: ClipItem) -> String {
    item.kind == .image ? item.ocrText : item.text
  }

  static func filtered(
    _ options: [TextActionPickerOption],
    query: String
  ) -> [TextActionPickerOption] {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return options }
    return options.filter {
      $0.label.localizedStandardContains(query)
        || $0.preview.localizedStandardContains(query)
    }
  }
}

struct TextActionPickerView: View {
  @ObservedObject var store: ClipStore
  let pasteCoordinator: QuickPasteCoordinator
  let captureResult: SelectedTextCaptureResult
  @StateObject private var localIntelligence = LocalIntelligenceController()
  @StateObject private var localTranslation = LocalTranslationController()
  @State private var selectedSourceID: UUID?
  @State private var selectedActionID: String?
  @State private var actionQuery = ""
  @State private var feedback: String?
  @State private var retryPasteAvailable = false
  @State private var pendingAsyncItemID: UUID?
  @FocusState private var actionSearchFocused: Bool

  private var capturedItem: ClipItem? {
    if case .captured(let selectedItem) = captureResult { return selectedItem }
    return nil
  }

  private var sourceItems: [ClipItem] {
    var result: [ClipItem] = []
    if let capturedItem { result.append(capturedItem) }
    result.append(contentsOf: store.items.filter(Self.supportsActions).prefix(8))
    return result
  }

  private var item: ClipItem? {
    sourceItems.first { $0.id == selectedSourceID } ?? sourceItems.first
  }

  private var isSelectedCapture: Bool {
    guard let capturedItem, let item else { return false }
    return capturedItem.id == item.id
  }

  private var allActions: [TextActionPickerOption] {
    guard let item else { return [] }
    return TextActionPickerOptionBuilder.options(
      for: item,
      intelligenceAvailable: localIntelligence.availability.isAvailable,
      translationAvailable: localTranslation.isAvailable,
      savedInstructions: store.preferences.savedLocalInstructions,
      quickActions: store.quickPasteActions(for: item)
    )
  }

  private var actions: [TextActionPickerOption] {
    TextActionPickerOptionBuilder.filtered(allActions, query: actionQuery)
  }

  private var selectedAction: TextActionPickerOption? {
    actions.first { $0.id == selectedActionID } ?? actions.first
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider().overlay(Color.white.opacity(0.09))
      if let item {
        sourcePreview(item)
        Divider().overlay(Color.white.opacity(0.09))
        if isAsyncIdle {
          actionSearch
          if store.isPreparingQuickPasteActions(for: item) {
            HStack(spacing: 8) {
              ProgressView().controlSize(.small)
              Text(
                L10n.text(
                  "quick_paste.preparing_actions",
                  fallback: "Preparing local actions…"
                )
              )
              .font(.system(size: 10, weight: .semibold))
              Spacer()
            }
            .foregroundStyle(Color.white.opacity(0.58))
            .padding(.horizontal, 18)
            .frame(height: 28)
            .background(Color.white.opacity(0.025))
          }
        }
        asyncWorkArea ?? AnyView(actionList)
      } else {
        emptyState
      }
      Divider().overlay(Color.white.opacity(0.09))
      footer
      if let feedback {
        Text(feedback)
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(BrandTheme.accentOnDark)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 18)
          .frame(height: 32)
      }

      Button(L10n.text("text_actions.use", fallback: "Use action")) {
        useSelected(copyOnly: false)
      }
      .keyboardShortcut(.return, modifiers: [])
      .opacity(0)
      .frame(width: 0, height: 0)
      Button(L10n.text("text_actions.copy_result", fallback: "Copy action result")) {
        useSelected(copyOnly: true)
      }
      .keyboardShortcut(.return, modifiers: [.command])
      .opacity(0)
      .frame(width: 0, height: 0)
      Button(L10n.text("text_actions.dismiss", fallback: "Dismiss Text Actions")) {
        NotificationCenter.default.post(name: .dismissQuickPicker, object: nil)
      }
      .keyboardShortcut(.cancelAction)
      .opacity(0)
      .frame(width: 0, height: 0)
    }
    .foregroundStyle(.white)
    .tint(BrandTheme.softPlum)
    .accentColor(BrandTheme.softPlum)
    .environment(\.colorScheme, .dark)
    .background(
      RoundedRectangle(cornerRadius: 18)
        .fill(BrandTheme.popoverBackground)
        .overlay(
          RoundedRectangle(cornerRadius: 18)
            .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    )
    .clipShape(RoundedRectangle(cornerRadius: 18))
    .onAppear {
      selectedSourceID = sourceItems.first?.id
      selectedActionID = actions.first?.id
      actionSearchFocused = true
    }
    .onMoveCommand(perform: moveSelection)
    .onReceive(NotificationCenter.default.publisher(for: .cycleTextActionSource)) {
      notification in
      guard let direction = notification.object as? Int else { return }
      cycleSource(direction: direction)
    }
    .onReceive(NotificationCenter.default.publisher(for: .moveQuickPanelSelection)) {
      notification in
      guard let direction = notification.object as? Int else { return }
      moveSelection(direction > 0 ? .down : .up)
    }
    .onReceive(NotificationCenter.default.publisher(for: .pasteBackFailed)) { notification in
      let failure = notification.object as? PasteBackFailure
      retryPasteAvailable = failure?.reason == .destinationUnavailable
      if failure?.reason == .clipboardChanged {
        feedback = L10n.text(
          "text_actions.clipboard_changed",
          fallback:
            "Clipboard changed before paste. Press Return to prepare this action again."
        )
      } else if let targetName = failure?.targetName, !targetName.isEmpty {
        feedback = L10n.format(
          "text_actions.paste_back_failed_target",
          fallback:
            "Copied, but %@ was not ready. Press Return to retry, or switch there and press Command–V.",
          targetName
        )
      } else {
        feedback = L10n.text(
          "text_actions.paste_back_failed",
          fallback:
            "Copied, but the destination was not ready. Press Return to retry, or paste manually."
        )
      }
    }
    .onExitCommand {
      NotificationCenter.default.post(name: .dismissQuickPicker, object: nil)
    }
    .onChange(of: selectedActionID) { _, _ in
      retryPasteAvailable = false
    }
    .onChange(of: selectedSourceID) { _, _ in
      retryPasteAvailable = false
    }
    .onChange(of: actionQuery) { _, _ in
      selectedActionID = actions.first?.id
      retryPasteAvailable = false
    }
    .onChange(of: localIntelligence.state) { _, state in
      handleIntelligenceState(state)
    }
    .onChange(of: localTranslation.state) { _, state in
      handleTranslationState(state)
    }
    .onDisappear {
      localIntelligence.cancel()
      localTranslation.cancel()
    }
    .onReceive(NotificationCenter.default.publisher(for: .privacySessionDidSuspend)) { _ in
      localIntelligence.cancel()
      localTranslation.cancel()
      pendingAsyncItemID = nil
      feedback = nil
      retryPasteAvailable = false
    }
    .localTranslationTask(controller: localTranslation)
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: "wand.and.sparkles")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(BrandTheme.accentOnDark)
      VStack(alignment: .leading, spacing: 2) {
        Text(L10n.text("text_actions.title", fallback: "TEXT ACTIONS"))
          .font(.system(size: 10, weight: .black, design: .monospaced))
        Text(headerSubtitle)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.secondary)
      }
      Spacer()
      Text("ESC")
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
    }
    .padding(.horizontal, 18)
    .frame(height: 58)
  }

  private func sourcePreview(_ item: ClipItem) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: item.kind == .image ? "text.viewfinder" : "quote.opening")
        .foregroundStyle(Color.white.opacity(0.48))
      VStack(alignment: .leading, spacing: 3) {
        Text(sourceLabel(for: item))
          .font(.system(size: 9, weight: .black, design: .monospaced))
          .foregroundStyle(Color.white.opacity(0.45))
        Text(Self.sourceText(for: item))
          .font(.system(size: 12, weight: .medium))
          .lineLimit(2)
          .foregroundStyle(Color.white.opacity(0.78))
      }
      Spacer(minLength: 0)
      if sourceItems.count > 1 {
        Button {
          cycleSource()
        } label: {
          Label(sourcePositionLabel, systemImage: "arrow.triangle.2.circlepath")
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 8)
            .frame(height: 25)
            .background(Color.white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(
          L10n.text(
            "text_actions.source_next_help",
            fallback: "Switch to the next recent text or OCR source"))
      }
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.white.opacity(0.025))
  }

  private var actionSearch: some View {
    HStack(spacing: 9) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(Color.white.opacity(0.42))
      TextField(
        L10n.text(
          "text_actions.search_placeholder", fallback: "Find an action or language"),
        text: $actionQuery
      )
      .textFieldStyle(.plain)
      .focused($actionSearchFocused)
      if !actionQuery.isEmpty {
        Button {
          actionQuery = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(Color.white.opacity(0.42))
        }
        .buttonStyle(.plain)
        .help(L10n.text("text_actions.clear_search", fallback: "Clear action search"))
      }
    }
    .padding(.horizontal, 14)
    .frame(height: 38)
    .background(Color.white.opacity(0.035))
  }

  @ViewBuilder
  private var actionList: some View {
    if actions.isEmpty {
      VStack(spacing: 8) {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 24, weight: .light))
          .foregroundStyle(Color.white.opacity(0.45))
        Text(L10n.text("text_actions.no_match", fallback: "No matching action"))
          .font(.system(size: 13, weight: .bold))
        Button(L10n.text("text_actions.clear_search", fallback: "Clear action search")) {
          actionQuery = ""
        }
        .buttonStyle(.plain)
        .foregroundStyle(BrandTheme.accentOnDark)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      List(actions, selection: $selectedActionID) { action in
        HStack(spacing: 12) {
          Image(systemName: action.systemImage)
            .frame(width: 22)
            .foregroundStyle(
              selectedActionID == action.id
                ? BrandTheme.selectedAccent : Color.white.opacity(0.70)
            )
          VStack(alignment: .leading, spacing: 2) {
            Text(action.label)
              .font(.system(size: 13, weight: .semibold))
            Text(action.preview)
              .font(.system(size: 10, weight: .regular, design: .monospaced))
              .foregroundStyle(
                selectedActionID == action.id
                  ? BrandTheme.selectedText.opacity(0.76) : Color.white.opacity(0.70)
              )
              .lineLimit(1)
          }
          Spacer(minLength: 0)
          if selectedActionID == action.id {
            if isAsyncRunning {
              ProgressView().controlSize(.small)
            } else {
              Image(systemName: "return")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(BrandTheme.selectedText.opacity(0.76))
            }
          }
        }
        .padding(.vertical, 4)
        .foregroundStyle(selectedActionID == action.id ? BrandTheme.selectedText : Color.white)
        .background(selectedActionID == action.id ? BrandTheme.softPlum : Color.clear)
        .contentShape(Rectangle())
        .tag(action.id)
        .onTapGesture(count: 2) {
          retryPasteAvailable = false
          selectedActionID = action.id
          useSelected(copyOnly: false)
        }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .disabled(isAsyncRunning)
    }
  }

  private var asyncWorkArea: AnyView? {
    intelligenceWorkArea ?? translationWorkArea
  }

  private var intelligenceWorkArea: AnyView? {
    switch localIntelligence.state {
    case .idle, .failed:
      return nil
    case .generating(let action):
      return AnyView(
        VStack(spacing: 14) {
          ProgressView()
            .controlSize(.regular)
          Text(
            L10n.format(
              "text_actions.ai_running", fallback: "%@ is running privately on this Mac…",
              action.label)
          )
          .font(.system(size: 13, weight: .semibold))
          .multilineTextAlignment(.center)
          Button(L10n.text("text_actions.ai_cancel", fallback: "Cancel")) {
            pendingAsyncItemID = nil
            feedback = nil
            localIntelligence.cancel()
          }
          .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
      )
    case .result(let action, let result):
      return resultPreview(
        label: action.label,
        result: result,
        onBack: {
          pendingAsyncItemID = nil
          localIntelligence.reset()
        }
      )
    }
  }

  private var translationWorkArea: AnyView? {
    switch localTranslation.state {
    case .idle, .failed:
      return nil
    case .checking(let target):
      return translationProgressView(
        title: L10n.text(
          "text_actions.translation_detecting", fallback: "Detecting source language…"),
        detail: target.displayName
      )
    case .preparing(let target):
      return translationProgressView(
        title: L10n.format(
          "text_actions.translation_preparing", fallback: "Preparing %@…", target.name),
        detail: L10n.text(
          "text_actions.translation_download", fallback: "Approve a language download if asked.")
      )
    case .translating(let target):
      return translationProgressView(
        title: L10n.format(
          "text_actions.translation_running", fallback: "Translating to %@…", target.name),
        detail: L10n.text(
          "text_actions.translation_local", fallback: "Translation stays on this Mac.")
      )
    case .result(let target, let result):
      return resultPreview(
        label: target.displayName,
        result: result,
        onBack: {
          pendingAsyncItemID = nil
          localTranslation.reset()
        }
      )
    }
  }

  private func translationProgressView(title: String, detail: String) -> AnyView {
    AnyView(
      VStack(spacing: 10) {
        ProgressView().controlSize(.regular)
        Text(title)
          .font(.system(size: 13, weight: .semibold))
        Text(detail)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
        Button(L10n.text("text_actions.ai_cancel", fallback: "Cancel")) {
          pendingAsyncItemID = nil
          feedback = nil
          localTranslation.cancel()
        }
        .buttonStyle(.bordered)
      }
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(24)
    )
  }

  private func resultPreview(
    label: String,
    result: String,
    onBack: @escaping () -> Void
  ) -> AnyView {
    AnyView(
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Label(label, systemImage: "checkmark.circle.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.green)
          Spacer()
          Button(L10n.text("text_actions.ai_back", fallback: "Back"), action: onBack)
            .buttonStyle(.plain)
        }
        ScrollView {
          Text(result)
            .font(.system(size: 12, design: .rounded))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        resultCommitButtons
      }
      .padding(16)
    )
  }

  private var resultCommitButtons: some View {
    HStack {
      Button {
        commitAsyncResult(copyOnly: pasteCoordinator.targetApplicationName == nil)
      } label: {
        Label(
          pasteCoordinator.targetApplicationName.map {
            L10n.format("text_actions.ai_paste_to", fallback: "Paste into %@", $0)
          }
            ?? L10n.text("text_actions.ai_copy", fallback: "Copy result"),
          systemImage: pasteCoordinator.targetApplicationName == nil
            ? "doc.on.doc" : "arrow.turn.down.right"
        )
      }
      .buttonStyle(.borderedProminent)
      if pasteCoordinator.targetApplicationName != nil {
        Button {
          commitAsyncResult(copyOnly: true)
        } label: {
          Label(
            L10n.text("text_actions.ai_copy", fallback: "Copy result"),
            systemImage: "doc.on.doc")
        }
        .buttonStyle(.bordered)
      }
    }
  }

  private var emptyState: some View {
    VStack(spacing: 9) {
      Image(systemName: "text.badge.xmark")
        .font(.system(size: 30, weight: .light))
      Text(L10n.text("text_actions.empty_title", fallback: "No recent text to transform"))
        .font(.system(size: 14, weight: .bold))
      Text(
        L10n.text(
          "text_actions.empty_detail",
          fallback: "Copy text or capture a screenshot with OCR, then press the shortcut again."
        )
      )
      .font(.system(size: 11))
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, 40)
  }

  private var footer: some View {
    HStack {
      Text(L10n.text("text_actions.shortcut_select", fallback: "↑↓ select"))
      if let targetName = pasteCoordinator.targetApplicationName {
        Text("↩ \(targetName)").lineLimit(1)
      } else {
        Text(L10n.text("text_actions.shortcut_copy", fallback: "↩ copy"))
      }
      Text(L10n.text("text_actions.shortcut_copy_only", fallback: "⌘↩ copy only"))
      if sourceItems.count > 1 {
        Text(L10n.text("text_actions.shortcut_source", fallback: "⇥ source"))
      }
      Spacer()
      Text(
        isSelectedCapture
          ? L10n.text("text_actions.selected_local", fallback: "SELECTED · ON DEVICE")
          : L10n.text("text_actions.recent_local", fallback: "RECENT · ON DEVICE")
      )
      .fontWeight(.black)
      .foregroundStyle(Color.green.opacity(0.8))
    }
    .font(.system(size: 10, weight: .semibold, design: .monospaced))
    .foregroundStyle(.secondary)
    .padding(.horizontal, 18)
    .frame(height: 36)
  }

  private func useSelected(copyOnly: Bool) {
    if hasAsyncResult {
      commitAsyncResult(copyOnly: copyOnly)
      return
    }
    if !copyOnly, retryPasteAvailable {
      retryPasteAvailable = false
      switch pasteCoordinator.retryPasteDelivery() {
      case .pasteRequested:
        NotificationCenter.default.post(name: .dismissQuickPicker, object: nil)
      case .copiedOnly:
        feedback = L10n.text(
          "text_actions.copied_only",
          fallback: "Copied. Switch to a destination app and press Command–V."
        )
      case .permissionRequired:
        feedback = L10n.text(
          "text_actions.permission",
          fallback: "Copied. Allow Accessibility to paste back automatically."
        )
      case .copyFailed, .clipboardChanged:
        feedback = L10n.text(
          "text_actions.clipboard_changed",
          fallback:
            "Clipboard changed before paste. Press Return to prepare this action again."
        )
      }
      return
    }
    guard !isAsyncRunning, let item, let action = selectedAction else { return }
    switch action.kind {
    case .immediate(let text):
      deliver(text: text, from: item, copyOnly: copyOnly)
    case .intelligence(let intelligenceAction, let customInstruction):
      pendingAsyncItemID = item.id
      feedback = nil
      localIntelligence.generate(
        action: intelligenceAction,
        input: Self.sourceText(for: item),
        customInstruction: customInstruction
      )
    case .translation(let target):
      pendingAsyncItemID = item.id
      feedback = nil
      localTranslation.request(text: Self.sourceText(for: item), target: target)
    }
  }

  private func deliver(text: String, from item: ClipItem, copyOnly: Bool) {
    if copyOnly {
      if store.copyText(text, recording: item) {
        NotificationCenter.default.post(name: .dismissQuickPicker, object: nil)
      } else {
        feedback = L10n.text(
          "text_actions.copy_failed", fallback: "Could not copy the transformed text. Try again.")
      }
      return
    }
    switch pasteCoordinator.paste(text: text, from: item, using: store) {
    case .pasteRequested:
      NotificationCenter.default.post(name: .dismissQuickPicker, object: nil)
    case .copiedOnly:
      feedback = L10n.text(
        "text_actions.copied_only",
        fallback: "Copied. Switch to a destination app and press Command–V."
      )
    case .permissionRequired:
      feedback = L10n.text(
        "text_actions.permission",
        fallback: "Copied. Allow Accessibility to paste back automatically."
      )
    case .copyFailed:
      feedback = L10n.text(
        "text_actions.prepare_failed",
        fallback: "Could not prepare the transformed text. The original is unchanged."
      )
    case .clipboardChanged:
      feedback = L10n.text(
        "text_actions.clipboard_changed",
        fallback: "Clipboard changed before paste. Press Return to prepare this action again."
      )
    }
  }

  private func handleIntelligenceState(_ state: LocalIntelligenceController.State) {
    switch state {
    case .idle, .generating, .result:
      break
    case .failed(let message):
      pendingAsyncItemID = nil
      feedback = message
      localIntelligence.reset()
    }
  }

  private func handleTranslationState(_ state: LocalTranslationController.State) {
    switch state {
    case .idle, .checking, .preparing, .translating, .result:
      break
    case .failed(let message):
      pendingAsyncItemID = nil
      feedback = message
      localTranslation.reset()
    }
  }

  private func commitAsyncResult(copyOnly: Bool) {
    let result: String?
    if case .result(_, let intelligenceResult) = localIntelligence.state {
      result = intelligenceResult
    } else if case .result(_, let translationResult) = localTranslation.state {
      result = translationResult
    } else {
      result = nil
    }
    guard let result, let itemID = pendingAsyncItemID,
      let source = sourceItems.first(where: { $0.id == itemID })
    else { return }
    pendingAsyncItemID = nil
    localIntelligence.reset()
    localTranslation.reset()
    deliver(text: result, from: source, copyOnly: copyOnly)
  }

  private var hasAsyncResult: Bool {
    if case .result = localIntelligence.state { return true }
    if case .result = localTranslation.state { return true }
    return false
  }

  private var isAsyncRunning: Bool {
    if case .generating = localIntelligence.state { return true }
    switch localTranslation.state {
    case .checking, .preparing, .translating: return true
    case .idle, .result, .failed: return false
    }
  }

  private var isAsyncIdle: Bool {
    localIntelligence.state == .idle && localTranslation.state == .idle
  }

  private func moveSelection(_ direction: MoveCommandDirection) {
    guard !isAsyncRunning, !hasAsyncResult, !actions.isEmpty else { return }
    let current = actions.firstIndex { $0.id == selectedActionID } ?? 0
    let next: Int
    switch direction {
    case .down: next = min(current + 1, actions.count - 1)
    case .up: next = max(current - 1, 0)
    default: return
    }
    selectedActionID = actions[next].id
  }

  private static func supportsActions(_ item: ClipItem) -> Bool {
    guard !item.isConcealed else { return false }
    if item.kind == .text { return !item.text.isEmpty }
    return item.kind == .image && item.ocrState == .complete
      && !item.ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private static func sourceText(for item: ClipItem) -> String {
    item.kind == .image ? item.ocrText : item.text
  }

  private var headerSubtitle: String {
    switch captureResult {
    case .captured:
      L10n.text("text_actions.subtitle_selected", fallback: "Transform the current selection")
    case .permissionRequired:
      L10n.text(
        "text_actions.subtitle_permission",
        fallback: "Recent text · allow Accessibility for selection capture")
    case .protectedApplication:
      L10n.text(
        "text_actions.subtitle_protected",
        fallback: "Recent text · selection capture is blocked for this app")
    case .clipboardPreservationUnavailable:
      L10n.text(
        "text_actions.subtitle_clipboard_preservation",
        fallback: "Recent text · clipboard was left unchanged")
    case .selectionTooLarge:
      L10n.text(
        "text_actions.subtitle_selection_too_large",
        fallback: "Recent text · selection is too large for Text Actions")
    case .noSelection:
      L10n.text(
        "text_actions.subtitle_no_selection",
        fallback: "Recent text · no selection was detected")
    }
  }

  private func sourceLabel(for item: ClipItem) -> String {
    if isSelectedCapture {
      return L10n.format(
        "text_actions.source_selected",
        fallback: "SELECTED TEXT · %@",
        item.sourceApplication.uppercased())
    }
    return item.kind == .image
      ? L10n.text("text_actions.source_ocr", fallback: "RECENT OCR")
      : L10n.text("text_actions.source_text", fallback: "RECENT TEXT")
  }

  private var sourcePositionLabel: String {
    guard let item, let index = sourceItems.firstIndex(where: { $0.id == item.id }) else {
      return L10n.text("text_actions.source", fallback: "SOURCE")
    }
    return L10n.format(
      "text_actions.source_position",
      fallback: "SOURCE %d/%d",
      index + 1,
      sourceItems.count)
  }

  private func cycleSource(direction: Int = 1) {
    guard localIntelligence.state == .idle, localTranslation.state == .idle,
      sourceItems.count > 1
    else { return }
    let current = sourceItems.firstIndex { $0.id == item?.id } ?? 0
    let nextIndex = (current + direction + sourceItems.count) % sourceItems.count
    let next = sourceItems[nextIndex]
    selectedSourceID = next.id
    selectedActionID = actions.first?.id
    feedback = nil
  }
}
