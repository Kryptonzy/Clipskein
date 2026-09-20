import AppKit
import SwiftUI

struct EditClipView: View {
  let item: ClipItem?
  let originalText: String
  let isCreatingSnippet: Bool
  let availableBoards: [ClipBoard]
  let protectsSecrets: Bool
  let sourceApplication: String?
  let sourceBundleIdentifier: String?
  let richTextData: Data?
  let onSubmit: (NewSnippetDraft) -> String?
  let onValidate: (NewSnippetDraft) -> String?
  let onDraftChange: (NewSnippetDraft) -> Void
  let onDiscard: () -> Void
  let onCancel: () -> Void

  @State private var text: String
  @State private var title: String
  @State private var alias: String
  @State private var concealSnippet: Bool
  @State private var tagsText: String
  @State private var selectedBoardID: UUID?
  @State private var failureMessage: String?
  @State private var templatePreviewNow = Date.now
  @State private var templatePreviewIdentifier = UUID()
  @State private var editorSelection: NSRange?
  @State private var editorTextView: NSTextView?
  @FocusState private var editorIsFocused: Bool

  init(
    item: ClipItem,
    originalText: String,
    onSave: @escaping (String) -> EditedClipResult,
    onCancel: @escaping () -> Void
  ) {
    self.item = item
    self.originalText = originalText
    self.isCreatingSnippet = false
    self.availableBoards = []
    self.protectsSecrets = false
    self.sourceApplication = nil
    self.sourceBundleIdentifier = nil
    self.richTextData = nil
    self.onSubmit = { draft in onSave(draft.text).errorMessage }
    self.onValidate = { _ in nil }
    self.onDraftChange = { _ in }
    self.onDiscard = onCancel
    self.onCancel = onCancel
    _text = State(initialValue: originalText)
    _title = State(initialValue: "")
    _alias = State(initialValue: "")
    _concealSnippet = State(initialValue: false)
    _tagsText = State(initialValue: "")
    _selectedBoardID = State(initialValue: nil)
  }

  init(
    boards: [ClipBoard],
    protectsSecrets: Bool,
    draft: NewSnippetDraft = .empty,
    onCreate: @escaping (NewSnippetDraft) -> SnippetCreationResult,
    onValidate: @escaping (NewSnippetDraft) -> String?,
    onDraftChange: @escaping (NewSnippetDraft) -> Void,
    onDiscard: @escaping () -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.item = nil
    self.originalText = ""
    self.isCreatingSnippet = true
    self.availableBoards = boards
    self.protectsSecrets = protectsSecrets
    self.sourceApplication = draft.sourceApplication
    self.sourceBundleIdentifier = draft.sourceBundleIdentifier
    self.richTextData = draft.richTextData
    self.onSubmit = { draft in onCreate(draft).errorMessage }
    self.onValidate = onValidate
    self.onDraftChange = onDraftChange
    self.onDiscard = onDiscard
    self.onCancel = onCancel
    _text = State(initialValue: draft.text)
    _title = State(initialValue: draft.title)
    _alias = State(initialValue: draft.alias)
    _concealSnippet = State(initialValue: draft.conceal)
    _tagsText = State(initialValue: draft.tags.joined(separator: ", "))
    _selectedBoardID = State(
      initialValue: draft.boardID.flatMap { id in boards.contains { $0.id == id } ? id : nil }
    )
  }

  private var isEmpty: Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var isUnchanged: Bool { !isCreatingSnippet && text == originalText }
  private var isTooLarge: Bool { text.utf8.count > ClipStore.maximumEditedTextBytes }
  private var canAuthorTemplate: Bool {
    (isCreatingSnippet && !willConcealSnippet)
      || (item?.kind == .text && item?.isConcealed == false)
  }
  private var automaticallyConcealsSnippet: Bool {
    isCreatingSnippet && protectsSecrets && ClipStore.looksSensitive(text)
  }
  private var willConcealSnippet: Bool { concealSnippet || automaticallyConcealsSnippet }
  private var draftTemplate: ClipTemplate { ClipTemplate(text) }
  private var currentDraft: NewSnippetDraft {
    NewSnippetDraft(
      text: text,
      title: title,
      alias: alias,
      conceal: concealSnippet,
      tags: parsedTags,
      boardID: selectedBoardID,
      sourceApplication: sourceApplication,
      sourceBundleIdentifier: sourceBundleIdentifier,
      richTextData: preservedRichTextData
    )
  }

  private var preservedRichTextData: Data? {
    RichTextPayload.validated(richTextData, matching: text)
  }
  private var parsedTags: [String] {
    tagsText.split(whereSeparator: { $0 == "," || $0.isNewline }).map(String.init)
  }
  private var validationMessage: String? {
    isCreatingSnippet ? onValidate(currentDraft) : nil
  }
  private var titleIsTooLong: Bool {
    title.trimmingCharacters(in: .whitespacesAndNewlines).count
      > ClipStore.maximumCustomTitleLength
  }
  private var aliasIsTooLong: Bool { ClipAlias.exceedsMaximumLength(alias) }
  private var aliasIsInvalid: Bool {
    !alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && ClipAlias.normalized(alias) == nil
  }
  private var tagsExceedLimit: Bool { parsedTags.count > ClipStore.maximumTagCount }
  private var tagIsTooLong: Bool {
    parsedTags.contains { tag in
      var normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines)
      while normalized.hasPrefix("#") { normalized.removeFirst() }
      return normalized.trimmingCharacters(in: .whitespacesAndNewlines).count
        > ClipStore.maximumTagLength
    }
  }

  private var templatePreview: String {
    let template = draftTemplate
    return template.render(
      values: template.previewValues(),
      now: templatePreviewNow,
      identifier: templatePreviewIdentifier
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 5) {
        Text(
          isCreatingSnippet
            ? L10n.text("new_snippet.title", fallback: "New Snippet")
            : item?.kind == .image
            ? L10n.text("edit_clip.title_ocr", fallback: "Edit recognized text")
            : L10n.text("edit_clip.title", fallback: "Create an edited copy")
        )
        .font(.system(size: 22, weight: .bold, design: .rounded))
        Text(
          isCreatingSnippet
            ? L10n.text(
              "new_snippet.detail",
              fallback: "Create a pinned, searchable snippet without changing the clipboard."
            )
            : L10n.text(
              "edit_clip.detail",
              fallback:
                "The original clip stays unchanged. Your edit becomes a separate searchable clip."
            )
        )
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
      }

      if isCreatingSnippet {
        VStack(alignment: .leading, spacing: 10) {
          Label(
            L10n.text(
              "new_snippet.draft_protection",
              fallback: "Drafts are encrypted locally and restored automatically."
            ),
            systemImage: "lock.doc.fill"
          )
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(.secondary)

          if let sourceApplication, !sourceApplication.isEmpty {
            Label(
              L10n.format(
                "new_snippet.captured_from", fallback: "Captured from %@", sourceApplication),
              systemImage: "app.dashed"
            )
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
          }

          if preservedRichTextData != nil {
            Label(
              L10n.text(
                "new_snippet.formatting_preserved",
                fallback: "Original formatting will be preserved"
              ),
              systemImage: "textformat"
            )
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
          }

          HStack(spacing: 12) {
            TextField(
              L10n.text("new_snippet.title_placeholder", fallback: "Optional title"),
              text: $title
            )
            .textFieldStyle(.roundedBorder)
            HStack(spacing: 4) {
              Text("@")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
              TextField(
                L10n.text("new_snippet.alias_placeholder", fallback: "optional-alias"),
                text: $alias
              )
              .textFieldStyle(.roundedBorder)
            }
          }
          HStack(spacing: 12) {
            Text(
              L10n.format(
                "new_snippet.title_count", fallback: "Title %d/%d",
                title.count, ClipStore.maximumCustomTitleLength)
            )
            .foregroundStyle(titleIsTooLong ? Color.red : Color.secondary)
            Spacer()
            Text(
              L10n.format(
                "new_snippet.alias_count", fallback: "Alias %d/%d",
                alias.count, ClipAlias.maximumLength)
            )
            .foregroundStyle(aliasIsTooLong || aliasIsInvalid ? Color.red : Color.secondary)
          }
          .font(.system(size: 10, weight: .medium))
          Toggle(
            L10n.text("new_snippet.conceal", fallback: "Conceal preview"),
            isOn: $concealSnippet
          )
          .toggleStyle(.checkbox)
          .help(
            L10n.text(
              "new_snippet.conceal_help",
              fallback:
                "Hide content until you reveal it. Likely passwords and secrets are concealed automatically."
            )
          )

          if automaticallyConcealsSnippet, !concealSnippet {
            Label(
              L10n.text(
                "new_snippet.secret_detected",
                fallback: "Likely secret detected · preview will be concealed automatically"
              ),
              systemImage: "lock.shield.fill"
            )
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.orange)
          }

          HStack(spacing: 12) {
            TextField(
              L10n.text(
                "new_snippet.tags_placeholder", fallback: "Tags, separated by commas"),
              text: $tagsText
            )
            .textFieldStyle(.roundedBorder)

            Picker(
              L10n.text("new_snippet.pinboard", fallback: "Pinboard"),
              selection: $selectedBoardID
            ) {
              Text(L10n.text("new_snippet.no_pinboard", fallback: "No Pinboard"))
                .tag(nil as UUID?)
              ForEach(availableBoards) { board in
                Text(board.name).tag(Optional(board.id))
              }
            }
            .frame(width: 220)
          }
          HStack {
            Text(
              L10n.format(
                "new_snippet.tags_count", fallback: "Tags %d/%d",
                parsedTags.count, ClipStore.maximumTagCount)
            )
            .foregroundStyle(tagsExceedLimit || tagIsTooLong ? Color.red : Color.secondary)
            Spacer()
          }
          .font(.system(size: 10, weight: .medium))

          if let validationMessage {
            Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(Color.red)
          }
        }
      }

      TextEditor(text: $text)
        .font(
          .system(
            size: 14,
            design: item?.privacySafeContentKind == .code ? .monospaced : .rounded
          )
        )
        .focused($editorIsFocused)
        .padding(8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.18)))

      if canAuthorTemplate {
        HStack(spacing: 10) {
          Menu {
            Button(
              L10n.text(
                "edit_clip.template.custom", fallback: "Fill-in field · {{name}}")
            ) {
              insertTemplatePlaceholder("{{name}}")
            }
            Button(
              L10n.text(
                "edit_clip.template.default",
                fallback: "Field with default · {{name|friend}}")
            ) {
              insertTemplatePlaceholder("{{name|friend}}")
            }
            Divider()
            Button(
              L10n.text("edit_clip.template.date", fallback: "Current date · {{date}}")
            ) {
              insertTemplatePlaceholder("{{date}}")
            }
            Button(
              L10n.text(
                "edit_clip.template.date_offset", fallback: "Seven days later · {{date+7d}}")
            ) {
              insertTemplatePlaceholder("{{date+7d}}")
            }
            Button(
              L10n.text("edit_clip.template.time", fallback: "Current time · {{time}}")
            ) {
              insertTemplatePlaceholder("{{time}}")
            }
            Button(
              L10n.text(
                "edit_clip.template.datetime", fallback: "Date and time · {{datetime}}")
            ) {
              insertTemplatePlaceholder("{{datetime}}")
            }
            Divider()
            Button(
              L10n.text(
                "edit_clip.template.iso8601", fallback: "ISO 8601 time · {{iso8601}}")
            ) {
              insertTemplatePlaceholder("{{iso8601}}")
            }
            Button(
              L10n.text("edit_clip.template.uuid", fallback: "Unique ID · {{uuid}}")
            ) {
              insertTemplatePlaceholder("{{uuid}}")
            }
          } label: {
            Label(
              L10n.text("edit_clip.template.insert", fallback: "Insert Template Variable"),
              systemImage: "curlybraces"
            )
          }
          .menuStyle(.borderlessButton)

          Text(
            L10n.text(
              isCreatingSnippet ? "new_snippet.template_help" : "edit_clip.template.help",
              fallback: isCreatingSnippet
                ? "New snippets are pinned automatically; add an @alias for instant lookup."
                : "Pin the saved copy or give it an @alias to reuse it as a template."
            )
          )
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(.secondary)
          Spacer()
        }
      }

      if canAuthorTemplate, draftTemplate.hasPlaceholders {
        VStack(alignment: .leading, spacing: 7) {
          HStack(spacing: 8) {
            Text(L10n.text("edit_clip.template.preview", fallback: "TEMPLATE PREVIEW"))
              .font(.system(size: 10, weight: .black, design: .monospaced))
              .tracking(1.1)
            Spacer()
            if draftTemplate.isSupported {
              Text(templateFieldSummary)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            } else {
              Text(
                L10n.format(
                  "edit_clip.template.too_many",
                  fallback: "%d fields · maximum %d",
                  draftTemplate.fields.count,
                  ClipTemplate.maximumCustomFieldCount
                )
              )
              .font(.system(size: 10, weight: .bold))
              .foregroundStyle(Color.orange)
            }
            Button {
              templatePreviewNow = .now
              templatePreviewIdentifier = UUID()
            } label: {
              Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(
              L10n.text(
                "edit_clip.template.refresh_preview", fallback: "Refresh dynamic preview values")
            )
          }

          Text(templatePreview)
            .font(.system(size: 12, design: .rounded))
            .lineLimit(4)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)

          if !draftTemplate.isSupported {
            Text(
              L10n.text(
                "edit_clip.template.unsupported_help",
                fallback:
                  "The clip can still be saved, but it will not run as a template until fields are reduced."
              )
            )
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.orange)
          }
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.14)))
      }

      HStack {
        if isTooLarge {
          Text(L10n.text("edit_clip.too_large", fallback: "Keep edited text under 2 MB."))
            .foregroundStyle(Color.red)
        } else if isUnchanged {
          Text(
            L10n.text(
              "edit_clip.unchanged", fallback: "Make a change to create a new clip.")
          )
          .foregroundStyle(.secondary)
        } else if isEmpty {
          Text(L10n.text("edit_clip.empty", fallback: "Edited text cannot be empty."))
            .foregroundStyle(Color.red)
        } else {
          Text(
            item?.isConcealed == true
              ? L10n.text(
                "edit_clip.concealed", fallback: "The edited copy will remain concealed.")
              : isCreatingSnippet && willConcealSnippet
                ? L10n.text(
                  "new_snippet.ready_concealed",
                  fallback: "Ready to encrypt, pin, and conceal locally."
                )
                : isCreatingSnippet
                ? L10n.text(
                  "new_snippet.ready", fallback: "Ready to encrypt and pin locally.")
                : L10n.text("edit_clip.ready", fallback: "Ready to save locally.")
          )
          .foregroundStyle(.secondary)
        }
        Spacer()
        Text(
          L10n.format("edit_clip.character_count", fallback: "%d characters", text.count)
        )
        .monospacedDigit()
        .foregroundStyle(.secondary)
      }
      .font(.system(size: 11, weight: .medium))

      if let failureMessage {
        Label(failureMessage, systemImage: "exclamationmark.triangle.fill")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(Color.orange)
      }

      HStack {
        if isCreatingSnippet, currentDraft.hasContent {
          Button(
            L10n.text("new_snippet.discard", fallback: "Discard Draft"),
            role: .destructive,
            action: onDiscard
          )
        }
        Spacer()
        Button(
          isCreatingSnippet
            ? L10n.text("new_snippet.close", fallback: "Close")
            : L10n.text("edit_clip.cancel", fallback: "Cancel"),
          action: onCancel
        )
          .keyboardShortcut(.cancelAction)
        Button(
          isCreatingSnippet
            ? L10n.text("new_snippet.create", fallback: "Create Snippet")
            : L10n.text("edit_clip.create", fallback: "Create Edited Copy"),
          action: save
        )
          .keyboardShortcut(.defaultAction)
          .disabled(isEmpty || isUnchanged || isTooLarge || validationMessage != nil)
      }
    }
    .padding(24)
    .frame(width: 620, height: editorHeight)
    .onAppear { editorIsFocused = true }
    .onChange(of: currentDraft) { _, draft in
      guard isCreatingSnippet else { return }
      failureMessage = nil
      onDraftChange(draft)
    }
    .onReceive(
      NotificationCenter.default.publisher(for: NSTextView.didChangeSelectionNotification)
    ) { notification in
      rememberEditorSelection(notification)
    }
  }

  private func save() {
    guard !isEmpty, !isUnchanged, !isTooLarge, validationMessage == nil else { return }
    failureMessage = onSubmit(currentDraft)
  }

  private func insertTemplatePlaceholder(_ placeholder: String) {
    let selection = editorTextView?.selectedRange() ?? editorSelection
    let insertion = ClipTemplate.insertingPlaceholder(
      placeholder,
      into: text,
      replacing: selection
    )
    text = insertion.text
    editorSelection = insertion.selectedRange
    failureMessage = nil
    Task { @MainActor in
      await Task.yield()
      editorIsFocused = true
      editorTextView?.setSelectedRange(insertion.selectedRange)
      editorTextView?.scrollRangeToVisible(insertion.selectedRange)
    }
  }

  private func rememberEditorSelection(_ notification: Notification) {
    guard let textView = notification.object as? NSTextView,
      textView.isEditable,
      !textView.isFieldEditor
    else {
      return
    }
    editorTextView = textView
    editorSelection = textView.selectedRange()
  }

  private var templateFieldSummary: String {
    switch draftTemplate.fields.count {
    case 0:
      return L10n.text("edit_clip.template.dynamic_only", fallback: "Dynamic values only")
    case 1:
      return L10n.text("edit_clip.template.one_field", fallback: "1 fill-in field")
    default:
      return L10n.format(
        "edit_clip.template.many_fields",
        fallback: "%d fill-in fields",
        draftTemplate.fields.count
      )
    }
  }

  private var editorHeight: CGFloat {
    if isCreatingSnippet {
      return draftTemplate.hasPlaceholders ? 760 : 650
    }
    return draftTemplate.hasPlaceholders && canAuthorTemplate ? 620 : 500
  }
}
