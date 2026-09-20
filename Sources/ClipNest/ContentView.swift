import AppKit
import SwiftUI

struct ContentView: View {
  @ObservedObject var store: ClipStore
  @StateObject private var localIntelligence = LocalIntelligenceController()
  @StateObject private var localTranslation = LocalTranslationController()
  @StateObject private var concealedAccess = ConcealedAccessController()
  @State private var copiedID: UUID?
  @State private var copiedExtractionID: String?
  @State private var copiedTransformationID: String?
  @State private var showingClearConfirmation = false
  @State private var showingClearStackConfirmation = false
  @State private var showingWelcome: Bool
  @State private var showingNewSnippet = false
  @State private var renamingItem: ClipItem?
  @State private var editingItem: ClipItem?
  @State private var templateItem: ClipItem?
  @State private var taggingItem: ClipItem?
  @State private var customInstructionItem: ClipItem?
  @State private var showingSaveView = false
  @State private var showingNewBoard = false
  @State private var showingResultsBoard = false
  @State private var resultBoardCandidateIDs: [UUID] = []
  @State private var editingBoard: ClipBoard?
  @State private var translationTarget = LocalTranslationTarget.defaultTarget
  @State private var revealedConcealedIDs = Set<UUID>()
  @State private var showingMarkdownSource = false
  @State private var contextReturnID: UUID?
  @State private var stackComparison: ClipTextComparison?
  @State private var structuredResultsTask: Task<Void, Never>?
  @State private var isPreparingStructuredResults = false
  @FocusState private var searchIsFocused: Bool
  @FocusState private var historyIsFocused: Bool

  private let textColor = BrandTheme.text
  private let canvas = BrandTheme.canvas
  private let actionColor = BrandTheme.action
  private let emphasisColor = BrandTheme.action

  init(store: ClipStore) {
    self.store = store
    _showingWelcome = State(initialValue: store.preferences.needsOnboarding)
  }

  var selectedItem: ClipItem? {
    store.items.first { $0.id == store.selectedID }
  }

  private var semanticCollectionCandidates: [ClipItem] {
    store.semanticCollectionCandidates(
      from: store.filteredItems,
      query: store.searchText
    )
  }

  var body: some View {
    HStack(spacing: 0) {
      rail
      timeline
      detail
    }
    .background(canvas)
    .foregroundStyle(textColor)
    .tint(actionColor)
    .onAppear {
      store.normalizeSelection()
      if let selectedItem { store.refreshFileReferenceAvailability(for: selectedItem) }
      historyIsFocused = true
    }
    .focusable()
    .focused($historyIsFocused)
    .onMoveCommand { direction in
      moveHistorySelection(direction)
    }
    .onReceive(NotificationCenter.default.publisher(for: .showWelcome)) { _ in
      showingWelcome = true
    }
    .onReceive(NotificationCenter.default.publisher(for: .showNewSnippet)) { _ in
      showingNewSnippet = true
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification))
    {
      _ in
      revealedConcealedIDs.removeAll()
      concealedAccess.lock()
      store.discardCachedImages()
    }
    .onReceive(NotificationCenter.default.publisher(for: .privacySessionDidSuspend)) { _ in
      structuredResultsTask?.cancel()
      structuredResultsTask = nil
      isPreparingStructuredResults = false
      localIntelligence.cancel()
      localTranslation.cancel()
      customInstructionItem = nil
      stackComparison = nil
      copiedExtractionID = nil
      copiedTransformationID = nil
      showingNewSnippet = false
    }
    .onDisappear {
      structuredResultsTask?.cancel()
      structuredResultsTask = nil
      isPreparingStructuredResults = false
    }
    .onChange(of: store.selectedID) { _, _ in
      localIntelligence.reset()
      localTranslation.reset()
      customInstructionItem = nil
      revealedConcealedIDs.removeAll()
      showingMarkdownSource = false
      if let selectedID = store.selectedID,
        store.filteredItems.contains(where: { $0.id == selectedID })
      {
        contextReturnID = nil
      }
      if let selectedItem { store.refreshFileReferenceAvailability(for: selectedItem) }
    }
    .onChange(of: translationTarget) { _, _ in
      localTranslation.reset()
    }
    .onChange(of: store.preferences.authenticateConcealedPreviews) { _, enabled in
      concealedAccess.lock()
      if enabled { revealedConcealedIDs.removeAll() }
    }
    .sheet(isPresented: $showingWelcome) {
      WelcomeView(store: store) {
        store.preferences.completeOnboarding()
        showingWelcome = false
      }
    }
    .sheet(isPresented: $showingNewSnippet) {
      EditClipView(
        boards: store.boards,
        protectsSecrets: store.preferences.protectSecrets,
        draft: store.pendingNewSnippetDraft ?? .empty,
        onCreate: { draft in
          let result = store.createSnippet(
            text: draft.text,
            title: draft.title,
            alias: draft.alias,
            conceal: draft.conceal,
            tags: draft.tags,
            boardID: draft.boardID,
            sourceApplication: draft.sourceApplication,
            sourceBundleIdentifier: draft.sourceBundleIdentifier,
            richTextData: draft.richTextData
          )
          if result.succeededID != nil {
            store.discardPendingNewSnippetDraft()
            showingNewSnippet = false
          }
          return result
        },
        onValidate: { store.validateNewSnippetDraft($0) },
        onDraftChange: { store.updatePendingNewSnippetDraft($0) },
        onDiscard: {
          store.discardPendingNewSnippetDraft()
          showingNewSnippet = false
        },
        onCancel: { showingNewSnippet = false }
      )
    }
    .sheet(item: $renamingItem) { item in
      RenameClipView(item: item) { title, alias in
        let error = store.updateMetadata(item, title: title, alias: alias)
        if error == nil { renamingItem = nil }
        return error
      } onCancel: {
        renamingItem = nil
      }
    }
    .sheet(item: $editingItem) { item in
      EditClipView(item: item, originalText: editableContent(for: item)) { text in
        let result = store.createEditedCopy(of: item, text: text)
        if result.succeededID != nil { editingItem = nil }
        return result
      } onCancel: {
        editingItem = nil
      }
    }
    .sheet(item: $templateItem) { item in
      TemplateFillView(
        item: item,
        template: ClipTemplate(item.text),
        actionLabel: L10n.text("template_fill.copy", fallback: "Copy Filled Template")
      ) { renderedText in
        let copied = copyText(renderedText, from: item)
        if copied {
          templateItem = nil
          showCopiedFeedback(for: item)
        }
        return copied
      } onCancel: {
        templateItem = nil
      }
    }
    .sheet(item: $taggingItem) { item in
      TagEditorView(item: item) { tags in
        store.updateTags(item, tags: tags)
        taggingItem = nil
      } onCancel: {
        taggingItem = nil
      }
    }
    .sheet(item: $customInstructionItem) { item in
      CustomInstructionView(preferences: store.preferences) { instruction in
        localIntelligence.generate(
          action: .custom,
          input: localIntelligenceInput(for: item),
          customInstruction: instruction
        )
        customInstructionItem = nil
      } onCancel: {
        customInstructionItem = nil
      }
    }
    .sheet(item: $stackComparison) { comparison in
      ClipComparisonView(comparison: comparison) {
        stackComparison = nil
      }
    }
    .sheet(isPresented: $showingSaveView) {
      SaveViewSheet(
        suggestedName: suggestedSavedViewName,
        criteriaDescription: currentViewCriteriaDescription
      ) { name in
        let saved = store.saveCurrentView(named: name)
        if saved { showingSaveView = false }
        return saved
      } onCancel: {
        showingSaveView = false
      }
    }
    .sheet(isPresented: $showingNewBoard) {
      BoardEditorView(
        title: L10n.text("board_editor.new_title", fallback: "New Pinboard")
      ) { name in
        guard store.createBoard(named: name) != nil else { return false }
        showingNewBoard = false
        return true
      } onCancel: {
        showingNewBoard = false
      }
    }
    .sheet(isPresented: $showingResultsBoard) {
      BoardEditorView(
        title: L10n.text(
          "results.pinboard.title", fallback: "New Pinboard from Results")
      ) { name in
        guard let board = store.createBoard(named: name) else { return false }
        let itemsByID = Dictionary(uniqueKeysWithValues: store.items.map { ($0.id, $0) })
        let candidates = resultBoardCandidateIDs.compactMap { itemsByID[$0] }
        saveCandidates(candidates, to: board)
        resultBoardCandidateIDs = []
        showingResultsBoard = false
        return true
      } onCancel: {
        resultBoardCandidateIDs = []
        showingResultsBoard = false
      }
    }
    .sheet(item: $editingBoard) { board in
      BoardEditorView(
        title: L10n.text("board_editor.rename_title", fallback: "Rename Pinboard"),
        initialName: board.name
      ) { name in
        guard store.renameBoard(board, to: name) else { return false }
        editingBoard = nil
        return true
      } onCancel: {
        editingBoard = nil
      }
    }
    .localTranslationTask(controller: localTranslation)
  }

  private var rail: some View {
    VStack(alignment: .leading, spacing: 22) {
      VStack(alignment: .leading, spacing: 4) {
        ClipskeinMark()
          .frame(width: 36, height: 36)
          .accessibilityHidden(true)
        Text("Clipskein")
          .font(.system(size: 18, weight: .semibold, design: .rounded))
          .tracking(0.1)
        Text(L10n.text("main.tagline", fallback: "Find. Arrange. Reuse."))
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(Color.white.opacity(0.68))
      }

      Button {
        showingNewSnippet = true
      } label: {
        Label(
          store.hasPendingNewSnippetDraft
            ? L10n.text("main.resume_snippet", fallback: "Resume Draft")
            : L10n.text("main.new_snippet", fallback: "New Snippet"),
          systemImage: store.hasPendingNewSnippetDraft
            ? "arrow.clockwise.square.fill" : "plus.square.fill"
        )
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.plain)
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .background(BrandTheme.accentOnDark, in: RoundedRectangle(cornerRadius: 7))
      .foregroundStyle(BrandTheme.deepPlum)
      .help(
        store.hasPendingNewSnippetDraft
          ? L10n.text(
            "main.resume_snippet.help",
            fallback: "Continue the encrypted snippet draft saved on this Mac"
          )
          : L10n.text(
            "main.new_snippet.help",
            fallback: "Create a pinned reusable clip without changing the clipboard"
          )
      )

      LazyVGrid(
        columns: [GridItem(.flexible()), GridItem(.flexible())],
        alignment: .leading,
        spacing: 6
      ) {
        ForEach(ClipFilter.allCases) { filter in
          filterButton(filter)
        }
      }

      VStack(alignment: .leading, spacing: 7) {
        HStack {
          Text(L10n.text("main.pinboards", fallback: "PINBOARDS"))
            .font(.system(size: 10, weight: .black, design: .monospaced))
            .tracking(1)
            .foregroundStyle(.white.opacity(0.46))
          Spacer()
          Button {
            showingNewBoard = true
          } label: {
            Image(systemName: "plus")
          }
          .buttonStyle(.plain)
          .help(L10n.text("main.pinboard.create", fallback: "Create Pinboard"))
          .accessibilityLabel(
            L10n.text("main.pinboard.create", fallback: "Create Pinboard")
          )
          .disabled(store.boards.count >= ClipBoard.maximumCount)
        }

        if store.boards.isEmpty {
          Button {
            showingNewBoard = true
          } label: {
            Label(
              L10n.text("main.pinboard.empty", fallback: "Group reusable clips"),
              systemImage: "rectangle.stack.badge.plus"
            )
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.62))
          }
          .buttonStyle(.plain)
        } else {
          ScrollView {
            VStack(spacing: 3) {
              ForEach(store.boards) { board in
                Button {
                  store.selectedBoardID = store.selectedBoardID == board.id ? nil : board.id
                } label: {
                  HStack(spacing: 7) {
                    Image(systemName: "rectangle.stack.fill")
                    Text(board.name).lineLimit(1)
                    Spacer(minLength: 2)
                    Text("\(store.itemCount(in: board))")
                      .font(.system(size: 9, weight: .bold, design: .monospaced))
                      .foregroundStyle(.white.opacity(0.45))
                  }
                  .font(
                    .system(
                      size: 11,
                      weight: store.selectedBoardID == board.id ? .bold : .medium
                    )
                  )
                  .padding(.horizontal, 7)
                  .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                  .background(
                    store.selectedBoardID == board.id ? Color.white.opacity(0.11) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7)
                  )
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                  store.selectedBoardID == board.id ? .white : .white.opacity(0.64)
                )
                .contextMenu {
                  Button(L10n.text("main.pinboard.rename", fallback: "Rename…")) {
                    editingBoard = board
                  }
                  Divider()
                  Button(
                    L10n.text("main.pinboard.delete", fallback: "Delete Pinboard"),
                    role: .destructive
                  ) { store.deleteBoard(board) }
                }
              }
            }
          }
          .frame(maxHeight: 150)
        }
      }

      Spacer()

      Button {
        store.captureRegion()
      } label: {
        Label(
          store.isCapturingRegion
            ? L10n.text("main.screen_ocr.selecting", fallback: "Select a region…")
            : (store.preferences.screenOCRHotKeyPreset == .disabled
              ? L10n.text("main.screen_ocr", fallback: "Screen OCR")
              : L10n.format(
                "main.screen_ocr.shortcut", fallback: "Screen OCR  %@",
                store.preferences.screenOCRHotKeyPreset.display)),
          systemImage: store.isCapturingRegion ? "viewfinder.circle.fill" : "viewfinder"
        )
      }
      .buttonStyle(.plain)
      .disabled(store.isCapturingRegion)
      .help(
        L10n.text(
          "main.screen_ocr.help",
          fallback: "Select a region, save the screenshot, and copy recognized text"
        )
      )

      Button {
        performImageImportAction()
      } label: {
        Label(
          imageImportActionTitle,
          systemImage: store.imageImportProgress == nil ? "photo.badge.plus" : "xmark.circle"
        )
      }
      .buttonStyle(.plain)
      .disabled(store.imageImportProgress?.isCancelling == true)

      ScreenshotImportStatusView(store: store, accentColor: BrandTheme.accentOnDark)

      Button {
        store.setScreenshotWatching(!store.preferences.watchScreenshots)
      } label: {
        HStack(spacing: 8) {
          Circle()
            .fill(store.isWatchingScreenshots ? Color.green : Color.gray)
            .frame(width: 7, height: 7)
          Text(
            store.isWatchingScreenshots
              ? L10n.text("main.screenshots.watching", fallback: "Watching screenshots")
              : L10n.text("main.screenshots.off", fallback: "Screenshot inbox off")
          )
        }
      }
      .buttonStyle(.plain)
      .font(.system(size: 12, weight: .medium))
      .help(
        L10n.text(
          "main.screenshots.help",
          fallback: "Automatically add new macOS screenshots and read their text locally"
        )
      )

      if store.pendingImageAnalysisCount > 0 {
        Label(
          store.pendingImageAnalysisCount == 1
            ? L10n.text("main.ocr.analyzing_one", fallback: "Reading 1 image locally…")
            : L10n.format(
              "main.ocr.analyzing_many",
              fallback: "Reading %d images locally…",
              store.pendingImageAnalysisCount
            ),
          systemImage: "text.viewfinder"
        )
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(BrandTheme.accentOnDark)
        .accessibilityAddTraits(.updatesFrequently)
      }

      if let issue = store.screenshotWatchIssue {
        VStack(alignment: .leading, spacing: 5) {
          Text(issue)
            .fixedSize(horizontal: false, vertical: true)
          Button {
            Task { await store.retryScreenshotWatching() }
          } label: {
            Label(
              store.isRetryingScreenshotWatch
                ? L10n.text("screenshot_watch.retrying", fallback: "Checking…")
                : L10n.text("screenshot_watch.retry", fallback: "Retry now"),
              systemImage: store.isRetryingScreenshotWatch ? "hourglass" : "arrow.clockwise"
            )
          }
          .buttonStyle(.plain)
          .fontWeight(.bold)
          .disabled(store.isRetryingScreenshotWatch)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(Color.orange)
      }

      Button {
        store.toggleMonitoring()
      } label: {
        HStack(spacing: 8) {
          Circle()
            .fill(store.isMonitoring ? Color.green : Color.orange)
            .frame(width: 7, height: 7)
          Text(
            store.isMonitoring
              ? L10n.text("main.monitoring.watching", fallback: "Watching clipboard")
              : L10n.text("main.monitoring.paused", fallback: "Monitoring paused")
          )
        }
      }
      .buttonStyle(.plain)
      .font(.system(size: 12, weight: .medium))

      Button {
        if store.isIgnoringNextCopy {
          store.cancelIgnoringNextCopy()
        } else {
          store.ignoreNextCopy()
        }
      } label: {
        Label(
          store.isIgnoringNextCopy
            ? L10n.text("main.ignore_next.cancel", fallback: "Cancel ignore next")
            : L10n.text("main.ignore_next", fallback: "Ignore next copy"),
          systemImage: store.isIgnoringNextCopy ? "eye" : "eye.slash"
        )
      }
      .buttonStyle(.plain)
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(store.isIgnoringNextCopy ? BrandTheme.accentOnDark : Color.white)

      if let notice = store.notice {
        VStack(alignment: .leading, spacing: 6) {
          Label(notice.message, systemImage: notice.systemImage)
            .fixedSize(horizontal: false, vertical: true)
          if let action = notice.action {
            Button(L10n.text("main.undo", fallback: "Undo")) {
              store.performNoticeAction(action)
            }
            .buttonStyle(.plain)
            .underline()
          }
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(BrandTheme.accentOnDark)
      }

      if let expiration = store.secureCopyExpiration {
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 6) {
            Image(systemName: "timer")
            Text(L10n.text("main.secure_copy.clears_in", fallback: "Clipboard clears in"))
            Spacer(minLength: 2)
            Text(expiration, style: .timer)
              .monospacedDigit()
          }
          Button(L10n.text("main.secure_copy.keep", fallback: "Keep on clipboard")) {
            store.keepSecureCopyOnClipboard()
          }
          .buttonStyle(.plain)
          .underline()
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(BrandTheme.accentOnDark)
      }

      SettingsLink {
        Label(
          L10n.text("main.privacy_retention", fallback: "Privacy & retention"),
          systemImage: "gearshape"
        )
      }
      .buttonStyle(.plain)
      .font(.system(size: 12, weight: .medium))

      Button(role: .destructive) {
        showingClearConfirmation = true
      } label: {
        Label(
          L10n.text("main.clear_history", fallback: "Clear unpinned history…"),
          systemImage: "trash"
        )
      }
      .buttonStyle(.plain)
      .font(.system(size: 12, weight: .medium))
      .disabled(!store.items.contains { !$0.isPinned })

      VStack(alignment: .leading, spacing: 3) {
        Text(
          store.preferences.hotKeyPreset == .disabled
            ? L10n.text("main.shortcut.picker_off", fallback: "Quick picker shortcut is off")
            : L10n.format(
              "main.shortcut.picker", fallback: "%@ opens quick picker",
              store.preferences.hotKeyPreset.display)
        )
        Text(
          store.preferences.newSnippetHotKeyPreset == .disabled
            ? L10n.text(
              "main.shortcut.new_snippet_off", fallback: "New Snippet shortcut is off")
            : L10n.format(
              "main.shortcut.new_snippet", fallback: "%@ creates a reusable snippet",
              store.preferences.newSnippetHotKeyPreset.display)
        )
        Text(
          store.preferences.snippetHotKeyPreset == .disabled
            ? L10n.text("main.shortcut.snippets_off", fallback: "Snippets shortcut is off")
            : L10n.format(
              "main.shortcut.snippets", fallback: "%@ opens @aliases",
              store.preferences.snippetHotKeyPreset.display)
        )
        Text(
          store.preferences.textActionHotKeyPreset == .disabled
            ? L10n.text(
              "main.shortcut.text_actions_off", fallback: "Text Actions shortcut is off")
            : L10n.format(
              "main.shortcut.text_actions", fallback: "%@ transforms recent text",
              store.preferences.textActionHotKeyPreset.display)
        )
      }
      .font(.system(size: 10, weight: .semibold, design: .monospaced))
      .foregroundStyle(Color.white.opacity(0.68))
    }
    .padding(24)
    .frame(width: 210)
    .background(BrandTheme.railBackground)
    .foregroundStyle(Color.white)
    .confirmationDialog(
      L10n.text("main.clear_history.confirm_title", fallback: "Clear unpinned history?"),
      isPresented: $showingClearConfirmation,
      titleVisibility: .visible
    ) {
      Button(
        L10n.text("main.clear_history.confirm", fallback: "Clear unpinned history"),
        role: .destructive
      ) { store.clearUnpinned() }
    } message: {
      Text(
        L10n.text(
          "main.clear_history.detail",
          fallback: "Pinned clips stay, and you can undo this afterward."
        )
      )
    }
  }

  private func filterButton(_ filter: ClipFilter) -> some View {
    Button {
      store.filter = filter
    } label: {
      HStack {
        Image(systemName: filter.systemImage)
          .frame(width: 14)
        Text(localizedFilterLabel(filter))
          .lineLimit(1)
      }
      .font(.system(size: 11, weight: store.filter == filter ? .bold : .medium))
      .padding(.horizontal, 7)
      .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
      .background(
        store.filter == filter ? Color.white.opacity(0.11) : Color.clear,
        in: RoundedRectangle(cornerRadius: 7)
      )
    }
    .buttonStyle(.plain)
    .foregroundStyle(store.filter == filter ? .white : .white.opacity(0.58))
  }

  private var timeline: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 14) {
        HStack(alignment: .firstTextBaseline) {
          Text(L10n.text("main.recent_memory", fallback: "RECENT MEMORY"))
            .font(.system(size: 11, weight: .black, design: .monospaced))
            .tracking(1.2)
          Spacer()
          Text(
            L10n.format(
              "main.clip_count", fallback: "%d clips", store.filteredItems.count)
          )
          .font(.system(size: 11, weight: .medium, design: .monospaced))
          .foregroundStyle(.secondary)
          if store.canSaveCurrentView, !store.filteredItems.isEmpty {
            visibleResultsCollectionMenu
          }
        }

        HStack(spacing: 8) {
          TextField(
            L10n.text(
              "main.search_placeholder",
              fallback: "Search anything — try “Safari links yesterday”"
            ),
            text: $store.searchText
          )
          .textFieldStyle(.plain)
          .font(.system(size: 14, weight: .medium))
          .padding(.leading, 14)
          .padding(.trailing, trimmedSearchText.isEmpty ? 14 : 34)
          .frame(height: 42)
          .background(BrandTheme.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 11))
          .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.primary.opacity(0.07)))
          .overlay(alignment: .trailing) {
            if !trimmedSearchText.isEmpty {
              Button {
                store.searchText = ""
              } label: {
                Image(systemName: "xmark.circle.fill")
                  .foregroundStyle(.secondary)
              }
              .buttonStyle(.plain)
              .padding(.trailing, 11)
              .help(L10n.text("main.clear_search", fallback: "Clear search"))
              .accessibilityLabel(L10n.text("main.clear_search", fallback: "Clear search"))
            }
          }
          .focused($searchIsFocused)
          .onKeyPress(.upArrow) {
            store.selectAdjacentVisibleItem(by: -1)
            return .handled
          }
          .onKeyPress(.downArrow) {
            store.selectAdjacentVisibleItem(by: 1)
            return .handled
          }

          searchFilterMenu
          savedViewsMenu
        }

        if let semanticMessage = store.currentSemanticSearchStatus.localizedMessage {
          HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(
              systemName: store.currentSemanticSearchStatus.isPreparing
                ? "brain.head.profile" : "sparkles"
            )
            Text(semanticMessage)
              .font(.system(size: 10, weight: .semibold, design: .monospaced))
              .lineLimit(2)
            Spacer(minLength: 4)
            if store.currentSemanticSearchStatus.canCollectResults,
              !semanticCollectionCandidates.isEmpty
            {
              Button {
                store.addItemsToStack(semanticCollectionCandidates)
              } label: {
                Label(
                  L10n.format(
                    "semantic.collect_count", fallback: "Collect %d",
                    semanticCollectionCandidates.count
                  ),
                  systemImage: "square.stack.3d.up"
                )
              }
              .buttonStyle(.plain)
              .font(.system(size: 10, weight: .bold))
              .help(
                L10n.text(
                  "semantic.collect.help",
                  fallback: "Add strong and related meaning matches to Stack"
                )
              )
              Menu {
                Button {
                  resultBoardCandidateIDs = semanticCollectionCandidates.map(\.id)
                  showingResultsBoard = true
                } label: {
                  Label(
                    L10n.text("semantic.pinboard.new", fallback: "New Pinboard…"),
                    systemImage: "rectangle.stack.badge.plus"
                  )
                }
                .disabled(store.boards.count >= ClipBoard.maximumCount)
                if !store.boards.isEmpty {
                  Divider()
                  Section(
                    L10n.text(
                      "semantic.pinboard.existing", fallback: "Existing Pinboards")
                  ) {
                    ForEach(store.boards) { board in
                      Button {
                        saveCandidates(semanticCollectionCandidates, to: board)
                      } label: {
                        Label(board.name, systemImage: "rectangle.stack.fill")
                      }
                    }
                  }
                }
              } label: {
                Image(systemName: "rectangle.stack.badge.plus")
              }
              .menuStyle(.borderlessButton)
              .menuIndicator(.hidden)
              .fixedSize()
              .font(.system(size: 10, weight: .bold))
              .help(
                L10n.text(
                  "semantic.save_pinboard.help",
                  fallback: "Keep these meaning matches in a named Pinboard"
                )
              )
              .accessibilityLabel(
                L10n.text(
                  "semantic.save_pinboard", fallback: "Save results as Pinboard"
                )
              )
            } else {
              Text("~")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
            }
          }
          .foregroundStyle(actionColor)
          .padding(.horizontal, 10)
          .padding(.vertical, 8)
          .background(actionColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
          .accessibilityElement(children: .contain)
        } else if let regexMessage = store.currentRegexSearchStatus.localizedMessage {
          HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(
              systemName: store.currentRegexSearchStatus.isInvalid
                ? "exclamationmark.triangle.fill" : "textformat.abc.dottedunderline"
            )
            Text(regexMessage)
              .font(.system(size: 10, weight: .semibold, design: .monospaced))
              .lineLimit(2)
            Spacer(minLength: 4)
            Text("regex:")
              .font(.system(size: 9, weight: .bold, design: .monospaced))
          }
          .foregroundStyle(store.currentRegexSearchStatus.isInvalid ? Color.orange : actionColor)
          .padding(.horizontal, 10)
          .padding(.vertical, 8)
          .background(
            (store.currentRegexSearchStatus.isInvalid ? Color.orange : actionColor).opacity(0.07),
            in: RoundedRectangle(cornerRadius: 9)
          )
          .accessibilityElement(children: .combine)
        } else if let interpretation = store.currentSearchInterpretation {
          HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: store.searchAsLiteral ? "textformat" : "sparkle.magnifyingglass")
              .foregroundStyle(store.searchAsLiteral ? Color.secondary : actionColor)
            Text(
              store.searchAsLiteral
                ? L10n.text(
                  "search.literal_status", fallback: "Searching those words literally")
                : L10n.format(
                  "search.understood",
                  fallback: "Understood: %@",
                  interpretation.localizedFacetLabels().joined(separator: " · ")
                )
            )
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(2)
            Spacer(minLength: 4)
            Button(
              store.searchAsLiteral
                ? L10n.text("search.smart", fallback: "Use smart search")
                : L10n.text("search.literal", fallback: "Search literally")
            ) {
              if store.searchAsLiteral {
                store.useNaturalLanguageSearch()
              } else {
                store.useLiteralSearch()
              }
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(actionColor)
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 8)
          .background(actionColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
          .accessibilityElement(children: .contain)
        }

        if !store.popularTags.isEmpty {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
              ForEach(store.popularTags, id: \.self) { tag in
                Button {
                  store.selectedTag = store.selectedTag == tag ? nil : tag
                } label: {
                  Label(tag, systemImage: "tag.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 9)
                    .frame(height: 25)
                    .background(
                      store.selectedTag?.localizedCaseInsensitiveCompare(tag) == .orderedSame
                        ? actionColor.opacity(0.16) : BrandTheme.surface.opacity(0.68),
                      in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .help(tagFilterActionLabel(tag))
                .accessibilityLabel(tagFilterActionLabel(tag))
              }
            }
          }
        }

        if !store.stackItems.isEmpty {
          stackBar
        }
      }
      .padding(20)

      if let issue = store.storageIssue {
        storageIssueBanner(issue)
          .padding(.horizontal, 16)
          .padding(.bottom, 14)
      }

      Divider().opacity(0.55)

      if store.filteredItems.isEmpty {
        emptyState
      } else {
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(spacing: 0) {
              ForEach(store.filteredItems) { item in
                clipRow(item)
                  .id(item.id)
              }
            }
          }
          .onChange(of: store.selectedID) { _, selectedID in
            guard let selectedID else { return }
            withAnimation(.easeOut(duration: 0.12)) {
              proxy.scrollTo(selectedID, anchor: .center)
            }
          }
        }
      }

      keyboardCommandButtons
    }
    .frame(width: 360)
    .background(BrandTheme.surface.opacity(0.46))
  }

  private func clipRow(_ item: ClipItem) -> some View {
    Button {
      store.selectedID = item.id
      historyIsFocused = true
    } label: {
      HStack(spacing: 12) {
        thumbnail(item)
          .overlay(alignment: .bottomTrailing) {
            sourceApplicationBadge(for: item, size: 18)
          }
        VStack(alignment: .leading, spacing: 6) {
          HStack {
            Text(item.localizedDisplayTitle())
              .font(.system(size: 13, weight: .semibold))
              .lineLimit(2)
              .multilineTextAlignment(.leading)
            Spacer(minLength: 4)
            if item.isPinned {
              Image(systemName: "pin.fill")
                .font(.system(size: 10))
                .foregroundStyle(emphasisColor)
            }
          }
          HStack(spacing: 6) {
            Label(
              localizedContentKindLabel(item.privacySafeContentKind),
              systemImage: item.privacySafeContentKind.systemImage
            )
            Text("·")
            Text(item.localizedSourceApplication())
            if item.hasRichText, !item.isConcealed {
              Text("·")
              Text(L10n.text("main.row.rich", fallback: "Rich"))
            }
            if let metadata = item.imageMetadata, !item.isConcealed {
              Text("·")
              Text(metadata.dimensionsText)
            }
            if let format = item.localizedImageFormat(), !item.isConcealed {
              Text("·")
              Text(format)
            }
            Text("·")
            Text(item.createdAt, style: .relative)
            if let semanticConfidence = store.semanticMatchConfidence(
              for: item,
              query: store.searchText
            ) {
              Text("·")
              Label(
                semanticConfidence.localizedLabel,
                systemImage: semanticConfidence.systemImage
              )
              .foregroundStyle(actionColor)
            }
            if let expiresAt = item.expiresAt {
              Text("·")
              Label {
                Text(expiresAt, style: .relative)
              } icon: {
                Image(systemName: "timer")
              }
              .foregroundStyle(Color.orange)
            }
          }
          .font(.system(size: 10, weight: .medium))
          .lineLimit(1)
          .foregroundStyle(.secondary)
          if item.alias != nil || !item.tags.isEmpty {
            HStack(spacing: 5) {
              if let alias = item.alias {
                Text("@\(alias)")
                  .font(.system(size: 9, weight: .bold, design: .monospaced))
                  .lineLimit(1)
                  .padding(.horizontal, 6)
                  .frame(height: 18)
                  .foregroundStyle(actionColor)
                  .background(emphasisColor.opacity(0.17), in: Capsule())
              }
              ForEach(item.tags.prefix(2), id: \.self) { tag in
                Text("#\(tag)")
                  .font(.system(size: 9, weight: .semibold))
                  .lineLimit(1)
                  .padding(.horizontal, 6)
                  .frame(height: 18)
                  .background(actionColor.opacity(0.09), in: Capsule())
              }
              if item.tags.count > 2 {
                Text("+\(item.tags.count - 2)")
                  .font(.system(size: 9, weight: .bold))
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
        clipDragSource(for: item)
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 13)
      .background(store.selectedID == item.id ? actionColor.opacity(0.09) : Color.clear)
      .overlay(alignment: .leading) {
        if store.selectedID == item.id {
          Rectangle().fill(actionColor).frame(width: 3)
        }
      }
    }
    .buttonStyle(.plain)
    .overlay(alignment: .bottom) { Divider().padding(.leading, 82).opacity(0.45) }
    .contextMenu {
      if SemanticSearchRequest.suggestedQuery(for: item) != nil {
        Button {
          store.findSimilar(to: item)
        } label: {
          Label(
            L10n.text("semantic.find_similar", fallback: "Find Similar"),
            systemImage: "brain.head.profile"
          )
        }
        Divider()
      }
      if ClipTemplate.isEligible(item) {
        Button(L10n.text("main.detail.fill_template_ellipsis", fallback: "Fill template…")) {
          beginTemplateCopy(item)
        }
        Divider()
      }
      if item.kind != .files {
        Button(
          item.kind == .image
            ? L10n.text(
              "main.detail.edit_ocr", fallback: "Edit recognized text as a copy…")
            : L10n.text("main.detail.edit_copy", fallback: "Create edited copy…")
        ) {
          editingItem = item
        }
        .disabled(
          editableContent(for: item).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !sensitiveContentIsVisible(item)
        )
        Divider()
      }
      Button(
        store.isInStack(item)
          ? L10n.text("main.stack.remove", fallback: "Remove from Stack")
          : L10n.text("main.detail.add_stack", fallback: "Add to Stack")
      ) {
        store.toggleStackMembership(item)
      }
      .disabled(!store.isInStack(item) && !store.canAddToStack(item))
      if !store.boards.isEmpty {
        Divider()
        boardMembershipMenu(for: item)
      }
      if item.sourceBundleIdentifier != nil {
        Divider()
        let isExcluded = store.preferences.isExcluded(
          bundleIdentifier: item.sourceBundleIdentifier
        )
        Button {
          store.setSourceApplicationExcluded(!isExcluded, for: item)
        } label: {
          Label(
            isExcluded
              ? L10n.format(
                "source_privacy.include",
                fallback: "Allow future copies from %@",
                item.localizedSourceApplication()
              )
              : L10n.format(
                "source_privacy.exclude",
                fallback: "Never capture future copies from %@",
                item.localizedSourceApplication()
              ),
            systemImage: isExcluded ? "checkmark.shield" : "hand.raised"
          )
        }
      }
    }
  }

  private func boardMembershipMenu(for item: ClipItem) -> some View {
    Menu(L10n.text("main.detail.pinboards", fallback: "Pinboards")) {
      ForEach(store.boards) { board in
        Button {
          store.toggleBoardMembership(board, for: item)
        } label: {
          Label(
            board.name,
            systemImage: item.boardIDs.contains(board.id) ? "checkmark" : "rectangle.stack"
          )
        }
      }
    }
  }

  @ViewBuilder
  private func thumbnail(_ item: ClipItem) -> some View {
    if item.isConcealed {
      concealedGlyph(size: 52)
    } else if item.kind == .image {
      if let image = store.cachedDecodedImage(for: item) {
        Image(nsImage: image)
          .resizable()
          .scaledToFill()
          .frame(width: 52, height: 52)
          .clipShape(RoundedRectangle(cornerRadius: 9))
      } else {
        contentGlyph(item, size: 52)
          .task(id: item.imageFileName) { store.requestDecodedImage(for: item) }
      }
    } else if item.kind == .files {
      Image(systemName: item.filePaths.count > 1 ? "doc.on.doc.fill" : "doc.fill")
        .font(.system(size: 34, weight: .medium))
        .foregroundStyle(actionColor)
        .frame(width: 42, height: 42)
    } else {
      contentGlyph(item, size: 52)
    }
  }

  @ViewBuilder
  private func sourceApplicationBadge(for item: ClipItem, size: CGFloat) -> some View {
    if let icon = store.sourceApplicationIcon(for: item) {
      Image(nsImage: icon)
        .resizable()
        .scaledToFit()
        .frame(width: size, height: size)
        .background(Color.white, in: RoundedRectangle(cornerRadius: size * 0.22))
        .overlay(
          RoundedRectangle(cornerRadius: size * 0.22)
            .stroke(Color.primary.opacity(0.14), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 1, y: 1)
        .accessibilityHidden(true)
    }
  }

  private var detail: some View {
    Group {
      if let item = selectedItem {
        detailView(item)
      } else {
        VStack(spacing: 12) {
          Image(systemName: "sparkle.magnifyingglass")
            .font(.system(size: 42, weight: .light))
          Text(L10n.text("main.detail.choose", fallback: "Choose a clip to inspect it"))
            .font(.system(size: 16, weight: .semibold))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(canvas)
  }

  private func detailView(_ item: ClipItem) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      if contextReturnID != nil,
        !store.filteredItems.contains(where: { $0.id == item.id })
      {
        contextNavigationBanner
        Divider().opacity(0.55)
      }

      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(
            item.kind == .image
              ? L10n.text("main.detail.image_ocr", fallback: "IMAGE + OCR")
              : localizedContentKindLabel(item.privacySafeContentKind).uppercased()
          )
          .font(.system(size: 10, weight: .black, design: .monospaced))
          .tracking(1.1)
          .foregroundStyle(actionColor)
          if item.customTitle != nil {
            Text(item.localizedDisplayTitle())
              .font(.system(size: 17, weight: .bold, design: .rounded))
              .lineLimit(2)
          }
          Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
          if let metadata = item.imageMetadata, sensitiveContentIsVisible(item) {
            Label(metadata.localizedSummary, systemImage: "aspectratio")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(.secondary)
          }
          if let format = item.localizedImageFormat(), sensitiveContentIsVisible(item) {
            Label(format, systemImage: "play.rectangle.on.rectangle")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(.secondary)
          }
          if let confidence = item.ocrConfidence, sensitiveContentIsVisible(item) {
            Label(
              L10n.format(
                item.hasLowConfidenceOCR
                  ? "main.detail.ocr_confidence_low"
                  : "main.detail.ocr_confidence",
                fallback: item.hasLowConfidenceOCR
                  ? "OCR confidence: low · %d%%"
                  : "OCR confidence: %d%%",
                Int((confidence * 100).rounded())
              ),
              systemImage: item.hasLowConfidenceOCR
                ? "exclamationmark.triangle.fill" : "checkmark.circle"
            )
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(item.hasLowConfidenceOCR ? Color.orange : Color.secondary)
          }
          if let alias = item.alias {
            Text("@\(alias)")
              .font(.system(size: 10, weight: .bold, design: .monospaced))
              .foregroundStyle(actionColor)
          }
          if item.hasRichText, !item.isConcealed {
            Label(
              L10n.text("main.detail.formatting_preserved", fallback: "Formatting preserved"),
              systemImage: "textformat"
            )
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
          }
          if let expiresAt = item.expiresAt {
            Label(
              L10n.format(
                "main.detail.expires", fallback: "Expires %@",
                expiresAt.formatted(date: .abbreviated, time: .shortened)),
              systemImage: "timer"
            )
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.orange)
          }
        }
        Spacer()
        clipDragSource(for: item)
        Button {
          store.togglePin(item)
        } label: {
          Image(systemName: item.isPinned ? "pin.fill" : "pin")
        }
        .help(
          item.isPinned
            ? L10n.text("main.detail.unpin", fallback: "Unpin")
            : L10n.text("main.detail.pin", fallback: "Pin")
        )
        detailActionsMenu(for: item)
      }
      .buttonStyle(.borderless)
      .padding(24)

      Divider().opacity(0.55)

      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          let itemBoards = store.boards(for: item)
          if !itemBoards.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 7) {
                ForEach(itemBoards) { board in
                  Button {
                    store.selectedBoardID = store.selectedBoardID == board.id ? nil : board.id
                  } label: {
                    Label(board.name, systemImage: "rectangle.stack.fill")
                      .font(.system(size: 11, weight: .semibold))
                      .padding(.horizontal, 10)
                      .frame(height: 28)
                      .background(emphasisColor.opacity(0.14), in: Capsule())
                  }
                  .buttonStyle(.plain)
                  .help(
                    L10n.format(
                      "main.pinboard.show", fallback: "Show %@", board.name)
                  )
                  .accessibilityLabel(
                    L10n.format(
                      "main.pinboard.show", fallback: "Show %@", board.name)
                  )
                }
              }
            }
          }

          if !item.tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 7) {
                ForEach(item.tags, id: \.self) { tag in
                  Button {
                    store.selectedTag = store.selectedTag == tag ? nil : tag
                  } label: {
                    Label(tag, systemImage: "tag.fill")
                      .font(.system(size: 11, weight: .semibold))
                      .padding(.horizontal, 10)
                      .frame(height: 28)
                      .background(actionColor.opacity(0.10), in: Capsule())
                  }
                  .buttonStyle(.plain)
                  .help(tagFilterActionLabel(tag))
                  .accessibilityLabel(tagFilterActionLabel(tag))
                }
              }
            }
          }

          if item.kind == .image, sensitiveContentIsVisible(item) {
            if let image = store.cachedDecodedImage(for: item) {
              Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 330)
                .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
            } else {
              ProgressView()
                .frame(maxWidth: .infinity, minHeight: 160)
                .task(id: item.imageFileName) { store.requestDecodedImage(for: item) }
            }
          }

          if sensitiveContentIsVisible(item), let color = item.contentAnalysis.color {
            RoundedRectangle(cornerRadius: 14)
              .fill(
                Color(
                  red: color.red,
                  green: color.green,
                  blue: color.blue,
                  opacity: color.alpha
                )
              )
              .frame(height: 120)
              .overlay(
                RoundedRectangle(cornerRadius: 14)
                  .stroke(Color.primary.opacity(0.10), lineWidth: 1)
              )
          }

          if sensitiveContentIsVisible(item) {
            if item.isConcealed {
              HStack(spacing: 8) {
                Label(
                  L10n.text(
                    "main.detail.visible_until_blur",
                    fallback: "Visible until Clipskein loses focus"
                  ),
                  systemImage: "eye.fill"
                )
                Spacer()
                Button(L10n.text("main.detail.hide_now", fallback: "Hide now")) {
                  revealedConcealedIDs.remove(item.id)
                }
              }
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(Color.orange)
              .padding(11)
              .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            }

            if item.kind == .files {
              fileReferencePanel(item)
            } else {
              contentPanel(for: item)
            }
          } else {
            concealedContentPanel(item)
          }

          if sensitiveContentIsVisible(item), !item.detectedBarcodes.isEmpty {
            barcodeSection(for: item)
          }

          let template = ClipTemplate(item.text)
          if sensitiveContentIsVisible(item), item.kind == .text, template.isSupported {
            HStack(spacing: 10) {
              Image(systemName: "text.badge.plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(actionColor)
              VStack(alignment: .leading, spacing: 3) {
                Text(L10n.text("main.detail.dynamic_template", fallback: "DYNAMIC TEMPLATE"))
                  .font(.system(size: 10, weight: .black, design: .monospaced))
                  .tracking(1.1)
                Text(
                  ClipTemplate.isEligible(item)
                    ? template.fields.isEmpty
                      ? L10n.text(
                        "main.detail.template_ready_dynamic",
                        fallback: "Ready to generate fresh dynamic values when copied."
                      )
                      : L10n.format(
                        template.fields.count == 1
                          ? "main.detail.template_ready_one" : "main.detail.template_ready_many",
                        fallback: template.fields.count == 1
                          ? "Ready to fill %d custom field before copying."
                          : "Ready to fill %d custom fields before copying.",
                        template.fields.count)
                    : L10n.text(
                      "main.detail.template_requires_pin",
                      fallback: "Pin this clip or give it an @alias to enable fill-before-copy."
                    )
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
              }
              Spacer()
              if ClipTemplate.isEligible(item) {
                Button(
                  template.fields.isEmpty
                    ? L10n.text("main.detail.generate", fallback: "Generate")
                    : L10n.text("main.detail.fill", fallback: "Fill")
                ) {
                  beginTemplateCopy(item)
                }
                .buttonStyle(.bordered)
              }
            }
            .padding(12)
            .background(actionColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(actionColor.opacity(0.15)))
          }

          let tableActions = tableActions(for: item)
          if sensitiveContentIsVisible(item), !tableActions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
              HStack {
                Text(L10n.text("main.detail.detected_table", fallback: "DETECTED TABLE"))
                  .font(.system(size: 10, weight: .black, design: .monospaced))
                  .tracking(1.1)
                Spacer()
                Text(
                  L10n.text(
                    "main.detail.table_local", fallback: "Structured locally from OCR")
                )
                .font(.system(size: 10, weight: .medium))
              }
              .foregroundStyle(.secondary)

              LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160), spacing: 8)],
                alignment: .leading,
                spacing: 8
              ) {
                ForEach(tableActions) { action in
                  Button {
                    copyFormattedAction(action, from: item)
                  } label: {
                    HStack(spacing: 8) {
                      Image(
                        systemName: copiedTransformationID == formattedActionCopyID(action, item)
                          ? "checkmark.circle.fill" : action.systemImage
                      )
                      Text(
                        copiedTransformationID == formattedActionCopyID(action, item)
                          ? L10n.text("main.detail.copied", fallback: "Copied")
                          : action.label.replacingOccurrences(of: "Paste ", with: "")
                      )
                      Spacer(minLength: 0)
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 11)
                    .frame(height: 40)
                    .background(BrandTheme.surface.opacity(0.68), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                      RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.07))
                    )
                  }
                  .buttonStyle(.plain)
                  .help(action.label)
                }
              }
            }
          }

          let transformations = textTransformations(for: item)
          if sensitiveContentIsVisible(item), !transformations.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
              HStack {
                Text(L10n.text("main.detail.local_text_tools", fallback: "LOCAL TEXT TOOLS"))
                  .font(.system(size: 10, weight: .black, design: .monospaced))
                  .tracking(1.1)
                Spacer()
                Text(
                  L10n.text(
                    "main.detail.original_unchanged", fallback: "Original stays unchanged")
                )
                .font(.system(size: 10, weight: .medium))
              }
              .foregroundStyle(.secondary)

              LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: 8)],
                alignment: .leading,
                spacing: 8
              ) {
                ForEach(transformations) { transformation in
                  Button {
                    copyTransformation(transformation, from: item)
                  } label: {
                    HStack(spacing: 8) {
                      Image(
                        systemName: copiedTransformationID
                          == transformationCopyID(transformation, from: item)
                          ? "checkmark.circle.fill" : transformation.systemImage
                      )
                      Text(
                        copiedTransformationID == transformationCopyID(transformation, from: item)
                          ? L10n.text("main.detail.copied", fallback: "Copied")
                          : transformation.label
                      )
                      Spacer(minLength: 0)
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 11)
                    .frame(height: 40)
                    .background(BrandTheme.surface.opacity(0.68), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                      RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.07))
                    )
                  }
                  .buttonStyle(.plain)
                  .help(
                    L10n.format(
                      "main.detail.copy_transformation",
                      fallback: "Copy %@ result",
                      transformation.label
                    )
                  )
                }
              }
            }
          }

          if sensitiveContentIsVisible(item), !localIntelligenceInput(for: item).isEmpty {
            localIntelligenceSection(for: item)
            localTranslationSection(for: item)
          }

          let extractedValues = actionableExtractedValues(for: item)
          if sensitiveContentIsVisible(item), !extractedValues.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
              HStack {
                Text(L10n.text("main.detail.quick_extract", fallback: "QUICK EXTRACT"))
                  .font(.system(size: 10, weight: .black, design: .monospaced))
                  .tracking(1.1)
                Spacer()
                let structuredActions = structuredExtractionActions(for: item)
                if !structuredActions.isEmpty {
                  Menu {
                    ForEach(structuredActions) { action in
                      Button {
                        copyStructuredExtraction(action, from: item)
                      } label: {
                        Label(structuredExtractionCopyLabel(action), systemImage: action.systemImage)
                      }
                    }
                  } label: {
                    let copied = structuredActions.contains {
                      copiedTransformationID == formattedActionCopyID($0, item)
                    }
                    Label(
                      copied
                        ? L10n.text("main.detail.copied", fallback: "Copied")
                        : L10n.text("main.detail.copy_extracted_data", fallback: "Copy data"),
                      systemImage: copied ? "checkmark.circle.fill" : "square.and.arrow.up"
                    )
                  }
                  .buttonStyle(.borderless)
                  .font(.system(size: 10, weight: .semibold))
                  .help(
                    L10n.text(
                      "main.detail.copy_extracted_data_help",
                      fallback: "Copy extracted fields as JSON or a spreadsheet-ready table"
                    )
                  )
                } else {
                  Text(
                    L10n.text("main.detail.detected_locally", fallback: "Detected on this Mac")
                  )
                  .font(.system(size: 10, weight: .medium))
                }
              }
              .foregroundStyle(.secondary)

              LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: 8)],
                alignment: .leading,
                spacing: 8
              ) {
                ForEach(extractedValues) { extracted in
                  Button {
                    copyExtractedValue(extracted, from: item)
                  } label: {
                    HStack(spacing: 8) {
                      Image(
                        systemName: copiedExtractionID == extracted.id
                          ? "checkmark.circle.fill" : extracted.kind.systemImage
                      )
                      VStack(alignment: .leading, spacing: 2) {
                        Text(extracted.kind.label)
                          .font(.system(size: 9, weight: .bold))
                          .foregroundStyle(.secondary)
                        Text(extracted.value)
                          .font(.system(size: 12, weight: .semibold, design: .rounded))
                          .lineLimit(1)
                      }
                      Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 46)
                    .background(BrandTheme.surface.opacity(0.68), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                      RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.07))
                    )
                  }
                  .buttonStyle(.plain)
                  .help(
                    L10n.format(
                      "main.detail.copy_extracted",
                      fallback: "Copy %@",
                      extracted.kind.label
                    )
                  )
                }
              }
            }
          }

          workTrailSection(for: item)

          HStack(spacing: 8) {
            if let icon = store.sourceApplicationIcon(for: item) {
              Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            } else {
              Image(systemName: "app.dashed")
            }
            Text(item.localizedSourceApplication())
            Spacer()
            Text(L10n.text("main.detail.local_only", fallback: "Stored only on this Mac"))
          }
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.secondary)
        }
        .padding(28)
      }

      Divider().opacity(0.55)

      HStack(spacing: 10) {
        if sensitiveContentIsVisible(item) {
          if item.kind == .files,
            item.filePaths.allSatisfy({
              store.fileReferenceStatus(for: $0, in: item) == .available
            })
          {
            Button {
              _ = FileQuickLookController.shared.preview(
                item.filePaths.map { URL(fileURLWithPath: $0) }
              )
            } label: {
              Label(
                L10n.text("main.detail.quick_look", fallback: "Quick Look"),
                systemImage: "eye"
              )
              .frame(height: 42)
            }
            .buttonStyle(.bordered)

            Button {
              NSWorkspace.shared.activateFileViewerSelecting(
                item.filePaths.map { URL(fileURLWithPath: $0) }
              )
            } label: {
              Label(
                L10n.text("main.detail.show_finder", fallback: "Show in Finder"),
                systemImage: "folder"
              )
              .frame(height: 42)
            }
            .buttonStyle(.bordered)
          }

          if ClipTemplate.isEligible(item) {
            Button {
              beginTemplateCopy(item)
            } label: {
              Label(
                L10n.text("main.detail.fill_template", fallback: "Fill template"),
                systemImage: "text.badge.plus"
              )
              .frame(height: 42)
            }
            .buttonStyle(.bordered)
          }

          if let url = item.contentAnalysis.actionURL {
            Button {
              NSWorkspace.shared.open(url)
            } label: {
              Label(
                item.contentAnalysis.kind == .email
                  ? L10n.text("main.detail.new_email", fallback: "New email")
                  : L10n.text("main.detail.open_link", fallback: "Open link"),
                systemImage: "arrow.up.right"
              )
              .frame(height: 42)
            }
            .buttonStyle(.bordered)
          }

          if let formatted = item.contentAnalysis.formattedText, formatted != item.text {
            Button {
              markCopied(item) { copyText(formatted, from: item) }
            } label: {
              Label(
                L10n.text("main.detail.copy_formatted", fallback: "Copy formatted"),
                systemImage: "text.alignleft"
              )
              .frame(height: 42)
            }
            .buttonStyle(.bordered)
          }

          if item.kind != .files {
            Button {
              store.toggleStackMembership(item)
            } label: {
              Label(
                store.isInStack(item)
                  ? L10n.text("main.detail.in_stack", fallback: "In Stack")
                  : L10n.text("main.detail.add_stack", fallback: "Add to Stack"),
                systemImage: store.isInStack(item)
                  ? "checkmark.circle.fill" : "square.stack.3d.up"
              )
              .frame(height: 42)
            }
            .buttonStyle(.bordered)
            .disabled(!store.isInStack(item) && !store.canAddToStack(item))
          }
        }

        Button {
          if item.kind == .image {
            guard store.preparingImageCopyID == nil else { return }
            Task { @MainActor in
              if await store.copyForUse(item, securely: item.isConcealed) {
                showCopiedFeedback(for: item)
              }
            }
          } else {
            markCopied(item) {
              item.isConcealed ? store.secureCopy(item) : store.copy(item)
            }
          }
        } label: {
          HStack {
            Image(
              systemName: copiedID == item.id
                ? "checkmark" : (item.isConcealed ? "timer" : "doc.on.doc")
            )
            Text(
              store.preparingImageCopyID == item.id
                ? L10n.text("main.detail.preparing_image", fallback: "Preparing image…")
                : copiedID == item.id
                ? (item.isConcealed
                  ? L10n.text("main.detail.copied_securely", fallback: "Copied securely")
                  : L10n.text("main.detail.copied", fallback: "Copied"))
                : (item.isConcealed
                  ? L10n.text("main.detail.copy_securely", fallback: "Copy securely")
                  : L10n.text("main.detail.copy", fallback: "Copy"))
            )
            Spacer()
            Text("↩")
          }
          .font(.system(size: 13, weight: .bold))
          .padding(.horizontal, 18)
          .frame(height: 46)
          .frame(maxWidth: .infinity)
          .foregroundStyle(.white)
          .background(BrandTheme.plum, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.return, modifiers: [])
        .disabled(store.preparingImageCopyID != nil)
      }
      .padding(20)
    }
  }

  private var contextNavigationBanner: some View {
    HStack(spacing: 9) {
      Image(systemName: "arrow.triangle.branch")
        .foregroundStyle(actionColor)
      Text(
        L10n.text(
          "main.context.outside_results",
          fallback: "Viewing a nearby clip outside the current results"
        )
      )
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(.secondary)
      Spacer()
      Button(L10n.text("main.context.back", fallback: "Back to results")) {
        returnFromContext()
      }
      .buttonStyle(.borderless)
      .font(.system(size: 11, weight: .bold))
      .foregroundStyle(actionColor)
    }
    .padding(.horizontal, 24)
    .frame(minHeight: 38)
    .background(actionColor.opacity(0.055))
  }

  @ViewBuilder
  private func workTrailSection(for item: ClipItem) -> some View {
    let entries = ClipContextTrail.entries(around: item, in: store.items)
    if !entries.isEmpty {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Text(L10n.text("main.context.title", fallback: "WORK TRAIL"))
            .font(.system(size: 10, weight: .black, design: .monospaced))
            .tracking(1.1)
          Spacer()
          Text(
            L10n.text(
              "main.context.detail",
              fallback: "Copied within 30 minutes of this clip"
            )
          )
          .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(.secondary)

        VStack(spacing: 7) {
          ForEach(entries) { entry in
            Button {
              openContextEntry(entry.item, from: item)
            } label: {
              HStack(spacing: 10) {
                Image(
                  systemName: entry.relation == .before
                    ? "arrow.up.left" : "arrow.down.right"
                )
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(actionColor)
                .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                  Text(entry.item.localizedDisplayTitle())
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                  HStack(spacing: 5) {
                    Text(
                      entry.relation == .before
                        ? L10n.text("main.context.before", fallback: "Before")
                        : L10n.text("main.context.after", fallback: "After")
                    )
                    Text("·")
                    Text(entry.item.localizedSourceApplication())
                    Text("·")
                    Text(entry.item.createdAt, style: .time)
                  }
                  .font(.system(size: 9, weight: .medium))
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                  .font(.system(size: 9, weight: .bold))
                  .foregroundStyle(.tertiary)
              }
              .padding(.horizontal, 11)
              .frame(minHeight: 46)
              .background(BrandTheme.surface.opacity(0.68), in: RoundedRectangle(cornerRadius: 10))
              .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.07)))
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
              L10n.format(
                "main.context.open",
                fallback: "Open nearby clip: %@",
                entry.item.localizedDisplayTitle()
              )
            )
          }
        }
      }
    }
  }

  private func openContextEntry(_ target: ClipItem, from source: ClipItem) {
    if !store.filteredItems.contains(where: { $0.id == target.id }) {
      contextReturnID = contextReturnID ?? source.id
    }
    store.selectedID = target.id
    historyIsFocused = true
  }

  private func returnFromContext() {
    let returnID = contextReturnID
    contextReturnID = nil
    if let returnID, store.filteredItems.contains(where: { $0.id == returnID }) {
      store.selectedID = returnID
    } else {
      store.normalizeSelection()
    }
    historyIsFocused = true
  }

  private func detailActionsMenu(for item: ClipItem) -> some View {
    Menu {
      if SemanticSearchRequest.suggestedQuery(for: item) != nil {
        Button {
          store.findSimilar(to: item)
        } label: {
          Label(
            L10n.text("semantic.find_similar", fallback: "Find Similar"),
            systemImage: "brain.head.profile"
          )
        }
        Divider()
      }
      Menu {
        ForEach(ClipExpirationPreset.allCases) { preset in
          Button(localizedExpirationPreset(preset)) {
            store.setExpiration(item, at: preset.date())
          }
        }
      } label: {
        Label(
          item.expiresAt == nil
            ? L10n.text("main.detail.expiration.set", fallback: "Set expiration")
            : L10n.text("main.detail.expiration.change", fallback: "Change expiration"),
          systemImage: item.expiresAt == nil ? "clock" : "timer"
        )
      }

      Button {
        revealedConcealedIDs.remove(item.id)
        store.toggleConcealment(item)
      } label: {
        Label(
          item.isConcealed
            ? L10n.text("main.detail.reveal_permanently", fallback: "Stop concealing")
            : L10n.text("main.detail.conceal", fallback: "Conceal preview"),
          systemImage: item.isConcealed ? "eye.fill" : "eye.slash"
        )
      }

      Divider()

      Button {
        renamingItem = item
      } label: {
        Label(
          item.customTitle == nil && item.alias == nil
            ? L10n.text("main.detail.add_title_alias", fallback: "Add title or alias…")
            : L10n.text("main.detail.edit_details", fallback: "Edit details…"),
          systemImage: "pencil"
        )
      }

      if item.kind != .files {
        Button {
          editingItem = item
        } label: {
          Label(
            item.kind == .image
              ? L10n.text("main.detail.edit_ocr", fallback: "Edit recognized text as a copy…")
              : L10n.text("main.detail.edit_copy", fallback: "Create edited copy…"),
            systemImage: "square.and.pencil"
          )
        }
        .disabled(
          editableContent(for: item).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !sensitiveContentIsVisible(item)
        )
      }

      Button {
        taggingItem = item
      } label: {
        Label(
          item.tags.isEmpty
            ? L10n.text("main.detail.add_tags", fallback: "Add tags…")
            : L10n.text("main.detail.edit_tags", fallback: "Edit tags…"),
          systemImage: item.tags.isEmpty ? "tag" : "tag.fill"
        )
      }

      if !store.boards.isEmpty {
        Menu {
          ForEach(store.boards) { board in
            Button {
              store.toggleBoardMembership(board, for: item)
            } label: {
              Label(
                board.name,
                systemImage: item.boardIDs.contains(board.id) ? "checkmark" : "rectangle.stack"
              )
            }
          }
        } label: {
          Label(
            L10n.text("main.detail.pinboards", fallback: "Pinboards"),
            systemImage: item.boardIDs.isEmpty ? "rectangle.stack" : "rectangle.stack.fill"
          )
        }
      }

      if item.kind == .image {
        Button {
          exportImage(item)
        } label: {
          Label(
            store.isExportingImage
              ? L10n.text("main.detail.exporting_image", fallback: "Exporting image…")
              : L10n.text("main.detail.export_image", fallback: "Export Image…"),
            systemImage: "square.and.arrow.down"
          )
        }
        .disabled(store.isExportingImage || !sensitiveContentIsVisible(item))
      }

      Divider()

      Button(role: .destructive) {
        store.delete(item)
      } label: {
        Label(L10n.text("main.detail.delete", fallback: "Delete Clip"), systemImage: "trash")
      }
    } label: {
      Image(systemName: "ellipsis.circle")
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .help(L10n.text("main.detail.more_actions", fallback: "More actions"))
    .accessibilityLabel(L10n.text("main.detail.more_actions", fallback: "More actions"))
  }

  private func exportImage(_ item: ClipItem) {
    guard item.kind == .image, sensitiveContentIsVisible(item), !store.isExportingImage else {
      return
    }
    guard let destination = ImageExportPanel.chooseDestination(for: item) else { return }
    Task { await store.exportImage(item, to: destination) }
  }

  private func clipDragSource(for item: ClipItem) -> some View {
    let availability = store.dragAvailability(for: item)
    return ClipDragSourceView(
      availability: availability,
      makePasteboardWriters: { store.dragPasteboardWriters(for: item) },
      makePreviewImage: { store.dragPreviewImage(for: item) },
      onCompleted: {
        store.recordUse(for: item)
        store.reportNotice(
          item.kind == .files && item.filePaths.count > 1
            ? L10n.format(
              "notice.dragged_files", fallback: "Dragged %d files", item.filePaths.count)
            : L10n.text("notice.dragged_clip", fallback: "Clip dragged to another app"),
          systemImage: "hand.draw.fill"
        )
      }
    )
    .frame(width: 24, height: 24)
    .help(availability.helpText)
  }

  private var emptyState: some View {
    VStack(spacing: 12) {
      Spacer()
      Image(systemName: emptyStateIcon)
        .font(.system(size: 38, weight: .light))
      Text(emptyStateTitle)
        .font(.system(size: 15, weight: .bold))
      Text(emptyStateMessage)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      if !trimmedSearchText.isEmpty || store.selectedTag != nil || store.selectedBoardID != nil {
        Button(L10n.text("main.clear_filters", fallback: "Clear filters")) {
          resetViewFilters()
        }
        .buttonStyle(.borderedProminent)
      } else if store.filter != .all {
        Button(L10n.text("main.empty.show_all", fallback: "Show all clips")) {
          store.filter = .all
        }
        .buttonStyle(.borderedProminent)
      } else if !store.isMonitoring {
        Button(L10n.text("main.empty.resume_monitoring", fallback: "Resume monitoring")) {
          store.startMonitoring()
        }
        .buttonStyle(.borderedProminent)
      } else if store.items.isEmpty {
        HStack(spacing: 8) {
          Button {
            performImageImportAction()
          } label: {
            Label(
              imageImportActionTitle,
              systemImage: store.imageImportProgress == nil ? "photo.badge.plus" : "xmark.circle"
            )
          }
          .buttonStyle(.borderedProminent)
          .disabled(store.imageImportProgress?.isCancelling == true)

          Button {
            store.captureRegion()
          } label: {
            Label(
              L10n.text("main.screen_ocr", fallback: "Screen OCR"),
              systemImage: "viewfinder"
            )
          }
          .buttonStyle(.bordered)
          .disabled(store.isCapturingRegion)
        }
      }
      Spacer()
    }
    .frame(maxWidth: .infinity)
    .padding(30)
  }

  private var imageImportActionTitle: String {
    guard let progress = store.imageImportProgress else {
      return L10n.text("main.import_screenshots", fallback: "Import screenshots")
    }
    if progress.isCancelling {
      return L10n.text("main.import.stopping", fallback: "Stopping import…")
    }
    return L10n.format(
      "main.import.stop_progress",
      fallback: "Stop import %d/%d",
      progress.completed,
      progress.total
    )
  }

  private func performImageImportAction() {
    if store.imageImportProgress == nil {
      store.importImage()
    } else {
      store.cancelImageImport()
    }
  }

  private func storageIssueBanner(_ issue: StorageIssue) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(
        systemName: issue.kind == .persistence
          ? "externaldrive.badge.exclamationmark" : "doc.badge.clock"
      )
      .font(.system(size: 16, weight: .semibold))
      .foregroundStyle(issue.kind == .persistence ? Color.red : Color.orange)

      VStack(alignment: .leading, spacing: 4) {
        Text(issue.message)
          .font(.system(size: 12, weight: .bold))
        Text(issue.detail)
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
          .lineLimit(2)
        if let recoveryFileName = issue.recoveryFileName {
          Text(recoveryFileName)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }

      Spacer(minLength: 4)

      VStack(alignment: .trailing, spacing: 5) {
        if issue.kind == .persistence {
          Button(
            store.isUnlockingStorage
              ? L10n.text("main.storage.unlocking", fallback: "Unlocking…")
              : L10n.text("main.storage.retry", fallback: "Retry")
          ) {
            store.retryStorage()
          }
          .disabled(store.isUnlockingStorage)
          if store.isStorageUnlockTakingLong {
            Button(
              L10n.text("main.storage.open_keychain", fallback: "Open Keychain Access")
            ) {
              store.openKeychainAccess()
            }
          }
        } else {
          Button(L10n.text("main.detail.dismiss", fallback: "Dismiss")) {
            store.dismissRecoveredHistoryNotice()
          }
        }
        Button(L10n.text("main.storage.show_files", fallback: "Show Files")) {
          store.revealStorage()
        }
      }
      .buttonStyle(.plain)
      .font(.system(size: 10, weight: .bold))
      .foregroundStyle(actionColor)
    }
    .padding(12)
    .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
    .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.orange.opacity(0.24)))
    .help(issue.detail)
  }

  private var trimmedSearchText: String {
    store.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func saveCandidates(_ candidates: [ClipItem], to board: ClipBoard) {
    store.addItemsToBoard(candidates, board: board)
    store.searchText = ""
    store.filter = .all
    store.selectedTag = nil
    store.selectedBoardID = board.id
  }

  private func copyVisibleStructuredResults() {
    structuredResultsTask?.cancel()
    let candidates = store.filteredItems
    guard !candidates.isEmpty else { return }
    isPreparingStructuredResults = true
    structuredResultsTask = Task {
      let result = await Task.detached(priority: .utility) {
        SmartExtractor.structuredTSV(from: candidates)
      }.value
      guard !Task.isCancelled, store.isSessionActive else {
        isPreparingStructuredResults = false
        structuredResultsTask = nil
        return
      }
      isPreparingStructuredResults = false
      structuredResultsTask = nil
      guard let result else {
        store.reportNotice(
          L10n.text(
            "notice.results_table_empty",
            fallback: "No visible results contain enough structured fields"
          ),
          systemImage: "tablecells.badge.ellipsis"
        )
        return
      }
      guard store.copyGeneratedText(result.text) else {
        store.reportNotice(
          L10n.text(
            "notice.results_table_copy_failed",
            fallback: "Could not copy the structured results table"
          ),
          systemImage: "exclamationmark.triangle.fill"
        )
        return
      }
      store.reportNotice(
        L10n.format(
          "notice.results_table_copied",
          fallback: "%d structured rows copied · %d results skipped",
          result.rowCount,
          result.omittedCount
        ),
        systemImage: "checkmark.circle.fill"
      )
    }
  }

  private func copyVisibleReceiptSummary() {
    structuredResultsTask?.cancel()
    let candidates = store.filteredItems
    guard !candidates.isEmpty else { return }
    isPreparingStructuredResults = true
    structuredResultsTask = Task {
      let result = await Task.detached(priority: .utility) {
        SmartExtractor.receiptSummaryTSV(from: candidates)
      }.value
      guard !Task.isCancelled, store.isSessionActive else {
        isPreparingStructuredResults = false
        structuredResultsTask = nil
        return
      }
      isPreparingStructuredResults = false
      structuredResultsTask = nil
      guard let result else {
        store.reportNotice(
          L10n.text(
            "notice.receipt_summary_empty",
            fallback: "No visible receipts contain a usable total"
          ),
          systemImage: "chart.bar.doc.horizontal"
        )
        return
      }
      guard store.copyGeneratedText(result.text) else {
        store.reportNotice(
          L10n.text(
            "notice.receipt_summary_copy_failed",
            fallback: "Could not copy the receipt summary"
          ),
          systemImage: "exclamationmark.triangle.fill"
        )
        return
      }
      store.reportNotice(
        L10n.format(
          "notice.receipt_summary_copied",
          fallback: "%d receipts summarized across %d currencies · %d results skipped",
          result.receiptCount,
          result.currencyCount,
          result.omittedCount
        ),
        systemImage: "checkmark.circle.fill"
      )
    }
  }

  private var visibleResultsCollectionMenu: some View {
    Menu {
      Button {
        store.addItemsToStack(store.filteredItems)
      } label: {
        Label(
          L10n.text("results.collect_stack", fallback: "Add results to Stack"),
          systemImage: "square.stack.3d.up"
        )
      }

      Button {
        copyVisibleStructuredResults()
      } label: {
        Label(
          isPreparingStructuredResults
            ? L10n.text("results.table.preparing", fallback: "Preparing table…")
            : L10n.text("results.table.copy", fallback: "Copy structured table"),
          systemImage: "tablecells"
        )
      }
      .disabled(isPreparingStructuredResults)

      Button {
        copyVisibleReceiptSummary()
      } label: {
        Label(
          isPreparingStructuredResults
            ? L10n.text("results.table.preparing", fallback: "Preparing table…")
            : L10n.text("results.receipt_summary.copy", fallback: "Copy receipt summary"),
          systemImage: "chart.bar.doc.horizontal"
        )
      }
      .disabled(isPreparingStructuredResults)

      Divider()

      Button {
        resultBoardCandidateIDs = store.filteredItems.map(\.id)
        showingResultsBoard = true
      } label: {
        Label(
          L10n.text("results.pinboard.new", fallback: "New Pinboard from Results…"),
          systemImage: "rectangle.stack.badge.plus"
        )
      }
      .disabled(store.boards.count >= ClipBoard.maximumCount)

      if !store.boards.isEmpty {
        Section(L10n.text("results.pinboard.existing", fallback: "Add results to Pinboard")) {
          ForEach(store.boards) { board in
            Button {
              saveCandidates(store.filteredItems, to: board)
            } label: {
              Label(board.name, systemImage: "rectangle.stack.fill")
            }
          }
        }
      }
    } label: {
      Image(systemName: "rectangle.stack.badge.plus")
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(actionColor)
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .help(
      L10n.format(
        "results.collect_help",
        fallback: "Collect all %d visible results into Stack or a Pinboard",
        store.filteredItems.count
      )
    )
    .accessibilityLabel(
      L10n.text("results.collect", fallback: "Collect visible results")
    )
  }

  private var searchFilterMenu: some View {
    Menu {
      Section(L10n.text("main.search_filter.content", fallback: "Content")) {
        searchTokenMenuButton(
          L10n.text("main.search_filter.text", fallback: "Text only"), token: "type:text")
        searchTokenMenuButton(
          L10n.text("main.search_filter.images", fallback: "Images only"), token: "type:image")
      }
      Section(L10n.text("main.search_filter.smart", fallback: "Smart collections")) {
        searchTokenMenuButton(
          L10n.text("main.filter.receipts", fallback: "Receipts & invoices"),
          token: "kind:receipt")
        searchTokenMenuButton(
          L10n.text("main.filter.links", fallback: "Links"), token: "kind:link")
        searchTokenMenuButton(
          L10n.text("main.filter.emails", fallback: "Emails"), token: "kind:email")
        searchTokenMenuButton(
          L10n.text("main.filter.code", fallback: "Code"), token: "kind:code")
        searchTokenMenuButton("JSON", token: "kind:json")
        searchTokenMenuButton(
          L10n.text("main.filter.colors", fallback: "Colors"), token: "kind:color")
      }
      Section(L10n.text("main.search_filter.status", fallback: "Status")) {
        searchTokenMenuButton(
          L10n.text("main.filter.pinned", fallback: "Pinned"), token: "is:pinned")
        searchTokenMenuButton(
          L10n.text("main.search_filter.unpinned", fallback: "Unpinned"), token: "is:unpinned")
        searchTokenMenuButton(
          L10n.text("main.search_filter.concealed", fallback: "Concealed"),
          token: "is:concealed")
        searchTokenMenuButton(
          L10n.text("main.search_filter.visible", fallback: "Visible"), token: "is:visible")
        searchTokenMenuButton(
          L10n.text("main.search_filter.expiring", fallback: "Expiring"), token: "is:expiring")
        searchTokenMenuButton(
          L10n.text("main.search_filter.permanent", fallback: "Permanent"),
          token: "is:permanent")
      }
      if !store.sourceApplicationFacets.isEmpty {
        Section(L10n.text("main.search_filter.apps", fallback: "Source applications")) {
          ForEach(store.sourceApplicationFacets) { application in
            sourceApplicationFilterButton(application)
          }
        }
      }
      if !store.popularTags.isEmpty {
        Section(L10n.text("main.search_filter.tags", fallback: "Tags")) {
          ForEach(store.popularTags, id: \.self) { tag in
            Button(tag) { appendSearchToken("tag:\(quotedSearchValue(tag))") }
          }
        }
      }
      Section(L10n.text("main.search_filter.syntax", fallback: "More syntax")) {
        Text("app:Safari")
        Text("after:2026-09-01")
        Text("before:2026-10-01")
      }
    } label: {
      Image(systemName: "line.3.horizontal.decrease")
        .font(.system(size: 14, weight: .bold))
        .frame(width: 42, height: 42)
        .background(BrandTheme.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.primary.opacity(0.07)))
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .help(
      L10n.text("main.search_filter.help", fallback: "Add or remove a precise search filter")
    )
    .accessibilityLabel(L10n.text("main.search_filter.label", fallback: "Search filters"))
  }

  private var savedViewsMenu: some View {
    Menu {
      Button(L10n.text("main.saved_view.save", fallback: "Save current view…")) {
        showingSaveView = true
      }
      .disabled(!store.canSaveCurrentView)

      if !store.savedViews.isEmpty {
        Section(L10n.text("main.saved_view.saved", fallback: "Saved views")) {
          ForEach(store.savedViews) { view in
            Button {
              store.applySavedView(view)
            } label: {
              Label(
                view.name,
                systemImage: store.activeSavedViewID == view.id
                  ? "checkmark.circle.fill" : "bookmark"
              )
            }
            .help(view.criteriaDescription)
          }
        }
        Menu(L10n.text("main.saved_view.remove", fallback: "Remove saved view")) {
          ForEach(store.savedViews) { view in
            Button(view.name, role: .destructive) { store.deleteSavedView(view) }
          }
        }
      }
    } label: {
      Image(systemName: store.activeSavedViewID == nil ? "bookmark" : "bookmark.fill")
        .font(.system(size: 14, weight: .bold))
        .frame(width: 42, height: 42)
        .background(BrandTheme.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.primary.opacity(0.07)))
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .help(
      L10n.text("main.saved_view.help", fallback: "Save or open a reusable view")
    )
    .accessibilityLabel(L10n.text("main.saved_view.saved", fallback: "Saved views"))
  }

  private var currentViewCriteriaDescription: String {
    SavedClipView(
      name: "Current view",
      query: trimmedSearchText,
      filter: store.filter,
      tag: store.selectedTag,
      boardID: store.selectedBoardID,
      interpretsNaturalLanguage: !store.searchAsLiteral
    ).criteriaDescription
  }

  private var suggestedSavedViewName: String {
    if let activeID = store.activeSavedViewID,
      let active = store.savedViews.first(where: { $0.id == activeID })
    {
      return active.name
    }
    if let tag = store.selectedTag {
      return L10n.format("saved_view.suggested.tag", fallback: "%@ clips", tag)
    }
    if let boardID = store.selectedBoardID,
      let board = store.boards.first(where: { $0.id == boardID })
    {
      return board.name
    }
    if store.filter != .all { return store.filter.localizedLabel() }
    let query = trimmedSearchText
    return query.isEmpty
      ? L10n.text("saved_view.suggested.default", fallback: "Saved view")
      : String(query.prefix(30))
  }

  private var stackBar: some View {
    HStack(spacing: 9) {
      VStack(alignment: .leading, spacing: 2) {
        Label(
          L10n.format(
            "main.stack.count", fallback: "%d in Stack", store.stackItems.count),
          systemImage: "square.stack.3d.up.fill"
        )
        .font(.system(size: 11, weight: .bold, design: .rounded))
        .foregroundStyle(actionColor)
        if let nextItem = store.stackItems.first {
          Text(
            L10n.format(
              "main.stack.next_preview", fallback: "Next: %@", nextItem.localizedDisplayTitle())
          )
          .font(.system(size: 9, weight: .medium, design: .rounded))
          .foregroundStyle(.secondary)
          .lineLimit(1)
        }
      }
      Spacer(minLength: 4)
      Button {
        store.copyNextStackItem()
      } label: {
        Label(
          L10n.text("main.stack.next", fallback: "Next"),
          systemImage: "arrow.right.circle.fill"
        )
      }
      .buttonStyle(.plain)
      .font(.system(size: 11, weight: .bold))
      .help(
        L10n.text(
          "main.stack.next_help", fallback: "Copy the first Stack item and advance the queue")
      )

      if store.stackItems.count == 2 {
        Button {
          stackComparison = ClipTextComparison.comparison(for: store.stackItems)
        } label: {
          Label(
            L10n.text("main.stack.compare", fallback: "Compare"),
            systemImage: "arrow.left.arrow.right"
          )
          .labelStyle(.iconOnly)
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .bold))
        .disabled(!stackComparisonIsAvailable)
        .help(stackComparisonHelp)
      }

      Button {
        store.copyStack(format: .paragraphs)
      } label: {
        Label(L10n.text("main.detail.copy", fallback: "Copy"), systemImage: "doc.on.doc")
      }
      .buttonStyle(.plain)
      .font(.system(size: 11, weight: .bold))

      Menu {
        Section(L10n.text("main.stack.copy_as", fallback: "Copy Stack as")) {
          ForEach(ClipStackFormat.allCases, id: \.self) { format in
            Button {
              store.copyStack(format: format)
            } label: {
              Label(localizedStackFormat(format), systemImage: format.systemImage)
            }
          }
        }
        Section(L10n.text("main.stack.contents", fallback: "Contents")) {
          ForEach(Array(store.stackItems.enumerated()), id: \.element.id) { entry in
            let index = entry.offset
            let item = entry.element
            Menu {
              Button(L10n.text("main.stack.move_earlier", fallback: "Move earlier")) {
                store.moveStackItem(item, by: -1)
              }
              .disabled(index == 0)
              Button(L10n.text("main.stack.move_later", fallback: "Move later")) {
                store.moveStackItem(item, by: 1)
              }
              .disabled(index == store.stackItems.count - 1)
              Divider()
              Button(
                L10n.text("main.stack.remove", fallback: "Remove from Stack"),
                role: .destructive
              ) {
                store.toggleStackMembership(item)
              }
            } label: {
              Label(item.localizedDisplayTitle(), systemImage: "line.3.horizontal")
            }
          }
        }
        Divider()
        Button(L10n.text("main.stack.clear", fallback: "Clear Stack"), role: .destructive) {
          showingClearStackConfirmation = true
        }
      } label: {
        Image(systemName: "ellipsis.circle")
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .fixedSize()
      .help(
        L10n.text(
          "main.stack.more_help", fallback: "Choose a Stack format or manage its contents")
      )
    }
    .padding(.horizontal, 11)
    .frame(height: 46)
    .background(actionColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    .overlay(RoundedRectangle(cornerRadius: 9).stroke(actionColor.opacity(0.16)))
    .confirmationDialog(
      L10n.format(
        "main.stack.clear_confirm_title", fallback: "Remove all %d Stack items?",
        store.stackItems.count),
      isPresented: $showingClearStackConfirmation,
      titleVisibility: .visible
    ) {
      Button(L10n.text("main.stack.clear_confirm", fallback: "Clear Stack"), role: .destructive) {
        store.clearStack()
      }
    } message: {
      Text(
        L10n.text(
          "main.stack.clear_detail",
          fallback: "Your clipboard history stays unchanged; only this Stack is cleared."
        )
      )
    }
  }

  private func appendSearchToken(_ token: String) {
    let existingTokens = trimmedSearchText.split(whereSeparator: \.isWhitespace).map(String.init)
    guard !existingTokens.contains(token) else { return }
    store.searchText = trimmedSearchText.isEmpty ? token : "\(trimmedSearchText) \(token)"
  }

  @ViewBuilder
  private func searchTokenMenuButton(_ title: String, token: String) -> some View {
    Button {
      toggleSearchToken(token)
    } label: {
      if hasSearchToken(token) {
        Label(title, systemImage: "checkmark")
      } else {
        Text(title)
      }
    }
  }

  private func hasSearchToken(_ token: String) -> Bool {
    SearchTokenEditor.contains(token, in: trimmedSearchText)
  }

  private func toggleSearchToken(_ token: String) {
    store.searchText = SearchTokenEditor.toggling(token, in: trimmedSearchText)
  }

  @ViewBuilder
  private func sourceApplicationFilterButton(_ application: SourceApplicationFacet) -> some View {
    let filterValue = application.bundleIdentifier ?? application.name
    let token = "app:\(quotedSearchValue(filterValue))"
    Button {
      toggleSearchToken(token)
    } label: {
      HStack(spacing: 7) {
        if let icon = store.sourceApplicationIcon(
          bundleIdentifier: application.bundleIdentifier
        ) {
          Image(nsImage: icon)
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
        } else {
          Image(systemName: "app.dashed")
            .frame(width: 16, height: 16)
        }
        Text(application.name)
        Spacer(minLength: 8)
        Text("\(application.count)")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
        if hasSearchToken(token) {
          Image(systemName: "checkmark")
        }
      }
    }
  }

  private var keyboardCommandButtons: some View {
    Group {
      Button(L10n.text("main.focus_search", fallback: "Focus search")) {
        historyIsFocused = false
        searchIsFocused = true
      }
      .keyboardShortcut("f", modifiers: [.command])

      Button(L10n.text("main.clear_search_or_filters", fallback: "Clear search or filters")) {
        clearSearchOrFilters()
      }
      .keyboardShortcut(.cancelAction)
    }
    .opacity(0)
    .frame(width: 0, height: 0)
    .accessibilityHidden(true)
  }

  private func clearSearchOrFilters() {
    if !trimmedSearchText.isEmpty {
      store.searchText = ""
    } else if store.selectedTag != nil || store.selectedBoardID != nil || store.filter != .all {
      resetViewFilters()
    } else {
      searchIsFocused = false
      historyIsFocused = true
    }
  }

  private func moveHistorySelection(_ direction: MoveCommandDirection) {
    switch direction {
    case .up: store.selectAdjacentVisibleItem(by: -1)
    case .down: store.selectAdjacentVisibleItem(by: 1)
    default: break
    }
  }

  private func resetViewFilters() {
    store.searchText = ""
    store.selectedTag = nil
    store.selectedBoardID = nil
    store.filter = .all
  }

  private func tagFilterActionLabel(_ tag: String) -> String {
    store.selectedTag?.localizedCaseInsensitiveCompare(tag) == .orderedSame
      ? L10n.text("main.tag.clear_filter", fallback: "Clear tag filter")
      : L10n.format("main.tag.show", fallback: "Show clips tagged %@", tag)
  }

  private func localizedFilterLabel(_ filter: ClipFilter) -> String {
    filter.localizedLabel()
  }

  private func localizedContentKindLabel(_ kind: ClipContentKind) -> String {
    kind.localizedLabel()
  }

  private func localizedExpirationPreset(_ preset: ClipExpirationPreset) -> String {
    switch preset {
    case .oneHour: L10n.text("main.expiration.one_hour", fallback: "In 1 hour")
    case .endOfDay: L10n.text("main.expiration.end_of_day", fallback: "At end of day")
    case .oneDay: L10n.text("main.expiration.one_day", fallback: "In 24 hours")
    case .oneWeek: L10n.text("main.expiration.one_week", fallback: "In 7 days")
    case .never: L10n.text("main.expiration.never", fallback: "Never")
    }
  }

  private func localizedStackFormat(_ format: ClipStackFormat) -> String {
    switch format {
    case .paragraphs: L10n.text("main.stack.format.paragraphs", fallback: "Paragraphs")
    case .lines: L10n.text("main.stack.format.lines", fallback: "Plain lines")
    case .bullets: L10n.text("main.stack.format.bullets", fallback: "Bullet list")
    case .numbered: L10n.text("main.stack.format.numbered", fallback: "Numbered list")
    }
  }

  private func quotedSearchValue(_ value: String) -> String {
    let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
    return escaped.contains(where: \.isWhitespace) ? "\"\(escaped)\"" : escaped
  }

  private var emptyStateIcon: String {
    if store.selectedBoardID != nil { return "rectangle.stack" }
    if store.selectedTag != nil { return "tag" }
    if !trimmedSearchText.isEmpty { return "magnifyingglass" }
    if store.filter != .all { return "line.3.horizontal.decrease.circle" }
    if !store.isMonitoring { return "pause.circle" }
    return "square.on.square.dashed"
  }

  private var emptyStateTitle: String {
    if let boardID = store.selectedBoardID,
      let board = store.boards.first(where: { $0.id == boardID })
    {
      return L10n.format(
        "main.empty.board_title", fallback: "Nothing in %@ yet", board.name)
    }
    if let selectedTag = store.selectedTag {
      return L10n.format(
        "main.empty.tag_title", fallback: "No clips tagged %@", selectedTag)
    }
    if !trimmedSearchText.isEmpty {
      return L10n.text("main.empty.search_title", fallback: "Nothing matches that search")
    }
    if store.filter != .all {
      return L10n.format(
        "main.empty.filter_title", fallback: "No %@ yet",
        localizedFilterLabel(store.filter).localizedLowercase)
    }
    if !store.isMonitoring {
      return L10n.text(
        "main.empty.monitoring_title", fallback: "Clipboard monitoring is paused")
    }
    return L10n.text("main.empty.history_title", fallback: "Copy something to begin")
  }

  private var emptyStateMessage: String {
    if store.selectedBoardID != nil {
      return L10n.text(
        "main.empty.board_detail",
        fallback: "Add a clip from its Pinboards menu, or clear the filter to return to all clips."
      )
    }
    if store.selectedTag != nil {
      return trimmedSearchText.isEmpty
        ? L10n.text(
          "main.empty.tag_detail",
          fallback: "Choose another tag or clear the filter to see your full history."
        )
        : L10n.text(
          "main.empty.tag_search_detail",
          fallback: "No clips match both this tag and your search."
        )
    }
    if !trimmedSearchText.isEmpty {
      return L10n.text(
        "main.empty.search_detail",
        fallback: "Try ordinary words or narrow the search with the filter button."
      )
    }
    if store.filter != .all {
      return L10n.text(
        "main.empty.filter_detail", fallback: "Switch back to All to see the rest of your history."
      )
    }
    if !store.isMonitoring {
      return L10n.text(
        "main.empty.monitoring_detail",
        fallback: "Resume monitoring when you want Clipskein to remember new copies."
      )
    }
    return L10n.text(
      "main.empty.history_detail",
      fallback: "Text and images will appear here automatically and stay on this Mac."
    )
  }

  private var stackComparisonIsAvailable: Bool {
    ClipTextComparison.availability(for: store.stackItems) == .ready
  }

  private var stackComparisonHelp: String {
    switch ClipTextComparison.availability(for: store.stackItems) {
    case .ready:
      L10n.text(
        "main.stack.compare_help", fallback: "Compare the first and second Stack clips"
      )
    case .needsExactlyTwo:
      L10n.text("main.stack.compare_two", fallback: "Add exactly two clips to compare")
    case .concealed:
      L10n.text(
        "main.stack.compare_concealed",
        fallback: "Concealed clips cannot be shown in a comparison"
      )
    case .unsupported:
      L10n.text(
        "main.stack.compare_text", fallback: "Both Stack clips need readable text"
      )
    case .tooLarge:
      L10n.text(
        "main.stack.compare_large", fallback: "These clips are too large to compare safely"
      )
    }
  }

  private func ocrDescription(for item: ClipItem) -> String {
    switch item.ocrState {
    case .pending: L10n.text("main.ocr.recognizing", fallback: "Recognizing text…")
    case .complete:
      item.ocrText.isEmpty
        ? L10n.text(
          "main.ocr.no_text", fallback: "No readable text was found in this image.")
        : item.ocrText
    case .noText:
      L10n.text("main.ocr.no_text", fallback: "No readable text was found in this image.")
    case .failed:
      L10n.text(
        "main.ocr.failed",
        fallback: "Text recognition failed. Re-import or capture the image to try again."
      )
    case .notApplicable: item.text
    }
  }

  @ViewBuilder
  private func contentGlyph(_ item: ClipItem, size: CGFloat) -> some View {
    let analysis = item.contentAnalysis
    ZStack {
      RoundedRectangle(cornerRadius: 9)
        .fill(
          analysis.color.map {
            Color(red: $0.red, green: $0.green, blue: $0.blue, opacity: $0.alpha)
          } ?? actionColor.opacity(0.10)
        )
      if analysis.color == nil {
        Image(systemName: analysis.kind.systemImage)
          .font(.system(size: size * 0.30, weight: .bold))
          .foregroundStyle(actionColor)
      }
    }
    .frame(width: size, height: size)
    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.08)))
  }

  private func concealedGlyph(size: CGFloat) -> some View {
    ZStack {
      RoundedRectangle(cornerRadius: 9)
        .fill(Color.orange.opacity(0.12))
      Image(systemName: "eye.slash.fill")
        .font(.system(size: size * 0.28, weight: .bold))
        .foregroundStyle(Color.orange)
    }
    .frame(width: size, height: size)
    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.orange.opacity(0.22)))
  }

  private func sensitiveContentIsVisible(_ item: ClipItem) -> Bool {
    !item.isConcealed || revealedConcealedIDs.contains(item.id)
  }

  private func concealedContentPanel(_ item: ClipItem) -> some View {
    VStack(spacing: 12) {
      Image(systemName: "eye.slash.fill")
        .font(.system(size: 28, weight: .semibold))
        .foregroundStyle(Color.orange)
      Text(concealedPanelTitle(for: item))
        .font(.system(size: 15, weight: .bold, design: .rounded))
      Text(concealedPanelMessage(for: item))
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      if let errorMessage = concealedAccess.errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(Color.orange)
          .multilineTextAlignment(.center)
      }
      ocrRetryButton(item)
      Button {
        Task {
          let canReveal: Bool
          if store.preferences.authenticateConcealedPreviews {
            canReveal = await concealedAccess.authorize(
              reason: L10n.text(
                "main.detail.reveal_reason", fallback: "Reveal a concealed Clipskein preview")
            )
          } else {
            canReveal = true
          }
          if canReveal { revealedConcealedIDs.insert(item.id) }
        }
      } label: {
        Label(
          concealedAccess.isAuthenticating
            ? L10n.text("main.detail.authenticating", fallback: "Authenticating…")
            : (store.preferences.authenticateConcealedPreviews
              ? (concealedAccess.isAuthorized
                ? L10n.text("main.detail.reveal", fallback: "Reveal Preview")
                : L10n.text("main.detail.authenticate_reveal", fallback: "Authenticate & Reveal"))
              : L10n.text(
                "main.detail.reveal_until_blur", fallback: "Reveal Until Focus Changes")),
          systemImage: store.preferences.authenticateConcealedPreviews ? "touchid" : "eye.fill"
        )
      }
      .buttonStyle(.borderedProminent)
      .disabled(concealedAccess.isAuthenticating)
    }
    .frame(maxWidth: .infinity)
    .padding(28)
    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.20)))
  }

  private func concealedPanelTitle(for item: ClipItem) -> String {
    if item.kind == .files {
      return L10n.text("main.detail.files_concealed", fallback: "File references concealed")
    }
    if item.kind == .image, item.ocrState == .pending {
      return L10n.text(
        "main.detail.checking_screenshot", fallback: "Checking screenshot locally…")
    }
    if item.kind == .image, item.ocrState == .failed {
      return L10n.text("main.detail.preview_kept_concealed", fallback: "Preview kept concealed")
    }
    return L10n.text("main.detail.preview_concealed", fallback: "Preview concealed")
  }

  @ViewBuilder
  private func ocrRetryButton(_ item: ClipItem) -> some View {
    if item.needsOCRReview {
      Button {
        _ = store.retryOCR(item)
      } label: {
        Label(
          L10n.text("main.detail.retry_ocr", fallback: "Retry Text Recognition"),
          systemImage: "arrow.clockwise"
        )
      }
      .buttonStyle(.bordered)
      .help(
        L10n.text(
          "main.detail.retry_ocr_help",
          fallback: "Run on-device text recognition again using the stored screenshot"
        )
      )
    }
  }

  private func fileReferencePanel(_ item: ClipItem) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(L10n.text("main.detail.referenced_files", fallback: "REFERENCED FILES"))
          .font(.system(size: 10, weight: .black, design: .monospaced))
          .tracking(1.1)
        Spacer()
        Text(
          L10n.text(
            "main.detail.file_locations_only",
            fallback: "Locations only · file contents are not stored"
          )
        )
        .font(.system(size: 10, weight: .medium))
        Button {
          store.refreshFileReferenceAvailability(for: item, force: true)
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.borderless)
        .help(
          L10n.text(
            "main.detail.refresh_file_status",
            fallback: "Refresh referenced-file status"
          )
        )
      }
      .foregroundStyle(.secondary)

      ForEach(item.filePaths, id: \.self) { path in
        let status = store.fileReferenceStatus(for: path, in: item)
        HStack(spacing: 10) {
          Image(systemName: status == .missing ? "doc.badge.ellipsis" : "doc.fill")
            .font(.system(size: 23, weight: .regular))
            .foregroundStyle(status == .missing ? Color.orange : actionColor)
            .frame(width: 30, height: 30)
            .opacity(status == .checking ? 0.5 : 1)
          VStack(alignment: .leading, spacing: 2) {
            Text(URL(fileURLWithPath: path).lastPathComponent)
              .font(.system(size: 12, weight: .semibold, design: .rounded))
              .lineLimit(1)
            Text(path)
              .font(.system(size: 9, design: .monospaced))
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .textSelection(.enabled)
          }
          Spacer()
          switch status {
          case .available:
            Button {
              _ = FileQuickLookController.shared.preview([URL(fileURLWithPath: path)])
            } label: {
              Image(systemName: "eye")
            }
            .buttonStyle(.borderless)
            .help(L10n.text("main.detail.quick_look", fallback: "Quick Look"))
            Button {
              NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            } label: {
              Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help(L10n.text("main.detail.show_finder", fallback: "Show in Finder"))
          case .missing:
            VStack(alignment: .trailing, spacing: 5) {
              Label(
                L10n.text("main.detail.missing", fallback: "Missing"),
                systemImage: "exclamationmark.triangle.fill"
              )
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(Color.orange)
              Button(L10n.text("main.detail.relink", fallback: "Locate…")) {
                locateMissingFile(in: item, path: path)
              }
              .buttonStyle(.borderless)
              .font(.system(size: 10, weight: .bold))
              .help(
                L10n.text(
                  "main.detail.relink_help",
                  fallback: "Replace only this missing reference and keep the clip's metadata"
                )
              )
            }
          case .checking:
            VStack(alignment: .trailing, spacing: 4) {
              ProgressView()
                .controlSize(.small)
              Text(L10n.text("main.detail.checking_file", fallback: "Checking…"))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            }
          }
        }
        .padding(10)
        .background(BrandTheme.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.06)))
      }
    }
  }

  private func locateMissingFile(in item: ClipItem, path: String) {
    let panel = NSOpenPanel()
    panel.title = L10n.text("file_relink.title", fallback: "Locate Moved File")
    panel.message = L10n.format(
      "file_relink.message",
      fallback:
        "Choose the new location for %@. Clipskein will keep the rest of this group unchanged.",
      URL(fileURLWithPath: path).lastPathComponent
    )
    panel.prompt = L10n.text("file_relink.choose", fallback: "Use This Location")
    panel.canChooseFiles = true
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
    if FileManager.default.fileExists(atPath: parent.path) { panel.directoryURL = parent }
    guard panel.runModal() == .OK, let replacement = panel.url else { return }
    store.relinkFileReference(in: item, missingPath: path, to: replacement)
  }

  private func concealedPanelMessage(for item: ClipItem) -> String {
    if item.kind == .files {
      return L10n.text(
        "main.detail.files_concealed_detail",
        fallback: "The referenced file names and locations stay hidden until you reveal them."
      )
    }
    if item.kind == .image, item.ocrState == .pending {
      return L10n.text(
        "main.detail.checking_screenshot_detail",
        fallback:
          "The preview stays hidden until on-device text recognition finishes checking it."
      )
    }
    if item.kind == .image, item.ocrState == .failed {
      return L10n.text(
        "main.detail.preview_unverified_detail",
        fallback:
          "Text recognition could not verify this screenshot. You can still reveal it explicitly."
      )
    }
    return L10n.text(
      "main.detail.preview_concealed_detail",
      fallback: "Clipskein detected potentially sensitive text or you concealed this clip manually."
    )
  }

  private func displayedContent(for item: ClipItem) -> String {
    switch item.kind {
    case .text: return item.contentAnalysis.formattedText ?? item.text
    case .image: return ocrDescription(for: item)
    case .files: return item.filePaths.joined(separator: "\n")
    }
  }

  private func editableContent(for item: ClipItem) -> String {
    switch item.kind {
    case .text: item.text
    case .image: item.ocrText
    case .files: ""
    }
  }

  private func textTransformations(for item: ClipItem) -> [TextTransformation] {
    let source =
      switch item.kind {
      case .text: item.text
      case .image: item.ocrText
      case .files: ""
      }
    return TextTransformer.availableTransformations(for: source)
  }

  @ViewBuilder
  private func localIntelligenceSection(for item: ClipItem) -> some View {
    let input = localIntelligenceInput(for: item)
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(
          L10n.text("main.detail.on_device_intelligence", fallback: "ON-DEVICE INTELLIGENCE")
        )
        .font(.system(size: 10, weight: .black, design: .monospaced))
        .tracking(1.1)
        Spacer()
        Label(
          L10n.text("main.detail.stays_local", fallback: "Stays on this Mac"),
          systemImage: "lock.fill"
        )
        .font(.system(size: 10, weight: .medium))
      }
      .foregroundStyle(.secondary)

      switch localIntelligence.availability {
      case .available:
        if input.count > LocalIntelligenceService.maximumInputLength {
          Label(
            L10n.text(
              "main.detail.intelligence_too_long",
              fallback: "This clip is too long for a reliable local transformation."
            ),
            systemImage: "text.badge.xmark"
          )
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.secondary)
          .padding(12)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(BrandTheme.surface.opacity(0.58), in: RoundedRectangle(cornerRadius: 10))
        } else {
          localIntelligenceActions(for: item, input: input)
          localIntelligenceState(for: item)
        }

      case .unavailable(let title, let detail):
        HStack(alignment: .top, spacing: 10) {
          Image(systemName: "apple.intelligence")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(actionColor)
          VStack(alignment: .leading, spacing: 3) {
            Text(title)
              .font(.system(size: 12, weight: .bold))
            Text(detail)
              .font(.system(size: 11))
              .foregroundStyle(.secondary)
          }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandTheme.surface.opacity(0.58), in: RoundedRectangle(cornerRadius: 10))
      }
    }
  }

  private func localIntelligenceActions(for item: ClipItem, input: String) -> some View {
    let actions =
      input.count >= 120
      ? LocalIntelligenceAction.allCases
      : LocalIntelligenceAction.allCases.filter { $0 != .summarize }
    return LazyVGrid(
      columns: [GridItem(.adaptive(minimum: 145), spacing: 8)],
      alignment: .leading,
      spacing: 8
    ) {
      ForEach(actions) { action in
        Button {
          if action == .custom {
            customInstructionItem = item
          } else {
            localIntelligence.generate(action: action, input: input)
          }
        } label: {
          Label(action.label, systemImage: action.systemImage)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .disabled(isLocalIntelligenceGenerating)
      }
    }
  }

  @ViewBuilder
  private func localIntelligenceState(for item: ClipItem) -> some View {
    switch localIntelligence.state {
    case .idle:
      EmptyView()

    case .generating(let action):
      HStack(spacing: 10) {
        ProgressView()
          .controlSize(.small)
        Text(
          L10n.format(
            "main.detail.running_locally", fallback: "%@ on this Mac…", action.label)
        )
        .font(.system(size: 12, weight: .semibold))
        Spacer()
        Button(L10n.text("main.detail.cancel", fallback: "Cancel")) {
          localIntelligence.cancel()
        }
        .buttonStyle(.plain)
        .foregroundStyle(actionColor)
      }
      .padding(12)
      .background(actionColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

    case .result(let action, let result):
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Label(action.label, systemImage: "checkmark.circle.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.green)
          Spacer()
          Button(L10n.text("main.detail.dismiss", fallback: "Dismiss")) {
            localIntelligence.reset()
          }
          .buttonStyle(.plain)
          .font(.system(size: 10, weight: .semibold))
        }
        Text(result)
          .font(.system(size: 13, design: .rounded))
          .textSelection(.enabled)
          .lineLimit(12)
          .frame(maxWidth: .infinity, alignment: .leading)
        HStack {
          Button {
            guard copyText(result, from: item) else { return }
            store.reportNotice(
              L10n.text("main.detail.local_result_copied", fallback: "Local result copied"),
              systemImage: "checkmark.circle.fill"
            )
          } label: {
            Label(
              L10n.text("main.detail.copy_result", fallback: "Copy result"),
              systemImage: item.isConcealed ? "timer" : "doc.on.doc"
            )
          }
          Button {
            store.addText(
              result,
              source: L10n.text(
                "generated.source.intelligence", fallback: "Clipskein Local Intelligence"),
              isConcealed: item.isConcealed,
              customTitle: L10n.format(
                "generated.title.intelligence", fallback: "%@ result", action.label),
              tags: item.tags,
              boardIDs: item.boardIDs
            )
            localIntelligence.reset()
          } label: {
            Label(
              L10n.text("main.detail.save_new_clip", fallback: "Save as new clip"),
              systemImage: "plus.square.on.square"
            )
          }
        }
        .buttonStyle(.bordered)
      }
      .padding(12)
      .background(BrandTheme.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
      .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.07)))

    case .failed(let message):
      HStack(alignment: .top, spacing: 9) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(Color.orange)
        Text(message)
          .font(.system(size: 11, weight: .medium))
        Spacer()
        Button(L10n.text("main.detail.dismiss", fallback: "Dismiss")) {
          localIntelligence.reset()
        }
        .buttonStyle(.plain)
        .foregroundStyle(actionColor)
      }
      .padding(12)
      .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
    }
  }

  private var isLocalIntelligenceGenerating: Bool {
    if case .generating = localIntelligence.state { return true }
    return false
  }

  private func localIntelligenceInput(for item: ClipItem) -> String {
    let input =
      switch item.kind {
      case .text: item.text
      case .image: item.ocrText
      case .files: ""
      }
    return input.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  @ViewBuilder
  private func localTranslationSection(for item: ClipItem) -> some View {
    let input = localIntelligenceInput(for: item)
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(L10n.text("main.detail.local_translation", fallback: "LOCAL TRANSLATION"))
          .font(.system(size: 10, weight: .black, design: .monospaced))
          .tracking(1.1)
        Spacer()
        Label(
          L10n.text("main.detail.language_packs", fallback: "macOS language packs"),
          systemImage: "character.bubble.fill"
        )
        .font(.system(size: 10, weight: .medium))
      }
      .foregroundStyle(.secondary)

      if !localTranslation.isAvailable {
        Label(
          L10n.text(
            "main.detail.translation_requires_15",
            fallback: "Local translation requires macOS 15 or later."
          ),
          systemImage: "globe"
        )
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandTheme.surface.opacity(0.58), in: RoundedRectangle(cornerRadius: 10))
      } else if input.count > LocalTranslationController.maximumInputLength {
        Label(
          L10n.text(
            "main.detail.translation_too_long",
            fallback: "This clip is too long for a reliable local translation."
          ),
          systemImage: "text.badge.xmark"
        )
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandTheme.surface.opacity(0.58), in: RoundedRectangle(cornerRadius: 10))
      } else {
        HStack(spacing: 10) {
          Text(L10n.text("main.detail.translate_to", fallback: "Translate to"))
            .font(.system(size: 12, weight: .semibold))
          Picker(
            L10n.text("main.detail.translate_to", fallback: "Translate to"),
            selection: $translationTarget
          ) {
            ForEach(LocalTranslationTarget.common) { target in
              Text(target.displayName).tag(target)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(maxWidth: 240)
          .disabled(isLocalTranslationActive)

          Spacer()

          if case .idle = localTranslation.state {
            Button {
              localTranslation.request(text: input, target: translationTarget)
            } label: {
              Label(
                L10n.text("main.detail.translate", fallback: "Translate"),
                systemImage: "character.bubble"
              )
            }
            .buttonStyle(.borderedProminent)
          }
        }

        localTranslationState(for: item, input: input)
      }
    }
  }

  @ViewBuilder
  private func localTranslationState(for item: ClipItem, input: String) -> some View {
    switch localTranslation.state {
    case .idle:
      Text(
        L10n.text(
          "main.detail.translation_auto_detect",
          fallback:
            "Source language is detected automatically. macOS may ask before downloading a pack."
        )
      )
      .font(.system(size: 10, weight: .medium))
      .foregroundStyle(.secondary)

    case .checking(let target):
      translationProgress(
        title: L10n.text(
          "main.detail.translation_detecting", fallback: "Detecting source language…"),
        detail: L10n.format(
          "main.detail.translation_checking", fallback: "Checking support for %@.",
          target.displayName)
      )

    case .preparing(let target):
      translationProgress(
        title: L10n.format(
          "main.detail.translation_preparing", fallback: "Preparing %@…", target.name),
        detail: L10n.text(
          "main.detail.translation_approve_download",
          fallback: "Approve the macOS language download if prompted."
        )
      )

    case .translating(let target):
      translationProgress(
        title: L10n.format(
          "main.detail.translation_running", fallback: "Translating to %@…", target.name),
        detail: L10n.text(
          "main.detail.translation_running_local",
          fallback: "Translation is running locally on this Mac."
        )
      )

    case .result(let target, let result):
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Label(target.displayName, systemImage: "checkmark.circle.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.green)
          Spacer()
          Button(L10n.text("main.detail.dismiss", fallback: "Dismiss")) {
            localTranslation.reset()
          }
          .buttonStyle(.plain)
          .font(.system(size: 10, weight: .semibold))
        }
        Text(result)
          .font(.system(size: 13, design: .rounded))
          .textSelection(.enabled)
          .lineLimit(12)
          .frame(maxWidth: .infinity, alignment: .leading)
        HStack {
          Button {
            guard copyText(result, from: item) else { return }
            store.reportNotice(
              L10n.text("main.detail.translation_copied", fallback: "Translation copied"),
              systemImage: "checkmark.circle.fill"
            )
          } label: {
            Label(
              L10n.text("main.detail.copy_translation", fallback: "Copy translation"),
              systemImage: item.isConcealed ? "timer" : "doc.on.doc"
            )
          }
          Button {
            store.addText(
              result,
              source: L10n.text(
                "generated.source.translation", fallback: "Clipskein Local Translation"),
              isConcealed: item.isConcealed,
              customTitle: L10n.format(
                "generated.title.translation", fallback: "Translated to %@", target.displayName),
              tags: item.tags,
              boardIDs: item.boardIDs
            )
            localTranslation.reset()
          } label: {
            Label(
              L10n.text("main.detail.save_new_clip", fallback: "Save as new clip"),
              systemImage: "plus.square.on.square"
            )
          }
        }
        .buttonStyle(.bordered)
      }
      .padding(12)
      .background(BrandTheme.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
      .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.07)))

    case .failed(let message):
      HStack(alignment: .top, spacing: 9) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(Color.orange)
        VStack(alignment: .leading, spacing: 5) {
          Text(message)
            .font(.system(size: 11, weight: .medium))
          Button(L10n.text("main.detail.try_again", fallback: "Try again")) {
            localTranslation.request(text: input, target: translationTarget)
          }
          .buttonStyle(.plain)
          .foregroundStyle(actionColor)
        }
        Spacer()
        Button(L10n.text("main.detail.dismiss", fallback: "Dismiss")) {
          localTranslation.reset()
        }
        .buttonStyle(.plain)
        .foregroundStyle(actionColor)
      }
      .padding(12)
      .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
    }
  }

  private func translationProgress(title: String, detail: String) -> some View {
    HStack(spacing: 10) {
      ProgressView()
        .controlSize(.small)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 12, weight: .semibold))
        Text(detail)
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button(L10n.text("main.detail.cancel", fallback: "Cancel")) {
        localTranslation.cancel()
      }
      .buttonStyle(.plain)
      .foregroundStyle(actionColor)
    }
    .padding(12)
    .background(actionColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
  }

  private var isLocalTranslationActive: Bool {
    switch localTranslation.state {
    case .checking, .preparing, .translating:
      true
    case .idle, .result, .failed:
      false
    }
  }

  private func copyTransformation(_ transformation: TextTransformation, from item: ClipItem) {
    guard copyText(transformation.result, from: item) else { return }
    let copyID = transformationCopyID(transformation, from: item)
    copiedTransformationID = copyID
    store.reportNotice(
      L10n.format(
        "notice.transformation_copied", fallback: "%@ copied", transformation.label),
      systemImage: "checkmark.circle.fill"
    )
    Task {
      try? await Task.sleep(for: .seconds(1.2))
      if copiedTransformationID == copyID { copiedTransformationID = nil }
    }
  }

  @ViewBuilder
  private func contentPanel(for item: ClipItem) -> some View {
    let content = displayedContent(for: item)
    let markdown = item.kind == .text ? MarkdownDocument.parse(content) : nil
    let pasteActions = item.kind == .image ? store.quickPasteActions(for: item) : []

    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        Text(
          item.kind == .image
            ? L10n.text("main.detail.recognized_text", fallback: "RECOGNIZED TEXT")
            : (markdown == nil
              ? L10n.text("main.detail.content", fallback: "CONTENT")
              : L10n.text("main.detail.markdown", fallback: "MARKDOWN"))
        )
        .font(.system(size: 10, weight: .black, design: .monospaced))
        .tracking(1.1)
        .foregroundStyle(.secondary)

        Spacer()

        if store.isPreparingQuickPasteActions(for: item) {
          ProgressView()
            .controlSize(.small)
            .help(
              L10n.text(
                "quick_paste.preparing_actions",
                fallback: "Preparing local actions…"
              )
            )
        }

        if item.kind == .image,
          let action = detailSearchMatchAction(for: item, pasteActions: pasteActions)
        {
          Button {
            copySearchMatch(action, from: item)
          } label: {
            Label(
              copiedTransformationID == searchMatchCopyID(action, item)
                ? L10n.text("main.detail.copied", fallback: "Copied")
                : L10n.text(
                  "main.detail.copy_search_match",
                  fallback: "Copy search match"
                ),
              systemImage: copiedTransformationID == searchMatchCopyID(action, item)
                ? "checkmark.circle.fill" : action.systemImage
            )
          }
          .buttonStyle(.plain)
          .foregroundStyle(actionColor)
          .help(
            L10n.format(
              "main.detail.copy_search_match_help",
              fallback: "Copy %@",
              QuickPasteActionBuilder.compactPreview(action.text)
            )
          )
        }

        if markdown != nil {
          Picker(
            L10n.text("main.detail.markdown_display", fallback: "Markdown display"),
            selection: $showingMarkdownSource
          ) {
            Text(L10n.text("main.detail.preview", fallback: "Preview")).tag(false)
            Text(L10n.text("main.detail.source", fallback: "Source")).tag(true)
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .frame(width: 150)
        }
      }

      if let markdown {
        if showingMarkdownSource {
          Text(content)
            .font(.system(size: 14, weight: .regular, design: .monospaced))
            .textSelection(.enabled)
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
          MarkdownPreviewView(document: markdown)
            .padding(16)
            .background(BrandTheme.surface.opacity(0.66), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.06)))
        }

        HStack(spacing: 8) {
          Label(
            showingMarkdownSource
              ? L10n.text(
                "main.detail.markdown_source_unchanged", fallback: "Original source unchanged")
              : L10n.text("main.detail.markdown_local", fallback: "Rendered locally"),
            systemImage: showingMarkdownSource ? "doc.plaintext" : "lock.shield"
          )
          Spacer()
          Button {
            copyMarkdownPlainText(markdown, from: item)
          } label: {
            Label(
              copiedTransformationID == markdownPlainTextCopyID(item)
                ? L10n.text("main.detail.copied", fallback: "Copied")
                : L10n.text(
                  "main.detail.copy_markdown_plain", fallback: "Copy plain text"),
              systemImage: copiedTransformationID == markdownPlainTextCopyID(item)
                ? "checkmark.circle.fill" : "doc.on.doc"
            )
          }
          .buttonStyle(.plain)
          .foregroundStyle(actionColor)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
      } else {
        Text(content)
          .font(
            .system(
              size: 16,
              weight: .regular,
              design: usesMonospacedContent(item) ? .monospaced : .rounded
            )
          )
          .textSelection(.enabled)
          .lineSpacing(5)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      ocrRetryButton(item)
    }
  }

  private func copyMarkdownPlainText(_ markdown: MarkdownDocument, from item: ClipItem) {
    guard copyText(markdown.plainText, from: item) else { return }
    let copyID = markdownPlainTextCopyID(item)
    copiedTransformationID = copyID
    store.reportNotice(
      L10n.text("notice.markdown_plain_copied", fallback: "Markdown copied as plain text"),
      systemImage: "checkmark.circle.fill"
    )
    Task {
      try? await Task.sleep(for: .seconds(1.2))
      if copiedTransformationID == copyID { copiedTransformationID = nil }
    }
  }

  private func markdownPlainTextCopyID(_ item: ClipItem) -> String {
    "\(item.id.uuidString):markdownPlainText"
  }

  @ViewBuilder
  private func barcodeSection(for item: ClipItem) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(L10n.text("main.detail.detected_codes", fallback: "DETECTED CODES"))
          .font(.system(size: 10, weight: .black, design: .monospaced))
          .tracking(1.1)
        Spacer()
        Label(
          L10n.text("main.detail.codes_local", fallback: "Read locally with Vision"),
          systemImage: "lock.shield"
        )
        .font(.system(size: 10, weight: .medium))
      }
      .foregroundStyle(.secondary)

      ForEach(item.detectedBarcodes, id: \.self) { barcode in
        HStack(spacing: 10) {
          Image(systemName: barcode.isQRCode ? "qrcode" : "barcode")
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(actionColor)
            .frame(width: 24)
          VStack(alignment: .leading, spacing: 3) {
            Text(barcode.localizedKind)
              .font(.system(size: 9, weight: .bold))
              .foregroundStyle(.secondary)
            Text(barcode.payload)
              .font(.system(size: 12, weight: .semibold, design: .rounded))
              .lineLimit(2)
              .textSelection(.enabled)
          }
          Spacer(minLength: 4)
          if let url = barcode.webURL {
            Button {
              NSWorkspace.shared.open(url)
            } label: {
              Label(
                L10n.text("main.detail.open_code_link", fallback: "Open"),
                systemImage: "arrow.up.right"
              )
              .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help(L10n.text("main.detail.open_code_link", fallback: "Open"))
          }
          Button {
            copyBarcode(barcode, from: item)
          } label: {
            Label(
              copiedExtractionID == barcodeCopyID(barcode, item: item)
                ? L10n.text("main.detail.copied", fallback: "Copied")
                : L10n.text("main.detail.copy_code", fallback: "Copy"),
              systemImage: copiedExtractionID == barcodeCopyID(barcode, item: item)
                ? "checkmark.circle.fill" : "doc.on.doc"
            )
          }
          .buttonStyle(.bordered)
        }
        .padding(11)
        .background(BrandTheme.surface.opacity(0.68), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.07)))
      }
    }
  }

  private func copyBarcode(_ barcode: DetectedBarcode, from item: ClipItem) {
    guard copyText(barcode.payload, from: item) else { return }
    let copyID = barcodeCopyID(barcode, item: item)
    copiedExtractionID = copyID
    store.reportNotice(
      L10n.format("notice.barcode_copied", fallback: "%@ copied", barcode.localizedKind),
      systemImage: "checkmark.circle.fill"
    )
    Task {
      try? await Task.sleep(for: .seconds(1.2))
      if copiedExtractionID == copyID { copiedExtractionID = nil }
    }
  }

  private func barcodeCopyID(_ barcode: DetectedBarcode, item: ClipItem) -> String {
    "\(item.id.uuidString):\(barcode.symbology):\(barcode.payload)"
  }

  private func tableActions(for item: ClipItem) -> [QuickPasteAction] {
    store.quickPasteActions(for: item).filter {
      [.tableMarkdown, .tableJSON, .tableHTML].contains($0.kind)
    }
  }

  private func copyFormattedAction(_ action: QuickPasteAction, from item: ClipItem) {
    guard copyText(action.text, from: item) else { return }
    let copyID = formattedActionCopyID(action, item)
    copiedTransformationID = copyID
    store.reportNotice(
      L10n.text("notice.table_format_copied", fallback: "Table format copied"),
      systemImage: "checkmark.circle.fill"
    )
    Task {
      try? await Task.sleep(for: .seconds(1.2))
      if copiedTransformationID == copyID { copiedTransformationID = nil }
    }
  }

  private func structuredExtractionActions(for item: ClipItem) -> [QuickPasteAction] {
    store.quickPasteActions(for: item).filter {
      $0.kind == .extractedJSON || $0.kind == .extractedTSV
    }
  }

  private func structuredExtractionCopyLabel(_ action: QuickPasteAction) -> String {
    switch action.kind {
    case .extractedJSON:
      L10n.text("main.detail.copy_extracted_json", fallback: "Copy JSON")
    case .extractedTSV:
      L10n.text("main.detail.copy_extracted_tsv", fallback: "Copy table")
    default:
      action.label
    }
  }

  private func copyStructuredExtraction(_ action: QuickPasteAction, from item: ClipItem) {
    guard copyText(action.text, from: item) else { return }
    let copyID = formattedActionCopyID(action, item)
    copiedTransformationID = copyID
    store.reportNotice(
      action.kind == .extractedTSV
        ? L10n.text("notice.extracted_tsv_copied", fallback: "Extracted details copied as a table")
        : L10n.text("notice.extracted_json_copied", fallback: "Extracted details copied as JSON"),
      systemImage: "checkmark.circle.fill"
    )
    Task {
      try? await Task.sleep(for: .seconds(1.2))
      if copiedTransformationID == copyID { copiedTransformationID = nil }
    }
  }

  private func detailSearchMatchAction(
    for item: ClipItem,
    pasteActions: [QuickPasteAction]
  ) -> QuickPasteAction? {
    let freeText: String
    if !store.searchAsLiteral, let interpretation = store.currentSearchInterpretation {
      freeText = interpretation.remainingQuery
    } else {
      freeText = store.searchText
    }
    let parsed = ClipSearchQuery(freeText, interpretNaturalLanguage: false)
    guard case .inactive = parsed.regexStatus else { return nil }
    return QuickPasteActionBuilder.matchedContextAction(
      in: pasteActions,
      for: item,
      matching: parsed.matcher.query
    )
  }

  private func copySearchMatch(_ action: QuickPasteAction, from item: ClipItem) {
    guard copyText(action.text, from: item) else { return }
    let copyID = searchMatchCopyID(action, item)
    copiedTransformationID = copyID
    store.reportNotice(
      L10n.text("notice.search_match_copied", fallback: "Search match copied"),
      systemImage: "checkmark.circle.fill"
    )
    Task {
      try? await Task.sleep(for: .seconds(1.2))
      if copiedTransformationID == copyID { copiedTransformationID = nil }
    }
  }

  private func searchMatchCopyID(_ action: QuickPasteAction, _ item: ClipItem) -> String {
    "\(item.id.uuidString):search-match:\(action.text)"
  }

  private func formattedActionCopyID(_ action: QuickPasteAction, _ item: ClipItem) -> String {
    "\(item.id.uuidString):\(action.kind.rawValue)"
  }

  private func transformationCopyID(
    _ transformation: TextTransformation,
    from item: ClipItem
  ) -> String {
    "\(item.id.uuidString):\(transformation.id)"
  }

  private func usesMonospacedContent(_ item: ClipItem) -> Bool {
    [.code, .json].contains(item.contentAnalysis.kind)
  }

  private func actionableExtractedValues(for item: ClipItem) -> [ExtractedValue] {
    let completeText = displayedContent(for: item)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return item.extractedValues.filter { $0.value != completeText }
  }

  private func copyExtractedValue(_ extracted: ExtractedValue, from item: ClipItem) {
    guard copyText(extracted.value, from: item) else { return }
    copiedExtractionID = extracted.id
    Task {
      try? await Task.sleep(for: .seconds(1.2))
      if copiedExtractionID == extracted.id { copiedExtractionID = nil }
    }
  }

  private func markCopied(_ item: ClipItem, action: () -> Bool) {
    guard action() else { return }
    showCopiedFeedback(for: item)
  }

  private func showCopiedFeedback(for item: ClipItem) {
    copiedID = item.id
    Task {
      try? await Task.sleep(for: .seconds(1.2))
      if copiedID == item.id { copiedID = nil }
    }
  }

  private func beginTemplateCopy(_ item: ClipItem) {
    guard ClipTemplate.isEligible(item) else { return }
    let template = ClipTemplate(item.text)
    if template.fields.isEmpty {
      markCopied(item) { copyText(template.render(), from: item) }
    } else {
      templateItem = item
    }
  }

  private func copyText(_ text: String, from item: ClipItem) -> Bool {
    item.isConcealed
      ? store.secureCopyText(text, recording: item)
      : store.copyText(text, recording: item)
  }
}
