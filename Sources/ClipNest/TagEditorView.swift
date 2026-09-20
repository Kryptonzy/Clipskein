import SwiftUI

struct TagEditorView: View {
  let item: ClipItem
  let onSave: ([String]) -> Void
  let onCancel: () -> Void

  @State private var tags: [String]
  @State private var draft = ""
  @State private var validationMessage: String?
  @FocusState private var draftIsFocused: Bool

  init(
    item: ClipItem,
    onSave: @escaping ([String]) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.item = item
    self.onSave = onSave
    self.onCancel = onCancel
    _tags = State(initialValue: item.tags)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 6) {
        Text(L10n.text("tag_editor.title", fallback: "Organize this clip"))
          .font(.system(size: 22, weight: .bold, design: .rounded))
        Text(
          L10n.text(
            "tag_editor.detail",
            fallback: "Tags stay on this Mac, remain searchable, and travel in encrypted backups."
          )
        )
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
      }

      if tags.isEmpty {
        Text(L10n.text("tag_editor.empty", fallback: "No tags yet"))
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
      } else {
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 110), spacing: 8)],
          alignment: .leading,
          spacing: 8
        ) {
          ForEach(tags, id: \.self) { tag in
            HStack(spacing: 6) {
              Image(systemName: "tag.fill")
              Text(tag)
                .lineLimit(1)
              Spacer(minLength: 0)
              Button {
                remove(tag)
              } label: {
                Image(systemName: "xmark.circle.fill")
                  .foregroundStyle(.secondary)
              }
              .buttonStyle(.plain)
              .help(L10n.format("tag_editor.remove_help", fallback: "Remove %@", tag))
            }
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(Color.accentColor.opacity(0.10), in: Capsule())
          }
        }
      }

      VStack(alignment: .leading, spacing: 7) {
        HStack(spacing: 8) {
          TextField(L10n.text("tag_editor.placeholder", fallback: "Add a tag"), text: $draft)
            .textFieldStyle(.roundedBorder)
            .focused($draftIsFocused)
            .onSubmit(addDraft)
          Button(L10n.text("tag_editor.add", fallback: "Add"), action: addDraft)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }

        HStack {
          if let validationMessage {
            Text(validationMessage)
              .foregroundStyle(.red)
          } else {
            Text(
              L10n.text(
                "tag_editor.help", fallback: "Press Return to add. A leading # is optional.")
            )
            .foregroundStyle(.secondary)
          }
          Spacer()
          Text("\(tags.count)/\(ClipStore.maximumTagCount)")
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .font(.system(size: 11, weight: .medium))
      }

      HStack {
        if !tags.isEmpty {
          Button(L10n.text("tag_editor.remove_all", fallback: "Remove all"), role: .destructive) {
            tags.removeAll()
            validationMessage = nil
          }
        }
        Spacer()
        Button(L10n.text("tag_editor.cancel", fallback: "Cancel"), action: onCancel)
          .keyboardShortcut(.cancelAction)
        Button(L10n.text("tag_editor.save", fallback: "Save")) { onSave(tags) }
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(24)
    .frame(width: 480)
    .onAppear { draftIsFocused = true }
  }

  private func addDraft() {
    let raw = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty else { return }
    guard tags.count < ClipStore.maximumTagCount else {
      validationMessage = L10n.format(
        "tag_editor.limit", fallback: "A clip can have up to %d tags.", ClipStore.maximumTagCount)
      return
    }
    var candidate = raw
    while candidate.hasPrefix("#") {
      candidate.removeFirst()
    }
    candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !candidate.isEmpty else {
      validationMessage = L10n.text(
        "tag_editor.invalid", fallback: "Enter a word or short phrase after #.")
      return
    }
    guard candidate.count <= ClipStore.maximumTagLength else {
      validationMessage = L10n.format(
        "tag_editor.length", fallback: "Keep tags under %d characters.",
        ClipStore.maximumTagLength)
      return
    }
    let normalized = ClipStore.normalizedTags(tags + [candidate])
    guard normalized.count > tags.count else {
      validationMessage = L10n.text(
        "tag_editor.duplicate", fallback: "That tag is already attached.")
      return
    }
    tags = normalized
    draft = ""
    validationMessage = nil
  }

  private func remove(_ tag: String) {
    tags.removeAll { $0 == tag }
    validationMessage = nil
  }
}
