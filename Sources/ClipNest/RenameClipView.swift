import SwiftUI

struct RenameClipView: View {
  let item: ClipItem
  let onSave: (String, String) -> String?
  let onCancel: () -> Void

  @State private var title: String
  @State private var alias: String
  @State private var failureMessage: String?
  @FocusState private var titleIsFocused: Bool

  init(
    item: ClipItem,
    onSave: @escaping (String, String) -> String?,
    onCancel: @escaping () -> Void
  ) {
    self.item = item
    self.onSave = onSave
    self.onCancel = onCancel
    _title = State(initialValue: item.customTitle ?? "")
    _alias = State(initialValue: item.alias ?? "")
  }

  private var trimmedTitle: String {
    title.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var isTooLong: Bool {
    title.count > ClipStore.maximumCustomTitleLength
  }

  private var aliasIsInvalid: Bool {
    !alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && ClipAlias.normalized(alias) == nil
  }

  private var aliasIsTooLong: Bool {
    ClipAlias.exceedsMaximumLength(alias)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 6) {
        Text(L10n.text("rename_clip.title", fallback: "Edit clip details"))
          .font(.system(size: 22, weight: .bold, design: .rounded))
        Text(
          L10n.text(
            "rename_clip.detail",
            fallback: "A short title makes long text and screenshots easier to find.")
        )
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
      }

      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
          Text("@")
            .font(.system(size: 14, weight: .bold, design: .monospaced))
            .foregroundStyle(.secondary)
          TextField(
            L10n.text("rename_clip.alias_placeholder", fallback: "email or shipping-address"),
            text: $alias
          )
          .textFieldStyle(.roundedBorder)
        }
        HStack {
          Text(
            aliasIsTooLong
              ? L10n.format(
                "rename_clip.alias_limit",
                fallback: "Keep the alias under %d characters.",
                ClipAlias.maximumLength)
              : (aliasIsInvalid
                ? L10n.text(
                  "rename_clip.alias_invalid",
                  fallback: "Use letters, numbers, hyphens, or underscores.")
                : L10n.text(
                  "rename_clip.alias_help",
                  fallback: "Type this alias in Quick Picker to bring the clip to the top."))
          )
          Spacer()
          Text("\(alias.count)/\(ClipAlias.maximumLength)")
            .monospacedDigit()
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(aliasIsInvalid || aliasIsTooLong ? Color.red : Color.secondary)
      }

      if let failureMessage {
        Label(failureMessage, systemImage: "exclamationmark.triangle.fill")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(Color.orange)
      }

      VStack(alignment: .leading, spacing: 6) {
        TextField(
          L10n.text(
            "rename_clip.title_placeholder", fallback: "Example: March software receipt"),
          text: $title
        )
        .textFieldStyle(.roundedBorder)
        .focused($titleIsFocused)
        .onSubmit(save)

        HStack {
          if isTooLong {
            Text(
              L10n.format(
                "rename_clip.title_limit",
                fallback: "Keep the title under %d characters.",
                ClipStore.maximumCustomTitleLength)
            )
            .foregroundStyle(.red)
          }
          Spacer()
          Text("\(title.count)/\(ClipStore.maximumCustomTitleLength)")
            .monospacedDigit()
            .foregroundStyle(isTooLong ? .red : .secondary)
        }
        .font(.system(size: 11, weight: .medium))
      }

      Text(
        L10n.text(
          "rename_clip.original_unchanged",
          fallback: "The original clipboard content stays unchanged.")
      )
      .font(.system(size: 11))
      .foregroundStyle(.secondary)

      HStack {
        if item.customTitle != nil {
          Button(
            L10n.text("rename_clip.clear_title", fallback: "Clear title"),
            role: .destructive
          ) { title = "" }
        }
        Spacer()
        Button(L10n.text("rename_clip.cancel", fallback: "Cancel"), action: onCancel)
          .keyboardShortcut(.cancelAction)
        Button(L10n.text("rename_clip.save", fallback: "Save"), action: save)
          .keyboardShortcut(.defaultAction)
          .disabled(isTooLong || aliasIsInvalid || aliasIsTooLong)
      }
    }
    .padding(24)
    .frame(width: 440)
    .onAppear { titleIsFocused = true }
  }

  private func save() {
    guard !isTooLong, !aliasIsInvalid, !aliasIsTooLong else { return }
    failureMessage = onSave(trimmedTitle, alias)
  }
}
