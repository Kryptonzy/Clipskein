import AppKit
import SwiftUI

@MainActor
final class QuickPanelController {
  private let panel: QuickPanel
  private let store: ClipStore
  private let pasteCoordinator = QuickPasteCoordinator()
  private var textActionRequestID: UUID?

  init(store: ClipStore) {
    self.store = store
    panel = QuickPanel(
      contentRect: NSRect(x: 0, y: 0, width: 570, height: 440),
      styleMask: [.borderless, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    panel.level = .floating
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.isMovableByWindowBackground = true
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.onOrderOut = { [weak store] in
      store?.cancelImageCopyPreparation()
    }
    panel.onApplicationDeactivate = { [weak self] in
      self?.dismiss()
    }
  }

  func toggle(initialQuery: String = "") {
    if panel.isVisible {
      dismiss()
    } else {
      show(initialQuery: initialQuery)
    }
  }

  func show(initialQuery: String = "") {
    if panel.isVisible { store.cancelImageCopyPreparation() }
    pasteCoordinator.captureTargetApplication()
    panel.onTab = nil
    panel.onPreview = {
      NotificationCenter.default.post(name: .previewQuickPanelSelection, object: nil)
    }
    panel.contentView = NSHostingView(
      rootView: QuickPickerView(
        store: store,
        pasteCoordinator: pasteCoordinator,
        initialQuery: initialQuery
      )
    )
    positionNearPointer()
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
  }

  func showTextActions() {
    if panel.isVisible { store.cancelImageCopyPreparation() }
    pasteCoordinator.captureTargetApplication()
    panel.onPreview = nil
    let requestID = UUID()
    textActionRequestID = requestID
    let targetApplication = pasteCoordinator.targetApplication
    Task { @MainActor [weak self] in
      guard let self else { return }
      let captureResult = await store.captureSelectedText(from: targetApplication)
      guard textActionRequestID == requestID else { return }
      presentTextActions(captureResult: captureResult)
    }
  }

  private func presentTextActions(captureResult: SelectedTextCaptureResult) {
    panel.onTab = { reversed in
      NotificationCenter.default.post(
        name: .cycleTextActionSource,
        object: reversed ? -1 : 1
      )
    }
    panel.contentView = NSHostingView(
      rootView: TextActionPickerView(
        store: store,
        pasteCoordinator: pasteCoordinator,
        captureResult: captureResult
      )
    )
    positionNearPointer()
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
  }

  func dismiss() {
    textActionRequestID = nil
    store.cancelImageCopyPreparation()
    panel.onTab = nil
    panel.onPreview = nil
    panel.orderOut(nil)
    pasteCoordinator.restoreTargetApplication()
  }

  func suspendForPrivacy() {
    textActionRequestID = nil
    store.cancelImageCopyPreparation()
    panel.onTab = nil
    panel.onPreview = nil
    panel.orderOut(nil)
    panel.contentView = nil
    pasteCoordinator.suspendForPrivacy()
  }

  func recoverAfterPasteFailure() {
    positionNearPointer()
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
  }

  private func positionNearPointer() {
    let mouse = NSEvent.mouseLocation
    let screen =
      NSScreen.screens.first { NSMouseInRect(mouse, $0.visibleFrame, false) }
      ?? NSScreen.main
    guard let frame = screen?.visibleFrame else {
      panel.center()
      return
    }
    let size = panel.frame.size
    let preferredX = mouse.x - size.width / 2
    let preferredY = mouse.y - size.height - 24
    let x = min(max(preferredX, frame.minX + 12), frame.maxX - size.width - 12)
    let y = min(max(preferredY, frame.minY + 12), frame.maxY - size.height - 12)
    panel.setFrameOrigin(NSPoint(x: x, y: y))
  }
}

enum QuickPanelKeyboardAction: Equatable {
  case cycleSource(reverse: Bool)
  case moveSelection(Int)
  case useExtractedValue
  case previewSelection
  case passThrough
}

enum QuickPanelDeactivationPolicy {
  static func shouldDismiss(
    isPanelVisible: Bool,
    activatedProcessIdentifier: pid_t,
    currentProcessIdentifier: pid_t
  ) -> Bool {
    isPanelVisible && activatedProcessIdentifier != currentProcessIdentifier
  }
}

enum QuickPanelKeyboardRouter {
  static func action(
    keyCode: UInt16,
    modifiers: NSEvent.ModifierFlags,
    hasTabHandler: Bool,
    hasAttachedSheet: Bool,
    hasPreviewHandler: Bool = false,
    isComposingText: Bool = false
  ) -> QuickPanelKeyboardAction {
    guard !hasAttachedSheet, !isComposingText else { return .passThrough }
    let semanticModifiers = modifiers.intersection([.command, .control, .option, .shift])

    if keyCode == 48, hasTabHandler,
      semanticModifiers.isEmpty || semanticModifiers == .shift
    {
      return .cycleSource(reverse: semanticModifiers.contains(.shift))
    }
    if keyCode == 125 || keyCode == 126, semanticModifiers.isEmpty {
      return .moveSelection(keyCode == 125 ? 1 : -1)
    }
    if keyCode == 36 || keyCode == 76, semanticModifiers == .control {
      return .useExtractedValue
    }
    if keyCode == 16, semanticModifiers == .command, hasPreviewHandler {
      return .previewSelection
    }
    return .passThrough
  }
}

private final class QuickPanel: NSPanel {
  var onTab: ((Bool) -> Void)?
  var onPreview: (() -> Void)?
  var onOrderOut: (() -> Void)?
  var onApplicationDeactivate: (() -> Void)?
  override var canBecomeKey: Bool { true }

  override init(
    contentRect: NSRect,
    styleMask style: NSWindow.StyleMask,
    backing backingStoreType: NSWindow.BackingStoreType,
    defer flag: Bool
  ) {
    super.init(
      contentRect: contentRect,
      styleMask: style,
      backing: backingStoreType,
      defer: flag
    )
    NSWorkspace.shared.notificationCenter.addObserver(
      self,
      selector: #selector(frontmostApplicationDidChange(_:)),
      name: NSWorkspace.didActivateApplicationNotification,
      object: nil
    )
  }

  deinit {
    NSWorkspace.shared.notificationCenter.removeObserver(self)
  }

  @objc private func frontmostApplicationDidChange(_ notification: Notification) {
    guard
      let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
        as? NSRunningApplication,
      QuickPanelDeactivationPolicy.shouldDismiss(
        isPanelVisible: isVisible,
        activatedProcessIdentifier: application.processIdentifier,
        currentProcessIdentifier: ProcessInfo.processInfo.processIdentifier
      )
    else { return }
    onApplicationDeactivate?()
  }

  override func orderOut(_ sender: Any?) {
    onOrderOut?()
    super.orderOut(sender)
  }

  override func sendEvent(_ event: NSEvent) {
    if event.type == .keyDown {
      switch QuickPanelKeyboardRouter.action(
        keyCode: event.keyCode,
        modifiers: event.modifierFlags,
        hasTabHandler: onTab != nil,
        hasAttachedSheet: attachedSheet != nil,
        hasPreviewHandler: onPreview != nil,
        isComposingText: hasMarkedTextInput
      ) {
      case .cycleSource(let reverse):
        onTab?(reverse)
        return
      case .moveSelection(let direction):
        NotificationCenter.default.post(
          name: .moveQuickPanelSelection,
          object: direction
        )
        return
      case .useExtractedValue:
        NotificationCenter.default.post(name: .useQuickPanelExtractedValue, object: nil)
        return
      case .previewSelection:
        onPreview?()
        return
      case .passThrough:
        break
      }
    }
    super.sendEvent(event)
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    // SwiftUI implements hidden Return shortcuts as window key equivalents. While an input
    // method owns marked text, those keystrokes must reach its candidate editor first.
    guard !hasMarkedTextInput else { return false }
    return super.performKeyEquivalent(with: event)
  }

  private var hasMarkedTextInput: Bool {
    guard let textInput = firstResponder as? NSTextInputClient else { return false }
    return textInput.hasMarkedText()
  }
}

struct QuickPickerView: View {
  @ObservedObject var store: ClipStore
  let pasteCoordinator: QuickPasteCoordinator
  @State private var query: String
  @State private var selectedID: UUID?
  @State private var feedback: QuickPickerFeedback?
  @State private var templateItem: ClipItem?
  @State private var templateCopyOnly = false
  @State private var previewPayload: QuickPickerPreviewPayload?
  @State private var pendingImagePreviewID: UUID?
  @State private var pendingFilePreviewID: UUID?
  @State private var searchAsLiteral = false
  @State private var semanticOriginID: UUID?
  @State private var semanticOriginQueryKey: String?
  @State private var usesAppContext = true
  @FocusState private var searchFocused: Bool

  init(
    store: ClipStore,
    pasteCoordinator: QuickPasteCoordinator,
    initialQuery: String = ""
  ) {
    self.store = store
    self.pasteCoordinator = pasteCoordinator
    _query = State(initialValue: initialQuery)
  }

  private var results: [ClipItem] {
    store.quickPickerItems(
      query: query,
      interpretNaturalLanguage: !searchAsLiteral,
      limit: 8,
      excludingSemanticItemID: semanticOriginID,
      preferredBoardID: activeAppContextBoard?.id
    )
  }

  private var configuredAppContextBoard: ClipBoard? {
    guard let bundleIdentifier = pasteCoordinator.targetApplicationBundleIdentifier,
      let boardID = store.preferences.appContextBoardID(bundleIdentifier: bundleIdentifier)
    else { return nil }
    return store.boards.first { $0.id == boardID }
  }

  private var activeAppContextBoard: ClipBoard? {
    guard usesAppContext,
      query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return nil }
    return configuredAppContextBoard
  }

  private var searchInterpretation: NaturalLanguageSearch? {
    store.quickPickerSearchInterpretation(for: query)
  }

  private var regexStatus: RegexSearchStatus {
    store.quickPickerRegexSearchStatus(for: query)
  }

  private var semanticStatus: SemanticSearchStatus {
    store.semanticSearchStatus(for: query)
  }

  private var semanticCollectionCandidates: [ClipItem] {
    store.semanticCollectionCandidates(from: results, query: query)
  }

  private var contentMatchQuery: String {
    guard !isAliasMode, SemanticSearchRequest(query) == nil else { return "" }
    let freeText = searchInterpretation?.remainingQuery ?? query
    let parsed = ClipSearchQuery(freeText, interpretNaturalLanguage: false)
    if case .active = parsed.regexStatus { return freeText }
    return parsed.matcher.query
  }

  private var isAliasMode: Bool {
    query.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("@")
  }

  private var hasAliases: Bool {
    store.hasQuickAliases
  }

  private var activeSourceApplicationFacets: [SourceApplicationFacet] {
    store.sourceApplicationFacets.filter {
      SearchTokenEditor.contains(sourceApplicationToken(for: $0), in: query)
    }
  }

  private var targetPasteHint: String? {
    guard let targetName = pasteCoordinator.targetApplicationName else { return nil }
    let suffix =
      selectedItem.map {
        pasteCoordinator.usesPlainTextDefault(for: $0, using: store)
          ? " · \(L10n.text("picker.target.plain", fallback: "plain"))" : ""
      } ?? ""
    return "↩ \(targetName)\(suffix)"
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        ClipskeinMark()
          .frame(width: 26, height: 26)
          .accessibilityHidden(true)
        TextField(
          L10n.text("picker.search_placeholder", fallback: "Find anything or type @alias"),
          text: $query
        )
        .textFieldStyle(.plain)
        .font(.system(size: 17, weight: .semibold, design: .rounded))
        .focused($searchFocused)
        if isAliasMode {
          Text(L10n.text("picker.aliases", fallback: "ALIASES"))
            .font(.system(size: 9, weight: .black, design: .monospaced))
            .foregroundStyle(BrandTheme.accentOnDark)
            .padding(.horizontal, 7)
            .frame(height: 23)
            .background(Color.white.opacity(0.08), in: Capsule())
        } else if query.isEmpty, hasAliases {
          Button {
            query = "@"
          } label: {
            Text("@")
              .font(.system(size: 12, weight: .black, design: .monospaced))
              .frame(width: 25, height: 23)
              .background(Color.white.opacity(0.08), in: Capsule())
          }
          .buttonStyle(.plain)
          .help(L10n.text("picker.aliases.help", fallback: "Browse quick aliases"))
          .accessibilityLabel(
            L10n.text("picker.aliases.help", fallback: "Browse quick aliases")
          )
        }
        if query.isEmpty {
          Button {
            query = "~ "
          } label: {
            Image(systemName: "brain.head.profile")
              .font(.system(size: 11, weight: .bold))
              .frame(width: 25, height: 23)
              .background(Color.white.opacity(0.08), in: Capsule())
          }
          .buttonStyle(.plain)
          .help(
            L10n.text(
              "semantic.start.help",
              fallback: "Search by meaning with a private on-device index"
            )
          )
          .accessibilityLabel(L10n.text("semantic.start", fallback: "Search by meaning"))
        }
        if query.isEmpty, let contextBoard = configuredAppContextBoard {
          Button {
            usesAppContext.toggle()
            selectedID = results.first?.id
          } label: {
            Label(
              contextBoard.name,
              systemImage: usesAppContext ? "rectangle.stack.fill" : "rectangle.stack"
            )
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(maxWidth: 112, minHeight: 23)
            .foregroundStyle(
              usesAppContext
                ? BrandTheme.accentOnDark : Color.white.opacity(0.82)
            )
            .background(Color.white.opacity(0.08), in: Capsule())
          }
          .buttonStyle(.plain)
          .help(
            usesAppContext
              ? L10n.format(
                "picker.context.disable",
                fallback: "%@ clips are prioritized for this app. Click to use global ranking.",
                contextBoard.name
              )
              : L10n.format(
                "picker.context.enable",
                fallback: "Prioritize %@ clips for this app",
                contextBoard.name
              )
          )
          .accessibilityLabel(
            L10n.format(
              "picker.context.label",
              fallback: "App context: %@",
              contextBoard.name
            )
          )
        }
        if !store.sourceApplicationFacets.isEmpty, !isAliasMode,
          SemanticSearchRequest(query) == nil
        {
          sourceApplicationFilterMenu
        }
        if !store.stackItems.isEmpty {
          Menu {
            Button {
              useNextStackItem()
            } label: {
              Label(
                L10n.text("picker.stack.next", fallback: "Paste next and advance"),
                systemImage: "arrow.right.circle.fill"
              )
            }
            Button {
              useStack()
            } label: {
              Label(
                L10n.text("picker.stack.all", fallback: "Paste all as paragraphs"),
                systemImage: "doc.on.doc"
              )
            }
          } label: {
            Label("\(store.stackItems.count)", systemImage: "square.stack.3d.up.fill")
              .font(.system(size: 10, weight: .bold, design: .rounded))
              .padding(.horizontal, 8)
              .frame(height: 25)
              .background(Color.white.opacity(0.08), in: Capsule())
          }
          .menuStyle(.borderlessButton)
          .menuIndicator(.hidden)
          .fixedSize()
          .help(
            L10n.text(
              "picker.stack.help", fallback: "Use the Stack as a queue or paste it all"))
          .accessibilityLabel(
            L10n.text(
              "picker.stack.help", fallback: "Use the Stack as a queue or paste it all")
          )
        }
        Text(
          query.isEmpty
            ? "ESC"
            : L10n.text("picker.shortcut.escape_clear", fallback: "ESC CLEAR")
        )
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
      }
      .padding(.horizontal, 18)
      .frame(height: 58)

      if let semanticMessage = semanticStatus.localizedMessage {
        HStack(spacing: 7) {
          Image(systemName: semanticStatus.isPreparing ? "brain.head.profile" : "sparkles")
          Text(semanticMessage)
            .lineLimit(1)
          Spacer(minLength: 4)
          if semanticStatus.canCollectResults, !semanticCollectionCandidates.isEmpty {
            Button {
              collectSemanticResults()
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
          } else {
            Text("~")
              .font(.system(size: 9, weight: .bold, design: .monospaced))
          }
        }
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .foregroundStyle(BrandTheme.accentOnDark)
        .padding(.horizontal, 18)
        .frame(height: 30)
        .background(Color.white.opacity(0.045))
        .accessibilityElement(children: .contain)
      } else if let regexMessage = regexStatus.localizedMessage {
        HStack(spacing: 7) {
          Image(
            systemName: regexStatus.isInvalid
              ? "exclamationmark.triangle.fill" : "textformat.abc.dottedunderline"
          )
          Text(regexMessage)
            .lineLimit(1)
          Spacer(minLength: 4)
          Text("regex:")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
        }
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .foregroundStyle(regexStatus.isInvalid ? Color.orange : Color.white.opacity(0.82))
        .padding(.horizontal, 18)
        .frame(height: 30)
        .background(Color.white.opacity(0.045))
        .accessibilityElement(children: .combine)
      } else if let interpretation = searchInterpretation {
        HStack(spacing: 7) {
          Image(systemName: searchAsLiteral ? "textformat" : "sparkle.magnifyingglass")
          Text(
            searchAsLiteral
              ? L10n.text(
                "search.literal_status", fallback: "Searching those words literally")
              : L10n.format(
                "search.understood",
                fallback: "Understood: %@",
                interpretation.localizedFacetLabels().joined(separator: " · ")
              )
          )
          .lineLimit(1)
          Spacer(minLength: 4)
          Button(
            searchAsLiteral
              ? L10n.text("search.smart", fallback: "Use smart search")
              : L10n.text("search.literal", fallback: "Search literally")
          ) {
            searchAsLiteral.toggle()
            selectedID = results.first?.id
          }
          .buttonStyle(.plain)
          .fontWeight(.bold)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(searchAsLiteral ? Color.white.opacity(0.62) : Color.white.opacity(0.82))
        .padding(.horizontal, 18)
        .frame(height: 30)
        .background(Color.white.opacity(0.045))
        .accessibilityElement(children: .contain)
      }

      Divider().overlay(Color.white.opacity(0.09))

      if results.isEmpty {
        VStack(spacing: 9) {
          Image(
            systemName: semanticStatus.isPreparing
              ? "brain.head.profile" : (query.isEmpty ? "square.on.square.dashed" : "magnifyingglass")
          )
            .font(.system(size: 30, weight: .light))
          Text(
            semanticStatus.isPreparing
              ? L10n.text("semantic.empty.preparing_title", fallback: "Searching by meaning")
              : (query.isEmpty
              ? L10n.text(
                "picker.empty.clipboard.title", fallback: "Your clipboard is empty")
              : (isAliasMode
                ? L10n.text("picker.empty.alias.title", fallback: "No matching alias")
                : L10n.text("picker.empty.search.title", fallback: "No matching memory")))
          )
          .font(.system(size: 14, weight: .bold))
          Text(
            semanticStatus.isPreparing
              ? L10n.text(
                "semantic.empty.preparing_detail",
                fallback: "Clipskein is building a private, on-device meaning index."
              )
              : (query.isEmpty
              ? L10n.text(
                "picker.empty.clipboard.detail",
                fallback: "Copy text or an image, then open Clipskein again."
              )
              : (isAliasMode
                ? L10n.text(
                  "picker.empty.alias.detail",
                  fallback: "Type @ to browse every alias, or try another shortcut."
                )
                : (searchInterpretation != nil && !searchAsLiteral
                  ? L10n.text(
                    "picker.empty.smart.detail",
                    fallback: "Try changing a date, type, or source — or search literally."
                  )
                  : (searchAsLiteral && searchInterpretation != nil
                    ? L10n.text(
                      "picker.empty.literal.detail",
                      fallback: "Use smart search above, or try different words."
                    )
                    : L10n.text(
                      "picker.empty.search.detail",
                      fallback: "Try a phrase from the text or source app."
                    )))))
          )
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List(selection: $selectedID) {
          ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
            QuickPickerRow(
              store: store,
              item: item,
              pasteActions: store.quickPasteActions(for: item),
              contentMatchQuery: contentMatchQuery,
              semanticConfidence: store.semanticMatchConfidence(for: item, query: query),
              shortcutNumber: index + 1,
              isSelected: selectedID == item.id,
              onUse: {
                selectedID = item.id
                use(item)
              },
              onTogglePin: {
                selectedID = item.id
                togglePin(item)
              },
              onToggleStack: {
                selectedID = item.id
                toggleStackItem(item)
              },
              onPreview: {
                selectedID = item.id
                preview(item)
              },
              onPasteAction: { action in
                use(action, from: item)
              }
            )
            .tag(item.id)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { use(item) }
            .contextMenu {
              Button(
                item.isPinned
                  ? L10n.text("picker.unpin", fallback: "Unpin")
                  : L10n.text("picker.pin", fallback: "Pin")
              ) {
                togglePin(item)
              }
              if SemanticSearchRequest.suggestedQuery(for: item) != nil {
                Button {
                  findSimilar(to: item)
                } label: {
                  Label(
                    L10n.text("semantic.find_similar", fallback: "Find Similar"),
                    systemImage: "brain.head.profile"
                  )
                }
              }
              if item.kind == .image, !item.isConcealed {
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
                .disabled(store.isExportingImage)
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
              Divider()
              Button(L10n.text("picker.delete", fallback: "Delete"), role: .destructive) {
                deleteItem(item)
              }
            }
          }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
      }

      Divider().overlay(Color.white.opacity(0.09))

      ViewThatFits(in: .horizontal) {
        HStack {
          Text(L10n.text("picker.shortcut.select", fallback: "↑↓ select"))
          if results.count > 1 {
            Text(
              L10n.format(
                "picker.shortcut.use", fallback: "⌘1–%d use", results.count))
          }
          if let targetPasteHint {
            Text(targetPasteHint)
              .lineLimit(1)
          } else {
            Text(L10n.text("picker.shortcut.copy", fallback: "↩ copy"))
          }
          Text(L10n.text("picker.shortcut.command_copy", fallback: "⌘↩ copy"))
          Text(L10n.text("picker.shortcut.preview", fallback: "⌘Y preview"))
          if let selectedContextShortcutHint {
            Text(selectedContextShortcutHint)
              .lineLimit(1)
          }
          Text(L10n.text("picker.shortcut.stack", fallback: "⇧↩ stack"))
          if !semanticCollectionCandidates.isEmpty {
            Text(
              L10n.text(
                "picker.shortcut.collect_semantic", fallback: "⌘⇧A collect"
              )
            )
          }
          Text(L10n.text("picker.shortcut.preview_compact", fallback: "⌘Y"))
          if hasAliases, !isAliasMode {
            Text(L10n.text("picker.shortcut.aliases", fallback: "@ aliases"))
          }
          if !store.stackItems.isEmpty {
            Text(L10n.text("picker.shortcut.next", fallback: "⌥↩ next"))
            Text(
              L10n.format(
                "picker.shortcut.use_stack",
                fallback: "⌘⇧↩ use %d",
                store.stackItems.count
              )
            )
          }
          Text(L10n.text("picker.shortcut.pin", fallback: "⌘⇧P pin"))
          Text(L10n.text("picker.shortcut.delete", fallback: "⌘⌫ delete"))
          Spacer()
        }

        HStack {
          Text("↑↓")
          if let targetPasteHint {
            Text(targetPasteHint)
              .lineLimit(1)
          } else {
            Text(L10n.text("picker.shortcut.copy", fallback: "↩ copy"))
          }
          if results.count > 1 {
            Text("⌘1–\(results.count)")
          }
          if let selectedContextShortcutHint {
            Text(selectedContextShortcutHint)
              .lineLimit(1)
          }
          Text(L10n.text("picker.shortcut.stack", fallback: "⇧↩ stack"))
          if !semanticCollectionCandidates.isEmpty {
            Text(
              L10n.text(
                "picker.shortcut.collect_semantic", fallback: "⌘⇧A collect"
              )
            )
          }
          Spacer()
          Text(L10n.text("picker.shortcut.pin", fallback: "⌘⇧P pin"))
          Text(L10n.text("picker.shortcut.delete", fallback: "⌘⌫ delete"))
        }
      }
      .font(.system(size: 10, weight: .semibold, design: .monospaced))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 18)
      .frame(height: 36)

      if let feedback {
        HStack(spacing: 7) {
          Image(systemName: feedback.systemImage)
          Text(feedback.message)
          Spacer()
          if feedback.canUndoDeletion, store.canUndoDeletion {
            Button(L10n.text("picker.undo", fallback: "Undo")) { undoDeletion() }
              .buttonStyle(.plain)
              .underline()
          }
          if feedback.canUndoStackCollection,
            case .undoStackCollection? = store.notice?.action
          {
            Button(L10n.text("picker.undo", fallback: "Undo")) {
              undoSemanticCollection()
            }
            .buttonStyle(.plain)
            .underline()
          }
          if feedback.canOpenSettings {
            Button(L10n.text("picker.open_settings", fallback: "Open Settings")) {
              openAccessibilitySettings()
            }
            .buttonStyle(.plain)
            .underline()
          }
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(BrandTheme.accentOnDark)
        .padding(.horizontal, 18)
        .frame(height: 34)
      }

      Button(L10n.text("picker.hidden.use_selection", fallback: "Use selection")) {
        if feedback?.isPasteBackFailure == true {
          retryPendingPaste()
          return
        }
        guard let item = results.first(where: { $0.id == selectedID }) ?? results.first else {
          return
        }
        use(item)
      }
      .keyboardShortcut(.return, modifiers: [])
      .opacity(0)
      .frame(width: 0, height: 0)

      Button(L10n.text("picker.hidden.copy_selection", fallback: "Copy selection")) {
        guard let item = selectedItem else { return }
        copyOnly(item)
      }
      .keyboardShortcut(.return, modifiers: [.command])
      .opacity(0)
      .frame(width: 0, height: 0)

      Button(
        L10n.text(
          "picker.hidden.use_extracted", fallback: "Paste the selected extracted value")
      ) {
        guard let item = selectedItem, let action = selectedContextAction else { return }
        use(action, from: item)
      }
      .keyboardShortcut(.return, modifiers: [.control])
      .disabled(selectedContextAction == nil)
      .opacity(0)
      .frame(width: 0, height: 0)

      Button(
        L10n.text(
          "picker.hidden.toggle_stack", fallback: "Toggle selection in Stack")
      ) {
        toggleSelectedStackItem()
      }
      .keyboardShortcut(.return, modifiers: [.shift])
      .opacity(0)
      .frame(width: 0, height: 0)

      Button(
        L10n.text(
          "picker.hidden.collect_semantic", fallback: "Collect trusted meaning matches")
      ) {
        collectSemanticResults()
      }
      .keyboardShortcut("a", modifiers: [.command, .shift])
      .disabled(semanticCollectionCandidates.isEmpty)
      .opacity(0)
      .frame(width: 0, height: 0)

      Button(L10n.text("picker.hidden.paste_stack", fallback: "Paste Stack")) {
        useStack()
      }
      .keyboardShortcut(.return, modifiers: [.command, .shift])
      .disabled(store.stackItems.isEmpty)
      .opacity(0)
      .frame(width: 0, height: 0)

      Button(
        L10n.text(
          "picker.hidden.paste_next", fallback: "Paste next Stack item")
      ) {
        useNextStackItem()
      }
      .keyboardShortcut(.return, modifiers: [.option])
      .disabled(store.stackItems.isEmpty)
      .opacity(0)
      .frame(width: 0, height: 0)

      ForEach(0..<8, id: \.self) { index in
        Button(
          L10n.format(
            "picker.hidden.use_result", fallback: "Use result %d", index + 1)
        ) {
          useResult(at: index)
        }
        .keyboardShortcut(
          KeyEquivalent(Character(String(index + 1))),
          modifiers: [.command]
        )
        .disabled(index >= results.count)
        .opacity(0)
        .frame(width: 0, height: 0)
      }

      Button(
        L10n.text(
          "picker.hidden.toggle_pin", fallback: "Pin or unpin selection")
      ) {
        guard let item = selectedItem else { return }
        togglePin(item)
      }
      .keyboardShortcut("p", modifiers: [.command, .shift])
      .disabled(selectedItem == nil)
      .opacity(0)
      .frame(width: 0, height: 0)

      Button(L10n.text("picker.hidden.delete_selection", fallback: "Delete selection")) {
        guard let item = selectedItem else { return }
        deleteItem(item)
      }
      .keyboardShortcut(.delete, modifiers: [.command])
      .disabled(selectedItem == nil)
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
      selectedID = results.first?.id
      searchFocused = true
    }
    .onChange(of: query) { _, _ in
      if semanticOriginQueryKey != SemanticSearchRequest(query)?.cacheKey {
        semanticOriginID = nil
        semanticOriginQueryKey = nil
      }
      searchAsLiteral = false
      selectedID = results.first?.id
      feedback = nil
    }
    .onChange(of: results.map(\.id)) { _, resultIDs in
      if selectedID.map({ resultIDs.contains($0) }) != true {
        selectedID = resultIDs.first
      }
      if let pendingFilePreviewID, !resultIDs.contains(pendingFilePreviewID) {
        self.pendingFilePreviewID = nil
        feedback = .previewUnavailable
      }
    }
    .onChange(of: selectedID) { _, _ in
      if feedback?.isPasteBackFailure == true { feedback = nil }
    }
    .onReceive(NotificationCenter.default.publisher(for: .pasteBackFailed)) { notification in
      let failure = notification.object as? PasteBackFailure
      feedback =
        failure?.reason == .clipboardChanged
        ? .clipboardChanged
        : .pasteBackFailed(targetName: failure?.targetName)
    }
    .onReceive(NotificationCenter.default.publisher(for: .moveQuickPanelSelection)) {
      notification in
      guard let direction = notification.object as? Int else { return }
      moveSelection(direction > 0 ? .down : .up)
    }
    .onReceive(NotificationCenter.default.publisher(for: .useQuickPanelExtractedValue)) { _ in
      guard let item = selectedItem, let action = selectedContextAction else { return }
      use(action, from: item)
    }
    .onReceive(NotificationCenter.default.publisher(for: .previewQuickPanelSelection)) { _ in
      guard let item = selectedItem else { return }
      preview(item)
    }
    .onChange(of: store.imageCacheRevision) { _, _ in
      finishPendingImagePreview()
    }
    .onChange(of: store.fileReferenceRevision) { _, _ in
      finishPendingFilePreview()
    }
    .onMoveCommand { direction in
      moveSelection(direction)
    }
    .onExitCommand {
      if searchAsLiteral {
        searchAsLiteral = false
        selectedID = results.first?.id
      } else if !query.isEmpty, feedback == nil {
        query = ""
      } else {
        NotificationCenter.default.post(name: .dismissQuickPicker, object: nil)
      }
    }
    .sheet(item: $templateItem) { item in
      let template = ClipTemplate(item.text)
      TemplateFillView(
        item: item,
        template: template,
        actionLabel: templateCopyOnly
          ? L10n.text("template_fill.copy", fallback: "Copy Filled Template")
          : L10n.text("template_fill.paste", fallback: "Paste Filled Template")
      ) { renderedText in
        finishTemplate(renderedText, from: item, copyOnly: templateCopyOnly)
      } onCancel: {
        templateItem = nil
      }
    }
    .sheet(item: $previewPayload) { payload in
      let item = store.items.first(where: { $0.id == payload.id })
      QuickPickerPreviewView(
        payload: payload,
        decodedImage: item.flatMap { store.cachedDecodedImage(for: $0) }
      ) {
        previewPayload = nil
      }
    }
  }

  private var sourceApplicationFilterMenu: some View {
    Menu {
      Section(L10n.text("picker.filter.apps", fallback: "Source applications")) {
        ForEach(store.sourceApplicationFacets) { application in
          let token = sourceApplicationToken(for: application)
          Button {
            query = SearchTokenEditor.toggling(token, in: query)
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
              if SearchTokenEditor.contains(token, in: query) {
                Image(systemName: "checkmark")
              }
            }
          }
        }
      }
      if !activeSourceApplicationFacets.isEmpty {
        Divider()
        Button {
          clearSourceApplicationFilters()
        } label: {
          Label(
            L10n.text("picker.filter.apps.clear", fallback: "Clear source filters"),
            systemImage: "xmark.circle"
          )
        }
      }
    } label: {
      Image(
        systemName: activeSourceApplicationFacets.isEmpty
          ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
      )
      .font(.system(size: 12, weight: .bold))
      .foregroundStyle(
        activeSourceApplicationFacets.isEmpty
          ? Color.white.opacity(0.82) : BrandTheme.accentOnDark
      )
      .frame(width: 25, height: 23)
      .background(Color.white.opacity(0.08), in: Capsule())
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .help(
      L10n.text(
        "picker.filter.apps.help", fallback: "Filter history by source application"
      )
    )
    .accessibilityLabel(
      L10n.text("picker.filter.apps", fallback: "Source applications")
    )
  }

  private func sourceApplicationToken(for application: SourceApplicationFacet) -> String {
    let value = application.bundleIdentifier ?? application.name
    let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
    return "app:\(escaped.contains(where: \.isWhitespace) ? "\"\(escaped)\"" : escaped)"
  }

  private func clearSourceApplicationFilters() {
    var updatedQuery = query
    for application in activeSourceApplicationFacets {
      updatedQuery = SearchTokenEditor.toggling(
        sourceApplicationToken(for: application),
        in: updatedQuery
      )
    }
    query = updatedQuery
  }

  private func findSimilar(to item: ClipItem) {
    guard let suggestedQuery = SemanticSearchRequest.suggestedQuery(for: item),
      let request = SemanticSearchRequest("~ \(suggestedQuery)")
    else { return }
    semanticOriginID = item.id
    semanticOriginQueryKey = request.cacheKey
    query = "~ \(suggestedQuery)"
    selectedID = nil
    feedback = nil
  }

  private func copyOnly(_ item: ClipItem) {
    if beginTemplateUse(item, copyOnly: true) { return }
    if item.kind == .image {
      guard store.preparingImageCopyID == nil else { return }
      feedback = .imagePreparing
      Task { @MainActor in
        let copied = await store.copyForUse(item, securely: item.isConcealed)
        guard copied else {
          feedback = .copyFailed
          return
        }
        NotificationCenter.default.post(name: .dismissQuickPicker, object: nil)
      }
      return
    }
    let copied = item.isConcealed ? store.secureCopy(item) : store.copy(item)
    if copied {
      NotificationCenter.default.post(name: .dismissQuickPicker, object: nil)
    } else {
      feedback = .copyFailed
    }
  }

  private func preview(_ item: ClipItem) {
    guard !item.isConcealed else {
      feedback = .previewUnavailable
      return
    }
    if item.kind == .files {
      guard pendingFilePreviewID != item.id else { return }
      pendingFilePreviewID = item.id
      feedback = .previewLoading
      store.refreshFileReferenceAvailability(for: item, force: true)
      return
    }
    if item.kind == .image {
      guard let data = store.cachedImageData(for: item),
        let image = store.cachedDecodedImage(for: item)
      else {
        pendingImagePreviewID = item.id
        feedback = .previewLoading
        store.requestDecodedImage(for: item)
        return
      }
      presentPreview(item, imageData: data, decodedImage: image)
      return
    }
    presentPreview(item, imageData: nil, decodedImage: nil)
  }

  private func exportImage(_ item: ClipItem) {
    guard item.kind == .image, !item.isConcealed, !store.isExportingImage,
      let destination = ImageExportPanel.chooseDestination(for: item)
    else { return }
    Task { @MainActor in
      switch await store.exportImage(item, to: destination) {
      case .exported:
        feedback = .imageExported(destination.lastPathComponent)
      case .cancelled:
        break
      case .failed(let message):
        feedback = .imageExportFailed(message)
      }
    }
  }

  private func finishPendingImagePreview() {
    guard let id = pendingImagePreviewID else { return }
    guard let item = store.items.first(where: { $0.id == id }) else {
      pendingImagePreviewID = nil
      feedback = .previewUnavailable
      return
    }
    if let data = store.cachedImageData(for: item),
      let image = store.cachedDecodedImage(for: item)
    {
      presentPreview(item, imageData: data, decodedImage: image)
      return
    }
    switch store.cachedImageStatus(for: item) {
    case .loading:
      return
    case .available:
      return
    case .failed, .unavailable:
      pendingImagePreviewID = nil
      feedback = .previewUnavailable
    }
  }

  private func finishPendingFilePreview() {
    guard let id = pendingFilePreviewID else { return }
    guard let item = store.items.first(where: { $0.id == id }) else {
      pendingFilePreviewID = nil
      feedback = .previewUnavailable
      return
    }
    let statuses = item.filePaths.map { store.fileReferenceStatus(for: $0, in: item) }
    if statuses.contains(.checking) { return }
    pendingFilePreviewID = nil
    guard !statuses.isEmpty, statuses.allSatisfy({ $0 == .available }) else {
      feedback = .previewUnavailable
      return
    }
    let urls = item.filePaths.map { URL(fileURLWithPath: $0) }
    if FileQuickLookController.shared.preview(urls) {
      feedback = nil
    } else {
      feedback = .previewUnavailable
    }
  }

  private func presentPreview(
    _ item: ClipItem,
    imageData: Data?,
    decodedImage: NSImage?
  ) {
    guard
      let payload = QuickPickerPreviewPayload(
        item: item,
        imageData: imageData,
        decodedImage: decodedImage
      )
    else {
      feedback = .previewUnavailable
      return
    }
    pendingImagePreviewID = nil
    feedback = nil
    previewPayload = payload
  }

  private func useResult(at index: Int) {
    guard results.indices.contains(index) else { return }
    selectedID = results[index].id
    use(results[index])
  }

  private func togglePin(_ item: ClipItem) {
    let willPin = !item.isPinned
    store.togglePin(item)
    selectedID = results.contains(where: { $0.id == item.id }) ? item.id : results.first?.id
    feedback = .pinChanged(pinned: willPin)
  }

  private func deleteItem(_ item: ClipItem) {
    store.delete(item)
    selectedID = results.first?.id
    feedback = .clipDeleted
  }

  private func undoDeletion() {
    guard store.canUndoDeletion else { return }
    store.undoLastDeletion()
    selectedID = store.selectedID ?? results.first?.id
    feedback = .deletionUndone
  }

  private var selectedItem: ClipItem? {
    results.first(where: { $0.id == selectedID }) ?? results.first
  }

  private var selectedContextAction: QuickPasteAction? {
    guard let selectedItem else { return nil }
    return QuickPasteActionBuilder.preferredContextAction(
      in: store.quickPasteActions(for: selectedItem),
      for: selectedItem,
      matching: contentMatchQuery
    )
  }

  private var selectedContextShortcutHint: String? {
    guard let action = selectedContextAction else { return nil }
    return L10n.format(
      "picker.shortcut.extract_value",
      fallback: "⌃↩ %@",
      QuickPasteActionBuilder.compactPreview(action.text, maximumLength: 22)
    )
  }

  private func use(_ item: ClipItem) {
    if beginTemplateUse(item, copyOnly: false) { return }
    if item.kind == .image {
      guard store.preparingImageCopyID == nil else { return }
      feedback = .imagePreparing
      Task { @MainActor in
        handlePasteResult(await pasteCoordinator.pasteAfterPreparingImage(item, using: store))
      }
      return
    }
    handlePasteResult(pasteCoordinator.paste(item, using: store))
  }

  private func handlePasteResult(_ result: QuickPasteResult) {
    switch result {
    case .pasteRequested:
      NotificationCenter.default.post(name: .dismissQuickPicker, object: nil)
    case .copiedOnly:
      feedback = .copiedOnly
    case .permissionRequired:
      feedback = .permissionRequired
    case .copyFailed:
      feedback = .copyFailed
    case .clipboardChanged:
      feedback = .clipboardChanged
    }
  }

  private func retryPendingPaste() {
    switch pasteCoordinator.retryPasteDelivery() {
    case .pasteRequested:
      NotificationCenter.default.post(name: .dismissQuickPicker, object: nil)
    case .copiedOnly:
      feedback = .copiedOnly
    case .permissionRequired:
      feedback = .permissionRequired
    case .copyFailed, .clipboardChanged:
      feedback = .clipboardChanged
    }
  }

  private func beginTemplateUse(_ item: ClipItem, copyOnly: Bool) -> Bool {
    guard ClipTemplate.isEligible(item) else { return false }
    let template = ClipTemplate(item.text)
    if template.fields.isEmpty {
      _ = finishTemplate(template.render(), from: item, copyOnly: copyOnly)
      return true
    }
    templateCopyOnly = copyOnly
    templateItem = item
    return true
  }

  private func finishTemplate(_ text: String, from item: ClipItem, copyOnly: Bool) -> Bool {
    if copyOnly {
      guard store.copyText(text, recording: item) else {
        feedback = .templateCopyFailed
        return false
      }
      templateItem = nil
      NotificationCenter.default.post(name: .dismissQuickPicker, object: nil)
      return true
    }

    switch pasteCoordinator.paste(text: text, from: item, using: store) {
    case .pasteRequested:
      templateItem = nil
      NotificationCenter.default.post(name: .dismissQuickPicker, object: nil)
      return true
    case .copiedOnly:
      templateItem = nil
      feedback = .copiedOnly
      return true
    case .permissionRequired:
      templateItem = nil
      feedback = .permissionRequired
      return true
    case .copyFailed:
      feedback = .templateCopyFailed
      return false
    case .clipboardChanged:
      feedback = .clipboardChanged
      return false
    }
  }

  private func use(_ action: QuickPasteAction, from item: ClipItem) {
    switch pasteCoordinator.paste(text: action.text, from: item, using: store) {
    case .pasteRequested:
      NotificationCenter.default.post(name: .dismissQuickPicker, object: nil)
    case .copiedOnly:
      feedback = .copiedOnly
    case .permissionRequired:
      feedback = .permissionRequired
    case .copyFailed:
      feedback = .formattedCopyFailed
    case .clipboardChanged:
      feedback = .clipboardChanged
    }
  }

  private func toggleSelectedStackItem() {
    guard let item = selectedItem else { return }
    toggleStackItem(item)
  }

  private func toggleStackItem(_ item: ClipItem) {
    let wasInStack = store.isInStack(item)
    guard wasInStack || store.canAddToStack(item) else {
      feedback = .stackUnavailable
      return
    }
    store.toggleStackMembership(item)
    feedback = .stackChanged(added: !wasInStack, count: store.stackItems.count)
  }

  private func collectSemanticResults() {
    let candidates = semanticCollectionCandidates
    guard !candidates.isEmpty else { return }
    guard store.stackItems.count < ClipStore.maximumStackCount else {
      feedback = .stackFull
      return
    }
    let added = store.addItemsToStack(candidates)
    feedback = added > 0
      ? .stackBatchAdded(added: added, total: store.stackItems.count)
      : .stackBatchUnchanged
  }

  private func undoSemanticCollection() {
    guard let action = store.notice?.action,
      case .undoStackCollection = action
    else { return }
    store.performNoticeAction(action)
    feedback = .stackBatchUndone(total: store.stackItems.count)
  }

  private func useStack() {
    guard !store.stackItems.isEmpty else {
      feedback = .stackEmpty
      return
    }
    switch pasteCoordinator.pasteStack(using: store) {
    case .pasteRequested:
      NotificationCenter.default.post(name: .dismissQuickPicker, object: nil)
    case .copiedOnly:
      feedback = .copiedOnly
    case .permissionRequired:
      feedback = .permissionRequired
    case .copyFailed:
      feedback = .stackCopyFailed
    case .clipboardChanged:
      feedback = .clipboardChanged
    }
  }

  private func useNextStackItem() {
    guard !store.stackItems.isEmpty else {
      feedback = .stackEmpty
      return
    }
    switch pasteCoordinator.pasteNextStackItem(using: store) {
    case .pasteRequested:
      NotificationCenter.default.post(name: .dismissQuickPicker, object: nil)
    case .copiedOnly:
      feedback = .nextCopiedOnly(remaining: store.stackItems.count)
    case .permissionRequired:
      feedback = .nextPermissionRequired(remaining: store.stackItems.count)
    case .copyFailed:
      feedback = .nextStackCopyFailed
    case .clipboardChanged:
      feedback = .clipboardChanged
    }
  }

  private func openAccessibilitySettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
      )
    else { return }
    NSWorkspace.shared.open(url)
  }

  private func moveSelection(_ direction: MoveCommandDirection) {
    guard !results.isEmpty else { return }
    let current = results.firstIndex { $0.id == selectedID } ?? 0
    let next: Int
    switch direction {
    case .down:
      next = min(current + 1, results.count - 1)
    case .up:
      next = max(current - 1, 0)
    default:
      return
    }
    selectedID = results[next].id
  }
}

private enum QuickPickerFeedback: Equatable {
  case permissionRequired
  case copiedOnly
  case copyFailed
  case stackChanged(added: Bool, count: Int)
  case stackBatchAdded(added: Int, total: Int)
  case stackBatchUnchanged
  case stackBatchUndone(total: Int)
  case stackFull
  case stackUnavailable
  case stackEmpty
  case stackCopyFailed
  case nextStackCopyFailed
  case nextPermissionRequired(remaining: Int)
  case nextCopiedOnly(remaining: Int)
  case pasteBackFailed(targetName: String?)
  case clipboardChanged
  case formattedCopyFailed
  case templateCopyFailed
  case pinChanged(pinned: Bool)
  case clipDeleted
  case deletionUndone
  case previewLoading
  case previewUnavailable
  case imagePreparing
  case imageExported(String)
  case imageExportFailed(String)

  var message: String {
    switch self {
    case .permissionRequired:
      L10n.text(
        "picker.feedback.permission",
        fallback: "Copied. Press Esc then Command–V, or allow automatic paste."
      )
    case .copiedOnly:
      L10n.text(
        "picker.feedback.copied_only",
        fallback: "Copied. Switch to a destination app and press Command–V."
      )
    case .copyFailed:
      L10n.text(
        "picker.feedback.copy_failed",
        fallback: "Could not copy this item. A local image or referenced file may be missing."
      )
    case .stackChanged(let added, let count):
      added
        ? L10n.format(
          "picker.feedback.stack_added", fallback: "Added to Stack — %d total.", count)
        : L10n.format(
          "picker.feedback.stack_removed",
          fallback: "Removed from Stack — %d remaining.",
          count
        )
    case .stackBatchAdded(let added, let total):
      L10n.format(
        "picker.feedback.stack_batch_added",
        fallback: "Collected %d results — %d in Stack.",
        added,
        total
      )
    case .stackBatchUnchanged:
      L10n.text(
        "picker.feedback.stack_batch_unchanged",
        fallback: "All trusted results are already in Stack."
      )
    case .stackBatchUndone(let total):
      L10n.format(
        "picker.feedback.stack_batch_undone",
        fallback: "Collection undone — %d in Stack.",
        total
      )
    case .stackFull:
      L10n.format(
        "picker.feedback.stack_full",
        fallback: "Stack can hold up to %d clips.",
        ClipStore.maximumStackCount
      )
    case .stackUnavailable:
      L10n.text(
        "picker.feedback.stack_unavailable",
        fallback: "This clip has no text or recognized text to add."
      )
    case .stackEmpty:
      L10n.text(
        "picker.feedback.stack_empty",
        fallback: "Add at least one text clip to the Stack first."
      )
    case .stackCopyFailed:
      L10n.text(
        "picker.feedback.stack_copy_failed",
        fallback: "Could not copy the Stack. Try again from the main window."
      )
    case .nextStackCopyFailed:
      L10n.text(
        "picker.feedback.next_failed",
        fallback: "Could not copy the next item. It remains at the front of the Stack."
      )
    case .formattedCopyFailed:
      L10n.text(
        "picker.feedback.format_failed",
        fallback: "Could not prepare that format. The original clip is unchanged."
      )
    case .templateCopyFailed:
      L10n.text(
        "picker.feedback.template_failed",
        fallback: "Could not copy the filled template. Your entries are still available."
      )
    case .pinChanged(let pinned):
      pinned
        ? L10n.text(
          "picker.feedback.pinned", fallback: "Pinned. This clip will stay easy to reach.")
        : L10n.text(
          "picker.feedback.unpinned", fallback: "Unpinned. The clip remains in history.")
    case .clipDeleted:
      L10n.text(
        "picker.feedback.deleted", fallback: "Deleted. Press Command–Z to undo.")
    case .deletionUndone:
      L10n.text(
        "picker.feedback.restored", fallback: "Restored the deleted clip.")
    case .previewLoading:
      L10n.text(
        "picker.feedback.preview_loading", fallback: "Preparing preview…")
    case .previewUnavailable:
      L10n.text(
        "picker.feedback.preview_unavailable",
        fallback: "Preview is unavailable for concealed or missing content."
      )
    case .imagePreparing:
      L10n.text(
        "picker.feedback.image_preparing",
        fallback: "Preparing the full-resolution image…"
      )
    case .imageExported(let fileName):
      L10n.format("notice.image_exported", fallback: "Exported %@", fileName)
    case .imageExportFailed(let message):
      message
    case .nextPermissionRequired(let remaining):
      L10n.format(
        "picker.feedback.advanced",
        fallback:
          "Copied and advanced — %d remaining. Press Esc then Command–V, or allow automatic paste.",
        remaining
      )
    case .nextCopiedOnly(let remaining):
      L10n.format(
        "picker.feedback.advanced_copied_only",
        fallback:
          "Copied and advanced — %d remaining. Switch to your destination and press Command–V.",
        remaining
      )
    case .pasteBackFailed(let targetName):
      if let targetName, !targetName.isEmpty {
        L10n.format(
          "picker.feedback.paste_back_failed_target",
          fallback:
            "Copied, but %@ was not ready. Press Return to retry, or switch there and press Command–V.",
          targetName
        )
      } else {
        L10n.text(
          "picker.feedback.paste_back_failed",
          fallback:
            "Copied, but the destination was not ready. Press Return to retry, or paste manually."
        )
      }
    case .clipboardChanged:
      L10n.text(
        "picker.feedback.clipboard_changed",
        fallback: "Clipboard changed before paste. Press Return to copy this item and try again."
      )
    }
  }

  var systemImage: String {
    switch self {
    case .permissionRequired, .nextPermissionRequired: "hand.raised.fill"
    case .copiedOnly, .nextCopiedOnly: "doc.on.clipboard.fill"
    case .pasteBackFailed: "arrow.clockwise.circle.fill"
    case .clipboardChanged: "exclamationmark.shield.fill"
    case .copyFailed, .stackUnavailable, .stackEmpty, .stackCopyFailed,
      .nextStackCopyFailed, .formattedCopyFailed, .templateCopyFailed:
      "exclamationmark.triangle.fill"
    case .stackChanged(let added, _):
      added ? "square.stack.3d.up.fill" : "minus.circle.fill"
    case .stackBatchAdded:
      "square.stack.3d.up.fill"
    case .stackBatchUnchanged:
      "checkmark.circle.fill"
    case .stackBatchUndone:
      "arrow.uturn.backward.circle.fill"
    case .stackFull:
      "tray.full.fill"
    case .pinChanged(let pinned):
      pinned ? "pin.fill" : "pin.slash"
    case .clipDeleted:
      "trash"
    case .deletionUndone:
      "arrow.uturn.backward.circle.fill"
    case .previewLoading:
      "clock.arrow.circlepath"
    case .imagePreparing:
      "photo.badge.arrow.down"
    case .previewUnavailable:
      "eye.slash.fill"
    case .imageExported:
      "square.and.arrow.down.fill"
    case .imageExportFailed:
      "exclamationmark.triangle.fill"
    }
  }

  var canOpenSettings: Bool {
    switch self {
    case .permissionRequired, .nextPermissionRequired: true
    default: false
    }
  }

  var canUndoDeletion: Bool {
    self == .clipDeleted
  }

  var canUndoStackCollection: Bool {
    if case .stackBatchAdded = self { return true }
    return false
  }

  var isPasteBackFailure: Bool {
    if case .pasteBackFailed = self { return true }
    return false
  }
}

struct QuickPickerMatchPreview: Equatable {
  private static let maximumFuzzyScanBytes = 65_536

  let text: String
  let matchedText: String

  static func make(for item: ClipItem, query: String, radius: Int = 42) -> Self? {
    guard !item.isConcealed, radius > 0 else { return nil }
    let parsedQuery = ClipSearchQuery(query, interpretNaturalLanguage: false)
    if case .active = parsedQuery.regexStatus, let regex = parsedQuery.regexes.first {
      let title = item.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard title.isEmpty || !regex.matches(title) else { return nil }
      let content = item.kind == .text ? item.text : item.ocrText
      guard !content.isEmpty, let match = regex.firstMatch(in: content) else { return nil }
      return preview(
        title: title,
        content: match.text,
        match: match.range,
        radius: radius
      )
    }
    let matcher = SearchMatcher(query)
    guard !matcher.isEmpty else { return nil }

    let title = item.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard title.isEmpty || !matcher.matches(title) else { return nil }

    let content = item.kind == .text ? item.text : item.ocrText
    guard !content.isEmpty,
      let match = bestMatch(in: content, matcher: matcher)
    else { return nil }

    return preview(title: title, content: content, match: match, radius: radius)
  }

  private static func preview(
    title: String,
    content: String,
    match: Range<String.Index>,
    radius: Int
  ) -> Self? {
    let lower = content.index(
      match.lowerBound,
      offsetBy: -radius,
      limitedBy: content.startIndex
    ) ?? content.startIndex
    let upper = content.index(
      match.upperBound,
      offsetBy: radius,
      limitedBy: content.endIndex
    ) ?? content.endIndex
    let compact = content[lower..<upper]
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    guard !compact.isEmpty else { return nil }

    let prefix = lower == content.startIndex ? "" : "…"
    let suffix = upper == content.endIndex ? "" : "…"
    let context = prefix + compact + suffix
    return Self(
      text: title.isEmpty ? context : "\(title) — \(context)",
      matchedText: String(content[match])
    )
  }

  private static func bestMatch(
    in content: String,
    matcher: SearchMatcher
  ) -> Range<String.Index>? {
    if let exact = content.range(
      of: matcher.query,
      options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
    ) {
      return exact
    }
    for token in matcher.queryTokens {
      if let exact = content.range(
        of: token,
        options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
      ) {
        return exact
      }
    }

    guard content.utf8.count <= maximumFuzzyScanBytes else { return nil }

    var fuzzyMatch: Range<String.Index>?
    content.enumerateSubstrings(
      in: content.startIndex..<content.endIndex,
      options: [.byWords, .substringNotRequired]
    ) { _, range, _, stop in
      let word = String(content[range])
      if matcher.queryTokens.contains(where: { SearchMatcher($0).matches(word) }) {
        fuzzyMatch = range
        stop = true
      }
    }
    return fuzzyMatch
  }
}

private struct QuickPickerRow: View {
  @ObservedObject var store: ClipStore
  let item: ClipItem
  let pasteActions: [QuickPasteAction]
  let contentMatchQuery: String
  let semanticConfidence: SemanticMatchConfidence?
  let shortcutNumber: Int
  let isSelected: Bool
  let onUse: () -> Void
  let onTogglePin: () -> Void
  let onToggleStack: () -> Void
  let onPreview: () -> Void
  let onPasteAction: (QuickPasteAction) -> Void

  private var contextAction: QuickPasteAction? {
    QuickPasteActionBuilder.preferredContextAction(
      in: pasteActions,
      for: item,
      matching: contentMatchQuery
    )
  }

  private var matchPreview: QuickPickerMatchPreview? {
    QuickPickerMatchPreview.make(for: item, query: contentMatchQuery)
  }

  private var highlightedTitle: AttributedString {
    let text = matchPreview?.text ?? item.localizedDisplayTitle()
    var attributed = AttributedString(text)
    guard let matchedText = matchPreview?.matchedText,
      let range = attributed.range(
        of: matchedText,
        options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
      )
    else { return attributed }
    attributed[range].foregroundColor = isSelected ? BrandTheme.selectedAccent : BrandTheme.accentOnDark
    attributed[range].font = .system(size: 13, weight: .bold)
    return attributed
  }

  private var accessibilitySummary: String {
    var parts = [
      item.localizedDisplayTitle(),
      item.privacySafeContentKind.localizedLabel(),
      L10n.format(
        "picker.row.source", fallback: "from %@", item.localizedSourceApplication()),
      RelativeDateTimeFormatter().localizedString(for: item.createdAt, relativeTo: .now),
    ]
    if item.hasRichText, !item.isConcealed {
      parts.append(L10n.text("picker.row.rich", fallback: "Rich"))
    }
    if let metadata = item.imageMetadata, !item.isConcealed {
      parts.append(metadata.localizedSummary)
    }
    if let format = item.localizedImageFormat(), !item.isConcealed {
      parts.append(format)
    }
    if item.isPinned {
      parts.append(L10n.text("picker.row.pinned", fallback: "Pinned"))
    }
    if store.isInStack(item) {
      parts.append(L10n.text("picker.row.in_stack", fallback: "In Stack"))
    }
    if let alias = item.alias { parts.append("@\(alias)") }
    if let semanticConfidence { parts.append(semanticConfidence.localizedLabel) }
    if let contextAction { parts.append(contextAction.label) }
    return parts.joined(separator: ", ")
  }

  var body: some View {
    HStack(spacing: 12) {
      Text("⌘\(shortcutNumber)")
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .foregroundStyle(isSelected ? BrandTheme.selectedText.opacity(0.75) : Color.white.opacity(0.65))
        .frame(width: 20)

      Group {
        if item.isConcealed {
          ZStack {
            Color.orange.opacity(0.14)
            Image(systemName: "eye.slash.fill")
              .font(.system(size: 13, weight: .bold))
              .foregroundStyle(Color.orange)
          }
        } else if item.kind == .image {
          if let image = store.cachedDecodedImage(for: item) {
            Image(nsImage: image).resizable().scaledToFill()
          } else {
            ZStack {
              Color.white.opacity(0.07)
              Image(systemName: "photo.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isSelected ? BrandTheme.plum : BrandTheme.softTeal)
            }
            .task(id: item.imageFileName) { store.requestDecodedImage(for: item) }
          }
        } else if item.kind == .files {
          ZStack {
            Color.white.opacity(0.07)
            Image(systemName: item.filePaths.count > 1 ? "doc.on.doc.fill" : "doc.fill")
              .font(.system(size: 13, weight: .bold))
              .foregroundStyle(isSelected ? BrandTheme.plum : BrandTheme.softTeal)
          }
        } else if let color = item.contentAnalysis.color {
          Color(red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
        } else {
          ZStack {
            Color.white.opacity(0.07)
            Image(systemName: item.privacySafeContentKind.systemImage)
              .font(.system(size: 13, weight: .bold))
              .foregroundStyle(isSelected ? BrandTheme.plum : BrandTheme.softTeal)
          }
        }
      }
      .frame(width: 42, height: 42)
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .overlay(alignment: .bottomTrailing) {
        if let icon = store.sourceApplicationIcon(for: item) {
          Image(nsImage: icon)
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 4))
            .overlay(
              RoundedRectangle(cornerRadius: 4)
                .stroke(Color.black.opacity(0.22), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 1, y: 1)
        }
      }
      .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 4) {
        Text(highlightedTitle)
          .font(.system(size: 13, weight: .semibold))
          .lineLimit(1)
        HStack(spacing: 5) {
          Text(item.privacySafeContentKind.localizedLabel())
          Text("·")
          Text(item.localizedSourceApplication())
          if item.hasRichText, !item.isConcealed {
            Text("·")
            Text(L10n.text("picker.row.rich", fallback: "Rich"))
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
          Text(item.createdAt, style: .relative).monospacedDigit()
          if let semanticConfidence {
            Text("·")
            Label(semanticConfidence.localizedLabel, systemImage: semanticConfidence.systemImage)
              .foregroundStyle(isSelected ? BrandTheme.selectedAccent : BrandTheme.accentOnDark)
          }
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(isSelected ? BrandTheme.selectedText.opacity(0.76) : Color.white.opacity(0.70))
      }
      Spacer()
      if let alias = item.alias {
        Text("@\(alias)")
          .font(.system(size: 9, weight: .bold, design: .monospaced))
          .foregroundStyle(isSelected ? BrandTheme.selectedAccent : BrandTheme.accentOnDark)
          .padding(.horizontal, 6)
          .frame(height: 19)
          .background(Color.white.opacity(0.07), in: Capsule())
      }
      if ClipTemplate.isEligible(item) {
        Label(
          L10n.text("picker.row.template", fallback: "Template"),
          systemImage: "text.badge.plus"
        )
        .labelStyle(.iconOnly)
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(isSelected ? BrandTheme.plum : BrandTheme.softTeal)
        .help(
          L10n.text(
            "picker.row.template.help", fallback: "Fill dynamic fields before pasting")
        )
        .accessibilityLabel(L10n.text("picker.row.template", fallback: "Template"))
      }
      if item.isPinned {
        Image(systemName: "pin.fill")
          .font(.system(size: 10))
          .foregroundStyle(isSelected ? BrandTheme.selectedAccent : BrandTheme.accentOnDark)
          .accessibilityLabel(L10n.text("picker.row.pinned", fallback: "Pinned"))
      }
      if store.isInStack(item) {
        Image(systemName: "square.stack.3d.up.fill")
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(isSelected ? BrandTheme.plum : BrandTheme.softTeal)
          .accessibilityLabel(L10n.text("picker.row.in_stack", fallback: "In Stack"))
      }
      if let contextAction {
        Button {
          onPasteAction(contextAction)
        } label: {
          Label(contextAction.text, systemImage: contextAction.systemImage)
            .labelStyle(.titleAndIcon)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(maxWidth: 112, minHeight: 21)
            .background(
              BrandTheme.accentOnDark.opacity(0.14),
              in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .help(contextAction.label)
      }
      if store.isPreparingQuickPasteActions(for: item) {
        ProgressView()
          .controlSize(.small)
          .help(
            L10n.text(
              "quick_paste.preparing_actions",
              fallback: "Preparing local actions…"
            )
          )
          .accessibilityLabel(
            L10n.text(
              "quick_paste.preparing_actions",
              fallback: "Preparing local actions…"
            )
          )
      }
      if !item.isConcealed {
        Button(action: onPreview) {
          Image(systemName: "eye")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isSelected ? BrandTheme.selectedText.opacity(0.76) : Color.white.opacity(0.70))
        }
        .buttonStyle(.plain)
        .help(
          L10n.text(
            "picker.row.quick_look.help", fallback: "Quick Look without leaving the picker")
        )
        .accessibilityLabel(
          L10n.text("picker.row.preview", fallback: "Preview clip"))
      }
      if !pasteActions.isEmpty {
        Menu {
          ForEach(pasteActions) { action in
            Button {
              onPasteAction(action)
            } label: {
              Label(action.label, systemImage: action.systemImage)
            }
          }
        } label: {
          Image(systemName: "ellipsis.circle")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isSelected ? BrandTheme.selectedText.opacity(0.76) : Color.white.opacity(0.70))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(
          L10n.text("picker.row.formats.help", fallback: "Paste in another format")
        )
        .accessibilityLabel(L10n.text("picker.row.formats", fallback: "Paste formats"))
      }
    }
    .padding(.vertical, 5)
    .foregroundStyle(isSelected ? BrandTheme.selectedText : Color.white)
    .background(isSelected ? BrandTheme.softPlum : Color.clear)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilitySummary)
    .accessibilityHint(
      L10n.text(
        "picker.row.accessibility_hint",
        fallback: "Press Return to use this clip. More actions are available with VoiceOver."
      )
    )
    .accessibilityAction { onUse() }
    .accessibilityActions {
      Button(
        item.isPinned
          ? L10n.text("picker.unpin", fallback: "Unpin")
          : L10n.text("picker.pin", fallback: "Pin"),
        action: onTogglePin
      )
      if store.isInStack(item) || store.canAddToStack(item) {
        Button(
          store.isInStack(item)
            ? L10n.text("main.stack.remove", fallback: "Remove from Stack")
            : L10n.text("main.detail.add_stack", fallback: "Add to Stack"),
          action: onToggleStack
        )
      }
      if !item.isConcealed {
        Button(
          L10n.text("picker.row.preview", fallback: "Preview clip"),
          action: onPreview
        )
      }
      ForEach(pasteActions) { action in
        Button(action.label) { onPasteAction(action) }
      }
    }
  }
}
